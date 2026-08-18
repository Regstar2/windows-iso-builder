# Требования к Windows ISO Builder

## Назначение

Windows ISO Builder — интерактивный клиент UUP dump, который позволяет найти нужную сборку Windows, выбрать архитектуру, язык и редакции, а затем получить готовый ISO без ручной работы с сайтом и конвертером.

Ценность проекта состоит в пользовательском сценарии и надёжности. Собственный UUP-движок не разрабатывается. Начиная с `0.2.1-alpha.1` тот же PowerShell backend также предоставляет версионированный машиночитаемый Backend Contract для будущих frontend-клиентов.

## Обязательные требования основного backend

1. Каталог сборок загружается динамически во время выполнения.
2. Версии Windows и ссылки на них не перечисляются в исходном коде.
3. Поиск принимает названия выпусков и номера сборок, например `22H2`, `19045`, `22621`.
4. Отображаются название, номер сборки, архитектура, дата и UUID.
5. Preview/Insider-сборки отделяются от стабильных.
6. Языки и редакции запрашиваются для конкретного UUID.
7. Пользователь может выбрать одну или несколько редакций.
8. Поддерживаются `install.wim` и `install.esd`.
9. Полный цикл выполняется одной программой: пакет, загрузка UUP, конвертация, ISO, проверка, SHA-256.
10. Пользователь не редактирует `ConvertConfig.ini` и не вводит SKU вручную.
11. API-ответы, пакет конвертации и UUP-файлы кешируются.
12. Повторный запуск переиспользует уже загруженные файлы и штатные возможности `aria2` для продолжения незавершённых загрузок.
13. До крупной загрузки проверяются ОС, компоненты и свободное место.
14. Ошибка содержит этап, причину, путь к логу и сохранённому рабочему каталогу, когда эти данные доступны.
15. Сторонний конвертер запускается в коротком ASCII-пути; пользовательские пути с пробелами и кириллицей не должны ломать управляющую часть приложения.
16. Для каждого ISO создаются SHA-256 и JSON-метаданные.
17. Проверяются `boot.wim`, `install.wim` или `install.esd` и список образов, когда системные команды доступны.
18. Документация явно указывает зависимость от UUP dump и Microsoft CDN.

## Backend Contract v1

Backend Contract — отдельный слой над существующим PowerShell backend. Он не заменяет TUI/CLI и не дублирует UUP, BuildPlan, elevation или converter workflow.

Обязательные свойства версии `0.2.1-alpha.1`:

- отдельная entry point `Invoke-WibBackend.ps1`;
- Windows PowerShell 5.1 и PowerShell 7 compatibility;
- request/response через UTF-8 JSON-файлы;
- optional event stream через UTF-8 NDJSON;
- атомарная запись response;
- `schemaVersion`, `requestId`, `command`, `arguments` во входном envelope;
- `success` как обязательный boolean;
- `data` для успеха и `error` для ошибки;
- стабильные machine-oriented `error.code`, не зависящие от локализованного текста;
- только явный allowlist команд, без `Invoke-Expression`, eval и dynamic arbitrary dispatch;
- контролируемые DTO с английскими camelCase property names;
- reuse существующих `Search-WibBuilds`, `Get-WibLanguages`, `Get-WibEditions`, `New-WibBuildPlan`, `Assert-WibPlan`, `Invoke-WibBuildPlan` и quick-mode recommendation logic;
- structured progress строится тем же parser, который обслуживает console progress, без второго aria2 parser;
- event I/O является best-effort telemetry и не должно ломать саму сборку;
- Backend Contract request рассматривается как недоверенный вход.

Backend Contract SchemaVersion `1`, BuildPlan SchemaVersion `1` и ApplicationVersion — независимые сущности. Breaking change Backend Contract требует нового schema version; обычное изменение ApplicationVersion не меняет contract schema автоматически.

## Обязательные команды Backend Contract v1

- `GetVersion`;
- `SearchBuilds`;
- `GetRecommendedBuild`;
- `GetLanguages`;
- `GetEditions`;
- `CreateBuildPlan`;
- `ValidateBuildPlan`;
- `ExecuteBuildPlan`.

Минимальные error codes: `INVALID_REQUEST`, `UNSUPPORTED_SCHEMA`, `INVALID_COMMAND`, `INVALID_ARGUMENT`, `BUILD_NOT_FOUND`, `LANGUAGE_NOT_FOUND`, `EDITION_NOT_FOUND`, `UUP_API_ERROR`, `UUP_API_UNAVAILABLE`, `INVALID_BUILD_PLAN`, `ELEVATION_FAILED`, `BUILD_FAILED`, `INTERNAL_ERROR`.

## Надёжность и безопасность

- повышение прав выполняется только для стадии сборки;
- программа не меняет глобальную Execution Policy;
- программа не отключает UAC или антивирус;
- удаляются только собственные каталоги кеша;
- сетевые запросы имеют таймаут, повторные попытки и fallback на устаревший кеш;
- готовые ISO не удаляются при очистке кеша;
- внешние ошибки не маскируются сообщением только `Exit code: 1`;
- подробный вывод конвертера сохраняется в логах, даже если в интерактивной консоли показывается компактный прогресс;
- machine API не возвращает signed UUP download URLs, product keys, access tokens или произвольные exception object graphs;
- frontend не должен парсить `Write-Host`, `Write-Progress`, transcript, локализованный текст или raw aria2 output.

## Обратная совместимость

Версия `0.2.1-alpha.1` должна сохранять работоспособность:

- `Start-Builder.cmd`;
- `Start-Builder.ps1`;
- `Start-WibInteractive`;
- `Start-WibNonInteractive`;
- `Search-WibBuilds`;
- `Get-WibLanguages`;
- `Get-WibEditions`;
- `New-WibBuildPlan`;
- `Invoke-WibBuildPlan`;
- quick mode;
- UAC/elevation;
- console progress;
- существующих логов, кеша и resume behavior.

## Критерии публичной alpha-версии

Перед выпуском публичной alpha должны проходить актуальные локальные Pester-тесты и не должно быть блокирующих PSScriptAnalyzer проблем. Реальная end-to-end проверка ISO остаётся отдельной проверкой и не заменяется Backend Contract tests.

Для `0.2.1-alpha.1` contract tests не должны скачивать Windows: сетевые и build-команды мокируются. Отдельно проверяются JSON envelopes, DTO, error mapping, allowlist, event sequence/progress, PS5.1-safe standalone entry point и regression текущего console progress.

GitHub Actions не являются release gate проекта.

## Не входит в `0.2.1-alpha.1`

- GUI, WPF, WinUI или C# rewrite;
- собственный Windows Update/UUP downloader или converter;
- updater;
- запись USB/Rufus integration;
- очередь, profiles, history и cache GUI;
- полный cancellation subsystem;
- полный preflight следующей версии;
- полный taxonomy всех возможных ошибок;
- GitHub Actions;
- распространение готовых ISO Windows;
- активация Windows или обход лицензирования.
