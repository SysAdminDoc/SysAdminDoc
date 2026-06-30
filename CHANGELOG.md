# Changelog

## 2026-06-30

- Added a downstream portfolio feed compatibility fixture that locks required public feed fields, action variants, release-trust metadata, and suppression redaction behavior.
- Split repository security posture reporting into local and hosted controls so removed workflow-only controls no longer blur local validation evidence.
- Added a local validation bootstrap command that installs pinned validation tools before running markdownlint, PSScriptAnalyzer, and Pester.
