# Research - SysAdminDoc
Date: 2026-08-20 - replaces all prior research.

## Executive Summary
Verified: SysAdminDoc is a deterministic GitHub profile README, public catalog, and `projects.json` feed generator with a local-only PowerShell validation pipeline (`scripts/sync-profile.ps1`, 12,981 lines, 295 functions, 82% line coverage). The 2026-07 research plan is fully drained: stable feed IDs, drift diagnostics, probe caching, opt-in release verification, Backstage export, branch-tip provenance, and support bundles all shipped. The repo's biggest problem today is not missing features, it is staleness of its own published surfaces: the public feed has a frozen 2026-06-01 timestamp, the latest GitHub release (v4.9.153) is 8 versions behind local v4.9.161, seven catalog repos went private and still render as dead README links, one repo was renamed, 15 newer public repos are missing from the catalog, and the README's "AI service overview" link returns a live 404. The highest-value direction: reconcile the catalog and links with live GitHub state, republish the feed and release so the downstream portfolio rebuilds with current data, patch the toolchain (PowerShell 7.6.5 fixes CVE-2026-50523), and retire the remaining CI-era dead weight that keeps the sync report over its own size budget.

Top opportunities in priority order:
1. Fix the dead `sysadmindoc.github.io/ai/` link (live 404) and route portfolio links to the canonical `portfolio.getparkerai.com` origin.
2. Reconcile the catalog: 7 private-visibility violations, 1 rename (TsunamiSimulator is now Cataclysm), 15 missing public repos, 1 missing fork attribution (winget-pkgs).
3. Root-cause the frozen feed `generatedAt` (copied from the catalog stamp at `scripts/sync-profile.ps1:4897`, which nothing refreshes), then regenerate and publish so the feed-backed portfolio stops building from 11-week-old data.
4. Security patch lane: PowerShell 7.6.5 (CVE-2026-50523 affects the observed 7.6.3), gh CLI 2.97.0 (four advisories including an `attestation verify` matcher bypass), Node 24.18.1, zizmor 1.29.0 (skip 1.27.0, credential-logging defect).
5. Immutable releases are GA and free for personal repos (verified 2026-08-20 via the live API); the prior "plan-gated" blocker is obsolete and the item can be unblocked.
6. Pin `X-GitHub-Api-Version` and audit for the 2026-03-10 breaking REST calendar version (removes `rate`, `has_downloads`, `assignee`).
7. Retire CI-relic scripts and report stubs; that alone clears the report's own over-budget warning.
8. Root-fix the 20 mobile table overflows (5-column tables at 390px) so the blocked overflow gate can eventually promote to fatal.

## Product Map
- Core workflows: generate `README.md`, `projects.json`, and profile assets from `data/profile-catalog.json`; validate with `scripts/validate-local.ps1` (Pester 5.8.0 lane, opt-in 6.0.1 lane, PSScriptAnalyzer, markdownlint, dependency review); check with `scripts/sync-profile.ps1 -Check` (plus `-ProbePortfolio`, `-BackstageExportPath`, opt-in release verification); smoke the rendered profile with `scripts/render-profile-smoke.ps1`.
- User personas: the profile owner; public visitors routing to tools; the feed-backed portfolio at portfolio.getparkerai.com (Astro 7, builds from raw `projects.json`); prospective AI-consulting clients arriving through the header services block; future coding agents.
- Platforms and distribution: GitHub profile README; raw JSON feed plus JSON Schema contracts; Windows PowerShell 7.4+ generator with a 5.1-only `setup.ps1` bootstrap; no hosted CI by policy (local-only posture since 2026-08-12).
- Key integrations: GitHub CLI GraphQL/REST (repo list, latest releases with `immutable` and per-asset `digest` fields, contribution calendar), bounded link probes with a 24h cache under `.cache/profile-sync`, portfolio cross-surface probe (warning-only).

