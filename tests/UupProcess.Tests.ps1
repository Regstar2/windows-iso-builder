$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'UUP converter process execution' {
    InModuleScope WindowsISOBuilder {
        It 'uses the managed process runner and an owned PID tree' {
            $definition = (Get-Command Invoke-WibUupDownloadScript -ErrorAction Stop).Definition

            $definition | Should -Match 'Invoke-WibManagedProcess'
            $definition | Should -Match '\$env:ComSpec|cmd\.exe'
            $definition | Should -Match 'WorkingDirectory'
            $definition | Should -Not -Match 'Get-Process\s+(aria2|dism)'
        }

        It 'searches the full work directory for the resulting ISO and classifies converter failure' {
            $builderPath = Join-Path $script:ModuleRoot 'Private\Builder.ps1'
            $source = Get-Content -LiteralPath $builderPath -Raw -Encoding UTF8

            $source | Should -Match 'Get-ChildItem\s+-LiteralPath\s+\$workDirectory\s+-Filter\s+''\*\.iso'''
            $source | Should -Match 'CONVERTER_FAILED'
            $source | Should -Match '\$converterLogPath'
        }
    }
}
