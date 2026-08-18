function Get-WibResponsePreview {
    param([Parameter(Mandatory = $true)][string]$Path, [int]$MaximumCharacters = 600)
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -eq 0) { return '<пустой ответ>' }
        $count = [Math]::Min($bytes.Length, 16384)
        $text = [Text.Encoding]::UTF8.GetString($bytes, 0, $count)
        $text = [regex]::Replace($text, '(?is)<script.*?</script>', ' ')
        $text = [regex]::Replace($text, '(?is)<style.*?</style>', ' ')
        $text = [regex]::Replace($text, '(?s)<[^>]+>', ' ')
        $text = [Net.WebUtility]::HtmlDecode($text)
        $text = [regex]::Replace($text, '\s+', ' ').Trim()
        if ($text.Length -gt $MaximumCharacters) { $text = $text.Substring(0, $MaximumCharacters) + '...' }
        return $text
    }
    catch { return '<не удалось прочитать ответ>' }
}

function Test-WibUupPackageArchive {
    param([Parameter(Mandatory = $true)][string]$Path)
    $archive = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($Path)
        $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        $required = @('uup_download_windows.cmd', 'ConvertConfig.ini')
        $missing = @($required | Where-Object { $name = $_; -not ($entries | Where-Object { $_ -eq $name -or $_.EndsWith('/' + $name) }) })
        if ($missing.Count -gt 0) { return [pscustomobject]@{ IsValid=$false; Reason=('В ZIP отсутствуют: {0}' -f ($missing -join ', ')); Entries=$entries } }
        return [pscustomobject]@{ IsValid=$true; Reason=''; Entries=$entries }
    }
    catch { return [pscustomobject]@{ IsValid=$false; Reason=$_.Exception.Message; Entries=@() } }
    finally { if ($null -ne $archive) { $archive.Dispose() } }
}

function Download-WibUupPackage {
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)][string]$DestinationZip, [int]$Attempts = 3)

    Assert-WibNotCancelled -Stage 'download'
    if (Test-Path -LiteralPath $DestinationZip) {
        $existing = Test-WibUupPackageArchive -Path $DestinationZip
        if ($existing.IsValid) { Write-WibInfo ('Используется кешированный пакет UUP dump: {0}' -f $DestinationZip); return }
        Remove-Item -LiteralPath $DestinationZip -Force
    }

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
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    for ($attempt=1; $attempt -le $Attempts; $attempt++) {
        Assert-WibNotCancelled -Stage 'download'
        Remove-Item -LiteralPath $DestinationZip -Force -ErrorAction SilentlyContinue
        Write-WibInfo ('Загрузка служебного пакета UUP dump, попытка {0}/{1}' -f $attempt, $Attempts)
        try {
            $userAgent = 'Mozilla/5.0 WindowsISOBuilder/{0}' -f $script:WibApplicationVersion
            Invoke-WebRequest -Method Post -Uri $uri -Body $body -OutFile $DestinationZip -UseBasicParsing -TimeoutSec 300 -UserAgent $userAgent | Out-Null
        }
        catch {
            $lastReason = $_.Exception.Message
            if ($attempt -lt $Attempts) {
                Wait-WibCancellableDelay -Seconds (5 * $attempt) -Stage 'download'
                continue
            }
            $message = 'Не удалось загрузить пакет UUP dump.'
            throw (New-WibErrorException -Code 'UUP_PACKAGE_DOWNLOAD_FAILED' -Message ("$message $lastReason") -Stage 'download' -PublicMessage $message -Details ([ordered]@{ attempts=$Attempts }))
        }

        Assert-WibNotCancelled -Stage 'download'
        $validation = Test-WibUupPackageArchive -Path $DestinationZip
        if ($validation.IsValid) { Write-WibInfo ('Получен корректный пакет: {0} байт.' -f (Get-Item -LiteralPath $DestinationZip).Length); return }
        $lastReason = $validation.Reason
        Remove-Item -LiteralPath $invalidPath -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $DestinationZip -Destination $invalidPath -Force
        if ($attempt -lt $Attempts) { Wait-WibCancellableDelay -Seconds (5 * $attempt) -Stage 'download' }
    }

    $preview = Get-WibResponsePreview -Path $invalidPath
    $internal = 'UUP dump не вернул корректный ZIP. Причина: {0}. Ответ: {1}' -f $lastReason, $preview
    throw (New-WibErrorException -Code 'UUP_PACKAGE_INVALID' -Message $internal -Stage 'download' -PublicMessage 'UUP dump returned an invalid conversion package.')
}

