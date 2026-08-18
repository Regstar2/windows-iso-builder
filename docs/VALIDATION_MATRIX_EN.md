# Release Validation Matrix

## Purpose

This matrix separates implemented capabilities from validation that has actually been executed. `v0.2.3-alpha.1` is the validation/release-hardening release before the first GUI and does not add new user-facing feature scope.

Statuses:

- **Automated** — verified by the local validation workflow without downloading Windows;
- **Controlled smoke** — safe opt-in temporary-file/process validation without a UUP set;
- **Confirmed** — a real end-to-end scenario was previously completed to a usable ISO;
- **Not run** — the procedure exists but the scenario has not yet been executed;
- **Not required** — not a release gate for this version.

## A. Automated

| Check | Status | Notes |
|---|---|---|
| VERSION / ModuleVersion / SchemaVersion | Automated | `0.2.3-alpha.1` / `0.2.3` / Contract 1 / BuildPlan 1 |
| Module import | Automated | mandatory PS5.1 smoke |
| Full Pester suite | Automated | invoked only through `tests/Run-Tests.ps1` |
| PSScriptAnalyzer | Automated | Full: missing module = FAIL; Quick: SKIPPED |
| Backend `GetVersion` | Automated | JSON request/response |
| Offline `RunPreflight` | Automated | no network request and no UUP download |
| Backend Events | Automated | semantic fields/NDJSON serialization |
| Backend Contract v1 regression | Automated | required fields/commands; additive optional fields remain allowed |
| BuildPlan v1 fixture/round-trip | Automated | Schema v1 backward compatibility |
| Release allowlist/denylist | Automated | one shared packaging/test configuration |
| ZIP open/checksum/manifest | Automated | source validation does not replace package validation |
| Packaged module/GetVersion/RunPreflight | Automated | imported strictly from the extracted ZIP |
| Current tree obvious-secret scan | Automated | limited scan of current tracked files |
| Release package safety scan | Automated | obvious secrets, personal paths and generated/runtime junk |

Primary command:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1
```

Full safe release workflow:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Neither Quick nor Full may download a UUP set or build a real Windows ISO.

## B. Controlled smoke

| Check | Status | Notes |
|---|---|---|
| PowerShell 7 Backend Contract | Controlled smoke | runs when `pwsh` exists; missing PS7 = SKIPPED |
| PID-rooted process-tree cancellation | Controlled smoke | dummy PowerShell tree, no aria2/DISM/UUP |
| Release ZIP smoke | Controlled smoke | extract → syntax → package module → Backend GetVersion → offline RunPreflight |
| TUI navigation | Manual controlled smoke | Start-Builder.cmd, menu/quick/cache/back/exit; no UAC or build required |

TUI smoke procedure:

1. Run `Start-Builder.cmd`.
2. Verify the main menu.
3. Open the quick submenu and return.
4. Open cache information and return.
5. Exit normally.
6. Do not approve a real build or trigger UAC solely for this smoke.

## C. Real E2E

The minimum pre-GUI baseline is intentionally not a Cartesian product.

| Scenario | Product | Arch | Language | Editions | Format | Status |
|---|---|---|---|---|---|---|
| A | Windows 11 | x64 | ru-RU | Core + Professional | ESD | **Confirmed baseline** |
| B | Windows 10 | x64 | ru-RU or en-US | Professional | ESD | **Not run** |
| C | Windows 11 | x64 | ru-RU or en-US | one regular edition | WIM | **Not run** |

Scenario A was previously confirmed on the preserved build pipeline and remains the baseline. It is not represented as newly executed by the agent for `v0.2.3-alpha.1`.

Scenarios B and C may be changed to **Confirmed** only after a real ISO is built manually. Until then they remain **Not run**.

Manual E2E results use `docs/validation/results/.README.md`. Do not commit the ISO, signed UUP URLs, product keys, or personal local paths.

## D. Not tested / Not required for v0.2.3

This release does not require:

- a complete Windows 10 × Windows 11 × WIM × ESD × editions × languages Cartesian product;
- ARM64 E2E;
- x86 E2E;
- a dedicated 10+ GB download → cancel → resume test;
- a real UUP cancellation build;
- GUI/WPF/WinUI/C# validation;
- installer/MSIX/updater/USB/Rufus scenarios.

## Package-only user flow

The release ZIP is validated as a separate artifact rather than assumed correct because the source checkout passes tests:

1. download the ZIP and `.sha256`;
2. verify the checksum;
3. extract the ZIP;
4. run `Start-Builder.cmd`;
5. choose quick mode or normal search;
6. select build/language/edition/format;
7. pass local preflight;
8. UAC appears only immediately before the build;
9. observe progress;
10. receive the ISO and its SHA-256.

Automated package smoke stops before a real build and never requires UAC.

## Safety-scan limitations

The built-in scan is a limited check of **current tracked files and the current release package** for obvious secrets, private-key blocks, explicit credential assignments, personal `C:\Users\...` paths, and generated/runtime artifacts.

It is **not a Git-history audit** and does not prove that an old commit, reflog, fork, or external release asset never contained a secret. Historical secret auditing requires a separate specialized tool when needed.
