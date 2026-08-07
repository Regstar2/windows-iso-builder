$script:UupApiBaseUri = 'https://api.uupdump.net'
$script:UupWebsiteBaseUri = 'https://uupdump.net'

function ConvertTo-WibQueryString {
    param([Parameter(Mandatory = $true)][hashtable]$Parameters)

    return (($Parameters.GetEnumerator() | Sort-Object Key | ForEach-Object {
        '{0}={1}' -f [Uri]::EscapeDataString([string]$_.Key), [Uri]::EscapeDataString([string]$_.Value)
    }) -join '&')
}

function Get-WibApiErrorText {
    param($ErrorValue)

    if ($null -eq $ErrorValue) {
        return ''
    }
    if ($ErrorValue -is [string]) {
        return $ErrorValue
    }
    try {
        return ($ErrorValue | ConvertTo-Json -Compress -Depth 8)
    }
    catch {
        return [string]$ErrorValue
    }
}

function ConvertFrom-WibApiErrorBody {
    param([AllowNull()][string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return ''
    }

    try {
        $payload = $Body | ConvertFrom-Json
        if ($null -ne $payload.response -and ($payload.response.PSObject.Properties.Name -contains 'error')) {
            return (Get-WibApiErrorText -ErrorValue $payload.response.error)
        }
    }
    catch {
        # Preserve a non-JSON response because it can still contain a useful
        # proxy, CDN or server error message.
    }

    return $Body.Trim()
}

function Get-WibHttpErrorBody {
    param($Exception)

    $current = $Exception
    while ($null -ne $current) {
        $response = $current.Response
        if ($null -ne $response) {
            try {
                if ($null -ne $response.Content) {
                    $task = $response.Content.ReadAsStringAsync()
                    $content = $task.GetAwaiter().GetResult()
                    if (-not [string]::IsNullOrWhiteSpace($content)) {
                        return $content
                    }
                }
            }
            catch {
                # Windows PowerShell uses WebResponse instead of HttpResponseMessage.
            }

            try {
                $stream = $response.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object IO.StreamReader($stream)
                    try {
                        $content = $reader.ReadToEnd()
                        if (-not [string]::IsNullOrWhiteSpace($content)) {
                            return $content
                        }
                    }
                    finally {
                        $reader.Dispose()
                    }
                }
            }
            catch {
                # The response body is optional; the original exception remains useful.
            }
        }
        $current = $current.InnerException
    }
    return ''
}

function ConvertTo-WibApiSearchText {
    param([Parameter(Mandatory = $true)][string]$Search)

    $normalized = ($Search -replace '\s+', ' ').Trim()
    $normalized = [regex]::Replace($normalized, '(?i)\bwindows\s*(10|11)\b', 'Windows $1')
    $normalized = [regex]::Replace($normalized, '(?i)\bwin\s*(10|11)\b', 'Windows $1')
    $normalized = [regex]::Replace($normalized, '(?i)\bwindows\s*server\b', 'Windows Server')
    return $normalized
}

function Get-WibHttpStatusCode {
    param($Exception)

    $current = $Exception
    while ($null -ne $current) {
        try {
            if ($null -ne $current.Response -and $null -ne $current.Response.StatusCode) {
                return [int]$current.Response.StatusCode
            }
        }
        catch {
            # Some PowerShell and .NET combinations expose a response object
            # whose StatusCode cannot be converted. Continue through inner errors.
        }
        $current = $current.InnerException
    }
    return $null
}

function Test-WibRetryableHttpStatusCode {
    param([AllowNull()][Nullable[int]]$StatusCode)

    if ($null -eq $StatusCode) { return $true }
    if ($StatusCode -eq 408 -or $StatusCode -eq 429) { return $true }
    return ($StatusCode -ge 500 -and $StatusCode -le 599)
}

