# Validation matrix v0.3.4

Implementation status and actual execution are separate. Manual/runtime checks remain **NOT RUN** until they are performed on the current SHA.

## Automated gates

Before merge the current head must cover/pass, as applicable:

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
- current-tree/package safety scan;
- packaged GUI backend/startup smoke.

Main command:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

## v0.3.4 Network/Proxy coverage

Automated coverage must confirm:

- missing policy → System;
- corrupted/invalid Custom policy → controlled failure;
- credentials are stored separately from `network.json` and protected with DPAPI;
- corrupted credential → controlled failure;
- Direct bypasses proxy adapters and clears inherited downloader proxy variables;
- a Custom HTTP failure is not retried as Direct;
- UUP API, online preflight, conversion package, and generated downloader use the common policy layer;
- generated-downloader command lines contain only the loopback endpoint and no upstream proxy host/user/password;
- diagnostics redact password/proxy-credential assignments;
- GUI update checks use the policy-aware `IHttpClientProvider`.

## Manual GUI / network acceptance — NOT RUN until executed

On a packaged build, in RU and EN, verify the Network Settings card, System/Direct/Custom switching, HTTP/SOCKS5 validation, password non-disclosure after restart, save/replace/clear behavior, Test connection for all modes, controlled failure for a broken Custom proxy with no Direct fallback, and policy use by GitHub update checks and Build/Catalog online operations.

## Controlled downloader/proxy acceptance — NOT RUN until executed

Run controlled HTTP-proxy and SOCKS5 tests with the generated `uup_download_windows.cmd`/aria2 path and verify that upstream credentials never appear in process command lines or logs.

## Core regression

The existing Build/Catalog/theme/DPI/keyboard manual smoke and one final real packaged GUI ISO E2E remain public-release gates. A real ISO build through each proxy mode is not a PASS until it is actually executed.

## Safety scope

The built-in safety scan covers the current tracked tree and current release package. It is **not a Git-history audit**. A separate full-history secret scan is required before the public release.
