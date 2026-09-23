# Report sections about the rendered profile: artifact drift diagnostics, README
# experience, size, heading and density budgets, artifact budgets, rendered-smoke
# evidence and SVG contrast. Dot-sourced by scripts/sync-profile.ps1.

function Get-CompactDiffSnippet {
    param(
        [AllowNull()][string]$Text,
        # Column of the first difference. A long line is windowed around it, so two README
        # rows that only differ past the first 177 characters do not read as identical.
        [int]$Around = 0
    )

    if ($null -eq $Text) {
        return $null
    }

    $start = 0
    if ($Text.Length -gt 180 -and $Around -gt 60) {
        $start = [Math]::Min($Around - 60, $Text.Length - 177)
    }
    $snippet = (($Text.Substring($start) -replace "`t", " ") -replace '\s+', ' ').Trim()
    $prefix = if ($start -gt 0) { "..." } else { "" }
    if ($snippet.Length -gt 180) {
        return ($prefix + $snippet.Substring(0, 177) + "...")
    }

    return ($prefix + $snippet)
}

function Get-NearestDiffSectionMarker {
    param(
        [string[]]$Lines,
        [int]$LineIndex,
        # Headings and <summary> open README sections; "id" opens a project in the indented
        # feed. Table rows are not sections: the changed row is already in the snippet.
        [string]$MarkerPattern = '^(#{1,6}\s+|<summary\b)'
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0 -or $LineIndex -lt 1) {
        return $null
    }

    # Strictly above the changed line, so a changed heading points at the section it sits in.
    $start = [Math]::Min($LineIndex - 1, $Lines.Count - 1)
    for ($i = $start; $i -ge 0; $i--) {
        $line = [string]$Lines[$i]
        if ($line -match $MarkerPattern) {
            return [ordered]@{
                line = [int]($i + 1)
                text = Get-CompactDiffSnippet -Text $line
            }
        }
    }

    return $null
}

function New-TextArtifactDiffDiagnostic {
    param(
        [string]$Artifact,
        [AllowNull()][string]$Current,
        [AllowNull()][string]$Expected,
        [bool]$InSync,
        # The feed is one long line whose volatile fields always differ, so its first
        # difference is located in the masked comparable JSON, indented: the same form the
        # sync verdict compares. Hashes always cover the artifact text itself.
        [ValidateSet("artifact-lines", "comparable-json-lines")]
        [string]$DiffBasis = "artifact-lines",
        [AllowNull()][string]$CurrentDiffText,
        [AllowNull()][string]$ExpectedDiffText
    )

    $currentNormalized = ConvertTo-NormalizedGeneratedText -Text $Current
    $expectedNormalized = ConvertTo-NormalizedGeneratedText -Text $Expected
    $currentDiffSource = if ($PSBoundParameters.ContainsKey('CurrentDiffText')) { ConvertTo-NormalizedGeneratedText -Text $CurrentDiffText } else { $currentNormalized }
    $expectedDiffSource = if ($PSBoundParameters.ContainsKey('ExpectedDiffText')) { ConvertTo-NormalizedGeneratedText -Text $ExpectedDiffText } else { $expectedNormalized }
    $markerArguments = @{}
    if ($DiffBasis -eq "comparable-json-lines") {
        $markerArguments['MarkerPattern'] = '^\s*"(id|suppressedId)":\s'
    }
    # No limit argument: in PowerShell 7 a negative -split limit counts pieces from the
    # right, so -1 returned the whole artifact as a single "line 1".
    $currentLines = @($currentDiffSource -split "`n")
    $expectedLines = @($expectedDiffSource -split "`n")
    $maxLineCount = [Math]::Max($currentLines.Count, $expectedLines.Count)
    $firstDiff = $null

    if (-not $InSync) {
        for ($i = 0; $i -lt $maxLineCount; $i++) {
            $currentLine = if ($i -lt $currentLines.Count) { [string]$currentLines[$i] } else { $null }
            $expectedLine = if ($i -lt $expectedLines.Count) { [string]$expectedLines[$i] } else { $null }
            # -cne: the sync verdict is case-sensitive, so a case-only change is the difference.
            if ($currentLine -cne $expectedLine) {
                $column = 0
                if ($null -ne $currentLine -and $null -ne $expectedLine) {
                    $shorter = [Math]::Min($currentLine.Length, $expectedLine.Length)
                    while ($column -lt $shorter -and $currentLine[$column] -ceq $expectedLine[$column]) {
                        $column++
                    }
                }
                $firstDiff = [ordered]@{
                    line = [int]($i + 1)
                    sectionMarker = Get-NearestDiffSectionMarker -Lines $expectedLines -LineIndex $i @markerArguments
                    current = Get-CompactDiffSnippet -Text $currentLine -Around $column
                    expected = Get-CompactDiffSnippet -Text $expectedLine -Around $column
                }
                break
            }
        }
    }

    return [ordered]@{
        artifact = $Artifact
        inSync = [bool]$InSync
        currentSha256 = Get-StringSha256 -Text $currentNormalized
        expectedSha256 = Get-StringSha256 -Text $expectedNormalized
        diffBasis = $DiffBasis
        firstDiff = $firstDiff
    }
}

