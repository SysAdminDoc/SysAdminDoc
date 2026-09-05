# Roadmap

Actionable incomplete work only. Completed work belongs in `CHANGELOG.md`; external, account, governance, and plan-gated decisions belong in `Roadmap_Blocked.md`.

## Research-Driven Additions

### P1

- [ ] P1: Verify PowerShell Gallery package bytes and signer expectations before import
  Why: Exact module versions do not detect a changed same-version Gallery package, and the Pester package is unsigned.
  Evidence: `scripts/validate-local.ps1:93`, `scripts/validate-local.ps1:172`, [Save-PSResource](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/save-psresource?view=powershellget-3.x), [Pester 6.1.0 Gallery record](https://www.powershellgallery.com/packages/Pester/6.1.0), `RESEARCH.md` Security, Privacy, and Reliability.
  Touches: `scripts/validate-local.ps1`, `scripts/review-local-dependencies.ps1`, a version-controlled PowerShell module lock, module cache, `tests/sync-profile.Tests.ps1`.
  Acceptance: The lock records module, version, Gallery package URL, nupkg SHA-256, and expected signer evidence when present. Both default and Pester 6 lanes download as nupkg, verify the hash before extraction, require the expected Authenticode signer for signed packages, and allow unsigned Pester only by its reviewed hash. Fixtures prove changed same-version bytes and signer mismatch fail before import; a verified cached nupkg supports an explicit offline lane.
  Complexity: M
  Note (2026-09-04 research): the premise is wrong on one point. Pester Gallery packages ARE Authenticode-signed, issuer `CN=Jakub Jares, O=Jakub Jares, L=Praha, C=CZ`, for every version except 3.4.0 (https://github.com/pester/Pester/issues/2617; the cert root rolled at 5.6.0, which is where the `-SkipPublisherCheck` folklore comes from). Drop the unsigned-Pester carve-out and require the expected signer for Pester too. Also prefer `Save-PSResource -AuthenticodeCheck`: PSResourceGet 1.2.0 ships with PowerShell 7.6, so no bootstrap install is needed.

- [ ] P1: Validate every hand-authored profile link and local anchor
  Why: `Get-ReadmeHeaderLinkValidationTargets` recognizes three known URLs and images, so an arbitrary Markdown or HTML call to action can die without failing the full link check.
  Evidence: `scripts/sync-profile.ps1:2408`, `CHANGELOG.md:9`, `reports/profile-sync-report.json.linkValidationSummary`, `RESEARCH.md` Security, Privacy, and Reliability.
  Touches: `Get-ReadmeHeaderLinkValidationTargets`, generated-notice boundary parsing, anchor discovery, link report groups, `tests/sync-profile.Tests.ps1`.
  Acceptance: Parse every Markdown link, HTML `href`, image `src`, and `srcset` value before `$GeneratedCatalogNotice`; deduplicate normalized external targets; route HTTPS targets through the safe-outbound policy; and verify every local fragment exists in the complete generated README. A fixture with an unknown dead CTA fails, a missing local anchor fails without network access, and the current header produces a stable enumerated target set.
  Complexity: S

- [ ] P1: Use status-aware link caches and conditional revalidation
  Why: One 24-hour TTL currently preserves corrected 404s and transient timeouts, 429s, and 5xx responses for as long as successful checks while stored validators are never reused.
  Evidence: `scripts/sync-profile.ps1:4504`, `scripts/sync-profile.ps1:4605`, `Invoke-LinkProbeBatch`, [RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html), [GitHub REST best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api), `RESEARCH.md` Security, Privacy, and Reliability.
  Touches: Validation cache schema and state, `Test-HttpUrl`, `Invoke-LinkProbeBatch`, retry telemetry, report schema and summary, cache tests.
  Acceptance: Cache successful checks for 24 hours, 404/410 for one hour, and do not reuse timeout, 429, or 5xx results beyond the current run. Preserve stale ETag and Last-Modified values, send conditional headers, refresh only after 304 or a new response, honor `Retry-After` up to a 60-second local cap, and report a future retry time instead of sleeping longer. Tests freeze time and cover each status, 304, validator changes, and retry timing.
  Complexity: M

- [ ] P1: Report topic mutation capability truthfully
  Why: The report hard-codes `applyModeAvailable = false` although `-ApplyTopics` is implemented and the allowlist currently names 12 repositories.
  Evidence: `scripts/sync-profile.ps1:11112`, `scripts/sync-profile.ps1:13089`, `data/topic-allowlist.json`, `RESEARCH.md` Architecture Assessment.
  Touches: Metadata hygiene builder, `schemas/profile-sync-report.v1.json` if an allowlisted-count field is added, summary output, `tests/sync-profile.Tests.ps1`.
  Acceptance: With the current tree, the report states `applyModeAvailable = true`, `requiresExplicitAllowlist = true`, and `allowlistedRepositoryCount = 12`; a missing or invalid allowlist produces false plus an actionable reason. `-Check` never mutates topics, and tests prove the capability fields for present, empty, missing, and invalid allowlists.
  Complexity: S

- [ ] P1: Align Dependabot evidence with the local advisory-review policy
  Why: The report recommends keeping Dependabot disabled but still emits warnings and next actions that tell the maintainer to enable it.
  Evidence: `scripts/sync-profile.ps1:8340`, `scripts/sync-profile.ps1:9278`, `scripts/review-local-dependencies.ps1`, `AGENTS.md`, `RESEARCH.md` Architecture Assessment.
  Touches: `Get-DependabotSecurityPosture`, `Get-RepositoryCommunityBaseline`, report summary, repository-setting fixtures and tests.
  Acceptance: Dependabot disabled with a present, current, passing local dependency review produces no enablement warning and a `keep-dependabot-disabled-with-local-advisory-review` next action. Missing, stale, skipped, or failing local review produces one compensating-control warning. No generated text recommends creating Dependabot configuration.
  Complexity: S

- [ ] P1: Replace hand-maintained dependency freshness claims with registry evidence
  Why: `PinLatestCheckedAt` is green while curated transitive overrides already have newer registry releases that `npm outdated` does not report.
  Evidence: `scripts/review-local-dependencies.ps1:4`, `scripts/review-local-dependencies.ps1:13`, [markdown-it 15.0.0 registry metadata](https://registry.npmjs.org/markdown-it/15.0.0), [js-yaml 5.3.0 registry metadata](https://registry.npmjs.org/js-yaml/5.3.0), `RESEARCH.md` Architecture Assessment.
  Touches: `scripts/review-local-dependencies.ps1`, registry adapters and cache, dependency-review report shape, fixtures in `tests/sync-profile.Tests.ps1`, generated validation documentation.
  Acceptance: Online full review queries authoritative npm and PyPI metadata for direct pins, overrides, and audit tools and caches the response date. Each row separates `declaredByParent`, `currentCompatible`, `registryLatest`, `latestCheckedAt`, and compatibility status. New majors create review-needed evidence without forcing an upgrade; offline review reports cache age and becomes stale after 30 days. Fixtures report markdown-it 15.0.0 and js-yaml 5.3.0 while retaining 14.3.0 and 5.2.2 as compatible until regression tests approve changes.
  Complexity: M

### P2

- [ ] P2: Encode public text by output context and reject deceptive controls
  Why: Catalog and GitHub strings are interpolated into Markdown tables, links, HTML, and JSON without a shared context encoder or bidi-control policy.
  Evidence: `scripts/sync-profile.ps1:1421`, `scripts/sync-profile.ps1:3638`, `schemas/profile-catalog.v1.json`, [GitHub Flavored Markdown](https://github.github.com/gfm/), [Trojan Source](https://trojansource.codes/trojan-source.pdf), `RESEARCH.md` Security, Privacy, and Reliability.
  Touches: Catalog schema, Markdown table-cell and link-label encoders, HTML text encoder, one-line field validation, feed serialization tests.
  Acceptance: Central helpers correctly encode `|`, backslash, `](`, HTML metacharacters, and line breaks for their destination context. One-line public fields reject CR/LF, C0/C1 controls except permitted whitespace, unpaired surrogates, bidi override/isolate controls, and values over explicit schema limits. Fixtures preserve ordinary accented and non-Latin text and prove injected content cannot create a new row, link, or HTML element.
  Complexity: M

- [ ] P2: Synchronize local operating notes with live project state
  Why: Working notes still describe v4.9.161, old counts and tool pins, an empty topic allowlist, a removed hosted asset workflow, and branch protection as absent.
  Evidence: `CLAUDE.md:4`, `CLAUDE.md:19`, `CLAUDE.md:172`, `CLAUDE.md:191`, `Roadmap_Blocked.md`, `reports/profile-sync-report.json`, `RESEARCH.md` Architecture Assessment.
  Touches: `CLAUDE.md`, `Roadmap_Blocked.md`, any tests that assert working-note facts.
  Acceptance: Notes match the freshly regenerated report at implementation time, including v4.10.0 or the then-current version, public/catalog/feed/README/suppression counts, Pester 5.9.1 and 6.1.0, the current topic allowlist count, and the live branch-protection controls. No text claims a hosted asset-refresh workflow exists. A repository text scan finds none of the superseded values or claims listed in the evidence.
  Complexity: S

- [ ] P2: Reduce the sync report below 112 KiB without hiding failures
  Why: The current report is 122,065 bytes against a 114,688-byte soft limit, and dormant hosted-PR structures plus success-only detail consume avoidable space.
  Evidence: `reports/profile-sync-report.json.artifactSizeBudget`, `scripts/sync-profile.ps1:8686`, `scripts/sync-profile.ps1:12883`, `scripts/write-profile-sync-summary.ps1`, `RESEARCH.md` Architecture Assessment.
  Touches: Report builders, `schemas/profile-sync-report.v1.json`, summary writer, size-budget and schema-migration tests.
  Acceptance: Delete retired hosted generated-PR and review-delivery fields and handling; aggregate success-only userscript, branch-tip, repository-setting, and release rows while retaining every warning and failure row with its current diagnostic fields. The regenerated pretty-printed report is at most 114,688 bytes, schema validation passes, summary output remains below 65,536 bytes, and tests compare warning/failure row identities before and after compaction.
  Complexity: M

- [ ] P2: Add an opt-in normalized release-artifact export
  Why: Current aggregate release trust discards exact tagged asset URLs, content types, sizes, and per-asset digests that owned portfolio and store consumers can use without scraping release pages.
  Evidence: `New-ReleaseTrustSummary` and `New-ProjectsExportJson` in `scripts/sync-profile.ps1`, [GitHub release API](https://docs.github.com/en/rest/releases/releases?apiVersion=latest), `RESEARCH.md` Competitive Landscape and Architecture Assessment.
  Touches: `Add-ReleaseAssetMetadata`, a `-ProjectArtifactsExportPath` option, `New-ProjectArtifactsExport`, a versioned JSON schema, public-suppression rules, fixtures and downstream compatibility tests.
  Acceptance: Before implementation, record one owned consumer and its required contract. The opt-in export contains stable project ID, release tag and URL, and deterministically sorted uploaded assets with exact `browser_download_url`, name, kind, content type, size, GitHub digest, nullable platform, nullable architecture, and role (`installable`, `checksum`, `signature`, `sbom`, or `attestation`). Exclude drafts, suppressed projects, and volatile download counts; never infer platform or architecture at low confidence. Fixtures cover APK, CRX/ZIP, EXE/MSI, wheel, multi-architecture, no-digest, and source-only releases. Default artifacts remain byte-identical when the option is absent.
  Complexity: M

- [ ] P2: Add public-safe relationships between catalog projects
  Why: Product families are currently inferred from names, while software catalogs use explicit relations for companion, extension, suite, and replacement navigation.
  Evidence: `data/profile-catalog.json`, stable IDs and aliases in `schemas/profile-projects.v1.json`, [Backstage descriptor relations](https://backstage.io/docs/next/features/software-catalog/descriptor-format/), [Awesome Selfhosted related software](https://github.com/awesome-selfhosted/awesome-selfhosted-data/blob/master/software/ntfy.yml), `RESEARCH.md` Competitive Landscape.
  Touches: Catalog and feed schemas, alias resolution, `New-ProjectsExportJson`, optional Backstage export, fixtures and privacy tests.
  Acceptance: Before implementation, record one owned consumer and the first real project family it will render. Canonical entries accept an enum of `companion`, `extensionOf`, `supersedes`, and `suiteMember` with `targetRepo`; generation resolves aliases to stable IDs, rejects unknown targets and self-links, generates inverse `supersedes` information deterministically, and fails any public relation whose target is suppressed. Advance `schemaPolicy.currentVersion` from 3 to 4, retain version 3 in `supportedVersions`, and prove the existing field-selecting v3 compatibility fixture still passes. README output remains unchanged until a separate render decision is recorded.
  Complexity: M

### P3

- [ ] P3: Add a culture and input-order determinism oracle
  Why: Generated hashes treat ordering as meaningful, while many `Sort-Object` calls can inherit culture and metadata arrives in nondeterministic order.
  Evidence: `scripts/sync-profile.ps1`, `Get-StringSha256`, `reports/profile-sync-report.json.provenance`, `RESEARCH.md` Rejected Ideas.
  Touches: Sort comparers in generation paths, clock/time-zone seams, deterministic generation tests in `tests/sync-profile.Tests.ps1`.
  Acceptance: With volatile timestamps frozen, generation from the same fixture under `en-US` and `tr-TR`, UTC and America/New_York, and at least 20 shuffled repository/catalog input orders produces byte-identical README, feed, Backstage export, and SVG output. Any exposed difference is fixed with an explicit stable ordinal comparer for identifiers and a documented comparer for human text.
  Complexity: S

- [ ] P3: Generate distinct action-link names for assistive technology
  Why: Current smoke evidence aggregates 1,808 links and 884 duplicate labels across four viewports; identical names such as Repo, Install, and Download can point to different destinations.
  Evidence: `reports/rendered-profile-smoke.json`, [WCAG 2.4.4](https://www.w3.org/WAI/WCAG22/Understanding/link-purpose-in-context.html), `RESEARCH.md` Architecture Assessment.
  Touches: Action-label rendering in `New-Readme`, rendered-smoke link audit, README size budget, accessibility fixtures.
  Acceptance: Every primary project action has a project-specific accessible name, for example `Download ZeusWatch`. Smoke reports `ambiguousCrossDestinationLinkLabelCount` per viewport and the count is zero at all four viewports; same-name links to the same normalized destination are not treated as ambiguous. README remains below its 98,304-byte soft limit and smoke passes.
  Complexity: M

- [ ] P3: Add a consumer-gated opt-in JSON Feed 1.1 alias export
  Why: A feed alias is cheap only if a real reader wants project updates; 2026-08-23 research found no current consumer and JSON Feed models a changing item stream rather than a static catalog.
  Evidence: [JSON Feed 1.1](https://www.jsonfeed.org/version/1.1/), `projects.json`, `RESEARCH.md` Rejected Ideas and Open Questions.
  Touches: A `New-JsonFeedExport` builder beside the Backstage exporter, opt-in path parameter, validation fixtures, generated documentation.
  Acceptance: Record the named consumer and its update semantics first. The opt-in document uses the exact 1.1 version URL, title, stable string item IDs, at least one of `content_text` or `content_html` per item, canonical URLs, `home_page_url`, and `feed_url`; it validates against an independent JSON Feed fixture, remains at most 256,000 bytes or paginates with `next_url`, and is served as `application/feed+json` by the named consumer. Default artifacts are byte-identical when the option is absent.
  Complexity: S

## Research-Driven Additions (2026-09-04)

### P1

- [ ] P1: Prove every failure condition can actually fail
  Why: The 22 blocking conditions have no test that plants a realistic violation and watches the gate fire, which is how the P0 feed-sync hole survived 330 It blocks and roughly thirty audit passes.
  Evidence: `$failureConditions` (`scripts/sync-profile.ps1:14132`). `Describe 'Test-ProfileState projects sync gate'` (`tests/sync-profile.Tests.ps1:5812`) covers only a wholly invalid payload and an info-only provenance drift, and misses the space between them. Mutation-testing practice treats a surviving mutant as proof of an assertion gap (https://stryker-mutator.io/docs/, http://www0.cs.ucl.ac.uk/staff/M.Harman/tse-mutation-survey.pdf). See `RESEARCH.md` Security, Privacy, and Reliability.
  Touches: a new `Describe 'Failure condition reachability'` in `tests/sync-profile.Tests.ps1`, fixtures under `tests/fixtures/`.
  Acceptance: One It per entry in `$failureConditions`, each planting the smallest realistic violation of that condition into an otherwise valid fixture run of `Test-ProfileState`, asserting both `Failed` and that specific condition are true and that no unrelated condition flipped. A guard test enumerates the `$failureConditions` keys and fails if any key has no matching reachability test, so a new condition cannot be added without one. Conditions that need a switch, such as `releaseArtifactVerification`, are exercised with that switch set.
  Complexity: M

- [ ] P1: Replace the unreachable attestation next action with an achievable checksum action
  Why: The release-trust shortlist tells the maintainer to publish build-provenance attestations on all 91 executable downloads, but attestation generation requires a GitHub Actions OIDC token and the repository forbids Actions, so the report's headline remediation can never be performed.
  Evidence: `reports/profile-sync-report.json.releaseAssetDrift.executableDownloadTrustShortlist` sets `nextAction: publish-build-provenance-attestation` on every row and reports `attestationGapCount: 91`, `checksumGapCount: 75`, `platformDigestCount: 91`, and `releaseImmutability.immutableCount: 17` of 152 release rows. Attestation generation is Actions-only (https://github.com/actions/attest) and `gh attestation verify` is verification only (https://cli.github.com/manual/gh_attestation_verify). `AGENTS.md` forbids hosted workflows. See `RESEARCH.md` Security, Privacy, and Reliability.
  Touches: `New-ReleaseTrust` (`scripts/sync-profile.ps1:2547`) and the shortlist builder, the `readinessLevel` and `nextAction` enums in `schemas/profile-sync-report.v1.json`, `scripts/write-profile-sync-summary.ps1`, release-trust tests.
  Acceptance: `nextAction` values are limited to actions achievable under the local-only policy: `publish-sha256-checksums`, `enable-immutable-releases`, `publish-sbom` and `no-action-needed`. The `attested` tier is removed from the readiness ladder, and the report states `attestationAchievable: false` with the Actions reason once at section level rather than as a per-row instruction. Ranking puts the 75 rows missing checksums above the 135 mutable releases. A test asserts no generated string recommends attestation, and that a row with full checksum coverage on an immutable release reports `no-action-needed`.
  Complexity: S

- [ ] P1: Generate a reviewable catalog stub for every uncataloged public repository
  Why: `missingPublic` is fail-closed with hand-authored remediation, so a single new public repo stops the weekly check until a full catalog row is written by hand.
  Evidence: `missingPublic` in `$failureConditions` (`scripts/sync-profile.ps1:14132`). `CHANGELOG.md` entry 2026-09-03 records the check failing from 2026-08-31 over five uncataloged repos (WeightTrack, NoNo, IRL Streamer, BillMinder for PC, OpenRadar). The blank-and-log pattern from https://github.com/DSACMS/automated-codejson-generator is the precedent. See `RESEARCH.md` Security, Privacy, and Reliability.
  Touches: a new `New-CatalogEntryStub` beside `New-CatalogEntry` (`scripts/sync-profile.ps1:1288`), a `-DraftMissingCatalogEntries` switch, the `missingPublicRepos` report rows, `tests/sync-profile.Tests.ps1`.
  Acceptance: When `-Check` finds uncataloged public repos it writes a ready-to-paste JSON fragment per repo into the `missingPublicRepos` rows, populated from live metadata for `repo`, `title`, `language`, `branch`, `descriptionOverride` and an inferred `category`, with every unobservable field emitted as null and listed in a per-row `unresolvedFields` array. It never writes to `data/profile-catalog.json` unless `-DraftMissingCatalogEntries` is passed with `-Write`, and in that mode every drafted row is created suppressed with a review-required `suppressionReason` so nothing reaches the public feed before the owner edits it. The gate still fails either way. A test with two synthetic uncataloged repos asserts the stub contents, the `unresolvedFields` list, the suppressed default and the unchanged failure condition.
  Complexity: M

### P2

- [ ] P2: Instrument the remaining scripts for code coverage
  Why: Coverage measures only `sync-profile.ps1`, so five production scripts plus the public bootstrap have no line coverage at all, and the committed `coverage.xml` is eleven days older than the generator and still names a deleted function.
  Evidence: `scripts/validate-local.ps1` sets `CodeCoverage.Path` to `scripts/sync-profile.ps1` alone. `coverage.xml`, dated 2026-08-23, instruments one class and reports 81.0 percent line coverage with 24 functions at zero. Uncovered: `render-profile-smoke.ps1`, `validate-local.ps1`, `review-local-dependencies.ps1`, `write-profile-sync-summary.ps1`, `new-support-bundle.ps1`, `setup.ps1`. Test coverage is one of the few CHAOSS metrics still considered reliable in 2026 (https://nesbitt.io/2026/05/27/chaoss-metrics-in-2026.html). See `RESEARCH.md` Architecture Assessment.
  Touches: the Pester configuration in `scripts/validate-local.ps1`, new Describe blocks in `tests/sync-profile.Tests.ps1` or a sibling test file, `.gitignore` if the coverage output name changes.
  Acceptance: `CodeCoverage.Path` covers every file under `scripts/` plus `setup.ps1`. Each newly instrumented script gains direct tests for its pure helpers, at minimum `ConvertTo-RedactedSupportText`, `Limit-SupportText`, `ConvertTo-NpmAuditReview`, `Get-DependencyPinFreshness`, `ConvertTo-MarkdownCell`, `ConvertTo-GitHubAnnotationProperty` and `Find-ChromeExecutable`. The run prints per-file coverage and the lane fails if any instrumented file reports zero covered commands, which catches a file that is instrumented but never loaded.
  Complexity: M

- [ ] P2: Emit structured JSON Schema validation diagnostics
  Why: `schemaValidation` is a blocking condition whose failure output is a single generic exception string with no instance path or failing keyword, against a report schema of 7,467 lines and 56 required keys.
  Evidence: `Test-JsonSchemaContract` (`scripts/sync-profile.ps1:11063`) calls `Test-Json -SchemaFile`, which since PowerShell 7.4 returns only a boolean (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/test-json?view=powershell-7.6). JsonSchema.NET, the library already backing `Test-Json`, exposes `EvaluationResults` with Detailed and Verbose output formats. `Test-SchemaKeywordCoverage` (`scripts/sync-profile.ps1:11012`) recurses only into `properties`, `items` and root `$defs`, so composition keywords and `additionalProperties` subschemas are unchecked. See `RESEARCH.md` Architecture Assessment.
  Touches: `Test-JsonSchemaContract`, `Test-SchemaKeywordCoverage`, the `schemaValidation` block in `schemas/profile-sync-report.v1.json`, `Describe 'Feed schema contracts'` (`tests/sync-profile.Tests.ps1:4238`).
  Acceptance: A validation failure reports an array of errors, each carrying `instanceLocation`, `keywordLocation` and a message taken from JsonSchema.NET detailed output. `Test-SchemaKeywordCoverage` also walks `additionalProperties`, `patternProperties`, `oneOf`, `anyOf`, `allOf`, `not`, `if`, `then`, `else`, `prefixItems` and nested `$defs`. A fixture with a wrong-typed value three levels deep produces an error naming that exact path, and a fixture schema using `oneOf` inside a property produces the allowlist warning.
  Complexity: M

- [ ] P2: Commit npm supply-chain defaults and verify registry signatures locally
  Why: There is no `.npmrc`, dependency lifecycle scripts run on install under the npm version this machine has, and the dependency review runs `npm audit` but never `npm audit signatures`, which verifies registry signatures and provenance with no CI.
  Evidence: no `.npmrc` exists in the repo. `scripts/review-local-dependencies.ps1:76` runs `npm audit --json` only. `npm audit signatures` works against a local `node_modules` tree (https://docs.npmjs.com/cli/audit/, https://docs.npmjs.com/viewing-package-provenance/). The Shai-Hulud family moved to `preinstall`, which runs even when the install fails (https://www.microsoft.com/en-us/security/blog/2025/12/09/shai-hulud-2-0-guidance-for-detecting-investigating-and-defending-against-the-supply-chain-attack/). `min-release-age` is opt-in in every npm version to date. See `RESEARCH.md` Security, Privacy, and Reliability.
  Touches: a new `.npmrc`, `scripts/review-local-dependencies.ps1`, the bootstrap in `scripts/validate-local.ps1`, the dependency-review block in `schemas/profile-sync-report.v1.json`, `Describe 'Local dependency advisory review'` (`tests/sync-profile.Tests.ps1:7077`).
  Acceptance: A committed `.npmrc` sets `ignore-scripts=true`, `audit-level=high` and `min-release-age=1440`. `validate-local.ps1` runs `npm ci` under those settings, and the dependency review then runs `npm audit signatures`, recording verified, unverified and missing-signature counts plus provenance presence per direct dependency, and failing on any signature mismatch. A fixture with a tampered signature result fails the review; a clean fixture passes and records the counts.
  Complexity: S

- [ ] P2: Run OpenSSF Scorecard locally instead of reading a hosted score
  Why: Scorecard evidence is a remote score plus a grep for a workflow the policy guarantees will never exist, so the repo cannot reproduce or act on its own 6.7 score.
  Evidence: `Get-ScorecardScoreApiUrl` (`scripts/sync-profile.ps1:9533`) reads `api.securityscorecards.dev`. `$hasScorecardSarif` (`scripts/sync-profile.ps1:9427`) matches `ossf/scorecard-action@` against workflow text that is always empty because `.github/workflows` does not exist. Scorecard v5.5.0 is a standalone binary that runs against the public API with a `public_repo` token and needs no Actions (https://github.com/ossf/scorecard). `Roadmap_Blocked.md` blocks the Scorecard improvement path on a documentation-hygiene conflict, which a local run makes moot. See `RESEARCH.md` Architecture Assessment.
  Touches: `Get-ScorecardScoreSnapshot` (`scripts/sync-profile.ps1:9559`), `Get-ScorecardAlertPosture` (`:9683`), `Get-CodeScanningLocalEvidence` (`:9407`), a `-RunScorecard` switch, the `repositorySettings` block in `schemas/profile-sync-report.v1.json`.
  Acceptance: With the binary present and `-RunScorecard` passed, the report records a locally produced per-check score set with the tool version and run timestamp, and each check carries a disposition of `actionable`, `externally-governed` or `not-applicable` with a one-line reason. Without the binary the section reports `unavailable` with an install hint and never fails the run. The permanently false workflow grep is deleted along with `scorecardSarifUploadPresent`.
  Complexity: M

- [ ] P2: Derive profile SVG generation from what the README actually references
  Why: Twelve SVGs totalling 106,118 bytes are generated, committed, contrast-checked, budget-counted and drift-checked while the README references none of them, and the two contribution heatmaps are the sole reason for a GraphQL call on every run.
  Evidence: `README.md` contains zero `<img>` tags and zero `assets/profile` references, and `readmeExperienceChecks.imageTagCount` is 0. `tests/sync-profile.Tests.ps1:2951-2967` asserts their absence. `profileAssetChecks` reports both `contributions-*.svg` permanently `inSync: false`. `New-ProfileAssetSvgs` (`scripts/sync-profile.ps1:4599`) always emits all twelve. `Get-ContributionCalendar` (`scripts/sync-profile.ps1:1102`) feeds only those two files and the offline snapshot completeness check (`scripts/sync-profile.ps1:5581`). `Roadmap_Blocked.md` frames this as a product decision and states the README references only the footer pair, which is factually wrong: nothing is referenced. See `RESEARCH.md` Architecture Assessment.
  Touches: `New-ProfileAssetSvgs`, `New-ProfileChrome` (`scripts/sync-profile.ps1:4664`), the contribution-calendar fetch and the offline snapshot completeness rule, `profileAssetChecks`, the `artifactBudgets` asset rows, `tests/sync-profile.Tests.ps1:3468`.
  Acceptance: The generated asset set is computed from the asset paths the generated README actually references, so minimal mode emits nothing and rich mode emits its full set with no code change to switch between them. Assets no longer referenced are deleted from `assets/profile` through the existing publication transaction rather than left behind. `Get-ContributionCalendar` is called only when a contribution asset is in the computed set, and the offline snapshot requires a non-empty calendar only in that case. If rich mode is ever restored, theme selection uses `<picture>` with `prefers-color-scheme` rather than the superseded `#gh-dark-mode-only` fragments. Tests cover minimal mode emitting zero assets with no contribution fetch, rich mode emitting twelve, and a mode switch removing the stale files.
  Complexity: M

- [ ] P2: Distinguish live-probed from cache-served link results
  Why: The report presents 365 clean link targets with no indication that a run can serve every one of them from cache, so a green link check can be entirely stale within the flat 24-hour TTL.
  Evidence: `reports/profile-sync-report.json.validationPerformance.cache.links` reports `hitCount: 365, missCount: 0, writeCount: 0` for the same run in which `linkValidationSummary` reports `targetCount: 365, failureCount: 0, elapsedMs: 9107`, and the summary carries no live-versus-cached field. lychee reports cache hits separately and offers `--cache-exclude-status` for exactly this reason (https://github.com/lycheeverse/lychee). This supports the open status-aware-cache item rather than replacing it. See `RESEARCH.md` Architecture Assessment.
  Touches: `Invoke-LinkProbeBatch` (`scripts/sync-profile.ps1:2901`), the `linkValidationSummary` builder, `schemas/profile-sync-report.v1.json`, `scripts/write-profile-sync-summary.ps1`, the validation-cache Describe (`tests/sync-profile.Tests.ps1:1593`).
  Acceptance: `linkValidationSummary` reports `liveProbedCount`, `cacheServedCount`, `oldestCacheEntryAgeHours` and `allResultsFromCache`, and the summary writer states plainly when a check was fully cache-served. A run where every target is cached reports `liveProbedCount: 0` and `allResultsFromCache: true` without failing. A test seeds a cache covering all targets and asserts those values, then expires one entry and asserts `liveProbedCount` becomes 1.
  Complexity: S

- [ ] P2: Assert README structure instead of marketing copy
  Why: A blocking gate and the smoke check both key on the literal sentence "Broadcast IT, Healthcare IT, and practical public tools.", so rewriting one tagline is a three-file code change, and that sentence now sits directly above an "AI Implementation Services" section it no longer describes.
  Evidence: `Test-ReadmeExperience` (`scripts/sync-profile.ps1:7196`) requires the string in both `$hasPlainTextTagline` and `$hasMinimalProfileHeader`. `scripts/render-profile-smoke.ps1:217` detects the header by the same words. `readmeExperience` is a blocking condition (`scripts/sync-profile.ps1:14132`). See `README.md:1` and `README.md:3`, and `RESEARCH.md` Architecture Assessment.
  Touches: `Test-ReadmeExperience`, `New-ProfileChrome`, component detection in `scripts/render-profile-smoke.ps1`, the README experience Describe blocks.
  Acceptance: The tagline and hero copy move into one named constant beside `$CategoryDefinitions`, and every assertion references that constant rather than a literal. Header, hero, navigation and footer detection in the smoke check use structural selectors and stable anchors rather than copy. Changing the tagline in the constant and regenerating leaves both the experience gate and the smoke check passing with no other edit, proven by a test that generates against a fixture tagline.
  Complexity: S

- [ ] P2: Delete the scheduled-workflow freshness lane and its orphaned scanner config
  Why: An entire report section, three functions and a scanner config file exist to evaluate GitHub Actions workflows that repository policy guarantees will never exist, so the lane is structurally incapable of producing a finding.
  Evidence: `scheduledWorkflowFreshness` reports `status: not-applicable`, `scheduledWorkflowCount: 0`, zero rows, because `Get-ScheduledWorkflowDefinitions` (`scripts/sync-profile.ps1:8362`) reads a `.github/workflows` directory that `AGENTS.md` forbids creating; `Get-ScheduledWorkflowRunLookup` and `Get-ScheduledWorkflowDefinitions` sit at 13 and 19 percent coverage. `.github/zizmor.yml` configures a workflow-security scanner for a repo with no workflows and no runner. See `RESEARCH.md` Architecture Assessment. Scope note: the dormant generated-PR evidence in the same class is already covered by the open "Reduce the sync report below 112 KiB" item, and the permanently-false `ossf/scorecard-action@` grep by the open local-Scorecard item; do not delete those here.
  Touches: `Get-ScheduledWorkflowDefinitions`, `Get-ScheduledWorkflowRunLookup`, `Test-ScheduledWorkflowFreshness` (`scripts/sync-profile.ps1:8286-8563`), `Get-CronNumericSet`/`Get-CronWeekMinuteOffsets`/`Get-CronMaxGapMinutes`, the `scheduledWorkflowFreshness` required key in `schemas/profile-sync-report.v1.json`, `scripts/write-profile-sync-summary.ps1`, `.github/zizmor.yml`, `Describe 'Scheduled workflow freshness'` (`tests/sync-profile.Tests.ps1:6344`) and `Describe 'Hosted automation removal contract'` (`:5704`).
  Acceptance: The section, its six functions, its schema entry and its summary rendering are removed, and `.github/zizmor.yml` is deleted. The hosted-automation removal contract test is extended to fail if `scheduledWorkflowFreshness`, any of the cron helpers, or a `zizmor.yml` reappears. The regenerated report validates against its schema and is smaller by the removed section, and the local weekly cadence stays documented in `CLAUDE.md` where it already is.
  Complexity: S

- [ ] P2: Verify release artifacts in the unattended run
  Why: Release-artifact verification has never executed unattended, so its failure condition can never fire and all 213 targets carry metadata-only evidence.
  Evidence: `reports/profile-sync-report.json.releaseArtifactVerification` reports `enabled: false`, `targetCount: 213`, `checkedAssetCount: 0`, `downloadedBytes: 0`. The failure condition is guarded by `$VerifyReleaseArtifacts` (`scripts/sync-profile.ps1:14132`). The scheduled task `SysAdminDoc Profile Freshness Check` runs `sync-profile.ps1 -Check -GraphQlPageSize 300` weekly and passes no other switch. See `RESEARCH.md` Architecture Assessment.
  Touches: `Get-ReleaseArtifactVerificationTargets` (`scripts/sync-profile.ps1:1788`), `Test-ReleaseArtifactVerification` (`:2347`), the verification cache, the `releaseArtifactVerification` report block, the scheduled task command line.
  Acceptance: Verification selects a deterministic rotating slice of targets per run, seeded by run date so every target is covered within a bounded number of weeks, honouring the existing `-ReleaseVerificationMaxAssets` and `-ReleaseVerificationMaxBytes` caps and skipping any target verified within the last 30 days. The report records `rotationWindowWeeks`, `targetsCoveredThisRun` and `targetsNeverVerified`. The scheduled task command gains `-VerifyReleaseArtifacts`. A checksum mismatch fails the run and an unreachable asset warns. A test with a seeded clock proves two consecutive runs select disjoint slices.
  Complexity: M

- [ ] P2: Declare which report sections are advisory and why
  Why: 34 of 56 report sections can never fail a run, several of them carry live integrity findings, and a reader cannot tell a deliberate warning-only policy from an omission.
  Evidence: `$failureConditions` (`scripts/sync-profile.ps1:14132`) lists 22 entries. Advisory sections with live findings include `userscriptInstallTrust` (5 warnings: one missing `@updateURL`, one missing `@downloadURL`, three broad-scope, and all 12 install URLs branch-hosted), `artifactBudgets` (over its soft limit continuously since at least 2026-08-20), `profileReleaseConsistency`, and `profileAssetsAccessibility`, whose own note says warning-only. `docs/decisions/2026-06-07-userscript-install-posture.md` documents the branch-hosting decision but not the broad-scope or missing-metadata tolerance. See `RESEARCH.md` Architecture Assessment.
  Touches: `$failureConditions`, each affected section builder, `schemas/profile-sync-report.v1.json`, `scripts/write-profile-sync-summary.ps1`.
  Acceptance: Every report section declares an explicit `enforcement` value of `blocking`, `advisory-by-policy` or `advisory-pending-decision`, and `advisory-by-policy` requires a one-line `policyReason`. A missing `@updateURL` or `@downloadURL` on a userscript becomes blocking because it breaks the update path, while broad `@match` scope stays advisory with a reason citing the existing decision record. A test enumerates the report sections and fails if any lacks an `enforcement` value.
  Complexity: S

### P3

- [ ] P3: Give every catalog entry a machine-checkable review-by date
  Why: Staleness thresholds of 365, 540 and 730 days cannot fire for an actively maintained portfolio, so `staleProjectReview` reports zero stale and zero archive-review rows out of 198 projects and provides no signal at all.
  Evidence: `reports/profile-sync-report.json.staleProjectReview` reports `staleAfterDays: 365`, `releaseStaleAfterDays: 540`, `archiveAfterDays: 730`, `staleProjectCount: 0`, `archiveReviewCount: 0`, `noReleaseCount: 38`, `warningCount: 0`. Both awesome-list pipelines run hecat with `last_updated_warn_days: 186` and `last_updated_error_days: 365` plus a commented per-repo `last_updated_skip` allowlist (https://github.com/nodiscc/hecat). RFC 9116 made `Expires` mandatory in security.txt so staleness is checkable by construction, and adopter compliance rose from 1.78 percent in 2021 to 88.6 percent in 2026 (https://www.rfc-editor.org/info/rfc9116/). See `RESEARCH.md` Competitive Landscape.
  Touches: `Test-StaleProjectReview` (`scripts/sync-profile.ps1:12532`), the entry shape in `data/profile-catalog.json`, `schemas/profile-catalog.v1.json`, the `staleProjectReview` report block.
  Acceptance: Catalog entries accept an optional `reviewBy` ISO date and an optional `stalenessExempt` boolean that requires a reason string. Default thresholds move to 186 days warn and 365 days error against last push, matching the awesome-list norm, with exempt entries excluded and counted separately. A past `reviewBy` produces a warning naming the entry. The section reports `exemptCount` and `reviewOverdueCount`, and a fixture with one overdue, one exempt and one current entry produces exactly one warning.
  Complexity: S

- [ ] P3: Complete the public repository surface metadata
  Why: The repository `homepage` field is empty even though the profile's single call to action points at the portfolio, and the hand-authored services header carries no quantified outcomes, which is the one structural feature that separates for-hire profiles from hobbyist ones.
  Evidence: `gh api repos/SysAdminDoc/SysAdminDoc` returns `homepage: null` with topics `github-profile`, `portfolio`, `readme`. `README.md:3-7` carries the positioning line and the single CTA and no numbers. Verified for-hire profiles lead with client, project and geography counts and group skills as service categories (https://github.com/prashant-software-developer, https://github.com/RupeshDev18); the minimal end of the range does the same in prose (https://github.com/tiangolo). See `RESEARCH.md` Competitive Landscape.
  Touches: repository settings via `gh api repos/{owner}/{repo} -X PATCH`, the hand-authored header above the generated-catalog notice in `README.md`, `Get-RepositoryCommunityBaseline` if homepage presence becomes reported evidence.
  Acceptance: The repository `homepage` is set to the canonical portfolio origin and the report records it as present. The services header carries at least two verifiable quantities the owner is willing to stand behind, drawn where possible from data the repo already computes, such as the public project count and the number of shipping releases. No claim is added that the catalog cannot substantiate. The generated-catalog boundary is untouched and `readmeExperience` still passes.
  Complexity: S

### P2 (found during the 2026-09-04 drain)

- [ ] P2: Resolve or record the IRL_Streamer unknown-license row
  Why: `Feed JSON Schema contracts.keeps committed release and license trust drift resolved` has been red at HEAD since before this drain, so the suite carries a permanent baseline failure that masks new license regressions.
  Evidence: `tests/sync-profile.Tests.ps1:4509` asserts `projectLicenseMetadata.unresolvedUnknownCount` is 0; the committed report and the regenerated one both report 1, for `{"repo":"IRL_Streamer","licenseKey":"other","licenseName":"Other","licenseSpdxId":"NOASSERTION","reason":"GitHub reported an unrecognized or non-standard license","intentionalException":false}`. Reproduced 2026-09-04 against both the working tree and `git show HEAD:reports/profile-sync-report.json`.
  Touches: the `IRL_Streamer` LICENSE file upstream, or the intentional-exception fields consumed by `Test-ProjectLicenseMetadata` (`scripts/sync-profile.ps1:12295`) and `data/profile-catalog.json`.
  Acceptance: Either the upstream repository carries a license GitHub resolves to a real SPDX id, or the catalog row records `intentionalException: true` with a specific `exceptionReason` naming why the license is non-standard. `unresolvedUnknownCount` is 0 and the named test passes without its assertions being weakened.
  Complexity: S
