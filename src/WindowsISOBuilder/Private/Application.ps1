function Show-WibHeader {
    Clear-Host
    Write-Host 'Windows ISO Builder' -ForegroundColor Cyan
    Write-Host "Версия $script:WibVersion"
    Write-Host 'Интерактивный клиент UUP dump. Файлы Windows загружаются с серверов Microsoft.' -ForegroundColor DarkGray
    Write-Host 'Проект не является продуктом Microsoft и не выполняет активацию Windows.' -ForegroundColor DarkGray
}

function Show-WibCacheInfoInteractive {
    param([Parameter(Mandatory = $true)][string]$CacheDirectory)
    $info = Get-WibCacheInfo -CacheDirectory $CacheDirectory
    Write-WibStage 'Кеш'
    Write-Host "Путь: $($info.Path)"
    Write-Host ('Всего: {0:N2} ГБ' -f ($info.TotalBytes / 1GB))
    foreach ($category in $info.Categories) {
        Write-Host ('{0,-10} {1,10:N2} ГБ  {2}' -f $category.Category, ($category.Bytes / 1GB), $category.Path)
    }
}

function Show-WibBuildSuccess {
    param([AllowNull()]$Result)

    Write-Host ''
    Write-WibStage 'Сборка завершена'
    Write-Host 'ISO успешно создан.' -ForegroundColor Green

    if ($null -eq $Result) {
        return
    }

    $isoPath = Get-WibResultPropertyText -Result $Result -Name 'isoPath'
    $buildLogPath = Get-WibResultPropertyText -Result $Result -Name 'logPath'
    $executionLogPath = Get-WibResultPropertyText -Result $Result -Name 'executionLogPath'

    if (-not [string]::IsNullOrWhiteSpace($isoPath)) {
        Write-Host ('ISO: {0}' -f $isoPath) -ForegroundColor Green
    }
    if (-not [string]::IsNullOrWhiteSpace($buildLogPath)) {
        Write-Host ('Лог сборки: {0}' -f $buildLogPath) -ForegroundColor DarkGray
    }
    if (-not [string]::IsNullOrWhiteSpace($executionLogPath)) {
        Write-Host ('Лог повышенного процесса: {0}' -f $executionLogPath) -ForegroundColor DarkGray
    }
}

function Get-WibQuickLatestBuild {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows 11', 'Windows 10')]
        [string]$Product,
        [Parameter(Mandatory = $true)][string]$CacheDirectory
    )

    # Quick mode deliberately skips the catalog UI, but it must never hardcode
    # a Windows release or build number. Always refresh the UUP dump catalog and
    # let the same release-ranking logic used by the normal UI choose the latest
    # stable, installable build for the selected Windows family.
    $builds = @(Search-WibBuilds `
        -Search $Product `
        -Architecture amd64 `
        -ForceRefresh `
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

        $entryType -eq 'Windows' -and $actualProduct -eq $Product -and -not $isPreview
    })

    if ($candidates.Count -eq 0) {
        throw "UUP dump не вернул стабильную полноценную сборку $Product x64."
    }

    return Get-WibNewestBuild -Builds $candidates
}

