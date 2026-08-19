using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal sealed partial class AppSettingsService
{
    private const uint MonitorDefaultToNull = 0;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly GuiLogger _log;
    private readonly string _settingsPath;

    public AppSettingsService(GuiLogger log, string? settingsPath = null)
    {
        _log = log;
        _settingsPath = settingsPath ?? GetDefaultPath();
    }

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(_settingsPath)) return new AppSettings();
            var json = File.ReadAllText(_settingsPath);
            return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
        }
        catch (Exception exception)
        {
            _log.Error("Failed to read GUI settings", exception);
            return new AppSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        try
        {
            var directory = Path.GetDirectoryName(_settingsPath);
            if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
            File.WriteAllText(_settingsPath, JsonSerializer.Serialize(settings, JsonOptions));
        }
        catch (Exception exception)
        {
            _log.Error("Failed to persist GUI settings", exception);
        }
    }

    internal static bool HasUsableBoundsOnCurrentMonitors(AppSettings settings, double minimumVisible = 96)
    {
        if (!TryCreateRect(settings, out var saved)) return false;

        var nativeRect = new NativeRect(
            (int)Math.Floor(saved.Left),
            (int)Math.Floor(saved.Top),
            (int)Math.Ceiling(saved.Right),
            (int)Math.Ceiling(saved.Bottom));
        var monitor = MonitorFromRect(ref nativeRect, MonitorDefaultToNull);
        if (monitor == IntPtr.Zero) return false;

        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info)) return false;

        var workArea = new Rect(
            info.WorkArea.Left,
            info.WorkArea.Top,
            Math.Max(0, info.WorkArea.Right - info.WorkArea.Left),
            Math.Max(0, info.WorkArea.Bottom - info.WorkArea.Top));
        return HasMinimumIntersection(saved, workArea, minimumVisible);
    }

    internal static bool HasUsableBounds(AppSettings settings, Rect availableArea, double minimumVisible = 96) =>
        TryCreateRect(settings, out var saved) && HasMinimumIntersection(saved, availableArea, minimumVisible);

    private static bool TryCreateRect(AppSettings settings, out Rect saved)
    {
        saved = Rect.Empty;
        if (settings.Left is not double left || settings.Top is not double top ||
            settings.Width is not double width || settings.Height is not double height)
        {
            return false;
        }

        if (!double.IsFinite(left) || !double.IsFinite(top) ||
            !double.IsFinite(width) || !double.IsFinite(height) ||
            width < 480 || height < 320)
        {
            return false;
        }

        saved = new Rect(left, top, width, height);
        return true;
    }

    private static bool HasMinimumIntersection(Rect saved, Rect availableArea, double minimumVisible)
    {
        var intersection = Rect.Intersect(saved, availableArea);
        return !intersection.IsEmpty && intersection.Width >= minimumVisible && intersection.Height >= minimumVisible;
    }

    private static string GetDefaultPath()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var root = string.IsNullOrWhiteSpace(localAppData)
            ? Path.Combine(Path.GetTempPath(), "WindowsISOBuilder")
            : Path.Combine(localAppData, "WindowsISOBuilder");
        return Path.Combine(root, "settings.json");
    }

    [LibraryImport("user32.dll")]
    private static partial IntPtr MonitorFromRect(ref NativeRect rect, uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public NativeRect(int left, int top, int right, int bottom)
        {
            Left = left;
            Top = top;
            Right = right;
            Bottom = bottom;
        }
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfo
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect WorkArea;
        public uint Flags;
    }
}
