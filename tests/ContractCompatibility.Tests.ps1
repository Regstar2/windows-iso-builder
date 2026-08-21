$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'v0.3.4 release version baseline' {
    It 'keeps VERSION and ModuleVersion aligned with the release plan' {
        $root = Split-Path -Parent $PSScriptRoot
        $applicationVersion = [IO.File]::ReadAllText((Join-Path $root 'VERSION'), [Text.Encoding]::ASCII).Trim()
        $manifest = Test-ModuleManifest -Path (Join-Path $root 'src\WindowsISOBuilder\WindowsISOBuilder.psd1')
        $applicationVersion | Should -Be '0.3.4'
        [string]$manifest.Version | Should -Be '0.3.0'
    }

    InModuleScope WindowsISOBuilder {
        It 'keeps Backend Contract and BuildPlan schema versions at 1' {
            $script:WibBackendContractSchemaVersion | Should -Be 1
            $script:WibBuildPlanSchemaVersion | Should -Be 1
        }
    }
}

Describe 'Backend Contract v1 semantic compatibility baseline' {
    InModuleScope WindowsISOBuilder {
        BeforeEach {
            $script:compatBuild = [pscustomobject]@{
                Uuid='compat-build'; Title='Windows 11 compatibility fixture'; Product='Windows 11';
                VersionLabel='fixture'; Build='0.0'; BuildVersion=[version]'0.0'; Architecture='amd64';
                EntryType='Windows'; CreatedAt=[datetime]'2026-08-18T00:00:00Z'; Created=1L; IsPreview=$false
            }
            $script:compatPlan = [pscustomobject][ordered]@{
                SchemaVersion=1; ApplicationVersion='0.2.3-alpha.1'; CreatedAt='2026-08-18T00:00:00Z';
                Build=[pscustomobject]@{ Uuid='compat-build'; Title='Windows 11 compatibility fixture'; Product='Windows 11'; VersionLabel='fixture'; Build='0.0'; Architecture='amd64'; IsPreview=$false };
                Language='ru-ru'; Editions=@('Professional'); SourceEdition='Professional'; VirtualEditions=@();
                ImageFormat='ESD'; AddUpdates=$true; Cleanup=$true; NetFx3=$false;
                OutputDirectory=$TestDrive; CacheDirectory=$TestDrive; RemoveWorkAfterSuccess=$false
            }
        }

        It 'retains all baseline command names' {
            foreach ($command in @('GetVersion','SearchBuilds','GetRecommendedBuild','GetLanguages','GetEditions','CreateBuildPlan','ValidateBuildPlan','ExecuteBuildPlan','RunPreflight','CancelBuild')) { $script:WibBackendCommands | Should -Contain $command }
        }

        It 'retains required success envelope fields while allowing additive fields' {
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='compat-success'; command='GetVersion'; arguments=[pscustomobject]@{} })
            foreach ($name in @('schemaVersion','requestId','command','success','applicationVersion','data')) { $response.PSObject.Properties.Name | Should -Contain $name }
            $response.schemaVersion | Should -Be 1; $response.success | Should -BeTrue
        }

        It 'retains required failure envelope fields while allowing additive fields' {
            $failure = New-WibErrorException -Code 'INVALID_ARGUMENT' -Message 'controlled failure' -Stage 'plan'
            $error = ConvertTo-WibBackendErrorDto -Failure $failure -Command 'CreateBuildPlan'
            $response = New-WibBackendResponse -RequestId 'compat-failure' -Command 'CreateBuildPlan' -Success $false -Payload $error
            foreach ($name in @('schemaVersion','requestId','command','success','applicationVersion','error')) { $response.PSObject.Properties.Name | Should -Contain $name }
            foreach ($name in @('code','message','stage','details','logPath')) { $response.error.PSObject.Properties.Name | Should -Contain $name }
            $response.error.code | Should -Be 'INVALID_ARGUMENT'
        }

        It 'retains the required build DTO fields' {
            $dto = ConvertTo-WibBuildDto $script:compatBuild
            foreach ($name in @('uuid','title','product','versionLabel','build','architecture','entryType','createdAt','isPreview')) { $dto.PSObject.Properties.Name | Should -Contain $name }
        }

        It 'retains the required BuildResult DTO fields' {
            $dto = ConvertTo-WibBuildResultDto ([pscustomobject]@{ Stage='completed'; IsoPath='C:\out.iso'; Sha256='abc'; LogPath='C:\build.log'; ExecutionLogPath='C:\execution.log'; WorkDirectory='C:\work'; MetadataPath='C:\out.iso.json' })
            foreach ($name in @('stage','isoPath','sha256','logPath','executionLogPath','workDirectory','metadataPath')) { $dto.PSObject.Properties.Name | Should -Contain $name }
        }

        It 'retains the required preflight report and check fields' {
            Mock Invoke-WibPreflight { [pscustomobject][ordered]@{ ready=$false; checks=@([pscustomobject][ordered]@{ id='disk.cache'; status='fail'; severity='error'; code='DISK_SPACE_LOW'; message='low'; data=[pscustomobject]@{ availableBytes=1L; requiredBytes=2L } }) } }
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='compat-preflight'; command='RunPreflight'; arguments=[pscustomobject]@{ buildPlan=(ConvertTo-WibBuildPlanDto $script:compatPlan); onlineChecks=$false } })
            foreach ($name in @('ready','checks')) { $response.data.PSObject.Properties.Name | Should -Contain $name }
            foreach ($name in @('id','status','severity','code','message','data')) { $response.data.checks[0].PSObject.Properties.Name | Should -Contain $name }
        }

        It 'preserves structured failure-injection error codes' {
            foreach ($code in @('DISK_SPACE_LOW','PATH_NOT_WRITABLE','UUP_API_UNAVAILABLE','UUP_PACKAGE_INVALID','CONVERTER_FAILED','ISO_NOT_FOUND','BUILD_CANCELLED')) {
                $failure = New-WibErrorException -Code $code -Message 'controlled failure' -Stage 'preflight'; $dto = ConvertTo-WibBackendErrorDto -Failure $failure -Command 'ExecuteBuildPlan'; $dto.code | Should -Be $code
            }
        }

        It 'retains required progress and cancelled event fields' {
            $eventPath = Join-Path $TestDrive 'compat-events.ndjson'; Initialize-WibEventSink -RequestId 'compat-events' -EventFile $eventPath | Should -BeTrue
            try {
                Publish-WibEvent -Type progress -Stage download -Message 'progress' -Percent 25 -DetailPercent 10 | Should -BeTrue
                Publish-WibEvent -Type cancelled -Stage convert -Message 'cancelled' -Percent 25 | Should -BeTrue
                $events = @(Get-Content -LiteralPath $eventPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json }); $events.Count | Should -Be 2
                foreach ($event in $events) { foreach ($name in @('schemaVersion','requestId','sequence','timestamp','type','stage','message','progress')) { $event.PSObject.Properties.Name | Should -Contain $name } }
                $events[0].type | Should -Be 'progress'; $events[1].type | Should -Be 'cancelled'
                foreach ($name in @('percent','detailPercent','speedText','speedBytesPerSecond')) { $events[0].progress.PSObject.Properties.Name | Should -Contain $name }
            }
            finally { Reset-WibEventSink }
        }
    }
}

