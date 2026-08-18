# Changelog

## Unreleased

Пока нет изменений после `0.2.3-alpha.1`.

## 0.2.3-alpha.1 — 2026-08-18

### Added

- unified release validation tool;
- structured machine-readable validation report;
- release package smoke against an extracted ZIP;
- Backend Contract v1 semantic compatibility regression tests;
- BuildPlan v1 fixture/read/validate/round-trip regression;
- generated release manifest inside package staging;
- RU/EN validation matrix and manual E2E result template;
- current tracked-tree and release-package limited safety scan;
- centralized release allowlist/denylist shared by packaging and validation.

### Changed

- release packaging is self-validated before ZIP creation;
- source validation and package validation are explicitly separate;
- backend integration boundary is frozen as the first-GUI baseline;
- validation claims are separated from implementation claims;
- ApplicationVersion raised to `0.2.3-alpha.1`, ModuleVersion to `0.2.3`;
- generated `dist/` and `validation-result*.json` are ignored by Git.

### Compatibility

- Backend Contract SchemaVersion remains `1`;
- BuildPlan SchemaVersion remains `1`;
- TUI/CLI/quick mode behavior is unchanged by design;
- Windows PowerShell 5.1 / PowerShell 7 support policy is unchanged;
- GUI, WPF/WinUI, C#, installer/updater, queue/history/profiles, USB/Rufus, customization features and GitHub Actions are not added.

### Validation status

- automated/controlled validation implementation is complete in the branch;
- Windows 10 real E2E: **NOT RUN**;
- Windows 11 single-edition WIM real E2E: **NOT RUN**;
- Windows 11 x64 ru-RU Core + Professional ESD remains a previously confirmed baseline and is not represented as a new v0.2.3 run;
- exact current execution results must come from the local Windows validation workflow and must never be simulated.

## 0.2.2-alpha.1 — 2026-08-18

### Added

- Backend command `RunPreflight` и reusable aggregated preflight engine;
- structured preflight report со stable check ids, status/severity/code и machine-readable disk/path data;
- optional bounded official UUP dump API reachability check;
- Backend command `CancelBuild` и SHA-256-based runtime cancellation control;
- cooperative cancellation helpers, cancellable retry delays и runtime forwarding через elevation boundary;
- `cancelled` Backend Contract event и отдельное cancelled job state;
- extended structured error taxonomy, включая `UNSUPPORTED_HOST`, `REQUIRED_COMPONENT_MISSING`, `PATH_NOT_WRITABLE`, `DISK_SPACE_LOW`, `NETWORK_ERROR`, `UUP_PACKAGE_DOWNLOAD_FAILED`, `UUP_PACKAGE_INVALID`, `DOWNLOAD_FAILED`, `CONVERTER_FAILED`, `DISM_FAILED`, `ISO_NOT_FOUND`, `ISO_VALIDATION_FAILED`, `ELEVATION_CANCELLED`, `BUILD_CANCELLED`;
- managed child-process runner с PID-rooted process-tree cancellation;
- reliability/cancellation Pester tests и opt-in controlled Windows process-tree smoke test.

### Changed

- local preflight выполняется до UAC, поэтому fatal environment failure больше не открывает elevation prompt;
- elevated worker повторяет critical preflight через тот же reusable engine;
- прежние assert-style host/disk/tool checks сведены к общему preflight source of truth;
- retry delays поддерживают cancellation вместо blind `Start-Sleep`;
- `uup_download_windows.cmd` выполняется через managed root process с сохранением existing compact progress и `converter-*.log`;
- UUP/converter process tree может быть остановлен без kill-by-name и без orphan aria2/converter descendants;
- elevated result protocol передаёт optional structured error details;
- cancellation сохраняет UUP cache/work data и aria2 resume state.

### Compatibility

