#Requires -Version 7.0
param(
    [string]$ReportPath = "reports/profile-sync-report.json",
    [string]$SummaryPath = $env:GITHUB_STEP_SUMMARY,
    [string]$Context = "Profile sync",
    [switch]$AllowMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Count {
    param([object]$Value)

    if ($null -eq $Value) {
        return 0
    }

    return @($Value).Count
}

if (-not (Test-Path -LiteralPath $ReportPath)) {
    $message = "Profile sync report not found at $ReportPath."
    Write-Output "::warning::$message"
    if ($AllowMissing) {
        if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
            "### $Context report`n`n$message" | Out-File -FilePath $SummaryPath -Encoding utf8 -Append
        }
        exit 0
    }
    throw $message
}

$report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json

$metadataHygiene = $report.metadataHygiene
$projectLicenseMetadata = if ($report.PSObject.Properties.Name -contains 'projectLicenseMetadata') { $report.projectLicenseMetadata } else { $null }
$forkParentDrift = if ($report.PSObject.Properties.Name -contains 'forkParentDrift') { $report.forkParentDrift } else { $null }
$staleProjectReview = if ($report.PSObject.Properties.Name -contains 'staleProjectReview') { $report.staleProjectReview } else { $null }
$releaseDrift = $report.releaseAssetDrift
$linkSummary = $report.linkValidationSummary
$driftSummary = $report.metadataDriftSummary
$performance = $report.validationPerformance
$repositorySettings = $report.repositorySettings
$actionsWorkflowPermissions = if ($repositorySettings -and $repositorySettings.PSObject.Properties.Name -contains 'actionsWorkflowPermissions') { $repositorySettings.actionsWorkflowPermissions } else { $null }
$generatedPrCredentialDecision = if ($actionsWorkflowPermissions -and $actionsWorkflowPermissions.PSObject.Properties.Name -contains 'generatedPrCredentialDecision') { $actionsWorkflowPermissions.generatedPrCredentialDecision } else { $null }
$requiredCheckReadiness = if ($repositorySettings -and $repositorySettings.PSObject.Properties.Name -contains 'requiredCheckReadiness') { $repositorySettings.requiredCheckReadiness } else { $null }
$prDeliveryTransition = if ($requiredCheckReadiness -and $requiredCheckReadiness.PSObject.Properties.Name -contains 'prDeliveryTransition') { $requiredCheckReadiness.prDeliveryTransition } else { $null }
$generatedPrDryRunEvidence = if ($prDeliveryTransition -and $prDeliveryTransition.PSObject.Properties.Name -contains 'generatedPrDryRunEvidence') { $prDeliveryTransition.generatedPrDryRunEvidence } else { $null }
$generatedPrWriteEvidence = if ($prDeliveryTransition -and $prDeliveryTransition.PSObject.Properties.Name -contains 'generatedPrWriteEvidence') { $prDeliveryTransition.generatedPrWriteEvidence } else { $null }
$communityHealth = $report.communityHealth
$profileReleaseConsistency = if ($report.PSObject.Properties.Name -contains 'profileReleaseConsistency') { $report.profileReleaseConsistency } else { $null }
$userscriptInstallTrust = if ($report.PSObject.Properties.Name -contains 'userscriptInstallTrust') { $report.userscriptInstallTrust } else { $null }
$catalogFeedAccounting = if ($report.PSObject.Properties.Name -contains 'catalogFeedAccounting') { $report.catalogFeedAccounting } else { $null }
$portfolioCompatibility = if ($report.PSObject.Properties.Name -contains 'portfolioCompatibility') { $report.portfolioCompatibility } else { $null }
$readmeDensity = if ($report.PSObject.Properties.Name -contains 'readmeDensity') { $report.readmeDensity } else { $null }
$artifactBudgets = if ($report.PSObject.Properties.Name -contains 'artifactBudgets') { $report.artifactBudgets } else { $null }
$renderedProfileSmoke = if ($report.PSObject.Properties.Name -contains 'renderedProfileSmoke') { $report.renderedProfileSmoke } else { $null }
$restFallbackReleaseFetch = if ($performance -and $performance.PSObject.Properties.Name -contains 'restFallbackReleaseFetch') { $performance.restFallbackReleaseFetch } else { $null }

