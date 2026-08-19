using System.Text.RegularExpressions;

namespace WindowsISOBuilder.Gui.Services;

internal static partial class DiagnosticSanitizer
{
    public static string Sanitize(string? value, string? userName = null, string? userProfile = null)
    {
        if (string.IsNullOrEmpty(value)) return value ?? string.Empty;

        userName ??= Environment.UserName;
        userProfile ??= Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        var sanitized = UrlPattern().Replace(value, "<URL>");
        sanitized = AuthorizationBearerPattern().Replace(sanitized, "$1<SECRET>");
        sanitized = SecretAssignmentPattern().Replace(sanitized, "$1=<SECRET>");
        sanitized = ProductKeyPattern().Replace(sanitized, "<PRODUCT_KEY>");

        if (!string.IsNullOrWhiteSpace(userProfile))
        {
            sanitized = Regex.Replace(
                sanitized,
                Regex.Escape(userProfile.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)),
                "<USERPROFILE>",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }

        if (!string.IsNullOrWhiteSpace(userName))
        {
            sanitized = Regex.Replace(
                sanitized,
                $@"(?<![\p{{L}}\p{{N}}_]){Regex.Escape(userName)}(?![\p{{L}}\p{{N}}_])",
                "<USERNAME>",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }

        return sanitized;
    }

    [GeneratedRegex("https?://[^\\s\"'<>]+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex UrlPattern();

    [GeneratedRegex(@"(?im)\b(Authorization\s*:\s*Bearer\s+)[^\s]+", RegexOptions.CultureInvariant)]
    private static partial Regex AuthorizationBearerPattern();

    [GeneratedRegex(@"(?i)\b(token|access_token|refresh_token|api[_-]?key|apikey|secret)\s*[:=]\s*[^\s&;]+", RegexOptions.CultureInvariant)]
    private static partial Regex SecretAssignmentPattern();

    [GeneratedRegex(@"\b(?:[A-Z0-9]{5}-){4}[A-Z0-9]{5}\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ProductKeyPattern();
}
