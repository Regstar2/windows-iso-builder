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
    $lastError = $null

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
            $lastError = $_
            if ($attempt -lt $Attempts) {
                $delay = [Math]::Min(5 * $attempt, 20)
                Write-WibWarning "Запрос $Endpoint не выполнен, попытка $attempt/$Attempts. Повтор через $delay с: $($_.Exception.Message)"
                Start-Sleep -Seconds $delay
            }
        }
    }

    $stale = Get-WibCachedValue -Path $cachePath -MaximumAgeHours 87600 -AllowStale
    if ($null -ne $stale) {
        Write-WibWarning "UUP dump недоступен. Используется устаревший кеш: $cachePath"
        return $stale
    }

    throw "Не удалось выполнить запрос UUP dump API $Endpoint: $($lastError.Exception.Message)"
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
    if ($Title -match '(?i)Windows 11') { return 'Windows 11' }
    if ($Title -match '(?i)Windows 10') { return 'Windows 10' }
    if ($Title -match '(?i)Windows Server') { return 'Windows Server' }
    return 'Windows'
}

function Get-WibVersionLabel {
    param([Parameter(Mandatory = $true)][string]$Title)
    $match = [regex]::Match($Title, '(?i)\b\d{2}H[12]\b')
    if ($match.Success) {
        return $match.Value.ToUpperInvariant()
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
    try {
        $api = Invoke-WibApiRequest -Endpoint 'listid' -Parameters @{ search = $Search; sortByDate = 1 } -CacheDirectory $cache -CacheHours 6 -ForceRefresh:$ForceRefresh
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

        [pscustomobject]@{
            Uuid         = $uuid
            Title        = $title
            Product      = Get-WibProductLabel -Title $title
            VersionLabel = Get-WibVersionLabel -Title $title
            Build        = $build
            BuildVersion = ConvertTo-WibVersion -Build $build
            Architecture = $arch
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