function New-GeneratedArtifactDriftDiagnostics {
    param(
        [AllowNull()][string]$CurrentReadme,
        [AllowNull()][string]$ExpectedReadme,
        [AllowNull()][string]$CurrentProjects,
        [AllowNull()][string]$ExpectedProjects,
        [bool]$ReadmeInSync,
        [bool]$ProjectsInSync,
        [bool]$ProfileAssetsInSync,
        [object[]]$AssetChecks,
        [hashtable]$ExpectedAssets,
        [hashtable]$CurrentAssets = @{}
    )

    $affectedAssets = New-Object System.Collections.Generic.List[object]
    foreach ($assetCheck in @($AssetChecks | Where-Object { $null -ne $_ -and $_.inSync -ne $true })) {
        $path = [string]$assetCheck.path
        $currentText = if ($CurrentAssets.ContainsKey($path)) { [string]$CurrentAssets[$path] } else { "" }
        # A file the generator does not produce has no expected content, and -Write cannot
        # clear it because a write never deletes. Say so instead of hashing an empty string.
        $generated = [bool]($ExpectedAssets -and $ExpectedAssets.ContainsKey($path))
        $affectedAssets.Add([ordered]@{
            path = $path
            exists = [bool]$assetCheck.exists
            fatal = $true
            currentSha256 = if ([bool]$assetCheck.exists) { Get-StringSha256 -Text $currentText } else { $null }
            expectedSha256 = if ($generated) { Get-StringSha256 -Text ([string]$ExpectedAssets[$path]) } else { $null }
            remediation = if ($generated) { "run-write" } else { "delete-file" }
        })
    }

    return [ordered]@{
        remediationCommand = "pwsh -NoLogo -NoProfile -File ./scripts/sync-profile.ps1 -Write"
        readme = New-TextArtifactDiffDiagnostic -Artifact "README.md" -Current $CurrentReadme -Expected $ExpectedReadme -InSync:$ReadmeInSync
        projects = New-TextArtifactDiffDiagnostic -Artifact "projects.json" -Current $CurrentProjects -Expected $ExpectedProjects -InSync:$ProjectsInSync `
            -DiffBasis "comparable-json-lines" `
            -CurrentDiffText (ConvertTo-ProjectsSyncComparableJson -Json $CurrentProjects -Indented) `
            -ExpectedDiffText (ConvertTo-ProjectsSyncComparableJson -Json $ExpectedProjects -Indented)
        assets = [ordered]@{
            inSync = [bool]$ProfileAssetsInSync
            affectedAssetCount = [int]$affectedAssets.Count
            affectedAssets = $affectedAssets.ToArray()
        }
    }
}

function Test-ReadmeExperience {
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [string]$ExpectedReadme
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries | Where-Object {
        $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
    })
    $featured = @($entries | Where-Object { $_.featured -eq $true })
    $building = @($entries | Where-Object { $_.currentlyBuilding -eq $true })
    $missingPrimaryAction = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $entries) {
        $action = Get-PrimaryAction $entry (Get-RepoMeta $entry $repoLookup) $entry.category
        if ([string]::IsNullOrWhiteSpace([string]$action["label"]) -or [string]::IsNullOrWhiteSpace([string]$action["url"])) {
            $missingPrimaryAction.Add([string]$entry.repo)
        }
    }

    $missingAnchors = New-Object System.Collections.Generic.List[string]
    foreach ($definition in $CategoryDefinitions) {
        # Categories with no visible entries render no section, so only require an anchor
        # for categories that actually have at least one entry.
        $categoryEntryCount = @($entries | Where-Object { $_.category -eq $definition.Slug }).Count
        if ($categoryEntryCount -eq 0) {
            continue
        }
        $anchor = '<a id="{0}"></a>' -f (Get-CategoryAnchor $definition.Slug)
        if (-not $ExpectedReadme.Contains($anchor)) {
            $missingAnchors.Add($definition.Slug)
        }
    }

    $unlabeledDownloads = [regex]::Matches($ExpectedReadme, '<kbd>&#11015;\s*</kbd>').Count
    $hasStartHere = $ExpectedReadme.Contains("### Start Here")
    $hasSnapshot = $ExpectedReadme.Contains("### Catalog Snapshot")
    $hasGeneratedNotice = $ExpectedReadme.Contains($GeneratedCatalogNotice)
    $hasSetupInspectPath = $ExpectedReadme.Contains("Inspect before installing") -and
        $ExpectedReadme.Contains("-CheckOnly") -and
        $ExpectedReadme.Contains("SysAdminDoc-setup.ps1") -and
        $ExpectedReadme.Contains("SysAdminDoc-setup-*.log")
    $hasThemeAwareChrome = $ExpectedReadme.Contains("#gh-dark-mode-only") -and
        $ExpectedReadme.Contains("#gh-light-mode-only") -and
        $ExpectedReadme.Contains("assets/profile/header-light.svg#gh-light-mode-only") -and
        $ExpectedReadme.Contains("assets/profile/footer-light.svg#gh-light-mode-only")
    $thirdPartyMetricHostPattern = 'komarev\.com|github-readme-stats|streak-stats|github-readme-activity-graph'
    $thirdPartyMetricHostCount = [regex]::Matches($ExpectedReadme, $thirdPartyMetricHostPattern).Count
    $thirdPartyBadgeHostPattern = 'img\.shields\.io/github/(?:followers|stars)'
    $thirdPartyBadgeHostCount = [regex]::Matches($ExpectedReadme, $thirdPartyBadgeHostPattern).Count
    $thirdPartyRenderHostPattern = 'https://(?<host>(?:capsule-render\.vercel\.app|readme-typing-svg\.demolab\.com|skillicons\.dev))'
    $thirdPartyRenderHosts = @(
        [regex]::Matches($ExpectedReadme, $thirdPartyRenderHostPattern) |
            ForEach-Object { $_.Groups['host'].Value } |
            Sort-Object -Unique
    )
    $motionPattern = '(?i)(?:[?&]animation=|[?&]repeat=true|readme-typing-svg(?:\.demolab\.com)?)'
    $motionPatternCount = [regex]::Matches($ExpectedReadme, $motionPattern).Count
    $motionSafeChrome = $motionPatternCount -eq 0
    $profileStatsChromeCount = [regex]::Matches($ExpectedReadme, '<a href="https://skillicons\.dev">').Count
    $hasPlainTextTagline = $ExpectedReadme.Contains($ProfileTagline) -and
        $ExpectedReadme.Contains("Windows utilities, Android apps, browser extensions, web tools, media workflows, and generated validation evidence")
    $genericAltPattern = 'alt="(Header|Typing SVG|Profile Views|Followers|Stars|Tech Stack|GitHub Stats|Top Languages|GitHub Streak|Activity Graph|Footer)"'
    $genericAltCount = [regex]::Matches($ExpectedReadme, $genericAltPattern).Count
    $hasMeaningfulAltText = $genericAltCount -eq 0 -and
        $ExpectedReadme.Contains('alt="SysAdminDoc public tools command center profile header"') -and
        $ExpectedReadme.Contains('alt="SysAdminDoc generated profile footer"')
    # Per GitHub accessibility guidance, every <img> needs descriptive alt text.
    # Warning-only completeness check across all rendered <img> tags.
    $genericAltValuePattern = '(?i)^(header|typing svg|profile views|followers|stars|tech stack|github stats|top languages|github streak|activity graph|footer|image|img|logo|icon|screenshot|banner)$'
    $imageTags = [regex]::Matches($ExpectedReadme, '(?is)<img\b[^>]*>')
    $imageTagCount = $imageTags.Count
    $imageAltTextIssueCount = 0
    foreach ($imageTag in $imageTags) {
        $altMatch = [regex]::Match($imageTag.Value, '(?is)\balt\s*=\s*(?:"(?<alt>[^"]*)"|''(?<alt>[^'']*)'')')
        if (-not $altMatch.Success) {
            $imageAltTextIssueCount++
            continue
        }
        $altText = $altMatch.Groups['alt'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($altText) -or $altText -match $genericAltValuePattern) {
            $imageAltTextIssueCount++
        }
    }
    $imageAltTextComplete = $imageAltTextIssueCount -eq 0
    $hasFeaturedActionColumn = $ExpectedReadme.Contains("| Project | Category | Stars | Description | Action |")
    $hasFeaturedActionList = [regex]::IsMatch($ExpectedReadme, '(?m)^- \[\*\*.+?\*\*\]\(https://github\.com/SysAdminDoc/.+?\) -- .+?<br/>.+?<br/>(?:Action: )?\[')
    $hasFeaturedPrimaryActions = $hasFeaturedActionColumn -or $hasFeaturedActionList
    $taglinePrefix = '<p align="center"><b>' + $ProfileTagline + '</b>'
    $hasMinimalProfileHeader = $ExpectedReadme.TrimStart().StartsWith($taglinePrefix, [StringComparison]::Ordinal) -and
        $ExpectedReadme.Contains('<a href="' + (Get-ProfilePortfolioUrl) + '"><b>See everything') -and
        $ExpectedReadme.Contains('<a href="#powershell-system-utilities">PowerShell</a>') -and
        -not $ExpectedReadme.Contains('assets/profile/header-dark.svg') -and
        -not $ExpectedReadme.Contains('assets/profile/header-light.svg')
    $hasRichProfileHeader = $ExpectedReadme.Contains("assets/profile/header-dark.svg") -and
        $ExpectedReadme.Contains("View full portfolio") -and
        $ExpectedReadme.Contains("public tools command center")
    $hasCurrentlyBuildingActionColumn = ($building.Count -eq 0) -or
        (-not $ExpectedReadme.Contains("**Currently Building**")) -or
        $ExpectedReadme.Contains("| Project | Focus | Action |")
    $hasDiscoveryContract = ($hasMinimalProfileHeader -and -not $hasSnapshot -and $hasGeneratedNotice) -or
        ($hasMinimalProfileHeader -and -not $hasStartHere -and -not $hasSnapshot -and -not $hasGeneratedNotice)
    $hasProfileHeaderContract = ($hasRichProfileHeader -and $hasThemeAwareChrome -and $hasPlainTextTagline -and $hasMeaningfulAltText -and $profileStatsChromeCount -eq 0) -or
        ($hasMinimalProfileHeader -and -not $hasRichProfileHeader -and -not $hasPlainTextTagline -and $profileStatsChromeCount -eq 0)
    $passed = $hasDiscoveryContract -and $hasSetupInspectPath -and $hasCurrentlyBuildingActionColumn -and
        $hasProfileHeaderContract -and
        $motionSafeChrome -and
        $thirdPartyMetricHostCount -eq 0 -and $thirdPartyBadgeHostCount -eq 0 -and $thirdPartyRenderHosts.Count -eq 0 -and
        $missingAnchors.Count -eq 0 -and $missingPrimaryAction.Count -eq 0 -and $unlabeledDownloads -eq 0

    return [ordered]@{
        passed = [bool]$passed
        startHereSection = [bool]$hasStartHere
        catalogSnapshotSection = [bool]$hasSnapshot
        generatedCatalogNotice = [bool]$hasGeneratedNotice
        setupInspectPath = [bool]$hasSetupInspectPath
        themeAwareImageChrome = [bool]$hasThemeAwareChrome
        plainTextTagline = [bool]$hasPlainTextTagline
        meaningfulImageAltText = [bool]$hasMeaningfulAltText
        minimalProfileHeader = [bool]$hasMinimalProfileHeader
        richProfileHeader = [bool]$hasRichProfileHeader
        genericImageAltTextCount = $genericAltCount
        imageTagCount = [int]$imageTagCount
        imageAltTextIssueCount = [int]$imageAltTextIssueCount
        imageAltTextComplete = [bool]$imageAltTextComplete
        thirdPartyMetricHostCount = $thirdPartyMetricHostCount
        thirdPartyBadgeHostCount = $thirdPartyBadgeHostCount
        thirdPartyRenderHostCount = $thirdPartyRenderHosts.Count
        thirdPartyRenderHosts = $thirdPartyRenderHosts
        motionSafeChrome = [bool]$motionSafeChrome
        motionPatternCount = $motionPatternCount
        profileStatsChromeCount = $profileStatsChromeCount
        featuredRows = $featured.Count
        featuredActionColumn = [bool]$hasFeaturedActionColumn
        featuredActionList = [bool]$hasFeaturedActionList
        featuredPrimaryActions = [bool]$hasFeaturedPrimaryActions
        currentlyBuildingRows = $building.Count
        currentlyBuildingActionColumn = [bool]$hasCurrentlyBuildingActionColumn
        categoryAnchorCount = $CategoryDefinitions.Count - $missingAnchors.Count
        missingCategoryAnchors = $missingAnchors.ToArray()
        primaryActionCoverage = $entries.Count - $missingPrimaryAction.Count
        missingPrimaryActions = $missingPrimaryAction.ToArray()
        unlabeledDownloadButtons = $unlabeledDownloads
    }
}

function Test-ReadmeSizeBudget {
    param(
        [string]$ExpectedReadme,
        [int]$SoftLimitBytes = $ReadmeSoftLimitBytes
    )

    $byteCount = [System.Text.Encoding]::UTF8.GetByteCount($ExpectedReadme)
    $overSoftLimit = $byteCount -gt $SoftLimitBytes

    return [ordered]@{
        byteCount = $byteCount
        softLimitBytes = $SoftLimitBytes
        overSoftLimit = [bool]$overSoftLimit
        warning = if ($overSoftLimit) {
            "Generated README is $byteCount bytes, above the $SoftLimitBytes byte soft limit; consider collapsing low-traffic categories."
        } else {
            $null
        }
    }
}

function Test-ReadmeHeadingHierarchy {
    param(
        [string]$ExpectedReadme,
        # Profile READMEs render under the GitHub profile name (an implicit H1),
        # so opening at H2/H3 is allowed without being treated as a skipped level.
        [int]$ProfileContextMaxFirstLevel = 3
    )

    $sequence = New-Object System.Collections.Generic.List[int]
    $inFence = $false
    foreach ($line in ($ExpectedReadme -split "\r?\n")) {
        if ($line -match '^\s*(```|~~~)') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }
        $headingMatch = [regex]::Match($line, '^(?<hashes>#{1,6})\s+\S')
        if ($headingMatch.Success) {
            $sequence.Add($headingMatch.Groups['hashes'].Value.Length)
        }
    }

    $levels = @($sequence.ToArray())
    $firstLevel = if ($levels.Count -gt 0) { [int]$levels[0] } else { 0 }
    $profileContextAllowlistApplied = ($levels.Count -gt 0 -and $firstLevel -le $ProfileContextMaxFirstLevel)

    $skips = New-Object System.Collections.Generic.List[object]
    # Initial jump from the implied H1 to the first heading, only flagged when it
    # exceeds the profile-context allowance.
    if ($levels.Count -gt 0 -and -not $profileContextAllowlistApplied) {
        $skips.Add([ordered]@{ from = 1; to = $firstLevel; afterHeadingIndex = 0; context = "document-start" })
    }
    for ($i = 1; $i -lt $levels.Count; $i++) {
        if ($levels[$i] -gt ($levels[$i - 1] + 1)) {
            $skips.Add([ordered]@{ from = [int]$levels[$i - 1]; to = [int]$levels[$i]; afterHeadingIndex = $i; context = "descent" })
        }
    }

    $skipArray = @($skips.ToArray())
    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($skip in $skipArray) {
        $warnings.Add("Generated README heading level jumps from H$($skip.from) to H$($skip.to) ($($skip.context)); add the intermediate level or document the exception.")
    }

    return [ordered]@{
        status = if ($warnings.Count -eq 0) { "ok" } else { "warning" }
        headingCount = [int]$levels.Count
        firstLevel = [int]$firstLevel
        headingSequence = $levels
        profileContextMaxFirstLevel = [int]$ProfileContextMaxFirstLevel
        profileContextAllowlistApplied = [bool]$profileContextAllowlistApplied
        skippedLevelTransitions = $skipArray
        skippedLevelCount = [int]$skipArray.Count
        warnings = @($warnings.ToArray())
        warningCount = [int]$warnings.Count
    }
}

