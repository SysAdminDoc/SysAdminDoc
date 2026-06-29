# Research - SysAdminDoc

## Executive Summary

SysAdminDoc is a generated GitHub profile README and public project catalog: `data/profile-catalog.json` drives `scripts/sync-profile.ps1`, which emits `README.md`, `projects.json`, profile SVG assets, schemas, and `reports/profile-sync-report.json`. Its strongest current shape is a deterministic, privacy-aware, local-first portfolio/feed generator that avoids fragile hosted metrics while preserving structured project, release, and redaction evidence. Highest-value direction: make the local report trustworthy again after the no-workflow policy shift, then tighten catalog drift, rendered-profile evidence, public intake copy, and manual dependency review. Priority opportunities: reconcile live public repo drift; regenerate stale projects/assets after generator provenance changes; make rendered smoke evidence local instead of hosted-artifact-dependent; remove stale workflow/Dependabot public intake references; preserve release-trust evidence without implying binary verification; keep downstream portfolio/search metadata stable; add an explicit manual advisory-review lane; and continue rejecting live profile-card widgets that conflict with the repo's reliability and privacy posture.

## Product Map

- Core workflows: maintain the catalog, run local validation, render the profile README, export `projects.json`, generate profile SVGs, and inspect report evidence.
- User personas: GitHub profile visitors, portfolio-site visitors, users choosing install/download links, security reporters, public correction reporters, and the maintainer curating 200+ repos.
- Platforms and distribution: GitHub profile README, raw JSON feed, committed SVG assets, JSON schemas, issue templates, Windows `setup.ps1`, and the separate static portfolio consumer.
- Key integrations and data flows: GitHub repository/release metadata, catalog schema validation, Pester, PSScriptAnalyzer, markdownlint-cli2, release asset metadata, redacted suppression rows, and portfolio feed import.

## Competitive Landscape

- github-readme-stats and github-readme-streak-stats: strong drop-in dynamic cards, themes, and social proof; learn from simple configuration and clear fallback copy; avoid external image hosts/rate-limit fragility because open issues show broken public deployments, rate-limit/self-hosting pressure, and private-contribution ambiguity.
- lowlighter/metrics: strong plugin breadth, many output formats, and option-level configurability; learn from modular report sections; avoid a broad plugin framework because this repo is a curated single-maintainer catalog, not a general metrics product.
- cicirello/user-statistician: strong committed-artifact model for profile visuals; learn from static generated assets; avoid scheduled Action dependence under the repo's current local-only build policy.
- GitHub profile README generators: strong first-run onboarding and preview UX; learn from approachable setup and mobile-preview concerns; avoid template-builder scope because SysAdminDoc's value is catalog accuracy, feed data, and trust metadata.
- Awesome GitHub Profile README / awesome-sysadmin / awesome-userscripts: reward concise categories, working links, recognizable project purpose, and examples; keep the compact routing table and public-safe catalog instead of decorative personal chrome.
- Linktree, Bento, Carrd, ReadMe, and GitBook: emphasize curated link surfaces, analytics/search, changelogs, feedback, and stale-content management; learn from curation and health signals; avoid hosted CMS migration because the profile/feed belongs in the repo.
- Pagefind and Docusaurus search: strong static-search patterns without hosted infrastructure; this repo should export stable category/search/filter metadata while the portfolio site owns the rendered search UI.

## Security, Privacy, and Reliability

- Verified: `reports/profile-sync-report.json` currently reports `projectsExportInSync: false`, `profileAssetsInSync: false`, `metadataDriftSummary.fatalCount: 1`, `metadataDriftSummary.informationalCount: 26`, stale generated metadata, `evidenceFreshness.status: "stale"`, and `renderedProfileSmoke.status: "not-run"`.
- Verified: live public repo drift exists: `missingPublicRepos` lists `ClearCut`, `OpenNetLimit`, `GIFM`, and `AsteroidSimulator`; `renamedRepoRedirects` still maps `NovaCut` to `https://github.com/SysAdminDoc/ClearCut`.
- Verified: the catalog shape is substantial and worth guarding: `data/profile-catalog.json` has 205 entries, 172 README-visible rows, 183 portfolio rows, 23 suppressed rows, and categories for Android, desktop, extensions, guides, media, PowerShell, Python, security, web, misc, and suppressed entries.
- Verified: root Markdown hygiene is clean and privacy posture is strong: ignored planning docs stay local via `.gitignore`, `AGENTS.md` restricts root Markdown creation, suppressed project rows remain redacted, and issue templates warn against credentials, private names, medical data, and sensitive logs.
- Verified: accessibility guardrails are already useful: `reports/profile-sync-report.json` shows `profileAssetsAccessibility.status: "ok"` across 12 SVG assets with zero contrast failures, so future profile visual work should preserve that report gate.
- Verified: stale hosted-automation assumptions remain outside the existing roadmap's core code path: `.github/ISSUE_TEMPLATE/workflow-ci.yml`, `.github/zizmor.yml`, `requirements-ci.txt`, `scripts/open-generated-profile-pr.ps1`, `scripts/write-profile-sync-summary.ps1`, and `schemas/profile-sync-report.v1.json` still reference workflow/Dependabot/Scorecard-era concepts.
- Verified: `npm audit --json` reports zero Node vulnerabilities, `markdownlint-cli2` is at registry latest `0.22.1`, and local PowerShell modules show Pester `5.7.1` and PSScriptAnalyzer `1.25.0`; however `package.json` manually overrides `js-yaml` to `4.2.0` while the registry latest is newer, so manual update review needs a documented lane.
- Likely: release-trust metadata should remain evidence-only. GitHub release assets and artifact attestations are useful signals, but this repo should not imply local binary verification until it downloads/verifies checksums, signatures, attestations, or SBOMs explicitly.

