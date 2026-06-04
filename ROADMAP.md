# SysAdminDoc Profile Roadmap

> Single source of truth for all planned work. Items above the --- are existing plans; items below are research conducted 2026-06-03.

Last research refresh: 2026-06-04
Evidence bundle: `RESEARCH_REPORT.md` (archived source: `docs/archive/research-feature-plan-2026-06-04.md`)
Latest profile sync: 2026-06-04
Current repo version: v4.9.24
Research baseline HEAD: `3d4ed8f Release v4.7.0 -- catalog refresh, drop private-repo refs`
P0 implementation baseline: `1fe3830 Consolidate profile research roadmap`

> Last researched: Cycle 8 - 2026-06-04.

## ▶ Implementer Instructions (for the build machine)

This roadmap is fed continuously by an automated research machine. On every
pass, the implementing machine should:

1. `git pull --rebase` to get the latest researched items before starting.
2. Work the open 🤖 items top-down by priority (P0 → P3). Build them properly:
   multi-file structure, real error handling, no runtime auto-install hacks,
   version strings synced, docs/CHANGELOG updated in the same commit.
3. In ADDITION to building items, run a FULL UX AUDIT each pass — do not skip
   it even when the queue is full. Walk every screen / page / dialog / form /
   table / empty-loading-error-disabled state across light/dark/high-contrast
   themes. Check: onboarding, navigation clarity, spacing/contrast/alignment,
   clipping/overflow, hierarchy, microcopy, destructive-action guards,
   keyboard + screen-reader accessibility, and trust signals. Fix what you find,
   or file it back as a new 🤖 roadmap item if it is larger than a pass.
4. Check off ✅ each item you complete (leave it in place with the checkmark),
   commit per logical change with a "why" message, and push.
5. Never edit this Implementer Instructions block or the 🔬 Researcher Queue
   headings — the research machine owns those. Never force-push.

Last researched: Cycle 8 - 2026-06-04.

2026-06-04 v4.9.24 refresh: the "Forge" naming-debt item was logged as a
documentation-only decision. Existing live repositories named WinForge,
FirewallForge, NetForge, PathForge, GitForge, ImageForge, ClipForge, IconForge,
and MediaForge are retained to avoid breaking links, releases, stars, and
install snippets; new repository names should avoid the "Forge" pattern unless
there is an explicit naming exception. Verification ran
`scripts/sync-profile.ps1 -Write -Check` with
`docVersionConsistency.passed=true`, `projectsExportInSync=true`, 0 metadata
drift rows, 0 link failures, and 0 link warnings after REST fallback from a
transient GitHub GraphQL 502.

2026-06-04 v4.9.23 refresh: fork/continuation attribution shipped.
`data/profile-catalog.json` now supports structured `forkOf` and
`upstreamLicense` fields, generated `projects.json` emits `forkOf`,
`forkOfUrl`, and `upstreamLicense`, and README featured/category/currently
building rows render a compact upstream/license line for forked or continued
projects. AppManagerNG, uBlockVanced, LTSC-MicrosoftStore, RcloneBrowser,
TabExplorer, Vigil, and TagStudio now carry explicit attribution metadata.
Verification ran `Invoke-Pester -Path tests -Output Detailed` (44/44) and
`scripts/sync-profile.ps1 -Write -Check` with `schemaValidation.passed=true`,
`projectsExportInSync=true`, 0 metadata drift rows, 0 link failures, and 0 link
warnings after REST fallback from a transient GitHub GraphQL 502.

2026-06-04 v4.9.22 refresh: the WolfPack catalog-hygiene item shipped.
WolfPack moved out of Security & Networking into Native Desktop Applications,
and Vigil moved from Misc & Forks into the same desktop group so the
privacy/browser packaging entries render adjacent to one another. Generated
counts are now Security & Networking 3, Native Desktop Applications 19, and
Misc & Forks 5. Verification ran `scripts/sync-profile.ps1 -Write -Check` with
`readmeInSync=true`, `projectsExportInSync=true`,
`docVersionConsistency.passed=true`, 0 metadata drift rows, 0 link failures, and
0 link warnings.

2026-06-04 v4.9.21 refresh: `setup.ps1` hardening shipped. The bootstrapper
now declares `#Requires -Version 5.1`, supports `-CheckOnly` diagnostics for
winget, Python, pip, and Git without installing, writes a best-effort transcript
under `%TEMP%`, and preserves the existing one-paste `irm ... | iex` install
path. The generated First-time setup README section now includes an
inspect-before-install command path, and `readmeExperienceChecks` records
`setupInspectPath=true`. Verification ran `Invoke-Pester -Path tests -Output
Detailed` (42/42), `setup.ps1 -CheckOnly`, `scripts/sync-profile.ps1 -Write
-Check` with `setupInspectPath=true`, `projectsExportInSync=true`, 0 metadata
drift rows, 0 link failures, and 0 link warnings after REST fallback from a
transient GitHub GraphQL 502, plus `rtk git diff --check`.

2026-06-04 v4.9.20 refresh: the public planning-doc sync item and the
research-driven doc version/date consistency gate were implemented in
`scripts/sync-profile.ps1`. `Test-DocVersionConsistency` now reads
`ROADMAP.md`, `CHANGELOG.md`, `PROJECT_CONTEXT.md`, and `RESEARCH_REPORT.md`,
records `docVersionConsistency` in `reports/profile-sync-report.json`, and
causes `-Check` to fail on a version mismatch or on a planning sync date older
than the latest changelog date. Verification ran `Invoke-Pester -Path tests
-Output Detailed` (38/38), `scripts/sync-profile.ps1 -Write -Check` with
`docVersionConsistency.passed=true`, `projectsExportInSync=true`, 0 metadata
drift rows, 0 link failures, and 0 link warnings after REST fallback from a
transient GitHub GraphQL 502, plus `rtk git diff --check`.

2026-06-04 v4.9.19 refresh: the advertised JSON Schema contract item was
implemented in this repo. `data/profile-catalog.json` and generated
`projects.json` now point to committed raw-GitHub schema URLs under `schemas/`,
`scripts/sync-profile.ps1 -Check` validates the normalized catalog and generated
project feed against those schemas, and `reports/profile-sync-report.json`
records `schemaValidation` with passing catalog/projects checks. The feed
generator now emits `releaseAssetKinds`, `releaseAssetNames`, and `topics` as
arrays for all rows, including zero- and one-item cases. Verification ran
`Invoke-Pester -Path tests -Output Detailed` (35/35), `scripts/sync-profile.ps1
-Write -Check` with REST fallback after transient GitHub GraphQL 502, JSON parse
checks for schemas/feed/report, and `rtk git diff --check`.

2026-06-04 v4.9.18 refresh: the live profile-feed portfolio item was
implemented in `C:\Users\--\repos\sysadmindoc.github.io` commit
`9117f45 feat(data): render portfolio from profile feed`, then pushed to
GitHub. The portfolio now fetches
`https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/projects.json`
into an ignored build-time cache, renders catalog/project routes/search feeds
from `src/data/portfolio.ts`, excludes suppressed/non-portfolio rows, and keeps
local featured/live-app overlays plus local fallback data. Verification ran
`npm run check`, `npm run build`, `npm test`, `rtk git diff --check`, and a
build-output assertion confirming 177 feed projects, profile-feed source
metadata, no local-only feed omissions, no `DuplicateFF` route, and a present
`ZeusWatch` route. A focused Chrome CDP browser check also covered 177 cards,
129 download rows, no suppressed/local-only cards, `DuplicateFF` 404, and no
mobile horizontal overflow at 390 px.

2026-06-04 v4.9.17 refresh: the portfolio freshness/download views item was
implemented in `C:\Users\--\repos\sysadmindoc.github.io` commit
`29c2b1d feat(catalog): add freshness and download views`, then pushed to
GitHub. The portfolio now has URL-backed All, New, Recently updated, and Has
download catalog views derived from tracked catalog rows, cached GitHub metadata,
and release download totals. Verification ran `npm run check`, `npm run build`,
`npm test`, and a focused Chrome CDP browser check covering 181 all / 147 new /
173 recently updated / 20 has-download results, combined `view=recent&cat=web&q=Nuke`
hydration, and no mobile horizontal overflow at 390 px.

## Project-Specific Implementer Notes

- Treat `data/profile-catalog.json` and `scripts/sync-profile.ps1` as the source
  of truth for generated README/feed content. Do not hand-edit generated README
  sections except through the generator.
- Keep the public profile sanitized: suppress private repos, medical/private
  project names, employer-specific details, and stale install snippets that
  would 404 for visitors.
- For profile changes, run `Invoke-Pester -Path tests`, then
  `scripts/sync-profile.ps1 -Check`; use `-SkipLinkValidation` only for a
  structural fast path and record that live-link validation was skipped.
- Generated reports are evidence, not planning docs. Commit
  `reports/profile-sync-report.json` only with an intentional `-Write`/`-Check`
  sync batch, not as part of a research-only handoff.
- Researcher-queue ownership tags: `🤖` means implementer-actionable, `🔧`
  means user/external/manual gated, `🔬` means researcher-added this cycle, and
  `✅` means implemented/closed by the build lane.

