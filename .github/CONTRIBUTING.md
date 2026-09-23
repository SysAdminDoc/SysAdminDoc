# Contributing

Contributions, bug reports, and feature requests are welcome through [issues](https://github.com/SysAdminDoc/SysAdminDoc/issues/new/choose).

## How the profile is built

The public `README.md` is generated from two sources:

1. **`data/profile-catalog.json`** is the canonical list of projects, categories, descriptions, actions, and suppression rules. Its `profileHeader` block holds the README header's personal text and links.
2. **`scripts/sync-profile.ps1`** reads the catalog plus live GitHub metadata, then renders the full README, `projects.json` feed, and validation report. It holds the parameters, shared constants and the run itself, and loads its functions from `scripts/sync-profile/`, one file per concern.

The header and everything below the `<!-- GENERATED PROFILE CATALOG -->` marker are generated and should not be edited directly.

## Making changes

- **Project metadata** (description, category, action label, order): edit `data/profile-catalog.json`.
- **Generation logic**: README sections and install snippets live in `scripts/sync-profile/readme-render.ps1`, the feed in `feed-export.ps1`, catalog loading in `catalog.ps1`, GitHub calls in `github-api.ps1`, link checks in `link-validation.ps1`, and the report in `profile-state.ps1` plus the `report-*.ps1` files.
- **Profile header**: the tagline, language line, greeting, about text, links and support button come from `profileHeader` in `data/profile-catalog.json`. Leave it out and the header is a neutral tagline plus the category nav. The layout is `New-ProfileChrome` in `scripts/sync-profile/readme-render.ps1`.
- **Validation rules**: edit `tests/sync-profile.Tests.ps1`.

## Local validation

Run this from the repo root before pushing profile, catalog, or validation changes:

```powershell
pwsh -NoProfile -File .\scripts\validate-local.ps1
```

Create a redacted support bundle when local validation or setup needs troubleshooting:

```powershell
pwsh -NoProfile -File .\scripts\validate-local.ps1 -SupportBundlePath .\SysAdminDoc-support.zip -SupportBundleRedactValue 'PrivateRepoName'
```

The bundle contains tool versions, validation output, the profile sync report, and dependency-review evidence. User paths, common tokens/secrets, query credentials, and values supplied through `-SupportBundleRedactValue` are redacted. A setup transcript can be added directly when needed:

```powershell
pwsh -NoProfile -File .\scripts\new-support-bundle.ps1 -OutputPath .\SysAdminDoc-setup-support.zip -ProfileReportPath .\reports\profile-sync-report.json -SetupTranscriptPath (Get-ChildItem "$env:TEMP\SysAdminDoc-setup-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
```

Run the manual dependency and advisory review:

```powershell
npm run review:dependencies
```

Run the opt-in Pester 6 compatibility lane in an isolated module path:

```powershell
pwsh -NoProfile -File .\scripts\validate-local.ps1 -Pester6Compatibility
```

Optionally probe the deployed portfolio feed and key routes (warning-only):

```powershell
pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check -ProbePortfolio
```

Emit an optional redaction-safe Backstage catalog export:

```powershell
pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check -BackstageExportPath .\reports\backstage-catalog.json
```

| Check | Behavior |
|:------|:---------|
| Node tools | Runs `npm ci` before markdownlint so the pinned local package is present. The committed `.npmrc` sets `ignore-scripts=true`, `audit-level=high` and `min-release-age=1`, and the lane asks npm what it actually resolved before installing, so an environment override cannot quietly re-enable install scripts. |
| Dependency review | Runs `npm audit --json` and `npm audit signatures`, checks package override drift, verifies npm lock/hash pins, and resolves every pin against the npm and PyPI registries. Each row separates what the parent declares, the resolved pin, and the registry latest. A new major is recorded as review-needed rather than forced, so a deliberate hold stays green. Answers are cached under `.cache/registry-versions.json`; `-OfflineRegistry` reads that cache and reports its age, which goes stale after 30 days. Registry signature verification records verified, invalid and missing counts, names each offending package, and reports per direct dependency whether the installed version carries a registry signature and a build provenance attestation. An invalid or missing signature fails the review. |
| PowerShell runtime | Reports the current `pwsh` version/channel, warns below PowerShell 7.6 LTS during the 7.4 transition window, and keeps Windows PowerShell 5.1 limited to `setup.ps1` bootstrap. |
| PowerShell tools | Installs and imports Pester 5.9.1 plus PSScriptAnalyzer 1.25.0 for the current user when needed. Packages are downloaded as nupkg and their SHA-256 checked against `data/powershell-module-lock.json` before anything is extracted, then every signed file must carry the signer that lock names. A module with no reviewed record is refused rather than installed. Verified packages are cached under `.cache/powershell-modules` so an offline run reuses bytes that already passed. |
| Pester 6 compatibility | Add `-Pester6Compatibility` to save Pester 6.1.0 into an isolated temporary module path and run the non-integration suite; the default Pester 5.9.1 lane is unchanged. |
| Portfolio cross-surface probe | Add `-ProbePortfolio` to compare the deployed portfolio feed timestamp/schema/counts and key routes; external drift or outage is warning-only. |
| Markdown | Runs `npm run lint:markdown` against the tracked public Markdown surfaces. |
| Static analysis | Runs PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`. |
| Tests | Runs the Pester suite with code coverage over every script and `setup.ps1`, and fails if any of them ends the run with no executed command. |
| Profile check | Runs `sync-profile.ps1 -Check` against the working tree after the tests and fails the run on a non-zero exit, naming the failing report conditions. The Pester suite only exercises the generator against fixtures, so this is the lane that validates the committed README, feed, assets, privacy suppression, and links. Add `-SkipProfileCheck` or `-SkipLinkValidation` for a faster loop; both announce that the run was reduced. |
| Support bundle | Add `-SupportBundlePath .\SysAdminDoc-support.zip` to capture a redacted JSON/ZIP diagnostic bundle; pass known private values with `-SupportBundleRedactValue`. |
| Backstage export | Add `-BackstageExportPath .\reports\backstage-catalog.json` to emit opt-in public-safe `backstage.io/v1alpha1` Component descriptors; suppressed, private, and metadata-unavailable rows are omitted. |
| Metadata budget drill | Runs `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check -GraphQlPageSize 300` to exercise a smaller GitHub metadata page size and record request/retry telemetry. |
| Offline writes | `-Write -Offline` requires a fresh complete cache containing the repository inventory and release metadata; cold or partial caches stop before any generated file is opened. |
| Artifact publication | Checks the proposed generated set in memory, then stages each file beside its target with old and new SHA-256 hashes in a durable journal. Existing files are replaced atomically, the report moves last, and an interrupted run is repaired before the next generation. Overlapping runs wait on one repository lock, so they cannot race shared cache entries or transaction journals. |
| Release verification | Add `-VerifyReleaseArtifacts` to `-Check` to download a few GitHub release assets and compare them with their published SHA-256 files. Each UTC week checks a different slice of the assets. A mismatch fails the run, and an asset that can't be downloaded is only a warning. Without the switch, release evidence stays metadata-only. |
| OpenSSF Scorecard | Add `-RunScorecard` to `-Check` to run the Scorecard v5 CLI locally and record its score and per-check results. It needs the `scorecard` binary on `PATH` and a logged-in `gh`. Without the switch, the report says Scorecard wasn't run. |

Already bootstrapped? Add `-SkipBootstrap` to reuse installed modules and `node_modules`.

## Before submitting

1. Run `.\scripts\sync-profile.ps1 -Check` to verify nothing regresses.
2. Run `pwsh -NoProfile -File .\scripts\validate-local.ps1` for the full local validation suite (markdownlint, PSScriptAnalyzer, Pester).
3. Keep commits focused and conventional (`feat:`, `fix:`, `chore:`).
4. Do not include private repository names, medical data, or employer-specific details in any public content.
