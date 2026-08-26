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
