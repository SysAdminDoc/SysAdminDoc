# Changelog

All notable changes to SysAdminDoc will be documented in this file.

## [v4.8.0] - 2026-05-17

- Added: `data/profile-catalog.json` as the canonical catalog source for profile README entries, explicit suppressions, featured/currently-building flags, install metadata, release labels, and manual description overrides.
- Added: root `projects.json`, generated from the same catalog and live GitHub metadata, so the portfolio site can consume a stable public project feed.
- Added: `scripts/sync-profile.ps1` with `-SeedCatalog`, `-Write`, and `-Check` modes. The check mode writes `reports/profile-sync-report.json` and fails on missing active public repos, private/public visibility mistakes, medical-imaging privacy violations, renamed repo redirects, or generated README drift.
- Added: GitHub Actions automation for scheduled/manual profile sync checks, manual generated-profile PR creation, workflow security auditing with `zizmor`, and OpenSSF Scorecard scanning.
- Added: `.github/CODEOWNERS` plus Dependabot monitoring for GitHub Actions updates.
- Hardened: workflow actions are pinned to commit SHAs and checkout credential persistence is disabled; `zizmor` reports no workflow findings locally.
- Changed: `scripts/sync-profile.ps1 -Check` now validates entrypoint raw URLs, userscript raw URLs, GitHub Pages launch links, and `/releases/latest` redirects.
- Changed: Regenerated `README.md` from catalog + live GitHub metadata. The profile now claims `178+` active public projects, refreshes current star counts, category counts, featured ranking values, release/download links, and branch-pinned install snippets from metadata.
- Added: **OpenLumen**, **PhoneFork**, **AI-Usage_Tracker**, **AdapterLock**, **sysadmindoc.github.io**, and **improve-repo** to the generated catalog/profile where visitor-facing.
- Removed: **EspressoMonkey** duplicate listing after GitHub redirect verification showed it resolves to **ScriptVault**.
- Fixed: **kindred** now links to its repository instead of a missing GitHub Pages site.
- Guarded: **RadAtlas**, **Scripts**, **ChanPrep**, **null**, **project-nomad**, **mnamer**, and **DuplicateFF** now have explicit catalog suppression reasons instead of appearing as unexplained drift.

## [v4.7.0] - 2026-05-11

