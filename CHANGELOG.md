# Changelog

## 2026-09-05

- Link results are now cached by what the answer actually was. A single 24-hour window treated a corrected 404 exactly like a healthy 200, so a fixed link stayed reported broken for a day, and a rate-limited host stayed reported failed without ever being retried. Successes now hold for the configured window, definitive dead links for an hour, and transient failures (429, 5xx, timeouts, 403) are never reused across runs, because the next run is precisely when they should be retried. Stored `ETag` and `Last-Modified` values survive expiry and are sent back as conditional headers, so a `304 Not Modified` settles a target cheaply and keeps the previous verdict. A server's `Retry-After` is honoured in both its delta-seconds and HTTP-date forms but capped at 60 seconds locally, with the real retry time reported rather than slept through. The cache counters now report the reuse decision instead of the raw TTL: a 404 re-probed after an hour is no longer counted as a cache hit.
- Dependency freshness is now measured against the registries instead of a hand-edited list. The review carried a "latest known" map with a date beside it, so it reported markdown-it 14.3.0 and js-yaml 5.2.2 as current while npm had moved to 15.0.1 and 5.4.1, and `npm outdated` cannot see transitive overrides at all. Every pin is now resolved against registry.npmjs.org or pypi.org, and each row separates what the parent declares, the version actually resolved, and the registry latest. Being behind is not a failure: a new major is recorded as review-needed, which is what keeps the deliberate markdown-it 14.x hold green while still naming the 15.0.1 that exists. Only missing or stale evidence warns. Answers cache to `.cache/registry-versions.json`, and `-OfflineRegistry` reads that cache and reports its age, going stale after 30 days.
- Local validation now verifies the PowerShell modules it installs instead of trusting a version number. An exact version pin does not detect a changed same-version Gallery package, and `Install-Module` would have taken whatever the Gallery served. A new `data/powershell-module-lock.json` records the package URL, reviewed nupkg SHA-256 and expected Authenticode signer for Pester 5.9.1, PSScriptAnalyzer 1.25.0 and the opt-in Pester 6.1.0 lane. Both lanes download the nupkg, check its hash **before** extracting anything, then require every signed file to carry the signer the lock names. A module version with no reviewed record is refused rather than installed. Verified packages are cached under `.cache/powershell-modules`, so a later offline run reuses bytes that already passed. Signer subjects are compared case-sensitively and byte-for-byte: Pester's certificate carries non-ASCII characters, and a transliterated subject is a different signer.

## 2026-09-04

