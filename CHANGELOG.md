# Changelog

## 2026-07-07

- Compressed the generated public projects feed while preserving the existing schema, dropping `projects.json` under the 512 KB budget and adding a regression check for the real catalog output.
- Tightened generated profile parity with the mock image: centered line-art header, signal-based Start Here routing, generated Tool Catalog cards, and footer action strip.
- Bumped the internal profile evidence version to `v4.9.153`.
- Reimagined the generated profile README as a local, theme-aware public tools command center with a stronger first-viewport header, centered routing actions, and no third-party render hosts.
- Modernized Start Here routing, setup guidance, validation guidance, and category summaries so visitors can choose by platform, install path, and confidence signal without reading the full catalog first.
- Bumped the internal profile evidence version to `v4.9.152`.

## 2026-07-06

- Added public-safe metadata hygiene handoffs: the sync report now separates total topic/description gaps from public row details, redacts suppressed/private/unsafe repositories from exposed metadata and fork-parent detail rows, and renders ready-to-run `gh repo edit` commands or catalog guidance in the profile summary.
- Bumped the internal profile evidence version to `v4.9.151`.
- Refreshed local audit pins to `markdownlint-cli2` 0.23.0, `markdown-it` 14.3.0, `js-yaml` 5.2.1, and hash-pinned `zizmor` 1.26.1; dependency review now reports latest-known/current pin freshness and stale-review warnings without failing solely on stale evidence.
- Bumped the internal profile evidence version to `v4.9.150`.
- Added PowerShell runtime security posture reporting: setup now bootstraps PowerShell 7 while keeping Windows PowerShell 5.1 limited to `setup.ps1`, validation reports the active `pwsh` version/channel, and the profile sync report records current-LTS/preferred/runtime warning evidence.
- Bumped the internal profile evidence version to `v4.9.149`.
- Added GitHub metadata budget telemetry to profile sync: `-GraphQlPageSize` can exercise smaller repo-list pages, and `validationPerformance.metadataFetch` plus the public summary now record page size, request/retry counts, truncation, resource-limit fallback evidence, and REST release-fetch budgets.
- Bumped the internal profile evidence version to `v4.9.148`.
- Hardened userscript trust checks so `@updateURL` and `@downloadURL` metadata probes are blocked unless they use allowed GitHub raw-content hosts, preventing remote userscript headers from triggering arbitrary HTTP probes.
- Routed the remaining `gh repo view` profile-state check through the shared `Invoke-GhCli` adapter and added an early `-Owner` validation guard before generated URLs or GitHub API paths are built.
- Hardened `render-profile-smoke.ps1` with a bounded DevTools WebSocket connect and a guarded temp-profile cleanup helper that refuses recursive deletion outside the generated smoke-profile directory pattern.
- Made `review-local-dependencies.ps1` exit nonzero when its structured result is `review-needed`, so local advisory or pin drift checks cannot be missed by release scripts.
- Fixed the dependency-review skip path so local override or pin drift still reports `review-needed` and exits nonzero when the live npm audit is intentionally skipped.
- Bounded profile link validation to response headers so GET fallbacks prove reachability without downloading release assets or raw file bodies.
- Made `setup.ps1` fail loudly when `winget`, Python, or Git remain unavailable instead of returning success after warning-only incomplete setup paths.
- Bumped the internal profile evidence version to `v4.9.147`.
- Added a rendered-README action link audit to profile sync validation: generated clone/install snippets, `/releases/latest` download buttons, and raw userscript Install links are parsed from the README itself, probed through the shared HEAD/GET validator, and counted in `linkValidationSummary` plus profile-sync summaries.
- Fixed live catalog drift found by the audit: `HostsGuard` now renders as a native desktop EXE-release row instead of a stale Python `HostsGuard.py` clone snippet, and `RES-Slim` is cataloged as a public extensions/fork row.
- Bumped the internal profile evidence version to `v4.9.144`.

## 2026-07-02

