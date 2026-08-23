# Release-hardening overrides for the real UUP conversion path.
# Keep this layer small: it corrects upstream option semantics, verifies the
# requested install-image format, and makes converter diagnostics time-aware.

$script:WibExpectedImageFormat = ''
$script:WibBaseGetIsoMetadata = ${function:Get-WibIsoMetadata}

function Set-WibConverterConfiguration {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Plan)

    $virtualEditions = @($Plan.VirtualEditions)
    $isEsd = [string]$Plan.ImageFormat -eq 'ESD'
    $useWimToEsd = $isEsd -and [bool]$Plan.AddUpdates
    $script:WibExpectedImageFormat = if ($isEsd) { 'ESD' } else { 'WIM' }

    # uup-converter-wimlib AutoStart values are output choices:
    # 1 = ISO + install.wim, 2 = ISO + install.esd.
    Set-WibIniValue -Path $Path -Name 'AutoStart' -Value $(if ($isEsd) { '2' } else { '1' })
    Set-WibIniValue -Path $Path -Name 'AutoExit' -Value '1'
    Set-WibIniValue -Path $Path -Name 'AddUpdates' -Value $(if ([bool]$Plan.AddUpdates) { '1' } else { '0' })
    Set-WibIniValue -Path $Path -Name 'Cleanup' -Value $(if ([bool]$Plan.Cleanup) { '1' } else { '0' })
    Set-WibIniValue -Path $Path -Name 'NetFx3' -Value $(if ([bool]$Plan.NetFx3) { '1' } else { '0' })
    Set-WibIniValue -Path $Path -Name 'SkipWinRE' -Value '0'
    Set-WibIniValue -Path $Path -Name 'wim2esd' -Value $(if ($useWimToEsd) { '1' } else { '0' })
    Set-WibIniValue -Path $Path -Name 'StartVirtual' -Value $(if ($virtualEditions.Count -gt 0) { '1' } else { '0' })
    if ($virtualEditions.Count -gt 0) {
        Set-WibIniValue -Path $Path -Name 'vAutoStart' -Value '1'
        Set-WibIniValue -Path $Path -Name 'vAutoEditions' -Value ($virtualEditions -join ',')
        Set-WibIniValue -Path $Path -Name 'vwim2esd' -Value $(if ($useWimToEsd) { '1' } else { '0' })
    }
}

function Get-WibIsoMetadata {
    param([Parameter(Mandatory = $true)][string]$IsoPath)

    $result = & $script:WibBaseGetIsoMetadata -IsoPath $IsoPath
    if (-not $result.Mounted -or [string]::IsNullOrWhiteSpace($script:WibExpectedImageFormat)) {
        return $result
    }

    $matchesRequestedFormat = if ($script:WibExpectedImageFormat -eq 'ESD') {
        [bool]$result.HasInstallEsd
    }
    else {
        [bool]$result.HasInstallWim
    }

    if (-not $matchesRequestedFormat) {
        throw (New-WibErrorException -Code 'ISO_VALIDATION_FAILED' `
            -Message ('Generated ISO does not contain the requested install.{0} image.' -f $script:WibExpectedImageFormat.ToLowerInvariant()) `
            -Stage 'verify' `
            -PublicMessage 'Generated ISO does not contain the requested install image format.' `
            -Details ([ordered]@{
                requestedFormat = $script:WibExpectedImageFormat
                hasInstallWim = [bool]$result.HasInstallWim
                hasInstallEsd = [bool]$result.HasInstallEsd
            }))
    }

    return $result
}

function Write-WibConverterDetailLine {
    param([AllowEmptyString()][string]$Line)

    if ([string]::IsNullOrWhiteSpace($script:WibConverterDetailLogPath)) { return }
    try {
        $record = '{0}`t{1}{2}' -f ([DateTimeOffset]::Now.ToString('o')), $Line, [Environment]::NewLine
        [IO.File]::AppendAllText($script:WibConverterDetailLogPath, $record, (New-Object Text.UTF8Encoding($false)))
    }
    catch { }
}
