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
    It 'reports the generated catalog notice in README experience checks' {
        $result = Test-ReadmeExperience -Catalog $script:cat -Repos @() -ExpectedReadme $script:rendered
        $result.generatedCatalogNotice | Should -BeTrue
        $result.passed | Should -BeTrue
    }
}

Describe 'New-ProjectsExportJson feed' {
    It 'excludes suppressed entries and includes portfolio entries' {
        $cat = Get-Catalog -Path (Join-Path $PSScriptRoot 'fixtures/catalog.json')
        $json = New-ProjectsExportJson -Catalog $cat -Repos @() | ConvertFrom-Json
        $repos = $json.projects | ForEach-Object { $_.repo }
        $repos | Should -Contain 'WinTool'
        $repos | Should -Not -Contain 'HiddenTool'
        ($json.suppressed | ForEach-Object { $_.repo }) | Should -Contain 'HiddenTool'
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
