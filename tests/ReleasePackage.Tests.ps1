#requires -Version 5.1

Describe 'Release package validation' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:projectRoot 'tools\ReleaseValidation.Common.ps1')
        $script:releaseConfig = Import-WibReleaseValidationConfig -ProjectRoot $script:projectRoot
        $script:releaseVersion = [IO.File]::ReadAllText((Join-Path $script:projectRoot 'VERSION'), [Text.Encoding]::ASCII).Trim()
        $script:packageOutput = Join-Path $TestDrive 'package-output'
        & (Join-Path $script:projectRoot 'tools\New-ReleasePackage.ps1') -OutputDirectory $script:packageOutput | Out-Null
        $script:zipPath = Join-Path $script:packageOutput ('windows-iso-builder-v{0}.zip' -f $script:releaseVersion)
        $script:checksumPath = "$script:zipPath.sha256"
        $script:extractRoot = Join-Path $TestDrive 'extracted'
        Expand-Archive -LiteralPath $script:zipPath -DestinationPath $script:extractRoot -Force
        $script:packageRoot = Join-Path $script:extractRoot ('windows-iso-builder-v{0}' -f $script:releaseVersion)
    }

    AfterAll {
        Remove-Module WindowsISOBuilder -Force -ErrorAction SilentlyContinue
    }

    It 'creates an openable ZIP and matching SHA-256 checksum' {
        Test-Path -LiteralPath $script:zipPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:checksumPath -PathType Leaf | Should -BeTrue
        $checksumText = [IO.File]::ReadAllText($script:checksumPath, [Text.Encoding]::UTF8)
        $checksumText | Should -Match '^([A-Fa-f0-9]{64})\s+'
        $expectedHash = $matches[1].ToUpperInvariant()
        (Get-FileHash -LiteralPath $script:zipPath -Algorithm SHA256).Hash.ToUpperInvariant() | Should -Be $expectedHash

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($script:zipPath)
        try { @($archive.Entries).Count | Should -BeGreaterThan 0 }
        finally { $archive.Dispose() }
    }

    It 'contains exactly the allowlisted logical source files plus release-manifest.json' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($script:zipPath)
        try {
            $prefix = ('windows-iso-builder-v{0}/' -f $script:releaseVersion)
            $actual = @($archive.Entries | ForEach-Object { ([string]$_.FullName).Replace('\','/') } |
                Where-Object { $_ -and -not $_.EndsWith('/') } |
                ForEach-Object {
                    $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
                    $_.Substring($prefix.Length).Replace('/','\')
                } | Sort-Object -Unique)
        }
        finally { $archive.Dispose() }

        $source = @(Get-WibReleaseSourceFiles -ProjectRoot $script:projectRoot -Config $script:releaseConfig -Version $script:releaseVersion |
            ForEach-Object { $_.RelativePath } | Sort-Object -Unique)
        $expected = @($source + 'release-manifest.json' | Sort-Object -Unique)
        $actual | Should -Be $expected
        foreach ($path in $actual) {
            (Test-WibReleaseRelativePathDenied -RelativePath $path -Config $script:releaseConfig) | Should -BeFalse
        }
    }

    It 'generates the expected release manifest versions' {
        $manifestPath = Join-Path $script:packageRoot 'release-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifest.applicationVersion | Should -Be '0.2.3-alpha.1'
        $manifest.moduleVersion | Should -Be '0.2.3'
        $manifest.backendContractSchemaVersion | Should -Be 1
        $manifest.buildPlanSchemaVersion | Should -Be 1
    }

    It 'contains all required runtime files and no obvious secret or personal-path findings' {
        foreach ($required in @($script:releaseConfig.RequiredPackageFiles)) {
            Test-Path -LiteralPath (Join-Path $script:packageRoot ([string]$required)) | Should -BeTrue
        }
        $files = @(Get-WibFilesUnderRoot -Root $script:packageRoot)
        @(Get-WibReleaseSafetyFindings -Files $files -Config $script:releaseConfig).Count | Should -Be 0
    }

    It 'imports the packaged module from the extracted package instead of the source checkout' {
        Remove-Module WindowsISOBuilder -Force -ErrorAction SilentlyContinue
        $packagedModule = Join-Path $script:packageRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psd1'
        Import-Module $packagedModule -Force
        $loadedModule = Get-Module WindowsISOBuilder | Select-Object -First 1
        $loadedModule | Should -Not -BeNullOrEmpty
        [IO.Path]::GetFullPath([string]$loadedModule.Path).StartsWith(
            [IO.Path]::GetFullPath($script:packageRoot), [StringComparison]::OrdinalIgnoreCase
        ) | Should -BeTrue
    }

    It 'runs packaged GetVersion and offline RunPreflight through the public backend function' {
        Remove-Module WindowsISOBuilder -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:packageRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psd1') -Force

        $requestPath = Join-Path $TestDrive 'package-version-request.json'
        $responsePath = Join-Path $TestDrive 'package-version-response.json'
        $versionRequest = [ordered]@{ schemaVersion=1; requestId='package-version'; command='GetVersion'; arguments=[ordered]@{} }
        [IO.File]::WriteAllText($requestPath, ($versionRequest | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
        Invoke-WibBackendRequest -RequestFile $requestPath -ResponseFile $responsePath | Out-Null
        $version = Get-Content -LiteralPath $responsePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $version.success | Should -BeTrue
        $version.applicationVersion | Should -Be '0.2.3-alpha.1'

        $cache = Join-Path $TestDrive 'package-cache'
        $output = Join-Path $TestDrive 'package-output-dir'
        New-Item -ItemType Directory -Path $cache,$output -Force | Out-Null
        $plan = [ordered]@{
            schemaVersion=1; applicationVersion='0.2.3-alpha.1'; createdAt='2026-08-18T00:00:00Z';
            build=[ordered]@{ uuid='package-smoke'; title='Package smoke'; product='Windows 11'; versionLabel='smoke'; build='0.0'; architecture='amd64'; entryType='Windows'; createdAt='2026-08-18T00:00:00Z'; isPreview=$false };
            language='ru-ru'; editions=@('Professional'); sourceEdition='Professional'; virtualEditions=@(); imageFormat='ESD';
            addUpdates=$true; cleanup=$true; netFx3=$false; outputDirectory=$output; cacheDirectory=$cache; removeWorkAfterSuccess=$false
        }
        $preflightRequestPath = Join-Path $TestDrive 'package-preflight-request.json'
        $preflightResponsePath = Join-Path $TestDrive 'package-preflight-response.json'
        $preflightRequest = [ordered]@{ schemaVersion=1; requestId='package-preflight'; command='RunPreflight'; arguments=[ordered]@{ buildPlan=$plan; onlineChecks=$false } }
        [IO.File]::WriteAllText($preflightRequestPath, ($preflightRequest | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
        Invoke-WibBackendRequest -RequestFile $preflightRequestPath -ResponseFile $preflightResponsePath | Out-Null
        $preflight = Get-Content -LiteralPath $preflightResponsePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $preflight.success | Should -BeTrue
        $preflight.data.PSObject.Properties.Name | Should -Contain 'ready'
        @($preflight.data.checks).Count | Should -BeGreaterThan 0
    }
}
