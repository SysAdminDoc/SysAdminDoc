# SysAdminDoc Project Context

Last consolidated: 2026-06-06
Repository: `C:\Users\--\repos\SysAdminDoc`
Remote: `https://github.com/SysAdminDoc/SysAdminDoc.git`

## Purpose

This repository is the special public GitHub profile README repository for the `SysAdminDoc` account. GitHub displays `README.md` on the profile because the repository is public, matches the username, and contains a root README.

The product surface is not an app. It is a public catalog and trust surface for the user's portfolio of Windows, Android, browser-extension, web, security, media, and guide projects.

## Current Shape

- `README.md` is the rendered public profile.
- `data/profile-catalog.json` is the canonical profile catalog, suppression list, and upstream attribution source (`forkOf`, `upstreamLicense`) for forked/continued projects.
- `projects.json` is the generated public project feed for portfolio consumption, including structured upstream attribution fields (`forkOf`, `forkOfUrl`, `upstreamLicense`), release/download trust metadata, public-safe feed provenance, and redacted suppression records for rows omitted from the public catalog.
- `scripts/sync-profile.ps1` seeds, writes, and validates the generated README from catalog data plus live GitHub metadata, including parallel entrypoint/userscript/launch/release-link checks, README experience checks, compact public-header preservation, motion-safe committed local SVG profile asset generation, structured metadata-drift checks, metadata hygiene reporting with non-mutating topic hints and catalog-backed description suggestions, release/download drift and trust reporting, catalog/feed/report JSON Schema contract validation, planning-doc version/date consistency validation, and validation-performance reporting.
- `scripts/write-profile-sync-summary.ps1` renders public-safe GitHub Actions job summaries and annotations from `reports/profile-sync-report.json`.
- `PSScriptAnalyzerSettings.psd1` defines the curated PowerShell static-analysis gate for `scripts/sync-profile.ps1` and `setup.ps1`.
- `schemas/profile-catalog.v1.json`, `schemas/profile-projects.v1.json`, and `schemas/profile-sync-report.v1.json` are the versioned JSON Schema contracts advertised by the catalog, projects feed, and sync report through raw GitHub URLs.
- `reports/profile-sync-report.json` is the latest validation report from `scripts/sync-profile.ps1 -Check`, with a top-level `schema` URL and `schemaValidation.report` result.
- `.github/workflows/profile-sync.yml` runs scheduled/manual profile checks and can open a manual generated-profile PR.
- `.github/workflows/tests.yml` runs offline Pester, pinned PSScriptAnalyzer, and a Windows PowerShell setup smoke check on generator/setup changes, with exact reviewed validation module versions.
- `.github/workflows/workflow-security.yml` runs checksum-verified `actionlint` and hash-checked `zizmor` against workflow changes.
- `.github/workflows/scorecard.yml` runs OpenSSF Scorecard.
- `.github/CODEOWNERS` and `.github/dependabot.yml` guard workflow/catalog changes and monitor action updates.
- `setup.ps1` is a novice bootstrapper that installs Python 3.12 and Git through WinGet so README install snippets work on fresh Windows machines; it now supports `-CheckOnly` diagnostics, best-effort `%TEMP%` transcript logging, and an ASCII-only source contract for Windows PowerShell 5.1 compatibility.
- `CHANGELOG.md` records profile/catalog releases.
- `ROADMAP.md` is the tracked roadmap; P0 catalog truth/privacy work shipped as v4.8.0, the generated premium README/action pass shipped as v4.9.0, the LinkedIn-aligned hero/profile copy shipped as v4.9.1, the top-table layout fix shipped as v4.9.2, the generated metadata refresh plus public research plan shipped as v4.9.3, the generated drift-lockout marker/workflow batch shipped as v4.9.4, the structured metadata-drift report shipped as v4.9.5, the guarded legacy seed mode shipped as v4.9.6, parallel link validation shipped as v4.9.7, report schema depth shipped as v4.9.8, topic/description drift guidance shipped as v4.9.9, the four-row public repo description cleanup shipped as v4.9.10, the awesome-list candidate plan shipped as v4.9.11, theme-aware profile chrome shipped as v4.9.12, release asset taxonomy shipped as v4.9.13, committed local profile SVG assets shipped as v4.9.14, redundant dependency/status badge cleanup shipped as v4.9.15, portfolio Pagefind search verification shipped as v4.9.16, portfolio freshness/download views shipped as v4.9.17, portfolio live feed consumption shipped as v4.9.18, feed JSON Schema contracts shipped as v4.9.19, planning-doc version/date consistency checks shipped as v4.9.20, setup bootstrapper hardening shipped as v4.9.21, WolfPack/Vigil desktop recategorization shipped as v4.9.22, fork/upstream attribution shipped as v4.9.23, the Forge naming-debt log shipped as v4.9.24, the PSScriptAnalyzer CI lane shipped as v4.9.25, the OpenSSF Scorecard publish-permissions repair shipped as v4.9.26, the live GitHub-rendered profile smoke shipped as v4.9.27, generated-profile PR validation shipped as v4.9.28, public-safe intake files shipped as v4.9.29, required-check readiness shipped as v4.9.30, workflow report summaries shipped as v4.9.31, workflow timeout budgets shipped as v4.9.32, actionlint CI integration shipped as v4.9.33, checkout 6.0.3 pinning shipped as v4.9.34, CodeQL upload-sarif 4.36.1 pinning shipped as v4.9.35, v4.9.36-v4.9.40 reliability/catalog safety fixes shipped, Windows PowerShell setup smoke plus compact-header preservation shipped as v4.9.41, public suppressed-feed redaction shipped as v4.9.42, deterministic feed provenance shipped as v4.9.43, release/download trust metadata shipped as v4.9.44, the sync-report schema contract shipped as v4.9.45, CI validation tool pinning shipped as v4.9.46, and motion-safe profile chrome shipped as v4.9.47.
- Local working-note files are ignored by git.
- `.github/` contains workflow, CODEOWNERS, Scorecard, and Dependabot automation for profile sync and workflow safety.

