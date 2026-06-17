# Roadmap

## Research-Driven Additions (2026-06-09)

### Later (backlog, larger effort or lower priority)

- [ ] **Investigate PowerShell 7 native JSON Schema validation** -- `Test-Json -SchemaFile` in PowerShell 7.4+ uses JsonSchema.NET natively. Evaluate whether the custom `Test-JsonSchemaContract` function in sync-profile.ps1 can be replaced with the built-in cmdlet, reducing custom validation code. Known caveat: some PowerShell 7.4.0 schema bugs (GitHub issue #20743). Impact: 2, Effort: M.

- [ ] **Add sync-profile.ps1 function-level documentation** -- The script exports 100+ functions via the test seam but lacks parameter-level documentation or synopsis comments. Adding `[CmdletBinding()]` and `.SYNOPSIS`/`.PARAMETER` blocks to key public functions would improve maintainability and enable auto-generated docs. Impact: 2, Effort: L.

- [ ] **Add contribution-graph or streak visualization** -- Self-hosted (committed SVG) contribution visualization similar to Platane/snk or github-readme-stats streak. Would require a new GitHub Action step to generate the SVG from the contributions API. Lower priority because the current profile focuses on project catalog rather than activity metrics. Impact: 1, Effort: M.

## Research-Driven Additions (2026-06-10)

### P2 — leapfrog / hardening bets

- [ ] P2 — Attest projects.json provenance with actions/attest-build-provenance
  Why: The feed already publishes self-reported SHA-256 provenance hashes; a Sigstore attestation generated in the write-pr workflow makes provenance externally verifiable with `gh attestation verify`, matching GitHub's guidance that hash-bearing manifests are attestation candidates.
  Evidence: actions/attest-build-provenance README; GitHub artifact-attestations docs ("manifests that include hashes of detailed contents"); `projects.json.provenance` hash design (CLAUDE.md v4.9.43).
  Touches: `.github/workflows/profile-sync.yml` write-pr job (`attestations: write` + `id-token: write` permissions, attest step pinned by SHA), feed provenance docs in `schemas/profile-projects.v1.json` description, `scripts/open-generated-profile-pr.ps1` summary link.
  Acceptance: `gh attestation verify projects.json -o SysAdminDoc` succeeds for a feed produced by the write-pr workflow; zizmor stays green on the added permissions.
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

