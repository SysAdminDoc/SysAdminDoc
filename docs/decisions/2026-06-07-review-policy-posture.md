# Review Policy Posture

Date: 2026-06-07

## Decision

Keep pull request review and code-owner review requirements warning-only for
now. Branch-protection required checks are active, routine pull-request delivery
is proven, and direct-main bypass remains unapproved. Do not enable review
requirements until an independent reviewer or team model exists.

This preserves the current protection that matters for every routine change:
`Pester (offline)`, `PSScriptAnalyzer`, `Markdownlint`, `Windows setup smoke`,
`Check generated README`, and `zizmor` must pass before merge. It avoids turning
single-maintainer maintenance into a self-blocking review rule.

## Current Evidence

- PR #14 proved normal routine pull-request delivery before enforcement.
- PR #16 proved normal routine pull-request delivery after branch-protection
  required checks were enabled.
- Branch protection requires the six validation checks with strict up-to-date
  enforcement.
- Branch protection does not require pull request reviews.
- Branch protection does not require code-owner reviews.
- `.github/CODEOWNERS` is present and routes public-contract files, but review
  routing becomes merge enforcement only after branch protection requires code
  owner review.
- The Scorecard `CodeReviewID` alert is classified as
  `external-gated-reviewer-model`, not a local report defect.

## Activation Boundary

Review requirements may be revisited when one of these is true:

1. A second maintainer, reviewer team, or repository role exists and can approve
   routine profile maintenance PRs.
2. The repository adopts a formal self-review exception or bypass actor and
   records that policy separately.
3. GitHub branch protection is changed to require PR reviews or code-owner
   reviews and a follow-up PR proves that routine maintenance can still merge.

Until then, keep the warnings visible in `repositorySettings.warnings` and keep
the machine-readable posture in `repositorySettings.reviewPolicyPosture`.

## References

- [GitHub Docs: About protected branches](https://docs.github.com/articles/types-of-required-status-checks)
- [GitHub Docs: About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
