$script:WibBackendContractSchemaVersion = 1
$script:WibBackendCommands = @(
    'GetVersion', 'SearchBuilds', 'GetRecommendedBuild', 'GetLanguages',
    'GetEditions', 'CreateBuildPlan', 'ValidateBuildPlan', 'ExecuteBuildPlan'
)

function Test-WibBackendObject {
    param([AllowNull()]$Value)
    return ($null -ne $Value -and ($Value -is [pscustomobject] -or $Value -is [System.Collections.IDictionary]))
}

function Get-WibBackendProperty {
    param([AllowNull()]$Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $Object[$key] }
        }
        return $null
    }
    foreach ($property in $Object.PSObject.Properties) {
        if ([string]::Equals([string]$property.Name, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $property.Value }
    }
    return $null
}

function Test-WibBackendProperty {
    param([AllowNull()]$Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Test-WibBackendInteger {
    param([AllowNull()]$Value)
    return ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64])
}

function Throw-WibBackendError {
    param([string]$Code, [string]$Message, [string]$Stage = 'startup')
    throw (New-WibErrorException -Code $Code -Message $Message -Stage $Stage -PublicMessage $Message)
}

function Get-WibBackendString {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = '', [switch]$Required,
        [string]$Code = 'INVALID_ARGUMENT', [string]$Stage = 'startup'
    )
    if (-not (Test-WibBackendProperty -Object $Object -Name $Name)) {
        if ($Required) { Throw-WibBackendError -Code $Code -Message ("Missing string argument: {0}" -f $Name) -Stage $Stage }
        return $Default
    }
    $value = Get-WibBackendProperty -Object $Object -Name $Name
    if ($null -eq $value -or -not ($value -is [string])) {
        Throw-WibBackendError -Code $Code -Message ("Argument '{0}' must be a string." -f $Name) -Stage $Stage
    }
    $text = ([string]$value).Trim()
    if ($Required -and [string]::IsNullOrWhiteSpace($text)) {
        Throw-WibBackendError -Code $Code -Message ("Argument '{0}' must not be empty." -f $Name) -Stage $Stage
    }
    return $text
}

function Get-WibBackendBoolean {
    param($Object, [string]$Name, [bool]$Default, [string]$Code = 'INVALID_ARGUMENT', [string]$Stage = 'startup')
    if (-not (Test-WibBackendProperty -Object $Object -Name $Name)) { return $Default }
    $value = Get-WibBackendProperty -Object $Object -Name $Name
    if (-not ($value -is [bool])) { Throw-WibBackendError -Code $Code -Message ("Argument '{0}' must be boolean." -f $Name) -Stage $Stage }
    return [bool]$value
}

function Get-WibBackendEnum {
    param($Object, [string]$Name, [string[]]$Allowed, [string]$Default = '', [switch]$Required, [string]$Code = 'INVALID_ARGUMENT', [string]$Stage = 'startup')
    $value = Get-WibBackendString -Object $Object -Name $Name -Default $Default -Required:$Required -Code $Code -Stage $Stage
    foreach ($item in $Allowed) {
        if ([string]::Equals($value, $item, [StringComparison]::OrdinalIgnoreCase)) { return $item }
    }
    Throw-WibBackendError -Code $Code -Message ("Argument '{0}' has unsupported value '{1}'." -f $Name, $value) -Stage $Stage
}

function Get-WibBackendLanguage {
    param($Object, [string]$Name = 'language', [string]$Code = 'INVALID_ARGUMENT', [string]$Stage = 'metadata')
    $value = Get-WibBackendString -Object $Object -Name $Name -Required -Code $Code -Stage $Stage
    if ($value -notmatch '^[a-z]{2}-[a-z]{2}$') { Throw-WibBackendError -Code $Code -Message ("Argument '{0}' must use xx-xx format." -f $Name) -Stage $Stage }
    return $value.ToLowerInvariant()
}