$missingTopicCount = Get-Count ($metadataHygiene ? $metadataHygiene.missingTopics : $null)
$missingDescriptionCount = Get-Count ($metadataHygiene ? $metadataHygiene.missingDescriptions : $null)
$missingLicenseCount = if ($projectLicenseMetadata) { [int]$projectLicenseMetadata.missingCount } else { 0 }
$unknownLicenseCount = if ($projectLicenseMetadata) { [int]$projectLicenseMetadata.unknownCount } else { 0 }
$forkParentWarningCount = if ($forkParentDrift) { [int]$forkParentDrift.warningCount } else { 0 }
$staleProjectWarningCount = if ($staleProjectReview) { [int]$staleProjectReview.warningCount } else { 0 }
$archiveReviewCount = if ($staleProjectReview) { [int]$staleProjectReview.archiveReviewCount } else { 0 }
$fatalDriftCount = if ($driftSummary) { [int]$driftSummary.fatalCount } else { 0 }
$linkFailureCount = Get-Count $report.linkValidationFailures
$linkWarningCount = Get-Count $report.linkValidationWarnings
$releaseRowsChecked = if ($releaseDrift) { [int]$releaseDrift.checkedCatalogRows } else { 0 }
$validationElapsedMs = if ($performance -and $performance.linkValidation) { [int]$performance.linkValidation.elapsedMs } else { 0 }
$repositoryWarningCount = if ($repositorySettings) { [int]$repositorySettings.warningCount } else { 0 }
$actionsDefaultWorkflowPermissions = if ($actionsWorkflowPermissions -and $null -ne $actionsWorkflowPermissions.defaultWorkflowPermissions) { [string]$actionsWorkflowPermissions.defaultWorkflowPermissions } else { "unknown" }
$actionsPrCreationAllowed = if ($actionsWorkflowPermissions -and $null -ne $actionsWorkflowPermissions.generatedPrCreationAllowed) { [bool]$actionsWorkflowPermissions.generatedPrCreationAllowed } else { $false }
$actionsPrCreationRecommendation = if ($actionsWorkflowPermissions -and $null -ne $actionsWorkflowPermissions.recommendation) { [string]$actionsWorkflowPermissions.recommendation } else { "unknown" }
$generatedPrCredentialDecisionStatus = if ($generatedPrCredentialDecision -and $null -ne $generatedPrCredentialDecision.status) { [string]$generatedPrCredentialDecision.status } else { "unknown" }
$generatedPrCredentialDecisionPath = if ($generatedPrCredentialDecision -and $null -ne $generatedPrCredentialDecision.selectedPath) { [string]$generatedPrCredentialDecision.selectedPath } else { "unknown" }
$generatedPrCredentialRequiresNewSecret = if ($generatedPrCredentialDecision -and $null -ne $generatedPrCredentialDecision.requiresNewSecret) { [bool]$generatedPrCredentialDecision.requiresNewSecret } else { $false }
$generatedPrCredentialCurrentSettingAllowsPr = if ($generatedPrCredentialDecision -and $null -ne $generatedPrCredentialDecision.currentSettingAllowsGeneratedPr) { [bool]$generatedPrCredentialDecision.currentSettingAllowsGeneratedPr } else { $false }
$requiredCheckReadinessStatus = if ($requiredCheckReadiness) { [string]$requiredCheckReadiness.status } else { "unknown" }
$requiredCheckCandidateCount = if ($requiredCheckReadiness) { [int]$requiredCheckReadiness.candidateCheckCount } else { 0 }
$requiredCheckBlockerCount = if ($requiredCheckReadiness) { [int]$requiredCheckReadiness.blockerCount } else { 0 }
$prDeliveryTransitionStatus = if ($prDeliveryTransition) { [string]$prDeliveryTransition.status } else { "unknown" }
$prDeliveryTransitionBlockedCount = if ($prDeliveryTransition) { [int]$prDeliveryTransition.blockedCount } else { 0 }
$prDeliveryTransitionLiveValidationCount = if ($prDeliveryTransition) { [int]$prDeliveryTransition.needsLiveValidationCount } else { 0 }
$generatedPrDryRunAvailable = if ($generatedPrDryRunEvidence) { [bool]$generatedPrDryRunEvidence.available } else { $false }
$generatedPrDryRunConclusion = if ($generatedPrDryRunEvidence) { [string]$generatedPrDryRunEvidence.conclusion } else { "unknown" }
$generatedPrDryRunPreviewReached = if ($generatedPrDryRunEvidence) { [bool]$generatedPrDryRunEvidence.previewStepReached } else { $false }
$generatedPrDryRunFailedStep = if ($generatedPrDryRunEvidence -and $null -ne $generatedPrDryRunEvidence.failedStep) { [string]$generatedPrDryRunEvidence.failedStep } else { "" }
$generatedPrDryRunUrl = if ($generatedPrDryRunEvidence) { [string]$generatedPrDryRunEvidence.runUrl } else { "" }
$generatedPrWriteAvailable = if ($generatedPrWriteEvidence) { [bool]$generatedPrWriteEvidence.available } else { $false }
$generatedPrWriteConclusion = if ($generatedPrWriteEvidence) { [string]$generatedPrWriteEvidence.conclusion } else { "unknown" }
$generatedPrWriteFailedStep = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.failedStep) { [string]$generatedPrWriteEvidence.failedStep } else { "" }
$generatedPrWriteBranchCleanup = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.generatedBranchCleanup) { [string]$generatedPrWriteEvidence.generatedBranchCleanup } else { "" }
$generatedPrWriteUrl = if ($generatedPrWriteEvidence) { [string]$generatedPrWriteEvidence.runUrl } else { "" }
$generatedPrWritePullRequestNumber = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.pullRequestNumber) { [int]$generatedPrWriteEvidence.pullRequestNumber } else { 0 }
$generatedPrWritePullRequestState = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.pullRequestState) { [string]$generatedPrWriteEvidence.pullRequestState } else { "" }
$generatedPrWriteValidationDispatched = if ($generatedPrWriteEvidence) { [bool]$generatedPrWriteEvidence.validationDispatched } else { $false }
$generatedPrWriteValidationConclusion = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.validationConclusion) { [string]$generatedPrWriteEvidence.validationConclusion } else { "" }
$generatedPrWriteValidationFailedStep = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.validationFailedStep) { [string]$generatedPrWriteEvidence.validationFailedStep } else { "" }
$generatedPrWriteValidationUrl = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.validationRunUrl) { [string]$generatedPrWriteEvidence.validationRunUrl } else { "" }
$generatedPrWriteBranchCheckRunCount = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.generatedBranchCheckRunCount) { [int]$generatedPrWriteEvidence.generatedBranchCheckRunCount } else { 0 }
$generatedPrWriteBranchSuccessfulCheckRunCount = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.generatedBranchSuccessfulCheckRunCount) { [int]$generatedPrWriteEvidence.generatedBranchSuccessfulCheckRunCount } else { 0 }
$generatedPrWritePrCheckRollupCount = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.pullRequestCheckRollupCount) { [int]$generatedPrWriteEvidence.pullRequestCheckRollupCount } else { 0 }
$generatedPrWritePrChecksAttached = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.pullRequestChecksAttached) { [bool]$generatedPrWriteEvidence.pullRequestChecksAttached } else { $false }
$communityWarningCount = if ($communityHealth) { [int]$communityHealth.warningCount } else { 0 }
$communityFatalCount = if ($communityHealth) { [int]$communityHealth.fatalCount } else { 0 }
$codeScanning = if ($repositorySettings -and $repositorySettings.security) { $repositorySettings.security.codeScanning } else { $null }
$codeScanningStatus = if ($codeScanning) { [string]$codeScanning.status } else { "unknown" }
$codeScanningRecommendation = if ($codeScanning) { [string]$codeScanning.recommendation } else { "unknown" }
$codeScanningLanguages = if ($codeScanning -and $codeScanning.languagesInspected) {
    @($codeScanning.languagesInspected) -join ", "
} else {
    ""
}
$codeScanningControls = if ($codeScanning -and $codeScanning.activeControls) {
    @($codeScanning.activeControls) -join ", "
} else {
    ""
}
$scorecardAlertPosture = if ($codeScanning -and $codeScanning.PSObject.Properties.Name -contains 'scorecardAlertPosture') { $codeScanning.scorecardAlertPosture } else { $null }
$scorecardOpenAlertCount = if ($scorecardAlertPosture) { [int]$scorecardAlertPosture.openAlertCount } else { 0 }
$scorecardLocalActionableCount = if ($scorecardAlertPosture) { [int]$scorecardAlertPosture.localActionableCount } else { 0 }
$scorecardNeedsHostedRefreshCount = if ($scorecardAlertPosture) { [int]$scorecardAlertPosture.needsHostedRefreshCount } else { 0 }
$scorecardExternalGatedCount = if ($scorecardAlertPosture) { [int]$scorecardAlertPosture.externalGatedCount } else { 0 }
$scorecardNotApplicableCount = if ($scorecardAlertPosture) { [int]$scorecardAlertPosture.notApplicableCount } else { 0 }
$scorecardAlertRecommendation = if ($scorecardAlertPosture -and $null -ne $scorecardAlertPosture.recommendation) { [string]$scorecardAlertPosture.recommendation } else { "unknown" }
$profileReleaseWarningCount = if ($profileReleaseConsistency) { [int]$profileReleaseConsistency.warningCount } else { 0 }
$profileReleasePolicy = if ($profileReleaseConsistency -and $profileReleaseConsistency.PSObject.Properties.Name -contains 'releasePolicy') { $profileReleaseConsistency.releasePolicy } else { $null }
$profileReleasePolicyStatus = if ($profileReleasePolicy -and $null -ne $profileReleasePolicy.status) { [string]$profileReleasePolicy.status } else { "unknown" }
$profileReleaseWarningDisposition = if ($profileReleasePolicy -and $null -ne $profileReleasePolicy.warningDisposition) { [string]$profileReleasePolicy.warningDisposition } else { "unknown" }
$profileReleaseCreationRecommended = if ($profileReleasePolicy -and $null -ne $profileReleasePolicy.releaseCreationRecommended) { [bool]$profileReleasePolicy.releaseCreationRecommended } else { $false }
$userscriptInstallCount = if ($userscriptInstallTrust) { [int]$userscriptInstallTrust.installActionCount } else { 0 }
$userscriptWarningCount = if ($userscriptInstallTrust) { [int]$userscriptInstallTrust.warningCount } else { 0 }
$catalogAccountedCount = if ($catalogFeedAccounting) {
    [int]$catalogFeedAccounting.visitorFacingCatalogCount + [int]$catalogFeedAccounting.suppressedCatalogCount
} else {
    0
}
$catalogAccountingFatalCount = if ($catalogFeedAccounting) { [int]$catalogFeedAccounting.fatalCount } else { 0 }
$portfolioCompatibilityStatus = if ($portfolioCompatibility) { [string]$portfolioCompatibility.status } else { "unknown" }
$portfolioCompatibilityFatalCount = if ($portfolioCompatibility) { [int]$portfolioCompatibility.fatalCount } else { 0 }
$portfolioCompatibilityWarningCount = if ($portfolioCompatibility) { [int]$portfolioCompatibility.warningCount } else { 0 }
$readmeDensityWarningCount = if ($readmeDensity) { [int]$readmeDensity.warningCount } else { 0 }
$readmeLargestCategory = if ($readmeDensity) { [string]$readmeDensity.largestCategory } else { "" }
$readmeLargestCategoryCount = if ($readmeDensity) { [int]$readmeDensity.largestCategoryCount } else { 0 }
$readmeRepoOnlyProjectCount = if ($readmeDensity) { [int]$readmeDensity.repoOnlyProjectCount } else { 0 }
$readmePortfolioOnlyCandidateCount = if ($readmeDensity) { [int]$readmeDensity.portfolioOnlyCandidateCount } else { 0 }
$readmeRoutingRecommendation = if ($readmeDensity) { [string]$readmeDensity.routingRecommendation } else { "unknown" }
$readmePortfolioOnlyCandidateSample = if ($readmeDensity -and $readmeDensity.PSObject.Properties.Name -contains 'portfolioOnlyCandidates') {
    @($readmeDensity.portfolioOnlyCandidates | Select-Object -First 5 | ForEach-Object { [string]$_.repo }) -join ", "
} else {
    ""
}
$readmePortfolioOnlyPreview = if ($readmeDensity -and $readmeDensity.PSObject.Properties.Name -contains 'portfolioOnlyPreview') {
    $readmeDensity.portfolioOnlyPreview
} else {
    $null
}
$readmePortfolioOnlyPreviewStatus = if ($readmePortfolioOnlyPreview) { [string]$readmePortfolioOnlyPreview.status } else { "unknown" }
$readmePortfolioOnlyPreviewDelta = if ($readmePortfolioOnlyPreview) { [int]$readmePortfolioOnlyPreview.projectRowDelta } else { 0 }
$readmePortfolioOnlyPreviewRows = if ($readmePortfolioOnlyPreview) { [int]$readmePortfolioOnlyPreview.previewProjectRowCount } else { 0 }
$readmePortfolioOnlyPreviewOverLimitCategories = if ($readmePortfolioOnlyPreview) { [int]$readmePortfolioOnlyPreview.remainingOverSoftLimitCategoryCount } else { 0 }
$artifactBudgetStatus = if ($artifactBudgets) { [string]$artifactBudgets.status } else { "unknown" }
$artifactBudgetWarningCount = if ($artifactBudgets) { [int]$artifactBudgets.warningCount } else { 0 }
$artifactBudgetRowCount = if ($artifactBudgets) { Get-Count $artifactBudgets.rows } else { 0 }
$renderedSmokeStatus = if ($renderedProfileSmoke) { [string]$renderedProfileSmoke.status } else { "unknown" }
$renderedSmokeWarningCount = if ($renderedProfileSmoke) { [int]$renderedProfileSmoke.warningCount } else { 0 }
$renderedSmokeViewportCount = if ($renderedProfileSmoke) { [int]$renderedProfileSmoke.viewportCount } else { 0 }
$renderedSmokeMobileRootClientWidth = if ($renderedProfileSmoke -and $null -ne $renderedProfileSmoke.mobileRootClientWidth) { [int]$renderedProfileSmoke.mobileRootClientWidth } else { 0 }
$restFallbackStatus = if ($restFallbackReleaseFetch) { [string]$restFallbackReleaseFetch.status } else { "unknown" }
$restFallbackAttempted = if ($restFallbackReleaseFetch) { [int]$restFallbackReleaseFetch.attemptedReleaseFetches } else { 0 }
$restFallbackNoRelease404Count = if ($restFallbackReleaseFetch) { [int]$restFallbackReleaseFetch.noRelease404Count } else { 0 }
$restFallbackFatal = if ($restFallbackReleaseFetch) { [bool]$restFallbackReleaseFetch.fatal } else { $false }