2026-06-04 v4.9.16 refresh: the portfolio Pagefind item was closed as already
implemented in `C:\Users\--\repos\sysadmindoc.github.io`. The separate portfolio
repo has `/search/`, Pagefind Component UI, `npm run search:index`, project
Category filter and Type metadata, and no-JS fallback links. Verification ran
`npm run build` in the portfolio repo: data/assets/images audits passed, Astro
built 198 pages, the service worker stamped to v0.18.1, and Pagefind v1.5.2
indexed 198 HTML pages, 18,774 words, and 1 filter into `dist/pagefind`. The
portfolio repo worktree remained clean.

2026-06-04 v4.9.15 refresh: dependency/status badge cleanup removed the
redundant Shields follower/star image badges from the generated profile header,
moved the useful public-star signal into the committed local stats SVG, and made
header regeneration idempotent by stripping previously generated stats chrome
before appending the current block. `readmeExperienceChecks` now reports
`thirdPartyBadgeHostCount=0` and `profileStatsChromeCount=1`. Pester passed
32/32, and full `-Write -Check` passed with `profileAssetsInSync=true`, 6 asset
checks, 0 third-party metric hosts, 0 third-party badge hosts, 185 link targets
checked in 5217 ms, 0 link failures, and 0 link warnings. The run used the REST
metadata fallback after a transient GitHub GraphQL 502.

2026-06-04 v4.9.13 refresh: release asset taxonomy now inspects uploaded
latest-release asset names, exports `releaseAssetKinds` and `releaseAssetNames`
in `projects.json`, compares catalog `downloadKind` labels against actual asset
kinds, and keeps source-only latest releases as `Repo` actions. Catalog labels
were corrected for `ScriptVault` and `RumbleX`; `Vantage` is source-only until
installer assets are uploaded. Pester passed 31/31, and full
`-Write -Check` passed with 141 inspected release rows, 71 release actions, 17
source-only release rows, 0 release asset kind mismatches, 0 release asset fetch
failures, 185 link targets checked in 4404 ms, 0 link failures, and 0 link
warnings. The run used the REST metadata fallback after a transient GitHub
GraphQL 502.

2026-06-04 v4.9.14 refresh: profile metric chrome now uses committed local
dark/light SVG panels under `assets/profile/` for catalog stats, language mix,
and release asset health. The komarev counter and third-party stats/streak/
activity render hosts were removed from the generated README. `profileAssetsInSync`
and per-asset report checks validate the six committed SVG assets, and the new
`assets-refresh.yml` workflow can refresh them on schedule or by dispatch.
Pester passed 32/32, and full `-Write -Check` passed with
`profileAssetsInSync=true`, 6 asset checks, 0 third-party metric hosts, 185 link
targets checked in 4289 ms, 0 link failures, and 0 link warnings.

2026-06-04 v4.9.12 refresh: theme-aware README chrome now renders through
dark/light `<picture>` sources for the header, typing SVG, skill icons, stats,
streak card, activity graph, and footer. The generated header also includes a
plain-text tagline and descriptive alt text. Pester passed 30/30, and full
`-Write -Check` passed with `themeAwareImageChrome=true`,
`plainTextTagline=true`, `meaningfulImageAltText=true`, 0 generic image alt
labels, 239 link targets checked in 6041 ms, 0 link failures, and 0 link
warnings. The run used the REST metadata fallback after a transient GitHub
GraphQL 502.

2026-06-04 v4.9.11 refresh: the awesome-list batch prepared a curated
submission plan in `RESEARCH_REPORT.md` using current catalog data, live target
list metadata, and contribution-guideline checks. The prepared shortlist covers
`Network_Security_Auditor`, `win11-nvme-driver-patcher`, `UserScript-Finder`,
and the `SysAdminDoc` profile README. No external pull requests were opened in
this repo batch.

2026-06-04 v4.9.10 refresh: the four empty public GitHub repository
descriptions reported by `metadataHygiene` were filled for `AdapterLock`,
`facebook-exit-guide`, `IMDb_Enhanced`, and `SysAdminDoc`. The regenerated
report now shows 69 missing-topic rows, 0 missing-description rows, 239 link
targets checked in 6812 ms, 0 link failures, and 0 link warnings. Pester passed
28/28.

2026-06-04 v4.9.9 refresh: metadata hygiene now includes non-mutating
`topicHints` for missing-topic repos, catalog categories for topic/description
cleanup, catalog-backed description suggestions, and an explicit policy that any
future apply mode must require an allowlist. Pester passed 28/28 and full
`-Write -Check` passed with all 69 missing-topic rows carrying hints, 4
missing-description rows, 3 catalog-backed description suggestions, 239 link
targets checked in 5882 ms, 0 link failures, and 0 link warnings.

2026-06-04 v4.9.8 refresh: report schema depth now includes
`metadataHygiene`, `releaseAssetDrift`, and `validationPerformance` sections.
The v4.9.8 live report recorded 69 repos missing topics, 4 missing descriptions,
177 visitor-facing release-drift rows checked, 141 release-bearing rows, 102
release-action rows, 16 source-only rows with releases, and 239 link targets
checked in 6801 ms. Pester passed 26/26 and full `-Write -Check` passed with 0
metadata drift rows, 0 link failures, and 0 link warnings.

2026-06-04 v4.9.7 refresh: live link validation now collects URL targets first
and probes them in bounded parallel batches with throttle 16. The report adds
`linkValidationSummary` with target count, throttle, elapsed milliseconds, and
`warningCountByHost`. Pester passed 24/24, and the full live `-Write -Check`
passed with 239 link targets checked in 6835 ms, 0 link failures, and 0 link
warnings.

2026-06-04 v4.9.6 refresh: the legacy `-SeedCatalog` parser is now guarded
behind explicit `-ForceSeedCatalog`, prints a lossy one-shot bootstrap warning,
and seed-only mode exits after writing the catalog instead of entering normal
render/check flow. Pester passed 23/23, and the full live `-Write -Check`
passed with `readmeInSync=true`, `projectsExportInSync=true`, 0 metadata drift
rows, 0 link failures, and 0 link warnings.

2026-06-04 v4.9.5 refresh: the metadata-drift batch added structured
`metadataDrift` report rows plus `metadataDriftSummary`, including
fatal/informational counts and a 7-day stale `projects.json.generatedAt`
warning. Pester passed 20/20, and the full live check is green with
`readmeInSync=true`, 0 fatal metadata drift rows, full link validation enabled,
0 link failures, and 0 link warnings. `projectsExportInSync` remains a raw
exact-equality signal; info-only `pushedAt`/star/topic drift is surfaced without
failing the gate.

2026-06-04 v4.9.4 refresh: the P0 generated drift-lockout batch added a
generated-catalog notice, checked that marker in README experience validation,
refreshed generated header counts, and changed the manual write-PR workflow to
run `scripts/sync-profile.ps1 -Write -Check` in one metadata snapshot. Pester
passed 18/18, and the full write/check pass is green with
`readmeInSync=true`, `projectsExportInSync=true`, full link validation enabled,
0 link failures, and 0 link warnings.

## Current Diagnosis

This repository is the public GitHub profile README for `SysAdminDoc`. As of v4.9.10, the README is generated from `data/profile-catalog.json` plus live GitHub metadata through `scripts/sync-profile.ps1`, with a hand-authored LinkedIn-aligned hero section preserved above the generated catalog.

Live GitHub metadata gathered through 2026-06-04 showed:

- 184 active public repos visible through GitHub metadata.
- 177 catalog entries included in the public README and 9 public/private-state entries explicitly suppressed with reasons.
- 0 active public repos missing from the generated catalog after v4.9.0.
- 0 renamed-repo redirects after removing the duplicate `EspressoMonkey` profile row.
- 0 private visibility or medical-imaging privacy violations in `scripts/sync-profile.ps1 -Check`.
- 69 active public repos with no topics and 0 public repos with empty descriptions.
- `.github/` contains scheduled/manual profile sync, workflow security, Scorecard, CODEOWNERS, and Dependabot configuration.
- `scripts/sync-profile.ps1 -Check` validates install entrypoints, raw userscripts, GitHub Pages launch links, release/latest redirects, generated README navigation, action columns, category anchors, and primary-action coverage.
- Link validation runs in bounded parallel batches and reports target count, elapsed time, throttle, and warning counts by host.
- `reports/profile-sync-report.json` now includes metadata hygiene, release/download drift, and validation-performance sections for downstream audits.
- Missing-topic report rows now include generated `topicHints`; the four previously empty public descriptions have been filled on GitHub. The report does not mutate other repositories.
- `scripts/sync-profile.ps1 -Check` reports structured `metadataDrift` rows for committed-vs-live feed drift; branch/release/action/suppression drift is fatal, while stars, topics, and `pushedAt` are informational.
- Legacy README reverse parsing through `-SeedCatalog` now requires explicit `-ForceSeedCatalog` and is documented as a lossy one-shot bootstrap, not a routine source-of-truth path.
- Root `projects.json` is generated from the same catalog for portfolio consumption and includes structured primary-action metadata.
- The first-viewport profile copy leads with healthcare IT, DICOM/PACS specialization, 16+ years of infrastructure experience, 10+ production platforms, and quantified proof points while avoiding private project and employer-specific names.

One prior roadmap idea was retired: search boxes and filter chips cannot run inside the GitHub profile README because GitHub sanitizes rendered markup, including script tags and inline styles. Interactive search/filtering belongs in `sysadmindoc.github.io`; this profile README should remain generated static Markdown. (See COMPLETED.md.)

