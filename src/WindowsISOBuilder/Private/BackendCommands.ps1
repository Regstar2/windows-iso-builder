function ConvertTo-WibBuildResultDto {
    param([AllowNull()]$Result)
    if ($null -eq $Result) { $Result = [pscustomobject]@{} }
    $stage = [string](Get-WibBackendProperty $Result 'Stage')
    if ([string]::IsNullOrWhiteSpace($stage)) { $stage = 'completed' } else { $stage = ConvertTo-WibContractStage $stage }
    return [pscustomobject][ordered]@{
        stage = $stage
        isoPath = [string](Get-WibBackendProperty $Result 'IsoPath')
        sha256 = [string](Get-WibBackendProperty $Result 'Sha256')
        logPath = [string](Get-WibBackendProperty $Result 'LogPath')
        executionLogPath = [string](Get-WibBackendProperty $Result 'ExecutionLogPath')
        workDirectory = [string](Get-WibBackendProperty $Result 'WorkDirectory')
        metadataPath = [string](Get-WibBackendProperty $Result 'MetadataPath')
    }
}

function ConvertTo-WibBackendErrorDto {
    param($Failure, [string]$Command)
    $exception = if ($Failure -is [System.Management.Automation.ErrorRecord]) { $Failure.Exception } else { $Failure }
    $code = if ($Command -eq 'ExecuteBuildPlan') { 'BUILD_FAILED' } elseif ($Command -eq 'ValidateBuildPlan') { 'INVALID_BUILD_PLAN' } else { 'INTERNAL_ERROR' }
    $stage = if ($Command -in @('SearchBuilds','GetRecommendedBuild')) { 'catalog' } elseif ($Command -in @('GetLanguages','GetEditions')) { 'metadata' } elseif ($Command -in @('CreateBuildPlan','ValidateBuildPlan')) { 'plan' } else { 'startup' }
    $message = if ($null -eq $exception) { 'Backend operation failed.' } else { [string]$exception.Message }
    $logPath = ''; $workDirectory = ''; $executionLogPath = ''
    if ($null -ne $exception) {
        try {
            if ($exception.Data.Contains('WibErrorCode')) { $code = [string]$exception.Data['WibErrorCode'] }
            if ($exception.Data.Contains('WibStage')) { $stage = ConvertTo-WibContractStage ([string]$exception.Data['WibStage']) }
            if ($exception.Data.Contains('WibPublicMessage')) { $message = [string]$exception.Data['WibPublicMessage'] }
            if ($exception.Data.Contains('WibLogPath')) { $logPath = [string]$exception.Data['WibLogPath'] }
            if ($exception.Data.Contains('WibWorkDirectory')) { $workDirectory = [string]$exception.Data['WibWorkDirectory'] }
            if ($exception.Data.Contains('WibExecutionLogPath')) { $executionLogPath = [string]$exception.Data['WibExecutionLogPath'] }
        } catch { }
    }
    $details = $null
    if ($workDirectory -or $executionLogPath) {
        $details = [pscustomobject][ordered]@{
            workDirectory = if ($workDirectory) { $workDirectory } else { $null }
            executionLogPath = if ($executionLogPath) { $executionLogPath } else { $null }
        }
    }
    return [pscustomobject][ordered]@{
        code = $code
        message = $message
        stage = $stage
        details = $details
        logPath = if ($logPath) { $logPath } else { $null }
    }
}

function New-WibBackendResponse {
    param([string]$RequestId, [string]$Command, [bool]$Success, $Payload)
    $response = [ordered]@{
        schemaVersion = $script:WibBackendContractSchemaVersion
        requestId = $RequestId
        command = $Command
        success = $Success
        applicationVersion = $script:WibApplicationVersion
    }
    if ($Success) { $response.data = $Payload } else { $response.error = $Payload }
    return [pscustomobject]$response
}

