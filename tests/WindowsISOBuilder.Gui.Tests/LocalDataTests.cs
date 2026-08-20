using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class LocalDataTests
{
    [TestMethod] public void EmptyHistoryStoreIsValid() => WithTemp(root => Assert.AreEqual(0, NewHistory(root).GetEntries().Count));

    [TestMethod]
    public void HistorySaveLoadAndRoundTrip()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root);
            var id = service.Begin(SampleHistory());
            service.Complete(id, SampleResult(root));
            var loaded = NewHistory(root).GetEntries().Single();
            Assert.AreEqual(HistoryStatus.Completed, loaded.Status);
            Assert.AreEqual("Professional", loaded.Editions.Single());
            Assert.AreEqual("ESD", loaded.ImageFormat);
            Assert.AreEqual(Path.Combine(root, "Windows.iso"), loaded.IsoPath);
        });
    }

    [TestMethod]
    public void HistorySchemaVersionIsIndependentAndVersioned()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root);
            service.Begin(SampleHistory());
            using var json = JsonDocument.Parse(File.ReadAllText(service.StorePath));
            Assert.AreEqual(HistoryService.SchemaVersion, json.RootElement.GetProperty("schemaVersion").GetInt32());
        });
    }

    [TestMethod]
    public void HistoryRetentionKeepsNewestTwoHundred()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root);
            var origin = DateTimeOffset.UtcNow.AddDays(-1);
            for (var i = 0; i < HistoryService.RetentionLimit + 5; i++)
            {
                var entry = SampleHistory();
                entry.Build = i.ToString();
                entry.StartedAt = origin.AddMinutes(i);
                service.Begin(entry);
            }
            var entries = service.GetEntries();
            Assert.AreEqual(HistoryService.RetentionLimit, entries.Count);
            Assert.AreEqual((HistoryService.RetentionLimit + 4).ToString(), entries[0].Build);
            Assert.AreEqual("5", entries[^1].Build);
        });
    }

    [TestMethod]
    public void HistoryOrdersNewestFirst()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root);
            var older = SampleHistory(); older.Build = "old"; older.StartedAt = DateTimeOffset.UtcNow.AddHours(-1); service.Begin(older);
            var newer = SampleHistory(); newer.Build = "new"; newer.StartedAt = DateTimeOffset.UtcNow; service.Begin(newer);
            Assert.AreEqual("new", service.GetEntries()[0].Build);
        });
    }

    [TestMethod]
    public void CorruptedHistoryIsPreservedAndRecovered()
    {
        WithTemp(root =>
        {
            var path = Path.Combine(root, "history.json");
            File.WriteAllText(path, "{ not json");
            var service = new HistoryService(new GuiLogger(), path);
            Assert.AreEqual(0, service.GetEntries().Count);
            Assert.IsFalse(File.Exists(path));
            Assert.AreEqual(1, Directory.GetFiles(root, "history.damaged-*.json").Length);
        });
    }

    [TestMethod]
    public void FutureHistorySchemaIsNotOverwritten()
    {
        WithTemp(root =>
        {
            var path = Path.Combine(root, "history.json");
            File.WriteAllText(path, "{\"schemaVersion\":99,\"entries\":[]}");
            var service = new HistoryService(new GuiLogger(), path);
            Assert.IsFalse(service.CanWrite);
            service.Begin(SampleHistory());
            StringAssert.Contains(File.ReadAllText(path), "\"schemaVersion\":99");
        });
    }

    [TestMethod]
    public void AtomicHistorySaveLeavesNoTemporaryFile()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root);
            service.Begin(SampleHistory());
            Assert.IsTrue(File.Exists(service.StorePath));
            Assert.AreEqual(0, Directory.GetFiles(root, "*.tmp").Length);
        });
    }

    [TestMethod]
    public void HistoryPersistsControlledDtoNotBackendObject()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root);
            var id = service.Begin(SampleHistory());
            service.Complete(id, SampleResult(root));
            var json = File.ReadAllText(service.StorePath);
            StringAssert.DoesNotContain(json, "workDirectory");
            StringAssert.DoesNotContain(json, "uuid");
            StringAssert.DoesNotContain(json, "requestId");
            StringAssert.Contains(json, "isoPath");
        });
    }

    [TestMethod]
    public void CompletedHistoryRecordStoresTerminalArtifacts()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root); var id = service.Begin(SampleHistory()); service.Complete(id, SampleResult(root));
            var entry = service.GetEntries().Single();
            Assert.AreEqual(HistoryStatus.Completed, entry.Status);
            Assert.IsNotNull(entry.FinishedAt);
            Assert.AreEqual(new string('a', 64), entry.Sha256);
        });
    }

    [TestMethod]
    public void FailedHistoryRecordStoresControlledError()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root); var id = service.Begin(SampleHistory()); service.Fail(id, "DOWNLOAD_FAILED", Path.Combine(root, "build.log"));
            var entry = service.GetEntries().Single();
            Assert.AreEqual(HistoryStatus.Failed, entry.Status);
            Assert.AreEqual("DOWNLOAD_FAILED", entry.ErrorCode);
        });
    }

    [TestMethod]
    public void CancelledHistoryRecordIsTerminal()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root); var id = service.Begin(SampleHistory()); service.Cancel(id);
            Assert.AreEqual(HistoryStatus.Cancelled, service.GetEntries().Single().Status);
        });
    }

    [TestMethod]
    public void PendingHistoryNormalizesToInterruptedAfterRestart()
    {
        WithTemp(root =>
        {
            var service = NewHistory(root); service.Begin(SampleHistory());
            var loaded = NewHistory(root).GetEntries().Single();
            Assert.AreEqual(HistoryStatus.Interrupted, loaded.Status);
            Assert.IsNotNull(loaded.FinishedAt);
        });
    }

    [TestMethod]
    public void DeletingHistoryDoesNotDeleteArtifacts()
    {
        WithTemp(root =>
        {
            var iso = Path.Combine(root, "Windows.iso"); File.WriteAllText(iso, "test");
            var service = NewHistory(root); var id = service.Begin(SampleHistory()); service.Complete(id, SampleResult(root));
            Assert.IsTrue(service.Delete(id));
            Assert.IsTrue(File.Exists(iso));
        });
    }

    [TestMethod] public void EmptyProfileStoreIsValid() => WithTemp(root => Assert.AreEqual(0, NewProfiles(root).GetProfiles().Count));

    [TestMethod]
    public void ProfileSaveLoadAndRoundTrip()
    {
        WithTemp(root =>
        {
            var service = NewProfiles(root); var expected = service.Save(SampleProfile());
            var actual = NewProfiles(root).GetProfiles().Single();
            Assert.AreEqual(expected.Id, actual.Id);
            Assert.AreEqual("Professional", actual.Editions.Single());
            Assert.AreEqual("ru-ru", actual.Language);
        });
    }

    [TestMethod]
    public void ProfileSchemaVersionIsIndependentAndVersioned()
    {
        WithTemp(root =>
        {
            var service = NewProfiles(root); service.Save(SampleProfile());
            using var json = JsonDocument.Parse(File.ReadAllText(service.StorePath));
            Assert.AreEqual(ProfileService.SchemaVersion, json.RootElement.GetProperty("schemaVersion").GetInt32());
        });
    }

    [TestMethod]
    public void CorruptedProfileStoreRecoversWithoutCrash()
    {
        WithTemp(root =>
        {
            var path = Path.Combine(root, "profiles.json"); File.WriteAllText(path, "[broken");
            var service = new ProfileService(new GuiLogger(), path);
            Assert.AreEqual(0, service.GetProfiles().Count);
            Assert.AreEqual(1, Directory.GetFiles(root, "profiles.damaged-*.json").Length);
        });
    }

    [TestMethod]
    public void ProfileCreateUpdateDeleteUsesUuidIdentity()
    {
        WithTemp(root =>
        {
            var service = NewProfiles(root);
            var profile = service.Save(SampleProfile());
            Assert.IsTrue(Guid.TryParse(profile.Id, out _));
            profile.Name = "Updated"; service.Save(profile);
            Assert.AreEqual(1, service.GetProfiles().Count);
            Assert.AreEqual("Updated", service.GetProfiles().Single().Name);
            Assert.IsTrue(service.Delete(profile.Id));
            Assert.AreEqual(0, service.GetProfiles().Count);
        });
    }

    [TestMethod]
    public void DuplicateProfileDisplayNamesAreAllowed()
    {
        WithTemp(root =>
        {
            var service = NewProfiles(root);
            service.Save(SampleProfile());
            var second = SampleProfile(); second.Id = Guid.NewGuid().ToString("D"); service.Save(second);
            Assert.AreEqual(2, service.GetProfiles().Count);
        });
    }

    [TestMethod]
    public void DynamicProfileDoesNotPersistPinnedBuild()
    {
        WithTemp(root =>
        {
            var service = NewProfiles(root); var profile = SampleProfile(); profile.PinnedBuild = SamplePinned();
            var saved = service.Save(profile);
            Assert.AreEqual(ProfileSelectionMode.Recommended, saved.SelectionMode);
            Assert.IsNull(saved.PinnedBuild);
        });
    }

    [TestMethod]
    public void PinnedProfilePersistsControlledIdentity()
    {
        WithTemp(root =>
        {
            var service = NewProfiles(root); var profile = SampleProfile(); profile.SelectionMode = ProfileSelectionMode.Pinned; profile.PinnedBuild = SamplePinned(); service.Save(profile);
            var loaded = NewProfiles(root).GetProfiles().Single();
            Assert.AreEqual(ProfileSelectionMode.Pinned, loaded.SelectionMode);
            Assert.AreEqual("26200.1000", loaded.PinnedBuild?.Build);
        });
    }

    [TestMethod]
    public void ProfileNameIsTrimmedLimitedAndUuidDefinesIdentity()
    {
        WithTemp(root =>
        {
            var service = NewProfiles(root); var profile = SampleProfile(); profile.Name = "  My profile  "; service.Save(profile);
            Assert.AreEqual("My profile", service.GetProfiles().Single().Name);
            Assert.ThrowsException<ArgumentException>(() => ProfileService.NormalizeName(new string('x', 81)));
        });
    }

    [TestMethod]
    public void ProfileOutputPathIsPreservedWithoutCreatingIt()
    {
        WithTemp(root =>
        {
            var missing = Path.Combine(root, "does-not-exist"); var profile = SampleProfile(); profile.OutputDirectory = missing;
            var service = NewProfiles(root); service.Save(profile);
            Assert.AreEqual(missing, NewProfiles(root).GetProfiles().Single().OutputDirectory);
            Assert.IsFalse(Directory.Exists(missing));
        });
    }

    [TestMethod]
    public void HistoryCreatesRecommendedProfileByDefault()
    {
        var profile = ProfileService.FromHistory(SampleHistory(), "From history");
        Assert.AreEqual(ProfileSelectionMode.Recommended, profile.SelectionMode);
        Assert.IsNull(profile.PinnedBuild);
    }

    private static HistoryService NewHistory(string root) => new(new GuiLogger(), Path.Combine(root, "history.json"));
    private static ProfileService NewProfiles(string root) => new(new GuiLogger(), Path.Combine(root, "profiles.json"));

    private static HistoryEntry SampleHistory() => new()
    {
        Product = "Windows 11", VersionLabel = "25H2", Build = "26200.1000", Architecture = "amd64", Language = "ru-ru",
        Editions = ["Professional"], ImageFormat = "ESD", AddUpdates = true, Cleanup = true, NetFx3 = false, OutputDirectory = @"D:\ISO"
    };

    private static BuildResultDto SampleResult(string root) => new()
    {
        Stage = "completed", IsoPath = Path.Combine(root, "Windows.iso"), Sha256 = new string('a', 64),
        LogPath = Path.Combine(root, "build.log"), ExecutionLogPath = Path.Combine(root, "execution.log"),
        WorkDirectory = Path.Combine(root, "work"), MetadataPath = Path.Combine(root, "metadata.json")
    };

    private static BuildProfile SampleProfile() => new()
    {
        Name = "Windows 11 Pro RU", SelectionMode = ProfileSelectionMode.Recommended, Product = "Windows 11", Architecture = "amd64",
        Language = "ru-ru", Editions = ["Professional"], ImageFormat = "ESD", AddUpdates = true, Cleanup = true, OutputDirectory = @"D:\ISO"
    };

    private static PinnedBuildIdentity SamplePinned() => new()
    {
        Product = "Windows 11", VersionLabel = "25H2", Build = "26200.1000", Architecture = "amd64"
    };

    private static void WithTemp(Action<string> action)
    {
        var root = Path.Combine(Path.GetTempPath(), "wib-local-data-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try { action(root); }
        finally { Directory.Delete(root, recursive: true); }
    }
}
