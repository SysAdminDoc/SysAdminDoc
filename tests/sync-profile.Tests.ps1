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
            [switch]$WithRelease,
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
                    tagName = 'v1.0.0'
                    url = "https://github.com/SysAdminDoc/$Name/releases/tag/v1.0.0"
                    releaseAssetNames = @($AssetNames)
                    releaseAssetKinds = @($assetKinds)
                    assetApiInspected = $true
                }
            } else {
                $null
            }
            stargazerCount = 0
            pushedAt = '2026-06-04T00:00:00Z'
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
    }
}

Describe 'Report schema depth helpers' {
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
            (New-TestRepoMeta -Name 'GoodRelease' -WithRelease -AssetNames @('GoodRelease-v1.0.0.apk')),
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
        $result.assetApiInspected | Should -BeTrue
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
    It 'includes the generated catalog hand-edit notice' {
        $script:rendered | Should -Match ([regex]::Escape($GeneratedCatalogNotice))
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
    It 'emits theme-aware profile chrome with plain text and descriptive alt text' {
        $script:rendered | Should -Match '<picture>'
        $script:rendered | Should -Match '\(prefers-color-scheme: dark\)'
        $script:rendered | Should -Match '\(prefers-color-scheme: light\)'
        $script:rendered | Should -Match 'assets/profile/stats-light\.svg'
        $script:rendered | Should -Match 'assets/profile/languages-light\.svg'
        $script:rendered | Should -Match 'assets/profile/activity-light\.svg'
        $script:rendered | Should -Match 'Healthcare IT engineer and DICOM/PACS specialist'
        $script:rendered | Should -Match 'alt="SysAdminDoc - Healthcare IT Engineer, DICOM/PACS Specialist, Product Builder"'
        $script:rendered | Should -Not -Match 'alt="(Header|Typing SVG|Tech Stack|GitHub Stats|Top Languages|GitHub Streak|Activity Graph|Footer)"'
        $script:rendered | Should -Not -Match 'komarev\.com|github-readme-stats|streak-stats|github-readme-activity-graph'
        $script:rendered | Should -Not -Match 'img\.shields\.io/github/(followers|stars)'
    }
    It 'places stats chrome after the profile body and before the generated catalog' {
        $focusIndex = $script:rendered.IndexOf('### Professional Focus', [StringComparison]::Ordinal)
        $statsIndex = $script:rendered.IndexOf('https://skillicons.dev/icons', [StringComparison]::Ordinal)
        $noticeIndex = $script:rendered.IndexOf($GeneratedCatalogNotice, [StringComparison]::Ordinal)

        ($focusIndex -ge 0) | Should -BeTrue
        ($statsIndex -gt $focusIndex) | Should -BeTrue
        ($statsIndex -lt $noticeIndex) | Should -BeTrue
        $script:rendered.Substring(0, $focusIndex) | Should -Not -Match 'skillicons\.dev'
        $script:rendered | Should -Not -Match '(?s)\*\*Currently Building\*\*.*?\r?\n---\r?\n\r?\n---\r?\n\r?\n<p align="center">\s*<a href="https://skillicons\.dev">'
        [regex]::Matches($script:rendered, '<a href="https://skillicons\.dev">').Count | Should -Be 1
        [regex]::Matches($script:rendered, 'alt="Generated SysAdminDoc release asset validation summary"').Count | Should -Be 1
    }
    It 'reports the generated catalog notice in README experience checks' {
        $result = Test-ReadmeExperience -Catalog $script:cat -Repos @() -ExpectedReadme $script:rendered
        $result.generatedCatalogNotice | Should -BeTrue
        $result.setupInspectPath | Should -BeTrue
        $result.themeAwareImageChrome | Should -BeTrue
        $result.plainTextTagline | Should -BeTrue
        $result.meaningfulImageAltText | Should -BeTrue
        $result.genericImageAltTextCount | Should -Be 0
        $result.thirdPartyMetricHostCount | Should -Be 0
        $result.thirdPartyBadgeHostCount | Should -Be 0
        $result.profileStatsChromeCount | Should -Be 1
        $result.passed | Should -BeTrue
    }

    It 'generates committed local profile SVG assets' {
        $repo = New-TestRepoMeta -Name 'WinTool'
        $repo.stargazerCount = 7
        $assets = New-ProfileAssetSvgs -Catalog $script:cat -Repos @($repo)

        $assets.Keys | Should -Contain 'assets/profile/stats-dark.svg'
        $assets.Keys | Should -Contain 'assets/profile/languages-light.svg'
        $assets.Keys | Should -Contain 'assets/profile/activity-dark.svg'
        $assets['assets/profile/stats-dark.svg'] | Should -Match '<svg'
        $assets['assets/profile/stats-dark.svg'] | Should -Match 'total public stars'
        $assets['assets/profile/stats-dark.svg'] | Should -Match '>7</text>'
        $assets['assets/profile/activity-light.svg'] | Should -Match 'Release Asset Health'
    }
}

Describe 'setup.ps1 hardening contract' {
    BeforeAll {
        $script:setupSource = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'setup.ps1') -Raw
    }

    It 'declares the supported Windows PowerShell floor' {
        $script:setupSource | Should -Match '(?m)^#Requires -Version 5\.1\s*$'
    }

    It 'supports check-only diagnostics without installation' {
        $script:setupSource | Should -Match '\[switch\]\$CheckOnly'
        $script:setupSource | Should -Match 'Check-only mode: no packages will be installed\.'
        $script:setupSource | Should -Match 'Run without -CheckOnly to install with winget'
    }

    It 'writes a best-effort setup transcript under temp' {
        $script:setupSource | Should -Match 'Start-Transcript'
        $script:setupSource | Should -Match 'SysAdminDoc-setup-\{0\}\.log'
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

    It 'excludes suppressed entries and includes portfolio entries' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $repos = $json.projects | ForEach-Object { $_.repo }
        $repos | Should -Contain 'WinTool'
        $repos | Should -Not -Contain 'HiddenTool'
        ($json.suppressed | ForEach-Object { $_.repo }) | Should -Contain 'HiddenTool'
    }

    It 'exports release asset kinds and keeps source-only releases as repo actions' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $cat.entries[0].downloadKind = 'apk'
        $cat.entries[1].downloadKind = 'zip'
        $repos = @(
            (New-TestRepoMeta -Name 'WinTool' -WithRelease -AssetNames @('WinTool-v1.0.0.apk')),
            (New-TestRepoMeta -Name 'PyTool' -WithRelease),
            (New-TestRepoMeta -Name 'HiddenTool' -WithRelease -AssetNames @('HiddenTool-InternalSetup.exe')),
            (New-TestRepoMeta -Name 'WebTool')
        )

        $json = New-ProjectsExportJson -Catalog $cat -Repos $repos | ConvertFrom-Json
        $winTool = $json.projects | Where-Object { $_.repo -eq 'WinTool' }
        $pyTool = $json.projects | Where-Object { $_.repo -eq 'PyTool' }
        $hiddenTool = $json.suppressed | Where-Object { $_.repo -eq 'HiddenTool' }

        $winTool.releaseAssetKinds | Should -Contain 'apk'
        $winTool.primaryAction.kind | Should -Be 'release'
        $pyTool.releaseAssetKinds | Should -Contain 'source-archive'
        $pyTool.primaryAction.kind | Should -Be 'repo'
        $pyTool.hasDownload | Should -BeFalse
        $hiddenTool.releaseAssetKinds | Should -Contain 'exe'
        @($hiddenTool.releaseAssetNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count | Should -Be 0
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
                [string]$ResearchRefreshDate = $Date
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
            Set-Content -LiteralPath $paths.ChangelogPath -Value @(
                '# Changelog'
                ''
                "## [$Version] - $ChangelogDate"
                ''
                '- Changed: test.'
            ) -Encoding utf8
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
        $script:RenderSmokeScript | Should -Match 'Professional Focus'
        $script:RenderSmokeScript | Should -Match 'Currently Building'
        $script:RenderSmokeScript | Should -Match 'Start Here'
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
            $summary | Should -Match 'Link targets checked'
            $summary | Should -Not -Match 'AppManagerNG'
            $summary | Should -Not -Match 'VaultBox'
        } finally {
            Remove-Item -LiteralPath $summaryPath.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits GitHub annotations and uses aggregate report sections only' {
        $script:SummaryScript | Should -Match 'metadataDriftSummary'
        $script:SummaryScript | Should -Match 'linkValidationSummary'
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

Describe 'Workflow timeout budgets' {
    BeforeAll {
        $script:WorkflowTimeoutBudgets = [ordered]@{
            '.github/workflows/assets-refresh.yml' = 1
            '.github/workflows/profile-sync.yml' = 2
            '.github/workflows/scorecard.yml' = 1
            '.github/workflows/tests.yml' = 2
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
    }

    It 'installs a pinned checksum-verified actionlint binary' {
        $script:WorkflowSecurityWorkflow | Should -Match 'ACTIONLINT_VERSION: "1[.]7[.]12"'
        $script:WorkflowSecurityWorkflow | Should -Match 'ACTIONLINT_SHA256: "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"'
        $script:WorkflowSecurityWorkflow | Should -Match 'sha256sum -c -'
    }

    It 'runs actionlint and keeps zizmor in the same security lane' {
        $script:WorkflowSecurityWorkflow | Should -Match 'actionlint [.]github/workflows/[*][.]yml'
        $script:WorkflowSecurityWorkflow | Should -Match 'zizmor [.]github/workflows'
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
}
