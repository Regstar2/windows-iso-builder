namespace WindowsISOBuilder.Gui.Backend;

public sealed class BackendPathResolver
{
    public string Resolve(string? overrideRoot = null)
    {
        // Explicit override is accepted only from a caller that deliberately passes
        // it (for example --backend-root in release/developer smoke). Normal GUI
        // startup never trusts an ambient environment variable as executable code.
        if (!string.IsNullOrWhiteSpace(overrideRoot))
        {
            var explicitPath = Path.GetFullPath(Path.Combine(overrideRoot, "Invoke-WibBackend.ps1"));
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
