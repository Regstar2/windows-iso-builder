#requires -Version 5.1

Describe 'GUI clipping regressions' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:mainXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
        $script:quickXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\QuickView.xaml') -Raw -Encoding UTF8
        $script:catalogXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\CatalogView.xaml') -Raw -Encoding UTF8
    }

    It 'uses the footer for compact build status instead of settings controls' {
        $script:mainXaml | Should -Match '<RowDefinition Height="38"/>'
        $script:mainXaml | Should -Match 'Text="\{Binding Status, Mode=OneWay\}"'
        $script:mainXaml | Should -Not -Match 'x:Name="UiLanguageCombo"'
        $script:mainXaml | Should -Not -Match 'FooterDiagnostics'
    }

    It 'keeps the output-directory row visible in compact Build mode' {
        $script:quickXaml | Should -Match 'x:Name="QuickLayout" Margin="20,14,20,10"'
        $script:quickXaml | Should -Match '<TextBlock Grid.Row="4" Text="\{services:Loc LabelOutputDirectory\}"'
        $script:quickXaml | Should -Match '<Grid Grid.Row="5">'
        $script:quickXaml | Should -Not -Match '<TextBlock Grid.Row="6" Text="\{services:Loc TooltipAdvanced\}"'
    }

    It 'lets the advanced button size to its localized label instead of a narrow fixed column' {
        $script:quickXaml | Should -Match '<ColumnDefinition Width="Auto"/>'
        $script:quickXaml | Should -Match 'Content="\{services:Loc ButtonAdvanced\}"[\s\S]*?MinWidth="104"'
        $script:quickXaml | Should -Not -Match '<ColumnDefinition Width="86"/>[\s\S]*?Content="\{services:Loc ButtonAdvanced\}"'
    }

    It 'keeps catalog search controls tall enough for Fluent content' {
        $script:catalogXaml | Should -Match '<TextBox Grid.Column="0" Height="36"'
        $script:catalogXaml | Should -Match '<ComboBox Grid.Column="2" Height="36"'
        $script:catalogXaml | Should -Match '<Button Grid.Column="8" Height="36"[\s\S]*?Content="\{services:Loc ButtonSearch\}"'
    }
}
