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
3. Select the search-and-build option.
4. Enter a query such as `22H2` or `19045`.
5. Select the build, architecture, language, editions, and format.
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

A repeated run with the same build, language, and base edition uses the existing work directory. `aria2` verifies downloaded files and resumes incomplete transfers when supported by the server.

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

This mode selects the first matching entry after sorting by build number and date. Direct UUID selection is not implemented yet.

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

The repository contains Pester tests and a PSScriptAnalyzer configuration:

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
```

CI is configured for Windows PowerShell 5.1 and PowerShell 7. These checks and a complete ISO build were not executed in the current environment; their presence in the repository does not prove that they pass.

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
- virtual-edition compatibility depends on the selected base edition and UUP dump converter version;
- the external API and conversion-package format may change;
- there is no GUI or automatic application updater;
- non-interactive mode cannot select a UUID directly yet.

## License

No public license has been selected. Until a `LICENSE` file is added, the source code should not be treated as freely redistributable or reusable.