function Invoke-WibApiRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('listid', 'listlangs', 'listeditions', 'updateinfo')][string]$Endpoint,
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][string]$CacheDirectory,
        [int]$CacheHours = 6,
        [switch]$ForceRefresh,
        [int]$Attempts = 4
    )

    $query = ConvertTo-WibQueryString -Parameters $Parameters
    $cacheKey = '{0}?{1}' -f $Endpoint, $query
    $cachePath = Get-WibCachePath -CacheDirectory $CacheDirectory -Category 'api' -Key $cacheKey

    if (-not $ForceRefresh) {
        $cached = Get-WibCachedValue -Path $cachePath -MaximumAgeHours $CacheHours
        if ($null -ne $cached) {
            return $cached
        }
    }

    $uri = '{0}/{1}.php?{2}' -f $script:UupApiBaseUri, $Endpoint, $query
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $lastErrorMessage = ''
    $lastStatusCode = $null
    $lastErrorIsRetryable = $true

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-RestMethod -Method Get -Uri $uri -UseBasicParsing -TimeoutSec 120 -Headers @{
                'User-Agent' = 'WindowsISOBuilder/0.1 (+https://github.com/Regstar2/windows-iso-builder)'
                'Accept'     = 'application/json'
            }

            if ($null -eq $response.response) {
                throw 'Ответ UUP dump API не содержит поле response.'
            }
            if ($response.response.PSObject.Properties.Name -contains 'error') {
                $errorText = Get-WibApiErrorText -ErrorValue $response.response.error
                if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                    throw "UUP dump API: $errorText"
                }
            }

            Save-WibCachedValue -Value $response -Path $cachePath
            return $response
        }
        catch {
            $lastStatusCode = Get-WibHttpStatusCode -Exception $_.Exception
            $errorBody = Get-WibHttpErrorBody -Exception $_.Exception
            $apiErrorText = ConvertFrom-WibApiErrorBody -Body $errorBody
            $lastErrorMessage = if ([string]::IsNullOrWhiteSpace($apiErrorText)) {
                $_.Exception.Message
            }
            else {
                'UUP dump API: {0}' -f $apiErrorText
            }
            $lastErrorIsRetryable = Test-WibRetryableHttpStatusCode -StatusCode $lastStatusCode

            if (-not $lastErrorIsRetryable) {
                break
            }

            if ($attempt -lt $Attempts) {
                $delay = [Math]::Min(5 * $attempt, 20)
                Write-WibWarning "Запрос $Endpoint не выполнен, попытка $attempt/$Attempts. Повтор через $delay с: $lastErrorMessage"
                Start-Sleep -Seconds $delay
            }
        }
    }

    if ($lastErrorIsRetryable) {
        $stale = Get-WibCachedValue -Path $cachePath -MaximumAgeHours 87600 -AllowStale
        if ($null -ne $stale) {
            Write-WibWarning "UUP dump недоступен. Используется устаревший кеш: $cachePath"
            return $stale
        }
    }

    if ($null -ne $lastStatusCode) {
        throw ('Не удалось выполнить запрос UUP dump API {0} (HTTP {1}): {2}' -f $Endpoint, $lastStatusCode, $lastErrorMessage)
    }
    throw ('Не удалось выполнить запрос UUP dump API {0}: {1}' -f $Endpoint, $lastErrorMessage)
}

function ConvertFrom-WibBuildCollection {
    param($Builds)

    if ($null -eq $Builds) {
        return @()
    }

    if ($Builds -is [System.Array]) {
        return @($Builds)
    }

    if ($Builds -is [System.Collections.IEnumerable] -and -not ($Builds -is [string]) -and -not ($Builds -is [pscustomobject])) {
        return @($Builds)
    }

    $properties = @($Builds.PSObject.Properties)
    $looksLikeSingleBuild = ($properties.Name -contains 'title') -and ($properties.Name -contains 'build')
    if ($looksLikeSingleBuild) {
        return @($Builds)
    }

    return @($properties | ForEach-Object {
        $value = $_.Value
        if ($null -ne $value -and -not ($value.PSObject.Properties.Name -contains 'uuid')) {
            $value | Add-Member -NotePropertyName uuid -NotePropertyValue $_.Name -Force
        }
        $value
    })
}

