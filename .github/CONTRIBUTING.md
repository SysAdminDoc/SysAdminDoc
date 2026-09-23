# Contributing

Contributions, bug reports, and feature requests are welcome through [issues](https://github.com/SysAdminDoc/SysAdminDoc/issues/new/choose).

## How the profile is built

The public `README.md` is generated from two sources:

1. **`data/profile-catalog.json`** -- the canonical list of projects, categories, descriptions, actions, and suppression rules.
2. **`scripts/sync-profile.ps1`** -- reads the catalog plus live GitHub metadata, then renders the full README, `projects.json` feed, and validation report. It holds the parameters, shared constants and the run itself, and loads its functions from `scripts/sync-profile/`, one file per concern.

The header and everything below the `<!-- GENERATED PROFILE CATALOG -->` marker are generated and should not be edited directly.

## Making changes

- **Project metadata** (description, category, action label, order): edit `data/profile-catalog.json`.
- **Generation logic**: README sections and install snippets live in `scripts/sync-profile/readme-render.ps1`, the feed in `feed-export.ps1`, catalog loading in `catalog.ps1`, GitHub calls in `github-api.ps1`, link checks in `link-validation.ps1`, and the report in `profile-state.ps1` plus the `report-*.ps1` files.
- **Profile header** (portfolio link, category nav): edit `New-ProfileChrome` in `scripts/sync-profile/readme-render.ps1`. The tagline is the `$ProfileTagline` constant in `scripts/sync-profile.ps1`.
- **Validation rules**: edit `tests/sync-profile.Tests.ps1`.

## Before submitting

1. Run `.\scripts\sync-profile.ps1 -Check` to verify nothing regresses.
2. Run `pwsh -NoProfile -File .\scripts\validate-local.ps1` for the full local validation suite (markdownlint, PSScriptAnalyzer, Pester).
3. Keep commits focused and conventional (`feat:`, `fix:`, `chore:`).
4. Do not include private repository names, medical data, or employer-specific details in any public content.
