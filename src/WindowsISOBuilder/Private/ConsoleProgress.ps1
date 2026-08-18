$script:WibConverterProgressActive = $false
$script:WibConverterProgressPercent = 0
$script:WibConverterBuildLogPath = ''
$script:WibConverterDetailLogPath = ''
$script:WibConverterProgressId = 71
$script:WibConverterEventStage = ''

function Invoke-WibNativeWriteHost {
    param([AllowNull()][object[]]$Object,[object]$Separator=' ',[AllowNull()][object]$ForegroundColor=$null,[AllowNull()][object]$BackgroundColor=$null,[switch]$NoNewline)
    $parameters=@{ Separator=$Separator }; if ($null -ne $ForegroundColor) { $parameters.ForegroundColor=[ConsoleColor]$ForegroundColor }; if ($null -ne $BackgroundColor) { $parameters.BackgroundColor=[ConsoleColor]$BackgroundColor }; if ($NoNewline) { $parameters.NoNewline=$true }
    Microsoft.PowerShell.Utility\Write-Host -Object $Object @parameters
}
function Get-WibConverterDetailLogPath { if ([string]::IsNullOrWhiteSpace($script:WibConverterBuildLogPath)) { return '' }; $directory=Split-Path -Parent $script:WibConverterBuildLogPath; $name=[IO.Path]::GetFileNameWithoutExtension($script:WibConverterBuildLogPath); if ($name.StartsWith('build-',[StringComparison]::OrdinalIgnoreCase)) { $name='converter-'+$name.Substring(6) } else { $name='converter-'+$name }; return (Join-Path $directory ($name+'.log')) }
function Write-WibConverterDetailLine { param([AllowEmptyString()][string]$Line); if ([string]::IsNullOrWhiteSpace($script:WibConverterDetailLogPath)) { return }; try { [IO.File]::AppendAllText($script:WibConverterDetailLogPath,$Line+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false))) } catch { } }
function Set-WibConverterProgress { param([Parameter(Mandatory=$true)][string]$Status,[int]$Percent=-1); if ($Percent -ge 0) { $script:WibConverterProgressPercent=[Math]::Max($script:WibConverterProgressPercent,[Math]::Min(99,$Percent)) }; Write-Progress -Id $script:WibConverterProgressId -Activity 'Загрузка Windows и создание ISO' -Status $Status -PercentComplete $script:WibConverterProgressPercent }
function ConvertFrom-WibSpeedText { param([AllowNull()][string]$SpeedText); if ([string]::IsNullOrWhiteSpace($SpeedText)) { return $null }; $match=[regex]::Match($SpeedText.Trim(), '(?i)^(?<value>\d+(?:\.\d+)?)(?<unit>B|KiB|MiB|GiB|KB|MB|GB)(?:/s)?$'); if (-not $match.Success) { return $null }; $number=0.0; if (-not [double]::TryParse($match.Groups['value'].Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)) { return $null }; $factor=switch ($match.Groups['unit'].Value.ToUpperInvariant()) { 'B'{1};'KIB'{1KB};'MIB'{1MB};'GIB'{1GB};'KB'{1000};'MB'{1000000};'GB'{1000000000};default{return $null} }; try { return [int64][Math]::Round($number*$factor) } catch { return $null } }

