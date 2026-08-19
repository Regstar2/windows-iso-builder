using System.Globalization;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class DiagnosticsService
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private readonly string _userName;
    private readonly string _userProfile;

    public DiagnosticsService(string? userName = null, string? userProfile = null)
    {
        _userName = userName ?? Environment.UserName;
        _userProfile = userProfile ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    }

    public void CreatePackage(string destinationPath, DiagnosticsSource source)
    {
        if (string.IsNullOrWhiteSpace(destinationPath))
        {
            throw new ArgumentException("Diagnostics destination path is required.", nameof(destinationPath));
        }

        var fullPath = Path.GetFullPath(destinationPath);
        var directory = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);

        using var stream = new FileStream(fullPath, FileMode.Create, FileAccess.ReadWrite, FileShare.None);
        using var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: false, Utf8NoBom);

        WriteTextEntry(
            archive,
            "app-version.txt",
            $"Windows ISO Builder{Environment.NewLine}Version: {AppVersionInfo.Current}{Environment.NewLine}");

        var environment = new
        {
            appVersion = AppVersionInfo.Current,
            osVersion = RuntimeInformation.OSDescription,
            osArchitecture = RuntimeInformation.OSArchitecture.ToString(),
            processArchitecture = RuntimeInformation.ProcessArchitecture.ToString(),
            dotnetRuntime = RuntimeInformation.FrameworkDescription,
            uiCulture = CultureInfo.CurrentUICulture.Name,
            culture = CultureInfo.CurrentCulture.Name
        };
        WriteTextEntry(archive, "environment.json", JsonSerializer.Serialize(environment, new JsonSerializerOptions { WriteIndented = true }));

        WriteLogEntry(archive, "execution.log", source.ExecutionLogPath);
        WriteLogEntry(archive, "build.log", source.BuildLogPath);
        WriteLogEntry(archive, "converter.log", source.ConverterLogPath);
    }

    internal static string? FindLatestConverterLog(string? workDirectory)
    {
        if (string.IsNullOrWhiteSpace(workDirectory) || !Directory.Exists(workDirectory)) return null;
        try
        {
            return Directory.EnumerateFiles(workDirectory, "converter-*.log", SearchOption.TopDirectoryOnly)
                .Select(path => new FileInfo(path))
                .OrderByDescending(file => file.LastWriteTimeUtc)
                .Select(file => file.FullName)
                .FirstOrDefault();
        }
        catch
        {
            return null;
        }
    }

    private void WriteTextEntry(ZipArchive archive, string entryName, string text)
    {
        var entry = archive.CreateEntry(entryName, CompressionLevel.Optimal);
        using var writer = new StreamWriter(entry.Open(), Utf8NoBom);
        writer.Write(DiagnosticSanitizer.Sanitize(text, _userName, _userProfile));
    }

    private void WriteLogEntry(ZipArchive archive, string entryName, string? sourcePath)
    {
        var entry = archive.CreateEntry(entryName, CompressionLevel.Optimal);
        using var writer = new StreamWriter(entry.Open(), Utf8NoBom);

        if (string.IsNullOrWhiteSpace(sourcePath) || !File.Exists(sourcePath))
        {
            writer.WriteLine("Log file was not available for this session.");
            return;
        }

        try
        {
            using var reader = new StreamReader(sourcePath, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            string? line;
            while ((line = reader.ReadLine()) is not null)
            {
                writer.WriteLine(DiagnosticSanitizer.Sanitize(line, _userName, _userProfile));
            }
        }
        catch
        {
            writer.WriteLine("Log file could not be read for this session.");
        }
    }
}
