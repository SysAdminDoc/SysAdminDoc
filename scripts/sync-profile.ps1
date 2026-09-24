#Requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$SeedCatalog,
    [switch]$ForceSeedCatalog,
    [switch]$Write,
    [switch]$Check,
    [string]$CatalogPath = "data/profile-catalog.json",
    [string]$ReadmePath = "README.md",
    [string]$ProjectsPath = "projects.json",
    [string]$ReportPath = "reports/profile-sync-report.json",
    [string]$SmokeReportPath = "reports/rendered-profile-smoke.json",
    [string]$AssetsPath = "assets/profile",
    [switch]$SkipLinkValidation,
    [switch]$ApplyTopics,
    [string]$TopicAllowlistPath = "data/topic-allowlist.json",
    [string]$Owner = "SysAdminDoc",
    [ValidateRange(1, 1000)]
    [int]$GraphQlPageSize = 500,
    [string]$CachePath = ".cache/profile-sync",
    [ValidateRange(1, 720)]
    [int]$CacheTtlHours = 24,
    [switch]$NoCache,
    [switch]$VerifyReleaseArtifacts,
    [ValidateRange(1, 32)]
    [int]$ReleaseVerificationMaxAssets = 4,
    [ValidateRange(1024, 52428800)]
    [int]$ReleaseVerificationMaxBytes = 5MB,
    [string]$BackstageExportPath,
    [switch]$ProbePortfolio,
    # The portfolio origin behind "See everything" and -ProbePortfolio. Left out, the
    # catalog's portfolioUrl is used; given as '', the owner's GitHub Pages origin.
    [string]$PortfolioUrl,
    [switch]$DraftMissingCatalogEntries,
    [switch]$RunScorecard,
    [switch]$Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# `gh ... --json` emits UTF-8. On a legacy Windows console (cp437/cp1252) PowerShell