- Fixed six defects an adversarial review found in the day's own changes. The three artifact sync comparisons used `-eq`, which is case-insensitive in PowerShell, and with the drift fallback removed that comparison had become the entire verdict: a README, feed or asset differing only in letter case reported as in sync. They now use `-ceq`. The activity SVG renders release-inspection counters that move as repositories publish, but only the contribution heatmap was excluded from the fatal asset gate, so a clean checkout went red within hours of the commit that generated it; both live-derived assets are now excluded through one shared pattern. The topic allowlist counted nested objects, booleans and numbers as repository names because each stringifies into something the safe-name pattern accepts, and counted duplicates the apply path would only visit once. Future-dated smoke evidence produced a negative age that cleared every staleness signal, and an unparseable timestamp was treated as absent while still being published; both now warn. The summary writer threw under StrictMode on any report generated before the smoke-age fields existed, which made its own "unknown" fallbacks unreachable.
- A new public repository no longer costs a hand-written 22-field catalog row. `missingPublicRepos` is a fail-closed gate, and its only remediation was transcribing the whole entry from the API, which is what turned three new repos into a multi-day check outage in August and again this month. Each missing repo now carries a paste-ready fragment filled from live metadata (name, default branch, language, description, and a category only when a topic or language proves it), with everything unobservable left null and listed under `unresolvedFields` rather than guessed. `-Write -DraftMissingCatalogEntries` will append those rows for you, always suppressed and never published, with the unresolved fields named in the suppression reason. The gate still fails either way: a draft is not a cataloging decision.
- Every hand-authored link above the generated-catalog notice is now checked, not just three known URLs. The old collector recognized the portfolio link and the two setup links and nothing else, which is how a dead services call to action shipped and survived a clean link report. The header is now parsed for Markdown links and images, HTML `href`, `src` and `srcset` (each candidate in a set separately), with external targets deduplicated and routed through the same safe-outbound policy as everything else. A hand-written destination that stops resolving fails the run; images stay warning-only, since a slow badge host is not a broken profile. Local `#fragment` links are resolved against the complete generated README with no network access at all, so a call to action pointing at a section that no longer exists fails even offline. The live check went from 365 to 371 probed targets.
- The release-trust shortlist now recommends things that can actually be done. Every one of the 93 executable downloads was told to publish a build-provenance attestation, which requires a GitHub Actions OIDC token; this repository ships no workflows by policy, so the report's top recommendation was impossible on every row, and counting it as a gap kept every project permanently incomplete. Attestation no longer scores, ranks, or appears as a next action, and the section states once why it is unreachable. Ranking now weights a missing SHA-256 checksum above a mutable release above a missing SBOM, so the list opens with the cheapest real integrity wins: 78 repositories still ship executables with no checksum. Two projects now read as genuinely complete, which the old ladder could never report.
- Dependabot evidence now matches the repository's own policy. The report recommended keeping Dependabot disabled while simultaneously warning that it was not enabled and telling the maintainer to turn it on, which is the opposite of what `AGENTS.md` requires. Disabled is the intended state, so the only real question is whether the compensating control ran: `validate-local.ps1` now records every dependency review to a local `reports/dependency-review.json`, and the report reads it. A current, passing review means no warning at all; a missing, stale (older than 7 days), failing or never-run review produces one compensating-control warning naming `npm run review:dependencies`. Nothing generated recommends enabling Dependabot or creating its config any more, and an enabled setting is now reported as the policy violation it is.
- The report now states truthfully whether topic apply mode is available. `metadataHygiene.topicHintPolicy.applyModeAvailable` was hard-coded false while `-ApplyTopics` was implemented and `data/topic-allowlist.json` named 12 repositories, so the evidence described a capability the tree does not have. It is now derived from the same allowlist the apply path reads, alongside `allowlistedRepositoryCount` and, when apply mode is genuinely unavailable, a reason saying why: missing file, malformed JSON, not an array, empty, or an unsafe repository name. `-Check` still never mutates topics.
- The rendered-smoke evidence embedded in the sync report is now aged against its own timestamp. The report restamps `generatedAt` on every run while folding in whatever smoke artifact is on disk, so a report generated minutes ago could carry evidence from weeks earlier and still read as fresh; the old rule only fired when the status was literally `not-run` with no source. The section now records when the smoke evidence was produced, how old it is in hours, and whether it predates the newest commit touching `README.md`, `data/profile-catalog.json` or `scripts/render-profile-smoke.ps1`, and warns with the command to re-run when it does. On the current tree that surfaces evidence 373 hours old. Evidence with no timestamp reports no age rather than a made-up one.
- `validate-local.ps1` now runs the generator's own state check against the working tree and fails on a non-zero exit, naming the report conditions that broke. The documented pre-push command previously ran lint, static analysis, dependency review and Pester, and the test suite only ever exercises the generator against fixtures, so nothing in that lane read the committed README, feed, or assets. A catalog edit that desynced the profile, leaked a suppressed repository or broke a link passed it cleanly. `-SkipProfileCheck` and `-SkipLinkValidation` are available for a faster loop and both announce that the run was reduced.
- Cataloged three public repositories the profile had never seen: GLP-Ultra, HubSpot-Ticket-Refined and ColumnKit. The new lane is what surfaced them.
- Closed a hole that let the project feed publish out of sync. The check that decides whether `projects.json` matches what the catalog produces was a correct comparison ORed with a much weaker one: if the drift model found nothing fatal, the feed was called in sync no matter what had changed. That model only inspects an enumerated list of fields, so anything outside it was exempt. A project's stable ID, canonical repository, aliases, fork and license fields, locale and script hints, and the entire `schemaPolicy` block could all change silently. Tolerance for live upstream churn now lives in one named list of volatile fields that both the equality mask and the drift severity model read, and the comparison alone decides the verdict.

## 2026-09-03

- Cataloged five public repos the profile had never seen: WeightTrack, NoNo, IRL Streamer, BillMinder for PC and OpenRadar. Their absence is what had been failing the daily freshness check since 8/31.
- Stopped a transient GitHub throttle from failing that check. The generator drops from GraphQL to REST pagination on its own when a query gets resource-limited, so a run that recorded `graphql` and a later check that fell back to `rest-fallback` can describe exactly the same 222 repos. That difference now reports as info when the inventory matches and neither side was truncated, which is the same test the `requestedLimit` comparison beside it already used. A provider change with a different repo count still fails.

