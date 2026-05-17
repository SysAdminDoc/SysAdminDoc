# Memory Consolidation

Research date: 2026-05-17

## Sources Inspected

Local:

- `AGENTS.md`
- `CLAUDE.md`
- Existing `ROADMAP.md`
- `CHANGELOG.md`
- `README.md`
- `setup.ps1`

Shared/global:

- `C:/Users/--/.claude/CLAUDE.md`
- `C:/Users/--/CLAUDE.md`
- `C:/Users/--/.claude/projects/c--Users----repos/memory/MEMORY.md`
- `C:/Users/--/.claude/projects/c--Users----repos/memory/stack-powershell.md`
- `C:/Users/--/.claude/projects/c--Users----repos/memory/stack-web.md`

Codex memory was searched for `SysAdminDoc`, `sysadmin`, and documentation terms. No specific prior profile-roadmap memory was found.

## Durable Facts Consolidated

- This is the `SysAdminDoc` GitHub profile README repository.
- It must list public repos only.
- Medical/X-ray/DICOM/PACS-related repos must remain private unless explicitly overridden.
- `setup.ps1` exists for novice Python/Git setup.
- README install snippets should use the standardized clone-install-run pattern.
- Branches must be checked per repo; not every repo uses `main`.
- Userscript install URLs should remain raw `*.user.js` URLs.
- Repos with executable release artifacts should get `/releases/latest` links.
- `AGENTS.md` and `CLAUDE.md` are local tool files and ignored by git.

Root `PROJECT_CONTEXT.md` now holds the canonical consolidated project memory.

## Reconciled Plans

The old roadmap contained useful ideas: star automation, generated tables, live project strips, portfolio integration, metrics, link linting, and awesome-list discovery. These were retained but reprioritized around the verified drift problem.

The old roadmap also proposed inline README JavaScript search/filter. That is now redirected to the portfolio site because GitHub sanitizes README HTML.

## Conflicts

- Shared rules require `rtk`; this environment does not have `rtk`. Plain `git` and `gh` were used and documented.
- Shared rules discourage AI-agent repo artifacts; the user explicitly required `.ai/research/<date>/`, so the explicit task wins.
- Shared rules say no tests unless requested; this repo has no build target, so verification used metadata, git, and static checks.
- Some public repos are missing from the README but may have been intentionally removed. The future catalog must support explicit `omitReason`.

## Open Questions For Future Work

- Should the README public-project count mean all active public repos or curated listed repos?
- Should `sysadmindoc.github.io` be linked as a live site only or also as a GitHub repository?
- Which omitted public repos should be intentionally suppressed from the public profile?
