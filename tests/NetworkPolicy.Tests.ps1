$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'v0.3.4 global network policy' {
    InModuleScope WindowsISOBuilder {
        BeforeEach {
            Mock Get-WibNetworkStateRoot { $TestDrive }
        }

        It 'defaults a missing policy to System' {
            $policy = Get-WibNetworkPolicy
            $policy.schemaVersion | Should -Be 1
            $policy.mode | Should -Be 'system'
            $policy.proxyType | Should -BeNullOrEmpty
            $policy.hasCredential | Should -BeFalse
        }

        It 'rejects malformed Custom settings instead of falling back' {
            try { Set-WibNetworkPolicy -Mode Custom -ProxyType HTTP -Host '' -Port 8080 -Confirm:$false; throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'PROXY_CONFIGURATION_INVALID' }

            try { Set-WibNetworkPolicy -Mode Custom -ProxyType SOCKS5 -Host 'https://proxy.example' -Port 1080 -Confirm:$false; throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'PROXY_CONFIGURATION_INVALID' }
        }

        It 'fails closed when persisted policy JSON is corrupted' {
            [IO.File]::WriteAllText((Get-WibNetworkPolicyPath), '{broken-json', (New-Object Text.UTF8Encoding($false)))
            try { Get-WibNetworkPolicy | Out-Null; throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'PROXY_CONFIGURATION_INVALID' }
        }

        It 'stores proxy password outside network.json and protects it with DPAPI' {
            if ($env:OS -ne 'Windows_NT') { Set-ItResult -Skipped -Because 'Windows DPAPI test'; return }
            $secret = 'wib-proxy-secret-42'
            $secure = ConvertTo-SecureString $secret -AsPlainText -Force
            $policy = Set-WibNetworkPolicy -Mode Custom -ProxyType HTTP -Host '127.0.0.1' -Port 3128 -Username 'alice' -Password $secure -Confirm:$false
            $policy.hasCredential | Should -BeTrue

            $json = [IO.File]::ReadAllText((Get-WibNetworkPolicyPath), [Text.Encoding]::UTF8)
            $json | Should -Not -Match [regex]::Escape($secret)
            $json | Should -Not -Match 'password'

            $credentialBytes = [IO.File]::ReadAllBytes((Get-WibProxyCredentialPath))
            [Text.Encoding]::UTF8.GetString($credentialBytes) | Should -Not -Match [regex]::Escape($secret)
            (Get-WibProxyCredentialText -Policy (Get-WibNetworkPolicy)) | Should -Be $secret
        }

        It 'fails closed when a saved credential cannot be decrypted' {
            if ($env:OS -ne 'Windows_NT') { Set-ItResult -Skipped -Because 'Windows DPAPI test'; return }
            $secure = ConvertTo-SecureString 'temporary-secret' -AsPlainText -Force
            Set-WibNetworkPolicy -Mode Custom -ProxyType SOCKS5 -Host '127.0.0.1' -Port 1080 -Username 'alice' -Password $secure -Confirm:$false | Out-Null
            [IO.File]::WriteAllBytes((Get-WibProxyCredentialPath), [byte[]](1,2,3,4,5))
            try { Get-WibProxyCredentialText -Policy (Get-WibNetworkPolicy) | Out-Null; throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'PROXY_CREDENTIAL_UNAVAILABLE' }
        }

        It 'clears saved credential without leaving hasCredential true' {
            if ($env:OS -ne 'Windows_NT') { Set-ItResult -Skipped -Because 'Windows DPAPI test'; return }
            $secure = ConvertTo-SecureString 'temporary-secret' -AsPlainText -Force
            Set-WibNetworkPolicy -Mode Custom -ProxyType HTTP -Host '127.0.0.1' -Port 3128 -Username 'alice' -Password $secure -Confirm:$false | Out-Null
            Clear-WibProxyCredential -Confirm:$false
            Test-Path -LiteralPath (Get-WibProxyCredentialPath) | Should -BeFalse
            (Get-WibNetworkPolicy).hasCredential | Should -BeFalse
        }

        It 'Direct clears inherited proxy variables for the generated downloader' {
            $prefix = Get-WibManagedDownloadProxyPrefix -Policy ([pscustomobject]@{mode='direct'}) -Bridge $null
            $prefix | Should -Match 'HTTP_PROXY='
            $prefix | Should -Match 'HTTPS_PROXY='
            $prefix | Should -Match 'ALL_PROXY='
            $prefix | Should -Not -Match '127\.0\.0\.1:'
        }

        It 'System and Custom expose only the loopback bridge to the generated downloader' {
            $bridge = [pscustomobject]@{Port=54321}
            foreach ($policy in @(
                [pscustomobject]@{mode='system'},
                [pscustomobject]@{mode='custom';proxyType='socks5';host='proxy.example';port=1080;username='alice';hasCredential=$true}
            )) {
                $prefix = Get-WibManagedDownloadProxyPrefix -Policy $policy -Bridge $bridge
                $prefix | Should -Match '127\.0\.0\.1:54321'
                $prefix | Should -Not -Match 'proxy\.example|alice|secret'
            }
        }

        It 'Direct file download uses the central HttpClient path and never Invoke-WebRequest' {
            Mock Get-WibNetworkPolicy { [pscustomobject]@{schemaVersion=1;mode='direct';proxyType=$null;host=$null;port=$null;username=$null;hasCredential=$false} }
            Mock Invoke-WibHttpRequestCore { }
            Mock Invoke-WebRequest { throw 'must not be used for Direct' }
            Invoke-WibHttpDownload -Uri 'https://example.test/file' -OutFile (Join-Path $TestDrive 'file.bin')
            Assert-MockCalled Invoke-WibHttpRequestCore -Times 1 -Exactly
            Assert-MockCalled Invoke-WebRequest -Times 0 -Exactly
        }

        It 'Custom file download failure remains a proxy failure with no Direct retry' {
            Mock Get-WibNetworkPolicy { [pscustomobject]@{schemaVersion=1;mode='custom';proxyType='http';host='127.0.0.1';port=9;username=$null;hasCredential=$false} }
            Mock Invoke-WebRequest { throw 'controlled proxy failure' }
            try { Invoke-WibHttpDownload -Uri 'https://example.test/file' -OutFile (Join-Path $TestDrive 'file.bin'); throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'PROXY_CONNECTION_FAILED' }
            Assert-MockCalled Invoke-WebRequest -Times 1 -Exactly
        }

        It 'routes API preflight package and managed downloader paths through the policy layer' {
            (Get-Command Invoke-WibApiRequest).Definition | Should -Match 'Invoke-WibHttpJsonRequest'
            (Get-Command Test-WibUupApiAvailability).Definition | Should -Match 'Invoke-WibHttpJsonRequest'
            (Get-Command Download-WibUupPackage).Definition | Should -Match 'Invoke-WibHttpDownload'
            (Get-Command Invoke-WibUupDownloadScript).Definition | Should -Match 'Get-WibNetworkPolicy'
            (Get-Command Invoke-WibUupDownloadScript).Definition | Should -Match 'Get-WibManagedDownloadProxyPrefix'
        }

        It 'keeps upstream proxy credentials out of the generated downloader command line' {
            $bridge = [pscustomobject]@{Port=54321}
            $bridge | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            Mock Get-WibNetworkPolicy { [pscustomobject]@{schemaVersion=1;mode='custom';proxyType='socks5';host='proxy.example';port=1080;username='alice';hasCredential=$true} }
            Mock Start-WibNetworkProxyBridge { $bridge }
            Mock Invoke-WibManagedProcess {
                param($FilePath,$ArgumentList,$WorkingDirectory,$Stage,$LineHandler,$StageProvider)
                $script:capturedManagedArguments = [string]$ArgumentList
                [pscustomobject]@{ExitCode=0}
            }
            $oldComSpec = $env:ComSpec
            try {
                $env:ComSpec = 'C:\Windows\System32\cmd.exe'
                Invoke-WibUupDownloadScript -PackageDirectory $TestDrive -ScriptName 'uup_download_windows.cmd' | Should -Be 0
            }
            finally { $env:ComSpec = $oldComSpec }
            $script:capturedManagedArguments | Should -Match '127\.0\.0\.1:54321'
            $script:capturedManagedArguments | Should -Not -Match 'proxy\.example|alice|proxy-secret'
        }
    }
}
