#requires -Version 5.1

Describe 'Build progress liveness UI' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:buildPanelXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\BuildPanelView.xaml') -Raw -Encoding UTF8
    }

    It 'keeps precise progress determinate while showing continuous build activity' {
        $script:buildPanelXaml | Should -Match 'ProgressBar\s+Value="\{Binding Progress,\s*Mode=OneWay\}"'
        $script:buildPanelXaml | Should -Match 'x:Name="BuildActivityIndicator"'
        $script:buildPanelXaml | Should -Match '(?s)x:Name="BuildActivityIndicator".*?IsIndeterminate="True"'
    }

    It 'shows the activity indicator only inside the active build panel' {
        $script:buildPanelXaml | Should -Match '(?s)Visibility="\{Binding ShowBuildProgress,.*?BuildActivityIndicator'
    }

    It 'keeps the liveness indicator passive and reuses localized build status' {
        $script:buildPanelXaml | Should -Match '(?s)x:Name="BuildActivityIndicator".*?Focusable="False".*?IsHitTestVisible="False"'
        $script:buildPanelXaml | Should -Match 'AutomationProperties\.Name="\{Binding Status, Mode=OneWay\}"'
    }
}
