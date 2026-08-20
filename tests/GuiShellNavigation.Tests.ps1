#requires -Version 5.1

Describe 'v0.3.2 GUI shell navigation' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:mainXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
        $script:settingsXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\SettingsView.xaml') -Raw -Encoding UTF8
        $script:helpXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\HelpView.xaml') -Raw -Encoding UTF8
        $script:aboutXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\AboutView.xaml') -Raw -Encoding UTF8
        $script:quickXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\QuickView.xaml') -Raw -Encoding UTF8
        $script:buildPanelXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\BuildPanelView.xaml') -Raw -Encoding UTF8
        $script:stylesXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Resources\Styles.xaml') -Raw -Encoding UTF8
    }

    It 'moves app identity into the sidebar and removes the internal top header row' {
        $script:mainXaml | Should -Match '<ColumnDefinition Width="190"/>'
        $script:mainXaml | Should -Match '<TextBlock Text="\{services:Loc AppTitle\}" FontSize="18"'
        $script:mainXaml | Should -Not -Match '<RowDefinition Height="52"/>'
    }

    It 'provides Build Catalog Settings Help and About navigation without a large middle gap' {
        foreach ($nav in @('BuildNav','CatalogNav','SettingsNav','HelpNav','AboutNav')) {
            $script:mainXaml | Should -Match ('x:Name="{0}"' -f $nav)
        }
        $script:mainXaml | Should -Match 'Content="\{services:Loc NavBuild\}"'
        $script:mainXaml | Should -Match '<Separator Grid.Row="3"'
        $script:mainXaml | Should -Match 'x:Name="SettingsNav" Grid.Row="4"'
        $script:mainXaml | Should -Not -Match '<Separator Grid.Row="4"'
    }

    It 'moves language theme and diagnostics into Settings' {
        $script:settingsXaml | Should -Match 'x:Name="LanguageCombo"'
        $script:settingsXaml | Should -Match 'x:Name="ThemeCombo"'
        $script:settingsXaml | Should -Match 'Tag="dark"'
        $script:settingsXaml | Should -Match 'ButtonCreateDiagnostics'
        $script:mainXaml | Should -Not -Match 'UiLanguageCombo'
        $script:mainXaml | Should -Not -Match 'FooterDiagnostics'
    }

    It 'provides an explicit dark shell palette' {
        $script:stylesXaml | Should -Match 'x:Key="WibPageBackgroundBrush"'
        $script:stylesXaml | Should -Match 'x:Key="WibCardBrush"'
        $script:mainXaml | Should -Match 'Background="\{DynamicResource WibPageBackgroundBrush\}"'
    }

    It 'guides the Build workflow through the next required action' {
        $script:quickXaml | Should -Match 'Tag="\{Binding HighlightRecommended\}"'
        $script:quickXaml | Should -Match 'Tag="\{Binding HighlightEditions\}"'
        $script:quickXaml | Should -Match 'Tag="\{Binding HighlightPreflight\}"'
        $script:buildPanelXaml | Should -Match 'Tag="\{Binding HighlightBuild\}"'
        $script:stylesXaml | Should -Match 'x:Key="GuidedActionButton"'
        $script:stylesXaml | Should -Match 'x:Key="GuidedStepBorder"'
    }

    It 'provides localized Help and About content including the repository link' {
        $script:helpXaml | Should -Match 'HelpBuildStep1'
        $script:helpXaml | Should -Match 'HelpTroubleshootingDescription'
        $script:aboutXaml | Should -Match 'AboutDescription'
        $script:aboutXaml | Should -Match 'https://github\.com/Regstar2/windows-iso-builder'
        $script:aboutXaml | Should -Match 'Binding Version, Mode=OneWay'
    }
}
