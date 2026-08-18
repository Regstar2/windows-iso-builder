using System.Text;
using System.Text.Json;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Backend;

public sealed class NdjsonEventReader
{
    private long _position; private string _partial=""; private long _lastSequence=-1;
    public async Task<IReadOnlyList<BackendEvent>> ReadNewAsync(string path, CancellationToken ct=default)
    {
        if(!File.Exists(path)) return [];
        using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
        if(_position>stream.Length){_position=0;_partial="";_lastSequence=-1;}
        stream.Position=_position;
        using var reader=new StreamReader(stream,new UTF8Encoding(false,true),true,4096,true);
        var chunk=await reader.ReadToEndAsync(ct).ConfigureAwait(false); _position=stream.Position;
        var text=_partial+chunk; var lines=text.Split('\n'); _partial=text.EndsWith('\n')?"":lines[^1].TrimEnd('\r');
        var count=text.EndsWith('\n')?lines.Length:lines.Length-1; var result=new List<BackendEvent>();
        for(var i=0;i<count;i++) { var line=lines[i].TrimEnd('\r'); if(string.IsNullOrWhiteSpace(line)) continue; try { var ev=JsonSerializer.Deserialize<BackendEvent>(line,BackendClient.JsonOptions); if(ev is null) continue; if(ev.Sequence<=_lastSequence) continue; _lastSequence=ev.Sequence; result.Add(ev); } catch(JsonException) { } }
        return result;
    }
}
