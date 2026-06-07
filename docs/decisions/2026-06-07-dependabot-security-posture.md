# Dependabot Security Posture

Date: 2026-06-07

## Decision

Keep the disabled Dependabot security-updates setting visible as a repository
warning until it is enabled or a manual security-triage policy is documented.
Do not treat local Dependabot version-update configuration as equivalent to
Dependabot security updates.

## Current Evidence

- Repository metadata reports
  `security_and_analysis.dependabot_security_updates.status=disabled`.
- `.github/dependabot.yml` is present.
- Local Dependabot version updates cover `github-actions`.
- Local Dependabot version updates cover `npm`.
- Required status checks and routine pull-request delivery are active, so a
  future security-update PR can use the same required-check path as routine
  maintenance.

## Follow-Up Boundary

This decision does not mutate repository settings. The warning can be resolved
in either of these ways:

1. Enable Dependabot security updates in repository settings and record the
   hosted evidence in `repositorySettings.security.dependabotSecurityPosture`.
2. Record a separate manual security-triage policy that explains why automated
   Dependabot security-update PRs stay disabled for this profile repository.

Until one of those happens, keep
`repositorySettings.security.dependabotSecurityPosture.status=disabled` and keep
the repository warning visible.

## References

- [GitHub Docs: Configuring Dependabot security updates](https://docs.github.com/en/code-security/dependabot/dependabot-security-updates/configuring-dependabot-security-updates)
- [GitHub Docs: Dependabot options reference](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
