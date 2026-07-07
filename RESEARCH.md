# Research - SysAdminDoc
Date: 2026-07-07 - replaces all prior research.

## Executive Summary
Verified: SysAdminDoc is a deterministic GitHub profile README, public project catalog, committed SVG asset, validation-report, and `projects.json` feed generator for the `SysAdminDoc` portfolio. Its strongest current shape is the local-only PowerShell validation pipeline around `scripts/sync-profile.ps1`, JSON Schema 2020-12 contracts, public-safe redaction, rendered GitHub profile smoke evidence, and metadata-only release trust reporting. The highest-value direction is to keep the new command-center UX while hardening the generated contract: bring `projects.json` back under budget, clear live release/license warnings, make sync drift failures self-diagnosing, add API/cache resilience, preserve rendered visual evidence, stabilize public feed entity IDs, and add low-risk integration exports without reintroducing hosted widgets or third-party render dependencies.

Top opportunities, in priority order:
1. Fix the current `projects.json` soft-budget warning: `reports/profile-sync-report.json.artifactBudgets` shows 514281 bytes against a 512000-byte soft limit.
2. Clear current trust drift: `Images` advertises an EXE download while the latest release only exposes ZIP, and `qBittorrent-Vanced` remains an unresolved `NOASSERTION` license row.
3. Add first-mismatch diagnostics for `readmeInSync`, `projectsExportInSync`, and profile asset drift so `-Check` failures identify the exact section/file, not only a boolean.
4. Add a bounded cache/conditional-request layer for GitHub metadata, release, and link probes to reduce rate-limit exposure across 206 repos, 206 release fetches, and 342 link targets.
5. Persist rendered visual evidence for the first viewport after the UX revamp, including dark/light and mobile/desktop screenshot paths plus header/tool-catalog presence assertions.
6. Add stable public feed IDs and alias/rename metadata so portfolio/search consumers do not depend only on mutable repo names.
7. Add branch-tip provenance for branch-pinned clone/install snippets while preserving current-install behavior.
8. Add an optional Backstage-compatible catalog export as an integration format, not a general plugin system.

## Product Map
- Core workflows: generate `README.md`, `projects.json`, and `assets/profile/*.svg` from `data/profile-catalog.json`; validate with `scripts/validate-local.ps1`; run `scripts/sync-profile.ps1 -Check`; smoke the rendered profile with `scripts/render-profile-smoke.ps1`; review dependency/security posture with `scripts/review-local-dependencies.ps1`.
- User personas: the profile owner/maintainer; public visitors routing to tools by platform and confidence signal; downstream portfolio/search consumers; issue reporters submitting profile corrections, broken links, or local validation failures; future coding agents maintaining the generator.
- Platforms and distribution: GitHub profile README; raw GitHub JSON feed and schemas; Windows/PowerShell 7.4+ generator with Windows PowerShell 5.1 bootstrap support in `setup.ps1`; Node markdown linting; Pester/PSScriptAnalyzer local validation; hash-pinned Python `zizmor` local audit tooling.
- Key integrations and data flows: GitHub CLI GraphQL/REST metadata; GitHub latest-release asset metadata and platform digests; GitHub raw userscript header probes; Security Scorecards API classification; JSON Schema validation via `Test-Json -SchemaFile`; downstream `sysadmindoc.github.io` portfolio import and Pagefind/static-search metadata.

