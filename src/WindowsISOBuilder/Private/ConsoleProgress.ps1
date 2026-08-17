$script:WibConverterProgressActive = $false
$script:WibConverterProgressPercent = 0
$script:WibConverterBuildLogPath = ''
$script:WibConverterDetailLogPath = ''
$script:WibConverterProgressId = 71

function Invoke-WibNativeWriteHost {
    param(
        [AllowNull()][object[]]$Object,
        [object]$Separator = ' ',
        [AllowNull()][object]$ForegroundColor = $null,
        [AllowNull()][object]$BackgroundColor = $null,
        [switch]$NoNewline
    )

    $parameters = @{ Separator = $Separator }
    if ($null -ne $ForegroundColor) { $parameters.ForegroundColor = [ConsoleColor]$ForegroundColor }
    if ($null -ne $BackgroundColor) { $parameters.BackgroundColor = [ConsoleColor]$BackgroundColor }
    if ($NoNewline) { $parameters.NoNewline = $true }

    Microsoft.PowerShell.Utility\Write-Host -Object $Object @parameters
}

function Get-WibConverterDetailLogPath {
    if ([string]::IsNullOrWhiteSpace($script:WibConverterBuildLogPath)) {
        return ''
    }

    $directory = Split-Path -Parent $script:WibConverterBuildLogPath
    $name = [IO.Path]::GetFileNameWithoutExtension($script:WibConverterBuildLogPath)
    if ($name.StartsWith('build-', [StringComparison]::OrdinalIgnoreCase)) {
        $name = 'converter-' + $name.Substring(6)
    }
    else {
        $name = 'converter-' + $name
    }
    return (Join-Path $directory ($name + '.log'))
}

function Write-WibConverterDetailLine {
    param([AllowEmptyString()][string]$Line)

    if ([string]::IsNullOrWhiteSpace($script:WibConverterDetailLogPath)) {
        return
    }

    try {
        [IO.File]::AppendAllText(
            $script:WibConverterDetailLogPath,
            $Line + [Environment]::NewLine,
            (New-Object Text.UTF8Encoding($false))
        )
    }
    catch {
        # Detailed converter logging must never interrupt the build.
    }
}

function Set-WibConverterProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [int]$Percent = -1
    )

    if ($Percent -ge 0) {
        $script:WibConverterProgressPercent = [Math]::Max(
            $script:WibConverterProgressPercent,
            [Math]::Min(99, $Percent)
        )
    }

    Write-Progress `
        -Id $script:WibConverterProgressId `
        -Activity 'Загрузка Windows и создание ISO' `
        -Status $Status `
        -PercentComplete $script:WibConverterProgressPercent
}

function Start-WibConverterProgress {
    $script:WibConverterProgressActive = $true
    $script:WibConverterProgressPercent = 0
    $script:WibConverterDetailLogPath = Get-WibConverterDetailLogPath

    if (-not [string]::IsNullOrWhiteSpace($script:WibConverterDetailLogPath)) {
        try {
            Remove-Item -LiteralPath $script:WibConverterDetailLogPath -Force -ErrorAction SilentlyContinue
        }
        catch { }
        Invoke-WibNativeWriteHost `
            -Object @('[INFO] Подробный вывод конвертера: ' + $script:WibConverterDetailLogPath) `
            -ForegroundColor ([ConsoleColor]::DarkGray)
    }

    Set-WibConverterProgress -Status 'Подготовка загрузки...' -Percent 0
}

function Stop-WibConverterProgress {
    if ($script:WibConverterProgressActive) {
        Write-Progress -Id $script:WibConverterProgressId -Activity 'Загрузка Windows и создание ISO' -Completed
    }
    $script:WibConverterProgressActive = $false
    $script:WibConverterProgressPercent = 0
}

