$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Managed process cancellation Windows smoke' {
    InModuleScope WindowsISOBuilder {
        It 'terminates only the owned dummy process tree' -Skip:($env:WIB_RUN_PROCESS_CANCELLATION_SMOKE -ne '1' -or $env:OS -ne 'Windows_NT') {
            $cache = Join-Path $TestDrive 'cache'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            $context = Initialize-WibCancellationContext -RequestId 'process-smoke-target' -CacheDirectory $cache
            New-Item -ItemType Directory -Path (Split-Path -Parent $context.ControlPath) -Force | Out-Null
            $powerShell = Get-WibPowerShellExecutable
            $foreign = Start-Process -FilePath $powerShell -ArgumentList '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru
            $markerJob = Start-Job -ScriptBlock {
                param($Path)
                Start-Sleep -Milliseconds 800
                [IO.File]::WriteAllText($Path, '{}', (New-Object Text.UTF8Encoding($false)))
            } -ArgumentList $context.ControlPath
            try {
                try {
                    Invoke-WibManagedProcess -FilePath $powerShell -ArgumentList '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 30"' -WorkingDirectory $TestDrive -Stage 'convert' | Out-Null
                    throw 'expected cancellation'
                }
                catch {
                    $_.Exception.Data['WibErrorCode'] | Should -Be 'BUILD_CANCELLED'
                }
                $foreign.Refresh()
                $foreign.HasExited | Should -BeFalse
            }
            finally {
                if ($null -ne $foreign -and -not $foreign.HasExited) { Stop-Process -Id $foreign.Id -Force -ErrorAction SilentlyContinue }
                if ($null -ne $markerJob) { Wait-Job $markerJob -Timeout 5 | Out-Null; Remove-Job $markerJob -Force -ErrorAction SilentlyContinue }
                Reset-WibCancellationContext -RemoveControlFile -Confirm:$false
            }
        }
    }
}
