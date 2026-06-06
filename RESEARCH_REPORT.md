# Research Report

Consolidated from legacy research and feature-planning documents on 2026-06-03. This is the canonical research home for the profile-catalog system; planned work derived from it lives in `ROADMAP.md`. The dated source bundle was archived to `docs/archive/research-feature-plan-2026-06-04.md`.

Research refresh: 2026-06-06
Deep-research addenda: 2026-06-03 and 2026-06-04 (see addenda below)
Repository: SysAdminDoc/SysAdminDoc
Current version after this refresh: v4.9.57

## Verification Refresh — 2026-06-06

- The v4.9.57 batch closed the profile repository release/tag consistency gap by
  adding warning-only `profileReleaseConsistency` reporting beside
  `docVersionConsistency`.
- The current live report compares expected planning version `v4.9.57` against
  latest GitHub release `v3.0.0`, records the missing `v4.9.57` tag ref, and
  surfaces 2 warning-only release/tag rows.
- The sync-report schema, summary helper, and Pester suite now cover missing,
  behind, and matching release/tag states.
- The v4.9.56 batch closed the GitHub fork-parent drift reporting gap by adding
  live `isFork` collection, REST parent enrichment for GitHub forks, and a
  `forkParentDrift` sync-report section.
- The current live report records 8 GitHub forks, 7 catalog `forkOf` rows, 5
  matching GitHub forks, 2 catalog continuations/imports, 3 missing
  catalog-attribution warnings, and 0 parent mismatches.
- The sync-report schema, summary helper, and Pester suite now cover matching
  forks, catalog continuations, missing attribution, parent mismatches, and
  unavailable parent metadata.
- The v4.9.55 batch closed the per-project SPDX/license metadata gap by adding
  `licenseKey`, `licenseName`, and `licenseSpdxId` to visitor-facing
  `projects.json` rows.
- The sync report now includes `projectLicenseMetadata`; the current live report
  checks 177 visitor-facing rows, detects 174 project licenses, records 3
  missing-license rows, and records 9 non-standard GitHub `other` rows.
- The projects feed schema, sync-report schema, summary helper, and Pester suite
  now cover the new project-license fields and warning aggregates.
- The v4.9.54 batch closed the generated-profile PR validation handoff gap by
  explicitly dispatching `profile-sync.yml` in check mode on generated
  profile/assets PR branches.
- The PR-creating jobs now have scoped `actions: write` permission, while
  read-only check jobs remain `contents: read`; generated PR bodies and job
  summaries include branch-scoped validation-run links.
- Pester coverage guards the dispatch command, validation-run links, summary
  text, and permission isolation.
- The v4.9.53 batch closed the repository settings/community-health reporting
  gap by adding public-safe `repositorySettings` and `communityHealth` blocks to
  the sync report.
- Current live baseline data is available and records 4 repository-setting
  warnings, 3 community-health warnings, GitHub community health 71, and 0 fatal
  local required intake-file gaps.
- The summary helper now emits aggregate setting/community warning and fatal
  counts only; the report schema and Pester fixtures cover live-shaped disabled
  settings, missing local files, and unavailable metadata.
- The v4.9.52 batch closed the catalog JSON-shape validation gap by adding
  `Test-CatalogShape` plus `catalogShape` report output and `-Check` failure
  wiring.
- The guard catches missing repo names, duplicate repo keys, unknown categories,
  and unknown `downloadKind` values; the committed catalog currently passes with
  0 shape issues.
- The report schema validates the new `catalogShape` section, and Pester covers
  known-good and malformed catalog cases.
- The v4.9.51 batch closed the generated README size-budget gap by adding
  `readmeSizeBudget` to the sync report.
- The current generated README is 65,900 UTF-8 bytes against the 98,304-byte
  soft limit, with `overSoftLimit=false` and no warning.
- The report schema requires the new size-budget section, and Pester covers
  UTF-8 byte counting plus over-budget warning text.
- The v4.9.50 batch closed the REST release-fallback partial-data gap by using
  `gh api --paginate --slurp` for repo enumeration and enforcing authenticated,
  capped latest-release fetches.
- Release 404s are treated as expected no-release rows, while non-404 release
  fetch failures warn and abort so partial release metadata is not written
  silently.
- A forced REST fallback exercise returned 184 public repos and 147 inspected
  releases, and Pester covers paginated REST parsing, budget policy, and
  404/rate-limit classification.
- The v4.9.49 batch closed the header/non-catalog link-validation gap by adding
  generated README targets for the portfolio link and both `setup.ps1` raw/source
  links.
- External image URLs found in generated README image markup now use non-fatal
  link targets grouped under `linkValidationSummary.headerHostWarnings`; current
  compact output has 0 header-host warning groups.
- `schemas/profile-sync-report.v1.json` and validation-performance reporting now
  cover `headerHostWarnings` and `headerWarningHostCount`, and Pester proves
  profile/setup 404s fail while image-host 404s remain warnings.
- The v4.9.48 batch fixed rendered-profile smoke drift discovered during live
  post-push verification. The script now checks `Python Desktop Applications`
  and `Browser Extensions & Userscripts`, matching the current generated README.
- Focused Pester coverage now rejects the stale `Python Applications` smoke
  expectation, and live rendered-profile smoke passed for desktop and 390px
  mobile after the fix.
- The v4.9.47 batch closed the motion-safe profile chrome item by replacing
  generated capsule/typing motion with committed static header/footer SVG
  assets and local footer rendering in the compact README.
- `readmeExperienceChecks` now reports `motionSafeChrome`,
  `motionPatternCount`, `thirdPartyRenderHostCount`, and
  `thirdPartyRenderHosts`; the current report records `motionSafeChrome=true`,
  0 motion patterns, and 0 third-party render hosts.
- `schemas/profile-sync-report.v1.json` now requires the motion/render-host
  fields, and Pester coverage proves reintroduced `repeat=true`,
  `animation=`, or typing-SVG motion fails the README experience gate.
- Local verification passed for Pester 89/89, PSScriptAnalyzer, full profile
  sync/write/check, and whitespace diff checks.
- The v4.9.46 batch closed the CI validation-tool pinning item by replacing
  floating Pester and `zizmor` installs with exact reviewed versions.
- `.github/workflows/tests.yml` now installs Pester 5.7.1 with
  `Install-Module -RequiredVersion`, retaining the PSScriptAnalyzer 1.25.0 pin.
- `.github/workflows/workflow-security.yml` now installs `zizmor` 1.25.2 from
  `requirements-ci.txt` with PyPI distribution hashes, `--require-hashes`,
  `--only-binary :all:`, and `--no-deps`; `docs/ci-toolchain.md` documents the
  reviewed update process.
- Local verification passed for pip hash dry-run, Pester 88/88,
  PSScriptAnalyzer, full profile sync/write/check, and whitespace diff checks.
- The v4.9.45 batch closed the sync-report schema contract item by adding
  `schemas/profile-sync-report.v1.json`, a top-level report `schema` URL, and
  `schemaValidation.report`.
- `scripts/sync-profile.ps1 -Check` now validates the generated report against
  the report schema and fails when required report sections are missing or
  malformed. The first schema run caught and fixed single-value
  `releaseAssetDrift.sourceOnlyWithRelease.releaseAssetKinds` serialization.
- Local verification passed for Pester, PSScriptAnalyzer, and schema-gated
  generation; Pester now validates the committed report and a malformed report
  fixture.
- The v4.9.44 batch closed the release/download trust metadata item by adding
  `releaseTrust` to visitor-facing `projects.json` rows and requiring it in the
  project-feed schema. The object records filename-derived checksum, signature,
  SBOM, attestation, debug-artifact, source-only, executable-kind, trust-level,
  and public-note fields.
- `reports/profile-sync-report.json.releaseAssetDrift` now reports trust-level
  counts, executable download rows missing complete checksum coverage, and debug
  artifact rows. The latest run reports 23 checksum-classified rows, 118
  metadata-only rows, 36 unknown rows, 55 checksum-coverage gaps, and 3 debug
  artifact rows.
- Local verification passed for Pester, PSScriptAnalyzer, and
  `scripts/sync-profile.ps1 -Write -Check`; Pester coverage now includes trust
  classification, checksum sidecars, source-only releases, schema validation,
  and checksum-gap reporting.
- The v4.9.43 batch closed the generated-feed provenance backlog by adding a
  public-safe `projects.json.provenance` object with source repository,
  generation-base commit, catalog/generator/schema SHA-256 hashes,
  `metadataSnapshotAt`, `metadataProvider`, and repository enumeration status.
- `reports/profile-sync-report.json` now mirrors the feed provenance; stable
  provenance mismatches are fatal drift, while `sourceCommit` and
  `metadataSnapshotAt` are informational because committed files cannot embed
  the hash of the commit that contains themselves.
- Local verification passed for Pester, PSScriptAnalyzer, and
  `scripts/sync-profile.ps1 -Write -Check`; the latest provenance reports
  `metadataProvider=graphql`, `returnedCount=184`, `requestedLimit=500`, and
  `truncated=false`.
- The v4.9.42 batch closed the public suppressed-feed row leak by replacing
  full `projects.json.suppressed` project rows with redacted suppression records
  that carry only `suppressedId`, `suppressed`, `category`, `reasonCode`,
  `publicReason`, and `visibilityClass`.
- The projects feed schema now validates suppressed rows through a dedicated
  `suppressedProject` object, and offline Pester coverage rejects any suppressed
  feed row that exposes `repo`, `repoUrl`, `description`, `primaryAction`,
  `releaseAssetNames`, or known private/sensitive identifiers.
- Local verification passed for Pester, PSScriptAnalyzer, and
  `scripts/sync-profile.ps1 -Write -Check`; the latest report records
  `projectsExportInSync=true`, `schemaValidation.passed=true`, 177 public
  portfolio projects, and 10 redacted suppressions.
- The v4.9.41 batch closed the Windows PowerShell setup parser failure found in
  Cycle 33/Cycle 36 by replacing typographic punctuation in `setup.ps1` with
  ASCII hyphens and adding a Pester guard that rejects future non-ASCII bytes in
  the public bootstrapper.
