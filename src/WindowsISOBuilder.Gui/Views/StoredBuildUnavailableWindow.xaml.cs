using System.Windows;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Views;

internal enum StoredBuildUnavailableChoice
{
    Cancel,
    Recommended,
    Catalog
}

public partial class StoredBuildUnavailableWindow : Window
{
    public StoredBuildUnavailableChoice Choice { get; private set; }

    public StoredBuildUnavailableWindow(bool history)
    {
        InitializeComponent();
        var loc = LocalizationService.Instance;
        TitleText.Text = loc.Get(history ? "StoredBuildMissingHistoryTitle" : "StoredBuildMissingProfileTitle");
        MessageText.Text = loc.Get(history ? "StoredBuildMissingHistoryMessage" : "StoredBuildMissingProfileMessage");
        Title = TitleText.Text;
    }

    private void Recommended_Click(object sender, RoutedEventArgs e)
    {
        Choice = StoredBuildUnavailableChoice.Recommended;
        DialogResult = true;
    }

    private void Catalog_Click(object sender, RoutedEventArgs e)
    {
        Choice = StoredBuildUnavailableChoice.Catalog;
        DialogResult = true;
    }
}
