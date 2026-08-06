@{
    Severity     = @('Error', 'Warning')
    IncludeRules = @(
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingWriteHost',
        'PSUseApprovedVerbs',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidGlobalVars'
    )
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )
}
