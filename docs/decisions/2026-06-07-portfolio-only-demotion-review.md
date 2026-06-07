# Portfolio-Only Demotion Review

Date: 2026-06-07
Status: Approved for staged catalog change

## Decision

Approve moving the current 11 README portfolio-only review candidates to
portfolio-only browsing in a future catalog mutation pass.

The approved rows are `CSV_Power_Tool`, `Flux`, `PillSleepTracker`,
`UniversalCompiler`, `GmailDownloader`, `bypassnroGen`, `LipSight`, `PDFedit`,
`QR-Code-Generator-Pro`, `Stock-Video-Collector`, and `Tunerize`.

This decision does not mutate `data/profile-catalog.json`, `README.md`, or
`projects.json`. It records that the evidence is sufficient for the next
implementation pass to change catalog inclusion flags for only the approved
rows.

## Implementation Follow-up

Implemented in v4.9.95. The approved rows now use `includeInReadme=false` and
`includeInPortfolio=true`, which removes them from generated README output while
keeping them in `projects.json` for portfolio browsing.

## Rationale

The existing README density decision kept the README as the public routing
surface until concrete candidates were reviewed. That review is now complete
enough for the current candidate set:

- The candidates are non-featured, non-currently-building, repo-only Python
  rows selected by the deterministic report policy.
- Each candidate carries a catalog review note that held README inclusion until
  explicit demotion approval.
- The report-only preview reduces README project rows from 177 to 166.
- The Python category drops from 41 rows to the 30-row soft limit.
- No other category becomes over budget; the preview largest category becomes
  PowerShell at 30 rows.
- Portfolio routes remain preserved.

## Guardrails

- Apply the catalog change in a separate pass so the mutation is easy to audit.
- Change only the 11 approved rows unless a fresh report identifies a new
  decision set.
- Keep every approved repo public and reachable through the portfolio feed.
- Re-run `scripts/sync-profile.ps1 -Write -Check` after mutation and verify
  `readmeDensity.portfolioOnlyPreview` no longer recommends these same rows.
- Do not demote featured, currently-building, install-first, live-demo, or
  release-download rows without a separate decision.

## Evidence

- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyCandidateCount`:
  `11`
- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyPreview.status`:
  `ready`
- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyPreview.projectRowDelta`:
  `-11`
- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyPreview.previewProjectRowCount`:
  `166`
- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyPreview.remainingOverSoftLimitCategoryCount`:
  `0`
- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyPreview.preservesPortfolioRoutes`:
  `true`
- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyPreview.catalogMutated`:
  `false`
