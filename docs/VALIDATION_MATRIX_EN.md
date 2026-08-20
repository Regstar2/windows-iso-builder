# Validation matrix v0.3.3

Implementation status and actual execution are separate. Manual/runtime checks remain **NOT RUN** until they are performed on the current SHA.

## Automated gates

Before merge the current head must cover/pass, as applicable:

- VERSION / GUI version / ModuleVersion / SchemaVersion consistency;
- `dotnet restore/build/test`;
- update SemVer/channel/API/security tests;
- RU/EN localization key/placeholder parity;
- Pester main suite;
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

## v0.3.3 update coverage

Automated coverage must include installed == latest, newer release, installed newer than latest, Stable filtering prereleases, Prerelease selection, malformed/missing tags, no Authorization header, HTTPS github.com release URL validation, network/timeout failures, persisted channel and Stable default.

## Manual GUI acceptance — NOT RUN until executed

On the packaged build, in RU and EN, verify Settings update controls, offline/error behavior, update-available messaging/release-notes summary, decline path, official release-page opening, and About feedback actions.

Feedback links are not considered externally accepted while the target tracker is private/inaccessible to target users.

## Core regression

The existing Build/Catalog/theme/DPI/keyboard manual smoke and a final real packaged GUI ISO E2E remain stable-release gates. v0.3.3 does not replace them.

## Safety scope

The built-in safety scan covers the current tracked tree and current release package. It is **not a Git-history audit**. A separate full-history secret scan is required before the public stable release.
