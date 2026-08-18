# Backend Contract v1

## Purpose

Backend Contract is the stable machine-readable adapter over the Windows ISO Builder PowerShell backend. The `v0.3.0-alpha.1` GUI and automation clients use this boundary only, never private PowerShell implementation details.

Transport is local UTF-8 JSON request/response files, an optional UTF-8 NDJSON event file, and a separate `powershell.exe` process. There is no HTTP/RPC server.

## Versions

- ApplicationVersion: `0.3.0-alpha.1`;
- ModuleVersion: `0.3.0`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`.

ApplicationVersion is not a compatibility gate. Breaking changes to required names/semantics require SchemaVersion 2; additive optional fields, error codes, and event types are allowed in v1.

## Entry point and request

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile <request.json> `
  -ResponseFile <response.json> `
  -EventFile <events.ndjson>
```

Request envelope:

```json
{"schemaVersion":1,"requestId":"client-id","command":"GetVersion","arguments":{}}
```

Requests are untrusted data. Commands are selected from an explicit allowlist; JSON never names an executable PowerShell function/script.

## Schema v1 command baseline

`GetVersion`, `SearchBuilds`, `GetRecommendedBuild`, `GetLanguages`, `GetEditions`, `CreateBuildPlan`, `ValidateBuildPlan`, `RunPreflight`, `ExecuteBuildPlan`, `CancelBuild`.

`GetVersion` returns applicationVersion, contractSchemaVersion, and buildPlanSchemaVersion.

`SearchBuilds` requires `search`; architecture/includePreview/forceRefresh/cacheDirectory are optional.

`GetRecommendedBuild` requires `product`; recommendation logic remains backend-owned.

`GetLanguages(updateId)` returns dynamic `{code,name}` DTOs. `GetEditions(updateId,language)` returns dynamic `{code,name}` DTOs.

Build DTO semantics retain uuid/title/product/versionLabel/build/architecture/entryType/createdAt/isPreview.

`CreateBuildPlan` accepts the selected build/language/editions/imageFormat/options/output/cache and returns `{plan}`. BuildPlan v1 retains schemaVersion/applicationVersion/createdAt/build/language/editions/sourceEdition/virtualEditions/imageFormat/options/output/cache/removeWorkAfterSuccess.

`ValidateBuildPlan` uses `{plan}`.

`RunPreflight` uses the exact argument property `{buildPlan, onlineChecks}`. A valid-but-unready environment is `success=true`, `data.ready=false`. Data retains `ready` plus checks with `id/status/severity/code/message/data`.

`ExecuteBuildPlan` uses `{plan}` and reuses the existing preflight/elevation/build pipeline. Its requestId is the public build operation id.

`CancelBuild` accepts `targetRequestId` and `cacheDirectory`; acknowledgment is not terminal cancellation. The target build confirms `BUILD_CANCELLED`/cancelled semantics.

## Response envelopes

Success retains `schemaVersion`, `requestId`, `command`, `success=true`, `applicationVersion`, and `data`. Error responses retain the same envelope with `success=false` and `error` containing controlled `code/message/stage/details/logPath`.

Clients classify by error `code`, not localized message text, and must tolerate unknown future v1 codes as generic failures.

## Build result

Semantic fields: `stage`, `isoPath`, `sha256`, `logPath`, `executionLogPath`, `workDirectory`, `metadataPath`.

## Events

Each NDJSON event retains schemaVersion/requestId/monotonic sequence/UTC timestamp/type/normalized stage/message/progress. Progress retains percent/detailPercent/speedText/speedBytesPerSecond.

Types include stage/progress/completed/failed/cancelled/warning/info. Unknown additive v1 event types/properties must be ignored safely. The final Backend response, not 100% telemetry, is authoritative completion state.

## GUI boundary

The GUI does not import the module directly, call private functions, read internal state as an API, parse human console/transcript/aria2/converter output, duplicate UUP/DISM/preflight/cancellation workflow, classify localized text, or kill backend-owned process trees.

## Security

Explicit command allowlist, no eval/Invoke-Expression, normalized paths, SHA-256-derived cancellation control filenames, PID-rooted owned process termination, and controlled DTOs that exclude signed URLs, tokens, product keys, secrets, and arbitrary exception graphs.
