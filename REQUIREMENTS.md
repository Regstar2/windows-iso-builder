# REQUIREMENTS — Windows ISO Builder v0.4.0-alpha.1

## 1. Compatibility baseline

- Windows 10/11 x64 user runtime;
- Windows PowerShell 5.1 remains supported;
- PowerShell 7 remains supported where existing validation covers it;
- TUI/CLI remain supported;
- Backend Contract SchemaVersion = `1`;
- BuildPlan SchemaVersion = `1`;
- PowerShell ModuleVersion remains `0.3.0` unless backend functionality changes;
- GUI is WPF / .NET 10, self-contained `win-x64` in release package.

## 2. Backend ownership

PowerShell backend remains the sole source of truth for:

- UUP dump catalog/recommendation;
- build identity/update UUID;
- languages and editions;
- BuildPlan construction/validation;
- preflight;
- UAC/elevation;
- download/cache/resume;
- converter/DISM;
- ISO validation;
- cancellation process tree.

GUI must not persist BuildPlan as a profile/history format and must not add a backend command solely for History/Profile convenience.

## 3. GUI pages

Primary navigation order:

1. Build;
2. Catalog;
3. History;
4. Profiles;
5. Settings;
6. Help;
7. About.

No second navigation system or duplicate Quick/Catalog surface is allowed.

## 4. Build flow

Every GUI build starts through the same path:

`configuration → CreateBuildPlan → RunPreflight → user confirmation → ExecuteBuildPlan → terminal result`.

History/Profile/Repeat must never auto-start `ExecuteBuildPlan`.

## 5. History

History records real terminal build operations only. GetVersion/Search/GetLanguages/GetEditions/Preflight are not entries.

Required terminal statuses:

- Completed;
- Failed;
- Cancelled;
- Interrupted.

A real ExecuteBuildPlan may have an internal persisted `Pending` state. After GUI restart, remaining Pending records become Interrupted, not Failed.

History schema is independent version `1`; store is `%LOCALAPPDATA%\WindowsISOBuilder\history.json`; retention is 200 newest entries.

Controlled fields may include product/version/build/architecture, language, editions, format/options/output, timestamps/status, ISO/SHA-256, build/execution/metadata paths and stable error code. Do not store signed URLs, tokens, product keys, arbitrary backend responses, environment dumps, exceptions/stack traces or full BuildPlan JSON.

Deleting/clearing History removes records only; artifacts/cache/work/logs/metadata remain untouched.

## 6. Repeat

Repeat resolves the historical exact build through current `SearchBuilds`, then current languages and editions, and returns to Build. If exact build is unavailable, replacement with current recommended build requires explicit user choice; Catalog and Cancel must remain available. Old BuildPlan must never execute directly.

## 7. Profiles

Profile schema is independent version `1`; store is `%LOCALAPPDATA%\WindowsISOBuilder\profiles.json`.

Profile identity is UUID. Name is required, trimmed, 1..80 characters; duplicate display names are allowed.

Supported modes:

- Recommended/Dynamic — current `GetRecommendedBuild` is resolved every use;
- Pinned — controlled concrete build identity is resolved through current `SearchBuilds`.

Profile stores product/architecture/language/editions/format/build options/output directory. Cache directory, BuildPlan, UUP catalog snapshot, signed URLs and secrets are excluded.

Create profile is user initiated from Profiles, current Build configuration, or History. History defaults to Recommended mode; pinning the exact historical build is explicit.

## 8. Stale profile/configuration

Saved build/language/edition availability must be checked against current backend data. Missing editions/language are reported; they are not silently dropped/substituted. Pinned-build fallback is explicit and does not silently mutate the saved profile.

## 9. Local persistence

History/Profile stores must:

- carry `schemaVersion`;
- write temp in the same app-owned directory;
- flush/close before replace;
- use atomic replace/move semantics;
- recover malformed current-schema JSON without crashing startup;
- preserve a damaged copy when possible;
- refuse to blindly overwrite unknown future schemas.

Settings remain separate in `AppSettingsService`.

## 10. Privacy/diagnostics/package

History/Profile are local user data and are not sent to the network. They are excluded from diagnostics and release package. Diagnostics fixed allowlist remains:

`app-version.txt`, `environment.json`, `execution.log`, `build.log`, `converter.log`.

## 11. Localization/theme/accessibility

- all new user-visible strings have RU/EN resources with key/placeholder parity;
- schema values are not localized strings;
- System/Light/Dark theme resources are reused;
- new pages avoid hardcoded White/Black surfaces;
- keyboard-only navigation, Tab/Shift+Tab, Enter/Space activation, Esc dialog close and visible focus remain expected;
- primary History/Profile actions expose AutomationProperties;
- card accessibility summary includes product/status/date/architecture/format for History and name/product/mode/language/editions for Profile;
- PerMonitorV2 remains enabled; History/Profile use wrapping/scoped scrolling and must be manually checked at 100/125/150% DPI.

## 12. Automated validation

Required automated coverage includes:

- History/Profile empty/save/load/round-trip/schema;
- retention/newest ordering;
- corruption/future schema/atomic save;
- completed/failed/cancelled/interrupted lifecycle;
- dynamic/pinned profile identity;
- profile create/update/delete/UUID/name/output;
- recommended vs exact pinned resolution;
- unavailable build/language/edition detection;
- no silent edition removal;
- Repeat resolution and explicit recommended fallback boundary;
- localization parity;
- History/Profile shell/navigation/theme/AutomationProperties static regression;
- diagnostics allowlist and package isolation;
- existing Backend Contract/BuildPlan/NDJSON/cancellation/preflight/package/startup tests.

`tools/Invoke-ReleaseValidation.ps1 -Full` remains the release-level automated entry point.

## 13. Manual acceptance

Do not mark PASS without a real run:

- History visual/actions;
- Profile persistence/use/edit/delete;
- keyboard-only Build/History/Profile flow;
- ComboBox keyboard behavior;
- Esc dialogs;
- basic Narrator inspection;
- Light/Dark visible focus;
- DPI 100/125/150%;
- real Windows 11 recommended x64 ru-RU Professional ESD GUI E2E.

## 14. Explicitly out of scope

Queue/parallel builds/scheduling, updater, installer/MSIX, cache-management GUI, USB/Rufus, driver injection, customization/debloat, TPM bypass, activation, accounts, cloud sync, telemetry, profile import/export/sync, automatic history upload, custom UUP downloader/converter.