## 2026-08-23

- Routed every public HTTP fetch in the profile generator through one safe-outbound policy. Requests now require HTTPS with no embedded credentials, reject local and special-purpose IPv4 and IPv6 destinations, fail closed when any DNS result is non-public, disable automatic redirects, and validate each of at most five redirects. The transport pins sockets to the addresses that passed validation, preventing a second DNS answer from changing the destination after policy checks. Link probes remain header-only, while portfolio documents, userscripts, JSON APIs, and capped release downloads share the same guard.
- Made generated file publication recoverable. README, project feed, SVG, optional Backstage, validation cache, and report writes now stage beside their targets with old and new SHA-256 hashes in a durable journal. The proposed generated set is checked in memory before staging. Existing files use atomic replacement, new files use same-volume rename, and the report moves last. Startup repair restores the complete prior set after an interrupted run or keeps a fully committed new set, then removes transaction residue.
- Made offline profile writes fail closed and repeatable. A write now requires a fresh, owner-bound cache snapshot with the complete repository inventory, matching release rows, enumeration provenance, and a nonempty contribution calendar. Snapshot replay preserves the original generation timestamp. Cold, partial, or internally inconsistent caches stop before README, feed, report, or SVG files are opened, while offline checks still emit degraded diagnostics.
- Prevented configured GraphQL page sizes from silently truncating the public repository inventory. A full page now falls back to complete REST pagination, while a page below the configured limit remains on GraphQL. Behavioral coverage proves both paths and confirms REST-only repositories stay in the inventory.
- Reconciled the newly forked `apps.obtainium.imranr.dev` repository as an unchanged upstream reference, keeping it accounted for without presenting it as a SysAdminDoc project.

## 2026-08-20