$summary = @"
### $Context report

| Field | Value |
| --- | ---: |
| README in sync | $($report.readmeInSync) |
| Projects export in sync | $($report.projectsExportInSync) |
| Profile assets in sync | $($report.profileAssetsInSync) |
| Schema validation passed | $($report.schemaValidation.passed) |
| Planning docs aligned | $($report.docVersionConsistency.passed) |
| Catalog rows accounted | $catalogAccountedCount |
| Catalog accounting fatal gaps | $catalogAccountingFatalCount |
| Portfolio compatibility | $portfolioCompatibilityStatus |
| Portfolio compatibility fatal gaps | $portfolioCompatibilityFatalCount |
| Portfolio compatibility warnings | $portfolioCompatibilityWarningCount |
| README density warnings | $readmeDensityWarningCount |
| README largest category | $readmeLargestCategory ($readmeLargestCategoryCount) |
| README repo-only rows | $readmeRepoOnlyProjectCount |
| README portfolio-only candidates | $readmePortfolioOnlyCandidateCount |
| README candidate sample | $readmePortfolioOnlyCandidateSample |
| README portfolio-only preview | $readmePortfolioOnlyPreviewStatus |
| README preview row delta | $readmePortfolioOnlyPreviewDelta |
| README preview rows | $readmePortfolioOnlyPreviewRows |
| README preview over-limit categories | $readmePortfolioOnlyPreviewOverLimitCategories |
| README routing recommendation | $readmeRoutingRecommendation |
| Artifact budget status | $artifactBudgetStatus |
| Artifact budget warnings | $artifactBudgetWarningCount |
| Artifact budget rows | $artifactBudgetRowCount |
| Rendered smoke status | $renderedSmokeStatus |
| Rendered smoke warnings | $renderedSmokeWarningCount |
| Rendered smoke viewports | $renderedSmokeViewportCount |
| Rendered smoke mobile root px | $renderedSmokeMobileRootClientWidth |
| Profile release/tag warnings | $profileReleaseWarningCount |
| Profile release policy | $profileReleasePolicyStatus |
| Profile release warning disposition | $profileReleaseWarningDisposition |
| Profile release creation recommended | $profileReleaseCreationRecommended |
| Fatal metadata drift | $fatalDriftCount |
| Missing topic hints | $missingTopicCount |
| Missing descriptions | $missingDescriptionCount |
| Missing project licenses | $missingLicenseCount |
| Unknown project licenses | $unknownLicenseCount |
| Fork-parent warnings | $forkParentWarningCount |
| Stale project review rows | $staleProjectWarningCount |
| Archive review candidates | $archiveReviewCount |
| Release rows checked | $releaseRowsChecked |
| Userscript installs checked | $userscriptInstallCount |
| Userscript trust warnings | $userscriptWarningCount |
| Link targets checked | $($linkSummary.targetCount) |
| Link failures | $linkFailureCount |
| Link warnings | $linkWarningCount |
| REST fallback release status | $restFallbackStatus |
| REST fallback release attempts | $restFallbackAttempted |
| REST fallback no-release 404s | $restFallbackNoRelease404Count |
| Repository setting warnings | $repositoryWarningCount |
| Actions workflow default permissions | $actionsDefaultWorkflowPermissions |
| Actions PR creation allowed | $actionsPrCreationAllowed |
| Actions PR permission recommendation | $actionsPrCreationRecommendation |
| Generated PR credential decision | $generatedPrCredentialDecisionStatus |
| Generated PR credential path | $generatedPrCredentialDecisionPath |
| Generated PR credential new secret | $generatedPrCredentialRequiresNewSecret |
| Generated PR credential setting allows PR | $generatedPrCredentialCurrentSettingAllowsPr |
| Required check readiness | $requiredCheckReadinessStatus |
| Required check candidates | $requiredCheckCandidateCount |
| Required check blockers | $requiredCheckBlockerCount |
| PR delivery transition | $prDeliveryTransitionStatus |
| PR delivery blockers | $prDeliveryTransitionBlockedCount |
| PR delivery live validations | $prDeliveryTransitionLiveValidationCount |
| Generated PR dry-run evidence | $generatedPrDryRunAvailable |
| Generated PR dry-run conclusion | $generatedPrDryRunConclusion |
| Generated PR dry-run preview reached | $generatedPrDryRunPreviewReached |
| Generated PR dry-run failed step | $generatedPrDryRunFailedStep |
| Generated PR dry-run URL | $generatedPrDryRunUrl |
| Generated PR write evidence | $generatedPrWriteAvailable |
| Generated PR write conclusion | $generatedPrWriteConclusion |
| Generated PR write failed step | $generatedPrWriteFailedStep |
| Generated PR write branch cleanup | $generatedPrWriteBranchCleanup |
| Generated PR write URL | $generatedPrWriteUrl |
| Generated PR write pull request | $generatedPrWritePullRequestNumber |
| Generated PR write PR state | $generatedPrWritePullRequestState |
| Generated PR validation dispatched | $generatedPrWriteValidationDispatched |
| Generated PR validation conclusion | $generatedPrWriteValidationConclusion |
| Generated PR validation failed step | $generatedPrWriteValidationFailedStep |
| Generated PR validation URL | $generatedPrWriteValidationUrl |
| Generated PR branch check runs | $generatedPrWriteBranchCheckRunCount |
| Generated PR successful branch checks | $generatedPrWriteBranchSuccessfulCheckRunCount |
| Generated PR PR checks attached | $generatedPrWritePrChecksAttached |
| Generated PR PR check count | $generatedPrWritePrCheckRollupCount |
| Code scanning status | $codeScanningStatus |
| Code scanning recommendation | $codeScanningRecommendation |
| Code scanning languages | $codeScanningLanguages |
| Code scanning controls | $codeScanningControls |
| Scorecard open alerts | $scorecardOpenAlertCount |
| Scorecard local actionable alerts | $scorecardLocalActionableCount |
| Scorecard hosted-refresh alerts | $scorecardNeedsHostedRefreshCount |
| Scorecard external-gated alerts | $scorecardExternalGatedCount |
| Scorecard not-applicable alerts | $scorecardNotApplicableCount |
| Scorecard alert recommendation | $scorecardAlertRecommendation |
| Community-health warnings | $communityWarningCount |
| Community-health fatal gaps | $communityFatalCount |
| Link validation elapsed ms | $validationElapsedMs |

