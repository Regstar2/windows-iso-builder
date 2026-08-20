# GUI local data

## Scope

`v0.4.0-alpha.1` stores GUI user data only in the app-owned `%LOCALAPPDATA%\WindowsISOBuilder` directory.

| File/directory | Purpose | Schema/retention |
|---|---|---|
| `settings.json` | language, theme, window position/size | existing AppSettings format |
| `history.json` | real `ExecuteBuildPlan` operation history | History schema `1`, maximum `200` entries |
| `profiles.json` | reusable build profiles | Profile schema `1` |
| `logs\` | GUI logs | separate log lifecycle |

History/Profile data is not stored next to the executable, does not use the registry or SQLite, and is not part of PowerShell backend state.

## History schema v1

Root:

```json
{
  "schemaVersion": 1,
  "entries": []
}
```

Each entry contains controlled fields only: id/timestamps/status, Windows product/version/build/architecture, language/editions/image format/options/output directory, terminal ISO/SHA-256/log/metadata paths, and a stable error code when applicable.

Signed UUP URLs, HTTP bodies, product keys, tokens/secrets, arbitrary backend responses, exception/stack traces, environment dumps, and complete BuildPlan JSON are not stored.

Status is persisted as an enum value, not a localized string. `Pending` is an internal state for a real active operation. On the next startup an unfinished `Pending` entry becomes `Interrupted`, because an unexpected GUI exit does not prove backend build failure.

## Profile schema v1

Root:

```json
{
  "schemaVersion": 1,
  "profiles": []
}
```

A profile stores UUID identity, name, timestamps, selection mode, product/architecture, language/editions, image format, build options, and output directory.

A `Recommended` profile does not contain a concrete UUP build identity and resolves the current `GetRecommendedBuild` every time. A `Pinned` profile stores only a controlled build identity (product/version/build/architecture/preview marker), never a catalog snapshot, signed URLs, or BuildPlan.

Cache directory is intentionally not persisted per profile; it remains a runtime/application concern of the existing build pipeline.

## Atomic persistence

History/Profile stores use:

1. serialization to a temporary file in the same directory;
2. writes with `FileOptions.WriteThrough`;
3. `Flush(flushToDisk: true)`;
4. `File.Replace` for an existing target or move for first creation;
5. best-effort temporary-file cleanup.

The only existing JSON copy is never directly overwritten in place.

## Corruption and schema compatibility

Malformed/invalid current-schema JSON:

- does not block application startup;
- is logged without store contents;
- is renamed to `*.damaged-<timestamp>-<guid>.json` when possible;
- falls back to an empty store.

An unknown future schema (`schemaVersion > 1`) is not treated as ordinary corruption and is **not overwritten** by the current application. The store stays in a controlled read-incompatible/write-blocked state until the application is updated or the user intervenes.

## Retention

History is limited to `200` entries. Newest entries are retained and older records are removed oldest-first. Only History records are removed; ISO/cache/work/log/metadata files are not touched.

## Privacy

History/Profile data:

- is not sent to UUP dump, Microsoft, or GitHub;
- is not included in the diagnostics package;
- is not copied into the release ZIP;
- is not cloud-synchronized;
- is not telemetry.

Diagnostics remains a separate fixed allowlist: `app-version.txt`, `environment.json`, `execution.log`, `build.log`, and `converter.log`, after sanitizer processing.
