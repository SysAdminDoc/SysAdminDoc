# State Of Repo

Research date: 2026-05-17
Repository: `C:\Users\--\repos\SysAdminDoc`
Branch: `main...origin/main`
HEAD: `3d4ed8f Release v4.7.0 -- catalog refresh, drop private-repo refs`

## Local Shape

Tracked files: `.gitignore`, `CHANGELOG.md`, `LICENSE`, `README.md`, `ROADMAP.md`, `setup.ps1`.

Ignored local instruction files:

- `AGENTS.md`, ignored by `C:/Users/--/.gitignore_global`
- `CLAUDE.md`, ignored by repo `.gitignore`

No `.github/` directory exists, so the repo has no automated README sync, link validation, scheduled catalog refresh, or workflow security posture.

## Recent History

Recent commits show repeated manual catalog maintenance:

- v4.7.0 removed private-repo references and added new repos.
- v4.6.x refreshed sections and currently-building content.
- v4.5.0 added download buttons for repos with binary releases.
- v4.3.0 standardized 76 install one-liners.
- v4.2.0 fixed 16 broken install one-liners.

## Live GitHub Metadata

`gh repo view SysAdminDoc/SysAdminDoc` verified:

- Visibility: `PUBLIC`
- Default branch: `main`
- License: MIT
- Topics: `github-profile`, `portfolio`, `readme`
- Stars: 2

`gh repo list SysAdminDoc --limit 300 --visibility public` plus README parsing found:

- Public repos returned: 178
- Active public repos: 178
- Unique README GitHub repo mentions: 166
- README mentions not in public list: 1
- Active public repos not linked as GitHub repo entries in the README sample: 13
- Star-count mismatches: 18
- Clone branch mismatches: 0
- Release-link gaps: 40
- Release link present but no latestRelease: 1
- Recent active public repos without topics in sample: 25
- Active public repos with empty descriptions in sample: 3

Active public repos missing from README sample: `OpenLumen`, `PhoneFork`, `AI-Usage_Tracker`, `sysadmindoc.github.io` as GitHub repo link, `AdapterLock`, `mnamer`, `improve-repo`, `Scripts`, `RadAtlas`, `DuplicateFF`, `ChanPrep`, `null`, `project-nomad`.

README mention not in public list: `EspressoMonkey`. `gh repo view SysAdminDoc/EspressoMonkey` returned canonical public repo data for `ScriptVault`, indicating a redirect/rename that should be captured in catalog metadata.

## Star Drift

Representative mismatches:

- `win11-nvme-driver-patcher`: README 35/39 depending section, live 40.
- `OpenCut`: README 10/14 depending section, live 16.
- `VideoSubtitleRemover`: README 9/10 depending section, live 13.
- `NovaCut`: README 6, live 7.
- `AppManagerNG`: README 1, live 3.
- `AlarmClockXtreme`: README 1, live 3.

## setup.ps1

The bootstrapper installs Python 3.12 and Git through WinGet, refreshes PATH from registry, and verifies `python`, `pip`, and `git`. It uses exact package IDs, silent install, source/package agreement flags, and machine-to-user fallback.

Risk: the README uses `irm ... | iex` with no inspect-before-run alternative. Microsoft docs note `Invoke-RestMethod` and `Invoke-WebRequest` may not mark downloaded files as internet-zone files, so the setup section should present a safer review path.

## Main Finding

The README is doing too much by hand. The next durable improvement is a structured catalog plus a sync/check script with privacy gates, release-link validation, branch validation, and generated static Markdown.
