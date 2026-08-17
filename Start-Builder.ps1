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
    [switch]$NetFx3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

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

try {
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
                success       = $true
                stage         = $stage
                message       = ''
                stackTrace    = ''
                logPath       = $logPath
                workDirectory = $workDirectory
                isoPath       = $isoPath
            })
        }
        exit 0
    }

    if ($NonInteractive) {
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
        exit 0
    }

    Start-WibInteractive -ApplicationRoot $PSScriptRoot
    exit 0
}
catch {
    if ($PSCmdlet.ParameterSetName -eq 'Plan' -and -not [string]::IsNullOrWhiteSpace($ResultFile)) {
        $stage = 'startup'
        $logPath = ''
        $workDirectory = ''

        try {
            if ($_.Exception.Data.Contains('WibStage')) { $stage = [string]$_.Exception.Data['WibStage'] }
            if ($_.Exception.Data.Contains('WibLogPath')) { $logPath = [string]$_.Exception.Data['WibLogPath'] }
            if ($_.Exception.Data.Contains('WibWorkDirectory')) { $workDirectory = [string]$_.Exception.Data['WibWorkDirectory'] }
        }
        catch {
            # Result serialization should still succeed with fallback values.
        }

        try {
            Write-WibProcessResultFile -Path $ResultFile -Value ([ordered]@{
                success       = $false
                stage         = $stage
                message       = [string]$_.Exception.Message
                stackTrace    = [string]$_.ScriptStackTrace
                logPath       = $logPath
                workDirectory = $workDirectory
                isoPath       = ''
            })
        }
        catch {
            Write-Host ('Не удалось записать файл результата повышенного процесса: {0}' -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    Write-Host ''
    Write-Host ('ОШИБКА: {0}' -f $_.Exception.Message) -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
}
