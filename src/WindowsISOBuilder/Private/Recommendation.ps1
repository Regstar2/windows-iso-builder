function Get-WibQuickLatestBuild {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows 11', 'Windows 10')]
        [string]$Product,
        [ValidateSet('amd64', 'arm64', 'x86')]
        [string]$Architecture = 'amd64',
        [bool]$ForceRefresh = $true,
        [Parameter(Mandatory = $true)][string]$CacheDirectory
    )

    # Quick mode deliberately skips the catalog UI, but it must never hardcode
    # a Windows release or build number. The same selector is shared by TUI and
    # the machine-readable Backend Contract.
    $builds = @(Search-WibBuilds `
        -Search $Product `
        -Architecture $Architecture `
        -ForceRefresh:$ForceRefresh `
        -CacheDirectory $CacheDirectory)

    $candidates = @($builds | Where-Object {
        $entryType = if ($null -ne $_.PSObject.Properties['EntryType']) {
            [string]$_.EntryType
        }
        else {
            Get-WibBuildEntryType -Title ([string]$_.Title)
        }

        $actualProduct = if ($null -ne $_.PSObject.Properties['Product']) {
            [string]$_.Product
        }
        else {
            Get-WibProductLabel -Title ([string]$_.Title)
        }

        $isPreview = if ($null -ne $_.PSObject.Properties['IsPreview']) {
            [bool]$_.IsPreview
        }
        else {
            Test-WibPreviewTitle -Title ([string]$_.Title)
        }

        $actualArchitecture = if ($null -ne $_.PSObject.Properties['Architecture']) {
            [string]$_.Architecture
        }
        else {
            $Architecture
        }

        $entryType -eq 'Windows' -and
            $actualProduct -eq $Product -and
            $actualArchitecture -eq $Architecture -and
            -not $isPreview
    })

    if ($candidates.Count -eq 0) {
        $architectureLabel = if ($Architecture -eq 'amd64') { 'x64' } else { $Architecture }
        throw (New-WibErrorException `
            -Code 'BUILD_NOT_FOUND' `
            -Message ("UUP dump не вернул стабильную полноценную сборку {0} {1}." -f $Product, $architectureLabel) `
            -Stage 'catalog')
    }

    $recommendedCandidates = $candidates
    if ($Product -eq 'Windows 11') {
        # Preserve the existing project policy: prefer the mainstream stable H2
        # family over specialized H1 releases. Release/build numbers remain fully
        # dynamic and are never embedded in production code.
        $mainstreamCandidates = @($candidates | Where-Object {
            $versionLabel = if ($null -ne $_.PSObject.Properties['VersionLabel']) {
                [string]$_.VersionLabel
            }
            else {
                Get-WibVersionLabel -Title ([string]$_.Title)
            }

            $versionLabel -match '^\d{2}H2$'
        })

        if ($mainstreamCandidates.Count -gt 0) {
            $recommendedCandidates = $mainstreamCandidates
        }
        else {
            Write-WibWarning 'Для Windows 11 не найден обычный стабильный H2-релиз. Используется последняя стабильная сборка из UUP dump.'
        }
    }

    return Get-WibNewestBuild -Builds $recommendedCandidates
}