- Removed: **TeamStation** from Native Desktop Applications — repo went PRIVATE on GitHub, public link was 404'ing for visitors.
- Removed: **DICOM-PACS-Migrator** from Python Desktop Applications — repo is PRIVATE (X-ray repos must be private per global rule), public link was 404'ing.
- Added: **HurricaneMap** + **ApocalypseWatch** to Web Applications.
- Added: **OpenSwift** + **SwiftFloris** + **OpenTasker** to Android Applications.
- Added: **Devicer** + **Snapture** + **OrganizeContacts** to Native Desktop Applications (all C# / .NET 10 WPF).
- Added: **android-debloat-list** to Guides & Resources.
- Changed: Section counts — Python 42 → 41, Web 25 → 27, Android 14 → 17, Native Desktop 10 → 12, Guides 3 → 4.
- Changed: Featured Projects table — refreshed star counts (nvme-patcher 36 → 39, OpenCut 11 → 14, project-nomad-desktop 10 → 11, LibreSpot 9 → 10, Astra-Deck 8 → 9, HostShield 4 → 5). Re-ranked LibreSpot above VideoSubtitleRemover after tie-break by recency.
- Changed: "167+ open source tools" claim in the hero typing SVG + About line — was 165+.

## [v4.6.1] - 2026-05-01

- Removed: **RadAtlas** from Web Applications (no longer in portfolio).
- Changed: Web Applications count 26 → 25.

## [v4.6.0] - 2026-04-30

- Added: **Vantage** to Browser Extensions & Userscripts (new tab dashboard for Chromium — RSS, news, weather, quick links). Ships CRX + XPI + ZIP.
- Added: **AppManagerNG** to Android Applications (power-user package manager — continuation of MuntashirAkon/AppManager, GPL-3.0-or-later).
- Added: **CallShield** restored to Android Applications — repo is public again after being temporarily private (removed in v4.0.0).
- Changed: Section counts — Browser Extensions 21 → 22, Android 12 → 14.
- Changed: Featured Projects table — refreshed star counts (nvme-patcher 35 → 36, OpenCut 10 → 11, VideoSubtitleRemover 9 → 10).
- Changed: "Currently Building" table — replaced stale lineup (MyPortfolio / NovaCut / Astra-Deck / DICOM-PACS-Migrator) with the current high-velocity set: UniversalConverterX (C#/.NET 10), FileOrganizer (C#/Python WinUI 3 shell), AppManagerNG (Kotlin), Vantage (JavaScript). DICOM-PACS-Migrator is private and was 404'ing for visitors.

## [v4.5.0] - 2026-04-26

- Added: `[⬇ Download]` button next to every repo that ships an executable/installable artifact in its latest GitHub release (54 repos audited via `gh release view`). Renders as a `<kbd>`-styled button on GitHub. Each link points at `https://github.com/SysAdminDoc/<repo>/releases/latest` (the redirect URL), so the link stays valid across version bumps without re-editing the README.
- Added: Download column on the Android Applications, Native Desktop Applications, and Security & Networking tables.
- Changed: Browser Extensions & Userscripts table — the Install column now shows `[⬇ CRX]` / `[⬇ ZIP]` for repos that ship packed extension artifacts (Astra-Deck, ScriptVault, AmazonEnhanced, StyleKit, uBlockVanced, StyleCraft, EspressoMonkey, RumbleX, Discrub). Userscripts keep their canonical `[Install](raw...user.js)` link since that's the Tampermonkey/Violentmonkey install URL.
- Changed: Inline-format sections (PowerShell, Python, Media & Conversion) — each qualifying entry's heading line now ends with the download button after the description, so users can grab the prebuilt executable without pasting the clone-install-run one-liner.
- Notes: 99 repos have either no releases at all or release tags with no qualifying binary artifact (e.g. just `.py` / `.user.js` source). They keep the existing copy-paste one-liner only.

## [v4.4.0] - 2026-04-26

- Added: `setup.ps1` — winget-based Python 3.12 + Git installer for novice users. Refreshes `PATH` from the registry post-install so the README install one-liners work in the same shell. Probe-then-install (skips if already present), with machine→user scope fallback.
- Added: "First-time setup" collapsible section at the top of the categories list with the `irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1 | iex` one-liner so new visitors can install prerequisites in one paste.
- Changed: PowerShell section subtitle now states "Requires Git (see First-time setup above)" — was previously silent on the dependency despite every snippet using `git clone`.
- Changed: Python section subtitle now points at the new First-time setup section instead of leaving novices to install Python and Git on their own.

## [v4.3.0] - 2026-04-26

- Changed: All 76 install one-liners standardized to a single clone-install-run pattern. Each snippet now: shallow-clones the repo (`--depth 1 -b <branch>`) into `$env:TEMP\<repo>`, pulls if already present, conditionally `pip install -r requirements.txt` if the file exists, then runs the entry script. This guarantees the snippet works even when a project is refactored into a multi-file package or starts pulling in third-party deps via `requirements.txt`.
- Changed: Python section subtitle clarified — now states "Requires Python 3.8+ and Git" and explains the clone-to-TEMP behavior
- Added: Branch is now pinned per-snippet (`-b main` or `-b master`) so future default-branch changes won't silently break snippets

## [v4.2.0] - 2026-04-26

- Fixed: 16 broken one-liner install snippets after audit of all 87 README install commands
- Fixed: Branch errors (4) — HEICShift, LlamaLink, GmailDownloader, ClearGem default branch is `master`, not `main`
- Fixed: Filename renames/case (10) — NVMe patcher (drop `_v3.0.0`), EXTRACTORX → ExtractorX, AI-Model-Compass → ai_model_compass, DICOM-PACS-Migrator → dicom_migrator, Stock-Video-Collector → artlist_scraper, QuickFind/StreamKeep case
- Fixed: SwiftShot installer moved to `App/` subfolder
- Changed: 6 package-launcher snippets converted from single-file `irm | python` to git-clone snippets — Tunerize, project-nomad-desktop, UniFile, FileOrganizer, Bookmark-Organizer-Pro, StreamKeep (each refactored into multi-file packages where the launcher script imports siblings)

## [v4.1.0] - 2026-04-25

- Changed: Refresh star counts (nvme-patcher 35, OpenCut 10, VideoSubtitleRemover 9, Astra-Deck 8, ZeusWatch/NovaCut 6, DefenderControl 4, etc.)
- Changed: Re-rank Featured Projects by current stars
- Added: 13 missing repos — MyPortfolio, LocalChromeStore, LocalDesktopStore, LocalAndroidStore, TeamStation, Images, one-ui-home-clone, Tunerize, Vertigo, PromptCompanion, AmazonEnhanced, DisableDefender, SunoJump
- Added: octopus-factory, Vigil (fork), TagStudio (fork) to Misc
- Removed: ChanPrep, Scripts (matched portfolio site listing)
- Changed: Currently Building swap — feature MyPortfolio + DICOM-PACS-Migrator
- Changed: Section counts updated (PS 28, Py 42, Web 26, Ext 21, Android 12, Desktop 10, Misc 6)
- Changed: Update repo claim 170+ to 165+ (matches public, non-archived count)

## [v4.0.0] - 2026-04-13

- Changed: Update repo count 160+ to 170+ (173 total)
- Changed: Refresh star counts (nvme-patcher 31, nomad 9, OpenCut 5, VideoSubtitleRemover 4)
- Added: Astra-Deck (7 stars), StreamKeep, Discrub, GifText, GmailDownloader
- Removed: 15 private/archived repos from public listings (bypassnro, Mavenwinutil, NeonNote, NexRay, MavenSort, DarkReaderLocal, CallShield, YTYT-Downloader, ScrollJumper, DiggSuite, gSearchTweaks, HNCC, NextDNSPanel, uScriptStash, DuplicateFF)
- Changed: Renamed InboxForge to GmailDownloader
- Changed: Updated VaultBox language C++ to TypeScript
- Changed: Updated all category counts

## [v3.0.0] - %Y->- (HEAD -> main, origin/main, origin/HEAD)

- Changed: Update profile README with 27 new repos, refreshed stars, and updated sections
- Changed: Update profile README with 25 new repos (150+ total)
- Changed: Update README.md
- Removed: Remove unused snake workflow
- Removed: Remove snake animation from profile
- Changed: Enhance profile README with stats, streak, activity graph, and two-column layout
- Changed: Update README.md
- Removed: Remove stats card, streak stats, and trophies
- Removed: Remove quote, activity graph, pin cards; fix broken stats URLs
- Polish profile: featured projects, top langs, about bullets, dev quote
