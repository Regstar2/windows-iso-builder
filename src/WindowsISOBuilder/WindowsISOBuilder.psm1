Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleRoot = $PSScriptRoot
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WibVersion = '0.1.0-alpha.1'

$privateFiles = @(
    'Private\Common.ps1',
    'Private\Cache.ps1',
    'Private\UupApi.ps1',
    'Private\Plan.ps1',
    'Private\Selection.ps1',
    'Private\Builder.ps1',
    'Private\Application.ps1'
)

foreach ($relativePath in $privateFiles) {
    . (Join-Path $PSScriptRoot $relativePath)
}

Export-ModuleMember -Function @(
    'Start-WibInteractive',
    'Start-WibNonInteractive',
    'Invoke-WibPlanFile',
    'Search-WibBuilds',
    'Get-WibLanguages',
    'Get-WibEditions',
    'New-WibBuildPlan',
    'Invoke-WibBuildPlan',
    'Get-WibCacheInfo',
    'Clear-WibCache'
)
