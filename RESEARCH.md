# Research — SysAdminDoc

## Executive Summary

SysAdminDoc is a 9,359-line PowerShell-generated GitHub profile README, public project feed (`projects.json`, 440KB), profile-asset renderer (12 committed SVGs), and trust-evidence pipeline for 202 public repositories across PowerShell, Python, JavaScript, Kotlin, C#, C++, Rust, and TypeScript. Its strongest differentiator is deterministic, privacy-aware portfolio generation with zero external runtime dependencies: no third-party stats cards, badge hosts, or dynamic image services — everything is committed locally and validated by a 4,929-line Pester test suite at 78%+ coverage. The Scorecard score is 6.7/10 with 5 open alerts, 3 of which are external-governance-gated.

**Current blockers**: Two live CI failures — PSScriptAnalyzer flags 2 unused parameters in `New-DiscoverySection` (line 1779-1780), and zizmor's inline `# zizmor: ignore[dangerous-triggers]` suppression fails on the `dependabot-auto-merge.yml` `pull_request_target` trigger. Both prevent green CI. Three scheduled workflows (Profile sync, Assets refresh, Workflow security) are also failing — the first two from metadata drift and GraphQL 502 transients, the third from the zizmor finding.

**Top priorities** (in order): fix the two code-level CI failures; restore green scheduled workflow evidence; add a `zizmor.yml` config file to replace unreliable inline suppressions; migrate from `actions/attest-build-provenance` to `actions/attest`; resolve fork-parent attribution gaps (13 repos); make evidence freshness post-commit-aware; evaluate repository rulesets for Scorecard Branch-Protection improvement; promote platform release asset digests to first-class evidence; add API telemetry; and prove generated-PR validation end to end.

## Product Map

- **Core workflows**: edit `data/profile-catalog.json` → run `scripts/sync-profile.ps1 -Write -Check` → publish `README.md`, `projects.json`, `assets/profile/*.svg`, and `reports/profile-sync-report.json`.
- **User personas**: GitHub profile visitors, portfolio-site visitors (`sysadmindoc.github.io`), release/download users, userscript installers, public issue reporters, security reporters, and the maintainer operating generated PR workflows.
- **Platforms and distribution**: GitHub profile README (62KB, well under 96KB soft limit), raw `projects.json` feed, GitHub Actions summaries/artifacts, committed SVG assets, Windows `setup.ps1` bootstrapper, raw userscript install URLs, and the separate portfolio consumer.
- **Key integrations**: GitHub GraphQL/REST repo metadata (202 repos), release assets and platform digests, repository settings, scheduled workflow runs, OpenSSF Scorecard SARIF, Dependabot, JSON Schema (Draft 2020-12), markdownlint-cli2 0.22.1, PSScriptAnalyzer 1.25.0, Pester 5.7.1, rendered Chrome smoke, and portfolio feed import.

## Competitive Landscape

