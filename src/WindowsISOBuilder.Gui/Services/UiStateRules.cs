using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Services;

public static class UiStateRules
{
    public static bool CanTransition(UiState from, UiState to)
    {
        if (from == to) return true;
        return from switch
        {
            UiState.Idle => to is UiState.LoadingBuild or UiState.Failed,
            UiState.LoadingBuild => to is UiState.Idle or UiState.LoadingLanguages or UiState.Failed,
            UiState.LoadingLanguages => to is UiState.LoadingEditions or UiState.Failed,
            UiState.LoadingEditions => to is UiState.ReadyToPreflight or UiState.Failed,
            UiState.ReadyToPreflight => to is UiState.Preflighting or UiState.LoadingBuild or UiState.LoadingLanguages or UiState.LoadingEditions or UiState.Failed,
            UiState.Preflighting => to is UiState.ReadyToBuild or UiState.PreflightFailed or UiState.ReadyToPreflight or UiState.Failed,
            UiState.PreflightFailed => to is UiState.Preflighting or UiState.LoadingBuild or UiState.LoadingLanguages or UiState.LoadingEditions or UiState.Failed,
            UiState.ReadyToBuild => to is UiState.Building or UiState.Preflighting or UiState.ReadyToPreflight or UiState.LoadingBuild or UiState.LoadingLanguages or UiState.LoadingEditions or UiState.Failed,
            UiState.Building => to is UiState.Cancelling or UiState.Completed or UiState.Cancelled or UiState.Failed,

            // CancelBuild is cooperative. If the cancellation request cannot be
            // accepted/sent, the build is still alive and the UI must return to
            // Building instead of pretending that cancellation succeeded.
            UiState.Cancelling => to is UiState.Building or UiState.Cancelled or UiState.Completed or UiState.Failed,

            // Retry resumes the operation that failed. Metadata retries therefore
            // return directly to their loading state, while build retry restores
            // the already preflighted plan to ReadyToBuild.
            UiState.Failed => to is UiState.Idle or UiState.ReadyToPreflight or UiState.ReadyToBuild or UiState.LoadingBuild or UiState.LoadingLanguages or UiState.LoadingEditions or UiState.Failed,
            UiState.Completed or UiState.Cancelled => to is UiState.Idle or UiState.ReadyToPreflight or UiState.LoadingBuild or UiState.Failed,
            _ => false
        };
    }
}
