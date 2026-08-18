# Архитектура

## Общая модель

`0.2.1-alpha.1` сохраняет существующий pipeline:

```text
UUP dump API
      ↓
PowerShell backend
      ↓
BuildPlan
      ↓
elevated worker
      ↓
UUP converter / aria2 / DISM
      ↓
ISO
```

Над тем же backend добавлен отдельный внешний адаптер:

```text
                  ┌── TUI
                  │
PowerShell Core ──┼── CLI
                  │
                  └── Backend Contract v1
                            ↓
                         future GUI
```

Backend Contract не является вторым UUP/backend implementation. Он вызывает существующие core-функции и преобразует вход/выход в стабильные DTO.

## Entry points

- `Start-Builder.cmd` → основной пользовательский запуск;
- `Start-Builder.ps1` → TUI, non-interactive CLI и существующий elevated child mode;
- `Invoke-WibBackend.ps1` → отдельная machine-readable entry point с `RequestFile`, `ResponseFile` и optional `EventFile`.

`Invoke-WibBackend.ps1` намеренно ASCII-only, чтобы прямой запуск Windows PowerShell 5.1 не зависел от обработки UTF-8 without BOM.

## Версионирование

Три версии независимы:

- ApplicationVersion: читается из корневого `VERSION` (`0.2.1-alpha.1`);
- PowerShell module manifest: `0.2.1`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`VERSION` является единым runtime source ApplicationVersion. Модуль использует это значение в UI, BuildPlan/ISO metadata и сетевых User-Agent. Старое `$script:WibVersion` сохранено только как compatibility alias внутри модуля.

## Слои модуля

- `Common.ps1` — общие path/JSON/security/error helpers;
- `BackendEvents.ps1` — reusable best-effort structured event sink и internal-stage mapping;
- `Cache.ps1` — файловый кеш API, пакетов и рабочих данных;
- `UupApi.ps1` — `listid`, `listlangs`, `listeditions`, нормализация и фильтрация каталога;
- `Plan.ps1` — BuildPlan Schema v1 и validation;
- `Selection.ps1` — консольный пользовательский интерфейс и catalog selection helpers;
- `Recommendation.ps1` — общая dynamic quick-mode recommendation logic для TUI и Backend Contract;
- `Builder.ps1` — host requirements, UUP package, converter, ISO verification и основной build workflow;
- `Elevation.ps1` — существующий plan/result protocol между parent/elevated child, build error context и optional event forwarding;
- `Application.ps1` — интерактивный и неинтерактивный human workflows;
- `ConsoleProgress.ps1` — единый converter-output parser, console renderer и публикация normalized progress events;
- `BackendContract.ps1` — validation и explicit DTO conversion;
- `BackendCommands.ps1` — Backend Contract envelopes и allowlisted command dispatcher.

Private scripts по-прежнему загружаются модулем явно как UTF-8 для Windows PowerShell 5.1. Наружу не экспортируется весь private API: для machine use добавлен только `Invoke-WibBackendRequest`.

## Backend Contract transport

Клиент создаёт UTF-8 JSON request, запускает `Invoke-WibBackend.ps1`, читает атомарно записанный UTF-8 JSON response и при необходимости следит за UTF-8 NDJSON event stream.

Human stdout не является API. Contract не зависит от:

- `Write-Host`;
- `Write-Progress`;
- `Start-Transcript`;
- локализованных сообщений;
- raw `aria2`/converter lines.

Response пишется через общий atomic JSON helper: временный файл создаётся рядом с destination и затем заменяет destination.

## Request validation и dispatch

Request считается недоверенным. Contract проверяет schema version, request id, command, object/array/string/bool/enum values, language pattern и paths.

Выполнение команды реализовано статическим `switch ($Command)` по allowlist. JSON не может указать PowerShell function name, script path или произвольный код. `Invoke-Expression` не используется.

## DTO boundary

Contract не сериализует внутренние PowerShell object graphs напрямую. Явные converters формируют DTO для:

- build;
- language;
- edition;
- BuildPlan response/input;
- build result;
- structured error;
- event.

Contract property names — английский camelCase. Такие внутренние свойства, как `BuildVersion`, PowerShell remoting metadata, Exception objects и ScriptMethods, не являются частью schema.

## Structured errors

Простой PS5.1-compatible error annotation использует `Exception.Data`:

- `WibErrorCode`;
- `WibStage`;
- `WibPublicMessage`;
- `WibLogPath`;
- `WibWorkDirectory`;
- `WibExecutionLogPath` там, где применимо.

Это позволяет error mapper возвращать стабильный machine code независимо от локализованного `Exception.Message`, не вводя ненужную class hierarchy. Полный stack trace сохраняется в human/elevated diagnostics, но не становится основным machine message.

## Recommended build

Quick-mode selection logic выделена из `Application.ps1` в reusable `Recommendation.ps1`. И TUI, и `GetRecommendedBuild` вызывают одну функцию.

Каталог остаётся динамическим. Конкретные Windows release/build numbers не зашиваются. Существующее правило Windows 11 — предпочитать подходящий mainstream stable H2 — сохранено.

## BuildPlan и elevation

Contract `CreateBuildPlan` вызывает существующий `New-WibBuildPlan`; параллельной plan-структуры нет. `ValidateBuildPlan` использует существующую validation logic. `ExecuteBuildPlan` передаёт восстановленный BuildPlan в текущий `Invoke-WibBuildPlan`.

Существующий elevated protocol продолжает использовать JSON plan/result files. Для machine build он лишь получает optional `BackendRequestId`/`BackendEventFile`, чтобы elevated child мог append events в тот же stream. Отдельный elevation protocol не создаётся.

## Structured progress

`ConsoleProgress.ps1` остаётся единственным parser converter output:

```text
converter output
      ↓
ConvertFrom-WibConverterProgressLine
      ↓
normalized progress state
      ├── Set-WibConverterProgress → Write-Progress
      └── Publish-WibEvent → NDJSON
```

Normalized state содержит overall percent, optional download detail percent, optional speed text/bytes per second и contract stage. Overall event progress clamp-ится так, чтобы не идти назад. Неудача speed parsing или event file I/O не является build failure.

Raw converter lines продолжают сохраняться только в converter log.

## Поток данных TUI/CLI

1. Пользователь вводит поиск или выбирает quick mode.
2. `Search-WibBuilds` получает каталог UUP dump.
3. Фильтруются architecture/Preview/entry type.
4. Для UUID загружаются languages/editions.
5. Создаётся BuildPlan Schema v1.
6. При необходимости plan передаётся existing elevated child.
7. UUP dump package запускает aria2/converter в рабочем каталоге.
8. ISO проверяется, хешируется и получает metadata.
9. Existing structured elevated result возвращается parent.

## Кеш и resume

Ключ рабочего каталога строится из UUID, языка и базовой редакции. Повторный запуск использует тот же каталог, поэтому `aria2` может продолжать незавершённые загрузки. Backend Contract вызывает те же функции и не меняет caching/resume semantics.

## Граница доверия

Проект доверяет только структурированным данным UUP dump и содержимому generated ZIP после проверки обязательных файлов. Backend request дополнительно рассматривается как untrusted local input.

Machine response/event не должны раскрывать signed UUP URLs, product keys, tokens или произвольные internal object graphs.

## Проверки

Проект использует локальные Pester-тесты и PSScriptAnalyzer. GitHub Actions не являются release gate. Contract tests используют mocks и не выполняют реальную загрузку Windows.
