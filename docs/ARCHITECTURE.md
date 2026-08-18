# Архитектура

## Общая модель v0.3.0

PowerShell backend остаётся единственным implementation UUP/build workflow. `v0.3.0-alpha.1` добавляет WPF GUI как client Backend Contract v1, не переписывая backend.

```text
WPF GUI ─────┐
             ├─> Invoke-WibBackend.ps1 -> Backend Contract v1
Automation ──┘                         -> PowerShell backend
TUI/CLI --------------------------------> тот же PowerShell core
                                           │
                              preflight / UAC / build / cancel
                                           │
                                 aria2 / converter / DISM
```

TUI/CLI не переводятся на C# и не deprecated.

## Версии

- `VERSION` → ApplicationVersion `0.3.0-alpha.1`;
- module manifest → `0.3.0`;
- Backend Contract SchemaVersion → `1`;
- BuildPlan SchemaVersion → `1`.

Schema повышается только при breaking change. GUI compatibility определяется contract schema.

## Backend layers

Существующие `Common`, `ExecutionControl`, `BackendEvents`, `Cache`, `UupApi`, `Plan`, `Selection/Recommendation`, `Preflight`, `Builder`, `Elevation`, `Application`, `ConsoleProgress`, `BackendContract/BackendCommands` сохраняют ответственность. GUI не вызывает private layer напрямую.

## GUI layer

Новый `src/WindowsISOBuilder.Gui` содержит WPF view, MVVM state/orchestration, strongly typed DTOs, process/file BackendClient, incremental event reader, path resolution, error mapping и GUI logging.

Подробности: [GUI_ARCHITECTURE.md](GUI_ARCHITECTURE.md).

## BuildPlan != execution context

BuildPlan Schema v1 описывает что собирать. RequestId/event transport/cancellation state остаются runtime execution context и не добавляются в persistent BuildPlan.

## Preflight/elevation

GUI сначала вызывает `RunPreflight`. Fatal `ready=false` блокирует кнопку build. При `ExecuteBuildPlan` существующий backend повторно контролирует readiness и сам выполняет UAC/elevated worker. GUI остаётся обычным process.

## Cancellation

Public operation id — requestId `ExecuteBuildPlan`. GUI отменяет только через `CancelBuild`; внутренний backend по-прежнему завершает только owned PID tree и сохраняет partial cache/work data для resume.

## Events

Backend Contract v1 NDJSON остаётся semantic source progress telemetry. Клиенты обязаны терпеть additive fields/event types. Финальный response — source of truth job completion.

## Release architecture

`Build-Gui.ps1` создаёт self-contained `win-x64` publish. `New-ReleasePackage.ps1` объединяет published GUI с существующим backend/TUI/CLI и package-only manifest. `Invoke-ReleaseValidation.ps1 -Full` делает GUI build/test/publish и package/backend handshake smokes без реальной Windows download/build.

## Trust boundaries

- backend requests — untrusted data;
- command dispatch — allowlist;
- GUI process arguments — separated `ArgumentList`;
- raw request id не выбирает filesystem path;
- cancellation остаётся backend-owned;
- package/backend code не загружается из сети;
- release safety scan не является Git-history audit.
