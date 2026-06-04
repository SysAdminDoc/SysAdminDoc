# Project Research and Feature Plan

Research refresh: 2026-06-04
Repository: SysAdminDoc/SysAdminDoc
Current version after this refresh: v4.9.3

## Executive Summary

SysAdminDoc/SysAdminDoc is the public GitHub profile README repository for the SysAdminDoc account. Its strongest current shape is a generated, trust-oriented portfolio catalog: `data/profile-catalog.json` is joined with live GitHub metadata by `scripts/sync-profile.ps1`, then emitted as the profile `README.md`, public `projects.json` feed, and `reports/profile-sync-report.json` validation report. The highest-value direction is to keep the profile accurate, public-safe, accessible, and reusable by the portfolio site without turning the GitHub README into an interactive app.

Top opportunities, in priority order:

1. P0 - Keep generated README/feed drift at zero by treating `scripts/sync-profile.ps1 -Check` as a required gate for every profile change.
2. P1 - Add topic and public-description drift reporting; live metadata shows 69 active public repos with no topics and 4 public repos with empty descriptions.
3. P1 - Move richer discovery to `sysadmindoc.github.io` using `projects.json`, Pagefind, and generated "new", "recently updated", and "has download" views.
4. P1 - Make the image-heavy header and stats blocks theme-aware and accessible with real alt text and fallback text.
5. P2 - Add a release asset taxonomy so `downloadKind` is derived or audited from latest-release asset names, not only curated catalog fields.
6. P2 - Parallelize live link validation; the full check passes but spends most wall time in sequential HTTP probes.
7. P2 - Demote or guard `-SeedCatalog`, because the README-to-catalog parser is now a lossy legacy bootstrap path.
8. P2 - Harden `setup.ps1` with `#Requires -Version 5.1`, check-only diagnostics, transcript logging, and inspect-before-run documentation.
9. P3 - Standardize fork/upstream/license attribution through explicit catalog fields.
10. P3 - Add a stale-project and archive-review report derived from `pushedAt`, latest releases, and suppression reasons.

## Evidence Reviewed

Local repository evidence:

- `README.md` public profile surface, generated sections, hero, badges, install snippets, category tables, and project counts.
- `data/profile-catalog.json` canonical catalog: 187 entries, 177 included README entries, 9 explicit suppressions.
- `scripts/sync-profile.ps1` generator, live metadata fetch, README rendering, projects feed export, privacy checks, link checks, and report writer.
- `projects.json` public portfolio feed with `primaryAction`, `hasDownload`, `hasLiveDemo`, `hasDirectInstall`, latest release, pushed date, topic, and suppression metadata.
- `reports/profile-sync-report.json` validation output.
- `tests/sync-profile.Tests.ps1` offline Pester suite.
- `.github/workflows/profile-sync.yml`, `tests.yml`, `workflow-security.yml`, `scorecard.yml`, `.github/CODEOWNERS`, and `.github/dependabot.yml`.
- `setup.ps1` novice Windows bootstrapper for Python 3.12 and Git.
- `ROADMAP.md`, `CHANGELOG.md`, `PROJECT_CONTEXT.md`, and recent git history.

Live metadata and verification:

- `gh repo view SysAdminDoc/SysAdminDoc` verified public visibility, MIT license, `main` default branch, and topics `github-profile`, `portfolio`, `readme`.
- `gh repo list SysAdminDoc --visibility public --no-archived --limit 300` verified 184 active public repos, 147 repos with a latest release, 27 repos using `master`, 69 repos without topics, 4 repos with empty descriptions, and 158 repos updated within the last 30 days.
- `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check` initially found `readmeInSync=false` and `projectsExportInSync=false` because live star counts had drifted. Running `-Write` refreshed the generated files; the final `-Check` passed with one nonfatal 502 release-link warning for `Vigil`.
- `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Detailed"` passed 16 tests.

External sources reviewed:

