# Network and proxy standard

Adapted from `universal_project_rules_template_v10`. Implementation is scheduled for v0.3.4; this file defines the release requirement and prevents partial proxy claims in v0.3.3.

Required global modes:

- `System` — use the declared Windows/system proxy behavior;
- `Direct` — explicitly bypass custom proxy configuration;
- `Custom` — use the configured proxy and never silently fall back to Direct.

Custom must support HTTP and SOCKS5. All outbound paths must be audited: UUP API/catalog/metadata, package acquisition, Microsoft CDN/downloader/converter paths, update checks and any other network calls.

One normalized network policy must serve GUI, backend, TUI/CLI and update delivery as applicable. Do not create separate proxy settings per integration.

Proxy credentials are secrets. Passwords must not be stored in plaintext settings, logs, diagnostics, BuildPlan, issue URLs, command lines or Git. Persistent credentials require Windows-appropriate protected storage. Broken Custom mode must fail rather than leak traffic directly.

Mock coverage is insufficient by itself; final acceptance includes real Direct/System/HTTP/SOCKS5 checks and a broken-Custom no-fallback check.