- The Tests workflow now includes an always-created `Windows setup smoke` job on
  `windows-latest` that uses `shell: powershell` to parse `setup.ps1` with
  `System.Management.Automation.Language.Parser.ParseFile()` and run
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -CheckOnly`.
- The profile generator and rendered smoke check now preserve the compact
  portfolio-first README header from the latest remote privacy edit instead of
  regenerating the removed personal-profile chrome, Start Here, Catalog
  Snapshot, or Currently Building sections.
- Local verification passed for Windows PowerShell `5.1.26100.7920`
  `setup.ps1 -CheckOnly`, `pwsh -NoProfile -File .\setup.ps1 -CheckOnly`,
  PSScriptAnalyzer, and the offline Pester suite.

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
- The v4.9.16 batch closed the active P1 portfolio Pagefind item as already
  implemented in `C:\Users\--\repos\sysadmindoc.github.io`: `/search/` uses
  Pagefind Component UI, project pages expose Category filter and Type metadata,
  no-JS fallback links exist, and `npm run build` passed with Pagefind v1.5.2
  indexing 198 HTML pages, 18,774 words, and 1 filter into `dist/pagefind`.
- The v4.9.17 batch closed the active P1 portfolio freshness/download views item
  by implementing URL-backed All/New/Recently updated/Has download catalog views
  in `sysadmindoc.github.io` commit `29c2b1d`. Portfolio `npm run check`,
  `npm run build`, `npm test`, and focused Chrome CDP browser checks passed,
  including 181 all / 147 new / 173 recent / 20 download results and no mobile
  horizontal overflow at 390 px.
- The v4.9.18 batch closed the active P1 portfolio live-feed item by adding
  `profile-feed:sync` and `src/data/portfolio.ts` in `sysadmindoc.github.io`
  commit `9117f45`. The portfolio now renders catalog/project routes, command
  palette data, feeds, language lanes, timeline, OG routes, and JSON indexes
  from the public `projects.json` profile feed, excludes suppressed/non-portfolio
  rows, and preserves local curated overlays/fallbacks. Portfolio `npm run
  check`, `npm run build`, `npm test`, `rtk git diff --check`, build-output
  assertions, and focused Chrome CDP browser checks passed.
- The v4.9.19 batch closed the active P1 dangling feed-contract item by adding
  committed JSON Schema 2020-12 files under `schemas/`, repointing catalog/feed
  `schema` fields to raw GitHub URLs, adding schema validation to
  `Test-ProfileState`, recording `schemaValidation` in the sync report, and
  serializing release asset/topic fields as arrays. Pester passed 35/35 and full
  `scripts/sync-profile.ps1 -Write -Check` passed after REST fallback from a
  transient GitHub GraphQL 502.
- The v4.9.20 batch closed the active P1 planning-doc version/date consistency
  gate by adding `Test-DocVersionConsistency`, recording
  `docVersionConsistency` in the sync report, failing `-Check` on planning-doc
  version mismatches or stale sync dates, and adding Pester coverage for the
  passing, mismatched-version, and stale-date cases. Pester passed 38/38 and
  `scripts/sync-profile.ps1 -Write -Check` passed with
  `docVersionConsistency.passed=true`, `projectsExportInSync=true`, 0 metadata
  drift rows, 0 link failures, and 0 link warnings after REST fallback from a
  transient GitHub GraphQL 502.
- The v4.9.21 batch closed the active P2 setup bootstrapper hardening item by
  adding `#Requires -Version 5.1`, `-CheckOnly` diagnostics, best-effort
  `%TEMP%` transcript logging, generated inspect-before-install README guidance,
  and `readmeExperienceChecks.setupInspectPath`. Pester passed 42/42,
  `setup.ps1 -CheckOnly` reported local prerequisite state without installing,
  and `scripts/sync-profile.ps1 -Write -Check` passed with
  `setupInspectPath=true`, `projectsExportInSync=true`, 0 metadata drift rows, 0
  link failures, and 0 link warnings after REST fallback from a transient GitHub
  GraphQL 502.
- The v4.9.22 batch closed the active P3 WolfPack catalog hygiene item by
  moving WolfPack and Vigil into Native Desktop Applications so the
  privacy/browser packaging entries render together. Security & Networking now
  has 3 repos, Native Desktop Applications has 19 repos, and Misc & Forks has 5
  repos. `scripts/sync-profile.ps1 -Write -Check` passed with
  `readmeInSync=true`, `projectsExportInSync=true`,
  `docVersionConsistency.passed=true`, 0 metadata drift rows, 0 link failures,
  and 0 link warnings.
- The v4.9.23 batch closed the active P3 fork/continuation attribution item by
  adding structured `forkOf` and `upstreamLicense` catalog fields, generated
  `forkOf`, `forkOfUrl`, and `upstreamLicense` feed fields, and README
  upstream/license rendering for featured, category, and currently-building
  rows. AppManagerNG, uBlockVanced, LTSC-MicrosoftStore, RcloneBrowser,
  TabExplorer, Vigil, and TagStudio now carry explicit attribution metadata.
  Pester passed 44/44 and `scripts/sync-profile.ps1 -Write -Check` passed with
  `schemaValidation.passed=true`, `projectsExportInSync=true`, 0 metadata drift
  rows, 0 link failures, and 0 link warnings after REST fallback from a
  transient GitHub GraphQL 502.
- The v4.9.24 batch closed the active P3 "Forge" naming-debt log item without
  renaming live repositories. `ROADMAP.md` now records WinForge, FirewallForge,
  NetForge, PathForge, GitForge, ImageForge, ClipForge, IconForge, and
  MediaForge as retained live names to avoid breaking links, releases, stars,
  and install snippets, while new repository names should avoid the pattern.
  `scripts/sync-profile.ps1 -Write -Check` passed with
  `docVersionConsistency.passed=true`, `projectsExportInSync=true`, 0 metadata
  drift rows, 0 link failures, and 0 link warnings after REST fallback from a
  transient GitHub GraphQL 502.
- The v4.9.25 batch closed the active P1 PowerShell static-analysis item by
  adding `PSScriptAnalyzerSettings.psd1`, wiring pinned PSScriptAnalyzer 1.25.0
  into `.github/workflows/tests.yml`, and fixing the generator findings around
  automatic `$error` usage, unused values, and implicit `-SkipLinkValidation`
  state. The curated analyzer run reports 0 findings locally, Pester passed
  44/44, and `scripts/sync-profile.ps1 -Write -Check` passed with
  `docVersionConsistency.passed=true`, `projectsExportInSync=true`, 0 metadata
  drift rows, 185 link targets checked, 0 link failures, and 0 link warnings.
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
2. P1 - Add direct Pester coverage for the safety-critical `Test-ProfileState`, `Update-Header`, and medical-gate paths.
3. P1 - Redact private suppression rows from the public `projects.json` feed.
4. P1 - Add generated Markdown/text safety and URL-scheme validation for README/feed output.
5. P1 - Apply reviewed topic cleanup from the non-mutating report; live metadata still shows 69 active public repos with no topics and 0 public repos with empty descriptions.
6. P2 - Extend link validation to the hero/header and non-catalog URLs.
7. P2 - Add `actionlint` beside `zizmor` for workflow syntax/expression linting.
8. P2 - Add release/download trust metadata for EXE/APK/ZIP visitor-facing rows. [Completed v4.9.44]
9. P2 - Add userscript install trust metadata for raw `.user.js` actions.
10. P2 - Pin and audit CI-installed validation tools such as `zizmor` and Pester.
11. P2 - Add a reduced-motion/static generated profile chrome guard.
12. P2 - Add a generated profile PR validation handoff for automation-created branches. [Completed v4.9.54]
13. P2 - Add report artifact and summary parity to the profile-assets refresh workflow.
14. P2 - Expand CODEOWNERS coverage for profile-contract files.
15. P2 - Export per-project SPDX/license metadata in the generated feed and report. [Completed v4.9.55]
16. P2 - Report GitHub fork-parent drift against catalog attribution. [Completed v4.9.56]
17. P2 - Add a public-repo enumeration limit guard.
18. P2 - Publish a JSON Schema for `profile-sync-report.json`. [Completed v4.9.45]
19. P2 - Add a `.gitattributes` generated-artifact diff policy for feed/report/SVG churn.
20. P2 - Add a profile-repo release/tag consistency check for tracked `v4.9.x` versions. [Completed v4.9.57]
21. P2 - Add a live GitHub-rendered profile smoke check.
22. P3 - Add a stale-project and archive-review report derived from `pushedAt`, latest releases, and suppression reasons.
23. P3 - Add `.editorconfig` and generated README markdown linting.
24. P3 - Validate all historical `CHANGELOG.md` release headings.
25. P3 - Enable auto-delete or scoped cleanup for generated automation PR branches.
26. P3 - Centralize generated profile PR creation logic shared by profile-sync and asset-refresh workflows.
27. P3 - Cover future local GitHub actions under workflow-security triggers and ownership.
28. P3 - Stagger same-minute scheduled maintenance workflows.
29. P3 - Include schema-contract changes in the offline Tests workflow.
30. P3 - Group routine Dependabot GitHub Actions version updates.
31. P2 - Report catalog rows omitted from both public feed arrays.
32. P3 - Guard unsupported JSON Schema keywords in the custom validator.
33. P3 - Add internal title/description metadata to generated profile SVG panels.
34. P3 - Refresh stale catalog field names in completed-work docs.

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
- Current maturity: useful and trust-oriented after v4.9.21 added `-CheckOnly`, transcript logging, and inspect-before-install README guidance.
- Improvement opportunities: optional signing/checksum publication if the user wants a deeper trust model for remote execution.

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
- `setup.ps1` uses remote execution through the README one-liner; the generated README now also exposes a save/review/`-CheckOnly` path before installation.

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
- Keep the setup inspect/check-only path in the generated README when editing first-time setup copy.
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

A line-by-line read of `scripts/sync-profile.ps1` (1,495 lines), the four workflows, the Pester suite, and `setup.ps1`, plus live verification, surfaced net-new gaps that sit outside the existing roadmap. The public feed's dangling JSON Schema URLs were closed in v4.9.19, and the planning-doc version/date consistency gate was closed in v4.9.20. Remaining automated-guard gaps include raw userscript trust metadata; the previously identified hero-link validation, REST release-fallback, generated-README size-budget, catalog-shape validation, and repository/community-health reporting gaps are now closed.

Top addendum opportunities (one line each):

1. P1 — The `schema` URLs in catalog and `projects.json` are 404; publish them or repoint, then validate the feed. [Closed v4.9.19]
2. P1 — No automated version/date consistency gate across ROADMAP/CHANGELOG/PROJECT_CONTEXT. [Closed v4.9.20]
3. P1 — `Test-ProfileState` (the private/medical/visibility gate) has zero direct Pester coverage. [Verified]
4. P2 — Link validation never probes the hero/portfolio/image-host URLs. [Verified]
5. P2 — REST release-fallback is an unbounded per-repo N+1 (~184 calls) with no rate-limit awareness. [Verified]
6. P2 — No catalog JSON-shape validation; unknown `downloadKind` silently defaults. [Closed v4.9.52]
7. P2 — No generated-README size budget (file is ~72 KB and grows unbounded). [Closed v4.9.51]
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

