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
- dynamic language/edition loading и multi-edition UI;
- ESD/WIM, build options и output folder selection;
- `CreateBuildPlan` + structured `RunPreflight` UI;
- async `ExecuteBuildPlan`;
- incremental NDJSON reader и normalized progress/speed display;
- cooperative `CancelBuild` и close-during-build cancellation flow;
- structured error-code mapping;
- result path/SHA/log actions;
- GUI local logging + frontend exception boundary;
- hidden `--backend-smoke`;
- MSTest contract/event-reader coverage;
- `Build-Gui.ps1` self-contained `win-x64` publish tooling;
- release package integration preserving TUI/CLI/backend.

## Сохранено

Dynamic UUP catalog, recommendation engine, BuildPlan v1, preflight, elevation, UUP download/conversion/DISM, ISO validation, cancellation implementation, cache/resume, TUI/CLI, Backend Contract v1 and PowerShell validation remain backend-owned.

## Validation terminology

`Implemented` означает наличие code/test/tooling, но не подтверждает фактический PASS в среде, где команды не запускались. Фактические результаты фиксируются отдельно в `VALIDATION_MATRIX`/PR.

## Требует Windows execution перед release

- .NET restore/build/test;
- Pester;
- PSScriptAnalyzer;
- PS5.1/PS7 backend smoke;
- `Build-Gui.ps1` publish;
- Full release validation;
- packaged GUI backend smoke;
- manual GUI smoke;
- желательно один real GUI E2E до ISO.

Агент не должен переводить эти пункты в PASS без реального запуска.

## Намеренно не реализовано

History, profiles, queue, cache-management GUI, updater, installer/MSIX, USB writer/Rufus, full theme/language settings, accounts/cloud, Windows customization/debloat, driver injection, TPM bypass, activation, custom UUP downloader/converter и GitHub Actions.

## Известные ограничения alpha.1

- runtime localization полностью не реализована; основной GUI русский;
- layout/UI polish ограничены MVP;
- real build остаётся тяжёлой manual validation procedure;
- Backend Contract transport остаётся local process + JSON/NDJSON files;
- external UUP dump API/conversion package может измениться.
