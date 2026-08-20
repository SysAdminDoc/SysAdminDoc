# Roadmap

Actionable work only. Historical and completed roadmap material is archived in CHANGELOG.md; blocked work is kept in Roadmap_Blocked.md.

## Actionable Items

## Research-Driven Additions

Added 2026-08-20 from the RESEARCH.md refresh. Every item is traceable to RESEARCH.md evidence.

### P0

- [ ] P0 - Fix dead and non-canonical portfolio links in the profile README
  Why: The hand-authored header links "AI service overview" to sysadmindoc.github.io/ai/ which returns a live 404, and "Full portfolio" links route through the sysadmindoc.github.io redirect stub instead of the canonical portfolio.getparkerai.com origin.
  Evidence: Live fetches 2026-08-20 (RESEARCH.md Security section); repo CLAUDE.md names portfolio.getparkerai.com as the deployed feed target while the README contains 0 links to it.
  Touches: README.md hand-authored header (above the generated marker), the portfolio URL constants in scripts/sync-profile.ps1 (Start Here "Full portfolio" row, portfolioCompatibility consumerContract wording), tests/sync-profile.Tests.ps1. Keep per-project Launch links on sysadmindoc.github.io/<slug>/ since those are separate repos' live Pages.
  Acceptance: No README link returns 404; the portfolio root links point at portfolio.getparkerai.com; sync-profile.ps1 -Check link validation passes with those targets probed.
  Complexity: S

- [ ] P0 - Reconcile the catalog with live repository state
  Why: 7 cataloged repos are no longer public yet still render as README links (privateVisibilityViolations), TsunamiSimulator was renamed to Cataclysm, 15 public repos are absent from the catalog, and winget-pkgs lacks forkOf attribution. This one drift drives the license-missing, stale-project, branch-tip, and fork-attribution warning sections simultaneously.
  Evidence: reports/profile-sync-report.json privateVisibilityViolations, renamedRepoRedirects, missingPublicRepos, forkParentDrift (RESEARCH.md Security section).
  Touches: data/profile-catalog.json (suppress or remove the private set, rename Cataclysm, triage the 15 missing repos into categories or suppression, add forkOf microsoft/winget-pkgs), then regenerate README.md and projects.json.
  Acceptance: privateVisibilityViolations 0, renamedRepoRedirects 0, missingPublicRepos 0 (each triaged), forkParentDrift warningCount 0, and the knock-on license/stale/branch-tip warnings tied to vanished repos are gone.
  Complexity: M

- [ ] P0 - Root-cause the frozen feed timestamp, then republish the feed and release
  Why: projects.json generatedAt is copied from the catalog stamp at scripts/sync-profile.ps1:4897 and nothing refreshes it on -Write, so the published feed says 2026-06-01 and warns forever; the portfolio builds from that feed, and the latest GitHub release (v4.9.153) is 8 versions behind local v4.9.161.
  Evidence: RESEARCH.md Security section; raw projects.json fetch 2026-08-20; profileReleaseConsistency warnings.
  Touches: scripts/sync-profile.ps1 (stamp the feed generatedAt at write time, or restamp the catalog on successful -Write; keep check-only volatile-field normalization intact), tests for the new stamping, then a full -Write / -Check run, commit, tag, and GitHub release so the raw feed is current.
  Acceptance: Published projects.json generatedAt is within 7 days; metadataDriftSummary.generatedAt green; profileReleaseConsistency 0 warnings; portfolio rebuild picks up current data.
  Complexity: M

### P1

- [ ] P1 - Patch the PowerShell runtime and audit data-file parsing
  Why: CVE-2026-50523 (command injection, high) affects pwsh 7.6.0-7.6.4 and the observed runtime is 7.6.3; CVE-2026-26143 concerns Import-PowerShellDataFile -SkipLimitCheck.
  Evidence: RESEARCH.md Security section (fix released 2026-08-14 in 7.6.5).
  Touches: winget upgrade Microsoft.PowerShell on this machine; runtimeSecurity policy floor in scripts/sync-profile.ps1 and its tests; grep scripts/ for -SkipLimitCheck usage.
  Acceptance: reports runtimeSecurity records >= 7.6.5 with 0 warnings; no -SkipLimitCheck usage or each use justified inline.
  Complexity: S