- Made the `-Check` profile-asset sync gate deterministic: contribution heatmap SVGs are regenerated from the live GitHub contribution calendar (which changes continuously for an active account), so their committed-vs-fresh drift is now reported per-asset but excluded from the fatal gate. Deterministic catalog-driven assets (header/stats/languages/activity/footer) still fail the gate, and a missing contribution file still fails.
- `setup.ps1` now selects the winget install scope by elevation (`Test-Admin`): a non-elevated novice running `irm | iex` installs user-scope directly instead of triggering a noisy machine-scope failure dump before the fallback. Verified on Windows PowerShell 5.1.
- `render-profile-smoke.ps1`: kill the Chrome process tree on Windows (`taskkill /T`) instead of only the launcher PID, so failed runs no longer leak the locked temp `--user-data-dir`; restrict Chrome discovery to `-CommandType Application` so a same-named alias/function can't resolve to a broken path; guard the `artifactBudgets` lookup so a report missing that section still gets its rendered-smoke summary written.
- `write-profile-sync-summary.ps1`: encode the `file=`/`title=` annotation properties (adds `:`/`,` escaping) so a workflow filename or status can't corrupt the GitHub annotation property list.
- README profile nav now links all rendered category sections (added Security and Forks — previously 8 of 10 were navigable).
- markdownlint now covers `.github/CONTRIBUTING.md` and `.github/CODE_OF_CONDUCT.md` (previously unlinted, so rule violations there passed silently).

## 2026-07-01

- Added `Test-SafeGitHubName` and a fatal `catalogShape` check that rejects repo and `aliasOf` names not matching `^[A-Za-z0-9._-]+$`, plus a defense-in-depth guard in the `-ApplyTopics` path, preventing tampered catalog names from breaking out of `gh api` paths.
- Added `Test-AllowedUserscriptUrl` guarding `Get-UserscriptContent` so userscript fetches are restricted to HTTPS on GitHub raw-content hosts (raw/gist/objects.githubusercontent.com, github.com), blocking SSRF-style requests from tampered `userscriptUrl` fields.
- Upgraded pinned Pester from 5.7.1 to 5.8.0 across `validate-local.ps1`, the generated setup guidance, and the dependency-review contract; audited the suite for Pester 6.0-removed APIs (`Assert-MockCalled`, `Assert-VerifiableMocks`, `Set-ItResult -Pending`) and found none.
- `validate-local.ps1` now runs Pester through a configuration object with profiler-based JaCoCo code coverage of `sync-profile.ps1`, writing gitignored `coverage.xml` and printing a coverage percentage.
- Regenerated `README.md`, `projects.json`, and profile SVG assets to apply the pending premium-polish category summaries/routing copy and refresh live repository metadata.
- Added an `Invoke-GhCli` adapter and routed every read-path `gh` invocation (repo enumeration, GraphQL contributions, release/fork-parent/tag fetches, auth status, JSON helper) through it, giving one mock/error seam instead of duplicated `& gh ... 2>&1; $LASTEXITCODE` blocks. Tests mock the adapter directly.
- Resolved `$ReadmePath`/`$ProjectsPath` against `$RepoRoot` in `New-Readme`, `New-CatalogFromReadme`, and the check path so generation reads the correct files when the working directory is not the repo root.
- Fixed `Get-PythonAuditToolPins` to count `--hash=` directives per package (slicing between consecutive package declarations) instead of stamping the file-global total on every package.
- Fixed a StrictMode "property 'Count' cannot be found" crash on `sync-profile.ps1 -Write -Offline`: repo-count accesses in `New-Readme`, `New-ProjectsExportJson`, and `New-ProfileAssetSvgs` now null-filter the repo set so an empty/offline repo binding yields 0 instead of throwing.
- Constrained the seven `prDeliveryTransition` evidence fields in `profile-sync-report.v1.json` to `["object", "null"]` so they no longer accept arbitrary JSON scalar/array values.
- `New-CategorySection` now skips categories with zero visible entries instead of rendering an empty `<details>` shell; `Test-ReadmeExperience` only requires anchors for categories that have entries. (No effect on current output — all catalog categories are populated.)
- Promoted `$Owner` from a hard-coded value to a script parameter (default `SysAdminDoc`) so the generator can target another account without code edits.
- Resolved absolute `$ProjectsPath`/`$AssetsPath`/`$TopicAllowlistPath` correctly in the `-Write` and `-ApplyTopics` paths (previously only `$ReadmePath` honored absolute paths).
- Test suite: tagged the four child-process Describes `Integration` (run `Invoke-Pester -ExcludeTag Integration` for a fast in-process loop), and added coverage for the full profile-SVG asset set, empty/offline repo generation, and a real `-Write -Offline` entrypoint run.
- Documented the minimum GitHub token scopes inline at `Test-GitHubCliAuthenticated` (public-repo read for generation, `read:user` for the contribution calendar, `public_repo` for `-ApplyTopics`).
- Fixed the same StrictMode Count-on-null crash in the `-Check` path by null-normalizing `$Repos` at the top of `Test-ProfileState`; `-Check -Offline` now writes a report instead of throwing.
- Fixed `-ApplyTopics` being unreachable: it no longer defaults to `-Check` (which `exit`ed before the apply block), and generation is skipped unless `-Write`/`-Check` is set, so `-ApplyTopics` runs the topic-apply flow directly.

