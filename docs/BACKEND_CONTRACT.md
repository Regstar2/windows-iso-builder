# Backend Contract v1

## Назначение

Backend Contract — stable machine-readable adapter над PowerShell backend Windows ISO Builder. GUI `v0.3.0-alpha.1`, automation и другие clients используют только этот boundary, а не private PowerShell implementation.

Transport: локальные UTF-8 JSON request/response files, optional UTF-8 NDJSON event file и отдельный `powershell.exe` process. HTTP/RPC server отсутствует.

## Версии

- ApplicationVersion: `0.3.0-alpha.1`;
- ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

ApplicationVersion не определяет compatibility. Breaking rename/removal/semantic change required contract data требует SchemaVersion 2. Additive optional fields/error codes/event types допустимы внутри v1.

## Entry point

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile <request.json> `
  -ResponseFile <response.json> `
  -EventFile <events.ndjson>
```

## Request envelope

```json
{
  "schemaVersion": 1,
  "requestId": "client-generated-id",
  "command": "GetVersion",
  "arguments": {}
}
```

`schemaVersion`, non-empty `requestId`, allowlisted `command` и object `arguments` обязательны. Request считается untrusted data и не выбирает script/function name.

## Baseline commands

Schema v1 baseline:

- `GetVersion`;
- `SearchBuilds`;
- `GetRecommendedBuild`;
- `GetLanguages`;
- `GetEditions`;
- `CreateBuildPlan`;
- `ValidateBuildPlan`;
- `RunPreflight`;
- `ExecuteBuildPlan`;
- `CancelBuild`.

### GetVersion

Возвращает:

```json
{
  "applicationVersion": "0.3.0-alpha.1",
  "contractSchemaVersion": 1,
  "buildPlanSchemaVersion": 1
}
```

### Catalog

`SearchBuilds`: required `search`; optional `architecture`, `includePreview`, `forceRefresh`, `cacheDirectory`.

`GetRecommendedBuild`: required `product`; optional `architecture`, `forceRefresh`, `cacheDirectory`. Recommendation остаётся backend-owned.

`GetLanguages`: required `updateId`; optional `forceRefresh`, `cacheDirectory`.

`GetEditions`: required `updateId`, `language`; optional `forceRefresh`, `cacheDirectory`.

Build DTO required semantic fields: `uuid`, `title`, `product`, `versionLabel`, `build`, `architecture`, `entryType`, `createdAt`, `isPreview`.

Language DTO: `code`, `name`. Edition DTO: `code`, `name`.

### CreateBuildPlan

Controlled arguments: `build`, `language`, `editions`, `imageFormat`, `addUpdates`, `cleanup`, `netFx3`, `outputDirectory`, `cacheDirectory`.

Response data contains `plan` with BuildPlan Schema v1. Required semantic fields include `schemaVersion`, `applicationVersion`, `createdAt`, `build`, `language`, `editions`, `sourceEdition`, `virtualEditions`, `imageFormat`, options, output/cache paths, `removeWorkAfterSuccess`.

`ValidateBuildPlan` accepts `{ "plan": { ... } }`.

### RunPreflight

Request arguments use the exact property name `buildPlan`:

```json
{
  "buildPlan": { "schemaVersion": 1 },
  "onlineChecks": false
}
```

A malformed plan is contract failure `INVALID_BUILD_PLAN`. A valid plan in an unready environment is `success=true`, `data.ready=false`.

Data retains `ready` and `checks`. Each check retains `id`, `status`, `severity`, `code`, `message`, `data`. UI/clients classify status/severity/code structurally, not by text.

### ExecuteBuildPlan

Arguments: `{ "plan": { ... } }`. Existing preflight/elevation/build workflow remains the implementation. `ExecuteBuildPlan.requestId` is the operation id used for event correlation/cancellation.

BuildResult semantic fields: `stage`, `isoPath`, `sha256`, `logPath`, `executionLogPath`, `workDirectory`, `metadataPath`.

### CancelBuild

```json
{
  "targetRequestId": "build-request-id",
  "cacheDirectory": "C:\\UUP-ISO-Work"
}
```

Response retains `requested` and `targetRequestId`. `requested=true` acknowledges the cancellation request only. Actual termination is confirmed by the target operation final response/event using `BUILD_CANCELLED`/`cancelled` semantics.

## Response envelopes

Success:

```json
{
  "schemaVersion": 1,
  "requestId": "...",
  "command": "GetVersion",
  "success": true,
  "applicationVersion": "0.3.0-alpha.1",
  "data": {}
}
```

Error has the same envelope with `success=false` and `error`. Error DTO retains `code`, `message`, `stage`, controlled `details`, `logPath`.

Existing codes include `INVALID_REQUEST`, `UNSUPPORTED_SCHEMA`, `INVALID_COMMAND`, `INVALID_ARGUMENT`, `BUILD_NOT_FOUND`, `LANGUAGE_NOT_FOUND`, `EDITION_NOT_FOUND`, `UUP_API_ERROR`, `UUP_API_UNAVAILABLE`, `INVALID_BUILD_PLAN`, `ELEVATION_FAILED`, `BUILD_FAILED`, `INTERNAL_ERROR`, `UNSUPPORTED_HOST`, `REQUIRED_COMPONENT_MISSING`, `PATH_NOT_WRITABLE`, `DISK_SPACE_LOW`, `NETWORK_ERROR`, `UUP_PACKAGE_DOWNLOAD_FAILED`, `UUP_PACKAGE_INVALID`, `DOWNLOAD_FAILED`, `CONVERTER_FAILED`, `DISM_FAILED`, `ISO_NOT_FOUND`, `ISO_VALIDATION_FAILED`, `ELEVATION_CANCELLED`, `BUILD_CANCELLED`.

Clients classify by `code`; unknown future v1 code maps to generic failure.

## Events

Each NDJSON event retains `schemaVersion`, `requestId`, monotonic `sequence`, UTC `timestamp`, `type`, normalized `stage`, `message`, `progress`.

Progress retains `percent`, `detailPercent`, `speedText`, `speedBytesPerSecond`.

Normalized stages include `startup`, `catalog`, `metadata`, `plan`, `preflight`, `download`, `convert`, `verify`, `completed`, `failed`; cancellation uses structured cancellation semantics.

Event types include `stage`, `progress`, `completed`, `failed`, `cancelled`, `warning`, `info`. Unknown additive event types/properties must be ignored safely. Events are telemetry; final response is authoritative completion state.

## GUI boundary

The GUI may use only this public machine boundary. It must not import the module directly, dot-source private files, read internal state as an API, parse `Write-Host`, transcript, aria2/converter output, duplicate DISM/UUP workflow, classify localized messages, or kill backend-owned processes.

## Security

Explicit command allowlist; no eval/`Invoke-Expression`; normalized controlled paths; SHA-256-derived cancellation control path; owned PID-tree termination; DTOs exclude secrets, signed UUP URLs, product keys and arbitrary Exception graphs.