## Competitive Landscape
- anuraghazra/github-readme-stats: formally deprecated itself on 2026-06-30, pointing users at github-stats-extended. The largest third-party render host telling users to leave is direct external validation of this repo's committed-asset, no-render-host posture. Nothing to adopt.
- stats-organization/github-stats-extended: the blessed successor, still a hosted/self-hosted dynamic-image model. Community members are spinning up personal Vercel mirrors of it (multiple "self-hosted mirror for my profile" repos created Jul-Aug 2026). Learn: the market is converging on "don't trust the shared host"; committed static output remains the endpoint of that trend. Avoid: runtime infrastructure of any kind.
- lowlighter/metrics: semi-dormant (stable v3.34, beta unreleased). No longer a feature source.
- Anti-badge editorial wave (ReadmeDesign 2026-07-12, dev.to and codeboards 2026 guides): senior-dev consensus is one screen, one deliberate CTA, 3-5 pinned repos, 30-second scannability, no badge walls. The current minimal text-first header matches; the 695-line catalog body is the tension point, and the existing portfolio-only demotion lever in `readmeDensity` is the correct relief valve.
- Consultant-profile guidance (devbio.me 2026-06-08): one outbound CTA, a personal domain, one concrete outcome metric beats prose. The current header has two side-by-side service links and no metric; a small tune-up applies.
- awesome lists (verified active 2026-08): awesome-foss/awesome-sysadmin now takes YAML PRs to awesome-foss/awesome-sysadmin-data and prunes inactive software; awesome-scripts/awesome-userscripts merged 4 PRs in the last 3 weeks; abhisheknaiidu/awesome-github-profile-readme batch-merges every few months. Submission remains owner-gated (third-party PRs) and stays in Roadmap_Blocked, with the new data-repo mechanics noted.
- Backstage: no descriptor-format changes in 2026, and no adoption of catalog-info as an interchange format outside Backstage installs. The existing opt-in export is the right ceiling; do not invest further.
- Pagefind v1.5.2 (2026-04): deterministic index filenames and ~45% smaller chunks. That benefit lands in the separate portfolio repo, not here.
- llms.txt: 2026 state is broad publishing (GitHub Docs ships one), near-zero crawler consumption, real consumption only by IDE/agent tooling. A portfolio-side llms.txt referencing `projects.json` is cheap signaling; no README-side action.

## Security, Privacy, and Reliability
- Verified toolchain exposure: the machine runs pwsh 7.6.3; CVE-2026-50523 (command injection, high) affects 7.6.0-7.6.4 and is fixed in 7.6.5 (released 2026-08-14). CVE-2026-26143 concerns `Import-PowerShellDataFile -SkipLimitCheck`; the generator should be audited for that flag.
- Verified gh CLI advisories fixed in 2.97.0: terminal escape injection, URL path escaping, `gh auth status` token disclosure, and GHSA-mm27-mwq9-fr5g (`gh attestation verify` regex-metacharacter bypass of signer matchers). The opt-in release verification lane and any future attestation checks should require gh >= 2.97.0.
- Verified zizmor: 1.27.0 could log GitHub credentials (GHSA-f42p-wjw5-97qh); pinned 1.26.1 is unaffected; bump directly to 1.29.0. Node 24.18.1 is the July 2026 security release.
- Verified live Dependabot alert on this repo (2026-08-20, high): js-yaml >= 5.0.0 and <= 5.2.1 has exponential parsing time in flow collections (GHSA-pm4m-ph32-ghv5, DoS), fixed in 5.2.2. The package.json override pins exactly 5.2.1, so the toolchain-pin refresh is remediating a live advisory, not just currency drift.
- Verified live-surface breakage: `https://sysadmindoc.github.io/ai/` returns 404 (the old Pages site became a redirect stub without an /ai/ path), and the README's hand-authored header links to it. The "Full portfolio" link points at the redirect stub instead of the canonical `portfolio.getparkerai.com`.
- Verified feed staleness: published `projects.json` `generatedAt` is 2026-06-01 because `New-ProjectsExportJson` copies `$Catalog.generatedAt` (`scripts/sync-profile.ps1:4897`) and only the lossy seed path restamps the catalog. The portfolio builds from this feed, so its metadata is frozen at June 1. This is the one drift class the drift-hardening work never fixed.
- Verified report warnings (reports/profile-sync-report.json, itself generated 2026-08-12): report over its own byte budget (116,051 vs 114,688 soft limit); 20 mobile table overflows (both mobile themes, 5-column Tool Catalog tables, Start Here, and two others at 390px); 2 unreachable branch-tip rows; release consistency 2 warnings (published v4.9.153 vs local v4.9.161); 7 `privateVisibilityViolations` still cataloged and linked; `renamedRepoRedirects` TsunamiSimulator to Cataclysm; 15 `missingPublicRepos`; 8 license-missing rows that are all knock-ons of the private-visibility set; link validation ran with targetCount 0 (skipped), which is why the dead links went uncaught.
- Verified policy contradiction: `repositorySettings.security.dependabotSecurityPosture.status` is "enabled" and the repo's working notes say to keep it enabled, while the owner's global rules require Dependabot alerts/updates disabled everywhere. Needs a deliberate resolution in one direction; the local dependency-review lane is the compensating control if disabled.
- Verified platform shifts: immutable releases GA 2025-10-28 with per-asset Sigstore attestations, no plan gate, per-repo settings toggle (no user-account-wide toggle); REST calendar version 2026-03-10 removes `rate` from `/rate_limit`, `has_downloads`, `assignee`, and attestation `bundle` from list responses (2022-11-28 supported at least 24 months from 2026-03-12; unversioned requests keep old behavior); GraphQL per-query resource limits (2025-09-01) can partial-fail large queries; branch-protection-to-rulesets migration is now one click with per-rule exemptions and user bypass.
- Privacy guardrails hold: suppressed rows stay redacted in feed and report; preserve that in every new field.