Note: the profile README is an actively-curated surface and may have concurrent curation in flight. README-affecting items below should be executed through the catalog plus regeneration, never by hand-editing the generated sections.

## Existing Planned Work

### Generation integrity and drift enforcement

- [x] P0 — Enforce generated README/feed drift checks (hand-edit lockout)
  - Why: hand edits or live-metadata changes can silently reintroduce drift, broken links, and count mismatches; `-Check` already caught stale generated outputs in the v4.9.3 refresh.
  - Touches: `scripts/sync-profile.ps1` (`New-Readme`, `New-ProjectsExportJson`), `.github/workflows/profile-sync.yml`, optional generated-section banner and local git-hook docs.
  - Acceptance: any edit to a generated section fails `-Check`/CI until `-Write` is re-run; `README.md` carries a "do not hand-edit generated sections" banner; the headline count is generated, not typed.
  - Completed: v4.9.4 added the generated-catalog notice, validation report field, header-count refresh, Pester coverage, and one-process workflow write/check.
  - Source: docs/research-feature-plan-2026-06-04.md (P0); RESEARCH_FEATURE_PLAN (NF1/EI4)

- [x] P2 — Deeper metadata-drift report in `-Check` (NF2)
  - Why: `projectsExportInSync` catches feed drift, but `-Check` does not surface a structured committed-vs-live diff or a stale-`generatedAt` warning.
  - Touches: `scripts/sync-profile.ps1` (new `Test-MetadataDrift`), `reports/profile-sync-report.json` schema.
  - Acceptance: report includes a `metadataDrift` list (repo, field, old→new) and warns when `generatedAt` is older than N days; star drift is informational, structural fields (branch, release tag, visibility) are failing.
  - Completed: v4.9.5 added `Test-MetadataDrift`, `metadataDrift`, `metadataDriftSummary`, 7-day stale-feed warnings, fatal vs informational drift severity, and Pester coverage for star/branch/release/stale-age behavior.
  - Source: TODO.md (NF2); docs/research-feature-plan-2026-06-04.md (Report Schema Depth)

- [x] P2 — Deprecate/guard `-SeedCatalog` legacy parser (EI10)
  - Why: the README→catalog reverse parser (`New-CatalogFromReadme`) hard-codes star entity, em-dash separator, single-space pipes, and substring label matching and is brittle to any README drift; catalog JSON is now the source of truth.
  - Touches: `scripts/sync-profile.ps1` (parameters, `New-CatalogFromReadme`, help text), Pester tests.
  - Acceptance: seed mode requires an explicit `-ForceSeedCatalog`, emits a loud "lossy" warning, and is documented as a one-shot bootstrap; default invocation exits clearly.
  - Completed: v4.9.6 added the `-ForceSeedCatalog` guard, lossy bootstrap warning, seed-only exit behavior, clearer missing-catalog guidance, and Pester subprocess coverage for blocked and forced seed paths.
  - Source: TODO.md (EI10); docs/research-feature-plan-2026-06-04.md (-SeedCatalog Legacy Parser)

### Link validation and report depth

- [x] P2 — Parallelize link validation
  - Why: the full `-Check` passes but spends most wall time in ~115 sequential HEAD+GET probes; one blocked host can dominate runtime.
  - Touches: `scripts/sync-profile.ps1` (`Test-LinkTargets`, `Test-HttpUrl`), report warning schema.
  - Acceptance: probes run in bounded parallel batches with the same pass/fail semantics (404/410 fatal, transient 403/429/5xx/timeout as warnings), a `warningCountByHost` summary, and a lower wall-clock time.
  - Completed: v4.9.7 split target collection from probing, added bounded parallel probe batches, preserved fatal vs warning semantics, added `linkValidationSummary.warningCountByHost`, and verified 239 live targets in 6835 ms with no failures/warnings.
  - Source: docs/research-feature-plan-2026-06-04.md (P2); RESEARCH_FEATURE_PLAN (EI7)

- [x] P1 — Report schema depth (metadata hygiene, release-asset, performance sections)
  - Why: the report records pass/fail arrays but does not yet report topic gaps, description gaps, release-asset mismatches, stale feed age, or warning counts by host.
  - Touches: `scripts/sync-profile.ps1` (`Test-ProfileState`, `New-ProjectsExportJson`), `reports/profile-sync-report.json`.
  - Acceptance: report adds `metadataHygiene`, `releaseAssetDrift`, and `validationPerformance` sections; portfolio consumers ignore unknown fields.
  - Completed: v4.9.8 added `metadataHygiene` missing-topic/description arrays, visitor-facing `releaseAssetDrift` summaries from current release/action metadata, and `validationPerformance.linkValidation` timing/counts.
  - Source: docs/research-feature-plan-2026-06-04.md (Report Schema Depth)

### Metadata hygiene and discoverability

- [x] P1 — Topic coverage and topic/description drift reporting
  - Why: live metadata originally showed 69 active public repos without topics and four empty public descriptions, reducing discovery and overloading the catalog with explanatory burden.
  - Touches: `data/profile-catalog.json`, `scripts/sync-profile.ps1` (`Test-ProfileState`), `reports/profile-sync-report.json`, optional helper apply-script.
  - Acceptance: report lists missing topics/descriptions and recommended `topicHints` derived from category/language/platform/role without mutating any repo; any apply mode is separate and requires an explicit allowlist.
  - Completed: v4.9.9 added category/language/role-derived `topicHints`, catalog description suggestions, and a non-mutating allowlist-required topic hint policy to `metadataHygiene`.
  - Source: ROADMAP.md (P1 topic drift); docs/research-feature-plan-2026-06-04.md (P1 topic/description drift)

- [x] P1 — Add consistent repo descriptions before README sync
  - Why: empty public-repo descriptions (e.g. `SysAdminDoc`, `AdapterLock`, `facebook-exit-guide`) weaken the generated catalog.
  - Touches: GitHub repo descriptions (reviewed apply), `data/profile-catalog.json` (`descriptionOverride`).
  - Acceptance: the four empty public descriptions are filled; GitHub repo descriptions are preferred as the short source where accurate.
  - Completed: v4.9.10 filled the four-row `metadataHygiene.missingDescriptions` allowlist on GitHub and regenerated the report to 0 missing descriptions.
  - Source: ROADMAP.md (P1)

- [x] P1 — Submit focused projects to relevant awesome lists after metadata is clean
  - Why: clean taxonomy, stable descriptions, and link hygiene make selective awesome-list submissions worthwhile (sysadmin utilities, Android apps, browser extensions, local-first tools, profile/portfolio tooling).
  - Touches: external awesome-list PRs; candidate selection from the catalog.
  - Acceptance: a small, curated set of submissions is prepared only after topic/description hygiene lands.
  - Completed: v4.9.11 prepared the candidate plan and submission lines in `RESEARCH_REPORT.md`; external PRs remain a separate cross-repository action.
  - Source: ROADMAP.md (P1)

### Accessibility and README chrome

- [x] P1 — Theme-aware, accessible image chrome (NF3)
  - Why: the hero/stats/streak/activity/skill/capsule images are dark-only (`bg_color=0d1117`) and render as dark slabs in GitHub light mode; alt text is generic and the value proposition is trapped inside the typing SVG.
  - Touches: `scripts/sync-profile.ps1` (new `New-HeroChrome`/`New-StatsSection`), `README.md` top section (via generation), Pester fixtures.
  - Acceptance: generator emits `<picture>` blocks with dark+light sources, meaningful `alt` text, and a plain-text tagline that survives host failure; legible in both GitHub themes; coordinate with the hand-authored hero above the generated block.
  - Completed: v4.9.12 added generated dark/light image chrome, a plain-text tagline, descriptive alt text, and README experience checks for the profile chrome.
  - Source: TODO.md (NF3); docs/research-feature-plan-2026-06-04.md (P1)

### Release/download taxonomy and third-party assets

- [x] P2 — Release asset taxonomy and drift checks
  - Why: the latest report shows 141 visitor-facing rows with a latest release; `downloadKind`/action labels are curated and should be audited against actual release asset names (APK, EXE, ZIP, CRX, XPI, userscript, source-only, no-release).
  - Touches: `scripts/sync-profile.ps1` (REST release-asset fetch, `Get-PrimaryAction`, `Get-DownloadLabel`, `New-ProjectsExportJson`), report schema.
  - Acceptance: report flags asset-label mismatches; `projects.json` exposes `releaseAssetKinds`; installer-less source archives remain "Repo"/source-only.
  - Completed: v4.9.13 added latest-release asset inspection, exported `releaseAssetKinds`/`releaseAssetNames`, compared catalog `downloadKind` labels against actual asset kinds, corrected three catalog rows, and regenerated to 0 release asset kind mismatches.
  - Source: ROADMAP.md (P2 release taxonomy); docs/research-feature-plan-2026-06-04.md (P2)

- [x] P2 — Action-baked stat/snake SVGs (NF4)
  - Why: 5–7 third-party render hosts (stats/streak/activity, komarev counter) can rate-limit/outage together and leak visitor IP/UA; Camo caches them anyway, so there is no dynamism benefit.
  - Touches: new `.github/workflows/assets-refresh.yml`, committed `assets/*.svg`, generator references to local assets.
  - Acceptance: a scheduled Action snapshots stats/streak/activity (or a Platane/snk snake) to committed SVGs; README renders with hosts blocked; the komarev counter is dropped or reduced to one tiny badge.
  - Completed: v4.9.14 added committed local SVG profile panels, sync/report checks for six assets, a scheduled/manual assets-refresh workflow, and removed komarev plus readme-stats/streak/activity hosts from the generated README.
  - Source: TODO.md (NF4)

