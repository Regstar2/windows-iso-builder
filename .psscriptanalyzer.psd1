@{
    Severity     = @('Error', 'Warning')
    IncludeRules = @(
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingWriteHost',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidGlobalVars'
    )
    ExcludeRules = @(
        # Windows ISO Builder uses private domain-specific helper names such as
        # Download-WibUupPackage and Sort-WibBuildCatalog. Renaming those helpers
        # only to satisfy the public-cmdlet verb convention would add churn with
        # no runtime or API benefit.
        'PSUseApprovedVerbs',

        # These are internal orchestration/helper functions, not public cmdlets.
        # Adding SupportsShouldProcess to Start-/Set-/New- helpers would imply an
        # interactive contract that they intentionally do not expose.
        'PSUseShouldProcessForStateChangingFunctions',

        # Console output is part of the TUI contract and is wrapped/tested.
        'PSAvoidUsingWriteHost'
    )
}
