#Requires -Version 7.1
[CmdletBinding()]
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

function ConvertTo-CompactSummaryValue {
    param(
        [object]$Value,
        [int]$MaxLength = 180
    )

    if ($null -eq $Value) {
        return "null"
    }

    $text = $null
    if ($Value -is [string]) {
        $text = [string]$Value
    } else {
        try {
            $text = $Value | ConvertTo-Json -Depth 8 -Compress
        } catch {
            $text = [string]$Value
        }
    }

    $text = (($text -replace '\s+', ' ').Trim())
    if ($text.Length -gt $MaxLength) {
        return ($text.Substring(0, [Math]::Max(0, $MaxLength - 3)) + "...")
    }

    return $text
}

function ConvertTo-MarkdownCell {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value -replace '\|', '\|') -replace "\r?\n", " ")
}

function ConvertTo-GitHubAnnotationValue {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
}

function ConvertTo-GitHubAnnotationProperty {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    # Annotation properties (file=, title=) additionally require ':' and ',' encoded so a value
    # containing them cannot corrupt the property list.
    return $Value.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A').Replace(':', '%3A').Replace(',', '%2C')
}

function Get-ObjectPropertyOrDefault {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
        return $Default
    }

    $value = $Object.$Name
    if ($null -eq $value) {
        return $Default
    }

    return $value
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
$metadataHandoff = if ($metadataHygiene -and $metadataHygiene.PSObject.Properties.Name -contains 'handoff') { $metadataHygiene.handoff } else { $null }
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
$candidateCheckExerciseLatestEvidence = if ($prDeliveryTransition -and $prDeliveryTransition.PSObject.Properties.Name -contains 'candidateCheckExerciseEvidence') { $prDeliveryTransition.candidateCheckExerciseEvidence } else { $null }
$communityHealth = $report.communityHealth
$profileReleaseConsistency = if ($report.PSObject.Properties.Name -contains 'profileReleaseConsistency') { $report.profileReleaseConsistency } else { $null }
$runtimeSecurity = if ($report.PSObject.Properties.Name -contains 'runtimeSecurity') { $report.runtimeSecurity } else { $null }
$userscriptInstallTrust = if ($report.PSObject.Properties.Name -contains 'userscriptInstallTrust') { $report.userscriptInstallTrust } else { $null }
$catalogFeedAccounting = if ($report.PSObject.Properties.Name -contains 'catalogFeedAccounting') { $report.catalogFeedAccounting } else { $null }
$portfolioCompatibility = if ($report.PSObject.Properties.Name -contains 'portfolioCompatibility') { $report.portfolioCompatibility } else { $null }
$readmeDensity = if ($report.PSObject.Properties.Name -contains 'readmeDensity') { $report.readmeDensity } else { $null }
$artifactBudgets = if ($report.PSObject.Properties.Name -contains 'artifactBudgets') { $report.artifactBudgets } else { $null }
$renderedProfileSmoke = if ($report.PSObject.Properties.Name -contains 'renderedProfileSmoke') { $report.renderedProfileSmoke } else { $null }
$restFallbackReleaseFetch = if ($performance -and $performance.PSObject.Properties.Name -contains 'restFallbackReleaseFetch') { $performance.restFallbackReleaseFetch } else { $null }
$evidenceFreshness = if ($report.PSObject.Properties.Name -contains 'evidenceFreshness') { $report.evidenceFreshness } else { $null }
$scheduledWorkflowFreshness = if ($report.PSObject.Properties.Name -contains 'scheduledWorkflowFreshness') { $report.scheduledWorkflowFreshness } else { $null }
$roadmapHygiene = if ($report.PSObject.Properties.Name -contains 'roadmapHygiene') { $report.roadmapHygiene } else { $null }
$rootMarkdownHygiene = if ($report.PSObject.Properties.Name -contains 'rootMarkdownHygiene') { $report.rootMarkdownHygiene } else { $null }
$profileAssetsAccessibility = if ($report.PSObject.Properties.Name -contains 'profileAssetsAccessibility') { $report.profileAssetsAccessibility } else { $null }
$readmeExperienceChecks = if ($report.PSObject.Properties.Name -contains 'readmeExperienceChecks') { $report.readmeExperienceChecks } else { $null }
$readmeHeadingHierarchy = if ($report.PSObject.Properties.Name -contains 'readmeHeadingHierarchy') { $report.readmeHeadingHierarchy } else { $null }
$metadataFetch = if ($performance -and $performance.PSObject.Properties.Name -contains 'metadataFetch') { $performance.metadataFetch } else { $null }
$artifactDriftDiagnostics = if ($report.PSObject.Properties.Name -contains 'artifactDriftDiagnostics') { $report.artifactDriftDiagnostics } else { $null }

$missingTopicCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "missingTopicCount" -Default (Get-Count ($metadataHygiene ? $metadataHygiene.missingTopics : $null))) } else { 0 }
$missingDescriptionCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "missingDescriptionCount" -Default (Get-Count ($metadataHygiene ? $metadataHygiene.missingDescriptions : $null))) } else { 0 }
$publicMissingTopicCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "publicMissingTopicCount" -Default (Get-Count ($metadataHygiene ? $metadataHygiene.missingTopics : $null))) } else { 0 }
$publicMissingDescriptionCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "publicMissingDescriptionCount" -Default (Get-Count ($metadataHygiene ? $metadataHygiene.missingDescriptions : $null))) } else { 0 }
$redactedTopicCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "redactedTopicCount" -Default 0) } else { 0 }
$redactedDescriptionCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "redactedDescriptionCount" -Default 0) } else { 0 }
$suppressedTopicCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "suppressedTopicCount" -Default 0) } else { 0 }
$suppressedDescriptionCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "suppressedDescriptionCount" -Default 0) } else { 0 }
$unsafeOrPrivateTopicCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "unsafeOrPrivateTopicCount" -Default 0) } else { 0 }
$unsafeOrPrivateDescriptionCount = if ($metadataHygiene) { [int](Get-ObjectPropertyOrDefault -Object $metadataHygiene -Name "unsafeOrPrivateDescriptionCount" -Default 0) } else { 0 }
$metadataHandoffStatus = if ($metadataHandoff -and $null -ne $metadataHandoff.status) { [string]$metadataHandoff.status } else { "unknown" }
[object[]]$metadataHandoffTopicRows = if ($metadataHandoff -and $metadataHandoff.PSObject.Properties.Name -contains 'topicRows') { @($metadataHandoff.topicRows) } else { @() }
[object[]]$metadataHandoffDescriptionRows = if ($metadataHandoff -and $metadataHandoff.PSObject.Properties.Name -contains 'descriptionRows') { @($metadataHandoff.descriptionRows) } else { @() }
$metadataHandoffTopicRowCount = if ($metadataHandoff -and $null -ne $metadataHandoff.topicRowCount) { [int]$metadataHandoff.topicRowCount } else { Get-Count $metadataHandoffTopicRows }
$metadataHandoffDescriptionRowCount = if ($metadataHandoff -and $null -ne $metadataHandoff.descriptionRowCount) { [int]$metadataHandoff.descriptionRowCount } else { Get-Count $metadataHandoffDescriptionRows }
$missingLicenseCount = if ($projectLicenseMetadata) { [int]$projectLicenseMetadata.missingCount } else { 0 }
$unknownLicenseCount = if ($projectLicenseMetadata) { [int]$projectLicenseMetadata.unknownCount } else { 0 }
$intentionalLicenseExceptionCount = if ($projectLicenseMetadata -and $projectLicenseMetadata.PSObject.Properties.Name -contains 'intentionalExceptionCount') { [int]$projectLicenseMetadata.intentionalExceptionCount } else { 0 }
$unresolvedUnknownLicenseCount = if ($projectLicenseMetadata -and $projectLicenseMetadata.PSObject.Properties.Name -contains 'unresolvedUnknownCount') { [int]$projectLicenseMetadata.unresolvedUnknownCount } else { $unknownLicenseCount }
$forkParentWarningCount = if ($forkParentDrift) { [int]$forkParentDrift.warningCount } else { 0 }
$forkParentPublicDetailRowCount = if ($forkParentDrift -and $forkParentDrift.PSObject.Properties.Name -contains 'publicDetailRowCount') { [int]$forkParentDrift.publicDetailRowCount } else { 0 }
$forkParentRedactedDetailRowCount = if ($forkParentDrift -and $forkParentDrift.PSObject.Properties.Name -contains 'redactedDetailRowCount') { [int]$forkParentDrift.redactedDetailRowCount } else { 0 }
$staleProjectWarningCount = if ($staleProjectReview) { [int]$staleProjectReview.warningCount } else { 0 }
$archiveReviewCount = if ($staleProjectReview) { [int]$staleProjectReview.archiveReviewCount } else { 0 }
$fatalDriftCount = if ($driftSummary) { [int]$driftSummary.fatalCount } else { 0 }
$metadataDriftRows = if ($report.PSObject.Properties.Name -contains 'metadataDrift') { @($report.metadataDrift) } else { @() }
$fatalDriftRows = @($metadataDriftRows | Where-Object {
        $severity = [string](Get-ObjectPropertyOrDefault -Object $_ -Name "severity" -Default "")
        $failing = [bool](Get-ObjectPropertyOrDefault -Object $_ -Name "failing" -Default $false)
        $severity -eq "fatal" -or $failing
    })
