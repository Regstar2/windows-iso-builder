$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'v0.2.2 preflight engine' {
    InModuleScope WindowsISOBuilder {
        BeforeEach {
            $script:testPlan = [pscustomobject][ordered]@{
                SchemaVersion=1; ApplicationVersion='0.2.2-alpha.1'; CreatedAt='2026-08-18T00:00:00Z';
                Build=[pscustomobject]@{ Uuid='update-1'; Title='Windows 11 25H2'; Product='Windows 11'; VersionLabel='25H2'; Build='26200.1'; Architecture='amd64'; IsPreview=$false };
                Language='ru-ru'; Editions=@('Professional'); SourceEdition='Professional'; VirtualEditions=@(); ImageFormat='ESD';
                AddUpdates=$true; Cleanup=$true; NetFx3=$false; OutputDirectory=(Join-Path $TestDrive 'output'); CacheDirectory=(Join-Path $TestDrive 'cache'); RemoveWorkAfterSuccess=$false
            }
            Mock Assert-WibPlan { }
            Mock Test-WibWindowsHost { $true }
            Mock Test-Wib64BitHost { $true }
            Mock Get-WibPowerShellRuntimeVersion { [version]'7.5' }
            Mock Test-WibPreflightComponent { $true }
            Mock Test-WibPreflightDirectory {
                param($Path, $Kind)
                $check = New-WibPreflightCheck -Id ('path.{0}' -f $Kind) -Status pass -Severity error -Message 'ok' -Data ([ordered]@{path=$Path})
                $write = New-WibPreflightCheck -Id ('path.{0}Writable' -f $Kind) -Status pass -Severity error -Message 'ok' -Data ([ordered]@{path=$Path})
                [pscustomobject]@{ FullPath=$Path; Checks=@($check,$write); Writable=$true }
            }
            Mock Get-WibDriveFreeBytes { [int64](100GB) }
            Mock Test-WibUupApiAvailability { [pscustomobject]@{ Available=$true; Uri='https://api.uupdump.net'; StatusCode=200; Message='ok' } }
        }

        It '1. returns ready=true when local checks pass' {
            (Invoke-WibPreflight -Plan $script:testPlan).ready | Should -BeTrue
        }

        It '2. reports unsupported host without stopping other checks' {
            Mock Test-WibWindowsHost { $false }
            $report = Invoke-WibPreflight -Plan $script:testPlan
            $report.ready | Should -BeFalse
            ($report.checks | Where-Object id -eq 'host.windows').code | Should -Be 'UNSUPPORTED_HOST'
            @($report.checks).Count | Should -BeGreaterThan 5
        }

        It '3. reports non-64-bit host' {
            Mock Test-Wib64BitHost { $false }
            $report = Invoke-WibPreflight -Plan $script:testPlan
            ($report.checks | Where-Object id -eq 'host.architecture').status | Should -Be 'fail'
        }

        It '4. reports missing DISM as required component' {
            Mock Test-WibPreflightComponent { param($Name) $Name -ne 'dism.exe' }
            $report = Invoke-WibPreflight -Plan $script:testPlan
            ($report.checks | Where-Object id -eq 'tool.dism').code | Should -Be 'REQUIRED_COMPONENT_MISSING'
            $report.ready | Should -BeFalse
        }

        It '5. reports another missing required command' {
            Mock Test-WibPreflightComponent { param($Name) $Name -ne 'Expand-Archive' }
            (Invoke-WibPreflight -Plan $script:testPlan).checks | Where-Object id -eq 'tool.expandArchive' | Select-Object -ExpandProperty status | Should -Be 'fail'
        }

        It '6. reports non-writable cache directory' {
            Mock Test-WibPreflightDirectory {
                param($Path,$Kind)
                if ($Kind -eq 'cache') {
                    $fail=New-WibPreflightCheck -Id 'path.cacheWritable' -Status fail -Severity error -Code 'PATH_NOT_WRITABLE' -Message 'blocked' -Data ([ordered]@{path=$Path})
                    return [pscustomobject]@{FullPath=$Path;Checks=@($fail);Writable=$false}
                }
                $pass=New-WibPreflightCheck -Id 'path.outputWritable' -Status pass -Severity error -Message 'ok'
                return [pscustomobject]@{FullPath=$Path;Checks=@($pass);Writable=$true}
            }
            ($report = Invoke-WibPreflight -Plan $script:testPlan).ready | Should -BeFalse
            ($report.checks | Where-Object id -eq 'path.cacheWritable').code | Should -Be 'PATH_NOT_WRITABLE'
        }

        It '7. reports non-writable output directory' {
            Mock Test-WibPreflightDirectory {
                param($Path,$Kind)
                $status=if($Kind -eq 'output'){'fail'}else{'pass'}; $code=if($Kind -eq 'output'){'PATH_NOT_WRITABLE'}else{$null}
                $check=New-WibPreflightCheck -Id ('path.{0}Writable' -f $Kind) -Status $status -Severity error -Code $code -Message 'probe' -Data ([ordered]@{path=$Path})
                [pscustomobject]@{FullPath=$Path;Checks=@($check);Writable=($Kind -ne 'output')}
            }
            (Invoke-WibPreflight -Plan $script:testPlan).checks | Where-Object id -eq 'path.outputWritable' | Select-Object -ExpandProperty status | Should -Be 'fail'
        }

        It '8. reports low cache disk space with bytes' {
            Mock Get-WibDriveFreeBytes { param($Path) if($Path -match 'cache'){[int64](1GB)}else{[int64](100GB)} }
            $check=(Invoke-WibPreflight -Plan $script:testPlan).checks | Where-Object id -eq 'disk.cache'
            $check.code | Should -Be 'DISK_SPACE_LOW'; $check.data.requiredBytes | Should -Be ([int64](40GB)); $check.data.availableBytes | Should -Be ([int64](1GB))
        }

        It '9. reports low output disk space with bytes' {
            Mock Get-WibDriveFreeBytes { param($Path) if($Path -match 'output'){[int64](1GB)}else{[int64](100GB)} }
            $check=(Invoke-WibPreflight -Plan $script:testPlan).checks | Where-Object id -eq 'disk.output'
            $check.code | Should -Be 'DISK_SPACE_LOW'; $check.data.requiredBytes | Should -Be ([int64](8GB))
        }

        It '10. warning does not make ready=false' {
            Mock Test-WibPreflightComponent { param($Name) $Name -ne 'Mount-DiskImage' }
            $report=Invoke-WibPreflight -Plan $script:testPlan
            $report.ready | Should -BeTrue
            ($report.checks | Where-Object id -eq 'tool.mountDiskImage').status | Should -Be 'warning'
        }

        It '11. returns multiple independent failures in one report' {
            Mock Test-WibWindowsHost { $false }
            Mock Test-WibPreflightComponent { param($Name) $Name -ne 'dism.exe' }
            Mock Get-WibDriveFreeBytes { [int64](1GB) }
            $fails=@((Invoke-WibPreflight -Plan $script:testPlan).checks | Where-Object status -eq 'fail')
            $fails.Count | Should -BeGreaterThan 2
        }

        It '12. RunPreflight returns controlled DTO with success=true for not-ready environment' {
            Mock Invoke-WibPreflight { [pscustomobject]@{ready=$false;checks=@(New-WibPreflightCheck -Id 'host.windows' -Status fail -Severity error -Code 'UNSUPPORTED_HOST' -Message 'no')} }
            $planDto=ConvertTo-WibBuildPlanDto $script:testPlan
            $response=Invoke-WibBackendRequestObject ([pscustomobject]@{schemaVersion=1;requestId='preflight';command='RunPreflight';arguments=[pscustomobject]@{buildPlan=$planDto;onlineChecks=$false}})
            $response.success | Should -BeTrue; $response.data.ready | Should -BeFalse; $response.data.checks[0].id | Should -Be 'host.windows'
        }

        It '13. RunPreflight malformed plan uses INVALID_BUILD_PLAN' {
            try { Invoke-WibBackendRequestObject ([pscustomobject]@{schemaVersion=1;requestId='bad';command='RunPreflight';arguments=[pscustomobject]@{buildPlan=[pscustomobject]@{}}}); throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'INVALID_BUILD_PLAN' }
        }

        It '14. onlineChecks=false does not call network service' {
            Invoke-WibPreflight -Plan $script:testPlan -OnlineChecks:$false | Out-Null
            Assert-MockCalled Test-WibUupApiAvailability -Times 0 -Exactly
        }

        It '15. onlineChecks=true uses official UUP service abstraction' {
            Invoke-WibPreflight -Plan $script:testPlan -OnlineChecks:$true | Out-Null
            Assert-MockCalled Test-WibUupApiAvailability -Times 1 -Exactly
            $script:UupApiBaseUri | Should -Be 'https://api.uupdump.net'
        }

        It '16. build entry point reuses Invoke-WibPreflight before elevation' {
            Mock Invoke-WibPreflight { [pscustomobject]@{ready=$true;checks=@()} }
            Mock Show-WibPreflightSummary { }
            Mock Assert-WibPreflightReady { }
            Mock Test-WibAdministrator { $false }
            Mock Start-WibElevatedPlan { [pscustomobject]@{Stage='completed'} }
            $oldOs=$env:OS; try { $env:OS='Windows_NT'; Invoke-WibBuildPlan -Plan $script:testPlan | Out-Null } finally { $env:OS=$oldOs }
            Assert-MockCalled Invoke-WibPreflight -Times 1 -Exactly
            Assert-MockCalled Start-WibElevatedPlan -Times 1 -Exactly
        }
    }
}

