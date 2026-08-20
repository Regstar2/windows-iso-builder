using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Views;

public partial class SettingsView : UserControl
{
    private bool _initializing;

    internal event Action<string>? LanguageChanged;
    internal event Action<string>? ThemeChanged;
    internal event Action? DiagnosticsRequested;

    public SettingsView() => InitializeComponent();

    internal void Initialize(string language, string theme)
    {
        _initializing = true;
        try
        {
            LanguageCombo.SelectedValue = LocalizationService.NormalizeLanguage(language);
            ThemeCombo.SelectedValue = ThemeService.Normalize(theme);
        }
        finally
        {
            _initializing = false;
        }
    }

    private void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_initializing && LanguageCombo.SelectedValue is string language) LanguageChanged?.Invoke(language);
    }

    private void ThemeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_initializing && ThemeCombo.SelectedValue is string theme) ThemeChanged?.Invoke(theme);
    }

    private void CreateDiagnostics_Click(object sender, RoutedEventArgs e) => DiagnosticsRequested?.Invoke();
}
