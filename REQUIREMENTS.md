# Требования к Windows ISO Builder

## Назначение

Windows ISO Builder — PowerShell-клиент UUP dump для интерактивной и автоматизированной сборки Windows ISO. Каталог Windows остаётся динамическим; собственный UUP downloader/converter не разрабатывается.

Версия `0.2.3-alpha.1` не является feature release. Её цель — сделать существующий backend воспроизводимо проверяемым перед началом GUI и зафиксировать Backend Contract v1 / BuildPlan v1 как baseline интеграции.

## Версионирование

- ApplicationVersion: `0.2.3-alpha.1`, единый source of truth — `VERSION`;
- ModuleVersion: `0.2.3`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

Schema не повышается без breaking change. Additive optional properties/error codes/event types остаются допустимыми расширениями v1.

## Сохранённые требования backend

1. Каталог builds/languages/editions загружается динамически с UUP dump.
2. Production code не содержит hardcoded Windows release catalog.
3. TUI, CLI, quick mode, WIM/ESD, virtual editions, caching/resume и elevation остаются совместимыми.
4. Console progress и structured progress используют один converter parser.
5. BuildPlan описывает, что собирать; runtime ExecutionContext управляет конкретным запуском.
6. Backend Contract не парсит `Write-Host`, transcript, localized Exception.Message или raw aria2 output для классификации ошибок.
7. Windows PowerShell 5.1 остаётся обязательным target runtime; PowerShell 7 поддерживается как совместимая среда.

## Backend Contract v1 baseline

