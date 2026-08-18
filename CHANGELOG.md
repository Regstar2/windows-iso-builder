# Changelog

## Unreleased

Пока нет изменений после `0.3.0-alpha.1`.

## 0.3.0-alpha.1 — 2026-08-18

### Added

- first Windows GUI on C# / WPF / .NET 10;
- Quick Mode for Windows 11 and Windows 10 through Backend Contract `GetRecommendedBuild`;
- Catalog Mode through `SearchBuilds` with architecture, Preview and servicing display filter;
- dynamic language and multi-edition selection;
- ESD/WIM and existing backend build options;
- GUI preflight, progress, cancellation, success and structured error UX;
- strongly typed C# Backend Contract v1 client;
- incremental UTF-8 NDJSON event reader;
- GUI logging and frontend exception boundary;
- C# GUI test project and Windows backend integration smokes;
- `tools/Build-Gui.ps1`;
- self-contained `win-x64` GUI publishing;
- packaged GUI backend handshake smoke;
- GUI architecture documentation in Russian and English.

### Changed

- GUI becomes the recommended interactive user entry point;
- release package contains the GUI together with the existing PowerShell backend/TUI/CLI;
- release validation verifies GUI build/test/publish, package contents, backend handshake and package source isolation;
- release manifest has additive `gui` metadata.

### Compatibility

- ApplicationVersion: `0.3.0-alpha.1`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion remains `1`;
- BuildPlan SchemaVersion remains `1`;
- TUI/CLI remain supported;
- PowerShell backend remains the sole owner of UUP/build/elevation/cancellation workflow.

### Validation status

- C# tests: **NOT RUN** in the agent environment;
- Pester: **NOT RUN** in the agent environment;
- PSScriptAnalyzer: **NOT RUN** in the agent environment;
- PS5.1 smoke: **NOT RUN** in the agent environment;
- PS7 smoke: **NOT RUN** in the agent environment;
- Full release validation: **NOT RUN** in the agent environment;
- manual GUI smoke: **NOT RUN**;
- real GUI Windows 11 x64 ru-RU Professional ESD E2E: **NOT RUN**.

## 0.2.3-alpha.1 — 2026-08-18

### Added

- unified release validation tool;
- structured validation report;
- release package smoke;
- Backend Contract compatibility regression tests;
- BuildPlan v1 fixture/regression;
- release manifest;
- validation matrix;
- release tree/package safety scan.

### Changed

- release packaging is self-validated;
- source validation and package validation are explicitly separate;
- backend integration boundary is frozen as GUI baseline;
- validation claims are separated from implementation claims.

### Compatibility

- Backend Contract SchemaVersion `1`;
- BuildPlan SchemaVersion `1`;
- TUI/CLI unchanged;
- PS5.1/PS7 support unchanged.

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
- stable structured error codes: `INVALID_REQUEST`, `UNSUPPORTED_SCHEMA`, `INVALID_COMMAND`, `INVALID_ARGUMENT`, `BUILD_NOT_FOUND`, `LANGUAGE_NOT_FOUND`, `EDITION_NOT_FOUND`, `UUP_API_ERROR`, `UUP_API_UNAVAILABLE`, `INVALID_BUILD_PLAN`, `ELEVATION_FAILED`, `BUILD_FAILED`, `INTERNAL_ERROR`;
- Backend Contract commands `GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`;
- controlled camelCase DTO conversion for builds, languages, editions, build plans, build results, errors and events;
- Backend Contract/Event Pester tests using mocks instead of real Windows downloads;
- `docs/BACKEND_CONTRACT.md` and `docs/BACKEND_CONTRACT_EN.md`;
- release notes for `0.2.1-alpha.1`.

### Changed

- ApplicationVersion is centralized in root `VERSION`; UI, metadata, Backend Contract and HTTP User-Agent now use the same runtime source;
- module manifest version raised to `0.2.1`; ApplicationVersion remains independently versioned as `0.2.1-alpha.1`;
- BuildPlan schema version is explicitly independent and remains `1`;
- quick-mode recommendation logic moved into a reusable service used by both TUI and Backend Contract without hardcoded Windows release/build numbers;
- converter output parsing now produces normalized progress state consumed by the existing console renderer and the optional structured event sink; no second aria2 parser was added;
- existing elevated plan/result protocol can forward Backend Contract request/event context while preserving the same build/elevation workflow;
- UUP API/package User-Agent no longer contains the stale manually maintained `WindowsISOBuilder/0.1` value;
- release packaging reads its default version from `VERSION` and includes the machine entry point and Backend Contract documentation.

### Compatibility

- existing `Start-Builder.cmd`, `Start-Builder.ps1`, interactive TUI, non-interactive CLI, quick mode, UAC/elevation, console progress, logs, caching and resume behavior are preserved by design;
- Windows PowerShell 5.1 remains a required target; PowerShell 7 is also supported;
- no GUI, WPF, WinUI, C# rewrite, updater, USB/Rufus integration, queue/history/profiles, full cancellation subsystem, custom UUP downloader/converter, or GitHub Actions were added.

