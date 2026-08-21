# Статус реализации

## Текущая source-версия

`1.0.0 — Stable release`.

- ApplicationVersion: `1.0.0`;
- GUI Assembly/FileVersion: `1.0.0` / `1.0.0.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

## Реализовано в source

Стабильный v1.0.0 сохраняет существующий GUI/backend baseline: WPF/.NET 10, Build/Catalog, dynamic languages/editions, WIM/ESD, preflight, build progress, cancellation, structured errors, diagnostics, RU/EN, System/Light/Dark, feedback/update flow, TUI/CLI и self-hosted release validation.

Сохраняется Network/Proxy scope:

- одна глобальная Network Policy: `System`, `Direct`, `Custom`;
- `Custom HTTP` и `Custom SOCKS5`;
- отдельный `network.json`, где отсутствие файла означает System;
- fail-closed validation: повреждённая/неполная Custom configuration не превращается в Direct;
- отдельное хранение proxy credential с Windows DPAPI CurrentUser;
- GUI Settings для mode/type/host/port/username/password, Test connection и явной очистки credential;
- общий policy-aware HTTP layer для UUP API/catalog/metadata, online preflight, conversion package и GitHub update checker;
- loopback HTTP bridge для SOCKS5 и generated downloader/aria2;
- generated downloader получает только `127.0.0.1:<ephemeral-port>`, без upstream proxy host/user/password в command line;
- Direct очищает inherited proxy environment для generated downloader;
- публичные PowerShell operations `Get-WibNetworkPolicy`, `Set-WibNetworkPolicy`, `Clear-WibProxyCredential`, `Test-WibNetworkConnection`;
- diagnostic redaction rules для password/proxy credential assignments.

v1.0.0 не добавляет product features относительно принятого v0.3.5-rc.1. Финальный stable pass включает:

- синхронизацию ApplicationVersion/GUI metadata с `1.0.0`;
- сохранение ModuleVersion `0.3.0` и schema versions `1`;
- финальные RU/EN README, release notes, changelog, validation matrix и version docs;
- repository/package/secret-audit gates перед tag/release.

Network Policy остаётся runtime/user setting и не входит в BuildPlan v1. Backend Contract/BuildPlan schema остаются `1`.

## Validation terminology

`Implemented` не означает `PASS`. Конкретный PASS относится только к exact SHA и фиксируется в PR/Actions/validation artifacts.

## Требует фактического выполнения

Для v1.0.0 release workflow требуются:

- Full Windows validation exact branch head;
- required GitHub Actions PASS exact PR head;
- Full Windows validation exact master merge SHA;
- package smoke на финальном package source state;
- проверка, что release ZIP не содержит developer/private/local artifacts;
- current-tree и Git-history secret audit;
- checksum verification;
- packaged GUI startup/backend smoke из финального ZIP.

Реальный ISO build, real proxy E2E, Explorer/taskbar icon и high-DPI checks не заявляются как PASS, пока не выполнены фактически.

## После v1.0.0

Дальнейшая модель — maintenance, bug fixes, security fixes и user-driven development. Новые product tracks не открыты этим документом.
