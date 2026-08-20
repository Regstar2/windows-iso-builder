# Локальные данные GUI

## Область

`v0.4.0-alpha.1` хранит пользовательские GUI-данные только локально в app-owned каталоге `%LOCALAPPDATA%\WindowsISOBuilder`.

| Файл/каталог | Назначение | Schema/retention |
|---|---|---|
| `settings.json` | язык, тема, положение/размер окна | существующий AppSettings format |
| `history.json` | история фактических `ExecuteBuildPlan` операций | History schema `1`, максимум `200` записей |
| `profiles.json` | сохраняемые build profiles | Profile schema `1` |
| `logs\` | GUI logs | отдельный log lifecycle |

History/Profile не находятся рядом с EXE, не используют registry/SQLite и не входят в PowerShell backend state.

## History schema v1

Root:

```json
{
  "schemaVersion": 1,
  "entries": []
}
```

Каждая запись содержит controlled fields: id/timestamps/status, Windows product/version/build/architecture, language/editions/image format/options/output directory, terminal ISO/SHA-256/log/metadata paths и stable error code при наличии.

Не сохраняются signed UUP URLs, HTTP bodies, product keys, tokens/secrets, arbitrary backend response, exception/stack trace, environment dump или полный BuildPlan.

Status хранится как enum value, а не локализованная строка. `Pending` является внутренним состоянием реальной активной операции. На следующем startup незавершённый `Pending` становится `Interrupted`, потому что закрытие/авария GUI не доказывает backend failure.

## Profile schema v1

Root:

```json
{
  "schemaVersion": 1,
  "profiles": []
}
```

Profile хранит UUID identity, имя, timestamps, selection mode, product/architecture, language/editions, image format, build options и output directory.

`Recommended` profile не содержит конкретную UUP build identity и каждый раз использует актуальный `GetRecommendedBuild`. `Pinned` profile содержит только controlled build identity (product/version/build/architecture/preview marker), а не каталог, signed URLs или BuildPlan.

Cache directory не хранится в профиле: он остаётся runtime/application concern существующего build pipeline.

## Atomic persistence

History/Profile используют:

1. сериализацию в temp-файл в том же каталоге;
2. запись с `FileOptions.WriteThrough`;
3. `Flush(flushToDisk: true)`;
4. `File.Replace` для существующего target или move для первого файла;
5. best-effort удаление временного файла.

Единственная существующая копия JSON не перезаписывается напрямую.

## Corruption и schema compatibility

Malformed/invalid current-schema JSON:

- не блокирует startup;
- логируется без содержимого store;
- при возможности переименовывается в `*.damaged-<timestamp>-<guid>.json`;
- приложение продолжает работу с пустым store.

Unknown future schema (`schemaVersion > 1`) не считается обычной corruption и **не перезаписывается** текущей версией приложения. Store переходит в controlled read-incompatible/write-blocked state до обновления приложения или ручного вмешательства пользователя.

## Retention

History ограничена `200` записями. При превышении сохраняются самые новые записи, старые удаляются oldest-first. Это удаляет только History records; файлы ISO/cache/work/log/metadata не затрагиваются.

## Privacy

History/Profile:

- не отправляются в UUP dump/Microsoft/GitHub;
- не включаются в diagnostics package;
- не копируются в release ZIP;
- не синхронизируются в облако;
- не являются telemetry.

Diagnostics сохраняет отдельный фиксированный allowlist: `app-version.txt`, `environment.json`, `execution.log`, `build.log`, `converter.log`, после sanitizer.
