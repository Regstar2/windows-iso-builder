# Backend Contract v1

## Purpose

Backend Contract is a stable machine-readable layer over the existing Windows ISO Builder PowerShell backend. It is intended for future GUI/frontend clients and automation that must not depend on `Write-Host`, localized messages, `Write-Progress`, transcripts, or raw `aria2`/converter output.

The contract does **not** replace `Start-Builder.ps1`, does not implement a second UUP workflow, and is not an HTTP API. The current transport uses local JSON/NDJSON files and a separate PowerShell process.

## Versions

- ApplicationVersion: `0.2.1-alpha.1`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`;
- PowerShell module manifest: `0.2.1`.

These versions are independent. Changing ApplicationVersion does not automatically change the Backend Contract schema.

## Entry point

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile <request.json> `
  -ResponseFile <response.json> `
  -EventFile <events.ndjson>
```

`-EventFile` is optional. `Invoke-WibBackend.ps1` is ASCII-only and targets Windows PowerShell 5.1 compatibility.

## Transport

### RequestFile

- UTF-8 JSON;
- one request object;
- backend treats the contents as untrusted input.

### ResponseFile

- UTF-8 JSON;
- one final response object;
- written atomically through a temporary file next to the destination followed by replacement/move;
- a partially serialized response is not a valid result.

### EventFile

- UTF-8 NDJSON / JSON Lines;
- one JSON event per line;
- optional best-effort telemetry;
- event-write failure must not convert an otherwise valid build into a failure.

Human console output is not part of the protocol.

## Request envelope

```json
{
  "schemaVersion": 1,
  "requestId": "client-generated-id",
  "command": "GetVersion",
  "arguments": {}
}
```

### `schemaVersion`

Required integer. The current implementation supports only `1`.

### `requestId`

Required non-empty string. The backend returns it unchanged in the response and in every event for that request.

### `command`

Required string from the allowlist:

- `GetVersion`;
- `SearchBuilds`;
- `GetRecommendedBuild`;
- `GetLanguages`;
- `GetEditions`;
- `CreateBuildPlan`;
- `ValidateBuildPlan`;
- `ExecuteBuildPlan`.

Arbitrary PowerShell function names, script paths, or code execution are not supported.

### `arguments`

Required object. Commands without parameters use `{}`.

## Success response envelope

```json
{
  "schemaVersion": 1,
  "requestId": "client-generated-id",
  "command": "GetVersion",
  "success": true,
  "applicationVersion": "0.2.1-alpha.1",
  "data": {}
}
```

`success` is always boolean. When `success=true`, `data` is present.

## Error response envelope

```json
{
  "schemaVersion": 1,
  "requestId": "client-generated-id",
  "command": "SearchBuilds",
  "success": false,
  "applicationVersion": "0.2.1-alpha.1",
  "error": {
    "code": "UUP_API_UNAVAILABLE",
    "message": "...",
    "stage": "catalog",
    "details": null,
    "logPath": null
  }
}
```

When `success=false`, `error` is present.

- `error.code` is a stable machine-oriented identifier;
- `error.message` is human-readable and may currently be Russian because the project's human UI is Russian;
- `error.stage` is a normalized contract stage;
- `error.details` contains optional structured details;
- `error.logPath` contains an optional build-log path.

Frontend code must not classify errors by parsing `message`.

## Error codes v1

Minimum set:

- `INVALID_REQUEST` — missing or malformed request envelope;
- `UNSUPPORTED_SCHEMA` — unsupported Backend Contract schemaVersion;
- `INVALID_COMMAND` — command is not in the allowlist;
- `INVALID_ARGUMENT` — command argument has an invalid type/value;
- `BUILD_NOT_FOUND` — required build/recommendation is unavailable;
- `LANGUAGE_NOT_FOUND` — no language metadata is available;
- `EDITION_NOT_FOUND` — no edition metadata is available;
- `UUP_API_ERROR` — non-retryable/application-level UUP API failure;
- `UUP_API_UNAVAILABLE` — UUP API remains unavailable after retry/cache fallback;
- `INVALID_BUILD_PLAN` — BuildPlan validation failed;
- `ELEVATION_FAILED` — elevated worker could not be started or did not return a valid result;
- `BUILD_FAILED` — build/conversion workflow failed;
- `INTERNAL_ERROR` — unexpected backend failure not covered by a more specific code.

