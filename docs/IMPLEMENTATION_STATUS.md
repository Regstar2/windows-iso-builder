# Статус реализации

## Текущая source-версия

`0.3.3 — Feedback & Update Delivery`.

- ApplicationVersion: `0.3.3`;
- GUI Assembly/FileVersion: `0.3.3` / `0.3.3.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

## Реализовано в source

Сохраняется существующий GUI/backend baseline: WPF/.NET 10, Quick/Catalog, dynamic languages/editions, WIM/ESD, preflight, build progress, cancellation, structured errors, diagnostics, RU/EN, System/Light/Dark, TUI/CLI и self-hosted release validation.

v0.3.3 добавляет:

- Bug Report и Feature Request GitHub Issue Forms;
- `Report a bug` / `Request a feature` в About без PAT/OAuth;
- persisted update channel: Stable (default) / Prerelease;
- ручной `Check for updates` в Settings;
- официальный GitHub Releases API как единственный update metadata source;
- SemVer-aware comparison, включая prerelease precedence;
- bounded release-notes summary;
- только validated HTTPS `github.com` release link;
- safe portable update fallback: open release page, без download/self-replace/execute;
- injectable `IHttpClientProvider` seam для v0.3.4;
- v10-derived tracked project governance и release roadmap.

PowerShell build backend в v0.3.3 функционально не менялся.

## Validation terminology

`Implemented` не означает `PASS`. Конкретный PASS относится только к exact SHA и фиксируется в PR/Actions/validation artifacts.

## Требует фактического выполнения

Перед merge v0.3.3:

- Full Windows validation текущего PR head на self-hosted runner;
- manual RU/EN Settings/About smoke;
- manual Stable/Prerelease update UX smoke с доступным GitHub release source.

Пока repository private, unauthenticated public-client update/feedback availability не считается внешним PASS.

## Следующая версия

`v0.3.4 — Network Access & Proxy`: System / Direct / Custom, HTTP/SOCKS5, protected credentials и единая политика для всех outbound paths без silent Direct fallback.

History/Profiles и другие новые продуктовые функции отложены после v1.0.0 и только при реальном пользовательском спросе.
