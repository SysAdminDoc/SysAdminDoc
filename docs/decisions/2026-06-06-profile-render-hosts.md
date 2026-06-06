# Decision: Profile Render Hosts

Date: 2026-06-06
Status: Accepted

## Context

Earlier profile research flagged live third-party render widgets in the public
GitHub profile README. Those widgets included the profile-view counter, dynamic
stats cards, streak/activity images, animated header/typing images, and icon
strips. They added availability, motion, and visitor-request exposure concerns
for a profile that should be static, inspectable, and public-safe.

## Decision

Do not retain live third-party render hosts in the GitHub profile README. The
current profile uses committed local SVG assets under `assets/profile/` for
chrome and summary panels. `scripts/sync-profile.ps1 -Check` must continue to
report `thirdPartyRenderHostCount=0`, `thirdPartyMetricHostCount=0`,
`thirdPartyBadgeHostCount=0`, and `motionSafeChrome=true`.

## Reopen Criteria

Reopen this decision only if a future profile change proposes a live external
render host again. That change must document the host, visitor-facing purpose,
GitHub Camo exposure, availability fallback, removal trigger, and the exact
generator/report allowlist that keeps the host from becoming accidental drift.

## Verification

The current verification source is `reports/profile-sync-report.json` through
`readmeExperienceChecks`. Pester also guards the decision record so the roadmap
item does not reopen while the generated report still shows zero retained
third-party render, metric, and badge hosts.
