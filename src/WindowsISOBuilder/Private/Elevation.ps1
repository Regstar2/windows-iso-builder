function Get-WibPlanWorkDirectory {
    param([Parameter(Mandatory = $true)]$Plan)

    $cacheDirectory = Resolve-WibFullPath -Path ([string]$Plan.CacheDirectory) -Create
    $jobKey = '{0}-{1}-{2}' -f $Plan.Build.Uuid, $Plan.Language, $Plan.SourceEdition
    $jobHash = (Get-WibSha256Text -Text $jobKey).Substring(0, 16)
    return (Join-Path (Join-Path $cacheDirectory 'work') $jobHash)
}

function Get-WibExecutionContext {
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)][datetime]$StartedAt)

    $workDirectory = Get-WibPlanWorkDirectory -Plan $Plan
    $statePath = Join-Path $workDirectory 'state.json'
    $stage = 'preflight'
    if (Test-Path -LiteralPath $statePath) {
        try {
            $state = Read-WibJsonFile -Path $statePath
            $updatedAt = [datetime]::MinValue
            if ($null -ne $state -and $null -ne $state.PSObject.Properties['updatedAt']) {
                [datetime]::TryParse([string]$state.updatedAt, [ref]$updatedAt) | Out-Null
            }
            if ($updatedAt -ge $StartedAt.AddSeconds(-2)) {
                if ($null -ne $state.PSObject.Properties['failedStage'] -and -not [string]::IsNullOrWhiteSpace([string]$state.failedStage)) { $stage = [string]$state.failedStage }
                elseif ($null -ne $state.PSObject.Properties['stage'] -and -not [string]::IsNullOrWhiteSpace([string]$state.stage)) { $stage = [string]$state.stage }
            }
        }
        catch { }
    }

    $logPath = ''
    try {
        $logsDirectory = Join-Path ([string]$Plan.OutputDirectory) 'logs'
        if (Test-Path -LiteralPath $logsDirectory) {
            $latestLog = Get-ChildItem -LiteralPath $logsDirectory -Filter 'build-*.log' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $StartedAt.AddSeconds(-2) } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($null -ne $latestLog) { $logPath = $latestLog.FullName }
        }
    }
    catch { }

    return [pscustomobject]@{ Stage=$stage; LogPath=$logPath; WorkDirectory=$workDirectory }
}

# Preserve the previous concrete stage and publish contract stages from the
# existing job-state transitions. Event publishing is best-effort and non-fatal.
function Save-WibJobState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)]$Plan,
        [string]$Message = ''
    )

    $failedStage = ''
    if ($Stage -eq 'failed' -and (Test-Path -LiteralPath $Path)) {
        try {
            $previous = Read-WibJsonFile -Path $Path
            if ($null -ne $previous -and $null -ne $previous.PSObject.Properties['stage']) {
                $previousStage = [string]$previous.stage
                if (-not [string]::IsNullOrWhiteSpace($previousStage) -and $previousStage -ne 'failed') { $failedStage = $previousStage }
            }
        }
        catch { }
    }

    $payload = [ordered]@{ stage=$Stage; updatedAt=(Get-Date).ToString('o'); message=$Message; plan=$Plan }
    if (-not [string]::IsNullOrWhiteSpace($failedStage)) { $payload['failedStage'] = $failedStage }
    Write-WibJsonFile -Path $Path -Depth 20 -Value $payload

    if ($Stage -notin @('failed', 'completed')) {
        $contractStage = ConvertTo-WibContractStage -Stage $Stage
        Publish-WibEvent -Type 'stage' -Stage $contractStage -Message ("Build stage: {0}" -f $contractStage) | Out-Null
    }
}

$script:WibOriginalInvokeBuildPlanCore = ${function:Invoke-WibBuildPlanCore}