- **Major — Dangling feed contract.** `projects.json`/catalog advertise `schema` URLs that 404. Consumers following the contract get a dead link; the feed shape is unenforceable. → roadmap "Publish (or stop referencing) the JSON Schema URLs". `scripts/sync-profile.ps1:1086,1264`. [Closed v4.9.19]
- **Major — Unguarded planning-doc version drift.** Version/date are hand-typed in three tracked docs with no check; the existing alignment item is manual only. → "self-contained version/date consistency gate". [Closed v4.9.20]
- **Major — Privacy gate is untested.** `Test-ProfileState` (private-visibility + medical-keyword + drift) has no direct unit test; only the regex string is tested. A regression in the gate that keeps private/medical repos off the public profile would pass CI. → "Cover the safety-critical functions". `scripts/sync-profile.ps1:1324-1442`, `tests/sync-profile.Tests.ps1`. [Verified]
- **Minor — Hero links unvalidated.** The link gate used to iterate only catalog entries, so the portfolio link, the `setup.ps1` blob link, and third-party image hosts were not probed. → "Extend link validation to hero/header". [Closed v4.9.49]
- **Minor — REST fallback N+1.** Per-repo `gh api releases/latest` in the fallback used to run without authentication/budget policy or partial-data aborts. → "Cap and authenticate the REST release-fallback". [Closed v4.9.50]
- **Minor — Silent unknown-kind fallthrough.** `Get-DownloadLabel` `default { "Download" }` used to swallow an unrecognized `downloadKind`; catalog-shape validation now catches the typo. → "Add catalog JSON-shape validation". [Closed v4.9.52]
- **Minor — No size budget.** ~72 KB generated README had no growth guard; GitHub truncates long profile READMEs. → "generated-README size budget guard". [Closed v4.9.51]
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
4. P2 — Report repository settings and community-health status alongside generated-profile checks. [Closed v4.9.53]
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
- **Minor — GitHub-hosted settings are invisible to `-Check`.** Secret scanning and push protection are currently enabled, but this trust state is not captured in the sync report and can drift independently of tracked files. Community-health status is also absent from the report. → roadmap "Add a read-only repository settings and community-health baseline". [Closed v4.9.53]
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

## Cycle 7 Research Addendum — 2026-06-04

This pass widened from the existing profile-sync queue into generated Markdown
rendering safety, workflow lint coverage, Windows runtime verification for the
setup bootstrapper, and release/download trust metadata. It intentionally did
not add another visual profile-widget item: current competitor research shows
that many profile generators lean on dynamic cards, visitors counters, live
previews, and external stats services, while this repo's current philosophy is
stronger as a committed-assets, public-safe, evidence-backed catalog surface.

### Evidence reviewed (cycle 7)

- Local generator paths: `Get-DisplayDescription` and downstream README/feed
  renderers insert repo titles, descriptions, upstream attribution, and live
  metadata into Markdown table/link contexts (`scripts/sync-profile.ps1:467`,
  `:1221`, `:1243`, `:1313`, `:1683`).
- Local workflow security path: `.github/workflows/workflow-security.yml:21-36`
  installs and runs `zizmor`, with no `actionlint` or equivalent workflow
  syntax/expression checker.
- Local setup path: `README.md:118-130` advertises the one-paste setup and
  inspect-before-install `-CheckOnly` command; `tests/sync-profile.Tests.ps1:345-357`
  only inspects `setup.ps1` source text rather than executing the check-only
  path.
- Local release/download evidence: `reports/profile-sync-report.json:846-864`
  reports 71 release-action rows and classifies APK/EXE/ZIP-like asset kinds,
  but does not yet record checksum, signature, attestation, SBOM, or explicit
  unverified status.
- Live repository evidence: `gh pr list --repo SysAdminDoc/SysAdminDoc` still
  shows Dependabot workflow-action PRs #5 and #6, which remains covered by the
  existing Dependabot triage item instead of a new duplicate.
- Competitor/analogous OSS reviewed through GitHub search/API on 2026-06-04:
  `rahuldkjain/github-profile-readme-generator` (~24.2k stars, TypeScript,
  updated 2026-06-04), `Open-Dev-Society/openreadme` (auto-updating bento image
  generator, updated 2026-06-02), `anuraghazra/github-readme-stats` (~79.5k
  stars, dynamic stats cards, updated 2026-06-04), `stats-organization/github-readme-stats-action`
  (GitHub Action for generated stats cards), `abhisheknaiidu/awesome-github-profile-readme`
  (~30.1k stars, curated profile list), and `durgeshsamariya/awesome-github-profile-readme-templates`
  (~5.2k stars, template catalog).
- Official and primary sources reviewed:
  GitHub profile README docs: https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
  GitHub secure-use guidance for full-length SHA pinning and Dependabot action
  updates: https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions
  GitHub script-injection docs: https://docs.github.com/en/actions/concepts/security/script-injections
  GitHub-hosted Windows runner docs: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
  GitHub artifact attestation docs: https://docs.github.com/en/actions/how-tos/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
  GFM spec: https://github.github.com/gfm/
  Unicode UTS #39: https://www.unicode.org/reports/tr39/
  `actionlint` README: https://github.com/rhysd/actionlint
  OpenSSF Scorecard docs/repo: https://github.com/ossf/scorecard

### Harvested opportunities (cycle 7)

- **Markdown/text safety gate** — verify generated public text by Markdown
  context, not only JSON shape. This is a fit because the repo renders many
  third-party/live metadata strings into GitHub Markdown and already has a
  privacy/medical gate for public-surface trust.
- **Workflow linting with `actionlint`** — add a syntax/expression/run-step
  lint gate beside `zizmor`. This is a fit because workflow security is already
  a first-class repo concern and `zizmor` does not replace workflow-language
  linting.
- **Windows setup smoke check** — execute `setup.ps1 -CheckOnly` on
  `windows-latest` for setup-related PRs. This is a fit because the setup path
  is explicitly for novice Windows users and current tests are source-only.
- **Release/download trust metadata** — classify release-action rows by
  checksum/signature/attestation/SBOM/unverified status. This is a fit because
  the README routes visitors to many executable downloads and the report already
  owns release asset taxonomy.
- **Generated card/live preview expansion** — rejected for now. Competitors
  emphasize it, but SysAdminDoc already has committed local SVG panels and a
  separate searchable portfolio; more external dynamic cards would undermine
  the current trust/privacy direction.

### Findings (cycle 7)

- **Major — Generated Markdown has no content-safety layer beyond shape and
  privacy checks.** JSON Schema catches field shape, and the medical/private
  gate catches sensitive categories, but generated Markdown still relies on
  raw titles/descriptions being benign in table/link contexts. → roadmap "Add
  generated Markdown/text safety and URL-scheme validation". [Verified]
- **Minor — Workflow security lacks a workflow-language lint companion.**
  `zizmor` is present and valuable, but the workflow has no `actionlint` pass
  for syntax, expression, action-input, dependency, cron, and inline-script
  mistakes. → roadmap "Add `actionlint` beside `zizmor`". [Verified]
- **Minor — `setup.ps1 -CheckOnly` is advertised but not runtime-smoked on
  Windows CI.** Pester checks source strings and README output, but not the
  check-only runtime path users are told to execute. → roadmap "Add a Windows
  runner smoke check for `setup.ps1 -CheckOnly`". [Verified]
- **Major — Download trust was classified by asset kind, not by verifiable
  release evidence.** The report distinguishes EXE/APK/ZIP/source-only rows,
  but not whether visitor-facing binaries have checksums, signatures,
  attestations, SBOMs, or a documented unverified status. → roadmap "Add
  release/download trust metadata for visitor-facing binary rows". [Completed v4.9.44]

### Standards notes (cycle 7)

- Treat generated Markdown safety as a reportable gate, not a cosmetic linter:
  some characters should be escaped by context, while bidi/control characters
  and unknown URL schemes should fail validation before the README/feed is
  written.
- Keep `actionlint` and `zizmor` complementary: `zizmor` remains the security
  audit lane; `actionlint` covers workflow-language correctness and common
  injection-prone constructs.
- Keep the Windows setup smoke job path-filtered. It should run when setup docs
  or `setup.ps1` change, not on every unrelated catalog-only edit.
- Start release trust as report-only warnings. Making missing signatures or
  attestations fatal across dozens of historical repos would block useful
  catalog maintenance before the build machine has had a chance to add evidence
  to the highest-risk download rows.

## Cycle 8 Research Addendum — 2026-06-04

This pass focused on CI dependency/toolchain drift rather than another product
surface. The repo already pins third-party GitHub Actions by SHA and has a
Dependabot GitHub Actions update queue, but the validation tools installed from
PyPI and PowerShell Gallery are still floating.

### Evidence reviewed (cycle 8)

- `.github/workflows/workflow-security.yml:32-36` installs `zizmor` with
  `python -m pip install --upgrade zizmor`, so the workflow always takes the
  latest available PyPI release at run time.
- `.github/workflows/tests.yml:39-45` sets PSGallery as trusted and installs
  Pester with `Install-Module Pester -MinimumVersion 5.5.0 -Force -Scope
  CurrentUser`, so any compatible newer Pester release can change test-runner
  behavior without a reviewed repository diff.
- `rg` found no `requirements*.txt`, `pyproject.toml`, lock file,
  `PSScriptAnalyzerSettings.psd1`, or CI tool-version manifest in the repo.
- The current open Dependabot PRs cover GitHub Actions references, not
  registry-installed runtime tools such as PyPI packages or PowerShell modules.
- pip's repeatable-installs documentation recommends exact `==` pins for
  dependencies and describes hash-checking as a stricter automated-install
  option: https://pip.pypa.io/en/stable/topics/repeatable-installs/
- pip's secure-installs documentation says default pip installs do not protect
  against remote tampering and describes `--require-hashes` plus pinned
  requirements as the stricter mode: https://pip.pypa.io/en/stable/topics/secure-installs/
- Microsoft documents `Install-Module` version filters, including exact
  `-RequiredVersion`, for installing a specific module version:
  https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module
- OpenSSF Scorecard's Pinned-Dependencies check treats unpinned build/release
  dependencies as medium risk and recommends explicit versions/lock files plus
  update tooling: https://github.com/ossf/scorecard/blob/main/docs/checks.md#pinned-dependencies

### Finding (cycle 8)

- **Minor — CI validation tools are installed from floating registry versions.**
  The repository has good SHA pinning for workflow actions, but `zizmor` and
  Pester can still change under the same commit because they are installed from
  live registries without exact pins or a lock/update process. → roadmap "Pin
  and audit CI-installed validation tools". [Verified]

### Standards note (cycle 8)

- Keep this separate from Dependabot action triage. Action SHA updates and
  package/module tool updates are different supply-chain channels and should
  have different review paths.
- Prefer exact pins first, then hashes where the package manager makes them
  practical. A small documented update checklist is better than an unpinned
  "latest" install that silently changes behavior.

## Cycle 9 Research Addendum — 2026-06-04

This pass focused on accessibility and motion in the generated profile chrome.
The v4.9.12 and v4.9.15 batches already improved theme-aware image chrome,
plain-text tagline content, image alt text, and third-party render-host
reduction. The remaining gap is auto-starting visual motion in the hero and
typing line.

### Evidence reviewed (cycle 9)

