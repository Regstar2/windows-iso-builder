function Assert-WibHostRequirements {
    if ($env:OS -ne 'Windows_NT') {
        throw 'Сборка ISO поддерживается только в Windows 10 и Windows 11.'
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'Для сборки требуется 64-разрядная Windows.'
    }
    foreach ($command in @('dism.exe', 'Expand-Archive', 'Get-FileHash')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Не найден обязательный компонент: $command"
        }
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Get-WibResponsePreview {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaximumCharacters = 600
    )

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
    catch {
        return "<не удалось прочитать ответ: $($_.Exception.Message)>"
    }
}

function Test-WibUupPackageArchive {
    param([Parameter(Mandatory = $true)][string]$Path)

    $archive = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($Path)
        $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        $required = @('uup_download_windows.cmd', 'ConvertConfig.ini')
        $missing = @($required | Where-Object {
            $name = $_
            -not ($entries | Where-Object { $_ -eq $name -or $_.EndsWith('/' + $name) })
        })
        if ($missing.Count -gt 0) {
            return [pscustomobject]@{ IsValid = $false; Reason = "В ZIP отсутствуют: $($missing -join ', ')"; Entries = $entries }
        }
        return [pscustomobject]@{ IsValid = $true; Reason = ''; Entries = $entries }
    }
    catch {
        return [pscustomobject]@{ IsValid = $false; Reason = $_.Exception.Message; Entries = @() }
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
    }
}

function Download-WibUupPackage {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$DestinationZip,
        [int]$Attempts = 3
    )

    if (Test-Path -LiteralPath $DestinationZip) {
        $existing = Test-WibUupPackageArchive -Path $DestinationZip
        if ($existing.IsValid) {
            Write-WibInfo "Используется кешированный пакет UUP dump: $DestinationZip"
            return
        }
        Remove-Item -LiteralPath $DestinationZip -Force
    }

    $query = ConvertTo-WibQueryString -Parameters @{
        id      = [string]$Plan.Build.Uuid
        pack    = [string]$Plan.Language
        edition = [string]$Plan.SourceEdition
    }
    $uri = '{0}/get.php?{1}' -f $script:UupWebsiteBaseUri, $query
    $body = @{
        autodl  = 2
        updates = if ([bool]$Plan.AddUpdates) { 1 } else { 0 }
        cleanup = if ([bool]$Plan.Cleanup) { 1 } else { 0 }
        netfx   = if ([bool]$Plan.NetFx3) { 1 } else { 0 }
        esd     = if ([string]$Plan.ImageFormat -eq 'ESD') { 1 } else { 0 }
    }

    $invalidPath = "$DestinationZip.response.html"
    $lastReason = ''
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Remove-Item -LiteralPath $DestinationZip -Force -ErrorAction SilentlyContinue
        Write-WibInfo "Загрузка служебного пакета UUP dump, попытка $attempt/$Attempts"
        try {
            Invoke-WebRequest -Method Post -Uri $uri -Body $body -OutFile $DestinationZip -UseBasicParsing -TimeoutSec 300 -UserAgent 'Mozilla/5.0 WindowsISOBuilder/0.1' | Out-Null
        }
        catch {
            $lastReason = $_.Exception.Message
            if ($attempt -lt $Attempts) {
                Start-Sleep -Seconds (5 * $attempt)
                continue
            }
            throw "Не удалось загрузить пакет UUP dump: $lastReason"
        }

        $validation = Test-WibUupPackageArchive -Path $DestinationZip
        if ($validation.IsValid) {
            Write-WibInfo "Получен корректный пакет: $((Get-Item -LiteralPath $DestinationZip).Length) байт."
            return
        }

        $lastReason = $validation.Reason
        Remove-Item -LiteralPath $invalidPath -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $DestinationZip -Destination $invalidPath -Force
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds (5 * $attempt) }
    }

    $preview = Get-WibResponsePreview -Path $invalidPath
    throw "UUP dump не вернул корректный ZIP. Причина: $lastReason. Ответ: $preview"
}

