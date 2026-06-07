# Decision: Required Check Enforcement Readiness

Date: 2026-06-06
Status: Accepted

## Context

The profile repository has useful validation workflows and partial branch
protection, but the live GitHub settings still do not require status checks
before changes reach `main`. The current protected branch blocks force pushes,
blocks deletion, requires conversation resolution, and applies admin
enforcement. The rulesets API currently returns no repository rulesets.

GitHub's protected-branch documentation warns that required status checks need
unique job names, and GitHub's ruleset documentation says rulesets layer with
branch protection. GitHub's troubleshooting documentation also states that
required status checks are identified by job/check name rather than workflow,
matrix, or event trigger type.

## Decision

Do not enable branch-protection or ruleset required-status-check enforcement
while this loop still delivers by direct pushes to `main` and protected-branch
admin enforcement remains enabled.

The current candidate required checks are:

- `Pester (offline)`
- `PSScriptAnalyzer`
- `Markdownlint`
- `Windows setup smoke`
- `Check generated README`
- `zizmor`

These checks are intentionally backed by workflows that create pull request and
merge-queue checks without `pull_request` path filters. The direct `main` push
path remains guarded by local verification and push-triggered checks, but it is
not compatible with enforcing required checks for administrators before the
repository switches this loop to PR-based delivery or grants an explicit
approved bypass.

As of v4.9.82, `reports/profile-sync-report.json` also records this as
`repositorySettings.requiredCheckReadiness`. The report keeps the candidate
check list, live required-check/ruleset state, admin-enforcement state,
activation recommendation, and blocker list machine-readable without enabling
enforcement.

## Activation Preconditions

- Delivery switches from direct `main` pushes to pull requests, or an approved
  bypass exists for the maintainer/automation actor that runs this loop.
- Candidate job names stay unique and stable.
- `pull_request` and `merge_group` triggers stay unfiltered for the candidate
  workflows.
- Generated-profile PR workflows continue to dispatch branch-scoped profile
  validation after creating automation PRs.
- The selected enforcement mechanism is documented as either branch protection
  or a repository ruleset before it is made active.

## Verification

Current live verification:

- `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection` reports
  `required_status_checks=null`, `required_pull_request_reviews=null`,
  `required_conversation_resolution.enabled=true`, `enforce_admins.enabled=true`,
  `allow_force_pushes.enabled=false`, and `allow_deletions.enabled=false`.
- `gh api repos/SysAdminDoc/SysAdminDoc/rulesets` returns an empty list.
- `gh api repos/SysAdminDoc/SysAdminDoc/rules/branches/main` returns an empty
  list.
- `gh api repos/SysAdminDoc/SysAdminDoc/branches/main/protection/required_status_checks`
  returns `404 Required status checks not enabled`.
- `repositorySettings.requiredCheckReadiness` reports `status=not-enabled`,
  six candidate checks, three blockers, and
  `recommendation=defer-until-pr-delivery-or-bypass`.

When enforcement is activated, verification must include the branch-protection
or rulesets API showing the selected required checks and a pull request proving
that a failing required check blocks merge.
