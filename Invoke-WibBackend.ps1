#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RequestFile,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResponseFile,

    [string]$EventFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keep this standalone entry script ASCII-only for Windows PowerShell 5.1.
$scriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    throw 'Unable to determine backend entry script path.'
}
$projectRoot = Split-Path -Parent $scriptPath
$modulePath = Join-Path $projectRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

$parameters = @{
    RequestFile = $RequestFile
    ResponseFile = $ResponseFile
}
if (-not [string]::IsNullOrWhiteSpace($EventFile)) {
    $parameters.EventFile = $EventFile
}

$result = Invoke-WibBackendRequest @parameters
if ($null -ne $result -and $result.success) {
    exit 0
}
exit 1