function Invoke-WibBuildPlanCore {
    param([Parameter(Mandatory = $true)]$Plan)

    $startedAt = Get-Date
    try {
        $result = & $script:WibOriginalInvokeBuildPlanCore -Plan $Plan
        if ($null -ne $result) {
            $workDirectory = Get-WibPlanWorkDirectory -Plan $Plan
            $result | Add-Member -NotePropertyName Stage -NotePropertyValue 'completed' -Force
            $result | Add-Member -NotePropertyName WorkDirectory -NotePropertyValue $workDirectory -Force
        }
        return $result
    }
    catch {
        $failure = $_
        $context = [pscustomobject]@{ Stage='preflight'; LogPath=''; WorkDirectory='' }
        try { $context = Get-WibExecutionContext -Plan $Plan -StartedAt $startedAt } catch { }
        try { if (-not $failure.Exception.Data.Contains('WibErrorCode')) { $failure.Exception.Data['WibErrorCode'] = 'BUILD_FAILED' } } catch { }
        try { $failure.Exception.Data['WibStage'] = [string]$context.Stage } catch { }
        try { $failure.Exception.Data['WibLogPath'] = [string]$context.LogPath } catch { }
        try { $failure.Exception.Data['WibWorkDirectory'] = [string]$context.WorkDirectory } catch { }
        throw $failure
    }
}

function Get-WibResultPropertyText {
    param([Parameter(Mandatory = $true)]$Result, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Result.PSObject.Properties[$Name]) { return '' }
    return [string]$Result.$Name
}

function Format-WibElevatedFailure {
    param([Parameter(Mandatory = $true)]$Result, [Parameter(Mandatory = $true)][int]$ExitCode)

    $stageValue = Get-WibResultPropertyText $Result 'stage'
    $messageValue = Get-WibResultPropertyText $Result 'message'
    $logPath = Get-WibResultPropertyText $Result 'logPath'
    $executionLogPath = Get-WibResultPropertyText $Result 'executionLogPath'
    $workDirectory = Get-WibResultPropertyText $Result 'workDirectory'
    $isoPath = Get-WibResultPropertyText $Result 'isoPath'
    $stackTrace = Get-WibResultPropertyText $Result 'stackTrace'
    $stage = if ([string]::IsNullOrWhiteSpace($stageValue)) { 'unknown' } else { $stageValue }
    $message = if ([string]::IsNullOrWhiteSpace($messageValue)) { "Повышенный процесс завершился с кодом $ExitCode." } else { $messageValue }
    $lines = @('Сборка с правами администратора завершилась ошибкой.', ('Этап: {0}' -f $stage), ('Причина: {0}' -f $message))
    if ($logPath) { $lines += ('Лог сборки: {0}' -f $logPath) }
    if ($executionLogPath) { $lines += ('Лог выполнения: {0}' -f $executionLogPath) }
    if ($workDirectory) { $lines += ('Рабочий каталог: {0}' -f $workDirectory) }
    if ($isoPath) { $lines += ('ISO: {0}' -f $isoPath) }
    if ($stackTrace) { $lines += 'Стек ошибки:'; $lines += $stackTrace }
    return ($lines -join [Environment]::NewLine)
}

function New-WibElevationException {
    param(
        [string]$Code,
        [string]$Message,
        [string]$PublicMessage,
        [string]$Stage = 'preflight',
        [string]$LogPath = '',
        [string]$ExecutionLogPath = '',
        [string]$WorkDirectory = ''
    )
    $exception = New-WibErrorException -Code $Code -Message $Message -Stage $Stage -PublicMessage $PublicMessage -LogPath $LogPath -WorkDirectory $WorkDirectory
    if ($ExecutionLogPath) { $exception.Data['WibExecutionLogPath'] = $ExecutionLogPath }
    return $exception
}