## Architecture Assessment

- `scripts/sync-profile.ps1` is a 9,510-line orchestration script that mixes GitHub metadata collection, catalog rendering, SVG generation, report generation, security posture heuristics, and topic updates. Keep changes incremental and test-backed; extract helpers only when a boundary reduces report/test coupling.
- `tests/sync-profile.Tests.ps1` is a 4,062-line contract suite. Existing roadmap items already cover the highest-risk local-only/no-workflow test reconciliation; do not duplicate those items.
- `schemas/profile-sync-report.v1.json` is 5,896 lines and still models historical workflow, Scorecard, and generated-validation fields. Preserve schema compatibility, but make no-workflow states explicit and non-warning when policy says hosted automation is absent.
- `scripts/render-profile-smoke.ps1` already has a useful local Chrome/CDP path. Wire its results into the report as local evidence with clear skipped/unavailable states instead of warnings about missing hosted smoke artifacts.
- `scripts/write-profile-sync-summary.ps1` summarizes obsolete workflow/Dependabot fields. After existing local-only cleanup, summary output should emphasize local controls, catalog drift, rendered smoke, feed compatibility, and manual dependency/advisory review.
- `projects.json`, `schemas/profile-projects.v1.json`, and `reports/profile-sync-report.json` are the core public/downstream contracts. Existing roadmap items cover portfolio fixture and static-search metadata; new work should first make the live catalog current.

## Rejected Ideas

- Reintroduce hosted GitHub workflows: rejected because current project policy removed workflows and the correct fix is local validation/report semantics.
- Recreate Dependabot or Renovate config: rejected because dependency updates are manual by policy; add local advisory review instead.
- Add live third-party stats cards, counters, trophy cards, typing widgets, or streak widgets: rejected because competitor issue evidence shows broken images, rate-limit/deployment pressure, and private-contribution ambiguity.
- Build a generic profile README generator UI: rejected because existing OSS tools already solve template creation, while this repo differentiates on curated catalog/feed accuracy.
- Full localization: rejected because this is a personal public profile and no source showed visitor demand; keep copy clear and public-safe.
- Multi-user admin, hosted CMS, plugin marketplace, or profile SaaS migration: rejected because the repo is a deterministic single-maintainer profile/feed generator.
- Move the catalog to ReadMe, GitBook, Linktree, Carrd, or Bento: rejected because those products solve hosted docs/link-in-bio management, not a GitHub profile README with a public JSON feed and local evidence report.
- Claim binary integrity from release metadata alone: rejected because asset digests and attestations are evidence signals until an explicit local verifier exists.

## Sources

Project evidence:
- https://github.com/SysAdminDoc/SysAdminDoc
- https://github.com/SysAdminDoc/sysadmindoc.github.io

Profile README and OSS competitors:
- https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
- https://github.com/anuraghazra/github-readme-stats
- https://github.com/anuraghazra/github-readme-stats/issues/4737
- https://github.com/anuraghazra/github-readme-stats/issues/4747
- https://github.com/lowlighter/metrics
- https://github.com/lowlighter/metrics/issues/1576
- https://github.com/DenverCoder1/github-readme-streak-stats
- https://github.com/DenverCoder1/github-readme-streak-stats/issues/792
- https://github.com/DenverCoder1/github-readme-streak-stats/issues/805
- https://github.com/cicirello/user-statistician
- https://github.com/rahuldkjain/github-profile-readme-generator
- https://github.com/rahuldkjain/github-profile-readme-generator/issues/888
- https://github.com/abhisheknaiidu/awesome-github-profile-readme

Commercial and adjacent systems:
- https://linktr.ee/s/pricing/
- https://bento.me/
- https://carrd.co/pro
- https://readme.com/
- https://www.gitbook.com/pricing
- https://pagefind.app/
- https://pagefind.app/docs/filters/
- https://docusaurus.io/docs/search

GitHub platform, tooling, and advisories:
- https://docs.github.com/rest/releases/assets
- https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
- https://github.com/pester/Pester/releases
- https://github.com/PowerShell/PSScriptAnalyzer/blob/master/CHANGELOG.MD
- https://github.com/DavidAnson/markdownlint-cli2
- https://docs.zizmor.sh/audits/
- https://github.com/advisories/GHSA-6v5v-wf23-fmfq

## Open Questions

- None blocking prioritization; remaining choices are implementation policy decisions already bounded by the existing local-only, privacy-safe profile philosophy.
