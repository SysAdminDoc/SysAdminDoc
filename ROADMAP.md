# Roadmap

## Research-Driven Additions

### P0

### P1

- [ ] P1 — Add conditional GitHub metadata and link-probe caching
  Why: Current validation probes 206 repos, 206 release fetches, and 342 links; GitHub REST/GraphQL limits and competitor reliability failures make bounded caching a root-cause resilience improvement.
  Evidence: `reports/profile-sync-report.json.validationPerformance`, GitHub REST and GraphQL rate-limit docs, `anuraghazra/github-readme-stats#4867`.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`, `.gitignore` cache rules if a local cache path is added.
  Acceptance: read-only cache entries record ETag/Last-Modified or fetched-at metadata for repo, release, and link probes; API-limit/offline fallback can reuse non-stale cache with `fidelityDegraded` evidence and redaction-safe report fields.
  Complexity: L

- [ ] P1 — Persist rendered visual evidence for profile UX parity
  Why: Rendered smoke currently passes viewport/image/overflow checks, but it does not persist screenshot paths or assert first-viewport header, Tool Catalog, and footer presence after the mock-driven redesign.
  Evidence: `scripts/render-profile-smoke.ps1`, `reports/profile-sync-report.json.renderedProfileSmoke`, GitHub dark/light image rendering docs.
  Touches: `scripts/render-profile-smoke.ps1`, `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: smoke output records desktop/mobile dark/light screenshot paths, first-viewport component presence counts, blank/cropped/overlap warnings, and report integration without committing generated PNG artifacts.
  Complexity: M

- [ ] P1 — Add stable public feed entity IDs and alias metadata
  Why: Portfolio consumers currently depend on mutable repo/title values, while catalog systems such as Backstage use stable entity references for rename-safe links and search state.
  Evidence: `schemas/profile-projects.v1.json`, `projects.json.projects[].repo`, Backstage Software Catalog descriptor docs.
  Touches: `schemas/profile-projects.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, downstream `sysadmindoc.github.io` importer.
  Acceptance: each visible project row has a stable `id`, `canonicalRepo`, and optional `aliases`; the report flags duplicate/missing IDs and portfolio compatibility tests prove older consumers can ignore the additive fields.
  Complexity: M

### P2

- [ ] P2 — Generate actionable metadata hygiene handoffs
  Why: The current report still shows 19 missing-topic rows and 1 missing-description row, but the maintainer handoff is indirect.
  Evidence: `reports/profile-sync-report.json.metadataHygiene`, `.github/ISSUE_TEMPLATE/profile-correction.yml`, `scripts/write-profile-sync-summary.ps1`.
  Touches: `scripts/sync-profile.ps1`, `scripts/write-profile-sync-summary.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: summary/report output lists top missing topic/description rows with safe repo names, suggested topic hints, and ready-to-run owner commands or catalog patch guidance without leaking suppressed/private rows.
  Complexity: S

- [ ] P2 — Define feed schema migration and deprecation policy
  Why: `projects.json` is a public portfolio contract with schema validation but no explicit compatibility window or migration signal for consumers.
  Evidence: `projects.json.provenance`, `schemas/profile-projects.v1.json`, `reports/profile-sync-report.json.portfolioCompatibility`, JSON Schema 2020-12 docs.
  Touches: `schemas/profile-projects.v1.json`, `schemas/profile-sync-report.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: feed/report output records schema version compatibility, additive-vs-breaking status, and deprecation notes; tests require a migration note when required feed fields or major schema semantics change.
  Complexity: M

- [ ] P2 — Add portfolio feed locale and script hints
  Why: Full README i18n is not a fit, but downstream Pagefind/static-search consumers benefit from explicit language/script metadata for search tuning.
  Evidence: Pagefind docs and multilingual issues, `projects.json.projects[].searchMetadata`, `schemas/profile-projects.v1.json`.
  Touches: `schemas/profile-projects.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: visible project rows may emit optional `localeHints` and `scriptHints` with safe defaults such as `en`/`Latn`; portfolio compatibility remains warning-free and README output stays English-only.
  Complexity: M

- [ ] P2 — Add an opt-in release artifact verification pilot
  Why: Current `releaseTrust` is correctly metadata-only, but a bounded verifier can validate checksum sidecars for small release assets without implying universal binary trust.
  Evidence: `releaseTrust.notesPublic`, `releaseAssetDrift`, GitHub release asset metadata, `schemas/profile-projects.v1.json`, `tests/sync-profile.Tests.ps1`.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `schemas/profile-projects.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: an opt-in switch downloads only capped asset classes with matching checksum sidecars, records verified/skipped/failure counts and reasons, preserves metadata-only default wording, and tests checksum success/mismatch/skip paths.
  Complexity: L

- [ ] P2 — Add redacted local support bundles
  Why: Setup transcripts and validation reports exist, but issue reporters do not have a single redacted diagnostic artifact for local validation/setup failures.
  Evidence: `.github/ISSUE_TEMPLATE/local-validation.yml`, `setup.ps1` transcript logging, `reports/profile-sync-report.json`, `scripts/validate-local.ps1`.
  Touches: `scripts/validate-local.ps1`, a new `scripts/new-support-bundle.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: local validation can create a zip/json bundle containing tool versions, validation output, profile sync report, dependency review summary, and redacted paths/tokens; tests prove private names/secrets are excluded.
  Complexity: M

