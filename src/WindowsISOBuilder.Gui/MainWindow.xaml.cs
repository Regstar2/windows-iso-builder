using System.ComponentModel;
using System.Windows;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui;

public partial class MainWindow : Window
{
    private readonly AppSettingsService _settingsService;
    private readonly GuiLogger _log = new();
    private bool _allowClose;
    private string _theme;
    private MainViewModel ViewModel => (MainViewModel)DataContext;
    private LocalizationService Loc => LocalizationService.Instance;

    internal MainWindow(AppSettingsService settingsService, AppSettings settings)
    {
        _settingsService = settingsService;
        _theme = ThemeService.Normalize(settings.Theme);
        InitializeComponent();
        DataContext = new MainViewModel();
        RestoreWindow(settings);

        SettingsPage.LanguageChanged += OnLanguageChanged;
        SettingsPage.ThemeChanged += OnThemeChanged;
        SettingsPage.DiagnosticsRequested += CreateDiagnostics;
        SettingsPage.Initialize(Loc.CurrentLanguage, _theme);

        Closing += OnClosing;
    }

    private void Build_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.Architecture.Equals("all", StringComparison.OrdinalIgnoreCase)) ViewModel.Architecture = "amd64";
        SelectPage(0, BuildNav);
    }

    private void Catalog_Click(object sender, RoutedEventArgs e) => SelectPage(1, CatalogNav);
    private void History_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.RefreshHistory();
        SelectPage(2, HistoryNav);
    }
    private void Profiles_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.RefreshProfiles();
        SelectPage(3, ProfilesNav);
    }
    private void Settings_Click(object sender, RoutedEventArgs e) => SelectPage(4, SettingsNav);
    private void Help_Click(object sender, RoutedEventArgs e) => SelectPage(5, HelpNav);
    private void About_Click(object sender, RoutedEventArgs e) => SelectPage(6, AboutNav);

    private void CatalogView_BuildActivated(object? sender, EventArgs e) => SelectPage(0, BuildNav);
    private void StoredConfiguration_BuildActivated(object? sender, EventArgs e) => SelectPage(0, BuildNav);
    private void StoredConfiguration_CatalogActivated(object? sender, EventArgs e) => SelectPage(1, CatalogNav);

    private void SelectPage(int index, System.Windows.Controls.RadioButton navigationItem)
    {
        Tabs.SelectedIndex = index;
        navigationItem.IsChecked = true;
    }

    private void OnLanguageChanged(string language)
    {
        Loc.SetCulture(language);
        ViewModel.RefreshLocalData();
        SaveWindowSettings();
    }

    private void OnThemeChanged(string theme)
    {
        _theme = ThemeService.Normalize(theme);
        ThemeService.Apply(_theme);
        SaveWindowSettings();
    }

    private void CreateDiagnostics() => UiActions.CreateDiagnostics(this, ViewModel, _log);

    private void RestoreWindow(AppSettings settings)
    {
        if (AppSettingsService.HasUsableBoundsOnCurrentMonitors(settings))
        {
            WindowStartupLocation = WindowStartupLocation.Manual;
            Width = Math.Clamp(settings.Width!.Value, MinWidth, Math.Max(MinWidth, SystemParameters.VirtualScreenWidth));
            Height = Math.Clamp(settings.Height!.Value, MinHeight, Math.Max(MinHeight, SystemParameters.VirtualScreenHeight));
            Left = settings.Left!.Value;
            Top = settings.Top!.Value;
        }
        if (settings.IsMaximized) Loaded += (_, _) => WindowState = WindowState.Maximized;
    }

    private void SaveWindowSettings()
    {
        var bounds = WindowState == WindowState.Normal ? new Rect(Left, Top, ActualWidth, ActualHeight) : RestoreBounds;
        _settingsService.Save(new AppSettings
        {
            Left = bounds.Left,
            Top = bounds.Top,
            Width = bounds.Width,
            Height = bounds.Height,
            IsMaximized = WindowState == WindowState.Maximized,
            Language = Loc.CurrentLanguage,
            Theme = _theme
        });
    }

    private async void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_allowClose || !ViewModel.IsBuilding)
        {
            SaveWindowSettings();
            return;
        }
        e.Cancel = true;
        if (MessageBox.Show(this, Loc.Get("CancelCloseMessage"), Loc.Get("CancelCloseTitle"), MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        if (!await ViewModel.CancelAsync()) return;
        await ViewModel.WaitForBuildTerminationAsync();
        _allowClose = true;
        Close();
    }
}
