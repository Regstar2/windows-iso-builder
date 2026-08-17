$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Quick recommended Windows selection' {
    InModuleScope WindowsISOBuilder {
        It 'prefers the newest mainstream Windows 11 H2 release over a newer specialized H1 release' {
            $script:quickBuilds = @(
                [pscustomobject]@{
                    Uuid = 'win11-24h2'
                    Title = 'Windows 11, version 24H2 (26100.9000)'
                    Product = 'Windows 11'
                    VersionLabel = '24H2'
                    Build = '26100.9000'
                    Architecture = 'amd64'
                    EntryType = 'Windows'
                    CreatedAt = [datetime]'2026-08-01'
                    IsPreview = $false
                },
                [pscustomobject]@{
                    Uuid = 'win11-25h2'
                    Title = 'Windows 11, version 25H2 (26200.9000)'
                    Product = 'Windows 11'
                    VersionLabel = '25H2'
                    Build = '26200.9000'
                    Architecture = 'amd64'
                    EntryType = 'Windows'
                    CreatedAt = [datetime]'2026-08-02'
                    IsPreview = $false
                },
                [pscustomobject]@{
                    Uuid = 'win11-26h1'
                    Title = 'Windows 11, version 26H1 (28000.2704)'
                    Product = 'Windows 11'
                    VersionLabel = '26H1'
                    Build = '28000.2704'
                    Architecture = 'amd64'
                    EntryType = 'Windows'
                    CreatedAt = [datetime]'2026-08-03'
                    IsPreview = $false
                },
                [pscustomobject]@{
                    Uuid = 'servicing'
                    Title = 'Cumulative Update for Windows 11 Version 25H2'
                    Product = 'Windows 11'
                    VersionLabel = '25H2'
                    Build = '26200.9999'
                    Architecture = 'amd64'
                    EntryType = 'Servicing'
                    CreatedAt = [datetime]'2026-08-04'
                    IsPreview = $false
                }
            )

            Mock Search-WibBuilds { return $script:quickBuilds }

            $selected = Get-WibQuickLatestBuild -Product 'Windows 11' -CacheDirectory $TestDrive
            $selected.Uuid | Should -Be 'win11-25h2'

            Assert-MockCalled Search-WibBuilds -Times 1 -Exactly -ParameterFilter {
                $Search -eq 'Windows 11' -and
                $Architecture -eq 'amd64' -and
                $ForceRefresh
            }
        }

        It 'falls back to the newest stable Windows 11 build if no mainstream H2 release exists' {
            $script:quickBuilds = @(
                [pscustomobject]@{
                    Uuid = 'win11-h1-only'
                    Title = 'Windows 11, version 26H1 (28000.2704)'
                    Product = 'Windows 11'
                    VersionLabel = '26H1'
                    Build = '28000.2704'
                    Architecture = 'amd64'
                    EntryType = 'Windows'
                    CreatedAt = [datetime]'2026-08-03'
                    IsPreview = $false
                }
            )

            Mock Search-WibBuilds { return $script:quickBuilds }
            Mock Write-WibWarning { }

            $selected = Get-WibQuickLatestBuild -Product 'Windows 11' -CacheDirectory $TestDrive
            $selected.Uuid | Should -Be 'win11-h1-only'

            Assert-MockCalled Write-WibWarning -Times 1 -Exactly -ParameterFilter {
                $Message -match 'H2-релиз'
            }
        }

        It 'does not cross Windows product families when selecting Windows 10' {
            $script:quickBuilds = @(
                [pscustomobject]@{
                    Uuid = 'win11-newer'
                    Title = 'Windows 11, version 25H2 (26200.9000)'
                    Product = 'Windows 11'
                    VersionLabel = '25H2'
                    Build = '26200.9000'
                    Architecture = 'amd64'
                    EntryType = 'Windows'
                    CreatedAt = [datetime]'2026-08-02'
                    IsPreview = $false
                },
                [pscustomobject]@{
                    Uuid = 'win10-22h2'
                    Title = 'Windows 10, version 22H2 (19045.7000)'
                    Product = 'Windows 10'
                    VersionLabel = '22H2'
                    Build = '19045.7000'
                    Architecture = 'amd64'
                    EntryType = 'Windows'
                    CreatedAt = [datetime]'2026-08-01'
                    IsPreview = $false
                }
            )

            Mock Search-WibBuilds { return $script:quickBuilds }

            $selected = Get-WibQuickLatestBuild -Product 'Windows 10' -CacheDirectory $TestDrive
            $selected.Uuid | Should -Be 'win10-22h2'
        }

        It 'fails clearly when UUP dump has no stable installable build' {
            Mock Search-WibBuilds {
                return @([pscustomobject]@{
                    Uuid = 'preview-only'
                    Title = 'Windows 11 Insider Preview 28000.1000'
                    Product = 'Windows 11'
                    VersionLabel = '26H1'
                    Build = '28000.1000'
                    Architecture = 'amd64'
                    EntryType = 'Windows'
                    CreatedAt = [datetime]'2026-08-03'
                    IsPreview = $true
                })
            }

            { Get-WibQuickLatestBuild -Product 'Windows 11' -CacheDirectory $TestDrive } |
                Should -Throw '*не вернул стабильную полноценную сборку Windows 11 x64*'
        }
    }
}