- [ ] P1 - Refresh local validation tool pins
  Why: Pinned tools are behind security or maintenance releases: Pester 5.8.0 -> 5.9.1, opt-in 6.0.1 -> 6.1.0, markdownlint-cli2 0.23.0 -> 0.23.2 (js-yaml doc pin 5.2.1 -> 5.2.2), zizmor 1.26.1 -> 1.29.0 (must skip 1.27.0, credential-logging defect), gh >= 2.97.0 (four advisories, including the attestation-verify matcher bypass that affects the opt-in release verification lane), Node >= 24.18.1.
  Evidence: RESEARCH.md Security section and Sources (verified via GitHub API 2026-08-20).
  Touches: scripts/validate-local.ps1, requirements-local-audit.txt (new hashes), package.json and package-lock.json, scripts/review-local-dependencies.ps1 latest-known values, README validation table, tests/sync-profile.Tests.ps1 pin guards.
  Acceptance: validate-local.ps1 passes end to end on the new pins; dependency review reports 0 pin drift; zizmor 1.27.0 explicitly absent.
  Complexity: M

- [ ] P1 - Pin the REST API version and audit for the 2026-03-10 breaking calendar version
  Why: GitHub's first breaking REST calendar version removes rate from /rate_limit, has_downloads, assignee, and attestation bundle from list responses; unversioned requests keep old behavior for now, but the generator should pin explicitly and migrate deliberately.
  Evidence: RESEARCH.md Security section (changelog 2026-03-12; 2022-11-28 supported at least 24 months).
  Touches: Invoke-GhCli / REST fetch paths in scripts/sync-profile.ps1 (add X-GitHub-Api-Version header), an audit for removed-field consumption, tests.
  Acceptance: All REST calls send an explicit version header; an audit note in code confirms no removed-field reliance; -Check passes against the pinned version.
  Complexity: S

- [ ] P1 - Unblock and adopt immutable releases
  Why: Immutable releases are GA (2025-10-28), free on personal repos, enabled per-repo in Settings, with per-asset Sigstore attestations; the Roadmap_Blocked row's "plan-gated / tag protection 404" blocker is obsolete. The report already consumes the immutable and digest fields (currently 136 of 136 release-bearing rows mutable).
  Evidence: RESEARCH.md Security section; live API verification (cli/cli returns immutable: true).
  Touches: Enable on SysAdminDoc/SysAdminDoc first, then roll out per-repo across release-bearing repos via gh api; update Roadmap_Blocked.md (remove the stale blocker), report wording in scripts/sync-profile.ps1, and releaseImmutability expectations in tests. Note: releases published after enablement cannot be edited or deleted, which is the point; existing releases stay mutable.
  Acceptance: This repo's next release reports immutable: true; releaseAssetDrift.releaseImmutability shows a rising immutable count; stale blocker text gone.
  Complexity: M

- [ ] P1 - Restore link validation in the default check lane
  Why: The 2026-08-12 report ran with linkValidationSummary targetCount 0 (validation skipped) and userscriptInstallTrust skipped, which is exactly why 404 catalog links from the private-visibility set went uncaught.
  Evidence: reports/profile-sync-report.json validationPerformance and linkValidationSummary (RESEARCH.md Security section).
  Touches: scripts/sync-profile.ps1 link-validation gating (find why targetCount was 0: cache path, offline fallback, or a regression), a regression test asserting -Check probes a nonzero target count when online.
  Acceptance: A fresh -Check reports targetCount > 0, userscriptInstallTrust populated, and a test fails if link validation silently skips while online.
  Complexity: S

- [ ] P1 - Root-fix mobile table overflow
  Why: Rendered smoke reports 20 overflow warnings (10 per mobile theme at 390px, root client width 308px): both 5-column Tool Catalog tables, the Start Here routing table, the local-validation table, and the Web Apps table. The blocked promote-to-fatal gate can never land while the baseline is 20.
  Evidence: reports/rendered-profile-smoke.json (RESEARCH.md Security section); Roadmap_Blocked "rendered-smoke mobile viewport overflow regression gate" row (cross-referenced, not duplicated).
  Touches: New-Readme table generators in scripts/sync-profile.ps1 (reduce column counts, shorten kbd labels, or restructure the Tool Catalog cards for narrow viewports), rendered smoke expectations, tests.
  Acceptance: Rendered smoke reports 0 mobile overflow warnings across 3 consecutive runs, after which the blocked promotion row becomes actionable.
  Complexity: M

