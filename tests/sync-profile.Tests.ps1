#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Hermetic (offline) Pester tests for scripts/sync-profile.ps1.

    The script is dot-sourced so only its function library loads (the live
    GitHub fetch + generation block is guarded by an InvocationName check).
    These tests never touch the network.

    Run:  pwsh -NoProfile -Command "Invoke-Pester -Path tests"
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    # Dot-source the library. The script's test seam stops before the fetch/main block.
    . (Join-Path $script:RepoRoot 'scripts/sync-profile.ps1')
    # Run offline so nothing reaches out to GitHub.
    $script:Offline = $true

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
}

Describe 'Function library loads via the dot-source test seam' {
    It 'exposes the core functions without running the fetch/main block' {
        Get-Command New-Readme, New-ProjectsExportJson, Get-InstallSnippet, Test-HttpUrl, Get-Catalog -ErrorAction SilentlyContinue |
            Should -HaveCount 5
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
}

Describe 'Test-HttpUrl result shape (no network calls)' {
    It 'returns a record carrying the fatal flag' {
        # Unresolvable host -> transient failure (never fatal); does not require a live server.
        $r = Test-HttpUrl -Url 'https://nonexistent.invalid.example/nope' -TimeoutSec 2 -Retries 1
        $r.Keys | Should -Contain 'fatal'
        $r.ok | Should -BeFalse
        $r.fatal | Should -BeFalse
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
            [ordered]@{ path = '.github/ISSUE_TEMPLATE/workflow-ci.yml'; required = $true; exists = $true },
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
                dependabot_security_updates = [pscustomobject]@{ status = 'disabled' }
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
        $codeScanningEvidence = [ordered]@{
            codeqlWorkflowPresent = $false
            sarifUploadWorkflowPresent = $true
            scorecardSarifUploadPresent = $true
            psScriptAnalyzerWorkflowPresent = $true
            actionlintWorkflowPresent = $true
            zizmorWorkflowPresent = $true
        }

        $result = Test-RepositoryCommunityBaseline -Repository $repository -CommunityProfile $community -BranchProtection $branchProtection -Rulesets @() -Languages $languages -LocalFiles $script:LocalCommunityFilesOk -CodeScanningLocalEvidence $codeScanningEvidence
        $repoSettings = $result['repositorySettings']
        $communityHealth = $result['communityHealth']

        $repoSettings.available | Should -BeTrue
        $repoSettings.security.secretScanning | Should -Be 'enabled'
        $repoSettings.security.secretScanningPushProtection | Should -Be 'enabled'
        $repoSettings.security.dependabotSecurityUpdates | Should -Be 'disabled'
        $repoSettings.security.codeScanning.status | Should -Be 'not-applicable'
        $repoSettings.security.codeScanning.recommendation | Should -Be 'not-applicable-powershell-only'
        $repoSettings.security.codeScanning.reason | Should -Match 'CodeQL-supported source language'
        $repoSettings.security.codeScanning.codeqlSupportedLanguageDetected | Should -BeFalse
        @($repoSettings.security.codeScanning.codeqlSupportedLanguages) | Should -HaveCount 0
        $repoSettings.security.codeScanning.codeqlWorkflowPresent | Should -BeFalse
        $repoSettings.security.codeScanning.sarifUploadWorkflowPresent | Should -BeTrue
        $repoSettings.security.codeScanning.scorecardSarifUploadPresent | Should -BeTrue
        $repoSettings.security.codeScanning.activeControls | Should -Contain 'psscriptanalyzer'
        $repoSettings.security.codeScanning.activeControls | Should -Contain 'actionlint'
        $repoSettings.security.codeScanning.activeControls | Should -Contain 'zizmor'
        $repoSettings.security.codeScanning.activeControls | Should -Contain 'openssf-scorecard-sarif'
        $repoSettings.branchProtection.requiredStatusChecks | Should -BeFalse
        $repoSettings.rulesets.count | Should -Be 0
        $repoSettings.warningCount | Should -BeGreaterThan 0
        ($repoSettings.warnings -join ' ') | Should -Match 'Dependabot security updates'
        ($repoSettings.warnings -join ' ') | Should -Match 'status checks'
        ($repoSettings | ConvertTo-Json -Depth 20) | Should -Not -Match 'alert|secret_value|token'

        $communityHealth.available | Should -BeTrue
        $communityHealth.healthPercentage | Should -Be 71
        $communityHealth.providerFiles.issueTemplate | Should -BeFalse
        $communityHealth.localRequiredMissingCount | Should -Be 0
        $communityHealth.fatalCount | Should -Be 0
        ($communityHealth.warnings -join ' ') | Should -Match 'issue-template'
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

    It 'treats release 404 as no release while keeping rate limits fatal' {
        Test-GhApiNotFound -Output 'gh: Not Found (HTTP 404)' | Should -BeTrue
        Test-GhApiNotFound -Output 'gh: API rate limit exceeded (HTTP 403)' | Should -BeFalse
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

        $result.targetCount | Should -Be 3
        $result.throttleLimit | Should -Be 2
        @($result.failures) | Should -HaveCount 1
        @($result.warnings) | Should -HaveCount 2
        $result.failures[0].host | Should -Be 'sysadmindoc.github.io'

        $rawHost = @($result.warningCountByHost | Where-Object { $_.host -eq 'raw.githubusercontent.com' })
        $rawHost | Should -HaveCount 1
        $rawHost[0].count | Should -Be 2
        @($result.headerHostWarnings) | Should -HaveCount 0
    }

    It 'adds non-catalog profile links and keeps image-host outages nonfatal' {
        $readme = @'
**[View my full portfolio](https://sysadmindoc.github.io/)**

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
        $trust.trustLevel | Should -Be 'signed-and-attested'
    }

    It 'reports repos missing topics or public descriptions' {
        $noTopicsEntry = New-TestEntry -Repo 'NoTopics' -Category 'powershell' -Description 'Catalog Windows utility'
        $noDescriptionEntry = New-TestEntry -Repo 'NoDescription' -Category 'web' -Description 'Catalog web dashboard'
        $repos = @(
            (New-TestRepoMeta -Name 'NoTopics' -Topics @() -Description 'has description'),
            (New-TestRepoMeta -Name 'NoDescription' -Topics @('windows') -Description ''),
            (New-TestRepoMeta -Name 'CompleteRepo' -Topics @('windows') -Description 'ready')
        )

        $result = Test-MetadataHygiene -Repos $repos -CatalogEntries @($noTopicsEntry, $noDescriptionEntry)

        $result.missingTopicCount | Should -Be 1
        ($result.missingTopics | ForEach-Object { $_.repo }) | Should -Contain 'NoTopics'
        $result.missingTopics[0].category | Should -Be 'powershell'
        $result.missingTopics[0].topicHints | Should -Contain 'powershell'
        $result.missingTopics[0].topicHints | Should -Contain 'windows'
        $result.topicHintPolicy.requiresExplicitAllowlist | Should -BeTrue
        $result.topicHintPolicy.mutatesRepositories | Should -BeFalse
        $result.missingDescriptionCount | Should -Be 1
        ($result.missingDescriptions | ForEach-Object { $_.repo }) | Should -Contain 'NoDescription'
        $result.missingDescriptions[0].catalogDescription | Should -Be 'Catalog web dashboard'
    }

    It 'falls back to a generic topic hint when catalog and language signals are empty' {
        $suppressedEntry = New-TestEntry -Repo 'NoSignals' -Category 'suppressed' -Description ''
        $repos = @(
            (New-TestRepoMeta -Name 'NoSignals' -Topics @() -Description '' -Language $null)
        )

        $result = Test-MetadataHygiene -Repos $repos -CatalogEntries @($suppressedEntry)

        $result.missingTopics[0].topicHints | Should -Contain 'utility'
    }

    It 'summarizes visitor-facing project license metadata gaps' {
        $winTool = New-TestEntry -Repo 'WinTool' -Category 'powershell'
        $pyTool = New-TestEntry -Repo 'PyTool' -Category 'python'
        $webTool = New-TestEntry -Repo 'WebTool' -Category 'web'
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -LicenseInfo ([pscustomobject]@{ key = 'mit'; name = 'MIT License' })),
            (New-TestRepoMeta -Name 'PyTool' -LicenseInfo $null),
            (New-TestRepoMeta -Name 'WebTool' -LicenseInfo ([pscustomobject]@{ key = 'other'; name = 'Other' }))
        )
        $lookup = ConvertTo-Lookup $repos

        $result = Test-ProjectLicenseMetadata -Entries @($winTool, $pyTool, $webTool) -RepoLookup $lookup

        $result.checkedCount | Should -Be 3
        $result.detectedCount | Should -Be 2
        $result.missingCount | Should -Be 1
        $result.unknownCount | Should -Be 1
        $result.warningCount | Should -Be 2
        ($result.missingLicenses | ForEach-Object { $_.repo }) | Should -Contain 'PyTool'
        ($result.unknownLicenses | ForEach-Object { $_.repo }) | Should -Contain 'WebTool'
        ($result.licenseCounts | Where-Object { $_.licenseSpdxId -eq 'MIT' }).count | Should -Be 1
        ($result.licenseCounts | Where-Object { $_.licenseSpdxId -eq 'NOASSERTION' }).licenseKey | Should -Be 'other'
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
        $repos = @(
            (New-TestRepoMeta -Name 'MatchingFork' -IsFork $true -Parent ([pscustomobject]@{ nameWithOwner = 'Upstream/MatchingFork' })),
            (New-TestRepoMeta -Name 'ContinuationOnly' -IsFork $false),
            (New-TestRepoMeta -Name 'MissingAttribution' -IsFork $true -Parent ([pscustomobject]@{ nameWithOwner = 'Upstream/MissingAttribution' })),
            (New-TestRepoMeta -Name 'MismatchedFork' -IsFork $true -Parent ([pscustomobject]@{ nameWithOwner = 'GitHub/ActualParent' })),
            (New-TestRepoMeta -Name 'ParentUnavailable' -IsFork $true -ForkParentFetchError 'api unavailable')
        )

        $result = Test-ForkParentDrift -Repos $repos -CatalogEntries @($match, $continuation, $missing, $mismatch, $unavailable)

        $result.checkedCount | Should -Be 5
        $result.githubForkCount | Should -Be 4
        $result.catalogForkOfCount | Should -Be 3
        $result.matchingGitHubForkCount | Should -Be 1
        $result.catalogContinuationCount | Should -Be 1
        $result.missingCatalogAttributionCount | Should -Be 2
        $result.parentMismatchCount | Should -Be 1
        $result.parentUnavailableCount | Should -Be 1
        $result.warningCount | Should -Be 4
        ($result.matchingGitHubForks | ForEach-Object { $_.repo }) | Should -Contain 'MatchingFork'
        ($result.catalogContinuations | ForEach-Object { $_.repo }) | Should -Contain 'ContinuationOnly'
        ($result.missingCatalogAttribution | ForEach-Object { $_.repo }) | Should -Contain 'MissingAttribution'
        ($result.parentMismatches | ForEach-Object { $_.repo }) | Should -Contain 'MismatchedFork'
        ($result.parentUnavailable | ForEach-Object { $_.repo }) | Should -Contain 'ParentUnavailable'
    }

    It 'reports stale and archive review candidates without exposing suppressed names' {
        $current = New-TestEntry -Repo 'CurrentTool' -Category 'powershell'
        $stale = New-TestEntry -Repo 'StaleTool' -Category 'python'
        $oldRelease = New-TestEntry -Repo 'OldReleaseTool' -Category 'desktop'
        $archive = New-TestEntry -Repo 'ArchiveCandidate' -Category 'guides'
        $suppressedPrivate = New-TestEntry -Repo 'HiddenPrivate' -Category 'suppressed'
        $suppressedPrivate.suppressionReason = 'Repo is private; public profile links would 404 for visitors.'
        $suppressedDuplicate = New-TestEntry -Repo 'HiddenDuplicate' -Category 'suppressed'
        $suppressedDuplicate.suppressionReason = 'Renamed duplicate profile entry.'
        $repos = @(
            (New-TestRepoMeta -Name 'CurrentTool' -PushedAt '2026-06-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'StaleTool' -PushedAt '2025-01-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'OldReleaseTool' -WithRelease -PushedAt '2026-06-01T00:00:00Z' -ReleasePublishedAt '2024-01-01T00:00:00Z'),
            (New-TestRepoMeta -Name 'ArchiveCandidate' -PushedAt '2023-01-01T00:00:00Z')
        )
        $lookup = ConvertTo-Lookup $repos

        $result = Test-StaleProjectReview `
            -Entries @($current, $stale, $oldRelease, $archive, $suppressedPrivate, $suppressedDuplicate) `
            -RepoLookup $lookup `
            -Now ([datetimeoffset]'2026-06-06T00:00:00Z')

        $result.checkedProjectCount | Should -Be 4
        $result.staleAfterDays | Should -Be 365
        $result.releaseStaleAfterDays | Should -Be 540
        $result.archiveAfterDays | Should -Be 730
        $result.staleProjectCount | Should -Be 3
        $result.archiveReviewCount | Should -Be 1
        $result.noReleaseCount | Should -Be 3
        $result.suppressedCount | Should -Be 2
        $result.warningCount | Should -Be 3
        ($result.rows | ForEach-Object { $_.repo }) | Should -Contain 'StaleTool'
        ($result.rows | ForEach-Object { $_.repo }) | Should -Contain 'OldReleaseTool'
        ($result.rows | ForEach-Object { $_.repo }) | Should -Contain 'ArchiveCandidate'
        ($result.rows | Where-Object { $_.repo -eq 'OldReleaseTool' }).signals | Should -Contain 'release-stale'
        ($result.rows | Where-Object { $_.repo -eq 'ArchiveCandidate' }).status | Should -Be 'archive-review'
        ($result.suppressionReasonCounts | ForEach-Object { $_.reasonCode }) | Should -Contain 'private-or-sensitive'
        ($result.suppressionReasonCounts | ForEach-Object { $_.reasonCode }) | Should -Contain 'duplicate-or-superseded'
        ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'HiddenPrivate|HiddenDuplicate'
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
        ($result.releaseTrustLevelCounts | ForEach-Object { $_.trustLevel }) | Should -Contain 'checksum'
        $result.assetApiInspected | Should -BeTrue
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

        $result = Test-UserscriptInstallTrust -Entries @($broad, $scoped) -ContentByUrl $contentByUrl

        $result.checkedCount | Should -Be 2
        $result.rawGitHubCount | Should -Be 2
        $result.branchSourceCount | Should -Be 1
        $result.tagOrCommitSourceCount | Should -Be 1
        $result.metadataBlockCount | Should -Be 2
        $result.broadScopeCount | Should -Be 1
        $result.missingUpdateUrlCount | Should -Be 1
        $result.missingDownloadUrlCount | Should -Be 1
        $result.warningCount | Should -Be 3
        $broadRow = $result.rows | Where-Object { $_.repo -eq 'BroadScript' }
        $broadRow.name | Should -Be 'Broad Script'
        $broadRow.sourceRef | Should -Be 'main'
        $broadRow.sourceRefType | Should -Be 'branch'
        ($broadRow.warnings | ForEach-Object { $_.kind }) | Should -Contain 'scope-broad'
        ($broadRow.warnings | ForEach-Object { $_.kind }) | Should -Contain 'update-url-missing'
        ($broadRow.warnings | ForEach-Object { $_.kind }) | Should -Contain 'download-url-missing'
        $scopedRow = $result.rows | Where-Object { $_.repo -eq 'ScopedScript' }
        $scopedRow.sourceRefType | Should -Be 'tag'
        $scopedRow.warningCount | Should -Be 0
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
    It 'omits the generated catalog notice when the current README uses the compact header' {
        $script:rendered | Should -Not -Match ([regex]::Escape($GeneratedCatalogNotice))
    }
    It 'renders setup inspect-before-run and check-only guidance' {
        $script:rendered | Should -Match 'Inspect before installing'
        $script:rendered | Should -Match ([regex]::Escape('$u=''https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1'''))
        $script:rendered | Should -Match 'SysAdminDoc-setup\.ps1'
        $script:rendered | Should -Match '-CheckOnly'
        $script:rendered | Should -Match 'SysAdminDoc-setup-\*\.log'
    }
    It 'renders upstream and license attribution in featured and category rows' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $entry = @($cat.entries | Where-Object { $_.repo -eq 'WinTool' })[0]
        $entry.forkOf = 'UpstreamOrg/WinTool'
        $entry.upstreamLicense = 'MIT'
        $entry.featured = $true
        $entry.featuredRank = 1

        $rendered = New-Readme -Catalog $cat -Repos @()

        [regex]::Matches($rendered, 'Upstream: \[UpstreamOrg/WinTool\]\(https://github\.com/UpstreamOrg/WinTool\); License: MIT').Count | Should -BeGreaterOrEqual 2
    }
    It 'preserves the minimal public profile header without adding personal chrome' {
        $script:rendered.TrimStart() | Should -Match '^\*\*\[View my full portfolio'
        $script:rendered | Should -Not -Match '### Professional Focus'
        $script:rendered | Should -Not -Match 'Healthcare IT engineer and DICOM/PACS specialist'
        $script:rendered | Should -Not -Match 'Currently Building'
        $script:rendered | Should -Not -Match 'https://skillicons\.dev'
        $script:rendered | Should -Not -Match 'assets/profile/(stats|languages|activity)-(dark|light)\.svg'
        $script:rendered | Should -Not -Match 'capsule-render\.vercel\.app|readme-typing-svg|[?&]animation=|[?&]repeat=true'
        $script:rendered | Should -Not -Match 'komarev\.com|github-readme-stats|streak-stats|github-readme-activity-graph'
        $script:rendered | Should -Not -Match 'img\.shields\.io/github/(followers|stars)'
    }
    It 'keeps the generated catalog compact when the README omits the discovery block' {
        $script:rendered | Should -Not -Match ([regex]::Escape($GeneratedCatalogNotice))
        $script:rendered | Should -Not -Match '### Start Here'
        $script:rendered | Should -Not -Match '### Catalog Snapshot'
        $script:rendered | Should -Match '### Featured Projects'
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
        $density.warningCount | Should -BeGreaterThan 0
        ($density.warnings -join ' ') | Should -Match 'portfolio-only review'
    }
    It 'reports the generated catalog notice in README experience checks' {
        $result = Test-ReadmeExperience -Catalog $script:cat -Repos @() -ExpectedReadme $script:rendered
        $result.generatedCatalogNotice | Should -BeFalse
        $result.startHereSection | Should -BeFalse
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
        $assets.Keys | Should -Contain 'assets/profile/footer-dark.svg'
        $assets.Keys | Should -Contain 'assets/profile/footer-light.svg'
        $assets['assets/profile/header-dark.svg'] | Should -Match 'SysAdminDoc profile header'
        $assets['assets/profile/stats-dark.svg'] | Should -Match '<svg'
        $assets['assets/profile/stats-dark.svg'] | Should -Match '<title id="profile-sysadmindoc-catalog-stats-dark-title">SysAdminDoc Catalog Stats</title>'
        $assets['assets/profile/stats-dark.svg'] | Should -Match 'total public stars'
        $assets['assets/profile/stats-dark.svg'] | Should -Match '>7</text>'
        $assets['assets/profile/activity-light.svg'] | Should -Match 'Release Asset Health'
        $assets['assets/profile/footer-light.svg'] | Should -Match 'Static footer divider'

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
}

Describe 'Update-Header idempotency' {
    It 'produces identical output when run twice on the same input' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repoLookup = ConvertTo-Lookup @()
        $entries = @($cat.entries | Where-Object {
            $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
        })
        $header = @(
            '### Professional Focus'
            ''
            'Test engineer with 16+ years.'
            ''
            '**Currently Building**'
            ''
            '| Project | Focus | Action |'
            '|:--------|:------|:------:|'
            '| [**WinTool**](https://github.com/SysAdminDoc/WinTool) | A test PowerShell tool | [Repo](https://github.com/SysAdminDoc/WinTool) |'
            ''
            '---'
        ) -join [Environment]::NewLine

        $first = Update-Header -Header $header -PublicRepoCount 10 -Entries $entries -RepoLookup $repoLookup
        $second = Update-Header -Header $first -PublicRepoCount 10 -Entries $entries -RepoLookup $repoLookup

        $second | Should -Be $first
    }

    It 'updates the repo count in the portfolio line' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $repoLookup = ConvertTo-Lookup @()
        $entries = @($cat.entries | Where-Object {
            $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
        })
        $header = @(
            '### Professional Focus'
            ''
            'Public portfolio: 100 active repos, 50 visitor-facing projects, stuff.'
        ) -join [Environment]::NewLine

        $result = Update-Header -Header $header -PublicRepoCount 200 -Entries $entries -RepoLookup $repoLookup

        $result | Should -Match 'Public portfolio: 200 active repos'
        $result | Should -Match "$($entries.Count) visitor-facing projects"
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
        $script:setupSource | Should -Match 'Run without -CheckOnly to install with winget'
    }

    It 'writes a best-effort setup transcript under temp' {
        $script:setupSource | Should -Match 'Start-Transcript'
        $script:setupSource | Should -Match 'SysAdminDoc-setup-\{0\}-\{1\}\.log'
        $script:setupSource | Should -Match '\$PID'
        $script:setupSource | Should -Match 'Stop-Transcript'
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

    It 'accounts for every fixture catalog row as exported or redacted' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @()

        $result = Test-CatalogFeedAccounting -Catalog $cat -ProjectsJson $json

        $result.passed | Should -BeTrue
        $result.catalogEntryCount | Should -Be 4
        $result.visitorFacingCatalogCount | Should -Be 3
        $result.suppressedCatalogCount | Should -Be 1
        $result.exportedProjectCount | Should -Be 3
        $result.exportedSuppressedCount | Should -Be 1
        $result.unaccountedRowCount | Should -Be 0
        $result.fatalCount | Should -Be 0
        $result.unaccountedRows | Should -BeNullOrEmpty
    }

    It 'reports downstream portfolio compatibility for generated feed rows' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @()

        $result = Test-PortfolioFeedCompatibility -ProjectsJson $json

        $result.status | Should -Be 'compatible'
        $result.projectCount | Should -Be 3
        $result.suppressedCount | Should -Be 1
        $result.projectCountMatchesTopLevel | Should -BeTrue
        $result.suppressedCountMatchesTopLevel | Should -BeTrue
        $result.missingProjectFieldCount | Should -Be 0
        $result.suppressedIdentifierLeakCount | Should -Be 0
        $result.redactedSuppressedRowsCompatible | Should -BeTrue
        $result.provenanceAvailable | Should -BeTrue
        $result.releaseTrustAvailable | Should -BeTrue
        ($result.primaryActionKindCounts | ForEach-Object { $_.kind }) | Should -Contain 'repo'
        ($result.primaryActionKindCounts | ForEach-Object { $_.kind }) | Should -Contain 'live'
        $result.fatalCount | Should -Be 0
    }

    It 'flags visible project rows missing downstream-required fields' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $payload.projects[0].repoUrl = ''
        $json = $payload | ConvertTo-Json -Depth 50

        $result = Test-PortfolioFeedCompatibility -ProjectsJson $json

        $result.status | Should -Be 'incompatible'
        $result.missingProjectFieldCount | Should -Be 1
        $result.missingProjectFields[0].field | Should -Be 'repoUrl'
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
        $winTool.releaseTrust.trustLevel | Should -Be 'checksum'
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

        $result.passed | Should -BeTrue
        $result.catalogEntryCount | Should -Be 187
        $result.visitorFacingCatalogCount | Should -Be 177
        $result.suppressedCatalogCount | Should -Be 10
        $result.exportedProjectCount | Should -Be 177
        $result.exportedSuppressedCount | Should -Be 10
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
        $payload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $payload.projects[0].repo = $null

        $result = Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-projects.v1.json'

        $result.valid | Should -BeFalse
        ($result.errors -join "`n") | Should -Match '\$\.projects\[0\]\.repo'
    }

    It 'rejects suppressed feed rows that expose project identifiers' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $payload = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $payload.suppressed[0] | Add-Member -NotePropertyName repo -NotePropertyValue 'HiddenTool'
        $payload.suppressed[0] | Add-Member -NotePropertyName repoUrl -NotePropertyValue 'https://github.com/SysAdminDoc/HiddenTool'

        $result = Test-JsonSchemaContract -Value $payload -SchemaPath 'schemas/profile-projects.v1.json'

        $result.valid | Should -BeFalse
        ($result.errors -join "`n") | Should -Match '\$\.suppressed\[0\]\.repo'
        ($result.errors -join "`n") | Should -Match '\$\.suppressed\[0\]\.repoUrl'
    }

    It 'ignores volatile provenance fields in projects sync comparison' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $current = New-ProjectsExportJson -Catalog $cat -Repos @()
        $expectedPayload = $current | ConvertFrom-Json
        $expectedPayload.provenance.metadataSnapshotAt = '2026-06-06T00:00:00Z'
        $expectedPayload.provenance.sourceCommit = '0000000000000000000000000000000000000000'
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

    It 'validates the committed profile sync report contract' {
        $report = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') -Raw)

        $result = Test-JsonSchemaContract -Value $report -SchemaPath 'schemas/profile-sync-report.v1.json'

        $report.schema | Should -Be 'https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/schemas/profile-sync-report.v1.json'
        $report.schemaValidation.report.schemaPath | Should -Be 'schemas/profile-sync-report.v1.json'
        $report.schemaValidation.report.valid | Should -BeTrue
        $result.valid | Should -BeTrue
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
        ($result.errors -join "`n") | Should -Match '\$\.releaseAssetDrift is required'
    }

    It 'warns when a schema uses keywords the validator cannot check' {
        $schemaPath = Join-Path $TestDrive 'unsupported.json'
        Set-Content -LiteralPath $schemaPath -Value '{"type":"object","oneOf":[{"type":"string"}],"maxLength":10}' -Encoding utf8

        $result = Test-JsonSchemaContract -Value @{} -SchemaPath $schemaPath

        @($result.unsupportedKeywords).Count | Should -BeGreaterOrEqual 2
        ($result.unsupportedKeywords -join "`n") | Should -Match 'oneOf'
        ($result.unsupportedKeywords -join "`n") | Should -Match 'maxLength'
    }
}

