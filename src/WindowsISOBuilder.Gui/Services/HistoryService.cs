using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class HistoryService
{
    public const int SchemaVersion = 1;
    public const int RetentionLimit = 200;

    private readonly AtomicJsonStore<HistoryDocument> _store;
    private HistoryDocument _document;

    public HistoryService(GuiLogger log, string? path = null)
    {
        _store = new AtomicJsonStore<HistoryDocument>(
            log,
            path ?? LocalDataPath("history.json"),
            SchemaVersion,
            document => document.SchemaVersion);
        _document = _store.Load();
        NormalizeInterrupted();
        EnforceRetention();
    }

    internal string StorePath => _store.Path;
    internal bool CanWrite => _store.CanWrite;

    public IReadOnlyList<HistoryEntry> GetEntries() => _document.Entries
        .OrderByDescending(entry => entry.StartedAt)
        .ToArray();

    public string Begin(HistoryEntry entry)
    {
        if (string.IsNullOrWhiteSpace(entry.Id)) entry.Id = Guid.NewGuid().ToString("D");
        entry.StartedAt = entry.StartedAt == default ? DateTimeOffset.UtcNow : entry.StartedAt;
        entry.FinishedAt = null;
        entry.Status = HistoryStatus.Pending;
        entry.IsoPath = null;
        entry.Sha256 = null;
        entry.ErrorCode = null;
        _document.Entries.Add(entry);
        EnforceRetention();
        _store.Save(_document);
        return entry.Id;
    }

    public void Complete(string id, BuildResultDto result) => Finalize(
        id,
        HistoryStatus.Completed,
        result,
        null,
        null);

    public void Fail(string id, string? errorCode, string? logPath) => Finalize(
        id,
        HistoryStatus.Failed,
        null,
        errorCode,
        logPath);

    public void Cancel(string id, string? logPath = null) => Finalize(
        id,
        HistoryStatus.Cancelled,
        null,
        "BUILD_CANCELLED",
        logPath);

    public bool Delete(string id)
    {
        var removed = _document.Entries.RemoveAll(entry => string.Equals(entry.Id, id, StringComparison.Ordinal)) > 0;
        if (removed) _store.Save(_document);
        return removed;
    }

    public void Clear()
    {
        _document.Entries.Clear();
        _store.Save(_document);
    }

    private void Finalize(string id, HistoryStatus status, BuildResultDto? result, string? errorCode, string? logPath)
    {
        var entry = _document.Entries.FirstOrDefault(item => string.Equals(item.Id, id, StringComparison.Ordinal));
        if (entry is null) return;
        entry.Status = status;
        entry.FinishedAt = DateTimeOffset.UtcNow;
        entry.ErrorCode = errorCode;
        if (result is not null)
        {
            entry.IsoPath = NullIfBlank(result.IsoPath);
            entry.Sha256 = NullIfBlank(result.Sha256);
            entry.LogPath = NullIfBlank(result.LogPath);
            entry.ExecutionLogPath = NullIfBlank(result.ExecutionLogPath);
            entry.MetadataPath = NullIfBlank(result.MetadataPath);
        }
        else if (!string.IsNullOrWhiteSpace(logPath))
        {
            entry.LogPath = logPath;
        }
        EnforceRetention();
        _store.Save(_document);
    }

    private void NormalizeInterrupted()
    {
        var changed = false;
        foreach (var entry in _document.Entries.Where(entry => entry.Status == HistoryStatus.Pending))
        {
            entry.Status = HistoryStatus.Interrupted;
            entry.FinishedAt ??= DateTimeOffset.UtcNow;
            changed = true;
        }
        if (changed) _store.Save(_document);
    }

    private void EnforceRetention()
    {
        if (_document.Entries.Count <= RetentionLimit) return;
        _document.Entries = _document.Entries
            .OrderByDescending(entry => entry.StartedAt)
            .Take(RetentionLimit)
            .ToList();
    }

    internal static string LocalDataPath(string fileName)
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var root = string.IsNullOrWhiteSpace(localAppData)
            ? Path.Combine(Path.GetTempPath(), "WindowsISOBuilder")
            : Path.Combine(localAppData, "WindowsISOBuilder");
        return Path.Combine(root, fileName);
    }

    private static string? NullIfBlank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;
}
