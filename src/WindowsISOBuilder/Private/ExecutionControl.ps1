$script:WibCancellationContext = [pscustomobject]@{
    Enabled        = $false
    RequestId      = ''
    RequestHash    = ''
    CacheDirectory = ''
    ControlPath    = ''
}

function Get-WibCancellationRequestHash {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RequestId)

    if ($RequestId.Length -gt 2048) {
        throw (New-WibErrorException -Code 'INVALID_ARGUMENT' -Message 'requestId is too long.' -Stage 'startup')
    }
    return (Get-WibSha256Text -Text $RequestId)
}

function Get-WibCancellationControlPathFromHash {
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RequestHash,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CacheDirectory
    )

    $cache = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CacheDirectory))
    $controlDirectory = Join-Path $cache 'control'
    return (Join-Path $controlDirectory (($RequestHash.ToLowerInvariant()) + '.cancel.json'))
}

function Get-WibCancellationControlPath {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RequestId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CacheDirectory
    )

    $hash = Get-WibCancellationRequestHash -RequestId $RequestId
    return (Get-WibCancellationControlPathFromHash -RequestHash $hash -CacheDirectory $CacheDirectory)
}

function Test-WibCancellationControlFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RequestHash
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $marker = Read-WibJsonFile -Path $Path
        if ($null -eq $marker) { return $false }
        if ($null -eq $marker.PSObject.Properties['kind'] -or [string]$marker.kind -ne 'windows-iso-builder-cancel') { return $false }
        if ($null -eq $marker.PSObject.Properties['schemaVersion'] -or [int]$marker.schemaVersion -ne 1) { return $false }
        if ($null -eq $marker.PSObject.Properties['requestHash']) { return $false }
        return ([string]::Equals([string]$marker.requestHash, $RequestHash, [StringComparison]::OrdinalIgnoreCase))
    }
    catch { return $false }
}