## Architecture Assessment
- `scripts/sync-profile.ps1` remains a 12,981-line monolith with good seams (295 functions, ~40 `Test-*` report sections). Continue adding report fields near existing functions; a split is still not justified by defect data.
- CI-era relics to retire: `Get-GeneratedPr*` and routine-PR-drill stubs (`scripts/sync-profile.ps1:12713` keeps a "minimal stub" for `generatedPrWriteEvidence`), `scripts/open-generated-profile-pr.ps1`, `scripts/set-generated-validation-status.ps1`, CI-summary paths in `scripts/write-profile-sync-summary.ps1` (93.7 KB), and `.github/zizmor.yml` (no workflows left to scan; evaluate whether the zizmor lane itself still earns its pin). Trimming relic report fields is also the root fix for the report byte-budget warning.
- Stale local evidence misleads future sessions: `reports/profile-sync-summary.local.md` still describes "Cycle 133" and the deleted workflow apparatus (2026-06-07); `testResults.xml` (2026-06-11, 182 tests vs 301 current It blocks) and `coverage.xml` (2026-07-08) lag the suite. All are gitignored, so this is hygiene, not exposure.
- Test suite: 64 Describes, 301 Its, 82.2% line coverage of the generator. Gaps: fixtures for the frozen-generatedAt case, link-validation-skipped case, REST 2026-03-10 field removals, and partial GraphQL responses.
- `Roadmap_Blocked.md` needs reconciliation: five rows reference hosted workflows deleted on 2026-08-12 (scheduled-run evidence, profile-sync.yml, workflow_dispatch drills, CI-run-gated overflow promotion, Actions dependency locking), one cites an absent `TODO.md`, the "Future Platform State" heading is duplicated, and the immutable-releases blocker text is obsolete.
- Docs drift: `setup.ps1` installs `Python.Python.3.12` while the owner standard is 3.13; the README validation table advertises 3.12 accordingly.

## Rejected Ideas
- Reintroduce hosted render hosts, stats cards, or a self-hosted stats mirror. Source: github-readme-stats deprecation notice 2026-06-30; github-stats-extended mirror wave. Reason: the ecosystem is proving the failure mode; committed assets already win.
- Restore GitHub Actions for builds, attestation of `projects.json`, or scheduled refresh. Source: local-only posture decision 2026-08-12 and the owner's global no-CI rule. Reason: policy; local scheduled tasks cover freshness.
- GitHub-Actions-based artifact attestations for tool releases. Source: docs.github.com artifact-attestations. Reason: requires hosted builds, which the local-build policy forbids; platform digests plus optional local signing cover the trust story.
- Expand the Backstage export or emit catalog-info.yaml files per repo. Source: Northflank/Encore 2026 "Backstage alternatives" coverage showing no interchange adoption. Reason: no consumer exists.
- README-side llms.txt or JSON-LD. Source: llms.txt adoption studies (Presenc, aeo.press 2026). Reason: those work at domain roots and HTML pages; they belong to the portfolio repo if anywhere.
- Full-README translation, visitor analytics, email capture, monetization widgets. Source: prior research 2026-07-07, unchanged. Reason: unchanged.
- Default-download binary verification for all releases. Source: existing opt-in verifier shipped 2026-07-15. Reason: the opt-in design already balances cost; nothing new argues for default-on.
- ecosyste.ms metadata enrichment of the feed. Source: repos.ecosyste.ms API. Reason: adds an external dependency for dependents-count data no current consumer requests; revisit only if the portfolio wants it.

