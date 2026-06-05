# Changelog

All notable changes to SysAdminDoc will be documented in this file.

## [v4.9.40] - 2026-06-05

- Fixed: VaultBox catalog entry had `category: "suppressed"` but no `suppressionReason`, making it invisible in both `projects` and `suppressed` arrays of the feed.
- Added: Orphaned-suppressed-entry gate in `Test-ProfileState` catches entries with `category: "suppressed"` but missing `suppressionReason`.
- Added: `Update-Header` idempotency and repo-count update Pester tests (completes the P1 safety-critical coverage item).

## [v4.9.39] - 2026-06-05

- Added: Schema keyword coverage audit (`Test-SchemaKeywordCoverage`) detects when schemas use keywords the custom validator cannot check, preventing silent validation gaps.
- Added: Medical privacy gate functional tests in Pester verifying `Test-ProfileState` flags medical keywords and respects `allowPublicMedical`.
- Changed: CDP smoke test replaces hard-coded 8-second sleep with `document.readyState` polling (500ms intervals, 30s deadline, 2s settle).
- Added: Pester tests for schema keyword warnings (2 tests) and medical gate (2 tests).

## [v4.9.38] - 2026-06-05

- Added: URL-scheme validation gate rejects non-`https:` URLs in visitor-facing catalog fields (`liveUrl`, `userscriptUrl`), preventing `javascript:`/`data:` injection.
- Added: `.editorconfig` for consistent indent and EOL across editors.
- Changed: Expanded CODEOWNERS to cover schemas, assets, setup.ps1, scripts/, reports/, SECURITY.md, and PSScriptAnalyzer settings.
- Added: 2 Pester tests for URL scheme validation.

## [v4.9.37] - 2026-06-05

- Added: `.gitattributes` marking generated files (`README.md`, `projects.json`, SVGs) as `linguist-generated` (collapses PR diffs, excludes from language stats) with LF line endings.
- Fixed: Generated profile SVGs now include `<title>` and `<desc>` elements for screen reader accessibility (WCAG 1.1.1).
- Added: Pester assertion for SVG accessibility elements.

## [v4.9.36] - 2026-06-05

- Fixed: `Test-ProfileState` now includes `$projectsInSync` in its failure check — `projects.json` could previously drift without failing CI.
- Fixed: MemoryStream leak in CDP smoke test receive loop (never disposed on non-matching events).
- Fixed: CDP receive now has a 60-second deadline and per-receive 30-second cancellation token, preventing infinite hangs.
- Fixed: CI workflow `git push` replaced token-in-URL pattern with `extraheader` config to prevent credential logging.
- Added: `#Requires -Version 7.0` to all scripts using PS 7 features.
- Added: `--no-sandbox` to Chrome args for CI compatibility.
- Fixed: `setup.ps1` captures `$LASTEXITCODE` immediately after winget and handles "binary already present" case.
- Fixed: `write-profile-sync-summary.ps1` null-safety for partial reports.
- Fixed: `releaseAssetKinds` schema enum now includes all values the code can produce (`jar`, `deb`, `rpm`, `dmg`).
- Changed: `gh repo list` limit raised from 300 to 500 with truncation warning.
- Added: Pester test for projects sync gate.

## [v4.9.35] - 2026-06-05

- Changed: Updated the Scorecard SARIF upload step from `github/codeql-action` 3.35.5 to the pinned 4.36.1 SHA from Dependabot PR #6.
- Added: Pester coverage now guards the reviewed CodeQL upload-sarif SHA and rejects the older 3.35.5 SHA.

## [v4.9.34] - 2026-06-05

- Changed: Updated all pinned `actions/checkout` uses from 4.3.1 to the 6.0.3 commit SHA from Dependabot PR #5, addressing the hosted Node.js 20 action deprecation warning.
- Added: Pester coverage now guards that workflow checkout steps use the reviewed 6.0.3 SHA and do not return to the older 4.3.1 SHA.

## [v4.9.33] - 2026-06-05

- Added: Workflow security now installs checksum-verified `actionlint` 1.7.12 and lints all workflow YAML before running `zizmor`.
- Added: Pester coverage guards the pinned actionlint version, checksum verification, and workflow-security command wiring.

## [v4.9.32] - 2026-06-05

- Added: All GitHub Actions jobs now declare explicit timeout budgets, with longer caps for live profile generation and shorter caps for offline lint/test/security checks.
- Added: Pester coverage now guards timeout presence and keeps workflow job budgets at 30 minutes or less.

## [v4.9.31] - 2026-06-05

- Added: `scripts/write-profile-sync-summary.ps1` writes public-safe aggregate Markdown summaries from `reports/profile-sync-report.json` and emits GitHub warning/error annotations for fatal drift, link failures, and transient link warnings.
- Changed: Profile sync check/write-pr modes and profile-assets refresh now append report summaries and upload retained sync-report artifacts.
- Verified: Pester coverage now exercises the summary helper and workflow wiring.

