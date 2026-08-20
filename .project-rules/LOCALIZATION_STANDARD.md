# Localization standard

Adapted from `universal_project_rules_template_v10`.

- Required UI locales are `ru` and `en`.
- English is the fallback locale for unsupported or malformed locale requests.
- Every new user-visible string is added to both locales in the same change.
- Resource keys and format placeholders must remain in parity between RU and EN.
- Do not hardcode user-visible English or Russian strings in C# when the existing resource system can represent them.
- Technical identifiers, API names, file names, error codes and commands retain their official spelling.
- README and release notes are maintained as synchronized RU/EN pairs.
- Manual release review includes clipping, keyboard access and the main user flow in both locales.
