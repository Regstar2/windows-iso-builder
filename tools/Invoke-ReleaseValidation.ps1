#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Quick,
    [switch]$Full,
    [switch]$IncludePackageSmoke,
    [switch]$IncludePowerShell7,
    [switch]$IncludeProcessTreeSmoke,
    [string]$PackagePath = '',
    [string]$ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Quick -and $Full) { throw 'Choose either -Quick or -Full.' }

$scriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptPath)) { throw 'Unable to determine validation script path.' }
$scriptDirectory = Split-Path -Parent $scriptPath
$projectRoot = Split-Path -Parent $scriptDirectory
. (Join-Path $scriptDirectory 'ReleaseValidation.Common.ps1')
$config = Import-WibReleaseValidationConfig -ProjectRoot $projectRoot

$mode = if ($Full) { 'Full' } else { 'Quick' }
$withPackage = [bool]($Full -or $IncludePackageSmoke -or -not [string]::IsNullOrWhiteSpace($PackagePath))
$withPs7 = [bool]($Full -or $IncludePowerShell7)
$withProcessSmoke = [bool]($Full -or $IncludeProcessTreeSmoke)
$version = [IO.File]::ReadAllText((Join-Path $projectRoot 'VERSION'), [Text.Encoding]::ASCII).Trim()
$manifestData = Get-WibReleaseManifestData -ProjectRoot $projectRoot -ApplicationVersion $version
$moduleVersion = [string]$manifestData.moduleVersion
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('wib-validation-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($workRoot) | Out-Null
$checks = @()

if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $projectRoot 'validation-result.json' }
$ReportPath = [IO.Path]::GetFullPath($ReportPath)

function Protect-ValidationText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $value = [string]$Text
    foreach ($replacement in @(
        [pscustomobject]@{ Path=$projectRoot; Label='<projectRoot>' },
        [pscustomobject]@{ Path=$workRoot; Label='<temp>' },
        [pscustomobject]@{ Path=$env:USERPROFILE; Label='<userProfile>' }
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$replacement.Path)) {
            $value = $value -replace [regex]::Escape([string]$replacement.Path), [string]$replacement.Label
        }
    }
    return $value
}

function Add-ValidationResult {
    param(
        [string]$Id,
        [ValidateSet('pass','fail','skipped')][string]$Status,
        [bool]$Required,
        [string]$Message = '',
        [AllowNull()]$Details = $null
    )
    $script:checks += [pscustomobject][ordered]@{
        id = $Id
        status = $Status
        required = $Required
        message = Protect-ValidationText $Message
        details = $Details
    }
    Write-Host ('[{0}] {1} - {2}' -f $Status.ToUpperInvariant(), $Id, (Protect-ValidationText $Message))
}

function Invoke-RequiredCheck {
    param([string]$Id, [bool]$Required, [scriptblock]$Action)
    try {
        $details = & $Action
        Add-ValidationResult -Id $Id -Status pass -Required $Required -Message 'completed' -Details $details
    }
    catch {
        Add-ValidationResult -Id $Id -Status fail -Required $Required -Message $_.Exception.Message -Details ([ordered]@{
            error = Protect-ValidationText $_.Exception.Message
        })
    }
}

function Assert-ScriptSyntax {
    param([string]$Path)
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if (@($parseErrors).Count -gt 0) {
        throw ('Syntax errors in {0}: {1}' -f $Path, (@($parseErrors | ForEach-Object { $_.Message }) -join '; '))
    }
}

function Invoke-ChildPowerShell {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw ('Child PowerShell exited with code {0}.' -f $LASTEXITCODE) }
}