$linkFailureCount = Get-Count $report.linkValidationFailures
$linkWarningCount = Get-Count $report.linkValidationWarnings
$readmeActionTargetCount = if ($linkSummary -and $linkSummary.PSObject.Properties.Name -contains 'readmeActionTargetCount') { [int]$linkSummary.readmeActionTargetCount } else { 0 }
$readmeInstallSnippetTargetCount = if ($linkSummary -and $linkSummary.PSObject.Properties.Name -contains 'readmeInstallSnippetTargetCount') { [int]$linkSummary.readmeInstallSnippetTargetCount } else { 0 }
$readmeDownloadLinkTargetCount = if ($linkSummary -and $linkSummary.PSObject.Properties.Name -contains 'readmeDownloadLinkTargetCount') { [int]$linkSummary.readmeDownloadLinkTargetCount } else { 0 }
$readmeUserscriptInstallTargetCount = if ($linkSummary -and $linkSummary.PSObject.Properties.Name -contains 'readmeUserscriptInstallTargetCount') { [int]$linkSummary.readmeUserscriptInstallTargetCount } else { 0 }
$releaseRowsChecked = if ($releaseDrift) { [int]$releaseDrift.checkedCatalogRows } else { 0 }
$executableShortlist = if ($releaseDrift -and $releaseDrift.PSObject.Properties.Name -contains 'executableDownloadTrustShortlist') { $releaseDrift.executableDownloadTrustShortlist } else { $null }
$executableDownloadCount = if ($executableShortlist) { [int]$executableShortlist.executableDownloadCount } else { 0 }
$executableMetadataCompleteCount = if ($executableShortlist) { [int]$executableShortlist.metadataCompleteCount } else { 0 }
$executableChecksumGapCount = if ($executableShortlist) { [int]$executableShortlist.checksumGapCount } else { 0 }
$executableAttestationGapCount = if ($executableShortlist) { [int]$executableShortlist.attestationGapCount } else { 0 }
$executableShortlistTopRepo = if ($executableShortlist -and @($executableShortlist.rows).Count -gt 0) { [string]$executableShortlist.rows[0].repo } else { "" }
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
$generatedPrWriteStatusHandoffImplemented = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.statusHandoffImplemented) { [bool]$generatedPrWriteEvidence.statusHandoffImplemented } else { $false }
$generatedPrWriteStatusHandoffContext = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.statusHandoffContext) { [string]$generatedPrWriteEvidence.statusHandoffContext } else { "" }
$generatedPrWriteStatusHandoffProof = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.statusHandoffProof) { [string]$generatedPrWriteEvidence.statusHandoffProof } else { "" }
$generatedPrWriteStatusHandoffState = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.statusHandoffState) { [string]$generatedPrWriteEvidence.statusHandoffState } else { "" }
$generatedPrWriteStatusHandoffPermission = if ($generatedPrWriteEvidence -and $null -ne $generatedPrWriteEvidence.statusHandoffPermission) { [string]$generatedPrWriteEvidence.statusHandoffPermission } else { "" }
$directMainMaintenancePolicy = if ($prDeliveryTransition) { $prDeliveryTransition.directMainMaintenancePolicy } else { $null }
$directMainMaintenancePolicyStatus = if ($directMainMaintenancePolicy -and $null -ne $directMainMaintenancePolicy.status) { [string]$directMainMaintenancePolicy.status } else { "" }
$directMainMaintenancePolicyAllowed = if ($directMainMaintenancePolicy -and $null -ne $directMainMaintenancePolicy.allowed) { [bool]$directMainMaintenancePolicy.allowed } else { $false }
$directMainMaintenancePolicyRecommendation = if ($directMainMaintenancePolicy -and $null -ne $directMainMaintenancePolicy.recommendation) { [string]$directMainMaintenancePolicy.recommendation } else { "" }
$candidateCheckExercisePlan = if ($prDeliveryTransition -and $prDeliveryTransition.PSObject.Properties.Name -contains 'candidateCheckExercisePlan') { $prDeliveryTransition.candidateCheckExercisePlan } else { $null }
$candidateCheckExercisePlanStatus = if ($candidateCheckExercisePlan -and $null -ne $candidateCheckExercisePlan.status) { [string]$candidateCheckExercisePlan.status } else { "" }
$candidateCheckExerciseReadiness = if ($candidateCheckExercisePlan -and $null -ne $candidateCheckExercisePlan.readinessStatus) { [string]$candidateCheckExercisePlan.readinessStatus } else { "" }
$candidateCheckExercisePlanEvidenceStatus = if ($candidateCheckExercisePlan -and $null -ne $candidateCheckExercisePlan.evidenceStatus) { [string]$candidateCheckExercisePlan.evidenceStatus } else { "" }
$candidateCheckExerciseCandidateCount = if ($candidateCheckExercisePlan -and $null -ne $candidateCheckExercisePlan.candidateCheckCount) { [int]$candidateCheckExercisePlan.candidateCheckCount } else { 0 }
$candidateCheckExerciseBranchPrefix = if ($candidateCheckExercisePlan -and $null -ne $candidateCheckExercisePlan.disposableBranchPrefix) { [string]$candidateCheckExercisePlan.disposableBranchPrefix } else { "" }
$candidateCheckExerciseTouchPaths = if ($candidateCheckExercisePlan -and $candidateCheckExercisePlan.touchPaths) { @($candidateCheckExercisePlan.touchPaths) -join ", " } else { "" }
$candidateCheckExerciseLatestAvailable = if ($candidateCheckExerciseLatestEvidence) { [bool]$candidateCheckExerciseLatestEvidence.available } else { $false }
$candidateCheckExerciseLatestStatus = if ($candidateCheckExerciseLatestEvidence -and $null -ne $candidateCheckExerciseLatestEvidence.status) { [string]$candidateCheckExerciseLatestEvidence.status } else { "" }
$candidateCheckExerciseLatestPullRequest = if ($candidateCheckExerciseLatestEvidence -and $null -ne $candidateCheckExerciseLatestEvidence.pullRequestNumber) { [int]$candidateCheckExerciseLatestEvidence.pullRequestNumber } else { 0 }
$candidateCheckExerciseLatestSuccessful = if ($candidateCheckExerciseLatestEvidence -and $null -ne $candidateCheckExerciseLatestEvidence.successfulCandidateCheckCount) { [int]$candidateCheckExerciseLatestEvidence.successfulCandidateCheckCount } else { 0 }
$candidateCheckExerciseLatestFailed = if ($candidateCheckExerciseLatestEvidence -and $null -ne $candidateCheckExerciseLatestEvidence.failedCandidateCheckCount) { [int]$candidateCheckExerciseLatestEvidence.failedCandidateCheckCount } else { 0 }
$candidateCheckExerciseLatestFailedNames = if ($candidateCheckExerciseLatestEvidence -and $candidateCheckExerciseLatestEvidence.failedCandidateChecks) { @($candidateCheckExerciseLatestEvidence.failedCandidateChecks) -join ", " } else { "" }
$candidateCheckExerciseLatestCleanup = if ($candidateCheckExerciseLatestEvidence -and $null -ne $candidateCheckExerciseLatestEvidence.cleanupState) { [string]$candidateCheckExerciseLatestEvidence.cleanupState } else { "" }
$routineMaintenancePrDrillEvidence = if ($prDeliveryTransition -and $prDeliveryTransition.PSObject.Properties.Name -contains 'routineMaintenancePrDrillEvidence') { $prDeliveryTransition.routineMaintenancePrDrillEvidence } else { $null }
$routineMaintenancePrDrillAvailable = if ($routineMaintenancePrDrillEvidence -and $null -ne $routineMaintenancePrDrillEvidence.available) { [bool]$routineMaintenancePrDrillEvidence.available } else { $false }
$routineMaintenancePrDrillStatus = if ($routineMaintenancePrDrillEvidence -and $null -ne $routineMaintenancePrDrillEvidence.status) { [string]$routineMaintenancePrDrillEvidence.status } else { "" }
$routineMaintenancePrDrillPullRequest = if ($routineMaintenancePrDrillEvidence -and $null -ne $routineMaintenancePrDrillEvidence.pullRequestNumber) { [int]$routineMaintenancePrDrillEvidence.pullRequestNumber } else { 0 }
$routineMaintenancePrDrillSuccessful = if ($routineMaintenancePrDrillEvidence -and $null -ne $routineMaintenancePrDrillEvidence.successfulCandidateCheckCount) { [int]$routineMaintenancePrDrillEvidence.successfulCandidateCheckCount } else { 0 }
$routineMaintenancePrDrillFailed = if ($routineMaintenancePrDrillEvidence -and $null -ne $routineMaintenancePrDrillEvidence.failedCandidateCheckCount) { [int]$routineMaintenancePrDrillEvidence.failedCandidateCheckCount } else { 0 }
$routineMaintenancePrDrillCleanup = if ($routineMaintenancePrDrillEvidence -and $null -ne $routineMaintenancePrDrillEvidence.cleanupState) { [string]$routineMaintenancePrDrillEvidence.cleanupState } else { "" }
$requiredCheckEnforcementEvidence = if ($prDeliveryTransition -and $prDeliveryTransition.PSObject.Properties.Name -contains 'requiredCheckEnforcementEvidence') { $prDeliveryTransition.requiredCheckEnforcementEvidence } else { $null }
$requiredCheckEnforcementAvailable = if ($requiredCheckEnforcementEvidence -and $null -ne $requiredCheckEnforcementEvidence.available) { [bool]$requiredCheckEnforcementEvidence.available } else { $false }
$requiredCheckEnforcementStatus = if ($requiredCheckEnforcementEvidence -and $null -ne $requiredCheckEnforcementEvidence.status) { [string]$requiredCheckEnforcementEvidence.status } else { "" }
$requiredCheckEnforcementMechanism = if ($requiredCheckEnforcementEvidence -and $null -ne $requiredCheckEnforcementEvidence.enforcementMechanism) { [string]$requiredCheckEnforcementEvidence.enforcementMechanism } else { "" }
$requiredCheckEnforcementPullRequest = if ($requiredCheckEnforcementEvidence -and $null -ne $requiredCheckEnforcementEvidence.pullRequestNumber) { [int]$requiredCheckEnforcementEvidence.pullRequestNumber } else { 0 }
$requiredCheckEnforcementSuccessful = if ($requiredCheckEnforcementEvidence -and $null -ne $requiredCheckEnforcementEvidence.successfulCandidateCheckCount) { [int]$requiredCheckEnforcementEvidence.successfulCandidateCheckCount } else { 0 }
$requiredCheckEnforcementFailed = if ($requiredCheckEnforcementEvidence -and $null -ne $requiredCheckEnforcementEvidence.failedCandidateCheckCount) { [int]$requiredCheckEnforcementEvidence.failedCandidateCheckCount } else { 0 }
$requiredCheckEnforcementCleanup = if ($requiredCheckEnforcementEvidence -and $null -ne $requiredCheckEnforcementEvidence.cleanupState) { [string]$requiredCheckEnforcementEvidence.cleanupState } else { "" }
$reviewPolicyPosture = if ($repositorySettings -and $repositorySettings.PSObject.Properties.Name -contains 'reviewPolicyPosture') { $repositorySettings.reviewPolicyPosture } else { $null }
$reviewPolicyStatus = if ($reviewPolicyPosture -and $null -ne $reviewPolicyPosture.status) { [string]$reviewPolicyPosture.status } else { "unknown" }
$reviewPolicyRecommendation = if ($reviewPolicyPosture -and $null -ne $reviewPolicyPosture.recommendation) { [string]$reviewPolicyPosture.recommendation } else { "unknown" }
$reviewPolicyPrReviewsRequired = if ($reviewPolicyPosture -and $null -ne $reviewPolicyPosture.pullRequestReviewsRequired) { [bool]$reviewPolicyPosture.pullRequestReviewsRequired } else { $false }
$reviewPolicyCodeOwnerReviewsRequired = if ($reviewPolicyPosture -and $null -ne $reviewPolicyPosture.codeOwnerReviewsRequired) { [bool]$reviewPolicyPosture.codeOwnerReviewsRequired } else { $false }
$reviewPolicyReviewerModel = if ($reviewPolicyPosture -and $null -ne $reviewPolicyPosture.reviewerModel) { [string]$reviewPolicyPosture.reviewerModel } else { "" }
$reviewPolicyScorecardClassification = if ($reviewPolicyPosture -and $null -ne $reviewPolicyPosture.scorecardCodeReviewClassification) { [string]$reviewPolicyPosture.scorecardCodeReviewClassification } else { "" }
$communityWarningCount = if ($communityHealth) { [int]$communityHealth.warningCount } else { 0 }
$communityFatalCount = if ($communityHealth) { [int]$communityHealth.fatalCount } else { 0 }
$dependabotSecurityPosture = if ($repositorySettings -and $repositorySettings.security -and $repositorySettings.security.PSObject.Properties.Name -contains 'dependabotSecurityPosture') { $repositorySettings.security.dependabotSecurityPosture } else { $null }
$dependabotSecurityStatus = if ($dependabotSecurityPosture -and $null -ne $dependabotSecurityPosture.status) { [string]$dependabotSecurityPosture.status } else { "unknown" }
$dependabotSecurityRecommendation = if ($dependabotSecurityPosture -and $null -ne $dependabotSecurityPosture.recommendation) { [string]$dependabotSecurityPosture.recommendation } else { "unknown" }
$dependabotSecurityUpdatesEnabled = if ($dependabotSecurityPosture -and $null -ne $dependabotSecurityPosture.securityUpdatesEnabled) { [bool]$dependabotSecurityPosture.securityUpdatesEnabled } else { $false }
$dependabotConfigPresent = if ($dependabotSecurityPosture -and $null -ne $dependabotSecurityPosture.localConfigPresent) { [bool]$dependabotSecurityPosture.localConfigPresent } else { $false }
$dependabotConfigEcosystems = if ($dependabotSecurityPosture -and $dependabotSecurityPosture.localConfigEcosystems) { @($dependabotSecurityPosture.localConfigEcosystems) -join ", " } else { "" }
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
$codeScanningLocalControls = if ($codeScanning -and $codeScanning.PSObject.Properties.Name -contains 'localControls' -and $codeScanning.localControls) {
    @($codeScanning.localControls) -join ", "
} else {
    ""
}
$codeScanningHostedControls = if ($codeScanning -and $codeScanning.PSObject.Properties.Name -contains 'hostedControls' -and $codeScanning.hostedControls) {
    @($codeScanning.hostedControls) -join ", "
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
$runtimeCurrent = if ($runtimeSecurity -and $runtimeSecurity.PSObject.Properties.Name -contains 'current') { $runtimeSecurity.current } else { $null }
$runtimePolicy = if ($runtimeSecurity -and $runtimeSecurity.PSObject.Properties.Name -contains 'policy') { $runtimeSecurity.policy } else { $null }
$runtimeStatus = if ($runtimeSecurity -and $null -ne $runtimeSecurity.status) { [string]$runtimeSecurity.status } else { "unknown" }
$runtimeVersion = if ($runtimeCurrent -and $null -ne $runtimeCurrent.version) { [string]$runtimeCurrent.version } else { "unknown" }
$runtimeChannel = if ($runtimeCurrent -and $null -ne $runtimeCurrent.channel) { [string]$runtimeCurrent.channel } else { "unknown" }
$runtimeExecutable = if ($runtimeCurrent -and $null -ne $runtimeCurrent.executable) { [string]$runtimeCurrent.executable } else { "unknown" }
$runtimeSupported = if ($runtimeSecurity -and $null -ne $runtimeSecurity.supported) { [bool]$runtimeSecurity.supported } else { $false }
$runtimePreferred = if ($runtimeSecurity -and $null -ne $runtimeSecurity.preferred) { [bool]$runtimeSecurity.preferred } else { $false }
$runtimeWarningCount = if ($runtimeSecurity -and $null -ne $runtimeSecurity.warningCount) { [int]$runtimeSecurity.warningCount } else { 0 }
$runtimePreferredVersion = if ($runtimePolicy -and $null -ne $runtimePolicy.preferredLtsVersion) { [string]$runtimePolicy.preferredLtsVersion } else { "unknown" }
$runtimeTransitionEnd = if ($runtimePolicy -and $null -ne $runtimePolicy.previousLtsAcceptedUntil) { [string]$runtimePolicy.previousLtsAcceptedUntil } else { "unknown" }
$runtimeBootstrapOnly = if ($runtimePolicy -and $null -ne $runtimePolicy.windowsPowerShellBootstrapOnly) { [bool]$runtimePolicy.windowsPowerShellBootstrapOnly } else { $false }
$runtimeAdvisory = if ($runtimePolicy -and $null -ne $runtimePolicy.windowsPowerShellAdvisory) { [string]$runtimePolicy.windowsPowerShellAdvisory } else { "" }
$userscriptInstallCount = if ($userscriptInstallTrust) { [int]$userscriptInstallTrust.installActionCount } else { 0 }
$userscriptWarningCount = if ($userscriptInstallTrust) { [int]$userscriptInstallTrust.warningCount } else { 0 }
$userscriptReleaseReadyCount = if ($userscriptInstallTrust -and $userscriptInstallTrust.PSObject.Properties.Name -contains 'releaseChannelReadyCount') { [int]$userscriptInstallTrust.releaseChannelReadyCount } else { 0 }
$userscriptReleaseKeepBranchCount = if ($userscriptInstallTrust -and $userscriptInstallTrust.PSObject.Properties.Name -contains 'releaseChannelKeepBranchCount') { [int]$userscriptInstallTrust.releaseChannelKeepBranchCount } else { 0 }
$userscriptReleaseBlockedCount = if ($userscriptInstallTrust -and $userscriptInstallTrust.PSObject.Properties.Name -contains 'releaseChannelBlockedCount') { [int]$userscriptInstallTrust.releaseChannelBlockedCount } else { 0 }
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
$metadataProvider = if ($metadataFetch) { [string](Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "provider" -Default "unknown") } else { "unknown" }
$metadataGraphQlPageSize = if ($metadataFetch) { [int](Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "graphQlPageSize" -Default 0) } else { 0 }
$metadataRequestCount = if ($metadataFetch) { [int](Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "requestCount" -Default 0) } else { 0 }
$metadataAttemptCount = if ($metadataFetch) { [int](Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "attemptCount" -Default 0) } else { 0 }
$metadataRetryCount = if ($metadataFetch) { [int](Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "retryCount" -Default ([Math]::Max(0, $metadataAttemptCount - 1))) } else { 0 }
$metadataResourceLimitFallback = if ($metadataFetch) { [bool](Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "resourceLimitFallback" -Default $false) } else { $false }
$metadataFallbackReason = if ($metadataFetch) { ConvertTo-CompactSummaryValue (Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "fallbackReason") } else { "null" }
$metadataResourceLimitReason = if ($metadataFetch) { ConvertTo-CompactSummaryValue (Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "resourceLimitFallbackReason") } else { "null" }
$metadataRepoCount = if ($metadataFetch) { [int](Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "repoCount" -Default 0) } else { 0 }
$metadataTruncated = if ($metadataFetch) { [bool](Get-ObjectPropertyOrDefault -Object $metadataFetch -Name "truncated" -Default $false) } else { $false }
$restFallbackStatus = if ($restFallbackReleaseFetch) { [string]$restFallbackReleaseFetch.status } else { "unknown" }
$restFallbackMaxReleaseFetches = if ($restFallbackReleaseFetch) { [int]$restFallbackReleaseFetch.maxReleaseFetches } else { 0 }
$restFallbackUnauthenticatedReleaseFetchLimit = if ($restFallbackReleaseFetch) { [int]$restFallbackReleaseFetch.unauthenticatedReleaseFetchLimit } else { 0 }
$restFallbackAttempted = if ($restFallbackReleaseFetch) { [int]$restFallbackReleaseFetch.attemptedReleaseFetches } else { 0 }
$restFallbackNoRelease404Count = if ($restFallbackReleaseFetch) { [int]$restFallbackReleaseFetch.noRelease404Count } else { 0 }
$restFallbackFatal = if ($restFallbackReleaseFetch) { [bool]$restFallbackReleaseFetch.fatal } else { $false }
$evidenceFreshnessStatus = if ($evidenceFreshness) { [string]$evidenceFreshness.status } else { "unknown" }
$evidenceFreshnessWarningCount = if ($evidenceFreshness) { [int]$evidenceFreshness.warningCount } else { 0 }
$evidenceReportGeneratedAt = if ($evidenceFreshness -and $null -ne $evidenceFreshness.committedReportGeneratedAt) { [string]$evidenceFreshness.committedReportGeneratedAt } else { "" }
$evidenceLatestCommitDate = if ($evidenceFreshness -and $null -ne $evidenceFreshness.latestReportAffectingCommitDate) { [string]$evidenceFreshness.latestReportAffectingCommitDate } else { "" }
$evidenceReportBehindCommit = if ($evidenceFreshness) { [bool]$evidenceFreshness.reportAgeBehindCommit } else { $false }
$evidenceReportAgeBehindHours = if ($evidenceFreshness -and $null -ne $evidenceFreshness.reportAgeBehindHours) { [string]$evidenceFreshness.reportAgeBehindHours } else { "" }
$evidenceSmokeStatus = if ($evidenceFreshness -and $null -ne $evidenceFreshness.smokeStatus) { [string]$evidenceFreshness.smokeStatus } else { "unknown" }
$evidenceSmokeStale = if ($evidenceFreshness) { [bool]$evidenceFreshness.smokeEvidenceStale } else { $false }
$scheduledWorkflowStatus = if ($scheduledWorkflowFreshness) { [string]$scheduledWorkflowFreshness.status } else { "unknown" }
$scheduledWorkflowCount = if ($scheduledWorkflowFreshness) { [int]$scheduledWorkflowFreshness.scheduledWorkflowCount } else { 0 }
$scheduledWorkflowWarningCount = if ($scheduledWorkflowFreshness) { [int]$scheduledWorkflowFreshness.warningCount } else { 0 }
$scheduledWorkflowStaleCount = if ($scheduledWorkflowFreshness) { [int]$scheduledWorkflowFreshness.staleCount } else { 0 }
$scheduledWorkflowFailingCount = if ($scheduledWorkflowFreshness) { [int]$scheduledWorkflowFreshness.failingCount } else { 0 }
$scheduledWorkflowUnavailableCount = if ($scheduledWorkflowFreshness) { [int]$scheduledWorkflowFreshness.unavailableCount } else { 0 }
$scheduledWorkflowDisabledCount = if ($scheduledWorkflowFreshness) { [int]$scheduledWorkflowFreshness.disabledCount } else { 0 }
$scheduledWorkflowRows = if ($scheduledWorkflowFreshness -and $scheduledWorkflowFreshness.PSObject.Properties.Name -contains 'rows') { @($scheduledWorkflowFreshness.rows) } else { @() }
$roadmapHygieneStatus = if ($roadmapHygiene) { [string]$roadmapHygiene.status } else { "unknown" }
$roadmapHygieneWarningCount = if ($roadmapHygiene) { [int]$roadmapHygiene.warningCount } else { 0 }
$roadmapHygieneRows = if ($roadmapHygiene -and $roadmapHygiene.PSObject.Properties.Name -contains 'rows') { @($roadmapHygiene.rows) } else { @() }
$imageAltTextComplete = if ($readmeExperienceChecks -and $readmeExperienceChecks.PSObject.Properties.Name -contains 'imageAltTextComplete') { [bool]$readmeExperienceChecks.imageAltTextComplete } else { $true }
$imageAltTextIssueCount = if ($readmeExperienceChecks -and $readmeExperienceChecks.PSObject.Properties.Name -contains 'imageAltTextIssueCount') { [int]$readmeExperienceChecks.imageAltTextIssueCount } else { 0 }
$headingHierarchyStatus = if ($readmeHeadingHierarchy) { [string]$readmeHeadingHierarchy.status } else { "unknown" }
$headingSkippedLevelCount = if ($readmeHeadingHierarchy) { [int]$readmeHeadingHierarchy.skippedLevelCount } else { 0 }
$rootMarkdownStatus = if ($rootMarkdownHygiene) { [string]$rootMarkdownHygiene.status } else { "unknown" }
$rootMarkdownWarningCount = if ($rootMarkdownHygiene) { [int]$rootMarkdownHygiene.warningCount } else { 0 }
$rootMarkdownUnexpected = if ($rootMarkdownHygiene -and $rootMarkdownHygiene.PSObject.Properties.Name -contains 'unexpectedFiles') { @($rootMarkdownHygiene.unexpectedFiles) -join ", " } else { "" }
$svgContrastStatus = if ($profileAssetsAccessibility) { [string]$profileAssetsAccessibility.status } else { "unknown" }
$svgContrastFailingAssets = if ($profileAssetsAccessibility) { [int]$profileAssetsAccessibility.failingAssetCount } else { 0 }

$summary = @"
### $Context report

| Field | Value |
| --- | ---: |
| README in sync | $($report.readmeInSync) |
| Projects export in sync | $($report.projectsExportInSync) |
| Profile assets in sync | $($report.profileAssetsInSync) |
| Schema validation passed | $($report.schemaValidation.passed) |
| Profile version metadata valid | $($report.docVersionConsistency.passed) |
| PowerShell runtime status | $runtimeStatus |
| PowerShell runtime version | $runtimeVersion |
| PowerShell runtime channel | $runtimeChannel |
| PowerShell runtime executable | $runtimeExecutable |
| PowerShell runtime supported | $runtimeSupported |
| PowerShell runtime preferred | $runtimePreferred |
| PowerShell runtime preferred LTS | $runtimePreferredVersion |
| PowerShell runtime transition end | $runtimeTransitionEnd |
| PowerShell runtime warnings | $runtimeWarningCount |
| Windows PowerShell bootstrap-only | $runtimeBootstrapOnly |
| Windows PowerShell advisory | $runtimeAdvisory |
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
| Evidence freshness | $evidenceFreshnessStatus |
| Evidence freshness warnings | $evidenceFreshnessWarningCount |
| Committed report generated at | $evidenceReportGeneratedAt |
| Latest report-affecting commit | $evidenceLatestCommitDate |
| Committed report behind commit | $evidenceReportBehindCommit |
| Committed report age behind (hours) | $evidenceReportAgeBehindHours |
| Committed smoke status | $evidenceSmokeStatus |
| Committed smoke evidence stale | $evidenceSmokeStale |
| Scheduled workflow freshness | $scheduledWorkflowStatus |
| Scheduled workflows tracked | $scheduledWorkflowCount |
| Scheduled workflow warnings | $scheduledWorkflowWarningCount |
| Scheduled workflows stale | $scheduledWorkflowStaleCount |
| Scheduled workflows failing | $scheduledWorkflowFailingCount |
| Scheduled workflows unavailable | $scheduledWorkflowUnavailableCount |
| Scheduled workflows disabled | $scheduledWorkflowDisabledCount |
| Roadmap hygiene | $roadmapHygieneStatus |
| Roadmap shipped-entry warnings | $roadmapHygieneWarningCount |
| README image alt-text complete | $imageAltTextComplete |
| README images missing alt text | $imageAltTextIssueCount |
| README heading hierarchy | $headingHierarchyStatus |
| README skipped heading levels | $headingSkippedLevelCount |
| Root Markdown hygiene | $rootMarkdownStatus |
| Root Markdown unexpected files | $rootMarkdownWarningCount |
| Profile SVG contrast | $svgContrastStatus |
| Profile SVG contrast failures | $svgContrastFailingAssets |
| Profile release/tag warnings | $profileReleaseWarningCount |
| Profile release policy | $profileReleasePolicyStatus |
| Profile release warning disposition | $profileReleaseWarningDisposition |
| Profile release creation recommended | $profileReleaseCreationRecommended |
| Fatal metadata drift | $fatalDriftCount |
| Missing topic hints | $missingTopicCount |
| Missing descriptions | $missingDescriptionCount |
| Public missing topic rows | $publicMissingTopicCount |
| Public missing description rows | $publicMissingDescriptionCount |
| Redacted metadata topic gaps | $redactedTopicCount |
| Redacted metadata description gaps | $redactedDescriptionCount |
| Suppressed topic gaps excluded | $suppressedTopicCount |
| Suppressed description gaps excluded | $suppressedDescriptionCount |
| Unsafe/private topic gaps excluded | $unsafeOrPrivateTopicCount |
| Unsafe/private description gaps excluded | $unsafeOrPrivateDescriptionCount |
| Metadata hygiene handoff | $metadataHandoffStatus |
| Metadata handoff topic rows | $metadataHandoffTopicRowCount |
| Metadata handoff description rows | $metadataHandoffDescriptionRowCount |
| Missing project licenses | $missingLicenseCount |
| Unknown project licenses | $unknownLicenseCount |
| Intentional license exceptions | $intentionalLicenseExceptionCount |
| Unresolved unknown project licenses | $unresolvedUnknownLicenseCount |
| Fork-parent warnings | $forkParentWarningCount |
| Fork-parent public detail rows | $forkParentPublicDetailRowCount |
| Fork-parent redacted detail rows | $forkParentRedactedDetailRowCount |
| Stale project review rows | $staleProjectWarningCount |
| Archive review candidates | $archiveReviewCount |
| Release rows checked | $releaseRowsChecked |
| Executable downloads tracked | $executableDownloadCount |
| Executable downloads metadata complete | $executableMetadataCompleteCount |
| Executable downloads missing checksums | $executableChecksumGapCount |
| Executable downloads missing attestation | $executableAttestationGapCount |
| Executable trust top priority | $executableShortlistTopRepo |
| Userscript installs checked | $userscriptInstallCount |
| Userscript trust warnings | $userscriptWarningCount |
| Userscript release-channel keep-branch | $userscriptReleaseKeepBranchCount |
| Userscript release-channel ready | $userscriptReleaseReadyCount |
| Userscript release-channel blocked | $userscriptReleaseBlockedCount |
| Link targets checked | $($linkSummary.targetCount) |
| README action link targets | $readmeActionTargetCount |
| README install snippet targets | $readmeInstallSnippetTargetCount |
| README download link targets | $readmeDownloadLinkTargetCount |
| README userscript install targets | $readmeUserscriptInstallTargetCount |
| Link failures | $linkFailureCount |
| Link warnings | $linkWarningCount |
| Metadata provider | $metadataProvider |
| Metadata GraphQL page size | $metadataGraphQlPageSize |
| Metadata request count | $metadataRequestCount |
| Metadata retry count | $metadataRetryCount |
| Metadata repo count | $metadataRepoCount |
| Metadata truncated | $metadataTruncated |
| Metadata resource-limit fallback | $metadataResourceLimitFallback |
| Metadata fallback reason | $metadataFallbackReason |
| Metadata resource-limit reason | $metadataResourceLimitReason |
| REST fallback release status | $restFallbackStatus |
| REST fallback release max requests | $restFallbackMaxReleaseFetches |
| REST fallback release unauth cap | $restFallbackUnauthenticatedReleaseFetchLimit |
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
| Generated PR status handoff | $generatedPrWriteStatusHandoffImplemented |
| Generated PR status context | $generatedPrWriteStatusHandoffContext |
| Generated PR status state | $generatedPrWriteStatusHandoffState |
| Generated PR status permission | $generatedPrWriteStatusHandoffPermission |
| Generated PR status proof | $generatedPrWriteStatusHandoffProof |
| Direct-main maintenance policy | $directMainMaintenancePolicyStatus |
| Direct-main maintenance allowed | $directMainMaintenancePolicyAllowed |
| Direct-main maintenance recommendation | $directMainMaintenancePolicyRecommendation |
| Candidate check exercise plan | $candidateCheckExercisePlanStatus |
| Candidate check exercise readiness | $candidateCheckExerciseReadiness |
| Candidate check exercise plan evidence | $candidateCheckExercisePlanEvidenceStatus |
| Candidate check exercise candidates | $candidateCheckExerciseCandidateCount |
| Candidate check exercise branch prefix | $candidateCheckExerciseBranchPrefix |
| Candidate check exercise touch paths | $candidateCheckExerciseTouchPaths |
| Candidate check exercise latest evidence | $candidateCheckExerciseLatestStatus |
| Candidate check exercise PR | $candidateCheckExerciseLatestPullRequest |
| Candidate check exercise passed checks | $candidateCheckExerciseLatestSuccessful |
| Candidate check exercise failed checks | $candidateCheckExerciseLatestFailed |
| Candidate check exercise failed names | $candidateCheckExerciseLatestFailedNames |
| Candidate check exercise cleanup | $candidateCheckExerciseLatestCleanup |
| Routine PR drill evidence available | $routineMaintenancePrDrillAvailable |
| Routine PR drill status | $routineMaintenancePrDrillStatus |
| Routine PR drill pull request | $routineMaintenancePrDrillPullRequest |
| Routine PR drill passed checks | $routineMaintenancePrDrillSuccessful |
| Routine PR drill failed checks | $routineMaintenancePrDrillFailed |
| Routine PR drill cleanup | $routineMaintenancePrDrillCleanup |
| Required check enforcement evidence | $requiredCheckEnforcementAvailable |
| Required check enforcement status | $requiredCheckEnforcementStatus |
| Required check enforcement mechanism | $requiredCheckEnforcementMechanism |
| Required check enforcement PR | $requiredCheckEnforcementPullRequest |
| Required check enforcement passed checks | $requiredCheckEnforcementSuccessful |
| Required check enforcement failed checks | $requiredCheckEnforcementFailed |
| Required check enforcement cleanup | $requiredCheckEnforcementCleanup |
| Review policy posture | $reviewPolicyStatus |
| Review policy recommendation | $reviewPolicyRecommendation |
| PR reviews required | $reviewPolicyPrReviewsRequired |
| Code-owner reviews required | $reviewPolicyCodeOwnerReviewsRequired |
| Review policy reviewer model | $reviewPolicyReviewerModel |
| Scorecard CodeReview classification | $reviewPolicyScorecardClassification |
| Dependabot security posture | $dependabotSecurityStatus |
| Dependabot security recommendation | $dependabotSecurityRecommendation |
| Dependabot security updates enabled | $dependabotSecurityUpdatesEnabled |
| Dependabot local config present | $dependabotConfigPresent |
| Dependabot local config ecosystems | $dependabotConfigEcosystems |
| Code scanning status | $codeScanningStatus |
| Code scanning recommendation | $codeScanningRecommendation |
| Code scanning languages | $codeScanningLanguages |
| Code scanning local controls | $codeScanningLocalControls |
| Code scanning hosted controls | $codeScanningHostedControls |
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

if ($artifactDriftDiagnostics -and ($report.readmeInSync -ne $true -or $report.projectsExportInSync -ne $true -or $report.profileAssetsInSync -ne $true)) {
    $detailLines = New-Object System.Collections.Generic.List[string]
    $detailLines.Add("")
    $detailLines.Add("#### Generated Artifact Drift")
    $detailLines.Add("")
    $remediationCommand = [string](Get-ObjectPropertyOrDefault -Object $artifactDriftDiagnostics -Name "remediationCommand" -Default "pwsh -NoLogo -NoProfile -File ./scripts/sync-profile.ps1 -Write")
    $detailLines.Add("Remediation: ``$remediationCommand``")
    $detailLines.Add("")
    $detailLines.Add("| Artifact | Current SHA-256 | Expected SHA-256 | First differing line | Section | Current | Expected |")
    $detailLines.Add("| --- | --- | --- | ---: | --- | --- | --- |")

    foreach ($diagnostic in @($artifactDriftDiagnostics.readme, $artifactDriftDiagnostics.projects)) {
        if ($diagnostic -and $diagnostic.inSync -ne $true) {
            $firstDiff = Get-ObjectPropertyOrDefault -Object $diagnostic -Name "firstDiff"
            $line = if ($firstDiff -and $null -ne $firstDiff.line) { [int]$firstDiff.line } else { 0 }
            $section = ""
            if ($firstDiff -and $firstDiff.PSObject.Properties.Name -contains 'sectionMarker' -and $firstDiff.sectionMarker) {
                $section = [string](Get-ObjectPropertyOrDefault -Object $firstDiff.sectionMarker -Name "text" -Default "")
            }
            $current = if ($firstDiff) { [string](Get-ObjectPropertyOrDefault -Object $firstDiff -Name "current" -Default "") } else { "" }
            $expected = if ($firstDiff) { [string](Get-ObjectPropertyOrDefault -Object $firstDiff -Name "expected" -Default "") } else { "" }
            $detailLines.Add("| $(ConvertTo-MarkdownCell ([string]$diagnostic.artifact)) | ``$($diagnostic.currentSha256)`` | ``$($diagnostic.expectedSha256)`` | $line | $(ConvertTo-MarkdownCell $section) | $(ConvertTo-MarkdownCell $current) | $(ConvertTo-MarkdownCell $expected) |")
        }
    }

    $assets = Get-ObjectPropertyOrDefault -Object $artifactDriftDiagnostics -Name "assets"
    $affectedAssets = if ($assets -and $assets.PSObject.Properties.Name -contains 'affectedAssets') { @($assets.affectedAssets | Where-Object { $_.fatal -eq $true }) } else { @() }
    if ($affectedAssets.Count -gt 0) {
        $detailLines.Add("")
        $detailLines.Add("| Asset | Exists | Current SHA-256 | Expected SHA-256 |")
        $detailLines.Add("| --- | ---: | --- | --- |")
        foreach ($asset in $affectedAssets) {
            $currentHash = [string](Get-ObjectPropertyOrDefault -Object $asset -Name "currentSha256" -Default "")
            $expectedHash = [string](Get-ObjectPropertyOrDefault -Object $asset -Name "expectedSha256" -Default "")
            $detailLines.Add("| $(ConvertTo-MarkdownCell ([string]$asset.path)) | $($asset.exists) | ``$currentHash`` | ``$expectedHash`` |")
        }
    }

    $summary = $summary.TrimEnd() + "`n" + ($detailLines -join "`n") + "`n"
}

if ((Get-Count $metadataHandoffTopicRows) -gt 0 -or (Get-Count $metadataHandoffDescriptionRows) -gt 0) {
    $detailLines = New-Object System.Collections.Generic.List[string]
    $detailLines.Add("")
    $detailLines.Add("#### Metadata Hygiene Handoff")
    $detailLines.Add("")
    $detailLines.Add("Only public-safe rows are shown; suppressed, private, and unsafe repository names stay summarized by count.")
    $detailLines.Add("")
    $detailLines.Add("| Kind | Repo | Category | Action | Command or guidance |")
    $detailLines.Add("| --- | --- | --- | --- | --- |")

    foreach ($row in $metadataHandoffTopicRows) {
        $repoLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "repo" -Default "")
        $categoryLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "category" -Default "")
        $hints = @((Get-ObjectPropertyOrDefault -Object $row -Name "topicHints" -Default @()) | ForEach-Object { [string]$_ }) -join ", "
        $command = [string](Get-ObjectPropertyOrDefault -Object $row -Name "command" -Default "")
        $commandCell = if ([string]::IsNullOrWhiteSpace($command)) { "" } else { "``$command``" }
        $detailLines.Add("| Topics | $(ConvertTo-MarkdownCell $repoLabel) | $(ConvertTo-MarkdownCell $categoryLabel) | $(ConvertTo-MarkdownCell $hints) | $(ConvertTo-MarkdownCell $commandCell) |")
    }

    foreach ($row in $metadataHandoffDescriptionRows) {
        $repoLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "repo" -Default "")
        $categoryLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "category" -Default "")
        $catalogDescription = [string](Get-ObjectPropertyOrDefault -Object $row -Name "catalogDescription" -Default "")
        $guidance = [string](Get-ObjectPropertyOrDefault -Object $row -Name "catalogPatchGuidance" -Default "")
        $command = [string](Get-ObjectPropertyOrDefault -Object $row -Name "command" -Default "")
        $action = if ([string]::IsNullOrWhiteSpace($catalogDescription)) { $guidance } else { $catalogDescription }
        $commandOrGuidance = if ([string]::IsNullOrWhiteSpace($command)) { $guidance } else { "``$command``" }
        $detailLines.Add("| Description | $(ConvertTo-MarkdownCell $repoLabel) | $(ConvertTo-MarkdownCell $categoryLabel) | $(ConvertTo-MarkdownCell $action) | $(ConvertTo-MarkdownCell $commandOrGuidance) |")
    }

    $summary = $summary.TrimEnd() + "`n" + ($detailLines -join "`n") + "`n"
}

