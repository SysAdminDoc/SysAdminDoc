# Research - SysAdminDoc

## Executive Summary

SysAdminDoc is a generated GitHub profile README, public project feed, profile-asset renderer, and trust-evidence pipeline for 202 public repositories (Verified: `README.md`, `projects.json`, `reports/profile-sync-report.json`). Its strongest current shape is deterministic, privacy-aware portfolio generation: suppressed projects are redacted, README/feed/report schemas are validated, profile SVGs are committed locally, and release/download evidence is summarized without downloading binaries. Highest-value direction: keep the visible profile compact while making hosted automation evidence, workflow-trigger safety, branch/ruleset readiness, release-integrity reporting, and GitHub API resilience precise enough that the profile can be trusted without manual interpretation. Top opportunities: restore green hosted scheduled runs; remove or properly satisfy the Dependabot `pull_request_target` security exception; reconcile required-check/ruleset enforcement with the direct-main maintenance model; make report freshness post-commit-aware; upgrade release trust around GitHub asset digests, SBOMs, attestations, and immutable releases; record API rate-limit/fallback telemetry; prove generated-PR validation end to end; apply safe topic metadata fixes; and keep downstream portfolio compatibility guarded.

## Product Map

- Core workflows: edit `data/profile-catalog.json`, run `scripts/sync-profile.ps1 -Write -Check`, publish `README.md`, `projects.json`, `assets/profile/*.svg`, and `reports/profile-sync-report.json`.
- User personas: GitHub profile visitors, portfolio-site visitors, release/download users, userscript installers, public issue reporters, security reporters, and the maintainer operating generated PR workflows.
- Platforms and distribution: GitHub profile README, raw `projects.json`, GitHub Actions summaries/artifacts, committed SVG assets, Windows `setup.ps1`, raw userscript install URLs, and the separate `SysAdminDoc/sysadmindoc.github.io` portfolio consumer.
- Key integrations and data flows: GitHub GraphQL/REST repo metadata, release assets and digests, repository settings, scheduled workflow runs, OpenSSF Scorecard SARIF, Dependabot, JSON Schema, markdownlint, PSScriptAnalyzer, Pester, rendered Chrome smoke, and portfolio feed import.

## Competitive Landscape

- GitHub Profile README Generator / GPRM / ProfileMe.dev / readme.so: fast profile creation, social links, skill sections, widgets, and previews. Learn from preview speed and first-run ergonomics; avoid static copy-paste output because this repo's value is generated truth from catalog and GitHub metadata.
- `anuraghazra/github-readme-stats`: very high adoption and configurable stats cards, but current issues include public deployment pauses, broken cards, private contribution counting gaps, and SSRF/error-handling work. Learn from customization; avoid runtime third-party cards for the main profile.
- `lowlighter/metrics`: rich plugin model with 30+ plugins and many output formats. Learn from modular report sections and GitHub Actions generation; avoid sprawling plugin complexity because SysAdminDoc is a single-maintainer catalog, not a general metrics platform.
- `cicirello/user-statistician`: commits generated SVG stats through GitHub Actions and exposes localization requests. Learn from committed output and template-driven labels; reject full i18n for now because the current profile is an English personal catalog and no current user flow needs localization.
- `Platane/snk` and `DenverCoder1/readme-typing-svg`: popular profile visuals but open issues show generation/runtime failures and broken image links. Learn from theme-aware SVG output; avoid animation-heavy profile chrome and dynamic image dependencies.
- Awesome lists (`awesome-github-profile-readme`, `awesome-readme`, `awesome-sysadmin`, `awesome-userscripts`, developer portfolio lists): reward concise positioning, maturity, active maintenance, screenshots, and working links. SysAdminDoc should keep the "real tools with install/download paths" posture and only submit mature rows.
- GitHub/OpenSSF supply-chain tooling (`artifact attestations`, immutable releases, dependency review, Scorecard, Allstar, zizmor, poutine, actionlint, SLSA, SPDX, CycloneDX): directly aligns with the repo's evidence-first model. Continue adding platform-native evidence, but keep noisy scanners calibrated through report classifications and compact summaries.

## Security, Privacy, and Reliability

