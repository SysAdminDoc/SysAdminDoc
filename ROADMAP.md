# Roadmap

Actionable work only. Historical and completed roadmap material is archived in CHANGELOG.md; blocked work is kept in Roadmap_Blocked.md.

## Actionable Items

- [ ] P2 — Reconcile working notes with the current local-only posture
  Why: `CLAUDE.md` still contains many historical GitHub Actions and Dependabot notes while the live `.github` tree has no workflows or Dependabot config, which can mislead future agents.
  Evidence: `CLAUDE.md`, `.github/`, `AGENTS.md`, current repository policy.
  Touches: `CLAUDE.md`.
  Acceptance: working notes clearly mark hosted-workflow/Dependabot history as historical or remove stale operational guidance, while preserving current local validation, feed, and blocked-roadmap instructions.
  Complexity: S

- [ ] P3 — Add portfolio cross-surface drift probing
  Why: The separate portfolio consumes `projects.json`, but this repo only validates feed shape locally and does not optionally compare deployed portfolio freshness or route counts.
  Evidence: `reports/profile-sync-report.json.portfolioCompatibility`, `projects.json.provenance`, Portfolly/Devfol.io/GitProfile research, Pagefind static-search model.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `scripts/write-profile-sync-summary.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: `-Check` can optionally probe the deployed portfolio feed timestamp/schema version/key route counts, records warning-only drift or outage evidence, and never fails local validation solely because the external portfolio is unavailable.
  Complexity: M
