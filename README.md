<div align="center">

# Windows ISO Builder

GUI и PowerShell-клиент UUP dump для поиска, загрузки и сборки Windows ISO без ручной работы с UUID, SKU и `ConvertConfig.ini`.

**Русский** · [English](README_EN.md)

</div>

## Статус

Текущая версия — **`0.3.0-alpha.1`**.

- ApplicationVersion: `0.3.0-alpha.1`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`v0.3.0-alpha.1` добавляет первый WPF GUI. Существующие TUI, CLI и machine-readable Backend Contract сохраняются. GUI не является новым UUP/build backend: он работает через `Invoke-WibBackend.ps1` и Contract v1.

## Быстрый старт — GUI

1. Скачайте release ZIP и распакуйте его полностью.
2. Запустите `WindowsISOBuilder.exe` обычным пользователем.
3. Выберите Windows 11 или Windows 10 и получите рекомендуемую сборку либо откройте «Каталог».
4. Выберите язык, одну или несколько редакций, ESD/WIM и каталог результата.
5. Выполните проверку готовности.
6. Если fatal-проверок нет, нажмите «Создать ISO» и подтвердите UAC, когда backend запросит повышение прав.
7. После завершения GUI покажет путь к ISO и SHA-256.

Пользовательский release является `win-x64` self-contained: отдельная установка .NET Runtime не требуется. .NET 10 SDK нужен только для разработки/сборки GUI.

## GUI

Первый GUI включает:

- Quick Mode с backend-командой `GetRecommendedBuild`;
- Catalog Mode с `SearchBuilds`, Preview и display-фильтром служебных записей;
- явное применение выбранной каталожной сборки без запуска metadata-запросов по одиночному клику;
- динамические languages/editions из backend без встроенных списков;
- multi-edition выбор;
- ESD/WIM и базовые converter options;
- `CreateBuildPlan` + `RunPreflight`;
- asynchronous `ExecuteBuildPlan` и NDJSON progress/events;
- cooperative `CancelBuild` без GUI-side kill процессов;
- обработку стабильных backend error codes для preflight/download/converter/DISM/ISO/elevation/cancellation;
- success screen с ISO, SHA-256, журналом и открытием папки;
- GUI log в `%LOCALAPPDATA%\WindowsISOBuilder\logs`.

GUI запускается с `asInvoker`. UAC остаётся частью существующего backend workflow непосредственно перед privileged build stage.

## Console / automation

TUI не deprecated. Для консольного интерактивного режима:

```powershell
.\Start-Builder.cmd
```

или:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1
```

Non-interactive пример:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Builder.ps1 `
  -NonInteractive `
  -Search 22H2 `
  -Architecture amd64 `
  -Language ru-ru `
  -Editions Core,Professional `
  -ImageFormat ESD
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

PowerShell backend остаётся единственным владельцем UUP catalog, recommendation, BuildPlan, preflight, UAC/elevation, download, converter/DISM, ISO validation и cancellation process tree.

GUI не импортирует `WindowsISOBuilder.psm1`, не вызывает private functions, не парсит `Write-Host`, transcript, aria2/converter output и не классифицирует ошибку по локализованному `message`.

Совместимость GUI определяется schema interfaces, а не совпадением ApplicationVersion. Для `v0.3.0-alpha.1` требуются Backend Contract SchemaVersion `1` и BuildPlan SchemaVersion `1`; packaged GUI smoke проверяет оба значения.

Полный контракт: [docs/BACKEND_CONTRACT.md](docs/BACKEND_CONTRACT.md). Архитектура GUI: [docs/GUI_ARCHITECTURE.md](docs/GUI_ARCHITECTURE.md).

## Требования

Для пользователя:

- Windows 10/11 x64;
- Windows PowerShell 5.1;
- DISM и штатные Windows tools;
- доступ к UUP dump и Microsoft Windows Update/CDN;
- достаточно места для cache/work/output;
- права администратора только на privileged build stage.

Для разработки GUI требуется .NET 10 SDK.

## Сборка и тесты GUI

```powershell
dotnet restore .\WindowsISOBuilder.sln
dotnet build .\WindowsISOBuilder.sln -c Release
dotnet test .\WindowsISOBuilder.sln -c Release --no-build
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Gui.ps1
```

`Build-Gui.ps1` делает restore/build/test/publish `win-x64 --self-contained` и не устанавливает SDK автоматически.

## Проверка релиза

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Full validation должна проверять GUI build/test/publish, Pester, PSScriptAnalyzer, backend smokes, release package, manifest/checksum и packaged `WindowsISOBuilder.exe --backend-smoke`. Ни один автоматический smoke не скачивает Windows и не открывает UAC.

Репозиторий также содержит `.github/workflows/windows-self-hosted-validation.yml`. Для pull request в `master` он запускает тот же Full validation на Windows self-hosted runner с labels `self-hosted`, `Windows`, `X64`; superseded PR runs отменяются через `concurrency`. `validation-result.json` публикуется как Actions artifact даже при падении validation.

Фактические результаты конкретной среды нельзя подменять статусом implementation. См. [docs/VALIDATION_MATRIX.md](docs/VALIDATION_MATRIX.md).

## Release package

ZIP содержит:

- `WindowsISOBuilder.exe` и self-contained `win-x64` runtime;
- `Invoke-WibBackend.ps1`;
- PowerShell module/backend;
- `Start-Builder.cmd` / `Start-Builder.ps1`;
- документацию;
- package-only `release-manifest.json`.

Manifest содержит версии приложения/модуля/schema и additive GUI metadata; локальные developer paths, username и machine name не включаются. `.github`, tests, `bin`/`obj`, validation artifacts и другие developer-only файлы в release ZIP не попадают.

## Безопасность

- requests считаются недоверенными данными;
- backend dispatch использует allowlist;
- C# запускает PowerShell через `ProcessStartInfo.ArgumentList`;
- пользовательские строки не исполняются как PowerShell;
- cancellation выполняется через `CancelBuild`, а не `taskkill`/`Stop-Process` из GUI;
- signed UUP URLs, tokens и product keys не должны попадать в GUI log;
- backend path определяется относительно package root; сетевой executable/backend code не загружается.

## Документация

- [Backend Contract v1](docs/BACKEND_CONTRACT.md)
- [GUI architecture](docs/GUI_ARCHITECTURE.md)
- [Архитектура проекта](docs/ARCHITECTURE.md)
- [Статус реализации](docs/IMPLEMENTATION_STATUS.md)
- [Матрица проверки](docs/VALIDATION_MATRIX.md)
- [Требования](REQUIREMENTS.md)
- [История изменений](CHANGELOG.md)
- [Release notes](docs/releases/v0.3.0-alpha.1.md)

## Ограничения v0.3.0

В GUI MVP намеренно нет history, profiles, queue, cache-management UI, updater, installer/MSIX, USB writer/Rufus, full theme/language settings, customization/debloat, driver injection, TPM bypass, activation и custom UUP engine/downloader/converter. GitHub Actions используется только как thin orchestration layer над существующей локальной Full validation на self-hosted Windows runner и не входит в runtime/release package.

## Лицензия

Собственный код Windows ISO Builder распространяется по [MIT License](LICENSE). Windows, UUP dump и сторонние инструменты имеют собственные лицензии и условия использования.