## [v4.9.30] - 2026-06-05

- Changed: Required-check candidate workflows now create pull request and merge-queue checks for every PR instead of using path filters that could leave required checks pending.
- Added: Pester coverage now guards that Tests, Profile sync, and Workflow security expose always-created `pull_request` and `merge_group` checks before branch-protection enforcement.
- Deferred: External required-check enforcement remains open because the current protected `main` direct-push loop would be rejected once required checks are active without a PR/bypass path.
- Verified: Pester, PSScriptAnalyzer, actionlint, and full profile sync checks were run for this release.

## [v4.9.29] - 2026-06-05

- Added: `SECURITY.md` now provides a public-safe vulnerability reporting policy for the profile README, generated catalog, setup snippets, and workflow automation.
- Added: GitHub issue forms now guide broken-link, profile-correction, and workflow/validation reports while blocking blank issues and routing sensitive reports to the security policy.
- Added: The pull request template now warns contributors not to hand-edit generated README sections and includes public-safety and generated-profile checks.
- Verified: Pester coverage now checks the intake files and public-safety wording.

## [v4.9.28] - 2026-06-05

- Added: `profile-sync.yml` now runs generated-profile validation on pull requests touching the README, catalog, generated feed/report, schemas, profile SVG assets, sync/render scripts, setup script, tests, or the profile-sync workflow.
- Added: Offline Pester coverage verifies that the generated-profile PR trigger includes the public contract paths needed before any future required-check policy.
- Verified: Pester/static/profile checks were run for this release.

## [v4.9.27] - 2026-06-05

- Added: `scripts/render-profile-smoke.ps1` runs a dependency-free Chrome/Chromium DevTools smoke against the live GitHub profile at desktop and 390px mobile widths.
- Added: The profile-sync workflow now runs the rendered smoke after generated-profile validation and uploads the JSON report plus desktop/mobile screenshots as 14-day workflow artifacts.
- Added: Pester coverage guards the rendered-smoke script contract and profile-sync workflow artifact wiring; local smoke outputs are ignored so screenshots remain workflow evidence instead of committed churn.
- Verified: Local rendered smoke passed with no missing sections, no failed images, and no document/root overflow; PSScriptAnalyzer completed with 0 findings; Pester passed 49/49.

## [v4.9.26] - 2026-06-05

- Fixed: Moved OpenSSF Scorecard write permissions out of the workflow-level `permissions` block so `publish_results: true` satisfies Scorecard's workflow restrictions.
- Added: Offline Pester coverage now guards that the Scorecard workflow keeps workflow-level permissions read-only while granting `security-events: write` and `id-token: write` only at the Scorecard job level.
- Verified: External Scorecard action documentation still requires no workflow-level write permissions for publish mode; the latest scheduled Scorecard run (`26945062246`) was failing before this repair. Local Pester/profile checks were run for this release.

## [v4.9.25] - 2026-06-04

- Added: `PSScriptAnalyzerSettings.psd1` defines the curated PowerShell static-analysis gate for `scripts/sync-profile.ps1` and `setup.ps1`, including documented exclusions for intentional CLI output, domain-specific helper names, UTF-8-without-BOM policy, and a runspace false positive.
- Changed: `.github/workflows/tests.yml` now runs a pinned PSScriptAnalyzer 1.25.0 job beside the offline Pester job and fails if any curated analyzer finding is reported.
- Fixed: Renamed JSON Schema validation loop variables away from PowerShell's automatic `$error` variable, removed unused profile/category variables, and passed `-SkipLinkValidation` explicitly into `Test-ProfileState`.
- Verified: PSScriptAnalyzer completed with 0 findings locally; `Invoke-Pester -Path tests -Output Detailed` passed 44/44; `scripts/sync-profile.ps1 -Write -Check` passed after REST fallback from a transient GitHub GraphQL 502 with `docVersionConsistency.passed=true`, `projectsExportInSync=true`, 0 metadata drift rows, 185 link targets checked, 0 link failures, and 0 link warnings.

## [v4.9.24] - 2026-06-04

- Added: Recorded the "Forge" naming-debt log in `ROADMAP.md`, including WinForge, FirewallForge, NetForge, PathForge, GitForge, ImageForge, ClipForge, IconForge, and the additionally identified MediaForge.
- Decision: No live repositories were renamed because that would break links, releases, stars, and install snippets; new repository names should avoid the "Forge" pattern.
- Verified: `scripts/sync-profile.ps1 -Write -Check` passed with `docVersionConsistency.passed=true`, `projectsExportInSync=true`, 0 metadata drift rows, 0 link failures, and 0 link warnings after REST fallback from a transient GitHub GraphQL 502.

## [v4.9.23] - 2026-06-04

