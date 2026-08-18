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
| `Build-Gui.ps1` self-contained publish | Automated-ready | Pass |
| ZIP/checksum/manifest | Automated-ready | Pass |
| Packaged backend source isolation | Automated-ready | Pass |
| Packaged `WindowsISOBuilder.exe --backend-smoke` | Automated-ready | Pass |
| Current-tree/package safety scan | Automated-ready | Pass |

Primary command:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Safe automated validation must not download a UUP set, build a real Windows ISO, or request UAC.

## Manual GUI smoke

Before Ready/Merge on Windows, verify startup without immediate UAC; Quick Windows 11/10 recommendation; dynamic languages/editions and multi-selection; backend BuildPlan/preflight; fatal preflight gating; parameter changes; Catalog search/architecture/Preview/servicing filter; controlled error UX; and no accidental orphan build on close.

The agent environment used for this implementation is not a Windows/.NET execution environment, so this manual smoke remains **Not run** until performed by the owner.

## Real GUI E2E

Preferred pre-tag scenario: Windows 11, x64/amd64, ru-RU, Professional, ESD, GUI preflight → UAC → progress → ISO → success screen.

Status remains **Not run** until actually executed. Previous backend E2E evidence is not a new GUI E2E run.

## Not required for v0.3.0

Full Cartesian matrices, ARM64/x86 real E2E, installer/MSIX, updater, USB/Rufus, history/profiles/queue, and GitHub Actions.

## Safety scope

The built-in scan checks current tracked files and the current release package for obvious secrets, personal paths, and generated junk. It is **not a Git-history audit** and does not prove that old commits/reflogs/forks contain no secrets.
