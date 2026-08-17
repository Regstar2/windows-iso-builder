$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Elevated build result protocol' {
    InModuleScope WindowsISOBuilder {
        It 'preserves the concrete stage when a job is marked failed' {
            $statePath = Join-Path $TestDrive 'state.json'
            $plan = [pscustomobject]@{ Name = 'test-plan' }

            Save-WibJobState -Path $statePath -Stage 'downloading-uup-and-converting' -Plan $plan
            Save-WibJobState -Path $statePath -Stage 'failed' -Plan $plan -Message 'converter failed'

            $state = Read-WibJsonFile -Path $statePath
            $state.stage | Should -Be 'failed'
            $state.failedStage | Should -Be 'downloading-uup-and-converting'
            $state.message | Should -Be 'converter failed'
        }

        It 'attaches stage and work directory context to build exceptions' {
            $originalCore = $script:WibOriginalInvokeBuildPlanCore
            $outputDirectory = Join-Path $TestDrive 'output'
            $cacheDirectory = Join-Path $TestDrive 'cache'
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
            New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null

            $plan = [pscustomobject]@{
                CacheDirectory = $cacheDirectory
                OutputDirectory = $outputDirectory
                Language = 'ru-ru'
                SourceEdition = 'Professional'
                Build = [pscustomobject]@{ Uuid = 'test-uuid' }
            }

            try {
                $script:WibOriginalInvokeBuildPlanCore = {
                    param($Plan)
                    $workDirectory = Get-WibPlanWorkDirectory -Plan $Plan
                    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
                    Save-WibJobState -Path (Join-Path $workDirectory 'state.json') -Stage 'downloading-package' -Plan $Plan
                    throw 'network failed'
                }

                $caught = $null
                try {
                    Invoke-WibBuildPlanCore -Plan $plan | Out-Null
                }
                catch {
                    $caught = $_
                }

                $caught | Should -Not -BeNullOrEmpty
                $caught.Exception.Message | Should -Be 'network failed'
                $caught.Exception.Data['WibStage'] | Should -Be 'downloading-package'
                $caught.Exception.Data['WibWorkDirectory'] | Should -Not -BeNullOrEmpty
            }
            finally {
                $script:WibOriginalInvokeBuildPlanCore = $originalCore
            }
        }

        It 'reports the elevated child error instead of only exit code 1' {
            $cacheDirectory = Join-Path $TestDrive 'cache-error'
            $plan = [pscustomobject]@{ CacheDirectory = $cacheDirectory }

            Mock Save-WibPlan { }
            Mock Get-WibPowerShellExecutable { 'powershell.exe' }
            Mock Start-Process {
                param($FilePath, $Verb, $Wait, $PassThru, $ArgumentList)

                $resultIndex = -1
                for ($index = 0; $index -lt $ArgumentList.Count; $index++) {
                    if ([string]$ArgumentList[$index] -eq '-ResultFile') {
                        $resultIndex = $index
                        break
                    }
                }
                $resultIndex | Should -BeGreaterThan -1

                $resultPath = ([string]$ArgumentList[$resultIndex + 1]).Trim([char]34)
                Write-WibJsonFile -Path $resultPath -Value ([ordered]@{
                    success       = $false
                    stage         = 'downloading-uup-and-converting'
                    message       = 'uup_download_windows.cmd завершился с кодом 1.'
                    stackTrace    = 'test stack trace'
                    logPath       = 'C:\output\logs\build-test.log'
                    workDirectory = 'C:\UUP-ISO-Work\work\test'
                    isoPath       = ''
                })
                return [pscustomobject]@{ ExitCode = 1 }
            }

            $caught = $null
            try {
                Start-WibElevatedPlan -Plan $plan | Out-Null
            }
            catch {
                $caught = $_
            }

            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Message | Should -Match 'downloading-uup-and-converting'
            $caught.Exception.Message | Should -Match 'uup_download_windows\.cmd завершился с кодом 1'
            $caught.Exception.Message | Should -Match 'build-test\.log'
            $caught.Exception.Message | Should -Match ([regex]::Escape('C:\UUP-ISO-Work\work\test'))
            $caught.Exception.Message | Should -Match 'test stack trace'
        }

        It 'accepts a successful elevated child result' {
            $cacheDirectory = Join-Path $TestDrive 'cache-success'
            $plan = [pscustomobject]@{ CacheDirectory = $cacheDirectory }

            Mock Save-WibPlan { }
            Mock Get-WibPowerShellExecutable { 'powershell.exe' }
            Mock Start-Process {
                param($FilePath, $Verb, $Wait, $PassThru, $ArgumentList)

                $resultIndex = -1
                for ($index = 0; $index -lt $ArgumentList.Count; $index++) {
                    if ([string]$ArgumentList[$index] -eq '-ResultFile') {
                        $resultIndex = $index
                        break
                    }
                }
                $resultIndex | Should -BeGreaterThan -1

                $resultPath = ([string]$ArgumentList[$resultIndex + 1]).Trim([char]34)
                Write-WibJsonFile -Path $resultPath -Value ([ordered]@{
                    success       = $true
                    stage         = 'completed'
                    message       = ''
                    stackTrace    = ''
                    logPath       = 'C:\output\logs\build-test.log'
                    workDirectory = 'C:\UUP-ISO-Work\work\test'
                    isoPath       = 'C:\output\Windows.iso'
                })
                return [pscustomobject]@{ ExitCode = 0 }
            }

            $result = Start-WibElevatedPlan -Plan $plan
            $result.success | Should -BeTrue
            $result.stage | Should -Be 'completed'
            $result.isoPath | Should -Be 'C:\output\Windows.iso'
        }
    }
}
