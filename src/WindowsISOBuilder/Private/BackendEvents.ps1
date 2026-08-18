$script:WibEventSinkEnabled = $false
$script:WibEventFilePath = ''
$script:WibEventRequestId = ''
$script:WibEventSequence = 0
$script:WibEventLastProgressPercent = -1

function Get-WibEventFileLastSequence {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    try {
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -Tail 20 -ErrorAction Stop |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        for ($index = $lines.Count - 1; $index -ge 0; $index--) {
            try {
                $event = $lines[$index] | ConvertFrom-Json
                if ($null -ne $event.PSObject.Properties['sequence']) {
                    return [int]$event.sequence
                }
            }
            catch {
                # Ignore a damaged telemetry line. Event transport is best effort.
            }
        }
    }
    catch {
        # Sequence recovery must never break a build.
    }
    return 0
}

function Initialize-WibEventSink {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RequestId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$EventFile,
        [switch]$Append
    )

    $script:WibEventSinkEnabled = $false
    $script:WibEventFilePath = ''
    $script:WibEventRequestId = ''
    $script:WibEventSequence = 0
    $script:WibEventLastProgressPercent = -1

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($EventFile)
        $fullPath = [IO.Path]::GetFullPath($expanded)
        $directory = Split-Path -Parent $fullPath
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        if ($Append) {
            if (-not (Test-Path -LiteralPath $fullPath)) {
                [IO.File]::WriteAllText($fullPath, '', (New-Object Text.UTF8Encoding($false)))
            }
            $sequence = Get-WibEventFileLastSequence -Path $fullPath
        }
        else {
            [IO.File]::WriteAllText($fullPath, '', (New-Object Text.UTF8Encoding($false)))
            $sequence = 0
        }

        $script:WibEventFilePath = $fullPath
        $script:WibEventRequestId = $RequestId
        $script:WibEventSequence = $sequence
        $script:WibEventSinkEnabled = $true
        return $true
    }
    catch {
        # Structured events are telemetry and must not turn a valid build into a failure.
        return $false
    }
}

function Reset-WibEventSink {
    $script:WibEventSinkEnabled = $false
    $script:WibEventFilePath = ''
    $script:WibEventRequestId = ''
    $script:WibEventSequence = 0
    $script:WibEventLastProgressPercent = -1
}

function Get-WibEventSinkContext {
    return [pscustomobject]@{
        Enabled   = [bool]$script:WibEventSinkEnabled
        FilePath  = [string]$script:WibEventFilePath
        RequestId = [string]$script:WibEventRequestId
        Sequence  = [int]$script:WibEventSequence
    }
}

function Sync-WibEventSequenceFromFile {
    if (-not $script:WibEventSinkEnabled -or [string]::IsNullOrWhiteSpace($script:WibEventFilePath)) {
        return
    }

    $lastSequence = Get-WibEventFileLastSequence -Path $script:WibEventFilePath
    if ($lastSequence -gt $script:WibEventSequence) {
        $script:WibEventSequence = $lastSequence
    }
}

function ConvertTo-WibContractStage {
    param([AllowNull()][string]$Stage)

    switch (([string]$Stage).Trim().ToLowerInvariant()) {
        'startup' { return 'startup' }
        'catalog' { return 'catalog' }
        'metadata' { return 'metadata' }
        'plan' { return 'plan' }
        'preflight' { return 'preflight' }
        'downloading-package' { return 'metadata' }
        'download' { return 'download' }
        'downloading-uup-and-converting' { return 'download' }
        'convert' { return 'convert' }
        'validating' { return 'verify' }
        'verify' { return 'verify' }
        'completed' { return 'completed' }
        'failed' { return 'failed' }
        default { return 'preflight' }
    }
}

function Publish-WibEvent {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('stage', 'progress', 'completed', 'failed', 'warning', 'info')]
        [string]$Type,
        [string]$Stage = 'startup',
        [string]$Message = '',
        [int]$Percent = -1,
        [int]$DetailPercent = -1,
        [AllowNull()][string]$SpeedText = $null,
        [long]$SpeedBytesPerSecond = -1
    )

    if (-not $script:WibEventSinkEnabled) {
        return $false
    }

    try {
        Sync-WibEventSequenceFromFile

        $progressPercent = $null
        if ($Percent -ge 0) {
            $boundedPercent = [Math]::Max(0, [Math]::Min(100, $Percent))
            if ($script:WibEventLastProgressPercent -ge 0) {
                $boundedPercent = [Math]::Max($boundedPercent, $script:WibEventLastProgressPercent)
            }
            $script:WibEventLastProgressPercent = $boundedPercent
            $progressPercent = $boundedPercent
        }

        $detailValue = $null
        if ($DetailPercent -ge 0) {
            $detailValue = [Math]::Max(0, [Math]::Min(100, $DetailPercent))
        }

        $speedBytesValue = $null
        if ($SpeedBytesPerSecond -ge 0) {
            $speedBytesValue = [int64]$SpeedBytesPerSecond
        }

        $script:WibEventSequence++
        $event = [ordered]@{
            schemaVersion = 1
            requestId     = $script:WibEventRequestId
            sequence      = $script:WibEventSequence
            timestamp     = (Get-Date).ToUniversalTime().ToString('o')
            type          = $Type
            stage         = ConvertTo-WibContractStage -Stage $Stage
            message       = $Message
            progress      = [ordered]@{
                percent             = $progressPercent
                detailPercent       = $detailValue
                speedText           = $SpeedText
                speedBytesPerSecond = $speedBytesValue
            }
        }

        $json = ConvertTo-WibJsonText -Value $event -Depth 8 -Compress
        [IO.File]::AppendAllText(
            $script:WibEventFilePath,
            $json + [Environment]::NewLine,
            (New-Object Text.UTF8Encoding($false))
        )
        return $true
    }
    catch {
        # Event I/O and telemetry parsing are explicitly non-fatal.
        return $false
    }
}
