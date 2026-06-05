# SysAdminDoc Research Feature Plan - 2026-06-05

Research refresh: 2026-06-05
Repository: SysAdminDoc/SysAdminDoc
Baseline: `06f02c9 docs(roadmap): add live profile render smoke research`
Current version observed: v4.9.28

## Executive Summary

SysAdminDoc/SysAdminDoc is a public GitHub profile README repository that now operates more like a generated portfolio catalog than a hand-written profile page. Its strongest current shape is the generator contract: `data/profile-catalog.json` plus live GitHub metadata produce `README.md`, `projects.json`, `assets/profile/*.svg`, and `reports/profile-sync-report.json`, with Pester, schema validation, link validation, release-asset checks, metadata drift checks, and workflow security checks layered around that pipeline. The highest-value direction is no longer generic profile polish. It is closing the gaps between source-level checks, live GitHub rendering, repository governance, and downstream portfolio consumption.

Top opportunities, in priority order:

1. P0 - Fix the failing OpenSSF Scorecard workflow by moving write permissions out of workflow-level permissions and matching Scorecard publish restrictions. Shipped in v4.9.26.
2. P0 - Add a repeatable live GitHub-rendered profile smoke check with desktop/mobile screenshots and overflow assertions. Shipped in v4.9.27.
3. P1 - Make generated-profile validation run automatically on pull requests that touch catalog, README, feed, report, SVG assets, schemas, setup, or workflow surfaces. Shipped in v4.9.28.
4. P1 - Require the right status checks on `main` through branch protection or rulesets after the PR checks are always created.
5. P1 - Add a public-safe `SECURITY.md`, issue forms, and PR template for broken links, profile corrections, workflow changes, and security reports.
6. P1 - Account for every catalog row in the generated feed/report, including `VaultBox`, which is currently absent from both `projects` and `suppressed`.
7. P2 - Add generated-feed provenance fields such as source commit, catalog hash, generator hash, and metadata snapshot time.
8. P2 - Harden the custom JSON Schema validator so unsupported keywords fail closed before future schemas silently skip semantics.
9. P2 - Improve workflow observability with job summaries, report artifacts, explicit artifact retention, and timeout budgets.
10. P3 - Finish documentation hygiene: replace stale `privateReason` wording, add internal SVG `title`/`desc`, add `.gitattributes` generated-artifact hints, and group routine Dependabot action updates.

## Evidence Reviewed

Local files and directories inspected:

- Root public surfaces: `README.md`, `CHANGELOG.md`, `COMPLETED.md`, `PROJECT_CONTEXT.md`, `RESEARCH_REPORT.md`, `ROADMAP.md`, `projects.json`, `reports/profile-sync-report.json`.
- Generator and validation code: `scripts/sync-profile.ps1`, `setup.ps1`, `PSScriptAnalyzerSettings.psd1`.
- Source data and contracts: `data/profile-catalog.json`, `schemas/profile-catalog.v1.json`, `schemas/profile-projects.v1.json`.
- Generated visual assets: `assets/profile/stats-*.svg`, `assets/profile/languages-*.svg`, `assets/profile/activity-*.svg`.
- Test and CI surfaces: `tests/sync-profile.Tests.ps1`, `.github/workflows/profile-sync.yml`, `assets-refresh.yml`, `tests.yml`, `workflow-security.yml`, `scorecard.yml`, `.github/CODEOWNERS`, `.github/dependabot.yml`.
- Prior public research artifact: `docs/archive/research-feature-plan-2026-06-04.md`.

Git history reviewed:

- `rtk git log -10 --oneline --decorate`, covering `06f02c9` back through cycle 24 research additions.
- Recent commits show the active shape: research-cycle additions to `ROADMAP.md`, v4.9.25 PSScriptAnalyzer lane, and previously shipped feed/schema/profile asset hardening.

Live metadata and rendered behavior reviewed:

- `gh repo view SysAdminDoc/SysAdminDoc` confirmed `PUBLIC`, default branch `main`, MIT license, topics `github-profile`, `portfolio`, `readme`, no security policy, issues/discussions/wiki enabled, branch cleanup disabled, and two repository stars.
- `gh repo list SysAdminDoc --visibility public --no-archived --limit 300` confirmed 184 active public repos, 147 with latest releases, 27 using `master`, 69 without topics, 0 empty descriptions, 8 forks, and 158 updated within the last 30 days.
- `reports/profile-sync-report.json` shows `readmeInSync=true`, `projectsExportInSync=true`, `profileAssetsInSync=true`, `schemaValidation.passed=true`, `docVersionConsistency.passed=true`, zero metadata drift rows, zero link failures, zero link warnings, 185 link targets, and 16 bounded parallel link probes.
- Headless Chrome smoke on `https://github.com/SysAdminDoc` captured desktop and 390px mobile screenshots. The live DOM contained the hero, Professional Focus, Proof Points, Currently Building, and portfolio link. The mobile capture showed a visible horizontal scrollbar and clipped first-viewport README text, which confirms the queued live-render smoke item is real evidence, not only a theoretical gap.
- `gh pr list` showed two open Dependabot action-update PRs: actions/checkout and github/codeql-action.
- `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection/required_status_checks` returned "Required status checks not enabled."
- `gh api repos/SysAdminDoc/SysAdminDoc/community/profile` returned health percentage 42 with no security policy, issue template, PR template, contributing file, or code of conduct.
- `gh api repos/SysAdminDoc/SysAdminDoc/codeowners/errors` returned no CODEOWNERS syntax errors.
- `gh run list` showed the latest scheduled OpenSSF Scorecard run failed on 2026-06-04.
- `gh run view --log-failed` showed Scorecard publish failed because the workflow has workflow-level write permissions while Scorecard publish restrictions require no workflow-level write permissions and only the Scorecard job may use `id-token: write`.
- Local toolchain observed: PowerShell 7.6.2, Pester 5.7.1, PSScriptAnalyzer 1.25.0.

