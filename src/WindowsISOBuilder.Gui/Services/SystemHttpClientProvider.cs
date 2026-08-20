using System.Net;
using System.Net.Http;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class SystemHttpClientProvider : IHttpClientProvider
{
    private readonly TimeSpan _timeout;

    public SystemHttpClientProvider(TimeSpan? timeout = null) =>
        _timeout = timeout ?? TimeSpan.FromSeconds(10);

    public HttpClient CreateClient()
    {
        var handler = new HttpClientHandler
        {
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli
        };
        return new HttpClient(handler, disposeHandler: true) { Timeout = _timeout };
    }
}
