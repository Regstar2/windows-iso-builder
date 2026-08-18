<div align="center">

# Windows ISO Builder

Интерактивный клиент UUP dump для поиска, загрузки и автоматической сборки Windows ISO без ручной работы с сайтом, UUID, SKU и `ConvertConfig.ini`.

**Русский** · [English](README_EN.md)

[Быстрый старт](#быстрый-старт) · [Backend Contract](#backend-contract) · [Надёжность](#надёжность-и-отмена) · [Документация](#документация)

</div>

## О проекте

Windows ISO Builder использует динамический каталог UUP dump, а файлы Windows получает с Microsoft Windows Update/CDN через сгенерированный UUP dump conversion package. Проект не содержит зашитого каталога Windows и не реализует собственный UUP downloader/converter.

TUI/CLI и machine-readable Backend Contract используют один PowerShell backend.

## Статус проекта

Текущая версия — **`0.2.2-alpha.1`**.

- ApplicationVersion: `0.2.2-alpha.1`;
- PowerShell ModuleVersion: `0.2.2`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`0.2.2-alpha.1` — второй архитектурный релиз перед будущим GUI. GUI, WPF/WinUI и C# в этой версии отсутствуют намеренно.

## Возможности

- динамический поиск Windows builds и quick mode без hardcoded build numbers;
- динамические languages/editions, multi-edition через virtual editions;
- `install.wim` и `install.esd`;
- API/package/UUP cache и штатный `aria2` resume;
- compact console progress и полный `converter-*.log`;
- build/elevated/execution logs, SHA-256 и JSON metadata;
- TUI и non-interactive PowerShell CLI;
- Backend Contract v1 с JSON response/request и NDJSON events;
- `RunPreflight` с агрегированным machine-readable report;
- local preflight до UAC и повторный authoritative preflight в worker;
- structured error taxonomy с source-level error codes и optional `details`;
- `CancelBuild` и cooperative cancellation по `requestId`;
- отмена через elevation boundary;
- PID-rooted termination только собственного process tree;
- сохранение partial UUP cache/work directory после отмены.

## Быстрый старт

1. Распакуйте проект или release ZIP.
2. Запустите `Start-Builder.cmd`.
3. Выберите обычный поиск или quick mode.
4. Выберите язык, редакции и WIM/ESD.
5. До UAC приложение выполнит local preflight. При fatal problem UAC не открывается.
6. При успешном preflight подтвердите UAC и дождитесь ISO.

По умолчанию рабочий кеш: `C:\UUP-ISO-Work`. Готовые ISO сохраняются в выбранный output directory.

## Требования

- Windows 10/11 x64 для реальной ISO build;
- Windows PowerShell 5.1 или PowerShell 7;
- DISM, `Expand-Archive`, `Get-FileHash`;
- права администратора для UUP/conversion stage;
- conservative minimum: 40 GiB для cache/work и 8 GiB для output;
- доступ к UUP dump и Microsoft Windows Update/CDN.

`Mount-DiskImage` используется для более глубокой post-build проверки, но его отсутствие само по себе является warning, а не fatal preflight failure.

## Надёжность и отмена

`RunPreflight` не останавливается на первой независимой проблеме. Он возвращает `ready` и массив `checks` со стабильными `id`, `status`, `severity`, `code`, `message`, `data`. `availableBytes` и `requiredBytes` передаются числами.

Обычная неготовность environment — успешная Backend Contract operation (`success=true`, `data.ready=false`), а не transport failure.

`ExecuteBuildPlan` использует свой `requestId` как operation id. `CancelBuild` принимает `targetRequestId` и `cacheDirectory`, создавая control marker с именем на основе SHA-256 request id. Raw request id никогда не становится filesystem path.

`CancelBuild` означает только **«запрос отмены принят»**. Фактическая остановка подтверждается final response/event целевой `ExecuteBuildPlan` operation с `BUILD_CANCELLED`/`cancelled`.

При отмене managed runner завершает process tree, корнем которого является PID процесса, запущенного самим Windows ISO Builder. Поиск и kill по имени `aria2`, `dism` или другого процесса не используется. Partial downloads и work directory сохраняются для resume.

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

Schema остаётся `1`: новые команды/error codes/optional fields являются backward-compatible расширением v1. BuildPlan Schema также остаётся `1`; cancellation относится к runtime ExecutionContext и не записывается в постоянный BuildPlan.

Полный contract: [docs/BACKEND_CONTRACT.md](docs/BACKEND_CONTRACT.md).

## Безопасность

- explicit command allowlist;
- нет `Invoke-Expression`/eval;
- request считается untrusted input;
- cancellation path строится только через SHA-256 request id;
- process termination выполняется только по PID собственного process tree;
- preflight probe использует уникальный temporary file и удаляет его;
- machine responses не должны раскрывать tokens, signed UUP URLs, product keys или Exception object graph.

## Тестирование

Проект использует локальные Pester tests и PSScriptAnalyzer. GitHub Actions намеренно не являются release gate.

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1

$issues = @(Invoke-ScriptAnalyzer `
  -Path . `
  -Recurse `
  -Settings .\.psscriptanalyzer.psd1)
```

Основные reliability tests работают на mocks и не скачивают Windows. Реальный process-tree smoke test является opt-in (`WIB_RUN_PROCESS_CANCELLATION_SMOKE=1`) и использует dummy PowerShell child process, а не aria2/DISM.

## Документация

- [Backend Contract v1](docs/BACKEND_CONTRACT.md)
- [Требования](REQUIREMENTS.md)
- [Архитектура](docs/ARCHITECTURE.md)
- [Статус реализации](docs/IMPLEMENTATION_STATUS.md)
- [История изменений](CHANGELOG.md)
- [Release notes](docs/releases/)
- [Безопасность](SECURITY.md)
- [Участие в разработке](CONTRIBUTING.md)

## Ограничения

- `0.2.2-alpha.1` остаётся alpha;
- GUI, WPF/WinUI, queue/history/profiles, updater, USB/Rufus integration и dynamic disk estimator не реализованы;
- transport Backend Contract — local JSON/NDJSON files + PowerShell process, не HTTP server;
- full Windows 10/11 E2E matrix не является частью этого релиза;
- внешний UUP dump API/conversion package может измениться.

## Лицензия

Собственный код Windows ISO Builder распространяется по [MIT License](LICENSE). Windows, UUP dump и сторонние инструменты имеют собственные лицензии и условия использования.
