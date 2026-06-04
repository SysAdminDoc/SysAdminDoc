# Research Report

Consolidated from legacy research and feature-planning documents on 2026-06-03. This is the canonical research home for the profile-catalog system; planned work derived from it lives in `ROADMAP.md`. The dated source bundle was archived to `docs/archive/research-feature-plan-2026-06-04.md`.

Research refresh: 2026-06-04
Deep-research addenda: 2026-06-03 and 2026-06-04 (see addenda below)
Repository: SysAdminDoc/SysAdminDoc
Current version after this refresh: v4.9.15

## Verification Refresh — 2026-06-04

- `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Detailed"`
  passed 32/32 tests after the v4.9.15 dependency/status badge cleanup.
- `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Write -Check` completed
  successfully with `readmeInSync=true`, `projectsExportInSync=true`, 0 metadata
  drift rows, `metadataHygiene` showing 69 missing-topic repos, generated
  `topicHints` on all missing-topic rows, and 0 missing descriptions,
  `readmeExperienceChecks` showing theme-aware image chrome, plain-text tagline,
  meaningful image alt text, and 0 generic image alt labels, `releaseAssetDrift`
  checking 177 visitor-facing rows, 141 release-bearing rows, 141 inspected
  release rows, 71 release-action rows, 17 source-only release rows, 0 release
  asset kind mismatches, and 0 release asset fetch failures, full link
  validation enabled, `profileAssetsInSync=true`, 6 profile asset checks, 0
  third-party metric hosts, 0 third-party badge hosts, exactly 1 generated stats
  chrome block, 185 link targets checked in 5217 ms, 0 link failures, and 0 link
  warnings. Raw `projectsExportInSync` remains a report signal;
  info-only star/topic/`pushedAt` drift is now reported without failing the gate.
- The v4.9.15 batch closed the active P2 dependency/status badge item by
  removing redundant Shields follower/star image badges, moving total public
  stars into the committed local stats SVG, adding badge/chrome-count report
  guards, and fixing duplicate generated stats chrome across repeated writes.
- The v4.9.14 batch closed the active P2 action-baked assets item by generating
  committed local SVG metric panels, validating them in the sync report, adding
  a scheduled/manual asset-refresh workflow, and removing komarev plus the
  third-party stats/streak/activity hosts from the generated README.
- The v4.9.13 batch closed the active P2 release taxonomy item by inspecting
  latest-release asset names, exporting `releaseAssetKinds`/`releaseAssetNames`,
  keeping source-only releases as `Repo` actions, and cleaning the current
  catalog to 0 release asset kind mismatches.
- The v4.9.12 batch closed the active P1 theme-aware image chrome item by
  generating dark/light `<picture>` sources for profile chrome, adding a
  plain-text tagline, replacing generic image alt labels, and validating those
  checks in `readmeExperienceChecks`.
- The v4.9.10 batch closed the active P1 public-repo description item by filling
  the four-row `metadataHygiene.missingDescriptions` allowlist on GitHub and
  regenerating the report to 0 missing descriptions.
- The v4.9.11 batch closed the active P1 awesome-list item by preparing a
  small candidate shortlist with live target-list checks and proposed entry text;
  no external pull requests were opened in this repo batch.
- The v4.9.9 batch closed the active P1 topic/description drift reporting item
  by adding non-mutating topic hints, catalog categories, catalog-backed
  description suggestions, and an explicit allowlist-required apply policy.
- The v4.9.8 batch closed the active P1 report-schema-depth item by adding
  `metadataHygiene`, visitor-facing `releaseAssetDrift`, and
  `validationPerformance` sections.
- The v4.9.7 batch closed the active P2 parallel link-validation item by
  collecting link targets first, probing them in bounded parallel batches, and
  adding `linkValidationSummary.warningCountByHost`.
- The v4.9.6 batch closed the active P2 legacy seed-parser item by requiring
  explicit `-ForceSeedCatalog`, emitting a lossy one-shot bootstrap warning,
  and exiting seed-only mode after the catalog write.
- The v4.9.5 batch closed the active P2 metadata-drift item by adding
  `Test-MetadataDrift`, row-level `metadataDrift` output, `metadataDriftSummary`,
  and stale `projects.json.generatedAt` warnings.
- The v4.9.4 batch closed the active P0 generated-feed drift item by adding the
  generated-catalog notice, checking that marker in README experience
  validation, refreshing header counts from live metadata, and changing the
  manual write-PR workflow to run write/check in a single metadata snapshot.
- Current official-source recheck still supports the existing plan: GitHub
  profile README rendering is static and tied to the public username-matching
  repo, GitHub Actions workflow permissions remain a first-class workflow
  hygiene control, and Pagefind remains a fit for the separate static portfolio
  rather than the GitHub README. No new roadmap row was needed.

## Executive Summary

