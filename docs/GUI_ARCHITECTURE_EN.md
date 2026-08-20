# GUI architecture v0.4.0-alpha.1

## Responsibility boundary

`WindowsISOBuilder.Gui` is a WPF/.NET 10 application layer over the existing PowerShell backend.

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

History and Profiles are neither Backend Contract DTOs nor BuildPlan.

## Existing backend flow

Backend Contract SchemaVersion remains `1` and BuildPlan SchemaVersion remains `1`. The GUI uses the existing commands only:

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `RunPreflight`, `ExecuteBuildPlan`, `CancelBuild`.

No new backend command exists for History/Profile.

## Shell/navigation

The existing sidebar plus hidden `TabControl` remains the only navigation system. Page order is Build, Catalog, History, Profiles, Settings, Help, About. Build remains the startup page. History/Profile reuse existing WPF resources and do not introduce another header or theme framework.

## History

`HistoryService` owns History schema v1, retention, and persistent lifecycle. When the real `ExecuteBuildPlan` operation starts, the GUI creates a controlled `Pending` entry. The terminal result changes it to `Completed`, `Failed`, or `Cancelled`. On the next startup a remaining `Pending` entry becomes `Interrupted`.

History serializes selected configuration plus terminal artifacts/error code only. Arbitrary backend responses and BuildPlan are not persisted.

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

An old BuildPlan or old UUP UUID is never executed directly.

## Profiles

`ProfileService` owns Profile schema v1. UUID is profile identity; duplicate display names are allowed. Names are trimmed and limited to 1..80 characters.

### Recommended / Dynamic

Stores intent: product, architecture, language, editions, format, options, output. `Use` calls `GetRecommendedBuild` and then current languages/editions.

### Pinned

Additionally stores a controlled build identity. The exact build is resolved through `SearchBuilds`. If it is gone, fallback is explicit and does not mutate the saved profile automatically.

### Stale values

Unavailable saved language/edition values are not silently substituted. The GUI applies only compatible values, exposes a warning, and leaves the configuration unready for preflight until the user explicitly repairs it.

## StoredConfigurationResolver

Resolution is separate from persistence:

- `ResolveRecommendedAsync`;
- `ResolvePinnedAsync` / `ResolveHistoryAsync`;
- `ResolveValuesAsync` for current languages/editions and missing-value detection.

The production adapter calls the existing `BackendClient`; tests use a fake catalog and never download Windows.

## Storage

`AtomicJsonStore<T>` performs schema checks, temp writes, `WriteThrough`, disk flush, atomic replace/move, corruption recovery, and write blocking for unknown future schemas. See `docs/LOCAL_DATA_EN.md`.

`AppSettingsService` remains a separate small settings store; History/Profile arrays are not inserted into it.

## Build execution integration

The only actual execution path remains `MainViewModel.BuildAsync()`:

```text
configuration
→ CreateBuildPlan
→ RunPreflight
→ confirmation
→ ExecuteBuildPlan
→ terminal response/error
→ HistoryService terminal update
```

There are no `ExecuteBuildPlanFromHistory/Profile/Catalog` variants.

## Threading/cancellation

Backend process/file work remains asynchronous. Active requestId, NDJSON progress, and cooperative `CancelBuild` use the existing state machine. Navigation does not replace the shared MainViewModel, so progress/cancel/result state is retained.

## Localization/theme/accessibility

New strings live in paired `Strings.LocalData.resx` / `Strings.LocalData.ru.resx` resources and participate in the common localization parity test. Persisted schemas store enum/code values rather than localized text.

History/Profile XAML uses existing `Card` and theme-owned control resources, normal WPF keyboard activation, and AutomationProperties on primary actions. Each card exposes an accessibility summary without turning every text row into a separate tab stop.

PerMonitorV2 and existing System/Light/Dark resources remain unchanged; the new pages wrap actions and own their vertical scrolling regions.

## Privacy/diagnostics/package

History/Profile files live under `%LOCALAPPDATA%`, not next to the executable. Diagnostics keeps the existing fixed allowlist and never reads History/Profile. The release package contains runtime/docs but not local user data.