- [x] P2 — Dependency/status badges only where they carry signal
  - Why: the README already depends on multiple external image services; badge overload dilutes the catalog.
  - Touches: `README.md` generated header (via generation); optional self-hosted readme-stats.
  - Acceptance: a small generated summary replaces redundant third-party widgets; self-hosting is considered only if rate limits or uptime become a recurring problem.
  - Completed: v4.9.15 removed redundant Shields follower/star image badges, moved total public stars into the committed local stats SVG, added badge/chrome-count report guards, and fixed duplicate local stats chrome across repeated generator runs.
  - Source: ROADMAP.md (P2)

### Portfolio site (separate repo `sysadmindoc.github.io`)

- [x] P1 — Add Pagefind (or equivalent) static search to the portfolio
  - Why: 184/177 entries exceed browse-only navigation; the README cannot host search (sanitized markup).
  - Touches: `sysadmindoc.github.io` (Pagefind build config, `data-pagefind-body` scoping) consuming `projects.json`.
  - Acceptance: search covers repo name, description, category, topics, platform, release availability, and currently-building status; suppressed/private/medical entries are excluded from the index.
  - Completed: v4.9.16 verified the existing portfolio implementation: `/search/` uses Pagefind Component UI, `npm run build` generates `dist/pagefind`, project detail pages expose Category filter and Type metadata, no-JS fallback links exist, and the portfolio build indexed 198 public pages / 18,774 words / 1 filter with a clean worktree.
  - Source: ROADMAP.md (P1); TODO.md (NF7); docs/research-feature-plan-2026-06-04.md (P1)

- [x] P1 — Add "new", "recently updated", and "has-download" portfolio views (NF6)
  - Why: new repos are invisible until a manual refresh; there is no freshness signal.
  - Touches: `sysadmindoc.github.io` views; optional `projects.json` fields (`ageBucket`, `freshnessRank`, `releaseAssetKinds`, `searchKeywords`).
  - Acceptance: portfolio derives views from `pushedAt`, `latestRelease`, release asset type, topics, and catalog categories.
  - Completed: v4.9.17 implemented URL-backed All/New/Recently updated/Has download catalog views in `sysadmindoc.github.io` commit `29c2b1d`, with visible NEW/DOWNLOAD chips, combined `view=`, `cat=`, `q=`, and `sort=` state, and verification through portfolio check/build/test plus focused browser/mobile validation.
  - Source: ROADMAP.md (P1); TODO.md (NF6); docs/research-feature-plan-2026-06-04.md (P1)

- [x] P1 — Point the portfolio at the live `projects.json` feed
  - Why: the portfolio should consume the same public catalog state as the README.
  - Touches: `sysadmindoc.github.io` fetch of `raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/projects.json`.
  - Acceptance: the portfolio renders from the feed with raw-fetch caching handled and suppressed entries excluded.
  - Completed: v4.9.18 implemented `profile-feed:sync`, `src/data/portfolio.ts`, profile feed validation, feed-backed catalog/project routes/feeds/language lanes/timeline/OG routes, suppressed-row exclusion, and local curated overlays/fallbacks in `sysadmindoc.github.io` commit `9117f45`.
  - Source: TODO.md

### Setup bootstrapper

- [x] P2 — Harden `setup.ps1`
  - Why: onboarding is strong but lacks an inspect-before-run path; support diagnostics are transient.
  - Touches: `setup.ps1`, `New-FirstTimeSetupSection`, optional tests.
  - Acceptance: adds `#Requires -Version 5.1`, `-CheckOnly` (reports Python/Git/winget state without installing), transcript logging to a temp path, and a README inspect-before-run row; the `irm | iex` default path keeps working.
  - Completed: v4.9.21 added `#Requires -Version 5.1`, `-CheckOnly`, best-effort `%TEMP%` transcripts, generated inspect-before-install README guidance, `readmeExperienceChecks.setupInspectPath`, and Pester/static contract coverage.
  - Source: TODO.md; docs/research-feature-plan-2026-06-04.md (P2)

### Catalog hygiene and attribution

- [x] P3 — Recategorize WolfPack
  - Why: WolfPack (LibreWolf portable distro) sits in a 4-item Security & Networking section; it groups better with Vigil under Desktop/Privacy.
  - Touches: `data/profile-catalog.json` (category edit) then regenerate.
  - Acceptance: WolfPack renders under Desktop/Privacy; Security & Networking is tightened.
  - Completed: v4.9.22 moved WolfPack and Vigil into Native Desktop Applications, regenerated README/feed/report output, and tightened Security & Networking from 4 to 3 repos.
  - Source: TODO.md (P3)

- [x] P3 — Standardize fork/continuation + upstream-license attribution
  - Why: fork/continuation labeling is uneven (AppManagerNG shows license in body but not Featured; `(fork)` entries lack upstream link/license).
  - Touches: `data/profile-catalog.json` (`forkOf`/`upstreamLicense` fields), README renderer, `projects.json`.
  - Acceptance: Featured and category rows render upstream origin and license uniformly for forked/continued projects.
  - Completed: v4.9.23 added structured attribution fields, schema/feed support, README upstream/license rendering, and metadata for AppManagerNG, uBlockVanced, LTSC-MicrosoftStore, RcloneBrowser, TabExplorer, Vigil, and TagStudio.
  - Source: TODO.md (P3); docs/research-feature-plan-2026-06-04.md (P3)

- [x] P3 — Log "Forge" naming debt
  - Why: WinForge, FirewallForge, NetForge, PathForge, GitForge, ImageForge, ClipForge, and IconForge run against the no-"Forge" naming rule.
  - Touches: ROADMAP log only — do not rename live repos (breaks stars/links).
  - Acceptance: the debt is recorded and the pattern is avoided for new repos.
  - Completed: v4.9.24 records the retained names `WinForge`, `FirewallForge`, `NetForge`, `PathForge`, `GitForge`, `ImageForge`, `ClipForge`, `IconForge`, and the additionally found `MediaForge`; no live repos were renamed, and future repo names should avoid the "Forge" pattern unless explicitly excepted.
  - Source: TODO.md (P3)

- [ ] P2 — Add a quarterly archive/retirement / stale-project review
  - Why: many active repos benefit from periodic retirement review to keep the profile sharp.
  - Touches: `scripts/sync-profile.ps1` (`Test-ProfileState`), report schema, optional catalog `stalePolicy`; `data/profile-catalog.json` stale marks.
  - Acceptance: a report groups stale, dormant, source-only, suppressed, and recently revived projects from `pushedAt`/`latestRelease`/suppression reasons; forked or dormant repos stay out of the main featured set.
  - Source: ROADMAP.md (P2); docs/research-feature-plan-2026-06-04.md (P3)

- [ ] P2 — Add contributor/community signals if public contribution grows
  - Why: contributor recognition matters once public collaboration grows, but project discovery comes first.
  - Touches: optional All Contributors or a generated contributor summary.
  - Acceptance: evaluated and deferred below project discovery until collaboration grows.
  - Source: ROADMAP.md (P2)

### Public planning-doc sync

- [x] P1 — Keep public planning docs aligned with generated sync state
  - Why: tracked planning docs can drift from the generated profile version, latest sync date, and active open items.
  - Touches: `ROADMAP.md`, `CHANGELOG.md`, `PROJECT_CONTEXT.md`.
  - Acceptance: version, latest sync date, and remaining open items stay in lockstep with profile-sync releases; public docs stay sanitized.
  - Completed: v4.9.20 added the automated `docVersionConsistency` gate to `scripts/sync-profile.ps1 -Check`, updated the tracked public planning docs, and records version/date alignment in the sync report.
  - Source: docs/research-feature-plan-2026-06-04.md (P1 Public Planning Files)

### Blocked — needs user decision

- [ ] P1 — Git history scrub decision
  - Why: the local research bundle and private repo names are removed from the current tree but remain in public commit history; rewriting public profile history is disruptive.
  - Touches: `git filter-repo` (history) — user's call whether to rewrite or accept.
  - Acceptance: user decides to scrub history or formally accept the residue.
  - Source: TODO.md (blocked)

- [ ] P2 — Topics for ~60 bare repos via `gh api .../topics`
  - Why: applying topics mutates other repositories, so it needs explicit user go-ahead and a reviewed allowlist before any autonomous edit can proceed.
  - Touches: other repositories' topics (reviewed apply only).
  - Acceptance: topics applied only after explicit user approval and allowlist review.
  - Source: TODO.md (blocked); docs/research-feature-plan-2026-06-04.md (open question)

- [ ] P3 — Decide `PROJECT_CONTEXT.md` public status
  - Why: it references internal tooling/paths; decide keep-and-sanitize as public project documentation vs reduce to public-safe status notes vs untrack.
  - Touches: `PROJECT_CONTEXT.md` (and `.gitignore` if untracked).
  - Acceptance: an explicit decision is made and applied; no internal-only paths remain in a tracked public doc.
  - Source: TODO.md (blocked); docs/research-feature-plan-2026-06-04.md (open question)

