# Статус реализации

## Текущая source-версия

`0.3.5-rc.1 — Public Release Hardening`.

- ApplicationVersion: `0.3.5-rc.1`;
- GUI Assembly/FileVersion: `0.3.5-rc.1` / `0.3.5.1`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

## Реализовано в source

Сохраняется существующий GUI/backend baseline: WPF/.NET 10, Build/Catalog, dynamic languages/editions, WIM/ESD, preflight, build progress, cancellation, structured errors, diagnostics, RU/EN, System/Light/Dark, feedback/update flow, TUI/CLI и self-hosted release validation.

Сохраняется v0.3.4 Network/Proxy scope:

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

v0.3.5-rc.1 не добавляет product features. Текущий RC hardening в source включает:

- синхронизацию ApplicationVersion/GUI metadata с `0.3.5-rc.1`;
- сохранение ModuleVersion `0.3.0` и schema versions `1`;
- GUI validation, запрещающую сохранить proxy password без username;
- user-facing mappings для proxy configuration/credential/connection/authentication failures в общем error panel;
- небольшую final-polish правку spacing для переносимых action-кнопок и строки выбора Catalog;
- усиление `.gitignore` и release package denylist для validation/test/local network artifacts;
- RC release/version документацию и manual acceptance checklist.

Network Policy остаётся runtime/user setting и не входит в BuildPlan v1. Backend Contract/BuildPlan schema остаются `1`.

## Validation terminology

`Implemented` не означает `PASS`. Конкретный PASS относится только к exact SHA и фиксируется в PR/Actions/validation artifacts.

## Требует фактического выполнения

Перед merge v0.3.5-rc.1:

- Full Windows validation exact branch head;
- package smoke на финальном package source state;
- проверка, что release ZIP не содержит developer/private/local artifacts;
- current-tree и Git-history secret audit.

Перед первым публичным release дополнительно остаются:

- packaged GUI RU/EN Network Settings smoke;
- manual System / Direct / Custom HTTP / Custom SOCKS5 Test connection;
- controlled proxy build-path smoke с generated downloader;
- проверка сохранения/замены/очистки credential на обычной пользовательской учётной записи;
- final packaged GUI ISO E2E;
- внешний update/feedback acceptance после доступности public repository/tracker.

Реальный ISO build, proxy E2E, Explorer/taskbar icon и high-DPI checks не заявляются как PASS, пока не выполнены фактически.

## Следующий этап

Принять или отклонить RC. `v1.0.0` должен содержать только финальные release actions и version/release metadata corrections относительно принятого RC.
