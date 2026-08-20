using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui;

public partial class MainWindow : Window
{
    private readonly AppSettingsService _settingsService;
    private readonly GuiLogger _log = new();
    private readonly GitHubReleaseUpdateService _updateService = new(new SystemHttpClientProvider());
    private bool _allowClose;
    private string _theme;
    private string _updateChannel;
    private MainViewModel ViewModel => (MainViewModel)DataContext;
    private LocalizationService Loc => LocalizationService.Instance;

    internal MainWindow(AppSettingsService settingsService, AppSettings settings)
    {
        _settingsService = settingsService;
        _theme = ThemeService.Normalize(settings.Theme);
        _updateChannel = UpdateChannelService.Normalize(settings.UpdateChannel);
        InitializeComponent();
        DataContext = new MainViewModel();
        RestoreWindow(settings);

        SettingsPage.LanguageChanged += OnLanguageChanged;
        SettingsPage.ThemeChanged += OnThemeChanged;
        SettingsPage.UpdateChannelChanged += OnUpdateChannelChanged;
        SettingsPage.UpdateCheckRequested += CheckForUpdates;
        SettingsPage.DiagnosticsRequested += CreateDiagnostics;
        SettingsPage.Initialize(Loc.CurrentLanguage, _theme, _updateChannel);

        Closing += OnClosing;
    }

    private void Build_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.Architecture.Equals("all", StringComparison.OrdinalIgnoreCase)) ViewModel.Architecture = "amd64";
        SelectPage(0, BuildNav);
    }

    private void Catalog_Click(object sender, RoutedEventArgs e) => SelectPage(1, CatalogNav);
    private void Settings_Click(object sender, RoutedEventArgs e) => SelectPage(2, SettingsNav);
    private void Help_Click(object sender, RoutedEventArgs e) => SelectPage(3, HelpNav);
    private void About_Click(object sender, RoutedEventArgs e) => SelectPage(4, AboutNav);

    private void CatalogView_BuildActivated(object? sender, EventArgs e) => SelectPage(0, BuildNav);

    private void SelectPage(int index, System.Windows.Controls.RadioButton navigationItem)
    {
        Tabs.SelectedIndex = index;
        navigationItem.IsChecked = true;
    }

    private void OnLanguageChanged(string language)
    {
        Loc.SetCulture(language);
        SaveWindowSettings();
    }

    private void OnThemeChanged(string theme)
    {
        _theme = ThemeService.Normalize(theme);
        ThemeService.Apply(_theme);
        SaveWindowSettings();
    }

    private void OnUpdateChannelChanged(string channel)
    {
        _updateChannel = UpdateChannelService.Normalize(channel);
        SaveWindowSettings();
    }

    private async void CheckForUpdates()
    {
        SettingsPage.SetUpdateCheckBusy(true);
        try
        {
            var result = await _updateService.CheckAsync(ViewModel.Version, _updateChannel);
            if (result.Status == UpdateCheckStatus.UpdateAvailable)
            {
                var notes = string.IsNullOrWhiteSpace(result.ReleaseNotes) ? Loc.Get("UpdateNoNotes") : result.ReleaseNotes;
                var message = Loc.Format("UpdateAvailableMessageFormat", result.CurrentVersion, result.LatestVersion ?? "?", notes);
                if (result.ReleaseUrl is not null)
                {
                    var choice = MessageBox.Show(this, message, Loc.Get("UpdateAvailableTitle"), MessageBoxButton.YesNo, MessageBoxImage.Information);
                    if (choice == MessageBoxResult.Yes) OpenTrustedReleasePage(result.ReleaseUrl);
                }
                else
                {
                    MessageBox.Show(this, message, Loc.Get("UpdateAvailableTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
                }
                return;
            }

            if (result.Status == UpdateCheckStatus.NoPublishedRelease)
            {
                MessageBox.Show(this, Loc.Get("UpdateNoPublishedReleaseMessage"), Loc.Get("UpdateCheckTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            MessageBox.Show(this, Loc.Format("UpdateUpToDateMessageFormat", result.CurrentVersion), Loc.Get("UpdateCheckTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception exception)
        {
            _log.Error("Update check failed", exception);
            MessageBox.Show(this, Loc.Get("UpdateCheckFailedMessage"), Loc.Get("UpdateCheckFailedTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            SettingsPage.SetUpdateCheckBusy(false);
        }
    }

    private void OpenTrustedReleasePage(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
            !uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            !uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase))
        {
            _log.Info("Blocked non-GitHub update URL");
            MessageBox.Show(this, Loc.Get("UpdateOpenReleaseFailedMessage"), Loc.Get("UpdateOpenReleaseFailedTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            _log.Error("Failed to open release page", exception);
            MessageBox.Show(this, Loc.Get("UpdateOpenReleaseFailedMessage"), Loc.Get("UpdateOpenReleaseFailedTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
        }
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
            Theme = _theme,
            UpdateChannel = _updateChannel
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
