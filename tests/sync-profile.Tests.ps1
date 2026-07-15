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
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:SyncProfileScriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
    $script:SyncProfileScript = Get-Content -LiteralPath $script:SyncProfileScriptPath -Raw
    # Dot-source the library. The script's test seam stops before the fetch/main block.
    . $script:SyncProfileScriptPath
    # Run offline so nothing reaches out to GitHub.
    $script:Offline = $true

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
            [string[]]$AssetNames = @()
        )

        $assetKinds = if ($WithRelease) { @(Get-ReleaseAssetKinds -AssetNames $AssetNames) } else { @() }
        [pscustomobject]@{
            name = $Name
            description = $Description
            primaryLanguage = [pscustomobject]@{ name = $Language }
            repositoryTopics = @($Topics | ForEach-Object { [pscustomobject]@{ name = $_ } })
            defaultBranchRef = [pscustomobject]@{ name = 'main' }
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

Describe 'Function library loads via the dot-source test seam' {
    It 'exposes the core functions without running the fetch/main block' {
        Get-Command New-Readme, New-ProjectsExportJson, Get-InstallSnippet, Test-HttpUrl, Get-Catalog -ErrorAction SilentlyContinue |
            Should -HaveCount 5
    }

    It 'documents the key public test-seam functions with comment-based help' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:SyncProfileScriptPath, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $functionAsts = @{}
        foreach ($functionAst in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
            $functionAsts[$functionAst.Name] = $functionAst
        }
        $documentedFunctions = @(
            'Get-GitHubRepos',
            'Add-ReleaseAssetMetadata',
            'Add-ForkParentMetadata',
            'Add-LiveRepositoryMetadata',
            'ConvertTo-Lookup',
            'Get-ContributionCalendar',
            'Get-Catalog',
            'New-ProfileAssetSvgs',
            'New-ContributionGraphSvg',
            'Get-ExistingProfileAssetText',
            'New-ContributionAssetSvg',
            'New-Readme',
            'New-ProjectsExportJson',
            'New-RenderedProfileSmokeSummary',
            'Test-RoadmapHygiene',
            'Test-RootMarkdownHygiene',
            'Test-ProfileAssetsAccessibility',
            'Test-CatalogShape',
            'Test-JsonSchemaContract',
            'Test-FeedSchemaContracts',
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

    It 'uses a parameterized GraphQL query for contribution calendar lookup' {
        $script:SyncProfileScript | Should -Match 'query\(\$login: String!\)'
        $script:SyncProfileScript | Should -Match '"-f", "login=\$Owner"'
        $script:SyncProfileScript | Should -Not -Match "user\(login: `"\s*\+"
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
            $result.text | Should -Be 'api user'
            $result.output | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
        }
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
    It 'emits a branch-pinned clone-install-run snippet with the PowerShell runner' {
        $e = New-TestEntry -Repo 'WinTool' -Category 'powershell'
        $e.entrypoint = 'WinTool.ps1'; $e.installKind = 'powershell'; $e.branch = 'main'
        $snippet = Get-InstallSnippet -Entry $e -Meta $null -Category 'powershell'
        $snippet | Should -Match 'git clone -q --depth 1 -b main https://github.com/SysAdminDoc/WinTool'
        $snippet | Should -Match '& "\$d\\WinTool\.ps1"'
    }
    It 'emits the python runner and honours a non-main branch' {
        $e = New-TestEntry -Repo 'PyTool' -Category 'python'
        $e.entrypoint = 'app.py'; $e.installKind = 'python'; $e.branch = 'master'
        $snippet = Get-InstallSnippet -Entry $e -Meta $null -Category 'python'
        $snippet | Should -Match '-b master '
        $snippet | Should -Match 'python "\$d\\app\.py"'
    }
    It 'returns null when the entry has no entrypoint' {
        $e = New-TestEntry -Repo 'NoEntry' -Category 'powershell'
        Get-InstallSnippet -Entry $e -Meta $null -Category 'powershell' | Should -BeNullOrEmpty
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
            Should -Be '[<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/A/releases/latest)'
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
        $script:SyncProfileScript | Should -Match '\$\{function:Test-HttpUrl\}\.ToString\(\)'
        $script:SyncProfileScript | Should -Match '\$\{function:Test-HttpUrl\} = \$using:testHttpUrlDefinition'
    }

    It 'keeps link probes bounded to response headers' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:SyncProfileScript, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $functionAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-HttpUrl'
        }, $true)
        $functionAst | Should -Not -BeNullOrEmpty
        $body = $functionAst.Extent.Text

        $body | Should -Match 'ResponseHeadersRead'
        $body | Should -Match 'HttpClient'
        $body | Should -Not -Match 'Invoke-WebRequest'
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
            scorecardSarifUploadPresent = $false
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
        $repoSettings.security.dependabotSecurityPosture.recommendation | Should -Be 'monitor-dependabot-security-updates'
        $repoSettings.security.dependabotSecurityPosture.securityUpdatesEnabled | Should -BeTrue
        $repoSettings.security.dependabotSecurityPosture.localConfigPresent | Should -BeFalse
        $repoSettings.security.dependabotSecurityPosture.localConfigPath | Should -Be '.github/dependabot.yml'
        $repoSettings.security.dependabotSecurityPosture.localConfigEcosystems | Should -BeNullOrEmpty
        $repoSettings.security.dependabotSecurityPosture.documentationPath | Should -Be 'decision:dependabot-security-posture'
        $scorecardScore.available | Should -BeTrue
        $scorecardScore.score | Should -Be 7.4
        $scorecardScore.maxScore | Should -Be 10.0
        $scorecardScore.provider | Should -Be 'securityscorecards-api'
        $scorecardScore.sourceUrl | Should -Be 'https://api.securityscorecards.dev/projects/github.com/SysAdminDoc/SysAdminDoc'
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
        $repoSettings.security.codeScanning.scorecardSarifUploadPresent | Should -BeFalse
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

        $result = Test-RepositoryCommunityBaseline -Repository $repository -CommunityProfile $community -LocalFiles $localNoForms -CodeScanningLocalEvidence ([ordered]@{ sarifUploadWorkflowPresent = $true; scorecardSarifUploadPresent = $true })
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
        $result = Test-RepositoryCommunityBaseline -Repository $repository -CommunityProfile $community -LocalFiles $script:LocalCommunityFilesOk -CodeScanningLocalEvidence ([ordered]@{ sarifUploadWorkflowPresent = $true; scorecardSarifUploadPresent = $true })
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
            scorecardSarifUploadPresent = $true
            psScriptAnalyzerWorkflowPresent = $true
            actionlintWorkflowPresent = $true
            zizmorWorkflowPresent = $true
        }

        $result = Test-RepositoryCommunityBaseline -Repository $repository -LocalFiles $script:LocalCommunityFilesOk -CodeScanningLocalEvidence $codeScanningEvidence -DependabotSecurityUpdatesStatus 'enabled'
        $repoSettings = $result['repositorySettings']

        $repoSettings.security.dependabotSecurityUpdates | Should -Be 'enabled'
        $repoSettings.security.dependabotSecurityPosture.status | Should -Be 'enabled'
        $repoSettings.security.dependabotSecurityPosture.recommendation | Should -Be 'monitor-dependabot-security-updates'
        $repoSettings.security.codeScanning.activeControls | Should -Contain 'dependabot-security-updates'
        $repoSettings.security.codeScanning.hostedControls | Should -Contain 'dependabot-security-updates'
        $repoSettings.security.codeScanning.hostedControls | Should -Contain 'openssf-scorecard-sarif'
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
            scorecardSarifUploadPresent = $true
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
        $codeScanning.hostedControls | Should -Contain 'openssf-scorecard-sarif'
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

    It 'uses the configured GraphQL page size and records successful metadata telemetry' {
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
            return @(
                @{ name = 'RepoA' },
                @{ name = 'RepoB' }
            ) | ConvertTo-Json -Depth 5
        }

        try {
            $repos = @(Get-GitHubRepos)

            $repos | Should -HaveCount 2
            $script:ghCommands[0] | Should -Match '--limit 25'
            $script:MetadataFetchAttemptCount | Should -Be 1
            $script:MetadataFetchRequestCount | Should -Be 1
            $script:RepositoryEnumerationRequestedLimit | Should -Be 25
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
        $entry.fetchedAt = (Get-Date).ToUniversalTime().AddHours(-48).ToString("o")
        $entry | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $cacheFile -Encoding utf8

        Get-ValidationCacheValue -Bucket metadata -Key $cacheKey | Should -BeNullOrEmpty
        (Get-ValidationCacheState).metadata.staleCount | Should -Be 1
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

Describe 'Repository metadata enrichment' {
    It 'keeps latestRelease out of the bulk repo-list GraphQL request' {
        $script:SyncProfileScript | Should -Match '"--json", "name,description,stargazerCount,defaultBranchRef,licenseInfo,isFork,parent,isPrivate,visibility,isArchived,repositoryTopics,pushedAt,url,primaryLanguage"'
        $script:SyncProfileScript | Should -Not -Match '"--json", "name,description,stargazerCount,defaultBranchRef,latestRelease,licenseInfo'
    }

    It 'fetches latest releases through bounded REST enrichment when GraphQL omits them' {
        $oldOffline = $script:Offline
        $ownerVariable = Get-Variable -Name Owner -Scope Script -ErrorAction SilentlyContinue
        $hadOwner = ($null -ne $ownerVariable)
        $oldOwner = if ($hadOwner) { $ownerVariable.Value } else { $null }
        $script:Offline = $false
        $script:Owner = 'SysAdminDoc'

        function gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $global:LASTEXITCODE = 0
            $command = $Arguments -join ' '
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
$d="$env:TEMP\WinTool"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/WinTool $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\Tools\Win Tool.ps1"
```

[<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/MobileTool/releases/latest)
| [**ScriptTool**](https://github.com/SysAdminDoc/ScriptTool) | Browser helper | [Install](https://raw.githubusercontent.com/SysAdminDoc/ScriptTool/main/ScriptTool.user.js) |
'@
        $targets = @(Get-ReadmeActionLinkValidationTargets -ExpectedReadme $readme)

        $targets | Should -HaveCount 3
        ($targets | ForEach-Object { $_.type } | Sort-Object) -join ',' |
            Should -Be 'readme-download,readme-install-entrypoint,readme-userscript-install'
        ($targets | Where-Object { $_.type -eq 'readme-install-entrypoint' }).url |
            Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/WinTool/main/Tools/Win%20Tool.ps1'
        ($targets | Where-Object { $_.type -eq 'readme-download' }).repo | Should -Be 'MobileTool'
        ($targets | Where-Object { $_.type -eq 'readme-userscript-install' }).repo | Should -Be 'ScriptTool'
        ($targets | Where-Object { $_.group -eq 'readme-actions' }) | Should -HaveCount 3
    }

    It 'keeps README action target failures visible through link validation rows' {
        $readme = @'
```powershell
$d="$env:TEMP\WinTool"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/WinTool $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\WinTool.ps1"
```
'@
        $targets = @(Get-ReadmeActionLinkValidationTargets -ExpectedReadme $readme)
        $probe = {
            param($target)

            return [ordered]@{ ok = $false; status = 404; error = 'missing'; fatal = $true }
        }

        $result = Test-LinkTargets -Included @() -RepoLookup @{} -ExtraTargets $targets -ProbeScript $probe -ThrottleLimit 2

        @($result.failures) | Should -HaveCount 1
        $result.failures[0].type | Should -Be 'readme-install-entrypoint'
        $result.failures[0].url | Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/WinTool/main/WinTool.ps1'
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
            (New-TestRepoMeta -Name 'StaleTool' -PushedAt '2025-01-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'OldReleaseTool' -WithRelease -PushedAt '2026-06-01T00:00:00Z' -ReleasePublishedAt '2024-01-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'ArchiveCandidate' -PushedAt '2023-01-01T00:00:00Z')
        )
        $lookup = ConvertTo-Lookup $repos

        $result = Test-StaleProjectReview `
            -Entries @($current, $stale, $oldRelease, $archive, $suppressedPrivate, $suppressedVisitor, $suppressedDuplicate) `
            -RepoLookup $lookup `
            -Now ([datetimeoffset]'2026-06-06T00:00:00Z')

        $result.checkedProjectCount | Should -Be 4
        $result.staleAfterDays | Should -Be 365
        $result.releaseStaleAfterDays | Should -Be 540
        $result.archiveAfterDays | Should -Be 730
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
        # Highest evidence gap (MismatchRelease, gapScore 3) is ranked first.
        $shortlist.rows[0].repo | Should -Be 'MismatchRelease'
        $shortlist.rows[0].priorityRank | Should -Be 1
        $shortlist.rows[0].gapScore | Should -Be 3
        $shortlist.rows[0].nextAction | Should -Be 'publish-sha256sums'
        ($shortlist.rows | Where-Object { $_.repo -eq 'GoodRelease' }).hasChecksum | Should -BeTrue
        ($shortlist.rows | Where-Object { $_.repo -eq 'GoodRelease' }).nextAction | Should -Be 'publish-build-provenance-attestation'

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
        { New-ProfileAssetSvgs -Catalog $script:emptyCat -Repos $null -ContributionCalendar $null } | Should -Not -Throw
    }
    It 'reports zero live repositories in the feed provenance when the repo set is empty' {
        $feed = New-ProjectsExportJson -Catalog $script:emptyCat -Repos @() | ConvertFrom-Json
        $feed.publicRepoCount | Should -Be 0
        $feed.provenance.repoEnumeration.returnedCount | Should -Be 0
    }

    It 'generates the full set of theme-aware profile SVG assets' {
        $assets = New-ProfileAssetSvgs -Catalog $script:emptyCat -Repos @() -ContributionCalendar $null
        $expected = @(
            'header-dark.svg', 'header-light.svg', 'stats-dark.svg', 'stats-light.svg',
            'languages-dark.svg', 'languages-light.svg', 'activity-dark.svg', 'activity-light.svg',
            'contributions-dark.svg', 'contributions-light.svg', 'footer-dark.svg', 'footer-light.svg'
        )
        @($assets.Keys).Count | Should -Be 12
        foreach ($name in $expected) {
            $key = @($assets.Keys | Where-Object { $_ -like "*$name" }) | Select-Object -First 1
            $key | Should -Not -BeNullOrEmpty
            $assets[$key] | Should -Match '<svg'
            $assets[$key] | Should -Match 'role="img"'
        }
    }
}

Describe 'Empty category sections are not rendered' {
    It 'returns an empty string for a category with no visible entries' {
        $definition = $CategoryDefinitions | Where-Object { $_.Slug -eq 'security' } | Select-Object -First 1
        $entries = @((New-TestEntry -Repo 'OnlyPowerShell' -Category 'powershell'))
        $section = New-CategorySection -Entries $entries -RepoLookup @{} -Definition $definition
        [string]::IsNullOrEmpty($section) | Should -BeTrue
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
        $script:rendered | Should -Not -Match 'releases/latest\) -- '
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
    It 'renders local validation bootstrap guidance' {
        $script:rendered | Should -Match 'Set up or verify this profile repo'
        $script:rendered | Should -Match '<a id="local-validation"></a>'
        $script:rendered | Should -Match 'Regenerate, lint, analyze, test, and smoke-check the profile feed locally'
        $script:rendered | Should -Match ([regex]::Escape('pwsh -NoProfile -File .\scripts\validate-local.ps1'))
        $script:rendered | Should -Match 'manual dependency and advisory review'
        $script:rendered | Should -Match 'npm run review:dependencies'
        $script:rendered | Should -Match 'package override drift'
        $script:rendered | Should -Match 'npm ci'
        $script:rendered | Should -Match 'PowerShell runtime'
        $script:rendered | Should -Match 'warns below PowerShell 7\.6 LTS'
        $script:rendered | Should -Match 'Pester 5\.8\.0'
        $script:rendered | Should -Match 'PSScriptAnalyzer 1\.25\.0'
        $script:rendered | Should -Match 'Invoke-Pester -Path tests -Output Detailed'
        $script:rendered | Should -Match ([regex]::Escape('sync-profile.ps1 -Check -GraphQlPageSize 300'))
        $script:rendered | Should -Match '-SkipBootstrap'
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
        $script:rendered.TrimStart() | Should -Match '^<p align="center"><b>Broadcast IT, Healthcare IT, and practical public tools\.</b>'
        $script:rendered | Should -Not -Match 'assets/profile/header-(dark|light)\.svg'
        $script:rendered | Should -Not -Match 'assets/profile/footer-(dark|light)\.svg'
        $script:rendered | Should -Not -Match '<img '
        $script:rendered | Should -Not -Match '#gh-(dark|light)-mode-only'
        $script:rendered | Should -Match '<p align="center"><a href="https://sysadmindoc\.github\.io/"><b>View my full portfolio'
        $script:rendered | Should -Match '<a href="#start-here">Start Here</a>'
        $script:rendered | Should -Match '<a href="#powershell-system-utilities">PowerShell</a>'
        $script:rendered | Should -Match 'Broadcast IT, Healthcare IT, and practical public tools'
        $script:rendered | Should -Not -Match '### Professional Focus'
        $script:rendered | Should -Not -Match '(?m)^\*\*Currently Building\*\*$'
        $script:rendered | Should -Not -Match 'https://skillicons\.dev'
        $script:rendered | Should -Not -Match 'assets/profile/(stats|languages|activity)-(dark|light)\.svg'
        $script:rendered | Should -Not -Match 'capsule-render\.vercel\.app|readme-typing-svg|[?&]animation=|[?&]repeat=true'
        $script:rendered | Should -Not -Match 'komarev\.com|github-readme-stats|streak-stats|github-readme-activity-graph'
        $script:rendered | Should -Not -Match 'img\.shields\.io/github/(followers|stars)'
    }
    It 'renders the compact discovery block without catalog snapshot or featured projects' {
        $script:rendered | Should -Match ([regex]::Escape($GeneratedCatalogNotice))
        $script:rendered | Should -Match '### Start Here'
        $script:rendered | Should -Not -Match '### Catalog Snapshot'
        $script:rendered | Should -Not -Match '### Featured Projects'
    }
    It 'adds decision guidance that routes visitors by install surface' {
        $script:rendered | Should -Match ([regex]::Escape("| Signal | I want to... | Best category | What you'll find | Action |"))
        $script:rendered | Should -Match '<kbd>PS</kbd>'
        $script:rendered | Should -Match 'Branch-pinned commands, release downloads, and focused desktop utilities'
        $script:rendered | Should -Match 'CRX, XPI, userscript, source, and release-backed install paths'
        $script:rendered | Should -Match 'Quick platform map'
        $script:rendered | Should -Match '<a id="first-time-setup"></a>'
        $script:rendered | Should -Match '### Tool Catalog'
        $script:rendered | Should -Match 'Categories with suggested starting points and quick actions'
        $script:rendered | Should -Match 'Windows automation and administration'
        $script:rendered | Should -Match 'Self-hosted and online tools for IT'
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
        $result.startHereSection | Should -BeTrue
        $result.catalogSnapshotSection | Should -BeFalse
        $result.setupInspectPath | Should -BeTrue
        $result.themeAwareImageChrome | Should -BeFalse
        $result.plainTextTagline | Should -BeFalse
        $result.meaningfulImageAltText | Should -BeFalse
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

    It 'generates committed local profile SVG assets' {
        $repo = New-TestRepoMeta -Name 'WinTool'
        $repo.stargazerCount = 7
        $assets = New-ProfileAssetSvgs -Catalog $script:cat -Repos @($repo)

        $assets.Keys | Should -Contain 'assets/profile/header-dark.svg'
        $assets.Keys | Should -Contain 'assets/profile/header-light.svg'
        $assets.Keys | Should -Contain 'assets/profile/stats-dark.svg'
        $assets.Keys | Should -Contain 'assets/profile/languages-light.svg'
        $assets.Keys | Should -Contain 'assets/profile/activity-dark.svg'
        $assets.Keys | Should -Contain 'assets/profile/contributions-dark.svg'
        $assets.Keys | Should -Contain 'assets/profile/contributions-light.svg'
        $assets.Keys | Should -Contain 'assets/profile/footer-dark.svg'
        $assets.Keys | Should -Contain 'assets/profile/footer-light.svg'
        $assets['assets/profile/contributions-dark.svg'] | Should -Match 'Contribution Activity'
        $assets['assets/profile/contributions-dark.svg'] | Should -Match 'contributions in the last year'
        $assets['assets/profile/header-dark.svg'] | Should -Match 'SysAdminDoc profile header'
        $assets['assets/profile/header-dark.svg'] | Should -Match 'SysAdminDoc</text>'
        $assets['assets/profile/header-dark.svg'] | Should -Match 'Broadcast IT, Healthcare IT, and practical public tools'
        $assets['assets/profile/header-dark.svg'] | Should -Match 'View full portfolio -&gt;'
        $assets['assets/profile/stats-dark.svg'] | Should -Match '<svg'
        $assets['assets/profile/stats-dark.svg'] | Should -Match '<title id="profile-sysadmindoc-catalog-stats-dark-title">SysAdminDoc Catalog Stats</title>'
        $assets['assets/profile/stats-dark.svg'] | Should -Match 'total public stars'
        $assets['assets/profile/stats-dark.svg'] | Should -Match '>7</text>'
        $assets['assets/profile/activity-light.svg'] | Should -Match 'Release Asset Health'
        $assets['assets/profile/footer-light.svg'] | Should -Match 'Built from Broadcast IT, Healthcare IT'
        $assets['assets/profile/footer-light.svg'] | Should -Match 'View portfolio -&gt;'

        foreach ($asset in $assets.GetEnumerator()) {
            [xml]$assetXml = $asset.Value
            $root = $assetXml.DocumentElement
            $labelledBy = $root.GetAttribute('aria-labelledby')
            $describedBy = $root.GetAttribute('aria-describedby')
            $titleNode = $root.GetElementsByTagName('title')[0]
            $descNode = $root.GetElementsByTagName('desc')[0]

            $root.GetAttribute('role') | Should -Be 'img'
            $root.GetAttribute('aria-label') | Should -Be ''
            $labelledBy | Should -Not -BeNullOrEmpty
            $describedBy | Should -Not -BeNullOrEmpty
            $titleNode.GetAttribute('id') | Should -Be $labelledBy
            $descNode.GetAttribute('id') | Should -Be $describedBy
            $titleNode.InnerText | Should -Not -BeNullOrEmpty
            $descNode.InnerText | Should -Not -BeNullOrEmpty
        }

        [xml]$statsXml = $assets['assets/profile/stats-dark.svg']
        $statsRoot = $statsXml.DocumentElement
        $statsRoot.GetAttribute('aria-labelledby') | Should -Be 'profile-sysadmindoc-catalog-stats-dark-title'
        $statsRoot.GetAttribute('aria-describedby') | Should -Be 'profile-sysadmindoc-catalog-stats-dark-desc'
        $statsDesc = $statsRoot.GetElementsByTagName('desc')[0].InnerText
        $statsDesc | Should -Match ([regex]::Escape('Rows: 1 active public repositories'))
        $statsDesc | Should -Match ([regex]::Escape('7 total public stars'))

        $escapedSvg = New-ProfilePanelSvg -Title 'A&B <Stats>' -Subtitle 'Summary & status' -Rows @(
            [ordered]@{ label = 'stars <public>'; value = '7 & 8'; detail = 'live > stale' }
        ) -Theme dark
        [xml]$escapedXml = $escapedSvg
        $escapedRoot = $escapedXml.DocumentElement
        $escapedRoot.GetAttribute('aria-labelledby') | Should -Be 'profile-a-b-stats-dark-title'
        $escapedSvg | Should -Match 'A&amp;B &lt;Stats&gt;'
        $escapedRoot.GetElementsByTagName('desc')[0].InnerText | Should -Be 'Summary & status Rows: 7 & 8 stars <public> (live > stale).'
    }

    It 'preserves committed contribution graphs when the live calendar is unavailable' {
        $repo = New-TestRepoMeta -Name 'WinTool'
        $assets = New-ProfileAssetSvgs -Catalog $script:cat -Repos @($repo) -ContributionCalendar $null
        $committedDark = (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'assets/profile/contributions-dark.svg') -Raw).TrimEnd()

        $assets['assets/profile/contributions-dark.svg'] | Should -Be $committedDark
    }

    It 'expands contribution graph width for unusually long calendars' {
        $weeks = @(
            for ($w = 0; $w -lt 60; $w++) {
                [pscustomobject]@{
                    contributionDays = @(
                        [pscustomobject]@{
                            contributionCount = 1
                            date = ('2026-01-{0:00}' -f ((($w % 28) + 1)))
                            weekday = 0
                        }
                    )
                }
            }
        )
        $calendar = [pscustomobject]@{
            totalContributions = 60
            weeks = $weeks
        }

        $svg = New-ContributionGraphSvg -Calendar $calendar -Theme dark -Width 820

        $svg | Should -Match 'width="932"'
        $svg | Should -Match 'viewBox="0 0 932 236"'
    }
}

Describe 'Update-Header idempotency' {
    It 'produces identical output when run twice on the same input' {
        $first = Update-Header
        $second = Update-Header

        $second | Should -Be $first
    }

    It 'produces a minimal text-only header with no image chrome' {
        $result = Update-Header

        $result | Should -Not -Match 'assets/profile/header-(dark|light)\.svg'
        $result | Should -Not -Match '<img '
        $result | Should -Match 'View my full portfolio'
        $result | Should -Match 'Broadcast IT, Healthcare IT, and practical public tools'
        $result | Should -Match '<a href="#powershell-system-utilities">PowerShell</a>'
        $result | Should -Not -Match 'Professional Focus|Public portfolio: 100 active repos'
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

    It 'exports public-safe feed provenance fields' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $rawJson = New-ProjectsExportJson -Catalog $cat -Repos @()
        $json = $rawJson | ConvertFrom-Json
        $provenanceJson = $json.provenance | ConvertTo-Json -Depth 20

        $json.provenance.version | Should -Be 1
        $json.provenance.feedSchemaVersion | Should -Be 2
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
        ($result.errors -join "`n") | Should -Match 'projects/0/repo|projects\[0\]\.repo|\$\.projects\[0\]\.repo'
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
            ($result.errors -join "`n") | Should -Match "suppressed/0/$field|suppressed\[0\]\.$field|\$\.suppressed\[0\]\.$field"
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
                'overlapWarningCount'
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
        ($result.errors -join "`n") | Should -Match 'releaseAssetDrift'
        ($result.errors -join "`n") | Should -Match 'required|not present'
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
        $schema.'$defs'.releaseAssetDrift.required | Should -Contain 'executableDownloadTrustShortlist'
    }

    It 'warns when a schema uses keywords outside the project compatibility allowlist' {
        $schemaPath = Join-Path $TestDrive 'unsupported.json'
        $unsupportedSchema = @{
            type = 'object'
            oneOf = @(@{ type = 'string' })
            maxLength = 10
        } | ConvertTo-Json -Depth 5 -Compress
        Set-Content -LiteralPath $schemaPath -Value $unsupportedSchema -Encoding utf8

        $result = Test-JsonSchemaContract -Value @{} -SchemaPath $schemaPath

        @($result.unsupportedKeywords).Count | Should -BeGreaterOrEqual 2
        ($result.unsupportedKeywords -join "`n") | Should -Match 'oneOf'
        ($result.unsupportedKeywords -join "`n") | Should -Match 'maxLength'
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
        $script:MarkdownlintPackage.devDependencies['markdownlint-cli2'] | Should -Be '0.23.0'
        $script:MarkdownlintPackageLock.name | Should -Be 'sysadmindoc-profile'
        $script:MarkdownlintPackageLock.packages[''].devDependencies['markdownlint-cli2'] | Should -Be '0.23.0'
        $script:MarkdownlintPackageLock.packages['node_modules/markdownlint-cli2'].version | Should -Be '0.23.0'
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
        $codeScanning.scorecardSarifUploadPresent | Should -BeFalse
        $codeScanning.localControls | Should -Contain 'local-validation-bootstrap'
        $codeScanning.localControls | Should -Contain 'psscriptanalyzer'
        $codeScanning.localControls | Should -Contain 'pester'
        $codeScanning.localControls | Should -Contain 'markdownlint'
        $codeScanning.hostedControls | Should -Contain 'secret-scanning'
        $codeScanning.hostedControls | Should -Contain 'secret-scanning-push-protection'
        $codeScanning.hostedControls | Should -Contain 'dependabot-security-updates'
        $codeScanning.hostedControls | Should -Not -Contain 'psscriptanalyzer'
        $codeScanning.hostedControls | Should -Not -Contain 'openssf-scorecard-sarif'
        $codeScanning.activeControls | Should -Contain 'psscriptanalyzer'
        $codeScanning.activeControls | Should -Contain 'dependabot-security-updates'
        $report.repositorySettings.security.dependabotSecurityPosture.status | Should -Be 'enabled'
        $report.repositorySettings.security.dependabotSecurityPosture.localConfigPresent | Should -BeFalse
        $report.repositorySettings.security.dependabotSecurityPosture.localConfigEcosystems | Should -BeNullOrEmpty
        $codeScanning.scorecardAlertPosture.available | Should -BeTrue
        $codeScanning.scorecardAlertPosture.openAlertCount | Should -Be @($codeScanning.scorecardAlertPosture.rows).Count
        $codeScanning.scorecardAlertPosture.openAlertCount | Should -BeGreaterOrEqual 4
        $codeScanning.scorecardAlertPosture.needsHostedRefreshCount | Should -Be 0
        $codeScanning.scorecardAlertPosture.localActionableCount | Should -Be 0
        $codeScanning.scorecardAlertPosture.recommendation | Should -Be 'track-external-scorecard-governance-items'
        $report.repositorySettings.security.scorecardScore.provider | Should -Be 'securityscorecards-api'
        $report.repositorySettings.security.scorecardScore.sourceUrl | Should -Be 'https://api.securityscorecards.dev/projects/github.com/SysAdminDoc/SysAdminDoc'
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
            $report.repositorySettings.reviewPolicyPosture.requiredCheckEnforcementProven | Should -BeTrue
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
        $output = & pwsh -NoProfile -File $scriptPath -SeedCatalog -Offline -CatalogPath (Join-Path $TestDrive 'blocked-catalog.json') *>&1

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

        $output = & pwsh -NoProfile -File $scriptPath -SeedCatalog -ForceSeedCatalog -Offline -ReadmePath $readmePath -CatalogPath $catalogPath *>&1

        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'LOSSY LEGACY SEED MODE'
        Test-Path -LiteralPath $catalogPath | Should -BeTrue
    }
}

Describe 'Profile sync entrypoint' {
    It 'exits explicitly after a successful check run' {
        $script:SyncProfileScript | Should -Match '(?s)Write-Host "Profile sync check passed[.] Report: \$ReportPath"\s+# Keep hosted shells from surfacing handled native-command failures[.]\s+exit 0'
    }
}

Describe 'Generation entrypoint modes' -Tag 'Integration' {
    It 'writes README, feed, and assets under -Write -Offline without crashing' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $readmePath = Join-Path $TestDrive 'README.md'
        $projectsPath = Join-Path $TestDrive 'projects.json'
        $assetsPath = Join-Path $TestDrive 'assets'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Destination $readmePath -Force

        $output = & pwsh -NoProfile -File $scriptPath -Write -Offline `
            -CatalogPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') `
            -ReadmePath $readmePath -ProjectsPath $projectsPath -AssetsPath $assetsPath *>&1

        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Not -Match "property 'Count' cannot be found"
        Test-Path -LiteralPath $readmePath | Should -BeTrue
        Test-Path -LiteralPath $projectsPath | Should -BeTrue
        $feed = Get-Content -LiteralPath $projectsPath -Raw | ConvertFrom-Json
        $feed.publicRepoCount | Should -Be 0
    }

    It 'rejects unsafe Owner values before generation or network work' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'

        $output = & pwsh -NoProfile -File $scriptPath -Owner '../bad' -Check -Offline *>&1

        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'Owner must match'
    }

    It 'writes a report under -Check -Offline without a Count-on-null crash' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $reportPath = Join-Path $TestDrive 'offline-report.json'

        $output = & pwsh -NoProfile -File $scriptPath -Check -Offline -SkipLinkValidation `
            -CatalogPath (Join-Path $script:RepoRoot 'data/profile-catalog.json') `
            -ReportPath $reportPath *>&1

        # Offline check legitimately reports drift (exit 1); the point is that it does not throw.
        ($output | Out-String) | Should -Not -Match "property 'Count' cannot be found"
        Test-Path -LiteralPath $reportPath | Should -BeTrue
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $report.validationPerformance.metadataFetch.repoCount | Should -Be 0
        $report.validationPerformance.metadataFetch.graphQlPageSize | Should -Be 500
        $report.validationPerformance.metadataFetch.requestCount | Should -Be 0
        $report.validationPerformance.metadataFetch.retryCount | Should -Be 0
        $report.validationPerformance.metadataFetch.resourceLimitFallback | Should -BeFalse
    }

    It 'reaches the topic-apply block and exits cleanly on an empty allowlist' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/sync-profile.ps1'
        $allowlistPath = Join-Path $TestDrive 'empty-allowlist.json'
        '[]' | Set-Content -LiteralPath $allowlistPath -Encoding utf8

        $output = & pwsh -NoProfile -File $scriptPath -ApplyTopics -Offline `
            -TopicAllowlistPath $allowlistPath *>&1

        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'allowlist is empty'
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
        $script:RenderSmokeScript | Should -Match 'Start Here'
        $script:RenderSmokeScript | Should -Not -Match 'Catalog Snapshot'
        $script:RenderSmokeScript | Should -Not -Match 'Featured Projects'
        $script:RenderSmokeScript | Should -Match 'First-time setup'
        $script:RenderSmokeScript | Should -Match 'Tool Catalog'
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

Describe 'Generated profile PR validation handoff' -Tag 'Integration' {
    BeforeAll {
        $script:GeneratedPrHelper = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/open-generated-profile-pr.ps1') -Raw
        $script:GeneratedValidationStatusScriptPath = Join-Path $script:RepoRoot 'scripts/set-generated-validation-status.ps1'
        $script:GeneratedValidationStatusScript = Get-Content -LiteralPath $script:GeneratedValidationStatusScriptPath -Raw
    }

    It 'keeps helper scripts dormant while hosted workflows are absent' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/profile-sync.yml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/assets-refresh.yml') | Should -BeFalse
        $script:GeneratedPrHelper | Should -Match '\[switch\]\$DryRun'
        $script:GeneratedPrHelper | Should -Match 'Hosted generated pull-request creation is retired'
        $script:GeneratedPrHelper | Should -Match 'no branch, commit, push, pull request, commit status, or hosted validation dispatch will be created'
        $script:GeneratedPrHelper | Should -Not -Match 'gh pr create|gh workflow run|git push origin|git commit -m'
        $script:GeneratedValidationStatusScript | Should -Match 'Hosted generated validation status publishing is retired'
        $script:GeneratedValidationStatusScript | Should -Not -Match 'gh api -X POST|statuses/\$Sha'
    }

    It 'builds the generated validation status payload offline' {
        $sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $output = & pwsh -NoProfile -File $script:GeneratedValidationStatusScriptPath `
            -State pending `
            -Description 'Generated profile manual validation pending.' `
            -Repository 'SysAdminDoc/SysAdminDoc' `
            -Sha $sha `
            -TargetUrl 'https://github.com/SysAdminDoc/SysAdminDoc#local-validation' `
            -DryRun
        $payload = ($output | Out-String) | ConvertFrom-Json

        $payload.state | Should -Be 'pending'
        $payload.context | Should -Be 'generated-profile/manual-validation'
        $payload.description | Should -Be 'Generated profile manual validation pending.'
        $payload.target_url | Should -Match '#local-validation'
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
            pwsh -NoProfile -File $script:SummaryScriptPath -SummaryPath $summaryPath.FullName -Context 'Pester summary test'
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
            $summary | Should -Match 'README[.]md'
            $summary | Should -Match ('a' * 64)
            $summary | Should -Match ('b' * 64)
            $summary | Should -Match '## Tool Catalog'
            $summary | Should -Match 'assets/profile/footer-dark[.]svg'
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
            pwsh -NoProfile -File $script:SummaryScriptPath -SummaryPath $summaryPath.FullName -Context 'Pester summary budget test'
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
        $script:SummaryScript | Should -Match 'scheduledWorkflowFreshness'
    }
}

Describe 'Hosted automation removal contract' {
    It 'keeps workflow and Dependabot automation files absent' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/dependabot.yml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/renovate.json') | Should -BeFalse
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
        $result.Report.artifactDriftDiagnostics.projects.firstDiff.line | Should -Be 1
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

Describe 'Profile asset sync gate treats contribution heatmaps as time-sensitive' {
    It 'does not fail the fatal asset gate when only the live contribution heatmaps drift' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedReadme = New-Readme -Catalog $cat -Repos @()
        $expectedProjects = New-ProjectsExportJson -Catalog $cat -Repos @()
        $expectedAssets = @{
            'assets/profile/contributions-dark.svg'  = '<svg>drifted heatmap</svg>'
            'assets/profile/contributions-light.svg' = '<svg>drifted heatmap</svg>'
        }

        $result = Test-ProfileState -Catalog $cat -Repos @() `
            -ExpectedReadme $expectedReadme -ExpectedProjects $expectedProjects `
            -CurrentReadme $expectedReadme -CurrentProjects $expectedProjects `
            -ExpectedAssets $expectedAssets -SkipLinkValidation

        $result.Report.profileAssetsInSync | Should -BeTrue
        $contribRow = $result.Report.profileAssetChecks | Where-Object { $_.path -eq 'assets/profile/contributions-dark.svg' }
        $contribRow.inSync | Should -BeFalse
    }

    It 'still fails the fatal asset gate when a deterministic (non-contribution) asset drifts' {
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

Describe 'Scheduled workflow freshness gate' {
    It 'derives the max inter-run cadence from cron day-of-week schedules' {
        Get-CronMaxGapMinutes -Crons @('19 8 * * 3') | Should -Be 10080
        Get-CronMaxGapMinutes -Crons @('37 7 * * 2,5') | Should -Be 5760
        Get-CronMaxGapMinutes -Crons @('0 0 * * *') | Should -Be 1440
        Get-CronMaxGapMinutes -Crons @('0 0 1 * *') | Should -BeNullOrEmpty
    }

    It 'returns no scheduled workflow definitions when hosted workflows are absent' {
        $definitions = Get-ScheduledWorkflowDefinitions

        @($definitions) | Should -HaveCount 0
    }

    It 'reports not applicable when no scheduled workflow definitions exist' {
        $result = Test-ScheduledWorkflowFreshness -Definitions @() -RunLookup @{} -Now ([datetimeoffset]::Parse('2026-06-12T08:19:00Z'))

        $result.status | Should -Be 'not-applicable'
        $result.scheduledWorkflowCount | Should -Be 0
        $result.warningCount | Should -Be 0
        $result.rows | Should -BeNullOrEmpty
    }

    It 'reports ok when the latest successful scheduled run is within cadence plus grace' {
        $definitions = @([ordered]@{ workflowFile = '.github/workflows/assets-refresh.yml'; name = 'Profile assets refresh'; crons = @('19 8 * * 3'); hasWorkflowDispatch = $true })
        $lookup = @{
            '.github/workflows/assets-refresh.yml' = [ordered]@{
                available = $true
                state = 'active'
                latestScheduledConclusion = 'success'
                latestScheduledRunAt = '2026-06-10T08:19:00Z'
                latestSuccessfulScheduledAt = '2026-06-10T08:19:00Z'
                error = $null
            }
        }

        $result = Test-ScheduledWorkflowFreshness -Definitions $definitions -RunLookup $lookup -Now ([datetimeoffset]::Parse('2026-06-12T08:19:00Z'))
        $result.status | Should -Be 'ok'
        $result.scheduledWorkflowCount | Should -Be 1
        $result.warningCount | Should -Be 0
        $result.rows[0].status | Should -Be 'ok'
        $result.rows[0].cadenceMinutes | Should -Be 10080
    }

    It 'flags failing and stale scheduled runs as warnings' {
        $definitions = @(
            [ordered]@{ workflowFile = '.github/workflows/profile-sync.yml'; name = 'Profile sync'; crons = @('37 7 * * 2,5'); hasWorkflowDispatch = $true },
            [ordered]@{ workflowFile = '.github/workflows/assets-refresh.yml'; name = 'Profile assets refresh'; crons = @('19 8 * * 3'); hasWorkflowDispatch = $true }
        )
        $lookup = @{
            '.github/workflows/profile-sync.yml' = [ordered]@{
                available = $true
                state = 'active'
                latestScheduledConclusion = 'failure'
                latestScheduledRunAt = '2026-06-12T07:37:00Z'
                latestSuccessfulScheduledAt = '2026-06-09T07:37:00Z'
                error = $null
            }
            '.github/workflows/assets-refresh.yml' = [ordered]@{
                available = $true
                state = 'active'
                latestScheduledConclusion = 'success'
                latestScheduledRunAt = '2026-05-20T08:19:00Z'
                latestSuccessfulScheduledAt = '2026-05-20T08:19:00Z'
                error = $null
            }
        }

        $result = Test-ScheduledWorkflowFreshness -Definitions $definitions -RunLookup $lookup -Now ([datetimeoffset]::Parse('2026-06-12T12:00:00Z'))
        $result.status | Should -Be 'warning'
        $result.failingCount | Should -Be 1
        $result.staleCount | Should -Be 1
        ($result.rows | Where-Object { $_.workflowFile -eq '.github/workflows/profile-sync.yml' }).status | Should -Be 'failing'
        ($result.rows | Where-Object { $_.workflowFile -eq '.github/workflows/assets-refresh.yml' }).status | Should -Be 'stale'
    }

    It 'marks scheduled workflows unavailable when run evidence is missing' {
        $definitions = @([ordered]@{ workflowFile = '.github/workflows/scorecard.yml'; name = 'OpenSSF Scorecard'; crons = @('43 8 * * 4'); hasWorkflowDispatch = $false })
        $lookup = @{
            '.github/workflows/scorecard.yml' = [ordered]@{
                available = $false
                state = 'unknown'
                latestScheduledConclusion = $null
                latestScheduledRunAt = $null
                latestSuccessfulScheduledAt = $null
                error = 'gh authentication unavailable'
            }
        }

        $result = Test-ScheduledWorkflowFreshness -Definitions $definitions -RunLookup $lookup -Now ([datetimeoffset]::Parse('2026-06-12T12:00:00Z'))
        $result.unavailableCount | Should -Be 1
        $result.rows[0].status | Should -Be 'unavailable'
        ($result.rows[0].warning) | Should -Match 'unavailable'
    }

    It 'exposes a scheduledWorkflowFreshness contract in the summary script and report schema' {
        $summaryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1') -Raw
        $summaryScript | Should -Match 'scheduledWorkflowFreshness'
        $summaryScript | Should -Match 'Scheduled workflow freshness'

        $schema = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'schemas/profile-sync-report.v1.json') -Raw | ConvertFrom-Json
        $schema.properties.scheduledWorkflowFreshness.'$ref' | Should -Be '#/$defs/scheduledWorkflowFreshness'

        # Field parity for the aggregate object and per-row item.
        $sample = Test-ScheduledWorkflowFreshness `
            -Definitions @([ordered]@{ workflowFile = '.github/workflows/assets-refresh.yml'; name = 'Profile assets refresh'; crons = @('19 8 * * 3'); hasWorkflowDispatch = $true }) `
            -RunLookup @{ '.github/workflows/assets-refresh.yml' = [ordered]@{ available = $true; state = 'active'; latestScheduledConclusion = 'success'; latestScheduledRunAt = '2026-06-10T08:19:00Z'; latestSuccessfulScheduledAt = '2026-06-10T08:19:00Z'; error = $null } } `
            -Now ([datetimeoffset]::Parse('2026-06-12T08:19:00Z'))

        $aggregateKeys = @($sample.Keys) | Sort-Object
        $schemaAggregateKeys = @($schema.'$defs'.scheduledWorkflowFreshness.properties.PSObject.Properties.Name) | Sort-Object
        ($aggregateKeys -join ',') | Should -Be ($schemaAggregateKeys -join ',')

        $rowKeys = @($sample.rows[0].Keys) | Sort-Object
        $schemaRowKeys = @($schema.'$defs'.scheduledWorkflowFreshness.properties.rows.items.properties.PSObject.Properties.Name) | Sort-Object
        ($rowKeys -join ',') | Should -Be ($schemaRowKeys -join ',')
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
        $script:SyncProfileScript | Should -Match 'Test-Json -Json \$json -SchemaFile \$fullPath'
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
            -Version ([version]'7.6.3') `
            -Edition 'Core' `
            -NativeJsonSchemaAvailable $true `
            -Now ([datetimeoffset]::Parse('2026-07-06T00:00:00Z'))

        $result.status | Should -Be 'ok'
        $result.current.channel | Should -Be 'current-lts'
        $result.supported | Should -BeTrue
        $result.preferred | Should -BeTrue
        $result.warningCount | Should -Be 0
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

    It 'reports ok across the committed profile SVG assets' {
        $result = Test-ProfileAssetsAccessibility
        $result.status | Should -Be 'ok'
        $result.assetCount | Should -BeGreaterThan 0
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
        $validationScript | Should -Match 'Dependency review: \{0\}; npm audit: \{1\}; pin freshness: \{2\}'
        $validationScript | Should -Match 'Pester"; Version = "5\.8\.0"'
        $validationScript | Should -Match 'PSScriptAnalyzer"; Version = "1\.25\.0"'
        $validationScript | Should -Match 'Invoke-ScriptAnalyzer'
        $validationScript | Should -Match 'Invoke-Pester -Configuration'
        $validationScript | Should -Match 'CodeCoverage\.Enabled = \$true'
        $validationScript | Should -Match 'OutputFormat = "JaCoCo"'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/tests.yml') | Should -BeFalse
    }
}

Describe 'Local dependency advisory review' -Tag 'Integration' {
    BeforeAll {
        $script:DependencyReviewScriptPath = Join-Path $script:RepoRoot 'scripts/review-local-dependencies.ps1'
        $script:DependencyReviewScript = Get-Content -LiteralPath $script:DependencyReviewScriptPath -Raw
        $script:DependencyReviewPackage = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'package.json') | ConvertFrom-Json -AsHashtable
        $script:DependencyReviewReadme = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'README.md')
    }

    It 'documents a local dependency review command without hosted automation' {
        Test-Path -LiteralPath $script:DependencyReviewScriptPath | Should -BeTrue
        $script:DependencyReviewPackage.scripts['review:dependencies'] | Should -Be 'pwsh -NoProfile -File ./scripts/review-local-dependencies.ps1'
        $script:DependencyReviewReadme | Should -Match 'npm run review:dependencies'
        $script:DependencyReviewReadme | Should -Match 'manual dependency and advisory review'
        $script:DependencyReviewReadme | Should -Match 'package override drift'
        $script:DependencyReviewReadme | Should -Match 'latest-known npm/Python audit-tool freshness'
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

            $output = & pwsh -NoProfile -File $script:DependencyReviewScriptPath -NpmAuditJsonPath $auditPath
            $LASTEXITCODE | Should -Be 0
            $report = ($output -join "`n") | ConvertFrom-Json

            $report.status | Should -Be 'ok'
            $report.policy | Should -Be 'manual-local-only'
            $report.commands.full | Should -Match 'review-local-dependencies[.]ps1'
            $report.pinFreshness.status | Should -Be 'fresh'
            $report.pinFreshness.latestCheckedAt | Should -Be '2026-07-06'
            $report.pinFreshness.warningCount | Should -Be 0
            $report.npm.audit.status | Should -Be 'clean'
            $report.npm.audit.severityCounts.total | Should -Be 0
            $report.npm.overrides.count | Should -BeGreaterThan 0
            $report.npm.overrides.rows.package | Should -Contain 'js-yaml'
            $report.npm.overrides.rows.package | Should -Contain 'markdown-it'
            ($report.npm.overrides.rows | Where-Object { $_.package -eq 'js-yaml' }).status | Should -Be 'aligned'
            $report.npm.devDependencyPins.package | Should -Contain 'markdownlint-cli2'
            ($report.npm.devDependencyPins | Where-Object { $_.package -eq 'markdownlint-cli2' }).status | Should -Be 'aligned'
            $markdownlintFreshness = $report.pinFreshness.npm.rows | Where-Object { $_.name -eq 'markdownlint-cli2' }
            $markdownlintFreshness.currentVersion | Should -Be '0.23.0'
            $markdownlintFreshness.latestKnownVersion | Should -Be '0.23.0'
            $markdownlintFreshness.latestStatus | Should -Be 'current'
            $jsYamlFreshness = $report.pinFreshness.npm.rows | Where-Object { $_.name -eq 'js-yaml' }
            $jsYamlFreshness.latestKnownVersion | Should -Be '5.2.1'
            $markdownItFreshness = $report.pinFreshness.npm.rows | Where-Object { $_.name -eq 'markdown-it' }
            $markdownItFreshness.latestKnownVersion | Should -Be '14.3.0'
            $report.powershell.requiredModules.name | Should -Contain 'Pester'
            $report.powershell.requiredModules.name | Should -Contain 'PSScriptAnalyzer'
            ($report.powershell.requiredModules | Where-Object { $_.name -eq 'Pester' }).requiredVersion | Should -Be '5.8.0'
            $report.python.auditTools.name | Should -Contain 'zizmor'
            ($report.python.auditTools | Where-Object { $_.name -eq 'zizmor' }).hashPinned | Should -BeTrue
            $zizmorFreshness = $report.pinFreshness.python.rows | Where-Object { $_.name -eq 'zizmor' }
            $zizmorFreshness.currentVersion | Should -Be '1.26.1'
            $zizmorFreshness.latestKnownVersion | Should -Be '1.26.1'
            $zizmorFreshness.latestStatus | Should -Be 'current'
        } finally {
            if (Test-Path -LiteralPath $auditPath) {
                Remove-Item -LiteralPath $auditPath -Force
            }
        }
    }

    It 'warns but does not fail when latest-known pin evidence is stale' {
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

            $output = & pwsh -NoProfile -File $script:DependencyReviewScriptPath -NpmAuditJsonPath $auditPath -PinLatestCheckedAt '2026-05-01'
            $LASTEXITCODE | Should -Be 0
            $report = ($output -join "`n") | ConvertFrom-Json

            $report.status | Should -Be 'ok'
            $report.pinFreshness.status | Should -Be 'stale'
            $report.pinFreshness.warningCount | Should -BeGreaterThan 0
            $report.pinFreshness.warnings[0] | Should -Match 'refresh the manual pin review'
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

            $output = & pwsh -NoProfile -File $script:DependencyReviewScriptPath -NpmAuditJsonPath $auditPath *>&1
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
        '$requiredModules = @([pscustomobject]@{ Name = "Pester"; Version = "5.8.0" })' |
            Set-Content -LiteralPath (Join-Path $root 'scripts/validate-local.ps1') -Encoding utf8

        $output = & pwsh -NoProfile -File $script:DependencyReviewScriptPath -RepoRoot $root -SkipNpmAudit *>&1
        $LASTEXITCODE | Should -Be 1
        $report = ($output -join "`n") | ConvertFrom-Json

        $report.status | Should -Be 'review-needed'
        $report.npm.audit.status | Should -Be 'skipped'
        $report.npm.overrides.driftCount | Should -Be 1
    }
}
