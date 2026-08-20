# Implementation status

## Current target

`v0.4.0-alpha.1 — Build History & Profiles`

Version state:

- root `VERSION`: `0.4.0-alpha.1`;
- GUI Assembly/File version: `0.4.0`;
- PowerShell ModuleVersion: `0.3.0` (unchanged);
- Backend Contract SchemaVersion: `1` (unchanged);
- BuildPlan SchemaVersion: `1` (unchanged);
- History schema: `1`;
- Profile schema: `1`.

## Implemented

### Existing v0.3.x GUI baseline

- WPF/.NET 10 shell;
- Build and responsive Catalog;
- Settings/Help/About;
- RU/EN localization;
- System/Light/Dark themes;
- window state persistence;
- keyboard/accessibility groundwork;
- guided next-action highlighting;
- diagnostics package;
- Backend Contract v1 client;
- CreateBuildPlan/RunPreflight;
- ExecuteBuildPlan NDJSON progress;
- cooperative cancellation;
- structured errors;
- self-contained publish/package and self-hosted validation.

### v0.4.0 History

- History page and navigation;
- versioned `history.json` under LocalAppData;
- controlled History DTO;
- Pending → Completed/Failed/Cancelled lifecycle;
- startup Pending → Interrupted normalization;
- atomic writes/corruption recovery/future-schema write block;
- 200-entry retention, newest-first display;
- filters All/Completed/Failed/Cancelled+Interrupted;
- details dialog with ISO/SHA/log/execution-log/metadata/error code;
- missing-path detection and disabled path actions;
- record delete and clear-history operations that do not delete artifacts;
- Repeat through current SearchBuilds/languages/editions;
- explicit stale-build recommended/Catalog/Cancel UX;
- Create Profile from History defaults to Recommended.

### v0.4.0 Profiles

- Profiles page and navigation;
- separate versioned `profiles.json`;
- UUID identity, 1..80-character trimmed name, duplicate display names allowed;
- Recommended/Dynamic mode;
- Pinned Build mode with controlled build identity;
- create from Profiles/current Build/History;
- edit/delete/persist across restart;
- dynamic availability refresh through current backend catalog;
- stale language/edition detection;
- explicit pinned-build fallback without automatic profile mutation;
- output directory persisted, cache directory omitted.

### Privacy/package

- History/Profile are local only;
- diagnostics fixed allowlist unchanged and excludes local stores;
- release ZIP contains local-data documentation but never runtime-created history/profile files.

## Automated regression coverage added

- LocalDataTests: history/profile schema, round-trip, retention, corruption, future schema, atomic temp cleanup, terminal status records, interruption normalization, controlled DTO, artifact-safe deletion, UUID/update/delete/name/output behavior, dynamic/pinned modes;
- StoredConfigurationResolverTests: recommended and exact pinned resolution, unavailable build/language/edition, no silent edition removal, terminal-history repeat resolution, explicit fallback boundary;
- Pester shell/history/profile regression tests for navigation, theme resources, AutomationProperties, single execution path, local store atomic primitives, package/diagnostics isolation and version compatibility;
- existing localization parity test automatically includes `Strings.LocalData`.

## Requires actual validation before review completion

The following are execution statuses, not implementation claims, and must be filled from real runs:

- C# build/tests: pending self-hosted PR validation;
- Pester/PSScriptAnalyzer: pending self-hosted PR validation;
- Full release validation: pending self-hosted PR validation;
- published GUI startup smoke: pending self-hosted PR validation;
- manual History/Profile smoke: NOT RUN unless explicitly performed;
- keyboard/Narrator/DPI acceptance: NOT RUN unless explicitly performed;
- real Windows 11 recommended x64 ru-RU Professional ESD E2E: NOT RUN unless explicitly performed.

## Out of scope

Queue, parallel builds, scheduling, updater, installer/MSIX, cache-management UI, USB/Rufus, driver injection, customization/debloat, TPM bypass, activation, accounts/cloud sync/telemetry, profile import/export/sync, automatic history upload and custom UUP engine remain intentionally absent.
