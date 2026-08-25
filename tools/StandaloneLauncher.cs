using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

internal static class StandaloneLauncher
{
    private const string PayloadResource = "WindowsISOBuilder.Payload.zip";

    [STAThread]
    private static int Main(string[] args)
    {
        string extractionRoot = Path.Combine(
            Path.GetTempPath(),
            "WindowsISOBuilder",
            Guid.NewGuid().ToString("N"));

        try
        {
            Directory.CreateDirectory(extractionRoot);
            ExtractPayload(extractionRoot);

            string executable = Directory
                .EnumerateFiles(extractionRoot, "WindowsISOBuilder.exe", SearchOption.AllDirectories)
                .FirstOrDefault();
            if (String.IsNullOrWhiteSpace(executable))
                throw new InvalidDataException("Embedded Windows ISO Builder runtime is incomplete.");

            ProcessStartInfo startInfo = new ProcessStartInfo(executable);
            startInfo.WorkingDirectory = Path.GetDirectoryName(executable);
            startInfo.UseShellExecute = false;
            startInfo.Arguments = JoinArguments(args);

            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                    throw new InvalidOperationException("Windows ISO Builder could not be started.");
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                "Windows ISO Builder could not start.\r\n\r\n" + exception.Message,
                "Windows ISO Builder",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            try
            {
                if (Directory.Exists(extractionRoot))
                    Directory.Delete(extractionRoot, true);
            }
            catch
            {
                // Best-effort cleanup only. The OS temp directory remains the fallback.
            }
        }
    }

    private static void ExtractPayload(string destinationRoot)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream payload = assembly.GetManifestResourceStream(PayloadResource))
        {
            if (payload == null)
                throw new InvalidDataException("Embedded Windows ISO Builder payload is missing.");

            using (ZipArchive archive = new ZipArchive(payload, ZipArchiveMode.Read, false))
            {
                string rootPrefix = Path.GetFullPath(destinationRoot)
                    .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                    + Path.DirectorySeparatorChar;

                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    string target = Path.GetFullPath(Path.Combine(destinationRoot, relative));
                    if (!target.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("Embedded payload contains an unsafe path.");

                    if (String.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(target);
                        continue;
                    }

                    string parent = Path.GetDirectoryName(target);
                    if (!String.IsNullOrEmpty(parent))
                        Directory.CreateDirectory(parent);

                    using (Stream input = entry.Open())
                    using (FileStream output = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        input.CopyTo(output);
                    }
                }
            }
        }
    }

    private static string JoinArguments(string[] args)
    {
        if (args == null || args.Length == 0)
            return String.Empty;
        return String.Join(" ", args.Select(QuoteArgument).ToArray());
    }

    private static string QuoteArgument(string value)
    {
        if (value == null)
            return "\"\"";
        if (value.Length > 0 && value.IndexOfAny(new[] { ' ', '\t', '\"' }) < 0)
            return value;
        return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }
}
