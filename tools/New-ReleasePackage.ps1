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
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDirectory
. (Join-Path $scriptDirectory 'ReleaseValidation.Common.ps1')
$config = Import-WibReleaseValidationConfig -ProjectRoot $projectRoot

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [IO.File]::ReadAllText((Join-Path $projectRoot 'VERSION'), [Text.Encoding]::ASCII).Trim()
}
if ([string]::IsNullOrWhiteSpace($Version)) { throw 'Release version is empty.' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $projectRoot 'dist' }

$sourceFiles = @(Get-WibReleaseSourceFiles -ProjectRoot $projectRoot -Config $config -Version $Version)
$sourceFindings = @(Get-WibReleaseSafetyFindings -Files $sourceFiles -Config $config)
if ($sourceFindings.Count -gt 0) { throw 'Release source material failed safety validation.' }

$outputDirectoryFull = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputDirectoryFull -Force | Out-Null
$archiveName = 'windows-iso-builder-v{0}.zip' -f $Version
$archivePath = Join-Path $outputDirectoryFull $archiveName
$archiveHashPath = "$archivePath.sha256"
$standaloneName = 'windows-iso-builder-v{0}.exe' -f $Version
$standalonePath = Join-Path $outputDirectoryFull $standaloneName
$standaloneHashPath = "$standalonePath.sha256"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('windows-iso-builder-release-{0}' -f [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stagingRoot ('windows-iso-builder-v{0}' -f $Version)
$guiPublishRoot = Join-Path $stagingRoot 'gui-publish'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

try {
    New-Item -ItemType Directory -Path $packageRoot,$guiPublishRoot -Force | Out-Null

    & (Join-Path $scriptDirectory 'Build-Gui.ps1') -OutputDirectory $guiPublishRoot
    if ($LASTEXITCODE -ne 0) { throw ('GUI build/publish failed with exit code {0}.' -f $LASTEXITCODE) }

    foreach ($relativePath in (Expand-WibReleaseEntries -Config $config -Version $Version)) {
        $sourcePath = Join-Path $projectRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) { throw ('Release package entry is missing: {0}' -f $relativePath) }
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

    Copy-Item -Path (Join-Path $guiPublishRoot '*') -Destination $packageRoot -Recurse -Force

    $manifest = Get-WibReleaseManifestData -ProjectRoot $projectRoot -ApplicationVersion $Version
    $manifest.gui = [ordered]@{ included=$true; runtime='win-x64'; selfContained=$true }
    $manifest.releaseArtifacts = @('zip','standalone-exe')
    [IO.File]::WriteAllText((Join-Path $packageRoot 'release-manifest.json'), (($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine), $utf8NoBom)

    $packageFiles = @(Get-WibFilesUnderRoot -Root $packageRoot)
    $packageFindings = @(Get-WibReleaseSafetyFindings -Files $packageFiles -Config $config)
    if ($packageFindings.Count -gt 0) { throw 'Release staging failed safety validation.' }
    foreach ($requiredPath in @($config.RequiredPackageFiles)) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot ([string]$requiredPath)))) {
            throw ('Required release file is missing from staging: {0}' -f $requiredPath)
        }
    }

    $guiExe = Join-Path $packageRoot 'WindowsISOBuilder.exe'
    # Windows PowerShell 5.1 does not reliably wait for GUI-subsystem native
    # applications invoked with '&'. Waiting explicitly prevents runtime DLLs
    # from remaining locked when Compress-Archive starts reading the package.
    $smokeProcess = Start-Process -FilePath $guiExe -ArgumentList @('--backend-smoke') -Wait -PassThru -WindowStyle Hidden
    if ($smokeProcess.ExitCode -ne 0) { throw ('Packaged GUI backend smoke failed with exit code {0}.' -f $smokeProcess.ExitCode) }

    Remove-Item -LiteralPath $archivePath,$archiveHashPath,$standalonePath,$standaloneHashPath -Force -ErrorAction SilentlyContinue
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal
    $archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
    [IO.File]::WriteAllText($archiveHashPath, "$archiveHash  $archiveName`r`n", $utf8NoBom)

    # Build a Windows single-file launcher that embeds the exact validated ZIP.
    # The launcher extracts the portable payload to a unique temp directory,
    # starts WindowsISOBuilder.exe, forwards arguments, waits for completion,
    # and performs best-effort cleanup. This preserves the existing PowerShell
    # backend instead of introducing a second implementation.
    $launcherSource = Join-Path $scriptDirectory 'StandaloneLauncher.cs'
    if (-not (Test-Path -LiteralPath $launcherSource -PathType Leaf)) {
        throw 'Standalone launcher source is missing.'
    }

    $cscCandidates = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    $csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$csc)) {
        throw 'Windows .NET Framework C# compiler is required to build the standalone release EXE.'
    }

    # System.Windows.Forms is already referenced by the .NET Framework compiler
    # response file. Adding a second path from the GAC causes CS1703 on Windows.
    Add-Type -AssemblyName System.IO.Compression
    $compressionAssembly = [IO.Compression.ZipArchive].Assembly.Location
    $iconPath = Join-Path $projectRoot 'src\WindowsISOBuilder.Gui\Assets\WindowsISOBuilder.ico'
    foreach ($required in @($compressionAssembly,$iconPath)) {
        if ([string]::IsNullOrWhiteSpace([string]$required) -or -not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw ('Standalone launcher dependency is missing: {0}' -f $required)
        }
    }

    $cscArguments = @(
        '/nologo',
        '/target:winexe',
        '/optimize+',
        '/platform:x64',
        ('/out:{0}' -f $standalonePath),
        ('/win32icon:{0}' -f $iconPath),
        ('/resource:{0},WindowsISOBuilder.Payload.zip' -f $archivePath),
        ('/reference:{0}' -f $compressionAssembly),
        $launcherSource
    )
    & $csc @cscArguments
    if ($LASTEXITCODE -ne 0) { throw ('Standalone launcher compilation failed with exit code {0}.' -f $LASTEXITCODE) }
    if (-not (Test-Path -LiteralPath $standalonePath -PathType Leaf)) { throw 'Standalone release EXE was not produced.' }

    $standaloneSmoke = Start-Process -FilePath $standalonePath -ArgumentList @('--backend-smoke') -Wait -PassThru -WindowStyle Hidden
    if ($standaloneSmoke.ExitCode -ne 0) { throw ('Standalone EXE backend smoke failed with exit code {0}.' -f $standaloneSmoke.ExitCode) }

    $standaloneHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $standalonePath).Hash
    [IO.File]::WriteAllText($standaloneHashPath, "$standaloneHash  $standaloneName`r`n", $utf8NoBom)

    Write-Host "Release ZIP:       $archivePath" -ForegroundColor Green
    Write-Host "ZIP SHA-256:       $archiveHash" -ForegroundColor Green
    Write-Host "Standalone EXE:    $standalonePath" -ForegroundColor Green
    Write-Host "EXE SHA-256:       $standaloneHash" -ForegroundColor Green
    Write-Host "ZIP checksum:      $archiveHashPath" -ForegroundColor DarkGray
    Write-Host "EXE checksum:      $standaloneHashPath" -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
