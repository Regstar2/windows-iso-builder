Describe 'Repository safety rules' {
    $root = Split-Path -Parent $PSScriptRoot

    It 'does not hardcode a supported Windows version catalog in source code' {
        $sourceFiles = Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.ps1' -File -Recurse
        $source = ($sourceFiles | Get-Content -Raw) -join "`n"
        $source | Should -Not -Match 'Windows10BuildBase'
        $source | Should -Not -Match 'Windows11BuildBase'
    }

    It 'does not modify the machine execution policy' {
        $files = Get-ChildItem -LiteralPath $root -Include '*.ps1', '*.psm1' -File -Recurse
        $source = ($files | Get-Content -Raw) -join "`n"
        $source | Should -Not -Match '(?i)Set-ExecutionPolicy'
    }

    It 'keeps generated output and cache out of Git' {
        $gitignore = Get-Content -LiteralPath (Join-Path $root '.gitignore') -Raw
        $gitignore | Should -Match '(?m)^output/$'
        $gitignore | Should -Match '(?m)^\.private/$'
        $gitignore | Should -Match '(?m)^/AGENTS\.md$'
        $gitignore | Should -Match '(?m)^/\.project-rules/$'
        $gitignore | Should -Match '(?m)^/docs/ai-prompts/$'
    }


    It 'uses the lowercase kebab-case repository URL' {
        $manifest = Get-Content -LiteralPath (Join-Path $root 'src\WindowsISOBuilder\WindowsISOBuilder.psd1') -Raw
        $apiClient = Get-Content -LiteralPath (Join-Path $root 'src\WindowsISOBuilder\Private\UupApi.ps1') -Raw
        $manifest | Should -Match 'github\.com/Regstar2/windows-iso-builder'
        $apiClient | Should -Match 'github\.com/Regstar2/windows-iso-builder'
        $manifest | Should -Not -Match 'github\.com/Regstar2/WindowsISOBuilder'
    }


    It 'uses the repository README naming convention' {
        Test-Path -LiteralPath (Join-Path $root 'README.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'README_EN.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'README_RU.md') | Should -BeFalse
    }
}