function Test-WibPreviewTitle {
    param([Parameter(Mandatory = $true)][string]$Title)
    return ($Title -match '(?i)insider|preview|canary|dev channel|beta channel|release preview|rs_prerelease|zn_release|ge_release_svc_betaflt')
}

function Get-WibProductLabel {
    param([Parameter(Mandatory = $true)][string]$Title)
    if ($Title -match '(?i)\bWindows\s+Server\b') { return 'Windows Server' }
    if ($Title -match '(?i)\bWindows\s+11\b') { return 'Windows 11' }
    if ($Title -match '(?i)\bWindows\s+10X\b') { return 'Windows 10X' }
    if ($Title -match '(?i)\bWindows\s+10\b') { return 'Windows 10' }
    return 'Windows'
}

function Get-WibRequestedProduct {
    param([Parameter(Mandatory = $true)][string]$Search)

    $normalized = ConvertTo-WibApiSearchText -Search $Search
    if ($normalized -match '(?i)\bWindows\s+Server\b') { return 'Windows Server' }
    if ($normalized -match '(?i)\bWindows\s+11\b') { return 'Windows 11' }
    if ($normalized -match '(?i)\bWindows\s+10\b') { return 'Windows 10' }
    return ''
}

function Test-WibBuildMatchesSearch {
    param(
        [Parameter(Mandatory = $true)][string]$Search,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Build
    )

    $normalized = ConvertTo-WibApiSearchText -Search $Search
    $requestedProduct = Get-WibRequestedProduct -Search $normalized
    if (-not [string]::IsNullOrWhiteSpace($requestedProduct)) {
        $actualProduct = Get-WibProductLabel -Title $Title
        if ($actualProduct -ne $requestedProduct) {
            return $false
        }

        switch ($requestedProduct) {
            'Windows 10' { $normalized = [regex]::Replace($normalized, '(?i)\bWindows\s+10\b', ' ') }
            'Windows 11' { $normalized = [regex]::Replace($normalized, '(?i)\bWindows\s+11\b', ' ') }
            'Windows Server' { $normalized = [regex]::Replace($normalized, '(?i)\bWindows\s+Server\b', ' ') }
        }
    }

    $remainingTerms = @(($normalized -replace '\s+', ' ').Trim() -split ' ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($remainingTerms.Count -eq 0) {
        return $true
    }

    $searchableText = '{0} {1}' -f $Title, $Build
    foreach ($term in $remainingTerms) {
        if ($searchableText.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            return $false
        }
    }
    return $true
}

function Get-WibVersionLabel {
    param([Parameter(Mandatory = $true)][string]$Title)

    # Prefer an explicit Windows release label. Do not infer a release from the
    # numeric OS build because development builds can have a larger build number
    # than a newer generally available release (for example 19564 vs 19045).
    $versionMatch = [regex]::Match($Title, '(?i)\bversion\s+(?<version>\d{2}H[12]|\d{4})\b')
    if ($versionMatch.Success) {
        return $versionMatch.Groups['version'].Value.ToUpperInvariant()
    }

    $halfMatch = [regex]::Match($Title, '(?i)\b(?<version>\d{2}H[12])\b')
    if ($halfMatch.Success) {
        return $halfMatch.Groups['version'].Value.ToUpperInvariant()
    }

    $serverYearMatch = [regex]::Match($Title, '(?i)\bWindows\s+Server\s+(?<version>20\d{2})\b')
    if ($serverYearMatch.Success) {
        return $serverYearMatch.Groups['version'].Value
    }

    return ''
}

