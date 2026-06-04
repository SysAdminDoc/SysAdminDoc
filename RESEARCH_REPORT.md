# Research Report

Consolidated from legacy research and feature-planning documents on 2026-06-03. This is the canonical research home for the profile-catalog system; planned work derived from it lives in `ROADMAP.md`. The dated source bundle was archived to `docs/archive/research-feature-plan-2026-06-04.md`.

Research refresh: 2026-06-04
Deep-research addendum: 2026-06-03 (see "Deep-Research Addendum — 2026-06-03" below)
Repository: SysAdminDoc/SysAdminDoc
Current version after this refresh: v4.9.5

## Verification Refresh — 2026-06-04

- `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Detailed"`
  passed 20/20 tests after the v4.9.5 metadata-drift report update.
- `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check` completed
  successfully with `readmeInSync=true`, 0 fatal metadata drift rows, full link
  validation enabled, 0 link failures, and 0 link warnings. Raw
  `projectsExportInSync` remains a report signal; info-only star/topic/`pushedAt`
  drift is now reported without failing the gate.
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
- Improvement opportunities: add `topicHints`, `forkOf`, `upstreamLicense`, `releaseAssetPolicy`, `stalePolicy`, and `descriptionOwner` fields.

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
- Current maturity: strong; final check passed with zero fatal link failures and one nonfatal 502 warning.
- Improvement opportunities: make link probes parallel, add metadata drift detail, and classify warnings by transient status.

### Public Project Feed

- User value: lets the portfolio site consume the same public catalog state as the README.
- Entry point: `projects.json`.
- Main code: `New-ProjectsExportJson`.
- Current maturity: complete but underused until the portfolio consumes it.
- Improvement opportunities: add sort keys, age buckets, release-asset taxonomy, topic-hint fields, and generated freshness flags.

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
- Current maturity: functional and tolerant of transient failures, but slow because probes are sequential.
- Improvement opportunities: parallel probes, shorter per-host timeout, host-level warning summary, and cached validation in CI artifacts.

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

## Open Questions

- Which repo-topic taxonomy should be the canonical source: catalog category only, GitHub language plus category, or a curated `topicHints` field?
- Should low-risk generated metadata drift be auto-PR'd on schedule, or should scheduled jobs remain check-only with manual `write-pr`?
- Should `PROJECT_CONTEXT.md` stay tracked as public project documentation, or should it be reduced to public-safe status notes only?
- What is the portfolio site's preferred schema contract for search and freshness fields from `projects.json`?
