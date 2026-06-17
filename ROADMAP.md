# Roadmap

## Research-Driven Additions (2026-06-09)

### Later (backlog, larger effort or lower priority)

- [ ] **Investigate PowerShell 7 native JSON Schema validation** -- `Test-Json -SchemaFile` in PowerShell 7.4+ uses JsonSchema.NET natively. Evaluate whether the custom `Test-JsonSchemaContract` function in sync-profile.ps1 can be replaced with the built-in cmdlet, reducing custom validation code. Known caveat: some PowerShell 7.4.0 schema bugs (GitHub issue #20743). Impact: 2, Effort: M.

- [ ] **Add sync-profile.ps1 function-level documentation** -- The script exports 100+ functions via the test seam but lacks parameter-level documentation or synopsis comments. Adding `[CmdletBinding()]` and `.SYNOPSIS`/`.PARAMETER` blocks to key public functions would improve maintainability and enable auto-generated docs. Impact: 2, Effort: L.

- [ ] **Add contribution-graph or streak visualization** -- Self-hosted (committed SVG) contribution visualization similar to Platane/snk or github-readme-stats streak. Would require a new GitHub Action step to generate the SVG from the contributions API. Lower priority because the current profile focuses on project catalog rather than activity metrics. Impact: 1, Effort: M.

## Research-Driven Additions (2026-06-10)

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

## Research-Driven Additions (2026-06-13)

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

### P2 — security / pipeline hardening

- [ ] P2 — Add poutine workflow scanner to workflow-security lane
  Why: actionlint and zizmor cover syntax and common security findings, but poutine detects complementary CI/CD pipeline vulnerability patterns; recent scanner research evaluates poutine alongside actionlint and zizmor for broader workflow coverage.
  Evidence: `workflow-security.yml` currently runs actionlint and zizmor only; boostsecurityio/poutine README; arXiv 2601.14455v2 on complementary GitHub Actions scanner behavior.
  Touches: `.github/workflows/workflow-security.yml`, `requirements-ci.txt` or a pinned installer path, `tests/sync-profile.Tests.ps1`, `scripts/write-profile-sync-summary.ps1`
  Acceptance: workflow-security runs poutine on `.github/workflows` in warning-only mode first, uploads or summarizes findings without committing raw artifacts, and Pester guards the pinned version plus no-floating-download policy.
  Complexity: M

## Engineering Audit Findings (2026-06-14)

### P3 - Observability / Quality

- [ ] P3 — Align test fixture catalog fields with production schema
  Why: `tests/fixtures/catalog.json` entries are missing many fields that the schema marks as required, making tests unreliable against the real data shape.
  Where: `tests/fixtures/catalog.json`, `schemas/profile-catalog.v1.json`

## Research-Driven Additions

### P0

- [ ] P0 — Refresh generated feed evidence after current metadata drift
  Why: Profile sync and Profile assets refresh are failing because committed generated outputs no longer match live metadata and report freshness.
  Evidence: GitHub runs `27607877014` and `27680916293`; fatal metadata drift rows for `publicRepoCount`, `repoEnumeration.returnedCount`, `HEICShift`, and `Network_Security_Auditor`; `reports/profile-sync-report.json`.
  Touches: `data/profile-catalog.json`, `README.md`, `projects.json`, `assets/profile/`, `reports/profile-sync-report.json`, `scripts/sync-profile.ps1` if transient metadata handling needs tightening.
  Acceptance: `scripts/sync-profile.ps1 -Check` passes against current live metadata; next scheduled Profile sync and Profile assets refresh runs succeed; committed report records fresh rendered-smoke and scheduled-workflow evidence.
  Complexity: M

### P1

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

### P2

- [ ] P2 — Reconcile community health warnings with the markdown contract
  Why: GitHub community profile health is 71% because contributing guidelines and code of conduct are absent, but adding extra root Markdown would conflict with repo hygiene.
  Evidence: GitHub community profile endpoint; `reports/profile-sync-report.json.communityHealth`; `AGENTS.md` root Markdown contract.
  Touches: `.github/` community docs if allowed, `scripts/sync-profile.ps1` community baseline disposition, `reports/profile-sync-report.json`, tests for intentional omissions.
  Acceptance: community-health warnings are either resolved via non-root `.github` docs or downgraded with an explicit intentional-omission reason; root Markdown hygiene remains clean.
  Complexity: M
