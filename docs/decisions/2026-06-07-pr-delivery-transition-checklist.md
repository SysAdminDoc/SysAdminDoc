# PR Delivery Transition Checklist

Date: 2026-06-07

## Decision

Do not enable required-check enforcement yet. The repo has stable candidate
checks, pull request triggers, and merge queue triggers, but the maintenance
delivery path still pushes directly to `main`. Because protected `main` has
admin enforcement enabled, required checks would reject that delivery path until
the repo switches to PR-based delivery or documents and tests a narrow approved
bypass.

## Checklist

| Item | Status | Evidence | Next action |
| --- | --- | --- | --- |
| Candidate required checks | Ready | `Pester (offline)`, `PSScriptAnalyzer`, `Markdownlint`, `Windows setup smoke`, `Check generated README`, and `zizmor` are defined with stable workflow-backed names. | Keep job names unique and unchanged before enforcement. |
| Candidate workflow coverage | Ready | Tests, Profile sync, and Workflow security all create checks on `pull_request` and `merge_group`, and PR triggers are not path-filtered. | Keep required-check candidate workflows always-created for PRs and merge queue runs. |
| Recent successful check runs | Needs live validation | GitHub requires status checks to have completed recently in the repository before they can be selected as required checks. | Open or refresh a disposable PR immediately before enforcement and verify every candidate check completes. |
| PR delivery or bypass | Blocked | Current maintenance delivery still pushes directly to `main`, and branch protection has `enforce_admins.enabled=true`. | Switch the loop to PR-based delivery, or document and test a narrow approved bypass. |
| Enforcement mechanism | Blocked | Branch protection and repository rulesets are currently readable and non-enforcing for required checks. | After PR delivery is proven, enable either branch-protection required checks or one repository ruleset, then re-query live settings. |

## Activation Order

1. Open a disposable PR touching `README.md`, `.github/workflows/tests.yml`, and `setup.ps1`.
2. Confirm all six candidate checks are created on the PR and on `merge_group`.
3. Confirm each candidate check has completed successfully in this repository within GitHub's selection window.
4. Switch routine maintenance to PR delivery, or document an approved bypass and prove it works.
5. Enable one enforcement mechanism only after the delivery path is proven.
6. Re-run `scripts/sync-profile.ps1 -Check` and confirm `repositorySettings.requiredCheckReadiness` and `prDeliveryTransition` reflect the new state.

## References

- [GitHub Docs: About protected branches](https://docs.github.com/articles/types-of-required-status-checks)
- [GitHub Docs: Troubleshooting required status checks](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/troubleshooting-required-status-checks)
- [GitHub Docs: About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [GitHub Docs: Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
