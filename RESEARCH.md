# Research: SysAdminDoc

Date: 2026-09-04. Replaces all prior research.

Confidence labels: **Verified** means reproduced in the current tree or confirmed against a primary source. **Likely** is an evidence-backed inference. **Needs live validation** marks a decision this repository cannot answer alone.

## Executive Summary

SysAdminDoc is a single-owner, PowerShell-generated GitHub profile README and public software-catalog feed. The working tree records 222 public repositories, 228 canonical catalog rows, 198 feed projects, 30 redacted suppressions, and 185 README projects (`reports/profile-sync-report.json`, `data/profile-catalog.json`, `projects.json`). Since the 2026-08-23 pass it shipped the three items that mattered most: a single safe-outbound HTTP policy, recoverable staged artifact publication, and a fail-closed offline write guard. The generator is now 14,408 lines and 317 functions with a 7,293-line, 330-`It` Pester suite.

The product is in good shape. The problem is its evidence. This repository's entire value proposition is that its 56-section report tells the truth about the catalog, and this pass found that several of those sections cannot report a problem. The highest-value direction is no longer adding gates. It is proving the existing ones can fail, and deleting the ones that cannot.

Highest-value opportunities, in priority order:

1. **Verified, P0:** `projectsExportInSync` passes on any feed content drift that `Test-MetadataDrift` does not explicitly model. Seven planted mutations (project `id`, `canonicalRepo`, `aliases`, `licenseSpdxId`, `localeHints`, and both `schemaPolicy` fields) were all reported in sync (`scripts/sync-profile.ps1:13755`).
2. **Verified, P1:** `scripts/validate-local.ps1`, the documented pre-push gate, never invokes `sync-profile.ps1 -Check`. None of the 22 blocking conditions run in the local validation lane.
3. **Verified, P1:** Rendered-smoke evidence has no age check. The committed evidence is dated 2026-08-20 against a 2026-09-03 README and reports `smokeEvidenceStale: false`, `warningCount: 0` (`scripts/sync-profile.ps1:8256`).
4. **Verified, P1:** No failure condition has a test proving it can fire against a realistic input. The two `projects sync gate` tests cover a total-garbage payload and an info-only drift, and miss the entire gap between them (`tests/sync-profile.Tests.ps1:5812`).
5. **Verified, P1:** The release-trust shortlist tells the maintainer to `publish-build-provenance-attestation` on all 91 executable downloads. Attestation generation requires a GitHub Actions OIDC token, which repository policy forbids, so the report's top recommended action is unreachable by construction.
6. **Verified, P1:** A new public repository fails the weekly check until a catalog row is hand-authored. That is what broke the check from 2026-08-31 to 2026-09-03 (`CHANGELOG.md`, entry 2026-09-03).
7. **Verified, P2:** Twelve profile SVGs (106,118 bytes, of which 59,968 are the two contribution heatmaps) are generated, committed, contrast-checked, budget-counted and drift-checked. `README.md` contains zero `<img>` tags and zero references to `assets/profile`. `Get-ContributionCalendar` makes a GraphQL call every run to feed them.
8. **Verified, P2:** Local validation runs `npm audit` but not `npm audit signatures`, and there is no `.npmrc`. Registry signature and provenance verification works with no CI.
9. **Verified, P2:** OpenSSF Scorecard v5.5.0 is a standalone binary that runs locally against the public API. The repo currently only reads a hosted score and greps for a workflow that policy guarantees will never exist.
10. **Likely, P2:** The consultant-profile pattern that actually differentiates for-hire profiles is quantified client outcomes plus a contact-first CTA. The hand-authored header has the CTA and no numbers.

## Product Map

### Core workflows

- **Verified:** `data/profile-catalog.json` (228 entries) is the editorial source. `scripts/sync-profile.ps1` reconciles it with live GitHub metadata and generates `README.md`, `projects.json`, 12 SVG assets, and an optional Backstage export.
- **Verified:** `sync-profile.ps1 -Check` assembles 56 report sections into `reports/profile-sync-report.json`, of which 22 are blocking failure conditions (`scripts/sync-profile.ps1:14132`).
- **Verified:** Artifacts are staged beside their targets, journalled with old and new SHA-256, atomically replaced, and repaired on restart (`New-ArtifactPublicationTransaction`, `Repair-ArtifactPublicationTransactions`).
- **Verified:** Every outbound fetch routes through `Invoke-SafeOutboundHttpRequest`: HTTPS-only, no embedded credentials, all A/AAAA records validated, no automatic redirects, at most 5 validated hops, sockets pinned to the validated address.
- **Verified:** The only unattended caller is the Windows scheduled task `SysAdminDoc Profile Freshness Check`, weekly Monday 09:15, running `sync-profile.ps1 -Check -GraphQlPageSize 300`. It passes no other switch.

### User personas