- `scripts/sync-profile.ps1:1469-1472` generates the profile header through
  `capsule-render` URLs containing `animation=fadeIn` and the focus line
  through `readme-typing-svg` URLs containing `repeat=true`.
- `README.md:2` renders the generated animated capsule header in the public
  profile README.
- `README.md:11` renders the generated looping typing SVG in the public
  profile README.
- GitHub README embeds do not provide an in-page pause/stop/hide control for
  third-party image animation.
- W3C WCAG 2.2.2 says moving, blinking, or scrolling content that starts
  automatically, lasts more than five seconds, and appears alongside other
  content needs a pause, stop, or hide mechanism unless the movement is
  essential: https://www.w3.org/WAI/WCAG20/Understanding/pause-stop-hide.html
- MDN documents `prefers-reduced-motion` as the user preference for reducing
  non-essential motion:
  https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-reduced-motion
- `readme-typing-svg` documents `repeat` defaulting to `true`:
  https://github.com/DenverCoder1/readme-typing-svg

### Finding (cycle 9)

- **Minor — profile chrome still auto-starts motion without a pause control.**
  The profile README now has better theme and alt-text behavior, but the
  generated capsule and typing SVG can still animate automatically in a context
  where the repository cannot supply an accessible pause/stop/hide control. →
  roadmap "Add a reduced-motion/static profile chrome guard". [Verified]

### Standards note (cycle 9)

- Prefer static committed SVG or text for the hero and focus-line chrome. If the
  build machine keeps any animated renderer, the validation gate should fail on
  looping or long-running motion parameters such as `repeat=true` or
  `animation=` unless there is a documented accessible fallback.
- Keep this separate from third-party host privacy and link-validation work:
  those items answer where images come from and whether URLs stay alive; this
  item answers whether generated chrome respects motion-sensitive users.

## Cycle 10 Research Addendum — 2026-06-04

This pass focused on generated PR workflow semantics. It does not replace the
existing pull-request profile-sync check or branch-protection items; it covers
the handoff case where a workflow itself creates the branch and PR that should
then receive validation.

### Evidence reviewed (cycle 10)

- `.github/workflows/profile-sync.yml:67-101` sets `GH_TOKEN` to
  `${{ github.token }}`, creates an `automation/profile-sync-*` branch, pushes
  it with an x-access-token remote, and opens a PR with `gh pr create`.
- `.github/workflows/assets-refresh.yml:31-62` uses the same default
  `${{ github.token }}` pattern for `automation/profile-assets-*` PRs.
- Both write paths correctly scope job permissions to `contents: write` and
  `pull-requests: write`, and both checkout steps set `persist-credentials:
  false`; the risk is not overbroad checkout credential persistence.
- GitHub's workflow-trigger documentation says `GITHUB_TOKEN`-created
  `pull_request` events for opened, synchronize, or reopened can create
  workflow runs in an approval-required state, while other events such as push
  do not create new workflow runs. The same page says a GitHub App installation
  access token or PAT can be used when automation-created PRs should run
  validation automatically:
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow
- GitHub's `GITHUB_TOKEN` authentication docs recommend least-required token
  permissions and describe GitHub App/PAT tokens when additional permissions or
  behavior are needed:
  https://docs.github.com/en/actions/tutorials/authenticate-with-github_token
- The open roadmap already contains "Run profile-sync validation on
  profile/catalog pull requests" and "Require validation status checks on
  main"; this finding is the missing generated-PR trigger path those items will
  depend on.

### Finding (cycle 10)

- **Minor — generated profile PR validation may require manual approval or miss
  push-only checks.** The manual/scheduled generated-PR jobs use `github.token`
  to create the branch and pull request. Current GitHub behavior can create
  approval-required `pull_request` runs for those PRs, but push-triggered
  workflows remain suppressed. Unless the build machine chooses a
  least-privilege GitHub App/PAT token, dispatches validation explicitly, or
  documents the approval-required path, generated PRs can lack unattended
  validation evidence when branch policy starts requiring checks. → roadmap
  "Add a validation handoff for generated profile PRs". [Closed v4.9.54]

### Standards note (cycle 10)

- Treat token choice as part of the generated-PR contract, not as a generic
  hardening cleanup. The current workflows already use narrow permissions and
  disable checkout credential persistence; the missing control is proof that
  generated PRs receive the same validation evidence as human-authored PRs.
- Prefer a GitHub App installation token over a broad PAT if this repo gets a
  durable automation identity. If secrets are not desired, document the
  approval-required path or add an explicit `workflow_dispatch` /
  `repository_dispatch` handoff so generated PR validation evidence is visible.

## Cycle 11 Research Addendum — 2026-06-04

This pass focused on observability parity for the committed profile-assets
refresh workflow. The existing profile-sync job-summary item still applies to
the main profile-sync workflow; this pass covers the separate workflow that
refreshes committed SVG assets and also runs the generator/report path.

### Evidence reviewed (cycle 11)

- `.github/workflows/assets-refresh.yml:28-62` runs
  `./scripts/sync-profile.ps1 -Write -Check`, stages
  `reports/profile-sync-report.json`, and opens a generated PR when files
  change.
- `rg` found no `actions/upload-artifact`, `retention-days`,
  `GITHUB_STEP_SUMMARY`, `::warning`, or `::error` usage in
  `.github/workflows/assets-refresh.yml`.
- `.github/workflows/profile-sync.yml:37-49` runs
  `./scripts/sync-profile.ps1 -Check` and uploads
  `reports/profile-sync-report.json` as the `profile-sync-report` artifact.
- The existing roadmap already has "Profile-sync Actions job summary from
  reports/profile-sync-report.json"; this finding is about the asset-refresh
  workflow being outside that named coverage.
- GitHub artifact docs describe uploading workflow outputs for debugging and
  custom `retention-days`:
  https://docs.github.com/en/actions/tutorials/store-and-share-data
- GitHub workflow-command docs describe job summaries and warning/error
  annotations:
  https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions

### Finding (cycle 11)

- **Minor — profile-assets refresh lacks structured run evidence when it is
  no-op or fails before PR creation.** The workflow runs the same generator and
  report-producing check as profile-sync, but it only commits the report when a
  PR is created. No-op scheduled runs and failures leave maintainers with logs
  instead of the structured `profile-sync-report.json`, report retention, and
  high-signal summary fields. → roadmap "Add report artifact and summary parity
  to profile-assets refresh". [Verified]

### Standards note (cycle 11)

- Keep summaries aggregate-first and public-safe, matching the profile-sync
  summary work: sync status, profile asset check counts, fatal drift totals,
  link warnings by host, and duration are useful; private/suppressed repo names
  should not be printed into run summaries.
- Prefer a shared report-summary helper if the build machine implements both
  the profile-sync and asset-refresh observability items together, so future
  report fields are not summarized differently by workflow.

## Cycle 12 Research Addendum — 2026-06-04

This pass focused on CODEOWNERS coverage as a prerequisite for the queued
branch-protection/ruleset work. The repo already has a CODEOWNERS file; the gap
is that several public-contract paths sit outside its patterns.

### Evidence reviewed (cycle 12)

- `.github/CODEOWNERS:1-7` covers `.github/workflows/`,
  `scripts/sync-profile.ps1`, `tests/`, `data/profile-catalog.json`,
  `projects.json`, and `reports/profile-sync-report.json`.
- Root listing shows additional profile-contract files outside those patterns:
  `README.md`, `ROADMAP.md`, `RESEARCH_REPORT.md`, `CHANGELOG.md`,
  `COMPLETED.md`, `PROJECT_CONTEXT.md`, `schemas/`, `assets/`, and `setup.ps1`.
- The current roadmap already has branch-protection/ruleset work, PR
  profile-sync validation, generated PR validation handoff, and CODEOWNERS in
  the repository-security context; this finding is specifically about the owner
  pattern map being incomplete before code-owner review is required.
- GitHub CODEOWNERS docs say matching owners receive review requests and branch
  protection can require review from code owners:
  https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
- GitHub REST docs describe the CODEOWNERS errors endpoint for checking syntax
  and owner validity:
  https://docs.github.com/en/rest/repos/repos#list-codeowners-errors

### Finding (cycle 12)

- **Minor — CODEOWNERS omits several generated/public-contract files.** The
  current file owns the generator, workflows, tests, catalog, feed, and report,
  but not the generated README, schemas, profile assets, setup script, or public
  planning docs. If code-owner review becomes part of branch protection, those
  changes can miss automatic owner review routing. → roadmap "Expand CODEOWNERS
  coverage for profile-contract files". [Verified]

### Standards note (cycle 12)

- Keep this as coverage alignment, not as a new review bureaucracy. With a
  single-owner account, the main value is making critical profile-contract paths
  visible to GitHub's owner-routing and future branch/ruleset policy.
- Validate CODEOWNERS after changes through GitHub's errors endpoint; a typo in
  an owner or pattern can silently weaken the coverage that branch protection is
  expected to enforce.

## Cycle 13 Research Addendum — 2026-06-04

This pass focused on project license metadata in the generated feed and report.
The v4.9.23 fork/continuation work added upstream origin and upstream-license
fields; this item is separate because it records each SysAdminDoc repository's
own detected license.

### Evidence reviewed (cycle 13)

- `gh repo view SysAdminDoc/Network_Security_Auditor --json licenseInfo`
  returns `MIT License` with key `mit`, proving GitHub already exposes the
  repository's own license metadata for at least one visitor-facing project.
- `scripts/sync-profile.ps1:210-213` requests live repo fields from `gh repo
  list` without `licenseInfo`.
- The REST fallback metadata shape in `scripts/sync-profile.ps1:187-196`
  includes stars, default branch, latest release, visibility, archived/private
  flags, pushed date, URL, and primary language, but no license field.
- `New-ProjectsExportJson` emits `forkOf`, `forkOfUrl`, and
  `upstreamLicense`, plus language/stars/release/topic fields; current
  `projects.json` rows include no `licenseKey`, `licenseName`, or
  `licenseSpdxId` field for the project itself.
- `schemas/profile-projects.v1.json` defines upstream/fork fields but no
  project license fields.
- GitHub's license REST docs expose detected license `key`, `name`, and
  `spdx_id`: https://docs.github.com/rest/reference/licenses
- The SPDX License List provides stable license identifiers:
  https://spdx.org/licenses/

### Finding (cycle 13)

- **Minor — generated project rows omitted the repository's own license metadata.**
  The feed is already rich enough for portfolio search, release availability,
  and fork/upstream attribution, but consumers still cannot tell whether a
  project is MIT, GPL, unlicensed, or unknown without another GitHub query. →
  roadmap "Export per-project SPDX/license metadata in the feed". [Closed v4.9.55]

### Standards note (cycle 13)

- Keep upstream license and project license distinct. `upstreamLicense` answers
  "what was the inherited origin license for a fork/continuation"; generated
  `licenseKey`/`licenseName`/`licenseSpdxId` would answer "what license does
  this SysAdminDoc repository currently advertise."
