# Backend Contract v1

## Назначение

Backend Contract — стабильный машиночитаемый слой над существующим PowerShell backend Windows ISO Builder. Он предназначен для будущих GUI/frontend-клиентов и автоматизации, которым нельзя зависеть от `Write-Host`, локализованных сообщений, `Write-Progress`, transcript или raw output `aria2`/конвертера.

Contract **не** заменяет `Start-Builder.ps1`, не реализует второй UUP workflow и не является HTTP API. Текущий transport — локальные JSON/NDJSON файлы и отдельный процесс PowerShell.

## Версии

- ApplicationVersion: `0.2.1-alpha.1`;
- Backend Contract SchemaVersion: `1`;
- BuildPlan SchemaVersion: `1`;
- PowerShell module manifest: `0.2.1`.

Эти версии независимы. Изменение ApplicationVersion само по себе не меняет Backend Contract schema.

## Entry point

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-WibBackend.ps1 `
  -RequestFile <request.json> `
  -ResponseFile <response.json> `
  -EventFile <events.ndjson>
```

`-EventFile` необязателен. `Invoke-WibBackend.ps1` ASCII-only и совместим с Windows PowerShell 5.1.

## Transport

### RequestFile

- UTF-8 JSON;
- один request object;
- backend рассматривает содержимое как недоверенный ввод.

### ResponseFile

- UTF-8 JSON;
- один final response object;
- записывается атомарно через temporary file рядом с destination и replacement/move;
- частично сериализованный response не является допустимым результатом.

### EventFile

- UTF-8 NDJSON / JSON Lines;
- один JSON event на строку;
- optional best-effort telemetry;
- сбой записи event не должен превращать успешную build operation в failure.

Human console output не является частью protocol.

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

Обязательный integer. В текущей реализации поддерживается только `1`.

### `requestId`

Обязательная непустая string. Backend возвращает значение без изменения в response и во всех events данного request.

### `command`

Обязательная string из allowlist:

- `GetVersion`;
- `SearchBuilds`;
- `GetRecommendedBuild`;
- `GetLanguages`;
- `GetEditions`;
- `CreateBuildPlan`;
- `ValidateBuildPlan`;
- `ExecuteBuildPlan`.

Произвольные PowerShell function names, script paths и code execution не поддерживаются.

### `arguments`

Обязательный object. Для команд без параметров используется `{}`.

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

`success` всегда boolean. При `success=true` присутствует `data`.

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

При `success=false` присутствует `error`.

- `error.code` — стабильный machine-oriented identifier;
- `error.message` — human-readable текст; в текущем TUI/backend он может быть русским;
- `error.stage` — нормализованная contract stage;
- `error.details` — optional structured details;
- `error.logPath` — optional build log path.

Frontend не должен определять тип ошибки по `message`.

## Error codes v1

Минимальный набор:

- `INVALID_REQUEST` — envelope отсутствует/некорректен;
- `UNSUPPORTED_SCHEMA` — неизвестный Backend Contract schemaVersion;
- `INVALID_COMMAND` — command не входит в allowlist;
- `INVALID_ARGUMENT` — command argument имеет неверный тип/значение;
- `BUILD_NOT_FOUND` — рекомендуемая/запрошенная build selection недоступна там, где отсутствие результата является ошибкой;
- `LANGUAGE_NOT_FOUND` — metadata не содержит доступных languages;
- `EDITION_NOT_FOUND` — metadata не содержит доступных editions;
- `UUP_API_ERROR` — UUP API вернул non-retryable/application error;
- `UUP_API_UNAVAILABLE` — UUP API временно недоступен после retry/cache fallback;
- `INVALID_BUILD_PLAN` — BuildPlan не проходит validation;
- `ELEVATION_FAILED` — не удалось запустить/получить корректный результат elevated worker;
- `BUILD_FAILED` — build/conversion workflow завершился ошибкой;
- `INTERNAL_ERROR` — непредвиденная backend error вне более точной категории.

