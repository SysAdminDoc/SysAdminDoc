# SysAdminDoc Profile Roadmap

> Single source of truth for all planned work. Items above the --- are existing plans; items below are research conducted 2026-06-03.

Last research refresh: 2026-06-04
Evidence bundle: `RESEARCH_REPORT.md` (archived source: `docs/archive/research-feature-plan-2026-06-04.md`)
Latest profile sync: 2026-06-04
Current repo version: v4.9.3
Research baseline HEAD: `3d4ed8f Release v4.7.0 -- catalog refresh, drop private-repo refs`
P0 implementation baseline: `1fe3830 Consolidate profile research roadmap`

## Current Diagnosis

This repository is the public GitHub profile README for `SysAdminDoc`. As of v4.9.3, the README is generated from `data/profile-catalog.json` plus live GitHub metadata through `scripts/sync-profile.ps1`, with a hand-authored LinkedIn-aligned hero section preserved above the generated catalog.

Live GitHub metadata gathered through 2026-06-04 showed:

- 184 active public repos visible through GitHub metadata.
- 177 catalog entries included in the public README and 9 public/private-state entries explicitly suppressed with reasons.
- 0 active public repos missing from the generated catalog after v4.9.0.
- 0 renamed-repo redirects after removing the duplicate `EspressoMonkey` profile row.
- 0 private visibility or medical-imaging privacy violations in `scripts/sync-profile.ps1 -Check`.
- 69 active public repos with no topics and 4 public repos with empty descriptions.
- `.github/` contains scheduled/manual profile sync, workflow security, Scorecard, CODEOWNERS, and Dependabot configuration.
- `scripts/sync-profile.ps1 -Check` validates install entrypoints, raw userscripts, GitHub Pages launch links, release/latest redirects, generated README navigation, action columns, category anchors, and primary-action coverage.
- Root `projects.json` is generated from the same catalog for portfolio consumption and includes structured primary-action metadata.
- The first-viewport profile copy leads with healthcare IT, DICOM/PACS specialization, 16+ years of infrastructure experience, 10+ production platforms, and quantified proof points while avoiding private project and employer-specific names.

One prior roadmap idea was retired: search boxes and filter chips cannot run inside the GitHub profile README because GitHub sanitizes rendered markup, including script tags and inline styles. Interactive search/filtering belongs in `sysadmindoc.github.io`; this profile README should remain generated static Markdown. (See COMPLETED.md.)

Note: the profile README is an actively-curated surface and may have concurrent curation in flight. README-affecting items below should be executed through the catalog plus regeneration, never by hand-editing the generated sections.

## Existing Planned Work

### Generation integrity and drift enforcement

- [ ] P0 — Enforce generated README/feed drift checks (hand-edit lockout)
  - Why: hand edits or live-metadata changes can silently reintroduce drift, broken links, and count mismatches; `-Check` already caught stale generated outputs in the v4.9.3 refresh.
  - Touches: `scripts/sync-profile.ps1` (`New-Readme`, `New-ProjectsExportJson`), `.github/workflows/profile-sync.yml`, optional generated-section banner and local git-hook docs.
  - Acceptance: any edit to a generated section fails `-Check`/CI until `-Write` is re-run; `README.md` carries a "do not hand-edit generated sections" banner; the headline count is generated, not typed.
  - Source: docs/research-feature-plan-2026-06-04.md (P0); RESEARCH_FEATURE_PLAN (NF1/EI4)

- [ ] P2 — Deeper metadata-drift report in `-Check` (NF2)
  - Why: `projectsExportInSync` catches feed drift, but `-Check` does not surface a structured committed-vs-live diff or a stale-`generatedAt` warning.
  - Touches: `scripts/sync-profile.ps1` (new `Test-MetadataDrift`), `reports/profile-sync-report.json` schema.
  - Acceptance: report includes a `metadataDrift` list (repo, field, old→new) and warns when `generatedAt` is older than N days; star drift is informational, structural fields (branch, release tag, visibility) are failing.
  - Source: TODO.md (NF2); docs/research-feature-plan-2026-06-04.md (Report Schema Depth)

- [ ] P2 — Deprecate/guard `-SeedCatalog` legacy parser (EI10)
  - Why: the README→catalog reverse parser (`New-CatalogFromReadme`) hard-codes star entity, em-dash separator, single-space pipes, and substring label matching and is brittle to any README drift; catalog JSON is now the source of truth.
  - Touches: `scripts/sync-profile.ps1` (parameters, `New-CatalogFromReadme`, help text), Pester tests.
  - Acceptance: seed mode requires an explicit `-ForceSeedCatalog`, emits a loud "lossy" warning, and is documented as a one-shot bootstrap; default invocation exits clearly.
  - Source: TODO.md (EI10); docs/research-feature-plan-2026-06-04.md (-SeedCatalog Legacy Parser)

### Link validation and report depth

