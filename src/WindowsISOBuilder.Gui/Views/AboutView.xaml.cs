using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Views;

public partial class AboutView : UserControl
{
    private const string RepositoryUrl = "https://github.com/Regstar2/windows-iso-builder";

    public AboutView() => InitializeComponent();

    private void OpenGitHub_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo(RepositoryUrl) { UseShellExecute = true });
        }
        catch
        {
            var loc = LocalizationService.Instance;
            MessageBox.Show(loc.Get("AboutOpenGitHubErrorMessage"), loc.Get("AboutOpenGitHubErrorTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