## Competitive Landscape
- `rahuldkjain/github-profile-readme-generator`, `profileme-dev`, and `awesome-github-profile-readme`: strong onboarding, examples, social/icon sections, and profile-author discovery. Learn from low-friction section selection and public examples; avoid generic badge/icon bloat that weakens SysAdminDoc's current routing surface.
- `anuraghazra/github-readme-stats`, `github-readme-streak-stats`, `github-profile-summary-cards`, `github-trends`, and `lowlighter/metrics`: strong generated visuals, themes, and metrics depth. Learn from clear cards, theme variants, and generated artifacts; avoid live third-party render hosts because open issues show public-card downtime and API-host reliability failures.
- `waka-readme-stats`, `readme-scribe`, and `snk`: automate profile README updates from external data. Learn from deterministic generation and output artifacts; avoid hosted workflow dependence because this repo intentionally validates locally and has no live `.github/workflows` tree.
- `developerFolio`, `GitProfile`, Portfolly, Devfol.io, and Linktree: strong portfolio/search/link-hub positioning, analytics, highlighting, and external audience routing. Learn from portfolio freshness, search/filter contracts, and highlighted links; keep analytics and monetization out of the GitHub README and let the separate portfolio handle UI/search.
- Pagefind: useful static-search metadata and multilingual indexing model. Learn from language/script metadata for `projects.json`; avoid embedding a search UI in GitHub Markdown.
- Backstage Software Catalog: mature entity envelope, metadata, tags, links, lifecycle, and owner fields. Learn from stable entity references and optional export shape; avoid importing Backstage's multi-user portal complexity into this repo.
- GitHub REST/GraphQL docs, release asset digest metadata, OpenSSF Scorecard, WCAG 2.2, JSON Schema, Pester 6, PSScriptAnalyzer, PowerShell lifecycle, and `zizmor`: reinforce this repo's local evidence posture. Learn from API budget rules, release trust metadata, accessibility checks, and migration lanes; avoid treating external governance checks as local code defects when they are owner- or plan-gated.

## Security, Privacy, and Reliability
- Verified current warning: `projects.json` is above the configured public feed byte soft limit (`reports/profile-sync-report.json.artifactBudgets`, `scripts/sync-profile.ps1` `Test-GeneratedArtifactBudgets`). The README remains under its line/byte/table budgets.
- Verified current drift: `reports/profile-sync-report.json.releaseAssetDrift.releaseAssetKindMismatches` has one row for `Images` where `downloadKind` expects `exe` but the latest release asset is `Images-v0.2.15-win-x64.zip`.
- Verified current license gap: `reports/profile-sync-report.json.projectLicenseMetadata.unresolvedUnknownCount` is 1 for `qBittorrent-Vanced`; two other `NOASSERTION` rows are intentional exceptions.
- Verified current trust posture: `releaseAssetDrift.executableDownloadTrustShortlist` records metadata-only evidence, 77 executable download rows with no attestations, 75 without SBOM metadata, and 64 executable downloads missing sidecar checksum coverage. The existing roadmap already tracks an opt-in verifier, so do not duplicate it.
- Verified reliability risk: `validationPerformance` currently uses GraphQL page size 500, one GraphQL metadata request, REST release fetch for 206 repos, and 342 link probes. GitHub documents primary/secondary GraphQL and REST rate limits; caching and conditional requests would reduce exposure without weakening live validation.
- Verified privacy guardrails: issue forms and reports intentionally redact suppressed/private rows, and `metadataHygiene.handoff` excludes hidden repos. Preserve that pattern for every new report/export field.
- Missing guardrail: `readmeInSync`, `projectsExportInSync`, and `profileAssetsInSync` are booleans in the report. A future mismatch should include first differing line/section, expected/current hashes, and affected asset names.
- Missing recovery path: rendered smoke reports pass/fail and viewport metrics, but not visual screenshot artifact paths or first-viewport component presence assertions after the header/tool-catalog revamp.

## Architecture Assessment
- `scripts/sync-profile.ps1` is large but already has useful seams: GitHub CLI adapter, metadata fetch telemetry, release trust, link probes, README checks, artifact budgets, schema validation, and public-safe handoffs. Add report fields and tests near existing functions rather than rewriting the generator.
- `schemas/profile-projects.v1.json` and `schemas/profile-sync-report.v1.json` are the right boundary for additive fields such as feed entity IDs, alias metadata, cache telemetry, and visual smoke evidence. Keep schema changes additive unless the existing roadmap's migration policy lands first.
- `projects.json` is both a public portfolio contract and a generated feed. Size reduction should preserve `provenance`, `searchMetadata`, `primaryAction`, suppression redaction, and `releaseTrust.trustLevel`, while moving repeated or diagnostic-heavy fields out of the slim consumer path if needed.
- `scripts/render-profile-smoke.ps1` should become the rendered UX evidence lane: it already proves GitHub profile rendering at desktop/mobile viewports, so screenshots and first-viewport assertions belong there instead of in the generator.
- `tests/sync-profile.Tests.ps1` has coverage around GraphQL page-size telemetry, metadata hygiene handoffs, artifact budgets, rendered smoke summaries, release trust, project license metadata, portfolio compatibility, and runtime posture. Gaps are current warning remediation fixtures, cache/ETag behavior, visual smoke screenshot fields, feed stable IDs, and branch-tip provenance.
- `ROADMAP.md` and `Roadmap_Blocked.md` remain split correctly: actionable local work goes in `ROADMAP.md`; branch protection, immutable releases, secret scanning plan-gated settings, and owner decisions stay in `Roadmap_Blocked.md`.

