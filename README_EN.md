<div align="center">

# Windows ISO Builder

An interactive UUP dump client for searching, downloading, and building Windows ISO images without manually using the website, copying UUIDs, knowing SKU values, or editing `ConvertConfig.ini`.

[Русский](README.md) · **English**

[Quick start](#quick-start) · [Backend Contract](#backend-contract) · [Documentation](#documentation) · [Limitations](#limitations)

</div>

## About

Windows ISO Builder guides the user through searching for a Windows build and selecting architecture, language, editions, and installation-image format. The source code does not contain a fixed Windows release catalog: metadata comes from UUP dump, while Windows payload files are downloaded from Microsoft Windows Update/CDN.

The technical repository/root-directory name is `windows-iso-builder`; the public product name is Windows ISO Builder.

The project does not replace UUP dump or implement a separate UUP engine. It keeps one PowerShell backend for the existing human workflows and now exposes a stable machine-readable adapter over the same backend.

## Project status

The current application version is **`0.2.1-alpha.1`**. The PowerShell module manifest version is `0.2.1`. Backend Contract Schema and BuildPlan Schema are independently versioned and both currently equal `1`.

`0.2.1-alpha.1` is an architectural alpha preparing the project for a future GUI. **No GUI is implemented in this release.** Existing TUI/CLI behavior, UUP dump workflow, UAC/elevation, caching, and conversion remain in place; a JSON/NDJSON Backend Contract is added for future frontend clients.

See [implementation status](docs/IMPLEMENTATION_STATUS.md) for the validation matrix.

## Features

- dynamic search by release name, build number, or UUP dump title;
- quick selection of a recommended stable Windows 11 or Windows 10 build without hardcoding a release/build number;
- Windows 11 quick mode prefers a mainstream stable `YYH2` release over specialized H1 branches when appropriate;
- paginated catalog browsing;
- Preview/Insider entries hidden by default;
- dynamic language and edition metadata;
- one or multiple editions through the UUP dump converter's virtual-edition mechanism;
- `install.esd` and `install.wim` output;
- API, conversion-package, and UUP-file caching;
- normal `aria2` resume behavior for incomplete downloads;
- compact console progress with raw converter output kept in `converter-*.log`;
- structured elevated-process results;
- separate execution/elevated/converter/build logs;
- SHA-256 and JSON result metadata;
- ISO structure validation with `Mount-DiskImage` and DISM;
- interactive TUI and non-interactive PowerShell CLI;
- **Backend Contract v1** with JSON request/response files, NDJSON events, stable error codes, and a dedicated machine entry point.

## Quick start

1. Download the source or release ZIP and extract it.
2. Run `Start-Builder.cmd`.
3. Choose the normal catalog workflow or `Quick download latest Windows`.
4. Select language, editions, and image format.
5. Approve UAC before download and conversion begin.

Completed files are written to `output/`. The persistent work cache defaults to `C:\UUP-ISO-Work`.

## Requirements

- Windows 10 or Windows 11 x64 for an actual ISO build;
- Windows PowerShell 5.1 or PowerShell 7;
- administrator rights during download/conversion;
- at least 35–50 GB of free disk space;
- access to UUP dump and Microsoft Windows Update/CDN.

## Usage

Interactive mode collects parameters before requesting elevation. Quick mode uses the same reusable recommendation selector now exposed through the Backend Contract. No concrete Windows release/build number is fixed in production code.

During `uup_download_windows.cmd`, detailed `aria2`/converter output is not used as an API. One existing parser creates normalized progress state: the console renderer displays it to a human, while an optional structured event sink publishes DTOs when `EventFile` is configured. Raw output remains in `output/logs/converter-*.log`.

Repeated runs with the same build, language, and base edition reuse the existing work directory and normal `aria2` resume behavior.

## Commands

The existing non-interactive command remains supported:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1 `
  -NonInteractive `
  -Search 22H2 `
  -Architecture amd64 `
  -Language ru-ru `
  -Editions Core,Professional `
  -ImageFormat ESD
```

### Backend Contract

`Invoke-WibBackend.ps1` is a separate machine entry point and does not replace `Start-Builder.ps1`. Requests and responses use UTF-8 JSON files; optional stage/progress events use UTF-8 NDJSON.

Safe `GetVersion` example:

```powershell
@'
{
  "schemaVersion": 1,
  "requestId": "smoke-get-version",
  "command": "GetVersion",
  "arguments": {}
}
'@ | Set-Content -LiteralPath .\request.json -Encoding UTF8

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson

Get-Content .\response.json -Raw
```

Backend Contract v1 commands: `GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, and `ExecuteBuildPlan`. See [docs/BACKEND_CONTRACT_EN.md](docs/BACKEND_CONTRACT_EN.md).

## Architecture

The PowerShell backend remains the source of truth for UUP API access, BuildPlan, elevation, caching, and conversion. Backend Contract is an outer adapter over those functions, not a second backend. See [architecture](docs/ARCHITECTURE.md).

## Security

The tool does not disable antivirus protection, UAC, or system-wide PowerShell execution policy. Backend requests are untrusted input: commands are restricted to an allowlist, `Invoke-Expression` is not used, and JSON is never executed as code.

Do not publish complete UUP signed URLs, product keys, access tokens, or personal paths. See [SECURITY.md](SECURITY.md).

## Troubleshooting

Human workflows keep their existing detailed logs. Machine clients receive a stable `error.code`; frontend code must not classify errors by localized `error.message` text.

Check access to UUP dump/Microsoft CDN, free disk space, and the relevant `build-*.log`, `converter-*.log`, execution log, and elevated log.

## Build

Compilation is not required. Human entry points are `Start-Builder.cmd` and `Start-Builder.ps1`; the machine entry point is `Invoke-WibBackend.ps1`. The PowerShell module is under `src/WindowsISOBuilder/`.

## Testing

The project uses **local** Pester tests and PSScriptAnalyzer. GitHub Actions are not part of verification or release.

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\.psscriptanalyzer.psd1
```

Backend Contract tests mock catalog/build operations and do not download Windows. Real ISO builds remain separate end-to-end validation.

## Documentation

- [Backend Contract v1](docs/BACKEND_CONTRACT_EN.md)
- [Requirements](REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Implementation status](docs/IMPLEMENTATION_STATUS.md)
- [Source v4 migration](docs/SOURCE_V4_MIGRATION.md)
- [Changelog](CHANGELOG.md)
- [Release notes](docs/releases/)
- [Contributing](CONTRIBUTING.md)

## Credits

UUP dump provides catalog metadata and the conversion package. That package downloads Windows files from Microsoft Windows Update/CDN.

The project is not affiliated with Microsoft, does not distribute completed Windows ISO images, does not activate Windows, and does not bypass licensing.

## Limitations

- `0.2.1-alpha.1` is an early architectural release, not a stable version;
- GUI/WPF/WinUI, updater, USB/Rufus integration, queue/history/profiles, and a full cancellation subsystem are not implemented;
- Backend Contract v1 is not an HTTP network API; its transport uses local JSON/NDJSON files and a PowerShell process;
- complete error taxonomy and expanded preflight checks are deferred;
- UUP dump API/converter formats can change;
- a complete real-world matrix of Windows versions, languages, editions, and WIM/ESD combinations is not guaranteed.

## License

Windows ISO Builder's own code is distributed under the [MIT License](LICENSE). Windows, UUP dump, and third-party tools remain subject to their own licenses and terms.
