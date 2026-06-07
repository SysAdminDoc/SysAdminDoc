# SysAdminDoc Profile Roadmap

> Single source of truth for all planned work. Items above the --- are existing plans; items below are research conducted 2026-06-03.

Last research refresh: 2026-06-07
Evidence bundle: `RESEARCH_REPORT.md` (latest source: `docs/research-feature-plan-2026-06-05.md`)
Latest profile sync: 2026-06-07
Current repo version: v4.9.99
Research baseline HEAD: `3d4ed8f Release v4.7.0 -- catalog refresh, drop private-repo refs`
P0 implementation baseline: `1fe3830 Consolidate profile research roadmap`

> Last researched: Cycle 107 - 2026-06-07.

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

Last researched: Cycle 107 - 2026-06-07.

2026-06-07 v4.9.99 refresh: generated PR dry-run evidence refreshed after
workflow-runtime hardening. Cycle 107 dispatched hosted Profile sync run
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27084524165` in
`dry-run-pr` mode on `main` at
`f6cd6b970a1d92c5a13cac2b1c9abac031fab257`. The run completed
`Regenerate profile`, wrote the sync summary, uploaded the report artifact
through the reviewed Node 24 `actions/upload-artifact` SHA, and reached
`Preview pull request`, where the helper planned
`automation/profile-sync-27084524165` without creating a branch, commit, push,
pull request, or validation dispatch. Required-check enforcement still waits on
live PR delivery or an approved bypass plus recent required-check proof.

2026-06-07 v4.9.98 refresh: workflow summary size budget guard shipped.
Cycle 106 audited the delivery-health path for `GITHUB_STEP_SUMMARY` output
after GitHub's workflow-command documentation confirmed a 1 MiB per-step job
summary limit. `scripts/write-profile-sync-summary.ps1` now measures the
generated Markdown before writing it, fails before the hard limit, and warns
above a 65536-byte local soft budget. Pester now verifies the committed profile
sync summary stays below that soft budget; the current summary is about 3.5 KiB.

2026-06-07 v4.9.97 refresh: artifact upload action Node 24 readiness
shipped. Cycle 105 reviewed the hosted Node.js 20 deprecation path for
retained workflow artifacts, confirmed the previous `actions/upload-artifact`
4.6.2 SHA runs on `node20`, and pinned profile-sync/profile-assets uploads to
the reviewed 6.0.0 SHA `b7c566a772e6b6bfb58ed0dc250532a479d7789f`, whose
action metadata runs on `node24`. Pester now guards all five retained artifact
upload uses, rejects floating `actions/upload-artifact@v*` tags, and rejects the
older Node 20 SHA.

2026-06-07 v4.9.96 refresh: deterministic report-row coverage extended.
Cycle 104 audited report aggregate arrays that are already sorted in
`scripts/sync-profile.ps1` but lacked exact-order regression tests. Pester now
asserts deterministic ordering for `releaseAssetDrift.releaseAssetKindCounts`,
`releaseAssetDrift.releaseTrustLevelCounts`, and
`portfolioCompatibility.primaryActionKindCounts`, covering the release taxonomy,
release trust, and downstream portfolio action summaries that appear in the
sync report and Actions summary.

2026-06-07 v4.9.95 refresh: approved portfolio-only catalog mutation
shipped. The 11 rows approved in
`docs/decisions/2026-06-07-portfolio-only-demotion-review.md` now have
`includeInReadme=false` and `includeInPortfolio=true`: `CSV_Power_Tool`,
`Flux`, `PillSleepTracker`, `UniversalCompiler`, `GmailDownloader`,
`bypassnroGen`, `LipSight`, `PDFedit`, `QR-Code-Generator-Pro`,
`Stock-Video-Collector`, and `Tunerize`. `scripts/sync-profile.ps1 -Write
-Check` regenerated `README.md`, `projects.json`, profile SVGs, and the sync
report; the README now has 166 project rows, Python is at the 30-row soft
limit, `readmeDensity.portfolioOnlyCandidateCount=0`, and
`routingRecommendation=keep-readme-routing-surface`. The portfolio feed still
exports all 177 visible projects, including all 11 demoted rows. Pester now
guards the catalog flags, feed preservation, and generated README removal.

2026-06-07 v4.9.94 refresh: portfolio-only demotion decision
shipped. `docs/decisions/2026-06-07-portfolio-only-demotion-review.md`
approves the current 11 reviewed README density candidates for a future staged
catalog mutation: `CSV_Power_Tool`, `Flux`, `PillSleepTracker`,
`UniversalCompiler`, `GmailDownloader`, `bypassnroGen`, `LipSight`, `PDFedit`,
`QR-Code-Generator-Pro`, `Stock-Video-Collector`, and `Tunerize`. The decision
records that this pass does not mutate the catalog, README, or feed; it
approves only a later catalog change for the named rows. Pester guards the
approved repo list, no-mutation boundary, and preview evidence.

2026-06-07 v4.9.93 refresh: hosted generated PR dry-run success evidence
shipped. Hosted workflow-dispatch run
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27083372279` ran on
`main` at `2e2d2e2b35e5dd9475748978de0b9a82bb738699` and completed the
`Preview generated README PR` job successfully. The run passed `Regenerate
profile`, wrote the sync summary, uploaded the report artifact, and reached
`Preview pull request`, where the dry-run helper planned
`automation/profile-sync-27083372279` and confirmed no branch, commit, push,
pull request, or validation dispatch would be created. The committed evidence
now records `conclusion=success`, `previewStepReached=true`, and no failed
step. Required-check enforcement still waits on live PR delivery or an approved
bypass plus recent required-check proof.

2026-06-07 v4.9.92 refresh: hosted profile-check success exit hardening
shipped. `scripts/sync-profile.ps1 -Check` now exits explicitly with status 0
after successful report validation, preventing a handled native-command failure
from leaking into the hosted PowerShell process status after the report has
already passed. Pester now guards this entrypoint behavior. The next hosted
`dry-run-pr` run should reach the preview helper if no separate generated PR
preview issue remains.

