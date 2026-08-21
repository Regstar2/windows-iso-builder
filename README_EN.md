<div align="center">

# Windows ISO Builder

A GUI and PowerShell UUP dump client for searching, downloading, and building Windows ISO images without manually handling UUIDs, SKUs, or `ConvertConfig.ini`.

[Русский](README.md) · **English**

[![Version](https://img.shields.io/badge/VERSION-1.0.0-1f6feb?style=for-the-badge)](VERSION)
[![Windows](https://img.shields.io/badge/WINDOWS-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows11&logoColor=white)](REQUIREMENTS.md)
[![Architecture](https://img.shields.io/badge/ARCH-X64-7C3AED?style=for-the-badge)](REQUIREMENTS.md)
[![Build](https://github.com/Regstar2/windows-iso-builder/actions/workflows/windows-self-hosted-validation.yml/badge.svg?branch=master)](https://github.com/Regstar2/windows-iso-builder/actions/workflows/windows-self-hosted-validation.yml)
[![License](https://img.shields.io/badge/LICENSE-MIT-f97316?style=for-the-badge)](LICENSE)

[Quick start](#quick-start) · [Documentation](#documentation) · [Releases](https://github.com/Regstar2/windows-iso-builder/releases) · [Security](SECURITY.md)

</div>

## About

Windows ISO Builder helps build current Windows 10/11 ISO images through the dynamic UUP dump catalog. The GUI guides users through build selection, language, editions, image format, readiness checks, and the existing PowerShell build pipeline.

## Project status

Current stable version: **`1.0.0`**.

- ApplicationVersion: `1.0.0`;
- GUI Version/FileVersion: `1.0.0` / `1.0.0.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`v1.0.0` is the first stable release from the accepted `v0.3.5-rc.1`. It adds no new product features: the release finalizes the already implemented GUI, Network/Proxy, feedback/update, diagnostics, packaging, and validation capabilities.

## Features

- Windows 11 / Windows 10 through a dynamic UUP dump catalog without hardcoded build numbers;
- recommended build and full Catalog;
- dynamic languages/editions and multi-edition selection;
- WIM/ESD and existing converter options;
- structured preflight before UAC;
- progress, logs, cancellation, SHA-256 and result actions;
- WPF GUI with preserved TUI/CLI;
- RU/EN localization with English fallback;
- System/Light/Dark theme;
- one global Network Policy: System / Direct / Custom;
- Custom HTTP and SOCKS5 proxy support for UUP API, online preflight, conversion package acquisition, generated downloader/aria2, and GitHub update checks;
- Windows DPAPI CurrentUser protection for saved proxy passwords;
- fail-closed Custom mode with no silent Direct fallback;
- sanitized diagnostics bundle;
- GitHub Issue Forms and in-app feedback;
- Stable/Prerelease update checking through official GitHub Releases.

## Quick start

1. Download `windows-iso-builder-v1.0.0.zip` from [Releases](https://github.com/Regstar2/windows-iso-builder/releases).
2. Fully extract the ZIP.
3. Run `WindowsISOBuilder.exe` as a normal user.
4. If required, configure `Settings -> Network`: System, Direct, or Custom HTTP/SOCKS5.
5. Choose Windows 11/10 and the recommended build, or open Catalog.
6. Choose language, editions, ESD/WIM and output directory.
7. Run readiness checks.
8. Choose Create ISO and approve UAC when the backend requests elevation.
9. On completion, open the ISO location or copy SHA-256.

The release is self-contained `win-x64`; users do not need a separate .NET Runtime.

## Requirements

- Windows 10/11 x64;
- access to UUP dump and Microsoft CDN;
- enough disk space for UUP cache, work directory, and the ISO;
- UAC for the privileged build stage;
- no .NET Runtime installation for the release ZIP;
- .NET 10 SDK only when building from source.

## Network and proxy

One global policy applies to all supported outbound paths.

- **System** — use Windows/.NET system proxy behavior.
- **Direct** — explicitly bypass proxies; inherited `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` variables are cleared for the generated downloader.
- **Custom HTTP** — use the configured HTTP proxy.
- **Custom SOCKS5** — use SOCKS5 transport through the application's local loopback bridge.

For the generated UUP downloader/aria2 path, System and Custom are exposed only as an ephemeral loopback HTTP endpoint at `127.0.0.1:<port>`; upstream proxy host/user/password are not placed on the command line. A Custom proxy failure remains a proxy failure and never causes an implicit Direct retry.

Policy and credentials are stored separately. Proxy passwords are not written to `network.json`; they are protected with Windows DPAPI CurrentUser. Diagnostics additionally redact password/proxy-credential assignments and URLs.

## Updates

`Settings -> Updates` provides Stable and Prerelease channels and a manual check of official GitHub Releases. Stable never selects a prerelease. The update checker uses the same global Network Policy.

The application **does not automatically download or install updates**. When a newer version exists, it shows the version and bounded release-note summary and, with user consent, opens a validated HTTPS release page on `github.com`.

## Feedback

About contains Report a bug and Request a feature actions that open GitHub Issue Forms in the browser without a PAT/OAuth token in the client. The diagnostics package is created separately in Settings and is never attached automatically.

Do not publish product keys, passwords, tokens, cookies, proxy credentials, private URLs, or unsanitized personal data.

## Console / automation

```powershell
.\Start-Builder.cmd
```

Machine-readable entry point:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson
```

Network Policy is also exposed through the PowerShell API: `Get-WibNetworkPolicy`, `Set-WibNetworkPolicy`, `Clear-WibProxyCredential`, and `Test-WibNetworkConnection`.

## Development and release validation

GUI development requires the .NET 10 SDK.

```powershell
dotnet restore .\WindowsISOBuilder.sln
dotnet build .\WindowsISOBuilder.sln -c Release
dotnet test .\WindowsISOBuilder.sln -c Release --no-build
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Pull requests to `master` run the same Full validation on the owner-controlled Windows self-hosted runner. A PASS applies only to the exact tested SHA.

## Architecture and security

The PowerShell backend remains the only owner of UUP/build/elevation/cancellation behavior. The GUI communicates through Backend Contract v1. Network Policy is not stored in BuildPlan v1 and does not change Backend Contract SchemaVersion.

Requests and paths are untrusted; backend dispatch is allowlisted; GUI PowerShell launch uses safe process arguments; diagnostics/logging apply redaction. Invalid Custom proxy configuration or unavailable credentials fail closed.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [GUI architecture](docs/GUI_ARCHITECTURE_EN.md)
- [Backend Contract](docs/BACKEND_CONTRACT_EN.md)
- [Validation matrix](docs/VALIDATION_MATRIX_EN.md)
- [Requirements](REQUIREMENTS.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [Roadmap](docs/product/roadmap.md)

## Limitations

- There is no automatic self-update: the app only opens the official GitHub Release.
- Installer/MSIX, USB writer/Rufus integration, History/Profiles, Windows customization, debloat, unattended setup, driver injection, TPM bypass, activation, accounts/cloud sync, telemetry, and plugins are outside v1.0.0.
- Manual proxy acceptance, real ISO E2E, icon/taskbar/high-DPI visual checks keep separate statuses in the [validation matrix](docs/VALIDATION_MATRIX_EN.md) and are not inferred from automated PASS.

## License

Windows ISO Builder code is distributed under the [MIT License](LICENSE). Windows, UUP dump, and third-party tools retain their own licenses and terms.
