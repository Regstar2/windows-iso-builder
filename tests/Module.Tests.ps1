$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'WindowsISOBuilder module' {
    It 'imports on PowerShell 5.1-compatible syntax' {
        Get-Module WindowsISOBuilder | Should -Not -BeNullOrEmpty
    }

    It 'exports the public commands' {
        Get-Command Start-WibInteractive -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command Search-WibBuilds -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command Invoke-WibBuildPlan -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    InModuleScope WindowsISOBuilder {
        It 'detects preview titles' {
            Test-WibPreviewTitle -Title 'Windows 11 Insider Preview 26200.1000' | Should -BeTrue
            Test-WibPreviewTitle -Title 'Windows 11, version 24H2 (26100.1)' | Should -BeFalse
        }

        It 'extracts version labels without a hardcoded catalog' {
            Get-WibVersionLabel -Title 'Windows 10, version 22H2 (19045.1)' | Should -Be '22H2'
            Get-WibVersionLabel -Title 'Windows build 19045.1' | Should -Be ''
        }

        It 'normalizes array API build responses' {
            $input = @(
                [pscustomobject]@{ uuid = 'a'; title = 'Windows 10'; build = '19045.1'; arch = 'amd64'; created = 1 },
                [pscustomobject]@{ uuid = 'b'; title = 'Windows 11'; build = '22621.1'; arch = 'amd64'; created = 2 }
            )
            @(ConvertFrom-WibBuildCollection -Builds $input).Count | Should -Be 2
        }

        It 'normalizes keyed API build responses' {
            $input = [pscustomobject]@{
                'uuid-a' = [pscustomobject]@{ title = 'Windows 10'; build = '19045.1'; arch = 'amd64'; created = 1 }
            }
            $result = @(ConvertFrom-WibBuildCollection -Builds $input)
            $result.Count | Should -Be 1
            $result[0].uuid | Should -Be 'uuid-a'
        }

        It 'patches converter configuration values' {
            $path = Join-Path $TestDrive 'ConvertConfig.ini'
            @(
                '[convert-UUP]',
                'AutoStart =0',
                'StartVirtual =0',
                'wim2esd =0',
                '',
                '[create_virtual_editions]',
                'vAutoStart=0',
                'vAutoEditions=',
                'vwim2esd=0'
            ) | Set-Content -LiteralPath $path -Encoding ASCII

            $plan = [pscustomobject]@{
                AddUpdates = $true
                Cleanup = $true
                NetFx3 = $false
                ImageFormat = 'ESD'
                VirtualEditions = @('Core', 'Education')
            }
            Set-WibConverterConfiguration -Path $path -Plan $plan
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Match '(?m)^AutoStart=1$'
            $content | Should -Match '(?m)^StartVirtual=1$'
            $content | Should -Match '(?m)^wim2esd=1$'
            $content | Should -Match '(?m)^vAutoEditions=Core,Education$'
        }

        It 'creates a plan with the first edition as source' {
            $build = [pscustomobject]@{
                Uuid = '00000000-0000-0000-0000-000000000000'
                Title = 'Windows 10, version 22H2'
                Product = 'Windows 10'
                VersionLabel = '22H2'
                Build = '19045.1'
                Architecture = 'amd64'
                IsPreview = $false
            }
            $output = Join-Path $TestDrive 'output'
            $cache = Join-Path $TestDrive 'cache'
            $plan = New-WibBuildPlan -Build $build -Language 'ru-ru' -Editions @('Core', 'Professional') -OutputDirectory $output -CacheDirectory $cache
            $plan.SourceEdition | Should -Be 'Core'
            @($plan.VirtualEditions) | Should -Contain 'Professional'
        }
    }
}
