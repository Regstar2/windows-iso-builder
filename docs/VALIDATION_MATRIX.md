# Матрица проверки v0.3.0-alpha.1

Эта матрица отделяет наличие implementation от реально выполненного validation.

Статусы: **Automated-ready** — код проверки существует; **Confirmed** — реально выполнено; **Not run** — не запускалось; **Skipped** — optional runtime отсутствует; **Not required** — не gate версии.

## Автоматические проверки

| Проверка | Implementation | Требуемый фактический статус перед release |
|---|---|---|
| VERSION / ModuleVersion / SchemaVersion | Automated-ready | Pass |
| `dotnet restore/build/test` | Automated-ready | Pass |
| GUI Contract/MVVM/event-reader tests | Automated-ready | Pass |
| PowerShell Pester | Existing automated | Pass |
| PSScriptAnalyzer | Existing automated | Pass in Full |
| PS5.1 Backend GetVersion/preflight smoke | Automated-ready | Pass |
| PS7 Backend smoke | Existing optional | Pass или Skipped |
| `Build-Gui.ps1` self-contained publish | Automated-ready | Pass |
| Release ZIP/checksum/manifest | Automated-ready | Pass |
| Packaged backend source isolation | Automated-ready | Pass |
| Packaged `WindowsISOBuilder.exe --backend-smoke` | Automated-ready | Pass |
| Current tree/package safety scan | Automated-ready | Pass |

Главная команда:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Safe automated validation не скачивает UUP set, не собирает реальный ISO и не должно открывать UAC.

## Manual GUI smoke

Перед Ready/Merge проверить на Windows:

1. GUI запускается без startup UAC.
2. Quick Mode открывается.
3. Windows 11 recommended build загружается.
4. Windows 10 recommended build загружается.
5. Languages динамически загружаются.
6. Editions динамически загружаются, multi-selection доступен.
7. BuildPlan создаётся через backend.
8. RunPreflight отображает pass/warning/fatal states; fatal блокирует build.
9. Параметры можно изменить и перепроверить.
10. Catalog search/architecture/Preview/servicing display filter работают.
11. Network/invalid/preflight errors показываются controlled UI.
12. Close during non-build не оставляет backend process; close during active build использует CancelBuild.

Текущий агентский environment не является Windows/.NET validation environment, поэтому фактический результат этого smoke должен оставаться **Not run**, пока владелец его не выполнит.

## Real GUI E2E

Желательный pre-tag сценарий:

Windows 11 → x64/amd64 → ru-RU → Professional → ESD → GUI preflight → UAC → progress → ISO → success screen.

До фактической сборки статус: **Not run**. Предыдущие backend E2E не считаются новым GUI E2E.

## Сохранённый backend baseline

Ранее подтверждённый Windows 11 x64 ru-RU multi-edition ESD pipeline остаётся историческим backend baseline, но не заменяет GUI E2E `v0.3.0-alpha.1`.

## Not required for v0.3.0

Полный Cartesian matrix, ARM64/x86 E2E, installer/MSIX, updater, USB/Rufus, history/profiles/queue и GitHub Actions.

## Safety scope

Built-in safety scan проверяет текущие tracked files и current release package на очевидные secrets/personal paths/generated junk. Это **не Git-history audit** и не доказывает отсутствие секрета в старых commits/reflog/forks.