# decodes that output with the OEM codepage, mangling non-ASCII characters in repo
# descriptions (e.g. an em-dash becomes mojibake) and corrupting README/projects.json.
# Force UTF-8 so generation is byte-identical across Windows and Linux/CI.
try {
    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = $Utf8NoBom
    $OutputEncoding = $Utf8NoBom
} catch {
    Write-Verbose "Could not force UTF-8 console encoding: $($_.Exception.Message)"
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
# Read before the library is dot-sourced below, which can replace $PSBoundParameters here.
$portfolioUrlGiven = $PSBoundParameters.ContainsKey('PortfolioUrl')
$script:SmokeReportPath = $SmokeReportPath
$script:AssetsPath = $AssetsPath
$script:GraphQlPageSize = [int]$GraphQlPageSize
$script:CachePath = $CachePath
$script:CacheTtlHours = [int]$CacheTtlHours
$script:CacheEnabled = -not [bool]$NoCache
$script:ReleaseVerificationEnabled = [bool]$VerifyReleaseArtifacts
$script:ReleaseVerificationMaxAssets = [int]$ReleaseVerificationMaxAssets
$script:ReleaseVerificationMaxBytes = [int]$ReleaseVerificationMaxBytes
# Library functions read $script:Offline, like the copies above. A plain $Offline inside a
# function resolves to the nearest $Offline up its caller's scopes; when the Pester suite
# dot-sources this file that is the parameter bound in its BeforeAll ($false), so the suite's
# $script:Offline = $true never reached the generator and "offline" tests called GitHub.
$script:Offline = [bool]$Offline
$script:RunScorecard = [bool]$RunScorecard

if (-not $SeedCatalog -and -not $Write -and -not $Check -and -not $ApplyTopics) {
    $Check = $true
}

# $Owner is a script parameter (defaults to "SysAdminDoc") so the generator can target a
# different GitHub account without code edits.
# Word-boundary anchored so substrings (e.g. "dose" inside "glucose"/"overdose")
# do not false-flag a benign public repo as medical-imaging.
$script:MedicalPattern = '(?i)\b(xray|x-ray|dicom|pacs|radiograph|radiology|fluoro|dose|mammograph|nexray|clarity-pacs|weasis|orthanc|chiropractic-imaging|vet-imaging|dental-imaging|medical-imaging)\b'
$script:GeneratedCatalogNotice = '<!-- GENERATED PROFILE CATALOG: edit data/profile-catalog.json, then run scripts/sync-profile.ps1 -Write. Do not hand-edit the sections below. -->'
# The heading over the category grid. The rendered smoke looks for it on the page and reads
# it from here, so a rename can't leave the smoke looking for the old words.
$script:ToolCatalogHeading = "What's here"
$script:MetadataGeneratedAtStaleDays = 7
$script:SeedCatalogGuardMessage = "-SeedCatalog is a lossy legacy bootstrap parser. data/profile-catalog.json is the source of truth; re-run with -ForceSeedCatalog only for a one-shot bootstrap, then review the generated catalog before committing."
$script:LinkValidationThrottle = 16
$script:RestFallbackMaxReleaseFetches = 240
$script:RestFallbackUnauthenticatedReleaseFetchLimit = 50
$script:ReadmeSoftLimitBytes = 96KB
$script:ReadmeCategorySoftLimit = 30
$script:ReadmeLowSignalSoftLimit = 15
$script:ReadmeLineSoftLimit = 1000
$script:ReadmeTableRowSoftLimit = 220
$script:ReadmeDetailsSectionSoftLimit = 15
$script:ReadmeImageTagSoftLimit = 10
$script:ReadmeCodeBlockSoftLimit = 100
$script:ProjectsJsonSoftLimitBytes = 500KB
$script:ProjectsFeedSchemaVersion = 3
$script:PortfolioFeedSchemaVersion = 1
# Feed fields that legitimately differ between a -Write and a later -Check because they
# track live upstream state or the generation run itself. This is the single source of
# tolerance: ConvertTo-ProjectsSyncComparableJson masks exactly these before comparing,
# and Test-MetadataDrift downgrades the same per-project fields to informational. Keeping
# both readers on one list stops the equality check and the severity model drifting apart.
# Anything absent from this list is a real difference and fails the sync gate.
$script:ProjectsFeedVolatileTopLevelFields = @("generatedAt")
$script:ProjectsFeedVolatileProvenanceFields = @("sourceCommit", "metadataSnapshotAt", "metadataProvider")
$script:ProjectsFeedVolatileEnumerationFields = @("requestedLimit")
$script:ProjectsFeedVolatileProjectFields = @(
    "pushedAt",
    "stars",
    "latestReleaseTag",
    "latestReleaseUrl",
    "releaseAssetKinds",
    "releaseAssetNames",
    "releaseAssetInspected",
    "releaseTrust",
    "topics",
    "branchTipSha",
    "branchTipFetchedAt",
    "branchTipStatus",
    "branchTipWarning"
)
$script:ReportJsonSoftLimitBytes = 112KB
$script:ProfileAssetsSoftLimitBytes = 128KB
$script:ProfileAssetsCountSoftLimit = 16
$script:RenderedSmokeMinimumRootClientWidth = 300
$script:BranchTipStaleAfterHours = 24
# Paths whose changes can alter the committed sync report / rendered smoke evidence.
# Used to detect a committed report that predates the latest report-affecting commit.
$script:ReportAffectingPaths = @(
    "scripts/sync-profile.ps1",
    "scripts/sync-profile",
    "scripts/render-profile-smoke.ps1",
    "scripts/write-profile-sync-summary.ps1",
    "data/profile-catalog.json",
    "data/profile-version.json",
    "schemas",
    "README.md"
)
# Paths whose changes invalidate the rendered-smoke evidence specifically. The smoke
# run screenshots the published profile, so a regenerated README or a changed capture
# script means the committed evidence describes a page that no longer exists.
$script:SmokeAffectingPaths = @(
    "README.md",
    "data/profile-catalog.json",
    "scripts/render-profile-smoke.ps1"
)
# How long a local dependency-advisory review stays credible as the compensating
# control for the banned Dependabot lane.
$script:LocalAdvisoryReviewStaleDays = 7
# A project unpushed for about six months is due a look (a warning), and one unpushed for a
# year is an archive candidate. Release age keeps its own, longer threshold: a stable tool
# can go a long time between releases. A catalog reviewBy date replaces all three.
$script:StaleProjectPushedAtReviewDays = 186
$script:StaleProjectReleaseReviewDays = 540
$script:ArchiveProjectPushedAtReviewDays = 365
$script:RequiredStatusCheckCandidates = @()
$script:CodeQlSupportedLanguages = @("C", "C++", "C#", "Go", "Java", "JavaScript", "Kotlin", "Python", "Ruby", "Rust", "Swift", "TypeScript")
$SchemaBaseUrl = "https://raw.githubusercontent.com/$Owner/$Owner/main/schemas"
$script:CatalogSchemaUrl = "$SchemaBaseUrl/profile-catalog.v1.json"
$script:ProjectsSchemaUrl = "$SchemaBaseUrl/profile-projects.v1.json"
$script:ReportSchemaUrl = "$SchemaBaseUrl/profile-sync-report.v1.json"
$script:CatalogSchemaPath = Join-Path $RepoRoot "schemas/profile-catalog.v1.json"
$script:ProjectsSchemaPath = Join-Path $RepoRoot "schemas/profile-projects.v1.json"
$script:ReportSchemaPath = Join-Path $RepoRoot "schemas/profile-sync-report.v1.json"
# Pinned REST calendar version. 2022-11-28 stays supported for at least 24 months from
# the 2026-03-12 announcement; migrating to 2026-03-10 is a tracked, deliberate change.
$script:GitHubRestApiVersion = "2022-11-28"
$script:PowerShellMinimumGeneratorVersion = [version]"7.4.0"
$script:PowerShellPreferredLtsVersion = [version]"7.6.0"
$script:PowerShellPreviousLtsAcceptedUntil = "2026-11-10"
# CVE-2026-50523 (command injection) affects 7.4.0-7.4.18, 7.5.0-7.5.9, and 7.6.0-7.6.4.
# Patched builds are 7.4.19, 7.5.10, and 7.6.5, so an in-support runtime can still be
# vulnerable and needs its own per-line minimum rather than only a floor check.
$script:PowerShellSecurityAdvisoryId = "CVE-2026-50523"
$script:PowerShellSecurityAdvisoryUrl = "https://nvd.nist.gov/vuln/detail/CVE-2026-50523"
$script:PowerShellMinimumSecurePatchVersions = @(
    [version]"7.4.19",
    [version]"7.5.10",
    [version]"7.6.5"
)
$script:WindowsPowerShellBootstrapVersion = "5.1"
$script:WindowsPowerShellAdvisoryId = "CVE-2025-54100"
$script:PowerShellLifecycleUrl = "https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6"
$script:WindowsPowerShellAdvisoryUrl = "https://nvd.nist.gov/vuln/detail/CVE-2025-54100"
$script:ProfileVersionPath = Join-Path $RepoRoot "data/profile-version.json"
$script:RepositoryMetadataProvider = "graphql"
$script:RepositoryEnumerationRequestedLimit = $script:GraphQlPageSize
$script:RepositoryEnumerationTruncated = $false
$script:MetadataSnapshotAt = (Get-Date).ToString("o")
$script:GenerationArtifactTimestamp = $null
$script:RestFallbackReleaseFetchState = $null
$script:MetadataFetchAttemptCount = 0
$script:MetadataFetchRequestCount = 0
$script:MetadataFetchFallbackReason = $null
$script:MetadataFetchResourceLimitFallback = $false
$script:MetadataFetchResourceLimitReason = $null
$script:MetadataFetchPageSizeReduced = $false
$script:ValidationCacheState = $null

# Star counts below this are left off project links: a lone star beside a name is noise,
# not a signal. Ordering still uses the real count.
$script:MinStarDisplay = 2

$script:CategoryDefinitions = @(
    [ordered]@{
        Slug = "powershell"
        DisplayName = "PowerShell"
        Title = "&#9889; PowerShell System Utilities"
        Summary = '<summary><b>&#9889; PowerShell System Utilities</b> &middot; {0} repos &middot; <i>Paste-and-run scripts for Windows admin work.</i></summary>'
        Render = "code"
        DefaultInstallKind = "powershell"
    },
    [ordered]@{
        Slug = "python"
        DisplayName = "Python"
        Title = "&#128013; Python Desktop Applications"
        Summary = '<summary><b>&#128013; Python Desktop Applications</b> &middot; {0} repos &middot; <i>Desktop apps, creative tools, and automation scripts.</i></summary>'
        Render = "code"
        DefaultInstallKind = "python"
    },
    [ordered]@{
        Slug = "web"
        DisplayName = "Web Apps"
        Title = "&#127760; Web Applications"
        Summary = '<summary><b>&#127760; Web Applications</b> &middot; {0} repos &middot; <i>Live web apps and dashboards you can open right now.</i></summary>'
        Render = "web-table"
    },
    [ordered]@{
        Slug = "extensions"
        DisplayName = "Extensions"
        Title = "&#129513; Browser Extensions & Userscripts"
        Summary = '<summary><b>&#129513; Browser Extensions & Userscripts</b> &middot; {0} repos &middot; <i>One-click installs for Chrome and Firefox. Userscripts need Tampermonkey or similar.</i></summary>'
        Render = "install-table"
    },
    [ordered]@{
        Slug = "android"
        DisplayName = "Android"
        Title = "&#128241; Android Applications"
        Summary = '<summary><b>&#128241; Android Applications</b> &middot; {0} repos &middot; <i>APKs you can sideload and Android source projects.</i></summary>'
        Render = "download-table"
        DefaultDownloadKind = "apk"
    },
    [ordered]@{
        Slug = "security"
        DisplayName = "Security"
        Title = "&#128274; Security & Networking"
        Summary = '<summary><b>&#128274; Security & Networking</b> &middot; {0} repos &middot; <i>Network audits, DNS control, and hardening scripts.</i></summary>'
        Render = "download-table"
    },
    [ordered]@{
        Slug = "media"
        DisplayName = "Media"
        Title = "&#127916; Media & Conversion Tools"
        Summary = '<summary><b>&#127916; Media & Conversion Tools</b> &middot; {0} repos &middot; <i>Video, audio, and stream tools.</i></summary>'
        Render = "code"
        DefaultInstallKind = "python"
    },
    [ordered]@{
        Slug = "desktop"
        DisplayName = "Desktop"
        Title = "&#128421;&#65039; Native Desktop Applications"
        Summary = '<summary><b>&#128421;&#65039; Native Desktop Applications</b> &middot; {0} repos &middot; <i>Windows and cross-platform desktop apps.</i></summary>'
        Render = "desktop-table"
    },
    [ordered]@{
        Slug = "guides"
        DisplayName = "Guides"
        Title = "&#128218; Guides & Resources"
        Summary = '<summary><b>&#128218; Guides & Resources</b> &middot; {0} repos &middot; <i>How-to guides, checklists, and references.</i></summary>'
        Render = "simple-table"
    },
    [ordered]@{
        Slug = "misc"
        DisplayName = "Misc"
        Title = "&#128256; Misc & Forks"
        Summary = '<summary><b>&#128256; Misc & Forks</b> &middot; {0} repos &middot; <i>Forks, side projects, and things that didn''t fit elsewhere.</i></summary>'
        Render = "simple-table"
    }
)

# The function library lives in scripts/sync-profile/, one file per concern. Dot-sourcing
# each file here keeps every function in this script's scope, so the functions read the
# parameters and constants above exactly as they did when this was one file, and a caller
# that dot-sources this entry point (the Pester suite does) receives the whole library.
# This list is also the generator's identity for provenance.generatorSha256.
$GeneratorLibraryFiles = @(
    'scripts/sync-profile/common.ps1'
    'scripts/sync-profile/github-api.ps1'
    'scripts/sync-profile/outbound-http.ps1'
    'scripts/sync-profile/catalog.ps1'
    'scripts/sync-profile/release-trust.ps1'
    'scripts/sync-profile/link-validation.ps1'
    'scripts/sync-profile/readme-render.ps1'
    'scripts/sync-profile/feed-export.ps1'
    'scripts/sync-profile/artifact-store.ps1'
    'scripts/sync-profile/schema-validation.ps1'
    'scripts/sync-profile/report-readme.ps1'
    'scripts/sync-profile/report-evidence.ps1'
    'scripts/sync-profile/report-repository.ps1'
    'scripts/sync-profile/report-metadata.ps1'
    'scripts/sync-profile/report-install-trust.ps1'
    'scripts/sync-profile/profile-state.ps1'
)
foreach ($generatorLibraryFile in $GeneratorLibraryFiles) {
    . (Join-Path $RepoRoot $generatorLibraryFile)
}

# Test seam: when dot-sourced (e.g. by Pester), load the functions above and stop
# before running the live-metadata fetch / generation below.
if ($MyInvocation.InvocationName -eq '.') { return }

# Generated artifacts must not depend on the machine locale. Case-insensitive -match and
# -like follow the current culture, and under tr-TR a capital I is not an upper-case i,
# so '.SIG' stopped matching '\.sig$' and 'DICOM' stopped matching the medical-privacy
# pattern. Pin the invariant culture for this thread and for the parallel link probes.
[System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Globalization.CultureInfo]::CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Globalization.CultureInfo]::DefaultThreadCurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture

if (-not (Test-SafeGitHubName -Name $Owner)) {
    Write-Error "Owner must match ^[A-Za-z0-9._-]+$ so generated URLs and gh API paths cannot contain slashes, whitespace, or shell metacharacters."
    exit 1
}

Set-Location $RepoRoot

$profileSyncRunLock = $null
try {
$profileSyncRunLock = Enter-ProfileSyncRunLock

try {
    $recoveredPublicationCount = Repair-ArtifactPublicationTransactions
    if ($recoveredPublicationCount -gt 0) {
        Write-Warning "Recovered $recoveredPublicationCount interrupted artifact publication transaction(s) before generation."
    }
} catch {
    Write-Error "Artifact publication recovery failed before generation: $($_.Exception.Message)"
    exit 1
}

if ($SeedCatalog) {
    $seedGuard = Test-SeedCatalogGuard -SeedRequested ([bool]$SeedCatalog) -ForceRequested ([bool]$ForceSeedCatalog)
    if (-not $seedGuard.allowed) {
        Write-Error $seedGuard.message
        exit 1
    }
    Write-Warning "LOSSY LEGACY SEED MODE: $($seedGuard.message -replace '^-SeedCatalog is a ', '')"
}

# A normal run reads its catalog before anything is fetched, so a catalog the -Write gate
# refuses costs no GitHub requests and leaves the snapshot cache alone. A seed builds its
# catalog from the fetched repositories, so it's read and gated after the seed below.
$catalogForRun = $null
if (-not $SeedCatalog -and (Test-Path -LiteralPath $CatalogPath)) {
    $catalogForRun = Get-Catalog -Path $CatalogPath
}

# -Write alone never reaches Test-ProfileState, where -Check runs the shape check and the
# JSON schemas, yet it is the command the README tells editors to run. The shape check
# holds every value the README renders to its schema shape, so a catalog that fails it
# stops here and nothing is rendered or written.
if ($catalogForRun -and $Write -and -not $Check) {
    $writeShape = Test-CatalogShape -Catalog $catalogForRun
    if (-not $writeShape.passed) {
        foreach ($issue in @($writeShape.issues)) {
            $issueRepo = if ([string]::IsNullOrWhiteSpace([string]$issue.repo)) { '' } else { "$($issue.repo) " }
            Write-Warning ("Catalog issue: {0}{1}: {2}" -f $issueRepo, $issue.field, $issue.reason)
        }
        Write-Error 'The catalog failed its shape check, so nothing was written. Fix the issues above, or run -Check for the full report.' -ErrorAction Continue
        exit 1
    }
}

$repos = @()
if ($Offline -and ($Write -or $Check)) {
    $generationSnapshot = Get-CompleteGenerationSnapshot
    if ($null -eq $generationSnapshot) {
        if ($Write) {
            Write-Error 'Offline writes require a fresh, complete generation snapshot. Run sync-profile.ps1 -Check online once to populate the cache, then retry before the cache TTL expires.'
            exit 1
        }
        $script:RepositoryMetadataProvider = 'offline-empty'
        $script:RepositoryEnumerationRequestedLimit = [int]$script:GraphQlPageSize
        $script:RepositoryEnumerationTruncated = $false
        $script:MetadataFetchFallbackReason = 'complete generation snapshot unavailable'
    } else {
        Set-GenerationStateFromSnapshot -Snapshot $generationSnapshot
        $repos = @(Get-MemberValue -Object $generationSnapshot -Name 'repositories')
    }
} elseif (-not $Offline) {
    $repos = @(Add-LiveRepositoryMetadata -Repos (Get-GitHubRepos))
    if ($Write -or $Check) {
        $script:GenerationArtifactTimestamp = (Get-Date).ToString('o')
        $snapshotWritten = Write-CompleteGenerationSnapshot `
            -Repos $repos `
            -ReleaseMetadataComplete:$true `
            -GenerationTimestamp $script:GenerationArtifactTimestamp
        if (-not $snapshotWritten) {
            Write-Warning 'Complete generation snapshot was not refreshed because one or more live sources were incomplete.'
        }
    }
}

if ($SeedCatalog) {
    $catalog = New-CatalogFromReadme -Repos $repos
    $catalogDir = Split-Path -Parent $CatalogPath
    if ($catalogDir -and -not (Test-Path -LiteralPath $catalogDir)) {
        New-Item -ItemType Directory -Path $catalogDir | Out-Null
    }
    $catalogJson = $catalog | ConvertTo-Json -Depth 20
    Write-AtomicUtf8TextFile -Path $CatalogPath -Content ($catalogJson + [Environment]::NewLine)
    Write-Host "Seeded $CatalogPath with $($catalog.entries.Count) entries."
    if (-not $Write -and -not $Check) {
        exit 0
    }
    $catalogForRun = Get-Catalog -Path $CatalogPath
    # The same -Write gate as above, for the seeded catalog. The seed stays on disk to edit.
    if ($Write -and -not $Check) {
        $writeShape = Test-CatalogShape -Catalog $catalogForRun
        if (-not $writeShape.passed) {
            foreach ($issue in @($writeShape.issues)) {
                $issueRepo = if ([string]::IsNullOrWhiteSpace([string]$issue.repo)) { '' } else { "$($issue.repo) " }
                Write-Warning ("Catalog issue: {0}{1}: {2}" -f $issueRepo, $issue.field, $issue.reason)
            }
            Write-Error "The seeded catalog failed its shape check, so nothing else was written. Fix the issues above in $CatalogPath, then run -Write again." -ErrorAction Continue
            exit 1
        }
    }
}

# The portfolio links follow the catalog unless -PortfolioUrl was given, so a run for another
# account never links to this profile's site. Get-ProfilePortfolioUrl reads this variable and
# falls back to the owner's GitHub Pages origin when it is empty.
if (-not $portfolioUrlGiven -and $catalogForRun) {
    $PortfolioUrl = [string](Get-MemberValue -Object $catalogForRun -Name 'portfolioUrl')
}

if ($catalogForRun -and ($Write -or $Check)) {
    $expected = New-Readme -Catalog $catalogForRun -Repos $repos
    $expectedProjects = New-ProjectsExportJson -Catalog $catalogForRun -Repos $repos -GeneratedAt $script:GenerationArtifactTimestamp
    $expectedAssets = New-ProfileAssetSvgs
    $backstageExport = if ([string]::IsNullOrWhiteSpace($BackstageExportPath)) { $null } else { New-BackstageCatalogExport -Catalog $catalogForRun -Repos $repos }

    $publicationTransaction = $null
    $publicationRoot = Get-ArtifactPublicationTransactionRoot
    try {
        $publicationArtifacts = [System.Collections.Generic.List[object]]::new()
        if ($Write) {
            $readmeFullPath = if ([System.IO.Path]::IsPathRooted($ReadmePath)) { $ReadmePath } else { Join-Path $RepoRoot $ReadmePath }
            $projectsFullPath = if ([System.IO.Path]::IsPathRooted($ProjectsPath)) { $ProjectsPath } else { Join-Path $RepoRoot $ProjectsPath }
            $publicationArtifacts.Add([ordered]@{ path = $readmeFullPath; content = $expected; isReport = $false }) | Out-Null
            $publicationArtifacts.Add([ordered]@{ path = $projectsFullPath; content = ($expectedProjects + [Environment]::NewLine); isReport = $false }) | Out-Null
            foreach ($assetPath in @($expectedAssets.Keys)) {
                $fullPath = if ([System.IO.Path]::IsPathRooted($assetPath)) { $assetPath } else { Join-Path $RepoRoot $assetPath }
                $publicationArtifacts.Add([ordered]@{ path = $fullPath; content = ([string]$expectedAssets[$assetPath] + [Environment]::NewLine); isReport = $false }) | Out-Null
            }
        }
        if ($backstageExport) {
            $backstageFullPath = if ([System.IO.Path]::IsPathRooted($BackstageExportPath)) { $BackstageExportPath } else { Join-Path $RepoRoot $BackstageExportPath }
            $publicationArtifacts.Add([ordered]@{ path = $backstageFullPath; content = ([string]$backstageExport.json + [Environment]::NewLine); isReport = $false }) | Out-Null
        }

        $result = $null
        if ($Check) {
            $profileStateParameters = [ordered]@{
                Catalog = $catalogForRun
                Repos = $repos
                ExpectedReadme = $expected
                ExpectedProjects = $expectedProjects
                ExpectedAssets = $expectedAssets
                SkipLinkValidation = [bool]$SkipLinkValidation
                VerifyReleaseArtifacts = [bool]$VerifyReleaseArtifacts
                ReleaseVerificationMaxAssets = $ReleaseVerificationMaxAssets
                ReleaseVerificationMaxBytes = $ReleaseVerificationMaxBytes
                BackstageExport = $backstageExport
                BackstageExportPath = $BackstageExportPath
                ProbePortfolio = [bool]$ProbePortfolio
                # The address the footer links, so the probe checks what a visitor reaches.
                PortfolioUrl = Get-ProfilePortfolioUrl
            }
            if ($Write) {
                $profileStateParameters['CurrentReadme'] = $expected
                $profileStateParameters['CurrentProjects'] = $expectedProjects
                # The write replaces generated assets but never deletes, so a stray file
                # under -AssetsPath is still there afterwards and must still be reported.
                $assetsAfterWrite = Get-ProfileAssetFileContents
                foreach ($assetPath in @($expectedAssets.Keys)) {
                    $assetsAfterWrite[$assetPath] = [string]$expectedAssets[$assetPath]
                }
                $profileStateParameters['CurrentAssets'] = $assetsAfterWrite
            }
            $result = Test-ProfileState @profileStateParameters
            $reportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $RepoRoot $ReportPath }
            $reportJson = $result.Report | ConvertTo-Json -Depth 20
            if ($result['Failed'] -eq $true) {
                $publicationTransaction = New-ArtifactPublicationTransaction -Artifacts @(
                    [ordered]@{ path = $reportFullPath; content = ($reportJson + [Environment]::NewLine); isReport = $true }
                ) -TransactionRoot $publicationRoot
                Publish-ArtifactPublicationTransaction -Transaction $publicationTransaction
                Complete-ArtifactPublicationTransaction -Transaction $publicationTransaction
                $publicationTransaction = $null
                if ($DraftMissingCatalogEntries -and $Write) {
                    Write-CatalogEntryDraft -MissingPublicRepos @($result.Report.missingPublicRepos) -CatalogPath $CatalogPath
                }
                Write-Error "Profile sync check failed. Generated targets were not changed; see $ReportPath." -ErrorAction Continue
                exit 1
            }
            $publicationArtifacts.Add([ordered]@{ path = $reportFullPath; content = ($reportJson + [Environment]::NewLine); isReport = $true }) | Out-Null
        }

        if ($publicationArtifacts.Count -gt 0) {
            $publicationTransaction = New-ArtifactPublicationTransaction -Artifacts $publicationArtifacts.ToArray() -TransactionRoot $publicationRoot
            Publish-ArtifactPublicationTransaction -Transaction $publicationTransaction
            Complete-ArtifactPublicationTransaction -Transaction $publicationTransaction
            $publicationTransaction = $null
        }

        if ($Write) {
            Write-Host "Wrote $ReadmePath from $CatalogPath."
            Write-Host "Wrote $ProjectsPath from $CatalogPath."
        }
        if ($backstageExport) {
            Write-Host "Wrote Backstage export to $BackstageExportPath."
        }
        if ($Check) {
            Write-Host "Profile sync check passed. Report: $ReportPath"
            # Keep hosted shells from surfacing handled native-command failures.
            exit 0
        }
    } catch {
        $publicationFailure = $_
        if ($null -ne $publicationTransaction) {
            try {
                Repair-ArtifactPublicationTransactions -TransactionRoot $publicationRoot | Out-Null
            } catch {
                Write-Warning "Artifact publication rollback failed: $($_.Exception.Message)"
            }
        }
        Write-Error "Artifact publication failed: $($publicationFailure.Exception.Message)"
        exit 1
    }
}

if ($ApplyTopics) {
    $allowlistFullPath = if ([System.IO.Path]::IsPathRooted($TopicAllowlistPath)) { $TopicAllowlistPath } else { Join-Path $RepoRoot $TopicAllowlistPath }
    if (-not (Test-Path -LiteralPath $allowlistFullPath)) {
        Write-Error "Topic allowlist not found: $TopicAllowlistPath. Create a JSON array of repo names to apply topics to."
        exit 1
    }
    $allowlist = @(Get-Content -LiteralPath $allowlistFullPath -Raw | ConvertFrom-Json)
    if ($allowlist.Count -eq 0) {
        Write-Host "Topic allowlist is empty; no topics will be applied."
        exit 0
    }
    $catalogForTopics = Get-Catalog -Path (Join-Path $RepoRoot $CatalogPath)
    $repoLookup = @{}
    foreach ($repo in (Get-GitHubRepos)) {
        $repoLookup[([string](Get-MemberValue -Object $repo -Name "name")).ToLowerInvariant()] = $repo
    }
    $applied = 0
    $skipped = 0
    foreach ($entry in @($catalogForTopics.entries)) {
        $repoName = [string]$entry.repo
        if ($repoName -notin $allowlist) { continue }
        if (-not (Test-SafeGitHubName -Name $repoName)) {
            $skipped++
            Write-Warning "SKIP $repoName (unsafe repo name; must match ^[A-Za-z0-9._-]+`$)"
            continue
        }
        $repo = $repoLookup[$repoName.ToLowerInvariant()]
        $existingTopics = @()
        if ($repo) {
            $rawTopics = Get-MemberValue -Object $repo -Name "repositoryTopics"
            if ($rawTopics) {
                $existingTopics = @($rawTopics | ForEach-Object {
                    $name = Get-MemberValue -Object $_ -Name "name"
                    if ($null -eq $name) { $name = Get-MemberValue -Object (Get-MemberValue -Object $_ -Name "topic") -Name "name" }
                    [string]$name
                } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }
        if ($existingTopics.Count -gt 0) {
            $skipped++
            Write-Host "SKIP $repoName (already has $($existingTopics.Count) topic(s): $($existingTopics -join ', '))"
            continue
        }
        $language = if ($repo) { [string](Get-MemberValue -Object (Get-MemberValue -Object $repo -Name "primaryLanguage") -Name "name") } else { $null }
        $description = if ($repo) { [string](Get-MemberValue -Object $repo -Name "description") } else { $null }
        $hints = @(Get-TopicHints -Repo $repoName -Language $language -Entry $entry -Description $description)
        if ($hints.Count -eq 0) {
            $skipped++
            Write-Host "SKIP $repoName (no topic hints generated)"
            continue
        }
        Write-Host "APPLY $repoName -> $($hints -join ', ')"
        $topicPayload = @{ names = $hints } | ConvertTo-Json -Compress
        $topicGh = Invoke-GhCli -Arguments @("api", "repos/$Owner/$repoName/topics", "-X", "PUT", "--input", "-") -StandardInput $topicPayload
        if ($topicGh.exitCode -ne 0) {
            Write-Warning "Failed to apply topics to $repoName (exit code $($topicGh.exitCode)): $($topicGh.text)"
        } else {
            $applied++
        }
    }
    Write-Host "Topic apply complete: $applied applied, $skipped skipped."
}
} finally {
    if ($null -ne $profileSyncRunLock) {
        $profileSyncRunLock.Dispose()
    }
}
