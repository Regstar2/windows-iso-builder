$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'UUP converter process execution' {
    InModuleScope WindowsISOBuilder {
        It 'uses a nested PowerShell stream to wait for batch child processes' {
            $definition = (Get-Command Invoke-WibUupDownloadScript -ErrorAction Stop).Definition

            $definition | Should -Match 'Get-WibPowerShellExecutable'
            $definition | Should -Match 'Out-String\s+-Stream'
            $definition | Should -Match 'exit\s+\$LASTEXITCODE'
        }

        It 'searches the full work directory for the resulting ISO' {
            $builderPath = Join-Path $script:ModuleRoot 'Private\Builder.ps1'
            $source = Get-Content -LiteralPath $builderPath -Raw

            $source | Should -Match "Get-ChildItem\s+-LiteralPath\s+\$workDirectory\s+-Filter\s+'\*\.iso'"
            $source | Should -Match 'Подробный лог:\s+\$converterLogPath'
        }
    }
}
