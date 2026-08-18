# Backend Contract v1

## Назначение

Backend Contract — stable machine-readable adapter над существующим PowerShell backend Windows ISO Builder. Он предназначен для frontend/GUI automation и не зависит от `Write-Host`, `Write-Progress`, transcript, localized exception text или raw converter output.

Transport остаётся локальным: UTF-8 JSON request/response, optional UTF-8 NDJSON events и отдельный PowerShell process. HTTP/RPC server отсутствует.

## Версии

- ApplicationVersion: `0.2.2-alpha.1`;
- ModuleVersion: `0.2.2`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

`0.2.2-alpha.1` является backward-compatible расширением Schema v1. Новые commands, error codes, optional properties и event types не требуют Schema v2. Breaking changes требуют нового schema version.

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

- `schemaVersion`: required integer, сейчас только `1`;
- `requestId`: required non-empty string; возвращается без изменения;
- `command`: required allowlisted string;
- `arguments`: required object.

Request считается недоверенным input. JSON не выбирает PowerShell function/script name и не исполняется как code.

## Commands

Schema v1 поддерживает:

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

`GetVersion` принимает `{}` и возвращает:

```json
{
  "applicationVersion": "0.2.2-alpha.1",
  "contractSchemaVersion": 1,
  "buildPlanSchemaVersion": 1
}
```

`SearchBuilds` arguments:

```json
{
  "search": "Windows 11 25H2",
  "architecture": "amd64",
  "includePreview": false,
  "forceRefresh": false,
  "cacheDirectory": "C:\\UUP-ISO-Work"
}
```

`GetRecommendedBuild`: `product`, optional `architecture`, `forceRefresh`, `cacheDirectory`.

`GetLanguages`: required `updateId`, optional `forceRefresh`, `cacheDirectory`.

`GetEditions`: required `updateId`, `language`, optional `forceRefresh`, `cacheDirectory`.

`CreateBuildPlan`: controlled build DTO + `language`, `editions`, `imageFormat`, update/cleanup/netFx3 flags, output/cache paths. It reuses `New-WibBuildPlan`.

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

`buildPlan` required. `onlineChecks` optional, default `false`.

Invalid/malformed BuildPlan is a contract failure: `success=false`, `INVALID_BUILD_PLAN`.

A valid plan in an environment that is not ready is **not** a transport failure:

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

### Preflight check vocabulary

`status`: `pass`, `warning`, `fail`, `skipped`.

`severity`: `info`, `warning`, `error`.

Current stable check ids:

- `host.windows`;
- `host.architecture`;
- `host.powershell`;
- `tool.dism`;
- `tool.expandArchive`;
- `tool.getFileHash`;
- `tool.mountDiskImage`;
- `path.cache`;
- `path.output`;
- `path.cacheWritable`;
- `path.outputWritable`;
- `disk.cache`;
- `disk.output`;
- `network.uupApi`.

Fatal `fail` + `severity=error` makes `ready=false`. Warning does not block build. `Mount-DiskImage` absence is currently a warning because ISO creation can complete with reduced deep verification.

`onlineChecks=false` does not call the network. `onlineChecks=true` performs a bounded reachability check against the official UUP dump API only; it does not download Windows/UUP data.

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

The cancel command has its **own** `requestId`. `targetRequestId` identifies the target `ExecuteBuildPlan` operation.

`requested=true` means only **cancellation request accepted**. It does not mean the target build has already stopped. Actual termination is confirmed by the target build response/event.

## Cancellation lifecycle

1. Client creates a unique `requestId` for `ExecuteBuildPlan`.
2. Backend derives `SHA-256(UTF8(requestId))`.
3. Runtime control path is `<cache>\control\<hash>.cancel.json`.
4. `CancelBuild` creates that marker using `targetRequestId`.
5. Parent/elevated worker poll a centralized cancellation context at safe points.
6. Managed UUP process runner polls during long child execution.
7. On cancellation it terminates only the process tree rooted at its own PID.
8. Target operation finishes with `success=false`, `error.code=BUILD_CANCELLED` and a `cancelled` event.
9. Parent consumes/removes the control marker; UUP cache/work data remains.

The raw request id is never used as a filename. A marker that already exists before worker initialization is intentionally preserved, so cancel-before-worker races are not lost. Therefore `ExecuteBuildPlan.requestId` must be unique for each operation.

