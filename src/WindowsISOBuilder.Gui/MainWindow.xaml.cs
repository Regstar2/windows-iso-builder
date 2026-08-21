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
    private readonly NetworkPolicyService _networkPolicyService = new();
    private readonly ProxyCredentialStore _proxyCredentialStore = new();
    private readonly GitHubReleaseUpdateService _updateService;
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
        _updateService = new GitHubReleaseUpdateService(new NetworkHttpClientProvider(_networkPolicyService, _proxyCredentialStore));
        InitializeComponent();
        DataContext = new MainViewModel();
        RestoreWindow(settings);

        SettingsPage.LanguageChanged += OnLanguageChanged;
        SettingsPage.ThemeChanged += OnThemeChanged;
        SettingsPage.UpdateChannelChanged += OnUpdateChannelChanged;
        SettingsPage.UpdateCheckRequested += CheckForUpdates;
        SettingsPage.DiagnosticsRequested += CreateDiagnostics;
        SettingsPage.NetworkSaveRequested += SaveNetworkSettings;
        SettingsPage.NetworkTestRequested += TestNetworkSettings;
        SettingsPage.NetworkCredentialClearRequested += ClearNetworkCredential;

        NetworkPolicy networkPolicy;
        string? networkLoadError = null;
        try
        {
            networkPolicy = _networkPolicyService.Load();
        }
        catch (NetworkPolicyException exception)
        {
            networkPolicy = NetworkPolicyService.DefaultPolicy();
            networkLoadError = Loc.Get("NetworkSettingsInvalid");
            _log.Error("Network policy could not be loaded", exception);
        }
        SettingsPage.Initialize(Loc.CurrentLanguage, _theme, _updateChannel, networkPolicy);
        if (!string.IsNullOrWhiteSpace(networkLoadError)) SettingsPage.SetNetworkStatus(networkLoadError);

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
        RefreshNetworkLocalization();
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

    private void SaveNetworkSettings(NetworkSettingsInput input)
    {
        SettingsPage.SetNetworkBusy(true);
        var credentialExisted = _proxyCredentialStore.Exists;
        var wroteCredential = false;
        try
        {
            var policy = NetworkPolicyService.FromInput(input, credentialExisted);
            if (!string.IsNullOrEmpty(input.Password))
            {
                _proxyCredentialStore.Save(input.Password);
                wroteCredential = true;
                policy.HasCredential = true;
            }
            _networkPolicyService.Save(policy);
            SettingsPage.ClearPasswordEntry();
            SettingsPage.SetCredentialState(policy.HasCredential);
            SettingsPage.SetNetworkStatus(Loc.Get("NetworkSettingsSaved"));
        }
        catch (Exception exception)
        {
            if (wroteCredential && !credentialExisted)
            {
                try { _proxyCredentialStore.Clear(); } catch { }
            }
            _log.Error("Network settings could not be saved", exception);
            SettingsPage.SetNetworkStatus(MapNetworkFailure(exception));
        }
        finally
        {
            SettingsPage.SetNetworkBusy(false);
        }
    }

    private async void TestNetworkSettings(NetworkSettingsInput input)
    {
        SettingsPage.SetNetworkBusy(true);
        SettingsPage.SetNetworkStatus(Loc.Get("NetworkTestRunning"));
        try
        {
            var policy = NetworkPolicyService.FromInput(input, _proxyCredentialStore.Exists);
            string? password = null;
            if (!string.IsNullOrEmpty(input.Password)) password = input.Password;
            else if (policy.HasCredential) password = _proxyCredentialStore.Load();

            var result = await NetworkConnectionTester.TestAsync(policy, password);
            SettingsPage.SetNetworkStatus(result.Success ? Loc.Get("NetworkTestSuccess") : MapNetworkFailure(result.Code));
        }
        catch (Exception exception)
        {
            _log.Error("Network connection test failed", exception);
            SettingsPage.SetNetworkStatus(MapNetworkFailure(exception));
        }
        finally
        {
            SettingsPage.SetNetworkBusy(false);
        }
    }

    private void ClearNetworkCredential()
    {
        SettingsPage.SetNetworkBusy(true);
        try
        {
            _proxyCredentialStore.Clear();
            try
            {
                var policy = _networkPolicyService.Load();
                policy.HasCredential = false;
                _networkPolicyService.Save(policy);
            }
            catch (NetworkPolicyException)
            {
                // Invalid non-secret policy remains visible as invalid; clearing the secret is still authoritative.
            }
            SettingsPage.ClearPasswordEntry();
            SettingsPage.SetCredentialState(false);
            SettingsPage.SetNetworkStatus(Loc.Get("NetworkCredentialCleared"));
        }
        catch (Exception exception)
        {
            _log.Error("Proxy credential could not be cleared", exception);
            SettingsPage.SetNetworkStatus(MapNetworkFailure(exception));
        }
        finally
        {
            SettingsPage.SetNetworkBusy(false);
        }
    }

    private string MapNetworkFailure(Exception exception) => exception is NetworkPolicyException policyException
        ? MapNetworkFailure(policyException.Code)
        : Loc.Get("NetworkTestFailed");

    private string MapNetworkFailure(string code) => code switch
    {
        "PROXY_CONFIGURATION_INVALID" => Loc.Get("NetworkSettingsInvalid"),
        "PROXY_CREDENTIAL_REQUIRES_USERNAME" => Loc.Get("NetworkCredentialRequiresUsername"),
        "PROXY_CREDENTIAL_UNAVAILABLE" => Loc.Get("NetworkCredentialUnavailable"),
        "PROXY_AUTHENTICATION_FAILED" => Loc.Get("NetworkProxyAuthenticationFailed"),
        "PROXY_CONNECTION_FAILED" => Loc.Get("NetworkProxyUnavailable"),
        "NETWORK_TIMEOUT" => Loc.Get("NetworkTimeout"),
        _ => Loc.Get("NetworkTestFailed")
    };

    private void RefreshNetworkLocalization()
    {
        try
        {
            var policy = _networkPolicyService.Load();
            SettingsPage.SetCredentialState(policy.HasCredential);
        }
        catch
        {
            SettingsPage.SetNetworkStatus(Loc.Get("NetworkSettingsInvalid"));
        }
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