function New-SmokePlan {
    param([string]$CacheDirectory, [string]$OutputDirectory)
    return [ordered]@{
        schemaVersion = 1
        applicationVersion = $version
        createdAt = '2026-08-18T00:00:00Z'
        build = [ordered]@{
            uuid = '00000000-0000-0000-0000-000000000000'
            title = 'Release validation smoke'
            product = 'Windows 11'
            versionLabel = 'validation'
            build = '0.0'
            architecture = 'amd64'
            entryType = 'Windows'
            createdAt = '2026-08-18T00:00:00Z'
            isPreview = $false
        }
        language = 'ru-ru'
        editions = @('Professional')
        sourceEdition = 'Professional'
        virtualEditions = @()
        imageFormat = 'ESD'
        addUpdates = $true
        cleanup = $true
        netFx3 = $false
        outputDirectory = $OutputDirectory
        cacheDirectory = $CacheDirectory
        removeWorkAfterSuccess = $false
    }
}

function Invoke-ModuleImportSmoke {
    param([string]$Executable, [string]$Root, [string]$Label)
    $dir = Join-Path $workRoot ($Label + '-module')
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    $probe = Join-Path $dir 'probe.ps1'
    $probeSource = @'
param([string]$ModulePath,[string]$ExpectedRoot)
$ErrorActionPreference='Stop'
Import-Module $ModulePath -Force -ErrorAction Stop
$m=Get-Module WindowsISOBuilder | Select-Object -First 1
if($null -eq $m){throw 'Module was not imported.'}
$a=[IO.Path]::GetFullPath([string]$m.Path)
$r=[IO.Path]::GetFullPath($ExpectedRoot)
if(-not $a.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)){throw 'Imported module is outside expected root.'}
exit 0
'@
    [IO.File]::WriteAllText($probe, $probeSource, [Text.Encoding]::ASCII)
    Invoke-ChildPowerShell -Executable $Executable -Arguments @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$probe,
        '-ModulePath',(Join-Path $Root 'src\WindowsISOBuilder\WindowsISOBuilder.psd1'),
        '-ExpectedRoot',$Root
    )
    return [ordered]@{ importedFromExpectedRoot=$true }
}

function Invoke-BackendSmoke {
    param([string]$Executable, [string]$Root, [string]$Label)
    $dir = Join-Path $workRoot ($Label + '-backend')
    $cache = Join-Path $dir 'cache'
    $output = Join-Path $dir 'output'
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    [IO.Directory]::CreateDirectory($output) | Out-Null
    $entry = Join-Path $Root 'Invoke-WibBackend.ps1'

    $getRequestPath = Join-Path $dir 'get-version-request.json'
    $getResponsePath = Join-Path $dir 'get-version-response.json'
    $eventsPath = Join-Path $dir 'get-version-events.ndjson'
    $getRequest = [ordered]@{ schemaVersion=1; requestId=($Label + '-get-version'); command='GetVersion'; arguments=[ordered]@{} }
    [IO.File]::WriteAllText($getRequestPath, ($getRequest | ConvertTo-Json -Depth 10), $utf8NoBom)
    Invoke-ChildPowerShell -Executable $Executable -Arguments @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$entry,
        '-RequestFile',$getRequestPath,'-ResponseFile',$getResponsePath,'-EventFile',$eventsPath
    )

    $getResponse = [IO.File]::ReadAllText($getResponsePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not [bool]$getResponse.success) { throw 'GetVersion returned success=false.' }
    if ([string]$getResponse.applicationVersion -ne $version) { throw 'GetVersion applicationVersion mismatch.' }
    if ([int]$getResponse.data.contractSchemaVersion -ne 1) { throw 'Backend Contract schema mismatch.' }
    if ([int]$getResponse.data.buildPlanSchemaVersion -ne 1) { throw 'BuildPlan schema mismatch.' }
    foreach ($name in @('schemaVersion','requestId','command','success','applicationVersion','data')) {
        if ($null -eq $getResponse.PSObject.Properties[$name]) { throw ('GetVersion response missing field: {0}' -f $name) }
    }

    $eventLines = @(Get-Content -LiteralPath $eventsPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($eventLines.Count -eq 0) { throw 'Backend event stream is empty.' }
    foreach ($line in $eventLines) {
        $event = $line | ConvertFrom-Json
        foreach ($name in @('schemaVersion','requestId','sequence','timestamp','type','stage','message','progress')) {
            if ($null -eq $event.PSObject.Properties[$name]) { throw ('Backend event missing field: {0}' -f $name) }
        }
    }

    $preRequestPath = Join-Path $dir 'preflight-request.json'
    $preResponsePath = Join-Path $dir 'preflight-response.json'
    $preRequest = [ordered]@{
        schemaVersion = 1
        requestId = ($Label + '-preflight')
        command = 'RunPreflight'
        arguments = [ordered]@{ buildPlan=(New-SmokePlan -CacheDirectory $cache -OutputDirectory $output); onlineChecks=$false }
    }
    [IO.File]::WriteAllText($preRequestPath, ($preRequest | ConvertTo-Json -Depth 30), $utf8NoBom)
    Invoke-ChildPowerShell -Executable $Executable -Arguments @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$entry,
        '-RequestFile',$preRequestPath,'-ResponseFile',$preResponsePath
    )
    $preResponse = [IO.File]::ReadAllText($preResponsePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not [bool]$preResponse.success) { throw 'Offline RunPreflight returned success=false.' }
    if ($null -eq $preResponse.data.PSObject.Properties['ready']) { throw 'Preflight response missing ready.' }
    if (@($preResponse.data.checks).Count -eq 0) { throw 'Preflight response contains no checks.' }

    return [ordered]@{ getVersion='pass'; offlinePreflight='pass'; eventLines=$eventLines.Count; ready=[bool]$preResponse.data.ready }
}