Внутри schema v1 могут добавляться новые `error.code`; клиент должен корректно обрабатывать неизвестный code как generic failure.

## DTO: build

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

DTO намеренно не включает internal sorting/version helpers и PowerShell metadata.

## DTO: language

```json
{
  "code": "ru-ru",
  "name": "Russian"
}
```

## DTO: edition

```json
{
  "code": "Professional",
  "name": "Windows Pro"
}
```

## Команды

### GetVersion

Request arguments:

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

`search` обязателен. `architecture`: `amd64`, `arm64`, `x86` или `all`. Остальные поля optional.

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

Отсутствие search matches — успешный результат `builds: []`.

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

`product`: `Windows 11` или `Windows 10`. Команда использует ту же dynamic quick-mode recommendation logic, что и TUI; build/release number не hardcode-ится.

Response:

```json
{
  "build": { "uuid": "..." }
}
```

Полный object соответствует build DTO.

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

`language` должен соответствовать pattern `xx-xx`.

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

Команда вызывает существующий `New-WibBuildPlan`. Параллельного plan format нет.

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

Полный plan соответствует DTO выше.

Success:

```json
{
  "valid": true
}
```

Invalid plan возвращает `success=false`, `error.code=INVALID_BUILD_PLAN`.

### ExecuteBuildPlan

Arguments:

```json
{
  "plan": { "schemaVersion": 1 }
}
```

Команда использует существующий `Invoke-WibBuildPlan`, включая current UAC/elevation/conversion workflow.

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

Некоторые path/hash поля могут быть пустыми, если underlying workflow не успел их создать до failure/specific execution mode.

## Events

Одна строка `EventFile`:

```json
{
  "schemaVersion": 1,
  "requestId": "request-1",
  "sequence": 1,
  "timestamp": "2026-08-18T05:30:00.0000000Z",
  "type": "progress",
  "stage": "download",
  "message": "Загрузка файлов Windows: 15%",
  "progress": {
    "percent": 24,
    "detailPercent": 15,
    "speedText": "31MiB",
    "speedBytesPerSecond": 32505856
  }
}
```

### Event types

Обязательные:

- `stage`;
- `progress`;
- `completed`;
- `failed`.

Дополнительно v1 допускает `warning`, `info`.

### Sequence

- начинается с `1` для нового EventFile/request;
- монотонно увеличивается;
- elevated child продолжает sequence в том же file;
- `requestId` одинаков для всех events request.

### Timestamp

UTC ISO-8601 string.

### Contract stages

Ограниченный словарь:

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

Internal stages явно отображаются в этот словарь. Например `downloading-package` → `metadata`, `downloading-uup-and-converting` → `download`, `validating` → `verify`.

### Progress object

- `percent`: overall progress `0..100` или `null`;
- `detailPercent`: download/detail progress `0..100` или `null`;
- `speedText`: parser-friendly human speed string или `null`;
- `speedBytesPerSecond`: parsed integer bytes/s или `null`.

Overall progress не уменьшается. Speed parsing и event I/O — best effort; они не могут быть причиной build failure.

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

Ожидаемая структура `response.json`:

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

JSON formatting/whitespace не являются частью contract.

## Security model

- request — untrusted input;
- command dispatch — explicit allowlist;
- нет `Invoke-Expression`/eval;
- JSON никогда не интерпретируется как PowerShell code;
- enum/language/path values валидируются до вызова core;
- frontend не получает raw Exception object graph;
- Backend Contract не должен возвращать signed UUP download URLs, product keys, tokens или secrets;
- существующая UAC/security policy не меняется.

## Compatibility policy

Backend Contract Schema v1 гарантирует:

- существующие properties не меняют смысл;
- обязательные свойства не исчезают;
- новые optional properties могут добавляться;
- новые commands могут добавляться;
- новые `error.code` могут добавляться;
- клиент должен игнорировать неизвестные optional fields.

Несовместимое изменение требует `schemaVersion = 2`.

ApplicationVersion не влияет на contract schema автоматически.