SysAdminDoc/SysAdminDoc is the public GitHub profile README repository for the SysAdminDoc account. Its strongest current shape is a generated, trust-oriented portfolio catalog: `data/profile-catalog.json` is joined with live GitHub metadata by `scripts/sync-profile.ps1`, then emitted as the profile `README.md`, the public `projects.json` feed, and the `reports/profile-sync-report.json` validation report. The highest-value direction is to keep the profile accurate, public-safe, accessible, and reusable by the portfolio site without turning the GitHub README into an interactive app.

Top opportunities, in priority order:

1. P0 - Keep generated README/feed drift at zero by treating `scripts/sync-profile.ps1 -Check` as a required gate for every profile change.
2. P1 - Move richer discovery to `sysadmindoc.github.io` using `projects.json`, Pagefind, and generated "new", "recently updated", and "has download" views.
3. P1 - Apply reviewed topic cleanup from the non-mutating report; live metadata still shows 69 active public repos with no topics and 0 public repos with empty descriptions.
4. P1 - Publish or repoint the advertised JSON Schema URLs, then validate the feed against them.
5. P1 - Add a self-contained version/date consistency gate across tracked planning docs.
6. P2 - Harden `setup.ps1` with `#Requires -Version 5.1`, check-only diagnostics, transcript logging, and inspect-before-run documentation.
7. P3 - Standardize fork/upstream/license attribution through explicit catalog fields.
8. P3 - Add a stale-project and archive-review report derived from `pushedAt`, latest releases, and suppression reasons.

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
- `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check` initially found `readmeInSync=false` and `projectsExportInSync=false` because live star counts had drifted. Running `-Write` refreshed the generated files; the final `-Check` passed with one nonfatal 502 release-link warning.
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

## Awesome-List Submission Candidate Plan — 2026-06-04

Status: prepared candidate plan only. External pull requests were not opened in
this repo batch; the lines below are ready for a separate cross-repository
submission pass.

Live target-list checks:

- `awesome-foss/awesome-sysadmin` is active, public, and not archived; it is a
  curated open-source sysadmin resource list and its README points additions to
  the Contributing section. The repo contains a `.github/PULL_REQUEST_TEMPLATE.md`
  and no root `CONTRIBUTING.md`.
- `awesome-scripts/awesome-userscripts` is active, public, and not archived.
  Its `CONTRIBUTING.md` says submissions should be noteworthy, fill a gap, use
  one pull request per suggestion, and stay alphabetically sorted.
- `abhisheknaiidu/awesome-github-profile-readme` is active, public, and not
  archived. Its `contributing.md` asks for profile READMEs that stand out, one
  pull request per suggestion, and names starting with a capital.
- The archived `janikvonrotz/awesome-powershell` repo now points to Codeberg, so
  it is not a GitHub PR target for this batch.

Prepared shortlist:

| Target list | Candidate | Fit | Proposed entry text | Pre-submit gate |
|---|---|---|---|---|
| `awesome-foss/awesome-sysadmin` | `Network_Security_Auditor` | Sysadmin security auditing; current repo has MIT license metadata, topics, release, and no broken profile links. | `[Network Security Auditor](https://github.com/SysAdminDoc/Network_Security_Auditor) - Windows security audit runner with compliance mappings and MITRE ATT&CK reporting. ([Source Code](https://github.com/SysAdminDoc/Network_Security_Auditor)) \`MIT\` \`PowerShell\`` | Confirm target section with maintainer convention; likely Monitoring & Status Pages or Miscellaneous. |
| `awesome-foss/awesome-sysadmin` | `win11-nvme-driver-patcher` | Niche Windows storage-driver utility with strong stars, MIT license metadata, topics, and a release download. | `[Win11 NVMe Driver Patcher](https://github.com/SysAdminDoc/win11-nvme-driver-patcher) - GUI tool to enable the experimental Windows Server 2025 NVMe storage driver on Windows 11. ([Source Code](https://github.com/SysAdminDoc/win11-nvme-driver-patcher)) \`MIT\` \`PowerShell\`` | Confirm the list accepts workstation-admin utilities; otherwise keep for a Windows-specific target. |
| `awesome-scripts/awesome-userscripts` | `UserScript-Finder` | Userscript discovery tool with current topics, MIT license metadata, raw install action, and a gap-filling search use case. | `[UserScript Finder](https://raw.githubusercontent.com/SysAdminDoc/UserScript-Finder/main/UserScript-Finder.user.js) - Discover userscripts for the current site across GreasyFork, SleazyFork, and GitHub. ([Source Code](https://github.com/SysAdminDoc/UserScript-Finder))` | Submit one PR only, alphabetize in the best matching Links or Navigation section, and verify no duplicate existing entry. |
| `abhisheknaiidu/awesome-github-profile-readme` | `SysAdminDoc` profile README | Generated public catalog profile with current descriptions, drift checks, and live portfolio feed. | `[SysAdminDoc](https://github.com/SysAdminDoc/SysAdminDoc)` | Submit one PR, choose the best category after reviewing existing Dynamic Realtime / GitHub Actions examples, and keep display name capitalized. |

