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
            Get-WibVersionLabel -Title 'Windows 10, version 1809 (17763.1)' | Should -Be '1809'
            Get-WibVersionLabel -Title 'Windows Server 2025 (26100.1)' | Should -Be '2025'
        }

        It 'normalizes compact Windows product searches' {
            ConvertTo-WibApiSearchText -Search 'windows11' | Should -Be 'Windows 11'
            ConvertTo-WibApiSearchText -Search 'Win10 22H2' | Should -Be 'Windows 10 22H2'
            ConvertTo-WibApiSearchText -Search '  windows   server 2025  ' | Should -Be 'Windows Server 2025'
            ConvertTo-WibApiSearchText -Search '26100.1' | Should -Be '26100.1'
        }

        It 'matches requested Windows product families exactly' {
            Test-WibBuildMatchesSearch -Search 'windows10' -Title 'Windows 10, version 22H2 (19045.1)' -Build '19045.1' | Should -BeTrue
            Test-WibBuildMatchesSearch -Search 'windows10' -Title 'Windows 11, version 24H2 (26100.1)' -Build '26100.1' | Should -BeFalse
            Test-WibBuildMatchesSearch -Search 'windows10' -Title 'Windows Server 2025 (26100.1)' -Build '26100.1' | Should -BeFalse
            Test-WibBuildMatchesSearch -Search 'windows 10 22H2' -Title 'Windows 10, version 21H2 (19044.1)' -Build '19044.1' | Should -BeFalse
            Test-WibBuildMatchesSearch -Search 'windows 10 22H2' -Title 'Windows 10, version 22H2 (19045.1)' -Build '19045.1' | Should -BeTrue
        }

        It 'classifies Windows 10X separately from Windows 10' {
            Get-WibProductLabel -Title 'Windows 10X Insider Preview 20279.1' | Should -Be 'Windows 10X'
            Get-WibProductLabel -Title 'Windows 10, version 22H2' | Should -Be 'Windows 10'
        }

        It 'does not retry permanent HTTP client errors' {
            Test-WibRetryableHttpStatusCode -StatusCode 400 | Should -BeFalse
            Test-WibRetryableHttpStatusCode -StatusCode 404 | Should -BeFalse
            Test-WibRetryableHttpStatusCode -StatusCode 408 | Should -BeTrue
            Test-WibRetryableHttpStatusCode -StatusCode 429 | Should -BeTrue
            Test-WibRetryableHttpStatusCode -StatusCode 500 | Should -BeTrue
            Test-WibRetryableHttpStatusCode -StatusCode $null | Should -BeTrue
        }

        It 'extracts API error codes from HTTP response bodies' {
            $body = '{"response":{"error":"SEARCH_NO_RESULTS"},"jsonApiVersion":"0.4.1"}'
            ConvertFrom-WibApiErrorBody -Body $body | Should -Be 'SEARCH_NO_RESULTS'
            ConvertFrom-WibApiErrorBody -Body 'Bad gateway' | Should -Be 'Bad gateway'
            ConvertFrom-WibApiErrorBody -Body '' | Should -Be ''
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

        It 'moves to the next page and selects its first build' {
            $script:testBuilds = @(1..85 | ForEach-Object {
                [pscustomobject]@{
                    Uuid = ('uuid-{0}' -f $_)
                    Build = ('{0}.1' -f (10000 + $_))
                    Architecture = 'amd64'
                    CreatedAt = [datetime]'2026-01-01'
                    Title = ('Windows 11 build {0}.1' -f (10000 + $_))
                    IsPreview = $false
                }
            })
            $script:readHostResponses = @('windows 11', '>', '')
            $script:readHostPosition = 0

            Mock Select-WibArchitecture { 'amd64' }
            Mock Read-WibYesNo { $false }
            Mock Search-WibBuilds { $script:testBuilds }
            Mock Read-Host {
                $response = $script:readHostResponses[$script:readHostPosition]
                $script:readHostPosition++
                return $response
            }
            Mock Write-Host { }

            $selected = Select-WibBuildInteractive -CacheDirectory $TestDrive
            $selected.Uuid | Should -Be 'uuid-41'
        }

        It 'returns to the main menu when build selection is cancelled' {
            $script:testBuilds = @([pscustomobject]@{
                Uuid = 'uuid-1'
                Build = '10001.1'
                Architecture = 'amd64'
                CreatedAt = [datetime]'2026-01-01'
                Title = 'Windows 11 build 10001.1'
                IsPreview = $false
            })
            $script:readHostResponses = @('windows 11', '0')
            $script:readHostPosition = 0

            Mock Select-WibArchitecture { 'amd64' }
            Mock Read-WibYesNo { $false }
            Mock Search-WibBuilds { $script:testBuilds }
            Mock Read-Host {
                $response = $script:readHostResponses[$script:readHostPosition]
                $script:readHostPosition++
                return $response
            }
            Mock Write-Host { }

            Select-WibBuildInteractive -CacheDirectory $TestDrive | Should -BeNullOrEmpty
        }

        It 'renders build results as a bordered table without wrapped rows' {
            $builds = @(
                [pscustomobject]@{
                    Uuid = 'uuid-1'
                    Build = '26100.8973'
                    Architecture = 'amd64'
                    CreatedAt = [datetime]'2026-07-29'
                    Title = 'Windows 11, version 24H2 with an intentionally very long title that must be truncated'
                    IsPreview = $false
                },
                [pscustomobject]@{
                    Uuid = 'uuid-2'
                    Build = '26200.8973'
                    Architecture = 'amd64'
                    CreatedAt = [datetime]'2026-07-29'
                    Title = 'Windows 11 Insider Preview'
                    IsPreview = $true
                }
            )

            $lines = @(Get-WibBuildTableLines -Builds $builds -StartIndex 0 -EndIndex 1 -MaximumWidth 80)
            $lines[0].StartsWith('┌') | Should -BeTrue
            $lines[1] | Should -Match '№'
            $lines[1] | Should -Match 'Сборка'
            $lines[1] | Should -Match 'Арх\.'
            $lines[1] | Should -Match 'Дата'
            $lines[1] | Should -Match 'Тип'
            $lines[1] | Should -Match 'Название'
            $lines[-1].StartsWith('└') | Should -BeTrue
            ($lines -join "`n") | Should -Match '…'
            foreach ($line in $lines) {
                ($line.Length -le 80) | Should -BeTrue
                $line | Should -Not -Match "[`r`n]"
            }
        }


        It 'classifies full Windows builds separately from servicing packages' {
            Get-WibBuildEntryType -Title 'Windows 10 build 19564.1005' | Should -Be 'Windows'
            Get-WibBuildEntryType -Title 'Feature update to Windows 10, version 22H2 (19045.7548)' | Should -Be 'Windows'
            Get-WibBuildEntryType -Title 'Windows 11, version 24H2 (26100.8973)' | Should -Be 'Windows'
            Get-WibBuildEntryType -Title 'Cumulative Update for Windows 10 Version 22H2 (19045.7548)' | Should -Be 'Servicing'
            Get-WibBuildEntryType -Title '.NET Framework Security Update for Windows 11 - KB5101002' | Should -Be 'Servicing'
            Get-WibBuildEntryType -Title 'Windows 10 Team feature package' | Should -Be 'Other'
        }

        It 'sorts complete Windows builds before servicing packages' {
            $builds = @(
                [pscustomobject]@{ Build='19045.7548'; CreatedAt=[datetime]'2026-07-15'; Title='Cumulative Update for Windows 10 Version 22H2 (19045.7548)'; EntryType='Servicing'; WibOriginalOrder=0 },
                [pscustomobject]@{ Build='19564.1005'; CreatedAt=[datetime]'2020-06-23'; Title='Windows 10 build 19564.1005'; EntryType='Windows'; WibOriginalOrder=1 },
                [pscustomobject]@{ Build='19045.7548'; CreatedAt=[datetime]'2026-07-14'; Title='Feature update to Windows 10, version 22H2 (19045.7548)'; EntryType='Windows'; WibOriginalOrder=2 }
            )
            $sorted = @(Sort-WibBuildCatalog -Builds $builds -Column Type -Direction Ascending)
            $sorted[0].EntryType | Should -Be 'Windows'
            $sorted[1].EntryType | Should -Be 'Windows'
            $sorted[-1].EntryType | Should -Be 'Servicing'
            $sorted[0].Build | Should -Be '19045.7548'
        }

        It 'sorts build catalog by date and build' {
            $builds = @(
                [pscustomobject]@{ Build='19045.1'; Architecture='amd64'; CreatedAt=[datetime]'2025-01-01'; Title='B'; WibOriginalOrder=0 },
                [pscustomobject]@{ Build='26100.2'; Architecture='amd64'; CreatedAt=[datetime]'2026-01-01'; Title='A'; WibOriginalOrder=1 },
                [pscustomobject]@{ Build='22631.3'; Architecture='arm64'; CreatedAt=[datetime]'2024-01-01'; Title='C'; WibOriginalOrder=2 }
            )
            $byDate = @(Sort-WibBuildCatalog -Builds $builds -Column Date -Direction Descending)
            $byDate[0].Build | Should -Be '26100.2'
            $byBuild = @(Sort-WibBuildCatalog -Builds $builds -Column Build -Direction Ascending)
            $byBuild[0].Build | Should -Be '19045.1'
            $byBuild[-1].Build | Should -Be '26100.2'
        }

        It 'selects newest installable build instead of a newer servicing-only entry' {
            $builds = @(
                [pscustomobject]@{ Build='26100.9999'; CreatedAt=[datetime]'2026-08-07'; Title='.NET Framework Security Update for Windows 11'; VersionLabel='24H2'; EntryType='Servicing' },
                [pscustomobject]@{ Build='26100.9000'; CreatedAt=[datetime]'2026-08-06'; Title='Windows 11, version 24H2 (26100.9000)'; VersionLabel='24H2'; EntryType='Windows' },
                [pscustomobject]@{ Build='26100.8000'; CreatedAt=[datetime]'2026-08-01'; Title='Windows 11, version 24H2 (26100.8000)'; VersionLabel='24H2'; EntryType='Windows' }
            )
            (Get-WibNewestBuild -Builds $builds).Build | Should -Be '26100.9000'
        }

        It 'prefers the newest Windows release family over the newest servicing date' {
            $builds = @(
                [pscustomobject]@{ Build='17763.9020'; CreatedAt=[datetime]'2026-07-14'; Title='Feature update to Windows 10, version 1809 (17763.9020)'; VersionLabel='1809'; EntryType='Windows' },
                [pscustomobject]@{ Build='19044.7548'; CreatedAt=[datetime]'2026-07-14'; Title='Feature update to Windows 10, version 21H2 (19044.7548)'; VersionLabel='21H2'; EntryType='Windows' },
                [pscustomobject]@{ Build='19045.7548'; CreatedAt=[datetime]'2026-07-14'; Title='Feature update to Windows 10, version 22H2 (19045.7548)'; VersionLabel='22H2'; EntryType='Windows' },
                [pscustomobject]@{ Build='19564.1005'; CreatedAt=[datetime]'2020-06-23'; Title='Windows 10 build 19564.1005'; VersionLabel=''; EntryType='Windows' }
            )
            (Get-WibNewestBuild -Builds $builds).Build | Should -Be '19045.7548'
            $ranked = @(Sort-WibBuildCatalog -Builds $builds -Column Relevance -Direction Descending)
            $ranked[0].VersionLabel | Should -Be '22H2'
            $ranked[1].VersionLabel | Should -Be '21H2'
            $ranked[2].VersionLabel | Should -Be '1809'
            $ranked[3].Build | Should -Be '19564.1005'
        }

        It 'ranks Windows 11 release labels dynamically without a hardcoded catalog' {
            $builds = @(
                [pscustomobject]@{ Build='26100.9000'; CreatedAt=[datetime]'2026-08-01'; Title='Windows 11, version 24H2 (26100.9000)'; VersionLabel='24H2'; EntryType='Windows' },
                [pscustomobject]@{ Build='26200.9000'; CreatedAt=[datetime]'2026-08-01'; Title='Windows 11, version 25H2 (26200.9000)'; VersionLabel='25H2'; EntryType='Windows' },
                [pscustomobject]@{ Build='28000.2608'; CreatedAt=[datetime]'2026-07-29'; Title='Windows 11, version 26H1 (28000.2608)'; VersionLabel='26H1'; EntryType='Windows' }
            )
            (Get-WibNewestBuild -Builds $builds).VersionLabel | Should -Be '26H1'
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
