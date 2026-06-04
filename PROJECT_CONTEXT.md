# SysAdminDoc Project Context

Last consolidated: 2026-06-04
Repository: `C:\Users\--\repos\SysAdminDoc`
Remote: `https://github.com/SysAdminDoc/SysAdminDoc.git`

## Purpose

This repository is the special public GitHub profile README repository for the `SysAdminDoc` account. GitHub displays `README.md` on the profile because the repository is public, matches the username, and contains a root README.

The product surface is not an app. It is a public catalog and trust surface for the user's portfolio of Windows, Android, browser-extension, web, security, media, and guide projects.

## Current Shape

- `README.md` is the rendered public profile.
- `data/profile-catalog.json` is the canonical profile catalog and suppression list.
- `projects.json` is the generated public project feed for portfolio consumption.
- `scripts/sync-profile.ps1` seeds, writes, and validates the generated README from catalog data plus live GitHub metadata, including parallel entrypoint/userscript/launch/release-link checks, README experience checks, generated theme-aware profile chrome checks, structured metadata-drift checks, metadata hygiene reporting with non-mutating topic hints and catalog-backed description suggestions, release/download drift reporting, and validation-performance reporting.
- `reports/profile-sync-report.json` is the latest validation report from `scripts/sync-profile.ps1 -Check`.
- `.github/workflows/profile-sync.yml` runs scheduled/manual profile checks and can open a manual generated-profile PR.
- `.github/workflows/workflow-security.yml` runs `zizmor` against workflow changes.
- `.github/workflows/scorecard.yml` runs OpenSSF Scorecard.
- `.github/CODEOWNERS` and `.github/dependabot.yml` guard workflow/catalog changes and monitor action updates.
- `setup.ps1` is a novice bootstrapper that installs Python 3.12 and Git through WinGet so README install snippets work on fresh Windows machines.
- `CHANGELOG.md` records profile/catalog releases.
- `ROADMAP.md` is the tracked roadmap; P0 catalog truth/privacy work shipped as v4.8.0, the generated premium README/action pass shipped as v4.9.0, the LinkedIn-aligned hero/profile copy shipped as v4.9.1, the top-table layout fix shipped as v4.9.2, the generated metadata refresh plus public research plan shipped as v4.9.3, the generated drift-lockout marker/workflow batch shipped as v4.9.4, the structured metadata-drift report shipped as v4.9.5, the guarded legacy seed mode shipped as v4.9.6, parallel link validation shipped as v4.9.7, report schema depth shipped as v4.9.8, topic/description drift guidance shipped as v4.9.9, the four-row public repo description cleanup shipped as v4.9.10, the awesome-list candidate plan shipped as v4.9.11, and theme-aware profile chrome shipped as v4.9.12.
- Local working-note files are ignored by git.
- `.github/` contains workflow, CODEOWNERS, Scorecard, and Dependabot automation for profile sync and workflow safety.

## Current Verified State

Research run date: 2026-06-04
Latest sync date: 2026-06-04
Version: v4.9.12
Last committed baseline before v4.8.0 work: `1fe3830 Consolidate profile research roadmap`
Branch: `main...origin/main`
GitHub repo visibility: `PUBLIC`
License: MIT
GitHub topics on this repo: `github-profile`, `portfolio`, `readme`

Latest sync validation through `scripts/sync-profile.ps1 -Check` found:

- 184 active public repositories under `SysAdminDoc`.
- 187 catalog entries total.
- 177 entries included in the README.
- 9 entries explicitly suppressed with reasons.
- 0 missing public repos.
- 0 private visibility violations.
- 0 medical-imaging privacy violations in the generated public README.
- 0 renamed repository redirects.
- `README.md` in sync with generated output.
- `metadataDriftSummary` reports 0 fatal metadata drift rows; info-only star/topic/`pushedAt` drift is surfaced without failing `-Check`.
- `metadataHygiene` reports 69 public repos missing topics and 0 missing public descriptions; all missing-topic rows include generated `topicHints`.
- `releaseAssetDrift` checks 177 visitor-facing rows, including 141 release-bearing rows, 102 release-action rows, and 16 source-only rows with releases; asset filename inspection remains deferred to the release taxonomy item.
- 0 link validation failures across install entrypoints, raw userscripts, launch URLs, and release redirects.
- `linkValidationSummary` reports 239 URL targets checked with throttle 16 in 6041 ms and 0 warning host groups.
- `readmeExperienceChecks` pass: Start Here section, Catalog Snapshot, featured/currently-building action columns, category anchors, primary-action coverage, labeled download buttons, generated dark/light image chrome, plain-text tagline, and meaningful image alt text are all present.
- `projects.json` contains 177 public portfolio-ready projects plus 9 explicit suppressions, with structured primary-action metadata for downstream portfolio rendering. The raw `projectsExportInSync` boolean remains in the report, but v4.9.5 adds row-level drift details so exact feed drift can be separated into fatal structural drift and informational metadata drift.
- `README.md` now carries a generated-catalog hand-edit notice before the generated catalog block, and profile sync validation records `readmeExperienceChecks.generatedCatalogNotice`.
- The manual generated-profile workflow uses `scripts/sync-profile.ps1 -Write -Check` in a single invocation so write and validation share one live metadata snapshot.
- `-SeedCatalog` is guarded behind `-ForceSeedCatalog` and should only be used as a lossy one-shot bootstrap; routine updates must edit `data/profile-catalog.json` and run `-Write`/`-Check`.
- Full live link validation has 0 fatal failures and 0 warnings in the latest v4.9.12 sync report.
- Local `zizmor .github/workflows` returned no findings after pinning workflow actions to commit SHAs and disabling checkout credential persistence.
- The hand-authored hero section now matches the user's LinkedIn positioning while keeping private production project names and employer-specific details out of the public README.
- The top hero content uses full-width Markdown sections rather than an HTML two-column wrapper, preventing the Proof Points and Currently Building tables from rendering too narrow on GitHub.
- `docs/research-feature-plan-2026-06-04.md` is the current tracked companion research plan.

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

As of v4.9.0, the sync script retries GraphQL metadata and falls back to GitHub REST metadata when GraphQL returns transient 502 errors. The README includes generated Start Here and Catalog Snapshot sections, action columns for Featured/Currently Building rows, category anchors, and category previews. The generated project feed includes `primaryAction`, `hasDownload`, `hasLiveDemo`, and `hasDirectInstall`.

## Recommended Next Implementation

1. Update `sysadmindoc.github.io` to consume `https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/projects.json`.
2. Add Pagefind/search and "new", "recently updated", and "has download" views to the portfolio.
3. Add release/download taxonomy from actual latest-release asset names.
4. Add release/download taxonomy from actual latest-release asset names.
5. Add quarterly archive/retirement reporting.
6. Add accessible theme-aware image chrome for the profile header/stat blocks.

## Research Artifacts

The current tracked companion plan is `docs/research-feature-plan-2026-06-04.md`.
