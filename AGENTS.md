# Windows ISO Builder agent rules

These repository rules are adapted from `universal_project_rules_template_v10` and are mandatory for AI-assisted changes.

## Read before changing code

Read, in order:

1. `docs/product/roadmap.md`;
2. `REQUIREMENTS.md`;
3. `docs/ARCHITECTURE.md` and `docs/GUI_ARCHITECTURE.md`;
4. the relevant files under `.project-rules/`;
5. the current version document under `docs/versions/`.

## Release-train scope

Until `v1.0.0`, the only planned product work is:

- `v0.3.3` — Feedback & Update Delivery;
- `v0.3.4` — Network Access & Proxy;
- `v0.3.5-rc.1` — Public Release Hardening;
- `v1.0.0` — stable release from the accepted RC.

History, Profiles, queueing, USB writing, installers, customization, telemetry, cloud sync, plugin systems and backend rewrites are outside this train unless a concrete release blocker proves otherwise.

## Non-negotiable boundaries

- PowerShell remains the single owner of UUP catalog/build/preflight/elevation/conversion/cancellation behavior.
- GUI uses `Invoke-WibBackend.ps1` and the documented Backend Contract; do not call private module functions from C#.
- Do not hardcode Windows release/build catalogs.
- Preserve Windows PowerShell 5.1 compatibility.
- User-visible UI strings require RU and EN in the same change; English is fallback.
- Never invent validation results. `Implemented`, `PASS`, `NOT RUN` and historical results are distinct.
- Never put tokens, product keys, proxy credentials, signed UUP URLs or unredacted personal data into source, logs, diagnostics, issues or release artifacts.
- One release goal per feature branch. Do not stack the next release on an unmerged release branch.
- Do not merge, tag, publish a release or change repository visibility without explicit authorization.

## Validation

Use the repository validation entry point for release-bound changes:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

A PASS is valid only for the exact tested SHA. Manual GUI/network/real-ISO checks remain manual until actually run.
