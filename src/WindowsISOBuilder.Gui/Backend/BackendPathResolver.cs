namespace WindowsISOBuilder.Gui.Backend;

public sealed class BackendPathResolver
{
    public string Resolve(string? overrideRoot = null)
    {
        var explicitRoot = overrideRoot ?? Environment.GetEnvironmentVariable("WIB_BACKEND_ROOT");
        if (!string.IsNullOrWhiteSpace(explicitRoot))
        {
            var explicitPath = Path.GetFullPath(Path.Combine(explicitRoot, "Invoke-WibBackend.ps1"));
            if (File.Exists(explicitPath)) return explicitPath;
            throw new FileNotFoundException("Компоненты Windows ISO Builder повреждены или отсутствуют.", explicitPath);
        }

        // Packaged layout: GUI executable and Invoke-WibBackend.ps1 share package root.
        var packaged = Path.Combine(AppContext.BaseDirectory, "Invoke-WibBackend.ps1");
        if (File.Exists(packaged)) return packaged;

        // Development-only fallback: walk parents of bin/<configuration>/<tfm>.
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        for (var i = 0; i < 7 && current is not null; i++, current = current.Parent)
        {
            var candidate = Path.Combine(current.FullName, "Invoke-WibBackend.ps1");
            if (File.Exists(candidate)) return candidate;
        }

        throw new FileNotFoundException("Компоненты Windows ISO Builder повреждены или отсутствуют.", packaged);
    }
}