function Start-WibBuildFromSelectedBuild {
    param(
        [Parameter(Mandatory = $true)]$Build,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$CacheDirectory,
        [switch]$QuickMode
    )

    if ($QuickMode) {
        Write-Host ''
        Write-Host ('Выбрана последняя стабильная сборка: {0}' -f $Build.Title) -ForegroundColor Green
        Write-Host ('Сборка: {0}; архитектура: {1}' -f $Build.Build, $Build.Architecture) -ForegroundColor DarkGray
        Write-Host 'Быстрый режим пропускает каталог сборок; язык, редакции и формат можно выбрать ниже.' -ForegroundColor DarkGray
    }

    $language = Select-WibLanguageInteractive -UpdateId $Build.Uuid -CacheDirectory $CacheDirectory
    $editions = @(Select-WibEditionsInteractive -UpdateId $Build.Uuid -Language $language.Code -CacheDirectory $CacheDirectory)
    $format = Select-WibImageFormatInteractive

    Write-WibStage 'Дополнительные параметры'
    $addUpdates = Read-WibYesNo -Prompt 'Интегрировать доступные обновления?' -Default $true
    $cleanup = Read-WibYesNo -Prompt 'Выполнить очистку компонентов после интеграции?' -Default $true
    $netFx3 = Read-WibYesNo -Prompt 'Добавить .NET Framework 3.5?' -Default $false

    $plan = New-WibBuildPlan `
        -Build $Build `
        -Language $language.Code `
        -Editions @($editions.Code) `
        -ImageFormat $format `
        -AddUpdates $addUpdates `
        -Cleanup $cleanup `
        -NetFx3 $netFx3 `
        -OutputDirectory $OutputDirectory `
        -CacheDirectory $CacheDirectory

    Write-WibStage 'Подтверждение'
    Write-Host "Сборка:      $($plan.Build.Title)"
    Write-Host "Архитектура: $($plan.Build.Architecture)"
    Write-Host "Язык:        $($plan.Language)"
    Write-Host "Редакции:    $(@($plan.Editions) -join ', ')"
    Write-Host "Формат:      $($plan.ImageFormat)"
    Write-Host "Результат:   $($plan.OutputDirectory)"
    Write-Host "Кеш:         $($plan.CacheDirectory)"

    if (-not (Read-WibYesNo -Prompt 'Начать загрузку и сборку?' -Default $true)) {
        Write-Host 'Сборка отменена.'
        return $false
    }

    $buildResult = Invoke-WibBuildPlan -Plan $plan
    Show-WibBuildSuccess -Result $buildResult
    return $true
}

function Start-WibInteractiveBuild {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$CacheDirectory
    )

    $build = Select-WibBuildInteractive -CacheDirectory $CacheDirectory
    if ($null -eq $build) {
        return $false
    }

    return Start-WibBuildFromSelectedBuild `
        -Build $build `
        -OutputDirectory $OutputDirectory `
        -CacheDirectory $CacheDirectory
}

function Show-WibLegacyQuickDownloadUnavailable {
    param([Parameter(Mandatory = $true)][string]$Product)

    Write-Host ''
    Write-WibStage 'Источник недоступен'
    Write-Host ("$Product пока нельзя скачать через быстрый режим этого приложения.") -ForegroundColor Yellow
    Write-Host 'Текущий конвейер основан на UUP dump / Unified Update Platform и рассчитан на Windows 10/11.' -ForegroundColor DarkGray
    Write-Host 'Пункт зарезервирован: Windows 8.1/7 можно будет подключить позже через отдельный проверенный источник.' -ForegroundColor DarkGray
    Write-Host ''
    Read-Host 'Нажмите Enter, чтобы вернуться в меню' | Out-Null
}

function Start-WibQuickLatestInteractive {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$CacheDirectory
    )

    Write-WibStage 'Быстро скачать последнюю Windows'
    Write-Host '1. Windows 11 — последняя стабильная x64'
    Write-Host '2. Windows 10 — последняя стабильная x64'
    Write-Host '3. Windows 8.1 — пока недоступно через UUP dump' -ForegroundColor DarkGray
    Write-Host '4. Windows 7 — пока недоступно через UUP dump' -ForegroundColor DarkGray
    Write-Host '0. Назад'

    $choice = Read-WibNumber -Prompt 'Версия Windows' -Minimum 0 -Maximum 4 -Default 1
    switch ($choice) {
        0 { return $false }
        3 {
            Show-WibLegacyQuickDownloadUnavailable -Product 'Windows 8.1'
            return $false
        }
        4 {
            Show-WibLegacyQuickDownloadUnavailable -Product 'Windows 7'
            return $false
        }
    }

    $product = if ($choice -eq 1) { 'Windows 11' } else { 'Windows 10' }
    Write-Host ''
    Write-Host ("Ищу последнюю стабильную сборку $product x64 в UUP dump...") -ForegroundColor Cyan
    $build = Get-WibQuickLatestBuild -Product $product -CacheDirectory $CacheDirectory

    return Start-WibBuildFromSelectedBuild `
        -Build $build `
        -OutputDirectory $OutputDirectory `
        -CacheDirectory $CacheDirectory `
        -QuickMode
}

