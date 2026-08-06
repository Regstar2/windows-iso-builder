#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Plan', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PlanFile,

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

try {
    if ($PSCmdlet.ParameterSetName -eq 'Plan') {
        Invoke-WibPlanFile -Path $PlanFile
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
    Write-Host ''
    Write-Host ('ОШИБКА: {0}' -f $_.Exception.Message) -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
}