function New-ReadmePortfolioOnlyPreview {
    param(
        [object[]]$Entries,
        [object[]]$Candidates,
        [int]$CategorySoftLimit = $ReadmeCategorySoftLimit
    )

    $safeEntries = @($Entries)
    $safeCandidates = @($Candidates | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $_ -Name "repo"))
        } | Sort-Object @{ Expression = { [int](Get-MemberValue -Object $_ -Name "reviewRank") }; Ascending = $true })
    $candidateRepos = @($safeCandidates | ForEach-Object { [string](Get-MemberValue -Object $_ -Name "repo") })
    $candidateSet = @{}
    foreach ($repo in $candidateRepos) {
        $candidateSet[$repo.ToLowerInvariant()] = $true
    }

    $previewEntries = @($safeEntries | Where-Object {
            $repo = [string](Get-MemberValue -Object $_ -Name "repo")
            [string]::IsNullOrWhiteSpace($repo) -or -not $candidateSet.ContainsKey($repo.ToLowerInvariant())
        })
    $categoryRows = New-Object System.Collections.Generic.List[object]

    foreach ($definition in $CategoryDefinitions) {
        $slug = [string]$definition.Slug
        $currentCount = @($safeEntries | Where-Object { [string](Get-MemberValue -Object $_ -Name "category") -eq $slug }).Count
        $previewCount = @($previewEntries | Where-Object { [string](Get-MemberValue -Object $_ -Name "category") -eq $slug }).Count
        $categoryRows.Add([ordered]@{
                category = $slug
                displayName = Get-CategoryDisplayName -Slug $slug
                currentProjectCount = [int]$currentCount
                previewProjectCount = [int]$previewCount
                projectRowDelta = [int]($previewCount - $currentCount)
                currentOverSoftLimitBy = [int][Math]::Max(0, ($currentCount - $CategorySoftLimit))
                previewOverSoftLimitBy = [int][Math]::Max(0, ($previewCount - $CategorySoftLimit))
            })
    }

    $categoryRowsArray = @($categoryRows.ToArray())
    $largestPreviewCategory = @($categoryRowsArray |
        Sort-Object @{ Expression = { [int]$_.previewProjectCount }; Descending = $true }, category |
        Select-Object -First 1)
    $previewLargestCategory = $null
    $previewLargestCategoryCount = 0
    if ($largestPreviewCategory.Count -gt 0) {
        $previewLargestCategory = [string]$largestPreviewCategory[0].category
        $previewLargestCategoryCount = [int]$largestPreviewCategory[0].previewProjectCount
    }
    $largestCurrentCategory = @($categoryRowsArray |
        Sort-Object @{ Expression = { [int]$_.currentProjectCount }; Descending = $true }, category |
        Select-Object -First 1)
    $currentLargestCategory = $null
    if ($largestCurrentCategory.Count -gt 0) {
        $currentLargestCategory = [string]$largestCurrentCategory[0].category
    }

    $remainingOverSoftLimitCategoryCount = @($categoryRowsArray | Where-Object { [int]$_.previewOverSoftLimitBy -gt 0 }).Count
    $resolvedOverSoftLimitCategoryCount = @($categoryRowsArray | Where-Object {
            [int]$_.currentOverSoftLimitBy -gt 0 -and [int]$_.previewOverSoftLimitBy -eq 0
        }).Count
    $preservesPortfolioRoutes = @($safeCandidates | Where-Object {
            (Get-MemberValue -Object $_ -Name "includeInPortfolio") -ne $true
        }).Count -eq 0
    $candidateCount = [int]$candidateRepos.Count
    $status = if ($candidateCount -eq 0) {
        "no-candidates"
    } elseif ($remainingOverSoftLimitCategoryCount -gt 0) {
        "warning"
    } else {
        "ready"
    }
    $recommendation = if ($candidateCount -eq 0) {
        "keep-readme-routing-surface"
    } elseif ($remainingOverSoftLimitCategoryCount -gt 0) {
        "review-next-candidate-batch"
    } else {
        "review-catalog-demotion"
    }

    return [ordered]@{
        enabled = $true
        mode = "report-only"
        candidateSource = "readmeDensity.portfolioOnlyCandidates"
        candidateCount = $candidateCount
        candidateRepos = @($candidateRepos)
        currentProjectRowCount = [int]$safeEntries.Count
        previewProjectRowCount = [int]$previewEntries.Count
        projectRowDelta = [int]($previewEntries.Count - $safeEntries.Count)
        currentLargestCategory = $currentLargestCategory
        previewLargestCategory = $previewLargestCategory
        previewLargestCategoryCount = [int]$previewLargestCategoryCount
        remainingOverSoftLimitCategoryCount = [int]$remainingOverSoftLimitCategoryCount
        resolvedOverSoftLimitCategoryCount = [int]$resolvedOverSoftLimitCategoryCount
        preservesPortfolioRoutes = [bool]$preservesPortfolioRoutes
        catalogMutated = $false
        readmeMutated = $false
        projectsFeedMutated = $false
        status = $status
        recommendation = $recommendation
        note = "Report-only preview; catalog, README, and projects feed output are not mutated by this section."
        categoryRows = $categoryRowsArray
    }
}