Deferred candidates:

- `AppManagerNG`, `NovaCut`, `DefenderControl`, `DisableDefender`, and
  `OpenTasker` remain good future candidates, but they should wait until the
  missing-topic report is applied or the target list has a better matching
  category.
- Browser-extension and Android-app lists are fragmented; no stronger active
  target than the userscript/profile/sysadmin lists was identified in this pass.

Areas not fully verified:

- Rendered GitHub light-mode and mobile behavior were inferred from current image URLs and Markdown structure, not re-screenshotted in a browser.
- Portfolio-site implementation details were not inspected in this repo because the portfolio is a separate repository.
- Latest-release asset file names are now enumerated for the 141 visitor-facing release-bearing rows in the latest report; the remaining release work is reliability/cap handling for the REST fallback path.

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
- Improvement opportunities: promote reviewed `topicHints` into catalog-managed hints if needed, then add `forkOf`, `upstreamLicense`, `releaseAssetPolicy`, `stalePolicy`, and `descriptionOwner` fields.

### README Generator

- User value: keeps the public profile accurate without hand-maintained counts and links.
- Entry point: `scripts/sync-profile.ps1 -Write`.
- Main code: `New-Readme`, `Update-Header`, `New-DiscoverySection`, `New-FeaturedSection`, `New-CategorySection`, `New-FirstTimeSetupSection`.
- Current maturity: complete; final verification passed after this refresh.
- Improvement opportunities: generate more of the hand-authored hero/stat section, emit accessible image blocks, and add a stronger "do not hand-edit generated sections" guard.

### Profile Sync Check

- User value: prevents stale, private, renamed, broken, or malformed public profile links.
- Entry point: `scripts/sync-profile.ps1 -Check`.
- Main code: `Test-ProfileState`, `Test-ReadmeExperience`, `Test-LinkTargets`, `Test-HttpUrl`.
- Current maturity: strong; final check passed with zero fatal link failures, zero link warnings, structured metadata drift detail, parallel link probes, non-mutating topic guidance, generated theme-aware chrome checks, and zero missing public descriptions.
- Improvement opportunities: add doc-version consistency checks and a reviewed apply lane for topic cleanup.

### Public Project Feed

- User value: lets the portfolio site consume the same public catalog state as the README.
- Entry point: `projects.json`.
- Main code: `New-ProjectsExportJson`.
- Current maturity: complete but underused until the portfolio consumes it.
- Improvement opportunities: add sort keys, age buckets, release-asset taxonomy, public-safe topic-hint fields, and generated freshness flags.

### Privacy and Medical-Keyword Gate

- User value: keeps private or sensitive repos out of the public README.
- Entry point: `scripts/sync-profile.ps1 -Check`.
- Main code: `$MedicalPattern`, `Test-ProfileState`, `allowPublicMedical`, `suppressionReason`.
- Current maturity: complete; final report shows zero private visibility and zero medical privacy violations.
- Improvement opportunities: add a public report section that lists only counts and generic reasons while keeping sensitive names out of public docs.

### Link Validation

- User value: avoids dead install, launch, userscript, entrypoint, and release links.
- Entry point: `Test-LinkTargets`.
- Main code: `Test-HttpUrl`, `ConvertTo-RawGitHubUrl`, `Get-ReleaseUrl`.
- Current maturity: parallelized and tolerant of transient failures; latest report checked 185 targets in 5217 ms with zero warnings.
- Improvement opportunities: shorter per-host timeout tuning, header/non-catalog URL validation, and cached validation in CI artifacts.

### First-Time Setup Flow

- User value: gives new Windows users a one-paste way to install Python and Git before running snippets.
- Entry point: README First-time setup section and `setup.ps1`.
- Main code: `Install-Pkg`, `Update-PathFromRegistry`, `Test-Cmd`.
- Current maturity: useful and straightforward.
- Improvement opportunities: `#Requires -Version 5.1`, `-CheckOnly`, transcript logging, and an inspect-before-run path.

### GitHub Actions Automation

- User value: scheduled/manual validation, optional generated-profile PR, workflow security scanning, and Scorecard signal.
- Entry points: `.github/workflows/profile-sync.yml`, `tests.yml`, `workflow-security.yml`, `scorecard.yml`.
- Current maturity: good; actions are pinned and checkout credentials are not persisted.
- Improvement opportunities: add a docs-only validation path and a quicker `-SkipLinkValidation` matrix leg plus a scheduled full-link leg.

### Public Changelog and Roadmap

- User value: records profile releases and separates completed generated-profile work from remaining planning items.
- Entry points: `CHANGELOG.md`, `ROADMAP.md`, `COMPLETED.md`.
- Current maturity: useful, but planning docs should stay synchronized with v4.9.x updates.
- Improvement opportunities: keep current version, latest sync date, and active open items in lockstep with profile sync releases.

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

