# Статус реализации

## Текущая версия

`0.2.3-alpha.1` — последний backend-focused validation release перед GUI.

- ApplicationVersion: `0.2.3-alpha.1`;
- ModuleVersion: `0.2.3`;
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
- UAC/elevation JSON plan/result protocol;
- API/package/UUP cache and aria2 resume;
- compact console progress and converter/build/elevated/execution logs;
- SHA-256, result metadata and ISO validation;
- Backend Contract v1 JSON request/response and NDJSON events;
- controlled DTOs and requestId propagation;
- reusable preflight, structured errors and cooperative cancellation;
- managed PID-rooted process-tree termination;
- Windows PowerShell 5.1 / PowerShell 7 compatible control code;
- local validation workflow without GitHub Actions.

## Реализовано в `0.2.3-alpha.1`

| Элемент | Статус |
|---|---|
| Unified release validation workflow | Implemented / Automated-ready |
| Machine-readable validation report | Implemented / Automated-ready |
| Backend Contract v1 semantic regression | Implemented / Automated-ready |
| Baseline command regression | Implemented / Automated-ready |
| Required success/error envelope regression | Implemented / Automated-ready |
| Build/Preflight/BuildResult/Event DTO regression | Implemented / Automated-ready |
| Controlled structured-error failure injection | Implemented / Automated-ready |
| BuildPlan v1 fixture + round-trip/Validate regression | Implemented / Automated-ready |
| Centralized release allowlist/denylist | Implemented / Automated-ready |
| Generated `release-manifest.json` | Implemented / Automated-ready |
| ZIP checksum/open/content validation | Implemented / Automated-ready |
| Extracted-package module/backend smoke | Implemented / Automated-ready |
| Source-checkout leakage guard | Implemented / Automated-ready |
| Current tracked-tree obvious-secret/personal-path scan | Implemented / Automated-ready |
| Release-package safety scan | Implemented / Automated-ready |
| Validation matrix RU/EN | Implemented |
| GUI integration boundary/freeze | Documented |

`Automated-ready` означает, что code/tests существуют и должны запускаться локальным PowerShell validation entry point. Это не равно фактическому PASS в среде, где PowerShell tests не были выполнены.

## Backend Contract v1 commands

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`, `RunPreflight`, `CancelBuild`.

После `v0.2.3` этот command set, required envelope/DTO fields и BuildPlan Schema v1 являются baseline первого GUI. Additive optional fields остаются допустимыми. Breaking change требует SchemaVersion 2.

## Validation status vocabulary

Используются статусы:

- **Automated** — проверяется validation workflow;
- **Manual** — требует действия владельца;
- **Confirmed** — фактически выполнено и подтверждено;
- **Not run** — не выполнялось;
- **Not required** — не является gate этой версии;
- **Skipped** — optional check недоступен в текущей среде.

Подробная матрица: `docs/VALIDATION_MATRIX.md`.

## Реальный E2E baseline

| Scenario | Status | Comment |
|---|---|---|
| Windows 11 x64 ru-RU Core + Professional ESD | Confirmed baseline | ранее фактически завершён до ISO на сохранённом pipeline; не выдаётся за новый v0.2.3 run |
| Windows 10 x64 Professional ESD | Not run | требуется отдельная реальная ручная сборка |
| Windows 11 x64 single-edition WIM | Not run | требуется отдельная реальная ручная сборка |
| ARM64/x86 full matrix | Not required | вне pre-GUI baseline |
| multi-GB cancel/resume E2E | Not required | existing controlled/mocked cancellation coverage достаточна для этого release |

## Release package validation

Package validation считается отдельным от source validation и проверяет:

- ZIP существует/открывается;
- SHA-256 checksum совпадает;
- logical file set соответствует central allowlist;
- denied/generated files отсутствуют;
- `release-manifest.json` соответствует VERSION/module/schema versions;
- package распаковывается в Temp;
- `Start-Builder.ps1` синтаксически валиден;
- `WindowsISOBuilder` импортируется из extract root, а не source checkout;
- packaged Backend `GetVersion` и offline `RunPreflight` работают;
- package safety scan не находит obvious secrets/personal paths.

## Validation tool policy

`tools/Invoke-ReleaseValidation.ps1` по умолчанию выполняет Quick safe validation. `-Full` добавляет package smoke, strict analyzer requirement, PS7 smoke when available и controlled process-tree smoke.

Ни один обычный mode не скачивает UUP set, не собирает реальный ISO и не требует UAC.

`validation-result.json` — generated developer artifact и игнорируется Git.

## Намеренно не реализовано

- GUI;
- WPF/WinUI;
- C# rewrite;
- installer/MSIX/updater;
- queue/history/profiles;
- USB writer/Rufus integration;
- dynamic disk estimator;
- driver injection/customization/debloat/TPM bypass/activation;
- custom UUP API/downloader/converter;
- GitHub Actions.

## Известные ограничения

- Backend Contract transport остаётся local process + JSON/NDJSON files;
- external UUP dump API/conversion package может измениться;
- safety scan проверяет текущие tracked files/package, но не Git history;
- real Windows 10 E2E и real Windows 11 WIM baseline остаются `Not run`, пока владелец не выполнит их фактически;
- package/full validation требует Windows PowerShell 5.1 и локальных Pester/PSScriptAnalyzer dependencies согласно выбранному mode.

## Backend ready for GUI

**YES — как интерфейсный/архитектурный baseline.**

GUI должен опираться на `Invoke-WibBackend.ps1`, Backend Contract Schema v1, BuildPlan Schema v1, `RunPreflight`, `ExecuteBuildPlan`, `CancelBuild`, `requestId`, NDJSON events и structured error codes.

Перед merge/release владелец всё равно должен фактически выполнить локальный Windows validation workflow; отсутствие этого запуска не является причиной перепроектировать backend, но является release-validation gate.