External sources reviewed:

- GitHub profile README docs: https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
- GitHub repository README docs: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
- GitHub repository topics docs: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics
- GitHub Actions workflow syntax and path-filter behavior: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- GitHub Actions secure use reference: https://docs.github.com/en/actions/reference/security/secure-use
- GitHub workflow commands and job summaries: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- GitHub workflow artifacts docs: https://docs.github.com/en/actions/tutorials/store-and-share-data
- GitHub issue forms syntax: https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms
- GitHub protected branch REST docs: https://docs.github.com/en/rest/branches/branch-protection
- GitHub CODEOWNERS errors endpoint: https://docs.github.com/en/rest/repos/repos#list-codeowners-errors
- GitHub Dependabot options reference: https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference
- OpenSSF Scorecard action docs: https://github.com/ossf/scorecard-action
- JSON Schema keyword reference: https://json-schema.org/understanding-json-schema/keywords
- W3C SVG Accessibility API Mappings: https://www.w3.org/TR/svg-aam-1.0/
- Playwright screenshot docs: https://playwright.dev/docs/next/screenshots

Areas not fully verified:

- No full browser automation suite exists yet for the live GitHub-rendered page. The headless Chrome smoke was manual and temporary.
- The separate portfolio repo was not modified in this pass; portfolio findings are based on this repo's feed contract and prior recorded portfolio integration evidence.
- No GitHub settings were changed during research.

## Current Product Map

Core maintainer workflow:

- Maintain `data/profile-catalog.json` as the canonical catalog.
- Run `scripts/sync-profile.ps1 -Write -Check` to regenerate README, feed, SVG panels, and sync report from a single metadata snapshot.
- Validate with Pester, PSScriptAnalyzer, JSON Schema checks, metadata drift checks, link validation, release-asset drift checks, and doc version/date consistency checks.
- Use scheduled/manual workflows to check generated state and optionally open generated-profile pull requests.

Core visitor workflow:

- Land on `https://github.com/SysAdminDoc`.
- Read the GitHub account bio and profile README first viewport.
- Scan Professional Focus, Proof Points, Currently Building, Start Here, Catalog Snapshot, and Featured Projects.
- Expand categories to copy install commands, click release downloads, open live web apps, install userscripts, or visit repositories.
- Move to `https://sysadmindoc.github.io/` for the full searchable portfolio.

Current data model:

- `data/profile-catalog.json`: 187 catalog rows.
- `projects.json`: 177 public project rows, 9 suppressed rows, 184 active public repos, 71 release actions, 27 live links, 11 install actions, and 68 repo actions.
- One catalog row, `VaultBox`, is neither in `projects` nor `suppressed` because it has `includeInReadme=false`, `includeInPortfolio=false`, and no `suppressionReason`.
- `reports/profile-sync-report.json`: current report includes metadata hygiene, metadata drift, release asset drift, schema validation, doc consistency, profile asset sync, link validation performance, and README experience checks.

Important integrations:

- GitHub CLI and REST/GraphQL metadata.
- GitHub Releases and raw GitHub URLs.
- GitHub Actions, Scorecard, zizmor, PSScriptAnalyzer, Pester, Dependabot, CODEOWNERS.
- Committed local SVG panels under `assets/profile`.
- External profile chrome renderers for the capsule header/footer, typing SVG, and skill icons.

## Feature Inventory

### Generated Profile Catalog

- Name: Canonical profile catalog.
- User value: keeps 184 public repos represented through one curated source of truth.
- Entry point: `data/profile-catalog.json`.
- Main code locations: `Get-Catalog`, `ConvertTo-EntryHashtable`, `Get-RepoMeta`, `Get-PrimaryAction`, `New-Readme`, `New-ProjectsExportJson`.
- Current maturity: complete, active, schema-backed.
- Tests/docs coverage: Pester fixture coverage, schema validation, README/feed sync checks, ROADMAP/RESEARCH_REPORT history.
- Improvement opportunities: add explicit local-only or omitted-row reason fields, generated-feed provenance, and source-hash validation.

### Profile README Generator

- Name: Generated GitHub profile README.
- User value: accurate public profile and project catalog without manual count/link drift.
- Entry point: `scripts/sync-profile.ps1 -Write`.
- Main code locations: `New-Readme`, `Update-Header`, `New-DiscoverySection`, `New-FeaturedSection`, `New-CategorySection`, `New-FirstTimeSetupSection`, `New-ProfileStatsChrome`.
- Current maturity: complete, but live-render proof remains manual.
- Tests/docs coverage: `readmeExperienceChecks`, Pester output-shape tests, generated-catalog notice, sync report.
- Improvement opportunities: add live rendered smoke proof and mobile overflow guard.

### Public Projects Feed

- Name: `projects.json`.
- User value: public-safe source for the separate portfolio and any future catalog consumers.
- Entry point: raw GitHub `projects.json` URL.
- Main code locations: `New-ProjectsExportJson`, `schemas/profile-projects.v1.json`, `Test-FeedSchemaContracts`.
- Current maturity: complete and schema-backed.
- Tests/docs coverage: schema validation and Pester feed tests.
- Improvement opportunities: source ref, generator hash, catalog hash, metadata snapshot time, local-only/omitted-row accounting, and optional report schema.

