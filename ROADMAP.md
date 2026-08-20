# Roadmap

Actionable work only. Historical and completed roadmap material is archived in CHANGELOG.md; blocked work is kept in Roadmap_Blocked.md.

## Actionable Items

## Research-Driven Additions

Added 2026-08-20 from the RESEARCH.md refresh. Every item is traceable to RESEARCH.md evidence.

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