- Added: Catalog entries now support structured `forkOf` and `upstreamLicense` fields, and generated project feed rows now emit `forkOf`, `forkOfUrl`, and `upstreamLicense`.
- Changed: Featured rows, category rows, and currently-building rows now render upstream repository and license attribution consistently for forked or continued projects.
- Changed: Added upstream/license metadata for AppManagerNG, uBlockVanced, LTSC-MicrosoftStore, RcloneBrowser, TabExplorer, Vigil, and TagStudio, removing ad hoc `(fork)`/license text from their descriptions.
- Added: Updated catalog/projects JSON Schemas and Pester coverage for upstream attribution rendering and feed export fields.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passed 44/44; `scripts/sync-profile.ps1 -Write -Check` passed with `schemaValidation.passed=true`, `projectsExportInSync=true`, 0 metadata drift rows, 0 link failures, and 0 link warnings after REST fallback from a transient GitHub GraphQL 502.

## [v4.9.22] - 2026-06-04

- Changed: Moved WolfPack out of Security & Networking and into Native Desktop Applications, adjacent to Vigil.
- Changed: Moved Vigil from Misc & Forks into Native Desktop Applications so the privacy/browser packaging entries render together.
- Changed: Regenerated `README.md` and `projects.json`; Security & Networking now has 3 repos, Native Desktop Applications has 19 repos, and Misc & Forks has 5 repos.
- Verified: `scripts/sync-profile.ps1 -Write -Check` passed with `readmeInSync=true`, `projectsExportInSync=true`, `docVersionConsistency.passed=true`, 0 metadata drift rows, 0 link failures, and 0 link warnings.

## [v4.9.21] - 2026-06-04

- Added: Hardened `setup.ps1` with `#Requires -Version 5.1`, `-CheckOnly` prerequisite diagnostics, best-effort transcript logging under `%TEMP%`, and shared version/status helpers.
- Changed: The generated First-time setup README section now includes an inspect-before-install command path plus table rows for `-CheckOnly` and transcript diagnostics while keeping the one-paste `irm ... | iex` install path.
- Added: `readmeExperienceChecks.setupInspectPath` now guards the generated README setup guidance, with Pester coverage for the setup script contract and rendered inspect-before-run copy.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passed 42/42; `setup.ps1 -CheckOnly` reported winget/Python/pip/Git without installing; `scripts/sync-profile.ps1 -Write -Check` passed with `setupInspectPath=true`, `projectsExportInSync=true`, 0 metadata drift rows, 0 link failures, and 0 link warnings after REST fallback from a transient GitHub GraphQL 502.

## [v4.9.20] - 2026-06-04

- Added: `Test-DocVersionConsistency` validates the tracked planning docs (`ROADMAP.md`, `CHANGELOG.md`, `PROJECT_CONTEXT.md`, and `RESEARCH_REPORT.md`) from `scripts/sync-profile.ps1 -Check`.
- Changed: `Test-ProfileState` now records `docVersionConsistency` in `reports/profile-sync-report.json` and fails when planning-doc versions disagree with the latest changelog version or when a recorded planning sync date is older than the latest changelog date.
- Added: Pester coverage for the matching-doc happy path, version mismatch failure, and stale sync-date failure.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passed 38/38; `scripts/sync-profile.ps1 -Write -Check` passed with `docVersionConsistency.passed=true`, `projectsExportInSync=true`, 0 metadata drift rows, 0 link failures, and 0 link warnings after REST fallback from a transient GitHub GraphQL 502.

## [v4.9.19] - 2026-06-04

- Added: Committed JSON Schema 2020-12 contracts for `data/profile-catalog.json` and generated `projects.json` under `schemas/`.
- Changed: Repointed catalog/feed `schema` URLs to raw GitHub schema files in this repo instead of the previously advertised missing `sysadmindoc.github.io/schemas/*` paths.
- Added: `scripts/sync-profile.ps1 -Check` now validates the normalized catalog and generated project feed against the committed schemas and records `schemaValidation` in `reports/profile-sync-report.json`.
- Fixed: Generated feed fields `releaseAssetKinds`, `releaseAssetNames`, and `topics` now serialize as arrays for zero-, one-, and multi-item cases.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passed 35/35; `scripts/sync-profile.ps1 -Write -Check` passed with schema validation true, 0 metadata drift, 0 link failures, and 0 link warnings after REST fallback from a transient GitHub GraphQL 502.

## [v4.9.18] - 2026-06-04