function Set-WibConverterConfiguration {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Plan)
    $virtualEditions = @($Plan.VirtualEditions)
    Set-WibIniValue -Path $Path -Name 'AutoStart' -Value '1'
    Set-WibIniValue -Path $Path -Name 'AutoExit' -Value '1'
    Set-WibIniValue -Path $Path -Name 'AddUpdates' -Value $(if ([bool]$Plan.AddUpdates) { '1' } else { '0' })
    Set-WibIniValue -Path $Path -Name 'Cleanup' -Value $(if ([bool]$Plan.Cleanup) { '1' } else { '0' })
    Set-WibIniValue -Path $Path -Name 'NetFx3' -Value $(if ([bool]$Plan.NetFx3) { '1' } else { '0' })
    Set-WibIniValue -Path $Path -Name 'SkipWinRE' -Value '0'
    Set-WibIniValue -Path $Path -Name 'wim2esd' -Value $(if ([string]$Plan.ImageFormat -eq 'ESD') { '1' } else { '0' })
    Set-WibIniValue -Path $Path -Name 'StartVirtual' -Value $(if ($virtualEditions.Count -gt 0) { '1' } else { '0' })
    if ($virtualEditions.Count -gt 0) {
        Set-WibIniValue -Path $Path -Name 'vAutoStart' -Value '1'
        Set-WibIniValue -Path $Path -Name 'vAutoEditions' -Value ($virtualEditions -join ',')
        Set-WibIniValue -Path $Path -Name 'vwim2esd' -Value $(if ([string]$Plan.ImageFormat -eq 'ESD') { '1' } else { '0' })
    }
}

function Invoke-WibUupDownloadScript {
    param([Parameter(Mandatory = $true)][string]$PackageDirectory, [Parameter(Mandatory = $true)][string]$ScriptName)

    $commandProcessor = $env:ComSpec
    if ([string]::IsNullOrWhiteSpace($commandProcessor)) {
        $command = Get-Command cmd.exe -ErrorAction SilentlyContinue
        if ($command) { $commandProcessor = $command.Source }
    }
    if ([string]::IsNullOrWhiteSpace($commandProcessor)) {
        throw (New-WibErrorException -Code 'REQUIRED_COMPONENT_MISSING' -Message 'cmd.exe is unavailable.' -Stage 'download' -Details ([ordered]@{ component='cmd.exe' }))
    }

    $safeScriptName = $ScriptName.Replace('"', '""')
    $arguments = '/D /C call "{0}"' -f $safeScriptName
    $lineHandler = { param($line) Write-Host $line }
    $stageProvider = {
        if (Get-Command Get-WibConverterCurrentStage -ErrorAction SilentlyContinue) { return (Get-WibConverterCurrentStage) }
        return 'download'
    }
    try {
        $result = Invoke-WibManagedProcess -FilePath $commandProcessor -ArgumentList $arguments -WorkingDirectory $PackageDirectory -Stage 'download' -LineHandler $lineHandler -StageProvider $stageProvider
    }
    catch {
        $knownCode = ''
        try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
        if (-not [string]::IsNullOrWhiteSpace($knownCode)) { throw }
        throw (New-WibErrorException -Code 'DOWNLOAD_FAILED' -Message ('Unable to start or monitor the UUP download/conversion process: {0}' -f $_.Exception.Message) -Stage 'download' -PublicMessage 'The UUP download process could not be started or monitored.')
    }
    return [int]$result.ExitCode
}

