using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Views;

public partial class QuickView : UserControl
{
    public QuickView() => InitializeComponent();
    private MainViewModel ViewModel => (MainViewModel)DataContext;

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { InitialDirectory = ViewModel.OutputDirectory, Multiselect = false };
        if (dialog.ShowDialog(Window.GetWindow(this)) == true) ViewModel.OutputDirectory = dialog.FolderName;
    }

    private void Advanced_Click(object sender, RoutedEventArgs e) => new AdvancedOptionsWindow(ViewModel) { Owner = Window.GetWindow(this) }.ShowDialog();
    private void PreflightDetails_Click(object sender, RoutedEventArgs e) => new PreflightDetailsWindow(ViewModel.Checks) { Owner = Window.GetWindow(this) }.ShowDialog();

    private void StoredLanguage_SelectionChanged(object sender, SelectionChangedEventArgs e) => ViewModel.AcknowledgeStoredConfigurationChange();

    private void SaveProfile_Click(object sender, RoutedEventArgs e)
    {
        var loc = LocalizationService.Instance;
        if (ViewModel.SelectedBuild is null || ViewModel.SelectedLanguage is null || !ViewModel.Editions.Any(choice => choice.Selected))
        {
            MessageBox.Show(
                Window.GetWindow(this),
                loc.Format("ProfileAvailabilityStale", loc.Get("ProfileEditions")),
                loc.Get("ProfileEditorTitle"),
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        var draft = ViewModel.CreateProfileDraftFromCurrent();
        var pinCandidate = PinnedBuildIdentity.FromBuild(ViewModel.SelectedBuild);
        new ProfileEditorWindow(ViewModel, draft, pinCandidate) { Owner = Window.GetWindow(this) }.ShowDialog();
    }
}