function Test-ReadmeDensity {
    param(
        [string]$ExpectedReadme,
        [object[]]$Entries,
        [hashtable]$RepoLookup,
        [int]$CategorySoftLimit = $ReadmeCategorySoftLimit,
        [int]$LowSignalSoftLimit = $ReadmeLowSignalSoftLimit
    )

    $safeReadme = if ($null -eq $ExpectedReadme) { "" } else { $ExpectedReadme }
    $lineCount = if ([string]::IsNullOrEmpty($safeReadme)) {
        0
    } else {
        [regex]::Split($safeReadme.TrimEnd(), '\r?\n').Count
    }
    $detailsSectionCount = [regex]::Matches($safeReadme, '(?m)^<details>\s*$').Count
    $tableRowCount = [regex]::Matches($safeReadme, '(?m)^\| \[\*\*.+?\*\*\]\(https://github\.com/SysAdminDoc/').Count
    $categoryRows = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $repoOnlyProjectCount = 0
    $lowSignalProjectCount = 0
    $portfolioOnlyCandidateCount = 0
    $portfolioOnlyCandidateCategories = New-Object System.Collections.Generic.List[string]
    $portfolioOnlyCandidates = New-Object System.Collections.Generic.List[object]

    foreach ($definition in $CategoryDefinitions) {
        $slug = [string]$definition.Slug
        $categoryEntries = @($Entries | Where-Object { [string]$_.category -eq $slug })
        $categoryEntryRows = New-Object System.Collections.Generic.List[object]
        $repoOnlyCount = 0
        $actionableCount = 0
        $lowSignalCount = 0
        $overCategorySoftLimitBy = [Math]::Max(0, ($categoryEntries.Count - $CategorySoftLimit))
        $categoryWarnings = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $categoryEntries) {
            $meta = Get-RepoMeta $entry $RepoLookup
            $action = Get-PrimaryAction $entry $meta $entry.category
            $actionKind = [string]$action["kind"]
            $stars = if ($meta -and $null -ne (Get-MemberValue -Object $meta -Name "stargazerCount")) {
                [int](Get-MemberValue -Object $meta -Name "stargazerCount")
            } else {
                0
            }
            $release = if ($meta) { Get-MemberValue -Object $meta -Name "latestRelease" } else { $null }
            $pushedAt = if ($meta) { ConvertTo-IsoText (Get-MemberValue -Object $meta -Name "pushedAt") } else { $null }
            $categoryEntryRows.Add([ordered]@{
                    repo = [string]$entry.repo
                    title = [string]$entry.title
                    category = $slug
                    order = [int]$entry.order
                    primaryAction = $actionKind
                    stars = [int]$stars
                    includeInPortfolio = [bool]$entry.includeInPortfolio
                    featured = [bool]$entry.featured
                    currentlyBuilding = [bool]$entry.currentlyBuilding
                    hasLatestRelease = [bool]($null -ne $release)
                    pushedAt = if ([string]::IsNullOrWhiteSpace($pushedAt)) { $null } else { $pushedAt }
                    latestReleaseTag = if ($release) { [string](Get-MemberValue -Object $release -Name "tagName") } else { $null }
                    catalogReviewNote = if ([string]::IsNullOrWhiteSpace([string]$entry.readmeReviewNote)) { $null } else { [string]$entry.readmeReviewNote }
                })

            if ($actionKind -eq "repo") {
                $repoOnlyCount++
                if ($stars -eq 0) {
                    $lowSignalCount++
                }
            } else {
                $actionableCount++
            }
        }

        if ($categoryEntries.Count -gt $CategorySoftLimit) {
            $categoryWarnings.Add(("{0} has {1} README rows, above the {2} row category soft limit." -f $slug, $categoryEntries.Count, $CategorySoftLimit))
        }
        if ($lowSignalCount -ge $LowSignalSoftLimit -and $lowSignalCount -gt 0) {
            $categoryWarnings.Add(("{0} has {1} repo-only zero-star row(s); consider portfolio-only review for low-signal entries." -f $slug, $lowSignalCount))
        }

        $lowSignalCandidateCount = if ($lowSignalCount -ge $LowSignalSoftLimit) { $lowSignalCount } else { 0 }
        $categoryPortfolioOnlyCandidateCount = [Math]::Max($overCategorySoftLimitBy, $lowSignalCandidateCount)
        $categoryRoutingRecommendation = if ($categoryPortfolioOnlyCandidateCount -gt 0) {
            "review-portfolio-only-candidates"
        } else {
            "keep-in-readme"
        }
        $categoryCandidateRows = if ($categoryPortfolioOnlyCandidateCount -gt 0) {
            @($categoryEntryRows.ToArray() | Where-Object {
                    (Get-MemberValue -Object $_ -Name "primaryAction") -eq "repo" -and
                    (Get-MemberValue -Object $_ -Name "includeInPortfolio") -eq $true -and
                    (Get-MemberValue -Object $_ -Name "featured") -ne $true -and
                    (Get-MemberValue -Object $_ -Name "currentlyBuilding") -ne $true
                } | Sort-Object `
                @{ Expression = { [int](Get-MemberValue -Object $_ -Name "stars") }; Ascending = $true },
                @{ Expression = { [bool](Get-MemberValue -Object $_ -Name "hasLatestRelease") }; Ascending = $true },
                @{ Expression = {
                        $candidatePushedAt = Get-MemberValue -Object $_ -Name "pushedAt"
                        if ([string]::IsNullOrWhiteSpace([string]$candidatePushedAt)) {
                            [datetime]::MinValue
                        } else {
                            [datetime]::Parse([string]$candidatePushedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
                        }
                    }; Ascending = $true },
                @{ Expression = { [int](Get-MemberValue -Object $_ -Name "order") }; Descending = $true },
                @{ Expression = { [string](Get-MemberValue -Object $_ -Name "repo") }; Ascending = $true } |
                Select-Object -First $categoryPortfolioOnlyCandidateCount)
        } else {
            @()
        }
        foreach ($candidate in $categoryCandidateRows) {
            $candidateStars = [int](Get-MemberValue -Object $candidate -Name "stars")
            $reasonCodes = New-Object System.Collections.Generic.List[string]
            if ($overCategorySoftLimitBy -gt 0) { $reasonCodes.Add("category-over-soft-limit") }
            if ($lowSignalCandidateCount -gt 0 -and $candidateStars -eq 0) { $reasonCodes.Add("low-signal-zero-star") }
            $reasonCodes.Add("repo-only-action")
            if ((Get-MemberValue -Object $candidate -Name "hasLatestRelease") -ne $true) { $reasonCodes.Add("no-latest-release") }
            if ((Get-MemberValue -Object $candidate -Name "includeInPortfolio") -eq $true) { $reasonCodes.Add("portfolio-route-available") }

            $portfolioOnlyCandidates.Add([ordered]@{
                    reviewRank = [int]($portfolioOnlyCandidates.Count + 1)
                    category = $slug
                    displayName = Get-CategoryDisplayName -Slug $slug
                    repo = [string](Get-MemberValue -Object $candidate -Name "repo")
                    title = [string](Get-MemberValue -Object $candidate -Name "title")
                    stars = $candidateStars
                    primaryAction = [string](Get-MemberValue -Object $candidate -Name "primaryAction")
                    includeInPortfolio = [bool](Get-MemberValue -Object $candidate -Name "includeInPortfolio")
                    pushedAt = Get-MemberValue -Object $candidate -Name "pushedAt"
                    latestReleaseTag = Get-MemberValue -Object $candidate -Name "latestReleaseTag"
                    catalogReviewNote = Get-MemberValue -Object $candidate -Name "catalogReviewNote"
                    reasonCodes = @($reasonCodes.ToArray())
                    recommendation = "review-for-portfolio-only"
                })
        }

        foreach ($warning in $categoryWarnings) {
            $warnings.Add($warning)
        }

        $repoOnlyProjectCount += $repoOnlyCount
        $lowSignalProjectCount += $lowSignalCount
        $portfolioOnlyCandidateCount += $categoryPortfolioOnlyCandidateCount
        if ($categoryPortfolioOnlyCandidateCount -gt 0) {
            $portfolioOnlyCandidateCategories.Add($slug)
        }
        $categoryRows.Add([ordered]@{
            category = $slug
            displayName = Get-CategoryDisplayName -Slug $slug
            projectCount = [int]$categoryEntries.Count
            actionableCount = [int]$actionableCount
            repoOnlyCount = [int]$repoOnlyCount
            lowSignalCount = [int]$lowSignalCount
            overCategorySoftLimitBy = [int]$overCategorySoftLimitBy
            portfolioOnlyCandidateCount = [int]$categoryPortfolioOnlyCandidateCount
            routingRecommendation = $categoryRoutingRecommendation
            warningCount = [int]$categoryWarnings.Count
            warnings = @($categoryWarnings)
        })
    }

    $largestCategory = @($categoryRows | Sort-Object @{ Expression = { [int]$_.projectCount }; Descending = $true }, category | Select-Object -First 1)
    $largestCategoryName = $null
    $largestCategoryCount = 0
    if ($largestCategory.Count -gt 0) {
        $largestCategoryName = [string]$largestCategory[0].category
        $largestCategoryCount = [int]$largestCategory[0].projectCount
    }
    $warningsArray = @($warnings.ToArray())
    $categoryRowsArray = @($categoryRows.ToArray())
    $routingRecommendation = if ($portfolioOnlyCandidateCount -gt 0) {
        "review-portfolio-only-candidates"
    } else {
        "keep-readme-routing-surface"
    }
    $portfolioOnlyPreview = New-ReadmePortfolioOnlyPreview `
        -Entries $Entries `
        -Candidates $portfolioOnlyCandidates.ToArray() `
        -CategorySoftLimit $CategorySoftLimit

    return [ordered]@{
        lineCount = [int]$lineCount
        detailsSectionCount = [int]$detailsSectionCount
        tableRowCount = [int]$tableRowCount
        projectRowCount = [int](@($Entries).Count)
        categoryCount = [int]($CategoryDefinitions.Count)
        categorySoftLimit = [int]$CategorySoftLimit
        lowSignalSoftLimit = [int]$LowSignalSoftLimit
        largestCategory = $largestCategoryName
        largestCategoryCount = $largestCategoryCount
        repoOnlyProjectCount = [int]$repoOnlyProjectCount
        lowSignalProjectCount = [int]$lowSignalProjectCount
        portfolioOnlyCandidateCount = [int]$portfolioOnlyCandidateCount
        portfolioOnlyCandidateCategoryCount = [int]$portfolioOnlyCandidateCategories.Count
        portfolioOnlyCandidateCategories = @($portfolioOnlyCandidateCategories.ToArray())
        portfolioOnlyCandidateSelectionPolicy = "Review non-featured, non-currently-building repo-only rows that still have portfolio routes; sort by stars, release availability, age, category order, and repo name."
        portfolioOnlyCandidates = @($portfolioOnlyCandidates.ToArray())
        portfolioOnlyPreview = $portfolioOnlyPreview
        routingRecommendation = $routingRecommendation
        warningCount = [int]($warningsArray.Count)
        warnings = $warningsArray
        categoryRows = $categoryRowsArray
    }
}

function New-ArtifactBudgetRow {
    param(
        [string]$Artifact,
        [string]$Metric,
        [int]$Value,
        [int]$SoftLimit,
        [string]$Note
    )

    $overSoftLimit = $Value -gt $SoftLimit
    return [ordered]@{
        artifact = $Artifact
        metric = $Metric
        value = [int]$Value
        softLimit = [int]$SoftLimit
        overSoftLimit = [bool]$overSoftLimit
        warning = if ($overSoftLimit) {
            "{0} {1} is {2}, above the {3} soft limit." -f $Artifact, $Metric, $Value, $SoftLimit
        } else {
            $null
        }
        note = $Note
    }
}

function Test-GeneratedArtifactBudgets {
    param(
        [string]$ExpectedReadme,
        [string]$ExpectedProjectsJson,
        [hashtable]$ExpectedAssets,
        [AllowNull()][string]$ReportJson
    )

    $safeReadme = if ($null -eq $ExpectedReadme) { "" } else { $ExpectedReadme }
    $safeProjects = if ($null -eq $ExpectedProjectsJson) { "" } else { $ExpectedProjectsJson }
    $safeReport = if ($null -eq $ReportJson) { "" } else { $ReportJson }
    $lineCount = if ([string]::IsNullOrEmpty($safeReadme)) {
        0
    } else {
        [regex]::Split($safeReadme.TrimEnd(), '\r?\n').Count
    }
    $tableRowCount = [regex]::Matches($safeReadme, '(?m)^\| \[\*\*.+?\*\*\]\(https://github\.com/SysAdminDoc/').Count
    $detailsSectionCount = [regex]::Matches($safeReadme, '(?m)^<details>\s*$').Count
    $imageTagCount = [regex]::Matches($safeReadme, '<img\b|!\[').Count
    $codeFenceCount = [regex]::Matches($safeReadme, '(?m)^```').Count
    $codeBlockCount = [int][Math]::Floor($codeFenceCount / 2)
    $assetTotalBytes = 0
    $assetCount = 0
    $assetKeys = if ($null -eq $ExpectedAssets) {
        @()
    } elseif ($ExpectedAssets -is [System.Collections.IDictionary]) {
        @($ExpectedAssets.Keys)
    } elseif ($ExpectedAssets.PSObject.Properties.Name -contains "Keys") {
        @($ExpectedAssets.Keys)
    } else {
        @()
    }
    foreach ($assetPath in $assetKeys) {
        $assetCount++
        $assetTotalBytes += [System.Text.Encoding]::UTF8.GetByteCount(([string]$ExpectedAssets[$assetPath]) + [Environment]::NewLine)
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "bytes" -Value ([System.Text.Encoding]::UTF8.GetByteCount($safeReadme)) -SoftLimit $ReadmeSoftLimitBytes -Note "Generated profile README byte budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "lines" -Value $lineCount -SoftLimit $ReadmeLineSoftLimit -Note "Rendered profile scan budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "tableRows" -Value $tableRowCount -SoftLimit $ReadmeTableRowSoftLimit -Note "Generated project table-row budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "detailsSections" -Value $detailsSectionCount -SoftLimit $ReadmeDetailsSectionSoftLimit -Note "Collapsible section budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "imageTags" -Value $imageTagCount -SoftLimit $ReadmeImageTagSoftLimit -Note "Rendered image budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "codeBlocks" -Value $codeBlockCount -SoftLimit $ReadmeCodeBlockSoftLimit -Note "Install-snippet block budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "projects.json" -Metric "bytes" -Value ([System.Text.Encoding]::UTF8.GetByteCount($safeProjects)) -SoftLimit $ProjectsJsonSoftLimitBytes -Note "Public portfolio feed size budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "reports/profile-sync-report.json" -Metric "bytes" -Value ([System.Text.Encoding]::UTF8.GetByteCount($safeReport)) -SoftLimit $ReportJsonSoftLimitBytes -Note "Serialized sync-report size budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "assets/profile" -Metric "bytes" -Value $assetTotalBytes -SoftLimit $ProfileAssetsSoftLimitBytes -Note "Generated profile SVG asset total budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "assets/profile" -Metric "files" -Value $assetCount -SoftLimit $ProfileAssetsCountSoftLimit -Note "Generated profile SVG asset count budget."))

    $warnings = @($rows.ToArray() | Where-Object { $_.overSoftLimit -eq $true } | ForEach-Object { $_.warning })
    return [ordered]@{
        status = if ($warnings.Count -gt 0) { "warning" } else { "within-budget" }
        warningCount = [int]$warnings.Count
        warnings = @($warnings)
        rows = @($rows.ToArray())
    }
}

function New-RenderedProfileSmokeSummary {
    <#
    .SYNOPSIS
    Normalizes rendered profile smoke-test evidence for the sync report.
    .PARAMETER SmokeReport
    Parsed smoke-test report object, or null when no smoke artifact is available.
    .PARAMETER SourcePath
    Local rendered-profile smoke artifact path used as report provenance.
    .PARAMETER MinimumRootClientWidth
    Minimum acceptable root client width for mobile rendered-profile checks.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$SmokeReport,
        [AllowNull()][string]$SourcePath,
        [int]$MinimumRootClientWidth = $RenderedSmokeMinimumRootClientWidth
    )

    $sourcePathForReport = if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $null
    } else {
        ConvertTo-RepoRelativeReportPath -Path $SourcePath
    }

    if ($null -eq $SmokeReport) {
        $reason = "Local rendered smoke artifact was not found; run scripts/render-profile-smoke.ps1 locally to collect it."
        return [ordered]@{
            status = "not-run"
            source = "missing-local-artifact"
            sourcePath = $sourcePathForReport
            generatedAt = $null
            url = $null
            viewportCount = 0
            passedViewportCount = 0
            failedViewportCount = 0
            failedImageCount = 0
            missingSectionCount = 0
            overflowCount = 0
            accessibilityEvidenceAvailable = $false
            detailsCount = 0
            detailsSummaryCount = 0
            detailsKeyboardCheckCount = 0
            detailsKeyboardPassedCount = 0
            detailsKeyboardFailedCount = 0
            detailsCollapsedFocusPassCount = 0
            detailsExpandedFocusPassCount = 0
            detailsActivationPassCount = 0
            detailsKeyboardSanityPassed = $null
            tableCount = 0
            tableOverflowCount = 0
            linkCount = 0
            linkLabelCount = 0
            uniqueLinkLabelCount = 0
            duplicateLinkLabelCount = 0
            actionableLinkCount = 0
            uniqueActionableLinkLabelCount = 0
            emptyLinkLabelCount = 0
            nonActionableLinkCount = 0
            linkLabelSanityPassed = $null
            desktopPassedCount = 0
            desktopFailedCount = 0
            mobilePassedCount = 0
            mobileFailedCount = 0
            screenshotCount = 0
            screenshotPaths = @()
            firstViewportHeaderCount = 0
            firstViewportStartHereCount = 0
            toolCatalogPresenceCount = 0
            footerPresenceCount = 0
            blankViewportCount = 0
            croppedElementCount = 0
            overlapWarningCount = 0
            minimumRootClientWidth = $null
            mobileRootClientWidth = $null
            skipReason = $reason
            warningCount = 1
            warnings = @($reason)
        }
    }

    $skipped = [bool](Get-MemberValue -Object $SmokeReport -Name "skipped")
    $skipReason = [string](Get-MemberValue -Object $SmokeReport -Name "skipReason")
    $viewports = @(Get-MemberValue -Object $SmokeReport -Name "viewports")
    $passedViewportCount = @($viewports | Where-Object { [bool](Get-MemberValue -Object $_ -Name "passed") }).Count
    $failedViewportCount = @($viewports | Where-Object { -not [bool](Get-MemberValue -Object $_ -Name "passed") }).Count
    $failedImageCount = 0
    $missingSectionCount = 0
    $overflowCount = 0
    $accessibilityEvidenceAvailable = $false
    $detailsCount = 0
    $detailsSummaryCount = 0
    $detailsKeyboardCheckCount = 0
    $detailsKeyboardPassedCount = 0
    $detailsKeyboardFailedCount = 0
    $detailsCollapsedFocusPassCount = 0
    $detailsExpandedFocusPassCount = 0
    $detailsActivationPassCount = 0
    $detailsKeyboardSanityPassed = $null
    $tableCount = 0
    $tableOverflowCount = 0
    $linkCount = 0
    $linkLabelCount = 0
    $uniqueLinkLabelCount = 0
    $duplicateLinkLabelCount = 0
    $actionableLinkCount = 0
    $uniqueActionableLinkLabelCount = 0
    $emptyLinkLabelCount = 0
    $nonActionableLinkCount = 0
    $linkLabelSanityPassed = $null
    $desktopPassedCount = 0
    $desktopFailedCount = 0
    $mobilePassedCount = 0
    $mobileFailedCount = 0
    $screenshotPaths = New-Object System.Collections.Generic.List[string]
    $firstViewportHeaderCount = 0
    $firstViewportStartHereCount = 0
    $toolCatalogPresenceCount = 0
    $footerPresenceCount = 0
    $blankViewportCount = 0
    $croppedElementCount = 0
    $overlapWarningCount = 0
    $visualEvidenceAvailable = $false
    $rootWidths = New-Object System.Collections.Generic.List[int]
    $mobileRootClientWidth = $null
    foreach ($viewport in $viewports) {
        $viewportProperties = @(Get-ObjectPropertyNames -Object $viewport)
        $viewportName = [string](Get-MemberValue -Object $viewport -Name "name")
        if ($viewportName -eq "desktop") {
            if ([bool](Get-MemberValue -Object $viewport -Name "passed")) { $desktopPassedCount++ } else { $desktopFailedCount++ }
        } elseif ($viewportName -eq "mobile") {
            if ([bool](Get-MemberValue -Object $viewport -Name "passed")) { $mobilePassedCount++ } else { $mobileFailedCount++ }
        }
        $screenshotPath = Get-MemberValue -Object $viewport -Name "screenshotPath"
        if ([string]::IsNullOrWhiteSpace([string]$screenshotPath)) {
            $screenshotPath = Get-MemberValue -Object $viewport -Name "screenshot"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$screenshotPath)) {
            $screenshotPaths.Add((ConvertTo-RepoRelativeReportPath -Path ([string]$screenshotPath)))
        }

        $failedImageCount += @(Get-MemberValue -Object $viewport -Name "failedImages").Count
        $missingSectionCount += @(Get-MemberValue -Object $viewport -Name "missingSections").Count
        if ([bool](Get-MemberValue -Object $viewport -Name "rootOverflow") -or [bool](Get-MemberValue -Object $viewport -Name "documentOverflow")) {
            $overflowCount++
        }
        if ($viewportProperties -contains "componentPresence" -or $viewportProperties -contains "firstViewportComponentPresence" -or $viewportProperties -contains "blankPage" -or $viewportProperties -contains "croppedElementCount" -or $viewportProperties -contains "overlapWarningCount") {
            $visualEvidenceAvailable = $true
        }
        if ($viewportProperties -contains "detailsCount" -or $viewportProperties -contains "tableOverflowCount" -or $viewportProperties -contains "linkLabelCount") {
            $accessibilityEvidenceAvailable = $true
            $detailsCount += [int](Get-MemberValue -Object $viewport -Name "detailsCount")
            $detailsSummaryCount += [int](Get-MemberValue -Object $viewport -Name "detailsSummaryCount")
            $tableCount += [int](Get-MemberValue -Object $viewport -Name "tableCount")
            $tableOverflowCount += [int](Get-MemberValue -Object $viewport -Name "tableOverflowCount")
            $linkCount += [int](Get-MemberValue -Object $viewport -Name "linkCount")
            $linkLabelCount += [int](Get-MemberValue -Object $viewport -Name "linkLabelCount")
            $uniqueLinkLabelCount += [int](Get-MemberValue -Object $viewport -Name "uniqueLinkLabelCount")
            $duplicateLinkLabelCount += [int](Get-MemberValue -Object $viewport -Name "duplicateLinkLabelCount")
            $actionableLinkCount += [int](Get-MemberValue -Object $viewport -Name "actionableLinkCount")
            $uniqueActionableLinkLabelCount += [int](Get-MemberValue -Object $viewport -Name "uniqueActionableLinkLabelCount")
            $emptyLinkLabelCount += [int](Get-MemberValue -Object $viewport -Name "emptyLinkLabelCount")
            $nonActionableLinkCount += [int](Get-MemberValue -Object $viewport -Name "nonActionableLinkCount")
            $viewportLinkLabelSanity = Get-MemberValue -Object $viewport -Name "linkLabelSanityPassed"
            if ($null -ne $viewportLinkLabelSanity) {
                $linkLabelSanityPassed = if ($null -eq $linkLabelSanityPassed) { [bool]$viewportLinkLabelSanity } else { [bool]$linkLabelSanityPassed -and [bool]$viewportLinkLabelSanity }
            }
            $keyboard = Get-MemberValue -Object $viewport -Name "detailsKeyboardSanity"
            if ($null -ne $keyboard) {
                $detailsKeyboardCheckCount += [int](Get-MemberValue -Object $keyboard -Name "detailCount")
                $detailsKeyboardPassedCount += [int](Get-MemberValue -Object $keyboard -Name "detailCount") - [int](Get-MemberValue -Object $keyboard -Name "failedCount")
                $detailsKeyboardFailedCount += [int](Get-MemberValue -Object $keyboard -Name "failedCount")
                $detailsCollapsedFocusPassCount += [int](Get-MemberValue -Object $keyboard -Name "collapsedFocusPassCount")
                $detailsExpandedFocusPassCount += [int](Get-MemberValue -Object $keyboard -Name "expandedFocusPassCount")
                $detailsActivationPassCount += [int](Get-MemberValue -Object $keyboard -Name "activationPassCount")
                $viewportKeyboardSanity = Get-MemberValue -Object $keyboard -Name "passed"
                if ($null -ne $viewportKeyboardSanity) {
                    $detailsKeyboardSanityPassed = if ($null -eq $detailsKeyboardSanityPassed) { [bool]$viewportKeyboardSanity } else { [bool]$detailsKeyboardSanityPassed -and [bool]$viewportKeyboardSanity }
                }
            }
        }

        $firstViewportComponentPresence = Get-MemberValue -Object $viewport -Name "firstViewportComponentPresence"
        if ($null -ne $firstViewportComponentPresence) {
            $firstViewportHeaderCount += [int](Get-MemberValue -Object $firstViewportComponentPresence -Name "header")
            $firstViewportStartHereCount += [int](Get-MemberValue -Object $firstViewportComponentPresence -Name "startHere")
        }

        $componentPresence = Get-MemberValue -Object $viewport -Name "componentPresence"
        if ($null -ne $componentPresence) {
            $toolCatalogPresenceCount += [int](Get-MemberValue -Object $componentPresence -Name "toolCatalog")
            $footerPresenceCount += [int](Get-MemberValue -Object $componentPresence -Name "footer")
        }

        if (($viewportProperties -contains "blankPage") -and [bool](Get-MemberValue -Object $viewport -Name "blankPage")) {
            $blankViewportCount++
        }
        if ($viewportProperties -contains "croppedElementCount") {
            $croppedElementCount += [int](Get-MemberValue -Object $viewport -Name "croppedElementCount")
        }
        if ($viewportProperties -contains "overlapWarningCount") {
            $overlapWarningCount += [int](Get-MemberValue -Object $viewport -Name "overlapWarningCount")
        }

        $rootClientWidth = Get-MemberValue -Object $viewport -Name "rootClientWidth"
        if ($null -ne $rootClientWidth) {
            $widthValue = [int]$rootClientWidth
            $rootWidths.Add($widthValue)
            if ([string](Get-MemberValue -Object $viewport -Name "name") -eq "mobile") {
                $mobileRootClientWidth = if ($null -eq $mobileRootClientWidth) { $widthValue } else { [Math]::Min([int]$mobileRootClientWidth, $widthValue) }
            }
        }
    }

    $minimumRootClientWidthValue = if ($rootWidths.Count -gt 0) {
        [int](@($rootWidths.ToArray()) | Measure-Object -Minimum).Minimum
    } else {
        $null
    }
    $warnings = New-Object System.Collections.Generic.List[string]
    if ($failedViewportCount -gt 0) {
        $warnings.Add("Rendered profile smoke has $failedViewportCount failed viewport(s).")
    }
    if ($failedImageCount -gt 0) {
        $warnings.Add("Rendered profile smoke has $failedImageCount failed image(s).")
    }
    if ($missingSectionCount -gt 0) {
        $warnings.Add("Rendered profile smoke has $missingSectionCount missing section assertion(s).")
    }
    if ($overflowCount -gt 0) {
        $warnings.Add("Rendered profile smoke has $overflowCount viewport overflow warning(s).")
    }
    if ($null -ne $mobileRootClientWidth -and $mobileRootClientWidth -lt $MinimumRootClientWidth) {
        $warnings.Add("Rendered profile mobile root width is $mobileRootClientWidth px, below the $MinimumRootClientWidth px budget.")
    }
    if ($visualEvidenceAvailable) {
        if ($screenshotPaths.Count -lt $viewports.Count) {
            $warnings.Add("Rendered profile smoke captured $($screenshotPaths.Count) screenshot path(s) for $($viewports.Count) viewport(s).")
        }
        if ($firstViewportHeaderCount -eq 0) {
            $warnings.Add("Rendered profile smoke did not find the profile header region in any first viewport.")
        }
        if ($firstViewportStartHereCount -eq 0) {
            $warnings.Add("Rendered profile smoke did not find Start Here routing in any first viewport.")
        }
        if ($toolCatalogPresenceCount -eq 0) {
            $warnings.Add("Rendered profile smoke did not find the Tool Catalog in the rendered document.")
        }
        if ($footerPresenceCount -eq 0) {
            $warnings.Add("Rendered profile smoke did not find the profile footer in the rendered document.")
        }
        if ($blankViewportCount -gt 0) {
            $warnings.Add("Rendered profile smoke found $blankViewportCount blank viewport(s).")
        }
        if ($croppedElementCount -gt 0) {
            $warnings.Add("Rendered profile smoke found $croppedElementCount horizontally cropped element(s).")
        }
        if ($overlapWarningCount -gt 0) {
            $warnings.Add("Rendered profile smoke found $overlapWarningCount first-viewport overlap warning(s).")
        }
    }
    if ($accessibilityEvidenceAvailable) {
        # A table that scrolls inside a page that does not itself overflow is how GitHub
        # renders wide Markdown tables at phone widths: the table gets its own scroll
        # container, so the page layout is intact. Only warn when the page really breaks,
        # and keep the per-table count as informational evidence either way.
        if ($tableOverflowCount -gt 0 -and $overflowCount -gt 0) {
            $warnings.Add("Rendered profile smoke found $tableOverflowCount table overflow warning(s) on a page that also overflows horizontally.")
        }
        if ($emptyLinkLabelCount -gt 0) {
            $warnings.Add("Rendered profile smoke found $emptyLinkLabelCount link(s) without an accessible label.")
        }
        if ($nonActionableLinkCount -gt 0) {
            $warnings.Add("Rendered profile smoke found $nonActionableLinkCount non-actionable link target(s).")
        }
        if ($null -ne $detailsKeyboardSanityPassed -and -not $detailsKeyboardSanityPassed) {
            $warnings.Add("Rendered profile smoke found $detailsKeyboardFailedCount details keyboard/focus sanity failure(s).")
        }
        if ($null -ne $linkLabelSanityPassed -and -not $linkLabelSanityPassed -and $emptyLinkLabelCount -eq 0 -and $nonActionableLinkCount -eq 0) {
            $warnings.Add("Rendered profile smoke could not confirm actionable accessible link labels.")
        }
    }
    if ($skipped) {
        $reason = if ([string]::IsNullOrWhiteSpace($skipReason)) { "reason unavailable" } else { $skipReason }
        $warnings.Add("Rendered profile smoke did not run locally: $reason")
    }

    return [ordered]@{
        status = if ($skipped) { "not-run" } elseif ([bool](Get-MemberValue -Object $SmokeReport -Name "passed") -and $warnings.Count -eq 0) { "passed" } else { "warning" }
        source = "local-artifact"
        sourcePath = $sourcePathForReport
        generatedAt = Get-MemberValue -Object $SmokeReport -Name "generatedAt"
        url = Get-MemberValue -Object $SmokeReport -Name "url"
        viewportCount = [int]$viewports.Count
        passedViewportCount = [int]$passedViewportCount
        failedViewportCount = [int]$failedViewportCount
        failedImageCount = [int]$failedImageCount
        missingSectionCount = [int]$missingSectionCount
        overflowCount = [int]$overflowCount
        accessibilityEvidenceAvailable = [bool]$accessibilityEvidenceAvailable
        detailsCount = [int]$detailsCount
        detailsSummaryCount = [int]$detailsSummaryCount
        detailsKeyboardCheckCount = [int]$detailsKeyboardCheckCount
        detailsKeyboardPassedCount = [int]$detailsKeyboardPassedCount
        detailsKeyboardFailedCount = [int]$detailsKeyboardFailedCount
        detailsCollapsedFocusPassCount = [int]$detailsCollapsedFocusPassCount
        detailsExpandedFocusPassCount = [int]$detailsExpandedFocusPassCount
        detailsActivationPassCount = [int]$detailsActivationPassCount
        detailsKeyboardSanityPassed = $detailsKeyboardSanityPassed
        tableCount = [int]$tableCount
        tableOverflowCount = [int]$tableOverflowCount
        tableOverflowDisposition = if ($tableOverflowCount -eq 0) {
            "none"
        } elseif ($overflowCount -gt 0) {
            "page-overflow"
        } else {
            "contained-table-scroll"
        }
        linkCount = [int]$linkCount
        linkLabelCount = [int]$linkLabelCount
        uniqueLinkLabelCount = [int]$uniqueLinkLabelCount
        duplicateLinkLabelCount = [int]$duplicateLinkLabelCount
        actionableLinkCount = [int]$actionableLinkCount
        uniqueActionableLinkLabelCount = [int]$uniqueActionableLinkLabelCount
        emptyLinkLabelCount = [int]$emptyLinkLabelCount
        nonActionableLinkCount = [int]$nonActionableLinkCount
        linkLabelSanityPassed = $linkLabelSanityPassed
        desktopPassedCount = [int]$desktopPassedCount
        desktopFailedCount = [int]$desktopFailedCount
        mobilePassedCount = [int]$mobilePassedCount
        mobileFailedCount = [int]$mobileFailedCount
        screenshotCount = [int]$screenshotPaths.Count
        screenshotPaths = @($screenshotPaths.ToArray())
        firstViewportHeaderCount = [int]$firstViewportHeaderCount
        firstViewportStartHereCount = [int]$firstViewportStartHereCount
        toolCatalogPresenceCount = [int]$toolCatalogPresenceCount
        footerPresenceCount = [int]$footerPresenceCount
        blankViewportCount = [int]$blankViewportCount
        croppedElementCount = [int]$croppedElementCount
        overlapWarningCount = [int]$overlapWarningCount
        minimumRootClientWidth = $minimumRootClientWidthValue
        mobileRootClientWidth = $mobileRootClientWidth
        skipReason = if ([string]::IsNullOrWhiteSpace($skipReason)) { $null } else { $skipReason }
        warningCount = [int]$warnings.Count
        warnings = @($warnings.ToArray())
    }
}

