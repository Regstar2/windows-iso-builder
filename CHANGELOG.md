# Changelog

## Unreleased — v0.3.3

### Added

- RU/EN GUI localization with English fallback, runtime language switching, and persisted explicit language choice;
- system light/dark WPF theme integration and `PerMonitorV2` DPI manifest declaration;
- safe window bounds/maximized-state persistence with current-monitor validation;
- localized accessibility names and explanatory tooltips for the main workflow;
- sanitized `windows-iso-builder-diagnostics.zip` generation with a fixed five-file allowlist;
- dedicated Settings, Help, and About shell pages plus compact guided Build navigation;
- GitHub Bug Report and Feature Request Issue Forms;
- in-app `Report a bug` / `Request a feature` actions that open browser forms without PAT/OAuth;
- persisted update channel with Stable default and explicit Prerelease opt-in;
- manual GitHub Releases update check;
- SemVer-aware version precedence including prerelease identifiers;
- bounded release-notes summary and validated HTTPS `github.com` release-page transition;
- injectable `IHttpClientProvider` seam reserved for the v0.3.4 global network policy;
- tracked project-adapted v10 governance rules and a feature-frozen roadmap to v1.0.0;
- regression coverage for localization, diagnostics, update channels/SemVer/API security, settings, theme/DPI, feedback and compact-layout invariants.

### Changed

- Quick Mode is reorganized into a compact responsive grid without page-level vertical scrolling;
- build progress/status/actions live in a persistent bottom panel;
- successful preflight is summarized in the main window while complete details open separately;
- advanced options open in a dedicated dialog;
- Catalog uses the `DataGrid` as its scrolling region and keeps the selected-build action row visible;
- theme, language, diagnostics and update controls live in Settings;
- ApplicationVersion and GUI version are synchronized to `0.3.3`; PowerShell ModuleVersion remains `0.3.0` because the build backend is unchanged;
- update delivery intentionally uses a portable safe fallback: detect a newer official release and open its GitHub page instead of downloading/replacing/executing application binaries.

### Security

- GUI logs and diagnostics share one sanitizer for HTTP/HTTPS URLs, user-profile paths, usernames, bearer/token/API-key/secret assignments and Windows product keys before diagnostic archive writes;
- `environment.json` uses an explicit diagnostic allowlist instead of dumping process environment variables;
- update requests contain no GitHub Authorization credential and accept an openable release target only on HTTPS `github.com`;
- feedback does not automatically copy logs, diagnostics, secrets or personal data into GitHub Issues;
- project governance is tracked in source but `.project-rules` remains denied from the end-user release package.

### Validation status

- implementation and regression coverage are present in source;
- current-head Full Windows validation must be reported by the branch Pull Request/self-hosted Actions run and is not claimed here before execution;
- manual RU/EN update/feedback acceptance is **NOT RUN** until performed on the packaged current head;
- external feedback/update availability remains **NOT RUN** while the target repository/tracker is private;
- DPI, keyboard/Narrator, full network/proxy acceptance and final real ISO E2E remain separate release-train gates.

## 0.3.0-alpha.1 — 2026-08-18

### Added

- first Windows GUI on C# / WPF / .NET 10;
- Quick Mode for Windows 11 and Windows 10 through Backend Contract `GetRecommendedBuild`;
- Catalog Mode through `SearchBuilds` with architecture, Preview and servicing display filter;
- dynamic language and multi-edition selection;
- ESD/WIM and existing backend build options;
- GUI preflight, progress, cancellation, success and structured error UX;
- strongly typed C# Backend Contract v1 client;
- incremental UTF-8 NDJSON event reader;
- GUI logging and frontend exception boundary;
- C# GUI test project and Windows backend integration smokes;
- `tools/Build-Gui.ps1`;
- self-contained `win-x64` GUI publishing;
- packaged GUI backend handshake smoke;
- GUI architecture documentation in Russian and English.

### Changed

- GUI becomes the recommended interactive user entry point;
- release package contains the GUI together with the existing PowerShell backend/TUI/CLI;
- release validation verifies GUI build/test/publish, package contents, backend handshake and package source isolation;
- release manifest has additive `gui` metadata.

### Compatibility

- ApplicationVersion: `0.3.0-alpha.1`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion remains `1`;
- BuildPlan SchemaVersion remains `1`;
- TUI/CLI remain supported;
- PowerShell backend remains the sole owner of UUP/build/elevation/cancellation workflow.

### Validation status

- C# tests: **NOT RUN** in the agent environment;
- Pester: **NOT RUN** in the agent environment;
- PSScriptAnalyzer: **NOT RUN** in the agent environment;
- PS5.1 smoke: **NOT RUN** in the agent environment;
- PS7 smoke: **NOT RUN** in the agent environment;
- Full release validation: **NOT RUN** in the agent environment;
- manual GUI smoke: **NOT RUN**;
- real GUI Windows 11 x64 ru-RU Professional ESD E2E: **NOT RUN**.

## 0.2.3-alpha.1 — 2026-08-18

### Added

