# PR Delivery Transition Checklist

Date: 2026-06-07

## Decision

Do not enable required-check enforcement yet. The repo has stable candidate
checks, pull request triggers, and merge queue triggers, but the maintenance
delivery path still pushes directly to `main`. Because protected `main` has
admin enforcement enabled, required checks would reject that delivery path until
the repo switches to PR-based delivery or documents and tests a narrow approved
bypass.

Cycle 110 live evidence confirmed one additional blocker: the repository's
GitHub Actions workflow permissions currently use `default_workflow_permissions=read`
and `can_approve_pull_request_reviews=false`. GitHub documents the
"Allow GitHub Actions to create and approve pull requests" setting as the
control for whether `GITHUB_TOKEN` can create or approve pull requests:
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#preventing-github-actions-from-creating-or-approving-pull-requests.

Cycle 117 research confirmed the remaining PR-check-rollup blocker: GitHub
does not create follow-up `push` or `pull_request` workflow runs from
repository activity performed with `GITHUB_TOKEN`. To avoid adding a PAT or
GitHub App secret just for generated profile maintenance, generated PR delivery
now publishes a commit-status context, `generated-profile/validation`, on the
generated branch head SHA.

## Checklist

| Item | Status | Evidence | Next action |
| --- | --- | --- | --- |
| Candidate required checks | Ready | `Pester (offline)`, `PSScriptAnalyzer`, `Markdownlint`, `Windows setup smoke`, `Check generated README`, and `zizmor` are defined with stable workflow-backed names. | Keep job names unique and unchanged before enforcement. |
| Candidate workflow coverage | Ready | Tests, Profile sync, and Workflow security all create checks on `pull_request` and `merge_group`, and PR triggers are not path-filtered. | Keep required-check candidate workflows always-created for PRs and merge queue runs. |
| Recent successful check runs | Needs live validation | GitHub requires status checks to have completed recently in the repository before they can be selected as required checks. | Open or refresh a disposable PR immediately before enforcement and verify every candidate check completes. |
| PR delivery or bypass | Blocked | Generated PR creation and branch-scoped workflow-dispatch validation now work, but PR #9 reported no PR-attached check rollup and routine maintenance still pushes directly to `main` while branch protection has `enforce_admins.enabled=true`. Cycle 117 adds the `generated-profile/validation` commit-status handoff, with live PR-rollup proof still pending. | Prove PR-attached generated maintenance checks by rerunning hosted `write-pr` and verifying `generated-profile/validation` appears in `statusCheckRollup`, or document and test a narrow approved bypass before enabling required checks. |
| Enforcement mechanism | Blocked | Branch protection and repository rulesets are currently readable and non-enforcing for required checks. | After PR delivery is proven, enable either branch-protection required checks or one repository ruleset, then re-query live settings. |

## Activation Order

1. GitHub Actions pull-request creation for `GITHUB_TOKEN` is enabled as of
   Cycle 114. Keep default workflow permissions at `read`.
2. Re-run the Profile sync `write-pr` workflow against a disposable generated
   branch and confirm it creates a pull request, dispatches branch-scoped
   Profile sync validation, publishes `generated-profile/validation`, and
   leaves no orphaned branch after cleanup.
3. Open a disposable PR that exercises the required-check surface without
   intentionally invalidating generated README output.
4. Confirm all six candidate checks are created on the PR and on `merge_group`.
5. Confirm each candidate check has completed successfully in this repository
   within GitHub's selection window.
6. Switch routine maintenance to PR delivery, or document an approved bypass and
   prove it works.
7. Enable one enforcement mechanism only after the delivery path is proven.
8. Re-run `scripts/sync-profile.ps1 -Check` and confirm
   `repositorySettings.requiredCheckReadiness` and `prDeliveryTransition`
   reflect the new state.

## Cycle 110 Live Write-PR Drill

