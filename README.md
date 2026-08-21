<div align="center">

# Windows ISO Builder

GUI и PowerShell-клиент UUP dump для поиска, загрузки и сборки Windows ISO без ручной работы с UUID, SKU и `ConvertConfig.ini`.

**Русский** · [English](README_EN.md)

[![Version](https://img.shields.io/badge/VERSION-0.3.5--rc.1-1f6feb?style=for-the-badge)](VERSION)
[![Windows](https://img.shields.io/badge/WINDOWS-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows11&logoColor=white)](REQUIREMENTS.md)
[![Architecture](https://img.shields.io/badge/ARCH-X64-7C3AED?style=for-the-badge)](REQUIREMENTS.md)
[![Build](https://github.com/Regstar2/windows-iso-builder/actions/workflows/windows-self-hosted-validation.yml/badge.svg?branch=master)](https://github.com/Regstar2/windows-iso-builder/actions/workflows/windows-self-hosted-validation.yml)
[![License](https://img.shields.io/badge/LICENSE-MIT-f97316?style=for-the-badge)](LICENSE)

[Быстрый старт](#быстрый-старт-gui) · [Документация](#архитектура-и-безопасность) · [Релизы](https://github.com/Regstar2/windows-iso-builder/releases)

</div>

## Статус

Текущая source-версия release train — **`0.3.5-rc.1`**.

- ApplicationVersion: `0.3.5-rc.1`;
- GUI Version/FileVersion: `0.3.5-rc.1` / `0.3.5.1`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

Проект находится в финальном RC hardening перед первым публичным релизом. v0.3.5-rc.1 не добавляет product features: v0.3.4 Network/Proxy scope сохраняется, а текущая ветка закрывает только финальную полировку, metadata, packaging/security audit и release validation. History/Profiles и другие продуктовые функции отложены.

## Возможности

- Windows 11 / Windows 10 через динамический каталог UUP dump без зашитых build numbers;
- рекомендуемая сборка и полный Catalog;
- dynamic languages/editions, multi-edition;
- WIM/ESD и существующие converter options;
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
- Stable/Prerelease update check через официальный GitHub Releases.

## Быстрый старт GUI

1. Распакуйте release ZIP полностью.
2. Запустите `WindowsISOBuilder.exe` обычным пользователем.
3. При необходимости настройте `Настройки → Сеть`: System, Direct либо Custom HTTP/SOCKS5.
4. Выберите Windows 11/10 и рекомендуемую сборку либо откройте Catalog.
5. Выберите язык, редакции, ESD/WIM и каталог результата.
6. Запустите проверку готовности.
7. Нажмите «Создать ISO» и подтвердите UAC, когда backend запросит повышение прав.
8. После завершения откройте ISO или скопируйте SHA-256.

Release self-contained `win-x64`; отдельная установка .NET Runtime пользователю не нужна.

## Сеть и proxy

Одна глобальная policy применяется ко всем поддерживаемым исходящим путям приложения.

- **System** — использовать системное proxy-поведение Windows/.NET.
- **Direct** — явно обходить proxy; inherited `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` очищаются для generated downloader.
- **Custom HTTP** — использовать указанный HTTP proxy.
- **Custom SOCKS5** — использовать SOCKS5 transport через локальный loopback bridge приложения.

Для generated UUP downloader/aria2 System и Custom передаются только как ephemeral loopback HTTP endpoint `127.0.0.1:<port>`; upstream proxy host/user/password не попадают в command line. В Custom mode ошибка proxy считается ошибкой proxy и не приводит к скрытой повторной попытке Direct.

Policy хранится отдельно от credential. Proxy password не записывается в `network.json`: он защищается Windows DPAPI CurrentUser. Диагностика дополнительно редактирует password/proxy credential assignments и URL.

## Обновления

`Настройки → Обновления` поддерживает каналы Stable и Prerelease и ручную проверку официальных GitHub Releases. Stable не предлагает prerelease. Update checker использует ту же глобальную Network Policy.

Приложение **не скачивает и не устанавливает обновление автоматически**. Если новая версия найдена, оно показывает версию/краткие release notes и по согласию открывает проверенную HTTPS-страницу релиза на `github.com`.

Пока repository остаётся private, unauthenticated update check для обычного внешнего клиента может быть недоступен; внешний acceptance выполняется после подготовки public release channel.

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

Подробнее: [архитектура](docs/ARCHITECTURE.md), [Backend Contract](docs/BACKEND_CONTRACT.md), [validation matrix](docs/VALIDATION_MATRIX.md), [security](SECURITY.md), [roadmap](docs/product/roadmap.md).

## Следующий обязательный этап

Принять или отклонить RC. Перед public v1.0.0 остаются только release actions и фактические проверки: manual Network/Proxy acceptance, финальный packaged GUI ISO E2E, публичная доступность feedback/update channel и full Git-history secret audit.

## Лицензия

Собственный код Windows ISO Builder распространяется по [MIT License](LICENSE). Windows, UUP dump и сторонние инструменты имеют собственные лицензии и условия использования.
