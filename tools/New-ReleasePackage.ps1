#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Version = '0.2.0-alpha.1',
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectoryFull = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputDirectoryFull -Force | Out-Null

$archiveName = 'windows-iso-builder-v{0}.zip' -f $Version
$archivePath = Join-Path $outputDirectoryFull $archiveName
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('windows-iso-builder-release-{0}' -f [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stagingRoot ('windows-iso-builder-v{0}' -f $Version)

$runtimeFiles = @(
    'Start-Builder.cmd',
    'Start-Builder.ps1',
    'README.md',
    'README_EN.md',
    'LICENSE',
    'CHANGELOG.md',
    'REQUIREMENTS.md',
    'SECURITY.md',
    'CONTRIBUTING.md',
    'src',
    'docs\ARCHITECTURE.md',
    'docs\IMPLEMENTATION_STATUS.md',
    'docs\SOURCE_V4_MIGRATION.md',
    ('docs\releases\v{0}.md' -f $Version),
    ('docs\releases\v{0}_EN.md' -f $Version)
)

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    foreach ($relativePath in $runtimeFiles) {
        $sourcePath = Join-Path $projectRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Не найден файл релизного пакета: $relativePath"
        }

        $destinationPath = Join-Path $packageRoot $relativePath
        if ((Get-Item -LiteralPath $sourcePath).PSIsContainer) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
        }
        else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }
    }

    Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
    $hashPath = "$archivePath.sha256"
    [IO.File]::WriteAllText($hashPath, "$hash  $archiveName`r`n", (New-Object Text.UTF8Encoding($false)))

    Write-Host "Release ZIP: $archivePath" -ForegroundColor Green
    Write-Host "SHA-256:     $hash" -ForegroundColor Green
    Write-Host "Checksum:    $hashPath" -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}