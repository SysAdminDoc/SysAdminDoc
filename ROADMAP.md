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

- [ ] P0 — Fix PSScriptAnalyzer unused parameters in `New-DiscoverySection`
  Why: `New-DiscoverySection` declares `$Entries` and `$Repos` parameters (lines 1779-1780) that are never used inside the function body. PSScriptAnalyzer `PSReviewUnusedParameter` flags both, failing the Tests workflow on every push.
  Evidence: `gh run list --workflow=tests.yml` shows PSScriptAnalyzer failure; CI log output: "PSScriptAnalyzer reported 2 finding(s)."
  Touches: `scripts/sync-profile.ps1` (function `New-DiscoverySection` at line 1777 and call site at line 2620).
  Acceptance: Remove the unused `$Entries` and `$Repos` parameters from the function signature and the corresponding `-Entries $entries -Repos $Repos` arguments from the call site; PSScriptAnalyzer passes with 0 findings.
  Complexity: S

- [ ] P1 — Migrate attestation action from `actions/attest-build-provenance` to `actions/attest`
  Why: `actions/attest-build-provenance` is now a thin wrapper around `actions/attest`. GitHub's documentation recommends new implementations use `actions/attest` directly, which also supports SBOM attestation via `predicate-type` without needing the separate `actions/attest-sbom` action.
  Evidence: `actions/attest-build-provenance` README; `.github/workflows/profile-sync.yml` write-pr job uses `actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32`.
  Touches: `.github/workflows/profile-sync.yml`, `tests/sync-profile.Tests.ps1`.
  Acceptance: The write-pr job uses `actions/attest` with SHA-pinned reference and `predicate-type: https://slsa.dev/provenance/v1`; Pester guards the updated action reference; attestation verification still works via `gh attestation verify`.
  Complexity: S

- [ ] P1 — Resolve 13 missing fork-parent catalog attributions
  Why: 13 GitHub forks have no `forkOf` in `data/profile-catalog.json`. The report classifies these as warning-only under `forkParentDrift.missingCatalogAttribution`, but the attribution debt grows with each new fork.
  Evidence: `reports/profile-sync-report.json.forkParentDrift.missingCatalogAttribution` lists: `android-foss`, `awesome-privacy`, `CL4R1T4S`, `ews`, `foss-apps`, `Gmail-MCP-Server`, `hermes-webui`, `notepad-plus-plus`, `NotepadNext`, `qBittorrent-Enhanced-Edition`, `stylus`, `vcpkg`, `youtube-mcp-server`.
  Touches: `data/profile-catalog.json`, `reports/profile-sync-report.json`.
  Acceptance: Each fork has a `forkOf` field matching the `forkParentDrift.missingCatalogAttribution.githubParent` value; `forkParentDrift.missingCatalogAttributionCount` drops to 0; suppressed forks also carry `upstreamLicense` where available.
  Complexity: S

- [ ] P1 — Verify markdown-it CVE-2025-7969 coverage
  Why: CVE-2025-7969 reports an XSS vulnerability in markdown-it fenced code block rendering via unsanitized HTML. The repo pins markdown-it to 14.2.0 via `package.json` overrides, which addresses CVE-2026-48988 (smartquotes DoS). CVE-2025-7969 needs verification that 14.2.0 also covers it, or a further pin bump.
  Evidence: Snyk advisory SNYK-JS-MARKDOWNIT-12143043; `package.json` override `"markdown-it": "14.2.0"`; `npm ls markdown-it` confirms 14.2.0.
  Touches: `package.json`, `package-lock.json`.
  Acceptance: Confirm the XSS fix is included in 14.2.0 or bump the override to the patch version that includes it; `npm audit` shows no markdown-it advisories.
  Complexity: S

- [ ] P3 — Evaluate Pester `ExcludeTests` coverage option
  Why: Pester 5.7.0 added `CodeCoverage.ExcludeTests` which prevents test files themselves from inflating line-coverage numbers. The current Pester configuration does not use this option.
  Evidence: Pester 5.7.0 release notes; `.github/workflows/tests.yml` Pester configuration block.
  Touches: `.github/workflows/tests.yml`, `tests/sync-profile.Tests.ps1`.
  Acceptance: Enable `$config.CodeCoverage.ExcludeTests = $true` in the CI Pester config; verify the coverage floor (78%) still holds after test-file lines are excluded; adjust the floor if the measured baseline changes.
  Complexity: S

- [ ] P3 — Target PowerShell 7.6 LTS as preferred CI runtime
  Why: PowerShell 7.6.3 is the current LTS (supported through Nov 2028, .NET 10 base). The repo requires 7.4+ but GitHub Actions runners are migrating to 7.6 as the bundled `pwsh`. The 7.4 LTS support ends Nov 2026.
  Evidence: PowerShell support lifecycle docs; `#Requires -Version 7.4` in `scripts/sync-profile.ps1`; `Write-Host "PowerShell runtime: $($PSVersionTable.PSVersion)"` in tests.yml.
  Touches: `scripts/sync-profile.ps1`, `CLAUDE.md`.
  Acceptance: `#Requires -Version 7.4` stays as the minimum (backward compat); CI logs confirm `pwsh` 7.6+ is the tested runtime; no 7.6-specific features are required yet; CLAUDE.md notes the preferred runtime.
  Complexity: S