Describe 'Doc version consistency gate' {
    BeforeAll {
        function New-TestPlanningDocSet {
            param(
                [string]$Version = 'v4.9.20',
                [string]$Date = '2026-06-04',
                [string]$RoadmapVersion = $Version,
                [string]$ProjectContextVersion = $Version,
                [string]$ResearchReportVersion = $Version,
                [string]$ChangelogDate = $Date,
                [string]$RoadmapDate = $Date,
                [string]$ProjectContextDate = $Date,
                [string]$ResearchRefreshDate = $Date,
                [string[]]$ChangelogExtraLines = @()
            )

            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root | Out-Null
            $paths = [ordered]@{
                RoadmapPath = Join-Path $root 'ROADMAP.md'
                ChangelogPath = Join-Path $root 'CHANGELOG.md'
                ProjectContextPath = Join-Path $root 'PROJECT_CONTEXT.md'
                ResearchReportPath = Join-Path $root 'RESEARCH_REPORT.md'
            }

            Set-Content -LiteralPath $paths.RoadmapPath -Value @(
                '# Roadmap'
                ''
                "Latest profile sync: $RoadmapDate"
                "Current repo version: $RoadmapVersion"
            ) -Encoding utf8
            $changelogLines = @(
                '# Changelog'
                ''
                "## [$Version] - $ChangelogDate"
                ''
                '- Changed: test.'
            ) + $ChangelogExtraLines
            Set-Content -LiteralPath $paths.ChangelogPath -Value $changelogLines -Encoding utf8
            Set-Content -LiteralPath $paths.ProjectContextPath -Value @(
                '# Project Context'
                ''
                "Latest sync date: $ProjectContextDate"
                "Version: $ProjectContextVersion"
            ) -Encoding utf8
            Set-Content -LiteralPath $paths.ResearchReportPath -Value @(
                '# Research Report'
                ''
                "Research refresh: $ResearchRefreshDate"
                "Current version after this refresh: $ResearchReportVersion"
            ) -Encoding utf8

            return $paths
        }
    }

    It 'passes when tracked planning docs share the latest version and sync date' {
        $paths = New-TestPlanningDocSet

        $result = Test-DocVersionConsistency @paths

        $result.passed | Should -BeTrue
        $result.expectedVersion | Should -Be 'v4.9.20'
        $result.expectedDate | Should -Be '2026-06-04'
        $result.changelogHeadingValidation.passed | Should -BeTrue
        $result.changelogHeadingValidation.headingCount | Should -Be 1
        $result.changelogHeadingValidation.malformedCount | Should -Be 0
        @($result.errors) | Should -HaveCount 0
    }

    It 'rejects a tracked planning doc version mismatch' {
        $paths = New-TestPlanningDocSet -ProjectContextVersion 'v4.9.19'

        $result = Test-DocVersionConsistency @paths

        $result.passed | Should -BeFalse
        ($result.errors -join "`n") | Should -Match 'PROJECT_CONTEXT\.md'
        ($result.errors -join "`n") | Should -Match 'does not match CHANGELOG latest version'
    }

    It 'rejects sync dates older than the latest changelog release date' {
        $paths = New-TestPlanningDocSet -ChangelogDate '2026-06-05' -RoadmapDate '2026-06-04'

        $result = Test-DocVersionConsistency @paths

        $result.passed | Should -BeFalse
        ($result.errors -join "`n") | Should -Match 'ROADMAP\.md'
        ($result.errors -join "`n") | Should -Match 'older than CHANGELOG latest date'
    }

    It 'reports malformed historical changelog release headings with line numbers' {
        $paths = New-TestPlanningDocSet -ChangelogExtraLines @(
            '## [v3.0.0] - %Y->- (HEAD -> main, origin/main, origin/HEAD)'
        )

        $result = Test-DocVersionConsistency @paths

        $result.passed | Should -BeFalse
        $result.changelogHeadingValidation.passed | Should -BeFalse
        $result.changelogHeadingValidation.headingCount | Should -Be 2
        $result.changelogHeadingValidation.malformedCount | Should -Be 1
        $result.changelogHeadingValidation.malformedHeadings[0].lineNumber | Should -Be 6
        $result.changelogHeadingValidation.malformedHeadings[0].text | Should -Be '## [v3.0.0] - %Y->- (HEAD -> main, origin/main, origin/HEAD)'
        ($result.errors -join "`n") | Should -Match 'CHANGELOG\.md release heading at line 6 is invalid'
    }

    It 'rejects impossible historical changelog release dates' {
        $paths = New-TestPlanningDocSet -ChangelogExtraLines @(
            '## [v3.0.0] - 2026-99-99'
        )

        $result = Test-DocVersionConsistency @paths

        $result.passed | Should -BeFalse
        $result.changelogHeadingValidation.passed | Should -BeFalse
        $result.changelogHeadingValidation.malformedHeadings[0].reason | Should -Be 'release date is not a valid yyyy-MM-dd date'
    }
}

