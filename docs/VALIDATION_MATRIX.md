# Матрица проверки v0.3.5-rc.1

Статусы implementation и фактического выполнения разделяются. До реального запуска текущего SHA ручные и runtime проверки имеют статус **NOT RUN**.

## Автоматические gates

Перед merge текущий head должен пройти:

- VERSION / GUI version / ModuleVersion / SchemaVersion consistency;
- `dotnet restore/build/test`;
- RU/EN localization key/placeholder parity;
- Pester main suite;
- network-policy persistence/default/invalid-state tests;
- DPAPI credential round-trip/corruption/clear tests на Windows;
- Direct proxy bypass regression;
- Custom fail-closed/no-silent-Direct-fallback regression;
- generated-downloader loopback-only/credential command-line regression;
- diagnostic proxy-password redaction tests;
- update SemVer/channel/API/security tests через policy-aware provider;
- PSScriptAnalyzer;
- PS5.1 backend/module/offline-preflight smoke;
- PowerShell 7 backend smoke при наличии;
- controlled process-tree cancellation smoke;
- self-contained GUI publish;
- release ZIP/checksum/manifest/package smoke;
- current tracked-tree/package safety scan;
- packaged GUI backend/startup smoke.

Главная команда:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

## v0.3.5-rc.1 hardening coverage

Automated coverage должна подтвердить:

- root `VERSION` и GUI `<Version>` равны `0.3.5-rc.1`;
- GUI FileVersion/AssemblyVersion используют numeric `0.3.5.1`;
- ModuleVersion остаётся `0.3.0`;
- Backend Contract SchemaVersion и BuildPlan SchemaVersion остаются `1`;
- GUI и backend отклоняют proxy password без username;
- proxy configuration/credential/connection/authentication failures имеют user-facing action mappings;
- release package source allowlist не содержит denied paths;
- package/runtime safety scan не пропускает validation/test/local network artifacts.

## Manual GUI / network acceptance — NOT RUN до фактической проверки

| ID | Scenario | Steps | Expected | Actual | Status | Notes |
|---|---|---|---|---|---|---|
| MAN-GUI-001 | RU/EN Settings Network | Открыть packaged GUI в RU и EN, перейти в Settings → Network. | System/Direct/Custom, HTTP/SOCKS5, Host/Port/Username/Password, Save/Test/Clear отображаются без clipping. | | NOT RUN | Требует реального packaged GUI. |
| MAN-GUI-002 | Light/Dark/System theme | Проверить Build/Catalog/Settings/Help/About в Light, Dark и System theme. | Контраст читаемый, disabled controls не теряют текст, layout не прыгает. | | NOT RUN | Включает resize smoke. |
| MAN-NET-001 | System connection | Выбрать System и выполнить Test connection. | Успех или controlled network error без crash. | | NOT RUN | Нужна реальная сеть. |
| MAN-NET-002 | Direct connection | Выбрать Direct и выполнить Test connection. | Трафик идёт без proxy; inherited proxy vars не влияют на generated downloader. | | NOT RUN | Требует наблюдения трафика/окружения. |
| MAN-NET-003 | Custom HTTP proxy | Настроить рабочий HTTP proxy, сохранить, проверить restart/password state и Test connection. | PasswordBox пуст после restart; saved credential обозначен нейтрально; Test connection успешен через proxy. | | NOT RUN | Реальный proxy не заменяется mock-тестом. |
| MAN-NET-004 | Custom SOCKS5 proxy | Настроить рабочий SOCKS5 proxy и выполнить Test connection. | Test connection успешен через SOCKS5 policy. | | NOT RUN | Реальный proxy не заменяется mock-тестом. |
| MAN-NET-005 | Broken Custom no fallback | Настроить нерабочий Custom proxy. | Controlled proxy error; silent Direct fallback отсутствует. | | NOT RUN | Требует наблюдения отсутствия Direct fallback. |
| MAN-UPD-001 | Update check | Проверить Stable/Prerelease update check через выбранную policy. | Network failure не ломает приложение; URL остаётся official `https://github.com/Regstar2/windows-iso-builder`. | | NOT RUN | Внешний acceptance требует доступного public channel. |
| MAN-ICON-001 | Explorer/taskbar icon | Проверить exe, window, taskbar, publish и package output. | Текущая `WindowsISOBuilder.ico` отображается без замены artwork. | | NOT RUN | Визуальный Windows Explorer/taskbar check. |
| MAN-E2E-001 | Full packaged GUI ISO E2E | Из release ZIP собрать реальный ISO через GUI. | ISO создан, SHA-256 показан, logs/result actions работают. | | NOT RUN | Не выводится из automation PASS. |

## Controlled downloader/proxy acceptance — NOT RUN до фактической проверки

Отдельно выполнить контролируемый HTTP proxy и SOCKS5 test с generated `uup_download_windows.cmd`/aria2 и подтвердить, что upstream credential не появляется в process command line/logs.

## Safety scope

Built-in safety scan проверяет текущие tracked files и current release package. Это **не Git-history audit**. Перед public release требуется отдельный full-history secret scan.
