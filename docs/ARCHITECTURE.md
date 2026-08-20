# Архитектура Windows ISO Builder

## Версии и независимые схемы

Для `v0.4.0-alpha.1`:

- ApplicationVersion: `0.4.0-alpha.1`;
- GUI Assembly/File version: `0.4.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`;
- HistorySchemaVersion: `1`;
- ProfileSchemaVersion: `1`.

Эти версии не должны повышаться синхронно без причины. GUI release не требует изменения PowerShell ModuleVersion или backend schemas, если backend contract/pipeline не меняется.

## Слои

```text
Interactive clients
├─ WPF GUI
│  ├─ Build / Catalog
│  ├─ History / Profiles (local application data)
│  └─ Settings / Help / About
└─ PowerShell TUI / CLI
        │
        ▼
Public backend boundary
├─ Invoke-WibBackend.ps1 / Backend Contract v1
└─ public PowerShell module functions
        │
        ▼
PowerShell backend
├─ UUP dump catalog / recommendation
├─ languages / editions
├─ BuildPlan v1
├─ preflight
├─ UAC/elevated worker
├─ UUP download/cache/resume
├─ converter / DISM
├─ ISO validation
└─ cancellation / logs
```

## Source of truth

PowerShell backend остаётся source of truth для динамического каталога, конкретного BuildPlan, readiness и фактической сборки ISO. GUI не зашивает Windows build numbers и не переносит recommendation/build logic в C#.

History/Profile — application-level state:

- History описывает факт прошлой `ExecuteBuildPlan` операции;
- Profile описывает намерение пользователя для будущей конфигурации;
- BuildPlan описывает одну конкретную исполнимую сборку.

Эти форматы не взаимозаменяемы.

## Dynamic catalog rule

Recommended profile каждый раз вызывает `GetRecommendedBuild`. Pinned profile/history repeat используют `SearchBuilds` для разрешения сохранённой controlled build identity. После разрешения GUI всегда получает актуальные `GetLanguages` и `GetEditions`.

Если сохранённое значение исчезло, GUI показывает stale state; скрытая подмена не допускается.

## Single build pipeline

Все GUI entry points сходятся в одну последовательность:

```text
build configuration
→ CreateBuildPlan
→ RunPreflight
→ explicit user confirmation
→ ExecuteBuildPlan
→ terminal result
```

History recording добавляется после начала реального `ExecuteBuildPlan`, но не создаёт отдельный execution pipeline.

## Local data

`%LOCALAPPDATA%\WindowsISOBuilder` содержит settings/history/profiles/logs. History/Profile используют отдельные versioned JSON stores и atomic writes. Подробнее: `docs/LOCAL_DATA.md`.

## Security boundaries

- GUI запускается `asInvoker`; elevation выполняет backend;
- backend command dispatch allowlisted;
- C# process launch uses argument list, not shell concatenation;
- cancellation backend-owned, без kill-by-name;
- History/Profile не содержат signed UUP URLs, tokens, product keys, arbitrary backend payloads или BuildPlan dumps;
- diagnostics имеет отдельный фиксированный allowlist и sanitizer;
- release package не содержит локальные app-data files.

## Packaging/validation

`tools/Build-Gui.ps1` собирает self-contained `win-x64` GUI. `tools/Invoke-ReleaseValidation.ps1 -Full` остаётся единой полной automated validation. `.github/workflows/windows-self-hosted-validation.yml` — thin orchestration над этим tooling на owner-controlled Windows runner.

Manual DPI/Narrator/real ISO E2E фиксируются отдельно и не могут автоматически считаться PASS по результату unit/Pester/package smoke.