function Read-RenderedProfileSmokeReport {
    param([string]$Path)

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return [ordered]@{
            path = $fullPath
            report = $null
        }
    }

    try {
        return [ordered]@{
            path = $fullPath
            report = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
        }
    } catch {
        return [ordered]@{
            path = $fullPath
            report = [ordered]@{
                generatedAt = (Get-Date).ToString("o")
                url = $null
                passed = $false
                skipped = $true
                skipReason = "Local rendered smoke artifact could not be read: $($_.Exception.Message)"
                viewports = @()
            }
        }
    }
}

function ConvertFrom-HexColor {
    param([string]$Hex)

    if ([string]::IsNullOrWhiteSpace($Hex)) { return $null }
    $value = $Hex.Trim().TrimStart('#')
    if ($value.Length -eq 3) {
        $value = [string]::Concat($value[0], $value[0], $value[1], $value[1], $value[2], $value[2])
    }
    if ($value.Length -ne 6 -or $value -notmatch '^[0-9a-fA-F]{6}$') { return $null }
    return [ordered]@{
        r = [Convert]::ToInt32($value.Substring(0, 2), 16)
        g = [Convert]::ToInt32($value.Substring(2, 2), 16)
        b = [Convert]::ToInt32($value.Substring(4, 2), 16)
    }
}

