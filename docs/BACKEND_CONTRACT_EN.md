# Backend Contract v1

## Purpose

Backend Contract is a stable machine-readable adapter over the existing Windows ISO Builder PowerShell backend. It is intended for future frontend/GUI automation and does not depend on `Write-Host`, `Write-Progress`, transcripts, localized exception text, or raw converter output.

Transport remains local: UTF-8 JSON request/response files, optional UTF-8 NDJSON events, and a separate PowerShell process. There is no HTTP/RPC server.

## Versions

- ApplicationVersion: `0.2.2-alpha.1`;
- ModuleVersion: `0.2.2`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`0.2.2-alpha.1` is a backward-compatible Schema v1 extension. New commands, error codes, optional properties, and event types do not require Schema v2. Breaking changes do.

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

- `schemaVersion`: required integer, currently only `1`;
- `requestId`: required non-empty string, returned unchanged;
- `command`: required allowlisted string;
- `arguments`: required object.

Requests are untrusted input. JSON cannot select arbitrary PowerShell functions/scripts and is never executed as code.

## Commands

Schema v1 supports:

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

### Existing catalog/plan commands

`GetVersion` accepts `{}` and returns:

```json
{
  "applicationVersion": "0.2.2-alpha.1",
  "contractSchemaVersion": 1,
  "buildPlanSchemaVersion": 1
}
```

`SearchBuilds`: required `search`; optional `architecture`, `includePreview`, `forceRefresh`, `cacheDirectory`.

`GetRecommendedBuild`: required `product`; optional `architecture`, `forceRefresh`, `cacheDirectory`.

`GetLanguages`: required `updateId`; optional `forceRefresh`, `cacheDirectory`.

`GetEditions`: required `updateId` and `language`; optional `forceRefresh`, `cacheDirectory`.

`CreateBuildPlan`: controlled build DTO plus language, editions, image format, update/cleanup/netFx3 flags, and output/cache paths. It reuses `New-WibBuildPlan`.

`ValidateBuildPlan`: `{ "plan": { ... } }`; invalid data returns `INVALID_BUILD_PLAN`.

`ExecuteBuildPlan`: `{ "plan": { ... } }`; it reuses `Invoke-WibBuildPlan` and the existing elevation/build pipeline.

## RunPreflight

Request:

```json
{
  "schemaVersion": 1,
  "requestId": "preflight-123",
  "command": "RunPreflight",
  "arguments": {
    "buildPlan": {
      "schemaVersion": 1
    },
    "onlineChecks": false
  }
}
```

`buildPlan` is required. `onlineChecks` is optional and defaults to `false`.

A malformed BuildPlan is a contract failure: `success=false`, `INVALID_BUILD_PLAN`.

A valid plan in an environment that is not ready is not a transport failure:

```json
{
  "schemaVersion": 1,
  "requestId": "preflight-123",
  "command": "RunPreflight",
  "success": true,
  "applicationVersion": "0.2.2-alpha.1",
  "data": {
    "ready": false,
    "checks": [
      {
        "id": "disk.cache",
        "status": "fail",
        "severity": "error",
        "code": "DISK_SPACE_LOW",
        "message": "Insufficient free space for cache.",
        "data": {
          "path": "C:\\UUP-ISO-Work",
          "availableBytes": 12000000000,
          "requiredBytes": 42949672960
        }
      }
    ]
  }
}
```

`status`: `pass`, `warning`, `fail`, `skipped`.

`severity`: `info`, `warning`, `error`.

Current stable check ids:

`host.windows`, `host.architecture`, `host.powershell`, `tool.dism`, `tool.expandArchive`, `tool.getFileHash`, `tool.mountDiskImage`, `path.cache`, `path.output`, `path.cacheWritable`, `path.outputWritable`, `disk.cache`, `disk.output`, `network.uupApi`.

A fatal `fail` with `severity=error` makes `ready=false`. Warnings do not block the build. Missing `Mount-DiskImage` is a warning because ISO creation can still complete with reduced deep verification.

`onlineChecks=false` performs no network request. `onlineChecks=true` performs a bounded reachability check against the official UUP dump API only and does not download Windows/UUP data.

## CancelBuild

Request:

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

Response data:

```json
{
  "requested": true,
  "targetRequestId": "build-request-456"
}
```

The cancel command has its own `requestId`; `targetRequestId` identifies the target `ExecuteBuildPlan` operation.

