function Get-WibPlanWorkDirectory {
    param([Parameter(Mandatory = $true)]$Plan)

    $cacheDirectory = Resolve-WibFullPath -Path ([string]$Plan.CacheDirectory) -Create
    $jobKey = '{0}-{1}-{2}' -f $Plan.Build.Uuid, $Plan.Language, $Plan.SourceEdition
    $jobHash = (Get-WibSha256Text -Text $jobKey).Substring(0, 16)
    return (Join-Path (Join-Path $cacheDirectory 'work') $jobHash)
}

function Get-WibExecutionContext {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][datetime]$StartedAt
    )

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
                if ($null -ne $state.PSObject.Properties['failedStage'] -and -not [string]::IsNullOrWhiteSpace([string]$state.failedStage)) {
                    $stage = [string]$state.failedStage
                }
                elseif ($null -ne $state.PSObject.Properties['stage'] -and -not [string]::IsNullOrWhiteSpace([string]$state.stage)) {
                    $stage = [string]$state.stage
                }
            }
        }
        catch {
            # Context collection must never hide the original build failure.
        }
    }

    $logPath = ''
    try {
        $logsDirectory = Join-Path ([string]$Plan.OutputDirectory) 'logs'
        if (Test-Path -LiteralPath $logsDirectory) {
            $latestLog = Get-ChildItem -LiteralPath $logsDirectory -Filter 'build-*.log' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $StartedAt.AddSeconds(-2) } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($null -ne $latestLog) {
                $logPath = $latestLog.FullName
            }
        }
    }
    catch {
        # Context collection must never hide the original build failure.
    }

    return [pscustomobject]@{
        Stage         = $stage
        LogPath       = $logPath
        WorkDirectory = $workDirectory
    }
}

# Builder.ps1 writes a final generic "failed" state. Preserve the previous
# concrete stage so the elevated parent can report where the failure happened.
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
                if (-not [string]::IsNullOrWhiteSpace($previousStage) -and $previousStage -ne 'failed') {
                    $failedStage = $previousStage
                }
            }
        }
        catch {
            # A damaged state file is not more important than the build error.
        }
    }

    $payload = [ordered]@{
        stage     = $Stage
        updatedAt = (Get-Date).ToString('o')
        message   = $Message
        plan      = $Plan
    }
    if (-not [string]::IsNullOrWhiteSpace($failedStage)) {
        $payload['failedStage'] = $failedStage
    }

    Write-WibJsonFile -Path $Path -Depth 20 -Value $payload
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
        $context = [pscustomobject]@{
            Stage         = 'preflight'
            LogPath       = ''
            WorkDirectory = ''
        }

        try {
            $context = Get-WibExecutionContext -Plan $Plan -StartedAt $startedAt
        }
        catch {
            # Keep fallback context and preserve the original build exception.
        }

        try { $failure.Exception.Data['WibStage'] = [string]$context.Stage } catch { }
        try { $failure.Exception.Data['WibLogPath'] = [string]$context.LogPath } catch { }
        try { $failure.Exception.Data['WibWorkDirectory'] = [string]$context.WorkDirectory } catch { }
        throw $failure
    }
}

function Get-WibResultPropertyText {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Result.PSObject.Properties[$Name]) {
        return ''
    }
    return [string]$Result.$Name
}

function Format-WibElevatedFailure {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )

    $stageValue = Get-WibResultPropertyText -Result $Result -Name 'stage'
    $messageValue = Get-WibResultPropertyText -Result $Result -Name 'message'
    $logPath = Get-WibResultPropertyText -Result $Result -Name 'logPath'
    $workDirectory = Get-WibResultPropertyText -Result $Result -Name 'workDirectory'
    $isoPath = Get-WibResultPropertyText -Result $Result -Name 'isoPath'
    $stackTrace = Get-WibResultPropertyText -Result $Result -Name 'stackTrace'

    $stage = if ([string]::IsNullOrWhiteSpace($stageValue)) { 'unknown' } else { $stageValue }
    $message = if ([string]::IsNullOrWhiteSpace($messageValue)) { "Повышенный процесс завершился с кодом $ExitCode." } else { $messageValue }
    $lines = @(
        'Сборка с правами администратора завершилась ошибкой.',
        ('Этап: {0}' -f $stage),
        ('Причина: {0}' -f $message)
    )

    if (-not [string]::IsNullOrWhiteSpace($logPath)) {
        $lines += ('Лог: {0}' -f $logPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($workDirectory)) {
        $lines += ('Рабочий каталог: {0}' -f $workDirectory)
    }
    if (-not [string]::IsNullOrWhiteSpace($isoPath)) {
        $lines += ('ISO: {0}' -f $isoPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($stackTrace)) {
        $lines += 'Стек ошибки:'
        $lines += $stackTrace
    }

    return ($lines -join [Environment]::NewLine)
}

# Overrides the original implementation from Builder.ps1. The elevated child
# writes a result JSON next to the plan file, and the parent reports its details.
function Start-WibElevatedPlan {
    param([Parameter(Mandatory = $true)]$Plan)

    $plansDirectory = Join-Path ([string]$Plan.CacheDirectory) 'plans'
    New-Item -ItemType Directory -Path $plansDirectory -Force | Out-Null

    $operationId = [Guid]::NewGuid().ToString('N')
    $planPath = Join-Path $plansDirectory ('plan-{0}.json' -f $operationId)
    $resultPath = Join-Path $plansDirectory ('result-{0}.json' -f $operationId)
    Save-WibPlan -Plan $Plan -Path $planPath

    $entryScript = Join-Path $script:ProjectRoot 'Start-Builder.ps1'
    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Quote-WibCommandArgument -Value $entryScript),
        '-PlanFile',
        (Quote-WibCommandArgument -Value $planPath),
        '-ResultFile',
        (Quote-WibCommandArgument -Value $resultPath)
    )

    Write-Host 'Для загрузки и конвертации UUP требуются права администратора. Открывается UAC...' -ForegroundColor Yellow
    try {
        try {
            $process = Start-Process -FilePath (Get-WibPowerShellExecutable) -Verb RunAs -Wait -PassThru -ArgumentList $arguments
        }
        catch {
            throw "Не удалось запустить сборку с правами администратора: $($_.Exception.Message)"
        }

        $result = $null
        if (Test-Path -LiteralPath $resultPath) {
            try {
                $result = Read-WibJsonFile -Path $resultPath
            }
            catch {
                throw "Повышенный процесс завершился с кодом $($process.ExitCode), но файл результата повреждён: $resultPath. $($_.Exception.Message)"
            }
        }

        if ($null -eq $result) {
            throw "Повышенный процесс завершился с кодом $($process.ExitCode), но не создал файл результата: $resultPath"
        }

        $success = $false
        if ($null -ne $result.PSObject.Properties['success']) {
            $success = [bool]$result.success
        }
        if ($process.ExitCode -ne 0 -or -not $success) {
            throw (Format-WibElevatedFailure -Result $result -ExitCode $process.ExitCode)
        }

        return $result
    }
    finally {
        Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    }
}
