# Profile Release and Tag Policy

Date: 2026-06-07
Status: Accepted

## Decision

Keep `v4.9.x` profile-sync versions as internal evidence versions for generated
profile, catalog, report, and planning-doc changes. Do not create a GitHub
release or matching tag for every `v4.9.x` sync cycle.

GitHub Releases for `SysAdminDoc/SysAdminDoc` remain manual public milestones.
Create a release/tag only when the profile repository ships a user-visible
public milestone or when the operator explicitly asks for a release.

## Current Evidence

- Latest public GitHub release: `v3.0.0`, published 2026-04-13.
- Current planning-doc version before this decision: `v4.9.103`.
- The expected `v4.9.103` tag is not published on GitHub.
- GitHub documents releases as bundled project iterations tied to tags:
  <https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository>.

## Rationale

The `v4.9.x` cadence increments frequently because it records generated profile
sync evidence, report-schema growth, workflow hardening, and planning-doc
continuity. Publishing a GitHub release for every one of those internal sync
cycles would create public release noise without adding a new downloadable
artifact or visitor-facing delivery event.

Keeping public releases sparse makes the Releases page represent durable public
milestones. Keeping the `profileReleaseConsistency` warnings in the report
preserves evidence that planning docs have advanced beyond the last public
release.

## Report Policy

`reports/profile-sync-report.json.profileReleaseConsistency.releasePolicy`
records this decision in machine-readable form:

- `status`: `documented-internal-version-gap`
- `planningVersionKind`: `profile-sync-internal-evidence-version`
- `publicReleaseCadence`: `manual-public-milestone-only`
- `warningDisposition`: `informational`
- `releaseCreationRecommended`: `false`
- `tagCreationRecommended`: `false`

The sync report should continue to compare the latest planning-doc version with
the latest GitHub release and expected tag. When the only issue is the accepted
internal-version gap, Actions summaries may surface it as a notice instead of a
release-blocking warning.

## Revisit Triggers

- A public profile milestone needs a release page, release notes, or downloadable
  release asset.
- A downstream consumer starts relying on GitHub tags for the profile feed or
  schema versions.
- The repo switches from internal evidence versions to release-per-version
  publishing.