function Invoke-WibBackendCommand {
    param([string]$Command, $Arguments)
    switch ($Command) {
        'GetVersion' {
            return [pscustomobject][ordered]@{
                applicationVersion = $script:WibApplicationVersion
                contractSchemaVersion = $script:WibBackendContractSchemaVersion
                buildPlanSchemaVersion = $script:WibBuildPlanSchemaVersion
            }
        }
        'SearchBuilds' {
            $search = Get-WibBackendString $Arguments 'search' '' -Required -Stage 'catalog'
            $arch = Get-WibBackendEnum $Arguments 'architecture' @('amd64','arm64','x86','all') 'all' -Stage 'catalog'
            $preview = Get-WibBackendBoolean $Arguments 'includePreview' $false 'INVALID_ARGUMENT' 'catalog'
            $refresh = Get-WibBackendBoolean $Arguments 'forceRefresh' $false 'INVALID_ARGUMENT' 'catalog'
            $cache = Get-WibBackendPath $Arguments 'cacheDirectory' (Get-WibDefaultCacheDirectory) -Stage 'catalog'
            Publish-WibEvent stage catalog 'Searching Windows builds' | Out-Null
            return [pscustomobject][ordered]@{
                builds = @(Search-WibBuilds -Search $search -Architecture $arch -IncludePreview:$preview -ForceRefresh:$refresh -CacheDirectory $cache |
                    ForEach-Object { ConvertTo-WibBuildDto $_ })
            }
        }
        'GetRecommendedBuild' {
            $product = Get-WibBackendEnum $Arguments 'product' @('Windows 11','Windows 10') '' -Required -Stage 'catalog'
            $arch = Get-WibBackendEnum $Arguments 'architecture' @('amd64','arm64','x86') 'amd64' -Stage 'catalog'
            $refresh = Get-WibBackendBoolean $Arguments 'forceRefresh' $true 'INVALID_ARGUMENT' 'catalog'
            $cache = Get-WibBackendPath $Arguments 'cacheDirectory' (Get-WibDefaultCacheDirectory) -Stage 'catalog'
            Publish-WibEvent stage catalog 'Selecting recommended Windows build' | Out-Null
            return [pscustomobject][ordered]@{
                build = ConvertTo-WibBuildDto (Get-WibQuickLatestBuild -Product $product -Architecture $arch -ForceRefresh:$refresh -CacheDirectory $cache)
            }
        }
        'GetLanguages' {
            $id = Get-WibBackendString $Arguments 'updateId' '' -Required -Stage 'metadata'
            $refresh = Get-WibBackendBoolean $Arguments 'forceRefresh' $false 'INVALID_ARGUMENT' 'metadata'
            $cache = Get-WibBackendPath $Arguments 'cacheDirectory' (Get-WibDefaultCacheDirectory) -Stage 'metadata'
            Publish-WibEvent stage metadata 'Loading languages' | Out-Null
            $values = @(Get-WibLanguages -UpdateId $id -ForceRefresh:$refresh -CacheDirectory $cache)
            if ($values.Count -eq 0) { Throw-WibBackendError 'LANGUAGE_NOT_FOUND' 'No languages are available for the selected build.' 'metadata' }
            return [pscustomobject][ordered]@{ languages = @($values | ForEach-Object { ConvertTo-WibLanguageDto $_ }) }
        }
        'GetEditions' {
            $id = Get-WibBackendString $Arguments 'updateId' '' -Required -Stage 'metadata'
            $language = Get-WibBackendLanguage $Arguments
            $refresh = Get-WibBackendBoolean $Arguments 'forceRefresh' $false 'INVALID_ARGUMENT' 'metadata'
            $cache = Get-WibBackendPath $Arguments 'cacheDirectory' (Get-WibDefaultCacheDirectory) -Stage 'metadata'
            Publish-WibEvent stage metadata 'Loading editions' | Out-Null
            $values = @(Get-WibEditions -UpdateId $id -Language $language -ForceRefresh:$refresh -CacheDirectory $cache)
            if ($values.Count -eq 0) { Throw-WibBackendError 'EDITION_NOT_FOUND' 'No editions are available for the selected build and language.' 'metadata' }
            return [pscustomobject][ordered]@{ editions = @($values | ForEach-Object { ConvertTo-WibEditionDto $_ }) }
        }
        'CreateBuildPlan' {
            Publish-WibEvent stage plan 'Creating build plan' | Out-Null
            $build = ConvertFrom-WibBuildDto (Get-WibBackendProperty $Arguments 'build')
            $language = Get-WibBackendLanguage $Arguments 'language' 'INVALID_ARGUMENT' 'plan'
            $editions = Get-WibBackendStringArray $Arguments 'editions'
            $format = Get-WibBackendEnum $Arguments 'imageFormat' @('WIM','ESD') 'ESD' -Stage 'plan'
            $updates = Get-WibBackendBoolean $Arguments 'addUpdates' $true 'INVALID_ARGUMENT' 'plan'
            $cleanup = Get-WibBackendBoolean $Arguments 'cleanup' $true 'INVALID_ARGUMENT' 'plan'
            $netfx = Get-WibBackendBoolean $Arguments 'netFx3' $false 'INVALID_ARGUMENT' 'plan'
            $output = Get-WibBackendPath $Arguments 'outputDirectory' '' -Required -Stage 'plan'
            $cache = Get-WibBackendPath $Arguments 'cacheDirectory' '' -Required -Stage 'plan'
            return [pscustomobject][ordered]@{
                plan = ConvertTo-WibBuildPlanDto (New-WibBuildPlan -Build $build -Language $language -Editions $editions -ImageFormat $format -AddUpdates $updates -Cleanup $cleanup -NetFx3 $netfx -OutputDirectory $output -CacheDirectory $cache)
            }
        }
        'ValidateBuildPlan' {
            Publish-WibEvent stage plan 'Validating build plan' | Out-Null
            $plan = ConvertFrom-WibBuildPlanDto (Get-WibBackendProperty $Arguments 'plan')
            Assert-WibPlan $plan
            return [pscustomobject][ordered]@{ valid = $true }
        }
        'ExecuteBuildPlan' {
            Publish-WibEvent stage plan 'Preparing build plan' | Out-Null
            $plan = ConvertFrom-WibBuildPlanDto (Get-WibBackendProperty $Arguments 'plan')
            Assert-WibPlan $plan
            Publish-WibEvent stage preflight 'Starting build' | Out-Null
            try { $result = Invoke-WibBuildPlan $plan }
            catch {
                if (-not $_.Exception.Data.Contains('WibErrorCode')) { $_.Exception.Data['WibErrorCode'] = 'BUILD_FAILED' }
                throw
            }
            return ConvertTo-WibBuildResultDto $result
        }
        default { Throw-WibBackendError 'INVALID_COMMAND' ("Unknown backend command: {0}" -f $Command) 'startup' }
    }
}

