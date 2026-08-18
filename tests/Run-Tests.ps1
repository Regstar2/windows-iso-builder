#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw 'Pester не установлен. Установите Pester 5 и повторите запуск.'
}

$previousRepositoryRoot = $env:WIB_REPOSITORY_ROOT
$failedCount = 0
try {
    $env:WIB_REPOSITORY_ROOT = Split-Path -Parent $PSScriptRoot
    $result = Invoke-Pester -Path $PSScriptRoot -Output Detailed -PassThru
    $failedCount = [int]$result.FailedCount
}
finally {
    if ($null -eq $previousRepositoryRoot) {
        Remove-Item Env:WIB_REPOSITORY_ROOT -ErrorAction SilentlyContinue
    }
    else {
        $env:WIB_REPOSITORY_ROOT = $previousRepositoryRoot
    }
}

if ($failedCount -gt 0) {
    Write-Error ("Pester tests failed: {0}." -f $failedCount)
    exit 1
}

exit 0
