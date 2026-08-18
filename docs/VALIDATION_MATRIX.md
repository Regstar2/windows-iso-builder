# Матрица проверки релиза

## Назначение

Эта матрица отделяет реализованные возможности от реально выполненной проверки. `v0.2.3-alpha.1` — validation/release-hardening версия перед первым GUI; она не добавляет новый пользовательский feature scope.

Статусы:

- **Automated** — проверяется локальным validation workflow без загрузки Windows;
- **Controlled smoke** — безопасный opt-in тест с временными файлами/процессами, без UUP set;
- **Confirmed** — реальный end-to-end сценарий ранее фактически доведён до готового ISO;
- **Not run** — процедура подготовлена, но фактический E2E для этого сценария ещё не выполнен;
- **Not required** — не является release gate данной версии.

## A. Automated

| Проверка | Статус | Примечание |
|---|---|---|
| VERSION / ModuleVersion / SchemaVersion | Automated | `0.2.3-alpha.1` / `0.2.3` / Contract 1 / BuildPlan 1 |
| Import module | Automated | обязательный PS5.1 smoke |
| Полный Pester suite | Automated | запускается только через `tests/Run-Tests.ps1` |
| PSScriptAnalyzer | Automated | Full: отсутствие модуля = FAIL; Quick: SKIPPED |
| Backend `GetVersion` | Automated | JSON request/response |
| `RunPreflight` offline | Automated | не обращается к сети и не скачивает UUP |
| Backend Events | Automated | semantic fields/NDJSON serialization |
| Backend Contract v1 regression | Automated | required fields/commands; additive optional fields разрешены |
| BuildPlan v1 fixture/round-trip | Automated | Schema v1 backward compatibility |
| Release allowlist/denylist | Automated | единая конфигурация для packaging и tests |
| ZIP open/checksum/manifest | Automated | source validation не заменяет package validation |
| Packaged module/GetVersion/RunPreflight | Automated | импорт строго из распакованного ZIP |
| Current tree obvious-secret scan | Automated | ограниченный scan текущих tracked files |
| Release package safety scan | Automated | obvious secrets, personal paths, generated/runtime junk |

Основная команда:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1
```

Полный безопасный release workflow:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Invoke-ReleaseValidation.ps1 -Full
```

Ни Quick, ни Full не должны скачивать UUP set или собирать настоящий Windows ISO.

## B. Controlled smoke

| Проверка | Статус | Примечание |
|---|---|---|
| PowerShell 7 Backend Contract | Controlled smoke | запускается при наличии `pwsh`; отсутствие = SKIPPED |
| PID-rooted process-tree cancellation | Controlled smoke | dummy PowerShell tree, без aria2/DISM/UUP |
| Release ZIP smoke | Controlled smoke | extract → syntax → package module → Backend GetVersion → offline RunPreflight |
| TUI navigation | Manual controlled smoke | Start-Builder.cmd, menu/quick/cache/back/exit; UAC и build не нужны |

TUI smoke:

1. Запустить `Start-Builder.cmd`.
2. Проверить главное меню.
3. Открыть quick submenu и вернуться назад.
4. Открыть информацию о кеше и вернуться назад.
5. Завершить программу через штатный Exit.
6. Не подтверждать реальную сборку и не запускать UAC ради этого smoke.

## C. Real E2E

Минимальная baseline-матрица перед GUI не является Cartesian product.

| Сценарий | Product | Arch | Language | Editions | Format | Статус |
|---|---|---|---|---|---|---|
| A | Windows 11 | x64 | ru-RU | Core + Professional | ESD | **Confirmed baseline** |
| B | Windows 10 | x64 | ru-RU или en-US | Professional | ESD | **Not run** |
| C | Windows 11 | x64 | ru-RU или en-US | одна обычная edition | WIM | **Not run** |

Сценарий A подтверждён ранее на сохранённом build pipeline и остаётся baseline. Он не считается заново выполненным агентом для `v0.2.3-alpha.1`.

Сценарии B и C должны получить **Confirmed** только после фактической ручной сборки готового ISO. До этого статус остаётся **Not run**.

Результат ручного E2E записывается по шаблону `docs/validation/results/.README.md`. ISO, signed UUP URLs, product keys и персональные локальные пути в Git не коммитятся.

## D. Not tested / Not required for v0.2.3

Не требуется ради этой версии:

- полный Windows 10 × Windows 11 × WIM × ESD × editions × languages Cartesian product;
- ARM64 E2E;
- x86 E2E;
- специальный 10+ GB download → cancel → resume test;
- отдельная реальная UUP cancellation build;
- GUI/WPF/WinUI/C# validation;
- installer/MSIX/updater/USB/Rufus scenarios.

## Package-only user flow

Release ZIP проверяется как отдельный артефакт, а не как копия source checkout:

1. скачать ZIP и `.sha256`;
2. проверить checksum;
3. распаковать ZIP;
4. запустить `Start-Builder.cmd`;
5. выбрать quick mode или обычный поиск;
6. выбрать build/language/edition/format;
7. пройти local preflight;
8. UAC появляется только непосредственно перед build;
9. наблюдать progress;
10. получить ISO и его SHA-256.

Автоматический package smoke останавливается до шага реального build и не требует UAC.

## Ограничения safety scan

Встроенный scan — это ограниченная проверка **текущих tracked files и текущего release package** на очевидные секреты, private-key blocks, явные credential assignments, персональные `C:\Users\...` пути и generated/runtime artefacts.

Он **не является аудитом Git history** и не доказывает отсутствие секрета в старых commits, reflog, forks или внешних release assets. Исторический secret audit при необходимости выполняется отдельным специализированным инструментом.
