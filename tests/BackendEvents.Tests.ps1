$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Backend Contract events' {
    InModuleScope WindowsISOBuilder {
        AfterEach { Reset-WibEventSink }

        It 'writes one valid JSON object per NDJSON line with monotonic sequence' {
            $eventPath = Join-Path $TestDrive 'events.ndjson'
            Initialize-WibEventSink -RequestId 'event-request' -EventFile $eventPath | Should -BeTrue
            Publish-WibEvent -Type stage -Stage startup -Message 'start' -Percent 0 | Should -BeTrue
            Publish-WibEvent -Type progress -Stage download -Message 'download' -Percent 20 -DetailPercent 5 | Should -BeTrue
            Publish-WibEvent -Type completed -Stage completed -Message 'done' -Percent 100 | Should -BeTrue

            $lines = @(Get-Content -LiteralPath $eventPath -Encoding UTF8 | Where-Object { $_ })
            $lines.Count | Should -Be 3
            $events = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
            @($events.sequence) | Should -Be @(1,2,3)
            @($events.requestId | Select-Object -Unique) | Should -Be @('event-request')
            @($events.schemaVersion | Select-Object -Unique) | Should -Be @(1)
            @($events.type) | Should -Be @('stage','progress','completed')
        }

        It 'continues sequence when an elevated child appends to the same file' {
            $eventPath = Join-Path $TestDrive 'append.ndjson'
            Initialize-WibEventSink -RequestId 'same-request' -EventFile $eventPath | Out-Null
            Publish-WibEvent stage startup 'parent' | Out-Null
            Reset-WibEventSink
            Initialize-WibEventSink -RequestId 'same-request' -EventFile $eventPath -Append | Should -BeTrue
            Publish-WibEvent progress download 'child' -Percent 30 | Out-Null
            $events = @(Get-Content $eventPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
            $events[0].sequence | Should -Be 1
            $events[1].sequence | Should -Be 2
            $events[1].requestId | Should -Be 'same-request'
        }

        It 'never decreases overall progress' {
            $eventPath = Join-Path $TestDrive 'monotonic.ndjson'
            Initialize-WibEventSink -RequestId 'monotonic' -EventFile $eventPath | Out-Null
            Publish-WibEvent progress download 'first' -Percent 70 | Out-Null
            Publish-WibEvent progress download 'late line' -Percent 20 | Out-Null
            $events = @(Get-Content $eventPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
            $events[0].progress.percent | Should -Be 70
            $events[1].progress.percent | Should -Be 70
        }

        It 'does not throw when event writing fails' {
            $eventPath = Join-Path $TestDrive 'broken.ndjson'
            Initialize-WibEventSink -RequestId 'best-effort' -EventFile $eventPath | Should -BeTrue
            Remove-Item -LiteralPath $eventPath -Force
            New-Item -ItemType Directory -Path $eventPath | Out-Null
            { Publish-WibEvent progress download 'telemetry' -Percent 25 | Out-Null } | Should -Not -Throw
            Publish-WibEvent progress download 'telemetry' -Percent 25 | Should -BeFalse
        }

        It 'maps internal build stages to the documented contract vocabulary' {
            ConvertTo-WibContractStage 'downloading-package' | Should -Be 'metadata'
            ConvertTo-WibContractStage 'downloading-uup-and-converting' | Should -Be 'download'
            ConvertTo-WibContractStage 'validating' | Should -Be 'verify'
            ConvertTo-WibContractStage 'completed' | Should -Be 'completed'
            ConvertTo-WibContractStage 'failed' | Should -Be 'failed'
        }

        It 'uses the existing converter parser for structured progress' {
            $progress = ConvertFrom-WibConverterProgressLine '[#abc 1.0GiB/2.0GiB(50%) CN:16 DL:31MiB ETA:33s]'
            $progress.Status | Should -Be 'Загрузка файлов Windows: 50% — 31MiB'
            $progress.Percent | Should -Be 47
            $progress.DetailPercent | Should -Be 50
            $progress.SpeedText | Should -Be '31MiB'
            $progress.SpeedBytesPerSecond | Should -Be 32505856
            $progress.Stage | Should -Be 'download'
        }

        It 'treats speed parsing as optional telemetry' {
            { ConvertFrom-WibSpeedText 'not-a-speed' } | Should -Not -Throw
            ConvertFrom-WibSpeedText 'not-a-speed' | Should -BeNullOrEmpty
            $progress = ConvertFrom-WibConverterProgressLine '[#abc 1/2(40%) CN:1 DL:weird ETA:1s]'
            $progress.Percent | Should -Be 41
            $progress.SpeedBytesPerSecond | Should -BeNullOrEmpty
        }

        It 'publishes parsed converter progress without changing console progress behavior' {
            Mock Set-WibConverterProgress { }
            $eventPath = Join-Path $TestDrive 'converter.ndjson'
            Initialize-WibEventSink -RequestId 'converter' -EventFile $eventPath | Out-Null
            Update-WibConverterProgressFromLine '[#abc 1/2(50%) CN:1 DL:12MiB ETA:1s]'
            Assert-MockCalled Set-WibConverterProgress -Times 1 -Exactly -ParameterFilter { $Status -eq 'Загрузка файлов Windows: 50% — 12MiB' -and $Percent -eq 47 }
            $events = @(Get-Content $eventPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
            @($events | Where-Object type -eq 'progress').Count | Should -Be 1
            ($events | Where-Object type -eq 'progress').progress.detailPercent | Should -Be 50
        }
    }
}

Describe 'Progress parser static regression' {
    It 'keeps raw aria2 parsing out of Backend Contract transport files' {
        $contractFiles = @(
            '..\src\WindowsISOBuilder\Private\BackendContract.ps1',
            '..\src\WindowsISOBuilder\Private\BackendCommands.ps1',
            '..\src\WindowsISOBuilder\Private\BackendEvents.ps1'
        )
        foreach ($relative in $contractFiles) {
            (Get-Content -LiteralPath (Join-Path $PSScriptRoot $relative) -Raw -Encoding UTF8) | Should -Not -Match '\\bDL:'
        }
        $progressSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\Private\ConsoleProgress.ps1') -Raw -Encoding UTF8
        $progressSource | Should -Match 'ConvertFrom-WibConverterProgressLine'
        $progressSource | Should -Match 'Publish-WibEvent'
    }
}
