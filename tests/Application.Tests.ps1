$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Interactive build completion message' {
    InModuleScope WindowsISOBuilder {
        It 'shows an explicit ISO success message and resulting path' {
            $result = [pscustomobject]@{
                isoPath          = 'C:\output\Windows.iso'
                logPath          = 'C:\output\logs\build-test.log'
                executionLogPath = 'C:\project\logs\elevated-test.log'
            }

            Mock Write-WibStage { }
            Mock Write-Host { }

            Show-WibBuildSuccess -Result $result

            Should -Invoke Write-WibStage -Times 1 -ParameterFilter { $Message -eq 'Сборка завершена' }
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -eq 'ISO успешно создан.' }
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -eq 'ISO: C:\output\Windows.iso' }
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -eq 'Лог сборки: C:\output\logs\build-test.log' }
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -eq 'Лог повышенного процесса: C:\project\logs\elevated-test.log' }
        }
    }
}