- Added: Implemented portfolio consumption of the live SysAdminDoc `projects.json` feed in `C:\Users\--\repos\sysadmindoc.github.io`.
- Changed: The portfolio now uses build-time `profile-feed:sync` plus `src/data/portfolio.ts` to render catalog cards, project routes, feeds, language lanes, timeline, OG routes, and JSON indexes from the profile feed while preserving local featured/live-app overlays and fallback data.
- Fixed: Suppressed and non-portfolio feed rows are excluded from generated routes; feed-omitted local-only rows such as `DuplicateFF` no longer render project pages.
- Verified: Portfolio commit `9117f45 feat(data): render portfolio from profile feed` is pushed to GitHub; `npm run check`, `npm run build`, `npm test`, `rtk git diff --check`, build-output assertions, and focused Chrome CDP browser checks passed with 177 feed projects, 129 download rows, profile-feed metadata, no suppressed/local-only cards, `DuplicateFF` 404, and no mobile overflow at 390 px.

## [v4.9.17] - 2026-06-04

- Added: Implemented the portfolio New, Recently updated, and Has download catalog views in `C:\Users\--\repos\sysadmindoc.github.io`.
- Changed: `sysadmindoc.github.io` now exposes URL-backed catalog `view=` state that combines with category, search, and sort filters, plus visible `NEW` and `DOWNLOAD` chips.
- Verified: Portfolio commit `29c2b1d feat(catalog): add freshness and download views` is pushed to GitHub; `npm run check`, `npm run build`, `npm test`, and a focused Chrome CDP browser check passed with 181 all / 147 new / 173 recently updated / 20 has-download results and no mobile horizontal overflow at 390 px.

## [v4.9.16] - 2026-06-04

- Closed: Marked the portfolio Pagefind search roadmap item complete based on the existing `sysadmindoc.github.io` implementation.
- Verified: `C:\Users\--\repos\sysadmindoc.github.io` contains `/search/`, Pagefind Component UI, `npm run search:index`, project Category filter and Type metadata, and no-JS fallback links.
- Verified: `npm run build` in `sysadmindoc.github.io` passed data, asset, and image audits, built 198 pages, stamped the service worker, and Pagefind v1.5.2 indexed 198 HTML pages, 18,774 words, and 1 filter into `dist/pagefind`.

## [v4.9.15] - 2026-06-04

- Added: README experience checks now report `thirdPartyBadgeHostCount` and `profileStatsChromeCount` so redundant badge counters and duplicated generated chrome fail validation.
- Changed: Removed redundant Shields follower/star image badges from the generated header; total public stars now render in the committed local stats SVG panel.
- Fixed: `Update-Header` strips previously generated local stats chrome before appending the current block, preventing repeated skill/stat panels across successive `-Write` runs.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 32 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with `profileAssetsInSync=true`, 6 asset checks, 0 third-party metric hosts, 0 third-party badge hosts, `profileStatsChromeCount=1`, 185 link targets checked in 5217 ms, 0 link failures, and 0 link warnings. The run used the REST metadata fallback after a transient GitHub GraphQL 502.

## [v4.9.14] - 2026-06-04

- Added: Committed local dark/light SVG profile panels under `assets/profile/` for catalog stats, language mix, and release asset health.
- Added: `profileAssetsInSync` and per-asset checks to the sync report, plus Pester coverage for local asset generation.
- Added: Scheduled/manual `Profile assets refresh` workflow and included `assets/profile/*.svg` in generated-profile PR staging.
- Changed: README profile chrome now uses local SVG panels instead of readme-stats, streak-stats, activity-graph, and komarev metric hosts.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 32 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with `profileAssetsInSync=true`, 6 asset checks, 0 third-party metric hosts, 185 link targets checked in 4289 ms, 0 link failures, and 0 link warnings.

## [v4.9.13] - 2026-06-04

- Added: Latest-release asset filename inspection with normalized `releaseAssetKinds` and `releaseAssetNames` in `projects.json`.
- Added: Release/download drift checks that compare catalog `downloadKind` labels against uploaded asset kinds and keep source-only releases as `Repo` actions.
- Changed: Corrected catalog labels for `ScriptVault` and `RumbleX`; `Vantage` is now source-only until it publishes installer assets.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 31 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with 141 inspected release rows, 71 release actions, 17 source-only release rows, 0 release asset kind mismatches, 0 release asset fetch failures, 185 link targets checked in 4404 ms, 0 link failures, and 0 link warnings. The run used the REST metadata fallback after a transient GitHub GraphQL 502.

## [v4.9.12] - 2026-06-04

- Added: Generated theme-aware `<picture>` chrome for the profile header, typing SVG, skill icons, stats cards, streak card, activity graph, and footer.
- Added: Plain-text profile tagline and descriptive image alt text so the first viewport survives image-host failure and is clearer to assistive technology.
- Added: README experience checks for theme-aware image chrome, plain-text tagline, meaningful image alt text, and generic-alt regression count.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 30 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with `themeAwareImageChrome=true`, `plainTextTagline=true`, `meaningfulImageAltText=true`, 0 generic image alt labels, 239 link targets checked in 6041 ms, 0 link failures, and 0 link warnings. The run used the REST metadata fallback after a transient GitHub GraphQL 502.

## [v4.9.11] - 2026-06-04

