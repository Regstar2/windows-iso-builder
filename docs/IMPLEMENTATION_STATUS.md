# Статус реализации

## Текущая версия

`0.2.1-alpha.1` — архитектурная публичная alpha перед будущим GUI.

Версии разделены:

- ApplicationVersion: `0.2.1-alpha.1`;
- PowerShell module manifest: `0.2.1`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

GUI в этой версии намеренно отсутствует.

## Реализовано ранее и сохранено

- динамический каталог UUP dump и свободный поиск;
- быстрый выбор рекомендуемой стабильной Windows 11 или Windows 10 без зашитого номера версии;
- filters architecture/Preview и классификация servicing records;
- postраничный TUI catalog;
- dynamic languages/editions;
- интерактивный TUI и non-interactive PowerShell CLI;
- BuildPlan и безопасная передача в elevated process;
- structured elevated result и подробная диагностика;
- execution/elevated/converter/build logs;
- API/package/UUP cache и штатный `aria2` resume;
- WIM/ESD и virtual editions;
- SHA-256, JSON result metadata и ISO validation;
- Windows PowerShell 5.1 / PowerShell 7 compatible control code;
- локальные Pester tests и PSScriptAnalyzer workflow без GitHub Actions.

## Добавлено в `0.2.1-alpha.1`

- root `VERSION` как единый runtime source ApplicationVersion;
- `Invoke-WibBackend.ps1` как отдельная ASCII-only machine entry point;
- Backend Contract Schema v1 с JSON request/response envelopes;
- optional UTF-8 NDJSON event stream;
- stable structured error codes и mapping через PS5.1-compatible exception metadata;
- allowlisted dispatcher без arbitrary function execution;
- controlled camelCase DTO boundary;
- команды `GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`;
- reusable quick-mode recommendation service, общий для TUI и contract;
- общий structured event sink с no-op/best-effort behavior;
- reuse существующего converter progress parser для console renderer и structured events;
- optional event forwarding через существующий elevated plan/result protocol;
- dynamic ApplicationVersion в UUP API/package User-Agent;
- Backend Contract Pester regression tests без реальной загрузки Windows;
- документация Backend Contract RU/EN и release notes.

## Backend Contract guarantees v1

- `requestId` возвращается без изменения и присутствует в events;
- `success=true` возвращает `data`, `success=false` — `error`;
- `error.code` не требует parsing локализованного message;
- contract не использует human console output как transport;
- raw aria2 lines не являются частью event schema;
- BuildPlan Schema остаётся `1`;
- existing TUI/CLI используют тот же backend;
- unknown optional properties будущих v1-compatible ответов должны игнорироваться клиентом.

## Подтверждено предыдущей реальной ручной проверкой

Для основной build-системы до этой архитектурной версии ранее были подтверждены:

- end-to-end Windows 11 x64 ru-ru до готового ISO;
- multi-edition Core + Professional;
- UAC/elevated process;
- создание/отображение итогового ISO;
- build/converter/elevated/execution logs;
- structured elevated failure diagnostics.

Эти предыдущие проверки подтверждают существующий build pipeline, но не заменяют обязательный запуск актуального test suite для `0.2.1-alpha.1` перед релизом.

## Проверки `0.2.1-alpha.1`

Обязательные локальные проверки перед release:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\.psscriptanalyzer.psd1
```

Дополнительно должны быть выполнены `GetVersion` smoke tests через `Invoke-WibBackend.ps1` как минимум в Windows PowerShell 5.1 и, если доступен, PowerShell 7.

Backend Contract tests мокируют UUP API/build execution и поэтому не скачивают Windows.

## Не реализовано намеренно

- GUI/WPF/WinUI;
- C# rewrite;
- updater;
- очередь сборок;
- profiles/history/cache GUI;
- запись ISO на USB и Rufus integration;
- полный cancellation subsystem;
- полный preflight следующего релиза;
- полный taxonomy всех потенциальных ошибок;
- собственный UUP downloader/converter;
- GitHub Actions.

## Известные ограничения

- Backend Contract v1 использует local process + file transport, а не HTTP/RPC server;
- event stream — best-effort telemetry; невозможность записать event не должна ломать build;
- progress зависит от строк, которые умеет распознавать существующий converter parser; неизвестные строки просто логируются;
- speed bytes/sec публикуется только когда speed text безопасно распознан;
- полный набор field-level validation diagnostics отложен;
- внешний UUP dump API/converter format может измениться;
- полная реальная матрица Windows versions/languages/editions/WIM/ESD не заявляется.
