# Validation matrix v0.3.0-alpha.1

This matrix separates implemented validation from validation that was actually executed.

Status vocabulary: **Automated-ready** means the check exists; **Confirmed** means it was actually executed; **Not run** means it was not executed; **Skipped** means an optional runtime is unavailable; **Not required** means it is outside this release gate.

## Automated checks

| Check | Implementation | Required before release |
|---|---|---|
| VERSION / ModuleVersion / schemas | Automated-ready | Pass |
| `dotnet restore/build/test` | Automated-ready | Pass |
| GUI contract/state/event-reader tests | Automated-ready | Pass |
| PowerShell Pester | Existing automated | Pass |
| PSScriptAnalyzer | Existing automated | Pass in Full |
| PS5.1 backend GetVersion/preflight smoke | Automated-ready | Pass |
| PS7 backend smoke | Existing optional | Pass or Skipped |
| managed process-tree cancellation smoke | Automated-ready | Pass in Full |
| `Build-Gui.ps1` self-contained publish | Automated-ready | Pass |
| ZIP/checksum/manifest | Automated-ready | Pass |
| Packaged backend source isolation | Automated-ready | Pass |
| Packaged `WindowsISOBuilder.exe --backend-smoke` (Contract v1 + BuildPlan v1) | Automated-ready | Pass |
| Current-tree/package safety scan | Automated-ready | Pass |

Primary command:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Safe automated validation must not download a UUP set, build a real Windows ISO, or request UAC.

## Self-hosted GitHub Actions

`.github/workflows/windows-self-hosted-validation.yml` is a thin orchestration layer over the same Full validation command. A pull request targeting `master` must receive a successful `Full Windows validation` on runner labels `self-hosted`, `Windows`, `X64` before the PR is moved out of Draft / merged.

Workflow concurrency cancels superseded PR runs and `validation-result.json` is retained as an artifact even on failure. A PASS from an older commit does not validate the current PR head; the result must correspond to the current SHA.

## Manual GUI smoke

Before Ready/Merge on Windows, verify:

1. GUI starts without startup UAC.
2. Quick Mode opens.
3. Windows 11 recommended build loads.
4. Windows 10 recommended build loads.
5. Languages load dynamically.
6. Editions load dynamically and multi-selection works.
7. BuildPlan is created through the backend.
8. RunPreflight displays pass/warning/fatal states and fatal checks block build.
9. Changing build parameters invalidates the old preflight/plan and requires re-checking.
10. Catalog search/architecture/Preview/servicing display filter work.
11. A single Catalog row selection does not start metadata loading; double-click / use-selected enters the common Quick flow.
12. Network/UUP/download/converter/DISM/ISO/preflight failures show controlled `error.code`-based UX.
13. Closing outside a build leaves no backend process; closing during an active build uses CancelBuild.
14. A failed CancelBuild request returns the UI to Building and does not close over an active build.

The agent environment itself does not replace the Windows manual GUI smoke. Status remains **Not run** until the smoke is actually performed.

## Real GUI E2E

Preferred pre-tag scenario: Windows 11, x64/amd64, ru-RU, Professional, ESD, GUI preflight → UAC → progress → ISO → success screen.

Status remains **Not run** until actually executed. Previous backend E2E evidence is not a new GUI E2E run.

## Not required for v0.3.0

Full Cartesian matrices, ARM64/x86 real E2E, installer/MSIX, updater, USB/Rufus, and history/profiles/queue.

## Safety scope

The built-in scan checks current tracked files and the current release package for obvious secrets, personal paths, and generated junk. It is **not a Git-history audit** and does not prove that old commits/reflogs/forks contain no secrets.
