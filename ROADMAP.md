# SysAdminDoc Profile Roadmap

Last research refresh: 2026-05-17
Evidence bundle: `.ai/research/2026-05-17/`
Current repo version: v4.8.0
Research baseline HEAD: `3d4ed8f Release v4.7.0 -- catalog refresh, drop private-repo refs`
P0 implementation baseline: `1fe3830 Consolidate profile research roadmap`

## Current Diagnosis

This repository is the public GitHub profile README for `SysAdminDoc`. As of v4.8.0, the README is generated from `data/profile-catalog.json` plus live GitHub metadata through `scripts/sync-profile.ps1`.

Live GitHub metadata gathered on 2026-05-17 showed:

- 178 active public repos visible to `gh repo list SysAdminDoc --visibility public`.
- 166 unique `github.com/SysAdminDoc/...` repo mentions in `README.md`.
- 0 active public repos missing from the generated catalog after v4.8.0.
- 0 renamed-repo redirects after removing the duplicate `EspressoMonkey` profile row.
- 0 private visibility or medical-imaging privacy violations in `scripts/sync-profile.ps1 -Check`.
- 170 catalog entries included in the public README and 8 public repos explicitly suppressed with reasons.
- `.github/` now contains scheduled/manual profile sync, workflow security, Scorecard, CODEOWNERS, and Dependabot configuration.
- `scripts/sync-profile.ps1 -Check` now validates install entrypoints, raw userscripts, GitHub Pages launch links, and release/latest redirects.

One prior roadmap idea needs correction: search boxes and filter chips cannot run inside the GitHub profile README because GitHub sanitizes rendered markup, including script tags and inline styles. Interactive search/filtering belongs in `sysadmindoc.github.io`; this profile README should remain generated static Markdown.

## P0 - Stabilize Catalog Truth

- [x] Build a canonical catalog source file.
  - Create `data/profile-catalog.json` or `data/profile-catalog.yml` with one row per public catalog entry.
  - Fields: `repo`, `category`, `includeInReadme`, `includeInPortfolio`, `branch`, `entrypoint`, `installKind`, `downloadKind`, `descriptionOverride`, `featured`, `currentlyBuilding`, `privateReason`, `notes`.
  - Seed it from the current README plus live GitHub metadata.
  - Evidence: README drift counts above; existing clone-install-run standard in `CLAUDE.md`; GitHub REST/GraphQL metadata exposes name, description, topics, default branch, stars, releases, and visibility.

- [x] Implement `scripts/sync-profile.ps1`.
  - Read catalog data plus GitHub metadata using `gh`.
  - Regenerate README project sections, category counts, star counts, featured rankings, release links, and branch-pinned install snippets.
  - Preserve manual description overrides where GitHub repo descriptions are empty, too long, stale, or less useful for visitors.
  - Refuse to include private repos in the generated public README.
  - Evidence: `README.md` hardcodes every category; live metadata found 13 missing active public repos, 18 star mismatches, and 40 release-link gaps.

- [x] Add a strict validation mode before changing README content.
  - `scripts/sync-profile.ps1 -Check` should exit non-zero on stale stars, missing public repos, private/renamed/deleted repo links, branch mismatches, missing release links for qualifying artifacts, and count drift.
  - Keep a JSON report artifact for review.
  - Evidence: current manual state already has drift; clone branch audit was clean and should stay guarded.

- [x] Ship a v4.8.0 catalog refresh from the generated output.
  - Resolve `EspressoMonkey`, which currently resolves through GitHub metadata as `ScriptVault`.
  - Add or intentionally suppress `OpenLumen`, `PhoneFork`, `AI-Usage_Tracker`, and other newly public repos with explicit catalog reasons.
  - Refresh star counts and featured-project ordering from live values.
  - Recalculate the public-project claim from live active-public count.
  - Evidence: `OpenCut` is shown as 10 stars in one section and 16 live; `win11-nvme-driver-patcher` is shown as 35 in one section and 40 live.

## P0 - Guard Against Public/Private Mistakes

- [x] Add a public-readme privacy gate.
  - Block any README row whose live visibility is not `PUBLIC`.
  - Block medical/X-ray/PACS/DICOM-related repos from public listing unless an explicit allowlist entry exists.
  - Emit a separate private-repo compliance report but do not publish private names in the public README unless already intentionally public and verified safe.
  - Evidence: v4.7.0 removed private TeamStation and DICOM-PACS-Migrator because public links 404 for visitors; global rules require X-ray and medical-imaging repos to stay private.

- [x] Add a renamed/deleted repo resolver.
  - Detect GitHub redirects and canonical repository names.
  - Fail validation when a README link points to a renamed repo unless the catalog explicitly records the alias.
  - Evidence: `gh repo view SysAdminDoc/EspressoMonkey` returned canonical repo data for `ScriptVault`, while README still links `EspressoMonkey`.

## P1 - Automate Safely

- [x] Add `.github/workflows/profile-sync.yml`.
  - Triggers: `workflow_dispatch` plus a non-top-of-hour schedule.
  - Default to check-only on schedule; create a PR or commit only when explicitly enabled.
  - Use least-privilege `GITHUB_TOKEN` permissions.
  - Evidence: GitHub scheduled workflows can be delayed or dropped around high-load periods; scheduled workflows run on the default branch only.

