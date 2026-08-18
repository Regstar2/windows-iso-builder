<div align="center">

# Windows ISO Builder

Интерактивный PowerShell-клиент UUP dump для поиска, загрузки и автоматической сборки Windows ISO без ручной работы с сайтом, UUID, SKU и `ConvertConfig.ini`.

**Русский** · [English](README_EN.md)

[Быстрый старт](#быстрый-старт) · [Backend Contract](#backend-contract) · [Проверка релиза](#проверка-релиза) · [Документация](#документация)

</div>

## О проекте

Windows ISO Builder использует динамический каталог UUP dump, а файлы Windows получает с Microsoft Windows Update/CDN через сгенерированный UUP dump conversion package. Проект не содержит зашитого каталога Windows и не реализует собственный UUP downloader/converter.

TUI, non-interactive CLI и machine-readable Backend Contract используют один PowerShell backend.

## Статус проекта

Текущая версия — **`0.2.3-alpha.1`**.

- ApplicationVersion: `0.2.3-alpha.1`;
- PowerShell ModuleVersion: `0.2.3`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`0.2.3-alpha.1` — последний backend-focused validation release перед началом `v0.3.0` GUI. GUI, WPF/WinUI и C# здесь намеренно отсутствуют.

## Возможности

- динамический поиск Windows builds и quick mode без hardcoded build numbers;
- динамические languages/editions, multi-edition через virtual editions;
- `install.wim` и `install.esd`;
- API/package/UUP cache и штатный `aria2` resume;
- compact console progress и полный `converter-*.log`;
- build/elevated/execution logs, SHA-256 и JSON metadata;
- TUI и non-interactive PowerShell CLI;
- Backend Contract v1 с JSON request/response и NDJSON events;
- `RunPreflight` с агрегированным machine-readable report;
- local preflight до UAC и повторный authoritative preflight в worker;
- structured error taxonomy с source-level error codes и optional `details`;
- `CancelBuild` и cooperative cancellation по `requestId`;
- отмена через elevation boundary;
- PID-rooted termination только собственного process tree;
- сохранение partial UUP cache/work directory после отмены;
- локальный release validation workflow, который отдельно проверяет source checkout и готовый release ZIP.

## Быстрый старт

1. Скачайте и распакуйте release ZIP.
2. Запустите `Start-Builder.cmd`.
3. Выберите обычный поиск или quick mode.
4. Выберите язык, редакции и WIM/ESD.
5. До UAC приложение выполнит local preflight. Fatal problem не должна открывать elevation prompt.
6. При успешном preflight подтвердите UAC и дождитесь ISO.

Рабочий кеш по умолчанию: `C:\UUP-ISO-Work`. Готовые ISO сохраняются в выбранный output directory.

## Требования

- Windows 10/11 x64 для реальной ISO build;
- Windows PowerShell 5.1 или PowerShell 7;
- DISM, `Expand-Archive`, `Get-FileHash`;
- права администратора для UUP/conversion stage;
- conservative minimum: 40 GiB для cache/work и 8 GiB для output;
- доступ к UUP dump и Microsoft Windows Update/CDN.

`Mount-DiskImage` используется для более глубокой post-build проверки, но его отсутствие само по себе является warning, а не fatal preflight failure.

## Надёжность и отмена

`RunPreflight` возвращает `ready` и массив `checks` со стабильными `id`, `status`, `severity`, `code`, `message`, `data`. Обычная неготовность environment — успешная Backend Contract operation (`success=true`, `data.ready=false`), а не transport failure.

`ExecuteBuildPlan` использует свой `requestId` как operation id. `CancelBuild` принимает `targetRequestId` и `cacheDirectory`. Control marker строится по SHA-256 request id; raw request id не используется как filesystem path.

`CancelBuild` означает только принятие запроса отмены. Фактическая остановка подтверждается final response/event целевой `ExecuteBuildPlan` operation с `BUILD_CANCELLED`/`cancelled`.

Managed runner завершает только process tree, корнем которого является PID процесса, запущенного самим Windows ISO Builder. Поиск/kill по имени `aria2`, `dism` или другого процесса не используется. Partial downloads и work directory сохраняются для resume.

## Использование CLI

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1 `
  -NonInteractive `
  -Search 22H2 `
  -Architecture amd64 `
  -Language ru-ru `
  -Editions Core,Professional `
  -ImageFormat ESD
```

## Backend Contract

Machine entry point:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson
```

Backend Contract Schema v1 поддерживает:

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`, `RunPreflight`, `CancelBuild`.

После `v0.2.3` этот Contract v1 и BuildPlan v1 считаются baseline интерфейсом для первого GUI. Additive optional fields остаются допустимыми; breaking changes требуют отдельного SchemaVersion.

Полный contract: [docs/BACKEND_CONTRACT.md](docs/BACKEND_CONTRACT.md).

## Проверка релиза

Проект использует локальные Pester tests, PSScriptAnalyzer и единый validation entry point. GitHub Actions намеренно не являются release gate.

Быстрая проверка не скачивает UUP set и не собирает ISO:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1
```

Полный безопасный release smoke, включая временную сборку/распаковку ZIP и controlled process-tree test:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Validation пишет machine-readable `validation-result.json` и возвращает non-zero exit code при failure обязательной проверки. Generated report и `dist/` не предназначены для commit.

Source validation и release-package validation считаются разными слоями. Подробная фактическая матрица, включая реальные E2E статусы: [docs/VALIDATION_MATRIX.md](docs/VALIDATION_MATRIX.md).

## Release package

`tools/New-ReleasePackage.ps1` читает версию из `VERSION`, формирует ZIP и `.sha256`, а внутрь ZIP добавляет сгенерированный `release-manifest.json` с версиями приложения, модуля, Backend Contract и BuildPlan.

Release ZIP строится из централизованного allowlist и не должен содержать `tests`, `.git`, `.github`, `output`, `logs`, `dist`, cache, IDE state, `.project-rules` или user-specific files.

## Безопасность

- explicit Backend command allowlist;
- нет `Invoke-Expression`/eval;
- request считается untrusted input;
- cancellation path строится только через SHA-256 request id;
- process termination выполняется только по PID собственного process tree;
- machine responses не должны раскрывать tokens, signed UUP URLs, product keys или Exception object graph;
- release validation выполняет ограниченный scan текущих tracked files и package на очевидные secrets/personal paths.

Этот scan не является историческим аудитом Git history.

## Документация

- [Backend Contract v1](docs/BACKEND_CONTRACT.md)
- [Матрица проверки](docs/VALIDATION_MATRIX.md)
- [Требования](REQUIREMENTS.md)
- [Архитектура](docs/ARCHITECTURE.md)
- [Статус реализации](docs/IMPLEMENTATION_STATUS.md)
- [История изменений](CHANGELOG.md)
- [Release notes](docs/releases/)
- [Безопасность](SECURITY.md)
- [Участие в разработке](CONTRIBUTING.md)

## Ограничения

- `0.2.3-alpha.1` остаётся alpha;
- GUI, WPF/WinUI, queue/history/profiles, updater, USB/Rufus integration и dynamic disk estimator не реализованы;
- transport Backend Contract — local JSON/NDJSON files + PowerShell process, не HTTP server;
- реальный Windows 10 E2E и отдельный Windows 11 WIM baseline должны отмечаться как подтверждённые только после фактической ручной сборки;
- внешний UUP dump API/conversion package может измениться.

## Лицензия

Собственный код Windows ISO Builder распространяется по [MIT License](LICENSE). Windows, UUP dump и сторонние инструменты имеют собственные лицензии и условия использования.
