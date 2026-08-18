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

`schemaVersion` is required and currently `1`; `requestId` is a required non-empty string returned unchanged; `command` is allowlisted; `arguments` is a required object. Requests are untrusted input and JSON is never executed as code.

## Commands

Schema v1 supports `GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `ExecuteBuildPlan`, `RunPreflight`, and `CancelBuild`.

Existing catalog/plan commands retain their v1 arguments and controlled DTOs. `ValidateBuildPlan` returns `INVALID_BUILD_PLAN` for invalid plan data. `ExecuteBuildPlan` reuses `Invoke-WibBuildPlan` and the existing elevation/build pipeline.

## RunPreflight

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

`buildPlan` is required. `onlineChecks` defaults to `false`.

A malformed BuildPlan is a contract failure (`success=false`, `INVALID_BUILD_PLAN`). A valid plan in an environment that is not ready returns `success=true`, `data.ready=false` plus all independent checks.

Check `status` values: `pass`, `warning`, `fail`, `skipped`. Severity values: `info`, `warning`, `error`.

Current stable check ids:

`host.windows`, `host.architecture`, `host.powershell`, `tool.cmd`, `tool.dism`, `tool.expandArchive`, `tool.getFileHash`, `tool.mountDiskImage`, `path.cache`, `path.output`, `path.cacheWritable`, `path.outputWritable`, `disk.cache`, `disk.output`, `network.uupApi`.

Fatal `fail` + `severity=error` makes `ready=false`. Warnings do not block the build. Missing `Mount-DiskImage` is a warning because ISO creation can still complete with reduced deep verification.

Disk checks return numeric `availableBytes` and `requiredBytes`. `onlineChecks=false` performs no network request. `onlineChecks=true` performs a bounded reachability check against the official UUP dump API only and does not download Windows/UUP data.

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

Response data:

```json
{
  "requested": true,
  "targetRequestId": "build-request-456"
}
```

The cancel command has its own request id. `requested=true` means only that the cancellation request was accepted; it does not mean the target build has already stopped. Actual termination is confirmed by the target operation's final response/event.

## Cancellation lifecycle

1. Client creates a unique `requestId` for `ExecuteBuildPlan`.
2. Backend derives `SHA-256(UTF8(requestId))`.
3. Control path is `<cache>\control\<hash>.cancel.json`.
4. `CancelBuild` creates a validated Windows ISO Builder marker with `CreateNew` semantics.
5. Existing valid markers are preserved during worker initialization, so early cancellation is not lost.
6. Parent/elevated worker poll centralized cancellation helpers.
7. Managed UUP runner polls during long execution and terminates only the process tree rooted at its own PID.
8. Target operation finishes with `success=false`, `BUILD_CANCELLED`, and a `cancelled` event.
9. Parent removes only a validated owned marker; cache/work data remains.

The raw request id is never used as a filename. A colliding unrelated user file is neither overwritten nor deleted. `ExecuteBuildPlan.requestId` must be unique per operation.

BuildPlan does not contain request/event/cancellation fields; those belong to runtime ExecutionContext.

## Error envelope

A failed response contains `code`, human-readable `message`, normalized `stage`, optional controlled `details`, and optional `logPath`.

Controlled details may include path, available/required bytes, component, exit code, target request id, or failed check ids. Exception objects, tokens, signed UUP URLs, product keys, and arbitrary internal metadata are excluded.

Existing error codes remain valid:

`INVALID_REQUEST`, `UNSUPPORTED_SCHEMA`, `INVALID_COMMAND`, `INVALID_ARGUMENT`, `BUILD_NOT_FOUND`, `LANGUAGE_NOT_FOUND`, `EDITION_NOT_FOUND`, `UUP_API_ERROR`, `UUP_API_UNAVAILABLE`, `INVALID_BUILD_PLAN`, `ELEVATION_FAILED`, `BUILD_FAILED`, `INTERNAL_ERROR`.

Added in `0.2.2-alpha.1`:

`UNSUPPORTED_HOST`, `REQUIRED_COMPONENT_MISSING`, `PATH_NOT_WRITABLE`, `DISK_SPACE_LOW`, `NETWORK_ERROR`, `UUP_PACKAGE_DOWNLOAD_FAILED`, `UUP_PACKAGE_INVALID`, `DOWNLOAD_FAILED`, `CONVERTER_FAILED`, `DISM_FAILED`, `ISO_NOT_FOUND`, `ISO_VALIDATION_FAILED`, `ELEVATION_CANCELLED`, `BUILD_CANCELLED`.

Clients classify by `code`, not localized message text, and treat unknown future v1 codes as generic failures.

## Events

Each NDJSON event contains schema version, target request id, monotonic sequence, UTC timestamp, type, normalized stage, message, and progress object.

Event types are `stage`, `progress`, `completed`, `failed`, `cancelled`, `warning`, `info`. `cancelled` is an additive Schema v1 event type; v1 clients must ignore unknown event types and unknown optional properties.

Cancel-command events use the cancel-command request id. Target build events retain the target build request id. A cancellation event carries the real stage where cancellation was observed.

## Elevation behavior

Local preflight runs before UAC. Fatal local checks prevent UAC from opening. The elevated worker repeats authoritative preflight.

Cancellation runtime context is forwarded separately from BuildPlan through the existing plan/result boundary. UAC refusal is mapped to `ELEVATION_CANCELLED` only from reliable numeric Win32 information, never message parsing.

## Compatibility policy

Schema v1 clients must tolerate new optional fields, commands they do not call, error codes, event types, and preflight check ids. Removing/renaming required fields or changing their semantics requires a new schema version.

## Security

Explicit allowlist dispatch, no eval/`Invoke-Expression`, normalized paths, SHA-256-derived cancellation filenames, validated marker ownership, no process-name kill, owned-PID process tree termination, and data-only best-effort event transport.
