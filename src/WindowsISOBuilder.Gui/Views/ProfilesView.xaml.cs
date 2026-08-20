using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Views;

public partial class ProfilesView : UserControl
{
    public event EventHandler? BuildActivated;
    public event EventHandler? CatalogActivated;
    private MainViewModel ViewModel => (MainViewModel)DataContext;
    private LocalizationService Loc => LocalizationService.Instance;

    public ProfilesView() => InitializeComponent();

    private void OnLoaded(object sender, RoutedEventArgs e) => ViewModel.RefreshProfiles();

    private void Create_Click(object sender, RoutedEventArgs e)
    {
        var draft = new BuildProfile
        {
            Product = "Windows 11",
            Architecture = "amd64",
            SelectionMode = ProfileSelectionMode.Recommended,
            OutputDirectory = ViewModel.OutputDirectory
        };
        new ProfileEditorWindow(ViewModel, draft) { Owner = Window.GetWindow(this) }.ShowDialog();
    }

    private async void Use_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not BuildProfile profile) return;
        try
        {
            var result = await ViewModel.UseProfileAsync(profile);
            if (result == StoredApplyResult.Applied)
            {
                BuildActivated?.Invoke(this, EventArgs.Empty);
                return;
            }

            var dialog = new StoredBuildUnavailableWindow(history: false) { Owner = Window.GetWindow(this) };
            if (dialog.ShowDialog() != true) return;
            if (dialog.Choice == StoredBuildUnavailableChoice.Catalog)
            {
                ViewModel.SearchText = profile.PinnedBuild?.Build ?? profile.Product;
                CatalogActivated?.Invoke(this, EventArgs.Empty);
                return;
            }
            if (dialog.Choice == StoredBuildUnavailableChoice.Recommended &&
                await ViewModel.UseProfileAsync(profile, useRecommendedFallback: true) == StoredApplyResult.Applied)
            {
                // Fallback is intentionally session-only; the saved pinned profile is not mutated.
                BuildActivated?.Invoke(this, EventArgs.Empty);
            }
        }
        catch (Exception exception)
        {
            ViewModel.ReportFrontendActionError(exception);
        }
    }

    private void Edit_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not BuildProfile profile) return;
        var draft = Clone(profile);
        new ProfileEditorWindow(ViewModel, draft, profile.PinnedBuild) { Owner = Window.GetWindow(this) }.ShowDialog();
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not BuildProfile profile) return;
        if (MessageBox.Show(Window.GetWindow(this), Loc.Get("ProfileDeleteMessage"), Loc.Get("ProfileDeleteTitle"), MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
        {
            ViewModel.DeleteProfile(profile);
        }
    }

    private static BuildProfile Clone(BuildProfile profile) => new()
    {
        Id = profile.Id,
        Name = profile.Name,
        CreatedAt = profile.CreatedAt,
        UpdatedAt = profile.UpdatedAt,
        SelectionMode = profile.SelectionMode,
        Product = profile.Product,
        Architecture = profile.Architecture,
        PinnedBuild = profile.PinnedBuild is null ? null : new PinnedBuildIdentity
        {
            Product = profile.PinnedBuild.Product,
            VersionLabel = profile.PinnedBuild.VersionLabel,
            Build = profile.PinnedBuild.Build,
            Architecture = profile.PinnedBuild.Architecture,
            IsPreview = profile.PinnedBuild.IsPreview
        },
        Language = profile.Language,
        Editions = [.. profile.Editions],
        ImageFormat = profile.ImageFormat,
        AddUpdates = profile.AddUpdates,
        Cleanup = profile.Cleanup,
        NetFx3 = profile.NetFx3,
        OutputDirectory = profile.OutputDirectory
    };
}
