# Release standard

Adapted from `universal_project_rules_template_v10`.

A release is tied to an exact commit SHA. Do not reuse historical validation claims after code changes.

Before a stable release:

- canonical versions and package metadata agree;
- C# build/tests, Pester, PSScriptAnalyzer, backend smokes, package smoke and self-hosted Full validation pass on the final SHA;
- RU/EN documentation and release notes agree;
- release ZIP contains only allowlisted runtime/docs and passes safety scanning;
- feedback links are accessible to target users;
- update delivery works with Stable/Prerelease semantics;
- v0.3.4 global network/proxy policy passes its required real checks;
- a final packaged GUI Windows 11 ISO E2E is actually performed;
- Windows 10 recommended metadata → BuildPlan → preflight is checked;
- full Git-history secret audit is performed separately from the current-tree/package scanner;
- final ZIP SHA-256 is generated and verified.

Do not tag, publish a release, change visibility or move a published tag without explicit authorization. `v1.0.0` contains no new product functionality relative to the accepted RC other than release/version metadata fixes.
