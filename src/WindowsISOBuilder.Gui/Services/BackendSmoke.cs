using WindowsISOBuilder.Gui.Backend;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

public static class BackendSmoke
{
    public static async Task<int> RunAsync(string[] args, GuiLogger log)
    {
        try
        {
            string? root = null;
            for (var i = 0; i < args.Length - 1; i++)
            {
                if (args[i].Equals("--backend-root", StringComparison.OrdinalIgnoreCase))
                {
                    root = args[i + 1];
                }
            }

            var backendPath = new BackendPathResolver().Resolve(root);
            await new BackendClient(backendPath, log).InvokeAsync<VersionData>("GetVersion", new { });
            return 0;
        }
        catch (BackendException exception) when (exception.Code == "UNSUPPORTED_SCHEMA")
        {
            log.Error("backend smoke schema mismatch", exception);
            return 3;
        }
        catch (Exception exception)
        {
            log.Error("backend smoke failed", exception);
            return 2;
        }
    }
}