Describe 'Public planning document terminology' {
    It 'does not present privateReason as a current catalog field in completed work' {
        $completed = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'COMPLETED.md')
        $catalogLine = @($completed -split "`r?`n" | Where-Object { $_ -match 'Build a canonical catalog source file' })[0]

        $catalogLine | Should -Not -Match 'privateReason'
        $catalogLine | Should -Match ([regex]::Escape('schemas/profile-catalog.v1.json'))
        $catalogLine | Should -Match 'suppressionReason'
        $catalogLine | Should -Match 'allowPublicMedical'
        $catalogLine | Should -Match 'aliasOf'
        $catalogLine | Should -Match 'forkOf'
        $catalogLine | Should -Match 'upstreamLicense'
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
        $markdownPaths = & git -C $script:RepoRoot ls-files '*.md'
        $violations = foreach ($relativePath in $markdownPaths) {
            $path = Join-Path $script:RepoRoot $relativePath
            $lines = Get-Content -LiteralPath $path
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '[ \t]+$') {
                    '{0}:{1}' -f $relativePath, ($i + 1)
                }
            }
        }

        @($violations) | Should -HaveCount 0
    }
}

Describe 'Markdownlint contract' {
    BeforeAll {
        $script:MarkdownlintConfig = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.markdownlint-cli2.yaml')
        $script:MarkdownlintPackage = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'package.json') | ConvertFrom-Json -AsHashtable
        $script:MarkdownlintPackageLock = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'package-lock.json') | ConvertFrom-Json -AsHashtable
        $script:MarkdownlintTestsWorkflow = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/tests.yml')
        $script:MarkdownlintCodeowners = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.github/CODEOWNERS')
        $script:MarkdownlintDependabot = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.github/dependabot.yml')
        $script:MarkdownlintGitIgnore = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.gitignore')
    }

    It 'defines generated README-safe markdownlint rules' {
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD013:\s+false\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD031:\s+false\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD034:\s+false\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD041:\s+false\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^  MD060:\s+false\s*$'
        foreach ($tag in @('details', 'summary', 'kbd', 'br', 'sub', 'picture', 'source', 'img', 'a', 'b', 'i', 'code')) {
            $script:MarkdownlintConfig | Should -Match "(?m)^\s+- $tag\s*$"
        }
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "[*][.]md"\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "docs/[*][*]/[*][.]md"\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "[.]github/[*][*]/[*][.]md"\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "CLAUDE[.]md"\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "TODO[.]md"\s*$'
        $script:MarkdownlintConfig | Should -Match '(?m)^\s+- "RESEARCH_FEATURE_PLAN[.]md"\s*$'
    }

    It 'pins markdownlint through npm and keeps local installs ignored' {
        $script:MarkdownlintPackage.scripts['lint:markdown'] | Should -Be 'markdownlint-cli2'
        $script:MarkdownlintPackage.devDependencies['markdownlint-cli2'] | Should -Be '0.22.1'
        $script:MarkdownlintPackageLock.name | Should -Be 'sysadmindoc-profile'
        $script:MarkdownlintPackageLock.packages[''].devDependencies['markdownlint-cli2'] | Should -Be '0.22.1'
        $script:MarkdownlintPackageLock.packages['node_modules/markdownlint-cli2'].version | Should -Be '0.22.1'
        $script:MarkdownlintPackageLock.packages['node_modules/markdownlint-cli2'].integrity | Should -Match '^sha512-'
        $script:MarkdownlintGitIgnore | Should -Match '(?m)^node_modules/\s*$'
        $script:MarkdownlintCodeowners | Should -Match '(?m)^/[.]markdownlint-cli2[.]yaml\s+@SysAdminDoc\s*$'
        $script:MarkdownlintCodeowners | Should -Match '(?m)^/package-lock[.]json\s+@SysAdminDoc\s*$'
        $script:MarkdownlintDependabot | Should -Match '(?ms)package-ecosystem: "npm".*directory: "/"'
    }

    It 'runs markdownlint in Tests with a pinned setup-node action' {
        $script:MarkdownlintTestsWorkflow | Should -Match '(?m)^  markdownlint:\s*$'
        $script:MarkdownlintTestsWorkflow | Should -Match '(?m)^    name: Markdownlint\s*$'
        $script:MarkdownlintTestsWorkflow | Should -Match 'actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e'
        $script:MarkdownlintTestsWorkflow | Should -Not -Match 'actions/setup-node@v'
        $script:MarkdownlintTestsWorkflow | Should -Match 'node-version: "24"'
        $script:MarkdownlintTestsWorkflow | Should -Match '(?m)^\s+cache: npm\s*$'
        $script:MarkdownlintTestsWorkflow | Should -Match '(?m)^\s+npm ci\s*$'
        $script:MarkdownlintTestsWorkflow | Should -Match '(?m)^\s+npm run lint:markdown\s*$'
    }
}

