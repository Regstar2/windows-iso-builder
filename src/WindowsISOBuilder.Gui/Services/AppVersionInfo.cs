using System.Reflection;

namespace WindowsISOBuilder.Gui.Services;

internal static class AppVersionInfo
{
    public static string Current
    {
        get
        {
            var assembly = typeof(AppVersionInfo).Assembly;
            var informational = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            if (!string.IsNullOrWhiteSpace(informational))
            {
                var separator = informational.IndexOf('+');
                return separator >= 0 ? informational[..separator] : informational;
            }

            var version = assembly.GetName().Version;
            if (version is null) return "0.0.0";
            return $"{version.Major}.{version.Minor}.{version.Build}";
        }
    }
}