`requested=true` means only **the cancellation request was accepted**. It does not mean the target build is already stopped. Final termination is confirmed by the target operation's response/event.

## Cancellation lifecycle

1. Client generates a unique `requestId` for `ExecuteBuildPlan`.
2. Backend derives `SHA-256(UTF8(requestId))`.
3. Runtime control path is `<cache>\control\<hash>.cancel.json`.
4. `CancelBuild` creates that marker from `targetRequestId`.
5. Parent/elevated worker poll centralized cancellation helpers at safe points.
6. Managed UUP runner polls during long process execution.
7. On cancellation it terminates only the process tree rooted at its own PID.
8. Target operation ends with `success=false`, `BUILD_CANCELLED`, and a `cancelled` event.
9. Parent consumes/removes the control marker; UUP cache/work data remains.

The raw request id is never used as a filename. Existing markers are not deleted during initialization, so cancellation arriving before worker initialization is not lost. `ExecuteBuildPlan.requestId` must therefore be unique per operation.

BuildPlan does not contain request/event/cancellation fields. Those are runtime ExecutionContext data.

## Error envelope

```json
{
  "schemaVersion": 1,
  "requestId": "build-request-456",
  "command": "ExecuteBuildPlan",
  "success": false,
  "applicationVersion": "0.2.2-alpha.1",
  "error": {
    "code": "BUILD_CANCELLED",
    "message": "Build was cancelled.",
    "stage": "convert",
    "details": {
      "targetRequestId": "build-request-456"
    },
    "logPath": null
  }
}
```

Controlled optional details may include path, available/required bytes, component, exit code, target request id, or failed check ids. Exception objects, tokens, signed UUP URLs, product keys, and arbitrary internal metadata are excluded.

## Error codes v1

Existing codes:

`INVALID_REQUEST`, `UNSUPPORTED_SCHEMA`, `INVALID_COMMAND`, `INVALID_ARGUMENT`, `BUILD_NOT_FOUND`, `LANGUAGE_NOT_FOUND`, `EDITION_NOT_FOUND`, `UUP_API_ERROR`, `UUP_API_UNAVAILABLE`, `INVALID_BUILD_PLAN`, `ELEVATION_FAILED`, `BUILD_FAILED`, `INTERNAL_ERROR`.

Added in `0.2.2-alpha.1`:

`UNSUPPORTED_HOST`, `REQUIRED_COMPONENT_MISSING`, `PATH_NOT_WRITABLE`, `DISK_SPACE_LOW`, `NETWORK_ERROR`, `UUP_PACKAGE_DOWNLOAD_FAILED`, `UUP_PACKAGE_INVALID`, `DOWNLOAD_FAILED`, `CONVERTER_FAILED`, `DISM_FAILED`, `ISO_NOT_FOUND`, `ISO_VALIDATION_FAILED`, `ELEVATION_CANCELLED`, `BUILD_CANCELLED`.

Clients must classify by `code`, not localized `message`, and treat unknown future v1 codes as generic failures.

## Events

Each NDJSON event contains schema version, target request id, monotonic sequence, UTC timestamp, type, normalized stage, message, and progress object.

Event types:

- `stage`;
- `progress`;
- `completed`;
- `failed`;
- `cancelled`;
- `warning`;
- `info`.

`cancelled` is an additive Schema v1 event type. v1 clients must ignore unknown event types and unknown optional properties.

A cancel command event stream, if requested, uses the cancel-command request id. Target build events retain the target build request id.

Normalized stages remain `startup`, `catalog`, `metadata`, `plan`, `preflight`, `download`, `convert`, `verify`, `completed`, `failed`. A cancellation event uses the real stage where cancellation was observed.

## Elevation behavior

Local preflight runs before UAC. Fatal local checks prevent UAC from opening. The elevated worker performs authoritative preflight again.

Cancellation runtime context is forwarded separately from BuildPlan through the existing plan/result boundary. UAC refusal is mapped to `ELEVATION_CANCELLED` only when numeric Win32 information reliably identifies cancellation; message text is never parsed for this classification.

## Compatibility policy

Within Schema v1 clients must tolerate new optional properties, new commands they do not call, new error codes, new event types, and additional preflight check ids. Removing/renaming required fields or changing their semantics would require a new schema version.

## Security

- explicit allowlist dispatch;
- no eval/`Invoke-Expression`;
- normalized paths;
- cancellation filename derived only from SHA-256 target request id;
- no process-name kill;
- process tree termination targets only an owned PID;
- event transport is data only and best-effort.
