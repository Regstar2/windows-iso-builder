function New-WibBuildPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Build,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-z]{2}-[a-z]{2}$')][string]$Language,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Editions,
        [ValidateSet('WIM', 'ESD')][string]$ImageFormat = 'ESD',
        [bool]$AddUpdates = $true,
        [bool]$Cleanup = $true,
        [bool]$NetFx3 = $false,
        [string]$OutputDirectory = (Get-WibDefaultOutputDirectory),
        [string]$CacheDirectory = (Get-WibDefaultCacheDirectory),
        [bool]$RemoveWorkAfterSuccess = $false
    )

    $editionList = @($Editions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($editionList.Count -eq 0) {
        throw 'Нужно выбрать хотя бы одну редакцию.'
    }

    $output = Resolve-WibFullPath -Path $OutputDirectory -Create
    $cache = Resolve-WibFullPath -Path $CacheDirectory -Create
    $sourceEdition = $editionList[0]
    $virtualEditions = @($editionList | Select-Object -Skip 1)

    return [pscustomobject][ordered]@{
        SchemaVersion          = 1
        ApplicationVersion     = $script:WibVersion
        CreatedAt              = (Get-Date).ToString('o')
        Build                  = [pscustomobject][ordered]@{
            Uuid         = [string]$Build.Uuid
            Title        = [string]$Build.Title
            Product      = [string]$Build.Product
            VersionLabel = [string]$Build.VersionLabel
            Build        = [string]$Build.Build
            Architecture = [string]$Build.Architecture
            IsPreview    = [bool]$Build.IsPreview
        }
        Language               = $Language
        Editions               = @($editionList)
        SourceEdition          = $sourceEdition
        VirtualEditions        = @($virtualEditions)
        ImageFormat            = $ImageFormat
        AddUpdates             = $AddUpdates
        Cleanup                = $Cleanup
        NetFx3                 = $NetFx3
        OutputDirectory        = $output
        CacheDirectory         = $cache
        RemoveWorkAfterSuccess = $RemoveWorkAfterSuccess
    }
}

function Assert-WibPlan {
    param([Parameter(Mandatory = $true)]$Plan)

    if ([int]$Plan.SchemaVersion -ne 1) { throw 'Неподдерживаемая версия плана сборки.' }
    if ([string]::IsNullOrWhiteSpace([string]$Plan.Build.Uuid)) { throw 'В плане отсутствует UUID сборки.' }
    if ([string]::IsNullOrWhiteSpace([string]$Plan.Build.Architecture)) { throw 'В плане отсутствует архитектура.' }
    if ([string]::IsNullOrWhiteSpace([string]$Plan.Language)) { throw 'В плане отсутствует язык.' }
    if (@($Plan.Editions).Count -eq 0) { throw 'В плане отсутствуют редакции.' }
    if ([string]$Plan.ImageFormat -notin @('WIM', 'ESD')) { throw 'В плане указан неизвестный формат install-образа.' }
}

function Save-WibPlan {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$Path
    )
    Assert-WibPlan -Plan $Plan
    Write-WibJsonFile -Value $Plan -Path $Path -Depth 20
}

function Read-WibPlan {
    param([Parameter(Mandatory = $true)][string]$Path)
    $plan = Read-WibJsonFile -Path $Path
    if ($null -eq $plan) { throw "Файл плана не найден: $Path" }
    Assert-WibPlan -Plan $plan
    return $plan
}