**Positioning:** do not compete as a generic profile generator; the defensible position is a live, trustworthy, sysadmin-oriented catalog plus a richer portfolio. The README is the compact catalog; interactivity belongs on the portfolio. Generated truth is the moat.

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

## Quick Wins

- Run generated metadata refresh whenever `-Check` reports `readmeInSync=false` or fatal `metadataDrift` rows; raw `projectsExportInSync=false` can now be informational when only star/topic/`pushedAt` metadata changed.
- Review the generated topic hints before any cross-repo topic mutation.
- Add `#Requires -Version 5.1` and `-CheckOnly` to `setup.ps1`.
- Add a Pester fixture for the nonfatal link-warning path.
- Add a generated warning banner around generated README sections.

## Larger Bets

- Portfolio search and freshness views from `projects.json`.
- Release asset taxonomy across all release-bearing repos.
- Modularizing the PowerShell generator into fetch, model, render, validate, and report layers.
- Action-baked or self-hosted profile image assets to reduce live third-party widget dependence.
- Reviewed topic cleanup across public repos after an explicit allowlist is approved.

## Explicit Non-Goals

- Do not put JavaScript search or filtering inside the GitHub profile README; use the portfolio site.
- Do not replace the generated catalog with a generic profile README template.
- Do not add badge-heavy decoration that competes with the project catalog.
- Do not use private repository data for public stats, widgets, or feed generation.
- Do not mutate topics or descriptions across other repos without a reviewed allowlist.
- Do not rename existing public repos just to resolve naming debt; preserve links and stars.

## Deep-Research Addendum — 2026-06-03

This addendum is a fresh, code-first pass after the planning-doc consolidation. It reads the generator end-to-end and adds findings that the prior refresh did not capture. Prior [Verified] findings above stand.

### Executive summary (addendum)

A line-by-line read of `scripts/sync-profile.ps1` (1,495 lines), the four workflows, the Pester suite, and `setup.ps1`, plus live verification, surfaced net-new gaps that sit outside the existing roadmap. The single highest-value finding is that the public feed advertises two JSON Schema URLs that return 404 — the downstream contract is dangling. The second tier is automated-guard gaps: there is no version/date consistency check across planning docs, the link gate ignores the hand-authored hero (including the portfolio link itself), and the privacy-critical `Test-ProfileState` gate has no direct unit test. The third tier is community-health and reliability hygiene: no SECURITY.md despite shipping Scorecard/zizmor, an N+1 REST release-fallback that can blow the unauthenticated rate limit, and no generated-README size budget.

Top addendum opportunities (one line each):

1. P1 — The `schema` URLs in catalog and `projects.json` are 404; publish them or repoint, then validate the feed. [Verified]
2. P1 — No automated version/date consistency gate across ROADMAP/CHANGELOG/PROJECT_CONTEXT. [Verified]
3. P1 — `Test-ProfileState` (the private/medical/visibility gate) has zero direct Pester coverage. [Verified]
4. P2 — Link validation never probes the hero/portfolio/image-host URLs. [Verified]
5. P2 — REST release-fallback is an unbounded per-repo N+1 (~184 calls) with no rate-limit awareness. [Verified]
6. P2 — No catalog JSON-shape validation; unknown `downloadKind` silently defaults. [Verified]
7. P2 — No generated-README size budget (file is ~72 KB and grows unbounded). [Verified]
8. P2 — No SECURITY.md though Scorecard scores its presence. [Verified]
9. P3 — No `.editorconfig`/markdownlint contract for the large mixed-authorship README. [Verified]
10. P3 — Third-party render-host privacy exposure is undocumented as a decision. [Likely]

### Evidence reviewed (addendum)

- `scripts/sync-profile.ps1` read in full: fetch (`Get-GitHubRepos`, `Get-GitHubReposFromRest`), normalization (`ConvertTo-EntryHashtable`, `Get-Catalog`), rendering (`New-Readme`, `New-CategorySection`, `Update-Header`), feed export (`New-ProjectsExportJson`), validation (`Test-ProfileState`, `Test-LinkTargets`, `Test-HttpUrl`, `Test-ReadmeExperience`), and the lossy reverse parser (`New-CatalogFromReadme`).
- `.github/workflows/profile-sync.yml`, `tests.yml`, `workflow-security.yml`, `scorecard.yml`; `.github/dependabot.yml`, `.github/CODEOWNERS`.
- `tests/sync-profile.Tests.ps1` (+ `tests/fixtures/catalog.json`), `setup.ps1`, generated `README.md` (73,358 bytes), `data/profile-catalog.json:1` (schema pointer), `reports/profile-sync-report.json`.
- Git range reviewed: `git log -30 --oneline` through `89cabeb` (consolidation HEAD).
- Live verification: `https://sysadmindoc.github.io/schemas/profile-projects.v1.json` → **HTTP 404** [Verified]; root listing confirms no `SECURITY.md`/`CITATION.cff`/`.editorconfig`/`.markdownlint*` [Verified].
- Not verified this pass: rendered GitHub light-mode/mobile appearance; the live `sysadmindoc.github.io` portfolio implementation (separate repo); whether an authenticated CI token already lifts the REST fallback's rate ceiling [Needs validation].