function Get-WibIsoMetadata {
    param([Parameter(Mandatory = $true)][string]$IsoPath)
    $result = [ordered]@{ Mounted=$false; HasBootWim=$false; HasInstallWim=$false; HasInstallEsd=$false; Images=@(); Warning='' }
    if (-not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) {
        $result.Warning='Mount-DiskImage недоступен; внутреннее содержимое ISO не проверено.'
        return [pscustomobject]$result
    }

    $diskImage = $null
    try {
        try {
            $diskImage = Mount-DiskImage -ImagePath $IsoPath -PassThru
            $volume = $diskImage | Get-Volume
            if (-not $volume.DriveLetter) { throw 'ISO mounted without a drive letter.' }
        }
        catch {
            $result.Warning = $_.Exception.Message
            return [pscustomobject]$result
        }

        $result.Mounted = $true
        $sources = '{0}:\sources' -f $volume.DriveLetter
        $bootWim=Join-Path $sources 'boot.wim'; $installWim=Join-Path $sources 'install.wim'; $installEsd=Join-Path $sources 'install.esd'
        $result.HasBootWim=Test-Path -LiteralPath $bootWim; $result.HasInstallWim=Test-Path -LiteralPath $installWim; $result.HasInstallEsd=Test-Path -LiteralPath $installEsd
        $imagePath = if ($result.HasInstallWim) { $installWim } elseif ($result.HasInstallEsd) { $installEsd } else { $null }
        if ($imagePath -and (Get-Command Get-WindowsImage -ErrorAction SilentlyContinue)) {
            try {
                $images = foreach ($image in Get-WindowsImage -ImagePath $imagePath) {
                    $detail = Get-WindowsImage -ImagePath $imagePath -Index $image.ImageIndex
                    [pscustomobject]@{ Index=$detail.ImageIndex; Name=$detail.ImageName; Description=$detail.ImageDescription; Version=[string]$detail.Version; Architecture=[string]$detail.Architecture }
                }
                $result.Images = @($images)
            }
            catch {
                throw (New-WibErrorException -Code 'DISM_FAILED' -Message ('DISM image inspection failed: {0}' -f $_.Exception.Message) -Stage 'verify' -PublicMessage 'DISM could not inspect the generated ISO.' )
            }
        }
        return [pscustomobject]$result
    }
    finally {
        if ($null -ne $diskImage) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
    }
}

