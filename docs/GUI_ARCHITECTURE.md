# Архитектура GUI v0.3.0-alpha.1

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

- C#;
- WPF;
- .NET 10, `net10.0-windows`;
- SDK-style project;
- System.Text.Json;
- стандартные WPF resources/styles;
- минимальный собственный MVVM infrastructure;
- без Electron, WebView, Avalonia, MahApps и MaterialDesignInXaml.

## Слои

`MainWindow` отвечает только за view-specific behavior: навигацию, folder picker, clipboard/open-path actions и close confirmation.

`MainViewModel` управляет пользовательским flow и UI state. Backend-specific transport находится отдельно.

`Models/ContractDtos.cs` содержит strongly typed DTO Backend Contract v1.

`BackendClient` создаёт requestId, отдельный app-owned temporary transport directory с непредсказуемым GUID, сериализует JSON, запускает public backend entry point, читает response и очищает только transport data. Имя transport directory не выводится из requestId.

`BackendProcessRunner` использует `ProcessStartInfo.ArgumentList`, чтобы пользовательские строки не попадали в shell command concatenation.

`NdjsonEventReader` tail-ит event file incrementally и хранит stream position, partial line и последнее принятое sequence.

`BackendPathResolver` сначала ищет `Invoke-WibBackend.ps1` рядом с packaged executable. Dev override допускается через `--backend-root` для smoke или `WIB_BACKEND_ROOT`; parent search используется только как development fallback.

`GuiLogger` пишет frontend log в `%LOCALAPPDATA%\WindowsISOBuilder\logs`.

## Startup handshake

```text
start as normal user
   ↓
resolve backend
   ↓
GetVersion
   ↓
contractSchemaVersion == 1 ?
   ├─ no → blocking incompatibility failure
   └─ yes → Ready
```

ApplicationVersion не участвует в compatibility decision. User-visible version берётся из `GetVersion`.

## Request lifecycle

Для каждой operation создаются новый `requestId` и независимый `%TEMP%\WindowsISOBuilder\backend\<operation-guid>\` с request/response/event transport files.

Metadata operations удаляют transport directory после final response. Build events читаются, пока target backend process работает; cleanup выполняется после final response/error processing. Build logs, cache, work directory и ISO не принадлежат transport cleanup.

## Quick Mode

```text
product
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

`SearchBuilds` возвращает backend DTO. GUI может скрыть non-Windows/servicing rows display-фильтром, но хранит исходный response и не создаёт собственный ranking engine. После выбора build используется тот же configuration/preflight/build flow, что Quick Mode.

## State machine

Основные состояния:

`Idle → LoadingBuild → LoadingLanguages → LoadingEditions → ReadyToPreflight → Preflighting → ReadyToBuild → Building → Completed`.

Failure/cancellation branches: `PreflightFailed`, `Failed`, `Cancelling`, `Cancelled`.

State управляет conflicting commands и build/cancel availability; business workflow не хранится в `MainWindow` code-behind.

## Threading

Backend process calls, file I/O и event polling выполняются async. WPF continuations возвращаются на UI synchronization context для обновления bindable state. GUI не блокирует UI thread ожиданием backend process.

## Event lifecycle

`ExecuteBuildPlan` получает отдельный active build requestId. Event reader:

- читает только appended data;
- не перечитывает весь файл;
- сохраняет incomplete trailing line;
- принимает UTF-8;
- игнорирует malformed transient records;
- отбрасывает duplicate/out-of-order `sequence` telemetry;
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

GUI не вызывает `Process.Kill`, `taskkill`, `Stop-Process` и не завершает aria2/DISM по имени.

Закрытие окна во время build использует тот же cancellation flow и ждёт terminal target state перед exit.

## UAC boundary

GUI manifest — `asInvoker`. `RunPreflight` выполняется до build. `ExecuteBuildPlan` передаёт управление backend, а существующий backend самостоятельно выполняет elevation. `ELEVATION_CANCELLED` является обычным structured failure, а не frontend crash.

## Error handling

Frontend классифицирует backend failures только по `error.code`. Mapping пользовательского title/action не меняет backend message. Неизвестный v1 code отображается generic failure. Code, stage, backend message, log path и requestId находятся в раскрываемых technical details.

Application-level exception boundary пишет GUI log и показывает controlled frontend error. После критической frontend exception приложение завершается, а не продолжает unsafe state.

## Logging

GUI log содержит startup/backend location, contract/application versions, command names, request IDs, state transitions и frontend exception summaries. Full request JSON, signed URLs, tokens, product keys и secrets не логируются.

## Publish/package layout

`tools/Build-Gui.ps1` выполняет restore/build/test и `win-x64 --self-contained true` publish.

Release staging помещает `WindowsISOBuilder.exe` и published runtime в package root рядом с `Invoke-WibBackend.ps1`. Поэтому packaged backend location deterministic и не зависит от source checkout.

Release ZIP также сохраняет TUI/CLI. Package manifest содержит additive `gui.included/runtime/selfContained` metadata. Installer/MSIX не входит в v0.3.0.
