$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Compact converter progress' {
    InModuleScope WindowsISOBuilder {
        BeforeEach {
            $script:WibConverterProgressActive = $false
            $script:WibConverterProgressPercent = 0
            $script:WibConverterBuildLogPath = Join-Path $TestDrive 'build-20260817-120000.log'
            $script:WibConverterDetailLogPath = ''
            Mock Write-Progress { }
        }

        It 'supports normal Write-Host calls without explicit colors on Windows PowerShell 5.1' {
            { Write-Host 'Windows ISO Builder' } | Should -Not -Throw
            { Write-Host '' } | Should -Not -Throw
        }

        It 'supports explicit console colors through the Write-Host wrapper' {
            { Write-Host 'Windows ISO Builder' -ForegroundColor Cyan } | Should -Not -Throw
            { Write-Host 'diagnostic' -ForegroundColor DarkGray } | Should -Not -Throw
        }

        It 'maps aria2 download percentage into the overall progress bar' {
            Start-WibConverterProgress
            Update-WibConverterProgressFromLine -Line '[#abcdef 2.0GiB/4.0GiB(50%) CN:16 DL:12MiB ETA:2m]'

            $script:WibConverterProgressPercent | Should -Be 47
            Assert-MockCalled Write-Progress -ParameterFilter {
                $Status -match '50%' -and $Status -match '12MiB'
            }

            Stop-WibConverterProgress
        }

        It 'writes suppressed converter output into a separate detailed log' {
            Start-WibConverterProgress
            $detailLog = $script:WibConverterDetailLogPath

            Update-WibConverterProgressFromLine -Line 'Downloading the UUP set...'
            Update-WibConverterProgressFromLine -Line '[#abcdef 1.0GiB/4.0GiB(25%) CN:16 DL:8MiB]'

            Test-Path -LiteralPath $detailLog | Should -BeTrue
            $content = Get-Content -LiteralPath $detailLog -Raw -Encoding UTF8
            $content | Should -Match 'Downloading the UUP set'
            $content | Should -Match '25%'

            Stop-WibConverterProgress
        }

        It 'switches to conversion stages after download progress' {
            Start-WibConverterProgress
            Update-WibConverterProgressFromLine -Line '[#abcdef 4.0GiB/4.0GiB(100%) CN:16 DL:8MiB]'
            Update-WibConverterProgressFromLine -Line 'Creating ISO image...'

            $script:WibConverterProgressPercent | Should -Be 96
            Assert-MockCalled Write-Progress -ParameterFilter {
                $Status -eq 'Создание ISO...'
            }

            Stop-WibConverterProgress
        }
    }
}

Describe 'Quick recommended menu scope' {
    It 'does not advertise unsupported Windows 7 or 8 choices' {
        $applicationPath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\Private\Application.ps1'
        $source = Get-Content -LiteralPath $applicationPath -Raw -Encoding UTF8

        $source | Should -Not -Match 'Windows 8\.1'
        $source | Should -Not -Match 'Windows 7'
        $source | Should -Match 'Windows 11 — рекомендуемая стабильная x64'
        $source | Should -Match 'Windows 10 — рекомендуемая стабильная x64'
    }
}
