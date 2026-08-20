using System.Windows;

namespace WindowsISOBuilder.Gui.Services;

internal static class ThemeService
{
    public const string SystemTheme = "system";
    public const string LightTheme = "light";
    public const string DarkTheme = "dark";

    internal static string Normalize(string? theme) => theme?.Trim().ToLowerInvariant() switch
    {
        LightTheme => LightTheme,
        DarkTheme => DarkTheme,
        _ => SystemTheme
    };

    internal static void Apply(string? theme)
    {
        if (Application.Current is null) return;

        Application.Current.ThemeMode = Normalize(theme) switch
        {
            LightTheme => ThemeMode.Light,
            DarkTheme => ThemeMode.Dark,
            _ => ThemeMode.System
        };
    }
}