# Extends the existing elevated plan/result protocol with optional event context.
function Start-WibElevatedPlan {
    param([Parameter(Mandatory = $true)]$Plan)

    $plansDirectory = Join-Path ([string]$Plan.CacheDirectory) 'plans'
    New-Item -ItemType Directory -Path $plansDirectory -Force | Out-Null
    $operationId = [Guid]::NewGuid().ToString('N')
    $planPath = Join-Path $plansDirectory ('plan-{0}.json' -f $operationId)
    $resultPath = Join-Path $plansDirectory ('result-{0}.json' -f $operationId)
    Save-WibPlan -Plan $Plan -Path $planPath

    $executionLogsDirectory = Join-Path $script:ProjectRoot 'logs'
    New-Item -ItemType Directory -Path $executionLogsDirectory -Force | Out-Null
    $elevatedExecutionLogPath = Join-Path $executionLogsDirectory ('elevated-{0}.log' -f $operationId)

    $entryScript = Join-Path $script:ProjectRoot 'Start-Builder.ps1'
    $arguments = @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-WibCommandArgument $entryScript),
        '-PlanFile',(Quote-WibCommandArgument $planPath),
        '-ResultFile',(Quote-WibCommandArgument $resultPath),
        '-ExecutionLogFile',(Quote-WibCommandArgument $elevatedExecutionLogPath)
    )
    $eventContext = Get-WibEventSinkContext
    if ($eventContext.Enabled -and $eventContext.RequestId -and $eventContext.FilePath) {
        $arguments += @('-BackendRequestId',(Quote-WibCommandArgument $eventContext.RequestId),'-BackendEventFile',(Quote-WibCommandArgument $eventContext.FilePath))
    }

    Write-Host 'Для загрузки и конвертации UUP требуются права администратора. Открывается UAC...' -ForegroundColor Yellow
    Write-Host ('Лог повышенного процесса: {0}' -f $elevatedExecutionLogPath) -ForegroundColor DarkGray
    try {
        try {
            $process = Start-Process -FilePath (Get-WibPowerShellExecutable) -Verb RunAs -Wait -PassThru -ArgumentList $arguments
        }
        catch {
            $publicMessage = "Не удалось запустить сборку с правами администратора: $($_.Exception.Message)"
            $fullMessage = "$publicMessage. Лог выполнения: $elevatedExecutionLogPath"
            throw (New-WibElevationException 'ELEVATION_FAILED' $fullMessage $publicMessage 'preflight' '' $elevatedExecutionLogPath '')
        }
        Sync-WibEventSequenceFromFile

        $result = $null
        if (Test-Path -LiteralPath $resultPath) {
            try { $result = Read-WibJsonFile -Path $resultPath }
            catch {
                $message = "Повышенный процесс завершился с кодом $($process.ExitCode), но файл результата повреждён: $resultPath. $($_.Exception.Message). Лог выполнения: $elevatedExecutionLogPath"
                throw (New-WibElevationException 'ELEVATION_FAILED' $message 'Elevated result file is invalid.' 'preflight' '' $elevatedExecutionLogPath '')
            }
        }
        if ($null -eq $result) {
            $message = "Повышенный процесс завершился с кодом $($process.ExitCode), но не создал файл результата: $resultPath. Лог выполнения: $elevatedExecutionLogPath"
            throw (New-WibElevationException 'ELEVATION_FAILED' $message 'Elevated process did not return a result.' 'preflight' '' $elevatedExecutionLogPath '')
        }

        $success = $false
        if ($null -ne $result.PSObject.Properties['success']) { $success = [bool]$result.success }
        if ($process.ExitCode -ne 0 -or -not $success) {
            $fullMessage = Format-WibElevatedFailure -Result $result -ExitCode $process.ExitCode
            $errorCode = Get-WibResultPropertyText $result 'errorCode'
            if ([string]::IsNullOrWhiteSpace($errorCode)) { $errorCode = 'BUILD_FAILED' }
            $stage = Get-WibResultPropertyText $result 'stage'
            if ([string]::IsNullOrWhiteSpace($stage)) { $stage = 'preflight' }
            $publicMessage = Get-WibResultPropertyText $result 'message'
            if ([string]::IsNullOrWhiteSpace($publicMessage)) { $publicMessage = 'Elevated build failed.' }
            throw (New-WibElevationException $errorCode $fullMessage $publicMessage $stage (Get-WibResultPropertyText $result 'logPath') (Get-WibResultPropertyText $result 'executionLogPath') (Get-WibResultPropertyText $result 'workDirectory'))
        }
        return $result
    }
    finally {
        Sync-WibEventSequenceFromFile
        Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    }
}

# The child process uses the same BuildPlan executor and only appends events to
# the parent's EventFile. This is not a second elevation protocol.
function Invoke-WibPlanFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$BackendRequestId = '',
        [string]$BackendEventFile = ''
    )
    $ownsEventSink = $false
    try {
        if ($BackendRequestId -and $BackendEventFile) {
            $ownsEventSink = Initialize-WibEventSink -RequestId $BackendRequestId -EventFile $BackendEventFile -Append
        }
        $plan = Read-WibPlan -Path $Path
        return Invoke-WibBuildPlan -Plan $plan
    }
    finally {
        if ($ownsEventSink) { Reset-WibEventSink }
    }
}
