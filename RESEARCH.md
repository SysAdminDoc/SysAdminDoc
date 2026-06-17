# Research — SysAdminDoc

## Executive Summary

SysAdminDoc is a generated GitHub profile README, public project feed, and trust-evidence pipeline for 200 public repositories, centered on `data/profile-catalog.json`, `scripts/sync-profile.ps1`, `README.md`, `projects.json`, generated profile SVGs, and `reports/profile-sync-report.json` (Verified: repo files). Its strongest current shape is not visual flash; it is deterministic portfolio generation with privacy-aware suppressed rows, schema-checked feed contracts, release/download trust metadata, and unusually strong CI for a profile repository. Highest-value direction: restore live automation health, make report evidence more precise, and keep the visible profile minimal while hardening the feed/download trust surface. Top opportunities: fix current scheduled workflow failures; refresh generated metadata drift; remove or tightly contain the Dependabot `pull_request_target` auto-merge trigger; align dependency-review license policy with the catalog's actual OSS licenses; resolve the remaining unknown project license; clarify checksum coverage semantics; clear root Markdown hygiene warnings; continue already-roadmapped poutine, digest, immutable-release, and attestation work; avoid third-party dynamic profile widgets that reduce reliability and professional tone.

## Product Map

- Core workflows: edit `data/profile-catalog.json`, run `scripts/sync-profile.ps1 -Write`, validate with `-Check`, publish `README.md`, `projects.json`, `assets/profile/*.svg`, and `reports/profile-sync-report.json`.
- Core workflows: consume GitHub REST/GraphQL metadata, release assets, userscript headers, repository settings, Actions runs, Scorecard evidence, Dependabot, schemas, link probes, and rendered-profile smoke output.
- User personas: GitHub profile visitors, portfolio-site visitors, downstream feed consumers, release/download users, userscript installers, public issue reporters, security reporters, and the maintainer operating generated PRs.
- Platforms and distribution: GitHub profile README, raw `projects.json`, GitHub Actions summaries/artifacts, generated SVG assets, Windows `setup.ps1`, branch-hosted raw `.user.js` install URLs, and the separate `SysAdminDoc/sysadmindoc.github.io` portfolio importer.
- Key integrations and data flows: `projects.json` is consumed by `sysadmindoc.github.io/scripts/lib/profile-feed.mjs`, which requires `repo`, `title`, `category`, `description`, and `repoUrl`, filters `includeInPortfolio === false` and `suppressed === true`, and rejects duplicate visible repos.

## Competitive Landscape

- **GitHub profile README and profile-generator tools**: GitHub's profile README feature, `rahuldkjain/github-profile-readme-generator`, GPRM, ProfileMe.dev, and readme.so do fast creation, live preview, social links, stats cards, skill badges, and blog widgets well. SysAdminDoc should learn from concise first-run structure and previewability; avoid their copy-paste/static-template bias because this repo's value is generated truth from live catalog data.
- **Dynamic stats/card projects**: `anuraghazra/github-readme-stats`, `lowlighter/metrics`, `cicirello/user-statistician`, `Platane/snk`, and `DenverCoder1/readme-typing-svg` make profiles visually rich and frequently updated. SysAdminDoc should learn from light/dark SVG support, cache-aware generation, and action-driven refreshes; avoid third-party runtime images, vanity counters, typing animations, and contribution-game widgets because current local evidence already favors reliability, accessibility, and trust metadata.
- **Awesome lists and portfolio directories**: `abhisheknaiidu/awesome-github-profile-readme`, `matiassingers/awesome-readme`, `awesome-foss/awesome-sysadmin`, `awesome-scripts/awesome-userscripts`, and `emmabostian/developer-portfolios` reward clear positioning, active maintenance, quality READMEs, and working links. SysAdminDoc should keep the "catalog of real tools" positioning and submit only projects that satisfy list criteria; avoid mass-submission or low-signal rows.
- **Commercial and hosted profile products**: CodersRank aggregates GitHub, GitLab, StackOverflow, LinkedIn, APIs, and widgets into a developer profile. SysAdminDoc should learn from cross-surface aggregation and visitor-first project proof; avoid introducing accounts, paywalled dependencies, or multi-user product scope that contradicts this single-maintainer generated profile.
- **GitHub and OpenSSF supply-chain tooling**: Artifact Attestations, immutable releases, dependency review, Scorecard, Allstar, zizmor, poutine, actionlint, SLSA, SPDX, and CycloneDX align with this repo's evidence-first model. SysAdminDoc should continue platform-native provenance and workflow scanning; avoid adding scanners as noisy gates without warning-only calibration and compact report summaries.
- **Downstream portfolio site**: `SysAdminDoc/sysadmindoc.github.io` is not a competitor but is the main consumer. Its importer currently validates only a small required field set, so SysAdminDoc should preserve additive schema evolution and compact compatibility reporting; avoid breaking visible feed fields or leaking suppressed identifiers.

