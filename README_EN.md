<div align="center">

# Windows ISO Builder

GUI and PowerShell UUP dump client for discovering, validating, and building Windows ISO images without manual UUID, SKU, or `ConvertConfig.ini` work.

[Русский](README.md) · **English**

</div>

## Status

Current version: **`0.4.0-alpha.1`**.

- ApplicationVersion: `0.4.0-alpha.1`;
- GUI Assembly/File version: `0.4.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`;
- History schema: `1`;
- Profile schema: `1`.

`v0.4.0-alpha.1` adds local build history and reusable build profiles. The PowerShell backend, TUI/CLI, Backend Contract v1, and BuildPlan v1 remain intact. History and Profiles are GUI application-level features and do not create a second build pipeline.

## Main GUI flow

1. **Build** — choose Windows/architecture, load the recommended build, or apply a build from Catalog, History, or Profiles.
2. Choose language, editions, WIM/ESD, options, and output directory.
3. Run backend-owned `CreateBuildPlan` and `RunPreflight`.
4. Review the resulting configuration and explicitly confirm ISO creation.
5. The backend runs the existing UAC/download/converter/DISM/ISO workflow.
6. The terminal result is recorded in **History**.

Left navigation: **Build → Catalog → History → Profiles → Settings → Help → About**.

## Build History

History stores a controlled GUI DTO only for real `ExecuteBuildPlan` operations: completed, failed, cancelled, and interrupted. Metadata queries and preflight do not become history entries.

Each entry can show Windows/build/architecture/language/editions/format, timestamps, status, ISO/SHA-256, logs, metadata, and error code. Deleting an entry or clearing history removes **GUI records only**; ISO files, UUP cache, work directories, logs, and metadata are not deleted.

**Repeat** never executes an old BuildPlan. The GUI resolves the saved build against the current catalog, fetches current languages/editions, and returns the user to Build. If the exact build is gone, the user explicitly chooses the current recommended build, Catalog, or Cancel. No ISO build is auto-started.

## Profiles

A profile is a saved user intention, not an executable BuildPlan.

Two modes are supported:

- **Recommended / Dynamic** — stores product/architecture/language/editions/format/options/output and resolves `GetRecommendedBuild` against the current backend catalog every time;
- **Pinned Build** — additionally stores a controlled identity for one concrete build and uses it only if it can still be resolved through `SearchBuilds`.

Recommended is the default, including profiles created from History. Pinned mode is explicit. Profiles do not store the UUP catalog, signed URLs, cache directory, BuildPlan, tokens, or secrets.

If a saved language/edition is no longer available, the GUI exposes a stale state instead of silently replacing values. If a pinned build disappears, using a recommended fallback is an explicit session action and does not rewrite the saved profile automatically.

## Local data

GUI user data lives under `%LOCALAPPDATA%\WindowsISOBuilder`:

- `settings.json` — language, theme, and window state;
- `history.json` — History schema v1, maximum 200 entries;
- `profiles.json` — Profile schema v1;
- `logs\` — GUI logs.

History/Profile stores use temp write + flush + atomic replace/move. Corrupt JSON is preserved as `*.damaged-*` when possible and the GUI continues with an empty store. An unknown future schema is not overwritten automatically.

`history.json` and `profiles.json` are not sent over the network, do not enter the release ZIP, and are not included in diagnostics. See [docs/LOCAL_DATA_EN.md](docs/LOCAL_DATA_EN.md).

## GUI

The GUI is C# / WPF / .NET 10 and talks to `Invoke-WibBackend.ps1` through Backend Contract v1. It includes:

- Build and responsive Catalog pages;
- History and Profiles;
- dynamic languages/editions;
- ESD/WIM and converter options;
- preflight;
- asynchronous `ExecuteBuildPlan` with NDJSON progress;
- cooperative `CancelBuild`;
- structured errors;
- RU/EN localization;
- System/Light/Dark themes;
- persisted window state;
- keyboard/accessibility groundwork and AutomationProperties for primary actions;
- sanitized diagnostics ZIP with a fixed allowlist;
- self-contained `win-x64` publish/package.

The GUI runs as `asInvoker`; UAC remains part of the backend workflow immediately before privileged build operations.

## Console / automation

TUI/CLI remain supported:

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

The PowerShell backend remains the sole owner of:

- UUP catalog/recommendation;
- languages/editions;
- BuildPlan v1;
- preflight;
- UAC/elevation;
- download/converter/DISM;
- ISO validation;
- cancellation process tree.

History/Profile/Repeat do not extend Backend Contract and never use BuildPlan as a persistent profile format. GUI compatibility is based on Backend Contract SchemaVersion `1` and BuildPlan SchemaVersion `1`, not ApplicationVersion equality.

## Requirements

User runtime:

- Windows 10/11 x64;
- Windows PowerShell 5.1;
- DISM and standard Windows tools;
- access to UUP dump and Microsoft Windows Update/CDN;
- sufficient cache/work/output disk space;
- administrator consent only for the privileged build stage.

GUI development requires the .NET 10 SDK.

## Build and tests

```powershell
dotnet restore .\WindowsISOBuilder.sln
dotnet build .\WindowsISOBuilder.sln -c Release
dotnet test .\WindowsISOBuilder.sln -c Release --no-build
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Gui.ps1
```

Full release validation:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Pull requests into `master` run the same Full validation on the owner-controlled Windows self-hosted runner plus a published-GUI startup smoke. Automated validation does not download Windows and must not be presented as manual DPI/Narrator/real ISO E2E acceptance.

## Release package

The ZIP contains application runtime, PowerShell backend/TUI/CLI, and user documentation. Local `%LOCALAPPDATA%` files, `.github`, tests, `bin`/`obj`, validation artifacts, ISO/WIM/ESD/logs, and developer-only files are excluded.

## Security and privacy

- requests are treated as untrusted data;
- backend dispatch uses an allowlist;
- C# launches PowerShell with `ProcessStartInfo.ArgumentList`;
- cancellation uses `CancelBuild`, not kill-by-name;
- signed UUP URLs, tokens, product keys, and arbitrary backend payloads are not stored in History/Profile;
- diagnostics has a fixed allowlist: `app-version.txt`, `environment.json`, `execution.log`, `build.log`, `converter.log`, all passed through the sanitizer;
- History/Profiles are local and are not included in diagnostics automatically.

## Documentation

- [Backend Contract v1](docs/BACKEND_CONTRACT_EN.md)
- [GUI architecture](docs/GUI_ARCHITECTURE_EN.md)
- [Project architecture](docs/ARCHITECTURE.md)
- [Local data and privacy](docs/LOCAL_DATA_EN.md)
- [Implementation status](docs/IMPLEMENTATION_STATUS.md)
- [Validation matrix](docs/VALIDATION_MATRIX_EN.md)
- [Requirements](REQUIREMENTS.md)
- [Changelog](CHANGELOG.md)
- [v0.4.0-alpha.1 release notes](docs/releases/v0.4.0-alpha.1_EN.md)

## Out of scope for v0.4.0

Queue/parallel builds/scheduling, updater, installer/MSIX, cache-management GUI, USB/Rufus, driver injection, customization/debloat, TPM bypass, activation, accounts/cloud sync/telemetry, profile import/export/sync, custom UUP downloader/converter.

## License

Original Windows ISO Builder code is distributed under the [MIT License](LICENSE). Windows, UUP dump, and third-party tools have their own licenses and terms.
