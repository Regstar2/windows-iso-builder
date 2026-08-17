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

The technical repository and root-directory name is `windows-iso-builder`. The public product name remains Windows ISO Builder.

The project does not replace UUP dump or implement a separate UUP engine. Its purpose is to turn the manual workflow into one interactive process.

## Project status

The current version is `0.1.0-alpha.1`. The code is in private alpha validation.

The static structure and modular architecture are prepared, but a complete ISO build has not yet been validated with real Windows 10 and Windows 11 builds. The project is not considered ready for a public stable release until those checks are completed.

## Features

- dynamic search by release name, build number, or UUP dump title;
- quick selection of the latest stable Windows 11 or Windows 10 x64 build without browsing the catalog and without hardcoding a release/build number;
- paginated browsing for large result sets, including next, previous, and direct page navigation;
- no fixed catalog of supported Windows versions in the source code;
- `x64`, `ARM64`, and `x86` filters, with Preview/Insider results hidden by default;
- dynamic language and edition lists for the selected build;
- one or multiple editions through the UUP dump converter's virtual-edition mechanism;
- `install.esd` or `install.wim` output;
- API, conversion-package, and UUP-file caching;
- resumable `aria2` downloads in a persistent work directory;
- logs, SHA-256, and JSON metadata for the result;
- ISO structure validation with `Mount-DiskImage` and DISM;
- interactive TUI and non-interactive PowerShell mode.

## Quick start

1. Extract the project to a local directory.
2. Run `Start-Builder.cmd`.
3. For the normal workflow choose `Find a build and create ISO`; for the latest stable release choose `Quick download latest Windows`.
4. In quick mode choose Windows 11 or Windows 10. The application refreshes the catalog and automatically selects the latest stable x64 build.
5. Select language, editions, and image format.
6. Approve UAC before downloading and conversion begin.

Windows 8.1/8 and Windows 7 are not built by the current UUP pipeline. Their quick-menu entries are reserved for a future separate verified source.

Completed files are written to `output/`. The persistent work cache defaults to `C:\UUP-ISO-Work`.

## Requirements

- Windows 10 or Windows 11 x64;
- Windows PowerShell 5.1 or PowerShell 7;
- administrator rights during download and conversion;
- at least 35–50 GB of free disk space;
- access to UUP dump and Microsoft Windows Update/CDN.

## Usage

In interactive mode, the program collects all parameters before requesting elevation. The selection can therefore be cancelled or changed before a long-running operation starts.

Quick mode skips manual catalog browsing. For Windows 11 or Windows 10 it requests a fresh UUP dump catalog, keeps only stable complete x64 Windows builds, and uses the same relevance-ranking logic as the normal catalog. No release or build number is fixed in the source. After the build is selected automatically, the user still chooses language, editions, WIM/ESD, and optional build settings.

The catalog distinguishes complete Windows build entries from servicing packages. `.NET`, cumulative, OOBE, and similar servicing records are hidden by default so they cannot be selected accidentally as ISO sources. The sort menu includes an `Entry type` option and places complete Windows builds before updates. This classification does not guarantee that Microsoft still retains the UUP files for a particular old build.

A repeated run with the same build, language, and base edition uses the existing work directory. `aria2` verifies downloaded files and resumes incomplete transfers when supported by the server.

The result table supports `S` to sort by relevance, build, architecture, date, entry type, or title and `F` to select the current installable build. Relevance compares the Windows release label first (for example, 22H2 is newer than 21H2 and 1809) and then chooses the highest build inside that release. This prevents an older LTSC branch with a newer servicing date or an old development build with a larger base number from being treated as the current release. Type sorting can place complete Windows builds or servicing packages first. The selected sort order is preserved while paging through results.

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

After an error, the program keeps a log and displays its location. Check:

1. access to UUP dump and Microsoft CDN;
2. free space on the system and work drives;
3. whether antivirus software blocked `aria2`, DISM, or the converter;
4. the log for the failed run.

## Build

The project does not require compilation. Run the source through `Start-Builder.cmd` or `Start-Builder.ps1`. The PowerShell module is stored in `src/WindowsISOBuilder/`.

## Testing

The repository contains Pester tests and a PSScriptAnalyzer configuration. Checks are run locally; GitHub Actions are not required for this project:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\.psscriptanalyzer.psd1
```

A complete real ISO build remains a separate manual validation step and is not considered verified solely because the unit tests pass.

## Documentation

- [Requirements](REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Implementation status](docs/IMPLEMENTATION_STATUS.md)
- [Source v4 migration](docs/SOURCE_V4_MIGRATION.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)

## Contributing

Changes should be made in a dedicated branch and submitted through a pull request. Before publication, verify PowerShell 5.1 compatibility, the absence of a fixed Windows release catalog, and that user-facing claims match completed tests.

## Credits

UUP dump supplies the catalog, metadata, and conversion package. That package downloads Windows files from Microsoft Windows Update/CDN.

This project is not affiliated with Microsoft, does not distribute completed ISO images, does not activate Windows, and does not bypass licensing.

## Limitations

- the complete build workflow has not yet been validated on Windows 10 and Windows 11;
- quick UUP mode currently supports Windows 10 and Windows 11; Windows 8.1/8 and Windows 7 require a separate source;
- virtual-edition compatibility depends on the selected base edition and UUP dump converter version;
- the external API and conversion-package format may change;
- there is no GUI or automatic application updater;
- non-interactive mode cannot select a UUID directly yet.

## License

No public license has been selected. Until a `LICENSE` file is added, the source code should not be treated as freely redistributable or reusable.