function Set-WibConverterConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Plan
    )

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
    param(
        [Parameter(Mandatory = $true)][string]$PackageDirectory,
        [Parameter(Mandatory = $true)][string]$ScriptName
    )

    # Running the generated .cmd directly from a PowerShell pipeline can return
    # before every process spawned by the batch file has finished. UUP wrappers
    # commonly use a nested PowerShell process plus Out-String -Stream so the
    # parent does not look for the ISO while converter child processes are still
    # running. Explicitly propagate cmd.exe's exit code from that child process.
    $powerShellExecutable = Get-WibPowerShellExecutable
    $escapedScriptName = $ScriptName.Replace("'", "''")
    $childCommand = '& $env:ComSpec /D /C ''call "{0}"''; exit $LASTEXITCODE' -f $escapedScriptName

    Push-Location $PackageDirectory
    try {
        & $powerShellExecutable `
            -NoLogo `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -Command $childCommand |
            Out-String -Stream |
            ForEach-Object { Write-Host $_ }
        return $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
}

function Get-WibIsoMetadata {
    param([Parameter(Mandatory = $true)][string]$IsoPath)

    $result = [ordered]@{
        Mounted       = $false
        HasBootWim    = $false
        HasInstallWim = $false
        HasInstallEsd = $false
        Images        = @()
        Warning       = ''
    }

    if (-not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) {
        $result.Warning = 'Mount-DiskImage недоступен; внутреннее содержимое ISO не проверено.'
        return [pscustomobject]$result
    }

    $diskImage = $null
    try {
        $diskImage = Mount-DiskImage -ImagePath $IsoPath -PassThru
        $volume = $diskImage | Get-Volume
        if (-not $volume.DriveLetter) { throw 'ISO смонтирован без буквы диска.' }
        $result.Mounted = $true
        $sources = '{0}:\sources' -f $volume.DriveLetter
        $bootWim = Join-Path $sources 'boot.wim'
        $installWim = Join-Path $sources 'install.wim'
        $installEsd = Join-Path $sources 'install.esd'
        $result.HasBootWim = Test-Path -LiteralPath $bootWim
        $result.HasInstallWim = Test-Path -LiteralPath $installWim
        $result.HasInstallEsd = Test-Path -LiteralPath $installEsd

        $imagePath = if ($result.HasInstallWim) { $installWim } elseif ($result.HasInstallEsd) { $installEsd } else { $null }
        if ($imagePath -and (Get-Command Get-WindowsImage -ErrorAction SilentlyContinue)) {
            $images = foreach ($image in Get-WindowsImage -ImagePath $imagePath) {
                $detail = Get-WindowsImage -ImagePath $imagePath -Index $image.ImageIndex
                [pscustomobject]@{
                    Index        = $detail.ImageIndex
                    Name         = $detail.ImageName
                    Description  = $detail.ImageDescription
                    Version      = [string]$detail.Version
                    Architecture = [string]$detail.Architecture
                }
            }
            $result.Images = @($images)
        }
    }
    catch {
        $result.Warning = $_.Exception.Message
    }
    finally {
        if ($null -ne $diskImage) {
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
        }
    }
    return [pscustomobject]$result
}

function Save-WibJobState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)]$Plan,
        [string]$Message = ''
    )

    Write-WibJsonFile -Path $Path -Depth 20 -Value ([ordered]@{
        stage     = $Stage
        updatedAt = (Get-Date).ToString('o')
        message   = $Message
        plan      = $Plan
    })
}

