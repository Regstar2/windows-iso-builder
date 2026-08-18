# Backend Contract v1

## Purpose

Backend Contract is the stable machine-readable adapter over the existing Windows ISO Builder PowerShell backend. It is intended for automation and the future GUI and does not depend on `Write-Host`, `Write-Progress`, transcripts, localized exception text, or raw converter output.

Transport remains local: UTF-8 JSON request/response files, optional UTF-8 NDJSON events, and a separate PowerShell process. There is no HTTP/RPC server.

## Versions

- ApplicationVersion: `0.2.3-alpha.1`;
- ModuleVersion: `0.2.3`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`0.2.3-alpha.1` establishes Schema v1 as the baseline for the first GUI. Additive commands, error codes, event types, and optional properties remain compatible within v1. Removing/renaming required fields or commands, or changing their semantics, requires SchemaVersion 2.

## Entry point

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile <request.json> `
  -ResponseFile <response.json> `
  -EventFile <events.ndjson>
```

`-EventFile` is optional. `Invoke-WibBackend.ps1` remains ASCII-only for Windows PowerShell 5.1.

## Request envelope

```json
{
  "schemaVersion": 1,
  "requestId": "client-generated-id",
  "command": "GetVersion",
  "arguments": {}
}
```

Required fields are integer `schemaVersion`, non-empty `requestId`, allowlisted `command`, and object `arguments`. Requests are untrusted input; JSON never selects or executes a PowerShell function by name.

## Baseline commands

Schema v1 baseline after `v0.2.3`:

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`, `RunPreflight`, `CancelBuild`.

None of these commands may disappear from v1. Semantic regression tests protect this baseline.

## GetVersion

```json
{
  "applicationVersion": "0.2.3-alpha.1",
  "contractSchemaVersion": 1,
  "buildPlanSchemaVersion": 1
}
```

## Catalog and plan commands

`SearchBuilds` requires `search`; architecture/preview/refresh/cache fields are optional.

`GetRecommendedBuild` requires `product` and supports optional architecture/refresh/cache fields.

`GetLanguages` requires `updateId`. `GetEditions` requires `updateId` and `language`.

`CreateBuildPlan` accepts the controlled build DTO plus language, editions, image format, build options, and output/cache paths. It reuses `New-WibBuildPlan`.

`ValidateBuildPlan` maps malformed plans to `INVALID_BUILD_PLAN`.

`ExecuteBuildPlan` reuses `Invoke-WibBuildPlan`, the existing preflight/elevation/build pipeline, and runtime cancellation context.

## Build DTO baseline

Required v1 fields: `uuid`, `title`, `product`, `versionLabel`, `build`, `architecture`, `entryType`, `createdAt`, `isPreview`. Clients must tolerate additional optional fields.

## BuildPlan v1

BuildPlan SchemaVersion remains `1`. Required semantic data covers schema/application version, build, language, editions, source/virtual editions, image format, options, output/cache paths, and the remove-work option.

`tests/fixtures/build-plan-v1.json` protects read/validate/round-trip compatibility. Runtime `requestId`, event path, and cancellation state deliberately remain outside the persistent BuildPlan.

## RunPreflight

`buildPlan` is required; `onlineChecks` defaults to `false`.

Malformed BuildPlan is a contract failure (`success=false`, `INVALID_BUILD_PLAN`). A valid plan in an environment that is not ready returns `success=true`, `data.ready=false`.

Preflight data retains required `ready` and `checks`. Each check retains `id`, `status`, `severity`, `code`, `message`, and `data`. New check ids are additive.

`onlineChecks=false` performs no network request. `onlineChecks=true` only performs bounded UUP dump API reachability and does not download Windows/UUP data.

## CancelBuild

`CancelBuild` accepts `targetRequestId` and `cacheDirectory`; response data retains `requested` and `targetRequestId`.

`requested=true` only acknowledges that cancellation was requested. Actual termination is confirmed by the target operation response/event.

The control filename is derived from SHA-256 of the target request id, never from the raw id. Managed process termination targets only the owned PID tree and never kills by process name.

## Success envelope

Required fields: `schemaVersion`, `requestId`, `command`, `success`, `applicationVersion`, `data`. Additional optional fields are allowed.

## Error envelope

Required top-level fields: `schemaVersion`, `requestId`, `command`, `success`, `applicationVersion`, `error`.

Error DTO retains `code`, `message`, `stage`, `details`, and `logPath`. `details` is controlled and may be null. Exception objects, tokens, signed UUP URLs, product keys, and arbitrary internal graphs are excluded.

Existing v1 error codes remain valid, including `INVALID_REQUEST`, `UNSUPPORTED_SCHEMA`, `INVALID_COMMAND`, `INVALID_ARGUMENT`, catalog/metadata errors, `INVALID_BUILD_PLAN`, elevation/build failures, preflight errors, package/download/converter/DISM/ISO errors, `ELEVATION_CANCELLED`, and `BUILD_CANCELLED`.

Clients classify by `code`, never localized `message`, and treat unknown future v1 codes as generic failures.

## BuildResult baseline

Required semantic fields: `stage`, `isoPath`, `sha256`, `logPath`, `executionLogPath`, `workDirectory`, `metadataPath`. New optional fields are additive.

## Events

Each NDJSON event retains `schemaVersion`, `requestId`, monotonic `sequence`, UTC `timestamp`, `type`, normalized `stage`, `message`, and `progress`.

Progress retains `percent`, `detailPercent`, `speedText`, and `speedBytesPerSecond`.

Event types include `stage`, `progress`, `completed`, `failed`, `cancelled`, `warning`, and `info`. Unknown future v1 types/optional fields must be ignored safely by clients.

## GUI integration boundary

The first GUI must use only the public machine boundary:

- `Invoke-WibBackend.ps1`;
- Backend Contract Schema v1;
- BuildPlan Schema v1;
- `RunPreflight`;
- `ExecuteBuildPlan`;
- `CancelBuild`;
- `requestId`;
- NDJSON events;
- structured error codes.

The GUI must not call private PowerShell functions, parse `Write-Host`, parse aria2/converter output, classify localized error messages, or duplicate preflight/cancellation implementation.

## Contract regression policy

Tests compare the contract semantically rather than byte-for-byte JSON. They protect required baseline fields/commands while allowing additive optional evolution.

Fixtures are intentionally small: a v1 GetVersion request and a BuildPlan v1 fixture. A large brittle snapshot corpus is not required.

## Release validation is not Contract Schema

`validation-result.json` and `release-manifest.json` are developer/release tooling formats. They are not Backend Contract messages and do not change Contract SchemaVersion.

## Security

Explicit allowlist dispatch, no eval/`Invoke-Expression`, controlled normalized paths, SHA-256-derived cancellation filenames, owned-PID process-tree termination, data-only event transport, and controlled DTOs without secrets/internal object graphs.