Describe 'Profile render-host decision record' {
    It 'records that no live third-party profile render hosts are retained' {
        $decision = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'docs/decisions/2026-06-06-profile-render-hosts.md')
        $report = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') | ConvertFrom-Json

        $decision | Should -Match 'Do not retain live third-party render hosts'
        $decision | Should -Match 'thirdPartyRenderHostCount=0'
        $decision | Should -Match 'thirdPartyMetricHostCount=0'
        $decision | Should -Match 'thirdPartyBadgeHostCount=0'
        $decision | Should -Match 'motionSafeChrome=true'
        $report.readmeExperienceChecks.thirdPartyRenderHostCount | Should -Be 0
        $report.readmeExperienceChecks.thirdPartyMetricHostCount | Should -Be 0
        $report.readmeExperienceChecks.thirdPartyBadgeHostCount | Should -Be 0
        $report.readmeExperienceChecks.motionSafeChrome | Should -BeTrue
    }
}

Describe 'Code scanning posture decision' {
    It 'records PowerShell-only CodeQL as not applicable while retaining SARIF controls' {
        $decision = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'docs/decisions/2026-06-06-code-scanning-posture.md')
        $report = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'reports/profile-sync-report.json') | ConvertFrom-Json
        $codeScanning = $report.repositorySettings.security.codeScanning

        $decision | Should -Match 'Do not add a CodeQL analysis workflow'
        $decision | Should -Match 'not-applicable-powershell-only'
        $decision | Should -Match 'does not call the code-scanning alerts API'
        $codeScanning.status | Should -Be 'not-applicable'
        $codeScanning.recommendation | Should -Be 'not-applicable-powershell-only'
        $codeScanning.codeqlSupportedLanguageDetected | Should -BeFalse
        $codeScanning.codeqlWorkflowPresent | Should -BeFalse
        $codeScanning.scorecardSarifUploadPresent | Should -BeTrue
        $codeScanning.activeControls | Should -Contain 'psscriptanalyzer'
        $codeScanning.activeControls | Should -Contain 'openssf-scorecard-sarif'
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
    }
}

