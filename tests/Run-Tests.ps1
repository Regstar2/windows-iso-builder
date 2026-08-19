#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw 'Pester 5 is required to run the test suite.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$reportPath = Join-Path $repositoryRoot 'pester-result.json'
$previousRepositoryRoot = $env:WIB_REPOSITORY_ROOT
$failedCount = 0
try {
    $env:WIB_REPOSITORY_ROOT = $repositoryRoot
    $result = Invoke-Pester -Path $PSScriptRoot -Output Detailed -PassThru
    $failedCount = [int]$result.FailedCount

    $failedTests = @(
        $result.Tests |
            Where-Object { [string]$_.Result -eq 'Failed' } |
            ForEach-Object {
                [ordered]@{
                    name = [string]$_.Name
                    path = [IO.Path]::GetFileName([string]$_.Path)
                    error = if ($null -ne $_.ErrorRecord) { [string]$_.ErrorRecord.Exception.Message } else { '' }
                }
            }
    )
    $report = [ordered]@{
        totalCount = [int]$result.TotalCount
        passedCount = [int]$result.PassedCount
        failedCount = $failedCount
        skippedCount = [int]$result.SkippedCount
        failures = $failedTests
    }
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
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