function Get-WibBackendStringArray {
    param($Object, [string]$Name, [string]$Code = 'INVALID_ARGUMENT', [string]$Stage = 'plan')
    $value = Get-WibBackendProperty -Object $Object -Name $Name
    if ($null -eq $value -or $value -is [string]) { Throw-WibBackendError -Code $Code -Message ("Argument '{0}' must be a string array." -f $Name) -Stage $Stage }
    $result = @()
    foreach ($item in @($value)) {
        if ($null -eq $item -or -not ($item -is [string]) -or [string]::IsNullOrWhiteSpace([string]$item)) {
            Throw-WibBackendError -Code $Code -Message ("Argument '{0}' contains an invalid value." -f $Name) -Stage $Stage
        }
        $result += ([string]$item).Trim()
    }
    $result = @($result | Select-Object -Unique)
    if ($result.Count -eq 0) { Throw-WibBackendError -Code $Code -Message ("Argument '{0}' must not be empty." -f $Name) -Stage $Stage }
    return $result
}

function Resolve-WibBackendPath {
    param([string]$Value, [string]$Name, [string]$Code = 'INVALID_ARGUMENT', [string]$Stage = 'plan')
    try {
        if ([string]::IsNullOrWhiteSpace($Value)) { throw 'empty' }
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Value))
    }
    catch { Throw-WibBackendError -Code $Code -Message ("Argument '{0}' is not a valid path." -f $Name) -Stage $Stage }
}

function Get-WibBackendPath {
    param($Object, [string]$Name, [string]$Default, [switch]$Required, [string]$Code = 'INVALID_ARGUMENT', [string]$Stage = 'plan')
    $value = Get-WibBackendString -Object $Object -Name $Name -Default $Default -Required:$Required -Code $Code -Stage $Stage
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return Resolve-WibBackendPath -Value $value -Name $Name -Code $Code -Stage $Stage
}

function ConvertTo-WibBuildDto {
    param([Parameter(Mandatory = $true)]$Build)
    $created = Get-WibBackendProperty -Object $Build -Name 'CreatedAt'
    if ($created -is [datetime]) { $created = ([datetime]$created).ToUniversalTime().ToString('o') }
    elseif ($null -ne $created) { $created = [string]$created }
    $entryType = [string](Get-WibBackendProperty -Object $Build -Name 'EntryType')
    if ([string]::IsNullOrWhiteSpace($entryType)) { $entryType = Get-WibBuildEntryType -Title ([string](Get-WibBackendProperty -Object $Build -Name 'Title')) }
    return [pscustomobject][ordered]@{
        uuid = [string](Get-WibBackendProperty -Object $Build -Name 'Uuid')
        title = [string](Get-WibBackendProperty -Object $Build -Name 'Title')
        product = [string](Get-WibBackendProperty -Object $Build -Name 'Product')
        versionLabel = [string](Get-WibBackendProperty -Object $Build -Name 'VersionLabel')
        build = [string](Get-WibBackendProperty -Object $Build -Name 'Build')
        architecture = [string](Get-WibBackendProperty -Object $Build -Name 'Architecture')
        entryType = $entryType
        createdAt = $created
        isPreview = [bool](Get-WibBackendProperty -Object $Build -Name 'IsPreview')
    }
}

function ConvertFrom-WibBuildDto {
    param($Build, [string]$Code = 'INVALID_ARGUMENT')
    if (-not (Test-WibBackendObject -Value $Build)) { Throw-WibBackendError -Code $Code -Message "Argument 'build' must be an object." -Stage 'plan' }
    return [pscustomobject]@{
        Uuid = Get-WibBackendString -Object $Build -Name 'uuid' -Required -Code $Code -Stage 'plan'
        Title = Get-WibBackendString -Object $Build -Name 'title' -Required -Code $Code -Stage 'plan'
        Product = Get-WibBackendString -Object $Build -Name 'product' -Required -Code $Code -Stage 'plan'
        VersionLabel = Get-WibBackendString -Object $Build -Name 'versionLabel' -Default '' -Code $Code -Stage 'plan'
        Build = Get-WibBackendString -Object $Build -Name 'build' -Required -Code $Code -Stage 'plan'
        Architecture = Get-WibBackendEnum -Object $Build -Name 'architecture' -Allowed @('amd64','arm64','x86') -Required -Code $Code -Stage 'plan'
        IsPreview = Get-WibBackendBoolean -Object $Build -Name 'isPreview' -Default $false -Code $Code -Stage 'plan'
    }
}

