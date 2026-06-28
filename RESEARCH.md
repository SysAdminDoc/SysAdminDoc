# Research - SysAdminDoc

## Executive Summary

SysAdminDoc is a generated GitHub profile and public project catalog: `data/profile-catalog.json` feeds `scripts/sync-profile.ps1`, which renders `README.md`, `projects.json`, committed theme-aware SVG assets, schema contracts, and `reports/profile-sync-report.json`. Its strongest current shape is the deterministic, privacy-aware portfolio/feed generator: it avoids fragile live profile-card hosts, redacts suppressed projects, validates the feed shape, and gives downstream surfaces structured release and catalog metadata. Highest-value direction: reconcile the code and tests with the new local-only validation policy, then refresh generated artifacts and report semantics so the repo has one trustworthy local quality path. Top opportunities: fix the 80 failing Pester tests caused by removed `.github/workflows` and `.github/dependabot.yml`; make scheduled-workflow/report sections explicitly `not-applicable` when hosted automation is absent; sync `README.md`, `projects.json`, assets, and report evidence; install/use the pinned Node toolchain so markdownlint is reproducible; keep release-trust and feed-contract metadata, but decouple it from hosted workflow assumptions; add a downstream portfolio fixture; preserve privacy redaction and root-Markdown hygiene; and keep profile UX compact rather than adding third-party widgets.

## Product Map

- Core workflows: edit catalog data, run local PowerShell/Node validation, render the public profile README, export the public `projects.json` feed, and inspect report evidence.
- User personas: GitHub profile visitors, portfolio-site visitors, users choosing install/download links, public issue reporters, security reporters, and the maintainer curating 200+ public repos.
- Platforms and distribution: GitHub profile README, raw JSON feed, committed SVG assets, schemas, issue templates, Windows `setup.ps1`, and the separate static portfolio consumer.
- Key integrations and data flows: GitHub repository/release metadata, catalog schema validation, Pester tests, PSScriptAnalyzer, markdownlint-cli2, profile SVG generation, release-trust filename/digest metadata, and portfolio feed import.

## Competitive Landscape

- github-readme-stats: Strong at drop-in dynamic cards and themes; its own README warns the public Vercel instance is best-effort under rate limits. Learn from simple card configuration; avoid returning to live third-party metric hosts.
- lowlighter/metrics: Strong plugin breadth for generated profile infographics. Learn from modular report sections; avoid turning this single-maintainer catalog into a broad plugin framework.
- cicirello/user-statistician: Strong committed-SVG model for profile stats. Learn from committed output and repeatable generation; avoid hosted-workflow dependency now that this repo intentionally removed workflows.
- github-profile-readme-generator / ProfileMe.dev / readme.so: Strong first-run UI for hand-authored profile pages. Learn from approachable onboarding; avoid template-builder work because this repo's value is catalog accuracy, feed data, and trust metadata.
- Awesome GitHub Profile README and adjacent awesome lists: Reward concise positioning, working links, and recognizable categories. Keep the compact profile and public-safe catalog instead of decorative personal chrome.
- ReadMe and GitBook: Commercial docs platforms emphasize sync, changelog, analytics, search, and feedback loops. Learn from stale-content and question-gap reporting; avoid hosted docs migration because the profile/feed already belongs in the repo.
- Pagefind / Docusaurus local search: Strong model for static, client-side discovery without hosted infrastructure. This belongs primarily in `sysadmindoc.github.io`; this repo should keep exporting clean search/filter metadata.

## Security, Privacy, and Reliability

- Verified: `rtk pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Detailed"` reports 181 passed and 80 failed. Failures are dominated by tests still reading removed `.github/workflows/*.yml` and `.github/dependabot.yml` files at `tests/sync-profile.Tests.ps1:2447`, `2656`, `2686`, `2818`, `3124`, `3257`, `3292`, `3576`, `3600`, `3642`, `3688`, `3713`, `3736`, `3766`, `3787`, `3802`, `3823`, `4948`.
- Verified: `tests/sync-profile.Tests.ps1:408` still expects Dependabot local configuration even though recent history removed Dependabot by policy. This makes the repository's local quality gate contradict the current maintenance model.
- Verified: `scripts/sync-profile.ps1:4249-4415` handles missing workflow directories in definition discovery, but `Get-ScheduledWorkflowRunLookup` and `Test-ScheduledWorkflowFreshness` assume each definition has `workflowFile`; Pester fixtures passing `[ordered]` objects surface `PropertyNotFoundException` at `scripts/sync-profile.ps1:4279`.
- Verified: `reports/profile-sync-report.json:4-6` currently records `readmeInSync: false`, `projectsExportInSync: false`, and `profileAssetsInSync: false`; generated artifacts need a local refresh after the validation contract is corrected.
- Verified: `npm run lint:markdown` fails because `node_modules/.bin/markdownlint-cli2` is absent; the local validation path needs `npm ci` documented or wrapped before linting.
- Verified: `.gitignore` intentionally ignores root Markdown except the public/security docs, while `AGENTS.md` allows only `README.md`, `CLAUDE.md`, `AGENTS.md`, `CHANGELOG.md`, `ROADMAP.md`, and `RESEARCH.md`; the root-Markdown hygiene report is clean and should stay warning-only for local planning docs.
- Verified: privacy guardrails are strong: `projects.json.suppressed` uses redacted suppression rows, `reports/profile-sync-report.json:1619-1623` reports zero suppressed identifier leaks and zero duplicate visible repos, and issue forms warn against private names, credentials, medical data, and sensitive logs.
- Likely: release-trust metadata should stay filename/API-derived. GitHub exposes release asset metadata and artifact attestations, but this repo should report evidence rather than imply it cryptographically verified binaries without a real verification path.

