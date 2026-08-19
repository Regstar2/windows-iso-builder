namespace WindowsISOBuilder.Gui.Services;

internal readonly record struct ErrorMapping(string TitleKey, string ActionKey);

internal static class ErrorMapper
{
    public static ErrorMapping Map(string? code) => code switch
    {
        "INVALID_REQUEST" => new("ErrorInvalidRequestTitle", "ErrorReportDiagnosticsAction"),
        "UNSUPPORTED_SCHEMA" => new("ErrorUnsupportedSchemaTitle", "ErrorUpdatePackageAction"),
        "INVALID_COMMAND" => new("ErrorInvalidCommandTitle", "ErrorUpdatePackageAction"),
        "UNSUPPORTED_HOST" => new("ErrorUnsupportedHostTitle", "ErrorSupportedHostAction"),
        "INVALID_ARGUMENT" => new("ErrorInvalidArgumentTitle", "ErrorCheckParametersAction"),
        "INVALID_BUILD_PLAN" => new("ErrorInvalidBuildPlanTitle", "ErrorRepeatPreflightAction"),
        "BUILD_NOT_FOUND" => new("ErrorBuildNotFoundTitle", "ErrorRefreshCatalogAction"),
        "LANGUAGE_NOT_FOUND" => new("ErrorLanguageNotFoundTitle", "ErrorChooseBuildAction"),
        "EDITION_NOT_FOUND" => new("ErrorEditionNotFoundTitle", "ErrorChooseLanguageAction"),
        "DISK_SPACE_LOW" => new("ErrorDiskSpaceTitle", "ErrorFreeSpaceAction"),
        "PATH_NOT_WRITABLE" => new("ErrorPathNotWritableTitle", "ErrorChooseDirectoryAction"),
        "REQUIRED_COMPONENT_MISSING" => new("ErrorComponentMissingTitle", "ErrorRestoreComponentAction"),
        "UUP_API_ERROR" => new("ErrorUupApiTitle", "ErrorRetryLaterAction"),
        "UUP_API_UNAVAILABLE" => new("ErrorUupUnavailableTitle", "ErrorCheckNetworkAction"),
        "NETWORK_ERROR" => new("ErrorNetworkTitle", "ErrorCheckNetworkAction"),
        "UUP_PACKAGE_DOWNLOAD_FAILED" => new("ErrorPackageDownloadTitle", "ErrorCheckNetworkAction"),
        "UUP_PACKAGE_INVALID" => new("ErrorPackageInvalidTitle", "ErrorRetryPackageAction"),
        "DOWNLOAD_FAILED" => new("ErrorDownloadFailedTitle", "ErrorOpenDownloadLogAction"),
        "CONVERTER_FAILED" => new("ErrorConverterFailedTitle", "ErrorOpenConverterLogAction"),
        "DISM_FAILED" => new("ErrorDismFailedTitle", "ErrorOpenBuildLogAction"),
        "ISO_NOT_FOUND" => new("ErrorIsoNotFoundTitle", "ErrorOpenConverterLogAction"),
        "ISO_VALIDATION_FAILED" => new("ErrorIsoValidationTitle", "ErrorDoNotUseIsoAction"),
        "ELEVATION_FAILED" => new("ErrorElevationFailedTitle", "ErrorCheckUacAction"),
        "ELEVATION_CANCELLED" => new("ErrorElevationCancelledTitle", "ErrorRetryUacAction"),
        "BUILD_CANCELLED" => new("ErrorBuildCancelledTitle", "ErrorStartNewBuildAction"),
        "BUILD_FAILED" => new("ErrorBuildFailedTitle", "ErrorOpenBuildLogAction"),
        "INTERNAL_ERROR" => new("ErrorInternalTitle", "ErrorReportDiagnosticsAction"),
        "GUI_ERROR" => new("ErrorGuiTitle", "ErrorGuiAction"),
        _ => new("ErrorGenericTitle", "ErrorOpenDetailsAction")
    };
}
