# Архитектура Windows ISO Builder

## Граница ответственности

Windows ISO Builder состоит из трёх основных слоёв:

1. WPF GUI (`src/WindowsISOBuilder.Gui`) — пользовательский интерфейс и presentation-only сервисы.
2. `Invoke-WibBackend.ps1` + Backend Contract Schema v1 — машиночитаемая граница GUI/backend.
3. PowerShell module (`src/WindowsISOBuilder`) — единственный владелец UUP catalog, recommendation, BuildPlan, preflight, elevation, download/conversion/DISM, ISO validation и cancellation.

GUI не импортирует private PowerShell functions и не реализует второй build engine. BuildPlan SchemaVersion остаётся `1`.

## Версионирование

Root `VERSION` — канонический ApplicationVersion для backend/package/release tooling. GUI project version обязан совпадать с ним и это закреплено regression test. ModuleVersion и schema versions независимы и меняются только при соответствующем изменении контракта/модуля.

## v0.3.3 — Feedback

`AboutView` открывает только браузерные GitHub Issue Forms:

- bug report;
- feature request.

В приложение не встраивается GitHub PAT/OAuth write token. Diagnostic bundle пользователь создаёт и прикладывает самостоятельно.

## v0.3.3 — Update Delivery

Источник метаданных — HTTPS GitHub Releases API для `Regstar2/windows-iso-builder`.

```text
Settings
 -> Stable / Prerelease
 -> Check for updates
 -> GitHubReleaseUpdateService
 -> IHttpClientProvider
 -> official GitHub Releases API
 -> SemanticVersion comparison
 -> optional user confirmation
 -> validated https://github.com release page
```

`GitHubReleaseUpdateService`:

- не использует Authorization/PAT;
- игнорирует draft;
- Stable игнорирует prerelease;
- Prerelease рассматривает stable и prerelease;
- выбирает максимальную валидную SemVer, а не порядок API;
- ограничивает размер отображаемых release notes;
- отдаёт только HTTPS `github.com` как открываемый release URL.

Ошибка проверки обновлений не является ошибкой запуска или сборки.

### Почему нет self-update

Release-модель проекта — portable self-contained ZIP. Без отдельного installer/update host безопасная замена работающего приложения требует дополнительной модели целостности, rollback и migration. До v1.0.0 используется разрешённый safe fallback: приложение обнаруживает обновление и открывает официальный GitHub release; ничего не скачивает и не исполняет автоматически.

## Network seam

v0.3.3 вводит только `IHttpClientProvider` для update checker. Текущий `SystemHttpClientProvider` оставляет `HttpClientHandler.Proxy` не заданным и использует штатное system behavior .NET/Windows. Это не заявляется как завершённая global proxy feature.

v0.3.4 обязана заменить/расширить этот seam общей Network Policy `System / Direct / Custom (HTTP/SOCKS5)` и применить её ко всем outbound путям, включая updater. Update-only proxy setting запрещён.

## Security and diagnostics

Logs/diagnostics проходят через общий sanitizer; package имеет allowlist/denylist. `.project-rules`, `.github`, tests, generated build output, logs and PDB не входят в пользовательский ZIP. Built-in scan проверяет current tree/package, но не историю Git.