- Added: Prepared an awesome-list submission candidate plan in `RESEARCH_REPORT.md`, using current catalog data plus live target-list checks.
- Added: Shortlist entries for `Network_Security_Auditor`, `win11-nvme-driver-patcher`, `UserScript-Finder`, and the `SysAdminDoc` profile README, with target lists, proposed entry text, and pre-submit gates.
- Changed: Marked the awesome-list roadmap item complete as candidate preparation only; no external pull requests were opened in this repo batch.

## [v4.9.10] - 2026-06-04

- Changed: Filled the four empty public GitHub repository descriptions reported by `metadataHygiene` for `AdapterLock`, `facebook-exit-guide`, `IMDb_Enhanced`, and `SysAdminDoc`.
- Changed: Regenerated `projects.json` and `reports/profile-sync-report.json` from the updated live metadata.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 28 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with 69 missing-topic rows, 0 missing-description rows, 239 link targets checked in 6812 ms, 0 link failures, and 0 link warnings.

## [v4.9.9] - 2026-06-04

- Added: Non-mutating `topicHints` on `metadataHygiene.missingTopics`, derived from catalog category, language, install/download role, live URLs, and safe repo/description keywords.
- Added: Catalog category and catalog-backed description suggestions to metadata hygiene rows where available.
- Added: `topicHintPolicy` documenting that the report does not mutate repositories and any future apply mode requires an explicit allowlist.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 28 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with all 69 missing-topic rows carrying hints, 4 missing-description rows, 3 catalog-backed description suggestions, 239 link targets checked in 5882 ms, 0 link failures, and 0 link warnings.

## [v4.9.8] - 2026-06-04

- Added: `metadataHygiene` in `reports/profile-sync-report.json`, including missing-topic and missing-description counts plus public repo rows for cleanup planning.
- Added: `releaseAssetDrift` for visitor-facing catalog rows, summarizing current release-bearing rows, release action rows, source-only rows with releases, missing release/download-kind mismatches, and whether asset filename inspection ran.
- Added: `validationPerformance.linkValidation`, mirroring link target count, throttle, elapsed milliseconds, warning count, failure count, and warning-host count.
- Added: Pester coverage for metadata hygiene and release/download drift helper behavior.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 26 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with 69 missing-topic rows, 4 missing-description rows, 177 release-drift rows checked, 239 link targets checked in 6801 ms, 0 link failures, and 0 link warnings.

## [v4.9.7] - 2026-06-04

- Changed: Link validation now collects entrypoint, userscript, launch, and release targets first, then probes them in bounded parallel batches with throttle 16.
- Added: `linkValidationSummary` to `reports/profile-sync-report.json`, including target count, throttle, elapsed milliseconds, and `warningCountByHost`.
- Kept: Existing link semantics are preserved: 404/410 remain fatal failures, while transient 403/429/5xx/timeout results stay non-fatal warnings.
- Added: Pester coverage for deterministic warning/failure separation and warning counts grouped by host.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 24 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with 239 link targets checked in 6835 ms, 0 link failures, and 0 link warnings.

## [v4.9.6] - 2026-06-04

- Changed: `scripts/sync-profile.ps1 -SeedCatalog` now exits clearly unless `-ForceSeedCatalog` is also supplied.
- Added: A loud lossy one-shot bootstrap warning for forced seed mode and clearer missing-catalog guidance that keeps `data/profile-catalog.json` as the source of truth.
- Changed: Seed-only mode exits after writing the catalog instead of continuing into normal render/check preparation.
- Added: Pester subprocess coverage for blocked default seed mode and forced offline seed mode.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 23 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with `readmeInSync=true`, `projectsExportInSync=true`, 0 metadata drift rows, full link validation enabled, 0 link failures, and 0 link warnings.

## [v4.9.5] - 2026-06-04

- Added: Structured `metadataDrift` rows in `reports/profile-sync-report.json`, with repo, field, old value, new value, severity, and failing flags for committed-vs-live `projects.json` drift.
- Added: `metadataDriftSummary` with fatal and informational drift counts plus a 7-day stale `projects.json.generatedAt` warning.
- Changed: `scripts/sync-profile.ps1 -Check` now fails on fatal metadata drift such as branch, release, action, suppression, and row drift while keeping star/topic/`pushedAt` drift informational.
- Added: Pester coverage for metadata drift severity and stale-feed warning behavior.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 20 tests, and full `scripts/sync-profile.ps1 -Check` passes with `readmeInSync=true`, 0 fatal metadata drift rows, full link validation enabled, 0 link failures, and 0 link warnings.

## [v4.9.4] - 2026-06-04

