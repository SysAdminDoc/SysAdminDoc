# README Density Routing Decision

Date: 2026-06-06
Status: Active

## Decision

Keep `README.md` as the public routing surface, but review low-signal and
repo-only rows before demoting any generated catalog entries to portfolio-only
browsing.

The v4.9.83 sync report records the current routing recommendation as
`review-portfolio-only-candidates`. The only category over the soft limit is
`python`, with 41 generated rows against the 30-row category budget. The report
therefore records 11 portfolio-only review candidates for that category.

## Rationale

GitHub profile READMEs are best used as a concise public overview and profile
entry point. This repository already publishes a richer portfolio feed through
`projects.json`, so the README should not grow into the only browsing surface.

The current generated README is still below its byte-size budget and remains in
sync, so immediate catalog demotion would be premature. The safer next step is
machine-readable candidate reporting followed by an explicit catalog review.

## Guardrails

- Do not manually edit generated README catalog rows.
- Do not suppress public rows solely because they are unpopular.
- Prefer moving a row to portfolio-only only when the repo remains available
  through `projects.json` and the public portfolio.
- Keep density warnings informational until the catalog review chooses concrete
  rows.

## Evidence

- `reports/profile-sync-report.json.readmeDensity.routingRecommendation`:
  `review-portfolio-only-candidates`
- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyCandidateCount`:
  `11`
- `reports/profile-sync-report.json.readmeDensity.portfolioOnlyCandidateCategories`:
  `python`
- `reports/profile-sync-report.json.readmeDensity.categoryRows[python].overCategorySoftLimitBy`:
  `11`