- [ ] P2 — Parallelize link validation
  - Why: the full `-Check` passes but spends most wall time in ~115 sequential HEAD+GET probes; one blocked host can dominate runtime.
  - Touches: `scripts/sync-profile.ps1` (`Test-LinkTargets`, `Test-HttpUrl`), report warning schema.
  - Acceptance: probes run in bounded parallel batches with the same pass/fail semantics (404/410 fatal, transient 403/429/5xx/timeout as warnings), a `warningCountByHost` summary, and a lower wall-clock time.
  - Source: docs/research-feature-plan-2026-06-04.md (P2); RESEARCH_FEATURE_PLAN (EI7)

- [ ] P1 — Report schema depth (metadata hygiene, release-asset, performance sections)
  - Why: the report records pass/fail arrays but does not yet report topic gaps, description gaps, release-asset mismatches, stale feed age, or warning counts by host.
  - Touches: `scripts/sync-profile.ps1` (`Test-ProfileState`, `New-ProjectsExportJson`), `reports/profile-sync-report.json`.
  - Acceptance: report adds `metadataHygiene`, `releaseAssetDrift`, and `validationPerformance` sections; portfolio consumers ignore unknown fields.
  - Source: docs/research-feature-plan-2026-06-04.md (Report Schema Depth)

### Metadata hygiene and discoverability

- [ ] P1 — Topic coverage and topic/description drift reporting
  - Why: live metadata shows 69 active public repos without topics and 4 public repos with empty descriptions, reducing discovery and overloading the catalog with explanatory burden.
  - Touches: `data/profile-catalog.json`, `scripts/sync-profile.ps1` (`Test-ProfileState`), `reports/profile-sync-report.json`, optional helper apply-script.
  - Acceptance: report lists missing topics/descriptions and recommended `topicHints` derived from category/language/platform/role without mutating any repo; any apply mode is separate and requires an explicit allowlist.
  - Source: ROADMAP.md (P1 topic drift); docs/research-feature-plan-2026-06-04.md (P1 topic/description drift)

- [ ] P1 — Add consistent repo descriptions before README sync
  - Why: empty public-repo descriptions (e.g. `SysAdminDoc`, `AdapterLock`, `facebook-exit-guide`) weaken the generated catalog.
  - Touches: GitHub repo descriptions (reviewed apply), `data/profile-catalog.json` (`descriptionOverride`).
  - Acceptance: the four empty public descriptions are filled; GitHub repo descriptions are preferred as the short source where accurate.
  - Source: ROADMAP.md (P1)

- [ ] P1 — Submit focused projects to relevant awesome lists after metadata is clean
  - Why: clean taxonomy, stable descriptions, and link hygiene make selective awesome-list submissions worthwhile (sysadmin utilities, Android apps, browser extensions, local-first tools, profile/portfolio tooling).
  - Touches: external awesome-list PRs; candidate selection from the catalog.
  - Acceptance: a small, curated set of submissions is prepared only after topic/description hygiene lands.
  - Source: ROADMAP.md (P1)

### Accessibility and README chrome

- [ ] P1 — Theme-aware, accessible image chrome (NF3)
  - Why: the hero/stats/streak/activity/skill/capsule images are dark-only (`bg_color=0d1117`) and render as dark slabs in GitHub light mode; alt text is generic and the value proposition is trapped inside the typing SVG.
  - Touches: `scripts/sync-profile.ps1` (new `New-HeroChrome`/`New-StatsSection`), `README.md` top section (via generation), Pester fixtures.
  - Acceptance: generator emits `<picture>` blocks with dark+light sources, meaningful `alt` text, and a plain-text tagline that survives host failure; legible in both GitHub themes; coordinate with the hand-authored hero above the generated block.
  - Source: TODO.md (NF3); docs/research-feature-plan-2026-06-04.md (P1)

### Release/download taxonomy and third-party assets

- [ ] P2 — Release asset taxonomy and drift checks
  - Why: 147 public repos ship a latest release; `downloadKind`/action labels are curated and should be audited against actual release asset names (APK, EXE, ZIP, CRX, XPI, userscript, source-only, no-release).
  - Touches: `scripts/sync-profile.ps1` (REST release-asset fetch, `Get-PrimaryAction`, `Get-DownloadLabel`, `New-ProjectsExportJson`), report schema.
  - Acceptance: report flags asset-label mismatches; `projects.json` exposes `releaseAssetKinds`; installer-less source archives remain "Repo"/source-only.
  - Source: ROADMAP.md (P2 release taxonomy); docs/research-feature-plan-2026-06-04.md (P2)

- [ ] P2 — Action-baked stat/snake SVGs (NF4)
  - Why: 5–7 third-party render hosts (stats/streak/activity, komarev counter) can rate-limit/outage together and leak visitor IP/UA; Camo caches them anyway, so there is no dynamism benefit.
  - Touches: new `.github/workflows/assets-refresh.yml`, committed `assets/*.svg`, generator references to local assets.
  - Acceptance: a scheduled Action snapshots stats/streak/activity (or a Platane/snk snake) to committed SVGs; README renders with hosts blocked; the komarev counter is dropped or reduced to one tiny badge.
  - Source: TODO.md (NF4)

