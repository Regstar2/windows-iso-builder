<div align="center">

# Windows ISO Builder

An interactive UUP dump client for searching, downloading, and automatically building Windows ISO images without manually handling the website, UUIDs, SKUs, or `ConvertConfig.ini`.

[Русский](README.md) · **English**

[Quick start](#quick-start) · [Backend Contract](#backend-contract) · [Reliability](#reliability-and-cancellation) · [Documentation](#documentation)

</div>

## About

Windows ISO Builder uses the dynamic UUP dump catalog and obtains Windows files from Microsoft Windows Update/CDN through the generated UUP dump conversion package. The project does not embed a Windows version catalog and does not implement a custom UUP downloader/converter.

TUI/CLI and the machine-readable Backend Contract use the same PowerShell backend.

## Project status

Current version: **`0.2.2-alpha.1`**.

- ApplicationVersion: `0.2.2-alpha.1`;
- PowerShell ModuleVersion: `0.2.2`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`0.2.2-alpha.1` is the second architecture release before a future GUI. GUI, WPF/WinUI, and C# are intentionally absent.

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
- structured source-level error taxonomy with optional details;
- `CancelBuild` and cooperative cancellation addressed by `requestId`;
- cancellation forwarding across the elevation boundary;
- PID-rooted termination of only the process tree owned by the build;
- preservation of partial UUP cache/work data after cancellation.

## Quick start

1. Extract the source or release ZIP.
2. Run `Start-Builder.cmd`.
3. Select normal search or quick mode.
4. Choose language, editions, and WIM/ESD.
5. Local preflight runs before UAC. Fatal problems prevent UAC from opening.
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

`RunPreflight` aggregates independent problems instead of failing on the first one. It returns `ready` plus `checks` with stable `id`, `status`, `severity`, `code`, `message`, and `data` fields. Disk sizes are returned as numeric `availableBytes` and `requiredBytes` values.

An environment that is not ready is a successful Backend Contract operation (`success=true`, `data.ready=false`), not a transport failure.

`ExecuteBuildPlan.requestId` is the public operation id. `CancelBuild` accepts `targetRequestId` and `cacheDirectory`; the control filename is derived from a SHA-256 hash, never from the raw request id.

`CancelBuild` only acknowledges that **a cancellation request was accepted**. Actual termination is confirmed by the target `ExecuteBuildPlan` final response/event using `BUILD_CANCELLED`/`cancelled`.

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

Schema remains `1`: the new commands, error codes, and optional fields are backward-compatible v1 additions. BuildPlan Schema also remains `1`; cancellation belongs to the runtime ExecutionContext and is not persisted in BuildPlan.

Full contract: [docs/BACKEND_CONTRACT_EN.md](docs/BACKEND_CONTRACT_EN.md).

## Security

- explicit command allowlist;
- no `Invoke-Expression`/eval;
- requests are untrusted input;
- cancellation paths are derived from SHA-256 request-id hashes;
- process termination targets only an owned PID tree;
- preflight uses a unique temporary probe file and removes it;
- machine responses must not expose tokens, signed UUP URLs, product keys, or Exception object graphs.

## Testing

The project uses local Pester tests and PSScriptAnalyzer. GitHub Actions are intentionally not a release gate.

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1

$issues = @(Invoke-ScriptAnalyzer `
  -Path . `
  -Recurse `
  -Settings .\.psscriptanalyzer.psd1)
```

Reliability tests mock external operations and do not download Windows. The real process-tree smoke test is opt-in (`WIB_RUN_PROCESS_CANCELLATION_SMOKE=1`) and uses a controlled dummy PowerShell child rather than aria2/DISM.

## Documentation

- [Backend Contract v1](docs/BACKEND_CONTRACT_EN.md)
- [Requirements](REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Implementation status](docs/IMPLEMENTATION_STATUS.md)
- [Changelog](CHANGELOG.md)
- [Release notes](docs/releases/)
- [Security](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Limitations

- `0.2.2-alpha.1` remains an alpha release;
- GUI, WPF/WinUI, queue/history/profiles, updater, USB/Rufus integration, and dynamic disk estimation are not implemented;
- Backend Contract transport is local JSON/NDJSON files plus a PowerShell process, not an HTTP server;
- a full Windows 10/11 E2E matrix is outside this release;
- the external UUP dump API/conversion package can change.

## License

Windows ISO Builder code is distributed under the [MIT License](LICENSE). Windows, UUP dump, and third-party tools retain their own licenses and terms.