- Start as feed/report metadata. README license labels can be added only if the
  build machine finds a compact presentation that does not make the profile
  tables too wide.

## Cycle 14 Research Addendum — 2026-06-04

This pass focused on live GitHub fork-parent metadata versus the manual
fork/continuation attribution already shipped in v4.9.23.

### Evidence reviewed (cycle 14)

- `gh repo list SysAdminDoc --json isFork,parent` exposes fork status but, in the
  current CLI shape, returned null parent details for fork rows.
- `gh api repos/SysAdminDoc/RcloneBrowser --jq .parent.full_name` reports
  `kapitainsky/RcloneBrowser`, matching the catalog `forkOf` entry and upstream
  MIT attribution.
- `gh api repos/SysAdminDoc/uBlockVanced` reports `fork=false` with no GitHub
  parent, while the catalog intentionally records `forkOf=gorhill/uBlock` and
  `upstreamLicense=GPL-3.0`.
- `scripts/sync-profile.ps1:210-213` requests `gh repo list` fields without
  `isFork` or parent enrichment.
- The REST fallback metadata shape at `scripts/sync-profile.ps1:187-196`
  includes stars, default branch, latest release, visibility, archive/private
  status, pushed date, URL, and primary language, but no fork-parent metadata.
- `projects.json` currently exports manual `forkOf`, `forkOfUrl`, and
  `upstreamLicense` fields, but no live `isFork`, GitHub parent, or
  attribution-kind field.
- GitHub CLI documents `isFork` and `parent` as `gh repo view --json` fields:
  https://cli.github.com/manual/gh_repo_view

### Finding (cycle 14)

- **Minor — fork/continuation attribution was not checked against live GitHub
  parent metadata.** Manual `forkOf` fields now make attribution visible, but
  the report cannot distinguish a true GitHub fork with a matching parent from a
  continuation/import that intentionally records an upstream without being a
  GitHub fork. → roadmap "Report GitHub fork-parent drift against catalog
  attribution". [Closed v4.9.56]

### Standards note (cycle 14)

- Do not fail every `forkOf` row where `isFork=false`. Some rows are
  continuations or imports, not GitHub fork-network children. The useful report
  shape is a three-way classification: GitHub fork matches catalog, GitHub fork
  missing/mismatched catalog attribution, and catalog-declared continuation.
- Keep README rendering unchanged unless the build machine finds a compact
  visitor-facing label. This is primarily a report/feed correctness guard.

## Cycle 15 Research Addendum — 2026-06-04

This pass focused on live repository enumeration completeness as the public
catalog grows. The current account is under the configured limit, so this is a
future-proofing guard rather than a current truncation failure.

### Evidence reviewed (cycle 15)

- `scripts/sync-profile.ps1:207-213` builds the normal metadata command with
  `gh repo list SysAdminDoc --visibility public --no-archived --limit 300`.
- `gh repo list SysAdminDoc --visibility public --no-archived --limit 500
  --json name --jq 'length'` returned 184 active public repositories on
  2026-06-04.
- `gh repo list --help` documents `--limit` as the maximum number of
  repositories to list, with default 30.
- The REST fallback path at `scripts/sync-profile.ps1:141-156` paginates
  `users/$Owner/repos?per_page=100&page=$page`, but the normal `gh repo list`
  path has no near-limit warning or completeness metadata.
- GitHub CLI docs document `gh repo list --limit`:
  https://cli.github.com/manual/gh_repo_list

### Finding (cycle 15)

- **Minor — normal repo enumeration has a fixed cap without a near-limit
  signal.** The current account has 184 active public repos, below the hard-coded
  300 limit, but future growth could reach the cap and silently omit public repos
  from metadata, drift checks, and generated output. → roadmap "Add a public-repo
  enumeration limit guard". [Verified]

### Standards note (cycle 15)

- Keep this separate from the REST release-fallback N+1 item. That item handles
  per-repo release lookup and rate limits after metadata enumeration; this item
  verifies the first repo list is complete enough to trust.
- Report-only is enough while the account is far from the cap. Treat equality
  with the configured limit as suspicious, because an exact hit is more likely
  to indicate truncation than a naturally exact repository count.

## Cycle 16 Research Addendum — 2026-06-04

This pass focused on the committed sync report's machine-readable contract now
that multiple queued workflow-summary, artifact, and report-consumer items
depend on stable report fields.

### Evidence reviewed (cycle 16)

- `schemas/` currently contains only `profile-catalog.v1.json` and
  `profile-projects.v1.json`.
- `reports/profile-sync-report.json` has structured top-level fields including
  `generatedAt`, `readmeInSync`, `projectsExportInSync`,
  `profileAssetsInSync`, `metadataHygiene`, `releaseAssetDrift`,
  `validationPerformance`, `readmeExperienceChecks`, `schemaValidation`, and
  `docVersionConsistency`.
- `reports/profile-sync-report.json` has no top-level `schema` or `$schema`
  pointer.
- `tests/sync-profile.Tests.ps1` validates catalog/feed schema contracts and
  report helper behavior, but it does not validate the full sync-report document
  against a versioned schema.
- JSON Schema's official site describes the vocabulary as enabling JSON data
  consistency, validation, documentation, and interoperability:
  https://json-schema.org/

### Finding (cycle 16)

- **Minor — the sync report has no published schema contract.** The report is
  already the central evidence artifact for generated-profile checks and will be
  parsed by planned job summaries, artifacts, and report parity work, but its
  fields are not described by a versioned schema the way catalog/feed fields are.
  → roadmap "Publish a JSON Schema for profile-sync-report.json". [Completed v4.9.45]

### Standards note (cycle 16)

- Keep this schema pragmatic. The report contains arrays of diagnostic records
  where strict item schemas are useful, but it should still allow additive fields
  so future research/build cycles can extend report evidence without breaking
  older consumers.
- Avoid circular validation confusion: catalog/feed schema validation remains a
  report field, while report-schema validation should be a separate generated
  check or Pester assertion with a clear failure message.

## Cycle 17 Research Addendum — 2026-06-04

This pass focused on GitHub's pull-request presentation of the repo's committed
generated artifacts. The gap is review ergonomics, not generation correctness:
the generator can keep producing the files, while GitHub can be told which
fully generated artifacts should be collapsed in diffs by default.

### Evidence reviewed (cycle 17)

- Root listing shows no `.gitattributes`.
- `git check-attr -a -- README.md projects.json
  reports/profile-sync-report.json assets/profile/stats-light.svg` returned no
  attributes.
- Fully generated, tracked machine artifacts are large enough to dominate a
  generated-profile PR: `projects.json` is 293,281 bytes,
  `reports/profile-sync-report.json` is 27,988 bytes, and the six
  `assets/profile/*.svg` panels total 15,338 bytes.
- `scripts/sync-profile.ps1` exposes the generated destinations through
  `ReadmePath`, `ProjectsPath`, `ReportPath`, and `AssetsPath`, and it writes
  the profile SVG panels under `assets/profile/`.
- GitHub Docs describe `.gitattributes` with `linguist-generated` as the way to
  keep selected generated paths hidden by default in diffs and excluded from
  repository language statistics:
  https://docs.github.com/en/repositories/working-with-files/managing-files/customizing-how-changed-files-appear-on-github

### Finding (cycle 17)

- **Minor — generated feed/report/SVG churn is not marked for GitHub review
  ergonomics.** The repo already owns generated contract files through
  CODEOWNERS and validates them through the sync report, but GitHub has no
  `.gitattributes` hint to collapse the fully generated artifacts in PR diffs.
  `README.md` should remain visible by default because it is the public profile
  surface and includes hand-authored context around generated sections.
  → roadmap "Add a `.gitattributes` generated-artifact diff policy". [Verified]

### Standards note (cycle 17)

- Start with only fully generated files: `projects.json`,
  `reports/profile-sync-report.json`, and `assets/profile/*.svg`. Marking the
  whole README as generated would hide high-value public-facing review context
  until a later workflow can summarize generated README changes safely.
- Keep this separate from the `.editorconfig`/markdownlint item. `.gitattributes`
  affects GitHub presentation and language statistics; lint settings affect
  local formatting consistency.

## Cycle 18 Research Addendum — 2026-06-04

This pass checked the lifecycle of generated pull-request branches created by
the profile sync and profile-assets refresh workflows. The current state is not
dirty, but the repository setting does not prevent future branch accumulation.

### Evidence reviewed (cycle 18)

- `.github/workflows/profile-sync.yml` creates
  `automation/profile-sync-${{ github.run_id }}`, pushes it, and opens a PR
  with `gh pr create`.
- `.github/workflows/assets-refresh.yml` creates
  `automation/profile-assets-${{ github.run_id }}`, pushes it, and opens a PR
  with `gh pr create`.
- `gh repo view SysAdminDoc/SysAdminDoc --json deleteBranchOnMerge --jq
  .deleteBranchOnMerge` returned `false`.
- `git ls-remote --heads origin automation/*` returned no current automation
  branches, so the finding is preventive rather than cleanup of a current
  backlog.
- GitHub Docs describe an "Automatically delete head branches" repository
  setting for deleting PR head branches after merge:
  https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-the-automatic-deletion-of-branches

### Finding (cycle 18)

- **Cosmetic — generated PR branches have no cleanup policy.** The workflows
  intentionally create one branch per generated profile/assets run, but the repo
  has automatic branch deletion disabled. Future scheduled/manual generated PRs
  can leave merged automation branches behind unless the build machine enables
  repository-wide head-branch deletion or adds a narrowly scoped cleanup path.
  → roadmap "Enable cleanup for generated automation PR branches". [Verified]

### Standards note (cycle 18)

- Repository-wide auto-delete is simplest, but it is an operator setting and may
  affect human-created branches too. If that is too broad, prefer a scoped
  cleanup path that only touches merged `automation/profile-sync-*` and
  `automation/profile-assets-*` refs.
- Keep branch cleanup separate from generated PR validation. A generated branch
  should only be deleted after merge/closure, never as a substitute for checks.

## Cycle 19 Research Addendum — 2026-06-04

This pass looked at maintainability of the generated PR path now that both
profile sync and profile-assets refresh can create pull requests. The existing
roadmap already covers token semantics, report summaries, and branch cleanup;
this finding is about duplicated workflow code.

### Evidence reviewed (cycle 19)

- `.github/workflows/profile-sync.yml:71-101` has a `Create pull request` step
  that checks for changes, creates `automation/profile-sync-*`, configures the
  bot identity, stages `README.md`, `projects.json`,
  `reports/profile-sync-report.json`, and `assets/profile/*.svg`, commits,
  pushes, and runs `gh pr create`.
- `.github/workflows/assets-refresh.yml:34-62` repeats the same branch, staging,
  commit, push, and `gh pr create` flow for `automation/profile-assets-*`.
