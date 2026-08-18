$script:WibMinimumCacheFreeBytes = [int64](40GB)
$script:WibMinimumOutputFreeBytes = [int64](8GB)

function Test-WibWindowsHost { return ($env:OS -eq 'Windows_NT') }
function Test-Wib64BitHost { return [Environment]::Is64BitOperatingSystem }
function Get-WibPowerShellRuntimeVersion { return [version]$PSVersionTable.PSVersion }
function Test-WibPreflightComponent {
    param([Parameter(Mandatory = $true)][string]$Name)
    return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function New-WibPreflightCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet('pass','warning','fail','skipped')][string]$Status,
        [Parameter(Mandatory = $true)][ValidateSet('info','warning','error')][string]$Severity,
        [AllowNull()][string]$Code = $null,
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowNull()]$Data = $null
    )
    if ($null -eq $Data) { $Data = [ordered]@{} }
    return [pscustomobject][ordered]@{
        id=$Id; status=$Status; severity=$Severity; code=$Code; message=$Message; data=$Data
    }
}

function Test-WibPreflightDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('cache','output')][string]$Kind
    )

    $checks = @()
    $fullPath = ''
    $pathId = 'path.{0}' -f $Kind
    $writeId = 'path.{0}Writable' -f $Kind
    try {
        $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
        if (Test-Path -LiteralPath $fullPath) {
            $item = Get-Item -LiteralPath $fullPath -Force
            if (-not $item.PSIsContainer) { throw 'Path exists but is not a directory.' }
        }
        else {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        }
        $checks += New-WibPreflightCheck -Id $pathId -Status pass -Severity error -Message ('Directory is available: {0}' -f $fullPath) -Data ([ordered]@{ path=$fullPath })
    }
    catch {
        $checks += New-WibPreflightCheck -Id $pathId -Status fail -Severity error -Code 'PATH_NOT_WRITABLE' -Message ('Directory cannot be prepared: {0}' -f $Path) -Data ([ordered]@{ path=$Path })
        $checks += New-WibPreflightCheck -Id $writeId -Status skipped -Severity error -Code 'PATH_NOT_WRITABLE' -Message 'Write probe skipped because the directory is unavailable.' -Data ([ordered]@{ path=$Path })
        return [pscustomobject]@{ FullPath=''; Checks=@($checks); Writable=$false }
    }

    $probePath = Join-Path $fullPath ('.wib-preflight-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $stream = $null
    try {
        $stream = [IO.File]::Open($probePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.WriteByte(0)
        $stream.Flush()
        $checks += New-WibPreflightCheck -Id $writeId -Status pass -Severity error -Message ('Directory is writable: {0}' -f $fullPath) -Data ([ordered]@{ path=$fullPath })
        return [pscustomobject]@{ FullPath=$fullPath; Checks=@($checks); Writable=$true }
    }
    catch {
        $checks += New-WibPreflightCheck -Id $writeId -Status fail -Severity error -Code 'PATH_NOT_WRITABLE' -Message ('Directory is not writable: {0}' -f $fullPath) -Data ([ordered]@{ path=$fullPath })
        return [pscustomobject]@{ FullPath=$fullPath; Checks=@($checks); Writable=$false }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
    }
}

function New-WibDiskSpaceCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('cache','output')][string]$Kind,
        [Parameter(Mandatory = $true)][int64]$RequiredBytes
    )

    $id = 'disk.{0}' -f $Kind
    try {
        $available = [int64](Get-WibDriveFreeBytes -Path $Path)
        $data = [ordered]@{ path=$Path; availableBytes=$available; requiredBytes=$RequiredBytes }
        if ($available -lt $RequiredBytes) {
            return (New-WibPreflightCheck -Id $id -Status fail -Severity error -Code 'DISK_SPACE_LOW' -Message ('Insufficient free space for {0}.' -f $Kind) -Data $data)
        }
        return (New-WibPreflightCheck -Id $id -Status pass -Severity error -Message ('Sufficient free space for {0}.' -f $Kind) -Data $data)
    }
    catch {
        return (New-WibPreflightCheck -Id $id -Status fail -Severity error -Code 'DISK_SPACE_LOW' -Message ('Free space could not be determined for {0}.' -f $Path) -Data ([ordered]@{ path=$Path; availableBytes=$null; requiredBytes=$RequiredBytes }))
    }
}

