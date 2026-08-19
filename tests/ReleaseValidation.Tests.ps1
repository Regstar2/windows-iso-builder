#requires -Version 5.1

Describe 'Release validation tooling' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:projectRoot 'tools\ReleaseValidation.Common.ps1')
        $script:releaseConfig = Import-WibReleaseValidationConfig -ProjectRoot $script:projectRoot
        $script:version = [IO.File]::ReadAllText((Join-Path $script:projectRoot 'VERSION'), [Text.Encoding]::ASCII).Trim()
    }

    It 'keeps standalone validation, packaging, and GUI build scripts PS5.1-targeted and ASCII-only' {
        foreach ($relative in @('tools\Invoke-ReleaseValidation.ps1','tools\New-ReleasePackage.ps1','tools\Build-Gui.ps1')) {
            $path = Join-Path $script:projectRoot $relative
            $bytes = [IO.File]::ReadAllBytes($path)
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
            $text = [Text.Encoding]::ASCII.GetString($bytes)
            $text | Should -Match '#requires -Version 5\.1'
            $text | Should -Not -Match '\?\?|\?\.'
        }
    }

    It 'uses one centralized release allowlist and denylist' {
        [int]$script:releaseConfig.SchemaVersion | Should -Be 1
        @($script:releaseConfig.RuntimeEntries).Count | Should -BeGreaterThan 0
        @($script:releaseConfig.RequiredPackageFiles) | Should -Contain 'release-manifest.json'
        @($script:releaseConfig.RequiredPackageFiles) | Should -Contain 'WindowsISOBuilder.exe'
        foreach ($denied in @('.git','.github','tests','output','logs','dist','cache','bin','obj','.project-rules','.vscode','.idea')) { @($script:releaseConfig.DeniedPathSegments) | Should -Contain $denied }
        @($script:releaseConfig.DeniedExtensions) | Should -Contain '.pdb'
    }

    It 'disables GUI debug symbols in Release configuration' {
        $project = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\WindowsISOBuilder.Gui.csproj') -Raw -Encoding UTF8
        $project | Should -Match '<DebugSymbols>false</DebugSymbols>'
        $project | Should -Match '<DebugType>none</DebugType>'
    }

    It 'waits for packaged GUI smoke before starting archive creation' {
        $packager = Get-Content -LiteralPath (Join-Path $script:projectRoot 'tools\New-ReleasePackage.ps1') -Raw -Encoding ASCII
        $packager | Should -Match 'Start-Process -FilePath \$guiExe .* -Wait .* -PassThru'
        $packager | Should -Match '\$smokeProcess\.ExitCode'
        $packager | Should -Not -Match '&\s+\$guiExe\s+--backend-smoke'
    }

    It 'guards and restores the self-hosted validation environment' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:projectRoot '.github\workflows\windows-self-hosted-validation.yml') -Raw -Encoding UTF8
        $workflow | Should -Match "head\.repo\.full_name == github\.repository"
        $workflow | Should -Match 'contents:\s*read'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'runs-on:\s*\[self-hosted, Windows, X64\]'
        $workflow | Should -Match "RequiredVersion 5\.7\.1"
        $workflow | Should -Match "RequiredVersion 1\.25\.0"
        $workflow | Should -Match '\$originalPolicy'
        $workflow | Should -Match 'finally\s*\{'
        $workflow | Should -Match 'InstallationPolicy \$originalPolicy'
    }

    It 'has a complete source allowlist without generated GUI publish files' {
        $files = @(Get-WibReleaseSourceFiles -ProjectRoot $script:projectRoot -Config $script:releaseConfig -Version $script:version)
        $files.Count | Should -BeGreaterThan 0
        foreach ($file in $files) { (Test-WibReleaseRelativePathDenied -RelativePath $file.RelativePath -Config $script:releaseConfig) | Should -BeFalse }
        @($files | Where-Object { $_.RelativePath -like 'src\WindowsISOBuilder.Gui\bin\*' -or $_.RelativePath -like 'src\WindowsISOBuilder.Gui\obj\*' }).Count | Should -Be 0
    }

    It 'scans current tracked tree without treating developer-only tests as package violations' {
        $files = @(Get-WibCurrentTreeFiles -ProjectRoot $script:projectRoot)
        $findings = @(Get-WibReleaseSafetyFindings -Files $files -Config $script:releaseConfig -SkipDenyPathCheck)
        $findings.Count | Should -Be 0
    }

    It 'builds base manifest data from independent version sources without personal metadata' {
        $manifest = Get-WibReleaseManifestData -ProjectRoot $script:projectRoot -ApplicationVersion $script:version
        $manifest.applicationVersion | Should -Be '0.3.0-alpha.1'
        $manifest.moduleVersion | Should -Be '0.3.0'
        $manifest.backendContractSchemaVersion | Should -Be 1
        $manifest.buildPlanSchemaVersion | Should -Be 1
        @($manifest.Keys) | Should -Be @('applicationVersion','moduleVersion','backendContractSchemaVersion','buildPlanSchemaVersion')
    }

    It 'documents that the safety scan is not a Git-history audit' {
        $matrix = Get-Content -LiteralPath (Join-Path $script:projectRoot 'docs\VALIDATION_MATRIX_EN.md') -Raw -Encoding UTF8
        $matrix | Should -Match 'not a Git-history audit'
    }
}