- The PowerShell `$LASTEXITCODE` explanation for native-command no-change guards
  is present in the profile-sync workflow copy, but not in the assets-refresh
  workflow copy.
- `rg -n "workflow_call|composite|\\.github/actions|uses:" .github` found no
  reusable workflow or composite action in the current repo.
- GitHub Docs describe reusable workflows as a way to avoid workflow
  duplication, and composite actions as a way to collect repeated steps for use
  in multiple workflows:
  https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows
  and
  https://docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action

### Finding (cycle 19)

- **Cosmetic — generated PR creation logic is duplicated across workflows.**
  The two workflows currently have the same branch/stage/commit/push/PR
  mechanics with small message differences. Future changes from the generated PR
  validation handoff, branch cleanup, or report-summary work will be easier to
  apply correctly if both workflows call one shared helper or local composite
  action with explicit inputs.
  → roadmap "Centralize generated PR creation logic". [Verified]

### Standards note (cycle 19)

- A small PowerShell helper may be simpler than a reusable workflow because both
  current workflows already run different generation steps before creating a PR.
  A composite action is also reasonable if the build machine wants the shared
  behavior to stay inside `.github/`.
- The helper must keep staging explicit. Do not replace the file list with broad
  `git add .`, because the generated PR workflows should remain constrained to
  profile outputs.

## Cycle 20 Research Addendum — 2026-06-04

This pass checked whether the profile repository's public release state matches
the tracked planning-doc version. The docs are internally consistent, but GitHub
Releases and tags are behind that version series.

### Evidence reviewed (cycle 20)

- `CHANGELOG.md` starts at `v4.9.24` dated 2026-06-04.
- `ROADMAP.md` reports `Current repo version: v4.9.24`.
- `PROJECT_CONTEXT.md` reports `Version: v4.9.24`.
- `gh repo view SysAdminDoc/SysAdminDoc --json latestRelease` returned latest
  release tag `v3.0.0`, published 2026-04-13.
- `git tag --list "v4.9.*"` returned no local `v4.9.*` tags in the clean clone.
- `reports/profile-sync-report.json` has `docVersionConsistency`, but that
  section does not compare the tracked version to GitHub Releases or tags.
- GitHub Docs describe releases as deployable project iterations based on tags:
  https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository

### Finding (cycle 20)

- **Minor — tracked profile versions are ahead of public GitHub Releases.** The
  repo's planning docs and changelog now identify `v4.9.24` as current, while
  the public latest release remains `v3.0.0`. If releases are intended to be a
  public trust/version surface, the report should catch this drift; if they are
  not, the repo should document that the changelog version is the canonical
  profile-doc version and releases are intentionally sparse.
  → roadmap "Add a profile-repo release/tag consistency check". [Closed v4.9.57]

### Standards note (cycle 20)

- Keep release consistency policy explicit. A profile README repo may reasonably
  use changelog-only versions, but the current mix of versioned docs plus stale
  GitHub Releases is ambiguous to visitors and downstream tooling.
- This should augment, not replace, `docVersionConsistency`: tracked docs can be
  internally aligned while still drifting from public release/tag state.

## Cycle 21 Research Addendum — 2026-06-04

This pass checked the public changelog beyond the latest heading already covered
by `docVersionConsistency`. The current latest heading is valid, but historical
release headings are not validated.

### Evidence reviewed (cycle 21)

- `CHANGELOG.md:278` is `## [v3.0.0] - %Y->- (HEAD -> main, origin/main,
  origin/HEAD)`.
- A focused scan of `CHANGELOG.md` release headings found that line as the only
  heading whose date portion does not match `YYYY-MM-DD`.
- `scripts/sync-profile.ps1:2580-2585` parses the latest changelog version/date
  for cross-doc consistency, but it does not scan all release headings.
- Pester coverage exercises matching latest versions and stale latest dates, but
  not malformed historical headings.
- Keep a Changelog examples use second-level version headings with ISO-style
  dates such as `## [1.1.1] - 2023-03-05`:
  https://keepachangelog.com/en/1.1.0/

### Finding (cycle 21)

- **Cosmetic — historical changelog release headings can be malformed without
  failing checks.** The active doc-version gate is doing useful work for the
  current version, but an older `v3.0.0` heading still contains leaked git/status
  text instead of a date. The build machine should either clean the heading and
  validate all historical release headings, or record a narrow legacy exception
  if the original date cannot be recovered.
  → roadmap "Validate all changelog release headings". [Verified]

### Standards note (cycle 21)

- Keep the heading rule simple and explainable: `## [vMAJOR.MINOR.PATCH] -
  YYYY-MM-DD`. If historical dates are unknown, prefer a documented exception or
  an "Unknown date" policy over allowing arbitrary shell output in headings.
- This should be a docs-quality warning unless the malformed heading can break
  downstream release tooling; the latest-heading mismatch should remain fatal.

## Cycle 22 Research Addendum — 2026-06-04

This pass checked executable install trust for userscript rows. The existing
release/download trust roadmap item covers release-backed EXE/APK/ZIP rows; raw
`.user.js` install actions are a separate surface because userscript managers
execute and update them from metadata in the script header.

### Evidence reviewed (cycle 22)

- Parsing `projects.json` found 11 rows with `downloadKind=userscript` and
  `primaryAction.kind=install`.
- Ten userscript install URLs point to `raw.githubusercontent.com/.../main/...`
  and one points to `raw.githubusercontent.com/.../master/...`.
- `README.md` reports "11 userscript installs" in the generated profile
  snapshot and renders those rows as `Install` actions.
- `scripts/sync-profile.ps1:704-706` adds userscript URLs to link validation,
  so the current gate checks reachability.
- `scripts/sync-profile.ps1:3055-3062` excludes `userscript` from
  release/download drift checks, which is correct for release assets but leaves
  userscript trust unreported.
- Tampermonkey documents userscript metadata keys including `@version`,
  `@match`, `@updateURL`, and `@downloadURL`:
  https://www.tampermonkey.net/documentation.php?locale=en

### Finding (cycle 22)

- **Minor — raw userscript installs have link checks but no trust metadata
  report.** The profile offers 11 direct install links for browser-executed
  `.user.js` files. A reachable raw URL is necessary but not enough to explain
  whether the script header has a version, stable update/download URLs,
  expected match scope, and clear branch/tag provenance.
  → roadmap "Add userscript install trust metadata". [Verified]

### Standards note (cycle 22)

- Start report-only. Userscript trust signals are nuanced: branch-hosted scripts
  may be intentional for fast updates, while release/tag URLs are more stable
  but heavier to maintain.
- Keep public summaries aggregate-first. Do not surface noisy match-pattern
  details in the README unless a specific script is flagged.

## Cycle 23 Research Addendum — 2026-06-04

This pass checked whether the repo's workflow-security coverage would include a
future local composite action. There is no `.github/actions` directory today,
but the generated PR helper roadmap item explicitly allows that implementation
path.

### Evidence reviewed (cycle 23)

- `.github/workflows/workflow-security.yml` pull-request paths include
  `.github/workflows/**`, `.github/dependabot.yml`, and `.github/CODEOWNERS`.
- The workflow-security job runs `zizmor .github/workflows`, so its current
  audit target is also workflow-only.
- `.github/CODEOWNERS` owns `.github/workflows/`, but it does not own
  `.github/actions/`.
- A filesystem check found no current `.github/actions` directory.
- Cycle 19's generated PR helper item lists
  `.github/actions/create-generated-profile-pr/action.yml` as an implementation
  option.
- GitHub Docs describe composite actions as repository files with action
  metadata consumed by workflows:
  https://docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action

### Finding (cycle 23)

- **Cosmetic — future local actions would sit outside workflow-security
  coverage.** If the generated PR helper is implemented as a local composite
  action, changes under `.github/actions/**` would not trigger the current
  workflow-security PR path or CODEOWNERS review, and the audit command would
  still inspect only `.github/workflows`.
  → roadmap "Cover local GitHub actions in workflow-security". [Verified]

### Standards note (cycle 23)

- Keep this conditional. Do not add a placeholder `.github/actions` directory
  just to satisfy coverage; update the trigger, owner patterns, and audit target
  when the first local action lands.
- If the helper is implemented as a PowerShell script under `scripts/` instead,
  this item can be closed by documenting that no local action surface exists.

## Cycle 24 Research Addendum — 2026-06-04

This pass audited the public feed's suppressed rows for privacy posture. The
README/private profile gate keeps suppressed rows out of the README, but the
public `projects.json` feed still contains a `suppressed` array.

### Evidence reviewed (cycle 24)

- Parsing `projects.json` found 9 suppressed rows.
- One suppressed row has a suppression reason beginning "Repo is private" while
  still carrying include flags, a repo URL, and a primary action in the public
  feed. The row name is intentionally not repeated here.
- `scripts/sync-profile.ps1:1651-1739` emits all suppressed rows into
  `projects.json`.
- `scripts/sync-profile.ps1:3146-3185` enforces private/medical violations for
  profile inclusion, but it does not redact private rows from the public
  suppressed array.
- GitHub Docs describe private repositories as accessible only to explicitly
  shared users:
  https://docs.github.com/articles/limits-for-viewing-content-and-diffs-in-a-repository

### Finding (cycle 24)

- **Major — the public feed can name private suppressed rows.** Suppression is
  doing its job for the README, but exporting private suppression details in
  `projects.json` weakens that boundary. Public suppressed rows can remain
  useful for portfolio exclusion and stale-review reporting, but private or
  medical/privacy-sensitive rows should be omitted or redacted before the feed is
  committed.
  → roadmap "Redact private suppression rows from the public feed". [Verified]

### Standards note (cycle 24)

- Treat private suppression redaction as a public-feed contract issue, not just
  README hygiene. The portfolio consumes `projects.json`, and the raw feed is
  directly accessible.
- Keep public-safe suppression reasons for renamed, duplicate, placeholder, or
  stale public repos. Only private/privacy-sensitive rows need redaction or
  aggregate-only handling.

## Cycle 25 Research Addendum — 2026-06-04

This pass checked scheduled workflow cadence after the workflow and generated-PR
guardrail items. It found a low-priority operations hygiene issue, not a failing
validation path.

### Evidence reviewed (cycle 25)

- `.github/workflows/assets-refresh.yml` schedules `cron: "19 8 * * 3"`.
- `.github/workflows/workflow-security.yml` schedules the same
  `cron: "19 8 * * 3"`.
- `profile-sync.yml` is staggered on Tuesday/Friday at `37 7 * * 2,5`.
- `scorecard.yml` is staggered on Thursday at `43 8 * * 4`.
- GitHub Actions docs note scheduled workflows can be delayed or dropped during
  high-load periods and recommend scheduling at a different minute of the hour
  to reduce delay risk:
  https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule

### Finding (cycle 25)