- [ ] P2 — Reconcile working notes with the current local-only posture
  Why: `CLAUDE.md` still contains many historical GitHub Actions and Dependabot notes while the live `.github` tree has no workflows or Dependabot config, which can mislead future agents.
  Evidence: `CLAUDE.md`, `.github/`, `AGENTS.md`, current repository policy.
  Touches: `CLAUDE.md`.
  Acceptance: working notes clearly mark hosted-workflow/Dependabot history as historical or remove stale operational guidance, while preserving current local validation, feed, and blocked-roadmap instructions.
  Complexity: S

- [ ] P2 — Add branch-tip provenance to clone and install snippets
  Why: README install snippets are branch-pinned for current installs but do not record the branch tip SHA or freshness evidence that a visitor or portfolio consumer can verify.
  Evidence: `README.md` generated clone snippets, `docs/decisions/2026-06-07-userscript-install-posture.md`, GitHub REST refs API behavior.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-projects.v1.json`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: generated feed/report rows record advertised branch, current tip SHA, fetched-at time, and stale/unreachable warning state for branch-backed install actions while keeping branch-current snippets as the README default.
  Complexity: M

- [ ] P2 — Generate an optional Backstage-compatible catalog export
  Why: SysAdminDoc already maintains a structured software catalog; a narrow Backstage export adds integration value without turning the generator into a plugin framework.
  Evidence: Backstage Software Catalog descriptor docs, `projects.json`, `schemas/profile-projects.v1.json`.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`, optional generated YAML/JSON export path.
  Acceptance: an opt-in command emits redaction-safe Backstage Component entries with name, title, owner, lifecycle, tags, links, and repo URL; schema/report tests verify suppressed/private rows cannot leak.
  Complexity: M

- [ ] P2 — Add an owner-agnostic generator fixture
  Why: `scripts/sync-profile.ps1` accepts `-Owner`, but most fixtures and profile assumptions are SysAdminDoc-shaped, so multi-owner support can regress silently.
  Evidence: `scripts/sync-profile.ps1` `Owner` parameter, `tests/sync-profile.Tests.ps1`, GitHub profile README username-repo rules.
  Touches: `tests/sync-profile.Tests.ps1`, `tests/fixtures/`, `scripts/sync-profile.ps1`.
  Acceptance: a small non-SysAdminDoc fixture proves `-Owner` changes schema URLs, repo URLs, profile URLs, and metadata fetch paths without touching the real SysAdminDoc outputs; no private owner/repo names are introduced.
  Complexity: M

### P3

- [ ] P3 — Extend rendered README accessibility smoke checks
  Why: Rendered smoke verifies layout and image health, but the large generated README still needs explicit checks for details/table keyboard and link-label accessibility.
  Evidence: WCAG 2.2, `scripts/render-profile-smoke.ps1`, `reports/profile-sync-report.json.renderedProfileSmoke`, `readmeExperienceChecks`.
  Touches: `scripts/render-profile-smoke.ps1`, `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: smoke output records details count, table overflow, unique/actionable link labels, focus/keyboard sanity for collapsed and expanded sections, and desktop/mobile pass/fail counts.
  Complexity: M

- [ ] P3 — Add a Pester 6 compatibility lane
  Why: Pester 6.0.0 release candidates exist and include migration differences, while default validation is pinned to Pester 5.8.0.
  Evidence: Pester v6 migration docs, Pester releases, `scripts/validate-local.ps1`, `tests/sync-profile.Tests.ps1`.
  Touches: `scripts/validate-local.ps1`, `scripts/review-local-dependencies.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: an opt-in local command installs Pester 6 in an isolated module path, runs the non-integration suite, reports compatibility status, and leaves default Pester 5.8 validation unchanged.
  Complexity: M

- [ ] P3 — Add portfolio cross-surface drift probing
  Why: The separate portfolio consumes `projects.json`, but this repo only validates feed shape locally and does not optionally compare deployed portfolio freshness or route counts.
  Evidence: `reports/profile-sync-report.json.portfolioCompatibility`, `projects.json.provenance`, Portfolly/Devfol.io/GitProfile research, Pagefind static-search model.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `scripts/write-profile-sync-summary.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: `-Check` can optionally probe the deployed portfolio feed timestamp/schema version/key route counts, records warning-only drift or outage evidence, and never fails local validation solely because the external portfolio is unavailable.
  Complexity: M
