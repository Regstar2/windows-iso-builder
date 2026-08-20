# Feedback standard

Adapted from `universal_project_rules_template_v10`.

Windows ISO Builder is an end-user desktop application, so feedback through GitHub Issues is required before public beta/stable.

Required behavior:

- `Report a bug` / `Сообщить об ошибке` opens the project bug Issue Form.
- `Request a feature` / `Предложить улучшение` opens the feature Issue Form.
- The client opens browser forms and does not embed a GitHub PAT/OAuth write token.
- Bug forms request version, Windows environment, architecture, reproduction, expected/actual behavior, optional stable error code and diagnostics only by explicit user choice.
- Feature forms separate the problem from the proposed solution and alternatives.
- Issue URLs, clipboard data and attachments must not automatically contain tokens, cookies, product keys, proxy credentials, private URLs, unredacted personal paths or user files.
- Diagnostic ZIP creation and attachment are explicit user actions.
- A private repository is not considered an externally usable tracker. Final feedback acceptance is `NOT RUN` until the repository or selected tracker is accessible to target users.
- RU and EN entry points and accessibility metadata are required.
