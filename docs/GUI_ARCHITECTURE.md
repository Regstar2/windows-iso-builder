# Архитектура GUI v0.4.0-alpha.1

## Граница ответственности

`WindowsISOBuilder.Gui` — WPF/.NET 10 application layer над существующим PowerShell backend.

```text
WPF shell
  ├─ Build
  ├─ Catalog
  ├─ History ───── HistoryService ─── %LOCALAPPDATA%\WindowsISOBuilder\history.json
  ├─ Profiles ──── ProfileService ─── %LOCALAPPDATA%\WindowsISOBuilder\profiles.json
  ├─ Settings
  ├─ Help
  └─ About
        │
        ▼
BackendClient
        │ Backend Contract v1
        ▼
Invoke-WibBackend.ps1
        │
        ▼
PowerShell backend
  ├─ catalog / recommended build
  ├─ languages / editions
  ├─ BuildPlan v1
  ├─ preflight
  ├─ elevation
  ├─ download / converter / DISM
  ├─ ISO validation
  └─ cooperative cancellation
```

History и Profiles не являются Backend Contract DTO и не являются BuildPlan.

## Existing backend flow

Backend Contract SchemaVersion остаётся `1`, BuildPlan SchemaVersion остаётся `1`. GUI использует существующие команды:

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `RunPreflight`, `ExecuteBuildPlan`, `CancelBuild`.

Новой command для History/Profile нет.

## Shell/navigation

Существующая sidebar + hidden `TabControl` остаётся единственной системой навигации. Порядок страниц:

1. Build;
2. Catalog;
3. History;
4. Profiles;
5. Settings;
6. Help;
7. About.

Build остаётся стартовой страницей. История/профили используют существующие WPF resources и не создают новый header/theme framework.

## История

`HistoryService` владеет History schema v1, retention и persistent lifecycle. При реальном старте `ExecuteBuildPlan` GUI создаёт controlled `Pending` entry. Terminal result переводит его в `Completed`, `Failed` или `Cancelled`. При следующем startup остаточный `Pending` нормализуется в `Interrupted`.

History DTO содержит только выбранную конфигурацию и terminal artifacts/error code. Произвольный backend response или BuildPlan не сериализуется.

### Repeat

```text
History entry
  ↓
SearchBuilds(saved build identity)
  ├─ exact found ──────────────┐
  └─ missing → explicit UX     │
          ├─ current recommended
          ├─ open Catalog
          └─ cancel
                               ▼
GetLanguages(current updateId)
  ↓
validate saved language
  ↓
GetEditions(current updateId, language)
  ↓
validate saved editions
  ↓
Build page (no automatic build)
  ↓
CreateBuildPlan → RunPreflight → user confirmation → ExecuteBuildPlan
```

Старый BuildPlan и старый UUP UUID не исполняются напрямую.

## Профили

`ProfileService` владеет Profile schema v1. UUID является identity профиля; display names могут повторяться. Имя trim-ится и ограничено 1..80 символами.

### Recommended / Dynamic

Хранит intent: product, architecture, language, editions, format, options, output. При `Use` вызывает `GetRecommendedBuild`, затем актуальные languages/editions.

### Pinned

Дополнительно хранит controlled build identity. Exact build разрешается через `SearchBuilds`. Если build исчез, fallback только явный и не меняет сохранённый профиль автоматически.

### Stale values

Недоступный saved language или edition не заменяется молча. GUI применяет только совместимую часть, показывает предупреждение и оставляет конфигурацию неготовой к preflight до явного пользовательского выбора.

## StoredConfigurationResolver

Resolver отделяет динамическое catalog resolution от storage:

- `ResolveRecommendedAsync`;
- `ResolvePinnedAsync`/`ResolveHistoryAsync`;
- `ResolveValuesAsync` для current languages/editions и missing values.

Production adapter вызывает существующий `BackendClient`; tests используют fake catalog без Windows download.

## Storage

`AtomicJsonStore<T>` выполняет version check, temp write, `WriteThrough`, disk flush, atomic replace/move, corruption recovery и write-block для unknown future schema. Подробно: `docs/LOCAL_DATA.md`.

`AppSettingsService` остаётся отдельным маленьким settings store; массивы History/Profile в него не помещаются.

## Build execution integration

Единственный фактический execution path остаётся `MainViewModel.BuildAsync()`:

```text
configuration
→ CreateBuildPlan
→ RunPreflight
→ confirmation
→ ExecuteBuildPlan
→ terminal response/error
→ HistoryService terminal update
```

Не существуют отдельные `ExecuteBuildPlanFromHistory/Profile/Catalog` pipelines.

## Threading/cancellation

Backend process/file operations остаются async. Active build requestId, NDJSON progress и cooperative `CancelBuild` используют существующую state machine. Навигация не уничтожает MainViewModel, поэтому progress/cancel/result не теряются.

## Localization/theme/accessibility

Новые строки находятся в парных `Strings.LocalData.resx` / `Strings.LocalData.ru.resx` и включены в общий `LocalizationService` snapshot parity test. Schema хранит enum/code values, а не локализованные строки.

History/Profile XAML использует `Card`, theme-owned brushes/control templates, normal WPF keyboard activation и AutomationProperties на основных actions. Card-level accessibility summary не превращает каждую строку карточки в отдельный tab stop.

PerMonitorV2 и существующие light/dark/system resources сохраняются; History/Profile pages используют wrapping и собственный vertical scrolling.

## Privacy/diagnostics/package

History/Profile files находятся в `%LOCALAPPDATA%`, не рядом с EXE. Diagnostics сохраняет прежний фиксированный allowlist и не читает History/Profile. Release package содержит runtime/docs, но не локальные user data.
