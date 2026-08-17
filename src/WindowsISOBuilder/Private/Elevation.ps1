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
        $payload.failedStage = $failedStage
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
        $context = Get-WibExecutionContext -Plan $Plan -StartedAt $startedAt
        try { $_.Exception.Data['WibStage'] = [string]$context.Stage } catch { }
        try { $_.Exception.Data['WibLogPath'] = [string]$context.LogPath } catch { }
        try { $_.Exception.Data['WibWorkDirectory'] = [string]$context.WorkDirectory } catch { }
        throw
    }
}

function Format-WibElevatedFailure {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )

    $stage = if ([string]::IsNullOrWhiteSpace([string]$Result.stage)) { 'unknown' } else { [string]$Result.stage }
    $message = if ([string]::IsNullOrWhiteSpace([string]$Result.message)) { "Повышенный процесс завершился с кодом $ExitCode." } else { [string]$Result.message }
    $lines = @(
        'Сборка с правами администратора завершилась ошибкой.',
        ('Этап: {0}' -f $stage),
        ('Причина: {0}' -f $message)
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Result.logPath)) {
        $lines += ('Лог: {0}' -f [string]$Result.logPath)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.workDirectory)) {
        $lines += ('Рабочий каталог: {0}' -f [string]$Result.workDirectory)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.isoPath)) {
        $lines += ('ISO: {0}' -f [string]$Result.isoPath)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.stackTrace)) {
        $lines += 'Стек ошибки:'
        $lines += [string]$Result.stackTrace
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

        if ($process.ExitCode -ne 0 -or -not [bool]$result.success) {
            throw (Format-WibElevatedFailure -Result $result -ExitCode $process.ExitCode)
        }

        return $result
    }
    finally {
        Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    }
}
