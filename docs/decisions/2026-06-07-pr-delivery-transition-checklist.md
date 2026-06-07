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

## Checklist

| Item | Status | Evidence | Next action |
| --- | --- | --- | --- |
| Candidate required checks | Ready | `Pester (offline)`, `PSScriptAnalyzer`, `Markdownlint`, `Windows setup smoke`, `Check generated README`, and `zizmor` are defined with stable workflow-backed names. | Keep job names unique and unchanged before enforcement. |
| Candidate workflow coverage | Ready | Tests, Profile sync, and Workflow security all create checks on `pull_request` and `merge_group`, and PR triggers are not path-filtered. | Keep required-check candidate workflows always-created for PRs and merge queue runs. |
| Recent successful check runs | Needs live validation | GitHub requires status checks to have completed recently in the repository before they can be selected as required checks. | Open or refresh a disposable PR immediately before enforcement and verify every candidate check completes. |
| PR delivery or bypass | Blocked | Current maintenance delivery still pushes directly to `main`, branch protection has `enforce_admins.enabled=true`, and live Actions workflow permissions block `GITHUB_TOKEN` pull-request creation. | Enable GitHub Actions pull-request creation or switch generated PR delivery to an approved GitHub App/PAT credential before rerunning `write-pr`. |
| Enforcement mechanism | Blocked | Branch protection and repository rulesets are currently readable and non-enforcing for required checks. | After PR delivery is proven, enable either branch-protection required checks or one repository ruleset, then re-query live settings. |

## Activation Order

1. Enable GitHub Actions pull-request creation for `GITHUB_TOKEN`, or configure
   `scripts/open-generated-profile-pr.ps1` to use an approved GitHub App/PAT
   credential for `gh pr create`.
2. Re-run the Profile sync `write-pr` workflow against a disposable generated
   branch and confirm it creates a pull request, dispatches branch-scoped
   Profile sync validation, and leaves no orphaned branch after cleanup.
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

## References

- [GitHub Docs: About protected branches](https://docs.github.com/articles/types-of-required-status-checks)
- [GitHub Docs: Troubleshooting required status checks](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/troubleshooting-required-status-checks)
- [GitHub Docs: About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [GitHub Docs: Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
