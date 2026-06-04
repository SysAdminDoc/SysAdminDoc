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

*Research conducted 2026-06-03. Items below are new — not duplicates of Existing Planned Work.*

These come from reading `scripts/sync-profile.ps1` (1,495 lines), the four workflows, the Pester suite, `setup.ps1`, the generated `README.md`/`projects.json`, and live verification. Existing Planned Work already covers: drift lockout (P0), metadata-drift report depth, `-SeedCatalog` guard, parallel link validation, report schema depth, topic/description hygiene, theme-aware image chrome, release-asset taxonomy, action-baked SVGs, portfolio search/freshness, `setup.ps1` `-CheckOnly`/transcript, stale-project review, planning-doc sync, and the blocked decisions. The items below are deliberately outside all of those.

### Data integrity and trust gates

- [ ] P1 — Publish (or stop referencing) the JSON Schema URLs the feed advertises
  - Why: `data/profile-catalog.json` and `projects.json` both declare `schema` pointers (`https://sysadmindoc.github.io/schemas/profile-catalog.v1.json` and `.../profile-projects.v1.json`), but those URLs return HTTP 404. Any downstream consumer that follows the advertised contract gets a dead link, and the feed has no enforceable shape.
  - Evidence: `scripts/sync-profile.ps1:1086` (`schema = "https://sysadmindoc.github.io/schemas/profile-projects.v1.json"`), `:1264` (catalog schema), `data/profile-catalog.json:1`. Verified 2026-06-03: `https://sysadmindoc.github.io/schemas/profile-projects.v1.json` → 404.
  - Touches: `sysadmindoc.github.io` (publish the two schema docs) OR `scripts/sync-profile.ps1` (point `schema` at a versioned path that exists, e.g. the raw GitHub blob of a committed `schemas/*.json`); optional `schemas/` dir in this repo.
  - Acceptance: both advertised `schema` URLs resolve to a real JSON Schema that validates a current `projects.json`/catalog, or the field is repointed to a live URL; a Pester/CI step validates the generated feed against the committed schema.
  - Verify: `curl -sI <schema-url>` → 200; `Invoke-Pester` includes a schema-validation case that fails on a missing required field.
  - Complexity: M

- [ ] P1 — Add a self-contained version/date consistency gate across tracked planning docs
  - Why: `ROADMAP.md`, `CHANGELOG.md`, and `PROJECT_CONTEXT.md` each hand-type the current version (`v4.9.3`) and "latest sync" date; the existing "keep planning docs aligned" item is a manual discipline with no check. A single mismatched string ships silently. This is the *automated guard*, not the manual sync already planned.
  - Evidence: `ROADMAP.md:8` (`Current repo version: v4.9.3`), `CHANGELOG.md:5` (`## [v4.9.3]`), `RESEARCH_REPORT.md:7`; `Test-ProfileState` (`scripts/sync-profile.ps1:1324`) checks README/feed drift but never reads the planning docs.
  - Touches: `scripts/sync-profile.ps1` (new `Test-DocVersionConsistency`), `reports/profile-sync-report.json`, Pester.
  - Acceptance: `-Check` fails when the version token in CHANGELOG, ROADMAP, and PROJECT_CONTEXT disagree, or when the latest CHANGELOG date is newer than the recorded sync date; report adds a `docVersionConsistency` block.
  - Verify: deliberately bump one doc's version, run `-Check`, observe non-zero exit and the new report field.
  - Complexity: M

- [ ] P2 — Extend link validation to hero/header and non-catalog URLs
  - Why: `Test-LinkTargets` only probes catalog-derived entrypoint/userscript/live/release URLs. The hand-authored hero — the portfolio link `https://sysadmindoc.github.io/`, the `setup.ps1` blob link, and the third-party image hosts (capsule-render, readme-typing-svg, skill-icons, github-readme-stats, streak-stats, activity-graph, komarev) — is never checked. A dead portfolio link or a retired image host would pass the gate.
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

### Quick Wins

P2/P3, each doable in well under an hour:

- [ ] P2 — Generated-README size budget guard (informational warning in the report).
- [ ] P2 — SECURITY.md with a public-safe disclosure path (satisfies Scorecard's Security-Policy check).
- [ ] P3 — `.editorconfig` pinning LF + final-newline + trim-trailing-whitespace.
- [ ] P3 — Recorded decision note on the retained third-party render hosts.

### Larger Bets

P1/P2 needing design or staged rollout:

- [ ] P1 — Publish the advertised JSON Schemas and validate the feed against them (cross-repo with `sysadmindoc.github.io`; defines the downstream contract).
- [ ] P1 — Doc version/date consistency gate wired into `-Check` and CI.
- [ ] P1 — Pester coverage for `Test-ProfileState`/`Update-Header`/medical-gate (protects the privacy guard before any refactor).
- [ ] P2 — REST release-fallback N+1 cap with rate-limit awareness and partial-data abort.
- [ ] P2 — Header/non-catalog link validation folded into the existing link gate.
</content>
