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
$requiredCheckReadiness = if ($repositorySettings -and $repositorySettings.PSObject.Properties.Name -contains 'requiredCheckReadiness') { $repositorySettings.requiredCheckReadiness } else { $null }
$communityHealth = $report.communityHealth
$profileReleaseConsistency = if ($report.PSObject.Properties.Name -contains 'profileReleaseConsistency') { $report.profileReleaseConsistency } else { $null }
$userscriptInstallTrust = if ($report.PSObject.Properties.Name -contains 'userscriptInstallTrust') { $report.userscriptInstallTrust } else { $null }
$catalogFeedAccounting = if ($report.PSObject.Properties.Name -contains 'catalogFeedAccounting') { $report.catalogFeedAccounting } else { $null }
$portfolioCompatibility = if ($report.PSObject.Properties.Name -contains 'portfolioCompatibility') { $report.portfolioCompatibility } else { $null }
$readmeDensity = if ($report.PSObject.Properties.Name -contains 'readmeDensity') { $report.readmeDensity } else { $null }
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
$requiredCheckReadinessStatus = if ($requiredCheckReadiness) { [string]$requiredCheckReadiness.status } else { "unknown" }
$requiredCheckCandidateCount = if ($requiredCheckReadiness) { [int]$requiredCheckReadiness.candidateCheckCount } else { 0 }
$requiredCheckBlockerCount = if ($requiredCheckReadiness) { [int]$requiredCheckReadiness.blockerCount } else { 0 }
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
$profileReleaseWarningCount = if ($profileReleaseConsistency) { [int]$profileReleaseConsistency.warningCount } else { 0 }
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
| Profile release/tag warnings | $profileReleaseWarningCount |
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
| Required check readiness | $requiredCheckReadinessStatus |
| Required check candidates | $requiredCheckCandidateCount |
| Required check blockers | $requiredCheckBlockerCount |
| Code scanning status | $codeScanningStatus |
| Code scanning recommendation | $codeScanningRecommendation |
| Code scanning languages | $codeScanningLanguages |
| Code scanning controls | $codeScanningControls |
| Community-health warnings | $communityWarningCount |
| Community-health fatal gaps | $communityFatalCount |
| Link validation elapsed ms | $validationElapsedMs |

Report generated at $($report.generatedAt).
"@

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
    Write-Output "::warning::Profile sync report has $profileReleaseWarningCount profile release/tag warning(s)."
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

if ($codeScanningStatus -eq "needs-live-validation") {
    Write-Output "::warning::Profile sync report detected CodeQL-supported language(s); verify code scanning coverage."
}

if ($communityWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $communityWarningCount community-health warning(s)."
}

if ($communityFatalCount -gt 0) {
    Write-Output "::error::Profile sync report has $communityFatalCount required community-health gap(s)."
}