Describe 'Seed catalog guard' {
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
            '### Featured Projects'
        ) -Encoding utf8

        $output = & pwsh -NoProfile -File $scriptPath -SeedCatalog -ForceSeedCatalog -Offline -ReadmePath $readmePath -CatalogPath $catalogPath *>&1

        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'LOSSY LEGACY SEED MODE'
        Test-Path -LiteralPath $catalogPath | Should -BeTrue
    }
}

Describe 'OpenSSF Scorecard workflow permissions' {
    BeforeAll {
        $script:ScorecardWorkflow = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/scorecard.yml') -Raw
    }

    It 'keeps workflow-level permissions read-only for Scorecard publish mode' {
        $workflowPermissionBlock = [regex]::Match(
            $script:ScorecardWorkflow,
            "(?ms)^permissions:\s*(?<block>.*?)(?=^jobs:)"
        )

        $workflowPermissionBlock.Success | Should -BeTrue
        $workflowPermissionBlock.Groups['block'].Value | Should -Not -Match ':\s*write\b'
    }

    It 'grants OIDC and SARIF upload writes only at the Scorecard job level' {
        $scorecardJobBlock = [regex]::Match(
            $script:ScorecardWorkflow,
            "(?ms)^  scorecard:\s*(?<block>.*)"
        )

        $scorecardJobBlock.Success | Should -BeTrue
        $scorecardJobBlock.Groups['block'].Value | Should -Match 'contents:\s*read'
        $scorecardJobBlock.Groups['block'].Value | Should -Match 'security-events:\s*write'
        $scorecardJobBlock.Groups['block'].Value | Should -Match 'id-token:\s*write'
        $scorecardJobBlock.Groups['block'].Value | Should -Match 'publish_results:\s*true'
    }
}

Describe 'Rendered profile smoke wiring' {
    BeforeAll {
        $script:RenderSmokeScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/render-profile-smoke.ps1') -Raw
        $script:ProfileSyncWorkflow = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/profile-sync.yml') -Raw
    }

    It 'checks both desktop and 390px mobile viewports without committing screenshots' {
        $script:RenderSmokeScript | Should -Match 'Width = 1280'
        $script:RenderSmokeScript | Should -Match 'Width = 390'
        $script:RenderSmokeScript | Should -Match 'rendered-profile-smoke-'
        $script:RenderSmokeScript | Should -Match 'viewport\.Name'
        $script:RenderSmokeScript | Should -Match 'rendered-profile-smoke[.]json'
    }

    It 'asserts key rendered sections and overflow/image health' {
        $script:RenderSmokeScript | Should -Match 'Featured Projects'
        $script:RenderSmokeScript | Should -Match 'First-time setup'
        $script:RenderSmokeScript | Should -Match 'PowerShell System Utilities'
        $script:RenderSmokeScript | Should -Match 'Python Desktop Applications'
        $script:RenderSmokeScript | Should -Match 'Browser Extensions & Userscripts'
        $script:RenderSmokeScript | Should -Not -Match 'Python Applications'
        $script:RenderSmokeScript | Should -Match 'rootOverflow'
        $script:RenderSmokeScript | Should -Match 'failedImages'
    }

    It 'runs from profile-sync and uploads public-safe smoke artifacts' {
        $script:ProfileSyncWorkflow | Should -Match 'Smoke live rendered profile'
        $script:ProfileSyncWorkflow | Should -Match ([regex]::Escape('./scripts/render-profile-smoke.ps1'))
        $script:ProfileSyncWorkflow | Should -Match 'reports/rendered-profile-smoke[.]json'
        $script:ProfileSyncWorkflow | Should -Match 'reports/rendered-profile-smoke-[*][.]png'
        $script:ProfileSyncWorkflow | Should -Match 'retention-days: 14'
    }
}

