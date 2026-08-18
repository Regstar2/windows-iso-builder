# Статус реализации

## Текущая версия

`0.2.2-alpha.1` — второй архитектурный release перед GUI.

- ApplicationVersion: `0.2.2-alpha.1`;
- ModuleVersion: `0.2.2`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

GUI намеренно отсутствует.

## Реализовано и сохранено

- dynamic UUP dump catalog/search;
- quick recommended Windows selection without hardcoded build numbers;
- dynamic languages/editions;
- TUI, non-interactive CLI and quick mode;
- BuildPlan Schema v1;
- WIM/ESD and virtual editions;
- existing UAC/elevation JSON plan/result protocol;
- API/package/UUP cache and aria2 resume;
- compact console progress and converter/build/elevated/execution logs;
- SHA-256, result metadata and ISO validation;
- Backend Contract v1 JSON request/response and NDJSON events;
- controlled DTOs and requestId propagation;
- Windows PowerShell 5.1 / PowerShell 7 compatible control code;
- local Pester/PSScriptAnalyzer workflow without GitHub Actions.

## Реализовано в `0.2.2-alpha.1`

- reusable `Invoke-WibPreflight` engine;
- Backend command `RunPreflight`;
- aggregated structured preflight report;
- host/PowerShell/tool/path/write/disk checks;
- optional official UUP dump API online check;
- warning-vs-fatal semantics;
- local preflight before UAC;
- authoritative re-check in the build worker;
- centralized 40 GiB cache/work and 8 GiB output minimums;
- expanded structured error taxonomy and controlled `error.details`;
- source-level error classification without localized message parsing;
- cooperative cancellation helpers and cancellable retry delays;
- Backend command `CancelBuild`;
- SHA-256-derived cancellation control path;
- cancel-before-worker race preservation;
- runtime cancellation forwarding through elevation;
- managed UUP child process execution with PID-rooted tree termination;
- `BUILD_CANCELLED` and numeric `ELEVATION_CANCELLED` handling;
- distinct cancelled job state and `cancelled` event;
- cache/work preservation after cancel so aria2 resume remains possible;
- mandatory mock-based reliability tests plus optional Windows dummy process-tree smoke test.

## Backend Contract v1 commands

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`, `RunPreflight`, `CancelBuild`.

## Compatibility guarantees

- SchemaVersion stays `1`;
- BuildPlan Schema stays `1`;
- new commands/error codes/optional properties are additive;
- BuildPlan does not acquire cancellation/event fields;
- existing public TUI/CLI entry points remain;
- converter output still passes through the existing normalized progress parser;
- cache key/resume behavior remains based on build/language/source edition, not request id.

## Validation requirements for this branch/release

Must be executed on Windows before release:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1

$issues = @(Invoke-ScriptAnalyzer `
  -Path . `
  -Recurse `
  -Settings .\.psscriptanalyzer.psd1)
```

Also required: `GetVersion`, `RunPreflight`, controlled cancellation smoke through `Invoke-WibBackend.ps1`, and equivalent safe smokes in `pwsh` when available.

## Не реализовано намеренно

- GUI;
- WPF/WinUI;
- C# rewrite;
- installer/updater;
- queue;
- history;
- profiles;
- USB writer/Rufus integration;
- auto-download updates;
- dynamic disk estimator;
- custom UUP API/downloader/converter;
- GitHub Actions;
- full Windows 10/11 E2E matrix.

## Известные ограничения

- Backend Contract transport remains local process + JSON/NDJSON files;
- online preflight only checks UUP dump API reachability and does not validate Microsoft CDN or download a UUP set;
- `Mount-DiskImage` absence limits deep post-build validation but is non-fatal;
- task-tree termination relies on Windows `taskkill /T /F` for PS5.1-compatible descendant cleanup;
- an unconsumed cancellation marker can remain if `CancelBuild` targets an operation that is never started; request ids are required to be unique;
- full real Windows matrix remains a later validation release task.
