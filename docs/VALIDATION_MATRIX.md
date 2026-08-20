# Матрица проверки v0.3.4

Статусы implementation и фактического выполнения разделяются. До реального запуска текущего SHA ручные и runtime проверки имеют статус **NOT RUN**.

## Автоматические проверки

Перед merge требуются:

- VERSION / GUI version / ModuleVersion / SchemaVersion consistency;
- `dotnet restore/build/test`;
- localization resource-key/placeholder parity;
- Pester main suite;
- network policy persistence/default/invalid-state tests;
- DPAPI credential round-trip/corruption/clear tests на Windows;
- Direct proxy bypass regression;
- Custom fail-closed/no-silent-Direct-fallback regression;
- generated downloader loopback-only/credential command-line regression;
- diagnostic proxy-password redaction tests;
- update SemVer/channel/API/security tests через policy-aware provider;
- PSScriptAnalyzer;
- PS5.1 backend/module/offline-preflight smoke;
- PowerShell 7 backend smoke при наличии;
- controlled process-tree cancellation smoke;
- self-contained GUI publish;
- release ZIP/checksum/manifest/package smoke;
- current tree/package safety scan;
- packaged GUI backend startup smoke.

Главная команда:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

## v0.3.4 Network/Proxy coverage

Automated coverage должна подтверждать:

- missing policy → System;
- corrupted/invalid Custom policy → controlled failure;
- credential хранится отдельно от `network.json` и защищён DPAPI;
- corrupted credential → controlled failure;
- Direct не использует proxy adapter и очищает inherited downloader proxy variables;
- Custom HTTP failure не повторяется как Direct;
- UUP API, online preflight, conversion package и generated downloader используют общий policy layer;
- generated downloader command line содержит только loopback endpoint и не содержит upstream proxy host/user/password;
- diagnostics redacts password/proxy credential assignments;
- GUI updater использует policy-aware `IHttpClientProvider`.

## Manual GUI / network acceptance — NOT RUN до фактической проверки

На packaged build проверить RU и EN:

1. Settings показывает Network и System / Direct / Custom.
2. Custom переключает HTTP / SOCKS5 и валидирует host/port.
3. Password не отображает сохранённое значение после перезапуска.
4. Save/replace/clear credential работают ожидаемо.
5. Test connection работает отдельно в System, Direct, Custom HTTP и Custom SOCKS5.
6. Неработающий Custom proxy показывает controlled error без Direct fallback.
7. GitHub update check соблюдает выбранную policy.
8. Build/Catalog online operations соблюдают выбранную policy.

## Controlled downloader/proxy acceptance — NOT RUN до фактической проверки

Отдельно выполнить контролируемый HTTP proxy и SOCKS5 test с generated `uup_download_windows.cmd`/aria2 и подтвердить, что upstream credential не появляется в process command line/logs.

## Core regression

Сохраняются manual smoke основного Build/Catalog flow, theme, resize/DPI, keyboard и один final real packaged GUI ISO E2E перед публичным release. Реальный ISO build через каждый proxy mode не считается PASS, пока не выполнен фактически.

## Safety scope

Built-in safety scan проверяет текущие tracked files и current release package. Это **не Git-history audit**. Перед public release требуется отдельный full-history secret scan.
