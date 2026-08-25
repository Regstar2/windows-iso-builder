$repoRoot = Split-Path -Parent $PSScriptRoot

Describe 'v1.0.0 final release polish' {
    It 'keeps catalog rows on theme-owned backgrounds' {
        $xaml = Get-Content (Join-Path $repoRoot 'src\WindowsISOBuilder.Gui\Views\CatalogView.xaml') -Raw

        $xaml | Should -Match 'AlternationCount="2"'
        $xaml | Should -Match '<Setter Property="Background" Value="\{DynamicResource WibCardBrush\}"/>'
        $xaml | Should -Match '<Trigger Property="AlternationIndex" Value="1">'
        $xaml | Should -Match 'WibSubtleBrush'
    }

    It 'publishes the GUI as one self-contained file and rejects root DLL clutter' {
        $build = Get-Content (Join-Path $repoRoot 'tools\Build-Gui.ps1') -Raw
        $package = Get-Content (Join-Path $repoRoot 'tools\New-ReleasePackage.ps1') -Raw

        $build | Should -Match 'PublishSingleFile=true'
        $build | Should -Match 'IncludeNativeLibrariesForSelfExtract=true'
        $build | Should -Match "Filter '\*\.dll'"
        $package | Should -Match 'Release package root must not contain DLL files'
        $package | Should -Match 'singleFile=\$true'
    }

    It 'tracks the README screenshots' {
        foreach ($path in @(
            'docs\assets\screenshots\build-dark.jpg',
            'docs\assets\screenshots\catalog-dark.jpg'
        )) {
            Test-Path (Join-Path $repoRoot $path) | Should -BeTrue
        }

        $readme = Get-Content (Join-Path $repoRoot 'README.md') -Raw
        $readme | Should -Match 'docs/assets/screenshots/build-dark.jpg'
        $readme | Should -Match 'docs/assets/screenshots/catalog-dark.jpg'
    }
}
