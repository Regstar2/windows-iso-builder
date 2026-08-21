# Архитектура GUI

## Цель

`WindowsISOBuilder.Gui` — тонкий WPF-клиент над существующим PowerShell backend. Он не содержит альтернативного UUP/build workflow.

```text
WPF / MVVM
   │
BackendClient
   │ JSON files + process
   ▼
Invoke-WibBackend.ps1
   │
Backend Contract Schema v1
   ▼
PowerShell backend
   ├─ catalog/recommendation
   ├─ BuildPlan v1 / preflight
   ├─ UAC/elevated worker
   ├─ download/converter/DISM
   ├─ ISO validation
   └─ cooperative cancellation
```

## Технологии

- C# / WPF / .NET 10 (`net10.0-windows`);
- SDK-style project;
- `System.Text.Json`;
- стандартные WPF resources/styles;
- минимальный собственный MVVM infrastructure;
- без Electron, WebView, Avalonia, MahApps и MaterialDesignInXaml.

## Слои

`MainWindow` отвечает только за view-specific behavior: навигацию, folder picker, явное применение выбранной Catalog row, clipboard/open-path actions и close confirmation.

`MainViewModel` управляет пользовательским flow и UI state. Backend-specific transport находится отдельно.

`Models/ContractDtos.cs` содержит strongly typed DTO Backend Contract v1.

`BackendClient` создаёт requestId, отдельный app-owned temporary transport directory с независимым непредсказуемым GUID, сериализует JSON, запускает public backend entry point, валидирует envelope/data/schema handshake и очищает только transport data. Имя transport directory не выводится из requestId.

`BackendProcessRunner` использует `ProcessStartInfo.ArgumentList`, чтобы пользовательские строки не попадали в shell command concatenation.

`NdjsonEventReader` tail-ит event file incrementally на уровне bytes. Незавершённые bytes последней строки, включая разрыв внутри multibyte UTF-8 символа, сохраняются до `\n`; malformed completed telemetry не определяет результат build. Duplicate/out-of-order sequence игнорируются.

`BackendPathResolver` сначала ищет `Invoke-WibBackend.ps1` рядом с packaged executable. Explicit override допускается только когда caller сознательно передаёт root (например `--backend-root` smoke). Ambient environment variable не может подменить executable backend. Parent search используется как development fallback.

`GuiLogger` выбирает `%LOCALAPPDATA%\WindowsISOBuilder\logs` без обязательного создания каталога в constructor. Создание/запись best-effort и не может само уронить GUI. Backend exceptions логируются по code/requestId без backend message; URL и product-key patterns редактируются.

## Startup handshake

```text
start as normal user
   ↓
resolve packaged/dev backend
   ↓
GetVersion
   ↓
response envelope schema == 1
   ↓
contractSchemaVersion == 1 AND buildPlanSchemaVersion == 1 ?
   ├─ no → UNSUPPORTED_SCHEMA / blocking failure
   └─ yes → Ready
```

ApplicationVersion не участвует в compatibility decision. User-visible version берётся из `GetVersion`.

Normal startup создаёт `MainWindow` вручную только после выхода из backend-smoke path. В `App.xaml` нет `StartupUri`, поэтому `WindowsISOBuilder.exe --backend-smoke` не может открыть обычное GUI окно.

## Request lifecycle

Для каждой operation создаются новый `requestId` и независимый `%TEMP%\WindowsISOBuilder\backend\<operation-guid>\` с request/response/event transport files.

Весь owned transport lifecycle находится под `finally`: cleanup выполняется и после response processing, и после ранней serialization/write/process ошибки. Build logs, cache, work directory и ISO не принадлежат transport cleanup.

Successful response без `data` считается `INTERNAL_ERROR`. Final Backend response остаётся source of truth для результата operation.

## Quick Mode

```text
product / architecture
  ↓
GetRecommendedBuild
  ↓
GetLanguages(updateId)
  ↓
GetEditions(updateId, language)
  ↓
CreateBuildPlan
  ↓