BuildPlan does not contain `requestId`, cancellation path/hash, or event-file fields. Those are runtime ExecutionContext data.

## Success response envelope

```json
{
  "schemaVersion": 1,
  "requestId": "...",
  "command": "GetVersion",
  "success": true,
  "applicationVersion": "0.2.2-alpha.1",
  "data": {}
}
```

## Error response envelope

```json
{
  "schemaVersion": 1,
  "requestId": "build-request-456",
  "command": "ExecuteBuildPlan",
  "success": false,
  "applicationVersion": "0.2.2-alpha.1",
  "error": {
    "code": "BUILD_CANCELLED",
    "message": "Сборка отменена пользователем.",
    "stage": "convert",
    "details": {
      "targetRequestId": "build-request-456"
    },
    "logPath": null
  }
}
```

`error.details` is optional and controlled. Examples:

```json
{
  "path": "D:\\cache",
  "availableBytes": 12000000000,
  "requiredBytes": 42949672960,
  "component": "dism.exe",
  "exitCode": 1,
  "targetRequestId": "build-request-456"
}
```

Exception objects, tokens, signed UUP download URLs, product keys and arbitrary internal metadata are excluded.

## Error codes v1

Existing codes remain valid:

- `INVALID_REQUEST`;
- `UNSUPPORTED_SCHEMA`;
- `INVALID_COMMAND`;
- `INVALID_ARGUMENT`;
- `BUILD_NOT_FOUND`;
- `LANGUAGE_NOT_FOUND`;
- `EDITION_NOT_FOUND`;
- `UUP_API_ERROR`;
- `UUP_API_UNAVAILABLE`;
- `INVALID_BUILD_PLAN`;
- `ELEVATION_FAILED`;
- `BUILD_FAILED`;
- `INTERNAL_ERROR`.

Added in `0.2.2-alpha.1`:

- `UNSUPPORTED_HOST`;
- `REQUIRED_COMPONENT_MISSING`;
- `PATH_NOT_WRITABLE`;
- `DISK_SPACE_LOW`;
- `NETWORK_ERROR`;
- `UUP_PACKAGE_DOWNLOAD_FAILED`;
- `UUP_PACKAGE_INVALID`;
- `DOWNLOAD_FAILED`;
- `CONVERTER_FAILED`;
- `DISM_FAILED`;
- `ISO_NOT_FOUND`;
- `ISO_VALIDATION_FAILED`;
- `ELEVATION_CANCELLED`;
- `BUILD_CANCELLED`.

Clients must handle unknown future v1 error codes as generic failures and use `code`, not localized `message`, for classification.

## Events

Each `EventFile` line is one JSON event with:

- `schemaVersion`;
- target `requestId`;
- monotonic `sequence`;
- UTC `timestamp`;
- `type`;
- normalized `stage`;
- `message`;
- `progress` object.

Event types include:

- `stage`;
- `progress`;
- `completed`;
- `failed`;
- `cancelled`;
- `warning`;
- `info`.

`cancelled` is an additive Schema v1 event type. Schema v1 clients must ignore unknown event types and unknown optional properties while preserving their current behavior.

The cancel-command event stream, if requested, uses the cancel command `requestId`. The target build stream always retains the target build `requestId`.

Normalized stages remain: `startup`, `catalog`, `metadata`, `plan`, `preflight`, `download`, `convert`, `verify`, `completed`, `failed`.

Cancellation events carry the real stage where cancellation was observed, for example `download`, `convert`, or `verify`.

## Elevation behavior

Local preflight runs before UAC. Fatal local checks prevent UAC from opening. The elevated worker performs the authoritative preflight again.

Cancellation runtime context is forwarded separately from BuildPlan through the existing plan/result boundary. UAC refusal is classified as `ELEVATION_CANCELLED` only when numeric Win32 error information reliably indicates cancellation; message text is not parsed.

## Compatibility policy

Within Schema v1 clients must tolerate:

- new optional response/error/event properties;
- new allowlisted commands they do not call;
- new error codes;
- new event types;
- additional preflight check ids.

Clients must not assume that every event type or error code is known. Removing/renaming required fields or changing their meaning would require a new schema version.

## Security

- explicit allowlist dispatch;
- no eval/`Invoke-Expression`;
- paths normalized before use;
- cancellation filename derived only from SHA-256 target request id;
- no kill-by-process-name;
- process tree termination targets only an owned PID;
- event I/O is best-effort and cannot be used to inject executable code.