function Get-ColorRelativeLuminance {
    param([object]$Color)

    $channels = @($Color.r, $Color.g, $Color.b) | ForEach-Object {
        $c = [double]$_ / 255.0
        if ($c -le 0.03928) { $c / 12.92 } else { [Math]::Pow((($c + 0.055) / 1.055), 2.4) }
    }
    return (0.2126 * $channels[0]) + (0.7152 * $channels[1]) + (0.0722 * $channels[2])
}

function Get-ColorContrastRatio {
    param([object]$Foreground, [object]$Background)

    if ($null -eq $Foreground -or $null -eq $Background) { return $null }
    $l1 = Get-ColorRelativeLuminance -Color $Foreground
    $l2 = Get-ColorRelativeLuminance -Color $Background
    $lighter = [Math]::Max($l1, $l2)
    $darker = [Math]::Min($l1, $l2)
    return [Math]::Round((($lighter + 0.05) / ($darker + 0.05)), 2)
}

function Get-SvgContrastAnalysis {
    param(
        [string]$Name,
        [string]$Content,
        [double]$TextMinRatio = 4.5,
        [double]$NonTextMinRatio = 3.0
    )

    # Panel background = the largest numeric-area <rect> fill (the content panel
    # text actually sits on), ignoring full-canvas page backgrounds and thin
    # decorative accent stripes. Falls back to the last rect fill.
    $rectMatches = @([regex]::Matches($Content, '(?is)<rect\b[^>]*>'))
    $backgroundHex = $null
    $bestArea = -1.0
    foreach ($rect in $rectMatches) {
        $tag = $rect.Value
        $fillMatch = [regex]::Match($tag, '(?is)\bfill="(?<fill>#[0-9a-fA-F]{3,6})"')
        if (-not $fillMatch.Success) { continue }
        $widthMatch = [regex]::Match($tag, '(?is)\bwidth="(?<w>[0-9]+(?:\.[0-9]+)?)"')
        $heightMatch = [regex]::Match($tag, '(?is)\bheight="(?<h>[0-9]+(?:\.[0-9]+)?)"')
        if (-not $widthMatch.Success -or -not $heightMatch.Success) { continue }
        $area = [double]$widthMatch.Groups['w'].Value * [double]$heightMatch.Groups['h'].Value
        if ($area -gt $bestArea) {
            $bestArea = $area
            $backgroundHex = $fillMatch.Groups['fill'].Value
        }
    }
    if ([string]::IsNullOrWhiteSpace($backgroundHex)) {
        $rectFills = @($rectMatches | ForEach-Object { ([regex]::Match($_.Value, '(?is)\bfill="(?<fill>#[0-9a-fA-F]{3,6})"')).Groups['fill'].Value } | Where-Object { $_ })
        $backgroundHex = if ($rectFills.Count -gt 0) { $rectFills[$rectFills.Count - 1] } else { $null }
    }
    $background = ConvertFrom-HexColor $backgroundHex

    $textFills = @([regex]::Matches($Content, '(?is)<text\b[^>]*\bfill="(?<fill>#[0-9a-fA-F]{3,6})"') | ForEach-Object { $_.Groups['fill'].Value } | Sort-Object -Unique)

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($hex in $textFills) {
        $foreground = ConvertFrom-HexColor $hex
        $ratio = Get-ColorContrastRatio -Foreground $foreground -Background $background
        $rows.Add([ordered]@{
                foreground = [string]$hex
                ratio = $ratio
                meetsTextMin = [bool]($null -ne $ratio -and $ratio -ge $TextMinRatio)
                meetsNonTextMin = [bool]($null -ne $ratio -and $ratio -ge $NonTextMinRatio)
            })
    }

    $rowArray = @($rows.ToArray())
    $belowTextMin = @($rowArray | Where-Object { -not $_.meetsTextMin })
    $belowNonTextMin = @($rowArray | Where-Object { -not $_.meetsNonTextMin })
    $minRatio = if ($rowArray.Count -gt 0) { (@($rowArray | ForEach-Object { $_.ratio } | Where-Object { $null -ne $_ }) | Measure-Object -Minimum).Minimum } else { $null }

    return [ordered]@{
        asset = [string]$Name
        backgroundColor = if ([string]::IsNullOrWhiteSpace($backgroundHex)) { $null } else { [string]$backgroundHex }
        textColorCount = [int]$rowArray.Count
        minTextContrastRatio = $minRatio
        belowTextMinCount = [int]@($belowTextMin).Count
        belowNonTextMinCount = [int]@($belowNonTextMin).Count
        textColors = $rowArray
        pass = [bool](@($belowTextMin).Count -eq 0)
    }
}