### Profile SVG Panels

- Name: committed catalog stats, language mix, and release asset health panels.
- User value: first-viewport visual summary without third-party stats host dependence.
- Entry point: `assets/profile/*.svg`, embedded through `<picture>` in `README.md`.
- Main code locations: `New-ProfilePanelSvg`, `New-ProfileAssetSvgs`, `New-ProfileStatsChrome`.
- Current maturity: complete but partially undocumented for standalone accessibility.
- Tests/docs coverage: `profileAssetsInSync`, README experience checks, Pester coverage.
- Improvement opportunities: internal SVG `title` and `desc`, `aria-labelledby`, and `aria-describedby`.

### Release Asset Taxonomy

- Name: latest-release asset classification.
- User value: prevents release download labels from claiming an APK, EXE, ZIP, CRX, XPI, or generic download when latest assets do not match.
- Entry point: `scripts/sync-profile.ps1 -Check`, `projects.json.releaseAssetKinds`.
- Main code locations: `Add-ReleaseAssetMetadata`, `Get-ReleaseAssetKinds`, `Test-ReleaseAssetDrift`, `Get-PrimaryAction`.
- Current maturity: complete and useful.
- Tests/docs coverage: Pester, sync report.
- Improvement opportunities: source-only release follow-up for 17 rows and report-to-job-summary surfacing.

### Metadata Hygiene

- Name: public repo topic and description hygiene.
- User value: improves discoverability and reduces profile copy burden.
- Entry point: `reports/profile-sync-report.json.metadataHygiene`.
- Main code locations: `Test-MetadataHygiene`, `Get-TopicHints`.
- Current maturity: report-only, with 69 topicless repos and 0 missing descriptions.
- Tests/docs coverage: Pester and report.
- Improvement opportunities: reviewed allowlist apply mode for topics, plus a generated owner-facing checklist.

### Privacy and Suppression Guard

- Name: public-safe profile guard.
- User value: keeps private, hidden, superseded, and sensitive rows out of public project listings.
- Entry point: catalog `suppressionReason`, `allowPublicMedical`, `Test-ProfileState`.
- Main code locations: `Test-ProfileState`, `New-ProjectsExportJson`, `$MedicalPattern`.
- Current maturity: strong but one omitted row lacks explicit accounting.
- Tests/docs coverage: Pester and sync report.
- Improvement opportunities: report every catalog row state as project, suppressed, local-only, or invalid.

### Workflow Security and CI

- Name: generated-profile workflows and security lanes.
- User value: keeps profile output fresh, repeatable, and defended against workflow regressions.
- Entry point: `.github/workflows/*.yml`.
- Main code locations: `profile-sync.yml`, `assets-refresh.yml`, `tests.yml`, `workflow-security.yml`, `scorecard.yml`.
- Current maturity: good but incomplete.
- Tests/docs coverage: Pester, PSScriptAnalyzer, zizmor, Scorecard, Dependabot.
- Improvement opportunities: fix Scorecard publish failure, add PR profile-sync validation, add required status checks, timeouts, summaries, artifact retention, and workflow-action dependency grouping.

### First-Time Setup Bootstrapper

- Name: Windows first-time setup path.
- User value: lets visitors install Python/Git or inspect the installer before running profile snippets.
- Entry point: README First-time setup and `setup.ps1`.
- Main code locations: `setup.ps1`, `New-FirstTimeSetupSection`, README experience checks.
- Current maturity: complete and guarded by generated README checks.
- Tests/docs coverage: Pester setup guidance and script contract checks.
- Improvement opportunities: add a Windows CI smoke for `setup.ps1 -CheckOnly`.

### Public Planning Documents

- Name: public roadmap, completed work log, changelog, research report.
- User value: shows how the profile pipeline evolves and gives future implementers a backlog.
- Entry point: `ROADMAP.md`, `CHANGELOG.md`, `COMPLETED.md`, `RESEARCH_REPORT.md`.
- Main code locations: `Test-DocVersionConsistency`.
- Current maturity: useful but some stale terminology remains.
- Tests/docs coverage: version/date consistency gate.
- Improvement opportunities: stale field-name lint, current schema terminology sweep, and companion research pointers.

## Competitive and Ecosystem Research

| Product/source | Notable capabilities | What this project should learn | What to avoid |
|---|---|---|---|
| GitHub profile README docs | Public username-matching repo README renders on the profile | Keep the repo public, root README nonempty, and visitor-first | Treating the README as a dynamic app |
| GitHub topics | Topics improve repository discovery and show intended purpose | Convert report hints into reviewed topic cleanup | Bulk mutation without an allowlist |
| GitHub Actions workflow syntax | Path filters can skip workflows; skipped required checks can block merges | Use always-created required checks before branch protection | Requiring checks that are not created for docs/profile paths |
| GitHub secure use reference | Minimum token permissions, SHA-pinned actions, CODEOWNERS, Scorecard | Keep workflow permissions narrow and explain write jobs | Top-level write permissions where job-level permissions are enough |
| OpenSSF Scorecard action | Publish results requires strict workflow restrictions and OIDC | Fix current Scorecard failure before relying on score badges | Mixing publish mode with workflow-level write permissions |
| GitHub issue forms and PR templates | Structured intake for known issue types | Add broken-link, profile-correction, workflow-change, and security routing | Free-form issues that omit repo/action/evidence |
| GitHub workflow summaries/artifacts | Summaries expose high-signal results without log digging | Summarize sync report and upload screenshots/reports with retention | Forcing maintainers to download raw JSON for every run |
| JSON Schema | Rich keyword vocabulary beyond the current custom validator subset | Reject unsupported keywords or implement them intentionally | Silent success when a future schema uses `oneOf`, `if`, or `dependentRequired` |
| W3C SVG accessibility mappings | SVG `title` and `desc` contribute accessible names/descriptions | Add standalone metadata to generated SVG panels | Relying only on README wrapper alt text |
| Playwright screenshots | Repeatable screenshot capture for rendered pages | Use DOM assertions plus screenshots for live GitHub profile smoke | Brittle full-page pixel baselines against dynamic GitHub chrome |

