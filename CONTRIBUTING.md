# Contributing

Windows ISO Builder is released as an early public alpha.

Changes should normally be made in a dedicated branch and submitted through a pull request. A change is ready only when:

- it does not add a hardcoded Windows release catalog;
- Windows PowerShell 5.1 compatibility is preserved;
- local Pester tests pass;
- PSScriptAnalyzer does not report blocking problems;
- external API assumptions are documented;
- user-visible claims match completed validation;
- unrelated refactoring is excluded from the same pull request.

The repository uses an owner-controlled Windows self-hosted GitHub Actions runner as a thin orchestration layer over the same repository-owned validation tooling. The release-level automated entry point remains `tools/Invoke-ReleaseValidation.ps1 -Full`; CI does not replace manual DPI, Narrator, or real Windows ISO end-to-end acceptance.