## Verification Standard

Before a generated README refresh is shipped:

- `git status --short --branch`
- `git log -10 --oneline --decorate`
- `scripts/sync-profile.ps1 -Check`
- link audit for GitHub repo URLs, release/latest URLs, raw userscript URLs, and GitHub Pages launch URLs
- clone snippet audit for default branch and entrypoint existence
- privacy gate report with zero public README links to private repos
- markdown render smoke check on GitHub after push

---

## Research-Driven Additions

### Researcher Queue (Cycle 1 - 2026-06-04)

- [x] 🔬 `profile-sync-verification-refresh-2026-06-04` - rechecked current
  GitHub profile README, GitHub Actions workflow-permission, and Pagefind static
  search docs against the live repo state. Pester passed, structural profile
  check found `projectsExportInSync=false`, and the full live-link check timed
  out on the sequential validation path. Existing drift-lockout and parallel
  link-validation rows cover the findings; no new non-duplicate row was
  promoted.

*Research conducted 2026-06-03. Items below are new — not duplicates of Existing Planned Work.*

These come from reading `scripts/sync-profile.ps1` (1,495 lines), the four workflows, the Pester suite, `setup.ps1`, the generated `README.md`/`projects.json`, and live verification. Existing Planned Work already covers: drift lockout (P0), metadata-drift report depth, `-SeedCatalog` guard, parallel link validation, report schema depth, topic/description hygiene, theme-aware image chrome, release-asset taxonomy, action-baked SVGs, portfolio search/freshness/feed consumption, `setup.ps1` `-CheckOnly`/transcript, stale-project review, planning-doc sync, and the blocked decisions. The items below are deliberately outside all of those.

### Data integrity and trust gates

- [x] P1 — Publish (or stop referencing) the JSON Schema URLs the feed advertises
  - Why: `data/profile-catalog.json` and `projects.json` both declare `schema` pointers (`https://sysadmindoc.github.io/schemas/profile-catalog.v1.json` and `.../profile-projects.v1.json`), but those URLs return HTTP 404. Any downstream consumer that follows the advertised contract gets a dead link, and the feed has no enforceable shape.
  - Evidence: `scripts/sync-profile.ps1:1086` (`schema = "https://sysadmindoc.github.io/schemas/profile-projects.v1.json"`), `:1264` (catalog schema), `data/profile-catalog.json:1`. Verified 2026-06-03: `https://sysadmindoc.github.io/schemas/profile-projects.v1.json` → 404.
  - Touches: `sysadmindoc.github.io` (publish the two schema docs) OR `scripts/sync-profile.ps1` (point `schema` at a versioned path that exists, e.g. the raw GitHub blob of a committed `schemas/*.json`); optional `schemas/` dir in this repo.
  - Acceptance: both advertised `schema` URLs resolve to a real JSON Schema that validates a current `projects.json`/catalog, or the field is repointed to a live URL; a Pester/CI step validates the generated feed against the committed schema.
  - Completed: v4.9.19 added `schemas/profile-catalog.v1.json` and `schemas/profile-projects.v1.json`, repointed catalog/feed schema URLs to raw GitHub, added `schemaValidation` to `Test-ProfileState`, added Pester contract tests, regenerated `projects.json` with array-stable asset/topic fields, and verified full `-Write -Check`.
  - Verify: `curl -sI <schema-url>` → 200; `Invoke-Pester` includes a schema-validation case that fails on a missing required field.
  - Complexity: M

- [x] P1 — Add a self-contained version/date consistency gate across tracked planning docs
  - Why: `ROADMAP.md`, `CHANGELOG.md`, and `PROJECT_CONTEXT.md` each hand-type the current version (`v4.9.19`) and "latest sync" date; the existing "keep planning docs aligned" item is a manual discipline with no check. A single mismatched string ships silently. This is the *automated guard*, not the manual sync already planned.
  - Evidence: `ROADMAP.md:8` (`Current repo version: v4.9.19`), `CHANGELOG.md:5` (`## [v4.9.19]`), `RESEARCH_REPORT.md:7`; `Test-ProfileState` checks README/feed drift but never reads the planning docs.
  - Touches: `scripts/sync-profile.ps1` (new `Test-DocVersionConsistency`), `reports/profile-sync-report.json`, Pester.
  - Acceptance: `-Check` fails when the version token in CHANGELOG, ROADMAP, and PROJECT_CONTEXT disagree, or when the latest CHANGELOG date is newer than the recorded sync date; report adds a `docVersionConsistency` block.
  - Completed: v4.9.20 added `Test-DocVersionConsistency`, `docVersionConsistency` report output, failure wiring in `Test-ProfileState`, and Pester mismatch/stale-date coverage.
  - Verify: deliberately bump one doc's version, run `-Check`, observe non-zero exit and the new report field.
  - Complexity: M

- [ ] P2 — Extend link validation to hero/header and non-catalog URLs
  - Why: `Test-LinkTargets` only probes catalog-derived entrypoint/userscript/live/release URLs. The hand-authored hero — the portfolio link `https://sysadmindoc.github.io/`, the `setup.ps1` blob link, and the remaining third-party image hosts (capsule-render, readme-typing-svg, skill-icons, shields.io) — is never checked. A dead portfolio link or a retired image host would pass the gate.
  - Evidence: `scripts/sync-profile.ps1:476-528` (`Test-LinkTargets` iterates only `$Included` catalog entries); `README.md:1-68` (hero/header links and image hosts, none catalog-derived).
  - Touches: `scripts/sync-profile.ps1` (`Test-LinkTargets` plus a static header-URL extractor), report schema.
  - Acceptance: the portfolio link and `setup.ps1` blob link are probed as fatal-on-404; image hosts are probed as non-fatal warnings grouped under `headerHostWarnings`; results land in the report.
  - Verify: temporarily point the portfolio link at a 404 in a scratch copy and confirm a fatal failure; confirm image-host outages stay non-fatal.
  - Complexity: M

### Reliability and performance

- [ ] P2 — Cap and authenticate the REST release-fallback N+1
  - Why: when the GraphQL path fails three times, `Get-GitHubReposFromRest` issues one `gh api .../releases/latest` per public repo — ~184 sequential calls. Unauthenticated that blows the 60 req/hr limit; even authenticated it is slow and can partially fail mid-run, silently yielding a feed with missing release tags.
  - Evidence: `scripts/sync-profile.ps1:148-162` (per-repo `gh api releases/latest` loop inside the fallback).
  - Touches: `scripts/sync-profile.ps1` (`Get-GitHubReposFromRest`): batch via a single GraphQL-less paginated call where possible, add `--paginate`, surface a rate-limit/partial-fetch warning, and fail loudly rather than emitting a half-populated catalog.
  - Acceptance: fallback completes within a bounded request budget, logs a warning when any per-repo release fetch fails, and never writes a feed where release data is partially missing without flagging it.
  - Verify: force the GraphQL path to fail (simulate), run `-Write`, confirm the run either completes cleanly or aborts with a clear partial-data warning.
  - Complexity: M

- [ ] P2 — Add a generated-README size budget guard
  - Why: the generated `README.md` is ~72 KB. GitHub renders profile READMEs but truncates very long files and degrades on mobile; there is no budget check, so unbounded catalog growth can silently push the profile past a comfortable render size.
  - Evidence: `README.md` is 73,358 bytes on disk; `New-Readme` (`scripts/sync-profile.ps1:959`) emits every included entry with a full code block and no size accounting.
  - Touches: `scripts/sync-profile.ps1` (`Test-ProfileState`), report schema.
  - Acceptance: report records generated byte size and warns past a configurable soft cap (e.g. 96 KB); the warning is informational, not fatal, and suggests collapsing low-traffic categories.
  - Verify: lower the cap below current size, run `-Check`, confirm the warning appears in the report without failing the gate.
  - Complexity: S

### Test coverage gaps

- [ ] P1 — Cover the safety-critical functions the Pester suite skips
  - Why: the hermetic suite tests snippet/URL/description helpers and basic generation, but never exercises `Test-ProfileState` (the privacy/medical/private-visibility/drift gate), `Update-Header` (the Currently-Building regex replace), or `New-ProjectsExportJson` suppression edge cases beyond one fixture. The most safety-critical logic — the gate that keeps private/medical repos out of the public profile — has no direct unit test.
  - Evidence: `tests/sync-profile.Tests.ps1` (no `Describe` for `Test-ProfileState`, `Update-Header`, or the medical-violation branch at `scripts/sync-profile.ps1:1395`); `MedicalPattern` is tested only as a regex string, not through the gate that consumes it.
  - Touches: `tests/sync-profile.Tests.ps1`, new offline fixtures (a fake `$Repos` with a private/medical entry).
  - Acceptance: tests assert `Test-ProfileState` flags a private-visibility repo, flags a medical-keyword repo lacking `allowPublicMedical`, passes one with the allowlist, and that `Update-Header` rewrites the Currently-Building table idempotently.
  - Verify: `Invoke-Pester -Path tests` shows the new cases green; mutate the medical branch to confirm a test fails.
  - Complexity: M