## Highest-Value New Features

### P0 - Live GitHub-Rendered Profile Smoke

- User problem solved: source checks can pass while GitHub.com rendering still has mobile clipping, image failures, sanitizer changes, or table behavior regressions.
- Evidence: headless Chrome desktop/mobile smoke on 2026-06-05 found the expected profile sections, but the 390px mobile capture showed a horizontal scrollbar and clipped README text. `scripts/sync-profile.ps1 -Check` currently inspects source and generated patterns, not the actual GitHub-rendered surface.
- Proposed behavior: add a script or workflow job that loads `https://github.com/SysAdminDoc` after generated-profile changes, captures 390px and desktop screenshots, checks for no README-content horizontal overflow, confirms hero/Professional Focus/Proof Points/Currently Building/Start Here are visible in order, and uploads artifacts plus a summary.
- Implementation areas: new `scripts/render-profile-smoke.*` or `tests/rendered-profile-smoke.*`, `.github/workflows/profile-sync.yml`, `.github/workflows/assets-refresh.yml`, report artifacts.
- Data model/API/UI implications: optional smoke summary in `reports/profile-sync-report.json` or separate `reports/rendered-profile-smoke.json`.
- Risks and edge cases: GitHub navigation itself can create viewport scrollbars; assertions should target the README article/card rather than the whole page. Screenshots should be evidence artifacts, not brittle golden baselines.
- Verification plan: run the smoke locally with Chrome; dispatch workflow; confirm screenshots upload and a deliberately broken narrow table fails.
- Estimated complexity: M.
- Priority: P0.

### P0 - Scorecard Workflow Repair

- User problem solved: the repo advertises Scorecard hardening but the latest scheduled Scorecard run is red.
- Evidence: `gh run view --log-failed` for the 2026-06-04 scheduled run shows Scorecard publish rejected the workflow because write permissions are set at workflow level. `scorecard.yml` sets `security-events: write` and `id-token: write` at both workflow and job levels.
- Proposed behavior: remove workflow-level write permissions, keep `contents: read` at workflow level, move required write permissions to the Scorecard job only, and decide whether to keep `publish_results: true` or only upload SARIF/code scanning.
- Implementation areas: `.github/workflows/scorecard.yml`.
- Data model/API/UI implications: none.
- Risks and edge cases: Scorecard also reports classic branch-protection read limitations with the default token; if score accuracy matters, prefer repository rulesets or a documented token choice.
- Verification plan: manually dispatch Scorecard and confirm conclusion success, SARIF upload runs, and publish result is accepted or intentionally disabled.
- Estimated complexity: S.
- Priority: P0.

### P1 - Pull Request Generated-Profile Validation

- User problem solved: catalog, README, feed, report, schema, or setup changes can be opened as PRs without the full profile-sync gate running automatically.
- Evidence: `profile-sync.yml` currently runs only on `workflow_dispatch` and schedule. `tests.yml` path filters omit `data/**`, `README.md`, `projects.json`, `reports/**`, `schemas/**`, `assets/profile/**`, `docs/**`, and `profile-sync.yml`.
- Proposed behavior: add a PR-safe profile-sync validation workflow or event trigger for generated-profile contract paths, with a no-network fast lane and a full live lane when appropriate.
- Implementation areas: `.github/workflows/profile-sync.yml`, maybe a new `profile-contract.yml`.
- Data model/API/UI implications: none.
- Risks and edge cases: if this check becomes required, ensure it is always created for relevant PRs and does not hang as a skipped required check.
- Verification plan: open or simulate a PR touching only `data/profile-catalog.json`, only `schemas/profile-projects.v1.json`, and only `README.md`; verify the right check appears and fails on drift.
- Estimated complexity: M.
- Priority: P1.

### P1 - Required Status Checks or Rulesets

- User problem solved: strong checks exist but are not enforced before changes can land on `main`.
- Evidence: live branch protection has admin enforcement, force-push blocking, deletion blocking, and conversation resolution, but no required status checks.
- Proposed behavior: after PR checks are reliably created, require `Tests / Pester (offline)`, `PSScriptAnalyzer`, `Workflow security`, and generated-profile validation for relevant paths. Use rulesets if they better model path-specific requirements.
- Implementation areas: GitHub branch protection/rulesets settings, optional `ROADMAP.md` operator checklist.
- Data model/API/UI implications: none.
- Risks and edge cases: required checks plus path filters can block merges if a check is skipped; solve with always-created lightweight status jobs.
- Verification plan: `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection/required_status_checks` or rulesets API shows required checks; a failing PR cannot merge.
- Estimated complexity: M.
- Priority: P1.

### P1 - Public-Safe Community Intake

