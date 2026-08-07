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

function Get-WibConsoleTableWidth {
    param([int]$Fallback = 120)

    try {
        $width = [Console]::WindowWidth
        if ($width -gt 0) {
            # Leave one column unused because some console hosts wrap a line that
            # ends exactly at the right edge of the window.
            return [Math]::Max(20, ($width - 1))
        }
    }
    catch {
        # WindowWidth is unavailable when output is redirected or hosted outside
        # the classic Windows console. Use a conservative fallback in that case.
    }

    return $Fallback
}

function ConvertTo-WibTableCellText {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][ValidateRange(1, 4096)][int]$Width,
        [ValidateSet('Left', 'Right')][string]$Alignment = 'Left'
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    $text = ($text -replace '[\r\n\t]+', ' ').Trim()

    if ($text.Length -gt $Width) {
        if ($Width -eq 1) {
            $text = '…'
        }
        else {
            $text = $text.Substring(0, $Width - 1) + '…'
        }
    }

    if ($Alignment -eq 'Right') {
        return $text.PadLeft($Width)
    }
    return $text.PadRight($Width)
}

function New-WibTableBorderLine {
    param(
        [Parameter(Mandatory = $true)][int[]]$Widths,
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Middle,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $segments = @($Widths | ForEach-Object { -join ('─' * ($_ + 2)) })
    return $Left + ($segments -join $Middle) + $Right
}

function New-WibTableRowLine {
    param(
        [Parameter(Mandatory = $true)][string[]]$Values,
        [Parameter(Mandatory = $true)][int[]]$Widths,
        [string[]]$Alignments
    )

    $cells = @()
    for ($index = 0; $index -lt $Widths.Count; $index++) {
        $alignment = if ($Alignments -and $index -lt $Alignments.Count) { $Alignments[$index] } else { 'Left' }
        $cells += ConvertTo-WibTableCellText -Value $Values[$index] -Width $Widths[$index] -Alignment $alignment
    }
    return '│ ' + ($cells -join ' │ ') + ' │'
}

function Get-WibBuildTableLines {
    param(
        [Parameter(Mandatory = $true)][object[]]$Builds,
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][int]$StartIndex,
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][int]$EndIndex,
        [int]$MaximumWidth = (Get-WibConsoleTableWidth)
    )

    if ($Builds.Count -eq 0) { return @() }
    if ($StartIndex -ge $Builds.Count -or $EndIndex -lt $StartIndex -or $EndIndex -ge $Builds.Count) {
        throw 'Некорректный диапазон строк таблицы сборок.'
    }

    $maximumWidth = [Math]::Max(20, $MaximumWidth)
    $pageItems = @($Builds[$StartIndex..$EndIndex])
    $numberWidth = [Math]::Max(3, ([string]$Builds.Count).Length)

    $buildWidth = 6
    $architectureWidth = 4
    foreach ($item in $pageItems) {
        $buildWidth = [Math]::Max($buildWidth, ([string]$item.Build).Length)
        $architectureWidth = [Math]::Max($architectureWidth, ([string]$item.Architecture).Length)
    }
    $buildWidth = [Math]::Min(16, $buildWidth)
    $architectureWidth = [Math]::Min(8, $architectureWidth)

    # Six columns use 19 characters for borders, separators and cell padding.
    $dateWidth = 10
    $typeWidth = 8
    $tableOverhead = 19
    $titleWidth = $maximumWidth - $tableOverhead - $numberWidth - $buildWidth - $architectureWidth - $dateWidth - $typeWidth

    if ($titleWidth -lt 12) {
        $buildWidth = [Math]::Min($buildWidth, 8)
        $architectureWidth = [Math]::Min($architectureWidth, 5)
        $titleWidth = $maximumWidth - $tableOverhead - $numberWidth - $buildWidth - $architectureWidth - $dateWidth - $typeWidth
    }

    if ($titleWidth -lt 8) {
        # Extremely narrow hosts cannot fit five useful columns. Fall back to a
        # two-column table instead of allowing the console to wrap its rows.
        $summaryOverhead = 7
        $summaryWidth = [Math]::Max(1, $maximumWidth - $summaryOverhead - $numberWidth)
        $widths = @($numberWidth, $summaryWidth)
        $lines = @(
            (New-WibTableBorderLine -Widths $widths -Left '┌' -Middle '┬' -Right '┐'),
            (New-WibTableRowLine -Values @('№', 'Сборка / арх. / дата / тип / название') -Widths $widths -Alignments @('Right', 'Left')),
            (New-WibTableBorderLine -Widths $widths -Left '├' -Middle '┼' -Right '┤')
        )

        for ($index = $StartIndex; $index -le $EndIndex; $index++) {
            $item = $Builds[$index]
            $dateText = if ($null -ne $item.CreatedAt) { $item.CreatedAt.ToString('yyyy-MM-dd') } else { 'неизвестно' }
            $previewText = if ($item.IsPreview) { ' [PREVIEW]' } else { '' }
            $entryType = if ($null -ne $item.PSObject.Properties['EntryType']) { [string]$item.EntryType } else { Get-WibBuildEntryType -Title $item.Title }
            $typeLabel = Get-WibBuildEntryTypeLabel -EntryType $entryType
            $summary = '{0} | {1} | {2} | {3} | {4}{5}' -f $item.Build, $item.Architecture, $dateText, $typeLabel, $item.Title, $previewText
            $lines += New-WibTableRowLine -Values @([string]($index + 1), $summary) -Widths $widths -Alignments @('Right', 'Left')
        }

        $lines += New-WibTableBorderLine -Widths $widths -Left '└' -Middle '┴' -Right '┘'
        return $lines
    }

    $widths = @($numberWidth, $buildWidth, $architectureWidth, $dateWidth, $typeWidth, $titleWidth)
    $lines = @(
        (New-WibTableBorderLine -Widths $widths -Left '┌' -Middle '┬' -Right '┐'),
        (New-WibTableRowLine -Values @('№', 'Сборка', 'Арх.', 'Дата', 'Тип', 'Название') -Widths $widths -Alignments @('Right', 'Left', 'Left', 'Left', 'Left', 'Left')),
        (New-WibTableBorderLine -Widths $widths -Left '├' -Middle '┼' -Right '┤')
    )

    for ($index = $StartIndex; $index -le $EndIndex; $index++) {
        $item = $Builds[$index]
        $dateText = if ($null -ne $item.CreatedAt) { $item.CreatedAt.ToString('yyyy-MM-dd') } else { 'неизвестно' }
        $previewText = if ($item.IsPreview) { ' [PREVIEW]' } else { '' }
        $title = ([string]$item.Title) + $previewText
        $entryType = if ($null -ne $item.PSObject.Properties['EntryType']) { [string]$item.EntryType } else { Get-WibBuildEntryType -Title $item.Title }
        $typeLabel = Get-WibBuildEntryTypeLabel -EntryType $entryType
        $lines += New-WibTableRowLine -Values @(
            [string]($index + 1),
            [string]$item.Build,
            [string]$item.Architecture,
            $dateText,
            $typeLabel,
            $title
        ) -Widths $widths -Alignments @('Right', 'Left', 'Left', 'Left', 'Left', 'Left')
    }

    $lines += New-WibTableBorderLine -Widths $widths -Left '└' -Middle '┴' -Right '┘'
    return $lines
}


