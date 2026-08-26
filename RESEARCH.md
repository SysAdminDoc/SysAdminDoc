# Research: SysAdminDoc

Date: 2026-08-23. Replaces all prior research.

Confidence labels used below: **Verified** means confirmed in the current tree, live tracker, or a primary source. **Likely** is an evidence-backed inference. **Needs live validation** marks a consumer decision that this repository cannot answer.

## Executive Summary

SysAdminDoc v4.10.0 is a single-owner, PowerShell-generated GitHub profile and public software catalog. Its current working-tree evidence records 216 public repositories, 222 canonical catalog rows, 193 feed projects, 180 README projects, and 29 redacted suppressions (`reports/profile-sync-report.json`, `data/profile-catalog.json`, `projects.json`). It is already stronger than the profile-generator market on deterministic output, privacy boundaries, release evidence, local validation, and machine-readable data. The highest-value direction is therefore not more profile chrome. It is making every write recoverable, every network probe safe, and every evidence claim truthful while extending the catalog only where an owned consumer exists.

Highest-value opportunities, in priority order:

1. **Verified:** Refuse canonical `-Write -Offline` runs unless all required cached inputs are complete. The entrypoint currently replaces repository metadata with an empty array and can overwrite good outputs with degraded data (`scripts/sync-profile.ps1:12998`, `tests/sync-profile.Tests.ps1:4397`).
2. **Verified:** Stage and validate the whole README, feed, asset, and report set before replacing any target. Current direct writes can leave a mixed or truncated set after interruption (`scripts/sync-profile.ps1:13032`, `scripts/sync-profile.ps1:13076`).
3. **Verified:** Put every outbound request behind one SSRF-resistant destination policy. `Test-HttpUrl` follows redirects and checks neither resolved addresses nor private ranges (`scripts/sync-profile.ps1:2249`).
4. **Verified:** Discover all hand-authored README header links instead of three known URLs plus images. The prior dead service call to action escaped the current collector (`Get-ReadmeHeaderLinkValidationTargets` in `scripts/sync-profile.ps1:2410`, `CHANGELOG.md:9`).
5. **Verified:** Lock PowerShell Gallery package bytes and signer expectations before import. Exact versions alone do not protect `Install-Module` or `Save-Module` from a changed same-version package (`scripts/validate-local.ps1:93`, `scripts/validate-local.ps1:172`).
6. **Verified:** Use status-aware cache lifetimes, conditional requests, and server-directed retry timing. The single 24-hour TTL currently caches successes, definitive failures, and transient failures alike (`scripts/sync-profile.ps1:4504`, `scripts/sync-profile.ps1:4605`).
7. **Verified:** Replace hand-maintained "latest-known" dependency constants with dated registry evidence. The green report still names markdown-it 14.3.0 and js-yaml 5.2.2 as latest while the registries report 15.0.0 and 5.3.0 (`scripts/review-local-dependencies.ps1:13`).
8. **Verified:** Correct report claims about topic mutation and the intentional Dependabot-disabled policy, then behavior-test the active full-page GraphQL fallback (`scripts/sync-profile.ps1:676`, `scripts/sync-profile.ps1:8340`, `scripts/sync-profile.ps1:11112`).
9. **Verified:** Bring `reports/profile-sync-report.json` back under its 112 KiB soft budget by removing dormant hosted-PR evidence and compacting success-only detail (`scripts/sync-profile.ps1:8686`, `scripts/write-profile-sync-summary.ps1`).
10. **Likely:** Extend the data advantage with a consumer-gated release-artifact export and explicit project relationships. GitHub already exposes exact asset URLs, sizes, media types, and digests, while catalog products use relations for navigation (`New-ProjectsExportJson` in `scripts/sync-profile.ps1:4849`).

## Product Map

### Core workflows

