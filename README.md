<div align="center">

# Windows ISO Builder

GUI и PowerShell-клиент UUP dump для поиска, загрузки и сборки Windows ISO без ручной работы с UUID, SKU и `ConvertConfig.ini`.

**Русский** · [English](README_EN.md)

</div>

## Статус

Текущая source-версия release train — **`0.3.3`**.

- ApplicationVersion: `0.3.3`;
- PowerShell ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

Проект находится в feature freeze перед первым публичным `v1.0.0`: после v0.3.3 планируются только v0.3.4 Network/Proxy и RC hardening. History/Profiles и другие новые функции отложены.

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
- sanitized diagnostics bundle;
- GitHub Issue Forms и in-app feedback;
- Stable/Prerelease update check через официальный GitHub Releases.

## Быстрый старт GUI

1. Распакуйте release ZIP полностью.
2. Запустите `WindowsISOBuilder.exe` обычным пользователем.
3. Выберите Windows 11/10 и рекомендуемую сборку либо откройте Catalog.
4. Выберите язык, редакции, ESD/WIM и каталог результата.
5. Запустите проверку готовности.
6. Нажмите «Создать ISO» и подтвердите UAC, когда backend запросит повышение прав.
7. После завершения откройте ISO или скопируйте SHA-256.

Release self-contained `win-x64`; отдельная установка .NET Runtime пользователю не нужна.

## Обновления

`Настройки → Обновления` поддерживает каналы Stable и Prerelease и ручную проверку официальных GitHub Releases. Stable не предлагает prerelease.

Приложение **не скачивает и не устанавливает обновление автоматически**. Если новая версия найдена, оно показывает версию/краткие release notes и по согласию открывает проверенную HTTPS-страницу релиза на `github.com`. Это сознательный безопасный fallback для portable ZIP distribution.

Пока repository остаётся private, unauthenticated update check для обычного внешнего клиента может быть недоступен; внешний acceptance выполняется после подготовки public release channel.

## Обратная связь

В `О приложении` доступны «Сообщить об ошибке» и «Предложить улучшение». Они открывают GitHub Issue Forms в браузере без PAT/OAuth в клиенте. Диагностический пакет создаётся отдельно в Settings и никогда не прикладывается автоматически.

Не публикуйте product keys, пароли, tokens, cookies, proxy credentials, private URLs или необработанные персональные данные. Пока tracker private, внешняя доступность feedback считается непроверенной.

## Console / automation

```powershell
.\Start-Builder.cmd
```

или machine-readable entry point:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile .\request.json `
  -ResponseFile .\response.json `
  -EventFile .\events.ndjson
```

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

PowerShell backend остаётся единственным владельцем UUP/build/elevation/cancellation workflow. GUI работает через Backend Contract v1.

Update checker обращается только к официальному GitHub Releases endpoint без Authorization secret и не исполняет скачанные файлы. Requests/paths считаются недоверенными, backend dispatch allowlisted, GUI запускает PowerShell через безопасные process arguments, diagnostics/logging используют redaction.

Подробнее: [архитектура](docs/ARCHITECTURE.md), [Backend Contract](docs/BACKEND_CONTRACT.md), [validation matrix](docs/VALIDATION_MATRIX.md), [security](SECURITY.md), [roadmap](docs/product/roadmap.md).

## Следующий обязательный этап

`v0.3.4 — Network Access & Proxy`: единая System / Direct / Custom policy, HTTP/SOCKS5 и отсутствие silent Direct fallback. До её завершения custom proxy support **не заявляется**.

## Лицензия

Собственный код Windows ISO Builder распространяется по [MIT License](LICENSE). Windows, UUP dump и сторонние инструменты имеют собственные лицензии и условия использования.
