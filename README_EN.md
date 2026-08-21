<div align="center">

# Windows ISO Builder

A GUI and PowerShell UUP dump client for searching, downloading, and building Windows ISO images without manually handling UUIDs, SKUs, or `ConvertConfig.ini`.

[Русский](README.md) · **English**

[![Version](https://img.shields.io/badge/VERSION-0.3.5--rc.1-1f6feb?style=for-the-badge)](VERSION)
[![Windows](https://img.shields.io/badge/WINDOWS-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows11&logoColor=white)](REQUIREMENTS.md)
[![Architecture](https://img.shields.io/badge/ARCH-X64-7C3AED?style=for-the-badge)](REQUIREMENTS.md)
[![Build](https://github.com/Regstar2/windows-iso-builder/actions/workflows/windows-self-hosted-validation.yml/badge.svg?branch=master)](https://github.com/Regstar2/windows-iso-builder/actions/workflows/windows-self-hosted-validation.yml)
[![License](https://img.shields.io/badge/LICENSE-MIT-f97316?style=for-the-badge)](LICENSE)

[Quick start](#gui-quick-start) · [Documentation](#architecture-and-security) · [Releases](https://github.com/Regstar2/windows-iso-builder/releases)

</div>

## Status

Current release-train source version: **`0.3.5-rc.1`**.

- ApplicationVersion: `0.3.5-rc.1`;
- GUI Version/FileVersion: `0.3.5-rc.1` / `0.3.5.1`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

The project is in final RC hardening before its first public release. v0.3.5-rc.1 adds no product features: the v0.3.4 Network/Proxy scope is preserved, and this branch covers only final polish, metadata, packaging/security audit, and release validation. History/Profiles and unrelated product features remain deferred.

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

## GUI quick start

1. Fully extract the release ZIP.
2. Run `WindowsISOBuilder.exe` as a normal user.
3. If required, configure `Settings → Network`: System, Direct, or Custom HTTP/SOCKS5.
4. Choose Windows 11/10 and the recommended build, or open Catalog.
5. Choose language, editions, ESD/WIM and output directory.
6. Run readiness checks.
7. Choose Create ISO and approve UAC when the backend requests elevation.
8. On completion, open the ISO location or copy SHA-256.

The release is self-contained `win-x64`; users do not need a separate .NET Runtime.

## Network and proxy

One global policy applies to all supported outbound paths.

- **System** — use Windows/.NET system proxy behavior.
- **Direct** — explicitly bypass proxies; inherited `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` variables are cleared for the generated downloader.
- **Custom HTTP** — use the configured HTTP proxy.
- **Custom SOCKS5** — use SOCKS5 transport through the application's local loopback bridge.

For the generated UUP downloader/aria2 path, System and Custom are exposed only as an ephemeral loopback HTTP endpoint at `127.0.0.1:<port>`; upstream proxy host/user/password are not placed on the command line. A Custom proxy failure remains a proxy failure and never causes an implicit Direct retry.

Policy and credentials are stored separately. Proxy passwords are not written to `network.json`; they are protected with Windows DPAPI CurrentUser. Diagnostics additionally redact password/proxy-credential assignments and URLs.

## Updates

`Settings → Updates` provides Stable and Prerelease channels and a manual check of official GitHub Releases. Stable never selects a prerelease. The update checker uses the same global Network Policy.

The application **does not automatically download or install updates**. When a newer version exists, it shows the version and bounded release-note summary and, with user consent, opens a validated HTTPS release page on `github.com`.

While the source repository remains private, an unauthenticated external client may not be able to query its releases; external acceptance is performed after a public release channel exists.

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

See [architecture](docs/ARCHITECTURE.md), [Backend Contract](docs/BACKEND_CONTRACT_EN.md), [validation matrix](docs/VALIDATION_MATRIX_EN.md), [security](SECURITY.md), and [roadmap](docs/product/roadmap.md).

## Next required stage

Accept or reject the RC. Before public v1.0.0, only release actions and factual checks remain: manual Network/Proxy acceptance, a final packaged GUI ISO E2E, public feedback/update-channel accessibility, and the full Git-history secret audit.

## License

Windows ISO Builder code is distributed under the [MIT License](LICENSE). Windows, UUP dump, and third-party tools retain their own licenses and terms.
