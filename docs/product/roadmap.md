# Windows ISO Builder — roadmap

Windows ISO Builder v1.0.0 is released as the stable baseline from the accepted pre-1.0 release train. New unrelated features are deferred until real user feedback exists.

## v0.3.3 — Feedback & Update Delivery

Goal: close the public feedback and safe update-discovery requirements without changing the UUP/build backend.

- GitHub Bug Report and Feature Request Issue Forms;
- in-app feedback entry points;
- Stable / Prerelease update channels;
- manual GitHub Releases update check;
- SemVer-aware comparison;
- release-notes summary and safe transition to the official GitHub release page;
- no self-replacing updater;
- minimal injectable networking seam for the next network-policy release;
- RU/EN, tests, version/docs synchronization.

## v0.3.4 — Network Access & Proxy

Goal: one global network policy for all outbound traffic.

- System / Direct / Custom;
- HTTP / SOCKS5;
- protected proxy credentials;
- UUP API, downloader/CDN and update-check integration;
- no silent fallback from broken Custom to Direct;
- GUI plus supported TUI/CLI path;
- automated and real proxy validation.

## v0.3.5-rc.1 — Public Release Hardening

No new product features. Only blocker fixes, version/release synchronization, security, documentation, packaging, Git-history secret audit and final automated/manual acceptance.

## v1.0.0 — Released / Stable

Stable release from the accepted RC. No new functionality beyond release/version metadata corrections.

## Maintenance model

After v1.0.0 the default mode is maintenance, bug fixes, security fixes and user-driven development. No v1.1.0 feature train is defined.

Only reconsider larger product work with user demand or a demonstrated technical need:

- History / Profiles;
- queue or parallel builds;
- installer/MSIX;
- USB writer/Rufus integration;
- Windows customization/debloat/unattended setup;
- driver injection;
- account/cloud/telemetry/plugin systems;
- custom UUP downloader/converter.
