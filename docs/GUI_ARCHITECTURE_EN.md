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

`MainWindow` is limited to view-specific actions such as tab selection, the system folder picker, clipboard/open-path actions, and close confirmation.

`MainViewModel` owns user-flow orchestration and UI state. Transport concerns stay in `Backend/`.

`ContractDtos.cs` defines strongly typed Backend Contract v1 DTOs.

`BackendClient` generates request IDs, creates per-operation app-owned temporary transport files, starts the public backend entry point, reads the final response, and cleans only transport files.

`BackendProcessRunner` uses `ProcessStartInfo.ArgumentList`; no user-controlled shell command concatenation is used.

`NdjsonEventReader` incrementally tails UTF-8 NDJSON, retains an incomplete last line, and ignores duplicate/out-of-order sequence telemetry.

`BackendPathResolver` resolves packaged `Invoke-WibBackend.ps1` relative to the executable; `--backend-root`/`WIB_BACKEND_ROOT` and parent lookup are development-only fallbacks.

## Startup handshake

`resolve backend → GetVersion → require contractSchemaVersion == 1 → Ready`.

ApplicationVersion is not used for compatibility. The displayed version comes from backend `GetVersion`.

## Request/event lifecycle

Each operation uses a unique `%TEMP%\WindowsISOBuilder\backend\<requestId>` transport directory. Metadata transport is removed after the final response. Build event transport remains available while the build runs and is removed only after final response processing. Backend logs/cache/work/ISO are never transport cleanup targets.

Build progress is backend-owned. The GUI consumes normalized stage/progress/speed fields and does not recompute overall progress. A 100% telemetry value does not complete the job; the final backend response is authoritative.

## Quick and Catalog flows

Quick Mode: `GetRecommendedBuild → GetLanguages → GetEditions → CreateBuildPlan → RunPreflight → ExecuteBuildPlan`.

Catalog Mode: `SearchBuilds → select build → shared languages/editions/configuration/preflight/build flow`.

The GUI does not implement a recommendation engine or embedded language/edition catalog. Hiding servicing records is a display filter over the backend response.

## State and threading

The view model uses explicit idle/loading/preflight/build/cancel/completed/failed states. Backend work and file I/O are async; WPF state updates resume on the UI synchronization context.

## Cancellation

Cancellation is `CancelBuild(targetRequestId, cacheDirectory)` followed by a `Cancelling` state until the target `ExecuteBuildPlan` reports terminal cancellation/failure. The GUI never kills backend/aria2/DISM processes itself. Window-close cancellation uses the same protocol.

## UAC boundary

The GUI is `asInvoker`. The existing backend owns elevation. `ELEVATION_CANCELLED` is mapped as a normal structured error.

## Errors and logging

Backend classification uses only `error.code`. Unknown v1 codes become a generic failure. Frontend exceptions are logged and handled at application level.

GUI logs are stored under `%LOCALAPPDATA%\WindowsISOBuilder\logs`; signed URLs, secrets, tokens, product keys, and arbitrary full requests are not log content.

## Publishing

`tools/Build-Gui.ps1` restores, builds, tests, and publishes self-contained `win-x64`. Release staging puts the published GUI in the package root beside `Invoke-WibBackend.ps1`, while preserving `Start-Builder.cmd`, `Start-Builder.ps1`, and the PowerShell module. Installer/MSIX is outside v0.3.0.