## Rejected Ideas
- Reintroduce live third-party stats, streak, WakaTime, visitor counters, or metrics cards. Source: `github-readme-stats`, `github-readme-streak-stats`, `waka-readme-stats`, `lowlighter/metrics`, issue `anuraghazra/github-readme-stats#4867`. Reason: dynamic host/API failures contradict the committed-asset, local-smoke posture.
- Restore GitHub Actions or Dependabot version-update automation. Source: live `.github/zizmor.yml`, `.gitignore`, `AGENTS.md`, and recent commits removing workflows/Dependabot. Reason: current policy is local validation and manual dependency updates, with Dependabot security posture monitored only.
- Build a general plugin ecosystem. Source: `lowlighter/metrics`. Reason: high maintenance/trust boundary cost; a narrow Backstage export is enough.
- Fold the `sysadmindoc.github.io` portfolio into this repo. Source: `developerFolio`, `GitProfile`, Portfolly, Devfol.io. Reason: this repo should remain the authoritative feed/profile generator while the portfolio owns search/UI.
- Add visitor analytics, email capture, monetization, or link-in-bio growth tools. Source: Linktree pricing/features. Reason: poor fit for a public GitHub profile README and unnecessary privacy surface.
- Translate the full README. Source: Pagefind multilingual docs. Reason: high maintenance for a personal profile; feed-level locale/script hints already cover downstream search needs and are already tracked.
- Default-download and verify every release binary during `-Check`. Source: current `releaseTrust` metadata-only notes and 141 release-bearing rows. Reason: bandwidth/time/trust cost is too high; keep the existing opt-in verifier roadmap item.
- Add a mobile app, desktop app, or multi-user auth layer for catalog maintenance. Source: current workflows and GitHub profile constraints. Reason: no verified demand beyond the existing Git/GitHub maintenance model.

## Sources
Project and platform:
- https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme
- https://github.blog/developer-skills/github/how-to-make-your-images-in-markdown-on-github-adjust-for-dark-mode-and-light-mode/
- https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api
- https://github.blog/changelog/2025-09-01-graphql-api-resource-limits/
- https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api
- https://docs.github.com/en/rest/releases/assets?apiVersion=2022-11-28

Profile README competitors:
- https://github.com/rahuldkjain/github-profile-readme-generator
- https://github.com/abhisheknaiidu/awesome-github-profile-readme
- https://github.com/anuraghazra/github-readme-stats
- https://github.com/anuraghazra/github-readme-stats/issues/4867
- https://github.com/lowlighter/metrics
- https://github.com/DenverCoder1/github-readme-streak-stats
- https://github.com/vn7n24fzkq/github-profile-summary-cards
- https://github.com/anmol098/waka-readme-stats
- https://github.com/avgupta456/github-trends
- https://github.com/Platane/snk
- https://github.com/muesli/readme-scribe

Portfolio, catalog, and search:
- https://github.com/saadpasta/developerFolio
- https://github.com/arifszn/gitprofile
- https://portfolly.io/
- https://linktr.ee/s/pricing/
- https://pagefind.app/docs/
- https://github.com/Pagefind/pagefind/blob/main/docs/content/docs/multilingual.md
- https://backstage.io/docs/features/software-catalog/descriptor-format/

Security, standards, and dependencies:
- https://json-schema.org/specification
- https://www.w3.org/TR/WCAG22/
- https://scorecard.dev/
- https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6
- https://pester.dev/docs/migrations/v5-to-v6
- https://github.com/zizmorcore/zizmor/releases

## Open Questions
None.
