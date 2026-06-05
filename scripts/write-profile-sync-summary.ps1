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
$releaseDrift = $report.releaseAssetDrift
$linkSummary = $report.linkValidationSummary
$driftSummary = $report.metadataDriftSummary
$performance = $report.validationPerformance

$missingTopicCount = Get-Count $metadataHygiene.missingTopics
$missingDescriptionCount = Get-Count $metadataHygiene.missingDescriptions
$fatalDriftCount = [int]$driftSummary.fatalCount
$linkFailureCount = Get-Count $report.linkValidationFailures
$linkWarningCount = Get-Count $report.linkValidationWarnings
$releaseRowsChecked = [int]$releaseDrift.checkedCatalogRows
$validationElapsedMs = [int]$performance.linkValidation.elapsedMs

$summary = @"
### $Context report

| Field | Value |
| --- | ---: |
| README in sync | $($report.readmeInSync) |
| Projects export in sync | $($report.projectsExportInSync) |
| Profile assets in sync | $($report.profileAssetsInSync) |
| Schema validation passed | $($report.schemaValidation.passed) |
| Planning docs aligned | $($report.docVersionConsistency.passed) |
| Fatal metadata drift | $fatalDriftCount |
| Missing topic hints | $missingTopicCount |
| Missing descriptions | $missingDescriptionCount |
| Release rows checked | $releaseRowsChecked |
| Link targets checked | $($linkSummary.targetCount) |
| Link failures | $linkFailureCount |
| Link warnings | $linkWarningCount |
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

if ($linkFailureCount -gt 0) {
    Write-Output "::error::Profile sync report has $linkFailureCount fatal link failure(s)."
}

if ($linkWarningCount -gt 0) {
    Write-Output "::warning::Profile sync report has $linkWarningCount transient link warning(s)."
}