Describe 'BuildPlan Schema v1 fixture compatibility' {
    InModuleScope WindowsISOBuilder {
        It 'reads, validates and round-trips the v1 fixture without losing required data' {
            $fixturePath = Join-Path $script:ProjectRoot 'tests\fixtures\build-plan-v1.json'; $fixture = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json; $plan = ConvertFrom-WibBuildPlanDto $fixture
            { Assert-WibPlan $plan } | Should -Not -Throw; $roundTrip = ConvertTo-WibBuildPlanDto $plan
            $roundTrip.schemaVersion | Should -Be 1; $roundTrip.build.uuid | Should -Be $fixture.build.uuid; $roundTrip.language | Should -Be $fixture.language; @($roundTrip.editions) | Should -Be @($fixture.editions); $roundTrip.sourceEdition | Should -Be $fixture.sourceEdition; $roundTrip.imageFormat | Should -Be $fixture.imageFormat
        }

        It 'accepts the v1 fixture through ValidateBuildPlan' {
            $fixturePath = Join-Path $script:ProjectRoot 'tests\fixtures\build-plan-v1.json'; $fixture = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='fixture-validate'; command='ValidateBuildPlan'; arguments=[pscustomobject]@{ plan=$fixture } })
            $response.success | Should -BeTrue; $response.data.valid | Should -BeTrue
        }
    }
}

Describe 'Request fixture compatibility' {
    It 'keeps the GetVersion v1 request fixture valid' {
        $requestPath = Join-Path $PSScriptRoot 'fixtures\backend\get-version-request-v1.json'; $request = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $request.schemaVersion | Should -Be 1; $request.command | Should -Be 'GetVersion'; $request.requestId | Should -Not -BeNullOrEmpty; ($null -ne $request.arguments) | Should -BeTrue
    }
}
