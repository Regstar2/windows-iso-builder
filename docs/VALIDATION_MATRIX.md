# Матрица проверки v0.4.0-alpha.1

Статусы в этой таблице разделяют наличие проверки и факт её исполнения. Manual пункты нельзя помечать PASS по результатам unit/Pester/package smoke.

## Automated

| Проверка | Механизм | Ожидаемый результат | Текущий статус |
|---|---|---|---|
| GUI restore/build | `dotnet restore/build` | Release build без ошибок | PENDING PR CI |
| GUI tests | `dotnet test` | все C# tests PASS | PENDING PR CI |
| History empty/save/load/round-trip/schema | `LocalDataTests` | PASS | PENDING PR CI |
| History retention/newest-first | `LocalDataTests` | 200 newest, descending | PENDING PR CI |
| History corruption/future schema/atomic save | `LocalDataTests` | no crash/no blind overwrite/no temp residue | PENDING PR CI |
| History completed/failed/cancelled/interrupted | `LocalDataTests` | controlled terminal lifecycle | PENDING PR CI |
| Profile empty/save/load/schema/UUID/update/delete | `LocalDataTests` | PASS | PENDING PR CI |
| Recommended/Pinned profile model | `LocalDataTests` | correct controlled persistence | PENDING PR CI |
| Recommended resolution | `StoredConfigurationResolverTests` | `GetRecommendedBuild` path | PENDING PR CI |
| Pinned/history exact resolution | `StoredConfigurationResolverTests` | exact current `SearchBuilds` match | PENDING PR CI |
| unavailable build/language/edition | resolver tests | controlled stale result | PENDING PR CI |
| no silent edition removal | resolver tests | missing editions retained as warning data | PENDING PR CI |
| Repeat does not own execution | Pester static regression | no `ExecuteBuildPlan` in LocalData flow | PENDING PR CI |
| single ExecuteBuildPlan pipeline | Pester static regression | one execution command in Build flow | PENDING PR CI |
| sidebar History/Profiles RU/EN resources | C#/Pester | parity/navigation present | PENDING PR CI |
| theme-owned new pages | Pester | no hardcoded white/black surfaces | PENDING PR CI |
| AutomationProperties | Pester | principal actions/card summaries present | PENDING PR CI |
| diagnostics privacy | existing C# + Pester | fixed five-file allowlist; no stores | PENDING PR CI |
| package storage isolation | package/Pester | no runtime-created History/Profile files | PENDING PR CI |
| Backend Contract regression | existing tests | SchemaVersion 1 | PENDING PR CI |
| BuildPlan regression | existing tests | SchemaVersion 1 | PENDING PR CI |
| NDJSON/cancellation/preflight | existing tests | PASS | PENDING PR CI |
| Pester full suite | `Invoke-Pester` through validation | PASS | PENDING PR CI |
| PSScriptAnalyzer | release validation | PASS | PENDING PR CI |
| backend/package smoke | release validation | PASS | PENDING PR CI |
| published GUI startup smoke | self-hosted workflow | process starts and stays alive | PENDING PR CI |
| Full release validation | `tools/Invoke-ReleaseValidation.ps1 -Full` | exit 0 | PENDING PR CI |

## Manual

| Проверка | Минимальная процедура | Статус |
|---|---|---|
| History visual | completed/failed/cancelled cards, filters, details | NOT RUN |
| History actions | open folder/log/metadata, copy SHA, missing paths | NOT RUN |
| History delete/clear semantics | records disappear, files remain | NOT RUN |
| Repeat exact build | returns to Build, no auto-build | NOT RUN |
| Repeat stale build | explicit recommended/Catalog/Cancel | NOT RUN |
| Profile persistence | create → restart → profile remains | NOT RUN |
| Dynamic profile | Use → current recommended/language/editions | NOT RUN |
| Pinned profile stale flow | explicit fallback, saved profile unchanged | NOT RUN |
| Profile edit/delete | save changes/delete | NOT RUN |
| keyboard-only Build | Tab/Shift+Tab/Enter/Space | NOT RUN |
| keyboard History/Profiles | navigation/actions/dialogs | NOT RUN |
| ComboBox keyboard | open/select/close | NOT RUN |
| Esc dialogs | deterministic close/cancel | NOT RUN |
| basic Narrator | History/Profile accessibility summaries/actions | NOT RUN |
| Light/Dark focus | visible keyboard focus | NOT RUN |
| DPI 100% | Build/Catalog/History/Profiles/Settings | NOT RUN |
| DPI 125% | same | NOT RUN |
| DPI 150% | same | NOT RUN |
| real GUI E2E | Windows 11 recommended x64 ru-RU Professional ESD → success/history → Repeat to preflight | NOT RUN |

## E2E rule

Real Repeat validation does not require a second large ISO download. After the first successful build, Repeat may stop after the restored configuration reaches valid preflight/confirmation. If the real ISO E2E is not executed, release notes/report must state **NOT RUN**.
