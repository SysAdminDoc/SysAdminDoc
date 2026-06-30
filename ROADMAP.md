# Roadmap

## Research-Driven Additions

- [ ] P2 - Preserve release-trust evidence while avoiding unverifiable integrity claims
  Why: GitHub release asset digests and artifact attestations are valuable signals, but this repo should not imply binary verification it does not perform.
  Evidence: `schemas/profile-projects.v1.json:195`, `reports/profile-sync-report.json:624`, GitHub release asset and artifact attestation docs.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-projects.v1.json`, `reports/profile-sync-report.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: Release-trust output labels digests, checksums, SBOMs, and attestations as metadata evidence unless an explicit local verification command succeeds.
  Complexity: M

- [ ] P2 - Keep markdown hygiene checks aligned with tracked-file reality
  Why: Root planning docs are intentionally local/ignored, while tracked Markdown checks should not crash on scalar violation output.
  Evidence: `tests/sync-profile.Tests.ps1:2426-2431`; `.gitignore`; `AGENTS.md`.
  Touches: `tests/sync-profile.Tests.ps1`, `.markdownlint-cli2.yaml`.
  Acceptance: Tracked Markdown trailing-whitespace tests pass with zero, one, or many violations and still ignore local-only planning docs.
  Complexity: S

- [ ] P3 - Add static-search metadata hints for the portfolio consumer
  Why: Static search tools such as Pagefind support filters; this repo can improve downstream discovery by exporting stable category/type/search labels without changing the profile README.
  Evidence: `projects.json`, `schemas/profile-projects.v1.json`, Pagefind filtering docs, `sysadmindoc.github.io` feed consumption.
  Touches: `schemas/profile-projects.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: Feed rows expose stable search/filter metadata that the portfolio can consume without scraping README section text.
  Complexity: M

## Research-Driven Additions

- [ ] P2 - Add a manual dependency and advisory review lane for local tooling
  Why: `npm audit` is clean, but dependency updates are manual and the repo has explicit overrides plus PowerShell module/tool pins that need a repeatable review path.
  Evidence: `package.json` overrides for `markdown-it` and `js-yaml`; `requirements-local-audit.txt`; `npm audit --json`; PSGallery versions for Pester and PSScriptAnalyzer; markdownlint-cli2 and zizmor release sources.
  Touches: `package.json`, `package-lock.json`, `requirements-local-audit.txt`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: A documented local command or report section captures npm audit status, manual override drift, pinned PowerShell tooling versions, and advisory-review results without adding Dependabot or workflows.
  Complexity: M
