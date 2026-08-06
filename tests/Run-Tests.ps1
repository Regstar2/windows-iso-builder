#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw 'Pester не установлен. Установите Pester 5 и повторите запуск.'
}
Invoke-Pester -Path $PSScriptRoot -Output Detailed
