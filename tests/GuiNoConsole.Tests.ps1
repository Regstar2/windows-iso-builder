#requires -Version 5.1

Describe 'GUI process presentation' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
    }

    It 'uses WinExe for the GUI host' {
        $project = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\WindowsISOBuilder.Gui.csproj') -Raw -Encoding UTF8
        $project | Should -Match '<OutputType>WinExe</OutputType>'
    }

    It 'uses hidden no-window backend child processes' {
        $runner = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Backend\BackendProcessRunner.cs') -Raw -Encoding UTF8
        $runner | Should -Match 'UseShellExecute\s*=\s*false'
        $runner | Should -Match 'CreateNoWindow\s*=\s*true'
        $runner | Should -Match 'WindowStyle\s*=\s*ProcessWindowStyle\.Hidden'
    }

    It 'binds ProgressBar one-way in the persistent build panel' {
        $xaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\BuildPanelView.xaml') -Raw -Encoding UTF8
        $xaml | Should -Match '<ProgressBar[^>]*Value="\{Binding Progress,\s*Mode=OneWay\}"'
    }

    It 'keeps backend launch arguments separated' {
        $runner = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Backend\BackendProcessRunner.cs') -Raw -Encoding UTF8
        $runner | Should -Match 'ArgumentList\.Add'
        $runner | Should -Not -Match 'Arguments\s*='
    }
}
