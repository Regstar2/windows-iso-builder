<div align="center">

# Windows ISO Builder

A GUI and PowerShell UUP dump client for searching, downloading, and building Windows ISO images without manually handling UUIDs, SKUs, or `ConvertConfig.ini`.

[Русский](README.md) · **English**

</div>

## Status

Current version: **`0.3.0-alpha.1`**.

- ApplicationVersion: `0.3.0-alpha.1`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`v0.3.0-alpha.1` adds the first WPF GUI. The existing TUI, CLI, and machine-readable Backend Contract remain supported. The GUI is not a second UUP/build backend: it uses `Invoke-WibBackend.ps1` and Contract v1.

## Quick start — GUI

1. Download the release ZIP and extract it completely.
2. Run `WindowsISOBuilder.exe` as a normal user.
3. Select Windows 11/10 and request the recommended build, or open Catalog mode.
4. Select language, one or more editions, ESD/WIM, and the output directory.
5. Run readiness checks.
6. If no fatal check blocks the build, choose Create ISO and approve UAC when the backend requests elevation.
7. On completion, the GUI shows the ISO path and SHA-256.

The user release is self-contained `win-x64`; installing a separate .NET Runtime is not required. The .NET 10 SDK is a development/build dependency only.

## GUI scope

The first GUI includes Quick Mode, Catalog Mode with explicit build activation, dynamic languages/editions, multi-edition selection, ESD/WIM, build options, `CreateBuildPlan`, `RunPreflight`, async `ExecuteBuildPlan`, NDJSON progress, cooperative `CancelBuild`, stable backend error-code UX for preflight/download/converter/DISM/ISO/elevation/cancellation failures, result actions, and a local GUI log.

Catalog row highlighting does not start metadata requests. The selected row is activated by double-click or the explicit use-selected action and then enters the same Quick configuration/build flow.

The GUI manifest uses `asInvoker`. Elevation remains owned by the existing backend immediately before the privileged build stage.

## Console / automation

The TUI is not deprecated:

```powershell
.\Start-Builder.cmd
```

or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1
```

Machine entry point:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson
```

## Architecture boundary

The PowerShell backend remains the sole owner of UUP catalog/recommendation, BuildPlan, preflight, UAC/elevation, download, converter/DISM, ISO validation, and cancellation process-tree management.

The GUI does not import `WindowsISOBuilder.psm1`, invoke private functions, parse `Write-Host`/transcripts/aria2/converter output, or classify failures from localized messages.

Compatibility is schema-based rather than tied to exact ApplicationVersion matching. `v0.3.0-alpha.1` requires Backend Contract SchemaVersion `1` and BuildPlan SchemaVersion `1`; the packaged GUI smoke checks both values.

See [Backend Contract v1](docs/BACKEND_CONTRACT_EN.md) and [GUI architecture](docs/GUI_ARCHITECTURE_EN.md).

## Requirements

User runtime: Windows 10/11 x64, Windows PowerShell 5.1, standard Windows servicing tools, network access to UUP dump/Microsoft CDN, enough disk space, and administrator approval only for the privileged build stage.

Development requires the .NET 10 SDK.

## GUI build

```powershell
dotnet restore .\WindowsISOBuilder.sln
dotnet build .\WindowsISOBuilder.sln -c Release
dotnet test .\WindowsISOBuilder.sln -c Release --no-build
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Gui.ps1
```

`Build-Gui.ps1` restores, builds, tests, and publishes self-contained `win-x64`. It never installs the SDK automatically.

## Release validation

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Full validation covers GUI build/test/publish, Pester, PSScriptAnalyzer, backend smokes, packaging, checksum/manifest validation, and packaged `WindowsISOBuilder.exe --backend-smoke`. Safe automated smoke does not download Windows or request UAC.

The repository also contains `.github/workflows/windows-self-hosted-validation.yml`. Pull requests targeting `master` run the same Full validation on a Windows self-hosted runner labeled `self-hosted`, `Windows`, `X64`; superseded PR runs are cancelled through workflow concurrency. `validation-result.json` is uploaded as an Actions artifact even when validation fails.

Actual execution status must remain separate from implementation status. See [VALIDATION_MATRIX_EN.md](docs/VALIDATION_MATRIX_EN.md).

## Release package

The release ZIP contains `WindowsISOBuilder.exe` plus its self-contained runtime, the existing PowerShell backend/TUI/CLI, documentation, and a package-only `release-manifest.json` with application/module/schema versions and additive GUI metadata.

`.github`, tests, `bin`/`obj`, validation artifacts, and other developer-only files are excluded from the release ZIP.

## Security

Requests are untrusted data; backend dispatch is allowlisted; C# uses `ProcessStartInfo.ArgumentList`; user strings are not executed as PowerShell; GUI cancellation uses `CancelBuild` instead of process killing; signed URLs/tokens/product keys are not GUI-log data; backend code is resolved deterministically from the package and never downloaded at runtime.

## v0.3.0 limitations

History, profiles, queue, cache-management GUI, updater, installer/MSIX, USB/Rufus integration, full theme/language settings, customization/debloat, driver injection, TPM bypass, activation, and a custom UUP engine/downloader/converter are intentionally outside this GUI MVP. GitHub Actions is used only as a thin orchestration layer over the existing local Full validation on the owner's self-hosted Windows runner and is not part of the runtime/release package.

## License

Windows ISO Builder code is distributed under the [MIT License](LICENSE). Windows, UUP dump, and third-party tools retain their own licenses and terms.
