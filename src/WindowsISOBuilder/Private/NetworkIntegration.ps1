# v0.3.4 network integration overrides. These definitions intentionally load
# after the legacy implementation so every runtime outbound path resolves to the
# global Network Policy layer without changing BuildPlan v1.

function Get-WibHttpErrorBody {
    param($Exception)

    $current = $Exception
    while ($null -ne $current) {
        try {
            if ($current.Data.Contains('WibHttpErrorBody')) {
                $body = [string]$current.Data['WibHttpErrorBody']
                if (-not [string]::IsNullOrWhiteSpace($body)) { return $body }
            }
        }
        catch { }
        $response = $current.Response
        if ($null -ne $response) {
            try {
                if ($null -ne $response.Content) {
                    $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    if (-not [string]::IsNullOrWhiteSpace($content)) { return $content }
                }
            }
            catch { }
            try {
                $stream = $response.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object IO.StreamReader($stream)
                    try {
                        $content = $reader.ReadToEnd()
                        if (-not [string]::IsNullOrWhiteSpace($content)) { return $content }
                    }
                    finally { $reader.Dispose() }
                }
            }
            catch { }
        }
        $current = $current.InnerException
    }
    return ''
}

function Get-WibHttpStatusCode {
    param($Exception)

    $current = $Exception
    while ($null -ne $current) {
        try {
            if ($current.Data.Contains('WibHttpStatusCode')) { return [int]$current.Data['WibHttpStatusCode'] }
        }
        catch { }
        try {
            if ($null -ne $current.Response -and $null -ne $current.Response.StatusCode) { return [int]$current.Response.StatusCode }
        }
        catch { }
        $current = $current.InnerException
    }
    return $null
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
        if ($null -ne $cached) { return $cached }
    }

    $uri = '{0}/{1}.php?{2}' -f $script:UupApiBaseUri, $Endpoint, $query
    $lastErrorMessage = ''
    $lastStatusCode = $null
    $lastErrorIsRetryable = $true
    $lastApiErrorCode = ''

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-WibHttpJsonRequest -Uri $uri -Method GET -TimeoutSeconds 120 -Headers @{
                'User-Agent'=('WindowsISOBuilder/{0} (+https://github.com/Regstar2/windows-iso-builder)' -f $script:WibApplicationVersion)
                'Accept'='application/json'
            }
            if ($null -eq $response.response) { throw 'UUP dump API response has no response field.' }
            if ($response.response.PSObject.Properties.Name -contains 'error') {
                $errorText = Get-WibApiErrorText -ErrorValue $response.response.error
                if (-not [string]::IsNullOrWhiteSpace($errorText)) { throw ('UUP dump API: {0}' -f $errorText) }
            }
            Save-WibCachedValue -Value $response -Path $cachePath
            return $response
        }
        catch {
            $knownCode = ''
            try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
            if ($knownCode -like 'PROXY_*') { throw }

            $lastStatusCode = Get-WibHttpStatusCode -Exception $_.Exception
            $errorBody = Get-WibHttpErrorBody -Exception $_.Exception
            $apiErrorText = ConvertFrom-WibApiErrorBody -Body $errorBody
            if (-not [string]::IsNullOrWhiteSpace($apiErrorText)) { $lastApiErrorCode = $apiErrorText }
            $lastErrorMessage = if ([string]::IsNullOrWhiteSpace($apiErrorText)) { $_.Exception.Message } else { 'UUP dump API: {0}' -f $apiErrorText }
            $lastErrorIsRetryable = Test-WibRetryableHttpStatusCode -StatusCode $lastStatusCode
            if (-not $lastErrorIsRetryable) { break }
            if ($attempt -lt $Attempts) {
                $delay = [Math]::Min(5 * $attempt, 20)
                Write-WibWarning ('UUP API request {0} failed, attempt {1}/{2}; retrying in {3}s.' -f $Endpoint, $attempt, $Attempts, $delay)
                Wait-WibCancellableDelay -Seconds $delay -Stage 'metadata'
            }
        }
    }

    if ($lastErrorIsRetryable) {
        $stale = Get-WibCachedValue -Path $cachePath -MaximumAgeHours 87600 -AllowStale
        if ($null -ne $stale) {
            Write-WibWarning ('UUP dump is unavailable. Using stale cache: {0}' -f $cachePath)
            return $stale
        }
    }

    $stage = if ($Endpoint -eq 'listid') { 'catalog' } else { 'metadata' }
    $code = if ($lastErrorIsRetryable) { 'UUP_API_UNAVAILABLE' } else { 'UUP_API_ERROR' }
    $message = if ($null -ne $lastStatusCode) {
        'UUP dump API request {0} failed (HTTP {1}): {2}' -f $Endpoint, $lastStatusCode, $lastErrorMessage
    } else {
        'UUP dump API request {0} failed: {1}' -f $Endpoint, $lastErrorMessage
    }
    $exception = New-WibErrorException -Code $code -Message $message -Stage $stage
    if (-not [string]::IsNullOrWhiteSpace($lastApiErrorCode)) { $exception.Data['WibUupApiError'] = $lastApiErrorCode }
    throw $exception
}

