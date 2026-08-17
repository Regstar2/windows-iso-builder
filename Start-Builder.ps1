#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Plan', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PlanFile,

    [Parameter(ParameterSetName = 'Plan')]
    [ValidateNotNullOrEmpty()]
    [string]$ResultFile,

    [Parameter(ParameterSetName = 'CommandLine')]
    [switch]$NonInteractive,

    [Parameter(ParameterSetName = 'CommandLine')]
    [ValidateNotNullOrEmpty()]
    [string]$Search,

    [Parameter(ParameterSetName = 'CommandLine')]
    [ValidateSet('amd64', 'arm64', 'x86')]
    [string]$Architecture = 'amd64',

    [Parameter(ParameterSetName = 'CommandLine')]
    [ValidatePattern('^[a-z]{2}-[a-z]{2}$')]
    [string]$Language = 'ru-ru',

    [Parameter(ParameterSetName = 'CommandLine')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Editions = @('Professional'),

    [Parameter(ParameterSetName = 'CommandLine')]
    [ValidateSet('WIM', 'ESD')]
    [string]$ImageFormat = 'ESD',

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$OutputDirectory,

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$CacheDirectory,

    [Parameter(ParameterSetName = 'CommandLine')]
    [switch]$IncludePreview,

    [Parameter(ParameterSetName = 'CommandLine')]
    [switch]$ForceCatalogRefresh,

    [Parameter(ParameterSetName = 'CommandLine')]
    [switch]$NoUpdates,

    [Parameter(ParameterSetName = 'CommandLine')]
    [switch]$NoCleanup,

    [Parameter(ParameterSetName = 'CommandLine')]
    [switch]$NetFx3,

    [Parameter()]
    [string]$ExecutionLogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-WibProcessResultFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporary = '{0}.{1}.tmp' -f $Path, [Guid]::NewGuid().ToString('N')
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Start-WibExecutionTranscript {
    param([AllowEmptyString()][string]$RequestedPath)

    $path = $RequestedPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        $logsDirectory = Join-Path $PSScriptRoot 'logs'
        $fileName = 'execution-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID
        $path = Join-Path $logsDirectory $fileName
    }
    elseif (-not [IO.Path]::IsPathRooted($path)) {
        $path = Join-Path $PSScriptRoot $path
    }

    $directory = Split-Path -Parent $path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $fullPath = [IO.Path]::GetFullPath($path)
    Start-Transcript -LiteralPath $fullPath -Force | Out-Null
    return $fullPath
}

$executionLogPath = ''
$executionTranscriptStarted = $false
try {
    $executionLogPath = Start-WibExecutionTranscript -RequestedPath $ExecutionLogFile
    $executionTranscriptStarted = $true
    Write-Host ('Лог выполнения: {0}' -f $executionLogPath) -ForegroundColor DarkGray
}
catch {
    Write-Host ('ПРЕДУПРЕЖДЕНИЕ: не удалось запустить лог выполнения: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
}

$exitCode = 0
try {
    $modulePath = Join-Path $PSScriptRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psd1'
    Import-Module $modulePath -Force

    if ($PSCmdlet.ParameterSetName -eq 'Plan') {
        $buildResult = Invoke-WibPlanFile -Path $PlanFile

        if (-not [string]::IsNullOrWhiteSpace($ResultFile)) {
            $stage = 'completed'
            $logPath = ''
            $workDirectory = ''
            $isoPath = ''

            if ($null -ne $buildResult) {
                if ($null -ne $buildResult.PSObject.Properties['Stage']) { $stage = [string]$buildResult.Stage }
                if ($null -ne $buildResult.PSObject.Properties['LogPath']) { $logPath = [string]$buildResult.LogPath }
                if ($null -ne $buildResult.PSObject.Properties['WorkDirectory']) { $workDirectory = [string]$buildResult.WorkDirectory }
                if ($null -ne $buildResult.PSObject.Properties['IsoPath']) { $isoPath = [string]$buildResult.IsoPath }
            }

            Write-WibProcessResultFile -Path $ResultFile -Value ([ordered]@{
                success          = $true
                stage            = $stage
                message          = ''
                stackTrace       = ''
                logPath          = $logPath
                executionLogPath = $executionLogPath
                workDirectory    = $workDirectory
                isoPath          = $isoPath
            })
        }
    }
    elseif ($NonInteractive) {
        if ([string]::IsNullOrWhiteSpace($Search)) {
            throw 'Для неинтерактивного режима требуется параметр -Search.'
        }

        $parameters = @{
            Search              = $Search
            Architecture        = $Architecture
            Language            = $Language
            Editions            = $Editions
            ImageFormat         = $ImageFormat
            IncludePreview      = $IncludePreview.IsPresent
            ForceCatalogRefresh = $ForceCatalogRefresh.IsPresent
            AddUpdates          = -not $NoUpdates.IsPresent
            Cleanup             = -not $NoCleanup.IsPresent
            NetFx3              = $NetFx3.IsPresent
        }
        if ($PSBoundParameters.ContainsKey('OutputDirectory')) { $parameters.OutputDirectory = $OutputDirectory }
        if ($PSBoundParameters.ContainsKey('CacheDirectory')) { $parameters.CacheDirectory = $CacheDirectory }

        Start-WibNonInteractive @parameters
    }
    else {
        Start-WibInteractive -ApplicationRoot $PSScriptRoot
    }
}
catch {
    $failure = $_
    $exitCode = 1

    if ($PSCmdlet.ParameterSetName -eq 'Plan' -and -not [string]::IsNullOrWhiteSpace($ResultFile)) {
        $stage = 'startup'
        $logPath = ''
        $workDirectory = ''

        try {
            if ($failure.Exception.Data.Contains('WibStage')) { $stage = [string]$failure.Exception.Data['WibStage'] }
            if ($failure.Exception.Data.Contains('WibLogPath')) { $logPath = [string]$failure.Exception.Data['WibLogPath'] }
            if ($failure.Exception.Data.Contains('WibWorkDirectory')) { $workDirectory = [string]$failure.Exception.Data['WibWorkDirectory'] }
        }
        catch {
            # Result serialization should still succeed with fallback values.
        }

        try {
            Write-WibProcessResultFile -Path $ResultFile -Value ([ordered]@{
                success          = $false
                stage            = $stage
                message          = [string]$failure.Exception.Message
                stackTrace       = [string]$failure.ScriptStackTrace
                logPath          = $logPath
                executionLogPath = $executionLogPath
                workDirectory    = $workDirectory
                isoPath          = ''
            })
        }
        catch {
            Write-Host ('Не удалось записать файл результата повышенного процесса: {0}' -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    Write-Host ''
    Write-Host ('ОШИБКА: {0}' -f $failure.Exception.Message) -ForegroundColor Red
    if ($failure.ScriptStackTrace) {
        Write-Host $failure.ScriptStackTrace -ForegroundColor DarkGray
    }
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($executionLogPath)) {
        Write-Host ('Лог выполнения сохранён: {0}' -f $executionLogPath) -ForegroundColor DarkGray
    }
    if ($executionTranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}

exit $exitCode
