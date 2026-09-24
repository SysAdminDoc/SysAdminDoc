#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Hermetic (offline) Pester tests for scripts/sync-profile.ps1.

    The script is dot-sourced so only its function library loads (the live
    GitHub fetch + generation block is guarded by an InvocationName check).
    These tests never touch the network.

    Run:  pwsh -NoProfile -Command "Invoke-Pester -Path tests"

    Describe blocks that spawn a child pwsh process (seed/summary/dependency-review/PR-handoff)
    are tagged 'Integration'. For a faster in-process iteration loop, run
    Invoke-Pester -Path tests -ExcludeTag Integration.
#>

BeforeAll {
    # Lets the Describe blocks at the end dot-source the other scripts for coverage without
    # running their main bodies; see the seams in scripts/*.ps1 and setup.ps1.
    $env:SYSADMINDOC_TEST_SEAM = '1'
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:SyncProfileScriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
    # Dot-source the library. The script's test seam stops before the fetch/main block,
    # after the entry point has dot-sourced every file in $GeneratorLibraryFiles.
    . $script:SyncProfileScriptPath
    # Source-scan assertions read the whole generator: the entry script, then each library
    # file in load order, so a moved function is still in scope for them.
    $script:SyncProfileSourcePaths = @($script:SyncProfileScriptPath) + @($GeneratorLibraryFiles | ForEach-Object { Join-Path $script:RepoRoot $_ })
    $script:SyncProfileScript = @($script:SyncProfileSourcePaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
    # Run offline so nothing reaches out to GitHub. The generator reads $script:Offline; the
    # dot-source above also bound a local $Offline parameter ($false) in this scope, which is
    # what plain $Offline reads used to find.
    $script:Offline = $true
    # Nothing in the suite may start the real gh: mocks and function stubs stand in for it
    # in process, and child runs go offline. A gh.cmd first on PATH records any call that
    # gets past them (its first argument only; the rest can hold & for cmd to misread), and
    # a Describe near the end fails on it. gh --version is a local query the support bundle
    # records, so the trap answers it without logging.
    $script:GhTrapDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('sysadmindoc-gh-trap-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:GhTrapDirectory
    $script:GhTrapLog = Join-Path $script:GhTrapDirectory 'calls.log'
    [System.IO.File]::WriteAllText((Join-Path $script:GhTrapDirectory 'gh.cmd'), (@(
                '@echo off'
                'if "%~1"=="--version" goto version'
                "echo %1>>`"$script:GhTrapLog`""
                'echo gh is trapped in the test suite 1>&2'
                'exit /b 1'
                ':version'
                'echo gh version 0.0.0 test suite trap'
                'exit /b 0'
            ) -join "`r`n") + "`r`n")
    $script:PathBeforeGhTrap = $env:PATH
    $env:PATH = $script:GhTrapDirectory + [System.IO.Path]::PathSeparator + $env:PATH

    # Should -Be and -BeExactly compare by culture, which skips zero-width, bidi and other
    # ignorable characters: 'ab' | Should -BeExactly "a<ZWJ>b" passes. -BeOrdinal compares
    # code unit by code unit, keeps $null apart from '', and shows a mismatch as code points.
    # It takes what's piped in as a whole (one item is that item, none is $null), so a list
    # has to match a list item by item and doesn't pass because each item matches alone.
    Add-ShouldOperator -Name BeOrdinal -SupportsArrayInput -Test {
        param($ActualValue, $ExpectedValue, [switch]$Negate, [string]$Because)
        $asList = { param($Value) if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { , @($Value) } else { $null } }
        $actualItems = & $asList $ActualValue
        if ($null -ne $actualItems -and $actualItems.Count -le 1) { $ActualValue = if ($actualItems.Count -eq 1) { $actualItems[0] } else { $null }; $actualItems = $null }
        $expectedItems = & $asList $ExpectedValue
        $same = {
            param($Left, $Right)
            if ($null -eq $Left -or $null -eq $Right) { return ($null -eq $Left -and $null -eq $Right) }
            [string]::Equals([string]$Left, [string]$Right, [StringComparison]::Ordinal)
        }
        $succeeded = if ($null -ne $actualItems -or $null -ne $expectedItems) {
            $null -ne $actualItems -and $null -ne $expectedItems -and $actualItems.Count -eq $expectedItems.Count -and
            @(for ($index = 0; $index -lt $actualItems.Count; $index++) { if (-not (& $same $actualItems[$index] $expectedItems[$index])) { $index } }).Count -eq 0
        } else {
            & $same $ActualValue $ExpectedValue
        }
        if ($Negate) { $succeeded = -not $succeeded }
        $show = {
            param($Value)
            if ($null -eq $Value) { return '$null' }
            if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { return '@(' + ((@($Value) | ForEach-Object { & $show $_ }) -join ', ') + ')' }
            "'" + ((([string]$Value).ToCharArray() | ForEach-Object { if ([int]$_ -lt 0x20 -or [int]$_ -gt 0x7E) { '{U+' + ('{0:X4}' -f [int]$_) + '}' } else { [string]$_ } }) -join '') + "'"
        }
        if ($null -ne $actualItems) { $ActualValue = $actualItems }
        $failure = if ($succeeded) { $null } elseif ($Negate) { "Expected anything but $(& $show $ExpectedValue), compared ordinally." } else { "Expected $(& $show $ExpectedValue), compared ordinally, but got $(& $show $ActualValue)." }
        if ($failure -and $Because) { $failure += " Because $Because" }
        [pscustomobject]@{ Succeeded = $succeeded; FailureMessage = $failure }
    }

    function Get-MarkdownTrailingWhitespaceViolations {
        param(
            [Parameter(Mandatory)]
            [string]$RootPath,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$RelativePaths
        )

        $violations = [System.Collections.Generic.List[string]]::new()
        foreach ($relativePath in @($RelativePaths)) {
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                continue
            }

            $path = Join-Path $RootPath $relativePath
            $lines = @([System.IO.File]::ReadAllLines($path))
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ([string]$lines[$i] -match '[ \t]+$') {
                    $violations.Add(('{0}:{1}' -f $relativePath, ($i + 1)))
                }
            }
        }

        return $violations.ToArray()
    }

    function New-TestEntry {
        param([string]$Repo, [string]$Category, [string]$Description = 'desc', [int]$Order = 1)
        ConvertTo-EntryHashtable (New-CatalogEntry -Repo $Repo -Category $Category -Description $Description -Order $Order)
    }

    # A catalog profileHeader block with every field, none of it this profile's own text.
    function New-TestProfileHeader {
        @{
            tagline = 'Fixture tagline for the header.'
            languages = @('PowerShell', 'Python')
            heading = 'Hi, fixture here'
            about = 'Fixture about text.'
            links = @(@{ text = 'More about the fixture'; url = 'https://fixture.example.test/about/' })
            support = @{ url = 'https://support.example.test/fixture'; imageUrl = 'https://support.example.test/button.png'; imageAlt = 'Support the fixture' }
        }
    }

    function New-TestRepoMeta {
        param(
            [string]$Name,
            [string]$Description = 'desc',
            [string[]]$Topics = @('utility'),
            [string]$Language = 'PowerShell',
            [object]$LicenseInfo = $null,
            [bool]$IsFork = $false,
            [object]$Parent = $null,
            [string]$ForkParentFetchError = $null,
            [switch]$WithRelease,
            [string]$ReleaseTag = 'v1.0.0',
            [string]$ReleasePublishedAt = '2026-06-04T00:00:00Z',
            [string]$PushedAt = '2026-06-04T00:00:00Z',
            [string[]]$AssetNames = @(),
            [string]$BranchTipSha = $null,
            [string]$BranchTipFetchedAt = $null
        )

        $assetKinds = if ($WithRelease) { @(Get-ReleaseAssetKinds -AssetNames $AssetNames) } else { @() }
        [pscustomobject]@{
            name = $Name
            description = $Description
            primaryLanguage = [pscustomobject]@{ name = $Language }
            repositoryTopics = @($Topics | ForEach-Object { [pscustomobject]@{ name = $_ } })
            defaultBranchRef = [pscustomobject]@{
                name = 'main'
                target = if ($BranchTipSha) { [pscustomobject]@{ oid = $BranchTipSha } } else { $null }
            }
            branchTipSha = $BranchTipSha
            branchTipFetchedAt = $BranchTipFetchedAt
            branchTipStatus = if ($BranchTipSha) { 'fresh' } else { 'unreachable' }
            branchTipWarning = if ($BranchTipSha) { $null } else { 'fixture has no branch-tip evidence' }
            latestRelease = if ($WithRelease) {
                [pscustomobject]@{
                    tagName = $ReleaseTag
                    url = "https://github.com/SysAdminDoc/$Name/releases/tag/$ReleaseTag"
                    publishedAt = $ReleasePublishedAt
                    releaseAssetNames = @($AssetNames)
                    releaseAssetKinds = @($assetKinds)
                    assetApiInspected = $true
                }
            } else {
                $null
            }
            stargazerCount = 0
            pushedAt = $PushedAt
            licenseInfo = $LicenseInfo
            isFork = $IsFork
            parent = $Parent
            forkParentFetchError = $ForkParentFetchError
            visibility = 'PUBLIC'
            isPrivate = $false
            isArchived = $false
            url = "https://github.com/SysAdminDoc/$Name"
        }
    }

    function New-TestScorecardAlert {
        param(
            [int]$Number,
            [string]$RuleId,
            [string]$Description,
            [string]$SecuritySeverity = 'medium'
        )

        [pscustomobject]@{
            number = $Number
            state = 'open'
            html_url = "https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/$Number"
            created_at = '2026-06-07T06:18:17Z'
            updated_at = '2026-06-07T06:18:17Z'
            tool = [pscustomobject]@{
                name = 'Scorecard'
                version = 'v5.3.0'
            }
            rule = [pscustomobject]@{
                id = $RuleId
                description = $Description
                severity = 'error'
                security_severity_level = $SecuritySeverity
                help_uri = "https://github.com/ossf/scorecard/blob/c22063e786c11f9dd714d777a687ff7c4599b600/docs/checks.md#$($Description.ToLowerInvariant())"
            }
        }
    }
}

AfterAll {
    Remove-Item -LiteralPath Env:SYSADMINDOC_TEST_SEAM -ErrorAction SilentlyContinue
    $env:PATH = $script:PathBeforeGhTrap
    Remove-Item -LiteralPath $script:GhTrapDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Function library loads via the dot-source test seam' {
    It 'exposes the core functions without running the fetch/main block' {
        Get-Command New-Readme, New-ProjectsExportJson, Get-InstallSnippet, Test-HttpUrl, Get-Catalog -ErrorAction SilentlyContinue |
            Should -HaveCount 5
    }

    It 'loads every generator library file and nothing outside the list' {
        $onDisk = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'scripts/sync-profile') -Filter '*.ps1' -File |
            ForEach-Object { "scripts/sync-profile/$($_.Name)" } | Sort-Object)
        @($GeneratorLibraryFiles | Sort-Object) | Should -Be $onDisk -Because 'a library file the entry point does not load is dead code, and a listed file that is missing breaks every run'
        @($GeneratorLibraryFiles).Count | Should -BeGreaterOrEqual 5
    }

    It 'keeps library files to function definitions and constants, each function defined once' {
        $seen = @{}
        foreach ($relativePath in @($GeneratorLibraryFiles)) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot $relativePath), [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty -Because $relativePath
            $ast.ParamBlock | Should -BeNullOrEmpty -Because "$relativePath is dot-sourced by the entry point and takes no parameters"
            foreach ($statement in @($ast.EndBlock.Statements)) {
                if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                    $seen.ContainsKey($statement.Name) | Should -BeFalse -Because "$($statement.Name) is defined in $relativePath and $($seen[$statement.Name])"
                    $seen[$statement.Name] = $relativePath
                } else {
                    # Loading a library file must not do work: only constant assignments, whose
                    # value runs no command and calls no method ($null = Remove-Item ... would
                    # otherwise pass as an assignment).
                    $statement | Should -BeOfType ([System.Management.Automation.Language.AssignmentStatementAst]) -Because "top-level statement in $relativePath"
                    $work = @($statement.Right.FindAll({
                                param($node)
                                $node -is [System.Management.Automation.Language.CommandAst] -or
                                $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
                            }, $true))
                    $work | Should -BeNullOrEmpty -Because "the assignment at $relativePath line $($statement.Extent.StartLineNumber) must be a constant"
                }
            }
        }
        $seen.Count | Should -BeGreaterThan 300
    }

    It 'documents the key public test-seam functions with comment-based help' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:SyncProfileScript, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $functionAsts = @{}
        foreach ($functionAst in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
            $functionAsts[$functionAst.Name] = $functionAst
        }
        $documentedFunctions = @(
            'Get-GitHubRepos',
            'Add-ReleaseAssetMetadata',
            'Get-ReleaseArtifactVerificationTargets',
            'Test-ReleaseArtifactVerification',
            'Get-BranchTipRows',
            'Set-BranchTipMetadata',
            'Test-BranchTipProvenance',
            'Add-ForkParentMetadata',
            'Add-LiveRepositoryMetadata',
            'ConvertTo-Lookup',
            'New-CompleteGenerationSnapshot',
            'Test-CompleteGenerationSnapshot',
            'Write-CompleteGenerationSnapshot',
            'Get-CompleteGenerationSnapshot',
            'Set-GenerationStateFromSnapshot',
            'Get-Catalog',
            'New-ProfileAssetSvgs',
            'Get-ProfileAssetFileContents',
            'New-Readme',
            'New-ProjectsExportJson',
            'New-BackstageCatalogExport',
            'New-BackstageCatalogExportJson',
            'Get-ProjectCanonicalRepo',
            'Get-ProjectAliases',
            'Get-StableProjectEntityId',
            'New-ProjectsFeedSchemaPolicy',
            'New-RenderedProfileSmokeSummary',
            'Test-RoadmapHygiene',
            'Test-RootMarkdownHygiene',
            'Test-ProfileAssetsAccessibility',
            'Test-CatalogShape',
            'Test-JsonSchemaContract',
            'Test-FeedSchemaContracts',
            'Test-PortfolioCrossSurfaceDrift',
            'Test-StableProjectEntityIds',
            'Test-FeedSchemaMigrationPolicy',
            'Test-ProfileReleaseConsistency',
            'Test-ProfileState'
        )

        foreach ($name in $documentedFunctions) {
            $functionAsts.ContainsKey($name) | Should -BeTrue
            $functionAst = $functionAsts[$name]
            @($functionAst.Body.ParamBlock.Attributes | ForEach-Object { $_.TypeName.FullName }) |
                Should -Contain 'CmdletBinding'
            $help = $functionAst.GetHelpContent()
            $help | Should -Not -BeNullOrEmpty
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Synopsis | Should -Not -Be $name

            $parameterNames = @($functionAst.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            foreach ($parameterName in $parameterNames) {
                $help.Parameters.Keys | Should -Contain $parameterName
            }
        }
    }

    It 'makes no contribution-calendar GraphQL call' {
        # The heatmap SVGs were the only consumer, and the README references no generated
        # image, so the read:user-scoped query is gone rather than guarded.
        $script:SyncProfileScript | Should -Not -Match 'contributionsCollection'
        $script:SyncProfileScript | Should -Not -Match 'function Get-ContributionCalendar'
        $script:SyncProfileScript | Should -Not -Match 'Get-ContributionCalendar'
    }
}

Describe 'Public text is encoded for where it lands' {
    It 'escapes what would break a cell, a link label or open HTML' {
        ConvertTo-MarkdownText 'a | b' | Should -Be 'a \| b'
        ConvertTo-MarkdownText 'C:\tools' | Should -Be 'C:\\tools'
        ConvertTo-MarkdownText 'Evil](https://evil.example)' | Should -Be 'Evil\](https://evil.example)'
        ConvertTo-MarkdownText '<script>alert(1)</script>' | Should -Be '&lt;script&gt;alert(1)&lt;/script&gt;'
        ConvertTo-MarkdownText 'R&D &#8238;' | Should -Be 'R&amp;D &amp;#8238;'
        ConvertTo-MarkdownText "one`r`ntwo`nthree" | Should -Be 'one two three'
        ConvertTo-MarkdownText $null | Should -Be ''
    }

    It 'drops control and bidi characters and repairs lone surrogates' {
        $rlo = [string][char]0x202E
        $isolate = [string][char]0x2066
        # Ordinal: -Be compares by culture and skips a bidi control, so it passed with the
        # override still in the text.
        ConvertTo-MarkdownText ("safe" + $rlo + "txt.exe") | Should -BeOrdinal 'safetxt.exe'
        ConvertTo-MarkdownText ("a" + $isolate + "b" + [char]0 + "c") | Should -BeOrdinal 'abc'
        # U+0085 is a line break (NEL), so it becomes a space like CR and LF.
        ConvertTo-MarkdownText ("a" + [char]0x85 + "b") | Should -BeOrdinal 'a b'
        ConvertTo-MarkdownText ("x" + [char]0xD800 + "y") | Should -BeOrdinal ("x" + [char]0xFFFD + "y")
        $emoji = [char]::ConvertFromUtf32(0x1F600)
        ConvertTo-MarkdownText "ok $emoji" | Should -BeOrdinal "ok $emoji"
    }

    It 'leaves ordinary accented, non-Latin and emphasized text alone' {
        foreach ($text in @('Café naïve résumé', '日本語のツール', 'Инструмент', 'עברית and العربية', 'Power-user tool *(Kotlin)*', 'Network_Security_Auditor')) {
            ConvertTo-MarkdownText $text | Should -Be $text
        }
    }

    It 'escapes backticks, so text never opens a code span' {
        # A code span shows its escapes as written, so this would read C:\\Tools\\x.ps1.
        ConvertTo-MarkdownText '`C:\Tools\x.ps1`' | Should -Be '\`C:\\Tools\\x.ps1\`'
        ConvertTo-MarkdownText 'Runs `x` fast' | Should -Be 'Runs \`x\` fast'
    }

    It 'puts each dollar sign in a span, and leaves an attribute''s alone' {
        # GitHub finds math after rendering, so \$ and &#36; still made $x$ a formula
        # (checked with the /markdown API); a span keeps each dollar sign apart. An
        # attribute value is never math, and a span there would show as written.
        ConvertTo-MarkdownText '$x$ and $$y$$' | Should -Be '<span>$</span>x<span>$</span> and <span>$</span><span>$</span>y<span>$</span><span>$</span>'
        ConvertTo-HtmlText 'Save $5 & more' | Should -Be 'Save <span>$</span>5 &amp; more'
        ConvertTo-HtmlText 'Save $5 & "more"' -Attribute | Should -Be 'Save $5 &amp; &quot;more&quot;'
    }

    It 'writes a bare URL the way GitHub will link it: <Case>' -ForEach @(
        # Checked with the /markdown API on 2026-09-23: GitHub keeps escapes and entities
        # inside an autolinked URL as written, so &amp; linked a=1&amp;b=2.
        @{ Case = 'an ampersand'; Text = 'see https://x.invalid/a?b=1&c=2 now'; Expected = 'see https://x.invalid/a?b=1&c=2 now'; Links = 'https://x.invalid/a?b=1&c=2' }
        @{ Case = 'a dollar sign'; Text = 'see https://x.invalid/?q=$y and $5'; Expected = 'see https://x.invalid/?q=$y and <span>$</span>5'; Links = 'https://x.invalid/?q=$y' }
        @{ Case = 'characters an escape would break'; Text = 'see https://x.invalid/a|b\c[d]e`f>g end'; Expected = 'see https://x.invalid/a%7Cb%5Cc%5Bd%5De%60f%3Eg end'; Links = 'https://x.invalid/a%7Cb%5Cc%5Bd%5De%60f%3Eg' }
        # GitHub trims an entity-like &rlm; off a raw URL, but reads on through &amp;rlm;, so
        # without the empty span the link ran to https://x.invalid/a&amp;rlm.
        @{ Case = 'an entity GitHub trims off the end'; Text = 'see https://x.invalid/a&rlm; now'; Expected = 'see https://x.invalid/a<span></span>&amp;rlm; now'; Links = 'https://x.invalid/a' }
        @{ Case = 'a < after the URL'; Text = 'see https://x.invalid/a<b&c now'; Expected = 'see https://x.invalid/a<span></span>&lt;b&amp;c now'; Links = 'https://x.invalid/a' }
        @{ Case = 'a pipe after trimmed punctuation'; Text = 'see https://x.invalid/a.|b now'; Expected = 'see https://x.invalid/a.%7Cb now'; Links = 'https://x.invalid/a.%7Cb' }
        @{ Case = 'a pipe after a closing bracket'; Text = 'see (https://x.invalid/a)|b now'; Expected = 'see (https://x.invalid/a)%7Cb now'; Links = 'https://x.invalid/a)%7Cb' }
        @{ Case = 'an entity after a trailing bracket'; Text = 'see (https://x.invalid/a)&rlm; now'; Expected = 'see (https://x.invalid/a<span></span>)&amp;rlm; now'; Links = 'https://x.invalid/a' }
        @{ Case = 'an entity inside'; Text = 'see https://x.invalid/a&#8238;b now'; Expected = 'see https://x.invalid/a&#8238;b now'; Links = 'https://x.invalid/a&#8238;b' }
        @{ Case = 'trailing punctuation'; Text = 'see (https://x.invalid/a&b). Then'; Expected = 'see (https://x.invalid/a&b). Then'; Links = 'https://x.invalid/a&b' }
        @{ Case = 'a www host'; Text = 'see www.x.invalid/a?b=1&c=2 now'; Expected = 'see www.x.invalid/a?b=1&c=2 now'; Links = '' }
        @{ Case = 'no valid domain'; Text = 'see https://&rlm;x and https://_a.b_c/&x'; Expected = 'see https://&amp;rlm;x and https://_a.b_c/&amp;x'; Links = '' }
        @{ Case = 'what comes before the scheme'; Text = 'xhttps://x.invalid/a&b and :www.x.invalid/&c'; Expected = 'xhttps://x.invalid/a&amp;b and :www.x.invalid/&amp;c'; Links = '' }
        @{ Case = 'a scheme GitHub leaves alone'; Text = 'ftp://x.invalid/a&b'; Expected = 'ftp://x.invalid/a&amp;b'; Links = '' }
    ) {
        $encoded = ConvertTo-MarkdownText $Text

        $encoded | Should -BeExactly $Expected
        # The header reader follows GitHub's autolink rules, so it links what the catalog named.
        (@(Get-ReadmeHeaderLinkReference -ExpectedReadme $encoded | ForEach-Object { $_.value }) -join ' ; ') | Should -BeExactly $Links
    }

    It 'encodes a URL in a link label like any other text' {
        # GitHub doesn't autolink inside a link label and decodes entities there, so a raw
        # &rlm; would come back as a bidi mark.
        ConvertTo-MarkdownText 'Tool https://x.invalid/a&rlm;b' -LinkLabel | Should -BeExactly 'Tool https://x.invalid/a&amp;rlm;b'
    }

    It 'treats titles as link labels and descriptions as text wherever the README writes them' {
        # Every place a title lands in a link label (the row, the category previews, the
        # tool picks), and the row's description, where GitHub autolinks the URL.
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        foreach ($entry in @($catalog.entries | Where-Object { $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })) {
            $entry.title = 'Tool https://x.invalid/a&rlm;b'
        }
        $tool = @($catalog.entries | Where-Object { $_.category -eq 'powershell' -and $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })[0]
        $tool.descriptionOverride = 'Docs at https://x.invalid/guide?a=1&b=2 here'

        $readme = New-Readme -Catalog $catalog -Repos @()

        [regex]::Matches($readme, '&rlm;').Count | Should -Be 0 -Because 'no title may carry a raw entity into a link label'
        [regex]::Matches($readme, [regex]::Escape('[**Tool https://x.invalid/a&amp;rlm;b**](')).Count | Should -BeGreaterThan 1
        $readme | Should -Match ([regex]::Escape('Docs at https://x.invalid/guide?a=1&b=2 here'))
    }

    It 'keeps dollar signs in a project row out of math' {
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $tool = @($catalog.entries | Where-Object { $_.category -eq 'powershell' -and $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })[0]
        $tool.descriptionOverride = 'Costs $5, or $$x^2$$ a month'

        $readme = New-Readme -Catalog $catalog -Repos @()

        $readme | Should -Match ([regex]::Escape('Costs <span>$</span>5, or <span>$</span><span>$</span>x^2<span>$</span><span>$</span> a month'))
    }

    It 'keeps the project link when a title and a description both carry a backtick' {
        # A code span binds before a link, so an unescaped backtick in the title pairs with
        # one in the description and swallows the ](url) between them.
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $tool = @($catalog.entries | Where-Object { $_.category -eq 'powershell' -and $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })[0]
        $tool.title = 'Tick`Tool'
        $tool.descriptionOverride = 'Runs `x` fast'

        $readme = New-Readme -Catalog $catalog -Repos @()

        $readme | Should -Match ([regex]::Escape('[**Tick\`Tool**](https://github.com/SysAdminDoc/' + $tool.repo + ')'))
        $readme | Should -Match ([regex]::Escape('Runs \`x\` fast'))
    }

    It 'cannot make a new row, Markdown link or HTML element from catalog text' {
        # GitHub still links a bare URL in text on its own. That adds no row, cell or
        # element, so it isn't what this guards against.
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $web = @($catalog.entries | Where-Object { $_.repo -eq 'WebTool' })[0]
        $web.title = 'Web](https://evil.example/) | <b>bold</b>'
        $web.descriptionOverride = "desc | cell`n| injected | row | <img src=x onerror=alert(1)> [x](https://evil.example/)"

        $readme = New-Readme -Catalog $catalog -Repos @()
        $section = [regex]::Match($readme, '(?s)<a id="web-applications"></a>.*?</details>').Value
        # Every line of the table, whatever it starts with: header, separator, one row.
        $tableLines = @($section -split "\r?\n" | Where-Object { $_.StartsWith('|') })

        $tableLines | Should -HaveCount 3 -Because 'one catalog row renders one table row'
        # The only unescaped pipes in that row are the four cell borders.
        ([regex]::Matches($tableLines[2], '(?<!\\)\|')).Count | Should -Be 4
        # Escaped brackets are text; only an unescaped "](" could start a link.
        $readme | Should -Not -Match '(?<!\\)\]\(https://evil\.example'
        # The header's own <b> is legitimate; the injected elements must not appear.
        $readme | Should -Not -Match '<b>bold</b>|<img src=x'
        $readme | Should -Match ([regex]::Escape('&lt;b&gt;bold&lt;/b&gt;'))
    }

    It 'keeps the feed text raw and valid JSON' {
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $web = @($catalog.entries | Where-Object { $_.repo -eq 'WebTool' })[0]
        $raw = 'Tool | "quoted" \ back <tag> & more, Café 日本語'
        $web.descriptionOverride = $raw

        $feed = New-ProjectsExportJson -Catalog $catalog -Repos @() | ConvertFrom-Json

        @($feed.projects | Where-Object { $_.repo -eq 'WebTool' })[0].description | Should -Be $raw
    }

    It 'names each row action after its project: <Case>' -ForEach @(
        # 884 duplicate labels across four viewports: Download, Launch, Install and Repo were
        # the whole accessible name of links going to 190 places.
        @{ Case = 'a live app'; Field = 'liveUrl'; Url = 'https://example.test/app'; Kind = $null; Name = 'Launch Web Tool' }
        @{ Case = 'a userscript'; Field = 'userscriptUrl'; Url = 'https://raw.githubusercontent.com/o/r/main/x.user.js'; Kind = $null; Name = 'Install Web Tool' }
        @{ Case = 'a repository'; Field = $null; Url = $null; Kind = 'repo'; Name = 'Web Tool repository' }
    ) {
        $entry = New-TestEntry -Repo 'WebTool' -Category 'misc'
        $entry.title = 'Web Tool'
        if ($Field) { $entry[$Field] = $Url }
        if ($Kind) { $entry.downloadKind = $Kind }

        Get-ActionLink -Entry $entry -Meta $null -Category 'misc' | Should -Match ('^<a href="[^"]+" aria-label="' + [regex]::Escape($Name) + '">')
    }

    It 'names each category card''s button after its category' {
        # Three cards said Browse and three Download, each pointing somewhere else.
        $entry = New-TestEntry -Repo 'SecTool' -Category 'security'

        $cell = New-ToolCatalogCell -Slug 'security' -Entries @($entry) -RepoLookup @{}

        $cell | Should -Match '<a href="#security--networking" aria-label="Browse Security"><kbd>Browse &#8594;</kbd></a>'
    }

    It 'names a release action with its kind unless it is a plain download' {
        $apk = New-TestEntry -Repo 'A' -Category 'android'; $apk.downloadKind = 'apk'
        $plain = New-TestEntry -Repo 'B' -Category 'misc'

        Get-ActionLink -Entry $apk -Meta (New-TestRepoMeta -Name 'A' -WithRelease -AssetNames @('A.apk')) -Category 'android' | Should -Match 'aria-label="Download A \(APK\)"'
        Get-ActionLink -Entry $plain -Meta (New-TestRepoMeta -Name 'B' -WithRelease -AssetNames @('B.zip')) -Category 'misc' | Should -Match 'aria-label="Download B"'
    }

    It 'keeps catalog text in an action name an attribute value and nothing more' {
        $entry = New-TestEntry -Repo 'WebTool' -Category 'web'
        $entry.title = 'Tool "q" & <b>x</b> | [y](https://evil.example/) `z`'
        $entry.liveUrl = 'https://example.test/a?b=1&c="d"'

        $link = Get-ActionLink -Entry $entry -Meta $null -Category 'web'

        $link | Should -BeOrdinal ('<a href="https://example.test/a?b=1&amp;c=%22d%22" aria-label="Launch Tool &quot;q&quot; &amp; &lt;b&gt;x&lt;/b&gt; &#124; &#91;y&#93;(https://evil.example/) &#96;z&#96;">Launch</a>')
    }

    It 'reads the release and userscript targets back from the anchor tag form' {
        $readme = @(
            '| [**A**](https://github.com/o/A) | a | <a href="https://github.com/o/A/releases/latest" aria-label="Download A"><kbd>&#11015;&nbsp;Download</kbd></a> |'
            '| [**S**](https://github.com/o/S) | s | <a href="https://raw.githubusercontent.com/o/S/main/s.user.js?x=1&amp;y=2" aria-label="Install S">Install</a> |'
        ) -join "`n"

        $targets = @(Get-ReadmeActionLinkValidationTargets -ExpectedReadme $readme -Entries @() -RepoLookup @{})

        @($targets | Where-Object { $_.type -eq 'readme-download' } | ForEach-Object { $_.url }) | Should -BeOrdinal 'https://github.com/o/A/releases/latest'
        @($targets | Where-Object { $_.type -eq 'readme-userscript-install' } | ForEach-Object { $_.url }) | Should -BeOrdinal 'https://raw.githubusercontent.com/o/S/main/s.user.js?x=1&y=2'
    }

    It 'seeds action URLs and kinds back from the anchor tag form' {
        # The kind comes from the button, so a title naming another kind can't decide it.
        $ReadmePath = Join-Path $TestDrive 'seed-anchor-form.md'
        $lines = @(
            '<summary><b>&#129513; Browser Extensions & Userscripts</b></summary>'
            ''
            '| [**CRX/XPI Helper**](https://github.com/SysAdminDoc/CrxHelper) | An APK-free add-on | <a href="https://github.com/SysAdminDoc/CrxHelper/releases/latest" aria-label="Download CRX/XPI Helper (ZIP/XPI)"><kbd>&#11015;&nbsp;ZIP/XPI</kbd></a> |'
            '| [**Script**](https://github.com/SysAdminDoc/Script) | A script | <a href="https://raw.githubusercontent.com/SysAdminDoc/Script/main/s.user.js?a=1&amp;b=2" aria-label="Install Script">Install</a> |'
            '| [**Source**](https://github.com/SysAdminDoc/Source) | Source only | <a href="https://github.com/SysAdminDoc/Source" aria-label="Source repository">Repo</a> |'
        )
        [System.IO.File]::WriteAllText($ReadmePath, ($lines -join "`n") + "`n")

        $seeded = @(New-CatalogFromReadme -Repos @() 3>$null) | Select-Object -Last 1
        $byRepo = @{}
        foreach ($entry in @($seeded.entries)) { $byRepo[[string]$entry.repo] = $entry }

        $byRepo['CrxHelper'].downloadKind | Should -BeOrdinal 'zip-xpi'
        $byRepo['Script'].downloadKind | Should -BeOrdinal 'userscript'
        $byRepo['Script'].userscriptUrl | Should -BeOrdinal 'https://raw.githubusercontent.com/SysAdminDoc/Script/main/s.user.js?a=1&b=2'
        $byRepo['Source'].downloadKind | Should -BeOrdinal 'repo'
    }

    It 'percent-encodes characters that would break a catalog link destination' {
        $entry = New-TestEntry -Repo 'LiveTool' -Category 'web'
        $entry.liveUrl = 'https://example.test/app (beta)/<x>'

        Get-ActionLink $entry $null 'web' | Should -BeOrdinal '<a href="https://example.test/app%20%28beta%29/%3Cx%3E" aria-label="Launch LiveTool">Launch</a>'
    }
}

Describe 'Catalog refuses deceptive or unsafe one-line text' {
    BeforeAll {
        function script:Get-ShapeIssues {
            param([hashtable]$Entry)
            @((Test-CatalogShape -Catalog @{ entries = @($Entry) }).issues)
        }
    }

    It 'flags <Case> in <Field>' -ForEach @(
        @{ Case = 'a line break'; Field = 'descriptionOverride'; Value = "one`ntwo"; Reason = 'must be one line'; CodePoint = 'U+000A' }
        @{ Case = 'a tab'; Field = 'title'; Value = "Tab`tTool"; Reason = 'control character'; CodePoint = 'U+0009' }
        @{ Case = 'a C1 control'; Field = 'upstreamLicense'; Value = ('MIT' + [char]0x9B); Reason = 'control character'; CodePoint = 'U+009B' }
        @{ Case = 'a bidi override'; Field = 'title'; Value = ('Safe' + [char]0x202E + 'exe.txt'); Reason = 'bidi'; CodePoint = 'U+202E' }
        @{ Case = 'a bidi isolate'; Field = 'currentlyBuildingText'; Value = ('x' + [char]0x2068 + 'y'); Reason = 'bidi'; CodePoint = 'U+2068' }
        @{ Case = 'a lone surrogate'; Field = 'forkOf'; Value = ('owner/re' + [char]0xDC00 + 'po'); Reason = 'unpaired surrogate'; CodePoint = 'U+DC00' }
    ) {
        $entry = New-TestEntry -Repo 'ShapeTool' -Category 'powershell'
        $entry[$Field] = $Value

        $issue = @(script:Get-ShapeIssues -Entry $entry | Where-Object { $_.field -eq $Field })
        $issue | Should -HaveCount 1
        $issue[0].reason | Should -Match $Reason
        $issue[0].value | Should -Be $CodePoint -Because 'the report records the code point, not the text'
    }

    It 'accepts accented, non-Latin and emoji text' {
        $entry = New-TestEntry -Repo 'ShapeTool' -Category 'powershell'
        $entry.title = 'Outil café'
        $entry.descriptionOverride = ('日本語 · עברית · Инструмент ' + [char]::ConvertFromUtf32(0x1F680))

        @(script:Get-ShapeIssues -Entry $entry) | Should -BeNullOrEmpty
    }

    It 'keeps install-command values to a safe shape' -ForEach @(
        @{ Field = 'entrypoint'; Value = 'run$(Remove-Item x).ps1' }
        @{ Field = 'entrypoint'; Value = 'tool.ps1"; Remove-Item x; "' }
        @{ Field = 'entrypoint'; Value = '..\outside.ps1' }
        @{ Field = 'entrypoint'; Value = 'notes.txt' }
        @{ Field = 'branch'; Value = 'main; Remove-Item x' }
        @{ Field = 'branch'; Value = '--upload-pack=touch' }
        @{ Field = 'entrypoint'; Value = "tool.ps1`n" }
        @{ Field = 'branch'; Value = "main`n" }
    ) {
        $entry = New-TestEntry -Repo 'ShapeTool' -Category 'powershell'
        $entry[$Field] = $Value

        @(script:Get-ShapeIssues -Entry $entry | Where-Object { $_.field -eq $Field }) | Should -HaveCount 1
    }

    It 'accepts the install-command values the catalog uses today' {
        foreach ($entrypoint in @('app\main.py', 'flux-torrent\Launch-Flux.ps1', 'JDownloader 2 Ultimate Manager.ps1', 'gui.pyw')) {
            $entry = New-TestEntry -Repo 'ShapeTool' -Category 'powershell'
            $entry.entrypoint = $entrypoint
            $entry.installKind = if ($entrypoint -like '*.ps1') { 'powershell' } else { 'python' }
            $entry.branch = 'project-XT'
            @(script:Get-ShapeIssues -Entry $entry) | Should -BeNullOrEmpty -Because "$entrypoint is a real entrypoint"
        }
    }

    It 'holds public text to the schema length limits' {
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $catalog.entries[0].title = 'T' * 101
        $catalog.entries[1].descriptionOverride = 'D' * 301

        $result = Test-FeedSchemaContracts -Catalog $catalog -ProjectsJson (New-ProjectsExportJson -Catalog $catalog -Repos @())

        $result.catalog.valid | Should -BeFalse
        @($result.catalog.errors | ForEach-Object { $_.instanceLocation }) | Should -Contain '/entries/0/title'
        @($result.catalog.errors | ForEach-Object { $_.instanceLocation }) | Should -Contain '/entries/1/descriptionOverride'
    }

    It 'passes the committed catalog' {
        $shape = Test-CatalogShape -Catalog (Get-Catalog -Path (Join-Path $script:RepoRoot 'data/profile-catalog.json'))
        @($shape.issues | ForEach-Object { '{0}.{1}: {2}' -f $_.repo, $_.field, $_.reason }) | Should -BeNullOrEmpty
    }

    It 'keeps the committed feed''s <Field> in step with <Source>' -ForEach @(
        @{ Field = 'generatorSha256'; Source = 'the generator' }
        @{ Field = 'catalogSha256'; Source = 'the catalog' }
        @{ Field = 'projectSchemaSha256'; Source = 'the feed schema' }
    ) {
        # A generator, catalog or schema change committed without regenerating leaves
        # projects.json naming the old file, and -Check fails on it. validate-local skips the
        # profile check, so the suite has to notice.
        $feed = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'projects.json') -Raw | ConvertFrom-Json

        $feed.provenance.$Field | Should -Be (New-ProjectsProvenance -Repos @()).$Field -Because "a change to $Source needs scripts/sync-profile.ps1 -Write -Check -GraphQlPageSize 300 in the same commit"
    }
}

Describe 'run.ps1 install dispatcher' {
    BeforeAll {
        $script:RunScriptPath = Join-Path $script:RepoRoot 'run.ps1'
        . $script:RunScriptPath

        function script:New-FakeFeed {
            param([string]$Repo = 'WinTool', [string]$Branch = 'main', [string]$Entrypoint = 'WinTool.ps1')
            [pscustomobject]@{
                projects = @(
                    [pscustomobject]@{ repo = 'NoEntry'; branch = 'main'; entrypoint = $null }
                    [pscustomobject]@{ repo = $Repo; branch = $Branch; entrypoint = $Entrypoint }
                )
            }
        }
    }

    BeforeEach {
        $script:SavedTemp = $env:TEMP
        $env:TEMP = Join-Path $TestDrive ('temp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $env:TEMP | Out-Null
        $script:ToolCalls = New-Object System.Collections.Generic.List[string]
    }

    AfterEach {
        $env:TEMP = $script:SavedTemp
    }

    It 'is pure ASCII Windows PowerShell 5.1 syntax that only defines Start-Tool' {
        $bytes = [System.IO.File]::ReadAllBytes($script:RunScriptPath)
        @($bytes | Where-Object { $_ -gt 127 }) | Should -BeNullOrEmpty
        $text = [System.IO.File]::ReadAllText($script:RunScriptPath)
        $text | Should -Match '(?m)^#Requires -Version 5\.1\s*$'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        # Nothing but the function at the top level, so irm | iex has no side effect.
        @($ast.EndBlock.Statements | ForEach-Object { $_.GetType().Name }) | Should -Be @('FunctionDefinitionAst')
        $text | Should -Not -Match '\?\?|\?\.|ForEach-Object -Parallel|\s-AsHashtable'
    }

    It 'parses in Windows PowerShell 5.1 itself' {
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $windowsPowerShell)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not installed here'
            return
        }
        $check = "`$e = `$null; `$t = `$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$($script:RunScriptPath)', [ref]`$t, [ref]`$e); `$e.Count"
        $parseErrors = & $windowsPowerShell -NoProfile -NonInteractive -Command $check
        $LASTEXITCODE | Should -Be 0
        [int]$parseErrors | Should -Be 0
    }

    It 'runs end to end in Windows PowerShell 5.1, fed through iex like the README line' {
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $windowsPowerShell)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not installed here'
            return
        }
        # The feed and git are stubbed, so nothing leaves the machine and the entry script is
        # one this test wrote. A function wins over a cmdlet of the same name, so the stub
        # feed also replaces Invoke-RestMethod inside Start-Tool. The entry script reports
        # the error preference it sees and any of Start-Tool's variables it can read.
        $driver = @'
function Invoke-RestMethod { [pscustomobject]@{ projects = @([pscustomobject]@{ repo = 'WinTool'; branch = 'main'; entrypoint = 'Tools\Win Tool.ps1' }) } }
function git {
    if ($args[0] -eq 'clone') {
        $directory = [string]$args[-1]
        New-Item -ItemType Directory -Path (Join-Path $directory 'Tools') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $directory 'Tools\Win Tool.ps1') -Value @(
            '$leaked = @(''feed'', ''project'', ''repo'', ''directory'', ''target'', ''profileOwner'') | Where-Object { Get-Variable -Name $_ -ErrorAction SilentlyContinue }'
            '"ran in PowerShell $($PSVersionTable.PSVersion.Major) with $ErrorActionPreference; leaked=$($leaked -join '','')"'
        )
    }
    $global:LASTEXITCODE = 0
}
Get-Content -Raw -LiteralPath $env:SYSADMINDOC_RUN_SCRIPT | Invoke-Expression
Start-Tool WinTool
'@
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($driver))
        $env:SYSADMINDOC_RUN_SCRIPT = $script:RunScriptPath
        try {
            $output = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1 | ForEach-Object { [string]$_ })
        } finally {
            Remove-Item Env:SYSADMINDOC_RUN_SCRIPT -ErrorAction SilentlyContinue
        }

        $LASTEXITCODE | Should -Be 0
        $output | Should -Contain 'ran in PowerShell 5 with Continue; leaked='
    }

    It 'clones, installs requirements and runs the entry script the feed names' {
        Mock Invoke-RestMethod { New-FakeFeed }
        function git {
            $script:ToolCalls.Add('git ' + ($args -join ' '))
            if ($args[0] -eq 'clone') {
                $directory = [string]$args[-1]
                New-Item -ItemType Directory -Path $directory | Out-Null
                Set-Content -LiteralPath (Join-Path $directory 'requirements.txt') -Value 'rich' -Encoding utf8
                Set-Content -LiteralPath (Join-Path $directory 'WinTool.ps1') -Value "Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'ran.txt') -Value 'ran'" -Encoding utf8
            }
            $global:LASTEXITCODE = 0
        }
        function python { $script:ToolCalls.Add('python ' + ($args -join ' ')); $global:LASTEXITCODE = 0 }

        Start-Tool WinTool

        $directory = Join-Path $env:TEMP 'WinTool'
        $script:ToolCalls[0] | Should -Be "git clone -q --depth 1 -b main https://github.com/SysAdminDoc/WinTool $directory"
        # A working python first, then python -m pip, so the requirements land in the
        # interpreter a Python tool runs in.
        $script:ToolCalls[1] | Should -Be 'python --version'
        $script:ToolCalls[2] | Should -Be ('python -m pip install -q -r ' + (Join-Path $directory 'requirements.txt'))
        Get-Content -LiteralPath (Join-Path $directory 'ran.txt') | Should -Be 'ran'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/projects.json' }
    }

    It 'runs the entry script with the session''s error preference, not a caller''s' {
        # The tool runs as if from the prompt, like the old one-liner: it sees the session's
        # (global) preference, and neither a stricter one in Start-Tool nor its caller's own.
        Mock Invoke-RestMethod { New-FakeFeed }
        function git {
            if ($args[0] -eq 'clone') {
                $directory = [string]$args[-1]
                New-Item -ItemType Directory -Path $directory | Out-Null
                Set-Content -LiteralPath (Join-Path $directory 'WinTool.ps1') -Value "Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'preference.txt') -Value `$ErrorActionPreference" -Encoding utf8
            }
            $global:LASTEXITCODE = 0
        }
        $savedPreference = $global:ErrorActionPreference
        try {
            $global:ErrorActionPreference = 'SilentlyContinue'
            $ErrorActionPreference = 'Stop'

            Start-Tool WinTool
        } finally {
            $global:ErrorActionPreference = $savedPreference
        }

        Get-Content -LiteralPath (Join-Path $env:TEMP 'WinTool\preference.txt') | Should -Be 'SilentlyContinue'
    }

    It 'says how to recover when git cannot update an old copy' {
        Mock Invoke-RestMethod { New-FakeFeed }
        New-Item -ItemType Directory -Path (Join-Path $env:TEMP 'WinTool') | Out-Null
        function git { $global:LASTEXITCODE = 128 }

        { Start-Tool WinTool } | Should -Throw '*exit 128*delete it and run Start-Tool again*'
    }

    It 'stops before cloning when <Tool> is missing' -ForEach @(
        @{ Tool = 'git'; Entrypoint = 'WinTool.ps1'; Message = "*git isn't installed or isn't on PATH*" }
        @{ Tool = 'python'; Entrypoint = 'app.py'; Message = "*is a Python tool, and python isn't installed*" }
    ) {
        # Without the check a missing git left an old exit code behind, and the tool was
        # started from a folder that was never cloned.
        $script:MissingTool = $Tool
        $script:FakeEntrypoint = $Entrypoint
        Mock Invoke-RestMethod { New-FakeFeed -Entrypoint $script:FakeEntrypoint }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq $script:MissingTool }
        function git { $script:ToolCalls.Add('git'); $global:LASTEXITCODE = 0 }
        function python { $script:ToolCalls.Add('python'); $global:LASTEXITCODE = 0 }

        { Start-Tool WinTool } | Should -Throw $Message
        @($script:ToolCalls) | Should -BeNullOrEmpty
        # git is checked before the feed request; python needs the feed's entry script first.
        Should -Invoke Invoke-RestMethod -Times $(if ($Tool -eq 'git') { 0 } else { 1 }) -Exactly
    }

    It 'matches a feed row by its exact name, whatever the case' {
        # -eq compared by culture, which skips an invisible character, so a row named
        # Win<U+200B>Tool answered Start-Tool WinTool. Case still doesn't matter, as on GitHub.
        Mock Invoke-RestMethod { New-FakeFeed -Repo ('Win' + [char]0x200B + 'Tool') }
        function git { $script:ToolCalls.Add('git'); $global:LASTEXITCODE = 0 }

        { Start-Tool WinTool } | Should -Throw '*is not a project you can run*'
        @($script:ToolCalls) | Should -BeNullOrEmpty

        Mock Invoke-RestMethod { New-FakeFeed -Repo 'WinTool' }
        function git {
            $script:ToolCalls.Add('git ' + $args[0])
            if ($args[0] -eq 'clone') {
                $directory = [string]$args[-1]
                New-Item -ItemType Directory -Path $directory | Out-Null
                Set-Content -LiteralPath (Join-Path $directory 'WinTool.ps1') -Value "Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'ran.txt') -Value 'ran'" -Encoding utf8
            }
            $global:LASTEXITCODE = 0
        }

        Start-Tool wintool
        Get-Content -LiteralPath (Join-Path $env:TEMP 'WinTool\ran.txt') | Should -BeOrdinal 'ran'
    }

    It 'treats a python that can''t report its version as missing' {
        # On a machine without Python, the python on PATH is often the Store's stand-in,
        # which prints "Python was not found" and exits 9009.
        Mock Invoke-RestMethod { New-FakeFeed -Repo 'PyTool' -Entrypoint 'app.py' }
        function git { $script:ToolCalls.Add('git'); $global:LASTEXITCODE = 0 }
        function python { $script:ToolCalls.Add('python ' + ($args -join ' ')); $global:LASTEXITCODE = 9009 }

        { Start-Tool PyTool } | Should -Throw "*is a Python tool, and python isn't installed*"
        @($script:ToolCalls) | Should -Be @('python --version')
    }

    It 'judges <Case> by its exit code in Windows PowerShell 5.1 with <Via> at Stop' -ForEach @(
        @{ Case = 'Python 2, which prints its version on stderr'; Via = 'the session'; Stub = 'if "%~1"=="--version" (echo Python 2.7.18 1>&2& exit /b 0)'; Started = $true }
        @{ Case = 'a python that prints a warning on stderr'; Via = 'the session'; Stub = 'if "%~1"=="--version" (echo warning: user site not writable 1>&2& echo Python 3.12.0& exit /b 0)'; Started = $true }
        @{ Case = 'the Store stand-in'; Via = 'the session'; Stub = 'echo Python was not found; run without arguments to install from the Microsoft Store 1>&2& exit /b 9009'; Started = $false }
        # -ErrorAction Stop sets Start-Tool's own preference, which the check inherits, with
        # the session left at Continue.
        @{ Case = 'Python 2, which prints its version on stderr'; Via = 'Start-Tool -ErrorAction Stop'; Stub = 'if "%~1"=="--version" (echo Python 2.7.18 1>&2& exit /b 0)'; Started = $true }
    ) {
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $windowsPowerShell)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not installed here'
            return
        }
        # With the session at Stop, Windows PowerShell turned any stderr line from python
        # --version into an error, so a working python read as missing. Real python.cmd
        # stubs, since a function stub writes no stderr.
        $binPath = Join-Path $TestDrive ('python-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $binPath | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $binPath 'python.cmd'), "@echo off`r`n$Stub`r`necho ran> `"%~dp0ran.txt`"`r`nexit /b 0`r`n")
        $viaCall = $Via -eq 'Start-Tool -ErrorAction Stop'
        $driver = @'
$ErrorActionPreference = '<session-preference>'
function Invoke-RestMethod { [pscustomobject]@{ projects = @([pscustomobject]@{ repo = 'PyTool'; branch = 'main'; entrypoint = 'app.py' }) } }
function git { if ($args[0] -eq 'clone') { New-Item -ItemType Directory -Path ([string]$args[-1]) -Force | Out-Null }; $global:LASTEXITCODE = 0 }
Get-Content -Raw -LiteralPath $env:SYSADMINDOC_RUN_SCRIPT | Invoke-Expression
try { Start-Tool PyTool<call-arguments>; 'started' } catch { 'threw: ' + $_.Exception.Message }
'@.Replace('<session-preference>', $(if ($viaCall) { 'Continue' } else { 'Stop' })).Replace('<call-arguments>', $(if ($viaCall) { ' -ErrorAction Stop' } else { '' }))
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($driver))
        $savedPath = $env:PATH
        $env:SYSADMINDOC_RUN_SCRIPT = $script:RunScriptPath
        try {
            $env:PATH = $binPath + [System.IO.Path]::PathSeparator + $savedPath
            $output = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1 | ForEach-Object { [string]$_ })
        } finally {
            $env:PATH = $savedPath
            Remove-Item Env:SYSADMINDOC_RUN_SCRIPT -ErrorAction SilentlyContinue
        }

        if ($Started) {
            $output | Should -Contain 'started' -Because ($output -join "`n")
            Test-Path -LiteralPath (Join-Path $binPath 'ran.txt') | Should -BeTrue -Because 'the tool itself ran with that python'
        } else {
            ($output -join "`n") | Should -Match "threw: Start-Tool: PyTool is a Python tool, and python isn't installed"
            Test-Path -LiteralPath (Join-Path $binPath 'ran.txt') | Should -BeFalse
        }
    }

    It 'warns when the requirements fail to install and still starts the tool' {
        Mock Invoke-RestMethod { New-FakeFeed }
        function git {
            if ($args[0] -eq 'clone') {
                $directory = [string]$args[-1]
                New-Item -ItemType Directory -Path $directory | Out-Null
                Set-Content -LiteralPath (Join-Path $directory 'requirements.txt') -Value 'rich' -Encoding utf8
                Set-Content -LiteralPath (Join-Path $directory 'WinTool.ps1') -Value "Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'ran.txt') -Value 'ran'" -Encoding utf8
            }
            $global:LASTEXITCODE = 0
        }
        # A working python whose pip install fails.
        function python { $global:LASTEXITCODE = $(if ($args[0] -eq '--version') { 0 } else { 1 }) }

        Start-Tool WinTool -WarningVariable warnings 3>$null

        @($warnings) | Should -HaveCount 1
        [string]$warnings[0] | Should -Match 'requirements failed \(exit 1\); starting it anyway'
        Get-Content -LiteralPath (Join-Path $env:TEMP 'WinTool\ran.txt') | Should -Be 'ran'
    }

    It 'runs the tool with none of Start-Tool''s variables in reach' {
        # The old one-liner ran the tool from the prompt, where only its own $d existed.
        Mock Invoke-RestMethod { New-FakeFeed }
        function git {
            if ($args[0] -eq 'clone') {
                $directory = [string]$args[-1]
                New-Item -ItemType Directory -Path $directory | Out-Null
                Set-Content -LiteralPath (Join-Path $directory 'WinTool.ps1') -Encoding utf8 -Value @(
                    '$names = @(''Name'', ''feed'', ''project'', ''repo'', ''branch'', ''entrypoint'', ''directory'', ''requirements'', ''target'', ''profileOwner'', ''usesPython'')'
                    'Set-Content -LiteralPath (Join-Path $PSScriptRoot ''leaked.txt'') -Value (@($names | Where-Object { Get-Variable -Name $_ -ErrorAction SilentlyContinue }) -join '','')'
                )
            }
            $global:LASTEXITCODE = 0
        }

        Start-Tool WinTool

        [System.IO.File]::ReadAllText((Join-Path $env:TEMP 'WinTool\leaked.txt')).Trim() | Should -BeNullOrEmpty
    }

    It 'updates an existing copy and runs a Python entry script with python' {
        Mock Invoke-RestMethod { New-FakeFeed -Repo 'PyTool' -Branch 'master' -Entrypoint 'app\main.py' }
        New-Item -ItemType Directory -Path (Join-Path $env:TEMP 'PyTool') | Out-Null
        function git { $script:ToolCalls.Add('git ' + ($args -join ' ')); $global:LASTEXITCODE = 0 }
        function python { $script:ToolCalls.Add('python ' + ($args -join ' ')); $global:LASTEXITCODE = 0 }

        Start-Tool PyTool

        $directory = Join-Path $env:TEMP 'PyTool'
        # python --version first: a python that can't answer is the Store's stand-in.
        @($script:ToolCalls) | Should -Be @('python --version', "git -C $directory pull -q", ('python ' + (Join-Path $directory 'app\main.py')))
    }

    It 'refuses <Case> before git or any script runs' -ForEach @(
        @{ Case = 'an unsafe name'; Name = '..\WinTool'; Feed = @{} }
        @{ Case = 'an entry script that expands code'; Name = 'WinTool'; Feed = @{ Entrypoint = 'run$(Remove-Item x).ps1' } }
        @{ Case = 'an entry script outside the checkout'; Name = 'WinTool'; Feed = @{ Entrypoint = '..\outside.ps1' } }
        @{ Case = 'a branch that looks like an option'; Name = 'WinTool'; Feed = @{ Branch = '--upload-pack=touch' } }
        @{ Case = 'a project that is not in the feed'; Name = 'Missing'; Feed = @{} }
    ) {
        $script:FeedOverride = $Feed
        Mock Invoke-RestMethod { New-FakeFeed @script:FeedOverride }
        function git { $script:ToolCalls.Add('git') }

        { Start-Tool $Name } | Should -Throw 'Start-Tool:*'
        @($script:ToolCalls) | Should -BeNullOrEmpty
    }

    It 'requires installKind to match the entry script run.ps1 will start' {
        $entry = New-TestEntry -Repo 'KindTool' -Category 'python'
        $entry.entrypoint = 'KindTool.ps1'
        $entry.installKind = 'python'

        $issue = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq 'installKind' })
        $issue | Should -HaveCount 1
        $issue[0].reason | Should -Match 'installKind must be powershell'
    }
}

Describe 'Sync report stays valid against its own schema for small catalogs' {
    BeforeAll {
        $script:SmallCatalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $script:SmallReadme = New-Readme -Catalog $script:SmallCatalog -Repos @()
        $script:SmallProjects = New-ProjectsExportJson -Catalog $script:SmallCatalog -Repos @()

        function script:Invoke-SmallCatalogState {
            param([string]$Readme = $script:SmallReadme)
            # A missing smoke artifact, so the not-run stub is what gets validated even on a
            # machine that has a local rendered-smoke run.
            Test-ProfileState -Catalog $script:SmallCatalog -Repos @() -ExpectedReadme $Readme -ExpectedProjects $script:SmallProjects `
                -ExpectedAssets @{} -CurrentReadme $Readme -CurrentProjects $script:SmallProjects -CurrentAssets @{} -SkipLinkValidation `
                -SmokeReportPath (Join-Path $TestDrive 'no-smoke-run.json')
        }
    }

    It 'validates the report built from the fixture catalog with no repositories' {
        $result = script:Invoke-SmallCatalogState
        $errors = @($result.Report.schemaValidation.report.errors | ForEach-Object { '{0} {1}' -f $_.instanceLocation, $_.message })

        $errors | Should -BeNullOrEmpty
        $result.Report.schemaValidation.report.valid | Should -BeTrue
        $result.Report.renderedProfileSmoke.status | Should -Be 'not-run'
        $result.Report.renderedProfileSmoke.Contains('tableOverflowDisposition') | Should -BeTrue
        $result.Report.renderedProfileSmoke.tableOverflowDisposition | Should -BeNullOrEmpty
        # The fixture has exactly one suppressed row and no license data: the two list
        # shapes a PowerShell return used to unroll.
        ,$result.Report.staleProjectReview.suppressionReasonCounts | Should -BeOfType [System.Array]
        @($result.Report.staleProjectReview.suppressionReasonCounts) | Should -HaveCount 1
        ,$result.Report.projectLicenseMetadata.licenseCounts | Should -BeOfType [System.Array]
        @($result.Report.projectLicenseMetadata.licenseCounts) | Should -HaveCount 0
    }

    It 'still validates when a header anchor is dead' {
        $planted = '<p align="center"><a href="#section-that-does-not-exist">Go</a></p>' + "`n" + $script:SmallReadme
        $result = script:Invoke-SmallCatalogState -Readme $planted

        [bool]$result.FailureConditions['linkFailures'] | Should -BeTrue
        $row = @($result.Report.linkValidationFailures | Where-Object { $_.type -eq 'readme-header-anchor' })[0]
        @($row.Keys) | Should -Be @('repo', 'type', 'url', 'host', 'status', 'error')
        $result.Report.schemaValidation.report.valid | Should -BeTrue -Because 'a dead link fails linkFailures, not the report schema'
    }

    It 'still validates when the profile version file is malformed or incomplete' -ForEach @(
        @{ Case = 'malformed'; Json = '{"version":"v4.10","date":"not-a-date"}'; Version = 'v4.10' }
        @{ Case = 'missing version'; Json = '{"date":"2026-09-23"}'; Version = $null }
    ) {
        # docVersionConsistency reports what it found and fails the run itself; the report
        # schema has to be able to carry the bad value, or one typo fails two checks.
        $versionPath = Join-Path $TestDrive 'profile-version.json'
        Set-Content -LiteralPath $versionPath -Value $Json -Encoding utf8
        $savedVersionPath = $script:ProfileVersionPath
        $script:ProfileVersionPath = $versionPath
        try {
            $result = script:Invoke-SmallCatalogState
        } finally {
            $script:ProfileVersionPath = $savedVersionPath
        }

        $result.Report.docVersionConsistency.passed | Should -BeFalse
        $result.Report.docVersionConsistency.expectedVersion | Should -Be $Version
        @($result.Report.schemaValidation.report.errors | ForEach-Object { '{0} {1}' -f $_.instanceLocation, $_.message }) | Should -BeNullOrEmpty
    }

    It 'keeps a single license count a list' {
        $entry = New-TestEntry -Repo 'Licensed' -Category 'powershell'
        $meta = New-TestRepoMeta -Name 'Licensed' -LicenseInfo ([pscustomobject]@{ spdxId = 'MIT'; key = 'mit'; name = 'MIT License' })
        $result = Test-ProjectLicenseMetadata -Entries @($entry) -RepoLookup (ConvertTo-Lookup @($meta))

        ,$result.licenseCounts | Should -BeOfType [System.Array]
        @($result.licenseCounts) | Should -HaveCount 1
        ($result | ConvertTo-Json -Depth 5) | Should -Match '"licenseCounts":\s*\['
    }
}

Describe 'PR delivery checklist carries no recorded history' {
    It 'reports a workflow-enabled repository without borrowing this repository''s PR drills' {
        # Only reachable when workflows exist, which this repository no longer has. The
        # checklist used to fill in PR #14 and #16 as passed evidence for any owner.
        $transition = Get-PrDeliveryTransitionChecklist `
            -WorkflowCoverage ([ordered]@{ status = 'ready'; workflowCount = 2; warningCount = 0 }) `
            -RequiredChecksEnabled $true `
            -EnforceAdmins $true `
            -ActionsPullRequestCreationAllowed $true `
            -BranchProtectionAvailable $true `
            -RulesetsAvailable $true

        $transition.routineMaintenancePrDrillEvidence | Should -BeNullOrEmpty
        $transition.requiredCheckEnforcementEvidence | Should -BeNullOrEmpty
        $transition.directMainMaintenancePolicy | Should -BeNullOrEmpty
        ($transition | ConvertTo-Json -Depth 10) | Should -Not -Match 'PR #1[46]|pull/1[46]|27090770'
        @($transition.items | Where-Object { $_.id -eq 'pr-delivery-or-bypass' })[0].status | Should -Be 'needs-live-validation'
        $transition.readyForRequiredCheckEnforcement | Should -BeFalse
    }

    It 'describes PR creation <PrCreation>, required checks <Checks> and admins <Admins> as they are' -ForEach @(
        foreach ($prCreation in @('on', 'off', 'unknown')) {
            foreach ($checks in @('on', 'off')) {
                foreach ($admins in @('enforced', 'not enforced')) {
                    @{ PrCreation = $prCreation; Checks = $checks; Admins = $admins }
                }
            }
        }
    ) {
        $allowed = switch ($PrCreation) { 'on' { $true } 'off' { $false } default { $null } }
        $transition = Get-PrDeliveryTransitionChecklist `
            -WorkflowCoverage ([ordered]@{ status = 'ready'; workflowCount = 1; warningCount = 0 }) `
            -RequiredChecksEnabled ($Checks -eq 'on') `
            -EnforceAdmins ($Admins -eq 'enforced') `
            -ActionsPullRequestCreationAllowed $allowed `
            -BranchProtectionAvailable $true `
            -RulesetsAvailable $true
        $delivery = @($transition.items | Where-Object { $_.id -eq 'pr-delivery-or-bypass' })[0]

        # Workflows exist on this path, so nothing may describe the local-only posture.
        "$($delivery.evidence) $($delivery.nextAction)" | Should -Not -Match 'absent|retired|offline-only'
        $delivery.status | Should -Be $(if ($PrCreation -eq 'off') { 'blocked' } else { 'needs-live-validation' })
        $delivery.nextAction | Should -Match 'merge drill'
        if ($Checks -eq 'on') {
            $delivery.nextAction | Should -Match 'while the checks are required'
            $delivery.nextAction | Should -Not -Match 'before enabling'
        } else {
            $delivery.nextAction | Should -Match 'before enabling required checks'
        }
        switch ($PrCreation) {
            'off' { $delivery.evidence | Should -Match "don't let GitHub Actions create pull requests" }
            'unknown' { $delivery.evidence | Should -Match "couldn't be read" }
            'on' { $delivery.evidence | Should -Match 'may create pull requests' }
        }
    }

    It 'blocks on admin enforcement only while the checks are not yet required' -ForEach @(
        @{ Case = 'branch protection requires the checks'; RequiredStatusChecks = $true; RulesetCount = 0; RulesetRequires = $false; Enforced = $true }
        @{ Case = 'a ruleset requires the checks'; RequiredStatusChecks = $false; RulesetCount = 1; RulesetRequires = $true; Enforced = $true }
        @{ Case = 'a ruleset exists but requires nothing'; RequiredStatusChecks = $false; RulesetCount = 1; RulesetRequires = $false; Enforced = $false }
        @{ Case = 'nothing requires the checks'; RequiredStatusChecks = $false; RulesetCount = 0; RulesetRequires = $false; Enforced = $false }
    ) {
        Mock Test-RequiredCheckWorkflowCoverage { [ordered]@{ status = 'ready'; workflowCount = 1; candidateCheckCount = 1; warningCount = 0; warnings = @(); workflows = @() } }

        $readiness = Get-RequiredCheckReadiness -BranchProtectionAvailable:$true -RulesetsAvailable:$true `
            -RequiredStatusChecks $RequiredStatusChecks -EnforceAdmins $true -ActionsPullRequestCreationAllowed $true `
            -RulesetCount $RulesetCount -RulesetRequiresStatusChecks $RulesetRequires -BranchProtectionUnavailableReason '' -RulesetsUnavailableReason ''

        $adminBlockers = @($readiness.blockers | Where-Object { $_ -match 'enforces admins' })
        if ($Enforced) {
            $adminBlockers | Should -BeNullOrEmpty -Because "$Case, so a drill 'before required checks are enabled' is already past"
            @($readiness.blockers) | Should -BeNullOrEmpty
            $readiness.recommendation | Should -Be 'monitor-required-check-enforcement'
        } else {
            $adminBlockers | Should -HaveCount 1
            $readiness.recommendation | Should -Be 'defer-until-pr-delivery-or-bypass'
        }
    }

    It 'counts a ruleset as enforcement only for <Case>' -ForEach @(
        @{ Case = 'an active required_status_checks rule on main'; BranchRules = @([pscustomobject]@{ type = 'required_status_checks'; ruleset_id = 7 }); Enforced = $true }
        @{ Case = 'nothing when the only active rule blocks deletion'; BranchRules = @([pscustomobject]@{ type = 'deletion'; ruleset_id = 7 }); Enforced = $false }
        @{ Case = 'nothing when no rule is active'; BranchRules = @(); Enforced = $false }
    ) {
        # The ruleset list includes tag rulesets and disabled ones, so it can't stand for
        # enforcement; the branch's active rules can.
        $savedCandidates = $script:RequiredStatusCheckCandidates
        $script:RequiredStatusCheckCandidates = @([ordered]@{ name = 'validate'; workflow = '.github/workflows/validate.yml' })
        try {
            $result = Test-RepositoryCommunityBaseline `
                -Repository ([pscustomobject]@{ name = 'SysAdminDoc'; default_branch = 'main' }) `
                -BranchProtection ([pscustomobject]@{ enforce_admins = [pscustomobject]@{ enabled = $true } }) `
                -Rulesets @([pscustomobject]@{ id = 1; name = 'release tags'; target = 'tag'; enforcement = 'disabled' }) `
                -BranchRules $BranchRules `
                -ActionsWorkflowPermissions ([pscustomobject]@{ default_workflow_permissions = 'read'; can_approve_pull_request_reviews = $true }) `
                -CommunityUnavailableReason 'not needed here' -LanguagesUnavailableReason 'not needed here' `
                -ScorecardAlertsUnavailableReason 'not needed here' -ScorecardScoreUnavailableReason 'not needed here'
        } finally {
            $script:RequiredStatusCheckCandidates = $savedCandidates
        }

        $settings = $result['repositorySettings']
        $settings.rulesets.count | Should -Be 1
        $settings.rulesets.requiresStatusChecks | Should -Be $Enforced
        if ($Enforced) {
            $settings.requiredCheckReadiness.status | Should -Be 'enforcement-present'
            @($settings.requiredCheckReadiness.blockers) | Should -BeNullOrEmpty
            $settings.requiredCheckReadiness.recommendation | Should -Be 'monitor-required-check-enforcement'
        } else {
            $settings.requiredCheckReadiness.readyForEnforcement | Should -BeFalse
            $settings.requiredCheckReadiness.recommendation | Should -Be 'defer-until-pr-delivery-or-bypass'
            @($settings.requiredCheckReadiness.blockers | Where-Object { $_ -match 'enforces admins' }) | Should -HaveCount 1
        }
    }

    It 'agrees with itself when branch protection is <Protection>, the ruleset list <List> and the branch rules <Rules>' -ForEach @(
        foreach ($protection in @('requiring checks', 'requiring nothing', 'unreadable')) {
            foreach ($list in @('readable', 'unreadable')) {
                foreach ($rules in @('requiring checks', 'requiring nothing', 'unreadable')) {
                    @{ Protection = $protection; List = $list; Rules = $rules }
                }
            }
        }
    ) {
        # Status used to key on the ruleset list while enforcement keyed on the branch rules,
        # so one combination reported needs-live-validation and ready at the same time.
        $protectionValue = $null
        if ($Protection -eq 'requiring checks') {
            $protectionValue = [pscustomobject]@{ required_status_checks = [pscustomobject]@{ strict = $true; contexts = @('validate') }; enforce_admins = [pscustomobject]@{ enabled = $false } }
        } elseif ($Protection -eq 'requiring nothing') {
            $protectionValue = [pscustomobject]@{ enforce_admins = [pscustomobject]@{ enabled = $false } }
        }
        $listValue = $null
        if ($List -eq 'readable') { $listValue = @([pscustomobject]@{ id = 1; name = 'main'; target = 'branch'; enforcement = 'active' }) }
        $rulesValue = $null
        if ($Rules -eq 'requiring checks') {
            $rulesValue = @([pscustomobject]@{ type = 'required_status_checks'; ruleset_id = 1 })
        } elseif ($Rules -eq 'requiring nothing') {
            $rulesValue = @()
        }
        $savedCandidates = $script:RequiredStatusCheckCandidates
        $script:RequiredStatusCheckCandidates = @([ordered]@{ name = 'validate'; workflow = '.github/workflows/validate.yml' })
        try {
            $result = Test-RepositoryCommunityBaseline `
                -Repository ([pscustomobject]@{ name = 'SysAdminDoc'; default_branch = 'main' }) `
                -BranchProtection $protectionValue -BranchProtectionUnavailableReason $(if ($null -eq $protectionValue) { 'HTTP 404: Branch not protected' } else { '' }) `
                -Rulesets $listValue -RulesetsUnavailableReason $(if ($null -eq $listValue) { 'HTTP 403' } else { '' }) `
                -BranchRules $rulesValue -BranchRulesUnavailableReason $(if ($Rules -eq 'unreadable') { 'HTTP 502' } else { '' }) `
                -ActionsWorkflowPermissions ([pscustomobject]@{ default_workflow_permissions = 'read'; can_approve_pull_request_reviews = $true }) `
                -CommunityUnavailableReason 'not needed here' -LanguagesUnavailableReason 'not needed here' `
                -ScorecardAlertsUnavailableReason 'not needed here' -ScorecardScoreUnavailableReason 'not needed here'
        } finally {
            $script:RequiredStatusCheckCandidates = $savedCandidates
        }

        $settings = $result['repositorySettings']
        $readiness = $settings.requiredCheckReadiness
        $blockers = @($readiness.blockers)
        $enforcementItem = @($readiness.prDeliveryTransition.items | Where-Object { $_.id -eq 'enforcement-mechanism' })[0]
        if ($Protection -eq 'requiring checks' -or $Rules -eq 'requiring checks') {
            $readiness.status | Should -Be 'enforcement-present'
            $readiness.recommendation | Should -Be 'monitor-required-check-enforcement'
            # Nothing blocks, but no check-run proof or merge drill is recorded, so the
            # checklist isn't ready, and readiness says the same.
            $readiness.readyForEnforcement | Should -BeFalse
            $blockers | Should -BeNullOrEmpty
            $enforcementItem.status | Should -Be 'ready'
        } elseif ($Protection -eq 'requiring nothing' -and $Rules -eq 'requiring nothing') {
            $readiness.status | Should -Be 'not-enabled'
            $readiness.recommendation | Should -Be 'defer-until-pr-delivery-or-bypass'
            $readiness.readyForEnforcement | Should -BeFalse
            $blockers | Should -Contain 'Branch protection does not require status checks.'
            $blockers | Should -Contain 'No active repository ruleset requires status checks on the default branch.'
            $enforcementItem.status | Should -Be 'blocked'
        } else {
            # Unknown: nothing may read as ready, and nothing unread may read as absent.
            $readiness.status | Should -Be 'needs-live-validation'
            $readiness.recommendation | Should -Be 'defer-until-pr-delivery-or-bypass'
            $readiness.readyForEnforcement | Should -BeFalse
            $enforcementItem.status | Should -Be 'needs-live-validation'
            $enforcementItem.evidence | Should -Not -Match 'readable and show no'
            if ($Protection -eq 'unreadable') { $blockers | Should -Contain 'Branch protection evidence unavailable: HTTP 404: Branch not protected.' }
            if ($Rules -eq 'unreadable') { $blockers | Should -Contain 'Repository ruleset evidence unavailable: HTTP 502.' }
        }
        # The evidence names what was read, word for word: a negative match missed the old
        # "readable and currently show no" wording.
        $expectedEvidence = if ($Protection -eq 'requiring checks' -or $Rules -eq 'requiring checks') {
            'Required-check enforcement is already present.'
        } elseif ($Protection -ne 'unreadable' -and $Rules -ne 'unreadable') {
            "Branch protection and the default branch's rules are readable and show no required-check enforcement."
        } elseif ($Protection -ne 'unreadable') {
            "Branch protection requires no status checks, but the default branch's rules couldn't be read, so a ruleset may still require them."
        } elseif ($Rules -ne 'unreadable') {
            "No rule on the default branch requires status checks, but branch protection couldn't be read, so it may still require them."
        } else {
            'Live branch-protection and ruleset state must be validated before selecting an enforcement mechanism.'
        }
        $enforcementItem.evidence | Should -BeExactly $expectedEvidence
        # The two readiness answers agree in every case.
        $readiness.readyForEnforcement | Should -Be $readiness.prDeliveryTransition.readyForRequiredCheckEnforcement
        $rulesWarnings = @($settings.warnings | Where-Object { $_ -like 'Default branch rules unavailable*' })
        $rulesWarnings | Should -HaveCount $(if ($Rules -eq 'unreadable') { 1 } else { 0 })
    }

    It 'names an unread source as unread even with no reason given' {
        # The old blockers only said "unavailable" when a reason came with it, and otherwise
        # called the unread source one that doesn't require checks.
        Mock Test-RequiredCheckWorkflowCoverage { [ordered]@{ status = 'ready'; workflowCount = 1; candidateCheckCount = 1; warningCount = 0; warnings = @(); workflows = @() } }

        $readiness = Get-RequiredCheckReadiness -BranchProtectionAvailable:$false -RulesetsAvailable:$false `
            -RequiredStatusChecks $null -EnforceAdmins $null -ActionsPullRequestCreationAllowed $true -RulesetCount 0 `
            -RulesetRequiresStatusChecks $null -BranchProtectionUnavailableReason '' -RulesetsUnavailableReason ''

        @($readiness.blockers) | Should -Be @('Branch protection evidence unavailable.', 'Repository ruleset evidence unavailable.')
        $readiness.status | Should -Be 'needs-live-validation'
    }

    It 'is ready for enforcement only with nothing blocking and a ready checklist: <Case>' -ForEach @(
        @{ Case = 'checks required, checklist ready'; RequiredStatusChecks = $true; ChecklistReady = $true; Ready = $true }
        @{ Case = 'checks required, checklist not ready'; RequiredStatusChecks = $true; ChecklistReady = $false; Ready = $false }
        @{ Case = 'checks not required, checklist ready'; RequiredStatusChecks = $false; ChecklistReady = $true; Ready = $false }
    ) {
        # No real checklist can be ready yet (nothing records check-run proof or a merge
        # drill), so the matrix above never sees readiness true and a constant $false passed
        # it. A stand-in checklist pins how the two combine.
        Mock Test-RequiredCheckWorkflowCoverage { [ordered]@{ status = 'ready'; workflowCount = 1; candidateCheckCount = 1; warningCount = 0; warnings = @(); workflows = @() } }
        $script:ChecklistReady = $ChecklistReady
        Mock Get-PrDeliveryTransitionChecklist { [ordered]@{ status = $(if ($script:ChecklistReady) { 'ready' } else { 'needs-live-validation' }); readyForRequiredCheckEnforcement = $script:ChecklistReady; items = @() } }

        $readiness = Get-RequiredCheckReadiness -BranchProtectionAvailable:$true -RulesetsAvailable:$true `
            -RequiredStatusChecks $RequiredStatusChecks -EnforceAdmins $false -ActionsPullRequestCreationAllowed $true -RulesetCount 0 `
            -RulesetRequiresStatusChecks $false -BranchProtectionUnavailableReason '' -RulesetsUnavailableReason ''

        $readiness.readyForEnforcement | Should -Be $Ready
    }

    It 'reads left-out ruleset lists as unread, not as read and empty' {
        # -Rulesets and -BranchRules defaulted to @(), so a caller that left them out got
        # "readable, no rules" and a not-enabled verdict it never checked.
        $savedCandidates = $script:RequiredStatusCheckCandidates
        $script:RequiredStatusCheckCandidates = @([ordered]@{ name = 'validate'; workflow = '.github/workflows/validate.yml' })
        try {
            $result = Test-RepositoryCommunityBaseline `
                -Repository ([pscustomobject]@{ name = 'SysAdminDoc'; default_branch = 'main' }) `
                -BranchProtection ([pscustomobject]@{ enforce_admins = [pscustomobject]@{ enabled = $false } }) `
                -ActionsWorkflowPermissions ([pscustomobject]@{ default_workflow_permissions = 'read'; can_approve_pull_request_reviews = $true }) `
                -CommunityUnavailableReason 'not needed here' -LanguagesUnavailableReason 'not needed here' `
                -ScorecardAlertsUnavailableReason 'not needed here' -ScorecardScoreUnavailableReason 'not needed here'
        } finally {
            $script:RequiredStatusCheckCandidates = $savedCandidates
        }

        $settings = $result['repositorySettings']
        $settings.rulesets.available | Should -BeFalse
        $settings.requiredCheckReadiness.status | Should -Be 'needs-live-validation'
        @($settings.warnings | Where-Object { $_ -like 'Default branch rules unavailable*' }) | Should -HaveCount 1
    }

    It 'records neither generated-PR path while the decision is open, with the setting <Setting>' -ForEach @(
        @{ Setting = 'off'; Allowed = $false }
        @{ Setting = 'unreadable'; Allowed = $null }
    ) {
        # It used to record the local-only choice as made: manual validation selected and
        # hosted delivery rejected, beside decisionDocumentPath decision:pending.
        $decision = Get-GeneratedPrCredentialDecision -ActionsPullRequestCreationAllowed $Allowed -WorkflowsPresent $true
        # The report schema has to accept the value: find the decision object wherever it sits.
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json -AsHashtable
        $stack = [System.Collections.Generic.Stack[object]]::new()
        $stack.Push($schema)
        $decisionSchema = $null
        while ($stack.Count -gt 0 -and $null -eq $decisionSchema) {
            $node = $stack.Pop()
            if ($node -is [System.Collections.IDictionary]) {
                if ($node.Contains('generatedPrCredentialDecision')) { $decisionSchema = $node['generatedPrCredentialDecision'] }
                foreach ($value in $node.Values) { $stack.Push($value) }
            } elseif ($node -is [System.Collections.IList]) {
                foreach ($value in $node) { $stack.Push($value) }
            }
        }

        $decision.status | Should -Be 'needs-decision'
        $decision.selectedPath | Should -Be 'undecided'
        $decision.rejectedPath | Should -Be 'undecided'
        @($decisionSchema['properties']['selectedPath']['enum']) | Should -Contain 'undecided'
        @($decisionSchema['properties']['rejectedPath']['enum']) | Should -Contain 'undecided'
    }

    It 'describes a repository with workflows without the local-only posture' -ForEach @(
        @{ Setting = $false; Status = 'needs-decision' }
        @{ Setting = $true; Status = 'setting-enabled' }
    ) {
        $savedCandidates = $script:RequiredStatusCheckCandidates
        $script:RequiredStatusCheckCandidates = @([ordered]@{ name = 'validate'; workflow = '.github/workflows/validate.yml' })
        try {
            $result = Test-RepositoryCommunityBaseline `
                -Repository ([pscustomobject]@{ name = 'SysAdminDoc'; default_branch = 'main' }) `
                -BranchProtection ([pscustomobject]@{ enforce_admins = [pscustomobject]@{ enabled = $false } }) `
                -Rulesets @() -BranchRules @() `
                -ActionsWorkflowPermissions ([pscustomobject]@{ default_workflow_permissions = 'read'; can_approve_pull_request_reviews = $Setting }) `
                -CommunityUnavailableReason 'not needed here' -LanguagesUnavailableReason 'not needed here' `
                -ScorecardAlertsUnavailableReason 'not needed here' -ScorecardScoreUnavailableReason 'not needed here'
        } finally {
            $script:RequiredStatusCheckCandidates = $savedCandidates
        }

        $settings = $result['repositorySettings']
        ($settings | ConvertTo-Json -Depth 20) | Should -Not -Match 'local-validation-only|local-only validation|absent by policy|repository is local'
        $settings.actionsWorkflowPermissions.generatedPrCredentialDecision.status | Should -Be $Status
    }
}

Describe 'Repository settings read empty live lists as empty' {
    It 'reports no rulesets, no active rules and no open alerts as available and empty' {
        # gh api answers [] for each. ConvertFrom-Json turns that into no output, and an
        # if-expression assignment then passed $null on, which read as "unavailable".
        Mock Test-GitHubCliAuthenticated { $true }
        Mock Invoke-GhCli {
            $path = [string]$Arguments[1]
            $text = if ($path -eq 'repos/SysAdminDoc/SysAdminDoc') { '{"name":"SysAdminDoc","default_branch":"main"}' }
            elseif ($path -match '/rulesets$|/rules/branches/main$|/code-scanning/alerts') { '[]' }
            else { '{}' }
            [ordered]@{ output = $text; exitCode = 0; text = $text }
        }
        $savedOffline = $script:Offline
        $script:Offline = $false
        try {
            $result = Get-RepositoryCommunityBaseline
        } finally {
            $script:Offline = $savedOffline
        }

        $rulesets = $result['repositorySettings'].rulesets
        $rulesets.available | Should -BeTrue
        $rulesets.count | Should -Be 0
        $rulesets.requiresStatusChecks | Should -BeFalse
        $result['repositorySettings'].security.codeScanning.scorecardAlertPosture.available | Should -BeTrue
    }

    It 'reads a protection answer of <Case> as <Reading>' -ForEach @(
        @{ Case = '"Branch not protected" with 404'; Answer = 'gh: Branch not protected (HTTP 404)'; Reading = 'read, requiring nothing'; Available = $true; Status = 'not-enabled'; Reason = $null }
        @{ Case = 'any other 404'; Answer = 'gh: Not Found (HTTP 404)'; Reading = 'unread'; Available = $false; Status = 'needs-live-validation'; Reason = 'not found' }
        @{ Case = '"Branch not protected" with 403'; Answer = 'gh: Branch not protected (HTTP 403)'; Reading = 'unread'; Available = $false; Status = 'needs-live-validation'; Reason = 'Branch not protected (HTTP 403)' }
        @{ Case = '"Branch not protected" with 500'; Answer = 'gh: Branch not protected (HTTP 500)'; Reading = 'unread'; Available = $false; Status = 'needs-live-validation'; Reason = 'Branch not protected (HTTP 500)' }
        @{ Case = '"Branch not protected" with no status'; Answer = 'gh: Branch not protected'; Reading = 'unread'; Available = $false; Status = 'needs-live-validation'; Reason = 'Branch not protected' }
        # -ceq compared by culture, so the reading's own text with an invisible character in it matched.
        @{ Case = 'the reading''s text with a hidden character'; Answer = 'gh: branch not protected' + [char]0x200B; Reading = 'unread'; Available = $false; Status = 'needs-live-validation'; Reason = 'branch not protected' + [char]0x200B }
    ) {
        # Every 404 used to read as unread, so a repository without classic protection could
        # never show required checks as absent, only as unknown. Then the words alone were
        # enough, so a 403 or 500 carrying them read as protection turned off.
        $script:ProtectionAnswer = $Answer
        Mock Test-GitHubCliAuthenticated { $true }
        Mock Invoke-GhCli {
            $path = [string]$Arguments[1]
            if ($path -like '*/protection') {
                return [ordered]@{ output = $script:ProtectionAnswer; exitCode = 1; text = $script:ProtectionAnswer }
            }
            $text = if ($path -eq 'repos/SysAdminDoc/SysAdminDoc') { '{"name":"SysAdminDoc","default_branch":"main"}' }
            elseif ($path -match '/rulesets$|/rules/branches/|/code-scanning/alerts') { '[[]]' }
            else { '{}' }
            [ordered]@{ output = $text; exitCode = 0; text = $text }
        }
        $savedOffline = $script:Offline
        $savedCandidates = $script:RequiredStatusCheckCandidates
        $script:Offline = $false
        $script:RequiredStatusCheckCandidates = @([ordered]@{ name = 'validate'; workflow = '.github/workflows/validate.yml' })
        try {
            $result = Get-RepositoryCommunityBaseline
        } finally {
            $script:Offline = $savedOffline
            $script:RequiredStatusCheckCandidates = $savedCandidates
        }

        $settings = $result['repositorySettings']
        $settings.branchProtection.available | Should -Be $Available
        $settings.requiredCheckReadiness.status | Should -Be $Status
        if ($Available) {
            $settings.branchProtection.requiredStatusChecks | Should -BeFalse
            $settings.branchProtection.unavailableReason | Should -BeNullOrEmpty
        } else {
            # Ordinal: one reason ends in a zero-width space that -BeExactly would skip.
            $settings.branchProtection.unavailableReason | Should -BeOrdinal $Reason
        }
    }

    It 'reads protection and every page of rules for the default branch, <Case>' -ForEach @(
        @{ Case = 'master'; DefaultBranch = 'master'; Segment = 'master' }
        @{ Case = 'with a slash in it'; DefaultBranch = 'release/2.x'; Segment = 'release%2F2.x' }
        # Names git allows that the old pattern refused, so it read main's settings instead.
        @{ Case = 'with a plus in it'; DefaultBranch = 'main+dev'; Segment = 'main%2Bdev' }
        @{ Case = 'with an at sign in it'; DefaultBranch = 'dev@2'; Segment = 'dev%402' }
        @{ Case = 'falling back to main for a name no branch can have'; DefaultBranch = 'bad name'; Segment = 'main' }
        @{ Case = 'falling back to main for a path step'; DefaultBranch = '..'; Segment = 'main' }
        # Not a path step once escaped, so it's read by its own name; -in by culture took it for "..".
        @{ Case = 'with a hidden character after two dots'; DefaultBranch = '..' + [char]0x200B; Segment = '..%E2%80%8B' }
    ) {
        # Both endpoints named main whatever the default branch was, and only the first page
        # of rules and rulesets was read.
        $script:GhCalls = [System.Collections.Generic.List[string]]::new()
        $script:DefaultBranchAnswer = $DefaultBranch
        Mock Test-GitHubCliAuthenticated { $true }
        Mock Invoke-GhCli {
            $script:GhCalls.Add($Arguments -join ' ')
            $path = [string]$Arguments[1]
            $text = if ($path -eq 'repos/SysAdminDoc/SysAdminDoc') { '{"name":"SysAdminDoc","default_branch":' + (ConvertTo-Json $script:DefaultBranchAnswer) + '}' }
            elseif ($path -match '/rules/branches/') { '[[{"type":"deletion","ruleset_id":1}],[{"type":"required_status_checks","ruleset_id":2}]]' }
            elseif ($path -match '/rulesets$') { '[[{"id":1,"name":"one"}],[{"id":2,"name":"two"}]]' }
            elseif ($path -match '/code-scanning/alerts') { '[[]]' }
            else { '{}' }
            [ordered]@{ output = $text; exitCode = 0; text = $text }
        }
        $savedOffline = $script:Offline
        $script:Offline = $false
        try {
            $result = Get-RepositoryCommunityBaseline
        } finally {
            $script:Offline = $savedOffline
        }

        @($script:GhCalls).Contains("api repos/SysAdminDoc/SysAdminDoc/branches/$Segment/protection") | Should -BeTrue -Because ($script:GhCalls -join '; ')
        @($script:GhCalls).Contains("api repos/SysAdminDoc/SysAdminDoc/rules/branches/$Segment --paginate --slurp") | Should -BeTrue -Because ($script:GhCalls -join '; ')
        @($script:GhCalls).Contains('api repos/SysAdminDoc/SysAdminDoc/rulesets --paginate --slurp') | Should -BeTrue -Because ($script:GhCalls -join '; ')
        $rulesets = $result['repositorySettings'].rulesets
        $rulesets.count | Should -Be 2
        $rulesets.requiresStatusChecks | Should -BeTrue -Because 'the required-check rule is on the second page'
    }
}

Describe 'OpenSSF Scorecard runs locally' {
    It 'reports a missing binary instead of failing' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'scorecard' }

        $run = Invoke-ScorecardCli

        $run.ok | Should -BeFalse
        $run.error | Should -Match 'scorecard binary not found'
    }

    It 'hands Scorecard only the token-shaped line of gh auth token' {
        # A stand-in binary that echoes the token it was given; it runs with no window.
        $fake = Join-Path $TestDrive 'scorecard-echo.cmd'
        Set-Content -LiteralPath $fake -Encoding ascii -Value @('@echo off', 'echo {"token":"%GITHUB_AUTH_TOKEN%"}')
        Mock Get-Command { [pscustomobject]@{ Source = $fake } } -ParameterFilter { $Name -eq 'scorecard' }
        # Invoke-GhCli merges stderr into text, so gh's warnings arrive with the token.
        Mock Invoke-GhCli { [ordered]@{ output = @('warning: this token expires soon', 'gho_ABCDEFGHIJKLMNOPQRST1234'); exitCode = 0; text = "warning: this token expires soon`ngho_ABCDEFGHIJKLMNOPQRST1234" } }

        $run = Invoke-ScorecardCli

        $run.ok | Should -BeTrue
        $run.value.token | Should -BeExactly 'gho_ABCDEFGHIJKLMNOPQRST1234'
    }

    It 'leaves Scorecard unavailable when gh prints no token' {
        Mock Get-Command { [pscustomobject]@{ Source = (Join-Path $TestDrive 'never-started.exe') } } -ParameterFilter { $Name -eq 'scorecard' }
        Mock Invoke-GhCli { [ordered]@{ output = @('You are not logged into any GitHub hosts.'); exitCode = 0; text = 'You are not logged into any GitHub hosts.' } }

        $run = Invoke-ScorecardCli

        $run.ok | Should -BeFalse
        $run.error | Should -Match 'returned no GitHub token'
    }

    It 'takes tokens and account names out of the error it reports' {
        $fake = Join-Path $TestDrive 'scorecard-fail.cmd'
        Set-Content -LiteralPath $fake -Encoding ascii -Value @(
            '@echo off'
            'echo cannot read C:\Users\someone\AppData\scorecard.log with gho_ABCDEFGHIJKLMNOPQRST1234 1>&2'
            'exit /b 3'
        )
        Mock Get-Command { [pscustomobject]@{ Source = $fake } } -ParameterFilter { $Name -eq 'scorecard' }
        Mock Invoke-GhCli { [ordered]@{ output = @('gho_ZYXWVUTSRQPONMLKJIHG9876'); exitCode = 0; text = 'gho_ZYXWVUTSRQPONMLKJIHG9876' } }

        $run = Invoke-ScorecardCli

        $run.ok | Should -BeFalse
        $run.error | Should -Match '^scorecard exited 3: '
        $run.error | Should -Not -Match 'someone|gho_'
        $run.error | Should -Match ([regex]::Escape('C:\Users\<user>\AppData'))
        $run.error | Should -Match '<token>'
    }

    It 'takes the whole account name out of <Case>' -ForEach @(
        @{ Case = 'a path with a space in it'; Line = 'cannot read C:\Users\John Smith\AppData\scorecard.log'; Kept = 'C:\Users\<user>\AppData' }
        @{ Case = 'a Go-quoted path'; Line = 'open "C:\\Users\\someone\\scorecard.log": access denied'; Kept = 'C:\\Users\\<user>\\scorecard.log' }
        @{ Case = 'a UNC path'; Line = 'share \\fileserver\c$\Users\someone\cache failed'; Kept = '\Users\<user>\cache' }
        @{ Case = 'a forward-slash path'; Line = 'cannot read /home/someone/.cache/scorecard'; Kept = '/home/<user>/.cache' }
        @{ Case = 'a legacy 40-hex token'; Line = 'token 0123456789abcdef0123456789abcdef01234567 rejected'; Kept = 'token <token> rejected' }
    ) {
        $fake = Join-Path $TestDrive 'scorecard-fail-forms.cmd'
        Set-Content -LiteralPath $fake -Encoding ascii -Value @('@echo off', "echo $Line 1>&2", 'exit /b 3')
        Mock Get-Command { [pscustomobject]@{ Source = $fake } } -ParameterFilter { $Name -eq 'scorecard' }
        Mock Invoke-GhCli { [ordered]@{ output = @('gho_ZYXWVUTSRQPONMLKJIHG9876'); exitCode = 0; text = 'gho_ZYXWVUTSRQPONMLKJIHG9876' } }

        $run = Invoke-ScorecardCli

        $run.error | Should -Not -Match 'John|Smith|someone|0123456789abcdef'
        $run.error | Should -Match ([regex]::Escape($Kept))
    }

    It 'keeps the reason and nothing private in <Case>' -ForEach @(
        @{ Case = 'a Windows path that ends at the name'; Line = 'mkdir C:\Users\bob: Access is denied.'; Expected = 'mkdir C:\Users\<user>: Access is denied.'; Gone = 'bob' }
        @{ Case = 'a Linux home that ends at the name'; Line = 'stat /home/runner: no such file or directory'; Expected = 'stat /home/<user>: no such file or directory'; Gone = 'runner' }
        @{ Case = 'a name with an apostrophe'; Line = 'open C:\Users\Sean O''Brien\AppData\x: denied'; Expected = 'open C:\Users\<user>\AppData\x: denied'; Gone = 'Sean|Brien' }
        @{ Case = 'a path with its escapes doubled twice'; Line = 'open C:\\\\Users\\\\bob\\\\x failed'; Expected = 'open C:\\\\Users\\\\<user>\\\\x failed'; Gone = 'bob' }
        @{ Case = 'a JSON-escaped path'; Line = '{"path":"\/home\/bob\/x"} unreadable'; Expected = '{"path":"\/home\/<user>\/x"} unreadable'; Gone = 'bob' }
        @{ Case = 'a Windows path with forward slashes'; Line = 'open C:/Users/John Smith/x: denied'; Expected = 'open C:/Users/<user>/x: denied'; Gone = 'John|Smith' }
        @{ Case = 'an API URL with /users/ in it'; Line = 'GET https://api.github.com/users/octocat: 404 Not Found'; Expected = 'GET https://api.github.com/users/octocat: 404 Not Found'; Gone = '<user>' }
        @{ Case = 'a token after %20'; Line = 'GET https://x.test/?q=%20ghp_ABCDEFGHIJKLMNOPQRSTUV failed'; Expected = 'GET https://x.test/?q=%20<token> failed'; Gone = 'ghp_' }
        # A path segment before /Users/ or /home/ was taken for a URL, so these leaked.
        @{ Case = 'a WSL mount'; Line = 'open /mnt/c/Users/bob/x: permission denied'; Expected = 'open /mnt/c/Users/<user>/x: permission denied'; Gone = 'bob' }
        @{ Case = 'an MSYS path'; Line = 'open /c/Users/bob/x: permission denied'; Expected = 'open /c/Users/<user>/x: permission denied'; Gone = 'bob' }
        @{ Case = 'a macOS data volume'; Line = 'stat /System/Volumes/Data/Users/bob/x failed'; Expected = 'stat /System/Volumes/Data/Users/<user>/x failed'; Gone = 'bob' }
        @{ Case = 'an ostree home'; Line = 'stat /var/home/bob/x failed'; Expected = 'stat /var/home/<user>/x failed'; Gone = 'bob' }
        @{ Case = 'a share written with slashes'; Line = 'open //fileserver/Users/bob/x failed'; Expected = 'open //fileserver/Users/<user>/x failed'; Gone = 'bob' }
        # And a URL written with JSON's escaped slashes was redacted as if it were a path.
        @{ Case = 'a JSON-escaped URL'; Line = '{"url":"https:\/\/example.com\/home\/docs"} failed'; Expected = '{"url":"https:\/\/example.com\/home\/docs"} failed'; Gone = '<user>' }
        # Uppercase hex beside a legacy token (percent-encoding, a word) hid it.
        @{ Case = 'a token after %3D'; Line = 'GET https://x.test/?access_token%3D0123456789abcdef0123456789abcdef01234567 failed'; Expected = 'GET https://x.test/?access_token%3D<token> failed'; Gone = '0123456789abcdef' }
        @{ Case = 'a token followed by a capital'; Line = 'token 0123456789abcdef0123456789abcdef01234567Expired'; Expected = 'token <token>Expired'; Gone = '0123456789abcdef' }
        # Review of a899860: macOS paths ignore case, and a slash can arrive percent-encoded or
        # escaped twice, so these leaked; and URLs were only recognised in lower case.
        @{ Case = 'an upper-case /USERS/'; Line = 'stat /USERS/bob/x failed'; Expected = 'stat /USERS/<user>/x failed'; Gone = 'bob' }
        @{ Case = 'percent-encoded slashes'; Line = 'open %2FUsers%2Fbob%2Fx failed'; Expected = 'open %2FUsers%2F<user>%2Fx failed'; Gone = 'bob' }
        @{ Case = 'slashes escaped twice'; Line = '{"p":"\\/home\\/bob\\/x"} failed'; Expected = '{"p":"\\/home\\/<user>\\/x"} failed'; Gone = 'bob' }
        @{ Case = 'an upper-case URL scheme'; Line = 'GET HTTPS://example.com/Users/docs failed'; Expected = 'GET HTTPS://example.com/Users/docs failed'; Gone = '<user>' }
        @{ Case = 'a URL with a drive-like segment'; Line = 'GET https://x.test/a:/Users/docs failed'; Expected = 'GET https://x.test/a:/Users/docs failed'; Gone = '<user>' }
        # Review G4: an encoded byte inside the name ended it and the rest leaked, an encoded
        # backslash wasn't a separator, and an encoded colon hid a URL.
        @{ Case = 'an encoded space in the name'; Line = 'open %2FUsers%2Fjohn%20smith%2Fx failed'; Expected = 'open %2FUsers%2F<user>%2Fx failed'; Gone = 'john|smith' }
        @{ Case = 'encoded UTF-8 in the name'; Line = 'open %2Fhome%2Fj%C3%B6rg%2Fx failed'; Expected = 'open %2Fhome%2F<user>%2Fx failed'; Gone = '%C3|rg' }
        @{ Case = 'an encoded apostrophe in the name'; Line = 'open %2FUsers%2FO%27Brien%2Fx failed'; Expected = 'open %2FUsers%2F<user>%2Fx failed'; Gone = 'Brien' }
        @{ Case = 'encoded backslashes'; Line = 'open C:%5CUsers%5Cbob%5Cx failed'; Expected = 'open C:%5CUsers%5C<user>%5Cx failed'; Gone = 'bob' }
        @{ Case = 'a fully encoded URL'; Line = 'GET https%3A%2F%2Fexample.com%2FUsers%2Fdocs failed'; Expected = 'GET https%3A%2F%2Fexample.com%2FUsers%2Fdocs failed'; Gone = '<user>' }
        # Review G5: the name ran on through an encoded colon and took the reason with it, and
        # a %5C path with a %2F after Users wasn't redacted.
        @{ Case = 'an encoded colon after the name'; Line = 'open %2FUsers%2Fbob%3A%20denied'; Expected = 'open %2FUsers%2F<user>%3A%20denied'; Gone = 'bob' }
        @{ Case = 'an encoded quote after a Windows name'; Line = 'open C:%5CUsers%5Cbob%22 failed'; Expected = 'open C:%5CUsers%5C<user>%22 failed'; Gone = 'bob' }
        @{ Case = 'mixed encoded separators'; Line = 'open C:%5CUsers%2Fbob%5Cx failed'; Expected = 'open C:%5CUsers%2F<user>%5Cx failed'; Gone = 'bob' }
    ) {
        # The account redaction ran to the next separator or quote, which took the reason
        # after a name at the end of a path, and stopped at an apostrophe inside one.
        $fake = Join-Path $TestDrive 'scorecard-fail-reason.cmd'
        # cmd reads % as the start of a variable, so the script doubles it.
        Set-Content -LiteralPath $fake -Encoding ascii -Value @('@echo off', "echo $($Line.Replace('%', '%%')) 1>&2", 'exit /b 3')
        Mock Get-Command { [pscustomobject]@{ Source = $fake } } -ParameterFilter { $Name -eq 'scorecard' }
        Mock Invoke-GhCli { [ordered]@{ output = @('gho_ZYXWVUTSRQPONMLKJIHG9876'); exitCode = 0; text = 'gho_ZYXWVUTSRQPONMLKJIHG9876' } }

        $run = Invoke-ScorecardCli

        $Expected | Should -Not -Match $Gone -Because 'the expected line must itself hold nothing private'
        $run.error | Should -BeExactly ('scorecard exited 3: ' + $Expected)
    }

    It 'redacts a long run of <Case> in linear time' -ForEach @(
        @{ Case = 'backslashes'; Unit = '\' }
        @{ Case = 'doubled backslashes'; Unit = '\\' }
        @{ Case = 'encoded backslashes'; Unit = '%5C' }
    ) {
        # Review G5: the %5C separator took 50 KB of backslashes from 0.9 to 44 seconds, the
        # match scanning the rest of the run from every backslash in it.
        $text = ($Unit * [int](50KB / $Unit.Length)) + ' done'
        $fake = Join-Path $TestDrive 'scorecard-fail-run.cmd'
        [System.IO.File]::WriteAllText((Join-Path $TestDrive 'run.txt'), $text)
        Set-Content -LiteralPath $fake -Encoding ascii -Value @('@echo off', 'type "%~dp0run.txt" 1>&2', 'exit /b 3')
        Mock Get-Command { [pscustomobject]@{ Source = $fake } } -ParameterFilter { $Name -eq 'scorecard' }
        Mock Invoke-GhCli { [ordered]@{ output = @('gho_ZYXWVUTSRQPONMLKJIHG9876'); exitCode = 0; text = 'gho_ZYXWVUTSRQPONMLKJIHG9876' } }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $run = Invoke-ScorecardCli
        $elapsed.Stop()

        $run.error | Should -Match '^scorecard exited 3: '
        $elapsed.Elapsed.TotalSeconds | Should -BeLessThan 5 -Because 'the redaction has to stay linear in the length of the line'
    }

    It 'takes out a token the length cap would have cut, then caps the line' {
        # The cap ran first, and 23 of a legacy token's 40 characters got past the redaction.
        $fake = Join-Path $TestDrive 'scorecard-fail-long.cmd'
        $line = ('x' * 170) + ' token 0123456789abcdef0123456789abcdef01234567 rejected ' + ('y' * 200)
        Set-Content -LiteralPath $fake -Encoding ascii -Value @('@echo off', "echo $line 1>&2", 'exit /b 3')
        Mock Get-Command { [pscustomobject]@{ Source = $fake } } -ParameterFilter { $Name -eq 'scorecard' }
        Mock Invoke-GhCli { [ordered]@{ output = @('gho_ZYXWVUTSRQPONMLKJIHG9876'); exitCode = 0; text = 'gho_ZYXWVUTSRQPONMLKJIHG9876' } }

        $run = Invoke-ScorecardCli

        $run.error | Should -Not -Match '[0-9a-f]{8}'
        $run.error | Should -Match ' token <token> rejected y'
        $run.error.Length | Should -Be 240
    }

    It 'accepts a legacy 40-hex token from gh auth token' {
        $fake = Join-Path $TestDrive 'scorecard-echo-legacy.cmd'
        Set-Content -LiteralPath $fake -Encoding ascii -Value @('@echo off', 'echo {"token":"%GITHUB_AUTH_TOKEN%"}')
        Mock Get-Command { [pscustomobject]@{ Source = $fake } } -ParameterFilter { $Name -eq 'scorecard' }
        Mock Invoke-GhCli { [ordered]@{ output = @('0123456789abcdef0123456789abcdef01234567'); exitCode = 0; text = '0123456789abcdef0123456789abcdef01234567' } }

        $run = Invoke-ScorecardCli

        $run.ok | Should -BeTrue
        $run.value.token | Should -BeExactly '0123456789abcdef0123456789abcdef01234567'
    }

    It 'records the local run only when -RunScorecard asks for it' {
        $savedOffline = $script:Offline
        $savedRunScorecard = $script:RunScorecard
        $script:Offline = $false
        Mock Invoke-GhCli {
            if ($Arguments[0] -eq 'auth' -and $Arguments[1] -eq 'status') {
                return [ordered]@{ output = 'Logged in'; exitCode = 0; text = 'Logged in' }
            }
            [ordered]@{ output = 'not in this test'; exitCode = 1; text = 'not in this test' }
        }
        Mock Invoke-ScorecardCli {
            [ordered]@{
                ok = $true
                error = $null
                value = [pscustomobject]@{
                    date = '2026-09-23T08:00:00Z'
                    score = 6.1
                    repo = [pscustomobject]@{ name = 'github.com/SysAdminDoc/SysAdminDoc'; commit = '0123456789abcdef0123456789abcdef01234567' }
                    scorecard = [pscustomobject]@{ version = 'v5.2.1' }
                    checks = @([pscustomobject]@{ name = 'Pinned-Dependencies'; score = 8; reason = 'dependencies are pinned' })
                }
            }
        }
        try {
            $script:RunScorecard = $false
            $notRun = (Get-RepositoryCommunityBaseline)['repositorySettings'].security.scorecardScore
            $script:RunScorecard = $true
            $ran = (Get-RepositoryCommunityBaseline)['repositorySettings'].security.scorecardScore
        } finally {
            $script:Offline = $savedOffline
            $script:RunScorecard = $savedRunScorecard
        }

        $notRun.available | Should -BeFalse
        $notRun.unavailableReason | Should -Match '-RunScorecard'
        $ran.available | Should -BeTrue
        $ran.score | Should -Be 6.1
        $ran.checks[0].name | Should -Be 'Pinned-Dependencies'
        Should -Invoke Invoke-ScorecardCli -Times 1 -Exactly
    }

    It 'never reads the hosted Scorecard API' {
        $script:SyncProfileScript | Should -Not -Match 'api\.securityscorecards\.dev'
        $script:SyncProfileScript | Should -Not -Match 'ossf/scorecard-action@'
    }
}

Describe 'The suite runs the generator offline' {
    It 'reads the offline switch only through $script:Offline in the library' {
        $script:Offline | Should -BeTrue
        $plainReads = foreach ($path in @($script:SyncProfileSourcePaths | Where-Object { $_ -ne $script:SyncProfileScriptPath })) {
            Select-String -LiteralPath $path -Pattern '(?<![:\w])\$Offline\b' |
                ForEach-Object { '{0}:{1}' -f $_.Filename, $_.LineNumber }
        }

        @($plainReads) | Should -BeNullOrEmpty -Because 'a plain $Offline read in a dot-sourced library sees the parameter bound in the suite''s BeforeAll, not $script:Offline'
    }

    It 'checks the fixture catalog without calling GitHub' {
        Mock Invoke-GhCli { throw "live gh call: $($Arguments -join ' ')" }
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $readme = New-Readme -Catalog $catalog -Repos @()
        $projects = New-ProjectsExportJson -Catalog $catalog -Repos @()

        $result = Test-ProfileState -Catalog $catalog -Repos @() -ExpectedReadme $readme -ExpectedProjects $projects `
            -ExpectedAssets @{} -CurrentReadme $readme -CurrentProjects $projects -CurrentAssets @{} -SkipLinkValidation

        Should -Invoke Invoke-GhCli -Times 0 -Exactly
        # Online, each fixture row missing from the live repo list is looked up with gh and
        # reported as private; offline that lookup must not happen at all.
        [bool]$result.FailureConditions['privateViolations'] | Should -BeFalse
        $result.Report.repositorySettings.unavailableReason | Should -Be 'offline'
    }
}

Describe 'Invoke-GhCli adapter seam' {
    It 'returns structured output, exit code, and trimmed text from gh' {
        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
            $global:LASTEXITCODE = 0
            return "  $($Arguments -join ' ')  "
        }
        try {
            $result = Invoke-GhCli -Arguments @('api', 'user')
            $result.exitCode | Should -Be 0
            $result.text | Should -Be 'api user -H X-GitHub-Api-Version: 2022-11-28'
            $result.output | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
        }
    }

    It 'pins REST calls to an explicit GitHub API calendar version' {
        (Add-GitHubApiVersionArgument -Arguments @('api', 'repos/SysAdminDoc/SysAdminDoc')) -join ' ' |
            Should -Be 'api repos/SysAdminDoc/SysAdminDoc -H X-GitHub-Api-Version: 2022-11-28'
    }

    It 'leaves GraphQL and non-api gh commands unpinned' {
        (Add-GitHubApiVersionArgument -Arguments @('api', 'graphql', '-f', 'query=x')) -join ' ' |
            Should -Be 'api graphql -f query=x'
        (Add-GitHubApiVersionArgument -Arguments @('repo', 'list')) -join ' ' | Should -Be 'repo list'
        (Add-GitHubApiVersionArgument -Arguments @()) | Should -BeNullOrEmpty
    }

    It 'lets an explicit caller-supplied API version win' {
        (Add-GitHubApiVersionArgument -Arguments @('api', 'repos/x', '-H', 'X-GitHub-Api-Version: 2026-03-10')) -join ' ' |
            Should -Be 'api repos/x -H X-GitHub-Api-Version: 2026-03-10'
    }

    It 'surfaces a non-zero gh exit code without throwing' {
        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
            $global:LASTEXITCODE = 1
            return "HTTP 404: Not Found ($($Arguments -join ' '))"
        }
        try {
            $result = Invoke-GhCli -Arguments @('api', 'repos/Owner/Missing')
            $result.exitCode | Should -Be 1
            $result.text | Should -Match '404'
        } finally {
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
        }
    }

    It 'passes stdin through the mockable adapter path for gh api write calls' {
        function gh {
            process {
                $script:SeenGhInput = $_
                $global:LASTEXITCODE = 0
                return "stdin=$_ args=$($args -join ' ')"
            }
        }
        try {
            $payload = '{"names":["powershell"]}'
            $result = Invoke-GhCli -Arguments @('api', 'repos/Owner/Repo/topics', '-X', 'PUT', '--input', '-') -StandardInput $payload

            $script:SeenGhInput | Should -Be $payload
            $result.exitCode | Should -Be 0
            $result.text | Should -Match 'repos/Owner/Repo/topics'
        } finally {
            Remove-Variable -Name SeenGhInput -Scope Script -ErrorAction SilentlyContinue
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
        }
    }

    It 'bounds real gh.exe invocations so live metadata probes cannot hang forever' {
        $script:SyncProfileScript | Should -Match 'TimeoutSeconds = 45'
        $script:SyncProfileScript | Should -Match '\[string\]\$StandardInput'
        $script:SyncProfileScript | Should -Match 'WaitForExit\(\$TimeoutSeconds \* 1000\)'
        $script:SyncProfileScript | Should -Match 'gh timed out after \$TimeoutSeconds second\(s\)'
        $script:SyncProfileScript | Should -Match 'exitCode = 124'
    }

    It 'routes topic apply writes through the bounded gh adapter' {
        $script:SyncProfileScript | Should -Match 'Invoke-GhCli -Arguments @\("api", "repos/\$Owner/\$repoName/topics", "-X", "PUT", "--input", "-"\) -StandardInput \$topicPayload'
        $script:SyncProfileScript | Should -Not -Match '\$topicPayload \| gh api "repos/\$Owner/\$repoName/topics"'
    }

    It 'keeps profile-state repo-view checks behind the gh adapter seam' {
        $script:SyncProfileScript | Should -Match 'Invoke-GhCli -Arguments @\("repo", "view"'
        $script:SyncProfileScript | Should -Not -Match '\bgh repo view\b'
    }
}

Describe 'ConvertTo-Lookup' {
    It 'skips null and blank repo names under StrictMode' {
        $repos = @(
            (New-TestRepoMeta -Name 'GoodRepo'),
            [pscustomobject]@{ name = $null },
            [pscustomobject]@{ name = '   ' },
            $null,
            @{ name = 'OtherRepo' }
        )

        $lookup = ConvertTo-Lookup $repos

        @($lookup.Keys | Sort-Object) | Should -Be @('goodrepo', 'otherrepo')
        $lookup['goodrepo'].name | Should -Be 'GoodRepo'
        $lookup['otherrepo']['name'] | Should -Be 'OtherRepo'
    }
}

Describe 'MedicalPattern privacy regex is word-boundary anchored' {
    It 'does NOT match medical substrings inside unrelated words' {
        'overdose'      | Should -Not -Match $MedicalPattern
        'glucose'       | Should -Not -Match $MedicalPattern
        'keyboard-tool' | Should -Not -Match $MedicalPattern
    }
    It 'DOES match genuine medical-imaging terms' {
        'x-ray-room'     | Should -Match $MedicalPattern
        'my-dicom-tool'  | Should -Match $MedicalPattern
        'pacs'           | Should -Match $MedicalPattern
        'radiology dept' | Should -Match $MedicalPattern
    }
}

Describe 'Get-InstallSnippet' {
    It 'emits the short run.ps1 line for a PowerShell project' {
        $e = New-TestEntry -Repo 'WinTool' -Category 'powershell'
        $e.entrypoint = 'WinTool.ps1'; $e.installKind = 'powershell'; $e.branch = 'main'
        Get-InstallSnippet -Entry $e | Should -Be 'irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/run.ps1 | iex; Start-Tool WinTool'
    }
    It 'emits the same short line for a Python project on another branch' {
        # run.ps1 reads the branch and the runner from projects.json.
        $e = New-TestEntry -Repo 'PyTool' -Category 'python'
        $e.entrypoint = 'app.py'; $e.installKind = 'python'; $e.branch = 'master'
        $snippet = Get-InstallSnippet -Entry $e
        $snippet | Should -Be 'irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/run.ps1 | iex; Start-Tool PyTool'
        $snippet.Length | Should -BeLessThan 110
    }
    It 'returns null when the entry has no entrypoint' {
        $e = New-TestEntry -Repo 'NoEntry' -Category 'powershell'
        Get-InstallSnippet -Entry $e | Should -BeNullOrEmpty
    }
}

Describe 'Branch-tip provenance' {
    It 'records the advertised branch, current tip SHA, and fetched-at time for a fresh response' {
        $sha = 'a' * 40
        $repo = New-TestRepoMeta -Name 'WinTool'
        $fetch = [ordered]@{
            succeeded = $true
            fetchedAt = '2026-08-12T12:00:00Z'
            error = $null
            rows = @([ordered]@{ name = 'WinTool'; branch = 'main'; sha = $sha })
        }

        $updated = @(Set-BranchTipMetadata -Repos @($repo) -FetchResult $fetch)

        $updated[0].defaultBranchRef.name | Should -Be 'main'
        $updated[0].branchTipSha | Should -Be $sha
        $updated[0].branchTipFetchedAt | Should -Be '2026-08-12T12:00:00Z'
        $updated[0].branchTipStatus | Should -Be 'fresh'
        $updated[0].branchTipWarning | Should -BeNullOrEmpty
    }

    It 'marks previously fetched evidence stale when refresh is unreachable' {
        $sha = 'b' * 40
        $repo = New-TestRepoMeta -Name 'WinTool' -BranchTipSha $sha -BranchTipFetchedAt '2026-08-10T12:00:00Z'
        $fetch = [ordered]@{
            succeeded = $false
            fetchedAt = $null
            error = 'HTTP 503 branch ref unavailable'
            rows = @()
        }

        $updated = @(Set-BranchTipMetadata -Repos @($repo) -FetchResult $fetch -StaleAfterHours 24)

        $updated[0].branchTipSha | Should -Be $sha
        $updated[0].branchTipStatus | Should -Be 'stale'
        $updated[0].branchTipWarning | Should -Match 'unreachable'
    }

    It 'reports branch-tip evidence only for branch-backed install actions' {
        $entry = New-TestEntry -Repo 'WinTool' -Category 'powershell'
        $entry.entrypoint = 'WinTool.ps1'
        $entry.installKind = 'powershell'
        $sha = 'c' * 40
        $meta = New-TestRepoMeta -Name 'WinTool' -BranchTipSha $sha -BranchTipFetchedAt '2026-08-12T12:00:00Z'
        $result = Test-BranchTipProvenance -Entries @($entry) -RepoLookup (ConvertTo-Lookup @($meta)) -Now ([datetimeoffset]'2026-08-12T12:30:00Z')

        $result.status | Should -Be 'ok'
        $result.checkedInstallActionCount | Should -Be 1
        $result.freshCount | Should -Be 1
        $result.warningCount | Should -Be 0
        $result.rows[0].branch | Should -Be 'main'
        $result.rows[0].branchTipSha | Should -Be $sha
    }
}

Describe 'URL and metadata helpers' {
    It 'Get-RepoUrl resolves aliasOf to the canonical repo' {
        $e = New-TestEntry -Repo 'OldName' -Category 'misc'
        $e.aliasOf = 'NewName'
        Get-RepoUrl -Entry $e | Should -Be 'https://github.com/SysAdminDoc/NewName'
    }
    It 'Get-Branch prefers the explicit catalog branch, else defaults to main' {
        $e = New-TestEntry -Repo 'B' -Category 'misc'; $e.branch = 'develop'
        Get-Branch -Entry $e -Meta $null | Should -Be 'develop'
        $e2 = New-TestEntry -Repo 'B2' -Category 'misc'
        Get-Branch -Entry $e2 -Meta $null | Should -Be 'main'
    }
    It 'Get-Description prefers the override' {
        $e = New-TestEntry -Repo 'D' -Category 'misc' -Description 'override text'
        Get-Description -Entry $e -Meta $null | Should -Be 'override text'
    }
    It 'ConvertTo-RawGitHubUrl percent-encodes path segments' {
        $u = ConvertTo-RawGitHubUrl -Repo 'R' -Branch 'main' -Path 'My Script.user.js'
        $u | Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/R/main/My%20Script.user.js'
    }
    It 'Get-DownloadLabel maps known kinds' {
        $apk = New-TestEntry -Repo 'A' -Category 'android'; $apk.downloadKind = 'apk'
        Get-DownloadLabel -Entry $apk -Category 'android' | Should -Be 'APK'
    }

    It 'keeps release action icon and label from wrapping apart' {
        $apk = New-TestEntry -Repo 'A' -Category 'android'; $apk.downloadKind = 'apk'
        $meta = New-TestRepoMeta -Name 'A' -WithRelease -AssetNames @('A.apk')

        Get-ActionLink -Entry $apk -Meta $meta -Category 'android' |
            Should -BeOrdinal '<a href="https://github.com/SysAdminDoc/A/releases/latest" aria-label="Download A (APK)"><kbd>&#11015;&nbsp;APK</kbd></a>'
    }
}

Describe 'Test-HttpUrl result shape (no network calls)' {
    It 'returns a record carrying the fatal flag' {
        # Unresolvable host -> transient failure (never fatal); does not require a live server.
        $r = Test-HttpUrl -Url 'https://nonexistent.invalid.example/nope' -TimeoutSec 2 -Retries 1
        $r.Keys | Should -Contain 'fatal'
        $r.ok | Should -BeFalse
        $r.fatal | Should -BeFalse
    }

    It 'uses the shared Test-HttpUrl implementation inside the parallel link probe' {
        $script:SyncProfileScript | Should -Not -Match 'function Test-ParallelHttpUrl'
        $script:SyncProfileScript | Should -Match '\$\{function:Invoke-SafeOutboundHttpRequest\}\.ToString\(\)'
        $script:SyncProfileScript | Should -Match '\$\{function:Invoke-SafeOutboundHttpRequest\} = \$using:invokeSafeOutboundHttpRequestDefinition'
        $script:SyncProfileScript | Should -Match '\$\{function:Test-HttpUrl\}\.ToString\(\)'
        $script:SyncProfileScript | Should -Match '\$\{function:Test-HttpUrl\} = \$using:testHttpUrlDefinition'
    }

    It 'keeps link probes bounded to response headers' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:SyncProfileScript, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $functionBodies = @{}
        foreach ($functionAst in @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -in @('Test-HttpUrl', 'Invoke-SafeOutboundHttpHop', 'Invoke-SafeOutboundHttpRequest')
                }, $true))) {
            $functionBodies[$functionAst.Name] = $functionAst.Extent.Text
        }

        $functionBodies['Test-HttpUrl'] | Should -Match 'Invoke-SafeOutboundHttpRequest'
        $functionBodies['Invoke-SafeOutboundHttpHop'] | Should -Match 'ResponseHeadersRead'
        $functionBodies['Invoke-SafeOutboundHttpHop'] | Should -Match 'HttpClient'
        ($functionBodies.Values -join "`n") | Should -Not -Match 'Invoke-WebRequest'
    }
}

Describe 'Safe outbound destination policy' {
    BeforeEach {
        $script:SafeOutboundSendCount = 0
        $script:SafeOutboundSent = [System.Collections.Generic.List[object]]::new()
    }

    It 'rejects credentials, non-HTTPS schemes, localhost, and special-purpose IPv4 literals before sending' {
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSendCount++
            return [ordered]@{ statusCode = 200; location = $null; error = $null; bytes = @(); text = $null; bytesRead = 0 }
        }
        $blockedUrls = @(
            'http://example.com/',
            'https://user:password@example.com/',
            'https://localhost/',
            'https://service.localhost/',
            'https://0.0.0.0/',
            'https://10.1.2.3/',
            'https://100.64.0.1/',
            'https://127.0.0.1/',
            'https://169.254.169.254/latest/meta-data/',
            'https://172.16.0.1/',
            'https://192.168.1.1/',
            'https://224.0.0.1/',
            'https://255.255.255.255/'
        )

        foreach ($url in $blockedUrls) {
            $result = Invoke-SafeOutboundHttpRequest -Url $url -SendRequestScript $sender
            $result.ok | Should -BeFalse -Because $url
            $result.policyBlocked | Should -BeTrue -Because $url
        }
        $script:SafeOutboundSendCount | Should -Be 0
    }

    It 'rejects mixed and encoded loopback forms before sending' {
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSendCount++
            return [ordered]@{ statusCode = 200; location = $null; error = $null; bytes = @(); text = $null; bytesRead = 0 }
        }
        foreach ($url in @(
                'https://2130706433/',
                'https://127.1/',
                'https://0177.0.0.1/',
                'https://0x7f000001/',
                'https://%31%32%37.0.0.1/')) {
            $result = Invoke-SafeOutboundHttpRequest -Url $url -SendRequestScript $sender
            $result.ok | Should -BeFalse -Because $url
            $result.policyBlocked | Should -BeTrue -Because $url
        }
        $script:SafeOutboundSendCount | Should -Be 0
    }

    It 'rejects loopback, link-local, unique-local, unspecified, and mapped IPv6 literals before sending' {
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSendCount++
            return [ordered]@{ statusCode = 200; location = $null; error = $null; bytes = @(); text = $null; bytesRead = 0 }
        }
        foreach ($url in @(
                'https://[::]/',
                'https://[::1]/',
                'https://[fe80::1]/',
                'https://[fc00::1]/',
                'https://[ff02::1]/',
                'https://[::ffff:127.0.0.1]/',
                'https://[2001:db8::1]/')) {
            $result = Invoke-SafeOutboundHttpRequest -Url $url -SendRequestScript $sender
            $result.ok | Should -BeFalse -Because $url
            $result.policyBlocked | Should -BeTrue -Because $url
        }
        $script:SafeOutboundSendCount | Should -Be 0
    }

    It 'rejects a hostname when any A or AAAA result is non-public' {
        $resolver = { param($HostName) @('93.184.216.34', '10.20.30.40', '2606:4700:4700::1111') }
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSendCount++
            return [ordered]@{ statusCode = 200; location = $null; error = $null; bytes = @(); text = $null; bytesRead = 0 }
        }

        $result = Invoke-SafeOutboundHttpRequest `
            -Url 'https://mixed.example/resource' `
            -ResolveHostScript $resolver `
            -SendRequestScript $sender

        $result.ok | Should -BeFalse
        $result.policyBlocked | Should -BeTrue
        $result.error | Should -Match 'non-public address'
        $script:SafeOutboundSendCount | Should -Be 0
    }

    It 'tells a non-public DNS answer apart from a URL that names a private address' {
        # A DNS filter answers a blocked name with a sinkhole address; a URL that names a
        # private address itself is the request pointing inward.
        $resolver = { param($HostName) @('0.0.0.0') }
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSendCount++
            return [ordered]@{ statusCode = 200; location = $null; error = $null; bytes = @(); text = $null; bytesRead = 0 }
        }

        $sinkhole = Invoke-SafeOutboundHttpRequest -Url 'https://filtered.example/asset.zip' -ResolveHostScript $resolver -SendRequestScript $sender
        $literal = Invoke-SafeOutboundHttpRequest -Url 'https://10.0.0.1/asset.zip' -SendRequestScript $sender

        $sinkhole.policyBlocked | Should -BeTrue
        $sinkhole.dnsAnswerBlocked | Should -BeTrue
        $literal.policyBlocked | Should -BeTrue
        $literal.dnsAnswerBlocked | Should -BeFalse
        $script:SafeOutboundSendCount | Should -Be 0
    }

    It 'says when a body was bigger than the byte cap' {
        $resolver = { param($HostName) @('93.184.216.34') }
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            return [ordered]@{ statusCode = 200; location = $null; error = 'response exceeds the configured byte cap'; byteCapExceeded = $true; bytes = @(); text = $null; bytesRead = 4096 }
        }

        $result = Invoke-SafeOutboundHttpRequest -Url 'https://public.example/big' -ReadBody -MaxBytes 1024 -ResolveHostScript $resolver -SendRequestScript $sender

        $result.ok | Should -BeFalse
        $result.byteCapExceeded | Should -BeTrue
        $result.policyBlocked | Should -BeFalse
    }

    It 'blocks a public redirect to a private DNS answer before the protected request' {
        $resolver = {
            param($HostName)
            if ($HostName -eq 'public.example') { return @('93.184.216.34') }
            return @('169.254.169.254')
        }
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSendCount++
            return [ordered]@{
                statusCode = 302
                location = 'https://metadata.example/latest/'
                error = $null
                bytes = @()
                text = $null
                bytesRead = 0
            }
        }

        $result = Invoke-SafeOutboundHttpRequest `
            -Url 'https://public.example/start' `
            -ResolveHostScript $resolver `
            -SendRequestScript $sender

        $result.ok | Should -BeFalse
        $result.policyBlocked | Should -BeTrue
        $result.finalUrl | Should -Be 'https://metadata.example/latest/'
        $script:SafeOutboundSendCount | Should -Be 1
    }

    It 'passes public HTTPS and pins the request to every validated address' {
        $resolver = { param($HostName) @('93.184.216.34', '2606:4700:4700::1111') }
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSent.Add([ordered]@{ uri = $Uri; addresses = @($Addresses | ForEach-Object { $_.ToString() }) })
            return [ordered]@{ statusCode = 204; location = $null; error = $null; bytes = @(); text = $null; bytesRead = 0 }
        }

        $result = Invoke-SafeOutboundHttpRequest `
            -Url 'https://public.example/resource' `
            -ResolveHostScript $resolver `
            -SendRequestScript $sender

        $result.ok | Should -BeTrue
        $result.statusCode | Should -Be 204
        $script:SafeOutboundSent | Should -HaveCount 1
        $script:SafeOutboundSent[0].uri | Should -Be 'https://public.example/resource'
        @($script:SafeOutboundSent[0].addresses) | Should -Be @('93.184.216.34', '2606:4700:4700::1111')
    }

    It 'allows a modeled GitHub release redirect when every hop resolves publicly' {
        $resolver = { param($HostName) @('140.82.112.3') }
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSent.Add($Uri)
            if ($Uri -like 'https://github.com/*') {
                return [ordered]@{
                    statusCode = 302
                    location = 'https://objects.githubusercontent.com/github-production-release-asset/file.zip'
                    error = $null
                    bytes = @()
                    text = $null
                    bytesRead = 0
                }
            }
            return [ordered]@{ statusCode = 200; location = $null; error = $null; bytes = @(1, 2); text = $null; bytesRead = 2 }
        }

        $result = Invoke-SafeOutboundHttpRequest `
            -Url 'https://github.com/SysAdminDoc/Tool/releases/download/v1.0.0/file.zip' `
            -ResolveHostScript $resolver `
            -SendRequestScript $sender

        $result.ok | Should -BeTrue
        $result.redirectCount | Should -Be 1
        $result.finalUrl | Should -Be 'https://objects.githubusercontent.com/github-production-release-asset/file.zip'
        $script:SafeOutboundSent | Should -HaveCount 2
    }

    It 'stops after five redirects without sending a seventh request' {
        $resolver = { param($HostName) @('93.184.216.34') }
        $sender = {
            param($Uri, $Method, $Addresses, $TimeoutSec, $MaxBytes, $ReadBody, $UserAgent, $Accept, $Headers)
            $script:SafeOutboundSendCount++
            return [ordered]@{
                statusCode = 302
                location = "/hop/$script:SafeOutboundSendCount"
                error = $null
                bytes = @()
                text = $null
                bytesRead = 0
            }
        }

        $result = Invoke-SafeOutboundHttpRequest `
            -Url 'https://public.example/start' `
            -MaxRedirects 5 `
            -ResolveHostScript $resolver `
            -SendRequestScript $sender

        $result.ok | Should -BeFalse
        $result.policyBlocked | Should -BeTrue
        $result.error | Should -Match 'redirect limit of 5 exceeded'
        $script:SafeOutboundSendCount | Should -Be 6
    }

    It 'pins sockets and routes every public raw HTTP path through the shared policy' {
        $script:SyncProfileScript | Should -Match 'ConnectCallback'
        $script:SyncProfileScript | Should -Match 'UseProxy = false'
        $script:SyncProfileScript | Should -Match 'AllowAutoRedirect = false'
        $script:SyncProfileScript | Should -Not -Match 'Invoke-WebRequest'
        $script:SyncProfileScript | Should -Not -Match 'Invoke-RestMethod'

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:SyncProfileScript, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $functionBodies = @{}
        foreach ($functionAst in @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true))) {
            $functionBodies[$functionAst.Name] = $functionAst.Extent.Text
        }

        foreach ($functionName in @(
                'Test-HttpUrl',
                'Get-ReleaseArtifactDownload',
                'Get-PortfolioHttpDocument',
                'Get-UserscriptContent')) {
            $functionBodies[$functionName] | Should -Match 'Invoke-SafeOutboundHttpRequest' -Because $functionName
        }
    }
}

Describe 'Catalog shape validation' {
    It 'passes the fixture and committed catalog' {
        foreach ($path in @('tests/fixtures/catalog.json', 'data/profile-catalog.json')) {
            $cat = Get-Catalog -Path (Join-Path $script:RepoRoot $path)
            $result = Test-CatalogShape -Catalog $cat

            $result.passed | Should -BeTrue
            $result.issueCount | Should -Be 0
            @($result.issues) | Should -HaveCount 0
        }
    }

    It 'flags duplicate repo rows case-insensitively' {
        $first = New-TestEntry -Repo 'DupTool' -Category 'powershell'
        $second = New-TestEntry -Repo 'duptool' -Category 'python'

        $result = Test-CatalogShape -Catalog @{ entries = @($first, $second) }

        $result.passed | Should -BeFalse
        ($result.issues | Where-Object { $_.field -eq 'repo' }).reason | Should -Match 'duplicate repo'
    }

    It 'flags a missing repo value' {
        $entry = New-TestEntry -Repo '' -Category 'powershell'

        $result = Test-CatalogShape -Catalog @{ entries = @($entry) }

        $result.passed | Should -BeFalse
        ($result.issues | Where-Object { $_.field -eq 'repo' }).reason | Should -Be 'repo is required'
    }

    It 'flags unknown category and downloadKind values' {
        $entry = New-TestEntry -Repo 'BadShape' -Category 'unknown'
        $entry.downloadKind = 'installer'

        $result = Test-CatalogShape -Catalog @{ entries = @($entry) }

        $result.passed | Should -BeFalse
        ($result.issues | Where-Object { $_.field -eq 'category' }).reason | Should -Be 'unknown category'
        ($result.issues | Where-Object { $_.field -eq 'downloadKind' }).reason | Should -Be 'unknown downloadKind'
    }

    It 'flags an unsafe repo name that could break out of a gh api path' {
        $entry = New-TestEntry -Repo '../secrets' -Category 'powershell'

        $result = Test-CatalogShape -Catalog @{ entries = @($entry) }

        $result.passed | Should -BeFalse
        ($result.issues | Where-Object { $_.field -eq 'repo' }).reason | Should -Match '\^\[A-Za-z0-9'
    }

    It 'flags an unsafe aliasOf name' {
        $entry = New-TestEntry -Repo 'CleanRepo' -Category 'powershell'
        $entry.aliasOf = 'evil/../../path'

        $result = Test-CatalogShape -Catalog @{ entries = @($entry) }

        $result.passed | Should -BeFalse
        ($result.issues | Where-Object { $_.field -eq 'aliasOf' }).reason | Should -Match '\^\[A-Za-z0-9'
    }
}

Describe 'Test-SafeGitHubName repository name guard' {
    It 'accepts valid GitHub repository names' {
        foreach ($name in @('SysAdminDoc', 'win11-nvme-driver-patcher', 'IMDb_Enhanced', 'a.b-c_d')) {
            Test-SafeGitHubName -Name $name | Should -BeTrue
        }
    }

    It 'rejects traversal, slashes, whitespace, and empty values' {
        foreach ($name in @('../etc', 'owner/repo', 'has space', 'semi;colon', '', '  ', 'quote"mark')) {
            Test-SafeGitHubName -Name $name | Should -BeFalse
        }
    }
}

Describe 'Test-AllowedUserscriptUrl SSRF guard' {
    It 'allows HTTPS GitHub raw-content hosts' {
        foreach ($url in @(
                'https://raw.githubusercontent.com/SysAdminDoc/UserScript-Finder/main/finder.user.js',
                'https://gist.githubusercontent.com/SysAdminDoc/abc/raw/x.user.js',
                'https://github.com/SysAdminDoc/repo/raw/main/x.user.js')) {
            Test-AllowedUserscriptUrl -Url $url | Should -BeTrue
        }
    }

    It 'blocks non-HTTPS schemes, disallowed hosts, and internal targets' {
        foreach ($url in @(
                'http://raw.githubusercontent.com/x/y/main/z.user.js',
                'https://evil.example.com/payload.user.js',
                'https://github.com/SysAdminDoc/repo/blob/main/x.user.js',
                'https://github.com/SysAdminDoc/repo/issues',
                'https://169.254.169.254/latest/meta-data',
                'file:///etc/passwd',
                'https://localhost:8080/x.user.js',
                '')) {
            Test-AllowedUserscriptUrl -Url $url | Should -BeFalse
        }
    }

    It 'returns a blocked fetch result without making a request for a disallowed URL' {
        $result = Get-UserscriptContent -Url 'https://evil.example.com/x.user.js'
        $result.succeeded | Should -BeFalse
        $result.error | Should -Match 'Blocked userscript fetch'
    }

    It 'blocks userscript metadata URL probes outside allowed raw-content hosts' {
        $result = Get-UserscriptUrlProbe -Url 'https://169.254.169.254/latest/meta-data'

        $result.checked | Should -BeTrue
        $result.ok | Should -BeFalse
        $result.statusCode | Should -BeNullOrEmpty
        $result.error | Should -Match 'Blocked userscript metadata URL probe'
        $result.fatal | Should -BeFalse
    }
}

Describe 'Repository settings and community-health baseline' {
    BeforeAll {
        $script:LocalCommunityFilesOk = @(
            [ordered]@{ path = 'README.md'; required = $true; exists = $true },
            [ordered]@{ path = 'LICENSE'; required = $true; exists = $true },
            [ordered]@{ path = 'SECURITY.md'; required = $true; exists = $true },
            [ordered]@{ path = '.github/CODEOWNERS'; required = $true; exists = $true },
            [ordered]@{ path = '.github/pull_request_template.md'; required = $true; exists = $true },
            [ordered]@{ path = '.github/ISSUE_TEMPLATE/broken-link.yml'; required = $true; exists = $true },
            [ordered]@{ path = '.github/ISSUE_TEMPLATE/profile-correction.yml'; required = $true; exists = $true },
            [ordered]@{ path = '.github/ISSUE_TEMPLATE/local-validation.yml'; required = $true; exists = $true },
            [ordered]@{ path = '.github/ISSUE_TEMPLATE/config.yml'; required = $true; exists = $true }
        )
    }

    It 'summarizes live-shaped settings without leaking alert details' {
        $repository = [pscustomobject]@{
            visibility = 'public'
            has_issues = $true
            has_discussions = $true
            has_projects = $true
            has_wiki = $true
            allow_forking = $true
            delete_branch_on_merge = $false
            web_commit_signoff_required = $false
            security_and_analysis = [pscustomobject]@{
                secret_scanning = [pscustomobject]@{ status = 'enabled' }
                secret_scanning_push_protection = [pscustomobject]@{ status = 'enabled' }
                secret_scanning_non_provider_patterns = [pscustomobject]@{ status = 'disabled' }
                secret_scanning_validity_checks = [pscustomobject]@{ status = 'disabled' }
                dependabot_security_updates = [pscustomobject]@{ status = 'enabled' }
            }
        }
        $community = [pscustomobject]@{
            health_percentage = 71
            files = [pscustomobject]@{
                readme = [pscustomobject]@{}
                license = [pscustomobject]@{}
                issue_template = $null
                pull_request_template = [pscustomobject]@{}
                contributing = $null
                code_of_conduct = $null
            }
        }
        $branchProtection = [pscustomobject]@{
            required_status_checks = $null
            required_pull_request_reviews = $null
            required_conversation_resolution = [pscustomobject]@{ enabled = $true }
            enforce_admins = [pscustomobject]@{ enabled = $true }
            allow_force_pushes = [pscustomobject]@{ enabled = $false }
            allow_deletions = [pscustomobject]@{ enabled = $false }
        }
        $languages = [pscustomobject]@{ PowerShell = 210925 }
        $actionsWorkflowPermissions = [pscustomobject]@{
            default_workflow_permissions = 'read'
            can_approve_pull_request_reviews = $false
        }
        $codeScanningEvidence = [ordered]@{
            codeqlWorkflowPresent = $false
            sarifUploadWorkflowPresent = $false
            psScriptAnalyzerWorkflowPresent = $false
            actionlintWorkflowPresent = $false
            zizmorWorkflowPresent = $false
            localValidationScriptPresent = $true
            psScriptAnalyzerLocalPresent = $true
            pesterLocalPresent = $true
            markdownlintLocalPresent = $true
            zizmorLocalConfigPresent = $true
        }
        $scorecardAlerts = @(
            New-TestScorecardAlert -Number 1 -RuleId 'CodeReviewID' -Description 'Code-Review' -SecuritySeverity 'high'
            New-TestScorecardAlert -Number 2 -RuleId 'SecurityPolicyID' -Description 'Security-Policy'
            New-TestScorecardAlert -Number 3 -RuleId 'SASTID' -Description 'SAST'
            New-TestScorecardAlert -Number 4 -RuleId 'CIIBestPracticesID' -Description 'CII-Best-Practices' -SecuritySeverity 'low'
            New-TestScorecardAlert -Number 5 -RuleId 'FuzzingID' -Description 'Fuzzing'
            New-TestScorecardAlert -Number 6 -RuleId 'BranchProtectionID' -Description 'Branch-Protection' -SecuritySeverity 'high'
        )
        $scorecardScoreResult = [pscustomobject]@{
            date = '2026-06-11T10:08:14Z'
            score = 7.4
            repo = [pscustomobject]@{
                name = 'github.com/SysAdminDoc/SysAdminDoc'
                commit = '0123456789abcdef0123456789abcdef01234567'
            }
            scorecard = [pscustomobject]@{ version = 'v5.2.1' }
            checks = @(
                [pscustomobject]@{ name = 'Security-Policy'; score = 10; reason = 'security policy file detected' }
                [pscustomobject]@{ name = 'Code-Review'; score = 0; reason = 'Found 0/30 approved changesets' }
                [pscustomobject]@{ name = 'Fuzzing'; score = -1; reason = $null }
            )
        }

        $result = Test-RepositoryCommunityBaseline -Repository $repository -CommunityProfile $community -BranchProtection $branchProtection -Rulesets @() -ActionsWorkflowPermissions $actionsWorkflowPermissions -Languages $languages -LocalFiles $script:LocalCommunityFilesOk -CodeScanningLocalEvidence $codeScanningEvidence -ScorecardAlerts $scorecardAlerts -ScorecardScoreResult $scorecardScoreResult
        $repoSettings = $result['repositorySettings']
        $communityHealth = $result['communityHealth']
        $scorecardPosture = $repoSettings.security.codeScanning.scorecardAlertPosture
        $scorecardScore = $repoSettings.security.scorecardScore

        $repoSettings.available | Should -BeTrue
        $repoSettings.security.secretScanning | Should -Be 'enabled'
        $repoSettings.security.secretScanningPushProtection | Should -Be 'enabled'
        $repoSettings.security.dependabotSecurityUpdates | Should -Be 'enabled'
        $repoSettings.security.dependabotSecurityPosture.status | Should -Be 'enabled'
        $repoSettings.security.dependabotSecurityPosture.recommendation | Should -Be 'disable-dependabot-per-repository-policy'
        $repoSettings.security.dependabotSecurityPosture.securityUpdatesEnabled | Should -BeTrue
        $repoSettings.security.dependabotSecurityPosture.localConfigPresent | Should -BeFalse
        $repoSettings.security.dependabotSecurityPosture.localConfigPath | Should -Be '.github/dependabot.yml'
        $repoSettings.security.dependabotSecurityPosture.localConfigEcosystems | Should -BeNullOrEmpty
        $repoSettings.security.dependabotSecurityPosture.documentationPath | Should -Be 'decision:dependabot-security-posture'
        $scorecardScore.available | Should -BeTrue
        $scorecardScore.score | Should -Be 7.4
        $scorecardScore.maxScore | Should -Be 10.0
        $scorecardScore.provider | Should -Be 'scorecard-cli'
        $scorecardScore.command | Should -Be 'scorecard --repo=github.com/SysAdminDoc/SysAdminDoc --format=json'
        $scorecardScore.scorecardVersion | Should -Be 'v5.2.1'
        @($scorecardScore.checks | ForEach-Object { $_.name }) | Should -Be @('Code-Review', 'Fuzzing', 'Security-Policy')
        @($scorecardScore.checks | Where-Object { $_.name -eq 'Fuzzing' })[0].score | Should -Be -1
        @($scorecardScore.checks | Where-Object { $_.name -eq 'Fuzzing' })[0].reason | Should -BeNullOrEmpty
        $scorecardScore.date | Should -Be '2026-06-11T10:08:14Z'
        $scorecardScore.analyzedRepo | Should -Be 'github.com/SysAdminDoc/SysAdminDoc'
        $scorecardScore.analyzedCommit | Should -Be '0123456789abcdef0123456789abcdef01234567'
        $scorecardScore.unavailableReason | Should -BeNullOrEmpty
        $repoSettings.security.codeScanning.status | Should -Be 'not-applicable'
        $repoSettings.security.codeScanning.recommendation | Should -Be 'not-applicable-powershell-only'
        $repoSettings.security.codeScanning.reason | Should -Match 'CodeQL-supported source language'
        $repoSettings.security.codeScanning.codeqlSupportedLanguageDetected | Should -BeFalse
        @($repoSettings.security.codeScanning.codeqlSupportedLanguages) | Should -HaveCount 0
        $repoSettings.security.codeScanning.codeqlWorkflowPresent | Should -BeFalse
        $repoSettings.security.codeScanning.sarifUploadWorkflowPresent | Should -BeFalse
        $repoSettings.security.codeScanning.Contains('scorecardSarifUploadPresent') | Should -BeFalse -Because 'the Scorecard workflow grep was removed'
        $repoSettings.security.codeScanning.localControls | Should -Contain 'local-validation-bootstrap'
        $repoSettings.security.codeScanning.localControls | Should -Contain 'psscriptanalyzer'
        $repoSettings.security.codeScanning.localControls | Should -Contain 'pester'
        $repoSettings.security.codeScanning.localControls | Should -Contain 'markdownlint'
        $repoSettings.security.codeScanning.localControls | Should -Contain 'zizmor-config'
        $repoSettings.security.codeScanning.hostedControls | Should -Contain 'secret-scanning'
        $repoSettings.security.codeScanning.hostedControls | Should -Contain 'secret-scanning-push-protection'
        $repoSettings.security.codeScanning.hostedControls | Should -Contain 'dependabot-security-updates'
        $repoSettings.security.codeScanning.hostedControls | Should -Not -Contain 'psscriptanalyzer'
        $repoSettings.security.codeScanning.hostedControls | Should -Not -Contain 'actionlint'
        $repoSettings.security.codeScanning.hostedControls | Should -Not -Contain 'zizmor'
        $repoSettings.security.codeScanning.hostedControls | Should -Not -Contain 'openssf-scorecard-sarif'
        $repoSettings.security.codeScanning.activeControls | Should -Contain 'psscriptanalyzer'
        $repoSettings.security.codeScanning.activeControls | Should -Contain 'dependabot-security-updates'
        $scorecardPosture.available | Should -BeTrue
        $scorecardPosture.openAlertCount | Should -Be 6
        $scorecardPosture.localActionableCount | Should -Be 0
        $scorecardPosture.needsHostedRefreshCount | Should -Be 1
        $scorecardPosture.externalGatedCount | Should -Be 3
        $scorecardPosture.notApplicableCount | Should -Be 2
        $scorecardPosture.recommendation | Should -Be 'rerun-scorecard-to-refresh-alerts'
        ($scorecardPosture.rows | Where-Object { $_.ruleId -eq 'SecurityPolicyID' }).classification | Should -Be 'local-fix-pending-scorecard-refresh'
        ($scorecardPosture.rows | Where-Object { $_.ruleId -eq 'SASTID' }).classification | Should -Be 'covered-by-local-static-analysis'
        ($scorecardPosture.rows | Where-Object { $_.ruleId -eq 'FuzzingID' }).classification | Should -Be 'not-applicable-profile-generator'
        ($scorecardPosture.rows | Where-Object { $_.ruleId -eq 'CodeReviewID' }).classification | Should -Be 'external-gated-reviewer-model'
        ($scorecardPosture.rows | Where-Object { $_.ruleId -eq 'CodeReviewID' }).nextAction | Should -Match 'independent reviewer'
        ($scorecardPosture.rows | Where-Object { $_.ruleId -eq 'BranchProtectionID' }).classification | Should -Be 'external-gated-branch-protection-policy'
        ($scorecardPosture.rows | Where-Object { $_.ruleId -eq 'BranchProtectionID' }).nextAction | Should -Match 'direct-main maintenance policy'
        ($scorecardPosture.rows | Where-Object { $_.ruleId -eq 'CIIBestPracticesID' }).classification | Should -Be 'external-program-optional'
        $repoSettings.branchProtection.requiredStatusChecks | Should -BeFalse
        $repoSettings.rulesets.count | Should -Be 0
        $repoSettings.actionsWorkflowPermissions.recommendation | Should -Be 'local-validation-only'
        $repoSettings.actionsWorkflowPermissions.generatedPrCredentialDecision.status | Should -Be 'not-applicable'
        $repoSettings.actionsWorkflowPermissions.generatedPrCredentialDecision.selectedPath | Should -Be 'manual-local-validation'
        $repoSettings.actionsWorkflowPermissions.generatedPrCredentialDecision.requiresRepositorySetting | Should -BeFalse
        $repoSettings.requiredCheckReadiness.status | Should -Be 'not-applicable'
        $repoSettings.requiredCheckReadiness.recommendation | Should -Be 'local-validation-only'
        $repoSettings.requiredCheckReadiness.readyForEnforcement | Should -BeFalse
        $repoSettings.requiredCheckReadiness.branchProtectionRequiredStatusChecks | Should -BeFalse
        $repoSettings.requiredCheckReadiness.rulesetCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.enforceAdmins | Should -BeTrue
        $repoSettings.requiredCheckReadiness.candidateCheckCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.candidateChecks | Should -BeNullOrEmpty
        $repoSettings.requiredCheckReadiness.workflowCoverage.status | Should -Be 'not-applicable'
        $repoSettings.requiredCheckReadiness.workflowCoverage.workflowCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.workflowCoverage.warningCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.status | Should -Be 'not-applicable'
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.readyForRequiredCheckEnforcement | Should -BeFalse
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.checklistCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.readyCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.blockedCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.needsLiveValidationCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.generatedPrDryRunEvidence | Should -BeNullOrEmpty
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.generatedPrWriteEvidence | Should -BeNullOrEmpty
        $repoSettings.requiredCheckReadiness.prDeliveryTransition.items | Should -BeNullOrEmpty
        $repoSettings.requiredCheckReadiness.blockerCount | Should -Be 0
        $repoSettings.requiredCheckReadiness.blockers | Should -BeNullOrEmpty
        $repoSettings.reviewPolicyPosture.available | Should -BeTrue
        $repoSettings.reviewPolicyPosture.status | Should -Be 'warning-only-single-maintainer'
        $repoSettings.reviewPolicyPosture.recommendation | Should -Be 'keep-warning-only-until-reviewer-model'
        $repoSettings.reviewPolicyPosture.pullRequestReviewsRequired | Should -BeFalse
        $repoSettings.reviewPolicyPosture.codeOwnerReviewsRequired | Should -BeFalse
        $repoSettings.reviewPolicyPosture.requiredStatusChecksEnabled | Should -BeFalse
        $repoSettings.reviewPolicyPosture.codeownersFilePresent | Should -BeTrue
        $repoSettings.reviewPolicyPosture.scorecardCodeReviewClassification | Should -Be 'external-gated-reviewer-model'
        $repoSettings.reviewPolicyPosture.documentationPath | Should -Be 'decision:review-policy-posture'
        $repoSettings.reviewPolicyPosture.nextAction | Should -Match 'independent reviewer'
        $repoSettings.warningCount | Should -BeGreaterThan 0
        ($repoSettings.warnings -join ' ') | Should -Not -Match 'create pull requests'
        ($repoSettings | ConvertTo-Json -Depth 20) | Should -Not -Match 'secret_value|ghp_|gho_|github_pat_'

        $communityHealth.available | Should -BeTrue
        $communityHealth.healthPercentage | Should -Be 71
        $communityHealth.providerFiles.issueTemplate | Should -BeFalse
        $communityHealth.localRequiredMissingCount | Should -Be 0
        $communityHealth.fatalCount | Should -Be 0
        # Provider issue-template gap with local forms present is contextual info, not a warning.
        $communityHealth.issueTemplateProviderState | Should -Be 'provider-gap-local-forms-present'
        $communityHealth.localIssueFormCount | Should -Be 4
        ($communityHealth.warnings -join ' ') | Should -Not -Match 'issue-template'
        ($communityHealth.info -join ' ') | Should -Match 'issue form'
    }

    It 'warns when neither provider templates nor local issue forms exist' {
        $repository = [pscustomobject]@{ visibility = 'public'; has_issues = $true }
        $community = [pscustomobject]@{
            health_percentage = 50
            files = [pscustomobject]@{
                readme = [pscustomobject]@{}
                license = [pscustomobject]@{}
                issue_template = $null
                pull_request_template = [pscustomobject]@{}
                contributing = [pscustomobject]@{}
                code_of_conduct = [pscustomobject]@{}
            }
        }
        $localNoForms = @(
            [ordered]@{ path = 'README.md'; required = $true; exists = $true },
            [ordered]@{ path = 'LICENSE'; required = $true; exists = $true },
            [ordered]@{ path = 'SECURITY.md'; required = $true; exists = $true }
        )

        $result = Test-RepositoryCommunityBaseline -Repository $repository -CommunityProfile $community -LocalFiles $localNoForms -CodeScanningLocalEvidence ([ordered]@{ sarifUploadWorkflowPresent = $true })
        $community = $result.communityHealth
        $community.issueTemplateProviderState | Should -Be 'missing'
        $community.localIssueFormCount | Should -Be 0
        ($community.warnings -join ' ') | Should -Match 'structured intake'
    }

    It 'reports detected provider issue templates without info or warning noise' {
        $repository = [pscustomobject]@{ visibility = 'public'; has_issues = $true }
        $community = [pscustomobject]@{
            health_percentage = 90
            files = [pscustomobject]@{
                readme = [pscustomobject]@{}
                license = [pscustomobject]@{}
                issue_template = [pscustomobject]@{}
                pull_request_template = [pscustomobject]@{}
                contributing = [pscustomobject]@{}
                code_of_conduct = [pscustomobject]@{}
            }
        }
        $result = Test-RepositoryCommunityBaseline -Repository $repository -CommunityProfile $community -LocalFiles $script:LocalCommunityFilesOk -CodeScanningLocalEvidence ([ordered]@{ sarifUploadWorkflowPresent = $true })
        $result.communityHealth.issueTemplateProviderState | Should -Be 'detected'
        ($result.communityHealth.info -join ' ') | Should -Not -Match 'issue form'
    }

    It 'uses automated-security-fixes fallback when repository metadata omits Dependabot status' {
        $repository = [pscustomobject]@{
            security_and_analysis = [pscustomobject]@{
                secret_scanning = [pscustomobject]@{ status = 'enabled' }
                secret_scanning_push_protection = [pscustomobject]@{ status = 'enabled' }
            }
        }
        $codeScanningEvidence = [ordered]@{
            codeqlWorkflowPresent = $false
            sarifUploadWorkflowPresent = $true
            psScriptAnalyzerWorkflowPresent = $true
            actionlintWorkflowPresent = $true
            zizmorWorkflowPresent = $true
        }

        $result = Test-RepositoryCommunityBaseline -Repository $repository -LocalFiles $script:LocalCommunityFilesOk -CodeScanningLocalEvidence $codeScanningEvidence -DependabotSecurityUpdatesStatus 'enabled'
        $repoSettings = $result['repositorySettings']

        $repoSettings.security.dependabotSecurityUpdates | Should -Be 'enabled'
        $repoSettings.security.dependabotSecurityPosture.status | Should -Be 'enabled'
        $repoSettings.security.dependabotSecurityPosture.recommendation | Should -Be 'disable-dependabot-per-repository-policy'
        $repoSettings.security.codeScanning.activeControls | Should -Contain 'dependabot-security-updates'
        $repoSettings.security.codeScanning.hostedControls | Should -Contain 'dependabot-security-updates'
        # Scorecard runs locally now; a workflow is no longer counted as a Scorecard control.
        $repoSettings.security.codeScanning.hostedControls | Should -Not -Contain 'openssf-scorecard-sarif'
        $repoSettings.security.codeScanning.hostedControls | Should -Contain 'actionlint-workflow'
        ($repoSettings.warnings -join ' ') | Should -Not -Match 'Dependabot security updates are not enabled'
    }

    It 'does not report unavailable repository security metadata as disabled' {
        $repository = [pscustomobject]@{
            security_and_analysis = [pscustomobject]@{}
        }

        $result = Test-RepositoryCommunityBaseline -Repository $repository -LocalFiles $script:LocalCommunityFilesOk -DependabotSecurityUpdatesUnavailableReason 'Resource not accessible by integration (HTTP 403)'
        $repoSettings = $result['repositorySettings']
        $warnings = $repoSettings.warnings -join ' '

        $repoSettings.security.dependabotSecurityPosture.status | Should -Be 'unavailable'
        $repoSettings.security.dependabotSecurityPosture.evidence | Should -Match 'automated-security-fixes endpoint'
        $repoSettings.security.scorecardScore.available | Should -BeFalse
        $repoSettings.security.scorecardScore.score | Should -BeNullOrEmpty
        $repoSettings.security.scorecardScore.unavailableReason | Should -Be 'scorecard score evidence was not supplied'
        $warnings | Should -Match 'Secret scanning status is unavailable'
        $warnings | Should -Match 'Secret scanning push protection status is unavailable'
        $warnings | Should -Match 'Dependabot security update status is unavailable'
        $warnings | Should -Not -Match 'Secret scanning is not enabled'
        $warnings | Should -Not -Match 'Secret scanning push protection is not enabled'
        $warnings | Should -Not -Match 'Dependabot security updates are not enabled'
    }

    It 'warns when a CodeQL-supported language appears without an intentional CodeQL workflow' {
        $repository = [pscustomobject]@{
            security_and_analysis = [pscustomobject]@{
                secret_scanning = [pscustomobject]@{ status = 'enabled' }
                secret_scanning_push_protection = [pscustomobject]@{ status = 'enabled' }
                dependabot_security_updates = [pscustomobject]@{ status = 'disabled' }
            }
        }
        $codeScanningEvidence = [ordered]@{
            codeqlWorkflowPresent = $false
            sarifUploadWorkflowPresent = $true
            psScriptAnalyzerWorkflowPresent = $true
            actionlintWorkflowPresent = $true
            zizmorWorkflowPresent = $true
        }

        $result = Test-RepositoryCommunityBaseline -Repository $repository -Languages ([pscustomobject]@{ PowerShell = 200; Python = 100 }) -LocalFiles $script:LocalCommunityFilesOk -CodeScanningLocalEvidence $codeScanningEvidence
        $codeScanning = $result['repositorySettings'].security.codeScanning

        $codeScanning.status | Should -Be 'needs-live-validation'
        $codeScanning.recommendation | Should -Be 'verify-code-scanning-for-supported-languages'
        $codeScanning.codeqlSupportedLanguageDetected | Should -BeTrue
        $codeScanning.codeqlSupportedLanguages | Should -Contain 'Python'
        $codeScanning.codeqlWorkflowPresent | Should -BeFalse
        $codeScanning.hostedControls | Should -Not -Contain 'openssf-scorecard-sarif'
        $codeScanning.hostedControls | Should -Contain 'actionlint-workflow'
        ($result['repositorySettings'].warnings -join ' ') | Should -Match 'CodeQL-supported languages detected'
    }

    It 'marks missing required local intake files fatal' {
        $localFiles = @(
            [ordered]@{ path = 'SECURITY.md'; required = $true; exists = $false },
            [ordered]@{ path = 'CONTRIBUTING.md'; required = $false; exists = $false }
        )

        $result = Test-RepositoryCommunityBaseline -LocalFiles $localFiles -RepositoryUnavailableReason 'offline' -CommunityUnavailableReason 'offline' -BranchProtectionUnavailableReason 'offline' -RulesetsUnavailableReason 'offline' -LanguagesUnavailableReason 'offline'
        $communityHealth = $result['communityHealth']

        $communityHealth.fatalCount | Should -Be 1
        $communityHealth.localRequiredMissingCount | Should -Be 1
        ($communityHealth.errors -join ' ') | Should -Match 'SECURITY.md'
    }

    It 'records unavailable live metadata without failing local-file checks' {
        $result = Test-RepositoryCommunityBaseline -LocalFiles $script:LocalCommunityFilesOk -RepositoryUnavailableReason 'gh authentication unavailable' -CommunityUnavailableReason 'gh authentication unavailable' -BranchProtectionUnavailableReason 'gh authentication unavailable' -RulesetsUnavailableReason 'gh authentication unavailable' -LanguagesUnavailableReason 'gh authentication unavailable'

        $result['repositorySettings'].available | Should -BeFalse
        $result['repositorySettings'].unavailableReason | Should -Be 'gh authentication unavailable'
        $result['repositorySettings'].warningCount | Should -BeGreaterThan 0
        $result['communityHealth'].available | Should -BeFalse
        $result['communityHealth'].fatalCount | Should -Be 0
    }
}

Describe 'GraphQL resource limit downshift' {
    BeforeEach {
        # These cases drive the online fetch through a stubbed Invoke-GhCli, so they have to
        # leave the suite's offline mode; offline, Get-GitHubRepos reads the local cache.
        $script:DownshiftOldOffline = $script:Offline
        $script:Offline = $false
    }

    AfterEach {
        $script:Offline = $script:DownshiftOldOffline
        Remove-Item Function:\Invoke-GhCli -ErrorAction SilentlyContinue
        Remove-Variable -Name RequestedLimits -Scope Script -ErrorAction SilentlyContinue
        Reset-MetadataFetchTelemetry
        Reset-RestFallbackReleaseFetchState
    }

    It 'halves the requested page size instead of resending an over-limit query' {
        $script:RequestedLimits = New-Object System.Collections.Generic.List[int]
        function Invoke-GhCli {
            param([string[]]$Arguments, [string]$StandardInput, [int]$TimeoutSeconds = 45)

            $limitIndex = [array]::IndexOf($Arguments, '--limit')
            $script:RequestedLimits.Add([int]$Arguments[$limitIndex + 1])
            if ($script:RequestedLimits.Count -eq 1) {
                return @{ output = 'x'; exitCode = 1; text = 'GraphQL resource limit exceeded for this query' }
            }
            $payload = @(
                [ordered]@{ name = 'OnlyRepo'; description = 'd'; stargazerCount = 1; isFork = $false; isPrivate = $false; isArchived = $false; pushedAt = '2026-08-01T00:00:00Z'; url = 'https://github.com/SysAdminDoc/OnlyRepo' }
            ) | ConvertTo-Json -Depth 6
            return @{ output = $payload; exitCode = 0; text = $payload }
        }

        $oldPageSize = $script:GraphQlPageSize
        $script:GraphQlPageSize = 500
        try {
            $repos = @(Get-GitHubRepos)

            $repos.Count | Should -Be 1
            $script:RequestedLimits.Count | Should -Be 2
            $script:RequestedLimits[0] | Should -Be 500
            # Retrying the identical oversized query would fail the same way every time.
            $script:RequestedLimits[1] | Should -Be 250
            $script:MetadataFetchPageSizeReduced | Should -BeTrue
            $script:RepositoryMetadataProvider | Should -Be 'graphql'
        } finally {
            $script:GraphQlPageSize = $oldPageSize
        }
    }

    It 'never reduces the page size below the REST pagination floor' {
        $script:RequestedLimits = New-Object System.Collections.Generic.List[int]
        function Invoke-GhCli {
            param([string[]]$Arguments, [string]$StandardInput, [int]$TimeoutSeconds = 45)

            # Only the repo-list query carries --limit; the REST fallback afterwards does not.
            $limitIndex = [array]::IndexOf($Arguments, '--limit')
            if ($limitIndex -ge 0) {
                $script:RequestedLimits.Add([int]$Arguments[$limitIndex + 1])
            }
            return @{ output = 'x'; exitCode = 1; text = 'GraphQL resource limit exceeded for this query' }
        }

        $oldPageSize = $script:GraphQlPageSize
        $script:GraphQlPageSize = 120
        try {
            # Every GraphQL attempt fails here, so the run ends in the REST fallback and
            # throws. The assertion is about the page sizes tried on the way there.
            try { $null = Get-GitHubRepos } catch { }
            $script:RequestedLimits.Count | Should -BeGreaterThan 1
            foreach ($limit in $script:RequestedLimits) {
                $limit | Should -BeGreaterOrEqual 100
            }
        } finally {
            $script:GraphQlPageSize = $oldPageSize
        }
    }
}

Describe 'REST fallback release request guard' {
    It 'parses slurped paginated repo arrays from gh api' {
        $json = @'
[
  [
    { "name": "A", "archived": false, "private": false }
  ],
  [
    { "name": "B", "archived": false, "private": false }
  ]
]
'@

        $repos = @(ConvertFrom-RestRepoPageJson -Json $json)

        $repos | Should -HaveCount 2
        $repos[0].name | Should -Be 'A'
        $repos[1].name | Should -Be 'B'
    }

    It 'maps REST repo metadata when optional fields are omitted' {
        $repo = [pscustomobject]@{
            name = 'OptionalFieldsRepo'
            description = 'REST fallback fixture'
            stargazers_count = 3
            default_branch = 'main'
            fork = $false
            private = $false
            archived = $false
            pushed_at = '2026-06-11T07:00:00Z'
            html_url = 'https://github.com/SysAdminDoc/OptionalFieldsRepo'
        }

        $mapped = ConvertFrom-RestRepoMetadata -Repo $repo -Release $null

        $mapped.name | Should -Be 'OptionalFieldsRepo'
        $mapped.defaultBranchRef.name | Should -Be 'main'
        $mapped.parent | Should -BeNullOrEmpty
        $mapped.repositoryTopics | Should -HaveCount 0
        $mapped.licenseInfo | Should -BeNullOrEmpty
        $mapped.primaryLanguage | Should -BeNullOrEmpty
    }

    It 'requires authentication when release requests exceed the unauthenticated budget' {
        $result = Test-RestFallbackReleaseFetchBudget -RepoCount 184 -Authenticated:$false -MaxReleaseFetches 240 -UnauthenticatedReleaseFetchLimit 50

        $result.allowed | Should -BeFalse
        $result.message | Should -Match 'requires authenticated gh access'
    }

    It 'caps release requests even when authenticated' {
        $result = Test-RestFallbackReleaseFetchBudget -RepoCount 241 -Authenticated:$true -MaxReleaseFetches 240 -UnauthenticatedReleaseFetchLimit 50

        $result.allowed | Should -BeFalse
        $result.message | Should -Match 'exceeding the configured cap'
    }

    It 'allows the current repo count when authenticated and under the cap' {
        $result = Test-RestFallbackReleaseFetchBudget -RepoCount 184 -Authenticated:$true -MaxReleaseFetches 240 -UnauthenticatedReleaseFetchLimit 50

        $result.allowed | Should -BeTrue
        $result.message | Should -BeNullOrEmpty
    }

    It 'falls back when gh repo list returns the default 100-row page' {
        $script:SyncProfileScript | Should -Match 'repos[.]Count -eq 100'
        $script:SyncProfileScript | Should -Match 'falling back to REST pagination'
        $script:SyncProfileScript | Should -Match 'partial default-page result'
    }

    It 'classifies GitHub API resource and rate-limit metadata failures' {
        Test-GitHubMetadataResourceLimit -Output 'GraphQL resource limit exceeded for this query' | Should -BeTrue
        Test-GitHubMetadataResourceLimit -Output 'gh: API rate limit exceeded (HTTP 403)' | Should -BeTrue
        Test-GitHubMetadataResourceLimit -Output 'gh: Bad Gateway (HTTP 502)' | Should -BeTrue
        Test-GitHubMetadataResourceLimit -Output 'gh: Not Found (HTTP 404)' | Should -BeFalse
    }

    It 'keeps a 24-row configured GraphQL page on GraphQL and records successful metadata telemetry' {
        $oldOffline = $script:Offline
        $ownerVariable = Get-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
        $pageSizeVariable = Get-Variable -Name GraphQlPageSize -Scope Script -ErrorAction SilentlyContinue
        $hadOwner = ($null -ne $ownerVariable)
        $hadPageSize = ($null -ne $pageSizeVariable)
        $oldOwner = if ($hadOwner) { $ownerVariable.Value } else { $null }
        $oldPageSize = if ($hadPageSize) { $pageSizeVariable.Value } else { $null }
        $script:Offline = $false
        $script:Owner = 'SysAdminDoc'
        $script:GraphQlPageSize = 25
        $script:ghCommands = @()

        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $script:ghCommands += ($Arguments -join ' ')
            $global:LASTEXITCODE = 0
            return @(1..24 | ForEach-Object {
                @{ name = "GraphRepo$($_.ToString('00'))" }
            }) | ConvertTo-Json -Depth 5
        }

        try {
            $repos = @(Get-GitHubRepos)

            $repos | Should -HaveCount 24
            $script:ghCommands[0] | Should -Match '--limit 25'
            $script:MetadataFetchAttemptCount | Should -Be 1
            $script:MetadataFetchRequestCount | Should -Be 1
            $script:RepositoryEnumerationRequestedLimit | Should -Be 25
            $script:RepositoryMetadataProvider | Should -Be 'graphql'
            $script:RepositoryEnumerationTruncated | Should -BeFalse
            $script:MetadataFetchResourceLimitFallback | Should -BeFalse
        } finally {
            $script:Offline = $oldOffline
            if ($hadOwner) {
                $script:Owner = $oldOwner
            } else {
                Remove-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
            }
            if ($hadPageSize) {
                $script:GraphQlPageSize = $oldPageSize
            } else {
                Remove-Variable -Name GraphQlPageSize -Scope Script -ErrorAction SilentlyContinue
            }
            Remove-Variable -Name ghCommands -Scope Script -ErrorAction SilentlyContinue
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
            Reset-MetadataFetchTelemetry
            Reset-RestFallbackReleaseFetchState
        }
    }

    It 'falls back to complete REST enumeration when the configured GraphQL page is full' {
        $oldOffline = $script:Offline
        $oldCachePath = $script:CachePath
        $oldCacheEnabled = $script:CacheEnabled
        $ownerVariable = Get-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
        $pageSizeVariable = Get-Variable -Name GraphQlPageSize -Scope Script -ErrorAction SilentlyContinue
        $hadOwner = ($null -ne $ownerVariable)
        $hadPageSize = ($null -ne $pageSizeVariable)
        $oldOwner = if ($hadOwner) { $ownerVariable.Value } else { $null }
        $oldPageSize = if ($hadPageSize) { $pageSizeVariable.Value } else { $null }
        $script:Offline = $false
        $script:Owner = 'SysAdminDoc'
        $script:GraphQlPageSize = 25
        $script:CachePath = Join-Path $TestDrive 'full-page-cache'
        $script:CacheEnabled = $true
        Reset-ValidationCacheState
        Write-ValidationCacheEntry -Bucket metadata -Key (Get-LiveRepositoryMetadataCacheKey) -Value @(
            (New-TestRepoMeta -Name 'StaleCachedRepo')
        )

        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $command = $Arguments -join ' '
            $command = ($command -replace '\s*-H X-GitHub-Api-Version: [\d-]+', '')
            if ($command -like 'repo list *') {
                $global:LASTEXITCODE = 0
                return @(1..25 | ForEach-Object {
                    @{ name = "GraphRepo$($_.ToString('00'))" }
                }) | ConvertTo-Json -Depth 5
            }
            if ($command -eq 'api --paginate --slurp users/SysAdminDoc/repos?per_page=100') {
                $global:LASTEXITCODE = 0
                $restRows = @(1..27 | ForEach-Object {
                    [ordered]@{
                        name = if ($_ -eq 27) { 'RestOnlyRepo' } else { "RestRepo$($_.ToString('00'))" }
                        description = 'REST fallback fixture'
                        stargazers_count = $_
                        default_branch = 'main'
                        fork = $false
                        private = $false
                        archived = $false
                        topics = @('utility')
                        pushed_at = '2026-08-23T00:00:00Z'
                        html_url = "https://github.com/SysAdminDoc/RestRepo$($_.ToString('00'))"
                    }
                })
                $pageJson = $restRows | ConvertTo-Json -Depth 5 -Compress
                return "[$pageJson]"
            }

            throw "Unexpected gh invocation: $command"
        }

        try {
            Mock -CommandName Start-Sleep -MockWith {}

            $repos = @(Get-GitHubRepos)

            $repos | Should -HaveCount 27
            @($repos.name) | Should -Contain 'RestOnlyRepo'
            @($repos.name) | Should -Not -Contain 'GraphRepo25'
            @($repos.name) | Should -Not -Contain 'StaleCachedRepo'
            $script:RepositoryMetadataProvider | Should -Be 'rest-fallback'
            $script:MetadataFetchFallbackReason | Should -Match '25 repos at limit 25'
            $script:MetadataFetchAttemptCount | Should -Be 1
            $script:MetadataFetchRequestCount | Should -Be 2
            $script:RepositoryEnumerationRequestedLimit | Should -Be 0
            $script:RepositoryEnumerationTruncated | Should -BeFalse
        } finally {
            $script:Offline = $oldOffline
            $script:CachePath = $oldCachePath
            $script:CacheEnabled = $oldCacheEnabled
            Reset-ValidationCacheState
            if ($hadOwner) {
                $script:Owner = $oldOwner
            } else {
                Remove-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
            }
            if ($hadPageSize) {
                $script:GraphQlPageSize = $oldPageSize
            } else {
                Remove-Variable -Name GraphQlPageSize -Scope Script -ErrorAction SilentlyContinue
            }
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
            Reset-MetadataFetchTelemetry
            Reset-RestFallbackReleaseFetchState
        }
    }

    It 'records request, retry, and resource-limit telemetry when GraphQL falls back to REST' {
        $oldOffline = $script:Offline
        $ownerVariable = Get-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
        $pageSizeVariable = Get-Variable -Name GraphQlPageSize -Scope Script -ErrorAction SilentlyContinue
        $hadOwner = ($null -ne $ownerVariable)
        $hadPageSize = ($null -ne $pageSizeVariable)
        $oldOwner = if ($hadOwner) { $ownerVariable.Value } else { $null }
        $oldPageSize = if ($hadPageSize) { $pageSizeVariable.Value } else { $null }
        $script:Offline = $false
        $script:Owner = 'SysAdminDoc'
        $script:GraphQlPageSize = 75

        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $command = $Arguments -join ' '
            # Transport-level API version pin is not part of what call sites assert.
            $command = ($command -replace '\s*-H X-GitHub-Api-Version: [\d-]+', '')
            if ($command -like 'repo list *') {
                $global:LASTEXITCODE = 1
                return 'GraphQL resource limit exceeded for this query'
            }
            if ($command -eq 'api --paginate --slurp users/SysAdminDoc/repos?per_page=100') {
                $global:LASTEXITCODE = 0
                return '[[{"name":"RestRepo","description":"desc","stargazers_count":1,"default_branch":"main","fork":false,"private":false,"archived":false,"topics":["utility"],"pushed_at":"2026-07-06T00:00:00Z","html_url":"https://github.com/SysAdminDoc/RestRepo"}]]'
            }

            throw "Unexpected gh invocation: $command"
        }

        try {
            $repos = @(Get-GitHubRepos)

            $repos | Should -HaveCount 1
            $script:RepositoryMetadataProvider | Should -Be 'rest-fallback'
            $script:MetadataFetchAttemptCount | Should -Be 3
            $script:MetadataFetchRequestCount | Should -Be 4
            $script:MetadataFetchResourceLimitFallback | Should -BeTrue
            $script:MetadataFetchResourceLimitReason | Should -Match 'resource limit'
            $script:RepositoryEnumerationRequestedLimit | Should -Be 0
        } finally {
            $script:Offline = $oldOffline
            if ($hadOwner) {
                $script:Owner = $oldOwner
            } else {
                Remove-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
            }
            if ($hadPageSize) {
                $script:GraphQlPageSize = $oldPageSize
            } else {
                Remove-Variable -Name GraphQlPageSize -Scope Script -ErrorAction SilentlyContinue
            }
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
            Reset-MetadataFetchTelemetry
            Reset-RestFallbackReleaseFetchState
        }
    }

    It 'treats release 404 as no release while keeping rate limits fatal' {
        Test-GhApiNotFound -Output 'gh: Not Found (HTTP 404)' | Should -BeTrue
        Test-GhApiNotFound -Output 'gh: API rate limit exceeded (HTTP 403)' | Should -BeFalse
    }

    It 'extracts gh api HTTP status from failure output' {
        Get-GhApiHttpStatus -Output 'gh: API rate limit exceeded (HTTP 403)' | Should -Be 403
        Get-GhApiHttpStatus -Output 'gh: Not Found (HTTP 404)' | Should -Be 404
        Get-GhApiHttpStatus -Output 'network failed before an HTTP response' | Should -BeNullOrEmpty
    }

    It 'creates a reportable REST fallback release-fetch state' {
        $state = New-RestFallbackReleaseFetchState `
            -Used `
            -Status 'aborted' `
            -RepoCount 184 `
            -Authenticated:$true `
            -AttemptedReleaseFetches 12 `
            -SuccessfulReleaseFetches 10 `
            -NoRelease404Count 1 `
            -Fatal:$true `
            -AbortRepo 'BrokenRepo' `
            -AbortHttpStatus 403 `
            -AbortMessage 'Latest-release fetch failed after 12 attempted request(s).'

        $state.used | Should -BeTrue
        $state.status | Should -Be 'aborted'
        $state.repoCount | Should -Be 184
        $state.attemptedReleaseFetches | Should -Be 12
        $state.noRelease404Count | Should -Be 1
        $state.fatal | Should -BeTrue
        $state.abortRepo | Should -Be 'BrokenRepo'
        $state.abortHttpStatus | Should -Be 403
    }

    It 'reports GraphQL and offline paths as not using REST release fallback' {
        Reset-RestFallbackReleaseFetchState
        $state = Get-RestFallbackReleaseFetchState

        $state.used | Should -BeFalse
        $state.status | Should -Be 'not-used'
        $state.attemptedReleaseFetches | Should -Be 0
        $state.fatal | Should -BeFalse
    }
}

Describe 'Validation cache' {
    BeforeEach {
        $script:TestValidationCachePath = Join-Path ([System.IO.Path]::GetTempPath()) ("sysadmindoc-cache-test-" + [guid]::NewGuid().ToString("N"))
        $script:OldValidationCachePath = $script:CachePath
        $script:OldValidationCacheTtlHours = $script:CacheTtlHours
        $script:OldValidationCacheEnabled = $script:CacheEnabled
        $script:OldValidationOffline = $script:Offline
        $ownerVariable = Get-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
        $pageSizeVariable = Get-Variable -Name GraphQlPageSize -Scope Script -ErrorAction SilentlyContinue
        $providerVariable = Get-Variable -Name RepositoryMetadataProvider -Scope Script -ErrorAction SilentlyContinue
        $script:HadValidationOwner = ($null -ne $ownerVariable)
        $script:HadValidationGraphQlPageSize = ($null -ne $pageSizeVariable)
        $script:HadValidationRepositoryMetadataProvider = ($null -ne $providerVariable)
        $script:OldValidationOwner = if ($script:HadValidationOwner) { $ownerVariable.Value } else { $null }
        $script:OldValidationGraphQlPageSize = if ($script:HadValidationGraphQlPageSize) { $pageSizeVariable.Value } else { $null }
        $script:OldValidationRepositoryMetadataProvider = if ($script:HadValidationRepositoryMetadataProvider) { $providerVariable.Value } else { $null }

        $script:CachePath = $script:TestValidationCachePath
        $script:CacheTtlHours = 24
        $script:CacheEnabled = $true
        $script:Owner = 'SysAdminDoc'
        $script:GraphQlPageSize = 50
        Reset-ValidationCacheState
        Reset-RestFallbackReleaseFetchState
    }

    AfterEach {
        $script:CachePath = $script:OldValidationCachePath
        $script:CacheTtlHours = $script:OldValidationCacheTtlHours
        $script:CacheEnabled = $script:OldValidationCacheEnabled
        $script:Offline = $script:OldValidationOffline
        if ($script:HadValidationOwner) {
            $script:Owner = $script:OldValidationOwner
        } else {
            Remove-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
        }
        if ($script:HadValidationGraphQlPageSize) {
            $script:GraphQlPageSize = $script:OldValidationGraphQlPageSize
        } else {
            Remove-Variable -Name GraphQlPageSize -Scope Script -ErrorAction SilentlyContinue
        }
        if ($script:HadValidationRepositoryMetadataProvider) {
            $script:RepositoryMetadataProvider = $script:OldValidationRepositoryMetadataProvider
        } else {
            Remove-Variable -Name RepositoryMetadataProvider -Scope Script -ErrorAction SilentlyContinue
        }
        Reset-ValidationCacheState
        Reset-RestFallbackReleaseFetchState
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
        Remove-Item Function:\Start-Sleep -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestValidationCachePath -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($name in @(
                'TestValidationCachePath',
                'OldValidationCachePath',
                'OldValidationCacheTtlHours',
                'OldValidationCacheEnabled',
                'OldValidationOffline',
                'HadValidationOwner',
                'OldValidationOwner',
                'HadValidationGraphQlPageSize',
                'OldValidationGraphQlPageSize',
                'HadValidationRepositoryMetadataProvider',
                'OldValidationRepositoryMetadataProvider'
            )) {
            Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'reads fresh entries and marks stale entries without leaking cache files into git' {
        $cacheKey = 'unit-metadata'
        Write-ValidationCacheEntry `
            -Bucket metadata `
            -Key $cacheKey `
            -Value ([pscustomobject]@{ name = 'CachedRepo' }) `
            -Headers @{ ETag = '"abc123"'; 'Last-Modified' = 'Tue, 07 Jul 2026 00:00:00 GMT' }

        $value = Get-ValidationCacheValue -Bucket metadata -Key $cacheKey
        $state = Get-ValidationCacheState

        $value.name | Should -Be 'CachedRepo'
        $state.metadata.writeCount | Should -Be 1
        $state.metadata.hitCount | Should -Be 1
        $state.metadata.missCount | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot '.gitignore') -Raw) | Should -Match '(?m)^\.cache/$'

        $cacheFile = Get-ValidationCacheFilePath -Bucket metadata -Key $cacheKey
        $entry = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $cacheFile) -File -Force | Where-Object { $_.Name -match '[.](stage|backup)([.]|$)' }) | Should -BeNullOrEmpty
        $entry.fetchedAt = (Get-Date).ToUniversalTime().AddHours(-48).ToString("o")
        $entry | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $cacheFile -Encoding utf8

        Get-ValidationCacheValue -Bucket metadata -Key $cacheKey | Should -BeNullOrEmpty
        (Get-ValidationCacheState).metadata.staleCount | Should -Be 1
    }

    It 'records complete owner-bound generation inputs and rejects incomplete snapshots' {
        $oldMetadataSnapshotAt = $script:MetadataSnapshotAt
        $oldProvider = $script:RepositoryMetadataProvider
        $oldRequestedLimit = $script:RepositoryEnumerationRequestedLimit
        $oldTruncated = $script:RepositoryEnumerationTruncated
        $repo = New-TestRepoMeta -Name 'CachedCompleteRepo' -WithRelease -AssetNames @('CachedCompleteRepo.zip')

        try {
            $script:MetadataSnapshotAt = '2026-08-23T12:00:00.0000000Z'
            $script:RepositoryMetadataProvider = 'graphql'
            $script:RepositoryEnumerationRequestedLimit = 25
            $script:RepositoryEnumerationTruncated = $false

            Write-CompleteGenerationSnapshot -Repos @($repo) -ReleaseMetadataComplete:$true | Should -BeTrue
            $snapshot = Get-CompleteGenerationSnapshot
            $cacheFile = Get-ValidationCacheFilePath -Bucket metadata -Key (Get-CompleteGenerationSnapshotCacheKey)
            $cacheEnvelope = Read-ValidationCacheEntry -Bucket metadata -Key (Get-CompleteGenerationSnapshotCacheKey)

            $snapshot.owner | Should -BeOrdinal 'SysAdminDoc'
            $snapshot.sourceComplete | Should -BeTrue
            $snapshot.sourceCompleteness.repositoryEnumeration | Should -BeTrue
            $snapshot.sourceCompleteness.releases | Should -BeTrue
            $snapshot.schemaVersion | Should -Be 3
            $snapshot.Contains('contributionData') | Should -BeFalse
            $snapshot.sourceCompleteness.Contains('contributionData') | Should -BeFalse
            $snapshot.repositoryEnumeration.returnedCount | Should -Be 1
            $snapshot.repositoryEnumeration.truncated | Should -BeFalse
            $snapshot.repositories | Should -HaveCount 1
            $snapshot.releases | Should -HaveCount 1
            $snapshot.releases[0].latestRelease.tagName | Should -BeOrdinal 'v1.0.0'
            $cacheEnvelope.fetchedAt | Should -Not -BeNullOrEmpty
            $cacheEnvelope.value.fetchedAt | Should -BeOrdinal '2026-08-23T12:00:00.0000000Z'
            $cacheEnvelope.value.generationTimestamp | Should -Not -BeNullOrEmpty

            $snapshot.owner = 'DifferentOwner'
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.owner = 'SysAdminDoc'
            # A schema-2 snapshot from before the calendar was dropped must not replay.
            $snapshot.schemaVersion = 2
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.schemaVersion = 3
            $snapshot.sourceCompleteness.releases = $false
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.sourceCompleteness.releases = $true
            $snapshot.repositoryEnumeration.provider = 'cache-fallback'
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            # A restored provider and tip status are published as written, and the schemas'
            # enums are case-sensitive, so the restore can't take either in another case.
            $snapshot.repositoryEnumeration.provider = 'GraphQL'
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.repositoryEnumeration.provider = 'graphql'
            $tipStatus = $snapshot.repositories[0].branchTipStatus
            $snapshot.repositories[0].branchTipStatus = $tipStatus.ToUpperInvariant()
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.repositories[0].branchTipStatus = $tipStatus
            # -cnotin and -ne compared by culture, which skips an invisible character, so each of
            # these passed the restore check and would have been published or trusted as written.
            $snapshot.repositoryEnumeration.provider = 'graph' + [char]0x200B + 'ql'
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.repositoryEnumeration.provider = 'graphql'
            $snapshot.repositories[0].branchTipStatus = $tipStatus + [char]0x200B
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.repositories[0].branchTipStatus = $tipStatus
            $visibility = $snapshot.repositories[0].visibility
            $snapshot.repositories[0].visibility = 'PUB' + [char]0x200B + 'LIC'
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.repositories[0].visibility = $visibility
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeTrue -Because 'the snapshot passes once both are back in the schemas'' case'
            $snapshot.releases[0].repo = 'DifferentRepo'
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
            $snapshot.releases[0].repo = 'CachedCompleteRepo'

            $missingRepositoryRelease = $snapshot | ConvertTo-Json -Depth 50 | ConvertFrom-Json
            $missingRepositoryRelease.repositories[0].PSObject.Properties.Remove('latestRelease')
            Test-CompleteGenerationSnapshot -Snapshot $missingRepositoryRelease | Should -BeFalse

            foreach ($requiredField in @(
                'description', 'stargazerCount', 'defaultBranchRef', 'branchTipSha', 'branchTipFetchedAt',
                'branchTipStatus', 'branchTipWarning', 'licenseInfo', 'isFork', 'parent', 'isPrivate',
                'visibility', 'isArchived', 'repositoryTopics', 'pushedAt', 'url', 'primaryLanguage'
            )) {
                $partialRepository = $snapshot | ConvertTo-Json -Depth 50 | ConvertFrom-Json
                $partialRepository.repositories[0].PSObject.Properties.Remove($requiredField)
                Test-CompleteGenerationSnapshot -Snapshot $partialRepository | Should -BeFalse
            }

            $mismatchedRelease = $snapshot | ConvertTo-Json -Depth 50 | ConvertFrom-Json
            $mismatchedRelease.releases[0].latestRelease.tagName = 'v9.9.9'
            Test-CompleteGenerationSnapshot -Snapshot $mismatchedRelease | Should -BeFalse

            $snapshot.repositories = @($snapshot.repositories[0], $snapshot.repositories[0])
            $snapshot.releases = @($snapshot.releases[0], $snapshot.releases[0])
            $snapshot.repositoryEnumeration.returnedCount = 2
            Test-CompleteGenerationSnapshot -Snapshot $snapshot | Should -BeFalse
        } finally {
            $script:MetadataSnapshotAt = $oldMetadataSnapshotAt
            $script:RepositoryMetadataProvider = $oldProvider
            $script:RepositoryEnumerationRequestedLimit = $oldRequestedLimit
            $script:RepositoryEnumerationTruncated = $oldTruncated
        }
    }

    It 'replays complete cached generation inputs byte-identically across elapsed time' {
        $oldMetadataSnapshotAt = $script:MetadataSnapshotAt
        $oldProvider = $script:RepositoryMetadataProvider
        $oldRequestedLimit = $script:RepositoryEnumerationRequestedLimit
        $oldTruncated = $script:RepositoryEnumerationTruncated
        $oldGenerationArtifactTimestamp = $script:GenerationArtifactTimestamp
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -WithRelease -AssetNames @('WinTool.zip')),
            (New-TestRepoMeta -Name 'PyTool' -Language 'Python')
        )

        try {
            $script:MetadataSnapshotAt = '2026-08-23T12:00:00.0000000Z'
            $script:RepositoryMetadataProvider = 'graphql'
            $script:RepositoryEnumerationRequestedLimit = 25
            $script:RepositoryEnumerationTruncated = $false
            $generationTimestamp = '2026-08-23T12:00:01.0000000Z'

            $onlineReadme = New-Readme -Catalog $catalog -Repos $repos
            $onlineProjects = New-ProjectsExportJson -Catalog $catalog -Repos $repos -GeneratedAt $generationTimestamp
            Write-CompleteGenerationSnapshot -Repos $repos -ReleaseMetadataComplete:$true -GenerationTimestamp $generationTimestamp | Should -BeTrue

            $snapshot = Get-CompleteGenerationSnapshot
            Set-GenerationStateFromSnapshot -Snapshot $snapshot
            $cachedRepos = @(Get-MemberValue -Object $snapshot -Name 'repositories')
            $offlineReadme = New-Readme -Catalog $catalog -Repos $cachedRepos
            Start-Sleep -Milliseconds 25
            $offlineProjects = New-ProjectsExportJson -Catalog $catalog -Repos $cachedRepos -GeneratedAt $script:GenerationArtifactTimestamp

            $offlineReadme | Should -BeExactly $onlineReadme
            $offlineProjects | Should -BeExactly $onlineProjects
        } finally {
            $script:MetadataSnapshotAt = $oldMetadataSnapshotAt
            $script:RepositoryMetadataProvider = $oldProvider
            $script:RepositoryEnumerationRequestedLimit = $oldRequestedLimit
            $script:RepositoryEnumerationTruncated = $oldTruncated
            $script:GenerationArtifactTimestamp = $oldGenerationArtifactTimestamp
        }
    }

    It 'uses cached repository metadata for offline runs and records degraded fidelity' {
        $Owner = 'SysAdminDoc'
        $GraphQlPageSize = 37
        $Offline = $true
        $script:Offline = $true
        $script:GraphQlPageSize = 37
        Write-ValidationCacheEntry -Bucket metadata -Key (Get-LiveRepositoryMetadataCacheKey) -Value @(
            (New-TestRepoMeta -Name 'CachedOfflineRepo')
        )

        $repos = @(Get-GitHubRepos)
        $state = Get-ValidationCacheState

        $repos | Should -HaveCount 1
        $repos[0].name | Should -Be 'CachedOfflineRepo'
        $script:RepositoryMetadataProvider | Should -Be 'cache-offline'
        $script:MetadataFetchFallbackReason | Should -Be 'offline cache hit'
        $state.metadata.hitCount | Should -Be 1
        $state.metadata.usedForFallback | Should -BeTrue
        $state.metadata.lastFallbackReason | Should -Be 'offline'
    }

    It 'uses cached repository metadata after GraphQL resource-limit failures' {
        $Owner = 'SysAdminDoc'
        $GraphQlPageSize = 41
        $Offline = $false
        $script:Offline = $false
        $script:GraphQlPageSize = 41
        Write-ValidationCacheEntry -Bucket metadata -Key (Get-LiveRepositoryMetadataCacheKey) -Value @(
            (New-TestRepoMeta -Name 'CachedFallbackRepo')
        )

        function Start-Sleep {
            param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
        }

        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $global:LASTEXITCODE = 1
            return 'gh: API rate limit exceeded (HTTP 403)'
        }

        $repos = @(Get-GitHubRepos)
        $state = Get-ValidationCacheState

        $repos | Should -HaveCount 1
        $repos[0].name | Should -Be 'CachedFallbackRepo'
        $script:RepositoryMetadataProvider | Should -Be 'cache-fallback'
        $script:MetadataFetchAttemptCount | Should -Be 3
        $script:MetadataFetchRequestCount | Should -Be 3
        $script:MetadataFetchResourceLimitFallback | Should -BeTrue
        $state.metadata.usedForFallback | Should -BeTrue
        $state.metadata.lastFallbackReason | Should -Match 'rate limit'
    }

    It 'uses cached release metadata when latest-release fetches are rate-limited' {
        $Owner = 'SysAdminDoc'
        $Offline = $false
        $script:Offline = $false
        $script:RepositoryMetadataProvider = 'rest-fallback'
        $releaseKey = Get-ReleaseMetadataCacheKey -Repo 'CachedRelease'
        Write-ValidationCacheEntry -Bucket releases -Key $releaseKey -Value ([pscustomobject]@{
                tagName = 'v9.0.0'
                url = 'https://github.com/SysAdminDoc/CachedRelease/releases/tag/v9.0.0'
                name = 'v9.0.0'
                publishedAt = '2026-07-07T00:00:00Z'
                releaseAssetNames = @('CachedRelease.exe')
                releaseAssetKinds = @('exe')
                releaseAssetDigests = @()
                assetApiInspected = $true
                immutable = $true
            })

        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $command = $Arguments -join ' '
            # Transport-level API version pin is not part of what call sites assert.
            $command = ($command -replace '\s*-H X-GitHub-Api-Version: [\d-]+', '')
            if ($command -eq 'auth status -h github.com') {
                $global:LASTEXITCODE = 0
                return 'Logged in to github.com'
            }
            if ($command -eq 'api repos/SysAdminDoc/CachedRelease/releases/latest') {
                $global:LASTEXITCODE = 1
                return 'gh: API rate limit exceeded (HTTP 403)'
            }

            throw "Unexpected gh invocation: $command"
        }

        $result = @(Add-ReleaseAssetMetadata -Repos @((New-TestRepoMeta -Name 'CachedRelease')))
        $releaseState = Get-RestFallbackReleaseFetchState
        $cacheState = Get-ValidationCacheState

        $result[0].latestRelease.tagName | Should -Be 'v9.0.0'
        $result[0].latestRelease.releaseAssetKinds | Should -Contain 'exe'
        $releaseState.status | Should -Be 'completed'
        $releaseState.attemptedReleaseFetches | Should -Be 1
        $releaseState.successfulReleaseFetches | Should -Be 1
        $cacheState.releases.usedForFallback | Should -BeTrue
        $cacheState.releases.lastFallbackReason | Should -Match 'rate limit'
    }

    It 'uses cached link probe results without touching the network path' {
        $url = 'https://example.test/ok'
        Write-ValidationCacheEntry -Bucket links -Key (Get-LinkProbeCacheKey -Url $url) -Value ([ordered]@{
                ok = $true
                status = 204
                error = $null
                fatal = $false
            })
        $target = [ordered]@{
            repo = 'CachedLinkRepo'
            type = 'launch'
            url = $url
            host = 'example.test'
            fatalOnFailure = $true
        }

        $batch = Invoke-LinkProbeBatch -Targets @($target) -ThrottleLimit 1
        $state = Get-ValidationCacheState

        $batch.targetCount | Should -Be 1
        $batch.results | Should -HaveCount 1
        $batch.results[0].ok | Should -BeTrue
        $batch.results[0].status | Should -Be 204
        $batch.results[0].fatal | Should -BeFalse
        $state.links.hitCount | Should -Be 1
        $state.links.writeCount | Should -Be 1
    }
}

Describe 'Recoverable artifact publication' {
    It 'rolls back every injected promotion failure after a simulated restart' {
        $oldReadme = "old readme`n"
        $oldProjects = "{`"generation`":`"old`"}`n"
        $oldReport = "{`"report`":`"old`"}`n"
        $newReadme = "new readme`n"
        $newProjects = "{`"generation`":`"new`"}`n"
        $newAsset = "<svg>new</svg>`n"
        $newReport = "{`"report`":`"new`"}`n"

        foreach ($faultAfter in 1..4) {
            $caseRoot = Join-Path $TestDrive "fault-$faultAfter"
            $transactionRoot = Join-Path $caseRoot 'transactions'
            $readmePath = Join-Path $caseRoot 'README.md'
            $projectsPath = Join-Path $caseRoot 'projects.json'
            $assetPath = Join-Path $caseRoot 'asset.svg'
            $reportPath = Join-Path $caseRoot 'profile-sync-report.json'
            [System.IO.Directory]::CreateDirectory($caseRoot) | Out-Null
            [System.IO.File]::WriteAllText($readmePath, $oldReadme, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($projectsPath, $oldProjects, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($reportPath, $oldReport, [System.Text.UTF8Encoding]::new($false))

            $transaction = New-ArtifactPublicationTransaction -TransactionRoot $transactionRoot -Artifacts @(
                [ordered]@{ path = $reportPath; content = $newReport; isReport = $true }
                [ordered]@{ path = $readmePath; content = $newReadme; isReport = $false }
                [ordered]@{ path = $projectsPath; content = $newProjects; isReport = $false }
                [ordered]@{ path = $assetPath; content = $newAsset; isReport = $false }
            )

            $journal = Get-Content -LiteralPath $transaction.journalPath -Raw | ConvertFrom-Json
            $journal.artifacts | Should -HaveCount 4
            @($journal.artifacts | Where-Object { $_.oldHash }).Count | Should -Be 3
            @($journal.artifacts | Where-Object { $_.newHash }).Count | Should -Be 4

            { Publish-ArtifactPublicationTransaction -Transaction $transaction -FaultAfterPromotion $faultAfter } | Should -Throw
            if ($faultAfter -lt 4) {
                [System.IO.File]::ReadAllText($reportPath) | Should -BeExactly $oldReport
            } else {
                [System.IO.File]::ReadAllText($reportPath) | Should -BeExactly $newReport
            }

            Repair-ArtifactPublicationTransactions -TransactionRoot $transactionRoot | Should -Be 1
            [System.IO.File]::ReadAllText($readmePath) | Should -BeExactly $oldReadme
            [System.IO.File]::ReadAllText($projectsPath) | Should -BeExactly $oldProjects
            [System.IO.File]::ReadAllText($reportPath) | Should -BeExactly $oldReport
            Test-Path -LiteralPath $assetPath | Should -BeFalse
            @(Get-ChildItem -LiteralPath $caseRoot -File -Force | Where-Object { $_.Name -match '[.](stage|backup)([.]|$)' }) | Should -BeNullOrEmpty
            @(Get-ChildItem -LiteralPath $transactionRoot -File -Force) | Should -BeNullOrEmpty
        }
    }

    It 'preserves an externally updated target that this transaction never promoted' {
        $caseRoot = Join-Path $TestDrive 'external-existing-target'
        $transactionRoot = Join-Path $caseRoot 'transactions'
        $targetPath = Join-Path $caseRoot 'cache-entry.json'
        [System.IO.Directory]::CreateDirectory($caseRoot) | Out-Null
        [System.IO.File]::WriteAllText($targetPath, 'old', [System.Text.UTF8Encoding]::new($false))

        $transaction = New-ArtifactPublicationTransaction -TransactionRoot $transactionRoot -Artifacts @(
            [ordered]@{ path = $targetPath; content = 'staged'; isReport = $false }
        )
        [System.IO.File]::WriteAllText($targetPath, 'external', [System.Text.UTF8Encoding]::new($false))

        { Publish-ArtifactPublicationTransaction -Transaction $transaction } | Should -Throw '*changed after staging*'
        Repair-ArtifactPublicationTransactions -TransactionRoot $transactionRoot | Should -Be 1

        [System.IO.File]::ReadAllText($targetPath) | Should -BeExactly 'external'
        Test-Path -LiteralPath $transaction.artifacts[0].stagedPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $transactionRoot -File -Force) | Should -BeNullOrEmpty
    }

    It 'preserves an external target that appeared after a new target was staged' {
        $caseRoot = Join-Path $TestDrive 'external-new-target'
        $transactionRoot = Join-Path $caseRoot 'transactions'
        $targetPath = Join-Path $caseRoot 'cache-entry.json'
        [System.IO.Directory]::CreateDirectory($caseRoot) | Out-Null

        $transaction = New-ArtifactPublicationTransaction -TransactionRoot $transactionRoot -Artifacts @(
            [ordered]@{ path = $targetPath; content = 'staged'; isReport = $false }
        )
        [System.IO.File]::WriteAllText($targetPath, 'external', [System.Text.UTF8Encoding]::new($false))

        { Publish-ArtifactPublicationTransaction -Transaction $transaction } | Should -Throw '*appeared after staging*'
        Repair-ArtifactPublicationTransactions -TransactionRoot $transactionRoot | Should -Be 1

        [System.IO.File]::ReadAllText($targetPath) | Should -BeExactly 'external'
        Test-Path -LiteralPath $transaction.artifacts[0].stagedPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $transactionRoot -File -Force) | Should -BeNullOrEmpty
    }

    It 'allows only one profile sync process to hold the publication lock' {
        $lockPath = Join-Path $TestDrive 'profile-sync.lock'
        $firstLock = Enter-ProfileSyncRunLock -LockPath $lockPath -TimeoutSeconds 0
        try {
            { Enter-ProfileSyncRunLock -LockPath $lockPath -TimeoutSeconds 0 } |
                Should -Throw '*Another profile sync process is already running*'
        } finally {
            $firstLock.Dispose()
        }

        $secondLock = Enter-ProfileSyncRunLock -LockPath $lockPath -TimeoutSeconds 0
        $secondLock.Dispose()
    }

    It 'keeps a committed new set and removes all publication residue' {
        $caseRoot = Join-Path $TestDrive 'committed'
        $transactionRoot = Join-Path $caseRoot 'transactions'
        $existingPath = Join-Path $caseRoot 'existing.txt'
        $newPath = Join-Path $caseRoot 'new.txt'
        $reportPath = Join-Path $caseRoot 'report.json'
        [System.IO.Directory]::CreateDirectory($caseRoot) | Out-Null
        [System.IO.File]::WriteAllText($existingPath, 'old', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($reportPath, 'old report', [System.Text.UTF8Encoding]::new($false))

        $transaction = New-ArtifactPublicationTransaction -TransactionRoot $transactionRoot -Artifacts @(
            [ordered]@{ path = $reportPath; content = 'new report'; isReport = $true }
            [ordered]@{ path = $existingPath; content = 'new'; isReport = $false }
            [ordered]@{ path = $newPath; content = 'created'; isReport = $false }
        )
        Publish-ArtifactPublicationTransaction -Transaction $transaction

        $existingRows = @($transaction.artifacts | Where-Object { $_.existed })
        $newRows = @($transaction.artifacts | Where-Object { -not $_.existed })
        $existingRows | Should -HaveCount 2
        $newRows | Should -HaveCount 1
        foreach ($row in $existingRows) {
            Test-Path -LiteralPath $row.backupPath | Should -BeTrue
        }
        Test-Path -LiteralPath $newRows[0].backupPath | Should -BeFalse

        Complete-ArtifactPublicationTransaction -Transaction $transaction

        [System.IO.File]::ReadAllText($existingPath) | Should -BeExactly 'new'
        [System.IO.File]::ReadAllText($newPath) | Should -BeExactly 'created'
        [System.IO.File]::ReadAllText($reportPath) | Should -BeExactly 'new report'
        @(Get-ChildItem -LiteralPath $caseRoot -File -Force | Where-Object { $_.Name -match '[.](stage|backup)([.]|$)' }) | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $transactionRoot -File -Force) | Should -BeNullOrEmpty
    }

    It 'finishes cleanup without rolling back a committed journal after restart' {
        $caseRoot = Join-Path $TestDrive 'committed-restart'
        $transactionRoot = Join-Path $caseRoot 'transactions'
        $targetPath = Join-Path $caseRoot 'target.txt'
        [System.IO.Directory]::CreateDirectory($caseRoot) | Out-Null
        [System.IO.File]::WriteAllText($targetPath, 'old', [System.Text.UTF8Encoding]::new($false))

        $transaction = New-ArtifactPublicationTransaction -TransactionRoot $transactionRoot -Artifacts @(
            [ordered]@{ path = $targetPath; content = 'new'; isReport = $false }
        )
        Publish-ArtifactPublicationTransaction -Transaction $transaction
        $transaction.state = 'committed'
        Write-ArtifactPublicationJournal -Transaction $transaction

        Repair-ArtifactPublicationTransactions -TransactionRoot $transactionRoot | Should -Be 1
        [System.IO.File]::ReadAllText($targetPath) | Should -BeExactly 'new'
        @(Get-ChildItem -LiteralPath $caseRoot -File -Force | Where-Object { $_.Name -match '[.](stage|backup)([.]|$)' }) | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $transactionRoot -File -Force) | Should -BeNullOrEmpty
    }
}

Describe 'Repository metadata enrichment' {
    It 'keeps latestRelease out of the bulk repo-list GraphQL request' {
        $script:SyncProfileScript | Should -Match '"--json", "name,description,stargazerCount,defaultBranchRef,licenseInfo,isFork,parent,isPrivate,visibility,isArchived,repositoryTopics,pushedAt,url,primaryLanguage"'
        $script:SyncProfileScript | Should -Not -Match '"--json", "name,description,stargazerCount,defaultBranchRef,latestRelease,licenseInfo'
    }

    It 'fetches latest releases through bounded REST enrichment when GraphQL omits them' {
        $oldOffline = $script:Offline
        $oldCachePath = $script:CachePath
        $ownerVariable = Get-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
        $hadOwner = ($null -ne $ownerVariable)
        $oldOwner = if ($hadOwner) { $ownerVariable.Value } else { $null }
        $script:Offline = $false
        $script:Owner = 'SysAdminDoc'
        # Online release fetches write the validation cache; keep that out of the repo.
        $script:CachePath = Join-Path $TestDrive 'release-enrichment-cache'

        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $global:LASTEXITCODE = 0
            $command = $Arguments -join ' '
            # Transport-level API version pin is not part of what call sites assert.
            $command = ($command -replace '\s*-H X-GitHub-Api-Version: [\d-]+', '')
            if ($command -eq 'auth status -h github.com') {
                return 'Logged in to github.com'
            }
            if ($command -eq 'api repos/SysAdminDoc/HasRelease/releases/latest') {
                return (@{
                    tag_name = 'v2.0.0'
                    html_url = 'https://github.com/SysAdminDoc/HasRelease/releases/tag/v2.0.0'
                    name = 'v2.0.0'
                    published_at = '2026-06-18T12:00:00Z'
                    immutable = $true
                    assets = @(
                        @{ name = 'HasRelease.exe'; digest = 'sha256:abc123' }
                    )
                } | ConvertTo-Json -Depth 10)
            }
            if ($command -eq 'api repos/SysAdminDoc/NoRelease/releases/latest') {
                $global:LASTEXITCODE = 1
                return 'HTTP 404: Not Found'
            }
            throw "Unexpected gh invocation: $command"
        }

        try {
            $repos = @(
                (New-TestRepoMeta -Name 'HasRelease'),
                (New-TestRepoMeta -Name 'NoRelease')
            )

            $result = @(Add-ReleaseAssetMetadata -Repos $repos)
            $releaseRepo = $result | Where-Object { $_.name -eq 'HasRelease' }
            $noReleaseRepo = $result | Where-Object { $_.name -eq 'NoRelease' }
            $state = Get-RestFallbackReleaseFetchState

            $releaseRepo.latestRelease.tagName | Should -Be 'v2.0.0'
            $releaseRepo.latestRelease.releaseAssetKinds | Should -Contain 'exe'
            $releaseRepo.latestRelease.assetApiInspected | Should -BeTrue
            $noReleaseRepo.latestRelease | Should -BeNullOrEmpty
            $state.used | Should -BeTrue
            $state.status | Should -Be 'completed'
            $state.repoCount | Should -Be 2
            $state.attemptedReleaseFetches | Should -Be 2
            $state.successfulReleaseFetches | Should -Be 1
            $state.noRelease404Count | Should -Be 1
        } finally {
            $script:Offline = $oldOffline
            $script:CachePath = $oldCachePath
            if ($hadOwner) {
                $script:Owner = $oldOwner
            } else {
                Remove-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
            }
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
            Reset-RestFallbackReleaseFetchState
        }
    }

    It 'records fork-parent enrichment failure on affected repos without dropping the base list' {
        $repos = @(
            (New-TestRepoMeta -Name 'ForkMissingParent' -IsFork $true),
            (New-TestRepoMeta -Name 'RegularRepo')
        )

        $result = @(Set-ForkParentMetadataEnrichmentFailure -Repos $repos -Message 'gh api failed')

        $result | Should -HaveCount 2
        ($result | Where-Object { $_.name -eq 'ForkMissingParent' }).forkParentFetchError | Should -Match 'gh api failed'
        ($result | Where-Object { $_.name -eq 'RegularRepo' }).forkParentFetchError | Should -BeNullOrEmpty
    }

    It 'routes live repo enrichment through the fork-parent failure isolation wrapper' {
        $script:SyncProfileScript | Should -Match 'Add-LiveRepositoryMetadata -Repos \(Get-GitHubRepos\)'
        $script:SyncProfileScript | Should -Not -Match 'Add-ReleaseAssetMetadata -Repos \(Add-ForkParentMetadata -Repos \(Get-GitHubRepos\)\)'
        $script:SyncProfileScript | Should -Match 'Set-ForkParentMetadataEnrichmentFailure'
    }
}

Describe 'Test-LinkTargets batch reporting' {
    It 'summarizes transient warnings by host while keeping fatal failures separate' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $included = @($cat.entries | Where-Object {
            $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
        })
        $probe = {
            param($target)

            if ($target.type -eq 'launch') {
                return [ordered]@{ ok = $false; status = 404; error = 'missing'; fatal = $true }
            }
            return [ordered]@{ ok = $false; status = 503; error = 'busy'; fatal = $false }
        }

        $result = Test-LinkTargets -Included $included -RepoLookup @{} -ProbeScript $probe -ThrottleLimit 2

        $result.targetCount | Should -Be 4
        $result.throttleLimit | Should -Be 2
        @($result.failures) | Should -HaveCount 1
        @($result.warnings) | Should -HaveCount 3
        $result.failures[0].host | Should -Be 'sysadmindoc.github.io'

        $rawHost = @($result.warningCountByHost | Where-Object { $_.host -eq 'raw.githubusercontent.com' })
        $rawHost | Should -HaveCount 1
        $rawHost[0].count | Should -Be 3
        @($result.headerHostWarnings) | Should -HaveCount 0
    }

    It 'adds non-catalog profile links and keeps image-host outages nonfatal' {
        $readme = @'
**[View full portfolio](https://sysadmindoc.github.io/)**

```powershell
irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1 | iex
```

[`setup.ps1`](https://github.com/SysAdminDoc/SysAdminDoc/blob/main/setup.ps1)

<picture><source srcset="https://skillicons.dev/icons?i=powershell&theme=dark"><img src="https://skillicons.dev/icons?i=powershell&theme=dark" /></picture>
![Stars](https://img.shields.io/github/stars/SysAdminDoc/SysAdminDoc)
'@
        $targets = @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $readme)
        $probe = {
            param($target)

            return [ordered]@{ ok = $false; status = 404; error = 'missing'; fatal = $true }
        }

        $result = Test-LinkTargets -Included @() -RepoLookup @{} -ExtraTargets $targets -ProbeScript $probe -ThrottleLimit 2

        $targets | Should -HaveCount 5
        ($targets | Where-Object { $_.type -eq 'profile-portfolio' }).url | Should -Be 'https://sysadmindoc.github.io/'
        ($targets | Where-Object { $_.type -eq 'setup-raw' }).url | Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1'
        ($targets | Where-Object { $_.type -eq 'setup-source' }).url | Should -Be 'https://github.com/SysAdminDoc/SysAdminDoc/blob/main/setup.ps1'
        @($targets | Where-Object { $_.type -eq 'header-image' }) | Should -HaveCount 2

        @($result.failures) | Should -HaveCount 3
        @($result.warnings) | Should -HaveCount 2
        ($result.failures | ForEach-Object { $_.type }) | Should -Contain 'profile-portfolio'
        ($result.failures | ForEach-Object { $_.type }) | Should -Contain 'setup-raw'
        ($result.failures | ForEach-Object { $_.type }) | Should -Contain 'setup-source'
        ($result.warnings | ForEach-Object { $_.type } | Sort-Object -Unique) | Should -Be 'header-image'

        $headerWarnings = @($result.headerHostWarnings)
        $headerWarnings | Should -HaveCount 2
        ($headerWarnings | Where-Object { $_.host -eq 'skillicons.dev' }).count | Should -Be 1
        ($headerWarnings | Where-Object { $_.host -eq 'img.shields.io' }).count | Should -Be 1
    }

    It 'extracts rendered README install, download, and userscript action targets' {
        $readme = @'
```powershell
irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/run.ps1 | iex; Start-Tool WinTool
```

```powershell
irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/run.ps1 | iex; Start-Tool <Name>
```

[<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/MobileTool/releases/latest)
| [**ScriptTool**](https://github.com/SysAdminDoc/ScriptTool) | Browser helper | [Install](https://raw.githubusercontent.com/SysAdminDoc/ScriptTool/main/ScriptTool.user.js) |
'@
        $winTool = New-TestEntry -Repo 'WinTool' -Category 'powershell'
        # Not main, so a hard-coded branch couldn't pass: six tools really are on master.
        $winTool.entrypoint = 'Tools\Win Tool.ps1'; $winTool.branch = 'master'
        $targets = @(Get-ReadmeActionLinkValidationTargets -ExpectedReadme $readme -Entries @($winTool))

        # The "<Name>" placeholder in the setup section's example resolves to nothing.
        $targets | Should -HaveCount 4
        ($targets | ForEach-Object { $_.type } | Sort-Object) -join ',' |
            Should -Be 'readme-download,readme-install-dispatcher,readme-install-entrypoint,readme-userscript-install'
        ($targets | Where-Object { $_.type -eq 'readme-install-entrypoint' }).url |
            Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/WinTool/master/Tools/Win%20Tool.ps1'
        ($targets | Where-Object { $_.type -eq 'readme-install-dispatcher' }).url |
            Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/run.ps1'
        ($targets | Where-Object { $_.type -eq 'readme-download' }).repo | Should -Be 'MobileTool'
        ($targets | Where-Object { $_.type -eq 'readme-userscript-install' }).repo | Should -Be 'ScriptTool'
        ($targets | Where-Object { $_.group -eq 'readme-actions' }) | Should -HaveCount 4
    }

    It 'keeps README action target failures visible through link validation rows' {
        $readme = @'
```powershell
irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/run.ps1 | iex; Start-Tool WinTool
```
'@
        $winTool = New-TestEntry -Repo 'WinTool' -Category 'powershell'
        $winTool.entrypoint = 'WinTool.ps1'; $winTool.branch = 'main'
        $targets = @(Get-ReadmeActionLinkValidationTargets -ExpectedReadme $readme -Entries @($winTool))
        $probe = {
            param($target)

            return [ordered]@{ ok = $false; status = 404; error = 'missing'; fatal = $true }
        }

        $result = Test-LinkTargets -Included @() -RepoLookup @{} -ExtraTargets $targets -ProbeScript $probe -ThrottleLimit 2

        @($result.failures) | Should -HaveCount 2
        @($result.failures | ForEach-Object { $_.type } | Sort-Object) | Should -Be @('readme-install-dispatcher', 'readme-install-entrypoint')
        @($result.failures | Where-Object { $_.type -eq 'readme-install-entrypoint' })[0].url | Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/WinTool/main/WinTool.ps1'
    }
}

Describe 'Report schema depth helpers' {
    It 'classifies release trust metadata from asset filenames' {
        $assetNames = @(
            'Tool-v1.0.0.exe',
            'Tool-v1.0.0.exe.sha256',
            'Tool-v1.0.0.exe.sig',
            'Tool-v1.0.0-debug.apk',
            'sbom.spdx.json',
            'Tool-v1.0.0.intoto.jsonl'
        )

        $assetKinds = @(Get-ReleaseAssetKinds -AssetNames $assetNames)
        $trust = New-ReleaseTrust -AssetKinds $assetKinds -AssetNames $assetNames -HasRelease $true -AssetInspected $true

        $trust.checksumAssets | Should -Contain 'Tool-v1.0.0.exe.sha256'
        $trust.signatureAssets | Should -Contain 'Tool-v1.0.0.exe.sig'
        $trust.sbomAssets | Should -Contain 'sbom.spdx.json'
        $trust.attestationAvailable | Should -BeTrue
        $trust.debugArtifactPresent | Should -BeTrue
        $trust.hasChecksumForEveryExecutable | Should -BeFalse
        $trust.executableAssetKinds | Should -Contain 'exe'
        $trust.executableAssetKinds | Should -Contain 'apk'
        $trust.trustLevel | Should -Be 'signature-and-attestation-metadata'
    }

    It 'keeps release verification disabled and metadata-only by default' {
        $target = [ordered]@{
            repo = 'VerifiedTool'
            assetName = 'VerifiedTool.zip'
            assetKind = 'zip'
            assetUrl = 'https://github.com/SysAdminDoc/VerifiedTool/releases/download/v1/VerifiedTool.zip'
            assetSize = 32
            checksumAssetName = 'SHA256SUMS'
            checksumUrl = 'https://github.com/SysAdminDoc/VerifiedTool/releases/download/v1/SHA256SUMS'
            checksumSize = 80
        }

        $result = Test-ReleaseArtifactVerification -Targets @($target)

        $result.enabled | Should -BeFalse
        $result.status | Should -Be 'disabled'
        $result.failureCount | Should -Be 0
        $result.note | Should -Match 'Metadata evidence only'
    }

    It 'verifies, rejects, and skips capped release artifact candidates' {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes('release payload')
        $hash = Get-ReleaseArtifactSha256 -Bytes $bytes
        $targets = @(
            [ordered]@{
                repo = 'VerifiedTool'; assetName = 'VerifiedTool.zip'; assetKind = 'zip'; assetUrl = 'https://github.com/SysAdminDoc/VerifiedTool/releases/download/v1/VerifiedTool.zip'; assetSize = $bytes.Length; checksumAssetName = 'SHA256SUMS'; checksumUrl = 'https://github.com/SysAdminDoc/VerifiedTool/releases/download/v1/SHA256SUMS'; checksumSize = 80
            },
            [ordered]@{
                repo = 'MismatchTool'; assetName = 'MismatchTool.zip'; assetKind = 'zip'; assetUrl = 'https://github.com/SysAdminDoc/MismatchTool/releases/download/v1/MismatchTool.zip'; assetSize = $bytes.Length; checksumAssetName = 'SHA256SUMS'; checksumUrl = 'https://github.com/SysAdminDoc/MismatchTool/releases/download/v1/SHA256SUMS'; checksumSize = 80
            },
            [ordered]@{
                repo = 'TooLargeTool'; assetName = 'TooLargeTool.zip'; assetKind = 'zip'; assetUrl = 'https://github.com/SysAdminDoc/TooLargeTool/releases/download/v1/TooLargeTool.zip'; assetSize = 4096; checksumAssetName = 'SHA256SUMS'; checksumUrl = 'https://github.com/SysAdminDoc/TooLargeTool/releases/download/v1/SHA256SUMS'; checksumSize = 80
            },
            [ordered]@{
                repo = 'NoChecksumTool'; assetName = 'NoChecksumTool.zip'; assetKind = 'zip'; assetUrl = 'https://github.com/SysAdminDoc/NoChecksumTool/releases/download/v1/NoChecksumTool.zip'; assetSize = $bytes.Length; checksumAssetName = $null; checksumUrl = $null; checksumSize = $null
            },
            [ordered]@{
                repo = 'ScriptTool'; assetName = 'ScriptTool.user.js'; assetKind = 'userscript'; assetUrl = 'https://github.com/SysAdminDoc/ScriptTool/releases/download/v1/ScriptTool.user.js'; assetSize = $bytes.Length; checksumAssetName = 'SHA256SUMS'; checksumUrl = 'https://github.com/SysAdminDoc/ScriptTool/releases/download/v1/SHA256SUMS'; checksumSize = 80
            }
        )
        $download = {
            param($target, $kind)
            $text = if ($kind -eq 'checksum' -and $target.repo -eq 'VerifiedTool') { "$hash  VerifiedTool.zip" } elseif ($kind -eq 'checksum') { ('0' * 64) + "  $($target.assetName)" } else { $null }
            [ordered]@{
                ok = $true
                bytes = if ($kind -eq 'asset') { $bytes } else { [System.Text.Encoding]::UTF8.GetBytes([string]$text) }
                text = $text
                error = $null
                bytesRead = if ($kind -eq 'asset') { $bytes.Length } else { [string]$text.Length }
            }
        }

        $result = Test-ReleaseArtifactVerification -Targets $targets -Enabled -MaxAssets 10 -MaxBytes 1024 -DownloadScript $download

        $result.status | Should -Be 'failed'
        $result.verifiedCount | Should -Be 1
        $result.failureCount | Should -Be 1
        $result.skippedCount | Should -Be 3
        $result.checkedAssetCount | Should -Be 2
        ($result.rows | Where-Object { $_.repo -eq 'VerifiedTool' }).status | Should -Be 'verified'
        ($result.rows | Where-Object { $_.repo -eq 'MismatchTool' }).reason | Should -Be 'SHA-256 mismatch'
        ($result.rows | Where-Object { $_.repo -eq 'TooLargeTool' }).reason | Should -Match 'byte cap'
        ($result.rows | Where-Object { $_.repo -eq 'NoChecksumTool' }).reason | Should -Match 'checksum sidecar'
        ($result.rows | Where-Object { $_.repo -eq 'ScriptTool' }).reason | Should -Match 'allowlist'
    }

    Context 'rotation' {
        BeforeAll {
            $script:RotationBytes = [System.Text.Encoding]::UTF8.GetBytes('release payload')
            $script:RotationHash = Get-ReleaseArtifactSha256 -Bytes $script:RotationBytes
            $script:RotationTargets = @(foreach ($name in 'Echo', 'Alpha', 'Delta', 'Bravo', 'Charlie') {
                    [ordered]@{
                        repo = $name; assetName = "$name.zip"; assetKind = 'zip'; assetUrl = "https://github.com/SysAdminDoc/$name/releases/download/v1/$name.zip"; assetSize = $script:RotationBytes.Length
                        checksumAssetName = 'SHA256SUMS'; checksumUrl = "https://github.com/SysAdminDoc/$name/releases/download/v1/SHA256SUMS"; checksumSize = 80
                    }
                })
            $script:RotationDownload = {
                param($target, $kind)
                $text = if ($kind -eq 'checksum') { "$($script:RotationHash)  $($target.assetName)" } else { $null }
                [ordered]@{ ok = $true; bytes = if ($kind -eq 'asset') { $script:RotationBytes } else { [System.Text.Encoding]::UTF8.GetBytes([string]$text) }; text = $text; error = $null; bytesRead = 0 }
            }
        }

        It 'checks the slice after the one the committed report recorded, whatever the cadence' {
            # The slice used to come from the UTC week, so runs every three weeks over three
            # slices checked the same two assets forever. Each run now takes the slice after
            # the one the report recorded, handed on the way the committed report carries it.
            $start = [datetimeoffset]'2026-09-21T09:15:00Z'
            $recorded = $null
            $runs = @(foreach ($run in 0..3) {
                    $result = Test-ReleaseArtifactVerification -Targets $script:RotationTargets -Enabled -MaxAssets 2 -MaxBytes 1024 -DownloadScript $script:RotationDownload -PreviousRotation $recorded -Now $start.AddDays(21 * $run)
                    $recorded = $result.rotation | ConvertTo-Json | ConvertFrom-Json
                    $result
                })
            $checked = @($runs[0..2] | ForEach-Object { @($_.rows | Where-Object { $_.status -eq 'verified' } | ForEach-Object { $_.repo }) })

            # Three runs, slices of two in a stable order: every eligible asset once, none twice.
            (@($checked | Sort-Object) -join ',') | Should -Be 'Alpha,Bravo,Charlie,Delta,Echo'
            (@($runs | ForEach-Object { $_.rotation.sliceIndex }) -join ',') | Should -Be '0,1,2,0' -Because 'the fourth run wraps to the first slice'
            $runs[0].rotation.sliceCount | Should -Be 3
            $runs[0].rotation.eligibleCount | Should -Be 5
            $runs[1].rotation.ranAt | Should -Be '2026-10-12T09:15:00.0000000Z'
            (@($runs[0].rows | Where-Object { $_.status -eq 'skipped' } | ForEach-Object { $_.reason } | Sort-Object -Unique) -join ',') | Should -Be "outside this run's rotation slice"
        }

        It 'carries the recorded slice through a run that does not verify' {
            # Plain regenerations don't verify, and the report they commit is what the next
            # verifying run reads, so they keep the record instead of dropping it.
            $verified = Test-ReleaseArtifactVerification -Targets $script:RotationTargets -Enabled -MaxAssets 2 -MaxBytes 1024 -DownloadScript $script:RotationDownload -Now ([datetimeoffset]'2026-09-21T09:15:00Z')
            $plain = Test-ReleaseArtifactVerification -Targets $script:RotationTargets -PreviousRotation ($verified.rotation | ConvertTo-Json | ConvertFrom-Json)
            $next = Test-ReleaseArtifactVerification -Targets $script:RotationTargets -Enabled -MaxAssets 2 -MaxBytes 1024 -DownloadScript $script:RotationDownload -PreviousRotation ($plain.rotation | ConvertTo-Json | ConvertFrom-Json)

            $plain.status | Should -Be 'disabled'
            ($plain.rotation | ConvertTo-Json -Compress) | Should -Be ($verified.rotation | ConvertTo-Json -Compress)
            $next.rotation.sliceIndex | Should -Be 1
        }

        It 'starts at the first slice when the recorded rotation is <Case>' -ForEach @(
            @{ Case = 'missing'; Recorded = $null }
            @{ Case = 'the old week-based shape'; Recorded = @{ weekIndex = 37; sliceIndex = 1; sliceCount = 3; eligibleCount = 5 } }
            @{ Case = 'past the last slice'; Recorded = @{ sliceIndex = 3; sliceCount = 3; eligibleCount = 5; ranAt = '2026-09-21T09:15:00.0000000Z' } }
            @{ Case = 'negative'; Recorded = @{ sliceIndex = -1; sliceCount = 3; eligibleCount = 5; ranAt = '2026-09-21T09:15:00.0000000Z' } }
            @{ Case = 'undated'; Recorded = @{ sliceIndex = 1; sliceCount = 3; eligibleCount = 5; ranAt = 'last week' } }
        ) {
            $result = Test-ReleaseArtifactVerification -Targets $script:RotationTargets -Enabled -MaxAssets 2 -MaxBytes 1024 -DownloadScript $script:RotationDownload -PreviousRotation $Recorded
            $plain = Test-ReleaseArtifactVerification -Targets $script:RotationTargets -PreviousRotation $Recorded

            $result.rotation.sliceIndex | Should -Be 0
            $plain.rotation | Should -BeNullOrEmpty -Because 'a record the next run can''t use isn''t carried forward'
        }
    }

    It 'warns on an asset it cannot download and fails only on a checksum mismatch' {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes('release payload')
        $targets = @(foreach ($name in 'Offline', 'Mismatch') {
                [ordered]@{
                    repo = $name; assetName = "$name.zip"; assetKind = 'zip'; assetUrl = "https://github.com/SysAdminDoc/$name/releases/download/v1/$name.zip"; assetSize = $bytes.Length
                    checksumAssetName = 'SHA256SUMS'; checksumUrl = "https://github.com/SysAdminDoc/$name/releases/download/v1/SHA256SUMS"; checksumSize = 80
                }
            })
        $download = {
            param($target, $kind)
            if ($target.repo -eq 'Offline' -and $kind -eq 'asset') {
                return [ordered]@{ ok = $false; bytes = @(); text = $null; error = 'connection timed out'; bytesRead = 0 }
            }
            $text = if ($kind -eq 'checksum') { ('0' * 64) + "  $($target.assetName)" } else { $null }
            [ordered]@{ ok = $true; bytes = if ($kind -eq 'asset') { $bytes } else { [System.Text.Encoding]::UTF8.GetBytes([string]$text) }; text = $text; error = $null; bytesRead = 0 }
        }

        $unreachableOnly = Test-ReleaseArtifactVerification -Targets @($targets[0]) -Enabled -MaxAssets 4 -MaxBytes 1024 -DownloadScript $download
        $unreachableOnly.status | Should -Be 'warning'
        $unreachableOnly.failureCount | Should -Be 0
        $unreachableOnly.unreachableCount | Should -Be 1
        $unreachableOnly.rows[0].status | Should -Be 'unreachable'
        $unreachableOnly.rows[0].reason | Should -Match 'connection timed out'

        $both = Test-ReleaseArtifactVerification -Targets $targets -Enabled -MaxAssets 4 -MaxBytes 1024 -DownloadScript $download
        $both.status | Should -Be 'failed'
        $both.failureCount | Should -Be 1
        $both.unreachableCount | Should -Be 1
    }

    It 'fails on <Case>, which the network can''t explain' -ForEach @(
        @{ Case = 'an asset bigger than its published size allowed'; Kind = 'asset'; Message = 'response exceeds the configured byte cap' }
        @{ Case = 'an asset redirect the safety check refused'; Kind = 'asset'; Message = 'destination resolves to a non-public address' }
        @{ Case = 'a checksum sidecar bigger than the sidecar cap'; Kind = 'checksum'; Message = 'response exceeds the configured byte cap' }
    ) {
        $payload = [System.Text.Encoding]::UTF8.GetBytes('release payload')
        $target = [ordered]@{
            repo = 'Refused'; assetName = 'Refused.zip'; assetKind = 'zip'; assetUrl = 'https://github.com/SysAdminDoc/Refused/releases/download/v1/Refused.zip'; assetSize = $payload.Length
            checksumAssetName = 'SHA256SUMS'; checksumUrl = 'https://github.com/SysAdminDoc/Refused/releases/download/v1/SHA256SUMS'; checksumSize = 80
        }
        $script:RefusedKind = $Kind
        $script:RefusedMessage = $Message
        $download = {
            param($target, $kind)
            if ($kind -eq $script:RefusedKind) {
                return [ordered]@{ ok = $false; refused = $true; bytes = @(); text = $null; error = $script:RefusedMessage; bytesRead = 0 }
            }
            $text = if ($kind -eq 'checksum') { (Get-ReleaseArtifactSha256 -Bytes $payload) + "  $($target.assetName)" } else { $null }
            [ordered]@{ ok = $true; refused = $false; bytes = if ($kind -eq 'asset') { $payload } else { [System.Text.Encoding]::UTF8.GetBytes([string]$text) }; text = $text; error = $null; bytesRead = 0 }
        }

        $result = Test-ReleaseArtifactVerification -Targets @($target) -Enabled -MaxAssets 4 -MaxBytes 1024 -DownloadScript $download

        $result.status | Should -Be 'failed'
        $result.failureCount | Should -Be 1
        $result.unreachableCount | Should -Be 0
        $result.rows[0].reason | Should -Match "refused: $([regex]::Escape($Message))"
    }

    It 'marks a download refused only for <Case>' -ForEach @(
        @{ Case = 'a redirect the safety check turned down'; Refused = $true; Answer = @{ ok = $false; statusCode = $null; error = 'only HTTPS destinations are allowed'; policyBlocked = $true; dnsAnswerBlocked = $false } }
        @{ Case = 'a successful body over the byte cap'; Refused = $true; Answer = @{ ok = $false; statusCode = 200; error = 'response exceeds the configured byte cap'; policyBlocked = $false; byteCapExceeded = $true } }
        @{ Case = 'nothing when DNS answers with a sinkhole address'; Refused = $false; Answer = @{ ok = $false; statusCode = $null; error = 'DNS returned a non-public address for objects.githubusercontent.com'; policyBlocked = $true; dnsAnswerBlocked = $true } }
        @{ Case = 'nothing when an error page is over the byte cap'; Refused = $false; Answer = @{ ok = $false; statusCode = 503; error = 'response exceeds the configured byte cap'; policyBlocked = $false; byteCapExceeded = $true } }
        @{ Case = 'nothing when the connection times out'; Refused = $false; Answer = @{ ok = $false; statusCode = $null; error = 'connection timed out'; policyBlocked = $false } }
    ) {
        $script:DownloadAnswer = $Answer
        Mock Invoke-SafeOutboundHttpRequest { [ordered]@{ bytes = @(); text = $null; bytesRead = 0 } + $script:DownloadAnswer }

        (Get-ReleaseArtifactDownload -Url 'https://github.com/SysAdminDoc/Refused/releases/download/v1/Refused.zip' -MaxBytes 1024).refused | Should -Be $Refused
    }

    It 'checks an asset listed at <Listed> bytes with a <Served>-byte body and a sidecar for the <SidecarOf> body' -ForEach @(
        @{ Listed = 100; Served = 4000; SidecarOf = 'listed'; Status = 'failed'; Reason = 'asset download refused: the body is bigger than the 100 bytes the release lists' }
        @{ Listed = 100; Served = 100; SidecarOf = 'listed'; Status = 'verified'; Reason = $null }
        @{ Listed = 100; Served = 60; SidecarOf = 'listed'; Status = 'failed'; Reason = 'asset body is 60 bytes, but the release lists 100' }
        # A sidecar that matched the short body that was served used to verify it.
        @{ Listed = 100; Served = 60; SidecarOf = 'served'; Status = 'failed'; Reason = 'asset body is 60 bytes, but the release lists 100' }
        # One byte or none threw: an if expression unrolled the byte array.
        @{ Listed = 1; Served = 1; SidecarOf = 'served'; Status = 'verified'; Reason = $null }
        @{ Listed = 0; Served = 0; SidecarOf = 'served'; Status = 'verified'; Reason = $null }
        @{ Listed = 100; Served = 1; SidecarOf = 'served'; Status = 'failed'; Reason = 'asset body is 1 bytes, but the release lists 100' }
    ) {
        # The cap was the configured one, so a 4,000-byte body for a 100-byte asset was
        # hashed, and read verified when a sidecar matched the body that was served.
        $script:ServedBody = [byte[]]::new($Served)
        $script:SidecarBody = if ($SidecarOf -eq 'served') { $Served } else { $Listed }
        $script:ExpectedCap = [Math]::Max(1, $Listed)
        Mock Invoke-SafeOutboundHttpRequest {
            if ($Url -like '*SHA256SUMS') {
                $body = [System.Text.Encoding]::UTF8.GetBytes((Get-ReleaseArtifactSha256 -Bytes ([byte[]]::new($script:SidecarBody))) + '  Sized.zip')
            } else {
                $body = $script:ServedBody
            }
            if ($body.Length -gt $MaxBytes) {
                return [ordered]@{ ok = $false; statusCode = 200; bytes = @(); text = $null; bytesRead = [int64]$body.Length; error = 'response exceeds the configured byte cap'; byteCapExceeded = $true; policyBlocked = $false; dnsAnswerBlocked = $false }
            }
            [ordered]@{ ok = $true; statusCode = 200; bytes = $body; text = [System.Text.Encoding]::UTF8.GetString($body); bytesRead = [int64]$body.Length; error = $null; byteCapExceeded = $false; policyBlocked = $false; dnsAnswerBlocked = $false }
        }
        $target = [ordered]@{
            repo = 'Sized'; assetName = 'Sized.zip'; assetKind = 'zip'; assetUrl = 'https://github.com/SysAdminDoc/Sized/releases/download/v1/Sized.zip'; assetSize = $Listed
            checksumAssetName = 'SHA256SUMS'; checksumUrl = 'https://github.com/SysAdminDoc/Sized/releases/download/v1/SHA256SUMS'; checksumSize = 80
        }

        $result = Test-ReleaseArtifactVerification -Targets @($target) -Enabled -MaxAssets 4 -MaxBytes 1MB

        $result.rows[0].status | Should -Be $Status
        if ($Reason) { $result.rows[0].reason | Should -BeExactly $Reason }
        Should -Invoke Invoke-SafeOutboundHttpRequest -Times 1 -Exactly -ParameterFilter { $Url -like '*Sized.zip' -and $MaxBytes -eq $script:ExpectedCap }
    }

    It 'refuses a download whose redirects end at <Case>' -ForEach @(
        @{ Case = 'a public host outside GitHub''s release hosts'; FinalUrl = 'https://downloads.example/Refused.zip'; Refused = $true }
        @{ Case = 'nothing when they end on a release host'; FinalUrl = 'https://objects.githubusercontent.com/github-production-release-asset/Refused.zip'; Refused = $false }
    ) {
        # Only the first URL's host was checked, so a body from anywhere was hashed.
        $script:FinalUrlAnswer = $FinalUrl
        Mock Invoke-SafeOutboundHttpRequest { [ordered]@{ ok = $true; statusCode = 200; error = $null; finalUrl = $script:FinalUrlAnswer; redirectCount = 1; policyBlocked = $false; bytes = @([byte]1); text = 'x'; bytesRead = 1 } }

        $download = Get-ReleaseArtifactDownload -Url 'https://github.com/SysAdminDoc/Refused/releases/download/v1/Refused.zip' -MaxBytes 1024

        $download.refused | Should -Be $Refused
        if ($Refused) {
            $download.ok | Should -BeFalse
            $download.error | Should -Be 'redirected to downloads.example, outside GitHub''s release hosts'
        } else {
            $download.ok | Should -BeTrue
        }
    }

    It 'says a literal private address was named, not looked up' {
        # The refusal said DNS returned the address when no lookup had happened.
        $literal = Resolve-SafeOutboundDestination -Url 'https://10.0.0.1/asset.zip'
        $answered = Resolve-SafeOutboundDestination -Url 'https://sinkholed.example/asset.zip' -ResolveHostScript { param($HostName) @('0.0.0.0') }

        $literal.error | Should -Be 'Blocked outbound request: the URL names a non-public address, 10.0.0.1'
        $literal.dnsAnswerBlocked | Should -BeFalse
        $answered.error | Should -Be 'Blocked outbound request: DNS returned a non-public address for sinkholed.example'
        $answered.dnsAnswerBlocked | Should -BeTrue
    }

    It 'refuses a download from a host outside GitHub''s release hosts' {
        (Get-ReleaseArtifactDownload -Url 'https://downloads.example/Refused.zip' -MaxBytes 1024).refused | Should -BeTrue
    }

    It 'skips a checksum sidecar published over its cap instead of downloading it' {
        $script:DownloadCalls = 0
        $target = [ordered]@{
            repo = 'BigSums'; assetName = 'BigSums.zip'; assetKind = 'zip'; assetUrl = 'https://github.com/SysAdminDoc/BigSums/releases/download/v1/BigSums.zip'; assetSize = 100
            checksumAssetName = 'SHA256SUMS'; checksumUrl = 'https://github.com/SysAdminDoc/BigSums/releases/download/v1/SHA256SUMS'; checksumSize = 300KB
        }

        $result = Test-ReleaseArtifactVerification -Targets @($target) -Enabled -MaxAssets 4 -MaxBytes 1MB -DownloadScript { $script:DownloadCalls++ }

        $result.rows[0].status | Should -Be 'skipped'
        $result.rows[0].reason | Should -Be 'checksum sidecar exceeds the sidecar cap'
        $result.failureCount | Should -Be 0
        $script:DownloadCalls | Should -Be 0
    }

    It 'counts release digests the same after a cache round trip' {
        # A cache read returns the digests as an ordered dictionary, and both readers kept only
        # a hashtable, so a run on cached metadata published zero digests for every release.
        $repo = New-TestRepoMeta -Name 'WinTool' -WithRelease -AssetNames @('WinTool.zip', 'WinTool.exe')
        Set-MemberValue -Object $repo.latestRelease -Name 'releaseAssetDigests' -Value @{ 'WinTool.zip' = 'sha256:' + ('a' * 64); 'WinTool.exe' = 'sha256:' + ('b' * 64) }
        $saved = @{
            CachePath = $script:CachePath; CacheEnabled = $script:CacheEnabled; MetadataSnapshotAt = $script:MetadataSnapshotAt
            Provider = $script:RepositoryMetadataProvider; RequestedLimit = $script:RepositoryEnumerationRequestedLimit; Truncated = $script:RepositoryEnumerationTruncated
        }
        try {
            $script:CachePath = Join-Path $TestDrive 'digest-round-trip-cache'
            $script:CacheEnabled = $true
            $script:MetadataSnapshotAt = (Get-Date).ToUniversalTime().ToString('o')
            $script:RepositoryMetadataProvider = 'graphql'
            $script:RepositoryEnumerationRequestedLimit = 25
            $script:RepositoryEnumerationTruncated = $false
            Reset-ValidationCacheState
            Write-CompleteGenerationSnapshot -Repos @($repo) -ReleaseMetadataComplete:$true | Should -BeTrue
            Reset-ValidationCacheState
            $cachedRepos = @(Get-MemberValue -Object (Get-CompleteGenerationSnapshot) -Name 'repositories')
        } finally {
            $script:CachePath = $saved.CachePath
            $script:CacheEnabled = $saved.CacheEnabled
            $script:MetadataSnapshotAt = $saved.MetadataSnapshotAt
            $script:RepositoryMetadataProvider = $saved.Provider
            $script:RepositoryEnumerationRequestedLimit = $saved.RequestedLimit
            $script:RepositoryEnumerationTruncated = $saved.Truncated
            Reset-ValidationCacheState
        }
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')

        $liveFeed = New-ProjectsExportJson -Catalog $catalog -Repos @($repo) | ConvertFrom-Json
        $cachedFeed = New-ProjectsExportJson -Catalog $catalog -Repos $cachedRepos | ConvertFrom-Json
        $liveDrift = Test-ReleaseAssetDrift -Entries @($catalog.entries) -RepoLookup (ConvertTo-Lookup @($repo))
        $cachedDrift = Test-ReleaseAssetDrift -Entries @($catalog.entries) -RepoLookup (ConvertTo-Lookup $cachedRepos)

        @($liveFeed.projects | Where-Object { $_.repo -eq 'WinTool' })[0].releaseTrust.platformDigestCount | Should -Be 2
        @($cachedFeed.projects | Where-Object { $_.repo -eq 'WinTool' })[0].releaseTrust.platformDigestCount | Should -Be 2
        $cachedDrift.platformDigestCoverage.withDigestCount | Should -Be $liveDrift.platformDigestCoverage.withDigestCount
        $cachedDrift.platformDigestCoverage.withDigestCount | Should -BeGreaterThan 0
    }

    It 'derives verification targets only from capped asset classes with checksum candidates' {
        $entry = New-TestEntry -Repo 'VerifiedTool' -Category 'desktop'
        $repo = New-TestRepoMeta -Name 'VerifiedTool' -WithRelease -AssetNames @('VerifiedTool.zip', 'SHA256SUMS')
        Set-MemberValue -Object $repo.latestRelease -Name 'releaseAssets' -Value @(
            [pscustomobject]@{ name = 'VerifiedTool.zip'; browserDownloadUrl = 'https://github.com/SysAdminDoc/VerifiedTool/releases/download/v1/VerifiedTool.zip'; size = 12 },
            [pscustomobject]@{ name = 'SHA256SUMS'; browserDownloadUrl = 'https://github.com/SysAdminDoc/VerifiedTool/releases/download/v1/SHA256SUMS'; size = 80 },
            [pscustomobject]@{ name = 'VerifiedTool.user.js'; browserDownloadUrl = 'https://github.com/SysAdminDoc/VerifiedTool/releases/download/v1/VerifiedTool.user.js'; size = 12 }
        )

        $targets = @(Get-ReleaseArtifactVerificationTargets -Entries @($entry) -RepoLookup (ConvertTo-Lookup @($repo)))

        $targets | Should -HaveCount 1
        $targets[0].assetName | Should -Be 'VerifiedTool.zip'
        $targets[0].checksumAssetName | Should -Be 'SHA256SUMS'
    }

    It 'reports repos missing topics or public descriptions' {
        $noTopicsEntry = New-TestEntry -Repo 'NoTopics' -Category 'powershell' -Description 'Catalog Windows utility'
        $noDescriptionEntry = New-TestEntry -Repo 'NoDescription' -Category 'web' -Description 'Catalog web dashboard'
        $suppressedEntry = New-TestEntry -Repo 'SuppressedGap' -Category 'suppressed' -Description ''
        $repos = @(
            (New-TestRepoMeta -Name 'NoTopics' -Topics @() -Description 'has description'),
            (New-TestRepoMeta -Name 'NoDescription' -Topics @('windows') -Description ''),
            (New-TestRepoMeta -Name 'SuppressedGap' -Topics @() -Description ''),
            (New-TestRepoMeta -Name 'PrivateGap' -Topics @() -Description '' -Language 'PowerShell' | ForEach-Object {
                    $_.isPrivate = $true
                    $_.visibility = 'PRIVATE'
                    $_
                }),
            (New-TestRepoMeta -Name 'CompleteRepo' -Topics @('windows') -Description 'ready')
        )

        $result = Test-MetadataHygiene -Repos $repos -CatalogEntries @($noTopicsEntry, $noDescriptionEntry, $suppressedEntry) -OwnerName 'SysAdminDoc'

        $result.missingTopicCount | Should -Be 3
        $result.publicMissingTopicCount | Should -Be 1
        $result.redactedTopicCount | Should -Be 2
        $result.suppressedTopicCount | Should -Be 1
        $result.unsafeOrPrivateTopicCount | Should -Be 1
        ($result.missingTopics | ForEach-Object { $_.repo }) | Should -Contain 'NoTopics'
        ($result.missingTopics | ForEach-Object { $_.repo }) | Should -Not -Contain 'SuppressedGap'
        ($result.missingTopics | ForEach-Object { $_.repo }) | Should -Not -Contain 'PrivateGap'
        $result.missingTopics[0].category | Should -Be 'powershell'
        $result.missingTopics[0].topicHints | Should -Contain 'powershell'
        $result.missingTopics[0].topicHints | Should -Contain 'windows'
        $result.topicHintPolicy.requiresExplicitAllowlist | Should -BeTrue
        $result.topicHintPolicy.mutatesRepositories | Should -BeFalse
        # -ApplyTopics is implemented and the committed allowlist is populated, so the
        # report must not claim the capability is unavailable.
        $result.topicHintPolicy.applyModeAvailable | Should -BeTrue
        $result.topicHintPolicy.allowlistedRepositoryCount | Should -Be 12
        $result.topicHintPolicy.applyModeUnavailableReason | Should -BeNullOrEmpty
        $result.missingDescriptionCount | Should -Be 3
        $result.publicMissingDescriptionCount | Should -Be 1
        $result.redactedDescriptionCount | Should -Be 2
        $result.suppressedDescriptionCount | Should -Be 1
        $result.unsafeOrPrivateDescriptionCount | Should -Be 1
        ($result.missingDescriptions | ForEach-Object { $_.repo }) | Should -Contain 'NoDescription'
        ($result.missingDescriptions | ForEach-Object { $_.repo }) | Should -Not -Contain 'SuppressedGap'
        ($result.missingDescriptions | ForEach-Object { $_.repo }) | Should -Not -Contain 'PrivateGap'
        $result.missingDescriptions[0].catalogDescription | Should -Be 'Catalog web dashboard'
        $result.handoff.status | Should -Be 'actionable'
        $result.handoff.topicRows[0].repo | Should -Be 'NoTopics'
        $result.handoff.topicRows[0].command | Should -Be 'gh repo edit SysAdminDoc/NoTopics --add-topic powershell --add-topic windows --add-topic sysadmin'
        $result.handoff.descriptionRows[0].repo | Should -Be 'NoDescription'
        $result.handoff.descriptionRows[0].command | Should -Be "gh repo edit SysAdminDoc/NoDescription --description 'Catalog web dashboard'"
        $result.handoff.excludedSuppressedTopicCount | Should -Be 1
        $result.handoff.excludedSuppressedDescriptionCount | Should -Be 1
        $result.handoff.excludedUnsafeOrPrivateTopicCount | Should -Be 1
        $result.handoff.excludedUnsafeOrPrivateDescriptionCount | Should -Be 1
        ($result.handoff | ConvertTo-Json -Depth 10) | Should -Not -Match 'SuppressedGap|PrivateGap'
    }

    It 'falls back to a generic topic hint when catalog and language signals are empty' {
        $repos = @(
            (New-TestRepoMeta -Name 'NoSignals' -Topics @() -Description '' -Language $null)
        )

        $result = Test-MetadataHygiene -Repos $repos -CatalogEntries @()

        $result.missingTopics[0].topicHints | Should -Contain 'utility'
    }

    It 'summarizes visitor-facing project license metadata gaps' {
        $webTool = New-TestEntry -Repo 'AWebTool' -Category 'web'
        $winTool = New-TestEntry -Repo 'BWinTool' -Category 'powershell'
        $apiTool = New-TestEntry -Repo 'CApiTool' -Category 'web'
        $pyTool = New-TestEntry -Repo 'DPyTool' -Category 'python'
        $customFork = New-TestEntry -Repo 'ECustomFork' -Category 'misc'
        $customFork.upstreamLicense = 'Other'
        $sourceAvailable = New-TestEntry -Repo 'FSourceAvailable' -Category 'web'
        $sourceAvailable.notes = 'Intentional Business Source License 1.1; GitHub reports it as Other.'
        $repos = @(
            (New-TestRepoMeta -Name 'AWebTool' -LicenseInfo ([pscustomobject]@{ key = 'other'; name = 'Other' })),
            (New-TestRepoMeta -Name 'BWinTool' -LicenseInfo ([pscustomobject]@{ key = 'mit'; name = 'MIT License' })),
            (New-TestRepoMeta -Name 'CApiTool' -LicenseInfo ([pscustomobject]@{ key = 'apache-2.0'; name = 'Apache License 2.0' })),
            (New-TestRepoMeta -Name 'DPyTool' -LicenseInfo $null),
            (New-TestRepoMeta -Name 'ECustomFork' -LicenseInfo ([pscustomobject]@{ key = 'other'; name = 'Other' })),
            (New-TestRepoMeta -Name 'FSourceAvailable' -LicenseInfo ([pscustomobject]@{ key = 'other'; name = 'Other' }))
        )
        $lookup = ConvertTo-Lookup $repos

        $result = Test-ProjectLicenseMetadata -Entries @($webTool, $winTool, $apiTool, $pyTool, $customFork, $sourceAvailable) -RepoLookup $lookup

        $result.checkedCount | Should -Be 6
        $result.detectedCount | Should -Be 5
        $result.missingCount | Should -Be 1
        $result.unknownCount | Should -Be 3
        $result.intentionalExceptionCount | Should -Be 2
        $result.unresolvedUnknownCount | Should -Be 1
        $result.warningCount | Should -Be 2
        ($result.missingLicenses | ForEach-Object { $_.repo }) | Should -Contain 'DPyTool'
        ($result.unknownLicenses | ForEach-Object { $_.repo }) | Should -Contain 'AWebTool'
        ($result.unknownLicenses | Where-Object { $_.repo -eq 'AWebTool' }).intentionalException | Should -BeFalse
        ($result.unknownLicenses | Where-Object { $_.repo -eq 'ECustomFork' }).intentionalException | Should -BeTrue
        ($result.unknownLicenses | Where-Object { $_.repo -eq 'ECustomFork' }).exceptionReason | Should -Match 'upstream license'
        ($result.unknownLicenses | Where-Object { $_.repo -eq 'FSourceAvailable' }).intentionalException | Should -BeTrue
        ($result.unknownLicenses | Where-Object { $_.repo -eq 'FSourceAvailable' }).exceptionReason | Should -Match 'Business Source License'
        (($result.licenseCounts | ForEach-Object { $_.licenseSpdxId }) -join ',') | Should -Be 'Apache-2.0,MIT,NOASSERTION'
        ($result.licenseCounts | Where-Object { $_.licenseSpdxId -eq 'MIT' }).count | Should -Be 1
        ($result.licenseCounts | Where-Object { $_.licenseSpdxId -eq 'NOASSERTION' }).licenseKey | Should -Be 'other'
        ($result.licenseCounts | Where-Object { $_.licenseSpdxId -eq 'NOASSERTION' }).count | Should -Be 3
    }

    It 'classifies GitHub fork parents against catalog attribution' {
        $match = New-TestEntry -Repo 'MatchingFork' -Category 'desktop'
        $match.forkOf = 'Upstream/MatchingFork'
        $continuation = New-TestEntry -Repo 'ContinuationOnly' -Category 'extensions'
        $continuation.forkOf = 'Upstream/ContinuationOnly'
        $missing = New-TestEntry -Repo 'MissingAttribution' -Category 'guides'
        $mismatch = New-TestEntry -Repo 'MismatchedFork' -Category 'desktop'
        $mismatch.forkOf = 'Catalog/WrongParent'
        $unavailable = New-TestEntry -Repo 'ParentUnavailable' -Category 'desktop'
        $suppressedFork = New-TestEntry -Repo 'HiddenFork' -Category 'suppressed'
        $suppressedFork.forkOf = 'Upstream/HiddenFork'
        $repos = @(
            (New-TestRepoMeta -Name 'MatchingFork' -IsFork $true -Parent ([pscustomobject]@{ nameWithOwner = 'Upstream/MatchingFork' })),
            (New-TestRepoMeta -Name 'ContinuationOnly' -IsFork $false),
            (New-TestRepoMeta -Name 'MissingAttribution' -IsFork $true -Parent ([pscustomobject]@{ nameWithOwner = 'Upstream/MissingAttribution' })),
            (New-TestRepoMeta -Name 'MismatchedFork' -IsFork $true -Parent ([pscustomobject]@{ nameWithOwner = 'GitHub/ActualParent' })),
            (New-TestRepoMeta -Name 'ParentUnavailable' -IsFork $true -ForkParentFetchError 'api unavailable'),
            (New-TestRepoMeta -Name 'HiddenFork' -IsFork $true -Parent ([pscustomobject]@{ nameWithOwner = 'Upstream/HiddenFork' }))
        )

        $result = Test-ForkParentDrift -Repos $repos -CatalogEntries @($match, $continuation, $missing, $mismatch, $unavailable, $suppressedFork)

        $result.checkedCount | Should -Be 6
        $result.githubForkCount | Should -Be 5
        $result.catalogForkOfCount | Should -Be 4
        $result.matchingGitHubForkCount | Should -Be 2
        $result.catalogContinuationCount | Should -Be 1
        $result.missingCatalogAttributionCount | Should -Be 2
        $result.parentMismatchCount | Should -Be 1
        $result.parentUnavailableCount | Should -Be 1
        $result.warningCount | Should -Be 4
        $result.publicDetailRowCount | Should -Be 6
        $result.redactedDetailRowCount | Should -Be 1
        ($result.matchingGitHubForks | ForEach-Object { $_.repo }) | Should -Contain 'MatchingFork'
        ($result.matchingGitHubForks | ForEach-Object { $_.repo }) | Should -Not -Contain 'HiddenFork'
        ($result.catalogContinuations | ForEach-Object { $_.repo }) | Should -Contain 'ContinuationOnly'
        ($result.missingCatalogAttribution | ForEach-Object { $_.repo }) | Should -Contain 'MissingAttribution'
        ($result.parentMismatches | ForEach-Object { $_.repo }) | Should -Contain 'MismatchedFork'
        ($result.parentUnavailable | ForEach-Object { $_.repo }) | Should -Contain 'ParentUnavailable'
        ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'HiddenFork'
    }

    It 'reports stale and archive review candidates without exposing suppressed names' {
        $current = New-TestEntry -Repo 'CurrentTool' -Category 'powershell'
        $stale = New-TestEntry -Repo 'StaleTool' -Category 'python'
        $oldRelease = New-TestEntry -Repo 'OldReleaseTool' -Category 'desktop'
        $archive = New-TestEntry -Repo 'ArchiveCandidate' -Category 'guides'
        $suppressedPrivate = New-TestEntry -Repo 'AHiddenPrivate' -Category 'suppressed'
        $suppressedPrivate.suppressionReason = 'Repo is private; public profile links would 404 for visitors.'
        $suppressedVisitor = New-TestEntry -Repo 'MHiddenVisitor' -Category 'suppressed'
        $suppressedVisitor.suppressionReason = 'Not visitor-facing.'
        $suppressedDuplicate = New-TestEntry -Repo 'ZHiddenDuplicate' -Category 'suppressed'
        $suppressedDuplicate.suppressionReason = 'Renamed duplicate profile entry.'
        $repos = @(
            (New-TestRepoMeta -Name 'CurrentTool' -PushedAt '2026-06-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'StaleTool' -PushedAt '2025-10-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'OldReleaseTool' -WithRelease -PushedAt '2026-06-01T00:00:00Z' -ReleasePublishedAt '2024-01-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'ArchiveCandidate' -PushedAt '2023-01-01T00:00:00Z')
        )
        $lookup = ConvertTo-Lookup $repos

        $result = Test-StaleProjectReview `
            -Entries @($current, $stale, $oldRelease, $archive, $suppressedPrivate, $suppressedVisitor, $suppressedDuplicate) `
            -RepoLookup $lookup `
            -Now ([datetimeoffset]'2026-06-06T00:00:00Z')

        $result.checkedProjectCount | Should -Be 4
        $result.staleAfterDays | Should -Be 186
        $result.releaseStaleAfterDays | Should -Be 540
        $result.archiveAfterDays | Should -Be 365
        $result.staleProjectCount | Should -Be 3
        $result.archiveReviewCount | Should -Be 1
        $result.noReleaseCount | Should -Be 3
        $result.suppressedCount | Should -Be 3
        $result.warningCount | Should -Be 3
        ($result.rows | ForEach-Object { $_.repo }) | Should -Contain 'StaleTool'
        ($result.rows | ForEach-Object { $_.repo }) | Should -Contain 'OldReleaseTool'
        ($result.rows | ForEach-Object { $_.repo }) | Should -Contain 'ArchiveCandidate'
        ($result.rows | Where-Object { $_.repo -eq 'OldReleaseTool' }).signals | Should -Contain 'release-stale'
        ($result.rows | Where-Object { $_.repo -eq 'ArchiveCandidate' }).status | Should -Be 'archive-review'
        (($result.suppressionReasonCounts | ForEach-Object { $_.reasonCode }) -join ',') | Should -Be 'duplicate-or-superseded,not-visitor-facing,private-or-sensitive'
        ($result.suppressionReasonCounts | ForEach-Object { $_.reasonCode }) | Should -Contain 'private-or-sensitive'
        ($result.suppressionReasonCounts | ForEach-Object { $_.reasonCode }) | Should -Contain 'duplicate-or-superseded'
        ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'AHiddenPrivate|MHiddenVisitor|ZHiddenDuplicate'
    }

    It 'judges an entry with a review-by date by that date alone' {
        # The age thresholds couldn't fire for an actively maintained portfolio, so the report
        # had no signal; a promised review date gives it one. The overdue entry was pushed
        # days ago, and the scheduled one years ago.
        $overdue = New-TestEntry -Repo 'OverdueTool' -Category 'powershell'
        $overdue.reviewBy = '2026-05-01'
        $scheduled = New-TestEntry -Repo 'ScheduledTool' -Category 'python'
        $scheduled.reviewBy = '2026-12-31'
        $current = New-TestEntry -Repo 'CurrentTool' -Category 'desktop'
        $lookup = ConvertTo-Lookup @(
            (New-TestRepoMeta -Name 'OverdueTool' -PushedAt '2026-06-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'ScheduledTool' -PushedAt '2020-01-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'CurrentTool' -PushedAt '2026-06-01T00:00:00Z')
        )

        $result = Test-StaleProjectReview -Entries @($overdue, $scheduled, $current) -RepoLookup $lookup -Now ([datetimeoffset]'2026-06-06T00:00:00Z')

        $result.warningCount | Should -Be 1
        $result.reviewByCount | Should -Be 2
        $result.reviewOverdueCount | Should -Be 1
        $result.reviewScheduledCount | Should -Be 1
        @($result.rows | ForEach-Object { $_.repo }) | Should -BeOrdinal 'OverdueTool'
        @($result.rows[0].signals) | Should -BeOrdinal 'review-overdue'
        $result.rows[0].reviewBy | Should -BeOrdinal '2026-05-01'
        $result.rows[0].status | Should -BeOrdinal 'stale-review'
    }

    It 'counts a review-by date as due, not overdue, on the day itself' {
        $entry = New-TestEntry -Repo 'DueTool' -Category 'powershell'
        $entry.reviewBy = '2026-06-06'
        $lookup = ConvertTo-Lookup @((New-TestRepoMeta -Name 'DueTool' -PushedAt '2020-01-01T00:00:00Z'))

        $result = Test-StaleProjectReview -Entries @($entry) -RepoLookup $lookup -Now ([datetimeoffset]'2026-06-06T12:00:00Z')

        $result.warningCount | Should -Be 0
        $result.reviewScheduledCount | Should -Be 1
    }

    It 'takes reviewBy only as a YYYY-MM-DD date: <Case>' -ForEach @(
        @{ Case = 'a date'; Value = '2026-06-01'; Valid = $true }
        @{ Case = 'left out'; Value = $null; Valid = $true }
        @{ Case = 'not a real date'; Value = '2026-13-01'; Valid = $false }
        @{ Case = 'slashes'; Value = '2026/06/01'; Valid = $false }
        @{ Case = 'a trailing space'; Value = '2026-06-01 '; Valid = $false }
        @{ Case = 'a number'; Value = 20260601; Valid = $false }
    ) {
        $entry = New-TestEntry -Repo 'DateTool' -Category 'powershell'
        $entry.reviewBy = $Value

        $issues = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq 'reviewBy' })
        $schema = Test-JsonSchemaContract -Value (ConvertFrom-JsonPreservingArrays -Json (@{ entries = @($entry) } | ConvertTo-Json -Depth 10)) -SchemaPath 'schemas/profile-catalog.v1.json'
        $schemaIssues = @($schema.errors | Where-Object { [string]$_.instanceLocation -match 'reviewBy' })

        $issues.Count -eq 0 | Should -Be $Valid
        $schemaIssues.Count -eq 0 | Should -Be $Valid
    }

    It 'normalizes C++ language topic hints to cpp' {
        $hints = Get-TopicHints -Repo 'CppTool' -Language 'C++' -Entry $null -Description ''

        $hints | Should -Contain 'cpp'
        $hints | Should -Not -Contain 'cplusplus'
    }

    It 'reports release/download action drift from current catalog metadata' {
        $missingRelease = New-TestEntry -Repo 'MissingRelease' -Category 'android'
        $missingRelease.downloadKind = 'apk'
        $sourceOnly = New-TestEntry -Repo 'SourceOnly' -Category 'desktop'
        $sourceOnly.downloadKind = 'repo'
        $userscriptMissingUrl = New-TestEntry -Repo 'ScriptNoUrl' -Category 'extensions'
        $userscriptMissingUrl.downloadKind = 'userscript'
        $goodRelease = New-TestEntry -Repo 'GoodRelease' -Category 'android'
        $goodRelease.downloadKind = 'apk'
        $mismatchRelease = New-TestEntry -Repo 'MismatchRelease' -Category 'android'
        $mismatchRelease.downloadKind = 'exe'
        $sourceArchiveRelease = New-TestEntry -Repo 'SourceArchiveRelease' -Category 'desktop'
        $sourceArchiveRelease.downloadKind = 'zip'

        $repos = @(
            (New-TestRepoMeta -Name 'MissingRelease'),
            (New-TestRepoMeta -Name 'SourceOnly' -WithRelease),
            (New-TestRepoMeta -Name 'ScriptNoUrl'),
            (New-TestRepoMeta -Name 'GoodRelease' -WithRelease -AssetNames @('GoodRelease-v1.0.0.apk', 'GoodRelease-v1.0.0.apk.sha256')),
            (New-TestRepoMeta -Name 'MismatchRelease' -WithRelease -AssetNames @('MismatchRelease-v1.0.0.apk')),
            (New-TestRepoMeta -Name 'SourceArchiveRelease' -WithRelease)
        )
        $lookup = ConvertTo-Lookup $repos

        $result = Test-ReleaseAssetDrift -Entries @($missingRelease, $sourceOnly, $userscriptMissingUrl, $goodRelease, $mismatchRelease, $sourceArchiveRelease) -RepoLookup $lookup

        $result.checkedCatalogRows | Should -Be 6
        $result.releaseBearingRows | Should -Be 4
        $result.releaseActionRows | Should -Be 2
        $result.inspectedReleaseRows | Should -Be 4
        ($result.missingReleaseForDownloadKind | ForEach-Object { $_.repo }) | Should -Contain 'MissingRelease'
        ($result.sourceOnlyWithRelease | ForEach-Object { $_.repo }) | Should -Contain 'SourceOnly'
        ($result.sourceOnlyWithRelease[0].releaseAssetKinds) | Should -Contain 'source-archive'
        ($result.releaseAssetKindMismatches | ForEach-Object { $_.repo }) | Should -Contain 'MismatchRelease'
        ($result.releaseAssetKindMismatches | ForEach-Object { $_.repo }) | Should -Contain 'SourceArchiveRelease'
        ($result.userscriptKindWithoutInstallUrl | ForEach-Object { $_.repo }) | Should -Contain 'ScriptNoUrl'
        ($result.executableDownloadsMissingChecksums | ForEach-Object { $_.repo }) | Should -Contain 'MismatchRelease'
        ($result.executableDownloadsMissingChecksums | ForEach-Object { $_.repo }) | Should -Not -Contain 'GoodRelease'
        (($result.releaseAssetKindCounts | ForEach-Object { $_.kind }) -join ',') | Should -Be 'apk,other,source-archive'
        (($result.releaseTrustLevelCounts | ForEach-Object { $_.trustLevel }) -join ',') | Should -Be 'checksum-metadata,metadata-only,unknown'
        ($result.releaseTrustLevelCounts | Where-Object { $_.trustLevel -eq 'checksum-metadata' }).count | Should -Be 1
        $result.assetApiInspected | Should -BeTrue

        $shortlist = $result.executableDownloadTrustShortlist
        $shortlist.evidenceSource | Should -Be 'release-metadata-only'
        $shortlist.executableDownloadCount | Should -Be 2
        $shortlist.metadataCompleteCount | Should -Be 0
        $shortlist.checksumGapCount | Should -Be 1
        $shortlist.attestationGapCount | Should -Be 2
        $shortlist.sbomGapCount | Should -Be 2
        # Highest evidence gap is ranked first. A missing checksum weighs 2 because it is
        # the cheapest real integrity win; a mutable release and a missing SBOM weigh 1
        # each. Attestation is excluded from scoring entirely: it needs a GitHub Actions
        # OIDC token, which this repository will never have.
        $shortlist.rows[0].repo | Should -Be 'MismatchRelease'
        $shortlist.rows[0].priorityRank | Should -Be 1
        $shortlist.rows[0].gapScore | Should -Be 4
        $shortlist.rows[0].nextAction | Should -Be 'publish-sha256-checksums'
        ($shortlist.rows | Where-Object { $_.repo -eq 'GoodRelease' }).hasChecksum | Should -BeTrue
        ($shortlist.rows | Where-Object { $_.repo -eq 'GoodRelease' }).nextAction | Should -Be 'enable-immutable-releases'
        $shortlist.attestationAchievable | Should -BeFalse

        # Field parity against the report schema so live schema validation stays green.
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $shortlistDef = $schema.'$defs'.executableDownloadTrustShortlist
        $aggregateKeys = @($shortlist.Keys) | Sort-Object
        $schemaAggregateKeys = @($shortlistDef.properties.PSObject.Properties.Name) | Sort-Object
        ($aggregateKeys -join ',') | Should -Be ($schemaAggregateKeys -join ',')
        $rowKeys = @($shortlist.rows[0].Keys) | Sort-Object
        $schemaRowKeys = @($shortlistDef.properties.rows.items.properties.PSObject.Properties.Name) | Sort-Object
        ($rowKeys -join ',') | Should -Be ($schemaRowKeys -join ',')
    }

    It 'reports userscript metadata trust gaps from raw install headers' {
        $broad = New-TestEntry -Repo 'BroadScript' -Category 'extensions'
        $broad.downloadKind = 'userscript'
        $broad.userscriptUrl = 'https://raw.githubusercontent.com/SysAdminDoc/BroadScript/main/BroadScript.user.js'
        $scoped = New-TestEntry -Repo 'ScopedScript' -Category 'extensions'
        $scoped.downloadKind = 'userscript'
        $scoped.userscriptUrl = 'https://raw.githubusercontent.com/SysAdminDoc/ScopedScript/v1.2.3/ScopedScript.user.js'
        $contentByUrl = @{
            $broad.userscriptUrl = @'
// ==UserScript==
// @name        Broad Script
// @version     1.0.0
// @match       *://*/*
// @grant       GM_xmlhttpRequest
// ==/UserScript==
'@
            $scoped.userscriptUrl = @'
// ==UserScript==
// @name        Scoped Script
// @version     1.2.3
// @match       https://example.com/*
// @updateURL   https://raw.githubusercontent.com/SysAdminDoc/ScopedScript/v1.2.3/ScopedScript.meta.js
// @downloadURL https://raw.githubusercontent.com/SysAdminDoc/ScopedScript/v1.2.3/ScopedScript.user.js
// @grant       none
// ==/UserScript==
'@
        }
        $probeByUrl = @{
            'https://raw.githubusercontent.com/SysAdminDoc/ScopedScript/v1.2.3/ScopedScript.meta.js' = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
            'https://raw.githubusercontent.com/SysAdminDoc/ScopedScript/v1.2.3/ScopedScript.user.js' = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
        }

        $result = Test-UserscriptInstallTrust -Entries @($broad, $scoped) -ContentByUrl $contentByUrl -ProbeByUrl $probeByUrl

        $result.checkedCount | Should -Be 2
        $result.rawGitHubCount | Should -Be 2
        $result.branchSourceCount | Should -Be 1
        $result.tagOrCommitSourceCount | Should -Be 1
        $result.metadataBlockCount | Should -Be 2
        $result.broadScopeCount | Should -Be 1
        $result.missingUpdateUrlCount | Should -Be 1
        $result.missingDownloadUrlCount | Should -Be 1
        $result.warningCount | Should -Be 3
        $result.fatalCount | Should -Be 0
        $result.updateUrlProbeFailureCount | Should -Be 0
        $result.downloadUrlProbeFailureCount | Should -Be 0
        $result.updateUrlRefMismatchCount | Should -Be 0
        $result.downloadUrlRefMismatchCount | Should -Be 0
        $broadRow = $result.rows | Where-Object { $_.repo -eq 'BroadScript' }
        $broadRow.name | Should -Be 'Broad Script'
        $broadRow.sourceRef | Should -Be 'main'
        $broadRow.sourceRefType | Should -Be 'branch'
        $broadRow.fatalCount | Should -Be 0
        ($broadRow.warnings | ForEach-Object { $_.kind }) | Should -Contain 'scope-broad'
        ($broadRow.warnings | ForEach-Object { $_.kind }) | Should -Contain 'update-url-missing'
        ($broadRow.warnings | ForEach-Object { $_.kind }) | Should -Contain 'download-url-missing'
        @($broadRow.warnings | Where-Object { $_.fatal }).Count | Should -Be 0
        $scopedRow = $result.rows | Where-Object { $_.repo -eq 'ScopedScript' }
        $scopedRow.sourceRefType | Should -Be 'tag'
        $scopedRow.updateUrlSourceRef | Should -Be 'v1.2.3'
        $scopedRow.updateUrlRefMatchesSource | Should -BeTrue
        $scopedRow.updateUrlProbeSucceeded | Should -BeTrue
        $scopedRow.updateUrlProbeStatusCode | Should -Be 200
        $scopedRow.downloadUrlSourceRef | Should -Be 'v1.2.3'
        $scopedRow.downloadUrlRefMatchesSource | Should -BeTrue
        $scopedRow.downloadUrlProbeSucceeded | Should -BeTrue
        $scopedRow.downloadUrlProbeStatusCode | Should -Be 200
        $scopedRow.warningCount | Should -Be 0

        # Release-channel readiness classifier (no install-URL change).
        $broadRow.releaseChannelReadiness | Should -Be 'blocked'
        $broadRow.releaseChannelEvidence.metadataComplete | Should -BeFalse
        $broadRow.releaseChannelNextAction | Should -Match '@updateURL'
        $scopedRow.releaseChannelReadiness | Should -Be 'ready'
        $scopedRow.releaseChannelEvidence.metadataComplete | Should -BeTrue
        $scopedRow.releaseChannelEvidence.sourceRefType | Should -Be 'tag'
        $result.releaseChannelBlockedCount | Should -Be 1
        $result.releaseChannelReadyCount | Should -Be 1
        $result.releaseChannelKeepBranchCount | Should -Be 0
    }

    It 'classifies a complete branch-hosted userscript as keep-branch' {
        $entry = New-TestEntry -Repo 'BranchScript' -Category 'extensions'
        $entry.downloadKind = 'userscript'
        $entry.userscriptUrl = 'https://raw.githubusercontent.com/SysAdminDoc/BranchScript/main/BranchScript.user.js'
        $contentByUrl = @{
            $entry.userscriptUrl = @'
// ==UserScript==
// @name        Branch Script
// @version     2.0.0
// @match       https://example.com/*
// @updateURL   https://raw.githubusercontent.com/SysAdminDoc/BranchScript/main/BranchScript.meta.js
// @downloadURL https://raw.githubusercontent.com/SysAdminDoc/BranchScript/main/BranchScript.user.js
// @grant       none
// ==/UserScript==
'@
        }
        $probeByUrl = @{
            'https://raw.githubusercontent.com/SysAdminDoc/BranchScript/main/BranchScript.meta.js' = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
            'https://raw.githubusercontent.com/SysAdminDoc/BranchScript/main/BranchScript.user.js' = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
        }

        $result = Test-UserscriptInstallTrust -Entries @($entry) -ContentByUrl $contentByUrl -ProbeByUrl $probeByUrl
        $row = $result.rows[0]
        $row.releaseChannelReadiness | Should -Be 'keep-branch'
        $row.releaseChannelEvidence.metadataComplete | Should -BeTrue
        $row.releaseChannelEvidence.sourceRefType | Should -Be 'branch'
        $row.releaseChannelEvidence.updateUrlAligned | Should -BeTrue
        $row.releaseChannelNextAction | Should -Match 'branch-hosted'
        $result.releaseChannelKeepBranchCount | Should -Be 1

        # Field parity for the new row fields against the report schema.
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $rowKeys = @($row.Keys) | Sort-Object
        $schemaRowKeys = @($schema.'$defs'.userscriptTrustRow.properties.PSObject.Properties.Name) | Sort-Object
        ($rowKeys -join ',') | Should -Be ($schemaRowKeys -join ',')
        $evidenceKeys = @($row.releaseChannelEvidence.Keys) | Sort-Object
        $schemaEvidenceKeys = @($schema.'$defs'.userscriptTrustRow.properties.releaseChannelEvidence.properties.PSObject.Properties.Name) | Sort-Object
        ($evidenceKeys -join ',') | Should -Be ($schemaEvidenceKeys -join ',')
    }

    It 'flags userscript update and download URL ref mismatches and dead raw URLs' {
        $entry = New-TestEntry -Repo 'MismatchScript' -Category 'extensions'
        $entry.downloadKind = 'userscript'
        $entry.userscriptUrl = 'https://raw.githubusercontent.com/SysAdminDoc/MismatchScript/master/MismatchScript.user.js'
        $updateUrl = 'https://raw.githubusercontent.com/SysAdminDoc/MismatchScript/main/MismatchScript.meta.js'
        $downloadUrl = 'https://raw.githubusercontent.com/SysAdminDoc/MismatchScript/main/MismatchScript.user.js'
        $contentByUrl = @{
            $entry.userscriptUrl = @"
// ==UserScript==
// @name        Mismatch Script
// @version     1.0.0
// @match       https://example.com/*
// @updateURL   $updateUrl
// @downloadURL $downloadUrl
// @grant       none
// ==/UserScript==
"@
        }
        $probeByUrl = @{
            $updateUrl = [ordered]@{ ok = $false; status = 404; error = 'Not Found'; fatal = $true }
            $downloadUrl = [ordered]@{ ok = $false; status = 404; error = 'Not Found'; fatal = $true }
        }

        $result = Test-UserscriptInstallTrust -Entries @($entry) -ContentByUrl $contentByUrl -ProbeByUrl $probeByUrl
        $row = $result.rows[0]

        $result.warningCount | Should -Be 4
        $result.fatalCount | Should -Be 2
        $result.updateUrlProbeFailureCount | Should -Be 1
        $result.downloadUrlProbeFailureCount | Should -Be 1
        $result.updateUrlRefMismatchCount | Should -Be 1
        $result.downloadUrlRefMismatchCount | Should -Be 1
        $row.sourceRef | Should -Be 'master'
        $row.updateUrlSourceRef | Should -Be 'main'
        $row.downloadUrlSourceRef | Should -Be 'main'
        $row.updateUrlRefMatchesSource | Should -BeFalse
        $row.downloadUrlRefMatchesSource | Should -BeFalse
        $row.updateUrlProbeSucceeded | Should -BeFalse
        $row.downloadUrlProbeSucceeded | Should -BeFalse
        $row.updateUrlProbeStatusCode | Should -Be 404
        $row.downloadUrlProbeStatusCode | Should -Be 404
        ($row.warnings | ForEach-Object { $_.kind }) | Should -Contain 'update-url-ref-mismatch'
        ($row.warnings | ForEach-Object { $_.kind }) | Should -Contain 'download-url-ref-mismatch'
        ($row.warnings | ForEach-Object { $_.kind }) | Should -Contain 'update-url-unreachable'
        ($row.warnings | ForEach-Object { $_.kind }) | Should -Contain 'download-url-unreachable'
        ($row.warnings | Where-Object { $_.fatal }).Count | Should -Be 2
    }
}

Describe 'Offline generation with an empty repository set' {
    BeforeAll {
        $script:emptyCat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
    }
    It 'renders README, feed, and asset SVGs without a Count-on-null crash when repos bind to null' {
        { New-Readme -Catalog $script:emptyCat -Repos $null } | Should -Not -Throw
        { New-ProjectsExportJson -Catalog $script:emptyCat -Repos $null } | Should -Not -Throw
        { New-ProfileAssetSvgs } | Should -Not -Throw
    }
    It 'reports zero live repositories in the feed provenance when the repo set is empty' {
        $feed = New-ProjectsExportJson -Catalog $script:emptyCat -Repos @() | ConvertFrom-Json
        $feed.publicRepoCount | Should -Be 0
        $feed.provenance.repoEnumeration.returnedCount | Should -Be 0
    }

    It 'generates no profile SVG assets for the text-only README' {
        # The README header and footer reference no generated image. Twelve SVGs used to be
        # rendered, committed and drift-checked for a rich header that never displayed.
        $assets = New-ProfileAssetSvgs

        $null -eq $assets | Should -BeFalse -Because 'callers enumerate the returned dictionary'
        $assets.Count | Should -Be 0
    }
}

Describe 'Generation determinism across culture, time zone and input order' {
    BeforeAll {
        # Culture is per thread, but the local time zone comes from the OS. The zone is
        # swapped through TimeZoneInfo's private cache and restored with ClearCachedData.
        # A renamed field throws here rather than leaving the zone unchanged and the
        # comparison meaningless.
        function script:Set-DeterminismTimeZone {
            param([string]$Id)

            [TimeZoneInfo]::ClearCachedData()
            if ([string]::IsNullOrWhiteSpace($Id)) {
                return
            }
            $cachedField = [TimeZoneInfo].GetField('s_cachedData', [Reflection.BindingFlags]'NonPublic,Static')
            if ($null -eq $cachedField) { throw 'TimeZoneInfo.s_cachedData not found; the determinism time-zone seam needs updating.' }
            $cached = $cachedField.GetValue($null)
            $localField = $cached.GetType().GetField('_localTimeZone', [Reflection.BindingFlags]'NonPublic,Instance')
            if ($null -eq $localField) { throw 'TimeZoneInfo cached _localTimeZone not found; the determinism time-zone seam needs updating.' }
            $zone = [TimeZoneInfo]::FindSystemTimeZoneById($Id)
            $localField.SetValue($cached, $zone)
            if ([TimeZoneInfo]::Local.Id -ne $zone.Id) { throw "Local time zone did not switch to $Id." }
        }

        # Repository metadata as gh returns it: JSON text parsed inside each run, so date
        # parsing happens under that run's culture and zone. Star counts cycle through
        # three values so most rows tie and fall through to the name ordering, which is
        # where locale-sensitive comparison showed up (IRL_Streamer before iOSIconPack).
        $script:DeterminismCatalog = Get-Catalog -Path (Join-Path $script:RepoRoot 'data/profile-catalog.json')
        $index = 0
        $script:DeterminismRepoJson = @(foreach ($entry in @($script:DeterminismCatalog.entries | Where-Object {
                        [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) -and [string]::IsNullOrWhiteSpace([string]$_.aliasOf)
                    })) {
                $index++
                # Every fourth row carries a release whose asset names mix I and i, which sort
                # and match differently under tr-TR; one row has an offset timestamp, which
                # ConvertFrom-Json turns into local time.
                $release = if ($index % 4 -eq 0) {
                    [ordered]@{
                        tagName = 'v1.0.0'
                        url = "https://github.com/SysAdminDoc/$($entry.repo)/releases/tag/v1.0.0"
                        publishedAt = '2026-06-04T00:00:00Z'
                        releaseAssetNames = @('Imager-x64.exe', 'imager-arm64.exe', 'Imager-x64.exe.sha256', 'imager-arm64.exe.sha256', 'IMAGER.EXE.SIG', 'SBOM.SPDX.JSON', 'Setup.ZIP')
                        releaseAssetKinds = @()
                        assetApiInspected = $true
                    }
                } else {
                    $null
                }
                [ordered]@{
                    name = [string]$entry.repo
                    description = "Fixture description for $($entry.repo)"
                    stargazerCount = $index % 3
                    primaryLanguage = [ordered]@{ name = 'PowerShell' }
                    repositoryTopics = @([ordered]@{ name = 'utility' }, [ordered]@{ name = 'Ideas' }, [ordered]@{ name = 'iot' })
                    defaultBranchRef = [ordered]@{ name = 'main'; target = [ordered]@{ oid = ('{0:x40}' -f $index) } }
                    latestRelease = $release
                    licenseInfo = [ordered]@{ spdxId = 'MIT'; key = 'mit'; name = 'MIT License' }
                    isFork = $false
                    parent = $null
                    visibility = 'PUBLIC'
                    isPrivate = $false
                    isArchived = $false
                    pushedAt = if ($index -eq 5) { '2026-06-04T02:00:00+02:00' } else { '2026-06-04T00:00:00Z' }
                    url = "https://github.com/SysAdminDoc/$($entry.repo)"
                    branchTipSha = ('{0:x40}' -f $index)
                    branchTipFetchedAt = '2026-06-04T00:00:00Z'
                    branchTipStatus = 'fresh'
                    branchTipWarning = $null
                } | ConvertTo-Json -Depth 10 -Compress
            })

        function script:Invoke-DeterministicGeneration {
            param(
                [hashtable]$Catalog,
                [string[]]$RepoJson,
                [string]$Culture = 'en-US',
                [string]$TimeZoneId = 'UTC'
            )

            $oldCulture = [cultureinfo]::CurrentCulture
            $oldUiCulture = [cultureinfo]::CurrentUICulture
            $oldSnapshotAt = $script:MetadataSnapshotAt
            try {
                [cultureinfo]::CurrentCulture = $Culture
                [cultureinfo]::CurrentUICulture = $Culture
                script:Set-DeterminismTimeZone -Id $TimeZoneId
                $script:MetadataSnapshotAt = '2026-08-23T12:00:00.0000000Z'
                $repos = @($RepoJson | ForEach-Object { $_ | ConvertFrom-Json })
                foreach ($repo in @($repos | Where-Object { $null -ne $_.latestRelease })) {
                    # Asset kinds are derived at fetch time, so derive them under this run's culture.
                    $repo.latestRelease.releaseAssetKinds = @(Get-ReleaseAssetKinds -AssetNames @($repo.latestRelease.releaseAssetNames))
                }
                $artifacts = [ordered]@{
                    culture = [cultureinfo]::CurrentCulture.Name
                    timeZone = [TimeZoneInfo]::Local.Id
                    readme = New-Readme -Catalog $Catalog -Repos $repos
                    projects = New-ProjectsExportJson -Catalog $Catalog -Repos $repos -GeneratedAt '2026-08-23T12:00:01.0000000Z'
                    backstage = New-BackstageCatalogExportJson -Catalog $Catalog -Repos $repos
                }
                return $artifacts
            } finally {
                [cultureinfo]::CurrentCulture = $oldCulture
                [cultureinfo]::CurrentUICulture = $oldUiCulture
                $script:MetadataSnapshotAt = $oldSnapshotAt
                script:Set-DeterminismTimeZone -Id $null
            }
        }

        function script:Assert-SameGeneration {
            param([System.Collections.IDictionary]$Actual, [string]$Because)
            foreach ($artifact in @('readme', 'projects', 'backstage')) {
                $Actual[$artifact] | Should -BeExactly $script:DeterminismBaseline[$artifact] -Because "$artifact must not change $Because"
            }
        }

        $script:DeterminismBaseline = script:Invoke-DeterministicGeneration -Catalog $script:DeterminismCatalog -RepoJson $script:DeterminismRepoJson
    }

    It 'records the baseline under en-US in UTC' {
        $script:DeterminismBaseline.culture | Should -Be 'en-US'
        $script:DeterminismBaseline.timeZone | Should -Be ([TimeZoneInfo]::FindSystemTimeZoneById('UTC').Id)
        $script:DeterminismBaseline.readme | Should -Match 'iOSIconPack'
        $script:DeterminismBaseline.readme | Should -Match 'IRL_Streamer'
        # The fixture must reach the release-trust and timestamp paths, or the comparisons
        # below prove nothing about them.
        $script:DeterminismBaseline.projects | Should -Match 'IMAGER\.EXE\.SIG'
        $script:DeterminismBaseline.projects | Should -Not -Match '"pushedAt":\s*"[^"]*[+-]\d\d:\d\d"' -Because 'a local timestamp must be written as UTC'
    }

    It 'renders byte-identical README, feed and Backstage output under tr-TR' {
        $turkish = script:Invoke-DeterministicGeneration -Catalog $script:DeterminismCatalog -RepoJson $script:DeterminismRepoJson -Culture 'tr-TR'

        $turkish.culture | Should -Be 'tr-TR'
        script:Assert-SameGeneration -Actual $turkish -Because 'when the process culture is tr-TR'
    }

    It 'renders byte-identical README, feed and Backstage output in America/New_York' {
        $eastern = script:Invoke-DeterministicGeneration -Catalog $script:DeterminismCatalog -RepoJson $script:DeterminismRepoJson -TimeZoneId 'America/New_York'

        $eastern.timeZone | Should -Be ([TimeZoneInfo]::FindSystemTimeZoneById('America/New_York').Id)
        script:Assert-SameGeneration -Actual $eastern -Because 'when the local time zone is America/New_York'
    }

    It 'renders byte-identical output for 20 shuffled catalog and repository orders' -Tag 'Integration' {
        $random = [Random]::new(20260922)
        for ($shuffle = 1; $shuffle -le 20; $shuffle++) {
            $catalog = @{}
            foreach ($key in $script:DeterminismCatalog.Keys) { $catalog[$key] = $script:DeterminismCatalog[$key] }
            $catalog.entries = @($script:DeterminismCatalog.entries | Sort-Object { $random.Next() })
            $repoJson = @($script:DeterminismRepoJson | Sort-Object { $random.Next() })

            $shuffled = script:Invoke-DeterministicGeneration -Catalog $catalog -RepoJson $repoJson

            script:Assert-SameGeneration -Actual $shuffled -Because "for shuffle $shuffle"
        }
    }

    It 'writes byte-identical README and feed from the entry point in fresh tr-TR and en-US processes' -Tag 'Integration' {
        $cachePath = Join-Path $TestDrive 'culture-cache'
        $oldCachePath = $script:CachePath
        $oldCacheEnabled = $script:CacheEnabled
        $oldMetadataSnapshotAt = $script:MetadataSnapshotAt
        $oldProvider = $script:RepositoryMetadataProvider
        $oldRequestedLimit = $script:RepositoryEnumerationRequestedLimit
        $oldTruncated = $script:RepositoryEnumerationTruncated
        $assets = @('Imager-x64.exe', 'imager-arm64.exe', 'Imager-x64.exe.sha256', 'imager-arm64.exe.sha256', 'IMAGER.EXE.SIG', 'SBOM.SPDX.JSON', 'Setup.ZIP')
        try {
            $script:CachePath = $cachePath
            $script:CacheEnabled = $true
            $script:MetadataSnapshotAt = (Get-Date).ToUniversalTime().ToString('o')
            $script:RepositoryMetadataProvider = 'graphql'
            $script:RepositoryEnumerationRequestedLimit = 25
            $script:RepositoryEnumerationTruncated = $false
            Reset-ValidationCacheState
            $repos = @(
                (New-TestRepoMeta -Name 'WinTool' -Topics @('Imaging', 'iot') -WithRelease -AssetNames $assets),
                (New-TestRepoMeta -Name 'ReleaseTool' -WithRelease -AssetNames $assets),
                (New-TestRepoMeta -Name 'PyTool' -Language 'Python')
            )
            Write-CompleteGenerationSnapshot -Repos $repos -ReleaseMetadataComplete:$true | Should -BeTrue
        } finally {
            $script:CachePath = $oldCachePath
            $script:CacheEnabled = $oldCacheEnabled
            $script:MetadataSnapshotAt = $oldMetadataSnapshotAt
            $script:RepositoryMetadataProvider = $oldProvider
            $script:RepositoryEnumerationRequestedLimit = $oldRequestedLimit
            $script:RepositoryEnumerationTruncated = $oldTruncated
            Reset-ValidationCacheState
        }

        $runner = Join-Path $TestDrive 'culture-runner.ps1'
        Set-Content -LiteralPath $runner -Encoding utf8 -Value @'
param([string]$Culture, [string]$Entry, [string]$Catalog, [string]$Readme, [string]$Projects, [string]$Cache, [string]$Assets)
[System.Globalization.CultureInfo]::CurrentCulture = $Culture
& $Entry -Write -Offline -CatalogPath $Catalog -ReadmePath $Readme -ProjectsPath $Projects -CachePath $Cache -AssetsPath $Assets
exit $LASTEXITCODE
'@
        $outputs = @{}
        foreach ($culture in @('en-US', 'tr-TR')) {
            $readme = Join-Path $TestDrive "README-$culture.md"
            $projects = Join-Path $TestDrive "projects-$culture.json"
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Destination $readme -Force
            # The runner writes with -Write, so every output path is the test drive's; without
            # -AssetsPath the profile assets would land in the checkout.
            $log = & pwsh -NoProfile -File $runner -Culture $culture -Entry $script:SyncProfileScriptPath `
                -Catalog (Join-Path $PSScriptRoot 'fixtures/catalog.json') -Readme $readme -Projects $projects -Cache $cachePath `
                -Assets (Join-Path $TestDrive "assets-$culture") *>&1
            $LASTEXITCODE | Should -Be 0 -Because ($log | Out-String)
            $outputs[$culture] = @{
                readme = [System.IO.File]::ReadAllText($readme)
                projects = [System.IO.File]::ReadAllText($projects)
            }
        }

        $outputs['en-US'].projects | Should -Match 'IMAGER\.EXE\.SIG'
        $outputs['tr-TR'].readme | Should -BeExactly $outputs['en-US'].readme
        $outputs['tr-TR'].projects | Should -BeExactly $outputs['en-US'].projects
    }

    It 'still flags a medical-imaging repository in a fresh tr-TR process' -Tag 'Integration' {
        $runner = Join-Path $TestDrive 'medical-runner.ps1'
        Set-Content -LiteralPath $runner -Encoding utf8 -Value @'
param([string]$GeneratorEntry, [string]$FixtureCatalogPath, [string]$RunnerCachePath)
# Parameter names must not match the generator's own (a dot-source rebinds them) or a
# later variable ($catalog would coerce into a [string] $Catalog parameter). The cache is
# the test drive's: the generator's default is the checkout's .cache.
[System.Globalization.CultureInfo]::CurrentCulture = 'tr-TR'
. $GeneratorEntry -CachePath $RunnerCachePath
$Offline = $true
$script:Offline = $true
$catalog = Get-Catalog -Path $FixtureCatalogPath
$catalog.entries = @($catalog.entries + (ConvertTo-EntryHashtable (New-CatalogEntry -Repo 'DICOM-Viewer' -Category 'desktop' -Description 'desc' -Order 99)))
$repo = [pscustomobject]@{
    name = 'DICOM-Viewer'; description = 'Viewer'; primaryLanguage = [pscustomobject]@{ name = 'C#' }
    repositoryTopics = @(); defaultBranchRef = [pscustomobject]@{ name = 'main'; target = $null }
    branchTipSha = $null; branchTipFetchedAt = $null; branchTipStatus = 'unreachable'; branchTipWarning = 'fixture'
    latestRelease = $null; stargazerCount = 0; pushedAt = '2026-06-04T00:00:00Z'; licenseInfo = $null
    isFork = $false; parent = $null; forkParentFetchError = $null; visibility = 'PUBLIC'; isPrivate = $false
    isArchived = $false; url = 'https://github.com/SysAdminDoc/DICOM-Viewer'
}
$readme = New-Readme -Catalog $catalog -Repos @($repo)
$projects = New-ProjectsExportJson -Catalog $catalog -Repos @($repo)
$result = Test-ProfileState -Catalog $catalog -Repos @($repo) -ExpectedReadme $readme -ExpectedProjects $projects `
    -CurrentReadme $readme -CurrentProjects $projects -ExpectedAssets (New-ProfileAssetSvgs) -CurrentAssets @{} -SkipLinkValidation
"culture=$([System.Globalization.CultureInfo]::CurrentCulture.Name)"
"medical=$(@($result.Report.medicalPrivacyViolations | Where-Object { $_.repo -eq 'DICOM-Viewer' }).Count)"
'@

        $output = & pwsh -NoProfile -File $runner -GeneratorEntry $script:SyncProfileScriptPath -FixtureCatalogPath (Join-Path $PSScriptRoot 'fixtures/catalog.json') `
            -RunnerCachePath (Join-Path $TestDrive 'medical-cache') 2>&1 | Out-String

        $output | Should -Match 'culture=tr-TR' -Because 'the check must run under the Turkish culture that broke it'
        $output | Should -Match 'medical=1' -Because $output
    }

    It 'orders identifiers by OrdinalIgnoreCase whatever the culture' {
        $names = @('IRL_Streamer', 'iOSIconPack', 'IconForge', 'improve-repo', 'IMDb_Enhanced', 'Images', 'ImgConverter')
        $expected = [string[]]$names.Clone()
        [Array]::Sort($expected, [StringComparer]::OrdinalIgnoreCase)
        $oldCulture = [cultureinfo]::CurrentCulture
        try {
            foreach ($culture in @('en-US', 'tr-TR', 'da-DK', 'lt-LT')) {
                [cultureinfo]::CurrentCulture = $culture
                @($names | Sort-Object { ConvertTo-OrdinalSortKey $_ }) | Should -Be $expected -Because "order under $culture"
            }
        } finally {
            [cultureinfo]::CurrentCulture = $oldCulture
        }
        ConvertTo-OrdinalSortKey $null | Should -Be ''
    }
}

Describe 'Profile footer contact route' {
    It 'links to the portfolio contact section and publishes no address itself' {
        $footer = New-ProfileFooter

        # The origin comes from the resolver: tests see the owner fallback, a real run the
        # configured -PortfolioUrl (https://portfolio.getparkerai.com/).
        $footer | Should -Match ([regex]::Escape('<a href="' + (Get-ProfilePortfolioUrl) + '#connect">Get in touch</a>'))
        $footer | Should -Match 'See everything'
        $footer | Should -Not -Match 'mailto:'
        [regex]::Matches($footer, '<img\b').Count | Should -Be 0
    }

    It 'renders the contact link at the end of the generated README' {
        $readme = New-Readme -Catalog (Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')) -Repos @()

        $readme.TrimEnd() | Should -Match '#connect">Get in touch</a></p>$'
    }

    It 'publishes the portfolio contact link in the committed README' {
        $committed = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw

        $committed | Should -Match ([regex]::Escape('<a href="https://portfolio.getparkerai.com/#connect">Get in touch</a>'))
    }
}

Describe 'What-is-this sentence before the category grid' {
    It 'explains the page and its audience in one sentence ahead of the grid' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $visible = @($cat.entries | Where-Object { $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) }).Count

        $readme = New-Readme -Catalog $cat -Repos @()
        $section = $readme.Substring($readme.IndexOf("### What's here"))
        $sentence = @($section -split "\r?\n" | Where-Object { $_ -like 'This is the index of *' })

        $sentence | Should -HaveCount 1
        $sentence[0] | Should -Match "^This is the index of the $visible public projects I've published"
        $sentence[0] | Should -Match 'for anyone who'
        ($sentence[0] -split '(?<=[.!?])\s+').Count | Should -Be 1 -Because 'it is a single sentence'
        $tagline = [regex]::Match($readme.TrimStart(), '^<p align="center"><b>(?<text>[^<]+)</b>').Groups['text'].Value
        $tagline | Should -Not -BeNullOrEmpty
        $sentence[0] | Should -Not -Match ([regex]::Escape($tagline))
        $sentence[0] | Should -Not -Match '[\u2013\u2014]'
        $section.IndexOf($sentence[0]) | Should -BeLessThan $section.IndexOf('| PowerShell |') -Because 'it has to come before the grid'
    }
}

Describe 'Star count display threshold' {
    It 'shows star counts at or above the threshold and hides lower ones' {
        $MinStarDisplay | Should -Be 2
        Get-StarText $null | Should -Be ''
        Get-StarText ([pscustomobject]@{ stargazerCount = 0 }) | Should -Be ''
        Get-StarText ([pscustomobject]@{ stargazerCount = 1 }) | Should -Be ''
        Get-StarText ([pscustomobject]@{ stargazerCount = 2 }) | Should -Be ' &#11088;2'
        Get-StarText ([pscustomobject]@{ stargazerCount = 69 }) | Should -Be ' &#11088;69'
    }

    It 'follows the constant rather than a hard-coded threshold' {
        $MinStarDisplay = 5

        Get-StarText ([pscustomobject]@{ stargazerCount = 4 }) | Should -Be ''
        Get-StarText ([pscustomobject]@{ stargazerCount = 5 }) | Should -Be ' &#11088;5'
    }

    It 'renders README rows with the threshold applied' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $oneStar = New-TestRepoMeta -Name 'WinTool'
        $oneStar.stargazerCount = 1
        $threeStars = New-TestRepoMeta -Name 'PyTool' -Language 'Python'
        $threeStars.stargazerCount = 3

        $readme = New-Readme -Catalog $cat -Repos @($oneStar, $threeStars)

        $readme | Should -Match '\[\*\*WinTool\*\*\]\(https://github\.com/SysAdminDoc/WinTool\) &middot; '
        $readme | Should -Not -Match 'WinTool\) &#11088;1'
        $readme | Should -Match '\[\*\*PyTool\*\*\]\(https://github\.com/SysAdminDoc/PyTool\) &#11088;3'
    }

    It 'orders a category by the real star count, including counts it hides' {
        $definition = $CategoryDefinitions | Where-Object { $_.Slug -eq 'powershell' } | Select-Object -First 1
        $entries = @(
            (New-TestEntry -Repo 'Alpha' -Category 'powershell')
            (New-TestEntry -Repo 'Mu' -Category 'powershell')
            (New-TestEntry -Repo 'Zeta' -Category 'powershell')
        )
        $lookup = @{}
        foreach ($stars in @(@('Alpha', 0), @('Mu', 1), @('Zeta', 3))) {
            $meta = New-TestRepoMeta -Name $stars[0]
            $meta.stargazerCount = $stars[1]
            $lookup[$stars[0].ToLowerInvariant()] = $meta
        }

        $section = New-CategorySection -Entries $entries -RepoLookup $lookup -Definition $definition
        $rows = @([regex]::Matches($section, '(?m)^\[\*\*(\w+)\*\*\]\([^)]*\)(?: &#11088;\d+)? &middot; ') | ForEach-Object { $_.Groups[1].Value })

        # Mu's single star is not shown, and it still ranks above Alpha's zero; alphabetical
        # order would put Alpha first.
        $rows | Should -Be @('Zeta', 'Mu', 'Alpha')
        $section | Should -Match '\[\*\*Zeta\*\*\]\([^)]*\) &#11088;3 &middot; '
        $section | Should -Not -Match '&#11088;1'
    }
}

Describe 'Owner-bound output follows -Owner' {
    BeforeAll {
        $script:OwnerAgnosticCatalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/owner-agnostic-catalog.json')
    }

    It 'renders no link to the default owner when another owner generates the README' {
        $Owner = 'FixtureOwner'
        $readme = New-Readme -Catalog $script:OwnerAgnosticCatalog -Repos @()

        $readme | Should -Not -Match '(?i)github\.com/SysAdminDoc|githubusercontent\.com/SysAdminDoc'
        $readme | Should -Match ([regex]::Escape('[`setup.ps1`](https://github.com/FixtureOwner/FixtureOwner/blob/main/setup.ps1)'))
        # What is left names the files setup.ps1 itself writes, which a fork's copy keeps.
        $leftovers = @([regex]::Matches($readme, '(?i)SysAdminDoc[\w.*-]*') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $leftovers | Should -HaveCount 2
        $leftovers | Should -Contain 'SysAdminDoc-setup.ps1'
        $leftovers | Should -Contain 'SysAdminDoc-setup-*.log'
    }

    It 'counts rendered table rows for another owner' {
        $Owner = 'FixtureOwner'
        $readme = New-Readme -Catalog $script:OwnerAgnosticCatalog -Repos @()
        $expectedRows = [regex]::Matches($readme, '(?m)^\| \[\*\*.+?\*\*\]\(https://github\.com/FixtureOwner/').Count
        $expectedRows | Should -BeGreaterThan 0 -Because 'the fixture renders a web tools table row'

        $density = Test-ReadmeDensity -ExpectedReadme $readme -Entries @($script:OwnerAgnosticCatalog.entries) -RepoLookup (ConvertTo-Lookup @())
        $budgets = Test-GeneratedArtifactBudgets -ExpectedReadme $readme -ExpectedProjectsJson '{"projects":[]}' -ExpectedAssets @{} -ReportJson '{}'

        $density.tableRowCount | Should -Be $expectedRows
        @($budgets.rows | Where-Object { $_.metric -eq 'tableRows' })[0].value | Should -Be $expectedRows
    }

    It 'recognizes a featured action list row for another owner' {
        $Owner = 'FixtureOwner'
        $readme = '- [**FixtureTool**](https://github.com/FixtureOwner/FixtureTool) -- A fixture tool<br/>Web Tools<br/>Action: [Launch](https://fixture.example.test/)'

        (Test-ReadmeExperience -Catalog $script:OwnerAgnosticCatalog -Repos @() -ExpectedReadme $readme).featuredActionList | Should -BeTrue
    }

    It 'seeds a catalog from a README generated for another owner' {
        $Owner = 'FixtureOwner'
        # Render before pointing $ReadmePath at the copy: New-Readme reads $ReadmePath too.
        $readme = New-Readme -Catalog $script:OwnerAgnosticCatalog -Repos @()
        $ReadmePath = Join-Path $TestDrive 'fixture-owner-readme.md'
        Set-Content -LiteralPath $ReadmePath -Value $readme -Encoding utf8

        $seeded = New-CatalogFromReadme -Repos @()

        $row = @($seeded.entries | Where-Object { $_.repo -eq 'FixtureTool' })
        $row | Should -HaveCount 1
        $row[0].category | Should -Be 'web'
        $row[0].liveUrl | Should -Be 'https://fixture.example.test/'
    }

    It 'passes the published schemas with the catalog, feed and report of another owner' {
        # The schemas pin the shape of the owner-bound fields, not the account: a fork's own
        # feed has to validate without editing them.
        $Owner = 'FixtureOwner'
        $SchemaBaseUrl = 'https://raw.githubusercontent.com/FixtureOwner/FixtureOwner/main/schemas'
        $CatalogSchemaUrl = "$SchemaBaseUrl/profile-catalog.v1.json"
        $ProjectsSchemaUrl = "$SchemaBaseUrl/profile-projects.v1.json"
        $ReportSchemaUrl = "$SchemaBaseUrl/profile-sync-report.v1.json"
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/owner-agnostic-catalog.json')
        $catalog.schema = $CatalogSchemaUrl
        $readme = New-Readme -Catalog $catalog -Repos @()
        $projects = New-ProjectsExportJson -Catalog $catalog -Repos @()

        $feed = Test-FeedSchemaContracts -Catalog $catalog -ProjectsJson $projects
        @(@($feed.catalog.errors) + @($feed.projects.errors) | ForEach-Object { '{0} {1}' -f $_.instanceLocation, $_.message }) | Should -BeNullOrEmpty
        $feed.passed | Should -BeTrue
        ($projects | ConvertFrom-Json).provenance.sourceRepository | Should -Be 'FixtureOwner/FixtureOwner'

        $state = Test-ProfileState -Catalog $catalog -Repos @() -ExpectedReadme $readme -ExpectedProjects $projects `
            -ExpectedAssets @{} -CurrentReadme $readme -CurrentProjects $projects -CurrentAssets @{} -SkipLinkValidation `
            -SmokeReportPath (Join-Path $TestDrive 'no-smoke-run.json')
        @($state.Report.schemaValidation.report.errors | ForEach-Object { '{0} {1}' -f $_.instanceLocation, $_.message }) | Should -BeNullOrEmpty
        $state.Report.schema | Should -Be $ReportSchemaUrl
    }

    It 'still rejects a schema URL for another file or a malformed source' {
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/owner-agnostic-catalog.json')
        $payload = New-ProjectsExportJson -Catalog $catalog -Repos @() | ConvertFrom-Json
        $payload.schema = 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/schemas/profile-catalog.v1.json'
        $payload.source = 'SysAdminDoc data/profile-catalog.json'

        $feed = Test-FeedSchemaContracts -Catalog $catalog -ProjectsJson ($payload | ConvertTo-Json -Depth 30)
        $feed.projects.valid | Should -BeFalse
        @($feed.projects.errors | ForEach-Object { $_.instanceLocation }) | Should -Contain '/schema'
        @($feed.projects.errors | ForEach-Object { $_.instanceLocation }) | Should -Contain '/source'
    }

    It 'rejects <Case> in the owner-bound feed fields' -ForEach @(
        @{ Case = 'a trailing newline'; Schema = "https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/schemas/profile-projects.v1.json`n"; Source = "SysAdminDoc/SysAdminDoc data/profile-catalog.json`n"; SourceRepository = "SysAdminDoc/SysAdminDoc`n" }
        @{ Case = 'a dot segment'; Schema = 'https://raw.githubusercontent.com/SysAdminDoc/../main/schemas/profile-projects.v1.json'; Source = 'SysAdminDoc/.. data/profile-catalog.json'; SourceRepository = 'x/..' }
        @{ Case = 'a repo that is not the profile repo'; Schema = 'https://raw.githubusercontent.com/someone/other-repo/main/schemas/profile-projects.v1.json'; Source = 'someone/other-repo data/profile-catalog.json'; SourceRepository = 'someone/other-repo' }
    ) {
        # .NET regex lets $ match before a final newline, and a loose owner/repo pattern let
        # through values the old const refused; the patterns pin the profile repo and the end.
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/owner-agnostic-catalog.json')
        $payload = New-ProjectsExportJson -Catalog $catalog -Repos @() | ConvertFrom-Json
        $payload.schema = $Schema
        $payload.source = $Source
        $payload.provenance.sourceRepository = $SourceRepository

        $feed = Test-FeedSchemaContracts -Catalog $catalog -ProjectsJson ($payload | ConvertTo-Json -Depth 30)

        $locations = @($feed.projects.errors | ForEach-Object { $_.instanceLocation })
        $locations | Should -Contain '/schema'
        $locations | Should -Contain '/source'
        $locations | Should -Contain '/provenance/sourceRepository'
    }

    It 'seeds every legacy row shape from a README written for another owner' {
        $Owner = 'FixtureOwner'
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/owner-agnostic-catalog.json')
        $catalog.entries = @($catalog.entries) + @(
            (New-TestEntry -Repo 'OwnerCode' -Category 'powershell' -Description 'A code row')
            (New-TestEntry -Repo 'OwnerMisc' -Category 'misc' -Description 'A two-column row')
        )
        # Render before pointing $ReadmePath at the copy: New-Readme reads $ReadmePath too.
        $rendered = New-Readme -Catalog $catalog -Repos @()
        # The featured table shapes are no longer rendered, but the legacy parser still reads them.
        $featured = @(
            '| [**FeatStars**](https://github.com/FixtureOwner/FeatStars) | &#11088;5 | Featured with stars |'
            '| [**FeatAction**](https://github.com/FixtureOwner/FeatAction) | PowerShell | &#11088;3 | Featured with an action | [Repo](https://github.com/FixtureOwner/FeatAction) |'
        ) -join "`n"
        $ReadmePath = Join-Path $TestDrive 'legacy-owner-readme.md'
        Set-Content -LiteralPath $ReadmePath -Value ($featured + "`n`n" + $rendered) -Encoding utf8

        $seeded = New-CatalogFromReadme -Repos @()
        $byRepo = @{}
        foreach ($entry in @($seeded.entries)) { $byRepo[[string]$entry.repo] = $entry }

        # One repo per row shape: featured with stars, featured with an action, a code row,
        # a table row with a trailing cell, and a two-column table row.
        $byRepo['FeatStars'].featured | Should -BeTrue
        $byRepo['FeatAction'].featured | Should -BeTrue
        $byRepo['OwnerCode'].category | Should -Be 'powershell'
        $byRepo['FixtureTool'].category | Should -Be 'web'
        $byRepo['OwnerMisc'].category | Should -Be 'misc'
    }

    It 'names the default owner in the generator only where it is not the owner' {
        # Any other literal would put the default owner into a run made with -Owner.
        $allowed = @(
            '^\s*\[string\]\$Owner = "SysAdminDoc",$'                           # the parameter default
            '^# \$Owner is a script parameter \(defaults to "SysAdminDoc"\)'     # the comment on it
            "-UserAgent 'SysAdminDoc-[a-z-]+'|\[string\]\`$UserAgent = 'SysAdminDoc-profile-sync'"  # names the tool to servers
            'SysAdminDoc\.Networking'                                           # namespace of the compiled HTTP handler
            'SysAdminDoc-setup'                                                 # files setup.ps1 itself writes
            'sysadmindoc-backstage-catalog\.v1'                                 # feed format identifier
        )
        $offenders = foreach ($path in $script:SyncProfileSourcePaths) {
            $lineNumber = 0
            foreach ($line in [System.IO.File]::ReadAllLines($path)) {
                $lineNumber++
                # Strip each allowed token instead of excusing the whole line, so an owner
                # literal sitting next to an allowed one is still caught.
                $remainder = $line
                foreach ($pattern in $allowed) {
                    $remainder = [regex]::Replace($remainder, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                }
                if ($remainder -match 'sysadmindoc') {
                    '{0}:{1}: {2}' -f [System.IO.Path]::GetFileName($path), $lineNumber, $line.Trim()
                }
            }
        }

        @($offenders) | Should -BeNullOrEmpty
    }
}

Describe 'Empty category sections are not rendered' {
    It 'returns an empty string for a category with no visible entries' {
        $definition = $CategoryDefinitions | Where-Object { $_.Slug -eq 'security' } | Select-Object -First 1
        $entries = @((New-TestEntry -Repo 'OnlyPowerShell' -Category 'powershell'))
        $section = New-CategorySection -Entries $entries -RepoLookup @{} -Definition $definition
        [string]::IsNullOrEmpty($section) | Should -BeTrue
    }

    It 'links only to category sections that are rendered' {
        # The fixture has no Android, Security, Desktop or Guides rows.
        $readme = New-Readme -Catalog (Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')) -Repos @()
        $rendered = @([regex]::Matches($readme, '(?m)^<a id="(?<id>[^"]+)"></a>') | ForEach-Object { $_.Groups['id'].Value })
        $linked = @([regex]::Matches($readme, '\(#(?<id>[a-z0-9-]+)\)|href="#(?<id>[a-z0-9-]+)"') | ForEach-Object { $_.Groups['id'].Value } | Select-Object -Unique)

        $rendered | Should -Not -Contain 'android-applications'
        @($linked | Where-Object { $_ -notin $rendered }) | Should -BeNullOrEmpty -Because 'every in-page link needs a section to land on'
        $readme | Should -Match '<sub>No public rows</sub>\s*\|'
        @(Test-ReadmeHeaderAnchor -ExpectedReadme $readme) | Should -BeNullOrEmpty
        $readme | Should -Match '<a href="#powershell-system-utilities">PowerShell</a>'
    }

    It 'keeps the header contract when a catalog has no PowerShell rows' {
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $catalog.entries = @($catalog.entries | Where-Object { $_.category -ne 'powershell' })
        $readme = New-Readme -Catalog $catalog -Repos @()

        $readme | Should -Not -Match 'powershell-system-utilities'
        (Test-ReadmeExperience -Catalog $catalog -Repos @() -ExpectedReadme $readme).minimalProfileHeader | Should -BeTrue
    }

    It 'renders a section when the category has at least one entry' {
        $definition = $CategoryDefinitions | Where-Object { $_.Slug -eq 'powershell' } | Select-Object -First 1
        $entries = @((New-TestEntry -Repo 'OnlyPowerShell' -Category 'powershell'))
        $section = New-CategorySection -Entries $entries -RepoLookup @{} -Definition $definition
        $section | Should -Match '<details>'
        $section | Should -Match 'OnlyPowerShell'
    }
}

Describe 'New-Readme generation (offline, fixture catalog)' {
    BeforeAll {
        $script:cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $script:rendered = New-Readme -Catalog $script:cat -Repos @()
    }
    It 'is deterministic across repeated renders' {
        $again = New-Readme -Catalog $script:cat -Repos @()
        $again | Should -Be $script:rendered
    }
    It 'links project titles to the repo root (not /releases/latest)' {
        $script:rendered | Should -Match '\[\*\*WinTool\*\*\]\(https://github\.com/SysAdminDoc/WinTool\)'
        $script:rendered | Should -Not -Match 'releases/latest\) &middot; '
    }
    It 'includes included entries and excludes suppressed entries' {
        $script:rendered | Should -Match 'WinTool'
        $script:rendered | Should -Match 'PyTool'
        $script:rendered | Should -Not -Match 'HiddenTool'
    }
    It 'keeps the generated catalog notice when the compact discovery block is active' {
        $script:rendered | Should -Match ([regex]::Escape($GeneratedCatalogNotice))
    }
    It 'renders setup inspect-before-run and check-only guidance' {
        $script:rendered | Should -Match 'Inspect first, then install only the tooling your machine is missing'
        $script:rendered | Should -Match 'checks for PowerShell 7, Python, pip, and Git before changing anything'
        $script:rendered | Should -Match 'Inspect before installing'
        $script:rendered | Should -Match ([regex]::Escape('$u=''https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1'''))
        $script:rendered | Should -Match 'SysAdminDoc-setup\.ps1'
        $script:rendered | Should -Match '-CheckOnly'
        $script:rendered | Should -Match 'SysAdminDoc-setup-\*\.log'
    }
    It 'renders a short, contributor-labelled local validation pointer' {
        $section = [regex]::Match($script:rendered, '(?s)<a id="local-validation"></a>.*?</details>').Value
        $section | Should -Not -BeNullOrEmpty
        $section | Should -Match 'For contributors'
        $section | Should -Match ([regex]::Escape('pwsh -NoProfile -File .\scripts\validate-local.ps1'))
        $section | Should -Match ([regex]::Escape('](https://github.com/SysAdminDoc/SysAdminDoc/blob/main/.github/CONTRIBUTING.md#local-validation)'))
        # The lane-by-lane detail moved to CONTRIBUTING.md; a visitor does not scroll past it.
        $section | Should -Not -Match 'package override drift|Pester 6 compatibility lane|Backstage'
        ($section -split "`n").Count | Should -BeLessThan 20
    }

    It 'keeps the full local validation guide in CONTRIBUTING.md' {
        $contributing = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/CONTRIBUTING.md') -Raw
        $contributing | Should -Match '(?m)^## Local validation$'
        $contributing | Should -Match ([regex]::Escape('pwsh -NoProfile -File .\scripts\validate-local.ps1'))
        $contributing | Should -Match 'manual dependency and advisory review'
        $contributing | Should -Match 'npm run review:dependencies'
        $contributing | Should -Match 'package override drift'
        $contributing | Should -Match 'npm ci'
        $contributing | Should -Match 'warns below PowerShell 7\.6 LTS'
        $contributing | Should -Match 'Pester 5\.9\.1'
        $contributing | Should -Match 'PSScriptAnalyzer 1\.25\.0'
        $contributing | Should -Match 'code coverage over every script and `setup\.ps1`'
        $contributing | Should -Match ([regex]::Escape('sync-profile.ps1 -Check -GraphQlPageSize 300'))
        $contributing | Should -Match 'min-release-age=1'
        $contributing | Should -Match '-SkipBootstrap'
    }

    It 'keeps the committed README below 680 lines' {
        @(Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md')).Count | Should -BeLessThan 680
    }
    It 'renders upstream and license attribution in category rows' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $entry = @($cat.entries | Where-Object { $_.repo -eq 'WinTool' })[0]
        $entry.forkOf = 'UpstreamOrg/WinTool'
        $entry.upstreamLicense = 'MIT'

        $rendered = New-Readme -Catalog $cat -Repos @()

        [regex]::Matches($rendered, 'Upstream: \[UpstreamOrg/WinTool\]\(https://github\.com/UpstreamOrg/WinTool\); License: MIT').Count | Should -Be 1
    }
    It 'renders a minimal text-only profile chrome without images or third-party render hosts' {
        # The fixture catalog has no profileHeader block, so this is the neutral header.
        $script:rendered.TrimStart() | Should -Match '^<p align="center"><b>Public projects by SysAdminDoc</b></p>'
        $script:rendered | Should -Not -Match 'assets/profile/header-(dark|light)\.svg'
        $script:rendered | Should -Not -Match 'assets/profile/footer-(dark|light)\.svg'
        $script:rendered | Should -Not -Match '<img[^>]*assets/profile/'
        $headerRegion = $script:rendered.Substring(0, $script:rendered.IndexOf("### What's here"))
        [regex]::Matches($headerRegion, '<img\b').Count | Should -Be 0 -Because 'a header without support data has no image'
        $script:rendered | Should -Not -Match '#gh-(dark|light)-mode-only'
        $script:rendered | Should -Not -Match "Hey, I'm Matt|medical imaging|getparkerai\.com/healthcare-it|ko-fi"
        $script:rendered | Should -Not -Match 'AI service overview'
        $script:rendered | Should -Not -Match 'Proof:|186\+ shipped'
        $script:rendered | Should -Not -Match '<a href="#start-here">Start Here</a>'
        $script:rendered | Should -Match '<a href="#powershell-system-utilities">PowerShell</a>'
        $script:rendered | Should -Not -Match '### Professional Focus'
        $script:rendered | Should -Not -Match '(?m)^\*\*Currently Building\*\*$'
        $script:rendered | Should -Not -Match 'https://skillicons\.dev'
        $script:rendered | Should -Not -Match 'assets/profile/(stats|languages|activity)-(dark|light)\.svg'
        $script:rendered | Should -Not -Match 'capsule-render\.vercel\.app|readme-typing-svg|[?&]animation=|[?&]repeat=true'
        $script:rendered | Should -Not -Match 'komarev\.com|github-readme-stats|streak-stats|github-readme-activity-graph'
        $script:rendered | Should -Not -Match 'img\.shields\.io/github/(followers|stars)'
    }
    It 'renders the catalog grid without start-here table, catalog snapshot, or featured projects' {
        $script:rendered | Should -Match ([regex]::Escape($GeneratedCatalogNotice))
        $script:rendered | Should -Match "### What's here"
        $script:rendered | Should -Not -Match '### Start Here'
        $script:rendered | Should -Not -Match '### Catalog Snapshot'
        $script:rendered | Should -Not -Match '### Featured Projects'
        $script:rendered | Should -Not -Match ([regex]::Escape("| I want to... |"))
        # The retired five-column layout forced horizontal scrolling at phone widths.
        $script:rendered | Should -Not -Match ([regex]::Escape("| Signal | I want to... | Best category |"))
        $script:rendered | Should -Not -Match 'Quick platform map'
        $script:rendered | Should -Not -Match 'Feed consumers'
        $script:rendered | Should -Match '<a id="first-time-setup"></a>'
        $script:rendered | Should -Match "### What's here"
        $script:rendered | Should -Match 'Pick a category to jump in'
        $script:rendered | Should -Match 'Scripts and tools for Windows'
        $script:rendered | Should -Match 'Browser-based tools and dashboards'
    }
    It 'reports generated README byte size under the default soft budget' {
        $budget = Test-ReadmeSizeBudget -ExpectedReadme $script:rendered

        $budget.byteCount | Should -Be ([System.Text.Encoding]::UTF8.GetByteCount($script:rendered))
        $budget.softLimitBytes | Should -Be 98304
        $budget.overSoftLimit | Should -BeFalse
        $budget.warning | Should -BeNullOrEmpty
    }
    It 'warns when generated README output exceeds the soft budget' {
        $budget = Test-ReadmeSizeBudget -ExpectedReadme '0123456789' -SoftLimitBytes 5

        $budget.byteCount | Should -Be 10
        $budget.softLimitBytes | Should -Be 5
        $budget.overSoftLimit | Should -BeTrue
        $budget.warning | Should -Match 'consider collapsing low-traffic categories'
    }
    It 'reports README density and low-signal category warnings without failing sync' {
        $first = New-TestEntry -Repo 'RepoOnlyA' -Category 'powershell' -Description 'repo only A' -Order 1
        $second = New-TestEntry -Repo 'RepoOnlyB' -Category 'powershell' -Description 'repo only B' -Order 2
        $second.readmeReviewNote = 'Keep in README until explicit portfolio-only demotion is approved.'
        $density = Test-ReadmeDensity `
            -ExpectedReadme "one`ntwo`n<details>`n| [**RepoOnlyA**](https://github.com/SysAdminDoc/RepoOnlyA) | PowerShell |" `
            -Entries @($first, $second) `
            -RepoLookup (ConvertTo-Lookup @()) `
            -CategorySoftLimit 1 `
            -LowSignalSoftLimit 1

        $density.lineCount | Should -Be 4
        $density.detailsSectionCount | Should -Be 1
        $density.tableRowCount | Should -Be 1
        $density.projectRowCount | Should -Be 2
        $density.largestCategory | Should -Be 'powershell'
        $density.largestCategoryCount | Should -Be 2
        $density.repoOnlyProjectCount | Should -Be 2
        $density.lowSignalProjectCount | Should -Be 2
        $density.portfolioOnlyCandidateCount | Should -Be 2
        $density.portfolioOnlyCandidateCategoryCount | Should -Be 1
        $density.portfolioOnlyCandidateCategories | Should -Contain 'powershell'
        $density.portfolioOnlyCandidateSelectionPolicy | Should -Match 'non-featured'
        @($density.portfolioOnlyCandidates) | Should -HaveCount 2
        $density.portfolioOnlyCandidates[0].reviewRank | Should -Be 1
        $density.portfolioOnlyCandidates[0].repo | Should -Be 'RepoOnlyB'
        $density.portfolioOnlyCandidates[0].catalogReviewNote | Should -Be 'Keep in README until explicit portfolio-only demotion is approved.'
        $density.portfolioOnlyCandidates[0].recommendation | Should -Be 'review-for-portfolio-only'
        $density.portfolioOnlyCandidates[0].reasonCodes | Should -Contain 'category-over-soft-limit'
        $density.portfolioOnlyCandidates[0].reasonCodes | Should -Contain 'low-signal-zero-star'
        $density.portfolioOnlyCandidates[0].reasonCodes | Should -Contain 'repo-only-action'
        $density.portfolioOnlyCandidates[0].reasonCodes | Should -Contain 'no-latest-release'
        $density.portfolioOnlyCandidates[0].reasonCodes | Should -Contain 'portfolio-route-available'
        $density.portfolioOnlyPreview.mode | Should -Be 'report-only'
        $density.portfolioOnlyPreview.status | Should -Be 'ready'
        $density.portfolioOnlyPreview.recommendation | Should -Be 'review-catalog-demotion'
        $density.portfolioOnlyPreview.candidateSource | Should -Be 'readmeDensity.portfolioOnlyCandidates'
        $density.portfolioOnlyPreview.candidateCount | Should -Be 2
        $density.portfolioOnlyPreview.candidateRepos | Should -Contain 'RepoOnlyA'
        $density.portfolioOnlyPreview.candidateRepos | Should -Contain 'RepoOnlyB'
        $density.portfolioOnlyPreview.currentProjectRowCount | Should -Be 2
        $density.portfolioOnlyPreview.previewProjectRowCount | Should -Be 0
        $density.portfolioOnlyPreview.projectRowDelta | Should -Be -2
        $density.portfolioOnlyPreview.resolvedOverSoftLimitCategoryCount | Should -Be 1
        $density.portfolioOnlyPreview.remainingOverSoftLimitCategoryCount | Should -Be 0
        $density.portfolioOnlyPreview.preservesPortfolioRoutes | Should -BeTrue
        $density.portfolioOnlyPreview.catalogMutated | Should -BeFalse
        $density.portfolioOnlyPreview.readmeMutated | Should -BeFalse
        $density.portfolioOnlyPreview.projectsFeedMutated | Should -BeFalse
        $density.portfolioOnlyPreview.note | Should -Match 'Report-only preview'
        $density.routingRecommendation | Should -Be 'review-portfolio-only-candidates'
        $density.warningCount | Should -BeGreaterThan 0
        ($density.warnings -join ' ') | Should -Match 'portfolio-only review'
        $powershellDensity = @($density.categoryRows | Where-Object { $_.category -eq 'powershell' })[0]
        $powershellDensity.overCategorySoftLimitBy | Should -Be 1
        $powershellDensity.portfolioOnlyCandidateCount | Should -Be 2
        $powershellDensity.routingRecommendation | Should -Be 'review-portfolio-only-candidates'
        $powershellPreview = @($density.portfolioOnlyPreview.categoryRows | Where-Object { $_.category -eq 'powershell' })[0]
        $powershellPreview.currentProjectCount | Should -Be 2
        $powershellPreview.previewProjectCount | Should -Be 0
        $powershellPreview.projectRowDelta | Should -Be -2
        $powershellPreview.currentOverSoftLimitBy | Should -Be 1
        $powershellPreview.previewOverSoftLimitBy | Should -Be 0
    }
    It 'reports generated artifact budgets without failing healthy artifacts' {
        $fixtureReadme = @'
one
two
<details>
```powershell
Write-Host ok
```
'@
        $budgets = Test-GeneratedArtifactBudgets `
            -ExpectedReadme $fixtureReadme `
            -ExpectedProjectsJson '{"projects":[]}' `
            -ExpectedAssets @{ 'assets/profile/test.svg' = '<svg><title>Test</title></svg>' } `
            -ReportJson '{"schema":"test"}'

        $budgets.status | Should -Be 'within-budget'
        $budgets.warningCount | Should -Be 0
        $budgets.rows.Count | Should -Be 10
        $readmeLineBudget = @($budgets.rows | Where-Object { $_.artifact -eq 'README.md' -and $_.metric -eq 'lines' })[0]
        $readmeLineBudget.value | Should -Be 6
        $readmeLineBudget.softLimit | Should -Be 1000
        $readmeLineBudget.overSoftLimit | Should -BeFalse
        $reportBudget = @($budgets.rows | Where-Object { $_.artifact -eq 'reports/profile-sync-report.json' -and $_.metric -eq 'bytes' })[0]
        $reportBudget.value | Should -Be ([System.Text.Encoding]::UTF8.GetByteCount('{"schema":"test"}'))
        $reportBudget.softLimit | Should -Be 114688
    }
    It 'warns when generated artifact budgets cross soft limits' {
        $largeReadme = (@('line') * 1001) -join "`n"
        $budgets = Test-GeneratedArtifactBudgets `
            -ExpectedReadme $largeReadme `
            -ExpectedProjectsJson '{"projects":[]}' `
            -ExpectedAssets @{} `
            -ReportJson '{}'

        $budgets.status | Should -Be 'warning'
        $budgets.warningCount | Should -BeGreaterThan 0
        ($budgets.warnings -join ' ') | Should -Match 'README.md lines'
    }
    It 'keeps the real projects feed under the public byte budget' {
        $cat = Get-Catalog -Path (Join-Path $script:RepoRoot 'data/profile-catalog.json')
        $projectsJson = New-ProjectsExportJson -Catalog $cat -Repos @()
        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($projectsJson)

        $projectsJson | Should -Not -Match "`n"
        $bytes | Should -BeLessOrEqual 512000
    }
    It 'summarizes rendered profile smoke reports and mobile render budgets' {
        $smoke = [pscustomobject]@{
            generatedAt = '2026-06-06T00:00:00Z'
            url = 'https://github.com/SysAdminDoc'
            passed = $true
            viewports = @(
                [pscustomobject]@{
                    name = 'desktop'
                    passed = $true
                    rootClientWidth = 846
                    rootOverflow = $false
                    documentOverflow = $false
                    failedImages = @()
                    missingSections = @()
                },
                [pscustomobject]@{
                    name = 'mobile'
                    passed = $true
                    rootClientWidth = 308
                    rootOverflow = $false
                    documentOverflow = $false
                    failedImages = @()
                    missingSections = @()
                }
            )
        }

        $summary = New-RenderedProfileSmokeSummary -SmokeReport $smoke

        $summary.status | Should -Be 'passed'
        $summary.source | Should -Be 'local-artifact'
        $summary.viewportCount | Should -Be 2
        $summary.passedViewportCount | Should -Be 2
        $summary.minimumRootClientWidth | Should -Be 308
        $summary.mobileRootClientWidth | Should -Be 308
        $summary.warningCount | Should -Be 0
    }

    It 'summarizes screenshot paths and first-viewport component evidence' {
        $viewports = foreach ($viewportName in @('desktop', 'mobile')) {
            foreach ($theme in @('dark', 'light')) {
                [pscustomobject]@{
                    name = $viewportName
                    theme = $theme
                    passed = $true
                    screenshotPath = "reports/rendered-profile-smoke-$viewportName-$theme.png"
                    rootClientWidth = if ($viewportName -eq 'mobile') { 308 } else { 846 }
                    rootOverflow = $false
                    documentOverflow = $false
                    failedImages = @()
                    missingSections = @()
                    componentPresence = [pscustomobject]@{
                        header = 1
                        toolCatalog = 1
                        footer = 1
                    }
                    firstViewportComponentPresence = [pscustomobject]@{
                        header = 1
                        navigation = 1
                        startHere = 1
                        toolCatalog = 0
                        footer = 0
                    }
                    blankPage = $false
                    croppedElementCount = 0
                    overlapWarningCount = 0
                }
            }
        }
        $smoke = [pscustomobject]@{
            generatedAt = '2026-06-06T00:00:00Z'
            url = 'https://github.com/SysAdminDoc'
            passed = $true
            viewports = @($viewports)
        }

        $summary = New-RenderedProfileSmokeSummary -SmokeReport $smoke

        $summary.status | Should -Be 'passed'
        $summary.viewportCount | Should -Be 4
        $summary.screenshotCount | Should -Be 4
        $summary.screenshotPaths | Should -Contain 'reports/rendered-profile-smoke-desktop-dark.png'
        $summary.firstViewportHeaderCount | Should -Be 4
        $summary.firstViewportStartHereCount | Should -Be 4
        $summary.toolCatalogPresenceCount | Should -Be 4
        $summary.footerPresenceCount | Should -Be 4
        $summary.blankViewportCount | Should -Be 0
        $summary.croppedElementCount | Should -Be 0
        $summary.overlapWarningCount | Should -Be 0
        $summary.warningCount | Should -Be 0
    }

    It 'summarizes rendered README accessibility evidence and desktop/mobile outcomes' {
        $viewports = @(
            [pscustomobject]@{
                name = 'desktop'
                passed = $true
                detailsCount = 2
                detailsSummaryCount = 2
                detailsKeyboardSanity = [pscustomobject]@{
                    detailCount = 2
                    collapsedFocusPassCount = 2
                    expandedFocusPassCount = 2
                    activationPassCount = 2
                    failedCount = 0
                    passed = $true
                }
                tableCount = 4
                tableOverflowCount = 0
                linkCount = 12
                linkLabelCount = 12
                uniqueLinkLabelCount = 9
                duplicateLinkLabelCount = 3
                actionableLinkCount = 12
                uniqueActionableLinkLabelCount = 9
                emptyLinkLabelCount = 0
                nonActionableLinkCount = 0
                linkLabelSanityPassed = $true
            },
            [pscustomobject]@{
                name = 'mobile'
                passed = $false
                detailsCount = 2
                detailsSummaryCount = 1
                detailsKeyboardSanity = [pscustomobject]@{
                    detailCount = 2
                    collapsedFocusPassCount = 1
                    expandedFocusPassCount = 1
                    activationPassCount = 1
                    failedCount = 1
                    passed = $false
                }
                tableCount = 4
                tableOverflowCount = 1
                linkCount = 12
                linkLabelCount = 11
                uniqueLinkLabelCount = 8
                duplicateLinkLabelCount = 3
                actionableLinkCount = 11
                uniqueActionableLinkLabelCount = 8
                emptyLinkLabelCount = 1
                nonActionableLinkCount = 0
                linkLabelSanityPassed = $false
            }
        )
        $smoke = [pscustomobject]@{
            generatedAt = '2026-06-06T00:00:00Z'
            url = 'https://github.com/SysAdminDoc'
            passed = $false
            viewports = $viewports
        }

        $summary = New-RenderedProfileSmokeSummary -SmokeReport $smoke

        $summary.accessibilityEvidenceAvailable | Should -BeTrue
        $summary.detailsCount | Should -Be 4
        $summary.detailsSummaryCount | Should -Be 3
        $summary.detailsKeyboardCheckCount | Should -Be 4
        $summary.detailsKeyboardPassedCount | Should -Be 3
        $summary.detailsKeyboardFailedCount | Should -Be 1
        $summary.detailsCollapsedFocusPassCount | Should -Be 3
        $summary.detailsExpandedFocusPassCount | Should -Be 3
        $summary.detailsActivationPassCount | Should -Be 3
        $summary.detailsKeyboardSanityPassed | Should -BeFalse
        $summary.tableCount | Should -Be 8
        $summary.tableOverflowCount | Should -Be 1
        $summary.uniqueLinkLabelCount | Should -Be 17
        $summary.actionableLinkCount | Should -Be 23
        $summary.uniqueActionableLinkLabelCount | Should -Be 17
        $summary.emptyLinkLabelCount | Should -Be 1
        $summary.linkLabelSanityPassed | Should -BeFalse
        $summary.desktopPassedCount | Should -Be 1
        $summary.desktopFailedCount | Should -Be 0
        $summary.mobilePassedCount | Should -Be 0
        $summary.mobileFailedCount | Should -Be 1
        $summary.warningCount | Should -BeGreaterThan 0
        # A table scrolling inside a page that does not overflow is how GitHub renders wide
        # Markdown tables on phones, so it is recorded but not warned about.
        $summary.tableOverflowDisposition | Should -Be 'contained-table-scroll'
        ($summary.warnings -join ' ') | Should -Not -Match 'table overflow'
        ($summary.warnings -join ' ') | Should -Match 'accessible label'
        ($summary.warnings -join ' ') | Should -Match 'keyboard/focus sanity'
    }

    It 'sums link names that lead to more than one place over the viewports' {
        $smoke = [pscustomobject]@{
            generatedAt = '2026-06-06T00:00:00Z'
            url = 'https://github.com/SysAdminDoc'
            passed = $true
            viewports = @(
                [pscustomobject]@{ name = 'desktop'; passed = $true; linkLabelCount = 3; ambiguousCrossDestinationLinkLabelCount = 2 },
                [pscustomobject]@{ name = 'mobile'; passed = $true; linkLabelCount = 3; ambiguousCrossDestinationLinkLabelCount = 1 }
            )
        }

        (New-RenderedProfileSmokeSummary -SmokeReport $smoke).ambiguousCrossDestinationLinkLabelCount | Should -Be 3
        (New-RenderedProfileSmokeSummary -SmokeReport $null).ambiguousCrossDestinationLinkLabelCount | Should -Be 0
    }

    It 'warns about table overflow only when the page itself overflows horizontally' {
        $makeViewport = {
            param([bool]$PageOverflow)
            [pscustomobject]@{
                name = 'mobile'
                passed = $true
                rootOverflow = $PageOverflow
                documentOverflow = $false
                detailsCount = 1
                detailsSummaryCount = 1
                tableCount = 4
                tableOverflowCount = 2
                linkCount = 4
                linkLabelCount = 4
                uniqueLinkLabelCount = 4
                duplicateLinkLabelCount = 0
                actionableLinkCount = 4
                uniqueActionableLinkLabelCount = 4
                emptyLinkLabelCount = 0
                nonActionableLinkCount = 0
                linkLabelSanityPassed = $true
            }
        }

        $contained = New-RenderedProfileSmokeSummary -SmokeReport ([pscustomobject]@{
                generatedAt = '2026-08-20T00:00:00Z'
                url = 'https://github.com/SysAdminDoc'
                passed = $true
                viewports = @((& $makeViewport $false))
            })
        $broken = New-RenderedProfileSmokeSummary -SmokeReport ([pscustomobject]@{
                generatedAt = '2026-08-20T00:00:00Z'
                url = 'https://github.com/SysAdminDoc'
                passed = $true
                viewports = @((& $makeViewport $true))
            })

        $contained.tableOverflowCount | Should -Be 2
        $contained.tableOverflowDisposition | Should -Be 'contained-table-scroll'
        ($contained.warnings -join ' ') | Should -Not -Match 'table overflow'

        $broken.tableOverflowDisposition | Should -Be 'page-overflow'
        ($broken.warnings -join ' ') | Should -Match 'table overflow'
    }

    It 'warns on rendered smoke overflow and narrow mobile root width' {
        $smoke = [pscustomobject]@{
            generatedAt = '2026-06-06T00:00:00Z'
            url = 'https://github.com/SysAdminDoc'
            passed = $false
            viewports = @(
                [pscustomobject]@{
                    name = 'mobile'
                    passed = $false
                    rootClientWidth = 280
                    rootOverflow = $true
                    documentOverflow = $false
                    failedImages = @([pscustomobject]@{ src = 'missing.png' })
                    missingSections = @('Start Here')
                    componentPresence = [pscustomobject]@{
                        header = 0
                        toolCatalog = 0
                        footer = 0
                    }
                    firstViewportComponentPresence = [pscustomobject]@{
                        header = 0
                        navigation = 0
                        startHere = 0
                        toolCatalog = 0
                        footer = 0
                    }
                    blankPage = $true
                    croppedElementCount = 2
                    overlapWarningCount = 3
                }
            )
        }

        $summary = New-RenderedProfileSmokeSummary -SmokeReport $smoke

        $summary.status | Should -Be 'warning'
        $summary.failedViewportCount | Should -Be 1
        $summary.failedImageCount | Should -Be 1
        $summary.missingSectionCount | Should -Be 1
        $summary.overflowCount | Should -Be 1
        $summary.blankViewportCount | Should -Be 1
        $summary.croppedElementCount | Should -Be 2
        $summary.overlapWarningCount | Should -Be 3
        $summary.warningCount | Should -BeGreaterThan 0
        ($summary.warnings -join ' ') | Should -Match 'below the 300 px budget'
        ($summary.warnings -join ' ') | Should -Match 'blank viewport'
        ($summary.warnings -join ' ') | Should -Match 'cropped element'
        ($summary.warnings -join ' ') | Should -Match 'overlap warning'
    }
    It 'summarizes skipped rendered smoke artifacts with an explicit reason' {
        $smoke = [pscustomobject]@{
            generatedAt = '2026-06-06T00:00:00Z'
            url = 'https://github.com/SysAdminDoc'
            passed = $false
            skipped = $true
            skipReason = 'Chrome was not found'
            viewports = @()
        }

        $summary = New-RenderedProfileSmokeSummary -SmokeReport $smoke

        $summary.status | Should -Be 'not-run'
        $summary.source | Should -Be 'local-artifact'
        $summary.viewportCount | Should -Be 0
        $summary.skipReason | Should -Be 'Chrome was not found'
        $summary.warningCount | Should -Be 1
        ($summary.warnings -join ' ') | Should -Match 'Chrome was not found'
    }
    It 'reports missing rendered smoke artifacts as local collection gaps' {
        $summary = New-RenderedProfileSmokeSummary -SmokeReport $null -SourcePath 'reports/rendered-profile-smoke.json'

        $summary.status | Should -Be 'not-run'
        $summary.source | Should -Be 'missing-local-artifact'
        $summary.sourcePath | Should -Be 'reports/rendered-profile-smoke.json'
        $summary.skipReason | Should -Match 'Local rendered smoke artifact was not found'
        $summary.warningCount | Should -Be 1
    }
    It 'reports the generated catalog notice in README experience checks' {
        $result = Test-ReadmeExperience -Catalog $script:cat -Repos @() -ExpectedReadme $script:rendered
        $result.generatedCatalogNotice | Should -BeTrue
        $result.startHereSection | Should -BeFalse
        $result.catalogSnapshotSection | Should -BeFalse
        $result.setupInspectPath | Should -BeTrue
        $result.plainTextTagline | Should -BeFalse
        # Only the SVG header could set these, and the generator no longer renders one.
        $result.Keys | Should -Not -Contain 'themeAwareImageChrome'
        $result.Keys | Should -Not -Contain 'meaningfulImageAltText'
        $result.minimalProfileHeader | Should -BeTrue
        $result.richProfileHeader | Should -BeFalse
        $result.genericImageAltTextCount | Should -Be 0
        $result.thirdPartyMetricHostCount | Should -Be 0
        $result.thirdPartyBadgeHostCount | Should -Be 0
        $result.thirdPartyRenderHostCount | Should -Be 0
        $result.thirdPartyRenderHosts | Should -BeNullOrEmpty
        $result.motionSafeChrome | Should -BeTrue
        $result.motionPatternCount | Should -Be 0
        $result.profileStatsChromeCount | Should -Be 0
        $result.featuredPrimaryActions | Should -BeFalse
        $result.currentlyBuildingActionColumn | Should -BeTrue
        $result.passed | Should -BeTrue
    }

    It 'fails the header contract for a README that still carries the old SVG header' {
        # The header the generator rendered before the README went text-only.
        $oldHeader = @'
<p align="center">
  <img src="assets/profile/header-dark.svg#gh-dark-mode-only" alt="SysAdminDoc public tools command center profile header" />
  <img src="assets/profile/header-light.svg#gh-light-mode-only" alt="SysAdminDoc public tools command center profile header" />
</p>

<p align="center">Windows utilities, Android apps, browser extensions, web tools, media workflows, and generated validation evidence</p>

**[View full portfolio](https://portfolio.getparkerai.com/)**

'@
        $result = Test-ReadmeExperience -Catalog $script:cat -Repos @() -ExpectedReadme ($oldHeader + $script:rendered)

        $result.richProfileHeader | Should -BeTrue
        $result.plainTextTagline | Should -BeTrue
        $result.minimalProfileHeader | Should -BeFalse
        $result.passed | Should -BeFalse
    }

    It 'fails README experience checks for auto-starting profile motion patterns' {
        $animatedReadme = $script:rendered + [Environment]::NewLine + @'
<p align="center"><img src="https://readme-typing-svg.demolab.com?duration=4000&repeat=true" alt="Animated typing line" /></p>
<p align="center"><img src="https://capsule-render.vercel.app/api?animation=fadeIn" alt="Animated header" /></p>
'@

        $result = Test-ReadmeExperience -Catalog $script:cat -Repos @() -ExpectedReadme $animatedReadme

        $result.motionSafeChrome | Should -BeFalse
        $result.motionPatternCount | Should -BeGreaterOrEqual 3
        $result.thirdPartyRenderHosts | Should -Contain 'readme-typing-svg.demolab.com'
        $result.thirdPartyRenderHosts | Should -Contain 'capsule-render.vercel.app'
        $result.passed | Should -BeFalse
    }
}

Describe 'Update-Header idempotency' {
    It 'produces identical output when run twice on the same input' {
        $first = Update-Header
        $second = Update-Header

        $second | Should -Be $first
    }

    It 'produces a minimal text-only header with no image chrome' {
        $result = Update-Header -Header (New-TestProfileHeader)

        $result | Should -Not -Match 'assets/profile/header-(dark|light)\.svg'
        $result | Should -Not -Match '<img[^>]*assets/profile/'
        [regex]::Matches($result, '<img\b').Count | Should -Be 1 -Because 'only the support image is expected'
        $result | Should -Match 'support\.example\.test/button\.png'
        $result | Should -Match 'More about the fixture'
        $result | Should -Not -Match 'AI service overview'
        $result | Should -Match 'Fixture tagline for the header\.'
        $result | Should -Match '<a href="#powershell-system-utilities">PowerShell</a>'
        $result | Should -Not -Match 'Professional Focus|Public portfolio: 100 active repos'
    }
}

Describe 'README separators' {
    It 'joins its parts with middots, never a double hyphen or a dash' {
        # A double hyphen or an em or en dash between a name and its description reads as a
        # dash substitute; the page uses &middot; the way its header and footer already do.
        $readme = New-Readme -Catalog (Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')) -Repos @()

        $readme | Should -Not -Match ' -- '
        $readme.IndexOf([char]0x2014) | Should -Be -1
        $readme.IndexOf([char]0x2013) | Should -Be -1
        $readme | Should -Match '(?m)^<summary><b>.+?</b> &middot; \d+ repos &middot; <i>'
        $readme | Should -Match '(?m)^\[\*\*WinTool\*\*\]\([^)]+\) &middot; '
    }

    It 'seeds a catalog from rows written with a middot or the old double hyphen' {
        $rendered = New-Readme -Catalog (Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')) -Repos @()
        foreach ($variant in @('middot', 'hyphens')) {
            $text = if ($variant -eq 'middot') { $rendered } else { [regex]::Replace($rendered, '(?m)^(\[\*\*.+?\*\*\]\([^)]+\)(?: &#11088;\d+)?) &middot; ', '$1 -- ') }
            $ReadmePath = Join-Path $TestDrive "seed-$variant.md"
            [System.IO.File]::WriteAllText($ReadmePath, $text)

            $seeded = New-CatalogFromReadme -Repos @()

            @($seeded.entries | ForEach-Object { [string]$_.repo }) | Should -Contain 'WinTool' -Because "rows use $variant"
        }
    }

    It 'seeds a catalog from a fixed legacy README with each row separator and a long install block' {
        # The row test above renders and parses with the same code, so it can't show the parser
        # still reads what older READMEs actually held: rows joined with " -- ", an em dash or
        # &middot;, and the clone-and-run block that named the branch and entry script.
        $ReadmePath = Join-Path $TestDrive 'legacy-fixed.md'
        $lines = @(
            '<summary><b>&#9889; PowerShell System Utilities</b></summary>'
            ''
            '[**HyphenTool**](https://github.com/SysAdminDoc/HyphenTool) &#11088;3 -- Joined with two hyphens'
            ('[**DashTool**](https://github.com/SysAdminDoc/DashTool) &#11088;2 ' + [char]0x2014 + ' Joined with an em dash')
            '[**DotTool**](https://github.com/SysAdminDoc/DotTool) &middot; Joined with a middot'
            '```powershell'
            '$d = "$env:TEMP\DotTool"; git clone -q --depth 1 -b develop https://github.com/SysAdminDoc/DotTool $d; & "$d\Start-DotTool.ps1"'
            '```'
            ''
            '| [**ZipXpiTool**](https://github.com/SysAdminDoc/ZipXpiTool) | An extension | [<kbd>ZIP/XPI</kbd>](https://github.com/SysAdminDoc/ZipXpiTool/releases/latest) |'
            '| [**XpiTool**](https://github.com/SysAdminDoc/XpiTool) | An add-on | [<kbd>XPI</kbd>](https://github.com/SysAdminDoc/XpiTool/releases/latest) |'
        )
        [System.IO.File]::WriteAllText($ReadmePath, ($lines -join "`n") + "`n")

        $seeded = @(New-CatalogFromReadme -Repos @() 3>$null) | Select-Object -Last 1
        $byRepo = @{}
        foreach ($entry in @($seeded.entries)) { $byRepo[[string]$entry.repo] = $entry }

        (@($byRepo.Keys | Sort-Object) -join ',') | Should -BeOrdinal 'DashTool,DotTool,HyphenTool,XpiTool,ZipXpiTool'
        # A ZIP/XPI release seeded as xpi, which isn't a catalog kind; a bare XPI is a download.
        $byRepo['ZipXpiTool'].downloadKind | Should -BeOrdinal 'zip-xpi'
        $byRepo['XpiTool'].downloadKind | Should -BeOrdinal 'download'
        $byRepo['HyphenTool'].descriptionOverride | Should -BeOrdinal 'Joined with two hyphens'
        $byRepo['DashTool'].descriptionOverride | Should -BeOrdinal 'Joined with an em dash'
        $byRepo['DotTool'].descriptionOverride | Should -BeOrdinal 'Joined with a middot'
        $byRepo['DotTool'].category | Should -BeOrdinal 'powershell'
        $byRepo['DotTool'].branch | Should -BeOrdinal 'develop'
        $byRepo['DotTool'].entrypoint | Should -BeOrdinal 'Start-DotTool.ps1'
        $byRepo['DotTool'].installKind | Should -BeOrdinal 'powershell'
    }

    It 'says what a README of Start-Tool install lines can''t give back' {
        # Review of f4e88e5: Start-Tool <Name> names the tool and nothing else, so seeding from
        # today's README recovered no entry script and no branch, and said nothing about it.
        $rendered = New-Readme -Catalog (Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')) -Repos @()
        $ReadmePath = Join-Path $TestDrive 'seed-start-tool.md'
        [System.IO.File]::WriteAllText($ReadmePath, $rendered)
        $rendered | Should -Match 'Start-Tool ' -Because 'the fixture README has to hold Start-Tool lines for this to test anything'

        $output = @(New-CatalogFromReadme -Repos @() 3>&1)
        $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })

        $warnings | Should -HaveCount 1
        $warnings[0] | Should -Match 'Start-Tool'
        $warnings[0] | Should -Match 'entry script'
        $warnings[0] | Should -Match 'branch'
        $warnings[0] | Should -Match 'projects\.json'
    }

    It 'seeds a catalog from the committed README that passes the shape check' {
        # Review of 5149e12: a ZIP/XPI download seeded as xpi, which isn't a catalog kind, so
        # -SeedCatalog -ForceSeedCatalog -Write on the committed README wrote a catalog that
        # failed its own check.
        $ReadmePath = Join-Path $script:RepoRoot 'README.md'

        $seeded = @(New-CatalogFromReadme -Repos @() 3>$null) | Select-Object -Last 1

        @($seeded.entries).Count | Should -BeGreaterThan 100
        @((Test-CatalogShape -Catalog $seeded).issues | ForEach-Object { '{0} {1}: {2}' -f $_.repo, $_.field, $_.reason }) | Should -BeNullOrEmpty
    }
}

Describe 'Catalog URLs and names cannot break a README row' {
    It 'refuses a <Field> that could <Case>' -ForEach @(
        @{ Field = 'liveUrl'; Case = 'start a new table row'; Url = "https://sysadmindoc.github.io/demo`n| [**Injected**](https://evil.example/) | planted row | x |" }
        @{ Field = 'liveUrl'; Case = 'split its table cell'; Url = 'https://example.test/a|b' }
        @{ Field = 'userscriptUrl'; Case = 'leave its link destination'; Url = 'https://example.test/x.user.js) [Evil](https://evil.example/' }
        @{ Field = 'userscriptUrl'; Case = 'end an HTML attribute'; Url = 'https://example.test/x".user.js' }
    ) {
        $entry = New-TestEntry -Repo 'UrlTool' -Category 'web'
        $entry[$Field] = $Url

        $issues = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq $Field })

        $issues | Should -HaveCount 1
        $issues[0].repo | Should -Be 'UrlTool'
        $issues[0].value | Should -Not -Match '[\r\n]' -Because 'the issue itself stays on one line'
    }

    It 'leaves plain http to the URL scheme check, so each gate has one reason' {
        $entry = New-TestEntry -Repo 'UrlTool' -Category 'web'
        $entry.liveUrl = 'http://example.test/app/'

        @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq 'liveUrl' }) | Should -BeNullOrEmpty
        @(Test-CatalogUrlSchemes -Entries @($entry)) | Should -HaveCount 1
    }

    It 'accepts every action URL in the published catalog' {
        $catalog = Get-Catalog -Path (Join-Path $script:RepoRoot 'data/profile-catalog.json')

        @((Test-CatalogShape -Catalog $catalog).issues | Where-Object { $_.field -in @('liveUrl', 'userscriptUrl') }) | Should -BeNullOrEmpty
    }

    It 'percent-encodes a pipe and a backslash in an action link' {
        $entry = New-TestEntry -Repo 'WebTool' -Category 'web'
        $entry.liveUrl = 'https://example.test/a|b\c'

        Get-ActionLink -Entry $entry -Meta $null -Category 'web' | Should -BeOrdinal '<a href="https://example.test/a%7Cb%5Cc" aria-label="Launch WebTool">Launch</a>'
    }

    It 'percent-encodes a line break in an action link, whatever the catalog check said' {
        $entry = New-TestEntry -Repo 'WebTool' -Category 'web'
        $entry.liveUrl = "https://example.test/a`r`n| [**Injected**](https://evil.example/) |"

        Get-ActionLink -Entry $entry -Meta $null -Category 'web' | Should -BeOrdinal '<a href="https://example.test/a%0D%0A%7C%20[**Injected**]%28https://evil.example/%29%20%7C" aria-label="Launch WebTool">Launch</a>'
    }

    It 'percent-encodes a C1 control in an action link as its UTF-8 bytes' {
        # Only C0 and DEL were encoded, so U+0085, a line break to some readers, went in raw.
        $entry = New-TestEntry -Repo 'WebTool' -Category 'web'
        $entry.liveUrl = 'https://example.test/a' + [char]0x85 + 'b' + [char]0x9B + 'c' + [char]0x7F

        Get-ActionLink -Entry $entry -Meta $null -Category 'web' | Should -BeOrdinal '<a href="https://example.test/a%C2%85b%C2%9Bc%7F" aria-label="Launch WebTool">Launch</a>'
    }

    It 'holds <Field> to the schema''s case: <Value>' -ForEach @(
        @{ Field = 'category'; Value = 'PowerShell'; Valid = $false }
        @{ Field = 'category'; Value = 'misc'; Valid = $true }
        @{ Field = 'downloadKind'; Value = 'APK'; Valid = $false }
        @{ Field = 'downloadKind'; Value = 'apk'; Valid = $true }
        @{ Field = 'installKind'; Value = 'PowerShell'; Valid = $false }
        @{ Field = 'installKind'; Value = 'python'; Valid = $true }
    ) {
        # These compared case-insensitively (installKind not at all without an entry script),
        # and -Write copied the value into projects.json as written, past the schema's enum.
        $entry = New-TestEntry -Repo 'CaseTool' -Category 'misc'
        $entry[$Field] = $Value

        $issues = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq $Field })

        $issues.Count -eq 0 | Should -Be $Valid
    }

    It 'refuses <Case> in public text' -ForEach @(
        @{ Case = 'an em dash'; Text = 'Fast' + [char]0x2014 + 'and small'; Dash = 'U+2014' }
        @{ Case = 'an en dash'; Text = 'Pages 1' + [char]0x2013 + '2'; Dash = 'U+2013' }
        @{ Case = 'a spaced double hyphen'; Text = 'Fast -- and small'; Dash = ' -- ' }
        @{ Case = 'nothing for a hyphenated word'; Text = 'A well-known tool'; Dash = $null }
        @{ Case = 'nothing for an option'; Text = 'Run it with --help first'; Dash = $null }
        @{ Case = 'nothing for a range written out'; Text = 'Pages 1 to 2'; Dash = $null }
        # Review G2 of fb91747: each of these passed.
        @{ Case = 'a spaced single hyphen'; Text = 'Fast - and small'; Dash = ' - ' }
        @{ Case = 'a double hyphen between words'; Text = 'Fast--and small'; Dash = '--' }
        @{ Case = 'three hyphens'; Text = 'Fast --- and small'; Dash = '---' }
        @{ Case = 'a double hyphen spaced with NBSP'; Text = 'Fast' + [char]0xA0 + '--' + [char]0xA0 + 'and small'; Dash = '{U+00A0}--{U+00A0}' }
        @{ Case = 'a horizontal bar'; Text = 'Fast' + [char]0x2015 + 'and small'; Dash = 'U+2015' }
        @{ Case = 'a two-em dash'; Text = 'Fast' + [char]0x2E3A + 'and small'; Dash = 'U+2E3A' }
        @{ Case = 'a three-em dash'; Text = 'Fast' + [char]0x2E3B + 'and small'; Dash = 'U+2E3B' }
        @{ Case = 'a small em dash'; Text = 'Fast' + [char]0xFE58 + 'and small'; Dash = 'U+FE58' }
        @{ Case = 'nothing for a minus sign'; Text = 'Returns x ' + [char]0x2212 + ' 1'; Dash = $null }
        @{ Case = 'nothing for a range with a hyphen'; Text = 'Pages 1-2'; Dash = $null }
        @{ Case = 'nothing for a negative number'; Text = 'Offsets down to -5'; Dash = $null }
    ) {
        # The separator change took " -- " out of the generated rows, but catalog text could
        # still carry any dash into the README.
        $entry = New-TestEntry -Repo 'DashTool' -Category 'misc'
        $entry.descriptionOverride = $Text

        $issues = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq 'descriptionOverride' })

        if ($Dash) {
            $issues | Should -HaveCount 1
            $issues[0].value | Should -Be $Dash
            $issues[0].reason | Should -Match 'joins clauses with a dash'
        } else {
            $issues | Should -BeNullOrEmpty
        }
    }

    It 'writes each character a reader could not see in an issue as its code point' {
        $text = 'Win' + [char]0x200B + 'Tool' + [char]0x202E + ' a' + [char]0x00A0 + 'b' + "`t" + [char]::ConvertFromUtf32(0xE0041) + [char]0xD800 + ' ok ' + [char]::ConvertFromUtf32(0x1F600) + [char]0x2065

        ConvertTo-VisibleIssueText $text | Should -BeExactly ('Win{U+200B}Tool{U+202E} a{U+00A0}b{U+0009}{U+E0041}{U+D800} ok ' + [char]::ConvertFromUtf32(0x1F600) + '{U+2065}')
        ConvertTo-VisibleIssueText 'plain text stays' | Should -BeOrdinal 'plain text stays'
    }

    It 'shows invisible characters in the <Field> issue by code point' -ForEach @(
        @{ Field = 'repo'; Value = 'Win' + [char]0x200B + [char]0x202E + 'Tool' }
        @{ Field = 'id'; Value = 'abc' + [char]0x200B + 'def' }
        @{ Field = 'aliases'; Value = 'Old' + [char]0x200B + 'Name' }
        @{ Field = 'aliasOf'; Value = 'Up' + [char]0x200B + 'stream' }
        @{ Field = 'category'; Value = 'mi' + [char]0x200B + 'sc' }
        @{ Field = 'downloadKind'; Value = 'zi' + [char]0x200B + 'p' }
        @{ Field = 'entrypoint'; Value = 'too' + [char]0x200B + 'l.ps1' }
        @{ Field = 'installKind'; Value = 'power' + [char]0x200B + 'shell'; Entrypoint = 'tool.ps1' }
        @{ Field = 'installKind'; Value = 'py' + [char]0x200B + 'thon' }
        @{ Field = 'branch'; Value = 'ma' + [char]0x200B + 'in' }
        @{ Field = 'forkOf'; Value = 'owner/re' + [char]0x200B + 'po' }
        @{ Field = 'liveUrl'; Value = 'https://x.invalid/a' + [char]0x200B + [char]0x202E }
    ) {
        # These issue values carried the text as written, so a zero-width space, a bidi mark
        # or an override went into the report, where it hides or reorders what it says.
        $entry = New-TestEntry -Repo 'CleanTool' -Category 'misc'
        if ($Field -eq 'aliases') { $entry.aliases = @($Value) } else { $entry[$Field] = $Value }
        if ($_.ContainsKey('Entrypoint')) { $entry.entrypoint = $_.Entrypoint }

        $issues = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues)

        (@($issues | Where-Object { $_.field -eq $Field } | ForEach-Object { $_.value }) -join ' ') | Should -Match '\{U\+200B\}'
        foreach ($issue in $issues) {
            foreach ($key in 'repo', 'value', 'reason') {
                if ($null -ne $issue[$key]) {
                    ConvertTo-VisibleIssueText ([string]$issue[$key]) | Should -BeExactly ([string]$issue[$key]) -Because "the $($issue.field) issue's $key holds nothing a reader can't see"
                }
            }
        }
    }

    It 'shows invisible characters in a reason that quotes a name' {
        $name = 'Dup' + [char]0x200B + 'Tool'
        $first = New-TestEntry -Repo $name -Category 'misc'
        $second = New-TestEntry -Repo $name -Category 'misc'

        $duplicate = @((Test-CatalogShape -Catalog @{ entries = @($first, $second) }).issues | Where-Object { $_.reason -like 'duplicate repo*' })

        $duplicate | Should -HaveCount 1
        $duplicate[0].reason | Should -BeOrdinal 'duplicate repo also appears as Dup{U+200B}Tool'
        $duplicate[0].repo | Should -BeOrdinal 'Dup{U+200B}Tool'
    }

    It 'gives language the one-line check' {
        $entry = New-TestEntry -Repo 'LangTool' -Category 'powershell'
        $entry.language = "C#`nEvil" + [char]0x202E

        $issues = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq 'language' })

        $issues | Should -HaveCount 1
        $issues[0].value | Should -BeOrdinal 'U+000A'
    }

    It 'ends repository names and ids at the true end of text' {
        Test-SafeGitHubName -Name "WinTool`n" | Should -BeFalse
        Test-SafeGitHubName -Name 'WinTool' | Should -BeTrue
        $entry = New-TestEntry -Repo 'IdTool' -Category 'powershell'
        foreach ($id in @("id-tool`n", 'ID-TOOL')) {
            $entry.id = $id
            @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq 'id' }) | Should -HaveCount 1 -Because "'$id' is not a valid id"
        }
        $entry.id = 'id-tool'
        @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq 'id' }) | Should -BeNullOrEmpty
    }

    It 'holds names and catalog URLs to the same shapes in the catalog schema' {
        $payload = ConvertFrom-JsonPreservingArrays -Json ([System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'data/profile-catalog.json')))
        $entry = @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name 'entries'))[0]
        Set-MemberValue -Object $entry -Name 'repo' -Value "WinTool`n"
        Set-MemberValue -Object $entry -Name 'liveUrl' -Value 'https://example.test/a|b'

        $locations = @((Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-catalog.v1.json').errors | ForEach-Object { $_.instanceLocation })

        $locations | Should -Contain '/entries/0/repo'
        $locations | Should -Contain '/entries/0/liveUrl'
    }

    It 'holds the feed''s branch to the catalog''s branch shape' {
        # The branch in the feed can come from GitHub's default branch, which the catalog
        # check never sees; run.ps1 passes it to git clone -b.
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = ConvertFrom-JsonPreservingArrays -Json (New-ProjectsExportJson -Catalog $cat -Repos @())
        $project = @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name 'projects'))[0]
        Set-MemberValue -Object $project -Name 'branch' -Value 'x$(Write-Output INJECTED)'

        $result = Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-projects.v1.json'

        @($result.errors | Where-Object { $_.instanceLocation -eq '/projects/0/branch' }) | Should -HaveCount 1
    }

    It 'holds forkOf to owner/repo like its schema: <ForkOf>' -ForEach @(
        @{ ForkOf = 'upstream-owner/WebTool|x'; Valid = $false }
        @{ ForkOf = "upstream-owner/WebTool`n"; Valid = $false }
        @{ ForkOf = 'upstream owner/WebTool'; Valid = $false }
        @{ ForkOf = 'upstream-owner/..'; Valid = $false }
        @{ ForkOf = 'upstream-owner/WebTool/tree'; Valid = $false }
        @{ ForkOf = 'upstream_owner/WebTool'; Valid = $false }
        @{ ForkOf = 'upstream-owner/Web.Tool_2'; Valid = $true }
        # The schema's length and non-blank rules as well as its pattern.
        @{ ForkOf = ''; Valid = $false }
        @{ ForkOf = '   '; Valid = $false }
        @{ ForkOf = [string][char]0x00A0; Valid = $false }
        @{ ForkOf = 'o/' + ('r' * 138); Valid = $true }
        @{ ForkOf = 'o/' + ('r' * 139); Valid = $false }
    ) {
        # -Write alone runs only the shape check, and the fork link lands in a table cell.
        $entry = New-TestEntry -Repo 'WebTool' -Category 'web'
        $entry.forkOf = $ForkOf

        $payload = ConvertFrom-JsonPreservingArrays -Json ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/catalog.json')))
        Set-MemberValue -Object @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name 'entries'))[0] -Name 'forkOf' -Value $ForkOf

        $issues = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.field -eq 'forkOf' })
        $schemaErrors = @((Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-catalog.v1.json').errors |
            Where-Object { $_.instanceLocation -eq '/entries/0/forkOf' })

        # One issue per bad value: a line break is the one-line rule's, the rest the shape's.
        $issues | Should -HaveCount $(if ($Valid) { 0 } else { 1 })
        # The same verdict as the schema's own pattern.
        $schemaErrors.Count -eq 0 | Should -Be $Valid
    }

    It 'shows a forkOf that isn''t owner/repo as text, not a link' {
        $entry = New-TestEntry -Repo 'WebTool' -Category 'web'
        $entry.forkOf = 'upstream-owner/WebTool|x'

        $attribution = Get-UpstreamAttribution $entry

        $attribution | Should -Be '<br/><sub>Upstream: upstream-owner/WebTool\|x</sub>'
        $entry.forkOf = 'upstream-owner/WebTool'
        Get-UpstreamAttribution $entry | Should -Be '<br/><sub>Upstream: [upstream-owner/WebTool](https://github.com/upstream-owner/WebTool)</sub>'
    }
}

Describe 'Profile header comes from catalog data' {
    It 'renders the tagline, languages, about text, links and support button from the catalog' {
        $result = (Update-Header -Header (New-TestProfileHeader) -CategorySlugs @('powershell')) -replace "`r`n", "`n"

        $result | Should -Match '^<p align="center"><b>Fixture tagline for the header\.</b><br/><sub>PowerShell &middot; Python</sub></p>'
        $result | Should -Match '(?m)^## Hi, fixture here$'
        $result | Should -Match '(?m)^Fixture about text\.$'
        # One deliberate outbound call to action, not a pair of competing links.
        [regex]::Matches($result, '(?m)^<p align="center"><a href="https://fixture\.example\.test/about/"><b>More about the fixture &#8594;</b></a></p>$').Count | Should -Be 1
        $result | Should -Match '<a href="https://support\.example\.test/fixture">\s*<img height="36" src="https://support\.example\.test/button\.png" alt="Support the fixture" />\s*</a>'
    }

    It 'encodes header text for the HTML or Markdown it lands in' {
        $header = New-TestProfileHeader
        $header.tagline = 'Tools & <scripts> "quoted"'
        $header.languages = @('C#', '<script>')
        $header.heading = 'Hi | [there]'
        $header.about = 'A [link](https://evil.example/) and <b>bold</b>'
        $header.links = @(@{ text = 'Read "more" <now>'; url = 'https://fixture.example.test/about/' })
        $header.support.imageAlt = 'Buy "me" a <coffee>'

        $result = Update-Header -Header $header -CategorySlugs @('powershell')

        # Inside an HTML block GitHub shows backslashes as written, so only entities are used there.
        $result | Should -Match ([regex]::Escape('<b>Tools &amp; &lt;scripts&gt; &quot;quoted&quot;</b><br/><sub>C# &middot; &lt;script&gt;</sub>'))
        $result | Should -Match ([regex]::Escape('## Hi \| \[there\]'))
        $result | Should -Match ([regex]::Escape('A \[link\](https://evil.example/) and &lt;b&gt;bold&lt;/b&gt;'))
        $result | Should -Match ([regex]::Escape('<b>Read &quot;more&quot; &lt;now&gt; &#8594;</b>'))
        $result | Should -Match ([regex]::Escape('alt="Buy &quot;me&quot; a &lt;coffee&gt;"'))
        $result | Should -Not -Match '<script>|<scripts>|<now>|<coffee>'
    }

    It 'keeps every dollar sign in the header out of math' {
        # GitHub pairs dollar signs into math inside HTML blocks too, so each one sits in a
        # span; the alt is an attribute, which is never math, so it keeps its $.
        $header = New-TestProfileHeader
        $header.tagline = 'Tools for $0'
        $header.languages = @('$shell')
        $header.heading = 'Hi $name'
        $header.about = '$$x^2$$ is math on GitHub'
        $header.links = @(@{ text = 'Save $5'; url = 'https://fixture.example.test/about/' })
        $header.support.imageAlt = 'Give $3'

        $result = (Update-Header -Header $header -CategorySlugs @('powershell')) -replace "`r`n", "`n"

        $result | Should -Match ([regex]::Escape('<b>Tools for <span>$</span>0</b><br/><sub><span>$</span>shell</sub>'))
        $result | Should -Match ([regex]::Escape('## Hi <span>$</span>name'))
        $result | Should -Match ('(?m)^' + [regex]::Escape('<span>$</span><span>$</span>x^2<span>$</span><span>$</span> is math on GitHub') + '$')
        $result | Should -Match ([regex]::Escape('<b>Save <span>$</span>5 &#8594;</b>'))
        $result | Should -Match ([regex]::Escape('alt="Give $3"'))
        ([regex]::Matches($result, '\$').Count - [regex]::Matches($result, '<span>\$</span>').Count) | Should -Be 1 -Because 'only the alt''s dollar sign stands alone'
    }

    It 'keeps the about text a paragraph when it starts with <Case>' -ForEach @(
        @{ Case = 'a backtick fence'; About = '```is how I start every code block.'; Expected = '\`\`\`is how I start every code block.' }
        @{ Case = 'a tilde fence'; About = '~~~ opens a fence too'; Expected = '\~~~ opens a fence too' }
        @{ Case = 'a heading marker'; About = '# not a heading'; Expected = '\# not a heading' }
        @{ Case = 'a level 6 heading marker'; About = '###### not a heading'; Expected = '\###### not a heading' }
        @{ Case = 'a lone heading marker'; About = '#'; Expected = '\#' }
        @{ Case = 'a rule'; About = '---'; Expected = '\---' }
        @{ Case = 'a star rule'; About = '***'; Expected = '\***' }
        @{ Case = 'an underscore rule'; About = '___'; Expected = '\___' }
        @{ Case = 'a spaced rule'; About = '_ _ _ _'; Expected = '\_ _ _ _' }
        @{ Case = 'a list marker'; About = '- not a list'; Expected = '\- not a list' }
        @{ Case = 'a plus list marker'; About = '+ not a list'; Expected = '\+ not a list' }
        @{ Case = 'a star list marker'; About = '* not a list'; Expected = '\* not a list' }
        @{ Case = 'a lone list marker'; About = '-'; Expected = '\-' }
        @{ Case = 'four spaces'; About = '    not a code block'; Expected = 'not a code block' }
        @{ Case = 'an ordered list marker'; About = '1. not an ordered list'; Expected = '1\. not an ordered list' }
        @{ Case = 'a parenthesis list marker'; About = '42) not an ordered list'; Expected = '42\) not an ordered list' }
        @{ Case = 'a lone list number'; About = '1.'; Expected = '1\.' }
        @{ Case = 'a lone parenthesis list number'; About = '1)'; Expected = '1\)' }
        @{ Case = 'a four-digit list number'; About = '2024. was a good year'; Expected = '2024\. was a good year' }
        # CommonMark allows nine digits, and GitHub renders 12345. as a list starting at 12345.
        @{ Case = 'a five-digit list number'; About = '12345. five digits'; Expected = '12345\. five digits' }
        @{ Case = 'a nine-digit list number'; About = '123456789. nine digits'; Expected = '123456789\. nine digits' }
        @{ Case = 'a quote marker'; About = '> not a quote'; Expected = '&gt; not a quote' }
    ) {
        $header = New-TestProfileHeader
        $header.about = $About

        $lines = @((Update-Header -Header $header -CategorySlugs @('powershell')) -split '\r?\n')

        $lines | Should -Contain $Expected
    }

    It 'leaves the about text as written when it starts with <Case>' -ForEach @(
        @{ Case = 'emphasis'; About = '*Sysadmin* by day' }
        @{ Case = 'strong emphasis'; About = '**Tools** I actually use' }
        @{ Case = 'underscore emphasis'; About = '_Mostly_ PowerShell' }
        @{ Case = 'strikethrough'; About = '~~Old~~ new tools' }
        @{ Case = 'a hashtag'; About = '#homelab tools and notes' }
        @{ Case = 'a decimal number'; About = '1.5 million downloads so far' }
        @{ Case = 'a plus sign'; About = '+1 for automation' }
        @{ Case = 'a negative number'; About = '-5 degrees outside, still coding' }
        @{ Case = 'a long option'; About = '--help is the flag I read most' }
        @{ Case = 'mixed rule characters'; About = '*-* marks the tools I use daily' }
        @{ Case = 'strong emphasis in a rule''s characters'; About = '***Everything*** here is free' }
        # Ten digits is past CommonMark's limit, so it's a paragraph already.
        @{ Case = 'a ten-digit number and a period'; About = '1234567890. ten digits' }
    ) {
        # None of these opens a block, so escaping them would show the markup as text.
        $header = New-TestProfileHeader
        $header.about = $About

        @((Update-Header -Header $header -CategorySlugs @('powershell')) -split '\r?\n') | Should -Contain $About
    }

    It 'escapes only a closing run of # at the end of the heading: <Heading>' -ForEach @(
        @{ Heading = 'Tools #'; Expected = '## Tools \#' }
        @{ Heading = 'Tools ###'; Expected = '## Tools \###' }
        @{ Heading = 'C#'; Expected = '## C#' }
        @{ Heading = 'Docs at https://x.invalid/page#'; Expected = '## Docs at https://x.invalid/page#' }
    ) {
        # A run of # after a space is closing markup GitHub drops. One right after other text
        # isn't, and an escape there would break an autolinked URL (checked with the API).
        $header = New-TestProfileHeader
        $header.heading = $Heading

        @((Update-Header -Header $header -CategorySlugs @('powershell')) -split '\r?\n') | Should -Contain $Expected
    }

    It 'renders no header link or button whose URL could leave its attribute' {
        # The renderer guards itself instead of leaning on the catalog check.
        $header = New-TestProfileHeader
        $header.links = @(
            @{ text = 'About'; url = 'https://x.test/"><img src="https://tracker.example/p.png' }
            @{ text = 'Script'; url = 'javascript:alert(1)' }
            @{ text = ' '; url = 'https://fixture.example.test/blank/' }
            @{ text = 'Kept'; url = 'https://fixture.example.test/kept/' }
        )
        $header.support.imageUrl = 'https://support.example.test/b.png" onerror="x'

        $result = Update-Header -Header $header -CategorySlugs @('powershell')

        $result | Should -Not -Match 'tracker\.example|javascript:|onerror|fixture\.example\.test/blank/'
        $result | Should -Match ([regex]::Escape('<a href="https://fixture.example.test/kept/"><b>Kept &#8594;</b></a>'))
        [regex]::Matches($result, '<img\b').Count | Should -Be 0
    }

    It 'renders no header link whose text is blank once encoded' {
        # A bidi override or a control character alone passes a whitespace test but encodes
        # to nothing, which left an arrow-only link.
        $header = New-TestProfileHeader
        $header.links = @(
            @{ text = [string][char]0x202E; url = 'https://fixture.example.test/bidi/' }
            @{ text = [string][char]7; url = 'https://fixture.example.test/bell/' }
        )

        $result = Update-Header -Header $header -CategorySlugs @('powershell')

        $result | Should -Not -Match 'fixture\.example\.test/(bidi|bell)/'
    }

    It 'hands the schema gate a profileHeader that is <Case> as written' -ForEach @(
        @{ Case = 'a one-item list'; Json = '[{"tagline":"From an array"}]' }
        @{ Case = 'null'; Json = 'null' }
    ) {
        $raw = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/catalog.json'))
        $path = Join-Path $TestDrive 'header-shape.json'
        [System.IO.File]::WriteAllText($path, $raw.Replace('"entries":', ('"profileHeader": ' + $Json + ', "entries":')))

        $result = Test-JsonSchemaContract -Value (Get-Catalog -Path $path) -SchemaPath 'schemas/profile-catalog.v1.json'

        $result.valid | Should -BeFalse
        @($result.errors | Where-Object { $_.instanceLocation -eq '/profileHeader' }) | Should -Not -BeNullOrEmpty
    }

    It 'refuses blank header text and a missing link text or image alt' {
        $header = New-TestProfileHeader
        $header.tagline = '   '
        $header.links = @(@{ text = ' '; url = 'https://fixture.example.test/about/' }, @{ url = 'https://fixture.example.test/other/' })
        $header.support.Remove('imageAlt')

        $result = Test-CatalogShape -Catalog @{ entries = @(New-TestEntry -Repo 'ShapeTool' -Category 'powershell'); profileHeader = $header }

        @($result.issues | Where-Object { $_.reason -match 'must not be blank' } | ForEach-Object { $_.field } | Sort-Object) |
            Should -Be @('profileHeader.links[0].text', 'profileHeader.links[1].text', 'profileHeader.support.imageAlt', 'profileHeader.tagline')
    }

    It 'counts <Case> as visible text: <Visible>' -ForEach @(
        @{ Case = 'nothing'; Text = $null; Visible = $false }
        @{ Case = 'spaces'; Text = '   '; Visible = $false }
        @{ Case = 'a lone NBSP'; Text = [string][char]0x00A0; Visible = $false }
        @{ Case = 'a zero-width space'; Text = [string][char]0x200B; Visible = $false }
        @{ Case = 'a left-to-right mark'; Text = [string][char]0x200E; Visible = $false }
        @{ Case = 'a right-to-left mark'; Text = [string][char]0x200F; Visible = $false }
        @{ Case = 'a word joiner'; Text = [string][char]0x2060; Visible = $false }
        # Unassigned, so not a format character, but default-ignorable like its neighbours.
        @{ Case = 'U+2065 among the invisible operators'; Text = [string][char]0x2065; Visible = $false }
        @{ Case = 'a byte order mark'; Text = [string][char]0xFEFF; Visible = $false }
        @{ Case = 'a variation selector'; Text = [string][char]0xFE0F; Visible = $false }
        @{ Case = 'a mix of them'; Text = [string][char]0x00A0 + [char]0x200B + [char]0x202E + "`t"; Visible = $false }
        @{ Case = 'a word'; Text = 'Tools'; Visible = $true }
        @{ Case = 'a word behind an NBSP'; Text = [string][char]0x00A0 + 'Tools'; Visible = $true }
        @{ Case = 'an emoji'; Text = [char]::ConvertFromUtf32(0x1F527); Visible = $true }
    ) {
        Test-VisibleText $Text | Should -Be $Visible
    }

    It 'judges U+<Code> by code point: visible <Visible>' -ForEach @(
        # Outside the Basic Multilingual Plane a character is two UTF-16 units, and the first,
        # a high surrogate, used to count as visible whatever the character was.
        @{ Code = 'E0020'; Visible = $false; Note = 'tag space' }
        @{ Code = 'E0001'; Visible = $false; Note = 'language tag' }
        @{ Code = '1D173'; Visible = $false; Note = 'musical symbol begin beam' }
        @{ Code = '13430'; Visible = $false; Note = 'Egyptian hieroglyph joiner' }
        @{ Code = '1BCA0'; Visible = $false; Note = 'shorthand format letter overlap' }
        @{ Code = 'E0100'; Visible = $false; Note = 'variation selector 17' }
        # Default-ignorable characters that aren't format characters draw nothing either.
        @{ Code = '180B'; Visible = $false; Note = 'Mongolian free variation selector one' }
        @{ Code = '180F'; Visible = $false; Note = 'Mongolian free variation selector four' }
        @{ Code = '3164'; Visible = $false; Note = 'Hangul filler' }
        @{ Code = '115F'; Visible = $false; Note = 'Hangul choseong filler' }
        @{ Code = 'FFA0'; Visible = $false; Note = 'halfwidth Hangul filler' }
        @{ Code = '034F'; Visible = $false; Note = 'combining grapheme joiner' }
        @{ Code = '17B4'; Visible = $false; Note = 'Khmer vowel inherent aq' }
        @{ Code = '2800'; Visible = $false; Note = 'braille pattern blank' }
        # And these draw something although their category says space or format.
        @{ Code = '1680'; Visible = $true; Note = 'Ogham space mark' }
        @{ Code = '0600'; Visible = $true; Note = 'Arabic number sign' }
        @{ Code = '06DD'; Visible = $true; Note = 'Arabic end of ayah' }
        @{ Code = '070F'; Visible = $true; Note = 'Syriac abbreviation mark' }
        @{ Code = '110BD'; Visible = $true; Note = 'Kaithi number sign' }
    ) {
        Test-VisibleText ([char]::ConvertFromUtf32([Convert]::ToInt32($Code, 16))) | Should -Be $Visible -Because $Note
    }

    It 'counts a lone surrogate as visible, since the encoders write it as U+FFFD' {
        Test-VisibleText ([string][char]0xD800) | Should -BeTrue
    }

    It 'falls back from row text a reader can''t see' {
        # descriptionOverride, the Language cell and upstreamLicense used IsNullOrWhiteSpace,
        # so zero-width text left an empty cell or a bare "License: ".
        $blank = [string][char]0x200B
        $entry = New-TestEntry -Repo 'RowTool' -Category 'desktop'
        $entry.descriptionOverride = $blank
        $entry.upstreamLicense = $blank
        $entry.forkOf = 'upstream-owner/RowTool'
        $meta = New-TestRepoMeta -Name 'RowTool'
        Set-MemberValue -Object $meta -Name 'description' -Value 'From GitHub'

        Get-Description $entry $meta | Should -BeOrdinal 'From GitHub'
        Get-UpstreamAttribution $entry | Should -BeOrdinal '<br/><sub>Upstream: [upstream-owner/RowTool](https://github.com/upstream-owner/RowTool)</sub>'
    }

    It 'draws no support button whose image has no alt a reader can see' {
        $header = New-TestProfileHeader
        $header.support.imageAlt = [string][char]0x200B

        $result = Update-Header -Header $header -CategorySlugs @('powershell')

        [regex]::Matches($result, '<img\b').Count | Should -Be 0
    }

    It 'refuses given row text a reader can''t see, and allows it left out' {
        $entry = New-TestEntry -Repo 'RowTool' -Category 'desktop'
        foreach ($field in 'descriptionOverride', 'currentlyBuildingText', 'language', 'upstreamLicense') {
            $entry[$field] = [char]::ConvertFromUtf32(0xE0020)
        }
        $blankFields = @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues | Where-Object { $_.reason -match 'must not be blank or only invisible characters' } | ForEach-Object { $_.field } | Sort-Object)

        $blankFields | Should -Be @('currentlyBuildingText', 'descriptionOverride', 'language', 'upstreamLicense')
        foreach ($field in 'descriptionOverride', 'currentlyBuildingText', 'language', 'upstreamLicense') {
            $entry[$field] = $null
        }
        @((Test-CatalogShape -Catalog @{ entries = @($entry) }).issues) | Should -BeNullOrEmpty
    }

    It 'draws no header part whose text is only <Case>' -ForEach @(
        @{ Case = 'an NBSP'; Blank = [string][char]0x00A0 }
        @{ Case = 'a zero-width space'; Blank = [string][char]0x200B }
        @{ Case = 'a left-to-right mark'; Blank = [string][char]0x200E }
        @{ Case = 'a byte order mark'; Blank = [string][char]0xFEFF }
    ) {
        # The link guard tested the encoded label, and HtmlEncode turns an NBSP into &#160;.
        $header = New-TestProfileHeader
        $header.tagline = $Blank
        $header.languages = @('PowerShell', $Blank)
        $header.heading = $Blank
        $header.about = $Blank
        $header.links = @(@{ text = $Blank; url = 'https://fixture.example.test/blank/' })

        $result = (Update-Header -Header $header -CategorySlugs @('powershell')) -replace "`r`n", "`n"

        $result | Should -Match '^<p align="center"><b>Public projects by [^<]+</b><br/><sub>PowerShell</sub></p>\n'
        $result | Should -Not -Match '(?m)^## '
        $result | Should -Not -Match 'fixture\.example\.test/blank/'
        $result | Should -Not -Match ([regex]::Escape($Blank))
        $result | Should -Not -Match '&#160;|&#8203;|&#8206;|&#65279;'
    }

    It 'refuses header text and titles that are only <Case>' -ForEach @(
        @{ Case = 'an NBSP'; Blank = [string][char]0x00A0 }
        @{ Case = 'a zero-width space'; Blank = [string][char]0x200B }
        @{ Case = 'a left-to-right mark'; Blank = [string][char]0x200E }
        @{ Case = 'a byte order mark'; Blank = [string][char]0xFEFF }
    ) {
        $header = New-TestProfileHeader
        $header.tagline = $Blank
        $header.languages = @($Blank)
        $header.heading = $Blank
        $header.about = $Blank
        $header.links = @(@{ text = $Blank; url = 'https://fixture.example.test/about/' })
        $header.support.imageAlt = $Blank
        $entry = New-TestEntry -Repo 'ShapeTool' -Category 'powershell'
        $entry.title = $Blank

        $result = Test-CatalogShape -Catalog @{ entries = @($entry); profileHeader = $header }

        @($result.issues | Where-Object { $_.reason -match 'must not be blank or only invisible characters' } | ForEach-Object { $_.field } | Sort-Object) |
            Should -Be @('profileHeader.about', 'profileHeader.heading', 'profileHeader.languages[0]', 'profileHeader.links[0].text', 'profileHeader.support.imageAlt', 'profileHeader.tagline', 'title')
    }

    It 'renders a neutral header for another owner with no header data' {
        $Owner = 'FixtureOwner'
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $catalog.Contains('profileHeader') | Should -BeFalse

        $readme = New-Readme -Catalog $catalog -Repos @()

        $headerRegion = $readme.Substring(0, $readme.IndexOf("### What's here"))
        $headerRegion.TrimStart() | Should -Match '^<p align="center"><b>Public projects by FixtureOwner</b></p>'
        $headerRegion | Should -Not -Match "Matt|medical|getparkerai|ko-fi|Sysadmin by day|tool-builder"
        [regex]::Matches($headerRegion, '<img\b').Count | Should -Be 0
        # The footer and the grid's portfolio links use the owner's own fallback.
        $readme | Should -Not -Match 'getparkerai'
        $readme | Should -Match ([regex]::Escape('<a href="https://fixtureowner.github.io/"><b>See everything</b></a>'))
        $experience = Test-ReadmeExperience -Catalog $catalog -Repos @() -ExpectedReadme $readme
        $experience.minimalProfileHeader | Should -BeTrue
        # This repository's run.ps1 still serves SysAdminDoc, so the page's install lines
        # would install that account's tools until the owner's own copy names the owner.
        $experience.installDispatcherOwner | Should -Be 'SysAdminDoc'
        $experience.installDispatcherMatchesOwner | Should -BeFalse
        $experience.passed | Should -BeFalse
    }

    It 'passes the install dispatcher check for the owner run.ps1 serves' {
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $readme = New-Readme -Catalog $catalog -Repos @()

        $experience = Test-ReadmeExperience -Catalog $catalog -Repos @() -ExpectedReadme $readme

        [regex]::Matches($readme, '(?m)^irm \S+/run\.ps1 \| iex; Start-Tool ').Count | Should -BeGreaterThan 0
        $experience.installDispatcherOwner | Should -Be $Owner
        $experience.installDispatcherMatchesOwner | Should -BeTrue
        $experience.passed | Should -BeTrue
    }

    It 'reads run.ps1''s owner from its syntax tree: <Case>' -ForEach @(
        @{ Case = 'double quotes'; Script = "function Start-Tool {`n    `$profileOwner = `"SysAdminDoc`"`n}"; ExpectedOwner = 'SysAdminDoc'; MatchesOwner = $true }
        @{ Case = 'a block comment naming someone else first'; Script = "<#`n    `$profileOwner = 'Someone'`n#>`nfunction Start-Tool {`n    `$profileOwner = 'SysAdminDoc'`n}"; ExpectedOwner = 'SysAdminDoc'; MatchesOwner = $true }
        @{ Case = 'two assignments'; Script = "function Start-Tool {`n    `$profileOwner = 'SysAdminDoc'`n    `$profileOwner = 'Someone'`n}"; ExpectedOwner = $null; MatchesOwner = $false }
        @{ Case = 'a computed value'; Script = "function Start-Tool {`n    `$profileOwner = `"`$env:OWNER`"`n}"; ExpectedOwner = $null; MatchesOwner = $false }
        @{ Case = 'a name with a hidden character'; Script = "function Start-Tool {`n    `$profileOwner = 'SysAdmin" + [char]0x200B + "Doc'`n}"; ExpectedOwner = 'SysAdmin' + [char]0x200B + 'Doc'; MatchesOwner = $false }
        # Review G4: these two gave no owner, and a variable whose name hid a character
        # counted as a second assignment to $profileOwner.
        @{ Case = 'a [string] cast'; Script = "function Start-Tool {`n    [string]`$profileOwner = 'SysAdminDoc'`n}"; ExpectedOwner = 'SysAdminDoc'; MatchesOwner = $true }
        @{ Case = 'a value in parentheses'; Script = "function Start-Tool {`n    `$profileOwner = (('SysAdminDoc'))`n}"; ExpectedOwner = 'SysAdminDoc'; MatchesOwner = $true }
        @{ Case = 'a validation attribute and a cast'; Script = "function Start-Tool {`n    [ValidateNotNullOrEmpty()][string]`$profileOwner = 'SysAdminDoc'`n}"; ExpectedOwner = 'SysAdminDoc'; MatchesOwner = $true }
        @{ Case = 'a cast to another type'; Script = "function Start-Tool {`n    [char[]]`$profileOwner = 'SysAdminDoc'`n}"; ExpectedOwner = $null; MatchesOwner = $false }
        @{ Case = 'another variable with a hidden character'; Script = "function Start-Tool {`n    `$profileOwner = 'SysAdminDoc'`n    `${profile" + [char]0x200B + "Owner} = 'Someone'`n}"; ExpectedOwner = 'SysAdminDoc'; MatchesOwner = $true }
    ) {
        # The regex took the first $profileOwner = '...' it found, a block comment's included,
        # a double-quoted one gave no owner at all, and -eq matched a name with a hidden
        # character in it.
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $readme = New-Readme -Catalog $catalog -Repos @()
        $root = Join-Path $TestDrive ('run-owner-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'run.ps1') -Value $Script -Encoding utf8
        # A local $RepoRoot shadows the generator's for this block only; the generator reads it
        # from the scope that calls it, so a $script: one would lose to the dot-sourced copy.
        $RepoRoot = $root

        $experience = Test-ReadmeExperience -Catalog $catalog -Repos @() -ExpectedReadme $readme

        if ($null -eq $ExpectedOwner) {
            $experience.installDispatcherOwner | Should -BeNullOrEmpty
        } else {
            # Ordinal: one owner holds a zero-width space that -BeExactly would skip.
            $experience.installDispatcherOwner | Should -BeOrdinal $ExpectedOwner
        }
        $experience.installDispatcherMatchesOwner | Should -Be $MatchesOwner
    }

    It 'takes a URL whose scheme is written in capitals' {
        # The scheme check accepted HTTPS:// but the shape check, the catalog schema and the
        # renderer wanted lower case, so it failed with a reason that didn't fit.
        $entry = New-TestEntry -Repo 'CapsTool' -Category 'web'
        $entry.liveUrl = 'HTTPS://example.test/app/'
        $header = New-TestProfileHeader
        $header.links = @(@{ text = 'Caps link'; url = 'HTTPS://example.test/about/' })

        @((Test-CatalogShape -Catalog @{ entries = @($entry); profileHeader = $header }).issues | Where-Object { $_.field -like '*url*' -or $_.field -like '*Url*' }) | Should -BeNullOrEmpty
        (Update-Header -Header $header -CategorySlugs @('powershell')) | Should -Match ([regex]::Escape('<a href="HTTPS://example.test/about/"><b>Caps link'))
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        @($catalog.entries)[0].liveUrl = 'HTTPS://example.test/app/'
        (Test-JsonSchemaContract -Value $catalog -SchemaPath 'schemas/profile-catalog.v1.json').valid | Should -BeTrue
    }

    It 'refuses an aliasOf that isn''t a repository name in the catalog schema' {
        # aliasOf had no pattern, so "WinTool" with a line break after it passed the schema.
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        (Test-JsonSchemaContract -Value $catalog -SchemaPath 'schemas/profile-catalog.v1.json').valid | Should -BeTrue -Because 'the fixture passes as it is'
        @($catalog.entries)[0].aliasOf = "WinTool`n"

        $result = Test-JsonSchemaContract -Value $catalog -SchemaPath 'schemas/profile-catalog.v1.json'

        $result.valid | Should -BeFalse
        @($result.errors | ForEach-Object instanceLocation) | Should -Contain '/entries/0/aliasOf'
    }

    It 'ends every schema pattern at the true end of text' {
        # JsonSchema.Net runs patterns as .NET regexes, where $ also matches before a final
        # line break, so "<40 hex digits>" plus a newline passed a branchTipSha of ^...$.
        $offenders = foreach ($schemaFile in Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'schemas') -Filter '*.json') {
            foreach ($match in [regex]::Matches([System.IO.File]::ReadAllText($schemaFile.FullName), '"pattern": "(?<value>(?:\\.|[^"\\])*)"')) {
                if ($match.Groups['value'].Value -match '(?<!\\)\$\z') { '{0}: {1}' -f $schemaFile.Name, $match.Groups['value'].Value }
            }
        }

        @($offenders) | Should -BeNullOrEmpty
    }

    It 'refuses a portfolioUrl that isn''t a plain https URL' {
        $result = Test-CatalogShape -Catalog @{ entries = @(New-TestEntry -Repo 'ShapeTool' -Category 'powershell'); portfolioUrl = 'http://portfolio.example.test/"x' }

        @($result.issues | Where-Object { $_.field -eq 'portfolioUrl' }) | Should -HaveCount 1
    }

    It 'holds the README to the tagline its own catalog renders' {
        $catalog = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $catalog.profileHeader = New-TestProfileHeader
        $readme = New-Readme -Catalog $catalog -Repos @()

        (Test-ReadmeExperience -Catalog $catalog -Repos @() -ExpectedReadme $readme).minimalProfileHeader | Should -BeTrue
        $catalog.profileHeader.tagline = 'A different tagline.'
        (Test-ReadmeExperience -Catalog $catalog -Repos @() -ExpectedReadme $readme).minimalProfileHeader | Should -BeFalse
    }

    It 'keeps this profile''s personal text and links out of the generator' {
        $personal = @("Hey, I'm Matt", 'medical imaging', 'healthcare-it', 'ko-fi', 'X8K126YVER', 'Sysadmin by day', 'getparkerai')
        $offenders = foreach ($path in $script:SyncProfileSourcePaths) {
            # The report names the importer whose feed contract it checks; that names the
            # contract, not a link on the page.
            $text = [System.IO.File]::ReadAllText($path).Replace('consumerContract = "portfolio.getparkerai.com profile-feed importer"', '')
            foreach ($phrase in $personal) {
                if ($text.IndexOf($phrase, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    '{0}: {1}' -f [System.IO.Path]::GetFileName($path), $phrase
                }
            }
        }

        @($offenders) | Should -BeNullOrEmpty
    }

    It 'publishes the header this catalog describes' {
        $catalog = Get-Catalog -Path (Join-Path $script:RepoRoot 'data/profile-catalog.json')
        $slugs = @($CategoryDefinitions | ForEach-Object { [string]$_.Slug })
        $header = (Update-Header -CategorySlugs $slugs -Header $catalog.profileHeader) -replace "`r`n", "`n"
        $committed = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'README.md')) -replace "`r`n", "`n"

        $catalog.profileHeader | Should -Not -BeNullOrEmpty
        $committed.StartsWith($header, [StringComparison]::Ordinal) | Should -BeTrue
    }

    It 'refuses header text that breaks a line and header URLs that could leave their attribute' {
        $header = New-TestProfileHeader
        $header.tagline = "Two`nlines"
        $header.links = @(@{ text = 'Link'; url = 'https://example.test/"onmouseover="x' })
        $header.support.imageUrl = 'http://insecure.example.test/button.png'

        $result = Test-CatalogShape -Catalog @{ entries = @(New-TestEntry -Repo 'ShapeTool' -Category 'powershell'); profileHeader = $header }

        $issues = @($result.issues | Where-Object { $_.field -like 'profileHeader*' })
        @($issues | ForEach-Object { $_.field } | Sort-Object) | Should -Be @('profileHeader.links[0].url', 'profileHeader.support.imageUrl', 'profileHeader.tagline')
        ($issues | Where-Object { $_.field -eq 'profileHeader.tagline' }).value | Should -Be 'U+000A'
        $result.passed | Should -BeFalse
    }

    It 'accepts a complete header block' {
        $result = Test-CatalogShape -Catalog @{ entries = @(New-TestEntry -Repo 'ShapeTool' -Category 'powershell'); profileHeader = (New-TestProfileHeader) }

        @($result.issues | Where-Object { $_.field -like 'profileHeader*' }) | Should -BeNullOrEmpty
    }

    It 'validates the catalog the generator loads, one-link header included' {
        # Get-Catalog reads with ConvertFrom-Json, so the header is a PSCustomObject whose
        # one-item links array must still validate as an array.
        $result = Test-JsonSchemaContract -Value (Get-Catalog -Path (Join-Path $script:RepoRoot 'data/profile-catalog.json')) -SchemaPath 'schemas/profile-catalog.v1.json'

        @($result.errors | ForEach-Object { '{0} {1}' -f $_.instanceLocation, $_.message }) | Should -BeNullOrEmpty
        $result.valid | Should -BeTrue
    }

    It 'keeps a one-item array an array when it prepares an object for validation' {
        $converted = $null
        ConvertTo-JsonSchemaValidationValue -Value ([pscustomobject]@{ one = @('only'); none = @(); many = @(1, 2) }) -Result ([ref]$converted)

        ,$converted['one'] | Should -BeOfType [object[]]
        @($converted['one']) | Should -Be @('only')
        ,$converted['none'] | Should -BeOfType [object[]]
        @($converted['none']).Count | Should -Be 0
        @($converted['many']).Count | Should -Be 2
    }

    It 'validates the header block against the catalog schema' {
        $payload = ConvertFrom-JsonPreservingArrays -Json ([System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'data/profile-catalog.json')))
        (Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-catalog.v1.json').valid | Should -BeTrue

        $link = @(Get-JsonArrayItems (Get-MemberValue -Object (Get-MemberValue -Object $payload -Name 'profileHeader') -Name 'links'))[0]
        Set-MemberValue -Object $link -Name 'url' -Value 'https://example.test/"x'
        $result = Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-catalog.v1.json'

        $result.valid | Should -BeFalse
        @($result.errors | Where-Object { $_.instanceLocation -eq '/profileHeader/links/0/url' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'setup.ps1 hardening contract' {
    BeforeAll {
        $script:setupPath = Join-Path $script:RepoRoot 'setup.ps1'
        $script:setupSource = Get-Content -LiteralPath $script:setupPath -Raw
    }

    It 'declares the supported Windows PowerShell floor' {
        $script:setupSource | Should -Match '(?m)^#Requires -Version 5\.1\s*$'
    }

    It 'keeps the public bootstrapper ASCII-only for Windows PowerShell 5.1' {
        $nonAsciiBytes = @([System.IO.File]::ReadAllBytes($script:setupPath) | Where-Object { $_ -gt 0x7f })

        $nonAsciiBytes | Should -HaveCount 0
    }

    It 'supports check-only diagnostics without installation' {
        $script:setupSource | Should -Match '\[switch\]\$CheckOnly'
        $script:setupSource | Should -Match 'Check-only mode: no packages will be installed\.'
        $script:setupSource | Should -Match "Pwsh = Write-ToolStatus 'pwsh' 'pwsh'"
        $script:setupSource | Should -Match "Pip = Write-ToolStatus 'pip' 'pip'"
        $script:setupSource | Should -Match '\$state\.Pwsh -and \$state\.Python -and \$state\.Pip -and \$state\.Git'
        $script:setupSource | Should -Match 'PowerShell 7, Python, pip, and Git are installed'
        $script:setupSource | Should -Match 'Run without -CheckOnly to install with winget'
    }

    It 'installs PowerShell 7 while keeping Windows PowerShell as bootstrap only' {
        $script:setupSource | Should -Match 'Windows PowerShell 5\.1 is bootstrap-only'
        $script:setupSource | Should -Match "Install-Pkg 'Microsoft.PowerShell' 'PowerShell 7' 'pwsh'"
    }

    It 'uses terminating failures when prerequisites remain missing' {
        $script:setupSource | Should -Match 'function Stop-SetupWithFailure'
        $script:setupSource | Should -Match 'throw \$Message'
        $script:setupSource | Should -Match 'Stop-SetupWithFailure "One or more prerequisites are missing\.'
        $script:setupSource | Should -Match 'Stop-SetupWithFailure "Setup cannot continue until winget is available\.'
        $script:setupSource | Should -Match 'Stop-SetupWithFailure "Setup incomplete\.'
    }

    It 'writes a best-effort setup transcript under temp' {
        $script:setupSource | Should -Match 'Start-Transcript'
        $script:setupSource | Should -Match 'SysAdminDoc-setup-\{0\}-\{1\}\.log'
        $script:setupSource | Should -Match '\$PID'
        $script:setupSource | Should -Match 'Stop-Transcript'
    }

    It 'selects winget scope by elevation to avoid noisy machine-scope failures for non-admins' {
        $script:setupSource | Should -Match 'function Test-Admin'
        $script:setupSource | Should -Match 'WindowsBuiltInRole\]::Administrator'
        $script:setupSource | Should -Match "\`$primaryScope = if \(Test-Admin\) \{ 'machine' \} else \{ 'user' \}"
        $script:setupSource | Should -Match '--scope \$primaryScope'
        $script:setupSource | Should -Match '--scope \$fallbackScope'
    }

    It 'parses as valid PowerShell (Windows PowerShell 5.1 floor)' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:setupPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
}

Describe 'New-ProjectsExportJson feed' {
    It 'points projects and catalog schemas at versioned raw GitHub contracts' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json

        $cat.schema | Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/schemas/profile-catalog.v1.json'
        $json.schema | Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/schemas/profile-projects.v1.json'
    }

    It 'stamps feed generatedAt at generation time instead of copying the catalog stamp' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $cat.generatedAt = '2026-06-01T16:18:55.0998940-04:00'
        $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json

        $json.generatedAt | Should -Not -Be $cat.generatedAt
        $parsed = [datetimeoffset]::MinValue
        [datetimeoffset]::TryParse([string]$json.generatedAt, [ref]$parsed) | Should -BeTrue
        ([datetimeoffset]::Now - $parsed).TotalMinutes | Should -BeLessThan 10
    }

    It 'treats feed generatedAt as volatile when comparing committed and generated feeds' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $current = New-ProjectsExportJson -Catalog $cat -Repos @()
        $stale = $current -replace '"generatedAt":\s*"[^"]+"', '"generatedAt": "2026-06-01T16:18:55.0998940-04:00"'

        $stale | Should -Not -Be $current
        (ConvertTo-ProjectsSyncComparableJson -Json $stale) |
            Should -Be (ConvertTo-ProjectsSyncComparableJson -Json $current)
    }

    It 'exports public-safe feed provenance fields' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $rawJson = New-ProjectsExportJson -Catalog $cat -Repos @()
        $json = $rawJson | ConvertFrom-Json
        $provenanceJson = $json.provenance | ConvertTo-Json -Depth 20

        $json.provenance.version | Should -Be 1
        $json.provenance.feedSchemaVersion | Should -Be 3
        $json.provenance.sourceRepository | Should -Be 'SysAdminDoc/SysAdminDoc'
        if ($null -ne $json.provenance.sourceCommit) {
            $json.provenance.sourceCommit | Should -Match '^[a-f0-9]{40}$'
        }
        $json.provenance.catalogSha256 | Should -Match '^[a-f0-9]{64}$'
        $json.provenance.generatorSha256 | Should -Match '^[a-f0-9]{64}$'
        $json.provenance.projectSchemaSha256 | Should -Match '^[a-f0-9]{64}$'
        $rawJson | Should -Match '"metadataSnapshotAt":\s*"\d{4}-\d{2}-\d{2}T'
        $json.provenance.metadataProvider | Should -Be 'graphql'
        $json.provenance.repoEnumeration.requestedLimit | Should -BeGreaterOrEqual 0
        $json.provenance.repoEnumeration.returnedCount | Should -Be 0
        $json.provenance.repoEnumeration.truncated | Should -BeFalse
        $provenanceJson | Should -Not -Match 'C:\\|/Users/|repos\\\\|VaultBox|RadAtlas|improve-repo'
    }

    It 'exports stable IDs, canonical repository aliases, and locale/script hints' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $aliasEntry = New-TestEntry -Repo 'RenamedTool' -Category 'misc'
        $aliasEntry.id = 'legacy-tool'
        $aliasEntry.aliasOf = 'LegacyTool'
        $aliasEntry.aliases = @('OlderTool')
        $cat.entries += $aliasEntry

        $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $row = $json.projects | Where-Object { $_.repo -eq 'RenamedTool' }

        $row.id | Should -Be 'legacy-tool'
        $row.canonicalRepo | Should -Be 'SysAdminDoc/LegacyTool'
        @($row.aliases) | Should -Contain 'OlderTool'
        @($row.aliases) | Should -Contain 'RenamedTool'
        @($row.localeHints) | Should -Contain 'en-US'
        @($row.localeHints) | Should -Contain 'en'
        @($row.scriptHints) | Should -Contain 'Latn'
        $row.id | Should -Match '^[a-z0-9][a-z0-9-]{2,63}$'
    }

    It 'records and validates the feed schema migration policy' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $rawJson = New-ProjectsExportJson -Catalog $cat -Repos @()
        $json = $rawJson | ConvertFrom-Json

        $json.schemaPolicy.currentVersion | Should -Be 3
        @($json.schemaPolicy.supportedVersions) | Should -Contain 2
        @($json.schemaPolicy.supportedVersions) | Should -Contain 3
        $json.schemaPolicy.migrationRequired | Should -BeTrue
        @($json.schemaPolicy.migrationNotes).Count | Should -BeGreaterThan 0

        $result = Test-FeedSchemaMigrationPolicy -ProjectsJson $rawJson
        $result.passed | Should -BeTrue
        $result.changeKind | Should -Be 'required-field-addition'

        $invalid = $json
        $invalid.schemaPolicy.migrationNotes = @()
        $invalidResult = Test-FeedSchemaMigrationPolicy -ProjectsJson ($invalid | ConvertTo-Json -Depth 30)
        $invalidResult.passed | Should -BeFalse
        $invalidResult.errors -join "`n" | Should -Match 'migration note'
    }

    It 'verifies stable IDs and catches duplicate feed identities' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $rawJson = New-ProjectsExportJson -Catalog $cat -Repos @()
        $result = Test-StableProjectEntityIds -ProjectsJson $rawJson

        $result.passed | Should -BeTrue
        $result.missingIdCount | Should -Be 0
        $result.duplicateIdCount | Should -Be 0
        $result.missingAliasMetadataCount | Should -Be 0
        $result.projectCount | Should -Be 6

        $invalid = $rawJson | ConvertFrom-Json
        $invalid.projects[1].id = $invalid.projects[0].id
        $invalidResult = Test-StableProjectEntityIds -ProjectsJson ($invalid | ConvertTo-Json -Depth 30)
        $invalidResult.passed | Should -BeFalse
        $invalidResult.duplicateIdCount | Should -Be 1
    }

    It 'keeps feed generation owner-agnostic through the catalog fixture' {
        $previousOwner = $Owner
        $previousSchemaBaseUrl = $SchemaBaseUrl
        $previousCatalogSchemaUrl = $CatalogSchemaUrl
        $previousProjectsSchemaUrl = $ProjectsSchemaUrl
        $previousReportSchemaUrl = $ReportSchemaUrl
        try {
            $Owner = 'FixtureOwner'
            $SchemaBaseUrl = 'https://raw.githubusercontent.com/FixtureOwner/FixtureOwner/main/schemas'
            $CatalogSchemaUrl = "$SchemaBaseUrl/profile-catalog.v1.json"
            $ProjectsSchemaUrl = "$SchemaBaseUrl/profile-projects.v1.json"
            $ReportSchemaUrl = "$SchemaBaseUrl/profile-sync-report.v1.json"

            $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/owner-agnostic-catalog.json')
            $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json

            $json.source | Should -Be 'FixtureOwner/FixtureOwner data/profile-catalog.json'
            $json.provenance.sourceRepository | Should -Be 'FixtureOwner/FixtureOwner'
            $json.provenance.repoEnumeration.returnedCount | Should -Be 0
            $json.projects[0].repoUrl | Should -Be 'https://github.com/FixtureOwner/FixtureTool'
            $json.projects[0].canonicalRepo | Should -Be 'FixtureOwner/FixtureTool'
            $json.schema | Should -Be 'https://raw.githubusercontent.com/FixtureOwner/FixtureOwner/main/schemas/profile-projects.v1.json'

            $readme = New-Readme -Catalog $cat -Repos @()
            $readme | Should -Match 'https://raw.githubusercontent.com/FixtureOwner/FixtureOwner/main/setup[.]ps1'
            $readme | Should -Match 'https://github.com/FixtureOwner[?]tab=repositories'
            $readme | Should -Match 'https://fixtureowner[.]github[.]io/'
        } finally {
            $Owner = $previousOwner
            $SchemaBaseUrl = $previousSchemaBaseUrl
            $CatalogSchemaUrl = $previousCatalogSchemaUrl
            $ProjectsSchemaUrl = $previousProjectsSchemaUrl
            $ReportSchemaUrl = $previousReportSchemaUrl
        }
    }

    It 'documents the downstream feed schema version bump contract' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-projects.v1.json') -Raw

        $schema | Should -Match '"feedSchemaVersion"'
        $schema | Should -Match 'Downstream projects[.]json feed contract version'
        $schema | Should -Match 'breaking feed changes'
        $schema | Should -Match 'new required fields'
        $schema | Should -Match 'Optional additive fields do not require a bump'
    }

    It 'normalizes text newlines before hashing feed provenance files' {
        $previousRepoRoot = $script:RepoRoot
        $hashRoot = Join-Path $TestDrive 'hash-root'
        New-Item -ItemType Directory -Path $hashRoot -Force | Out-Null
        $hashPath = Join-Path $hashRoot 'sample.txt'

        try {
            $script:RepoRoot = $hashRoot
            [System.IO.File]::WriteAllText($hashPath, "alpha`r`nbravo`r`n", [System.Text.Encoding]::UTF8)
            $crlfHash = Get-RepoFileSha256 -RelativePath 'sample.txt'
            [System.IO.File]::WriteAllText($hashPath, "alpha`nbravo`n", [System.Text.Encoding]::UTF8)
            $lfHash = Get-RepoFileSha256 -RelativePath 'sample.txt'

            $crlfHash | Should -Be $lfHash
        } finally {
            $script:RepoRoot = $previousRepoRoot
        }
    }

    It 'excludes suppressed entries and includes portfolio entries' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $repos = $json.projects | ForEach-Object { $_.repo }
        $repos | Should -Contain 'WinTool'
        $repos | Should -Not -Contain 'HiddenTool'
        $json.suppressed | Should -HaveCount 1
        $json.suppressed[0].suppressedId | Should -Be 'suppressed-001'
        $json.suppressed[0].category | Should -Be 'misc'
        $json.suppressed[0].reasonCode | Should -Be 'not-visitor-facing'
        $json.suppressed[0].publicReason | Should -Be 'Project omitted because it is not visitor-facing.'
        $json.suppressed[0].visibilityClass | Should -Be 'suppressed'

        $suppressedJson = $json.suppressed | ConvertTo-Json -Depth 20
        $suppressedJson | Should -Not -Match 'HiddenTool|Should be excluded|github.com|repoUrl|primaryAction|description'
    }

    It 'exports static search metadata hints for downstream portfolio filters' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        (@($cat.entries | Where-Object { $_.repo -eq 'WinTool' })[0]).language = 'C#'
        (@($cat.entries | Where-Object { $_.repo -eq 'ReleaseTool' })[0]).language = 'C++'
        $repos = @(
            (New-TestRepoMeta -Name 'ReleaseTool' -WithRelease -AssetNames @('ReleaseTool-v1.0.0.zip')),
            (New-TestRepoMeta -Name 'InstallTool' -Language 'JavaScript')
        )

        $json = New-ProjectsExportJson -Catalog $cat -Repos $repos | ConvertFrom-Json
        $winTool = $json.projects | Where-Object { $_.repo -eq 'WinTool' }
        $releaseTool = $json.projects | Where-Object { $_.repo -eq 'ReleaseTool' }
        $installTool = $json.projects | Where-Object { $_.repo -eq 'InstallTool' }

        $winTool.searchMetadata.type | Should -Be 'powershell-tool'
        @($winTool.searchMetadata.labels) | Should -Contain 'PowerShell'
        @($winTool.searchMetadata.labels) | Should -Contain 'PowerShell tool'
        @($winTool.searchMetadata.filters) | Should -Contain 'category:powershell'
        @($winTool.searchMetadata.filters) | Should -Contain 'type:powershell-tool'
        @($winTool.searchMetadata.filters) | Should -Contain 'language:c-sharp'

        $releaseTool.searchMetadata.type | Should -Be 'media-tool'
        @($releaseTool.searchMetadata.labels) | Should -Contain 'Media tool'
        @($releaseTool.searchMetadata.filters) | Should -Contain 'category:media'
        @($releaseTool.searchMetadata.filters) | Should -Contain 'type:media-tool'
        @($releaseTool.searchMetadata.filters) | Should -Contain 'language:c-plus-plus'

        $installTool.searchMetadata.type | Should -Be 'userscript'
        @($installTool.searchMetadata.labels) | Should -Contain 'Userscript'
        @($installTool.searchMetadata.filters) | Should -Contain 'type:userscript'
    }

    It 'accounts for every fixture catalog row as exported or redacted' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @()

        $result = Test-CatalogFeedAccounting -Catalog $cat -ProjectsJson $json

        $result.passed | Should -BeTrue
        $result.catalogEntryCount | Should -Be 7
        $result.visitorFacingCatalogCount | Should -Be 6
        $result.suppressedCatalogCount | Should -Be 1
        $result.exportedProjectCount | Should -Be 6
        $result.exportedSuppressedCount | Should -Be 1
        $result.unaccountedRowCount | Should -Be 0
        $result.fatalCount | Should -Be 0
        $result.unaccountedRows | Should -BeNullOrEmpty
    }

    It 'reports downstream portfolio compatibility for generated feed rows' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -Topics @('powershell', 'utility')),
            (New-TestRepoMeta -Name 'PyTool' -Language 'Python' -Topics @('python', 'utility')),
            (New-TestRepoMeta -Name 'WebTool' -Language 'JavaScript' -Topics @('web', 'dashboard')),
            (New-TestRepoMeta -Name 'InstallTool' -Language 'JavaScript' -Topics @('userscript', 'browser-extension')),
            (New-TestRepoMeta -Name 'ReleaseTool' -Language 'PowerShell' -Topics @('media', 'release') -WithRelease -AssetNames @('ReleaseTool-v1.0.0.zip', 'ReleaseTool-v1.0.0.zip.sha256')),
            (New-TestRepoMeta -Name 'ForkTool' -Language 'C#' -Topics @('csharp', 'fork') -IsFork $true)
        )
        $json = New-ProjectsExportJson -Catalog $cat -Repos $repos

        $result = Test-PortfolioFeedCompatibility -ProjectsJson $json

        $result.status | Should -Be 'compatible'
        $result.projectCount | Should -Be 6
        $result.suppressedCount | Should -Be 1
        $result.projectCountMatchesTopLevel | Should -BeTrue
        $result.suppressedCountMatchesTopLevel | Should -BeTrue
        $result.projectRequiredFields | Should -Contain 'primaryAction.url'
        $result.projectRequiredFields | Should -Contain 'releaseTrust.trustLevel'
        $result.projectRequiredFields | Should -Contain 'searchMetadata.filters'
        $result.projectRequiredFields | Should -Contain 'topics'
        $result.missingProjectFieldCount | Should -Be 0
        $result.suppressedIdentifierLeakCount | Should -Be 0
        $result.redactedSuppressedRowsCompatible | Should -BeTrue
        $result.provenanceAvailable | Should -BeTrue
        $result.releaseTrustAvailable | Should -BeTrue
        $result.searchMetadataAvailable | Should -BeTrue
        $result.searchFiltersAvailable | Should -BeTrue
        (($result.primaryActionKindCounts | ForEach-Object { $_.kind }) -join ',') | Should -Be 'install,live,release,repo'
        ($result.primaryActionKindCounts | Where-Object { $_.kind -eq 'install' }).count | Should -Be 1
        ($result.primaryActionKindCounts | Where-Object { $_.kind -eq 'live' }).count | Should -Be 1
        ($result.primaryActionKindCounts | Where-Object { $_.kind -eq 'release' }).count | Should -Be 1
        ($result.primaryActionKindCounts | Where-Object { $_.kind -eq 'repo' }).count | Should -Be 3
        $result.fatalCount | Should -Be 0
    }

    It 'keeps the optional portfolio cross-surface probe compatible when deployed evidence matches' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $localPayload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $localPayload.generatedAt = '2026-08-12T12:00:00.0000000Z'
        $localJson = $localPayload | ConvertTo-Json -Depth 50
        $liveAppCount = @($localPayload.projects | Where-Object { $_.hasLiveDemo -or -not [string]::IsNullOrWhiteSpace([string]$_.liveUrl) }).Count
        $featuredCount = @($localPayload.projects | Where-Object { $_.featured }).Count
        $deployedPayload = [ordered]@{
            schemaVersion = 1
            generatedAt = '2026-08-12T12:05:00.000Z'
            source = [ordered]@{ profileFeedGeneratedAt = $localPayload.generatedAt }
            counts = [ordered]@{
                projects = [int]$localPayload.projectCount
                catalog = [int]$localPayload.projectCount
                featured = [int]$featuredCount
                liveApps = [int]$liveAppCount
            }
        }
        $routes = @{}
        foreach ($path in @('/', 'projects.json', 'catalog/', 'feed.json', 'releases/', 'resume/', 'search/')) {
            $routes[$path] = @{ ok = $true; status = 200; error = $null }
        }
        $snapshot = @{
            root = @{ succeeded = $true; statusCode = 200; content = '<html></html>'; error = $null }
            feed = @{ succeeded = $true; statusCode = 200; content = ($deployedPayload | ConvertTo-Json -Depth 20); error = $null }
            routes = $routes
        }

        $result = Test-PortfolioCrossSurfaceDrift -ProjectsJson $localJson -Enabled -PortfolioUrl 'https://portfolio.example/' -Snapshot $snapshot

        $result.status | Should -Be 'compatible'
        $result.warningCount | Should -Be 0
        $result.feedFetchSucceeded | Should -BeTrue
        $result.localFeedSchemaVersion | Should -Be 3
        $result.deployedPortfolioSchemaVersion | Should -Be 1
        $result.routeProbeCount | Should -Be 7
        $result.routeProbePassedCount | Should -Be 7
        $result.routeProbeFailedCount | Should -Be 0
        $result.localRouteCounts.catalog | Should -Be $localPayload.projectCount
        $result.deployedRouteCounts.liveApps | Should -Be $liveAppCount
    }

    It 'records portfolio drift and route outages as warnings only' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $localPayload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $localPayload.generatedAt = '2026-08-12T12:00:00.0000000Z'
        $localJson = $localPayload | ConvertTo-Json -Depth 50
        $deployedPayload = [ordered]@{
            schemaVersion = 2
            generatedAt = '2026-08-12T12:05:00.000Z'
            source = [ordered]@{ profileFeedGeneratedAt = '2026-08-11T12:00:00.000Z' }
            counts = [ordered]@{ projects = 1; catalog = 1; featured = 0; liveApps = 0 }
        }
        $routes = @{}
        foreach ($path in @('/', 'projects.json', 'catalog/', 'feed.json', 'releases/', 'resume/', 'search/')) {
            $routes[$path] = @{ ok = $true; status = 200; error = $null }
        }
        $routes['catalog/'] = @{ ok = $false; status = 404; error = 'HTTP 404' }
        $snapshot = @{
            root = @{ succeeded = $true; statusCode = 200; content = '<html></html>'; error = $null }
            feed = @{ succeeded = $true; statusCode = 200; content = ($deployedPayload | ConvertTo-Json -Depth 20); error = $null }
            routes = $routes
        }

        $result = Test-PortfolioCrossSurfaceDrift -ProjectsJson $localJson -Enabled -PortfolioUrl 'https://portfolio.example/' -Snapshot $snapshot

        $result.status | Should -Be 'warning'
        $result.warningCount | Should -BeGreaterThan 0
        $result.routeProbeFailedCount | Should -Be 1
        ($result.warnings -join ' ') | Should -Match 'schemaVersion|timestamp|counts[.]catalog|catalog/'
        $script:SyncProfileScript | Should -Not -Match 'portfolioCrossSurfaceProbe = \[bool\]'
    }

    It 'does not probe the network when the portfolio probe is disabled' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @()

        $result = Test-PortfolioCrossSurfaceDrift -ProjectsJson $json

        $result.enabled | Should -BeFalse
        $result.status | Should -Be 'disabled'
        $result.routeProbeCount | Should -Be 0
        $result.warningCount | Should -Be 0
        $result.feedFetchSucceeded | Should -BeFalse
    }

    It 'flags visible project rows missing downstream-required fields' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $payload.projects[0].primaryAction.url = ''
        $json = $payload | ConvertTo-Json -Depth 50

        $result = Test-PortfolioFeedCompatibility -ProjectsJson $json

        $result.status | Should -Be 'incompatible'
        $result.missingProjectFieldCount | Should -Be 1
        $result.missingProjectFields[0].field | Should -Be 'primaryAction.url'
        $result.fatalCount | Should -BeGreaterThan 0
    }

    It 'flags visible project rows missing search filter metadata' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $payload.projects[0].searchMetadata.filters = @()
        $json = $payload | ConvertTo-Json -Depth 50

        $result = Test-PortfolioFeedCompatibility -ProjectsJson $json

        $result.status | Should -Be 'incompatible'
        $result.missingProjectFieldCount | Should -Be 1
        $result.missingProjectFields[0].field | Should -Be 'searchMetadata.filters'
        $result.searchMetadataAvailable | Should -BeTrue
        $result.searchFiltersAvailable | Should -BeFalse
        $result.fatalCount | Should -BeGreaterThan 0
    }

    It 'fails the consumer fixture when a primary action variant disappears' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = New-ProjectsExportJson -Catalog $cat -Repos @(
            (New-TestRepoMeta -Name 'ReleaseTool' -WithRelease -AssetNames @('ReleaseTool-v1.0.0.zip'))
        ) | ConvertFrom-Json

        foreach ($project in @($payload.projects | Where-Object { $_.primaryAction.kind -eq 'install' })) {
            $project.primaryAction.kind = 'repo'
            $project.primaryAction.label = 'Repo'
            $project.primaryAction.url = $project.repoUrl
            $project.hasDirectInstall = $false
        }
        $json = $payload | ConvertTo-Json -Depth 50

        $result = Test-PortfolioFeedCompatibility -ProjectsJson $json

        $result.status | Should -Be 'incompatible'
        ($result.errors -join ' ') | Should -Match 'consumer-required primary action kind\(s\): install'
        $result.fatalCount | Should -BeGreaterThan 0
    }

    It 'rejects duplicate visible repo names in the portfolio feed' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $dup = $payload.projects[0].PSObject.Copy()
        $payload.projects = @($payload.projects) + @($dup)
        $payload.projectCount = $payload.projects.Count
        $json = $payload | ConvertTo-Json -Depth 50

        $result = Test-PortfolioFeedCompatibility -ProjectsJson $json

        $result.status | Should -Be 'incompatible'
        $result.duplicateVisibleRepoCount | Should -BeGreaterThan 0
        $result.fatalCount | Should -BeGreaterThan 0
    }

    It 'flags suppressed rows that expose project-identifying fields to consumers' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $payload.suppressed[0] | Add-Member -NotePropertyName repoUrl -NotePropertyValue 'https://github.com/SysAdminDoc/HiddenTool'
        $json = $payload | ConvertTo-Json -Depth 50

        $result = Test-PortfolioFeedCompatibility -ProjectsJson $json

        $result.status | Should -Be 'incompatible'
        $result.suppressedIdentifierLeakCount | Should -Be 1
        $result.suppressedIdentifierLeaks[0].field | Should -Be 'repoUrl'
        $result.redactedSuppressedRowsCompatible | Should -BeFalse
        $result.fatalCount | Should -BeGreaterThan 0
    }

    It 'exports release asset kinds and keeps source-only releases as repo actions' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $cat.entries[0].downloadKind = 'apk'
        $cat.entries[1].downloadKind = 'zip'
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -WithRelease -AssetNames @('WinTool-v1.0.0.apk', 'WinTool-v1.0.0.apk.sha256')),
            (New-TestRepoMeta -Name 'PyTool' -WithRelease),
            (New-TestRepoMeta -Name 'HiddenTool' -WithRelease -AssetNames @('HiddenTool-InternalSetup.exe')),
            (New-TestRepoMeta -Name 'WebTool')
        )

        $json = New-ProjectsExportJson -Catalog $cat -Repos $repos | ConvertFrom-Json
        $winTool = $json.projects | Where-Object { $_.repo -eq 'WinTool' }
        $pyTool = $json.projects | Where-Object { $_.repo -eq 'PyTool' }
        $suppressedRow = $json.suppressed | Select-Object -First 1

        $winTool.releaseAssetKinds | Should -Contain 'apk'
        $winTool.releaseTrust.checksumAssets | Should -Contain 'WinTool-v1.0.0.apk.sha256'
        $winTool.releaseTrust.hasChecksumForEveryExecutable | Should -BeTrue
        $winTool.releaseTrust.trustLevel | Should -Be 'checksum-metadata'
        $winTool.primaryAction.kind | Should -Be 'release'
        $pyTool.releaseAssetKinds | Should -Contain 'source-archive'
        $pyTool.releaseTrust.sourceOnlyRelease | Should -BeTrue
        $pyTool.primaryAction.kind | Should -Be 'repo'
        $pyTool.hasDownload | Should -BeFalse
        $suppressedRow.reasonCode | Should -Be 'not-visitor-facing'
        $suppressedRow.PSObject.Properties.Name | Should -Not -Contain 'repo'
        $suppressedRow.PSObject.Properties.Name | Should -Not -Contain 'releaseAssetKinds'
        $suppressedRow.PSObject.Properties.Name | Should -Not -Contain 'releaseAssetNames'

        $suppressedJson = $json.suppressed | ConvertTo-Json -Depth 20
        $suppressedJson | Should -Not -Match 'HiddenTool|InternalSetup|releaseAssetNames'
    }

    It 'redacts real catalog suppressed rows from project identifiers' {
        $cat = Get-Catalog -Path (Join-Path $script:RepoRoot 'data/profile-catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $suppressedJson = $json.suppressed | ConvertTo-Json -Depth 20

        $json.suppressed | Should -HaveCount $json.suppressedCount
        @($json.suppressed | Where-Object { $_.suppressed -ne $true }).Count | Should -Be 0
        $suppressedJson | Should -Not -Match 'VaultBox|improve-repo|RadAtlas|https://github.com|repoUrl|primaryAction|releaseAssetNames|description|title'
    }

    It 'reports the real catalog as fully accounted without exposing suppressed names' {
        $cat = Get-Catalog -Path (Join-Path $script:RepoRoot 'data/profile-catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @()

        $result = Test-CatalogFeedAccounting -Catalog $cat -ProjectsJson $json
        $accountingJson = $result | ConvertTo-Json -Depth 20
        $visitorFacingCount = @($cat.entries | Where-Object {
                $_.includeInPortfolio -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
            }).Count
        $suppressedCount = @($cat.entries | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
            }).Count

        $result.passed | Should -BeTrue
        $result.catalogEntryCount | Should -Be @($cat.entries).Count
        $result.visitorFacingCatalogCount | Should -Be $visitorFacingCount
        $result.suppressedCatalogCount | Should -Be $suppressedCount
        $result.exportedProjectCount | Should -Be $visitorFacingCount
        $result.exportedSuppressedCount | Should -Be $suppressedCount
        $result.unaccountedRowCount | Should -Be 0
        $accountingJson | Should -Not -Match 'VaultBox|improve-repo|RadAtlas|github.com/SysAdminDoc'
    }

    It 'exports structured upstream attribution fields' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $cat.entries[0].forkOf = 'UpstreamOrg/WinTool'
        $cat.entries[0].upstreamLicense = 'MIT'

        $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $winTool = $json.projects | Where-Object { $_.repo -eq 'WinTool' }

        $winTool.description | Should -Not -Match 'Upstream:'
        $winTool.forkOf | Should -Be 'UpstreamOrg/WinTool'
        $winTool.forkOfUrl | Should -Be 'https://github.com/UpstreamOrg/WinTool'
        $winTool.upstreamLicense | Should -Be 'MIT'
    }

    It 'exports project license metadata separately from upstream attribution' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $cat.entries[0].upstreamLicense = 'GPL-3.0'
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -LicenseInfo ([pscustomobject]@{ key = 'mit'; name = 'MIT License' }))
        )

        $json = New-ProjectsExportJson -Catalog $cat -Repos $repos | ConvertFrom-Json
        $winTool = $json.projects | Where-Object { $_.repo -eq 'WinTool' }

        $winTool.upstreamLicense | Should -Be 'GPL-3.0'
        $winTool.licenseKey | Should -Be 'mit'
        $winTool.licenseName | Should -Be 'MIT License'
        $winTool.licenseSpdxId | Should -Be 'MIT'
    }
}

Describe 'Outside data is compared ordinally' {
    # PowerShell's -eq, -ceq, -in, -cnotin, -contains and switch compare strings by invariant
    # culture, which skips zero-width and other ignorable characters: ("py" + U+200B +
    # "thon") -ceq "python" is True, so a check built on them passes the hidden character on.
    It 'has no culture-sensitive comparison with a literal in <File>' -ForEach @(
        @{ File = 'scripts/sync-profile/catalog.ps1' }
        @{ File = 'scripts/sync-profile/artifact-store.ps1' }
        @{ File = 'run.ps1' }
    ) {
        # These decide what the catalog, the cache and the feed may publish or start.
        $operators = @('Ieq', 'Ceq', 'Ine', 'Cne', 'Iin', 'Cin', 'Inotin', 'Cnotin', 'Icontains', 'Ccontains', 'Inotcontains', 'Cnotcontains')
        $tokens = $null
        $parseErrors = $null
        $tree = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot $File), [ref]$tokens, [ref]$parseErrors)
        $isLiteral = {
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            (($node -is [System.Management.Automation.Language.ArrayLiteralAst] -or $node -is [System.Management.Automation.Language.ArrayExpressionAst]) -and
                $null -ne $node.Find({ param($inner) $inner -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
        }
        $patternFlags = [System.Management.Automation.Language.SwitchFlags]::Regex -bor [System.Management.Automation.Language.SwitchFlags]::Wildcard

        $cultureComparisons = @($tree.FindAll({
                    param($node)
                    ($node -is [System.Management.Automation.Language.BinaryExpressionAst] -and $operators -contains $node.Operator.ToString() -and ((& $isLiteral $node.Left) -or (& $isLiteral $node.Right))) -or
                    ($node -is [System.Management.Automation.Language.SwitchStatementAst] -and -not ($node.Flags -band $patternFlags))
                }, $true) | ForEach-Object { 'line {0}: {1}' -f $_.Extent.StartLineNumber, ($_.Extent.Text -split "`n")[0].Trim() })

        $parseErrors | Should -BeNullOrEmpty
        $cultureComparisons | Should -BeNullOrEmpty
    }

    It 'takes <Case> as a different value' -ForEach @(
        @{ Case = 'a "true" with a zero-width space'; Check = { ConvertTo-BooleanValue ('true' + [char]0x200B) }; Expected = $false }
        @{ Case = 'an allowed release host with a zero-width space'; Check = { Test-AllowedReleaseArtifactUrl ('https://github.com' + [char]0x200B + '/o/r/releases/download/v1/a.zip') }; Expected = $false }
        @{ Case = 'a branch tip status with a zero-width space'; Check = { (Get-BranchTipActionEvidence -Entry @{ repo = 'TipTool'; entrypoint = 'tool.ps1' } -Meta @{ branchTipSha = ('a' * 40); branchTipFetchedAt = '2026-09-23T00:00:00Z'; branchTipStatus = 'fresh' + [char]0x200B; branchTipWarning = $null }).status }; Expected = 'unreachable' }
        @{ Case = 'a public visibility with a zero-width space'; Check = { Test-PublicMetadataHygieneRow -Repo @{ isPrivate = $false; visibility = 'PUB' + [char]0x200B + 'LIC' } -RepoName 'HygieneTool' -Category 'misc' }; Expected = $false }
    ) {
        & $Check | Should -Be $Expected
    }

    It 'still takes the plain values: <Case>' -ForEach @(
        @{ Case = 'true, in any case'; Check = { ConvertTo-BooleanValue 'TRUE' }; Expected = $true }
        @{ Case = 'an allowed release host'; Check = { Test-AllowedReleaseArtifactUrl 'https://github.com/o/r/releases/download/v1/a.zip' }; Expected = $true }
        @{ Case = 'a fresh branch tip'; Check = { (Get-BranchTipActionEvidence -Entry @{ repo = 'TipTool'; entrypoint = 'tool.ps1' } -Meta @{ branchTipSha = ('a' * 40); branchTipFetchedAt = '2026-09-23T00:00:00Z'; branchTipStatus = 'fresh'; branchTipWarning = $null }).status }; Expected = 'fresh' }
        @{ Case = 'a public visibility in lower case'; Check = { Test-PublicMetadataHygieneRow -Repo @{ isPrivate = $false; visibility = 'public' } -RepoName 'HygieneTool' -Category 'misc' }; Expected = $true }
    ) {
        & $Check | Should -Be $Expected
    }
}

Describe 'Backstage catalog export' {
    It 'skips a row whose visibility only looks public' {
        # The gate compared with -ne, by culture, so PUBLIC with a zero-width space passed.
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $hiddenEntry = New-TestEntry -Repo 'HiddenVisibilityTool' -Category 'misc' -Description 'Fixture row'
        $cat.entries = @($cat.entries) + @($hiddenEntry)
        $hiddenMeta = New-TestRepoMeta -Name 'HiddenVisibilityTool' -Description 'Fixture metadata'
        $hiddenMeta.isPrivate = $false
        $hiddenMeta.visibility = 'PUB' + [char]0x200B + 'LIC'

        $export = New-BackstageCatalogExport -Catalog $cat -Repos @((New-TestRepoMeta -Name 'WinTool' -Description 'Public fixture metadata'), $hiddenMeta)

        $export.summary.privateSkippedCount | Should -Be 1
        $export.json | Should -Not -Match 'HiddenVisibilityTool'
    }

    It 'emits public Component descriptors and omits suppressed or private rows' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $privateEntry = New-TestEntry -Repo 'PrivateTool' -Category 'misc' -Description 'Private fixture row'
        $cat.entries = @($cat.entries) + @($privateEntry)

        $publicMeta = New-TestRepoMeta -Name 'WinTool' -Description 'Public fixture metadata'
        $privateMeta = New-TestRepoMeta -Name 'PrivateTool' -Description 'Private fixture metadata'
        $privateMeta.isPrivate = $true
        $privateMeta.visibility = 'PRIVATE'

        $export = New-BackstageCatalogExport -Catalog $cat -Repos @($publicMeta, $privateMeta)
        $entities = @($export.json | ConvertFrom-Json)

        $entities | Should -HaveCount 1
        $entity = $entities[0]
        $entity.apiVersion | Should -Be 'backstage.io/v1alpha1'
        $entity.kind | Should -Be 'Component'
        $entity.metadata.name | Should -Match '^[a-z0-9][a-z0-9-]{0,62}$'
        $entity.metadata.title | Should -Be 'WinTool'
        @($entity.metadata.tags) | Should -Not -BeNullOrEmpty
        $repositoryLink = @($entity.metadata.links)[0]
        $repositoryLink.title | Should -Be 'Repository'
        $repositoryLink.url | Should -Be 'https://github.com/SysAdminDoc/WinTool'
        $entity.spec.owner | Should -Be 'user:default/sysadmindoc'
        $entity.spec.lifecycle | Should -Be 'production'
        $entity.spec.type | Should -Be 'service'

        $export.summary.schemaVersion | Should -Be 'sysadmindoc-backstage-catalog.v1'
        $export.summary.componentCount | Should -Be 1
        $export.summary.suppressedCount | Should -Be 1
        $export.summary.privateSkippedCount | Should -Be 1
        $export.summary.redactionSafe | Should -BeTrue
        $export.json | Should -Not -Match 'HiddenTool|PrivateTool|PRIVATE'
    }

    It 'emits an empty JSON array when public metadata is unavailable' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-BackstageCatalogExportJson -Catalog $cat -Repos @()

        $json | Should -Be '[]'
        @($json | ConvertFrom-Json) | Should -HaveCount 0
        $json | Should -Not -Match 'WinTool|HiddenTool'
    }
}

Describe 'Feed JSON Schema contracts' {
    It 'validates the normalized fixture catalog and generated projects feed' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @()

        $result = Test-FeedSchemaContracts -Catalog $cat -ProjectsJson $json

        $result.passed | Should -BeTrue
        $result.catalog.valid | Should -BeTrue
        $result.projects.valid | Should -BeTrue
    }

    It 'rejects malformed project feed rows' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = ConvertFrom-JsonPreservingArrays -Json (New-ProjectsExportJson -Catalog $cat -Repos @())
        $project = @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name 'projects'))[0]
        Set-MemberValue -Object $project -Name 'repo' -Value $null

        $result = Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-projects.v1.json'

        $result.valid | Should -BeFalse
        $failure = @($result.errors | Where-Object { $_.instanceLocation -eq '/projects/0/repo' })
        $failure | Should -HaveCount 1
        $failure[0].keywordLocation | Should -Be '/properties/projects/items/$ref/properties/repo/type'
        $failure[0].message | Should -Match 'null'
    }

    It 'rejects suppressed feed rows that expose project identifiers' {
        foreach ($field in @('repo', 'repoUrl')) {
            $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
            $payload = ConvertFrom-JsonPreservingArrays -Json (New-ProjectsExportJson -Catalog $cat -Repos @())
            $suppressed = @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name 'suppressed'))[0]
            $value = if ($field -eq 'repo') { 'HiddenTool' } else { 'https://github.com/SysAdminDoc/HiddenTool' }
            Set-MemberValue -Object $suppressed -Name $field -Value $value

            $result = Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-projects.v1.json'

            $result.valid | Should -BeFalse
            $failure = @($result.errors | Where-Object { $_.instanceLocation -eq "/suppressed/0/$field" })
            $failure | Should -HaveCount 1 -Because "$field must be refused on a suppressed row"
            $failure[0].keywordLocation | Should -BeLike '/properties/suppressed/items/*additionalProperties'
        }
    }

    It 'ignores volatile provenance and pushed-at fields in projects sync comparison' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $current = New-ProjectsExportJson -Catalog $cat -Repos @()
        $currentPayload = $current | ConvertFrom-Json
        $currentPayload.projects[0].pushedAt = '2026-06-01T08:00:01Z'
        $current = $currentPayload | ConvertTo-Json -Depth 20
        $expectedPayload = $current | ConvertFrom-Json
        $expectedPayload.provenance.metadataSnapshotAt = '2026-06-06T00:00:00Z'
        $expectedPayload.provenance.sourceCommit = '0000000000000000000000000000000000000000'
        $expectedPayload.projects[0].pushedAt = '2026-06-07T09:56:21Z'
        $expected = $expectedPayload | ConvertTo-Json -Depth 20

        (ConvertTo-ProjectsSyncComparableJson -Json $current) | Should -Be (ConvertTo-ProjectsSyncComparableJson -Json $expected)

        $expectedPayload.provenance.catalogSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $changed = $expectedPayload | ConvertTo-Json -Depth 20
        (ConvertTo-ProjectsSyncComparableJson -Json $current) | Should -Not -Be (ConvertTo-ProjectsSyncComparableJson -Json $changed)
    }

    It 'reports no unsupported keywords for the current schemas' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @()
        $report = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw)

        $result = Test-FeedSchemaContracts -Catalog $cat -ProjectsJson $json
        $reportResult = Test-JsonSchemaContract -Value $report -SchemaPath 'schemas/profile-sync-report.v1.json'

        @($result.catalog.unsupportedKeywords) | Should -HaveCount 0
        @($result.projects.unsupportedKeywords) | Should -HaveCount 0
        @($reportResult.unsupportedKeywords) | Should -HaveCount 0
    }

    It 'requires metadata fetch budget telemetry in the report schema' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $required = @($schema.'$defs'.validationPerformance.properties.metadataFetch.required)

        foreach ($field in @('graphQlPageSize', 'requestCount', 'retryCount', 'resourceLimitFallback', 'resourceLimitFallbackReason', 'truncated')) {
            $required | Should -Contain $field
        }

        @($schema.'$defs'.validationPerformance.required) | Should -Contain 'cache'
        $schema.'$defs'.validationPerformance.properties.cache.'$ref' | Should -Be '#/$defs/validationCache'

        $cacheRequired = @($schema.'$defs'.validationCache.required)
        foreach ($field in @('enabled', 'path', 'ttlHours', 'metadata', 'releases', 'links')) {
            $cacheRequired | Should -Contain $field
        }

        $cacheBucketRequired = @($schema.'$defs'.validationCacheBucket.required)
        foreach ($field in @('hitCount', 'missCount', 'staleCount', 'writeCount', 'fallbackHitCount', 'usedForFallback', 'lastFallbackReason')) {
            $cacheBucketRequired | Should -Contain $field
        }
    }

    It 'requires public-safe metadata hygiene handoff fields in the report schema and summary' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $required = @($schema.'$defs'.metadataHygiene.required)

        foreach ($field in @('publicMissingTopicCount', 'publicMissingDescriptionCount', 'redactedTopicCount', 'redactedDescriptionCount', 'handoff')) {
            $required | Should -Contain $field
        }

        $handoffRequired = @($schema.'$defs'.metadataHygieneHandoff.required)
        foreach ($field in @('status', 'topicRows', 'descriptionRows', 'excludedSuppressedTopicCount', 'excludedUnsafeOrPrivateTopicCount')) {
            $handoffRequired | Should -Contain $field
        }

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'Metadata Hygiene Handoff'
        $summaryScript | Should -Match 'Only public-safe rows are shown'
        $summaryScript | Should -Match 'Metadata handoff topic rows'

        $forkRequired = @($schema.'$defs'.forkParentDrift.required)
        $forkRequired | Should -Contain 'publicDetailRowCount'
        $forkRequired | Should -Contain 'redactedDetailRowCount'
    }

    It 'requires PowerShell runtime security posture in the report schema' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        @($schema.required) | Should -Contain 'runtimeSecurity'
        $schema.properties.runtimeSecurity.'$ref' | Should -Be '#/$defs/runtimeSecurity'

        $required = @($schema.'$defs'.runtimeSecurity.required)
        foreach ($field in @('status', 'current', 'policy', 'capabilities', 'supported', 'preferred', 'warningCount', 'warnings')) {
            $required | Should -Contain $field
        }

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'PowerShell runtime status'
        $summaryScript | Should -Match 'PowerShell runtime posture'
    }

    It 'requires rendered smoke visual evidence fields in the report schema and summary' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $required = @($schema.'$defs'.renderedProfileSmoke.required)

        foreach ($field in @(
                'screenshotCount',
                'screenshotPaths',
                'firstViewportHeaderCount',
                'firstViewportStartHereCount',
                'toolCatalogPresenceCount',
                'footerPresenceCount',
                'blankViewportCount',
                'croppedElementCount',
                'overlapWarningCount',
                'accessibilityEvidenceAvailable',
                'detailsCount',
                'detailsSummaryCount',
                'detailsKeyboardCheckCount',
                'detailsKeyboardPassedCount',
                'detailsKeyboardFailedCount',
                'detailsCollapsedFocusPassCount',
                'detailsExpandedFocusPassCount',
                'detailsActivationPassCount',
                'detailsKeyboardSanityPassed',
                'tableCount',
                'tableOverflowCount',
                'linkCount',
                'linkLabelCount',
                'uniqueLinkLabelCount',
                'duplicateLinkLabelCount',
                'actionableLinkCount',
                'uniqueActionableLinkLabelCount',
                'emptyLinkLabelCount',
                'nonActionableLinkCount',
                'ambiguousCrossDestinationLinkLabelCount',
                'linkLabelSanityPassed',
                'desktopPassedCount',
                'desktopFailedCount',
                'mobilePassedCount',
                'mobileFailedCount'
            )) {
            $required | Should -Contain $field
        }

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'Rendered smoke screenshots'
        $summaryScript | Should -Match 'Rendered smoke first-viewport header count'
        $summaryScript | Should -Match 'Rendered smoke first-viewport Start Here count'
        $summaryScript | Should -Match 'Rendered smoke Tool Catalog count'
        $summaryScript | Should -Match 'Rendered smoke footer count'
        $summaryScript | Should -Match 'Rendered smoke blank viewports'
        $summaryScript | Should -Match 'Rendered smoke cropped elements'
        $summaryScript | Should -Match 'Rendered smoke overlap warnings'
        $summaryScript | Should -Match 'Rendered smoke details keyboard sanity'
        $summaryScript | Should -Match 'Rendered smoke table overflow'
        $summaryScript | Should -Match 'Rendered smoke unique actionable link labels'
        $summaryScript | Should -Match 'Rendered smoke desktop passed'
        $summaryScript | Should -Match 'Rendered smoke mobile failed'
    }

    It 'requires the opt-in release artifact verification report contract' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        @($schema.required) | Should -Contain 'releaseArtifactVerification'
        $required = @($schema.'$defs'.releaseArtifactVerification.required)
        foreach ($field in @('enabled', 'status', 'verificationMode', 'maxAssets', 'maxBytes', 'verifiedCount', 'skippedCount', 'failureCount', 'rows', 'note')) {
            $required | Should -Contain $field
        }
        $rowRequired = @($schema.'$defs'.releaseArtifactVerificationRow.required)
        foreach ($field in @('repo', 'asset', 'checksumAsset', 'status', 'reason', 'expectedSha256', 'actualSha256')) {
            $rowRequired | Should -Contain $field
        }

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'Release artifact verification'
        $summaryScript | Should -Match 'Release artifacts verified'
        $summaryScript | Should -Match 'Release artifact verification failures'
    }

    It 'requires branch-tip provenance evidence for branch-backed install actions' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        @($schema.required) | Should -Contain 'branchTipProvenance'
        $required = @($schema.'$defs'.branchTipProvenance.required)
        foreach ($field in @('status', 'checkedInstallActionCount', 'staleAfterHours', 'freshCount', 'staleCount', 'unreachableCount', 'missingCount', 'warningCount', 'statusCounts', 'rows', 'note')) {
            $required | Should -Contain $field
        }
        $rowRequired = @($schema.'$defs'.branchTipProvenanceRow.required)
        foreach ($field in @('repo', 'branch', 'branchTipSha', 'branchTipFetchedAt', 'status', 'warning')) {
            $rowRequired | Should -Contain $field
        }

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'Branch-tip provenance'
        $summaryScript | Should -Match 'Fresh branch-tip rows'
    }

    It 'requires the opt-in Backstage catalog export report contract' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        @($schema.required) | Should -Contain 'backstageCatalogExport'
        $required = @($schema.'$defs'.backstageCatalogExport.required)
        foreach ($field in @('enabled', 'status', 'outputPath', 'schemaVersion', 'componentCount', 'suppressedCount', 'privateSkippedCount', 'missingMetadataCount', 'redactionSafe', 'note')) {
            $required | Should -Contain $field
        }
        $schema.'$defs'.backstageCatalogExport.properties.schemaVersion.const | Should -Be 'sysadmindoc-backstage-catalog.v1'
        $schema.'$defs'.backstageCatalogExport.properties.redactionSafe.const | Should -BeTrue

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'Backstage export'
        $summaryScript | Should -Match 'Backstage components'
        $summaryScript | Should -Match 'Backstage suppressed rows omitted'
        $summaryScript | Should -Match 'Backstage private rows omitted'
    }

    It 'requires the warning-only portfolio cross-surface probe report contract' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        @($schema.required) | Should -Contain 'portfolioCrossSurfaceProbe'
        $required = @($schema.'$defs'.portfolioCrossSurfaceProbe.required)
        foreach ($field in @('enabled', 'status', 'portfolioUrl', 'feedUrl', 'localFeedGeneratedAt', 'deployedPortfolioGeneratedAt', 'deployedProfileFeedGeneratedAt', 'localFeedSchemaVersion', 'expectedPortfolioSchemaVersion', 'deployedPortfolioSchemaVersion', 'localRouteCounts', 'deployedRouteCounts', 'rootStatusCode', 'feedStatusCode', 'feedFetchSucceeded', 'routeProbeCount', 'routeProbePassedCount', 'routeProbeFailedCount', 'routeProbes', 'warningCount', 'warnings', 'note')) {
            $required | Should -Contain $field
        }
        @($schema.'$defs'.portfolioCrossSurfaceRouteCounts.required) | Should -Be @('catalog', 'featured', 'liveApps')
        @($schema.'$defs'.portfolioCrossSurfaceRouteProbe.required) | Should -Be @('path', 'url', 'ok', 'statusCode', 'error')
        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'portfolioCrossSurfaceProbe'
        $summaryScript | Should -Match 'warning-only portfolio cross-surface probe'
    }

    It 'validates the committed profile sync report contract' {
        $report = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw)

        $result = Test-JsonSchemaContract -Value $report -SchemaPath 'schemas/profile-sync-report.v1.json'

        $report.schema | Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/schemas/profile-sync-report.v1.json'
        $report.schemaValidation.report.schemaPath | Should -Be 'schemas/profile-sync-report.v1.json'
        $report.schemaValidation.report.valid | Should -BeTrue
        $result.valid | Should -BeTrue
    }

    It 'keeps committed release and license trust drift resolved' {
        $report = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw)

        @(Get-JsonArrayItems $report.releaseAssetDrift.releaseAssetKindMismatches) | Should -HaveCount 0
        [int]$report.projectLicenseMetadata.unresolvedUnknownCount | Should -Be 0
        @(Get-JsonArrayItems $report.projectLicenseMetadata.unknownLicenses | Where-Object { $_.intentionalException -ne $true }) | Should -HaveCount 0
    }

    It 'allows arbitrary metadata drift old and new values in the report schema' {
        $report = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw)
        $metadataDrift = @(
            [ordered]@{
                repo = 'ZeusWatch'
                category = 'android'
                field = 'releaseAssetNames'
                oldValue = @('ZeusWatch-v1.21.3.apk', 'ZeusWatch-v1.21.3.apk.sha256')
                newValue = @('ZeusWatch-v1.21.4.apk')
                severity = 'fatal'
                failing = $true
            }
        )
        if ($report -is [System.Collections.IDictionary]) {
            $report['metadataDrift'] = $metadataDrift
        } else {
            $report.metadataDrift = $metadataDrift
        }

        $result = Test-JsonSchemaContract -Value $report -SchemaPath 'schemas/profile-sync-report.v1.json'

        $result.valid | Should -BeTrue
        @($result.errors) | Should -HaveCount 0
    }

    It 'rejects profile sync reports missing a required section' {
        $report = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw)
        if ($report -is [System.Collections.IDictionary]) {
            $report.Remove('releaseAssetDrift')
        } else {
            $report.PSObject.Properties.Remove('releaseAssetDrift')
        }

        $result = Test-JsonSchemaContract -Value $report -SchemaPath 'schemas/profile-sync-report.v1.json'

        $result.valid | Should -BeFalse
        $failure = @($result.errors | Where-Object { $_.keywordLocation -eq '/required' })
        $failure | Should -HaveCount 1
        $failure[0].instanceLocation | Should -Be '' -Because 'a missing top-level section is a failure at the document root'
        $failure[0].message | Should -Match 'releaseAssetDrift'
    }

    It 'reports every schema failure with its instance location, keyword location and message' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = ConvertFrom-JsonPreservingArrays -Json (New-ProjectsExportJson -Catalog $cat -Repos @())
        $projects = @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name 'projects'))
        Set-MemberValue -Object $projects[0] -Name 'repo' -Value 42
        Set-MemberValue -Object $projects[1] -Name 'title' -Value $null
        Set-MemberValue -Object $payload -Name 'undeclaredTopLevelField' -Value 'x'

        $result = Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-projects.v1.json'

        $result.valid | Should -BeFalse
        @($result.errors).Count | Should -BeGreaterOrEqual 3
        foreach ($schemaError in @($result.errors)) {
            @($schemaError.Keys) | Should -Be @('instanceLocation', 'keywordLocation', 'message')
            $schemaError.instanceLocation | Should -Match '^(/.*)?$'
            $schemaError.keywordLocation | Should -Match '^/'
            $schemaError.message | Should -Not -BeNullOrEmpty
        }
        $instances = @($result.errors | ForEach-Object instanceLocation)
        $instances | Should -Contain '/projects/0/repo'
        $instances | Should -Contain '/projects/1/title'
        $instances | Should -Contain '/undeclaredTopLevelField'
        # Stable order: sorted by instance, then keyword, so reruns produce the same report.
        $instances | Should -Be @($instances | Sort-Object { ConvertTo-OrdinalSortKey $_ })
    }

    It 'reports a missing schema file as a structured error with no locations' {
        $result = Test-JsonSchemaContract -Value @{} -SchemaPath (Join-Path $TestDrive 'no-such-schema.json')

        $result.valid | Should -BeFalse
        @($result.errors) | Should -HaveCount 1
        # Null, not "": an empty pointer means the document root.
        $null -eq $result.errors[0].instanceLocation | Should -BeTrue
        $null -eq $result.errors[0].keywordLocation | Should -BeTrue
        $result.errors[0].message | Should -Match 'schema file not found'
    }

    It 'reports only the failures that decide the result, including a failed not' {
        $schemaPath = Join-Path $TestDrive 'composition.json'
        Set-Content -LiteralPath $schemaPath -Encoding utf8 -Value @'
{
  "type": "object",
  "properties": {
    "a": { "anyOf": [ { "type": "string" }, { "type": "integer" } ] },
    "b": { "not": { "type": "integer" } },
    "c": { "type": "string" }
  }
}
'@

        $result = Test-JsonSchemaContract -Value ([ordered]@{ a = 5; b = 7; c = 1 }) -SchemaPath $schemaPath

        $result.valid | Should -BeFalse
        @($result.errors | ForEach-Object instanceLocation) | Should -Be @('/b', '/c') -Because 'the anyOf branch that failed while another passed did not cause the failure'
        $result.errors[0].keywordLocation | Should -Be '/properties/b/not'
        $result.errors[0].message | Should -Match 'not'
        $result.errors[1].keywordLocation | Should -Be '/properties/c/type'
    }

    It 'holds a string to its schema format' {
        # JsonSchema.Net skips format unless asked, so a date-time of "yesterday" and a uri of
        # "not a uri" passed every schema check.
        $schemaPath = Join-Path $TestDrive 'formats.json'
        Set-Content -LiteralPath $schemaPath -Encoding utf8 -Value '{"type":"object","properties":{"at":{"type":"string","format":"date-time"},"link":{"type":"string","format":"uri"}}}'

        $bad = Test-JsonSchemaContract -Value ([ordered]@{ at = 'yesterday'; link = 'not a uri' }) -SchemaPath $schemaPath
        $good = Test-JsonSchemaContract -Value ([ordered]@{ at = '2026-09-24T10:00:00Z'; link = 'https://example.test/' }) -SchemaPath $schemaPath

        $bad.valid | Should -BeFalse
        (@($bad.errors | ForEach-Object keywordLocation | Sort-Object) -join ' ; ') | Should -Be '/properties/at/format ; /properties/link/format'
        $good.valid | Should -BeTrue
    }

    It 'lets both schemas accept every metadata provider the generator records' {
        # The enums held graphql and rest-fallback only, so a run that fell back to cached
        # metadata (cache-fallback) failed its own schema check and wrote nothing. The scan
        # reads the syntax tree, so a spaced, computed or appended value can't slip past it:
        # every assignment is a string constant, or the snapshot restore, whose values come
        # from Test-CompleteGenerationSnapshot's allow-list.
        $sources = @('scripts/sync-profile.ps1') + @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'scripts/sync-profile') -Filter '*.ps1' | ForEach-Object { 'scripts/sync-profile/' + $_.Name })
        $providers = [System.Collections.Generic.List[string]]::new()
        $restores = [System.Collections.Generic.List[string]]::new()
        $allowList = $null
        foreach ($source in $sources) {
            $tokens = $null
            $parseErrors = $null
            $tree = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot $source), [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty -Because "$source has to parse"
            $assignments = $tree.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -eq 'script:RepositoryMetadataProvider'
            }, $true)
            foreach ($assignment in $assignments) {
                $owner = $assignment.Parent
                while ($null -ne $owner -and $owner -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $owner = $owner.Parent }
                $ownerName = if ($null -eq $owner) { '(script)' } else { $owner.Name }
                if ($assignment.Operator -eq 'Equals' -and
                    $assignment.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
                    $assignment.Right.Expression -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $providers.Add($assignment.Right.Expression.Value)
                } else {
                    # The restore has to check the snapshot, allow-list included, before it assigns.
                    $checked = $null -ne $owner -and $null -ne $owner.Find({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -eq 'Test-CompleteGenerationSnapshot' -and
                        $node.Extent.StartOffset -lt $assignment.Extent.StartOffset
                    }, $true)
                    $restores.Add("$ownerName in $source, checked first: $checked")
                }
            }
            $snapshotCheck = $tree.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-CompleteGenerationSnapshot'
            }, $true)
            if ($null -ne $snapshotCheck) {
                # The allow-list is an array's Contains, which compares with String.Equals: exact,
                # like the enums. -cnotin compared by culture and skipped an invisible character.
                $providerTest = @($snapshotCheck.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $node.Member.Value -eq 'Contains' -and
                    @($node.Arguments).Count -eq 1 -and
                    $node.Arguments[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $node.Arguments[0].VariablePath.UserPath -eq 'provider'
                }, $true))
                $providerTest | Should -HaveCount 1 -Because 'the snapshot check tests the provider once'
                $providerTest[0].Expression | Should -BeOfType ([System.Management.Automation.Language.ArrayExpressionAst]) -Because 'the allow-list is a literal array'
                $allowList = @($providerTest[0].Expression.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
            }
        }

        $providers | Should -Contain 'cache-fallback' -Because 'the scan has to find the cache fallback'
        ($restores -join '; ') | Should -Be 'Set-GenerationStateFromSnapshot in scripts/sync-profile/artifact-store.ps1, checked first: True' -Because 'only the snapshot restore may assign a value that is not a string constant'
        $allowList | Should -Contain 'graphql' -Because 'the scan has to find the snapshot allow-list'
        $providers = @($providers) + @($allowList) | Sort-Object -Unique
        foreach ($schemaPath in 'schemas/profile-projects.v1.json', 'schemas/profile-sync-report.v1.json') {
            $schemaText = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $schemaPath))
            $enum = [regex]::Match($schemaText, '"metadataProvider":\s*\{\s*"type":\s*"string",\s*"enum":\s*\[(?<values>[^\]]*)\]')
            $enum.Success | Should -BeTrue -Because "$schemaPath declares the provider enum"
            $allowed = @([regex]::Matches($enum.Groups['values'].Value, '"(?<v>[^"]+)"') | ForEach-Object { $_.Groups['v'].Value })
            @($providers | Where-Object { $allowed -notcontains $_ }) | Should -BeNullOrEmpty -Because "$schemaPath must accept every provider"
        }
    }

    It 'prints schema values as written, without JSON escapes' {
        # A const failure used to show the value's JSON text escaped twice, every quote, & and
        # < as a backslash-u escape, and required listed names the same way.
        $cafe = 'caf' + [char]0xE9
        $schemaPath = Join-Path $TestDrive 'plain-messages.json'
        $schema = [ordered]@{
            type = 'object'
            required = @('needed', $cafe)
            properties = [ordered]@{
                url = @{ const = 'https://example.test/a?b=1&c=<d> "quoted" ' + $cafe }
                count = @{ const = 42 }
                kind = @{ enum = @('one', 'two') }
                name = @{ type = 'string'; pattern = '^[a-z]+$' }
            }
        }
        [System.IO.File]::WriteAllText($schemaPath, ($schema | ConvertTo-Json -Depth 10))

        $result = Test-JsonSchemaContract -Value ([ordered]@{ url = 'x'; count = 1; kind = 'three'; name = 'ABC' }) -SchemaPath $schemaPath
        $byKeyword = @{}
        foreach ($schemaError in @($result.errors)) { $byKeyword[$schemaError.keywordLocation] = $schemaError }

        $byKeyword['/properties/url/const'].message | Should -BeExactly ('Expected "https://example.test/a?b=1&c=<d> "quoted" ' + $cafe + '"')
        $byKeyword['/properties/url/const'].instanceLocation | Should -Be '/url'
        $byKeyword['/properties/count/const'].message | Should -BeExactly 'Expected 42'
        $byKeyword['/required'].message | Should -Match ([regex]::Escape($cafe))
        @($byKeyword.Keys) | Should -Contain '/properties/kind/enum'
        @($byKeyword.Keys) | Should -Contain '/properties/name/pattern'
        foreach ($schemaError in @($result.errors)) {
            $schemaError.message | Should -Not -Match '\\u[0-9A-Fa-f]{4}'
        }
    }

    It 'prints tricky schema values by their structure, never decoding them twice' {
        # A catch-all decode after the const branch turned a string holding the text
        # backslash-u-0041 into "A", brought a control character in an object back raw so the
        # printed value stopped being JSON, and left required names half decoded.
        $bs = [string][char]92
        $schemaPath = Join-Path $TestDrive 'tricky-messages.json'
        $schema = [ordered]@{
            type = 'object'
            required = @('q"uote', ('back' + $bs + 'slash'), "nl`nx")
            properties = [ordered]@{
                literal = @{ const = $bs + 'u0041' }
                escape = @{ const = [ordered]@{ s = 'a' + [char]27 + 'b' } }
                list = @{ const = @(1, 'two', '<3>') }
            }
        }
        [System.IO.File]::WriteAllText($schemaPath, ($schema | ConvertTo-Json -Depth 10))

        $result = Test-JsonSchemaContract -Value ([ordered]@{ literal = 'x'; escape = @{}; list = @() }) -SchemaPath $schemaPath
        $byKeyword = @{}
        foreach ($schemaError in @($result.errors)) { $byKeyword[$schemaError.keywordLocation] = [string]$schemaError.message }

        $byKeyword['/properties/literal/const'] | Should -BeExactly ('Expected "' + $bs + 'u0041"')
        (ConvertFrom-Json -InputObject ($byKeyword['/properties/escape/const'] -replace '^Expected ', '')).s | Should -BeOrdinal ('a' + [char]27 + 'b')
        $byKeyword['/properties/list/const'] | Should -BeOrdinal 'Expected [1,"two","<3>"]'
        $names = ConvertFrom-Json -InputObject ($byKeyword['/required'] -replace '^Required properties ', '' -replace ' are not present$', '')
        @($names) | Should -Be @('q"uote', ('back' + $bs + 'slash'), "nl`nx")
    }

    It 'requires always-emitted nested profile sync report fields' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json

        $schema.'$defs'.readmeExperienceChecks.required | Should -Contain 'imageTagCount'
        $schema.'$defs'.readmeExperienceChecks.required | Should -Contain 'imageAltTextIssueCount'
        $schema.'$defs'.readmeExperienceChecks.required | Should -Contain 'imageAltTextComplete'
        $schema.'$defs'.communityHealth.required | Should -Contain 'localIssueFormCount'
        $schema.'$defs'.communityHealth.required | Should -Contain 'issueTemplateProviderState'
        $schema.'$defs'.communityHealth.required | Should -Contain 'infoCount'
        $schema.'$defs'.communityHealth.required | Should -Contain 'info'
        $schema.'$defs'.userscriptInstallTrust.required | Should -Contain 'releaseChannelReadyCount'
        $schema.'$defs'.userscriptInstallTrust.required | Should -Contain 'releaseChannelKeepBranchCount'
        $schema.'$defs'.userscriptInstallTrust.required | Should -Contain 'releaseChannelBlockedCount'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'readmeActionTargetCount'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'readmeInstallSnippetTargetCount'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'readmeDownloadLinkTargetCount'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'readmeUserscriptInstallTargetCount'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'liveProbedCount'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'cacheServedCount'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'oldestCacheEntryAgeHours'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'allResultsFromCache'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'skipped'
        $schema.'$defs'.linkValidationSummary.required | Should -Contain 'skipReason'
        $schema.'$defs'.releaseAssetDrift.required | Should -Contain 'executableDownloadTrustShortlist'
    }

    It 'records why link validation was skipped instead of reporting zero probed targets' {
        $report = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') | ConvertFrom-Json
        $summary = $report.linkValidationSummary

        # A skipped run and a clean run both leave targetCount at 0 for the skipped case,
        # so the skip must be explicit or a skipped lane reads as validated.
        $summary.skipped | Should -Be $report.linkValidationSkipped
        if ($summary.skipped) {
            $summary.skipReason | Should -Not -BeNullOrEmpty
        } else {
            $summary.skipReason | Should -BeNullOrEmpty
            $summary.targetCount | Should -BeGreaterThan 0
        }
    }

    It 'warns when a schema uses keywords outside the project compatibility allowlist' {
        $schemaPath = Join-Path $TestDrive 'unsupported.json'
        $unsupportedSchema = @{
            type = 'object'
            oneOf = @(@{ type = 'string' })
            maxProperties = 10
        } | ConvertTo-Json -Depth 5 -Compress
        Set-Content -LiteralPath $schemaPath -Value $unsupportedSchema -Encoding utf8

        $result = Test-JsonSchemaContract -Value @{} -SchemaPath $schemaPath

        @($result.unsupportedKeywords).Count | Should -BeGreaterOrEqual 2
        ($result.unsupportedKeywords -join "`n") | Should -Match 'oneOf'
        ($result.unsupportedKeywords -join "`n") | Should -Match 'maxProperties'
    }

    It 'walks composition branches, conditionals and nested definitions for unsupported keywords' {
        $schema = ConvertFrom-JsonPreservingArrays -Json (@'
{
  "type": "object",
  "properties": {
    "a": { "anyOf": [ { "type": "string", "maxProperties": 3 }, { "type": "null" } ] },
    "b": { "$defs": { "inner": { "type": "integer", "multipleOf": 2 } }, "$ref": "#/properties/b/$defs/inner" },
    "c": { "if": { "type": "string" }, "then": { "minProperties": 1 }, "else": true },
    "d": { "type": "array", "prefixItems": [ { "type": "string", "exclusiveMaximum": 5 } ] },
    "e": { "type": "object", "additionalProperties": { "type": "string", "uniqueItems": true } },
    "f": { "dependencies": { "x": { "maxProperties": 1 }, "y": [ "z" ] }, "contentSchema": { "minProperties": 1 } }
  },
  "$defs": { "outer": { "allOf": [ { "not": { "maxItems": 1 } } ] } }
}
'@)

        $warnings = @(Test-SchemaKeywordCoverage -Schema $schema)

        $expected = @(
            "`$.properties.a uses schema keyword 'anyOf'",
            "`$.properties.a.anyOf[0] uses schema keyword 'maxProperties'",
            "`$.properties.b.`$defs.inner uses schema keyword 'multipleOf'",
            "`$.properties.c uses schema keyword 'if'",
            "`$.properties.c.then uses schema keyword 'minProperties'",
            "`$.properties.d.prefixItems[0] uses schema keyword 'exclusiveMaximum'",
            "`$.properties.e.additionalProperties uses schema keyword 'uniqueItems'",
            "`$defs.outer uses schema keyword 'allOf'",
            "`$defs.outer.allOf[0].not uses schema keyword 'maxItems'",
            "`$.properties.f.dependencies.x uses schema keyword 'maxProperties'",
            "`$.properties.f.contentSchema uses schema keyword 'minProperties'"
        )
        foreach ($warning in $expected) {
            @($warnings | Where-Object { $_.StartsWith($warning, [StringComparison]::Ordinal) }) | Should -HaveCount 1 -Because "the walker must reach: $warning"
        }
    }
}

Describe 'Doc version consistency gate' {
    BeforeAll {
        function New-TestProfileVersionFile {
            param(
                [string]$Version = 'v4.9.20',
                [string]$Date = '2026-06-04',
                [switch]$MalformedJson
            )

            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root | Out-Null
            $path = Join-Path $root 'profile-version.json'
            if ($MalformedJson) {
                Set-Content -LiteralPath $path -Value '{' -Encoding utf8
                return $path
            }

            [ordered]@{
                version = $Version
                date = $Date
                source = 'test'
                publicReleaseCadence = 'manual-public-milestone-only'
            } | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8

            return $path
        }
    }

    It 'passes when the tracked profile version file exposes a valid version and date' {
        $path = New-TestProfileVersionFile

        $result = Test-DocVersionConsistency -ProfileVersionPath $path

        $result.passed | Should -BeTrue
        $result.expectedVersion | Should -Be 'v4.9.20'
        $result.expectedDate | Should -Be '2026-06-04'
        $result.changelogHeadingValidation.passed | Should -BeTrue
        $result.changelogHeadingValidation.headingCount | Should -Be 0
        $result.changelogHeadingValidation.malformedCount | Should -Be 0
        @($result.errors) | Should -HaveCount 0
    }

    It 'rejects an invalid tracked profile version value' {
        $path = New-TestProfileVersionFile -Version '4.9'

        $result = Test-DocVersionConsistency -ProfileVersionPath $path

        $result.passed | Should -BeFalse
        ($result.errors -join "`n") | Should -Match 'must match vMAJOR\.MINOR\.PATCH'
    }

    It 'rejects an invalid tracked profile version date' {
        $path = New-TestProfileVersionFile -Date '2026-99-99'

        $result = Test-DocVersionConsistency -ProfileVersionPath $path

        $result.passed | Should -BeFalse
        ($result.errors -join "`n") | Should -Match 'not a valid yyyy-MM-dd date'
    }

    It 'rejects unreadable tracked profile version JSON' {
        $path = New-TestProfileVersionFile -MalformedJson

        $result = Test-DocVersionConsistency -ProfileVersionPath $path

        $result.passed | Should -BeFalse
        ($result.errors -join "`n") | Should -Match 'unreadable JSON'
    }

    It 'does not require local-only planning markdown in a CI-shaped checkout' {
        $path = New-TestProfileVersionFile

        $result = Test-DocVersionConsistency -ProfileVersionPath $path

        $result.passed | Should -BeTrue
        ($result.versions + $result.dates | ForEach-Object { $_.path }) | Should -Not -Match 'CHANGELOG|PROJECT_CONTEXT|RESEARCH_REPORT|ROADMAP'
    }
}

Describe 'Public planning document terminology' {
    It 'does not present privateReason as a current catalog field in tracked schemas' {
        $schema = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-catalog.v1.json')

        $schema | Should -Not -Match 'privateReason'
        $schema | Should -Match 'suppressionReason'
        $schema | Should -Match 'allowPublicMedical'
        $schema | Should -Match 'aliasOf'
        $schema | Should -Match 'forkOf'
        $schema | Should -Match 'upstreamLicense'
    }
}

Describe 'Repository formatting contract' {
    It 'pins LF endings, final newlines, and trailing-whitespace trimming in EditorConfig' {
        $editorConfig = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.editorconfig')
        $gitAttributes = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.gitattributes')

        $editorConfig | Should -Match '(?m)^root\s*=\s*true\s*$'
        $editorConfig | Should -Match '(?m)^end_of_line\s*=\s*lf\s*$'
        $editorConfig | Should -Match '(?m)^insert_final_newline\s*=\s*true\s*$'
        $editorConfig | Should -Match '(?m)^trim_trailing_whitespace\s*=\s*true\s*$'
        $editorConfig | Should -Not -Match '(?m)^trim_trailing_whitespace\s*=\s*false\s*$'
        $gitAttributes | Should -Match '(?m)^\.gitattributes\s+text\s+eol=lf\s*$'
        $gitAttributes | Should -Match '(?m)^\.editorconfig\s+text\s+eol=lf\s*$'
        $gitAttributes | Should -Match '(?m)^\.gitignore\s+text\s+eol=lf\s*$'
        $gitAttributes | Should -Match '(?m)^\.github/CODEOWNERS\s+text\s+eol=lf\s*$'
        $gitAttributes | Should -Match '(?m)^\.markdownlint-cli2\.yaml\s+text\s+eol=lf\s*$'
        $gitAttributes | Should -Match '(?m)^package\.json\s+text\s+eol=lf\s*$'
        $gitAttributes | Should -Match '(?m)^package-lock\.json\s+text\s+eol=lf\s*$'
        $gitAttributes | Should -Match '(?m)^[*]\.yaml\s+text\s+eol=lf\s*$'
    }

    It 'keeps tracked Markdown free of trailing whitespace' {
        $markdownPaths = @(& git -C $script:RepoRoot ls-files '*.md' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $violations = @(Get-MarkdownTrailingWhitespaceViolations -RootPath $script:RepoRoot -RelativePaths $markdownPaths)

        $violations | Should -HaveCount 0
    }

    It 'handles zero, one, and many Markdown trailing-whitespace violations' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('SysAdminDoc-markdown-trailing-whitespace-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $root -Force
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText((Join-Path $root 'clean.md'), "# Clean`nNo trailing whitespace`n", $utf8NoBom)
            [System.IO.File]::WriteAllText((Join-Path $root 'one.md'), ('trim me' + '  ' + "`n"), $utf8NoBom)
            [System.IO.File]::WriteAllText(
                (Join-Path $root 'many.md'),
                ('first' + ' ' + "`n" + 'second' + "`t`n" + 'third' + "`n"),
                $utf8NoBom
            )

            @(Get-MarkdownTrailingWhitespaceViolations -RootPath $root -RelativePaths 'clean.md') | Should -HaveCount 0

            $oneViolation = @(Get-MarkdownTrailingWhitespaceViolations -RootPath $root -RelativePaths 'one.md')
            $oneViolation | Should -HaveCount 1
            $oneViolation[0] | Should -Be 'one.md:1'

            $manyViolations = @(Get-MarkdownTrailingWhitespaceViolations -RootPath $root -RelativePaths @('one.md', 'many.md'))
            $manyViolations | Should -HaveCount 3
            $manyViolations | Should -Contain 'one.md:1'
            $manyViolations | Should -Contain 'many.md:1'
            $manyViolations | Should -Contain 'many.md:2'
        } finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}

Describe 'Markdownlint contract' {
    BeforeAll {
        $script:MarkdownlintConfig = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.markdownlint-cli2.yaml')
        $script:MarkdownlintPackage = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'package.json') | ConvertFrom-Json -AsHashtable
        $script:MarkdownlintPackageLock = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'package-lock.json') | ConvertFrom-Json -AsHashtable
        $script:MarkdownlintCodeowners = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.github/CODEOWNERS')
        $script:MarkdownlintGitIgnore = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.gitignore')
    }

    It 'defines generated README-safe markdownlint rules' {
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD013:\s+false\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD031:\s+false\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD034:\s+false\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD041:\s+false\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD060:\s+false\s*$'
        foreach ($tag in @('details', 'summary', 'kbd', 'br', 'sub', 'p', 'picture', 'source', 'img', 'a', 'b', 'i', 'code')) {
            $script:MarkdownlintConfig | Should -Match "(?m)^\s+- $tag\s*$"
        }
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "README[.]md"\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "SECURITY[.]md"\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "[.]github/pull_request_template[.]md"\s*$'
        $script:MarkdownlintConfig | Should -Not -Match 'docs/[*][*]/[*][.]md'
        $globsBlock = [regex]::Match($script:MarkdownlintConfig, '(?ms)^globs:\s*(?<body>.*?)(?=^ignores:|\z)').Groups['body'].Value
        $ignoresBlock = [regex]::Match($script:MarkdownlintConfig, '(?ms)^ignores:\s*(?<body>.*)\z').Groups['body'].Value
        foreach ($localDoc in @(
                'AGENTS.md',
                'CHANGELOG.md',
                'CLAUDE.md',
                'CODEX_CHANGELOG.md',
                'CONTINUATION_PROMPT.md',
                'PROJECT_CONTEXT.md',
                'RESEARCH.md',
                'ROADMAP.md',
                'Roadmap_Blocked.md',
                'TODO.md',
                'RESEARCH_FEATURE_PLAN.md'
            )) {
            $quotedPattern = '(?m)^\s*- "{0}"\s*$' -f [regex]::Escape($localDoc)
            $globsBlock | Should -Not -Match $quotedPattern
            $ignoresBlock | Should -Match $quotedPattern
        }
    }

    It 'pins markdownlint through npm and keeps local installs ignored' {
        $script:MarkdownlintPackage.scripts['lint:markdown'] | Should -Be 'markdownlint-cli2'
        $script:MarkdownlintPackage.scripts['validate:local'] | Should -Be 'pwsh -NoProfile -File ./scripts/validate-local.ps1'
        $script:MarkdownlintPackage.devDependencies['markdownlint-cli2'] | Should -Be '0.23.2'
        $script:MarkdownlintPackageLock.name | Should -Be 'sysadmindoc-profile'
        $script:MarkdownlintPackageLock.packages[''].devDependencies['markdownlint-cli2'] | Should -Be '0.23.2'
        $script:MarkdownlintPackageLock.packages['node_modules/markdownlint-cli2'].version | Should -Be '0.23.2'
        $script:MarkdownlintPackageLock.packages['node_modules/markdownlint-cli2'].integrity | Should -Match '^sha512-'
        $script:MarkdownlintGitIgnore | Should -Match '(?m)^node_modules/\s*$'
        $script:MarkdownlintCodeowners | Should -Match '(?m)^/[.]markdownlint-cli2[.]yaml\s+@SysAdminDoc\s*$'
        $script:MarkdownlintCodeowners | Should -Match '(?m)^/package-lock[.]json\s+@SysAdminDoc\s*$'
    }

    It 'keeps markdownlint local-only without workflow or Dependabot config' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/tests.yml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/dependabot.yml') | Should -BeFalse
    }
}

Describe 'Profile render-host decision record' {
    It 'reports that no live third-party profile render hosts are retained' {
        $report = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') | ConvertFrom-Json

        $report.readmeExperienceChecks.thirdPartyRenderHostCount | Should -Be 0
        $report.readmeExperienceChecks.thirdPartyMetricHostCount | Should -Be 0
        $report.readmeExperienceChecks.thirdPartyBadgeHostCount | Should -Be 0
        $report.readmeExperienceChecks.motionSafeChrome | Should -BeTrue
    }
}

Describe 'Code scanning posture decision' {
    It 'reports PowerShell-only CodeQL as not applicable without hosted SARIF controls' {
        $report = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') | ConvertFrom-Json
        $codeScanning = $report.repositorySettings.security.codeScanning

        $codeScanning.status | Should -Be 'not-applicable'
        $codeScanning.recommendation | Should -Be 'not-applicable-powershell-only'
        $codeScanning.codeqlSupportedLanguageDetected | Should -BeFalse
        $codeScanning.codeqlWorkflowPresent | Should -BeFalse
        @($codeScanning.PSObject.Properties.Name) | Should -Not -Contain 'scorecardSarifUploadPresent'
        $codeScanning.localControls | Should -Contain 'local-validation-bootstrap'
        $codeScanning.localControls | Should -Contain 'psscriptanalyzer'
        $codeScanning.localControls | Should -Contain 'pester'
        $codeScanning.localControls | Should -Contain 'markdownlint'
        $codeScanning.hostedControls | Should -Contain 'secret-scanning'
        $codeScanning.hostedControls | Should -Contain 'secret-scanning-push-protection'
        # Repository policy bans Dependabot, so it must not appear as an active control.
        # Advisory coverage is the local npm audit lane inside validate-local.ps1.
        $codeScanning.hostedControls | Should -Not -Contain 'dependabot-security-updates'
        $codeScanning.hostedControls | Should -Not -Contain 'psscriptanalyzer'
        $codeScanning.hostedControls | Should -Not -Contain 'openssf-scorecard-sarif'
        $codeScanning.activeControls | Should -Contain 'psscriptanalyzer'
        $codeScanning.activeControls | Should -Not -Contain 'dependabot-security-updates'
        $immutableReleases = $report.repositorySettings.security.immutableReleases
        $immutableReleases.status | Should -BeIn @('enabled', 'disabled', 'unavailable')
        $immutableReleases.appliesTo | Should -Not -BeNullOrEmpty
        if ($immutableReleases.status -eq 'enabled') {
            $immutableReleases.enabled | Should -BeTrue
            $immutableReleases.recommendation | Should -Be 'keep-immutable-releases-enabled'
        }
        $report.repositorySettings.security.dependabotSecurityPosture.status | Should -Be 'disabled'
        $report.repositorySettings.security.dependabotSecurityPosture.recommendation |
            Should -Be 'keep-dependabot-disabled-with-local-advisory-review'
        $report.repositorySettings.security.dependabotSecurityPosture.evidence |
            Should -Match 'review:dependencies'
        $report.repositorySettings.security.dependabotSecurityPosture.localConfigPresent | Should -BeFalse
        $report.repositorySettings.security.dependabotSecurityPosture.localConfigEcosystems | Should -BeNullOrEmpty
        $codeScanning.scorecardAlertPosture.available | Should -BeTrue
        $codeScanning.scorecardAlertPosture.openAlertCount | Should -Be @($codeScanning.scorecardAlertPosture.rows).Count
        $codeScanning.scorecardAlertPosture.openAlertCount | Should -BeGreaterOrEqual 4
        $codeScanning.scorecardAlertPosture.needsHostedRefreshCount | Should -Be 0
        $codeScanning.scorecardAlertPosture.localActionableCount | Should -Be 0
        $codeScanning.scorecardAlertPosture.recommendation | Should -Be 'track-external-scorecard-governance-items'
        $report.repositorySettings.security.scorecardScore.provider | Should -Be 'scorecard-cli'
        $report.repositorySettings.security.scorecardScore.command | Should -Be 'scorecard --repo=github.com/SysAdminDoc/SysAdminDoc --format=json'
        if ($report.repositorySettings.security.scorecardScore.available) {
            $report.repositorySettings.security.scorecardScore.score | Should -BeGreaterOrEqual 0
            $report.repositorySettings.security.scorecardScore.score | Should -BeLessOrEqual 10
            $report.repositorySettings.security.scorecardScore.maxScore | Should -Be 10
            $report.repositorySettings.security.scorecardScore.analyzedRepo | Should -Be 'github.com/SysAdminDoc/SysAdminDoc'
        } else {
            $report.repositorySettings.security.scorecardScore.unavailableReason | Should -Not -BeNullOrEmpty
        }
        ($codeScanning.scorecardAlertPosture.rows | Where-Object { $_.ruleId -eq 'SecurityPolicyID' }) | Should -BeNullOrEmpty
        ($codeScanning.scorecardAlertPosture.rows | Where-Object { $_.ruleId -eq 'CodeReviewID' }).classification | Should -Be 'external-gated-reviewer-model'
        if ($report.repositorySettings.reviewPolicyPosture.available) {
            $report.repositorySettings.reviewPolicyPosture.status | Should -Be 'warning-only-single-maintainer'
            $report.repositorySettings.reviewPolicyPosture.recommendation | Should -Be 'keep-warning-only-until-reviewer-model'
            # Local-only posture: there are no hosted workflows, so hosted required-check
            # enforcement cannot be proven and the evidence must not claim otherwise.
            $report.repositorySettings.reviewPolicyPosture.requiredCheckEnforcementProven | Should -BeFalse
            $report.repositorySettings.reviewPolicyPosture.evidence | Should -Not -Match 'PR #\d+'
            $report.repositorySettings.reviewPolicyPosture.scorecardCodeReviewClassification | Should -Be 'external-gated-reviewer-model'
        } else {
            $report.repositorySettings.reviewPolicyPosture.status | Should -Be 'unavailable'
            $report.repositorySettings.reviewPolicyPosture.branchProtectionUnavailableReason | Should -Not -BeNullOrEmpty
            $report.repositorySettings.reviewPolicyPosture.recommendation | Should -Be 'verify-branch-protection-review-policy'
        }
    }
}

Describe 'Profile release/tag consistency' {
    It 'warns when the latest profile release and tag are behind the planning version' {
        $doc = [ordered]@{ expectedVersion = 'v4.9.57' }
        $repo = New-TestRepoMeta -Name 'SysAdminDoc' -WithRelease -ReleaseTag 'v4.9.20'
        $tagRef = [ordered]@{
            checked = $true
            exists = $false
            tagName = 'v4.9.57'
            url = $null
            sha = $null
            unavailableReason = $null
        }

        $result = Test-ProfileReleaseConsistency -Repos @($repo) -DocVersionConsistency $doc -TagRef $tagRef

        $result.passed | Should -BeFalse
        $result.versionRelation | Should -Be 'behind'
        $result.latestReleaseTag | Should -Be 'v4.9.20'
        $result.expectedTagExists | Should -BeFalse
        $result.warningCount | Should -Be 2
        $result.releasePolicy.status | Should -Be 'documented-internal-version-gap'
        $result.releasePolicy.warningDisposition | Should -Be 'informational'
        $result.releasePolicy.releaseCreationRecommended | Should -BeFalse
        $result.releasePolicy.tagCreationRecommended | Should -BeFalse
        $result.releasePolicy.decisionDocumentPath | Should -Be 'decision:profile-release-tag-policy'
        ($result.warnings | ForEach-Object { $_.kind }) | Should -Contain 'latest-release-behind'
        ($result.warnings | ForEach-Object { $_.kind }) | Should -Contain 'expected-version-tag-missing'
    }

    It 'passes when the latest profile release and tag match the planning version' {
        $doc = [ordered]@{ expectedVersion = 'v4.9.57' }
        $repo = New-TestRepoMeta -Name 'SysAdminDoc' -WithRelease -ReleaseTag 'v4.9.57'
        $tagRef = [ordered]@{
            checked = $true
            exists = $true
            tagName = 'v4.9.57'
            url = 'https://github.com/SysAdminDoc/SysAdminDoc/releases/tag/v4.9.57'
            sha = 'abc123'
            unavailableReason = $null
        }

        $result = Test-ProfileReleaseConsistency -Repos @($repo) -DocVersionConsistency $doc -TagRef $tagRef

        $result.passed | Should -BeTrue
        $result.versionRelation | Should -Be 'matching'
        $result.latestReleaseMatchesExpected | Should -BeTrue
        $result.latestReleaseAtLeastExpected | Should -BeTrue
        $result.expectedTagExists | Should -BeTrue
        $result.warningCount | Should -Be 0
        $result.releasePolicy.status | Should -Be 'documented-internal-version-gap'
        $result.releasePolicy.publicReleaseCadence | Should -Be 'manual-public-milestone-only'
    }
}

Describe 'Seed catalog guard' -Tag 'Integration' {
    It 'requires ForceSeedCatalog for the lossy legacy parser' {
        $blocked = Test-SeedCatalogGuard -SeedRequested $true -ForceRequested $false
        $blocked.allowed | Should -BeFalse
        $blocked.message | Should -Match 'ForceSeedCatalog'
        $blocked.message | Should -Match 'lossy'

        $allowed = Test-SeedCatalogGuard -SeedRequested $true -ForceRequested $true
        $allowed.allowed | Should -BeTrue
        $allowed.message | Should -Match 'one-shot bootstrap'
    }

    It 'exits clearly when SeedCatalog is invoked without ForceSeedCatalog' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $output = & pwsh -NoProfile -File $scriptPath -SeedCatalog -Offline -CatalogPath (Join-Path $TestDrive 'blocked-catalog.json') -CachePath (Join-Path $TestDrive 'seed-blocked-cache') *>&1

        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'ForceSeedCatalog'
        ($output | Out-String) | Should -Match 'lossy'
    }

    It 'allows forced offline one-shot seed mode with a lossy warning' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $readmePath = Join-Path $TestDrive 'README.md'
        $catalogPath = Join-Path $TestDrive 'catalog.json'
        Set-Content -LiteralPath $readmePath -Value @(
            '# Temporary profile'
            ''
            '### Start Here'
        ) -Encoding utf8

        $output = & pwsh -NoProfile -File $scriptPath -SeedCatalog -ForceSeedCatalog -Offline -ReadmePath $readmePath -CatalogPath $catalogPath -CachePath (Join-Path $TestDrive 'seed-cache') *>&1

        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'LOSSY LEGACY SEED MODE'
        Test-Path -LiteralPath $catalogPath | Should -BeTrue
    }
}

Describe 'Profile sync entrypoint' {
    It 'exits explicitly after a successful check run' {
        $script:SyncProfileScript | Should -Match '(?s)Write-Host "Profile sync check passed[.] Report: \$ReportPath"\s+# Keep hosted shells from surfacing handled native-command failures[.]\s+exit 0'
    }

    It 'takes the repository lock before inspecting shared transaction journals' {
        $mainBlock = $script:SyncProfileScript.Substring($script:SyncProfileScript.IndexOf('# Test seam:'))
        $lockIndex = $mainBlock.IndexOf('$profileSyncRunLock = Enter-ProfileSyncRunLock')
        $repairIndex = $mainBlock.IndexOf('$recoveredPublicationCount = Repair-ArtifactPublicationTransactions')

        $lockIndex | Should -BeGreaterThan -1
        $repairIndex | Should -BeGreaterThan $lockIndex
        $mainBlock | Should -Match '(?s)finally\s*\{\s*if \(\$null -ne \$profileSyncRunLock\)\s*\{\s*\$profileSyncRunLock[.]Dispose\(\)'
    }

    It 'validates the proposed write set before staging one report-last transaction' {
        $mainBlock = $script:SyncProfileScript.Substring($script:SyncProfileScript.IndexOf('# Test seam:'))
        $validationIndex = $mainBlock.IndexOf('$result = Test-ProfileState @profileStateParameters')
        $publicationIndex = $mainBlock.IndexOf('$publicationTransaction = New-ArtifactPublicationTransaction -Artifacts $publicationArtifacts.ToArray()')

        $validationIndex | Should -BeGreaterThan -1
        $publicationIndex | Should -BeGreaterThan $validationIndex
        $mainBlock | Should -Match 'profileStateParameters\[''CurrentReadme''\] = \$expected'
        $mainBlock | Should -Match 'profileStateParameters\[''CurrentProjects''\] = \$expectedProjects'
        $mainBlock | Should -Match '\$assetsAfterWrite = Get-ProfileAssetFileContents'
        $mainBlock | Should -Match 'profileStateParameters\[''CurrentAssets''\] = \$assetsAfterWrite'
        $mainBlock | Should -Match 'isReport = \$true'
        $mainBlock | Should -Match 'Generated targets were not changed'
    }
}

Describe 'Generation entrypoint modes' -Tag 'Integration' {
    BeforeAll {
        # A complete, fresh generation snapshot in its own cache, so an offline -Write can run.
        function script:New-OfflineSnapshotCache {
            param([string]$Path)
            $saved = @{
                CachePath = $script:CachePath; CacheEnabled = $script:CacheEnabled; MetadataSnapshotAt = $script:MetadataSnapshotAt
                Provider = $script:RepositoryMetadataProvider; RequestedLimit = $script:RepositoryEnumerationRequestedLimit; Truncated = $script:RepositoryEnumerationTruncated
            }
            try {
                $script:CachePath = $Path
                $script:CacheEnabled = $true
                $script:MetadataSnapshotAt = (Get-Date).ToUniversalTime().ToString('o')
                $script:RepositoryMetadataProvider = 'graphql'
                $script:RepositoryEnumerationRequestedLimit = 25
                $script:RepositoryEnumerationTruncated = $false
                Reset-ValidationCacheState
                Write-CompleteGenerationSnapshot -Repos @((New-TestRepoMeta -Name 'WinTool' -WithRelease -AssetNames @('WinTool.zip'))) -ReleaseMetadataComplete:$true | Should -BeTrue
            } finally {
                $script:CachePath = $saved.CachePath
                $script:CacheEnabled = $saved.CacheEnabled
                $script:MetadataSnapshotAt = $saved.MetadataSnapshotAt
                $script:RepositoryMetadataProvider = $saved.Provider
                $script:RepositoryEnumerationRequestedLimit = $saved.RequestedLimit
                $script:RepositoryEnumerationTruncated = $saved.Truncated
                Reset-ValidationCacheState
            }
        }
    }

    It 'refuses to write from a catalog that fails its shape check' {
        # -Write alone never reaches Test-ProfileState, so it runs the catalog check itself.
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $cachePath = Join-Path $TestDrive 'shape-cache'
        script:New-OfflineSnapshotCache -Path $cachePath
        $sourceCatalog = Join-Path $TestDrive 'shape-catalog.json'
        $fixture = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/catalog.json'))
        [System.IO.File]::WriteAllText($sourceCatalog, $fixture.Replace('"liveUrl": "https://sysadmindoc.github.io/WebTool/"', '"liveUrl": "https://sysadmindoc.github.io/WebTool/\n| [**Injected**](https://evil.example/) | row |"'))
        $readmePath = Join-Path $TestDrive 'shape-README.md'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Destination $readmePath -Force
        $before = (Get-FileHash -LiteralPath $readmePath -Algorithm SHA256).Hash

        $output = & pwsh -NoProfile -File $scriptPath -Write -Offline -CatalogPath $sourceCatalog -ReadmePath $readmePath `
            -ProjectsPath (Join-Path $TestDrive 'shape-projects.json') -AssetsPath (Join-Path $TestDrive 'shape-assets') -CachePath $cachePath *>&1

        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'Catalog issue: WebTool liveUrl'
        ($output | Out-String) | Should -Match 'nothing was written'
        (Get-FileHash -LiteralPath $readmePath -Algorithm SHA256).Hash | Should -Be $before
        Test-Path -LiteralPath (Join-Path $TestDrive 'shape-projects.json') | Should -BeFalse
    }

    It 'refuses a forkOf that would split its README row' {
        # The fork link's owner/repo shape used to live only in the schema, which -Write skips.
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $cachePath = Join-Path $TestDrive 'fork-cache'
        script:New-OfflineSnapshotCache -Path $cachePath
        $sourceCatalog = Join-Path $TestDrive 'fork-catalog.json'
        $fixture = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/catalog.json'))
        [System.IO.File]::WriteAllText($sourceCatalog, $fixture.Replace('"descriptionOverride": "A test web app",', '"descriptionOverride": "A test web app", "forkOf": "upstream-owner/WebTool|x",'))
        $readmePath = Join-Path $TestDrive 'fork-README.md'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Destination $readmePath -Force
        $before = (Get-FileHash -LiteralPath $readmePath -Algorithm SHA256).Hash

        $output = & pwsh -NoProfile -File $scriptPath -Write -Offline -CatalogPath $sourceCatalog -ReadmePath $readmePath `
            -ProjectsPath (Join-Path $TestDrive 'fork-projects.json') -AssetsPath (Join-Path $TestDrive 'fork-assets') -CachePath $cachePath *>&1

        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'Catalog issue: WebTool forkOf: forkOf must be owner/repo'
        (Get-FileHash -LiteralPath $readmePath -Algorithm SHA256).Hash | Should -Be $before
        Test-Path -LiteralPath (Join-Path $TestDrive 'fork-projects.json') | Should -BeFalse
    }

    It 'refuses the catalog before fetching anything from GitHub' {
        # A stand-in gh first on PATH records every call; the refusal has to come before one.
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $binPath = Join-Path $TestDrive 'early-gate-bin'
        $null = New-Item -ItemType Directory -Path $binPath
        $marker = Join-Path $TestDrive 'early-gate-gh-called.txt'
        [System.IO.File]::WriteAllText((Join-Path $binPath 'gh.cmd'), "@echo called>>`"$marker`"`r`n@exit /b 1`r`n")
        $sourceCatalog = Join-Path $TestDrive 'early-gate-catalog.json'
        $fixture = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/catalog.json'))
        [System.IO.File]::WriteAllText($sourceCatalog, $fixture.Replace('"descriptionOverride": "A test web app",', '"descriptionOverride": "A test web app", "forkOf": "upstream-owner/WebTool|x",'))
        $savedPath = $env:PATH
        try {
            $env:PATH = $binPath + [System.IO.Path]::PathSeparator + $savedPath
            $output = & pwsh -NoProfile -File $scriptPath -Write -CatalogPath $sourceCatalog -ReadmePath (Join-Path $TestDrive 'early-gate-README.md') `
                -ProjectsPath (Join-Path $TestDrive 'early-gate-projects.json') -AssetsPath (Join-Path $TestDrive 'early-gate-assets') -CachePath (Join-Path $TestDrive 'early-gate-cache') *>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $env:PATH = $savedPath
        }

        $exitCode | Should -Be 1 -Because ($output | Out-String)
        ($output | Out-String) | Should -Match 'Catalog issue: WebTool forkOf'
        Test-Path -LiteralPath $marker | Should -BeFalse -Because 'the catalog is checked before any gh call'
        Test-Path -LiteralPath (Join-Path $TestDrive 'early-gate-README.md') | Should -BeFalse
    }

    It 'links the owner''s own address when -PortfolioUrl could leave its attribute' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $cachePath = Join-Path $TestDrive 'unsafe-portfolio-cache'
        script:New-OfflineSnapshotCache -Path $cachePath
        $readmePath = Join-Path $TestDrive 'unsafe-portfolio.md'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Destination $readmePath -Force

        $output = & pwsh -NoProfile -File $scriptPath -Write -Offline -PortfolioUrl 'https://portfolio.example.test/"><img src="https://tracker.example/p.png' `
            -CatalogPath (Join-Path $PSScriptRoot 'fixtures/catalog.json') -ReadmePath $readmePath `
            -ProjectsPath (Join-Path $TestDrive 'unsafe-portfolio.json') -AssetsPath (Join-Path $TestDrive 'unsafe-portfolio-assets') -CachePath $cachePath *>&1

        $LASTEXITCODE | Should -Be 0 -Because ($output | Out-String)
        $written = [System.IO.File]::ReadAllText($readmePath)
        $written | Should -Not -Match 'tracker\.example'
        $written | Should -Match ([regex]::Escape('<a href="https://sysadmindoc.github.io/"><b>See everything</b></a>'))
    }

    It 'probes the portfolio address the footer links' {
        # The run used to hand the probe its raw $PortfolioUrl, empty without catalog or switch.
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $reportPath = Join-Path $TestDrive 'probe-report.json'

        $null = & pwsh -NoProfile -File $scriptPath -Check -Offline -SkipLinkValidation -ProbePortfolio -Owner 'OtherOwner' `
            -CatalogPath (Join-Path $PSScriptRoot 'fixtures/catalog.json') -ReportPath $reportPath -CachePath (Join-Path $TestDrive 'probe-cache') *>&1

        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $report.portfolioCrossSurfaceProbe.portfolioUrl | Should -Be 'https://otherowner.github.io/'
    }

    It 'rejects a cold-cache offline write before changing any canonical target' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $readmePath = Join-Path $TestDrive 'README.md'
        $projectsPath = Join-Path $TestDrive 'projects.json'
        $reportPath = Join-Path $TestDrive 'profile-sync-report.json'
        $assetsPath = Join-Path $TestDrive 'assets'
        $cachePath = Join-Path $TestDrive 'cold-cache'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Destination $readmePath -Force
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'projects.json') -Destination $projectsPath -Force
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Destination $reportPath -Force
        $targetPaths = @($readmePath, $projectsPath, $reportPath)
        $beforeHashes = @{}
        foreach ($path in $targetPaths) {
            $beforeHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }

        $output = & pwsh -NoProfile -File $scriptPath -Write -Offline `
            -CatalogPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') `
            -ReadmePath $readmePath -ProjectsPath $projectsPath -ReportPath $reportPath `
            -AssetsPath $assetsPath -CachePath $cachePath *>&1

        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'Offline writes require a fresh, complete generation snapshot'
        $targetPaths | Should -HaveCount 3
        Test-Path -LiteralPath $assetsPath | Should -BeFalse
        foreach ($path in $targetPaths) {
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $beforeHashes[$path]
        }
    }

    It 'writes canonical artifacts offline from a complete owner-bound snapshot' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $readmePath = Join-Path $TestDrive 'cached-README.md'
        $projectsPath = Join-Path $TestDrive 'cached-projects.json'
        $assetsPath = Join-Path $TestDrive 'cached-assets'
        $cachePath = Join-Path $TestDrive 'complete-cache'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Destination $readmePath -Force
        $oldCachePath = $script:CachePath
        $oldCacheEnabled = $script:CacheEnabled
        $oldMetadataSnapshotAt = $script:MetadataSnapshotAt
        $oldProvider = $script:RepositoryMetadataProvider
        $oldRequestedLimit = $script:RepositoryEnumerationRequestedLimit
        $oldTruncated = $script:RepositoryEnumerationTruncated

        try {
            $script:CachePath = $cachePath
            $script:CacheEnabled = $true
            $script:MetadataSnapshotAt = (Get-Date).ToUniversalTime().ToString('o')
            $script:RepositoryMetadataProvider = 'graphql'
            $script:RepositoryEnumerationRequestedLimit = 25
            $script:RepositoryEnumerationTruncated = $false
            Reset-ValidationCacheState
            Write-CompleteGenerationSnapshot `
                -Repos @((New-TestRepoMeta -Name 'WinTool' -WithRelease -AssetNames @('WinTool.zip'))) `
                -ReleaseMetadataComplete:$true | Should -BeTrue
        } finally {
            $script:CachePath = $oldCachePath
            $script:CacheEnabled = $oldCacheEnabled
            $script:MetadataSnapshotAt = $oldMetadataSnapshotAt
            $script:RepositoryMetadataProvider = $oldProvider
            $script:RepositoryEnumerationRequestedLimit = $oldRequestedLimit
            $script:RepositoryEnumerationTruncated = $oldTruncated
            Reset-ValidationCacheState
        }

        $output = & pwsh -NoProfile -File $scriptPath -Write -Offline `
            -CatalogPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') `
            -ReadmePath $readmePath -ProjectsPath $projectsPath -AssetsPath $assetsPath `
            -CachePath $cachePath *>&1

        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'Wrote .*cached-README[.]md'
        $feed = Get-Content -LiteralPath $projectsPath -Raw | ConvertFrom-Json
        $feed.publicRepoCount | Should -Be 1
        $feed.provenance.metadataProvider | Should -Be 'graphql'
        $feed.provenance.repoEnumeration.returnedCount | Should -Be 1
        Test-Path -LiteralPath $assetsPath | Should -BeFalse -Because 'the text-only README has no generated assets to write'
    }

    It 'links the catalog''s portfolioUrl unless -PortfolioUrl says otherwise' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $cachePath = Join-Path $TestDrive 'portfolio-cache'
        $catalogPath = Join-Path $TestDrive 'portfolio-catalog.json'
        $fixture = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/catalog.json'))
        [System.IO.File]::WriteAllText($catalogPath, $fixture.Replace('"entries":', '"portfolioUrl": "https://portfolio.example.test/", "entries":'))
        $saved = @{
            CachePath = $script:CachePath; CacheEnabled = $script:CacheEnabled; MetadataSnapshotAt = $script:MetadataSnapshotAt
            Provider = $script:RepositoryMetadataProvider; RequestedLimit = $script:RepositoryEnumerationRequestedLimit; Truncated = $script:RepositoryEnumerationTruncated
        }
        try {
            $script:CachePath = $cachePath
            $script:CacheEnabled = $true
            $script:MetadataSnapshotAt = (Get-Date).ToUniversalTime().ToString('o')
            $script:RepositoryMetadataProvider = 'graphql'
            $script:RepositoryEnumerationRequestedLimit = 25
            $script:RepositoryEnumerationTruncated = $false
            Reset-ValidationCacheState
            Write-CompleteGenerationSnapshot -Repos @((New-TestRepoMeta -Name 'WinTool' -WithRelease -AssetNames @('WinTool.zip'))) -ReleaseMetadataComplete:$true | Should -BeTrue
        } finally {
            $script:CachePath = $saved.CachePath
            $script:CacheEnabled = $saved.CacheEnabled
            $script:MetadataSnapshotAt = $saved.MetadataSnapshotAt
            $script:RepositoryMetadataProvider = $saved.Provider
            $script:RepositoryEnumerationRequestedLimit = $saved.RequestedLimit
            $script:RepositoryEnumerationTruncated = $saved.Truncated
            Reset-ValidationCacheState
        }
        $readmes = @{}
        foreach ($case in @('catalog', 'empty')) {
            $readmes[$case] = Join-Path $TestDrive "portfolio-$case.md"
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Destination $readmes[$case] -Force
            # Written out in full for each case: the checkout guard can't read a splatted run.
            if ($case -eq 'empty') {
                $output = & pwsh -NoProfile -File $scriptPath -Write -Offline -PortfolioUrl '' -CatalogPath $catalogPath -ReadmePath $readmes[$case] `
                    -ProjectsPath (Join-Path $TestDrive "portfolio-feed-$case.json") -AssetsPath (Join-Path $TestDrive "portfolio-assets-$case") -CachePath $cachePath *>&1
            } else {
                $output = & pwsh -NoProfile -File $scriptPath -Write -Offline -CatalogPath $catalogPath -ReadmePath $readmes[$case] `
                    -ProjectsPath (Join-Path $TestDrive "portfolio-feed-$case.json") -AssetsPath (Join-Path $TestDrive "portfolio-assets-$case") -CachePath $cachePath *>&1
            }
            $LASTEXITCODE | Should -Be 0 -Because ($output | Out-String)
        }

        [System.IO.File]::ReadAllText($readmes['catalog']) | Should -Match ([regex]::Escape('<a href="https://portfolio.example.test/"><b>See everything</b></a>'))
        [System.IO.File]::ReadAllText($readmes['empty']) | Should -Match ([regex]::Escape('<a href="https://sysadmindoc.github.io/"><b>See everything</b></a>'))
    }

    It 'rejects unsafe Owner values before generation or network work' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'

        # -ReportPath too: without it the run would write the tracked report if the check ever moved.
        $output = & pwsh -NoProfile -File $scriptPath -Owner '../bad' -Check -Offline -CachePath (Join-Path $TestDrive 'bad-owner-cache') `
            -ReportPath (Join-Path $TestDrive 'bad-owner-report.json') *>&1

        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'Owner must match'
    }

    It 'writes a report under -Check -Offline without a Count-on-null crash' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $reportPath = Join-Path $TestDrive 'offline-report.json'

        $output = & pwsh -NoProfile -File $scriptPath -Check -Offline -SkipLinkValidation `
            -CatalogPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') `
            -ReportPath $reportPath -CachePath (Join-Path $TestDrive 'cold-check-cache') *>&1

        # Offline check legitimately reports drift (exit 1); the point is that it does not throw.
        ($output | Out-String) | Should -Not -Match "property 'Count' cannot be found"
        Test-Path -LiteralPath $reportPath | Should -BeTrue
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $report.validationPerformance.metadataFetch.repoCount | Should -Be 0
        $report.validationPerformance.metadataFetch.graphQlPageSize | Should -Be 500
        $report.validationPerformance.metadataFetch.requestCount | Should -Be 0
        $report.validationPerformance.metadataFetch.retryCount | Should -Be 0
        $report.validationPerformance.metadataFetch.resourceLimitFallback | Should -BeFalse
        $report.provenance.metadataProvider | Should -Be 'offline-empty'
        $report.validationPerformance.metadataFetch.fallbackReason | Should -Be 'complete generation snapshot unavailable'
        $report.validationPerformance.metadataFetch.fidelityDegraded | Should -BeTrue
    }

    It 'reaches the topic-apply block and exits cleanly on an empty allowlist' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $allowlistPath = Join-Path $TestDrive 'empty-allowlist.json'
        '[]' | Set-Content -LiteralPath $allowlistPath -Encoding utf8

        $output = & pwsh -NoProfile -File $scriptPath -ApplyTopics -Offline `
            -TopicAllowlistPath $allowlistPath -CachePath (Join-Path $TestDrive 'topics-cache') *>&1

        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'allowlist is empty'
    }
}

Describe 'Source files carry no invisible characters' {
    It 'spells line separators and bidi controls in scripts as escapes' {
        # A literal U+2028 or U+202E looks like nothing in an editor, which can drop or
        # reorder it; a regex that needs one writes it as a \u escape instead. The pattern is
        # built from the code points so this file holds none of the characters itself.
        $codes = @(0x85, 0x2028, 0x2029) + @(0x202A..0x202E) + @(0x2066..0x2069)
        $pattern = '[' + (($codes | ForEach-Object { [string][char]92 + 'u' + $_.ToString('X4') }) -join '') + ']'
        # Every PowerShell file: scripts and tests at any depth, and the root's own, settings
        # data (.psd1) and modules (.psm1) included.
        $powershellFile = { $_.Extension -in @('.ps1', '.psd1', '.psm1') }
        $files = @(
            foreach ($directory in @('scripts', 'tests')) {
                Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot $directory) -File -Recurse | Where-Object $powershellFile
            }
            Get-ChildItem -LiteralPath $script:RepoRoot -File | Where-Object $powershellFile
        )
        @($files | ForEach-Object Name) | Should -Contain 'PSScriptAnalyzerSettings.psd1'

        $offenders = foreach ($file in $files) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($match in [regex]::Matches($text, $pattern)) {
                '{0}:{1} U+{2:X4}' -f $file.Name, ($text.Substring(0, $match.Index) -split "`n").Count, [int][char]$match.Value
            }
        }

        $files.Count | Should -BeGreaterThan 15 -Because 'the scan has to reach the generator, its library and the tests'
        @($offenders) | Should -BeNullOrEmpty
    }
}

Describe 'Child script runs stay out of the checkout' {
    BeforeAll {
        $tokens = $null
        $parseErrors = $null
        $script:TestFileAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'sync-profile.Tests.ps1'), [ref]$tokens, [ref]$parseErrors)

        # Every child pwsh that runs -File with a path the file-matching block accepts, however
        # pwsh is named: pwsh, pwsh.exe, a full path to it, or anything computed that could
        # hold it ((Get-Command pwsh).Source, & $exe), since the -File path says what runs.
        function script:Find-ChildRun {
            param([scriptblock]$FileMatches)
            @($script:TestFileAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    ($node.CommandElements[0] -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $node.CommandElements[0].Value -match '(?:^|[\\/])pwsh(?:\.exe)?$') -and
                    (& $FileMatches $node)
            }, $true))
        }

        # pwsh takes -File as -f, -fi or -fil too, with one or two dashes or a slash, quoted or not.
        $script:FileSwitchPattern = '(?:^|\s)[''"]?(?:--?|/)f(?:i(?:le?)?)?[''"]?\s+'

        # A variable's name without local: or private:, which name the same variable.
        function script:Get-VariableName {
            param($Variable)
            $Variable.VariablePath.UserPath -replace '^(?i:local|private):', ''
        }

        # True when a path value comes from the test drive: $TestDrive itself, Join-Path with
        # $TestDrive as its base, a double-quoted string that starts with one of those, or a
        # variable or indexed value whose last write before the run is one of those. The text
        # alone isn't enough: '$TestDrive/cache' in single quotes is a relative path in the
        # checkout.
        function script:Test-TestDriveValue {
            param($Value, [int]$Before, [int]$Depth = 0)
            if ($null -eq $Value -or $Depth -gt 6) { return $false }
            # A .. segment can climb out of the test drive ("$TestDrive\..\..\repos").
            if ($Value.Extent.Text -match '(?:^|[\\/''"\s])\.\.(?:[\\/''"\s]|$)') { return $false }
            switch ($Value.GetType().Name) {
                'VariableExpressionAst' {
                    # Ordinal: -eq compares by culture and skips an invisible character, and
                    # $TestDrive:cacheH is an item on the TestDrive: drive, not the variable.
                    # $TestDrive itself counts only when the test hasn't written to it.
                    if ([string]::Equals($Value.VariablePath.UserPath, 'TestDrive', [StringComparison]::OrdinalIgnoreCase)) { return ($null -eq (script:Get-LastWrite -Target $Value -Before $Before)) }
                    return (script:Test-AssignedFromTestDrive -Target $Value -Before $Before -Depth $Depth)
                }
                'IndexExpressionAst' { return (script:Test-AssignedFromTestDrive -Target $Value -Before $Before -Depth $Depth) }
                'ParenExpressionAst' { return (script:Test-TestDriveValue -Value $Value.Pipeline -Before $Before -Depth ($Depth + 1)) }
                'SubExpressionAst' {
                    $statements = @($Value.SubExpression.Statements)
                    return ($statements.Count -eq 1 -and (script:Test-TestDriveValue -Value $statements[0] -Before $Before -Depth ($Depth + 1)))
                }
                'PipelineAst' {
                    if ($Value.PipelineElements.Count -ne 1) { return $false }
                    return (script:Test-TestDriveValue -Value $Value.PipelineElements[0] -Before $Before -Depth ($Depth + 1))
                }
                'CommandExpressionAst' { return (script:Test-TestDriveValue -Value $Value.Expression -Before $Before -Depth ($Depth + 1)) }
                'CommandAst' {
                    if ($Value.GetCommandName() -ne 'Join-Path') { return $false }
                    # The base: -Path's value, or the first positional argument.
                    $elements = @($Value.CommandElements)
                    for ($index = 1; $index -lt $elements.Count; $index++) {
                        $element = $elements[$index]
                        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                            if ($element.ParameterName -eq 'Path') {
                                $base = if ($null -ne $element.Argument) { $element.Argument } elseif ($index + 1 -lt $elements.Count) { $elements[$index + 1] } else { $null }
                                return (script:Test-TestDriveValue -Value $base -Before $Before -Depth ($Depth + 1))
                            }
                            if ($null -eq $element.Argument) { $index++ }
                            continue
                        }
                        return (script:Test-TestDriveValue -Value $element -Before $Before -Depth ($Depth + 1))
                    }
                    return $false
                }
                'ExpandableStringExpressionAst' {
                    # What opens the string decides where the path lies ("$TestDrive\c",
                    # "${TestDrive}\c", "$($TestDrive)\c", "$c\x"); a here-string is left to the
                    # snapshot.
                    $first = @($Value.NestedExpressions)[0]
                    if ($null -eq $first -or $first.Extent.StartOffset -ne $Value.Extent.StartOffset + 1) { return $false }
                    return (script:Test-TestDriveValue -Value $first -Before $Before -Depth ($Depth + 1))
                }
                default { return $false }
            }
        }

        # The last write to a variable or indexed value before the run, in the script block the
        # run sits in, as { Offset; Value }, where Value is the syntax tree written or $null when
        # the guard can't follow the write; nothing when there's no write at all. A plain
        # assignment, typed or not, is followed. These aren't: a write in a nested script block
        # (ForEach-Object runs its block in the caller's scope, & { } in a child scope) or in a
        # branch, loop, try or trap the run isn't in (it may not happen), a multiple assignment,
        # a foreach variable, Set-Variable and its kin (by name, or given a name that isn't
        # written out), an -OutVariable style parameter, and for an indexed value a write to a
        # computed key, a property or the whole table. Keys compare by value, so $h['c'] is
        # $h["c"].
        function script:Get-LastWrite {
            param($Target, [int]$Before)
            $scope = $Target.Parent
            while ($null -ne $scope -and $scope -isnot [System.Management.Automation.Language.ScriptBlockAst]) { $scope = $scope.Parent }
            $variable = if ($Target -is [System.Management.Automation.Language.IndexExpressionAst]) { $Target.Target } else { $Target }
            if ($null -eq $scope -or $variable -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return [pscustomobject]@{ Offset = 0; Value = $null } }
            $name = script:Get-VariableName $variable
            $isName = { param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] -and [string]::Equals((script:Get-VariableName $node), $name, [StringComparison]::OrdinalIgnoreCase) }
            $keyOf = { param($index) if ($index -is [System.Management.Automation.Language.ConstantExpressionAst]) { [string]$index.Value } else { $null } }
            $targetKey = if ($Target -is [System.Management.Automation.Language.IndexExpressionAst]) { & $keyOf $Target.Index } else { $null }
            $branches = @('IfStatementAst', 'SwitchStatementAst', 'TryStatementAst', 'TrapStatementAst', 'ForStatementAst', 'ForEachStatementAst', 'WhileStatementAst', 'DoWhileStatementAst', 'DoUntilStatementAst')
            $outVariables = @('outvariable', 'ov', 'errorvariable', 'ev', 'warningvariable', 'wv', 'informationvariable', 'iv', 'pipelinevariable', 'pv')
            $writes = foreach ($node in $scope.FindAll({ param($node) $node.Extent.EndOffset -le $Before -or $node -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
                $traced = $null
                $untraceable = $false
                if ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Extent.EndOffset -le $Before) {
                    $left = $node.Left
                    while ($left -is [System.Management.Automation.Language.AttributedExpressionAst]) { $left = $left.Child }
                    if ($Target -is [System.Management.Automation.Language.IndexExpressionAst]) {
                        if ($left -is [System.Management.Automation.Language.IndexExpressionAst] -and (& $isName $left.Target)) {
                            # Constant keys compare by value; two computed ones by how they're
                            # written ($readmes[$case] in a loop); a mix can't be followed.
                            $key = & $keyOf $left.Index
                            if ($null -eq $key -and $null -eq $targetKey) {
                                if ([string]::Equals($left.Index.Extent.Text, $Target.Index.Extent.Text, [StringComparison]::Ordinal)) { $traced = $node.Right } else { $untraceable = $true }
                            } elseif ($null -eq $key -or $null -eq $targetKey) { $untraceable = $true }
                            elseif ([string]::Equals($key, $targetKey, [StringComparison]::Ordinal)) { $traced = $node.Right }
                        } elseif (($left -is [System.Management.Automation.Language.MemberExpressionAst] -and (& $isName $left.Expression)) -or (& $isName $left)) {
                            $untraceable = $true
                        }
                    } elseif (& $isName $left) { $traced = $node.Right }
                    if ($left -is [System.Management.Automation.Language.ArrayLiteralAst] -and @($left.Elements | Where-Object {
                                $element = $_
                                while ($element -is [System.Management.Automation.Language.AttributedExpressionAst]) { $element = $element.Child }
                                & $isName $element
                            }).Count -gt 0) { $untraceable = $true }
                } elseif ($node -is [System.Management.Automation.Language.ForEachStatementAst] -and $node.Extent.StartOffset -lt $Before -and (& $isName $node.Variable)) {
                    $untraceable = $true
                } elseif ($node -is [System.Management.Automation.Language.CommandAst]) {
                    $elements = @($node.CommandElements)
                    if (@('set-variable', 'new-variable', 'clear-variable', 'remove-variable', 'sv', 'nv', 'clv', 'rv', 'set').Contains(([string]$node.GetCommandName()).ToLowerInvariant())) {
                        # The name: -Name's value or the first positional argument. One not
                        # written out as a constant could be this variable.
                        $given = script:Get-ParameterValue -Command $node -Name 'Name'
                        if ($null -eq $given -and $elements.Count -gt 1 -and $elements[1] -isnot [System.Management.Automation.Language.CommandParameterAst]) { $given = $elements[1] }
                        $givenNames = if ($given -is [System.Management.Automation.Language.ArrayLiteralAst]) { @($given.Elements) } else { @($given) }
                        foreach ($givenName in $givenNames) {
                            if ($givenName -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or
                                [string]::Equals(($givenName.Value -replace '^(?i:local|private):', ''), $name, [StringComparison]::OrdinalIgnoreCase)) { $untraceable = $true }
                        }
                    }
                    for ($index = 1; $index -lt $elements.Count; $index++) {
                        $parameter = $elements[$index]
                        if ($parameter -isnot [System.Management.Automation.Language.CommandParameterAst] -or -not $outVariables.Contains($parameter.ParameterName.ToLowerInvariant())) { continue }
                        $given = if ($null -ne $parameter.Argument) { $parameter.Argument } elseif ($index + 1 -lt $elements.Count) { $elements[$index + 1] } else { $null }
                        if ($given -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or
                            [string]::Equals($given.Value.TrimStart('+'), $name, [StringComparison]::OrdinalIgnoreCase)) { $untraceable = $true }
                    }
                }
                if ($null -eq $traced -and -not $untraceable) { continue }
                $owningBlock = $node.Parent
                while ($null -ne $owningBlock -and $owningBlock -isnot [System.Management.Automation.Language.ScriptBlockAst]) {
                    if ($branches.Contains($owningBlock.GetType().Name) -and -not ($Target.Extent.StartOffset -ge $owningBlock.Extent.StartOffset -and $Target.Extent.EndOffset -le $owningBlock.Extent.EndOffset)) { $untraceable = $true }
                    $owningBlock = $owningBlock.Parent
                }
                [pscustomobject]@{ Offset = $node.Extent.StartOffset; Value = if ($untraceable -or -not [object]::ReferenceEquals($owningBlock, $scope)) { $null } else { $traced } }
            }
            @($writes | Sort-Object Offset) | Select-Object -Last 1
        }

        function script:Test-AssignedFromTestDrive {
            param($Target, [int]$Before, [int]$Depth)
            $last = script:Get-LastWrite -Target $Target -Before $Before
            if ($null -eq $last -or $null -eq $last.Value) { return $false }
            return (script:Test-TestDriveValue -Value $last.Value -Before $last.Offset -Depth ($Depth + 1))
        }

        # By the full name only: an abbreviated -Cache reads as missing, which fails the check
        # rather than passing it.
        function script:Get-ParameterValue {
            param($Command, [string]$Name)
            $elements = @($Command.CommandElements)
            for ($index = 0; $index -lt $elements.Count; $index++) {
                $element = $elements[$index]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -eq $Name) {
                    if ($null -ne $element.Argument) { return $element.Argument }
                    if ($index + 1 -lt $elements.Count) { return $elements[$index + 1] }
                }
            }
            return $null
        }

        # The output paths the run passes that don't come from the test drive, and the ones it
        # needs and leaves out (they default into the checkout). An empty list is safe.
        function script:Get-UnsafeOutputPath {
            param($Command, [string[]]$Required, [string[]]$Optional)
            @(foreach ($name in @($Required) + @($Optional)) {
                $value = script:Get-ParameterValue -Command $Command -Name $name
                if ($null -eq $value) {
                    if ($Required -contains $name) { "-$name missing" }
                } elseif (-not (script:Test-TestDriveValue -Value $value -Before $Command.Extent.StartOffset)) {
                    "-$name $($value.Extent.Text)"
                }
            })
        }

        # PowerShell binds an unambiguous prefix (-Wri is -Write), so any prefix counts; one that
        # could name another switch as well only makes the check ask for more paths.
        function script:Test-SwitchPresent {
            param($Command, [string]$Name)
            @($Command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName.Length -gt 0 -and $Name.StartsWith($_.ParameterName, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        }

        # What a sync-profile.ps1 run writes: the cache and lock always, the report under
        # -Check, the README, feed and assets under -Write, the catalog under -SeedCatalog and
        # under -DraftMissingCatalogEntries (with -Write).
        function script:Get-SyncProfileRequiredPath {
            param($Command)
            $required = @('CachePath')
            if (script:Test-SwitchPresent -Command $Command -Name 'Check') { $required += 'ReportPath' }
            if (script:Test-SwitchPresent -Command $Command -Name 'Write') { $required += @('ReadmePath', 'ProjectsPath', 'AssetsPath') }
            if ((script:Test-SwitchPresent -Command $Command -Name 'SeedCatalog') -or (script:Test-SwitchPresent -Command $Command -Name 'DraftMissingCatalogEntries')) { $required += 'CatalogPath' }
            $required
        }

        # The switches of the scripts the suite runs and of pwsh itself: they take no value, so
        # an argument after one is positional.
        $script:ChildSwitchNames = @(@(foreach ($relative in @('scripts/sync-profile.ps1', 'scripts/review-local-dependencies.ps1')) {
                    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot $relative), [ref]$null, [ref]$null)
                    foreach ($parameter in @($scriptAst.ParamBlock.Parameters)) {
                        if ($parameter.StaticType -eq [switch]) { $parameter.Name.VariablePath.UserPath }
                    }
                }) + @('NoProfile', 'NonInteractive', 'NoLogo', 'NoExit', 'Interactive', 'Login', 'Sta', 'Mta'))

        # A pwsh run, or a computed command that may be one, whose arguments the guards can't
        # read: a splat; for pwsh, anything but a constant where no parameter takes it (a
        # variable, an array, a member, an index or an expression in parentheses); and
        # Start-Process pwsh with an argument list, which the guards can't read at all. A
        # computed command's positional arguments are left to the snapshot: & $script:Real
        # $x is how the suite calls a saved function, so they can't all be refused.
        function script:Test-HiddenChildArgument {
            param($Command)
            $elements = @($Command.CommandElements)
            if ([string]::Equals($Command.GetCommandName(), 'Start-Process', [StringComparison]::OrdinalIgnoreCase)) {
                $file = script:Get-ParameterValue -Command $Command -Name 'FilePath'
                if ($null -eq $file -and $elements.Count -gt 1 -and $elements[1] -isnot [System.Management.Automation.Language.CommandParameterAst]) { $file = $elements[1] }
                return ($null -ne $file -and $file.Extent.Text -match 'pwsh' -and $null -ne (script:Get-ParameterValue -Command $Command -Name 'ArgumentList'))
            }
            $isPwsh = $elements[0].Extent.Text -match 'pwsh'
            if (-not $isPwsh -and $elements[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $false }
            if (@($elements | Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Splatted }).Count -gt 0) { return $true }
            if (-not $isPwsh) { return $false }
            for ($index = 1; $index -lt $elements.Count; $index++) {
                $previous = $elements[$index - 1]
                $takenByParameter = $previous -is [System.Management.Automation.Language.CommandParameterAst] -and $null -eq $previous.Argument -and
                    @($script:ChildSwitchNames | Where-Object { $_.StartsWith($previous.ParameterName, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0
                if (-not $takenByParameter -and $elements[$index] -isnot [System.Management.Automation.Language.CommandParameterAst] -and
                    $elements[$index] -isnot [System.Management.Automation.Language.ConstantExpressionAst]) { return $true }
            }
            return $false
        }

        function script:Format-ChildRun {
            param($Command)
            'line {0}: {1}' -f $Command.Extent.StartLineNumber, ($Command.Extent.Text -split "`n")[0].Trim()
        }
    }

    It 'gives every child run of sync-profile.ps1 a cache path under the test drive' {
        # Without -CachePath a child run takes the run lock under the checkout's
        # .cache/profile-sync, leaves run.lock behind, and waits on a real run's lock.
        $childRuns = script:Find-ChildRun -FileMatches {
            param($node)
            $text = $node.Extent.Text
            if ($text -match ($script:FileSwitchPattern + '\$script:SyncProfileScriptPath\b')) { return $true }
            if ($text -notmatch ($script:FileSwitchPattern + '\$scriptPath\b')) { return $false }
            # $scriptPath names sync-profile.ps1 when the enclosing test assigns it so.
            $scope = $node.Parent
            while ($null -ne $scope -and $scope -isnot [System.Management.Automation.Language.ScriptBlockAst]) { $scope = $scope.Parent }
            return ($null -ne $scope -and $scope.Extent.Text -match "\`$scriptPath = Join-Path \`$script:RepoRoot 'scripts/sync-profile\.ps1'")
        }

        $childRuns.Count | Should -BeGreaterThan 5 -Because 'the scan has to find the seed and entrypoint-mode runs'
        @(foreach ($run in $childRuns) {
            $unsafe = @(script:Get-UnsafeOutputPath -Command $run -Required (script:Get-SyncProfileRequiredPath -Command $run) -Optional @('BackstageExportPath'))
            if ($unsafe.Count -gt 0) { '{0} ({1})' -f (script:Format-ChildRun $run), ($unsafe -join ', ') }
        }) | Should -BeNullOrEmpty
    }

    It 'gives every child run of review-local-dependencies.ps1 a registry cache or root under the test drive' {
        # The default registry cache is the checkout's .cache/registry-versions.json, which
        # the validation lane owns; a test run belongs in its own cache or its own root.
        $childRuns = script:Find-ChildRun -FileMatches {
            param($node)
            $node.Extent.Text -match ($script:FileSwitchPattern + '\$script:(?:DependencyReviewScriptPath|ReviewScriptPath)\b')
        }

        $childRuns.Count | Should -BeGreaterThan 6 -Because 'the scan has to find the pwsh and (Get-Command pwsh).Source runs'
        # The cache defaults to <RepoRoot>/.cache, so one of the two has to be given, and
        # every one given has to come from the test drive.
        @(foreach ($run in $childRuns) {
            $given = @('RegistryCachePath', 'RepoRoot' | Where-Object { $null -ne (script:Get-ParameterValue -Command $run -Name $_) })
            $unsafe = @(if ($given.Count -eq 0) { '-RegistryCachePath or -RepoRoot missing' } else { script:Get-UnsafeOutputPath -Command $run -Required $given -Optional @() })
            if ($unsafe.Count -gt 0) { '{0} ({1})' -f (script:Format-ChildRun $run), ($unsafe -join ', ') }
        }) | Should -BeNullOrEmpty
    }

    It 'writes every child pwsh run out in full, so the checks above can read it' {
        # A splatted argument list hides the paths the run writes, and so does an array passed
        # to pwsh as one argument; the guards can't see either. A computed command (& $exe)
        # may be pwsh, so it can't splat either.
        $hidden = @($script:TestFileAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                (script:Test-HiddenChildArgument -Command $node)
        }, $true))

        @($hidden | ForEach-Object { script:Format-ChildRun $_ }) | Should -BeNullOrEmpty
    }

    It 'finds a hidden argument list in <Case>' -ForEach @(
        @{ Case = 'a splat to pwsh'; Code = 'pwsh -File x.ps1 @arguments'; Hidden = $true }
        @{ Case = 'a splat to a computed command'; Code = '& $exe @arguments'; Hidden = $true }
        @{ Case = 'an array passed to pwsh'; Code = '& pwsh $arguments'; Hidden = $true }
        @{ Case = 'an array after the script path'; Code = '& pwsh -NoProfile -File x.ps1 $arguments'; Hidden = $true }
        @{ Case = 'not a value given to a parameter'; Code = '& pwsh -NoProfile -File $scriptPath -CachePath $cache'; Hidden = $false }
        @{ Case = 'not a splat to a named command'; Code = 'Invoke-Thing @arguments'; Hidden = $false }
        # Review G6: none of these was flagged.
        @{ Case = 'a variable after a switch'; Code = '& pwsh -NoProfile -File $scriptPath -Offline $arguments'; Hidden = $true }
        @{ Case = 'an expression in parentheses'; Code = '& pwsh -File x.ps1 ($arguments)'; Hidden = $true }
        @{ Case = 'a member'; Code = '& pwsh -File x.ps1 $h.Args'; Hidden = $true }
        @{ Case = 'an index'; Code = '& pwsh -File x.ps1 $a[0]'; Hidden = $true }
        @{ Case = 'Start-Process pwsh with an argument list'; Code = 'Start-Process pwsh -ArgumentList $arguments'; Hidden = $true }
        @{ Case = 'not Start-Process of another program'; Code = 'Start-Process notepad -ArgumentList $arguments'; Hidden = $false }
    ) {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$null, [ref]$null)
        $command = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))[0]

        script:Test-HiddenChildArgument -Command $command | Should -Be $Hidden
    }

    It 'finds a child run however pwsh and -File are written: <Case>' -ForEach @(
        @{ Case = 'pwsh -f'; Code = '& pwsh -NoProfile -f $script:SyncProfileScriptPath -Check' }
        @{ Case = 'a quoted -File'; Code = '& pwsh -NoProfile ''-File'' $script:SyncProfileScriptPath -Check' }
        @{ Case = 'a double-dash -file'; Code = '& pwsh --file $script:SyncProfileScriptPath -Check' }
        @{ Case = 'pwsh held in a variable'; Code = '& $exe -NoProfile -File $script:SyncProfileScriptPath -Check' }
        @{ Case = 'a full path to pwsh.exe'; Code = '& ''C:\Program Files\PowerShell\7\pwsh.exe'' -File $script:SyncProfileScriptPath -Check' }
    ) {
        $saved = $script:TestFileAst
        try {
            $script:TestFileAst = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$null, [ref]$null)
            $runs = script:Find-ChildRun -FileMatches { param($node) $node.Extent.Text -match ($script:FileSwitchPattern + '\$script:SyncProfileScriptPath\b') }
        } finally {
            $script:TestFileAst = $saved
        }

        @($runs) | Should -HaveCount 1
    }

    It 'asks a sync-profile run for the paths it writes: <Case>' -ForEach @(
        @{ Case = 'a plain run'; Code = 'pwsh -File x.ps1 -Offline'; Expected = 'CachePath' }
        @{ Case = 'a check'; Code = 'pwsh -File x.ps1 -Check'; Expected = 'CachePath,ReportPath' }
        @{ Case = 'a seed'; Code = 'pwsh -File x.ps1 -SeedCatalog'; Expected = 'CachePath,CatalogPath' }
        @{ Case = 'drafting missing entries'; Code = 'pwsh -File x.ps1 -Write -DraftMissingCatalogEntries'; Expected = 'CachePath,ReadmePath,ProjectsPath,AssetsPath,CatalogPath' }
    ) {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$null, [ref]$null)
        $run = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))[0]

        (@(script:Get-SyncProfileRequiredPath -Command $run) -join ',') | Should -Be $Expected
    }

    It 'asks for the paths a switch written <Case> writes' -ForEach @(
        @{ Case = 'in full'; Code = 'pwsh -File x.ps1 -Write'; Name = 'Write'; Present = $true }
        @{ Case = 'as a prefix'; Code = 'pwsh -File x.ps1 -Wri'; Name = 'Write'; Present = $true }
        @{ Case = 'in another case'; Code = 'pwsh -File x.ps1 -draftmissing'; Name = 'DraftMissingCatalogEntries'; Present = $true }
        @{ Case = 'not as another switch'; Code = 'pwsh -File x.ps1 -WriteThrough'; Name = 'Write'; Present = $false }
    ) {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$null, [ref]$null)
        $run = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))[0]

        script:Test-SwitchPresent -Command $run -Name $Name | Should -Be $Present
    }

    It 'traces a path to the test drive only through <Case>' -ForEach @(
        @{ Case = 'the variable itself'; Code = '& pwsh -File x.ps1 -CachePath $TestDrive'; Safe = $true }
        @{ Case = 'Join-Path on it'; Code = '& pwsh -File x.ps1 -CachePath (Join-Path $TestDrive "c")'; Safe = $true }
        @{ Case = 'a double-quoted string that starts with it'; Code = '& pwsh -File x.ps1 -CachePath "$TestDrive\c"'; Safe = $true }
        @{ Case = 'a variable last assigned from it'; Code = '$c = Join-Path $script:RepoRoot "c"; $c = Join-Path $TestDrive "c"; & pwsh -File x.ps1 -CachePath $c'; Safe = $true }
        @{ Case = 'not a single-quoted string, which is a relative path'; Code = '& pwsh -File x.ps1 -CachePath ''$TestDrive/c'''; Safe = $false }
        @{ Case = 'not a variable reassigned into the checkout'; Code = '$c = Join-Path $TestDrive "c"; $c = Join-Path $script:RepoRoot "c"; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not a value that only mentions it'; Code = '& pwsh -File x.ps1 -CachePath ($TestDrive -replace ''.+'', $script:RepoRoot)'; Safe = $false }
        @{ Case = 'not an assignment made after the run'; Code = '& pwsh -File x.ps1 -CachePath $c; $c = Join-Path $TestDrive "c"'; Safe = $false }
        # Review of c2f43c1: each of these was misread.
        @{ Case = 'not an assignment in a nested script block'; Code = '$c = Join-Path $script:RepoRoot "c"; 1 | ForEach-Object { $c = Join-Path $TestDrive "c" }; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not a multiple assignment after it'; Code = '$c = Join-Path $TestDrive "c"; $c, $d = "a", "b"; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not a foreach variable after it'; Code = '$c = Join-Path $TestDrive "c"; foreach ($c in @("a")) { }; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not Set-Variable after it'; Code = '$c = Join-Path $TestDrive "c"; Set-Variable -Name c -Value "a"; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not Clear-Variable after it'; Code = '$c = Join-Path $TestDrive "c"; Clear-Variable c; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not a braced reassignment'; Code = '$c = Join-Path $TestDrive "c"; ${c} = Join-Path $script:RepoRoot "c"; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not a local: reassignment'; Code = '$c = Join-Path $TestDrive "c"; $local:c = Join-Path $script:RepoRoot "c"; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not a typed reassignment'; Code = '$c = Join-Path $TestDrive "c"; [string]$c = Join-Path $script:RepoRoot "c"; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'a typed assignment from it'; Code = '[string]$c = Join-Path $TestDrive "c"; & pwsh -File x.ps1 -CachePath $c'; Safe = $true }
        @{ Case = 'an indexed value assigned from it'; Code = '$h = @{}; $h["c"] = Join-Path $TestDrive "c"; & pwsh -File x.ps1 -CachePath $h["c"]'; Safe = $true }
        @{ Case = 'not an indexed value whose table was replaced'; Code = '$h = @{}; $h["c"] = Join-Path $TestDrive "c"; $h = @{ c = "c" }; & pwsh -File x.ps1 -CachePath $h["c"]'; Safe = $false }
        @{ Case = 'not an item on the TestDrive: drive'; Code = '& pwsh -File x.ps1 -CachePath "$TestDrive:cacheH"'; Safe = $false }
        @{ Case = 'a braced variable in a string'; Code = '& pwsh -File x.ps1 -CachePath "${TestDrive}\c"'; Safe = $true }
        @{ Case = 'a subexpression in a string'; Code = '& pwsh -File x.ps1 -CachePath "$($TestDrive)\c"'; Safe = $true }
        @{ Case = 'a string that opens with a traced variable'; Code = '$c = Join-Path $TestDrive "c"; & pwsh -File x.ps1 -CachePath "$c\x"'; Safe = $true }
        @{ Case = 'not a string where it comes later'; Code = '& pwsh -File x.ps1 -CachePath "cache\$TestDrive"'; Safe = $false }
        @{ Case = 'not a variable whose name hides a character'; Code = '& pwsh -File x.ps1 -CachePath ${Test' + [char]0x200B + 'Drive}'; Safe = $false }
        # Review G6: each of these passed as safe.
        @{ Case = 'a key written with other quotes'; Code = '$h = @{}; $h[''c''] = Join-Path $TestDrive "c"; & pwsh -File x.ps1 -CachePath $h["c"]'; Safe = $true }
        @{ Case = 'not a key rewritten with other quotes'; Code = '$h = @{}; $h["c"] = Join-Path $TestDrive "c"; $h[''c''] = Join-Path $script:RepoRoot "c"; & pwsh -File x.ps1 -CachePath $h["c"]'; Safe = $false }
        @{ Case = 'not a computed key written after it'; Code = '$h = @{}; $h["c"] = Join-Path $TestDrive "c"; $h[$k] = "x"; & pwsh -File x.ps1 -CachePath $h["c"]'; Safe = $false }
        @{ Case = 'not a property written after it'; Code = '$h = @{}; $h["c"] = Join-Path $TestDrive "c"; $h.c = "x"; & pwsh -File x.ps1 -CachePath $h["c"]'; Safe = $false }
        @{ Case = 'not a write in a branch'; Code = 'if ($x) { $c = Join-Path $script:RepoRoot "c" } else { $c = Join-Path $TestDrive "c" }; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'a write in the branch the run is in'; Code = 'if ($x) { $c = Join-Path $TestDrive "c"; & pwsh -File x.ps1 -CachePath $c }'; Safe = $true }
        @{ Case = 'not Set-Variable with a computed name'; Code = '$c = Join-Path $TestDrive "c"; Set-Variable -Name $n -Value "a"; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not Set-Variable with a list of names'; Code = '$c = Join-Path $TestDrive "c"; Set-Variable -Name c, d -Value "a"; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not an -OutVariable'; Code = '$c = Join-Path $TestDrive "c"; Join-Path $script:RepoRoot "c" -OutVariable c; & pwsh -File x.ps1 -CachePath $c'; Safe = $false }
        @{ Case = 'not a reassigned TestDrive'; Code = '$TestDrive = $script:RepoRoot; & pwsh -File x.ps1 -CachePath $TestDrive'; Safe = $false }
        @{ Case = 'not a .. segment in Join-Path'; Code = '& pwsh -File x.ps1 -CachePath (Join-Path $TestDrive "..\..\repos\x")'; Safe = $false }
        @{ Case = 'not a .. segment in a string'; Code = '& pwsh -File x.ps1 -CachePath "$TestDrive\..\.."'; Safe = $false }
    ) {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$null, [ref]$null)
        $run = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.CommandElements[0].Extent.Text -eq 'pwsh' }, $true))[0]

        @(script:Get-UnsafeOutputPath -Command $run -Required @('CachePath') -Optional @()).Count -eq 0 | Should -Be $Safe
    }
}

Describe 'Hosted workflow policy' {
    It 'keeps GitHub Actions workflows absent for local-only validation' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows') | Should -BeFalse
    }
}

Describe 'Rendered profile smoke wiring' {
    BeforeAll {
        $script:RenderSmokeScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/render-profile-smoke.ps1') -Raw
    }

    It 'checks both desktop and 390px mobile viewports without committing screenshots' {
        $script:RenderSmokeScript | Should -Match 'Width = 1280'
        $script:RenderSmokeScript | Should -Match 'Width = 390'
        $script:RenderSmokeScript | Should -Match 'rendered-profile-smoke-'
        $script:RenderSmokeScript | Should -Match 'rendered-profile-smoke-\$\(\$viewport[.]Name\)-\$theme[.]png'
        $script:RenderSmokeScript | Should -Match 'viewport\.Name'
        $script:RenderSmokeScript | Should -Match 'themes = @\("dark", "light"\)'
        $script:RenderSmokeScript | Should -Match 'Emulation[.]setEmulatedMedia'
        $script:RenderSmokeScript | Should -Match 'prefers-color-scheme'
        $script:RenderSmokeScript | Should -Match 'rendered-profile-smoke[.]json'
        $script:RenderSmokeScript | Should -Match 'renderedProfileSmoke'
        $script:RenderSmokeScript | Should -Match 'skipReason'
        $script:RenderSmokeScript | Should -Match 'Write-RenderedSmokeArtifact'
    }

    It 'asserts key rendered sections and overflow/image health' {
        $script:RenderSmokeScript | Should -Match "What.s here"
        $script:RenderSmokeScript | Should -Not -Match 'Catalog Snapshot'
        $script:RenderSmokeScript | Should -Not -Match 'Featured Projects'
        $script:RenderSmokeScript | Should -Match 'First-time setup'
        $script:RenderSmokeScript | Should -Not -Match 'Tool Catalog'
        $script:RenderSmokeScript | Should -Match 'PowerShell System Utilities'
        $script:RenderSmokeScript | Should -Match 'Python Desktop Applications'
        $script:RenderSmokeScript | Should -Match 'Browser Extensions & Userscripts'
        $script:RenderSmokeScript | Should -Not -Match 'Python Applications'
        $script:RenderSmokeScript | Should -Match 'rootOverflow'
        $script:RenderSmokeScript | Should -Match 'failedImages'
        $script:RenderSmokeScript | Should -Match 'componentPresence'
        $script:RenderSmokeScript | Should -Match 'firstViewportComponentPresence'
        $script:RenderSmokeScript | Should -Match 'navigation'
        $script:RenderSmokeScript | Should -Match 'startHere'
        $script:RenderSmokeScript | Should -Match 'blankPage'
        $script:RenderSmokeScript | Should -Match 'croppedElementCount'
        $script:RenderSmokeScript | Should -Match 'overlapWarningCount'
        $script:RenderSmokeScript | Should -Match 'detailsCount'
        $script:RenderSmokeScript | Should -Match 'detailsKeyboardSanity'
        $script:RenderSmokeScript | Should -Match 'tableOverflowCount'
        $script:RenderSmokeScript | Should -Match 'uniqueActionableLinkLabelCount'
        $script:RenderSmokeScript | Should -Match 'linkLabelSanityPassed'
    }

    It 'uses CI-friendly Chrome launch flags and retries DevTools startup' {
        $script:RenderSmokeScript | Should -Match '--disable-dev-shm-usage'
        $script:RenderSmokeScript | Should -Match '--remote-debugging-address=127[.]0[.]0[.]1'
        $script:RenderSmokeScript | Should -Match 'rendered-profile-smoke-chrome-\$attempt[.]err[.]log'
        $script:RenderSmokeScript | Should -Match 'for \(\$attempt = 1; \$attempt -le 2'
        $script:RenderSmokeScript | Should -Match 'Chrome exited before DevTools became ready'
        $script:RenderSmokeScript | Should -Match 'function Connect-CdpWebSocket'
        $script:RenderSmokeScript | Should -Match 'CancellationTokenSource'
    }

    It 'guards recursive cleanup to the generated temp profile directory' {
        $script:RenderSmokeScript | Should -Match 'function Remove-RenderedSmokeProfileDir'
        $script:RenderSmokeScript | Should -Match 'SysAdminDoc-render-smoke-\[0-9a-f\]\{32\}'
        $script:RenderSmokeScript | Should -Match 'Refusing to remove unexpected rendered-smoke profile directory'
        $script:RenderSmokeScript | Should -Match 'Remove-RenderedSmokeProfileDir -Path \$profileDir'
    }

    It 'remains a local smoke script while hosted workflows are absent' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/profile-sync.yml') | Should -BeFalse
        $script:RenderSmokeScript | Should -Match 'rendered-profile-smoke[.]json'
        $script:RenderSmokeScript | Should -Match 'rendered-profile-smoke-'
        $script:SyncProfileScript | Should -Match 'SmokeReportPath = "reports/rendered-profile-smoke[.]json"'
        $script:SyncProfileScript | Should -Match 'Read-RenderedProfileSmokeReport'
        $script:SyncProfileScript | Should -Match 'missing-local-artifact'
    }
}

Describe 'Portfolio-only demotion decision' {
    BeforeAll {
        $script:PortfolioOnlyDecisionCatalog = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') -Raw | ConvertFrom-Json
        $script:PortfolioOnlyDecisionReport = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw | ConvertFrom-Json
    }

    It 'keeps the reviewed README density candidates encoded in tracked catalog data' {
        foreach ($repo in @(
                'CSV_Power_Tool',
                'Flux',
                'PillSleepTracker',
                'UniversalCompiler',
                'GmailDownloader',
                'bypassnroGen',
                'LipSight',
                'PDFedit',
                'QR-Code-Generator-Pro',
                'Stock-Video-Collector',
                'Tunerize'
            )) {
            $entry = @($script:PortfolioOnlyDecisionCatalog.entries | Where-Object { $_.repo -eq $repo })
            $entry | Should -HaveCount 1
            $entry[0].includeInReadme | Should -BeFalse
            $entry[0].includeInPortfolio | Should -BeTrue
            $entry[0].readmeReviewNote | Should -Match 'Approved for portfolio-only routing'
        }
        $script:PortfolioOnlyDecisionReport.readmeDensity.portfolioOnlyPreview.preservesPortfolioRoutes | Should -BeTrue
    }
}

Describe 'Portfolio-only catalog mutation' {
    BeforeAll {
        $script:ApprovedPortfolioOnlyRepos = @(
            'CSV_Power_Tool',
            'Flux',
            'PillSleepTracker',
            'UniversalCompiler',
            'GmailDownloader',
            'bypassnroGen',
            'LipSight',
            'PDFedit',
            'QR-Code-Generator-Pro',
            'Stock-Video-Collector',
            'Tunerize'
        )
        $script:PortfolioOnlyCatalog = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') -Raw | ConvertFrom-Json
        $script:PortfolioOnlyFeed = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'projects.json') -Raw | ConvertFrom-Json
        $script:PortfolioOnlyReport = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw | ConvertFrom-Json
        $script:GeneratedReadme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw
    }

    It 'routes the approved rows to the portfolio feed only' {
        foreach ($repo in $script:ApprovedPortfolioOnlyRepos) {
            $catalogEntry = @($script:PortfolioOnlyCatalog.entries | Where-Object { $_.repo -eq $repo })
            $catalogEntry | Should -HaveCount 1
            $catalogEntry[0].includeInReadme | Should -BeFalse
            $catalogEntry[0].includeInPortfolio | Should -BeTrue
            [string]$catalogEntry[0].suppressionReason | Should -Be ''
            $catalogEntry[0].readmeReviewNote | Should -Match 'Approved for portfolio-only routing in v4[.]9[.]95'

            @($script:PortfolioOnlyFeed.projects | Where-Object { $_.repo -eq $repo }) | Should -HaveCount 1
            $script:GeneratedReadme | Should -Not -Match ([regex]::Escape("github.com/SysAdminDoc/$repo"))
        }
    }

    It 'keeps the committed README density report below portfolio-only review thresholds' {
        $density = $script:PortfolioOnlyReport.readmeDensity

        $density.warningCount | Should -Be 0
        $density.portfolioOnlyCandidateCount | Should -Be 0
        $density.portfolioOnlyCandidateCategoryCount | Should -Be 0
        $density.routingRecommendation | Should -Be 'keep-readme-routing-surface'
        $density.largestCategoryCount | Should -BeLessOrEqual $density.categorySoftLimit
        $density.portfolioOnlyPreview.status | Should -Be 'no-candidates'
        $density.portfolioOnlyPreview.remainingOverSoftLimitCategoryCount | Should -Be 0
        $density.portfolioOnlyPreview.projectRowDelta | Should -Be 0

        foreach ($row in $density.categoryRows) {
            $row.overCategorySoftLimitBy | Should -Be 0
            $row.portfolioOnlyCandidateCount | Should -Be 0
        }
    }
}

Describe 'Required status check readiness' {
    It 'has no hosted required-check candidates under the local-only policy' {
        @($RequiredStatusCheckCandidates) | Should -HaveCount 0
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows') | Should -BeFalse
    }

    It 'reports workflow coverage as not applicable when no hosted candidates exist' {
        $coverage = Test-RequiredCheckWorkflowCoverage

        $coverage.status | Should -Be 'not-applicable'
        $coverage.workflowCount | Should -Be 0
        $coverage.candidateCheckCount | Should -Be 0
        $coverage.warningCount | Should -Be 0
        $coverage.workflows | Should -BeNullOrEmpty
    }

    It 'reports required-check readiness as local-validation-only' {
        $readiness = Get-RequiredCheckReadiness -BranchProtectionAvailable:$true -RulesetsAvailable:$true -RequiredStatusChecks $false -EnforceAdmins $true -ActionsPullRequestCreationAllowed $false -RulesetCount 0 -BranchProtectionUnavailableReason '' -RulesetsUnavailableReason ''

        $readiness.status | Should -Be 'not-applicable'
        $readiness.recommendation | Should -Be 'local-validation-only'
        $readiness.readyForEnforcement | Should -BeFalse
        $readiness.candidateCheckCount | Should -Be 0
        $readiness.workflowCoverage.status | Should -Be 'not-applicable'
        $readiness.prDeliveryTransition.status | Should -Be 'not-applicable'
        $readiness.blockerCount | Should -Be 0
    }
}

Describe 'Tracked profile version metadata' {
    BeforeAll {
        $script:ProfileVersionMetadata = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'data/profile-version.json') -Raw | ConvertFrom-Json
    }

    It 'keeps the CI-visible version source in tracked JSON' {
        $script:ProfileVersionMetadata.version | Should -Match '^v\d+\.\d+\.\d+$'
        $script:ProfileVersionMetadata.date | Should -Match '^\d{4}-\d{2}-\d{2}$'
        $script:ProfileVersionMetadata.source | Should -Be 'profile-sync-internal-evidence-version'
        $script:ProfileVersionMetadata.publicReleaseCadence | Should -Be 'manual-public-milestone-only'
    }

    It 'does not depend on local-only planning markdown for the version gate' {
        $result = Test-DocVersionConsistency -ProfileVersionPath (Join-Path $script:RepoRoot 'data/profile-version.json')

        $result.passed | Should -BeTrue
        ($result.versions + $result.dates | ForEach-Object { $_.path }) | Should -Not -Match 'ROADMAP|CHANGELOG|PROJECT_CONTEXT|RESEARCH_REPORT'
    }
}

Describe 'Generated profile PR validation handoff' {
    It 'retires the hosted generated-PR helper scripts under the local-only policy' {
        # The helpers only orchestrated hosted workflows, which this checkout does not
        # have and policy does not allow. They were removed rather than kept dormant.
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/profile-sync.yml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/assets-refresh.yml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'scripts/open-generated-profile-pr.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'scripts/set-generated-validation-status.ps1') | Should -BeFalse
    }

    It 'keeps no generated-PR helper references in the validation lane' {
        $validationScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/validate-local.ps1') -Raw
        $syncScript = $script:SyncProfileScript

        $validationScript | Should -Not -Match 'open-generated-profile-pr|set-generated-validation-status'
        $syncScript | Should -Not -Match 'open-generated-profile-pr|set-generated-validation-status'
    }
}

Describe 'Generated automation branch cleanup' {
    It 'has no scheduled cleanup workflow under the local-only policy' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/automation-branch-cleanup.yml') | Should -BeFalse
    }
}

Describe 'Profile sync report summaries' -Tag 'Integration' {
    BeforeAll {
        $script:SummaryScriptPath = Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1'
        $script:SummaryScript = Get-Content -LiteralPath $script:SummaryScriptPath -Raw
    }

    It 'writes a public-safe aggregate summary from the committed report' {
        $summaryPath = New-TemporaryFile
        try {
            pwsh -NoProfile -File $script:SummaryScriptPath -ReportPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -SummaryPath $summaryPath.FullName -Context 'Pester summary test'
            $summary = Get-Content -LiteralPath $summaryPath.FullName -Raw

            $summary | Should -Match 'Pester summary test report'
            $summary | Should -Match 'Fatal metadata drift'
            $summary | Should -Match 'Missing topic hints'
            $summary | Should -Match 'Public missing topic rows'
            $summary | Should -Match 'Redacted metadata topic gaps'
            $summary | Should -Match 'Metadata hygiene handoff'
            $summary | Should -Match 'Metadata handoff topic rows'
            $summary | Should -Match 'Missing project licenses'
            $summary | Should -Match 'Unknown project licenses'
            $summary | Should -Match 'Fork-parent warnings'
            $summary | Should -Match 'Fork-parent public detail rows'
            $summary | Should -Match 'Fork-parent redacted detail rows'
            $summary | Should -Match 'Stale project review rows'
            $summary | Should -Match 'Archive review candidates'
            $summary | Should -Match 'Catalog rows accounted'
            $summary | Should -Match 'Catalog accounting fatal gaps'
            $summary | Should -Match 'Portfolio compatibility'
            $summary | Should -Match 'Portfolio compatibility fatal gaps'
            $summary | Should -Match 'Portfolio compatibility warnings'
            $summary | Should -Match 'README density warnings'
            $summary | Should -Match 'README largest category'
            $summary | Should -Match 'README repo-only rows'
            $summary | Should -Match 'README portfolio-only candidates'
            $summary | Should -Match 'README candidate sample'
            $summary | Should -Match 'README portfolio-only preview'
            $summary | Should -Match 'README preview row delta'
            $summary | Should -Match 'README preview rows'
            $summary | Should -Match 'README preview over-limit categories'
            $summary | Should -Match 'README routing recommendation'
            $summary | Should -Match 'Artifact budget status'
            $summary | Should -Match 'Artifact budget warnings'
            $summary | Should -Match 'Artifact budget rows'
            $summary | Should -Match 'Rendered smoke status'
            $summary | Should -Match 'Rendered smoke warnings'
            $summary | Should -Match 'Rendered smoke mobile root px'
            $summary | Should -Match 'Profile release/tag warnings'
            $summary | Should -Match 'Profile release policy'
            $summary | Should -Match 'Profile release warning disposition'
            $summary | Should -Match 'Profile release creation recommended'
            $summary | Should -Match 'Userscript installs checked'
            $summary | Should -Match 'Userscript trust warnings'
            $summary | Should -Match 'Link targets checked'
            $summary | Should -Match 'README action link targets'
            $summary | Should -Match 'README install snippet targets'
            $summary | Should -Match 'README download link targets'
            $summary | Should -Match 'README userscript install targets'
            $summary | Should -Match 'Metadata provider'
            $summary | Should -Match 'Metadata GraphQL page size'
            $summary | Should -Match 'Metadata request count'
            $summary | Should -Match 'Metadata retry count'
            $summary | Should -Match 'Metadata resource-limit fallback'
            $summary | Should -Match 'Validation cache enabled'
            $summary | Should -Match 'Validation cache TTL hours'
            $summary | Should -Match 'Metadata cache hits'
            $summary | Should -Match 'Metadata cache fallback used'
            $summary | Should -Match 'Release cache hits'
            $summary | Should -Match 'Release cache fallback used'
            $summary | Should -Match 'Link cache hits'
            $summary | Should -Match 'Link cache writes'
            $summary | Should -Match 'REST fallback release status'
            $summary | Should -Match 'REST fallback release max requests'
            $summary | Should -Match 'REST fallback release unauth cap'
            $summary | Should -Match 'REST fallback release attempts'
            $summary | Should -Match 'REST fallback no-release 404s'
            $summary | Should -Match 'Repository setting warnings'
            $summary | Should -Match 'Required check readiness'
            $summary | Should -Match 'Required check candidates'
            $summary | Should -Match 'Required check blockers'
            $summary | Should -Match 'PR delivery transition'
            $summary | Should -Match 'Generated PR dry-run evidence'
            $summary | Should -Match 'Generated PR dry-run conclusion'
            $summary | Should -Match 'Generated PR dry-run preview reached'
            $summary | Should -Match 'Generated PR dry-run failed step'
            $summary | Should -Match 'Generated PR write evidence'
            $summary | Should -Match 'Generated PR write conclusion'
            $summary | Should -Match 'Generated PR write failed step'
            $summary | Should -Match 'Generated PR write branch cleanup'
            $summary | Should -Match 'Generated PR branch check runs'
            $summary | Should -Match 'Generated PR PR checks attached'
            $summary | Should -Match 'Generated PR status context'
            $summary | Should -Not -Match 'generated-profile/validation'
            $summary | Should -Match 'Candidate check exercise latest evidence'
            $summary | Should -Match 'Candidate check exercise failed names'
            $summary | Should -Match 'Routine PR drill status'
            $summary | Should -Match 'Routine PR drill cleanup'
            $summary | Should -Match 'Code scanning status'
            $summary | Should -Match 'Code scanning recommendation'
            $summary | Should -Match 'Code scanning languages'
            $summary | Should -Match 'Code scanning controls'
            $summary | Should -Match 'Community-health fatal gaps'
            $summary | Should -Not -Match 'AppManagerNG'
            $summary | Should -Not -Match 'VaultBox'
        } finally {
            Remove-Item -LiteralPath $summaryPath.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'lists fatal metadata drift rows in summaries and GitHub annotations' {
        $reportPath = New-TemporaryFile
        $summaryPath = New-TemporaryFile
        try {
            $report = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw | ConvertFrom-Json
            $report.metadataDrift = @(
                [pscustomobject]@{
                    repo = 'BadRepo'
                    category = 'web'
                    field = 'primaryAction.url'
                    oldValue = 'https://old.example/install'
                    newValue = 'https://new.example/install'
                    severity = 'fatal'
                    failing = $true
                },
                [pscustomobject]@{
                    repo = $null
                    category = $null
                    field = 'provenance.catalogSha256'
                    oldValue = 'aaa'
                    newValue = 'bbb'
                    severity = 'fatal'
                    failing = $true
                }
            )
            $report.metadataDriftSummary.fatalCount = 2
            $report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $reportPath.FullName -Encoding utf8

            $output = pwsh -NoProfile -File $script:SummaryScriptPath -ReportPath $reportPath.FullName -SummaryPath $summaryPath.FullName -Context 'Fatal drift test' 2>&1
            $summary = Get-Content -LiteralPath $summaryPath.FullName -Raw

            $summary | Should -Match 'Fatal Metadata Drift Details'
            $summary | Should -Match 'BadRepo'
            $summary | Should -Match 'web'
            $summary | Should -Match 'primaryAction[.]url'
            ($output -join "`n") | Should -Match '::error file=projects[.]json,title=Fatal metadata drift::repo=BadRepo; category=web; field=primaryAction[.]url'
            ($output -join "`n") | Should -Match 'repo=top-level; category=top-level; field=provenance[.]catalogSha256'
        } finally {
            Remove-Item -LiteralPath $reportPath.FullName -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $summaryPath.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'lists generated artifact drift diagnostics and remediation in summaries' {
        $reportPath = New-TemporaryFile
        $summaryPath = New-TemporaryFile
        try {
            $report = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw | ConvertFrom-Json
            $report.readmeInSync = $false
            $report.projectsExportInSync = $false
            $report.profileAssetsInSync = $false
            $artifactDriftDiagnostics = [pscustomobject]@{
                remediationCommand = 'pwsh -NoLogo -NoProfile -File ./scripts/sync-profile.ps1 -Write'
                readme = [pscustomobject]@{
                    artifact = 'README.md'
                    inSync = $false
                    currentSha256 = ('a' * 64)
                    expectedSha256 = ('b' * 64)
                    firstDiff = [pscustomobject]@{
                        line = 12
                        sectionMarker = [pscustomobject]@{ line = 10; text = '## Tool Catalog' }
                        current = 'old row'
                        expected = 'new row'
                    }
                }
                projects = [pscustomobject]@{
                    artifact = 'projects.json'
                    inSync = $false
                    currentSha256 = ('c' * 64)
                    expectedSha256 = ('d' * 64)
                    diffBasis = 'comparable-json-lines'
                    firstDiff = [pscustomobject]@{
                        line = 1
                        sectionMarker = $null
                        current = '{"stale":true}'
                        expected = '{"schema":"profile"}'
                    }
                }
                assets = [pscustomobject]@{
                    inSync = $false
                    affectedAssetCount = 1
                    affectedAssets = @(
                        [pscustomobject]@{
                            path = 'assets/profile/footer-dark.svg'
                            exists = $true
                            fatal = $true
                            currentSha256 = ('e' * 64)
                            expectedSha256 = ('f' * 64)
                            remediation = 'run-write'
                        },
                        [pscustomobject]@{
                            path = 'assets/profile/stray.svg'
                            exists = $true
                            fatal = $true
                            currentSha256 = ('0' * 64)
                            expectedSha256 = $null
                            remediation = 'delete-file'
                        }
                    )
                }
            }
            if ($report.PSObject.Properties.Name -contains 'artifactDriftDiagnostics') {
                $report.artifactDriftDiagnostics = $artifactDriftDiagnostics
            } else {
                $report | Add-Member -NotePropertyName artifactDriftDiagnostics -NotePropertyValue $artifactDriftDiagnostics
            }
            $report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $reportPath.FullName -Encoding utf8

            pwsh -NoProfile -File $script:SummaryScriptPath -ReportPath $reportPath.FullName -SummaryPath $summaryPath.FullName -Context 'Artifact drift test'
            $summary = Get-Content -LiteralPath $summaryPath.FullName -Raw

            $summary | Should -Match 'Generated Artifact Drift'
            $summary | Should -Match 'Remediation: `pwsh -NoLogo -NoProfile -File ./scripts/sync-profile[.]ps1 -Write`'
            $summary | Should -Match '\| Section enforcement \| \d+ blocking, \d+ advisory by policy, \d+ pending decision \|'
            $summary | Should -Match '#### Pending Enforcement Decisions'
            $summary | Should -Match '\| userscriptInstallTrust \| Should a userscript'
            $summary | Should -Match 'README[.]md'
            $summary | Should -Match ('a' * 64)
            $summary | Should -Match ('b' * 64)
            $summary | Should -Match '## Tool Catalog'
            $summary | Should -Match '\| projects[.]json \| `c{64}` \| `d{64}` \| 1 \(masked JSON\) \|'
            $summary | Should -Match 'assets/profile/footer-dark[.]svg'
            $summary | Should -Match '\| assets/profile/stray[.]svg \| True \| `0{64}` \| not generated \| Delete the file; the generator does not produce it and -Write never deletes[.] \|'
            $summary | Should -Match '\| assets/profile/footer-dark[.]svg \| True \| `e{64}` \| `f{64}` \| Run the remediation command[.] \|'
        } finally {
            Remove-Item -LiteralPath $reportPath.FullName -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $summaryPath.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits GitHub annotations and uses aggregate report sections only' {
        $script:SummaryScript | Should -Match 'metadataDriftSummary'
        $script:SummaryScript | Should -Match 'metadataDrift'
        $script:SummaryScript | Should -Match 'artifactDriftDiagnostics'
        $script:SummaryScript | Should -Match 'Generated Artifact Drift'
        $script:SummaryScript | Should -Match 'Fatal Metadata Drift Details'
        $script:SummaryScript | Should -Match 'Metadata Hygiene Handoff'
        $script:SummaryScript | Should -Match 'metadataHandoff'
        $script:SummaryScript | Should -Match 'linkValidationSummary'
        $script:SummaryScript | Should -Match 'projectLicenseMetadata'
        $script:SummaryScript | Should -Match 'forkParentDrift'
        $script:SummaryScript | Should -Match 'Fork-parent redacted detail rows'
        $script:SummaryScript | Should -Match 'staleProjectReview'
        $script:SummaryScript | Should -Match 'profileReleaseConsistency'
        $script:SummaryScript | Should -Match 'releasePolicy'
        $script:SummaryScript | Should -Match '::notice::Profile sync report has'
        $script:SummaryScript | Should -Match 'userscriptInstallTrust'
        $script:SummaryScript | Should -Match 'catalogFeedAccounting'
        $script:SummaryScript | Should -Match 'portfolioCompatibility'
        $script:SummaryScript | Should -Match 'readmeDensity'
        $script:SummaryScript | Should -Match 'portfolioOnlyCandidateCount'
        $script:SummaryScript | Should -Match 'portfolioOnlyCandidates'
        $script:SummaryScript | Should -Match 'portfolioOnlyPreview'
        $script:SummaryScript | Should -Match 'artifactBudgets'
        $script:SummaryScript | Should -Match 'renderedProfileSmoke'
        $script:SummaryScript | Should -Match 'metadataFetch'
        $script:SummaryScript | Should -Match 'Metadata GraphQL page size'
        $script:SummaryScript | Should -Match 'restFallbackReleaseFetch'
        $script:SummaryScript | Should -Match 'repositorySettings'
        $script:SummaryScript | Should -Match 'actionsWorkflowPermissions'
        $script:SummaryScript | Should -Match 'generatedPrCredentialDecision'
        $script:SummaryScript | Should -Match 'Generated PR credential decision'
        $script:SummaryScript | Should -Match 'requiredCheckReadiness'
        $script:SummaryScript | Should -Match 'prDeliveryTransition'
        $script:SummaryScript | Should -Match 'generatedPrDryRunEvidence'
        $script:SummaryScript | Should -Match 'generatedPrWriteEvidence'
        $script:SummaryScript | Should -Match 'Generated PR validation conclusion'
        $script:SummaryScript | Should -Match 'Generated PR PR check count'
        $script:SummaryScript | Should -Match 'Generated PR status handoff'
        $script:SummaryScript | Should -Match 'statusHandoffContext'
        $script:SummaryScript | Should -Match 'statusHandoffState'
        $script:SummaryScript | Should -Match 'directMainMaintenancePolicy'
        $script:SummaryScript | Should -Match 'Direct-main maintenance policy'
        $script:SummaryScript | Should -Match 'candidateCheckExercisePlan'
        $script:SummaryScript | Should -Match 'candidateCheckExerciseEvidence'
        $script:SummaryScript | Should -Match 'routineMaintenancePrDrillEvidence'
        $script:SummaryScript | Should -Match 'requiredCheckEnforcementEvidence'
        $script:SummaryScript | Should -Match 'reviewPolicyPosture'
        $script:SummaryScript | Should -Match 'Review policy posture'
        $script:SummaryScript | Should -Match 'Scorecard CodeReview classification'
        $script:SummaryScript | Should -Match 'dependabotSecurityPosture'
        $script:SummaryScript | Should -Match 'Dependabot security posture'
        $script:SummaryScript | Should -Match 'Dependabot local config ecosystems'
        $script:SummaryScript | Should -Match 'Routine PR drill status'
        $script:SummaryScript | Should -Match 'Candidate check exercise plan'
        $script:SummaryScript | Should -Match 'Candidate check exercise evidence is'
        $script:SummaryScript | Should -Match 'codeScanning'
        $script:SummaryScript | Should -Match 'scorecardAlertPosture'
        $script:SummaryScript | Should -Match 'Code scanning local controls'
        $script:SummaryScript | Should -Match 'Code scanning hosted controls'
        $script:SummaryScript | Should -Match 'Scorecard open alerts'
        $script:SummaryScript | Should -Match 'communityHealth'
        $script:SummaryScript | Should -Match '::warning::'
        $script:SummaryScript | Should -Match '::error::'
    }

    It 'keeps the committed report summary below the local step-summary soft budget' {
        $summaryPath = New-TemporaryFile
        try {
            pwsh -NoProfile -File $script:SummaryScriptPath -ReportPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -SummaryPath $summaryPath.FullName -Context 'Pester summary budget test'
            $summary = Get-Content -LiteralPath $summaryPath.FullName -Raw
            $summaryBytes = [Text.Encoding]::UTF8.GetByteCount($summary)

            $summaryBytes | Should -BeLessThan 65536
            $script:SummaryScript | Should -Match '1MB'
            $script:SummaryScript | Should -Match '65536'
        } finally {
            Remove-Item -LiteralPath $summaryPath.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps report summary generation local when hosted workflows are absent' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows') | Should -BeFalse
        $script:SummaryScript | Should -Match 'profile-sync-report[.]json'
        $script:SummaryScript | Should -Not -Match 'scheduledWorkflowFreshness'
    }
}

Describe 'Hosted automation removal contract' {
    It 'keeps workflow and Dependabot automation files absent' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/dependabot.yml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/renovate.json') | Should -BeFalse
    }

    It 'keeps the zizmor scanner config absent' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/zizmor.yml') | Should -BeFalse
    }

    It 'keeps the scheduled-workflow freshness lane removed' {
        $script:SyncProfileScript | Should -Not -Match 'scheduledWorkflowFreshness'
        $script:SyncProfileScript | Should -Not -Match 'function Get-CronNumericSet'
        $script:SyncProfileScript | Should -Not -Match 'function Get-CronWeekMinuteOffsets'
        $script:SyncProfileScript | Should -Not -Match 'function Get-CronMaxGapMinutes'
        $script:SyncProfileScript | Should -Not -Match 'function Get-ScheduledWorkflowDefinitions'
        $script:SyncProfileScript | Should -Not -Match 'function Get-ScheduledWorkflowRunLookup'
    }
}

Describe 'Public-safe intake files' {
    It 'publishes a security policy that avoids public sensitive disclosure' {
        $securityPolicy = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'SECURITY.md') -Raw

        $securityPolicy | Should -Match 'private vulnerability reporting'
        $securityPolicy | Should -Match 'https://github\.com/SysAdminDoc/SysAdminDoc/security/advisories/new'
        $securityPolicy | Should -Match 'Do not include secrets'
        $securityPolicy | Should -Match 'private repository names'
        $securityPolicy | Should -Match 'medical data'
    }

    It 'provides issue forms for broken links, profile corrections, and local validation problems' {
        foreach ($file in @(
            '.github/ISSUE_TEMPLATE/broken-link.yml',
            '.github/ISSUE_TEMPLATE/profile-correction.yml',
            '.github/ISSUE_TEMPLATE/local-validation.yml'
        )) {
            $content = Get-Content -LiteralPath (Join-Path $script:RepoRoot $file) -Raw
            $content | Should -Match 'validations:'
            $content | Should -Match 'required: true'
            $content | Should -Match 'Do not'
        }
    }

    It 'routes sensitive issue reports to the security policy' {
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/ISSUE_TEMPLATE/config.yml') -Raw

        $config | Should -Match 'blank_issues_enabled: false'
        $config | Should -Match 'security/policy'
    }

    It 'warns pull requests not to hand-edit generated README sections' {
        $template = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/pull_request_template.md') -Raw

        $template | Should -Match 'Public-Safety Check'
        $template | Should -Match 'data/profile-catalog.json'
        $template | Should -Match 'hand-edit generated README sections'
    }
}

Describe 'Medical privacy gate in Test-ProfileState' {
    It 'flags a catalog entry whose repo metadata contains medical keywords' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $medicalRepo = New-TestRepoMeta -Name 'WinTool' -Description 'A DICOM viewer for radiology'
        $expectedReadme = New-Readme -Catalog $cat -Repos @($medicalRepo)
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @($medicalRepo)

        $result = Test-ProfileState `
            -Catalog $cat `
            -Repos @($medicalRepo) `
            -ExpectedReadme $expectedReadme `
            -ExpectedProjects $expectedProjects `
            -SkipLinkValidation

        $result.Failed | Should -BeTrue
        @($result.Report.medicalPrivacyViolations).Count | Should -BeGreaterOrEqual 1
        ($result.Report.medicalPrivacyViolations | ForEach-Object { $_.repo }) | Should -Contain 'WinTool'
    }

    It 'allows medical keywords when allowPublicMedical is set' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $cat.entries[0].allowPublicMedical = $true
        $medicalRepo = New-TestRepoMeta -Name 'WinTool' -Description 'A DICOM viewer for radiology'
        $expectedReadme = New-Readme -Catalog $cat -Repos @($medicalRepo)
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @($medicalRepo)

        $result = Test-ProfileState `
            -Catalog $cat `
            -Repos @($medicalRepo) `
            -ExpectedReadme $expectedReadme `
            -ExpectedProjects $expectedProjects `
            -SkipLinkValidation

        @($result.Report.medicalPrivacyViolations).Count | Should -Be 0
    }
}

Describe 'URL scheme safety' {
    It 'rejects non-https URLs in visitor-facing catalog fields' {
        $entries = @(
            (New-TestEntry -Repo 'Safe' -Category 'web'),
            (New-TestEntry -Repo 'Unsafe' -Category 'web')
        )
        $entries[0].liveUrl = 'https://sysadmindoc.github.io/Safe/'
        $entries[1].liveUrl = 'javascript:alert(1)'

        $violations = @(Test-CatalogUrlSchemes -Entries $entries)

        $violations | Should -HaveCount 1
        $violations[0].repo | Should -Be 'Unsafe'
        $violations[0].field | Should -Be 'liveUrl'
    }

    It 'accepts null and empty URLs without violation' {
        $entry = New-TestEntry -Repo 'NoUrl' -Category 'powershell'
        $violations = @(Test-CatalogUrlSchemes -Entries @($entry))
        $violations | Should -HaveCount 0
    }
}

Describe 'Artifact drift diagnostic line location' {
    BeforeAll {
        $script:DiffExpectedLines = @(
            '<p align="center"><b>Tagline</b></p>',
            '',
            '### What''s here',
            'Pick a category.',
            '<summary><b>PowerShell</b></summary>',
            '[**ToolA**](https://github.com/o/ToolA) &#11088;4 -- first tool',
            '[**ToolB**](https://github.com/o/ToolB) &#11088;2 -- second tool'
        )
    }

    It 'reports the first differing line and its section when a later line drifts' {
        $current = @($script:DiffExpectedLines)
        $current[6] = '[**ToolB**](https://github.com/o/ToolB) &#11088;3 -- second tool'

        $diagnostic = New-TextArtifactDiffDiagnostic -Artifact 'README.md' -Current ($current -join "`n") -Expected ($script:DiffExpectedLines -join "`r`n") -InSync:$false

        $diagnostic.firstDiff.line | Should -Be 7
        $diagnostic.firstDiff.current | Should -Be $current[6]
        $diagnostic.firstDiff.expected | Should -Be $script:DiffExpectedLines[6]
        $diagnostic.firstDiff.sectionMarker.line | Should -Be 5
        $diagnostic.firstDiff.sectionMarker.text | Should -Be '<summary><b>PowerShell</b></summary>'
    }

    It 'treats a letter-case change as the first difference, matching the case-sensitive sync verdict' {
        $current = @($script:DiffExpectedLines)
        $current[3] = 'PICK a category.'

        $diagnostic = New-TextArtifactDiffDiagnostic -Artifact 'README.md' -Current ($current -join "`n") -Expected ($script:DiffExpectedLines -join "`n") -InSync:$false

        $diagnostic.firstDiff.line | Should -Be 4
        $diagnostic.firstDiff.sectionMarker.text | Should -Be '### What''s here'
    }

    It 'reports an appended line after an otherwise identical artifact' {
        $current = @($script:DiffExpectedLines) + 'stray trailing line'

        $diagnostic = New-TextArtifactDiffDiagnostic -Artifact 'README.md' -Current ($current -join "`n") -Expected ($script:DiffExpectedLines -join "`n") -InSync:$false

        $diagnostic.firstDiff.line | Should -Be 8
        $diagnostic.firstDiff.current | Should -Be 'stray trailing line'
        $diagnostic.firstDiff.expected | Should -BeNullOrEmpty
        $diagnostic.diffBasis | Should -Be 'artifact-lines'
    }

    It 'names the enclosing section, not the changed table row or the row above it' {
        $expected = @(
            '### What''s here',
            '<summary><b>Web Applications</b> -- 2 repos</summary>',
            '| Project | Description | Live |',
            '|:--------|:------------|:----:|',
            '| [**Alpha**](https://github.com/o/Alpha) &#11088;3 | first | [Launch](https://o.github.io/Alpha/) |',
            '| [**Beta**](https://github.com/o/Beta) &#11088;1 | second | [Launch](https://o.github.io/Beta/) |'
        )
        $current = @($expected)
        $current[5] = '| [**Beta**](https://github.com/o/Beta) &#11088;2 | second | [Launch](https://o.github.io/Beta/) |'

        $diagnostic = New-TextArtifactDiffDiagnostic -Artifact 'README.md' -Current ($current -join "`n") -Expected ($expected -join "`n") -InSync:$false

        $diagnostic.firstDiff.line | Should -Be 6
        $diagnostic.firstDiff.sectionMarker.line | Should -Be 2
        $diagnostic.firstDiff.sectionMarker.text | Should -BeLike '<summary><b>Web Applications</b>*'
    }

    It 'windows a long line around the first differing column' {
        $prefix = '[**LibreSpot**](https://github.com/o/LibreSpot) &#11088;9 -- ' + ('word ' * 30)
        $expectedLine = $prefix + '[<kbd>Download</kbd>](https://github.com/o/LibreSpot/releases/latest) trailing text'
        $currentLine = $prefix + '[<kbd>Download</kbd>](https://github.com/o/LibreSpot/releases/tag/v2) trailing text'
        $prefix.Length | Should -BeGreaterThan 180 -Because 'the difference must sit past the unwindowed snippet'

        $diagnostic = New-TextArtifactDiffDiagnostic -Artifact 'README.md' -Current $currentLine -Expected $expectedLine -InSync:$false

        $diagnostic.firstDiff.line | Should -Be 1
        $diagnostic.firstDiff.current | Should -Not -Be $diagnostic.firstDiff.expected
        $diagnostic.firstDiff.current | Should -BeLike '...*releases/tag/v2*'
        $diagnostic.firstDiff.expected | Should -BeLike '...*releases/latest*'
    }

    It 'locates feed drift in the masked comparable JSON and names the project it is in' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @() -GeneratedAt '2026-09-01T00:00:00.0000000Z'
        $payload = $expectedProjects | ConvertFrom-Json -DateKind String
        $target = $payload.projects[1]
        $target.description = 'Changed description for the drift test'
        # A newer timestamp is volatile: masked by the verdict, so it must not be reported.
        $payload.generatedAt = '2026-09-22T00:00:00.0000000Z'
        $currentProjects = $payload | ConvertTo-Json -Depth 50 -Compress

        $diagnostics = New-GeneratedArtifactDriftDiagnostics `
            -CurrentReadme 'same' -ExpectedReadme 'same' `
            -CurrentProjects $currentProjects -ExpectedProjects $expectedProjects `
            -ReadmeInSync:$true -ProjectsInSync:$false -ProfileAssetsInSync:$true `
            -AssetChecks @() -ExpectedAssets @{}

        $diagnostics.projects.diffBasis | Should -Be 'comparable-json-lines'
        $diagnostics.projects.firstDiff.current | Should -Match 'Changed description for the drift test'
        $diagnostics.projects.firstDiff.expected | Should -Not -Match 'Changed description'
        $diagnostics.projects.firstDiff.line | Should -BeGreaterThan 1
        $diagnostics.projects.firstDiff.sectionMarker.text | Should -Be ('"id": "{0}",' -f $target.id)
        $diagnostics.readme.diffBasis | Should -Be 'artifact-lines'
    }
}

Describe 'Test-ProfileState projects sync gate' {
    It 'fails with artifact diagnostics when README and projects.json are out of sync' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedReadme = New-Readme -Catalog $cat -Repos @()
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @()

        $result = Test-ProfileState `
            -Catalog $cat `
            -Repos @() `
            -ExpectedReadme $expectedReadme `
            -ExpectedProjects $expectedProjects `
            -CurrentReadme "# stale profile`n" `
            -CurrentProjects '{"stale":true}' `
            -SkipLinkValidation

        $result.Failed | Should -BeTrue
        $result.Report.readmeInSync | Should -BeFalse
        $result.Report.projectsExportInSync | Should -BeFalse
        $result.Report.artifactDriftDiagnostics.remediationCommand | Should -Be 'pwsh -NoLogo -NoProfile -File ./scripts/sync-profile.ps1 -Write'
        $result.Report.artifactDriftDiagnostics.readme.currentSha256 | Should -Match '^[a-f0-9]{64}$'
        $result.Report.artifactDriftDiagnostics.readme.expectedSha256 | Should -Match '^[a-f0-9]{64}$'
        $result.Report.artifactDriftDiagnostics.readme.firstDiff.line | Should -Be 1
        $result.Report.artifactDriftDiagnostics.readme.firstDiff.current | Should -Be '# stale profile'
        $result.Report.artifactDriftDiagnostics.projects.currentSha256 | Should -Match '^[a-f0-9]{64}$'
        $result.Report.artifactDriftDiagnostics.projects.expectedSha256 | Should -Match '^[a-f0-9]{64}$'
        # The feed is compared as masked, indented JSON: line 1 is the shared "{".
        $result.Report.artifactDriftDiagnostics.projects.diffBasis | Should -Be 'comparable-json-lines'
        $result.Report.artifactDriftDiagnostics.projects.firstDiff.line | Should -Be 2
        $result.Report.artifactDriftDiagnostics.projects.firstDiff.current | Should -Match '"stale": true'
    }

    It 'passes when projects.json differs only by informational metadata drift' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -Language 'PowerShell'),
            (New-TestRepoMeta -Name 'PyTool' -Language 'Python'),
            (New-TestRepoMeta -Name 'WebTool' -Language 'JavaScript')
        )
        $expectedReadme = New-Readme -Catalog $cat -Repos $repos
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos $repos
        $currentProjectsPayload = $expectedProjects | ConvertFrom-Json
        $currentProjectsPayload.provenance.sourceCommit = '0000000000000000000000000000000000000000'
        $currentProjectsPayload.provenance.metadataSnapshotAt = '2026-06-07T00:00:00Z'
        $currentProjectsPayload.provenance.repoEnumeration.requestedLimit = 300
        $currentProjectsPayload.projects[0].pushedAt = '2026-06-07T10:05:07Z'
        $currentProjects = $currentProjectsPayload | ConvertTo-Json -Depth 20

        $result = Test-ProfileState `
            -Catalog $cat `
            -Repos $repos `
            -ExpectedReadme $expectedReadme `
            -ExpectedProjects $expectedProjects `
            -CurrentReadme $expectedReadme `
            -CurrentProjects $currentProjects `
            -SkipLinkValidation

        $result.Report.projectsExportInSync | Should -BeTrue
        $result.Report.metadataDriftSummary.fatalCount | Should -Be 0
        @($result.Report.metadataDrift | Where-Object { $_.severity -eq 'info' }) | Should -Not -BeNullOrEmpty
        $limitDrift = @($result.Report.metadataDrift | Where-Object { $_.field -eq 'provenance.repoEnumeration.requestedLimit' })
        $limitDrift | Should -HaveCount 1
        $limitDrift[0].severity | Should -Be 'info'
    }

    It 'treats a difference in a field the drift model does not enumerate as out of sync' {
        # projectsExportInSync is now exactly this comparison, so a per-field sweep here
        # is a per-field sweep of the gate. One full Test-ProfileState run below proves
        # the wiring; running it thirteen more times only re-tests live GitHub metadata.
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -Language 'PowerShell'),
            (New-TestRepoMeta -Name 'PyTool' -Language 'Python'),
            (New-TestRepoMeta -Name 'WebTool' -Language 'JavaScript')
        )
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos $repos
        $unmodelled = @(
            @{ Path = 'projects.0.id'; Value = 'tampered-entity-id' }
            @{ Path = 'projects.0.canonicalRepo'; Value = 'SomeoneElse/Repo' }
            @{ Path = 'projects.0.aliases'; Value = @('bogus-alias') }
            @{ Path = 'projects.0.forkOf'; Value = 'someone/upstream' }
            @{ Path = 'projects.0.forkOfUrl'; Value = 'https://github.com/someone/upstream' }
            @{ Path = 'projects.0.upstreamLicense'; Value = 'GPL-3.0' }
            @{ Path = 'projects.0.licenseKey'; Value = 'proprietary' }
            @{ Path = 'projects.0.licenseName'; Value = 'Proprietary' }
            @{ Path = 'projects.0.licenseSpdxId'; Value = 'Proprietary' }
            @{ Path = 'projects.0.localeHints'; Value = @('zz-ZZ') }
            @{ Path = 'projects.0.scriptHints'; Value = @('Zzzz') }
            @{ Path = 'schemaPolicy.currentVersion'; Value = 9 }
            @{ Path = 'schemaPolicy.supportedVersions'; Value = @() }
        )

        foreach ($case in $unmodelled) {
            $payload = $expectedProjects | ConvertFrom-Json
            $segments = @($case.Path -split '\.')
            $target = $payload
            for ($i = 0; $i -lt $segments.Count - 1; $i++) {
                $segment = $segments[$i]
                $target = if ($segment -match '^\d+$') { $target[[int]$segment] } else { $target.$segment }
            }
            $leaf = $segments[-1]
            # The path must already exist, or the case is asserting against a field this
            # generator never emits and would pass for the wrong reason.
            $target.PSObject.Properties.Name | Should -Contain $leaf -Because "$($case.Path) must exist in the generated feed"
            $target.$leaf = $case.Value
            $current = $payload | ConvertTo-Json -Depth 20

            $comparable = (ConvertTo-ProjectsSyncComparableJson -Json $current) -eq (ConvertTo-ProjectsSyncComparableJson -Json $expectedProjects)
            $comparable | Should -BeFalse -Because "$($case.Path) is not a volatile field and must fail the sync gate"

            # The drift model alone would have passed every one of these, which is what
            # the removed -or fallback deferred to.
            $drift = Test-MetadataDrift -CurrentProjectsJson $current -ExpectedProjectsJson $expectedProjects
            [int]$drift.fatalCount | Should -Be 0 -Because "$($case.Path) is outside the drift model, so fatalCount cannot carry this gate"
        }
    }

    It 'fails the whole run when the feed differs outside the volatile mask' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -Language 'PowerShell'),
            (New-TestRepoMeta -Name 'PyTool' -Language 'Python'),
            (New-TestRepoMeta -Name 'WebTool' -Language 'JavaScript')
        )
        $expectedReadme = New-Readme -Catalog $cat -Repos $repos
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos $repos

        $payload = $expectedProjects | ConvertFrom-Json
        $payload.projects[0].id = 'tampered-entity-id'
        $payload.schemaPolicy.currentVersion = 9
        $currentProjects = $payload | ConvertTo-Json -Depth 20

        $result = Test-ProfileState `
            -Catalog $cat `
            -Repos $repos `
            -ExpectedReadme $expectedReadme `
            -ExpectedProjects $expectedProjects `
            -CurrentReadme $expectedReadme `
            -CurrentProjects $currentProjects `
            -SkipLinkValidation

        $result.Report.projectsExportInSync | Should -BeFalse
        $result.Failed | Should -BeTrue
        # Nothing in the drift model saw it, so the sync gate is the only thing standing.
        $result.Report.metadataDriftSummary.fatalCount | Should -Be 0
    }

    It 'tolerates every masked volatile field in one run' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -Language 'PowerShell'),
            (New-TestRepoMeta -Name 'PyTool' -Language 'Python'),
            (New-TestRepoMeta -Name 'WebTool' -Language 'JavaScript')
        )
        $expectedReadme = New-Readme -Catalog $cat -Repos $repos
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos $repos

        $payload = $expectedProjects | ConvertFrom-Json
        $payload.generatedAt = '2020-01-01T00:00:00Z'
        $payload.provenance.sourceCommit = '0000000000000000000000000000000000000000'
        $payload.provenance.metadataSnapshotAt = '2020-01-01T00:00:00Z'
        $payload.provenance.metadataProvider = 'rest-fallback'
        $payload.provenance.repoEnumeration.requestedLimit = 300
        foreach ($project in $payload.projects) {
            foreach ($field in $script:ProjectsFeedVolatileProjectFields) {
                if ($project.PSObject.Properties.Name -contains $field) {
                    $project.$field = $null
                }
            }
        }
        $currentProjects = $payload | ConvertTo-Json -Depth 20

        $result = Test-ProfileState `
            -Catalog $cat `
            -Repos $repos `
            -ExpectedReadme $expectedReadme `
            -ExpectedProjects $expectedProjects `
            -CurrentReadme $expectedReadme `
            -CurrentProjects $currentProjects `
            -SkipLinkValidation

        $result.Report.projectsExportInSync | Should -BeTrue
    }

    It 'treats a case-only difference as out of sync' {
        # PowerShell -eq on strings is case-insensitive. With the -or fallback gone this
        # comparison is the entire verdict, so -eq let a renamed repo, a rewritten title
        # or a changed URL path segment through whenever it differed only in case.
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repos = @((New-TestRepoMeta -Name 'WinTool' -Language 'PowerShell'))
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos $repos

        foreach ($field in @('title', 'id', 'repoUrl')) {
            $payload = $expectedProjects | ConvertFrom-Json
            $original = [string]$payload.projects[0].$field
            $swapped = if ($original -ceq $original.ToUpperInvariant()) { $original.ToLowerInvariant() } else { $original.ToUpperInvariant() }
            $swapped | Should -Not -BeExactly $original -Because "$field must contain letters for this case test to mean anything"
            $payload.projects[0].$field = $swapped
            $current = $payload | ConvertTo-Json -Depth 20

            $comparable = (ConvertTo-ProjectsSyncComparableJson -Json $current) -ceq (ConvertTo-ProjectsSyncComparableJson -Json $expectedProjects)
            $comparable | Should -BeFalse -Because "a case-only change to $field is a real difference"
        }
    }

    It 'compares generated artifacts case-sensitively' {
        $script:SyncProfileScript | Should -Match '\$readmeInSync = .+-ceq'
        $script:SyncProfileScript | Should -Match '\$projectsComparableInSync = .+-ceq'
        $script:SyncProfileScript | Should -Match '\$assetInSync = .+-ceq'
    }

    It 'keeps the equality mask and the drift severity model on one list' {
        # A field tolerated by the mask but treated as fatal by the drift model (or the
        # reverse) is how the two diverged before; assert they read the same source.
        $script:ProjectsFeedVolatileProjectFields | Should -Not -BeNullOrEmpty
        $generator = $script:SyncProfileScript
        $generator | Should -Match '\$infoFields = @\(\$script:ProjectsFeedVolatileProjectFields\)'
        $generator | Should -Not -Match '\$projectsComparableInSync -or'
    }

    It 'fails when a catalog row is excluded from both public feed arrays without a reason' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $localOnly = New-TestEntry -Repo 'LocalOnly' -Category 'misc'
        $localOnly.includeInReadme = $false
        $localOnly.includeInPortfolio = $false
        $cat.entries = @($cat.entries + $localOnly)
        $expectedReadme = New-Readme -Catalog $cat -Repos @()
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @()

        $result = Test-ProfileState `
            -Catalog $cat `
            -Repos @() `
            -ExpectedReadme $expectedReadme `
            -ExpectedProjects $expectedProjects `
            -SkipLinkValidation

        $result.Failed | Should -BeTrue
        $result.Report.catalogFeedAccounting.passed | Should -BeFalse
        $result.Report.catalogFeedAccounting.unaccountedRowCount | Should -Be 1
        $result.Report.catalogFeedAccounting.unaccountedRows[0].catalogId | Should -Be 'catalog-008'
        $result.Report.catalogFeedAccounting.unaccountedRows[0].exportStatus | Should -Be 'unaccounted'
        ($result.Report.catalogFeedAccounting.unaccountedRows | ConvertTo-Json -Depth 20) | Should -Not -Match 'LocalOnly|github.com'
    }
}

Describe 'Profile asset sync gate' {
    It 'checks prospective in-memory SVGs before publication' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedReadme = New-Readme -Catalog $cat -Repos @()
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @()
        $prospectiveAssets = @{
            'assets/profile/prospective.svg' = '<svg><rect width="500" height="200" fill="#161b22"/><text fill="#2a2f37">barely visible</text></svg>'
        }

        $result = Test-ProfileState -Catalog $cat -Repos @() `
            -ExpectedReadme $expectedReadme -ExpectedProjects $expectedProjects `
            -CurrentReadme $expectedReadme -CurrentProjects $expectedProjects `
            -CurrentAssets $prospectiveAssets -ExpectedAssets $prospectiveAssets -SkipLinkValidation

        $result.Report.profileAssetsAccessibility.assetCount | Should -Be 1
        $result.Report.profileAssetsAccessibility.failingAssetCount | Should -Be 1
        $result.Report.profileAssetsAccessibility.contrastRatios[0].asset | Should -Be 'prospective.svg'
    }

    It 'fails the asset gate when a generated asset drifts' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedReadme = New-Readme -Catalog $cat -Repos @()
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @()
        $expectedAssets = @{ 'assets/profile/footer-dark.svg' = '<svg>drifted footer</svg>' }

        $result = Test-ProfileState -Catalog $cat -Repos @() `
            -ExpectedReadme $expectedReadme -ExpectedProjects $expectedProjects `
            -CurrentReadme $expectedReadme -CurrentProjects $expectedProjects `
            -ExpectedAssets $expectedAssets -SkipLinkValidation

        $result.Report.profileAssetsInSync | Should -BeFalse
        $result.Report.artifactDriftDiagnostics.assets.inSync | Should -BeFalse
        $result.Report.artifactDriftDiagnostics.assets.affectedAssetCount | Should -Be 1
        $result.Report.artifactDriftDiagnostics.assets.affectedAssets[0].path | Should -Be 'assets/profile/footer-dark.svg'
        $result.Report.artifactDriftDiagnostics.assets.affectedAssets[0].fatal | Should -BeTrue
        $result.Report.artifactDriftDiagnostics.assets.affectedAssets[0].expectedSha256 | Should -Match '^[a-f0-9]{64}$'
        $result.Report.artifactDriftDiagnostics.assets.affectedAssets[0].remediation | Should -Be 'run-write'
    }

    It 'fails the asset gate when a file the generator does not produce is present' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedReadme = New-Readme -Catalog $cat -Repos @()
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @()
        $stray = '<svg><title>restored heatmap</title></svg>'

        $result = Test-ProfileState -Catalog $cat -Repos @() `
            -ExpectedReadme $expectedReadme -ExpectedProjects $expectedProjects `
            -CurrentReadme $expectedReadme -CurrentProjects $expectedProjects `
            -ExpectedAssets (New-ProfileAssetSvgs) -CurrentAssets @{ 'assets/profile/contributions-dark.svg' = $stray } `
            -SkipLinkValidation

        $result.Report.profileAssetsInSync | Should -BeFalse
        $result.FailureConditions['profileAssetsInSync'] | Should -BeTrue
        $row = @($result.Report.profileAssetChecks | Where-Object { $_.path -eq 'assets/profile/contributions-dark.svg' })
        $row | Should -HaveCount 1
        $row[0].exists | Should -BeTrue
        $row[0].inSync | Should -BeFalse
        $drift = $result.Report.artifactDriftDiagnostics.assets.affectedAssets[0]
        $drift.fatal | Should -BeTrue
        $drift.expectedSha256 | Should -BeNullOrEmpty -Because 'the generator produces no content for a stray file'
        $drift.remediation | Should -Be 'delete-file' -Because '-Write never deletes, so it cannot clear a stray file'
        $drift.currentSha256 | Should -Be (Get-StringSha256 -Text (ConvertTo-NormalizedGeneratedText -Text $stray)) -Because 'the row must describe the stray file, not an empty read'
    }

    It 'finds a stray file on disk under the asset path when no current set is passed' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedReadme = New-Readme -Catalog $cat -Repos @()
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @()
        $strayRoot = Join-Path $TestDrive 'stray-assets'
        New-Item -ItemType Directory -Path (Join-Path $strayRoot 'nested') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $strayRoot 'nested/stats-dark.svg') -Value '<svg/>' -Encoding utf8

        # git commits hidden files and dotfiles, so the scan must see them as well.
        $hidden = Join-Path $strayRoot 'hidden.svg'
        Set-Content -LiteralPath $hidden -Value '<svg/>' -Encoding utf8
        (Get-Item -LiteralPath $hidden -Force).Attributes = [System.IO.FileAttributes]::Hidden
        Set-Content -LiteralPath (Join-Path $strayRoot '.dotfile.svg') -Value '<svg/>' -Encoding utf8

        $onDisk = Get-ProfileAssetFileContents -Path $strayRoot
        $oldAssetsPath = $script:AssetsPath
        try {
            $script:AssetsPath = $strayRoot
            $result = Test-ProfileState -Catalog $cat -Repos @() `
                -ExpectedReadme $expectedReadme -ExpectedProjects $expectedProjects `
                -CurrentReadme $expectedReadme -CurrentProjects $expectedProjects `
                -ExpectedAssets (New-ProfileAssetSvgs) -SkipLinkValidation
        } finally {
            $script:AssetsPath = $oldAssetsPath
        }

        $onDisk.Keys | Should -HaveCount 3
        @($onDisk.Keys | Where-Object { $_ -like '*/stray-assets/nested/stats-dark.svg' }) | Should -HaveCount 1
        @($onDisk.Keys | Where-Object { $_ -like '*/stray-assets/hidden.svg' }) | Should -HaveCount 1
        @($onDisk.Keys | Where-Object { $_ -like '*/stray-assets/.dotfile.svg' }) | Should -HaveCount 1
        $result.Report.profileAssetsInSync | Should -BeFalse
        @($result.Report.profileAssetChecks | Where-Object { $_.path -like '*/nested/stats-dark.svg' }) | Should -HaveCount 1
        @($result.Report.profileAssetChecks) | Should -HaveCount 3
        $result.Report.profileAssetsAccessibility.assetCount | Should -Be 3
    }

    It 'passes the asset gate when the generator produces nothing and the directory is absent' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedReadme = New-Readme -Catalog $cat -Repos @()
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @()
        $oldAssetsPath = $script:AssetsPath
        try {
            $script:AssetsPath = Join-Path $TestDrive 'no-such-assets'
            $result = Test-ProfileState -Catalog $cat -Repos @() `
                -ExpectedReadme $expectedReadme -ExpectedProjects $expectedProjects `
                -CurrentReadme $expectedReadme -CurrentProjects $expectedProjects `
                -ExpectedAssets (New-ProfileAssetSvgs) -SkipLinkValidation
        } finally {
            $script:AssetsPath = $oldAssetsPath
        }

        $result.Report.profileAssetsInSync | Should -BeTrue
        @($result.Report.profileAssetChecks) | Should -HaveCount 0
        $result.Report.profileAssetsAccessibility.assetCount | Should -Be 0
        $budget = @($result.Report.artifactBudgets.rows | Where-Object { $_.artifact -eq 'assets/profile' -and $_.metric -eq 'files' })
        $budget | Should -HaveCount 1
        $budget[0].value | Should -Be 0
    }
}

Describe 'Test-MetadataDrift report' {
    It 'marks live metadata drift informational and branch drift fatal' {
        $current = [ordered]@{
            generatedAt = '2026-06-04T00:00:00Z'
            publicRepoCount = 1
            projectCount = 1
            suppressedCount = 0
            projects = @(
                [ordered]@{
                    repo = 'WinTool'
                    title = 'WinTool'
                    category = 'powershell'
                    includeInReadme = $true
                    includeInPortfolio = $true
                    suppressed = $false
                    suppressionReason = $null
                    description = 'desc'
                    repoUrl = 'https://github.com/SysAdminDoc/WinTool'
                    primaryAction = [ordered]@{ kind = 'repo'; label = 'Repo'; url = 'https://github.com/SysAdminDoc/WinTool' }
                    hasDownload = $false
                    hasLiveDemo = $false
                    hasDirectInstall = $false
                    branch = 'main'
                    stars = 1
                    latestReleaseTag = 'v1.0.0'
                    latestReleaseUrl = 'https://github.com/SysAdminDoc/WinTool/releases/tag/v1.0.0'
                }
            )
            suppressed = @()
        }
        $expected = [ordered]@{
            generatedAt = '2026-06-04T00:00:00Z'
            publicRepoCount = 1
            projectCount = 1
            suppressedCount = 0
            projects = @(
                [ordered]@{
                    repo = 'WinTool'
                    title = 'WinTool'
                    category = 'powershell'
                    includeInReadme = $true
                    includeInPortfolio = $true
                    suppressed = $false
                    suppressionReason = $null
                    description = 'desc'
                    repoUrl = 'https://github.com/SysAdminDoc/WinTool'
                    primaryAction = [ordered]@{ kind = 'repo'; label = 'Repo'; url = 'https://github.com/SysAdminDoc/WinTool' }
                    hasDownload = $false
                    hasLiveDemo = $false
                    hasDirectInstall = $false
                    branch = 'master'
                    stars = 2
                    latestReleaseTag = 'v1.1.0'
                    latestReleaseUrl = 'https://github.com/SysAdminDoc/WinTool/releases/tag/v1.1.0'
                }
            )
            suppressed = @()
        }

        $result = Test-MetadataDrift `
            -CurrentProjectsJson ($current | ConvertTo-Json -Depth 20) `
            -ExpectedProjectsJson ($expected | ConvertTo-Json -Depth 20)

        $branch = @($result.metadataDrift | Where-Object { $_.field -eq 'branch' })
        $branch | Should -HaveCount 1
        $branch[0].severity | Should -Be 'fatal'
        $branch[0].oldValue | Should -Be 'main'
        $branch[0].newValue | Should -Be 'master'

        $release = @($result.metadataDrift | Where-Object { $_.field -eq 'latestReleaseTag' })
        $release | Should -HaveCount 1
        $release[0].severity | Should -Be 'info'

        $stars = @($result.metadataDrift | Where-Object { $_.field -eq 'stars' })
        $stars | Should -HaveCount 1
        $stars[0].severity | Should -Be 'info'

        $result.fatalCount | Should -Be 1
        $result.informationalCount | Should -Be 3
    }

    It 'marks transient release asset inspection loss informational' {
        $baseProject = [ordered]@{
            repo = 'WinTool'
            title = 'WinTool'
            category = 'powershell'
            includeInReadme = $true
            includeInPortfolio = $true
            suppressed = $false
            suppressionReason = $null
            description = 'desc'
            repoUrl = 'https://github.com/SysAdminDoc/WinTool'
            primaryAction = [ordered]@{ kind = 'release'; label = 'Download'; url = 'https://github.com/SysAdminDoc/WinTool/releases/latest' }
            hasDownload = $true
            hasLiveDemo = $false
            hasDirectInstall = $false
            branch = 'main'
            stars = 1
            latestReleaseTag = 'v1.0.0'
            latestReleaseUrl = 'https://github.com/SysAdminDoc/WinTool/releases/tag/v1.0.0'
            releaseAssetKinds = @('exe')
            releaseAssetNames = @('WinTool.exe')
            releaseAssetInspected = $true
            releaseTrust = [ordered]@{
                checksumAssets = @()
                checksumCoverage = 'none'
                hasChecksumForEveryExecutable = $false
                signatureAssets = @()
                hasAuthenticodeSignature = $null
                apkSignatureVerified = $null
                sbomAssets = @()
                attestationAvailable = $false
                debugArtifactPresent = $false
                sourceOnlyRelease = $false
                executableAssetKinds = @('exe')
                trustLevel = 'metadata-only'
                platformDigestCount = 0
                releaseImmutable = $null
                notesPublic = 'Metadata evidence only: derived from release asset filenames and GitHub release API asset digests; binaries were not downloaded or locally verified.'
            }
        }
        $current = [ordered]@{
            generatedAt = '2026-06-04T00:00:00Z'
            publicRepoCount = 1
            projectCount = 1
            suppressedCount = 0
            projects = @($baseProject)
            suppressed = @()
        }
        $expectedProject = $baseProject | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        $expectedProject.primaryAction = [ordered]@{ kind = 'repo'; label = 'Repo'; url = 'https://github.com/SysAdminDoc/WinTool' }
        $expectedProject.hasDownload = $false
        $expectedProject.releaseAssetKinds = @()
        $expectedProject.releaseAssetNames = @()
        $expectedProject.releaseAssetInspected = $false
        $expectedProject.releaseTrust = [ordered]@{
            checksumAssets = @()
            checksumCoverage = 'none'
            hasChecksumForEveryExecutable = $false
            signatureAssets = @()
            hasAuthenticodeSignature = $null
            apkSignatureVerified = $null
            sbomAssets = @()
            attestationAvailable = $false
            debugArtifactPresent = $false
            sourceOnlyRelease = $false
            executableAssetKinds = @()
            trustLevel = 'unknown'
            platformDigestCount = 0
            releaseImmutable = $null
            notesPublic = $null
        }
        $expected = [ordered]@{
            generatedAt = '2026-06-04T00:00:00Z'
            publicRepoCount = 1
            projectCount = 1
            suppressedCount = 0
            projects = @($expectedProject)
            suppressed = @()
        }

        $result = Test-MetadataDrift `
            -CurrentProjectsJson ($current | ConvertTo-Json -Depth 20) `
            -ExpectedProjectsJson ($expected | ConvertTo-Json -Depth 20)

        $result.fatalCount | Should -Be 0
        $result.informationalCount | Should -BeGreaterThan 0
        foreach ($field in @('primaryAction.kind', 'primaryAction.label', 'primaryAction.url', 'hasDownload', 'releaseAssetKinds', 'releaseAssetNames', 'releaseAssetInspected', 'releaseTrust')) {
            $row = @($result.metadataDrift | Where-Object { $_.field -eq $field })
            $row | Should -HaveCount 1
            $row[0].severity | Should -Be 'info'
        }
    }

    It 'warns when the committed projects feed is stale' {
        $payload = [ordered]@{
            generatedAt = '2026-05-01T00:00:00Z'
            publicRepoCount = 0
            projectCount = 0
            suppressedCount = 0
            projects = @()
            suppressed = @()
        }

        $result = Test-MetadataDrift `
            -CurrentProjectsJson ($payload | ConvertTo-Json -Depth 20) `
            -ExpectedProjectsJson ($payload | ConvertTo-Json -Depth 20) `
            -Now ([datetimeoffset]::Parse('2026-06-04T00:00:00Z')) `
            -StaleGeneratedAtDays 7

        $result.generatedAt.stale | Should -BeTrue
        $result.generatedAt.ageDays | Should -BeGreaterThan 33
        $result.generatedAt.warning | Should -Match 'older than 7 days'
        $result.fatalCount | Should -Be 0
    }

    It 'marks stable provenance drift fatal and volatile provenance drift informational' {
        $current = [ordered]@{
            schema = 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/schemas/profile-projects.v1.json'
            generatedAt = '2026-06-04T00:00:00Z'
            source = 'SysAdminDoc/SysAdminDoc data/profile-catalog.json'
            provenance = [ordered]@{
                version = 1
                feedSchemaVersion = 2
                sourceRepository = 'SysAdminDoc/SysAdminDoc'
                sourceCommit = '1111111111111111111111111111111111111111'
                catalogSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                generatorSha256 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
                projectSchemaSha256 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
                metadataSnapshotAt = '2026-06-06T00:00:00Z'
                metadataProvider = 'graphql'
                repoEnumeration = [ordered]@{
                    requestedLimit = 500
                    returnedCount = 1
                    truncated = $false
                }
            }
            publicRepoCount = 1
            projectCount = 0
            suppressedCount = 0
            projects = @()
            suppressed = @()
        }
        $expected = $current | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        $expected.provenance.sourceCommit = '2222222222222222222222222222222222222222'
        $expected.provenance.feedSchemaVersion = 3
        $expected.provenance.catalogSha256 = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
        $expected.provenance.metadataSnapshotAt = '2026-06-06T01:00:00Z'

        $result = Test-MetadataDrift `
            -CurrentProjectsJson ($current | ConvertTo-Json -Depth 20) `
            -ExpectedProjectsJson ($expected | ConvertTo-Json -Depth 20)

        $catalogHash = @($result.metadataDrift | Where-Object { $_.field -eq 'provenance.catalogSha256' })
        $catalogHash | Should -HaveCount 1
        $catalogHash[0].severity | Should -Be 'fatal'

        $feedSchemaVersion = @($result.metadataDrift | Where-Object { $_.field -eq 'provenance.feedSchemaVersion' })
        $feedSchemaVersion | Should -HaveCount 1
        $feedSchemaVersion[0].severity | Should -Be 'fatal'

        $sourceCommit = @($result.metadataDrift | Where-Object { $_.field -eq 'provenance.sourceCommit' })
        $sourceCommit | Should -HaveCount 1
        $sourceCommit[0].severity | Should -Be 'info'

        $snapshot = @($result.metadataDrift | Where-Object { $_.field -eq 'provenance.metadataSnapshotAt' })
        $snapshot | Should -HaveCount 1
        $snapshot[0].severity | Should -Be 'info'

        $result.fatalCount | Should -Be 2
        $result.informationalCount | Should -Be 2
    }
}

Describe 'Report evidence freshness gate' {
    It 'reports fresh evidence when the committed report is newer than the latest commit and smoke ran' {
        $committed = [pscustomobject]@{
            generatedAt = '2026-06-12T10:00:00-04:00'
            renderedProfileSmoke = [pscustomobject]@{ status = 'passed' }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-06-12T09:00:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567'

        $result.status | Should -Be 'fresh'
        $result.committedReportPresent | Should -BeTrue
        $result.reportAgeBehindCommit | Should -BeFalse
        $result.smokeStatus | Should -Be 'passed'
        $result.smokeEvidenceStale | Should -BeFalse
        $result.warningCount | Should -Be 0
        $result.latestReportAffectingCommitSha | Should -Be '0123456789abcdef0123456789abcdef01234567'
        $result.reportAffectingPaths | Should -Not -BeNullOrEmpty
    }

    It 'warns when the committed report predates the latest report-affecting commit' {
        $committed = [pscustomobject]@{
            generatedAt = '2026-06-12T06:21:44-04:00'
            renderedProfileSmoke = [pscustomobject]@{ status = 'passed' }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-06-12T09:22:19-04:00')) `
            -LatestCommitSha 'a61993d612632adcb7047281210add079c326b02'

        $result.status | Should -Be 'stale'
        $result.reportAgeBehindCommit | Should -BeTrue
        $result.reportAgeBehindHours | Should -BeGreaterThan 0
        $result.warningCount | Should -BeGreaterThan 0
        ($result.warnings -join ' ') | Should -Match 'older than the latest report-affecting commit'
    }

    It 'warns when legacy committed rendered-smoke status lacks local source metadata' {
        $committed = [pscustomobject]@{
            generatedAt = '2026-06-12T10:00:00-04:00'
            renderedProfileSmoke = [pscustomobject]@{ status = 'not-run' }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-06-12T09:00:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567'

        $result.status | Should -Be 'stale'
        $result.smokeStatus | Should -Be 'not-run'
        $result.smokeEvidenceStale | Should -BeTrue
        ($result.warnings -join ' ') | Should -Match 'without local source metadata'
    }

    It 'accepts current local not-run smoke evidence without freshness warnings' {
        $committed = [pscustomobject]@{
            generatedAt = '2026-06-12T10:00:00-04:00'
            renderedProfileSmoke = [pscustomobject]@{
                status = 'not-run'
                source = 'missing-local-artifact'
            }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-06-12T09:00:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567'

        $result.status | Should -Be 'fresh'
        $result.smokeStatus | Should -Be 'not-run'
        $result.smokeEvidenceStale | Should -BeFalse
        $result.warningCount | Should -Be 0
    }

    It 'classifies a small report-behind-commit delta as generated-with-commit' {
        $committed = [pscustomobject]@{
            generatedAt = '2026-06-19T00:01:12-04:00'
            renderedProfileSmoke = [pscustomobject]@{ status = 'passed' }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-06-19T00:04:07-04:00')) `
            -LatestCommitSha '2f185dbaef9cb1c6f3ec0115b69c6a943cbcc122'

        $result.status | Should -Be 'generated-with-commit'
        $result.reportAgeBehindCommit | Should -BeTrue
        $result.generatedWithCommit | Should -BeTrue
        $result.sameCommitThresholdMinutes | Should -Be 10
        $result.warningCount | Should -Be 0
    }

    It 'flags a missing committed report as unavailable evidence' {
        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $null `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-06-12T09:00:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567'

        $result.status | Should -Be 'stale'
        $result.committedReportPresent | Should -BeFalse
        $result.smokeStatus | Should -Be 'unavailable'
        ($result.warnings -join ' ') | Should -Match 'was not found'
    }

    It 'flags smoke evidence generated before the latest smoke-affecting commit' {
        # The report restamps its own generatedAt every run while folding in whatever
        # smoke artifact is on disk, so the wrapper always looks fresh. Age the evidence
        # against its own timestamp instead.
        $committed = [pscustomobject]@{
            generatedAt = '2026-09-03T14:34:00-04:00'
            renderedProfileSmoke = [pscustomobject]@{
                status = 'passed'
                source = 'local-artifact'
                generatedAt = '2026-08-20T13:20:52-04:00'
            }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-09-03T14:33:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567' `
            -SmokeAffectingCommitDate ([datetimeoffset]::Parse('2026-09-03T14:12:14-04:00')) `
            -Now ([datetimeoffset]::Parse('2026-09-03T14:34:00-04:00'))

        $result.smokeEvidenceBehindReadme | Should -BeTrue
        $result.smokeEvidenceStale | Should -BeTrue
        $result.status | Should -Be 'stale'
        $result.smokeEvidenceGeneratedAt | Should -Match '^2026-08-20'
        $result.smokeEvidenceAgeHours | Should -BeGreaterThan 300
        ($result.warnings -join ' ') | Should -Match 'predates the latest smoke-affecting commit'
        ($result.warnings -join ' ') | Should -Match 'render-profile-smoke\.ps1'
    }

    It 'accepts smoke evidence generated after the latest smoke-affecting commit' {
        $committed = [pscustomobject]@{
            generatedAt = '2026-09-03T14:34:00-04:00'
            renderedProfileSmoke = [pscustomobject]@{
                status = 'passed'
                source = 'local-artifact'
                generatedAt = '2026-09-03T14:20:00-04:00'
            }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-09-03T14:33:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567' `
            -SmokeAffectingCommitDate ([datetimeoffset]::Parse('2026-09-03T14:12:14-04:00')) `
            -Now ([datetimeoffset]::Parse('2026-09-03T14:34:00-04:00'))

        $result.smokeEvidenceBehindReadme | Should -BeFalse
        $result.smokeEvidenceStale | Should -BeFalse
        $result.smokeEvidenceAgeHours | Should -Be 0.23
        ($result.warnings -join ' ') | Should -Not -Match 'predates the latest smoke-affecting commit'
    }

    It 'cannot age smoke evidence that carries no timestamp' {
        # Legacy reports have no smoke generatedAt; reporting a false age would be worse
        # than reporting none, and the not-run rule still covers the missing-evidence case.
        $committed = [pscustomobject]@{
            generatedAt = '2026-09-03T14:34:00-04:00'
            renderedProfileSmoke = [pscustomobject]@{ status = 'passed' }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-09-03T14:33:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567' `
            -SmokeAffectingCommitDate ([datetimeoffset]::Parse('2026-09-03T14:12:14-04:00')) `
            -Now ([datetimeoffset]::Parse('2026-09-03T14:34:00-04:00'))

        $result.smokeEvidenceGeneratedAt | Should -BeNullOrEmpty
        $result.smokeEvidenceAgeHours | Should -BeNullOrEmpty
        $result.smokeEvidenceBehindReadme | Should -BeFalse
        $result.smokeEvidenceStale | Should -BeFalse
        $result.warningCount | Should -Be 0
    }

    It 'refuses future-dated or unparseable smoke evidence' -ForEach @(
        @{ Case = 'future'; Stamp = '2027-01-01T00:00:00-04:00'; Match = 'dated in the future' }
        @{ Case = 'unparseable'; Stamp = 'not-a-date'; Match = 'unparseable generatedAt' }
    ) {
        # A future stamp made age negative and cleared every staleness signal; an
        # unparseable one was treated as absent while still being published in the report.
        $committed = [pscustomobject]@{
            generatedAt = '2026-09-05T10:00:00-04:00'
            renderedProfileSmoke = [pscustomobject]@{ status = 'passed'; source = 'local-artifact'; generatedAt = $Stamp }
        }

        $result = Test-ReportEvidenceFreshness `
            -CommittedReport $committed `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-09-05T09:00:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567' `
            -SmokeAffectingCommitDate ([datetimeoffset]::Parse('2026-09-05T08:00:00-04:00')) `
            -Now ([datetimeoffset]::Parse('2026-09-05T10:00:00-04:00'))

        $result.smokeEvidenceStale | Should -BeTrue
        $result.status | Should -Be 'stale'
        ($result.warnings -join ' ') | Should -Match $Match
    }

    It 'names the paths that invalidate smoke evidence' {
        $result = Test-ReportEvidenceFreshness `
            -CommittedReport ([pscustomobject]@{ generatedAt = '2026-09-03T14:34:00-04:00'; renderedProfileSmoke = [pscustomobject]@{ status = 'passed' } }) `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-09-03T14:33:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567'

        $result.smokeAffectingPaths | Should -Contain 'README.md'
        $result.smokeAffectingPaths | Should -Contain 'data/profile-catalog.json'
        $result.smokeAffectingPaths | Should -Contain 'scripts/render-profile-smoke.ps1'
    }

    It 'renders a report generated before the smoke-age fields existed' {
        # StrictMode makes a bare property reference on a missing member throw, so the
        # "unknown" fallbacks were unreachable for exactly the archived and rolled-back
        # reports they were written for.
        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        foreach ($field in @('smokeEvidenceGeneratedAt', 'smokeEvidenceAgeHours', 'smokeEvidenceBehindReadme')) {
            $summaryScript | Should -Match "Get-ObjectPropertyOrDefault -Object \`$evidenceFreshness -Name `"$field`""
            $summaryScript | Should -Not -Match "\`$evidenceFreshness\.$field"
        }
    }

    It 'exposes an evidenceFreshness contract in the summary script and report schema' {
        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'evidenceFreshness'
        $summaryScript | Should -Match 'Committed report behind commit'
        $summaryScript | Should -Match 'Committed smoke evidence stale'
        $summaryScript | Should -Match 'render-profile-smoke[.]ps1'

        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $schema.properties.evidenceFreshness.'$ref' | Should -Be '#/$defs/evidenceFreshness'
        $schema.'$defs'.evidenceFreshness.required | Should -Contain 'reportAgeBehindCommit'
        $schema.'$defs'.evidenceFreshness.required | Should -Contain 'smokeEvidenceStale'
        $schema.'$defs'.evidenceFreshness.additionalProperties | Should -BeFalse

        # Field parity: the function output keys must exactly match the schema's
        # additionalProperties:false definition or live report schema validation breaks.
        $sample = Test-ReportEvidenceFreshness `
            -CommittedReport ([pscustomobject]@{ generatedAt = '2026-06-12T10:00:00-04:00'; renderedProfileSmoke = [pscustomobject]@{ status = 'passed' } }) `
            -LatestCommitDate ([datetimeoffset]::Parse('2026-06-12T09:00:00-04:00')) `
            -LatestCommitSha '0123456789abcdef0123456789abcdef01234567'
        $outputKeys = @($sample.Keys) | Sort-Object
        $schemaKeys = @($schema.'$defs'.evidenceFreshness.properties.PSObject.Properties.Name) | Sort-Object
        ($outputKeys -join ',') | Should -Be ($schemaKeys -join ',')
        $schemaRequired = @($schema.'$defs'.evidenceFreshness.required) | Sort-Object
        ($schemaRequired -join ',') | Should -Be ($schemaKeys -join ',')
    }
}

Describe 'Roadmap hygiene gate' {
    It 'flags an open roadmap entry whose marker rule is satisfied' {
        $roadmap = @'
# Roadmap

- [ ] P1 -- Add the widget feature to the catalog
- [ ] P1 -- Add dependency-review-action to PR workflows
'@
        $rules = @(
            [ordered]@{ id = 'widget'; marker = 'Add the widget feature'; satisfied = { $false } },
            [ordered]@{ id = 'dependency-review-action'; marker = 'Add dependency-review-action to PR workflows'; satisfied = { $true } }
        )

        $result = Test-RoadmapHygiene -RoadmapText $roadmap -Rules $rules
        $result.status | Should -Be 'stale-entries'
        $result.roadmapPresent | Should -BeTrue
        $result.shippedEntryCount | Should -Be 1
        $result.warningCount | Should -Be 1
        $result.rows[0].ruleId | Should -Be 'dependency-review-action'
        $result.rows[0].entry | Should -Match 'dependency-review-action'
    }

    It 'reports clean when no satisfied rule matches an open entry' {
        $roadmap = "# Roadmap`n`n- [ ] P2 -- Some unrelated future work"
        $rules = @([ordered]@{ id = 'dependency-review-action'; marker = 'Add dependency-review-action to PR workflows'; satisfied = { $true } })

        $result = Test-RoadmapHygiene -RoadmapText $roadmap -Rules $rules
        $result.status | Should -Be 'clean'
        $result.warningCount | Should -Be 0
    }

    It 'ignores satisfied rules that have no matching open entry' {
        $roadmap = "# Roadmap`n`n- [ ] P2 -- Add dependency-review-action to PR workflows"
        # entry present but rule reports not satisfied -> no warning
        $rules = @([ordered]@{ id = 'dependency-review-action'; marker = 'Add dependency-review-action to PR workflows'; satisfied = { $false } })

        $result = Test-RoadmapHygiene -RoadmapText $roadmap -Rules $rules
        $result.status | Should -Be 'clean'
        $result.warningCount | Should -Be 0
    }

    It 'reports not-present when the roadmap file is absent (CI checkout)' {
        $result = Test-RoadmapHygiene -RoadmapPath (Join-Path $script:RepoRoot 'this-roadmap-does-not-exist.md')
        $result.status | Should -Be 'not-present'
        $result.roadmapPresent | Should -BeFalse
        $result.warningCount | Should -Be 0
    }

    It 'does not mark removed hosted automation tasks as shipped' {
        $rules = Get-RoadmapHygieneRules
        $synthetic = @'
# Roadmap

- [ ] P1 -- Add dependency-review-action to PR workflows
- [ ] P1 -- Upgrade upload-artifact to v7
- [ ] P1 -- Update scorecard-action and dependabot/fetch-metadata SHA pins
- [ ] P1 -- Add Dependabot pip updates for hash-pinned CI tools
'@
        $result = Test-RoadmapHygiene -RoadmapText $synthetic -Rules $rules
        $result.shippedEntryCount | Should -Be 0
        $result.rows | Should -BeNullOrEmpty
    }

    It 'exposes a roadmapHygiene contract in the summary script and report schema' {
        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'roadmapHygiene'
        $summaryScript | Should -Match 'Roadmap hygiene'

        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $schema.properties.roadmapHygiene.'$ref' | Should -Be '#/$defs/roadmapHygiene'

        $sample = Test-RoadmapHygiene -RoadmapText "# Roadmap`n`n- [ ] P2 -- nothing shipped here" -Rules (Get-RoadmapHygieneRules)
        $aggregateKeys = @($sample.Keys) | Sort-Object
        $schemaAggregateKeys = @($schema.'$defs'.roadmapHygiene.properties.PSObject.Properties.Name) | Sort-Object
        ($aggregateKeys -join ',') | Should -Be ($schemaAggregateKeys -join ',')
    }
}

Describe 'GitHub issue form schemas' {
    BeforeAll {
        $script:IssueTemplateDir = Join-Path $script:RepoRoot '.github/ISSUE_TEMPLATE'
        $script:AllowedIssueFieldTypes = @('markdown', 'input', 'textarea', 'dropdown', 'checkboxes')
        # Public-report fields whose required validation guards intake quality.
        $script:RequiredIssueFieldIds = @{
            'broken-link.yml'        = @('project', 'url', 'observed', 'expected', 'surface')
            'profile-correction.yml' = @('project', 'current', 'proposed', 'generated')
            'local-validation.yml'   = @('check', 'observed', 'expected', 'sensitive')
        }

        function Get-IssueFormFields {
            param([string]$Content)

            $fields = New-Object System.Collections.Generic.List[object]
            $current = $null
            foreach ($line in ($Content -split "\r?\n")) {
                $typeMatch = [regex]::Match($line, '^\s*-\s*type:\s*(?<type>\S+)\s*$')
                if ($typeMatch.Success) {
                    if ($null -ne $current) { $fields.Add($current) }
                    $current = [ordered]@{ type = $typeMatch.Groups['type'].Value; id = $null; required = $false; hasOptions = $false }
                    continue
                }
                if ($null -eq $current) { continue }
                $idMatch = [regex]::Match($line, '^\s*id:\s*(?<id>\S+)\s*$')
                if ($idMatch.Success) { $current.id = $idMatch.Groups['id'].Value }
                if ($line -match '^\s*required:\s*true\s*$') { $current.required = $true }
                if ($line -match '^\s*options:\s*$') { $current.hasOptions = $true }
            }
            if ($null -ne $current) { $fields.Add($current) }
            return @($fields.ToArray())
        }

        $script:IssueFormFiles = @(Get-ChildItem -LiteralPath $script:IssueTemplateDir -Filter '*.yml' -File | Where-Object { $_.Name -ne 'config.yml' })
    }

    It 'has the expected issue form set plus a chooser config' {
        @($script:IssueFormFiles.Name | Sort-Object) | Should -Be @('broken-link.yml', 'local-validation.yml', 'profile-correction.yml')
        Test-Path -LiteralPath (Join-Path $script:IssueTemplateDir 'config.yml') | Should -BeTrue
    }

    It 'declares name, description, title, labels, and body on every issue form' {
        foreach ($file in $script:IssueFormFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Match '(?m)^name:\s*\S' -Because "$($file.Name) needs a top-level name"
            $content | Should -Match '(?m)^description:\s*\S' -Because "$($file.Name) needs a top-level description"
            $content | Should -Match '(?m)^title:\s*' -Because "$($file.Name) needs a title prefix"
            $content | Should -Match '(?ms)^labels:\s*\r?\n\s+-\s*\S' -Because "$($file.Name) needs at least one label"
            $content | Should -Match '(?m)^body:\s*$' -Because "$($file.Name) needs a body"
        }
    }

    It 'opens every issue form with a public-safe sensitive-data warning' {
        foreach ($file in $script:IssueFormFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $markdownBlock = [regex]::Match($content, '(?ms)-\s*type:\s*markdown\s*\r?\n\s*attributes:\s*\r?\n\s*value:\s*(?<value>.+?)\s*(\r?\n\s*-\s*type:|\r?\n\S|$)')
            $markdownBlock.Success | Should -BeTrue -Because "$($file.Name) must lead with a markdown notice"
            $markdownBlock.Groups['value'].Value | Should -Match '(?i)(private|secret|sensitive|medical|customer|credential|redact)' -Because "$($file.Name) notice must warn against sensitive data"
        }
    }

    It 'keeps public validation intake local-only' {
        $content = Get-Content -LiteralPath (Join-Path $script:IssueTemplateDir 'local-validation.yml') -Raw

        $content | Should -Match 'scripts/validate-local[.]ps1'
        $content | Should -Match 'scripts/render-profile-smoke[.]ps1'
        $content | Should -Not -Match '(?i)\bCI\b|workflow|generated-profile|actions/runs|OpenSSF Scorecard|Dependabot'
    }

    It 'uses only supported field types and provides dropdown options' {
        foreach ($file in $script:IssueFormFiles) {
            $fields = Get-IssueFormFields -Content (Get-Content -LiteralPath $file.FullName -Raw)
            @($fields).Count | Should -BeGreaterThan 0 -Because "$($file.Name) must declare body fields"
            foreach ($field in $fields) {
                $script:AllowedIssueFieldTypes | Should -Contain $field.type -Because "$($file.Name) uses an unsupported field type '$($field.type)'"
                if ($field.type -eq 'dropdown') {
                    $field.hasOptions | Should -BeTrue -Because "$($file.Name) dropdown '$($field.id)' must list options"
                }
            }
        }
    }

    It 'requires validation on key public-report fields' {
        foreach ($file in $script:IssueFormFiles) {
            $fields = Get-IssueFormFields -Content (Get-Content -LiteralPath $file.FullName -Raw)
            $requiredIds = @($fields | Where-Object { $_.required } | ForEach-Object { $_.id })
            foreach ($expectedId in $script:RequiredIssueFieldIds[$file.Name]) {
                $requiredIds | Should -Contain $expectedId -Because "$($file.Name) field '$expectedId' must require validation"
            }
        }
    }

    It 'routes sensitive reports away from public issues in the chooser config' {
        $config = Get-Content -LiteralPath (Join-Path $script:IssueTemplateDir 'config.yml') -Raw
        $config | Should -Match 'blank_issues_enabled:\s*false'
        $config | Should -Match 'security/policy'
    }
}

Describe 'README image alt-text completeness' {
    It 'reports complete alt text when every image has descriptive alt' {
        $readme = @'
### Featured Projects

<picture>
  <img src="assets/profile/stats-dark.svg" alt="SysAdminDoc public catalog statistics panel" />
</picture>
<img src="assets/profile/footer.svg" alt="Decorative footer wave for the SysAdminDoc profile" />
'@
        $result = Test-ReadmeExperience -Catalog @{ entries = @() } -Repos @() -ExpectedReadme $readme
        $result.imageTagCount | Should -Be 2
        $result.imageAltTextIssueCount | Should -Be 0
        $result.imageAltTextComplete | Should -BeTrue
    }

    It 'flags missing, empty, and generic alt text without failing the gate' {
        $readme = @'
### Featured Projects

<img src="a.svg" alt="A clear description of panel A" />
<img src="b.svg" />
<img src="c.svg" alt="" />
<img src="d.svg" alt="image" />
'@
        $result = Test-ReadmeExperience -Catalog @{ entries = @() } -Repos @() -ExpectedReadme $readme
        $result.imageTagCount | Should -Be 4
        # b.svg (missing), c.svg (empty), d.svg (generic "image") are issues.
        $result.imageAltTextIssueCount | Should -Be 3
        $result.imageAltTextComplete | Should -BeFalse
    }

    It 'requires the alt-text report contract without making it a fatal experience gate' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $checksDef = $schema.'$defs'.readmeExperienceChecks
        $checksDef.properties.PSObject.Properties.Name | Should -Contain 'imageTagCount'
        $checksDef.properties.PSObject.Properties.Name | Should -Contain 'imageAltTextIssueCount'
        $checksDef.properties.PSObject.Properties.Name | Should -Contain 'imageAltTextComplete'
        @($checksDef.required) | Should -Contain 'imageTagCount'
        @($checksDef.required) | Should -Contain 'imageAltTextIssueCount'
        @($checksDef.required) | Should -Contain 'imageAltTextComplete'

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'imageAltTextComplete'
        $summaryScript | Should -Match 'missing descriptive alt text'
    }
}

Describe 'README heading hierarchy' {
    It 'allows a profile README that opens at H3 without flagging the implied H1 skip' {
        $readme = "### Featured Projects`n`nsome text`n`n### Categories`n`nmore text"
        $result = Test-ReadmeHeadingHierarchy -ExpectedReadme $readme
        $result.status | Should -Be 'ok'
        $result.firstLevel | Should -Be 3
        $result.headingCount | Should -Be 2
        $result.profileContextAllowlistApplied | Should -BeTrue
        $result.skippedLevelCount | Should -Be 0
        @($result.headingSequence) | Should -Be @(3, 3)
    }

    It 'flags a skipped heading level during descent' {
        $readme = "### Featured`n`ntext`n`n##### Deep section`n`ntext"
        $result = Test-ReadmeHeadingHierarchy -ExpectedReadme $readme
        $result.status | Should -Be 'warning'
        $result.skippedLevelCount | Should -Be 1
        $result.skippedLevelTransitions[0].from | Should -Be 3
        $result.skippedLevelTransitions[0].to | Should -Be 5
        ($result.warnings -join ' ') | Should -Match 'H3 to H5'
    }

    It 'ignores hash characters inside fenced code blocks' {
        $readme = "### Real heading`n`n``````powershell`n# not a heading`n## also not`n``````"
        $result = Test-ReadmeHeadingHierarchy -ExpectedReadme $readme
        $result.headingCount | Should -Be 1
        $result.skippedLevelCount | Should -Be 0
    }

    It 'flags an over-deep first heading beyond the profile-context allowance' {
        $readme = "##### Too deep to start`n`ntext"
        $result = Test-ReadmeHeadingHierarchy -ExpectedReadme $readme
        $result.profileContextAllowlistApplied | Should -BeFalse
        $result.skippedLevelCount | Should -Be 1
        $result.skippedLevelTransitions[0].context | Should -Be 'document-start'
    }

    It 'exposes a readmeHeadingHierarchy contract in the schema and summary' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $schema.properties.readmeHeadingHierarchy.'$ref' | Should -Be '#/$defs/readmeHeadingHierarchy'

        $sample = Test-ReadmeHeadingHierarchy -ExpectedReadme "### Featured Projects"
        $aggregateKeys = @($sample.Keys) | Sort-Object
        $schemaKeys = @($schema.'$defs'.readmeHeadingHierarchy.properties.PSObject.Properties.Name) | Sort-Object
        ($aggregateKeys -join ',') | Should -Be ($schemaKeys -join ',')

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'README heading hierarchy'
    }
}

Describe 'Root Markdown hygiene' {
    It 'reports clean when only allowed root Markdown files are present' {
        $result = Test-RootMarkdownHygiene -RootMarkdownNames @('README.md', 'ROADMAP.md', 'Roadmap_Blocked.md', 'RESEARCH.md', 'SECURITY.md')
        $result.status | Should -Be 'clean'
        $result.warningCount | Should -Be 0
        @($result.unexpectedFiles) | Should -BeNullOrEmpty
        @($result.allowedFiles) | Should -Contain 'Roadmap_Blocked.md'
    }

    It 'flags root Markdown files outside the documentation contract as warnings' {
        $result = Test-RootMarkdownHygiene -RootMarkdownNames @('README.md', 'TODO.md', 'LOGO_PROMPTS.md', 'RESEARCH_FEATURE_PLAN.md')
        $result.status | Should -Be 'unexpected-files'
        $result.warningCount | Should -Be 3
        @($result.unexpectedFiles) | Should -Contain 'TODO.md'
        @($result.unexpectedFiles) | Should -Contain 'LOGO_PROMPTS.md'
        @($result.unexpectedFiles) | Should -Contain 'RESEARCH_FEATURE_PLAN.md'
    }

    It 'treats explicitly exempted leftovers as non-warning rows' {
        $result = Test-RootMarkdownHygiene -RootMarkdownNames @('README.md', 'TODO.md') -Exemptions @('TODO.md')
        $result.status | Should -Be 'clean'
        $result.warningCount | Should -Be 0
        @($result.exemptFiles) | Should -Contain 'TODO.md'
        ($result.rows | Where-Object { $_.file -eq 'TODO.md' }).status | Should -Be 'exempt'
    }

    It 'exposes a rootMarkdownHygiene contract in the schema and summary' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $schema.properties.rootMarkdownHygiene.'$ref' | Should -Be '#/$defs/rootMarkdownHygiene'

        $sample = Test-RootMarkdownHygiene -RootMarkdownNames @('README.md')
        $aggregateKeys = @($sample.Keys) | Sort-Object
        $schemaKeys = @($schema.'$defs'.rootMarkdownHygiene.properties.PSObject.Properties.Name) | Sort-Object
        ($aggregateKeys -join ',') | Should -Be ($schemaKeys -join ',')

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'Root Markdown hygiene'
    }
}

Describe 'PowerShell version baseline' {
    It 'requires PowerShell 7.4+ for native JSON Schema validation' {
        $script:SyncProfileScript | Should -Match '(?m)^#Requires -Version 7\.4'
        # The JsonSchema.Net engine ships with PowerShell 7.4+ (Test-Json wraps it); the
        # generator calls it directly for per-keyword errors instead of a hand-rolled validator.
        $script:SyncProfileScript | Should -Match 'Add-Type -AssemblyName JsonSchema\.Net'
        $script:SyncProfileScript | Should -Match '\[Json\.Schema\.JsonSchema\]::FromFile\(\$SchemaPath\)'
        $script:SyncProfileScript | Should -Not -Match 'function Test-JsonSchemaNode'
    }

    It 'keeps rendered profile smoke on the sync-profile PowerShell floor' {
        $renderSmokeScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/render-profile-smoke.ps1') -Raw
        $renderSmokeScript | Should -Match '(?m)^#Requires -Version 7\.4'
        $renderSmokeScript | Should -Match 'sync-profile[.]ps1'
    }

    It 'runs the test suite on a supported PowerShell version' {
        $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 7
    }

    It 'keeps the PowerShell baseline local-only without a Tests workflow' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/tests.yml') | Should -BeFalse
        $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 7
        $PSVersionTable.PSVersion.Minor | Should -BeGreaterOrEqual 4
    }

    It 'classifies current PowerShell LTS as preferred runtime' {
        $result = Test-PowerShellRuntimeSecurity `
            -Version ([version]'7.6.5') `
            -Edition 'Core' `
            -NativeJsonSchemaAvailable $true `
            -Now ([datetimeoffset]::Parse('2026-07-06T00:00:00Z'))

        $result.status | Should -Be 'ok'
        $result.current.channel | Should -Be 'current-lts'
        $result.supported | Should -BeTrue
        $result.preferred | Should -BeTrue
        $result.policy.meetsMinimumSecurePatch | Should -BeTrue
        $result.warningCount | Should -Be 0
    }

    It 'warns for an in-support runtime still affected by CVE-2026-50523' {
        $result = Test-PowerShellRuntimeSecurity `
            -Version ([version]'7.6.3') `
            -Edition 'Core' `
            -NativeJsonSchemaAvailable $true `
            -Now ([datetimeoffset]::Parse('2026-08-20T00:00:00Z'))

        $result.status | Should -Be 'warning'
        $result.supported | Should -BeTrue
        $result.policy.meetsMinimumSecurePatch | Should -BeFalse
        ($result.warnings -join ' ') | Should -Match 'CVE-2026-50523'
        ($result.warnings -join ' ') | Should -Match '7\.6\.5'
    }

    It 'applies the CVE-2026-50523 patch floor per release line' {
        $patched75 = Test-PowerShellRuntimeSecurity `
            -Version ([version]'7.5.10') `
            -Edition 'Core' `
            -NativeJsonSchemaAvailable $true `
            -Now ([datetimeoffset]::Parse('2026-08-20T00:00:00Z'))
        $vulnerable75 = Test-PowerShellRuntimeSecurity `
            -Version ([version]'7.5.9') `
            -Edition 'Core' `
            -NativeJsonSchemaAvailable $true `
            -Now ([datetimeoffset]::Parse('2026-08-20T00:00:00Z'))

        $patched75.policy.meetsMinimumSecurePatch | Should -BeTrue
        $vulnerable75.policy.meetsMinimumSecurePatch | Should -BeFalse
        ($vulnerable75.warnings -join ' ') | Should -Match '7\.5\.10'
    }

    It 'warns for PowerShell 7.4 during the transition window' {
        $result = Test-PowerShellRuntimeSecurity `
            -Version ([version]'7.4.17') `
            -Edition 'Core' `
            -NativeJsonSchemaAvailable $true `
            -Now ([datetimeoffset]::Parse('2026-07-06T00:00:00Z'))

        $result.status | Should -Be 'warning'
        $result.current.channel | Should -Be 'previous-lts'
        $result.supported | Should -BeTrue
        $result.preferred | Should -BeFalse
        $result.warnings[0] | Should -Match '2026-11-10'
    }

    It 'fails PowerShell 7.4 after the transition window' {
        $result = Test-PowerShellRuntimeSecurity `
            -Version ([version]'7.4.17') `
            -Edition 'Core' `
            -NativeJsonSchemaAvailable $true `
            -Now ([datetimeoffset]::Parse('2026-11-11T00:00:00Z'))

        $result.status | Should -Be 'fail'
        $result.supported | Should -BeFalse
    }

    It 'marks Windows PowerShell as bootstrap-only for setup.ps1' {
        $result = Test-PowerShellRuntimeSecurity `
            -Version ([version]'5.1.26100') `
            -Edition 'Desktop' `
            -NativeJsonSchemaAvailable $false `
            -Now ([datetimeoffset]::Parse('2026-07-06T00:00:00Z'))

        $result.status | Should -Be 'fail'
        $result.current.channel | Should -Be 'windows-powershell-bootstrap-only'
        $result.capabilities.setupBootstrapOnly | Should -BeTrue
        $result.policy.windowsPowerShellAdvisory | Should -Be 'CVE-2025-54100'
    }
}

Describe 'Profile SVG color contrast' {
    It 'computes the WCAG contrast ratio between two colors' {
        # Black on white is the maximum 21:1.
        Get-ColorContrastRatio -Foreground (ConvertFrom-HexColor '#000000') -Background (ConvertFrom-HexColor '#ffffff') | Should -Be 21
        # Identical colors are 1:1.
        Get-ColorContrastRatio -Foreground (ConvertFrom-HexColor '#161b22') -Background (ConvertFrom-HexColor '#161b22') | Should -Be 1
    }

    It 'expands shorthand hex and rejects invalid hex' {
        $c = ConvertFrom-HexColor '#fff'
        $c.r | Should -Be 255
        $c.g | Should -Be 255
        $c.b | Should -Be 255
        ConvertFrom-HexColor 'not-a-color' | Should -BeNullOrEmpty
    }

    It 'passes a panel whose text colors clear the text minimum against the largest rect' {
        $svg = '<svg><rect width="100%" height="100%" fill="#0d1117"/><rect x="16" y="16" width="788" height="188" fill="#161b22"/><rect x="16" y="16" width="8" height="188" fill="#1f6feb"/><text fill="#c9d1d9">Title</text><text fill="#8b949e">Sub</text></svg>'
        $result = Get-SvgContrastAnalysis -Name 'panel.svg' -Content $svg
        # Largest rect (the panel) is chosen, not the page bg or the 8px accent stripe.
        $result.backgroundColor | Should -Be '#161b22'
        $result.pass | Should -BeTrue
        $result.belowTextMinCount | Should -Be 0
    }

    It 'flags low-contrast text against the panel background' {
        $svg = '<svg><rect width="500" height="200" fill="#161b22"/><text fill="#2a2f37">barely visible</text></svg>'
        $result = Get-SvgContrastAnalysis -Name 'low.svg' -Content $svg
        $result.pass | Should -BeFalse
        $result.belowTextMinCount | Should -BeGreaterThan 0
        $result.textColors[0].meetsTextMin | Should -BeFalse
    }

    It 'reports ok with nothing to check now that no profile SVGs are committed' {
        $result = Test-ProfileAssetsAccessibility
        $result.status | Should -Be 'ok'
        $result.assetCount | Should -Be 0
        $result.failingAssetCount | Should -Be 0
        $result.textMinRatio | Should -Be 4.5
    }

    It 'exposes a profileAssetsAccessibility contract in the schema and summary' {
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $schema.properties.profileAssetsAccessibility.'$ref' | Should -Be '#/$defs/profileAssetsAccessibility'

        $sample = Test-ProfileAssetsAccessibility -AssetContents @{ 'a.svg' = '<svg><rect width="100" height="100" fill="#161b22"/><text fill="#c9d1d9">x</text></svg>' }
        $aggregateKeys = @($sample.Keys) | Sort-Object
        $schemaKeys = @($schema.'$defs'.profileAssetsAccessibility.properties.PSObject.Properties.Name) | Sort-Object
        ($aggregateKeys -join ',') | Should -Be ($schemaKeys -join ',')
        $rowKeys = @($sample.contrastRatios[0].Keys) | Sort-Object
        $schemaRowKeys = @($schema.'$defs'.profileAssetsAccessibility.properties.contrastRatios.items.properties.PSObject.Properties.Name) | Sort-Object
        ($rowKeys -join ',') | Should -Be ($schemaRowKeys -join ',')

        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'Profile SVG contrast'
    }
}

Describe 'Pester local validation command' {
    It 'wires a pinned local validation wrapper instead of a hosted workflow' {
        $testText = Get-Content -LiteralPath $PSCommandPath -Raw
        $validationScriptPath = Join-Path $script:RepoRoot 'scripts/validate-local.ps1'
        $validationScript = Get-Content -LiteralPath $validationScriptPath -Raw

        $testText | Should -Match 'Invoke-Pester -Path tests'
        Test-Path -LiteralPath $validationScriptPath | Should -BeTrue
        $validationScript | Should -Match '-ArgumentList @\("ci"\)'
        $validationScript | Should -Match '-ArgumentList @\("run", "lint:markdown"\)'
        $validationScript | Should -Match 'lint:markdown'
        $validationScript | Should -Match 'scripts/review-local-dependencies[.]ps1'
        $validationScript | Should -Match 'function Invoke-DependencyReview'
        $validationScript | Should -Match 'Invoke-DependencyReview -RepoRoot \$repoRoot'
        $validationScript | Should -Match 'Dependency review failed with exit code'
        $validationScript | Should -Match 'Dependency review: \{0\}; npm audit: \{1\}; signatures: \{2\}; pin freshness: \{3\}'
        $validationScript | Should -Match 'Pester"; Version = "5\.9\.1"'
        $validationScript | Should -Match 'PSScriptAnalyzer"; Version = "1\.25\.0"'
        $validationScript | Should -Match 'Invoke-ScriptAnalyzer'
        $validationScript | Should -Match 'Invoke-Pester -Configuration'
        $validationScript | Should -Match 'CodeCoverage\.Enabled = \$true'
        $validationScript | Should -Match 'OutputFormat = "JaCoCo"'
        $validationScript | Should -Match 'SupportBundlePath'
        $validationScript | Should -Match 'New-LocalSupportBundle'
        $validationScript | Should -Match 'Pester6Compatibility'
        $validationScript | Should -Match 'function Invoke-Pester6Compatibility'
        $validationScript | Should -Match 'Save-Module'
        $validationScript | Should -Match 'PSModulePath'
        $validationScript | Should -Match 'ExcludeTag Integration'
        $validationScript | Should -Match 'Pester6CompatibilityVersion'
        $contributing = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/CONTRIBUTING.md') -Raw
        $contributing | Should -Match 'Pester 6 compatibility lane'
        $contributing | Should -Match 'validate-local[.]ps1 -Pester6Compatibility'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'scripts/new-support-bundle.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/tests.yml') | Should -BeFalse
    }
}

Describe 'Report section enforcement declarations' {
    BeforeAll {
        $script:EnforcementSchema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $conditionBlock = [regex]::Match($script:SyncProfileScript, '(?s)\$failureConditions = \[ordered\]@\{(?<body>.*?)\n    \}')
        $script:EnforcementFailureConditions = @([regex]::Matches($conditionBlock.Groups['body'].Value, '(?m)^\s{8}(?<name>[A-Za-z][A-Za-z0-9]*)\s*=') |
            ForEach-Object { $_.Groups['name'].Value })
    }

    It 'declares an enforcement for every report section and for nothing else' {
        # The report schema's required list is the full set of top-level sections,
        # sectionEnforcement included.
        $sections = @($script:EnforcementSchema.required | Sort-Object)
        $declared = @($script:ReportSectionEnforcement.Keys | Sort-Object)

        $sections.Count | Should -BeGreaterThan 50
        @($sections | Where-Object { $_ -notin $declared }) | Should -BeNullOrEmpty -Because 'every section needs an explicit enforcement'
        @($declared | Where-Object { $_ -notin $sections }) | Should -BeNullOrEmpty -Because 'a declaration must name a real section'
        foreach ($section in $declared) {
            $declaration = $script:ReportSectionEnforcement[$section]
            $declaration.enforcement | Should -BeIn @('blocking', 'advisory-by-policy', 'advisory-pending-decision') -Because $section
            if ($declaration.enforcement -eq 'blocking') {
                $declaration.failureCondition | Should -BeIn $script:EnforcementFailureConditions -Because "$section must name the failure condition that makes it blocking"
            } else {
                [string]$declaration.reason | Should -Not -BeNullOrEmpty -Because "advisory section $section must say why it cannot fail a run"
            }
        }
    }

    It 'ties every blocking failure condition to exactly one blocking section' {
        $script:EnforcementFailureConditions.Count | Should -BeGreaterThan 15
        foreach ($condition in $script:EnforcementFailureConditions) {
            $owners = @($script:ReportSectionEnforcement.Keys | Where-Object {
                    $script:ReportSectionEnforcement[$_].enforcement -eq 'blocking' -and
                    $script:ReportSectionEnforcement[$_].failureCondition -eq $condition
                })
            $owners | Should -HaveCount 1 -Because "failure condition $condition"
        }
    }

    It 'records undeclared sections so the report schema rejects them' {
        $result = New-ReportSectionEnforcement -Sections @('readmeInSync', 'userscriptInstallTrust', 'brandNewSection')

        $result.sections['readmeInSync'] | Should -Be 'blocking'
        $result.sections['brandNewSection'] | Should -Be 'undeclared'
        @($result.pendingDecisions) | Should -HaveCount 1
        $result.pendingDecisions[0].section | Should -Be 'userscriptInstallTrust'
        $result.pendingDecisions[0].question | Should -Match '\?$'
        $allowed = @($script:EnforcementSchema.'$defs'.sectionEnforcement.properties.sections.additionalProperties.enum)
        $allowed | Should -Be @('blocking', 'advisory-by-policy', 'advisory-pending-decision')
        $allowed | Should -Not -Contain 'undeclared'
    }

    It 'fails the report schema when a section is recorded as undeclared' {
        $report = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw)
        $sections = Get-MemberValue -Object (Get-MemberValue -Object $report -Name 'sectionEnforcement') -Name 'sections'
        Set-MemberValue -Object $sections -Name 'brandNewSection' -Value 'undeclared'

        $result = Test-JsonSchemaContract -Value $report -SchemaPath 'schemas/profile-sync-report.v1.json'

        $result.valid | Should -BeFalse -Because 'schemaValidation is blocking, so this is what fails the run'
        $failure = @($result.errors | Where-Object { $_.instanceLocation -eq '/sectionEnforcement/sections/brandNewSection' })
        $failure | Should -HaveCount 1
        $failure[0].keywordLocation | Should -BeLike '*/sections/additionalProperties/enum'
    }

    It 'publishes the declarations in the committed report' {
        $report = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw | ConvertFrom-Json
        $reportSections = @($report.PSObject.Properties.Name | Sort-Object)
        $published = @($report.sectionEnforcement.sections.PSObject.Properties.Name | Sort-Object)

        $published | Should -Be $reportSections
        @($report.sectionEnforcement.sections.PSObject.Properties.Value) | Should -Not -Contain 'undeclared'
        $pending = @($script:ReportSectionEnforcement.Keys | Where-Object { $script:ReportSectionEnforcement[$_].enforcement -eq 'advisory-pending-decision' })
        @($report.sectionEnforcement.pendingDecisions | ForEach-Object section) | Should -Be $pending
    }
}

Describe 'Failure condition reachability coverage' {
    # Cheap guard in the default lane: a new blocking condition cannot ship without
    # either a reachability case or an explicit, reasoned exemption. The cases
    # themselves are Integration-tagged because each costs 8-50s of live metadata.
    BeforeAll {
        # Conditions that cannot be planted yet, each with the reason. Empty: every blocking
        # condition has a case. A new condition needs a case or a reasoned entry here.
        $script:ReachabilityExemptions = [ordered]@{}
    }

    It 'has a reachability case or a reasoned exemption for every blocking condition' {
        $generator = $script:SyncProfileScript
        $block = [regex]::Match($generator, '(?s)\$failureConditions = \[ordered\]@\{(?<body>.*?)\n    \}')
        $block.Success | Should -BeTrue -Because 'the failure condition block must be discoverable'
        $conditions = @([regex]::Matches($block.Groups['body'].Value, '(?m)^\s{8}(?<name>[A-Za-z][A-Za-z0-9]*)\s*=') |
            ForEach-Object { $_.Groups['name'].Value })
        $conditions.Count | Should -BeGreaterThan 15

        $tests = Get-Content -LiteralPath $PSCommandPath -Raw
        $uncovered = New-Object System.Collections.Generic.List[string]
        foreach ($condition in $conditions) {
            $hasCase = $tests -match [regex]::Escape("-Condition '$condition'") -or
                $tests -match [regex]::Escape("FailureConditions['$condition']")
            if (-not $hasCase -and -not $script:ReachabilityExemptions.Contains($condition)) {
                $uncovered.Add($condition)
            }
        }

        $uncovered | Should -BeNullOrEmpty -Because "each blocking condition needs a reachability case or an exemption: $($uncovered -join ', ')"
    }

    It 'keeps every exemption pointed at a real condition with a stated reason' {
        # A stale exemption would silently excuse a condition that is now plantable.
        $generator = $script:SyncProfileScript
        $block = [regex]::Match($generator, '(?s)\$failureConditions = \[ordered\]@\{(?<body>.*?)\n    \}')
        $conditions = @([regex]::Matches($block.Groups['body'].Value, '(?m)^\s{8}(?<name>[A-Za-z][A-Za-z0-9]*)\s*=') |
            ForEach-Object { $_.Groups['name'].Value })

        foreach ($exempt in @($script:ReachabilityExemptions.Keys)) {
            $conditions | Should -Contain $exempt -Because "exemption '$exempt' no longer matches a blocking condition"
            [string]$script:ReachabilityExemptions[$exempt] | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Every blocking failure condition can be made to fire' -Tag 'Integration' {
    # A gate nobody has ever seen fail is not evidence. Each case plants the smallest
    # realistic violation and asserts that its own condition goes true, that the run
    # fails, and that no unrelated condition flipped. Tagged Integration because each
    # Test-ProfileState call builds a full report; the cheap guard test below runs in the
    # default lane and refuses a condition with no case here.
    BeforeAll {
        $script:ReachabilityCatalogPath = Join-Path $PSScriptRoot 'fixtures/catalog.json'
        # The portfolio feed contract needs at least one release action, which only live
        # release metadata produces; with it the untouched fixture passes every gate.
        $script:ReachabilityRepos = @((New-TestRepoMeta -Name 'ReleaseTool' -WithRelease -AssetNames @('ReleaseTool.zip')))

        function script:New-ReachabilityBaseline {
            param([hashtable]$Catalog, [object[]]$Repos = $script:ReachabilityRepos)
            $expectedReadme = New-Readme -Catalog $Catalog -Repos $Repos
            $expectedProjects = New-ProjectsExportJson -Catalog $Catalog -Repos $Repos
            $expectedAssets = New-ProfileAssetSvgs
            [ordered]@{
                Catalog = $Catalog
                Repos = $Repos
                ExpectedReadme = $expectedReadme
                ExpectedProjects = $expectedProjects
                ExpectedAssets = $expectedAssets
            }
        }

        function script:Invoke-ReachabilityState {
            param([hashtable]$Baseline, [hashtable]$Override = @{})
            $parameters = @{
                Catalog = $Baseline.Catalog
                Repos = $Baseline.Repos
                ExpectedReadme = $Baseline.ExpectedReadme
                ExpectedProjects = $Baseline.ExpectedProjects
                ExpectedAssets = $Baseline.ExpectedAssets
                CurrentReadme = $Baseline.ExpectedReadme
                CurrentProjects = $Baseline.ExpectedProjects
                CurrentAssets = $Baseline.ExpectedAssets
                SkipLinkValidation = $true
                # A missing smoke artifact, so a local rendered-smoke run cannot change the result.
                SmokeReportPath = (Join-Path $TestDrive 'no-smoke-run.json')
            }
            foreach ($key in $Override.Keys) { $parameters[$key] = $Override[$key] }
            Test-ProfileState @parameters
        }

        function script:Get-FiredConditions {
            param([object]$Result)
            @($Result.FailureConditions.GetEnumerator() | Where-Object { [bool]$_.Value } | ForEach-Object { [string]$_.Key })
        }

        # The offline fixture cannot satisfy every check: with no live repository
        # metadata some conditions are already true before anything is planted. Compare
        # against that measured baseline rather than against an empty set, so a case
        # still proves its own condition newly fired and nothing else did.
        $script:ReachabilityBaselineFired = @()

        function script:Assert-ConditionNewlyFired {
            # -AlsoFires names conditions the plant fires by its nature (a duplicate catalog
            # row is also a duplicate feed row); they must fire too, so the list stays exact.
            param([object]$Result, [string]$Condition, [string[]]$AlsoFires = @())
            $Result.Failed | Should -BeTrue -Because "planting a $Condition violation must fail the run"
            [bool]$Result.FailureConditions[$Condition] | Should -BeTrue -Because "$Condition must report the violation it exists to catch"
            $script:ReachabilityBaselineFired | Should -Not -Contain $Condition -Because "$Condition must be green before the plant, or the case proves nothing"
            foreach ($expected in $AlsoFires) {
                [bool]$Result.FailureConditions[$expected] | Should -BeTrue -Because "planting $Condition is expected to fire $expected as well"
            }
            $unexpected = @(script:Get-FiredConditions -Result $Result |
                Where-Object { $_ -ne $Condition -and $_ -notin $AlsoFires -and $_ -notin $script:ReachabilityBaselineFired })
            $unexpected | Should -BeNullOrEmpty -Because "planting $Condition must not flip anything else; also fired: $($unexpected -join ', ')"
        }

        # The runtime check reflects the PowerShell running the suite, so an older host past
        # its support window would start every case red. Pin it to a supported version and
        # date; the runtimeSecurity case feeds the same real check an unsupported one.
        $script:RealRuntimeSecurity = ${function:Test-PowerShellRuntimeSecurity}
        Mock Test-PowerShellRuntimeSecurity { & $script:RealRuntimeSecurity -Version ([version]'7.6.6') -Now ([datetimeoffset]'2026-09-23T00:00:00Z') }

        $script:ReachabilityBaseline = script:New-ReachabilityBaseline -Catalog (Get-Catalog -Path $script:ReachabilityCatalogPath)
        $script:ReachabilityBaselineFired = @(script:Get-FiredConditions -Result (script:Invoke-ReachabilityState -Baseline $script:ReachabilityBaseline))
    }

    It 'starts every case from a baseline where no condition fires' {
        # The control. Without it a case could "pass" because the baseline was already
        # failing for an unrelated reason, so each case below has to take its own condition
        # from false to true and flip nothing else.
        $script:ReachabilityBaselineFired | Should -BeNullOrEmpty
    }

    It 'fires readmeInSync when the published README drifts' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ CurrentReadme = "# drifted profile`n" }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'readmeInSync'
    }

    It 'fires projectsExportInSync when the feed drifts outside the volatile mask' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        $payload = $baseline.ExpectedProjects | ConvertFrom-Json
        $payload.schemaPolicy.currentVersion = 99

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{
            CurrentProjects = ($payload | ConvertTo-Json -Depth 20)
        }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'projectsExportInSync'
    }

    It 'fires profileAssetsInSync when a file the generator does not produce is present' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        $current = @{ 'assets/profile/header-dark.svg' = '<svg><title>restored</title></svg>' }

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ CurrentAssets = $current }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'profileAssetsInSync'
    }

    It 'fires catalogShape on a duplicate catalog row' {
        # Removing a required field crashes generation before the gate is reached, so
        # the plant has to be a violation the generator can still render past.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $duplicate = New-TestEntry -Repo ([string]$catalog.entries[0].repo) -Category ([string]$catalog.entries[0].category)
        $catalog.entries = @($catalog.entries + $duplicate)
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        # A duplicate catalog row is also a duplicate feed row: same repo name, same id.
        script:Assert-ConditionNewlyFired -Result $result -Condition 'catalogShape' -AlsoFires @('portfolioCompatibility', 'stableEntityIds')
        @($result.Report.catalogShape.issues | Where-Object { $_.reason -match 'duplicate' }).Count | Should -BeGreaterThan 0
    }

    It 'fires catalogShape on a liveUrl that plants a README table row' {
        # The plant from the review of e13349f, which fired nothing at the time.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $web = @($catalog.entries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.liveUrl) })[0]
        $web.liveUrl = [string]$web.liveUrl + "`n| [**Injected**](https://evil.example/) | planted row | x |"
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        # The catalog schema's URL pattern refuses the same value.
        script:Assert-ConditionNewlyFired -Result $result -Condition 'catalogShape' -AlsoFires @('schemaValidation')
        @($result.Report.catalogShape.issues | Where-Object { $_.field -eq 'liveUrl' }) | Should -HaveCount 1
        @($result.Report.schemaValidation.catalog.errors | Where-Object { $_.instanceLocation -like '/entries/*/liveUrl' }) | Should -HaveCount 1
    }

    It 'fires catalogShape alone on a title with a bidi override' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $catalog.entries[0].title = 'Win' + [char]0x202E + 'Tool'
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'catalogShape'
        @($result.Report.catalogShape.issues | Where-Object { $_.value -eq 'U+202E' }).Count | Should -Be 1
    }

    It 'fires missingPublic when a live repo has no catalog row' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $repos = @($script:ReachabilityRepos + (New-TestRepoMeta -Name 'UncatalogedTool' -Language 'PowerShell'))
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog -Repos $repos

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'missingPublic'
        @($result.Report.missingPublicRepos).Count | Should -BeGreaterThan 0
    }

    It 'fires urlSchemeViolations on a plaintext catalog URL' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $catalog.entries[0].liveUrl = 'http://insecure.example/demo'
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'urlSchemeViolations'
    }

    It 'fires orphanedSuppressed when a suppressed row states no reason' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $orphan = New-TestEntry -Repo 'SuppressedNoReason' -Category 'suppressed'
        $orphan.suppressionReason = $null
        $catalog.entries = @($catalog.entries + $orphan)
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'orphanedSuppressed'
    }

    It 'fires linkFailures on a dead local anchor with no network access' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        # Local fragments are resolved without probing, so this fires even with
        # link validation skipped. The dead link goes at the end of the header, just above
        # the generated-catalog notice: above the tagline it would break the header contract
        # too, and below the notice the header check does not look.
        $planted = $baseline.ExpectedReadme.Replace($GeneratedCatalogNotice, '<p align="center"><a href="#section-that-does-not-exist">Go</a></p>' + "`n`n" + $GeneratedCatalogNotice)
        $planted | Should -Not -Be $baseline.ExpectedReadme

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{
            ExpectedReadme = $planted
            CurrentReadme = $planted
        }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'linkFailures'
        @($result.Report.linkValidationFailures | Where-Object { $_.type -eq 'readme-header-anchor' }).Count |
            Should -BeGreaterThan 0
    }

    It 'fires catalogFeedAccounting when a row leaves both public arrays unexplained' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $localOnly = New-TestEntry -Repo 'AccountingGap' -Category 'misc'
        $localOnly.includeInReadme = $false
        $localOnly.includeInPortfolio = $false
        $catalog.entries = @($catalog.entries + $localOnly)
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'catalogFeedAccounting'
    }

    It 'fires readmeExperience when the header contract breaks' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        $broken = [regex]::Replace($baseline.ExpectedReadme, '^(\s*<p align="center"><b>)[^<]+', '${1}Something Else Entirely.')
        $broken | Should -Not -Be $baseline.ExpectedReadme

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{
            ExpectedReadme = $broken
            CurrentReadme = $broken
        }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'readmeExperience'
    }

    It 'fires medicalViolations on an unflagged medical-imaging row' {
        # Two things this plant has to get right. The medical check only runs for
        # entries that resolve to live repository metadata, so the row needs a matching
        # repo. And $MedicalPattern is word-bounded: "DicomBridge" does not match
        # because a word character follows the keyword, while "Dicom-Bridge" does.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $medical = New-TestEntry -Repo 'Dicom-Bridge' -Category 'desktop'
        $medical.allowPublicMedical = $false
        $catalog.entries = @($catalog.entries + $medical)
        $repos = @($script:ReachabilityRepos + (New-TestRepoMeta -Name 'Dicom-Bridge' -Language 'C#'))
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog -Repos $repos

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'medicalViolations'
        @($result.Report.medicalPrivacyViolations | Where-Object { $_.repo -eq 'Dicom-Bridge' }).Count | Should -Be 1
    }

    It 'fires metadataDrift on a fatal feed field' {
        # Changing a fatal drift field also desyncs the feed, so both conditions are
        # expected here; the point is that metadataDrift is one of them.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        $payload = $baseline.ExpectedProjects | ConvertFrom-Json
        $payload.publicRepoCount = [int]$payload.publicRepoCount + 41

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{
            CurrentProjects = ($payload | ConvertTo-Json -Depth 20)
        }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'metadataDrift' -AlsoFires @('projectsExportInSync')
        $result.Report.metadataDriftSummary.fatalCount | Should -BeGreaterThan 0
    }

    It 'fires privateViolations when a cataloged repo turns private' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $private = New-TestRepoMeta -Name 'WinTool'
        $private.visibility = 'PRIVATE'
        $private.isPrivate = $true
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog -Repos @($script:ReachabilityRepos + $private)

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'privateViolations'
        @($result.Report.privateVisibilityViolations | Where-Object { $_.repo -eq 'WinTool' }).Count | Should -Be 1
    }

    It 'fires privateViolations when a repo''s visibility only looks public' {
        # The gate compared with -ne, by culture, so PUBLIC with a zero-width space passed it.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $hidden = New-TestRepoMeta -Name 'WinTool'
        $hidden.visibility = 'PUB' + [char]0x200B + 'LIC'
        $hidden.isPrivate = $false
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog -Repos @($script:ReachabilityRepos + $hidden)

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'privateViolations'
        @($result.Report.privateVisibilityViolations | Where-Object { $_.repo -eq 'WinTool' }).Count | Should -Be 1
    }

    It 'fires redirects when a cataloged repo answers under a new name' {
        # Online, a visible row missing from the live repo list is looked up with gh repo view.
        # Every other visible row gets metadata, so WinTool is the only lookup, and the stub
        # answers it under a new name. Every other gh call fails, as it would unauthenticated.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $visible = @($catalog.entries | Where-Object { $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })
        $repos = @($visible | Where-Object { $_.repo -ne 'WinTool' } | ForEach-Object {
            if ($_.repo -eq 'ReleaseTool') { $script:ReachabilityRepos[0] } else { New-TestRepoMeta -Name ([string]$_.repo) }
        })
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog -Repos $repos
        Mock Invoke-GhCli {
            if ($Arguments[0] -eq 'repo' -and $Arguments[1] -eq 'view') {
                $view = '{"name":"WinToolRenamed","url":"https://github.com/SysAdminDoc/WinToolRenamed","visibility":"PUBLIC"}'
                return [ordered]@{ output = $view; exitCode = 0; text = $view }
            }
            return [ordered]@{ output = 'gh unavailable in this test'; exitCode = 1; text = 'gh unavailable in this test' }
        }

        $savedOffline = $script:Offline
        $script:Offline = $false
        try {
            $result = script:Invoke-ReachabilityState -Baseline $baseline
        } finally {
            $script:Offline = $savedOffline
        }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'redirects'
        @($result.Report.renamedRepoRedirects | Where-Object { $_.repo -eq 'WinTool' -and $_.canonical -eq 'WinToolRenamed' }).Count | Should -Be 1
    }

    It 'fires communityHealth when a required community file is missing' {
        $script:CommunityFilesWithoutSecurity = @(Get-CommunityLocalFileStatus | ForEach-Object {
            $row = [ordered]@{ path = $_.path; required = $_.required; exists = $_.exists }
            if ($row.path -eq 'SECURITY.md') { $row.exists = $false }
            $row
        })
        Mock Get-CommunityLocalFileStatus { $script:CommunityFilesWithoutSecurity }
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'communityHealth'
    }

    It 'fires portfolioCompatibility when the feed miscounts its own projects' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        $payload = $baseline.ExpectedProjects | ConvertFrom-Json
        $payload.projectCount = [int]$payload.projectCount + 1
        $planted = $payload | ConvertTo-Json -Depth 30

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ ExpectedProjects = $planted; CurrentProjects = $planted }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'portfolioCompatibility'
    }

    It 'fires stableEntityIds when two feed rows share an id' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        $payload = $baseline.ExpectedProjects | ConvertFrom-Json
        $payload.projects[1].id = $payload.projects[0].id
        $planted = $payload | ConvertTo-Json -Depth 30

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ ExpectedProjects = $planted; CurrentProjects = $planted }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'stableEntityIds'
    }

    It 'fires feedSchemaMigration when the supported versions leave out the current one' {
        # The schema already refuses a breaking change without a migration note, so the
        # plant has to be a policy the schema accepts: a supported window that no longer
        # includes the version the feed is written in.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        $payload = $baseline.ExpectedProjects | ConvertFrom-Json
        $payload.schemaPolicy.supportedVersions = @([int]$payload.schemaPolicy.currentVersion + 1)
        $planted = $payload | ConvertTo-Json -Depth 30

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ ExpectedProjects = $planted; CurrentProjects = $planted }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'feedSchemaMigration'
    }

    It 'fires schemaValidation on a feed field the schema does not allow' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog
        $payload = $baseline.ExpectedProjects | ConvertFrom-Json
        $payload | Add-Member -NotePropertyName 'undeclaredField' -NotePropertyValue 'not in the contract'
        $planted = $payload | ConvertTo-Json -Depth 30

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ ExpectedProjects = $planted; CurrentProjects = $planted }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'schemaValidation'
        @($result.Report.schemaValidation.projects.errors | Where-Object { $_.instanceLocation -eq '/undeclaredField' }).Count | Should -Be 1
    }

    It 'fires docVersionConsistency on a malformed profile version' {
        $versionPath = Join-Path $TestDrive 'profile-version.json'
        $version = Get-Content -LiteralPath $script:ProfileVersionPath -Raw | ConvertFrom-Json
        $version.version = 'v4.10'
        $version | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $versionPath -Encoding utf8
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $savedVersionPath = $script:ProfileVersionPath
        $script:ProfileVersionPath = $versionPath
        try {
            $result = script:Invoke-ReachabilityState -Baseline $baseline
        } finally {
            $script:ProfileVersionPath = $savedVersionPath
        }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'docVersionConsistency'
    }

    It 'fires runtimeSecurity on a PowerShell below the generator floor' {
        # The real check (captured before the Describe-level pin), fed an unsupported version.
        Mock Test-PowerShellRuntimeSecurity { & $script:RealRuntimeSecurity -Version ([version]'7.2.0') -Now ([datetimeoffset]'2026-09-23T00:00:00Z') }
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        script:Assert-ConditionNewlyFired -Result $result -Condition 'runtimeSecurity'
        $result.Report.runtimeSecurity.status | Should -Be 'fail'
    }

    It 'fires releaseArtifactVerification on a release asset that fails its checksum' {
        # Downloads are the seam: the real verifier runs, fed bytes that disagree with the
        # published SHA-256.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $release = New-TestRepoMeta -Name 'ReleaseTool' -WithRelease -AssetNames @('ReleaseTool.zip', 'SHA256SUMS')
        Set-MemberValue -Object $release.latestRelease -Name 'releaseAssets' -Value @(
            [pscustomobject]@{ name = 'ReleaseTool.zip'; browserDownloadUrl = 'https://github.com/SysAdminDoc/ReleaseTool/releases/download/v1.0.0/ReleaseTool.zip'; size = 15 },
            [pscustomobject]@{ name = 'SHA256SUMS'; browserDownloadUrl = 'https://github.com/SysAdminDoc/ReleaseTool/releases/download/v1.0.0/SHA256SUMS'; size = 90 }
        )
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog -Repos @($release)
        Mock Get-ReleaseArtifactDownload {
            if ($Url -like '*SHA256SUMS') {
                $text = ('0' * 64) + '  ReleaseTool.zip'
                return [ordered]@{ ok = $true; bytes = [System.Text.Encoding]::UTF8.GetBytes($text); text = $text; error = $null; bytesRead = $text.Length }
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('release payload')
            [ordered]@{ ok = $true; bytes = $bytes; text = $null; error = $null; bytesRead = $bytes.Length }
        }

        $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ VerifyReleaseArtifacts = $true }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'releaseArtifactVerification'
        $result.Report.releaseArtifactVerification.failureCount | Should -Be 1
        Should -Invoke Get-ReleaseArtifactDownload -Times 2 -Exactly
    }

    It 'fires schemaValidation when only the report breaks its schema' {
        # The other schemaValidation case breaks the feed. This one leaves catalog and feed
        # valid and points the report check at a copy of its schema that demands one more
        # field, so only the report half of schemaValidation can fail.
        $schema = Get-Content -LiteralPath $script:ReportSchemaPath -Raw | ConvertFrom-Json -AsHashtable
        $schema['$id'] = 'https://example.test/schemas/profile-sync-report.planted.json'
        $schema['required'] = @($schema['required']) + 'fieldThatNoReportHas'
        $plantedSchemaPath = Join-Path $TestDrive 'profile-sync-report.planted.json'
        $schema | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $plantedSchemaPath -Encoding utf8
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        $savedSchemaPath = $script:ReportSchemaPath
        $script:ReportSchemaPath = $plantedSchemaPath
        try {
            $result = script:Invoke-ReachabilityState -Baseline $baseline
        } finally {
            $script:ReportSchemaPath = $savedSchemaPath
        }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'schemaValidation'
        $result.Report.schemaValidation.projects.valid | Should -BeTrue
        $result.Report.schemaValidation.report.valid | Should -BeFalse
    }

    It 'fires linkFailures when a live link probe reports a dead target' {
        # Probes run in parallel runspaces a mock cannot reach, so the seam is Test-LinkTargets.
        # It answers with one fatal failure, which proves live probe failures, not only dead
        # anchors, reach the condition. Every visible row has metadata so no gh lookup runs,
        # gh itself fails, and userscript trust stays in its skip mode.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $visible = @($catalog.entries | Where-Object { $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })
        $repos = @($visible | ForEach-Object {
            if ($_.repo -eq 'ReleaseTool') { $script:ReachabilityRepos[0] } else { New-TestRepoMeta -Name ([string]$_.repo) }
        })
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog -Repos $repos
        $script:RealUserscriptTrust = ${function:Test-UserscriptInstallTrust}
        Mock Test-UserscriptInstallTrust { & $script:RealUserscriptTrust -Entries $Entries -Skip }
        Mock Invoke-GhCli { [ordered]@{ output = 'gh unavailable in this test'; exitCode = 1; text = 'gh unavailable in this test' } }
        Mock Test-LinkTargets {
            [ordered]@{
                failures = @([ordered]@{ repo = 'WinTool'; type = 'repo'; url = 'https://github.com/SysAdminDoc/WinTool'; host = 'github.com'; status = 404; error = 'HTTP 404' })
                warnings = @()
                targetCount = 1
                liveProbedCount = 1
                cacheServedCount = 0
                oldestCacheEntryAgeHours = $null
                allResultsFromCache = $false
                throttleLimit = 1
                elapsedMs = 0
                warningCountByHost = @()
                headerHostWarnings = @()
                deferredRetries = @()
            }
        }

        $savedOffline = $script:Offline
        $script:Offline = $false
        try {
            $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ SkipLinkValidation = $false }
        } finally {
            $script:Offline = $savedOffline
        }

        script:Assert-ConditionNewlyFired -Result $result -Condition 'linkFailures'
        @($result.Report.linkValidationFailures | Where-Object { $_.type -eq 'repo' -and $_.status -eq 404 }).Count | Should -Be 1
        Should -Invoke Test-LinkTargets -Times 1 -Exactly
    }

    It 'counts every README action target by type, the dispatcher included' {
        # Not a condition of its own: the link summary's per-type counts have to add up to its
        # total. Same seams as the live-probe case above, with every probe passing.
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $visible = @($catalog.entries | Where-Object { $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })
        $repos = @($visible | ForEach-Object {
            if ($_.repo -eq 'ReleaseTool') { $script:ReachabilityRepos[0] } else { New-TestRepoMeta -Name ([string]$_.repo) }
        })
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog -Repos $repos
        $script:RealUserscriptTrust = ${function:Test-UserscriptInstallTrust}
        Mock Test-UserscriptInstallTrust { & $script:RealUserscriptTrust -Entries $Entries -Skip }
        Mock Invoke-GhCli { [ordered]@{ output = 'gh unavailable in this test'; exitCode = 1; text = 'gh unavailable in this test' } }
        Mock Test-LinkTargets {
            [ordered]@{
                failures = @(); warnings = @(); targetCount = 1; liveProbedCount = 1; cacheServedCount = 0; oldestCacheEntryAgeHours = $null
                allResultsFromCache = $false; throttleLimit = 1; elapsedMs = 0; warningCountByHost = @(); headerHostWarnings = @(); deferredRetries = @()
            }
        }

        $savedOffline = $script:Offline
        $script:Offline = $false
        try {
            $result = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ SkipLinkValidation = $false }
        } finally {
            $script:Offline = $savedOffline
        }

        $summary = $result.Report.linkValidationSummary
        $summary.readmeInstallDispatcherTargetCount | Should -Be 1
        $summary.readmeInstallSnippetTargetCount | Should -BeGreaterThan 0
        ($summary.readmeInstallSnippetTargetCount + $summary.readmeInstallDispatcherTargetCount + $summary.readmeDownloadLinkTargetCount + $summary.readmeUserscriptInstallTargetCount) |
            Should -Be $summary.readmeActionTargetCount
    }

    It 'writes a full userscript row only for a script with a warning or a fatal' {
        # Not a condition either. Fourteen rows of passing evidence took the report past its
        # size budget, so the clean scripts are named instead; the counts still cover both.
        $baseline = script:New-ReachabilityBaseline -Catalog (Get-Catalog -Path $script:ReachabilityCatalogPath)
        $clean = New-TestEntry -Repo 'CleanScript' -Category 'extensions'
        $clean.downloadKind = 'userscript'
        $clean.userscriptUrl = 'https://raw.githubusercontent.com/SysAdminDoc/CleanScript/main/CleanScript.user.js'
        $broad = New-TestEntry -Repo 'BroadScript' -Category 'extensions'
        $broad.downloadKind = 'userscript'
        $broad.userscriptUrl = 'https://raw.githubusercontent.com/SysAdminDoc/BroadScript/main/BroadScript.user.js'
        $script:TrimEntries = @($clean, $broad)
        $script:TrimContent = @{
            $clean.userscriptUrl = "// ==UserScript==`n// @name Clean Script`n// @version 1.0.0`n// @match https://example.com/*`n// @updateURL $($clean.userscriptUrl)`n// @downloadURL $($clean.userscriptUrl)`n// ==/UserScript=="
            $broad.userscriptUrl = "// ==UserScript==`n// @name Broad Script`n// @version 1.0.0`n// @match *://*/*`n// @updateURL $($broad.userscriptUrl)`n// @downloadURL $($broad.userscriptUrl)`n// ==/UserScript=="
        }
        $script:TrimProbes = @{
            $clean.userscriptUrl = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
            $broad.userscriptUrl = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
        }
        $script:RealUserscriptTrust = ${function:Test-UserscriptInstallTrust}
        Mock Test-UserscriptInstallTrust { & $script:RealUserscriptTrust -Entries $script:TrimEntries -ContentByUrl $script:TrimContent -ProbeByUrl $script:TrimProbes }

        $result = script:Invoke-ReachabilityState -Baseline $baseline

        $section = $result.Report.userscriptInstallTrust
        @($section.rows | ForEach-Object { $_.repo }) | Should -Be @('BroadScript')
        @($section.rows[0].warnings | ForEach-Object { $_.kind }) | Should -Contain 'scope-broad'
        @($section.passingRepos) | Should -Be @('CleanScript')
        $section.checkedCount | Should -Be 2
        $section.releaseChannelKeepBranchCount | Should -Be 2
        $section.warningCount | Should -Be 1
        $result.Report.schemaValidation.report.valid | Should -BeTrue
    }

    It 'fires releaseArtifactVerification only when the switch is set' {
        $catalog = Get-Catalog -Path $script:ReachabilityCatalogPath
        $baseline = script:New-ReachabilityBaseline -Catalog $catalog

        # Off by default: the condition is guarded by the switch, so it can never fire
        # in the unattended lane, which is itself worth pinning.
        $default = script:Invoke-ReachabilityState -Baseline $baseline
        [bool]$default.FailureConditions['releaseArtifactVerification'] | Should -BeFalse
        $default.Report.releaseArtifactVerification.enabled | Should -BeFalse

        $enabled = script:Invoke-ReachabilityState -Baseline $baseline -Override @{ VerifyReleaseArtifacts = $true }
        $enabled.Report.releaseArtifactVerification.enabled | Should -BeTrue
    }
}

Describe 'Link cache lifetimes depend on what the previous answer was' {
    It 'holds successes, expires dead links quickly, and never reuses transient failures' -ForEach @(
        @{ Case = 'success'; Status = 200; Ok = $true; Expected = 24 }
        @{ Case = 'not-found'; Status = 404; Ok = $false; Expected = 1 }
        @{ Case = 'gone'; Status = 410; Ok = $false; Expected = 1 }
        @{ Case = 'throttled'; Status = 429; Ok = $false; Expected = 0 }
        @{ Case = 'server-error'; Status = 500; Ok = $false; Expected = 0 }
        @{ Case = 'forbidden'; Status = 403; Ok = $false; Expected = 0 }
        @{ Case = 'timeout'; Status = $null; Ok = $false; Expected = 0 }
    ) {
        # One flat TTL kept a corrected 404 broken for a day and kept a rate-limited
        # host "failed" without ever retrying it.
        Get-LinkCacheTtlHours -Status $Status -Ok $Ok -SuccessTtlHours 24 -DeadLinkTtlHours 1 | Should -Be $Expected
    }

    It 'parses both Retry-After forms and caps how long a run will wait' -ForEach @(
        @{ Case = 'delta-seconds'; Value = '30'; Requested = 30; Wait = 30; Capped = $false }
        @{ Case = 'delta-over-cap'; Value = '600'; Requested = 600; Wait = 60; Capped = $true }
        @{ Case = 'http-date'; Value = 'Sat, 05 Sep 2026 12:10:00 GMT'; Requested = 600; Wait = 60; Capped = $true }
    ) {
        # RFC 9110 section 10.2.3 allows delta-seconds or an HTTP-date. A server may name
        # hours; a local run must report the real retry time rather than sleep for it.
        $now = [datetimeoffset]::Parse('2026-09-05T12:00:00Z')
        $retry = Get-RetryAfterSeconds -RetryAfter $Value -CapSeconds 60 -Now $now

        $retry | Should -Not -BeNullOrEmpty
        $retry.requestedSeconds | Should -Be $Requested
        $retry.waitSeconds | Should -Be $Wait
        $retry.capped | Should -Be $Capped
        ([datetimeoffset]::Parse($retry.retryAfterUtc)) | Should -Be $now.AddSeconds($Requested)
    }

    It 'returns nothing for an absent or unparseable Retry-After' -ForEach @(
        @{ Value = $null }
        @{ Value = '' }
        @{ Value = 'not-a-date' }
    ) {
        Get-RetryAfterSeconds -RetryAfter $Value -Now ([datetimeoffset]::Parse('2026-09-05T12:00:00Z')) |
            Should -BeNullOrEmpty
    }

    It 'clamps a Retry-After that has already passed to zero' {
        $now = [datetimeoffset]::Parse('2026-09-05T12:00:00Z')
        $retry = Get-RetryAfterSeconds -RetryAfter 'Sat, 05 Sep 2026 11:00:00 GMT' -Now $now
        $retry.requestedSeconds | Should -Be 0
        $retry.waitSeconds | Should -Be 0
    }

    It 'keeps stale validators readable so a re-probe can revalidate' {
        $cacheRoot = Join-Path $TestDrive 'link-cache'
        $oldEnabled = $script:CacheEnabled
        $oldPath = $script:CachePath
        try {
            $script:CacheEnabled = $true
            $script:CachePath = $cacheRoot
            $key = Get-LinkProbeCacheKey -Url 'https://example.invalid/stale'
            $entryPath = Get-ValidationCacheFilePath -Bucket links -Key $key
            New-Item -ItemType Directory -Path (Split-Path -Parent $entryPath) -Force | Out-Null
            ([ordered]@{
                key = $key
                fetchedAt = ([datetimeoffset]::Now.AddHours(-100)).ToUniversalTime().ToString('o')
                etag = 'W/"abc123"'
                lastModified = 'Fri, 01 Aug 2026 10:00:00 GMT'
                value = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
            } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $entryPath -Encoding utf8

            # Without -IncludeStale the entry is dropped and its validators with it.
            Read-ValidationCacheEntry -Bucket links -Key $key -NoCounters | Should -BeNullOrEmpty

            $stale = Read-ValidationCacheEntry -Bucket links -Key $key -IncludeStale -NoCounters
            $stale | Should -Not -BeNullOrEmpty
            (Get-MemberValue -Object $stale -Name 'stale') | Should -BeTrue
            (Get-MemberValue -Object $stale -Name 'etag') | Should -Be 'W/"abc123"'
            (Get-MemberValue -Object $stale -Name 'lastModified') | Should -Be 'Fri, 01 Aug 2026 10:00:00 GMT'
            [double](Get-MemberValue -Object $stale -Name 'ageHours') | Should -BeGreaterThan 24
        } finally {
            $script:CacheEnabled = $oldEnabled
            $script:CachePath = $oldPath
        }
    }

    It 'counts the reuse decision rather than the flat TTL' {
        # A 404 written three hours ago is inside the 24h TTL but outside its own
        # one-hour lifetime, so reporting it as a cache hit overstated coverage.
        $cacheRoot = Join-Path $TestDrive 'decision-cache'
        $oldEnabled = $script:CacheEnabled
        $oldPath = $script:CachePath
        try {
            $script:CacheEnabled = $true
            $script:CachePath = $cacheRoot
            Reset-ValidationCacheState

            foreach ($seed in @(
                @{ Url = 'https://example.invalid/ok-fresh'; Status = 200; Ok = $true; Age = 2 }
                @{ Url = 'https://example.invalid/404-old'; Status = 404; Ok = $false; Age = 3 }
                @{ Url = 'https://example.invalid/throttled'; Status = 429; Ok = $false; Age = 0.1 }
                @{ Url = 'https://example.invalid/ok-stale'; Status = 200; Ok = $true; Age = 30 }
            )) {
                $key = Get-LinkProbeCacheKey -Url $seed.Url
                $entryPath = Get-ValidationCacheFilePath -Bucket links -Key $key
                New-Item -ItemType Directory -Path (Split-Path -Parent $entryPath) -Force | Out-Null
                ([ordered]@{
                    key = $key
                    fetchedAt = ([datetimeoffset]::Now.AddHours(-$seed.Age)).ToUniversalTime().ToString('o')
                    etag = 'W/"seed"'
                    lastModified = $null
                    value = [ordered]@{ ok = $seed.Ok; status = $seed.Status; error = $null; fatal = $false }
                } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $entryPath -Encoding utf8
            }

            $targets = @('ok-fresh', '404-old', 'throttled', 'ok-stale', 'never-seen' | ForEach-Object {
                [pscustomobject]@{ repo = 'x'; type = 't'; url = "https://example.invalid/$_"; host = 'example.invalid'; fatalOnFailure = $false }
            })
            $null = Invoke-LinkProbeBatch -Targets $targets
            $state = Get-ValidationCacheState

            $state.links.hitCount | Should -Be 1
            $state.links.staleCount | Should -Be 3
            $state.links.missCount | Should -Be 1
        } finally {
            $script:CacheEnabled = $oldEnabled
            $script:CachePath = $oldPath
        }
    }

    It 'reports live-probed and cache-served counts in the batch result' {
        $cacheRoot = Join-Path $TestDrive 'coverage-cache'
        $oldEnabled = $script:CacheEnabled
        $oldPath = $script:CachePath
        try {
            $script:CacheEnabled = $true
            $script:CachePath = $cacheRoot
            Reset-ValidationCacheState

            $targets = @(
                (New-LinkValidationTarget -Repo 'a' -Type 't' -Url 'https://example.invalid/live-a' -FatalOnFailure $false -Group 'g'),
                (New-LinkValidationTarget -Repo 'b' -Type 't' -Url 'https://example.invalid/live-b' -FatalOnFailure $false -Group 'g')
            )
            $probe = { param($t) [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false; notModified = $false; etag = $null; lastModified = $null; retryAfter = $null } }
            $batch = Invoke-LinkProbeBatch -Targets $targets -ProbeScript $probe

            $batch.liveProbedCount | Should -Be 2
            $batch.cacheServedCount | Should -Be 0
            $batch.allResultsFromCache | Should -BeFalse
        } finally {
            $script:CacheEnabled = $oldEnabled
            $script:CachePath = $oldPath
        }
    }

    It 'reports allResultsFromCache when every target is cached' {
        $cacheRoot = Join-Path $TestDrive 'all-cached'
        $oldEnabled = $script:CacheEnabled
        $oldPath = $script:CachePath
        try {
            $script:CacheEnabled = $true
            $script:CachePath = $cacheRoot
            Reset-ValidationCacheState

            $key = Get-LinkProbeCacheKey -Url 'https://example.invalid/only-cached'
            $entryPath = Get-ValidationCacheFilePath -Bucket links -Key $key
            New-Item -ItemType Directory -Path (Split-Path -Parent $entryPath) -Force | Out-Null
            ([ordered]@{
                key = $key
                fetchedAt = ([datetimeoffset]::Now.AddMinutes(-30)).ToUniversalTime().ToString('o')
                value = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
            } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $entryPath -Encoding utf8

            $targets = @(
                (New-LinkValidationTarget -Repo 'a' -Type 't' -Url 'https://example.invalid/only-cached' -FatalOnFailure $false -Group 'g')
            )
            $batch = Invoke-LinkProbeBatch -Targets $targets

            $batch.cacheServedCount | Should -Be 1
            $batch.liveProbedCount | Should -Be 0
            $batch.allResultsFromCache | Should -BeTrue
        } finally {
            $script:CacheEnabled = $oldEnabled
            $script:CachePath = $oldPath
        }
    }

    It 'sends stored validators and lets a 304 restore the previous verdict' {
        # Built through New-LinkValidationTarget, which returns an [ordered] dictionary.
        # An earlier version of this test used [pscustomobject], a shape the generator
        # never produces, and so passed while conditional headers were never sent:
        # $target.PSObject.Properties.Name on a dictionary lists Count/Keys/Values, not
        # the entries.
        $oldEnabled = $script:CacheEnabled
        $oldPath = $script:CachePath
        $oldProbe = ${function:Test-HttpUrl}
        try {
            $script:CacheEnabled = $true
            $script:CachePath = Join-Path $TestDrive 'conditional-cache'
            Reset-ValidationCacheState

            $url = 'https://example.invalid/conditional'
            $key = Get-LinkProbeCacheKey -Url $url
            $entryPath = Get-ValidationCacheFilePath -Bucket links -Key $key
            New-Item -ItemType Directory -Path (Split-Path -Parent $entryPath) -Force | Out-Null
            ([ordered]@{
                key = $key
                fetchedAt = ([datetimeoffset]::Now.AddHours(-100)).ToUniversalTime().ToString('o')
                etag = 'W/"stored-etag"'
                lastModified = 'Fri, 01 Aug 2026 10:00:00 GMT'
                value = [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false }
            } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $entryPath -Encoding utf8

            $target = New-LinkValidationTarget -Repo 'x' -Type 't' -Url $url -FatalOnFailure $false -Group 'g'
            $target | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]

            # The stale entry's validators must be attached to the target by the cache
            # read loop. Reading them off the dictionary is the assertion: a PSObject
            # guard here silently found nothing and no header was ever sent.
            $seen = [ordered]@{}
            $probe = {
                param($t)
                $seen['ifNoneMatch'] = Get-MemberValue -Object $t -Name 'ifNoneMatch'
                $seen['ifModifiedSince'] = Get-MemberValue -Object $t -Name 'ifModifiedSince'
                [ordered]@{ ok = $true; status = 200; error = $null; fatal = $false; notModified = $true
                    etag = Get-MemberValue -Object $t -Name 'ifNoneMatch'
                    lastModified = Get-MemberValue -Object $t -Name 'ifModifiedSince'
                    retryAfter = $null }
            }
            $row = (Invoke-LinkProbeBatch -Targets @($target) -ProbeScript $probe).results[0]

            $seen['ifNoneMatch'] | Should -Be 'W/"stored-etag"' -Because 'the stale entry carries a validator the probe must receive'
            $seen['ifModifiedSince'] | Should -Be 'Fri, 01 Aug 2026 10:00:00 GMT'
            $row.notModified | Should -BeTrue
            $row.etag | Should -Be 'W/"stored-etag"'
            $row.lastModified | Should -Be 'Fri, 01 Aug 2026 10:00:00 GMT'
        } finally {
            $script:CacheEnabled = $oldEnabled
            $script:CachePath = $oldPath
        }
    }

    It 'restores the cached verdict on a 304 rather than reporting 304' {
        # Test-HttpUrl itself builds the conditional headers and classifies the answer.
        $captured = $null
        $result = & {
            function Invoke-SafeOutboundHttpRequest {
                param([string]$Url, [string]$Method, [int]$TimeoutSec, [int]$MaxRedirects, [int64]$MaxBytes,
                    [switch]$ReadBody, [string]$UserAgent, [string]$Accept, [hashtable]$Headers = @{},
                    [scriptblock]$ResolveHostScript, [scriptblock]$SendRequestScript)
                $script:CapturedHeaders = $Headers
                [ordered]@{ ok = $false; statusCode = 304; error = $null; policyBlocked = $false
                    etag = 'W/"stored-etag"'; lastModified = $null; retryAfter = $null }
            }
            Test-HttpUrl -Url 'https://example.invalid/x' -IfNoneMatch 'W/"stored-etag"' -IfModifiedSince 'Fri, 01 Aug 2026 10:00:00 GMT'
        }

        $result.status | Should -Be 304
        $result.notModified | Should -BeTrue
        $result.ok | Should -BeTrue -Because 'not-modified means the previous answer still stands'
        $script:CapturedHeaders['If-None-Match'] | Should -Be 'W/"stored-etag"'
        $script:CapturedHeaders['If-Modified-Since'] | Should -Be 'Fri, 01 Aug 2026 10:00:00 GMT'
    }

    It 'reports a future retry time instead of sleeping through it' {
        $oldEnabled = $script:CacheEnabled
        try {
            $script:CacheEnabled = $false
            $throttled = {
                param($t)
                [ordered]@{
                    ok = $false; status = 429; error = 'HTTP 429'; fatal = $false; notModified = $false
                    etag = $null; lastModified = $null
                    retryAfter = (Get-RetryAfterSeconds -RetryAfter '600' -CapSeconds 60 -Now ([datetimeoffset]::Parse('2026-09-05T12:00:00Z')))
                }
            }
            $target = New-LinkValidationTarget -Repo 'x' -Type 't' -Url 'https://throttled.invalid/a' -FatalOnFailure $false -Group 'g'

            $deferred = @((Invoke-LinkProbeBatch -Targets @($target) -ProbeScript $throttled).deferredRetries)

            $deferred | Should -HaveCount 1
            $deferred[0].url | Should -Be 'https://throttled.invalid/a'
            $deferred[0].status | Should -Be 429
            # The server asked for 600s; the run waits at most 60 but still reports the
            # real time the target may be probed again.
            ([datetimeoffset]::Parse($deferred[0].retryAfterUtc)) | Should -Be ([datetimeoffset]::Parse('2026-09-05T12:10:00Z'))

            $reported = @((Test-LinkTargets -Included @() -RepoLookup @{} -ExtraTargets @($target) -ProbeScript $throttled).deferredRetries)
            $reported | Should -HaveCount 1 -Because 'the retry time must reach the report, not stop at the probe batch'
        } finally {
            $script:CacheEnabled = $oldEnabled
        }
    }
}

Describe 'Dependency freshness comes from the registry, not a hand-edited map' {
    BeforeAll {
        $script:ReviewScriptPath = Join-Path $script:RepoRoot 'scripts/review-local-dependencies.ps1'
        $script:ReviewScriptText = Get-Content -LiteralPath $script:ReviewScriptPath -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:ReviewScriptText, [ref]$null, [ref]$null)
        foreach ($name in @('Get-RegistryVersionCache', 'Test-CompatibleWithLatest', 'New-PinFreshnessRow')) {
            $definition = $ast.FindAll(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
                }, $true) | Select-Object -First 1
            $definition | Should -Not -BeNullOrEmpty -Because "$name must exist in review-local-dependencies.ps1"
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    It 'no longer carries a hand-maintained latest-known version map' {
        # The map reported pins as current long after the registries moved on, which is
        # what made the freshness section green while it was wrong.
        $script:ReviewScriptText | Should -Not -Match 'LatestKnownNpmVersions'
        $script:ReviewScriptText | Should -Not -Match 'LatestKnownPythonVersions'
        $script:ReviewScriptText | Should -Not -Match 'PinLatestCheckedAt'
        $script:ReviewScriptText | Should -Match 'registry\.npmjs\.org'
        $script:ReviewScriptText | Should -Match 'pypi\.org/pypi'
    }

    It 'separates the parent declaration, the resolved pin and the registry latest' {
        $row = New-PinFreshnessRow -Name 'markdown-it' -Kind 'npm-override' -CurrentVersion '14.3.0' `
            -RegistryLatest '15.0.1' -LatestCheckedAt ([datetimeoffset]::Now.ToString('o')) `
            -Now ([datetimeoffset]::Now) -StaleAfterDays 30 -DeclaredByParent '14.3.0'

        $row.declaredByParent | Should -Be '14.3.0'
        $row.currentCompatible | Should -Be '14.3.0'
        $row.registryLatest | Should -Be '15.0.1'
        $row.latestCheckedAt | Should -Not -BeNullOrEmpty
        $row.freshnessStatus | Should -Be 'fresh'
    }

    It 'treats a new major as review-needed rather than a failure' -ForEach @(
        @{ Current = '14.3.0'; Latest = '15.0.1'; Expected = 'major-upgrade-available' }
        @{ Current = '5.2.2'; Latest = '5.4.1'; Expected = 'behind-registry-latest' }
        @{ Current = '0.23.2'; Latest = '0.23.2'; Expected = 'current' }
        @{ Current = '2.0.0'; Latest = '1.9.0'; Expected = 'ahead-of-registry-latest' }
        @{ Current = '1.0.0'; Latest = ''; Expected = 'unknown' }
        @{ Current = ''; Latest = '1.0.0'; Expected = 'unknown' }
    ) {
        Test-CompatibleWithLatest -CurrentVersion $Current -RegistryLatest $Latest | Should -Be $Expected
    }

    It 'warns on missing or stale registry evidence, not on being behind' {
        $fresh = New-PinFreshnessRow -Name 'js-yaml' -Kind 'npm-override' -CurrentVersion '5.2.2' `
            -RegistryLatest '5.4.1' -LatestCheckedAt ([datetimeoffset]::Now.ToString('o')) `
            -Now ([datetimeoffset]::Now) -StaleAfterDays 30 -DeclaredByParent '5.2.2'
        # Deliberately held back but safe: being behind must not raise a warning.
        $fresh.compatibilityStatus | Should -Be 'behind-registry-latest'
        $fresh.warning | Should -BeNullOrEmpty

        $stale = New-PinFreshnessRow -Name 'js-yaml' -Kind 'npm-override' -CurrentVersion '5.2.2' `
            -RegistryLatest '5.4.1' -LatestCheckedAt ([datetimeoffset]::Now.AddDays(-45).ToString('o')) `
            -Now ([datetimeoffset]::Now) -StaleAfterDays 30 -DeclaredByParent '5.2.2'
        $stale.freshnessStatus | Should -Be 'stale'
        $stale.warning | Should -Match 'past the 30 day window'

        $none = New-PinFreshnessRow -Name 'js-yaml' -Kind 'npm-override' -CurrentVersion '5.2.2' `
            -RegistryLatest '5.4.1' -LatestCheckedAt '' `
            -Now ([datetimeoffset]::Now) -StaleAfterDays 30 -DeclaredByParent '5.2.2'
        $none.freshnessStatus | Should -Be 'unavailable'
        $none.warning | Should -Match 'run the review online'
    }

    It 'round-trips the cache timestamp instead of culture-formatting it' {
        # ConvertFrom-Json turns an ISO string into a DateTime; casting that back to
        # string uses the current culture and produces a value the next run cannot parse.
        $cachePath = Join-Path $TestDrive 'registry-cache.json'
        $stamp = '2026-09-05T11:31:44.1116113+00:00'
        ([ordered]@{ fetchedAt = $stamp; packages = [ordered]@{ 'npm/js-yaml' = '5.4.1' } } | ConvertTo-Json -Depth 5) |
            Set-Content -LiteralPath $cachePath -Encoding utf8

        $cache = Get-RegistryVersionCache -Path $cachePath

        $parsed = [datetimeoffset]::MinValue
        [datetimeoffset]::TryParse($cache.fetchedAt, [ref]$parsed) | Should -BeTrue
        $parsed.ToUniversalTime() | Should -Be ([datetimeoffset]::Parse($stamp).ToUniversalTime())
        $cache.packages['npm/js-yaml'] | Should -Be '5.4.1'
    }

    It 'returns an empty cache rather than throwing on a missing or corrupt file' {
        $missing = Get-RegistryVersionCache -Path (Join-Path $TestDrive 'absent-cache.json')
        $missing.fetchedAt | Should -BeNullOrEmpty
        @($missing.packages.Keys) | Should -HaveCount 0

        $bad = Join-Path $TestDrive 'corrupt-cache.json'
        'not json' | Set-Content -LiteralPath $bad -Encoding utf8
        $corrupt = Get-RegistryVersionCache -Path $bad
        $corrupt.fetchedAt | Should -BeNullOrEmpty
        @($corrupt.packages.Keys) | Should -HaveCount 0
    }

    It 'offers an offline lane that reports its cache source' {
        $script:ReviewScriptText | Should -Match '\[switch\]\$OfflineRegistry'
        $script:ReviewScriptText | Should -Match "source = if \(\`$null -eq \`$cache\.fetchedAt\) \{ 'unavailable' \} else \{ 'cache' \}"
    }
}

Describe 'PowerShell module packages are verified before import' {
    BeforeAll {
        $script:ModuleLockPath = Join-Path $script:RepoRoot 'data/powershell-module-lock.json'
        $script:ModuleLock = Get-Content -LiteralPath $script:ModuleLockPath -Raw | ConvertFrom-Json
        # Load the verification helpers without executing the validation lane.
        $validationText = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/validate-local.ps1') -Raw
        $script:ValidateLocalText = $validationText
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($validationText, [ref]$null, [ref]$null)
        foreach ($name in @('Get-ModuleLockEntry', 'Assert-ModuleAuthenticodeSigner', 'Install-RequiredModule')) {
            $definition = $ast.FindAll(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
                }, $true) | Select-Object -First 1
            $definition | Should -Not -BeNullOrEmpty -Because "$name must exist in validate-local.ps1"
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    It 'locks every module the validation lane imports' {
        # A pin the lane installs but the lock does not describe would be installed
        # unverified, which is the whole gap this closes.
        $pinned = @([regex]::Matches($script:ValidateLocalText, 'Name\s*=\s*"(?<name>[^"]+)";\s*Version\s*=\s*"(?<version>[^"]+)"') |
            ForEach-Object { [pscustomobject]@{ Name = $_.Groups['name'].Value; Version = $_.Groups['version'].Value } })
        $pinned | Should -Not -BeNullOrEmpty

        foreach ($module in $pinned) {
            $entry = @($script:ModuleLock.modules | Where-Object { $_.name -ceq $module.Name -and $_.version -ceq $module.Version })
            $entry | Should -HaveCount 1 -Because "$($module.Name) $($module.Version) must have a reviewed lock record"
        }
        # The opt-in Pester 6 lane is pinned separately and must also be locked.
        @($script:ModuleLock.modules | Where-Object { $_.name -ceq 'Pester' -and $_.version -ceq '6.1.0' }) | Should -HaveCount 1
    }

    It 'records package bytes and a signer for every locked module' {
        foreach ($entry in @($script:ModuleLock.modules)) {
            $entry.packageUrl | Should -Match '^https://www\.powershellgallery\.com/api/v2/package/'
            $entry.nupkgSha256 | Should -Match '^[a-f0-9]{64}$'
            $entry.signed | Should -BeOfType [bool]
            if ($entry.signed) {
                @($entry.expectedSigners) | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'holds the lock file to its own schema' {
        # The schema required one expectedSigner string while the file, validate-local.ps1 and
        # these tests use the expectedSigners list, and nothing validated the file against it.
        $lock = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath $script:ModuleLockPath -Raw)

        $result = Test-JsonSchemaContract -Value $lock -SchemaPath 'schemas/powershell-module-lock.v1.json'

        $result.valid | Should -BeTrue -Because (@($result.errors | ConvertTo-Json -Compress -Depth 4) -join '; ')
    }

    It 'judges a lock record by what the bootstrap needs: <Case>' -ForEach @(
        @{ Case = 'an unsigned module with no signers'; Valid = $true; Change = { param($m) $m.signed = $false; $m.expectedSigners = @() } }
        @{ Case = 'a single expectedSigner string'; Valid = $false; Change = { param($m) $m.Remove('expectedSigners'); $m.expectedSigner = 'CN=x' } }
        @{ Case = 'a signed module with no signers'; Valid = $false; Change = { param($m) $m.expectedSigners = @() } }
        @{ Case = 'a blank signer'; Valid = $false; Change = { param($m) $m.expectedSigners = @(' ') } }
        # Review G5: the schema's \S is ASCII only, so these passed it while the bootstrap,
        # which asks .NET whether a signer is whitespace, refused them.
        @{ Case = 'a signer of only NBSP'; Valid = $false; Change = { param($m) $m.expectedSigners = @([string][char]0xA0) } }
        @{ Case = 'a signer of only an em space'; Valid = $false; Change = { param($m) $m.expectedSigners = @([string][char]0x2003) } }
        @{ Case = 'a signer of only ideographic spaces'; Valid = $false; Change = { param($m) $m.expectedSigners = @(([string][char]0x3000) * 2) } }
        @{ Case = 'a signer with an NBSP inside it'; Valid = $true; Change = { param($m) $m.expectedSigners = @('CN=a' + [char]0xA0 + 'b') } }
    ) {
        $module = [ordered]@{
            name = 'Pester'; version = '5.9.1'
            packageUrl = 'https://www.powershellgallery.com/api/v2/package/Pester/5.9.1'
            nupkgSha256 = ('a' * 64); signed = $true; expectedSigners = @('CN=x'); lane = 'default'
        }
        $lock = [ordered]@{ '$schema' = 'x'; note = 'n'; reviewedAt = '2026-09-24'; packageSource = 'https://www.powershellgallery.com/api/v2/package'; modules = @($module) }
        (Test-JsonSchemaContract -Value $lock -SchemaPath 'schemas/powershell-module-lock.v1.json').valid | Should -BeTrue -Because 'the record passes before the change'

        & $Change $module

        (Test-JsonSchemaContract -Value $lock -SchemaPath 'schemas/powershell-module-lock.v1.json').valid | Should -Be $Valid
    }

    It 'refuses a module version with no reviewed record' {
        { Get-ModuleLockEntry -RepoRoot $script:RepoRoot -Name 'Pester' -Version '9.9.9' } |
            Should -Throw -ExpectedMessage '*No reviewed lock record*'
        { Get-ModuleLockEntry -RepoRoot $script:RepoRoot -Name 'NotAModule' -Version '1.0.0' } |
            Should -Throw -ExpectedMessage '*No reviewed lock record*'
    }

    It 'refuses a lock record that claims signing without naming a signer' {
        $lockPath = Join-Path $TestDrive 'bad-lock.json'
        ([ordered]@{
            modules = @([ordered]@{
                name = 'Pester'; version = '5.9.1'
                packageUrl = 'https://www.powershellgallery.com/api/v2/package/Pester/5.9.1'
                nupkgSha256 = ('a' * 64)
                signed = $true
                expectedSigners = @()
            })
        } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $lockPath -Encoding utf8

        { Get-ModuleLockEntry -RepoRoot $TestDrive -Name 'Pester' -Version '5.9.1' -LockPath $lockPath } |
            Should -Throw -ExpectedMessage '*names no expected signer*'
    }

    It 'accepts every module the default lane installs' -ForEach @(
        @{ Module = 'Pester'; Version = '5.9.1' }
        # PSScriptAnalyzer bundles third-party signed assemblies, so it ships three
        # distinct signers. A single expected subject could never be satisfied and made
        # the whole bootstrap throw; only Pester was covered before.
        @{ Module = 'PSScriptAnalyzer'; Version = '1.25.0' }
    ) {
        $entry = @($script:ModuleLock.modules | Where-Object { $_.name -ceq $Module -and $_.version -ceq $Version })[0]
        $entry | Should -Not -BeNullOrEmpty
        $installed = Get-Module -ListAvailable -Name $Module | Where-Object { $_.Version -eq [version]$Version } | Select-Object -First 1
        if (-not $installed) {
            Set-ItResult -Skipped -Because "$Module $Version is not installed on this machine"
            return
        }

        $verified = Assert-ModuleAuthenticodeSigner -ModuleRoot (Split-Path -Parent $installed.Path) `
            -Name $Module -Version $Version -ExpectedSigners (@($entry.expectedSigners))

        $verified | Should -BeGreaterThan 0
    }

    It 'refuses an unsigned file inside a package the lock records as signed' {
        # Stripping a signature block is how a tampered file slips past a check that
        # only inspects files which still carry one.
        $installed = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq [version]'5.9.1' } | Select-Object -First 1
        if (-not $installed) {
            Set-ItResult -Skipped -Because 'Pester 5.9.1 is not installed on this machine'
            return
        }
        $entry = @($script:ModuleLock.modules | Where-Object { $_.name -ceq 'Pester' -and $_.version -ceq '5.9.1' })[0]
        $copy = Join-Path $TestDrive 'tampered-module'
        Copy-Item -LiteralPath (Split-Path -Parent $installed.Path) -Destination $copy -Recurse
        '# unsigned addition' | Set-Content -LiteralPath (Join-Path $copy 'Injected.psm1') -Encoding utf8

        { Assert-ModuleAuthenticodeSigner -ModuleRoot $copy -Name 'Pester' -Version '5.9.1' -ExpectedSigners (@($entry.expectedSigners)) } |
            Should -Throw -ExpectedMessage '*carry no signature*'
    }

    It 'refuses package bytes that do not match the lock, and clears them' {
        $entry = @($script:ModuleLock.modules | Where-Object { $_.name -ceq 'Pester' -and $_.version -ceq '6.1.0' })[0]
        $cache = Join-Path $TestDrive 'bad-package-cache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        $nupkg = Join-Path $cache 'Pester.6.1.0.nupkg'
        [System.IO.File]::WriteAllBytes($nupkg, [byte[]](1..64))

        { Install-RequiredModule -Name 'Pester' -Version '6.1.0' -RepoRoot $script:RepoRoot -CacheRoot $cache -DestinationRoot (Join-Path $TestDrive 'dest') } |
            Should -Throw -ExpectedMessage '*refusing to extract*'
        # A retry must not pick the rejected bytes back up.
        Test-Path -LiteralPath $nupkg | Should -BeFalse
        $entry.nupkgSha256 | Should -Match '^[a-f0-9]{64}$'
    }

    It 'refuses a signer that does not match the lock exactly' {
        $installed = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq [version]'5.9.1' } | Select-Object -First 1
        if (-not $installed) {
            Set-ItResult -Skipped -Because 'Pester 5.9.1 is not installed on this machine'
            return
        }
        $root = Split-Path -Parent $installed.Path

        { Assert-ModuleAuthenticodeSigner -ModuleRoot $root -Name 'Pester' -Version '5.9.1' -ExpectedSigners @('CN=Someone Else, O=Evil, C=XX') } |
            Should -Throw -ExpectedMessage '*which the lock does not list*'
        # The real subject carries non-ASCII characters; an ASCII-mangled copy of it must
        # not pass, because a transliterated signer is a different signer.
        { Assert-ModuleAuthenticodeSigner -ModuleRoot $root -Name 'Pester' -Version '5.9.1' -ExpectedSigners @('CN=Jakub Jares, O=Jakub Jares, L=Praha, C=CZ') } |
            Should -Throw -ExpectedMessage '*which the lock does not list*'
    }

    It 'refuses a tree with no signature when the lock says signed' {
        $root = Join-Path $TestDrive 'unsigned-module'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        '@{ ModuleVersion = "1.0" }' | Set-Content -LiteralPath (Join-Path $root 'Fake.psd1') -Encoding utf8

        { Assert-ModuleAuthenticodeSigner -ModuleRoot $root -Name 'Fake' -Version '1.0' -ExpectedSigners @('CN=Anyone') } |
            Should -Throw -ExpectedMessage '*carry no signature*'
    }

    It 'verifies package bytes before extracting and both lanes use the lock' {
        # Order matters: hashing after extraction would already have written attacker
        # controlled files to the module path.
        $script:ValidateLocalText | Should -Match 'refusing to extract'
        $script:ValidateLocalText | Should -Match 'Expand-Archive'
        $hashIndex = $script:ValidateLocalText.IndexOf('refusing to extract')
        $expandIndex = $script:ValidateLocalText.IndexOf('Expand-Archive')
        $hashIndex | Should -BeLessThan $expandIndex

        # The opt-in Pester 6 lane must not fall back to an unverified Save-Module.
        $script:ValidateLocalText | Should -Not -Match 'Get-Command Save-Module'
        @([regex]::Matches($script:ValidateLocalText, 'Get-ModuleLockEntry -RepoRoot')).Count | Should -BeGreaterOrEqual 2
    }
}

Describe 'Uncataloged public repos get a reviewable stub' {
    BeforeAll {
        function script:New-StubRepo {
            param([string]$Name, [string]$Language, [string]$Branch = 'main', [string[]]$Topics = @(), [string]$Description)
            [pscustomobject]@{
                name = $Name
                description = $Description
                primaryLanguage = if ([string]::IsNullOrWhiteSpace($Language)) { $null } else { [pscustomobject]@{ name = $Language } }
                defaultBranchRef = [pscustomobject]@{ name = $Branch }
                repositoryTopics = @($Topics | ForEach-Object { [pscustomobject]@{ name = $_ } })
            }
        }
    }

    It 'fills what live metadata can prove' {
        $stub = New-CatalogEntryStub -Repo (script:New-StubRepo -Name 'StormScope' -Language 'PowerShell' -Description 'Desktop weather radar')

        $stub.entry.repo | Should -Be 'StormScope'
        $stub.entry.title | Should -Be 'StormScope'
        $stub.entry.branch | Should -Be 'main'
        $stub.entry.language | Should -Be 'PowerShell'
        $stub.entry.descriptionOverride | Should -Be 'Desktop weather radar'
        $stub.entry.category | Should -Be 'powershell'
        # Booleans are strict in the catalog schema and must never be null-filled.
        $stub.entry.featured | Should -BeFalse
        $stub.entry.currentlyBuilding | Should -BeFalse
        $stub.entry.allowPublicMedical | Should -BeFalse
    }

    It 'leaves unobservable fields null and names them' {
        $stub = New-CatalogEntryStub -Repo (script:New-StubRepo -Name 'Mystery' -Language $null -Branch 'master' -Description $null)

        $stub.entry.branch | Should -Be 'master'
        $stub.entry.category | Should -BeNullOrEmpty
        $stub.entry.language | Should -BeNullOrEmpty
        $stub.entry.descriptionOverride | Should -BeNullOrEmpty
        $stub.unresolvedFields | Should -Contain 'category'
        $stub.unresolvedFields | Should -Contain 'downloadKind'
        $stub.unresolvedFields | Should -Contain 'language'
        $stub.unresolvedFields | Should -Contain 'descriptionOverride'
    }

    It 'infers a category from an unambiguous topic before falling back to language' {
        (New-CatalogEntryStub -Repo (script:New-StubRepo -Name 'Scripty' -Language 'JavaScript' -Topics @('userscript'))).entry.category |
            Should -Be 'extensions'
        # JavaScript alone is not a category signal, so it stays unresolved.
        (New-CatalogEntryStub -Repo (script:New-StubRepo -Name 'Plain' -Language 'JavaScript')).entry.category |
            Should -BeNullOrEmpty
    }

    It 'writes suppressed, schema-valid drafts and skips repos already cataloged' {
        $catalogPath = Join-Path $TestDrive 'catalog.json'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') -Destination $catalogPath
        $before = @(Get-JsonArrayItems (ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath $catalogPath -Raw)).entries).Count

        $mystery = New-CatalogEntryStub -Repo (script:New-StubRepo -Name 'MysteryOne' -Language $null -Branch 'master')
        $rows = @(
            [ordered]@{ repo = 'MysteryOne'; catalogEntryStub = [pscustomobject]$mystery.entry; unresolvedFields = @($mystery.unresolvedFields) }
            # Already in the committed catalog, so it must not be drafted again.
            [ordered]@{ repo = 'ColumnKit'; catalogEntryStub = [pscustomobject](New-CatalogEntryStub -Repo (script:New-StubRepo -Name 'ColumnKit' -Language 'TypeScript')).entry; unresolvedFields = @() }
        )

        Write-CatalogEntryDraft -MissingPublicRepos $rows -CatalogPath $catalogPath

        $after = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath $catalogPath -Raw)
        @(Get-JsonArrayItems $after.entries).Count | Should -Be ($before + 1)

        $drafted = @(Get-JsonArrayItems $after.entries | Where-Object { [string](Get-MemberValue -Object $_ -Name 'repo') -eq 'MysteryOne' })
        $drafted | Should -HaveCount 1
        (Get-MemberValue -Object $drafted[0] -Name 'includeInReadme') | Should -BeFalse
        (Get-MemberValue -Object $drafted[0] -Name 'includeInPortfolio') | Should -BeFalse
        (Get-MemberValue -Object $drafted[0] -Name 'suppressionReason') | Should -Match 'awaiting owner review'
        (Get-MemberValue -Object $drafted[0] -Name 'suppressionReason') | Should -Match 'Unresolved:'
        # The catalog schema requires an enum category and a non-negative order, so a
        # draft that keeps them null would make the catalog unparseable.
        (Get-MemberValue -Object $drafted[0] -Name 'category') | Should -Be 'misc'
        [int](Get-MemberValue -Object $drafted[0] -Name 'order') | Should -BeGreaterThan 0

        (Test-JsonSchemaContract -Value $after -SchemaPath 'schemas/profile-catalog.v1.json').valid | Should -BeTrue
    }

    It 'keeps every other array in the catalog an array when it writes a draft' {
        # The writer reads with the array-preserving parser, whose wrappers ConvertTo-Json
        # would otherwise write out as { "__JsonArray": true, "Items": [...] } objects.
        $catalogPath = Join-Path $TestDrive 'arrays.json'
        $catalog = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'data/profile-catalog.json')) | ConvertFrom-Json
        $catalog.entries[0] | Add-Member -NotePropertyName aliases -NotePropertyValue @('OldName') -Force
        [System.IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 20))
        $mystery = New-CatalogEntryStub -Repo (script:New-StubRepo -Name 'MysteryTwo' -Language $null -Branch 'master')
        $rows = @([ordered]@{ repo = 'MysteryTwo'; catalogEntryStub = [pscustomobject]$mystery.entry; unresolvedFields = @($mystery.unresolvedFields) })

        Write-CatalogEntryDraft -MissingPublicRepos $rows -CatalogPath $catalogPath

        $written = [System.IO.File]::ReadAllText($catalogPath)
        $written | Should -Not -Match '__JsonArray'
        $after = $written | ConvertFrom-Json -AsHashtable
        @($after.entries[0].aliases) | Should -Be @('OldName')
        @($after.profileHeader.languages).Count | Should -Be @($catalog.profileHeader.languages).Count
        @($after.profileHeader.links)[0].url | Should -Be @($catalog.profileHeader.links)[0].url
    }

    It 'writes nothing when there is nothing to draft' {
        $catalogPath = Join-Path $TestDrive 'untouched.json'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') -Destination $catalogPath
        $before = (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash

        Write-CatalogEntryDraft -MissingPublicRepos @() -CatalogPath $catalogPath

        (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'keeps drafting behind an explicit switch alongside -Write' {
        $script:SyncProfileScript | Should -Match '\[switch\]\$DraftMissingCatalogEntries'
        $script:SyncProfileScript | Should -Match 'if \(\$DraftMissingCatalogEntries -and \$Write\)'
    }
}

Describe 'Hand-authored header links and anchors are validated' {
    BeforeAll {
        $script:LiveReadme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw
    }

    It 'probes the hand-authored call to action, not just three known URLs' {
        # A dead services link shipped because the collector recognized only the
        # portfolio and setup URLs.
        $targets = @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $script:LiveReadme)
        $cta = $targets | Where-Object { $_.url -eq 'https://portfolio.getparkerai.com/healthcare-it/' }

        $cta | Should -Not -BeNullOrEmpty
        $cta.fatalOnFailure | Should -BeTrue
    }

    It 'reads no Markdown link from escaped brackets, but probes the URL GitHub autolinks in them' {
        # GitHub autolinks the bare URL between escaped brackets (checked with the /markdown
        # API), so it's a link a reader can follow and the check has to probe it. The escaped
        # fragment is plain text.
        $header = New-TestProfileHeader
        $header.about = 'Jump to [the tools](#tools) or read [the docs](https://docs.invalid/guide).'
        $readme = Update-Header -Header $header -CategorySlugs @('powershell')
        $readme | Should -Match ([regex]::Escape('\[the tools\](#tools)'))

        $docs = @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $readme | Where-Object { $_.url -like '*docs.invalid*' })
        (@($docs | ForEach-Object { $_.url }) -join ' ; ') | Should -Be 'https://docs.invalid/guide'
        $docs[0].fatalOnFailure | Should -BeTrue
        @(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | Where-Object { $_.fragment -eq 'tools' }) | Should -BeNullOrEmpty
    }

    It 'still reads a Markdown link and anchor that are not escaped' {
        $readme = 'See [the guide](https://real.example/guide) or [below](#no-such-anchor), not \[this\](https://escaped.example/).'

        $targets = @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $readme)
        @($targets | Where-Object { $_.url -eq 'https://real.example/guide' }) | Should -HaveCount 1
        # Not a Markdown link, but GitHub autolinks the URL and leaves the ) outside it.
        (@($targets | Where-Object { $_.url -like '*escaped.example*' } | ForEach-Object { $_.url }) -join ' ; ') | Should -Be 'https://escaped.example/'
        @(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | Where-Object { $_.fragment -eq 'no-such-anchor' }) | Should -HaveCount 1
    }

    It 'reads <Case> the way GitHub renders it' -ForEach @(
        # Each expectation is what GitHub's /markdown API linked for the same text on 2026-09-23.
        @{ Case = 'a bare URL between escaped brackets'; Text = '\[the docs\](https://docs.invalid/guide)'; Expected = @('link https://docs.invalid/guide') }
        @{ Case = 'escapes in a destination'; Text = '[guide](#sec\_tion) and [two](https://g.invalid/a\_b\(c\))'; Expected = @('link #sec_tion', 'link https://g.invalid/a_b(c)') }
        @{ Case = 'attribute words in a paragraph'; Text = 'See href="#x" and href="https://h.invalid/" here'; Expected = @('link https://h.invalid/') }
        @{ Case = 'a bare URL in an HTML block'; Text = '<p align="center"><b>See https://docs.invalid/x now</b></p>'; Expected = @() }
        @{ Case = 'an entity in an href'; Text = '<p align="center"><a href="https://ok.invalid/a?x=1&amp;y=2">x</a></p>'; Expected = @('link https://ok.invalid/a?x=1&y=2') }
        @{ Case = 'trailing punctuation'; Text = 'x https://f.invalid/x_ y https://f2.invalid/y* z https://f3.invalid/z? w https://f4.invalid/w! v https://f5.invalid/v. q "https://f6.invalid/q"'; Expected = @('link https://f.invalid/x', 'link https://f2.invalid/y', 'link https://f3.invalid/z', 'link https://f4.invalid/w', 'link https://f5.invalid/v', 'link https://f6.invalid/q') }
        @{ Case = 'parentheses'; Text = '(see https://d.invalid/x) and https://d2.invalid/wiki/A_(b) end'; Expected = @('link https://d.invalid/x', 'link https://d2.invalid/wiki/A_(b)') }
        @{ Case = 'an entity after a URL'; Text = 'Go &lt;https://c.invalid/x&gt; now'; Expected = @('link https://c.invalid/x') }
        @{ Case = 'letters before the scheme'; Text = 'abchttps://j.invalid/k and :https://k.invalid/l'; Expected = @('link https://k.invalid/l') }
        @{ Case = 'a URL in link text'; Text = '[https://a.invalid/p](https://b.invalid/q)'; Expected = @('link https://b.invalid/q') }
        @{ Case = 'a badge inside a link'; Text = '[![badge](https://img.invalid/b.svg)](https://badge.invalid/c)'; Expected = @('image https://img.invalid/b.svg', 'link https://badge.invalid/c') }
        @{ Case = 'a URL in a code span'; Text = 'a `https://code.invalid/` and `[x](https://code2.invalid/)` b'; Expected = @() }
        @{ Case = 'a URL cut by a tag'; Text = 'Pay at https://q.invalid/pay<span>$</span> now'; Expected = @('link https://q.invalid/pay') }
        @{ Case = 'a theme picture'; Text = '<picture><source media="(prefers-color-scheme: dark)" srcset="https://s4.invalid/dark.png"><img src="https://s5.invalid/light.png" srcset="https://s6.invalid/x.png 2x"></picture>'; Expected = @('image https://s4.invalid/dark.png', 'image https://s5.invalid/light.png') }
        @{ Case = 'a URL after a lone tag line'; Text = "<a href=`"https://seven.invalid/`">`nhttps://after.invalid/x"; Expected = @('link https://seven.invalid/') }
        @{ Case = 'a URL after a comment'; Text = "<!-- https://comment.invalid/ -->`nhttps://aftercomment.invalid/z"; Expected = @('link https://aftercomment.invalid/z') }
        # Review G3 of 7aebf68, each checked against the API on 2026-09-24.
        @{ Case = 'an angle autolink'; Text = 'Go <https://ab.invalid/> now'; Expected = @('link https://ab.invalid/') }
        @{ Case = 'a URL in another tag''s attribute'; Text = 'See <span title="https://t.invalid/x">now</span>'; Expected = @() }
        @{ Case = 'a tag and a URL in a comment'; Text = 'See <!-- <a href="https://cm.invalid/"> https://cm2.invalid/ --> now'; Expected = @() }
        @{ Case = 'a lone tag after a rule'; Text = "---`n<a href=`"https://seven2.invalid/`">`nhttps://after2.invalid/x"; Expected = @('link https://seven2.invalid/') }
        @{ Case = 'a lone tag after a quote'; Text = "> quote`n<a href=`"https://seven3.invalid/`">`nhttps://after3.invalid/x"; Expected = @('link https://seven3.invalid/') }
        @{ Case = 'a lone tag after a list item'; Text = "- item`n<a href=`"https://seven4.invalid/`">`nhttps://after4.invalid/x"; Expected = @('link https://seven4.invalid/') }
        @{ Case = 'a lone tag after a setext heading'; Text = "Title`n===`n<a href=`"https://seven5.invalid/`">`nhttps://after5.invalid/x"; Expected = @('link https://seven5.invalid/') }
        @{ Case = 'indented code'; Text = "para`n`n    https://indent.invalid/x"; Expected = @() }
        @{ Case = 'a fenced block'; Text = "text`n```````nhttps://fence.invalid/x`n`n<a href=`"https://fence2.invalid/`">x</a>`n```````nafter https://afterfence.invalid/y"; Expected = @('link https://afterfence.invalid/y') }
        @{ Case = 'indented text in a list item'; Text = "- item`n`n    https://listcont.invalid/x"; Expected = @('link https://listcont.invalid/x') }
        # Review G5, each checked with the API.
        @{ Case = 'an angle autolink with an entity'; Text = 'Go <https://ab.invalid/?a=1&amp;b=2> now'; Expected = @('link https://ab.invalid/?a=1&b=2') }
        @{ Case = 'an indented tag in a list item'; Text = "- item`n  <a href=`"https://li.invalid/`">`nhttps://lazy.invalid/x"; Expected = @('link https://li.invalid/', 'link https://lazy.invalid/x') }
        @{ Case = 'indented code in a list item'; Text = "- item`n`n      https://deep.invalid/x"; Expected = @() }
        @{ Case = 'indented code in an ordered item'; Text = "1. item`n`n       https://deep2.invalid/x"; Expected = @() }
        @{ Case = 'text six spaces into an ordered item'; Text = "1. item`n`n      https://six.invalid/x"; Expected = @('link https://six.invalid/x') }
        # Review G7: text five or more spaces after the marker is indented code.
        @{ Case = 'code on a list item line'; Text = "-      https://code.invalid/x"; Expected = @() }
    ) {
        $references = @(Get-ReadmeHeaderLinkReference -ExpectedReadme $Text | ForEach-Object { $_.kind + ' ' + $_.value })

        (@($references | Sort-Object) -join ' ; ') | Should -Be (@($Expected | Sort-Object) -join ' ; ')
    }

    It 'takes an anchor only from a real tag' {
        # The words name="ghost" in a paragraph used to count as an anchor, so a link to a
        # missing one looked fine.
        $readme = 'See name="ghost" here. <a name="real"></a>' + "`n`n" + '<p align="center"><a href="#ghost">A</a> &middot; <a href="#real">B</a></p>'

        (@(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | ForEach-Object { $_.fragment }) -join ' ; ') | Should -Be 'ghost'
    }

    It 'takes no anchor from a tag GitHub shows as text or drops: <Case>' -ForEach @(
        @{ Case = 'a code span'; Text = 'See `<a name="ghost"></a>` here.' }
        @{ Case = 'an HTML comment'; Text = 'See <!-- <a name="ghost"></a> --> here.' }
        @{ Case = 'an escaped tag'; Text = 'See \<a name="ghost"></a> here.' }
        @{ Case = 'a fenced block'; Text = "text`n```````n<a name=`"ghost`"></a>`n``````" }
        @{ Case = 'a heading line in a fenced block'; Text = "text`n``````powershell`n# Ghost`n``````" }
        @{ Case = 'the line after an empty heading'; Text = "#`nghost" }
    ) {
        # Review G3: each of these counted as an anchor, so a link to a missing one passed.
        $readme = $Text + "`n`n" + '<p align="center"><a href="#ghost">A</a></p>'

        (@(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | ForEach-Object { $_.fragment }) -join ' ; ') | Should -Be 'ghost'
    }

    It 'reads an anchor as GitHub does with <Case>' -ForEach @(
        # Review G5, each checked with the API. The link comes first so a fence that runs to
        # the end can't take it too.
        @{ Case = 'escaped backticks around it'; Text = 'See \`x <a id="real"></a> y\` here.'; Present = $true }
        @{ Case = 'an escaped backtick before a code span'; Text = 'a \` <a id="real"></a> `x`'; Present = $true }
        @{ Case = 'comment markers in code spans around it'; Text = 'See `<!--` <a id="real"></a> `-->` here.'; Present = $true }
        @{ Case = 'a comment that starts inside a code span'; Text = 'See ` <!-- ` --> ` <a id="real"></a> ` here.'; Present = $false }
        @{ Case = 'a backtick in a fence''s info string'; Text = ('```a`b' + "`n" + '<a id="real"></a>' + "`n" + '```'); Present = $true }
        @{ Case = 'a fence after a line that only looks like one'; Text = ('```a`b' + "`nx`n" + '```' + "`n`n" + '<a id="real"></a>'); Present = $false }
        @{ Case = 'a closing run of mixed characters'; Text = ('```' + "`nx`n" + '```~' + "`n`n" + '<a id="real"></a>'); Present = $false }
    ) {
        $readme = '<p align="center"><a href="#real">x</a></p>' + "`n`n" + $Text + "`n"

        (@(Test-ReadmeHeaderAnchor -ExpectedReadme $readme).Count -eq 0) | Should -Be $Present
    }

    It 'takes an anchor from an id on any element' {
        # GitHub keeps id on a div or a p (as user-content-<id>), so #top reaches it.
        $readme = '<div id="top"></div>' + "`n`n" + '<p align="center"><a href="#top">Top</a></p>'

        @(Test-ReadmeHeaderAnchor -ExpectedReadme $readme) | Should -BeNullOrEmpty
    }

    It 'takes anchors after a fenced block in CRLF text' {
        # The generated README has CRLF line endings; the closing fence didn't match before
        # its CR, so the first fence ran to the end and hid every anchor after it.
        $readme = "``````powershell`r`nirm x`r`n```````r`n`r`n<a id=`"after`"></a>`r`n`r`n## Later`r`n`r`n" + '<p align="center"><a href="#after">A</a> <a href="#later">B</a></p>'

        @(Test-ReadmeHeaderAnchor -ExpectedReadme $readme) | Should -BeNullOrEmpty
    }

    It 'fails on an unknown dead call to action in the header' {
        $planted = '<p align="center"><a href="https://example.invalid/dead-cta"><b>Dead</b></a></p>' + "`n" + $script:LiveReadme

        $target = @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $planted) |
            Where-Object { $_.url -eq 'https://example.invalid/dead-cta' }

        $target | Should -Not -BeNullOrEmpty
        $target.type | Should -Be 'header-link'
        $target.fatalOnFailure | Should -BeTrue
    }

    It 'resolves every local fragment in the committed README' {
        @(Test-ReadmeHeaderAnchor -ExpectedReadme $script:LiveReadme) | Should -HaveCount 0
    }

    It 'fails a missing local anchor without any network access' {
        $planted = $script:LiveReadme.Replace('<a href="#powershell-system-utilities">PowerShell</a>', '<a href="#totally-absent-section">PowerShell</a>')

        $missing = @(Test-ReadmeHeaderAnchor -ExpectedReadme $planted)

        $missing | Should -HaveCount 1
        $missing[0].fragment | Should -Be 'totally-absent-section'
        $missing[0].reason | Should -Match 'No heading or explicit anchor'
    }

    It 'stops at the generated-catalog notice' {
        # Everything below the notice is generated and covered by the action-link lane;
        # scanning it here would double-probe hundreds of targets.
        @(Get-ReadmeHeaderLinkReference -ExpectedReadme $script:LiveReadme) |
            Where-Object { $_.value -like '*win11-nvme*' } |
            Should -HaveCount 0
    }

    It 'splits srcset candidates and keeps images warning-only' {
        # GitHub strips srcset from an <img> and keeps it on a <picture>'s <source>, the theme
        # image, so the candidates there are what a reader can load.
        $fixture = '<p><picture><source media="(prefers-color-scheme: dark)" srcset="https://a.example/x.png 1x, https://b.example/y.png 2x"><img srcset="https://d.example/w.png 2x" src="https://c.example/z.png"></picture></p>' + "`n" + $GeneratedCatalogNotice

        $targets = @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $fixture)

        @($targets).Count | Should -Be 3
        foreach ($target in $targets) {
            $target.type | Should -Be 'header-image'
            $target.fatalOnFailure | Should -BeFalse
        }
        ($targets | ForEach-Object { $_.url }) | Should -Contain 'https://b.example/y.png'
        ($targets | ForEach-Object { $_.url }) | Should -Not -Contain 'https://d.example/w.png'
    }

    It 'slugs headings the way GitHub does' {
        ConvertTo-GitHubHeadingAnchor -Text 'Browser Extensions & Userscripts' | Should -Be 'browser-extensions--userscripts'
        ConvertTo-GitHubHeadingAnchor -Text 'Media & Conversion Tools' | Should -Be 'media--conversion-tools'
        ConvertTo-GitHubHeadingAnchor -Text '**Start Here**' | Should -Be 'start-here'
        ConvertTo-GitHubHeadingAnchor -Text '<b>AI</b> Implementation Services' | Should -Be 'ai-implementation-services'
    }

    It 'gives the id github.com rendered for a heading with <Case>' -ForEach @(
        # Each expected id was read off a heading rendered on github.com on 2026-09-24. The
        # slug dropped every _, mark and number beyond 0-9, kept &amp; as "amp" and read
        # neither escapes nor images, so a correct link to any of these was reported missing.
        @{ Case = 'an underscore'; Text = 'Net_Tools'; Expected = 'net_tools' }
        @{ Case = 'accented letters'; Text = 'Caf' + [char]0xE9 + ' D' + [char]0xE9 + 'j' + [char]0xE0; Expected = 'caf' + [char]0xE9 + '-d' + [char]0xE9 + 'j' + [char]0xE0 }
        @{ Case = 'emphasis'; Text = 'A *b* _c_ **d** __e__'; Expected = 'a-b-c-d-e' }
        @{ Case = 'underscores inside a word'; Text = 'a_b_c and _em_'; Expected = 'a_b_c-and-em' }
        @{ Case = 'backslash escapes'; Text = 'x\_y and \*z\*'; Expected = 'x_y-and-z' }
        @{ Case = 'escaped emphasis and an escaped entity'; Text = '\_em\_ and \&amp; lit'; Expected = '_em_-and-amp-lit' }
        @{ Case = 'markup inside a code span'; Text = 'Use `_x_` and `&amp;` here'; Expected = 'use-_x_-and-amp-here' }
        @{ Case = 'numbers that are not digits'; Text = 'Half ' + [char]0xBD + ' sup ' + [char]0xB2 + ' arabic ' + [char]0x663; Expected = 'half--sup--arabic-' + [char]0x663 }
        @{ Case = 'a letter number and an astral digit'; Text = 'Rome ' + [char]0x216B + ' math ' + [char]::ConvertFromUtf32(0x1D7D8); Expected = 'rome-' + [char]0x217B + '-math-' + [char]::ConvertFromUtf32(0x1D7D8) }
        @{ Case = 'fullwidth and subscript digits'; Text = 'wide ' + [char]0xFF11 + ' sub ' + [char]0x2081; Expected = 'wide-' + [char]0xFF11 + '-sub-' }
        @{ Case = 'a combining mark'; Text = 'Cafe' + [char]0x301 + ' ok'; Expected = 'cafe' + [char]0x301 + '-ok' }
        @{ Case = 'titlecase, modifier and other letters'; Text = 'Dz ' + [char]0x1C5 + ' ' + [char]0x3131 + ' ' + [char]0x2B0; Expected = 'dz-' + [char]0x1C6 + '-' + [char]0x3131 + '-' + [char]0x2B0 }
        @{ Case = 'connector punctuation'; Text = 'a' + [char]0x203F + 'b wide' + [char]0xFF3F + 'line'; Expected = 'a' + [char]0x203F + 'b-wide' + [char]0xFF3F + 'line' }
        @{ Case = 'the joiners'; Text = 'a' + [char]0x200D + 'b a' + [char]0x200C + 'b'; Expected = 'a' + [char]0x200D + 'b-a' + [char]0x200C + 'b' }
        @{ Case = 'a circled letter'; Text = 'circ ' + [char]0x24B6; Expected = 'circ-' + [char]0x24D0 }
        @{ Case = 'full lower casing'; Text = 'dot ' + [char]0x130 + ' sharp ' + [char]0x1E9E + ' kelvin ' + [char]0x212A + ' ' + [char]0x39F + [char]0x3A3; Expected = 'dot-i' + [char]0x307 + '-sharp-' + [char]0xDF + '-kelvin-k-' + [char]0x3BF + [char]0x3C3 }
        @{ Case = 'a tab, an ampersand and a bang'; Text = "Tab`tHere & more!"; Expected = 'tabhere--more' }
        @{ Case = 'other spaces and invisible characters'; Text = 'No' + [char]0xA0 + 'break ideo' + [char]0x3000 + 'space soft' + [char]0xAD + 'hyphen zero' + [char]0x200B + 'width'; Expected = 'nobreak-ideospace-softhyphen-zerowidth' }
        @{ Case = 'dashes'; Text = '- dash ' + [char]0x2013 + ' here -'; Expected = '--dash--here--' }
        @{ Case = 'an emoji'; Text = 'Party ' + [char]::ConvertFromUtf32(0x1F389) + ' time'; Expected = 'party--time' }
        @{ Case = 'punctuation'; Text = "Hey, I'm v1.2: C++ @home `$5"; Expected = 'hey-im-v12-c-home-5' }
        @{ Case = 'a link'; Text = '[Linked](https://example.invalid/) text'; Expected = 'linked-text' }
        @{ Case = 'an image'; Text = '![Alt](https://example.invalid/a.png) pic'; Expected = '-pic' }
        @{ Case = 'a code span'; Text = 'Use `code_here` now'; Expected = 'use-code_here-now' }
        @{ Case = 'entities'; Text = 'Tom &amp; Jerry &lt;3'; Expected = 'tom--jerry-3' }
        @{ Case = 'inline HTML'; Text = 'Big <b>bold</b> word'; Expected = 'big-bold-word' }
        @{ Case = 'strikethrough'; Text = 'Old ~~gone~~ new'; Expected = 'old-gone-new' }
    ) {
        $slug = ConvertTo-GitHubHeadingAnchor -Text $Text

        # Ordinal: Should -BeExactly compares by culture, so a slug that lost or kept a
        # zero-width character would still pass.
        $slug | Should -BeOrdinal $Expected
    }

    It 'slugs the text GitHub renders for a heading with <Case>' -ForEach @(
        # Review G6: GitHub's rendered text of each heading (gh api markdown), put through the
        # character rules above. Each of these slugged differently.
        @{ Case = 'an underscore that opens nothing'; Text = '_a_b _c_'; Expected = '_a_b-c' }
        @{ Case = 'emphasis around a code span'; Text = '_a `b`_'; Expected = 'a-b' }
        @{ Case = 'an escaped backtick before emphasis'; Text = '\`_x_`'; Expected = 'x' }
        @{ Case = 'only underscores'; Text = '____'; Expected = '____' }
        @{ Case = 'a longer opening run'; Text = '__a_'; Expected = '_a' }
        @{ Case = 'a longer closing run'; Text = '_a__'; Expected = 'a_' }
        @{ Case = 'three underscores each side'; Text = '___a___'; Expected = 'a' }
        @{ Case = 'brackets inside link text'; Text = '[a [b] c](https://x.invalid/)'; Expected = 'a-b-c' }
        @{ Case = 'an email autolink'; Text = '<user@example.com>'; Expected = 'userexamplecom' }
        @{ Case = 'an HTML comment'; Text = 'Title <!-- note --> end'; Expected = 'title--end' }
        @{ Case = 'a code span of only spaces'; Text = '`   `'; Expected = '---' }
        @{ Case = 'a code span as link text'; Text = '[`]`](https://x.invalid/)'; Expected = '' }
        @{ Case = 'private use characters'; Text = 'a' + [char]0xE05F + 'b' + [char]0xE02D + 'c'; Expected = 'abc' }
        # Review G7: each of these slugged unlike GitHub's rendered text, or threw.
        @{ Case = 'emphasis after a tag'; Text = '<b>a</b>_b_'; Expected = 'ab' }
        @{ Case = 'emphasis after a comment'; Text = 'a<!-- c -->_b_'; Expected = 'ab' }
        @{ Case = 'emphasis after a line break tag'; Text = 'a<br>_b_'; Expected = 'ab' }
        @{ Case = 'underscores in a URL autolink'; Text = '<https://x.invalid/?q=_a_>'; Expected = 'httpsxinvalidq_a_' }
        @{ Case = 'underscores in an email autolink'; Text = '<_a_@example.com>'; Expected = '_a_examplecom' }
        @{ Case = 'underscores after a currency sign'; Text = [string][char]0x20AC + '_a_'; Expected = '_a_' }
        @{ Case = 'underscores after an emoji'; Text = [char]::ConvertFromUtf32(0x1F600) + '_a_'; Expected = '_a_' }
        @{ Case = 'underscores before an emoji'; Text = '_a_' + [char]::ConvertFromUtf32(0x1F600); Expected = '_a_' }
        @{ Case = 'brackets two deep in link text'; Text = '[a [b [c]]](https://x.invalid/)'; Expected = 'a-b-c' }
        @{ Case = 'a > in a quoted attribute'; Text = '<a href="x>y">z</a>'; Expected = 'z' }
        @{ Case = 'a noncharacter before a private use character'; Text = [string][char]0xFDD0 + [char]0xE000; Expected = '' }
        @{ Case = 'another noncharacter before a code span'; Text = [string][char]0xFDD1 + [char]0xE000 + '`x`'; Expected = 'x' }
        @{ Case = '6401 escaped underscores'; Text = '\_' * 6401; Expected = '_' * 6401 }
        @{ Case = 'noncharacters spelling a placeholder'; Text = [string][char]0xFDD0 + '0' + [char]0xFDD1 + ' `x`'; Expected = '0-x' }
        @{ Case = 'an underscore after a symbol inside emphasis'; Text = '_a ' + [char]0x20AC + '_b c_'; Expected = 'a-_b-c' }
    ) {
        ConvertTo-GitHubHeadingAnchor -Text $Text | Should -BeOrdinal $Expected
    }

    It 'slugs a long line of nested underscores quickly' {
        # Review G7: 12 KB of nesting took a pass per level, 2.4 seconds.
        $watch = [System.Diagnostics.Stopwatch]::StartNew()

        $null = ConvertTo-GitHubHeadingAnchor -Text (('_a ' * 2000) + ('b_ ' * 2000))

        $watch.Elapsed.TotalSeconds | Should -BeLessThan 1
    }

    It 'finds the id github.com gives a heading written as <Case>' -ForEach @(
        # Read off a page rendered on github.com on 2026-09-24. Only ATX headings were read,
        # so a link to any of these was reported missing.
        @{ Case = 'a setext heading'; Text = "Setext One`n=========="; Id = 'setext-one' }
        @{ Case = 'a setext heading with dashes'; Text = "Setext Two`n---"; Id = 'setext-two' }
        @{ Case = 'a two-line setext heading'; Text = "Two line`nsetext heading`n=="; Id = 'two-linesetext-heading' }
        @{ Case = 'an indented setext underline'; Text = "Paragraph`n  ==="; Id = 'paragraph' }
        @{ Case = 'a raw HTML heading'; Text = '<h2>Raw Html</h2>'; Id = 'raw-html' }
        @{ Case = 'a raw HTML heading with its own id'; Text = '<h3 id="given">Raw With Id</h3>'; Id = 'raw-with-id' }
        @{ Case = 'a raw HTML heading inside a paragraph'; Text = 'Text before <h4>Inline Raw</h4> after'; Id = 'inline-raw' }
        @{ Case = 'an ATX heading in a quote'; Text = '> ## Quoted Heading'; Id = 'quoted-heading' }
        @{ Case = 'an ATX heading in a list item'; Text = '- ## Listed Heading'; Id = 'listed-heading' }
    ) {
        $readme = '<p align="center"><a href="#' + $Id + '">x</a></p>' + "`n`n" + $Text + "`n"

        @(Test-ReadmeHeaderAnchor -ExpectedReadme $readme) | Should -BeNullOrEmpty
    }

    It 'reads headings beside HTML and inside containers as GitHub does: <Case>' -ForEach @(
        # Review G7, each rendered with GitHub's /markdown API: Ids are the headings it shows,
        # Absent the ones it doesn't. A line opening with an inline tag was taken for an HTML
        # block, blocks that end at a closing marker ended at a blank line, and container and
        # indentation rules were missed.
        @{ Case = 'an inline image before a heading'; Text = "<img src=`"x`"> Title`n## Next"; Ids = @('next'); Absent = @('title') }
        @{ Case = 'inline bold before a heading'; Text = "<b>bold</b> text`n## Heading"; Ids = @('heading'); Absent = @('bold-text') }
        @{ Case = 'inline bold as a setext heading'; Text = "<b>bold</b> text`n==="; Ids = @('bold-text'); Absent = @() }
        @{ Case = 'an inline link before a heading'; Text = "<a href=`"https://x.invalid/`">link</a>`n## After Link"; Ids = @('after-link'); Absent = @('link') }
        @{ Case = 'an inline span before a heading'; Text = "<span>x</span>`n## Y Head"; Ids = @('y-head'); Absent = @('x') }
        @{ Case = 'a less-than before a heading'; Text = "< 5 is less`n## Less"; Ids = @('less'); Absent = @() }
        @{ Case = 'an autolink before a heading'; Text = "<https://x.invalid/>`n## Auto"; Ids = @('auto'); Absent = @() }
        @{ Case = 'a span inside a setext paragraph'; Text = "para`n<span>x</span>`n==="; Ids = @('parax'); Absent = @('para') }
        @{ Case = 'a lone tag inside a setext paragraph'; Text = "para`n<span>`n==="; Ids = @('para'); Absent = @() }
        @{ Case = 'a heading inside pre'; Text = "<pre>`n`n## InPre`n</pre>"; Ids = @(); Absent = @('inpre') }
        @{ Case = 'a heading inside script'; Text = "<script>`n`n## InScript`n</script>"; Ids = @(); Absent = @('inscript') }
        @{ Case = 'a heading inside CDATA'; Text = "<![CDATA[`n`n## InCdata`n]]>"; Ids = @(); Absent = @('incdata') }
        @{ Case = 'indented code on a list item line'; Text = "-     ## Deep"; Ids = @(); Absent = @('deep') }
        @{ Case = 'a heading three spaces into a quote'; Text = ">    ## Quoted4"; Ids = @('quoted4'); Absent = @() }
        @{ Case = 'a quote in a list item'; Text = "- > ## ListQuote"; Ids = @('listquote'); Absent = @() }
        @{ Case = 'a raw heading in indented code'; Text = "para`n`n    <h2>Indented</h2>"; Ids = @(); Absent = @('indented') }
        @{ Case = 'a > in a raw heading attribute'; Text = "<h2 title=`"a>b`">Gt</h2>"; Ids = @('gt'); Absent = @('bgt') }
        @{ Case = 'a raw heading inside an ATX heading'; Text = "## Outer <h3>Inner</h3>"; Ids = @('outer-', 'inner'); Absent = @('outer-inner') }
        @{ Case = 'a raw heading inside a setext heading'; Text = "text <h2>a</h2>`n==="; Ids = @('text-', 'a'); Absent = @('text-a') }
    ) {
        $links = (@($Ids) + @($Absent) | ForEach-Object { '<a href="#' + $_ + '">x</a>' }) -join ' '
        $readme = '<p align="center">' + $links + '</p>' + "`n`n" + $Text + "`n"

        $missing = @(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | ForEach-Object { $_.fragment })

        (@($missing | Sort-Object) -join ' ; ') | Should -BeOrdinal (@($Absent | Sort-Object) -join ' ; ')
    }

    It 'finds no heading id in <Case>' -ForEach @(
        @{ Case = 'a rule after a blank line'; Text = "Para`n`n---"; Id = 'para' }
        @{ Case = 'a rule after a list item'; Text = "- item`n---"; Id = 'item' }
        @{ Case = 'an ATX line inside an HTML block'; Text = "<div>`n## Hidden`n</div>"; Id = 'hidden' }
        @{ Case = 'a raw heading in a code span'; Text = 'See `<h2>Code</h2>` here'; Id = 'code' }
        @{ Case = 'a raw heading in an HTML comment'; Text = '<!-- <h2>Gone</h2> -->'; Id = 'gone' }
        @{ Case = 'a hash with no space'; Text = '#5 not a heading'; Id = '5-not-a-heading' }
    ) {
        $readme = '<p align="center"><a href="#' + $Id + '">x</a></p>' + "`n`n" + $Text + "`n"

        (@(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | ForEach-Object { $_.fragment }) -join ' ; ') | Should -Be $Id
    }

    It 'numbers headings of every form together, in document order' {
        # github.com gave the ATX Same "same" and the setext one after it "same-1".
        $readme = '<p align="center"><a href="#same">a</a> <a href="#same-1">b</a> <a href="#same-2">c</a> <a href="#same-3">d</a></p>' +
            "`n`n## Same`n`nSame`n====`n`n<h2>Same</h2>`n"

        (@(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | ForEach-Object { $_.fragment }) -join ' ; ') | Should -Be 'same-3'

        # A raw Same-1 between two ATX Sames takes same-1 first, so the second Same is same-2;
        # read out of order, it would be same-1 and the raw one same-1-1.
        $readme = '<p align="center"><a href="#same-2">a</a> <a href="#same-1-1">b</a></p>' +
            "`n`n## Same`n`n<h2>Same-1</h2>`n`n## Same`n"

        (@(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | ForEach-Object { $_.fragment }) -join ' ; ') | Should -Be 'same-1-1'
    }

    It 'finds the id GitHub gives a repeated heading and one with a closing run of #' {
        # github.com numbered these same, same-1, same-2 and, since same-1 was taken,
        # same-1-1; the closing ## isn't part of the text.
        $readme = '<p align="center"><a href="#same">a</a> <a href="#same-1">b</a> <a href="#same-2">c</a> <a href="#same-1-1">d</a> <a href="#closed">e</a> <a href="#same-3">f</a></p>' +
            "`n`n## Same`n`n## Same`n`n## Same`n`n## Same-1`n`n## Closed ##`n"

        (@(Test-ReadmeHeaderAnchor -ExpectedReadme $readme | ForEach-Object { $_.fragment }) -join ' ; ') | Should -Be 'same-3'
    }

    It 'deduplicates a repeated external target' {
        $fixture = '<p><a href="https://dup.example/a">one</a> <a href="https://dup.example/a">two</a></p>' + "`n" + $GeneratedCatalogNotice

        @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $fixture) | Should -HaveCount 1
    }
}

Describe 'Release trust shortlist recommends only achievable actions' {
    BeforeAll {
        $script:TrustShortlist = (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw |
            ConvertFrom-Json).releaseAssetDrift.executableDownloadTrustShortlist
    }

    It 'never recommends build-provenance attestation' {
        # Attestation generation needs a GitHub Actions OIDC token and AGENTS.md bans
        # workflows, so recommending it asked for something impossible on every row.
        ($script:TrustShortlist | ConvertTo-Json -Depth 8) | Should -Not -Match 'publish-build-provenance-attestation'
        $script:SyncProfileScript | Should -Not -Match 'publish-build-provenance-attestation'
    }

    It 'records once, at section level, that attestation is unreachable' {
        $script:TrustShortlist.attestationAchievable | Should -BeFalse
        $script:TrustShortlist.attestationUnachievableReason | Should -Match 'OIDC'
        $script:TrustShortlist.attestationUnachievableReason | Should -Match '(?i)no workflows'
    }

    It 'limits nextAction to actions the maintainer can perform' {
        $allowed = @('publish-sha256-checksums', 'enable-immutable-releases', 'publish-sbom', 'no-action-needed')
        foreach ($row in @($script:TrustShortlist.rows)) {
            $allowed | Should -Contain $row.nextAction
        }
    }

    It 'ranks missing checksums above mutable releases' {
        # Checksums are the cheapest real integrity win; immutability is a repo setting.
        $rows = @($script:TrustShortlist.rows)
        $rows.Count | Should -BeGreaterThan 0
        $firstWithChecksum = $rows | Where-Object { $_.hasChecksum } | Select-Object -First 1
        $lastWithout = $rows | Where-Object { -not $_.hasChecksum } | Select-Object -Last 1
        if ($null -ne $firstWithChecksum -and $null -ne $lastWithout) {
            [int]$lastWithout.priorityRank | Should -BeLessThan ([int]$firstWithChecksum.priorityRank)
        }
        foreach ($row in @($rows | Where-Object { -not $_.hasChecksum })) {
            $row.nextAction | Should -Be 'publish-sha256-checksums'
        }
    }

    It 'drops the unreachable tier from the readiness ladder' {
        foreach ($bucket in @($script:TrustShortlist.readinessCounts)) {
            $bucket.readinessLevel | Should -Not -Be 'attestation-metadata'
        }
        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $ladder = $schema.'$defs'.executableDownloadTrustShortlist.properties.readinessCounts.items.properties.readinessLevel.enum
        $ladder | Should -Not -Contain 'attestation-metadata'
        $ladder | Should -Contain 'metadata-complete'
    }

    It 'calls a fully covered immutable release complete' {
        $complete = @($script:TrustShortlist.rows | Where-Object { $_.hasChecksum -and $_.isImmutable -and $_.hasSbom })
        foreach ($row in $complete) {
            $row.readinessLevel | Should -Be 'metadata-complete'
            $row.nextAction | Should -Be 'no-action-needed'
        }
    }
}

Describe 'Dependabot posture defers to the local advisory lane' {
    BeforeAll {
        function script:New-ReviewArtifact {
            param([string]$Path, [string]$Status, [double]$AgeDays)
            $payload = [ordered]@{
                status = $Status
                generatedAt = ([datetimeoffset]::Now.AddDays(-$AgeDays)).ToUniversalTime().ToString('o')
            }
            ($payload | ConvertTo-Json) | Set-Content -LiteralPath $Path -Encoding utf8
            $Path
        }
    }

    It 'raises no warning when Dependabot is disabled and the local review is current' {
        $path = script:New-ReviewArtifact -Path (Join-Path $TestDrive 'fresh.json') -Status 'ok' -AgeDays 0
        $review = Get-LocalAdvisoryReviewPosture -ReviewPath $path

        $review.covering | Should -BeTrue
        $posture = Get-DependabotSecurityPosture -DependabotSecurityUpdates 'disabled' -LocalAdvisoryReview $review

        $posture.warningDisposition | Should -Be 'none'
        $posture.recommendation | Should -Be 'keep-dependabot-disabled-with-local-advisory-review'
        $posture.localAdvisoryReviewCovering | Should -BeTrue
        $posture.localAdvisoryReviewGapReason | Should -BeNullOrEmpty
    }

    It 'raises one compensating-control warning when the local review cannot cover' -ForEach @(
        @{ Case = 'stale'; Status = 'ok'; AgeDays = 9; Match = 'past the 7 day window' }
        @{ Case = 'review-needed'; Status = 'review-needed'; AgeDays = 0; Match = "status 'review-needed'" }
        @{ Case = 'not-run'; Status = 'not-run'; AgeDays = 0; Match = "status 'not-run'" }
    ) {
        $path = script:New-ReviewArtifact -Path (Join-Path $TestDrive "$Case.json") -Status $Status -AgeDays $AgeDays
        $review = Get-LocalAdvisoryReviewPosture -ReviewPath $path

        $review.covering | Should -BeFalse
        $review.gapReason | Should -Match $Match

        $posture = Get-DependabotSecurityPosture -DependabotSecurityUpdates 'disabled' -LocalAdvisoryReview $review
        $posture.warningDisposition | Should -Be 'compensating-control-warning'
        $posture.localAdvisoryReviewCovering | Should -BeFalse
        $posture.nextAction | Should -Match 'npm run review:dependencies'
    }

    It 'treats a missing or unparseable review artifact as no coverage' {
        $missing = Get-LocalAdvisoryReviewPosture -ReviewPath (Join-Path $TestDrive 'absent.json')
        $missing.present | Should -BeFalse
        $missing.covering | Should -BeFalse
        $missing.gapReason | Should -Match 'No local dependency review artifact'

        $badPath = Join-Path $TestDrive 'bad.json'
        'not json' | Set-Content -LiteralPath $badPath -Encoding utf8
        $bad = Get-LocalAdvisoryReviewPosture -ReviewPath $badPath
        $bad.covering | Should -BeFalse
        $bad.gapReason | Should -Match 'could not be parsed'
    }

    It 'never tells the maintainer to enable Dependabot or add its config' {
        $review = Get-LocalAdvisoryReviewPosture -ReviewPath (script:New-ReviewArtifact -Path (Join-Path $TestDrive 'policy.json') -Status 'ok' -AgeDays 0)
        foreach ($state in @('disabled', 'enabled', '')) {
            $posture = Get-DependabotSecurityPosture -DependabotSecurityUpdates $state -LocalAdvisoryReview $review
            $text = ($posture.evidence + ' ' + $posture.nextAction + ' ' + $posture.recommendation)
            $text | Should -Not -Match '(?i)enable dependabot'
            $text | Should -Not -Match '(?i)create .*dependabot'
        }
        # Enabled contradicts policy, so the action is to turn it off.
        (Get-DependabotSecurityPosture -DependabotSecurityUpdates 'enabled' -LocalAdvisoryReview $review).recommendation |
            Should -Be 'disable-dependabot-per-repository-policy'
    }

    It 'persists the review artifact from the validation lane' {
        # The generator treats this file as the compensating-control evidence, so the
        # lane has to write it on every run, not only when a support bundle is requested.
        $validation = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/validate-local.ps1') -Raw
        $validation | Should -Match 'reports/dependency-review\.json'
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot '.gitignore') -Raw) | Should -Match 'reports/dependency-review\.json'
    }
}

Describe 'Topic apply capability reporting' {
    It 'reports the committed allowlist as an available apply mode' {
        $result = Get-TopicApplyCapability

        $result.available | Should -BeTrue
        $result.allowlistedRepositoryCount | Should -Be 12
        $result.unavailableReason | Should -BeNullOrEmpty
    }

    It 'counts a single-entry allowlist as one repository' {
        # ConvertFrom-Json unwraps a one-element array to a bare string, which would
        # misreport a valid single-repository allowlist as malformed.
        $path = Join-Path $TestDrive 'single.json'
        '["AlphaTool"]' | Set-Content -LiteralPath $path -Encoding utf8

        $result = Get-TopicApplyCapability -AllowlistPath $path

        $result.available | Should -BeTrue
        $result.allowlistedRepositoryCount | Should -Be 1
        $result.unavailableReason | Should -BeNullOrEmpty
    }

    It 'reports an actionable reason instead of a bare false' -ForEach @(
        @{ Case = 'absent'; Content = $null; Match = 'not found' }
        @{ Case = 'empty'; Content = '[]'; Match = 'is empty' }
        @{ Case = 'malformed'; Content = 'nope{'; Match = 'not valid JSON' }
        @{ Case = 'object'; Content = '{"a":1}'; Match = 'must be a JSON array' }
        @{ Case = 'bare-string'; Content = '"AlphaTool"'; Match = 'must be a JSON array' }
        @{ Case = 'unsafe'; Content = '["../evil"]'; Match = 'unsafe repository name' }
        # A nested object stringifies to its .NET type name, a bool to "True" and a
        # number to "1", all of which satisfy the safe-name pattern and were counted
        # as real repositories.
        @{ Case = 'object-element'; Content = '[{"name":"a"}]'; Match = 'only repository name strings' }
        @{ Case = 'bool-element'; Content = '[true]'; Match = 'only repository name strings' }
        @{ Case = 'number-element'; Content = '[1,2,3]'; Match = 'only repository name strings' }
        @{ Case = 'null-element'; Content = '["a",null]'; Match = 'only repository name strings' }
        # The apply path matches with -notin, so a duplicate inflates the count without
        # adding a repository it would touch.
        @{ Case = 'duplicate'; Content = '["Repo","Repo"]'; Match = 'duplicate repository names' }
        @{ Case = 'blank-element'; Content = '["Alpha","  "]'; Match = 'blank repository name' }
    ) {
        $path = Join-Path $TestDrive "allowlist-$Case.json"
        if ($null -ne $Content) {
            $Content | Set-Content -LiteralPath $path -Encoding utf8
        }

        $result = Get-TopicApplyCapability -AllowlistPath $path

        $result.available | Should -BeFalse
        $result.allowlistedRepositoryCount | Should -Be 0
        $result.unavailableReason | Should -Match $Match
    }

    It 'keeps the reported capability aligned with what the apply path reads' {
        # Both read data/topic-allowlist.json; a divergence is how the report started
        # describing a capability the tree did not have.
        $script:SyncProfileScript | Should -Match 'applyModeAvailable = \$topicApplyCapability\.available'
        $script:SyncProfileScript | Should -Match 'Get-TopicApplyCapability -AllowlistPath \$TopicAllowlist'
        $script:SyncProfileScript | Should -Not -Match 'applyModeAvailable = \$false'
    }
}

Describe 'Local validation runs the profile check' {
    BeforeAll {
        $script:ValidateLocalPath = Join-Path $script:RepoRoot 'scripts/validate-local.ps1'
        $script:ValidateLocalText = Get-Content -LiteralPath $script:ValidateLocalPath -Raw
        # Load the reporting helper without executing the script body, which would run
        # the whole validation lane.
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:ValidateLocalText, [ref]$null, [ref]$null)
        $definition = $ast.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Get-FailedProfileConditionName'
            }, $true) | Select-Object -First 1
        $definition | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    It 'invokes the generator state check on the default path' {
        # The Pester suite only ever validates the generator against fixtures, so
        # without this call the documented pre-push command validates no catalog,
        # privacy, link, or artifact-sync evidence at all.
        $script:ValidateLocalText | Should -Match 'function Invoke-ProfileCheck'
        $script:ValidateLocalText | Should -Match 'Invoke-ProfileCheck -RepoRoot \$repoRoot'
        $script:ValidateLocalText | Should -Match '"-File", \$scriptPath, "-Check"'
        # Reachable unless explicitly skipped; anything else would put the check
        # behind a flag nobody passes.
        $script:ValidateLocalText | Should -Match 'if \(\$SkipProfileCheck\) \{'
    }

    It 'exposes skip switches and announces a reduced run' {
        $script:ValidateLocalText | Should -Match '\[switch\]\$SkipProfileCheck'
        $script:ValidateLocalText | Should -Match '\[switch\]\$SkipLinkValidation'
        $script:ValidateLocalText | Should -Match 'Skipped lane: profile check'
        $script:ValidateLocalText | Should -Match 'Reduced lane: profile check'
    }

    It 'fails the lane when the child check exits non-zero' {
        # Invoke-ProfileCheck routes through Invoke-NativeCommand, which throws on a
        # non-zero exit code, so a failing generator check stops the whole lane.
        $script:ValidateLocalText | Should -Match 'Invoke-NativeCommand -FilePath \(Get-Command pwsh -ErrorAction Stop\)\.Source -ArgumentList \$arguments'
        $script:ValidateLocalText | Should -Match 'failed with exit code \$LASTEXITCODE'
    }

    It 'names the failing report conditions' {
        $reportPath = Join-Path $TestDrive 'seeded-report.json'
        $report = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw | ConvertFrom-Json
        $report.projectsExportInSync = $false
        $report.medicalPrivacyViolations = @([pscustomobject]@{ repo = 'Seeded'; reason = 'seeded' })
        $report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $reportPath -Encoding utf8

        $failed = @(Get-FailedProfileConditionName -ReportPath $reportPath)

        $failed | Should -Contain 'projectsExportInSync'
        $failed | Should -Contain 'medicalPrivacyViolations'
        $failed | Should -Not -Contain 'readmeInSync'
    }

    It 'reports nothing for the committed healthy report' {
        @(Get-FailedProfileConditionName -ReportPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json')) | Should -HaveCount 0
    }

    It 'stays quiet instead of throwing when the report is missing or unreadable' {
        @(Get-FailedProfileConditionName -ReportPath (Join-Path $TestDrive 'absent-report.json')) | Should -HaveCount 0

        $badPath = Join-Path $TestDrive 'unparseable-report.json'
        'not json at all' | Set-Content -LiteralPath $badPath -Encoding utf8
        @(Get-FailedProfileConditionName -ReportPath $badPath) | Should -HaveCount 0
    }
}

Describe 'Redacted local support bundles' -Tag 'Integration' {
    BeforeAll {
        $script:SupportBundleScriptPath = Join-Path $script:RepoRoot 'scripts/new-support-bundle.ps1'
    }

    It 'writes a ZIP manifest and evidence set without private names, paths, or tokens' {
        $inputRoot = Join-Path $TestDrive 'support-input'
        New-Item -ItemType Directory -Path $inputRoot | Out-Null
        $validationPath = Join-Path $inputRoot 'validation.log'
        $reportPath = Join-Path $inputRoot 'report.json'
        $dependencyPath = Join-Path $inputRoot 'dependency.json'
        $transcriptPath = Join-Path $inputRoot 'setup.log'
        @'
Validation failed at C:\Users\Alice\PrivateRepo.
Authorization: Bearer ghp_private_token_value
'@ | Set-Content -LiteralPath $validationPath -Encoding utf8
        @'
{"repo":"https://github.com/private-owner/PrivateRepo","secret":"do-not-export","path":"C:\Users\Alice\PrivateRepo"}
'@ | Set-Content -LiteralPath $reportPath -Encoding utf8
        @'
{"status":"review-needed","access_token":"github_pat_private_value"}
'@ | Set-Content -LiteralPath $dependencyPath -Encoding utf8
        @'
setup saw PrivateRepo at C:\Users\Alice\PrivateRepo
'@ | Set-Content -LiteralPath $transcriptPath -Encoding utf8

        $outputPath = Join-Path $TestDrive 'SysAdminDoc-support.zip'
        $commandOutput = & pwsh -NoProfile -File $script:SupportBundleScriptPath `
            -OutputPath $outputPath `
            -RepoRoot $script:RepoRoot `
            -ValidationOutputPath $validationPath `
            -ProfileReportPath $reportPath `
            -DependencyReviewPath $dependencyPath `
            -SetupTranscriptPath $transcriptPath `
            -ValidationStatus failed `
            -RedactValue 'PrivateRepo,private-owner,Alice' *>&1

        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $outputPath | Should -BeTrue

        Add-Type -AssemblyName System.IO.Compression
        $archive = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
        try {
            $entries = @($archive.Entries)
            $entries.FullName | Should -Contain 'manifest.json'
            $entries.FullName | Should -Contain 'evidence/validation-output.txt'
            $manifestEntry = $entries | Where-Object FullName -eq 'manifest.json'
            $manifestReader = [System.IO.StreamReader]::new($manifestEntry.Open())
            try {
                $manifest = $manifestReader.ReadToEnd() | ConvertFrom-Json
            } finally {
                $manifestReader.Dispose()
            }

            $manifest.schemaVersion | Should -Be 'sysadmindoc-support-bundle.v1'
            $manifest.validationStatus | Should -Be 'failed'
            $manifest.redaction.applied | Should -BeTrue
            @($manifest.evidence).Count | Should -Be 4

            $evidenceText = foreach ($entry in $entries | Where-Object FullName -like 'evidence/*') {
                $reader = [System.IO.StreamReader]::new($entry.Open())
                try {
                    $reader.ReadToEnd()
                } finally {
                    $reader.Dispose()
                }
            }
            $combined = $evidenceText -join "`n"
            $combined | Should -Match '<REDACTED_'
            $combined | Should -Not -Match 'PrivateRepo|private-owner|Alice|ghp_private_token_value|github_pat_private_value|do-not-export'
            $combined | Should -Not -Match 'C:\\Users\\Alice'
        } finally {
            $archive.Dispose()
        }
    }

    It 'writes JSON when the output extension is json' {
        $inputPath = Join-Path $TestDrive 'validation.log'
        'token=ghp_json_secret' | Set-Content -LiteralPath $inputPath -Encoding utf8
        $outputPath = Join-Path $TestDrive 'SysAdminDoc-support.json'

        & pwsh -NoProfile -File $script:SupportBundleScriptPath `
            -OutputPath $outputPath `
            -RepoRoot $script:RepoRoot `
            -ValidationOutputPath $inputPath `
            -RedactValue 'ghp_json_secret' | Out-Null

        $LASTEXITCODE | Should -Be 0
        $bundle = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $bundle.redaction.applied | Should -BeTrue
        ($bundle.evidence | Where-Object name -eq 'validation-output.txt').content | Should -Not -Match 'ghp_json_secret'
        ($bundle.evidence | Where-Object name -eq 'validation-output.txt').content | Should -Match '<REDACTED_'
    }

    It 'redacts quoted user paths that contain spaces' {
        $inputPath = Join-Path $TestDrive 'space-path-validation.log'
        @'
Found config at "C:\Users\John Smith\AppData\Local\secret.conf"
Also at 'C:\Users\Jane Doe\Desktop\data.txt'
'@ | Set-Content -LiteralPath $inputPath -Encoding utf8
        $outputPath = Join-Path $TestDrive 'SysAdminDoc-space-path.json'

        & pwsh -NoProfile -File $script:SupportBundleScriptPath `
            -OutputPath $outputPath `
            -RepoRoot $script:RepoRoot `
            -ValidationOutputPath $inputPath `
            -RedactValue 'secret' | Out-Null

        $LASTEXITCODE | Should -Be 0
        $bundle = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $content = ($bundle.evidence | Where-Object name -eq 'validation-output.txt').content
        $content | Should -Not -Match 'John Smith'
        $content | Should -Not -Match 'Jane Doe'
        $content | Should -Match '<REDACTED_USER_PATH>'
    }

    It 'does not produce a replacement character when truncating multi-byte UTF-8' {
        $inputPath = Join-Path $TestDrive 'multibyte-validation.log'
        $multibyte = ('x' * 90) + [char]0x00E9 + ('y' * 10)
        $multibyte | Set-Content -LiteralPath $inputPath -Encoding utf8
        $outputPath = Join-Path $TestDrive 'SysAdminDoc-multibyte.json'

        & pwsh -NoProfile -File $script:SupportBundleScriptPath `
            -OutputPath $outputPath `
            -RepoRoot $script:RepoRoot `
            -ValidationOutputPath $inputPath `
            -Format Json | Out-Null

        $LASTEXITCODE | Should -Be 0
        $bundle = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $content = ($bundle.evidence | Where-Object name -eq 'validation-output.txt').content
        $content | Should -Not -Match ([char]0xFFFD)
    }
}

Describe 'Local dependency advisory review' -Tag 'Integration' {
    BeforeAll {
        $script:DependencyReviewScriptPath = Join-Path $script:RepoRoot 'scripts/review-local-dependencies.ps1'
        $script:DependencyReviewScript = Get-Content -LiteralPath $script:DependencyReviewScriptPath -Raw
        $script:DependencyReviewPackage = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'package.json') | ConvertFrom-Json -AsHashtable
        # The dependency review is contributor documentation, kept in CONTRIBUTING.md.
        $script:DependencyReviewReadme = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.github/CONTRIBUTING.md')
    }

    It 'documents a local dependency review command without hosted automation' {
        Test-Path -LiteralPath $script:DependencyReviewScriptPath | Should -BeTrue
        $script:DependencyReviewPackage.scripts['review:dependencies'] | Should -Be 'pwsh -NoProfile -File ./scripts/review-local-dependencies.ps1'
        $script:DependencyReviewReadme | Should -Match 'npm run review:dependencies'
        $script:DependencyReviewReadme | Should -Match 'manual dependency and advisory review'
        $script:DependencyReviewReadme | Should -Match 'package override drift'
        # Wording follows the registry-backed freshness model that replaced the
        # hand-edited latest-known map; the old phrase described evidence that is gone.
        $script:DependencyReviewReadme | Should -Match 'resolves every pin against the npm and PyPI registries'
        $script:DependencyReviewReadme | Should -Match 'npm audit signatures'
        $script:DependencyReviewReadme | Should -Match 'ignore-scripts=true'
        $script:DependencyReviewScript | Should -Match 'compatibilityLanes'
        $script:DependencyReviewScript | Should -Match 'Pester6CompatibilityVersion'
        $script:DependencyReviewReadme | Should -Match 'Pester 6 compatibility lane'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/dependabot.yml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/tests.yml') | Should -BeFalse
    }

    It 'reports npm audit status, override drift, PowerShell pins, and hash-pinned audit tools' {
        $auditPath = Join-Path ([System.IO.Path]::GetTempPath()) ('SysAdminDoc-npm-audit-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $auditJson = @'
{
  "metadata": {
    "vulnerabilities": {
      "info": 0,
      "low": 0,
      "moderate": 0,
      "high": 0,
      "critical": 0,
      "total": 0
    },
    "dependencies": {
      "prod": 0,
      "dev": 1,
      "optional": 0,
      "peer": 0,
      "peerOptional": 0,
      "total": 1
    }
  }
}
'@
            [System.IO.File]::WriteAllText($auditPath, $auditJson, [System.Text.UTF8Encoding]::new($false))

            # A fresh registry answer in the test drive: the run stays offline and leaves the
            # checkout's .cache/registry-versions.json to the validation lane that owns it.
            $cachePath = Join-Path $TestDrive 'fresh-registry-cache.json'
            ([ordered]@{
                fetchedAt = ([datetimeoffset]::Now).ToString('o')
                packages = [ordered]@{
                    'npm/markdownlint-cli2' = '0.23.2'
                    'npm/js-yaml' = '5.2.2'
                    'npm/markdown-it' = '14.3.0'
                    'python/zizmor' = '1.29.0'
                }
            } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $cachePath -Encoding utf8

            $output = & pwsh -NoProfile -File $script:DependencyReviewScriptPath -NpmAuditJsonPath $auditPath -SkipNpmSignatures `
                -OfflineRegistry -RegistryCachePath $cachePath
            $LASTEXITCODE | Should -Be 0
            $report = ($output -join "`n") | ConvertFrom-Json

            $report.status | Should -Be 'ok'
            $report.policy | Should -Be 'manual-local-only'
            $report.commands.full | Should -Match 'review-local-dependencies[.]ps1'
            $report.pinFreshness.warningCount | Should -Be 0
            $report.npm.audit.status | Should -Be 'clean'
            $report.npm.audit.severityCounts.total | Should -Be 0
            $report.npm.overrides.count | Should -BeGreaterThan 0
            $report.npm.overrides.rows.package | Should -Contain 'js-yaml'
            $report.npm.overrides.rows.package | Should -Contain 'markdown-it'
            ($report.npm.overrides.rows | Where-Object { $_.package -eq 'js-yaml' }).status | Should -Be 'aligned'
            $report.npm.devDependencyPins.package | Should -Contain 'markdownlint-cli2'
            ($report.npm.devDependencyPins | Where-Object { $_.package -eq 'markdownlint-cli2' }).status | Should -Be 'aligned'
            # currentCompatible is the version actually resolved; registryLatest is what
            # the registry serves today. The old assertions read a hand-edited map that
            # reported every pin as current long after npm had moved on.
            $markdownlintFreshness = $report.pinFreshness.npm.rows | Where-Object { $_.name -eq 'markdownlint-cli2' }
            $markdownlintFreshness.currentCompatible | Should -Be '0.23.2'
            $markdownlintFreshness.declaredByParent | Should -Be '0.23.2'
            $markdownlintFreshness.compatibilityStatus | Should -BeIn @('current', 'behind-registry-latest', 'major-upgrade-available')
            $jsYamlFreshness = $report.pinFreshness.npm.rows | Where-Object { $_.name -eq 'js-yaml' }
            $jsYamlFreshness.currentCompatible | Should -Be '5.2.2'
            $jsYamlFreshness.registryLatest | Should -Not -BeNullOrEmpty
            $markdownItFreshness = $report.pinFreshness.npm.rows | Where-Object { $_.name -eq 'markdown-it' }
            $markdownItFreshness.currentCompatible | Should -Be '14.3.0'
            $markdownItFreshness.registryLatest | Should -Not -BeNullOrEmpty
            $report.powershell.requiredModules.name | Should -Contain 'Pester'
            $report.powershell.requiredModules.name | Should -Contain 'PSScriptAnalyzer'
            ($report.powershell.requiredModules | Where-Object { $_.name -eq 'Pester' }).requiredVersion | Should -Be '5.9.1'
            $report.python.auditTools.name | Should -Contain 'zizmor'
            ($report.python.auditTools | Where-Object { $_.name -eq 'zizmor' }).hashPinned | Should -BeTrue
            $zizmorFreshness = $report.pinFreshness.python.rows | Where-Object { $_.name -eq 'zizmor' }
            $zizmorFreshness.currentCompatible | Should -Be '1.29.0'
            $zizmorFreshness.registryLatest | Should -Not -BeNullOrEmpty
        } finally {
            if (Test-Path -LiteralPath $auditPath) {
                Remove-Item -LiteralPath $auditPath -Force
            }
        }
    }

    It 'warns but does not fail when the cached registry evidence is stale' {
        $auditPath = Join-Path ([System.IO.Path]::GetTempPath()) ('SysAdminDoc-npm-audit-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $auditJson = @'
{
  "metadata": {
    "vulnerabilities": {
      "info": 0,
      "low": 0,
      "moderate": 0,
      "high": 0,
      "critical": 0,
      "total": 0
    },
    "dependencies": {
      "prod": 0,
      "dev": 1,
      "optional": 0,
      "peer": 0,
      "peerOptional": 0,
      "total": 1
    }
  }
}
'@
            [System.IO.File]::WriteAllText($auditPath, $auditJson, [System.Text.UTF8Encoding]::new($false))

            # Staleness is no longer a hand-entered date. It is the age of the cached
            # registry answer, so the fixture is an aged cache read under -OfflineRegistry.
            $cachePath = Join-Path $TestDrive 'aged-registry-cache.json'
            ([ordered]@{
                fetchedAt = ([datetimeoffset]::Now.AddDays(-120)).ToString('o')
                packages = [ordered]@{
                    'npm/markdownlint-cli2' = '0.23.2'
                    'npm/js-yaml' = '5.2.2'
                    'npm/markdown-it' = '14.3.0'
                    'python/zizmor' = '1.29.0'
                }
            } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $cachePath -Encoding utf8

            $output = & pwsh -NoProfile -File $script:DependencyReviewScriptPath -NpmAuditJsonPath $auditPath `
                -SkipNpmSignatures -OfflineRegistry -RegistryCachePath $cachePath
            $LASTEXITCODE | Should -Be 0
            $report = ($output -join "`n") | ConvertFrom-Json

            $report.status | Should -Be 'ok'
            $report.pinFreshness.status | Should -Be 'stale'
            $report.pinFreshness.evidenceSource | Should -Be 'cache'
            $report.pinFreshness.warningCount | Should -BeGreaterThan 0
            $report.pinFreshness.warnings[0] | Should -Match 'past the 30 day window'
        } finally {
            if (Test-Path -LiteralPath $auditPath) {
                Remove-Item -LiteralPath $auditPath -Force
            }
        }
    }

    It 'returns a non-zero exit when dependency review needs action' {
        $auditPath = Join-Path ([System.IO.Path]::GetTempPath()) ('SysAdminDoc-npm-audit-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $auditJson = @'
{
  "metadata": {
    "vulnerabilities": {
      "info": 0,
      "low": 0,
      "moderate": 1,
      "high": 0,
      "critical": 0,
      "total": 1
    },
    "dependencies": {
      "prod": 0,
      "dev": 1,
      "optional": 0,
      "peer": 0,
      "peerOptional": 0,
      "total": 1
    }
  }
}
'@
            [System.IO.File]::WriteAllText($auditPath, $auditJson, [System.Text.UTF8Encoding]::new($false))

            $output = & pwsh -NoProfile -File $script:DependencyReviewScriptPath -NpmAuditJsonPath $auditPath -SkipNpmSignatures `
                -OfflineRegistry -RegistryCachePath (Join-Path $TestDrive 'needs-action-registry-cache.json') *>&1
            $LASTEXITCODE | Should -Be 1
            $report = ($output -join "`n") | ConvertFrom-Json

            $report.status | Should -Be 'review-needed'
            $report.npm.audit.status | Should -Be 'vulnerabilities-found'
            $report.npm.audit.severityCounts.moderate | Should -Be 1
        } finally {
            if (Test-Path -LiteralPath $auditPath) {
                Remove-Item -LiteralPath $auditPath -Force
            }
        }
    }

    It 'still fails local pin drift when npm audit is skipped' {
        $root = Join-Path $TestDrive 'dependency-review-drift'
        New-Item -ItemType Directory -Path $root | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'scripts') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'requirements-local-audit.txt') -Destination (Join-Path $root 'requirements-local-audit.txt')
        @'
{
  "name": "drift-fixture",
  "private": true,
  "devDependencies": {
    "markdownlint-cli2": "0.22.1"
  },
  "overrides": {
    "js-yaml": "4.2.0"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $root 'package.json') -Encoding utf8
        @'
{
  "lockfileVersion": 3,
  "packages": {
    "": {},
    "node_modules/markdownlint-cli2": {
      "version": "0.22.1"
    },
    "node_modules/js-yaml": {
      "version": "4.1.0"
    }
  }
}
'@ | Set-Content -LiteralPath (Join-Path $root 'package-lock.json') -Encoding utf8
        '$requiredModules = @([pscustomobject]@{ Name = "Pester"; Version = "5.9.1" })' |
            Set-Content -LiteralPath (Join-Path $root 'scripts/validate-local.ps1') -Encoding utf8

        $output = & pwsh -NoProfile -File $script:DependencyReviewScriptPath -RepoRoot $root -SkipNpmAudit -SkipNpmSignatures *>&1
        $LASTEXITCODE | Should -Be 1
        $report = ($output -join "`n") | ConvertFrom-Json

        $report.status | Should -Be 'review-needed'
        $report.npm.audit.status | Should -Be 'skipped'
        $report.npm.overrides.driftCount | Should -Be 1
    }
}

Describe 'npm supply-chain defaults are committed and enforced' {
    BeforeAll {
        $script:ReviewScriptPath = Join-Path $script:RepoRoot 'scripts/review-local-dependencies.ps1'
        $script:ValidationScriptPath = Join-Path $script:RepoRoot 'scripts/validate-local.ps1'
        $script:NpmrcPath = Join-Path $script:RepoRoot '.npmrc'

        # Dot-sourced here rather than through a helper: a helper would define the
        # functions in its own scope and the tests would never see them.
        $wanted = @(
            @{ Path = $script:ReviewScriptPath; Names = @('Get-NpmSignatureCount', 'ConvertTo-NpmSignatureReview', 'ConvertTo-NpmProvenanceRow', 'Get-MemberOrProperty') }
            @{ Path = $script:ValidationScriptPath; Names = @('Get-NpmSupplyChainPosture', 'Assert-NpmSupplyChainDefaults') }
        )
        foreach ($source in $wanted) {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-Content -LiteralPath $source.Path -Raw), [ref]$null, [ref]$null)
            foreach ($name in $source.Names) {
                $definition = $ast.FindAll(
                    {
                        param($node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
                    }, $true) | Select-Object -First 1
                $definition | Should -Not -BeNullOrEmpty -Because "$name must exist in $($source.Path)"
                . ([scriptblock]::Create($definition.Extent.Text))
            }
        }

        # Verbatim npm 11.17.0 output. Held as fixtures so the parser is exercised against
        # the wording npm actually prints, singular forms included.
        $script:CleanSignatureText = @'
audited 86 packages in 0s

86 packages have verified registry signatures

2 packages have verified attestations
(use --json --include-attestations to view attestation details)
'@
        $script:TamperedSignatureText = @'
audited 86 packages in 1s

85 packages have verified registry signatures

1 package has an invalid registry signature:

markdown-it@14.3.0 (https://registry.npmjs.org)

Someone might have tampered with this package since it was published on the registry!
'@
        $script:MissingSignatureText = @'
audited 86 packages in 1s

84 packages have verified registry signatures

2 packages have missing registry signatures but the registry is providing signing keys:

js-yaml@5.2.2 (https://registry.npmjs.org)
markdown-it@14.3.0 (https://registry.npmjs.org)
'@
    }

    It 'commits the three supply-chain settings rather than relying on npm defaults' {
        Test-Path -LiteralPath $script:NpmrcPath | Should -BeTrue -Because 'a clone must inherit the settings, not the operator memory of them'
        $npmrc = Get-Content -LiteralPath $script:NpmrcPath -Raw
        $npmrc | Should -Match '(?m)^ignore-scripts=true$'
        $npmrc | Should -Match '(?m)^audit-level=high$'
        $npmrc | Should -Match '(?m)^min-release-age=1$'
    }

    It 'records the counts from a clean signature run' {
        $review = ConvertTo-NpmSignatureReview -RawText $script:CleanSignatureText -ExitCode 0 -Source 'file'

        $review.status | Should -Be 'verified'
        $review.verifiedCount | Should -Be 86
        $review.attestationCount | Should -Be 2
        $review.invalidCount | Should -Be 0
        $review.missingCount | Should -Be 0
        @($review.offendingPackages) | Should -HaveCount 0
    }

    It 'fails on a tampered signature and names the package' {
        $review = ConvertTo-NpmSignatureReview -RawText $script:TamperedSignatureText -ExitCode 1 -Source 'file'

        $review.status | Should -Be 'signature-mismatch'
        $review.invalidCount | Should -Be 1
        $review.verifiedCount | Should -Be 85
        @($review.offendingPackages) | Should -Contain 'markdown-it@14.3.0'
    }

    It 'separates a missing signature from a mismatched one' {
        # A package the registry never signed is a gap; a package whose signature does not
        # verify is a tampering signal. Both stop the review, and the report says which.
        $review = ConvertTo-NpmSignatureReview -RawText $script:MissingSignatureText -ExitCode 1 -Source 'file'

        $review.status | Should -Be 'signatures-missing'
        $review.missingCount | Should -Be 2
        $review.invalidCount | Should -Be 0
        @($review.offendingPackages) | Should -HaveCount 2
    }

    It 'reports an empty or failed run as unavailable rather than clean' {
        (ConvertTo-NpmSignatureReview -RawText '' -ExitCode $null -Source 'file').status | Should -Be 'unavailable'
        (ConvertTo-NpmSignatureReview -RawText 'npm error code ENOTFOUND' -ExitCode 1 -Source 'local').status | Should -Be 'unavailable'
    }

    It 'reads the singular wording npm uses for a single package' {
        Get-NpmSignatureCount -Body '1 package has an invalid registry signature:' -Subject 'invalid registry signatures?' |
            Should -Be 1
        Get-NpmSignatureCount -Body '1 package has a missing registry signature but the registry is providing signing keys:' -Subject 'missing registry signatures?' |
            Should -Be 1
    }

    It 'fails the whole dependency review when a signature does not verify' {
        # The end-to-end proof: the parser verdict has to reach the exit code, or the
        # review stays green while npm is telling us a package was tampered with.
        $fixture = Join-Path $TestDrive 'tampered-signatures.txt'
        Set-Content -LiteralPath $fixture -Value $script:TamperedSignatureText -Encoding utf8

        $output = & (Get-Command pwsh).Source -NoProfile -File $script:ReviewScriptPath `
            -NpmSignatureTextPath $fixture -SkipNpmAudit -OfflineRegistry -RegistryCachePath (Join-Path $TestDrive 'signature-registry-cache.json') 2>&1
        $exitCode = $LASTEXITCODE
        $review = ($output | Out-String) | ConvertFrom-Json

        $exitCode | Should -Be 1
        $review.status | Should -Be 'review-needed'
        $review.npm.signatures.status | Should -Be 'signature-mismatch'
    }

    It 'passes the review and records the counts on a clean signature fixture' {
        $fixture = Join-Path $TestDrive 'clean-signatures.txt'
        Set-Content -LiteralPath $fixture -Value $script:CleanSignatureText -Encoding utf8

        $output = & (Get-Command pwsh).Source -NoProfile -File $script:ReviewScriptPath `
            -NpmSignatureTextPath $fixture -SkipNpmAudit -OfflineRegistry -RegistryCachePath (Join-Path $TestDrive 'signature-registry-cache.json') 2>&1
        $exitCode = $LASTEXITCODE
        $review = ($output | Out-String) | ConvertFrom-Json

        $exitCode | Should -Be 0
        $review.status | Should -Not -Be 'review-needed'
        $review.npm.signatures.status | Should -Be 'verified'
        $review.npm.signatures.verifiedCount | Should -Be 86
        $review.npm.signatures.attestationCount | Should -Be 2
    }

    It 'enumerates every direct dependency at its locked version' {
        # Offline, so the row set and the version resolution are proved without depending
        # on the registry being reachable; the live signature answer is an Integration test.
        $output = & (Get-Command pwsh).Source -NoProfile -File $script:ReviewScriptPath -SkipNpmAudit -SkipNpmSignatures -OfflineRegistry -RegistryCachePath (Join-Path $TestDrive 'provenance-registry-cache.json') 2>&1
        $review = ($output | Out-String) | ConvertFrom-Json
        $rows = @($review.npm.provenance.rows)

        @($rows | ForEach-Object { $_.name }) | Should -Be @('js-yaml', 'markdown-it', 'markdownlint-cli2', 'smol-toml')
        @($rows | Where-Object { $_.source -eq 'devDependency' }).name | Should -Be 'markdownlint-cli2'
        foreach ($row in $rows) {
            $row.installedVersion | Should -Not -BeNullOrEmpty
            $row.registrySignature | Should -Be 'unknown'
            $row.status | Should -Be 'unknown'
        }
        $review.npm.provenance.unknownCount | Should -Be $rows.Count
    }

    It 'distinguishes an attested package from a merely signed one' {
        $attested = ConvertTo-NpmProvenanceRow -Name 'sigstore' -Source 'devDependency' -RequestedVersion '1.0.0' `
            -InstalledVersion '1.0.0' -Dist ([pscustomobject]@{ signatures = @(@{ keyid = 'abc' }); attestations = @{ url = 'https://registry.npmjs.org/-/npm/v1/attestations/sigstore@1.0.0' } })
        $attested.registrySignature | Should -Be 'present'
        $attested.provenanceAttestation | Should -Be 'present'
        $attested.status | Should -Be 'signed'

        $signedOnly = ConvertTo-NpmProvenanceRow -Name 'js-yaml' -Source 'override' -RequestedVersion '5.2.2' `
            -InstalledVersion '5.2.2' -Dist ([pscustomobject]@{ signatures = @(@{ keyid = 'abc' }) })
        $signedOnly.provenanceAttestation | Should -Be 'absent'
        $signedOnly.status | Should -Be 'signed'

        $unsigned = ConvertTo-NpmProvenanceRow -Name 'legacy' -Source 'override' -RequestedVersion '1.0.0' `
            -InstalledVersion '1.0.0' -Dist ([pscustomobject]@{ shasum = 'deadbeef' })
        $unsigned.registrySignature | Should -Be 'absent'
        $unsigned.status | Should -Be 'unsigned'

        $offline = ConvertTo-NpmProvenanceRow -Name 'legacy' -Source 'override' -RequestedVersion '1.0.0' `
            -InstalledVersion '1.0.0' -Dist $null
        $offline.status | Should -Be 'unknown' -Because 'no registry answer is not the same as no signature'
    }

    It 'asks npm what it resolved instead of trusting the committed file' {
        $npm = Get-Command npm -ErrorAction Stop
        $posture = Get-NpmSupplyChainPosture -NpmPath $npm.Source -RepoRoot $script:RepoRoot

        $posture.status | Should -Be 'enforced'
        @($posture.settings | Where-Object { $_.key -eq 'ignore-scripts' }).actual | Should -Be 'true'
        @($posture.settings | Where-Object { $_.key -eq 'audit-level' }).actual | Should -Be 'high'
    }

    It 'stops the install when an environment override turns ignore-scripts back off' {
        # Planting the violation the committed file cannot see: npm merges env config over
        # .npmrc, so a green lane here would mean lifecycle scripts ran anyway.
        $npm = Get-Command npm -ErrorAction Stop
        $previous = $env:npm_config_ignore_scripts
        try {
            $env:npm_config_ignore_scripts = 'false'
            $posture = Get-NpmSupplyChainPosture -NpmPath $npm.Source -RepoRoot $script:RepoRoot

            $posture.status | Should -Be 'overridden'
            @($posture.violations) | Should -Not -BeNullOrEmpty
            { Assert-NpmSupplyChainDefaults -NpmPath $npm.Source -RepoRoot $script:RepoRoot 3>$null } |
                Should -Throw -ExpectedMessage '*not running with the committed supply-chain settings*'
        } finally {
            if ($null -eq $previous) {
                Remove-Item Env:npm_config_ignore_scripts -ErrorAction SilentlyContinue
            } else {
                $env:npm_config_ignore_scripts = $previous
            }
        }
    }

    It 'runs the settings check before npm ci, not after' {
        $validation = Get-Content -LiteralPath $script:ValidationScriptPath -Raw
        $gateIndex = $validation.IndexOf('Assert-NpmSupplyChainDefaults -NpmPath')
        $installIndex = $validation.IndexOf('-ArgumentList @("ci")')

        $gateIndex | Should -BeGreaterThan 0
        $installIndex | Should -BeGreaterThan 0
        $gateIndex | Should -BeLessThan $installIndex -Because 'checking after the install has already run the scripts is not a control'
    }
}

Describe 'Registry signatures verified against the live registry' -Tag 'Integration' {
    BeforeAll {
        $script:ReviewScriptPath = Join-Path $script:RepoRoot 'scripts/review-local-dependencies.ps1'
    }

    It 'confirms npm verifies every installed package and that direct dependencies are signed' {
        $output = & (Get-Command pwsh).Source -NoProfile -File $script:ReviewScriptPath -SkipNpmAudit -RegistryCachePath (Join-Path $TestDrive 'live-registry-cache.json') 2>&1
        $review = ($output | Out-String) | ConvertFrom-Json

        $review.npm.signatures.status | Should -Be 'verified'
        $review.npm.signatures.invalidCount | Should -Be 0
        $review.npm.signatures.missingCount | Should -Be 0
        $review.npm.signatures.verifiedCount | Should -BeGreaterThan 0

        $rows = @($review.npm.provenance.rows)
        $rows.Count | Should -Be 4
        foreach ($row in $rows) {
            $row.registrySignature | Should -Be 'present' -Because "$($row.name)@$($row.installedVersion) must carry a registry signature"
            $row.provenanceAttestation | Should -BeIn @('present', 'absent')
        }
        $review.npm.provenance.unknownCount | Should -Be 0
    }
}

Describe 'Script test seams need the suite opt-in' {
    BeforeDiscovery {
        $seamScripts = @(
            'setup.ps1'
            'scripts/validate-local.ps1'
            'scripts/review-local-dependencies.ps1'
            'scripts/write-profile-sync-summary.ps1'
            'scripts/render-profile-smoke.ps1'
            'scripts/new-support-bundle.ps1'
        )
    }

    # Each case copies the script's real seam line in front of a marker line, so it checks the
    # condition that ships without running the script itself.
    It '<_> still runs its main body when dot-sourced outside the suite' -ForEach $seamScripts {
        $scriptPath = Join-Path $script:RepoRoot $_
        $seam = @(Get-Content -LiteralPath $scriptPath | Where-Object { $_ -match "^if \(\`$MyInvocation\.InvocationName -(eq|ne) '\.'" })
        $seam | Should -HaveCount 1
        $probeLines = if ($seam[0].TrimEnd().EndsWith('{')) { @($seam[0], "    Write-Output 'MAIN-BODY'", '}') } else { @($seam[0], "Write-Output 'MAIN-BODY'") }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
        $probe = Join-Path $TestDrive "$name-seam.ps1"
        $wrapper = Join-Path $TestDrive "$name-iex-wrapper.ps1"
        Set-Content -LiteralPath $probe -Value $probeLines -Encoding utf8
        Set-Content -LiteralPath $wrapper -Value "Get-Content -Raw -LiteralPath '$probe' | Invoke-Expression" -Encoding utf8

        $suiteValue = $env:SYSADMINDOC_TEST_SEAM
        try {
            Remove-Item -LiteralPath Env:SYSADMINDOC_TEST_SEAM -ErrorAction SilentlyContinue
            @(. $probe) | Should -Be @('MAIN-BODY') -Because 'an editor F5 dot-sources the script and must still run it'
            @(. $wrapper) | Should -Be @('MAIN-BODY') -Because 'irm | iex inside a dot-sourced script or profile sees that script''s invocation name'
            @(& $probe) | Should -Be @('MAIN-BODY')

            $env:SYSADMINDOC_TEST_SEAM = '1'
            @(. $probe) | Should -BeNullOrEmpty -Because 'the suite dot-sources the script to load its functions only'
            @(& $probe) | Should -Be @('MAIN-BODY') -Because 'the opt-in alone must not stop a script that was not dot-sourced'
        } finally {
            $env:SYSADMINDOC_TEST_SEAM = $suiteValue
        }
    }

    It 'keeps the generator seam a plain dot-source check' {
        # render-profile-smoke.ps1 dot-sources sync-profile.ps1 as a library in normal use, so
        # gating this seam on the suite variable would run the whole generator there.
        $seam = @(Get-Content -LiteralPath $script:SyncProfileScriptPath | Where-Object { $_ -match '^if \(\$MyInvocation\.InvocationName' })
        $seam | Should -Be @("if (`$MyInvocation.InvocationName -eq '.') { return }")
        Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/render-profile-smoke.ps1') -Raw |
            Should -Match '(?m)^\. \(Join-Path \$PSScriptRoot "sync-profile\.ps1"\)'
    }
}

# The Describe blocks below dot-source the other production scripts so code coverage can
# see them. Each script stops at its test seam (the suite sets SYSADMINDOC_TEST_SEAM=1 in
# its top-level BeforeAll), so nothing is installed, no npm or browser runs, and no report is
# read or written. They load into their own Describe scope, and the
# render-smoke block (which dot-sources the generator again) stays last in the file.

Describe 'Summary writer helpers (in-process)' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -ReportPath (Join-Path $TestDrive 'no-report.json') -SummaryPath (Join-Path $TestDrive 'no-summary.md')
    }

    It 'loads without reading a report or writing a summary' {
        Test-Path -LiteralPath (Join-Path $TestDrive 'no-summary.md') | Should -BeFalse
    }

    It 'counts null, single values and collections' {
        Get-Count $null | Should -Be 0
        Get-Count 'one' | Should -Be 1
        Get-Count @(1, 2, 3) | Should -Be 3
    }

    It 'compacts values for summary cells' {
        ConvertTo-CompactSummaryValue $null | Should -Be 'null'
        ConvertTo-CompactSummaryValue "a`n   b" | Should -Be 'a b'
        ConvertTo-CompactSummaryValue ([ordered]@{ k = 1 }) | Should -Be '{"k":1}'
        ConvertTo-CompactSummaryValue ('x' * 300) -MaxLength 10 | Should -Be 'xxxxxxx...'
    }

    It 'escapes Markdown table cells' {
        ConvertTo-MarkdownCell "a|b`r`nc" | Should -Be 'a\|b c'
        ConvertTo-MarkdownCell '   ' | Should -Be ''
    }

    It 'encodes GitHub workflow command values and properties' {
        ConvertTo-GitHubAnnotationValue "50%`r`nnext" | Should -Be '50%25%0D%0Anext'
        ConvertTo-GitHubAnnotationValue $null | Should -Be ''
        ConvertTo-GitHubAnnotationProperty 'file:a,b' | Should -Be 'file%3Aa%2Cb'
    }

    It 'reads optional report properties with a default' {
        $object = [pscustomobject]@{ present = 'value'; empty = $null }
        Get-ObjectPropertyOrDefault -Object $object -Name 'present' -Default 'fallback' | Should -Be 'value'
        Get-ObjectPropertyOrDefault -Object $object -Name 'missing' -Default 'fallback' | Should -Be 'fallback'
        Get-ObjectPropertyOrDefault -Object $object -Name 'empty' -Default 'fallback' | Should -Be 'fallback'
        Get-ObjectPropertyOrDefault -Object $null -Name 'present' -Default 'fallback' | Should -Be 'fallback'
    }
}

Describe 'Dependency review helpers (in-process)' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'scripts/review-local-dependencies.ps1') -RepoRoot $script:RepoRoot
    }

    It 'classifies a pin against the registry latest without forcing majors' {
        Test-CompatibleWithLatest -CurrentVersion '1.2.3' -RegistryLatest '1.2.3' | Should -Be 'current'
        Test-CompatibleWithLatest -CurrentVersion '1.2.3' -RegistryLatest '1.3.0' | Should -Be 'behind-registry-latest'
        Test-CompatibleWithLatest -CurrentVersion '14.3.0' -RegistryLatest '15.0.1' | Should -Be 'major-upgrade-available'
        Test-CompatibleWithLatest -CurrentVersion '2.0.0' -RegistryLatest '1.9.9' | Should -Be 'ahead-of-registry-latest'
        Test-CompatibleWithLatest -CurrentVersion '1.0.0' -RegistryLatest '' | Should -Be 'unknown'
        Test-CompatibleWithLatest -CurrentVersion 'next' -RegistryLatest '1.0.0' | Should -Be 'behind-registry-latest'
    }

    It 'reads npm signature tallies from the audit summary text' {
        $body = "audited 120 packages in 1s`n118 packages have verified registry signatures`n2 packages have missing registry signatures"
        Get-NpmSignatureCount -Body $body -Subject 'verified registry signatures' | Should -Be 118
        Get-NpmSignatureCount -Body $body -Subject 'missing registry signatures' | Should -Be 2
        Get-NpmSignatureCount -Body $body -Subject 'invalid registry signatures' | Should -Be 0
    }

    It 'reads map values and counts with defaults' {
        Get-MapValue -Map @{ a = 1 } -Key 'a' | Should -Be 1
        Get-MapValue -Map @{ a = 1 } -Key 'b' -Default 'none' | Should -Be 'none'
        Get-MapValue -Map 'not a map' -Key 'a' -Default 'none' | Should -Be 'none'
        ConvertTo-Count $null | Should -Be 0
        ConvertTo-Count '7' | Should -Be 7
    }

    It 'marks registry evidence stale past its window and missing evidence unavailable' {
        $now = [datetimeoffset]'2026-09-22T00:00:00Z'
        $fresh = New-PinFreshnessRow -Name 'pkg' -Kind 'npm-override' -CurrentVersion '1.0.0' -RegistryLatest '1.0.0' -LatestCheckedAt '2026-09-20T00:00:00Z' -Now $now -StaleAfterDays 30
        $stale = New-PinFreshnessRow -Name 'pkg' -Kind 'npm-override' -CurrentVersion '1.0.0' -RegistryLatest '2.0.0' -LatestCheckedAt '2026-07-01T00:00:00Z' -Now $now -StaleAfterDays 30
        $unknown = New-PinFreshnessRow -Name 'pkg' -Kind 'npm-override' -CurrentVersion '1.0.0' -RegistryLatest '' -LatestCheckedAt '' -Now $now -StaleAfterDays 30

        $fresh.freshnessStatus | Should -Be 'fresh'
        $fresh.warning | Should -BeNullOrEmpty
        $stale.freshnessStatus | Should -Be 'stale'
        $stale.compatibilityStatus | Should -Be 'major-upgrade-available'
        $stale.warning | Should -Match '83 day'
        $unknown.freshnessStatus | Should -Be 'unavailable'
        $unknown.registryLatest | Should -BeNullOrEmpty
    }

    It 'refuses a missing JSON input by name' {
        { Get-JsonHashtable -Path (Join-Path $TestDrive 'absent.json') } | Should -Throw '*Required JSON file not found*'
    }

    It 'reads npm audit counts and calls the result clean only when advisories came back empty' {
        $clean = '{"auditReportVersion":2,"vulnerabilities":{},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0},"dependencies":{"prod":1,"dev":339,"optional":2,"peer":0,"peerOptional":0,"total":341}}}'
        $found = '{"auditReportVersion":2,"vulnerabilities":{"example":{}},"metadata":{"vulnerabilities":{"info":0,"low":1,"moderate":0,"high":2,"critical":0,"total":3},"dependencies":{"prod":1,"dev":10,"optional":0,"peer":0,"peerOptional":0,"total":11}}}'

        $cleanReview = ConvertTo-NpmAuditReview -RawJson $clean -ExitCode 0 -Source 'local'
        $cleanReview.status | Should -Be 'clean'
        $cleanReview.exitCode | Should -Be 0
        $cleanReview.dependencyCounts.dev | Should -Be 339
        $cleanReview.dependencyCounts.total | Should -Be 341

        $foundReview = ConvertTo-NpmAuditReview -RawJson $found -ExitCode 1 -Source 'file'
        $foundReview.status | Should -Be 'vulnerabilities-found'
        $foundReview.source | Should -Be 'file'
        $foundReview.severityCounts.low | Should -Be 1
        $foundReview.severityCounts.high | Should -Be 2
        $foundReview.severityCounts.total | Should -Be 3
        $foundReview.note | Should -Match 'Review npm advisory details'
    }

    It 'never reads a failed npm audit as clean' {
        # What npm 10 prints with loglevel=silent when the advisory request fails (exit 1).
        $failed = '{"message":"request to http://127.0.0.1:9/-/npm/v1/security/advisories/bulk failed, reason: connect ECONNREFUSED 127.0.0.1:9","error":{"summary":"","detail":""}}'
        $review = ConvertTo-NpmAuditReview -RawJson $failed -ExitCode 1 -Source 'local'
        $review.status | Should -Be 'unavailable'
        $review.exitCode | Should -Be 1
        $review.note | Should -Match 'ECONNREFUSED'
        $review.severityCounts.total | Should -Be 0

        # Older npm names the failure only in error.summary.
        $older = ConvertTo-NpmAuditReview -RawJson '{"error":{"code":"ENOAUDIT","summary":"Your configured registry does not support audit requests.","detail":""}}' -ExitCode 1 -Source 'file'
        $older.status | Should -Be 'unavailable'
        $older.note | Should -Match 'does not support audit requests'

        (ConvertTo-NpmAuditReview -RawJson '{}' -ExitCode 0 -Source 'file').status | Should -Be 'unavailable'
        (ConvertTo-NpmAuditReview -RawJson '[]' -ExitCode 0 -Source 'file').status | Should -Be 'unavailable'
        (ConvertTo-NpmAuditReview -RawJson '{"metadata":{"dependencies":{"total":5}}}' -ExitCode 0 -Source 'file').status | Should -Be 'unavailable'
        # A counts block with no counts in it is not a clean audit either.
        (ConvertTo-NpmAuditReview -RawJson '{"metadata":{"vulnerabilities":{}}}' -ExitCode 0 -Source 'file').status | Should -Be 'unavailable'
        (ConvertTo-NpmAuditReview -RawJson '{"metadata":{"vulnerabilities":{"total":null}}}' -ExitCode 0 -Source 'file').status | Should -Be 'unavailable'
        (ConvertTo-NpmAuditReview -RawJson '{"metadata":{"vulnerabilities":{"unexpected":1}}}' -ExitCode 0 -Source 'file').status | Should -Be 'unavailable'
    }

    It 'finds vulnerabilities that only the severities or the advisory map report' {
        # Older npm and other package managers report severities without a total.
        $noTotal = ConvertTo-NpmAuditReview -RawJson '{"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":2,"critical":0}}}' -ExitCode 1 -Source 'file'
        $noTotal.status | Should -Be 'vulnerabilities-found'
        $noTotal.severityCounts.high | Should -Be 2

        # A per-package advisory entry outranks a zero tally.
        $listed = ConvertTo-NpmAuditReview -RawJson '{"auditReportVersion":2,"vulnerabilities":{"left-pad":{"severity":"high"}},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}}}' -ExitCode 1 -Source 'file'
        $listed.status | Should -Be 'vulnerabilities-found'
    }

    It 'compares each npm override with the version the lockfile resolved' {
        $packageJson = @{ overrides = [ordered]@{ 'markdown-it' = '14.3.0'; 'left-pad' = '1.3.0'; 'js-yaml' = '5.2.2' } }
        $packageLock = @{
            packages = @{
                'node_modules/js-yaml' = @{ version = '5.2.2' }
                'node_modules/markdown-it' = @{ version = '14.1.0' }
            }
        }

        $review = Get-PackageOverrideReview -PackageJson $packageJson -PackageLock $packageLock

        $review.count | Should -Be 3
        $review.driftCount | Should -Be 2
        @($review.rows | ForEach-Object { $_.package }) | Should -Be @('js-yaml', 'left-pad', 'markdown-it')
        $byName = @{}
        foreach ($row in $review.rows) { $byName[$row.package] = $row }
        $byName['js-yaml'].status | Should -Be 'aligned'
        $byName['markdown-it'].status | Should -Be 'lock-drift'
        $byName['markdown-it'].overrideVersion | Should -Be '14.3.0'
        $byName['markdown-it'].lockedVersion | Should -Be '14.1.0'
        $byName['left-pad'].status | Should -Be 'missing-lock-entry'
        $byName['left-pad'].lockedVersion | Should -Be ''
    }

    It 'treats a package without overrides as nothing to review' {
        $review = Get-PackageOverrideReview -PackageJson @{ name = 'x' } -PackageLock @{ packages = @{} }

        $review.count | Should -Be 0
        $review.driftCount | Should -Be 0
        @($review.rows) | Should -HaveCount 0
    }

    It 'keeps missing and unparseable audit output apart' {
        $empty = ConvertTo-NpmAuditReview -RawJson '' -ExitCode $null -Source 'local'
        $empty.status | Should -Be 'unavailable'
        $empty.note | Should -Be 'npm audit did not return JSON.'

        $broken = ConvertTo-NpmAuditReview -RawJson "npm error code ENOLOCK`n{" -ExitCode 1 -Source 'local'
        $broken.status | Should -Be 'invalid-json'
        $broken.severityCounts.total | Should -Be 0
    }
}

Describe 'Local validation helpers (in-process)' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'scripts/validate-local.ps1')
    }

    It 'maps PowerShell versions to support channels' {
        Get-PowerShellRuntimeChannel -Version '5.1' -Edition 'Desktop' | Should -Be 'windows-powershell-bootstrap-only'
        Get-PowerShellRuntimeChannel -Version '7.3.9' | Should -Be 'unsupported'
        Get-PowerShellRuntimeChannel -Version '7.4.19' | Should -Be 'previous-lts'
        Get-PowerShellRuntimeChannel -Version '7.5.3' | Should -Be 'stable-non-lts'
        Get-PowerShellRuntimeChannel -Version '7.6.6' | Should -Be 'current-lts'
        Get-PowerShellRuntimeChannel -Version '7.7.0' | Should -Be 'newer-than-current-lts'
    }

    It 'names the failing report conditions and tolerates a missing or unreadable report' {
        $reportPath = Join-Path $TestDrive 'report.json'
        [ordered]@{
            readmeInSync = $true
            projectsExportInSync = $false
            profileAssetsInSync = $true
            missingPublicRepos = @('NewRepo')
            linkValidationFailures = @()
        } | ConvertTo-Json | Set-Content -LiteralPath $reportPath -Encoding utf8
        Set-Content -LiteralPath (Join-Path $TestDrive 'broken.json') -Value '{not json' -Encoding utf8

        @(Get-FailedProfileConditionName -ReportPath $reportPath) | Should -Be @('projectsExportInSync', 'missingPublicRepos')
        @(Get-FailedProfileConditionName -ReportPath (Join-Path $TestDrive 'absent.json')) | Should -BeNullOrEmpty
        @(Get-FailedProfileConditionName -ReportPath (Join-Path $TestDrive 'broken.json')) | Should -BeNullOrEmpty
    }

    It 'finds the reviewed lock record for a pinned module and refuses an unreviewed one' {
        $entry = Get-ModuleLockEntry -RepoRoot $script:RepoRoot -Name 'Pester' -Version '5.9.1'
        $entry.nupkgSha256 | Should -Match '^[a-fA-F0-9]{64}$'
        { Get-ModuleLockEntry -RepoRoot $script:RepoRoot -Name 'Pester' -Version '0.0.1' } | Should -Throw '*No reviewed lock record*'
    }

    It 'names instrumented files that the tests never executed' {
        $coverage = [pscustomobject]@{
            FilesAnalyzed = @('C:\repo\a.ps1', 'C:\repo\b.ps1', 'C:\repo\c.ps1')
            CommandsExecuted = @([pscustomobject]@{ File = 'C:\REPO\A.ps1' }, [pscustomobject]@{ File = 'C:\repo\c.ps1' })
        }

        @(Get-UncoveredCoverageFile -Coverage $coverage) | Should -Be @('C:\repo\b.ps1')
        @(Get-UncoveredCoverageFile -Coverage $null) | Should -BeNullOrEmpty
    }

    It 'fails the lane when an instrumented file has no executed command' {
        $validation = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/validate-local.ps1') -Raw
        $validation | Should -Match 'Join-Path \$repoRoot "scripts"'
        $validation | Should -Match 'Join-Path \$repoRoot "setup\.ps1"'
        $validation | Should -Match 'Join-Path \$repoRoot "run\.ps1"'
        $validation | Should -Match '\$uncoveredFiles = @\(Get-UncoveredCoverageFile -Coverage \$coverage\)'
        $validation | Should -Match 'Code coverage recorded no executed command in'
    }

    It 'surfaces a failing native command' {
        $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        { Invoke-NativeCommand -FilePath $pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'exit 3') } | Should -Throw '*failed with exit code 3*'
    }

    It 'names every file a run added, changed or removed in the checkout, and nothing else' {
        # The AST guards only see the child-run forms they know; this sees any write.
        $root = Join-Path $TestDrive 'checkout-state'
        foreach ($folder in '.cache', 'reports', '.git', 'node_modules', '.claude') {
            New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force | Out-Null
        }
        Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'readme'
        Set-Content -LiteralPath (Join-Path $root 'reports/profile-sync-report.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path $root '.cache/registry-versions.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path $root 'coverage.xml') -Value 'old'
        $before = Get-CheckoutFileState -RepoRoot $root

        Set-Content -LiteralPath (Join-Path $root 'reports/profile-sync-report.json') -Value '{"rewritten":true}'
        Set-Content -LiteralPath (Join-Path $root '.cache/run.lock') -Value ''
        Remove-Item -LiteralPath (Join-Path $root 'README.md')
        Set-Content -LiteralPath (Join-Path $root 'coverage.xml') -Value 'new coverage'
        foreach ($toolFile in '.git/index', 'node_modules/x.js', '.claude/settings.local.json') {
            Set-Content -LiteralPath (Join-Path $root $toolFile) -Value 'tool state'
        }
        $after = Get-CheckoutFileState -RepoRoot $root

        Compare-CheckoutFileState -Before $before -After $after -Allowed @('coverage.xml') |
            Should -Be @('added .cache/run.lock', 'changed reports/profile-sync-report.json', 'removed README.md')
        Compare-CheckoutFileState -Before $before -After $before | Should -BeNullOrEmpty
    }

    It 'names a checkout file it cannot read instead of stopping' {
        # A file held open without read sharing made File.Open throw, so the lane died on the
        # exception instead of reporting what the run changed.
        $root = Join-Path $TestDrive 'checkout-state-locked'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $locked = Join-Path $root 'locked.txt'
        Set-Content -LiteralPath $locked -Value 'held'
        Set-Content -LiteralPath (Join-Path $root 'other.txt') -Value 'other'
        $holder = [System.IO.File]::Open($locked, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $state = Get-CheckoutFileState -RepoRoot $root -WarningVariable warnings 3>$null
        } finally {
            $holder.Dispose()
        }

        $state['locked.txt'] | Should -Be 'unreadable'
        $state['other.txt'] | Should -Match '^[0-9A-F]{64}$'
        @($warnings) | Should -HaveCount 1
        [string]$warnings[0] | Should -Match 'locked\.txt'
        # Readable again with other bytes, it shows as changed.
        Set-Content -LiteralPath $locked -Value 'changed'
        (@(Compare-CheckoutFileState -Before $state -After (Get-CheckoutFileState -RepoRoot $root)) -join ' ; ') | Should -Be 'changed locked.txt'
    }

    It 'sees a same-size rewrite with its time put back, a case-only rename and a new directory, and walks no junction' {
        # Size and write time missed the first; a case-insensitive table the second; files
        # alone the third; and a junction back to the root would have looped the walk.
        $root = Join-Path $TestDrive 'checkout-state-subtle'
        New-Item -ItemType Directory -Path (Join-Path $root 'reports') -Force | Out-Null
        $report = Join-Path $root 'reports/profile-sync-report.json'
        Set-Content -LiteralPath $report -Value 'aaaa' -NoNewline
        Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'readme'
        $loop = Join-Path $root 'loop'
        New-Item -ItemType Junction -Path $loop -Target $root | Out-Null
        try {
            $before = Get-CheckoutFileState -RepoRoot $root
            $writeTime = (Get-Item -LiteralPath $report).LastWriteTimeUtc

            Set-Content -LiteralPath $report -Value 'bbbb' -NoNewline
            (Get-Item -LiteralPath $report).LastWriteTimeUtc = $writeTime
            Rename-Item -LiteralPath (Join-Path $root 'README.md') -NewName 'readme.md'
            New-Item -ItemType Directory -Path (Join-Path $root '.cache/profile-sync') -Force | Out-Null
            $after = Get-CheckoutFileState -RepoRoot $root

            @($before.Keys | Where-Object { $_ -like 'loop*' }) | Should -BeNullOrEmpty -Because 'the junction is not followed'
            Compare-CheckoutFileState -Before $before -After $after |
                Should -Be @('added .cache/', 'added .cache/profile-sync/', 'added readme.md', 'changed reports/profile-sync-report.json', 'removed README.md')
        } finally {
            # Pester's TestDrive cleanup follows a junction, so a loop left here ran it until
            # the path was too long, and the framework error failed every test after this
            # one. Deleting the link itself doesn't follow it.
            [System.IO.Directory]::Delete($loop)
        }
    }

    It 'fails the lane when the test run writes into the checkout' {
        $validation = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/validate-local.ps1') -Raw
        $snapshot = $validation.IndexOf('$checkoutBefore = Get-CheckoutFileState -RepoRoot $repoRoot')
        $run = $validation.IndexOf('$pesterResult = Invoke-Pester -Configuration $pesterConfig')
        $compare = $validation.IndexOf('Compare-CheckoutFileState -Before $checkoutBefore -After (Get-CheckoutFileState -RepoRoot $repoRoot) -Allowed @(''coverage.xml'')')

        $snapshot | Should -BeGreaterThan -1
        $run | Should -BeGreaterThan $snapshot
        $compare | Should -BeGreaterThan $run
        $validation | Should -Match 'throw \$checkoutWriteText'
    }
}

Describe 'Support bundle helpers (in-process)' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'scripts/new-support-bundle.ps1') -OutputPath (Join-Path $TestDrive 'never-written.zip')
    }

    It 'loads without writing a bundle' {
        Test-Path -LiteralPath (Join-Path $TestDrive 'never-written.zip') | Should -BeFalse
    }

    It 'redacts user paths, tokens, secrets, query credentials and caller values' {
        $text = 'C:\Users\Alice\repo "C:\Users\Bob Smith\x" ghp_abc123 Bearer tok.en password=hunter2 https://h/?token=abc PrivateRepoName'
        $redacted = ConvertTo-RedactedSupportText -Text $text -AdditionalValues @('PrivateRepoName')

        $redacted | Should -Not -Match 'Alice|Bob Smith|ghp_abc123|tok\.en|hunter2|token=abc|PrivateRepoName'
        $redacted | Should -Match '<REDACTED_USER_PATH>'
        $redacted | Should -Match '<REDACTED_TOKEN>'
        $redacted | Should -Match '<REDACTED_SECRET>'
        $redacted | Should -Match '<REDACTED_QUERY_VALUE>'
        $redacted | Should -Match '<REDACTED_VALUE>'
    }

    It 'redacts the token prefixes gh itself hands out' {
        # gh auth token returns gho_ for an OAuth login; ghu_, ghs_ and ghr_ come from apps.
        foreach ($token in @('gho_ABCDEFGHIJKLMNOPQRST1234', 'ghu_ABCDEFGHIJKLMNOPQRST1234', 'ghs_ABCDEFGHIJKLMNOPQRST1234', 'ghr_ABCDEFGHIJKLMNOPQRST1234')) {
            $redacted = ConvertTo-RedactedSupportText -Text "token $token end"
            $redacted | Should -Be 'token <REDACTED_TOKEN> end' -Because $token
        }
    }

    It 'rejects an invalid caller redaction pattern' {
        { ConvertTo-RedactedSupportText -Text 'x' -AdditionalPatterns @('(') } | Should -Throw '*Invalid support-bundle redaction pattern*'
    }

    It 'truncates oversized input on a UTF-8 boundary' {
        $text = ('a' * 1023) + ([string][char]0x00E9) + 'tail'
        $limited = Limit-SupportText -Text $text -MaxBytes 1024

        $limited | Should -Match 'truncated at 1024 bytes'
        $limited | Should -Not -Match ([string][char]0xFFFD)
        $limited.StartsWith('a' * 1023) | Should -BeTrue
        Limit-SupportText -Text 'short' -MaxBytes 1024 | Should -Be 'short'
    }

    It 'writes the bundle JSON with its redaction contract and evidence in order' {
        $evidence = @(
            [pscustomobject]@{ name = 'validation output'; status = 'included'; bytes = 29; content = 'ran in <REDACTED_USER_PATH>'; redacted = $true }
            [pscustomobject]@{ name = 'setup transcript'; status = 'not-provided'; bytes = 0; content = 'No setup transcript was supplied.'; redacted = $true }
        )

        $raw = Get-SupportBundleJson -ValidationStatus 'passed' -ToolVersions @{ pwsh = '7.6.6'; git = $null } -Evidence $evidence -IncludeContent $true
        $bundle = $raw | ConvertFrom-Json

        $bundle.schemaVersion | Should -Be 'sysadmindoc-support-bundle.v1'
        $bundle.validationStatus | Should -Be 'passed'
        $raw | Should -Match '"generatedAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}(Z|\+00:00)"'
        $bundle.redaction.applied | Should -BeTrue
        $bundle.redaction.userPaths | Should -Be '<REDACTED_USER_PATH>'
        $bundle.redaction.tokens | Should -Be '<REDACTED_TOKEN>'
        $bundle.redaction.secrets | Should -Be '<REDACTED_SECRET>'
        $bundle.redaction.callerValues | Should -Be '<REDACTED_VALUE>'
        $bundle.redaction.queryValues | Should -Be '<REDACTED_QUERY_VALUE>'
        $bundle.toolVersions.pwsh | Should -Be '7.6.6'
        @($bundle.evidence | ForEach-Object { $_.name }) | Should -Be @('validation output', 'setup transcript')
        $bundle.evidence[0].content | Should -Be 'ran in <REDACTED_USER_PATH>'
        $bundle.evidence[0].bytes | Should -Be 29
        $bundle.evidence[1].status | Should -Be 'not-provided'
    }

    It 'leaves evidence content out when asked and keeps a single item a list' {
        $one = [pscustomobject]@{ name = 'validation output'; status = 'included'; bytes = 5; content = 'SECRET-LOOKING TEXT'; redacted = $true }

        $raw = Get-SupportBundleJson -ValidationStatus 'failed' -ToolVersions @{} -Evidence @($one) -IncludeContent $false
        $bundle = $raw | ConvertFrom-Json

        $bundle.validationStatus | Should -Be 'failed'
        $raw | Should -Match '"evidence":\s*\['
        $raw | Should -Not -Match 'SECRET-LOOKING TEXT'
        @($bundle.evidence) | Should -HaveCount 1
        $bundle.evidence[0].PSObject.Properties.Name | Should -Not -Contain 'content'
        $bundle.evidence[0].redacted | Should -BeTrue
    }
}

Describe 'Setup bootstrapper helpers (in-process)' {
    BeforeAll {
        # The seam stops before anything is checked or installed. Install-Pkg,
        # Update-PathFromRegistry and the transcript helpers change the machine or the
        # session and are not called here.
        . (Join-Path $script:RepoRoot 'setup.ps1')
        $script:MissingCommand = 'sysadmindoc-no-such-command-' + [guid]::NewGuid().ToString('N')
    }

    It 'detects commands on PATH' {
        Test-Cmd 'pwsh' | Should -BeTrue
        Test-Cmd $script:MissingCommand | Should -BeFalse
    }

    It 'reads a version line only for installed tools' {
        Get-VersionLine $script:MissingCommand | Should -BeNullOrEmpty
        [string](Get-VersionLine 'pwsh') | Should -Match '7\.\d+'
    }

    It 'reports a tool status as present or missing' {
        Write-ToolStatus 'pwsh' 'pwsh' 6>$null | Should -BeTrue
        Write-ToolStatus 'none' $script:MissingCommand 6>$null | Should -BeFalse
    }

    It 'stops setup with the message it prints' {
        { Stop-SetupWithFailure 'setup cannot continue' 6>$null } | Should -Throw 'setup cannot continue'
    }

    It 'answers the elevation question with a boolean' {
        Test-Admin | Should -BeOfType ([bool])
    }

    It 'prints status lines without failing' {
        { & { Write-Step 'step'; Write-Ok 'ok'; Write-Skip 'skip'; Write-Warn2 'warn' } 6>$null } | Should -Not -Throw
    }
}

Describe 'No test starts the real gh' {
    It 'puts the trap first on PATH' {
        (Get-Command gh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source | Should -Be (Join-Path $script:GhTrapDirectory 'gh.cmd')
    }

    It 'left the gh trap untouched' {
        # A call here means a test reached for GitHub without a mock, a stub or -Offline.
        # (A review once took a stubbed gh's rate-limit warning for a live call; this is
        # the check that tells the two apart.)
        $calls = if (Test-Path -LiteralPath $script:GhTrapLog) { @(Get-Content -LiteralPath $script:GhTrapLog) } else { @() }

        $calls | Should -BeNullOrEmpty -Because 'the suite stays offline'
    }
}

Describe 'Rendered smoke helpers (in-process)' {
    BeforeAll {
        # Loads the helpers only: the seam stops before the output directory is created or a
        # browser starts. Invoke-RenderedSmoke is never called here.
        . (Join-Path $script:RepoRoot 'scripts/render-profile-smoke.ps1') -OutputDir (Join-Path $TestDrive 'never-created')
        # That dot-source ran the generator's entry again, which reset $script:Offline from
        # its own -Offline parameter ($false); put the suite back offline.
        $script:Offline = $true
    }

    It 'loads without creating the output directory' {
        Test-Path -LiteralPath (Join-Path $TestDrive 'never-created') | Should -BeFalse
        Get-Command Invoke-RenderedSmoke -CommandType Function | Should -Not -BeNullOrEmpty
    }

    It 'renders the profile of the owner it is given unless a URL is named' {
        $smokeScript = Join-Path $script:RepoRoot 'scripts/render-profile-smoke.ps1'
        $outputDir = Join-Path $TestDrive 'never-created'
        try {
            # Each dot-source runs in its own child scope, so each binds its own parameters.
            $default = & { . $smokeScript -OutputDir $outputDir; $Url }
            $forOwner = & { . $smokeScript -Owner 'FixtureOwner' -OutputDir $outputDir; $Url }
            $named = & { . $smokeScript -Owner 'FixtureOwner' -Url 'https://example.test/profile' -OutputDir $outputDir; $Url }
        } finally {
            # The generator's entry ran again in each dot-source and reset the run settings.
            $script:Offline = $true
        }

        $default | Should -Be 'https://github.com/SysAdminDoc'
        $forOwner | Should -Be 'https://github.com/FixtureOwner'
        $named | Should -Be 'https://example.test/profile'
    }

    It 'writes the smoke artifact without touching a sync report outside its directory' {
        $resolvedOutputDir = Join-Path $TestDrive 'smoke-out'
        $currentDirectory = Join-Path $TestDrive 'no-repo'
        New-Item -ItemType Directory -Path $resolvedOutputDir, $currentDirectory -Force | Out-Null

        $artifact = Write-RenderedSmokeArtifact -Report ([ordered]@{ status = 'passed'; viewports = @() })

        $artifact | Should -Be (Join-Path $resolvedOutputDir 'rendered-profile-smoke.json')
        (Get-Content -LiteralPath $artifact -Raw | ConvertFrom-Json).status | Should -Be 'passed'
        Test-Path -LiteralPath (Join-Path $currentDirectory 'reports') | Should -BeFalse
    }

    It 'removes only its own temporary browser profile directories' {
        $foreign = Join-Path $TestDrive 'not-a-smoke-profile'
        New-Item -ItemType Directory -Path $foreign | Out-Null
        $own = Join-Path ([System.IO.Path]::GetTempPath()) ('SysAdminDoc-render-smoke-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $own | Out-Null
        try {
            Remove-RenderedSmokeProfileDir -Path $foreign 3>$null
            Remove-RenderedSmokeProfileDir -Path $own

            Test-Path -LiteralPath $foreign | Should -BeTrue -Because 'a directory without the smoke profile name must be left alone'
            Test-Path -LiteralPath $own | Should -BeFalse
            { Remove-RenderedSmokeProfileDir -Path $null } | Should -Not -Throw
        } finally {
            Remove-Item -LiteralPath $own -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Assertions on invisible characters compare them exactly' {
    BeforeAll {
        # True when the text builds a character a reader can't see: with [char]0x.. or
        # [char]<decimal>, [char]::ConvertFromUtf32 of either, "`u{..}", or written into the
        # source as it is; a lone surrogate counts.
        function script:Test-BuildsInvisibleCharacter {
            param([string]$Text)
            foreach ($match in [regex]::Matches($Text, '\[char\]\s*(?:0x(?<hex>[0-9A-Fa-f]{1,6})|(?<dec>\d{1,7}))(?![0-9A-Za-z])|ConvertFromUtf32\(\s*(?:0x(?<hex>[0-9A-Fa-f]{1,6})|(?<dec>\d{1,7}))\s*\)|`u\{(?<hex>[0-9A-Fa-f]{1,6})\}')) {
                $codePoint = if ($match.Groups['hex'].Success) { [Convert]::ToInt32($match.Groups['hex'].Value, 16) } else { [int]$match.Groups['dec'].Value }
                if ($codePoint -ge 0xD800 -and $codePoint -le 0xDFFF) { return $true }
                if ($codePoint -le 0x10FFFF -and -not (Test-VisibleText ([char]::ConvertFromUtf32($codePoint)))) { return $true }
            }
            foreach ($rune in $Text.EnumerateRunes()) {
                if ($rune.Value -gt 0x7E -and -not (Test-VisibleText $rune.ToString())) { return $true }
            }
            return $false
        }

        # Where an assertion's expected value can come from: its test (body and -ForEach data),
        # each Describe or Context around it (data, BeforeAll and BeforeEach) and the file's own
        # BeforeAll.
        function script:Get-AssertionContext {
            param($Should)
            $isSetup = { param($node) $node -is [System.Management.Automation.Language.CommandAst] -and @('beforeall', 'beforeeach').Contains(([string]$node.GetCommandName()).ToLowerInvariant()) }
            for ($node = $Should.Parent; $null -ne $node; $node = $node.Parent) {
                if ($node -is [System.Management.Automation.Language.CommandAst]) {
                    $command = ([string]$node.GetCommandName()).ToLowerInvariant()
                    if ('it'.Equals($command)) { $node }
                    elseif (@('describe', 'context').Contains($command)) {
                        @($node.CommandElements | Where-Object { $_ -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst] })
                        @($node.FindAll($isSetup, $true))
                    }
                }
                if ($null -eq $node.Parent) { @($node.FindAll($isSetup, $false)) }
            }
        }

        # True when the expression is built from an invisible character, directly or through
        # what the names it reads are given in its context: an assignment, or a hashtable or
        # -ForEach entry of that name ($Expected, $_.Expected), three steps deep.
        function script:Test-ExpressionBuildsInvisible {
            param($Expression, [object[]]$Contexts, [int]$Depth = 0)
            if ($null -eq $Expression -or $Depth -gt 3) { return $false }
            if (script:Test-BuildsInvisibleCharacter $Expression.Extent.Text) { return $true }
            $names = @($Expression.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] -or ($node -is [System.Management.Automation.Language.MemberExpressionAst] -and $node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) }, $true) | ForEach-Object {
                    if ($_ -is [System.Management.Automation.Language.VariableExpressionAst]) { $_.VariablePath.UserPath -replace '^(?i:script|local|private|global):', '' } else { $_.Member.Value }
                } | Select-Object -Unique)
            foreach ($name in $names) {
                if (@('_', 'psitem', 'true', 'false', 'null').Contains($name.ToLowerInvariant())) { continue }
                foreach ($context in $Contexts) {
                    foreach ($assignment in $context.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                        $left = $assignment.Left
                        while ($left -is [System.Management.Automation.Language.AttributedExpressionAst]) { $left = $left.Child }
                        if ($left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                            [string]::Equals(($left.VariablePath.UserPath -replace '^(?i:script|local|private|global):', ''), $name, [StringComparison]::OrdinalIgnoreCase) -and
                            (script:Test-ExpressionBuildsInvisible -Expression $assignment.Right -Contexts $Contexts -Depth ($Depth + 1))) { return $true }
                    }
                    foreach ($table in $context.FindAll({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true)) {
                        foreach ($pair in $table.KeyValuePairs) {
                            if ([string]::Equals($pair.Item1.Extent.Text.Trim([char[]]"'`""), $name, [StringComparison]::OrdinalIgnoreCase) -and
                                (script:Test-ExpressionBuildsInvisible -Expression $pair.Item2 -Contexts $Contexts -Depth ($Depth + 1))) { return $true }
                        }
                    }
                }
            }
            return $false
        }

        # Every Should -Be, -BeExactly, -Contain, -BeIn, -BeLike or -BeLikeExactly (and the -EQ
        # and -CEQ aliases, and -ExpectedValue after any of them) that compares by culture where
        # an invisible character can be: an expected value built from one, or a string written
        # out as the expected value in a test that builds one anywhere, which the actual value
        # may then hold. A value from a helper's return is left to review.
        function script:Find-CultureComparedInvisible {
            param($Ast)
            $shoulds = $Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and [string]::Equals($node.GetCommandName(), 'Should', [StringComparison]::OrdinalIgnoreCase) }, $true)
            foreach ($should in $shoulds) {
                $elements = @($should.CommandElements)
                for ($index = 1; $index -lt $elements.Count; $index++) {
                    $element = $elements[$index]
                    if ($element -isnot [System.Management.Automation.Language.CommandParameterAst] -or
                        -not @('be', 'beexactly', 'contain', 'eq', 'ceq', 'bein', 'belike', 'belikeexactly').Contains($element.ParameterName.ToLowerInvariant())) { continue }
                    $expected = if ($null -ne $element.Argument) { $element.Argument } elseif ($index + 1 -lt $elements.Count) { $elements[$index + 1] } else { $null }
                    if ($expected -is [System.Management.Automation.Language.CommandParameterAst] -and [string]::Equals($expected.ParameterName, 'ExpectedValue', [StringComparison]::OrdinalIgnoreCase)) {
                        $at = [array]::IndexOf($elements, $expected)
                        $expected = if ($null -ne $expected.Argument) { $expected.Argument } elseif ($at + 1 -lt $elements.Count) { $elements[$at + 1] } else { $null }
                    }
                    if ($null -eq $expected -or $expected -is [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    $contexts = @(script:Get-AssertionContext -Should $should)
                    $built = script:Test-ExpressionBuildsInvisible -Expression $expected -Contexts $contexts
                    if (-not $built) {
                        $plain = $expected
                        while ($plain -is [System.Management.Automation.Language.ParenExpressionAst] -and $plain.Pipeline -is [System.Management.Automation.Language.PipelineAst] -and
                            @($plain.Pipeline.PipelineElements).Count -eq 1 -and $plain.Pipeline.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) { $plain = $plain.Pipeline.PipelineElements[0].Expression }
                        $isText = ($plain -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $plain.StringConstantType -ne 'BareWord') -or $plain -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                        $test = $contexts | Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] -and [string]::Equals($_.GetCommandName(), 'It', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
                        $built = $isText -and $null -ne $test -and (script:Test-BuildsInvisibleCharacter $test.Extent.Text)
                    }
                    if ($built) { 'line {0}: {1}' -f $should.Extent.StartLineNumber, (($should.Parent.Extent.Text -split "`n")[0].Trim()) }
                }
            }
        }
    }

    It 'compares every expected value built from an invisible character ordinally' {
        # Should -Be and -BeExactly compare by culture and skip zero-width, bidi and other
        # ignorable characters, so each of these could pass on a value that lost the very
        # character the test is about. -BeOrdinal doesn't skip them.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'sync-profile.Tests.ps1'), [ref]$null, [ref]$null)

        @(script:Find-CultureComparedInvisible -Ast $ast) | Should -BeNullOrEmpty
    }

    It 'finds a culture-compared invisible expected value in <Case>' -ForEach @(
        @{ Case = 'the argument'; Code = "It 'x' { 'a' | Should -Be ('a' + [char]0x200B) }"; Found = $true }
        @{ Case = 'a -ForEach value'; Code = "It 'x' -ForEach @(@{ Expected = 'a' + [char]0x200D }) { 'a' | Should -BeExactly `$Expected }"; Found = $true }
        @{ Case = 'an assignment in the test'; Code = "It 'x' { `$e = [string][char]0x202E; @('a') | Should -Contain `$e }"; Found = $true }
        @{ Case = 'a Unicode escape'; Code = "It 'x' { 'a' | Should -EQ ""a``u{200B}"" }"; Found = $true }
        @{ Case = 'a lone surrogate'; Code = "It 'x' { 'a' | Should -Be ('a' + [char]0xD800) }"; Found = $true }
        @{ Case = 'not a visible character'; Code = "It 'x' { 'a' | Should -Be ('a' + [char]0x00E9) }"; Found = $false }
        @{ Case = 'not an ordinal compare'; Code = "It 'x' { 'a' | Should -BeOrdinal ('a' + [char]0x200B) }"; Found = $false }
        # Review G6: none of these was found.
        @{ Case = 'a decimal code point'; Code = "It 'x' { 'a' | Should -Be ('a' + [char]8203) }"; Found = $true }
        @{ Case = 'a character written in as it is'; Code = "It 'x' { 'a' | Should -Be 'a" + [char]0x200B + "' }"; Found = $true }
        @{ Case = '-BeIn'; Code = "It 'x' { 'a' | Should -BeIn @('a' + [char]0x200B) }"; Found = $true }
        @{ Case = '-BeLike'; Code = "It 'x' { 'a' | Should -BeLike ('a' + [char]0x200B) }"; Found = $true }
        @{ Case = '-ExpectedValue'; Code = "It 'x' { 'a' | Should -Be -ExpectedValue ('a' + [char]0x200B) }"; Found = $true }
        @{ Case = 'a variable built from another'; Code = "It 'x' { `$rlo = [string][char]0x202E; `$e = 'a' + `$rlo; 'a' | Should -Be `$e }"; Found = $true }
        @{ Case = 'a value from BeforeAll'; Code = "Describe 'd' { BeforeAll { `$script:Hidden = [string][char]0x200B }; It 'x' { 'a' | Should -Be `$script:Hidden } }"; Found = $true }
        @{ Case = 'a member of the pipeline item'; Code = "It 'x' { @(@{ Expected = 'a' + [char]0x200B }) | ForEach-Object { 'a' | Should -Be `$_.Expected } }"; Found = $true }
        @{ Case = 'Describe-level data'; Code = "Describe 'd' -ForEach @(@{ Expected = 'a' + [char]0x200B }) { It 'x' { 'a' | Should -Be `$Expected } }"; Found = $true }
        @{ Case = 'the actual side only'; Code = "It 'x' { `$v = 'a' + [char]0x200B; `$v | Should -Be 'a' }"; Found = $true }
        @{ Case = 'not a test with nothing invisible'; Code = "It 'x' { 'a' | Should -Be 'a' }"; Found = $false }
    ) {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$null, [ref]$null)

        (@(script:Find-CultureComparedInvisible -Ast $ast).Count -gt 0) | Should -Be $Found
    }

    It 'fails -BeOrdinal on a character -BeExactly skips, and keeps $null apart from empty' {
        $joined = 'a' + [char]0x200D + 'b'
        ('ab' -ceq $joined) | Should -BeTrue -Because 'the culture compare -BeExactly uses skips the joiner, which is why -BeOrdinal exists'

        { 'ab' | Should -BeOrdinal $joined } | Should -Throw -ExpectedMessage "*Expected 'a{U+200D}b', compared ordinally, but got 'ab'*"
        $joined | Should -BeOrdinal $joined
        'ab' | Should -Not -BeOrdinal $joined
        { '' | Should -BeOrdinal $null } | Should -Throw
        $null | Should -BeOrdinal $null
    }

    It 'compares a list with -BeOrdinal as a whole' {
        # Review G6: each item was compared on its own, so @('a', 'a') passed as 'a'.
        { @('a', 'a') | Should -BeOrdinal 'a' } | Should -Throw -ExpectedMessage "*Expected 'a', compared ordinally, but got @('a', 'a')*"
        @('a', 'b') | Should -BeOrdinal @('a', 'b')
        { @('a', 'b') | Should -BeOrdinal @('a', ('b' + [char]0x200B)) } | Should -Throw
        { @('a', 'b') | Should -BeOrdinal @('a') } | Should -Throw
        @('a') | Should -BeOrdinal 'a'
        @() | Should -BeOrdinal $null
    }
}