function Test-WibUupApiAvailability {
    param([int]$TimeoutSeconds = 10)

    $uri = '{0}/listid.php?search=Windows%2011&sortByDate=1' -f $script:UupApiBaseUri
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $response = Invoke-RestMethod -Method Get -Uri $uri -UseBasicParsing -TimeoutSec $TimeoutSeconds -Headers @{
            'User-Agent' = ('WindowsISOBuilder/{0} preflight' -f $script:WibApplicationVersion)
            'Accept'='application/json'
        }
        if ($null -eq $response -or $null -eq $response.response) { throw 'UUP dump API returned an unexpected response.' }
        return [pscustomobject]@{ Available=$true; Uri=$script:UupApiBaseUri; StatusCode=200; Message='Official UUP dump API is reachable.' }
    }
    catch {
        $statusCode = Get-WibHttpStatusCode -Exception $_.Exception
        return [pscustomobject]@{ Available=$false; Uri=$script:UupApiBaseUri; StatusCode=$statusCode; Message='Official UUP dump API is not reachable.' }
    }
}

function Invoke-WibPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [bool]$OnlineChecks = $false
    )

    Assert-WibPlan -Plan $Plan
    $checks = @()

    if (Test-WibWindowsHost) {
        $checks += New-WibPreflightCheck -Id 'host.windows' -Status pass -Severity error -Message 'Supported Windows host.'
    }
    else {
        $checks += New-WibPreflightCheck -Id 'host.windows' -Status fail -Severity error -Code 'UNSUPPORTED_HOST' -Message 'ISO build requires Windows 10 or Windows 11.' -Data ([ordered]@{ os=[string]$env:OS })
    }

    if (Test-Wib64BitHost) {
        $checks += New-WibPreflightCheck -Id 'host.architecture' -Status pass -Severity error -Message '64-bit operating system.'
    }
    else {
        $checks += New-WibPreflightCheck -Id 'host.architecture' -Status fail -Severity error -Code 'UNSUPPORTED_HOST' -Message 'ISO build requires a 64-bit operating system.'
    }

    $powerShellVersion = Get-WibPowerShellRuntimeVersion
    if ($powerShellVersion -ge [version]'5.1') {
        $checks += New-WibPreflightCheck -Id 'host.powershell' -Status pass -Severity error -Message ('Compatible PowerShell {0}.' -f $powerShellVersion) -Data ([ordered]@{ version=[string]$powerShellVersion })
    }
    else {
        $checks += New-WibPreflightCheck -Id 'host.powershell' -Status fail -Severity error -Code 'UNSUPPORTED_HOST' -Message ('PowerShell 5.1 or newer is required; found {0}.' -f $powerShellVersion) -Data ([ordered]@{ version=[string]$powerShellVersion; minimumVersion='5.1' })
    }

    foreach ($tool in @(
        [pscustomobject]@{ Id='tool.cmd'; Name='cmd.exe'; Required=$true },
        [pscustomobject]@{ Id='tool.dism'; Name='dism.exe'; Required=$true },
        [pscustomobject]@{ Id='tool.expandArchive'; Name='Expand-Archive'; Required=$true },
        [pscustomobject]@{ Id='tool.getFileHash'; Name='Get-FileHash'; Required=$true },
        [pscustomobject]@{ Id='tool.mountDiskImage'; Name='Mount-DiskImage'; Required=$false }
    )) {
        if (Test-WibPreflightComponent -Name $tool.Name) {
            $severity = if ($tool.Required) { 'error' } else { 'warning' }
            $checks += New-WibPreflightCheck -Id $tool.Id -Status pass -Severity $severity -Message ('Component is available: {0}' -f $tool.Name) -Data ([ordered]@{ component=$tool.Name })
        }
        elseif ($tool.Required) {
            $checks += New-WibPreflightCheck -Id $tool.Id -Status fail -Severity error -Code 'REQUIRED_COMPONENT_MISSING' -Message ('Required component is missing: {0}' -f $tool.Name) -Data ([ordered]@{ component=$tool.Name })
        }
        else {
            $checks += New-WibPreflightCheck -Id $tool.Id -Status warning -Severity warning -Message ('Optional verification component is unavailable: {0}' -f $tool.Name) -Data ([ordered]@{ component=$tool.Name })
        }
    }

    $cacheResult = Test-WibPreflightDirectory -Path ([string]$Plan.CacheDirectory) -Kind cache
    $outputResult = Test-WibPreflightDirectory -Path ([string]$Plan.OutputDirectory) -Kind output
    $checks += @($cacheResult.Checks)
    $checks += @($outputResult.Checks)

    if ($cacheResult.Writable) {
        $checks += New-WibDiskSpaceCheck -Path $cacheResult.FullPath -Kind cache -RequiredBytes $script:WibMinimumCacheFreeBytes
    }
    else {
        $checks += New-WibPreflightCheck -Id 'disk.cache' -Status skipped -Severity error -Code 'DISK_SPACE_LOW' -Message 'Cache disk-space check skipped because the directory is unavailable.' -Data ([ordered]@{ path=[string]$Plan.CacheDirectory; availableBytes=$null; requiredBytes=$script:WibMinimumCacheFreeBytes })
    }
    if ($outputResult.Writable) {
        $checks += New-WibDiskSpaceCheck -Path $outputResult.FullPath -Kind output -RequiredBytes $script:WibMinimumOutputFreeBytes
    }
    else {
        $checks += New-WibPreflightCheck -Id 'disk.output' -Status skipped -Severity error -Code 'DISK_SPACE_LOW' -Message 'Output disk-space check skipped because the directory is unavailable.' -Data ([ordered]@{ path=[string]$Plan.OutputDirectory; availableBytes=$null; requiredBytes=$script:WibMinimumOutputFreeBytes })
    }

    if ($OnlineChecks) {
        $network = Test-WibUupApiAvailability
        if ($network.Available) {
            $checks += New-WibPreflightCheck -Id 'network.uupApi' -Status pass -Severity warning -Message $network.Message -Data ([ordered]@{ uri=$network.Uri; statusCode=$network.StatusCode })
        }
        else {
            $checks += New-WibPreflightCheck -Id 'network.uupApi' -Status warning -Severity warning -Code 'NETWORK_ERROR' -Message $network.Message -Data ([ordered]@{ uri=$network.Uri; statusCode=$network.StatusCode })
        }
    }
    else {
        $checks += New-WibPreflightCheck -Id 'network.uupApi' -Status skipped -Severity info -Message 'Online checks were not requested.' -Data ([ordered]@{ uri=$script:UupApiBaseUri })
    }

    $fatalFailures = @($checks | Where-Object { $_.status -eq 'fail' -and $_.severity -eq 'error' })
    return [pscustomobject][ordered]@{ ready=($fatalFailures.Count -eq 0); checks=@($checks) }
}

