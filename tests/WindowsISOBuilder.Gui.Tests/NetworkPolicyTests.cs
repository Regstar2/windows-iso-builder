using System.Net;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class NetworkPolicyTests
{
    [TestMethod]
    public void MissingPolicyDefaultsToSystem()
    {
        var root = NewRoot();
        try
        {
            var service = new NetworkPolicyService(Path.Combine(root, "network.json"));
            var policy = service.Load();
            Assert.AreEqual(NetworkPolicyService.SystemMode, policy.Mode);
            Assert.AreEqual(NetworkPolicy.CurrentSchemaVersion, policy.SchemaVersion);
        }
        finally { Directory.Delete(root, true); }
    }

    [TestMethod]
    public void DirectExplicitlyDisablesProxy()
    {
        var handler = NetworkHttpClientProvider.CreateHandler(new NetworkPolicy { Mode = "direct" }, null);
        Assert.IsFalse(handler.UseProxy);
        Assert.IsNull(handler.Proxy);
        handler.Dispose();
    }

    [TestMethod]
    public void CustomHttpUsesExpectedProxyWithoutUriCredentials()
    {
        var policy = Custom("http", "proxy.example", 8080, "alice", true);
        var handler = NetworkHttpClientProvider.CreateHandler(policy, "secret");
        Assert.IsTrue(handler.UseProxy);
        Assert.IsNotNull(handler.Proxy);
        var proxyUri = handler.Proxy.GetProxy(new Uri("https://example.test/"));
        Assert.AreEqual("http", proxyUri.Scheme);
        Assert.AreEqual("proxy.example", proxyUri.Host);
        Assert.AreEqual(8080, proxyUri.Port);
        Assert.IsTrue(string.IsNullOrEmpty(proxyUri.UserInfo));
        Assert.IsInstanceOfType(handler.Proxy.Credentials, typeof(NetworkCredential));
        handler.Dispose();
    }

    [TestMethod]
    public void CustomSocks5UsesSocks5Scheme()
    {
        var handler = NetworkHttpClientProvider.CreateHandler(Custom("socks5", "127.0.0.1", 1080, null, false), null);
        var proxyUri = handler.Proxy!.GetProxy(new Uri("https://example.test/"));
        Assert.AreEqual("socks5", proxyUri.Scheme);
        Assert.AreEqual(1080, proxyUri.Port);
        handler.Dispose();
    }

    [TestMethod]
    public void InvalidCustomPolicyDoesNotFallBack()
    {
        foreach (var policy in new[]
        {
            Custom("http", "", 8080, null, false),
            Custom("http", "proxy.example", 0, null, false),
            Custom("socks5", "https://proxy.example", 1080, null, false),
            Custom("unknown", "proxy.example", 1080, null, false)
        })
        {
            Assert.Throws<NetworkPolicyException>(() => NetworkPolicyService.NormalizeAndValidate(policy));
        }
    }

    [TestMethod]
    public void PolicyPersistenceContainsNoPassword()
    {
        var root = NewRoot();
        try
        {
            var path = Path.Combine(root, "network.json");
            var service = new NetworkPolicyService(path);
            service.Save(Custom("http", "proxy.example", 3128, "alice", true));
            var json = File.ReadAllText(path);
            Assert.IsFalse(json.Contains("secret", StringComparison.OrdinalIgnoreCase));
            Assert.IsFalse(json.Contains("password", StringComparison.OrdinalIgnoreCase));
            var loaded = service.Load();
            Assert.AreEqual("custom", loaded.Mode);
            Assert.IsTrue(loaded.HasCredential);
        }
        finally { Directory.Delete(root, true); }
    }

    [TestMethod]
    public void DpapiCredentialRoundTripsReplacesAndClears()
    {
        if (!OperatingSystem.IsWindows()) return;
        var root = NewRoot();
        try
        {
            var path = Path.Combine(root, "credential.bin");
            var store = new ProxyCredentialStore(path);
            store.Save("one-secret");
            CollectionAssert.DoesNotContain(File.ReadAllBytes(path), (byte)'o');
            Assert.AreEqual("one-secret", store.Load());
            store.Save("two-secret");
            Assert.AreEqual("two-secret", store.Load());
            store.Clear();
            Assert.IsNull(store.Load());
        }
        finally { Directory.Delete(root, true); }
    }

    [TestMethod]
    public void CorruptedCredentialFailsClosed()
    {
        if (!OperatingSystem.IsWindows()) return;
        var root = NewRoot();
        try
        {
            var path = Path.Combine(root, "credential.bin");
            File.WriteAllBytes(path, [1, 2, 3, 4]);
            var exception = Assert.Throws<NetworkPolicyException>(() => new ProxyCredentialStore(path).Load());
            Assert.AreEqual("PROXY_CREDENTIAL_UNAVAILABLE", exception.Code);
        }
        finally { Directory.Delete(root, true); }
    }

    private static NetworkPolicy Custom(string type, string host, int port, string? username, bool hasCredential) => new()
    {
        SchemaVersion = 1,
        Mode = "custom",
        ProxyType = type,
        Host = host,
        Port = port,
        Username = username,
        HasCredential = hasCredential
    };

    private static string NewRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), "wib-network-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }
}