- GitHub profile README docs: https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
- GitHub repository README docs: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
- GitHub repository topics docs: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics
- GitHub Actions workflow syntax and permissions: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- GitHub Actions events and schedules: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- GitHub Actions secure use guidance: https://docs.github.com/en/actions/reference/security/secure-use
- GitHub anonymized image URLs: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-anonymized-urls
- GitHub dark/light image guidance: https://github.blog/developer-skills/github/how-to-make-your-images-in-markdown-on-github-adjust-for-dark-mode-and-light-mode/
- Pagefind: https://pagefind.app/docs/
- GitHub Profile README Generator: https://rahuldkjain.github.io/gh-profile-readme-generator/about/
- awesome-github-profile-readme: https://github.com/abhisheknaiidu/awesome-github-profile-readme
- awesome-sysadmin: https://github.com/awesome-foss/awesome-sysadmin
- github-readme-stats: https://github.com/anuraghazra/github-readme-stats
- readme-typing-svg: https://github.com/DenverCoder1/readme-typing-svg
- skill-icons: https://github.com/tandpfun/skill-icons
- OpenSSF Scorecard: https://github.com/ossf/scorecard
- zizmor: https://docs.zizmor.sh/

Areas not fully verified:

- Rendered GitHub light-mode and mobile behavior were inferred from current image URLs and Markdown structure, not re-screenshotted in a browser.
- Portfolio-site implementation details were not inspected in this repo because the portfolio is a separate repository.
- Latest-release asset file names were not fully enumerated for all 147 release-bearing repos; that is the input to the proposed release taxonomy item.

## Current Product Map

Core maintainer workflow:

- Edit `data/profile-catalog.json` for inclusion, suppression, category, description, featured, currently-building, install, and download metadata.
- Run `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Write`.
- Run `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check`.
- Commit `README.md`, `projects.json`, and `reports/profile-sync-report.json` when generated metadata changes.

Core visitor workflow:

- Land on `github.com/SysAdminDoc`.
- Scan the hero, professional focus, proof points, currently-building table, Start Here table, Catalog Snapshot, and Featured Projects.
- Expand a category and choose a project.
- Use the primary action: release download, live launch, userscript install, repo link, or a branch-pinned clone-install-run snippet.
- Use the full portfolio site for richer exploration.

User personas:

- Casual visitor checking credibility and public project breadth.
- Windows power user looking for a direct install or copy-paste setup path.
- Recruiter or peer skimming role, domain, proof points, and flagship work.
- Maintainer keeping 184 public repos, 177 profile entries, release links, and install snippets accurate.
- Portfolio site consuming `projects.json` for a richer searchable catalog.

Distribution surfaces:

- GitHub profile README.
- `projects.json` feed hosted from the repository.
- GitHub Actions validation and optional generated-profile PR flow.
- `setup.ps1` bootstrapper used by README install snippets.

Important integrations:

- GitHub CLI metadata from `gh repo list`, `gh repo view`, and REST fallback calls.
- GitHub Releases via `/releases/latest`.
- Raw GitHub URLs for userscripts and install entrypoints.
- Third-party README image renderers for hero, typing SVG, skill icons, stats, streak, activity graph, and profile view badge.
- GitHub Actions, Dependabot, OpenSSF Scorecard, and zizmor.

## Feature Inventory

### Canonical Profile Catalog

- User value: one maintainable source for public inclusion, suppression, categories, install snippets, release labels, and featured/currently-building state.
- Entry point: `data/profile-catalog.json`.
- Main code: `Get-Catalog`, `ConvertTo-EntryHashtable`, `Get-RepoMeta`, `Get-PrimaryAction`.
- Current maturity: complete and active.
- Coverage: checked by full sync validation and fixture-based Pester tests.
- Improvement opportunities: add `topicHints`, `forkOf`, `upstreamLicense`, `releaseAssetPolicy`, `stalePolicy`, and `descriptionOwner` fields.

### README Generator