if ($fatalDriftRows.Count -gt 0) {
    $detailLines = New-Object System.Collections.Generic.List[string]
    $detailLines.Add("")
    $detailLines.Add("#### Fatal Metadata Drift Details")
    $detailLines.Add("")
    $detailLines.Add("| Repo | Category | Field | Current | Expected |")
    $detailLines.Add("| --- | --- | --- | --- | --- |")
    foreach ($row in $fatalDriftRows) {
        $repoLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "repo" -Default "top-level")
        $categoryLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "category" -Default "top-level")
        $fieldLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "field" -Default "unknown")
        $currentValue = ConvertTo-CompactSummaryValue (Get-ObjectPropertyOrDefault -Object $row -Name "oldValue")
        $expectedValue = ConvertTo-CompactSummaryValue (Get-ObjectPropertyOrDefault -Object $row -Name "newValue")
        $detailLines.Add("| $(ConvertTo-MarkdownCell $repoLabel) | $(ConvertTo-MarkdownCell $categoryLabel) | $(ConvertTo-MarkdownCell $fieldLabel) | $(ConvertTo-MarkdownCell $currentValue) | $(ConvertTo-MarkdownCell $expectedValue) |")
    }
    $summary = $summary.TrimEnd() + "`n" + ($detailLines -join "`n") + "`n"
}

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
    foreach ($row in $fatalDriftRows) {
        $repoLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "repo" -Default "top-level")
        $categoryLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "category" -Default "top-level")
        $fieldLabel = [string](Get-ObjectPropertyOrDefault -Object $row -Name "field" -Default "unknown")
        $currentValue = ConvertTo-CompactSummaryValue (Get-ObjectPropertyOrDefault -Object $row -Name "oldValue") -MaxLength 120
        $expectedValue = ConvertTo-CompactSummaryValue (Get-ObjectPropertyOrDefault -Object $row -Name "newValue") -MaxLength 120
        $annotation = "repo=$repoLabel; category=$categoryLabel; field=$fieldLabel; current=$currentValue; expected=$expectedValue"
        Write-Output "::error file=projects.json,title=Fatal metadata drift::$(ConvertTo-GitHubAnnotationValue $annotation)"
    }
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