Report generated at $($report.generatedAt).
"@

$githubStepSummaryHardLimitBytes = 1MB
$githubStepSummarySoftLimitBytes = 65536
$summaryByteCount = [Text.Encoding]::UTF8.GetByteCount($summary)
if ($summaryByteCount -gt $githubStepSummaryHardLimitBytes) {
    Write-Output "::error::Profile sync summary is $summaryByteCount byte(s), above GitHub's 1 MiB per-step summary limit."
    throw "Profile sync summary exceeds GitHub step summary limit."
}

if ($summaryByteCount -gt $githubStepSummarySoftLimitBytes) {
    Write-Output "::warning::Profile sync summary is $summaryByteCount byte(s), above the 65536-byte local soft budget."
}

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $summary | Out-File -FilePath $SummaryPath -Encoding utf8 -Append
} else {
    Write-Output $summary
}

if ($fatalDriftCount -gt 0) {
    Write-Output "::error::Profile sync report has $fatalDriftCount fatal metadata drift row(s)."
}

if ($catalogAccountingFatalCount -gt 0) {
    Write-Output "::error::Profile sync report has $catalogAccountingFatalCount catalog/feed accounting fatal gap(s)."
}

if ($portfolioCompatibilityFatalCount -gt 0) {
    Write-Output "::error::Profile sync report has $portfolioCompatibilityFatalCount portfolio compatibility fatal gap(s)."
}

