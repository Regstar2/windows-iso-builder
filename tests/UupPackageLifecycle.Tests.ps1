$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'UUP conversion package lifecycle hardening' {
    InModuleScope WindowsISOBuilder {
        BeforeAll {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
        }

        It 'loads the fresh-package implementation after network integration' {
            $source = (Get-Command Download-WibUupPackage -CommandType Function).ScriptBlock.ToString()
            $source | Should -Match 'Downloading fresh UUP dump conversion package'
            $source | Should -Match 'Reset-WibUupConversionMetadata'
        }

        It 'refreshes a structurally valid cached package and invalidates old conversion metadata' {
            $packagesDirectory = Join-Path $TestDrive 'packages'
            $workDirectory = Join-Path (Join-Path $TestDrive 'work') 'job123'
            $payloadDirectory = Join-Path $workDirectory 'files'
            New-Item -ItemType Directory -Path $packagesDirectory -Force | Out-Null
            New-Item -ItemType Directory -Path $payloadDirectory -Force | Out-Null

            $destinationZip = Join-Path $packagesDirectory 'job123.zip'
            $staleSource = Join-Path $TestDrive 'stale-source'
            New-Item -ItemType Directory -Path $staleSource -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $staleSource 'uup_download_windows.cmd'), 'old converter url')
            [IO.File]::WriteAllText((Join-Path $staleSource 'ConvertConfig.ini'), 'old config')
            [IO.Compression.ZipFile]::CreateFromDirectory($staleSource, $destinationZip)

            [IO.File]::WriteAllText((Join-Path $workDirectory 'uup_download_windows.cmd'), 'old converter url')
            [IO.File]::WriteAllText((Join-Path $workDirectory 'ConvertConfig.ini'), 'old config')
            $payloadPath = Join-Path $payloadDirectory 'partial-uup.esd'
            [IO.File]::WriteAllText($payloadPath, 'keep me')

            $freshSource = Join-Path $TestDrive 'fresh-source'
            $freshZip = Join-Path $TestDrive 'fresh.zip'
            New-Item -ItemType Directory -Path $freshSource -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $freshSource 'uup_download_windows.cmd'), 'new converter url')
            [IO.File]::WriteAllText((Join-Path $freshSource 'ConvertConfig.ini'), 'new config')
            [IO.Compression.ZipFile]::CreateFromDirectory($freshSource, $freshZip)

            Mock Invoke-WibHttpDownload {
                param($Method, $Uri, $FormBody, $OutFile, $TimeoutSeconds, $Headers)
                Copy-Item -LiteralPath $freshZip -Destination $OutFile -Force
            }

            $plan = [pscustomobject]@{
                Build=[pscustomobject]@{Uuid='id'}
                Language='ru-ru'
                SourceEdition='Professional'
                AddUpdates=$true
                Cleanup=$true
                NetFx3=$false
                ImageFormat='ESD'
            }

            Download-WibUupPackage -Plan $plan -DestinationZip $destinationZip -Attempts 1

            Assert-MockCalled Invoke-WibHttpDownload -Times 1 -Exactly
            Test-Path -LiteralPath $destinationZip -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $workDirectory 'uup_download_windows.cmd') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $workDirectory 'ConvertConfig.ini') | Should -BeFalse
            Test-Path -LiteralPath $payloadPath -PathType Leaf | Should -BeTrue
            [IO.File]::ReadAllText($payloadPath) | Should -Be 'keep me'
        }

        It 'does not silently fall back to a stale conversion ZIP when refresh fails' {
            $packagesDirectory = Join-Path $TestDrive 'packages'
            New-Item -ItemType Directory -Path $packagesDirectory -Force | Out-Null
            $destinationZip = Join-Path $packagesDirectory 'job456.zip'

            $staleSource = Join-Path $TestDrive 'stale-fallback-source'
            New-Item -ItemType Directory -Path $staleSource -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $staleSource 'uup_download_windows.cmd'), 'old converter url')
            [IO.File]::WriteAllText((Join-Path $staleSource 'ConvertConfig.ini'), 'old config')
            [IO.Compression.ZipFile]::CreateFromDirectory($staleSource, $destinationZip)

            Mock Invoke-WibHttpDownload { throw 'network down' }

            $plan = [pscustomobject]@{
                Build=[pscustomobject]@{Uuid='id'}
                Language='ru-ru'
                SourceEdition='Professional'
                AddUpdates=$true
                Cleanup=$true
                NetFx3=$false
                ImageFormat='ESD'
            }

            $caught = $null
            try { Download-WibUupPackage -Plan $plan -DestinationZip $destinationZip -Attempts 1 }
            catch { $caught = $_ }

            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Data['WibErrorCode'] | Should -Be 'UUP_PACKAGE_DOWNLOAD_FAILED'
            Test-Path -LiteralPath $destinationZip | Should -BeFalse
            Assert-MockCalled Invoke-WibHttpDownload -Times 1 -Exactly
        }

        It 'derives the resumable work directory only from the packages cache layout' {
            $expected = Join-Path (Join-Path $TestDrive 'work') 'abc123'
            Get-WibUupPackageWorkDirectory -DestinationZip (Join-Path (Join-Path $TestDrive 'packages') 'abc123.zip') | Should -Be $expected
            Get-WibUupPackageWorkDirectory -DestinationZip (Join-Path $TestDrive 'abc123.zip') | Should -BeNullOrEmpty
        }
    }
}