function Start-WibInteractive {
    [CmdletBinding()]
    param([string]$ApplicationRoot = $script:ProjectRoot)

    $outputDirectory = Resolve-WibFullPath -Path (Join-Path $ApplicationRoot 'output') -Create
    $cacheDirectory = Resolve-WibFullPath -Path (Get-WibDefaultCacheDirectory) -Create

    while ($true) {
        Show-WibHeader
        Write-Host ''
        Write-Host '1. Найти сборку и создать ISO'
        Write-Host '2. Быстро скачать последнюю Windows'
        Write-Host '3. Показать размер кеша'
        Write-Host '4. Очистить кеш API'
        Write-Host '5. Очистить весь кеш и незавершённые загрузки'
        Write-Host '0. Выход'
        $choice = Read-WibNumber -Prompt 'Действие' -Minimum 0 -Maximum 5 -Default 1

        switch ($choice) {
            0 { return }
            1 {
                $buildStarted = Start-WibInteractiveBuild -OutputDirectory $outputDirectory -CacheDirectory $cacheDirectory
                if ($buildStarted) {
                    Write-Host ''
                    Read-Host 'Нажмите Enter, чтобы вернуться в меню' | Out-Null
                }
            }
            2 {
                $buildStarted = Start-WibQuickLatestInteractive -OutputDirectory $outputDirectory -CacheDirectory $cacheDirectory
                if ($buildStarted) {
                    Write-Host ''
                    Read-Host 'Нажмите Enter, чтобы вернуться в меню' | Out-Null
                }
            }
            3 {
                Show-WibCacheInfoInteractive -CacheDirectory $cacheDirectory
                Write-Host ''
                Read-Host 'Нажмите Enter, чтобы вернуться в меню' | Out-Null
            }
            4 {
                if (Read-WibYesNo -Prompt 'Удалить кеш каталога и метаданных API?' -Default $false) {
                    Clear-WibCache -CacheDirectory $cacheDirectory -Category Api -Confirm:$false
                }
            }
            5 {
                if (Read-WibYesNo -Prompt 'Удалить весь кеш, включая загруженные UUP-файлы?' -Default $false) {
                    Clear-WibCache -CacheDirectory $cacheDirectory -Category All -Confirm:$false
                }
            }
        }
    }
}

function Start-WibNonInteractive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Search,
        [ValidateSet('amd64', 'arm64', 'x86')][string]$Architecture = 'amd64',
        [ValidatePattern('^[a-z]{2}-[a-z]{2}$')][string]$Language = 'ru-ru',
        [string[]]$Editions = @('Professional'),
        [ValidateSet('WIM', 'ESD')][string]$ImageFormat = 'ESD',
        [bool]$IncludePreview = $false,
        [bool]$ForceCatalogRefresh = $false,
        [bool]$AddUpdates = $true,
        [bool]$Cleanup = $true,
        [bool]$NetFx3 = $false,
        [string]$OutputDirectory = (Get-WibDefaultOutputDirectory),
        [string]$CacheDirectory = (Get-WibDefaultCacheDirectory)
    )

    $builds = @(Search-WibBuilds -Search $Search -Architecture $Architecture -IncludePreview:$IncludePreview -ForceRefresh:$ForceCatalogRefresh -CacheDirectory $CacheDirectory)
    if ($builds.Count -eq 0) { throw "По запросу '$Search' подходящие сборки не найдены." }
    $normalBuilds = @($builds | Where-Object {
        $entryType = if ($null -ne $_.PSObject.Properties['EntryType']) { [string]$_.EntryType } else { Get-WibBuildEntryType -Title $_.Title }
        $entryType -eq 'Windows'
    })
    $build = if ($normalBuilds.Count -gt 0) { $normalBuilds[0] } else { $builds[0] }

    $availableLanguages = @(Get-WibLanguages -UpdateId $build.Uuid -CacheDirectory $CacheDirectory)
    if ($availableLanguages.Code -notcontains $Language) { throw "Язык $Language недоступен для сборки $($build.Build)." }

    $availableEditions = @(Get-WibEditions -UpdateId $build.Uuid -Language $Language -CacheDirectory $CacheDirectory)
    foreach ($edition in $Editions) {
        if ($availableEditions.Code -notcontains $edition) { throw "Редакция $edition недоступна для сборки $($build.Build), язык $Language." }
    }

    $plan = New-WibBuildPlan -Build $build -Language $Language -Editions $Editions -ImageFormat $ImageFormat -AddUpdates $AddUpdates -Cleanup $Cleanup -NetFx3 $NetFx3 -OutputDirectory $OutputDirectory -CacheDirectory $CacheDirectory
    Invoke-WibBuildPlan -Plan $plan
}