- [ ] P2 — Add catalog JSON-shape validation to CI/Pester
  - Why: a malformed `data/profile-catalog.json` (bad category slug, missing `repo`, duplicate entry, unknown `downloadKind`) only surfaces at generation runtime, and some bad values (e.g. an unrecognized `downloadKind`) silently fall through to a default label. There is no structural validation step.
  - Evidence: `Get-Catalog` (`scripts/sync-profile.ps1:313`) `ConvertFrom-Json` with no schema/shape assertions; `Get-DownloadLabel` (`:546`) `default { return "Download" }` swallows unknown kinds.
  - Touches: `tests/sync-profile.Tests.ps1` (or a new `Test-CatalogShape` function), optional committed schema from the P1 schema item.
  - Acceptance: a test fails on a duplicate `repo`, an unknown `category` slug, or an unknown `downloadKind`; known-good catalog passes.
  - Verify: inject a duplicate repo into a fixture, run Pester, confirm the new test fails.
  - Complexity: M

### Repository community health

- [ ] P2 — Add SECURITY.md and a coordinated-disclosure path
  - Why: the repo ships zizmor, OpenSSF Scorecard, CODEOWNERS, and pinned actions, but has no `SECURITY.md`. Scorecard explicitly scores the presence of a security policy, and a profile repo that runs supply-chain tooling should publish how to report an issue.
  - Evidence: root listing shows no `SECURITY.md`/`.github/SECURITY.md`; `scorecard.yml` runs the Scorecard action that checks for one.
  - Touches: `SECURITY.md` (or `.github/SECURITY.md`), public-safe contact only.
  - Acceptance: a concise security policy exists with a non-PII reporting channel; Scorecard's Security-Policy check stops flagging it.
  - Verify: GitHub shows the "Security policy" community-health entry as satisfied after push.
  - Complexity: S

- [ ] P3 — Add `.editorconfig` and a generated-README markdown lint pass
  - Why: the generated README is large hand-and-machine-mixed Markdown with no lint or whitespace contract; inconsistent line endings or stray trailing whitespace in the hand-authored hero can drift the generated diff. No `.editorconfig` or markdownlint config exists.
  - Evidence: root listing shows no `.editorconfig`/`.markdownlint*`; `New-Readme` normalizes only trailing `---` runs (`scripts/sync-profile.ps1:984`), not general whitespace.
  - Touches: `.editorconfig`, optional `.markdownlint.jsonc`, optional `tests.yml` lint leg.
  - Acceptance: an `.editorconfig` pins LF + final-newline + trim-trailing-whitespace; an optional markdownlint leg runs on PRs touching `README.md` with a curated ruleset (the generated tables are allowlisted).
  - Verify: introduce trailing whitespace in the hero, confirm the lint leg flags it.
  - Complexity: S

### Privacy of the public surface

- [ ] P3 — Document/justify the third-party render-host privacy exposure inline
  - Why: distinct from the planned action-baked-SVG work, the komarev profile-view counter and the stats/streak/activity hosts each see every profile visitor's request through Camo's proxy origin; there is no public note that these are third-party and no documented decision record for keeping them. A short DECISION note makes the trade-off auditable and avoids re-litigating it each research pass.
  - Evidence: `README.md:8` (komarev counter), `:59-68` (four render hosts); no decision record in tracked docs.
  - Touches: a short note in `RESEARCH_REPORT.md` or a `docs/decisions/` entry; no code change.
  - Acceptance: a one-paragraph recorded decision states which hosts are retained, why, and what would trigger removal (tie-in to the action-baked-SVG item).
  - Verify: the note exists and is referenced from the action-baked-SVG roadmap item.
  - Complexity: S

### Researcher Queue (Cycle 2 - 2026-06-04)

*Research conducted 2026-06-04. Items below were new relative to the open queue at research time. Existing open items already cover JSON Schema publishing, doc-version consistency, header link validation, REST fallback caps, catalog-shape validation, SECURITY.md, and setup `-CheckOnly`/transcript hardening.*

- [ ] P1 — Add a PowerShell static-analysis lane for the generator and setup scripts
  - Why: Pester exercises selected behavior, but no CI step checks common PowerShell quality/security rules for `scripts/sync-profile.ps1` or `setup.ps1`. Microsoft documents `Invoke-ScriptAnalyzer` as a static checker for `.ps1`, `.psm1`, and `.psd1` files and supports `-EnableExit` for CI failure.
  - Evidence: `.github/workflows/tests.yml` installs/runs only Pester; root search found no `PSScriptAnalyzerSettings.psd1` or `Invoke-ScriptAnalyzer`; Microsoft Learn `Invoke-ScriptAnalyzer` docs: https://learn.microsoft.com/en-us/powershell/module/psscriptanalyzer/invoke-scriptanalyzer?view=ps-modules
  - Touches: `PSScriptAnalyzerSettings.psd1` (or equivalent), `.github/workflows/tests.yml`, existing PowerShell scripts only as needed to satisfy the rules.
  - Acceptance: CI runs `Invoke-ScriptAnalyzer` against `scripts/` and `setup.ps1` with a curated settings file; any suppressions carry justifications; Pester remains the behavioral test lane.
  - Verify: `pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser -Force; Invoke-ScriptAnalyzer -Path scripts,setup.ps1 -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -EnableExit"`
  - Complexity: M

- [ ] P1 — Add generated-feed provenance fields for downstream consumers
  - Why: `projects.json` exposes `schema`, `generatedAt`, and a generic `source`, but does not identify the source tree, catalog hash, generator hash/version, or metadata snapshot that produced the feed. The portfolio cannot distinguish a stale cache from a freshly generated feed with unchanged timestamps, and debugging feed drift requires rerunning local context.
  - Evidence: `projects.json:2-5`; `New-ProjectsExportJson` currently emits top-level `schema`, `generatedAt`, `source`, and counts; GitHub artifact-attestation docs frame provenance as "where and how" artifacts were built: https://docs.github.com/en/actions/how-tos/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
  - Touches: `scripts/sync-profile.ps1` (`New-ProjectsExportJson`, report writer), `projects.json`, `reports/profile-sync-report.json`, optional portfolio consumer handling.
  - Acceptance: feed metadata includes a stable schema version plus public-safe provenance such as `sourceRef`, `catalogSha256`, `generatorSha256`, and `metadataSnapshotAt`; `-Check` reports or fails on mismatched provenance when generated files are stale.
  - Verify: run `scripts/sync-profile.ps1 -Write -Check`; compare the reported catalog/generator hashes to the current files; alter one provenance field and confirm `-Check` catches the mismatch.
  - Complexity: M

- [ ] P2 — Add structured issue/support intake for catalog and install-link reports
  - Why: Issues are enabled on the public repo, but the community profile reports no issue template, no PR template, and no contributing guidelines. A profile with 177 visitor-facing entries needs a guided intake for broken install snippets, stale release links, catalog corrections, and README/profile copy corrections; security reports should be routed to the planned `SECURITY.md` instead of public issues.
  - Evidence: `gh api repos/SysAdminDoc/SysAdminDoc/community/profile` returned `health_percentage=28` with `issue_template=null`, `contributing=null`, and no security-policy file; `gh api repos/SysAdminDoc/SysAdminDoc` shows `has_issues=true`; GitHub issue-template docs: https://docs.github.com/articles/creating-an-issue-template-for-your-repository
  - Touches: `.github/ISSUE_TEMPLATE/catalog-link.yml`, `.github/ISSUE_TEMPLATE/profile-correction.yml`, `.github/ISSUE_TEMPLATE/config.yml`, `.github/PULL_REQUEST_TEMPLATE.md`, optional `CONTRIBUTING.md` or `docs/CONTRIBUTING.md`.
  - Acceptance: the issue chooser has public-safe forms for broken catalog links and profile corrections, required fields capture repo/link/current behavior/expected behavior, security reports point to `SECURITY.md`, and the PR template warns against hand-editing generated README sections.
  - Verify: GitHub's community profile shows an issue-template check; opening `/issues/new/choose` shows the forms; a PR touching `README.md` presents the template.
  - Complexity: S

- [ ] P2 — Add a read-only repository settings and community-health baseline to the sync report
  - Why: `scripts/sync-profile.ps1 -Check` validates generated files, but file checks miss drift in GitHub-hosted settings and community-health state. Live metadata currently shows secret scanning and push protection enabled, but non-provider/generic detection disabled, Dependabot security updates disabled, Projects/Wiki enabled, and missing issue/contributing templates. These should be visible as public-safe report fields before they become silent trust regressions.
  - Evidence: `gh api repos/SysAdminDoc/SysAdminDoc --jq '{has_issues,has_projects,has_wiki,security_and_analysis}'`; `gh api repos/SysAdminDoc/SysAdminDoc/community/profile`; GitHub secret-scanning docs: https://docs.github.com/en/code-security/secret-scanning/enabling-secret-scanning-features
  - Touches: `scripts/sync-profile.ps1` (new read-only repository/community metadata probe), `reports/profile-sync-report.json`, optional Pester fixture for report shape.
  - Acceptance: the sync report includes `repositorySettings` and `communityHealth` blocks with non-sensitive statuses; disabled push protection or missing planned community files are warnings; no settings are mutated by the check.
  - Verify: `scripts/sync-profile.ps1 -Check` records the blocks; mock a missing/disabled field in a fixture and confirm the warning count changes.
  - Complexity: M