## 2026-07-01 (earlier)

- Added schema-versioned static search metadata to `projects.json` so portfolio consumers can use stable category, type, and language filters without scraping README sections.
- Polished community docs: enriched CONTRIBUTING.md with pipeline explanation, improved SECURITY.md structure, refined PR template guidance, and fixed stale placeholder references in issue templates.
- Refined header and footer SVG assets: wider accent line, tighter label tracking, dot separators in header; smoother wave proportions in footer. Both themes updated.
- Improved category summary descriptions from generic to action-oriented copy that tells visitors what each section contains.
- Replaced internal jargon in the Start Here routing table with visitor-friendly descriptions.
- Polished setup.ps1 terminal banner and messaging.
- Fixed null-unsafe `ToLowerInvariant()` call in `Get-RepoMeta` that could crash under StrictMode when a catalog entry has a null repo field.
- Fixed `$missingPins` count in `review-local-dependencies.ps1` that nested sub-arrays instead of flattening them, causing the dependency review status to falsely report "ok" when misaligned pins existed.
- Bumped `write-profile-sync-summary.ps1` version requirement from 7.0 to 7.1 to match its use of the ternary operator.
- Added all `scripts/` files to the PSScriptAnalyzer target list so findings in helper scripts are not missed during local validation.
- Removed unused `RunId` parameter from `set-generated-validation-status.ps1`.
- Added `minLength: 1` constraint on catalog and projects schema `title` fields to reject empty-string titles.
- Added `minLength` to the schema keyword compatibility allowlist.
- Added fork attribution fixture entry with `forkOf`, `upstreamLicense`, and `readmeReviewNote` fields for better schema validation coverage.

## 2026-06-30

- Added a local dependency/advisory review command that captures npm audit status, override lock drift, pinned npm tools, PowerShell module pins, and hash-pinned zizmor evidence.
- Hardened markdown hygiene checks so tracked Markdown trailing-whitespace validation handles zero, single, and multiple violations while markdownlint stays limited to public tracked docs.
- Re-labeled release trust, checksum, SBOM, digest, and attestation signals as metadata evidence so the feed and report no longer imply local binary verification.
- Retired generated PR helper side effects so profile automation helpers are offline/manual previews under the local-only validation policy.
- Replaced stale workflow/CI public intake with local-validation issue reporting and local-only audit tooling configuration.
- Made rendered profile smoke evidence local and policy-aware, with passed desktop/mobile evidence folded into the sync report and legacy hosted-artifact warnings removed.
- Added a downstream portfolio feed compatibility fixture that locks required public feed fields, action variants, release-trust metadata, and suppression redaction behavior.
- Split repository security posture reporting into local and hosted controls so removed workflow-only controls no longer blur local validation evidence.
- Added a local validation bootstrap command that installs pinned validation tools before running markdownlint, PSScriptAnalyzer, and Pester.