- User value: keeps the public profile accurate without hand-maintained counts and links.
- Entry point: `scripts/sync-profile.ps1 -Write`.
- Main code: `New-Readme`, `Update-Header`, `New-DiscoverySection`, `New-FeaturedSection`, `New-CategorySection`, `New-FirstTimeSetupSection`.
- Current maturity: complete; final verification passed after this refresh.
- Coverage: Pester covers deterministic generation, title-link shape, suppression behavior, and projects feed shape.
- Improvement opportunities: generate more of the hand-authored hero/stat section, emit accessible image blocks, and add a stronger "do not hand-edit generated sections" guard.

### Profile Sync Check

- User value: prevents stale, private, renamed, broken, or malformed public profile links.
- Entry point: `scripts/sync-profile.ps1 -Check`.
- Main code: `Test-ProfileState`, `Test-ReadmeExperience`, `Test-LinkTargets`, `Test-HttpUrl`.
- Current maturity: strong; final check passed with zero fatal link failures and one nonfatal 502 warning.
- Coverage: CI workflow plus Pester unit checks for key helper behavior.
- Improvement opportunities: make link probes parallel, add metadata drift detail, and classify warnings by transient status.

### Public Project Feed

- User value: lets the portfolio site consume the same public catalog state as the README.
- Entry point: `projects.json`.
- Main code: `New-ProjectsExportJson`.
- Current maturity: complete but underused until the portfolio consumes it.
- Coverage: Pester verifies suppressed entries are excluded from public projects and retained in the suppressed list.
- Improvement opportunities: add sort keys, age buckets, release-asset taxonomy, topic-hint fields, and generated freshness flags.

### Privacy and Medical-Keyword Gate

- User value: keeps private or sensitive repos out of the public README.
- Entry point: `scripts/sync-profile.ps1 -Check`.
- Main code: `$MedicalPattern`, `Test-ProfileState`, `allowPublicMedical`, `suppressionReason`.
- Current maturity: complete; final report shows zero private visibility and zero medical privacy violations.
- Coverage: Pester verifies word-boundary behavior.
- Improvement opportunities: add a public report section that lists only counts and generic reasons while keeping sensitive names out of public docs.

### Link Validation

- User value: avoids dead install, launch, userscript, entrypoint, and release links.
- Entry point: `Test-LinkTargets`.
- Main code: `Test-HttpUrl`, `ConvertTo-RawGitHubUrl`, `Get-ReleaseUrl`.
- Current maturity: functional and tolerant of transient failures, but slow because probes are sequential.
- Coverage: Pester verifies result shape without live network dependency.
- Improvement opportunities: parallel probes, shorter per-host timeout, host-level warning summary, and cached validation in CI artifacts.

### First-Time Setup Flow

- User value: gives new Windows users a one-paste way to install Python and Git before running snippets.
- Entry point: README First-time setup section and `setup.ps1`.
- Main code: `Install-Pkg`, `Update-PathFromRegistry`, `Test-Cmd`.
- Current maturity: useful and straightforward.
- Coverage: no dedicated tests.
- Improvement opportunities: `#Requires -Version 5.1`, `-CheckOnly`, transcript logging, and an inspect-before-run path.

### GitHub Actions Automation

- User value: scheduled/manual validation, optional generated-profile PR, workflow security scanning, and Scorecard signal.
- Entry points: `.github/workflows/profile-sync.yml`, `tests.yml`, `workflow-security.yml`, `scorecard.yml`.
- Current maturity: good; actions are pinned and checkout credentials are not persisted.
- Coverage: workflows run on relevant paths.
- Improvement opportunities: add the companion research doc path to docs-only validation if this pattern continues; include a quicker `-SkipLinkValidation` matrix leg plus a scheduled full-link leg.

### Public Changelog and Roadmap

- User value: records profile releases and separates completed generated-profile work from remaining planning items.
- Entry points: `CHANGELOG.md`, `ROADMAP.md`.
- Current maturity: useful, but roadmap still references older research dates and should stay synchronized with v4.9.x updates.
- Coverage: manual review only.
- Improvement opportunities: keep roadmap current version, latest sync date, and active open items in lockstep with profile sync releases.