function Invoke-WibBackendRequestObject {
    param([Parameter(Mandatory = $true)]$Request)
    if (-not (Test-WibBackendObject $Request)) { Throw-WibBackendError 'INVALID_REQUEST' 'Backend request must be a JSON object.' 'startup' }
    $schema = Get-WibBackendProperty $Request 'schemaVersion'
    if (-not (Test-WibBackendInteger $schema)) { Throw-WibBackendError 'INVALID_REQUEST' 'schemaVersion is required and must be an integer.' 'startup' }
    if ([int64]$schema -ne $script:WibBackendContractSchemaVersion) { Throw-WibBackendError 'UNSUPPORTED_SCHEMA' ("Unsupported backend contract schemaVersion: {0}" -f $schema) 'startup' }
    $requestId = Get-WibBackendString $Request 'requestId' '' -Required -Code 'INVALID_REQUEST'
    $command = Get-WibBackendString $Request 'command' '' -Required -Code 'INVALID_REQUEST'
    if ($script:WibBackendCommands -notcontains $command) { Throw-WibBackendError 'INVALID_COMMAND' ("Unknown backend command: {0}" -f $command) 'startup' }
    $arguments = Get-WibBackendProperty $Request 'arguments'
    if (-not (Test-WibBackendObject $arguments)) { Throw-WibBackendError 'INVALID_REQUEST' 'arguments is required and must be an object.' 'startup' }
    return New-WibBackendResponse $requestId $command $true (Invoke-WibBackendCommand $command $arguments)
}

function Invoke-WibBackendRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RequestFile,
        [Parameter(Mandatory = $true)][string]$ResponseFile,
        [string]$EventFile = ''
    )
    $requestId = ''
    $command = ''
    $response = $null
    $events = $false
    try {
        if (-not (Test-Path -LiteralPath $RequestFile)) { Throw-WibBackendError 'INVALID_REQUEST' 'Request file does not exist.' 'startup' }
        try { $request = Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Throw-WibBackendError 'INVALID_REQUEST' 'Request file is not valid UTF-8 JSON.' 'startup' }
        $idValue = Get-WibBackendProperty $request 'requestId'
        if ($idValue -is [string]) { $requestId = [string]$idValue }
        $commandValue = Get-WibBackendProperty $request 'command'
        if ($commandValue -is [string]) { $command = [string]$commandValue }
        if ($EventFile -and $requestId) {
            $events = Initialize-WibEventSink -RequestId $requestId -EventFile $EventFile
            if ($events) { Publish-WibEvent stage startup 'Backend request started' -Percent 0 | Out-Null }
        }
        $response = Invoke-WibBackendRequestObject $request
        if ($events) {
            Sync-WibEventSequenceFromFile
            Publish-WibEvent completed completed 'Backend request completed' -Percent 100 | Out-Null
        }
    }
    catch {
        $error = ConvertTo-WibBackendErrorDto $_ $command
        $response = New-WibBackendResponse $requestId $command $false $error
        if ($events) {
            Sync-WibEventSequenceFromFile
            Publish-WibEvent failed $error.stage $error.message | Out-Null
        }
    }
    finally {
        if ($null -eq $response) {
            $fallback = New-WibErrorException -Code 'INTERNAL_ERROR' -Message 'Backend did not produce a response.' -Stage 'startup'
            $response = New-WibBackendResponse $requestId $command $false (ConvertTo-WibBackendErrorDto $fallback $command)
        }
        Write-WibJsonFile -Value $response -Path $ResponseFile -Depth 30
        Reset-WibEventSink
    }
    return $response
}
