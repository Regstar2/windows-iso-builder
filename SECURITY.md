# Security

Do not publish UUP download URLs from logs: Microsoft CDN links may be temporary and can contain opaque identifiers.

Report vulnerabilities privately to the repository owner. Do not include Windows product keys, personal paths, access tokens, or complete private logs in a public issue.

The tool must not disable antivirus, UAC, or system-wide PowerShell security settings. The generated UUP dump package is executed only after the ZIP structure is validated and inside the tool-owned cache directory.