## Competitive and Ecosystem Research

| Product or source | Notable capability | What this repo should learn | What to avoid |
|---|---|---|---|
| GitHub profile README docs | Native profile placement when a public repo matches the username | Keep the README fast, static, and profile-specific | Treating it like a full web app |
| GitHub topics | Topics improve repository classification and discovery | Generate topic drift reports from catalog category, language, platform, and project role | Mutating topics without a reviewed allowlist |
| GitHub dark/light image pattern | `<picture>` with `prefers-color-scheme` works in GitHub Markdown | Make hero/stat image blocks theme-aware and accessible | Deprecated URL-fragment image theme hacks |
| Pagefind | Static search for built sites with no backend | Use on `sysadmindoc.github.io` against `projects.json` | Trying to run search/filter JavaScript inside the profile README |
| GitHub Profile README Generator | Common badge/widget/profile template patterns | Useful reference for expected profile sections | Becoming generic or badge-heavy |
| awesome-github-profile-readme | Profile pattern gallery | Use for layout inspiration and sanity checks | Copying decorative widgets without catalog value |
| awesome-sysadmin | Deep taxonomy of sysadmin tooling | Use taxonomy ideas for topics and categories | Submitting broad or immature projects before metadata is clean |
| github-readme-stats | Dynamic stats cards and self-host options | Treat stats as decorative; self-host or bake assets if reliability matters | Relying on live third-party widgets for core truth |
| readme-typing-svg and skill-icons | Lightweight visual identity widgets | Keep only if generated URLs and alt text are maintained | Letting visual widgets hide the actual value proposition |
| OpenSSF Scorecard and zizmor | Supply-chain and workflow security signals | Keep workflow changes scanned and pinned | Treating badges as a substitute for clean workflow permissions |

## Highest-Value New Features

### P0 - Generated Drift Enforcement

- User problem solved: hand edits or live metadata changes can make the profile fail `-Check`.
- Evidence: the first full check in this session failed only because `README.md` and `projects.json` had stale live metadata; `-Write` corrected it.
- Proposed behavior: add a clear generated-section banner and a PR check that fails whenever `README.md` or `projects.json` differs from generator output.
- Implementation areas: `New-Readme`, `New-ProjectsExportJson`, `.github/workflows/profile-sync.yml`, optional local git hook docs.
- Data model/API/UI implications: none beyond generated comments and CI behavior.
- Risks and edge cases: hand-authored top copy still needs a safe edit path; avoid blocking legitimate header edits that are outside generated markers.
- Verification plan: hand-edit a generated row, run `-Check`, confirm non-zero exit; run `-Write`, confirm clean.
- Estimated complexity: M.
- Priority: P0.

### P1 - Topic and Description Drift Report

- User problem solved: 69 active public repos lack topics and 4 have empty descriptions, reducing discovery and making the profile catalog carry too much explanatory burden.
- Evidence: live `gh repo list` metadata.
- Proposed behavior: add `topicHints` and `descriptionStatus` to the report, with a generated list of missing topics/descriptions and a safe apply script that requires an explicit allowlist.
- Implementation areas: `data/profile-catalog.json`, `Test-ProfileState`, `reports/profile-sync-report.json`, optional helper script.
- Data model/API/UI implications: report-only at first; later `projects.json` can expose topic hints for the portfolio.
- Risks and edge cases: GitHub topic mutation affects other repos; keep apply mode separate and reviewable.
- Verification plan: clear topics on a fixture repo object, confirm report includes recommended topics without mutating GitHub.
- Estimated complexity: M.
- Priority: P1.

### P1 - Portfolio Search and Freshness Views

