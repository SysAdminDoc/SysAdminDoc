# Routine Maintenance PR Delivery

Date: 2026-06-07

## Decision

Select pull-request delivery for routine maintenance before required-check
enforcement. Do not approve a direct-main bypass actor in this pass, and do not
enable required status checks yet.

Protected `main` currently has `enforce_admins.enabled=true`. If required
status checks are enabled through branch protection while this maintenance loop
continues pushing directly to `main`, future direct pushes can be rejected
before checks exist for the pushed commit. GitHub's branch-protection
documentation says admin restrictions are optional unless applied to
administrators, while this repository already applies them. GitHub rulesets can
grant bypass permissions to repository roles, teams, users, or GitHub Apps, but
adding a bypass without a narrow actor model would weaken the control being
prepared.

The selected path is:

1. Keep direct-main bypass unapproved.
2. Deliver routine maintenance through a normal branch and pull request.
3. Wait for the six candidate checks already proven by PR #13.
4. Merge without bypass.
5. Record the merged PR number, head SHA, merge SHA, check run IDs, and cleanup
   state in `routineMaintenancePrDrillEvidence` in the next sync report.

This decision does not change branch protection, create a ruleset, require pull
request reviews, or enable required status checks. It only records the delivery
policy that must be proven before enforcement can be safely enabled.

## Current Evidence

- Branch protection is readable and reports `enforce_admins.enabled=true`,
  `required_status_checks=null`, `required_pull_request_reviews=null`,
  `required_conversation_resolution.enabled=true`,
  `allow_force_pushes.enabled=false`, and `allow_deletions.enabled=false`.
- Repository rulesets are readable and currently return `[]`.
- PR #13 proved all six candidate required-check names complete successfully on
  a pull request.
- Generated-profile maintenance PR delivery is already proven separately by
  PR #10 and `generated-profile/validation`, but routine non-generated
  maintenance still needs a live merge drill.
- `routineMaintenancePrDrillEvidence` is present in the sync report as the
  pending evidence slot for that merged routine-maintenance PR.

## References

- [GitHub Docs: About protected branches](https://docs.github.com/articles/types-of-required-status-checks)
- [GitHub Docs: Creating rulesets for a repository](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)
- [GitHub Docs: Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
