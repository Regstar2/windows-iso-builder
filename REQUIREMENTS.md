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
6. Safe process arguments via `ProcessStartInfo.ArgumentList`; Windows PowerShell host resolves deterministically from the Windows system directory rather than PATH search order.
7. Strongly typed System.Text.Json DTOs; unknown optional properties and additive event types must not crash the GUI.
8. Startup handshake: locate backend → `GetVersion` → require Backend Contract SchemaVersion `1` **and** BuildPlan SchemaVersion `1` → ready.
9. Packaged backend path is deterministic relative to the executable. Explicit dev/test override may be used only when deliberately supplied by the caller; ambient environment variables must not replace executable backend code.
10. Request/response/event transport uses per-operation app-owned temp directories whose names are independent from requestId and does not delete build logs/cache/work/ISO.
11. Successful Backend Contract responses must contain the required command payload; malformed nested build/plan/preflight/result data is a controlled protocol error, not a partially valid GUI state.

## User flows

Quick Mode:

`GetRecommendedBuild → GetLanguages → GetEditions → CreateBuildPlan → RunPreflight → ExecuteBuildPlan`.

Catalog Mode:

`SearchBuilds → selected build → explicit activation → GetLanguages → GetEditions → shared build flow`.

Recommendation, language and edition catalogs must remain backend-owned and dynamic. Merely highlighting a Catalog row must not start metadata requests.

## Preflight

GUI renders `ready` and structured checks (`status`, `severity`, `code`, `data`). `ready=false` disables ExecuteBuildPlan. Warning severity must remain distinct from fatal failures. Retry is supported.

Output/cache directory creation, writability and disk-space checks belong to backend preflight. GUI must not pre-create the output directory in a way that converts `PATH_NOT_WRITABLE` into an unrelated frontend exception.

## Progress and events

The NDJSON reader tails incrementally at byte level, keeps incomplete trailing data including a split inside a multibyte UTF-8 character, handles UTF-8 strictly, ignores malformed completed telemetry, unsupported event schemas, duplicate/out-of-order sequence telemetry and unknown additive event types, and updates WPF state asynchronously.

Overall progress/speed come from backend event fields; the final Backend response is the completion source of truth.

## Cancellation

GUI sends `CancelBuild(targetRequestId, cacheDirectory)` and waits for target `BUILD_CANCELLED`/cancelled/final response semantics. It must not use `Process.Kill`, `taskkill`, `Stop-Process`, kill-by-name, or directly terminate aria2/DISM/backend trees.

Closing the GUI during an active build must explicitly offer to continue or cancel-and-exit; cancel-and-exit uses the same backend cancellation contract. If CancelBuild cannot be sent/accepted, the GUI remains open and returns to the active-build state.

## Error handling

Classification uses `error.code`, never localized message matching. Known stable codes get user-friendly titles/actions; unknown v1 codes map to a generic failure. Technical details may show sanitized code/stage/backend message/log path/request correlation but not secrets or giant stack traces by default.

## Security/logging

GUI log location: `%LOCALAPPDATA%\WindowsISOBuilder\logs` when available. Logging is best-effort and must never prevent application startup or crash a GUI operation.

Log command names, request IDs, state transitions, version/schema state and frontend exception type/message after sanitization. Do not log signed UUP URLs, tokens, product keys, secrets or arbitrary full request payloads. Backend exceptions are logged by stable code/requestId rather than copying arbitrary backend messages.

## Testing

C# tests cover DTO/envelopes, compatibility with unknown fields/codes/types, request generation/serialization, safe/deterministic process launch, deterministic backend path resolution, error mapping, state behavior and NDJSON tailing including partial lines/duplicates/UTF-8 splits/schema guards.

The C# test project is explicitly an MSTest project and includes `Microsoft.NET.Test.Sdk`; `dotnet test` must discover and execute the tests rather than only compiling them.

A Windows integration smoke may invoke real `Invoke-WibBackend.ps1` only for safe operations such as `GetVersion` and offline preflight; it must not download Windows or request UAC.

Existing Pester/PowerShell validation remains mandatory.

## Publish/package

Release GUI: `win-x64`, `self-contained=true`. Reliability is preferred over single-file packaging. The package keeps `Start-Builder.cmd`, `Start-Builder.ps1`, `Invoke-WibBackend.ps1` and PowerShell backend.

Release configuration does not publish GUI PDB files; `.pdb` is also forbidden by package safety policy.

Package-only `release-manifest.json` includes additive:

```json
"gui": { "included": true, "runtime": "win-x64", "selfContained": true }
```

Full validation fails if GUI build/test/publish or packaged GUI backend handshake fails.

## Self-hosted validation

`.github/workflows/windows-self-hosted-validation.yml` may orchestrate the existing `Invoke-ReleaseValidation.ps1 -Full` on the owner-controlled Windows self-hosted runner. It is development/release infrastructure, not product runtime functionality.

The self-hosted workflow must use least-privilege repository permissions, avoid persisted checkout credentials, reject fork-PR execution on the owner-controlled runner, pin validation module versions, restore temporary PowerShell repository policy changes, cancel superseded PR validations, and keep `.github`/validation artifacts out of the release ZIP.

A PASS from an older commit does not validate the current PR head.

## Out of scope

History, profiles, queue, cache-management GUI, updater, installer/MSIX, USB writer/Rufus, full theme/language settings, account/cloud features, Windows customization/debloat, drivers, TPM bypass, activation, custom UUP downloader/converter, hosted CI as a replacement for the owner-controlled Windows validation environment, and automated real-ISO/UAC E2E builds.
