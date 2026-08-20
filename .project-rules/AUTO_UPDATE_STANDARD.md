# Update delivery standard

Adapted from `universal_project_rules_template_v10`.

## Source

The only update metadata source for the current release train is official GitHub Releases for `Regstar2/windows-iso-builder` over HTTPS. No PAT, embedded token, mirror or arbitrary manifest URL is allowed.

## Required behavior

- Installed version comes from the project canonical version flow and is regression-checked against `VERSION`.
- Version comparison follows SemVer precedence, including prerelease identifiers; string comparison is forbidden.
- Channels are `Stable` and `Prerelease`, with `Stable` as default.
- Stable ignores prerelease releases; Prerelease may see both.
- A manual `Check for updates` action is required.
- Network/API/timeout failures are non-fatal to the application.
- Release notes or a bounded summary are shown when available.
- Optional updates can be declined.

## Safe portable fallback

Windows ISO Builder is currently distributed as a portable self-contained ZIP. The application must not replace its own executable or run a downloaded binary. For v1.0.0, the safe fallback is:

```text
check official GitHub Releases
-> compare versions
-> offer update
-> open the validated official github.com release page
```

A future self-installer requires its own integrity/signature and rollback design; it is not part of the current release train.

## Network policy integration

v0.3.3 uses a minimal injectable HTTP-client boundary. v0.3.4 must route update checks through the same global System/Direct/Custom proxy policy as the rest of the application. No update-only proxy setting is allowed.