### Quality & friction findings (addendum, severity-tagged)

- **Major — Dangling feed contract.** `projects.json`/catalog advertise `schema` URLs that 404. Consumers following the contract get a dead link; the feed shape is unenforceable. → roadmap "Publish (or stop referencing) the JSON Schema URLs". `scripts/sync-profile.ps1:1086,1264`. [Verified]
- **Major — Unguarded planning-doc version drift.** Version/date are hand-typed in three tracked docs with no check; the existing alignment item is manual only. → "self-contained version/date consistency gate". [Verified]
- **Major — Privacy gate is untested.** `Test-ProfileState` (private-visibility + medical-keyword + drift) has no direct unit test; only the regex string is tested. A regression in the gate that keeps private/medical repos off the public profile would pass CI. → "Cover the safety-critical functions". `scripts/sync-profile.ps1:1324-1442`, `tests/sync-profile.Tests.ps1`. [Verified]
- **Minor — Hero links unvalidated.** The link gate iterates only catalog entries, so the portfolio link, the `setup.ps1` blob link, and seven third-party image hosts are never probed. → "Extend link validation to hero/header". `scripts/sync-profile.ps1:476-528`. [Verified]
- **Minor — REST fallback N+1.** Per-repo `gh api releases/latest` in the fallback (~184 calls) with no rate-limit handling; a partial fetch yields a silently incomplete feed. → "Cap and authenticate the REST release-fallback". `scripts/sync-profile.ps1:148-162`. [Verified]
- **Minor — Silent unknown-kind fallthrough.** `Get-DownloadLabel` `default { "Download" }` swallows an unrecognized `downloadKind`; no catalog-shape validation catches the typo. → "Add catalog JSON-shape validation". `scripts/sync-profile.ps1:546`. [Verified]
- **Minor — No size budget.** ~72 KB generated README with no growth guard; GitHub truncates long profile READMEs. → "generated-README size budget guard". [Verified]
- **Minor — No SECURITY.md.** Repo runs Scorecard/zizmor but lacks a security policy Scorecard scores. → "Add SECURITY.md". [Verified]
- **Cosmetic — No whitespace/lint contract.** Large mixed-authorship README with no `.editorconfig`/markdownlint; hero whitespace can drift the generated diff. → "Add `.editorconfig` and a markdown lint pass". [Verified]
- **Cosmetic — Undocumented render-host exposure.** komarev counter + four stats hosts see every visitor via Camo; no recorded decision. → "Document/justify the third-party render-host privacy exposure". [Likely]

### Competitive & standards notes (addendum)

This is internal profile/portfolio tooling, so the bar is best-practice and platform standards rather than consumer competitors:

- **OpenSSF Scorecard** — explicitly scores Security-Policy, Pinned-Dependencies, Token-Permissions, and Maintained. The repo already pins actions and sets least-privilege `contents: read`; the missing Security-Policy is a concrete, gradeable gap. Avoid: treating the Scorecard badge as proof while the policy file is absent.
- **JSON Schema (2020-12)** — a published `$schema`/contract is the standard way to let a feed consumer validate. The advertised URLs should resolve and the feed should validate against them; the portfolio repo is the natural home. Avoid: advertising a schema URL that does not exist (current state).
- **GitHub community-health files** — `SECURITY.md`, and optionally `CITATION.cff`, are the documented community-standards set GitHub surfaces; a flagship profile repo benefits from completing the checklist. Avoid: adding PII as a disclosure contact.
- **GitHub anonymized image URLs (Camo)** — confirms third-party README images are proxied, which mitigates but does not eliminate the host-availability and decision-record concerns; pairs with the planned action-baked-SVG work.
- **EditorConfig / markdownlint** — standard whitespace and Markdown contracts for repos with hand-edited Markdown; cheap to add, prevents diff noise in a generated file.

### Open questions raised by the addendum

- Does the CI `GH_TOKEN` already authenticate the REST fallback enough to avoid the 60 req/hr ceiling, or is the N+1 a live risk on scheduled runs? [Needs validation]
- Should the JSON Schemas live in this repo (`schemas/`, referenced by raw URL) or in `sysadmindoc.github.io` under the advertised path? Cross-repo decision. [Needs validation]

## Cycle 2 Research Addendum — 2026-06-04

This addendum was researched while seed-guard work was still in flight and focused only on planning gaps not already covered by the then-open queue. The seed guard has since shipped as v4.9.6, report-schema depth shipped as v4.9.8, and topic/description drift guidance shipped as v4.9.9. The remaining promoted items below still describe future work unless separately checked off in `ROADMAP.md`.

### Executive summary (cycle 2)