- User problem solved: visitors can find 177 projects but have no structured path to report broken install snippets, stale release links, profile copy corrections, or security issues.
- Evidence: community profile API reports no security policy, issue template, PR template, or contributing file. Issues, discussions, and wiki are enabled.
- Proposed behavior: add `SECURITY.md`, issue forms for broken catalog link and profile correction, and a PR template that tells contributors not to hand-edit generated sections. Decide whether discussions/wiki are useful or should be disabled to reduce unused surfaces.
- Implementation areas: `SECURITY.md`, `.github/ISSUE_TEMPLATE/*.yml`, `.github/pull_request_template.md`, GitHub repo settings.
- Data model/API/UI implications: issue forms should request repo name, action kind, observed link, expected behavior, and public-safe evidence.
- Risks and edge cases: security reports need a non-public contact path or clear private-reporting guidance; issue forms are not supported for PRs, so PR template remains separate.
- Verification plan: community profile health increases; issue template API lists forms; creating a draft issue shows required fields.
- Estimated complexity: S.
- Priority: P1.

### P1 - Catalog Row Accounting Report

- User problem solved: a catalog row can be omitted from both public projects and suppressed rows, making feed consumers unable to distinguish intentional local-only state from a mistake.
- Evidence: `VaultBox` is present in `data/profile-catalog.json` with `category=suppressed`, `includeInReadme=false`, `includeInPortfolio=false`, and `suppressionReason=null`, but is absent from both `projects.json.projects` and `projects.json.suppressed`.
- Proposed behavior: every catalog row must be exported as a public project, exported as a suppressed row, or counted in a public-safe `omittedCatalogRows`/`localOnlyRows` report section with an explicit reason.
- Implementation areas: `New-ProjectsExportJson`, `Test-ProfileState`, `reports/profile-sync-report.json`, optional schema if report schema is added.
- Data model/API/UI implications: `projects.json` can stay public-only; omitted accounting can live in report until a feed consumer needs it.
- Risks and edge cases: reasons must not expose private or sensitive details.
- Verification plan: add a fixture row with no public/suppressed/local-only reason and confirm `-Check` warns or fails.
- Estimated complexity: S.
- Priority: P1.

### P2 - Generated Feed Provenance

- User problem solved: downstream portfolio debugging cannot tell which commit, catalog hash, generator hash, or metadata snapshot produced a given feed.
- Evidence: `projects.json` exposes `generatedAt`, `source`, and counts, but no source ref or content hashes.
- Proposed behavior: add `sourceRef`, `sourceCommit`, `catalogSha256`, `generatorSha256`, `schemaVersion`, and `metadataSnapshotAt`, plus report checks that stale generated artifacts are traceable.
- Implementation areas: `New-ProjectsExportJson`, `Test-MetadataDrift`, schemas, portfolio consumer docs.
- Data model/API/UI implications: schema update required; downstream consumers can display or log feed provenance.
- Risks and edge cases: hashes should exclude nondeterministic fields and avoid private paths.
- Verification plan: regenerate twice from unchanged inputs and confirm stable hashes except snapshot timestamp; edit catalog and confirm catalog hash changes.
- Estimated complexity: M.
- Priority: P2.

### P2 - JSON Schema Validator Fail-Closed Mode

- User problem solved: future schemas can add JSON Schema keywords that the custom validator ignores, producing false confidence.
- Evidence: `Test-JsonSchemaNode` implements a subset. JSON Schema includes composition and conditional keywords such as `oneOf`, `anyOf`, `allOf`, `if`, `then`, and `dependentRequired`.
- Proposed behavior: recursively reject unsupported schema keywords with clear errors unless they are explicitly in the supported set, or implement the next needed keyword before schema authors use it.
- Implementation areas: `Test-JsonSchemaNode`, tests, schema authoring notes.
- Data model/API/UI implications: none, unless future schemas need richer keywords.
- Risks and edge cases: `title`, `description`, `$schema`, `$id`, and other annotations should be allowed as annotations, not rejected as constraints.
- Verification plan: create a fixture schema with `oneOf` that should reject bad data; current validator must fail with unsupported-keyword or real validation error.
- Estimated complexity: S.
- Priority: P2.

### P2 - Workflow Observability and Timeout Budget

- User problem solved: generated-profile and asset-refresh jobs produce useful JSON but require log or artifact digging; network jobs lack explicit timeout ceilings.
- Evidence: `profile-sync.yml` uploads the sync report, `assets-refresh.yml` currently does not upload a report artifact, neither writes `$GITHUB_STEP_SUMMARY`, and `rg "timeout-minutes" .github/workflows` finds none.
- Proposed behavior: every workflow writes a concise public-safe job summary, uploads report artifacts with retention, emits warnings/errors from report failures, and defines job/step timeouts appropriate to live network checks.
- Implementation areas: all `.github/workflows/*.yml`, optional summary helper in `scripts/`.
- Data model/API/UI implications: no schema change required; summary should redact suppressed/private row names where necessary.
- Risks and edge cases: job summary max size is 1 MiB; keep output compact.
- Verification plan: dispatch workflows; confirm summaries, artifacts, retention, and timeout declarations.
- Estimated complexity: S-M.
- Priority: P2.

## Existing Feature Improvements

### Metadata Hygiene Apply Path

- Current behavior: report shows 69 topicless public repos and generated topic hints; descriptions are clean.
- Problem or missed opportunity: report-only hints improve visibility but do not improve repository search until reviewed changes are applied.
- Recommended change: add a reviewed allowlist file and dry-run/apply helper that updates topics only for explicitly listed repos.
- Code locations likely affected: `reports/profile-sync-report.json`, optional `scripts/apply-topic-hints.ps1`, optional `docs/topic-cleanup-allowlist.md`.
- Backward compatibility concerns: topic changes affect other repos, so apply mode should never run implicitly in `-Check`.
- Verification plan: dry run prints intended topics; apply mode requires an allowlist and uses GitHub's 20-topic limit.
- Estimated complexity: M.
- Priority: P2.