- [x] Add workflow hardening.
  - Add CODEOWNERS or an equivalent review gate for `.github/workflows/**`.
  - Run `zizmor` once workflows exist.
  - Add OpenSSF Scorecard if the repo starts relying on Actions.
  - Pin or monitor third-party actions deliberately, documenting the tradeoff between SHA pinning and Dependabot action alerts.
  - Evidence: GitHub secure-use docs recommend Dependabot/action dependency visibility and Scorecard; GitHub workflow syntax supports explicit token permissions.

- [x] Add markdown/link/install validation.
  - Validate all `github.com/SysAdminDoc/<repo>` links against GitHub metadata instead of blind HTTP only.
  - Validate all `raw.githubusercontent.com` userscript links against live default branches and files.
  - Validate launch links on `sysadmindoc.github.io`.
  - Keep the existing clone-install-run snippets branch-pinned.
  - Evidence: current branch audit found 0 mismatches, but prior changelog entries show 16 broken one-liners were fixed in v4.2.0.

## P1 - Move Interactive Discovery To The Portfolio

- [ ] Feed `sysadmindoc.github.io` from the same catalog data.
  - Publish a generated `projects.json` from this repo or consume it from the portfolio repo.
  - Keep the README as the compact catalog and make the portfolio the rich searchable experience.
  - Evidence: GitHub README HTML is sanitized; Pagefind supports static search without backend infrastructure.

- [ ] Add Pagefind or an equivalent static search to the portfolio site.
  - Search repo names, descriptions, categories, topics, platform, release availability, and currently-building status.
  - Use filters and sorting on the portfolio, not in the GitHub README.
  - Evidence: Pagefind is designed for static sites and chunks search indexes for low-bandwidth browser search.

- [ ] Add "new", "recently updated", and "has download" portfolio views.
  - Derive from `pushedAt`, `latestRelease`, release asset type, topics, and catalog categories.
  - Evidence: live repo metadata already contains enough fields to generate this.

## P1 - Improve Discoverability

- [ ] Add topic coverage and topic drift reporting.
  - Generate recommended topics per repo from catalog category, language, platform, and key feature tags.
  - Report missing topics for public repos; apply topics with `gh api` only after review.
  - Evidence: GitHub topics improve repository discovery; the live audit found many recent active public repos without topics.

- [ ] Submit focused projects to relevant awesome lists after metadata is clean.
  - Candidates: sysadmin utilities, Android apps, browser extensions, local-first tools, and profile/portfolio tooling.
  - Do this selectively; awesome-list maintainers expect curated, personally recommended resources.
  - Evidence: `awesome-sysadmin`, `awesome-github-profile-readme`, and awesome-list tooling reward clean taxonomy, stable descriptions, and link hygiene.

- [ ] Add consistent repo descriptions before README sync.
  - Fix empty public repo descriptions for `SysAdminDoc`, `AdapterLock`, and `facebook-exit-guide`.
  - Prefer GitHub repo descriptions as the short source when they are accurate.
  - Evidence: live metadata found empty descriptions in active public repos.

## P2 - Quality And Trust Signals

- [ ] Add a release/download taxonomy.
  - Classify APK, EXE, ZIP, XPI, CRX, userscript, source-only, and no-release repos.
  - Generate download labels consistently from release assets rather than manually curated guesses.
  - Evidence: 40 mentioned repos have latest releases but no README release/latest link.

- [ ] Add dependency/status badges only where they carry signal.
  - Avoid badge overload in the profile README.
  - Prefer a small generated summary over many third-party widgets.
  - Consider self-hosting GitHub readme stats if rate limits or uptime become a recurring problem.
  - Evidence: current README already depends on multiple external image services; github-readme-stats documents self-hosting for rate-limit and caching control.

- [ ] Add contributor/community signals if public contribution grows.
  - Evaluate All Contributors or a generated contributor summary across public repos.
  - Keep this below project discovery, because most repos are currently personal tools.
  - Evidence: All Contributors automates README contributor recognition, but the current portfolio goal is project discoverability first.

- [ ] Add a quarterly archive/retirement review.
  - Mark stale repos in the generated catalog.
  - Keep forked or intentionally dormant repos out of the main featured set.
  - Evidence: global working rules already call for archive review after 6+ months of inactivity.

## Verification Standard

Before a generated README refresh is shipped:

- `git status --short --branch`
- `git log -10 --oneline --decorate`
- `scripts/sync-profile.ps1 -Check`
- link audit for GitHub repo URLs, release/latest URLs, raw userscript URLs, and GitHub Pages launch URLs
- clone snippet audit for default branch and entrypoint existence
- privacy gate report with zero public README links to private repos
- markdown render smoke check on GitHub after push

## Source Index

The full source register is `.ai/research/2026-05-17/SOURCE_REGISTER.md`. High-impact sources used in this roadmap include:

- Local: `README.md`, `CHANGELOG.md`, `CLAUDE.md`, previous `ROADMAP.md`, `setup.ps1`, `git log`, `gh repo view`, `gh repo list`.
- GitHub Docs: profile README requirements, repository README behavior, repository topics, Actions schedule and permissions, secure Actions use.
- GitHub Markup: rendered README HTML is sanitized before display.
- Microsoft Learn: WinGet install flags and PowerShell execution-policy behavior.
- Ecosystem: Pagefind, Shields.io, awesome-lint, GitHub Profile README Generator, awesome-github-profile-readme, awesome-sysadmin, OpenSSF Scorecard, zizmor.