if ($portfolioCompatibilityWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $portfolioCompatibilityWarningCount portfolio compatibility warning(s)."
}

if ($readmeDensityWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $readmeDensityWarningCount README density warning(s)."
}

if ($readmePortfolioOnlyCandidateCount -gt 0) {
    Write-Output "::warning::Profile sync report recommends reviewing $readmePortfolioOnlyCandidateCount README row(s) for portfolio-only routing."
}

if ($artifactBudgetWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $artifactBudgetWarningCount generated artifact budget warning(s)."
}

if ($renderedSmokeWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $renderedSmokeWarningCount rendered profile smoke warning(s)."
}

if ($linkFailureCount -gt 0) {
    Write-Output "::error::Profile sync report has $linkFailureCount fatal link failure(s)."
}

if ($linkWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $linkWarningCount transient link warning(s)."
}

if ($restFallbackFatal) {
    Write-Output "::error::Profile sync report captured a fatal REST fallback release-fetch state: $restFallbackStatus."
}

if ($missingLicenseCount -gt 0) {
    Write-Output "::warning::Profile sync report has $missingLicenseCount visitor-facing project(s) without detected license metadata."
}

if ($unknownLicenseCount -gt 0) {
    Write-Output "::warning::Profile sync report has $unknownLicenseCount visitor-facing project(s) with non-standard license metadata."
}

