using System.Diagnostics;

namespace WindowsISOBuilder.Gui.Backend;

public sealed class BackendProcessRunner
{
    public ProcessStartInfo CreateStartInfo(string script, string request, string response, string events)
    {
        var windowsPowerShell = Path.Combine(
            Environment.SystemDirectory,
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");

        var psi = new ProcessStartInfo(windowsPowerShell)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        foreach (var argument in new[]
        {
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", script, "-RequestFile", request, "-ResponseFile", response,
            "-EventFile", events
        })
        {
            psi.ArgumentList.Add(argument);
        }
        return psi;
    }

    public async Task<int> RunAsync(ProcessStartInfo startInfo, CancellationToken cancellationToken)
    {
        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException("Не удалось запустить PowerShell backend.");
        }
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return process.ExitCode;
    }
}