function Test-WibUupApiAvailability {
    param([int]$TimeoutSeconds = 10)

    $uri = '{0}/listid.php?search=Windows%2011&sortByDate=1' -f $script:UupApiBaseUri
    try {
        $response = Invoke-WibHttpJsonRequest -Uri $uri -Method GET -TimeoutSeconds $TimeoutSeconds -Headers @{
            'User-Agent'=('WindowsISOBuilder/{0} preflight' -f $script:WibApplicationVersion)
            'Accept'='application/json'
        }
        if ($null -eq $response -or $null -eq $response.response) { throw 'UUP dump API returned an unexpected response.' }
        $policy = Get-WibNetworkPolicy
        return [pscustomobject]@{ Available=$true; Uri=$script:UupApiBaseUri; StatusCode=200; Message='Official UUP dump API is reachable.'; Mode=[string]$policy.mode }
    }
    catch {
        $knownCode = ''
        try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
        $statusCode = Get-WibHttpStatusCode -Exception $_.Exception
        return [pscustomobject]@{ Available=$false; Uri=$script:UupApiBaseUri; StatusCode=$statusCode; Message='Official UUP dump API is not reachable.'; Code=$knownCode }
    }
}

function Download-WibUupPackage {
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)][string]$DestinationZip, [int]$Attempts = 3)

    Assert-WibNotCancelled -Stage 'download'
    if (Test-Path -LiteralPath $DestinationZip) {
        $existing = Test-WibUupPackageArchive -Path $DestinationZip
        if ($existing.IsValid) { Write-WibInfo ('Using cached UUP dump package: {0}' -f $DestinationZip); return }
        Remove-Item -LiteralPath $DestinationZip -Force
    }

    $query = ConvertTo-WibQueryString -Parameters @{ id=[string]$Plan.Build.Uuid; pack=[string]$Plan.Language; edition=[string]$Plan.SourceEdition }
    $uri = '{0}/get.php?{1}' -f $script:UupWebsiteBaseUri, $query
    $body = @{
        autodl=2
        updates=if ([bool]$Plan.AddUpdates) { 1 } else { 0 }
        cleanup=if ([bool]$Plan.Cleanup) { 1 } else { 0 }
        netfx=if ([bool]$Plan.NetFx3) { 1 } else { 0 }
        esd=if ([string]$Plan.ImageFormat -eq 'ESD') { 1 } else { 0 }
    }
    $invalidPath = "$DestinationZip.response.html"
    $lastReason = ''

    for ($attempt=1; $attempt -le $Attempts; $attempt++) {
        Assert-WibNotCancelled -Stage 'download'
        Remove-Item -LiteralPath $DestinationZip -Force -ErrorAction SilentlyContinue
        Write-WibInfo ('Downloading UUP dump conversion package, attempt {0}/{1}' -f $attempt, $Attempts)
        try {
            Invoke-WibHttpDownload -Method POST -Uri $uri -FormBody $body -OutFile $DestinationZip -TimeoutSeconds 300 -Headers @{
                'User-Agent'=('Mozilla/5.0 WindowsISOBuilder/{0}' -f $script:WibApplicationVersion)
            }
        }
        catch {
            $knownCode = ''
            try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
            if ($knownCode -like 'PROXY_*') { throw }
            $lastReason = $_.Exception.Message
            if ($attempt -lt $Attempts) {
                Wait-WibCancellableDelay -Seconds (5 * $attempt) -Stage 'download'
                continue
            }
            throw (New-WibErrorException -Code 'UUP_PACKAGE_DOWNLOAD_FAILED' -Message 'UUP dump conversion package could not be downloaded.' -Stage 'download' -PublicMessage 'The UUP conversion package could not be downloaded.' -Details ([ordered]@{ attempts=$Attempts }))
        }

        Assert-WibNotCancelled -Stage 'download'
        $validation = Test-WibUupPackageArchive -Path $DestinationZip
        if ($validation.IsValid) { Write-WibInfo ('Received valid conversion package: {0} bytes.' -f (Get-Item -LiteralPath $DestinationZip).Length); return }
        $lastReason = $validation.Reason
        Remove-Item -LiteralPath $invalidPath -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $DestinationZip -Destination $invalidPath -Force
        if ($attempt -lt $Attempts) { Wait-WibCancellableDelay -Seconds (5 * $attempt) -Stage 'download' }
    }

    $preview = Get-WibResponsePreview -Path $invalidPath
    $internal = 'UUP dump returned an invalid ZIP. Reason: {0}. Response: {1}' -f $lastReason, $preview
    throw (New-WibErrorException -Code 'UUP_PACKAGE_INVALID' -Message $internal -Stage 'download' -PublicMessage 'UUP dump returned an invalid conversion package.')
}