- **Cosmetic — two independent scheduled maintenance workflows start in the same
  minute.** `assets-refresh` and `workflow-security` do different work, but
  running both at Wednesday 08:19 makes run triage noisier and can stack package
  installs, GitHub API calls, and generated-output checks in the same
  maintenance window.
  → roadmap "Stagger same-minute scheduled maintenance workflows". [Verified]

### Standards note (cycle 25)

- Keep this as hygiene. The existing timeout-budget item remains the real
  control for hung jobs; schedule staggering only improves attribution and
  reduces avoidable overlap.
- Preserve manual dispatch behavior and avoid top-of-hour cron values.

## Cycle 26 Research Addendum — 2026-06-04

This pass checked whether the committed JSON Schema contracts are covered by
the offline Tests workflow when schema files themselves change. It found a small
trigger gap rather than a missing test.

### Evidence reviewed (cycle 26)

- `.github/workflows/tests.yml` runs on `pull_request` and `push`, but both path
  filters include only `scripts/**`, `tests/**`, and
  `.github/workflows/tests.yml`.
- The offline Pester suite contains `Feed JSON Schema contracts` cases that call
  `Test-FeedSchemaContracts` and validate a generated projects payload against
  `schemas/profile-projects.v1.json`.
- `schemas/profile-catalog.v1.json` and `schemas/profile-projects.v1.json`
  define the committed public schema contract IDs.
- GitHub workflow syntax docs state that `push`/`pull_request` path filters run
  based on changed file paths and that skipped required checks can remain
  pending:
  https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax

### Finding (cycle 26)

- **Cosmetic — schema-only contract edits can skip the schema-contract test
  lane.** The tests exist, but the workflow path filters do not include
  `schemas/**`. A PR that changes only a committed schema can therefore avoid the
  offline Pester workflow that validates catalog/feed compatibility against
  those schemas.
  → roadmap "Include schema-contract changes in the offline Tests workflow".
  [Verified]

### Standards note (cycle 26)

- Keep this narrow. The heavier profile-sync PR-validation item can decide
  whether schemas also require a live generated-profile check; this item only
  ensures the existing offline schema-contract tests are created for schema
  diffs.
- If Tests becomes a required check, account for GitHub's skipped-check behavior
  before relying on path filters globally.

## Cycle 27 Research Addendum — 2026-06-04

This pass checked future Dependabot workflow-update queue shape. It is separate
from the existing item that triages the currently open major action-update PRs.

### Evidence reviewed (cycle 27)

- `.github/dependabot.yml` has one `github-actions` update block, a weekly
  Tuesday schedule, and `open-pull-requests-limit: 5`.
- The Dependabot config has no `groups` rule.
- Live `gh pr list -R SysAdminDoc/SysAdminDoc --state open` currently shows two
  separate Dependabot GitHub Actions PRs: #5 for `actions/checkout` and #6 for
  `github/codeql-action`.
- GitHub's Dependabot options reference says Dependabot opens one PR per
  dependency by default, while `groups` can combine matching updates into fewer
  targeted PRs with `patterns` and `update-types`:
  https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference

### Finding (cycle 27)

- **Cosmetic — routine GitHub Actions updates are not grouped.** The current
  separate major PRs still need the existing SHA-pin review checklist, but the
  config has no way to bundle future low-risk minor/patch action bumps. A small
  group rule can reduce review queue noise without weakening major-action or
  permission-sensitive review.
  → roadmap "Group routine Dependabot GitHub Actions version updates".
  [Verified]

### Standards note (cycle 27)

- Do not group major action updates blindly. Major updates and any action that
  changes requested permissions, credential persistence, or workflow semantics
  should stay individually reviewable.
- Keep this subordinate to the existing action-update triage process; grouping
  helps queue shape, not trust evaluation.

## Cycle 28 Research Addendum — 2026-06-04

This pass checked catalog-to-feed accounting after the public-feed privacy and
schema-contract items. It found one row that is not exported in either public
feed array and is not separately reported as intentionally local-only. This is
about source catalog accounting in this repo, not the portfolio site's local
overlay/fallback omission check from v4.9.18.

### Evidence reviewed (cycle 28)

- Parsing `data/profile-catalog.json` and `projects.json` found 187 catalog
  entries, 177 exported `projects`, 9 exported `suppressed` rows, and 1 catalog
  row absent from both arrays.
- The absent row is `VaultBox`: `category: "suppressed"`,
  `includeInReadme: false`, `includeInPortfolio: false`, and
  `suppressionReason: null`.
- `scripts/sync-profile.ps1:1665` sets the exported `suppressed` flag only from
  nonblank `suppressionReason`.
- `scripts/sync-profile.ps1:1724-1728` adds rows to `suppressed` when that flag
  is true, otherwise adds only `includeInPortfolio` rows to `projects`.

### Finding (cycle 28)

- **Minor — one catalog row is omitted from both feed arrays without an
  accounting trail.** This may be intentional local-only state, but the current
  report and feed do not distinguish intentional omission from a catalog mistake.
  The row is neither visible to portfolio consumers nor represented in
  `suppressedCount`.
  → roadmap "Report catalog rows omitted from both public feed arrays".
  [Verified]

### Standards note (cycle 28)

- Keep this compatible with Cycle 24 privacy redaction. Private or
  privacy-sensitive rows should not be publicly named just to satisfy accounting;
  aggregate/redacted counts are acceptable for those cases.
- Prefer an explicit reason field or report section over making `category:
  "suppressed"` alone imply a public feed suppression reason.

## Cycle 29 Research Addendum — 2026-06-04

This pass checked whether the in-repo JSON Schema validator fails closed when
future schemas use keywords outside its current subset. Current schemas are
simple enough for the validator, so this is a future-proofing guard.

### Evidence reviewed (cycle 29)

- `scripts/sync-profile.ps1:2261-2395` implements `$ref`, `type`, `const`,
  `enum`, `format`, `pattern`, `minimum`, `minItems`, `items`, `required`,
  `properties`, and `additionalProperties`.
- Searches of `schemas/` found no current `oneOf`, `anyOf`, `allOf`, `if`,
  `then`, or `dependentRequired` keywords.
- `tests/sync-profile.Tests.ps1:425-445` checks that a missing required project
  row field is rejected, but there is no fixture proving unsupported schema
  keywords fail closed.
- A queued sync-report schema and the Cycle 28 omitted-row accounting invariant
  are both likely to need semantic constraints that go beyond simple required
  fields and enums if they are represented in JSON Schema.

### Finding (cycle 29)

- **Cosmetic — unsupported schema keywords can be silently ignored.** The custom
  validator is sufficient for today's schemas, but a future schema can add
  conditional or combinator keywords and still appear to pass if those keywords
  are not implemented. That weakens the schema contract at the exact moment the
  repo starts adding deeper report/feed semantics.
  → roadmap "Guard unsupported JSON Schema keywords in the custom validator".
  [Verified]

### Standards note (cycle 29)

- Failing closed is enough for now. The build machine does not need to implement
  every JSON Schema keyword immediately; it only needs to prevent schemas from
  claiming enforcement that the validator does not perform.
- If deeper schemas become central to downstream consumers, reassess whether a
  full JSON Schema implementation is better than maintaining a local subset.

## Cycle 30 Research Addendum — 2026-06-04

This pass checked committed profile SVG panel accessibility metadata. It is
separate from the completed README image-alt work because the SVGs are also raw
repository artifacts that can be opened or inspected outside the README wrapper.

### Evidence reviewed (cycle 30)

- `scripts/sync-profile.ps1:1355-1359` emits `<svg ... role="img"
  aria-label="...">` plus visible text, but no internal `<title>` or `<desc>`.
- `assets/profile/stats-dark.svg:1-5` mirrors that structure in the committed
  artifact.
- A scan of `assets/profile/*.svg` found no `<title>` or `<desc>` elements.
- W3C SVG Accessibility API Mappings describe `title`/`desc` and note current
  best practice for fallback support is linking them with `aria-labelledby` and
  `aria-describedby`:
  https://www.w3.org/TR/svg-aam-1.0/

### Finding (cycle 30)

- **Cosmetic — generated SVG panels lack standalone title/description metadata.**
  The README embeds use meaningful `<img alt>` text, so the profile page is not
  missing alt labels. The raw SVG artifacts themselves, however, only carry a
  short `aria-label`; adding internal `title`/`desc` metadata would make direct
  SVG links and tooling exports more self-describing.
  → roadmap "Add internal `<title>` and `<desc>` metadata to generated profile
  SVG panels". [Verified]

### Standards note (cycle 30)

- Keep README alt text concise. The SVG `desc` can summarize the panel rows, but
  the outer `<img alt>` should remain the user-facing fallback for the profile
  README.
- Generate stable ids so the SVGs can use `aria-labelledby` and
  `aria-describedby` without fragile random output.

## Cycle 31 Research Addendum — 2026-06-04

This pass checked public planning/history docs for stale catalog-field
terminology. It found a docs drift issue rather than a generator failure.

### Evidence reviewed (cycle 31)

- `COMPLETED.md:9` describes the canonical catalog row shape and includes
  `privateReason`.
- `schemas/profile-catalog.v1.json` defines current catalog fields including
  `allowPublicMedical`, `aliasOf`, and `suppressionReason`; it has no
  `privateReason`.
- `data/profile-catalog.json` uses `suppressionReason` for suppression state.
- The current version/date consistency gate keeps planning docs aligned by
  version/date, but it does not catch stale field-name references in public
  history docs.

### Finding (cycle 31)

- **Cosmetic — completed-work docs mention a stale catalog field name.**
  `COMPLETED.md` is historical, but the line describes the canonical catalog
  source file as a current shape. Keeping `privateReason` there can mislead
  maintainers now that schema-backed catalog rows use `suppressionReason` plus
  explicit public-safety fields.
  → roadmap "Refresh stale catalog field names in completed-work docs".
  [Verified]

### Standards note (cycle 31)

- Avoid rewriting broad project history. This is a terminology cleanup for
  public current-shape descriptions, not a request to reframe every historical
  implementation note.
- Prefer pointing maintainers at `schemas/profile-catalog.v1.json` when a full
  field list would drift quickly.

## Cycle 32 Research Addendum — 2026-06-04

This pass checked the boundary between generated Markdown validation and the
actual GitHub.com profile rendering path. The repo already says generated
README refreshes need a "markdown render smoke check on GitHub after push"; the
missing piece is a repeatable, artifact-producing smoke path that future
generated-profile changes can run before accepting a PR or after a push.

### Evidence reviewed (cycle 32)

- `ROADMAP.md:503` lists "markdown render smoke check on GitHub after push" in
  the verification standard, but no current workflow uploads screenshots or
  records rendered DOM checks.
- `scripts/sync-profile.ps1:1923-2011` implements `Test-ReadmeExperience` as a
  string/pattern check over generated README content.
- `tests/sync-profile.Tests.ps1:250-330` exercises generated Markdown output
  offline, including profile chrome, alt labels, setup guidance, and duplicate
  chrome guards.