Describe 'v0.2.2 error taxonomy' {
    InModuleScope WindowsISOBuilder {
        It '17-19. preflight source codes survive without message parsing' -TestCases @(
            @{Code='DISK_SPACE_LOW';Id='disk.cache'}, @{Code='REQUIRED_COMPONENT_MISSING';Id='tool.dism'}, @{Code='PATH_NOT_WRITABLE';Id='path.cacheWritable'}
        ) {
            param($Code,$Id)
            $report=[pscustomobject]@{ready=$false;checks=@(New-WibPreflightCheck -Id $Id -Status fail -Severity error -Code $Code -Message 'произвольный русский текст' -Data ([ordered]@{path='C:\x';component='x'}))}
            try { Assert-WibPreflightReady $report; throw 'expected' } catch { $_.Exception.Data['WibErrorCode'] | Should -Be $Code }
        }

        It '20. UUP package network failure becomes UUP_PACKAGE_DOWNLOAD_FAILED' {
            $plan=[pscustomobject]@{Build=[pscustomobject]@{Uuid='id'};Language='ru-ru';SourceEdition='Professional';AddUpdates=$true;Cleanup=$true;NetFx3=$false;ImageFormat='ESD'}
            Mock Invoke-WebRequest { throw 'network down' }
            try { Download-WibUupPackage -Plan $plan -DestinationZip (Join-Path $TestDrive 'pkg.zip') -Attempts 1; throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'UUP_PACKAGE_DOWNLOAD_FAILED' }
        }

        It '21. invalid UUP ZIP becomes UUP_PACKAGE_INVALID' {
            $plan=[pscustomobject]@{Build=[pscustomobject]@{Uuid='id'};Language='ru-ru';SourceEdition='Professional';AddUpdates=$true;Cleanup=$true;NetFx3=$false;ImageFormat='ESD'}
            Mock Invoke-WebRequest { param($OutFile) [IO.File]::WriteAllText($OutFile,'invalid') }
            try { Download-WibUupPackage -Plan $plan -DestinationZip (Join-Path $TestDrive 'pkg.zip') -Attempts 1; throw 'expected' }
            catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'UUP_PACKAGE_INVALID' }
        }

        It '22-24. converter and ISO failure points assign explicit source codes' {
            $source=Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private\Builder.ps1') -Raw -Encoding UTF8
            $source | Should -Match "Code 'CONVERTER_FAILED'|Code = 'CONVERTER_FAILED'"
            $source | Should -Match "Code 'ISO_NOT_FOUND'|Code = 'ISO_NOT_FOUND'"
            $source | Should -Match "Code 'ISO_VALIDATION_FAILED'|Code = 'ISO_VALIDATION_FAILED'"
        }

        It '25. generic ExecuteBuildPlan failure still falls back to BUILD_FAILED' {
            $failure=[Exception]::new('unknown')
            (ConvertTo-WibBackendErrorDto $failure 'ExecuteBuildPlan').code | Should -Be 'BUILD_FAILED'
        }

        It '26. classification is independent of localized exception text' {
            $exception=New-WibErrorException -Code 'DISK_SPACE_LOW' -Message 'место на диске вообще не упоминается' -Stage 'preflight'
            (ConvertTo-WibBackendErrorDto $exception 'ExecuteBuildPlan').code | Should -Be 'DISK_SPACE_LOW'
        }

        It 'documents remaining distinct codes in source taxonomy' {
            $all=(Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private\Builder.ps1') -Raw -Encoding UTF8) + (Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private\Elevation.ps1') -Raw -Encoding UTF8)
            foreach($code in @('DISM_FAILED','ELEVATION_CANCELLED','BUILD_CANCELLED')) { $all | Should -Match $code }
        }
    }
}

