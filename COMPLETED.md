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
- [x] Enforced generated README/feed drift checks with a generated-catalog hand-edit notice, `readmeExperienceChecks.generatedCatalogNotice`, refreshed header counts, Pester coverage, and a one-process workflow write/check path (v4.9.4). — *Source: ROADMAP.md*
- [x] Added structured metadata-drift reporting with fatal/informational severities, stale generated-feed age warnings, and Pester coverage for branch/release/star/stale-age behavior (v4.9.5). — *Source: ROADMAP.md*
- [x] Guarded the legacy README-to-catalog reverse parser behind explicit `-ForceSeedCatalog`, with lossy bootstrap warnings and seed-mode subprocess coverage (v4.9.6). — *Source: ROADMAP.md*
- [x] Parallelized link validation with bounded probe batches, `linkValidationSummary`, `warningCountByHost`, and hermetic warning/failure host-summary coverage (v4.9.7). — *Source: ROADMAP.md*
- [x] Extended link validation to generated README header/non-catalog links, with fatal portfolio/setup probes, non-fatal image-host warnings grouped under `headerHostWarnings`, report-schema fields, and Pester coverage (v4.9.49). — *Source: ROADMAP.md*
- [x] Expanded report schema with `metadataHygiene`, visitor-facing `releaseAssetDrift`, and `validationPerformance` sections plus Pester coverage (v4.9.8). — *Source: ROADMAP.md*
- [x] Added non-mutating topic hints, catalog categories, and catalog-backed description suggestions to metadata hygiene reporting, with an allowlist-required apply policy (v4.9.9). — *Source: ROADMAP.md*
- [x] Filled the four empty public GitHub repository descriptions from the reviewed `metadataHygiene.missingDescriptions` allowlist and regenerated the report to 0 missing descriptions (v4.9.10). — *Source: ROADMAP.md*
- [x] Prepared a focused awesome-list submission shortlist with target lists, proposed entry text, and pre-submit gates, without opening external PRs (v4.9.11). — *Source: ROADMAP.md*
- [x] Added release asset taxonomy from latest-release asset names, exported asset kinds/names in `projects.json`, corrected mismatched catalog labels, and regenerated to 0 release asset kind mismatches (v4.9.13). — *Source: ROADMAP.md*
- [x] Added release/download trust metadata to visitor-facing feed rows, including checksum/signature/SBOM/attestation/debug/source-only filename evidence, schema validation, trust-level counts, checksum-gap reporting, and debug artifact reporting (v4.9.44). — *Source: ROADMAP.md*
- [x] Added per-project repository license metadata to visitor-facing feed rows with `licenseKey`, `licenseName`, and `licenseSpdxId`, plus sync-report detected/missing/non-standard/license-count aggregates (v4.9.55). — *Source: ROADMAP.md*
- [x] Added committed local SVG profile metric panels, asset sync/report checks, and a scheduled/manual asset-refresh workflow; removed komarev plus third-party stats/streak/activity hosts from the generated README (v4.9.14). — *Source: ROADMAP.md*
- [x] Made generated profile chrome motion-safe by replacing external capsule/typing motion with committed static header/footer SVG assets, adding `readmeExperienceChecks.motionSafeChrome` plus render-host reporting, and adding Pester/schema coverage (v4.9.47). — *Source: ROADMAP.md*
- [x] Removed redundant Shields follower/star image badges, moved total public stars into the local stats SVG, added badge/chrome-count report guards, and fixed duplicate generated stats chrome across repeated writes (v4.9.15). — *Source: ROADMAP.md*
- [x] Verified the separate `sysadmindoc.github.io` Pagefind search implementation: `/search/`, Pagefind Component UI, build-time `dist/pagefind`, Category filter and Type metadata, and no-JS fallbacks; portfolio build indexed 198 pages / 18,774 words / 1 filter (v4.9.16). — *Source: ROADMAP.md*
- [x] Implemented the separate `sysadmindoc.github.io` New, Recently updated, and Has download catalog views with URL-backed `view=` state, NEW/DOWNLOAD chips, and focused browser/mobile verification (v4.9.17, portfolio commit `29c2b1d`). — *Source: ROADMAP.md*
- [x] Implemented separate `sysadmindoc.github.io` consumption of the live SysAdminDoc `projects.json` feed with build-time raw-cache sync, suppressed-row exclusion, feed-backed routes/feeds/language lanes/timeline/OG routes, local curated overlays, and fallback data (v4.9.18, portfolio commit `9117f45`). — *Source: ROADMAP.md*
- [x] Published and validated the feed JSON Schema contracts with committed `schemas/profile-catalog.v1.json` and `schemas/profile-projects.v1.json`, raw GitHub schema URLs, `schemaValidation` report output, Pester contract tests, and array-stable release/topic feed fields (v4.9.19). — *Source: ROADMAP.md*
- [x] Published and validated the sync-report JSON Schema contract with `schemas/profile-sync-report.v1.json`, a top-level report `schema` URL, `schemaValidation.report`, `-Check` failure wiring, and malformed-report Pester coverage (v4.9.45). — *Source: ROADMAP.md*
- [x] Added deterministic public-safe feed provenance with source repository, generation-base commit, catalog/generator/schema SHA-256 hashes, metadata snapshot time, metadata provider, repository enumeration status, schema validation, report summary, and drift coverage (v4.9.43). — *Source: ROADMAP.md*
- [x] Added the planning-doc version/date consistency gate with `Test-DocVersionConsistency`, `docVersionConsistency` report output, `-Check` failure wiring, and Pester coverage for aligned docs, version mismatches, and stale sync dates (v4.9.20). — *Source: ROADMAP.md*
- [x] Added warning-only profile repository release/tag consistency reporting with `profileReleaseConsistency`, latest GitHub release comparison, expected tag-ref checks, and public-safe summary counts (v4.9.57). — *Source: ROADMAP.md*
- [x] Hardened `setup.ps1` with `#Requires -Version 5.1`, `-CheckOnly` diagnostics, best-effort `%TEMP%` transcript logging, generated inspect-before-install README guidance, and `readmeExperienceChecks.setupInspectPath` coverage (v4.9.21). — *Source: ROADMAP.md*
- [x] Recategorized WolfPack and Vigil into Native Desktop Applications, tightening Security & Networking to 3 repos and grouping the privacy/browser packaging rows together (v4.9.22). — *Source: ROADMAP.md*
- [x] Standardized fork/continuation attribution with catalog `forkOf`/`upstreamLicense` fields, generated feed `forkOf`/`forkOfUrl`/`upstreamLicense` fields, README upstream/license rendering, schema updates, and Pester coverage (v4.9.23). — *Source: ROADMAP.md*
- [x] Added fork-parent drift reporting that compares live GitHub forks against catalog `forkOf`, classifies catalog continuations/imports, and summarizes missing/mismatched/unavailable parent warnings without failing validation (v4.9.56). — *Source: ROADMAP.md*
- [x] Logged "Forge" naming debt for WinForge, FirewallForge, NetForge, PathForge, GitForge, ImageForge, ClipForge, IconForge, and MediaForge, retaining live names to avoid broken links/releases/stars/install snippets while avoiding the pattern for new repositories (v4.9.24). — *Source: ROADMAP.md*