Describe 'Required status check readiness' {
    BeforeAll {
        $script:RequiredCheckWorkflows = [ordered]@{
            Tests = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/tests.yml') -Raw
            ProfileSync = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/profile-sync.yml') -Raw
            WorkflowSecurity = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/workflow-security.yml') -Raw
        }
        $script:RequiredCheckDecision = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs/decisions/2026-06-06-required-check-enforcement-readiness.md') -Raw
    }

    It 'creates candidate required checks for every pull request and merge queue run' {
        foreach ($workflow in $script:RequiredCheckWorkflows.Values) {
            $workflow | Should -Match '(?m)^  pull_request:\s*$'
            $workflow | Should -Match '(?m)^  merge_group:\s*$'
        }
    }

    It 'does not path-filter workflows that may become required status checks' {
        foreach ($workflow in $script:RequiredCheckWorkflows.Values) {
            $workflow | Should -Not -Match '(?ms)^  pull_request:\s*\r?\n\s+paths:'
        }
    }

    It 'runs offline tests for schema and markdown contract changes pushed to main' {
        $pushBlock = [regex]::Match($script:RequiredCheckWorkflows.Tests, '(?ms)^  push:\s*\r?\n(?<block>.*?)(?=^\S|\z)').Groups['block'].Value

        $pushBlock | Should -Match '(?m)^\s+paths:\s*$'
        $pushBlock | Should -Match '(?m)^\s+- "schemas/[*][*]"\s*$'
        $pushBlock | Should -Match '(?m)^\s+- "[*][.]md"\s*$'
        $pushBlock | Should -Match '(?m)^\s+- "docs/[*][*]/[*][.]md"\s*$'
        $pushBlock | Should -Match '(?m)^\s+- "[.]github/[*][*]/[*][.]md"\s*$'
        $pushBlock | Should -Match '(?m)^\s+- "[.]markdownlint-cli2[.]yaml"\s*$'
        $pushBlock | Should -Match '(?m)^\s+- "package[.]json"\s*$'
        $pushBlock | Should -Match '(?m)^\s+- "package-lock[.]json"\s*$'
    }

    It 'keeps the Windows setup smoke check always created for PRs and merge queue runs' {
        $testsWorkflow = $script:RequiredCheckWorkflows.Tests

        $testsWorkflow | Should -Match '(?m)^  windows-setup-smoke:\s*$'
        $testsWorkflow | Should -Match '(?m)^    name: Windows setup smoke\s*$'
        $testsWorkflow | Should -Match '(?m)^    runs-on: windows-latest\s*$'
        $testsWorkflow | Should -Match '(?m)^        shell: powershell\s*$'
        $testsWorkflow | Should -Match 'System\.Management\.Automation\.Language\.Parser'
        $testsWorkflow | Should -Match '-CheckOnly'
    }

    It 'records non-enforcing activation preconditions for the candidate checks' {
        foreach ($checkName in @('Pester \(offline\)', 'PSScriptAnalyzer', 'Markdownlint', 'Windows setup smoke', 'Check generated README', 'zizmor')) {
            $script:RequiredCheckDecision | Should -Match $checkName
        }

        $script:RequiredCheckDecision | Should -Match 'Do not enable branch-protection or ruleset required-status-check enforcement'
        $script:RequiredCheckDecision | Should -Match 'direct pushes to `main`'
        $script:RequiredCheckDecision | Should -Match 'enforce_admins\.enabled=true'
        $script:RequiredCheckDecision | Should -Match '404 Required status checks not enabled'
        $script:RequiredCheckDecision | Should -Match 'pull requests, or an approved'
        $script:RequiredCheckDecision | Should -Match 'job names stay unique and stable'
    }
}

Describe 'Roadmap reconciliation guards' {
    BeforeAll {
        $script:RoadmapForReconciliation = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'ROADMAP.md') -Raw
    }

    It 'does not leave shipped duplicate roadmap rows unchecked' {
        $shippedRows = [ordered]@{
            'Add a Windows runner smoke check for `setup.ps1 -CheckOnly`' = 'v4.9.41'
            'Pin and audit CI-installed validation tools' = 'v4.9.46'
            'Add a public-repo enumeration limit guard' = 'v4.9.36'
            'Add a `.gitattributes` generated-artifact diff policy' = 'v4.9.37'
            'Enable cleanup for generated automation PR branches' = 'v4.9.61'
            'Redact private suppression rows from the public feed' = 'v4.9.42'
        }

        foreach ($entry in $shippedRows.GetEnumerator()) {
            $titlePattern = [regex]::Escape($entry.Key)
            $versionPattern = [regex]::Escape($entry.Value)

            $script:RoadmapForReconciliation | Should -Not -Match "(?m)^- \[ \].*$titlePattern"
            $script:RoadmapForReconciliation | Should -Match "(?m)^- \[x\].*$titlePattern"
            $script:RoadmapForReconciliation | Should -Match "Completed: $versionPattern"
        }
    }

    It 'records current branch-protection evidence without enabling enforcement' {
        $script:RoadmapForReconciliation | Should -Match 'Required status checks not enabled'
        $script:RoadmapForReconciliation | Should -Match 'PR #7'
        $script:RoadmapForReconciliation | Should -Match 'Markdownlint'
        $script:RoadmapForReconciliation | Should -Match 'external-gated'
    }
}

Describe 'Generated profile PR validation handoff' {
    BeforeAll {
        $script:GeneratedPrHelper = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/open-generated-profile-pr.ps1') -Raw
        $script:GeneratedPrWorkflows = [ordered]@{
            ProfileSync = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/profile-sync.yml') -Raw
            AssetsRefresh = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/assets-refresh.yml') -Raw
        }
    }

    It 'grants actions write only to generated PR jobs that dispatch validation' {
        foreach ($workflow in $script:GeneratedPrWorkflows.Values) {
            $workflow | Should -Match '(?ms)permissions:\s*\r?\n\s+actions: write\s*\r?\n\s+contents: write\s*\r?\n\s+pull-requests: write'
            $workflow | Should -Match 'open-generated-profile-pr[.]ps1'
        }
        $script:GeneratedPrHelper | Should -Match 'gh workflow run \$ValidationWorkflow --ref \$branch -f "mode=\$ValidationMode"'
    }

    It 'links the branch-scoped validation runs in the PR body and job summary' {
        $script:GeneratedPrHelper | Should -Match 'Validation handoff: this workflow dispatches Profile sync in check mode'
        $script:GeneratedPrHelper | Should -Match 'actions/workflows/\$ValidationWorkflow'
        $script:GeneratedPrHelper | Should -Match '\[uri\]::EscapeDataString\("branch:\$branch"\)'
        $script:GeneratedPrHelper | Should -Match 'GITHUB_STEP_SUMMARY'
        $script:GeneratedPrHelper | Should -Match 'Generated profile PR validation handoff'
    }

    It 'centralizes branch creation, commit, push, pull request, and validation guards' {
        $script:GeneratedPrHelper | Should -Match "\[ValidateSet\('automation/profile-sync-', 'automation/profile-assets-'\)\]"
        $script:GeneratedPrHelper | Should -Match 'git diff --quiet'
        $script:GeneratedPrHelper | Should -Match 'git diff --cached --quiet'
        $script:GeneratedPrHelper | Should -Match 'git switch -c \$branch'
        $script:GeneratedPrHelper | Should -Match 'git commit -m \$CommitMessage'
        $script:GeneratedPrHelper | Should -Match 'gh pr create'

        $script:GeneratedPrWorkflows.ProfileSync | Should -Match '-BranchPrefix "automation/profile-sync-"'
        $script:GeneratedPrWorkflows.AssetsRefresh | Should -Match '-BranchPrefix "automation/profile-assets-"'
        foreach ($workflow in $script:GeneratedPrWorkflows.Values) {
            $workflow | Should -Not -Match 'git switch -c'
            $workflow | Should -Not -Match 'git commit -m'
            $workflow | Should -Not -Match 'gh pr create'
        }
    }

    It 'keeps validation dispatch out of the read-only check job' {
        $checkJob = [regex]::Match($script:GeneratedPrWorkflows.ProfileSync, '(?ms)^  check:.*?^  write-pr:').Value

        $checkJob | Should -Match 'contents: read'
        $checkJob | Should -Not -Match 'actions: write'
        $checkJob | Should -Not -Match 'open-generated-profile-pr[.]ps1'
    }
}

Describe 'Generated automation branch cleanup' {
    BeforeAll {
        $script:AutomationCleanupWorkflow = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/automation-branch-cleanup.yml') -Raw
    }

    It 'defaults to dry-run cleanup and staggers the weekly schedule' {
        $script:AutomationCleanupWorkflow | Should -Match 'dry_run:'
        $script:AutomationCleanupWorkflow | Should -Match 'default: "true"'
        $script:AutomationCleanupWorkflow | Should -Match 'DRY_RUN: \$\{\{ github[.]event_name != ''workflow_dispatch'' \|\| inputs[.]dry_run == ''true'' \}\}'
        $script:AutomationCleanupWorkflow | Should -Match 'cron: "43 8 [*] [*] 3"'
    }

    It 'limits deletion to merged generated profile branches' {
        $script:AutomationCleanupWorkflow | Should -Match '"automation/profile-sync-"'
        $script:AutomationCleanupWorkflow | Should -Match '"automation/profile-assets-"'
        $script:AutomationCleanupWorkflow | Should -Match 'matching-refs/heads/automation/'
        $script:AutomationCleanupWorkflow | Should -Match 'StartsWith\(\$prefix, \[StringComparison\]::Ordinal\)'
        $script:AutomationCleanupWorkflow | Should -Match '\$_[.]state -eq "MERGED"'
        $script:AutomationCleanupWorkflow | Should -Match 'mergedAt'
        $script:AutomationCleanupWorkflow | Should -Match 'gh api -X DELETE "repos/\$repo/git/refs/heads/\$branch"'
    }

    It 'keeps write permissions scoped to the cleanup job' {
        $workflowLevel = [regex]::Match($script:AutomationCleanupWorkflow, '(?ms)^permissions:\s*(?<block>.*?)(?=^jobs:)').Groups['block'].Value
        $job = [regex]::Match($script:AutomationCleanupWorkflow, '(?ms)^  cleanup:.*').Value

        $workflowLevel | Should -Match 'contents: read'
        $workflowLevel | Should -Not -Match 'contents: write'
        $job | Should -Match 'contents: write'
        $job | Should -Match 'pull-requests: read'
    }
}

