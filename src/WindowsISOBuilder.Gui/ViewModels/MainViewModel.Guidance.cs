namespace WindowsISOBuilder.Gui.ViewModels;

public sealed partial class MainViewModel
{
    public bool HighlightRecommended =>
        State == UiState.Idle && SelectedBuild is null;

    public bool HighlightEditions =>
        IsConfigurationEnabled &&
        SelectedBuild is not null &&
        Editions.Count > 0 &&
        !Editions.Any(x => x.Selected);

    public bool HighlightPreflight =>
        IsConfigurationEnabled &&
        SelectedBuild is not null &&
        Editions.Any(x => x.Selected) &&
        State is UiState.ReadyToPreflight or UiState.PreflightFailed;

    public bool HighlightBuild => State == UiState.ReadyToBuild;

    private void RaiseWorkflowGuidance()
    {
        Raise(nameof(HighlightRecommended));
        Raise(nameof(HighlightEditions));
        Raise(nameof(HighlightPreflight));
        Raise(nameof(HighlightBuild));
    }
}
