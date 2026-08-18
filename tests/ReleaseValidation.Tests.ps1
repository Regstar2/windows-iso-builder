#requires -Version 5.1

Describe 'Release validation tooling' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:projectRoot 'tools\ReleaseValidation.Common.ps1')
        $script:releaseConfig = Import-WibReleaseValidationConfig -ProjectRoot $script:projectRoot
        $script:version = [IO.File]::ReadAllText((Join-Path $script:projectRoot 'VERSION'), [Text.Encoding]::ASCII).Trim()
    }

    It 'keeps the standalone validation and packaging scripts PS5.1-targeted and ASCII-only' {
        foreach ($relative in @('tools\Invoke-ReleaseValidation.ps1','tools\New-ReleasePackage.ps1')) {
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
        foreach ($denied in @('.git','.github','tests','output','logs','dist','cache','.project-rules','.vscode','.idea')) {
            @($script:releaseConfig.DeniedPathSegments) | Should -Contain $denied
        }
    }

    It 'has a complete release source allowlist for the current version' {
        $files = @(Get-WibReleaseSourceFiles -ProjectRoot $script:projectRoot -Config $script:releaseConfig -Version $script:version)
        $files.Count | Should -BeGreaterThan 0
        foreach ($file in $files) {
            (Test-WibReleaseRelativePathDenied -RelativePath $file.RelativePath -Config $script:releaseConfig) | Should -BeFalse
        }
    }

    It 'scans the current tracked tree without treating tests and developer tools as package denylist violations' {
        $files = @(Get-WibCurrentTreeFiles -ProjectRoot $script:projectRoot)
        $files.Count | Should -BeGreaterThan 0
        $findings = @(Get-WibReleaseSafetyFindings -Files $files -Config $script:releaseConfig -SkipDenyPathCheck)
        $findings.Count | Should -Be 0
    }

    It 'does not include generated validation output in the release allowlist' {
        $paths = @(Get-WibReleaseSourceFiles -ProjectRoot $script:projectRoot -Config $script:releaseConfig -Version $script:version |
            ForEach-Object { $_.RelativePath })
        foreach ($bad in @('validation-result.json','dist','output','logs','cache','tests')) {
            @($paths | Where-Object { $_ -eq $bad -or $_ -like ($bad + '\*') }).Count | Should -Be 0
        }
    }

    It 'builds manifest data from independent version sources without personal metadata' {
        $manifest = Get-WibReleaseManifestData -ProjectRoot $script:projectRoot -ApplicationVersion $script:version
        $manifest.applicationVersion | Should -Be '0.2.3-alpha.1'
        $manifest.moduleVersion | Should -Be '0.2.3'
        $manifest.backendContractSchemaVersion | Should -Be 1
        $manifest.buildPlanSchemaVersion | Should -Be 1
        @($manifest.Keys) | Should -Be @('applicationVersion','moduleVersion','backendContractSchemaVersion','buildPlanSchemaVersion')
    }

    It 'documents that the safety scan is not a Git-history audit' {
        $matrix = Get-Content -LiteralPath (Join-Path $script:projectRoot 'docs\VALIDATION_MATRIX_EN.md') -Raw -Encoding UTF8
        $matrix | Should -Match 'not a Git-history audit'
    }
}