- User problem solved: 177 public profile entries are too many for README-only browsing.
- Evidence: `projects.json` already has public/suppressed split, primary actions, latest releases, pushed dates, topics, and categories.
- Proposed behavior: update the portfolio site to consume `projects.json`, add Pagefind search, and add "new", "recently updated", and "has download" views.
- Implementation areas: separate portfolio repo, raw `projects.json` endpoint, Pagefind build config.
- Data model/API/UI implications: may need feed fields for `ageBucket`, `freshnessRank`, `releaseAssetKinds`, and `searchKeywords`.
- Risks and edge cases: suppressed entries must never enter the search index; raw GitHub fetch caching must be handled.
- Verification plan: build portfolio, search for a repo in every category, confirm suppressed entries are absent.
- Estimated complexity: M.
- Priority: P1.

### P1 - Theme-Aware Accessible README Chrome

- User problem solved: current image widgets are dark-themed and have generic alt text, weakening light-mode and screen-reader experience.
- Evidence: README hero, typing SVG, stats, streak, activity graph, skill icons, and footer are external images.
- Proposed behavior: generate `<picture>` blocks with dark and light source URLs, real `alt` text, and a plain-text tagline that does not depend on images.
- Implementation areas: `Update-Header` or new `New-HeroChrome` helper in `scripts/sync-profile.ps1`, README top section, Pester fixture.
- Data model/API/UI implications: optional catalog/profile fields for tagline and hero descriptors.
- Risks and edge cases: some widget services may not support good light theme variants; fallback to local/static SVG assets if needed.
- Verification plan: inspect GitHub in light and dark modes; run a Markdown render or browser smoke; verify meaningful alt text.
- Estimated complexity: M.
- Priority: P1.

### P2 - Release Asset Taxonomy

- User problem solved: primary action labels are curated, but the repo can detect whether a release actually ships APK, EXE, ZIP, CRX, XPI, or source-only assets.
- Evidence: live metadata shows 147 public repos with a latest release; README action labels are valuable and should stay trustworthy.
- Proposed behavior: fetch latest-release asset names, report mismatches against `downloadKind`, and optionally derive labels when catalog data is absent.
- Implementation areas: REST fallback release fetch, `Get-PrimaryAction`, `Get-DownloadLabel`, `New-ProjectsExportJson`, report schema.
- Data model/API/UI implications: add `releaseAssetKinds` to `projects.json`.
- Risks and edge cases: GitHub API pagination and rate limits; releases with installer-less source archives must remain "Repo" or source-only.
- Verification plan: fixture release assets with APK, EXE, ZIP, CRX, XPI, source-only; assert labels and drift report.
- Estimated complexity: M.
- Priority: P2.

### P2 - Parallel Link Validation

- User problem solved: full sync validation passes but takes around 90 seconds because live HTTP checks run sequentially.
- Evidence: both full sync checks in this session spent most time in URL validation, while Pester finished in about one second.
- Proposed behavior: run URL probes in bounded parallel batches, keep 404/410 fatal, keep transient 403/429/5xx/timeouts as warnings.
- Implementation areas: `Test-LinkTargets`, `Test-HttpUrl`, report warning schema.
- Data model/API/UI implications: report can include `warningCountByHost`.
- Risks and edge cases: parallel probes can trigger host throttling; cap concurrency conservatively.
- Verification plan: fixture URLs through a local test server or mocked `Test-HttpUrl`; live full check under a target time budget.
- Estimated complexity: M.
- Priority: P2.

## Existing Feature Improvements

### README and Feed Metadata Refresh

- Current behavior: generated content can drift as stars and live metadata change.
- Problem or missed opportunity: `-Check` correctly catches drift, but the repo needs frequent generated refresh commits.
- Recommended change: keep the scheduled check and run manual `-Write` whenever drift is detected; consider automated PR mode for low-risk metadata-only changes.
- Code locations likely affected: `README.md`, `projects.json`, `reports/profile-sync-report.json`, `.github/workflows/profile-sync.yml`.
- Backward compatibility concerns: none; generated star changes are visitor-visible but expected.
- Verification plan: `scripts/sync-profile.ps1 -Check`.
- Estimated complexity: S.
- Priority: P0.

