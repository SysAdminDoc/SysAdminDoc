# Roadmap

## Research-Driven Additions

- [ ] P3 - Add static-search metadata hints for the portfolio consumer
  Why: Static search tools such as Pagefind support filters; this repo can improve downstream discovery by exporting stable category/type/search labels without changing the profile README.
  Evidence: `projects.json`, `schemas/profile-projects.v1.json`, Pagefind filtering docs, `sysadmindoc.github.io` feed consumption.
  Touches: `schemas/profile-projects.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: Feed rows expose stable search/filter metadata that the portfolio can consume without scraping README section text.
  Complexity: M