- **github-readme-stats / GPRM / ProfileMe.dev / readme.so**: Fast profile creation with social links, skill sections, and widget previews. Rate limiting on the public Vercel instance is a persistent problem (issue #4748 discusses deprecating Vercel hosting). Learn from preview speed and first-run ergonomics; avoid runtime third-party cards. SysAdminDoc's committed-SVG approach sidesteps the entire class of rate-limit/camo-proxy/broken-widget complaints that dominate community forums.
- **lowlighter/metrics**: Rich plugin model with 30+ plugins and GitHub Actions generation. Learn from modular report sections; avoid sprawling plugin complexity. SysAdminDoc is a single-maintainer catalog, not a general metrics platform.
- **cicirello/user-statistician**: Commits generated SVG stats through GitHub Actions with localization requests. Learn from committed output and template-driven labels; reject full i18n for now.
- **Platane/snk / DenverCoder1/readme-typing-svg**: Popular profile visuals but open issues show generation/runtime failures and broken image links. SysAdminDoc correctly uses motion-safe committed chrome.
- **Awesome lists**: `awesome-github-profile-readme`, `awesome-sysadmin`, `awesome-userscripts` reward concise positioning, maturity, active maintenance, and working links. SysAdminDoc should maintain its "real tools with install/download paths" posture.
- **GitHub/OpenSSF supply-chain tooling**: `actions/attest` (consolidating `attest-build-provenance` and `attest-sbom`), immutable releases (GA Oct 2025), Scorecard v5.5.0, zizmor v1.25.2 (39 audit rules), actionlint v1.7.12, poutine v1.1.6, harden-runner v2.19.4. SysAdminDoc already integrates all of these; the gap is in upgrading to the consolidated `actions/attest` action and fixing the zizmor suppression.
- **No existing profile README tool has a test suite** — Pester-backed validation of generated markdown, link checking, image accessibility, size limits, and rendering correctness is a unique differentiator for SysAdminDoc.

## Security, Privacy, and Reliability

**Live CI failures** (verified 2026-06-20):
- `scripts/sync-profile.ps1:1779-1780` — `New-DiscoverySection` declares `$Entries` and `$Repos` parameters that are never used. PSScriptAnalyzer `PSReviewUnusedParameter` flags both, failing the Tests workflow.
- `.github/workflows/dependabot-auto-merge.yml:8` — inline `# zizmor: ignore[dangerous-triggers]` suppression is not recognized by zizmor 1.25.2. The `dangerous-triggers` finding on `pull_request_target` fails the Workflow security workflow with exit code 14. The workflow is hardened (no checkout, empty workflow-level permissions, narrow job-level write scopes, actor/repo checks), but zizmor's inline suppression for this workflow-level trigger isn't being honored. A `zizmor.yml` configuration file with `rules.dangerous-triggers.ignore` is the recommended fix path.

**Scheduled workflow failures** (verified via `gh run list`):
- Profile sync (last scheduled: 2026-06-19): fails because generated README drifts from committed state as live metadata (star counts, pushedAt) changes.
- Profile assets refresh (last scheduled: 2026-06-17): hit GraphQL 502 on metadata fetch, fell back to REST, then the profile sync check itself failed.
- Workflow security (last scheduled: 2026-06-17): zizmor `dangerous-triggers` finding (see above).
- Automation branch cleanup and Scorecard are healthy (both last ran successfully).

**Evidence freshness paradox**: `reports/profile-sync-report.json.evidenceFreshness.status` is always `stale` because the report is generated before the commit that contains it (report at `2026-06-19T00:01:12`, commit at `2026-06-19T00:04:07`). Already identified in the roadmap.

**Release trust gaps** (from sync report):
- 136 release-bearing repos, 0 immutable releases, 84 with platform digests, 52 without.
- 65 executable download rows with 55 checksum gaps, 65 attestation gaps, 64 SBOM gaps.
- `actions/attest-build-provenance@v4.1.0` is a wrapper around `actions/attest`; new implementations should use `actions/attest@v2` directly.

**Branch protection / rulesets**: `main` has no branch protection (API returns 404) and no rulesets (empty array). Scorecard Branch-Protection alert is open. Repository rulesets are now the recommended replacement — they're readable by default `GITHUB_TOKEN` (no admin PAT needed), support bypass actor lists with audit logs, and stack additively.

**Privacy guardrails**: Strong. `projects.json.suppressed` redacts suppressed identifiers, `portfolioCompatibility.suppressedIdentifierLeakCount` is zero, medical pattern matching uses word-boundary anchors, and issue forms warn against private data.

**Dependency security**: markdown-it pinned to 14.2.0 (addresses CVE-2026-48988 DoS), js-yaml pinned to 4.2.0 (addresses DoS). CVE-2025-7969 (markdown-it XSS in fenced code blocks) should be verified as covered by 14.2.0.

**Fork-parent attribution gaps**: 13 repos are GitHub forks with no `forkOf` in the catalog (e.g., `notepad-plus-plus`, `vcpkg`, `stylus`). Warning-only in the report but creates attribution debt.

## Architecture Assessment

- `scripts/sync-profile.ps1` (9,359 lines) is the correct orchestration boundary with 130+ functions. The test seam pattern (dot-source for functions, `InvocationName` guard for live execution) is sound. Continue gaining small, tested helper boundaries rather than new standalone scripts.
- The GitHub metadata strategy is directionally correct: exclude expensive `latestRelease` from bulk GraphQL, retry transient 502s, fall back to REST pagination. The 100-repo default-page detection (line 425-427) is a good guard. Next improvement: record rate-limit headroom, retry counts, and fallback reasons.
- `Get-LatestReportAffectingCommit` / evidence freshness needs a same-commit interpretation so a validly generated report isn't flagged stale immediately after commit.
- The `New-DiscoverySection` unused params are a regression from the v4.9.137-v4.9.139 compact profile overhaul that simplified the routing section but didn't clean up the function signature.
- Required-check readiness has strong local report structure but no live enforcement. Repository rulesets (not classic branch protection) are the recommended path forward, with bypass-actor audit logs for the direct-main maintenance model.
- The `zizmor.yml` configuration file approach is more maintainable than inline `# zizmor: ignore[...]` comments for workflow-level audits like `dangerous-triggers`.
- Feed compatibility is guarded inside this repo but lacks a contract fixture against the downstream `sysadmindoc.github.io` importer expectations.
- Test coverage floor (78%) is reasonable but could benefit from Pester's `ExcludeTests` option (available since 5.7.0) to prevent test files from inflating coverage numbers.
- No separate accessibility, offline, mobile, i18n, or plugin roadmap item is warranted — committed SVG accessibility checks and rendered smoke cover accessibility; the other categories don't fit a single-profile generated catalog.

## Rejected Ideas

- **Third-party GitHub stats cards, visitor counters, typing SVGs, trophy widgets**: Rejected. Competitor evidence shows runtime fragility (rate limiting, Camo proxy breakage, service outages). The repo intentionally uses committed local SVGs. Source: github-readme-stats issue #4748; community complaints on Reddit/HN.
- **Generic profile-generator web UI**: Rejected. Existing tools (GPRM, ProfileMe.dev, readme.so) cover low-friction generation. SysAdminDoc's value is live catalog/feed/trust evidence, not template selection.
- **Full localization/i18n**: Rejected. English personal profile with no evidence of multilingual user demand. Source: cicirello/user-statistician i18n issues show limited adoption.
- **Multi-user admin UI or plugin marketplace**: Rejected. Single-maintainer deterministic profile, not a hosted SaaS.
- **Replace portfolio site with commercial builder**: Rejected. The separate `sysadmindoc.github.io` repo is already the richer public site.
- **Remove all release/download trust gaps from this repo**: Rejected for this planning pass. This repo should produce precise evidence and instructions; cross-repo release changes belong in those repos.
- **Full Scorecard 10/10**: Impractical for a solo maintainer. CII-Best-Practices requires external questionnaire enrollment; Code-Review requires independent reviewer model; Fuzzing is not applicable to a profile generator. Source: Scorecard alert classifications in `reports/profile-sync-report.json`.
- **Pester 6.0 migration**: Rejected. Pester 6 is alpha (6.0.0-alpha5, Oct 2024), not production-ready. Stay on 5.7.1.
- **CodeQL for this repo**: Not applicable. The repo is PowerShell-only; CodeQL doesn't support PowerShell. PSScriptAnalyzer, actionlint, zizmor, and Scorecard SARIF provide equivalent static analysis coverage.
- **Workflow keepalive action**: Under consideration but not recommended yet. GitHub disables scheduled workflows after 60 days of inactivity, but this repo has sufficient push activity to keep workflows active. Monitor for auto-disable if push frequency drops. Source: GitHub community discussions #57858, #184653.

## Sources

Project evidence:
- https://github.com/SysAdminDoc/SysAdminDoc/actions
- https://github.com/SysAdminDoc/sysadmindoc.github.io

Profile and portfolio:
- https://github.com/anuraghazra/github-readme-stats
- https://github.com/lowlighter/metrics
- https://github.com/cicirello/user-statistician
- https://github.com/rahuldkjain/github-profile-readme-generator
- https://github.com/abhisheknaiidu/awesome-github-profile-readme
- https://github.com/awesome-foss/awesome-sysadmin
- https://github.com/awesome-scripts/awesome-userscripts

Supply chain and workflow security:
- https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations
- https://github.blog/changelog/2025-10-28-immutable-releases-are-now-generally-available/
- https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/
- https://github.blog/news-insights/product-news/whats-coming-to-our-github-actions-2026-security-roadmap/
- https://github.blog/changelog/2026-06-18-control-who-and-what-triggers-github-actions-workflows/
- https://github.blog/changelog/2025-11-07-actions-pull_request_target-and-environment-branch-protections-changes/
- https://docs.zizmor.sh/audits/
- https://docs.zizmor.sh/configuration/
- https://github.com/zizmorcore/zizmor/releases
- https://github.com/rhysd/actionlint/releases
- https://github.com/boostsecurityio/poutine/releases
- https://github.com/step-security/harden-runner/releases
- https://github.com/ossf/scorecard
- https://github.com/actions/attest-build-provenance

PowerShell and CI tooling:
- https://www.powershellgallery.com/packages/Pester/5.7.1
- https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0
- https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle
- https://www.npmjs.com/package/markdownlint-cli2
- https://advisories.gitlab.com/npm/markdown-it/CVE-2026-48988/

Community signal:
- https://github.com/orgs/community/discussions/57858
- https://github.com/orgs/community/discussions/184653
- https://github.com/zizmorcore/zizmor/issues/612

## Open Questions

- Does the maintainer want to enable repository rulesets with a bypass-actor rule for direct-main pushes, or switch entirely to PR delivery before enabling any enforcement?
