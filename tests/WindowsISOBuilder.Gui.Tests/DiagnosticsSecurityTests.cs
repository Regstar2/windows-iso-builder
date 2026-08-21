using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class DiagnosticsSecurityTests
{
    private static string TestUserProfile => Path.Combine("C:" + Path.DirectorySeparatorChar, "Users", "test-user");

    [TestMethod]
    public void SanitizerRedactsProxyCredentialsAndPasswords()
    {
        const string fixtureValue = "proxy-fixture-value-42";
        var input = $"password={fixtureValue} proxy_password={fixtureValue} proxy-credential={fixtureValue} secret={fixtureValue}";
        var sanitized = DiagnosticSanitizer.Sanitize(input, "test-user", TestUserProfile);

        Assert.IsFalse(sanitized.Contains(fixtureValue, StringComparison.Ordinal));
        Assert.IsTrue(sanitized.Contains("password=<SECRET>", StringComparison.OrdinalIgnoreCase));
        Assert.IsTrue(sanitized.Contains("proxy_password=<SECRET>", StringComparison.OrdinalIgnoreCase));
        Assert.IsTrue(sanitized.Contains("proxy-credential=<SECRET>", StringComparison.OrdinalIgnoreCase));
    }

    [TestMethod]
    public void SanitizerRedactsCredentialBearingProxyUrlsAsUrls()
    {
        const string fixtureValue = "proxy-fixture-value-42";
        var input = $"proxy=http://alice:{fixtureValue}@127.0.0.1:3128/path";
        var sanitized = DiagnosticSanitizer.Sanitize(input, "test-user", TestUserProfile);

        Assert.IsFalse(sanitized.Contains(fixtureValue, StringComparison.Ordinal));
        Assert.IsFalse(sanitized.Contains("alice:", StringComparison.Ordinal));
        Assert.IsTrue(sanitized.Contains("<URL>", StringComparison.Ordinal));
    }
}
