function Write-WibStage {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ''
    Write-Host ('=== {0} ===' -f $Message) -ForegroundColor Cyan
}

function Write-WibInfo {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ('[INFO] {0}' -f $Message)
}

function Write-WibWarning {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Warning $Message
}

function New-WibErrorException {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Code,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message,
        [string]$Stage = '',
        [string]$PublicMessage = '',
        [string]$LogPath = '',
        [string]$WorkDirectory = '',
        [AllowNull()]$Details = $null
    )

    $exception = New-Object System.Exception($Message)
    $exception.Data['WibErrorCode'] = $Code
    if (-not [string]::IsNullOrWhiteSpace($Stage)) {
        $exception.Data['WibStage'] = $Stage
    }
    if (-not [string]::IsNullOrWhiteSpace($PublicMessage)) {
        $exception.Data['WibPublicMessage'] = $PublicMessage
    }
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $exception.Data['WibLogPath'] = $LogPath
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkDirectory)) {
        $exception.Data['WibWorkDirectory'] = $WorkDirectory
    }
    if ($null -ne $Details) {
        $exception.Data['WibErrorDetails'] = $Details
    }
    return $exception
}

function Set-WibExceptionMetadata {
    param(
        [Parameter(Mandatory = $true)][System.Exception]$Exception,
        [string]$Code = '',
        [string]$Stage = '',
        [string]$PublicMessage = '',
        [string]$LogPath = '',
        [string]$WorkDirectory = '',
        [AllowNull()]$Details = $null
    )

    if (-not [string]::IsNullOrWhiteSpace($Code)) {
        $Exception.Data['WibErrorCode'] = $Code
    }
    if (-not [string]::IsNullOrWhiteSpace($Stage)) {
        $Exception.Data['WibStage'] = $Stage
    }
    if (-not [string]::IsNullOrWhiteSpace($PublicMessage)) {
        $Exception.Data['WibPublicMessage'] = $PublicMessage
    }
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $Exception.Data['WibLogPath'] = $LogPath
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkDirectory)) {
        $Exception.Data['WibWorkDirectory'] = $WorkDirectory
    }
    if ($null -ne $Details) {
        $Exception.Data['WibErrorDetails'] = $Details
    }
    return $Exception
}

function Get-WibDefaultOutputDirectory {
    if ($script:ProjectRoot) {
        return (Join-Path $script:ProjectRoot 'output')
    }
    return (Join-Path (Get-Location).Path 'output')
}

function Get-WibDefaultCacheDirectory {
    $systemDrive = $env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($systemDrive)) {
        $systemDrive = 'C:'
    }
    return (Join-Path $systemDrive 'UUP-ISO-Work')
}

function Resolve-WibFullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Create
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $full = [IO.Path]::GetFullPath($expanded)
    if ($Create -and -not (Test-Path -LiteralPath $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
    }
    return $full
}

function ConvertTo-WibSafeFilePart {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = $Value.Trim()
    foreach ($character in [IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$character, '_')
    }
    $safe = $safe -replace '\s+', '_'
    $safe = $safe -replace '[^\p{L}\p{Nd}._-]', '_'
    $safe = $safe.Trim([char[]]' ._')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'item'
    }
    if ($safe.Length -gt 80) {
        return $safe.Substring(0, 80)
    }
    return $safe
}

function Get-WibSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertTo-WibJsonText {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 20,
        [switch]$Compress
    )

    return ($Value | ConvertTo-Json -Depth $Depth -Compress:$Compress)
}

function Resolve-WibFileSystemPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    try {
        $providerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($expanded)
        return [IO.Path]::GetFullPath($providerPath)
    }
    catch {
        return [IO.Path]::GetFullPath($expanded)
    }
}

function Write-WibJsonFile {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 20
    )

    # System.IO APIs do not understand PowerShell provider paths such as
    # TestDrive:\. Resolve them first while keeping normal/8.3 filesystem paths
    # out of the PowerShell provider move implementation that previously failed
    # for a Cyrillic user profile represented through its short DOS alias.
    $targetPath = Resolve-WibFileSystemPath -Path $Path
    $directory = Split-Path -Parent $targetPath
    if ($directory -and -not [IO.Directory]::Exists($directory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $operationId = [Guid]::NewGuid().ToString('N')
    $temporary = '{0}.{1}.tmp' -f $targetPath, $operationId
    $backup = '{0}.{1}.bak' -f $targetPath, $operationId
    $json = ConvertTo-WibJsonText -Value $Value -Depth $Depth
    try {
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($targetPath)) {
            # Windows PowerShell 5.1 / .NET Framework does not reliably accept
            # a null backup path for File.Replace. A same-directory backup keeps
            # the replacement atomic and is deleted immediately afterwards.
            [IO.File]::Replace($temporary, $targetPath, $backup)
        }
        else {
            [IO.File]::Move($temporary, $targetPath)
        }
    }
    finally {
        if ([IO.File]::Exists($temporary)) {
            [IO.File]::Delete($temporary)
        }
        if ([IO.File]::Exists($backup)) {
            [IO.File]::Delete($backup)
        }
    }
}

