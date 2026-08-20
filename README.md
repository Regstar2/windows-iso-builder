<div align="center">

# Windows ISO Builder

GUI и PowerShell-клиент UUP dump для поиска, проверки и сборки Windows ISO без ручной работы с UUID, SKU и `ConvertConfig.ini`.

**Русский** · [English](README_EN.md)

</div>

## Статус

Текущая версия — **`0.4.0-alpha.1`**.

- ApplicationVersion: `0.4.0-alpha.1`;
- GUI Assembly/File version: `0.4.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`;
- History schema: `1`;
- Profile schema: `1`.

`v0.4.0-alpha.1` добавляет локальную историю фактических сборок и сохраняемые профили конфигурации. PowerShell backend, TUI/CLI, Backend Contract v1 и BuildPlan v1 сохраняются. History/Profiles являются application-level возможностями GUI и не создают второй build pipeline.

## Основной GUI-flow

1. **Сборка** — выбрать Windows/архитектуру, получить рекомендуемую сборку или применить сборку из каталога/истории/профиля.
2. Выбрать язык, редакции, WIM/ESD, параметры и каталог результата.
3. Выполнить `CreateBuildPlan` и `RunPreflight` через backend.
4. Проверить итоговые параметры и явно подтвердить создание ISO.
5. Backend выполняет существующий UAC/download/converter/DISM/ISO workflow.
6. Терминальный результат записывается в **Историю**.

Левая навигация: **Сборка → Каталог → История → Профили → Настройки → Справка → О программе**.

## История сборок

История хранит только controlled GUI DTO для фактических `ExecuteBuildPlan` операций: completed, failed, cancelled и interrupted. Metadata-запросы и preflight в историю не попадают.

Для записи доступны сведения о Windows/build/архитектуре/языке/редакциях/формате, время, статус, ISO/SHA-256, журналы, metadata и error code. Удаление записи или очистка истории удаляет **только запись GUI** и не удаляет ISO, UUP cache, work directory, logs или metadata.

**Повторить** не исполняет старый BuildPlan. GUI заново ищет сохранённую сборку в актуальном каталоге, получает текущие languages/editions и переводит пользователя на страницу «Сборка». Если exact build исчез, пользователь сам выбирает актуальную recommended build, Catalog или отмену. Автоматического запуска ISO нет.

## Профили

Профиль — это сохраняемое пользовательское намерение, а не исполнимый BuildPlan.

Поддерживаются:

- **Recommended / Dynamic** — хранит product/architecture/language/editions/format/options/output; при каждом использовании вызывает `GetRecommendedBuild` и использует актуальный backend catalog;
- **Pinned Build** — дополнительно хранит controlled identity конкретной сборки и применяет её только если она всё ещё найдена через `SearchBuilds`.

Recommended — режим по умолчанию, в том числе при создании профиля из History. Pinned выбирается явно. Профиль не хранит UUP catalog, signed URLs, cache directory, BuildPlan, tokens или secrets.

Если сохранённый language/edition исчез, GUI показывает stale-state и не делает скрытую замену. Если pinned build исчез, fallback на recommended требует отдельного действия и не переписывает сохранённый профиль автоматически.

## Локальные данные

Пользовательские данные GUI находятся в `%LOCALAPPDATA%\WindowsISOBuilder`:

- `settings.json` — язык, тема и состояние окна;
- `history.json` — History schema v1, максимум 200 записей;
- `profiles.json` — Profile schema v1;
- `logs\` — GUI logs.

History/Profile stores используют temp write + flush + atomic replace/move. Повреждённый JSON сохраняется как `*.damaged-*` при возможности, после чего GUI запускается с пустым store. Файл неизвестной будущей schema не перезаписывается автоматически.

`history.json` и `profiles.json` не отправляются в сеть, не входят в release ZIP и не добавляются в diagnostics package. Подробнее: [docs/LOCAL_DATA.md](docs/LOCAL_DATA.md).

## GUI

GUI — C# / WPF / .NET 10 и работает через `Invoke-WibBackend.ps1` / Backend Contract v1. Реализованы:

- Build и responsive Catalog;
- History и Profiles;
- dynamic languages/editions;
- ESD/WIM и converter options;
- preflight;
- asynchronous `ExecuteBuildPlan` и NDJSON progress;
- cooperative `CancelBuild`;
- structured errors;
- RU/EN localization;
- System/Light/Dark themes;
- window state persistence;
- keyboard/accessibility groundwork и AutomationProperties для основных действий;
- sanitized diagnostics ZIP с фиксированным allowlist;
- self-contained `win-x64` publish/package.

GUI запускается как `asInvoker`. UAC остаётся частью backend workflow непосредственно перед privileged build stage.

## Console / automation

TUI/CLI сохраняются:

```powershell
.\Start-Builder.cmd
```

или:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1
```