function ConvertTo-WibBuildVersionKey {
    param([AllowNull()][string]$Build)

    $parts = @()
    foreach ($part in (([string]$Build) -split '\.')) {
        $value = 0
        if ([int]::TryParse($part, [ref]$value)) { $parts += $value } else { $parts += 0 }
    }
    while ($parts.Count -lt 4) { $parts += 0 }
    return ('{0:D10}.{1:D10}.{2:D10}.{3:D10}' -f $parts[0], $parts[1], $parts[2], $parts[3])
}

function ConvertTo-WibReleaseVersionKey {
    param([AllowNull()][string]$VersionLabel)

    $label = ([string]$VersionLabel).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($label)) { return 0L }

    $halfMatch = [regex]::Match($label, '^(?<year>\d{2})H(?<half>[12])$')
    if ($halfMatch.Success) {
        $year = 2000 + [int]$halfMatch.Groups['year'].Value
        $half = [int]$halfMatch.Groups['half'].Value
        return [int64](($year * 100) + ($half * 6))
    }

    # Legacy Windows versions such as 1809 and 1607 are YYMM labels.
    $yymmMatch = [regex]::Match($label, '^(?<year>\d{2})(?<month>0[1-9]|1[0-2])$')
    if ($yymmMatch.Success) {
        $year = 2000 + [int]$yymmMatch.Groups['year'].Value
        $month = [int]$yymmMatch.Groups['month'].Value
        return [int64](($year * 100) + $month)
    }

    # Product-year labels, primarily Windows Server releases.
    $yearMatch = [regex]::Match($label, '^(?<year>20\d{2})$')
    if ($yearMatch.Success) {
        return [int64](([int]$yearMatch.Groups['year'].Value * 100) + 12)
    }

    return 0L
}

