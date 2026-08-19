using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui;

public partial class MainWindow : Window
{
    private readonly AppSettingsService _settingsService;
    private readonly GuiLogger _log = new();
    private bool _allowClose;
    private MainViewModel ViewModel => (MainViewModel)DataContext;
    private LocalizationService Loc => LocalizationService.Instance;

    internal MainWindow(AppSettingsService settingsService, AppSettings settings)
    {
        _settingsService = settingsService;
        InitializeComponent();
        DataContext = new MainViewModel();
        RestoreWindow(settings);
        UiLanguageCombo.SelectedValue = Loc.CurrentLanguage;
        Closing += OnClosing;
    }

    private void Quick_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.Architecture.Equals("all", StringComparison.OrdinalIgnoreCase)) ViewModel.Architecture = "amd64";
        Tabs.SelectedIndex = 0;
        QuickNav.IsChecked = true;
    }

    private void Catalog_Click(object sender, RoutedEventArgs e)
    {
        Tabs.SelectedIndex = 1;
        CatalogNav.IsChecked = true;
    }

    private void CatalogView_BuildActivated(object? sender, EventArgs e)
    {
        Tabs.SelectedIndex = 0;
        QuickNav.IsChecked = true;
    }

    private void UiLanguage_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (UiLanguageCombo.SelectedValue is string language) Loc.SetCulture(language);
    }

    private void CreateDiagnostics_Click(object sender, RoutedEventArgs e) => UiActions.CreateDiagnostics(this, ViewModel, _log);

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
            Language = Loc.CurrentLanguage
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