function Initialize-WibCancellationContext {
    [CmdletBinding(DefaultParameterSetName = 'RequestId')]
    param(
        [Parameter(ParameterSetName = 'RequestId', Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RequestId,
        [Parameter(ParameterSetName = 'Hash', Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RequestHash,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CacheDirectory
    )

    $cache = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CacheDirectory))
    $hash = if ($PSCmdlet.ParameterSetName -eq 'RequestId') { Get-WibCancellationRequestHash -RequestId $RequestId } else { $RequestHash.ToLowerInvariant() }
    $controlPath = Get-WibCancellationControlPathFromHash -RequestHash $hash -CacheDirectory $cache

    # Never delete an existing valid marker here. CancelBuild may win the race
    # and create it before ExecuteBuildPlan finishes initializing its worker.
    $script:WibCancellationContext = [pscustomobject]@{
        Enabled        = $true
        RequestId      = if ($PSCmdlet.ParameterSetName -eq 'RequestId') { $RequestId } else { '' }
        RequestHash    = $hash
        CacheDirectory = $cache
        ControlPath    = $controlPath
    }
    return $script:WibCancellationContext
}

function Get-WibCancellationContext {
    return $script:WibCancellationContext
}

function Reset-WibCancellationContext {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param([switch]$RemoveControlFile)

    $context = $script:WibCancellationContext
    if ($RemoveControlFile -and $context.Enabled -and -not [string]::IsNullOrWhiteSpace([string]$context.ControlPath)) {
        $isOwnedMarker = Test-WibCancellationControlFile -Path ([string]$context.ControlPath) -RequestHash ([string]$context.RequestHash)
        if ($isOwnedMarker -and $PSCmdlet.ShouldProcess([string]$context.ControlPath, 'Remove consumed cancellation marker')) {
            Remove-Item -LiteralPath ([string]$context.ControlPath) -Force -ErrorAction SilentlyContinue
        }
    }
    $script:WibCancellationContext = [pscustomobject]@{
        Enabled=$false; RequestId=''; RequestHash=''; CacheDirectory=''; ControlPath=''
    }
}

function Save-WibCancellationRequest {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$TargetRequestId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CacheDirectory
    )

    $hash = Get-WibCancellationRequestHash -RequestId $TargetRequestId
    $path = Get-WibCancellationControlPathFromHash -RequestHash $hash -CacheDirectory $CacheDirectory
    $directory = Split-Path -Parent $path
    $requested = $false

    if ($PSCmdlet.ShouldProcess($path, 'Write cancellation request')) {
        try {
            if (-not (Test-Path -LiteralPath $directory)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }

            if (Test-Path -LiteralPath $path) {
                if (-not (Test-WibCancellationControlFile -Path $path -RequestHash $hash)) {
                    throw (New-WibErrorException -Code 'PATH_NOT_WRITABLE' -Message 'Cancellation control path is occupied by a file that is not owned by Windows ISO Builder.' -Stage 'startup' -PublicMessage 'Cancellation control path is not safe to use.' -Details ([ordered]@{ path=$path }))
                }
                $requested = $true
            }
            else {
                $payload = [ordered]@{
                    kind = 'windows-iso-builder-cancel'
                    schemaVersion = 1
                    requestHash = $hash
                    requestedAt = (Get-Date).ToUniversalTime().ToString('o')
                }
                $json = ConvertTo-WibJsonText -Value $payload -Depth 6
                $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($json)
                $stream = $null
                try {
                    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
                    $stream.Write($bytes, 0, $bytes.Length)
                    $stream.Flush()
                }
                catch [IO.IOException] {
                    # Another CancelBuild may have won the CreateNew race. It is
                    # safe only when the existing file is a valid marker for the
                    # same target hash; never overwrite an unrelated user file.
                    if (-not (Test-WibCancellationControlFile -Path $path -RequestHash $hash)) { throw }
                }
                finally {
                    if ($null -ne $stream) { $stream.Dispose() }
                }
                if (-not (Test-WibCancellationControlFile -Path $path -RequestHash $hash)) {
                    throw (New-WibErrorException -Code 'PATH_NOT_WRITABLE' -Message 'Cancellation marker could not be created safely.' -Stage 'startup' -PublicMessage 'Cancellation marker could not be created.' -Details ([ordered]@{ path=$path }))
                }
                $requested = $true
            }
        }
        catch {
            $knownCode = ''
            try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
            if (-not [string]::IsNullOrWhiteSpace($knownCode)) { throw }
            throw (New-WibErrorException -Code 'PATH_NOT_WRITABLE' -Message ('Unable to create cancellation control marker: {0}' -f $_.Exception.Message) -Stage 'startup' -PublicMessage 'Cancellation control path is not writable.' -Details ([ordered]@{ path=$path }))
        }
    }

    return [pscustomobject]@{ Requested=$requested; TargetRequestId=$TargetRequestId; ControlPath=$path }
}

function Test-WibCancellationRequested {
    $context = $script:WibCancellationContext
    if (-not $context.Enabled -or [string]::IsNullOrWhiteSpace([string]$context.ControlPath)) {
        return $false
    }
    return (Test-WibCancellationControlFile -Path ([string]$context.ControlPath) -RequestHash ([string]$context.RequestHash))
}

function New-WibCancellationException {
    param([string]$Stage = 'preflight', [string]$Message = 'Сборка отменена пользователем.')

    $details = [ordered]@{}
    if ($script:WibCancellationContext.Enabled -and -not [string]::IsNullOrWhiteSpace([string]$script:WibCancellationContext.RequestId)) {
        $details.targetRequestId = [string]$script:WibCancellationContext.RequestId
    }
    return (New-WibErrorException -Code 'BUILD_CANCELLED' -Message $Message -Stage $Stage -PublicMessage $Message -Details $details)
}

function Assert-WibNotCancelled {
    param([string]$Stage = 'preflight')
    if (Test-WibCancellationRequested) {
        throw (New-WibCancellationException -Stage $Stage)
    }
}

function Wait-WibCancellableDelay {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(0, 3600)][double]$Seconds,
        [string]$Stage = 'download'
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        Assert-WibNotCancelled -Stage $Stage
        $remaining = ($deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($remaining -le 0) { break }
        $sleepMs = [int][Math]::Min(250, [Math]::Max(1, $remaining))
        Start-Sleep -Milliseconds $sleepMs
    } while ([DateTime]::UtcNow -lt $deadline)
    Assert-WibNotCancelled -Stage $Stage
}

function Write-WibProcessTerminationDiagnostic {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-WibInfo $Message
    if (Get-Command Write-WibConverterDetailLine -ErrorAction SilentlyContinue) {
        try { Write-WibConverterDetailLine -Line ('[CONTROL] ' + $Message) } catch { }
    }
}

