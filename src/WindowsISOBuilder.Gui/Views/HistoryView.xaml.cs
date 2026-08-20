using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Views;

public partial class HistoryView : UserControl
{
    public event EventHandler? BuildActivated;
    public event EventHandler? CatalogActivated;
    private MainViewModel ViewModel => (MainViewModel)DataContext;
    private LocalizationService Loc => LocalizationService.Instance;

    public HistoryView() => InitializeComponent();

    private void OnLoaded(object sender, RoutedEventArgs e) => ViewModel.RefreshHistory();
    private void AllFilter_Click(object sender, RoutedEventArgs e) => ViewModel.SetHistoryFilter(HistoryFilter.All);
    private void CompletedFilter_Click(object sender, RoutedEventArgs e) => ViewModel.SetHistoryFilter(HistoryFilter.Completed);
    private void FailedFilter_Click(object sender, RoutedEventArgs e) => ViewModel.SetHistoryFilter(HistoryFilter.Failed);
    private void CancelledFilter_Click(object sender, RoutedEventArgs e) => ViewModel.SetHistoryFilter(HistoryFilter.Cancelled);

    private void Details_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not HistoryEntry entry) return;
        new HistoryDetailsWindow(entry) { Owner = Window.GetWindow(this) }.ShowDialog();
    }

    private async void Repeat_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not HistoryEntry entry) return;
        try
        {
            var result = await ViewModel.RepeatHistoryAsync(entry);
            if (result == StoredApplyResult.Applied)
            {
                BuildActivated?.Invoke(this, EventArgs.Empty);
                return;
            }

            var dialog = new StoredBuildUnavailableWindow(history: true) { Owner = Window.GetWindow(this) };
            if (dialog.ShowDialog() != true) return;
            if (dialog.Choice == StoredBuildUnavailableChoice.Catalog)
            {
                ViewModel.SearchText = entry.Build;
                CatalogActivated?.Invoke(this, EventArgs.Empty);
                return;
            }
            if (dialog.Choice == StoredBuildUnavailableChoice.Recommended &&
                await ViewModel.RepeatHistoryAsync(entry, useRecommendedFallback: true) == StoredApplyResult.Applied)
            {
                BuildActivated?.Invoke(this, EventArgs.Empty);
            }
        }
        catch (Exception exception)
        {
            ViewModel.ReportFrontendActionError(exception);
        }
    }

    private void CreateProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not HistoryEntry entry) return;
        var draft = ViewModel.CreateProfileDraftFromHistory(entry);
        var pinCandidate = new PinnedBuildIdentity
        {
            Product = entry.Product,
            VersionLabel = entry.VersionLabel,
            Build = entry.Build,
            Architecture = entry.Architecture,
            IsPreview = false
        };
        new ProfileEditorWindow(ViewModel, draft, pinCandidate) { Owner = Window.GetWindow(this) }.ShowDialog();
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not HistoryEntry entry) return;
        if (MessageBox.Show(Window.GetWindow(this), Loc.Get("HistoryDeleteMessage"), Loc.Get("HistoryDeleteTitle"), MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
        {
            ViewModel.DeleteHistory(entry);
        }
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(Window.GetWindow(this), Loc.Get("HistoryClearMessage"), Loc.Get("HistoryClearTitle"), MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
        {
            ViewModel.ClearHistory();
        }
    }
}