function Invoke-WibBuildPlanCore {
    param([Parameter(Mandatory = $true)]$Plan)

    Assert-WibPlan -Plan $Plan
    Assert-WibNotCancelled -Stage 'preflight'
    $authoritativePreflight = Invoke-WibPreflight -Plan $Plan -OnlineChecks:$false
    Assert-WibPreflightReady -Report $authoritativePreflight
    Assert-WibNotCancelled -Stage 'preflight'

    $outputDirectory = Resolve-WibFullPath -Path ([string]$Plan.OutputDirectory) -Create
    $cacheDirectory = Resolve-WibFullPath -Path ([string]$Plan.CacheDirectory) -Create
    $logsDirectory = Join-Path $outputDirectory 'logs'
    New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null
    $logPath = Join-Path $logsDirectory ('build-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $converterLogPath = Join-Path $logsDirectory (([IO.Path]::GetFileName($logPath)) -replace '^build-', 'converter-')
    $transcriptStarted = $false
    $jobKey = '{0}-{1}-{2}' -f $Plan.Build.Uuid, $Plan.Language, $Plan.SourceEdition
    $jobHash = (Get-WibSha256Text -Text $jobKey).Substring(0, 16)
    $workDirectory = Join-Path (Join-Path $cacheDirectory 'work') $jobHash
    $packagesDirectory = Join-Path $cacheDirectory 'packages'
    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $packagesDirectory -Force | Out-Null
    $packageZip = Join-Path $packagesDirectory ("$jobHash.zip")
    $statePath = Join-Path $workDirectory 'state.json'

    try {
        Start-Transcript -LiteralPath $logPath -Force | Out-Null
        $transcriptStarted = $true
        Write-WibStage 'План сборки'
        Write-Host ('Сборка:      {0}' -f $Plan.Build.Title)
        Write-Host ('Номер:       {0}' -f $Plan.Build.Build)
        Write-Host ('Архитектура: {0}' -f $Plan.Build.Architecture)
        Write-Host ('Язык:        {0}' -f $Plan.Language)
        Write-Host ('Редакции:    {0}' -f (@($Plan.Editions) -join ', '))
        Write-Host ('Формат:      install.{0}' -f ([string]$Plan.ImageFormat).ToLowerInvariant())
        Write-Host ('Результат:   {0}' -f $outputDirectory)
        Write-Host ('Кеш:         {0}' -f $cacheDirectory)
        Write-Host ('Лог:         {0}' -f $logPath)

        Assert-WibNotCancelled -Stage 'download'
        Save-WibJobState -Path $statePath -Stage 'downloading-package' -Plan $Plan
        Write-WibStage 'Получение пакета UUP dump'
        Download-WibUupPackage -Plan $Plan -DestinationZip $packageZip
        Assert-WibNotCancelled -Stage 'download'

        $downloadScript = Get-ChildItem -LiteralPath $workDirectory -Filter 'uup_download_windows.cmd' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $downloadScript) {
            Write-WibInfo 'Распаковка пакета конвертации...'
            Assert-WibNotCancelled -Stage 'download'
            try { Expand-Archive -LiteralPath $packageZip -DestinationPath $workDirectory -Force }
            catch {
                throw (New-WibErrorException -Code 'UUP_PACKAGE_INVALID' -Message ('Conversion package extraction failed: {0}' -f $_.Exception.Message) -Stage 'download' -PublicMessage 'The UUP conversion package could not be extracted.')
            }
            Assert-WibNotCancelled -Stage 'download'
            $downloadScript=Get-ChildItem -LiteralPath $workDirectory -Filter 'uup_download_windows.cmd' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if (-not $downloadScript) { throw (New-WibErrorException -Code 'UUP_PACKAGE_INVALID' -Message 'uup_download_windows.cmd is missing from the UUP package.' -Stage 'download') }
        $packageDirectory=$downloadScript.Directory.FullName
        $configPath=Join-Path $packageDirectory 'ConvertConfig.ini'
        if (-not (Test-Path -LiteralPath $configPath)) { throw (New-WibErrorException -Code 'UUP_PACKAGE_INVALID' -Message 'ConvertConfig.ini is missing from the UUP package.' -Stage 'download') }
        Set-WibConverterConfiguration -Path $configPath -Plan $Plan

        Get-ChildItem -LiteralPath $workDirectory -Filter '*.iso' -File -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Assert-WibNotCancelled -Stage 'download'
        Save-WibJobState -Path $statePath -Stage 'downloading-uup-and-converting' -Plan $Plan
        Write-WibStage 'Загрузка файлов Microsoft и создание ISO'
        Write-WibInfo 'aria2 продолжит неполные загрузки из сохранённого рабочего каталога.'
        $exitCode=Invoke-WibUupDownloadScript -PackageDirectory $packageDirectory -ScriptName $downloadScript.Name
        if ($exitCode -ne 0) {
            throw (New-WibErrorException -Code 'CONVERTER_FAILED' -Message ('uup_download_windows.cmd exited with code {0}. Detailed log: {1}' -f $exitCode, $converterLogPath) -Stage 'convert' -PublicMessage 'UUP converter failed.' -LogPath $logPath -WorkDirectory $workDirectory -Details ([ordered]@{ exitCode=$exitCode }))
        }

        Assert-WibNotCancelled -Stage 'convert'
        $iso=Get-ChildItem -LiteralPath $workDirectory -Filter '*.iso' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $iso) {
            throw (New-WibErrorException -Code 'ISO_NOT_FOUND' -Message ('Converter completed but no ISO was found in {0}. Detailed log: {1}' -f $workDirectory, $converterLogPath) -Stage 'convert' -PublicMessage 'Converter completed without producing an ISO.' -LogPath $logPath -WorkDirectory $workDirectory)
        }
        if ($iso.Length -lt 1GB) {
            throw (New-WibErrorException -Code 'ISO_VALIDATION_FAILED' -Message ('Generated ISO is suspiciously small: {0} bytes.' -f $iso.Length) -Stage 'verify' -PublicMessage 'Generated ISO failed size validation.' -Details ([ordered]@{ path=$iso.FullName; actualBytes=[int64]$iso.Length; minimumBytes=[int64](1GB) }))
        }

        $editionPart=ConvertTo-WibSafeFilePart -Value (@($Plan.Editions) -join '+')
        $versionPart=if ([string]::IsNullOrWhiteSpace([string]$Plan.Build.VersionLabel)) { 'build' } else { [string]$Plan.Build.VersionLabel }
        $fileName='{0}_{1}_{2}_{3}_{4}_{5}.iso' -f (ConvertTo-WibSafeFilePart -Value ([string]$Plan.Build.Product)),(ConvertTo-WibSafeFilePart -Value $versionPart),(ConvertTo-WibSafeFilePart -Value ([string]$Plan.Build.Build)),(ConvertTo-WibSafeFilePart -Value ([string]$Plan.Language)),(ConvertTo-WibSafeFilePart -Value ([string]$Plan.Build.Architecture)),$editionPart
        $destinationIso=Join-Path $outputDirectory $fileName
        Move-Item -LiteralPath $iso.FullName -Destination $destinationIso -Force

        Assert-WibNotCancelled -Stage 'verify'
        Save-WibJobState -Path $statePath -Stage 'validating' -Plan $Plan
        Write-WibStage 'Проверка результата'
        try {
            $hash=(Get-FileHash -LiteralPath $destinationIso -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        catch {
            throw (New-WibErrorException -Code 'ISO_VALIDATION_FAILED' -Message ('ISO hashing failed: {0}' -f $_.Exception.Message) -Stage 'verify' -PublicMessage 'Generated ISO could not be hashed.')
        }
        [IO.File]::WriteAllText("$destinationIso.sha256.txt", "$hash  $fileName`r`n", [Text.Encoding]::ASCII)
        $isoMetadata=Get-WibIsoMetadata -IsoPath $destinationIso
        if ($isoMetadata.Warning) { Write-WibWarning $isoMetadata.Warning }
        if ($isoMetadata.Mounted -and (-not $isoMetadata.HasBootWim -or (-not $isoMetadata.HasInstallWim -and -not $isoMetadata.HasInstallEsd))) {
            throw (New-WibErrorException -Code 'ISO_VALIDATION_FAILED' -Message 'Generated ISO is missing boot.wim or install.wim/install.esd.' -Stage 'verify' -PublicMessage 'Generated ISO failed structure validation.')
        }

        $metadata=[ordered]@{ applicationVersion=$script:WibApplicationVersion; createdAt=(Get-Date).ToString('o'); source='Microsoft Windows Update/CDN via UUP dump generated conversion package'; uupUpdateId=[string]$Plan.Build.Uuid; uupUpdateName=[string]$Plan.Build.Title; product=[string]$Plan.Build.Product; versionLabel=[string]$Plan.Build.VersionLabel; build=[string]$Plan.Build.Build; architecture=[string]$Plan.Build.Architecture; language=[string]$Plan.Language; editions=@($Plan.Editions); sourceEdition=[string]$Plan.SourceEdition; virtualEditions=@($Plan.VirtualEditions); imageFormat=[string]$Plan.ImageFormat; addUpdates=[bool]$Plan.AddUpdates; cleanup=[bool]$Plan.Cleanup; netFx3=[bool]$Plan.NetFx3; sha256=$hash; bytes=(Get-Item -LiteralPath $destinationIso).Length; isoValidation=$isoMetadata }
        Write-WibJsonFile -Value $metadata -Path "$destinationIso.json" -Depth 20
        Assert-WibNotCancelled -Stage 'verify'
        Save-WibJobState -Path $statePath -Stage 'completed' -Plan $Plan -Message $destinationIso
        Write-Host ''
        Write-Host ('Готово: {0}' -f $destinationIso) -ForegroundColor Green
        Write-Host ('SHA-256: {0}' -f $hash)
        Write-Host ('Лог: {0}' -f $logPath)
        if ([bool]$Plan.RemoveWorkAfterSuccess) { Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue }
        return [pscustomobject]@{ IsoPath=$destinationIso; Sha256=$hash; LogPath=$logPath; MetadataPath="$destinationIso.json" }
    }
    catch {
        $failure = $_
        $errorCode = ''
        try { if ($failure.Exception.Data.Contains('WibErrorCode')) { $errorCode=[string]$failure.Exception.Data['WibErrorCode'] } } catch { }
        if ($errorCode -eq 'BUILD_CANCELLED') {
            try { Save-WibJobState -Path $statePath -Stage 'cancelled' -Plan $Plan -Message $failure.Exception.Message } catch { }
            Write-Host ''
            Write-Host ('СБОРКА ОТМЕНЕНА: {0}' -f $failure.Exception.Message) -ForegroundColor Yellow
            Write-Host ('Рабочий каталог сохранён для продолжения: {0}' -f $workDirectory)
            Write-Host ('Лог: {0}' -f $logPath)
        }
        else {
            try { Save-WibJobState -Path $statePath -Stage 'failed' -Plan $Plan -Message $failure.Exception.Message } catch { }
            Write-Host ''
            Write-Host ('ОШИБКА СБОРКИ: {0}' -f $failure.Exception.Message) -ForegroundColor Red
            Write-Host ('Рабочий каталог сохранён для продолжения: {0}' -f $workDirectory)
            Write-Host ('Лог: {0}' -f $logPath)
        }
        throw $failure
    }
    finally { if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch { } } }
}

function Invoke-WibBuildPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan)

    Assert-WibPlan -Plan $Plan
    Assert-WibNotCancelled -Stage 'preflight'
    $preflight = Invoke-WibPreflight -Plan $Plan -OnlineChecks:$false
    Show-WibPreflightSummary -Report $preflight
    Assert-WibPreflightReady -Report $preflight
    Assert-WibNotCancelled -Stage 'preflight'

    if ($env:OS -eq 'Windows_NT' -and -not (Test-WibAdministrator)) {
        Assert-WibNotCancelled -Stage 'preflight'
        $result = Start-WibElevatedPlan -Plan $Plan
        Assert-WibNotCancelled -Stage 'verify'
        return $result
    }
    return Invoke-WibBuildPlanCore -Plan $Plan
}

function Invoke-WibPlanFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $plan=Read-WibPlan -Path $Path
    Invoke-WibBuildPlan -Plan $plan
}
