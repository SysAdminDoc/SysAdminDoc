# SysAdminDoc Project Context

Last consolidated: 2026-05-17
Repository: `C:\Users\--\repos\SysAdminDoc`
Remote: `https://github.com/SysAdminDoc/SysAdminDoc.git`

## Purpose

This repository is the special public GitHub profile README repository for the `SysAdminDoc` account. GitHub displays `README.md` on the profile because the repository is public, matches the username, and contains a root README.

The product surface is not an app. It is a public catalog and trust surface for the user's portfolio of Windows, Android, browser-extension, web, security, media, and guide projects.

## Current Shape

- `README.md` is the rendered public profile.
- `setup.ps1` is a novice bootstrapper that installs Python 3.12 and Git through WinGet so README install snippets work on fresh Windows machines.
- `CHANGELOG.md` records profile/catalog releases.
- `ROADMAP.md` is the tracked roadmap and was rewritten on 2026-05-17 into an evidence-backed plan.
- `AGENTS.md` and `CLAUDE.md` exist locally but are ignored by git. `AGENTS.md` points to `CLAUDE.md`; `CLAUDE.md` is the local working-notes file.
- `.github/` does not currently exist.

## Current Verified State

Research run date: 2026-05-17
HEAD: `3d4ed8f Release v4.7.0 -- catalog refresh, drop private-repo refs`
Branch: `main...origin/main`
GitHub repo visibility: `PUBLIC`
License: MIT
GitHub topics on this repo: `github-profile`, `portfolio`, `readme`

Live GitHub metadata gathered through `gh` found:

- 178 active public repositories under `SysAdminDoc`.
- 166 unique `github.com/SysAdminDoc/...` repo mentions in the README.
- 13 active public repos not linked as GitHub repo entries in the README sample.
- 18 README star-count mismatches.
- 40 mentioned repos with `latestRelease` but no `/releases/latest` link.
- 0 clone-snippet default-branch mismatches.
- 25 recent active public repos in the sample without repository topics.
- 3 active public repos in the sample with empty descriptions.

## Project Philosophy

The README should be:

- Public-only: private repos must not appear as dead links.
- Visitor-focused: fast scanning, accurate descriptions, working install/download paths.
- Windows-first: PowerShell install snippets and setup flow are first-class.
- Zero-config: the public promise is "download it, launch it, done."
- Catalog-style: the README should summarize and route; richer exploration belongs on the portfolio site.
- Generated where possible: counts, stars, release links, default branches, and public/private status should not be hand-maintained.

## Critical Rules

- Only list public repos in `README.md`.
- Medical imaging, X-ray, DICOM, PACS, and related repos must stay private unless explicitly overridden.
- Use the standardized clone-install-run snippet pattern documented in `CLAUDE.md`.
- Pin clone snippets to the live default branch.
- Userscript install links should remain raw `*.user.js` URLs when that is the canonical Tampermonkey/Violentmonkey flow.
- Repos with executable release artifacts should get `/releases/latest` download links.
- Do not put JavaScript search/filter controls inside the GitHub README. GitHub sanitizes README HTML before rendering.

## Main Architectural Gap

The README is currently the data source, presentation layer, and release checklist all at once. That is why drift appears quickly. The durable fix is a canonical catalog file plus a sync/validation script that regenerates static Markdown and feeds the portfolio site.

## Recommended Next Implementation

1. Create `data/profile-catalog.json`.
2. Create `scripts/sync-profile.ps1` with `-Check` and `-Write` modes.
3. Add a generated README refresh as v4.8.0.
4. Add `.github/workflows/profile-sync.yml` after the script works locally.
5. Feed `sysadmindoc.github.io` from the same catalog and move search/filter UX there.

## Research Artifacts

The 2026-05-17 research run lives in `.ai/research/2026-05-17/`.

Key files:

- `STATE_OF_REPO.md`
- `MEMORY_CONSOLIDATION.md`
- `SOURCE_REGISTER.md`
- `RESEARCH_LOG.md`
- `COMPETITOR_MATRIX.md`
- `FEATURE_BACKLOG.md`
- `PRIORITIZATION_MATRIX.md`
- `SECURITY_AND_DEPENDENCY_REVIEW.md`
- `DATASET_MODEL_INTEGRATION_REVIEW.md`
- `CHANGESET_SUMMARY.md`
