# Архитектура

## Общая модель v0.2.2

PowerShell backend остаётся единственным implementation UUP/build workflow. Backend Contract — адаптер над ним.

```text
Frontend
   │
   ├── RunPreflight
   │
   └── ExecuteBuildPlan
            │
            ├── NDJSON events
            │
            └── cancellation control
                     │
                     ▼
              elevated worker
                     │
                     ▼
              managed process tree
                     │
             aria2 / converter / DISM
```

TUI и CLI используют те же core-функции; отдельного GUI/backend implementation нет.

## Версии

- `VERSION` → ApplicationVersion `0.2.2-alpha.1`;
- module manifest → `0.2.2`;
- Backend Contract SchemaVersion → `1`;
- BuildPlan SchemaVersion → `1`.

ApplicationVersion, contract schema и BuildPlan schema независимы.

## Module layers

- `Common.ps1` — JSON/path/hash/error helpers;
- `ExecutionControl.ps1` — runtime cancellation context, control path, cancellable delay, managed process tree;
- `BackendEvents.ps1` — best-effort structured events;
- `Cache.ps1` — API/package/work cache;
- `UupApi.ps1` — UUP dump API abstraction;
- `Plan.ps1` — BuildPlan Schema v1;
- `Selection.ps1` / `Recommendation.ps1` — TUI selection and quick recommendation;
- `Preflight.ps1` — reusable aggregated readiness checks;
- `Builder.ps1` — package/download/conversion/ISO validation pipeline;
- `Elevation.ps1` — existing plan/result transport plus runtime context forwarding;
- `Application.ps1` — human workflows;
- `ConsoleProgress.ps1` — single converter output parser + console/event adapters;
- `BackendContract.ps1` / `BackendCommands.ps1` — machine validation, DTOs, allowlisted dispatch.

Private files are explicitly loaded as UTF-8 by the module for Windows PowerShell 5.1 compatibility. `Invoke-WibBackend.ps1` remains ASCII-only.

## BuildPlan ≠ ExecutionContext

**BuildPlan** is persistent Schema v1 data describing what to build: selected build, language, editions, image format, output/cache paths, update/cleanup options.

**ExecutionContext** is runtime-only control state for one operation: Backend request id, event file and cancellation hash/cache context.

`requestId`, cancellation control path/hash and event transport are not required BuildPlan fields. This keeps BuildPlan SchemaVersion at `1` and prevents transient process-control state from leaking into reproducible build intent.

## Preflight lifecycle

```text
BuildPlan
   ↓
local non-elevated Invoke-WibPreflight
   ├── fatal fail → structured error, no UAC
   └── ready/warnings
          ↓
         UAC
          ↓
     elevated worker
          ↓
authoritative Invoke-WibPreflight
          ↓
        build
```

The same engine produces `RunPreflight` reports and gates the real build. It aggregates independent checks instead of throwing at the first problem.

Stable report shape:

```json
{
  "ready": true,
  "checks": [
    {
      "id": "disk.cache",
      "status": "pass",
      "severity": "error",
      "code": null,
      "message": "...",
      "data": {
        "availableBytes": 100000000000,
        "requiredBytes": 42949672960
      }
    }
  ]
}
```

Warnings do not change `ready` to false. Online UUP API reachability is optional and bounded by timeout.

## Structured errors

`New-WibErrorException`/`Exception.Data` remains the PS5.1-compatible metadata mechanism. Source code assigns `WibErrorCode`, `WibStage`, optional public message/log/work paths, and controlled `WibErrorDetails` at the failure point.

Backend mapping therefore never needs localized-message pattern matching.

## Cancellation protocol

`ExecuteBuildPlan.requestId` is the public operation id. Internal file transport derives:

```text
SHA256(UTF8(requestId))
        ↓
<cache>\control\<64-hex>.cancel.json
```

`CancelBuild` receives its own request id plus `targetRequestId`. The cancel command response belongs to the cancel request; target build events retain the target request id.

The initialization path never deletes an existing target marker, so a cancellation request that arrives before worker initialization is preserved. Target request ids must therefore be unique per operation.

Parent backend owns marker cleanup after target completion/failure/cancellation. Elevated child uses the hash forwarded by the parent and does not independently delete the shared marker.

## Elevation boundary

The existing JSON plan/result protocol remains in use. Runtime forwarding adds command-line fields for:

- Backend target request id/event file;
- cancellation request hash;
- cancellation cache directory.

No second plan format or HTTP service is introduced. Child results can return structured `errorDetails`. Numeric Win32 cancellation (`ERROR_CANCELLED` 1223) is mapped to `ELEVATION_CANCELLED`; text is not parsed.

## Managed UUP process

`Invoke-WibUupDownloadScript` runs the generated batch through a managed root `cmd.exe` process. The runner redirects output to temporary files, tails it into the existing `Write-Host`/`ConsoleProgress` adapter, and polls cancellation.

At cancellation:

1. the runner already owns the root PID;
2. `taskkill.exe /PID <pid> /T /F` terminates that PID tree;
3. no process name is used for selection;
4. cleanup failure is diagnostic and must not replace the original `BUILD_CANCELLED` classification;
5. process/read handles and only the runner's temporary output files are released.

Existing converter progress and `converter-*.log` remain driven by the single current parser.

## Cache and resume

Cancellation intentionally does not remove package cache, work directory, `.aria2` partial state, converter/build logs, or already downloaded UUP files. A later operation with a new request id and the same BuildPlan can reuse the same cache/work key and normal aria2 resume behavior.

## State and events

`state.json` distinguishes `cancelled` from `failed` and records cancellation time plus the previous build stage when available.

Backend Contract v1 adds the `cancelled` event type as an additive event vocabulary extension. v1 clients must ignore unknown event types and optional fields. Sequence remains monotonic across parent/elevated writers.

## Trust boundaries

- Backend request/cancel request is untrusted local input;
- command dispatch is an explicit allowlist;
- raw request ids never select filesystem paths;
- JSON is not executable code;
- managed process termination is PID-rooted;
- machine DTOs exclude Exception graphs, tokens, product keys and signed download URLs.

## Validation

Primary Pester tests mock network/build dependencies. The process-tree smoke test is opt-in on Windows and uses controlled dummy PowerShell processes so the mandatory suite does not depend on aria2/DISM timing.