RunPreflight
  ↓
ExecuteBuildPlan
```

Recommendation logic не переносится в C#. Language/edition values не зашиты в GUI.

## Catalog Mode

`SearchBuilds` возвращает backend DTO. GUI может скрыть non-Windows/servicing rows display-фильтром, но хранит исходный response и не создаёт собственный ranking engine.

Одиночное выделение строки не меняет active build и не запускает metadata. Double-click или `Использовать выбранную` синхронизирует product/architecture, назначает active build и переводит пользователя в тот же configuration/preflight/build flow, что Quick Mode.

## State machine

Основной happy path:

`Idle → LoadingBuild → LoadingLanguages → LoadingEditions → ReadyToPreflight → Preflighting → ReadyToBuild → Building → Completed`.

Failure/cancellation branches: `PreflightFailed`, `Failed`, `Cancelling`, `Cancelled`.

Cooperative cancellation допускает `Cancelling → Building`, если CancelBuild не был принят/отправлен и target build всё ещё жив. Retry из `Failed` возвращает UI в состояние той operation, которая упала (`ReadyToBuild`, `ReadyToPreflight`, metadata loading и т.д.).

## Threading

Backend process calls, file I/O и event polling выполняются async. WPF continuations возвращаются на UI synchronization context для обновления bindable state. GUI не блокирует UI thread ожиданием backend process.

## Event lifecycle

`ExecuteBuildPlan` получает отдельный active build requestId. Event reader:

- читает только appended bytes;
- не перечитывает весь файл;
- сохраняет incomplete trailing bytes/line;
- корректно переживает UTF-8 split внутри символа;
- игнорирует malformed completed telemetry;
- отбрасывает duplicate/out-of-order `sequence`;
- позволяет безопасно игнорировать неизвестные additive event types;
- использует backend `stage`, `percent`, `detailPercent`, `speedText`, `speedBytesPerSecond`.

100% progress не означает completion. Source of truth — final Backend response.

## Cancellation lifecycle

```text
Building
  ↓ user cancel
CancelBuild(targetRequestId, cacheDirectory)
  ↓ acknowledgement
Cancelling
  ↓ target ExecuteBuildPlan final result/event
BUILD_CANCELLED / cancelled
  ↓
Cancelled
```

Если запрос отмены не принят/не отправлен, UI возвращается в `Building` и не закрывается поверх активной сборки.

GUI не вызывает `Process.Kill`, `taskkill`, `Stop-Process` и не завершает aria2/DISM по имени. Закрытие окна во время build использует тот же cancellation flow и ждёт terminal target state перед exit.

## UAC boundary

GUI manifest — `asInvoker`. `RunPreflight` выполняется до build. `ExecuteBuildPlan` передаёт управление backend, а существующий backend самостоятельно выполняет elevation. `ELEVATION_CANCELLED` является обычным structured failure, а не frontend crash.

## Error handling

Frontend классифицирует backend failures только по `error.code`. Stable backend taxonomy имеет явные user-facing mappings для schema/preflight/network/UUP/download/converter/DISM/ISO/elevation/cancellation/build failures. Неизвестный v1 code отображается generic failure.

Code, stage, backend message, log path и requestId находятся в раскрываемых technical details. Application-level exception boundary пишет безопасный GUI log и завершает приложение после critical frontend exception.

## Publish/package layout

`tools/Build-Gui.ps1` выполняет restore/build/test и `win-x64 --self-contained true` publish. Release configuration не публикует PDB; `.pdb` также запрещён package safety policy.

Release staging помещает `WindowsISOBuilder.exe` и published runtime в package root рядом с `Invoke-WibBackend.ps1`. Поэтому packaged backend location deterministic и не зависит от source checkout/environment override.

Release ZIP также сохраняет TUI/CLI. Package manifest содержит additive `gui.included/runtime/selfContained` metadata. `.github`, tests, build outputs и validation artifacts не входят в runtime package. Installer/MSIX не входит в pre-1.0 release train.
