# Engineering principles

Adapted from `universal_project_rules_template_v10` for Windows ISO Builder.

1. Prefer the smallest change that satisfies the current release goal.
2. Preserve the existing C# GUI → Backend Contract → PowerShell backend boundary.
3. Reuse existing implementation paths; do not create a second UUP/download/conversion/preflight/cancellation engine.
4. External catalogs remain dynamic. Do not hardcode supported Windows release numbers or build lists.
5. Treat network input, JSON, paths and external process results as untrusted.
6. Keep secrets out of arguments, logs, diagnostics, issue URLs and repository files.
7. New behavior requires regression coverage at the closest practical layer.
8. Do not hide failures with silent fallbacks that change user intent.
9. Documentation and user-visible claims must describe what the code and completed validation actually prove.
10. Avoid unrelated refactoring during the pre-1.0 release train.
