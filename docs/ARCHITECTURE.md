# Архитектура

## Общая модель v0.2.3

PowerShell backend остаётся единственным implementation UUP/build workflow. Backend Contract — стабильный machine-readable adapter над ним. `v0.2.3-alpha.1` не переписывает backend, а добавляет validation/release-hardening слой вокруг существующей архитектуры.

```text
TUI / CLI / future GUI
          │
          ▼
 Invoke-WibBackend.ps1
          │
 Backend Contract v1
          │
   ┌──────┴────────┐
   │               │
RunPreflight   ExecuteBuildPlan ◄── CancelBuild
                   │
              NDJSON events
                   │
              UAC boundary
                   │
            elevated worker
                   │
          managed process tree
                   │
           aria2 / converter / DISM
```

TUI и CLI продолжают использовать тот же core. Отдельного GUI/backend implementation нет.

## Версии

- `VERSION` → ApplicationVersion `0.2.3-alpha.1`;
- module manifest → `0.2.3`;
- Backend Contract SchemaVersion → `1`;
- BuildPlan SchemaVersion → `1`.

ApplicationVersion, module version, contract schema и BuildPlan schema независимы. Schema повышается только при реальном breaking change.

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
- `Elevation.ps1` — plan/result transport plus runtime context forwarding;
- `Application.ps1` — human workflows;
- `ConsoleProgress.ps1` — single converter output parser + console/event adapters;
- `BackendContract.ps1` / `BackendCommands.ps1` — machine validation, DTOs, allowlisted dispatch.

Private files загружаются модулем через явное UTF-8 чтение для Windows PowerShell 5.1 compatibility. Standalone `Invoke-WibBackend.ps1` остаётся ASCII-only.

## BuildPlan != ExecutionContext

**BuildPlan** — persistent Schema v1 data о том, что собирать: selected build, language, editions, image format, output/cache paths и build options.

**ExecutionContext** — runtime-only state конкретной operation: Backend request id, event file и cancellation context.

`requestId`, cancellation control path/hash и event transport не являются required BuildPlan fields. Это сохраняет backward compatibility BuildPlan Schema v1.

## Preflight lifecycle

```text
BuildPlan
   ↓
local non-elevated Invoke-WibPreflight
   ├── fatal fail → no UAC
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

Тот же engine формирует `RunPreflight` report и gates реальный build. `onlineChecks=false` не выполняет network request.

Stable report fields: `ready`; each check has `id`, `status`, `severity`, `code`, `message`, `data`.

## Structured errors

`New-WibErrorException` / `Exception.Data` остаются PS5.1-compatible metadata mechanism. Error code присваивается там, где возникает failure, а не определяется по localized message.

Backend error DTO содержит controlled fields и не сериализует Exception graph, signed UUP URLs, tokens или product keys.

## Cancellation protocol

`ExecuteBuildPlan.requestId` — public operation id. Internal control path выводится из:

```text
SHA256(UTF8(requestId))
        ↓
<cache>\control\<64-hex>.cancel.json
```

`CancelBuild` имеет собственный request id и принимает `targetRequestId`. Existing early marker не удаляется worker initialization, поэтому cancel-before-worker race не теряется.

Managed runner завершает только process tree собственного root PID. Kill-by-name не используется. Cancellation сохраняет partial UUP/work data для обычного aria2 resume.

## State and events

Backend Contract v1 event line содержит semantic envelope: `schemaVersion`, `requestId`, monotonic `sequence`, UTC `timestamp`, `type`, normalized `stage`, `message`, `progress`.

Event types включают `stage`, `progress`, `completed`, `failed`, `cancelled`, `warning`, `info`. Новые optional fields/types могут добавляться внутри v1; клиент обязан игнорировать неизвестные additive extensions.

## GUI integration boundary

После `v0.2.3-alpha.1` следующий интерфейс считается baseline для первого GUI:

- machine entry point: `Invoke-WibBackend.ps1`;
- Backend Contract Schema v1;
- BuildPlan Schema v1;
- `RunPreflight`;
- `ExecuteBuildPlan`;
- `CancelBuild`;
- `requestId` как operation correlation id;
- NDJSON event stream;
- structured error codes.

Будущий GUI **не должен**:

- вызывать private PowerShell functions;
- dot-source private implementation files;
- парсить `Write-Host`/console text;
- парсить raw aria2/converter output;
- определять тип ошибки по localized `message`;
- обходить `RunPreflight` и напрямую воспроизводить его проверки;
- реализовывать собственную cancellation process-kill логику.

GUI отправляет JSON request в `Invoke-WibBackend.ps1`, связывает operation по `requestId`, читает machine response и optional event stream, запускает preflight через contract и отменяет build через `CancelBuild`.

Это **не вечный freeze API**. Additive evolution v1 разрешена. Удаление/переименование required fields/commands или изменение их смысла требует осознанного Backend Contract SchemaVersion 2.

## Release-validation architecture

`v0.2.3` добавляет developer/release layer, не являющийся Backend Contract:

```text
 tools/Invoke-ReleaseValidation.ps1
        │
        ├── source checks
        │    ├── versions/syntax/module
        │    ├── tests/Run-Tests.ps1
        │    ├── PSScriptAnalyzer
        │    ├── Backend safe smokes
        │    └── current-tree safety scan
        │
        └── package checks
             ├── New-ReleasePackage.ps1
             ├── checksum / ZIP / logical allowlist
             ├── release-manifest.json
             ├── extract into Temp
             ├── packaged module import
             ├── packaged Backend GetVersion
             ├── packaged offline RunPreflight
             └── package safety scan
```

`tools/ReleasePackageConfig.psd1` — единый source of truth для logical runtime entries, required package files и denylist. Packaging и validation не должны поддерживать независимые копии этих списков.

`release-manifest.json` генерируется только в staging package и содержит версии, но не timestamp, username, machine name или local absolute paths.

## Source validation != package validation

Source checkout может быть green, а ZIP — неполным, загрязнённым или импортировать неправильный module path. Поэтому release package является отдельным validation target.

Package smoke распаковывает ZIP в Temp и проверяет, что imported `WindowsISOBuilder` module path находится именно внутри extract root. Это предотвращает false PASS из-за module source checkout рядом.

## Validation layers

- **Automated** — versions, syntax, Pester, analyzer, Contract/BuildPlan regressions, safety checks;
- **Controlled smoke** — PS7 compatibility, dummy PID-tree cancellation, package smoke;
- **Real E2E** — настоящая Windows ISO build, только вручную/opt-in;
- **Not tested/not required** — сценарии вне baseline этой alpha.

Подробно: `docs/VALIDATION_MATRIX.md`.

## Trust boundaries

- Backend request/cancel request — untrusted local input;
- command dispatch — explicit allowlist;
- raw request ids никогда не выбирают filesystem paths;
- JSON не является executable code;
- process termination PID-rooted;
- package content формируется explicit allowlist;
- current-tree/package scan — ограниченный obvious-secret check, не Git-history audit.