New `error.code` values may be added within schema v1. Clients must treat unknown codes as generic failures while preserving the code value for diagnostics.

## Build DTO

```json
{
  "uuid": "...",
  "title": "Windows 11, version 25H2 (...) ",
  "product": "Windows 11",
  "versionLabel": "25H2",
  "build": "26200.1234",
  "architecture": "amd64",
  "entryType": "Windows",
  "createdAt": "2026-08-01T00:00:00.0000000Z",
  "isPreview": false
}
```

The DTO intentionally excludes internal sorting/version helpers and PowerShell metadata.

## Language DTO

```json
{
  "code": "ru-ru",
  "name": "Russian"
}
```

## Edition DTO

```json
{
  "code": "Professional",
  "name": "Windows Pro"
}
```

## Commands

### GetVersion

Arguments:

```json
{}
```

Response `data`:

```json
{
  "applicationVersion": "0.2.1-alpha.1",
  "contractSchemaVersion": 1,
  "buildPlanSchemaVersion": 1
}
```

### SearchBuilds

Arguments:

```json
{
  "search": "Windows 11 25H2",
  "architecture": "amd64",
  "includePreview": false,
  "forceRefresh": false,
  "cacheDirectory": "C:\\UUP-ISO-Work"
}
```

`search` is required. `architecture` supports `amd64`, `arm64`, `x86`, and `all`; other fields are optional.

Response:

```json
{
  "builds": [
    {
      "uuid": "...",
      "title": "...",
      "product": "Windows 11",
      "versionLabel": "25H2",
      "build": "...",
      "architecture": "amd64",
      "entryType": "Windows",
      "createdAt": "...",
      "isPreview": false
    }
  ]
}
```

No search matches is a successful result with `builds: []`.

### GetRecommendedBuild

Arguments:

```json
{
  "product": "Windows 11",
  "architecture": "amd64",
  "forceRefresh": true,
  "cacheDirectory": "C:\\UUP-ISO-Work"
}
```

`product` is `Windows 11` or `Windows 10`. The command uses the same dynamic quick-mode recommendation logic as the TUI; no release/build number is hardcoded.

Response:

```json
{
  "build": { "uuid": "..." }
}
```

The full object follows the build DTO above.

### GetLanguages

Arguments:

```json
{
  "updateId": "...",
  "forceRefresh": false,
  "cacheDirectory": "C:\\UUP-ISO-Work"
}
```

Response:

```json
{
  "languages": [
    { "code": "ru-ru", "name": "Russian" }
  ]
}
```

### GetEditions

Arguments:

```json
{
  "updateId": "...",
  "language": "ru-ru",
  "forceRefresh": false,
  "cacheDirectory": "C:\\UUP-ISO-Work"
}
```

`language` must match the `xx-xx` pattern.

Response:

```json
{
  "editions": [
    { "code": "Professional", "name": "Windows Pro" }
  ]
}
```

### CreateBuildPlan

Arguments:

```json
{
  "build": {
    "uuid": "...",
    "title": "...",
    "product": "Windows 11",
    "versionLabel": "25H2",
    "build": "...",
    "architecture": "amd64",
    "entryType": "Windows",
    "createdAt": "...",
    "isPreview": false
  },
  "language": "ru-ru",
  "editions": ["Core", "Professional"],
  "imageFormat": "ESD",
  "addUpdates": true,
  "cleanup": true,
  "netFx3": false,
  "outputDirectory": "C:\\output",
  "cacheDirectory": "C:\\UUP-ISO-Work"
}
```

The command delegates to the existing `New-WibBuildPlan`; no parallel plan structure exists.

Response:

```json
{
  "plan": {
    "schemaVersion": 1,
    "applicationVersion": "0.2.1-alpha.1",
    "createdAt": "...",
    "build": {},
    "language": "ru-ru",
    "editions": ["Core", "Professional"],
    "sourceEdition": "Core",
    "virtualEditions": ["Professional"],
    "imageFormat": "ESD",
    "addUpdates": true,
    "cleanup": true,
    "netFx3": false,
    "outputDirectory": "C:\\output",
    "cacheDirectory": "C:\\UUP-ISO-Work",
    "removeWorkAfterSuccess": false
  }
}
```