function Update-WibConverterProgressFromLine {
    param([AllowEmptyString()][string]$Line)

    Write-WibConverterDetailLine -Line $Line
    $text = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    $percentageMatch = [regex]::Match($text, '\((?<percent>\d{1,3})%\)')
    if ($percentageMatch.Success) {
        $downloadPercent = [Math]::Max(0, [Math]::Min(100, [int]$percentageMatch.Groups['percent'].Value))
        $overallPercent = 15 + [int][Math]::Floor($downloadPercent * 0.65)
        $speedMatch = [regex]::Match($text, '(?i)\bDL:(?<speed>[^\s\]]+)')
        $status = 'Загрузка файлов Windows: {0}%' -f $downloadPercent
        if ($speedMatch.Success -and $speedMatch.Groups['speed'].Value -ne '0B') {
            $status += ' — ' + $speedMatch.Groups['speed'].Value
        }
        Set-WibConverterProgress -Status $status -Percent $overallPercent
        return
    }

    switch -Regex ($text) {
        '(?i)^Downloading aria2c\.exe' {
            Set-WibConverterProgress -Status 'Подготовка менеджера загрузки...' -Percent 2
            return
        }
        '(?i)^Verifying aria2c\.exe' {
            Set-WibConverterProgress -Status 'Проверка менеджера загрузки...' -Percent 3
            return
        }
        '(?i)^Downloading the UUP converter' {
            Set-WibConverterProgress -Status 'Загрузка конвертера UUP...' -Percent 5
            return
        }
        '(?i)^Extracting UUP converter' {
            Set-WibConverterProgress -Status 'Распаковка конвертера UUP...' -Percent 8
            return
        }
        '(?i)^Retrieving aria2 script' {
            Set-WibConverterProgress -Status 'Получение списка файлов Microsoft...' -Percent 10
            return
        }
        '(?i)^Downloading the UUP set' {
            Set-WibConverterProgress -Status 'Загрузка файлов Windows...' -Percent 15
            return
        }
        '(?i)download completed|download complete|downloads complete' {
            Set-WibConverterProgress -Status 'Файлы Windows загружены.' -Percent 80
            return
        }
        '(?i)adding updates|integrating updates|applying updates|update integration' {
            Set-WibConverterProgress -Status 'Интеграция обновлений...' -Percent 84
            return
        }
        '(?i)cleanup|component cleanup' {
            Set-WibConverterProgress -Status 'Очистка компонентов...' -Percent 88
            return
        }
        '(?i)creating.*install|converting.*(wim|esd)|wim2esd|exporting.*image|compressing.*image' {
            Set-WibConverterProgress -Status 'Создание install-образа...' -Percent 91
            return
        }
        '(?i)creating.*iso|iso image|oscdimg|cdimage' {
            Set-WibConverterProgress -Status 'Создание ISO...' -Percent 96
            return
        }
    }
}

# The UUP dump batch file is invoked by Builder.ps1 and its stdout is piped to
# Write-Host. Shadow Write-Host only inside this module so converter chatter can
# be written to a detailed log while the console displays a single progress bar.
function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [object[]]$Object,
        [object]$Separator = ' ',
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [switch]$NoNewline
    )

    process {
        $text = if ($null -eq $Object) {
            ''
        }
        else {
            (($Object | ForEach-Object { [string]$_ }) -join [string]$Separator)
        }
        $trimmed = $text.Trim()

        if ($trimmed -match '^Лог:\s*(?<path>.+\.log)\s*$') {
            $script:WibConverterBuildLogPath = $Matches['path'].Trim()
        }

        $foreground = if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $ForegroundColor } else { $null }
        $background = if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $BackgroundColor } else { $null }

        if ($trimmed -eq '=== Загрузка файлов Microsoft и создание ISO ===') {
            Invoke-WibNativeWriteHost `
                -Object $Object `
                -Separator $Separator `
                -ForegroundColor $foreground `
                -BackgroundColor $background `
                -NoNewline:$NoNewline
            Start-WibConverterProgress
            return
        }

        if ($script:WibConverterProgressActive -and $trimmed -eq '=== Проверка результата ===') {
            Stop-WibConverterProgress
            Invoke-WibNativeWriteHost `
                -Object $Object `
                -Separator $Separator `
                -ForegroundColor $foreground `
                -BackgroundColor $background `
                -NoNewline:$NoNewline
            return
        }

        if ($script:WibConverterProgressActive -and $trimmed -match '^ОШИБКА СБОРКИ:') {
            Write-WibConverterDetailLine -Line $text
            Stop-WibConverterProgress
            Invoke-WibNativeWriteHost `
                -Object $Object `
                -Separator $Separator `
                -ForegroundColor $foreground `
                -BackgroundColor $background `
                -NoNewline:$NoNewline
            return
        }

        if ($script:WibConverterProgressActive) {
            Update-WibConverterProgressFromLine -Line $text
            return
        }

        Invoke-WibNativeWriteHost `
            -Object $Object `
            -Separator $Separator `
            -ForegroundColor $foreground `
            -BackgroundColor $background `
            -NoNewline:$NoNewline
    }
}
