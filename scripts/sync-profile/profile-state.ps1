# Test-ProfileState: runs every check against the expected and current artifacts,
# assembles reports/profile-sync-report.json, and decides the blocking failure
# conditions. Dot-sourced by scripts/sync-profile.ps1.

# Enforcement for every top-level report section, so a warning-only section reads as a
# decision rather than an omission. "blocking" names the failure condition in
# Test-ProfileState that fires for the section. "advisory-by-policy" is warning-only on
# purpose, for the reason given. "advisory-pending-decision" carries integrity signal that
# could reasonably fail a run; its reason is the question the owner still has to answer,
# and it is published in the report.
$script:ReportSectionEnforcement = [ordered]@{
    schema = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Run metadata: the schema this report conforms to.' }
    generatedAt = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Run metadata: when this report was written.' }
    readmeInSync = [ordered]@{ enforcement = 'blocking'; failureCondition = 'readmeInSync' }
    projectsExportInSync = [ordered]@{ enforcement = 'blocking'; failureCondition = 'projectsExportInSync' }
    profileAssetsInSync = [ordered]@{ enforcement = 'blocking'; failureCondition = 'profileAssetsInSync' }
    artifactDriftDiagnostics = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Explains the three sync gates; the gates decide.' }
    profileAssetChecks = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Per-file rows behind profileAssetsInSync, which is the gate.' }
    publicRepoCount = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Run metadata: public repositories seen.' }
    catalogEntryCount = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Run metadata: catalog rows read.' }
    includedReadmeCount = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Run metadata: rows rendered in the README.' }
    provenance = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Run metadata: source commit, input hashes and metadata provider.' }
    catalogShape = [ordered]@{ enforcement = 'blocking'; failureCondition = 'catalogShape' }
    metadataHygiene = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Topic and description guidance. The check never edits repositories; -ApplyTopics is a separate allowlisted step.' }
    projectLicenseMetadata = [ordered]@{ enforcement = 'advisory-pending-decision'; reason = 'Should a visitor-facing project with no recognizable license fail the run, or stay a review prompt?' }
    forkParentDrift = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'A catalog row may continue a fork, so attribution drift is listed for review rather than failed.' }
    staleProjectReview = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'A maintenance prompt: an old push date is not a defect in the profile.' }
    releaseAssetDrift = [ordered]@{ enforcement = 'advisory-pending-decision'; reason = 'Should a download label that no longer matches the latest release''s assets fail the run?' }
    branchTipProvenance = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Install snippets follow the branch head by design; tip SHAs are evidence, and a slow API must not fail the profile.' }
    backstageCatalogExport = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Status of an opt-in export that is off by default.' }
    releaseArtifactVerification = [ordered]@{ enforcement = 'blocking'; failureCondition = 'releaseArtifactVerification' }
    userscriptInstallTrust = [ordered]@{ enforcement = 'advisory-pending-decision'; reason = 'Should a userscript without @updateURL or @downloadURL, or with a broad @match, fail the run?' }
    catalogFeedAccounting = [ordered]@{ enforcement = 'blocking'; failureCondition = 'catalogFeedAccounting' }
    portfolioCompatibility = [ordered]@{ enforcement = 'blocking'; failureCondition = 'portfolioCompatibility' }
    portfolioCrossSurfaceProbe = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Opt-in probe of the deployed portfolio; external drift or an outage must not fail local validation.' }
    stableEntityIds = [ordered]@{ enforcement = 'blocking'; failureCondition = 'stableEntityIds' }
    feedSchemaMigration = [ordered]@{ enforcement = 'blocking'; failureCondition = 'feedSchemaMigration' }
    repositorySettings = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Account and plan-level settings such as branch protection and secret scanning are outside what a catalog change can fix.' }
    communityHealth = [ordered]@{ enforcement = 'blocking'; failureCondition = 'communityHealth' }
    schemaValidation = [ordered]@{ enforcement = 'blocking'; failureCondition = 'schemaValidation' }
    docVersionConsistency = [ordered]@{ enforcement = 'blocking'; failureCondition = 'docVersionConsistency' }
    profileReleaseConsistency = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Public releases are cut by hand at milestones (publicReleaseCadence in data/profile-version.json), so the internal version running ahead is expected.' }
    runtimeSecurity = [ordered]@{ enforcement = 'blocking'; failureCondition = 'runtimeSecurity' }
    validationPerformance = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Timing and cache telemetry.' }
    missingPublicRepos = [ordered]@{ enforcement = 'blocking'; failureCondition = 'missingPublic' }
    privateVisibilityViolations = [ordered]@{ enforcement = 'blocking'; failureCondition = 'privateViolations' }
    medicalPrivacyViolations = [ordered]@{ enforcement = 'blocking'; failureCondition = 'medicalViolations' }
    urlSchemeViolations = [ordered]@{ enforcement = 'blocking'; failureCondition = 'urlSchemeViolations' }
    orphanedSuppressedEntries = [ordered]@{ enforcement = 'blocking'; failureCondition = 'orphanedSuppressed' }
    renamedRepoRedirects = [ordered]@{ enforcement = 'blocking'; failureCondition = 'redirects' }
    metadataDrift = [ordered]@{ enforcement = 'blocking'; failureCondition = 'metadataDrift' }
    metadataDriftSummary = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Counts behind metadataDrift, which is the gate.' }
    linkValidationSkipped = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Records whether link probing ran; a skipped lane is announced, not failed.' }
    linkValidationSummary = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Link lane telemetry; dead links fail through linkValidationFailures.' }
    linkValidationFailures = [ordered]@{ enforcement = 'blocking'; failureCondition = 'linkFailures' }
    linkValidationWarnings = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Rate limits, 5xx responses and timeouts are transient and are retried next run instead of failing this one.' }
    readmeSizeBudget = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'A soft size limit is a prompt to trim, not a broken profile.' }
    readmeHeadingHierarchy = [ordered]@{ enforcement = 'advisory-pending-decision'; reason = 'Should a skipped heading level in the generated README fail the run like the other README experience checks?' }
    readmeDensity = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Soft category limits with a ready demotion list; a test also holds the committed README to them.' }
    artifactBudgets = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Soft byte and count budgets for generated artifacts.' }
    renderedProfileSmoke = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Evidence from a manual browser run, which cannot run on every check.' }
    evidenceFreshness = [ordered]@{ enforcement = 'advisory-pending-decision'; reason = 'Should report or smoke evidence older than the newest commit that affects it fail the run?' }
    roadmapHygiene = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'ROADMAP.md is local-only and absent from most checkouts.' }
    rootMarkdownHygiene = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'A documentation-contract reminder; stray root Markdown is gitignored and never published.' }
    profileAssetsAccessibility = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Contrast of generated SVGs. None are generated, and any stray file already fails profileAssetsInSync.' }
    readmeExperienceChecks = [ordered]@{ enforcement = 'blocking'; failureCondition = 'readmeExperience' }
    sectionEnforcement = [ordered]@{ enforcement = 'advisory-by-policy'; reason = 'Declares the enforcement of every section, itself included; an undeclared section fails the report schema instead.' }
}