- [ ] P2 — Dependency/status badges only where they carry signal
  - Why: the README already depends on multiple external image services; badge overload dilutes the catalog.
  - Touches: `README.md` generated header (via generation); optional self-hosted readme-stats.
  - Acceptance: a small generated summary replaces redundant third-party widgets; self-hosting is considered only if rate limits or uptime become a recurring problem.
  - Source: ROADMAP.md (P2)

### Portfolio site (separate repo `sysadmindoc.github.io`)

- [ ] P1 — Add Pagefind (or equivalent) static search to the portfolio
  - Why: 184/177 entries exceed browse-only navigation; the README cannot host search (sanitized markup).
  - Touches: `sysadmindoc.github.io` (Pagefind build config, `data-pagefind-body` scoping) consuming `projects.json`.
  - Acceptance: search covers repo name, description, category, topics, platform, release availability, and currently-building status; suppressed/private/medical entries are excluded from the index.
  - Source: ROADMAP.md (P1); TODO.md (NF7); docs/research-feature-plan-2026-06-04.md (P1)

- [ ] P1 — Add "new", "recently updated", and "has-download" portfolio views (NF6)
  - Why: new repos are invisible until a manual refresh; there is no freshness signal.
  - Touches: `sysadmindoc.github.io` views; optional `projects.json` fields (`ageBucket`, `freshnessRank`, `releaseAssetKinds`, `searchKeywords`).
  - Acceptance: portfolio derives views from `pushedAt`, `latestRelease`, release asset type, topics, and catalog categories.
  - Source: ROADMAP.md (P1); TODO.md (NF6); docs/research-feature-plan-2026-06-04.md (P1)

- [ ] P1 — Point the portfolio at the live `projects.json` feed
  - Why: the portfolio should consume the same public catalog state as the README.
  - Touches: `sysadmindoc.github.io` fetch of `raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/projects.json`.
  - Acceptance: the portfolio renders from the feed with raw-fetch caching handled and suppressed entries excluded.
  - Source: TODO.md

### Setup bootstrapper

- [ ] P2 — Harden `setup.ps1`
  - Why: onboarding is strong but lacks an inspect-before-run path; support diagnostics are transient.
  - Touches: `setup.ps1`, `New-FirstTimeSetupSection`, optional tests.
  - Acceptance: adds `#Requires -Version 5.1`, `-CheckOnly` (reports Python/Git/winget state without installing), transcript logging to a temp path, and a README inspect-before-run row; the `irm | iex` default path keeps working.
  - Source: TODO.md; docs/research-feature-plan-2026-06-04.md (P2)

### Catalog hygiene and attribution

- [ ] P3 — Recategorize WolfPack
  - Why: WolfPack (LibreWolf portable distro) sits in a 4-item Security & Networking section; it groups better with Vigil under Desktop/Privacy.
  - Touches: `data/profile-catalog.json` (category edit) then regenerate.
  - Acceptance: WolfPack renders under Desktop/Privacy; Security & Networking is tightened.
  - Source: TODO.md (P3)

- [ ] P3 — Standardize fork/continuation + upstream-license attribution
  - Why: fork/continuation labeling is uneven (AppManagerNG shows license in body but not Featured; `(fork)` entries lack upstream link/license).
  - Touches: `data/profile-catalog.json` (`forkOf`/`upstreamLicense` fields), README renderer, `projects.json`.
  - Acceptance: Featured and category rows render upstream origin and license uniformly for forked/continued projects.
  - Source: TODO.md (P3); docs/research-feature-plan-2026-06-04.md (P3)

- [ ] P3 — Log "Forge" naming debt
  - Why: WinForge, FirewallForge, NetForge, PathForge, GitForge, ImageForge, ClipForge, and IconForge run against the no-"Forge" naming rule.
  - Touches: ROADMAP log only — do not rename live repos (breaks stars/links).
  - Acceptance: the debt is recorded and the pattern is avoided for new repos.
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

- [ ] P1 — Keep public planning docs aligned with generated sync state
  - Why: tracked planning docs can drift from the generated profile version, latest sync date, and active open items.
  - Touches: `ROADMAP.md`, `CHANGELOG.md`, `PROJECT_CONTEXT.md`.
  - Acceptance: version, latest sync date, and remaining open items stay in lockstep with profile-sync releases; public docs stay sanitized.
  - Source: docs/research-feature-plan-2026-06-04.md (P1 Public Planning Files)

### Blocked — needs user decision

- [ ] P1 — Git history scrub decision
  - Why: the local research bundle and private repo names are removed from the current tree but remain in public commit history; rewriting public profile history is disruptive.
  - Touches: `git filter-repo` (history) — user's call whether to rewrite or accept.
  - Acceptance: user decides to scrub history or formally accept the residue.
  - Source: TODO.md (blocked)

- [ ] P2 — Topics for ~60 bare repos via `gh api .../topics`
  - Why: applying topics mutates other repositories, so it needs explicit user go-ahead and a reviewed allowlist (out of scope for autonomous edits to this repo).
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

<!-- populated by the research pass -->
</content>
