Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleRoot = $PSScriptRoot
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$versionPath = Join-Path $script:ProjectRoot 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath)) {
    throw 'Application VERSION file is missing.'
}
$script:WibApplicationVersion = [IO.File]::ReadAllText($versionPath, [Text.Encoding]::ASCII).Trim()
if ([string]::IsNullOrWhiteSpace($script:WibApplicationVersion)) {
    throw 'Application VERSION file is empty.'
}
# Keep the existing script variable as a compatibility alias for current TUI
# and metadata code while VERSION remains the single application-version source.
$script:WibVersion = $script:WibApplicationVersion

$privateFiles = @(
    'Private\Common.ps1',
    'Private\BackendEvents.ps1',
    'Private\Cache.ps1',
    'Private\UupApi.ps1',
    'Private\Plan.ps1',
    'Private\Selection.ps1',
    'Private\Recommendation.ps1',
    'Private\Builder.ps1',
    'Private\Elevation.ps1',
    'Private\Application.ps1',
    'Private\ConsoleProgress.ps1',
    'Private\BackendContract.ps1',
    'Private\BackendCommands.ps1'
)

foreach ($relativePath in $privateFiles) {
    $privatePath = Join-Path $PSScriptRoot $relativePath

    # Windows PowerShell 5.1 treats UTF-8 files without a BOM as the current
    # ANSI code page when they are dot-sourced by path. GitHub and other tools
    # can legitimately save UTF-8 without a BOM, so read the source explicitly
    # as UTF-8 before parsing it. Dot-sourcing the resulting script block keeps
    # the private functions in this module's script scope.
    $privateSource = Get-Content -LiteralPath $privatePath -Raw -Encoding UTF8
    $privateScript = [scriptblock]::Create($privateSource)
    . $privateScript
}

Export-ModuleMember -Function @(
    'Start-WibInteractive',
    'Start-WibNonInteractive',
    'Invoke-WibPlanFile',
    'Invoke-WibBackendRequest',
    'Search-WibBuilds',
    'Get-WibLanguages',
    'Get-WibEditions',
    'New-WibBuildPlan',
    'Invoke-WibBuildPlan',
    'Get-WibCacheInfo',
    'Clear-WibCache'
)