The repo has a strong generated-profile core, but the next research gaps are around maintenance confidence and downstream trust rather than visitor-facing catalog layout. Four durable additions were promoted to `ROADMAP.md`: PowerShell static analysis, generated-feed provenance metadata, structured issue/support intake, and a read-only repository/community-health baseline in the sync report. A fifth short-lived but actionable item was added for the currently open Dependabot workflow-action update PRs.

Top cycle 2 opportunities:

1. P1 — Run PSScriptAnalyzer in CI for `scripts/sync-profile.ps1` and `setup.ps1`. [Verified]
2. P1 — Add public-safe feed provenance fields such as source ref, catalog hash, generator hash, and metadata snapshot time. [Verified]
3. P2 — Add issue forms and PR/contribution templates for broken catalog links and profile corrections. [Verified]
4. P2 — Report repository settings and community-health status alongside generated-profile checks. [Verified]
5. P2 — Triage current Dependabot workflow-action update PRs #5 and #6 with a repeatable SHA-pin review path. [Verified]

### Evidence reviewed (cycle 2)

- At research time, `git pull --rebase` returned already up to date and `git status --short --branch` showed `main...origin/main` plus one in-flight `scripts/sync-profile.ps1` seed-guard edit.
- That in-flight seed-guard work has since shipped as v4.9.6; current worktree state should always be verified live before using this addendum as implementation context.
- `projects.json` top-level metadata currently contains `schema`, `generatedAt`, `source`, and counts, but no source ref, catalog/generator hash, or generator version.
- `.github/workflows/tests.yml` installs and runs Pester only; root/workflow searches found no PSScriptAnalyzer settings file and no `Invoke-ScriptAnalyzer` invocation.
- Live repository metadata: `gh repo view SysAdminDoc/SysAdminDoc` verified `PUBLIC`, MIT, default branch `main`, topics `github-profile`, `portfolio`, `readme`, and latest push/update on 2026-06-04.
- Community profile API: `gh api repos/SysAdminDoc/SysAdminDoc/community/profile` returned `health_percentage=28`, no issue template, no contributing file, no PR template, and no security policy.
- Repository settings API: `gh api repos/SysAdminDoc/SysAdminDoc --jq '{has_issues,has_projects,has_wiki,security_and_analysis}'` showed Issues/Projects/Wiki enabled, secret scanning enabled, push protection enabled, non-provider/generic/validity secret-detection options disabled, and Dependabot security updates disabled.
- Open PRs: `gh pr list -R SysAdminDoc/SysAdminDoc` showed Dependabot PR #5 (`actions/checkout` 4.3.1 -> 6.0.3) and #6 (`github/codeql-action` 3.35.5 -> 4.36.1). `gh pr checks 5` reported Pester and zizmor passing; `gh pr checks 6` reported zizmor passing.

External sources reviewed:

- Microsoft Learn `Invoke-ScriptAnalyzer`: https://learn.microsoft.com/en-us/powershell/module/psscriptanalyzer/invoke-scriptanalyzer?view=ps-modules
- Microsoft Learn `about_Signing`: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5
- GitHub artifact attestations: https://docs.github.com/en/actions/how-tos/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
- GitHub issue and pull request templates: https://docs.github.com/articles/creating-an-issue-template-for-your-repository
- GitHub secret scanning feature docs: https://docs.github.com/en/code-security/secret-scanning/enabling-secret-scanning-features
- GitHub Dependabot action-update docs: https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot

### Quality and friction findings (cycle 2)

- **Major — No static PowerShell analysis.** The repo's critical behavior lives in two `.ps1` files, but CI only runs Pester. Microsoft documents PSScriptAnalyzer as a static checker with `-EnableExit` for CI, making this a low-risk guard before future generator/setup refactors. → roadmap "Add a PowerShell static-analysis lane". [Verified]
- **Major — Feed provenance is too thin for downstream debugging.** `projects.json` tells consumers when it was generated but not what source tree, catalog file hash, or generator script hash produced it. The separate portfolio will consume this feed, so a bad cache or stale generated artifact is hard to diagnose without rerunning the generator. → roadmap "Add generated-feed provenance fields". [Verified]
- **Minor — Public issue intake is unstructured.** The repo has Issues enabled and a long visitor-facing catalog, but no issue forms for broken install snippets, stale release links, or profile corrections. GitHub's template docs support structured forms and PR templates that can steer users away from generated-section hand edits. → roadmap "Add structured issue/support intake". [Verified]
- **Minor — GitHub-hosted settings are invisible to `-Check`.** Secret scanning and push protection are currently enabled, but this trust state is not captured in the sync report and can drift independently of tracked files. Community-health status is also absent from the report. → roadmap "Add a read-only repository settings and community-health baseline". [Verified]
- **Minor — Open workflow-action update PRs need a repeatable review path.** Dependabot is doing its job for pinned actions, but #5 and #6 remain open. The repo should merge or defer them with a standard checklist covering checks, `zizmor`, permissions, and `persist-credentials:false`. → roadmap "Triage current Dependabot workflow-action update PRs". [Verified]
- **Covered, not duplicated — Setup script trust.** Microsoft `about_Signing` reinforces the existing setup hardening row: the inspect-before-run path is the near-term improvement, with Authenticode signing or checksum publication as optional future trust depth if the user chooses a signing certificate path. No separate roadmap item was added to avoid duplicating `setup.ps1` hardening.

