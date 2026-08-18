# Требования к Windows ISO Builder

## Назначение

Windows ISO Builder — PowerShell-клиент UUP dump для интерактивной и автоматизированной сборки Windows ISO. Каталог Windows остаётся динамическим; собственный UUP downloader/converter не разрабатывается.

Версия `0.2.2-alpha.1` укрепляет Backend Contract v1 перед будущим GUI: добавляет reusable preflight, расширенную error taxonomy и cooperative cancellation без изменения SchemaVersion.

## Версионирование

- ApplicationVersion: `0.2.2-alpha.1`, единый source of truth — `VERSION`;
- ModuleVersion: `0.2.2`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

Новые команды, error codes и optional properties должны оставаться backward-compatible расширением Backend Contract v1. Cancellation — runtime concern и не требует BuildPlan Schema v2.

## Сохранённые требования backend

1. Каталог builds/languages/editions загружается динамически с UUP dump.
2. Production code не содержит hardcoded Windows release catalog.
3. TUI, CLI, quick mode, WIM/ESD, virtual editions, caching/resume и elevation остаются совместимыми.
4. Console progress и structured progress используют один converter parser.
5. BuildPlan описывает, **что** собирать; runtime ExecutionContext описывает, **как** контролировать конкретный запуск.
6. Backend Contract не парсит `Write-Host`, transcript, localized Exception.Message или raw aria2 output для классификации ошибок.

## Preflight

Один reusable engine `Invoke-WibPreflight` используется Backend Contract и build workflow.

Local checks минимум:

- Windows host;
- 64-bit OS;
- PowerShell 5.1+;
- `cmd.exe`;
- `dism.exe`;
- `Expand-Archive`;
- `Get-FileHash`;
- optional `Mount-DiskImage` как warning;
- cache/output path preparation and write probe;
- cache/work >= 40 GiB;
- output >= 8 GiB.

Пороговые значения хранятся централизованно. Disk report содержит `availableBytes` и `requiredBytes`.

`RunPreflight` агрегирует независимые проверки. Fatal checks задают `ready=false`; warnings не блокируют build. Неготовое environment возвращается как `success=true`, `data.ready=false`.

При `onlineChecks=true` выполняется ограниченная по timeout проверка официального UUP dump API без скачивания UUP set. При `onlineChecks=false` сетевой запрос не выполняется.

Перед UAC выполняется local non-privileged preflight. Elevated worker повторяет критические проверки через тот же engine непосредственно перед build.

## Structured errors

Существующий PS5.1-compatible metadata mechanism (`Exception.Data` / `New-WibErrorException`) остаётся источником structured classification. Error code назначается в месте возникновения failure, а не по тексту сообщения.

Taxonomy сохраняет прежние codes и дополнительно включает:

`UNSUPPORTED_HOST`, `REQUIRED_COMPONENT_MISSING`, `PATH_NOT_WRITABLE`, `DISK_SPACE_LOW`, `NETWORK_ERROR`, `UUP_PACKAGE_DOWNLOAD_FAILED`, `UUP_PACKAGE_INVALID`, `DOWNLOAD_FAILED`, `CONVERTER_FAILED`, `DISM_FAILED`, `ISO_NOT_FOUND`, `ISO_VALIDATION_FAILED`, `ELEVATION_CANCELLED`, `BUILD_CANCELLED`.

`error.details` может содержать только controlled scalar/DTO data, например path, bytes, component, exitCode и targetRequestId. Exception object, tokens, signed download URLs, secrets и product keys не сериализуются.

## Cancellation

- `ExecuteBuildPlan.requestId` — публичный operation id;
- request id должен быть уникальным для конкретной operation;
- `CancelBuild` принимает `targetRequestId` и `cacheDirectory`;
- control filename строится по SHA-256 request id и не допускает path traversal;
- marker создаётся с `CreateNew`, имеет проверяемый owned format и не перезаписывает colliding user file;
- cleanup удаляет только валидный marker для ожидаемого request hash;
- pre-existing valid marker не удаляется при initialization, поэтому cancel-before-worker race не теряется;
- cancellation context не добавляется в permanent BuildPlan fields;
- cancellation checks выполняются перед/после preflight, перед UAC, на download/retry/extraction/converter/verify boundaries и перед final success;
- retry delays являются cancellable и не используют busy loop;
- cancellation проходит через existing elevated plan/result boundary;
- final cancellation возвращает `BUILD_CANCELLED` с фактической normalized stage;
- state.json различает `cancelled` и `failed`;
- cancellation не удаляет UUP cache/work data и не запрещает aria2 resume.

## Managed child process

Длительный UUP batch запускается через managed runner, который:

- знает PID созданного им root process;
- читает stdout/stderr и сохраняет существующую progress/logging семантику;
- опрашивает central cancellation context;
- при cancellation завершает только process tree этого PID;
- на Windows использует `taskkill.exe /PID <pid> /T /F` как PS5.1-compatible tree termination mechanism;
- никогда не использует `/IM`, `Get-Process aria2`, `Get-Process dism` или другой kill-by-name;
- закрывает process/stream handles и удаляет только свои temporary redirection files.

## Backend Contract v1 commands

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`, `RunPreflight`, `CancelBuild`.

`CancelBuild` acknowledgement означает только принятие запроса отмены. Остановка target build подтверждается final target response/event.

## Security

- request/cancellation input считается недоверенным;
- dispatch — explicit allowlist;
- нет eval/`Invoke-Expression`;
- request id не используется как raw filesystem path;
- CancelBuild не выбирает arbitrary filename и не перезаписывает/удаляет foreign collision;
- preflight probe создаётся через unique `CreateNew` file и удаляется;
- process termination применяется только к PID собственного runner;
- machine DTO не содержит secrets или arbitrary internal object graphs.

## Compatibility

Обязательна совместимость:

- Windows PowerShell 5.1 и PowerShell 7;
- `Start-Builder.cmd`, `Start-Builder.ps1`;
- TUI, non-interactive CLI и quick mode;
- текущие public module functions;
- BuildPlan Schema v1;
- existing JSON elevated plan/result protocol;
- console progress, converter/build/elevated/execution logs;
- cache/resume;
- WIM/ESD и virtual editions.

Standalone `Invoke-WibBackend.ps1` остаётся ASCII-only.

## Validation

Release gate выполняется локально, без GitHub Actions:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1

$issues = @(Invoke-ScriptAnalyzer `
  -Path . `
  -Recurse `
  -Settings .\.psscriptanalyzer.psd1)
```

Backend/preflight/cancellation tests не должны скачивать Windows. Process-tree integration используется как optional controlled Windows smoke test с dummy process.

## Не входит в `0.2.2-alpha.1`

GUI, WPF, WinUI, C#, installer, updater, queue, history, profiles, USB writer, Rufus integration, auto-update download, dynamic disk estimator, custom UUP API/downloader/converter, GitHub Actions и full Windows 10/11 E2E matrix.
