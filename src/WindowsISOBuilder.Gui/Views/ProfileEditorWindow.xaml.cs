using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Views;

public partial class ProfileEditorWindow : Window
{
    private readonly MainViewModel _viewModel;
    private readonly BuildProfile _draft;
    private readonly PinnedBuildIdentity? _pinCandidate;
    private bool _initializing = true;
    private bool _refreshing;

    public ObservableCollection<EditionChoice> EditionChoices { get; } = [];

    public ProfileEditorWindow(MainViewModel viewModel, BuildProfile draft, PinnedBuildIdentity? pinCandidate = null)
    {
        _viewModel = viewModel;
        _draft = draft;
        _pinCandidate = pinCandidate ?? draft.PinnedBuild;
        InitializeComponent();
        DataContext = this;

        NameBox.Text = draft.Name;
        ModeCombo.SelectedValue = draft.SelectionMode == ProfileSelectionMode.Pinned ? "pinned" : "recommended";
        ProductCombo.SelectedValue = draft.Product;
        ArchitectureCombo.SelectedValue = draft.Architecture;
        FormatCombo.SelectedValue = draft.ImageFormat;
        OutputBox.Text = draft.OutputDirectory;
        AddUpdatesCheck.IsChecked = draft.AddUpdates;
        CleanupCheck.IsChecked = draft.Cleanup;
        NetFx3Check.IsChecked = draft.NetFx3;
        ApplyModeRules();
        _initializing = false;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e) => await RefreshAvailabilityAsync();

    private void ModeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_initializing) return;
        ApplyModeRules();
        AvailabilityText.Text = string.Empty;
    }

    private async void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_initializing || _refreshing || LanguageCombo.SelectedItem is not LanguageDto) return;
        await RefreshAvailabilityAsync();
    }

    private async void RefreshAvailability_Click(object sender, RoutedEventArgs e) => await RefreshAvailabilityAsync();

    private async Task RefreshAvailabilityAsync()
    {
        if (_refreshing) return;
        _refreshing = true;
        try
        {
            var requestedLanguage = (LanguageCombo.SelectedItem as LanguageDto)?.Code;
            if (string.IsNullOrWhiteSpace(requestedLanguage)) requestedLanguage = _draft.Language;
            var requestedEditions = EditionChoices.Count > 0
                ? EditionChoices.Where(choice => choice.Selected).Select(choice => choice.Dto.Code).ToList()
                : [.. _draft.Editions];

            var probe = new BuildProfile
            {
                SelectionMode = SelectedMode(),
                Product = SelectedProduct(),
                Architecture = SelectedArchitecture(),
                PinnedBuild = SelectedMode() == ProfileSelectionMode.Pinned ? (_draft.PinnedBuild ?? _pinCandidate) : null,
                Language = requestedLanguage ?? string.Empty,
                Editions = requestedEditions
            };

            var resolution = await _viewModel.ResolveProfileEditorAsync(probe);
            if (resolution is null)
            {
                LanguageCombo.ItemsSource = null;
                EditionChoices.Clear();
                AvailabilityText.Text = LocalizationService.Instance.Get("StoredBuildMissingProfileMessage");
                return;
            }

            LanguageCombo.ItemsSource = resolution.Languages;
            LanguageCombo.SelectedItem = resolution.Languages.FirstOrDefault(language =>
                language.Code.Equals(requestedLanguage, StringComparison.OrdinalIgnoreCase));

            EditionChoices.Clear();
            var selectedCodes = requestedEditions.ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var edition in resolution.Editions)
            {
                EditionChoices.Add(new EditionChoice(edition) { Selected = selectedCodes.Contains(edition.Code) });
            }

            if (resolution.HasStaleValues)
            {
                var stale = resolution.LanguageMissing
                    ? requestedLanguage ?? string.Empty
                    : string.Join(", ", resolution.MissingEditions);
                AvailabilityText.Text = LocalizationService.Instance.Format("ProfileAvailabilityStale", stale);
            }
            else
            {
                AvailabilityText.Text = LocalizationService.Instance.Get("ProfileAvailabilityCurrent");
            }
        }
        catch (Exception exception)
        {
            _viewModel.ReportFrontendActionError(exception);
        }
        finally
        {
            _refreshing = false;
        }
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var loc = LocalizationService.Instance;
        string name;
        try
        {
            name = ProfileService.NormalizeName(NameBox.Text);
        }
        catch (ArgumentException)
        {
            MessageBox.Show(this, loc.Get("ProfileNameInvalid"), loc.Get("ProfileEditorTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
            NameBox.Focus();
            return;
        }

        if (LanguageCombo.SelectedItem is not LanguageDto language)
        {
            MessageBox.Show(this, loc.Format("StoredLanguageUnavailable", _draft.Language), loc.Get("ProfileEditorTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var editions = EditionChoices.Where(choice => choice.Selected).Select(choice => choice.Dto.Code).ToList();
        if (editions.Count == 0)
        {
            MessageBox.Show(this, loc.Get("MsgSelectEdition"), loc.Get("MsgSelectEditionTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var mode = SelectedMode();
        var pinned = mode == ProfileSelectionMode.Pinned ? (_draft.PinnedBuild ?? _pinCandidate) : null;
        if (mode == ProfileSelectionMode.Pinned && pinned is null)
        {
            MessageBox.Show(this, loc.Get("StoredBuildMissingProfileMessage"), loc.Get("StoredBuildMissingProfileTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        _draft.Name = name;
        _draft.SelectionMode = mode;
        _draft.Product = mode == ProfileSelectionMode.Pinned ? pinned!.Product : SelectedProduct();
        _draft.Architecture = mode == ProfileSelectionMode.Pinned ? pinned!.Architecture : SelectedArchitecture();
        _draft.PinnedBuild = pinned;
        _draft.Language = language.Code;
        _draft.Editions = editions;
        _draft.ImageFormat = FormatCombo.SelectedValue as string ?? "ESD";
        _draft.AddUpdates = AddUpdatesCheck.IsChecked == true;
        _draft.Cleanup = CleanupCheck.IsChecked == true;
        _draft.NetFx3 = NetFx3Check.IsChecked == true;
        _draft.OutputDirectory = OutputBox.Text;
        _viewModel.SaveProfile(_draft);
        DialogResult = true;
    }

    private void ApplyModeRules()
    {
        var pinnedMode = SelectedMode() == ProfileSelectionMode.Pinned;
        ProductCombo.IsEnabled = !pinnedMode;
        ArchitectureCombo.IsEnabled = !pinnedMode;
        var identity = _draft.PinnedBuild ?? _pinCandidate;
        if (pinnedMode && identity is not null)
        {
            ProductCombo.SelectedValue = identity.Product;
            ArchitectureCombo.SelectedValue = identity.Architecture;
        }
    }

    private ProfileSelectionMode SelectedMode() =>
        string.Equals(ModeCombo.SelectedValue as string, "pinned", StringComparison.OrdinalIgnoreCase)
            ? ProfileSelectionMode.Pinned
            : ProfileSelectionMode.Recommended;

    private string SelectedProduct() => ProductCombo.SelectedValue as string ?? "Windows 11";
    private string SelectedArchitecture() => ArchitectureCombo.SelectedValue as string ?? "amd64";
}