function Test-ProfileAssetsAccessibility {
    <#
    .SYNOPSIS
    Checks generated profile SVG assets for minimum color contrast.
    .PARAMETER AssetDirectory
    Directory containing committed profile SVG assets.
    .PARAMETER AssetContents
    Optional map of asset names to SVG content used by tests.
    .PARAMETER TextMinRatio
    Minimum WCAG contrast ratio for SVG text.
    .PARAMETER NonTextMinRatio
    Minimum WCAG contrast ratio for non-text checks.
    #>
    [CmdletBinding()]
    param(
        [string]$AssetDirectory = (Join-Path $RepoRoot "assets/profile"),
        [AllowNull()][hashtable]$AssetContents,
        [double]$TextMinRatio = 4.5,
        [double]$NonTextMinRatio = 3.0
    )

    $assets = [ordered]@{}
    if ($null -ne $AssetContents) {
        foreach ($key in @($AssetContents.Keys | Sort-Object)) { $assets[$key] = [string]$AssetContents[$key] }
    } elseif (Test-Path -LiteralPath $AssetDirectory) {
        foreach ($file in @(Get-ChildItem -LiteralPath $AssetDirectory -Filter '*.svg' -File | Sort-Object Name)) {
            $assets[$file.Name] = Get-Content -LiteralPath $file.FullName -Raw
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($name in @($assets.Keys)) {
        $rows.Add((Get-SvgContrastAnalysis -Name $name -Content $assets[$name] -TextMinRatio $TextMinRatio -NonTextMinRatio $NonTextMinRatio))
    }

    $rowArray = @($rows.ToArray())
    $failingAssets = @($rowArray | Where-Object { -not $_.pass })
    $belowNonTextMin = @($rowArray | Where-Object { $_.belowNonTextMinCount -gt 0 })

    return [ordered]@{
        status = if (@($failingAssets).Count -eq 0) { "ok" } else { "warning" }
        textMinRatio = $TextMinRatio
        nonTextMinRatio = $NonTextMinRatio
        assetCount = [int]$rowArray.Count
        failingAssetCount = [int]@($failingAssets).Count
        belowNonTextMinAssetCount = [int]@($belowNonTextMin).Count
        warningCount = [int]@($failingAssets).Count
        contrastRatios = $rowArray
        note = "WCAG 2.1 contrast check of generated profile SVG <text> colors against the panel background (text min 4.5:1, non-text min 3:1). Warning-only."
    }
}
