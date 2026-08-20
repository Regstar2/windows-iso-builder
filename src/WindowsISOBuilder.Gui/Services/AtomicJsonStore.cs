using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class AtomicJsonStore<TDocument> where TDocument : class, new()
{
    internal static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly GuiLogger _log;
    private readonly string _path;
    private readonly int _schemaVersion;
    private readonly Func<TDocument, int> _getSchemaVersion;
    private bool _writeBlockedByFutureSchema;

    public AtomicJsonStore(GuiLogger log, string path, int schemaVersion, Func<TDocument, int> getSchemaVersion)
    {
        _log = log;
        _path = path;
        _schemaVersion = schemaVersion;
        _getSchemaVersion = getSchemaVersion;
    }

    internal string Path => _path;
    internal bool CanWrite => !_writeBlockedByFutureSchema;

    public TDocument Load()
    {
        _writeBlockedByFutureSchema = false;
        if (!File.Exists(_path)) return new TDocument();

        try
        {
            var json = File.ReadAllText(_path, Encoding.UTF8);
            using var parsed = JsonDocument.Parse(json);
            if (!parsed.RootElement.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number)
            {
                throw new JsonException("Local data schemaVersion is missing.");
            }

            var version = schema.GetInt32();
            if (version > _schemaVersion)
            {
                _writeBlockedByFutureSchema = true;
                _log.Warning($"Local data schema unsupported: {DiagnosticSanitizer.Sanitize(_path)} schema={version} supported={_schemaVersion}");
                return new TDocument();
            }
            if (version != _schemaVersion)
            {
                throw new JsonException($"Unsupported local data schema {version}.");
            }

            var document = JsonSerializer.Deserialize<TDocument>(json, JsonOptions) ?? new TDocument();
            if (_getSchemaVersion(document) != _schemaVersion) throw new JsonException("Local data schema mismatch.");
            return document;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or NotSupportedException)
        {
            _log.Warning($"Local data load failed: {DiagnosticSanitizer.Sanitize(_path)}");
            PreserveDamagedCopy();
            return new TDocument();
        }
    }

    public bool Save(TDocument document)
    {
        if (_writeBlockedByFutureSchema)
        {
            _log.Warning($"Local data save skipped because a future schema is present: {DiagnosticSanitizer.Sanitize(_path)}");
            return false;
        }
        if (_getSchemaVersion(document) != _schemaVersion)
        {
            _log.Warning($"Local data save rejected because schema is invalid: {DiagnosticSanitizer.Sanitize(_path)}");
            return false;
        }

        var temp = string.Empty;
        try
        {
            var directory = System.IO.Path.GetDirectoryName(_path);
            if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
            temp = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            var bytes = new UTF8Encoding(false).GetBytes(JsonSerializer.Serialize(document, JsonOptions));
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush(flushToDisk: true);
            }

            if (File.Exists(_path))
            {
                try
                {
                    File.Replace(temp, _path, null, ignoreMetadataErrors: true);
                }
                catch (PlatformNotSupportedException)
                {
                    File.Move(temp, _path, overwrite: true);
                }
            }
            else
            {
                File.Move(temp, _path);
            }
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            _log.Warning($"Local data save failed: {DiagnosticSanitizer.Sanitize(_path)}");
            return false;
        }
        finally
        {
            if (!string.IsNullOrWhiteSpace(temp) && File.Exists(temp))
            {
                try { File.Delete(temp); } catch { }
            }
        }
    }

    private void PreserveDamagedCopy()
    {
        if (!File.Exists(_path) || _writeBlockedByFutureSchema) return;
        try
        {
            var directory = System.IO.Path.GetDirectoryName(_path) ?? string.Empty;
            var name = System.IO.Path.GetFileNameWithoutExtension(_path);
            var extension = System.IO.Path.GetExtension(_path);
            var damaged = System.IO.Path.Combine(directory, $"{name}.damaged-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}-{Guid.NewGuid():N}{extension}");
            File.Move(_path, damaged, overwrite: false);
            _log.Warning($"Damaged local data preserved: {DiagnosticSanitizer.Sanitize(damaged)}");
        }
        catch
        {
            _log.Warning($"Damaged local data could not be preserved: {DiagnosticSanitizer.Sanitize(_path)}");
        }
    }
}
