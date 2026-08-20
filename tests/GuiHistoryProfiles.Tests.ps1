#requires -Version 5.1

Describe 'v0.4.0 History and Profiles regression surface' {
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:historyXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\HistoryView.xaml') -Raw -Encoding UTF8
        $script:profilesXaml = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Views\ProfilesView.xaml') -Raw -Encoding UTF8
        $script:localDataVm = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\ViewModels\MainViewModel.LocalData.cs') -Raw -Encoding UTF8
        $script:buildVm = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\ViewModels\MainViewModel.Build.cs') -Raw -Encoding UTF8
        $script:historyService = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\HistoryService.cs') -Raw -Encoding UTF8
        $script:profileService = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\ProfileService.cs') -Raw -Encoding UTF8
        $script:jsonStore = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\AtomicJsonStore.cs') -Raw -Encoding UTF8
        $script:diagnostics = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\Services\DiagnosticsService.cs') -Raw -Encoding UTF8
        $script:packageConfig = Get-Content -LiteralPath (Join-Path $script:projectRoot 'tools\ReleasePackageConfig.psd1') -Raw -Encoding UTF8
        $script:version = (Get-Content -LiteralPath (Join-Path $script:projectRoot 'VERSION') -Raw -Encoding UTF8).Trim()
        $script:guiProject = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder.Gui\WindowsISOBuilder.Gui.csproj') -Raw -Encoding UTF8
        $script:moduleManifest = Get-Content -LiteralPath (Join-Path $script:projectRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psd1') -Raw -Encoding UTF8
    }

    It 'uses v0.4 public and GUI versions while leaving the PowerShell module version alone' {
        $script:version | Should -Be '0.4.0-alpha.1'
        $script:guiProject | Should -Match '<Version>0\.4\.0</Version>'
        $script:guiProject | Should -Match '<FileVersion>0\.4\.0\.0</FileVersion>'
        $script:guiProject | Should -Match '<AssemblyVersion>0\.4\.0\.0</AssemblyVersion>'
        $script:moduleManifest | Should -Match "ModuleVersion\s*=\s*'0\.3\.0'"
    }

    It 'keeps History and Profiles entirely outside the backend contract' {
        $script:localDataVm | Should -Not -Match 'ExecuteBuildPlan'
        $script:localDataVm | Should -Not -Match 'CreateBuildPlan'
        $script:localDataVm | Should -Not -Match 'RunPreflight'
        $script:buildVm | Should -Match '"CreateBuildPlan"'
        $script:buildVm | Should -Match '"RunPreflight"'
        ([regex]::Matches($script:buildVm, '"ExecuteBuildPlan"').Count) | Should -Be 1
    }

    It 'records only the actual ExecuteBuildPlan lifecycle' {
        $script:buildVm | Should -Match '_historyService\.Begin\(CreatePendingHistoryEntry\(\)\)'
        $script:buildVm | Should -Match '_historyService\.Complete'
        $script:buildVm | Should -Match '_historyService\.Fail'
        $script:buildVm | Should -Match '_historyService\.Cancel'
        $script:historyService | Should -Match 'HistoryStatus\.Interrupted'
    }

    It 'uses versioned local JSON stores with atomic replacement and retention' {
        $script:historyService | Should -Match 'SchemaVersion = 1'
        $script:profileService | Should -Match 'SchemaVersion = 1'
        $script:historyService | Should -Match 'RetentionLimit = 200'
        $script:historyService | Should -Match 'LocalDataPath\("history\.json"\)'
        $script:profileService | Should -Match 'LocalDataPath\("profiles\.json"\)'
        $script:jsonStore | Should -Match 'FileOptions\.WriteThrough'
        $script:jsonStore | Should -Match 'Flush\(flushToDisk: true\)'
        $script:jsonStore | Should -Match 'File\.Replace'
        $script:jsonStore | Should -Match 'damaged-'
    }

    It 'keeps local user stores out of diagnostics and release package configuration' {
        $script:diagnostics | Should -Not -Match 'history\.json|profiles\.json'
        $script:packageConfig | Should -Not -Match 'history\.json|profiles\.json'
        $script:diagnostics | Should -Match '"app-version\.txt"'
        $script:diagnostics | Should -Match '"environment\.json"'
        $script:diagnostics | Should -Match '"execution\.log"'
        $script:diagnostics | Should -Match '"build\.log"'
        $script:diagnostics | Should -Match '"converter\.log"'
    }

    It 'uses theme-owned surfaces in both new pages' {
        foreach ($xaml in @($script:historyXaml, $script:profilesXaml)) {
            $xaml | Should -Match 'StaticResource Card'
            $xaml | Should -Not -Match 'Background="White"|Background="Black"|#[Ff]{6}|#000000'
        }
    }

    It 'provides automation names on principal History and Profile actions' {
        foreach ($key in @('AutomationHistoryDetails','AutomationHistoryRepeat','AutomationHistoryCreateProfile','AutomationHistoryDelete')) {
            $script:historyXaml | Should -Match $key
        }
        foreach ($key in @('AutomationProfilesUse','AutomationProfilesEdit','AutomationProfilesDelete')) {
            $script:profilesXaml | Should -Match $key
        }
        $script:historyXaml | Should -Match 'AutomationProperties\.Name="\{Binding AccessibilitySummary\}"'
        $script:profilesXaml | Should -Match 'AutomationProperties\.Name="\{Binding AccessibilitySummary\}"'
    }

    It 'keeps Repeat and Use as configuration application rather than build execution' {
        $script:localDataVm | Should -Match 'RepeatHistoryAsync'
        $script:localDataVm | Should -Match 'UseProfileAsync'
        $script:localDataVm | Should -Match 'ResolveRecommendedAsync'
        $script:localDataVm | Should -Match 'ResolvePinnedAsync'
        $script:localDataVm | Should -Match 'ResolveValuesAsync'
        $script:localDataVm | Should -Not -Match 'BuildAsync\('
    }
}