Describe 'Profile sync report summaries' {
    BeforeAll {
        $script:SummaryScriptPath = Join-Path $script:RepoRoot 'scripts/write-profile-sync-summary.ps1'
        $script:SummaryScript = Get-Content -LiteralPath $script:SummaryScriptPath -Raw
        $script:ProfileSyncWorkflowForSummary = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/profile-sync.yml') -Raw
        $script:AssetsRefreshWorkflowForSummary = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/assets-refresh.yml') -Raw
    }

    It 'writes a public-safe aggregate summary from the committed report' {
        $summaryPath = New-TemporaryFile
        try {
            pwsh -NoProfile -File $script:SummaryScriptPath -SummaryPath $summaryPath.FullName -Context 'Pester summary test'
            $summary = Get-Content -LiteralPath $summaryPath.FullName -Raw

            $summary | Should -Match 'Pester summary test report'
            $summary | Should -Match 'Fatal metadata drift'
            $summary | Should -Match 'Missing topic hints'
            $summary | Should -Match 'Missing project licenses'
            $summary | Should -Match 'Unknown project licenses'
            $summary | Should -Match 'Fork-parent warnings'
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
            $summary | Should -Match 'Profile release/tag warnings'
            $summary | Should -Match 'Userscript installs checked'
            $summary | Should -Match 'Userscript trust warnings'
            $summary | Should -Match 'Link targets checked'
            $summary | Should -Match 'Repository setting warnings'
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

    It 'emits GitHub annotations and uses aggregate report sections only' {
        $script:SummaryScript | Should -Match 'metadataDriftSummary'
        $script:SummaryScript | Should -Match 'linkValidationSummary'
        $script:SummaryScript | Should -Match 'projectLicenseMetadata'
        $script:SummaryScript | Should -Match 'forkParentDrift'
        $script:SummaryScript | Should -Match 'staleProjectReview'
        $script:SummaryScript | Should -Match 'profileReleaseConsistency'
        $script:SummaryScript | Should -Match 'userscriptInstallTrust'
        $script:SummaryScript | Should -Match 'catalogFeedAccounting'
        $script:SummaryScript | Should -Match 'portfolioCompatibility'
        $script:SummaryScript | Should -Match 'readmeDensity'
        $script:SummaryScript | Should -Match 'repositorySettings'
        $script:SummaryScript | Should -Match 'codeScanning'
        $script:SummaryScript | Should -Match 'communityHealth'
        $script:SummaryScript | Should -Match '::warning::'
        $script:SummaryScript | Should -Match '::error::'
    }

    It 'wires summaries and retained report artifacts into profile workflows' {
        foreach ($workflow in @($script:ProfileSyncWorkflowForSummary, $script:AssetsRefreshWorkflowForSummary)) {
            $workflow | Should -Match 'write-profile-sync-summary[.]ps1'
            $workflow | Should -Match 'GITHUB_STEP_SUMMARY|Write sync report summary'
            $workflow | Should -Match 'actions/upload-artifact@'
            $workflow | Should -Match 'reports/profile-sync-report[.]json'
            $workflow | Should -Match 'retention-days: 14'
        }
    }
}

Describe 'Maintenance workflow schedules' {
    BeforeAll {
        $script:MaintenanceScheduleWorkflows = [ordered]@{
            AssetsRefresh = '.github/workflows/assets-refresh.yml'
            WorkflowSecurity = '.github/workflows/workflow-security.yml'
            AutomationBranchCleanup = '.github/workflows/automation-branch-cleanup.yml'
            ProfileSync = '.github/workflows/profile-sync.yml'
            Scorecard = '.github/workflows/scorecard.yml'
        }
    }

    It 'stagger independent Wednesday maintenance workflows' {
        $assetsRefresh = Get-Content -LiteralPath (Join-Path $script:RepoRoot $script:MaintenanceScheduleWorkflows.AssetsRefresh) -Raw
        $workflowSecurity = Get-Content -LiteralPath (Join-Path $script:RepoRoot $script:MaintenanceScheduleWorkflows.WorkflowSecurity) -Raw
        $automationCleanup = Get-Content -LiteralPath (Join-Path $script:RepoRoot $script:MaintenanceScheduleWorkflows.AutomationBranchCleanup) -Raw

        $assetsRefresh | Should -Match 'cron: "19 8 [*] [*] 3"'
        $automationCleanup | Should -Match 'cron: "43 8 [*] [*] 3"'
        $workflowSecurity | Should -Match 'cron: "17 9 [*] [*] 3"'
        $workflowSecurity | Should -Not -Match 'cron: "19 8 [*] [*] 3"'
    }

    It 'does not duplicate day-hour-minute schedule slots across maintenance workflows' {
        $slots = foreach ($path in $script:MaintenanceScheduleWorkflows.Values) {
            $content = Get-Content -LiteralPath (Join-Path $script:RepoRoot $path) -Raw
            foreach ($match in [regex]::Matches($content, 'cron:\s+"(?<cron>[^"]+)"')) {
                $parts = $match.Groups['cron'].Value -split '\s+'
                foreach ($day in ($parts[4] -split ',')) {
                    '{0} {1} {2}' -f $parts[0], $parts[1], $day
                }
            }
        }

        $duplicates = $slots | Group-Object | Where-Object { $_.Count -gt 1 }

        $duplicates | Should -BeNullOrEmpty
    }
}

Describe 'Workflow timeout budgets' {
    BeforeAll {
        $script:WorkflowTimeoutBudgets = [ordered]@{
            '.github/workflows/automation-branch-cleanup.yml' = 1
            '.github/workflows/assets-refresh.yml' = 1
            '.github/workflows/profile-sync.yml' = 2
            '.github/workflows/scorecard.yml' = 1
            '.github/workflows/tests.yml' = 4
            '.github/workflows/workflow-security.yml' = 1
        }
    }

    It 'declares a timeout for every workflow job' {
        foreach ($entry in $script:WorkflowTimeoutBudgets.GetEnumerator()) {
            $content = Get-Content -LiteralPath (Join-Path $script:RepoRoot $entry.Key) -Raw
            $timeouts = [regex]::Matches($content, '(?m)^\s+timeout-minutes:\s+\d+\s*$')

            $timeouts.Count | Should -Be $entry.Value
        }
    }

    It 'keeps timeout budgets bounded for maintenance and validation jobs' {
        foreach ($path in $script:WorkflowTimeoutBudgets.Keys) {
            $content = Get-Content -LiteralPath (Join-Path $script:RepoRoot $path) -Raw
            foreach ($match in [regex]::Matches($content, '(?m)^\s+timeout-minutes:\s+(?<minutes>\d+)\s*$')) {
                [int]$match.Groups['minutes'].Value | Should -BeLessOrEqual 30
            }
        }
    }
}

Describe 'Workflow security actionlint lane' {
    BeforeAll {
        $script:WorkflowSecurityWorkflow = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/workflow-security.yml') -Raw
        $script:WorkflowSecurityCodeowners = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/CODEOWNERS') -Raw
    }

    It 'installs a pinned checksum-verified actionlint binary' {
        $script:WorkflowSecurityWorkflow | Should -Match 'ACTIONLINT_VERSION: "1[.]7[.]12"'
        $script:WorkflowSecurityWorkflow | Should -Match 'ACTIONLINT_SHA256: "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"'
        $script:WorkflowSecurityWorkflow | Should -Match 'sha256sum -c -'
    }

    It 'runs actionlint and collects workflows plus local actions for zizmor' {
        $script:WorkflowSecurityWorkflow | Should -Match 'actionlint [.]github/workflows/[*][.]yml'
        $script:WorkflowSecurityWorkflow | Should -Match 'zizmor --strict-collection --collect=workflows --collect=actions [.]github'
        $script:WorkflowSecurityWorkflow | Should -Not -Match 'zizmor [.]github/workflows'
    }

    It 'keeps local action changes covered by trigger and ownership rules' {
        $script:WorkflowSecurityWorkflow | Should -Not -Match '(?ms)^  pull_request:\s*\r?\n\s+paths:'
        $script:WorkflowSecurityCodeowners | Should -Match '(?m)^/[.]github/\s+@SysAdminDoc\s*$'
    }
}

Describe 'CI validation tool pins' {
    BeforeAll {
        $script:TestsWorkflowForToolPins = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/tests.yml') -Raw
        $script:WorkflowSecurityForToolPins = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/workflow-security.yml') -Raw
        $script:CiRequirements = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'requirements-ci.txt') -Raw
        $script:CiToolchainDoc = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs/ci-toolchain.md') -Raw
    }

    It 'installs exact PowerShell validation module versions' {
        $script:TestsWorkflowForToolPins | Should -Match 'Install-Module PSScriptAnalyzer -RequiredVersion 1[.]25[.]0'
        $script:TestsWorkflowForToolPins | Should -Match 'Install-Module Pester -RequiredVersion 5[.]7[.]1'
        $script:TestsWorkflowForToolPins | Should -Not -Match 'Install-Module Pester -MinimumVersion'
    }

    It 'installs zizmor from hash-checked pinned requirements' {
        $script:WorkflowSecurityForToolPins | Should -Match 'python -m pip install --disable-pip-version-check --no-deps\s+--require-hashes --only-binary=:all: -r requirements-ci[.]txt'
        $script:WorkflowSecurityForToolPins | Should -Not -Match 'pip install --upgrade zizmor'
        $script:CiRequirements | Should -Match '(?m)^zizmor==1[.]25[.]2\s+\\'
        $script:CiRequirements | Should -Match '--hash=sha256:c4246f1344d8dbeffc044d7bb11b131773a7db7eb57d9073c45942dfd3543a1f'
        $script:CiRequirements | Should -Match '--hash=sha256:f26ffeb16659c8922c7b08203ca5a4f8bf5e1a7e8d190734961c40877cf778ea'
    }

    It 'documents the reviewed update path' {
        $script:CiToolchainDoc | Should -Match 'Pester\s+\| `.github/workflows/tests[.]yml`\s+\| `5[.]7[.]1`'
        $script:CiToolchainDoc | Should -Match 'zizmor\s+\| `.github/workflows/workflow-security[.]yml`\s+\| `1[.]25[.]2`'
        $script:CiToolchainDoc | Should -Match 'Update Process'
        $script:CiToolchainDoc | Should -Match 'requirements-ci[.]txt'
    }
}

Describe 'Dependabot GitHub Actions update grouping' {
    BeforeAll {
        $script:DependabotConfig = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/dependabot.yml') -Raw
    }

    It 'groups routine minor and patch action updates while leaving majors separate' {
        $script:DependabotConfig | Should -Match 'package-ecosystem: "github-actions"'
        $script:DependabotConfig | Should -Match 'open-pull-requests-limit: 5'
        $script:DependabotConfig | Should -Match '(?ms)groups:\s*\r?\n\s+routine-actions:\s*\r?\n\s+patterns:\s*\r?\n\s+- "[*]"\s*\r?\n\s+update-types:\s*\r?\n\s+- "minor"\s*\r?\n\s+- "patch"'
        $script:DependabotConfig | Should -Not -Match '(?m)^\s+- "major"\s*$'
    }
}

Describe 'Workflow checkout action pin' {
    BeforeAll {
        $script:WorkflowFilesForCheckout = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot '.github/workflows') -Filter '*.yml' -File
        $script:CheckoutV603Sha = 'df4cb1c069e1874edd31b4311f1884172cec0e10'
        $script:CheckoutV431Sha = '34e114876b0b11c390a56381ad16ebd13914f8d5'
    }

    It 'uses the pinned checkout 6.0.3 action SHA everywhere checkout is needed' {
        $allWorkflows = ($script:WorkflowFilesForCheckout | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        $checkoutUses = [regex]::Matches($allWorkflows, 'actions/checkout@(?<sha>[a-f0-9]{40})')

        $checkoutUses.Count | Should -Be 9
        foreach ($match in $checkoutUses) {
            $match.Groups['sha'].Value | Should -Be $script:CheckoutV603Sha
        }
    }

    It 'does not use the older checkout 4.3.1 action SHA' {
        foreach ($workflowFile in $script:WorkflowFilesForCheckout) {
            Get-Content -LiteralPath $workflowFile.FullName -Raw | Should -Not -Match $script:CheckoutV431Sha
        }
    }
}

Describe 'Workflow CodeQL upload action pin' {
    BeforeAll {
        $script:ScorecardWorkflowForCodeQl = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/scorecard.yml') -Raw
        $script:CodeQlV4362Sha = '8aad20d150bbac5944a9f9d289da16a4b0d87c1e'
        $script:CodeQlV4361Sha = '87557b9c84dde89fdd9b10e88954ac2f4248e463'
        $script:CodeQlV3355Sha = '458d36d7d4f47d0dd16ca424c1d3cda0060f1360'
    }

    It 'uses the pinned CodeQL upload-sarif 4.36.2 action SHA' {
        $script:ScorecardWorkflowForCodeQl | Should -Match "github/codeql-action/upload-sarif@$script:CodeQlV4362Sha"
    }

    It 'does not use the older CodeQL upload-sarif 4.36.1 action SHA' {
        $script:ScorecardWorkflowForCodeQl | Should -Not -Match $script:CodeQlV4361Sha
    }

    It 'does not use the older CodeQL upload-sarif 3.35.5 action SHA' {
        $script:ScorecardWorkflowForCodeQl | Should -Not -Match $script:CodeQlV3355Sha
    }
}

Describe 'Public-safe intake files' {
    It 'publishes a security policy that avoids public sensitive disclosure' {
        $securityPolicy = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'SECURITY.md') -Raw

        $securityPolicy | Should -Match 'private vulnerability reporting'
        $securityPolicy | Should -Match 'Do not include secrets'
        $securityPolicy | Should -Match 'private repository names'
        $securityPolicy | Should -Match 'medical data'
    }

    It 'provides issue forms for broken links, profile corrections, and workflow problems' {
        foreach ($file in @(
            '.github/ISSUE_TEMPLATE/broken-link.yml',
            '.github/ISSUE_TEMPLATE/profile-correction.yml',
            '.github/ISSUE_TEMPLATE/workflow-ci.yml'
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
    It 'fails when projects.json is out of sync with the expected feed' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $expectedReadme = New-Readme -Catalog $cat -Repos @()

        $result = Test-ProfileState `
            -Catalog $cat `
            -Repos @() `
            -ExpectedReadme $expectedReadme `
            -ExpectedProjects '{"stale": true}' `
            -SkipLinkValidation

        $result.Failed | Should -BeTrue
        $result.Report.projectsExportInSync | Should -BeFalse
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
        $result.Report.catalogFeedAccounting.unaccountedRows[0].catalogId | Should -Be 'catalog-005'
        $result.Report.catalogFeedAccounting.unaccountedRows[0].exportStatus | Should -Be 'unaccounted'
        ($result.Report.catalogFeedAccounting.unaccountedRows | ConvertTo-Json -Depth 20) | Should -Not -Match 'LocalOnly|github.com'
    }
}

Describe 'Test-MetadataDrift report' {
    It 'marks star drift informational and branch/release drift fatal' {
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
        $release[0].severity | Should -Be 'fatal'

        $stars = @($result.metadataDrift | Where-Object { $_.field -eq 'stars' })
        $stars | Should -HaveCount 1
        $stars[0].severity | Should -Be 'info'

        $result.fatalCount | Should -Be 3
        $result.informationalCount | Should -Be 1
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
        $expected.provenance.catalogSha256 = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
        $expected.provenance.metadataSnapshotAt = '2026-06-06T01:00:00Z'

        $result = Test-MetadataDrift `
            -CurrentProjectsJson ($current | ConvertTo-Json -Depth 20) `
            -ExpectedProjectsJson ($expected | ConvertTo-Json -Depth 20)

        $catalogHash = @($result.metadataDrift | Where-Object { $_.field -eq 'provenance.catalogSha256' })
        $catalogHash | Should -HaveCount 1
        $catalogHash[0].severity | Should -Be 'fatal'

        $sourceCommit = @($result.metadataDrift | Where-Object { $_.field -eq 'provenance.sourceCommit' })
        $sourceCommit | Should -HaveCount 1
        $sourceCommit[0].severity | Should -Be 'info'

        $snapshot = @($result.metadataDrift | Where-Object { $_.field -eq 'provenance.metadataSnapshotAt' })
        $snapshot | Should -HaveCount 1
        $snapshot[0].severity | Should -Be 'info'

        $result.fatalCount | Should -Be 1
        $result.informationalCount | Should -Be 2
    }
}
