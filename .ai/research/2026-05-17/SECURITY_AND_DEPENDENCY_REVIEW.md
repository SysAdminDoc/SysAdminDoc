# Security And Dependency Review

Research date: 2026-05-17

## Current Dependency Surface

This repo has no package manifest and no build dependency graph. Its real dependencies are:

- GitHub-rendered Markdown.
- External image/widget services in `README.md`.
- `setup.ps1` invoking WinGet.
- Future GitHub Actions automation.
- GitHub API/CLI metadata for maintenance.

## External README Services

Current widgets include capsule-render, readme-typing-svg, Komarev, Shields.io, skill-icons, github-readme-stats, streak-stats, and activity graph.

Risks:

- Outage/rate-limit can degrade the profile.
- Query strings can drift.
- Dynamic widgets can cache stale data.
- External services can change rendering.

Mitigation: keep widgets decorative and generate authoritative catalog data statically.

## README Execution Constraint

GitHub Markup sanitizes rendered README HTML and removes risky markup including script tags and inline styles. Therefore:

- Do not build README JavaScript search/filter.
- Keep README as generated static Markdown.
- Put interactive search/filter on `sysadmindoc.github.io`.

## setup.ps1

Strengths:

- Exact WinGet package IDs.
- Silent install and agreement flags.
- Machine-scope then user-scope fallback.
- PATH refresh and verification for Python, pip, and Git.

Risks:

- README recommends `irm ... | iex`.
- Microsoft docs note `Invoke-RestMethod` and `Invoke-WebRequest` may not mark downloaded files as internet-zone files.
- No inspect-before-run alternative.
- No explicit PowerShell version requirement.
- No persistent setup log.

Recommended hardening:

- Add a safer download/inspect/run path in README.
- Add `#Requires -Version 5.1`.
- Consider `-CheckOnly`.
- Add setup logging.

## Future GitHub Actions

No workflows exist yet. When added:

- Use explicit least-privilege `permissions`.
- Schedule away from top of hour.
- Start with check-only jobs.
- Add CODEOWNERS for workflow files.
- Run `zizmor`.
- Add OpenSSF Scorecard after automation exists.
- Use Dependabot/action monitoring deliberately, documenting the SHA-pinning tradeoff.

## Privacy

The README must not include private repo links. A sync script should:

- Query live visibility before output.
- Refuse private repos.
- Enforce medical/X-ray/DICOM/PACS keyword gates.
- Require explicit allowlists for sensitive exceptions.
- Keep private reports local.