function ConvertTo-WibBuildPlanDto {
    param($Plan)
    return [pscustomobject][ordered]@{
        schemaVersion = [int](Get-WibBackendProperty $Plan 'SchemaVersion')
        applicationVersion = [string](Get-WibBackendProperty $Plan 'ApplicationVersion')
        createdAt = [string](Get-WibBackendProperty $Plan 'CreatedAt')
        build = ConvertTo-WibBuildDto (Get-WibBackendProperty $Plan 'Build')
        language = [string](Get-WibBackendProperty $Plan 'Language')
        editions = @((Get-WibBackendProperty $Plan 'Editions'))
        sourceEdition = [string](Get-WibBackendProperty $Plan 'SourceEdition')
        virtualEditions = @((Get-WibBackendProperty $Plan 'VirtualEditions'))
        imageFormat = [string](Get-WibBackendProperty $Plan 'ImageFormat')
        addUpdates = [bool](Get-WibBackendProperty $Plan 'AddUpdates')
        cleanup = [bool](Get-WibBackendProperty $Plan 'Cleanup')
        netFx3 = [bool](Get-WibBackendProperty $Plan 'NetFx3')
        outputDirectory = [string](Get-WibBackendProperty $Plan 'OutputDirectory')
        cacheDirectory = [string](Get-WibBackendProperty $Plan 'CacheDirectory')
        removeWorkAfterSuccess = [bool](Get-WibBackendProperty $Plan 'RemoveWorkAfterSuccess')
    }
}

function ConvertFrom-WibBuildPlanDto {
    param($Plan)
    $code = 'INVALID_BUILD_PLAN'
    if (-not (Test-WibBackendObject $Plan)) { Throw-WibBackendError $code 'Build plan must be an object.' 'plan' }
    $schema = Get-WibBackendProperty $Plan 'schemaVersion'
    if (-not (Test-WibBackendInteger $schema)) { Throw-WibBackendError $code 'Build plan schemaVersion must be an integer.' 'plan' }
    $build = ConvertFrom-WibBuildDto (Get-WibBackendProperty $Plan 'build') $code
    $language = Get-WibBackendLanguage $Plan 'language' $code 'plan'
    $editions = Get-WibBackendStringArray $Plan 'editions' $code 'plan'
    $imageFormat = Get-WibBackendEnum $Plan 'imageFormat' @('WIM','ESD') '' -Required -Code $code -Stage 'plan'
    $outputDirectory = Get-WibBackendPath $Plan 'outputDirectory' '' -Required -Code $code -Stage 'plan'
    $cacheDirectory = Get-WibBackendPath $Plan 'cacheDirectory' '' -Required -Code $code -Stage 'plan'
    $sourceEdition = Get-WibBackendString $Plan 'sourceEdition' $editions[0] -Code $code -Stage 'plan'
    if ([string]::IsNullOrWhiteSpace($sourceEdition)) { $sourceEdition = $editions[0] }
    $virtual = @($editions | Where-Object { $_ -ne $sourceEdition })
    return [pscustomobject][ordered]@{
        SchemaVersion = [int]$schema
        ApplicationVersion = Get-WibBackendString $Plan 'applicationVersion' $script:WibApplicationVersion -Code $code -Stage 'plan'
        CreatedAt = Get-WibBackendString $Plan 'createdAt' (Get-Date).ToString('o') -Code $code -Stage 'plan'
        Build = $build
        Language = $language
        Editions = @($editions)
        SourceEdition = $sourceEdition
        VirtualEditions = @($virtual)
        ImageFormat = $imageFormat
        AddUpdates = Get-WibBackendBoolean $Plan 'addUpdates' $true $code 'plan'
        Cleanup = Get-WibBackendBoolean $Plan 'cleanup' $true $code 'plan'
        NetFx3 = Get-WibBackendBoolean $Plan 'netFx3' $false $code 'plan'
        OutputDirectory = $outputDirectory
        CacheDirectory = $cacheDirectory
        RemoveWorkAfterSuccess = Get-WibBackendBoolean $Plan 'removeWorkAfterSuccess' $false $code 'plan'
    }
}

function ConvertTo-WibLanguageDto { param($Value) [pscustomobject][ordered]@{ code=[string](Get-WibBackendProperty $Value 'Code'); name=[string](Get-WibBackendProperty $Value 'Name') } }
function ConvertTo-WibEditionDto { param($Value) [pscustomobject][ordered]@{ code=[string](Get-WibBackendProperty $Value 'Code'); name=[string](Get-WibBackendProperty $Value 'Name') } }
