using System.Text;
using System.Text.Json;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Backend;

public sealed class NdjsonEventReader
{
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    private long _position;
    private byte[] _partial = [];
    private long _lastSequence = -1;

    public async Task<IReadOnlyList<BackendEvent>> ReadNewAsync(string path, CancellationToken ct = default)
    {
        if (!File.Exists(path)) return [];

        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (_position > stream.Length)
        {
            _position = 0;
            _partial = [];
            _lastSequence = -1;
        }

        stream.Position = _position;
        using var buffer = new MemoryStream();
        await stream.CopyToAsync(buffer, ct).ConfigureAwait(false);
        _position = stream.Position;

        var appended = buffer.ToArray();
        if (appended.Length == 0) return [];

        var data = new byte[_partial.Length + appended.Length];
        Buffer.BlockCopy(_partial, 0, data, 0, _partial.Length);
        Buffer.BlockCopy(appended, 0, data, _partial.Length, appended.Length);

        var result = new List<BackendEvent>();
        var lineStart = 0;
        for (var i = 0; i < data.Length; i++)
        {
            if (data[i] != (byte)'\n') continue;

            var lineLength = i - lineStart;
            if (lineLength > 0 && data[i - 1] == (byte)'\r') lineLength--;
            TryParseLine(data.AsSpan(lineStart, lineLength), result);
            lineStart = i + 1;
        }

        _partial = lineStart < data.Length ? data[lineStart..] : [];
        return result;
    }

    private void TryParseLine(ReadOnlySpan<byte> lineBytes, List<BackendEvent> result)
    {
        if (lineBytes.IsEmpty) return;

        try
        {
            var line = StrictUtf8.GetString(lineBytes);
            if (string.IsNullOrWhiteSpace(line)) return;

            var backendEvent = JsonSerializer.Deserialize<BackendEvent>(line, BackendClient.JsonOptions);
            if (backendEvent is null || backendEvent.Sequence <= _lastSequence) return;

            _lastSequence = backendEvent.Sequence;
            result.Add(backendEvent);
        }
        catch (DecoderFallbackException)
        {
            // A complete newline-terminated record with invalid UTF-8 is malformed
            // telemetry. Ignore it rather than failing the authoritative build.
        }
        catch (JsonException)
        {
            // Events are additive telemetry. A malformed line must not determine
            // build success/failure; the final backend response remains authoritative.
        }
    }
}
