Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Windows PowerShell 5.1 form POST compatibility' {
    InModuleScope WindowsISOBuilder {
        It 'loads the compatibility override after the base network implementation' {
            $moduleSource = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'WindowsISOBuilder.psm1') -Raw -Encoding UTF8
            $baseIndex = $moduleSource.IndexOf("Private\Network.ps1")
            $compatIndex = $moduleSource.IndexOf("Private\NetworkPowerShell51Compat.ps1")
            $baseIndex | Should -BeGreaterThanOrEqual 0
            $compatIndex | Should -BeGreaterThan $baseIndex
        }

        It 'constructs a five-field form body as one FormUrlEncodedContent argument' {
            $form = @{
                autodl = '2'
                updates = '1'
                cleanup = '1'
                netfx = '0'
                esd = '1'
            }

            $content = New-WibFormUrlEncodedContent -FormBody $form
            try {
                $content.GetType().FullName | Should -Be 'System.Net.Http.FormUrlEncodedContent'
                $encoded = $content.ReadAsStringAsync().GetAwaiter().GetResult()
                foreach ($expected in @('autodl=2','updates=1','cleanup=1','netfx=0','esd=1')) {
                    $encoded | Should -Match ([regex]::Escape($expected))
                }
            }
            finally {
                if ($null -ne $content) { $content.Dispose() }
            }
        }

        It 'keeps the fixed core wired to the compatibility form-content helper' {
            $source = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private\NetworkPowerShell51Compat.ps1') -Raw -Encoding UTF8
            $source | Should -Match 'New-WibFormUrlEncodedContent -FormBody \$FormBody'
            $source | Should -Match '-ArgumentList \(,\$pairs\)'
        }
    }
}