On 2026-06-07, hosted Profile sync run
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27085061539` ran
`workflow_dispatch` mode `write-pr` on `main` at
`e0eba1d6d54a4112f9151e55245dd589f7c19d50`.

The run completed `Regenerate profile`, wrote the generated PR summary, uploaded
`profile-sync-report` artifact `7461506616`, created commit
`cfbdac4a6431c8ee7ad8e79b573f31a8a3380946` on
`automation/profile-sync-27085061539`, and pushed that disposable branch.
`gh pr create` then failed with:

`GraphQL: GitHub Actions is not permitted to create or approve pull requests (createPullRequest)`

No pull request was created, no branch-scoped validation was dispatched, and the
disposable branch was deleted after evidence collection. The helper now
preflights `repos/SysAdminDoc/SysAdminDoc/actions/permissions/workflow` before
branch creation when running in GitHub Actions, so this disabled setting fails
before a future automation branch is pushed.

## Cycle 114 Live Setting Activation

On 2026-06-07, the repository workflow-permissions setting was updated to keep
`default_workflow_permissions=read` while setting
`can_approve_pull_request_reviews=true`. Local admin-token evidence now reports
`generatedPrCreationAllowed=true` and
`recommendation=ready-for-generated-pr-delivery`.

Hosted Profile sync run
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27086351848` then ran
`write-pr` mode on `main` at
`e0aaf1a5e94eb0be19e9a550ea75059f834db2a7`. The run regenerated profile
artifacts and uploaded `profile-sync-report` artifact `7461985005`, but the
helper failed before branch creation because `GITHUB_TOKEN` received
`Resource not accessible by integration (HTTP 403)` when reading the repository
workflow-permissions endpoint. No generated branch, pull request, or
branch-scoped validation was created.

The helper now treats that specific endpoint-read 403 as an unavailable
preflight and continues to `gh pr create`. It also deletes the generated branch
if a future `gh pr create` call fails after the branch is pushed.

## Cycle 115 Generated PR Proof

Hosted Profile sync run
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27086701950` ran
`write-pr` mode on `main` at
`244613af3ced21adec9d557e0a80732a8f04fa07`. The patched helper continued past
the workflow-permissions endpoint 403, created commit
`0e52dce09f34cd292af534f7b08aa35141c47b24` on
`automation/profile-sync-27086701950`, pushed the branch, and opened PR #8:

`https://github.com/SysAdminDoc/SysAdminDoc/pull/8`

The helper also dispatched branch-scoped Profile sync validation run
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27086730286`.
Validation failed at `Validate generated profile` because the generated branch
check ran `sync-profile.ps1 -Check` against a fresh live metadata snapshot and
reported `projectsExportInSync=false`. PR #8 was closed and
`automation/profile-sync-27086701950` was deleted after evidence collection.

Profile sync now runs `sync-profile.ps1 -Write -Check` only for
workflow-dispatch checks on `automation/profile-*` branches. Normal pull
request, merge queue, scheduled, and main checks still use strict check-only
validation.

## Cycle 116 Branch Validation Proof

Hosted Profile sync run
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27087015369` ran
`write-pr` mode on `main` at
`5509b9e0e63837d4c52c5d38d6f1ccf7621d4c7e`. The helper continued past the
workflow-permissions endpoint 403, created commit
`787a869f04a4b5a644730c4bba9552875541b76c` on
`automation/profile-sync-27087015369`, pushed the branch, and opened PR #9:

`https://github.com/SysAdminDoc/SysAdminDoc/pull/9`

The helper dispatched branch-scoped Profile sync validation run
`https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27087055596`.
Validation ran `sync-profile.ps1 -Write -Check`, passed, uploaded
`profile-sync-report` artifact `7462246872`, and uploaded
`rendered-profile-smoke` artifact `7462247041`. PR #9 was closed and
`automation/profile-sync-27087015369` was deleted after evidence collection.

GitHub commit check-runs for
`787a869f04a4b5a644730c4bba9552875541b76c` showed three workflow-dispatch check
runs, including successful `Check generated README`. However, `gh pr checks`
and PR `statusCheckRollup` reported zero PR-attached checks, so this is branch
validation proof rather than required-check enforcement proof.

## Cycle 117 Commit-Status Handoff

Cycle 117 added a generated PR commit-status handoff without adding a new
automation secret. The shared helper now publishes `generated-profile/validation`
as `pending` on the generated branch head SHA before `gh pr create`; if that
status publication fails after the branch push, the helper deletes the generated
branch before failing. The generated PR body and job summary list the same
status context.

Profile sync now has a separate workflow-dispatch-only
`generated-validation-status` job. It depends on `Check generated README`, has
`statuses: write`, and updates `generated-profile/validation` to success or
failure after branch-scoped validation completes. The normal read-only check
job stays `contents: read` and does not receive status-write permission.

The sync report, schema, summary helper, and Pester suite now record and guard
the status context, permission boundary, pending/final publisher paths, and
pending hosted proof state. Required-check enforcement remains blocked until a
new hosted `write-pr` run proves the status context appears in the generated PR
`statusCheckRollup`.

## References

- [GitHub Docs: About protected branches](https://docs.github.com/articles/types-of-required-status-checks)
- [GitHub Docs: Troubleshooting required status checks](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/troubleshooting-required-status-checks)
- [GitHub Docs: About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [GitHub Docs: Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [GitHub Docs: Triggering a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)
- [GitHub Docs: REST API endpoints for commit statuses](https://docs.github.com/en/rest/commits/statuses)
