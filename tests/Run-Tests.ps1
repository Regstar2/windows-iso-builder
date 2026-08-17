#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw 'Pester не установлен. Установите Pester 5 и повторите запуск.'
}

$previousRepositoryRoot = $env:WIB_REPOSITORY_ROOT
try {
    $env:WIB_REPOSITORY_ROOT = Split-Path -Parent $PSScriptRoot
    Invoke-Pester -Path $PSScriptRoot -Output Detailed
}
finally {
    if ($null -eq $previousRepositoryRoot) {
        Remove-Item Env:WIB_REPOSITORY_ROOT -ErrorAction SilentlyContinue
    }
    else {
        $env:WIB_REPOSITORY_ROOT = $previousRepositoryRoot
    }
}