### Standards notes (cycle 2)

- **PSScriptAnalyzer** is a better fit than generic shell linting because the repo's active scripts are PowerShell and the official analyzer understands PowerShell-specific rules, severity, settings, and CI exit behavior.
- **Artifact attestation** is likely too heavy for the committed `projects.json` feed today, but the provenance principle applies directly. Start with public-safe feed metadata and hashes; consider attestations later only if generated downloadable assets are introduced.
- **Issue forms** should stay narrowly scoped. This profile repo is not the support desk for every listed project; the forms should capture catalog/link/profile problems and route project-specific bugs to the relevant repository.
- **Repository settings baselining** should be report-only at first. Mutating Issues/Projects/Wiki, secret scanning options, or Dependabot security settings crosses into account/repo administration and should remain a reviewed operator action.

## Cycle 3 Research Addendum — 2026-06-04

This pass focused on operator experience around the richer v4.9.8/v4.9.9 sync report. It did not find a need for another catalog feature; the gap is that CI already produces useful report data but does not surface its important findings on the workflow run page.

### Evidence reviewed (cycle 3)

- `.github/workflows/profile-sync.yml` runs `./scripts/sync-profile.ps1 -Check`, then uploads `reports/profile-sync-report.json` as the `profile-sync-report` artifact. There is no `$GITHUB_STEP_SUMMARY` write, no warning/error annotation step, and no explicit artifact `retention-days`.
- `reports/profile-sync-report.json` now contains high-signal sections that are worth summarizing directly: `metadataHygiene`, `releaseAssetDrift`, `validationPerformance`, `metadataDriftSummary`, `linkValidationSummary`, and README experience checks.
- `gh api repos/SysAdminDoc/SysAdminDoc/actions/runs` showed the latest scheduled Profile sync runs before the current fixes concluded failure, making fast triage from the run summary more useful than artifact-only reporting.
- GitHub's workflow-command docs state that job summaries can be written as GitHub-flavored Markdown through the `GITHUB_STEP_SUMMARY` environment file and that warnings/errors can create annotations in workflow logs: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions

### Finding (cycle 3)

- **Minor — Profile sync results are artifact-only.** The workflow preserves the JSON report, but the run page does not show the key counts that decide whether a maintainer should regenerate, fix links, triage metadata hygiene, or ignore an informational warning. → roadmap "Surface profile-sync results in GitHub Actions job summaries". [Verified]

### Standards note (cycle 3)

- Keep the job summary public-safe and aggregate-first: counts, warning hosts, fatal drift totals, and generic hygiene summaries are useful; private/suppressed repo names should stay out of the run summary unless already public-safe in the committed report.

## Cycle 4 Research Addendum — 2026-06-04

This pass audited live repository governance settings rather than the generated catalog. The new finding is operator/admin-gated because it changes GitHub branch-protection or ruleset settings, not source code.

### Evidence reviewed (cycle 4)

- `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection --jq '{required_status_checks,required_pull_request_reviews,required_conversation_resolution,enforce_admins,allow_force_pushes,allow_deletions,required_linear_history,required_signatures}'` returned `required_status_checks=null` and `required_pull_request_reviews=null`, while `required_conversation_resolution.enabled=true`, `enforce_admins.enabled=true`, `allow_force_pushes.enabled=false`, and `allow_deletions.enabled=false`.
- `gh api repos/SysAdminDoc/SysAdminDoc/rulesets` returned an empty list, so no repository ruleset currently compensates for the missing required status checks.
- Existing workflows already expose candidate checks: Pester, workflow security (`zizmor`), Scorecard, and Profile sync. The branch policy should require only stable, intentional check names to avoid blocking merges on ambiguous or path-skipped checks.
- GitHub's protected-branch docs state that required status checks can require checks to pass before merging and note that duplicate job names can create ambiguous results: https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches/
- GitHub ruleset docs describe rulesets as another way to control branch/tag interactions and require status checks, with evaluate/enforce modes and bypass options: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository

### Finding (cycle 4)

- **Major — Main branch checks are not enforced by branch policy.** The repo has useful validation workflows and partial branch protection, but live settings do not require those checks before merge. A generated-profile, Pester, or workflow-security regression can become a policy miss if a maintainer merges without manually reviewing checks. → roadmap "Require validation status checks on `main`". [Verified]

### Standards note (cycle 4)