- [ ] P1 - Retire CI-era dead weight and bring the sync report under budget
  Why: The report exceeds its own soft byte budget (116,051 vs 114,688) while carrying stub fields for deleted CI (generatedPrWriteEvidence stub at scripts/sync-profile.ps1:12713, prDeliveryTransition relics); relic scripts and configs remain (open-generated-profile-pr.ps1, set-generated-validation-status.ps1, CI paths in write-profile-sync-summary.ps1, .github/zizmor.yml with no workflows to scan).
  Evidence: artifactBudgets warning; TODO/debt scan (RESEARCH.md Architecture section).
  Touches: scripts/sync-profile.ps1 (drop stub report fields, update schema required lists in schemas/profile-sync-report.v1.json), delete the two relic scripts, trim write-profile-sync-summary.ps1 to local-summary paths, decide whether the zizmor lane stays (it audits workflows that no longer exist), tests.
  Acceptance: artifactBudgets 0 warnings; relic scripts gone; schema validation passes; validate-local.ps1 green.
  Complexity: M

- [ ] P1 - Resolve the Dependabot repo-setting contradiction
  Why: repositorySettings.security.dependabotSecurityPosture is "enabled" and the repo notes say keep it enabled, while the owner's global rules require Dependabot alerts/updates disabled on sight. One direction must win and be recorded.
  Evidence: RESEARCH.md Security section (policy contradiction).
  Touches: gh api repos/SysAdminDoc/SysAdminDoc/automated-security-fixes -X DELETE and vulnerability-alerts if the global rule wins (default), report expectation in scripts/sync-profile.ps1 plus tests, repo CLAUDE.md gotcha update. The local dependency review lane (npm run review:dependencies) is the compensating control.
  Acceptance: Setting state matches the recorded decision; report expects that state without warning; no contradictory guidance remains in repo docs.
  Complexity: S

- [ ] P1 - Reconcile Roadmap_Blocked.md with the local-only posture
  Why: Five rows reference hosted workflows deleted on 2026-08-12 (scheduled-run evidence, profile-sync.yml/assets-refresh.yml confirmation, workflow_dispatch PR drills, CI-run-gated overflow promotion, Actions dependency locking), one cites an absent TODO.md, the Future Platform State heading is duplicated, and the immutable-releases blocker is obsolete.
  Evidence: RESEARCH.md Architecture section; Roadmap_Blocked.md line-level review 2026-08-20.
  Touches: Roadmap_Blocked.md (delete dead rows, rewrite the overflow-gate row against local smoke runs, dedupe headings, fix the evidence citation), move the immutable-releases row out per its own roadmap item.
  Acceptance: Every remaining blocked row names a blocker that exists today; no row references deleted workflow files.
  Complexity: S

### P2

- [ ] P2 - Execute the blocked topic and description hygiene pass
  Why: 15 public repos lack topics and 1 lacks a description; -ApplyTopics shipped with an empty allowlist and has never run. Topics are the GitHub-side discoverability lever and the report already generates topicHints.
  Evidence: metadataHygiene (RESEARCH.md Security section); Roadmap_Blocked "Apply safe topic and description metadata hygiene fixes" row (this item unblocks it: the allowlist decision is the work).
  Touches: data/topic-allowlist.json (populate from the 15 public rows), sync-profile.ps1 -ApplyTopics run, gh repo edit for the missing description, Roadmap_Blocked.md row removal.
  Acceptance: publicMissingTopicCount 0, missingDescriptionCount 0, allowlist documents which repos may be mutated.
  Complexity: S

- [ ] P2 - Refresh stale local evidence artifacts
  Why: reports/profile-sync-summary.local.md still describes the deleted CI apparatus (Cycle 133, 2026-06-07), and testResults.xml (2026-06-11, 182 of the current 301 tests) and coverage.xml (2026-07-08) lag the suite; all mislead future sessions even though gitignored.
  Evidence: RESEARCH.md Architecture section.
  Touches: Re-run validate-local.ps1 and write-profile-sync-summary.ps1 under the local-only posture (after the dead-weight trim so the summary reflects current sections).
  Acceptance: All three artifacts carry current dates and describe only surviving lanes.
  Complexity: S

- [ ] P2 - Tune the consultant header to 2026 conversion evidence
  Why: Current header has two side-by-side service links, no concrete outcome metric, and a four-item list-in-a-sentence; 2026 consultant-profile guidance converges on one deliberate CTA, one real metric, 30-second scannability.
  Evidence: devbio.me guide 2026-06-08; anti-badge editorial wave (RESEARCH.md Competitive Landscape).
  Touches: README.md hand-authored header only (above the generated marker); keep the compact-header contract tests passing.
  Acceptance: Header has a single primary CTA, one verifiable metric, and copy passing the owner's human-voice rules; readmeExperienceChecks still green.
  Complexity: S

