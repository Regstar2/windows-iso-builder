using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Backend;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class StateAndIntegrationTests
{
    [TestMethod]
    public void StateMachineAllowsNormalBuildAndCancellationPaths()
    {
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Idle, UiState.LoadingBuild));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.LoadingBuild, UiState.LoadingLanguages));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.LoadingLanguages, UiState.LoadingEditions));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.LoadingEditions, UiState.ReadyToPreflight));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.ReadyToPreflight, UiState.Preflighting));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Preflighting, UiState.ReadyToBuild));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.ReadyToBuild, UiState.Building));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Building, UiState.Cancelling));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Cancelling, UiState.Cancelled));
        Assert.IsFalse(UiStateRules.CanTransition(UiState.Idle, UiState.Completed));
    }

    [TestMethod]
    public void StateMachineAllowsCancellationFailureAndRetryRecovery()
    {
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Cancelling, UiState.Building));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Failed, UiState.ReadyToBuild));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Failed, UiState.ReadyToPreflight));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Failed, UiState.LoadingBuild));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Failed, UiState.LoadingLanguages));
        Assert.IsTrue(UiStateRules.CanTransition(UiState.Failed, UiState.LoadingEditions));
    }

    [TestMethod]
    public async Task RealBackendGetVersionSmokeOnWindows()
    {
        if (!OperatingSystem.IsWindows())
        {
            Assert.Inconclusive("Windows-only integration smoke.");
            return;
        }

        var script = new BackendPathResolver().Resolve();
        var response = await new BackendClient(script, new GuiLogger()).InvokeAsync<VersionData>("GetVersion", new { });
        Assert.IsTrue(response.Success);
        Assert.AreEqual(1, response.Data?.ContractSchemaVersion);
        Assert.AreEqual(1, response.Data?.BuildPlanSchemaVersion);
    }

    [TestMethod]
    public async Task RealBackendOfflinePreflightSmokeOnWindows()
    {
        if (!OperatingSystem.IsWindows())
        {
            Assert.Inconclusive("Windows-only integration smoke.");
            return;
        }

        var root = Path.Combine(Path.GetTempPath(), "wib-gui-preflight-" + Guid.NewGuid().ToString("N"));
        var cache = Path.Combine(root, "cache");
        var output = Path.Combine(root, "output");
        Directory.CreateDirectory(cache);
        Directory.CreateDirectory(output);

        try
        {
            var script = new BackendPathResolver().Resolve();
            var client = new BackendClient(script, new GuiLogger());
            var version = await client.InvokeAsync<VersionData>("GetVersion", new { });
            var plan = new BuildPlanDto
            {
                SchemaVersion = 1,
                ApplicationVersion = version.Data?.ApplicationVersion ?? version.ApplicationVersion,
                CreatedAt = DateTimeOffset.UtcNow,
                Build = new BuildDto
                {
                    Uuid = "00000000-0000-0000-0000-000000000000",
                    Title = "GUI offline preflight smoke",
                    Product = "Windows 11",
                    VersionLabel = "smoke",
                    Build = "0.0",
                    Architecture = "amd64",
                    EntryType = "Windows",
                    CreatedAt = DateTimeOffset.UtcNow,
                    IsPreview = false
                },
                Language = "ru-ru",
                Editions = ["Professional"],
                SourceEdition = "Professional",
                VirtualEditions = [],
                ImageFormat = "ESD",
                AddUpdates = true,
                Cleanup = true,
                NetFx3 = false,
                OutputDirectory = output,
                CacheDirectory = cache,
                RemoveWorkAfterSuccess = false
            };

            var response = await client.InvokeAsync<PreflightData>(
                "RunPreflight",
                new { buildPlan = plan, onlineChecks = false });
            Assert.IsNotNull(response.Data);
            Assert.IsNotNull(response.Data.Checks);
            Assert.IsTrue(response.Data.Checks.Count > 0);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