### Validation status

- Backend Contract tests are designed to run without downloading Windows by mocking external/build operations;
- release verification still requires the complete local Pester suite, PSScriptAnalyzer and `GetVersion` smoke tests in Windows PowerShell 5.1 and, when available, PowerShell 7;
- previous real Windows 11 end-to-end build validation belongs to the preserved build pipeline and does not replace current-version automated verification.

## 0.2.0-alpha.1 — 2026-08-17

- в главное меню добавлен быстрый сценарий `Быстро скачать последнюю Windows`: для Windows 11 и Windows 10 приложение принудительно обновляет каталог UUP dump, динамически выбирает рекомендуемую стабильную полноценную x64-сборку без зашитого номера версии и затем предлагает выбрать язык, редакции и формат; недоступные Windows 7/8 удалены из быстрого меню;
- быстрый режим Windows 11 предпочитает последний стабильный H2-релиз как массовую ветку ежегодного feature-update цикла и не выбирает специализированный H1-релиз только из-за большего номера версии; если H2-релиз в каталоге отсутствует, используется последняя стабильная сборка с предупреждением;
- подробный вывод `aria2` и UUP-конвертера больше не засоряет консоль: во время загрузки и конвертации показывается одна обновляемая полоса прогресса с процентом/скоростью, а полный вывод сохраняется рядом с build-log в `converter-*.log`;
- запуск `uup_download_windows.cmd` переведён на вложенный PowerShell с `Out-String -Stream` и явной передачей exit code, чтобы родительский процесс дождался дочерних процессов конвертера перед поиском ISO; готовый ISO ищется во всём рабочем каталоге, а ошибка без ISO содержит путь к подробному `converter-*.log`;
- после успешной интерактивной сборки родительское окно явно показывает блок `Сборка завершена`, сообщение `ISO успешно создан`, полный путь к ISO и доступные диагностические логи;
- каждый запуск `Start-Builder.ps1` пишет отдельный transcript-лог в `logs\execution-<timestamp>-<pid>.log`; elevated-процесс получает отдельный `logs\elevated-<operation-id>.log`;
- повышенный процесс сборки передаёт родительскому процессу структурированный JSON-результат с `success`, этапом, сообщением, стеком, путём к логу, рабочим каталогом и путём к ISO; вместо общего `Exit code: 1` показывается реальная причина ошибки;
- каталог классифицирует полноценные сборки Windows, servicing-обновления и прочие записи; cumulative/.NET/OOBE-пакеты скрыты в интерактивном режиме по умолчанию;
- в таблицу добавлен столбец `Тип`, а в меню сортировки — сортировка по типу записи с полноценными сборками Windows впереди;
- неинтерактивный режим предпочитает полноценную сборку Windows, если API одновременно возвращает servicing-пакеты;
- добавлена постраничная навигация по каталогу сборок: следующие/предыдущие 40 записей, переход к странице, новый поиск и возврат в главное меню;
- изменён порядок актуальности: сначала сравнивается семейство Windows-релиза, затем servicing date/build number, чтобы старые LTSC/development-ветки не вытесняли актуальный массовый выпуск;
- исправлены проблемы Windows PowerShell 5.1 с UTF-8 private scripts и обёрткой `Write-Host`;
- статические тесты ограничены исходниками и тестами проекта и используют UTF-8-safe разбор PowerShell;
- добавлены локальные Pester-тесты elevated-result, execution-log, сообщения об успешной сборке, quick mode, compact converter progress, ожидания UUP-процессов, UTF-8 loader, `Write-Host` compatibility и политики выбора рекомендуемого Windows 11 H2;
- русская и английская документация обновлена под публичную alpha и явно отделяет реализованные возможности от непроверенных вручную сценариев;
- GitHub Actions исключены из релизного процесса; используются локальные Pester и PSScriptAnalyzer;
- добавлена MIT License;
- версия проекта повышена до `0.2.0-alpha.1`, версия PowerShell-модуля — до `0.2.0`.

### Validation status

- локальные тесты и PSScriptAnalyzer используются как обязательная автоматическая проверка;
- подтверждён real end-to-end сценарий Windows 11 x64 ru-ru до готового ISO;
- подтверждён multi-edition сценарий Core + Professional на реальной сборке;
- отдельный Windows 10 end-to-end, принудительный обрыв сети и полная ручная WIM/ESD-матрица не являются release gates для этой alpha.

## 0.1.0-alpha.1 — 2026-08-06

- заменён фиксированный сценарий Windows 10/11 на динамический каталог UUP dump;
- добавлен интерактивный выбор сборки, архитектуры, языка и редакций;
- добавлены virtual editions, WIM/ESD и параметры интеграции обновлений;
- добавлен постоянный кеш и восстановление загрузок aria2;
- добавлены план сборки, повышение прав после выбора параметров и подробные состояния задания;
- добавлены SHA-256, JSON-метаданные и проверка структуры ISO;
- проект разделён на PowerShell-модуль и покрыт локальными тестами;
- добавлена русская и английская документация.
