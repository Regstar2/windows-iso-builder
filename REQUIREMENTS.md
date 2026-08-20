# Требования к Windows ISO Builder v0.3.3

## Версии

- ApplicationVersion: `0.3.3`; source of truth — root `VERSION`.
- GUI Version/FileVersion: `0.3.3` / `0.3.3.0`.
- PowerShell ModuleVersion: `0.3.0`.
- Backend Contract SchemaVersion: `1`.
- BuildPlan SchemaVersion: `1`.

GUI version должна совпадать с root `VERSION`; ModuleVersion и schema versions независимы.

## Runtime

Пользовательский release: Windows 10/11 x64, self-contained `win-x64`; отдельный .NET Runtime не требуется. Backend сохраняет Windows PowerShell 5.1, standard Windows servicing tools, доступ к UUP dump / Microsoft CDN, достаточное место и UAC только для privileged build stage.

## Architecture invariants

- C# WPF/.NET 10 GUI не является вторым build backend.
- Все build operations идут через `Invoke-WibBackend.ps1` и Backend Contract v1.
- GUI не вызывает private PowerShell functions, не парсит human console output и не управляет aria2/DISM process tree самостоятельно.
- Recommendation/language/edition catalogs остаются dynamic и backend-owned.
- BuildPlan создаётся только backend и preflight остаётся backend-owned.
- Cancellation идёт через `CancelBuild`; GUI не kill-ит build processes.

## Feedback — v0.3.3

Обязательны GitHub Issue Forms для bug report и feature request и встроенные About actions RU/EN. Клиент открывает browser forms и не содержит GitHub write token. Diagnostics не прикладываются автоматически. Issue URLs не должны автоматически включать секреты, product keys, proxy credentials, private URLs или personal paths.

До публичного beta/stable target tracker обязан быть доступен конечным пользователям; private inaccessible Issues не считаются acceptance.

## Update Delivery — v0.3.3

Источник: официальный GitHub Releases `Regstar2/windows-iso-builder` по HTTPS, без PAT/token/mirror/custom manifest.

Требуется:

- Stable (default) и Prerelease channels;
- Stable не предлагает prerelease;
- SemVer comparison, не string comparison;
- ручная команда Check for updates;
- async network request с bounded timeout;
- network/API/timeout failure не ломает приложение/Build flow;
- номер новой версии и bounded release-notes summary;
- пользователь может отказаться;
- release link открывается только если это HTTPS `github.com`;
- никакого автоматического download/self-replace/execute.

Safe fallback до v1.0.0: обнаружить update → предложить → открыть официальный GitHub release page. Причина отсутствия self-update зафиксирована в architecture.

v0.3.3 вводит `IHttpClientProvider` только как минимальный seam. Полная System/Direct/Custom policy относится к v0.3.4 и не должна заявляться как готовая раньше.

## Localization / accessibility

RU и EN обязательны, EN fallback. Новые strings добавляются парно и проходят parity checks. Основные действия получают keyboard/automation behavior в рамках WPF conventions.

## Security / diagnostics

- signed UUP URLs, tokens, product keys, secrets и arbitrary payloads не логируются;
- diagnostics — fixed allowlist и sanitizer;
- release package не содержит `.github`, `.project-rules`, tests, bin/obj, logs, local configs или PDB;
- update checker не содержит Authorization secret;
- full Git-history secret audit является отдельным pre-public gate.

## Validation

Current-head Full validation обязательна перед merge. Фактические результаты фиксируются в PR/Actions и не подменяются implementation status. Manual external feedback/update acceptance, DPI/keyboard and real ISO E2E остаются `NOT RUN` до фактического выполнения.

## Out of scope v0.3.3

Global proxy policy (следующая v0.3.4), History/Profiles, queue, installer/MSIX, USB writer, customization/debloat, drivers, TPM bypass, activation, accounts/cloud/telemetry/plugins и custom UUP downloader/converter.