### `-SeedCatalog` Legacy Parser

- Current behavior: `New-CatalogFromReadme` reverse-parses Markdown and install snippets.
- Problem or missed opportunity: catalog JSON is now the source of truth; reverse parsing is brittle and easy to mislead with harmless Markdown changes.
- Recommended change: keep `-SeedCatalog` as a clearly marked one-shot bootstrap mode, require `-ForceSeedCatalog`, and warn that it is lossy.
- Code locations likely affected: script parameters, `New-CatalogFromReadme`, help text, Pester tests.
- Backward compatibility concerns: any workflow still using `-SeedCatalog` must opt in.
- Verification plan: running `-SeedCatalog` without force exits with a clear warning; force mode still works.
- Estimated complexity: S.
- Priority: P2.

### Report Schema Depth

- Current behavior: report records pass/fail arrays for missing repos, private visibility, medical privacy, redirects, links, and README experience checks.
- Problem or missed opportunity: it does not yet report topic gaps, description gaps, release asset mismatches, stale generated feed age, or warning counts by host.
- Recommended change: add `metadataHygiene`, `releaseAssetDrift`, and `validationPerformance` sections.
- Code locations likely affected: `Test-ProfileState`, `New-ProjectsExportJson`, `reports/profile-sync-report.json`.
- Backward compatibility concerns: portfolio consumers should ignore unknown fields.
- Verification plan: Pester fixture asserts the new report keys and counts.
- Estimated complexity: M.
- Priority: P1.

### `setup.ps1` Diagnostics

- Current behavior: the script installs Python and Git through winget, refreshes PATH, and prints status.
- Problem or missed opportunity: security-conscious visitors may want an inspect-first path; support diagnostics are transient.
- Recommended change: add `#Requires -Version 5.1`, `-CheckOnly`, transcript logging to a temp path, and a README table row for inspect-before-run.
- Code locations likely affected: `setup.ps1`, `New-FirstTimeSetupSection`, tests if added.
- Backward compatibility concerns: `irm ... | iex` should keep working with default behavior.
- Verification plan: run `.\setup.ps1 -CheckOnly` on a machine with Python/Git installed and missing in PATH.
- Estimated complexity: S.
- Priority: P2.

### Public Planning Files

- Current behavior: `ROADMAP.md`, `CHANGELOG.md`, and `PROJECT_CONTEXT.md` describe the public profile system and prior implementation batches.
- Problem or missed opportunity: tracked planning docs can drift from generated sync state.
- Recommended change: keep version, latest sync date, and recommended next work aligned with actual generated commits.
- Code locations likely affected: `ROADMAP.md`, `CHANGELOG.md`, `PROJECT_CONTEXT.md`.
- Backward compatibility concerns: public docs should remain sanitized and avoid local-only implementation notes.
- Verification plan: `rg -n "Current repo version|Version:|Latest sync|v4\\.9\\." ROADMAP.md CHANGELOG.md PROJECT_CONTEXT.md`.
- Estimated complexity: S.
- Priority: P1.

## Reliability, Security, Privacy, and Data Safety

- Public-only enforcement is strong. The final report shows zero missing public repos, zero private visibility violations, zero medical privacy violations, and zero renamed-repo redirects.
- Link validation is tolerant of transient host errors. The final full check had one nonfatal 502 warning for a release redirect and zero fatal failures.
- Third-party image services are a reliability and privacy surface. GitHub anonymizes image URLs through Camo, but widget outages still affect the profile's first impression.
- Any future widget or metrics integration must use public-only data. Do not grant private repository scope to public-facing stats generation.
- Topic mutation should remain a reviewed operation because it changes other repositories, not just this profile repo.
- The generated feed should continue to include suppressed entries only in the `suppressed` array, with no private-only data in public project rows.
- `setup.ps1` uses remote execution through the README one-liner; an inspect-before-run path would improve trust without removing the convenience path.

## UX, Accessibility, and Trust

