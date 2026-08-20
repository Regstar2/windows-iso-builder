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

    It 'keeps read-only progress and inline text bindings one-way' {
        $buildPanelXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\BuildPanelView.xaml') -Raw -Encoding UTF8
        $viewModel = @('MainViewModel.cs','MainViewModel.Metadata.cs','MainViewModel.Build.cs','MainViewModel.Guidance.cs') | ForEach-Object { Get-Content -LiteralPath (Join-Path $script:projectRoot ('src\WindowsISOBuilder.Gui\ViewModels\' + $_)) -Raw -Encoding UTF8 } | Out-String
        $buildPanelXaml | Should -Match 'ProgressBar\s+Value="\{Binding Progress,\s*Mode=OneWay\}"'
        $buildPanelXaml | Should -Match '<Run\s+Text="\{Binding Status,\s*Mode=OneWay\}"'
        $buildPanelXaml | Should -Match '<Run\s+Text="\{Binding Speed,\s*Mode=OneWay\}"'
        $buildPanelXaml | Should -Match '<Run\s+Text="\{Binding Result\.Sha256,\s*Mode=OneWay\}"'
        $viewModel | Should -Match 'public\s+double\s+Progress\s*\{\s*get\s*=>\s*_progress;\s*private\s+set'
        $viewModel | Should -Match 'public\s+string\s+Speed\s*\{\s*get\s*=>\s*_speed;\s*private\s+set'
        $viewModel | Should -Match 'public\s+string\s+Status\s*=>'
    }

    It 'prevents sync-context deadlock in packaged backend smoke' {
        $smoke = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\BackendSmoke.cs') -Raw -Encoding UTF8
        $smoke | Should -Match '\.ConfigureAwait\(false\)'
    }

    It 'keeps output directory creation and writability in backend preflight' {
        $viewModel = @('MainViewModel.cs','MainViewModel.Metadata.cs','MainViewModel.Build.cs','MainViewModel.Guidance.cs') | ForEach-Object { Get-Content -LiteralPath (Join-Path $script:projectRoot ('src\WindowsISOBuilder.Gui\ViewModels\' + $_)) -Raw -Encoding UTF8 } | Out-String
        $viewModel | Should -Not -Match 'Directory\.CreateDirectory\(\s*OutputDirectory\s*\)'
        $viewModel | Should -Match 'RunPreflight'
    }

    It 'gates the interactive GUI on the startup backend handshake' {
        $viewModel = @('MainViewModel.cs','MainViewModel.Metadata.cs','MainViewModel.Build.cs','MainViewModel.Guidance.cs') | ForEach-Object { Get-Content -LiteralPath (Join-Path $script:projectRoot ('src\WindowsISOBuilder.Gui\ViewModels\' + $_)) -Raw -Encoding UTF8 } | Out-String
        $viewModel | Should -Match 'State\s*=\s*UiState\.LoadingBuild'
        $viewModel | Should -Match 'InvokeAsync<VersionData>\("GetVersion"'
    }

    It 'shows actual preflight status instead of failure severity' {
        $xaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\PreflightDetailsWindow.xaml') -Raw -Encoding UTF8
        $dtos = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Models\ContractDtos.cs') -Raw -Encoding UTF8
        $xaml | Should -Match 'Binding="\{Binding StatusLabel, Mode=OneWay\}"'
        $xaml | Should -Not -Match 'Binding="\{Binding Severity\}"'
        $dtos | Should -Match 'StatusLabel\s*=>\s*Status\.ToLowerInvariant\(\)\s*switch'
        foreach ($status in @('pass','warning','fail','skipped')) { $dtos | Should -Match ('"{0}"\s*=>' -f $status) }
    }

    It 'sanitizes technical diagnostics through one reusable sanitizer' {
        $viewModel = @('MainViewModel.cs','MainViewModel.Metadata.cs','MainViewModel.Build.cs','MainViewModel.Guidance.cs') | ForEach-Object { Get-Content -LiteralPath (Join-Path $script:projectRoot ('src\WindowsISOBuilder.Gui\ViewModels\' + $_)) -Raw -Encoding UTF8 } | Out-String
        $logger = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\GuiLogger.cs') -Raw -Encoding UTF8
        $sanitizer = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\DiagnosticSanitizer.cs') -Raw -Encoding UTF8
        $viewModel | Should -Match 'DiagnosticSanitizer\.Sanitize\(backendException\.Message\)'
        $logger | Should -Match 'DiagnosticSanitizer\.Sanitize'
        foreach ($marker in @('<URL>','<PRODUCT_KEY>','<USERPROFILE>','<USERNAME>','<SECRET>')) { $sanitizer | Should -Match ([regex]::Escape($marker)) }
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

Describe 'GUI polish regression boundaries' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:mainXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml') -Raw -Encoding UTF8
    }

    It 'keeps Build page-level scrolling removed and the build panel persistent' {
        $quickXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\QuickView.xaml') -Raw -Encoding UTF8
        $buildPanelXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\BuildPanelView.xaml') -Raw -Encoding UTF8
        $script:mainXaml | Should -Not -Match '<TabItem[^>]*Header='
        $quickXaml | Should -Not -Match '<ScrollViewer\s+VerticalScrollBarVisibility="Auto">\s*<StackPanel\s+Margin="24"'
        $quickXaml | Should -Match 'x:Name="QuickLayout"'
        $quickXaml | Should -Match 'BuildPageTitle'
        $quickXaml | Should -Match '<views:BuildPanelView'
        $buildPanelXaml | Should -Match 'x:Name="BuildPanel"'
        foreach ($state in @('ShowBuildIdle','ShowBuildProgress','ShowBuildError','ShowBuildResult')) { $buildPanelXaml | Should -Match $state }
    }

    It 'keeps hidden tab navigation out of keyboard focus' {
        $script:mainXaml | Should -Match '<TabControl\.Template>'
        $script:mainXaml | Should -Match 'Focusable="False"'
        $script:mainXaml | Should -Match 'IsTabStop="False"'
    }

    It 'keeps Catalog collection scrolling inside the DataGrid with a persistent action row' {
        $catalogXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\CatalogView.xaml') -Raw -Encoding UTF8
        $catalogCode = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\CatalogView.xaml.cs') -Raw -Encoding UTF8
        $catalogXaml | Should -Match 'x:Name="CatalogGrid"'
        $catalogXaml | Should -Match '<RowDefinition Height="\*"/>'
        $catalogXaml | Should -Match '<WrapPanel Orientation="Horizontal">'
        $catalogCode | Should -Match 'UseCatalogBuild_Click'
    }

    It 'uses centralized RU and EN localization with English fallback and a canonical application version' {
        $project = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\WindowsISOBuilder.Gui.csproj') -Raw -Encoding UTF8
        $localization = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\LocalizationService.cs') -Raw -Encoding UTF8
        foreach ($group in @('Core','Pages','Automation','Errors','Status')) {
            Test-Path -LiteralPath (Join-Path $script:projectRoot ("src\WindowsISOBuilder.Gui\Resources\Strings.{0}.resx" -f $group)) | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:projectRoot ("src\WindowsISOBuilder.Gui\Resources\Strings.{0}.ru.resx" -f $group)) | Should -BeTrue
        }
        $localization | Should -Match 'EnglishCulture'
        $localization | Should -Match 'RussianCulture'
        $localization | Should -Match 'return "en"'
        $script:mainXaml | Should -Match 'services:Loc'
        $version = [IO.File]::ReadAllText((Join-Path $script:projectRoot 'VERSION'), [Text.Encoding]::ASCII).Trim()
        $project | Should -Match ('<Version>{0}</Version>' -f [regex]::Escape($version))
    }

    It 'uses application ThemeMode with persisted System Light and Dark choices' {
        $app = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\App.xaml') -Raw -Encoding UTF8
        $manifest = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\app.manifest') -Raw -Encoding UTF8
        $styles = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Resources\Styles.xaml') -Raw -Encoding UTF8
        $theme = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\ThemeService.cs') -Raw -Encoding UTF8
        $app | Should -Match 'ThemeMode="System"'
        $manifest | Should -Match 'PerMonitorV2'
        $theme | Should -Match 'ThemeMode\.System'
        $theme | Should -Match 'ThemeMode\.Light'
        $theme | Should -Match 'ThemeMode\.Dark'
        $theme | Should -Match 'WibPageBackgroundBrush'
        $theme | Should -Match 'AppsUseLightTheme'
        $styles | Should -Not -Match 'PresentationFramework\.Fluent;component/Themes/Fluent\.xaml'
        $styles | Should -Match '<Style TargetType="UserControl">'
        $styles | Should -Match 'WibTextBrush'
        $styles | Should -Match 'WibCardBrush'
        $styles | Should -Not -Match '#F5F5F5|#EEEEEE|Background="White"'
    }

    It 'keeps the compact shell hierarchy and complete navigation' {
        $styles = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Resources\Styles.xaml') -Raw -Encoding UTF8
        $quick = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\QuickView.xaml') -Raw -Encoding UTF8
        $catalog = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\CatalogView.xaml') -Raw -Encoding UTF8
        $build = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\BuildPanelView.xaml') -Raw -Encoding UTF8
        $styles | Should -Match 'x:Key="NavigationRadio"'
        $styles | Should -Match 'x:Key="PrimaryButton"'
        $styles | Should -Match 'x:Key="GuidedActionButton"'
        foreach ($nav in @('BuildNav','CatalogNav','SettingsNav','HelpNav','AboutNav')) { $script:mainXaml | Should -Match ('x:Name="{0}"' -f $nav) }
        $script:mainXaml | Should -Match '<views:SettingsView x:Name="SettingsPage"/>'
        $script:mainXaml | Should -Match '<views:HelpView/>'
        $script:mainXaml | Should -Match '<views:AboutView/>'
        $quick | Should -Match 'Style="\{StaticResource StatusBanner\}"'
        $quick | Should -Match 'Style="\{StaticResource FieldLabel\}"'
        $quick | Should -Match 'Tag="\{Binding HighlightRecommended\}"'
        $quick | Should -Match 'Tag="\{Binding HighlightEditions\}"'
        $quick | Should -Match 'Tag="\{Binding HighlightPreflight\}"'
        $catalog | Should -Match 'Style="\{StaticResource PrimaryButton\}"'
        $build | Should -Match 'Style="\{StaticResource GuidedActionButton\}"'
        $build | Should -Match 'Tag="\{Binding HighlightBuild\}"'
    }

    It 'keeps diagnostics archive entries controlled and sanitized before ZIP writes' {
        $diagnostics = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\DiagnosticsService.cs') -Raw -Encoding UTF8
        foreach ($entry in @('app-version.txt','environment.json','execution.log','build.log','converter.log')) { $diagnostics | Should -Match ([regex]::Escape($entry)) }
        $diagnostics | Should -Match 'DiagnosticSanitizer\.Sanitize'
        $diagnostics | Should -Not -Match 'CreateFromDirectory'
    }

    It 'persists window state language theme and update channel in a tolerant settings service' {
        $settings = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\AppSettingsService.cs') -Raw -Encoding UTF8
        $model = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Models\AppSettings.cs') -Raw -Encoding UTF8
        $settings | Should -Match 'settings\.json'
        $settings | Should -Match 'HasUsableBounds'
        $settings | Should -Match 'MonitorFromRect'
        $model | Should -Match 'IsMaximized'
        $model | Should -Match 'Language'
        $model | Should -Match 'Theme'
        $model | Should -Match 'UpdateChannel'
        $model | Should -Not -Match 'Minimized'
    }
}

Describe 'v0.3.3 feedback and update delivery regressions' {
    BeforeAll { $script:projectRoot = Split-Path -Parent $PSScriptRoot }

    It 'ships structured issue forms and safe in-app feedback links' {
        foreach ($form in @('bug_report.yml','feature_request.yml','config.yml')) {
            Test-Path -LiteralPath (Join-Path $script:projectRoot ('.github\ISSUE_TEMPLATE\' + $form)) | Should -BeTrue
        }
        $about = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\AboutView.xaml.cs') -Raw -Encoding UTF8
        $about | Should -Match 'issues/new\?template=bug_report\.yml'
        $about | Should -Match 'issues/new\?template=feature_request\.yml'
        $about | Should -Not -Match 'token=|Authorization|PAT'
    }

    It 'exposes Stable and Prerelease channels and a manual update action' {
        $settings = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\SettingsView.xaml') -Raw -Encoding UTF8
        $settings | Should -Match 'x:Name="UpdateChannelCombo"'
        $settings | Should -Match 'Tag="stable"'
        $settings | Should -Match 'Tag="prerelease"'
        $settings | Should -Match 'x:Name="CheckUpdatesButton"'
    }

    It 'keeps update delivery on the official GitHub Releases endpoint with no self-update execution' {
        $service = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\GitHubReleaseUpdateService.cs') -Raw -Encoding UTF8
        $window = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\MainWindow.xaml.cs') -Raw -Encoding UTF8
        $service | Should -Match 'api\.github\.com/repos/Regstar2/windows-iso-builder/releases'
        $service | Should -Not -Match 'Authorization'
        $window | Should -Match 'github\.com'
        $window | Should -Not -Match 'WebClient|DownloadFile|ProcessStartInfo\([^\)]*\.exe'
    }
}