function Assert-WibPreflightReady {
    param([Parameter(Mandatory = $true)]$Report)
    if ([bool]$Report.ready) { return }

    $failures = @($Report.checks | Where-Object { $_.status -eq 'fail' -and $_.severity -eq 'error' })
    if ($failures.Count -eq 0) {
        throw (New-WibErrorException -Code 'BUILD_FAILED' -Message 'Preflight reported not-ready without a fatal check.' -Stage 'preflight')
    }
    $first = $failures[0]
    $details = [ordered]@{ failedCheckIds=@($failures | ForEach-Object { $_.id }) }
    foreach ($name in @('path','availableBytes','requiredBytes','component','statusCode','uri')) {
        if ($null -ne $first.data -and $null -ne $first.data.PSObject -and $first.data.PSObject.Properties.Name -contains $name) {
            $details[$name] = $first.data.$name
        }
        elseif ($first.data -is [System.Collections.IDictionary] -and $first.data.Contains($name)) {
            $details[$name] = $first.data[$name]
        }
    }
    $code = if ([string]::IsNullOrWhiteSpace([string]$first.code)) { 'BUILD_FAILED' } else { [string]$first.code }
    throw (New-WibErrorException -Code $code -Message ([string]$first.message) -Stage 'preflight' -PublicMessage ([string]$first.message) -Details $details)
}

function Show-WibPreflightSummary {
    param([Parameter(Mandatory = $true)]$Report)

    Write-WibStage 'Проверка готовности'
    foreach ($check in @($Report.checks | Where-Object { $_.status -ne 'skipped' })) {
        $prefix = switch ([string]$check.status) {
            'pass' { '[OK]' }
            'warning' { '[!]' }
            'fail' { '[X]' }
            default { '[-]' }
        }
        $color = switch ([string]$check.status) {
            'pass' { 'DarkGray' }
            'warning' { 'Yellow' }
            'fail' { 'Red' }
            default { 'DarkGray' }
        }
        Write-Host ('{0} {1}' -f $prefix, $check.message) -ForegroundColor $color
    }
}
