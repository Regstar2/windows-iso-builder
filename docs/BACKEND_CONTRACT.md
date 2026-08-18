# Backend Contract v1

## Назначение

Backend Contract — stable machine-readable adapter над существующим PowerShell backend Windows ISO Builder. Он предназначен для TUI/CLI-adjacent automation и будущего GUI и не зависит от `Write-Host`, `Write-Progress`, transcript, localized exception text или raw converter output.

Transport остаётся локальным: UTF-8 JSON request/response, optional UTF-8 NDJSON events и отдельный PowerShell process. HTTP/RPC server отсутствует.

## Версии

- ApplicationVersion: `0.2.3-alpha.1`;
- ModuleVersion: `0.2.3`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`0.2.3-alpha.1` фиксирует Schema v1 как baseline первого GUI. Additive commands/error codes/event types/optional properties допустимы внутри v1. Удаление или переименование required fields/commands, либо изменение их смысла, является breaking change и требует SchemaVersion 2.

## Entry point

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile <request.json> `
  -ResponseFile <response.json> `
  -EventFile <events.ndjson>
```

`-EventFile` optional. `Invoke-WibBackend.ps1` остаётся ASCII-only для Windows PowerShell 5.1.

## Request envelope

```json
{
  "schemaVersion": 1,
  "requestId": "client-generated-id",
  "command": "GetVersion",
  "arguments": {}
}
```

Required:

- `schemaVersion`: integer, сейчас `1`;
- `requestId`: non-empty string, возвращается без изменения;
- `command`: allowlisted string;
- `arguments`: object.

Request считается untrusted input. JSON не выбирает PowerShell function/script name и не исполняется как code.

## Baseline commands

Schema v1 baseline после `v0.2.3`:

- `GetVersion`;
- `SearchBuilds`;
- `GetRecommendedBuild`;
- `GetLanguages`;
- `GetEditions`;
- `CreateBuildPlan`;
- `ValidateBuildPlan`;
- `ExecuteBuildPlan`;
- `RunPreflight`;
- `CancelBuild`.

Ни одна из этих команд не должна исчезать из v1. Regression tests защищают этот semantic command set.

## GetVersion

Request arguments: `{}`.

Response data:

```json
{
  "applicationVersion": "0.2.3-alpha.1",
  "contractSchemaVersion": 1,
  "buildPlanSchemaVersion": 1
}
```

## Catalog and plan commands

`SearchBuilds`: required `search`; optional `architecture`, `includePreview`, `forceRefresh`, `cacheDirectory`.

`GetRecommendedBuild`: required `product`; optional `architecture`, `forceRefresh`, `cacheDirectory`.

`GetLanguages`: required `updateId`; optional `forceRefresh`, `cacheDirectory`.

`GetEditions`: required `updateId`, `language`; optional `forceRefresh`, `cacheDirectory`.

`CreateBuildPlan`: controlled build DTO + language/editions/imageFormat/options/output/cache paths. Reuses `New-WibBuildPlan`.

`ValidateBuildPlan`: `{ "plan": { ... } }`; invalid data maps to `INVALID_BUILD_PLAN`.

`ExecuteBuildPlan`: `{ "plan": { ... } }`; reuses `Invoke-WibBuildPlan`, existing preflight/elevation/build pipeline and runtime cancellation context.

## Build DTO baseline

Required v1 fields:

- `uuid`;
- `title`;
- `product`;
- `versionLabel`;
- `build`;
- `architecture`;
- `entryType`;
- `createdAt`;
- `isPreview`.

Clients must tolerate additional optional fields.

## BuildPlan DTO baseline

BuildPlan SchemaVersion remains `1`. Required semantic data includes schema/application version, build, language, editions, source/virtual editions, image format, build options, output/cache paths and remove-work option.

A compatibility fixture is stored in `tests/fixtures/build-plan-v1.json`. It is used for read/validate/round-trip regression. Runtime `requestId`, event path and cancellation state are deliberately not BuildPlan fields.

## RunPreflight

Request:

```json
{
  "schemaVersion": 1,
  "requestId": "preflight-123",
  "command": "RunPreflight",
  "arguments": {
    "buildPlan": { "schemaVersion": 1 },
    "onlineChecks": false
  }
}
```

`buildPlan` required. `onlineChecks` defaults to `false`.

Malformed BuildPlan is a contract failure (`success=false`, `INVALID_BUILD_PLAN`). A valid plan in a not-ready environment is a successful operation (`success=true`, `data.ready=false`).

Preflight data retains required fields:

- `ready`;
- `checks`.

Each check retains:

- `id`;
- `status`;
- `severity`;
- `code`;
- `message`;
- `data`.

Current stable ids include `host.windows`, `host.architecture`, `host.powershell`, tool checks, cache/output path checks, disk checks and `network.uupApi`. New check ids are additive.

`onlineChecks=false` performs no network request. `onlineChecks=true` performs only bounded UUP dump API reachability and does not download Windows/UUP data.

## CancelBuild

```json
{
  "schemaVersion": 1,
  "requestId": "cancel-command-123",
  "command": "CancelBuild",
  "arguments": {
    "targetRequestId": "build-request-456",
    "cacheDirectory": "C:\\UUP-ISO-Work"
  }
}
```

Response data retains `requested` and `targetRequestId`.

`requested=true` means only that the cancellation request was accepted. Actual termination is confirmed by the target operation response/event.

Cancellation path is derived from SHA-256 of the target request id; raw request id is never a filename. Managed process termination is rooted at the owned PID tree and never selects processes by name.

## Success response envelope

Required fields:

```json
{
  "schemaVersion": 1,
  "requestId": "...",
  "command": "GetVersion",
  "success": true,
  "applicationVersion": "0.2.3-alpha.1",
  "data": {}
}
```

Additional optional properties are allowed.

## Error response envelope

Required top-level fields:

```json
{
  "schemaVersion": 1,
  "requestId": "...",
  "command": "ExecuteBuildPlan",
  "success": false,
  "applicationVersion": "0.2.3-alpha.1",
  "error": {}
}
```

Error DTO retains `code`, `message`, `stage`, `details`, `logPath`. `details` is controlled and may be null. Exception objects, tokens, signed UUP URLs, product keys and arbitrary internal graphs are excluded.

Existing error codes remain valid, including:

`INVALID_REQUEST`, `UNSUPPORTED_SCHEMA`, `INVALID_COMMAND`, `INVALID_ARGUMENT`, `BUILD_NOT_FOUND`, `LANGUAGE_NOT_FOUND`, `EDITION_NOT_FOUND`, `UUP_API_ERROR`, `UUP_API_UNAVAILABLE`, `INVALID_BUILD_PLAN`, `ELEVATION_FAILED`, `BUILD_FAILED`, `INTERNAL_ERROR`, `UNSUPPORTED_HOST`, `REQUIRED_COMPONENT_MISSING`, `PATH_NOT_WRITABLE`, `DISK_SPACE_LOW`, `NETWORK_ERROR`, `UUP_PACKAGE_DOWNLOAD_FAILED`, `UUP_PACKAGE_INVALID`, `DOWNLOAD_FAILED`, `CONVERTER_FAILED`, `DISM_FAILED`, `ISO_NOT_FOUND`, `ISO_VALIDATION_FAILED`, `ELEVATION_CANCELLED`, `BUILD_CANCELLED`.

Clients classify by `code`, not localized `message`, and treat unknown future v1 codes as generic failures.

## BuildResult baseline

Required semantic fields:

- `stage`;
- `isoPath`;
- `sha256`;
- `logPath`;
- `executionLogPath`;
- `workDirectory`;
- `metadataPath`.

New optional fields are additive.

## Events

Each NDJSON event retains:

- `schemaVersion`;
- `requestId`;
- monotonic `sequence`;
- UTC `timestamp`;
- `type`;
- normalized `stage`;
- `message`;
- `progress`.

Progress retains `percent`, `detailPercent`, `speedText`, `speedBytesPerSecond`.

Event types include `stage`, `progress`, `completed`, `failed`, `cancelled`, `warning`, `info`. Unknown future v1 event types/optional fields must be ignored safely by clients.

## GUI integration boundary

Первый GUI должен использовать только public machine boundary:

- `Invoke-WibBackend.ps1`;
- Backend Contract Schema v1;
- BuildPlan Schema v1;
- `RunPreflight`;
- `ExecuteBuildPlan`;
- `CancelBuild`;
- `requestId`;
- NDJSON events;
- structured error codes.

GUI не вызывает private PowerShell functions, не парсит `Write-Host`, aria2/converter output или localized messages, и не дублирует preflight/cancellation implementation.

## Contract regression policy

Tests сравнивают contract **семантически**, а не byte-for-byte JSON. Они проверяют наличие required baseline fields/commands и не запрещают additive optional evolution.

Fixtures используются только там, где защищают compatibility: v1 GetVersion request и BuildPlan v1. Большой snapshot corpus намеренно не создаётся.

## Release validation is not Contract Schema

`validation-result.json` и `release-manifest.json` относятся к developer/release tooling. Они не являются Backend Contract messages и не повышают Contract SchemaVersion.

## Security

- explicit allowlist dispatch;
- no eval/`Invoke-Expression`;
- normalized controlled paths;
- SHA-256-derived cancellation filename;
- owned PID process-tree termination;
- data-only event transport;
- DTOs exclude secrets/arbitrary internal objects.