function Invoke-WibUupDownloadScript {
    param([Parameter(Mandatory = $true)][string]$PackageDirectory, [Parameter(Mandatory = $true)][string]$ScriptName)

    $commandProcessor = $env:ComSpec
    if ([string]::IsNullOrWhiteSpace($commandProcessor)) {
        $command = Get-Command cmd.exe -ErrorAction SilentlyContinue
        if ($command) { $commandProcessor = $command.Source }
    }
    if ([string]::IsNullOrWhiteSpace($commandProcessor)) {
        throw (New-WibErrorException -Code 'REQUIRED_COMPONENT_MISSING' -Message 'cmd.exe is unavailable.' -Stage 'download' -Details ([ordered]@{ component='cmd.exe' }))
    }

    $policy = Get-WibNetworkPolicy
    $bridge = $null
    try {
        if ($policy.mode -ne 'direct') { $bridge = Start-WibNetworkProxyBridge -Policy $policy }
        $environmentPrefix = Get-WibManagedDownloadProxyPrefix -Policy $policy -Bridge $bridge
        $safeScriptName = $ScriptName.Replace('"', '""')
        $arguments = '/D /C {0} & call "{1}"' -f $environmentPrefix, $safeScriptName
        $lineHandler = { param($line) Write-Host $line }
        $stageProvider = {
            if (Get-Command Get-WibConverterCurrentStage -ErrorAction SilentlyContinue) { return (Get-WibConverterCurrentStage) }
            return 'download'
        }
        try {
            $result = Invoke-WibManagedProcess -FilePath $commandProcessor -ArgumentList $arguments -WorkingDirectory $PackageDirectory -Stage 'download' -LineHandler $lineHandler -StageProvider $stageProvider
        }
        catch {
            $knownCode = ''
            try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
            if (-not [string]::IsNullOrWhiteSpace($knownCode)) { throw }
            $code = if ($policy.mode -eq 'custom') { 'PROXY_CONNECTION_FAILED' } else { 'DOWNLOAD_FAILED' }
            $public = if ($policy.mode -eq 'custom') { 'The configured custom proxy could not complete the download.' } else { 'The UUP download process could not be started or monitored.' }
            throw (New-WibErrorException -Code $code -Message 'UUP download/conversion process failed to start or run.' -Stage 'download' -PublicMessage $public)
        }
        return [int]$result.ExitCode
    }
    finally {
        if ($null -ne $bridge) { try { $bridge.Dispose() } catch { } }
    }
}
