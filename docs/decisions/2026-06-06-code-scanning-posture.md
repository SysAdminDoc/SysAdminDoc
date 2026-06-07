# Decision: Code Scanning Posture

Date: 2026-06-06
Status: Accepted

## Context

The profile repository uses security and workflow validation controls, but its
live GitHub language accounting currently reports a PowerShell-only source mix.
GitHub's CodeQL supported-language list does not include PowerShell. Enabling a
CodeQL workflow or chasing default setup for this repository would not add
meaningful source-code scanning coverage until a supported source language is
introduced.

The repository already publishes security signal through OpenSSF Scorecard
SARIF upload, `PSScriptAnalyzer`, `actionlint`, `zizmor`, secret scanning, and
secret-scanning push protection.

## Decision

Do not add a CodeQL analysis workflow for the current PowerShell-only profile
repository. Treat missing CodeQL analysis as not applicable, not as a
misconfiguration, while the live language list has no CodeQL-supported source
language.

`scripts/sync-profile.ps1 -Check` records this as
`repositorySettings.security.codeScanning.status=not-applicable` with
`recommendation=not-applicable-powershell-only`.

Scorecard alert posture is informational. The normal profile sync check queries
the code-scanning alerts API when the current token can read it and records the
result under `repositorySettings.security.codeScanning.scorecardAlertPosture`.
If the API is unavailable, profile sync keeps running and records an unavailable
posture instead of requiring extra alert or security API scopes.

## Reopen Criteria

Reopen this decision when live repository languages include a CodeQL-supported
source language such as JavaScript, TypeScript, Python, C#, Java/Kotlin, Go,
Ruby, Rust, Swift, or C/C++. At that point the repository should either enable
CodeQL default or advanced setup, or document a different SARIF-producing
analyzer that covers the supported language.

## Verification

Current verification:

- `gh api repos/SysAdminDoc/SysAdminDoc/languages` reports `PowerShell`.
- `.github/workflows/scorecard.yml` uploads Scorecard SARIF through
  `github/codeql-action/upload-sarif`.
- `.github/workflows/tests.yml` runs `PSScriptAnalyzer`.
- `.github/workflows/workflow-security.yml` runs `actionlint` and `zizmor`.
- The latest reviewed Scorecard alert posture records 5 open Scorecard alerts:
  1 local hosted-refresh item after the `SECURITY.md` reporting-link fix, 2
  external-gated governance items, and 2 accepted Scorecard limitations for the
  current PowerShell-only profile generator.

Source notes:

- GitHub CodeQL supported languages:
  `https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning-with-codeql`
- GitHub SARIF upload:
  `https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github`
