#requires -Version 5.1

Describe 'GUI startup page selection' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:mainXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
    }

    It 'opens Build instead of an empty page on first launch' {
        $script:mainXaml | Should -Match '<RadioButton\s+x:Name="BuildNav"[^>]*IsChecked="True"'
        $script:mainXaml | Should -Match '<TabControl\s+x:Name="Tabs"\s+SelectedIndex="0"'
    }
}
