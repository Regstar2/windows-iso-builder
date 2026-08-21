# Release hardening for UUP dump conversion-package lifecycle.
# UUP dump conversion bundles contain volatile converter URLs. They must not be
# treated as durable cache entries even when the ZIP structure is still valid.

function Get-WibUupPackageWorkDirectory {
    param([Parameter(Mandatory = $true)][string]$DestinationZip)

    $packageDirectory = Split-Path -Parent $DestinationZip
    if ([string]::IsNullOrWhiteSpace($packageDirectory)) { return $null }
    if ([IO.Path]::GetFileName($packageDirectory) -ne 'packages') { return $null }

    $cacheDirectory = Split-Path -Parent $packageDirectory
    if ([string]::IsNullOrWhiteSpace($cacheDirectory)) { return $null }

    $jobHash = [IO.Path]::GetFileNameWithoutExtension($DestinationZip)
    if ([string]::IsNullOrWhiteSpace($jobHash)) { return $null }

    return (Join-Path (Join-Path $cacheDirectory 'work') $jobHash)
}

function Reset-WibUupConversionMetadata {
    param([Parameter(Mandatory = $true)][string]$DestinationZip)

    $workDirectory = Get-WibUupPackageWorkDirectory -DestinationZip $DestinationZip
    if ([string]::IsNullOrWhiteSpace($workDirectory) -or -not (Test-Path -LiteralPath $workDirectory)) { return }

    try {
        foreach ($fileName in @('uup_download_windows.cmd', 'ConvertConfig.ini')) {
            Get-ChildItem -LiteralPath $workDirectory -Filter $fileName -File -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction Stop
        }
    }
    catch {
        throw (New-WibErrorException -Code 'UUP_PACKAGE_INVALID' -Message ('Cached UUP conversion metadata could not be refreshed: {0}' -f $_.Exception.Message) -Stage 'download' -PublicMessage 'Cached UUP conversion metadata could not be refreshed.')
    }
}

function Download-WibUupPackage {
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)][string]$DestinationZip, [int]$Attempts = 3)

    Assert-WibNotCancelled -Stage 'download'

    # Always request a fresh conversion bundle. The generated package is small,
    # while its embedded converter URLs are intentionally mutable upstream.
    # Reusing a structurally valid old ZIP can therefore make otherwise valid
    # builds fail with permanent 404s after UUP dump rotates converter assets.
    Remove-Item -LiteralPath $DestinationZip -Force -ErrorAction SilentlyContinue

    $query = ConvertTo-WibQueryString -Parameters @{ id=[string]$Plan.Build.Uuid; pack=[string]$Plan.Language; edition=[string]$Plan.SourceEdition }
    $uri = '{0}/get.php?{1}' -f $script:UupWebsiteBaseUri, $query
    $body = @{
        autodl=2
        updates=if ([bool]$Plan.AddUpdates) { 1 } else { 0 }
        cleanup=if ([bool]$Plan.Cleanup) { 1 } else { 0 }
        netfx=if ([bool]$Plan.NetFx3) { 1 } else { 0 }
        esd=if ([string]$Plan.ImageFormat -eq 'ESD') { 1 } else { 0 }
    }
    $invalidPath = "$DestinationZip.response.html"
    $lastReason = ''

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Assert-WibNotCancelled -Stage 'download'
        Remove-Item -LiteralPath $DestinationZip -Force -ErrorAction SilentlyContinue
        Write-WibInfo ('Downloading fresh UUP dump conversion package, attempt {0}/{1}' -f $attempt, $Attempts)
        try {
            Invoke-WibHttpDownload -Method POST -Uri $uri -FormBody $body -OutFile $DestinationZip -TimeoutSeconds 300 -Headers @{
                'User-Agent'=('Mozilla/5.0 WindowsISOBuilder/{0}' -f $script:WibApplicationVersion)
            }
        }
        catch {
            $knownCode = ''
            try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
            if ($knownCode -like 'PROXY_*') { throw }
            $lastReason = $_.Exception.Message
            if ($attempt -lt $Attempts) {
                Wait-WibCancellableDelay -Seconds (5 * $attempt) -Stage 'download'
                continue
            }
            throw (New-WibErrorException -Code 'UUP_PACKAGE_DOWNLOAD_FAILED' -Message 'UUP dump conversion package could not be downloaded.' -Stage 'download' -PublicMessage 'The UUP conversion package could not be downloaded.' -Details ([ordered]@{ attempts=$Attempts }))
        }

        Assert-WibNotCancelled -Stage 'download'
        $validation = Test-WibUupPackageArchive -Path $DestinationZip
        if ($validation.IsValid) {
            # Force Builder.ps1 to expand the just-downloaded bundle instead of
            # finding an older generated script in the resumable work directory.
            # Only generated metadata is removed; downloaded UUP payload files
            # remain in place and aria2 can continue partial downloads.
            Reset-WibUupConversionMetadata -DestinationZip $DestinationZip
            Remove-Item -LiteralPath $invalidPath -Force -ErrorAction SilentlyContinue
            Write-WibInfo ('Received fresh conversion package: {0} bytes.' -f (Get-Item -LiteralPath $DestinationZip).Length)
            return
        }

        $lastReason = $validation.Reason
        Remove-Item -LiteralPath $invalidPath -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $DestinationZip -Destination $invalidPath -Force
        if ($attempt -lt $Attempts) { Wait-WibCancellableDelay -Seconds (5 * $attempt) -Stage 'download' }
    }

    $preview = Get-WibResponsePreview -Path $invalidPath
    $internal = 'UUP dump returned an invalid ZIP. Reason: {0}. Response: {1}' -f $lastReason, $preview
    throw (New-WibErrorException -Code 'UUP_PACKAGE_INVALID' -Message $internal -Stage 'download' -PublicMessage 'UUP dump returned an invalid conversion package.')
}
