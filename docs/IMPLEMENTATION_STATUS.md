# Статус реализации

## Текущая source-версия

`0.3.4 — Network Access & Proxy`.

- ApplicationVersion: `0.3.4`;
- GUI Assembly/FileVersion: `0.3.4` / `0.3.4.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

## Реализовано в source

Сохраняется существующий GUI/backend baseline: WPF/.NET 10, Build/Catalog, dynamic languages/editions, WIM/ESD, preflight, build progress, cancellation, structured errors, diagnostics, RU/EN, System/Light/Dark, feedback/update flow, TUI/CLI и self-hosted release validation.

v0.3.4 добавляет:

- одну глобальную Network Policy: `System`, `Direct`, `Custom`;
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
- дополнительные diagnostic redaction rules для password/proxy credential assignments;
- C#/Pester regression coverage для persistence, DPAPI, invalid/corrupted state, Direct bypass и no-silent-fallback behavior.

Network Policy остаётся runtime/user setting и не входит в BuildPlan v1. Backend Contract/BuildPlan schema остаются `1`. ModuleVersion остаётся независимой линией `0.3.0` в текущем `0.3.x` release train.

## Validation terminology

`Implemented` не означает `PASS`. Конкретный PASS относится только к exact SHA и фиксируется в PR/Actions/validation artifacts.

## Требует фактического выполнения

Перед merge v0.3.4:

- Full Windows validation exact PR head на self-hosted runner;
- packaged GUI RU/EN Network Settings smoke;
- manual System / Direct / Custom HTTP / Custom SOCKS5 Test connection;
- controlled proxy build-path smoke с generated downloader;
- проверка сохранения/замены/очистки credential на обычной пользовательской учётной записи.

Перед первым публичным release дополнительно остаются:

- final packaged GUI ISO E2E;
- отдельный full Git-history secret audit;
- внешний update/feedback acceptance после доступности public repository/tracker.

Реальный ISO build через каждый тип proxy не заявляется как PASS, пока не выполнен фактически.

## Следующий этап

Только RC hardening и подготовка публичного release. Новые продуктовые функции в release train не добавляются. History/Profiles остаются отложенными до появления реального пользовательского спроса.
