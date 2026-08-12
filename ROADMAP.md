# Roadmap

Actionable work only. Historical and completed roadmap material is archived in CHANGELOG.md; blocked work is kept in Roadmap_Blocked.md.

## Actionable Items

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