- Added: A generated-catalog hand-edit notice before the generated README catalog sections, with `readmeExperienceChecks.generatedCatalogNotice` enforcing the marker during profile sync validation.
- Changed: The manual generated-profile workflow now runs `scripts/sync-profile.ps1 -Write -Check` in one process so writes and validation share the same live GitHub metadata snapshot.
- Changed: Header public portfolio counts and proof-point public catalog counts are refreshed by `Update-Header` from live metadata instead of remaining hand-typed.
- Added: Pester coverage for the generated-catalog notice and README experience report field.
- Verified: `Invoke-Pester -Path tests -Output Detailed` passes 18 tests, and full `scripts/sync-profile.ps1 -Write -Check` passes with `readmeInSync=true`, `projectsExportInSync=true`, full link validation enabled, 0 link failures, and 0 link warnings.

## [v4.9.3] - 2026-06-04

- Added: public-safe companion research and feature plan at `docs/research-feature-plan-2026-06-04.md`, focused on generated-profile drift enforcement, topic/description hygiene, portfolio search, accessibility, release taxonomy, and setup hardening.
- Changed: Regenerated `README.md` and `projects.json` from `data/profile-catalog.json` plus live GitHub metadata after `scripts/sync-profile.ps1 -Check` detected stale generated star counts.
- Verified: Full profile sync validation passes with 184 public repos, 187 catalog entries, 177 README entries, 9 suppressions, 0 missing public repos, 0 private visibility violations, 0 medical privacy violations, 0 fatal link failures, and passing README experience checks.
- Noted: One transient nonfatal 502 warning was recorded for a `/releases/latest` redirect during validation.

## [v4.9.2] - 2026-06-01

- Fixed: Replaced the first-viewport HTML two-column layout with full-width Markdown sections so **Proof Points** and **Currently Building** no longer render as cramped nested tables on the GitHub profile page.
- Kept: The generated **Currently Building** marker and table format expected by `scripts/sync-profile.ps1`, so future sync runs can still refresh the table safely.

## [v4.9.1] - 2026-06-01

- Changed: Rewrote the first-viewport profile copy to match the user's LinkedIn positioning: healthcare IT engineer, DICOM/PACS specialist, AI-augmented product developer, and systems administrator.
- Added: A proof-point table for 16+ years of IT operations, 10+ production platforms, cloud PACS delivery, lead-intelligence scale, X-ray room compliance tooling, and public catalog breadth.
- Kept: Private production project names and employer-specific details out of the public GitHub profile while preserving the LinkedIn evidence in generic, visitor-safe language.
- Verified: `scripts/sync-profile.ps1 -Check` remains the required gate so generated catalog counts, private-repo guards, link validation, and README experience checks stay intact after the hand-authored header change.

## [v4.9.0] - 2026-06-01

- Added: premium profile navigation with generated **Start Here** and **Catalog Snapshot** sections so visitors can choose the right project path before entering the long catalog.
- Added: direct action columns to **Featured Projects** and **Currently Building** rows, reusing the same Launch/Install/Repo/Download action logic as the category tables.
- Added: stable category anchors and generated "Start with" previews inside every collapsible category to improve scanning and deep linking.
- Added: structured `primaryAction`, `hasDownload`, `hasLiveDemo`, and `hasDirectInstall` fields to `projects.json` for portfolio consumers.
- Added: README experience checks to `reports/profile-sync-report.json`; validation now fails if generated navigation, action columns, category anchors, primary actions, or download labels regress.
- Hardened: `scripts/sync-profile.ps1` now retries GitHub GraphQL metadata and falls back to REST metadata when GitHub returns transient 502 errors.
- Added: **Brave-Portable-Updater**, **FoxPort**, **IMDb_Enhanced**, **Droidsmith**, **QuotaGlass**, **TaskCopy**, **AndroidEmulatorPlus**, **Keepr**, and **TsunamiSimulator** to the canonical catalog where visitor-facing.
- Fixed: **Brave-Portable-Updater** now points to `Update-BravePortable.ps1`; **FoxPort** no longer emits a stale root `foxport.py` snippet; **TsunamiSimulator** is listed as a desktop release instead of a dead GitHub Pages launch.
- Guarded: **VaultBox** is now explicitly suppressed because the repo is private and public profile links would 404 for visitors.
- Changed: Full profile sync validation now passes with 184 public repos, 187 catalog entries, 177 public README entries, 9 explicit suppressions, 0 link failures, and passing README experience checks.

## [v4.8.0] - 2026-05-17

