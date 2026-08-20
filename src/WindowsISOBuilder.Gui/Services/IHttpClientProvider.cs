using System.Net.Http;

namespace WindowsISOBuilder.Gui.Services;

internal interface IHttpClientProvider
{
    HttpClient CreateClient();
}
