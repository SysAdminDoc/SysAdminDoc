# Routine Maintenance PR Delivery

Date: 2026-06-07

## Decision

Select pull-request delivery for routine maintenance. This document originally
recorded the pre-enforcement decision; Cycle 129 later enabled branch-protection
required checks after the delivery path was proven, and Cycle 130 recorded the
first enforced routine PR proof. Direct-main bypass remains unapproved.

Protected `main` has `enforce_admins.enabled=true` and strict required status
checks for the six candidate checks. Pull-request delivery avoids the rejected
direct-push path while preserving the control being prepared. GitHub's
branch-protection documentation says admin restrictions are optional unless
applied to administrators, while this repository applies them. GitHub rulesets
can grant bypass permissions to repository roles, teams, users, or GitHub Apps,
but adding a bypass without a narrow actor model would weaken the control.

The selected path is now:

1. Keep direct-main bypass unapproved.
2. Deliver routine maintenance through a normal branch and pull request.
3. Wait for the six candidate checks already proven by PR #13 and PR #14.
4. Merge without bypass after all required checks pass.
5. Record merged PR proof in `routineMaintenancePrDrillEvidence` and
   `requiredCheckEnforcementEvidence`.

This decision does not create a ruleset or approve a bypass. It records the
delivery policy that supports active branch-protection enforcement.

## Current Evidence

- Branch protection is readable and reports `enforce_admins.enabled=true`,
  strict required status checks for `Pester (offline)`, `PSScriptAnalyzer`,
  `Markdownlint`, `Windows setup smoke`, `Check generated README`, and
  `zizmor`, `required_pull_request_reviews=null`,
  `required_conversation_resolution.enabled=true`,
  `allow_force_pushes.enabled=false`, and `allow_deletions.enabled=false`.
- Repository rulesets are readable and currently return `[]`.
- PR #13 proved all six candidate required-check names complete successfully on
  a pull request.
- PR #14 proved normal routine-maintenance PR delivery: it merged by rebase from
  the `routine-pr-drill-evidence` branch after `Check generated README`,
  `PSScriptAnalyzer`, `Pester (offline)`, `Markdownlint`,
  `Windows setup smoke`, and `zizmor` all passed.
- PR #16 proved normal routine-maintenance PR delivery under active
  branch-protection required checks after the same six required checks passed.
- Generated-profile maintenance PR delivery is already proven separately by
  PR #10 and `generated-profile/validation`.
- `routineMaintenancePrDrillEvidence` records PR #14, head SHA
  `65475b7b47fc1e33a96843a131108b2660b18d19`, merge SHA
  `64e02f3b4b9737f77b4629052dabc9f449e261bb`, workflow run IDs
  `27090770215`, `27090770193`, and `27090770203`, rebase merge method, and
  deleted-branch cleanup.
- `requiredCheckEnforcementEvidence` records PR #16, head SHA
  `8575e324182b96527bb9b58420d5ff44e3c05c06`, merge SHA
  `dc05296386af847d4e89803f1ed3ac966df49fb7`, workflow run IDs
  `27091837034`, `27091837025`, and `27091837036`, profile-sync artifact
  `7463884699`, rendered-smoke artifact `7463884770`, rebase merge method,
  and deleted-branch cleanup.

## References

- [GitHub Docs: About protected branches](https://docs.github.com/articles/types-of-required-status-checks)
- [GitHub Docs: Creating rulesets for a repository](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)
- [GitHub Docs: Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
