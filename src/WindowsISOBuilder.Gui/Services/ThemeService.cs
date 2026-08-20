using Microsoft.Win32;
using System.Windows;
using System.Windows.Media;

namespace WindowsISOBuilder.Gui.Services;

internal static class ThemeService
{
    public const string SystemTheme = "system";
    public const string LightTheme = "light";
    public const string DarkTheme = "dark";

    public static string Normalize(string? theme) => theme?.Trim().ToLowerInvariant() switch
    {
        LightTheme => LightTheme,
        DarkTheme => DarkTheme,
        _ => SystemTheme
    };

    public static void Apply(string? theme)
    {
        if (Application.Current is null) return;

        var normalized = Normalize(theme);
        Application.Current.ThemeMode = normalized switch
        {
            LightTheme => ThemeMode.Light,
            DarkTheme => ThemeMode.Dark,
            _ => ThemeMode.System
        };

        ApplyShellPalette(normalized == DarkTheme || normalized == SystemTheme && IsWindowsAppThemeDark());
    }

    private static void ApplyShellPalette(bool dark)
    {
        if (Application.Current is null) return;

        var resources = Application.Current.Resources;
        resources["WibPageBackgroundBrush"] = Brush(dark ? 0x20 : 0xF3, dark ? 0x20 : 0xF3, dark ? 0x20 : 0xF3);
        resources["WibSurfaceBrush"] = Brush(dark ? 0x20 : 0xF3, dark ? 0x20 : 0xF3, dark ? 0x20 : 0xF3);
        resources["WibCardBrush"] = Brush(dark ? 0x2B : 0xFF, dark ? 0x2B : 0xFF, dark ? 0x2B : 0xFF);
        resources["WibSubtleBrush"] = Brush(dark ? 0x34 : 0xF7, dark ? 0x34 : 0xF7, dark ? 0x34 : 0xF7);
        resources["WibBorderBrush"] = Brush(dark ? 0x4A : 0xD0, dark ? 0x4A : 0xD0, dark ? 0x4A : 0xD0);
        resources["WibTextBrush"] = Brush(dark ? 0xF2 : 0x1A, dark ? 0xF2 : 0x1A, dark ? 0xF2 : 0x1A);
        resources["WibMutedTextBrush"] = Brush(dark ? 0xB7 : 0x6B, dark ? 0xB7 : 0x6B, dark ? 0xB7 : 0x6B);
        resources["WibControlBrush"] = Brush(dark ? 0x34 : 0xFF, dark ? 0x34 : 0xFF, dark ? 0x34 : 0xFF);
        resources["WibDisabledControlBrush"] = Brush(dark ? 0x30 : 0xF0, dark ? 0x30 : 0xF0, dark ? 0x30 : 0xF0);
        resources["WibDisabledTextBrush"] = Brush(dark ? 0xB0 : 0x6F, dark ? 0xB0 : 0x6F, dark ? 0xB0 : 0x6F);
    }

    private static bool IsWindowsAppThemeDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
        }
        catch
        {
            return false;
        }
    }

    private static SolidColorBrush Brush(int red, int green, int blue)
    {
        var brush = new SolidColorBrush(Color.FromRgb((byte)red, (byte)green, (byte)blue));
        brush.Freeze();
        return brush;
    }
}
