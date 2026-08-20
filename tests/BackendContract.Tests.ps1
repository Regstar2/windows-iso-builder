$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Backend Contract v1' {
    InModuleScope WindowsISOBuilder {
        BeforeEach {
            $script:testBuild = [pscustomobject]@{ Uuid='update-1'; Title='Windows 11, version 25H2 (26200.1)'; Product='Windows 11'; VersionLabel='25H2'; Build='26200.1'; BuildVersion=[version]'26200.1'; Architecture='amd64'; EntryType='Windows'; CreatedAt=[datetime]'2026-08-01T00:00:00Z'; Created=1L; IsPreview=$false }
            $script:testPlan = [pscustomobject][ordered]@{ SchemaVersion=1; ApplicationVersion='0.4.0-alpha.1'; CreatedAt='2026-08-18T00:00:00Z'; Build=[pscustomobject]@{ Uuid='update-1'; Title='Windows 11, version 25H2 (26200.1)'; Product='Windows 11'; VersionLabel='25H2'; Build='26200.1'; Architecture='amd64'; IsPreview=$false }; Language='ru-ru'; Editions=@('Core','Professional'); SourceEdition='Core'; VirtualEditions=@('Professional'); ImageFormat='ESD'; AddUpdates=$true; Cleanup=$true; NetFx3=$false; OutputDirectory=$TestDrive; CacheDirectory=$TestDrive; RemoveWorkAfterSuccess=$false }
        }

        It 'returns GetVersion with distinct application and schema versions' {
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='get-version'; command='GetVersion'; arguments=[pscustomobject]@{} })
            $response.success | Should -BeTrue
            $response.requestId | Should -Be 'get-version'
            $response.applicationVersion | Should -Be '0.4.0-alpha.1'
            $response.data.applicationVersion | Should -Be '0.4.0-alpha.1'
            $response.data.contractSchemaVersion | Should -Be 1
            $response.data.buildPlanSchemaVersion | Should -Be 1
        }

        It 'accepts schemaVersion 1 and preserves requestId exactly' {
            $requestId = 'Client-ID:AbC-123'
            (Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId=$requestId; command='GetVersion'; arguments=[pscustomobject]@{} })).requestId | Should -BeExactly $requestId
        }

        It 'rejects unsupported schema with UNSUPPORTED_SCHEMA' {
            try { Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=2; requestId='x'; command='GetVersion'; arguments=[pscustomobject]@{} }); throw 'expected failure' } catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'UNSUPPORTED_SCHEMA' }
        }

        It 'rejects missing command with INVALID_REQUEST' {
            try { Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='x'; arguments=[pscustomobject]@{} }); throw 'expected failure' } catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'INVALID_REQUEST' }
        }

        It 'rejects unknown command with INVALID_COMMAND' {
            try { Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='x'; command='Invoke-Something'; arguments=[pscustomobject]@{} }); throw 'expected failure' } catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'INVALID_COMMAND' }
        }

        It 'rejects invalid command arguments with INVALID_ARGUMENT' {
            try { Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='x'; command='SearchBuilds'; arguments=[pscustomobject]@{ search=7 } }); throw 'expected failure' } catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'INVALID_ARGUMENT' }
        }

        It 'SearchBuilds calls existing core and returns controlled build DTOs' {
            Mock Search-WibBuilds { @($script:testBuild) }
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='search'; command='SearchBuilds'; arguments=[pscustomobject]@{ search='Windows 11 25H2'; architecture='amd64'; includePreview=$false; forceRefresh=$false; cacheDirectory=$TestDrive } })
            Assert-MockCalled Search-WibBuilds -Times 1 -Exactly -ParameterFilter { $Search -eq 'Windows 11 25H2' -and $Architecture -eq 'amd64' }
            $response.data.builds.Count | Should -Be 1
            $response.data.builds[0].uuid | Should -Be 'update-1'
            $response.data.builds[0].PSObject.Properties.Name | Should -Not -Contain 'BuildVersion'
            $response.data.builds[0].PSObject.Properties.Name | Should -Contain 'createdAt'
        }

        It 'SearchBuilds empty result is success with an empty array' {
            Mock Search-WibBuilds { @() }
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='empty'; command='SearchBuilds'; arguments=[pscustomobject]@{ search='none' } })
            $response.success | Should -BeTrue
            @($response.data.builds).Count | Should -Be 0
        }

        It 'GetRecommendedBuild uses shared quick-mode selection logic' {
            Mock Get-WibQuickLatestBuild { $script:testBuild }
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='recommended'; command='GetRecommendedBuild'; arguments=[pscustomobject]@{ product='Windows 11'; architecture='amd64'; forceRefresh=$true; cacheDirectory=$TestDrive } })
            Assert-MockCalled Get-WibQuickLatestBuild -Times 1 -Exactly -ParameterFilter { $Product -eq 'Windows 11' -and $Architecture -eq 'amd64' -and $ForceRefresh }
            $response.data.build.uuid | Should -Be 'update-1'
        }

        It 'GetLanguages returns language DTOs' {
            Mock Get-WibLanguages { @([pscustomobject]@{ Code='ru-ru'; Name='Russian' }) }
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='langs'; command='GetLanguages'; arguments=[pscustomobject]@{ updateId='update-1'; cacheDirectory=$TestDrive } })
            $response.data.languages[0].code | Should -Be 'ru-ru'
            $response.data.languages[0].name | Should -Be 'Russian'
        }

        It 'GetEditions returns edition DTOs' {
            Mock Get-WibEditions { @([pscustomobject]@{ Code='Professional'; Name='Windows Pro' }) }
            (Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='editions'; command='GetEditions'; arguments=[pscustomobject]@{ updateId='update-1'; language='ru-ru'; cacheDirectory=$TestDrive } })).data.editions[0].code | Should -Be 'Professional'
        }

        It 'CreateBuildPlan delegates to New-WibBuildPlan' {
            Mock New-WibBuildPlan { $script:testPlan }
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='plan'; command='CreateBuildPlan'; arguments=[pscustomobject]@{ build=(ConvertTo-WibBuildDto $script:testBuild); language='ru-ru'; editions=@('Core','Professional'); imageFormat='ESD'; addUpdates=$true; cleanup=$true; netFx3=$false; outputDirectory=$TestDrive; cacheDirectory=$TestDrive } })
            Assert-MockCalled New-WibBuildPlan -Times 1 -Exactly
            $response.data.plan.schemaVersion | Should -Be 1
            $response.data.plan.build.uuid | Should -Be 'update-1'
        }

        It 'ValidateBuildPlan delegates to Assert-WibPlan' {
            Mock Assert-WibPlan { }
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='validate'; command='ValidateBuildPlan'; arguments=[pscustomobject]@{ plan=(ConvertTo-WibBuildPlanDto $script:testPlan) } })
            Assert-MockCalled Assert-WibPlan -Times 1 -Exactly
            $response.data.valid | Should -BeTrue
        }

        It 'invalid build plan maps to INVALID_BUILD_PLAN' {
            try { Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='bad-plan'; command='ValidateBuildPlan'; arguments=[pscustomobject]@{ plan=[pscustomobject]@{} } }); throw 'expected failure' } catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'INVALID_BUILD_PLAN' }
        }

        It 'ExecuteBuildPlan delegates to existing Invoke-WibBuildPlan' {
            Mock Assert-WibPlan { }
            Mock Invoke-WibBuildPlan { [pscustomobject]@{ Stage='completed'; IsoPath='C:\out.iso'; Sha256='abc'; LogPath='C:\build.log'; WorkDirectory='C:\work'; MetadataPath='C:\out.iso.json' } }
            $response = Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='execute'; command='ExecuteBuildPlan'; arguments=[pscustomobject]@{ plan=(ConvertTo-WibBuildPlanDto $script:testPlan) } })
            Assert-MockCalled Invoke-WibBuildPlan -Times 1 -Exactly
            $response.data.stage | Should -Be 'completed'
            $response.data.isoPath | Should -Be 'C:\out.iso'
            $response.data.sha256 | Should -Be 'abc'
        }

        It 'build exception is converted to structured BUILD_FAILED response' {
            Mock Assert-WibPlan { }
            Mock Invoke-WibBuildPlan { throw 'converter failed' }
            $requestPath = Join-Path $TestDrive 'execute-request.json'; $responsePath = Join-Path $TestDrive 'execute-response.json'
            Write-WibJsonFile ([ordered]@{ schemaVersion=1; requestId='execute-error'; command='ExecuteBuildPlan'; arguments=[ordered]@{ plan=ConvertTo-WibBuildPlanDto $script:testPlan } }) $requestPath 30
            $response = Invoke-WibBackendRequest -RequestFile $requestPath -ResponseFile $responsePath
            $response.success | Should -BeFalse
            $response.error.code | Should -Be 'BUILD_FAILED'
            $response.error.message | Should -Match 'converter failed'
            $response.error.PSObject.Properties.Name | Should -Not -Contain 'Exception'
        }

        It 'writes a valid response JSON envelope with expected property names' {
            $requestPath = Join-Path $TestDrive 'version-request.json'; $responsePath = Join-Path $TestDrive 'version-response.json'
            Write-WibJsonFile ([ordered]@{ schemaVersion=1; requestId='file-smoke'; command='GetVersion'; arguments=[ordered]@{} }) $requestPath 20
            Invoke-WibBackendRequest -RequestFile $requestPath -ResponseFile $responsePath | Out-Null
            { Get-Content -LiteralPath $responsePath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null } | Should -Not -Throw
            $response = Get-Content -LiteralPath $responsePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $response.PSObject.Properties.Name | Should -Be @('schemaVersion','requestId','command','success','applicationVersion','data')
            $response.success | Should -BeOfType [bool]
        }

        It 'does not serialize internal PowerShell metadata into build JSON' {
            Mock Search-WibBuilds { @($script:testBuild) }
            $json = ConvertTo-WibJsonText (Invoke-WibBackendRequestObject ([pscustomobject]@{ schemaVersion=1; requestId='dto'; command='SearchBuilds'; arguments=[pscustomobject]@{ search='Windows 11'; cacheDirectory=$TestDrive } })) 20
            $json | Should -Not -Match 'BuildVersion|PSComputerName|RunspaceId|ScriptMethod|PSStandardMembers'
        }
    }
}

Describe 'Backend Contract static security regressions' {
    It 'uses an explicit command allowlist and no Invoke-Expression' {
        $source = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\Private\BackendContract.ps1') -Raw -Encoding UTF8) + (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\Private\BackendCommands.ps1') -Raw -Encoding UTF8)
        $source | Should -Not -Match '(?i)Invoke-Expression'
        $source | Should -Match 'switch\s*\(\$Command\)'
        foreach ($command in @('GetVersion','SearchBuilds','GetRecommendedBuild','GetLanguages','GetEditions','CreateBuildPlan','ValidateBuildPlan','ExecuteBuildPlan','RunPreflight','CancelBuild')) { $source | Should -Match ([regex]::Escape("'$command'")) }
    }

    It 'keeps the standalone machine entry point ASCII-only and PS5.1-targeted' {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot '..\Invoke-WibBackend.ps1'))
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        $source = [Text.Encoding]::ASCII.GetString($bytes)
        $source | Should -Match '#requires -Version 5\.1'
        $source | Should -Not -Match '\?\?|\?\.'
    }
}