function Get-WibBuildReleaseRank {
    param([Parameter(Mandatory = $true)]$Build)

    $entryType = if ($null -ne $Build.PSObject.Properties['EntryType']) { [string]$Build.EntryType } else { Get-WibBuildEntryType -Title $Build.Title }
    if ($entryType -ne 'Windows') { return 0L }

    $versionLabel = if ($null -ne $Build.PSObject.Properties['VersionLabel']) { [string]$Build.VersionLabel } else { Get-WibVersionLabel -Title ([string]$Build.Title) }
    return ConvertTo-WibReleaseVersionKey -VersionLabel $versionLabel
}

function Sort-WibBuildByRelevance {
    param([Parameter(Mandatory = $true)][object[]]$Builds)

    return @($Builds | Sort-Object -Property `
        @{ Expression = {
            $entryType = if ($null -ne $_.PSObject.Properties['EntryType']) { [string]$_.EntryType } else { Get-WibBuildEntryType -Title $_.Title }
            Get-WibBuildEntryTypeRank -EntryType $entryType
        }; Descending = $false }, `
        @{ Expression = { Get-WibBuildReleaseRank -Build $_ }; Descending = $true }, `
        @{ Expression = { ConvertTo-WibBuildVersionKey -Build $_.Build }; Descending = $true }, `
        @{ Expression = { if ($null -eq $_.CreatedAt) { [datetime]::MinValue } else { $_.CreatedAt } }; Descending = $true })
}

