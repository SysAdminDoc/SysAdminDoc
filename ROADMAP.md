# Roadmap

Actionable work only. Historical and completed roadmap material is archived in CHANGELOG.md; blocked work is kept in Roadmap_Blocked.md.

## Actionable Items

- [ ] P3 — Add portfolio cross-surface drift probing
  Why: The separate portfolio consumes `projects.json`, but this repo only validates feed shape locally and does not optionally compare deployed portfolio freshness or route counts.
  Evidence: `reports/profile-sync-report.json.portfolioCompatibility`, `projects.json.provenance`, Portfolly/Devfol.io/GitProfile research, Pagefind static-search model.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `scripts/write-profile-sync-summary.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: `-Check` can optionally probe the deployed portfolio feed timestamp/schema version/key route counts, records warning-only drift or outage evidence, and never fails local validation solely because the external portfolio is unavailable.
  Complexity: M