### Privacy, safety, and supply-chain hardening

- [x] Add a public-readme privacy gate that blocks any README row whose live visibility is not PUBLIC, blocks medical/X-ray/PACS/DICOM repos unless explicitly allowlisted, and emits a separate private-repo compliance report without publishing private names. — *Source: ROADMAP.md*
- [x] Add a renamed/deleted repo resolver that detects GitHub redirects and canonical names and fails validation on README links to renamed repos absent a catalog alias. — *Source: ROADMAP.md*
- [x] Privacy scrub: untracked the local research bundle, gitignored local working files, and scrubbed private medical repo names from `CHANGELOG.md` and `ROADMAP.md`. — *Source: TODO.md*
- [x] Anchored the medical-keyword pattern to word boundaries so "dose" no longer matches inside "glucose" and similar false positives. — *Source: TODO.md*
- [x] Forced `[Console]::OutputEncoding` to UTF-8 so `gh` JSON output is not mojibake'd on legacy Windows consoles; refreshed feed. — *Source: TODO.md*
- [x] Redacted all public `projects.json.suppressed` rows into dedicated suppression records so suppressed repo names, URLs, descriptions, primary actions, release fields, topics, and notes are not exported in the public feed (v4.9.42). — *Source: ROADMAP.md*

### Automation and CI

