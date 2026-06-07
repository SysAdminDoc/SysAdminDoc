# Generated PR Credential Decision

Date: 2026-06-07

## Decision

Decision: Enable GitHub Actions pull-request creation for the repository before
rerunning generated profile PR delivery.

Do not add a PAT or GitHub App secret for this path unless the repository
setting remains unavailable or proves too broad for the required-check rollout.
The manual `write-pr` job already narrows its write surface to `actions: write`,
`contents: write`, `pull-requests: write`, and now `statuses: write` for the
generated validation status context; enabling the repository setting avoids
introducing a new long-lived automation credential.

## Before Activation

Before Cycle 114, the live Actions workflow-permissions endpoint reported:

- `default_workflow_permissions=read`
- `can_approve_pull_request_reviews=false`

Hosted Profile sync run `27085061539` proved the failure mode: the generated
branch was pushed, but `gh pr create` failed with GitHub's
`createPullRequest` permission block, so no pull request was created and no
branch-scoped validation was dispatched.

## Cycle 114 Activation

Cycle 114 applied the selected repository setting. The live endpoint now
reports:

- `default_workflow_permissions=read`
- `can_approve_pull_request_reviews=true`

The local sync report now records:

- `generatedPrCreationAllowed=true`
- `recommendation=ready-for-generated-pr-delivery`
- `generatedPrCredentialDecision.status=setting-enabled`

Hosted run `27086351848` then proved a separate helper preflight issue:
`GITHUB_TOKEN` cannot read the repository workflow-permissions endpoint, so the
helper failed before creating or pushing `automation/profile-sync-27086351848`.
The helper now continues past that known endpoint-read 403 and deletes the
generated branch if pull-request creation fails after a future push.

## Cycle 115 PR Creation Proof

Hosted run `27086701950` proved that the enabled repository setting and helper
fallback can create generated pull requests. The run created branch
`automation/profile-sync-27086701950`, committed
`0e52dce09f34cd292af534f7b08aa35141c47b24`, opened PR #8, and dispatched
branch-scoped Profile sync validation run `27086730286`.

The validation run failed at `Validate generated profile` because the generated
branch check ran `sync-profile.ps1 -Check` against a fresh live metadata
snapshot and reported `projectsExportInSync=false`. PR #8 was closed and the
generated branch was deleted after evidence collection. The Profile sync
workflow now regenerates before checking only on dispatched
`automation/profile-*` branches.

## Cycle 116 Branch Validation Proof

Hosted run `27087015369` proved the regenerated branch validation path. The run
created branch `automation/profile-sync-27087015369`, committed
`787a869f04a4b5a644730c4bba9552875541b76c`, opened PR #9, and dispatched
branch-scoped Profile sync validation run `27087055596`.

Validation run `27087055596` ran `sync-profile.ps1 -Write -Check`, passed, and
uploaded both the `profile-sync-report` and `rendered-profile-smoke` artifacts.
PR #9 was closed and the generated branch was deleted after evidence
collection.

The credential path is therefore sufficient for branch creation, PR creation,
validation dispatch, and cleanup. It does not by itself prove required-check
enforcement readiness: `gh pr checks` and PR `statusCheckRollup` reported no
PR-attached checks for PR #9.

## Cycle 117 Status Handoff

Cycle 117 kept the selected no-new-secret path and added a commit-status
handoff for generated PRs. GitHub documents that repository activity performed
with `GITHUB_TOKEN` does not create follow-up `push` or `pull_request`
workflow runs, so generated PRs cannot rely on natural PR CI unless the repo
switches to an approved GitHub App/PAT credential.

Instead, the helper publishes `generated-profile/validation` as a pending
commit status before PR creation, and the dispatched Profile sync validation
workflow updates the same context after `Check generated README` completes.
Both write surfaces stay job-scoped: generated PR jobs get `statuses: write`,
and normal read-only check jobs remain `contents: read`.

## Selected Path

The applied repository setting command was:

```powershell
gh api -X PUT repos/SysAdminDoc/SysAdminDoc/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```

Next, prove the generated status handoff or document a narrow approved bypass:

- Rerun hosted `write-pr` and confirm generated maintenance PRs surface
  `generated-profile/validation` in the PR check rollup, not only commit-level
  workflow-dispatch check runs.
- Confirm the generated branch cleanup policy leaves no orphaned generated
  branches.
- `repositorySettings.actionsWorkflowPermissions.generatedPrCreationAllowed`
  remains `true` in the next sync report.

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