## Current Verified State

Research run date: 2026-06-06
Latest sync date: 2026-06-06
Version: v4.9.47
Last committed baseline before v4.8.0 work: `1fe3830 Consolidate profile research roadmap`
Branch: `main...origin/main`
GitHub repo visibility: `PUBLIC`
License: MIT
GitHub topics on this repo: `github-profile`, `portfolio`, `readme`

Latest sync validation through `scripts/sync-profile.ps1 -Check` found:

- 184 active public repositories under `SysAdminDoc`.
- 187 catalog entries total.
- 177 entries included in the README.
- 10 entries explicitly suppressed with public-safe redacted feed records.
- 0 missing public repos.
- 0 private visibility violations.
- 0 medical-imaging privacy violations in the generated public README.
- 0 renamed repository redirects.
- `README.md` in sync with generated output.
- `profileAssetsInSync=true`; ten committed local SVG assets under `assets/profile/` match generated output, including static header/footer chrome and the stats/language/activity panels.
- `metadataDriftSummary` reports 0 fatal metadata drift rows; info-only star/topic/`pushedAt` drift is surfaced without failing `-Check`.
- `metadataHygiene` reports 69 public repos missing topics and 0 missing public descriptions; all missing-topic rows include generated `topicHints`.
- `releaseAssetDrift` checks 177 visitor-facing rows, including 141 release-bearing rows, 141 asset-inspected release rows, 71 release-action rows, 17 source-only rows with releases, 0 release asset kind mismatches, and 0 release asset fetch failures.
- `releaseAssetDrift.releaseTrustLevelCounts` reports 23 checksum-classified rows, 118 metadata-only rows, and 36 unknown rows; `executableDownloadsMissingChecksums` reports 55 visitor-facing executable download rows missing complete checksum coverage, and `debugArtifactRows` reports 3 debug-named release rows.
- 0 link validation failures across install entrypoints, raw userscripts, launch URLs, and release redirects.
- `linkValidationSummary` reports 185 URL targets checked with throttle 16 in 3269 ms and 0 warning host groups.
- `readmeExperienceChecks` pass for the compact public header: featured action column, setup inspect-before-run guidance, category anchors, primary-action coverage, labeled download buttons, `motionSafeChrome=true`, 0 motion patterns, 0 third-party render hosts, 0 third-party metric hosts, 0 third-party badge hosts, and no reintroduced personal-profile chrome.
- `projects.json` contains 177 public portfolio-ready projects plus 10 redacted suppression records, with structured primary-action metadata, release asset taxonomy (`releaseAssetKinds`, `releaseAssetNames`, `releaseAssetInspected`), and release trust metadata (`releaseTrust`) for visible downstream portfolio rendering. Suppressed feed rows no longer export repo names, URLs, descriptions, primary actions, release fields, topics, or notes.
- `projects.json.provenance` records source repository, generation-base commit, catalog/generator/schema SHA-256 hashes, metadata snapshot time, `metadataProvider=graphql`, and repo enumeration status (`requestedLimit=500`, `returnedCount=184`, `truncated=false`).
- `reports/profile-sync-report.json.provenance` mirrors the feed provenance, and metadata drift treats stable provenance mismatches as fatal while keeping `sourceCommit` and `metadataSnapshotAt` informational.
- `schemaValidation.passed=true`; the normalized catalog, generated projects feed, and sync report validate against `schemas/profile-catalog.v1.json`, `schemas/profile-projects.v1.json`, and `schemas/profile-sync-report.v1.json`, including the required `releaseTrust` object and the report `schemaValidation.report` result.
- `schemas/profile-projects.v1.json` now defines `suppressedProject` separately from visitor-facing `project` rows, and Pester coverage rejects suppressed feed rows that expose project identifiers.
- `docVersionConsistency.passed=true`; `ROADMAP.md`, `CHANGELOG.md`, `PROJECT_CONTEXT.md`, and `RESEARCH_REPORT.md` align to the latest planning version/date, and `-Check` fails if a planning sync date falls behind the latest changelog date.
- WolfPack and Vigil now render together in Native Desktop Applications; generated category counts are Security & Networking 3, Native Desktop Applications 19, and Misc & Forks 5.
- Forked/continued rows now use structured upstream attribution; AppManagerNG, uBlockVanced, LTSC-MicrosoftStore, RcloneBrowser, TabExplorer, Vigil, and TagStudio render upstream repo and license lines in the README and export the same metadata in `projects.json`.
- Forge-name debt is explicitly logged in `ROADMAP.md`; retained live names are WinForge, FirewallForge, NetForge, PathForge, GitForge, ImageForge, ClipForge, IconForge, and MediaForge, and new repository names should avoid that pattern.
- PSScriptAnalyzer now runs in `tests.yml` with pinned version 1.25.0, Pester runs with pinned version 5.7.1, and curated analyzer settings produce 0 local findings against `scripts/sync-profile.ps1` plus `setup.ps1`.
- OpenSSF Scorecard publish mode now keeps workflow-level permissions read-only and grants `security-events: write` plus `id-token: write` only at the Scorecard job level, with offline Pester coverage guarding the permission shape.
- `scripts/render-profile-smoke.ps1` drives installed Chrome/Chromium through DevTools to validate the live GitHub profile at desktop and 390px mobile widths; profile-sync uploads its JSON report and screenshots as artifacts.
- `tests.yml`, `profile-sync.yml`, and `workflow-security.yml` now create pull request and merge-queue checks for every PR so they can safely become required checks without path-filter pending states.
- `tests.yml` now includes an always-created `Windows setup smoke` job that parses `setup.ps1` with Windows PowerShell and runs `setup.ps1 -CheckOnly`; offline Pester rejects non-ASCII bootstrapper bytes before they can break Windows PowerShell 5.1.
- Profile sync and profile-assets refresh now write public-safe Actions summaries from `reports/profile-sync-report.json` and upload retained report artifacts.
- Every GitHub Actions job now has an explicit timeout budget, with Pester coverage for timeout presence and maximum duration.
- Workflow security now runs checksum-verified `actionlint` 1.7.12 before hash-checked `zizmor` 1.25.2 from `requirements-ci.txt`.
- All workflow checkout steps now use the pinned `actions/checkout` 6.0.3 SHA from Dependabot PR #5.
- Scorecard SARIF upload now uses the pinned `github/codeql-action/upload-sarif` 4.36.1 SHA from Dependabot PR #6.
- Public intake files now include `SECURITY.md`, issue forms for broken links/profile corrections/workflow issues, issue chooser security routing, and a PR template that protects generated README sections.
- The current compact `README.md` omits the older generated-catalog hand-edit notice by design, and profile sync validation records that as part of the minimal-header contract.
- The manual generated-profile workflow uses `scripts/sync-profile.ps1 -Write -Check` in a single invocation so write and validation share one live metadata snapshot.
- `-SeedCatalog` is guarded behind `-ForceSeedCatalog` and should only be used as a lossy one-shot bootstrap; routine updates must edit `data/profile-catalog.json` and run `-Write`/`-Check`.
- Full live link validation has 0 fatal failures and 0 warnings in the latest v4.9.15 sync report.
- Portfolio Pagefind search is implemented in `C:\Users\--\repos\sysadmindoc.github.io`: `/search/`, Pagefind Component UI, generated `dist/pagefind`, Category filter and Type metadata, and no-JS fallback links were verified by a clean `npm run build` that indexed 198 pages, 18,774 words, and 1 filter.
- Portfolio catalog freshness/download views are implemented in `C:\Users\--\repos\sysadmindoc.github.io` commit `29c2b1d`: URL-backed All/New/Recently updated/Has download filters, visible NEW/DOWNLOAD chips, combined `view=`, `cat=`, `q=`, and `sort=` state, and browser verification for 181 all / 147 new / 173 recent / 20 download results.
- Portfolio live profile-feed consumption is implemented in `C:\Users\--\repos\sysadmindoc.github.io` commit `9117f45`: `profile-feed:sync` caches raw `SysAdminDoc/SysAdminDoc` `projects.json`, `src/data/portfolio.ts` renders catalog/project routes/feeds/language lanes/timeline/OG routes from the feed, suppressed/non-portfolio rows are excluded, local featured/live-app overlays are preserved, and final verification covered 177 feed projects, 129 download rows, no suppressed/local-only cards, `DuplicateFF` 404, and no mobile overflow at 390 px.
- Local `zizmor .github/workflows` returned no findings after pinning workflow actions to commit SHAs and disabling checkout credential persistence.
- The current hand-authored header is intentionally compact: portfolio link first, then the generated Featured Projects table. Do not reintroduce the removed personal-profile hero, Proof Points, or Currently Building sections unless the user asks.
- `docs/research-feature-plan-2026-06-05.md` is the current tracked companion research plan.

