# CI Validation Toolchain

Last reviewed: 2026-06-06
Profile release: v4.9.46

This file records the reviewed validation-tool pins used by GitHub Actions.
Keep these pins in reviewable files instead of letting hosted runners resolve
the latest registry release during CI.

## Current Pins

| Tool | Workflow | Pin | Integrity control |
| --- | --- | --- | --- |
| Pester | `.github/workflows/tests.yml` | `5.7.1` | `Install-Module Pester -RequiredVersion 5.7.1` |
| PSScriptAnalyzer | `.github/workflows/tests.yml` | `1.25.0` | `Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0` |
| actionlint | `.github/workflows/workflow-security.yml` | `1.7.12` | Release archive SHA-256 in workflow env |
| zizmor | `.github/workflows/workflow-security.yml` | `1.25.2` | `requirements-ci.txt` hashes plus `--require-hashes --only-binary :all:` |

## Update Process

1. Check the upstream release notes and registry metadata for the target tool.
2. Update the exact version in the workflow or `requirements-ci.txt`.
3. For `zizmor`, refresh every PyPI distribution hash in `requirements-ci.txt`.
4. For `actionlint`, refresh the release archive checksum in the workflow env.
5. Update this file, the changelog, roadmap, completed-work log, and loop state.
6. Run the local validation gate before commit:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Detailed"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1; Invoke-ScriptAnalyzer -Path setup.ps1 -Settings ./PSScriptAnalyzerSettings.psd1"
pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Write -Check
rtk git diff --check
```

## Python Hash Mode Notes

`zizmor` 1.25.2 publishes platform wheels and a source archive on PyPI and does
not declare Python package dependencies. The workflow installs it with
`--no-deps`, `--require-hashes`, and `--only-binary :all:` so CI uses only the
reviewed wheel for the hosted runner platform and fails if the package starts
requiring unpinned dependencies or if PyPI serves an unreviewed artifact.
