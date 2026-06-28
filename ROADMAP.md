# Roadmap

## Research-Driven Additions

- [ ] P0 - Reconcile the Pester suite with the local-only validation policy
  Why: The current local quality gate fails 80 tests after `.github/workflows` and `.github/dependabot.yml` were removed.
  Evidence: `Invoke-Pester -Path tests -Output Detailed`; `tests/sync-profile.Tests.ps1:2447`, `2656`, `2686`, `2818`, `3124`, `3257`, `3292`, `3576`, `3600`, `3642`, `3688`, `3713`, `3736`, `3766`, `3787`, `3802`, `3823`, `4948`; commits `475558a` and `190b262`.
  Touches: `tests/sync-profile.Tests.ps1`, `scripts/sync-profile.ps1`, `scripts/write-profile-sync-summary.ps1`.
  Acceptance: `Invoke-Pester -Path tests -Output Detailed` passes without recreating workflow or dependency-automation files.
  Complexity: L

- [ ] P0 - Make scheduled workflow freshness cleanly not applicable when workflows are absent
  Why: Missing workflow definitions should not throw `PropertyNotFoundException` or produce stale hosted-run warnings in a repo that intentionally has no workflows.
  Evidence: `scripts/sync-profile.ps1:4249-4415`; Pester failures at `scripts/sync-profile.ps1:4279`; `reports/profile-sync-report.json:3743`.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`, `scripts/write-profile-sync-summary.ps1`.
  Acceptance: Empty `.github/workflows` fixtures return `status: "not-applicable"` with zero warning/failing counts and no exceptions.
  Complexity: M

- [ ] P0 - Regenerate and verify the public profile artifacts after contract fixes
  Why: The committed report currently says README, projects feed, and profile assets are out of sync.
  Evidence: `reports/profile-sync-report.json:4-6`.
  Touches: `README.md`, `projects.json`, `assets/profile/*.svg`, `reports/profile-sync-report.json`, `data/profile-version.json`.
  Acceptance: `scripts/sync-profile.ps1 -Write -Check` reports `readmeInSync`, `projectsExportInSync`, and `profileAssetsInSync` as true or only documents nonfatal live metadata drift.
  Complexity: M

- [ ] P1 - Add a local validation bootstrap command that installs pinned tools before linting
  Why: `npm run lint:markdown` fails on a clean checkout when `markdownlint-cli2` is not installed locally.
  Evidence: `package.json`, `package-lock.json`, `.markdownlint-cli2.yaml`; local `npm run lint:markdown` output.
  Touches: `package.json`, `README.md`, `tests/sync-profile.Tests.ps1`.
  Acceptance: A documented local command runs `npm ci`, markdownlint, PSScriptAnalyzer, and Pester from a clean checkout.
  Complexity: S

- [ ] P1 - Remove hosted-automation assumptions from repository security posture reporting
  Why: Code scanning, Scorecard, actionlint, hardened runner, and dependency-review report fields are useful only if the report distinguishes removed hosted controls from local controls.
  Evidence: `tests/sync-profile.Tests.ps1:2484-2531`, `3600-3823`; `.github/workflows` absent.
  Touches: `scripts/sync-profile.ps1`, `scripts/write-profile-sync-summary.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: Report output separates `localControls` from `hostedControls`, and absent hosted controls are not warnings under the local-only policy.
  Complexity: M

- [ ] P1 - Add a downstream portfolio feed compatibility fixture
  Why: The separate portfolio consumes `projects.json`, but this repo only checks generic field presence and not a pinned consumer-shaped fixture.
  Evidence: `reports/profile-sync-report.json:1619-1627`; `schemas/profile-projects.v1.json`; Pagefind and static-site source patterns.
  Touches: `tests/fixtures/catalog.json`, `tests/sync-profile.Tests.ps1`, `schemas/profile-projects.v1.json`.
  Acceptance: A fixture fails if visible project rows lose fields required by the portfolio importer, search filters, release-trust display, or redacted suppression handling.
  Complexity: M

- [ ] P1 - Add a no-workflow regression fixture for `Test-ProfileState`
  Why: Several business-logic tests now fail before reaching their assertions because scheduled workflow lookup runs unconditionally.
  Evidence: Failing medical privacy and project-sync tests at `tests/sync-profile.Tests.ps1:3947`, `3966`, `4005`, `4031`, `4054`.
  Touches: `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: `Test-ProfileState` can run in offline/no-workflow fixtures and still exercises medical privacy, project sync, and catalog-accounting assertions.
  Complexity: S

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
