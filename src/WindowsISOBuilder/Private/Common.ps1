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

function Write-WibJsonFile {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 12
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporary = '{0}.{1}.tmp' -f $Path, [Guid]::NewGuid().ToString('N')
    $json = $Value | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
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
