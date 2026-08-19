#requires -Version 5.1

Describe 'GUI MVP regression boundaries' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
    }

    It 'keeps the GUI WPF-only and the headless smoke free of StartupUri' {
        $project = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\WindowsISOBuilder.Gui.csproj') -Raw -Encoding UTF8
        $appXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\App.xaml') -Raw -Encoding UTF8
        $mainWindow = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml.cs') -Raw -Encoding UTF8

        $project | Should -Match '<UseWPF>true</UseWPF>'
        $project | Should -Not -Match '<UseWindowsForms>true</UseWindowsForms>'
        $mainWindow | Should -Not -Match 'System\.Windows\.Forms'
        $appXaml | Should -Not -Match 'StartupUri'
    }

    It 'keeps read-only progress binding one-way' {
        $mainWindowXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
        $viewModel = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\ViewModels\MainViewModel.cs') -Raw -Encoding UTF8

        $mainWindowXaml | Should -Match 'ProgressBar\s+Value="\{Binding Progress,\s*Mode=OneWay\}"'
        $viewModel | Should -Match 'public\s+double\s+Progress\s*\{\s*get\s*=>\s*_progress;\s*private\s+set'
    }

    It 'prevents sync-context deadlock in packaged backend smoke' {
        $smoke = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\BackendSmoke.cs') -Raw -Encoding UTF8
        $smoke | Should -Match '\.ConfigureAwait\(false\)'
    }

    It 'keeps output directory creation and writability in backend preflight' {
        $viewModel = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\ViewModels\MainViewModel.cs') -Raw -Encoding UTF8
        $viewModel | Should -Not -Match 'Directory\.CreateDirectory\(\s*OutputDirectory\s*\)'
        $viewModel | Should -Match 'RunPreflight'
    }

    It 'gates the interactive GUI on the startup backend handshake' {
        $viewModel = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\ViewModels\MainViewModel.cs') -Raw -Encoding UTF8
        $viewModel | Should -Match 'State\s*=\s*UiState\.LoadingBuild'
        $viewModel | Should -Match 'InvokeAsync<VersionData>\("GetVersion"'
    }

    It 'shows actual preflight status instead of failure severity' {
        $xaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
        $dtos = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Models\ContractDtos.cs') -Raw -Encoding UTF8

        $xaml | Should -Match 'Text="\{Binding StatusLabel, Mode=OneWay\}"'
        $xaml | Should -Not -Match 'Text="\{Binding Severity\}"'
        $dtos | Should -Match '"pass"\s*=>\s*"OK"'
        $dtos | Should -Match '"warning"\s*=>\s*"Предупреждение"'
        $dtos | Should -Match '"fail"\s*=>\s*"Ошибка"'
        $dtos | Should -Match '"skipped"\s*=>\s*"Пропущено"'
    }

    It 'sanitizes technical diagnostics instead of exposing raw backend messages' {
        $viewModel = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\ViewModels\MainViewModel.cs') -Raw -Encoding UTF8
        $logger = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\GuiLogger.cs') -Raw -Encoding UTF8

        $viewModel | Should -Match 'GuiLogger\.SanitizeDiagnostic\(backendException\.Message\)'
        $logger | Should -Match '<URL>'
        $logger | Should -Match '<PRODUCT_KEY>'
    }

    It 'uses deterministic executable boundaries for PowerShell and packaged backend code' {
        $runner = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Backend\BackendProcessRunner.cs') -Raw -Encoding UTF8
        $resolver = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Backend\BackendPathResolver.cs') -Raw -Encoding UTF8

        $runner | Should -Match 'Environment\.SystemDirectory'
        $runner | Should -Match 'WindowsPowerShell'
        $runner | Should -Not -Match 'ProcessStartInfo\(\s*"powershell\.exe"'
        $resolver | Should -Not -Match 'GetEnvironmentVariable\(\s*"WIB_BACKEND_ROOT"'
        $resolver | Should -Match 'AppContext\.BaseDirectory'
    }

    It 'keeps event transport byte-safe and schema-guarded' {
        $reader = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Backend\NdjsonEventReader.cs') -Raw -Encoding UTF8
        $reader | Should -Match 'byte\[\]\s+_partial'
        $reader | Should -Match 'throwOnInvalidBytes:\s*true'
        $reader | Should -Match 'SchemaVersion\s*!=\s*1'
        $reader | Should -Match 'Sequence\s*<=\s*_lastSequence'
    }
}