- [ ] P2 - Human-voice retrofit of catalog descriptions
  Why: Generated project rows carry em dashes and three inconsistent dash conventions from descriptionOverride and GitHub descriptions, violating the owner's public-writing rules across the profile's most-read surface.
  Evidence: README editorial review 2026-08-20 (RESEARCH.md Architecture section); owner global human-voice rule.
  Touches: data/profile-catalog.json descriptionOverride fields, optionally a warning-only dash-convention check in the metadata hygiene section, regeneration.
  Acceptance: Generated README contains no em dashes in project descriptions; one dash convention throughout; optional hygiene check reports 0.
  Complexity: M

- [ ] P2 - Add userscript install prerequisites for the post-MV2 reality
  Why: Chrome finished removing Manifest V2 in mid-2025; userscript installs now require Tampermonkey plus the developer-mode/userScripts toggle, and Violentmonkey remains broken on current Chrome. The Extensions section's Install links assume any manager works.
  Evidence: RESEARCH.md cross-repo notes (Grokipedia userscript-manager state, chrome-stats).
  Touches: Extensions category preamble in the New-Readme generator, docs/decisions/2026-06-07-userscript-install-posture.md addendum.
  Acceptance: The Extensions section carries a one-line prerequisite note; userscriptInstallTrust unaffected.
  Complexity: S

- [ ] P2 - Update setup.ps1 to the current Python standard and inspect-path trust cue
  Why: setup.ps1 installs Python.Python.3.12 while the owner standard is 3.13, and 2026 discourse treats bare irm-iex one-liners as a trust smell for exactly this profile's sysadmin audience.
  Evidence: setup.ps1:165; RESEARCH.md cross-repo notes (irm-iex discourse hardening).
  Touches: setup.ps1 winget id and README setup table, plus a short expected-behavior line reinforcing the existing inspect-first path.
  Acceptance: Fresh-machine bootstrap installs Python 3.13; README setup table matches; Windows setup smoke passes on PowerShell 5.1.
  Complexity: S

- [ ] P2 - Schedule a weekly local freshness check
  Why: The report and feed both went stale silently (report 8 days, feed 11 weeks) because nothing runs -Check between working sessions; hosted schedules are banned by policy but local scheduled tasks are the house pattern.
  Evidence: RESEARCH.md Executive Summary; owner precedent (existing daily local scheduled tasks).
  Touches: A small wrapper script plus a Windows scheduled task registering pwsh sync-profile.ps1 -Check with a visible drift summary (no auto-commit; -Write stays a session action).
  Acceptance: Task runs weekly, writes the report, and surfaces warnings where the owner sees them; no unattended pushes.
  Complexity: S

- [ ] P2 - Handle partial GraphQL responses under the new resource limits
  Why: GitHub's 2025-09-01 GraphQL resource limits can return partial responses with resource-limit errors on expensive queries; the generator retries transient 502s but has no explicit partial-response path.
  Evidence: RESEARCH.md Security section (changelog verified).
  Touches: GraphQL fetch and retry paths in scripts/sync-profile.ps1 (detect errors alongside partial data, fall back to REST as with 502s), tests with a partial-response fixture.
  Acceptance: A partial GraphQL response triggers the documented fallback instead of silent partial metadata; test covers it.
  Complexity: S

### P3

- [ ] P3 - Generate distinct action-link labels for assistive tech
  Why: The rendered README carries 1,820 links with 908 duplicate labels (Repo, Install, Download, Launch), a screen-reader pain the smoke currently only tallies.
  Evidence: reports/rendered-profile-smoke.json link audit (RESEARCH.md Security section).
  Touches: Action-label rendering in New-Readme (for example "Download ZeusWatch"), README size budget check (labels add bytes; verify the 96 KiB soft cap holds), smoke expectations.
  Acceptance: Duplicate-label count drops materially without breaching the README byte budget; smoke records the new baseline.
  Complexity: M

- [ ] P3 - Opt-in JSON Feed 1.1 alias export
  Why: A JSON Feed alias of projects.json is a cheap mapping that makes the portfolio consumable by feed readers, matching the existing opt-in export pattern (Backstage) without touching default output.
  Evidence: jsonfeed.org v1.1 (frozen spec); RESEARCH.md Competitive Landscape.
  Touches: A New-JsonFeedExport function beside the Backstage exporter in scripts/sync-profile.ps1, an opt-in switch, schema note, tests.
  Acceptance: Opt-in flag emits a valid JSON Feed 1.1 document from the same catalog data; default artifacts unchanged.
  Complexity: S
