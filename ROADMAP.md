# Roadmap

## Research-Driven Additions (2026-06-09)

### Now (immediate, high impact, low-medium effort)

### Next (near-term, moderate effort)

### Later (backlog, larger effort or lower priority)

- [ ] **Submit to awesome lists** -- Per the v4.9.11 awesome-list candidate plan, submit Network_Security_Auditor and win11-nvme-driver-patcher to `awesome-foss/awesome-sysadmin`; UserScript-Finder and Astra-Deck to `awesome-scripts/awesome-userscripts`; the SysAdminDoc profile itself to `abhisheknaiidu/awesome-github-profile-readme` under data-driven automation. Requires each project to meet list-specific criteria (FOSS license, active maintenance, quality README). Impact: 3, Effort: M.

- [ ] **Add rendered-smoke mobile viewport overflow regression gate** -- The rendered profile smoke currently reports mobile viewport overflow as a warning. Promote it to a fatal check once the current 0-warning baseline is confirmed stable across 3+ consecutive runs. Impact: 2, Effort: S.

- [ ] **Investigate PowerShell 7 native JSON Schema validation** -- `Test-Json -SchemaFile` in PowerShell 7.4+ uses JsonSchema.NET natively. Evaluate whether the custom `Test-JsonSchemaContract` function in sync-profile.ps1 can be replaced with the built-in cmdlet, reducing custom validation code. Known caveat: some PowerShell 7.4.0 schema bugs (GitHub issue #20743). Impact: 2, Effort: M.

- [ ] **Add sync-profile.ps1 function-level documentation** -- The script exports 100+ functions via the test seam but lacks parameter-level documentation or synopsis comments. Adding `[CmdletBinding()]` and `.SYNOPSIS`/`.PARAMETER` blocks to key public functions would improve maintainability and enable auto-generated docs. Impact: 2, Effort: L.

- [ ] **Evaluate migration from branch protection to repository rulesets** -- GitHub rulesets support organization-wide enforcement and bypass-actor audit logs, but currently lack per-rule exemptions that branch protection provides via `enforce_admins`. Monitor GitHub's ruleset feature maturity before migrating. Impact: 2, Effort: L.

### Under Consideration

- [ ] **Portfolio-only demotion for low-signal README rows** -- The `readmeDensity` report identifies 11 Python rows as portfolio-only candidates with catalog `readmeReviewNote` context. If the README approaches the 96KB soft limit, these rows can be demoted to portfolio-only (visible on sysadmindoc.github.io but not in the GitHub README). Currently informational. Impact: 2, Effort: M.

- [ ] **Add contribution-graph or streak visualization** -- Self-hosted (committed SVG) contribution visualization similar to Platane/snk or github-readme-stats streak. Would require a new GitHub Action step to generate the SVG from the contributions API. Lower priority because the current profile focuses on project catalog rather than activity metrics. Impact: 1, Effort: M.

## Research-Driven Additions (2026-06-10)

### P1 — trust / reliability

- [ ] P2 — Confirm hosted profile sync and assets-refresh runs after the v4.9.125 branch lands
  Why: Local v4.9.125 generation has 0 fatal metadata drift rows and profile assets are in sync, but the previously failing hosted schedules need post-merge GitHub Actions evidence.
  Where: `.github/workflows/profile-sync.yml`, `.github/workflows/assets-refresh.yml`, `reports/profile-sync-report.json`
  Acceptance: next scheduled or manually dispatched Profile sync and Profile assets refresh runs complete successfully on GitHub.
  Complexity: S

### P2 — leapfrog / hardening bets

- [ ] P2 — Surface GitHub release immutability in releaseTrust and enable immutable releases on flagship repos
  Why: Immutable releases are GA with signed Sigstore release attestations and tag locking; the REST release payload already returns an `immutable` boolean the generator discards — recording it upgrades filename-derived trust heuristics to a platform-verified signal no competitor surfaces.
  Evidence: GitHub changelog 2025-10-28 (immutable releases GA); observed `"immutable": true/false` fields in api.github.com release responses; CLAUDE.md v4.9.44 releaseTrust constraint ("unless explicit verification paths are added later").
  Touches: `scripts/sync-profile.ps1` (REST/GraphQL release fetch to capture `immutable`, extend `releaseTrust` and report aggregates), `schemas/profile-projects.v1.json`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`; repository settings on download-bearing repos (enable immutable releases).
  Acceptance: `projects.json` rows with releases carry an immutability field; sync report counts immutable vs mutable latest releases; at least the top-starred download repos publish immutable releases.
  Complexity: M

- [ ] P2 — Attest projects.json provenance with actions/attest-build-provenance
  Why: The feed already publishes self-reported SHA-256 provenance hashes; a Sigstore attestation generated in the write-pr workflow makes provenance externally verifiable with `gh attestation verify`, matching GitHub's guidance that hash-bearing manifests are attestation candidates.
  Evidence: actions/attest-build-provenance README; GitHub artifact-attestations docs ("manifests that include hashes of detailed contents"); `projects.json.provenance` hash design (CLAUDE.md v4.9.43).
  Touches: `.github/workflows/profile-sync.yml` write-pr job (`attestations: write` + `id-token: write` permissions, attest step pinned by SHA), feed provenance docs in `schemas/profile-projects.v1.json` description, `scripts/open-generated-profile-pr.ps1` summary link.
  Acceptance: `gh attestation verify projects.json -o SysAdminDoc` succeeds for a feed produced by the write-pr workflow; zizmor stays green on the added permissions.
  Complexity: M

- [ ] P2 — Pilot Harden-Runner egress auditing on CI jobs
  Why: Runner-level egress monitoring is the one widely adopted Actions hardening layer this CI lacks; audit mode catches exfiltration/compromised-dependency callouts with zero blocking risk, and findings inform a later block-mode allowlist.
  Evidence: step-security/harden-runner docs (audit vs block egress policies); existing zizmor/Scorecard posture in `.github/workflows/*`.
  Touches: `.github/workflows/tests.yml`, `profile-sync.yml`, `workflow-security.yml` (first step `step-security/harden-runner` SHA-pinned, `egress-policy: audit`), `requirements-ci`-style pin documentation, Pester workflow-contract tests.
  Acceptance: all jobs run with harden-runner audit insights available; documented tradeoff note records the added third-party dependency; no required check regresses. Roll back by removing the step if insights show no value after 4 weeks.
  Complexity: M

## Research-Driven Additions (2026-06-12)

### P1 — reliability / CI currency

- [ ] P1 — Compact sync report to recover soft-budget headroom
  Why: The committed report is 94,795 bytes (82.7% of the 114,688-byte soft limit). `repositorySettings` alone is 34% of the JSON; three sections account for 75%. One new report section could breach the budget.
  Evidence: `reports/profile-sync-report.json` byte count vs `artifactBudgets` soft limit; section-size analysis showing `repositorySettings` (24KB), `userscriptInstallTrust` (13KB), `releaseAssetDrift` (9.5KB) dominate.
  Touches: `scripts/sync-profile.ps1` (report-building functions), `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`
  Acceptance: committed report drops below 70% of its soft limit by moving per-row evidence detail into CI-only summary/annotation output while keeping aggregates in the committed JSON. Schema version stays compatible.
  Complexity: M

### P2 — hardening / observability

- [ ] P2 — Enable delete-branch-on-merge
  Why: Currently disabled (`deleteBranchOnMerge: false`). The `automation-branch-cleanup.yml` handles generated branches weekly, but enabling the native setting auto-cleans all merged PR branches immediately, reducing stale-branch noise and simplifying the cleanup workflow.
  Evidence: `repositorySettings.features.deleteBranchOnMerge: false` in sync report; GitHub docs on automatic head-branch deletion.
  Touches: Repository settings (GitHub API or UI), `scripts/sync-profile.ps1` (report the setting), `tests/sync-profile.Tests.ps1`
  Acceptance: `deleteBranchOnMerge` reports `true` in the sync report; merged PR branches are auto-deleted; protected branches remain unaffected.
  Complexity: S

- [ ] P2 — Enable secret-scanning non-provider patterns
  Why: Non-provider pattern scanning is disabled, meaning custom/internal secret formats are not caught. Enabling it adds broader coverage at zero configuration cost.
  Evidence: `repositorySettings.security.secretScanningNonProviderPatterns: "disabled"` in sync report.
  Touches: Repository settings (GitHub API or UI), `scripts/sync-profile.ps1` (report the setting)
  Acceptance: `secretScanningNonProviderPatterns` reports `enabled`; no false-positive alert volume regression after 2 weeks.
  Complexity: S

## Research-Driven Additions (2026-06-13)

### P1 — trust / security posture

- [ ] P1 — Enable Private Vulnerability Reporting (PVR)
  Why: PVR is free for all public repos but not toggled on. `SECURITY.md` references PVR with "when it is available" language. Enabling it provides researchers a structured private channel, satisfies the CII Best Practices vulnerability-reporting criterion, and completes the security posture without exposing private details.
  Evidence: SECURITY.md current wording; GitHub PVR GA announcement; CII Best Practices badge requirements (vulnerability reporting process with <14-day response).
  Touches: Repository settings (GitHub UI toggle), `SECURITY.md` (update conditional language to reference the live PVR channel)
  Acceptance: "Report a vulnerability" button is visible on the repository's Security/Advisories page; `SECURITY.md` no longer uses "when it is available" conditional language.
  Complexity: S

### P2 — trust signals / hardening

- [ ] P2 — Capture ReleaseAsset.digest from GraphQL for asset integrity verification
  Why: The GraphQL API added a `digest` field to `ReleaseAsset` (SHA digest, May 2025) providing platform-verified checksums without downloading assets. The generator currently uses filename-derived trust heuristics only. Capturing platform-provided digests upgrades trust metadata from heuristic to verified. Complements the existing immutable-releases roadmap item which covers the `Release.immutable` boolean.
  Evidence: GitHub GraphQL breaking changes docs (2025-05-27 `digest` addition to `ReleaseAsset`); current `scripts/sync-profile.ps1` has zero references to `digest` or `immutable`.
  Touches: `scripts/sync-profile.ps1` (GraphQL query enrichment, trust metadata processing), `schemas/profile-projects.v1.json` (add digest field), `schemas/profile-sync-report.v1.json` (add digest coverage aggregates), `tests/sync-profile.Tests.ps1`
  Acceptance: `projects.json` rows with releases include a platform-provided asset digest when available; sync report aggregates count repos with vs without digest coverage.
  Complexity: M

### P3 — accessibility / discoverability

- [ ] P3 — Add opt-in topic-apply mode with allowlist
  Why: GitHub Topics drive 99% of discovery searches. The sync report already tracks `metadataHygiene.missingTopics` with generated `topicHints`, but the policy is non-mutating. An opt-in apply mode with an explicit allowlist would close the discoverability gap for repos that haven't had topics set.
  Evidence: GitHub Topics documentation (max 20/repo, 50 chars, lowercase + hyphens); current `topicHintPolicy` states "does not mutate repositories"; `metadataHygiene.missingTopics` identifies 69 repos with missing topics; GitHub SEO research showing topic pages dominate discovery.
  Touches: `scripts/sync-profile.ps1` (add `-ApplyTopics` parameter with allowlist file/inline list, `gh api` topic mutation calls), `data/` (optional topic-allowlist file), `tests/sync-profile.Tests.ps1`
  Acceptance: `-ApplyTopics` with an allowlist applies generated topic hints to listed repos only; dry-run mode shows what would change; non-allowlisted repos are never mutated.
  Complexity: M

## Research-Driven Additions (2026-06-13 continued)

### P1 — reliability / evidence hygiene

### P2 — security / pipeline hardening

- [ ] P2 — Enable secret-scanning validity checks and report state
  Why: Secret scanning and push protection are enabled, but validity checks are disabled, so leaked-token triage lacks active/inactive prioritization when provider support exists.
  Evidence: `reports/profile-sync-report.json.repositorySettings.security.secretScanningValidityChecks` is `disabled`; GitHub secret scanning docs describe validity checks as the active-secret prioritization signal.
  Touches: GitHub repository security settings, `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`
  Acceptance: repository settings show validity checks enabled where available; sync report distinguishes enabled, disabled, unavailable, and intentionally declined states; no new fatal warning appears when GitHub does not support validity for a pattern.
  Complexity: S

- [ ] P2 — Add poutine workflow scanner to workflow-security lane
  Why: actionlint and zizmor cover syntax and common security findings, but poutine detects complementary CI/CD pipeline vulnerability patterns; recent scanner research evaluates poutine alongside actionlint and zizmor for broader workflow coverage.
  Evidence: `workflow-security.yml` currently runs actionlint and zizmor only; boostsecurityio/poutine README; arXiv 2601.14455v2 on complementary GitHub Actions scanner behavior.
  Touches: `.github/workflows/workflow-security.yml`, `requirements-ci.txt` or a pinned installer path, `tests/sync-profile.Tests.ps1`, `scripts/write-profile-sync-summary.ps1`
  Acceptance: workflow-security runs poutine on `.github/workflows` in warning-only mode first, uploads or summarizes findings without committing raw artifacts, and Pester guards the pinned version plus no-floating-download policy.
  Complexity: M

## Engineering Audit Findings (2026-06-14)

### P2 - Security / Hardening

- [ ] P2 — Clean up GH_TOKEN credential from .git/config in open-generated-profile-pr.ps1
  Why: The base64-encoded token written to `http.https://github.com/.extraheader` persists in `.git/config` after the script completes. A finally block should unset it.
  Where: `scripts/open-generated-profile-pr.ps1` lines 171-174

- [ ] P2 — Initialize $branchPushed before use in open-generated-profile-pr.ps1
  Why: The variable is referenced in a catch block (line 216) but never explicitly initialized. Under StrictMode this would error.
  Where: `scripts/open-generated-profile-pr.ps1`

### P3 - Observability / Quality

- [ ] P3 — Add page-load timeout warning in render-profile-smoke.ps1
  Why: If the GitHub profile page never reaches readyState === 'complete', the smoke test proceeds silently on a partially-loaded page with no warning.
  Where: `scripts/render-profile-smoke.ps1` lines 143-152

- [ ] P3 — Align test fixture catalog fields with production schema
  Why: `tests/fixtures/catalog.json` entries are missing many fields that the schema marks as required, making tests unreliable against the real data shape.
  Where: `tests/fixtures/catalog.json`, `schemas/profile-catalog.v1.json`

- [ ] P3 — Add SECURITY.md response-time guidance
  Why: The security policy has no indication of expected response time, which may discourage reporters. Consider adding a "reviewed within 7 business days" commitment.
  Where: `SECURITY.md`

## Research-Driven Additions

### P0

- [ ] P0 — Remove or contain the Dependabot auto-merge `pull_request_target` trigger
  Why: The scheduled workflow-security lane is currently failing because zizmor reports `dangerous-triggers` on `.github/workflows/dependabot-auto-merge.yml`.
  Evidence: GitHub run `27683950030`; `.github/workflows/dependabot-auto-merge.yml`; zizmor `dangerous-triggers` audit.
  Touches: `.github/workflows/dependabot-auto-merge.yml`, `.github/workflows/workflow-security.yml`, `tests/sync-profile.Tests.ps1` if workflow policy guards are added.
  Acceptance: scheduled Workflow security passes on `main`; Dependabot auto-merge still only acts on verified Dependabot PRs; no unsuppressed zizmor high findings remain.
  Complexity: M

- [ ] P0 — Refresh generated feed evidence after current metadata drift
  Why: Profile sync and Profile assets refresh are failing because committed generated outputs no longer match live metadata and report freshness.
  Evidence: GitHub runs `27607877014` and `27680916293`; fatal metadata drift rows for `publicRepoCount`, `repoEnumeration.returnedCount`, `HEICShift`, and `Network_Security_Auditor`; `reports/profile-sync-report.json`.
  Touches: `data/profile-catalog.json`, `README.md`, `projects.json`, `assets/profile/`, `reports/profile-sync-report.json`, `scripts/sync-profile.ps1` if transient metadata handling needs tightening.
  Acceptance: `scripts/sync-profile.ps1 -Check` passes against current live metadata; next scheduled Profile sync and Profile assets refresh runs succeed; committed report records fresh rendered-smoke and scheduled-workflow evidence.
  Complexity: M

### P1

- [ ] P1 — Align dependency-review license policy with catalog license posture
  Why: CI blocks GPL/AGPL/LGPL dependency licenses even though the catalog intentionally discloses GPL, AGPL, and LGPL project licenses, and `deny-licenses` is deprecated for possible removal.
  Evidence: `.github/workflows/tests.yml` `deny-licenses`; `reports/profile-sync-report.json.projectLicenseMetadata.licenseCounts`; actions/dependency-review-action docs.
  Touches: `.github/workflows/tests.yml`, optional `.github/dependency-review-config.yml`, `tests/sync-profile.Tests.ps1`, `RESEARCH.md`/security docs if policy wording changes.
  Acceptance: dependency-review enforces vulnerability severity and any truly disallowed licenses without contradicting the public catalog's OSS license posture; a local test or workflow check documents the selected policy.
  Complexity: S

- [ ] P1 — Resolve the remaining unresolved project license metadata row
  Why: `HostShield` is visitor-facing with `NOASSERTION`/Other license metadata and no intentional exception, leaving one unresolved legal/trust warning.
  Evidence: `reports/profile-sync-report.json.projectLicenseMetadata.unresolvedUnknownCount`; `data/profile-catalog.json`; `projects.json`.
  Touches: source repository license metadata for `HostShield`, `data/profile-catalog.json`, `scripts/sync-profile.ps1` only if exception wording needs support, `tests/sync-profile.Tests.ps1`.
  Acceptance: `projectLicenseMetadata.unresolvedUnknownCount` is 0; intentional custom licenses remain explicitly documented; README/feed license fields stay schema-valid.
  Complexity: S

- [ ] P1 — Clarify checksum coverage semantics in release trust reporting
  Why: Some release rows show `trustLevel: checksum` while the executable-download shortlist marks `hasChecksum: false`, which makes the next action ambiguous for repos with partial checksum evidence.
  Evidence: `reports/profile-sync-report.json.releaseAssetDrift.executableDownloadTrustShortlist`; `scripts/sync-profile.ps1` `New-ReleaseTrust` and release drift summary.
  Touches: `scripts/sync-profile.ps1`, `scripts/write-profile-sync-summary.ps1`, `schemas/profile-projects.v1.json`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: report rows distinguish any checksum asset from complete executable checksum coverage; summaries and `nextAction` text tell maintainers whether to add checksums or complete missing per-asset coverage.
  Complexity: S

- [ ] P1 — Clear root Markdown hygiene warnings without adding root docs
  Why: The report currently flags ignored root leftovers that violate the documented markdown hygiene contract and keep reappearing in research passes.
  Evidence: `reports/profile-sync-report.json.rootMarkdownHygiene.unexpectedFiles` lists `LOGO_PROMPTS.md`, `RESEARCH_FEATURE_PLAN.md`, and `TODO.md`; `AGENTS.md` file hygiene rules.
  Touches: local root documentation cleanup or hygiene allowlist policy, `scripts/sync-profile.ps1` root markdown hygiene report, `.markdownlint-cli2.yaml` only if exemptions change.
  Acceptance: `rootMarkdownHygiene.status` is `ok`; only allowed root Markdown files remain; no completed-work logs or duplicate planning docs are introduced.
  Complexity: S

### P2

- [ ] P2 — Reconcile community health warnings with the markdown contract
  Why: GitHub community profile health is 71% because contributing guidelines and code of conduct are absent, but adding extra root Markdown would conflict with repo hygiene.
  Evidence: GitHub community profile endpoint; `reports/profile-sync-report.json.communityHealth`; `AGENTS.md` root Markdown contract.
  Touches: `.github/` community docs if allowed, `scripts/sync-profile.ps1` community baseline disposition, `reports/profile-sync-report.json`, tests for intentional omissions.
  Acceptance: community-health warnings are either resolved via non-root `.github` docs or downgraded with an explicit intentional-omission reason; root Markdown hygiene remains clean.
  Complexity: M