- **Verified:** `data/profile-catalog.json` is the canonical editorial source. `scripts/sync-profile.ps1` reconciles it with GitHub metadata and generates `README.md`, `projects.json`, and 12 committed SVG assets.
- **Verified:** `scripts/sync-profile.ps1 -Check` assembles structural, privacy, schema, link, accessibility, release, repository-setting, provenance, and downstream-compatibility evidence in `reports/profile-sync-report.json`.
- **Verified:** `scripts/validate-local.ps1` installs pinned local tools, runs dependency review, markdownlint, PSScriptAnalyzer, Pester, coverage, generation checks, and rendered smoke validation. Hosted build and test workflows are intentionally absent (`AGENTS.md`, `README.md:70`).
- **Verified:** Optional paths apply allowlisted repository topics, validate capped release artifacts, probe the deployed portfolio, emit a Backstage catalog, and create a redacted support bundle (`scripts/sync-profile.ps1`, `scripts/new-support-bundle.ps1`).

### User personas

- **Verified:** The owner-maintainer curates one public profile and its privacy boundary. This is not a multi-tenant product (`README.md`, `AGENTS.md`).
- **Verified:** GitHub profile visitors need fast routes to representative projects, downloads, source, setup, and services (`README.md`).
- **Verified:** Owned downstream consumers use `projects.json` as a stable, public-safe catalog feed (`schemas/profile-projects.v1.json`, `reports/profile-sync-report.json.portfolioCompatibility`).
- **Likely:** Store and portfolio maintainers benefit more from exact artifact and relationship data than from additional README presentation.

### Platforms and distribution

- **Verified:** The public surface is GitHub-rendered Markdown and committed SVG, with a separate web portfolio consuming JSON (`README.md`, `projects.json`).
- **Verified:** Generation and validation target PowerShell 7.4 or newer on Windows; `setup.ps1` remains the Windows PowerShell 5.1 bootstrap. Node 22 or newer supplies local Markdown tooling (`scripts/setup.ps1`, `scripts/validate-local.ps1`, `package.json`).
- **Verified:** Render smoke exercises four desktop and mobile viewports in headless Chromium-compatible browsers. Current evidence reports no page overflow, clipping, overlap, or keyboard-inaccessible details controls (`reports/rendered-profile-smoke.json`).

### Key integrations and data flows

- **Verified:** GitHub CLI provides GraphQL repository and contribution data plus version-pinned REST release, settings, topic, and governance data (`Invoke-GhCli` and `Get-GitHubRepos` in `scripts/sync-profile.ps1`).
- **Verified:** npm supplies a lockfile-integrity-backed Markdown toolchain; PowerShell Gallery supplies Pester and PSScriptAnalyzer; PyPI requirements hash-pin zizmor (`package-lock.json`, `scripts/validate-local.ps1`, `requirements-local-audit.txt`).
- **Verified:** Public data flows from catalog plus live metadata into README, JSON, SVG, optional Backstage output, local evidence, and the separate portfolio. Suppressed identifiers are redacted from visitor-facing output (`schemas/profile-projects.v1.json`, `reports/profile-sync-report.json`).

## Competitive Landscape

