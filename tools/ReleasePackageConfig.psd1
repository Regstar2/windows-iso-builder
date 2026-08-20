@{
    SchemaVersion = 1

    RuntimeEntries = @(
        'VERSION'
        'Start-Builder.cmd'
        'Start-Builder.ps1'
        'Invoke-WibBackend.ps1'
        'README.md'
        'README_EN.md'
        'LICENSE'
        'CHANGELOG.md'
        'REQUIREMENTS.md'
        'SECURITY.md'
        'CONTRIBUTING.md'
        'src\WindowsISOBuilder'
        'docs\ARCHITECTURE.md'
        'docs\IMPLEMENTATION_STATUS.md'
        'docs\SOURCE_V4_MIGRATION.md'
        'docs\BACKEND_CONTRACT.md'
        'docs\BACKEND_CONTRACT_EN.md'
        'docs\GUI_ARCHITECTURE.md'
        'docs\GUI_ARCHITECTURE_EN.md'
        'docs\LOCAL_DATA.md'
        'docs\LOCAL_DATA_EN.md'
        'docs\VALIDATION_MATRIX.md'
        'docs\VALIDATION_MATRIX_EN.md'
        'docs\validation'
        'docs\releases\v{version}.md'
        'docs\releases\v{version}_EN.md'
    )

    RequiredPackageFiles = @(
        'VERSION'
        'release-manifest.json'
        'WindowsISOBuilder.exe'
        'Start-Builder.cmd'
        'Start-Builder.ps1'
        'Invoke-WibBackend.ps1'
        'README.md'
        'README_EN.md'
        'src\WindowsISOBuilder\WindowsISOBuilder.psd1'
        'src\WindowsISOBuilder\WindowsISOBuilder.psm1'
        'docs\ARCHITECTURE.md'
        'docs\BACKEND_CONTRACT.md'
        'docs\BACKEND_CONTRACT_EN.md'
        'docs\GUI_ARCHITECTURE.md'
        'docs\GUI_ARCHITECTURE_EN.md'
        'docs\LOCAL_DATA.md'
        'docs\LOCAL_DATA_EN.md'
        'docs\VALIDATION_MATRIX.md'
        'docs\VALIDATION_MATRIX_EN.md'
    )

    DeniedPathSegments = @(
        '.git'
        '.github'
        'tests'
        'output'
        'logs'
        'dist'
        'cache'
        'bin'
        'obj'
        '.project-rules'
        '.vscode'
        '.idea'
        '.cursor'
        '.codex'
        '.claude'
        '.ai'
    )

    DeniedFileNames = @('.DS_Store','Thumbs.db','validation-result.json')
    DeniedExtensions = @('.iso','.wim','.esd','.swm','.log','.zip','.aria2','.tmp','.bak','.user','.suo','.secret','.secrets','.local','.pdb')
    TextScanExtensions = @('.ps1','.psm1','.psd1','.cmd','.md','.json','.txt','.yml','.yaml','.ini','.cs','.csproj','.xaml')
}