if ($forkParentWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $forkParentWarningCount fork-parent attribution warning(s)."
}

if ($staleProjectWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $staleProjectWarningCount stale/archive project review row(s)."
}

if ($profileReleaseWarningCount -gt 0) {
    if ($profileReleaseWarningDisposition -eq "informational") {
        Write-Output "::notice::Profile sync report has $profileReleaseWarningCount informational profile release/tag warning(s); policy: $profileReleasePolicyStatus."
    } else {
        Write-Output "::warning::Profile sync report has $profileReleaseWarningCount profile release/tag warning(s)."
    }
}

if ($userscriptWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $userscriptWarningCount userscript install trust warning(s)."
}

if ($repositoryWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $repositoryWarningCount repository setting warning(s)."
}

if ($requiredCheckBlockerCount -gt 0) {
    Write-Output "::warning::Profile sync report has $requiredCheckBlockerCount required-check activation blocker(s)."
}

if ($prDeliveryTransitionBlockedCount -gt 0) {
    Write-Output "::warning::Profile sync report has $prDeliveryTransitionBlockedCount PR-delivery transition blocker(s)."
}

if ($prDeliveryTransitionLiveValidationCount -gt 0) {
    Write-Output "::warning::Profile sync report has $prDeliveryTransitionLiveValidationCount PR-delivery transition live-validation item(s)."
}

if ($generatedPrDryRunAvailable -and $generatedPrDryRunConclusion -ne "success") {
    Write-Output "::warning::Generated PR dry-run evidence is $generatedPrDryRunConclusion; preview reached: $generatedPrDryRunPreviewReached; failed step: $generatedPrDryRunFailedStep."
}

if ($codeScanningStatus -eq "needs-live-validation") {
    Write-Output "::warning::Profile sync report detected CodeQL-supported language(s); verify code scanning coverage."
}

if ($scorecardLocalActionableCount -gt 0) {
    Write-Output "::warning::Profile sync report has $scorecardLocalActionableCount locally actionable Scorecard alert(s)."
}

if ($scorecardNeedsHostedRefreshCount -gt 0) {
    Write-Output "::warning::Profile sync report has $scorecardNeedsHostedRefreshCount Scorecard alert(s) waiting on hosted refresh after local changes."
}

if ($communityWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $communityWarningCount community-health warning(s)."
}

if ($communityFatalCount -gt 0) {
    Write-Output "::error::Profile sync report has $communityFatalCount required community-health gap(s)."
}
