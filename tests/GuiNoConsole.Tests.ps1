#requires -Version 5.1

Describe 'GUI build runs without visible console windows' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
    }

    It 'hides the elevated PowerShell window only for Backend Contract event mode' {
        $elevation = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder\Private\Elevation.ps1') -Raw -Encoding UTF8
        $elevation | Should -Match 'if \(\$eventContext\.Enabled\) \{ \$startProcessParameters\.WindowStyle = ''Hidden'' \}'
        $elevation | Should -Match '\$process = Start-Process @startProcessParameters'
    }

    It 'hides the managed converter process while retaining redirected output' {
        $execution = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder\Private\ExecutionControl.ps1') -Raw -Encoding UTF8
        $execution | Should -Match 'RedirectStandardOutput \$stdoutPath'
        $execution | Should -Match 'RedirectStandardError \$stderrPath'
        $execution | Should -Match 'PassThru -WindowStyle Hidden'
    }

    It 'keeps structured converter progress events for the GUI progress bar' {
        $progress = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder\Private\ConsoleProgress.ps1') -Raw -Encoding UTF8
        $xaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
        $progress | Should -Match "Publish-WibEvent -Type 'progress'"
        $progress | Should -Match 'SpeedBytesPerSecond'
        $xaml | Should -Match 'ProgressBar Value="\{Binding Progress, Mode=OneWay\}"'
    }
}
