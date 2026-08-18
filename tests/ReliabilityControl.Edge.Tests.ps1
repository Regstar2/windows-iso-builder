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

        It 'recognizes Windows ERROR_CANCELLED numerically instead of parsing text' {
            $exception = New-Object ComponentModel.Win32Exception(1223)
            Test-WibElevationCancelledException -Exception $exception | Should -BeTrue
            $source = (Get-Command Test-WibElevationCancelledException -ErrorAction Stop).Definition
            $source | Should -Not -Match 'Message.*match|match.*Message'
        }
    }
}