- Bumped the internal profile evidence version to `v4.10.0`.
- Filled in the missing repository topics for every public project that lacked them, using the hints the sync report already generated. `data/topic-allowlist.json` now names the repositories that `-ApplyTopics` may touch, and the public topic and description gaps are both zero.
- Made repository metadata fetching adapt to GitHub's per-query GraphQL resource limit instead of retrying the same oversized query three times and giving up. A resource-limit error now halves the requested page size (never below the REST pagination floor of 100) before retrying, which is the manual `-GraphQlPageSize` workaround made automatic. The sync report records the effective page size and whether it was reduced.
- Rewrote 69 catalog descriptions that joined two clauses with a dash, so the generated README now reads as separate sentences and contains no em or en dashes.
- Tightened the services header to a single call to action. The old copy ran a four-item list through one sentence and offered two competing links, one of which pointed at a page that no longer exists.
- Pointed `setup.ps1` at Python 3.13 and said so in the generated setup table. Verified with `-CheckOnly` under Windows PowerShell 5.1.
- Noted the post-Manifest-V2 install prerequisite in the extensions section: userscripts need a manager such as Tampermonkey, and Chrome now requires Developer mode.
- Rolled immutable releases out to all 91 release-bearing repositories in the catalog, so every future release is tamper-evident and its assets cannot be swapped after publication. Existing releases stay mutable, which is how the feature works.
- Resolved a contradiction between repository policy and live settings by disabling Dependabot alerts and security updates, which policy bans in every form. The report no longer treats Dependabot as an active control and no longer recommends enabling it; advisory coverage is the local dependency review lane, which runs `npm audit` inside `validate-local.ps1` and fails the build on open advisories. That lane is what surfaced the js-yaml advisory fixed above.
- Narrowed the Start Here routing table from five columns to three. The old "Best category" column duplicated the target of the Action link beside it, and five columns of prose forced horizontal scrolling on phone widths.
- Scoped the rendered-smoke table-overflow warning to pages that actually break. Measurements show the profile page itself never overflows horizontally at 390px while individual wide tables do, which is how GitHub renders wide Markdown tables: each gets its own scroll container. The count is still reported, now alongside a `tableOverflowDisposition` of `contained-table-scroll` or `page-overflow`.
- Enabled immutable releases on this repository and added the setting to the reported security posture. The feature reached general availability on 2025-10-28 and is available on personal repositories, so the previous "may require an organization or paid plan" blocker no longer applies. It is exposed through a dedicated endpoint rather than the repository object, and it only covers releases published after it was turned on.
- Pinned REST calls to an explicit GitHub API calendar version (`2022-11-28`) in the shared `gh` adapter. GitHub shipped its first breaking calendar version on 2026-03-10, and unversioned requests inherit a default that is not guaranteed to stay put. An audit confirmed the generator reads none of the fields that version removes, so migrating later is a deliberate one-line change.
- Made a skipped link-validation run distinguishable from a clean one. `linkValidationSummary` previously reported zero probed targets whether it had validated everything or been skipped entirely, so a skipped lane read as a pass; it now records `skipped` and `skipReason`. Running the lane immediately caught a dead userscript install URL, which is fixed: all 355 link targets now probe clean.
- Retired the dormant hosted generated-PR helper scripts and corrected the review-policy evidence that outlived them. The posture text hard-coded a hosted PR-delivery proof, which contradicted the live branch-protection state once the workflows were removed; it is now derived from actual settings. `scripts/validate-local.ps1` passes end to end again.
- Refreshed the pinned local validation toolchain and cleared a high-severity advisory. The `js-yaml` override moved from 5.2.1 to 5.2.2 for GHSA-pm4m-ph32-ghv5 (exponential parsing time in flow collections), `markdownlint-cli2` to 0.23.2, `zizmor` to a hash-pinned 1.29.0 (skipping 1.27.0, which could log GitHub credentials), Pester to 5.9.1, and the opt-in compatibility lane to Pester 6.1.0. `npm audit` now reports zero vulnerabilities, and `validate-local.ps1` gets past the dependency review that had been failing it.
- Added a per-release-line security floor to the PowerShell runtime posture check. CVE-2026-50523 affects 7.4.0-7.4.18, 7.5.0-7.5.9, and 7.6.0-7.6.4, so an in-support runtime could sit on a vulnerable patch without any warning. `runtimeSecurity.policy` now records the advisory, the patched builds, and whether the active runtime clears them.
- Fixed the frozen `projects.json` timestamp. The feed copied `generatedAt` from the catalog, which only the lossy seed path ever refreshes, so the published feed claimed 2026-06-01 for eleven weeks and the staleness warning could never clear. The feed is now stamped when it is generated, and check-only comparison treats the field as volatile alongside `sourceCommit`, `metadataSnapshotAt`, and `pushedAt`.
- Reconciled the profile catalog with live repository state. Five deleted repositories were dropped, two that went private are now suppressed so visitors never reach a 404, TsunamiSimulator was renamed to Cataclysm with an alias row preserving the redirect history, and seventeen public repositories that had never been cataloged were triaged into categories or suppressed as support and upstream-fork rows. `scripts/sync-profile.ps1 -Check` passes again: missing public repos, private-visibility violations, rename redirects, fork attribution, stale-project review, and license metadata all report zero.
- Demoted two narrow Python utilities to portfolio-only so the Python category stays inside its README soft limit. Both still ship in `projects.json` for the portfolio.
- Pointed the generated profile links at the canonical portfolio origin. The "AI service overview" link previously resolved to a GitHub Pages path that returns 404 since the portfolio moved, and the Start Here and footer portfolio links went through a redirect stub. `Get-ProfilePortfolioUrl` now resolves the configured `-PortfolioUrl` origin, so published links and the cross-surface drift probe can no longer disagree, and falls back to the owner's GitHub Pages origin when no portfolio origin is configured.

## 2026-08-12

- Bumped the internal profile evidence version to `v4.9.161` after draining the active roadmap.

## 2026-07-15

