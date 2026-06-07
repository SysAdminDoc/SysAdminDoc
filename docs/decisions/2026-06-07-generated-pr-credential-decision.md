# Generated PR Credential Decision

Date: 2026-06-07

## Decision

Decision: Enable GitHub Actions pull-request creation for the repository before
rerunning generated profile PR delivery.

Do not add a PAT or GitHub App secret for this path unless the repository
setting remains unavailable or proves too broad for the required-check rollout.
The manual `write-pr` job already narrows its write surface to `actions: write`,
`contents: write`, and `pull-requests: write`; enabling the repository setting
avoids introducing a new long-lived automation credential.

## Current Evidence

The live Actions workflow-permissions endpoint currently reports:

- `default_workflow_permissions=read`
- `can_approve_pull_request_reviews=false`

Hosted Profile sync run `27085061539` proved the failure mode: the generated
branch was pushed, but `gh pr create` failed with GitHub's
`createPullRequest` permission block, so no pull request was created and no
branch-scoped validation was dispatched.

## Selected Path

Enable the repository setting with:

```powershell
gh api -X PUT repos/SysAdminDoc/SysAdminDoc/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```

Then rerun the hosted Profile sync `write-pr` workflow and verify:

- A generated pull request is created.
- Branch-scoped Profile sync validation is dispatched.
- The generated branch cleanup policy leaves no orphaned generated branches.
- `repositorySettings.actionsWorkflowPermissions.generatedPrCreationAllowed`
  becomes `true` in the next sync report.

## Rejected Path

An approved GitHub App or PAT credential remains the fallback path, not the
primary path. It would add secret storage, rotation, and review burden for a
workflow that can already be limited by job-level permissions plus the
repository Actions setting.

## Enforcement Boundary

This decision does not enable required-check enforcement. Required checks should
wait until generated PR delivery is proven with a live pull request, recent
candidate checks complete successfully, and the branch-protection or ruleset
activation step is recorded in the sync report.
