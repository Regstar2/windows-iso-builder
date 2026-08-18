# Требования к Windows ISO Builder v0.3.0-alpha.1

## Версионирование

- ApplicationVersion: `0.3.0-alpha.1`; source of truth — root `VERSION`.
- ModuleVersion: `0.3.0`.
- Backend Contract SchemaVersion: `1`.
- BuildPlan SchemaVersion: `1`.

GUI получает user-visible ApplicationVersion через backend `GetVersion`. Contract/BuildPlan schema не повышаются: GUI использует существующий v1 без breaking change.

## Runtime requirements

Пользовательский release рассчитан на Windows x64 и публикуется как self-contained `win-x64`, поэтому отдельный .NET Runtime не требуется.

Backend сохраняет требования Windows PowerShell 5.1, Windows servicing tools, доступ к UUP dump/Microsoft Windows Update CDN, достаточный disk space и UAC approval для privileged build stage.

GUI запускается без administrator manifest (`asInvoker`).

## Development requirements

Для разработки/validation GUI требуется .NET 10 SDK. SDK автоматически не устанавливается.

Поддерживаемые команды:

```powershell
dotnet restore .\WindowsISOBuilder.sln
dotnet build .\WindowsISOBuilder.sln -c Release
dotnet test .\WindowsISOBuilder.sln -c Release --no-build
powershell.exe -File .\tools\Build-Gui.ps1
```

## GUI architecture requirements

1. C#, WPF, `net10.0-windows`, SDK-style project.
2. No Electron/WebView UI and no heavy third-party UI framework.
3. Backend communication only through `Invoke-WibBackend.ps1` + Backend Contract Schema v1.
4. No direct module/private function calls, no parsing human console text and no duplicated UUP/conversion/preflight/cancellation engine.
5. All backend operations asynchronous from the UI thread.
6. Safe process arguments via `ProcessStartInfo.ArgumentList`.
7. Strongly typed System.Text.Json DTOs; unknown optional properties and additive event types must not crash the GUI.
8. Startup handshake: locate backend → `GetVersion` → require contract schema 1 → ready.
9. Packaged backend path is deterministic relative to the executable. Dev override may be used only for development/testing.
10. Request/response/event transport uses per-operation app-owned temp directories and does not delete build logs/cache/work/ISO.

## User flows

Quick Mode:

`GetRecommendedBuild → GetLanguages → GetEditions → CreateBuildPlan → RunPreflight → ExecuteBuildPlan`.

Catalog Mode:

`SearchBuilds → selected build → GetLanguages → GetEditions → shared build flow`.

Recommendation, language and edition catalogs must remain backend-owned and dynamic.

## Preflight

GUI renders `ready` and structured checks (`status`, `severity`, `code`, `data`). `ready=false` disables ExecuteBuildPlan. Warning severity must remain distinct from fatal failures. Retry is supported.

## Progress and events

The NDJSON reader tails incrementally, keeps incomplete trailing data, handles UTF-8, ignores duplicate/out-of-order sequence telemetry and unknown additive event types, and updates WPF state asynchronously.

Overall progress/speed come from backend event fields; the final Backend response is the completion source of truth.

## Cancellation

GUI sends `CancelBuild(targetRequestId, cacheDirectory)` and waits for target `BUILD_CANCELLED`/cancelled/final response semantics. It must not use `Process.Kill`, `taskkill`, `Stop-Process`, kill-by-name, or directly terminate aria2/DISM/backend trees.

Closing the GUI during an active build must explicitly offer to continue or cancel-and-exit; cancel-and-exit uses the same backend cancellation contract.

## Error handling

Classification uses `error.code`, never localized message matching. Known codes get user-friendly titles/actions; unknown v1 codes map to a generic failure. Technical details may show code/stage/backend message/log path/request correlation but not secrets or giant stack traces by default.

## Security/logging

GUI log location: `%LOCALAPPDATA%\WindowsISOBuilder\logs`. Log startup/backend path/version, command names, request IDs, state transitions and frontend exceptions. Do not log signed UUP URLs, tokens, product keys, secrets or arbitrary full request payloads.

## Testing

C# tests cover DTO/envelopes, compatibility with unknown fields/codes/types, request generation/serialization, safe process arguments, backend path resolution, error mapping, state behavior and NDJSON tailing including partial lines/duplicates/UTF-8.

A Windows integration smoke may invoke real `Invoke-WibBackend.ps1` only for safe operations such as `GetVersion`; it must not download Windows or request UAC.

Existing Pester/PowerShell validation remains mandatory.

## Publish/package

Release GUI: `win-x64`, `self-contained=true`. Reliability is preferred over single-file packaging. The package keeps `Start-Builder.cmd`, `Start-Builder.ps1`, `Invoke-WibBackend.ps1` and PowerShell backend.

Package-only `release-manifest.json` includes additive:

```json
"gui": { "included": true, "runtime": "win-x64", "selfContained": true }
```

Full validation fails if GUI build/test/publish or packaged GUI backend handshake fails.

## Out of scope

History, profiles, queue, cache-management GUI, updater, installer/MSIX, USB writer/Rufus, full theme/language settings, account/cloud features, Windows customization/debloat, drivers, TPM bypass, activation, custom UUP downloader/converter and GitHub Actions.
