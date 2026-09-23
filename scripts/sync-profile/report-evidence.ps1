# Report sections about the repository's own evidence: report and smoke freshness,
# roadmap and root Markdown hygiene, planning-doc version consistency and profile
# release consistency. Dot-sourced by scripts/sync-profile.ps1.

function Get-LatestReportAffectingCommit {
    param([string[]]$Paths = $ReportAffectingPaths)

    $gitArgs = @('-C', $RepoRoot, 'log', '-1', '--format=%H%n%cI', '--') + @($Paths)
    $output = & git @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
        return [ordered]@{ sha = $null; date = $null }
    }

    $lines = @($output)
    $sha = if ($lines.Count -ge 1) { [string]$lines[0] } else { $null }
    $dateText = if ($lines.Count -ge 2) { [string]$lines[1] } else { $null }
    $date = ConvertTo-DateTimeOffsetOrNull $dateText
    return [ordered]@{ sha = $sha; date = $date }
}

function Test-ReportEvidenceFreshness {
    param(
        [AllowNull()][object]$CommittedReport,
        [AllowNull()][object]$LatestCommitDate,
        [AllowNull()][string]$LatestCommitSha,
        [string[]]$ReportAffectingPathList = $ReportAffectingPaths,
        [AllowNull()][object]$SmokeAffectingCommitDate,
        [string[]]$SmokeAffectingPathList = $SmokeAffectingPaths,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )

    $warnings = New-Object System.Collections.Generic.List[string]

    $committedPresent = $null -ne $CommittedReport
    $committedGeneratedAtText = if ($committedPresent) { ConvertTo-IsoText (Get-MemberValue -Object $CommittedReport -Name "generatedAt") } else { $null }
    $committedGeneratedAt = ConvertTo-DateTimeOffsetOrNull $committedGeneratedAtText
    $latestCommitDateOffset = ConvertTo-DateTimeOffsetOrNull $LatestCommitDate

    $smokeStatus = "unavailable"
    $smokeSource = $null
    $smokeGeneratedAtText = $null
    if ($committedPresent) {
        $smoke = Get-MemberValue -Object $CommittedReport -Name "renderedProfileSmoke"
        if ($null -ne $smoke) {
            $statusValue = Get-MemberValue -Object $smoke -Name "status"
            if (-not [string]::IsNullOrWhiteSpace([string]$statusValue)) {
                $smokeStatus = [string]$statusValue
            }
            $sourceValue = Get-MemberValue -Object $smoke -Name "source"
            if (-not [string]::IsNullOrWhiteSpace([string]$sourceValue)) {
                $smokeSource = [string]$sourceValue
            }
            $smokeGeneratedAtText = ConvertTo-IsoText (Get-MemberValue -Object $smoke -Name "generatedAt")
        }
    }
    $smokeGeneratedAt = ConvertTo-DateTimeOffsetOrNull $smokeGeneratedAtText

    $reportBehindCommit = $false
    $reportAgeBehindHours = $null
    $generatedWithCommit = $false
    $sameCommitThresholdMinutes = 10
    if (-not $committedPresent) {
        $warnings.Add("Committed sync report was not found; report-freshness evidence is unavailable.")
    } elseif ($null -eq $committedGeneratedAt) {
        $warnings.Add("Committed sync report generatedAt is missing or unparseable.")
    } elseif ($null -ne $latestCommitDateOffset -and $committedGeneratedAt -lt $latestCommitDateOffset) {
        $reportBehindCommit = $true
        $reportAgeBehindHours = [math]::Round(($latestCommitDateOffset - $committedGeneratedAt).TotalHours, 2)
        $deltaMinutes = ($latestCommitDateOffset - $committedGeneratedAt).TotalMinutes
        if ($deltaMinutes -le $sameCommitThresholdMinutes) {
            $generatedWithCommit = $true
        } else {
            $shaLabel = if ([string]::IsNullOrWhiteSpace($LatestCommitSha)) { "the latest report-affecting commit" } else { $LatestCommitSha.Substring(0, [Math]::Min(7, $LatestCommitSha.Length)) }
            $warnings.Add("Committed sync report ($committedGeneratedAtText) is older than the latest report-affecting commit $shaLabel ($($latestCommitDateOffset.ToString('o'))); regenerate and recommit reports/profile-sync-report.json.")
        }
    }

    $smokeEvidenceStale = $false
    if ($committedPresent -and $smokeStatus -eq "not-run" -and [string]::IsNullOrWhiteSpace($smokeSource)) {
        $smokeEvidenceStale = $true
        $warnings.Add("Committed rendered-smoke status is not-run without local source metadata; run scripts/render-profile-smoke.ps1 locally and regenerate reports/profile-sync-report.json.")
    }

    # The report restamps its own generatedAt every run while folding in whatever smoke
    # artifact is on disk, so a fresh-looking report can carry arbitrarily old evidence.
    # Age the evidence against its own timestamp, not the wrapper's.
    $smokeEvidenceAgeHours = $null
    if ($null -ne $smokeGeneratedAt) {
        $smokeEvidenceAgeHours = [math]::Round(($Now.ToUniversalTime() - $smokeGeneratedAt.ToUniversalTime()).TotalHours, 2)
        # A future timestamp is clock skew or a fabricated artifact. Either way it clears
        # every staleness signal, so treat it as unusable rather than as very fresh.
        if ($smokeEvidenceAgeHours -lt 0) {
            $smokeEvidenceStale = $true
            $warnings.Add("Committed rendered-smoke evidence is dated in the future ($smokeGeneratedAtText); the artifact or the clock that produced it cannot be trusted, so run scripts/render-profile-smoke.ps1 locally and regenerate reports/profile-sync-report.json.")
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($smokeGeneratedAtText)) {
        # Present but unparseable is different from absent: the report is publishing a
        # timestamp nothing can read, which the absent case never does.
        $smokeEvidenceStale = $true
        $warnings.Add("Committed rendered-smoke evidence has an unparseable generatedAt ('$smokeGeneratedAtText'); run scripts/render-profile-smoke.ps1 locally and regenerate reports/profile-sync-report.json.")
    }
    $smokeAffectingCommitDateOffset = ConvertTo-DateTimeOffsetOrNull $SmokeAffectingCommitDate
    $smokeEvidenceBehindReadme = $false
    if ($null -ne $smokeGeneratedAt -and $null -ne $smokeAffectingCommitDateOffset -and
        $smokeGeneratedAt -lt $smokeAffectingCommitDateOffset) {
        $smokeEvidenceBehindReadme = $true
        $smokeEvidenceStale = $true
        $warnings.Add("Committed rendered-smoke evidence ($smokeGeneratedAtText) predates the latest smoke-affecting commit ($($smokeAffectingCommitDateOffset.ToString('o'))); run scripts/render-profile-smoke.ps1 locally and regenerate reports/profile-sync-report.json.")
    }

    $status = if ($warnings.Count -eq 0) {
        if ($generatedWithCommit) { "generated-with-commit" } else { "fresh" }
    } else { "stale" }

    return [ordered]@{
        status = $status
        committedReportPresent = [bool]$committedPresent
        committedReportGeneratedAt = $committedGeneratedAtText
        latestReportAffectingCommitSha = if ([string]::IsNullOrWhiteSpace($LatestCommitSha)) { $null } else { [string]$LatestCommitSha }
        latestReportAffectingCommitDate = if ($null -ne $latestCommitDateOffset) { $latestCommitDateOffset.ToString("o") } else { $null }
        reportAgeBehindCommit = [bool]$reportBehindCommit
        reportAgeBehindHours = $reportAgeBehindHours
        generatedWithCommit = [bool]$generatedWithCommit
        sameCommitThresholdMinutes = [int]$sameCommitThresholdMinutes
        smokeStatus = $smokeStatus
        smokeEvidenceStale = [bool]$smokeEvidenceStale
        smokeEvidenceGeneratedAt = if ([string]::IsNullOrWhiteSpace($smokeGeneratedAtText)) { $null } else { $smokeGeneratedAtText }
        smokeEvidenceAgeHours = $smokeEvidenceAgeHours
        smokeEvidenceBehindReadme = [bool]$smokeEvidenceBehindReadme
        smokeAffectingPaths = @($SmokeAffectingPathList)
        reportAffectingPaths = @($ReportAffectingPathList)
        warnings = @($warnings.ToArray())
        warningCount = [int]$warnings.Count
    }
}

function Get-RoadmapHygieneRules {
    # Each rule flags an OPEN roadmap entry whose completion is fully verifiable
    # from committed repository files. Items whose acceptance depends on
    # GitHub-side toggles (PVR enablement, branch settings) are intentionally
    # excluded because file state cannot prove them shipped.
    return @(
        [ordered]@{
            id = "dependency-review-action"
            marker = "Add dependency-review-action to PR workflows"
            satisfied = {
                $path = Join-Path $RepoRoot ".github/workflows/tests.yml"
                if (-not (Test-Path -LiteralPath $path)) { return $false }
                return ((Get-Content -LiteralPath $path -Raw) -match 'actions/dependency-review-action@')
            }
        },
        [ordered]@{
            id = "upload-artifact-v7"
            marker = "Upgrade upload-artifact to v7"
            satisfied = {
                $dir = Join-Path $RepoRoot ".github/workflows"
                if (-not (Test-Path -LiteralPath $dir)) { return $false }
                $all = @(Get-ChildItem -LiteralPath $dir -Filter '*.yml' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
                return ($all -match 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a') -and ($all -notmatch 'actions/upload-artifact@b7c566a772e6b6bfb58ed0dc250532a479d7789f')
            }
        },
        [ordered]@{
            id = "fetch-metadata-v3"
            marker = "fetch-metadata"
            satisfied = {
                $path = Join-Path $RepoRoot ".github/workflows/dependabot-auto-merge.yml"
                if (-not (Test-Path -LiteralPath $path)) { return $false }
                return ((Get-Content -LiteralPath $path -Raw) -match 'dependabot/fetch-metadata@25dd0e34f4fe68f24cc83900b1fe3fe149efef98')
            }
        },
        [ordered]@{
            id = "pip-dependabot"
            marker = "Add Dependabot pip updates"
            satisfied = {
                $path = Join-Path $RepoRoot ".github/dependabot.yml"
                if (-not (Test-Path -LiteralPath $path)) { return $false }
                return ((Get-Content -LiteralPath $path -Raw) -match 'package-ecosystem:\s*"pip"')
            }
        }
    )
}

function Test-RoadmapHygiene {
    <#
    .SYNOPSIS
    Reports open roadmap entries that current repository files already satisfy.
    .PARAMETER RoadmapPath
    Path to ROADMAP.md when reading roadmap text from disk.
    .PARAMETER RoadmapText
    Optional roadmap text used by tests instead of reading a file.
    .PARAMETER Rules
    Optional hygiene rule objects that map roadmap markers to satisfaction checks.
    #>
    [CmdletBinding()]
    param(
        [string]$RoadmapPath = (Join-Path $RepoRoot "ROADMAP.md"),
        [AllowNull()][string]$RoadmapText,
        [AllowNull()][object[]]$Rules
    )

    if ($null -eq $Rules) { $Rules = Get-RoadmapHygieneRules }

    $present = $false
    $text = $null
    if ($PSBoundParameters.ContainsKey("RoadmapText") -and $null -ne $RoadmapText) {
        $present = $true
        $text = $RoadmapText
    } elseif (Test-Path -LiteralPath $RoadmapPath) {
        $present = $true
        $text = Get-Content -LiteralPath $RoadmapPath -Raw
    }

    $rows = New-Object System.Collections.Generic.List[object]
    if ($present) {
        $openEntries = @([regex]::Matches($text, '(?m)^\s*-\s*\[ \]\s*(?<title>.+?)\s*$') | ForEach-Object { $_.Groups['title'].Value })
        foreach ($rule in @($Rules)) {
            $marker = [string]$rule.marker
            if ([string]::IsNullOrWhiteSpace($marker)) { continue }
            $matchingEntries = @($openEntries | Where-Object { $_ -match [regex]::Escape($marker) })
            if ($matchingEntries.Count -eq 0) { continue }

            $isSatisfied = $false
            try { $isSatisfied = [bool](& $rule.satisfied) } catch { $isSatisfied = $false }
            if ($isSatisfied) {
                $rows.Add([ordered]@{
                        ruleId = [string]$rule.id
                        marker = $marker
                        entry = [string]$matchingEntries[0]
                        reason = "Open roadmap entry matches '$marker' but current repository files already satisfy it; remove the entry."
                    })
            }
        }
    }

    $rowArray = @($rows.ToArray() | Sort-Object -Property @{ Expression = { [string]$_.ruleId } })
    return [ordered]@{
        status = if (-not $present) { "not-present" } elseif ($rowArray.Count -eq 0) { "clean" } else { "stale-entries" }
        roadmapPresent = [bool]$present
        shippedEntryCount = [int]$rowArray.Count
        warningCount = [int]$rowArray.Count
        rows = $rowArray
        note = "Warning-only roadmap hygiene: lists open ROADMAP.md entries already satisfied by committed repository files. ROADMAP.md is local-only and is typically absent in CI checkouts."
    }
}

function Test-RootMarkdownHygiene {
    <#
    .SYNOPSIS
    Checks root Markdown files against the repository documentation contract.
    .PARAMETER RepoRootPath
    Repository root to scan for root-level Markdown files.
    .PARAMETER AllowedFiles
    Markdown file names allowed at the repository root.
    .PARAMETER Exemptions
    Root Markdown names that should be reported as exempt instead of warnings.
    .PARAMETER RootMarkdownNames
    Optional file-name list used by tests instead of scanning the filesystem.
    #>
    [CmdletBinding()]
    param(
        [string]$RepoRootPath = $RepoRoot,
        [string[]]$AllowedFiles = @("README.md", "CLAUDE.md", "AGENTS.md", "CHANGELOG.md", "ROADMAP.md", "Roadmap_Blocked.md", "RESEARCH.md", "SECURITY.md"),
        [string[]]$Exemptions = @(),
        [AllowNull()][string[]]$RootMarkdownNames
    )

    if ($null -ne $RootMarkdownNames) {
        $names = @($RootMarkdownNames)
    } elseif (Test-Path -LiteralPath $RepoRootPath) {
        $names = @(Get-ChildItem -LiteralPath $RepoRootPath -Filter '*.md' -File | ForEach-Object { $_.Name })
    } else {
        $names = @()
    }

    $allowedSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($allowed in @($AllowedFiles)) { [void]$allowedSet.Add($allowed) }
    $exemptSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($exempt in @($Exemptions)) { [void]$exemptSet.Add($exempt) }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($name in @($names | Sort-Object -Unique)) {
        if ($allowedSet.Contains($name)) { continue }
        $isExempt = $exemptSet.Contains($name)
        $rows.Add([ordered]@{
                file = [string]$name
                status = if ($isExempt) { "exempt" } else { "unexpected" }
            })
    }

    $rowArray = @($rows.ToArray())
    $unexpected = @($rowArray | Where-Object { $_.status -eq "unexpected" })
    $exempt = @($rowArray | Where-Object { $_.status -eq "exempt" })

    return [ordered]@{
        status = if (@($unexpected).Count -eq 0) { "clean" } else { "unexpected-files" }
        rootMarkdownCount = [int]@($names).Count
        allowedFiles = @($AllowedFiles | Sort-Object -Unique)
        unexpectedFiles = @($unexpected | ForEach-Object { [string]$_.file })
        exemptFiles = @($exempt | ForEach-Object { [string]$_.file })
        rows = $rowArray
        warningCount = [int]@($unexpected).Count
        note = "Warning-only root Markdown hygiene against the repo documentation contract. Most non-README root Markdown is gitignored and absent in CI; historical leftovers can be removed or added to the exemption allowlist."
    }
}

function Read-DocConsistencyFile {
    param(
        [string]$Path,
        [System.Collections.Generic.List[string]]$Errors
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }
    $reportPath = ConvertTo-RepoRelativeReportPath -Path $fullPath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $Errors.Add("$reportPath is missing")
        return [ordered]@{
            path = $reportPath
            text = $null
        }
    }

    try {
        return [ordered]@{
            path = $reportPath
            text = Get-Content -LiteralPath $fullPath -Raw
        }
    } catch {
        $Errors.Add("$reportPath is unreadable: $($_.Exception.Message)")
        return [ordered]@{
            path = $reportPath
            text = $null
        }
    }
}

function Test-DocVersionConsistency {
    param(
        [string]$ProfileVersionPath = $script:ProfileVersionPath
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $versions = New-Object System.Collections.Generic.List[object]
    $dates = New-Object System.Collections.Generic.List[object]

    $profileVersionDoc = Read-DocConsistencyFile -Path $ProfileVersionPath -Errors $errors
    $profileVersion = $null
    $profileDate = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$profileVersionDoc.text)) {
        try {
            $profileVersionJson = [string]$profileVersionDoc.text | ConvertFrom-Json
            $profileVersion = [string](Get-MemberValue -Object $profileVersionJson -Name "version")
            $profileDate = [string](Get-MemberValue -Object $profileVersionJson -Name "date")
        } catch {
            $errors.Add("$($profileVersionDoc.path) is unreadable JSON: $($_.Exception.Message)")
        }
    }

    if ([string]::IsNullOrWhiteSpace($profileVersion)) {
        $errors.Add("$($profileVersionDoc.path) missing version")
    } elseif ($profileVersion -notmatch '^v\d+\.\d+\.\d+$') {
        $errors.Add("$($profileVersionDoc.path) version '$profileVersion' must match vMAJOR.MINOR.PATCH")
    }
    if ([string]::IsNullOrWhiteSpace($profileDate)) {
        $errors.Add("$($profileVersionDoc.path) missing date")
    } elseif (-not (Test-IsoDateText -Value $profileDate)) {
        $errors.Add("$($profileVersionDoc.path) date '$profileDate' is not a valid yyyy-MM-dd date")
    }

    $versions.Add([ordered]@{
            path = $profileVersionDoc.path
            field = "version"
            value = if ([string]::IsNullOrWhiteSpace($profileVersion)) { $null } else { $profileVersion }
        })
    $dates.Add([ordered]@{
            path = $profileVersionDoc.path
            field = "date"
            value = if ([string]::IsNullOrWhiteSpace($profileDate)) { $null } else { $profileDate }
        })

    $changelogHeadingValidation = [ordered]@{
        passed = $true
        headingCount = 0
        malformedCount = 0
        malformedHeadings = @()
    }

    return [ordered]@{
        passed = [bool]($errors.Count -eq 0)
        expectedVersion = if ([string]::IsNullOrWhiteSpace([string]$profileVersion)) { $null } else { [string]$profileVersion }
        expectedDate = if ([string]::IsNullOrWhiteSpace([string]$profileDate)) { $null } else { [string]$profileDate }
        versions = $versions.ToArray()
        dates = $dates.ToArray()
        changelogHeadingValidation = $changelogHeadingValidation
        errors = $errors.ToArray()
        warnings = $warnings.ToArray()
    }
}

function ConvertTo-ProfileVersion {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match($Value.Trim(), '^v?(\d+)\.(\d+)\.(\d+)$')
    if (-not $match.Success) {
        return $null
    }

    return [version]::new(
        [int]$match.Groups[1].Value,
        [int]$match.Groups[2].Value,
        [int]$match.Groups[3].Value
    )
}

function Get-ProfileRepositoryTagRef {
    param(
        [string]$TagName,
        [string]$Repository = "$Owner/$Owner"
    )

    $result = [ordered]@{
        checked = $false
        exists = $null
        tagName = if ([string]::IsNullOrWhiteSpace($TagName)) { $null } else { [string]$TagName }
        url = $null
        sha = $null
        unavailableReason = $null
    }

    if ([string]::IsNullOrWhiteSpace($TagName)) {
        $result.unavailableReason = "expected version is missing"
        return $result
    }

    if ($script:Offline) {
        $result.unavailableReason = "offline mode"
        return $result
    }

    $gh = Invoke-GhCli -Arguments @("api", "repos/$Repository/git/ref/tags/$TagName")
    $tagOutput = $gh.text
    if ($gh.exitCode -eq 0) {
        $tag = $tagOutput | ConvertFrom-Json
        $result.checked = $true
        $result.exists = $true
        $result.url = "https://github.com/$Repository/releases/tag/$TagName"
        $result.sha = [string](Get-NestedMemberValue -Object $tag -Path "object.sha")
        return $result
    }

    if (Test-GhApiNotFound -Output $tagOutput) {
        $result.checked = $true
        $result.exists = $false
        return $result
    }

    $result.unavailableReason = $tagOutput
    return $result
}

function Test-ProfileReleaseConsistency {
    <#
    .SYNOPSIS
    Compares the profile repo release/tag state with the tracked profile version.
    .PARAMETER Repos
    Repository metadata rows that include the profile repository.
    .PARAMETER DocVersionConsistency
    Version consistency result containing the expected profile version.
    .PARAMETER TagRef
    Optional pre-fetched expected tag reference result used by tests.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Repos,
        [object]$DocVersionConsistency,
        [object]$TagRef = $null
    )

    $repository = "$Owner/$Owner"
    $expectedVersion = [string](Get-MemberValue -Object $DocVersionConsistency -Name "expectedVersion")
    if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
        $expectedVersion = $null
    }

    $warnings = New-Object System.Collections.Generic.List[object]
    $profileRepo = $Repos | Where-Object { [string](Get-MemberValue -Object $_ -Name "name") -eq $Owner } | Select-Object -First 1
    $latestRelease = if ($profileRepo) { Get-MemberValue -Object $profileRepo -Name "latestRelease" } else { $null }
    $latestReleaseTag = if ($latestRelease) { [string](Get-MemberValue -Object $latestRelease -Name "tagName") } else { $null }
    $latestReleaseUrl = if ($latestRelease) { [string](Get-MemberValue -Object $latestRelease -Name "url") } else { $null }
    $latestReleasePublishedAt = if ($latestRelease) { ConvertTo-IsoText (Get-MemberValue -Object $latestRelease -Name "publishedAt") } else { $null }
    $versionRelation = "unavailable"
    $latestMatchesExpected = $false
    $latestAtLeastExpected = $false

    if (-not $profileRepo) {
        $warnings.Add([ordered]@{
            kind = "profile-repo-metadata-unavailable"
            expectedVersion = $expectedVersion
            actualVersion = $null
            message = "Profile repository metadata was not available in the public repo list."
        })
    } elseif ([string]::IsNullOrWhiteSpace($expectedVersion)) {
        $warnings.Add([ordered]@{
            kind = "expected-version-missing"
            expectedVersion = $null
            actualVersion = $latestReleaseTag
            message = "Planning docs did not expose a current version for release/tag comparison."
        })
    } elseif ([string]::IsNullOrWhiteSpace($latestReleaseTag)) {
        $versionRelation = "missing-release"
        $warnings.Add([ordered]@{
            kind = "latest-release-missing"
            expectedVersion = $expectedVersion
            actualVersion = $null
            message = "Profile repository has no latest release to compare with the planning version."
        })
    } else {
        $latestMatchesExpected = ([string]$latestReleaseTag -eq [string]$expectedVersion)
        $expectedParsed = ConvertTo-ProfileVersion -Value $expectedVersion
        $latestParsed = ConvertTo-ProfileVersion -Value $latestReleaseTag

        if ($latestMatchesExpected) {
            $versionRelation = "matching"
            $latestAtLeastExpected = $true
        } elseif ($expectedParsed -and $latestParsed) {
            $comparison = $latestParsed.CompareTo($expectedParsed)
            if ($comparison -lt 0) {
                $versionRelation = "behind"
                $warnings.Add([ordered]@{
                    kind = "latest-release-behind"
                    expectedVersion = $expectedVersion
                    actualVersion = $latestReleaseTag
                    message = "Latest profile release is older than the planning-doc version."
                })
            } elseif ($comparison -gt 0) {
                $versionRelation = "ahead"
                $latestAtLeastExpected = $true
                $warnings.Add([ordered]@{
                    kind = "latest-release-ahead"
                    expectedVersion = $expectedVersion
                    actualVersion = $latestReleaseTag
                    message = "Latest profile release is newer than the planning-doc version."
                })
            }
        } else {
            $versionRelation = "unparseable"
            $warnings.Add([ordered]@{
                kind = "release-version-unparseable"
                expectedVersion = $expectedVersion
                actualVersion = $latestReleaseTag
                message = "Release tag or planning version did not match vMAJOR.MINOR.PATCH."
            })
        }
    }

    if ($null -eq $TagRef) {
        $TagRef = [ordered]@{
            checked = $false
            exists = $null
            tagName = $expectedVersion
            url = $null
            sha = $null
            unavailableReason = "tag ref not checked"
        }
    }

    $tagRefChecked = [bool](Get-MemberValue -Object $TagRef -Name "checked")
    $tagRefExistsValue = Get-MemberValue -Object $TagRef -Name "exists"
    $tagRefExists = if ($null -eq $tagRefExistsValue) { $null } else { [bool]$tagRefExistsValue }
    $tagRefUnavailableReason = [string](Get-MemberValue -Object $TagRef -Name "unavailableReason")
    if ([string]::IsNullOrWhiteSpace($tagRefUnavailableReason)) {
        $tagRefUnavailableReason = $null
    }

    if ($expectedVersion) {
        if (-not $tagRefChecked) {
            $warnings.Add([ordered]@{
                kind = "expected-version-tag-unavailable"
                expectedVersion = $expectedVersion
                actualVersion = $null
                message = "Expected profile tag could not be checked: $tagRefUnavailableReason"
            })
        } elseif ($tagRefExists -ne $true) {
            $warnings.Add([ordered]@{
                kind = "expected-version-tag-missing"
                expectedVersion = $expectedVersion
                actualVersion = $null
                message = "Expected profile tag is not published on GitHub."
            })
        }
    }

    $releasePolicy = [ordered]@{
        status = "documented-internal-version-gap"
        decisionDocumentPath = "decision:profile-release-tag-policy"
        planningVersionKind = "profile-sync-internal-evidence-version"
        publicReleaseCadence = "manual-public-milestone-only"
        warningDisposition = "informational"
        releaseCreationRecommended = $false
        tagCreationRecommended = $false
        releaseCreationGate = "Create a GitHub release/tag only for user-visible public profile milestones or explicit operator request."
        nextAction = "Keep reporting the release/tag gap as warning-only evidence until a public milestone is intentionally cut or the repo switches to per-version releases."
    }

    return [ordered]@{
        passed = [bool]($warnings.Count -eq 0)
        repository = $repository
        expectedVersion = $expectedVersion
        latestReleaseTag = if ([string]::IsNullOrWhiteSpace($latestReleaseTag)) { $null } else { $latestReleaseTag }
        latestReleaseUrl = if ([string]::IsNullOrWhiteSpace($latestReleaseUrl)) { $null } else { $latestReleaseUrl }
        latestReleasePublishedAt = if ([string]::IsNullOrWhiteSpace($latestReleasePublishedAt)) { $null } else { $latestReleasePublishedAt }
        versionRelation = $versionRelation
        latestReleaseMatchesExpected = [bool]$latestMatchesExpected
        latestReleaseAtLeastExpected = [bool]$latestAtLeastExpected
        expectedTag = $expectedVersion
        expectedTagRefChecked = [bool]$tagRefChecked
        expectedTagExists = $tagRefExists
        expectedTagUrl = if ([string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $TagRef -Name "url"))) { $null } else { [string](Get-MemberValue -Object $TagRef -Name "url") }
        expectedTagSha = if ([string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $TagRef -Name "sha"))) { $null } else { [string](Get-MemberValue -Object $TagRef -Name "sha") }
        expectedTagUnavailableReason = $tagRefUnavailableReason
        warningCount = $warnings.Count
        warnings = $warnings.ToArray()
        releasePolicy = $releasePolicy
        note = "Warning-only comparison of the planning-doc version against the profile repository's latest GitHub release and matching tag ref."
    }
}
