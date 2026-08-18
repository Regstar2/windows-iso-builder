#requires -Version 5.1

Describe 'PowerShell 7 Backend Contract compatibility' {
    It 'runs GetVersion and offline RunPreflight through the machine entry point' {
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($null -eq $pwsh) {
            Set-ItResult -Skipped -Because 'pwsh is not installed.'
            return
        }

        $projectRoot = Split-Path -Parent $PSScriptRoot
        $entryScript = Join-Path $projectRoot 'Invoke-WibBackend.ps1'
        $smokeRoot = Join-Path ([IO.Path]::GetTempPath()) ('wib-ps7-test-' + [Guid]::NewGuid().ToString('N'))
        $cache = Join-Path $smokeRoot 'cache'
        $output = Join-Path $smokeRoot 'output'

        try {
            [IO.Directory]::CreateDirectory($cache) | Out-Null
            [IO.Directory]::CreateDirectory($output) | Out-Null

            $versionRequest = Join-Path $smokeRoot 'version-request.json'
            $versionResponse = Join-Path $smokeRoot 'version-response.json'
            $versionObject = [ordered]@{
                schemaVersion = 1
                requestId = 'ps7-version-test'
                command = 'GetVersion'
                arguments = [ordered]@{}
            }
            [IO.File]::WriteAllText($versionRequest, ($versionObject | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))

            & $pwsh.Source -NoLogo -NoProfile -File $entryScript -RequestFile $versionRequest -ResponseFile $versionResponse
            $versionExitCode = $LASTEXITCODE
            $versionText = if ([IO.File]::Exists($versionResponse)) { [IO.File]::ReadAllText($versionResponse, [Text.Encoding]::UTF8) } else { '' }
            if ($versionExitCode -ne 0) {
                throw ('PowerShell 7 GetVersion failed with exit code {0}. Response: {1}' -f $versionExitCode, $versionText)
            }
            $version = $versionText | ConvertFrom-Json
            $version.success | Should -BeTrue
            $version.applicationVersion | Should -Be '0.2.2-alpha.1'

            $preflightRequest = Join-Path $smokeRoot 'preflight-request.json'
            $preflightResponse = Join-Path $smokeRoot 'preflight-response.json'
            $plan = [ordered]@{
                schemaVersion = 1
                applicationVersion = '0.2.2-alpha.1'
                createdAt = (Get-Date).ToUniversalTime().ToString('o')
                build = [ordered]@{
                    uuid = '00000000-0000-0000-0000-000000000000'
                    title = 'PowerShell 7 backend smoke'
                    product = 'Windows 11'
                    versionLabel = 'smoke'
                    build = '0.0'
                    architecture = 'amd64'
                    isPreview = $false
                }
                language = 'ru-ru'
                editions = @('Professional')
                sourceEdition = 'Professional'
                virtualEditions = @()
                imageFormat = 'ESD'
                addUpdates = $true
                cleanup = $true
                netFx3 = $false
                outputDirectory = $output
                cacheDirectory = $cache
                removeWorkAfterSuccess = $false
            }
            $preflightObject = [ordered]@{
                schemaVersion = 1
                requestId = 'ps7-preflight-test'
                command = 'RunPreflight'
                arguments = [ordered]@{
                    buildPlan = $plan
                    onlineChecks = $false
                }
            }
            [IO.File]::WriteAllText($preflightRequest, ($preflightObject | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))

            & $pwsh.Source -NoLogo -NoProfile -File $entryScript -RequestFile $preflightRequest -ResponseFile $preflightResponse
            $preflightExitCode = $LASTEXITCODE
            $preflightText = if ([IO.File]::Exists($preflightResponse)) { [IO.File]::ReadAllText($preflightResponse, [Text.Encoding]::UTF8) } else { '' }
            if ($preflightExitCode -ne 0) {
                throw ('PowerShell 7 RunPreflight failed with exit code {0}. Response: {1}' -f $preflightExitCode, $preflightText)
            }
            $preflight = $preflightText | ConvertFrom-Json
            $preflight.success | Should -BeTrue
            $preflight.data.PSObject.Properties.Name | Should -Contain 'ready'
            @($preflight.data.checks).Count | Should -BeGreaterThan 0
        }
        finally {
            if ([IO.Directory]::Exists($smokeRoot)) {
                [IO.Directory]::Delete($smokeRoot, $true)
            }
        }
    }
}
