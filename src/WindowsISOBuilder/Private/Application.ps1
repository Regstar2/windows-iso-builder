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

function Start-WibInteractiveBuild {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$CacheDirectory
    )

    $build = Select-WibBuildInteractive -CacheDirectory $CacheDirectory
    if ($null -eq $build) {
        return $false
    }

    $language = Select-WibLanguageInteractive -UpdateId $build.Uuid -CacheDirectory $CacheDirectory
    $editions = @(Select-WibEditionsInteractive -UpdateId $build.Uuid -Language $language.Code -CacheDirectory $CacheDirectory)
    $format = Select-WibImageFormatInteractive

    Write-WibStage 'Дополнительные параметры'
    $addUpdates = Read-WibYesNo -Prompt 'Интегрировать доступные обновления?' -Default $true
    $cleanup = Read-WibYesNo -Prompt 'Выполнить очистку компонентов после интеграции?' -Default $true
    $netFx3 = Read-WibYesNo -Prompt 'Добавить .NET Framework 3.5?' -Default $false

    $plan = New-WibBuildPlan -Build $build -Language $language.Code -Editions @($editions.Code) -ImageFormat $format -AddUpdates $addUpdates -Cleanup $cleanup -NetFx3 $netFx3 -OutputDirectory $OutputDirectory -CacheDirectory $CacheDirectory

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

function Start-WibInteractive {
    [CmdletBinding()]
    param([string]$ApplicationRoot = $script:ProjectRoot)

    $outputDirectory = Resolve-WibFullPath -Path (Join-Path $ApplicationRoot 'output') -Create
    $cacheDirectory = Resolve-WibFullPath -Path (Get-WibDefaultCacheDirectory) -Create

    while ($true) {
        Show-WibHeader
        Write-Host ''
        Write-Host '1. Найти сборку и создать ISO'
        Write-Host '2. Показать размер кеша'
        Write-Host '3. Очистить кеш API'
        Write-Host '4. Очистить весь кеш и незавершённые загрузки'
        Write-Host '0. Выход'
        $choice = Read-WibNumber -Prompt 'Действие' -Minimum 0 -Maximum 4 -Default 1

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
                Show-WibCacheInfoInteractive -CacheDirectory $cacheDirectory
                Write-Host ''
                Read-Host 'Нажмите Enter, чтобы вернуться в меню' | Out-Null
            }
            3 {
                if (Read-WibYesNo -Prompt 'Удалить кеш каталога и метаданных API?' -Default $false) {
                    Clear-WibCache -CacheDirectory $cacheDirectory -Category Api -Confirm:$false
                }
            }
            4 {
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
