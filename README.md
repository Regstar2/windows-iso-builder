<div align="center">

# Windows ISO Builder

Интерактивный клиент UUP dump для поиска, загрузки и автоматической сборки Windows ISO без ручной работы с сайтом, UUID, SKU и `ConvertConfig.ini`.

**Русский** · [English](README_EN.md)

[Быстрый старт](#быстрый-старт) · [Backend Contract](#backend-contract) · [Документация](#документация) · [Ограничения](#ограничения)

</div>

## О проекте

Windows ISO Builder проводит пользователя через поиск сборки Windows, выбор архитектуры, языка, редакций и формата установочного образа. Каталог версий не хранится в исходном коде: данные запрашиваются у UUP dump, а файлы Windows загружаются с Microsoft Windows Update/CDN.

Техническое имя репозитория и корневого каталога — `windows-iso-builder`. Публичное название продукта — Windows ISO Builder.

Проект не заменяет UUP dump и не реализует собственный UUP-движок. Его задача — сократить ручной процесс до одного интерактивного сценария и предоставить стабильный машиночитаемый слой над тем же PowerShell backend.

## Статус проекта

Текущая версия — **`0.2.1-alpha.1`**. Версия manifest PowerShell-модуля — `0.2.1`; Backend Contract Schema и BuildPlan Schema имеют независимые версии `1`.

`0.2.1-alpha.1` — архитектурная alpha перед будущим GUI. GUI в этой версии отсутствует. Существующие TUI/CLI, UUP dump workflow, UAC/elevation, кеширование и конвертация сохраняются; добавлен отдельный JSON/NDJSON Backend Contract для будущих frontend-клиентов.

Подробная матрица реализации находится в [статусе реализации](docs/IMPLEMENTATION_STATUS.md).

## Возможности

- динамический поиск по названию релиза, номеру сборки или заголовку UUP dump;
- быстрый выбор рекомендуемой стабильной Windows 11 или Windows 10 x64 без просмотра каталога и без зашитого номера сборки;
- для Windows 11 quick mode предпочитает массовый стабильный `YYH2`-релиз специализированным H1-веткам, если подходящий H2 доступен;
- постраничный просмотр больших результатов поиска;
- Preview/Insider скрыты по умолчанию;
- динамическая загрузка языков и редакций;
- одна или несколько редакций через virtual editions;
- `install.esd` или `install.wim`;
- кеширование API, конвертационного пакета и UUP-файлов;
- штатное продолжение незавершённых загрузок средствами `aria2`;
- компактная console progress-индикация, полный raw output в `converter-*.log`;
- структурированная передача результата elevated-процесса родителю;
- execution/elevated/converter/build-логи;
- SHA-256 и JSON-метаданные результата;
- проверка структуры ISO через `Mount-DiskImage` и DISM;
- TUI и неинтерактивный PowerShell CLI;
- **Backend Contract v1**: JSON request/response, NDJSON events, стабильные error codes и отдельная machine entry point.

## Быстрый старт

1. Скачайте исходники или release ZIP и распакуйте их.
2. Запустите `Start-Builder.cmd`.
3. Для обычного режима выберите `Найти сборку и создать ISO`; для рекомендуемого стабильного выпуска — `Быстро скачать последнюю Windows`.
4. Выберите язык, редакции и формат образа.
5. Подтвердите UAC перед загрузкой и конвертацией.

Готовые файлы сохраняются в `output/`. Постоянный рабочий кеш по умолчанию расположен в `C:\UUP-ISO-Work`.

## Требования

- Windows 10 или Windows 11 x64 для реальной сборки ISO;
- Windows PowerShell 5.1 или PowerShell 7;
- права администратора на этапе загрузки и конвертации;
- не менее 35–50 ГБ свободного места;
- доступ к UUP dump и Microsoft Windows Update/CDN.

## Использование

Интерактивный режим сначала собирает параметры и только затем запрашивает повышение прав. Быстрый режим использует тот же reusable selector, который теперь доступен и Backend Contract; конкретные Windows release/build не фиксируются в production-коде.

Во время `uup_download_windows.cmd` подробные строки `aria2` и конвертера не используются как API. Один существующий parser формирует progress state: console renderer показывает его человеку, а structured event sink при наличии `EventFile` публикует DTO. Raw output остаётся в `output/logs/converter-*.log`.

Повторный запуск с той же сборкой, языком и базовой редакцией использует существующий рабочий каталог и штатный resume `aria2`.

## Команды

Неинтерактивный пример остаётся совместимым:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1 `
  -NonInteractive `
  -Search 22H2 `
  -Architecture amd64 `
  -Language ru-ru `
  -Editions Core,Professional `
  -ImageFormat ESD
```

### Backend Contract

`Invoke-WibBackend.ps1` — отдельная machine entry point и не заменяет `Start-Builder.ps1`. Запрос и ответ передаются через UTF-8 JSON-файлы; progress/стадии при необходимости пишутся в UTF-8 NDJSON.

Пример безопасного `GetVersion`:

```powershell
@'
{
  "schemaVersion": 1,
  "requestId": "smoke-get-version",
  "command": "GetVersion",
  "arguments": {}
}
'@ | Set-Content -LiteralPath .\request.json -Encoding UTF8

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson

Get-Content .\response.json -Raw
```

Backend Contract v1 поддерживает команды `GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`. Полное описание: [docs/BACKEND_CONTRACT.md](docs/BACKEND_CONTRACT.md).

## Архитектура

PowerShell backend остаётся источником истины для UUP API, BuildPlan, elevation и конвертации. Backend Contract — внешний адаптер над существующими функциями, а не второй backend. См. [архитектуру](docs/ARCHITECTURE.md).

## Безопасность

Программа не отключает антивирус, UAC или глобальную политику выполнения PowerShell. Backend request считается недоверенным: command ограничен allowlist, `Invoke-Expression` не используется, JSON не исполняется как код.

В публичные отчёты нельзя включать полные UUP signed URLs, ключи продукта, токены и персональные пути. См. [SECURITY.md](SECURITY.md).

## Диагностика

После ошибки TUI сохраняет журнал и показывает путь к нему. Machine API возвращает стабильный `error.code`; frontend не должен классифицировать ошибку по локализованному `error.message`.

Проверяйте доступность UUP dump/Microsoft CDN, свободное место и `build-*.log`, `converter-*.log`, execution/elevated logs конкретного запуска.

## Сборка

Компиляция не требуется. Основной пользовательский entry point — `Start-Builder.cmd`/`Start-Builder.ps1`; machine entry point — `Invoke-WibBackend.ps1`. Модуль находится в `src/WindowsISOBuilder/`.

## Тестирование

Проект использует **локальные** Pester-тесты и PSScriptAnalyzer; GitHub Actions не являются частью процесса проверки или выпуска.

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\.psscriptanalyzer.psd1
```

Backend Contract tests мокируют UUP/build операции и не скачивают Windows. Реальная ISO-сборка остаётся отдельной end-to-end проверкой.

## Документация

- [Backend Contract v1](docs/BACKEND_CONTRACT.md)
- [Требования](REQUIREMENTS.md)
- [Архитектура](docs/ARCHITECTURE.md)
- [Статус реализации](docs/IMPLEMENTATION_STATUS.md)
- [Миграция исходной v4](docs/SOURCE_V4_MIGRATION.md)
- [История изменений](CHANGELOG.md)
- [Release notes](docs/releases/)
- [Участие в разработке](CONTRIBUTING.md)

## Происхождение и благодарности

UUP dump предоставляет каталог, метаданные и пакет конвертации. Файлы Windows загружаются средствами этого пакета с серверов Microsoft Windows Update/CDN.

Проект не связан с Microsoft, не распространяет готовые ISO Windows, не активирует Windows и не обходит лицензирование.

## Ограничения

- `0.2.1-alpha.1` — ранняя архитектурная версия, а не стабильный релиз;
- GUI, WPF/WinUI, updater, USB/Rufus integration, queue/history/profiles и полный cancellation subsystem не реализованы;
- Backend Contract v1 не является сетевым HTTP API: transport основан на локальных JSON/NDJSON файлах и процессе PowerShell;
- полная taxonomy ошибок и расширенный preflight отложены на последующие версии;
- внешний API UUP dump и формат конвертационного пакета могут измениться;
- реальная матрица всех Windows/языков/редакций/WIM/ESD не гарантируется.

## Лицензия

Собственный код Windows ISO Builder распространяется по лицензии [MIT](LICENSE). Windows, UUP dump и сторонние инструменты сохраняют собственные лицензии и условия использования.
