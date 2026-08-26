#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keep this script ASCII-only for Windows PowerShell 5.1.
$projectRoot = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $projectRoot 'WindowsISOBuilder.sln'
$project = Join-Path $projectRoot 'src\WindowsISOBuilder.Gui\WindowsISOBuilder.Gui.csproj'
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if ($null -eq $dotnet) {
    throw '.NET 10 SDK is required. See REQUIREMENTS.md.'
}
$sdks = @(& $dotnet.Source --list-sdks)
if (@($sdks | Where-Object { $_ -match '^10\.' }).Count -eq 0) {
    throw '.NET 10 SDK is required. Install an SDK 10.x version documented in REQUIREMENTS.md.'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'dist\gui\win-x64'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Invoke-DotNetStep {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & $dotnet.Source @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ('dotnet {0} failed with exit code {1}.' -f ($Arguments -join ' '), $LASTEXITCODE)
    }
}

Invoke-DotNetStep -Arguments @('restore', $solution)
Invoke-DotNetStep -Arguments @('build', $solution, '-c', 'Release', '--no-restore')
Invoke-DotNetStep -Arguments @('test', $solution, '-c', 'Release', '--no-build')

# Publish the WPF GUI as one self-contained executable. The PowerShell backend
# and documentation remain normal files in the portable ZIP, but the release
# root is no longer polluted by framework/runtime DLLs.
Invoke-DotNetStep -Arguments @('restore', $project, '-r', 'win-x64')
Invoke-DotNetStep -Arguments @(
    'publish', $project,
    '-c', 'Release',
    '-r', 'win-x64',
    '--self-contained', 'true',
    '--no-restore',
    '-p:PublishSingleFile=true',
    '-p:IncludeNativeLibrariesForSelfExtract=true',
    '-p:EnableCompressionInSingleFile=true',
    '-p:DebugType=None',
    '-p:DebugSymbols=false',
    '-o', $OutputDirectory
)

$publishedDlls = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Filter '*.dll' -ErrorAction SilentlyContinue)
if ($publishedDlls.Count -gt 0) {
    throw ('Single-file GUI publish unexpectedly produced DLL files: {0}' -f (($publishedDlls.Name) -join ', '))
}
if (-not (Test-Path -LiteralPath (Join-Path $OutputDirectory 'WindowsISOBuilder.exe') -PathType Leaf)) {
    throw 'Single-file GUI publish did not produce WindowsISOBuilder.exe.'
}

Write-Host ('GUI publish: {0}' -f $OutputDirectory)
