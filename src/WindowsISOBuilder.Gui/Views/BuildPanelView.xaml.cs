using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Views;

public partial class BuildPanelView : UserControl
{
    private readonly GuiLogger _log = new();
    public BuildPanelView() => InitializeComponent();
    private MainViewModel ViewModel => (MainViewModel)DataContext;

    private void OpenResultFolder_Click(object sender, RoutedEventArgs e) => ViewModel.OpenPath(ViewModel.ResultDirectory);
    private void OpenResultLog_Click(object sender, RoutedEventArgs e) => ViewModel.OpenPath(ViewModel.Result?.LogPath);
    private void OpenErrorLog_Click(object sender, RoutedEventArgs e) => ViewModel.OpenPath(ViewModel.ErrorLogPath);
    private void CopySha_Click(object sender, RoutedEventArgs e) { if (!string.IsNullOrWhiteSpace(ViewModel.Result?.Sha256)) Clipboard.SetText(ViewModel.Result.Sha256); }
    private void StartOver_Click(object sender, RoutedEventArgs e) => ViewModel.StartOver();
    private void CreateDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        if (Window.GetWindow(this) is Window owner) UiActions.CreateDiagnostics(owner, ViewModel, _log);
    }
}
