# Changelog

## 1.0.0 — 2026-08-21

### Released

- first stable public release from the accepted `v0.3.5-rc.1` baseline;
- WPF GUI over the documented Backend Contract v1 and existing PowerShell backend;
- dynamic UUP dump catalog for Windows 10/11 without hardcoded build catalogs;
- recommended build flow plus full Catalog;
- dynamic language/edition selection, multi-edition builds, WIM/ESD and existing converter options;
- structured preflight before UAC, elevated build execution, progress, cancellation, result actions and SHA-256 display;
- sanitized diagnostics, GUI logs and structured error handling;
- RU/EN localization with English fallback and System/Light/Dark theme support;
- in-app feedback links to GitHub Issue Forms without embedded PAT/OAuth;
- manual Stable/Prerelease update discovery through official GitHub Releases with no self-updater;
- global Network Policy with System, Direct, Custom HTTP and Custom SOCKS5;
- protected proxy credentials through Windows DPAPI CurrentUser;
- fail-closed Custom proxy handling, loopback proxy bridge for generated downloader/aria2 and diagnostics redaction;
- release validation and packaging hardening for self-contained `win-x64` ZIP artifacts.

### Compatibility

- ApplicationVersion: `1.0.0`;
- GUI Version/FileVersion: `1.0.0` / `1.0.0.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion remains `1`;
- BuildPlan SchemaVersion remains `1`;
- no product features, Backend Contract changes, BuildPlan changes, or PowerShell public API changes are introduced relative to the accepted RC.

### Validation status

- exact current-head automated validation is reported by PR/Actions or local validation artifacts and is not claimed in this file before execution;
- manual Network/Proxy acceptance, controlled generated-downloader proxy acceptance, Explorer/taskbar icon visual check, high-DPI visual check, real ISO proxy E2E and final packaged GUI ISO E2E remain **NOT RUN** until performed.

## 0.3.5-rc.1 — 2026-08-21

### Changed

- ApplicationVersion and GUI version are synchronized to `0.3.5-rc.1`; GUI FileVersion/AssemblyVersion use numeric `0.3.5.1`;
- release/package hardening now denies local validation/test/network artifacts such as `pester-result.json`, `network.json`, `proxy-credential.bin`, `settings.json`, `*.tmp`, `*.bak`, `*.old`, `*.pdb`, and local logs;
- RC documentation, validation matrix, and release metadata distinguish implemented source state, automated validation, manual PASS, and NOT RUN checks.

### Fixed

- GUI Network settings now reject saving a proxy password without a proxy username, matching the backend fail-closed policy validation;
- Build/Catalog error UX now maps proxy configuration, credential, connection, and authentication failures to actionable localized messages;
- wrapped Build/About action buttons and Catalog selection summary spacing were tightened to avoid cramped layouts at narrow widths.

### Security

- current-tree/package safety policy was tightened for generated validation artifacts and local proxy/settings files;
- proxy password handling remains unchanged: credentials stay outside `network.json`, BuildPlan, command lines, logs, diagnostics, and release artifacts.

### Compatibility

- ApplicationVersion: `0.3.5-rc.1`;
- GUI Version/FileVersion: `0.3.5-rc.1` / `0.3.5.1`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion remains `1`;
- BuildPlan SchemaVersion remains `1`;
- no product features, Backend Contract changes, BuildPlan changes, or PowerShell public API changes are introduced.

### Validation status

- exact current-head automated validation is reported by PR/Actions or local validation artifacts and is not claimed in this file before execution;
- manual Network/Proxy acceptance, controlled generated-downloader proxy acceptance, Explorer/taskbar icon visual check, high-DPI visual check, real ISO proxy E2E, final packaged GUI ISO E2E, and public feedback/update acceptance remain **NOT RUN** until performed.

## 0.3.4 — 2026-08-21

### Added

- one global Network Policy with `System`, `Direct`, and `Custom` modes;
- Custom HTTP and SOCKS5 proxy support;
- persisted non-secret `network.json` policy and separate Windows DPAPI CurrentUser credential storage;
- GUI Network settings with mode/type/host/port/username/password, save, test-connection, and explicit credential clearing;
- PowerShell API: `Get-WibNetworkPolicy`, `Set-WibNetworkPolicy`, `Clear-WibProxyCredential`, and `Test-WibNetworkConnection`;
- policy-aware UUP API/catalog/metadata, online preflight, conversion-package download, generated downloader/aria2, and GitHub update checks;
- ephemeral loopback HTTP bridge used to keep upstream HTTP/SOCKS5 proxy details out of generated downloader command lines;
- network/security regression coverage for missing/corrupted policy, DPAPI credential round-trip/corruption/clear, Direct bypass, Custom no-fallback, downloader loopback-only behavior, and diagnostic credential redaction.

### Changed

- ApplicationVersion and GUI version are synchronized to `0.3.4`; PowerShell ModuleVersion remains the independent `0.3.0` line for the current `0.3.x` release train;
- Direct mode explicitly bypasses proxy handling and clears inherited HTTP/HTTPS/ALL proxy environment variables for the generated downloader;
- System/Custom generated-downloader paths use only an ephemeral `127.0.0.1:<port>` bridge endpoint;
- the v0.3.3 `IHttpClientProvider` seam is now backed by the global Network Policy.

### Security

- proxy passwords are not written to `network.json`, BuildPlan v1, backend request JSON, generated downloader command lines, logs, diagnostics, or release artifacts;
- invalid Custom configuration and unavailable/corrupted credentials fail closed;
- Custom proxy connection failure never causes a silent Direct retry;
- diagnostic sanitizer additionally redacts password/proxy-password/proxy-credential assignments and credential-bearing URLs.

### Compatibility

- ApplicationVersion: `0.3.4`;
- GUI Version/FileVersion: `0.3.4` / `0.3.4.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion remains `1`;
- BuildPlan SchemaVersion remains `1`;
- Network Policy remains a runtime/user setting and is not added to BuildPlan v1.

### Validation status

- exact current-head automated validation is reported by PR/Actions and is not claimed in this file before execution;
- manual System/Direct/Custom HTTP/Custom SOCKS5 acceptance is **NOT RUN** until performed on the packaged current head;
- controlled generated-downloader proxy acceptance, real ISO proxy E2E, and full Git-history secret audit remain **NOT RUN** until performed.

## 0.3.3 — 2026-08-20

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
- ApplicationVersion and GUI version are synchronized to `0.3.3`; PowerShell ModuleVersion remains `0.3.0` because the module version line is independent;
- update delivery intentionally uses a portable safe fallback: detect a newer official release and open its GitHub page instead of downloading/replacing/executing application binaries.

### Security

- GUI logs and diagnostics share one sanitizer for HTTP/HTTPS URLs, user-profile paths, usernames, bearer/token/API-key/secret assignments and Windows product keys before diagnostic archive writes;
- `environment.json` uses an explicit diagnostic allowlist instead of dumping process environment variables;
- update requests contain no GitHub Authorization credential and accept an openable release target only on HTTPS `github.com`;
- feedback does not automatically copy logs, diagnostics, secrets or personal data into GitHub Issues;
- project governance is tracked in source but `.project-rules` remains denied from the end-user release package.

### Validation status

- implementation and regression coverage are present in source;
- factual validation results are recorded by the corresponding PR/Actions run;
- external feedback/update acceptance remained unavailable while the target repository/tracker was private.

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

- current execution results must come from the local Windows validation workflow and must never be simulated;
- manual GUI and real ISO E2E remain distinct from automated validation.

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
