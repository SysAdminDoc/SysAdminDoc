# Feature Backlog

Research date: 2026-05-17

## Raw Opportunities

| ID | Idea | Evidence |
|---|---|---|
| F001 | Create `data/profile-catalog.json` as canonical project metadata. | README is hand-maintained and drifting. |
| F002 | Build `scripts/sync-profile.ps1` with `-Check` and `-Write`. | No automation exists. |
| F003 | Generate README category counts. | Counts are manually edited. |
| F004 | Generate star counts. | 18 mismatches found. |
| F005 | Generate Featured Projects from stars plus recency. | Featured table is stale. |
| F006 | Generate Currently Building from catalog flags. | Recent public repos are missing from README. |
| F007 | Add `omitReason` for intentionally hidden public repos. | Some missing repos were previously removed intentionally. |
| F008 | Detect renamed/deleted/redirected repos. | `EspressoMonkey` resolves as `ScriptVault`. |
| F009 | Generate release/latest buttons by release asset type. | 40 release-link gaps found. |
| F010 | Generate install snippets from branch/entrypoint metadata. | Existing snippets had 0 branch mismatches but have broken in prior releases. |
| F011 | Block private repos from README output. | v4.7.0 removed private 404 links. |
| F012 | Add medical/X-ray/DICOM/PACS privacy gate. | Global privacy rule. |
| F013 | Report empty public repo descriptions. | 3 sample empty descriptions found. |
| F014 | Report missing repository topics. | 25 recent missing-topic samples found. |
| F015 | Add check-only GitHub Actions workflow. | `.github/` absent. |
| F016 | Schedule away from top of hour. | GitHub docs warn about schedule delays/drops. |
| F017 | Use explicit minimal workflow permissions. | GitHub workflow syntax supports this. |
| F018 | Add CODEOWNERS for workflows. | GitHub secure-use guidance. |
| F019 | Run zizmor after workflows exist. | Purpose-built Actions scanner. |
| F020 | Add OpenSSF Scorecard after automation exists. | Supply-chain score/trust signal. |
| F021 | Validate raw userscript links. | README has many raw install URLs. |
| F022 | Validate GitHub Pages launch links. | Web app section depends on live Pages URLs. |
| F023 | Export `projects.json` for portfolio. | README and portfolio can drift. |
| F024 | Move search/filter UX to portfolio. | GitHub README sanitizes script tags. |
| F025 | Add Pagefind to portfolio. | Static search fits GitHub Pages. |
| F026 | Add static "new this week" README section. | New public repos wait for manual refresh. |
| F027 | Add release activity feed on portfolio. | Release metadata available from GitHub. |
| F028 | Add safer setup inspect-before-run path. | `irm|iex` is high-trust remote execution. |
| F029 | Add `#Requires -Version 5.1` to `setup.ps1`. | PowerShell convention. |
| F030 | Add `setup.ps1 -CheckOnly`. | Useful novice diagnostic mode. |
| F031 | Add setup logging/transcript. | Easier support for failed setup. |
| F032 | Generate topic recommendations. | GitHub topics aid discoverability. |
| F033 | Submit selected projects to awesome lists. | External discovery channel. |
| F034 | Add generated stale repo report. | Global archive rule after 6+ months inactivity. |
| F035 | Add README diff summary before write. | Generated updates need reviewability. |
| F036 | Classify placeholder/source-only repos. | `null` and source-only repos should not be promoted accidentally. |

## Deferred Ideas

- Inline README search/filter JavaScript: invalid for GitHub README, move to portfolio.
- Contributor badges: defer until public contribution signal grows.
- Badge-heavy redesign: current catalog needs accuracy before more decoration.