## Security, Privacy, and Reliability

- Verified: Workflow security scheduled run `27683950030` failed on June 17, 2026 because `zizmor --strict-collection` raised unsuppressed `dangerous-triggers` on `.github/workflows/dependabot-auto-merge.yml:3` for `pull_request_target`.
- Verified: Profile assets refresh run `27680916293` failed on June 17, 2026 after `scripts/sync-profile.ps1 -Write -Check`; the summary reported artifact-budget, stale report/smoke, scheduled workflow, unresolved license, fork-parent, userscript, repository-setting, required-check, and community-health warnings.
- Verified: Profile sync run `27607877014` failed on June 16, 2026 with 16 fatal metadata drift rows, including top-level `publicRepoCount`/`repoEnumeration.returnedCount`, `provenance.generatorSha256`, `HEICShift` release fields, and `Network_Security_Auditor` latest release fields.
- Verified: live repository settings currently report no branch protection and no repository rulesets, while `reports/profile-sync-report.json` still contains older required-check proof evidence. The report should continue distinguishing historical proof from current enforcement.
- Verified: `.github/workflows/tests.yml` blocks `GPL-2.0`, `GPL-3.0`, `AGPL-3.0`, `LGPL-2.1`, and `LGPL-3.0` through dependency-review `deny-licenses`, while the catalog/feed already include AGPL, GPL, and LGPL project licenses. GitHub documents `deny-licenses` as deprecated for possible removal in the next major dependency-review-action release.
- Verified: `projectLicenseMetadata` detects all 169 README-visible project licenses but still has `unresolvedUnknownCount: 1` for `HostShield` (`NOASSERTION`/Other), plus two intentional exceptions.
- Verified: `releaseAssetDrift` reports 65 executable download rows, 55 checksum gaps, 65 attestation gaps, and 64 SBOM gaps; some rows have `trustLevel: "checksum"` while shortlist `hasChecksum` is false, so the report needs clearer "checksum asset present" versus "complete executable checksum coverage" wording.
- Verified: `rootMarkdownHygiene.status` is `unexpected-files` because local ignored root files `LOGO_PROMPTS.md`, `RESEARCH_FEATURE_PLAN.md`, and `TODO.md` remain outside the repo's documented root Markdown contract.
- Privacy guardrails are strong: `projects.json` redacts suppressed rows, `portfolioCompatibility.suppressedIdentifierLeakCount` is zero, and public-safe issue forms avoid private project leakage.

## Architecture Assessment

