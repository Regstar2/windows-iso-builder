function Read-WibYesNo {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = (Read-Host "$Prompt $suffix").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($answer -match '(?i)^(y|yes|д|да)$') { return $true }
        if ($answer -match '(?i)^(n|no|н|нет)$') { return $false }
        Write-Host 'Введите Y или N.' -ForegroundColor Yellow
    }
}

function Read-WibNumber {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][int]$Minimum,
        [Parameter(Mandatory = $true)][int]$Maximum,
        [int]$Default = 0
    )

    while ($true) {
        $suffix = if ($Default -ge $Minimum -and $Default -le $Maximum) { " [$Default]" } else { '' }
        $raw = (Read-Host "$Prompt$suffix").Trim()
        if ([string]::IsNullOrWhiteSpace($raw) -and $suffix) { return $Default }
        $value = 0
        if ([int]::TryParse($raw, [ref]$value) -and $value -ge $Minimum -and $value -le $Maximum) {
            return $value
        }
        Write-Host "Введите число от $Minimum до $Maximum." -ForegroundColor Yellow
    }
}

function Select-WibArchitecture {
    Write-Host '1. x64 (amd64) — рекомендуется для обычных ПК'
    Write-Host '2. ARM64'
    Write-Host '3. x86 — только для старых выпусков Windows'
    $choice = Read-WibNumber -Prompt 'Архитектура' -Minimum 1 -Maximum 3 -Default 1
    return @('amd64', 'arm64', 'x86')[$choice - 1]
}

function Select-WibBuildInteractive {
    param([Parameter(Mandatory = $true)][string]$CacheDirectory)

    while ($true) {
        Write-WibStage 'Поиск сборки Windows'
        $query = (Read-Host 'Введите версию, номер сборки или название, например 22H2, 19045, 22621').Trim()
        if ([string]::IsNullOrWhiteSpace($query)) {
            Write-Host 'Поисковый запрос не может быть пустым.' -ForegroundColor Yellow
            continue
        }

        $architecture = Select-WibArchitecture
        $includePreview = Read-WibYesNo -Prompt 'Показывать предварительные Insider/Preview-сборки?' -Default $false
        $builds = @(Search-WibBuilds -Search $query -Architecture $architecture -IncludePreview:$includePreview -CacheDirectory $CacheDirectory)
        if ($builds.Count -eq 0) {
            Write-Host 'Подходящие сборки не найдены. Измените запрос или фильтры.' -ForegroundColor Yellow
            continue
        }

        $limit = [Math]::Min($builds.Count, 40)
        Write-Host ''
        Write-Host ('Найдено: {0}. Показаны первые {1}.' -f $builds.Count, $limit)
        for ($index = 0; $index -lt $limit; $index++) {
            $item = $builds[$index]
            $dateText = if ($null -ne $item.CreatedAt) { $item.CreatedAt.ToString('yyyy-MM-dd') } else { 'unknown-date' }
            $previewText = if ($item.IsPreview) { ' PREVIEW' } else { '' }
            Write-Host ('{0,2}. {1} | {2} | {3} | {4}{5}' -f ($index + 1), $item.Build, $item.Architecture, $dateText, $item.Title, $previewText)
        }

        $selection = Read-WibNumber -Prompt 'Номер сборки' -Minimum 1 -Maximum $limit -Default 1
        return $builds[$selection - 1]
    }
}

function Select-WibLanguageInteractive {
    param(
        [Parameter(Mandatory = $true)][string]$UpdateId,
        [Parameter(Mandatory = $true)][string]$CacheDirectory
    )

    Write-WibStage 'Выбор языка'
    $languages = @(Get-WibLanguages -UpdateId $UpdateId -CacheDirectory $CacheDirectory)
    if ($languages.Count -eq 0) { throw 'Для выбранной сборки API не вернул языки.' }

    $defaultIndex = 1
    for ($index = 0; $index -lt $languages.Count; $index++) {
        if ($languages[$index].Code -eq 'ru-ru') { $defaultIndex = $index + 1 }
        Write-Host ('{0,2}. {1,-8} {2}' -f ($index + 1), $languages[$index].Code, $languages[$index].Name)
    }

    $selection = Read-WibNumber -Prompt 'Номер языка' -Minimum 1 -Maximum $languages.Count -Default $defaultIndex
    return $languages[$selection - 1]
}

function Select-WibEditionsInteractive {
    param(
        [Parameter(Mandatory = $true)][string]$UpdateId,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string]$CacheDirectory
    )

    Write-WibStage 'Выбор редакций'
    $editions = @(Get-WibEditions -UpdateId $UpdateId -Language $Language -CacheDirectory $CacheDirectory)
    if ($editions.Count -eq 0) { throw 'Для выбранной сборки и языка API не вернул редакции.' }

    $defaultIndex = 1
    for ($index = 0; $index -lt $editions.Count; $index++) {
        if ($editions[$index].Code -eq 'Professional') { $defaultIndex = $index + 1 }
        Write-Host ('{0,2}. {1,-28} {2}' -f ($index + 1), $editions[$index].Code, $editions[$index].Name)
    }

    Write-Host ''
    Write-Host 'Можно указать несколько номеров через запятую. Первая редакция станет базовой, остальные будут созданы механизмом virtual editions.' -ForegroundColor DarkGray

    while ($true) {
        $raw = (Read-Host "Редакции [$defaultIndex]").Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [string]$defaultIndex }
        $numbers = @()
        $valid = $true
        foreach ($part in ($raw -split ',')) {
            $number = 0
            if (-not [int]::TryParse($part.Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $editions.Count) {
                $valid = $false
                break
            }
            if ($numbers -notcontains $number) { $numbers += $number }
        }
        if ($valid -and $numbers.Count -gt 0) {
            return @($numbers | ForEach-Object { $editions[$_ - 1] })
        }
        Write-Host 'Введите корректные номера, например 1 или 1,3.' -ForegroundColor Yellow
    }
}

function Select-WibImageFormatInteractive {
    Write-WibStage 'Формат install-образа'
    Write-Host '1. install.esd — меньше размер, дольше создание'
    Write-Host '2. install.wim — проще обслуживать и изменять'
    $choice = Read-WibNumber -Prompt 'Формат' -Minimum 1 -Maximum 2 -Default 1
    if ($choice -eq 1) { return 'ESD' }
    return 'WIM'
}
