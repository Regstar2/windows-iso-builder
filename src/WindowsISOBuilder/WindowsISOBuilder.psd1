@{
    RootModule        = 'WindowsISOBuilder.psm1'
    ModuleVersion     = '0.2.2'
    GUID              = 'c4e7ccdc-80c0-4a6e-bd43-3e2ae61c8f59'
    Author            = 'Regstar2'
    CompanyName       = 'Community project'
    Copyright         = '(c) 2026 Regstar2. MIT License.'
    Description       = 'Interactive UUP dump client for searching, downloading, and building Windows ISO images.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Start-WibInteractive',
        'Start-WibNonInteractive',
        'Invoke-WibPlanFile',
        'Invoke-WibBackendRequest',
        'Search-WibBuilds',
        'Get-WibLanguages',
        'Get-WibEditions',
        'New-WibBuildPlan',
        'Invoke-WibBuildPlan',
        'Get-WibCacheInfo',
        'Clear-WibCache'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Windows', 'ISO', 'UUP', 'UUP-dump')
            LicenseUri = 'https://github.com/Regstar2/windows-iso-builder/blob/master/LICENSE'
            ProjectUri = 'https://github.com/Regstar2/windows-iso-builder'
        }
    }
}