function Stop-WibOwnedProcessTree {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param([Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$ProcessId)

    if ($env:OS -ne 'Windows_NT') { return $false }
    $ownedProcess = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $ownedProcess) { return $true }
    if (-not $PSCmdlet.ShouldProcess(('PID {0}' -f $ProcessId), 'Terminate Windows ISO Builder owned process tree')) { return $false }

    $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (-not (Test-Path -LiteralPath $taskkill)) {
        $taskkillCommand = Get-Command taskkill.exe -ErrorAction SilentlyContinue
        if ($taskkillCommand) { $taskkill = $taskkillCommand.Source }
    }

    if (Test-Path -LiteralPath $taskkill) {
        try {
            Write-WibProcessTerminationDiagnostic ('Terminating owned process tree rooted at PID {0}.' -f $ProcessId)
            $terminator = Start-Process -FilePath $taskkill -ArgumentList @('/PID', [string]$ProcessId, '/T', '/F') -Wait -PassThru -WindowStyle Hidden
            if ($terminator.ExitCode -eq 0 -or -not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return $true }
            Write-WibProcessTerminationDiagnostic ('taskkill returned exit code {0} for PID {1}.' -f $terminator.ExitCode, $ProcessId)
        }
        catch {
            Write-WibProcessTerminationDiagnostic ('taskkill failed for PID {0}: {1}' -f $ProcessId, $_.Exception.Message)
        }
    }

    try {
        $ownedProcess = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $ownedProcess) { $ownedProcess.Kill() }
    }
    catch {
        Write-WibProcessTerminationDiagnostic ('Fallback root-process termination failed for PID {0}: {1}' -f $ProcessId, $_.Exception.Message)
    }
    return (-not [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

function Open-WibManagedOutputReader {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $encoding = [Console]::OutputEncoding
    if ($null -eq $encoding) { $encoding = [Text.Encoding]::Default }
    return (New-Object IO.StreamReader($stream, $encoding, $true))
}

function Read-WibManagedOutputLines {
    param(
        [AllowNull()][IO.StreamReader]$Reader,
        [AllowNull()][scriptblock]$LineHandler
    )
    if ($null -eq $Reader) { return }
    while (-not $Reader.EndOfStream) {
        $line = $Reader.ReadLine()
        if ($null -ne $line -and $null -ne $LineHandler) { & $LineHandler $line }
    }
}

function Invoke-WibManagedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [string]$Stage = 'download',
        [AllowNull()][scriptblock]$LineHandler = $null,
        [AllowNull()][scriptblock]$StageProvider = $null
    )

    Assert-WibNotCancelled -Stage $Stage
    $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) ('wib-process-{0}.out' -f [Guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) ('wib-process-{0}.err' -f [Guid]::NewGuid().ToString('N'))
    $process = $null
    $stdoutReader = $null
    $stderrReader = $null
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
        Write-WibProcessTerminationDiagnostic ('Managed process started with PID {0}.' -f $process.Id)

        for ($openAttempt = 0; $openAttempt -lt 20 -and ($null -eq $stdoutReader -or $null -eq $stderrReader); $openAttempt++) {
            if ($null -eq $stdoutReader) { try { $stdoutReader = Open-WibManagedOutputReader -Path $stdoutPath } catch { } }
            if ($null -eq $stderrReader) { try { $stderrReader = Open-WibManagedOutputReader -Path $stderrPath } catch { } }
            if ($null -eq $stdoutReader -or $null -eq $stderrReader) { Start-Sleep -Milliseconds 50 }
        }

        while (-not $process.HasExited) {
            Read-WibManagedOutputLines -Reader $stdoutReader -LineHandler $LineHandler
            Read-WibManagedOutputLines -Reader $stderrReader -LineHandler $LineHandler
            if (Test-WibCancellationRequested) {
                $cancelStage = $Stage
                if ($null -ne $StageProvider) {
                    try {
                        $candidate = [string](& $StageProvider)
                        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $cancelStage = $candidate }
                    }
                    catch { }
                }
                Stop-WibOwnedProcessTree -ProcessId $process.Id -Confirm:$false | Out-Null
                try { $process.WaitForExit(5000) | Out-Null } catch { }
                Read-WibManagedOutputLines -Reader $stdoutReader -LineHandler $LineHandler
                Read-WibManagedOutputLines -Reader $stderrReader -LineHandler $LineHandler
                throw (New-WibCancellationException -Stage $cancelStage)
            }
            Start-Sleep -Milliseconds 200
        }

        $process.WaitForExit()
        Read-WibManagedOutputLines -Reader $stdoutReader -LineHandler $LineHandler
        Read-WibManagedOutputLines -Reader $stderrReader -LineHandler $LineHandler
        return [pscustomobject]@{ ExitCode=[int]$process.ExitCode; ProcessId=[int]$process.Id; Cancelled=$false }
    }
    finally {
        if ($null -ne $stdoutReader) { $stdoutReader.Dispose() }
        if ($null -ne $stderrReader) { $stderrReader.Dispose() }
        if ($null -ne $process) { $process.Dispose() }
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}
