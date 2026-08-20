# Roadmap

Actionable work only. Historical and completed roadmap material is archived in CHANGELOG.md; blocked work is kept in Roadmap_Blocked.md.

## Actionable Items

## Research-Driven Additions

Added 2026-08-20 from the RESEARCH.md refresh. Every item is traceable to RESEARCH.md evidence.

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

- [ ] P2 - Schedule a weekly local freshness check
  Why: The report and feed both went stale silently (report 8 days, feed 11 weeks) because nothing runs -Check between working sessions; hosted schedules are banned by policy but local scheduled tasks are the house pattern.
  Evidence: RESEARCH.md Executive Summary; owner precedent (existing daily local scheduled tasks).
  Touches: A small wrapper script plus a Windows scheduled task registering pwsh sync-profile.ps1 -Check with a visible drift summary (no auto-commit; -Write stays a session action).
  Acceptance: Task runs weekly, writes the report, and surfaces warnings where the owner sees them; no unattended pushes.
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
