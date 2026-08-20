using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Views;

public partial class SettingsView : UserControl
{
    private bool _initializing;
    private bool _hasSavedCredential;

    internal event Action<string>? LanguageChanged;
    internal event Action<string>? ThemeChanged;
    internal event Action<string>? UpdateChannelChanged;
    internal event Action? UpdateCheckRequested;
    internal event Action? DiagnosticsRequested;
    internal event Action<NetworkSettingsInput>? NetworkSaveRequested;
    internal event Action<NetworkSettingsInput>? NetworkTestRequested;
    internal event Action? NetworkCredentialClearRequested;

    public SettingsView() => InitializeComponent();

    internal void Initialize(string language, string theme, string updateChannel, NetworkPolicy networkPolicy)
    {
        _initializing = true;
        try
        {
            LanguageCombo.SelectedValue = LocalizationService.NormalizeLanguage(language);
            ThemeCombo.SelectedValue = ThemeService.Normalize(theme);
            UpdateChannelCombo.SelectedValue = UpdateChannelService.Normalize(updateChannel);
            NetworkModeCombo.SelectedValue = networkPolicy.Mode;
            ProxyTypeCombo.SelectedValue = networkPolicy.ProxyType ?? NetworkPolicyService.HttpProxy;
            ProxyHostTextBox.Text = networkPolicy.Host ?? string.Empty;
            ProxyPortTextBox.Text = networkPolicy.Port?.ToString() ?? string.Empty;
            ProxyUsernameTextBox.Text = networkPolicy.Username ?? string.Empty;
            ProxyPasswordBox.Password = string.Empty;
            SetCredentialState(networkPolicy.HasCredential);
            UpdateCustomEnabled();
        }
        finally
        {
            _initializing = false;
        }
    }

    internal void SetUpdateCheckBusy(bool busy)
    {
        CheckUpdatesButton.IsEnabled = !busy;
        UpdateChannelCombo.IsEnabled = !busy;
    }

    internal void SetNetworkBusy(bool busy)
    {
        SaveNetworkButton.IsEnabled = !busy;
        TestNetworkButton.IsEnabled = !busy;
        ClearCredentialButton.IsEnabled = !busy && _hasSavedCredential;
    }

    internal void SetNetworkStatus(string text) => NetworkStatusText.Text = text;
    internal void ClearPasswordEntry() => ProxyPasswordBox.Password = string.Empty;

    internal void SetCredentialState(bool hasCredential)
    {
        _hasSavedCredential = hasCredential;
        CredentialStatusText.Text = LocalizationService.Instance.Get(hasCredential ? "ProxyCredentialSaved" : "ProxyCredentialNotSaved");
        ClearCredentialButton.IsEnabled = hasCredential;
    }

    private NetworkSettingsInput GetNetworkInput() => new(
        NetworkModeCombo.SelectedValue as string ?? NetworkPolicyService.SystemMode,
        ProxyTypeCombo.SelectedValue as string ?? NetworkPolicyService.HttpProxy,
        ProxyHostTextBox.Text,
        ProxyPortTextBox.Text,
        ProxyUsernameTextBox.Text,
        ProxyPasswordBox.Password);

    private void UpdateCustomEnabled()
    {
        var custom = string.Equals(NetworkModeCombo.SelectedValue as string, NetworkPolicyService.CustomMode, StringComparison.OrdinalIgnoreCase);
        foreach (var element in new UIElement[] { ProxyTypePanel, ProxyHostPanel, ProxyPortPanel, ProxyUsernamePanel, ProxyPasswordPanel })
        {
            element.IsEnabled = custom;
            element.IsHitTestVisible = custom;
            element.Focusable = custom;
        }
        ClearCredentialButton.Visibility = custom ? Visibility.Visible : Visibility.Collapsed;
    }

    private void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_initializing && LanguageCombo.SelectedValue is string language) LanguageChanged?.Invoke(language);
    }

    private void ThemeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_initializing && ThemeCombo.SelectedValue is string theme) ThemeChanged?.Invoke(theme);
    }

    private void UpdateChannelCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_initializing && UpdateChannelCombo.SelectedValue is string channel) UpdateChannelChanged?.Invoke(channel);
    }

    private void NetworkModeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_initializing) UpdateCustomEnabled();
    }

    private void SaveNetwork_Click(object sender, RoutedEventArgs e) => NetworkSaveRequested?.Invoke(GetNetworkInput());
    private void TestNetwork_Click(object sender, RoutedEventArgs e) => NetworkTestRequested?.Invoke(GetNetworkInput());
    private void ClearCredential_Click(object sender, RoutedEventArgs e) => NetworkCredentialClearRequested?.Invoke();
    private void CheckUpdates_Click(object sender, RoutedEventArgs e) => UpdateCheckRequested?.Invoke();
    private void CreateDiagnostics_Click(object sender, RoutedEventArgs e) => DiagnosticsRequested?.Invoke();
}
