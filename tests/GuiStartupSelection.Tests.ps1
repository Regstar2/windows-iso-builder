#requires -Version 5.1

Describe 'GUI startup page selection' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $mainXaml = Get-Content -LiteralPath (Join-Path $projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
    }

    It 'opens Quick Mode instead of an empty page on first launch' {
        $mainXaml | Should -Match '<RadioButton\s+x:Name="QuickNav"[^>]*IsChecked="True"'
        $mainXaml | Should -Match '<TabControl\s+x:Name="Tabs"\s+SelectedIndex="0"'
    }
}
