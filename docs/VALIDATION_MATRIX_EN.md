# Validation matrix v1.0.0

Implementation status and actual execution are separate. Manual/runtime checks remain **NOT RUN** until they are performed on the current SHA.

## Automated gates

For release-bound changes, the current head must pass:

- VERSION / GUI version / ModuleVersion / SchemaVersion consistency;
- `dotnet restore/build/test`;
- RU/EN localization key/placeholder parity;
- Pester main suite;
- network-policy persistence/default/invalid-state tests;
- Windows DPAPI credential round-trip/corruption/clear tests;
- Direct proxy bypass regression;
- Custom fail-closed/no-silent-Direct-fallback regression;
- generated-downloader loopback-only/credential command-line regression;
- diagnostic proxy-password redaction tests;
- update SemVer/channel/API/security tests through the policy-aware provider;
- PSScriptAnalyzer;
- PS5.1 backend/module/offline-preflight smoke;
- PowerShell 7 backend smoke when available;
- controlled process-tree cancellation smoke;
- self-contained GUI publish;
- release ZIP/checksum/manifest/package smoke;
- current tracked-tree/package safety scan;
- packaged GUI backend/startup smoke.

Main command:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

## v1.0.0 stable coverage

Automated coverage must confirm:

- root `VERSION` and GUI `<Version>` are `1.0.0`;
- GUI FileVersion/AssemblyVersion use numeric `1.0.0.0`;
- ModuleVersion remains `0.3.0`;
- Backend Contract SchemaVersion and BuildPlan SchemaVersion remain `1`;
- the GUI and backend reject a proxy password without a username;
- proxy configuration/credential/connection/authentication failures have user-facing action mappings;
- the release package source allowlist contains no denied paths;
- package/runtime safety scanning does not allow validation/test/local network artifacts.

## Manual GUI / network acceptance — NOT RUN until executed

| ID | Scenario | Steps | Expected | Actual | Status | Notes |
|---|---|---|---|---|---|---|
| MAN-GUI-001 | RU/EN Settings Network | Open the packaged GUI in RU and EN, then open Settings -> Network. | System/Direct/Custom, HTTP/SOCKS5, Host/Port/Username/Password, Save/Test/Clear render without clipping. | | NOT RUN | Requires the real packaged GUI. |
| MAN-GUI-002 | Light/Dark/System theme | Check Build/Catalog/Settings/Help/About in Light, Dark, and System theme. | Contrast is readable, disabled controls keep readable text, layout does not jump. | | NOT RUN | Includes resize smoke. |
| MAN-NET-001 | System connection | Select System and run Test connection. | Success or a controlled network error without a crash. | | NOT RUN | Requires a real network. |
| MAN-NET-002 | Direct connection | Select Direct and run Test connection. | Traffic bypasses proxies; inherited proxy variables do not affect the generated downloader. | | NOT RUN | Requires traffic/environment observation. |
| MAN-NET-003 | Custom HTTP proxy | Configure a working HTTP proxy, save, check restart/password state, and run Test connection. | PasswordBox is empty after restart; saved credential is indicated neutrally; Test connection succeeds through the proxy. | | NOT RUN | A real proxy is not replaced by mock tests. |
| MAN-NET-004 | Custom SOCKS5 proxy | Configure a working SOCKS5 proxy and run Test connection. | Test connection succeeds through the SOCKS5 policy. | | NOT RUN | A real proxy is not replaced by mock tests. |
| MAN-NET-005 | Broken Custom no fallback | Configure a broken Custom proxy. | Controlled proxy error; no silent Direct fallback. | | NOT RUN | Requires observing that Direct fallback did not occur. |
| MAN-UPD-001 | Update check | Check Stable/Prerelease updates through the selected policy. | Network failure does not break the app; the URL remains official `https://github.com/Regstar2/windows-iso-builder`. | | NOT RUN | External acceptance requires an available GitHub release channel. |
| MAN-ICON-001 | Explorer/taskbar icon | Check the exe, window, taskbar, publish output, and package output. | The existing `WindowsISOBuilder.ico` renders without replacing artwork. | | NOT RUN | Visual Windows Explorer/taskbar check. |
| MAN-E2E-001 | Full packaged GUI ISO E2E | Build a real ISO from the release ZIP through the GUI. | ISO is created, SHA-256 is shown, logs/result actions work. | | NOT RUN | Not inferred from automation PASS. |

## Controlled downloader/proxy acceptance — NOT RUN until executed

Run controlled HTTP-proxy and SOCKS5 tests with the generated `uup_download_windows.cmd`/aria2 path and verify that upstream credentials never appear in process command lines or logs.

## Safety scope

The built-in safety scan covers current tracked files and the current release package. It is **not a Git-history audit**. A separate full-history secret scan is required before a stable release.