function Sort-WibBuildCatalog {
    param(
        [Parameter(Mandatory = $true)][object[]]$Builds,
        [ValidateSet('Relevance', 'Build', 'Architecture', 'Date', 'Type', 'Title', 'Original')][string]$Column = 'Original',
        [ValidateSet('Ascending', 'Descending')][string]$Direction = 'Ascending'
    )

    if ($Column -eq 'Original') {
        return @($Builds | Sort-Object -Property WibOriginalOrder)
    }

    $descending = ($Direction -eq 'Descending')
    switch ($Column) {
        'Relevance' {
            if ($Direction -eq 'Descending') {
                return @(Sort-WibBuildByRelevance -Builds $Builds)
            }
            return @((Sort-WibBuildByRelevance -Builds $Builds) | Sort-Object -Property @{ Expression = {
                $entryType = if ($null -ne $_.PSObject.Properties['EntryType']) { [string]$_.EntryType } else { Get-WibBuildEntryType -Title $_.Title }
                Get-WibBuildEntryTypeRank -EntryType $entryType
            }; Descending = $true }, @{ Expression = { Get-WibBuildReleaseRank -Build $_ }; Descending = $false }, @{ Expression = { ConvertTo-WibBuildVersionKey -Build $_.Build }; Descending = $false })
        }
        'Build' {
            return @($Builds | Sort-Object -Property @{ Expression = { ConvertTo-WibBuildVersionKey -Build $_.Build }; Descending = $descending }, @{ Expression = { $_.CreatedAt }; Descending = $descending })
        }
        'Architecture' {
            return @($Builds | Sort-Object -Property @{ Expression = { [string]$_.Architecture }; Descending = $descending }, @{ Expression = { ConvertTo-WibBuildVersionKey -Build $_.Build }; Descending = $true })
        }
        'Date' {
            return @($Builds | Sort-Object -Property @{ Expression = { if ($null -eq $_.CreatedAt) { [datetime]::MinValue } else { $_.CreatedAt } }; Descending = $descending }, @{ Expression = { ConvertTo-WibBuildVersionKey -Build $_.Build }; Descending = $descending })
        }
        'Type' {
            return @($Builds | Sort-Object -Property @{ Expression = {
                $entryType = if ($null -ne $_.PSObject.Properties['EntryType']) { [string]$_.EntryType } else { Get-WibBuildEntryType -Title $_.Title }
                Get-WibBuildEntryTypeRank -EntryType $entryType
            }; Descending = $descending }, @{ Expression = { if ($null -eq $_.CreatedAt) { [datetime]::MinValue } else { $_.CreatedAt } }; Descending = $true }, @{ Expression = { ConvertTo-WibBuildVersionKey -Build $_.Build }; Descending = $true })
        }
        'Title' {
            return @($Builds | Sort-Object -Property @{ Expression = { [string]$_.Title }; Descending = $descending }, @{ Expression = { ConvertTo-WibBuildVersionKey -Build $_.Build }; Descending = $true })
        }
    }
}

function Test-WibInstallableBuildTitle {
    param([AllowNull()][string]$Title)

    $text = ([string]$Title).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    return ((Get-WibBuildEntryType -Title $text) -eq 'Windows')
}

function Get-WibNewestBuild {
    param([Parameter(Mandatory = $true)][object[]]$Builds)

    if ($Builds.Count -eq 0) { return $null }

    $installable = @($Builds | Where-Object { Test-WibInstallableBuildTitle -Title $_.Title })
    $candidates = if ($installable.Count -gt 0) { $installable } else { $Builds }

    # "Current" means the newest release family first, not the newest catalog
    # timestamp. This prevents an actively serviced old LTSC release (1809) or
    # an old development build with a larger base number (19564) from beating a
    # newer GA release such as Windows 10 22H2 (19045).
    $ranked = @(Sort-WibBuildByRelevance -Builds $candidates)
    if ($ranked.Count -eq 0) { return $null }
    return $ranked[0]
}

