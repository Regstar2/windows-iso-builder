#requires -Version 5.1

Describe 'Unified release validation' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:orchestratorPath = Join-Path $script:projectRoot 'tools\Invoke-ReleaseValidation.ps1'
        $script:commonPath = Join-Path $script:projectRoot 'tools\ReleaseValidation.Common.ps1'
        $script:reportPath = Join-Path $script:projectRoot 'tools\ReleaseValidation.Report.ps1'
        $script:packageSmokePath = Join-Path $script:projectRoot 'tools\Test-ReleasePackage.ps1'
        $script:packagerPath = Join-Path $script:projectRoot 'tools\New-ReleasePackage.ps1'
        $script:configPath = Join-Path $script:projectRoot 'tools\ReleasePackageConfig.psd1'
    }

    It 'defines quick and full modes plus result persistence' {
        $content = Get-Content -LiteralPath $script:orchestratorPath -Raw -Encoding UTF8
        $content | Should -Match '\[switch\]\$Full'
        $content | Should -Match '\[switch\]\$Quick'
        $content | Should -Match '\[switch\]\$KeepArtifacts'
        $content | Should -Match 'validation-result\.json'
        $content | Should -Match 'Resolve-WibValidationMode'
        $content | Should -Match 'New-WibValidationWorkspace'
        $content | Should -Match 'New-WibValidationReport'
        $content | Should -Match 'Save-WibValidationReport'
        $content | Should -Match 'exit \$report\.summary\.exitCode'
    }

    It 'keeps the release package layout driven by one config' {
        $orchestrator = Get-Content -LiteralPath $script:orchestratorPath -Raw -Encoding UTF8
        $packager = Get-Content -LiteralPath $script:packagerPath -Raw -Encoding UTF8
        $packageSmoke = Get-Content -LiteralPath $script:packageSmokePath -Raw -Encoding UTF8
        $orchestrator | Should -Match 'ReleasePackageConfig\.psd1'
        $packager | Should -Match 'ReleasePackageConfig\.psd1'
        $packageSmoke | Should -Match 'ReleasePackageConfig\.psd1'
    }

    It 'guards full validation with a baseline gate before expensive E2E work' {
        $content = Get-Content -LiteralPath $script:orchestratorPath -Raw -Encoding UTF8
        $content | Should -Match 'full-baseline-gate'
        $content | Should -Match 'if \(\$mode -eq ''Full'' -and \$baselineHealthy\)'
        $content | Should -Match 'release-package-smoke'
        $content | Should -Match 'quick-real-windows11-esd'
    }

    It 'reruns source and runtime safety checks against the produced package' {
        $content = Get-Content -LiteralPath $script:orchestratorPath -Raw -Encoding UTF8
        $content | Should -Match 'current-tree-safety-scan'
        $content | Should -Match 'release-tree-safety-scan'
        $content | Should -Match 'release-package-smoke'
        $content | Should -Match 'Get-WibReleaseSafetyFindings'
        $content | Should -Match 'Test-WibDeniedPath'
    }

    It 'uses isolated validation roots and machine-readable reports' {
        $common = Get-Content -LiteralPath $script:commonPath -Raw -Encoding UTF8
        $report = Get-Content -LiteralPath $script:reportPath -Raw -Encoding UTF8
        $common | Should -Match '\$env:TEMP'
        $common | Should -Match 'Join-Path \$root ''validation'''
        $report | Should -Match 'ConvertTo-Json -Depth'
        $report | Should -Match 'Set-Content -LiteralPath'
    }

    It 'preserves GUI publishing and validates the packaged backend handshake' {
        $orchestrator = Get-Content -LiteralPath $script:orchestratorPath -Raw -Encoding UTF8
        $packager = Get-Content -LiteralPath $script:packagerPath -Raw -Encoding UTF8
        $orchestrator | Should -Match 'Build-Gui\.ps1'
        $packager | Should -Match 'WindowsISOBuilder\.exe'
        $packager | Should -Match '--backend-smoke'
        $packager | Should -Match '\$smokeProcess\s*=\s*Start-Process -FilePath \$guiExe'
        $packager | Should -Match '-Wait\s+-PassThru'
        $packager | Should -Match 'if \(\$smokeProcess\.ExitCode -ne 0\)'
    }

    It 'fails closed if the packaged GUI handshake cannot be executed' {
        $packager = Get-Content -LiteralPath $script:packagerPath -Raw -Encoding UTF8
        $packager | Should -Match 'if \(-not \(Test-Path -LiteralPath \$guiExe -PathType Leaf\)\)'
        $packager | Should -Match '\$smokeProcess\s*=\s*Start-Process -FilePath \$guiExe'
        $packager | Should -Match '-Wait\s+-PassThru'
        $packager | Should -Match 'throw \(''Packaged GUI backend handshake failed'
    }
}
