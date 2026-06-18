# Roadmap

## Research-Driven Additions

- [ ] P0 - Restore green hosted scheduled workflow evidence
  Why: Local and push checks are green, but the latest hosted scheduled Profile sync, Profile assets refresh, and Workflow security runs are still failed.
  Evidence: `gh run list`; `reports/profile-sync-report.json.scheduledWorkflowFreshness`; runs `27607877014`, `27680916293`, `27683950030`.
  Touches: `.github/workflows/profile-sync.yml`, `.github/workflows/assets-refresh.yml`, `.github/workflows/workflow-security.yml`, `scripts/sync-profile.ps1`, `scripts/write-profile-sync-summary.ps1`, `reports/profile-sync-report.json`.
  Acceptance: manual reruns or next scheduled runs for all three workflows complete successfully, the sync report records fresh hosted evidence, and no stale scheduled-failure warning remains for already-fixed code.
  Complexity: M

- [ ] P0 - Resolve the Dependabot auto-merge dangerous-trigger finding
  Why: Workflow security still has hosted failed evidence around `pull_request_target`; the repo should either remove that trigger or provide a scanner-recognized hardened exception.
  Evidence: `.github/workflows/dependabot-auto-merge.yml`; `zizmor --strict-collection`; `zizmor` dangerous-triggers docs; hosted run `27683950030`.
  Touches: `.github/workflows/dependabot-auto-merge.yml`, `.github/workflows/workflow-security.yml`, `tests/sync-profile.Tests.ps1`, `scripts/sync-profile.ps1`.
  Acceptance: `actionlint`, `zizmor --strict-collection --collect=workflows --collect=actions .github`, and `poutine analyze_local .github/workflows` pass or produce only intentional warning-only findings; Pester guards the final Dependabot trigger/permission pattern.
  Complexity: M

- [ ] P1 - Make report evidence freshness post-commit-aware
  Why: A valid generated report becomes immediately stale once committed because the report-affecting commit is the commit that contains the report.
  Evidence: `reports/profile-sync-report.json.evidenceFreshness.status`; `Get-LatestReportAffectingCommit` in `scripts/sync-profile.ps1`.
  Touches: `scripts/sync-profile.ps1`, `scripts/write-profile-sync-summary.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`, `reports/profile-sync-report.json`.
  Acceptance: A report generated and committed with code/artifact changes is classified separately from genuinely stale reports, with tests covering same-commit report evidence and older committed report evidence.
  Complexity: M

- [ ] P1 - Reconcile required-check enforcement with live branch/ruleset state
  Why: Candidate checks are defined, but `main` has no branch protection or repository rulesets, leaving Scorecard Branch-Protection open and report readiness at `needs-live-validation`.
  Evidence: `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection` returns 404; `gh api repos/SysAdminDoc/SysAdminDoc/rulesets` returns `[]`; `reports/profile-sync-report.json.repositorySettings.requiredCheckReadiness`.
  Touches: `scripts/sync-profile.ps1`, `.github/workflows/tests.yml`, `.github/workflows/profile-sync.yml`, `.github/workflows/workflow-security.yml`, `tests/sync-profile.Tests.ps1`.
  Acceptance: Required-check readiness reports either an enabled ruleset/branch-protection configuration with the six candidate checks or an explicit direct-main bypass policy with no stale proof fields.
  Complexity: L

- [ ] P1 - Promote GitHub release asset digests to first-class release trust evidence
  Why: GitHub now exposes SHA-256 asset digests, but the report still mixes platform digests with filename-derived sidecar checksum gaps.
  Evidence: `reports/profile-sync-report.json.releaseAssetDrift.platformDigestCoverage`; GitHub release asset digest changelog and REST/GraphQL release asset docs.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-projects.v1.json`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`, `projects.json`, `reports/profile-sync-report.json`.
  Acceptance: `releaseTrust` and `releaseAssetDrift` separately report platform digest coverage, sidecar checksum coverage, complete executable coverage, and next actions; shortlist rows no longer say `hasChecksum=false` when platform digest evidence is present.
  Complexity: M

- [ ] P1 - Add immutable-release, attestation, and SBOM readiness lanes for executable releases
  Why: The report finds 65 executable download rows with 65 attestation gaps and 64 SBOM gaps, while GitHub immutable releases and artifact/SBOM attestations are now platform-supported.
  Evidence: `reports/profile-sync-report.json.releaseAssetDrift.executableDownloadTrustShortlist`; GitHub artifact attestations docs; GitHub immutable releases docs; CycloneDX/SPDX/SLSA sources.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`, `reports/profile-sync-report.json`.
  Acceptance: The report groups executable releases into digest-only, attested, SBOM-present, immutable, and fully-evidenced buckets, with top-priority repo/tag/asset rows and exact next-action labels.
  Complexity: L

- [ ] P2 - Add GitHub API rate-limit and fallback telemetry to profile sync
  Why: GraphQL resource limits and 502s are a recurring reliability risk for a 202-repo metadata snapshot.
  Evidence: `Get-GitHubRepos`, `Add-ReleaseAssetMetadata`, `validationPerformance.restFallbackReleaseFetch`; GitHub GraphQL resource-limit and REST secondary-rate-limit docs.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`, `reports/profile-sync-report.json`.
  Acceptance: The sync report records GraphQL/REST rate-limit headroom where available, retry counts, fallback reasons, release-enrichment duration, and whether metadata fidelity was degraded.
  Complexity: M

- [ ] P2 - Prove generated profile PR validation and status handoff end to end
  Why: Required-check readiness still has mostly null generated-PR write evidence even though the generated PR scripts and status handoff exist.
  Evidence: `reports/profile-sync-report.json.repositorySettings.requiredCheckReadiness.prDeliveryTransition.generatedPrWriteEvidence`; `scripts/open-generated-profile-pr.ps1`; `.github/workflows/profile-sync.yml`.
  Touches: `.github/workflows/profile-sync.yml`, `.github/workflows/assets-refresh.yml`, `scripts/open-generated-profile-pr.ps1`, `scripts/set-generated-validation-status.ps1`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: A dry-run and one real generated PR exercise records branch, PR, dispatched validation run, status context, status state, cleanup result, and check-rollup evidence in the sync report.
  Complexity: M

- [ ] P2 - Apply safe topic and description metadata hygiene fixes
  Why: The current report still shows 16 missing-topic repos and one missing public description, while `-ApplyTopics` exists but the allowlist is empty.
  Evidence: `reports/profile-sync-report.json.metadataHygiene`; `data/topic-allowlist.json`; `sync-profile.ps1 -ApplyTopics`.
  Touches: `data/topic-allowlist.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, `reports/profile-sync-report.json`.
  Acceptance: Allowlisted topic updates are applied only to intended public repos, the one missing description is either fixed or explicitly dispositioned, and `metadataHygiene` records reduced counts without mutating non-allowlisted repos.
  Complexity: S

- [ ] P2 - Add a downstream portfolio feed contract check
  Why: `projects.json` is consumed by `SysAdminDoc/sysadmindoc.github.io`; this repo should catch feed-shape regressions before the portfolio import breaks.
  Evidence: `projects.json`; `portfolioCompatibility`; `SysAdminDoc/sysadmindoc.github.io` importer dependency.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-projects.v1.json`, `tests/sync-profile.Tests.ps1`, `reports/profile-sync-report.json`.
  Acceptance: Tests or a report section validate the current feed against the downstream importer-required fields and visible/suppressed row expectations, including duplicate visible repo rejection.
  Complexity: M