## Architecture Assessment

- `scripts/sync-profile.ps1` is a 9,433-line orchestration module with 210 functions. Keep incremental helper extraction and tests; do not split it into new scripts unless a boundary is already proven by repeated test friction.
- `tests/sync-profile.Tests.ps1` is a 4,962-line local contract suite. Its highest-risk section is not business logic coverage but obsolete workflow/dependency-automation assumptions after commit `475558a`.
- `scripts/write-profile-sync-summary.ps1` still summarizes scheduled workflow, Scorecard, and hosted-run fields. Keep summary fields only if they can emit `not-applicable` cleanly when hosted automation is intentionally absent.
- `scripts/open-generated-profile-pr.ps1`, `scripts/set-generated-validation-status.ps1`, and workflow-related report fields now need an explicit decision: retire them from active gates or reframe them as dormant/manual helpers. The current tests treat them as live.
- `reports/profile-sync-report.json` remains valuable as the single machine-readable status contract, but its stale hosted-run evidence should not block local validation.
- `schemas/profile-projects.v1.json` and `schemas/profile-sync-report.v1.json` are useful downstream contracts. Add a portfolio-consumer fixture so future feed schema changes prove compatibility without checking the other repo.
- Test/documentation gaps: missing local validation bootstrap (`npm ci`, Pester, PSScriptAnalyzer, markdownlint), missing no-workflow fixtures, no regression test for empty scheduled workflow definitions, no test that workflow-removal policy keeps report status clean.

## Rejected Ideas

- Reintroduce hosted GitHub workflows: rejected because current repo history and project rules intentionally removed them; fix local contracts instead.
- Recreate Dependabot or Renovate config: rejected because dependency updates are handled manually and tests should stop requiring local dependency-automation files.
- Add live third-party stats cards, counters, typing widgets, or trophy widgets: rejected because competitor evidence shows rate-limit and availability risk; committed local SVG assets are more reliable.
- Build a generic profile README generator UI: rejected because existing OSS tools already cover template generation, while this repo's differentiator is a curated public repo catalog and feed.
- Full localization: rejected because this is a personal/public profile and no source shows visitor demand; keep metadata fields plain and public-safe.
- Multi-user admin, hosted CMS, or plugin marketplace: rejected because the repo is a deterministic single-maintainer profile/feed generator.
- Move the catalog to ReadMe, GitBook, or another hosted docs portal: rejected because paid docs portals solve product-doc collaboration, not a GitHub profile README plus public JSON feed.
- Claim binary integrity from release metadata alone: rejected because release asset digests and attestations are evidence signals, not full local verification unless the repo implements explicit verifier logic.

## Sources

Project evidence:
- https://github.com/SysAdminDoc/SysAdminDoc
- https://github.com/SysAdminDoc/sysadmindoc.github.io

Profile and catalog competitors:
- https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
- https://github.com/anuraghazra/github-readme-stats
- https://github.com/anuraghazra/github-readme-stats/issues/4748
- https://github.com/lowlighter/metrics
- https://github.com/cicirello/user-statistician
- https://github.com/rahuldkjain/github-profile-readme-generator
- https://github.com/abhisheknaiidu/awesome-github-profile-readme
- https://github.com/awesome-foss/awesome-sysadmin
- https://github.com/awesome-scripts/awesome-userscripts

Docs, search, and portfolio systems:
- https://readme.com/
- https://www.gitbook.com/pricing
- https://gitbook.com/docs/changelog
- https://pagefind.app/
- https://pagefind.app/docs/js-api-filtering/
- https://docusaurus.io/docs/search
- https://docusaurus.io/community/resources

GitHub platform and supply-chain evidence:
- https://docs.github.com/rest/releases/assets
- https://docs.github.com/rest/releases/releases
- https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
- https://github.com/actions/attest
- https://github.com/ossf/scorecard
- https://docs.zizmor.sh/audits/

Tooling and advisories:
- https://github.com/pester/Pester/releases
- https://github.com/PowerShell/PSScriptAnalyzer/blob/master/CHANGELOG.MD
- https://github.com/DavidAnson/markdownlint-cli2
- https://github.com/advisories/GHSA-6v5v-wf23-fmfq
- https://github.com/advisories/GHSA-h67p-54hq-rp68

## Open Questions

- None blocking this roadmap pass; `gh` live API validation was unavailable because the CLI is unauthenticated and the public REST rate limit was exhausted.