Cross-repo opportunities recorded for other repos (not this roadmap): winget manifests for flagship EXE tools (microsoft/winget-pkgs, ~12,850 packages, `wingetcreate` automates submission); Azure Trusted Signing at $9.99/month for local EXE signing (EV no longer bypasses SmartScreen reputation); SHA256SUMS.txt plus digest lines in release notes (GitHub already auto-digests assets); portfolio-side llms.txt, JSON-LD SoftwareApplication on catalog pages, and Pagefind 1.5.2; Greasy Fork mirrors for userscripts with raw-GitHub @updateURL; Tampermonkey-plus-developer-mode install notes post-MV2; getparkerai.com "Selected work" link still routes through the sysadmindoc.github.io redirect stub.

## Sources
Platform and APIs:
- https://github.blog/changelog/2025-10-28-immutable-releases-are-now-generally-available/
- https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes
- https://github.blog/changelog/2026-03-12-rest-api-version-2026-03-10-is-now-available/
- https://docs.github.com/en/rest/about-the-rest-api/breaking-changes?apiVersion=2026-03-10
- https://github.blog/changelog/2025-09-01-graphql-api-resource-limits/
- https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/
- https://github.blog/changelog/2026-08-11-automatically-migrate-branch-protection-rules-to-repository-rulesets/
- https://github.blog/changelog/2026-04-21-deprecation-of-security-related-organization-api-fields/

Toolchain and advisories:
- https://devblogs.microsoft.com/powershell/announcing-powershell-7-6/
- https://github.com/PowerShell/Announcements/issues/82
- https://docs.zizmor.sh/release-notes/
- https://nodejs.org/en/blog/vulnerability/july-2026-security-releases
- gh CLI 2.97.0 release notes (GHSA-3m3g-3wcr-px46, GHSA-4fjg-2h4q-fwg3, GHSA-cg6r-mpgc-h9mm, GHSA-mm27-mwq9-fr5g)
- https://pester.dev/ (5.9.1, 6.1.0 releases 2026-08-11)
- https://github.com/DavidAnson/markdownlint-cli2 (0.23.2)

Ecosystem:
- https://github.com/anuraghazra/github-readme-stats (deprecation commit 2026-06-30)
- https://github.com/stats-organization/github-stats-extended
- https://github.com/lowlighter/metrics
- https://readmedesign.com/blog/anti-badge-backlash-github-profile
- https://devbio.me/blogs/github-profile-readme-guide
- https://github.com/awesome-foss/awesome-sysadmin-data/blob/master/CONTRIBUTING.md
- https://github.com/awesome-scripts/awesome-userscripts/blob/master/CONTRIBUTING.md
- https://github.com/abhisheknaiidu/awesome-github-profile-readme
- https://github.com/Pagefind/pagefind/releases
- https://presenc.ai/research/state-of-llms-txt-2026
- https://docs.github.com/llms.txt

Trust and distribution:
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
- https://github.com/microsoft/winget-pkgs
- https://github.com/microsoft/winget-create
- https://greasyfork.org/en/help/code-rules
- https://learn.microsoft.com/en-us/windows/package-manager/winget/
- https://slsa.dev/blog/2025/11/slsa-v1.2-rc2
- https://docs.sigstore.dev/about/bundle/

Live surfaces (fetched 2026-08-20): github.com/SysAdminDoc, sysadmindoc.github.io (redirect stub), sysadmindoc.github.io/ai/ (404), getparkerai.com, portfolio.getparkerai.com, raw projects.json, SysAdminDoc/SysAdminDoc releases (latest v4.9.153).

## Open Questions
None. The Dependabot-setting contradiction and the fleet-wide immutable-release rollout are decisions the roadmap items surface explicitly, but both have a default direction (global rules win; enable on this repo first) and do not block prioritization.