function Select-WibBuildSortInteractive {
    param(
        [Parameter(Mandatory = $true)][object[]]$Builds,
        [string]$CurrentColumn = 'Original',
        [string]$CurrentDirection = 'Ascending'
    )

    Write-Host ''
    Write-Host 'Сортировка:'
    Write-Host '1. Актуальность (новый выпуск -> новая сборка)'
    Write-Host '2. Сборка'
    Write-Host '3. Архитектура'
    Write-Host '4. Дата'
    Write-Host '5. Тип записи (сборки Windows / обновления)'
    Write-Host '6. Название'
    Write-Host '7. Исходный порядок'
    Write-Host '0. Отмена'
    $choice = Read-WibNumber -Prompt 'Столбец' -Minimum 0 -Maximum 7 -Default 1
    if ($choice -eq 0) {
        return [pscustomobject]@{ Builds = $Builds; Column = $CurrentColumn; Direction = $CurrentDirection }
    }

    $column = @('', 'Relevance', 'Build', 'Architecture', 'Date', 'Type', 'Title', 'Original')[$choice]
    if ($column -eq 'Original') {
        return [pscustomobject]@{ Builds = @(Sort-WibBuildCatalog -Builds $Builds -Column Original); Column = 'Original'; Direction = 'Ascending' }
    }

    if ($column -eq 'Relevance') {
        $direction = 'Descending'
        return [pscustomobject]@{ Builds = @(Sort-WibBuildCatalog -Builds $Builds -Column $column -Direction $direction); Column = $column; Direction = $direction }
    }

    if ($column -eq 'Type') {
        Write-Host '1. Сборки Windows сначала'
        Write-Host '2. Служебные обновления сначала'
        $directionChoice = Read-WibNumber -Prompt 'Порядок типов' -Minimum 1 -Maximum 2 -Default 1
    }
    else {
        Write-Host '1. По возрастанию'
        Write-Host '2. По убыванию'
        $directionChoice = Read-WibNumber -Prompt 'Направление' -Minimum 1 -Maximum 2 -Default 2
    }
    $direction = if ($directionChoice -eq 1) { 'Ascending' } else { 'Descending' }
    return [pscustomobject]@{ Builds = @(Sort-WibBuildCatalog -Builds $Builds -Column $column -Direction $direction); Column = $column; Direction = $direction }
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

    :SearchLoop while ($true) {
        Write-WibStage 'Поиск сборки Windows'
        $query = (Read-Host 'Введите версию, номер сборки или название, например 22H2, 19045, 22621').Trim()
        if ([string]::IsNullOrWhiteSpace($query)) {
            Write-Host 'Поисковый запрос не может быть пустым.' -ForegroundColor Yellow
            continue
        }

        $architecture = Select-WibArchitecture
        $includePreview = Read-WibYesNo -Prompt 'Показывать предварительные Insider/Preview-сборки?' -Default $false
        $includeServicing = Read-WibYesNo -Prompt 'Показывать служебные обновления (.NET, cumulative, OOBE и другие)?' -Default $false
        $builds = @(Search-WibBuilds -Search $query -Architecture $architecture -IncludePreview:$includePreview -CacheDirectory $CacheDirectory)
        if ($builds.Count -eq 0) {
            Write-Host 'Подходящие сборки не найдены. Измените запрос или фильтры.' -ForegroundColor Yellow
            continue
        }

        if (-not $includeServicing) {
            $unfilteredCount = $builds.Count
            $builds = @($builds | Where-Object {
                $entryType = if ($null -ne $_.PSObject.Properties['EntryType']) { [string]$_.EntryType } else { Get-WibBuildEntryType -Title $_.Title }
                $entryType -eq 'Windows'
            })
            if ($builds.Count -eq 0) {
                Write-Host 'Полноценные сборки Windows по этому запросу не найдены. Повторите поиск и разрешите показ служебных обновлений.' -ForegroundColor Yellow
                continue
            }
            $hiddenCount = $unfilteredCount - $builds.Count
            if ($hiddenCount -gt 0) {
                Write-Host ('Скрыто служебных и прочих записей: {0}.' -f $hiddenCount) -ForegroundColor DarkGray
            }
        }

        for ($originalIndex = 0; $originalIndex -lt $builds.Count; $originalIndex++) {
            if ($null -eq $builds[$originalIndex].PSObject.Properties['WibOriginalOrder']) {
                $builds[$originalIndex] | Add-Member -NotePropertyName WibOriginalOrder -NotePropertyValue $originalIndex
            }
        }

        $sortColumn = 'Relevance'
        $sortDirection = 'Descending'
        $builds = @(Sort-WibBuildCatalog -Builds $builds -Column $sortColumn -Direction $sortDirection)
        $pageSize = 40
        $pageCount = [int][Math]::Ceiling($builds.Count / [double]$pageSize)
        $pageIndex = 0

        :PageLoop while ($true) {
            $startIndex = $pageIndex * $pageSize
            $endIndex = [Math]::Min($startIndex + $pageSize - 1, $builds.Count - 1)
            $firstNumber = $startIndex + 1
            $lastNumber = $endIndex + 1

            Write-Host ''
            $sortColumnLabel = switch ($sortColumn) {
                'Relevance' { 'актуальность' }
                'Build' { 'сборка' }
                'Architecture' { 'архитектура' }
                'Date' { 'дата' }
                'Type' { 'тип записи' }
                'Title' { 'название' }
                default { 'исходный порядок' }
            }
            $sortLabel = if ($sortColumn -eq 'Original') { $sortColumnLabel } else { '{0} {1}' -f $sortColumnLabel, $(if ($sortDirection -eq 'Ascending') { '↑' } else { '↓' }) }
            Write-Host ('Найдено: {0}. Страница {1} из {2}. Показаны записи {3}-{4}. Сортировка: {5}.' -f $builds.Count, ($pageIndex + 1), $pageCount, $firstNumber, $lastNumber, $sortLabel)
            foreach ($line in (Get-WibBuildTableLines -Builds $builds -StartIndex $startIndex -EndIndex $endIndex)) {
                Write-Host $line
            }

            Write-Host ''
            Write-Host 'Команды: N/> — далее; P/< — назад; G — страница; S — сортировка; F — актуальная сборка; R — новый поиск; 0 — главное меню.' -ForegroundColor DarkGray
            $raw = (Read-Host "Номер сборки или команда [$firstNumber]").Trim()
            if ([string]::IsNullOrWhiteSpace($raw)) {
                return $builds[$startIndex]
            }

            switch -Regex ($raw.ToLowerInvariant()) {
                '^(0|q|quit|выход)$' { return $null }
                '^(r|search|поиск)$' { continue SearchLoop }
                '^(n|next|далее|>)$' {
                    if ($pageIndex -lt ($pageCount - 1)) {
                        $pageIndex++
                    }
                    else {
                        Write-Host 'Это последняя страница.' -ForegroundColor Yellow
                    }
                    continue PageLoop
                }
                '^(p|prev|previous|назад|<)$' {
                    if ($pageIndex -gt 0) {
                        $pageIndex--
                    }
                    else {
                        Write-Host 'Это первая страница.' -ForegroundColor Yellow
                    }
                    continue PageLoop
                }
                '^(g|page|страница)$' {
                    $pageNumber = Read-WibNumber -Prompt 'Номер страницы' -Minimum 1 -Maximum $pageCount -Default ($pageIndex + 1)
                    $pageIndex = $pageNumber - 1
                    continue PageLoop
                }
                '^(s|sort|сортировка)$' {
                    $sortResult = Select-WibBuildSortInteractive -Builds $builds -CurrentColumn $sortColumn -CurrentDirection $sortDirection
                    $builds = @($sortResult.Builds)
                    $sortColumn = $sortResult.Column
                    $sortDirection = $sortResult.Direction
                    $pageIndex = 0
                    continue PageLoop
                }
                '^(f|fresh|latest|newest|current|актуальная|свежая|последняя)$' {
                    $newest = Get-WibNewestBuild -Builds $builds
                    if ($null -ne $newest) {
                        $releaseText = if (-not [string]::IsNullOrWhiteSpace([string]$newest.VersionLabel)) { 'выпуск {0} | ' -f $newest.VersionLabel } else { '' }
                        Write-Host ('Выбрана актуальная сборка: {0} | {1}{2:yyyy-MM-dd} | {3}' -f $newest.Build, $releaseText, $newest.CreatedAt, $newest.Title) -ForegroundColor Cyan
                        return $newest
                    }
                    Write-Host 'Не удалось определить актуальную сборку.' -ForegroundColor Yellow
                    continue PageLoop
                }
            }

            $selection = 0
            if ([int]::TryParse($raw, [ref]$selection) -and $selection -ge $firstNumber -and $selection -le $lastNumber) {
                return $builds[$selection - 1]
            }

            Write-Host (
                'Введите номер от {0} до {1} либо команду N, P, G, S, F, R или 0.' -f $firstNumber, $lastNumber
            ) -ForegroundColor Yellow
        }
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