- Verified: latest local and push checks are green, but latest scheduled hosted runs for Profile sync (`27607877014`), Profile assets refresh (`27680916293`), and Workflow security (`27683950030`) are still failed; `gh run list` shows no newer successful scheduled/manual proof for those workflows.
- Verified: `main` has no branch protection and no rulesets (`gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection` returns 404; `gh api repos/SysAdminDoc/SysAdminDoc/rulesets` returns `[]`), while `reports/profile-sync-report.json.repositorySettings.requiredCheckReadiness` reports `needs-live-validation`.
- Verified: `workflow-security.yml` runs `zizmor --strict-collection --collect=workflows --collect=actions .github`; `.github/workflows/dependabot-auto-merge.yml` still uses `pull_request_target` with an inline suppression, and hosted evidence shows workflow-security failed on the scheduled run.
- Verified: `reports/profile-sync-report.json.evidenceFreshness.status` is `stale` after committing generated evidence because the committed report necessarily predates the report-affecting commit; the current gate needs a post-commit-aware interpretation.
- Verified: `releaseAssetDrift.platformDigestCoverage` reports 84 release rows with GitHub platform digests and 52 without; `executableDownloadTrustShortlist` still reports 55 checksum gaps, 65 attestation gaps, and 64 SBOM gaps because filename-derived sidecar evidence is mixed with platform digest evidence.
- Verified: `repositorySettings.security.secretScanningNonProviderPatterns` and `secretScanningValidityChecks` are disabled; treat them as policy/configuration work, not code-only defects.
- Verified: privacy guardrails are strong: `projects.json.suppressed` redacts suppressed identifiers, `portfolioCompatibility.suppressedIdentifierLeakCount` is zero, and issue forms warn against private repo names, medical data, secrets, and employer-specific details.

## Architecture Assessment

- `scripts/sync-profile.ps1` remains the correct orchestration boundary, but at 400K+ bytes it should continue gaining small, tested helper boundaries rather than new standalone scripts for every report section.
- The GitHub metadata strategy is now directionally correct: exclude expensive `latestRelease` from bulk GraphQL and enrich releases through bounded REST calls. Next improvement is telemetry: record rate-limit headroom, retry counts, fallback reasons, and partial-provider status.
- `Get-LatestReportAffectingCommit` / evidence freshness should distinguish "report generated before the commit that contains it" from genuinely stale reports, or the report will keep warning immediately after a valid generated-evidence commit.
- `New-ReleaseTrust`, release drift reporting, and summary output need clearer types for platform digest, checksum sidecar, complete checksum coverage, SBOM, attestation, and immutable release evidence.
- Required-check readiness has strong local report structure but lacks live enforcement: no branch protection/rulesets are configured, and generated PR evidence fields remain mostly null.
- Downstream feed compatibility is currently guarded inside this repo; add a small contract fixture aligned to `sysadmindoc.github.io` importer expectations so feed changes do not silently break the portfolio site.
- Accessibility and responsive risk are currently covered by committed SVG accessibility checks and rendered GitHub profile smoke; no separate accessibility roadmap item is warranted until those gates surface a failure.
- Excluded categories: no mobile app, offline-first product mode, multi-user workflow, plugin marketplace, or full i18n is recommended. Plugin/i18n/multi-user features do not fit this single-profile generated catalog.

## Rejected Ideas

- Add third-party GitHub stats cards, visitor counters, typing SVGs, trophy widgets, or contribution games: rejected because competitor and issue evidence shows runtime fragility and the current repo intentionally uses committed local SVGs.
- Build a generic profile-generator web UI: rejected because existing tools already cover low-friction generation, while SysAdminDoc's differentiator is live catalog/feed/trust evidence.
- Full localization/i18n: rejected despite competitor requests because SysAdminDoc is an English personal profile/catalog and localization would add maintenance cost without evidence of user value.
- Multi-user admin UI or plugin marketplace: rejected because the repo is a deterministic single-maintainer profile and public feed, not a hosted SaaS.
- Replace `sysadmindoc.github.io` with a commercial portfolio builder: rejected because the separate portfolio repo is already the richer public site and this repo should remain the source of truth.
- Remove all release/download trust gaps by editing sibling repos from this repo: rejected for this planning pass; this repo should first produce precise evidence and reusable instructions before cross-repo release changes.

## Sources

Project evidence:

- https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27790661568
- https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27607877014
- https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27680916293
- https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27683950030
- https://github.com/SysAdminDoc/sysadmindoc.github.io

Profile and portfolio:

- https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
- https://github.com/rahuldkjain/github-profile-readme-generator
- https://www.profileme.dev/
- https://github.com/anuraghazra/github-readme-stats
- https://github.com/lowlighter/metrics
- https://github.com/cicirello/user-statistician
- https://github.com/Platane/snk
- https://github.com/DenverCoder1/readme-typing-svg
- https://github.com/abhisheknaiidu/awesome-github-profile-readme
- https://github.com/matiassingers/awesome-readme
- https://github.com/awesome-foss/awesome-sysadmin
- https://github.com/awesome-scripts/awesome-userscripts
- https://github.com/emmabostian/developer-portfolios

Supply chain, workflow security, and standards:

- https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
- https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases
- https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/
- https://github.blog/changelog/2025-10-28-immutable-releases-are-now-generally-available/
- https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api
- https://github.blog/changelog/2025-09-01-graphql-api-resource-limits/
- https://github.com/actions/dependency-review-action
- https://github.com/zizmorcore/zizmor
- https://github.com/boostsecurityio/poutine
- https://github.com/rhysd/actionlint
- https://github.com/ossf/scorecard
- https://github.com/ossf/allstar

## Open Questions

- Does the maintainer want direct pushes to `main` to remain possible after branch protection/rulesets are enabled, or should all future maintenance go through PR delivery?
