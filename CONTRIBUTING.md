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

GitHub Actions are not used as a release gate. Verification is performed locally with the commands documented in the README.