- Backend Contract SchemaVersion остаётся `1`;
- BuildPlan SchemaVersion остаётся `1`;
- ApplicationVersion — `0.2.2-alpha.1`, ModuleVersion — `0.2.2`;
- TUI/CLI, quick mode, WIM/ESD, virtual editions, cache/resume, progress и logs остаются совместимыми;
- Windows PowerShell 5.1 и PowerShell 7 остаются целевыми runtime;
- GUI, WPF/WinUI, C#, updater, queue/history/profiles, USB/Rufus, dynamic disk estimator и GitHub Actions не добавлены.

### Validation status

- reliability tests разработаны без реальной загрузки Windows;
- process-tree integration smoke является opt-in и использует controlled dummy PowerShell process;
- перед release требуется локально выполнить полный Pester suite, PSScriptAnalyzer, Backend `GetVersion`/`RunPreflight` и controlled cancellation smokes в Windows PowerShell 5.1 и, если доступен, PowerShell 7.

## 0.2.1-alpha.1 — 2026-08-18

### Added

- Backend Contract Schema v1 как отдельный машиночитаемый слой над существующим PowerShell backend;
- ASCII-only `Invoke-WibBackend.ps1` для Windows PowerShell 5.1 и PowerShell 7;
- UTF-8 JSON request/response transport с атомарной записью final response;
- optional UTF-8 NDJSON event stream со `stage`, `progress`, `completed`, `failed` и extensible `warning`/`info` events;
- stable structured error codes;
- Backend Contract commands `GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`;
- controlled DTO conversion for builds, languages, editions, build plans, build results, errors and events;
- Backend Contract/Event Pester tests using mocks instead of real Windows downloads;
- `docs/BACKEND_CONTRACT.md` and `docs/BACKEND_CONTRACT_EN.md`;
- release notes for `0.2.1-alpha.1`.

### Changed

- ApplicationVersion centralized in root `VERSION`;
- module manifest version raised to `0.2.1`;
- BuildPlan schema remains independently versioned as `1`;
- quick-mode recommendation logic moved into a reusable service;
- converter output parsing produces normalized progress consumed by console and structured event sinks;
- elevation transport can forward Backend request/event context;
- UUP API/package User-Agent uses the centralized application version;
- release packaging reads its default version from `VERSION` and includes Backend Contract files.

### Compatibility

- existing `Start-Builder.cmd`, `Start-Builder.ps1`, TUI, CLI, quick mode, UAC/elevation, progress, logs, caching and resume are preserved;
- Windows PowerShell 5.1 remains required and PowerShell 7 supported;
- GUI and unrelated post-backend features are not added.

## 0.2.0-alpha.1 — 2026-08-17

- добавлен динамический quick mode для рекомендуемой стабильной Windows 11/10 x64 без hardcoded build number;
- добавлены paging/classification/sorting для каталога UUP dump;
- улучшен compact console progress с raw converter log;
- улучшен structured elevated result/error path;
- добавлены execution/elevated/converter/build logs;
- добавлены SHA-256/result metadata и post-build ISO validation;
- сохранены cache/resume, virtual editions, WIM/ESD и dynamic catalog;
- исправлена совместимость Windows PowerShell 5.1 с UTF-8 private scripts;
- расширены локальные Pester/PSScriptAnalyzer проверки;
- подтверждён реальный Windows 11 x64 ru-RU ESD сценарий до ISO, включая Core + Professional multi-edition baseline.

### Validation status

- локальные tests/PSScriptAnalyzer используются как обязательный automation layer;
- отдельный Windows 10 E2E и полная ручная WIM/ESD matrix не были release gates этой alpha.

## 0.1.0-alpha.1 — 2026-08-06

- заменён фиксированный сценарий Windows 10/11 на динамический каталог UUP dump;
- добавлен интерактивный выбор build/architecture/language/editions;
- добавлены virtual editions, WIM/ESD и параметры интеграции обновлений;
- добавлен постоянный cache и aria2 resume;
- добавлены BuildPlan, elevation after selection и detailed job state;
- добавлены SHA-256, JSON metadata и ISO structure validation;
- проект разделён на PowerShell module и покрыт локальными tests;
- добавлены русская/английская документация и MIT License.