if ($evidenceReportBehindCommit) {
    Write-Output "::warning::Committed sync report ($evidenceReportGeneratedAt) is older than the latest report-affecting commit ($evidenceLatestCommitDate); regenerate and recommit the report."
}

if ($evidenceSmokeStale) {
    Write-Output "::warning::Committed rendered-smoke status is $evidenceSmokeStatus without local source metadata; run scripts/render-profile-smoke.ps1 locally and regenerate the report."
}

if ($scheduledWorkflowFailingCount -gt 0 -or $scheduledWorkflowStaleCount -gt 0) {
    foreach ($row in $scheduledWorkflowRows) {
        $rowStatus = [string](Get-ObjectPropertyOrDefault -Object $row -Name "status")
        if ($rowStatus -eq "failing" -or $rowStatus -eq "stale" -or $rowStatus -eq "disabled") {
            $rowWarning = [string](Get-ObjectPropertyOrDefault -Object $row -Name "warning")
            $workflowFile = [string](Get-ObjectPropertyOrDefault -Object $row -Name "workflowFile" -Default "")
            $annotation = if ([string]::IsNullOrWhiteSpace($rowWarning)) { "Scheduled workflow $workflowFile is $rowStatus." } else { $rowWarning }
            $annotationFile = ConvertTo-GitHubAnnotationProperty $workflowFile
            $annotationTitle = ConvertTo-GitHubAnnotationProperty "Scheduled workflow $rowStatus"
            Write-Output "::warning file=$annotationFile,title=$annotationTitle::$(ConvertTo-GitHubAnnotationValue $annotation)"
        }
    }
}