- [ ] P2 — Triage current Dependabot workflow-action update PRs with a repeatable SHA-pin review path
  - Why: Dependabot has two open PRs updating SHA-pinned workflow actions, and both current check sets pass. The repo already values pinned actions, least-privilege permissions, and `zizmor`; the missing piece is a small repeatable merge/defer protocol so pinned actions do not go stale while still preserving review of major action/runtime changes.
  - Evidence: `gh pr list -R SysAdminDoc/SysAdminDoc` shows PR #5 (`actions/checkout` 4.3.1 -> 6.0.3) and PR #6 (`github/codeql-action` 3.35.5 -> 4.36.1); `gh pr checks 5` shows Pester and zizmor passing; `gh pr checks 6` shows zizmor passing; GitHub Dependabot action-update docs: https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot
  - Touches: `.github/workflows/*.yml`; optional `CONTRIBUTING.md` or `RESEARCH_REPORT.md` maintenance note.
  - Acceptance: PR #5 and PR #6 are merged or explicitly deferred with a reason; the review checklist records `gh pr checks`, `zizmor`, Pester/profile-sync relevance, `persist-credentials:false`, and permission diffs before merging future action-update PRs.
  - Verify: `gh pr list -R SysAdminDoc/SysAdminDoc --state open --label github_actions` is empty or each remaining PR has a documented defer reason.
  - Complexity: S

### Researcher Queue (Cycle 3 - 2026-06-04)

*Research conducted 2026-06-04. This pass looked for workflow/operator-experience gaps after the v4.9.8 report schema expansion rather than adding more catalog features.*

- [ ] P2 — Surface profile-sync results in GitHub Actions job summaries
  - Why: `.github/workflows/profile-sync.yml` uploads `reports/profile-sync-report.json` as an artifact, but maintainers must download/open the JSON to see high-signal results. The report now includes metadata hygiene, release drift, validation performance, and link-warning summaries, and recent scheduled profile-sync runs show failures before the latest fixes. GitHub Actions supports Markdown job summaries through `$GITHUB_STEP_SUMMARY` and warning/error annotations through workflow commands.
  - Evidence: `.github/workflows/profile-sync.yml` only has the `Upload sync report` artifact step after `scripts/sync-profile.ps1 -Check`; `gh api repos/SysAdminDoc/SysAdminDoc/actions/runs` showed recent scheduled Profile sync runs concluding failure before the current v4.9.x fixes; GitHub workflow-command docs: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
  - Touches: `.github/workflows/profile-sync.yml`, optional `scripts/sync-profile.ps1` helper to render a concise summary from `reports/profile-sync-report.json`.
  - Acceptance: check and write-pr modes append a Markdown summary with readme/feed sync status, fatal metadata drift count, missing-topic/description counts, release-drift summary, link target count, warning count by host, and validation duration; fatal or warning conditions also emit GitHub annotations; the JSON artifact remains uploaded with an explicit retention period.
  - Verify: run the workflow manually or set `GITHUB_STEP_SUMMARY` to a temp file in a local dry run and confirm the summary contains the current report values without exposing private/suppressed repo names.
  - Complexity: S

### Researcher Queue (Cycle 4 - 2026-06-04)

*Research conducted 2026-06-04. This pass audited repository governance settings after the workflow/report hardening work.*

- [ ] P2 🔧 — Require validation status checks on `main`
  - Why: `main` has force-push/deletion protection and required conversation resolution, but live branch protection does not require any status checks and there are no repository rulesets. A broken generated-profile check, Pester regression, or workflow-security failure can still be merged by policy unless maintainers manually notice it.
  - Evidence: `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection` returned `required_status_checks=null`, `required_pull_request_reviews=null`, `required_conversation_resolution.enabled=true`, `allow_force_pushes.enabled=false`, and `allow_deletions.enabled=false`; `gh api repos/SysAdminDoc/SysAdminDoc/rulesets` returned no rulesets. GitHub protected-branch docs describe required status checks before merging: https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches/
  - Touches: GitHub repository branch-protection or ruleset settings; optional `.github/workflows/*.yml` job-name stabilization if required-check names need to be fixed.
  - Acceptance: the default branch requires the relevant validation checks before merge, at minimum Pester, workflow security, and generated profile sync for changes that affect the profile pipeline; any admin bypass or Dependabot bypass is documented.
  - Verify: `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection --jq '.required_status_checks'` or the rulesets API shows required checks; a PR with a failing required check is blocked from merging.
  - Complexity: S

### Researcher Queue (Cycle 5 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked whether generated-profile validation actually runs on pull requests before it can be made a required status check.*

- [ ] P2 — Run profile-sync validation on profile/catalog pull requests
  - Why: `profile-sync.yml` is scheduled/manual only, and `tests.yml` only runs on script/test/workflow changes. A pull request that changes `data/profile-catalog.json`, generated `README.md`, `projects.json`, or the committed sync report can miss `scripts/sync-profile.ps1 -Check` unless a maintainer runs the workflow manually. This also blocks the Cycle 4 branch-protection item from safely requiring generated-profile validation on relevant PRs.
  - Evidence: `.github/workflows/profile-sync.yml` declares only `workflow_dispatch` and `schedule`; `.github/workflows/tests.yml` path filters omit `data/profile-catalog.json`, `README.md`, `projects.json`, and `reports/profile-sync-report.json`; `gh run list -R SysAdminDoc/SysAdminDoc --limit 10` showed recent push-triggered `Tests` runs but no push/PR-triggered `Profile sync` runs. GitHub workflow syntax docs state that `push` and `pull_request` events can use path filters, and warn that skipped required checks remain pending: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  - Touches: `.github/workflows/profile-sync.yml`, optional `scripts/sync-profile.ps1` helper output if the PR check needs a shorter summary.
  - Acceptance: a read-only `pull_request` check runs `scripts/sync-profile.ps1 -Check` for profile-pipeline paths such as `data/profile-catalog.json`, `scripts/sync-profile.ps1`, `README.md`, `projects.json`, `reports/profile-sync-report.json`, and `.github/workflows/profile-sync.yml`; unrelated PRs are not blocked by a skipped required check.
  - Verify: open or simulate a PR touching `data/profile-catalog.json` and confirm `Profile sync / Check generated README` runs and fails on stale generated output; open or inspect an unrelated-doc PR and confirm branch policy does not wait on a skipped profile-sync status.
  - Complexity: S

### Researcher Queue (Cycle 6 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked workflow runtime budgets after profile sync and asset refresh work expanded the number of live-network automation paths.*

- [ ] P2 — Add explicit GitHub Actions timeout budgets
  - Why: the workflows currently rely on GitHub's default job timeout, which is much larger than any expected profile validation, Pester, workflow-security, Scorecard, or asset-refresh run. A hung package install, GitHub API fallback, third-party image fetch, link validation, or PR-create step can consume runner time and obscure whether the failure is validation drift or infrastructure stall.
  - Evidence: `rg -n "timeout-minutes" .github/workflows` returned no tracked workflow timeouts; the in-flight `assets-refresh.yml` also has no job or step timeout; GitHub workflow syntax docs state `jobs.<job_id>.timeout-minutes` defaults to 360 and `steps[*].timeout-minutes` can cap individual steps: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  - Touches: `.github/workflows/profile-sync.yml`, `tests.yml`, `workflow-security.yml`, `scorecard.yml`, and any committed asset-refresh workflow; optional `scripts/sync-profile.ps1` messaging if a timeout-prone phase should emit clearer progress.
  - Acceptance: every workflow job has an explicit timeout sized to observed runtime plus margin, long live-network steps have step-level caps where useful, and timeout values are documented enough that future workflow additions copy the pattern.
  - Verify: `rg -n "timeout-minutes" .github/workflows` shows coverage for each job; normal manual runs still complete; lowering a timeout on a test branch proves GitHub cancels the intended job/step instead of waiting for the default 360 minutes.
  - Complexity: S

### Researcher Queue (Cycle 7 - 2026-06-04)

*Research conducted 2026-06-04. This pass widened from the existing profile-sync
queue into generated-Markdown safety, workflow linting, setup bootstrapper
runtime verification, and release/download trust signals. Existing open items
already cover PSScriptAnalyzer, JSON-shape validation, feed provenance fields,
header link validation, workflow timeouts, branch protection, SECURITY.md, and
structured issue forms, so the items below avoid those duplicates.*

