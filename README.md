<div align="center">

# Windows ISO Builder

GUI и PowerShell-клиент UUP dump для поиска, загрузки и сборки Windows ISO без ручной работы с UUID, SKU и `ConvertConfig.ini`.

**Русский** · [English](README_EN.md)

[![Version](https://img.shields.io/badge/VERSION-1.0.0-1f6feb?style=for-the-badge)](VERSION)
[![Windows](https://img.shields.io/badge/WINDOWS-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows11&logoColor=white)](REQUIREMENTS.md)
[![Architecture](https://img.shields.io/badge/ARCH-X64-7C3AED?style=for-the-badge)](REQUIREMENTS.md)
[![Build](https://github.com/Regstar2/windows-iso-builder/actions/workflows/windows-self-hosted-validation.yml/badge.svg?branch=master)](https://github.com/Regstar2/windows-iso-builder/actions/workflows/windows-self-hosted-validation.yml)
[![License](https://img.shields.io/badge/LICENSE-MIT-f97316?style=for-the-badge)](LICENSE)

[Быстрый старт](#быстрый-старт) · [Документация](#документация) · [Релизы](https://github.com/Regstar2/windows-iso-builder/releases) · [Security](SECURITY.md)

</div>

## О проекте

Windows ISO Builder помогает собрать актуальный Windows 10/11 ISO через динамический каталог UUP dump. GUI ведёт пользователя по выбору сборки, языка, редакций, формата образа, проверке готовности и запуску существующего PowerShell build pipeline.

## Интерфейс

### Сборка

![Windows ISO Builder — сборка в тёмной теме](docs/assets/screenshots/build-dark.jpg)

### Каталог Windows

![Windows ISO Builder — каталог Windows](docs/assets/screenshots/catalog-dark.jpg)

## Статус проекта

Текущая стабильная версия — **`1.0.0`**.

- ApplicationVersion: `1.0.0`;
- GUI Version/FileVersion: `1.0.0` / `1.0.0.0`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`v1.0.0` — первый стабильный релиз. Он фиксирует реализованные GUI, Network/Proxy, feedback/update, diagnostics, packaging и validation возможности и подтверждён реальными E2E-сборками Windows 11.

## Возможности

- Windows 11 / Windows 10 через динамический каталог UUP dump без зашитых build numbers;
- рекомендуемая сборка и полный Catalog;
- dynamic languages/editions, multi-edition;
- WIM/ESD и существующие converter options;
- интеграция обновлений и Cleanup доступны как opt-in и по умолчанию выключены для более быстрой обычной сборки;
- structured preflight до UAC;
- progress, logs, cancellation, SHA-256 и result actions;
- WPF GUI + сохранённые TUI/CLI;
- RU/EN с English fallback;
- System/Light/Dark theme;
- единая Network Policy: System / Direct / Custom;
- Custom HTTP и SOCKS5 proxy для UUP API, online preflight, conversion package, generated downloader/aria2 и GitHub update checks;
- Windows DPAPI CurrentUser для сохранённого proxy password;
- fail-closed Custom mode без silent Direct fallback;
- sanitized diagnostics bundle;
- GitHub Issue Forms и in-app feedback;
- Stable/Prerelease update check через официальный GitHub Releases;
- два release-формата: standalone EXE и полный portable ZIP.

## Что скачать

- **`windows-iso-builder-v1.0.0.exe`** — основной вариант для обычного пользователя: один запускаемый файл, содержащий проверенный portable payload.
- **`windows-iso-builder-v1.0.0.zip`** — полный portable package с GUI, PowerShell CLI/backend и документацией.

В ZIP GUI публикуется как один self-contained `WindowsISOBuilder.exe`: рядом с ним нет набора framework/runtime DLL. Отдельная установка .NET Runtime для release-версии не требуется.

## Быстрый старт

1. Скачайте `windows-iso-builder-v1.0.0.exe` из [Releases](https://github.com/Regstar2/windows-iso-builder/releases) либо ZIP, если нужен CLI/portable package.
2. Для EXE — запустите файл. Для ZIP — распакуйте архив полностью и запустите `WindowsISOBuilder.exe`.
3. При необходимости настройте `Настройки -> Сеть`: System, Direct либо Custom HTTP/SOCKS5.
4. Выберите Windows 11/10 и рекомендуемую сборку либо откройте Catalog.
5. Выберите язык, редакции, ESD/WIM и каталог результата.
6. Запустите проверку готовности.
7. Нажмите «Создать ISO» и подтвердите UAC, когда backend запросит повышение прав.
8. После завершения откройте ISO или скопируйте SHA-256.

## Требования

- Windows 10/11 x64;
- доступ к UUP dump и Microsoft CDN;
- достаточно места на диске для UUP cache, work directory и ISO;
- UAC для привилегированной стадии сборки;
- .NET Runtime не требуется для release EXE/ZIP;
- .NET 10 SDK нужен только для сборки из исходников.

## Сеть и proxy

Одна глобальная policy применяется ко всем поддерживаемым исходящим путям приложения.

- **System** — использовать системное proxy-поведение Windows/.NET.
- **Direct** — явно обходить proxy; inherited `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` очищаются для generated downloader.
- **Custom HTTP** — использовать указанный HTTP proxy.
- **Custom SOCKS5** — использовать SOCKS5 transport через локальный loopback bridge приложения.

Для generated UUP downloader/aria2 System и Custom передаются только как ephemeral loopback HTTP endpoint `127.0.0.1:<port>`; upstream proxy host/user/password не попадают в command line. В Custom mode ошибка proxy считается ошибкой proxy и не приводит к скрытой повторной попытке Direct.

Policy хранится отдельно от credential. Proxy password не записывается в `network.json`: он защищается Windows DPAPI CurrentUser. Диагностика дополнительно редактирует password/proxy credential assignments и URL.

## Обновления

`Настройки -> Обновления` поддерживает каналы Stable и Prerelease и ручную проверку официальных GitHub Releases. Stable не предлагает prerelease. Update checker использует ту же глобальную Network Policy.

Приложение **не скачивает и не устанавливает обновление автоматически**. Если новая версия найдена, оно показывает версию/краткие release notes и по согласию открывает проверенную HTTPS-страницу релиза на `github.com`.

## Обратная связь

В `О приложении` доступны «Сообщить об ошибке» и «Предложить улучшение». Они открывают GitHub Issue Forms в браузере без PAT/OAuth в клиенте. Диагностический пакет создаётся отдельно в Settings и никогда не прикладывается автоматически.

Не публикуйте product keys, пароли, tokens, cookies, proxy credentials, private URLs или необработанные персональные данные.

## Console / automation

```powershell
.\Start-Builder.cmd
```

Machine-readable entry point:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson
```

Network Policy также доступна через PowerShell API: `Get-WibNetworkPolicy`, `Set-WibNetworkPolicy`, `Clear-WibProxyCredential`, `Test-WibNetworkConnection`.

## Разработка и release validation

Для разработки GUI требуется .NET 10 SDK.

```powershell
dotnet restore .\WindowsISOBuilder.sln
dotnet build .\WindowsISOBuilder.sln -c Release
dotnet test .\WindowsISOBuilder.sln -c Release --no-build
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Pull requests в `master` запускают ту же Full validation на owner-controlled Windows self-hosted runner. PASS относится только к exact tested SHA.

## Архитектура и безопасность

PowerShell backend остаётся единственным владельцем UUP/build/elevation/cancellation workflow. GUI работает через Backend Contract v1. Network Policy не добавляется в BuildPlan v1 и не меняет Backend Contract SchemaVersion.

Requests/paths считаются недоверенными, backend dispatch allowlisted, GUI запускает PowerShell через безопасные process arguments, diagnostics/logging используют redaction. Custom proxy configuration/credential failures работают fail-closed.

## Документация

- [Архитектура](docs/ARCHITECTURE.md)
- [GUI architecture](docs/GUI_ARCHITECTURE.md)
- [Backend Contract](docs/BACKEND_CONTRACT.md)
- [Validation matrix](docs/VALIDATION_MATRIX.md)
- [Requirements](REQUIREMENTS.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [Roadmap](docs/product/roadmap.md)

## Ограничения

- Автоматического self-update нет: приложение только открывает официальный GitHub Release.
- Installer/MSIX, USB writer/Rufus integration, History/Profiles, Windows customization, debloat, unattended setup, driver injection, TPM bypass, activation, accounts/cloud sync, telemetry и plugins не входят в v1.0.0.
- Manual proxy acceptance, real ISO E2E, icon/taskbar/high-DPI visual checks имеют отдельные статусы в [validation matrix](docs/VALIDATION_MATRIX.md) и не выводятся из automated PASS.

## Лицензия

Собственный код Windows ISO Builder распространяется по [MIT License](LICENSE). Windows, UUP dump и сторонние инструменты имеют собственные лицензии и условия использования.