Machine entry point:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson
```

## Архитектурная граница

PowerShell backend остаётся единственным владельцем:

- UUP catalog/recommendation;
- languages/editions;
- BuildPlan v1;
- preflight;
- UAC/elevation;
- download/converter/DISM;
- ISO validation;
- cancellation process tree.

History/Profile/Repeat не расширяют Backend Contract и не сохраняют BuildPlan как профиль. Совместимость GUI определяется Backend Contract SchemaVersion `1` и BuildPlan SchemaVersion `1`, а не совпадением ApplicationVersion.

## Требования

Для пользователя:

- Windows 10/11 x64;
- Windows PowerShell 5.1;
- DISM и штатные Windows tools;
- доступ к UUP dump и Microsoft Windows Update/CDN;
- достаточно места для cache/work/output;
- права администратора только на privileged build stage.

Для разработки GUI требуется .NET 10 SDK.

## Сборка и тесты

```powershell
dotnet restore .\WindowsISOBuilder.sln
dotnet build .\WindowsISOBuilder.sln -c Release
dotnet test .\WindowsISOBuilder.sln -c Release --no-build
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Gui.ps1
```

Полная release validation:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Pull request в `master` запускает ту же Full validation на owner-controlled Windows self-hosted runner и отдельный published-GUI startup smoke. Automated validation не скачивает Windows и не имитирует manual DPI/Narrator/E2E acceptance.

## Release package

ZIP содержит application runtime, PowerShell backend/TUI/CLI и пользовательскую документацию. Локальные `%LOCALAPPDATA%` data files, `.github`, tests, `bin`/`obj`, validation artifacts, ISO/WIM/ESD/logs и developer-only файлы в release ZIP не попадают.

## Безопасность и приватность

- requests рассматриваются как недоверенные данные;
- backend command dispatch использует allowlist;
- C# использует `ProcessStartInfo.ArgumentList`;
- cancellation выполняется через `CancelBuild`, а не kill-by-name;
- signed UUP URLs, tokens, product keys и raw backend payloads не сохраняются в History/Profile;
- diagnostics имеет фиксированный allowlist `app-version.txt`, `environment.json`, `execution.log`, `build.log`, `converter.log` и проходит sanitizer;
- History/Profiles локальны и не включаются в diagnostics автоматически.

## Документация

- [Backend Contract v1](docs/BACKEND_CONTRACT.md)
- [GUI architecture](docs/GUI_ARCHITECTURE.md)
- [Архитектура проекта](docs/ARCHITECTURE.md)
- [Локальные данные и privacy](docs/LOCAL_DATA.md)
- [Статус реализации](docs/IMPLEMENTATION_STATUS.md)
- [Матрица проверки](docs/VALIDATION_MATRIX.md)
- [Требования](REQUIREMENTS.md)
- [История изменений](CHANGELOG.md)
- [Release notes v0.4.0-alpha.1](docs/releases/v0.4.0-alpha.1.md)

## Не входит в v0.4.0

Queue/parallel builds/scheduling, updater, installer/MSIX, cache-management GUI, USB/Rufus, driver injection, customization/debloat, TPM bypass, activation, accounts/cloud sync/telemetry, profile import/export/sync, custom UUP downloader/converter.

## Лицензия

Собственный код Windows ISO Builder распространяется по [MIT License](LICENSE). Windows, UUP dump и сторонние инструменты имеют собственные лицензии и условия использования.
