# Статус реализации

## Текущая версия

`0.3.0-alpha.1` — первый GUI MVP.

- ApplicationVersion: `0.3.0-alpha.1`;
- ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

## Реализовано в source

- WPF/.NET 10 GUI project и solution;
- startup backend resolution + `GetVersion` schema handshake;
- Quick Windows 11/10 через backend recommendation;
- Catalog search, architecture, Preview и servicing display filter;
- отдельное выделение/активация Catalog row без преждевременного metadata flow;
- dynamic language/edition loading и multi-edition UI;
- ESD/WIM, build options и output folder selection;
- `CreateBuildPlan` + structured `RunPreflight` UI;
- invalidation старого BuildPlan/preflight после изменения build options;
- async `ExecuteBuildPlan`;
- incremental NDJSON reader и normalized progress/speed display;
- cooperative `CancelBuild` и close-during-build cancellation flow;
- state rules для normal/retry/cancellation-failure paths;
- structured mapping стабильной backend error taxonomy;
- result path/SHA/log actions;
- GUI local logging + frontend exception boundary;
- hidden `--backend-smoke`, проверяющий Contract v1 + BuildPlan v1;
- MSTest contract/state/event-reader/integration coverage;
- explicit `Microsoft.NET.Test.Sdk` test runner configuration;
- `Build-Gui.ps1` self-contained `win-x64` publish tooling;
- release package integration preserving TUI/CLI/backend;
- self-hosted Windows GitHub Actions workflow как thin wrapper над Full release validation.

## Сохранено

Dynamic UUP catalog, recommendation engine, BuildPlan v1, preflight, elevation, UUP download/conversion/DISM, ISO validation, cancellation implementation, cache/resume, TUI/CLI, Backend Contract v1 and PowerShell validation remain backend-owned.

## Validation terminology

`Implemented` означает наличие code/test/tooling, но не подтверждает фактический PASS. Фактический результат относится только к конкретному SHA и фиксируется отдельно в `VALIDATION_MATRIX`/PR/Actions run.

## Требует Windows execution перед release

- успешный Full Windows validation текущего PR head на self-hosted runner;
- manual GUI smoke;
- желательно один real GUI E2E до ISO.

Full validation включает .NET restore/build/test, Pester, PSScriptAnalyzer, PS5.1/PS7 backend smoke, process-tree smoke, `Build-Gui.ps1` publish, release package и packaged GUI/backend smoke.

Агент не должен переводить эти пункты в PASS без реального запуска соответствующего SHA.

## Намеренно не реализовано

History, profiles, queue, cache-management GUI, updater, installer/MSIX, USB writer/Rufus, full theme/language settings, accounts/cloud, Windows customization/debloat, driver injection, TPM bypass, activation и custom UUP downloader/converter.

GitHub Actions не является частью продукта/runtime: workflow только отправляет существующую release validation на owner-controlled self-hosted Windows runner и исключён из release package.

## Известные ограничения alpha.1

- runtime localization полностью не реализована; основной GUI русский;
- layout/UI polish ограничены MVP;
- real build остаётся тяжёлой manual validation procedure;
- Backend Contract transport остаётся local process + JSON/NDJSON files;
- external UUP dump API/conversion package может измениться.
