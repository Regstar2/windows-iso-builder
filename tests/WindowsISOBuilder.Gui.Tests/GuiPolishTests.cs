using System.IO.Compression;
using System.Text.RegularExpressions;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class GuiPolishTests
{
    [TestMethod]
    public void LocalizationResourcesHaveMatchingKeysAndPlaceholders()
    {
        var en = LocalizationService.GetResourceSnapshot("en");
        var ru = LocalizationService.GetResourceSnapshot("ru");
        CollectionAssert.AreEquivalent(en.Keys.ToArray(), ru.Keys.ToArray());
        foreach (var key in en.Keys) CollectionAssert.AreEquivalent(PlaceholderIndexes(en[key]), PlaceholderIndexes(ru[key]), key);
    }

    [TestMethod]
    public void UnsupportedLocaleFallsBackToEnglish()
    {
        Assert.AreEqual("en", LocalizationService.NormalizeLanguage("de-DE"));
        Assert.AreEqual("en", LocalizationService.NormalizeLanguage("not-a-culture"));
        Assert.AreEqual("ru", LocalizationService.NormalizeLanguage("ru-RU"));
        var service = LocalizationService.Instance;
        var original = service.CurrentLanguage;
        try
        {
            service.SetCulture("de-DE");
            Assert.AreEqual("en", service.CurrentLanguage);
            Assert.AreEqual("Quick build", service.Get("QuickTitle"));
            service.SetCulture("ru-RU");
            Assert.AreEqual("Быстрая сборка", service.Get("QuickTitle"));
        }
        finally { service.SetCulture(original); }
    }

    [TestMethod]
    public void DiagnosticSanitizerRedactsSensitiveValuesWithoutDestroyingDiagnostics()
    {
        var profile = "C:" + "\\Users\\" + "Alice Smith";
        var productKey = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE";
        var sha = new string('a', 64);
        const string requestId = "request-20260819-ABCDEF1234567890";
        var source = string.Join(Environment.NewLine, new[]
        {
            profile + "\\Downloads\\ISO",
            "https://example.test/uup/file.esd?token=super-secret",
            "Authorization: Bearer abcdef123456",
            "token=super-secret",
            "access_token=second-secret",
            productKey,
            $"sha256={sha}",
            "build=26200.9267",
            $"requestId={requestId}",
            "Alice Smith"
        });
        var safe = DiagnosticSanitizer.Sanitize(source, "Alice Smith", profile);
        Assert.IsFalse(safe.Contains(profile, StringComparison.OrdinalIgnoreCase));
        Assert.IsFalse(safe.Contains("Alice Smith", StringComparison.OrdinalIgnoreCase));
        Assert.IsFalse(safe.Contains("https://example.test", StringComparison.OrdinalIgnoreCase));
        Assert.IsFalse(safe.Contains("abcdef123456", StringComparison.Ordinal));
        Assert.IsFalse(safe.Contains("super-secret", StringComparison.Ordinal));
        Assert.IsFalse(safe.Contains("second-secret", StringComparison.Ordinal));
        Assert.IsFalse(safe.Contains(productKey, StringComparison.Ordinal));
        Assert.IsTrue(safe.Contains("<USERPROFILE>", StringComparison.Ordinal));
        Assert.IsTrue(safe.Contains("<URL>", StringComparison.Ordinal));
        Assert.IsTrue(safe.Contains("<PRODUCT_KEY>", StringComparison.Ordinal));
        Assert.IsTrue(safe.Contains(sha, StringComparison.Ordinal));
        Assert.IsTrue(safe.Contains("26200.9267", StringComparison.Ordinal));
        Assert.IsTrue(safe.Contains(requestId, StringComparison.Ordinal));
    }

    [TestMethod]
    public void DiagnosticSanitizerHandlesCyrillicUserProfile()
    {
        var profile = "C:" + "\\Users\\" + "Царь";
        var safe = DiagnosticSanitizer.Sanitize(profile + "\\Downloads\\ISO user=Царь", "Царь", profile);
        Assert.IsFalse(safe.Contains("Царь", StringComparison.OrdinalIgnoreCase));
        Assert.IsTrue(safe.Contains("<USERPROFILE>", StringComparison.Ordinal));
    }

    [TestMethod]
    public void DiagnosticsPackageContainsOnlyExpectedEntriesAndNoSeededSecrets()
    {
        var root = Path.Combine(Path.GetTempPath(), "wib-diagnostics-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var profile = Path.Combine(root, "Users", "Alice Smith");
            var execution = Path.Combine(root, "execution.log");
            var build = Path.Combine(root, "build.log");
            var converter = Path.Combine(root, "converter.log");
            var productKey = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE";
            var seeded = $"user Alice Smith profile {profile} https://example.test/uup?a=1 token=super-secret key {productKey}";
            File.WriteAllText(execution, seeded); File.WriteAllText(build, seeded); File.WriteAllText(converter, seeded);
            var zipPath = Path.Combine(root, "windows-iso-builder-diagnostics.zip");
            new DiagnosticsService("Alice Smith", profile).CreatePackage(zipPath, new DiagnosticsSource(execution, build, converter));
            using var archive = ZipFile.OpenRead(zipPath);
            CollectionAssert.AreEqual(new[] { "app-version.txt", "build.log", "converter.log", "environment.json", "execution.log" }, archive.Entries.Select(x => x.FullName).OrderBy(x => x, StringComparer.Ordinal).ToArray());
            foreach (var entry in archive.Entries)
            {
                using var reader = new StreamReader(entry.Open());
                var text = reader.ReadToEnd();
                Assert.IsFalse(text.Contains("Alice Smith", StringComparison.OrdinalIgnoreCase), entry.FullName);
                Assert.IsFalse(text.Contains(profile, StringComparison.OrdinalIgnoreCase), entry.FullName);
                Assert.IsFalse(text.Contains("super-secret", StringComparison.Ordinal), entry.FullName);
                Assert.IsFalse(text.Contains(productKey, StringComparison.Ordinal), entry.FullName);
                Assert.IsFalse(text.Contains("https://example.test", StringComparison.OrdinalIgnoreCase), entry.FullName);
            }
        }
        finally { Directory.Delete(root, true); }
    }

    [TestMethod]
    public void CorruptSettingsAreIgnoredAndValidSettingsRoundTrip()
    {
        var root = Path.Combine(Path.GetTempPath(), "wib-settings-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var path = Path.Combine(root, "settings.json");
            File.WriteAllText(path, "{ definitely not json");
            var service = new AppSettingsService(new GuiLogger(), path);
            Assert.IsNull(service.Load().Language);
            var expected = new AppSettings { Left = 120, Top = 80, Width = 1100, Height = 700, IsMaximized = true, Language = "ru" };
            service.Save(expected);
            var actual = service.Load();
            Assert.AreEqual(expected.Width, actual.Width); Assert.AreEqual(expected.Height, actual.Height); Assert.AreEqual("ru", actual.Language); Assert.IsTrue(actual.IsMaximized);
        }
        finally { Directory.Delete(root, true); }
    }

    [TestMethod]
    public void WindowBoundsValidationRejectsOffScreenAndAcceptsVisibleBounds()
    {
        var screen = new System.Windows.Rect(0, 0, 1920, 1080);
        Assert.IsTrue(AppSettingsService.HasUsableBounds(new AppSettings { Left = 100, Top = 100, Width = 1100, Height = 700 }, screen));
        Assert.IsFalse(AppSettingsService.HasUsableBounds(new AppSettings { Left = 5000, Top = 5000, Width = 1100, Height = 700 }, screen));
        Assert.IsFalse(AppSettingsService.HasUsableBounds(new AppSettings { Left = 0, Top = 0, Width = 200, Height = 100 }, screen));
    }

    private static string[] PlaceholderIndexes(string value) => Regex.Matches(value, @"\{(\d+)(?:[^}]*)\}").Select(match => match.Groups[1].Value).Distinct(StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal).ToArray();
}