### Source-Only Latest Releases

- Current behavior: 17 rows have latest releases but still render `Repo` actions because assets are source-only or not mapped to visitor-ready downloads.
- Problem or missed opportunity: some projects may have releasable assets but no visitor-facing action.
- Recommended change: classify the 17 rows into intentionally source-only, missing asset, or should-download. Keep source-only releases as `Repo` actions unless an asset is usable.
- Code locations likely affected: `data/profile-catalog.json`, `Test-ReleaseAssetDrift`, `README.md`, `projects.json`.
- Backward compatibility concerns: do not turn source archives into download buttons.
- Verification plan: report contains a stable source-only review section; any changed action passes release-asset drift checks.
- Estimated complexity: S-M.
- Priority: P2.

### CODEOWNERS Coverage

- Current behavior: CODEOWNERS syntax is clean and covers workflows, generator, tests, catalog, feed, and sync report.
- Problem or missed opportunity: schemas, setup script, generated SVG assets, and public planning docs are not covered.
- Recommended change: add entries for `schemas/`, `assets/profile/`, `setup.ps1`, `PSScriptAnalyzerSettings.psd1`, and major public docs as needed.
- Code locations likely affected: `.github/CODEOWNERS`.
- Backward compatibility concerns: broader CODEOWNERS only matters when review policy is enforced.
- Verification plan: `gh api repos/SysAdminDoc/SysAdminDoc/codeowners/errors` remains empty; PR touching each path requests the owner.
- Estimated complexity: S.
- Priority: P2.

### Dependabot Action Update Handling

- Current behavior: Dependabot has two open major action-update PRs and no grouping rule.
- Problem or missed opportunity: routine minor/patch action updates can create repetitive PRs, but major action updates still need individual security review.
- Recommended change: add Dependabot grouping for minor/patch GitHub Actions updates while keeping major action updates separate.
- Code locations likely affected: `.github/dependabot.yml`.
- Backward compatibility concerns: action references are SHA-pinned; any update still needs workflow-security review.
- Verification plan: next Dependabot run groups eligible routine updates and leaves major updates separate.
- Estimated complexity: S.
- Priority: P3.

### Public Planning Terminology

- Current behavior: `COMPLETED.md:9` still lists `privateReason` as a canonical catalog field.
- Problem or missed opportunity: the live schema uses `suppressionReason`, `allowPublicMedical`, `aliasOf`, `forkOf`, and `upstreamLicense`.
- Recommended change: update current-state/history docs so legacy field names are either removed or explicitly marked historical.
- Code locations likely affected: `COMPLETED.md`, optional `PROJECT_CONTEXT.md`, `RESEARCH_REPORT.md`.
- Backward compatibility concerns: do not rewrite old changelog history beyond clarifying current field names.
- Verification plan: `rg -n "privateReason" COMPLETED.md PROJECT_CONTEXT.md ROADMAP.md RESEARCH_REPORT.md` returns no unqualified current-field claims.
- Estimated complexity: S.
- Priority: P3.

### Standalone SVG Accessibility

- Current behavior: generated SVG panels include `role="img"` and `aria-label`, but no internal `title` or `desc`.
- Problem or missed opportunity: direct links to SVG assets and tooling exports are less self-describing than the README wrapper.
- Recommended change: generate stable IDs, internal `title`, internal `desc`, `aria-labelledby`, and `aria-describedby`.
- Code locations likely affected: `New-ProfilePanelSvg`, `assets/profile/*.svg`, tests.
- Backward compatibility concerns: keep README `img alt` concise and do not duplicate a long description in the wrapper.
- Verification plan: regenerate assets and scan all SVG files for `title`, `desc`, `aria-labelledby`, and `aria-describedby`.
- Estimated complexity: S.
- Priority: P3.

## Reliability, Security, Privacy, and Data Safety

- Scorecard is currently failing. This is a reliability and trust issue because the workflow exists but the latest scheduled run is red.
- Branch protection is partially configured but required status checks are absent. The repo should not enforce path-filtered checks until the checks are always created for relevant PRs.
- Vulnerability alerts are disabled according to the GitHub API response. If Dependabot alerts are intended, enable and document them.
- No `SECURITY.md` exists. Scorecard flags this and visitors have no clear path for private security reports.
- Issues, discussions, and wiki are enabled. If they are not intentionally used, disable discussions/wiki or add guidance so public support surfaces stay predictable.
- Default workflow token permission is read-only, which is good. Write permissions should stay job-level and exact.
- Actions are SHA-pinned, which aligns with GitHub secure-use guidance. Dependabot update PRs should retain security review because SHA changes are meaningful.
- The public feed currently has one unaccounted catalog row. That should be a reportable state before more consumers depend on the feed.
- Topic mutation across other repos is a data safety concern. Keep topic cleanup reviewed and allowlisted.
- Live render screenshots should be artifacts, not committed large binaries, unless a later visual baseline workflow needs versioned references.

## UX, Accessibility, and Trust

- The README source has strong plain-text first-viewport content and meaningful image alt text after v4.9.x work.
- The live desktop capture shows the profile account bio and README positioning are both visible, but the account bio and README positioning are not identical. This may be acceptable, but it is a trust/positioning decision.
- The mobile capture shows clipped first-viewport README text and a horizontal scrollbar. The live-render smoke should distinguish GitHub's own tab overflow from README content overflow.
- The capsule header in the dark desktop capture appears visually low-information compared with the plain-text tagline. Consider simplifying or reducing its prominence if screenshots confirm it adds little value.
- The generated README comment marker is present in source but not visible in the live DOM, as expected for comments. Do not depend on rendered comments as maintainer guidance.
- The Start Here table and Catalog Snapshot are useful above-the-fold routing, but they need live mobile verification after any table/layout change.
- The profile feed now powers downstream discovery. Keep suppressed/local-only rows out of public search indexes.
- Internal SVG `title`/`desc` will improve standalone accessibility for committed panels.