- [x] Add `.github/workflows/profile-sync.yml` with `workflow_dispatch` plus a non-top-of-hour schedule, defaulting to check-only on schedule, with least-privilege `GITHUB_TOKEN` permissions. — *Source: ROADMAP.md*
- [x] Add workflow hardening: CODEOWNERS review gate for `.github/workflows/**`, zizmor, OpenSSF Scorecard, and deliberate action pinning/monitoring. — *Source: ROADMAP.md*
- [x] Added a PSScriptAnalyzer static-analysis CI lane for `scripts/sync-profile.ps1` and `setup.ps1`, with curated settings, documented exclusions, pinned module install, and script fixes for analyzer findings (v4.9.25). — *Source: ROADMAP.md*
- [x] Repaired the OpenSSF Scorecard publish workflow by keeping workflow-level permissions read-only, moving `security-events: write`/`id-token: write` to the Scorecard job, and adding offline Pester coverage for the required permission shape (v4.9.26). — *Source: ROADMAP.md; docs/research-feature-plan-2026-06-05.md*
- [x] Added a live GitHub-rendered profile smoke check with Chrome/Chromium DevTools automation, desktop/mobile screenshots, overflow/image/section assertions, profile-sync artifact upload, and offline wiring coverage (v4.9.27). — *Source: ROADMAP.md; docs/research-feature-plan-2026-06-05.md*
- [x] Aligned the rendered-profile smoke section assertions to the current generated README labels and added Pester coverage against the stale `Python Applications` expectation (v4.9.48). — *Source: live rendered-smoke follow-up*
- [x] Added read-only generated-profile validation on pull requests that touch README/catalog/feed/report/schema/profile-asset/sync-script/setup/test/profile-workflow paths, with Pester coverage for the trigger surface (v4.9.28). — *Source: ROADMAP.md; docs/research-feature-plan-2026-06-05.md*
- [x] Added an explicit generated-PR validation handoff: profile-sync and profile-assets PR workflows dispatch `profile-sync.yml` in check mode on the generated branch, link the validation run search in PR bodies and summaries, and use scoped `actions: write` only in PR-creating jobs (v4.9.54). — *Source: ROADMAP.md*
- [x] Added public-safe intake files: `SECURITY.md`, broken-link/profile-correction/workflow issue forms, issue chooser security routing, and a generated-profile-aware PR template with Pester coverage (v4.9.29). — *Source: ROADMAP.md; docs/research-feature-plan-2026-06-05.md*
- [x] Made required-check candidate workflows always create pull request and merge-queue checks by removing PR path filters from Tests, Profile sync, and Workflow security, with Pester coverage guarding the trigger shape (v4.9.30). — *Source: ROADMAP.md; docs/research-feature-plan-2026-06-05.md*
- [x] Added public-safe profile-sync report summaries and retained report artifacts to profile-sync and profile-assets refresh workflows, with Pester coverage for the helper and wiring (v4.9.31). — *Source: ROADMAP.md; docs/research-feature-plan-2026-06-05.md*
- [x] Added read-only repository settings and community-health baseline reporting with public-safe `repositorySettings`/`communityHealth` sections, local required intake-file fatal gaps, summary rows, schema support, and Pester fixture coverage (v4.9.53). — *Source: ROADMAP.md*
- [x] Added explicit timeout budgets to every GitHub Actions job, with Pester coverage for timeout presence and maximum duration (v4.9.32). — *Source: ROADMAP.md; docs/research-feature-plan-2026-06-05.md*
- [x] Added checksum-verified `actionlint` 1.7.12 to workflow-security beside `zizmor`, with Pester coverage for the pinned install and command wiring (v4.9.33). — *Source: ROADMAP.md; docs/research-feature-plan-2026-06-05.md*
- [x] Pinned CI-installed validation tools by installing Pester 5.7.1 with `-RequiredVersion`, installing `zizmor` 1.25.2 from hash-checked `requirements-ci.txt`, documenting the reviewed update path, and adding Pester source guards (v4.9.46). — *Source: ROADMAP.md*
- [x] Applied Dependabot PR #5's pinned `actions/checkout` 6.0.3 SHA across all workflow checkout steps, with Pester coverage against reverting to the older 4.3.1 SHA (v4.9.34). — *Source: ROADMAP.md; hosted Tests annotation*
- [x] Applied Dependabot PR #6's pinned `github/codeql-action/upload-sarif` 4.36.1 SHA to the Scorecard SARIF upload step, with Pester coverage against reverting to the older 3.35.5 SHA (v4.9.35). — *Source: ROADMAP.md; Dependabot PR #6*
- [x] Fixed the advertised Windows PowerShell `setup.ps1 -CheckOnly` path by keeping `setup.ps1` ASCII-only, adding source-level Pester coverage, and adding an always-created `Windows setup smoke` workflow job that parses and runs the bootstrapper with Windows PowerShell (v4.9.41). — *Source: ROADMAP.md*
- [x] Add markdown/link/install validation against GitHub metadata, raw userscript links against live default branches, and portfolio launch links, keeping clone-install-run snippets branch-pinned. — *Source: ROADMAP.md*
- [x] Fixed the dead-code no-changes guard in `profile-sync.yml` where `if (git diff --quiet)` tested stdout instead of the exit code, causing clean scheduled runs to fail. — *Source: TODO.md*
- [x] Link-validation de-flake: 12s timeout plus retry in `Test-HttpUrl`; only 404/410 are fatal, while transient 403/429/5xx/timeout become `linkValidationWarnings`. — *Source: TODO.md*
- [x] Hardened the REST metadata fallback with paginated repo enumeration, authenticated/capped latest-release fetches, non-404 partial-data aborts, live fallback verification, and Pester coverage (v4.9.50). — *Source: ROADMAP.md*
- [x] Added an informational generated-README size budget report with UTF-8 byte count, a 96 KiB soft cap, schema coverage, and Pester warning checks (v4.9.51). — *Source: ROADMAP.md*

