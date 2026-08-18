#requires -Version 5.1
Set-StrictMode -Version Latest

function Import-WibReleaseValidationConfig {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $path = Join-Path $ProjectRoot 'tools\ReleasePackageConfig.psd1'
    if (-not (Test-Path -LiteralPath $path)) {
        throw 'Release package configuration is missing.'
    }
    return Import-PowerShellDataFile -LiteralPath $path
}

function Expand-WibReleaseEntries {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Version
    )

    return @($Config.RuntimeEntries | ForEach-Object {
        ([string]$_).Replace('{version}', $Version)
    })
}

function Get-WibReleaseRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Path is outside the expected release root.'
    }
    return ($pathFull.Substring($rootFull.Length) -replace '^[\\/]+', '')
}

function Get-WibReleaseSourceFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Version
    )

    $files = @()
    foreach ($relativeEntry in (Expand-WibReleaseEntries -Config $Config -Version $Version)) {
        $sourcePath = Join-Path $ProjectRoot $relativeEntry
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw ("Release package entry is missing: {0}" -f $relativeEntry)
        }
        $item = Get-Item -LiteralPath $sourcePath
        if ($item.PSIsContainer) {
            foreach ($file in @(Get-ChildItem -LiteralPath $sourcePath -Recurse -Force -File)) {
                $files += [pscustomobject]@{
                    RelativePath = Get-WibReleaseRelativePath -Root $ProjectRoot -Path $file.FullName
                    FullName = $file.FullName
                }
            }
        }
        else {
            $files += [pscustomobject]@{
                RelativePath = Get-WibReleaseRelativePath -Root $ProjectRoot -Path $item.FullName
                FullName = $item.FullName
            }
        }
    }
    return @($files | Sort-Object RelativePath -Unique)
}

function Get-WibFilesUnderRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object {
        [pscustomobject]@{
            RelativePath = Get-WibReleaseRelativePath -Root $Root -Path $_.FullName
            FullName = $_.FullName
        }
    } | Sort-Object RelativePath -Unique)
}

function Get-WibCurrentTreeFiles {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $git) {
        $relativePaths = @(& $git.Source -C $ProjectRoot ls-files 2>$null)
        if ($LASTEXITCODE -eq 0 -and $relativePaths.Count -gt 0) {
            return @($relativePaths | ForEach-Object {
                $relativePath = [string]$_
                $fullPath = Join-Path $ProjectRoot $relativePath
                if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                    [pscustomobject]@{ RelativePath=$relativePath; FullName=$fullPath }
                }
            } | Where-Object { $null -ne $_ } | Sort-Object RelativePath -Unique)
        }
    }

    $excludedSegments = @('.git','dist','output','logs','cache','TestResults','.private')
    return @(Get-WibFilesUnderRoot -Root $ProjectRoot | Where-Object {
        $segments = @(([string]$_.RelativePath -replace '/', '\') -split '\\')
        @($segments | Where-Object { $excludedSegments -contains $_ }).Count -eq 0
    })
}

function Test-WibReleaseRelativePathDenied {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)]$Config
    )

    $normalized = $RelativePath -replace '/', '\'
    $segments = @($normalized -split '\\' | Where-Object { $_ -ne '' })
    foreach ($segment in $segments) {
        if (@($Config.DeniedPathSegments) -contains $segment) { return $true }
    }

    $fileName = [IO.Path]::GetFileName($normalized)
    if (@($Config.DeniedFileNames) -contains $fileName) { return $true }

    $extension = [IO.Path]::GetExtension($fileName)
    if ($extension -and (@($Config.DeniedExtensions) -contains $extension.ToLowerInvariant())) { return $true }
    return $false
}

function Get-WibReleaseSafetyFindings {
    param(
        [Parameter(Mandatory = $true)]$Files,
        [Parameter(Mandatory = $true)]$Config,
        [switch]$SkipDenyPathCheck
    )

    $findings = @()
    $tokenPatterns = @(
        ('gh' + 'p_[A-Za-z0-9]{20,}'),
        ('github_' + 'pat_[A-Za-z0-9_]{20,}'),
        ('sk-' + '[A-Za-z0-9]{20,}')
    )
    $privateKeyPattern = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    $credentialAssignmentPattern = '(?im)\b(?:access[_-]?token|client[_-]?secret)\b\s*[:=]\s*["''][^"'']{8,}["'']'
    $personalPathPattern = '(?i)C:\\Users\\(?!Example(?:\\|$)|<[^>]+>(?:\\|$))[^\\\r\n]+'

    foreach ($file in @($Files)) {
        $relativePath = [string]$file.RelativePath
        if (-not $SkipDenyPathCheck -and (Test-WibReleaseRelativePathDenied -RelativePath $relativePath -Config $Config)) {
            $findings += [pscustomobject]@{ type='denied-path'; path=$relativePath }
            continue
        }

        $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
        if (@($Config.TextScanExtensions) -notcontains $extension) { continue }

        try {
            $text = [IO.File]::ReadAllText([string]$file.FullName, [Text.Encoding]::UTF8)
        }
        catch {
            $findings += [pscustomobject]@{ type='unreadable-text'; path=$relativePath }
            continue
        }

        foreach ($pattern in $tokenPatterns) {
            if ($text -match $pattern) {
                $findings += [pscustomobject]@{ type='possible-token'; path=$relativePath }
                break
            }
        }
        if ($text -match $privateKeyPattern) {
            $findings += [pscustomobject]@{ type='private-key-block'; path=$relativePath }
        }
        if ($text -match $credentialAssignmentPattern) {
            $findings += [pscustomobject]@{ type='possible-credential-assignment'; path=$relativePath }
        }
        if ($text -match $personalPathPattern) {
            $findings += [pscustomobject]@{ type='personal-absolute-path'; path=$relativePath }
        }
    }
    return @($findings)
}

function Get-WibSchemaVersionFromSource {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$VariableName
    )

    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $pattern = '\$script:' + [regex]::Escape($VariableName) + '\s*=\s*(\d+)'
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        throw ("Unable to read schema version from {0}." -f $Path)
    }
    return [int]$match.Groups[1].Value
}

function Get-WibReleaseManifestData {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ApplicationVersion
    )

    $moduleManifestPath = Join-Path $ProjectRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psd1'
    $moduleManifest = Import-PowerShellDataFile -LiteralPath $moduleManifestPath
    $contractPath = Join-Path $ProjectRoot 'src\WindowsISOBuilder\Private\BackendContract.ps1'
    $planPath = Join-Path $ProjectRoot 'src\WindowsISOBuilder\Private\Plan.ps1'

    return [ordered]@{
        applicationVersion = $ApplicationVersion
        moduleVersion = [string]$moduleManifest.ModuleVersion
        backendContractSchemaVersion = Get-WibSchemaVersionFromSource -Path $contractPath -VariableName 'WibBackendContractSchemaVersion'
        buildPlanSchemaVersion = Get-WibSchemaVersionFromSource -Path $planPath -VariableName 'WibBuildPlanSchemaVersion'
    }
}