- Added a local support-bundle command and `validate-local.ps1 -SupportBundlePath` integration that package tool versions, validation output, profile-sync evidence, dependency review, and optional setup transcripts into redaction-safe JSON/ZIP diagnostics. Common user paths, tokens, secrets, query credentials, and caller-supplied private values are removed before packaging.
- Added warning-only branch-tip provenance for clone/install actions: `projects.json` rows now carry the advertised branch's observed tip SHA, fetched-at timestamp, and fresh/stale/unreachable state, while the sync report summarizes the evidence without changing branch-current README snippets.
- Added an opt-in redaction-safe Backstage `backstage.io/v1alpha1` Component export with stable names, public owner/lifecycle/tags/links metadata, and report counts for suppressed, private, and metadata-unavailable rows.
- Extended rendered README smoke evidence with `<details>` focus/activation checks, table overflow counts, accessible/actionable link-label counts, and explicit desktop/mobile pass/fail totals; the current GitHub mobile render records its expected table overflow as a warning.
- Added an opt-in Pester 6.0.1 compatibility lane that installs into an isolated temporary module path and runs the non-integration suite, while dependency review documents the lane and the default Pester 5.8.0 validation pin remains unchanged.
- Reconciled ignored working notes with the current local-only workflow and Dependabot posture while preserving historical hosted-automation context and current blocked-roadmap guidance.
- Added an opt-in warning-only portfolio cross-surface probe for the deployed portfolio feed, including source-feed timestamps, portfolio schema version, catalog/live-app/featured counts, and key navigation route availability; external drift or outage never fails local validation.
- Added stable public feed entity IDs, canonical repository/alias metadata, and default `en-US`/`en` plus `Latn` locale/script hints for visible project rows.
- Added feed/report schema migration policy evidence with supported-version windows and required migration notes, plus report checks for duplicate or missing entity identities.
- Added a non-SysAdminDoc catalog fixture covering owner-qualified feed URLs and schema provenance.
- Added an opt-in release verification pilot with GitHub-host allowlisting, per-run asset/byte caps, checksum-sidecar matching, and verified/skipped/failure report rows while preserving metadata-only defaults.
- Aligned Astra-Deck's catalog download kind with its current ZIP/XPI release assets.
- Replaced the generated profile header and footer image chrome with a minimal, text-only header (plain tagline, portfolio and category links) and footer, removing all rendered SVG/image chrome from the profile README while preserving Start Here routing and the full tool catalog.
- Updated the generated-profile smoke renderer to detect the text-only header and footer, and aligned the profile header/experience contract tests to the minimal-header path.
- Bumped the internal profile evidence version to `v4.9.160`.

## 2026-07-08

- Fixed GitHub-rendered profile chrome by replacing sanitized theme `<picture>` blocks with GitHub-visible dark/light image fragments for the generated profile header and footer.
- Added rendered profile smoke evidence for desktop/mobile dark/light screenshots, first-viewport header and Start Here routing, document-level Tool Catalog/footer presence, blank/cropped/overlap checks, and summary/schema fields.
- Wired `scripts/validate-local.ps1` to execute the local dependency review so npm advisory, override, module, and hash-pin drift cannot pass the standard validation command unnoticed.
- Fixed `setup.ps1` readiness gates so missing `pip` fails check-only and final setup validation instead of reporting a false-ready state.
- Bounded real `gh.exe` adapter calls so local validation reports a timed-out GitHub metadata probe instead of hanging indefinitely.
- Routed `-ApplyTopics` topic writes through the same bounded GitHub CLI adapter, including stdin payload handling for `gh api --input -`.
- Bumped the internal profile evidence version to `v4.9.159`.

## 2026-07-07

- Added bounded validation caching for live GitHub metadata, latest-release metadata, and README link probes; `-Check` now reports cache counters, TTL, and fallback use for offline/API-limit runs.
- Bumped the internal profile evidence version to `v4.9.154`.
- Added generated artifact drift diagnostics to profile sync reports and summaries: failed README/feed checks now include normalized SHA-256s, first differing line/section context, affected SVG assets, and the regeneration command.
- Cleared the remaining release/license drift warnings by aligning the Images catalog row to its ZIP release asset and documenting the qBittorrent-Vanced multi-license exception from its repository license files.
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

## Roadmap archive — 2026-08-10 — ROADMAP.md

<details>
<summary>Original roadmap snapshot</summary>

```markdown
# Roadmap

## Research-Driven Additions

### P0

### P1

- [ ] P1 — Persist rendered visual evidence for profile UX parity
  Why: Rendered smoke currently passes viewport/image/overflow checks, but it does not persist screenshot paths or assert first-viewport header, Tool Catalog, and footer presence after the mock-driven redesign.
  Evidence: `scripts/render-profile-smoke.ps1`, `reports/profile-sync-report.json.renderedProfileSmoke`, GitHub dark/light image rendering docs.
  Touches: `scripts/render-profile-smoke.ps1`, `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: smoke output records desktop/mobile dark/light screenshot paths, first-viewport component presence counts, blank/cropped/overlap warnings, and report integration without committing generated PNG artifacts.
  Complexity: M

