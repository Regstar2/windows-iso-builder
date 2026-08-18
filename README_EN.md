<div align="center">

# Windows ISO Builder

An interactive PowerShell UUP dump client for searching, downloading, and automatically building Windows ISO images without manually handling the website, UUIDs, SKUs, or `ConvertConfig.ini`.

[Русский](README.md) · **English**

[Quick start](#quick-start) · [Backend Contract](#backend-contract) · [Release validation](#release-validation) · [Documentation](#documentation)

</div>

## About

Windows ISO Builder uses the dynamic UUP dump catalog and obtains Windows files from Microsoft Windows Update/CDN through the generated UUP dump conversion package. The project does not embed a Windows version catalog and does not implement a custom UUP downloader/converter.

TUI, non-interactive CLI, and the machine-readable Backend Contract share the same PowerShell backend.

## Project status

Current version: **`0.2.3-alpha.1`**.

- ApplicationVersion: `0.2.3-alpha.1`;
- PowerShell ModuleVersion: `0.2.3`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`0.2.3-alpha.1` is the final backend-focused validation release before `v0.3.0` GUI work begins. GUI, WPF/WinUI, and C# are intentionally absent.

## Features

- dynamic Windows build search and quick mode without hardcoded build numbers;
- dynamic languages/editions and multi-edition virtual editions;
- `install.wim` and `install.esd`;
- API/package/UUP cache and native `aria2` resume;
- compact console progress and complete `converter-*.log` output;
- build/elevated/execution logs, SHA-256, and JSON metadata;
- TUI and non-interactive PowerShell CLI;
- Backend Contract v1 with JSON requests/responses and NDJSON events;
- `RunPreflight` with an aggregated machine-readable report;
- local preflight before UAC and authoritative preflight inside the worker;
- structured source-level error taxonomy with optional `details`;
- `CancelBuild` and cooperative cancellation addressed by `requestId`;
- cancellation forwarding across the elevation boundary;
- PID-rooted termination of only the process tree owned by the build;
- preservation of partial UUP cache/work data after cancellation;
- a local release-validation workflow that validates source and the release ZIP separately.

## Quick start

1. Download and extract the release ZIP.
2. Run `Start-Builder.cmd`.
3. Select normal search or quick mode.
4. Choose language, editions, and WIM/ESD.
5. Local preflight runs before UAC. Fatal problems must not open the elevation prompt.
6. If preflight succeeds, approve UAC and wait for the ISO.

Default work cache: `C:\UUP-ISO-Work`.

## Requirements

- Windows 10/11 x64 for real ISO builds;
- Windows PowerShell 5.1 or PowerShell 7;
- DISM, `Expand-Archive`, and `Get-FileHash`;
- administrator rights for the UUP/conversion stage;
- conservative minimums: 40 GiB cache/work and 8 GiB output;
- access to UUP dump and Microsoft Windows Update/CDN.

`Mount-DiskImage` enables deeper post-build validation, but its absence is a warning rather than a fatal preflight failure.

## Reliability and cancellation

`RunPreflight` returns `ready` plus `checks` with stable `id`, `status`, `severity`, `code`, `message`, and `data`. An environment that is not ready is a successful Backend Contract operation (`success=true`, `data.ready=false`), not a transport failure.

`ExecuteBuildPlan.requestId` is the public operation id. `CancelBuild` accepts `targetRequestId` and `cacheDirectory`; the control filename is derived from a SHA-256 hash, never from the raw request id.

`CancelBuild` only acknowledges that a cancellation request was accepted. Actual termination is confirmed by the target `ExecuteBuildPlan` response/event using `BUILD_CANCELLED`/`cancelled`.

The managed runner terminates only the process tree rooted at a PID started by Windows ISO Builder. It never searches for or kills `aria2`, DISM, or other processes by name. Partial downloads/work data remain available for resume.

## CLI example

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1 `
  -NonInteractive `
  -Search 22H2 `
  -Architecture amd64 `
  -Language ru-ru `
  -Editions Core,Professional `
  -ImageFormat ESD
```

## Backend Contract

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson
```

Backend Contract Schema v1 commands:

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`, `RunPreflight`, `CancelBuild`.

After `v0.2.3`, Contract v1 and BuildPlan v1 are the baseline interface for the first GUI. Additive optional fields remain allowed; breaking changes require a new SchemaVersion.

Full contract: [docs/BACKEND_CONTRACT_EN.md](docs/BACKEND_CONTRACT_EN.md).

## Release validation

The project uses local Pester tests, PSScriptAnalyzer, and one release-validation entry point. GitHub Actions are intentionally not a release gate.

Quick validation does not download a UUP set or build an ISO:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1
```

Full safe release smoke includes temporary ZIP creation/extraction and the controlled process-tree test:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Validation writes machine-readable `validation-result.json` and returns a non-zero exit code when a required check fails. Generated reports and `dist/` are not committed.

Source validation and release-package validation are separate layers. See [docs/VALIDATION_MATRIX_EN.md](docs/VALIDATION_MATRIX_EN.md) for the actual automated, smoke, and real-E2E statuses.

## Release package

`tools/New-ReleasePackage.ps1` reads the application version from `VERSION`, creates the ZIP and `.sha256`, and adds a generated `release-manifest.json` containing application, module, Backend Contract, and BuildPlan versions.

The ZIP is built from a centralized allowlist and must not contain `tests`, `.git`, `.github`, `output`, `logs`, `dist`, cache, IDE state, `.project-rules`, or user-specific files.

## Security

- explicit Backend command allowlist;
- no `Invoke-Expression`/eval;
- requests are untrusted input;
- cancellation paths are derived from SHA-256 request-id hashes;
- process termination targets only an owned PID tree;
- machine responses must not expose tokens, signed UUP URLs, product keys, or Exception object graphs;
- release validation performs a limited scan of current tracked files and the package for obvious secrets/personal paths.

This scan is not a historical Git-history audit.

## Documentation

- [Backend Contract v1](docs/BACKEND_CONTRACT_EN.md)
- [Validation matrix](docs/VALIDATION_MATRIX_EN.md)
- [Requirements](REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Implementation status](docs/IMPLEMENTATION_STATUS.md)
- [Changelog](CHANGELOG.md)
- [Release notes](docs/releases/)
- [Security](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Limitations

- `0.2.3-alpha.1` remains an alpha release;
- GUI, WPF/WinUI, queue/history/profiles, updater, USB/Rufus integration, and dynamic disk estimation are not implemented;
- Backend Contract transport is local JSON/NDJSON files plus a PowerShell process, not an HTTP server;
- Windows 10 real E2E and a separate Windows 11 WIM baseline may be marked confirmed only after they are actually built manually;
- the external UUP dump API/conversion package can change.

## License

Windows ISO Builder code is distributed under the [MIT License](LICENSE). Windows, UUP dump, and third-party tools retain their own licenses and terms.