- The Start Here and Catalog Snapshot sections are high-value because they route visitors before the long catalog.
- The profile still relies heavily on image-rendered value signals. Add plain text equivalents for the headline/tagline and meaningful alt text for all images.
- GitHub profile README tables can be awkward on small screens. Keep top-page content full-width and avoid nested HTML wrappers.
- Category collapsibles reduce page length but hide the breadth of the catalog. The Start Here table and Featured table are the right above-the-fold counterweight.
- Primary actions are one of the strongest trust signals; keep action labels generated and tied to actual release/install/live metadata.
- Star counts are visitor-facing and change often; the generated refresh in this pass was necessary because the required check caught stale values.
- Fork/continuation projects need consistent upstream and license attribution so visitors understand origin, maintenance status, and license obligations.

## Architecture and Maintainability

- `scripts/sync-profile.ps1` owns fetch, model normalization, rendering, validation, and reporting. It works, but future changes would be easier if GitHub I/O, catalog normalization, renderers, validators, and report writers were split into smaller modules or clearly separated regions.
- The Pester suite is now valuable and fast. Extend it before touching renderer behavior.
- The live link checker is intentionally integration-heavy. Keep a fast offline test layer and a slower scheduled/live check layer.
- `projects.json` is the architectural bridge to the portfolio site. New data should be added there only when it is public-safe and useful to downstream rendering.
- The catalog should remain the single source of truth. README reverse parsing should not regain authority now that the generated pipeline is established.

## Prioritized Roadmap

- [ ] P0 - Enforce generated README/feed drift checks
  - Why: `-Check` caught stale generated outputs in this refresh.
  - Evidence: initial full check returned `readmeInSync=false` and `projectsExportInSync=false`; final check passed after `-Write`.
  - Touches: `scripts/sync-profile.ps1`, `.github/workflows/profile-sync.yml`, optional generated banner.
  - Acceptance: any generated-section edit fails CI until `-Write` is run.
  - Verify: `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check`.

- [ ] P1 - Add topic and description drift reporting
  - Why: live metadata shows 69 active public repos without topics and 4 with empty descriptions.
  - Evidence: `gh repo list SysAdminDoc --visibility public --no-archived --limit 300 --json name,description,repositoryTopics`.
  - Touches: `data/profile-catalog.json`, `scripts/sync-profile.ps1`, `reports/profile-sync-report.json`.
  - Acceptance: report lists missing topics/descriptions and suggested topic hints without mutating repos.
  - Verify: `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check`.

- [ ] P1 - Add portfolio search and freshness views from `projects.json`
  - Why: 177 public profile entries need better discovery than collapsible README browsing.
  - Evidence: `projects.json` already exposes category, primary action, topics, release, and pushed-date fields.
  - Touches: separate portfolio repo, `projects.json` schema additions if needed.
  - Acceptance: portfolio search finds projects by name/category/topic/action and excludes suppressed entries.
  - Verify: portfolio build plus search smoke tests.

- [ ] P1 - Generate accessible theme-aware header/stat image blocks
  - Why: current external image blocks are dark-first and have generic alt text.
  - Evidence: README hero/stats/streak/activity/skill/footer images.
  - Touches: `scripts/sync-profile.ps1`, `README.md`, Pester fixtures.
  - Acceptance: meaningful alt text, light/dark sources, and a plain-text tagline are present.
  - Verify: GitHub light/dark render smoke and `scripts/sync-profile.ps1 -Check`.

- [ ] P2 - Add release asset taxonomy and drift checks
  - Why: 147 public repos have latest releases; action labels should match actual shipped assets.
  - Evidence: live metadata and existing `downloadKind` catalog field.
  - Touches: GitHub REST release asset fetch, `Get-PrimaryAction`, `Get-DownloadLabel`, `New-ProjectsExportJson`.
  - Acceptance: report flags asset-label mismatches and `projects.json` exposes release asset kinds.
  - Verify: Pester fixture plus live `-Check`.