### ValidateBuildPlan

Arguments:

```json
{
  "plan": { "schemaVersion": 1 }
}
```

The complete plan follows the DTO above.

Success:

```json
{
  "valid": true
}
```

An invalid plan returns `success=false` with `error.code=INVALID_BUILD_PLAN`.

### ExecuteBuildPlan

Arguments:

```json
{
  "plan": { "schemaVersion": 1 }
}
```

The command delegates to the existing `Invoke-WibBuildPlan`, including the current UAC/elevation/conversion workflow.

Success `data`:

```json
{
  "stage": "completed",
  "isoPath": "C:\\output\\Windows.iso",
  "sha256": "...",
  "logPath": "C:\\output\\logs\\build-....log",
  "executionLogPath": "C:\\project\\logs\\elevated-....log",
  "workDirectory": "C:\\UUP-ISO-Work\\work\\...",
  "metadataPath": "C:\\output\\Windows.iso.json"
}
```

Some path/hash fields can be empty when the underlying workflow did not reach the stage that creates them.

## Events

One `EventFile` line:

```json
{
  "schemaVersion": 1,
  "requestId": "request-1",
  "sequence": 1,
  "timestamp": "2026-08-18T05:30:00.0000000Z",
  "type": "progress",
  "stage": "download",
  "message": "Downloading Windows files",
  "progress": {
    "percent": 24,
    "detailPercent": 15,
    "speedText": "31MiB",
    "speedBytesPerSecond": 32505856
  }
}
```

### Event types

Required:

- `stage`;
- `progress`;
- `completed`;
- `failed`.

Schema v1 also permits `warning` and `info`.

### Sequence

- starts at `1` for a new EventFile/request;
- increases monotonically;
- an elevated child continues the sequence in the same file;
- all events for the request carry the same `requestId`.

### Timestamp

UTC ISO-8601 string.

### Contract stages

Restricted vocabulary:

- `startup`;
- `catalog`;
- `metadata`;
- `plan`;
- `preflight`;
- `download`;
- `convert`;
- `verify`;
- `completed`;
- `failed`.

Internal stages are explicitly mapped into this vocabulary. For example, `downloading-package` maps to `metadata`, `downloading-uup-and-converting` to `download`, and `validating` to `verify`.

### Progress object

- `percent`: overall progress `0..100` or `null`;
- `detailPercent`: detail/download progress `0..100` or `null`;
- `speedText`: parser-friendly human speed string or `null`;
- `speedBytesPerSecond`: parsed integer bytes/s or `null`.

Overall progress never decreases. Speed parsing and event I/O are best effort and cannot be the reason for a build failure.

## GetVersion smoke request

`request.json`:

```json
{
  "schemaVersion": 1,
  "requestId": "smoke-get-version",
  "command": "GetVersion",
  "arguments": {}
}
```

Expected `response.json` structure:

```json
{
  "schemaVersion": 1,
  "requestId": "smoke-get-version",
  "command": "GetVersion",
  "success": true,
  "applicationVersion": "0.2.1-alpha.1",
  "data": {
    "applicationVersion": "0.2.1-alpha.1",
    "contractSchemaVersion": 1,
    "buildPlanSchemaVersion": 1
  }
}
```

JSON formatting and whitespace are not part of the contract.

## Security model

- request content is untrusted input;
- command dispatch uses an explicit allowlist;
- no `Invoke-Expression`/eval;
- JSON is never interpreted as PowerShell code;
- enum/language/path values are validated before core calls;
- frontend clients do not receive arbitrary Exception object graphs;
- Backend Contract must not expose signed UUP download URLs, product keys, tokens, or other secrets;
- existing UAC/security policy remains unchanged.

## Compatibility policy

Backend Contract Schema v1 guarantees:

- existing properties keep their meaning;
- required properties are not removed;
- new optional properties may be added;
- new commands may be added;
- new `error.code` values may be added;
- clients must ignore unknown optional fields.

A breaking contract change requires `schemaVersion = 2`.

ApplicationVersion does not automatically affect the contract schema.
