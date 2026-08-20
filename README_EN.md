<div align="center">

# Windows ISO Builder

A GUI and PowerShell UUP dump client for searching, downloading, and building Windows ISO images without manually handling UUIDs, SKUs, or `ConvertConfig.ini`.

[Русский](README.md) · **English**

</div>

## Status

Current release-train source version: **`0.3.3`**.

- ApplicationVersion: `0.3.3`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

The project is feature-frozen before its first public `v1.0.0`. After v0.3.3 only the v0.3.4 network/proxy milestone and RC hardening are planned. History/Profiles and unrelated features are deferred.

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
- sanitized diagnostics bundle;
- GitHub Issue Forms and in-app feedback;
- Stable/Prerelease update checking through official GitHub Releases.

## GUI quick start

1. Fully extract the release ZIP.
2. Run `WindowsISOBuilder.exe` as a normal user.
3. Choose Windows 11/10 and the recommended build, or open Catalog.
4. Choose language, editions, ESD/WIM and output directory.
5. Run readiness checks.
6. Choose Create ISO and approve UAC when the backend requests elevation.
7. On completion, open the ISO location or copy SHA-256.

The release is self-contained `win-x64`; users do not need a separate .NET Runtime.

## Updates

`Settings → Updates` provides Stable and Prerelease channels and a manual check of official GitHub Releases. Stable never selects a prerelease.

The application **does not automatically download or install updates**. When a newer version exists, it shows the version and bounded release-note summary and, with user consent, opens a validated HTTPS release page on `github.com`. This is the deliberate safe fallback for portable ZIP distribution.

While the source repository remains private, an unauthenticated external client may not be able to query its releases; external acceptance is performed after a public release channel exists.

## Feedback

About contains Report a bug and Request a feature actions that open GitHub Issue Forms in the browser without a PAT/OAuth token in the client. The diagnostics package is created separately in Settings and is never attached automatically.

Do not publish product keys, passwords, tokens, cookies, proxy credentials, private URLs, or unsanitized personal data. External feedback availability remains unverified while the tracker is private.

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

The PowerShell backend remains the only owner of UUP/build/elevation/cancellation behavior. The GUI communicates through Backend Contract v1.

The update checker uses only the official GitHub Releases endpoint without an Authorization secret and does not execute downloaded files. Requests and paths are untrusted; backend dispatch is allowlisted; GUI PowerShell launch uses safe process arguments; diagnostics/logging apply redaction.

See [architecture](docs/ARCHITECTURE.md), [Backend Contract](docs/BACKEND_CONTRACT_EN.md), [validation matrix](docs/VALIDATION_MATRIX_EN.md), [security](SECURITY.md), and [roadmap](docs/product/roadmap.md).

## Next required milestone

`v0.3.4 — Network Access & Proxy`: one System / Direct / Custom policy, HTTP/SOCKS5, and no silent Direct fallback. Custom proxy support is **not claimed** before that milestone is complete.

## License

Windows ISO Builder code is distributed under the [MIT License](LICENSE). Windows, UUP dump, and third-party tools retain their own licenses and terms.
