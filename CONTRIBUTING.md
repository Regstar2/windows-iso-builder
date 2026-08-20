# Contributing

Windows ISO Builder is in a feature-frozen release train toward the first public stable release. Read `AGENTS.md`, `docs/product/roadmap.md` and the relevant `.project-rules/` standards before changing code.

Use a dedicated branch and pull request. A change is reviewable only when:

- it stays inside the current release goal;
- it does not hardcode a Windows release catalog;
- Windows PowerShell 5.1 compatibility is preserved;
- user-visible changes include RU and EN resources;
- relevant C# and Pester tests are updated;
- PSScriptAnalyzer has no blocking findings;
- external API assumptions are documented;
- user-visible claims match actual validation;
- unrelated refactoring is excluded.

Pull requests targeting `master` use the owner-controlled Windows self-hosted workflow as a release gate. It runs the repository Full validation. Fork PR code is intentionally not executed on the self-hosted runner. A PASS applies only to the tested commit SHA.

Do not commit secrets, private logs, product keys, proxy credentials, generated ISO/WIM/ESD files or local environment data.