- `scripts/sync-profile.ps1` is large but still the correct orchestration boundary for catalog loading, metadata collection, README/feed generation, report sections, schema checks, and write/check behavior. New evidence should land as compact report fields and focused helper functions rather than standalone scripts.
- Refactor candidate: `.github/workflows/dependabot-auto-merge.yml` should stop using `pull_request_target` where possible, or prove that it only checks Dependabot identity, checks out trusted base code, grants minimal permissions, and never executes untrusted PR content.
- Refactor candidate: metadata drift handling should separate transient GitHub GraphQL/REST availability and repo enumeration changes from true catalog/feed drift, so scheduled `-Check` failures are actionable and not just "regenerate everything" noise.
- Refactor candidate: `New-ReleaseTrust`, `Test-ReleaseAssetDrift`, and summary rendering should distinguish any checksum asset, complete checksum coverage, platform digest availability, SBOM presence, and attestation presence.
- Test gap: dependency-review policy has no local guard that explains why license failures are vulnerability-policy failures rather than catalog/license-disclosure facts.
- Test gap: root Markdown hygiene is warning-only and currently dirty in the local working directory; a cleanup or exemption policy should be explicit so repeated research passes do not keep rediscovering the same leftovers.
- Documentation gap: community health is 71% because GitHub does not detect contributing guidelines or a code of conduct. Root docs should not be added casually; either use `.github/` docs if allowed or mark the omission intentional in the report.
- Excluded categories: no mobile app, offline mode, multi-user workflow, plugin ecosystem, or i18n surface is justified for this repo. Mobile risk is limited to rendered GitHub profile viewport checks already covered by existing smoke-roadmap work.

## Rejected Ideas

- Add third-party GitHub stats cards, visitor counters, typing SVGs, contribution games, or trophy widgets: rejected because competitor/community evidence shows popularity but also runtime fragility, visual clutter, and weaker trust than the current generated catalog.
- Migrate userscript install URLs from branch raw URLs to tag/release URLs now: rejected because `docs/decisions/2026-06-07-userscript-install-posture.md` correctly requires repeatable source-repo release metadata automation first.
- Add a multi-user admin UI, CMS, or plugin marketplace: rejected because the repo is a deterministic single-profile generator and downstream portfolio feed, not a general SaaS product.
- Add root `CONTRIBUTING.md` or `CODE_OF_CONDUCT.md` immediately: rejected because the root Markdown contract and current hygiene report would make extra root docs a regression; use `.github/` placement or report disposition if needed.
- Replace the existing generated README with a commercial portfolio builder output: rejected because `SysAdminDoc/sysadmindoc.github.io` already provides the richer hosted portfolio while this repo must remain the GitHub-profile/feed source of truth.
- Re-list poutine, release digests, immutable releases, `projects.json` attestations, secret-scanning validity checks, or mobile rendered-smoke overflow gates as new roadmap work: rejected because `ROADMAP.md` already contains those incomplete items.
- Full localization/i18n: rejected because this is an English personal GitHub profile/catalog; no source or comparable project showed high-value localized profile README workflows.

## Sources

Project evidence:

- https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27683950030
- https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27680916293
- https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27607877014
- https://github.com/SysAdminDoc/sysadmindoc.github.io

Profile and portfolio:

- https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
- https://github.com/rahuldkjain/github-profile-readme-generator
- https://github.com/anuraghazra/github-readme-stats
- https://github.com/lowlighter/metrics
- https://github.com/cicirello/user-statistician
- https://github.com/abhisheknaiidu/awesome-github-profile-readme
- https://github.com/matiassingers/awesome-readme
- https://readme.so/editor
- https://www.profileme.dev/
- https://codersrank.io/

Supply chain and workflow security:

- https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations
- https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
- https://github.com/actions/dependency-review-action
- https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/customize-dependency-review-action
- https://github.com/zizmorcore/zizmor
- https://github.com/boostsecurityio/poutine
- https://github.com/rhysd/actionlint
- https://github.com/ossf/scorecard
- https://github.com/ossf/allstar
- https://arxiv.org/html/2601.14455v2

Standards:

- https://json-schema.org/draft/2020-12
- https://spdx.dev/use/specifications/
- https://cyclonedx.org/specification/overview/
- https://github.com/slsa-framework/slsa-github-generator

## Open Questions

- None.
