function Get-WibCachePath {
    param(
        [Parameter(Mandatory = $true)][string]$CacheDirectory,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Extension = 'json'
    )

    $categoryDirectory = Join-Path $CacheDirectory $Category
    if (-not (Test-Path -LiteralPath $categoryDirectory)) {
        New-Item -ItemType Directory -Path $categoryDirectory -Force | Out-Null
    }
    $hash = Get-WibSha256Text -Text $Key
    return (Join-Path $categoryDirectory ('{0}.{1}' -f $hash, $Extension))
}

function Get-WibCachedValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$MaximumAgeHours,
        [switch]$AllowStale
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path
    $age = (Get-Date) - $item.LastWriteTime
    if (-not $AllowStale -and $age.TotalHours -gt $MaximumAgeHours) {
        return $null
    }

    try {
        return Read-WibJsonFile -Path $Path
    }
    catch {
        Write-WibWarning ('Повреждён кеш {0}: {1}' -f $Path, $_.Exception.Message)
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Save-WibCachedValue {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )
    Write-WibJsonFile -Value $Value -Path $Path -Depth 20
}

function Get-WibCacheInfo {
    [CmdletBinding()]
    param([string]$CacheDirectory = (Get-WibDefaultCacheDirectory))

    $cache = Resolve-WibFullPath -Path $CacheDirectory -Create
    $categories = @('api', 'packages', 'work', 'plans', 'logs')
    $items = foreach ($category in $categories) {
        $path = Join-Path $cache $category
        [pscustomobject]@{
            Category = $category
            Path     = $path
            Bytes    = Get-WibDirectorySizeBytes -Path $path
        }
    }

    return [pscustomobject]@{
        Path       = $cache
        TotalBytes = [int64](($items | Measure-Object -Property Bytes -Sum).Sum)
        Categories = @($items)
    }
}

function Clear-WibCache {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$CacheDirectory = (Get-WibDefaultCacheDirectory),
        [ValidateSet('All', 'Api', 'Packages', 'Work', 'Plans', 'Logs')]
        [string]$Category = 'All'
    )

    $cache = Resolve-WibFullPath -Path $CacheDirectory -Create
    $targets = if ($Category -eq 'All') {
        @('api', 'packages', 'work', 'plans', 'logs')
    }
    else {
        @($Category.ToLowerInvariant())
    }

    foreach ($target in $targets) {
        $path = Join-Path $cache $target
        if (Test-Path -LiteralPath $path) {
            if ($PSCmdlet.ShouldProcess($path, 'Удалить кеш')) {
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
    }
}