## Architecture and Maintainability

- `scripts/sync-profile.ps1` is comprehensive but large. The current split into functions is usable, but future high-risk work should preserve the existing helper boundaries instead of introducing a new framework.
- The generator already handles GitHub API fallback, release asset inspection, JSON schema validation, metadata drift, link probes, and doc consistency. New features should extend these checks rather than duplicate them in separate scripts.
- The custom JSON Schema validator is a useful local dependency-saving choice, but it now needs unsupported-keyword detection because schemas are becoming real public contracts.
- `projects.json` is becoming an external API. Provenance fields and report schema will matter more as the portfolio and other tools consume it.
- Workflows duplicate generated PR creation logic across profile sync and asset refresh. A shared PowerShell helper is safer than a local composite action until local action workflow coverage is added.
- Public planning files are large and active. Companion research docs should stay additive and should not rewrite `ROADMAP.md` unless implementing a concrete queued item.

## Prioritized Roadmap

- [x] P0 - Repair the OpenSSF Scorecard workflow
  - Why: the latest scheduled Scorecard run failed, undermining the repository security signal.
  - Evidence: `scorecard.yml` has workflow-level write permissions; failed run log says Scorecard publish rejects workflow-level write permissions.
  - Touches: `.github/workflows/scorecard.yml`.
  - Acceptance: scheduled/manual Scorecard run completes successfully; SARIF upload still works or publish mode is intentionally disabled.
  - Verify: `gh run view -R SysAdminDoc/SysAdminDoc <scorecard-run> --json conclusion,jobs`.
  - Completed: v4.9.26 moved workflow-level permissions to read-only, kept Scorecard publish/SARIF writes at job level, and added offline Pester regression coverage for the permission shape. A new GitHub Actions run is still needed to prove the hosted scheduled/manual workflow conclusion.

- [x] P0 - Add live GitHub-rendered profile smoke
  - Why: source checks do not prove GitHub.com mobile/desktop rendering.
  - Evidence: 2026-06-05 headless Chrome mobile screenshot showed horizontal scrollbar and clipped first-viewport README text.
  - Touches: new render-smoke script, `.github/workflows/profile-sync.yml`, `.github/workflows/assets-refresh.yml`, optional report JSON.
  - Acceptance: desktop and 390px mobile screenshots upload; README content has no horizontal overflow; key sections render in order.
  - Verify: dispatch workflow and inspect artifacts plus summary.
  - Completed: v4.9.27 added `scripts/render-profile-smoke.ps1`, wired it into `profile-sync.yml`, ignored local smoke artifacts, and added offline Pester wiring coverage. Local smoke passed for desktop and 390px mobile with no missing sections, failed images, or overflow.

- [x] P1 - Run generated-profile validation on PRs
  - Why: catalog/feed/schema/profile paths can change without an automatic full profile-sync status.
  - Evidence: `profile-sync.yml` is schedule/manual only; `tests.yml` path filters omit several generated-profile contract paths.
  - Touches: `.github/workflows/profile-sync.yml` or new `profile-contract.yml`.
  - Acceptance: PRs touching catalog, README, projects feed, schemas, reports, setup, profile assets, or profile workflows get a generated-profile validation check.
  - Verify: open a scratch PR touching each path class and confirm checks appear.
  - Completed: v4.9.28 added a read-only `pull_request` trigger to `profile-sync.yml` for the generated profile contract surface and Pester coverage for the path list. A scratch PR remains the hosted end-to-end confirmation.

- [ ] P1 - Require validated checks on `main`
  - Why: strong checks are not enforced by required status checks.
  - Evidence: required status checks endpoint returns "Required status checks not enabled."
  - Touches: GitHub branch protection/ruleset settings, optional docs.
  - Acceptance: required checks block bad PRs, and path-skipped checks do not leave required statuses pending.
  - Verify: branch protection or rulesets API shows required checks.

- [ ] P1 - Add public-safe intake files
  - Why: the repo has no security policy, issue template, PR template, or contributing file.
  - Evidence: community profile API health 42 and missing files.
  - Touches: `SECURITY.md`, `.github/ISSUE_TEMPLATE/*.yml`, `.github/pull_request_template.md`, optional `CONTRIBUTING.md`.
  - Acceptance: community profile detects the files; issue forms guide broken-link/profile-correction reports.
  - Verify: `gh api repos/SysAdminDoc/SysAdminDoc/community/profile`.

- [ ] P1 - Account for omitted catalog rows
  - Why: every catalog row should have an explicit public/feed state.
  - Evidence: `VaultBox` is absent from both `projects` and `suppressed`.
  - Touches: `scripts/sync-profile.ps1`, `reports/profile-sync-report.json`, tests.
  - Acceptance: report lists local-only/omitted rows with public-safe reasons or fails missing reasons.
  - Verify: fixture row without reason causes `-Check` warning/failure.

- [ ] P2 - Add generated-feed provenance
  - Why: downstream consumers need to debug stale or mismatched feed artifacts.
  - Evidence: `projects.json` lacks commit/hash provenance.
  - Touches: `New-ProjectsExportJson`, schemas, tests, portfolio notes.
  - Acceptance: feed includes source commit and stable content hashes; schema validates them.
  - Verify: regenerate twice and compare hash stability.

