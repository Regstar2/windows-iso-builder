#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keep this script ASCII-only. Windows PowerShell 5.1 may interpret UTF-8 files
# without a BOM using the active ANSI code page, which can break parsing.
$scriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    throw 'Unable to determine the release script path.'
}

$scriptDirectory = Split-Path -Parent $scriptPath
$projectRoot = Split-Path -Parent $scriptDirectory
. (Join-Path $scriptDirectory 'ReleaseValidation.Common.ps1')
$config = Import-WibReleaseValidationConfig -ProjectRoot $projectRoot

$versionFile = Join-Path $projectRoot 'VERSION'
if ([string]::IsNullOrWhiteSpace($Version)) {
    if (-not (Test-Path -LiteralPath $versionFile)) {
        throw 'Application VERSION file not found.'
    }
    $Version = [IO.File]::ReadAllText($versionFile, [Text.Encoding]::ASCII).Trim()
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    throw 'Release version is empty.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'dist'
}

$sourceFiles = @(Get-WibReleaseSourceFiles -ProjectRoot $projectRoot -Config $config -Version $Version)
$sourceFindings = @(Get-WibReleaseSafetyFindings -Files $sourceFiles -Config $config)
if ($sourceFindings.Count -gt 0) {
    $paths = @($sourceFindings | ForEach-Object { $_.path } | Sort-Object -Unique)
    throw ('Release source material failed safety validation: {0}' -f ($paths -join ', '))
}

$outputDirectoryFull = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputDirectoryFull -Force | Out-Null

$archiveName = 'windows-iso-builder-v{0}.zip' -f $Version
$archivePath = Join-Path $outputDirectoryFull $archiveName
$hashPath = "$archivePath.sha256"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('windows-iso-builder-release-{0}' -f [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stagingRoot ('windows-iso-builder-v{0}' -f $Version)
$utf8NoBom = New-Object Text.UTF8Encoding($false)

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    foreach ($relativePath in (Expand-WibReleaseEntries -Config $config -Version $Version)) {
        $sourcePath = Join-Path $projectRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw ("Release package file not found: {0}" -f $relativePath)
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

    $manifest = Get-WibReleaseManifestData -ProjectRoot $projectRoot -ApplicationVersion $Version
    $manifestPath = Join-Path $packageRoot 'release-manifest.json'
    [IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 5) + [Environment]::NewLine), $utf8NoBom)

    $packageFiles = @(Get-WibFilesUnderRoot -Root $packageRoot)
    $packageFindings = @(Get-WibReleaseSafetyFindings -Files $packageFiles -Config $config)
    if ($packageFindings.Count -gt 0) {
        $paths = @($packageFindings | ForEach-Object { $_.path } | Sort-Object -Unique)
        throw ('Release staging failed safety validation: {0}' -f ($paths -join ', '))
    }

    foreach ($requiredPath in @($config.RequiredPackageFiles)) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot ([string]$requiredPath)))) {
            throw ("Required release file is missing from staging: {0}" -f $requiredPath)
        }
    }

    Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $hashPath -Force -ErrorAction SilentlyContinue
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
    [IO.File]::WriteAllText($hashPath, "$hash  $archiveName`r`n", $utf8NoBom)

    Write-Host "Release ZIP: $archivePath" -ForegroundColor Green
    Write-Host "SHA-256:     $hash" -ForegroundColor Green
    Write-Host "Checksum:    $hashPath" -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
