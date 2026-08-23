#requires -Version 5.1
Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Real E2E release hardening' {
    InModuleScope WindowsISOBuilder {
        It 'maps WIM and ESD to the documented converter automation choices' {
            $configPath = Join-Path $TestDrive 'ConvertConfig.ini'
            @(
                '[convert-UUP]',
                'AutoStart=0',
                'AutoExit=0',
                'AddUpdates=0',
                'Cleanup=0',
                'NetFx3=0',
                'SkipWinRE=0',
                'wim2esd=0',
                'StartVirtual=0',
                '',
                '[create_virtual_editions]',
                'vAutoStart=0',
                'vAutoEditions=',
                'vwim2esd=0'
            ) | Set-Content -LiteralPath $configPath -Encoding ASCII

            $esdPlan = [pscustomobject]@{
                AddUpdates=$true; Cleanup=$false; NetFx3=$false; ImageFormat='ESD'; VirtualEditions=@()
            }
            Set-WibConverterConfiguration -Path $configPath -Plan $esdPlan
            $esd = Get-Content -LiteralPath $configPath -Raw
            $esd | Should -Match '(?m)^AutoStart=2$'
            $esd | Should -Match '(?m)^wim2esd=1$'
            $esd | Should -Match '(?m)^Cleanup=0$'

            $wimPlan = [pscustomobject]@{
                AddUpdates=$true; Cleanup=$true; NetFx3=$false; ImageFormat='WIM'; VirtualEditions=@()
            }
            Set-WibConverterConfiguration -Path $configPath -Plan $wimPlan
            $wim = Get-Content -LiteralPath $configPath -Raw
            $wim | Should -Match '(?m)^AutoStart=1$'
            $wim | Should -Match '(?m)^wim2esd=0$'
            $wim | Should -Match '(?m)^Cleanup=1$'
        }

        It 'does not request redundant wim-to-esd conversion when updates are disabled' {
            $configPath = Join-Path $TestDrive 'NoUpdates.ini'
            @(
                '[convert-UUP]', 'AutoStart=0', 'AutoExit=0', 'AddUpdates=0', 'Cleanup=0',
                'NetFx3=0', 'SkipWinRE=0', 'wim2esd=0', 'StartVirtual=0'
            ) | Set-Content -LiteralPath $configPath -Encoding ASCII
            $plan = [pscustomobject]@{
                AddUpdates=$false; Cleanup=$false; NetFx3=$false; ImageFormat='ESD'; VirtualEditions=@()
            }
            Set-WibConverterConfiguration -Path $configPath -Plan $plan
            $content = Get-Content -LiteralPath $configPath -Raw
            $content | Should -Match '(?m)^AutoStart=2$'
            $content | Should -Match '(?m)^wim2esd=0$'
        }

        It 'rejects a mounted ISO whose install image format does not match the plan' {
            $savedReader = $script:WibBaseGetIsoMetadata
            try {
                $script:WibExpectedImageFormat = 'ESD'
                $script:WibBaseGetIsoMetadata = {
                    param([string]$IsoPath)
                    [pscustomobject]@{
                        Mounted=$true; HasBootWim=$true; HasInstallWim=$true; HasInstallEsd=$false; Images=@(); Warning=''
                    }
                }

                $caught = $null
                try { Get-WibIsoMetadata -IsoPath 'fake.iso' | Out-Null } catch { $caught = $_.Exception }
                $caught | Should -Not -BeNullOrEmpty
                [string]$caught.Data['WibErrorCode'] | Should -Be 'ISO_VALIDATION_FAILED'
                [string]$caught.Data['WibStage'] | Should -Be 'verify'
            }
            finally {
                $script:WibBaseGetIsoMetadata = $savedReader
                $script:WibExpectedImageFormat = ''
            }
        }

        It 'accepts a mounted ISO that contains the requested ESD image' {
            $savedReader = $script:WibBaseGetIsoMetadata
            try {
                $script:WibExpectedImageFormat = 'ESD'
                $script:WibBaseGetIsoMetadata = {
                    param([string]$IsoPath)
                    [pscustomobject]@{
                        Mounted=$true; HasBootWim=$true; HasInstallWim=$false; HasInstallEsd=$true; Images=@(); Warning=''
                    }
                }

                $result = Get-WibIsoMetadata -IsoPath 'fake.iso'
                $result.HasInstallEsd | Should -BeTrue
            }
            finally {
                $script:WibBaseGetIsoMetadata = $savedReader
                $script:WibExpectedImageFormat = ''
            }
        }

        It 'defaults backend cleanup to false while keeping explicit cleanup supported' {
            $build = [pscustomobject]@{
                Uuid='00000000-0000-0000-0000-000000000001'; Title='Windows 11, version 25H2';
                Product='Windows 11'; VersionLabel='25H2'; Build='26200.1'; Architecture='amd64'; IsPreview=$false
            }
            $defaultPlan = New-WibBuildPlan -Build $build -Language 'ru-ru' -Editions @('Professional') -OutputDirectory (Join-Path $TestDrive 'out1') -CacheDirectory (Join-Path $TestDrive 'cache1')
            $defaultPlan.Cleanup | Should -BeFalse

            $explicitPlan = New-WibBuildPlan -Build $build -Language 'ru-ru' -Editions @('Professional') -Cleanup $true -OutputDirectory (Join-Path $TestDrive 'out2') -CacheDirectory (Join-Path $TestDrive 'cache2')
            $explicitPlan.Cleanup | Should -BeTrue
        }

        It 'writes ISO-8601 timestamps to detailed converter diagnostics' {
            $script:WibConverterDetailLogPath = Join-Path $TestDrive 'converter.log'
            Write-WibConverterDetailLine -Line '=== Creating install.wim . . .'
            $line = Get-Content -LiteralPath $script:WibConverterDetailLogPath -First 1
            $line | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.'
            $line | Should -Match "`t=== Creating install\.wim \. \. \.$"
            $script:WibConverterDetailLogPath = ''
        }
    }

    It 'defaults the WPF cleanup option to false' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $source = Get-Content -LiteralPath (Join-Path $projectRoot 'src\WindowsISOBuilder.Gui\ViewModels\MainViewModel.cs') -Raw -Encoding UTF8
        $source | Should -Match 'private bool _cleanup;'
        $source | Should -Not -Match 'private bool _cleanup\s*=\s*true;'
    }
}