- **Verified:** The owner-maintainer curates one public profile and its privacy boundary. Not a multi-tenant product (`AGENTS.md`).
- **Verified:** Profile visitors need fast routes to downloads, source, setup, and services (`README.md`).
- **Verified:** The separate portfolio repo consumes `projects.json` as a stable, public-safe feed (`schemas/profile-projects.v1.json`, `portfolioCompatibility`).

### Platforms and distribution

- **Verified:** Public surface is GitHub-rendered Markdown plus a JSON feed. GitHub truncates a README beyond 500 KiB ([docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)); the repo's own 98,304-byte soft limit is far stricter, and the README is 77,777 bytes.
- **Verified:** Generation targets PowerShell 7.4+ on Windows (`runtimeSecurity` floors: min 7.4.0, secure patches 7.4.19 / 7.5.10 / 7.6.5 for CVE-2026-50523). `setup.ps1` is the 5.1 bootstrap.
- **Verified:** Rendered smoke drives headless Chrome over raw CDP across 4 viewport and theme combinations.

### Key integrations and data flows

- **Verified:** `gh` CLI supplies GraphQL repository and contribution data plus REST release, settings, topic and governance data, pinned to `X-GitHub-Api-Version: 2022-11-28`. Only `2022-11-28` and `2026-03-10` are supported today; `2022-11-28` is guaranteed into March 2028 ([API versions](https://docs.github.com/en/rest/about-the-rest-api/api-versions)).
- **Verified:** Release metadata always arrives by REST fallback (`restFallbackReleaseFetch.used: true`, 222 attempted, 166 successful, 56 absent) even when the primary provider is GraphQL.
- **Verified:** npm supplies markdownlint; PowerShell Gallery supplies Pester 5.9.1 and PSScriptAnalyzer 1.25.0; PyPI hash-pins zizmor 1.29.0.

## Competitive Landscape

Re-verified 2026-09-04. Nothing in the prior rejection set has been archived or deprecated, so those rejections stand.

- [github-readme-stats](https://github.com/anuraghazra/github-readme-stats) (79,845 stars, 168 open issues) remains the dominant stats-card tool and remains the dominant failure mode. [Community discussion #190905](https://github.com/orgs/community/discussions/190905) root-caused a 2026-03 outage to the public Vercel instance being paused; [issue #4658](https://github.com/anuraghazra/github-readme-stats/issues/4658) is maintainer-labelled a top bug. Committed first-party SVGs remain correct. Avoid re-adding any render host.
- [lowlighter/metrics](https://github.com/lowlighter/metrics) (17,153 stars) still pushes commits but its last release is v3.34 from 2023-09-13. Borrow only the strict split between data collection and renderers; avoid the plugin surface.
- [maurodesouza/profile-readme-generator](https://github.com/maurodesouza/profile-readme-generator) is the healthiest generator (4,496 stars, pushed 2026-09-03, 9 open issues). It solves broad-user composition, which this repo does not need.
- [backstage/backstage](https://github.com/backstage/backstage) v1.54.6 remains the reference data model for entity identity, relations and provenance. Borrow the descriptor patterns; avoid the runtime.
- [hecat](https://github.com/nodiscc/hecat) is the real answer to "how do awesome-lists validate data". Both [awesome-selfhosted-data](https://github.com/awesome-selfhosted/awesome-selfhosted-data) and [awesome-sysadmin-data](https://github.com/awesome-foss/awesome-sysadmin-data) pin `hecat@1.6.0` and run `url_check` plus `awesome_lint` nightly. Steal its staleness thresholds: `last_updated_warn_days: 186`, `last_updated_error_days: 365`, with a hand-curated `last_updated_skip` allowlist. This repo uses 365 / 540 / 730 and consequently reports 0 stale projects out of 198. Avoid its regex host exclude-list approach; a curated allowlist of stable exceptions is cleaner.
- [lychee](https://github.com/lycheeverse/lychee) v0.24.2 is the strongest link checker: `--cache` with `--max-cache-age`, `--cache-exclude-status` for per-status caching, `--exclude-all-private` / `--exclude-link-local` / `--exclude-loopback`, `--host-concurrency` (default 10), `--host-request-interval` (default 50ms), `--max-retries` 3. Steal the per-status cache policy and per-host throttling numbers. Notably, **no tool in this class does ETag conditional revalidation** (checked against lychee, [muffet](https://github.com/raviqqe/muffet) v2.11.5, [linkinator](https://github.com/JustinBeckwith/linkinator) v8.1.0, [htmltest](https://github.com/wjdp/htmltest) v0.17.0 which is effectively unmaintained since 2022). The existing conditional-revalidation roadmap item is correct per RFC 9111 but ahead of the field; the per-status TTL half is the part with proven precedent.
- [OpenSSF Scorecard](https://github.com/ossf/scorecard) v5.5.0 runs as a local Go binary against the public API with a `public_repo` token. Every check except Branch-Protection works unauthenticated. This is a local gate, not a workflow, and fits the no-Actions policy.
- **The closest precedent to this exact design is dead.** [nsacyber/CodeGov](https://github.com/nsacyber/CodeGov) was a PowerShell module that walked an org's repos and emitted a schema-validated `code.json` inventory. Same language, same own-repos scope, same schema-validation discipline. Archived, last pushed 2019-01-16, nobody picked it up. [GuilhermeBalog/portfolio-generator](https://github.com/GuilhermeBalog/portfolio-generator) is the most literally-named match and has been stale since 2023. The niche has a history of abandonment, which is an argument for keeping this repo small and boring rather than for expanding it.
- **[simonw/simonw](https://github.com/simonw/simonw) is the closest live analogue.** A bio plus a "Recent releases" table regenerated hourly by a script that scans the owner's own repos and commits the diff back under a bot identity. Same script-driven, self-committing model; the difference is only that it uses a hosted cron and this repo uses a weekly Windows scheduled task. Steal the discipline of a generated section that is never hand-edited, which this repo already has.
- **Other live self-catalog tools worth reading.** [dogsheep/github-to-sqlite](https://github.com/dogsheep/github-to-sqlite) (471 stars, 2026-07-14) is one-row-per-repo with one command per entity type; a flat JSON is simpler to diff in git than its SQLite, so borrow the entity split, not the store. [octoherd/cli](https://github.com/octoherd/cli) (101 stars, 2026-09-02) is the bulk-iteration primitive for "every repo I can push to". [queelius/repoindex](https://github.com/queelius/repoindex) uses a normalized core (`stars`, `topics`, `is_archived`) with namespaced enrichment (`pypi_version`, `citation_doi`) and treats the thing you own as canonical identity with forges as enrichment, which is exactly this repo's alias model. [DSACMS/automated-codejson-generator](https://github.com/DSACMS/automated-codejson-generator) leaves unobservable fields blank and logged rather than guessing. [mikaelvesavuori/catalogist](https://github.com/mikaelvesavuori/catalogist) caps every array at 20 items and the payload at 20,000 characters to stop a catalog schema becoming a dumping ground. [italia/publiccode-crawler](https://github.com/italia/publiccode-crawler) treats a missing descriptor as a soft fail rather than an error, which is the opposite of this repo's fail-closed cataloging and worth weighing against it. Also archived or stale: `todogroup/repolinter` (archived 2026-02-06), `project-open-data/catalog-generator`, `wbkd/awesomer`. None of them ships privacy suppression, stable IDs and release trust together.
- **Catalog field vocabularies worth borrowing, if a consumer ever asks.** Cheap and plain-typed: `purl` from [CycloneDX 1.7](https://cyclonedx.org/docs/1.7/json/) (`pkg:github/owner/repo` is a free cross-ecosystem identity string), `spec.lifecycle` enum values from Backstage (`experimental`/`production`/`deprecated`) and its `spec.subcomponentOf` / `spec.system` for product families, `downloadLocation`/`homePage`/`supportLevel` from [SPDX 3.0.1 Package](https://spdx.github.io/spdx-spec/v3.0.1/model/Software/Classes/Package/), and `repository.status` plus `repository.license.expression` from [OpenSSF Security Insights](https://github.com/ossf/security-insights) v2.2.0, whose v2 layout splits into `header` / `project` / `repository` sections. Code.gov's `permissions.usageType` exemption codes are the nearest published precedent for this repo's suppression-reason vocabulary. The single best idea found is structural rather than a field: [RFC 9116](https://www.rfc-editor.org/info/rfc9116/) makes `Expires` mandatory in `security.txt` so staleness is machine-checkable by construction, and `Expires` compliance among adopters rose from 1.78% in 2021 to 88.6% in 2026 because the spec made it non-optional. A per-entry review-by date would do the same for this catalog and would fix thresholds that currently cannot fire.
- **[CHAOSS](https://chaoss.community/kb/) metrics, 2026 caveat:** activity-count and responsiveness metrics are now unreliable because AI-authored commits, PRs and issues are indistinguishable from human ones in the event stream ([2026 assessment](https://nesbitt.io/2026/05/27/chaoss-metrics-in-2026.html)). Test Coverage and dependency freshness survive because they measure the artifact directly. Bus Factor is meaningless at one owner.
- **Profile design, corrected:** the 2026 "anti-badge minimalism has won" narrative does not survive direct inspection. [sindresorhus](https://github.com/sindresorhus) is deliberately maximalist and GIF-heavy; [anuraghazra](https://github.com/anuraghazra) still runs two of his own stats cards; [addyosmani](https://github.com/addyosmani) still carries the uncleaned emoji-bullet wizard boilerplate. [kentcdodds](https://github.com/kentcdodds) and [tiangolo](https://github.com/tiangolo) are genuinely minimal, and both [gaearon](https://github.com/gaearon) and [torvalds](https://github.com/torvalds) publish an empty profile README. The distribution is bimodal, not directional: near-empty prose, or a live generated data feed with no decoration, and almost never a stats-card wall at the top of the credibility ladder. What *does* separate for-hire from hobbyist profiles is concrete: a role or service positioning line, a contact-first link row, quantified client and project counts, and skills grouped as service categories rather than a language badge wall ([prashant-software-developer](https://github.com/prashant-software-developer), [RupeshDev18](https://github.com/RupeshDev18)). This repo's header has the positioning line and the single CTA and no numbers.

## Reported Issues

The tracker carries no signal at all. Verified 2026-09-04 via `gh`: **zero open issues, zero closed issues, zero open pull requests, zero discussions.** Issues and Discussions are both enabled and four issue forms exist (`broken-link.yml`, `local-validation.yml`, `profile-correction.yml`, `config.yml`); none has ever been used. Historical PRs #1 through #23 are all closed June 2026 automation drills for workflows that were deleted on 2026-06-26.

Consequences for prioritization:

- Every roadmap item in this repository is self-generated from audits. There are no user repros to outrank them, so audit rigour is the only quality control, which is exactly why the gate-integrity findings below sit at the top.
- Five historical OpenSSF Scorecard code-scanning alerts remain open ([1](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/1), [3](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/3), [4](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/4), [5](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/5), [6](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/6)). They came from removed hosted workflows and are not current code defects.

## Security, Privacy, and Reliability

- **Verified, P0 — the feed sync gate cannot fail on unmodelled drift.** `scripts/sync-profile.ps1:13755` reads `$projectsInSync = $projectsComparableInSync -or ([int]$metadataDriftResult.fatalCount -eq 0)`. `ConvertTo-ProjectsSyncComparableJson` masks exactly four volatile fields and is the correct comparison; the `-or` clause overrides it whenever `Test-MetadataDrift` finds nothing fatal, and that function only inspects a fixed field list. Reproduced by dot-sourcing the generator and mutating the live feed: changes to `projects[0].id`, `canonicalRepo`, `aliases`, `licenseSpdxId`, `localeHints`, `schemaPolicy.currentVersion` and `schemaPolicy.supportedVersions` each produced `comparableInSync=False, fatalCount=0, projectsExportInSync=True`. Controls (`description`, `repoUrl`) correctly produced `fatalCount=1` and a failure. The committed report already shows the symptom: `artifactDriftDiagnostics.projects.currentSha256` is `9f824f1e…` against `expectedSha256` `66fd45d7…` with `inSync: true`. `id` is the stable-entity contract downstream consumers key on.
- **Verified, P1 — the documented local gate skips every catalog check.** `scripts/validate-local.ps1:404-470` runs `npm ci`, `npm run lint:markdown`, `Assert-ScriptAnalyzerClean`, `Invoke-DependencyReview` and Pester with coverage. It never calls `sync-profile.ps1`. `README.md` presents it as the thing to run "before pushing profile, catalog, asset, or validation changes". A catalog edit that leaks a suppressed repo, breaks a link, or desyncs README from feed passes it cleanly. No Pester test reads the committed `README.md` or `projects.json`; every sync assertion runs on `tests/fixtures/catalog.json`.
- **Verified, P1 — smoke evidence has no age.** `Test-ReportEvidenceFreshness` (`scripts/sync-profile.ps1:8256`) sets `smokeEvidenceStale` only when `smokeStatus -eq "not-run"` **and** the source string is blank. The evidence's own `generatedAt` is never compared to anything. `renderedProfileSmoke.generatedAt` is 2026-08-20T13:20:52 against a README regenerated 2026-09-03, and the section reports `status: "generated-with-commit"`, `smokeEvidenceStale: false`, `warningCount: 0`. Because `-Check` re-reads the stale local artifact and restamps the report, the wrapper always looks fresh. This is a freshness check on fetch age rather than content age.
- **Verified, P1 — no gate has a reachability test.** The suite has 330 `It` blocks and none plants a realistic violation to prove a failure condition fires. `Describe 'Test-ProfileState projects sync gate'` (`tests/sync-profile.Tests.ps1:5812`) proves the gate fails on `'{"stale":true}'` and passes on provenance-only info drift. The entire space between those two poles is untested, which is where the P0 above lives. Mutation testing formalises this: a surviving mutant proves an assertion gap ([Stryker](https://stryker-mutator.io/docs/), [Jia & Harman 2011](http://www0.cs.ucl.ac.uk/staff/M.Harman/tse-mutation-survey.pdf)). There is no standard name for the config-gate equivalent, but the practice is the same.
- **Verified, P1 — the report's headline remediation is impossible.** `releaseAssetDrift.executableDownloadTrustShortlist` sets `nextAction: publish-build-provenance-attestation` on every one of 91 executable downloads (`attestationGapCount: 91`). All attestation generation paths require a GitHub Actions OIDC token ([actions/attest](https://github.com/actions/attest)); `gh attestation verify` is verification only, and no CLI or local generation path exists as of 2026-09-04. Under `AGENTS.md` policy this tier is permanently unreachable. The achievable action is SHA-256 sidecars: 75 of 91 executable downloads have none, while 119 of 152 release rows already carry free platform digests.
- **Verified, P1 — fail-closed cataloging with hand-authored remediation.** `missingPublic` is a blocking condition, so one new public repository stops the weekly check until a full catalog row is written by hand. `CHANGELOG.md` records exactly that from 2026-08-31 to 2026-09-03 for five repos. The gate is right; the remediation cost is what turns it into an outage.
- **Verified, P2 — schema validation has the worst diagnostics of any blocking gate.** `Test-JsonSchemaContract` (`scripts/sync-profile.ps1:11063`) uses `Test-Json -SchemaFile`, which since PowerShell 7.4 returns only a boolean and a generic exception message, with no instance path or failing keyword ([Test-Json docs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/test-json?view=powershell-7.6)). `schemas/profile-sync-report.v1.json` is 7,467 lines with 56 required keys. `schemaValidation` is a blocking condition, so the highest-consequence gate gives the least actionable output. JsonSchema.NET, the library already backing `Test-Json`, exposes `EvaluationResults` with `Detailed`/`Verbose` output formats.
- **Verified, P2 — no npm supply-chain hardening.** There is no `.npmrc`. `scripts/review-local-dependencies.ps1` runs `npm audit --json` but never `npm audit signatures`, which verifies registry ECDSA signatures and provenance attestations locally with no CI ([npm docs](https://docs.npmjs.com/cli/audit/)). npm 12 defaults lifecycle scripts off, but this machine runs npm 11.17.0, and `min-release-age` is opt-in in every npm version. The Shai-Hulud family moved to `preinstall`, which runs even when the install fails ([Microsoft](https://www.microsoft.com/en-us/security/blog/2025/12/09/shai-hulud-2-0-guidance-for-detecting-investigating-and-defending-against-the-supply-chain-attack/)).
- **Verified strength, do not weaken:** current evidence reports zero public privacy leaks, zero missing public repositories, zero unsafe URL schemes, zero link failures and zero orphaned suppressions. The safe-outbound policy and the staged publication transaction are correctly built. Branch protection on `main` is live with `enforce_admins: true` and force-push and deletion blocked.
- **Correction to an existing roadmap item:** the P1 Gallery-integrity item asserts Pester is unsigned. Pester Gallery packages **are** Authenticode-signed, issuer `CN=Jakub Jareš, O=Jakub Jareš, L=Praha, C=CZ`, for every version except 3.4.0 ([pester#2617](https://github.com/pester/Pester/issues/2617)). The certificate root rolled at 5.6.0, which is the origin of the `-SkipPublisherCheck` folklore. That item should require the expected signer rather than allow an unsigned package by reviewed hash. PSResourceGet 1.2.0 ships with PowerShell 7.6 and `Save-PSResource -AuthenticodeCheck` is the supported mechanism.

## Architecture Assessment

- **Verified:** `scripts/sync-profile.ps1` is 14,408 lines and 317 functions; the suite is 7,293 lines, 67 `Describe`, 330 `It`. Coverage instruments **only** `sync-profile.ps1` (81.0% line, 24 functions at zero). `render-profile-smoke.ps1`, `validate-local.ps1`, `review-local-dependencies.ps1`, `write-profile-sync-summary.ps1`, `new-support-bundle.ps1` and `setup.ps1` have no line coverage at all. `coverage.xml` is dated 2026-08-23 and still names a function deleted since; it should not be cited as current.
- **Verified:** Splitting into a module is the standard remedy and buys real checks, not just tidiness. A whole class of PSScriptAnalyzer rules (`MissingModuleManifestField` and the manifest family) only fires against `.psd1` and is inert against a monolithic `.ps1`. Pester's documented mechanism for testing non-exported internals is `InModuleScope` ([Pester modules](https://pester.dev/docs/usage/modules)). The credible path is a `Private/`/`Public/` split behind a thin loader with an explicit `FunctionsToExport`, migrating tests area by area.
- **Verified:** 12 SVGs (106,118 bytes) are generated, committed, contrast-checked (`profileAssetsAccessibility`, warning-only), budget-counted and drift-checked. `README.md` has zero `<img>` tags and zero `assets/profile` references, and `tests/sync-profile.Tests.ps1:2951-2967` asserts their absence. `Roadmap_Blocked.md` says the minimal README "references only the footer pair"; that is wrong, nothing is referenced. `contributions-{dark,light}.svg` are 59,968 of those bytes, permanently drift against the committed copies (`profileAssetChecks[].inSync: false` on both), are excluded from the fatal gate, and are the sole consumer of the per-run `Get-ContributionCalendar` GraphQL call, which the offline snapshot guard also requires to be non-empty.
- **Verified:** Several sections are structurally dead. `scheduledWorkflowFreshness` reports `status: "not-applicable"`, 0 workflows, 0 rows: `Get-ScheduledWorkflowDefinitions` reads `.github/workflows`, which policy guarantees stays empty. `codeScanningLocalEvidence` greps workflow text for `ossf/scorecard-action@`, permanently false. `.github/zizmor.yml` configures a workflow scanner for a repo with no workflows. `Get-GeneratedPrWriteEvidence` and `Get-GeneratedPrDryRunEvidence` are self-described stubs (`scripts/sync-profile.ps1:14069`, `:14075`) kept only so the summary writer does not null-deref. These sit in the 0-30% coverage band and inflate the report.
- **Verified:** 34 of 56 report sections are advisory and can never fail a run (`scripts/sync-profile.ps1:14132`). Some of those carry real integrity signal: `userscriptInstallTrust` (5 warnings, one missing `@updateURL`, one missing `@downloadURL`, 3 broad-scope), `profileReleaseConsistency`, and `artifactBudgets`, which has warned that the report is over its soft limit continuously since at least 2026-08-20. The report is now 126,706 bytes against a 114,688 limit, up from 122,065 on 2026-08-23; the existing reduction item is still open and the gap is widening.
- **Verified:** `releaseArtifactVerification` is opt-in behind `-VerifyReleaseArtifacts`, and the only unattended caller does not pass it. Across 213 targets it has verified 0 assets and downloaded 0 bytes. Its failure condition is guarded by the same switch, so it can never fail unattended.
- **Verified:** The link check reports 365 targets, 0 failures, 9,107 ms. `validationPerformance.cache.links` shows `hitCount: 365, missCount: 0, writeCount: 0` for that run: every result was cache-replayed and nothing was probed live. `linkValidationSummary` does not distinguish live from cached, so a green link check can be entirely stale within the flat 24-hour TTL. This is fresh evidence for the existing status-aware-cache item plus a distinct reporting gap.
- **Verified:** The README experience contract encodes marketing copy, not structure. `Test-ReadmeExperience` requires the literal string `Broadcast IT, Healthcare IT, and practical public tools.` in two places (`scripts/sync-profile.ps1:7261`, `:7288`) and `scripts/render-profile-smoke.ps1:217` detects the header by the same sentence. `readmeExperience` is a blocking condition, so rewriting one tagline is a three-file code change. The positioning has already moved twice, and the pinned tagline now sits directly above an `## AI Implementation Services` section it no longer describes.
- **Verified:** `imageAltTextComplete` inspects an empty set. With `imageTagCount: 0` the loop never executes, `imageAltTextIssueCount` is 0 by construction, and the value is not part of `$passed` anyway. `themeAwareImageChrome` requires `#gh-dark-mode-only` / `#gh-light-mode-only` fragments, which are superseded by `<picture>` with `prefers-color-scheme` and should not be reintroduced if rich chrome ever returns.
- **Verified:** `AGENTS.md` states that `README.md` is "the ONLY .md tracked in git; all others are gitignored". That is false. `git ls-files -v` reports `CHANGELOG.md`, `RESEARCH.md` and `ROADMAP.md` as tracked with normal status, and `git check-ignore` matches none of them. The `.gitignore` `*.md` rule was added after those files were already tracked, and gitignore has no effect on tracked files. Only `CLAUDE.md` is genuinely untracked. The practical consequence is that this research pass and every roadmap edit are public repository content, which is the opposite of what the hygiene rule claims and worth deciding deliberately rather than by accident.
- **Verified:** `Test-SchemaKeywordCoverage` recurses only into `properties`, `items` and root `$defs`. Composition keywords and `additionalProperties` subschemas are not walked. The three current schemas use only `$defs` and `additionalProperties`, so this is latent rather than live.
- **Verified dependency state, 2026-09-04:** no pin carries an unpatched advisory. Exactly current: Pester 5.9.1, Pester 6.1.0, PSScriptAnalyzer 1.25.0, markdownlint-cli2 0.23.2, pip-audit 2.10.0. Behind but safe: markdown-it 14.3.0 against [15.0.1](https://github.com/markdown-it/markdown-it/blob/HEAD/docs/migration/migration_v15.md) (2026-08-27, breaking ESM rewrite, so the hold is justified), js-yaml 5.2.2 against 5.4.1 (2026-08-26; CVE-2026-59868 was fixed in 5.2.0), zizmor 1.29.0 against 1.30.0 (2026-08-30; GHSA-f42p-wjw5-97qh only ever affected 1.27.0). All three releases postdate `PinLatestCheckedAt = "2026-08-20"`, which is live proof for the existing registry-evidence item.
- **Verified platform deltas since 2026-08-23:** `gh` moved 2.97.0 to 2.100.0 (this machine is current); rulesets gained push-rule path exceptions and a GA rule-insights dashboard (2026-08-25) but classic `/branches/{branch}/protection` carries no deprecation notice; rulesets are available on public repos under Free; a privacy-safe star-history REST endpoint shipped 2026-09-04. Immutable releases, the release-asset `digest` field, README rendering and rate limits are unchanged. `releaseImmutability` reports 17 immutable of 152: enablement applies to releases published after the toggle, so the 2026-08-20 change did not retroactively convert existing releases.

## Rejected Ideas

- **JSON-LD structured data in the README or feed.** GitHub strips `<script>` from rendered Markdown, so a `type="application/ld+json"` block cannot survive. Google's "Software app" rich result requires `offers` and `aggregateRating`/`review` ([search gallery](https://developers.google.com/search/docs/appearance/structured-data/search-gallery)), which a dev-tool catalog has none of, and `SoftwareSourceCode` is not a supported rich-result type. A raw JSON file is not an indexable page. Zero payoff on GitHub-hosted content.
- **llms.txt.** Ahrefs analysed 137,210 domains: 28% publish a valid llms.txt and **97% of those received zero requests** in May 2026, with the traffic that did arrive 96% generic bot noise ([study](https://ahrefs.com/blog/llmstxt-study/)). Adoption grew roughly 8.8x year over year while readership did not, no major vendor has committed to consuming it in production, and Google said in July 2025 it has no plans to support it. Removing it as a feature *improved* a citation-prediction model ([analysis](https://mecanik.dev/en/posts/does-llms-txt-do-anything-yet/)). The only real consumer is a coding agent a human explicitly points at a URL, which `projects.json` already serves.
- **Hosted stats, streak, trophy and visitor cards.** Re-verified: [community discussion #190905](https://github.com/orgs/community/discussions/190905) and [github-readme-stats#4658](https://github.com/anuraghazra/github-readme-stats/issues/4658) show the same outage class recurring through 2026. Committed first-party assets stay.
- **GitHub Actions of any kind, and therefore build-provenance attestations.** Forbidden by `AGENTS.md`, and confirmed that no non-Actions attestation-generation path exists.
- **Replacing the PowerShell link checker with lychee outright.** The catalog-specific logic (release existence, userscript metadata trust, suppression rules, branch-tip provenance) has to live beside the rest of the pipeline, which is the same reason the awesome-lists wrote hecat rather than adopting a generic linter. Copy lychee's cache and throttling policy instead.
- **A visual README wizard, themes, drag-and-drop composition, or a portfolio rebuild here.** Unchanged from 2026-08-23; those solve broad-user onboarding and the separate portfolio repo owns presentation.
- **Profile analytics, tracking pixels, email capture, public submissions and ratings.** Weakens privacy, adds moderation, and the tracker shows zero demand.
- **Native mobile, multi-user, plugin marketplace, GitLab or Codeberg ingestion.** The identity, release model, privacy boundary and owner workflow are intentionally GitHub-specific.
- **Immediate markdown-it 15 adoption.** v15 is an ESM rewrite that drops `dist/`, externalises Punycode and disables fuzzy linkify by default. 14.3.0 carries no live advisory. Fix the freshness *evidence* first, then evaluate.
- **Internationalised profile copy.** The feed already carries `localeHints` and `scriptHints` and preserves Unicode, but the product is one owner's English profile with no consumer requesting locale variants. Culture-independent ordering is still worth testing and stays on the roadmap.
- **WCAG 3.0 conformance targets.** The March 2026 Working Draft renamed outcomes to requirements and reworked conformance to Bronze/Silver/Gold; Candidate Recommendation is not expected before Q4 2027 and Recommendation no earlier than 2028 ([W3C](https://www.w3.org/WAI/news/2026-03-03/wcag3)). WCAG 2.2 AA remains the bar.
- **Feed signing, Sigstore badges and SLSA build-track claims.** Unchanged: no verifier, no stable signing identity, and no hosted build platform.
- **`SECURITY-INSIGHTS.yml`, SPDX 3.0.1 and CycloneDX 1.7 conformance.** Modelled for multi-maintainer projects and dependency inventories; no consumer requires them from a personal catalog. Individual field names are worth borrowing (see Competitive Landscape); the specs are not worth adopting.
- **Port, Cortex, OpsLevel and CNCF Score data models.** The first three assume a paid backend and exist to route on-call and SLOs across many teams, which has no referent at one owner. Score describes a Kubernetes-style runtime workload, and this catalog has none.
- **repolinter as a community-health checker.** Archived read-only by the TODO Group on 2026-02-06 with no announced successor. The repo's own `communityHealth` section already covers the same ground.
- **CHAOSS activity and responsiveness metrics.** Structurally inapplicable at one owner, and compromised in 2026 by AI-authored events being indistinguishable from human ones in the underlying stream.
- **Retaining a history of report evidence for trend analysis.** Considered and excluded deliberately, not overlooked. Appending a per-run row would show whether checksum coverage or link health is improving, and the report already computes the numbers. But every run overwrites today, the weekly cadence gives 52 points a year, and no consumer exists for the series. Revisit only if the release-trust work in the roadmap creates a backlog worth burning down against a target. Meanwhile the per-entry review-by date does the useful half of this job at a fraction of the cost.

## Sources

### Project and tracker

- https://github.com/SysAdminDoc/SysAdminDoc
- https://github.com/orgs/community/discussions/190905
- https://github.com/anuraghazra/github-readme-stats/issues/4658

### GitHub platform

- https://docs.github.com/en/rest/about-the-rest-api/api-versions
- https://docs.github.com/rest/about-the-rest-api/breaking-changes?apiVersion=2026-03-10
- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
- https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
- https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api
- https://github.blog/changelog/2026-08-11-automatically-migrate-branch-protection-rules-to-repository-rulesets/
- https://github.blog/changelog/2026-08-25-push-rules-in-rulesets-now-support-path-exceptions/
- https://github.blog/changelog/2026-09-04-new-api-endpoint-provides-privacy-safe-star-history-data/
- https://github.blog/changelog/2021-10-31-warning-about-bidirectional-unicode-text/
- https://github.com/actions/attest
- https://cli.github.com/manual/gh_attestation_verify

### Catalogs, link checking and awesome-list tooling

- https://github.com/nodiscc/hecat
- https://github.com/awesome-selfhosted/awesome-selfhosted-data
- https://github.com/awesome-foss/awesome-sysadmin-data
- https://github.com/lycheeverse/lychee
- https://github.com/raviqqe/muffet
- https://github.com/JustinBeckwith/linkinator
- https://github.com/wjdp/htmltest
- https://github.com/ossf/scorecard
- https://backstage.io/docs/next/features/software-catalog/descriptor-format/

### Standards and specifications

- https://www.rfc-editor.org/rfc/rfc9111.html
- https://www.rfc-editor.org/rfc/rfc9110#section-15.1
- https://www.rfc-editor.org/info/rfc8785/
- https://reproducible-builds.org/specs/source-date-epoch/
- https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html
- https://www.unicode.org/reports/tr39/
- https://trojansource.codes/
- https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html
- https://www.w3.org/WAI/WCAG21/Understanding/name-role-value.html
- https://www.w3.org/TR/UNDERSTANDING-WCAG20/navigation-mechanisms-refs.html
- https://www.w3.org/WAI/news/2026-03-03/wcag3
- https://json-schema.org/specification

### Toolchain and dependencies

- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/test-json?view=powershell-7.6
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/save-psresource
- https://learn.microsoft.com/en-us/dotnet/api/system.io.file.replace?view=net-10.0
- https://learn.microsoft.com/en-us/windows/win32/fileio/deprecation-of-txf
- https://learn.microsoft.com/en-us/dotnet/api/system.net.http.socketshttphandler.connectcallback?view=net-8.0
- https://learn.microsoft.com/en-us/dotnet/api/system.stringcomparer.ordinal?view=net-6.0
- https://github.com/PowerShell/PowerShell/releases/tag/v7.6.5
- https://nvd.nist.gov/vuln/detail/CVE-2026-50523
- https://github.com/pester/Pester/issues/2617
- https://pester.dev/docs/migrations/v5-to-v6
- https://pester.dev/docs/usage/modules
- https://github.com/markdown-it/markdown-it/blob/HEAD/docs/migration/migration_v15.md
- https://cve.report/CVE-2026-59868
- https://github.com/zizmorcore/zizmor/releases/tag/v1.30.0
- https://docs.npmjs.com/cli/audit/
- https://docs.npmjs.com/viewing-package-provenance/
- https://www.microsoft.com/en-us/security/blog/2025/12/09/shai-hulud-2-0-guidance-for-detecting-investigating-and-defending-against-the-supply-chain-attack/
- https://nodejs.org/en/blog/vulnerability/july-2026-security-releases

### Testing practice and profile design

- https://stryker-mutator.io/docs/
- http://www0.cs.ucl.ac.uk/staff/M.Harman/tse-mutation-survey.pdf
- https://github.com/PoshCode/PowerShellPracticeAndStyle
- https://mecanik.dev/en/posts/does-llms-txt-do-anything-yet/
- https://developers.google.com/search/docs/appearance/structured-data/search-gallery
- https://github.com/abhisheknaiidu/awesome-github-profile-readme

## Open Questions

- **Needs live validation:** should the profile display any generated chrome at all? Twelve SVGs are maintained for a rich mode that has not rendered since 2026-07-15. Either the README renders them through `<picture>` with `prefers-color-scheme`, or generation should be derived from what the README actually references. Both are implementable; which one is a positioning decision.
- **Needs live validation:** the hand-authored header claims "Broadcast IT, Healthcare IT" while the section beneath it sells AI implementation services. Which is the current positioning determines the copy, and the copy is currently pinned by three code assertions.
- **Needs live validation:** is `portfolio.getparkerai.com` the only consumer of `projects.json`? The existing release-artifact-export and project-relationship items are both gated on a named consumer recording a field contract, and no such record exists yet.
- **Needs live validation:** the repository `homepage` field is empty. Setting it to the portfolio origin is free and affects the repo page and search, but it is an owner-facing branding choice.
