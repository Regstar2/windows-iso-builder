BeforeAll {
    # Pester 5 separates discovery from test execution. Resolve the repository
    # root during the run phase so it remains available to every It block.
    if (-not [string]::IsNullOrWhiteSpace($env:WIB_REPOSITORY_ROOT)) {
        $script:RepositoryRoot = $env:WIB_REPOSITORY_ROOT
    }
    else {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    }

    if ([string]::IsNullOrWhiteSpace($script:RepositoryRoot) -or -not (Test-Path -LiteralPath $script:RepositoryRoot)) {
        throw 'Не удалось определить корневой каталог репозитория для статических тестов.'
    }

    # Only inspect source-controlled PowerShell areas. A recursive scan from the
    # repository root can accidentally traverse local/generated directories and
    # consume a large amount of memory on a developer machine.
    $powerShellFiles = @(
        Get-ChildItem -LiteralPath $script:RepositoryRoot -File -ErrorAction Stop |
            Where-Object { $_.Extension -in @('.ps1', '.psm1') }

        foreach ($relativeDirectory in @('src', 'tests')) {
            $directory = Join-Path $script:RepositoryRoot $relativeDirectory
            if (Test-Path -LiteralPath $directory) {
                Get-ChildItem -LiteralPath $directory -File -Recurse -ErrorAction Stop |
                    Where-Object { $_.Extension -in @('.ps1', '.psm1') }
            }
        }
    )

    $script:PowerShellFiles = @($powerShellFiles | Sort-Object FullName -Unique)
}

Describe 'Repository safety rules' {
    It 'does not hardcode a supported Windows version catalog in source code' {
        $sourceFiles = Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'src') -Filter '*.ps1' -File -Recurse
        $source = ($sourceFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $source | Should -Not -Match 'Windows10BuildBase'
        $source | Should -Not -Match 'Windows11BuildBase'
    }

    It 'does not modify the machine execution policy' {
        $violations = foreach ($file in $script:PowerShellFiles) {
            $source = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                $file.FullName,
                [ref]$tokens,
                [ref]$parseErrors
            )

            foreach ($parseError in $parseErrors) {
                throw ('Не удалось разобрать {0}: {1}' -f $file.FullName, $parseError.Message)
            }

            $commands = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -ieq 'Set-ExecutionPolicy'
            }, $true)

            foreach ($command in $commands) {
                '{0}:{1} {2}' -f $file.FullName, $command.Extent.StartLineNumber, $command.Extent.Text
            }
        }

        @($violations).Count | Should -Be 0
    }

    It 'keeps generated output and cache out of Git' {
        $gitignore = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitignore') -Raw
        $gitignore | Should -Match '(?m)^output/$'
        $gitignore | Should -Match '(?m)^\.private/$'
        $gitignore | Should -Match '(?m)^/AGENTS\.md$'
        $gitignore | Should -Match '(?m)^/\.project-rules/$'
        $gitignore | Should -Match '(?m)^/docs/ai-prompts/$'
    }

    It 'uses the lowercase kebab-case repository URL' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psd1') -Raw
        $apiClient = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'src\WindowsISOBuilder\Private\UupApi.ps1') -Raw -Encoding UTF8
        $manifest | Should -Match 'github\.com/Regstar2/windows-iso-builder'
        $apiClient | Should -Match 'github\.com/Regstar2/windows-iso-builder'
        $manifest | Should -Not -Match 'github\.com/Regstar2/WindowsISOBuilder'
    }

    It 'parses every PowerShell source file as UTF-8 without syntax errors' {
        $errors = foreach ($file in $script:PowerShellFiles) {
            $source = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            $tokens = $null
            $parseErrors = $null

            [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                $file.FullName,
                [ref]$tokens,
                [ref]$parseErrors
            ) | Out-Null

            foreach ($parseError in $parseErrors) {
                '{0}:{1}:{2} {3}' -f @(
                    $file.FullName,
                    $parseError.Extent.StartLineNumber,
                    $parseError.Extent.StartColumnNumber,
                    $parseError.Message
                )
            }
        }

        @($errors).Count | Should -Be 0
    }

    It 'loads private module scripts explicitly as UTF-8 for Windows PowerShell 5.1' {
        $modulePath = Join-Path $script:RepositoryRoot 'src\WindowsISOBuilder\WindowsISOBuilder.psm1'
        $moduleSource = Get-Content -LiteralPath $modulePath -Raw -Encoding UTF8

        $moduleSource | Should -Match 'Get-Content\s+-LiteralPath\s+\$privatePath\s+-Raw\s+-Encoding\s+UTF8'
        $moduleSource | Should -Match '\[scriptblock\]::Create\(\$privateSource\)'
    }

    It 'uses the repository README naming convention' {
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'README.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'README_EN.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'README_RU.md') | Should -BeFalse
    }
}