- Added: `data/profile-catalog.json` as the canonical catalog source for profile README entries, explicit suppressions, featured/currently-building flags, install metadata, release labels, and manual description overrides.
- Added: root `projects.json`, generated from the same catalog and live GitHub metadata, so the portfolio site can consume a stable public project feed.
- Added: `scripts/sync-profile.ps1` with `-SeedCatalog`, `-Write`, and `-Check` modes. The check mode writes `reports/profile-sync-report.json` and fails on missing active public repos, private/public visibility mistakes, medical-imaging privacy violations, renamed repo redirects, or generated README drift.
- Added: GitHub Actions automation for scheduled/manual profile sync checks, manual generated-profile PR creation, workflow security auditing with `zizmor`, and OpenSSF Scorecard scanning.
- Added: `.github/CODEOWNERS` plus Dependabot monitoring for GitHub Actions updates.
- Hardened: workflow actions are pinned to commit SHAs and checkout credential persistence is disabled; `zizmor` reports no workflow findings locally.
- Changed: `scripts/sync-profile.ps1 -Check` now validates entrypoint raw URLs, userscript raw URLs, GitHub Pages launch links, and `/releases/latest` redirects.
- Changed: Regenerated `README.md` from catalog + live GitHub metadata. The profile now claims `178+` active public projects, refreshes current star counts, category counts, featured ranking values, release/download links, and branch-pinned install snippets from metadata.
- Added: **OpenLumen**, **PhoneFork**, **AI-Usage_Tracker**, **AdapterLock**, **sysadmindoc.github.io**, and **improve-repo** to the generated catalog/profile where visitor-facing.
- Removed: **EspressoMonkey** duplicate listing after GitHub redirect verification showed it resolves to **ScriptVault**.
- Fixed: **kindred** now links to its repository instead of a missing GitHub Pages site.
- Guarded: **RadAtlas**, **Scripts**, **ChanPrep**, **null**, **project-nomad**, **mnamer**, and **DuplicateFF** now have explicit catalog suppression reasons instead of appearing as unexplained drift.

## [v4.7.0] - 2026-05-11

