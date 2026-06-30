# Roadmap

## Research-Driven Additions

- [ ] P2 - Reframe generated PR helper scripts as dormant manual tools or retire their active report gates
  Why: `scripts/open-generated-profile-pr.ps1` and generated-validation status helpers remain in the repo, but current policy and tests no longer support live hosted PR validation.
  Evidence: `scripts/open-generated-profile-pr.ps1`, `scripts/set-generated-validation-status.ps1`, `tests/sync-profile.Tests.ps1:3124`, `3257`.
  Touches: `scripts/open-generated-profile-pr.ps1`, `scripts/set-generated-validation-status.ps1`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: Helper scripts are either covered as manual utilities with no active freshness gates or removed with all references cleaned up.
  Complexity: M

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

- [ ] P1 - Make rendered profile smoke evidence fully local and policy-aware
  Why: The report currently marks rendered smoke as `not-run` and warns that hosted smoke evidence should have refreshed it, which contradicts the local-only validation model.
  Evidence: `reports/profile-sync-report.json` `renderedProfileSmoke.status: "not-run"` and `evidenceFreshness.warnings`; `scripts/render-profile-smoke.ps1`.
  Touches: `scripts/render-profile-smoke.ps1`, `scripts/sync-profile.ps1`, `scripts/write-profile-sync-summary.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: A local smoke run records desktop and mobile viewport evidence, and unavailable browser evidence is reported as a clear local skip rather than a hosted-artifact warning.
  Complexity: M

- [ ] P1 - Clean public intake and audit config after the no-workflow policy shift
  Why: Public issue/config files still point users and tooling at workflow/CI concepts even though the repo intentionally removed hosted workflows.
  Evidence: `.github/ISSUE_TEMPLATE/workflow-ci.yml`, `.github/zizmor.yml`, `requirements-ci.txt`, `scripts/open-generated-profile-pr.ps1`.
  Touches: `.github/ISSUE_TEMPLATE/workflow-ci.yml`, `.github/zizmor.yml`, `requirements-ci.txt`, `scripts/write-profile-sync-summary.ps1`, `scripts/sync-profile.ps1`.
  Acceptance: Public issue templates and local audit config describe local validation/support paths without implying active CI workflows, Dependabot, or generated-profile hosted validation.
  Complexity: S

- [ ] P2 - Add a manual dependency and advisory review lane for local tooling
  Why: `npm audit` is clean, but dependency updates are manual and the repo has explicit overrides plus PowerShell module/tool pins that need a repeatable review path.
  Evidence: `package.json` overrides for `markdown-it` and `js-yaml`; `requirements-ci.txt`; `npm audit --json`; PSGallery versions for Pester and PSScriptAnalyzer; markdownlint-cli2 and zizmor release sources.
  Touches: `package.json`, `package-lock.json`, `requirements-ci.txt`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: A documented local command or report section captures npm audit status, manual override drift, pinned PowerShell tooling versions, and advisory-review results without adding Dependabot or workflows.
  Complexity: M