function Search-WibBuilds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Search,
        [ValidateSet('amd64', 'arm64', 'x86', 'all')][string]$Architecture = 'all',
        [switch]$IncludePreview,
        [switch]$ForceRefresh,
        [string]$CacheDirectory = (Get-WibDefaultCacheDirectory)
    )

    $cache = Resolve-WibFullPath -Path $CacheDirectory -Create
    $apiSearch = ConvertTo-WibApiSearchText -Search $Search
    try {
        $api = Invoke-WibApiRequest -Endpoint 'listid' -Parameters @{ search = $apiSearch; sortByDate = 1 } -CacheDirectory $cache -CacheHours 6 -ForceRefresh:$ForceRefresh
    }
    catch {
        if ($_.Exception.Message -match 'SEARCH_NO_RESULTS') {
            return @()
        }
        throw
    }
    $items = ConvertFrom-WibBuildCollection -Builds $api.response.builds

    $result = foreach ($item in $items) {
        if ($null -eq $item) { continue }

        $title = [string]$item.title
        $arch = [string]$item.arch
        $build = [string]$item.build
        $uuid = [string]$item.uuid
        $createdSeconds = 0L
        if ($item.PSObject.Properties.Name -contains 'created') {
            [long]::TryParse([string]$item.created, [ref]$createdSeconds) | Out-Null
        }
        $isPreview = Test-WibPreviewTitle -Title $title

        if ($Architecture -ne 'all' -and $arch -ne $Architecture) { continue }
        if (-not $IncludePreview -and $isPreview) { continue }
        if (-not (Test-WibBuildMatchesSearch -Search $apiSearch -Title $title -Build $build)) { continue }

        [pscustomobject]@{
            Uuid         = $uuid
            Title        = $title
            Product      = Get-WibProductLabel -Title $title
            VersionLabel = Get-WibVersionLabel -Title $title
            Build        = $build
            BuildVersion = ConvertTo-WibVersion -Build $build
            Architecture = $arch
            EntryType    = Get-WibBuildEntryType -Title $title
            Created      = $createdSeconds
            CreatedAt    = if ($createdSeconds -gt 0) { Get-WibUnixDate -Seconds $createdSeconds } else { $null }
            IsPreview    = $isPreview
        }
    }

    return @($result | Sort-Object -Property @{ Expression = 'BuildVersion'; Descending = $true }, @{ Expression = 'Created'; Descending = $true })
}

function Get-WibLanguages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$UpdateId,
        [switch]$ForceRefresh,
        [string]$CacheDirectory = (Get-WibDefaultCacheDirectory)
    )

    $cache = Resolve-WibFullPath -Path $CacheDirectory -Create
    $api = Invoke-WibApiRequest -Endpoint 'listlangs' -Parameters @{ id = $UpdateId } -CacheDirectory $cache -CacheHours 24 -ForceRefresh:$ForceRefresh
    $fancy = $api.response.langFancyNames
    if ($null -eq $fancy) { return @() }

    return @($fancy.PSObject.Properties | ForEach-Object {
        [pscustomobject]@{ Code = $_.Name; Name = [string]$_.Value }
    } | Sort-Object Code)
}

function Get-WibEditions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$UpdateId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-z]{2}-[a-z]{2}$')][string]$Language,
        [switch]$ForceRefresh,
        [string]$CacheDirectory = (Get-WibDefaultCacheDirectory)
    )

    $cache = Resolve-WibFullPath -Path $CacheDirectory -Create
    $api = Invoke-WibApiRequest -Endpoint 'listeditions' -Parameters @{ id = $UpdateId; lang = $Language } -CacheDirectory $cache -CacheHours 24 -ForceRefresh:$ForceRefresh
    $fancy = $api.response.editionFancyNames
    if ($null -eq $fancy) { return @() }

    return @($fancy.PSObject.Properties | ForEach-Object {
        [pscustomobject]@{ Code = $_.Name; Name = [string]$_.Value }
    } | Sort-Object Code)
}
