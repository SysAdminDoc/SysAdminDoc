# SysAdminDoc Project Context

Last consolidated: 2026-05-17
Repository: `C:\Users\--\repos\SysAdminDoc`
Remote: `https://github.com/SysAdminDoc/SysAdminDoc.git`

## Purpose

This repository is the special public GitHub profile README repository for the `SysAdminDoc` account. GitHub displays `README.md` on the profile because the repository is public, matches the username, and contains a root README.

The product surface is not an app. It is a public catalog and trust surface for the user's portfolio of Windows, Android, browser-extension, web, security, media, and guide projects.

## Current Shape

- `README.md` is the rendered public profile.
- `data/profile-catalog.json` is the canonical profile catalog and suppression list.
- `scripts/sync-profile.ps1` seeds, writes, and validates the generated README from catalog data plus live GitHub metadata.
- `reports/profile-sync-report.json` is the latest validation report from `scripts/sync-profile.ps1 -Check`.
- `setup.ps1` is a novice bootstrapper that installs Python 3.12 and Git through WinGet so README install snippets work on fresh Windows machines.
- `CHANGELOG.md` records profile/catalog releases.
- `ROADMAP.md` is the tracked roadmap; P0 catalog truth/privacy work was implemented on 2026-05-17 as v4.8.0.
- `AGENTS.md` and `CLAUDE.md` exist locally but are ignored by git. `AGENTS.md` points to `CLAUDE.md`; `CLAUDE.md` is the local working-notes file.
- `.github/` does not currently exist.

## Current Verified State

Research run date: 2026-05-17
P0 implementation date: 2026-05-17
Version: v4.8.0
Last committed baseline before v4.8.0 work: `1fe3830 Consolidate profile research roadmap`
Branch: `main...origin/main`
GitHub repo visibility: `PUBLIC`
License: MIT
GitHub topics on this repo: `github-profile`, `portfolio`, `readme`

Latest sync validation through `scripts/sync-profile.ps1 -Check` found:

- 178 active public repositories under `SysAdminDoc`.
- 178 catalog entries total.
- 170 entries included in the README.
- 8 public repos explicitly suppressed with reasons.
- 0 missing public repos.
- 0 private visibility violations.
- 0 medical-imaging privacy violations in the generated public README.
- 0 renamed repository redirects.
- `README.md` in sync with generated output.

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

## Architecture

The README is now generated static Markdown. The catalog file is the source of truth for visitor-facing inclusion, suppression decisions, install snippets, release-link labels, featured rows, category placement, and currently-building rows. The sync script joins that catalog with live `gh repo list` metadata for stars, default branches, releases, visibility, descriptions, topics, and primary languages.

## Recommended Next Implementation

1. Add `.github/workflows/profile-sync.yml` in check-only scheduled mode plus manual write mode.
2. Add workflow hardening: least-privilege token permissions, CODEOWNERS review gate, and `zizmor` verification.
3. Extend `scripts/sync-profile.ps1 -Check` with link/install validation for raw userscripts, Pages launch links, and release/latest links.
4. Feed `sysadmindoc.github.io` from the same catalog and move search/filter UX there.
5. Add topic drift reporting and safe repo-description cleanup.

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
