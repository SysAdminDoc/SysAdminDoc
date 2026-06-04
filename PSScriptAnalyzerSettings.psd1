@{
    Severity = @(
        'Error'
        'Warning'
    )

    ExcludeRules = @(
        # This repo is a user-facing profile/bootstrapper tool; Write-Host is used
        # intentionally for concise CI and novice setup status output.
        'PSAvoidUsingWriteHost'

        # The generator uses New-* and Set-* helper names for in-memory rendering
        # and report construction. Actual filesystem writes stay in the guarded
        # main block, so ShouldProcess would add noise without protecting users.
        'PSUseShouldProcessForStateChangingFunctions'

        # Existing function names mirror GitHub/JSON/domain concepts such as repos,
        # release assets, and schema contracts; renaming them would reduce clarity.
        'PSUseSingularNouns'

        # Project convention is UTF-8 without BOM; sync-profile.ps1 also forces
        # UTF-8 console output to avoid Windows mojibake in generated artifacts.
        'PSUseBOMForUnicodeEncodedFile'

        # The link checker declares Test-ParallelHttpUrl inside a
        # ForEach-Object -Parallel block. Its param block is valid at runtime,
        # but this analyzer rule treats those parameters as outer variables.
        'PSUseUsingScopeModifierInNewRunspaces'
    )
}