- `.github/workflows/profile-sync.yml:23-48` and
  `.github/workflows/assets-refresh.yml:23-62` run the generator/check path, but
  neither workflow opens GitHub.com, captures rendered screenshots, checks
  viewport overflow, or uploads visual artifacts.
- `README.md:11`, `README.md:60-65`, and the live profile at
  https://github.com/SysAdminDoc use profile-specific image, table, picture, SVG,
  kbd, details, and remote-image rendering that can be correct as Markdown but
  still fail in GitHub.com layout.
- `RESEARCH_REPORT.md:276` records that rendered GitHub light-mode and mobile
  behavior were inferred in an earlier pass rather than re-screenshotted in a
  browser.
- GitHub docs state that a public username-matching repository README appears on
  the profile and is formatted with GitHub Flavored Markdown:
  https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
- GitHub's profile docs emphasize the profile README as a top-of-profile public
  surface:
  https://docs.github.com/en/account-and-profile/concepts/personal-profile
- GitHub's Markdown REST API can render Markdown as HTML, but that is not a full
  substitute for GitHub.com profile CSS, sanitizer, image loading, and responsive
  behavior:
  https://docs.github.com/en/rest/markdown/markdown
- GitHub Markup documents that it covers markup rendering only; sanitization and
  the rest of the pipeline happen on GitHub.com:
  https://github.com/github/markup
- Playwright supports screenshot assertions and stable screenshot generation for
  visual comparison:
  https://playwright.dev/docs/test-snapshots
- GitHub Actions artifacts and job summaries can publish rendered evidence for
  maintainer review:
  https://docs.github.com/en/actions/tutorials/store-and-share-data and
  https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands

### Landscape source sweep (cycle 32)

External source set checked for render constraints, accessibility, workflow
evidence, and adjacent profile-README tooling:

1. https://github.com/SysAdminDoc
2. https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
3. https://docs.github.com/en/account-and-profile/concepts/personal-profile
4. https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
5. https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax
6. https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-tables
7. https://docs.github.com/en/rest/markdown/markdown
8. https://github.github.com/gfm/
9. https://github.com/github/cmark-gfm
10. https://github.com/github/markup
11. https://github.blog/changelog/2021-11-24-specify-theme-context-for-images-in-markdown/
12. https://playwright.dev/docs/test-snapshots
13. https://playwright.dev/docs/screenshots
14. https://docs.github.com/en/actions/tutorials/store-and-share-data
15. https://github.com/actions/upload-artifact
16. https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
17. https://www.w3.org/WAI/test-evaluate/easy-checks/image-alt/
18. https://www.w3.org/TR/svg-aam-1.0/
19. https://www.w3.org/WAI/WCAG20/Understanding/pause-stop-hide.html
20. https://docs.github.com/en/actions/reference/security/secure-use
21. https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
22. https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow
23. https://github.com/ossf/scorecard-action
24. https://github.com/ossf/scorecard
25. https://zizmor.sh/
26. https://github.com/rhysd/actionlint
27. https://www.npmjs.com/package/markdownlint-cli2
28. https://github.com/lycheeverse/lychee
29. https://github.com/tcort/markdown-link-check
30. https://github.com/DenverCoder1/readme-typing-svg
31. https://github.com/tandpfun/skill-icons
32. https://github.com/anuraghazra/github-readme-stats
33. https://rahuldkjain.github.io/gh-profile-readme-generator/about/
34. https://github.com/abhisheknaiidu/awesome-github-profile-readme

### Raw ideas harvested (cycle 32)

- Browser-load the live `https://github.com/SysAdminDoc` profile and capture
  desktop plus mobile screenshots after profile sync changes.
- Use GitHub's Markdown REST API as a faster pre-render check for sanitizer/GFM
  output, but do not treat it as proof of final GitHub.com layout.
- Add full visual-regression baselines for the profile page.
- Add screenshot artifacts and a concise job summary to generated-profile
  workflows so maintainers can inspect render state without opening logs.
- Add another static Markdown/table linter.

### Fit scoring (cycle 32)

- **Live rendered smoke check** - Fit: high; impact: medium; effort: medium;
  risk: low if screenshot artifacts are public-safe; dependency: Playwright or
  equivalent browser runner; novelty: medium because existing checks are static;
  tier: P2; implementation level: M.
- **Markdown REST API render check only** - Fit: medium; impact: low; effort:
  small; rejected as a standalone item because it still misses GitHub.com CSS,
  viewport, image loading, and responsive behavior. It can be a sub-step inside
  the live smoke path.
- **Full visual regression baselines** - Fit: medium; impact: medium; effort:
  high; rejected for now because profile content, stars, and GitHub shell UI can
  change. A smoke assertion plus artifacts gives useful proof without brittle
  pixel baselines.
- **Static Markdown/table lint only** - Fit: medium; impact: low; effort: small;
  rejected as a new row because generated README linting and source safety are
  already queued separately.

### Finding (cycle 32)

- **Minor - generated profile checks do not prove the live GitHub-rendered
  profile.** The repo has strong generator, schema, link, SVG, and README string
  checks, but the actual user-visible surface is GitHub.com rendering. A small
  browser smoke path would catch table compression, horizontal overflow, missing
  images, theme-specific asset regressions, and first-viewport ordering issues
  that static tests can miss. -> roadmap "Add a live GitHub-rendered profile
  smoke check". [Verified]

### Standards note (cycle 32)

- Keep the first implementation smoke-oriented: DOM assertions, horizontal
  overflow checks, image natural-width/load checks, and screenshots as artifacts.
  Avoid brittle full-page pixel baselines until the generated profile is stable
  enough to justify them.
- If the smoke runs after push against the live profile, record the exact commit
  SHA, run URL, and profile fetch time in the summary so cache delays are
  distinguishable from real render regressions.
- Coverage audit: security/privacy is covered by public-safe screenshot and
  summary requirements; accessibility is covered through rendered image, motion,
  table, and first-viewport checks; observability is covered through artifacts
  and job summaries; testing/docs are covered by the smoke and this roadmap
  entry. i18n, packaging, plugin, offline, multi-user, and data migration are
  not active dimensions for this static public GitHub profile surface.

## Open Questions

- Should generated `topicHints` stay report-only, or should reviewed hints be promoted into catalog-managed metadata?
- Should low-risk generated metadata drift be auto-PR'd on schedule, or should scheduled jobs remain check-only with manual `write-pr`?
- Should CODEOWNERS cover all public planning docs, or only files that directly
  affect generated README/feed output and setup/install trust?
- Should project SPDX labels remain feed/report-only, or should README rows
  eventually display compact license labels for download/action-heavy projects?
- Should catalog `forkOf` rows gain an explicit attribution kind such as
  `github-fork`, `continuation`, or `imported-fork`?
- What public-repo count threshold should warn before the configured enumeration
  cap becomes a real truncation risk?
- Should the sync-report schema be strict for all diagnostic arrays, or allow
  additive fields so report consumers survive future validation sections?
- Should GitHub collapse only fully generated feed/report/SVG artifacts, or
  should a later job-summary workflow make generated README sections safe to
  mark as generated too?
- Should generated branch cleanup use the repository-wide auto-delete setting,
  or a scoped workflow/admin cleanup that only removes merged `automation/*`
  branches?
- Should shared generated-PR logic live as a PowerShell helper under `scripts/`,
  or as a local composite action under `.github/actions/`?
- Should `v4.9.x` planning versions produce matching GitHub Releases/tags, or
  should this repo document that changelog versions are internal profile-doc
  milestones and releases are intentionally sparse?
- Should malformed historical changelog headings fail `-Check`, or start as
  report warnings until the existing `v3.0.0` date can be recovered?
- Should completed-work docs preserve legacy field names as historical notes, or
  normalize them to current public schema terms when they describe current
  catalog shape?
- Should raw userscript install rows stay branch-hosted for automatic updates,
  or should high-traffic scripts move toward release/tag-hosted install URLs
  with explicit update metadata?
- If generated PR creation becomes a local composite action, should
  workflow-security audit `.github/actions/**` in the same job as workflows or
  through a separate local-action metadata lint step?
- Should private/privacy-sensitive suppressed rows be omitted entirely from the
  public feed, or represented only as aggregate redacted counts?
- Should the repo adopt a simple maintenance-window convention for scheduled
  workflows, or only stagger accidental same-minute collisions as they appear?
- Should schema changes trigger only the offline Pester contract lane, or also
  the heavier profile-sync PR validation path?
- Should Dependabot group only minor/patch GitHub Actions updates, or keep
  separate PRs for security-sensitive actions such as checkout and CodeQL?
- Should local-only catalog rows require their own explicit reason field, or is
  a non-public aggregate count enough when `includeInPortfolio=false`?
- Should the repo keep a small fail-closed custom JSON Schema validator, or adopt
  a full validator once report schemas need conditionals/combinators?
- Should generated SVG panel descriptions enumerate all row values, or summarize
  the panel purpose while leaving detailed counts to the visible text/README?
- Should `PROJECT_CONTEXT.md` stay tracked as public project documentation, or should it be reduced to public-safe status notes only?
- What is the portfolio site's preferred schema contract for search and freshness fields from `projects.json`?
- Should `projects.json` provenance stop at hashes/source refs, or should a later generated-asset workflow emit GitHub artifact attestations if the repo starts publishing downloadable generated bundles?
- Should issue templates live only in this repo, or should the account-level `.github` community-health repo carry shared catalog/link templates for all public SysAdminDoc repositories?
- Which checks should be required on every pull request versus only on path-filtered profile-pipeline changes if branch protection/rulesets are tightened?
- Should profile-sync PR validation use a path-filtered workflow, an always-run workflow with internal no-op logic, or a pair of checks so branch protection never waits on skipped profile-sync runs?
- Should the live rendered profile smoke run only post-push against
  `https://github.com/SysAdminDoc`, or should generated PRs also run a
  Markdown-API/local-preview preflight before the live page changes?
- What timeout budget should be treated as normal for full live profile validation once committed SVG asset refresh and release-asset checks both run in the same automation path?
- Should generated Markdown content-safety failures be fatal for all current
  sources, or should GitHub-derived descriptions start as warnings until the
  existing catalog is cleaned?
- Should motion-safe profile chrome replace the typing SVG entirely with static
  text/SVG, or keep a non-repeating version if that proves acceptable?
- Which release trust signals should count as sufficient for README-linked
  EXE/APK/ZIP assets: checksums, signed binaries, GitHub artifact attestations,
  SBOMs, or a documented unsigned status?
- Should the Windows setup smoke check become a required PR check only for
  setup-related paths, or should it remain a manually dispatched regression
  check until runtime is proven stable?
- Should CI tool pins be updated manually in the same Dependabot review pass, or
  should the repo add a lightweight updater such as Renovate only for non-Action
  validation tools?
- Should PyPI-installed CI tools use hash-checking immediately, or start with
  exact version pins and add hashes once the update process is stable?
