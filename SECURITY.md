# Security

## Reporting vulnerabilities

Do not report security vulnerabilities through the normal Bug Report form. Report them privately to the repository owner. If GitHub Private Vulnerability Reporting is enabled for the repository, use that path; otherwise contact the owner through the available private channel.

Never include Windows product keys, access tokens, passwords, cookies, proxy credentials, signed UUP download URLs, personal paths, private documents or complete unredacted logs in a public issue.

## Runtime boundaries

- Windows ISO Builder does not disable antivirus, UAC or system-wide PowerShell security settings.
- Generated UUP dump packages are validated structurally and executed only inside the tool-owned cache/work flow.
- GUI/backend process arguments are controlled; user strings are not executed as PowerShell code.
- Update checks use the official GitHub Releases endpoint without embedded GitHub credentials and do not automatically download or execute an update.
- Diagnostics use an allowlist and sanitization before ZIP writes. Users still need to review a diagnostic package before publishing it.

The current-tree/package safety scanner is not a Git-history audit. A separate full-history secret scan is required before publishing a stable release.