function ConvertFrom-WibConverterProgressLine {
    param([AllowEmptyString()][string]$Line)
    $text=$Line.Trim(); if ([string]::IsNullOrWhiteSpace($text)) { return $null }; $percentageMatch=[regex]::Match($text,'\((?<percent>\d{1,3})%\)')
    if ($percentageMatch.Success) { $downloadPercent=[Math]::Max(0,[Math]::Min(100,[int]$percentageMatch.Groups['percent'].Value)); $overallPercent=15+[int][Math]::Floor($downloadPercent*0.65); $speedMatch=[regex]::Match($text,'(?i)\bDL:(?<speed>[^\s\]]+)'); $speedText=$null; $status='Загрузка файлов Windows: {0}%' -f $downloadPercent; if ($speedMatch.Success -and $speedMatch.Groups['speed'].Value -ne '0B') { $speedText=$speedMatch.Groups['speed'].Value; $status+=' — '+$speedText }; return [pscustomobject]@{ Status=$status; Percent=$overallPercent; DetailPercent=$downloadPercent; SpeedText=$speedText; SpeedBytesPerSecond=(ConvertFrom-WibSpeedText $speedText); Stage='download' } }
    switch -Regex ($text) {
        '(?i)^Downloading aria2c\.exe' { return [pscustomobject]@{ Status='Подготовка менеджера загрузки...'; Percent=2; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='download' } }
        '(?i)^Verifying aria2c\.exe' { return [pscustomobject]@{ Status='Проверка менеджера загрузки...'; Percent=3; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='download' } }
        '(?i)^Downloading the UUP converter' { return [pscustomobject]@{ Status='Загрузка конвертера UUP...'; Percent=5; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='download' } }
        '(?i)^Extracting UUP converter' { return [pscustomobject]@{ Status='Распаковка конвертера UUP...'; Percent=8; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='download' } }
        '(?i)^Retrieving aria2 script' { return [pscustomobject]@{ Status='Получение списка файлов Microsoft...'; Percent=10; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='download' } }
        '(?i)^Downloading the UUP set' { return [pscustomobject]@{ Status='Загрузка файлов Windows...'; Percent=15; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='download' } }
        '(?i)download completed|download complete|downloads complete' { return [pscustomobject]@{ Status='Файлы Windows загружены.'; Percent=80; DetailPercent=100; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='download' } }
        '(?i)adding updates|integrating updates|applying updates|update integration' { return [pscustomobject]@{ Status='Интеграция обновлений...'; Percent=84; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='convert' } }
        '(?i)cleanup|component cleanup' { return [pscustomobject]@{ Status='Очистка компонентов...'; Percent=88; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='convert' } }
        '(?i)creating.*install|converting.*(wim|esd)|wim2esd|exporting.*image|compressing.*image' { return [pscustomobject]@{ Status='Создание install-образа...'; Percent=91; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='convert' } }
        '(?i)creating.*iso|iso image|oscdimg|cdimage' { return [pscustomobject]@{ Status='Создание ISO...'; Percent=96; DetailPercent=$null; SpeedText=$null; SpeedBytesPerSecond=$null; Stage='convert' } }
    }
    return $null
}
function Start-WibConverterProgress { $script:WibConverterProgressActive=$true; $script:WibConverterProgressPercent=0; $script:WibConverterEventStage=''; $script:WibConverterDetailLogPath=Get-WibConverterDetailLogPath; if (-not [string]::IsNullOrWhiteSpace($script:WibConverterDetailLogPath)) { try { Remove-Item -LiteralPath $script:WibConverterDetailLogPath -Force -ErrorAction SilentlyContinue } catch { }; Invoke-WibNativeWriteHost -Object @('[INFO] Подробный вывод конвертера: '+$script:WibConverterDetailLogPath) -ForegroundColor ([ConsoleColor]::DarkGray) }; Set-WibConverterProgress -Status 'Подготовка загрузки...' -Percent 0 }
function Stop-WibConverterProgress { if ($script:WibConverterProgressActive) { Write-Progress -Id $script:WibConverterProgressId -Activity 'Загрузка Windows и создание ISO' -Completed }; $script:WibConverterProgressActive=$false; $script:WibConverterProgressPercent=0; $script:WibConverterEventStage='' }
function Get-WibConverterCurrentStage { if (-not [string]::IsNullOrWhiteSpace($script:WibConverterEventStage)) { return $script:WibConverterEventStage }; return 'download' }
function Update-WibConverterProgressFromLine { param([AllowEmptyString()][string]$Line); Write-WibConverterDetailLine -Line $Line; $progress=ConvertFrom-WibConverterProgressLine -Line $Line; if ($null -eq $progress) { return }; Set-WibConverterProgress -Status $progress.Status -Percent $progress.Percent; if ($script:WibConverterEventStage -ne $progress.Stage) { $script:WibConverterEventStage=$progress.Stage; Publish-WibEvent -Type 'stage' -Stage $progress.Stage -Message $progress.Status | Out-Null }; $detailPercent=if ($null -eq $progress.DetailPercent) {-1}else{[int]$progress.DetailPercent}; $speedBytes=if ($null -eq $progress.SpeedBytesPerSecond){-1}else{[int64]$progress.SpeedBytesPerSecond}; Publish-WibEvent -Type 'progress' -Stage $progress.Stage -Message $progress.Status -Percent ([int]$progress.Percent) -DetailPercent $detailPercent -SpeedText $progress.SpeedText -SpeedBytesPerSecond $speedBytes | Out-Null }

function Write-Host {
    [CmdletBinding()]
    param([Parameter(Position=0,ValueFromPipeline=$true)][AllowNull()][object[]]$Object,[object]$Separator=' ',[ConsoleColor]$ForegroundColor,[ConsoleColor]$BackgroundColor,[switch]$NoNewline)
    process {
        $text=if ($null -eq $Object){''}else{(($Object|ForEach-Object{[string]$_}) -join [string]$Separator)}; $trimmed=$text.Trim(); if ($trimmed -match '^Лог:\s*(?<path>.+\.log)\s*$') { $script:WibConverterBuildLogPath=$Matches['path'].Trim() }; $foreground=if($PSBoundParameters.ContainsKey('ForegroundColor')){$ForegroundColor}else{$null}; $background=if($PSBoundParameters.ContainsKey('BackgroundColor')){$BackgroundColor}else{$null}
        if ($trimmed -eq '=== Загрузка файлов Microsoft и создание ISO ===') { Invoke-WibNativeWriteHost -Object $Object -Separator $Separator -ForegroundColor $foreground -BackgroundColor $background -NoNewline:$NoNewline; Start-WibConverterProgress; return }
        if ($script:WibConverterProgressActive -and $trimmed -eq '=== Проверка результата ===') { Stop-WibConverterProgress; Invoke-WibNativeWriteHost -Object $Object -Separator $Separator -ForegroundColor $foreground -BackgroundColor $background -NoNewline:$NoNewline; return }
        if ($script:WibConverterProgressActive -and ($trimmed -match '^ОШИБКА СБОРКИ:' -or $trimmed -match '^СБОРКА ОТМЕНЕНА:')) { Write-WibConverterDetailLine -Line $text; Stop-WibConverterProgress; Invoke-WibNativeWriteHost -Object $Object -Separator $Separator -ForegroundColor $foreground -BackgroundColor $background -NoNewline:$NoNewline; return }
        if ($script:WibConverterProgressActive) { Update-WibConverterProgressFromLine -Line $text; return }
        Invoke-WibNativeWriteHost -Object $Object -Separator $Separator -ForegroundColor $foreground -BackgroundColor $background -NoNewline:$NoNewline
    }
}
