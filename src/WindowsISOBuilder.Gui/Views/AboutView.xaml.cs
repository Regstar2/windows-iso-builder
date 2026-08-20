using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Views;

public partial class AboutView : UserControl
{
    private const string RepositoryUrl = "https://github.com/Regstar2/windows-iso-builder";
    private const string BugReportUrl = RepositoryUrl + "/issues/new?template=bug_report.yml";
    private const string FeatureRequestUrl = RepositoryUrl + "/issues/new?template=feature_request.yml";

    public AboutView() => InitializeComponent();

    private void OpenGitHub_Click(object sender, RoutedEventArgs e) => OpenUrl(RepositoryUrl);
    private void ReportBug_Click(object sender, RoutedEventArgs e) => OpenUrl(BugReportUrl);
    private void RequestFeature_Click(object sender, RoutedEventArgs e) => OpenUrl(FeatureRequestUrl);

    private static void OpenUrl(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch
        {
            var loc = LocalizationService.Instance;
            MessageBox.Show(loc.Get("AboutOpenGitHubErrorMessage"), loc.Get("AboutOpenGitHubErrorTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