- Removed: a private desktop app from Native Desktop Applications — repo went PRIVATE on GitHub, public link was 404'ing for visitors.
- Removed: a private imaging tool from Python Desktop Applications — repo is PRIVATE (medical-imaging repos must stay private per global rule), public link was 404'ing.
- Added: **HurricaneMap** + **ApocalypseWatch** to Web Applications.
- Added: **OpenSwift** + **SwiftFloris** + **OpenTasker** to Android Applications.
- Added: **Devicer** + **Snapture** + **OrganizeContacts** to Native Desktop Applications (all C# / .NET 10 WPF).
- Added: **android-debloat-list** to Guides & Resources.
- Changed: Section counts — Python 42 → 41, Web 25 → 27, Android 14 → 17, Native Desktop 10 → 12, Guides 3 → 4.
- Changed: Featured Projects table — refreshed star counts (nvme-patcher 36 → 39, OpenCut 11 → 14, project-nomad-desktop 10 → 11, LibreSpot 9 → 10, Astra-Deck 8 → 9, HostShield 4 → 5). Re-ranked LibreSpot above VideoSubtitleRemover after tie-break by recency.
- Changed: "167+ open source tools" claim in the hero typing SVG + About line — was 165+.

## [v4.6.1] - 2026-05-01

- Removed: **RadAtlas** from Web Applications (no longer in portfolio).
- Changed: Web Applications count 26 → 25.

## [v4.6.0] - 2026-04-30

- Added: **Vantage** to Browser Extensions & Userscripts (new tab dashboard for Chromium — RSS, news, weather, quick links). Ships CRX + XPI + ZIP.
- Added: **AppManagerNG** to Android Applications (power-user package manager — continuation of MuntashirAkon/AppManager, GPL-3.0-or-later).
- Added: **CallShield** restored to Android Applications — repo is public again after being temporarily private (removed in v4.0.0).
- Changed: Section counts — Browser Extensions 21 → 22, Android 12 → 14.
- Changed: Featured Projects table — refreshed star counts (nvme-patcher 35 → 36, OpenCut 10 → 11, VideoSubtitleRemover 9 → 10).
- Changed: "Currently Building" table — replaced stale lineup (MyPortfolio / NovaCut / Astra-Deck / a private imaging tool) with the current high-velocity set: UniversalConverterX (C#/.NET 10), FileOrganizer (C#/Python WinUI 3 shell), AppManagerNG (Kotlin), Vantage (JavaScript). That imaging tool is private and was 404'ing for visitors.

## [v4.5.0] - 2026-04-26

- Added: `[⬇ Download]` button next to every repo that ships an executable/installable artifact in its latest GitHub release (54 repos audited via `gh release view`). Renders as a `<kbd>`-styled button on GitHub. Each link points at `https://github.com/SysAdminDoc/<repo>/releases/latest` (the redirect URL), so the link stays valid across version bumps without re-editing the README.
- Added: Download column on the Android Applications, Native Desktop Applications, and Security & Networking tables.
- Changed: Browser Extensions & Userscripts table — the Install column now shows `[⬇ CRX]` / `[⬇ ZIP]` for repos that ship packed extension artifacts (Astra-Deck, ScriptVault, AmazonEnhanced, StyleKit, uBlockVanced, StyleCraft, EspressoMonkey, RumbleX, Discrub). Userscripts keep their canonical `[Install](raw...user.js)` link since that's the Tampermonkey/Violentmonkey install URL.
- Changed: Inline-format sections (PowerShell, Python, Media & Conversion) — each qualifying entry's heading line now ends with the download button after the description, so users can grab the prebuilt executable without pasting the clone-install-run one-liner.
- Notes: 99 repos have either no releases at all or release tags with no qualifying binary artifact (e.g. just `.py` / `.user.js` source). They keep the existing copy-paste one-liner only.

## [v4.4.0] - 2026-04-26

- Added: `setup.ps1` — winget-based Python 3.12 + Git installer for novice users. Refreshes `PATH` from the registry post-install so the README install one-liners work in the same shell. Probe-then-install (skips if already present), with machine→user scope fallback.
- Added: "First-time setup" collapsible section at the top of the categories list with the `irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1 | iex` one-liner so new visitors can install prerequisites in one paste.
- Changed: PowerShell section subtitle now states "Requires Git (see First-time setup above)" — was previously silent on the dependency despite every snippet using `git clone`.
- Changed: Python section subtitle now points at the new First-time setup section instead of leaving novices to install Python and Git on their own.

## [v4.3.0] - 2026-04-26

- Changed: All 76 install one-liners standardized to a single clone-install-run pattern. Each snippet now: shallow-clones the repo (`--depth 1 -b <branch>`) into `$env:TEMP\<repo>`, pulls if already present, conditionally `pip install -r requirements.txt` if the file exists, then runs the entry script. This guarantees the snippet works even when a project is refactored into a multi-file package or starts pulling in third-party deps via `requirements.txt`.
- Changed: Python section subtitle clarified — now states "Requires Python 3.8+ and Git" and explains the clone-to-TEMP behavior
- Added: Branch is now pinned per-snippet (`-b main` or `-b master`) so future default-branch changes won't silently break snippets

## [v4.2.0] - 2026-04-26

- Fixed: 16 broken one-liner install snippets after audit of all 87 README install commands
- Fixed: Branch errors (4) — HEICShift, LlamaLink, GmailDownloader, ClearGem default branch is `master`, not `main`
- Fixed: Filename renames/case — NVMe patcher (drop `_v3.0.0`), EXTRACTORX → ExtractorX, AI-Model-Compass → ai_model_compass, Stock-Video-Collector → artlist_scraper, QuickFind/StreamKeep case
- Fixed: SwiftShot installer moved to `App/` subfolder
- Changed: 6 package-launcher snippets converted from single-file `irm | python` to git-clone snippets — Tunerize, project-nomad-desktop, UniFile, FileOrganizer, Bookmark-Organizer-Pro, StreamKeep (each refactored into multi-file packages where the launcher script imports siblings)

## [v4.1.0] - 2026-04-25

- Changed: Refresh star counts (nvme-patcher 35, OpenCut 10, VideoSubtitleRemover 9, Astra-Deck 8, ZeusWatch/NovaCut 6, DefenderControl 4, etc.)
- Changed: Re-rank Featured Projects by current stars
- Added: 13 missing repos — MyPortfolio, LocalChromeStore, LocalDesktopStore, LocalAndroidStore, Images, one-ui-home-clone, Tunerize, Vertigo, PromptCompanion, AmazonEnhanced, DisableDefender, SunoJump
- Added: octopus-factory, Vigil (fork), TagStudio (fork) to Misc
- Removed: ChanPrep, Scripts (matched portfolio site listing)
- Changed: Currently Building swap — feature MyPortfolio + a private imaging tool
- Changed: Section counts updated (PS 28, Py 42, Web 26, Ext 21, Android 12, Desktop 10, Misc 6)
- Changed: Update repo claim 170+ to 165+ (matches public, non-archived count)

## [v4.0.0] - 2026-04-13

- Changed: Update repo count 160+ to 170+ (173 total)
- Changed: Refresh star counts (nvme-patcher 31, nomad 9, OpenCut 5, VideoSubtitleRemover 4)
- Added: Astra-Deck (7 stars), StreamKeep, Discrub, GifText, GmailDownloader
- Removed: 15 private/archived repos from public listings.
- Changed: Renamed InboxForge to GmailDownloader
- Changed: Updated VaultBox language C++ to TypeScript
- Changed: Updated all category counts

## [v3.0.0] - %Y->- (HEAD -> main, origin/main, origin/HEAD)

- Changed: Update profile README with 27 new repos, refreshed stars, and updated sections
- Changed: Update profile README with 25 new repos (150+ total)
- Changed: Update README.md
- Removed: Remove unused snake workflow
- Removed: Remove snake animation from profile
- Changed: Enhance profile README with stats, streak, activity graph, and two-column layout
- Changed: Update README.md
- Removed: Remove stats card, streak stats, and trophies
- Removed: Remove quote, activity graph, pin cards; fix broken stats URLs
- Polish profile: featured projects, top langs, about bullets, dev quote