if ($scheduledWorkflowUnavailableCount -gt 0) {
    Write-Output "::notice::Profile sync report could not evaluate $scheduledWorkflowUnavailableCount scheduled workflow(s) (run evidence unavailable, e.g. offline or unauthenticated)."
}

if ($executableChecksumGapCount -gt 0) {
    Write-Output "::notice::Profile sync report shortlists $executableChecksumGapCount executable-download repo(s) without filename-derived checksum coverage (top priority: $executableShortlistTopRepo)."
}

if ($imageAltTextIssueCount -gt 0) {
    Write-Output "::warning::Profile sync report found $imageAltTextIssueCount generated README <img> tag(s) missing descriptive alt text."
}

if ($headingSkippedLevelCount -gt 0) {
    Write-Output "::warning::Profile sync report found $headingSkippedLevelCount skipped README heading level(s)."
}

if ($rootMarkdownWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report found $rootMarkdownWarningCount root Markdown file(s) outside the documentation contract: $rootMarkdownUnexpected."
}

if ($svgContrastFailingAssets -gt 0) {
    Write-Output "::warning::Profile sync report found $svgContrastFailingAssets profile SVG asset(s) with text color contrast below WCAG minimums."
}

if ($roadmapHygieneWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report found $roadmapHygieneWarningCount open roadmap entry(ies) already satisfied by committed files."
    foreach ($row in $roadmapHygieneRows) {
        $marker = [string](Get-ObjectPropertyOrDefault -Object $row -Name "marker")
        $reason = [string](Get-ObjectPropertyOrDefault -Object $row -Name "reason")
        Write-Output "::warning title=Stale roadmap entry::$(ConvertTo-GitHubAnnotationValue "$marker -- $reason")"
    }
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

if ($metadataResourceLimitFallback) {
    Write-Output "::warning::Profile sync metadata enumeration fell back after a GitHub API resource or rate-limit signal: $(ConvertTo-GitHubAnnotationValue $metadataResourceLimitReason)"
}

if ($metadataTruncated) {
    Write-Output "::warning::Profile sync metadata enumeration reached the configured GraphQL page size of $metadataGraphQlPageSize; lower or raise -GraphQlPageSize only after reviewing repo count evidence."
}

if ($missingLicenseCount -gt 0) {
    Write-Output "::warning::Profile sync report has $missingLicenseCount visitor-facing project(s) without detected license metadata."
}

if ($unresolvedUnknownLicenseCount -gt 0) {
    Write-Output "::warning::Profile sync report has $unresolvedUnknownLicenseCount visitor-facing project(s) with unresolved non-standard license metadata."
}

if ($intentionalLicenseExceptionCount -gt 0) {
    Write-Output "::notice::Profile sync report has $intentionalLicenseExceptionCount documented non-standard license exception(s)."
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

if ($runtimeStatus -eq "fail") {
    Write-Output "::error::Profile sync report was generated under unsupported PowerShell runtime $runtimeVersion ($runtimeChannel)."
} elseif ($runtimeWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $runtimeWarningCount PowerShell runtime posture warning(s)."
}

if ($runtimeWarningCount -gt 0 -and $runtimeSecurity -and $runtimeSecurity.PSObject.Properties.Name -contains 'warnings') {
    foreach ($warning in @($runtimeSecurity.warnings)) {
        Write-Output "::warning title=PowerShell runtime posture::$(ConvertTo-GitHubAnnotationValue ([string]$warning))"
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

if ($candidateCheckExerciseLatestAvailable -and $candidateCheckExerciseLatestStatus -ne "passed") {
    Write-Output "::warning::Candidate check exercise evidence is $candidateCheckExerciseLatestStatus; failed candidate checks: $candidateCheckExerciseLatestFailedNames."
}

if ($requiredCheckEnforcementAvailable -and $requiredCheckEnforcementStatus -ne "passed") {
    Write-Output "::warning::Required-check enforcement evidence is $requiredCheckEnforcementStatus; failed candidate checks: $requiredCheckEnforcementFailed."
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