Стабильный набор команд первого GUI:

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`, `RunPreflight`, `CancelBuild`.

Regression tests должны защищать semantic contract, а не byte-for-byte JSON. Обязательные поля response envelope, основных DTO и event envelope не могут исчезать в Schema v1. Новые optional fields разрешены.

Breaking rename/removal/semantic change после `v0.2.3` требует осознанного перехода на Backend Contract SchemaVersion 2.

## BuildPlan v1 compatibility

BuildPlan SchemaVersion остаётся `1`. В repository хранится небольшой fixture `tests/fixtures/build-plan-v1.json`, который должен:

- читаться текущим backend;
- проходить `ValidateBuildPlan`;
- round-trip через contract DTO без потери required data;
- оставаться Schema v1.

Volatile runtime state (`requestId`, event file, cancellation path/hash) не добавляется в persistent BuildPlan.

## Preflight

Один reusable engine `Invoke-WibPreflight` используется Backend Contract и build workflow.

Local checks включают Windows host, 64-bit OS, PowerShell, `cmd.exe`, DISM, archive/hash tools, optional `Mount-DiskImage`, path/write probes и централизованные disk minimums.

`RunPreflight` агрегирует независимые checks. Fatal checks задают `ready=false`; warnings не блокируют build. Неготовое environment возвращается как `success=true`, `data.ready=false`.

`onlineChecks=false` не выполняет сетевой запрос. Validation release smoke использует только offline mode.

## Structured errors

Source-level `Exception.Data` metadata остаётся источником structured classification. Backend не должен определять error code по локализованному message.

Сохраняются, среди прочих, коды:

`DISK_SPACE_LOW`, `PATH_NOT_WRITABLE`, `UUP_API_UNAVAILABLE`, `UUP_PACKAGE_INVALID`, `CONVERTER_FAILED`, `ISO_NOT_FOUND`, `BUILD_CANCELLED`.

Regression tests используют controlled failure injection/mocks и проверяют стабильность codes без создания настоящих OS/UUP failures.

## Cancellation

Существующий cooperative cancellation механизм сохраняется без переписывания:

- `ExecuteBuildPlan.requestId` — operation id;
- `CancelBuild` принимает `targetRequestId` и `cacheDirectory`;
- control filename строится по SHA-256 request id;
- cancellation checks выполняются на безопасных boundaries;
- managed child process завершается только по owned PID tree;
- partial UUP/work data сохраняются для resume;
- final cancellation классифицируется `BUILD_CANCELLED` и публикует `cancelled` event.

## Unified release validation

Обязателен единый entry point:

`tools/Invoke-ReleaseValidation.ps1`

По умолчанию он не должен:

- скачивать UUP set;
- собирать настоящий ISO;
- запускать многочасовой E2E;
- требовать UAC.

Quick validation включает минимум version/schema checks, module import, полный `tests/Run-Tests.ps1`, Backend `GetVersion`, offline `RunPreflight`, event/JSON smoke, package configuration/syntax и current-tree safety scan.

Full validation дополнительно делает release ZIP build/smoke, требует PSScriptAnalyzer, выполняет PS7 smoke при наличии `pwsh` и controlled process-tree smoke.

Отсутствие PowerShell 7 не является fatal. Отсутствие PSScriptAnalyzer в Full mode является FAIL; Quick mode может пометить его SKIPPED.

Validation возвращает deterministic exit code:

- `0` — все required checks прошли;
- non-zero — минимум один required check failed;
- optional skipped сами по себе не дают failure.

## Structured validation report

Validation создаёт machine-readable `validation-result.json` с версиями, timestamp, mode, success, checks и summary.

Report не должен содержать secrets, machine name, username или персональные absolute paths. Generated report не коммитится.

Validation report — developer/release tooling и не входит в Backend Contract Schema.

## Release package

`tools/New-ReleasePackage.ps1`:

- по умолчанию читает ApplicationVersion из `VERSION`;
- использует централизованный release allowlist/denylist;
- генерирует package staging;
- генерирует `release-manifest.json` только внутри package staging;
- создаёт ZIP и `.sha256`;
- не требует byte-for-byte reproducible ZIP, но logical file set должен быть deterministic для одного source version.

Release manifest содержит:

- `applicationVersion`;
- `moduleVersion`;
- `backendContractSchemaVersion`;
- `buildPlanSchemaVersion`.

Он не содержит timestamp, username, machine name, absolute local path или secrets.

## Source validation != release validation

Green source tests не означают, что release ZIP корректен.

Package validation отдельно проверяет:

- ZIP существует и открывается;
- checksum существует и совпадает;
- expected logical files присутствуют;
- unexpected/denied files отсутствуют;
- generated manifest имеет правильные версии;
- `Start-Builder.ps1` парсится;
- packaged module импортируется именно из Temp extract root;
- packaged Backend `GetVersion` работает;
- packaged offline `RunPreflight` работает;
- package safety scan не находит obvious secrets/personal paths/generated junk.

## Security scan scope

Локальный scan предназначен только для очевидных ошибок в текущих tracked files и текущем release package. Он проверяет common token prefixes, private-key blocks, очевидные access-token/client-secret assignments, персональные `C:\Users\...` пути и случайные generated/runtime artefacts.

Это не Git-history secret audit. История commits/reflog/forks требует отдельного специализированного аудита.

## Real E2E

Реальные Windows builds не запускаются автоматически validation tool.

Минимальная pre-GUI baseline-матрица:

1. Windows 11 x64, ru-RU, Core + Professional, ESD — ранее Confirmed baseline;
2. Windows 10 x64, Professional, ru-RU/en-US, ESD — Not run до фактической проверки;
3. Windows 11 x64, одна обычная edition, WIM — Not run до фактической проверки.

Не требуется полный Cartesian product, ARM64/x86 matrix или отдельный многогигабайтный cancellation/resume E2E.

Подробности: `docs/VALIDATION_MATRIX.md`.

## GUI integration boundary

Будущий GUI работает только через:

- `Invoke-WibBackend.ps1`;
- Backend Contract Schema v1;
- BuildPlan Schema v1;
- `RunPreflight`;
- `ExecuteBuildPlan`;
- `CancelBuild`;
- `requestId`;
- NDJSON event stream;
- structured error codes.

GUI не вызывает private PowerShell functions, не парсит `Write-Host`, aria2 output или localized error messages.

## Не входит в `0.2.3-alpha.1`

GUI, WPF, WinUI, C#, installer, MSIX, updater, queue, history, profiles, USB writer, Rufus integration, dynamic disk estimator, driver injection, Windows customization/debloat, TPM bypass, activation, custom UUP downloader/converter и GitHub Actions.