- unified release validation tool;
- structured validation report;
- release package smoke;
- Backend Contract compatibility regression tests;
- BuildPlan v1 fixture/regression;
- release manifest;
- validation matrix;
- release tree/package safety scan.

### Changed

- release packaging is self-validated;
- source validation and release-package validation are explicitly separate;
- backend integration boundary is frozen as GUI baseline;
- validation claims are separated from implementation claims.

### Compatibility

- Backend Contract SchemaVersion `1`;
- BuildPlan SchemaVersion `1`;
- TUI/CLI unchanged;
- PS5.1/PS7 support unchanged.

### Validation status

- automated/controlled validation implementation is complete in the branch;
- Windows 10 real E2E: **NOT RUN**;
- Windows 11 single-edition WIM real E2E: **NOT RUN**;
- Windows 11 x64 ru-RU Core + Professional ESD remains a previously confirmed baseline and is not represented as a new v0.2.3 run;
- exact current execution results must come from the local Windows validation workflow and must never be simulated.

## 0.2.2-alpha.1 — 2026-08-18

### Added

- Backend command `RunPreflight` and reusable aggregated preflight engine;
- structured preflight report with stable check ids, status/severity/code and machine-readable disk/path data;
- optional bounded official UUP dump API reachability check;
- Backend command `CancelBuild` and SHA-256-based runtime cancellation control;
- cooperative cancellation helpers, cancellable retry delays and runtime forwarding through the elevation boundary;
- `cancelled` Backend Contract event and a separate cancelled job state;
- extended structured error taxonomy including host/path/disk/network/download/converter/DISM/ISO/elevation/cancellation failures;
- managed child-process runner with PID-rooted process-tree cancellation;
- reliability/cancellation Pester tests and an opt-in controlled Windows process-tree smoke test.

### Changed

- local preflight runs before UAC, so fatal environment failures do not open an elevation prompt;
- elevated worker repeats critical preflight through the same reusable engine;
- prior host/disk/tool checks share one preflight source of truth;
- retry delays support cancellation;
- `uup_download_windows.cmd` executes through the managed root process while preserving compact progress and `converter-*.log`;
- UUP/converter process tree can be stopped without kill-by-name and without selecting unrelated aria2/DISM processes;
- elevated result protocol carries optional structured error details;
- cancellation preserves UUP cache/work data and aria2 resume state.

### Compatibility

- Backend Contract SchemaVersion remains `1`;
- BuildPlan SchemaVersion remains `1`;
- ApplicationVersion `0.2.2-alpha.1`, ModuleVersion `0.2.2`;
- TUI/CLI, quick mode, WIM/ESD, virtual editions, cache/resume, progress and logs remain compatible;
- Windows PowerShell 5.1 and PowerShell 7 remain target runtimes.

### Validation status

- reliability tests were developed without real Windows downloads;
- process-tree integration smoke is opt-in and uses controlled dummy PowerShell processes;
- release requires the complete Pester suite, PSScriptAnalyzer, Backend `GetVersion`/`RunPreflight` and controlled cancellation smokes on Windows.

## 0.2.1-alpha.1 — 2026-08-18

### Added

- Backend Contract Schema v1 as a machine-readable layer over the existing PowerShell backend;
- ASCII-only `Invoke-WibBackend.ps1` for Windows PowerShell 5.1 and PowerShell 7;
- UTF-8 JSON request/response transport with atomic final response;
- optional UTF-8 NDJSON events;
- stable structured error codes and allowlisted Backend Contract commands;
- controlled DTO conversion for builds, languages, editions, build plans, build results, errors and events;
- Backend Contract/Event Pester tests using mocks;
- Backend Contract documentation RU/EN.

### Changed

- ApplicationVersion is centralized in root `VERSION`;
- module and schema versions remain independently versioned;
- recommendation logic is reusable by TUI and Backend Contract without hardcoded Windows releases;
- converter parsing produces normalized progress consumed by console and structured event sinks;
- existing elevation protocol forwards optional Backend Contract event context;
- network User-Agent reads the runtime application version;
- release packaging includes machine entry point and Backend Contract documentation.

### Compatibility

- existing TUI/CLI/quick mode/UAC/elevation/log/cache/resume behavior is preserved;
- Windows PowerShell 5.1 remains required and PowerShell 7 remains supported.

## 0.2.0-alpha.1 — 2026-08-17

- added a dynamic quick-download path for recommended Windows 11/10 without hardcoded release numbers;
- compact converter/aria2 progress and detailed converter logs;
- structured elevated-process result and execution logging;
- catalog entry classification, pagination and improved selection/sorting;
- Windows PowerShell 5.1 UTF-8/Write-Host compatibility fixes;
- local Pester/PSScriptAnalyzer validation and MIT license.

### Validation status

- local tests and PSScriptAnalyzer are mandatory automated checks;
- a real Windows 11 x64 ru-ru ISO build and Core + Professional multi-edition scenario were historically confirmed;
- Windows 10 E2E, forced network interruption and a complete WIM/ESD manual matrix were not alpha release gates.
