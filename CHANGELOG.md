# Changelog

## 2026-07-01

- Added schema-versioned static search metadata to `projects.json` so portfolio consumers can use stable category, type, and language filters without scraping README sections.
- Polished community docs: enriched CONTRIBUTING.md with pipeline explanation, improved SECURITY.md structure, refined PR template guidance, and fixed stale placeholder references in issue templates.
- Refined header and footer SVG assets: wider accent line, tighter label tracking, dot separators in header; smoother wave proportions in footer. Both themes updated.
- Improved category summary descriptions from generic to action-oriented copy that tells visitors what each section contains.
- Replaced internal jargon in the Start Here routing table with visitor-friendly descriptions.
- Polished setup.ps1 terminal banner and messaging.
- Fixed null-unsafe `ToLowerInvariant()` call in `Get-RepoMeta` that could crash under StrictMode when a catalog entry has a null repo field.
- Fixed `$missingPins` count in `review-local-dependencies.ps1` that nested sub-arrays instead of flattening them, causing the dependency review status to falsely report "ok" when misaligned pins existed.
- Bumped `write-profile-sync-summary.ps1` version requirement from 7.0 to 7.1 to match its use of the ternary operator.
- Added all `scripts/` files to the PSScriptAnalyzer target list so findings in helper scripts are not missed during local validation.
- Removed unused `RunId` parameter from `set-generated-validation-status.ps1`.
- Added `minLength: 1` constraint on catalog and projects schema `title` fields to reject empty-string titles.
- Added `minLength` to the schema keyword compatibility allowlist.
- Added fork attribution fixture entry with `forkOf`, `upstreamLicense`, and `readmeReviewNote` fields for better schema validation coverage.

## 2026-06-30

- Added a local dependency/advisory review command that captures npm audit status, override lock drift, pinned npm tools, PowerShell module pins, and hash-pinned zizmor evidence.
- Hardened markdown hygiene checks so tracked Markdown trailing-whitespace validation handles zero, single, and multiple violations while markdownlint stays limited to public tracked docs.
- Re-labeled release trust, checksum, SBOM, digest, and attestation signals as metadata evidence so the feed and report no longer imply local binary verification.
- Retired generated PR helper side effects so profile automation helpers are offline/manual previews under the local-only validation policy.
- Replaced stale workflow/CI public intake with local-validation issue reporting and local-only audit tooling configuration.
- Made rendered profile smoke evidence local and policy-aware, with passed desktop/mobile evidence folded into the sync report and legacy hosted-artifact warnings removed.
- Added a downstream portfolio feed compatibility fixture that locks required public feed fields, action variants, release-trust metadata, and suppression redaction behavior.
- Split repository security posture reporting into local and hosted controls so removed workflow-only controls no longer blur local validation evidence.
- Added a local validation bootstrap command that installs pinned validation tools before running markdownlint, PSScriptAnalyzer, and Pester.