function Get-ZipLogicalFiles {
    param([string]$ZipPath, [string]$ExpectedRootName)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $prefix = $ExpectedRootName + '/'
        $result = @()
        foreach ($entry in @($archive.Entries)) {
            $name = ([string]$entry.FullName).Replace('\','/')
            if ([string]::IsNullOrWhiteSpace($name) -or $name.EndsWith('/')) { continue }
            if (-not $name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw ('ZIP entry outside package root: {0}' -f $name)
            }
            $result += $name.Substring($prefix.Length).Replace('/','\')
        }
        return @($result | Sort-Object -Unique)
    }
    finally { $archive.Dispose() }
}

function Invoke-PackageSmoke {
    param([string]$ZipPath, [string]$PowerShellExe)
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw 'Release ZIP does not exist.' }
    $checksumPath = "$ZipPath.sha256"
    if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) { throw 'Release checksum does not exist.' }

    $checksumText = [IO.File]::ReadAllText($checksumPath, [Text.Encoding]::UTF8).Trim()
    if ($checksumText -notmatch '^([A-Fa-f0-9]{64})\s+') { throw 'Checksum file format is invalid.' }
    $expectedHash = $matches[1].ToUpperInvariant()
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash.ToUpperInvariant()
    if ($expectedHash -ne $actualHash) { throw 'Release checksum mismatch.' }

    $rootName = 'windows-iso-builder-v{0}' -f $version
    $actualFiles = @(Get-ZipLogicalFiles -ZipPath $ZipPath -ExpectedRootName $rootName)
    $expectedFiles = @(Get-WibReleaseSourceFiles -ProjectRoot $projectRoot -Config $config -Version $version | ForEach-Object { $_.RelativePath })
    $expectedFiles = @($expectedFiles + 'release-manifest.json' | Sort-Object -Unique)
    if ($actualFiles.Count -ne $expectedFiles.Count) { throw 'ZIP logical file count does not match release allowlist.' }
    foreach ($path in $expectedFiles) {
        if ($actualFiles -notcontains $path) { throw ('ZIP missing expected file: {0}' -f $path) }
    }
    foreach ($path in $actualFiles) {
        if ($expectedFiles -notcontains $path) { throw ('ZIP contains unexpected file: {0}' -f $path) }
        if (Test-WibReleaseRelativePathDenied -RelativePath $path -Config $config) { throw ('ZIP contains denied file: {0}' -f $path) }
    }

    $extractRoot = Join-Path $workRoot ('package-' + [Guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractRoot -Force
    $packageRoot = Join-Path $extractRoot $rootName
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) { throw 'Extracted package root is missing.' }

    foreach ($required in @($config.RequiredPackageFiles)) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot ([string]$required)) -PathType Leaf)) {
            throw ('Package missing required file: {0}' -f $required)
        }
    }

    $releaseManifest = [IO.File]::ReadAllText((Join-Path $packageRoot 'release-manifest.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$releaseManifest.applicationVersion -ne $version) { throw 'release-manifest applicationVersion mismatch.' }
    if ([string]$releaseManifest.moduleVersion -ne $moduleVersion) { throw 'release-manifest moduleVersion mismatch.' }
    if ([int]$releaseManifest.backendContractSchemaVersion -ne 1) { throw 'release-manifest Backend Contract schema mismatch.' }
    if ([int]$releaseManifest.buildPlanSchemaVersion -ne 1) { throw 'release-manifest BuildPlan schema mismatch.' }

    Assert-ScriptSyntax -Path (Join-Path $packageRoot 'Start-Builder.ps1')
    $packageFindings = @(Get-WibReleaseSafetyFindings -Files (Get-WibFilesUnderRoot -Root $packageRoot) -Config $config)
    if ($packageFindings.Count -gt 0) { throw ('Package safety scan found {0} issue(s).' -f $packageFindings.Count) }

    Invoke-ModuleImportSmoke -Executable $PowerShellExe -Root $packageRoot -Label 'package-ps51' | Out-Null
    $backend = Invoke-BackendSmoke -Executable $PowerShellExe -Root $packageRoot -Label 'package-ps51'
    return [ordered]@{ checksum='pass'; logicalFiles=$actualFiles.Count; manifest='pass'; safety='pass'; backend=$backend }
}

try {
    Write-Host ('Windows ISO Builder {0}' -f $version)
    Write-Host ('Validation mode: {0}' -f $mode)
    Write-Host ''

    Invoke-RequiredCheck -Id 'version-and-schema' -Required $true -Action {
        if ($version -ne '0.2.3-alpha.1') { throw ('VERSION is {0}; expected 0.2.3-alpha.1.' -f $version) }
        if ($moduleVersion -ne '0.2.3') { throw ('ModuleVersion is {0}; expected 0.2.3.' -f $moduleVersion) }
        if ([int]$manifestData.backendContractSchemaVersion -ne 1) { throw 'Backend Contract SchemaVersion must remain 1.' }
        if ([int]$manifestData.buildPlanSchemaVersion -ne 1) { throw 'BuildPlan SchemaVersion must remain 1.' }
        [ordered]@{ applicationVersion=$version; moduleVersion=$moduleVersion; backendContractSchemaVersion=1; buildPlanSchemaVersion=1 }
    }

    Invoke-RequiredCheck -Id 'release-file-manifest' -Required $true -Action {
        $releaseFiles = @(Get-WibReleaseSourceFiles -ProjectRoot $projectRoot -Config $config -Version $version)
        foreach ($file in $releaseFiles) {
            if (Test-WibReleaseRelativePathDenied -RelativePath $file.RelativePath -Config $config) {
                throw ('Release allowlist contains denied path: {0}' -f $file.RelativePath)
            }
        }
        [ordered]@{ files=$releaseFiles.Count; configSchema=[int]$config.SchemaVersion }
    }

    Invoke-RequiredCheck -Id 'powershell-syntax' -Required $true -Action {
        foreach ($relative in @('Start-Builder.ps1','Invoke-WibBackend.ps1','tools\New-ReleasePackage.ps1','tools\Invoke-ReleaseValidation.ps1','tools\ReleaseValidation.Common.ps1')) {
            Assert-ScriptSyntax -Path (Join-Path $projectRoot $relative)
        }
        [ordered]@{ parsed=5 }
    }

    Invoke-RequiredCheck -Id 'current-tree-safety-scan' -Required $true -Action {
        $treeFiles = @(Get-WibCurrentTreeFiles -ProjectRoot $projectRoot)
        $findings = @(Get-WibReleaseSafetyFindings -Files $treeFiles -Config $config -SkipDenyPathCheck)
        if ($findings.Count -gt 0) {
            $paths = @($findings | ForEach-Object { $_.path } | Sort-Object -Unique)
            throw ('Current tracked-tree safety scan found {0} issue(s): {1}' -f $findings.Count, ($paths -join ', '))
        }
        [ordered]@{ filesScanned=$treeFiles.Count; findings=0; scope='current tracked tree; not Git history' }
    }

    $psCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    $ps51 = if ($null -eq $psCommand) { '' } else { [string]$psCommand.Source }
    if ([string]::IsNullOrWhiteSpace($ps51)) {
        Add-ValidationResult -Id 'powershell-5.1-runtime' -Status fail -Required $true -Message 'powershell.exe is not available.'
    }
    else {
        Invoke-RequiredCheck -Id 'module-import-ps5.1' -Required $true -Action {
            Invoke-ModuleImportSmoke -Executable $ps51 -Root $projectRoot -Label 'source-ps51'
        }
        Invoke-RequiredCheck -Id 'backend-json-events-preflight-ps5.1' -Required $true -Action {
            Invoke-BackendSmoke -Executable $ps51 -Root $projectRoot -Label 'source-ps51'
        }
        Invoke-RequiredCheck -Id 'pester' -Required $true -Action {
            Invoke-ChildPowerShell -Executable $ps51 -Arguments @(
                '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $projectRoot 'tests\Run-Tests.ps1')
            )
            [ordered]@{ exitCode=0; runner='tests/Run-Tests.ps1' }
        }
    }

    $analyzerModule = Get-Module -ListAvailable -Name PSScriptAnalyzer | Select-Object -First 1
    if ($null -eq $analyzerModule) {
        if ($Full) {
            Add-ValidationResult -Id 'psscriptanalyzer' -Status fail -Required $true -Message 'PSScriptAnalyzer is not installed.'
        }
        else {
            Add-ValidationResult -Id 'psscriptanalyzer' -Status skipped -Required $false -Message 'PSScriptAnalyzer is not installed; Quick mode permits skip.'
        }
    }
    else {
        Invoke-RequiredCheck -Id 'psscriptanalyzer' -Required $true -Action {
            Import-Module PSScriptAnalyzer -ErrorAction Stop
            $issues = @(Invoke-ScriptAnalyzer -Path $projectRoot -Recurse -Settings (Join-Path $projectRoot '.psscriptanalyzer.psd1'))
            if ($issues.Count -gt 0) { throw ('PSScriptAnalyzer reported {0} issue(s).' -f $issues.Count) }
            [ordered]@{ issues=0; moduleVersion=[string]$analyzerModule.Version }
        }
    }

    if ($withPs7) {
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($null -eq $pwsh) {
            Add-ValidationResult -Id 'backend-smoke-ps7' -Status skipped -Required $false -Message 'PowerShell 7 is not installed.'
        }
        else {
            Invoke-RequiredCheck -Id 'backend-smoke-ps7' -Required $true -Action {
                Invoke-BackendSmoke -Executable ([string]$pwsh.Source) -Root $projectRoot -Label 'source-ps7'
            }
        }
    }
    else {
        Add-ValidationResult -Id 'backend-smoke-ps7' -Status skipped -Required $false -Message 'Not requested in Quick mode.'
    }

    if ($withProcessSmoke) {
        if ([string]::IsNullOrWhiteSpace($ps51)) {
            Add-ValidationResult -Id 'process-tree-smoke' -Status fail -Required $true -Message 'PS5.1 is unavailable.'
        }
        else {
            Invoke-RequiredCheck -Id 'process-tree-smoke' -Required $true -Action {
                $runner = Join-Path $workRoot 'process-tree-smoke.ps1'
                $runnerSource = @'
param([string]$TestPath)
$ErrorActionPreference='Stop'
if(-not (Get-Module -ListAvailable -Name Pester)){throw 'Pester is not installed.'}
$env:WIB_RUN_PROCESS_CANCELLATION_SMOKE='1'
$r=Invoke-Pester -Path $TestPath -Output Detailed -PassThru
if([int]$r.FailedCount -gt 0){exit 1}
exit 0
'@
                [IO.File]::WriteAllText($runner, $runnerSource, [Text.Encoding]::ASCII)
                Invoke-ChildPowerShell -Executable $ps51 -Arguments @(
                    '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,
                    '-TestPath',(Join-Path $projectRoot 'tests\ProcessCancellation.Smoke.Tests.ps1')
                )
                [ordered]@{ controlledDummyTree='pass'; realUupDownload=$false }
            }
        }
    }
    else {
        Add-ValidationResult -Id 'process-tree-smoke' -Status skipped -Required $false -Message 'Not requested in Quick mode.'
    }

    if ($withPackage) {
        if ([string]::IsNullOrWhiteSpace($ps51)) {
            Add-ValidationResult -Id 'release-package-smoke' -Status fail -Required $true -Message 'PS5.1 is unavailable.'
        }
        else {
            Invoke-RequiredCheck -Id 'release-package-smoke' -Required $true -Action {
                $zip = $PackagePath
                if ([string]::IsNullOrWhiteSpace($zip)) {
                    $packageOutput = Join-Path $workRoot 'dist'
                    [IO.Directory]::CreateDirectory($packageOutput) | Out-Null
                    Invoke-ChildPowerShell -Executable $ps51 -Arguments @(
                        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $projectRoot 'tools\New-ReleasePackage.ps1'),
                        '-OutputDirectory',$packageOutput
                    )
                    $zip = Join-Path $packageOutput ('windows-iso-builder-v{0}.zip' -f $version)
                }
                else { $zip = [IO.Path]::GetFullPath($zip) }
                Invoke-PackageSmoke -ZipPath $zip -PowerShellExe $ps51
            }
        }
    }
    else {
        Add-ValidationResult -Id 'release-package-smoke' -Status skipped -Required $false -Message 'Use -Full or -IncludePackageSmoke.'
    }

    $required = @($checks | Where-Object { $_.required })
    $optional = @($checks | Where-Object { -not $_.required })
    $requiredPassed = @($required | Where-Object status -eq 'pass').Count
    $requiredFailed = @($required | Where-Object status -eq 'fail').Count
    $optionalPassed = @($optional | Where-Object status -eq 'pass').Count
    $optionalFailed = @($optional | Where-Object status -eq 'fail').Count
    $optionalSkipped = @($optional | Where-Object status -eq 'skipped').Count
    $success = ($requiredFailed -eq 0)

    $report = [ordered]@{
        applicationVersion = $version
        moduleVersion = $moduleVersion
        backendContractSchemaVersion = [int]$manifestData.backendContractSchemaVersion
        buildPlanSchemaVersion = [int]$manifestData.buildPlanSchemaVersion
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        mode = $mode
        success = $success
        checks = @($checks)
        summary = [ordered]@{
            requiredPassed=$requiredPassed
            requiredFailed=$requiredFailed
            optionalPassed=$optionalPassed
            optionalFailed=$optionalFailed
            optionalSkipped=$optionalSkipped
        }
    }
    $reportDir = Split-Path -Parent $ReportPath
    if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) { [IO.Directory]::CreateDirectory($reportDir) | Out-Null }
    [IO.File]::WriteAllText($ReportPath, (($report | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8NoBom)

    Write-Host ''
    Write-Host ('Required: {0} passed, {1} failed' -f $requiredPassed, $requiredFailed)
    Write-Host ('Optional: {0} passed, {1} failed, {2} skipped' -f $optionalPassed, $optionalFailed, $optionalSkipped)
    Write-Host ('Report: {0}' -f (Protect-ValidationText $ReportPath))
    if ($success) {
        Write-Host 'Validation: PASS'
        exit 0
    }
    Write-Host 'Validation: FAIL'
    Write-Host ('{0} required checks failed' -f $requiredFailed)
    exit 1
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}