- [ ] P1 — Add stable public feed entity IDs and alias metadata
  Why: Portfolio consumers currently depend on mutable repo/title values, while catalog systems such as Backstage use stable entity references for rename-safe links and search state.
  Evidence: `schemas/profile-projects.v1.json`, `projects.json.projects[].repo`, Backstage Software Catalog descriptor docs.
  Touches: `schemas/profile-projects.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, downstream `sysadmindoc.github.io` importer.
  Acceptance: each visible project row has a stable `id`, `canonicalRepo`, and optional `aliases`; the report flags duplicate/missing IDs and portfolio compatibility tests prove older consumers can ignore the additive fields.
  Complexity: M

### P2

- [ ] P2 — Generate actionable metadata hygiene handoffs
  Why: The current report still shows 19 missing-topic rows and 1 missing-description row, but the maintainer handoff is indirect.
  Evidence: `reports/profile-sync-report.json.metadataHygiene`, `.github/ISSUE_TEMPLATE/profile-correction.yml`, `scripts/write-profile-sync-summary.ps1`.
  Touches: `scripts/sync-profile.ps1`, `scripts/write-profile-sync-summary.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: summary/report output lists top missing topic/description rows with safe repo names, suggested topic hints, and ready-to-run owner commands or catalog patch guidance without leaking suppressed/private rows.
  Complexity: S

- [ ] P2 — Define feed schema migration and deprecation policy
  Why: `projects.json` is a public portfolio contract with schema validation but no explicit compatibility window or migration signal for consumers.
  Evidence: `projects.json.provenance`, `schemas/profile-projects.v1.json`, `reports/profile-sync-report.json.portfolioCompatibility`, JSON Schema 2020-12 docs.
  Touches: `schemas/profile-projects.v1.json`, `schemas/profile-sync-report.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: feed/report output records schema version compatibility, additive-vs-breaking status, and deprecation notes; tests require a migration note when required feed fields or major schema semantics change.
  Complexity: M

- [ ] P2 — Add portfolio feed locale and script hints
  Why: Full README i18n is not a fit, but downstream Pagefind/static-search consumers benefit from explicit language/script metadata for search tuning.
  Evidence: Pagefind docs and multilingual issues, `projects.json.projects[].searchMetadata`, `schemas/profile-projects.v1.json`.
  Touches: `schemas/profile-projects.v1.json`, `scripts/sync-profile.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: visible project rows may emit optional `localeHints` and `scriptHints` with safe defaults such as `en`/`Latn`; portfolio compatibility remains warning-free and README output stays English-only.
  Complexity: M

- [ ] P2 — Add an opt-in release artifact verification pilot
  Why: Current `releaseTrust` is correctly metadata-only, but a bounded verifier can validate checksum sidecars for small release assets without implying universal binary trust.
  Evidence: `releaseTrust.notesPublic`, `releaseAssetDrift`, GitHub release asset metadata, `schemas/profile-projects.v1.json`, `tests/sync-profile.Tests.ps1`.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `schemas/profile-projects.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: an opt-in switch downloads only capped asset classes with matching checksum sidecars, records verified/skipped/failure counts and reasons, preserves metadata-only default wording, and tests checksum success/mismatch/skip paths.
  Complexity: L

- [ ] P2 — Add redacted local support bundles
  Why: Setup transcripts and validation reports exist, but issue reporters do not have a single redacted diagnostic artifact for local validation/setup failures.
  Evidence: `.github/ISSUE_TEMPLATE/local-validation.yml`, `setup.ps1` transcript logging, `reports/profile-sync-report.json`, `scripts/validate-local.ps1`.
  Touches: `scripts/validate-local.ps1`, a new `scripts/new-support-bundle.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: local validation can create a zip/json bundle containing tool versions, validation output, profile sync report, dependency review summary, and redacted paths/tokens; tests prove private names/secrets are excluded.
  Complexity: M

- [ ] P2 — Reconcile working notes with the current local-only posture
  Why: `CLAUDE.md` still contains many historical GitHub Actions and Dependabot notes while the live `.github` tree has no workflows or Dependabot config, which can mislead future agents.
  Evidence: `CLAUDE.md`, `.github/`, `AGENTS.md`, current repository policy.
  Touches: `CLAUDE.md`.
  Acceptance: working notes clearly mark hosted-workflow/Dependabot history as historical or remove stale operational guidance, while preserving current local validation, feed, and blocked-roadmap instructions.
  Complexity: S