function New-ReportSectionEnforcement {
    <#
    .SYNOPSIS
    Records the declared enforcement of each report section and the open decisions.
    .DESCRIPTION
    A section with no entry in $script:ReportSectionEnforcement is recorded as
    "undeclared", which the report schema rejects, so a new section fails the run
    until someone decides whether it can block.
    .PARAMETER Sections
    Top-level report section names, in report order.
    #>
    [CmdletBinding()]
    param([string[]]$Sections)

    $enforcementBySection = [ordered]@{}
    $pendingDecisions = [System.Collections.Generic.List[object]]::new()
    foreach ($section in @($Sections)) {
        $declaration = $script:ReportSectionEnforcement[$section]
        if ($null -eq $declaration) {
            $enforcementBySection[$section] = "undeclared"
            continue
        }
        $enforcementBySection[$section] = [string]$declaration.enforcement
        if ($declaration.enforcement -eq "advisory-pending-decision") {
            $pendingDecisions.Add([ordered]@{
                section = [string]$section
                question = [string]$declaration.reason
            })
        }
    }

    return [ordered]@{
        sections = $enforcementBySection
        pendingDecisions = $pendingDecisions.ToArray()
    }
}

function Test-ProfileState {
    <#
    .SYNOPSIS
    Runs the complete profile sync validation and builds the sync report.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER Repos
    Live or offline repository metadata used for generated output and reports.
    .PARAMETER ExpectedReadme
    README content expected from the current catalog and metadata.
    .PARAMETER ExpectedProjects
    projects.json content expected from the current catalog and metadata.
    .PARAMETER CurrentReadme
    Optional current README content; defaults to reading README.md.
    .PARAMETER CurrentProjects
    Optional current projects.json content; defaults to reading projects.json.
    .PARAMETER CurrentAssets
    Optional current SVG content keyed by path; defaults to reading committed assets.
    .PARAMETER ExpectedAssets
    Expected generated profile SVG content keyed by relative path.
    .PARAMETER SkipLinkValidation
    Skips outbound link probing while keeping the rest of the sync checks active.
    .PARAMETER SmokeReportPath
    Local rendered-profile smoke artifact to fold into reports/profile-sync-report.json.
    .PARAMETER VerifyReleaseArtifacts
    Enables the capped opt-in release artifact download and checksum pilot.
    .PARAMETER ReleaseVerificationMaxAssets
    Maximum number of release assets considered by the opt-in verification pilot.
    .PARAMETER ReleaseVerificationMaxBytes
    Maximum size of each release asset download in the opt-in verification pilot.
    .PARAMETER BackstageExport
    Optional in-memory Backstage export generated for an opt-in output path.
    .PARAMETER BackstageExportPath
    Optional output path used only as a public-safe filename in the sync report.
    .PARAMETER ProbePortfolio
    Enables the warning-only deployed portfolio feed and route probe.
    .PARAMETER PortfolioUrl
    HTTPS origin used by the optional deployed portfolio probe.
    .PARAMETER PortfolioProbeSnapshot
    Optional deterministic probe evidence used by tests instead of network calls.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [string]$ExpectedReadme,
        [string]$ExpectedProjects,
        [string]$CurrentReadme,
        [string]$CurrentProjects,
        [hashtable]$CurrentAssets,
        [hashtable]$ExpectedAssets = @{},
    [switch]$SkipLinkValidation,
    [switch]$VerifyReleaseArtifacts,
    [ValidateRange(1, 32)]
    [int]$ReleaseVerificationMaxAssets = $script:ReleaseVerificationMaxAssets,
    [ValidateRange(1024, 52428800)]
    [int]$ReleaseVerificationMaxBytes = $script:ReleaseVerificationMaxBytes,
    [object]$BackstageExport,
    [string]$BackstageExportPath,
    [switch]$ProbePortfolio,
    [string]$PortfolioUrl = "https://portfolio.getparkerai.com/",
    [object]$PortfolioProbeSnapshot,
    [string]$SmokeReportPath = $script:SmokeReportPath
    )

    # Normalize to a null-filtered array so .Count and enumeration stay safe under StrictMode
    # when the repo set is empty (e.g. offline runs bind $Repos to $null).
    $Repos = @($Repos | Where-Object { $null -ne $_ })
    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries)
    $catalogShape = Test-CatalogShape -Catalog $Catalog
    $included = @($entries | Where-Object { $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })
    $orphanedSuppressed = @($entries | Where-Object {
        $_.category -eq 'suppressed' -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
    } | ForEach-Object { [ordered]@{ repo = [string]$_.repo; reason = "category is 'suppressed' but suppressionReason is missing" } })
    $handledNames = @{}
    foreach ($entry in $entries) {
        $handledNames[$entry.repo.ToLowerInvariant()] = $true
        if ($entry.aliasOf) {
            $handledNames[([string]$entry.aliasOf).ToLowerInvariant()] = $true
        }
    }

    $missingPublic = @()
    foreach ($repo in $Repos) {
        if ($repo.name -eq $Owner) {
            continue
        }
        if (-not $handledNames.ContainsKey($repo.name.ToLowerInvariant())) {
            $stub = New-CatalogEntryStub -Repo $repo
            $missingPublic += [ordered]@{
                repo = $repo.name
                description = $repo.description
                language = if ($repo.primaryLanguage) { $repo.primaryLanguage.name } else { $null }
                # Paste-ready fragment so cataloging a new public repo is a review, not
                # a 22-field transcription from the API.
                catalogEntryStub = $stub.entry
                unresolvedFields = @($stub.unresolvedFields)
            }
        }
    }

    $privateViolations = @()
    $medicalViolations = @()
    $redirects = @()
    foreach ($entry in $included) {
        $meta = Get-RepoMeta $entry $repoLookup
        if (-not $meta) {
            if (-not $script:Offline) {
                $view = $null
                $entryRepo = [string]$entry.repo
                if (Test-SafeGitHubName -Name $entryRepo) {
                    $gh = Invoke-GhCli -Arguments @("repo", "view", "$Owner/$entryRepo", "--json", "name,url,visibility")
                    if ($gh.exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($gh.text)) {
                        try {
                            $view = $gh.text | ConvertFrom-Json
                        } catch {
                            $view = $null
                        }
                    }
                }
                if ($view -and $view.name -ne $entry.repo) {
                    $redirects += [ordered]@{
                        repo = $entry.repo
                        canonical = $view.name
                        url = $view.url
                    }
                } else {
                    $privateViolations += [ordered]@{
                        repo = $entry.repo
                        reason = "not returned by public active repo list"
                    }
                }
            }
            continue
        }

        if ($meta.visibility -ne "PUBLIC" -or $meta.isPrivate) {
            $privateViolations += [ordered]@{
                repo = $entry.repo
                visibility = $meta.visibility
            }
        }

        $topicText = if ($meta.repositoryTopics) { ($meta.repositoryTopics.name -join " ") } else { "" }
        $medicalText = "$($entry.repo) $($meta.description) $topicText"
        # CultureInvariant: under tr-TR the (?i) match of 'DICOM' against 'dicom' fails, which
        # would publish a medical-imaging repository the gate exists to keep private.
        if ([regex]::IsMatch($medicalText, $MedicalPattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant) -and $entry.allowPublicMedical -ne $true) {
            $medicalViolations += [ordered]@{
                repo = $entry.repo
                reason = "medical-imaging keyword requires explicit allowPublicMedical"
            }
        }
    }

    $readmeReadPath = if ([System.IO.Path]::IsPathRooted($ReadmePath)) { $ReadmePath } else { Join-Path $RepoRoot $ReadmePath }
    $projectsReadPath = if ([System.IO.Path]::IsPathRooted($ProjectsPath)) { $ProjectsPath } else { Join-Path $RepoRoot $ProjectsPath }
    $currentReadme = if ($PSBoundParameters.ContainsKey("CurrentReadme")) {
        $CurrentReadme
    } else {
        Get-Content -LiteralPath $readmeReadPath -Raw
    }
    $currentProjects = if ($PSBoundParameters.ContainsKey("CurrentProjects")) {
        $CurrentProjects
    } elseif (Test-Path -LiteralPath $projectsReadPath) {
        Get-Content -LiteralPath $projectsReadPath -Raw
    } else {
        ""
    }
    # -ceq, not -eq: PowerShell string comparison is case-insensitive by default, and
    # these three comparisons are the whole verdict for their artifacts. With -eq a
    # renamed repo, a rewritten title or a changed URL path segment that differed only
    # in letter case reported as in sync.
    $readmeInSync = (ConvertTo-NormalizedGeneratedText -Text $currentReadme) -ceq (ConvertTo-NormalizedGeneratedText -Text $ExpectedReadme)
    $projectsComparableInSync = (ConvertTo-ProjectsSyncComparableJson -Json $currentProjects) -ceq (ConvertTo-ProjectsSyncComparableJson -Json $ExpectedProjects)
    $metadataDriftResult = Test-MetadataDrift -CurrentProjectsJson $currentProjects -ExpectedProjectsJson $ExpectedProjects
    # The canonical comparison is the whole verdict. Tolerance for live upstream churn
    # lives inside ConvertTo-ProjectsSyncComparableJson as an explicit mask; it must not
    # be reintroduced here as a second, weaker predicate. An -or against the drift model
    # made the gate pass for every field that model does not enumerate.
    $projectsInSync = $projectsComparableInSync
    $currentAssetSet = if ($PSBoundParameters.ContainsKey('CurrentAssets')) { $CurrentAssets } else { Get-ProfileAssetFileContents }
    $assetChecks = New-Object System.Collections.Generic.List[object]
    foreach ($assetPath in @($ExpectedAssets.Keys | Sort-Object)) {
        $exists = $currentAssetSet.ContainsKey($assetPath)
        $assetInSync = $exists -and ((ConvertTo-NormalizedGeneratedText -Text ([string]$currentAssetSet[$assetPath])) -ceq (ConvertTo-NormalizedGeneratedText -Text ([string]$ExpectedAssets[$assetPath])))
        $assetChecks.Add([ordered]@{
            path = [string]$assetPath
            exists = [bool]$exists
            inSync = [bool]$assetInSync
        })
    }
    # A file under -AssetsPath that the generator does not produce is drift too. Nothing
    # regenerates, budgets or contrast-checks it, and -Write never deletes, so without this
    # row a stray or restored SVG would sit in the published tree with the gate green.
    foreach ($assetPath in @($currentAssetSet.Keys | Where-Object { -not $ExpectedAssets.ContainsKey([string]$_) } | Sort-Object)) {
        $assetChecks.Add([ordered]@{
            path = [string]$assetPath
            exists = $true
            inSync = $false
        })
    }
    $assetsInSync = @($assetChecks | Where-Object { $_.inSync -ne $true }).Count -eq 0
    $artifactDriftDiagnostics = New-GeneratedArtifactDriftDiagnostics `
        -CurrentReadme $currentReadme `
        -ExpectedReadme $ExpectedReadme `
        -CurrentProjects $currentProjects `
        -ExpectedProjects $ExpectedProjects `
        -ReadmeInSync:$readmeInSync `
        -ProjectsInSync:$projectsInSync `
        -ProfileAssetsInSync:$assetsInSync `
        -AssetChecks $assetChecks.ToArray() `
        -ExpectedAssets $ExpectedAssets `
        -CurrentAssets $currentAssetSet

    $linkFailures = @()
    $linkWarnings = @()
    # Local fragments need no network, so they are checked even when link probing is
    # skipped or offline: a call to action pointing at a section that no longer exists
    # is broken for every visitor regardless of connectivity.
    $missingHeaderAnchors = @(Test-ReadmeHeaderAnchor -ExpectedReadme $ExpectedReadme)
    foreach ($anchor in $missingHeaderAnchors) {
        # Same shape as a probe failure row (schema: linkValidationRow). Every row in this list
        # is fatal, so the extra group/fatal fields the anchor rows used to carry made the
        # report fail its own schema on top of failing linkFailures.
        $linkFailures += [ordered]@{
            repo = $Owner
            type = "readme-header-anchor"
            url = "#$($anchor.fragment)"
            host = $null
            status = $null
            error = [string]$anchor.reason
        }
    }
    # A bare targetCount of 0 reads like "probed everything, found nothing wrong". Record the
    # skip explicitly so a skipped run is never mistaken for a clean one.
    $linkValidationSkipReason = if ($script:Offline) {
        "offline mode"
    } elseif ($SkipLinkValidation) {
        "-SkipLinkValidation"
    } else {
        $null
    }
    $linkValidationSummary = [ordered]@{
        skipped = [bool]($script:Offline -or $SkipLinkValidation)
        skipReason = $linkValidationSkipReason
        targetCount = 0
        liveProbedCount = 0
        cacheServedCount = 0
        oldestCacheEntryAgeHours = $null
        allResultsFromCache = $false
        throttleLimit = $LinkValidationThrottle
        elapsedMs = 0
        readmeActionTargetCount = 0
        readmeInstallSnippetTargetCount = 0
        readmeDownloadLinkTargetCount = 0
        readmeUserscriptInstallTargetCount = 0
        warningCountByHost = @()
        headerHostWarnings = @()
        deferredRetries = @()
    }
    if (-not $script:Offline -and -not $SkipLinkValidation) {
        $readmeHeaderTargets = @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $ExpectedReadme)
        $readmeActionTargets = @(Get-ReadmeActionLinkValidationTargets -ExpectedReadme $ExpectedReadme -Entries $included -RepoLookup $repoLookup)
        $linkResult = Test-LinkTargets -Included $included -RepoLookup $repoLookup -ExtraTargets @($readmeHeaderTargets + $readmeActionTargets)
        $linkFailures = @($linkFailures + @($linkResult.failures))
        $linkWarnings = @($linkResult.warnings)
        $linkValidationSummary = [ordered]@{
            skipped = $false
            skipReason = $null
            targetCount = $linkResult.targetCount
            liveProbedCount = [int]$linkResult.liveProbedCount
            cacheServedCount = [int]$linkResult.cacheServedCount
            oldestCacheEntryAgeHours = $linkResult.oldestCacheEntryAgeHours
            allResultsFromCache = [bool]$linkResult.allResultsFromCache
            throttleLimit = $linkResult.throttleLimit
            elapsedMs = $linkResult.elapsedMs
            readmeActionTargetCount = @($readmeActionTargets).Count
            readmeInstallSnippetTargetCount = @($readmeActionTargets | Where-Object { $_.type -eq "readme-install-entrypoint" }).Count
            readmeDownloadLinkTargetCount = @($readmeActionTargets | Where-Object { $_.type -eq "readme-download" }).Count
            readmeUserscriptInstallTargetCount = @($readmeActionTargets | Where-Object { $_.type -eq "readme-userscript-install" }).Count
            warningCountByHost = @($linkResult.warningCountByHost)
            headerHostWarnings = @($linkResult.headerHostWarnings)
            deferredRetries = @($linkResult.deferredRetries)
        }
    }

    $urlSchemeViolations = @(Test-CatalogUrlSchemes -Entries $included)
    $experienceChecks = Test-ReadmeExperience -Catalog $Catalog -Repos $Repos -ExpectedReadme $ExpectedReadme
    $readmeSizeBudget = Test-ReadmeSizeBudget -ExpectedReadme $ExpectedReadme
    $readmeHeadingHierarchy = Test-ReadmeHeadingHierarchy -ExpectedReadme $ExpectedReadme
    $readmeDensity = Test-ReadmeDensity -ExpectedReadme $ExpectedReadme -Entries $included -RepoLookup $repoLookup
    $artifactBudgets = Test-GeneratedArtifactBudgets -ExpectedReadme $ExpectedReadme -ExpectedProjectsJson $ExpectedProjects -ExpectedAssets $ExpectedAssets -ReportJson $null
    $smokeArtifact = Read-RenderedProfileSmokeReport -Path $SmokeReportPath
    $renderedProfileSmoke = New-RenderedProfileSmokeSummary -SmokeReport $smokeArtifact.report -SourcePath $smokeArtifact.path
    $committedReportForFreshness = $null
    $committedReportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $RepoRoot $ReportPath }
    if (Test-Path -LiteralPath $committedReportFullPath) {
        try {
            $committedReportForFreshness = Get-Content -LiteralPath $committedReportFullPath -Raw | ConvertFrom-Json
        } catch {
            $committedReportForFreshness = $null
        }
    }
    $latestReportCommit = Get-LatestReportAffectingCommit
    $latestSmokeCommit = Get-LatestReportAffectingCommit -Paths $SmokeAffectingPaths
    $evidenceFreshness = Test-ReportEvidenceFreshness -CommittedReport $committedReportForFreshness -LatestCommitDate $latestReportCommit.date -LatestCommitSha $latestReportCommit.sha -SmokeAffectingCommitDate $latestSmokeCommit.date
    $roadmapHygiene = Test-RoadmapHygiene
    $rootMarkdownHygiene = Test-RootMarkdownHygiene
    $profileAssetContents = @{}
    foreach ($assetPath in @($currentAssetSet.Keys)) {
        $assetName = [System.IO.Path]::GetFileName([string]$assetPath)
        if ($assetName.EndsWith('.svg', [StringComparison]::OrdinalIgnoreCase)) {
            $profileAssetContents[$assetName] = [string]$currentAssetSet[$assetPath]
        }
    }
    $profileAssetsAccessibility = Test-ProfileAssetsAccessibility -AssetContents $profileAssetContents
    $metadataHygiene = Test-MetadataHygiene -Repos $Repos -CatalogEntries $entries
    $projectLicenseMetadata = Test-ProjectLicenseMetadata -Entries $included -RepoLookup $repoLookup
    $forkParentDrift = Test-ForkParentDrift -Repos $Repos -CatalogEntries $entries
    $staleProjectReview = Test-StaleProjectReview -Entries $entries -RepoLookup $repoLookup
    $releaseAssetDrift = Test-ReleaseAssetDrift -Entries $included -RepoLookup $repoLookup
    $branchTipProvenance = Test-BranchTipProvenance -Entries $included -RepoLookup $repoLookup
    $backstageCatalogExport = if ($null -eq $BackstageExport) {
        [ordered]@{
            enabled = $false
            status = "disabled"
            outputPath = $null
            schemaVersion = "sysadmindoc-backstage-catalog.v1"
            componentCount = 0
            suppressedCount = 0
            privateSkippedCount = 0
            missingMetadataCount = 0
            redactionSafe = $true
            note = "Opt-in only: pass -BackstageExportPath to emit public-safe Backstage Component descriptors."
        }
    } else {
        $summary = $BackstageExport.summary
        $outputName = if ([string]::IsNullOrWhiteSpace([string]$BackstageExportPath)) { $null } else { [System.IO.Path]::GetFileName([string]$BackstageExportPath) }
        [ordered]@{
            enabled = $true
            status = "generated"
            outputPath = $outputName
            schemaVersion = [string]$summary.schemaVersion
            componentCount = [int]$summary.componentCount
            suppressedCount = [int]$summary.suppressedCount
            privateSkippedCount = [int]$summary.privateSkippedCount
            missingMetadataCount = [int]$summary.missingMetadataCount
            redactionSafe = [bool]$summary.redactionSafe
            note = [string]$summary.note
        }
    }
    $releaseArtifactVerification = Test-ReleaseArtifactVerification `
        -Entries $included `
        -RepoLookup $repoLookup `
        -Enabled:$VerifyReleaseArtifacts `
        -MaxAssets $ReleaseVerificationMaxAssets `
        -MaxBytes $ReleaseVerificationMaxBytes
    $userscriptInstallTrust = Test-UserscriptInstallTrust -Entries $included -Skip:($script:Offline -or $SkipLinkValidation)
    $catalogFeedAccounting = Test-CatalogFeedAccounting -Catalog $Catalog -ProjectsJson $ExpectedProjects
    $portfolioCompatibility = Test-PortfolioFeedCompatibility -ProjectsJson $ExpectedProjects
    $portfolioCrossSurfaceProbe = Test-PortfolioCrossSurfaceDrift `
        -ProjectsJson $ExpectedProjects `
        -Enabled:$ProbePortfolio `
        -PortfolioUrl $PortfolioUrl `
        -Snapshot $PortfolioProbeSnapshot
    $stableEntityIds = Test-StableProjectEntityIds -ProjectsJson $ExpectedProjects
    $feedSchemaMigration = Test-FeedSchemaMigrationPolicy -ProjectsJson $ExpectedProjects
    $feedSchemaValidation = Test-FeedSchemaContracts -Catalog $Catalog -ProjectsJson $ExpectedProjects
    $repositoryCommunityBaseline = Get-RepositoryCommunityBaseline
    $schemaValidation = [ordered]@{
        passed = [bool]$feedSchemaValidation.passed
        catalog = $feedSchemaValidation.catalog
        projects = $feedSchemaValidation.projects
        report = [ordered]@{
            schemaPath = "schemas/profile-sync-report.v1.json"
            schemaId = $ReportSchemaUrl
            valid = $true
            errors = @()
            unsupportedKeywords = @()
        }
    }
    $docVersionConsistency = Test-DocVersionConsistency
    $profileReleaseConsistency = Test-ProfileReleaseConsistency `
        -Repos $Repos `
        -DocVersionConsistency $docVersionConsistency `
        -TagRef (Get-ProfileRepositoryTagRef -TagName ([string]$docVersionConsistency.expectedVersion))
    $runtimeSecurity = Test-PowerShellRuntimeSecurity
    $reportGeneratedAt = (Get-Date).ToString("o")
    $feedProvenance = $null
    try {
        $expectedProjectsPayload = ConvertFrom-JsonPreservingArrays -Json $ExpectedProjects
        $feedProvenance = Get-MemberValue -Object $expectedProjectsPayload -Name "provenance"
    } catch {
        $feedProvenance = $null
    }
    $validationPerformance = [ordered]@{
        metadataFetch = [ordered]@{
            provider = [string]$script:RepositoryMetadataProvider
            graphQlPageSize = [int]$script:GraphQlPageSize
            requestCount = [int]$script:MetadataFetchRequestCount
            attemptCount = [int]$script:MetadataFetchAttemptCount
            retryCount = [Math]::Max(0, ([int]$script:MetadataFetchAttemptCount - 1))
            fallbackUsed = [bool]($script:RepositoryMetadataProvider -eq "rest-fallback" -or $script:RepositoryMetadataProvider -eq "offline-empty" -or ([string]$script:RepositoryMetadataProvider).StartsWith("cache", [StringComparison]::OrdinalIgnoreCase))
            fallbackReason = if ([string]::IsNullOrWhiteSpace($script:MetadataFetchFallbackReason)) { $null } else { [string]$script:MetadataFetchFallbackReason }
            resourceLimitFallback = [bool]$script:MetadataFetchResourceLimitFallback
            resourceLimitFallbackReason = if ([string]::IsNullOrWhiteSpace($script:MetadataFetchResourceLimitReason)) { $null } else { [string]$script:MetadataFetchResourceLimitReason }
            pageSizeReduced = [bool]$script:MetadataFetchPageSizeReduced
            effectivePageSize = [int]$script:RepositoryEnumerationRequestedLimit
            repoCount = [int]$Repos.Count
            truncated = [bool]$script:RepositoryEnumerationTruncated
            fidelityDegraded = [bool]($script:RepositoryEnumerationTruncated -or $script:RepositoryMetadataProvider -eq "rest-fallback" -or $script:RepositoryMetadataProvider -eq "offline-empty" -or ([string]$script:RepositoryMetadataProvider).StartsWith("cache", [StringComparison]::OrdinalIgnoreCase))
        }
        linkValidation = [ordered]@{
            skipped = [bool]($script:Offline -or $SkipLinkValidation)
            targetCount = $linkValidationSummary.targetCount
            throttleLimit = $linkValidationSummary.throttleLimit
            elapsedMs = $linkValidationSummary.elapsedMs
            failureCount = @($linkFailures).Count
            warningCount = @($linkWarnings).Count
            warningHostCount = @($linkValidationSummary.warningCountByHost).Count
            headerWarningHostCount = @($linkValidationSummary.headerHostWarnings).Count
        }
        restFallbackReleaseFetch = Get-RestFallbackReleaseFetchState
        cache = Get-ValidationCacheState
    }
    $report = [ordered]@{
        schema = $ReportSchemaUrl
        generatedAt = $reportGeneratedAt
        readmeInSync = $readmeInSync
        projectsExportInSync = $projectsInSync
        profileAssetsInSync = $assetsInSync
        artifactDriftDiagnostics = $artifactDriftDiagnostics
        profileAssetChecks = $assetChecks.ToArray()
        publicRepoCount = $Repos.Count
        catalogEntryCount = $entries.Count
        includedReadmeCount = $included.Count
        provenance = $feedProvenance
        catalogShape = $catalogShape
        metadataHygiene = $metadataHygiene
        projectLicenseMetadata = $projectLicenseMetadata
        forkParentDrift = $forkParentDrift
        staleProjectReview = $staleProjectReview
        releaseAssetDrift = $releaseAssetDrift
        branchTipProvenance = $branchTipProvenance
        backstageCatalogExport = $backstageCatalogExport
        releaseArtifactVerification = $releaseArtifactVerification
        userscriptInstallTrust = $userscriptInstallTrust
        catalogFeedAccounting = $catalogFeedAccounting
        portfolioCompatibility = $portfolioCompatibility
        portfolioCrossSurfaceProbe = $portfolioCrossSurfaceProbe
        stableEntityIds = $stableEntityIds
        feedSchemaMigration = $feedSchemaMigration
        repositorySettings = $repositoryCommunityBaseline["repositorySettings"]
        communityHealth = $repositoryCommunityBaseline["communityHealth"]
        schemaValidation = $schemaValidation
        docVersionConsistency = $docVersionConsistency
        profileReleaseConsistency = $profileReleaseConsistency
        runtimeSecurity = $runtimeSecurity
        validationPerformance = $validationPerformance
        missingPublicRepos = $missingPublic
        privateVisibilityViolations = $privateViolations
        medicalPrivacyViolations = $medicalViolations
        urlSchemeViolations = $urlSchemeViolations
        orphanedSuppressedEntries = $orphanedSuppressed
        renamedRepoRedirects = $redirects
        metadataDrift = @($metadataDriftResult.metadataDrift)
        metadataDriftSummary = [ordered]@{
            fatalCount = $metadataDriftResult.fatalCount
            informationalCount = $metadataDriftResult.informationalCount
            generatedAt = $metadataDriftResult.generatedAt
        }
        linkValidationSkipped = [bool]($script:Offline -or $SkipLinkValidation)
        linkValidationSummary = $linkValidationSummary
        linkValidationFailures = @($linkFailures)
        linkValidationWarnings = @($linkWarnings)
        readmeSizeBudget = $readmeSizeBudget
        readmeHeadingHierarchy = $readmeHeadingHierarchy
        readmeDensity = $readmeDensity
        artifactBudgets = $artifactBudgets
        renderedProfileSmoke = $renderedProfileSmoke
        evidenceFreshness = $evidenceFreshness
        roadmapHygiene = $roadmapHygiene
        rootMarkdownHygiene = $rootMarkdownHygiene
        profileAssetsAccessibility = $profileAssetsAccessibility
        readmeExperienceChecks = $experienceChecks
    }
    # Listed before it exists, so the declaration block covers itself too.
    $report.sectionEnforcement = New-ReportSectionEnforcement -Sections (@($report.Keys) + 'sectionEnforcement')
    # Compact report sections to keep the committed JSON below the 70 % soft-limit.
    # The live PS objects are still fully populated for downstream use within this
    # function; only the serialised report copy is stripped here.

    # 1. prDeliveryTransition: replace per-evidence detail objects and the items
    #    checklist array with compact status strings / counts.
    $prTransitionRef = $null
    try {
        $prTransitionRef = $report["repositorySettings"]["requiredCheckReadiness"]["prDeliveryTransition"]
    } catch {
        $prTransitionRef = $null
    }
    if ($prTransitionRef -is [System.Collections.IDictionary]) {
        $detailKeys = @(
            'generatedPrDryRunEvidence', 'generatedPrWriteEvidence', 'directMainMaintenancePolicy',
            'candidateCheckExercisePlan', 'candidateCheckExerciseEvidence',
            'routineMaintenancePrDrillEvidence', 'requiredCheckEnforcementEvidence', 'items'
        )
        foreach ($dk in $detailKeys) {
            if ($prTransitionRef.Contains($dk)) {
                $detail = $prTransitionRef[$dk]
                # Replace detail objects and arrays with compact summaries.
                # The items count is preserved as a nonNegativeInteger.
                # generatedPrWriteEvidence is kept as a minimal stub so that
                # write-profile-sync-summary.ps1 can still read statusHandoffContext
                # for the CI step summary (tested by the summary test suite).
                $prTransitionRef[$dk] = if ($dk -eq 'items' -and $null -ne $detail -and $detail.GetType().IsArray) {
                    [int]($detail | Measure-Object).Count
                } elseif ($dk -eq 'generatedPrWriteEvidence' -and $detail -is [System.Collections.IDictionary]) {
                    # Keep a stub with all fields that write-profile-sync-summary.ps1 reads under
                    # Set-StrictMode -Version Latest (missing props throw); only statusHandoffContext
                    # needs its real value — the rest default to null so guards short-circuit.
                    [ordered]@{
                        available                           = $null
                        conclusion                          = $null
                        failedStep                          = $null
                        generatedBranchCleanup              = $null
                        runUrl                              = $null
                        pullRequestNumber                   = $null
                        pullRequestState                    = $null
                        validationDispatched                = $null
                        validationConclusion                = $null
                        validationFailedStep                = $null
                        validationRunUrl                    = $null
                        generatedBranchCheckRunCount        = $null
                        generatedBranchSuccessfulCheckRunCount = $null
                        pullRequestCheckRollupCount         = $null
                        pullRequestChecksAttached           = $null
                        statusHandoffImplemented            = $null
                        statusHandoffContext                 = [string](Get-MemberValue -Object $detail -Name 'statusHandoffContext')
                        statusHandoffProof                  = $null
                        statusHandoffState                  = $null
                        statusHandoffPermission             = $null
                    }
                } else {
                    $null
                }
            }
        }
    }

    # 2. executableDownloadsMissingChecksums: replace the per-repo row array with
    #    just the count.
    $releaseAssetDriftRef = $report["releaseAssetDrift"]
    if ($releaseAssetDriftRef -is [System.Collections.IDictionary] -and
        $releaseAssetDriftRef.Contains('executableDownloadsMissingChecksums')) {
        $checksumArray = $releaseAssetDriftRef['executableDownloadsMissingChecksums']
        $releaseAssetDriftRef['executableDownloadsMissingChecksums'] = if ($null -ne $checksumArray -and $checksumArray.GetType().IsArray) {
            [int]($checksumArray | Measure-Object).Count
        } else {
            [int]0
        }
    }
    for ($artifactBudgetPass = 0; $artifactBudgetPass -lt 2; $artifactBudgetPass++) {
        $draftReportJson = $report | ConvertTo-Json -Depth 30
        $report.artifactBudgets = Test-GeneratedArtifactBudgets -ExpectedReadme $ExpectedReadme -ExpectedProjectsJson $ExpectedProjects -ExpectedAssets $ExpectedAssets -ReportJson $draftReportJson
    }
    $reportSchemaValidation = Test-JsonSchemaContract -Value $report -SchemaPath $ReportSchemaPath
    $schemaValidation = [ordered]@{
        passed = [bool]($feedSchemaValidation.passed -and $reportSchemaValidation.valid)
        catalog = $feedSchemaValidation.catalog
        projects = $feedSchemaValidation.projects
        report = $reportSchemaValidation
    }
    $report.schemaValidation = $schemaValidation

    $failureConditions = [ordered]@{
        readmeInSync = [bool](-not $readmeInSync)
        projectsExportInSync = [bool](-not $projectsInSync)
        profileAssetsInSync = [bool](-not $assetsInSync)
        catalogShape = [bool]($catalogShape.passed -ne $true)
        metadataDrift = [bool]($metadataDriftResult.fatalCount -gt 0)
        missingPublic = [bool](@($missingPublic | Where-Object { $null -ne $_ }).Count -gt 0)
        privateViolations = [bool](@($privateViolations | Where-Object { $null -ne $_ }).Count -gt 0)
        medicalViolations = [bool](@($medicalViolations | Where-Object { $null -ne $_ }).Count -gt 0)
        urlSchemeViolations = [bool](@($urlSchemeViolations | Where-Object { $null -ne $_ }).Count -gt 0)
        orphanedSuppressed = [bool](@($orphanedSuppressed | Where-Object { $null -ne $_ }).Count -gt 0)
        redirects = [bool](@($redirects | Where-Object { $null -ne $_ }).Count -gt 0)
        linkFailures = [bool](@($linkFailures | Where-Object { $null -ne $_ }).Count -gt 0)
        readmeExperience = [bool]($experienceChecks["passed"] -ne $true)
        communityHealth = [bool]($repositoryCommunityBaseline["communityHealth"]["fatalCount"] -gt 0)
        catalogFeedAccounting = [bool]($catalogFeedAccounting.fatalCount -gt 0)
        portfolioCompatibility = [bool]($portfolioCompatibility.fatalCount -gt 0)
        stableEntityIds = [bool]($stableEntityIds.fatalCount -gt 0)
        feedSchemaMigration = [bool]($feedSchemaMigration.fatalCount -gt 0)
        schemaValidation = [bool]($schemaValidation.passed -ne $true)
        docVersionConsistency = [bool]($docVersionConsistency.passed -ne $true)
        runtimeSecurity = [bool]($runtimeSecurity.status -eq "fail")
        releaseArtifactVerification = [bool]($VerifyReleaseArtifacts -and $releaseArtifactVerification.failureCount -gt 0)
    }
    $failed = $failureConditions.Values -contains $true
    return [ordered]@{
        Failed = $failed
        FailureConditions = $failureConditions
        Report = $report
    }
}