## Project Philosophy

The README should be:

- Public-only: private repos must not appear as dead links.
- Visitor-focused: fast scanning, accurate descriptions, working install/download paths.
- Windows-first: PowerShell install snippets and setup flow are first-class.
- Zero-config: the public promise is "download it, launch it, done."
- Catalog-style: the README should summarize and route; richer exploration belongs on the portfolio site.
- Generated where possible: counts, stars, release links, default branches, and public/private status should not be hand-maintained.

## Critical Rules

- Only list public repos in `README.md`.
- Medical imaging, X-ray, DICOM, PACS, and related repos must stay private unless explicitly overridden.
- Use the standardized clone-install-run snippet pattern documented in the repo working notes and generated README.
- Pin clone snippets to the live default branch.
- Userscript install links should remain raw `*.user.js` URLs when that is the canonical Tampermonkey/Violentmonkey flow.
- Repos with executable release artifacts should get `/releases/latest` download links.
- Do not put JavaScript search/filter controls inside the GitHub README. GitHub sanitizes README HTML before rendering.

## Architecture

The README is now generated static Markdown. The catalog file is the source of truth for visitor-facing inclusion, suppression decisions, install snippets, release-link labels, featured rows, category placement, and currently-building rows. The sync script joins that catalog with live GitHub metadata for stars, default branches, releases, visibility, descriptions, topics, and primary languages. The old README-to-catalog reverse parser is retained only for forced one-shot bootstrap recovery.

As of v4.9.0, the sync script retries GraphQL metadata and falls back to GitHub REST metadata when GraphQL returns transient 502 errors. The README keeps a compact portfolio-first header, a generated Featured Projects table, setup guidance, category anchors, category previews, and action links. The generated project feed includes `primaryAction`, `hasDownload`, `hasLiveDemo`, `hasDirectInstall`, `releaseAssetKinds`, `releaseAssetNames`, and `releaseAssetInspected` for visible projects, while suppressed feed rows are reduced to public-safe placeholder records. Feed provenance now records source/content hashes, metadata provider, and repository enumeration status.

## Recommended Next Implementation

1. Pin CI validation-tool installs with a documented update path.
2. Add userscript install trust metadata for raw `.user.js` actions.
3. Add a repository settings/community-health baseline in the sync report.

## Research Artifacts

The current tracked companion plan is `docs/research-feature-plan-2026-06-05.md`.