- [ ] P2 — Add branch-tip provenance to clone and install snippets
  Why: README install snippets are branch-pinned for current installs but do not record the branch tip SHA or freshness evidence that a visitor or portfolio consumer can verify.
  Evidence: `README.md` generated clone snippets, `docs/decisions/2026-06-07-userscript-install-posture.md`, GitHub REST refs API behavior.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-projects.v1.json`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: generated feed/report rows record advertised branch, current tip SHA, fetched-at time, and stale/unreachable warning state for branch-backed install actions while keeping branch-current snippets as the README default.
  Complexity: M

- [ ] P2 — Generate an optional Backstage-compatible catalog export
  Why: SysAdminDoc already maintains a structured software catalog; a narrow Backstage export adds integration value without turning the generator into a plugin framework.
  Evidence: Backstage Software Catalog descriptor docs, `projects.json`, `schemas/profile-projects.v1.json`.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`, optional generated YAML/JSON export path.
  Acceptance: an opt-in command emits redaction-safe Backstage Component entries with name, title, owner, lifecycle, tags, links, and repo URL; schema/report tests verify suppressed/private rows cannot leak.
  Complexity: M

- [ ] P2 — Add an owner-agnostic generator fixture
  Why: `scripts/sync-profile.ps1` accepts `-Owner`, but most fixtures and profile assumptions are SysAdminDoc-shaped, so multi-owner support can regress silently.
  Evidence: `scripts/sync-profile.ps1` `Owner` parameter, `tests/sync-profile.Tests.ps1`, GitHub profile README username-repo rules.
  Touches: `tests/sync-profile.Tests.ps1`, `tests/fixtures/`, `scripts/sync-profile.ps1`.
  Acceptance: a small non-SysAdminDoc fixture proves `-Owner` changes schema URLs, repo URLs, profile URLs, and metadata fetch paths without touching the real SysAdminDoc outputs; no private owner/repo names are introduced.
  Complexity: M

### P3

- [ ] P3 — Extend rendered README accessibility smoke checks
  Why: Rendered smoke verifies layout and image health, but the large generated README still needs explicit checks for details/table keyboard and link-label accessibility.
  Evidence: WCAG 2.2, `scripts/render-profile-smoke.ps1`, `reports/profile-sync-report.json.renderedProfileSmoke`, `readmeExperienceChecks`.
  Touches: `scripts/render-profile-smoke.ps1`, `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `tests/sync-profile.Tests.ps1`.
  Acceptance: smoke output records details count, table overflow, unique/actionable link labels, focus/keyboard sanity for collapsed and expanded sections, and desktop/mobile pass/fail counts.
  Complexity: M

- [ ] P3 — Add a Pester 6 compatibility lane
  Why: Pester 6.0.0 release candidates exist and include migration differences, while default validation is pinned to Pester 5.8.0.
  Evidence: Pester v6 migration docs, Pester releases, `scripts/validate-local.ps1`, `tests/sync-profile.Tests.ps1`.
  Touches: `scripts/validate-local.ps1`, `scripts/review-local-dependencies.ps1`, `tests/sync-profile.Tests.ps1`, `README.md`.
  Acceptance: an opt-in local command installs Pester 6 in an isolated module path, runs the non-integration suite, reports compatibility status, and leaves default Pester 5.8 validation unchanged.
  Complexity: M

- [ ] P3 — Add portfolio cross-surface drift probing
  Why: The separate portfolio consumes `projects.json`, but this repo only validates feed shape locally and does not optionally compare deployed portfolio freshness or route counts.
  Evidence: `reports/profile-sync-report.json.portfolioCompatibility`, `projects.json.provenance`, Portfolly/Devfol.io/GitProfile research, Pagefind static-search model.
  Touches: `scripts/sync-profile.ps1`, `schemas/profile-sync-report.v1.json`, `scripts/write-profile-sync-summary.ps1`, `tests/sync-profile.Tests.ps1`.
  Acceptance: `-Check` can optionally probe the deployed portfolio feed timestamp/schema version/key route counts, records warning-only drift or outage evidence, and never fails local validation solely because the external portfolio is unavailable.
  Complexity: M
```

</details>
