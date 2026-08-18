$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'v0.2.2 reliability edge cases' {
    InModuleScope WindowsISOBuilder {
        It 'does not open UAC when local preflight has a fatal failure' {
            $plan = [pscustomobject]@{ CacheDirectory=$TestDrive; OutputDirectory=$TestDrive }
            Mock Assert-WibPlan { }
            Mock Invoke-WibPreflight { [pscustomobject]@{ ready=$false; checks=@(New-WibPreflightCheck -Id 'disk.cache' -Status fail -Severity error -Code 'DISK_SPACE_LOW' -Message 'low') } }
            Mock Show-WibPreflightSummary { }
            Mock Start-WibElevatedPlan { throw 'must not be called' }
            { Invoke-WibBuildPlan -Plan $plan } | Should -Throw
            Assert-MockCalled Start-WibElevatedPlan -Times 0 -Exactly
        }

        It 'classifies managed UUP process launch failures as DOWNLOAD_FAILED' {
            Mock Invoke-WibManagedProcess { throw 'process launch failed' }
            $oldComSpec = $env:ComSpec
            try {
                $env:ComSpec = 'C:\Windows\System32\cmd.exe'
                try { Invoke-WibUupDownloadScript -PackageDirectory $TestDrive -ScriptName 'uup_download_windows.cmd'; throw 'expected' }
                catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'DOWNLOAD_FAILED' }
            }
            finally { $env:ComSpec = $oldComSpec }
        }

        It 'preserves BUILD_CANCELLED from the managed process runner' {
            Mock Invoke-WibManagedProcess { throw (New-WibErrorException -Code 'BUILD_CANCELLED' -Message 'cancel' -Stage 'convert') }
            $oldComSpec = $env:ComSpec
            try {
                $env:ComSpec = 'C:\Windows\System32\cmd.exe'
                try { Invoke-WibUupDownloadScript -PackageDirectory $TestDrive -ScriptName 'uup_download_windows.cmd'; throw 'expected' }
                catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'BUILD_CANCELLED'; $_.Exception.Data['WibStage'] | Should -Be 'convert' }
            }
            finally { $env:ComSpec = $oldComSpec }
        }

        It 'checks cancellation again after the elevated worker returns' {
            $source = (Get-Command Invoke-WibBuildPlan -ErrorAction Stop).Definition
            $source | Should -Match 'Start-WibElevatedPlan'
            $source | Should -Match 'Assert-WibNotCancelled -Stage ''verify'''
        }

        It 'checks cancellation before emitting the final ExecuteBuildPlan success DTO' {
            $source = (Get-Command Invoke-WibBackendCommand -ErrorAction Stop).Definition
            $executeStart = $source.IndexOf("'ExecuteBuildPlan'")
            $executeSource = $source.Substring($executeStart)
            $invokeIndex = $executeSource.IndexOf('Invoke-WibBuildPlan')
            $finalCheckIndex = $executeSource.IndexOf("Assert-WibNotCancelled -Stage 'verify'", $invokeIndex)
            $returnIndex = $executeSource.IndexOf('return ConvertTo-WibBuildResultDto', $invokeIndex)
            $finalCheckIndex | Should -BeGreaterThan $invokeIndex
            $returnIndex | Should -BeGreaterThan $finalCheckIndex
        }

        It 'recognizes Windows ERROR_CANCELLED numerically instead of parsing text' {
            $exception = New-Object ComponentModel.Win32Exception -ArgumentList 1223
            Test-WibElevationCancelledException -Exception $exception | Should -BeTrue
            $source = (Get-Command Test-WibElevationCancelledException -ErrorAction Stop).Definition
            $source | Should -Not -Match 'Message.*match|match.*Message'
        }

        It 'does not overwrite or delete a foreign file that collides with a marker name' {
            $target = 'foreign-collision'
            $path = Get-WibCancellationControlPath -RequestId $target -CacheDirectory $TestDrive
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [IO.File]::WriteAllText($path, 'user-data', (New-Object Text.UTF8Encoding($false)))

            try { Save-WibCancellationRequest -TargetRequestId $target -CacheDirectory $TestDrive -Confirm:$false | Out-Null; throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'PATH_NOT_WRITABLE' }
            [IO.File]::ReadAllText($path) | Should -Be 'user-data'

            Initialize-WibCancellationContext -RequestId $target -CacheDirectory $TestDrive | Out-Null
            Test-WibCancellationRequested | Should -BeFalse
            Reset-WibCancellationContext -RemoveControlFile -Confirm:$false
            Test-Path -LiteralPath $path | Should -BeTrue
        }
    }
}
