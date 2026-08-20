# AI text guardrails

Adapted from `universal_project_rules_template_v10`.

AI-generated documentation, PR bodies and release notes must:

- distinguish source implementation from actually executed validation;
- never turn `NOT RUN`, `PENDING` or an old commit PASS into current PASS;
- avoid claims such as “bug-free”, “fully stable” or “production ready” without evidence;
- preserve exact version/schema/status values from the repository;
- state limitations and deferred work plainly;
- never invent checksums, dates, URLs, benchmark numbers or test results;
- never include secrets, private logs, product keys, proxy credentials or personal paths;
- keep RU/EN paired public documents semantically aligned.