- [github-profile-readme-generator](https://github.com/rahuldkjain/github-profile-readme-generator) does onboarding, validation, autosave, mobile-first editing, GitHub autofill, and versioned configuration round trips well. Learn from its explicit draft/import contract. Avoid rebuilding a general-purpose form wizard for one owner.
- [profile-readme-generator](https://github.com/maurodesouza/profile-readme-generator) makes arbitrary sections and ordering approachable. Its open [stats freshness report](https://github.com/maurodesouza/profile-readme-generator/issues/88) reinforces the cost of third-party cards. Keep deterministic owned assets instead.
- [ReadmeForge](https://github.com/lebedevnet/ReadmeForge) is a useful local-first reference because it is static, account-free, and supports versioned JSON drafts. Its layouts and 18 themes solve broad-user customization that SysAdminDoc does not need.
- [GitProfile](https://github.com/arifszn/gitprofile) handles themes, SEO, PWA behavior, project selection, work history, publications, and resumes. Treat it as evidence that the separate portfolio should own presentation. Do not duplicate that application inside this repository.
- [github-readme-stats](https://github.com/anuraghazra/github-readme-stats), [github-profile-trophy](https://github.com/ryo-ma/github-profile-trophy), and [github-readme-streak-stats](https://github.com/DenverCoder1/github-readme-streak-stats) show strong demand for visual summaries but also service pauses, inaccurate output, quotas, and hosting-cost pressure in their current trackers. Preserve committed, first-party SVGs and local refreshes.
- [metrics](https://github.com/lowlighter/metrics) proves that a plugin-rich generator can serve many output formats and data sources. Its operational surface is the reason not to add a plugin system here. Borrow only its strict separation between data collection and renderers.
- [Backstage](https://github.com/backstage/backstage) provides the strongest adjacent model for entity identity, relations, staged processing, and provenance. Borrow those data patterns. Avoid its database, event loop, ownership model, and runtime service for a version-controlled personal catalog.
- [Awesome Selfhosted Data](https://github.com/awesome-selfhosted/awesome-selfhosted-data) and [Awesome Sysadmin Data](https://github.com/awesome-foss/awesome-sysadmin-data) validate the data-first model, related-software links, deterministic public views, and continuous dead-link, rename, duplicate, and abandonment maintenance. SysAdminDoc already leads on privacy and live repository reconciliation; explicit relationships are the useful missing piece.
- [Contra portfolios](https://contra.com/portfolios) and [Fueler](https://www.fueler.io/pricing) treat case studies, proof of work, custom presentation, and analytics as product value. The useful lesson is a maintained evidence link on the owned portfolio. Avoid tracking pixels, visitor counters, email capture, and commercial-site features in a GitHub README.

## Reported Issues

- **Verified:** The live [issue tracker](https://github.com/SysAdminDoc/SysAdminDoc/issues) has zero open and zero closed issues as of 2026-08-23. There are no user-reported bugs or feature requests to promote above repository findings.
- **Verified:** The live [pull request list](https://github.com/SysAdminDoc/SysAdminDoc/pulls) has no open pull requests. PRs 1 through 23 are closed historical automation, dependency, and governance work. None supplies an unmerged user patch.
- **Verified:** [Discussions](https://github.com/SysAdminDoc/SysAdminDoc/discussions) are enabled but empty.
- **Verified:** Five historical OpenSSF Scorecard code-scanning alerts remain open: [1](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/1), [3](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/3), [4](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/4), [5](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/5), and [6](https://github.com/SysAdminDoc/SysAdminDoc/security/code-scanning/6). They came from removed hosted workflows; the current local report classifies them as externally governed or not applicable (`reports/profile-sync-report.json`, `Roadmap_Blocked.md`). They are not evidence of a current code defect.

## Security, Privacy, and Reliability

- **Verified, P0:** The main entrypoint sets `$repos` to an empty array whenever `-Offline` is present, bypassing the offline cache behavior already implemented in `Get-GitHubRepos`. `-Write -Offline` then writes canonical README, feed, and assets, and its integration test explicitly accepts `publicRepoCount = 0` (`scripts/sync-profile.ps1:634`, `scripts/sync-profile.ps1:12998`, `tests/sync-profile.Tests.ps1:4397`). Contribution data is also unavailable offline (`scripts/sync-profile.ps1:1104`). This is a reproducible data-loss path, not merely reduced fidelity.
- **Verified, P1:** Generated files and cache entries are written directly. An interruption between targets can publish a new README with an old feed, truncate a destination, or leave only part of the SVG set updated (`scripts/sync-profile.ps1:4650`, `scripts/sync-profile.ps1:13032`). Same-volume staging, validated promotion, retained backups, and rollback are required. [.NET File.Replace](https://learn.microsoft.com/en-us/dotnet/api/system.io.file.replace?view=net-10.0) provides the Windows primitive for existing targets.
- **Verified, P1:** `Test-HttpUrl` enables automatic redirects and does no credential, hostname, DNS, or address-range validation. Catalog `liveUrl` values and external redirects can therefore reach loopback, RFC1918, link-local, carrier-grade NAT, IPv6-local, or metadata-service destinations (`scripts/sync-profile.ps1:2249`, `Get-LinkValidationTargets`). [OWASP SSRF guidance](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html) calls for validating every A and AAAA address and every redirect hop.
- **Verified, P1:** The header-link collector validates only the portfolio, setup raw/source URLs, and images. It does not enumerate arbitrary Markdown or HTML hyperlinks (`scripts/sync-profile.ps1:2410`). A future dead or redirected call to action can therefore pass the same 355-target check recorded as clean on 2026-08-20 (`reports/profile-sync-report.json`).
- **Verified, P1:** `Install-Module` and `Save-Module` download and import exact versions without locking package bytes. Microsoft documents that [`Save-PSResource`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/save-psresource?view=powershellget-3.x) can preserve a package and run Authenticode checks. The Gallery record for [Pester 6.1.0](https://www.powershellgallery.com/packages/Pester/6.1.0) does not include a package signature, so a reviewed nupkg SHA-256 remains necessary (`scripts/validate-local.ps1:113`, `scripts/validate-local.ps1:197`).
- **Verified, P1:** A single 24-hour cache TTL applies across repository metadata, release metadata, and links. Link results include 404, 410, timeout, 429, and 5xx states, yet stale entries are discarded before validators can be reused (`scripts/sync-profile.ps1:4504`, `scripts/sync-profile.ps1:4605`, `Invoke-LinkProbeBatch`). [RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html) and [GitHub REST best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api) support conditional requests, server-directed retry timing, and bounded backoff.
- **Verified, P2:** Repository descriptions and catalog strings enter Markdown table cells, link labels, and HTML without one shared output-context encoder. Schemas do not reject bidi controls or most control characters (`scripts/sync-profile.ps1:1421`, `scripts/sync-profile.ps1:3638`, `schemas/profile-catalog.v1.json`). This is presentation-integrity risk rather than remote code execution. The [Trojan Source research](https://trojansource.codes/trojan-source.pdf) supports rejecting visual-order controls in public identifiers and one-line descriptions while preserving ordinary international text.
- **Verified strength:** Current evidence reports zero public privacy leaks, missing public repositories, unsafe URL schemes, stale rows, link failures, or release warnings. Suppressed medical and private identifiers remain redacted (`reports/profile-sync-report.json`). Do not weaken those fail-closed rules while addressing the items above.

## Architecture Assessment

- **Verified:** `scripts/sync-profile.ps1` is 13,150 lines with 296 functions. The last 200 commits touched the generator 103 times, tests 113 times, the report 96 times, and the feed 84 times. This coupling explains why schema, report, summary, tests, and generated files usually change together (`git log -200`, `scripts/sync-profile.ps1`). Avoid a big-bang rewrite. Extract outbound policy, artifact staging, cache policy, and export builders as tested boundaries when each roadmap item lands.
- **Verified:** The dirty working-tree fallback at `scripts/sync-profile.ps1:676` correctly treats a GraphQL response that fills its configured page as potentially truncated, but no behavioral test exercises that branch. The present test only source-matches the special 100-row case (`tests/sync-profile.Tests.ps1:1089`).
- **Verified:** `metadataHygiene.topicHintPolicy.applyModeAvailable` is hard-coded false even though `-ApplyTopics` is reachable and `data/topic-allowlist.json` contains 12 repositories (`scripts/sync-profile.ps1:11112`, `scripts/sync-profile.ps1:13089`).
- **Verified:** `Get-DependabotSecurityPosture` recommends keeping Dependabot disabled with local advisory review, but `nextAction`, warning disposition, and community-baseline text still recommend enabling it (`scripts/sync-profile.ps1:8340`, `scripts/sync-profile.ps1:9278`). Evidence must reflect the repository's actual local-only policy.
- **Verified:** The current report is 122,065 bytes against a 114,688-byte soft limit. Success-heavy userscript, branch-tip, repository-setting, and release detail plus dormant hosted-PR fields consume most of the excess (`reports/profile-sync-report.json`, `scripts/sync-profile.ps1:8686`, `scripts/write-profile-sync-summary.ps1`). Keep all warning and failure rows, but aggregate success rows and remove the retired delivery model.
- **Verified:** Dependency freshness is modeled as a hand-edited assertion. Registry data reports [markdown-it 15.0.0](https://registry.npmjs.org/markdown-it/15.0.0) and [js-yaml 5.3.0](https://registry.npmjs.org/js-yaml/5.3.0), while `scripts/review-local-dependencies.ps1:13` reports 14.3.0 and 5.2.2 as latest. Keep markdown-it 14.3.0 as the compatible pin until its breaking major passes markdownlint regressions, but report `registryLatest` separately from `currentCompatible`.
- **Verified:** `CLAUDE.md` still describes v4.9.161, 206 public repositories, Pester 5.8.0, an empty topic allowlist, and stale category counts. `Roadmap_Blocked.md` says `main` has no branch protection even though the live API shows admin enforcement and force-push/deletion prevention. Local operating notes should not be used as evidence until reconciled.
- **Verified migration posture:** `projects.json.schemaPolicy` declares current schema 3 and support for versions 2 and 3 (`projects.json`, `schemas/profile-projects.v1.json`). New consumer fields must be opt-in or advance the current version while retaining the prior version in the supported window; do not mutate a strict consumer contract silently.
- **Likely:** A separate opt-in artifact export is a lower-risk integration than inflating the README. The [GitHub release API](https://docs.github.com/en/rest/releases/releases?apiVersion=latest) exposes exact tagged asset URLs, content types, sizes, and digests that current aggregate trust fields discard (`New-ReleaseTrustSummary`, `New-ProjectsExportJson`).
- **Likely:** Relationships such as `companion`, `extensionOf`, `supersedes`, and `suiteMember` would make product families navigable across `projects.json` and the existing Backstage export. [Backstage relations](https://backstage.io/docs/next/features/software-catalog/descriptor-format/) and [Awesome Selfhosted related-software records](https://github.com/awesome-selfhosted/awesome-selfhosted-data/blob/master/software/ntfy.yml) provide proven data shapes. Alias resolution, suppression, and stable IDs already provide the required local foundation.
- **Verified accessibility gap:** The current smoke evidence aggregates 1,808 links and 884 duplicate labels across four viewports (`reports/rendered-profile-smoke.json`). Raw duplicate count is a poor acceptance metric because the same viewport and destination can repeat legitimately. The existing roadmap item should instead require zero identical accessible names that resolve to different destinations within each viewport, consistent with [WCAG 2.4.4](https://www.w3.org/WAI/WCAG22/Understanding/link-purpose-in-context.html).

## Rejected Ideas

- Hosted stats, streak, trophy, visitor, and language cards were rejected. Current [github-readme-stats](https://github.com/anuraghazra/github-readme-stats/issues/3851), [github-profile-trophy](https://github.com/ryo-ma/github-profile-trophy/issues/439), and [github-readme-streak-stats](https://github.com/DenverCoder1/github-readme-streak-stats/issues) reports show paused deployments, inaccurate output, quotas, and hosting pressure. They conflict with committed first-party assets.
- Scheduled GitHub Actions were rejected. They contradict the repository's local-only validation and release policy (`AGENTS.md`, `.github/`).
- A visual README wizard, templates, drag-and-drop composition, AI-authored copy, and local draft accounts were rejected. [ReadmeForge](https://github.com/lebedevnet/ReadmeForge) and [github-profile-readme-generator](https://github.com/rahuldkjain/github-profile-readme-generator) solve broad-user onboarding, not a single-owner canonical catalog.
- Rebuilding the portfolio here was rejected. [GitProfile](https://github.com/arifszn/gitprofile), [developerFolio](https://github.com/saadpasta/developerFolio), and [masterPortfolio](https://github.com/ashutosh1919/masterPortfolio) show the ongoing theme, framework, responsive, and empty-state maintenance already assigned to the separate portfolio.
- Profile analytics, tracking pixels, email capture, public submissions, ratings, and comments were rejected. They weaken privacy or add moderation, while [HNPWD](https://github.com/hnpwd/hnpwd) documents the backlog created by more than 2,000 community suggestions.
- Native mobile, multi-user, plugin-marketplace, and multi-provider GitLab or Codeberg ingestion were rejected. GitHub owns the mobile renderer, the current 390px smoke is clean, and the repository's identity, releases, privacy model, and owner workflow are intentionally GitHub-specific (`AGENTS.md`, `reports/rendered-profile-smoke.json`).
- Immediate markdown-it 15 adoption was rejected. Its [changelog](https://raw.githubusercontent.com/markdown-it/markdown-it/master/CHANGELOG.md) marks a breaking major; the roadmap should fix freshness evidence before changing the compatible override.
- Feed signing, Sigstore badges, and SLSA Build L2 claims were rejected until a verifier, stable signing identity, and hosted build platform exist. [SLSA 1.2](https://slsa.dev/spec/v1.2/build-track-basics) does not classify locally self-generated provenance as L2.
- Full SBOM conformance downloads, PURL identifiers, field-level provenance, and a lifecycle taxonomy were deferred. [CycloneDX 1.7](https://cyclonedx.org/specification/overview/), [ECMA-427](https://ecma-international.org/publications-and-standards/standards/ecma-427/), and [Backstage descriptors](https://backstage.io/docs/next/features/software-catalog/descriptor-format/) validate the concepts, but no current consumer requires them.
- A second JSON Feed roadmap item was rejected as a duplicate. The existing P3 item remains consumer-gated. The [JSON Feed 1.1 specification](https://www.jsonfeed.org/version/1.1/) is oriented to changing item streams and recommends practical feed-size limits; a static 193-project catalog needs a named reader before implementation.
- Internationalized profile copy was deferred. The catalog preserves Unicode project text, but the product is one owner's English profile and no tracker or consumer requests locale variants (`README.md`, [live issues](https://github.com/SysAdminDoc/SysAdminDoc/issues)). Culture-independent ordering is still worth testing because output hashes must remain deterministic.
- Extra distribution packages were rejected. The deliverables are GitHub-native Markdown, JSON, and SVG, while setup already has a checked bootstrap path (`README.md`, `scripts/setup.ps1`).

## Sources

### Project and tracker

- https://github.com/SysAdminDoc/SysAdminDoc
- https://github.com/SysAdminDoc/SysAdminDoc/issues
- https://github.com/SysAdminDoc/SysAdminDoc/pulls
- https://github.com/SysAdminDoc/SysAdminDoc/discussions
- https://github.com/SysAdminDoc/SysAdminDoc/releases/tag/v4.10.0

### Direct and adjacent open source

- https://github.com/rahuldkjain/github-profile-readme-generator
- https://github.com/maurodesouza/profile-readme-generator
- https://github.com/rishavanand/github-profilinator
- https://github.com/VishwaGauravIn/github-profile-readme-maker
- https://github.com/lebedevnet/ReadmeForge
- https://github.com/Open-Dev-Society/openreadme
- https://github.com/arifszn/gitprofile
- https://github.com/saadpasta/developerFolio
- https://github.com/ashutosh1919/masterPortfolio
- https://github.com/sunithvs/devb.io
- https://github.com/anuraghazra/github-readme-stats
- https://github.com/stats-organization/github-stats-extended
- https://github.com/lowlighter/metrics
- https://github.com/vn7n24fzkq/github-profile-summary-cards
- https://github.com/ryo-ma/github-profile-trophy
- https://github.com/yoshi389111/github-profile-3d-contrib
- https://github.com/DenverCoder1/github-readme-streak-stats
- https://github.com/Platane/snk
- https://github.com/backstage/backstage
- https://github.com/awesome-selfhosted/awesome-selfhosted-data
- https://github.com/awesome-foss/awesome-sysadmin-data
- https://github.com/abhisheknaiidu/awesome-github-profile-readme
- https://github.com/hnpwd/hnpwd
- https://github.com/ecosyste-ms/repos
- https://github.com/jsonresume/resume-schema

### Commercial and community

- https://contra.com/portfolios
- https://help.contra.com/en/articles/9322981-what-is-contra-pro
- https://www.fueler.io/pricing
- https://peerlist.io/user/settings/custom-domain
- https://www.framer.com/pricing
- https://webflow.com/pricing
- https://www.notion.com/en-gb/help/notion-sites-availability-and-pricing
- https://carrd.com/pro
- https://pages.github.com/versions/
- https://news.ycombinator.com/item?id=46618714
- https://news.ycombinator.com/item?id=23780236
- https://www.reddit.com/r/webdev/comments/wtde9r/what_kind_of_portfolio_projects_will_impress/
- https://www.reddit.com/r/webdev/comments/1703qzk/how_important_are_portfolios/

### Platform, standards, security, and dependencies

- https://docs.github.com/en/account-and-profile/reference/profile-reference
- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
- https://docs.github.com/en/rest/releases/releases?apiVersion=latest
- https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api
- https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- https://docs.github.com/en/rest/about-the-rest-api/breaking-changes
- https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html
- https://cwe.mitre.org/data/definitions/918.html
- https://learn.microsoft.com/en-us/dotnet/api/system.net.http.httpclienthandler.allowautoredirect?view=net-8.0
- https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/http/httpclient-guidelines
- https://learn.microsoft.com/en-us/dotnet/api/system.io.file.replace?view=net-10.0
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/save-psresource?view=powershellget-3.x
- https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines?view=powershellget-3.x
- https://www.powershellgallery.com/packages/Pester/6.1.0
- https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0
- https://www.rfc-editor.org/rfc/rfc9110.html
- https://www.rfc-editor.org/rfc/rfc9111.html
- https://www.w3.org/WAI/WCAG22/Understanding/link-purpose-in-context.html
- https://www.w3.org/WAI/WCAG22/Understanding/reflow.html
- https://github.github.com/gfm/
- https://json-schema.org/draft/2020-12/json-schema-core.html
- https://www.jsonfeed.org/version/1.1/
- https://registry.npmjs.org/markdown-it/15.0.0
- https://registry.npmjs.org/js-yaml/5.3.0
- https://raw.githubusercontent.com/markdown-it/markdown-it/master/CHANGELOG.md
- https://raw.githubusercontent.com/nodeca/js-yaml/04db45830b9ef92454b409eca80ec80ae9b2701a/CHANGELOG.md
- https://nvd.nist.gov/vuln/detail/CVE-2026-59868
- https://cyclonedx.org/specification/overview/
- https://spdx.github.io/spdx-spec/v3.0.1/
- https://ecma-international.org/publications-and-standards/standards/ecma-427/
- https://slsa.dev/spec/v1.2/build-track-basics
- https://trojansource.codes/trojan-source.pdf

## Open Questions

- **Needs live validation:** Which owned consumer will adopt the normalized release-artifact export first, and which will render catalog relationships first? Record each consumer's required fields before starting those P2 items. This does not block the higher-priority safety and evidence work.