function Start-WibElevatedPlan {
    param([Parameter(Mandatory = $true)]$Plan)

    $plansDirectory = Join-Path ([string]$Plan.CacheDirectory) 'plans'
    New-Item -ItemType Directory -Path $plansDirectory -Force | Out-Null
    $planPath = Join-Path $plansDirectory ('plan-{0}.json' -f [Guid]::NewGuid().ToString('N'))
    Save-WibPlan -Plan $Plan -Path $planPath

    $entryScript = Join-Path $script:ProjectRoot 'Start-Builder.ps1'
    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Quote-WibCommandArgument -Value $entryScript),
        '-PlanFile',
        (Quote-WibCommandArgument -Value $planPath)
    )

    Write-Host 'Для загрузки и конвертации UUP требуются права администратора. Открывается UAC...' -ForegroundColor Yellow
    try {
        $process = Start-Process -FilePath (Get-WibPowerShellExecutable) -Verb RunAs -Wait -PassThru -ArgumentList $arguments
        if ($process.ExitCode -ne 0) {
            throw "Повышенный процесс завершился с кодом $($process.ExitCode). План: $planPath"
        }
    }
    catch {
        throw "Не удалось запустить сборку с правами администратора: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WibBuildPlanCore {
    param([Parameter(Mandatory = $true)]$Plan)

    Assert-WibPlan -Plan $Plan
    Assert-WibHostRequirements

    $outputDirectory = Resolve-WibFullPath -Path ([string]$Plan.OutputDirectory) -Create
    $cacheDirectory = Resolve-WibFullPath -Path ([string]$Plan.CacheDirectory) -Create
    Assert-WibFreeSpace -Path $cacheDirectory -MinimumBytes 40GB -Purpose 'рабочих файлов UUP'
    Assert-WibFreeSpace -Path $outputDirectory -MinimumBytes 8GB -Purpose 'готового ISO'

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
        Write-Host "Сборка:      $($Plan.Build.Title)"
        Write-Host "Номер:       $($Plan.Build.Build)"
        Write-Host "Архитектура: $($Plan.Build.Architecture)"
        Write-Host "Язык:        $($Plan.Language)"
        Write-Host "Редакции:    $(@($Plan.Editions) -join ', ')"
        Write-Host "Формат:      install.$(([string]$Plan.ImageFormat).ToLowerInvariant())"
        Write-Host "Результат:   $outputDirectory"
        Write-Host "Кеш:         $cacheDirectory"
        Write-Host "Лог:         $logPath"

        Save-WibJobState -Path $statePath -Stage 'downloading-package' -Plan $Plan
        Write-WibStage 'Получение пакета UUP dump'
        Download-WibUupPackage -Plan $Plan -DestinationZip $packageZip

        $downloadScript = Get-ChildItem -LiteralPath $workDirectory -Filter 'uup_download_windows.cmd' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $downloadScript) {
            Write-WibInfo 'Распаковка пакета конвертации...'
            Expand-Archive -LiteralPath $packageZip -DestinationPath $workDirectory -Force
            $downloadScript = Get-ChildItem -LiteralPath $workDirectory -Filter 'uup_download_windows.cmd' -File -Recurse | Select-Object -First 1
        }
        if (-not $downloadScript) { throw 'В пакете отсутствует uup_download_windows.cmd.' }

        $packageDirectory = $downloadScript.Directory.FullName
        $configPath = Join-Path $packageDirectory 'ConvertConfig.ini'
        if (-not (Test-Path -LiteralPath $configPath)) { throw 'В пакете отсутствует ConvertConfig.ini.' }
        Set-WibConverterConfiguration -Path $configPath -Plan $Plan

        Get-ChildItem -LiteralPath $workDirectory -Filter '*.iso' -File -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

        Save-WibJobState -Path $statePath -Stage 'downloading-uup-and-converting' -Plan $Plan
        Write-WibStage 'Загрузка файлов Microsoft и создание ISO'
        Write-WibInfo 'aria2 продолжит неполные загрузки из сохранённого рабочего каталога.'

        $exitCode = Invoke-WibUupDownloadScript -PackageDirectory $packageDirectory -ScriptName $downloadScript.Name
        if ($exitCode -ne 0) { throw "uup_download_windows.cmd завершился с кодом $exitCode. Подробный лог: $converterLogPath" }

        $iso = Get-ChildItem -LiteralPath $workDirectory -Filter '*.iso' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $iso) {
            throw "Конвертер завершился, но ISO-файл не найден в рабочем каталоге: $workDirectory. Подробный лог: $converterLogPath"
        }
        if ($iso.Length -lt 1GB) { throw "Созданный ISO подозрительно мал: $($iso.Length) байт." }

        $editionPart = ConvertTo-WibSafeFilePart -Value (@($Plan.Editions) -join '+')
        $versionPart = if ([string]::IsNullOrWhiteSpace([string]$Plan.Build.VersionLabel)) { 'build' } else { [string]$Plan.Build.VersionLabel }
        $fileName = '{0}_{1}_{2}_{3}_{4}_{5}.iso' -f `
            (ConvertTo-WibSafeFilePart -Value ([string]$Plan.Build.Product)), `
            (ConvertTo-WibSafeFilePart -Value $versionPart), `
            (ConvertTo-WibSafeFilePart -Value ([string]$Plan.Build.Build)), `
            (ConvertTo-WibSafeFilePart -Value ([string]$Plan.Language)), `
            (ConvertTo-WibSafeFilePart -Value ([string]$Plan.Build.Architecture)), `
            $editionPart
        $destinationIso = Join-Path $outputDirectory $fileName
        Move-Item -LiteralPath $iso.FullName -Destination $destinationIso -Force

        Save-WibJobState -Path $statePath -Stage 'validating' -Plan $Plan
        Write-WibStage 'Проверка результата'
        $hash = (Get-FileHash -LiteralPath $destinationIso -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText("$destinationIso.sha256.txt", "$hash  $fileName`r`n", [Text.Encoding]::ASCII)
        $isoMetadata = Get-WibIsoMetadata -IsoPath $destinationIso
        if ($isoMetadata.Warning) { Write-WibWarning $isoMetadata.Warning }
        if ($isoMetadata.Mounted -and (-not $isoMetadata.HasBootWim -or (-not $isoMetadata.HasInstallWim -and -not $isoMetadata.HasInstallEsd))) {
            throw 'ISO создан, но обязательные boot.wim/install.wim/install.esd не найдены.'
        }

        $metadata = [ordered]@{
            applicationVersion = $script:WibVersion
            createdAt          = (Get-Date).ToString('o')
            source             = 'Microsoft Windows Update/CDN via UUP dump generated conversion package'
            uupUpdateId        = [string]$Plan.Build.Uuid
            uupUpdateName      = [string]$Plan.Build.Title
            product            = [string]$Plan.Build.Product
            versionLabel       = [string]$Plan.Build.VersionLabel
            build              = [string]$Plan.Build.Build
            architecture       = [string]$Plan.Build.Architecture
            language           = [string]$Plan.Language
            editions           = @($Plan.Editions)
            sourceEdition      = [string]$Plan.SourceEdition
            virtualEditions    = @($Plan.VirtualEditions)
            imageFormat        = [string]$Plan.ImageFormat
            addUpdates         = [bool]$Plan.AddUpdates
            cleanup            = [bool]$Plan.Cleanup
            netFx3             = [bool]$Plan.NetFx3
            sha256             = $hash
            bytes              = (Get-Item -LiteralPath $destinationIso).Length
            isoValidation      = $isoMetadata
        }
        Write-WibJsonFile -Value $metadata -Path "$destinationIso.json" -Depth 20

        Save-WibJobState -Path $statePath -Stage 'completed' -Plan $Plan -Message $destinationIso
        Write-Host ''
        Write-Host "Готово: $destinationIso" -ForegroundColor Green
        Write-Host "SHA-256: $hash"
        Write-Host "Лог: $logPath"

        if ([bool]$Plan.RemoveWorkAfterSuccess) {
            Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }

        return [pscustomobject]@{ IsoPath = $destinationIso; Sha256 = $hash; LogPath = $logPath; MetadataPath = "$destinationIso.json" }
    }
    catch {
        try { Save-WibJobState -Path $statePath -Stage 'failed' -Plan $Plan -Message $_.Exception.Message } catch { }
        Write-Host ''
        Write-Host ('ОШИБКА СБОРКИ: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host "Рабочий каталог сохранён для продолжения: $workDirectory"
        Write-Host "Лог: $logPath"
        throw
    }
    finally {
        if ($transcriptStarted) {
            try { Stop-Transcript | Out-Null } catch { }
        }
    }
}

function Invoke-WibBuildPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan)

    Assert-WibPlan -Plan $Plan
    if ($env:OS -eq 'Windows_NT' -and -not (Test-WibAdministrator)) {
        Start-WibElevatedPlan -Plan $Plan
        return
    }
    return Invoke-WibBuildPlanCore -Plan $Plan
}

function Invoke-WibPlanFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $plan = Read-WibPlan -Path $Path
    Invoke-WibBuildPlan -Plan $plan
}