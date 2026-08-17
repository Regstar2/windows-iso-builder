<div align="center">

# Windows ISO Builder

An interactive UUP dump client for searching, downloading, and building Windows ISO images without manually using the website, copying UUIDs, knowing SKU values, or editing `ConvertConfig.ini`.

[Русский](README.md) · **English**

[Quick start](#quick-start) ·
[Documentation](#documentation) ·
[Limitations](#limitations)

</div>

## About

Windows ISO Builder guides the user through searching for a Windows build and selecting the architecture, language, editions, and installation-image format. The source code does not contain a fixed release catalog: metadata comes from UUP dump, while Windows payload files are downloaded from Microsoft Windows Update/CDN.

The technical repository and root-directory name is `windows-iso-builder`. The public product name is Windows ISO Builder.

The project does not replace UUP dump or implement a separate UUP engine. Its purpose is to turn the manual workflow into one interactive process.

## Project status

The current version is **`0.2.0-alpha.1`**.

This is a public alpha: the main workflow is implemented, local automated checks pass, and a real Windows 11 x64 ru-ru end-to-end build has been confirmed through a completed ISO. The project is not presented as a stable release and does not claim that every Windows version, edition, and parameter combination has been manually validated.

See [implementation status](docs/IMPLEMENTATION_STATUS.md) for the detailed validation matrix.

## Features

- dynamic search by release name, build number, or UUP dump title;
- quick selection of a recommended stable Windows 11 or Windows 10 x64 build without browsing the catalog and without hardcoding a release/build number;
- Windows 11 quick mode prefers a mainstream stable `YYH2` release over specialized H1 branches when a suitable H2 release is available;
- paginated browsing for large result sets, including next, previous, and direct page navigation;
- no fixed catalog of supported Windows versions in the source code;
- `x64`, `ARM64`, and `x86` filters, with Preview/Insider results hidden by default;
- dynamic language and edition lists for the selected build;
- one or multiple editions through the UUP dump converter's virtual-edition mechanism;
- `install.esd` or `install.wim` output;
- API, conversion-package, and UUP-file caching;
- reuse of already downloaded files and normal `aria2` resume behavior for incomplete downloads;
- a compact download/conversion progress bar instead of continuously printing `aria2` output; full converter output is stored in `converter-*.log`;
- structured elevated-process results instead of reducing failures to a generic `Exit code: 1`;
- separate execution/elevated/converter/build logs;
- SHA-256 and JSON metadata for the result;
- ISO structure validation with `Mount-DiskImage` and DISM;
- interactive TUI and non-interactive PowerShell mode.

## Quick start

1. Download the source or release ZIP and extract it to a local directory.
2. Run `Start-Builder.cmd`.
3. For the normal workflow choose `Find a build and create ISO`; for a recommended stable release choose `Quick download latest Windows`.
4. In quick mode choose Windows 11 or Windows 10. The application refreshes the catalog and automatically selects a recommended stable x64 build.
5. Select language, editions, and image format.
6. Approve UAC before downloading and conversion begin.

Completed files are written to `output/`. The persistent work cache defaults to `C:\UUP-ISO-Work`.

## Requirements

- Windows 10 or Windows 11 x64;
- Windows PowerShell 5.1 or PowerShell 7;
- administrator rights during download and conversion;
- at least 35–50 GB of free disk space;
- access to UUP dump and Microsoft Windows Update/CDN.

## Usage

In interactive mode, the program collects all parameters before requesting elevation. The selection can therefore be cancelled or changed before a long-running operation starts.

Quick mode skips manual catalog browsing. For Windows 11 or Windows 10 it requests a fresh UUP dump catalog, keeps only stable complete x64 Windows builds, and selects a recommended option dynamically. No concrete release or build number is fixed in production code.

For Windows 11, a mainstream stable H2 release is preferred over a specialized H1 release with a larger version number. If no suitable H2 release exists, the application falls back to the best stable complete build and displays a warning.

While `uup_download_windows.cmd` runs, detailed `aria2` and converter lines are no longer continuously printed to the console. The application shows one updating progress bar with the current stage, download percentage, and speed when available. Full raw converter output is stored next to the build log in `output/logs/converter-*.log`.

The catalog distinguishes complete Windows build entries from servicing packages. `.NET`, cumulative, OOBE, and similar servicing records are hidden by default so they cannot be selected accidentally as ISO sources.

A repeated run with the same build, language, and base edition uses the existing work directory. `aria2` verifies downloaded files and uses its normal mechanisms to continue incomplete downloads. A dedicated forced network-interruption test is not a release gate for `0.2.0-alpha.1`.

## Commands

Non-interactive example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1 `
  -NonInteractive `
  -Search 22H2 `
  -Architecture amd64 `
  -Language ru-ru `
  -Editions Core,Professional `
  -ImageFormat ESD
```

When matching entries exist, this mode prefers a complete Windows build over cumulative/.NET/OOBE servicing packages. Direct UUID selection is not implemented yet.

## Architecture

The PowerShell module separates API access, caching, parameter selection, build-plan creation, and converter execution. See the [architecture document](docs/ARCHITECTURE.md) for details.

## Security

The program must not disable antivirus protection, UAC, or the machine-wide PowerShell execution policy. The UUP dump package is executed only after its ZIP structure has been validated and is extracted into a tool-owned work directory.

Public reports must not contain complete UUP URLs, product keys, tokens, or personal paths. See [SECURITY.md](SECURITY.md) for vulnerability reporting guidance.

## Troubleshooting

After an error, the program keeps logs and displays their locations. Check:

1. access to UUP dump and Microsoft CDN;
2. free space on the system and work drives;
3. whether antivirus software blocked `aria2`, DISM, or the converter;
4. the run's `build-*.log`, `converter-*.log`, execution log, and elevated-process log.

## Build

The project does not require compilation. Run the source through `Start-Builder.cmd` or `Start-Builder.ps1`. The PowerShell module is stored in `src/WindowsISOBuilder/`.

## Testing

The project uses **local** Pester tests and PSScriptAnalyzer. GitHub Actions are not part of the verification or release process.

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\.psscriptanalyzer.psd1
```

Local tests validate logic and compatibility but do not replace a real ISO build. For `0.2.0-alpha.1`, a real Windows 11 end-to-end scenario is confirmed; Windows 10 and a complete WIM/ESD manual matrix are not required alpha release gates.

## Documentation

- [Requirements](REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Implementation status](docs/IMPLEMENTATION_STATUS.md)
- [Source v4 migration](docs/SOURCE_V4_MIGRATION.md)
- [Changelog](CHANGELOG.md)
- [Release notes](docs/releases/)
- [Contributing](CONTRIBUTING.md)

## Credits

UUP dump supplies the catalog, metadata, and conversion package. That package downloads Windows files from Microsoft Windows Update/CDN.

This project is not affiliated with Microsoft, does not distribute completed Windows ISO images, does not activate Windows, and does not bypass licensing.

## Limitations

- `0.2.0-alpha.1` is an early release, not a stable version;
- a Windows 10 end-to-end build is not part of this alpha's mandatory validation;
- a dedicated forced network-interruption recovery test was not performed as a release gate;
- WIM and ESD are supported, but a complete manual matrix of both formats is not a release gate;
- virtual-edition compatibility depends on the selected base edition and UUP dump converter version;
- the external API and conversion-package format may change;
- there is no GUI or automatic application updater;
- non-interactive mode cannot select a UUID directly yet.

## License

Windows ISO Builder's own code is distributed under the [MIT License](LICENSE).

Windows, UUP dump, and third-party tools remain subject to their own licenses and terms. This repository's MIT License does not grant rights to Microsoft components or third-party files that may be downloaded while the tool is running.