### Tests and reliability

- [x] Added a hermetic Pester v5 suite (`tests/`, 16 tests) plus a `tests.yml` CI job and a dot-source test seam. — *Source: TODO.md*
- [x] Added catalog-shape validation for duplicate repos, missing repo values, unknown categories, and unknown `downloadKind` values, with report/schema support and Pester coverage (v4.9.52). — *Source: ROADMAP.md*
- [x] Added repository settings/community-health fixture coverage for enabled/disabled live-shaped settings, missing required local intake files, and unavailable API state (v4.9.53). — *Source: ROADMAP.md*
- [x] Added workflow coverage for generated-PR validation dispatch permissions, branch-scoped validation links, summary text, and read-only check-job isolation (v4.9.54). — *Source: ROADMAP.md*
- [x] Added Pester coverage for project license export, missing/non-standard license reporting, report summary rows, and schema validation (v4.9.55). — *Source: ROADMAP.md*
- [x] Added Pester coverage for fork-parent drift matches, catalog continuations, missing catalog attribution, parent mismatches, unavailable parents, report schema validation, and summary rows (v4.9.56). — *Source: ROADMAP.md*
- [x] Added Pester coverage for profile release/tag consistency when the latest release is behind, the expected tag is missing, and the latest release/tag matches the planning version (v4.9.57). — *Source: ROADMAP.md*
- [x] Fixed a StrictMode bug where `Test-HttpUrl` dereferenced `$_.Exception.Response` on exceptions lacking it (DNS failures crashed `-Check`). — *Source: TODO.md*
- [x] Renamed the splat array shadowing `$args` in `Get-GitHubRepos`. — *Source: TODO.md*

### Discoverability and positioning

- [x] Add premium generated README navigation: a compact Start Here table, a Catalog Snapshot, action columns on featured/currently-building rows, stable category anchors, and per-category "Start with" previews. — *Source: ROADMAP.md*
- [x] Align the first-viewport profile narrative with LinkedIn positioning (hero descriptor, typing lines, bio copy, proof-point table) around healthcare IT, DICOM/PACS, 16+ years of IT operations, and 10+ production platforms, keeping private project and employer names out of the public profile. — *Source: ROADMAP.md*
- [x] Fix the first-viewport table layout by removing the HTML two-column wrapper that cramped the Proof Points and Currently Building tables, while keeping the generated Currently Building table marker intact. — *Source: ROADMAP.md*
- [x] Preserve the minimal public README header after the 2026-06-06 privacy edit, keeping profile sync and rendered smoke checks aligned with the compact portfolio-first layout instead of reintroducing removed personal-profile sections (v4.9.41). — *Source: remote README update; ROADMAP.md*
- [x] Feed `sysadmindoc.github.io` from the same catalog data by publishing a generated `projects.json` and keeping the README as the compact catalog. — *Source: ROADMAP.md*
- [x] Added the public-safe companion research plan `docs/research-feature-plan-2026-06-04.md`. — *Source: TODO.md*
- [x] Generated theme-aware profile chrome with dark/light image sources, a plain-text tagline, descriptive alt text, and validation coverage (v4.9.12). — *Source: ROADMAP.md*

## Stale / Obsolete Items

- [STALE] In-README search boxes and filter chips. — *Reason: GitHub sanitizes rendered README markup (script tags and inline styles), so interactive search/filtering cannot run in the profile README; it belongs in `sysadmindoc.github.io`. The profile README remains generated static Markdown. Source: ROADMAP.md*
