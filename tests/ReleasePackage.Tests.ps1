#requires -Version 5.1

Describe 'Release package validation' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:projectRoot 'tools\ReleaseValidation.Common.ps1')
        $script:releaseConfig = Import-WibReleaseValidationConfig -ProjectRoot $script:projectRoot
        $script:releaseVersion = [IO.File]::ReadAllText((Join-Path $script:projectRoot 'VERSION'), [Text.Encoding]::ASCII).Trim()
        $script:packageOutput = Join-Path $TestDrive 'package-output'
        & (Join-Path $script:projectRoot 'tools\New-ReleasePackage.ps1') -OutputDirectory $script:packageOutput | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'New-ReleasePackage.ps1 failed.' }
        $script:zipPath = Join-Path $script:packageOutput ('windows-iso-builder-v{0}.zip' -f $script:releaseVersion)
        $script:checksumPath = "$script:zipPath.sha256"
        $script:extractRoot = Join-Path $TestDrive 'extracted'
        Expand-Archive -LiteralPath $script:zipPath -DestinationPath $script:extractRoot -Force
        $script:packageRoot = Join-Path $script:extractRoot ('windows-iso-builder-v{0}' -f $script:releaseVersion)
    }

    It 'creates an openable ZIP and matching SHA-256 checksum' {
        Test-Path -LiteralPath $script:zipPath -PathType Leaf | Should -BeTrue
        $checksumText = [IO.File]::ReadAllText($script:checksumPath, [Text.Encoding]::UTF8)
        $checksumText | Should -Match '^([A-Fa-f0-9]{64})\s+'
        $expectedHash = ([regex]::Match($checksumText, '^([A-Fa-f0-9]{64})\s+')).Groups[1].Value.ToUpperInvariant()
        (Get-FileHash -LiteralPath $script:zipPath -Algorithm SHA256).Hash.ToUpperInvariant() | Should -Be $expectedHash
    }

    It 'contains every allowlisted source runtime file plus generated GUI runtime files' {
        foreach ($source in @(Get-WibReleaseSourceFiles -ProjectRoot $script:projectRoot -Config $script:releaseConfig -Version $script:releaseVersion)) {
            Test-Path -LiteralPath (Join-Path $script:packageRoot $source.RelativePath) -PathType Leaf | Should -BeTrue
        }
        Test-Path -LiteralPath (Join-Path $script:packageRoot 'WindowsISOBuilder.exe') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:packageRoot 'WindowsISOBuilder.dll') -PathType Leaf | Should -BeTrue
    }

    It 'generates expected package-only manifest versions and GUI metadata' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:packageRoot 'release-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifest.applicationVersion | Should -Be '0.4.0-alpha.1'
        $manifest.moduleVersion | Should -Be '0.3.0'
        $manifest.backendContractSchemaVersion | Should -Be 1
        $manifest.buildPlanSchemaVersion | Should -Be 1
        $manifest.gui.included | Should -BeTrue
        $manifest.gui.runtime | Should -Be 'win-x64'
        $manifest.gui.selfContained | Should -BeTrue
    }

    It 'contains required runtime files and no safety findings' {
        foreach ($required in @($script:releaseConfig.RequiredPackageFiles)) { Test-Path -LiteralPath (Join-Path $script:packageRoot ([string]$required)) | Should -BeTrue }
        @(Get-WibReleaseSafetyFindings -Files (Get-WibFilesUnderRoot -Root $script:packageRoot) -Config $script:releaseConfig).Count | Should -Be 0
    }

    It 'keeps packaged backend inside extracted package and runs GUI backend smoke' {
        $guiExe = Join-Path $script:packageRoot 'WindowsISOBuilder.exe'
        Test-Path -LiteralPath (Join-Path $script:packageRoot 'Invoke-WibBackend.ps1') | Should -BeTrue
        $smokeProcess = Start-Process -FilePath $guiExe -ArgumentList @('--backend-smoke') -Wait -PassThru -WindowStyle Hidden
        $smokeProcess.ExitCode | Should -Be 0
    }

    It 'keeps TUI and CLI entry points in the GUI release' {
        Test-Path -LiteralPath (Join-Path $script:packageRoot 'Start-Builder.cmd') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:packageRoot 'Start-Builder.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:packageRoot 'Invoke-WibBackend.ps1') | Should -BeTrue
    }
}
