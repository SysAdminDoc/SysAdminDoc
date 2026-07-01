# Contributing

Contributions, bug reports, and feature requests are welcome through [issues](https://github.com/SysAdminDoc/SysAdminDoc/issues/new/choose).

## How the profile is built

The public `README.md` is generated from two sources:

1. **`data/profile-catalog.json`** -- the canonical list of projects, categories, descriptions, actions, and suppression rules.
2. **`scripts/sync-profile.ps1`** -- reads the catalog plus live GitHub metadata, then renders the full README, `projects.json` feed, validation report, and profile SVG assets.

The hand-authored header (above the `<!-- GENERATED PROFILE CATALOG -->` marker) is preserved across regenerations. Everything below it is generated and should not be edited directly.

## Making changes

- **Project metadata** (description, category, action label, order): edit `data/profile-catalog.json`.
- **Generation logic** (section layout, install snippet format, feed schema): edit `scripts/sync-profile.ps1`.
- **Profile header** (tagline, portfolio link, category nav): edit the top of `README.md` directly.
- **Validation rules**: edit `tests/sync-profile.Tests.ps1`.

## Before submitting

1. Run `.\scripts\sync-profile.ps1 -Check` to verify nothing regresses.
2. Run `pwsh -NoProfile -File .\scripts\validate-local.ps1` for the full local validation suite (markdownlint, PSScriptAnalyzer, Pester).
3. Keep commits focused and conventional (`feat:`, `fix:`, `chore:`).
4. Do not include private repository names, medical data, or employer-specific details in any public content.