function Read-WibJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Test-WibAdministrator {
    if ($env:OS -ne 'Windows_NT') {
        return $false
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WibPowerShellExecutable {
    $windowsPowerShell = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
    if ($windowsPowerShell) {
        return $windowsPowerShell.Source
    }
    $current = (Get-Process -Id $PID).Path
    if ($current) {
        return $current
    }
    throw 'Не удалось найти исполняемый файл PowerShell.'
}

function Quote-WibCommandArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ('"{0}"' -f $Value.Replace('"', '""'))
}

function Set-WibIniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = '(?im)^\s*' + [regex]::Escape($Name) + '\s*=.*$'
    $replacement = '{0}={1}' -f $Name, $Value

    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, $replacement)
    }
    else {
        $content = $content.TrimEnd() + "`r`n$replacement`r`n"
    }

    [IO.File]::WriteAllText($Path, $content, [Text.Encoding]::ASCII)
}

function Get-WibDriveFreeBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Не удалось определить диск для пути: $Path"
    }
    $drive = New-Object IO.DriveInfo($root)
    return $drive.AvailableFreeSpace
}

function Assert-WibFreeSpace {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int64]$MinimumBytes,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    $free = Get-WibDriveFreeBytes -Path $Path
    if ($free -lt $MinimumBytes) {
        throw ('Недостаточно места для {0}: свободно {1:N1} ГБ, требуется не менее {2:N1} ГБ.' -f $Purpose, ($free / 1GB), ($MinimumBytes / 1GB))
    }
    Write-WibInfo ('Свободное место для {0}: {1:N1} ГБ' -f $Purpose, ($free / 1GB))
}

function Get-WibDirectorySizeBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int64]0
    }
    $measure = Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
    if ($null -eq $measure.Sum) {
        return [int64]0
    }
    return [int64]$measure.Sum
}

function Get-WibUnixDate {
    param([Parameter(Mandatory = $true)][long]$Seconds)
    $epoch = [DateTime]::SpecifyKind([DateTime]'1970-01-01T00:00:00', [DateTimeKind]::Utc)
    return $epoch.AddSeconds($Seconds).ToLocalTime()
}

function ConvertTo-WibVersion {
    param([Parameter(Mandatory = $true)][string]$Build)
    try {
        return [version]$Build
    }
    catch {
        return [version]'0.0'
    }
}

function Get-WibBuildEntryType {
    param([AllowNull()][string]$Title)

    $text = ([string]$Title).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return 'Other' }

    # Servicing packages can appear in listid next to complete OS UUP sets. They
    # are useful catalog records but must not be presented as normal Windows ISO
    # sources by default.
    if ($text -match '(?i)^(?:Cumulative Update|Security Update|Critical Update|OOBE Update|Update for|Preview of Cumulative Update|\.NET Framework)' -or
        $text -match '(?i)\b(?:Cumulative|Security|Critical|OOBE|Dynamic|Compatibility|Servicing Stack) Update\b' -or
        $text -match '(?i)\b\.NET Framework\b') {
        return 'Servicing'
    }

    if ($text -match '(?i)^Feature update to Windows (?:10|11)(?:,|\s+version\b|\s*\()' -or
        $text -match '(?i)^Windows (?:10|11)(?:\s+Insider Preview\b|,\s*version\b|\s+build\b|\s*\(|$)' -or
        $text -match '(?i)^Windows Server(?:\s+Insider Preview\b|,\s*version\b|\s+build\b|\s+\d{4}\b|\s*\(|$)') {
        return 'Windows'
    }

    return 'Other'
}

function Get-WibBuildEntryTypeRank {
    param([AllowNull()][string]$EntryType)

    switch ([string]$EntryType) {
        'Windows' { return 0 }
        'Other' { return 1 }
        'Servicing' { return 2 }
        default { return 3 }
    }
}

function Get-WibBuildEntryTypeLabel {
    param([AllowNull()][string]$EntryType)

    switch ([string]$EntryType) {
        'Windows' { return 'Сборка' }
        'Servicing' { return 'Обновл.' }
        default { return 'Другое' }
    }
}