Describe 'v0.2.2 cancellation protocol' {
    InModuleScope WindowsISOBuilder {
        BeforeEach { Reset-WibCancellationContext -RemoveControlFile -Confirm:$false }
        AfterEach { Reset-WibCancellationContext -RemoveControlFile -Confirm:$false }

        It '27. CancelBuild acknowledges targetRequestId' {
            $result=Invoke-WibBackendCommand -Command 'CancelBuild' -RequestId 'cancel-command' -Arguments ([pscustomobject]@{targetRequestId='build-1';cacheDirectory=$TestDrive})
            $result.requested | Should -BeTrue; $result.targetRequestId | Should -Be 'build-1'
        }

        It '28-29. control path uses SHA-256 and blocks raw traversal semantics' {
            $path=Get-WibCancellationControlPath -RequestId '../evil\:build' -CacheDirectory $TestDrive
            [IO.Path]::GetFileName($path) | Should -Match '^[a-f0-9]{64}\.cancel\.json$'
            $path | Should -Not -Match '\.\./|evil|:build'
            (Split-Path -Parent $path) | Should -Be (Join-Path ([IO.Path]::GetFullPath($TestDrive)) 'control')
        }

        It '30. cancellation marker is detected centrally' {
            Initialize-WibCancellationContext -RequestId 'build-marker' -CacheDirectory $TestDrive | Out-Null
            Save-WibCancellationRequest -TargetRequestId 'build-marker' -CacheDirectory $TestDrive -Confirm:$false | Out-Null
            Test-WibCancellationRequested | Should -BeTrue
        }

        It '31. cancellation before build becomes BUILD_CANCELLED' {
            Initialize-WibCancellationContext -RequestId 'pre-cancel' -CacheDirectory $TestDrive | Out-Null
            Save-WibCancellationRequest -TargetRequestId 'pre-cancel' -CacheDirectory $TestDrive -Confirm:$false | Out-Null
            try { Assert-WibNotCancelled -Stage 'preflight'; throw 'expected' } catch { $_.Exception.Data['WibErrorCode'] | Should -Be 'BUILD_CANCELLED' }
        }

        It '32. cancellation between stages preserves the actual stage' {
            Initialize-WibCancellationContext -RequestId 'between' -CacheDirectory $TestDrive | Out-Null
            Save-WibCancellationRequest -TargetRequestId 'between' -CacheDirectory $TestDrive -Confirm:$false | Out-Null
            try { Assert-WibNotCancelled -Stage 'convert'; throw 'expected' } catch { $_.Exception.Data['WibStage'] | Should -Be 'convert' }
        }

        It '33. cancellable retry delay exits immediately after cancellation' {
            Initialize-WibCancellationContext -RequestId 'delay' -CacheDirectory $TestDrive | Out-Null
            Save-WibCancellationRequest -TargetRequestId 'delay' -CacheDirectory $TestDrive -Confirm:$false | Out-Null
            { Wait-WibCancellableDelay -Seconds 20 -Stage 'download' } | Should -Throw
        }

        It '34. elevation forwards runtime cancellation hash without modifying BuildPlan' {
            $source=Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private\Elevation.ps1') -Raw -Encoding UTF8
            $source | Should -Match 'CancellationRequestHash'; $source | Should -Match 'CancellationCacheDirectory'
            (ConvertTo-WibBuildPlanDto ([pscustomobject]@{SchemaVersion=1;ApplicationVersion='0.2.2-alpha.1';CreatedAt='x';Build=[pscustomobject]@{Uuid='u';Title='t';Product='Windows 11';VersionLabel='25H2';Build='1';Architecture='amd64';IsPreview=$false};Language='ru-ru';Editions=@('Professional');SourceEdition='Professional';VirtualEditions=@();ImageFormat='ESD';AddUpdates=$true;Cleanup=$true;NetFx3=$false;OutputDirectory=$TestDrive;CacheDirectory=$TestDrive;RemoveWorkAfterSuccess=$false})).PSObject.Properties.Name | Should -Not -Contain 'cancellationFile'
        }

        It '35. cancelled job state is distinct from failed' {
            $state=Join-Path $TestDrive 'state.json'; $plan=[pscustomobject]@{Name='x'}
            Save-WibJobState -Path $state -Stage 'downloading-uup-and-converting' -Plan $plan
            Save-WibJobState -Path $state -Stage 'cancelled' -Plan $plan -Message 'cancel'
            $value=Read-WibJsonFile $state
            $value.stage | Should -Be 'cancelled'; $value.cancelled | Should -BeTrue; $value.cancelledStage | Should -Be 'downloading-uup-and-converting'
        }

        It '36. cancelled target event keeps target requestId and monotonic sequence' {
            $events=Join-Path $TestDrive 'events.ndjson'; Initialize-WibEventSink -RequestId 'target-build' -EventFile $events | Out-Null
            Publish-WibEvent stage download 'running' | Out-Null; Publish-WibEvent cancelled download 'cancelled' | Out-Null
            $values=@(Get-Content $events -Encoding UTF8 | ForEach-Object { $_|ConvertFrom-Json })
            $values[-1].requestId | Should -Be 'target-build'; $values[-1].type | Should -Be 'cancelled'; $values[-1].sequence | Should -BeGreaterThan $values[0].sequence
            Reset-WibEventSink
        }

        It '37. partial cache survives cancellation cleanup' {
            $partial=Join-Path $TestDrive 'partial.aria2'; Set-Content -LiteralPath $partial -Value 'resume'
            Initialize-WibCancellationContext -RequestId 'cache-preserve' -CacheDirectory $TestDrive | Out-Null
            Save-WibCancellationRequest -TargetRequestId 'cache-preserve' -CacheDirectory $TestDrive -Confirm:$false | Out-Null
            Reset-WibCancellationContext -RemoveControlFile -Confirm:$false
            Test-Path $partial | Should -BeTrue
        }

        It '38. consumed control marker is cleaned up' {
            $context=Initialize-WibCancellationContext -RequestId 'cleanup' -CacheDirectory $TestDrive
            Save-WibCancellationRequest -TargetRequestId 'cleanup' -CacheDirectory $TestDrive -Confirm:$false | Out-Null
            Test-Path $context.ControlPath | Should -BeTrue
            Reset-WibCancellationContext -RemoveControlFile -Confirm:$false
            Test-Path $context.ControlPath | Should -BeFalse
        }

        It '39. a new requestId does not inherit an old cancellation marker' {
            Save-WibCancellationRequest -TargetRequestId 'old-build' -CacheDirectory $TestDrive -Confirm:$false | Out-Null
            Initialize-WibCancellationContext -RequestId 'new-build' -CacheDirectory $TestDrive | Out-Null
            Test-WibCancellationRequested | Should -BeFalse
        }

        It '40. process termination is PID-rooted and never name-rooted' {
            $source=Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private\ExecutionControl.ps1') -Raw -Encoding UTF8
            $source | Should -Match "'/PID'"; $source | Should -Match "'/T'"; $source | Should -Match "'/F'"; $source | Should -Not -Match '/IM|Get-Process\s+aria2|Get-Process\s+dism'
            $source | Should -Match 'Test-WibCancellationRequested'; $source | Should -Match 'Stop-WibOwnedProcessTree -ProcessId \$process\.Id'
        }
    }
}
