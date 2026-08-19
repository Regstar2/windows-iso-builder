#requires -Version 5.1

Describe 'GUI clipping regressions' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:mainXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
        $script:quickXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\QuickView.xaml') -Raw -Encoding UTF8
        $script:stylesXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Resources\Styles.xaml') -Raw -Encoding UTF8
    }

    It 'keeps footer controls inside a row tall enough for Fluent controls' {
        $script:mainXaml | Should -Match '<RowDefinition Height="38"/>'
        $script:mainXaml | Should -Match 'x:Name="UiLanguageCombo" Width="108" Height="30"'
        $script:stylesXaml | Should -Match 'x:Key="FooterButton"[\s\S]*?<Setter Property="MinHeight" Value="30"/>'
    }

    It 'keeps the output-directory row visible in compact Quick Mode' {
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
}
