# Changelog

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
