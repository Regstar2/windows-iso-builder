# Development workflow

Adapted from `universal_project_rules_template_v10`.

## Branching

Use a dedicated branch for one release goal. Current train:

```text
master
  -> feature/v0.3.3-feedback-update
  -> feature/v0.3.4-network-proxy
  -> release/v0.3.5-rc1
  -> v1.0.0 metadata only after accepted RC
```

Do not start the next release from an unmerged branch.

## Pull requests

- Open release work as Draft PRs.
- Keep unrelated refactors out.
- Do not merge automatically.
- Self-hosted Full Windows validation is a release gate for the current head.
- Historical PASS does not validate a changed SHA.

## Validation language

Use only factual statuses: `PASS`, `FAIL`, `SKIPPED`, `NOT RUN` and `Implemented`. A feature being implemented does not imply runtime acceptance.

## Scope freeze

Before v1.0.0 only feedback, update delivery, proxy/network policy, localization, security, diagnostics, release/versioning, tests, documentation and blocker fixes are allowed. Other ideas are post-release candidates driven by real user demand.
