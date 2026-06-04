# Completed Work

Items consolidated from legacy planning documents on 2026-06-03.

## Shipped Features

### Catalog truth and generation pipeline

- [x] Build a canonical catalog source file (`data/profile-catalog.json`) with one row per public catalog entry (repo, category, includeInReadme, includeInPortfolio, branch, entrypoint, installKind, downloadKind, descriptionOverride, featured, currentlyBuilding, privateReason, notes), seeded from the README plus live GitHub metadata. — *Source: ROADMAP.md*
- [x] Implement `scripts/sync-profile.ps1` to read catalog data plus GitHub metadata via `gh` and regenerate README project sections, category counts, star counts, featured rankings, release links, and branch-pinned install snippets, preserving manual description overrides and refusing to include private repos. — *Source: ROADMAP.md*
- [x] Add a strict validation mode (`scripts/sync-profile.ps1 -Check`) that exits non-zero on stale stars, missing public repos, private/renamed/deleted repo links, branch mismatches, missing release links, and count drift, keeping a JSON report artifact. — *Source: ROADMAP.md*
- [x] Ship a v4.8.0 catalog refresh from the generated output: resolve the EspressoMonkey→ScriptVault alias, add or intentionally suppress newly public repos with explicit reasons, refresh star counts and featured ordering, and recalculate the public-project claim from the live active-public count. — *Source: ROADMAP.md*
- [x] Catalog regenerated to 184 public / 187 entries; 10 new repos cataloged (AndroidEmulatorPlus, Brave-Portable-Updater, Droidsmith, FoxPort, IMDb_Enhanced, Keepr, QuotaGlass, TaskCopy, TsunamiSimulator, and self). — *Source: TODO.md*
- [x] Generator resilience: GraphQL retry/backoff plus REST fallback (`Get-GitHubReposFromRest`). — *Source: TODO.md*
- [x] `Test-ReadmeExperience` checks: category anchors, primary-action coverage, empty download-label detection, currently-building action column. — *Source: TODO.md*
- [x] Featured vs Currently-Building AppManagerNG contradiction resolved by regeneration; malformed `/releases/latest` title links fixed. — *Source: TODO.md*
- [x] `projects.json` structured fields added: `primaryAction`, `hasDownload`, `hasLiveDemo`, `hasDirectInstall`. — *Source: TODO.md*
- [x] Refreshed generated `README.md` and `projects.json` from live GitHub metadata after `-Check` caught stale star-count/feed drift (v4.9.3). — *Source: TODO.md*

### Privacy, safety, and supply-chain hardening

- [x] Add a public-readme privacy gate that blocks any README row whose live visibility is not PUBLIC, blocks medical/X-ray/PACS/DICOM repos unless explicitly allowlisted, and emits a separate private-repo compliance report without publishing private names. — *Source: ROADMAP.md*
- [x] Add a renamed/deleted repo resolver that detects GitHub redirects and canonical names and fails validation on README links to renamed repos absent a catalog alias. — *Source: ROADMAP.md*
- [x] Privacy scrub: untracked the `.ai/` research bundle, gitignored local working files, and scrubbed private medical repo names from `CHANGELOG.md` and `ROADMAP.md`. — *Source: TODO.md*
- [x] Anchored the medical-keyword pattern to word boundaries so "dose" no longer matches inside "glucose" and similar false positives. — *Source: TODO.md*
- [x] Forced `[Console]::OutputEncoding` to UTF-8 so `gh` JSON output is not mojibake'd on legacy Windows consoles; refreshed feed. — *Source: TODO.md*

### Automation and CI

- [x] Add `.github/workflows/profile-sync.yml` with `workflow_dispatch` plus a non-top-of-hour schedule, defaulting to check-only on schedule, with least-privilege `GITHUB_TOKEN` permissions. — *Source: ROADMAP.md*
- [x] Add workflow hardening: CODEOWNERS review gate for `.github/workflows/**`, zizmor, OpenSSF Scorecard, and deliberate action pinning/monitoring. — *Source: ROADMAP.md*
- [x] Add markdown/link/install validation against GitHub metadata, raw userscript links against live default branches, and portfolio launch links, keeping clone-install-run snippets branch-pinned. — *Source: ROADMAP.md*
- [x] Fixed the dead-code no-changes guard in `profile-sync.yml` where `if (git diff --quiet)` tested stdout instead of the exit code, causing clean scheduled runs to fail. — *Source: TODO.md*
- [x] Link-validation de-flake: 12s timeout plus retry in `Test-HttpUrl`; only 404/410 are fatal, while transient 403/429/5xx/timeout become `linkValidationWarnings`. — *Source: TODO.md*

### Tests and reliability

- [x] Added a hermetic Pester v5 suite (`tests/`, 16 tests) plus a `tests.yml` CI job and a dot-source test seam. — *Source: TODO.md*
- [x] Fixed a StrictMode bug where `Test-HttpUrl` dereferenced `$_.Exception.Response` on exceptions lacking it (DNS failures crashed `-Check`). — *Source: TODO.md*
- [x] Renamed the splat array shadowing `$args` in `Get-GitHubRepos`. — *Source: TODO.md*

### Discoverability and positioning

- [x] Add premium generated README navigation: a compact Start Here table, a Catalog Snapshot, action columns on featured/currently-building rows, stable category anchors, and per-category "Start with" previews. — *Source: ROADMAP.md*
- [x] Align the first-viewport profile narrative with LinkedIn positioning (hero descriptor, typing lines, bio copy, proof-point table) around healthcare IT, DICOM/PACS, 16+ years of IT operations, and 10+ production platforms, keeping private project and employer names out of the public profile. — *Source: ROADMAP.md*
- [x] Fix the first-viewport table layout by removing the HTML two-column wrapper that cramped the Proof Points and Currently Building tables, while keeping the generated Currently Building table marker intact. — *Source: ROADMAP.md*
- [x] Feed `sysadmindoc.github.io` from the same catalog data by publishing a generated `projects.json` and keeping the README as the compact catalog. — *Source: ROADMAP.md*
- [x] Added the public-safe companion research plan `docs/research-feature-plan-2026-06-04.md`. — *Source: TODO.md*

## Stale / Obsolete Items

- [STALE] In-README search boxes and filter chips. — *Reason: GitHub sanitizes rendered README markup (script tags and inline styles), so interactive search/filtering cannot run in the profile README; it belongs in `sysadmindoc.github.io`. The profile README remains generated static Markdown. Source: ROADMAP.md*
</content>
</invoke>