- [ ] P1 🤖 🔬 — Add generated Markdown/text safety and URL-scheme validation
  - Why: the generator inserts catalog titles, descriptions, upstream attribution, and live GitHub metadata directly into GFM table/link contexts. Shape schemas now exist, but they do not prevent Markdown-control characters, raw-HTML-looking text, bidi controls, or unexpected URL schemes from breaking the public profile or making generated links visually deceptive.
  - Evidence: `scripts/sync-profile.ps1:467`, `:1221`, `:1243`, `:1313`, and `:1683` insert display descriptions and titles into README/feed output; the GFM spec defines table, link, raw HTML, and backslash-escape behavior and says GitHub performs post-processing/sanitization after Markdown-to-HTML conversion: https://github.github.com/gfm/; Unicode UTS #39 documents restricted/default-ignorable characters and confusable data for security-sensitive text: https://www.unicode.org/reports/tr39/
  - Touches: `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, optional schema/report additions.
  - Acceptance: generated README table cells and links are escaped or rejected by context; catalog/feed validation rejects bidi controls, embedded null/control characters, raw-HTML-looking generated text where not explicitly allowed, and non-http(s)/GitHub/raw link schemes; `reports/profile-sync-report.json` records a `contentSafety` block with zero current violations.
  - Verify: add a fixture description containing `|`, `](`, `<script>`, and a bidi control; `Invoke-Pester -Path tests` must fail before escaping/rejection and pass after the safety gate is applied. Run `scripts/sync-profile.ps1 -Check` and confirm `contentSafety.passed=true`.
  - Complexity: M

- [ ] P2 🤖 🔬 — Add `actionlint` beside `zizmor` for workflow syntax/expression linting
  - Why: `workflow-security.yml` runs `zizmor`, which is useful for security posture, but no workflow validates GitHub Actions syntax, expression types, action inputs/outputs, `needs:` dependencies, cron syntax, or inline shell snippets. This is a complementary workflow-quality gate, not a replacement for `zizmor`.
  - Evidence: `.github/workflows/workflow-security.yml:21-36` installs and runs only `zizmor`; `actionlint` documents workflow syntax, expression, action-usage, ShellCheck/Pyflakes, and script-injection checks: https://github.com/rhysd/actionlint; GitHub's script-injection docs warn that attacker-controlled GitHub context values can be substituted into `run:` shell scripts before execution: https://docs.github.com/en/actions/concepts/security/script-injections
  - Touches: `.github/workflows/workflow-security.yml`, optional `.github/actionlint.yml` if the default rules need project-specific exclusions.
  - Acceptance: the workflow-security job runs both `zizmor` and `actionlint`; actionlint is pinned or installed through a repeatable versioned path; failures are blocking on workflow/security-file PRs; any project-specific ignores are documented.
  - Verify: `actionlint .github/workflows/*.yml` passes locally or in CI; introduce an invalid expression or bad `needs:` reference in a scratch branch and confirm the workflow fails before merge.
  - Complexity: S

- [ ] P2 🤖 🔬 — Add a Windows runner smoke check for `setup.ps1 -CheckOnly`
  - Why: the README now gives novices an inspect-before-install command that runs `setup.ps1 -CheckOnly`, but current Pester coverage only inspects source text and generated README snippets. Because the script is Windows/WinGet/PATH-specific, an Ubuntu-only source contract can miss runtime regressions in the exact path users are told to run.
  - Evidence: `README.md:118-130` advertises both the one-paste setup and `-CheckOnly`; `tests/sync-profile.Tests.ps1:345-357` reads `setup.ps1` text but does not execute it; GitHub-hosted runner docs list standard `windows-latest` public-repo runners: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
  - Touches: `.github/workflows/tests.yml` or a new path-filtered setup-smoke workflow; optional Pester helper that shells out to `setup.ps1 -CheckOnly` on Windows only.
  - Acceptance: a Windows job runs `powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -CheckOnly` for PRs touching `setup.ps1`, README setup text, or tests; the check asserts check-only mode does not install or mutate tools, and uploads/redacts the temp transcript only on failure.
  - Verify: open a scratch PR touching `setup.ps1`; confirm the Windows smoke job runs and passes. Temporarily make `-CheckOnly` call the install path and confirm the job fails.
  - Complexity: S

- [ ] P2 🤖 🔬 — Add release/download trust metadata for visitor-facing binary rows
  - Why: the profile now routes visitors to many executable release assets, but the generated report only classifies asset kinds. It does not tell visitors or the build machine whether release rows have checksums, signatures, attestations, SBOMs, or a documented "unsigned/unattested" status.
  - Evidence: `reports/profile-sync-report.json:846-864` shows 71 release-action rows, including APK and EXE kinds; OpenSSF Scorecard includes a `Signed-Releases` check and related security posture checks: https://github.com/ossf/scorecard; GitHub artifact attestations establish where and how artifacts were built and can be verified with `gh attestation verify`: https://docs.github.com/en/actions/how-tos/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
  - Touches: `scripts/sync-profile.ps1` report generation, optional README trust microcopy, optional per-repo release checklist outside this profile repo.
  - Acceptance: `reports/profile-sync-report.json` includes a `releaseTrust` section summarizing, per release-action row, whether latest assets expose checksum/signature/attestation/SBOM evidence or are explicitly `unverified`; the README can keep UI minimal, but the report gives the build machine a prioritized list for high-traffic EXE/APK rows.
  - Verify: run `scripts/sync-profile.ps1 -Check`; confirm the report counts EXE/APK rows by trust status and flags missing evidence as warnings, not fatal failures. For one repo with an attestation/checksum, verify the report recognizes it.
  - Complexity: M

### Researcher Queue (Cycle 8 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on dependency/toolchain drift
inside CI. Existing open items already cover GitHub Actions SHA-pin review,
`actionlint`, PSScriptAnalyzer, workflow timeouts, and Dependabot PR triage; the
new gap is that registry-installed validation tools are not pinned or locked.*

- [ ] P2 🤖 🔬 — Pin and audit CI-installed validation tools
  - Why: the workflows pin third-party GitHub Actions by SHA, but they still install validation tools directly from live registries: `zizmor` via `python -m pip install --upgrade zizmor` and Pester via `Install-Module Pester -MinimumVersion 5.5.0 -Force`. A new PyPI or PSGallery release can change CI behavior, break validation, or introduce a supply-chain dependency without a reviewed PR.
  - Evidence: `.github/workflows/workflow-security.yml:32-36` installs latest `zizmor`; `.github/workflows/tests.yml:39-45` trusts PSGallery and installs any Pester version at or above 5.5.0; no `requirements*.txt`, lock file, or tool-version manifest exists in the repo; pip's repeatable-installs docs recommend exact `==` pins and hash-checking for stricter automated installs: https://pip.pypa.io/en/stable/topics/repeatable-installs/ and https://pip.pypa.io/en/stable/topics/secure-installs/; Microsoft documents `Install-Module -RequiredVersion` for exact module selection: https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module; OpenSSF Scorecard's Pinned-Dependencies check calls unpinned build/release dependencies a medium risk: https://github.com/ossf/scorecard/blob/main/docs/checks.md#pinned-dependencies
  - Touches: `.github/workflows/tests.yml`, `.github/workflows/workflow-security.yml`, optional `requirements-ci.txt` with hashes, optional `docs/ci-toolchain.md` or a small tool-version manifest.
  - Acceptance: CI validation tools are installed from exact reviewed versions; Python-installed tools use a pinned requirements file, preferably with hashes or a documented reason hashes are deferred; PowerShell modules use `-RequiredVersion`; the maintenance note explains how to update pins intentionally and how those updates relate to Dependabot/Renovate/manual review.
  - Verify: `rg -n "pip install --upgrade|MinimumVersion" .github/workflows` returns no unreviewed floating validation-tool installs; a manual CI run uses the pinned versions; bumping a pin in a scratch branch produces a reviewable diff and still passes Pester/workflow-security.
  - Complexity: S

### Quick Wins

P2/P3, each doable in well under an hour:

- [ ] P2 — Generated-README size budget guard (informational warning in the report).
- [ ] P2 — SECURITY.md with a public-safe disclosure path (satisfies Scorecard's Security-Policy check).
- [ ] P2 — Profile-sync Actions job summary from `reports/profile-sync-report.json`.
- [ ] P2 — `actionlint` in `workflow-security.yml` alongside `zizmor`.
- [ ] P2 — Windows `setup.ps1 -CheckOnly` smoke job for setup/README changes.
- [ ] P2 — Exact pins for CI-installed `zizmor` and Pester validation tools.
- [ ] P2 🔧 — Require branch protection/ruleset status checks on `main`.
- [ ] P2 — Pull-request profile-sync validation for catalog/profile changes.
- [ ] P2 — Explicit GitHub Actions timeout budgets for validation and refresh jobs.
- [ ] P2 — Structured issue forms for broken catalog links and profile corrections.
- [ ] P2 — Current Dependabot workflow-action PR triage (#5 and #6).
- [ ] P3 — `.editorconfig` pinning LF + final-newline + trim-trailing-whitespace.
- [ ] P3 — Recorded decision note on the retained third-party render hosts.

### Larger Bets

P1/P2 needing design or staged rollout:

- [x] P1 — Publish the advertised JSON Schemas and validate the feed against them (completed v4.9.19 with committed raw-GitHub schemas and `schemaValidation`).
- [x] P1 — Doc version/date consistency gate wired into `-Check` and CI (completed v4.9.20 with `docVersionConsistency` in the existing profile-sync check/report path).
- [ ] P1 — PSScriptAnalyzer static-analysis lane for `scripts/` and `setup.ps1`.
- [ ] P1 — Generated-feed provenance fields (`sourceRef`, catalog/generator hashes, metadata snapshot).
- [ ] P1 — Generated Markdown/text safety and URL-scheme validation for README/feed output.
- [ ] P1 — Pester coverage for `Test-ProfileState`/`Update-Header`/medical-gate (protects the privacy guard before any refactor).
- [ ] P2 — Repository settings/community-health baseline in the sync report.
- [ ] P2 — REST release-fallback N+1 cap with rate-limit awareness and partial-data abort.
- [ ] P2 — Header/non-catalog link validation folded into the existing link gate.
- [ ] P2 — Release/download trust metadata for visitor-facing EXE/APK/ZIP release rows.
- [ ] P2 — Pinned CI validation-tool installs with a documented update path.
