# Матрица проверки v0.3.3

Статусы implementation и фактического выполнения разделяются. До реального запуска текущего SHA ручные и runtime проверки имеют статус **NOT RUN**.

## Автоматические проверки

Перед merge требуются:

- VERSION / GUI version / ModuleVersion / SchemaVersion consistency;
- `dotnet restore/build/test`;
- update SemVer/channel/API/security tests;
- localization resource-key/placeholder parity;
- Pester main suite;
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

## v0.3.3 update checks

Automated coverage должна подтверждать:

- installed == latest;
- latest > installed;
- installed > latest не считается downgrade;
- Stable игнорирует prerelease;
- Prerelease может выбрать более новую prerelease;
- malformed/missing tags игнорируются безопасно;
- GitHub request не содержит Authorization;
- release URL принимается только как HTTPS `github.com`;
- network/timeout API failures остаются контролируемыми и не меняют build state;
- update channel сохраняется, default — Stable.

## Manual GUI acceptance — NOT RUN до фактической проверки

На packaged build проверить RU и EN:

1. Settings показывает Updates, Stable/Prerelease и Check for updates.
2. При отсутствии/ошибке сети приложение остаётся работоспособным.
3. Update available показывает текущую/новую версию и release notes summary.
4. Пользователь может отказаться.
5. При согласии открывается официальный GitHub release URL.
6. About содержит Report a bug / Request a feature.
7. Оба действия открывают нужные forms после доступности tracker целевой аудитории.

## Core regression

Сохраняются manual smoke основного Build/Catalog flow, theme, resize/DPI, keyboard и один real packaged GUI ISO E2E до stable release. v0.3.3 не заменяет эти финальные release gates.

## Safety scope

Built-in safety scan проверяет текущие tracked files и current release package. Это **не Git-history audit**. Перед public stable требуется отдельный full-history secret scan.
