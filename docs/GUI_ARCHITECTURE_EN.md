# GUI architecture v0.3.0-alpha.1

## Purpose

`WindowsISOBuilder.Gui` is a thin WPF client over the existing PowerShell backend. It does not contain a second UUP/build workflow.

```text
WPF / MVVM
   │
BackendClient
   │ JSON files + process
   ▼
Invoke-WibBackend.ps1
   │
Backend Contract Schema v1
   ▼
PowerShell backend
```

## Stack

C#, WPF, .NET 10 (`net10.0-windows`), SDK-style projects, System.Text.Json, standard WPF resources/styles, and small in-repository MVVM infrastructure. No Electron, WebView foundation, Avalonia, MahApps, or MaterialDesignInXaml.

## Layers

`MainWindow` is limited to view-specific actions such as tab selection, the system folder picker, explicit activation of a selected Catalog row, clipboard/open-path actions, and close confirmation.

`MainViewModel` owns user-flow orchestration and UI state. Transport concerns stay in `Backend/`.

`ContractDtos.cs` defines strongly typed Backend Contract v1 DTOs.

`BackendClient` generates request IDs, creates per-operation app-owned transport directories named by an independent random GUID, serializes JSON, starts the public backend entry point, validates response/data/schema compatibility, and cleans only its owned transport directory. A caller-supplied requestId never determines a filesystem location.

`BackendProcessRunner` uses `ProcessStartInfo.ArgumentList`; no user-controlled shell command concatenation is used.

`NdjsonEventReader` tails appended bytes rather than decoding incomplete text eagerly. Bytes after the last newline are retained, including a split inside a multibyte UTF-8 character. Malformed completed telemetry, duplicate/out-of-order sequences, and unknown additive event types do not determine build success.

`BackendPathResolver` resolves packaged `Invoke-WibBackend.ps1` relative to the executable. An explicit root is accepted only when a caller deliberately supplies one, such as `--backend-root` in smoke/developer use. Ambient environment variables cannot replace executable backend code. Parent lookup exists only as a development fallback.

`GuiLogger` uses `%LOCALAPPDATA%\WindowsISOBuilder\logs` on a best-effort basis. Logger construction and writes cannot make the GUI fail; backend exception messages are not copied to the frontend log, URLs/product-key patterns are redacted, and backend failures are recorded by code/requestId.

## Startup handshake

`resolve backend → GetVersion → require response schema 1 + contractSchemaVersion 1 + buildPlanSchemaVersion 1 → Ready`.

ApplicationVersion is not used for compatibility. The displayed version comes from backend `GetVersion`.

Normal startup creates `MainWindow` explicitly only after the backend-smoke path has been excluded. `App.xaml` has no `StartupUri`, so `WindowsISOBuilder.exe --backend-smoke` stays headless.

## Request/event lifecycle

Each operation uses a unique requestId plus an independent `%TEMP%\WindowsISOBuilder\backend\<operation-guid>` transport directory. The entire owned transport lifecycle is wrapped in cleanup, including early serialization/write/process failures. Backend logs/cache/work/ISO are never transport cleanup targets.

A successful response with no `data` is treated as `INTERNAL_ERROR`. Final backend response remains authoritative for operation success/failure.

Build progress is backend-owned. The GUI consumes normalized stage/progress/speed fields and does not recompute overall progress. A 100% telemetry value does not complete the job.

## Quick and Catalog flows

Quick Mode: `GetRecommendedBuild → GetLanguages → GetEditions → CreateBuildPlan → RunPreflight → ExecuteBuildPlan`.

Catalog Mode: `SearchBuilds → highlight row → explicitly activate selected build → shared languages/editions/configuration/preflight/build flow`.

A single Catalog row click does not start metadata work. Double-click or the use-selected action synchronizes product/architecture and enters the common Quick flow. The GUI does not implement a recommendation engine or embedded language/edition catalog. Hiding servicing records is a display filter over the backend response.

## State and threading

Happy path: `Idle → LoadingBuild → LoadingLanguages → LoadingEditions → ReadyToPreflight → Preflighting → ReadyToBuild → Building → Completed`.

Failure/cancellation states include `PreflightFailed`, `Failed`, `Cancelling`, and `Cancelled`. If a cooperative CancelBuild request cannot be accepted/sent, `Cancelling → Building` is valid because the target build is still alive. Retry restores the state appropriate to the operation that failed.

Backend work and file I/O are async; WPF state updates resume on the UI synchronization context.

## Cancellation

Cancellation is `CancelBuild(targetRequestId, cacheDirectory)` followed by `Cancelling` until the target `ExecuteBuildPlan` reports terminal cancellation/failure. A failed cancellation request returns the UI to `Building` and does not allow close-over-active-build behavior.

The GUI never kills backend/aria2/DISM processes itself. Window-close cancellation uses the same protocol.

## UAC boundary

The GUI is `asInvoker`. The existing backend owns elevation. `ELEVATION_CANCELLED` is mapped as a normal structured error.

## Errors and logging

Backend classification uses only `error.code`. Stable schema/preflight/network/UUP/download/converter/DISM/ISO/elevation/cancellation/build codes have explicit user-facing mappings; unknown future v1 codes become a generic failure.

Technical details may show code/stage/backend message/log path/requestId to the local user. The GUI log intentionally stores less sensitive information and does not copy full backend messages/requests/signed URLs/tokens/product keys.

## Publishing

`tools/Build-Gui.ps1` restores, builds, tests, and publishes self-contained `win-x64`. Release builds suppress application PDB output, and `.pdb` is also denied by package safety policy.

Release staging puts the published GUI in the package root beside `Invoke-WibBackend.ps1`, while preserving `Start-Builder.cmd`, `Start-Builder.ps1`, and the PowerShell module. `.github`, tests, build outputs, and validation artifacts are not runtime package content. Installer/MSIX is outside v0.3.0.