- [ ] P2 - Parallelize link validation
  - Why: full sync validation passes but spends most time waiting on sequential HTTP probes.
  - Evidence: Pester completed in about one second; full live check took materially longer.
  - Touches: `Test-LinkTargets`, `Test-HttpUrl`, report warning grouping.
  - Acceptance: same pass/fail semantics with a lower wall-clock time and bounded concurrency.
  - Verify: full `-Check` and warning/failure fixture tests.

- [ ] P2 - Guard `-SeedCatalog`
  - Why: README reverse parsing is no longer the authoritative data path.
  - Evidence: `New-CatalogFromReadme` hard-codes Markdown and table shapes.
  - Touches: script parameters, `New-CatalogFromReadme`, docs/tests.
  - Acceptance: seed mode requires explicit force and warns that catalog JSON is authoritative.
  - Verify: `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -SeedCatalog` without force exits clearly.

- [ ] P2 - Harden `setup.ps1`
  - Why: onboarding is strong, but diagnostics and inspect-before-run trust can improve.
  - Evidence: current script has probe/install/PATH refresh but no check-only or transcript mode.
  - Touches: `setup.ps1`, README generated First-time setup copy.
  - Acceptance: `-CheckOnly` reports Python/Git/winget state without installing; transcript path is printed during installs.
  - Verify: `pwsh -NoProfile -File .\setup.ps1 -CheckOnly`.

- [ ] P3 - Standardize fork/upstream/license attribution
  - Why: continuation/fork projects are not labeled uniformly across Featured and category sections.
  - Evidence: catalog has category/action data but no explicit `forkOf` or `upstreamLicense` fields.
  - Touches: `data/profile-catalog.json`, README renderer, `projects.json`.
  - Acceptance: forked/continued projects show consistent upstream and license copy.
  - Verify: Pester fixture and README render inspection.

- [ ] P3 - Add stale-project and archive-review report
  - Why: the account has many active repos and periodic retirement review keeps the profile sharp.
  - Evidence: live `pushedAt`, latest release, and suppression data are already available.
  - Touches: `Test-ProfileState`, report schema, possibly catalog `stalePolicy`.
  - Acceptance: report groups stale, dormant, source-only, suppressed, and recently revived projects.
  - Verify: fixture dates plus live `-Check`.

## Quick Wins

- Run generated metadata refresh whenever `-Check` reports `readmeInSync=false` or `projectsExportInSync=false`.
- Add a report section for empty descriptions and missing topics before adding any mutation script.
- Add real alt text and a plain-text tagline under the hero.
- Add `#Requires -Version 5.1` and `-CheckOnly` to `setup.ps1`.
- Add a Pester fixture for the nonfatal link-warning path.
- Add a generated warning banner around generated README sections.

## Larger Bets

- Portfolio search and freshness views from `projects.json`.
- Release asset taxonomy across all release-bearing repos.
- Modularizing the PowerShell generator into fetch, model, render, validate, and report layers.
- Action-baked or self-hosted profile image assets to reduce live third-party widget dependence.
- Reviewed topic/description cleanup across public repos after report-only mode stabilizes.

## Explicit Non-Goals

- Do not put JavaScript search or filtering inside the GitHub profile README; use the portfolio site.
- Do not replace the generated catalog with a generic profile README template.
- Do not add badge-heavy decoration that competes with the project catalog.
- Do not use private repository data for public stats, widgets, or feed generation.
- Do not mutate topics or descriptions across other repos without a reviewed allowlist.
- Do not rename existing public repos just to resolve naming debt; preserve links and stars.

## Open Questions

- Which repo-topic taxonomy should be the canonical source: catalog category only, GitHub language plus category, or a curated `topicHints` field?
- Should low-risk generated metadata drift be auto-PR'd on schedule, or should scheduled jobs remain check-only with manual `write-pr`?
- Should `PROJECT_CONTEXT.md` stay tracked as public project documentation, or should it be reduced to public-safe status notes only?
- What is the portfolio site's preferred schema contract for search and freshness fields from `projects.json`?
