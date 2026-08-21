# Требования к Windows ISO Builder v0.3.5-rc.1

## Версии

- ApplicationVersion: `0.3.5-rc.1`; source of truth — root `VERSION`.
- GUI Version/FileVersion: `0.3.5-rc.1` / `0.3.5.1`.
- PowerShell ModuleVersion: `0.3.0`.
- Backend Contract SchemaVersion: `1`.
- BuildPlan SchemaVersion: `1`.

GUI/ApplicationVersion синхронизированы для v0.3.5-rc.1. ModuleVersion и schema versions остаются независимыми; текущий `0.3.x` release train сохраняет ModuleVersion `0.3.0`.

## RC hardening scope

v0.3.5-rc.1 не добавляет новые product features. Допустимы только исправления подтверждённых дефектов, финальная GUI/UX-полировка, cleanup репозитория, security/package audit, документация, version/release metadata и validation hardening.

## Runtime

Пользовательский release: Windows 10/11 x64, self-contained `win-x64`; отдельный .NET Runtime не требуется. Backend сохраняет Windows PowerShell 5.1, standard Windows servicing tools, доступ к UUP dump / Microsoft CDN, достаточное место и UAC только для privileged build stage.

## Architecture invariants

- C# WPF/.NET 10 GUI не является вторым build backend.
- Все build operations идут через `Invoke-WibBackend.ps1` и Backend Contract v1.
- GUI не вызывает private PowerShell functions, не парсит human console output и не управляет aria2/DISM process tree самостоятельно.
- Recommendation/language/edition catalogs остаются dynamic и backend-owned.
- BuildPlan создаётся только backend и preflight остаётся backend-owned.
- Cancellation идёт через `CancelBuild`; GUI не kill-ит build processes.
- Network Policy является runtime/user setting и не добавляется в BuildPlan v1.

## Network Access & Proxy — реализовано в v0.3.4 и сохраняется в v0.3.5-rc.1

Обязательна одна глобальная политика для всех поддерживаемых outbound paths:

- `System` — системное proxy-поведение Windows/.NET;
- `Direct` — явный bypass proxy;
- `Custom HTTP`;
- `Custom SOCKS5`.

Policy должна применяться к UUP dump API/catalog/metadata, online preflight, conversion-package download, generated UUP downloader/aria2 и GitHub Releases update check.

### Безопасность и отказоустойчивость

- отсутствие `network.json` означает System;
- повреждённый/неполный Custom config завершается controlled `PROXY_CONFIGURATION_INVALID` и не превращается в Direct;
- Custom connection failure завершается controlled proxy/network error и не запускает silent Direct retry;
- proxy password не хранится plaintext в settings/BuildPlan/backend request/command line/logs/diagnostics/release artifact;
- saved password защищается Windows DPAPI CurrentUser;
- `network.json` хранит только non-secret policy fields и `hasCredential` flag;
- generated downloader/aria2 получает System/Custom только через ephemeral loopback HTTP bridge `127.0.0.1:<port>`;
- upstream proxy host/user/password не передаются в generated downloader command line;
- Direct очищает inherited `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` и lowercase variants для generated downloader;
- diagnostics sanitizer редактирует URL, password, proxy-password/proxy-credential assignments и существующие token/secret classes.

### GUI / PowerShell API

Settings должна предоставлять mode, proxy type, host, port, username, PasswordBox, Save, Test connection и явную очистку сохранённого credential. Существующий пароль обратно в UI не отображается.

PowerShell API: `Get-WibNetworkPolicy`, `Set-WibNetworkPolicy`, `Clear-WibProxyCredential`, `Test-WibNetworkConnection`.

## Feedback / Update Delivery

GitHub Issue Forms и in-app feedback v0.3.3 сохраняются. Update checker использует ту же глобальную Network Policy. Источник обновлений остаётся официальный GitHub Releases `Regstar2/windows-iso-builder` по HTTPS без PAT/token/mirror/custom manifest. Автоматического download/self-replace/execute нет.

## Localization / accessibility

RU и EN обязательны, EN fallback. Новые strings добавляются парно и проходят parity checks. Основные действия получают keyboard/automation behavior в рамках WPF conventions.

## Security / diagnostics

- signed UUP URLs, tokens, product keys, secrets и arbitrary payloads не логируются;
- diagnostics — fixed allowlist и sanitizer;
- release package не содержит `.github`, `.project-rules`, tests, bin/obj, logs, local configs, `network.json`, credential store или PDB;
- update checker не содержит Authorization secret;
- full Git-history secret audit является отдельным pre-public gate.

## Validation

Current-head Full validation обязательна перед merge. Automated coverage включает version/schema consistency, C# tests, Pester network-policy/security regressions, PSScriptAnalyzer, PS5.1/PS7 backend smokes, process-tree smoke, package smoke и GUI startup smoke.

Manual Network/Proxy acceptance и real ISO proxy E2E остаются `NOT RUN` до фактического выполнения. Их нельзя выводить из unit/integration PASS.

## Out of scope v0.3.5-rc.1

History/Profiles, queue/parallel builds, installer/MSIX, USB/Rufus, customization/debloat/unattended setup, driver injection, TPM bypass, activation, accounts/cloud/telemetry/plugins, custom UUP downloader/converter, VPN/WARP/Tor и system-wide proxy manager.