- [ ] P2 - Fail closed on unsupported schema keywords
  - Why: future schemas can silently skip constraints in the custom validator.
  - Evidence: validator implements a subset; JSON Schema has many unsupported composition/conditional keywords.
  - Touches: `Test-JsonSchemaNode`, tests.
  - Acceptance: unsupported constraint keywords fail clearly unless explicitly allowed as annotations.
  - Verify: Pester fixture with unsupported `oneOf` or `if` fails.

- [ ] P2 - Add workflow summaries, artifacts, and timeouts
  - Why: maintainers need high-signal workflow evidence without log digging or unbounded network waits.
  - Evidence: no `GITHUB_STEP_SUMMARY` usage and no `timeout-minutes` in workflows.
  - Touches: `.github/workflows/*.yml`, optional summary helper.
  - Acceptance: workflows show concise summaries, explicit timeouts, artifacts with retention, and warning/error annotations.
  - Verify: dispatch each workflow and inspect summaries/artifacts.

- [ ] P2 - Add reviewed topic cleanup apply mode
  - Why: 69 public repos still lack topics.
  - Evidence: live metadata and metadata hygiene report.
  - Touches: optional helper script, allowlist, report.
  - Acceptance: dry-run lists suggested topics; apply mode requires an allowlist and mutates only listed repos.
  - Verify: run dry-run; apply to one low-risk repo; confirm topics through GitHub API.

- [ ] P3 - Refresh stale public planning terminology
  - Why: current docs still mention a legacy catalog field name.
  - Evidence: `COMPLETED.md:9` lists `privateReason`; live schema uses `suppressionReason`.
  - Touches: `COMPLETED.md`, optional docs lint.
  - Acceptance: current-state docs use schema-backed field names.
  - Verify: `rg -n "privateReason" COMPLETED.md PROJECT_CONTEXT.md ROADMAP.md RESEARCH_REPORT.md`.

- [ ] P3 - Add standalone SVG accessibility metadata
  - Why: committed SVG panels should be self-describing when opened outside the README.
  - Evidence: `assets/profile/*.svg` have no internal `title` or `desc`.
  - Touches: `New-ProfilePanelSvg`, generated SVG assets, tests.
  - Acceptance: each SVG has stable `title`, `desc`, `aria-labelledby`, and `aria-describedby`.
  - Verify: scan `assets/profile/*.svg` after `-Write`.

- [ ] P3 - Mark generated artifacts for review ergonomics
  - Why: generated feed, report, and SVG churn can dominate PR diffs.
  - Evidence: `projects.json` is large and SVG/report files are fully generated.
  - Touches: `.gitattributes`.
  - Acceptance: `projects.json`, `reports/profile-sync-report.json`, and `assets/profile/*.svg` are marked generated for GitHub linguist; README remains reviewable.
  - Verify: GitHub PR diff collapses generated artifacts.

- [ ] P3 - Group routine Dependabot action updates
  - Why: routine minor/patch action updates can be reviewed together while major updates stay separate.
  - Evidence: two open major Dependabot action PRs; `.github/dependabot.yml` has no grouping.
  - Touches: `.github/dependabot.yml`.
  - Acceptance: minor/patch GitHub Actions updates group; major updates remain individual.
  - Verify: next Dependabot run behavior.

## Quick Wins

- Fix `scorecard.yml` workflow-level write permissions.
- Add `SECURITY.md`.
- Add a broken-link issue form and profile-correction issue form.
- Add `.github/pull_request_template.md` warning contributors not to hand-edit generated sections.
- Add `schemas/**`, `data/**`, `README.md`, `projects.json`, `reports/**`, and `assets/profile/**` to a PR validation trigger.
- Add `timeout-minutes` to all workflow jobs.
- Add `$GITHUB_STEP_SUMMARY` output from `reports/profile-sync-report.json`.
- Add `VaultBox` omission accounting.
- Replace `privateReason` in current-state docs.
- Add `.gitattributes` for generated feed/report/SVG files.

## Larger Bets

- Live rendered profile smoke with screenshot artifacts and DOM overflow checks.
- Required status checks/rulesets that work correctly with path-specific checks.
- Feed provenance and report schema versioning.
- Topic cleanup allowlist across public repositories.
- Shared generated PR creation helper for profile sync and asset refresh workflows.
- Optional portfolio-facing fields for freshness, provenance, and trust metadata.

## Explicit Non-Goals

- Do not put JavaScript search or filtering inside the GitHub profile README. Keep interactivity on the portfolio site.
- Do not replace the generated catalog with a generic profile README template.
- Do not mutate topics or settings across other repositories without an explicit reviewed allowlist.
- Do not mark the whole README as generated in `.gitattributes`; generated artifact hints should start with feed/report/SVG files.
- Do not rely on screenshot pixel baselines for GitHub's full page chrome. Use DOM assertions plus screenshots as evidence.
- Do not rename existing public repositories only to resolve naming debt; preserve links, stars, releases, and install snippets.

## Open Questions

- Should generated-profile validation run against PR branches through GitHub's Markdown API, live GitHub.com only after push, or both?
- Should Scorecard publish results remain enabled, or is SARIF/code scanning evidence enough for this profile repo?
- Should discussions and wiki remain enabled for this repository, or should support intake be limited to structured issues?
- Should `VaultBox` be exported as a suppressed row with a public-safe reason, or tracked as a local-only/omitted row in the report?
- Which topic taxonomy should be canonical for the reviewed topic cleanup: catalog category, generated `topicHints`, or a separate allowlist?
