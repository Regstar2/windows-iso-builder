using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Backend;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class ContractTests
{
    [TestMethod] public void GetVersionResponseDeserializes() { var x = JsonSerializer.Deserialize<BackendResponse<VersionData>>("""{"schemaVersion":1,"requestId":"a","command":"GetVersion","success":true,"applicationVersion":"0.3.0-alpha.1","data":{"applicationVersion":"0.3.0-alpha.1","contractSchemaVersion":1,"buildPlanSchemaVersion":1,"future":1}}""", BackendClient.JsonOptions); Assert.AreEqual(1, x!.Data!.ContractSchemaVersion); }
    [TestMethod] public void SuccessEnvelopeDeserializes() { var x = JsonSerializer.Deserialize<BackendResponse<object>>("""{"schemaVersion":1,"requestId":"a","command":"x","success":true,"applicationVersion":"x","data":{}}""", BackendClient.JsonOptions); Assert.IsTrue(x!.Success); }
    [TestMethod] public void ErrorEnvelopeDeserializes() { var x = JsonSerializer.Deserialize<BackendResponse<object>>("""{"schemaVersion":1,"requestId":"a","command":"x","success":false,"applicationVersion":"x","error":{"code":"FUTURE_CODE","message":"x","stage":"startup","details":null,"logPath":null}}""", BackendClient.JsonOptions); Assert.AreEqual("FUTURE_CODE", x!.Error!.Code); }
    [TestMethod] public void UnknownOptionalPropertyIsTolerated() { var x = JsonSerializer.Deserialize<BuildDto>("""{"uuid":"u","title":"t","product":"Windows 11","versionLabel":"25H2","build":"26200","architecture":"amd64","entryType":"Windows","createdAt":"2026-08-18T00:00:00Z","isPreview":false,"future":{"x":1}}""", BackendClient.JsonOptions); Assert.AreEqual("u", x!.Uuid); }
    [TestMethod] public void UnknownErrorCodeMapsGeneric() { Assert.AreEqual("Не удалось выполнить операцию", ErrorMapper.Map("FUTURE_CODE").Title); }
    [TestMethod] public void BuildDtoDeserializes() { var x = JsonSerializer.Deserialize<BuildDto>("""{"uuid":"u","title":"t","product":"Windows 11","versionLabel":"25H2","build":"26200","architecture":"amd64","entryType":"Windows","createdAt":"2026-08-18T00:00:00Z","isPreview":false}""", BackendClient.JsonOptions); Assert.AreEqual("26200", x!.Build); }
    [TestMethod] public void LanguageDtoDeserializes() { Assert.AreEqual("ru-ru", JsonSerializer.Deserialize<LanguageDto>("""{"code":"ru-ru","name":"Russian"}""", BackendClient.JsonOptions)!.Code); }
    [TestMethod] public void EditionDtoDeserializes() { Assert.AreEqual("Professional", JsonSerializer.Deserialize<EditionDto>("""{"code":"Professional","name":"Pro"}""", BackendClient.JsonOptions)!.Code); }
    [TestMethod] public void BuildPlanDtoDeserializes() { var plan = JsonSerializer.Deserialize<BuildPlanDto>("""{"schemaVersion":1,"applicationVersion":"0.3.0-alpha.1","createdAt":"2026-08-18T00:00:00Z","build":{"uuid":"u","title":"t","product":"Windows 11","versionLabel":"25H2","build":"26200","architecture":"amd64","entryType":"Windows","createdAt":"2026-08-18T00:00:00Z","isPreview":false},"language":"ru-ru","editions":["Professional"],"sourceEdition":"Professional","virtualEditions":[],"imageFormat":"ESD","addUpdates":true,"cleanup":true,"netFx3":false,"outputDirectory":"C:\\out","cacheDirectory":"C:\\cache","removeWorkAfterSuccess":false}""", BackendClient.JsonOptions); Assert.AreEqual("Professional", plan!.SourceEdition); Assert.AreEqual("C:\\cache", plan.CacheDirectory); }
    [TestMethod] public void PreflightReportDeserializes() { var p = JsonSerializer.Deserialize<PreflightData>("""{"ready":false,"checks":[{"id":"disk","status":"failed","severity":"error","code":"DISK_SPACE_LOW","message":"low","data":{"availableBytes":1}}]}""", BackendClient.JsonOptions); Assert.IsFalse(p!.Ready); Assert.AreEqual("DISK_SPACE_LOW", p.Checks[0].Code); }
    [TestMethod] public void BuildResultDeserializes() { Assert.AreEqual("x.iso", JsonSerializer.Deserialize<BuildResultDto>("""{"stage":"completed","isoPath":"x.iso","sha256":"a","logPath":"l","executionLogPath":"e","workDirectory":"w","metadataPath":"m"}""", BackendClient.JsonOptions)!.IsoPath); }
    [TestMethod] public void ProgressEventDeserializes() { var ev = JsonSerializer.Deserialize<BackendEvent>("""{"schemaVersion":1,"requestId":"r","sequence":2,"timestamp":"2026-08-18T00:00:00Z","type":"progress","stage":"download","message":"x","progress":{"percent":67,"detailPercent":50,"speedText":"31 MiB/s","speedBytesPerSecond":1}}""", BackendClient.JsonOptions); Assert.AreEqual(67, ev!.Progress!.Percent); }
    [TestMethod] public void CancelledEventDeserializes() { var ev = JsonSerializer.Deserialize<BackendEvent>("""{"schemaVersion":1,"requestId":"r","sequence":3,"timestamp":"2026-08-18T00:00:00Z","type":"cancelled","stage":"failed","message":"cancelled","progress":null}""", BackendClient.JsonOptions); Assert.AreEqual("cancelled", ev!.Type); }
    [TestMethod] public void UnknownEventTypeDeserializes() { var ev = JsonSerializer.Deserialize<BackendEvent>("""{"schemaVersion":1,"requestId":"r","sequence":4,"timestamp":"2026-08-18T00:00:00Z","type":"future-event","stage":"metadata","message":"x","progress":null}""", BackendClient.JsonOptions); Assert.AreEqual("future-event", ev!.Type); }
    [TestMethod] public void RequestIdGenerationIsUnique() { Assert.AreNotEqual(BackendClient.NewRequestId(), BackendClient.NewRequestId()); }
    [TestMethod] public void SafeRequestSerializationDoesNotEmitTypeMetadata() { var json = JsonSerializer.Serialize(new BackendRequest(1, "id", "GetVersion", new { search = "x;Write-Host hacked" }), BackendClient.JsonOptions); Assert.IsFalse(json.Contains("$type", StringComparison.OrdinalIgnoreCase)); Assert.IsTrue(json.Contains("x;Write-Host hacked")); }

    [TestMethod]
    public void BackendProcessArgumentsAreSeparatedAndHostIsDeterministic()
    {
        var p = new BackendProcessRunner().CreateStartInfo("C:\\a b\\x.ps1", "r q.json", "resp.json", "events.json");
        CollectionAssert.Contains(p.ArgumentList.ToArray(), "C:\\a b\\x.ps1");
        CollectionAssert.Contains(p.ArgumentList.ToArray(), "r q.json");
        Assert.AreEqual(
            Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
            p.FileName);
    }

    [TestMethod] public void BackendPathResolverUsesExplicitRoot() { var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root); var file = Path.Combine(root, "Invoke-WibBackend.ps1"); File.WriteAllText(file, "# test"); try { Assert.AreEqual(file, new BackendPathResolver().Resolve(root)); } finally { Directory.Delete(root, true); } }

    [TestMethod]
    public void BackendPathResolverDoesNotTrustAmbientExecutableOverride()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var fakeBackend = Path.Combine(root, "Invoke-WibBackend.ps1");
        File.WriteAllText(fakeBackend, "# untrusted ambient override");
        var oldValue = Environment.GetEnvironmentVariable("WIB_BACKEND_ROOT");
        try
        {
            Environment.SetEnvironmentVariable("WIB_BACKEND_ROOT", root);
            var resolved = new BackendPathResolver().Resolve();
            Assert.AreNotEqual(Path.GetFullPath(fakeBackend), Path.GetFullPath(resolved));
        }
        finally
        {
            Environment.SetEnvironmentVariable("WIB_BACKEND_ROOT", oldValue);
            Directory.Delete(root, true);
        }
    }

    [TestMethod] public void ErrorMappingKnownCode() { Assert.AreEqual("Недостаточно свободного места", ErrorMapper.Map("DISK_SPACE_LOW").Title); }

    [TestMethod]
    public void ErrorMappingsCoverStableBackendTaxonomy()
    {
        var generic = ErrorMapper.Map("FUTURE_CODE").Title;
        foreach (var code in new[]
        {
            "UNSUPPORTED_SCHEMA", "UNSUPPORTED_HOST", "INVALID_ARGUMENT", "INVALID_BUILD_PLAN",
            "LANGUAGE_NOT_FOUND", "EDITION_NOT_FOUND",
            "DISK_SPACE_LOW", "PATH_NOT_WRITABLE", "REQUIRED_COMPONENT_MISSING",
            "UUP_API_UNAVAILABLE", "NETWORK_ERROR", "UUP_PACKAGE_DOWNLOAD_FAILED",
            "UUP_PACKAGE_INVALID", "DOWNLOAD_FAILED", "CONVERTER_FAILED", "DISM_FAILED",
            "ISO_NOT_FOUND", "ISO_VALIDATION_FAILED", "ELEVATION_CANCELLED",
            "BUILD_CANCELLED", "BUILD_FAILED", "INTERNAL_ERROR"
        })
        {
            Assert.AreNotEqual(generic, ErrorMapper.Map(code).Title, $"Missing user-facing mapping for {code}.");
        }
    }
}
