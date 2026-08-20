using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class DiagnosticsSecurityTests
{
    [TestMethod]
    public void SanitizerRedactsProxyCredentialsAndPasswords()
    {
        const string secret = "proxy-secret-42";
        var input = $"password={secret} proxy_password={secret} proxy-credential={secret} secret={secret}";
        var sanitized = DiagnosticSanitizer.Sanitize(input, "test-user", @"C:\Users\test-user");

        Assert.IsFalse(sanitized.Contains(secret, StringComparison.Ordinal));
        Assert.IsTrue(sanitized.Contains("password=<SECRET>", StringComparison.OrdinalIgnoreCase));
        Assert.IsTrue(sanitized.Contains("proxy_password=<SECRET>", StringComparison.OrdinalIgnoreCase));
        Assert.IsTrue(sanitized.Contains("proxy-credential=<SECRET>", StringComparison.OrdinalIgnoreCase));
    }

    [TestMethod]
    public void SanitizerRedactsCredentialBearingProxyUrlsAsUrls()
    {
        const string input = "proxy=http://alice:proxy-secret-42@127.0.0.1:3128/path";
        var sanitized = DiagnosticSanitizer.Sanitize(input, "test-user", @"C:\Users\test-user");

        Assert.IsFalse(sanitized.Contains("proxy-secret-42", StringComparison.Ordinal));
        Assert.IsFalse(sanitized.Contains("alice:", StringComparison.Ordinal));
        Assert.IsTrue(sanitized.Contains("<URL>", StringComparison.Ordinal));
    }
}