- Prefer starting in an evaluated ruleset or a narrow branch-protection update if there is uncertainty about path-filtered workflows. Required checks should use unique, stable job names and should not require scheduled-only checks that do not run on pull requests.

## Cycle 5 Research Addendum — 2026-06-04

This pass checked whether generated-profile validation currently runs on pull requests. The new finding is a prerequisite for the branch-protection work: a status check can only be required safely if it is created on the pull requests where maintainers need it.

### Evidence reviewed (cycle 5)

- `.github/workflows/profile-sync.yml` currently has `workflow_dispatch` and the twice-weekly `schedule`, but no `pull_request` or `push` trigger for profile-pipeline changes.
- `.github/workflows/tests.yml` runs on `pull_request` and `push`, but its path filters are limited to `scripts/**`, `tests/**`, and `.github/workflows/tests.yml`; they omit `data/profile-catalog.json`, `README.md`, `projects.json`, and `reports/profile-sync-report.json`.
- `gh run list -R SysAdminDoc/SysAdminDoc --limit 10 --json workflowName,event,conclusion,status,createdAt` showed recent push-triggered `Tests` runs and Dependabot PR checks, but no push/PR-triggered `Profile sync` run.
- GitHub's workflow syntax docs state that `push` and `pull_request` events can be filtered by changed paths and warn that skipped required checks remain pending, which matters if profile-sync becomes a required check: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax

### Finding (cycle 5)

- **Major — Generated-profile validation is not a PR check today.** The repo has a strong `scripts/sync-profile.ps1 -Check` gate, but it is only scheduled or manually dispatched for the profile-sync workflow. A PR can change the catalog, generated README, public feed, or committed report without automatically producing a profile-sync status. → roadmap "Run profile-sync validation on profile/catalog pull requests". [Verified]

### Standards note (cycle 5)

- Keep the PR trigger path-scoped but branch-policy-aware: either do not require the path-skipped check globally, or pair it with an always-running lightweight status that reports "not applicable" for unrelated changes. This avoids GitHub's pending skipped-check behavior while still gating profile-pipeline edits.

## Cycle 6 Research Addendum — 2026-06-04

This pass focused on workflow reliability budgets after profile validation, Scorecard, workflow security, and the in-flight committed-asset refresh path all depend on external package, GitHub API, or HTTP work.

### Evidence reviewed (cycle 6)

- `rg -n "timeout-minutes" .github/workflows` returned no timeout declarations in `profile-sync.yml`, `tests.yml`, `workflow-security.yml`, or `scorecard.yml`.
- The in-flight `.github/workflows/assets-refresh.yml` also has no job or step timeout while running `scripts/sync-profile.ps1 -Write -Check` and creating a generated-assets pull request.
- The workflows contain live-network or package-install steps: Pester installation from PSGallery, `python -m pip install --upgrade zizmor`, OpenSSF Scorecard, GitHub API-backed profile sync, link validation, and generated PR pushes.
- Recent `gh run list -R SysAdminDoc/SysAdminDoc --limit 10` results were short and successful for Tests/Workflow security, so this is a failure-budget control rather than a response to a current slow run.
- GitHub's workflow syntax docs state that job-level `timeout-minutes` defaults to 360 minutes and step-level `timeout-minutes` can cap individual steps: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax

### Finding (cycle 6)

- **Minor — Workflow jobs have no explicit timeout budget.** The current workflows are expected to finish in seconds or a few minutes, but a stuck external dependency or long REST fallback would wait on GitHub's broad default job timeout. → roadmap "Add explicit GitHub Actions timeout budgets". [Verified]

### Standards note (cycle 6)

- Use job-level budgets first, with step-level caps only for known live-network or package-install steps. The budgets should leave enough room for full link validation and release-asset refresh, but they should be short enough that a stall is clearly an infrastructure failure rather than an ambiguous validation result.

## Open Questions

- Should generated `topicHints` stay report-only, or should reviewed hints be promoted into catalog-managed metadata?
- Should low-risk generated metadata drift be auto-PR'd on schedule, or should scheduled jobs remain check-only with manual `write-pr`?
- Should `PROJECT_CONTEXT.md` stay tracked as public project documentation, or should it be reduced to public-safe status notes only?
- What is the portfolio site's preferred schema contract for search and freshness fields from `projects.json`?
- Should `projects.json` provenance stop at hashes/source refs, or should a later generated-asset workflow emit GitHub artifact attestations if the repo starts publishing downloadable generated bundles?
- Should issue templates live only in this repo, or should the account-level `.github` community-health repo carry shared catalog/link templates for all public SysAdminDoc repositories?
- Which checks should be required on every pull request versus only on path-filtered profile-pipeline changes if branch protection/rulesets are tightened?
- Should profile-sync PR validation use a path-filtered workflow, an always-run workflow with internal no-op logic, or a pair of checks so branch protection never waits on skipped profile-sync runs?
- What timeout budget should be treated as normal for full live profile validation once committed SVG asset refresh and release-asset checks both run in the same automation path?