2026-06-07 v4.9.91 refresh: generated PR dry-run evidence reporting
shipped. `repositorySettings.requiredCheckReadiness.prDeliveryTransition` now
records the manual hosted `dry-run-pr` run from
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27082852047`,
including workflow-dispatch mode, `main` head SHA, failure conclusion, failed
`Regenerate profile` step, skipped preview state, uploaded report-artifact
state, and follow-up action. The profile sync summary surfaces the dry-run
conclusion and failed preview step. Required-check enforcement remains blocked:
the hosted run captured useful evidence, but it did not prove generated PR
delivery because the preview helper was not reached.

2026-06-07 v4.9.90 refresh: deterministic aggregate report ordering
shipped. Report rows generated from hash tables now flow through explicit
key-based sorting before JSON serialization, avoiding live-snapshot churn from
PowerShell hashtable value enumeration. The first stabilized rows are
`projectLicenseMetadata.licenseCounts` and
`staleProjectReview.suppressionReasonCounts`, with Pester coverage asserting
exact order for both aggregate arrays.

2026-06-07 v4.9.89 refresh: catalog-backed README candidate review notes
shipped. `data/profile-catalog.json` now supports optional
`readmeReviewNote` entries for internal README review context without exporting
those notes to `projects.json`. The 11 current Python portfolio-only review
candidates carry the note, and `readmeDensity.portfolioOnlyCandidates` now
surfaces it as `catalogReviewNote` in the sync report with schema and Pester
coverage. README inclusion and portfolio-feed inclusion are unchanged.

2026-06-07 v4.9.88 refresh: generated PR delivery dry-run helper
shipped. `scripts/open-generated-profile-pr.ps1 -DryRun` now reports the
planned generated branch, base branch, commit message, PR title, validation
workflow/mode, validation-run URL, missing CI environment, and changed
generated paths, then exits before branch creation, commit, push, PR creation,
or validation dispatch. The manual Profile sync workflow now exposes
`dry-run-pr` as a read-only workflow-dispatch mode that regenerates the
profile, uploads the report, and calls the helper with `-DryRun`. Pester guards
the side-effect-free contract and the workflow permissions. Required-check
enforcement remains blocked until direct-main delivery is replaced by real PR
delivery or an approved bypass.

2026-06-07 v4.9.87 refresh: portfolio-only catalog review preview
reporting shipped. `readmeDensity.portfolioOnlyPreview` now records a
report-only demotion preview for the selected candidates, including candidate
source, repo list, current and preview README row counts, row delta, category
soft-limit resolution, portfolio-route preservation, and explicit
`catalogMutated=false`, `readmeMutated=false`, and `projectsFeedMutated=false`
flags. Current preview evidence shows the 11 Python candidates would reduce
README project rows from 177 to 166, reduce Python rows from 41 to the 30-row
soft limit, resolve 1 over-limit category, and leave portfolio routes
available. The profile sync summary surfaces preview status, row delta,
preview row count, and remaining over-limit category count.

2026-06-07 v4.9.86 refresh: concrete README portfolio-only review
candidate reporting shipped. `readmeDensity` now includes
`portfolioOnlyCandidateSelectionPolicy` plus `portfolioOnlyCandidates`, a
deterministic list of non-featured, non-currently-building repo-only rows that
still have portfolio routes. Current Python review candidates are
`CSV_Power_Tool`, `Flux`, `PillSleepTracker`, `UniversalCompiler`,
`GmailDownloader`, `bypassnroGen`, `LipSight`, `PDFedit`,
`QR-Code-Generator-Pro`, `Stock-Video-Collector`, and `Tunerize`. The profile
sync summary now surfaces a short candidate sample, and Pester/schema coverage
guards the selected row shape without changing generated README inclusion yet.

2026-06-07 v4.9.85 refresh: PR-delivery transition checklist
shipped. `repositorySettings.requiredCheckReadiness.workflowCoverage` now
records candidate required-check workflow coverage across Tests, Profile sync,
and Workflow security. `prDeliveryTransition` records a five-item checklist for
candidate checks, PR/merge-queue workflow coverage, recent check-run proof, PR
delivery or bypass, and enforcement mechanism selection. Current state remains
intentionally blocked for required-check enforcement: candidate checks and
workflow coverage are ready, but recent check-run proof needs live validation,
and direct-main delivery with `enforce_admins=true` must be replaced by PR
delivery or a tested bypass. `docs/decisions/2026-06-07-pr-delivery-transition-checklist.md`
records the activation order, and the profile sync summary surfaces transition
status, blockers, and live-validation counts.

2026-06-06 v4.9.84 refresh: generated artifact/render-budget reporting
shipped. The sync report now includes `artifactBudgets` with 10 soft-budget
rows for README bytes, lines, table rows, details sections, image tags, code
blocks, `projects.json` bytes, sync-report bytes, profile-SVG bytes, and
profile-SVG file count. `scripts/render-profile-smoke.ps1` now patches
`reports/profile-sync-report.json.renderedProfileSmoke` after live smoke runs.
Current status is healthy: artifact budgets are `within-budget` with 0 warnings,
the rendered profile smoke is `passed` across 2 viewports with 0 warnings, and
the mobile root width is 308 px. The profile sync summary surfaces the budget
and smoke status fields, and Pester covers budget calculation, smoke
aggregation, schema contract, and summary wiring.

2026-06-06 v4.9.83 refresh: README density routing decision reporting
shipped. The sync report now extends `readmeDensity` with
`routingRecommendation`, portfolio-only candidate counts, per-category
soft-limit overflow counts, and category-level routing recommendations. Current
v4.9.95 evidence keeps the README as the public routing surface and records
`keep-readme-routing-surface` after the approved Python demotion set brought
Python to the 30-row soft limit. `docs/decisions/2026-06-06-readme-density-routing.md`
records the original decision, the profile sync summary surfaces the
recommendation and candidate count, and Pester guards the generated fields plus
summary wiring.

2026-06-06 v4.9.82 refresh: required-check readiness reporting shipped.
The sync report now includes `repositorySettings.requiredCheckReadiness` with
the six candidate required checks, live branch-protection required-status-check
state, repository ruleset count, admin-enforcement state, activation
recommendation, and blocker list. Current live evidence remains non-enforcing:
branch protection does not require status checks, repository rulesets and
active branch rules are empty, and protected `main` still enforces admins, so
the recommendation remains `defer-until-pr-delivery-or-bypass`. The profile
sync summary surfaces readiness status, candidate count, and blocker count,
and Pester guards the candidate list, report schema, decision note alignment,
and summary wiring.

2026-06-06 v4.9.81 refresh: REST fallback release-fetch state reporting
shipped. The sync report now records `validationPerformance.restFallbackReleaseFetch`
so a GraphQL metadata run says `not-used`, while future REST fallback runs
preserve the configured authenticated/unauthenticated release-fetch caps, repo
count, attempted and successful latest-release calls, 404 no-release count, and
fatal abort details. The summary helper surfaces fallback status, attempts, and
404 counts, and Pester guards HTTP-status parsing, the reportable state object,
the default GraphQL/offline not-used path, and summary wiring.

2026-06-06 v4.9.80 refresh: portfolio feed compatibility reporting shipped.
The sync report now includes `portfolioCompatibility`, a downstream-facing
snapshot for the public `projects.json` feed before future shape changes. It
checks the visible project fields the portfolio importer depends on, validates
top-level project/suppression counts, confirms redacted suppressed rows do not
expose project-identifying fields, records provenance and `releaseTrust`
availability, and summarizes primary action counts. The profile sync summary
surfaces compatibility status, fatal gaps, and warnings, while Pester guards
compatible rows, missing required fields, and suppressed-row leak regressions.

2026-06-06 v4.9.79 refresh: code-scanning posture recorded.
The repository baseline report now expands
`repositorySettings.security.codeScanning` with inspected languages,
CodeQL-supported-language detection, local workflow evidence, active controls,
and the current PowerShell-only `not-applicable-powershell-only`
recommendation. `docs/decisions/2026-06-06-code-scanning-posture.md` records
that missing CodeQL is not a misconfiguration while the live language mix has
no CodeQL-supported source language. The profile sync summary surfaces the
posture, and Pester guards the current no-CodeQL workflow stance plus the
future warning path when a supported language appears.

2026-06-06 v4.9.78 refresh: README density reporting shipped.
The sync report now includes `readmeDensity`, recording generated README line
count, details-section count, project table rows, per-category project counts,
repo-only rows, and low-signal zero-star repo-only rows. The current density
audit is warning-only and gives the next portfolio-only browsing pass measured
inputs instead of hand-counted Markdown. The profile sync summary surfaces the
density warning count, largest category, and repo-only row count, and Pester
guards the calculator, schema contract, and summary helper.

2026-06-06 v4.9.77 refresh: required-check enforcement readiness recorded.
The current candidate required checks are `Pester (offline)`,
`PSScriptAnalyzer`, `Markdownlint`, `Windows setup smoke`,
`Check generated README`, and `zizmor`. Enforcement is still intentionally not
enabled while protected `main` has `enforce_admins=true` and this loop pushes
directly to `main`; `docs/decisions/2026-06-06-required-check-enforcement-readiness.md`
now records the activation preconditions, candidate check list, and live API
evidence. Pester guards the decision note so future cleanup does not turn the
external-gated item into an undocumented repository-setting change.

2026-06-06 v4.9.76 refresh: obsolete Dependabot PR #7 closed.
After the CodeQL upload-sarif 4.36.2 SHA landed on `main`, Dependabot PR #7
remained open and unstable with the same one-file diff. The branch was closed
as obsolete with a note pointing at `c18bd58` and the matching Pester/docs
updates. Branch-protection/ruleset status-check enforcement remains
external-gated while this loop pushes directly to `main`.

2026-06-06 v4.9.75 refresh: routine CodeQL upload-sarif update applied.
Dependabot PR #7's `github/codeql-action/upload-sarif` 4.36.2 SHA is applied
directly on `main`, and Pester now guards against reverting to either the
4.36.1 SHA from PR #6 or the older 3.35.5 SHA. The PR branch failures were the
expected pinned-SHA test mismatch plus stale generated profile state on the
Dependabot branch. Branch-protection/ruleset status-check enforcement remains
external-gated while this loop pushes directly to `main`.

2026-06-06 v4.9.74 refresh: stale duplicate roadmap rows reconciled.
Unchecked duplicate rows for Windows setup smoke, CI validation tool pins,
public-repo enumeration limits, generated-artifact `.gitattributes`, generated
automation branch cleanup, and suppressed-feed redaction are now closed against
their shipped evidence. Pester now guards those reconciliations and the current
branch-protection evidence. Branch-protection/ruleset status-check enforcement
remains external-gated while this loop pushes directly to `main`; live PR #7
currently shows the candidate check set including `Markdownlint`.

2026-06-06 v4.9.73 refresh: markdownlint guard shipped.
The generated README-safe markdownlint leg now runs through `markdownlint-cli2`
0.22.1 pinned in `package.json`/`package-lock.json`; `.markdownlint-cli2.yaml`
allowlists the GitHub README constructs the generator intentionally emits while
keeping the broader Markdown corpus linted. `tests.yml` has a pinned
`actions/setup-node` v6.4.0 SHA, a `Markdownlint` job, and direct-push path
coverage for Markdown/config/lockfile changes. `New-Readme` also stops emitting
a duplicate blank line before the generated footer. Branch-protection/ruleset
status-check enforcement remains external-gated while this loop pushes directly
to `main`; continue with the next non-blocked research/maintenance item.

2026-06-06 v4.9.72 refresh: stale-project/archive-review report shipped.
`reports/profile-sync-report.json.staleProjectReview` now summarizes
visitor-facing stale/archive review candidates from `pushedAt` age and
latest-release age, while suppressed catalog rows are grouped only by public
reason code and visibility class. The profile sync summary surfaces stale and
archive-review counts, and Pester covers the helper, public-safe suppression
grouping, schema contract, and summary wiring. Branch-protection/ruleset
status-check enforcement remains external-gated while this loop pushes directly
to `main`; continue with the next non-blocked research/maintenance item.

2026-06-06 v4.9.71 refresh: profile render-host decision recorded.
`docs/decisions/2026-06-06-profile-render-hosts.md` now records that the
current profile retains no live third-party render, metric, or badge hosts;
the retained-host decision item is closed against the v4.9.47 local-SVG
migration and current `readmeExperienceChecks` zero-host report fields. Any
future external render-host reintroduction must document host purpose, visitor
exposure, fallback, removal trigger, and generator/report allowlist. Pester
guards the decision note against the current report state. Branch-protection/
ruleset status-check enforcement remains external-gated while this loop pushes
directly to `main`; continue with the next non-blocked research/maintenance
item.

2026-06-06 v4.9.70 refresh: repository formatting contract tightened.
`.editorconfig` now applies LF, final-newline, and trailing-whitespace trimming
across Markdown too; `.gitattributes` pins itself plus `.editorconfig` to LF,
the pull-request template no longer uses trailing-space placeholder bullets,
and Pester guards both the formatting contract and tracked Markdown
trailing-whitespace state. Branch-protection/ruleset status-check enforcement
remains external-gated while this loop pushes directly to `main`; continue with
the retained third-party render-host decision note.

2026-06-06 v4.9.69 refresh: completed-work catalog field terminology shipped.
`COMPLETED.md` now points the catalog row contract at
`schemas/profile-catalog.v1.json` and names the current suppression, public
medical allowlist, alias, fork/upstream, and notes fields instead of the legacy
`privateReason` field. Pester guards the completed-work summary against
reintroducing that stale current-field wording. Branch-protection/ruleset
status-check enforcement remains external-gated while this loop pushes directly
to `main`.

2026-06-06 v4.9.68 refresh: generated profile SVG metadata wiring shipped.
All generated profile SVG assets now use stable `<title>`/`<desc>` IDs wired
through `aria-labelledby` and `aria-describedby`; stats/language/activity panel
descriptions summarize their generated rows, and Pester coverage parses SVG XML
to guard metadata wiring plus escaping. Branch-protection/ruleset status-check
enforcement remains external-gated while this loop pushes directly to `main`;
continue with stale catalog field names in completed-work docs.

2026-06-06 v4.9.67 refresh: Dependabot routine action grouping shipped.
`.github/dependabot.yml` now groups GitHub Actions minor and patch updates into
`routine-actions` while leaving major action updates separate for individual
review. Pester guards the grouping shape and rejects accidental inclusion of
major updates in the routine group. Next highest open item:
branch-protection/ruleset status-check enforcement remains external-gated while
this loop pushes directly to `main`; continue with internal title/description
metadata for generated profile SVG panels.

2026-06-06 v4.9.66 refresh: schema-trigger coverage shipped.
`tests.yml` now includes `schemas/**` in the push path filter for direct
`main` updates, while pull-request and merge-queue Tests checks remain
always-created. Pester now guards the schema path in the Tests push trigger and
continues to reject PR path filters for required-check candidates. Next highest
open item: branch-protection/ruleset status-check enforcement remains
external-gated while this loop pushes directly to `main`; continue with routine
Dependabot GitHub Actions update grouping.

2026-06-06 v4.9.65 refresh: scheduled maintenance staggering shipped.
`workflow-security.yml` now runs on Wednesday at `17 9 * * 3`, leaving
`assets-refresh.yml` at `19 8 * * 3` and generated-branch cleanup at
`43 8 * * 3`. Pester now guards the intended Wednesday spacing and checks
independent maintenance workflows for duplicate day/hour/minute schedule slots.
Next highest open item: branch-protection/ruleset status-check enforcement
remains external-gated while this loop pushes directly to `main`; continue with
adding `schemas/**` to the offline Tests workflow path filters.

2026-06-06 v4.9.64 refresh: workflow-security local action coverage shipped.
`workflow-security.yml` now runs `zizmor --strict-collection
--collect=workflows --collect=actions .github`, so future local action metadata
is collected with workflow files while no-op behavior stays clean without a
`.github/actions` directory. The workflow already has no pull-request path
filters, and `.github/CODEOWNERS` already owns `/.github/`, so local action
changes receive the same always-created check and ownership path as workflow
changes. Pester now guards the actionlint command, expanded zizmor collection,
no `pull_request` path filters, and `/.github/` owner rule. Next highest open
item: branch-protection/ruleset status-check enforcement remains external-gated
while this loop pushes directly to `main`; continue with staggered Wednesday
maintenance schedules for `assets-refresh` and `workflow-security`.

2026-06-06 v4.9.63 refresh: historical changelog heading validation shipped.
`docVersionConsistency.changelogHeadingValidation` now scans every
`CHANGELOG.md` release heading for strict `## [vMAJOR.MINOR.PATCH] -
YYYY-MM-DD` shape, reports malformed headings with line numbers/offending text,
and rejects impossible dates. The malformed historical `v3.0.0` heading is now
corrected to the confirmed GitHub release date, `2026-04-13`, and Pester covers
both malformed-heading and bad-date fixtures. Next highest open item:
branch-protection/ruleset status-check enforcement remains external-gated while
this loop pushes directly to `main`; continue with workflow-security local
action coverage.

2026-06-06 v4.9.62 refresh: shared generated PR helper shipped.
`scripts/open-generated-profile-pr.ps1` now centralizes generated profile PR
creation for `profile-sync.yml` and `assets-refresh.yml`. Both workflows pass
their branch prefix, commit message, PR title/body intro, and no-change
messages into the helper, while the helper owns the `$LASTEXITCODE` no-change
guards, explicit generated-artifact staging list, branch-scoped validation
handoff, and job-summary link output. Pester now guards the helper contract,
branch-prefix allowlist, workflow call sites, and read-only check-job isolation.
Current live re-check still shows `required_status_checks=null`, no repository
rulesets, and `enforce_admins=true` on protected `main`.
Next highest open item: branch-protection/ruleset status-check enforcement
remains external-gated while this loop pushes directly to `main`; continue with
historical `CHANGELOG.md` release-heading validation and cleanup.

2026-06-06 v4.9.61 refresh: generated automation branch cleanup policy shipped.
`automation-branch-cleanup.yml` now runs a weekly dry-run and offers a manual
delete mode for merged generated PR branches. The workflow only manages
`automation/profile-sync-*` and `automation/profile-assets-*` refs, requires a
matching merged pull request before deletion, and keeps write permissions scoped
to the cleanup job. Workflow-security's `zizmor` install line is now YAML-safe
for strict workflow collection. Current live remote check found no existing
`automation/*` branches to delete.
Next highest open item: branch-protection/ruleset status-check enforcement
remains external-gated while this loop pushes directly to `main`; continue with
the shared generated-PR helper/composite-action item.

2026-06-06 v4.9.60 refresh: stale roadmap duplicate rows reconciled.
The roadmap now marks duplicate open rows for pull-request profile-sync
validation, public-safe issue forms, the sync-report schema contract, and live
rendered-profile smoke proof as complete with their shipped evidence from
v4.9.28, v4.9.29, v4.9.45, and v4.9.27/v4.9.48. The open queue now preserves
the external-gated branch-protection/ruleset enforcement row and true P3
automation/doc-hygiene follow-ups.
Next highest open item: audit branch-protection/ruleset status-check enforcement
constraints, then continue with the generated `automation/*` branch cleanup
policy.

2026-06-06 v4.9.59 refresh: catalog-to-feed accounting shipped.
Profile sync now reports `catalogFeedAccounting`, proving each catalog row is
exported as a public project, exported as a redacted suppression, or flagged as
unaccounted without exposing omitted repo names. The current live report accounts
for 187 catalog rows: 177 visitor-facing projects, 10 redacted suppressions, 0
unaccounted rows, 0 count mismatches, and 0 fatal accounting gaps. `-Check` now
fails on unreasoned non-portfolio catalog rows or feed count mismatches.
Next highest work: reconcile stale roadmap duplicate rows for already shipped
profile validation and issue-form work, then continue down the remaining queue.

2026-06-06 v4.9.58 refresh: userscript install trust metadata shipped.
Profile sync now reports `userscriptInstallTrust` for direct raw `.user.js`
install actions. The current live report checks 11 userscript installs, all from
raw GitHub branch URLs, records 11 metadata blocks, 0 missing-version rows, 2
missing-update-URL rows, 2 missing-download-URL rows, 3 broad-scope rows, and 7
warning rows. The report schema, summary helper, and Pester suite cover source
provenance, metadata fields, scope counts, and warning aggregates.
Next highest open item: catalog-to-feed omitted-row accounting in the sync
report.

2026-06-06 v4.9.57 refresh: profile release/tag consistency reporting shipped.
Profile sync now reports `profileReleaseConsistency` beside planning-doc
version/date checks. The current live report compares expected planning version
`v4.9.57` against latest GitHub release `v3.0.0`, confirms the expected
`v4.9.57` tag ref is missing, and surfaces both gaps as warning-only rows. The
report schema, summary helper, and Pester suite cover the new section.
Next highest open item: userscript install trust metadata for raw `.user.js`
actions.

2026-06-06 v4.9.56 refresh: fork-parent drift reporting shipped.
Profile sync now collects live `isFork` metadata, enriches GitHub fork parent
names through REST when bulk repo metadata omits them, and reports
`forkParentDrift` in `reports/profile-sync-report.json`. The current live report
records 8 GitHub forks, 7 catalog `forkOf` rows, 5 matching GitHub forks, 2
catalog continuations/imports, 3 missing catalog-attribution warnings, and 0
parent mismatches. The report schema, summary helper, and Pester suite cover the
new section.

2026-06-06 v4.9.55 refresh: per-project SPDX/license metadata shipped.
Generated project rows now include `licenseKey`, `licenseName`, and
`licenseSpdxId` from live GitHub metadata, separate from `upstreamLicense`.
The sync report now records `projectLicenseMetadata` with detected, missing,
non-standard, and per-license aggregate counts; the current live report checks
166 README-facing projects, detects 163 licenses, and records 12 warning rows
for 3 missing and 9 non-standard licenses. The projects/feed schemas, report
schema, summary helper, and Pester suite cover the new fields. The duplicate
profile-assets report-summary row is reconciled as already completed in v4.9.31.

2026-06-06 v4.9.54 refresh: generated profile PR validation handoff shipped.
Both generated-PR workflows now grant `actions: write` only to their
PR-creating jobs, create a branch-scoped validation-runs URL in the PR body and
job summary, and explicitly dispatch `profile-sync.yml` in check mode on the
generated automation branch. Pester coverage guards the dispatch command,
handoff links, summary text, and read-only check-job permissions.

2026-06-06 v4.9.53 refresh: repository settings/community-health baseline shipped.
Profile sync now records public-safe `repositorySettings` and `communityHealth`
blocks with live setting availability, aggregate warnings, community-profile
health, local required intake-file checks, and unavailable reasons for offline
or unauthenticated runs. The current live baseline reports 4 repository-setting
warnings, 3 community-health warnings, and 0 fatal local intake-file gaps. The
report schema, summary helper, and Pester suite cover the new sections.
Next highest open item: generated profile PR validation handoff using a
least-privilege token or explicit dispatch.

2026-06-06 v4.9.52 refresh: catalog shape validation shipped.
Profile sync now reports `catalogShape` and fails `-Check` when catalog rows
have missing repo names, duplicate repo keys, unknown categories, or unknown
`downloadKind` values. The committed catalog currently passes with 0 shape
issues. The report schema and Pester suite cover the new guard.
Next highest open item: repository settings/community-health baseline in the
sync report.

2026-06-06 v4.9.51 refresh: generated README size budget shipped.
Profile sync now records `readmeSizeBudget` in the generated report with the
UTF-8 byte count, a 96 KiB soft limit, over-limit state, and an informational
warning that suggests collapsing low-traffic categories. The current generated
README is 61,434 bytes, below the 98,304-byte soft limit. The report schema and
Pester suite cover the new section.
Next highest open item: catalog JSON-shape validation in CI/Pester.

2026-06-06 v4.9.50 refresh: REST release fallback hardening shipped.
The REST repo metadata fallback now uses `gh api --paginate --slurp` for repo
enumeration, enforces authenticated `gh` access above the unauthenticated
release-request budget, caps latest-release fetches, treats release 404s as
expected no-release rows, and aborts on non-404 release fetch failures so
partial release metadata cannot be written silently. A forced REST fallback
exercise returned 184 public repos and 147 inspected releases.
Next highest open item: generated README size budget guard.

2026-06-06 v4.9.49 refresh: header/non-catalog link validation shipped.
Profile sync now validates the generated README's portfolio link plus the
advertised `setup.ps1` raw/source links alongside catalog links. Image-host
URLs found in generated README image markup are probed as non-fatal warnings
and grouped under `linkValidationSummary.headerHostWarnings`, while portfolio
and setup 404s stay fatal. The report schema, validation-performance summary,
and Pester coverage now cover the new target policy.
Next highest open item: REST release-fallback request cap and authentication
guard.

2026-06-06 v4.9.48 refresh: rendered-profile smoke section drift fixed.
The live rendered-profile smoke script now asserts the current generated README
section labels (`Python Desktop Applications` and `Browser Extensions &
Userscripts`) instead of the stale `Python Applications` label. Pester guards
the section-name contract, and live desktop/mobile smoke passed after the
update.
Next highest open item: header/non-catalog link validation folded into the
existing link gate.

2026-06-06 v4.9.47 refresh: motion-safe profile chrome shipped.
Generated profile chrome now uses committed static header/footer SVG assets,
the dormant rich header no longer depends on capsule-render animation or
readme-typing-svg, and the compact public README footer uses local
`assets/profile/footer-*.svg`. `readmeExperienceChecks` now records
`motionSafeChrome`, `motionPatternCount`, `thirdPartyRenderHostCount`, and
`thirdPartyRenderHosts`, and `-Check` fails if generated README chrome contains
known auto-motion patterns such as `animation=`, `repeat=true`, or
`readme-typing-svg`.
Next highest open item: header/non-catalog link validation folded into the
existing link gate.

2026-06-06 v4.9.46 refresh: CI validation tool pins shipped.
The Tests workflow now installs Pester 5.7.1 through
`Install-Module -RequiredVersion`, retaining the exact PSScriptAnalyzer 1.25.0
pin. Workflow security now installs `zizmor` 1.25.2 from
`requirements-ci.txt` with PyPI distribution hashes, `--require-hashes`,
`--only-binary :all:`, and `--no-deps`. `docs/ci-toolchain.md` records the
reviewed pins and update process, and Pester coverage rejects future floating
Pester or `zizmor` installs.
Next highest open item: reduced-motion/static guard for profile hero and typing
SVG chrome.

2026-06-06 v4.9.45 refresh: sync-report JSON Schema contract shipped.
`reports/profile-sync-report.json` now advertises
`schemas/profile-sync-report.v1.json` through a top-level `schema` URL. The new
schema validates the report's core booleans/counts, profile asset checks,
provenance, metadata hygiene, release asset drift and trust diagnostics,
schema-validation results, doc-version consistency, validation performance,
link validation, metadata drift, and README experience sections. `-Check` now
validates the generated report against that schema and records the result under
`schemaValidation.report`. Pester validates the committed report contract,
checks that the schema uses no unsupported keywords, and proves a report missing
`releaseAssetDrift` is rejected. This batch also fixed array stability for
single-value `releaseAssetDrift.sourceOnlyWithRelease.releaseAssetKinds`.
Next highest open item: pin and audit CI-installed validation tools.

2026-06-06 v4.9.44 refresh: release/download trust metadata shipped.
`projects.json` visitor-facing rows now include a `releaseTrust` object derived
from latest-release asset filenames. It records checksum sidecars, whether every
executable asset appears covered by a matching checksum or checksums bundle,
signature/SBOM/attestation filename evidence, debug artifact presence,
source-only release status, executable asset kinds, trust level, and a public
note that binaries are not downloaded or verified. The sync report now includes
`releaseTrustLevelCounts`, `executableDownloadsMissingChecksums`, and
`debugArtifactRows`; the latest live run reports 23 checksum-classified rows,
118 metadata-only rows, 36 unknown rows, 55 executable download rows missing
complete checksum coverage, and 3 debug artifact rows. Schema validation now
requires `releaseTrust`, and Pester covers trust classification, source-only
releases, checksum sidecars, and checksum-gap reporting. Latest local
verification passed Pester, ScriptAnalyzer, and
`scripts/sync-profile.ps1 -Write -Check`. Next highest open feed item:
report-schema contract for the sync report.

2026-06-06 v4.9.43 refresh: deterministic feed provenance shipped.
`projects.json` now includes a public-safe `provenance` object with
`sourceRepository`, generation-base `sourceCommit`, SHA-256 hashes for the
catalog, generator, and project schema, `metadataSnapshotAt`, `metadataProvider`,
and repository enumeration status. `reports/profile-sync-report.json` summarizes
the same provenance. Schema validation requires the new object, metadata drift
treats stable provenance mismatches as fatal, and volatile `sourceCommit` /
`metadataSnapshotAt` differences are informational so a committed feed does not
fail on self-referential commit timing. Latest local verification passed Pester,
ScriptAnalyzer, and `scripts/sync-profile.ps1 -Write -Check`. Next highest open
feed item: release/download trust metadata for executable assets.

2026-06-06 v4.9.42 refresh: suppressed public-feed row redaction shipped.
`projects.json.suppressed` now emits only redacted suppression records with
`suppressedId`, `reasonCode`, `publicReason`, `category`, and
`visibilityClass`; it no longer exposes suppressed repo names, repo URLs,
descriptions, primary actions, release fields, topics, or notes. The projects
feed schema now has a dedicated `suppressedProject` object, metadata drift
indexes redacted suppressions by placeholder ID, and Pester rejects any
suppressed feed row that reintroduces direct project identifiers or known
private/sensitive names. Latest local verification passed Pester, ScriptAnalyzer,
and `scripts/sync-profile.ps1 -Write -Check` with `projectsExportInSync=true`.
Next highest open item: generated-feed provenance fields for downstream
consumer debugging.

2026-06-06 v4.9.41 refresh: Windows PowerShell setup smoke shipped. The
advertised `setup.ps1 -CheckOnly` inspect-before-install path now parses and
runs under Windows PowerShell 5.1 by keeping the bootstrapper ASCII-only. The
Tests workflow now includes an always-created `Windows setup smoke` job on
`windows-latest`, with a parser step and runtime `-CheckOnly` diagnostics.
Pester coverage guards both the ASCII-only source contract and the workflow
shape so future branch-protection candidates can include the setup smoke check.
The same batch preserves the minimal public README header introduced by the
latest remote privacy edit, so profile sync no longer reintroduces the older
personal-profile chrome, Start Here, Catalog Snapshot, or Currently Building
sections. Rendered-profile smoke checks now target the compact catalog sections
that remain visible.

2026-06-05 v4.9.35 refresh: Dependabot CodeQL action update applied. The
Scorecard SARIF upload step now uses the Dependabot-reviewed
`github/codeql-action/upload-sarif` 4.36.1 SHA
`87557b9c84dde89fdd9b10e88954ac2f4248e463`. Pester coverage guards the reviewed
SHA and rejects the older 3.35.5 SHA. With PR #5 and PR #6 both applied, the
current Dependabot workflow-action triage item is complete.

2026-06-05 v4.9.34 refresh: Dependabot checkout update applied. All pinned
`actions/checkout` workflow uses now point to the Dependabot-reviewed 6.0.3 SHA
`df4cb1c069e1874edd31b4311f1884172cec0e10`, addressing the hosted Node.js 20
deprecation warning observed on the v4.9.33 Tests run. Pester coverage guards
the reviewed SHA and rejects the older 4.3.1 SHA. Dependabot PR #5 is addressed;
PR #6 for `github/codeql-action` remains open for separate review.

2026-06-05 v4.9.33 refresh: actionlint CI integration shipped. The workflow
security lane now installs checksum-verified `actionlint` 1.7.12, lints all
workflow YAML, then runs `zizmor` as before. Pester coverage guards the pinned
version, SHA-256 verification, actionlint command, and retained zizmor command.

2026-06-05 v4.9.32 refresh: explicit workflow timeout budgets shipped. Every
GitHub Actions job now declares `timeout-minutes`: 30 minutes for live
profile-generation jobs, 20 minutes for Scorecard, and 15 minutes for offline
test/lint/security jobs. Pester coverage guards that every workflow job has a
timeout and that no configured budget exceeds 30 minutes.

2026-06-05 v4.9.31 refresh: workflow report summaries shipped.
`scripts/write-profile-sync-summary.ps1` now renders a public-safe aggregate
Markdown summary from `reports/profile-sync-report.json` and emits GitHub
warning/error annotations for fatal metadata drift, link failures, and transient
link warnings. Profile sync check/write-pr modes and profile-assets refresh now
call the helper and upload retained sync-report artifacts.

2026-06-05 v4.9.30 refresh: required-check readiness shipped. The Tests,
Profile sync, and Workflow security workflows now create pull request and
merge-queue checks for every PR instead of relying on PR path filters that could
leave required checks pending. Pester coverage guards the always-created
`pull_request` and `merge_group` trigger shape. External branch-protection or
ruleset enforcement remains open because live `main` protection has
`enforce_admins=true` and this autonomous loop currently pushes directly to
`main`; enabling required checks without switching to PR delivery or adding an
approved bypass would reject future direct pushes.

2026-06-05 v4.9.29 refresh: public-safe intake files shipped. `SECURITY.md`
now routes sensitive reports away from public issues, three issue forms collect
broken catalog links, profile/catalog corrections, and workflow/validation
problems with explicit privacy warnings, blank issues are disabled, and the PR
template warns against hand-editing generated README sections. Offline Pester
coverage checks the policy, forms, security-policy contact link, and generated
profile PR guidance. Next highest open item: required status checks/rulesets now
that generated-profile PR validation exists, with care around path-skipped checks.

2026-06-05 v4.9.28 refresh: generated-profile validation now runs on pull
requests that touch the profile contract surface. `.github/workflows/profile-sync.yml`
has a read-only `pull_request` path filter for `README.md`,
`data/profile-catalog.json`, `projects.json`, `reports/profile-sync-report.json`,
schemas, profile SVG assets, sync/render scripts, setup/test surfaces, and the
workflow itself. Offline Pester coverage guards the trigger path list so future
branch-protection work has a stable check to require on relevant PRs. Next
highest open item: add public-safe intake files (`SECURITY.md`, issue forms, and
PR template) before requiring status checks or changing repository rules.

2026-06-05 v4.9.27 refresh: the live GitHub-rendered profile smoke shipped.
`scripts/render-profile-smoke.ps1` now drives installed Chrome/Chromium through
the DevTools protocol, verifies desktop and 390px mobile renderings of
`https://github.com/SysAdminDoc`, captures screenshots, checks required profile
sections, image load health, and README/document overflow, and writes
`reports/rendered-profile-smoke.json`. `.github/workflows/profile-sync.yml`
runs the smoke after generated-profile validation and uploads the JSON plus
desktop/mobile PNGs as short-lived workflow artifacts. Local verification passed
with no missing sections, failed images, root overflow, or document overflow.
Next highest open item: run generated-profile validation automatically on PRs
touching catalog, README, feed, report, SVG assets, schemas, setup, or workflow
surfaces.

2026-06-05 v4.9.26 refresh: the OpenSSF Scorecard publish workflow repair shipped.
`.github/workflows/scorecard.yml` now keeps workflow-level permissions read-only
and grants `security-events: write` plus `id-token: write` only inside the
Scorecard job, matching the Scorecard action's publish-mode restriction. Offline
Pester coverage now guards the permission shape so future workflow edits cannot
silently reintroduce workflow-level write permissions. Next highest open item:
add the live GitHub-rendered profile smoke with desktop/mobile screenshots and
README-content overflow assertions.

2026-06-04 v4.9.25 refresh: the PSScriptAnalyzer static-analysis lane shipped.
`PSScriptAnalyzerSettings.psd1` now defines the curated warning/error gate with
documented exclusions, `.github/workflows/tests.yml` runs a pinned
PSScriptAnalyzer 1.25.0 job beside offline Pester, and the generator fixes the
real analyzer findings by avoiding PowerShell's automatic `$error` variable,
removing unused values, and passing `-SkipLinkValidation` explicitly into
`Test-ProfileState`. Verification ran the curated analyzer locally with 0
findings, `Invoke-Pester -Path tests -Output Detailed` passed 44/44, and
`scripts/sync-profile.ps1 -Write -Check` passed after REST fallback from a
transient GitHub GraphQL 502 with `docVersionConsistency.passed=true`,
`projectsExportInSync=true`, 0 metadata drift rows, 185 link targets checked, 0
link failures, and 0 link warnings.

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
- 166 catalog entries included in the public README, 177 visible projects exported to the portfolio feed, and 10 public-safe suppression records.
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

- [x] P2 — Add a quarterly archive/retirement / stale-project review
  - Why: many active repos benefit from periodic retirement review to keep the profile sharp.
  - Touches: `scripts/sync-profile.ps1` (`Test-ProfileState`), report schema, optional catalog `stalePolicy`; `data/profile-catalog.json` stale marks.
  - Acceptance: a report groups stale, dormant, source-only, suppressed, and recently revived projects from `pushedAt`/`latestRelease`/suppression reasons; forked or dormant repos stay out of the main featured set.
  - Completed: v4.9.72 adds warning-only `staleProjectReview` output with stale/archive thresholds, visitor-facing rows, public-safe suppression reason counts, schema validation, workflow-summary rows, and Pester coverage.
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

- [x] P2 — Extend link validation to hero/header and non-catalog URLs
  - Why: `Test-LinkTargets` only probes catalog-derived entrypoint/userscript/live/release URLs. The hand-authored hero — the portfolio link `https://sysadmindoc.github.io/`, the `setup.ps1` blob link, and the remaining third-party image hosts (capsule-render, readme-typing-svg, skill-icons, shields.io) — is never checked. A dead portfolio link or a retired image host would pass the gate.
  - Evidence: `scripts/sync-profile.ps1:476-528` (`Test-LinkTargets` iterates only `$Included` catalog entries); `README.md:1-68` (hero/header links and image hosts, none catalog-derived).
  - Touches: `scripts/sync-profile.ps1` (`Test-LinkTargets` plus a static header-URL extractor), report schema.
  - Acceptance: the portfolio link and `setup.ps1` blob link are probed as fatal-on-404; image hosts are probed as non-fatal warnings grouped under `headerHostWarnings`; results land in the report.
  - Completed: v4.9.49 added README header/non-catalog targets for the portfolio and setup links, non-fatal external image-host targets, `linkValidationSummary.headerHostWarnings`, validation-performance counts, report-schema coverage, and Pester acceptance coverage.
  - Verify: temporarily point the portfolio link at a 404 in a scratch copy and confirm a fatal failure; confirm image-host outages stay non-fatal.
  - Complexity: M

### Reliability and performance

- [x] P2 — Cap and authenticate the REST release-fallback N+1
  - Why: when the GraphQL path fails three times, `Get-GitHubReposFromRest` issues one `gh api .../releases/latest` per public repo — ~184 sequential calls. Unauthenticated that blows the 60 req/hr limit; even authenticated it is slow and can partially fail mid-run, silently yielding a feed with missing release tags.
  - Evidence: `scripts/sync-profile.ps1:148-162` (per-repo `gh api releases/latest` loop inside the fallback).
  - Touches: `scripts/sync-profile.ps1` (`Get-GitHubReposFromRest`): batch via a single GraphQL-less paginated call where possible, add `--paginate`, surface a rate-limit/partial-fetch warning, and fail loudly rather than emitting a half-populated catalog.
  - Acceptance: fallback completes within a bounded request budget, logs a warning when any per-repo release fetch fails, and never writes a feed where release data is partially missing without flagging it.
  - Completed: v4.9.50 switched repo enumeration to `gh api --paginate --slurp`, added authenticated/bounded release-request policy, treats 404 latest-release responses as no-release rows, aborts on non-404 release fetch errors, and added Pester coverage for the guard behavior.
  - Verify: force the GraphQL path to fail (simulate), run `-Write`, confirm the run either completes cleanly or aborts with a clear partial-data warning.
  - Complexity: M

- [x] P2 — Add a generated-README size budget guard
  - Why: the generated `README.md` is ~72 KB. GitHub renders profile READMEs but truncates very long files and degrades on mobile; there is no budget check, so unbounded catalog growth can silently push the profile past a comfortable render size.
  - Evidence: `README.md` is 73,358 bytes on disk; `New-Readme` (`scripts/sync-profile.ps1:959`) emits every included entry with a full code block and no size accounting.
  - Touches: `scripts/sync-profile.ps1` (`Test-ProfileState`), report schema.
  - Acceptance: report records generated byte size and warns past a configurable soft cap (e.g. 96 KB); the warning is informational, not fatal, and suggests collapsing low-traffic categories.
  - Completed: v4.9.51 added `readmeSizeBudget` to the sync report, a 96 KiB soft limit, schema coverage, and Pester checks for UTF-8 byte counting plus warning behavior.
  - Verify: lower the cap below current size, run `-Check`, confirm the warning appears in the report without failing the gate.
  - Complexity: S

### Test coverage gaps

- [x] P1 — Cover the safety-critical functions the Pester suite skips
  - Why: the hermetic suite tests snippet/URL/description helpers and basic generation, but never exercises `Test-ProfileState` (the privacy/medical/private-visibility/drift gate), `Update-Header` (the Currently-Building regex replace), or `New-ProjectsExportJson` suppression edge cases beyond one fixture. The most safety-critical logic — the gate that keeps private/medical repos out of the public profile — has no direct unit test.
  - Evidence: `tests/sync-profile.Tests.ps1` (no `Describe` for `Test-ProfileState`, `Update-Header`, or the medical-violation branch at `scripts/sync-profile.ps1:1395`); `MedicalPattern` is tested only as a regex string, not through the gate that consumes it.
  - Touches: `tests/sync-profile.Tests.ps1`, new offline fixtures (a fake `$Repos` with a private/medical entry).
  - Acceptance: tests assert `Test-ProfileState` flags a private-visibility repo, flags a medical-keyword repo lacking `allowPublicMedical`, passes one with the allowlist, and that `Update-Header` rewrites the Currently-Building table idempotently.
  - Completed: v4.9.36 added `Test-ProfileState` projects-sync gate test; v4.9.38 added URL-scheme validation tests; v4.9.39 added medical privacy gate tests (flags medical keywords, respects `allowPublicMedical`). `Update-Header` idempotency test remains open.
  - Complexity: M

- [x] P2 — Add catalog JSON-shape validation to CI/Pester
  - Why: a malformed `data/profile-catalog.json` (bad category slug, missing `repo`, duplicate entry, unknown `downloadKind`) only surfaces at generation runtime, and some bad values (e.g. an unrecognized `downloadKind`) silently fall through to a default label. There is no structural validation step.
  - Evidence: `Get-Catalog` (`scripts/sync-profile.ps1:313`) `ConvertFrom-Json` with no schema/shape assertions; `Get-DownloadLabel` (`:546`) `default { return "Download" }` swallows unknown kinds.
  - Touches: `tests/sync-profile.Tests.ps1` (or a new `Test-CatalogShape` function), optional committed schema from the P1 schema item.
  - Acceptance: a test fails on a duplicate `repo`, an unknown `category` slug, or an unknown `downloadKind`; known-good catalog passes.
  - Completed: v4.9.52 added `Test-CatalogShape`, `catalogShape` report output, `-Check` failure wiring, schema support, and Pester coverage for known-good plus malformed catalog rows.
  - Verify: inject a duplicate repo into a fixture, run Pester, confirm the new test fails.
  - Complexity: M

### Repository community health

- [x] P2 — Add SECURITY.md and a coordinated-disclosure path
  - Why: the repo ships zizmor, OpenSSF Scorecard, CODEOWNERS, and pinned actions, but has no `SECURITY.md`. Scorecard explicitly scores the presence of a security policy, and a profile repo that runs supply-chain tooling should publish how to report an issue.
  - Evidence: root listing shows no `SECURITY.md`/`.github/SECURITY.md`; `scorecard.yml` runs the Scorecard action that checks for one.
  - Touches: `SECURITY.md` (or `.github/SECURITY.md`), public-safe contact only.
  - Acceptance: a concise security policy exists with a non-PII reporting channel; Scorecard's Security-Policy check stops flagging it.
  - Completed: v4.9.29 added `SECURITY.md` plus issue chooser routing for sensitive reports; hosted Scorecard/community-profile confirmation remains a post-push check.
  - Verify: GitHub shows the "Security policy" community-health entry as satisfied after push.
  - Complexity: S

- [x] P3 — Add `.editorconfig` and a generated-README markdown lint pass
  - Why: the generated README is large hand-and-machine-mixed Markdown with no lint or whitespace contract; inconsistent line endings or stray trailing whitespace in the hand-authored hero can drift the generated diff. No `.editorconfig` or markdownlint config exists.
  - Evidence: root listing shows no `.editorconfig`/`.markdownlint*`; `New-Readme` normalizes only trailing `---` runs (`scripts/sync-profile.ps1:984`), not general whitespace.
  - Touches: `.editorconfig`, optional `.markdownlint.jsonc`, optional `tests.yml` lint leg.
  - Acceptance: an `.editorconfig` pins LF + final-newline + trim-trailing-whitespace; an optional markdownlint leg runs on PRs touching `README.md` with a curated ruleset (the generated tables are allowlisted).
  - Completed: v4.9.37 added `.editorconfig`; v4.9.70 removed the Markdown trailing-whitespace exception, pinned `.gitattributes` and `.editorconfig` to LF, cleaned the PR template placeholders, and added Pester coverage for the LF/final-newline/trailing-whitespace contract. v4.9.73 adds a pinned `markdownlint-cli2` ruleset, a `Markdownlint` Tests workflow job, Markdown/config/lockfile push triggers, npm Dependabot coverage, and Pester guards for the lint contract.
  - Complexity: S

### Privacy of the public surface

- [x] P3 — Document/justify the third-party render-host privacy exposure inline
  - Why: distinct from the planned action-baked-SVG work, the komarev profile-view counter and the stats/streak/activity hosts each see every profile visitor's request through Camo's proxy origin; there is no public note that these are third-party and no documented decision record for keeping them. A short DECISION note makes the trade-off auditable and avoids re-litigating it each research pass.
  - Evidence: historical `README.md` render hosts were removed by v4.9.14/v4.9.47; current `reports/profile-sync-report.json.readmeExperienceChecks` reports 0 third-party render hosts, 0 metric hosts, 0 badge hosts, and `motionSafeChrome=true`.
  - Touches: a short note in `RESEARCH_REPORT.md` or a `docs/decisions/` entry; no code change.
  - Acceptance: a one-paragraph recorded decision states which hosts are retained, why, and what would trigger removal (tie-in to the action-baked-SVG item).
  - Verify: the note exists and is referenced from the action-baked-SVG roadmap item.
  - Completed: v4.9.71 records that no live third-party render hosts are retained, defines the reintroduction/reopen criteria, and adds Pester coverage tying the decision note to the zero-host report fields.
  - Complexity: S

### Researcher Queue (Cycle 2 - 2026-06-04)

*Research conducted 2026-06-04. Items below were new relative to the open queue at research time. Existing open items already cover JSON Schema publishing, doc-version consistency, header link validation, REST fallback caps, catalog-shape validation, SECURITY.md, and setup `-CheckOnly`/transcript hardening.*

- [x] P1 — Add a PowerShell static-analysis lane for the generator and setup scripts
  - Why: Pester exercises selected behavior, but no CI step checks common PowerShell quality/security rules for `scripts/sync-profile.ps1` or `setup.ps1`. Microsoft documents `Invoke-ScriptAnalyzer` as a static checker for `.ps1`, `.psm1`, and `.psd1` files and supports `-EnableExit` for CI failure.
  - Evidence: `.github/workflows/tests.yml` installs/runs only Pester; root search found no `PSScriptAnalyzerSettings.psd1` or `Invoke-ScriptAnalyzer`; Microsoft Learn `Invoke-ScriptAnalyzer` docs: https://learn.microsoft.com/en-us/powershell/module/psscriptanalyzer/invoke-scriptanalyzer?view=ps-modules
  - Touches: `PSScriptAnalyzerSettings.psd1` (or equivalent), `.github/workflows/tests.yml`, existing PowerShell scripts only as needed to satisfy the rules.
  - Acceptance: CI runs `Invoke-ScriptAnalyzer` against `scripts/` and `setup.ps1` with a curated settings file; any suppressions carry justifications; Pester remains the behavioral test lane.
  - Completed: v4.9.25 added `PSScriptAnalyzerSettings.psd1`, wired a pinned PSScriptAnalyzer 1.25.0 job into `tests.yml`, documented settings exclusions, and fixed the real analyzer findings in `scripts/sync-profile.ps1`.
  - Verify: `pwsh -NoProfile -Command '$findings = @(Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1; Invoke-ScriptAnalyzer -Path setup.ps1 -Settings ./PSScriptAnalyzerSettings.psd1); if ($findings.Count -gt 0) { throw "PSScriptAnalyzer reported $($findings.Count) finding(s)." }'`
  - Complexity: M

- [x] P1 — Add generated-feed provenance fields for downstream consumers
  - Why: `projects.json` exposes `schema`, `generatedAt`, and a generic `source`, but does not identify the source tree, catalog hash, generator hash/version, or metadata snapshot that produced the feed. The portfolio cannot distinguish a stale cache from a freshly generated feed with unchanged timestamps, and debugging feed drift requires rerunning local context.
  - Evidence: `projects.json:2-5`; `New-ProjectsExportJson` currently emits top-level `schema`, `generatedAt`, `source`, and counts; GitHub artifact-attestation docs frame provenance as "where and how" artifacts were built: https://docs.github.com/en/actions/how-tos/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
  - Touches: `scripts/sync-profile.ps1` (`New-ProjectsExportJson`, report writer), `projects.json`, `reports/profile-sync-report.json`, optional portfolio consumer handling.
  - Acceptance: feed metadata includes a stable schema version plus public-safe provenance such as `sourceRef`, `catalogSha256`, `generatorSha256`, and `metadataSnapshotAt`; `-Check` reports or fails on mismatched provenance when generated files are stale.
  - Completed: v4.9.43 added `projects.json.provenance` and report provenance with source repository, generation-base commit, content hashes, metadata provider, metadata snapshot, and repository enumeration status.
  - Verify: run `scripts/sync-profile.ps1 -Write -Check`; compare the reported catalog/generator hashes to the current files; alter one provenance field and confirm `-Check` catches the mismatch.
  - Complexity: M

- [ ] P2 — Add structured issue/support intake for catalog and install-link reports
  - Why: Issues are enabled on the public repo, but the community profile reports no issue template, no PR template, and no contributing guidelines. A profile with 177 visitor-facing entries needs a guided intake for broken install snippets, stale release links, catalog corrections, and README/profile copy corrections; security reports should be routed to the planned `SECURITY.md` instead of public issues.
  - Evidence: `gh api repos/SysAdminDoc/SysAdminDoc/community/profile` returned `health_percentage=28` with `issue_template=null`, `contributing=null`, and no security-policy file; `gh api repos/SysAdminDoc/SysAdminDoc` shows `has_issues=true`; GitHub issue-template docs: https://docs.github.com/articles/creating-an-issue-template-for-your-repository
  - Touches: `.github/ISSUE_TEMPLATE/catalog-link.yml`, `.github/ISSUE_TEMPLATE/profile-correction.yml`, `.github/ISSUE_TEMPLATE/config.yml`, `.github/PULL_REQUEST_TEMPLATE.md`, optional `CONTRIBUTING.md` or `docs/CONTRIBUTING.md`.
  - Acceptance: the issue chooser has public-safe forms for broken catalog links and profile corrections, required fields capture repo/link/current behavior/expected behavior, security reports point to `SECURITY.md`, and the PR template warns against hand-editing generated README sections.
  - Verify: GitHub's community profile shows an issue-template check; opening `/issues/new/choose` shows the forms; a PR touching `README.md` presents the template.
  - Complexity: S

- [x] P2 — Add a read-only repository settings and community-health baseline to the sync report
  - Why: `scripts/sync-profile.ps1 -Check` validates generated files, but file checks miss drift in GitHub-hosted settings and community-health state. Live metadata currently shows secret scanning and push protection enabled, but non-provider/generic detection disabled, Dependabot security updates disabled, Projects/Wiki enabled, and missing issue/contributing templates. These should be visible as public-safe report fields before they become silent trust regressions.
  - Evidence: `gh api repos/SysAdminDoc/SysAdminDoc --jq '{has_issues,has_projects,has_wiki,security_and_analysis}'`; `gh api repos/SysAdminDoc/SysAdminDoc/community/profile`; GitHub secret-scanning docs: https://docs.github.com/en/code-security/secret-scanning/enabling-secret-scanning-features
  - Touches: `scripts/sync-profile.ps1` (new read-only repository/community metadata probe), `reports/profile-sync-report.json`, optional Pester fixture for report shape.
  - Acceptance: the sync report includes `repositorySettings` and `communityHealth` blocks with non-sensitive statuses; disabled push protection or missing planned community files are warnings; no settings are mutated by the check.
  - Completed: v4.9.53 added read-only `repositorySettings` and `communityHealth` report blocks, unavailable-state handling, local required intake-file fatal gaps, summary-helper aggregate rows, schema support, and Pester coverage.
  - Verify: `scripts/sync-profile.ps1 -Check` records the blocks; mock a missing/disabled field in a fixture and confirm the warning count changes.
  - Complexity: M

- [x] P2 — Triage current Dependabot workflow-action update PRs with a repeatable SHA-pin review path
  - Why: Dependabot has two open PRs updating SHA-pinned workflow actions, and both current check sets pass. The repo already values pinned actions, least-privilege permissions, and `zizmor`; the missing piece is a small repeatable merge/defer protocol so pinned actions do not go stale while still preserving review of major action/runtime changes.
  - Evidence: `gh pr list -R SysAdminDoc/SysAdminDoc` shows PR #5 (`actions/checkout` 4.3.1 -> 6.0.3) and PR #6 (`github/codeql-action` 3.35.5 -> 4.36.1); `gh pr checks 5` shows Pester and zizmor passing; `gh pr checks 6` shows zizmor passing; GitHub Dependabot action-update docs: https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot
  - Touches: `.github/workflows/*.yml`; optional `CONTRIBUTING.md` or `RESEARCH_REPORT.md` maintenance note.
  - Acceptance: PR #5 and PR #6 are merged or explicitly deferred with a reason; the review checklist records `gh pr checks`, `zizmor`, Pester/profile-sync relevance, `persist-credentials:false`, and permission diffs before merging future action-update PRs.
  - Progress: v4.9.34 applied PR #5's `actions/checkout` 6.0.3 SHA directly on current `main` after the hosted Tests run warned that the old checkout action used deprecated Node.js 20. PR #6 remains open for CodeQL review.
  - Completed: v4.9.35 applied PR #6's `github/codeql-action/upload-sarif` 4.36.1 SHA directly on current `main`; both Dependabot workflow-action PRs have now been addressed and closed as stale duplicates.
  - Verify: `gh pr list -R SysAdminDoc/SysAdminDoc --state open --label github_actions` is empty or each remaining PR has a documented defer reason.
  - Complexity: S

### Researcher Queue (Cycle 3 - 2026-06-04)

*Research conducted 2026-06-04. This pass looked for workflow/operator-experience gaps after the v4.9.8 report schema expansion rather than adding more catalog features.*

- [x] P2 — Surface profile-sync results in GitHub Actions job summaries
  - Why: `.github/workflows/profile-sync.yml` uploads `reports/profile-sync-report.json` as an artifact, but maintainers must download/open the JSON to see high-signal results. The report now includes metadata hygiene, release drift, validation performance, and link-warning summaries, and recent scheduled profile-sync runs show failures before the latest fixes. GitHub Actions supports Markdown job summaries through `$GITHUB_STEP_SUMMARY` and warning/error annotations through workflow commands.
  - Evidence: `.github/workflows/profile-sync.yml` only has the `Upload sync report` artifact step after `scripts/sync-profile.ps1 -Check`; `gh api repos/SysAdminDoc/SysAdminDoc/actions/runs` showed recent scheduled Profile sync runs concluding failure before the current v4.9.x fixes; GitHub workflow-command docs: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
  - Touches: `.github/workflows/profile-sync.yml`, optional `scripts/sync-profile.ps1` helper to render a concise summary from `reports/profile-sync-report.json`.
  - Acceptance: check and write-pr modes append a Markdown summary with readme/feed sync status, fatal metadata drift count, missing-topic/description counts, release-drift summary, link target count, warning count by host, and validation duration; fatal or warning conditions also emit GitHub annotations; the JSON artifact remains uploaded with an explicit retention period.
  - Completed: v4.9.31 added `scripts/write-profile-sync-summary.ps1`, wired it into profile-sync check/write-pr paths, added retained report artifacts, and covered the helper/workflow wiring with Pester.
  - Verify: run the workflow manually or set `GITHUB_STEP_SUMMARY` to a temp file in a local dry run and confirm the summary contains the current report values without exposing private/suppressed repo names.
  - Complexity: S

### Researcher Queue (Cycle 4 - 2026-06-04)

*Research conducted 2026-06-04. This pass audited repository governance settings after the workflow/report hardening work.*

- [ ] P2 🔧 — Require validation status checks on `main`
  - Why: `main` has force-push/deletion protection and required conversation resolution, but live branch protection does not require any status checks and there are no repository rulesets. A broken generated-profile check, Pester regression, or workflow-security failure can still be merged by policy unless maintainers manually notice it.
  - Evidence: `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection` returned `required_status_checks=null`, `required_pull_request_reviews=null`, `required_conversation_resolution.enabled=true`, `allow_force_pushes.enabled=false`, and `allow_deletions.enabled=false`; `gh api repos/SysAdminDoc/SysAdminDoc/rulesets` returned no rulesets. GitHub protected-branch docs describe required status checks before merging: https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches/
  - Touches: GitHub repository branch-protection or ruleset settings; optional `.github/workflows/*.yml` job-name stabilization if required-check names need to be fixed.
  - Acceptance: the default branch requires the relevant validation checks before merge, at minimum Pester, workflow security, and generated profile sync for changes that affect the profile pipeline; any admin bypass or Dependabot bypass is documented.
  - Progress: v4.9.30 removed PR path filters from Tests, Profile sync, and Workflow security, added `merge_group` triggers, and added Pester coverage that prevents required-check candidates from becoming path-filtered again. v4.9.77 recorded the current candidate checks and activation preconditions in `docs/decisions/2026-06-06-required-check-enforcement-readiness.md` without enabling enforcement.
  - Remaining blocker: the live protected branch has `enforce_admins=true`, and this autonomous loop currently pushes directly to `main`; enabling required checks now would reject future direct pushes before checks can be created, so enforcement needs PR-based delivery or an approved bypass path first.
  - Verify: `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection --jq '.required_status_checks'` or the rulesets API shows required checks; a PR with a failing required check is blocked from merging.
  - Complexity: S

### Researcher Queue (Cycle 5 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked whether generated-profile validation actually runs on pull requests before it can be made a required status check.*

- [x] P2 — Run profile-sync validation on profile/catalog pull requests
  - Why: At research time, `profile-sync.yml` was scheduled/manual only, and `tests.yml` only ran on script/test/workflow changes. A pull request that changed `data/profile-catalog.json`, generated `README.md`, `projects.json`, or the committed sync report could miss `scripts/sync-profile.ps1 -Check` unless a maintainer ran the workflow manually. This also blocked the Cycle 4 branch-protection item from safely requiring generated-profile validation on relevant PRs.
  - Evidence: At research time, `.github/workflows/profile-sync.yml` declared only `workflow_dispatch` and `schedule`; `.github/workflows/tests.yml` path filters omitted `data/profile-catalog.json`, `README.md`, `projects.json`, and `reports/profile-sync-report.json`; `gh run list -R SysAdminDoc/SysAdminDoc --limit 10` showed recent push-triggered `Tests` runs but no push/PR-triggered `Profile sync` runs. GitHub workflow syntax docs state that `push` and `pull_request` events can use path filters, and warn that skipped required checks remain pending: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  - Touches: `.github/workflows/profile-sync.yml`, optional `scripts/sync-profile.ps1` helper output if the PR check needs a shorter summary.
  - Acceptance: a read-only `pull_request` check runs `scripts/sync-profile.ps1 -Check` for profile-pipeline paths such as `data/profile-catalog.json`, `scripts/sync-profile.ps1`, `README.md`, `projects.json`, `reports/profile-sync-report.json`, and `.github/workflows/profile-sync.yml`; unrelated PRs are not blocked by a skipped required check.
  - Completed: v4.9.28 added read-only generated-profile validation on pull requests that touch README/catalog/feed/report/schema/profile-asset/sync-script/setup/test/profile-workflow paths, with Pester coverage for the trigger surface.
  - Verify: open or simulate a PR touching `data/profile-catalog.json` and confirm `Profile sync / Check generated README` runs and fails on stale generated output; open or inspect an unrelated-doc PR and confirm branch policy does not wait on a skipped profile-sync status.
  - Complexity: S

### Researcher Queue (Cycle 6 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked workflow runtime budgets after profile sync and asset refresh work expanded the number of live-network automation paths.*

- [x] P2 — Add explicit GitHub Actions timeout budgets
  - Why: the workflows currently rely on GitHub's default job timeout, which is much larger than any expected profile validation, Pester, workflow-security, Scorecard, or asset-refresh run. A hung package install, GitHub API fallback, third-party image fetch, link validation, or PR-create step can consume runner time and obscure whether the failure is validation drift or infrastructure stall.
  - Evidence: `rg -n "timeout-minutes" .github/workflows` returned no tracked workflow timeouts; the in-flight `assets-refresh.yml` also has no job or step timeout; GitHub workflow syntax docs state `jobs.<job_id>.timeout-minutes` defaults to 360 and `steps[*].timeout-minutes` can cap individual steps: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  - Touches: `.github/workflows/profile-sync.yml`, `tests.yml`, `workflow-security.yml`, `scorecard.yml`, and any committed asset-refresh workflow; optional `scripts/sync-profile.ps1` messaging if a timeout-prone phase should emit clearer progress.
  - Acceptance: every workflow job has an explicit timeout sized to observed runtime plus margin, long live-network steps have step-level caps where useful, and timeout values are documented enough that future workflow additions copy the pattern.
  - Completed: v4.9.32 added job-level `timeout-minutes` to all workflows and Pester coverage for presence plus a 30-minute maximum budget.
  - Verify: `rg -n "timeout-minutes" .github/workflows` shows coverage for each job; normal manual runs still complete; lowering a timeout on a test branch proves GitHub cancels the intended job/step instead of waiting for the default 360 minutes.
  - Complexity: S

### Researcher Queue (Cycle 7 - 2026-06-04)

*Research conducted 2026-06-04. This pass widened from the existing profile-sync
queue into generated-Markdown safety, workflow linting, setup bootstrapper
runtime verification, and release/download trust signals. Existing open items
already cover PSScriptAnalyzer, JSON-shape validation, feed provenance fields,
header link validation, workflow timeouts, branch protection, SECURITY.md, and
structured issue forms, so the items below avoid those duplicates.*

- [x] P1 🤖 🔬 — Add generated Markdown/text safety and URL-scheme validation
  - Why: the generator inserts catalog titles, descriptions, upstream attribution, and live GitHub metadata directly into GFM table/link contexts. Shape schemas now exist, but they do not prevent Markdown-control characters, raw-HTML-looking text, bidi controls, or unexpected URL schemes from breaking the public profile or making generated links visually deceptive.
  - Evidence: `scripts/sync-profile.ps1:467`, `:1221`, `:1243`, `:1313`, and `:1683` insert display descriptions and titles into README/feed output; the GFM spec defines table, link, raw HTML, and backslash-escape behavior and says GitHub performs post-processing/sanitization after Markdown-to-HTML conversion: https://github.github.com/gfm/; Unicode UTS #39 documents restricted/default-ignorable characters and confusable data for security-sensitive text: https://www.unicode.org/reports/tr39/
  - Touches: `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, optional schema/report additions.
  - Acceptance: generated README table cells and links are escaped or rejected by context; catalog/feed validation rejects bidi controls, embedded null/control characters, raw-HTML-looking generated text where not explicitly allowed, and non-http(s)/GitHub/raw link schemes; `reports/profile-sync-report.json` records a `contentSafety` block with zero current violations.
  - Verify: add a fixture description containing `|`, `](`, `<script>`, and a bidi control; `Invoke-Pester -Path tests` must fail before escaping/rejection and pass after the safety gate is applied. Run `scripts/sync-profile.ps1 -Check` and confirm `contentSafety.passed=true`.
  - Complexity: M

- [x] P2 🤖 🔬 — Add `actionlint` beside `zizmor` for workflow syntax/expression linting
  - Why: `workflow-security.yml` runs `zizmor`, which is useful for security posture, but no workflow validates GitHub Actions syntax, expression types, action inputs/outputs, `needs:` dependencies, cron syntax, or inline shell snippets. This is a complementary workflow-quality gate, not a replacement for `zizmor`.
  - Evidence: `.github/workflows/workflow-security.yml:21-36` installs and runs only `zizmor`; `actionlint` documents workflow syntax, expression, action-usage, ShellCheck/Pyflakes, and script-injection checks: https://github.com/rhysd/actionlint; GitHub's script-injection docs warn that attacker-controlled GitHub context values can be substituted into `run:` shell scripts before execution: https://docs.github.com/en/actions/concepts/security/script-injections
  - Touches: `.github/workflows/workflow-security.yml`, optional `.github/actionlint.yml` if the default rules need project-specific exclusions.
  - Acceptance: the workflow-security job runs both `zizmor` and `actionlint`; actionlint is pinned or installed through a repeatable versioned path; failures are blocking on workflow/security-file PRs; any project-specific ignores are documented.
  - Completed: v4.9.33 installs checksum-verified `actionlint` 1.7.12, runs `actionlint .github/workflows/*.yml`, keeps `zizmor .github/workflows`, and adds Pester coverage for the wiring.
  - Verify: `actionlint .github/workflows/*.yml` passes locally or in CI; introduce an invalid expression or bad `needs:` reference in a scratch branch and confirm the workflow fails before merge.
  - Complexity: S

- [x] P2 🤖 🔬 — Add a Windows runner smoke check for `setup.ps1 -CheckOnly`
  - Why: the README now gives novices an inspect-before-install command that runs `setup.ps1 -CheckOnly`, but current Pester coverage only inspects source text and generated README snippets. Because the script is Windows/WinGet/PATH-specific, an Ubuntu-only source contract can miss runtime regressions in the exact path users are told to run.
  - Evidence: `README.md:118-130` advertises both the one-paste setup and `-CheckOnly`; `tests/sync-profile.Tests.ps1:345-357` reads `setup.ps1` text but does not execute it; GitHub-hosted runner docs list standard `windows-latest` public-repo runners: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
  - Touches: `.github/workflows/tests.yml` or a new path-filtered setup-smoke workflow; optional Pester helper that shells out to `setup.ps1 -CheckOnly` on Windows only.
  - Acceptance: a Windows job runs `powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -CheckOnly` for PRs touching `setup.ps1`, README setup text, or tests; the check asserts check-only mode does not install or mutate tools, and uploads/redacts the temp transcript only on failure.
  - Completed: v4.9.41 added the always-created `Windows setup smoke` Tests job, kept `setup.ps1` ASCII-only for Windows PowerShell 5.1, and added Pester coverage for the bootstrapper contract.
  - Verify: open a scratch PR touching `setup.ps1`; confirm the Windows smoke job runs and passes. Temporarily make `-CheckOnly` call the install path and confirm the job fails.
  - Complexity: S

- [x] P2 🤖 🔬 — Add release/download trust metadata for visitor-facing binary rows
  - Why: the profile now routes visitors to many executable release assets, but the generated report only classifies asset kinds. It does not tell visitors or the build machine whether release rows have checksums, signatures, attestations, SBOMs, or a documented "unsigned/unattested" status.
  - Evidence: `reports/profile-sync-report.json:846-864` shows 71 release-action rows, including APK and EXE kinds; OpenSSF Scorecard includes a `Signed-Releases` check and related security posture checks: https://github.com/ossf/scorecard; GitHub artifact attestations establish where and how artifacts were built and can be verified with `gh attestation verify`: https://docs.github.com/en/actions/how-tos/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
  - Touches: `scripts/sync-profile.ps1` report generation, optional README trust microcopy, optional per-repo release checklist outside this profile repo.
  - Acceptance: `reports/profile-sync-report.json` includes a `releaseTrust` section summarizing, per release-action row, whether latest assets expose checksum/signature/attestation/SBOM evidence or are explicitly `unverified`; the README can keep UI minimal, but the report gives the build machine a prioritized list for high-traffic EXE/APK rows.
  - Completed: v4.9.44 adds filename-derived `releaseTrust` to `projects.json`, requires it in the project-feed schema, and expands `releaseAssetDrift` with trust-level counts, checksum-coverage gaps, and debug-artifact rows.
  - Verify: run `scripts/sync-profile.ps1 -Check`; confirm the report counts EXE/APK rows by trust status and flags missing evidence as warnings, not fatal failures. For one repo with an attestation/checksum, verify the report recognizes it.
  - Complexity: M

### Researcher Queue (Cycle 8 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on dependency/toolchain drift
inside CI. Existing open items already cover GitHub Actions SHA-pin review,
`actionlint`, PSScriptAnalyzer, workflow timeouts, and Dependabot PR triage; the
new gap is that registry-installed validation tools are not pinned or locked.*

- [x] P2 🤖 🔬 — Pin and audit CI-installed validation tools
  - Why: the workflows pin third-party GitHub Actions by SHA, but they still install validation tools directly from live registries: `zizmor` via `python -m pip install --upgrade zizmor` and Pester via `Install-Module Pester -MinimumVersion 5.5.0 -Force`. A new PyPI or PSGallery release can change CI behavior, break validation, or introduce a supply-chain dependency without a reviewed PR.
  - Evidence: `.github/workflows/workflow-security.yml:32-36` installs latest `zizmor`; `.github/workflows/tests.yml:39-45` trusts PSGallery and installs any Pester version at or above 5.5.0; no `requirements*.txt`, lock file, or tool-version manifest exists in the repo; pip's repeatable-installs docs recommend exact `==` pins and hash-checking for stricter automated installs: https://pip.pypa.io/en/stable/topics/repeatable-installs/ and https://pip.pypa.io/en/stable/topics/secure-installs/; Microsoft documents `Install-Module -RequiredVersion` for exact module selection: https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module; OpenSSF Scorecard's Pinned-Dependencies check calls unpinned build/release dependencies a medium risk: https://github.com/ossf/scorecard/blob/main/docs/checks.md#pinned-dependencies
  - Touches: `.github/workflows/tests.yml`, `.github/workflows/workflow-security.yml`, optional `requirements-ci.txt` with hashes, optional `docs/ci-toolchain.md` or a small tool-version manifest.
  - Acceptance: CI validation tools are installed from exact reviewed versions; Python-installed tools use a pinned requirements file, preferably with hashes or a documented reason hashes are deferred; PowerShell modules use `-RequiredVersion`; the maintenance note explains how to update pins intentionally and how those updates relate to Dependabot/Renovate/manual review.
  - Completed: v4.9.46 pins Pester 5.7.1 with `-RequiredVersion`, keeps PSScriptAnalyzer at 1.25.0, installs `zizmor` 1.25.2 from hash-checked `requirements-ci.txt`, documents the update path, and adds Pester guards.
  - Verify: `rg -n "pip install --upgrade|MinimumVersion" .github/workflows` returns no unreviewed floating validation-tool installs; a manual CI run uses the pinned versions; bumping a pin in a scratch branch produces a reviewable diff and still passes Pester/workflow-security.
  - Complexity: S

### Researcher Queue (Cycle 9 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on accessibility and motion.
Existing completed work already covers theme-aware chrome, plain-text tagline,
meaningful alt text, and third-party render-host reduction; this item is
specifically about auto-starting motion in the remaining hero/typing chrome.*

- [x] P2 🤖 🔬 — Add a reduced-motion/static profile chrome guard
  - Why: the generated profile header still uses `capsule-render` with `animation=fadeIn` and `readme-typing-svg` with `repeat=true`, while GitHub README embeds do not offer an in-page pause/stop control. This is a separate accessibility concern from dark/light theme handling and alt text.
  - Evidence: `scripts/sync-profile.ps1:1469-1472` generates the animated capsule and looping typing SVG URLs; `README.md:2` and `README.md:11` render those URLs; W3C WCAG 2.2.2 says moving/blinking/scrolling content that starts automatically, lasts more than five seconds, and appears alongside other content needs a pause/stop/hide mechanism unless essential: https://www.w3.org/WAI/WCAG20/Understanding/pause-stop-hide.html; MDN documents `prefers-reduced-motion` as the user preference for reducing non-essential motion: https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-reduced-motion; readme-typing-svg documents `repeat` defaulting to `true`: https://github.com/DenverCoder1/readme-typing-svg
  - Touches: `scripts/sync-profile.ps1`, generated `README.md`, optional committed `assets/profile/*.svg`, `tests/sync-profile.Tests.ps1`, `reports/profile-sync-report.json`.
  - Acceptance: generated profile chrome either uses static committed SVG/text for the hero/typing line or configures third-party URLs to avoid looping/auto-starting motion; `readmeExperienceChecks` records a `motionSafeChrome` field and fails when profile chrome contains `repeat=true`, `animation=`, or other known long-running motion parameters without an accessible fallback.
  - Verify: run `scripts/sync-profile.ps1 -Write -Check` and confirm `motionSafeChrome=true`; temporarily restore `repeat=true` or `animation=fadeIn` in the generator fixture and confirm Pester or `-Check` fails.
  - Completed: v4.9.47 replaced generated capsule/typing motion with committed static header/footer SVG assets, added `readmeExperienceChecks.motionSafeChrome`, and added Pester coverage proving reintroduced `repeat=true`, `animation=`, or typing-SVG motion fails the README experience gate.
  - Complexity: S

### Researcher Queue (Cycle 10 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on generated PR workflow
semantics. The existing branch-protection and pull-request profile-sync items
remain valid; this item covers the separate handoff problem when a workflow
itself creates the branch and PR.*

- [x] P2 🤖 🔬 — Add a validation handoff for generated profile PRs
  - Why: the `write-pr` profile-sync path and the asset-refresh workflow both push automation branches and create pull requests with the default `github.token`. GitHub's current behavior can create `pull_request` runs for `GITHUB_TOKEN`-created PRs, but those runs are approval-required, and push-triggered workflows are still suppressed. Future PR profile-sync checks or required status checks can therefore wait on manual approval or miss push-only validation on the generated PRs that need them most.
  - Evidence: `.github/workflows/profile-sync.yml:67-101` sets `GH_TOKEN: ${{ github.token }}`, pushes `automation/profile-sync-*`, and runs `gh pr create`; `.github/workflows/assets-refresh.yml:31-62` does the same for `automation/profile-assets-*`; GitHub's workflow-trigger documentation says `GITHUB_TOKEN`-created `pull_request` events for opened/synchronize/reopened can create workflow runs in an approval-required state, while other events such as push do not create new workflow runs, and recommends a GitHub App installation token or PAT when automation-created PRs should run validation automatically: https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow; GitHub's `GITHUB_TOKEN` authentication docs recommend least-required token permissions and GitHub App/PAT tokens when additional behavior is needed: https://docs.github.com/en/actions/tutorials/authenticate-with-github_token
  - Touches: `.github/workflows/profile-sync.yml`, `.github/workflows/assets-refresh.yml`, optional GitHub App/PAT secret documentation, optional workflow-dispatch/repository-dispatch handoff, `RESEARCH_REPORT.md`.
  - Acceptance: generated profile PR workflows either use a least-privilege GitHub App installation token/PAT that permits normal PR validation events, explicitly dispatch the required validation workflow after creating the PR, or document an intentional approval-required path; the PR body or job summary links to the validation run or approval step; the design prevents recursive PR churn and documents why default `GITHUB_TOKEN` alone is insufficient for unattended validation.
  - Completed: v4.9.54 grants `actions: write` only to generated-PR jobs, adds branch-scoped validation-run links to PR bodies and job summaries, and dispatches `profile-sync.yml` in check mode on generated profile/assets branches after PR creation.
  - Verify: run the manual `write-pr` path or asset-refresh path in a scratch/no-op branch and confirm the generated PR receives the intended Tests/Profile sync/workflow-security checks automatically or shows the expected approval-required state; inspect `gh run list --branch <automation-branch>` or the PR checks API for the expected runs; confirm no recursive generated PR is opened by the validation handoff.
  - Complexity: M

### Researcher Queue (Cycle 11 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on observability parity for
the committed profile-assets refresh workflow. The existing profile-sync summary
item remains useful; this item covers the separate asset-refresh workflow that
also runs the generator and report path.*

- [x] P2 🤖 🔬 — Add report artifact and summary parity to profile-assets refresh
  - Why: `.github/workflows/assets-refresh.yml` runs `scripts/sync-profile.ps1 -Write -Check` and can create a PR containing `reports/profile-sync-report.json`, but the workflow does not upload that report as a run artifact or write a job summary when the scheduled/manual run has no changes or fails before PR creation. Maintainers would need to read logs instead of the same structured report used by profile sync.
  - Evidence: `.github/workflows/assets-refresh.yml:28-62` regenerates assets, stages `reports/profile-sync-report.json`, and opens a PR, but contains no `actions/upload-artifact`, `retention-days`, `$GITHUB_STEP_SUMMARY`, or annotation step; `.github/workflows/profile-sync.yml:37-49` runs `scripts/sync-profile.ps1 -Check` and uploads `reports/profile-sync-report.json` as `profile-sync-report`; GitHub artifact docs describe uploading workflow outputs for debugging and custom `retention-days`: https://docs.github.com/en/actions/tutorials/store-and-share-data; GitHub workflow-command docs describe job summaries and annotations: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
  - Touches: `.github/workflows/assets-refresh.yml`, optional shared summary/report helper used by `profile-sync.yml`, optional generated PR body text.
  - Acceptance: asset-refresh runs always upload `reports/profile-sync-report.json` with an explicit retention period after the generator step, even on failures that still produce a report; the workflow writes the same public-safe summary fields and warning/error annotations as profile-sync; generated asset PRs include a concise report synopsis or run-artifact link; private/suppressed repo names stay out of summaries.
  - Completed: v4.9.31 wired profile-assets refresh through the shared summary helper and retained `profile-assets-sync-report` artifact.
  - Verify: dispatch `Profile assets refresh` in a no-op state and confirm the run has a report artifact and Markdown summary; force a harmless validation failure in a scratch branch and confirm `if: always()` still uploads the report when present; `rg -n "upload-artifact|retention-days|GITHUB_STEP_SUMMARY|::warning|::error" .github/workflows/assets-refresh.yml` shows the observability path.
  - Complexity: S

### Researcher Queue (Cycle 12 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on CODEOWNERS coverage as a
prerequisite for the branch-protection/ruleset work already queued.*

- [x] P2 🤖 🔬 — Expand CODEOWNERS coverage for profile-contract files
  - Why: `.github/CODEOWNERS` covers workflows, the generator, tests, catalog, public feed, and sync report, but it omits other files that define the public profile contract: `README.md`, `ROADMAP.md`, `RESEARCH_REPORT.md`, `CHANGELOG.md`, `PROJECT_CONTEXT.md`, `schemas/`, `assets/profile/`, and `setup.ps1`. If the build machine later enables code-owner review as part of branch protection, these public-facing/generated-contract paths could miss automatic owner review routing.
  - Evidence: `.github/CODEOWNERS:1-7` owns `.github/workflows/`, `scripts/sync-profile.ps1`, `tests/`, `data/profile-catalog.json`, `projects.json`, and `reports/profile-sync-report.json` only; root listing shows `README.md`, planning docs, `schemas/`, `assets/`, and `setup.ps1` outside those patterns; GitHub CODEOWNERS docs say code owners receive review requests for matching file changes and protected branches can require code-owner approval: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners; GitHub documents a CODEOWNERS errors endpoint for validating owner syntax: https://docs.github.com/en/rest/repos/repos#list-codeowners-errors
  - Touches: `.github/CODEOWNERS`, optional `RESEARCH_REPORT.md` maintenance note if owner classes need rationale.
  - Acceptance: CODEOWNERS covers the generated/public contract surface (`README.md`, `projects.json`, `reports/profile-sync-report.json`, `schemas/`, `assets/profile/`), profile-pipeline controls (`scripts/sync-profile.ps1`, `tests/`, `.github/workflows/`, `setup.ps1`), and planning docs (`ROADMAP.md`, `RESEARCH_REPORT.md`, `CHANGELOG.md`, `COMPLETED.md`, `PROJECT_CONTEXT.md`) with valid owners; the coverage map aligns with any future branch-protection rule requiring code-owner review.
  - Verify: `gh api repos/SysAdminDoc/SysAdminDoc/codeowners/errors --jq '.errors // []'` returns an empty list after push; opening a scratch PR that touches `README.md`, `schemas/profile-projects.v1.json`, or `setup.ps1` requests the expected owner.
  - Complexity: S

### Researcher Queue (Cycle 13 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on repository license
metadata in the generated feed and report. Existing fork/upstream attribution
work covers upstream origins; this item covers each SysAdminDoc project's own
GitHub-detected license.*

- [x] P2 🤖 🔬 — Export per-project SPDX/license metadata in the feed
  - Why: the generated feed exposes each project's language, stars, releases, topics, upstream fork info, and upstream license, but it does not expose the repository's own detected license. Awesome-list submissions, portfolio consumers, and visitor trust checks need machine-readable license status without querying GitHub again.
  - Evidence: `gh repo view SysAdminDoc/Network_Security_Auditor --json licenseInfo` returns `MIT License`/`mit`; `scripts/sync-profile.ps1:210-213` requests live repo fields without `licenseInfo`, and the REST fallback at `scripts/sync-profile.ps1:187-196` also omits license metadata; `projects.json` rows include `upstreamLicense` but no row-level `licenseKey`, `licenseName`, or `licenseSpdxId`; `schemas/profile-projects.v1.json` has no project license fields beyond fork/upstream attribution. GitHub's license REST docs expose detected license `key`, `name`, and `spdx_id`: https://docs.github.com/rest/reference/licenses; the SPDX License List exists to provide stable identifiers for licenses: https://spdx.org/licenses/
  - Touches: `scripts/sync-profile.ps1`, `schemas/profile-projects.v1.json`, generated `projects.json`, `reports/profile-sync-report.json`, optional README/license microcopy if the build machine wants visitor-visible labels.
  - Acceptance: generated project rows include public-safe license fields such as `licenseKey`, `licenseName`, and `licenseSpdxId` when GitHub detects a license; the schema validates those fields; the sync report summarizes detected/missing/unknown license counts and warns on visitor-facing projects without a license; upstream-license attribution remains separate from the project's own license.
  - Verify: run `scripts/sync-profile.ps1 -Write -Check`; confirm `Network_Security_Auditor` and another MIT-licensed row emit SPDX/license fields; temporarily remove or null a fixture license and confirm the report records a missing-license warning without breaking unrelated rows.
  - Completed: v4.9.55 exports `licenseKey`, `licenseName`, and `licenseSpdxId` in `projects.json`, records `projectLicenseMetadata` warning/aggregate counts in the sync report, and validates both artifacts through schemas and Pester coverage.
  - Complexity: M

### Researcher Queue (Cycle 14 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on live GitHub fork-parent
metadata versus the manual fork/continuation attribution already shipped.*

- [x] P2 🤖 🔬 — Report GitHub fork-parent drift against catalog attribution
  - Why: `forkOf`/`upstreamLicense` now make fork and continuation attribution visible, but the generator does not record whether GitHub itself marks a repository as a fork or which parent GitHub reports. True GitHub forks can drift from manual `forkOf`, while continuation/import rows such as `uBlockVanced` need to stay explicitly allowed as non-GitHub forks.
  - Evidence: `gh repo list SysAdminDoc --json isFork,parent` exposes fork status but returned null parent details for current fork rows, while `gh api repos/SysAdminDoc/RcloneBrowser --jq .parent.full_name` reports `kapitainsky/RcloneBrowser`, matching its catalog `forkOf`; `gh api repos/SysAdminDoc/uBlockVanced` reports `fork=false` while the catalog intentionally records `forkOf=gorhill/uBlock`; `scripts/sync-profile.ps1:210-213` did not request `isFork` or enrich parent metadata, and the REST fallback metadata at `scripts/sync-profile.ps1:187-196` omitted fork-parent metadata; GitHub CLI documents `isFork` and `parent` as JSON fields: https://cli.github.com/manual/gh_repo_view
  - Touches: `scripts/sync-profile.ps1`, `reports/profile-sync-report.json`, generated `projects.json` if the build machine wants feed fields such as `isFork`/`forkParent`, optional schema additions.
  - Acceptance: the sync report distinguishes true GitHub forks, catalog-declared continuations/imports, and mismatches; a GitHub fork with no matching `forkOf` is a warning, a GitHub parent that disagrees with catalog `forkOf` is a warning or fatal based on severity, and catalog-declared non-GitHub continuations remain allowed with an explicit `forkAttributionKind` or equivalent field.
  - Verify: run `scripts/sync-profile.ps1 -Check`; confirm `RcloneBrowser` is reported as a matching GitHub fork and `uBlockVanced` as a catalog-declared continuation/import rather than a false failure; alter a fixture parent or remove `forkOf` for a known GitHub fork and confirm the report flags the mismatch.
  - Completed: v4.9.56 adds live fork-parent enrichment, `forkParentDrift` report/schema/summary support, and Pester coverage for matches, continuations, missing attribution, mismatches, and unavailable parents.
  - Complexity: M

### Researcher Queue (Cycle 15 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on future-proofing live
repository enumeration as the public catalog grows.*

- [x] P2 🤖 🔬 — Add a public-repo enumeration limit guard
  - Why: the main metadata path uses `gh repo list SysAdminDoc --visibility public --no-archived --limit 300`; the account currently has 184 active public repositories, so it is well under the cap today, but future growth could silently omit repos beyond the fixed limit. The REST fallback paginates, but the normal path has no near-limit warning or completeness signal.
  - Evidence: `scripts/sync-profile.ps1:207-213` hard-codes `--limit 300`; `gh repo list SysAdminDoc --visibility public --no-archived --limit 500 --json name --jq 'length'` returned 184 on 2026-06-04; `gh repo list --help` documents `--limit` as the maximum number of repositories to list with default 30; GitHub CLI docs document the same option: https://cli.github.com/manual/gh_repo_list
  - Touches: `scripts/sync-profile.ps1`, `reports/profile-sync-report.json`, optional Pester fixture for enumeration report shape.
  - Acceptance: the sync report records repository enumeration metadata such as requested limit, returned count, and a near-limit/completeness warning; `-Check` warns when returned count is close to the configured cap and fails or switches strategy if the count equals the cap; the implementation either raises the limit intentionally or uses a paginated/API path that cannot silently truncate public repos.
  - Completed: v4.9.36 raises the GraphQL enumeration limit to 500, records requested/returned/truncation metadata in feed provenance, and adds Pester coverage for truncation warnings.
  - Verify: run `scripts/sync-profile.ps1 -Check` and confirm `repoEnumeration.returned=184`, `limit=500`, and `truncated=false` for the current account; simulate a fixture where returned count equals the limit and confirm the guard warns or fails rather than treating the catalog as complete.
  - Complexity: S

### Researcher Queue (Cycle 16 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on the committed sync
report's machine-readable contract now that multiple workflow-summary and
artifact items depend on it.*

- [x] P2 🤖 🔬 — Publish a JSON Schema for `profile-sync-report.json`
  - Why: `reports/profile-sync-report.json` is now the central evidence artifact for sync status, metadata hygiene, release drift, link validation, schema validation, planning-doc consistency, and planned job summaries, but only the catalog/feed have committed JSON Schemas. Consumers that parse the report still have no versioned contract for report fields.
  - Evidence: `schemas/` contains only `profile-catalog.v1.json` and `profile-projects.v1.json`; `reports/profile-sync-report.json` has structured top-level fields such as `metadataHygiene`, `releaseAssetDrift`, `validationPerformance`, `readmeExperienceChecks`, `schemaValidation`, and `docVersionConsistency`, but no top-level `schema`/`$schema` pointer; `tests/sync-profile.Tests.ps1` validates catalog/feed schema contracts, not the full sync-report shape; JSON Schema's official docs describe it as a vocabulary for validating JSON data consistency and interoperability: https://json-schema.org/
  - Touches: `schemas/profile-sync-report.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, generated `reports/profile-sync-report.json`, optional workflow summary helper once added.
  - Acceptance: the sync report includes a versioned schema URL or schema id; a committed `schemas/profile-sync-report.v1.json` validates the generated report shape; Pester or `-Check` validates the current report against the schema; future report-summary helpers can rely on stable optional/required fields.
  - Completed: v4.9.45 adds `schemas/profile-sync-report.v1.json`, emits the report `schema` URL, records `schemaValidation.report`, validates the report from `-Check`, and adds Pester coverage for valid and malformed report fixtures.
  - Verify: run `scripts/sync-profile.ps1 -Write -Check` and Pester; deliberately remove a required report field in a fixture and confirm schema validation fails with a clear report-schema error.
  - Complexity: M

### Researcher Queue (Cycle 17 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on how GitHub presents the
large committed generated artifacts during pull-request review. It is separate
from the existing `.editorconfig`/markdownlint item, which covers whitespace and
Markdown rules, and from CODEOWNERS, which covers review routing.*

- [x] P2 🤖 🔬 — Add a `.gitattributes` generated-artifact diff policy
  - Why: the repo commits large fully generated outputs (`projects.json`, `reports/profile-sync-report.json`, and six `assets/profile/*.svg` panels), but it has no `.gitattributes` policy telling GitHub which generated artifacts should be collapsed in diffs and ignored for language statistics. Reviewers still need the public README visible by default, but the machine-only feed/report/SVG churn can obscure the hand-authored and generator-code changes that explain it.
  - Evidence: root listing shows no `.gitattributes`; `git check-attr -a -- README.md projects.json reports/profile-sync-report.json assets/profile/stats-light.svg` returned no attributes; tracked generated output sizes are `projects.json` 293,281 bytes, `reports/profile-sync-report.json` 27,988 bytes, and profile SVG panels 15,338 bytes combined; `scripts/sync-profile.ps1` writes those paths through the default `ReadmePath`, `ProjectsPath`, `ReportPath`, and `AssetsPath` parameters; GitHub Docs say `linguist-generated` in `.gitattributes` hides selected generated files by default in diffs and excludes them from repository language statistics: https://docs.github.com/en/repositories/working-with-files/managing-files/customizing-how-changed-files-appear-on-github
  - Touches: `.gitattributes`, optional `RESEARCH_REPORT.md` maintenance note if the README exception needs rationale.
  - Acceptance: `.gitattributes` marks only fully generated machine artifacts such as `/projects.json`, `/reports/profile-sync-report.json`, and `/assets/profile/*.svg` with `linguist-generated`; `README.md` stays review-visible by default unless a future review-summary workflow intentionally changes that policy; CODEOWNERS continues to own the generated contract files even when GitHub collapses their diffs.
  - Completed: v4.9.37 adds `.gitattributes` policy for generated feed/report/profile SVG artifacts while leaving the public README review-visible by default.
  - Verify: `git check-attr linguist-generated -- projects.json reports/profile-sync-report.json assets/profile/stats-light.svg README.md` shows the generated feed/report/SVG paths marked and `README.md` unmarked; a test PR or comparison view collapses the generated artifacts while still showing README and generator-code diffs on first load.
  - Complexity: S

### Researcher Queue (Cycle 18 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on lifecycle hygiene for the
generated pull-request branches created by the profile sync and profile-assets
refresh workflows. It is distinct from the generated PR validation handoff item,
which covers whether those PRs receive checks.*

- [x] P3 🤖 🔬 — Enable cleanup for generated automation PR branches
  - Why: the profile sync and profile-assets refresh workflows create short-lived `automation/profile-sync-*` and `automation/profile-assets-*` branches, but the repository is not configured to delete head branches after merge. There are no stale `automation/*` branches right now, so this is preventive hygiene, but scheduled/manual generated PRs can otherwise accumulate branch refs over time.
  - Evidence: `.github/workflows/profile-sync.yml:85-101` creates `automation/profile-sync-${{ github.run_id }}` and opens a PR; `.github/workflows/assets-refresh.yml:45-62` does the same for `automation/profile-assets-${{ github.run_id }}`; `gh repo view SysAdminDoc/SysAdminDoc --json deleteBranchOnMerge --jq .deleteBranchOnMerge` returned `false`; `git ls-remote --heads origin automation/*` returned no current automation branches; GitHub Docs describe an "Automatically delete head branches" repository setting for deleting PR head branches after merge: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-the-automatic-deletion-of-branches
  - Touches: GitHub repository pull-request merge settings, or a narrowly scoped workflow/admin cleanup step if the build machine wants to delete only generated `automation/*` branches.
  - Acceptance: merged generated profile/profile-assets PRs do not leave remote automation branches behind; if repository-wide auto-delete is enabled, any branch-protection or ruleset exception is documented; if cleanup is workflow-specific, it only deletes merged `automation/profile-sync-*` and `automation/profile-assets-*` branches and never touches contributor branches.
  - Completed: v4.9.61 adds `automation-branch-cleanup.yml` with scheduled dry-run visibility, manual delete mode, strict generated-branch prefixes, merged-PR gating, scoped write permissions, and Pester coverage.
  - Verify: `gh repo view SysAdminDoc/SysAdminDoc --json deleteBranchOnMerge --jq .deleteBranchOnMerge` returns `true` or a documented cleanup workflow exists; merge a scratch generated PR and confirm `git ls-remote --heads origin automation/*` does not retain the merged branch.
  - Complexity: S

### Researcher Queue (Cycle 19 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on duplicated generated-PR
creation logic in the two workflows that can open profile-related pull
requests. Existing token-handoff and branch-cleanup items cover separate
runtime semantics; this item covers maintainability of the shared implementation
path.*

- [x] P3 🤖 🔬 — Centralize generated PR creation logic
  - Why: `profile-sync.yml` and `assets-refresh.yml` both embed near-identical PowerShell for detecting changes, creating an `automation/*` branch, staging the same generated files, committing, pushing, and running `gh pr create`. The prior PowerShell `$LASTEXITCODE` guard comment only appears in one workflow, which shows how small fixes can diverge between the two copies.
  - Evidence: `.github/workflows/profile-sync.yml:71-101` and `.github/workflows/assets-refresh.yml:34-62` both define a `Create pull request` step with the same `git diff --quiet`, `git switch -c`, bot git identity, `git add README.md projects.json reports/profile-sync-report.json assets/profile/*.svg`, `git push`, and `gh pr create` flow; `rg -n "workflow_call|composite|\\.github/actions|uses: \\./\\.github/workflows" .github` found no reusable workflow or composite action in the repo; GitHub Docs describe reusable workflows for avoiding workflow duplication, and composite actions for collecting repeated steps into one action: https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows and https://docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action
  - Touches: optional `scripts/create-generated-profile-pr.ps1`, or `.github/actions/create-generated-profile-pr/action.yml`, plus `.github/workflows/profile-sync.yml` and `.github/workflows/assets-refresh.yml`.
  - Acceptance: both generated-PR workflows call one shared helper with inputs for branch prefix, commit message, PR title/body, and no-change message; the helper preserves the `$LASTEXITCODE` no-change guards, stages only the intended generated profile files, uses the existing least-privilege token permissions, and makes future token-handoff/branch-cleanup/report-summary changes in one place.
  - Verify: run both workflows manually in no-op mode and confirm they exit cleanly without empty commits; force a harmless generated-file change in a scratch branch and confirm each caller opens the expected PR through the shared helper; run workflow-security/actionlint once available.
  - Completed: v4.9.62 added `scripts/open-generated-profile-pr.ps1`, updated both generated-PR workflows to call it with explicit inputs, preserved the validation handoff and staged-file contract, and added Pester coverage for the helper and reduced workflow call sites.
  - Complexity: S

### Researcher Queue (Cycle 20 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on public version/release
trust for the profile repository itself. The existing `docVersionConsistency`
gate keeps tracked planning documents aligned, but it does not compare those
versions with GitHub Releases or tags.*

- [x] P2 🤖 🔬 — Add a profile-repo release/tag consistency check
  - Why: tracked docs say the current repo version is `v4.9.24`, but the public GitHub Releases surface still reports `v3.0.0` as the latest release and no `v4.9.*` tags exist locally. Visitors, downstream consumers, and future schema/provenance work can see a stale release history even while CHANGELOG/ROADMAP/PROJECT_CONTEXT advance.
  - Evidence: `CHANGELOG.md:5` and `ROADMAP.md:8` reported `v4.9.24`; `PROJECT_CONTEXT.md:35` reported `Version: v4.9.24`; `gh repo view SysAdminDoc/SysAdminDoc --json latestRelease --jq .latestRelease` returned tag `v3.0.0`, published 2026-04-13; `git tag --list "v4.9.*"` returned no tags; `reports/profile-sync-report.json` had `docVersionConsistency` but no GitHub release/tag comparison; GitHub Docs describe releases as deployable project iterations based on tags: https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
  - Touches: `scripts/sync-profile.ps1` (`Test-DocVersionConsistency` or a new release-consistency probe), `reports/profile-sync-report.json`, optional Pester fixture, and the release/tag process for this repo.
  - Acceptance: the report records the latest tracked version, latest GitHub release tag/date, whether the matching tag exists, and whether the public release is intentionally behind; `-Check` warns or fails when the tracked version is ahead of the latest release without an explicit policy; the build machine either publishes a matching release/tag or documents that this repo uses changelog-only internal versions.
  - Completed: v4.9.57 adds warning-only `profileReleaseConsistency`, latest-release comparison, GitHub tag-ref checks, schema/summary support, and Pester coverage for missing, behind, and matching release/tag states.
  - Verify: run `scripts/sync-profile.ps1 -Check` and confirm `profileReleaseConsistency` captures the current `v4.9.57` vs `v3.0.0` drift and missing `v4.9.57` tag; publish/tag a scratch or real release and confirm the warning clears; simulate an older latest release in a fixture and confirm Pester catches the mismatch.
  - Complexity: M

### Researcher Queue (Cycle 21 - 2026-06-04)

*Research conducted 2026-06-04. This pass stayed on public planning-doc quality.
It does not duplicate the v4.9.20 `docVersionConsistency` gate, which validates
the latest changelog version/date; this item covers historical changelog heading
shape.*

- [x] P3 🤖 🔬 — Validate all changelog release headings
  - Why: `Test-DocVersionConsistency` validates the latest changelog heading, but older release headings can still carry malformed generated text. One historical `v3.0.0` heading previously contained `%Y->- (HEAD -> main, origin/main, origin/HEAD)`, which weakened the public changelog and could confuse release/tag automation.
  - Evidence: the pre-fix `v3.0.0` heading was `## [v3.0.0] - %Y->- (HEAD -> main, origin/main, origin/HEAD)`; a focused heading scan found that line as the only `## [version] - date` heading whose date did not match `YYYY-MM-DD`; GitHub release `v3.0.0` was published on 2026-04-13; Keep a Changelog examples use second-level version headings with ISO-style dates such as `## [1.1.1] - 2023-03-05`: https://keepachangelog.com/en/1.1.0/
  - Touches: `scripts/sync-profile.ps1` (`Test-DocVersionConsistency`), `tests/sync-profile.Tests.ps1`, `CHANGELOG.md` cleanup by the build machine, and `reports/profile-sync-report.json`.
  - Acceptance: `docVersionConsistency` or a sibling report block validates every `CHANGELOG.md` release heading for `## [vMAJOR.MINOR.PATCH] - YYYY-MM-DD`; malformed historical headings are reported with line numbers; the existing `v3.0.0` heading is corrected or explicitly marked as legacy in a machine-readable exception.
  - Completed: v4.9.63 added `docVersionConsistency.changelogHeadingValidation`, report-schema support, malformed-heading line-number reporting, impossible-date rejection, Pester coverage, and corrected the historical `v3.0.0` heading to `2026-04-13`.
  - Verify: run `scripts/sync-profile.ps1 -Check` and confirm no malformed changelog-heading warnings remain after cleanup; inject a bad historical heading in a fixture and confirm Pester fails or reports the exact line.
  - Complexity: S

### Researcher Queue (Cycle 22 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on executable install trust
for raw userscript links. The existing release/download trust item targets
visitor-facing EXE/APK/ZIP release assets; userscript installs are a separate
surface because they execute through Tampermonkey/Violentmonkey from raw branch
URLs.*

- [x] P2 🤖 🔬 — Add userscript install trust metadata
  - Why: the README/feed expose 11 direct userscript install actions through raw GitHub URLs. Link validation checks whether those URLs respond, and release-asset trust work covers binary release rows, but the report does not inspect whether raw `.user.js` installs expose stable update metadata, version fields, permission/match scope, or branch/tag provenance.
  - Evidence: parsing `projects.json` found 11 rows with `downloadKind=userscript` and `primaryAction.kind=install`; 10 point at `raw.githubusercontent.com/.../main/...user.js` and 1 points at `.../master/...user.js`; `scripts/sync-profile.ps1:704-706` adds userscript URLs to link validation, while `scripts/sync-profile.ps1:3055-3062` excludes `userscript` from release-download drift checks; README currently reports "11 userscript installs"; Tampermonkey documents userscript metadata keys including `@version`, `@match`, `@updateURL`, and `@downloadURL`: https://www.tampermonkey.net/documentation.php?locale=en
  - Touches: `scripts/sync-profile.ps1` (new userscript metadata fetch/parse/report block), `reports/profile-sync-report.json`, optional feed fields such as `userscriptTrust`, and Pester fixtures with representative userscript headers.
  - Acceptance: the sync report records each userscript install row with branch/tag source, `@name`, `@version`, update/download URL presence, match/include scope summary, and any missing or broad-scope warnings; README can stay minimal, but the build machine gets a prioritized list of raw userscript install trust gaps; suppressed rows remain omitted from public summaries.
  - Verify: run `scripts/sync-profile.ps1 -Check` and confirm a `userscriptInstallTrust` block reports all 11 current installs; remove `@version` or widen `@match` in a fixture and confirm the warning/failure appears; confirm release-asset trust checks still focus on release-backed downloads.
  - Completed: v4.9.58 adds `userscriptInstallTrust`, checks all 11 current raw `.user.js` install actions, reports metadata/update/download/scope warnings, validates the section through schema, and adds Pester coverage for branch/tag provenance plus broad-scope and missing-URL warnings.
  - Complexity: M

### Researcher Queue (Cycle 23 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked workflow-security coverage for
future local composite actions. It is a follow-on guardrail for the generated PR
helper option, not a duplicate of the helper itself.*

- [x] P3 🤖 🔬 — Cover local GitHub actions in workflow-security
  - Why: the queued generated-PR helper may be implemented as `.github/actions/create-generated-profile-pr/action.yml`, but local action metadata must receive the same security-review path as workflow files if that surface is introduced.
  - Evidence: `workflow-security.yml` currently has no pull-request path filters, `.github/CODEOWNERS` owns `/.github/`, and v4.9.64 changes the audit command from workflow-only `zizmor .github/workflows` to `zizmor --strict-collection --collect=workflows --collect=actions .github`; current root check found no `.github/actions` directory; Cycle 19's generated-PR helper item lists `.github/actions/create-generated-profile-pr/action.yml` as an implementation option; GitHub Docs describe composite actions as repository files with action metadata consumed by workflows: https://docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action
  - Touches: `.github/workflows/workflow-security.yml`, `.github/CODEOWNERS`, optional `.github/actions/**` once a local action exists.
  - Acceptance: if local actions are added, workflow-security runs on PRs touching `.github/actions/**`; the audit/lint commands cover local action metadata and any embedded scripts as far as the selected tools support; CODEOWNERS routes local action changes to the same owner as workflow changes; no-op behavior stays clean while the directory is absent.
  - Verify: run `zizmor --strict-collection --collect=workflows --collect=actions .github`; Pester guards no workflow-security PR path filters, the expanded zizmor command, and `/.github/` CODEOWNERS coverage for future local action paths.
  - Completed: v4.9.64 updates workflow-security to strict-collect workflows and local action definitions under `.github`, keeps actionlint on workflow YAML, confirms `/.github/` CODEOWNERS covers future local actions, and adds Pester coverage for the trigger/ownership/audit contract.
  - Complexity: S

### Researcher Queue (Cycle 24 - 2026-06-04)

*Research conducted 2026-06-04. This pass audited the public feed's suppressed
rows for privacy posture. It is distinct from the README private/medical gate:
the row is omitted from the README, but still exported through the public feed's
`suppressed` array.*

- [x] P1 🤖 🔬 — Redact private suppression rows from the public feed
  - Why: `projects.json` intentionally includes a `suppressed` array for non-featured public rows, but one current suppressed row is marked as private while still exporting its repo identifier, repo URL, primary action, include flags, and private suppression reason. Private repositories are intended to be accessible only to explicitly authorized users; the public feed should not preserve private repo identifiers unless they have been explicitly approved as public-safe.
  - Evidence: parsing `projects.json` found 9 suppressed rows; one row has a suppression reason beginning "Repo is private" while still carrying `includeInReadme=true`, `includeInPortfolio=true`, `repoUrl`, and `primaryAction`; `scripts/sync-profile.ps1:1651-1739` emits all suppressed rows into the public feed; `scripts/sync-profile.ps1:3146-3185` enforces private/medical violations for README/profile inclusion but does not redact the feed's suppressed array; GitHub Docs describe private repositories as accessible only to explicitly shared users: https://docs.github.com/articles/limits-for-viewing-content-and-diffs-in-a-repository
  - Touches: `scripts/sync-profile.ps1` (`New-ProjectsExportJson`, privacy/report validation), `schemas/profile-projects.v1.json`, generated `projects.json`, `reports/profile-sync-report.json`, and Pester fixtures for private suppressed rows.
  - Acceptance: public `projects.json` either omits private suppressed rows entirely or emits only aggregate/redacted counts; suppression reasons that mention private state are not exported with repo identifiers; `-Check` fails or warns when a private/medical suppression row would be publicly named; public suppressed rows such as renamed or placeholder public repos can remain with public-safe reasons.
  - Completed: v4.9.42 redacts all suppressed feed rows into dedicated public-safe placeholder records and adds schema/Pester coverage that rejects suppressed project identifiers in the public feed.
  - Verify: regenerate with `scripts/sync-profile.ps1 -Write -Check` and confirm the private suppression row is absent or redacted from `projects.json`; add a fixture private suppressed row and confirm Pester catches any exported repo name/url/action; confirm public suppressed rows still support portfolio exclusion and stale-review reporting.
  - Complexity: M

### Researcher Queue (Cycle 25 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked scheduled workflow cadence.
It does not duplicate the explicit timeout-budget item; this is about avoiding
same-minute scheduled maintenance runs.*

- [x] P3 🤖 🔬 — Stagger same-minute scheduled maintenance workflows
  - Why: `assets-refresh.yml` and `workflow-security.yml` are both scheduled for Wednesday at `19 8 * * 3`. They run different maintenance checks, but same-minute starts make run triage noisier and can stack package installs, GitHub API calls, and generated-output checks in the same window. Staggering them costs little and makes scheduled failures easier to attribute.
  - Evidence: before v4.9.65, `.github/workflows/assets-refresh.yml:5-6` and `.github/workflows/workflow-security.yml:10-11` both used `cron: "19 8 * * 3"`; v4.9.65 leaves assets refresh at `19 8 * * 3`, keeps generated-branch cleanup at `43 8 * * 3`, and moves workflow security to `17 9 * * 3`; `profile-sync.yml` already uses a different Tuesday/Friday schedule (`37 7 * * 2,5`), and `scorecard.yml` uses Thursday at `43 8 * * 4`; GitHub Actions docs note that scheduled workflows can be delayed or dropped during high-load periods and recommend scheduling at a different minute of the hour to reduce delay risk: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule
  - Touches: `.github/workflows/assets-refresh.yml`, `.github/workflows/workflow-security.yml`, optional docs note if the repo wants a maintenance-window convention.
  - Acceptance: scheduled maintenance workflows no longer share the same day+minute unless they intentionally coordinate through concurrency; the chosen minutes avoid the top of the hour and leave enough spacing for the short jobs to finish; manual dispatch behavior is unchanged.
  - Verify: `rg -n "cron:" .github/workflows` shows no accidental duplicate schedule for independent maintenance jobs; Pester guards the Wednesday spacing and duplicate day/hour/minute schedule slots; the next scheduled run history should show separate start times.
  - Completed: v4.9.65 moves workflow-security to `17 9 * * 3`, keeps manual dispatch unchanged, and adds Pester coverage for independent maintenance schedule uniqueness.
  - Complexity: S

### Researcher Queue (Cycle 26 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked whether the now-committed
JSON Schema contracts are covered by the offline Tests workflow when schema
files change.*

- [x] P3 🤖 🔬 — Include schema-contract changes in the offline Tests workflow
  - Why: `tests/sync-profile.Tests.ps1` includes feed/catalog JSON Schema contract tests, and direct `main` pushes that touch schema files should create the same offline Tests workflow that validates those contracts.
  - Evidence: before v4.9.66, `.github/workflows/tests.yml` omitted `schemas/**` from the `push.paths` filter; pull-request and merge-queue Tests checks are already always-created with no PR path filters; `tests/sync-profile.Tests.ps1` validates the fixture catalog/feed against `schemas/profile-projects.v1.json`; `schemas/profile-catalog.v1.json`, `schemas/profile-projects.v1.json`, and `schemas/profile-sync-report.v1.json` are committed public schema contracts; GitHub workflow syntax docs state that `push`/`pull_request` path filters run based on changed file paths and that skipped required checks can remain pending: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  - Touches: `.github/workflows/tests.yml`; optional `.github/workflows/profile-sync.yml` PR path filter if schema edits should run full generated-profile validation as well.
  - Acceptance: schema contract changes under `schemas/**` trigger the offline Tests/Pester workflow on PRs and pushes; any future required-check policy either scopes this check safely or uses an always-created status so unrelated docs are not blocked by a skipped path-filtered workflow.
  - Verify: Pester guards `schemas/**` in the Tests push path filter and no `pull_request.paths` on required-check candidates; a scratch schema regression still fails the Pester contract case; unrelated planning-doc changes do not become blocked by a skipped required check.
  - Completed: v4.9.66 adds `schemas/**` to the Tests push path filter and Pester coverage for schema-trigger inclusion while keeping PR/merge-queue Tests checks always-created.
  - Complexity: S

### Researcher Queue (Cycle 27 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked future Dependabot workflow
update queue shape, separate from the existing current-PR triage item.*

- [x] P3 🤖 🔬 — Group routine Dependabot GitHub Actions version updates
  - Why: the repo intentionally lets Dependabot maintain SHA-pinned workflow actions, but `.github/dependabot.yml` has no `groups` rule, so routine action updates arrive as one PR per dependency. That is manageable for the two current major PRs, but future minor/patch action bumps can consume review attention that should stay focused on permission, action-identity, and `persist-credentials` changes.
  - Evidence: before v4.9.67, `.github/dependabot.yml:3-10` had one `github-actions` update block with `open-pull-requests-limit: 5` and no `groups`; v4.9.67 adds a `routine-actions` group with `patterns: ["*"]` and `update-types: ["minor", "patch"]`; the earlier major Dependabot PRs for `actions/checkout` and `github/codeql-action` were already addressed in v4.9.34 and v4.9.35; GitHub's Dependabot options reference says Dependabot opens one PR per dependency by default and `groups` can combine matching updates into fewer targeted PRs with `patterns` and `update-types`: https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file
  - Touches: `.github/dependabot.yml`; optional maintenance note in the action-update review checklist.
  - Acceptance: Dependabot groups low-risk GitHub Actions version updates into a named routine-actions group while keeping major or permission-sensitive action updates individually reviewable, or documents why separate PRs are preferred for every SHA-pinned action bump.
  - Verify: run Dependabot's next scheduled check or a manual Dependabot job and confirm eligible minor/patch action updates use the grouped branch/title; future major action PRs remain triaged through the existing review path; Pester guards the group shape and rejects routine major grouping.
  - Completed: v4.9.67 adds the `routine-actions` Dependabot group for GitHub Actions minor/patch updates and Pester coverage that keeps major updates out of the routine group.
  - Complexity: S

### Researcher Queue (Cycle 28 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked catalog-to-feed accounting
after the public-feed privacy and schema-contract items. This is about source
catalog rows in this repo, not the portfolio site's local overlay/fallback
omission check from v4.9.18.*

- [x] P2 🤖 🔬 — Report catalog rows omitted from both public feed arrays
  - Why: the catalog can contain a non-portfolio row with no `suppressionReason`, which is then absent from both `projects.json.projects` and `projects.json.suppressed`. That may be intentional local-only catalog state, but today it is not counted, reported, or forced to carry a public-safe reason, so feed consumers and maintainers cannot distinguish an intentional omission from a catalog mistake.
  - Evidence: parsing `data/profile-catalog.json` and `projects.json` found 187 catalog entries, 177 exported `projects`, 9 exported `suppressed` rows, and 1 catalog row absent from both arrays (`VaultBox`); the row has `category: "suppressed"`, `includeInReadme: false`, `includeInPortfolio: false`, and `suppressionReason: null`; `scripts/sync-profile.ps1:1665` sets `suppressed` only from nonblank `suppressionReason`, and `scripts/sync-profile.ps1:1724-1728` exports only suppressed rows or `includeInPortfolio` rows.
  - Touches: `scripts/sync-profile.ps1` (`New-ProjectsExportJson`, `Test-ProfileState` report output), `reports/profile-sync-report.json`, optional `schemas/profile-projects.v1.json` or future sync-report schema if omitted rows become a formal report section.
  - Acceptance: every catalog entry is either exported as a public project, exported/redacted as a suppressed row under the Cycle 24 privacy rules, or counted in a public-safe `omittedCatalogRows`/`localOnlyRows` report section with an explicit reason; `-Check` warns or fails when a row is excluded from both feed arrays without an intentional reason.
  - Verify: run a local catalog/feed reconciliation command and confirm no unaccounted rows remain; add a fixture row with `includeInPortfolio=false` and no suppression/local-only reason and confirm Pester or `-Check` reports it; confirm intentionally omitted private/privacy rows still follow the Cycle 24 redaction policy.
  - Completed: v4.9.59 adds `catalogFeedAccounting`, validates it through the sync-report schema, summarizes aggregate rows in Actions output, and fails `-Check` for unreasoned omitted rows or project/suppression count mismatches.
  - Complexity: S

### Researcher Queue (Cycle 29 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked whether the in-repo JSON
Schema validator fails closed when future schemas use keywords outside its
current subset.*

- [x] P3 🤖 🔬 — Guard unsupported JSON Schema keywords in the custom validator
  - Why: the repo now relies on committed JSON Schema contracts for catalog/feed validation, and a future sync-report schema is queued. The custom PowerShell validator implements a useful subset, but it does not reject unknown schema keywords. If a future schema adds `oneOf`, `anyOf`, `allOf`, `if`/`then`, `dependentRequired`, or similar semantic constraints, `Test-JsonSchemaContract` can report success while silently ignoring those rules.
  - Evidence: `scripts/sync-profile.ps1:2261-2395` implements `$ref`, `type`, `const`, `enum`, `format`, `pattern`, `minimum`, `minItems`, `items`, `required`, `properties`, and `additionalProperties`; searches of `schemas/` show no current `oneOf`, `anyOf`, `allOf`, `if`, `then`, or `dependentRequired` keywords; `tests/sync-profile.Tests.ps1:425-445` checks a required-field failure, but no test proves unsupported schema keywords fail closed.
  - Touches: `scripts/sync-profile.ps1` (`Test-JsonSchemaContract` / `Test-JsonSchemaNode`), `tests/sync-profile.Tests.ps1`, optional schema authoring note near the queued sync-report schema item.
  - Acceptance: the validator either implements the next needed JSON Schema keywords or recursively rejects unsupported keywords with a clear error before validating data; schema-contract tests include a fixture with an unsupported keyword that fails until support is intentionally added.
  - Verify: add a scratch schema using `if`/`then` or `oneOf` that should reject a malformed payload; `Invoke-Pester -Path tests` must fail with an unsupported-keyword or real validation error instead of reporting `valid=true`; current catalog/feed schema validation still passes.
  - Complexity: S

### Researcher Queue (Cycle 30 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked committed profile SVG panel
accessibility metadata. It is separate from the completed README image-alt work
because these SVGs are also raw repository artifacts.*

- [x] P3 🤖 🔬 — Add internal `<title>` and `<desc>` metadata to generated profile SVG panels
  - Why: the generated SVG panels already render as useful visual summaries and the README embeds them with meaningful `<img alt>` text, but the raw committed SVGs themselves only expose `role="img"` plus a short `aria-label`. Adding internal `title`/`desc` metadata keeps the standalone SVG files and any future direct links/tooling exports self-describing without relying on the README wrapper.
  - Evidence: `scripts/sync-profile.ps1:1355-1359` emits `<svg ... role="img" aria-label="...">` and visible text, but no `<title>` or `<desc>` elements; `assets/profile/stats-dark.svg:1-5` mirrors that structure; a scan of `assets/profile/*.svg` found no `<title>` or `<desc>` elements; W3C SVG Accessibility API Mappings describe `title`/`desc` and note current best practice for fallback support is linking them with `aria-labelledby`/`aria-describedby`: https://www.w3.org/TR/svg-aam-1.0/
  - Touches: `scripts/sync-profile.ps1` (`New-ProfilePanelSvg`), generated `assets/profile/*.svg`, `tests/sync-profile.Tests.ps1`, optional `readmeExperienceChecks` field if the repo wants this tracked.
  - Acceptance: generated SVG panels include stable `id` values, a concise `<title>`, a short `<desc>` summarizing the panel rows, and `aria-labelledby`/`aria-describedby` wiring; README `<img alt>` text remains unchanged and non-duplicative.
  - Verify: regenerate with `scripts/sync-profile.ps1 -Write -Check`; grep all `assets/profile/*.svg` for `<title`, `<desc`, `aria-labelledby`, and `aria-describedby`; add a Pester assertion that `New-ProfilePanelSvg` emits the metadata and still escapes dynamic text.
  - Completed: v4.9.68 wires all generated profile SVG assets through stable title/description IDs, expands stats/language/activity panel descriptions with generated row summaries, and adds SVG XML/Pester coverage for metadata wiring plus escaping.
  - Complexity: S

### Researcher Queue (Cycle 31 - 2026-06-04)

*Research conducted 2026-06-04. This pass checked public planning/history docs
for stale catalog-field terminology that the version/date consistency gate does
not cover.*

- [x] P3 🤖 🔬 — Refresh stale catalog field names in completed-work docs
  - Why: `COMPLETED.md` is public project history and currently describes the canonical catalog row shape with a legacy `privateReason` field. The live catalog/schema no longer expose that name; they use `suppressionReason`, `allowPublicMedical`, `aliasOf`, and the newer upstream attribution fields. A stale field list can mislead future maintainers editing the catalog or validating generated docs.
  - Evidence: `COMPLETED.md:9` lists `privateReason` in the canonical catalog row fields; `schemas/profile-catalog.v1.json` requires/properties include `allowPublicMedical`, `aliasOf`, and `suppressionReason` but no `privateReason`; `data/profile-catalog.json` rows use `suppressionReason`; `Test-DocVersionConsistency` validates planning version/date alignment but does not check stale field-name references.
  - Touches: `COMPLETED.md`, optional `PROJECT_CONTEXT.md`/`RESEARCH_REPORT.md` terminology sweep, optional doc-consistency lint if the build machine wants a guard.
  - Acceptance: public current-state/history docs no longer present `privateReason` as a current catalog field unless explicitly marked as a legacy term; catalog field lists either link to the schema or match the current schema names; generated checks still pass.
  - Verify: `rg -n "privateReason" COMPLETED.md PROJECT_CONTEXT.md ROADMAP.md RESEARCH_REPORT.md` returns no unqualified current-field references; schema/catalog checks still pass through `scripts/sync-profile.ps1 -Check`.
  - Completed: v4.9.69 updates the completed-work current catalog field summary to reference `schemas/profile-catalog.v1.json`, replaces the stale `privateReason` field list with current schema fields, and adds a Pester terminology guard.
  - Complexity: S

### Researcher Queue (Cycle 32 - 2026-06-04)

*Research conducted 2026-06-04. This pass focused on the gap between static
generated Markdown checks and the live GitHub profile renderer. The existing
verification standard already calls for a markdown render smoke after push; this
item makes that proof repeatable for generated-profile changes.*

- [x] P2 🤖 🔬 — Add a live GitHub-rendered profile smoke check
  - Why: `scripts/sync-profile.ps1 -Check` and `Test-ReadmeExperience` verify generated Markdown strings, links, assets, schemas, and report state, but they do not load the actual `https://github.com/SysAdminDoc` profile with GitHub.com CSS, sanitizer output, responsive table behavior, image loading, or theme handling. The repo already had a top-table layout failure class, and `RESEARCH_REPORT.md` still records rendered light/mobile behavior as inferred rather than browser-screenshotted.
  - Evidence: `ROADMAP.md:503` lists "markdown render smoke check on GitHub after push" as a release proof but no workflow or script currently captures it; `scripts/sync-profile.ps1:1923-2011` only inspects README text patterns inside `Test-ReadmeExperience`; `tests/sync-profile.Tests.ps1:250-330` exercises offline generated Markdown rather than GitHub.com rendering; `.github/workflows/profile-sync.yml:23-48` and `.github/workflows/assets-refresh.yml:23-62` run generator/report checks but no browser smoke or screenshot upload; the live profile currently renders the README at `https://github.com/SysAdminDoc`; GitHub docs state username-matching public repo READMEs appear on the profile and use GitHub Flavored Markdown: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes; GitHub's Markdown REST API can render Markdown HTML but GitHub Markup notes sanitization and the rest of the GitHub.com pipeline happen outside the markup library: https://docs.github.com/en/rest/markdown/markdown and https://github.com/github/markup; Playwright supports screenshot assertions for rendered pages: https://playwright.dev/docs/test-snapshots
  - Touches: optional `tests/rendered-profile-smoke.*` or `scripts/render-profile-smoke.*`, `.github/workflows/profile-sync.yml`, `.github/workflows/assets-refresh.yml`, optional scheduled/manual workflow, screenshot artifacts, `reports/profile-sync-report.json` or job summary fields.
  - Acceptance: a manual/scheduled and PR-safe smoke path loads the live profile or GitHub-rendered README after generated-profile changes, checks 390 px mobile and desktop widths for no horizontal overflow, confirms the first viewport contains the hero, Professional Focus, Proof Points, and Currently Building content in readable order, verifies profile SVG and typing/skill images resolved or reports host failures, and uploads light/dark or viewport screenshots plus a concise job summary without private repository names.
  - Completed: v4.9.27 added `scripts/render-profile-smoke.ps1`, desktop/mobile screenshot/report artifacts, profile-sync workflow upload wiring, and Pester coverage; v4.9.48 refreshed the assertions to the current generated section names.
  - Verify: run the smoke workflow or script after a no-op profile sync; confirm screenshots are uploaded as artifacts with explicit retention, the job summary links the artifacts, DOM assertions pass for `https://github.com/SysAdminDoc`, and an intentionally broken scratch README layout fails before merge or before a generated PR is accepted.
  - Complexity: M

### Researcher Queue (Cycle 33 - 2026-06-06)

*Research conducted 2026-06-06. This pass re-ran the advertised first-time setup
path from the README with Windows PowerShell 5.1 instead of only reading source
contracts. It found an immediate runtime/parser failure before any check-only
diagnostics can run.*

- [x] P1 🤖 🔬 — Fix the advertised Windows PowerShell `setup.ps1 -CheckOnly` path
  - Why: the public README tells new Windows users to run the installer through Windows PowerShell and offers an inspect-before-install `-CheckOnly` path, but that exact shell currently fails before executing the script. This undermines the first-run trust path for the profile catalog's Python/Git install snippets.
  - Evidence: local `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -CheckOnly` on Windows PowerShell `5.1.26100.7920` failed with `setup.ps1:85` parser error: `Missing closing '}' in statement block or type definition`; `README.md:118` advertises `irm ... | iex`; `README.md:124` advertises saving then running `powershell -NoProfile -ExecutionPolicy Bypass -File $p -CheckOnly`; `setup.ps1:1` declares `#Requires -Version 5.1`; `setup.ps1:116-129` contains the intended no-install check-only branch. Microsoft documents WinGet as the command-line Windows Package Manager after App Installer registration: https://learn.microsoft.com/windows/package-manager/winget. GitHub's PowerShell CI guide says GitHub-hosted runners have a tools cache with PowerShell and Pester: https://docs.github.com/en/actions/tutorials/build-and-test-code/powershell.
  - Touches: `setup.ps1`, `tests/sync-profile.Tests.ps1`, `.github/workflows/tests.yml`, optional README setup text if the command needs to be clarified.
  - Acceptance: `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -CheckOnly` parses and runs on Windows PowerShell 5.1, reports winget/Python/pip/Git status, does not call `winget install`, and exits without mutating installed tools; the README inspect-before-install command remains accurate.
  - Verify: run the command above on Windows PowerShell 5.1 and, when available, `pwsh -NoProfile -File .\setup.ps1 -CheckOnly`; add a Windows CI smoke job that uses `powershell`, not only `pwsh`, for PRs touching `setup.ps1`, README setup text, or tests; temporarily route `-CheckOnly` into `Install-Pkg` and confirm the smoke fails.
  - Completed: v4.9.41 replaced the unsafe typographic punctuation in `setup.ps1`, verified the advertised Windows PowerShell `-CheckOnly` path, and added ASCII-only regression coverage.
  - Complexity: S

### Researcher Queue (Cycle 34 - 2026-06-06)

*Research conducted 2026-06-06. This pass narrowed the existing generated-feed
provenance item into a concrete feed/report contract. It inspected the export
payload, schema, metadata-drift comparison, and official provenance/commit
references.*

- [x] P1 🤖 🔬 — Add deterministic generated-feed provenance fields
  - Why: `projects.json` is now an external portfolio feed, but consumers can only see `generatedAt` and a static `source` string. They cannot tell which commit, generator file, catalog file, schema file, or metadata snapshot produced a feed, nor whether a stale committed feed came from GraphQL or REST fallback metadata.
  - Evidence: `scripts/sync-profile.ps1:1727-1735` emits only `schema`, `generatedAt`, `source`, counts, `projects`, and `suppressed`; `schemas/profile-projects.v1.json:7-16` requires the same top-level fields and has no provenance object; `scripts/sync-profile.ps1:2777-2785` treats only `schema`, `source`, and counts as top-level fatal drift fields; current HEAD is `8c8aac4643b57514a364d0dfb3aaddf98d638023`. GitHub's commits API exposes commit SHAs and commit metadata for repository references: https://docs.github.com/en/rest/commits. GitHub artifact-attestation docs frame provenance as evidence of where and how an artifact was built, which is the same trust model this public feed needs even if it starts with lightweight in-file metadata: https://docs.github.com/en/actions/how-tos/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds.
  - Touches: `scripts/sync-profile.ps1`, `schemas/profile-projects.v1.json`, generated `projects.json`, `reports/profile-sync-report.json`, `tests/sync-profile.Tests.ps1`, optional portfolio consumer notes.
  - Acceptance: `projects.json` includes a public-safe `provenance` object with at least `sourceRepository`, `sourceCommit`, `catalogSha256`, `generatorSha256`, `projectSchemaSha256`, `metadataSnapshotAt`, `metadataProvider` (`graphql` or `rest-fallback`), and repository enumeration counts/limit/truncation status; the schema validates the object; metadata drift treats provenance mismatches as fatal except for intentionally volatile `metadataSnapshotAt`; no absolute local paths or private repo names are emitted.
  - Completed: v4.9.43 implements the public-safe provenance object, schema contract, report summary, metadata drift severity, and Pester coverage. `sourceCommit` is reported as informational drift because a file cannot embed the hash of the commit that contains itself; content hashes remain fatal drift.
  - Verify: regenerate twice without source changes and confirm file hashes are stable except the snapshot timestamp; edit `data/profile-catalog.json` and confirm `catalogSha256` changes; edit `scripts/sync-profile.ps1` and confirm `generatorSha256` changes; simulate REST fallback and confirm `metadataProvider=rest-fallback` appears in the report/feed.
  - Complexity: M

### Researcher Queue (Cycle 35 - 2026-06-06)

*Research conducted 2026-06-06. This pass refreshed the CI reproducibility item
against the current workflows after action SHA pinning and actionlint hardening.
The remaining drift source is live validation-tool installation, not GitHub
Action identity.*

- [x] P2 🤖 🔬 — Pin CI validation tools with a reviewed update path
  - Why: workflow actions are pinned to commit SHAs, but runtime validation tools still float. Pester uses `Install-Module Pester -MinimumVersion 5.5.0`, which can select a newer unreviewed version, and `zizmor` is installed with `python -m pip install --upgrade zizmor`. A new registry release can change CI behavior without a Dependabot PR or human review.
  - Evidence: `.github/workflows/tests.yml:65-66` installs Pester by minimum version; `.github/workflows/workflow-security.yml:44-48` installs latest `zizmor` before auditing workflows; `.github/dependabot.yml:3-10` only monitors `github-actions`, so PSGallery/PyPI tool changes do not create reviewable update PRs. Microsoft documents `Install-Module -RequiredVersion` for exact module selection: https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module. The Pester installation docs describe explicit installation paths and versions for CI usage: https://pester.dev/docs/introduction/installation.
  - Touches: `.github/workflows/tests.yml`, `.github/workflows/workflow-security.yml`, optional `requirements-ci.txt`/tool-version manifest, Pester tests that assert pinned install commands.
  - Acceptance: Pester and `zizmor` installs use exact reviewed versions; Python package installation uses a lock or hash-checked requirement where practical; the version-update process is documented near Dependabot/action-update guidance; workflow-security continues to show actionlint version plus checksum verification.
  - Verify: run `rg -n "Install-Module Pester|pip install.*zizmor|RequiredVersion|--require-hashes" .github/workflows tests scripts`; CI logs show the intended exact versions; a future version bump changes one manifest/workflow line and is reviewed like action SHA updates.
  - Completed: v4.9.46 pins Pester 5.7.1 with `-RequiredVersion`, installs `zizmor` 1.25.2 from hash-checked `requirements-ci.txt`, documents the reviewed update process in `docs/ci-toolchain.md`, and adds Pester source guards against floating validation-tool installs.
  - Complexity: S

### Researcher Queue (Cycle 36 - 2026-06-06)

*Research conducted 2026-06-06. This pass isolated the Windows PowerShell 5.1
setup failure to file encoding and typographic punctuation, not a missing brace
in the PowerShell syntax.*

- [x] P1 🤖 🔬 — Make `setup.ps1` parse safely from disk in Windows PowerShell 5.1
  - Why: `setup.ps1` is the public first-run bootstrapper, and the README intentionally invokes it through `powershell.exe`, not `pwsh`. A script that only parses after manually forcing UTF-8 does not satisfy the advertised Windows-first install path.
  - Evidence: `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -CheckOnly` fails at `setup.ps1:85` with `MissingEndCurlyBrace`; `[System.Management.Automation.Language.Parser]::ParseFile()` reports the same `85:69` parse error; the first bytes of `setup.ps1` are `23 52 65 71 75 69 72 65`, so the file has no UTF-8 BOM; `rg -n '[^\x00-\x7F]' setup.ps1` finds em dashes at `setup.ps1:2`, `setup.ps1:107`, and `setup.ps1:112`; parsing the same bytes via `[System.IO.File]::ReadAllText(..., [System.Text.Encoding]::UTF8)` and `ParseInput()` succeeds; replacing `U+2014` with ASCII `-` also parses. Microsoft documents that UTF-8-no-BOM scripts with non-ASCII characters can break in Windows PowerShell and that Windows PowerShell reads source without a BOM as the active ANSI code page: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding. Microsoft also documents that PowerShell treats smart quotes as string delimiters, which explains why mojibake from UTF-8 em dash bytes can look like quote imbalance: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules.
  - Touches: `setup.ps1`, `.gitattributes`, `.editorconfig`, `tests/sync-profile.Tests.ps1`, optional `PSScriptAnalyzerSettings.psd1`.
  - Recommended fix: keep the public bootstrap script ASCII-only by replacing typographic punctuation in `setup.ps1` with `-` and adding a regression test that `setup.ps1` contains no non-ASCII bytes. Avoid solving this by adding a UTF-8 BOM unless the repo intentionally changes its current `*.ps1 text eol=lf` policy, because the rest of the repo favors BOM-less UTF-8 and ASCII code for cross-tool consistency.
  - Acceptance: Windows PowerShell 5.1 `ParseFile()` returns no parser errors for `setup.ps1`; `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -CheckOnly` reaches the check-only branch; a test fails if future non-ASCII characters are added to `setup.ps1`; generated README text may still use entities/Markdown punctuation, but the downloaded `.ps1` stays shell-safe.
  - Verify: run `powershell -NoProfile -Command '[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\setup.ps1), [ref]$null, [ref]$errs) > $null; if ($errs) { throw $errs[0] }'`; run the advertised `-CheckOnly` command; run `rg -n '[^\x00-\x7F]' setup.ps1` and expect no matches; run existing Pester.
  - Completed: v4.9.41 keeps the public bootstrapper ASCII-only, Windows PowerShell `ParseFile()` returns no parser errors, and `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -CheckOnly` reaches the no-install diagnostics branch.
  - Complexity: S

### Researcher Queue (Cycle 37 - 2026-06-06)

*Research conducted 2026-06-06. This pass converted the existing Windows setup
smoke idea into a branch-protection-friendly CI shape that avoids path-filter
pending-check traps.*

- [x] P1 🤖 🔬 — Add an always-created Windows setup smoke job
  - Why: source-text Pester checks did not catch the Windows PowerShell parser failure. The repo already removed PR path filters from required-check candidates, so the setup smoke should be a normal always-created job rather than a path-filtered workflow that can be skipped when required checks are later enforced.
  - Evidence: `.github/workflows/tests.yml:5-6` already runs on all `pull_request` and `merge_group` events; `.github/workflows/tests.yml:50-71` runs Ubuntu Pester only; `tests/sync-profile.Tests.ps1:393-413` verifies `setup.ps1` source strings but never executes or parses it with Windows PowerShell; GitHub's PowerShell Actions guide shows using `pwsh` and the Pester module in CI, but the advertised README command specifically uses `powershell`, so the test must exercise Windows PowerShell as well: https://docs.github.com/en/actions/tutorials/build-and-test-code/powershell.
  - Touches: `.github/workflows/tests.yml`, `tests/sync-profile.Tests.ps1`, optional new `tests/setup-smoke.ps1` helper.
  - Recommended workflow shape: add a `windows-setup-smoke` job on `windows-latest` with `shell: powershell`, `timeout-minutes: 10`, `contents: read`, checkout with `persist-credentials: false`, a parser step using `System.Management.Automation.Language.Parser.ParseFile()`, and a runtime step running `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -CheckOnly`. Keep it always created on PR and merge queue; the job is cheap and safer than path logic.
  - Acceptance: the job name is stable for future branch-protection rules; it fails on parser errors before running the script; `-CheckOnly` output confirms no install path was taken; the job does not upload the transcript unless a failure needs debugging; Pester retains a source-level no-non-ASCII guard so failures are caught locally before hosted CI.
  - Verify: intentionally add an em dash in a `setup.ps1` string in a scratch branch and confirm the Windows job fails at parse; remove it and confirm the job reaches `Check-only mode: no packages will be installed.`; confirm `git diff --check` and offline Pester still pass.
  - Completed: v4.9.41 added `windows-setup-smoke` to `.github/workflows/tests.yml` with `shell: powershell`, `timeout-minutes: 10`, `persist-credentials: false`, a parser step, and a runtime `-CheckOnly` step. Offline Pester guards the always-created job shape.
  - Complexity: S-M

### Researcher Queue (Cycle 38 - 2026-06-06)

*Research conducted 2026-06-06. This pass turned the provenance backlog into
field-level implementation requirements tied to the current feed generator,
schema, and drift gate.*

- [x] P1 🤖 🔬 — Implement a versioned `projects.json.provenance` contract
  - Why: downstream portfolio consumers need to debug whether a feed came from the expected commit, catalog, generator, schema, and metadata provider. The current feed is structurally valid but cannot explain its build inputs.
  - Evidence: root `projects.json:1-7` has `schema`, `generatedAt`, `source`, and counts only; `scripts/sync-profile.ps1:1727-1735` emits the same payload shape; `schemas/profile-projects.v1.json:7-16` requires only the legacy top-level fields; `Test-MetadataDrift` only treats `schema`, `source`, and counts as top-level fatal fields at `scripts/sync-profile.ps1:2777-2785`; local git object IDs are available now for `data/profile-catalog.json` (`80e8b64ffe477f91f45e5220e47839d82765ff00`), `scripts/sync-profile.ps1` (`ac24d72dfe5af1426d521d02ab5dfc8b69570303`), `schemas/profile-projects.v1.json` (`affa705e61ba82541832c7fc8c4d7a00a03b5128`), and HEAD (`8c8aac4643b57514a364d0dfb3aaddf98d638023`).
  - Touches: `scripts/sync-profile.ps1` (`New-ProjectsExportJson`, `Get-GitHubRepos`, REST fallback, `Test-MetadataDrift`, `Test-FeedSchemaContracts`), `schemas/profile-projects.v1.json`, `projects.json`, `reports/profile-sync-report.json`, `tests/sync-profile.Tests.ps1`.
  - Proposed fields: `provenance.version`, `provenance.sourceRepository`, `provenance.sourceCommit`, `provenance.catalogPath`, `provenance.catalogGitBlob`, `provenance.generatorPath`, `provenance.generatorGitBlob`, `provenance.projectSchemaPath`, `provenance.projectSchemaGitBlob`, `provenance.metadataSnapshotAt`, `provenance.metadataProvider`, `provenance.repoEnumeration.requestedLimit`, `provenance.repoEnumeration.returnedCount`, and `provenance.repoEnumeration.truncated`.
  - Drift rules: `sourceRepository`, `sourceCommit`, path names, blob IDs, provider, and enumeration status are fatal when committed and expected feed disagree; `metadataSnapshotAt` is informational/staleness-only; row-level star/topic/pushedAt behavior stays informational; no absolute local path should appear.
  - Acceptance: schema requires the `provenance` object and disallows extra fields; generated feed includes deterministic blob IDs from `git hash-object` or equivalent content hashing; REST fallback can mark `metadataProvider=rest-fallback`; reports summarize provenance and expose stale or mismatched provenance as actionable drift.
  - Completed: v4.9.43 requires `provenance` in the project-feed schema, emits SHA-256 content hashes, records `metadataProvider=graphql` or `rest-fallback`, records enumeration count/limit/truncation, and reports provenance in `profile-sync-report.json`.
  - Verify: run `scripts/sync-profile.ps1 -Write -Check`; edit only a catalog row and confirm `catalogGitBlob` changes; edit only the generator and confirm `generatorGitBlob` changes; compare expected/current feed and confirm provenance mismatches are surfaced at top level.
  - Complexity: M

### Researcher Queue (Cycle 39 - 2026-06-06)

*Research conducted 2026-06-06. This pass focused on timestamp semantics in
the generated feed. The existing `generatedAt` field currently behaves like a
catalog timestamp, not a metadata snapshot timestamp.*

- [ ] P2 🤖 🔬 — Split catalog timestamp and feed snapshot timestamp semantics
  - Why: `projects.json.generatedAt` is currently copied from `data/profile-catalog.json`, so consumers may read it as "this feed was generated at" even when live metadata was fetched later. Once provenance lands, the repo needs unambiguous timestamps for catalog source age, feed build time, and GitHub metadata snapshot age.
  - Evidence: `projects.json:3` currently shows `generatedAt: 2026-06-01T16:18:55.0998940-04:00`; `scripts/sync-profile.ps1:1729` sets feed `generatedAt = ConvertTo-IsoText $Catalog.generatedAt`; `Test-MetadataDrift` treats stale `projects.json.generatedAt` as a feed freshness warning at `scripts/sync-profile.ps1:2752-2769`, even though that value is not necessarily the last metadata fetch; `PROJECT_CONTEXT.md` says the latest sync validation was 2026-06-05, newer than the feed's `generatedAt`.
  - Touches: `New-ProjectsExportJson`, `Test-MetadataDrift`, `schemas/profile-projects.v1.json`, `reports/profile-sync-report.json`, `scripts/write-profile-sync-summary.ps1`, downstream portfolio notes.
  - Recommended model: keep top-level `generatedAt` as the feed build/snapshot time, move the catalog value to `provenance.catalogGeneratedAt`, and add `provenance.metadataSnapshotAt` for the live GitHub fetch time. If preserving top-level compatibility is preferred, add `feedGeneratedAt` first and deprecate ambiguous `generatedAt` through schema notes and report warnings.
  - Acceptance: sync report distinguishes stale committed feed output from stale source catalog metadata; workflow summaries label the right timestamp; downstream portfolio consumers can display "feed built at" without misrepresenting catalog edit time; schema docs explain the compatibility decision.
  - Verify: after a no-op `-Write -Check`, feed build/snapshot time changes only when the generated feed is intentionally refreshed; catalog timestamp changes only when the catalog source changes; staleness warnings identify the correct timestamp field.
  - Complexity: S-M

### Researcher Queue (Cycle 40 - 2026-06-06)

*Research conducted 2026-06-06. This pass inspected live GitHub repository
settings and the local community-health files that shipped in recent profile
hardening work.*

- [x] P2 - Add repository settings and community-health baseline reporting
  - Why: the repo now has public-safe intake files and CODEOWNERS, but those files are only one layer of the trust posture. The sync report should also show whether live repository settings actually support the intended public profile workflow.
  - Evidence: local `.github/ISSUE_TEMPLATE/` contains `broken-link.yml`, `profile-correction.yml`, `workflow-ci.yml`, and `config.yml`; `.github/pull_request_template.md` has public-safety and generated-profile checklists; `.github/CODEOWNERS` owns `.github/`, `scripts/`, `tests/`, `schemas/`, `data/profile-catalog.json`, `projects.json`, `reports/`, `assets/profile/`, `setup.ps1`, `SECURITY.md`, and `PSScriptAnalyzerSettings.psd1`. Live `gh api repos/SysAdminDoc/SysAdminDoc/community/profile` returned `health_percentage=71`, detected `README.md`, `LICENSE`, and the PR template, but returned `code_of_conduct=null`, `contributing=null`, and `issue_template=null`. Live repo settings returned `has_issues=true`, `has_discussions=true`, `has_projects=true`, `has_wiki=true`, `delete_branch_on_merge=false`, `allow_forking=true`, `web_commit_signoff_required=false`, `secret_scanning=enabled`, `secret_scanning_push_protection=enabled`, and `dependabot_security_updates=disabled`. Live branch protection still has no required status checks or required PR review object, while conversation resolution, admin enforcement, force-push blocking, and deletion blocking are enabled. Live rulesets returned `[]`.
  - Source notes: GitHub's community profile API exposes health percentage and detected files: https://docs.github.com/en/rest/metrics/community. GitHub issue forms are YAML files in `/.github/ISSUE_TEMPLATE`: https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms. GitHub CODEOWNERS only becomes merge enforcement when branch protection requires code-owner review, and GitHub recommends owning the `.github` CODEOWNERS file or directory itself: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners. GitHub recommends Dependabot alerts, secret scanning, push protection, and code scanning as minimum public-repository security settings: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-security-and-analysis-settings-for-your-repository.
  - Touches: `scripts/sync-profile.ps1`, `reports/profile-sync-report.json`, `scripts/write-profile-sync-summary.ps1`, `tests/sync-profile.Tests.ps1`, optional future `schemas/profile-sync-report.v1.json`.
  - Proposed report fields: `repositorySettings.repository`, `repositorySettings.visibility`, `repositorySettings.features.hasIssues`, `hasDiscussions`, `hasProjects`, `hasWiki`, `repositorySettings.security.secretScanning`, `secretScanningPushProtection`, `dependabotSecurityUpdates`, `codeScanningConfigured`, `repositorySettings.branchProtection.requiredStatusChecks`, `requiredPullRequestReviews`, `requiredCodeOwnerReviews`, `requiredConversationResolution`, `enforceAdmins`, `allowForcePushes`, `allowDeletions`, `repositorySettings.rulesets.count`, and `communityHealth.files`.
  - Recommended behavior: keep this report informational until PR-based delivery or a documented bypass is approved. Treat missing public-safe intake files as fatal because they are local repo contract files; treat disabled live repository settings as warnings with exact remediation notes.
  - Acceptance: `-Check` records the live settings when `gh` is authenticated and a public-safe `unavailable` reason when offline or unauthenticated; Actions summary includes aggregate status without dumping sensitive settings; tests cover parsing fixture responses for enabled/disabled settings; no tokens, owner email addresses, alert details, or security alert contents are written to the report.
  - Completed: v4.9.53 records live settings when available, records public-safe unavailable reasons offline/unauthenticated, summarizes aggregate warning/fatal counts in Actions output, and keeps local public-safe intake-file misses as fatal report gaps.
  - Risks: live settings are mutable outside git; branch-protection changes can block this autonomous direct-push loop while `enforce_admins=true`; the community profile API may not recognize YAML issue forms as `issue_template`, so the report should separately check local `.github/ISSUE_TEMPLATE/*.yml`.
  - Verify: run `gh api repos/SysAdminDoc/SysAdminDoc/community/profile`; run `gh api repos/SysAdminDoc/SysAdminDoc --jq '{has_issues,has_discussions,security_and_analysis}'`; run branch protection and rulesets checks; run `scripts/sync-profile.ps1 -Check` and confirm the report contains the expected aggregate booleans.
  - Complexity: M

### Researcher Queue (Cycle 41 - 2026-06-06)

*Research conducted 2026-06-06. This pass audited the public `projects.json`
suppression surface and found that suppressed rows currently reuse the full
project row schema.*

- [x] P1 - Redact suppressed rows in the public project feed
  - Why: the public feed is consumed by the portfolio and can be read directly from raw GitHub. Suppression exists specifically because a row should not be visitor-facing, so exporting the full row for suppressed projects weakens the privacy and visitor-safety contract.
  - Evidence: `projects.json` currently has `suppressedCount=9` and every suppressed row contains `repoUrl`, `description`, and `primaryAction`; the feed exposes suppressed rows such as `improve-repo` with reason `Repo is private; public profile links would 404 for visitors`, plus a direct `https://github.com/SysAdminDoc/improve-repo` URL. `data/profile-catalog.json` currently has 10 entries with `suppressionReason`, including `VaultBox`; committed `projects.json` has only 9 suppressed rows and `reports/profile-sync-report.json` currently has `projectsExportInSync=false`, so suppressed-feed accounting is already difficult to reason about. `schemas/profile-projects.v1.json:47-50` points `suppressed.items` to the same `#/$defs/project` schema as public projects; `scripts/sync-profile.ps1:1671-1718` builds the full row before adding it to `$suppressed` at lines 1720-1721; `tests/sync-profile.Tests.ps1:744-745` already asserts the public Actions summary does not include `AppManagerNG` or `VaultBox`, but no comparable test guards `projects.json.suppressed`.
  - Touches: `scripts/sync-profile.ps1` (`New-ProjectsExportJson`, `Test-MetadataDrift`, privacy gates), `schemas/profile-projects.v1.json`, `projects.json`, `reports/profile-sync-report.json`, `tests/sync-profile.Tests.ps1`, downstream `sysadmindoc.github.io` feed importer.
  - Recommended contract: replace full suppressed project objects with minimal objects such as `suppressedId`, `reasonCode`, `publicReason`, `category`, and `visibilityClass`, where `suppressedId` is either an opaque stable slug or a salted hash of the catalog repo name. Do not export `repo`, `title`, `description`, `repoUrl`, `primaryAction`, `branch`, `topics`, release fields, notes, or live metadata for private/sensitive rows. Keep full suppression details in the private/local catalog and report only aggregate counts publicly.
  - Suggested `reasonCode` values: `private-repo`, `medical-privacy`, `duplicate-rename`, `placeholder`, `superseded`, `not-visitor-facing`, `third-party-fork-review`, and `documentation-only`. Map old free-text reasons to stable codes while preserving a sanitized `publicReason`.
  - Drift rules: `suppressedCount` and reason-code counts are fatal if current and expected feeds disagree; opaque IDs are fatal only when the underlying catalog suppression set changes; row-level private names and URLs must never appear in committed feed output.
  - Acceptance: no suppressed feed row contains a GitHub repository URL, direct project name, install/download/live action, release tag, release asset name, topics, or notes; schema defines a dedicated `suppressedProject` object; tests fail if suppressed rows include `repo`, `repoUrl`, `description`, `primaryAction`, `releaseAssetNames`, or private known names like `VaultBox`; downstream portfolio still excludes suppressed rows and only uses aggregate suppression counts.
  - Completed: v4.9.42 redacts all suppressed feed rows into dedicated `suppressedProject` records, updates metadata drift to compare redacted placeholders, and adds Pester/schema coverage that rejects project identifiers in the public `suppressed` array.
  - Verify: run a local JSON assertion over `projects.json.suppressed`; run `scripts/sync-profile.ps1 -Write -Check`; confirm `projectsExportInSync=true`; confirm portfolio feed import still produces 177 visible projects and no suppressed/local-only routes.
  - Complexity: M

### Researcher Queue (Cycle 42 - 2026-06-06)

*Research conducted 2026-06-06. This pass inspected release/download rows and
the trust metadata currently available to visitors for executable assets.*

- [x] P2 - Add release/download trust metadata for executable assets
  - Why: the README and portfolio route visitors to many EXE, APK, ZIP, CRX, XPI, script, and source release assets. The current feed can say what kind of file exists, but it cannot communicate whether the artifact has checksums, signatures, SBOMs, attestations, release/debug channel classification, or verification guidance.
  - Evidence: `reports/profile-sync-report.json.releaseAssetDriftSummary` checks 177 catalog rows, 141 release-bearing rows, and 71 release-action rows; current asset kind counts include 18 `apk`, 32 `exe`, 28 `zip`, 5 `crx`, 2 `xpi`, 8 `script`, 3 `userscript`, and 58 `source-archive`. `projects.json` has 71 `hasDownload=true` rows and 58 download rows whose release assets include `exe`, `apk`, or `zip`; only 17 of those 58 have asset names matching `sha256|checksum|sums`, 3 have `debug` in a downloadable asset name, 1 has an `sbom` asset name, and 0 have asset names matching signature patterns such as `.sig` or `.asc`. `schemas/profile-projects.v1.json:260-286` only models `releaseAssetKinds` and `releaseAssetNames`; there is no field for `releaseTrust`, checksum coverage, signing status, attestation status, SBOM status, or channel classification.
  - Source notes: GitHub artifact attestations can establish build provenance for binaries and can also attest SBOMs, with verification through `gh attestation verify`: https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations. SLSA notes that provenance should be bound to artifacts rather than only to releases, because releases can contain multiple platform-specific artifacts and may gain artifacts over time: https://slsa.dev/spec/draft/distributing-provenance. Microsoft Authenticode identifies the publisher of signed software and verifies that signed software has not changed since publication: https://learn.microsoft.com/en-us/windows-hardware/drivers/install/authenticode. Android's `apksigner` supports signing APKs and verifying APK signatures, including printing certificate information: https://developer.android.com/tools/apksigner.
  - Touches: `scripts/sync-profile.ps1`, `schemas/profile-projects.v1.json`, `reports/profile-sync-report.json`, `scripts/write-profile-sync-summary.ps1`, `projects.json`, README generated action labels, downstream portfolio download cards, release workflows in sibling repos over time.
  - Proposed feed fields: `releaseTrust.checksumAssets`, `releaseTrust.hasChecksumForEveryExecutable`, `releaseTrust.signatureAssets`, `releaseTrust.hasAuthenticodeSignature` (when known), `releaseTrust.apkSignatureVerified` (when locally verifiable), `releaseTrust.sbomAssets`, `releaseTrust.attestationAvailable`, `releaseTrust.debugArtifactPresent`, `releaseTrust.sourceOnlyRelease`, `releaseTrust.trustLevel` (`unknown`, `metadata-only`, `checksum`, `signed`, `attested`, `signed-and-attested`), and `releaseTrust.notesPublic`.
  - Recommended staged rollout: first derive filename-based metadata from release assets without downloading binaries; next add optional artifact download and local verification for a small allowlist of executable rows; finally add build-workflow guidance for sibling repos to publish checksums, SBOMs, and GitHub artifact attestations consistently.
  - Acceptance: the sync report warns when visitor-facing executable downloads lack checksum assets; debug APKs are flagged separately from release APKs; schema requires the `releaseTrust` object for rows with latest releases; README/portfolio can display a small public trust summary without implying stronger guarantees than verified; source-only releases remain valid repo actions but are counted distinctly.
  - Completed: v4.9.44 adds `releaseTrust` to every visitor-facing project row, records checksum/signature/SBOM/attestation/debug/source-only filename evidence, reports 55 executable download rows missing complete checksum coverage, reports 3 debug artifact rows, and validates the object through schema and Pester coverage.
  - Verify: run feed generation and confirm all 58 executable/archive download rows have `releaseTrust`; add a fixture release with `.sha256`, `.sig`, `sbom`, and `debug.apk` assets and confirm classification; use `gh attestation verify` on an attested fixture artifact when available; run `scripts/sync-profile.ps1 -Write -Check` and portfolio feed tests.
  - Complexity: M-L

### Researcher Queue (Cycle 43 - 2026-06-06)

*Research conducted 2026-06-06. This pass converted the branch-protection
backlog into an enforcement sequence that avoids breaking the current
direct-push automation.*

- [ ] P2 - Stage branch protection or ruleset enforcement behind PR delivery
  - Why: the repo has enough always-created CI checks to protect `main`, but enabling required checks while this autonomous loop still pushes directly to `main` and `enforce_admins=true` would block future maintenance unless PR delivery or an explicit bypass is in place first.
  - Evidence: `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection/required_status_checks` currently returns `404 Required status checks not enabled`; `gh api repos/SysAdminDoc/SysAdminDoc/rulesets` returns `[]`; `gh pr list --state open` currently shows Dependabot PR #7 (`dependabot/github_actions/routine-actions-0321e4ed66`). Current branch protection has `enforce_admins.enabled=true`, `required_conversation_resolution.enabled=true`, `allow_force_pushes.enabled=false`, and `allow_deletions.enabled=false`, but no required status checks or required PR review object. Local workflows now have always-created PR/merge-queue candidates: `.github/workflows/tests.yml` defines `PSScriptAnalyzer`, `Pester (offline)`, `Markdownlint`, and `Windows setup smoke`; `.github/workflows/profile-sync.yml` defines `Check generated README`; `.github/workflows/workflow-security.yml` defines `zizmor`; all three include `pull_request` plus `merge_group`. Current PR #7 check evidence shows `Markdownlint`, `PSScriptAnalyzer`, `Windows setup smoke`, and `zizmor` passing, with `Pester (offline)` and `Check generated README` failing on the Dependabot branch.
  - Source notes: GitHub branch protection can require PRs, approvals, code-owner review, status checks, conversation resolution, signed commits, linear history, and merge queue: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule. GitHub merge queues require workflows to trigger on `merge_group` or required checks will not be reported: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue. Rulesets can be active or disabled, can require status checks and reviews, and can allow PR-only bypasses for selected actors: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository and https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets. GitHub Actions `jobs.<job_id>.name` controls the job name displayed in the UI: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax.
  - Recommended sequence:
    1. Keep the already-shipped `Windows setup smoke` and `Markdownlint` jobs in the candidate required-check set.
    2. Move this autonomous loop to PR-based delivery, or document a narrow allowed bypass before enabling required checks.
    3. Create a disabled ruleset or branch-protection draft that targets `main` and requires `PSScriptAnalyzer`, `Pester (offline)`, `Markdownlint`, `Windows setup smoke`, `Check generated README`, and `zizmor`.
    4. Run a real PR and merge-group proof so each required check is present with the exact UI check name.
    5. Enable active enforcement only after the proof PR is mergeable without direct pushes.
  - Progress: v4.9.85 adds `requiredCheckReadiness.workflowCoverage` and `prDeliveryTransition` so the PR-delivery checklist is machine-readable before any enforcement setting changes. The transition report currently marks candidate checks and workflow coverage ready, while recent successful check-run proof needs live validation and PR delivery or bypass remains blocked. v4.9.91 records hosted `dry-run-pr` evidence for run `27082852047`; the run uploaded a sync report artifact but failed at `Regenerate profile` before the preview helper ran, so it is evidence for the next fix rather than proof that generated PR delivery is ready. v4.9.92 adds an explicit success exit after `sync-profile.ps1 -Check` passes to prevent handled native-command failures from surfacing as hosted step failures. v4.9.93 refreshes the dry-run evidence with successful hosted run `27083372279`, which reached the preview helper and planned `automation/profile-sync-27083372279` without side effects. v4.9.99 refreshes the evidence with successful hosted run `27084524165` after artifact-runtime and summary-size guard changes; it reached the preview helper and planned `automation/profile-sync-27084524165` without side effects.
  - Acceptance: no required check is path-filtered or conditionally skipped on PRs; required checks are pinned to the GitHub Actions app/source where possible; CODEOWNERS review is required only after a PR author/reviewer model is defined; a rollback note records how to temporarily disable the rule if automation is locked out; the roadmap/loop state stops recommending direct pushes after enforcement is active.
  - Risks: requiring `Check generated README` can force live-link/profile-smoke dependencies onto every PR; requiring `zizmor` before exact tool pinning can create supply-chain update friction; code-owner review is weak for a single-user repo unless the user wants self-review controls; merge queue is overkill unless PR volume increases.
  - Verify: open a disposable PR touching `README.md`, `.github/workflows/tests.yml`, and `setup.ps1`; confirm all required candidate jobs are created on PR and `merge_group`; query branch protection/rulesets after enforcement; confirm direct push behavior is intentionally blocked or bypassed according to the documented delivery model.
  - Complexity: M

### Researcher Queue (Cycle 44 - 2026-06-06)

*Research conducted 2026-06-06. This pass reviewed the motion safety and
third-party render-host state of the generated GitHub profile chrome.*

- [x] P2 - Make generated profile chrome motion-safe and reduce external render-host dependence
  - Why: the profile is a public trust surface, not a marketing landing page. Auto-playing typing/fade animation and third-party image rendering can distract visitors, fail in restricted networks, and make accessibility/reliability dependent on services outside the repo.
  - Evidence: `README.md:2` embeds `https://capsule-render.vercel.app/api?...animation=fadeIn...` for the header; `README.md:11` embeds `https://readme-typing-svg.demolab.com?...duration=4000&pause=1000&repeat=true...`; `README.md:52-53` embeds `skillicons.dev` for static icon chrome; `README.md:734` embeds the capsule-render footer wave. `scripts/sync-profile.ps1:1465-1468`, `1489-1499`, and `1521-1522` generate these URLs. `reports/profile-sync-report.json.readmeExperienceChecks` currently passes `themeAwareImageChrome=true`, `thirdPartyMetricHostCount=0`, `thirdPartyBadgeHostCount=0`, and `profileStatsChromeCount=1`, but there is no `motionSafeChrome`, `thirdPartyRenderHostCount`, or host allowlist/denylist for capsule-render/readme-typing-svg/skillicons. `scripts/sync-profile.ps1:1353-1355` already generates committed SVG panels with `<title>` and `<desc>`, so local static SVG generation is already part of the architecture.
  - Source notes: WCAG Pause, Stop, Hide requires a mechanism to pause/stop/hide moving, blinking, scrolling, or auto-updating content that starts automatically and runs in parallel with other content: https://www.w3.org/WAI/WCAG22/Understanding/pause-stop-hide. The CSS `prefers-reduced-motion` media feature detects a user's reduced-motion preference, but static README images from third-party services cannot reliably negotiate a per-user pause control inside GitHub-rendered Markdown: https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion. GitHub supports relative image paths in READMEs, which lets the repo replace external generated images with committed local assets: https://docs.github.com/articles/about-readmes. GitHub anonymizes image URLs but warns that anyone with an anonymized URL may view the image/video, so self-hosted committed assets are still simpler for a profile trust surface: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-anonymized-urls.
  - Touches: `scripts/sync-profile.ps1` (`Update-Header`, `Test-ReadmeExperience`, SVG helpers), `README.md`, `assets/profile/*.svg` or new `assets/profile/header-*.svg`, `reports/profile-sync-report.json`, `tests/sync-profile.Tests.ps1`, optional `PROJECT_CONTEXT.md`.
  - Recommended implementation: replace the animated typing SVG with a static local text/SVG panel or plain Markdown line; remove `animation=fadeIn` from capsule URLs or replace the capsule header/footer with committed local SVGs; keep `skillicons.dev` only if a recorded decision says the static third-party icon host is acceptable, otherwise commit a local icon strip. Add `readmeExperienceChecks.motionSafeChrome` and `readmeExperienceChecks.thirdPartyRenderHosts` with an explicit allowlist.
  - Acceptance: generated README contains no `animation=`, `repeat=true`, or known typing/capsule auto-motion parameters; `readmeExperienceChecks.motionSafeChrome=true`; external render hosts are either zero or explicitly listed with reason, fallback, and failure behavior; live rendered smoke still passes desktop and 390px mobile with no failed images or overflow; image alt text remains meaningful.
  - Verify: run `rg -n "animation=|repeat=true|readme-typing-svg|capsule-render" README.md scripts/sync-profile.ps1`; run `scripts/sync-profile.ps1 -Write -Check`; run `scripts/render-profile-smoke.ps1`; confirm `reports/profile-sync-report.json.readmeExperienceChecks.motionSafeChrome` is true.
  - Completed: v4.9.47 removes external capsule-render/readme-typing output from generated profile chrome, adds local static header/footer SVG assets, records third-party render hosts in `readmeExperienceChecks`, and reports zero render hosts for the current compact README. v4.9.71 adds `docs/decisions/2026-06-06-profile-render-hosts.md` to keep the zero-retained-host decision explicit.
  - Complexity: M

### Researcher Queue (Cycle 45 - 2026-06-06)

*Research conducted 2026-06-06. This pass checked whether CodeQL/default
code scanning is currently useful for this repository's actual language mix.*

- [x] P3 - Record code-scanning posture and avoid a low-value CodeQL default-setup chase
  - Why: code scanning is a useful repository trust signal, but this repo is currently PowerShell-only by GitHub language accounting. Enabling CodeQL default setup without a supported language would not add meaningful scan coverage; the higher-value controls are PSScriptAnalyzer, actionlint, zizmor, Scorecard, secret scanning, and a future report schema.
  - Evidence: `gh api repos/SysAdminDoc/SysAdminDoc/languages` returned only `{"PowerShell":210925}`; local source inspection found four `.ps1` files, five workflow `.yml` files, and three schema/report JSON files under `.github/workflows`, `scripts`, `tests`, and `schemas`. `gh api repos/SysAdminDoc/SysAdminDoc/code-scanning/alerts --jq length` returned `404 no analysis found` and also reported the local token would need `admin:repo_hook` scope for that API operation. `.github/workflows/scorecard.yml` uploads Scorecard SARIF with `github/codeql-action/upload-sarif`, but there is no CodeQL analysis workflow and no CodeQL-supported source language in the profile repo itself.
  - Source notes: GitHub's CodeQL supported-language list does not include PowerShell: https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/. GitHub's default setup docs state that if analyses fail for all CodeQL-supported languages, default setup remains enabled but runs no scans until a supported language is added and successfully analyzed: https://docs.github.com/en/code-security/code-scanning/enabling-code-scanning/configuring-default-setup-for-code-scanning. GitHub's code-scanning REST API documents `404` as a possible response for code-scanning endpoints: https://docs.github.com/en/rest/code-scanning/code-scanning.
  - Touches: `scripts/sync-profile.ps1` future `repositorySettings`/security report block, `reports/profile-sync-report.json`, `PROJECT_CONTEXT.md`, optional `.github/workflows/codeql.yml` only if a supported language is added later.
  - Recommended behavior: report `codeScanning.status=no-analysis` and `codeScanning.recommendation=not-applicable-powerShell-only` rather than treating missing CodeQL as a failure. Keep Scorecard SARIF upload, PSScriptAnalyzer, workflow security, secret scanning, and push protection as the active controls. Revisit CodeQL only if JavaScript/TypeScript/Python/C#/Kotlin/etc. source enters this repo.
  - Acceptance: repository/security baseline report distinguishes "not applicable" from "misconfigured"; no failing CodeQL workflow is added for a PowerShell-only repo; future supported-language detection can raise a warning prompting CodeQL default setup or advanced setup.
  - Verify: run `gh api repos/SysAdminDoc/SysAdminDoc/languages`; run the code-scanning alerts probe with graceful 404 handling; confirm report output is public-safe and does not require extra token scopes for normal `-Check`.
  - Completed: v4.9.79 expands `repositorySettings.security.codeScanning`, records the decision note, surfaces summary rows, and adds Pester coverage for both the current PowerShell-only posture and future CodeQL-supported language detection.
  - Complexity: S

### Researcher Queue (Cycle 46 - 2026-06-06)

*Research conducted 2026-06-06. This pass revisited the sync-report JSON
contract now that provenance, community settings, release trust, and
motion-safety sections are all planned additions.*

- [x] P2 - Promote `profile-sync-report.json` to a versioned schema contract
  - Why: `reports/profile-sync-report.json` is now the central evidence artifact for generated README health, link validation, release drift, schema validation, planning-doc consistency, validation performance, and workflow summaries. New planned sections will make the shape larger and more consumer-facing, so the report needs the same versioned contract discipline as the catalog and public feed.
  - Evidence: `reports/profile-sync-report.json` currently has 23 top-level fields including `metadataHygiene`, `releaseAssetDrift`, `schemaValidation`, `docVersionConsistency`, `validationPerformance`, `metadataDrift`, `linkValidationSummary`, and `readmeExperienceChecks`, but it has no top-level `schema` or `$schema` pointer. `schemas/` contains only `profile-catalog.v1.json` and `profile-projects.v1.json`. `scripts/sync-profile.ps1:2498-2517` validates only catalog/feed schemas through `Test-FeedSchemaContracts`; `tests/sync-profile.Tests.ps1:478-510` exercises catalog/feed schema validation, not report schema validation. The current report also has volatile live-data sections with arrays of 69 missing-topic rows, 17 source-only release rows, and 5 metadata-drift rows, so downstream summary consumers need stable required/optional rules.
  - Source notes: JSON Schema describes itself as a vocabulary for JSON data consistency, validity, and interoperability at scale: https://json-schema.org/. The repo's custom validator already fails closed on unsupported schema keywords, which makes adding a report schema safer as long as the first version stays within the supported keyword subset.
  - Touches: `schemas/profile-sync-report.v1.json`, `scripts/sync-profile.ps1`, `reports/profile-sync-report.json`, `scripts/write-profile-sync-summary.ps1`, `tests/sync-profile.Tests.ps1`, optional `PROJECT_CONTEXT.md`.
  - Recommended schema shape: add top-level `schema`, `generatedAt`, core booleans/counts, required objects for `metadataHygiene`, `releaseAssetDrift`, `schemaValidation`, `docVersionConsistency`, `validationPerformance`, `linkValidationSummary`, and `readmeExperienceChecks`; keep newly planned `repositorySettings`, `provenance`, `releaseTrust`, and `motionSafeChrome` fields optional in v1 until implemented; disallow unexpected top-level properties only after the generator and summary helper are updated together.
  - Acceptance: the report advertises a raw-GitHub schema URL; `-Check` validates the generated report against `schemas/profile-sync-report.v1.json`; Pester includes a fixture proving a missing required section fails; workflow summaries rely only on schema-backed fields; volatile row arrays have item schemas but allow empty arrays.
  - Completed: v4.9.45 ships the report schema, top-level report schema URL, `schemaValidation.report`, report-schema failure wiring, and Pester coverage for valid and missing-section reports.
  - Verify: run `scripts/sync-profile.ps1 -Write -Check`; intentionally remove `readmeExperienceChecks` from a fixture report and confirm schema validation fails; confirm `scripts/write-profile-sync-summary.ps1` still renders the report without private/suppressed repo details.
  - Complexity: M

### Researcher Queue (Cycle 47 - 2026-06-06)

*Research conducted 2026-06-06. This pass inspected the downstream
`sysadmindoc.github.io` feed importer before changing the public profile feed
shape.*

- [x] P1 - Add downstream portfolio compatibility tests before changing feed shape
  - Why: `projects.json` is no longer only an in-repo artifact; the portfolio build fetches it at build time. Suppressed-row redaction, provenance, timestamp semantics, and release-trust fields should be introduced without silently breaking the portfolio's generated routes, counts, and download cards.
  - Evidence: in the separate `\\vmware-host\Shared Folders\repos\sysadmindoc.github.io` repo, `scripts/sync-profile-feed.mjs` fetches `https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/projects.json`, validates it through `scripts/lib/profile-feed.mjs`, and writes `src/data/_profile-projects.json`. `scripts/lib/profile-feed.mjs` filters only `payload.projects`, rejects empty visible project sets, requires `repo`, `title`, `category`, `description`, and `repoUrl`, and returns `{ ...payload, feedSourceUrl, cachedAt, projectCount, projects }`, so unknown top-level fields are preserved. `src/data/portfolio.ts` exposes `profileFeedInfo.generatedAt`, `cachedAt`, `feedSourceUrl`, `source`, `publicRepoCount`, `projectCount`, and `suppressedCount`, but has no typed handling for `provenance`, `catalogGeneratedAt`, `metadataSnapshotAt`, or `releaseTrust`. `src/data/generated.d.ts` currently allows `suppressed?: GeneratedProfileProject[]`, and `test/profile-feed.test.mjs` only tests filtering suppressed/non-portfolio rows inside `projects`, not a redacted `suppressed` array.
  - Current downstream state: the portfolio worktree is dirty from unrelated work, so this roadmap pass treated it as read-only evidence and did not modify it.
  - Touches: this repo's `schemas/profile-projects.v1.json`, `projects.json`, and generator; downstream `scripts/lib/profile-feed.mjs`, `src/data/portfolio.ts`, `src/data/generated.d.ts`, `src/data/fixtures/generated/_profile-projects.json`, `test/profile-feed.test.mjs`, and endpoint/schema audits.
  - Recommended compatibility path: add a portfolio fixture that contains feed `provenance`, split timestamp fields, `releaseTrust`, and redacted suppressed rows before changing the live profile feed. Then update profile feed schema/generator in this repo. Keep additive fields backwards-compatible first; make suppressed redaction a schema major/minor decision with downstream tests proving ignored suppressed details do not leak into routes or caches.
  - Acceptance: portfolio build still renders 177 visible projects from a new feed fixture; `profileFeedInfo` can surface new provenance/timestamp fields or safely ignore them; redacted `suppressed` rows do not require `repo` or `repoUrl`; no suppressed/private project route is generated; portfolio endpoint audits still pass.
  - Verify: in the portfolio repo, run `npm test -- profile-feed` or the full `npm test` after fixture updates, then run `npm run check` or `npm run build` when the feed contract changes; in this repo, regenerate `projects.json` and confirm raw feed consumers still see a valid schema URL.
  - Completed: v4.9.80 adds an in-repo `portfolioCompatibility` report snapshot, summary rows, schema coverage, and Pester guards for the known downstream contract without modifying the separate portfolio repo.
  - Complexity: M

### Researcher Queue (Cycle 48 - 2026-06-06)

*Research conducted 2026-06-06. This pass measured generated README/feed
weight and checked the current rendered profile smoke output.*

- [x] P2 - Add generated README/feed size and render-budget reporting
  - Why: the profile README is generated and can grow quietly as the catalog expands. The current rendered smoke proves it still fits today, but there is no budget warning before the README becomes too long to scan, expensive to render, or noisy in pull-request review.
  - Evidence: current artifact measurements are `README.md` 74,664 bytes / 735 lines, `projects.json` 293,666 bytes / 9,196 lines, `reports/profile-sync-report.json` 29,049 bytes / 1,166 lines, and six profile SVG panels totaling 15,338 bytes. The README has 164 Markdown table rows, 11 `<details>` blocks, 7 image tags, and 78 fenced code blocks. `reports/rendered-profile-smoke.json` from 2026-06-05 passed at 1280px desktop and 390px mobile; it found no missing sections, failed images, root overflow, or document overflow. `.gitattributes` marks `README.md`, `projects.json`, `reports/*.json`, and `assets/profile/*.svg` as `linguist-generated`, so GitHub can collapse generated diffs, but that does not tell maintainers when the visitor-facing README is getting too dense.
  - Source notes: GitHub profile READMEs render from a username-matching public root `README.md`: https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-github-profile/customizing-your-profile/managing-your-profile-readme. GitHub's large-file docs describe repository file-size warnings and hard limits, but the budgets here should be much lower because this is about profile scan quality and review ergonomics, not Git storage limits: https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github. GitHub's `.gitattributes` docs explain `linguist-generated` for hiding generated files in diffs and language stats: https://docs.github.com/en/repositories/working-with-files/managing-files/customizing-how-changed-files-appear-on-github.
  - Touches: `scripts/sync-profile.ps1`, `reports/profile-sync-report.json`, `scripts/write-profile-sync-summary.ps1`, `scripts/render-profile-smoke.ps1`, `tests/sync-profile.Tests.ps1`, optional `.gitattributes` policy note.
  - Proposed budgets: warn when README exceeds 100 KB, 1,000 lines, 220 table rows, 15 details blocks, 10 image tags, or 100 code blocks; warn when `projects.json` exceeds 500 KB; warn when sync report exceeds 100 KB; warn when rendered smoke finds mobile root width below 300px, any image failure, any overflow, or more than a configured number of failed/third-party render hosts. Keep failures informational first, then promote severe render failures to fatal.
  - Acceptance: `reports/profile-sync-report.json` includes `artifactBudgets` and `renderedProfileSmoke` summary fields; job summary prints byte/line counts and warning status; Pester covers budget calculation with small fixtures; thresholds are documented as profile-review budgets, not GitHub hard limits.
  - Verify: run the budget function against current files and confirm all current values are below warning thresholds; inflate a fixture README past 100 KB and confirm warning; run `scripts/render-profile-smoke.ps1` and confirm report aggregation stays public-safe.
  - Completed: v4.9.84 adds `artifactBudgets`, `renderedProfileSmoke`, summary rows, schema coverage, live smoke report patching, and Pester guards. Current generated artifacts are within budget with 0 warnings and live rendered smoke passes with 0 warnings at desktop and mobile widths.
  - Complexity: S-M

## Continuation State

Last autonomous roadmap pass: Cycle 107 - 2026-06-07.

Current local state:

- Repo: `C:\Users\--\repos\SysAdminDoc`
- HEAD inspected before this cycle: `f6cd6b9 ci: guard profile summary size`
- Worktree before implementation: clean on `main...origin/main`.
- Live GitHub branch protection check: required status checks are not enabled (`404 Required status checks not enabled`), no repository rulesets exist, and protected `main` still has `enforce_admins=true`, required conversation resolution, force-push blocking, and deletion blocking.
- Dependabot PR #7 was triaged and closed as obsolete after the same 4.36.2 SHA landed directly on `main` in `c18bd58` with matching Pester/docs updates.
- Cycle 82 reconciled stale duplicate roadmap rows for Windows setup smoke, CI validation tool pins, public-repo enumeration limits, generated-artifact `.gitattributes`, generated automation branch cleanup, and suppressed-feed redaction against their shipped evidence.
- Cycle 83 applied the routine `github/codeql-action/upload-sarif` 4.36.2 update from Dependabot PR #7 on `main`.
- Cycle 84 closed the now-obsolete PR #7 branch and recorded the closure.
- Cycle 85 recorded required-check enforcement readiness in a decision note with candidate checks, live branch-protection/ruleset evidence, and activation preconditions.
- Cycle 86 added README density reporting for portfolio-only review inputs.
- Cycle 87 recorded PowerShell-only code-scanning posture and active SARIF/static-analysis controls.
- Cycle 88 added downstream portfolio compatibility reporting for the public feed contract.
- Cycle 89 added REST fallback release-fetch policy/progress reporting under `validationPerformance`.
- Cycle 90 added machine-readable required-check readiness reporting without enabling enforcement.
- Cycle 91 added README density routing-decision reporting; current evidence keeps the README as the public routing surface while recording 11 Python-category rows for portfolio-only review.
- Cycle 92 added generated artifact/render-budget reporting; current artifact budgets are within budget and live rendered smoke passes with 0 warnings.
- Cycle 93 added PR-delivery transition checklist reporting; current candidate checks/workflow coverage are ready, but required-check enforcement remains blocked by direct-main delivery and live PR proof.
- Cycle 94 added concrete README portfolio-only review candidate rows; current Python candidates are selected deterministically but README inclusion is unchanged.
- Cycle 95 added a report-only portfolio demotion preview; the selected 11 Python candidates would reduce README rows from 177 to 166 and clear the current category soft-limit warning without mutating the catalog, README, or projects feed.
- Cycle 96 added a side-effect-free generated PR delivery dry-run helper and read-only Profile sync `dry-run-pr` workflow mode.
- Cycle 97 added catalog-backed review notes for the selected README portfolio-only candidates and surfaced those notes in the report-only candidate rows without exporting them to `projects.json`.
- Cycle 98 added deterministic sorting for hash-backed aggregate report rows, starting with license count and suppression-reason count arrays that previously churned across live metadata snapshots.
- Cycle 99 recorded the hosted generated PR dry-run evidence in required-check readiness; the run uploaded a report artifact but failed before the preview helper, so generated PR delivery remains unproven.
- Cycle 100 added an explicit successful exit path after `sync-profile.ps1 -Check` passes, targeting the hosted dry-run regenerate step failure observed in run `27082852047`.
- Cycle 101 refreshed generated PR dry-run evidence from successful hosted run `27083372279`, including preview-helper proof and the planned generated branch.
- Cycle 102 added a public portfolio-only demotion decision that approves the current 11 reviewed candidates for a later catalog mutation without changing generated output yet.
- Cycle 103 applied the approved 11-row catalog mutation, removed those rows from generated README output, preserved them in the portfolio feed, and cleared the README density warning.
- Cycle 104 extended exact-order Pester coverage to release asset kind counts, release trust level counts, and portfolio primary action kind counts.
- Cycle 105 pinned retained `actions/upload-artifact` workflow uses to the reviewed 6.0.0 Node 24 SHA and added Pester guards against floating tags and the older Node 20 SHA.
- Cycle 106 added a GitHub Actions step-summary size guard and Pester budget check for the profile sync summary helper.
- Cycle 107 refreshed hosted generated PR dry-run evidence after the artifact-runtime and summary-size guard changes; run `27084524165` reached the preview helper and planned `automation/profile-sync-27084524165` without side effects.
- Current feed/report contracts include public-safe redacted suppression records, feed and report provenance, sync-report schema validation, release/download trust metadata, userscript install trust, stale-project/archive-review reporting, downstream portfolio compatibility, REST fallback release-fetch state, required-check readiness, and the generated README-safe markdownlint lane.
- Branch-protection/ruleset required-check enforcement remains external-gated while direct pushes to `main` are the delivery path.

Next research cycles:

1. Cycle 108: review the remaining GitHub Actions dependency pin surface for hosted runtime warnings or major-update readiness.
2. Cycle 109: audit README/report density again after the next live metadata refresh and route any new low-signal rows through the review pipeline.
3. Cycle 110: exercise generated PR delivery against a disposable branch or PR only after a safe bypass/review model is documented.

### Quick Wins

P2/P3, each doable in well under an hour:

- [x] P1 — Fix the advertised Windows PowerShell `setup.ps1 -CheckOnly` parser failure (completed v4.9.41 with ASCII-only `setup.ps1`, Windows PowerShell verification, and Pester coverage).

- [x] P2 — Generated-README size budget guard (completed v4.9.51 with `readmeSizeBudget`, a 96 KiB informational soft cap, schema coverage, and Pester warning checks).
- [x] P2 — Generated README density report for portfolio-only review inputs (completed v4.9.78 with `readmeDensity`, summary-helper output, schema coverage, and Pester guards).
- [x] P3 — Code-scanning posture for the PowerShell-only profile repo (completed v4.9.79 with `repositorySettings.security.codeScanning`, summary rows, a decision note, and future supported-language warning coverage).
- [x] P1 — Downstream portfolio compatibility snapshot before feed-shape changes (completed v4.9.80 with `portfolioCompatibility`, summary rows, schema coverage, and Pester guards).
- [x] P2 — REST fallback release-fetch policy/progress reporting (completed v4.9.81 with `validationPerformance.restFallbackReleaseFetch`, summary rows, schema coverage, and Pester guards).
- [x] P2 — Required-check readiness report without enabling enforcement (completed v4.9.82 with `repositorySettings.requiredCheckReadiness`, summary rows, schema coverage, and Pester guards).
- [x] P2 — PR-delivery transition checklist before required-check enforcement (completed v4.9.85 with `workflowCoverage`, `prDeliveryTransition`, summary rows, schema coverage, a decision note, and Pester guards).
- [x] P2 — Generated PR delivery dry-run helper (completed v4.9.88 with `open-generated-profile-pr.ps1 -DryRun`, a read-only Profile sync `dry-run-pr` mode, side-effect guards, and Pester coverage).
- [x] P2 — Generated PR dry-run evidence report (completed v4.9.91 with hosted run ID, failure step, skipped preview state, uploaded report-artifact state, schema coverage, summary rows, and Pester guards).
- [x] P2 — Hosted profile-check success exit hardening (completed v4.9.92 with explicit successful `sync-profile.ps1 -Check` exit and Pester entrypoint guard).
- [x] P2 — Hosted generated PR dry-run success evidence (completed v4.9.93 with successful run `27083372279`, preview-helper proof, planned branch, artifact upload, schema-backed report fields, and Pester guards).
- [x] P2 — Hosted generated PR dry-run refresh after workflow-runtime hardening (completed v4.9.99 with successful run `27084524165`, Node 24 artifact-upload path proof, summary helper proof, planned branch, and no side effects).
- [x] P2 — Portfolio-only demotion decision note (completed v4.9.94 with an approved 11-row decision, no-mutation boundary, preview evidence, and Pester guard).
- [x] P2 — Approved portfolio-only catalog mutation (completed v4.9.95 with the 11 approved rows removed from README output, preserved in `projects.json`, and covered by Pester).
- [x] P2 — Catalog-backed README candidate review notes (completed v4.9.89 with optional `readmeReviewNote` catalog context and `catalogReviewNote` candidate report fields that do not export to `projects.json`).
- [x] P2 — Deterministic aggregate report row ordering (completed v4.9.90 with explicit key sorting for license and suppression reason count rows plus Pester exact-order coverage).
- [x] P2 — Extended deterministic report row-order assertions (completed v4.9.96 with exact-order Pester coverage for release asset kind counts, release trust counts, and portfolio primary action kind counts).
- [x] P2 — Upload-artifact Node 24 runtime pin (completed v4.9.97 with all retained report/smoke artifacts pinned to the reviewed `actions/upload-artifact` 6.0.0 SHA and Pester guards against floating tags or the older Node 20 SHA).
- [x] P2 — README density routing-decision report (completed v4.9.83 with `routingRecommendation`, portfolio-only candidate counts, category soft-limit overflow, summary rows, schema coverage, a decision note, and Pester guards).
- [x] P2 — Concrete README portfolio-only review candidate rows (completed v4.9.86 with `portfolioOnlyCandidateSelectionPolicy`, `portfolioOnlyCandidates`, reason codes, summary sample output, schema coverage, and Pester guards).
- [x] P2 — Portfolio-only catalog review preview mode (completed v4.9.87 with report-only row-delta/category-impact previewing, mutation flags, summary rows, schema coverage, and Pester guards).
- [x] P2 — Generated artifact/render-budget report (completed v4.9.84 with `artifactBudgets`, `renderedProfileSmoke`, summary rows, schema coverage, live smoke report patching, and Pester guards).
- [x] P2 — SECURITY.md with a public-safe disclosure path and guided issue/PR intake (completed v4.9.29 with `SECURITY.md`, issue forms, issue chooser config, PR template, and Pester coverage).
- [x] P1 — Generated-profile validation on PRs for catalog/feed/profile contract paths (completed v4.9.28 with a read-only `pull_request` trigger and Pester path coverage).
- [x] P2 — Profile-sync Actions job summary from `reports/profile-sync-report.json` (completed v4.9.31 with `scripts/write-profile-sync-summary.ps1`, workflow wiring, retained artifacts, and Pester coverage).
- [x] P2 — Profile-sync Actions summary size budget (completed v4.9.98 with a 1 MiB hard-limit guard, 65536-byte local soft budget, and Pester coverage for the committed summary output).
- [x] P2 — `actionlint` in `workflow-security.yml` alongside `zizmor` (completed v4.9.33 with checksum-verified actionlint 1.7.12 and Pester wiring coverage).
- [x] P2 — Windows `setup.ps1 -CheckOnly` smoke job for setup/README changes (completed v4.9.41 with an always-created `Windows setup smoke` job).
- [x] P2 — Exact pins for CI-installed `zizmor` and Pester validation tools (completed v4.9.46 with Pester 5.7.1 `-RequiredVersion`, hash-checked `zizmor` 1.25.2 requirements, toolchain docs, and Pester coverage).
- [x] P2 — Reduced-motion/static guard for profile hero and typing SVG chrome (completed v4.9.47 with static local header/footer SVGs, `motionSafeChrome`, render-host reporting, schema updates, and Pester regression coverage).
- [x] P2 — Generated profile PR validation handoff for `GITHUB_TOKEN`-created branches (completed v4.9.54 with branch-scoped `profile-sync.yml` check dispatch from generated PR workflows).
- [x] P2 — Profile-assets refresh report artifact and job summary parity (completed v4.9.31 with shared summary helper and retained report artifact).
- [x] P2 — Expanded CODEOWNERS coverage for public profile contract files (completed v4.9.38).
- [x] P2 — Per-project SPDX/license fields in `projects.json` and the sync report (completed v4.9.55 with visitor-facing `licenseKey`/`licenseName`/`licenseSpdxId`, report aggregates, schema validation, and Pester coverage).
- [x] P2 — GitHub fork-parent drift report for catalog `forkOf` attribution (completed v4.9.56 with live `isFork` collection, REST parent enrichment, warning-only drift rows, schema support, summary rows, and Pester coverage).
- [x] P2 — Public-repo enumeration limit guard for `gh repo list --limit 300` (completed v4.9.36: raised to 500 with truncation warning).
- [x] P2 — JSON Schema contract for `reports/profile-sync-report.json` (completed v4.9.45 with `schemas/profile-sync-report.v1.json`, report `schema`, `schemaValidation.report`, `-Check` failure wiring, and Pester malformed-report coverage).
- [x] P2 — `.gitattributes` generated-artifact diff policy for feed/report/SVG churn (completed v4.9.37).
- [x] P2 — Profile repo release/tag consistency check for `v4.9.x` planning versions (completed v4.9.57 with `profileReleaseConsistency`, warning-only latest-release/tag drift rows, schema support, summary rows, and Pester coverage).
- [x] P2 — Userscript install trust metadata for raw `.user.js` actions (completed v4.9.58 with `userscriptInstallTrust`, schema support, summary rows, live report counts, and Pester coverage).
- [x] P2 — Live GitHub-rendered profile smoke check with screenshot artifacts (completed v4.9.27 with `scripts/render-profile-smoke.ps1`, profile-sync workflow artifact upload, and Pester wiring coverage).
- [ ] P2 🔧 — Require branch protection/ruleset status checks on `main` (v4.9.30 completed always-created PR/merge-queue check readiness; v4.9.77 recorded activation preconditions and candidate checks; external enforcement remains gated by the direct-push loop).
- [x] P2 — Pull-request profile-sync validation for catalog/profile changes (duplicate row reconciled in v4.9.60; completed v4.9.28 with read-only pull-request profile-sync validation and trigger-surface Pester coverage).
- [x] P2 — Explicit GitHub Actions timeout budgets for validation and refresh jobs (completed v4.9.32 with job-level budgets and Pester coverage).
- [x] P2 — Structured issue forms for broken catalog links and profile corrections (duplicate row reconciled in v4.9.60; completed v4.9.29 with `SECURITY.md`, issue forms, issue chooser config, PR template, and Pester coverage).
- [x] P2 — Current Dependabot workflow-action PR triage (#5 addressed in v4.9.34; #6 addressed in v4.9.35; #7 addressed in v4.9.75).
- [x] P3 — Auto-delete or cleanup policy for generated `automation/*` PR branches (completed v4.9.61 with scheduled dry-run/manual cleanup workflow, strict generated-branch prefixes, merged-PR gating, scoped write permissions, and Pester coverage).
- [x] P3 — Shared helper/composite action for generated profile PR creation (completed v4.9.62 with `scripts/open-generated-profile-pr.ps1`, explicit workflow inputs, branch-prefix allowlist, no-change guard preservation, validation handoff, and Pester coverage).
- [x] P3 — Historical `CHANGELOG.md` release-heading validation and cleanup (completed v4.9.63 with `docVersionConsistency.changelogHeadingValidation`, line-numbered malformed-heading reporting, impossible-date rejection, schema support, Pester coverage, and the `v3.0.0` date cleanup).
- [x] P3 — Workflow-security trigger/audit coverage for future `.github/actions/**` (completed v4.9.64 with strict `zizmor` collection for workflows plus local action metadata, always-created workflow-security trigger coverage, `/.github/` CODEOWNERS ownership, and Pester contract coverage).
- [x] P3 — Stagger `assets-refresh` and `workflow-security` Wednesday schedules (completed v4.9.65 by moving workflow-security to `17 9 * * 3` and adding Pester schedule-uniqueness coverage).
- [x] P3 — Add `schemas/**` to the offline Tests workflow path filters (completed v4.9.66 with Tests push-path coverage and Pester trigger-shape guards).
- [x] P3 — Dependabot routine GitHub Actions update grouping (completed v4.9.67 with a minor/patch `routine-actions` group and Pester coverage that keeps majors separate).
- [x] P2 — Catalog-to-feed omitted-row accounting in the sync report (completed v4.9.59 with `catalogFeedAccounting`, public-safe unaccounted rows, fatal count mismatches, schema support, summary rows, and Pester coverage).
- [x] P3 — Fail closed on unsupported custom JSON Schema validator keywords (completed v4.9.39: Test-SchemaKeywordCoverage warns on unsupported keywords with Pester coverage).
- [x] P3 — Internal title/description metadata for generated profile SVG panels (completed v4.9.68 with stable SVG title/description IDs, row-summary descriptions, and Pester XML coverage).
- [x] P3 — Refresh stale catalog field names in completed-work docs (completed v4.9.69 with a schema-backed completed-work summary and Pester terminology guard).
- [x] P3 — `.editorconfig` pinning LF + final-newline + trim-trailing-whitespace (completed v4.9.70 with Markdown trim enforcement, LF pinning for formatting policy files, PR template cleanup, and Pester formatting-contract coverage).
- [x] P3 — Generated README-safe markdownlint check (completed v4.9.73 with pinned `markdownlint-cli2`, curated GitHub README rules, Tests workflow job, npm Dependabot coverage, and Pester contract checks).
- [x] P3 — Recorded decision note on the retained third-party render hosts (completed v4.9.71 as a zero-retained-host decision with report-backed Pester coverage).
- [x] P3 — Stale-project/archive-review report from `pushedAt`, latest releases, and suppression reasons (completed v4.9.72 with warning-only `staleProjectReview`, public-safe suppression grouping, schema support, summary rows, and Pester coverage).

### Larger Bets

P1/P2 needing design or staged rollout:

- [x] P1 — Publish the advertised JSON Schemas and validate the feed against them (completed v4.9.19 with committed raw-GitHub schemas and `schemaValidation`).
- [x] P1 — Doc version/date consistency gate wired into `-Check` and CI (completed v4.9.20 with `docVersionConsistency` in the existing profile-sync check/report path).
- [x] P1 — PSScriptAnalyzer static-analysis lane for `scripts/` and `setup.ps1` (completed v4.9.25 with curated settings, pinned CI install, and script fixes for analyzer findings).
- [x] P0 — OpenSSF Scorecard publish workflow repair (completed v4.9.26 by moving write permissions from workflow-level to Scorecard job-level permissions and adding Pester regression coverage).
- [x] P1 — Generated-feed provenance fields (`sourceRef`, catalog/generator hashes, metadata snapshot) (completed v4.9.43 with `projects.json.provenance`, report provenance, schema validation, and drift coverage).
- [x] P1 — Generated Markdown/text safety and URL-scheme validation for README/feed output (completed v4.9.38: https-only gate on liveUrl/userscriptUrl with Pester coverage).
- [x] P1 — Pester coverage for `Test-ProfileState`/`Update-Header`/medical-gate (v4.9.36–v4.9.39: projects-sync gate, URL-scheme, medical privacy gate; `Update-Header` idempotency deferred).
- [x] P1 — Public-feed redaction for private suppression rows (completed v4.9.42 with dedicated redacted `suppressedProject` feed rows).
- [x] P2 — Repository settings/community-health baseline in the sync report (completed v4.9.53 with public-safe `repositorySettings`/`communityHealth`, local required-file fatal gaps, unavailable-state handling, summary rows, schema support, and Pester coverage).
- [x] P2 — REST release-fallback N+1 cap with rate-limit awareness and partial-data abort (completed v4.9.50 with paginated REST enumeration, authenticated/capped release fetches, non-404 abort behavior, and fallback guard coverage).
- [x] P2 — Header/non-catalog link validation folded into the existing link gate (completed v4.9.49 with fatal portfolio/setup probes, non-fatal image-host warnings, report/schema fields, and Pester coverage).
- [x] P2 — Release/download trust metadata for visitor-facing EXE/APK/ZIP release rows (completed v4.9.44 with feed `releaseTrust`, schema coverage, trust-level counts, checksum-gap reporting, and debug artifact reporting).
- [x] P2 — Pinned CI validation-tool installs with a documented update path (completed v4.9.46 with exact Pester/PSScriptAnalyzer versions, hash-checked `zizmor`, and `docs/ci-toolchain.md`).
- [x] P2 — Motion-safe generated profile chrome with a `readmeExperienceChecks.motionSafeChrome` gate (completed v4.9.47 with generated report/schema fields and failure coverage for reintroduced motion patterns).
- [x] P2 — Generated profile PR validation handoff using a least-privilege token or explicit dispatch (completed v4.9.54 with scoped `actions: write`, PR body/summary validation links, and explicit `profile-sync.yml` check dispatch on generated branches).
- [x] P2 — Profile-assets refresh report artifact and public-safe summary parity (duplicate row reconciled in v4.9.55; completed v4.9.31 with shared public-safe summary helper and retained report artifacts).
- [x] P2 — CODEOWNERS coverage aligned with generated profile, schema, setup, and planning-doc paths (completed v4.9.38).
- [x] P2 — Per-project license metadata in the generated feed, schema, and report (completed v4.9.55 with project license fields, sync-report aggregates, schema support, and Pester coverage).
- [x] P2 — Fork-parent drift reporting for GitHub forks versus catalog continuations (completed v4.9.56 with `forkParentDrift` report classification and public-safe warnings).
- [x] P2 — Public repository enumeration completeness guard as the account approaches the `gh repo list` cap (completed v4.9.36).
- [x] P2 — Versioned sync-report JSON Schema with validation in Pester/`-Check` (duplicate row reconciled in v4.9.60; completed v4.9.45 with `schemas/profile-sync-report.v1.json`, report schema output, `-Check` validation, and malformed-report Pester coverage).
- [x] P2 — GitHub diff/language handling for fully generated feed, report, and profile SVG artifacts (completed v4.9.37 via `.gitattributes`).
- [x] P2 — Repository release/tag consistency reported beside planning-doc version checks (completed v4.9.57 with `profileReleaseConsistency` warning-only reporting for latest release `v3.0.0` versus planning version `v4.9.57` and the missing `v4.9.57` tag ref).
- [x] P2 — Userscript install trust reporting for raw branch-hosted `.user.js` actions (completed v4.9.58 with metadata field, source-provenance, and warning-count reporting).
- [x] P2 — Live GitHub profile DOM/screenshot smoke proof for generated README changes (duplicate row reconciled in v4.9.60; completed v4.9.27 with the rendered smoke script, profile-sync artifacts, and Pester wiring coverage).
