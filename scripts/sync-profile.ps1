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
$script:SmokeReportPath = $SmokeReportPath

if (-not $SeedCatalog -and -not $Write -and -not $Check -and -not $ApplyTopics) {
    $Check = $true
}

# $Owner is a script parameter (defaults to "SysAdminDoc") so the generator can target a
# different GitHub account without code edits.
# Word-boundary anchored so substrings (e.g. "dose" inside "glucose"/"overdose")
# do not false-flag a benign public repo as medical-imaging.
$MedicalPattern = '(?i)\b(xray|x-ray|dicom|pacs|radiograph|radiology|fluoro|dose|mammograph|nexray|clarity-pacs|weasis|orthanc|chiropractic-imaging|vet-imaging|dental-imaging|medical-imaging)\b'
$GeneratedCatalogNotice = '<!-- GENERATED PROFILE CATALOG: edit data/profile-catalog.json, then run scripts/sync-profile.ps1 -Write. Do not hand-edit the sections below. -->'
$MetadataGeneratedAtStaleDays = 7
$SeedCatalogGuardMessage = "-SeedCatalog is a lossy legacy bootstrap parser. data/profile-catalog.json is the source of truth; re-run with -ForceSeedCatalog only for a one-shot bootstrap, then review the generated catalog before committing."
$LinkValidationThrottle = 16
$RestFallbackMaxReleaseFetches = 240
$RestFallbackUnauthenticatedReleaseFetchLimit = 50
$ReadmeSoftLimitBytes = 96KB
$ReadmeCategorySoftLimit = 30
$ReadmeLowSignalSoftLimit = 15
$ReadmeLineSoftLimit = 1000
$ReadmeTableRowSoftLimit = 220
$ReadmeDetailsSectionSoftLimit = 15
$ReadmeImageTagSoftLimit = 10
$ReadmeCodeBlockSoftLimit = 100
$ProjectsJsonSoftLimitBytes = 500KB
$ProjectsFeedSchemaVersion = 2
$ReportJsonSoftLimitBytes = 112KB
$ProfileAssetsSoftLimitBytes = 128KB
$ProfileAssetsCountSoftLimit = 16
$RenderedSmokeMinimumRootClientWidth = 300
# Extra tolerance (minutes) added to a scheduled workflow's max inter-run gap
# before its latest successful scheduled run is treated as stale. Covers runner
# queue delays and the GitHub-documented cron drift on busy schedules.
$ScheduledWorkflowGraceMinutes = 1440
# Paths whose changes can alter the committed sync report / rendered smoke evidence.
# Used to detect a committed report that predates the latest report-affecting commit.
$ReportAffectingPaths = @(
    "scripts/sync-profile.ps1",
    "scripts/render-profile-smoke.ps1",
    "scripts/write-profile-sync-summary.ps1",
    "scripts/open-generated-profile-pr.ps1",
    "data/profile-catalog.json",
    "data/profile-version.json",
    "schemas",
    "README.md"
)
$StaleProjectPushedAtReviewDays = 365
$StaleProjectReleaseReviewDays = 540
$ArchiveProjectPushedAtReviewDays = 730
$RequiredStatusCheckCandidates = @()
$CodeQlSupportedLanguages = @("C", "C++", "C#", "Go", "Java", "JavaScript", "Kotlin", "Python", "Ruby", "Rust", "Swift", "TypeScript")
$SchemaBaseUrl = "https://raw.githubusercontent.com/$Owner/$Owner/main/schemas"
$CatalogSchemaUrl = "$SchemaBaseUrl/profile-catalog.v1.json"
$ProjectsSchemaUrl = "$SchemaBaseUrl/profile-projects.v1.json"
$ReportSchemaUrl = "$SchemaBaseUrl/profile-sync-report.v1.json"
$CatalogSchemaPath = Join-Path $RepoRoot "schemas/profile-catalog.v1.json"
$ProjectsSchemaPath = Join-Path $RepoRoot "schemas/profile-projects.v1.json"
$ReportSchemaPath = Join-Path $RepoRoot "schemas/profile-sync-report.v1.json"
$script:ProfileVersionPath = Join-Path $RepoRoot "data/profile-version.json"
$script:RepositoryMetadataProvider = "graphql"
$script:RepositoryEnumerationRequestedLimit = 500
$script:RepositoryEnumerationTruncated = $false
$script:MetadataSnapshotAt = (Get-Date).ToString("o")
$script:RestFallbackReleaseFetchState = $null
$script:MetadataFetchAttemptCount = 0
$script:MetadataFetchFallbackReason = $null

$CategoryDefinitions = @(
    [ordered]@{
        Slug = "powershell"
        DisplayName = "PowerShell"
        Title = "&#9889; PowerShell System Utilities"
        Summary = '<summary><b>&#9889; PowerShell System Utilities</b> -- {0} repos -- <i>Branch-pinned commands you can paste into PowerShell and run immediately.</i></summary>'
        Render = "code"
        DefaultInstallKind = "powershell"
    },
    [ordered]@{
        Slug = "python"
        DisplayName = "Python"
        Title = "&#128013; Python Desktop Applications"
        Summary = '<summary><b>&#128013; Python Desktop Applications</b> -- {0} repos -- <i>Clone-and-run desktop tools and automation built on Python 3.</i></summary>'
        Render = "code"
        DefaultInstallKind = "python"
    },
    [ordered]@{
        Slug = "web"
        DisplayName = "Web Apps"
        Title = "&#127760; Web Applications"
        Summary = '<summary><b>&#127760; Web Applications</b> -- {0} repos -- <i>Tools and dashboards that run directly in the browser -- no install needed.</i></summary>'
        Render = "web-table"
    },
    [ordered]@{
        Slug = "extensions"
        DisplayName = "Extensions"
        Title = "&#129513; Browser Extensions & Userscripts"
        Summary = '<summary><b>&#129513; Browser Extensions & Userscripts</b> -- {0} repos -- <i>Chrome/Firefox extensions and userscripts with one-click installs.</i></summary>'
        Render = "install-table"
    },
    [ordered]@{
        Slug = "android"
        DisplayName = "Android"
        Title = "&#128241; Android Applications"
        Summary = '<summary><b>&#128241; Android Applications</b> -- {0} repos -- <i>Material You APKs and Android source projects.</i></summary>'
        Render = "download-table"
        DefaultDownloadKind = "apk"
    },
    [ordered]@{
        Slug = "security"
        DisplayName = "Security"
        Title = "&#128274; Security & Networking"
        Summary = '<summary><b>&#128274; Security & Networking</b> -- {0} repos -- <i>Network auditing, DNS management, and defensive security tools.</i></summary>'
        Render = "download-table"
    },
    [ordered]@{
        Slug = "media"
        DisplayName = "Media"
        Title = "&#127916; Media & Conversion Tools"
        Summary = '<summary><b>&#127916; Media & Conversion Tools</b> -- {0} repos -- <i>Video editing, conversion, compression, subtitle removal, and streaming capture.</i></summary>'
        Render = "code"
        DefaultInstallKind = "python"
    },
    [ordered]@{
        Slug = "desktop"
        DisplayName = "Desktop"
        Title = "&#128421;&#65039; Native Desktop Applications"
        Summary = '<summary><b>&#128421;&#65039; Native Desktop Applications</b> -- {0} repos -- <i>Compiled Windows and cross-platform desktop apps in C#, C++, Rust, and TypeScript.</i></summary>'
        Render = "desktop-table"
    },
    [ordered]@{
        Slug = "guides"
        DisplayName = "Guides"
        Title = "&#128218; Guides & Resources"
        Summary = '<summary><b>&#128218; Guides & Resources</b> -- {0} repos -- <i>Reference material, checklists, and public guides.</i></summary>'
        Render = "simple-table"
    },
    [ordered]@{
        Slug = "misc"
        DisplayName = "Misc"
        Title = "&#128256; Misc & Forks"
        Summary = '<summary><b>&#128256; Misc & Forks</b> -- {0} repos -- <i>Forks, continuations, and supporting utilities.</i></summary>'
        Render = "simple-table"
    }
)

function ConvertTo-CategorySlug {
    param([string]$SummaryLine)

    foreach ($def in $CategoryDefinitions) {
        $title = [string]$def.Title
        $plainTitle = [regex]::Replace($title, '&#\d+;|&#x[0-9a-fA-F]+;', '').Trim()
        if ($SummaryLine -match [regex]::Escape($plainTitle)) {
            return [string]$def.Slug
        }
    }
    return $null
}

function Invoke-GhCli {
    <#
    .SYNOPSIS
    Runs the GitHub CLI and returns its merged output, exit code, and trimmed text.
    .DESCRIPTION
    Single adapter seam for every read-path `gh` invocation so error handling, output
    normalization, and test mocking live in one place instead of being duplicated at each
    call site. Merges stderr into stdout (2>&1) and captures $LASTEXITCODE immediately so
    callers can inspect gh's real exit code regardless of later pipeline commands. Pester
    tests mock this function instead of replacing the raw `gh` command.
    .PARAMETER Arguments
    The argument list passed to gh (e.g. @("api", "repos/OWNER/REPO")).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & gh @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    return [ordered]@{
        output = $output
        exitCode = $exitCode
        text = (($output | Out-String).Trim())
    }
}

function Get-GitHubReposFromRest {
    if ($Offline) {
        return @()
    }

    $gh = Invoke-GhCli -Arguments @("api", "--paginate", "--slurp", "users/$Owner/repos?per_page=100")
    $repoOutput = $gh.text
    if ($gh.exitCode -ne 0) {
        throw "REST repo metadata fallback failed while enumerating repos. Last gh output: $repoOutput"
    }

    $allRepos = New-Object System.Collections.Generic.List[object]
    foreach ($repo in @(ConvertFrom-RestRepoPageJson -Json $repoOutput)) {
        if (-not [bool](Get-MemberValue -Object $repo -Name "archived") -and -not [bool](Get-MemberValue -Object $repo -Name "private")) {
            $allRepos.Add($repo)
        }
    }

    $mapped = New-Object System.Collections.Generic.List[object]
    foreach ($repo in $allRepos) {
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        if ([string]::IsNullOrWhiteSpace($repoName)) {
            continue
        }
        $mapped.Add((ConvertFrom-RestRepoMetadata -Repo $repo -Release $null))
    }

    $script:RepositoryMetadataProvider = "rest-fallback"
    $script:RepositoryEnumerationRequestedLimit = 0
    $script:RepositoryEnumerationTruncated = $false
    return $mapped.ToArray()
}

function ConvertFrom-RestRepoMetadata {
    param(
        [object]$Repo,
        [object]$Release
    )

    $topicsValue = Get-MemberValue -Object $Repo -Name "topics"
    $topics = @()
    if ($topicsValue) {
        $topics = @($topicsValue | ForEach-Object { [pscustomobject]@{ name = [string]$_ } })
    }

    $parentValue = Get-MemberValue -Object $Repo -Name "parent"
    $parent = $null
    if ($parentValue) {
        $parentName = Get-MemberValue -Object $parentValue -Name "full_name"
        $parentUrl = Get-MemberValue -Object $parentValue -Name "html_url"
        if (-not [string]::IsNullOrWhiteSpace([string]$parentName) -or -not [string]::IsNullOrWhiteSpace([string]$parentUrl)) {
            $parent = [pscustomobject]@{
                nameWithOwner = if ([string]::IsNullOrWhiteSpace([string]$parentName)) { $null } else { [string]$parentName }
                url = if ([string]::IsNullOrWhiteSpace([string]$parentUrl)) { $null } else { [string]$parentUrl }
            }
        }
    }

    $language = Get-MemberValue -Object $Repo -Name "language"

    return [pscustomobject]@{
        name = Get-MemberValue -Object $Repo -Name "name"
        description = Get-MemberValue -Object $Repo -Name "description"
        stargazerCount = [int](Get-MemberValue -Object $Repo -Name "stargazers_count")
        defaultBranchRef = [pscustomobject]@{ name = Get-MemberValue -Object $Repo -Name "default_branch" }
        latestRelease = $Release
        licenseInfo = Get-MemberValue -Object $Repo -Name "license"
        isFork = [bool](Get-MemberValue -Object $Repo -Name "fork")
        parent = $parent
        isPrivate = [bool](Get-MemberValue -Object $Repo -Name "private")
        visibility = "PUBLIC"
        isArchived = [bool](Get-MemberValue -Object $Repo -Name "archived")
        repositoryTopics = $topics
        pushedAt = Get-MemberValue -Object $Repo -Name "pushed_at"
        url = Get-MemberValue -Object $Repo -Name "html_url"
        primaryLanguage = if ([string]::IsNullOrWhiteSpace([string]$language)) { $null } else { [pscustomobject]@{ name = [string]$language } }
    }
}

function ConvertFrom-RestRepoPageJson {
    param([string]$Json)

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return @()
    }

    $repos = New-Object System.Collections.Generic.List[object]
    foreach ($page in @($Json | ConvertFrom-Json)) {
        foreach ($repo in @($page)) {
            $repos.Add($repo)
        }
    }

    return $repos.ToArray()
}

function Test-GitHubCliAuthenticated {
    # Authenticates via GH_TOKEN/GITHUB_TOKEN or the gh CLI keyring. Minimum token scopes:
    #   - Read-only generation (-Write/-Check): public repo read is enough; a fine-grained
    #     token needs read-only "Metadata" + "Contents" on public repos. GraphQL contribution
    #     calendar data needs classic "read:user" (or fine-grained "Profile" read).
    #   - -ApplyTopics (writes repo topics via PUT /repos/.../topics): needs classic "public_repo"
    #     (or fine-grained "Administration: read and write" on the target public repos).
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN) -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        return $true
    }

    $gh = Invoke-GhCli -Arguments @("auth", "status", "-h", "github.com")
    return ($gh.exitCode -eq 0)
}

function Test-GhApiNotFound {
    param([string]$Output)

    return ((Get-GhApiHttpStatus -Output $Output) -eq 404 -or $Output -match '(?i)\bNot Found\b')
}

function Get-GhApiHttpStatus {
    param([string]$Output)

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return $null
    }

    $match = [regex]::Match($Output, '(?i)\bHTTP\s+(\d{3})\b')
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups[1].Value
}

function Test-RestFallbackReleaseFetchBudget {
    param(
        [int]$RepoCount,
        [bool]$Authenticated,
        [int]$MaxReleaseFetches = $RestFallbackMaxReleaseFetches,
        [int]$UnauthenticatedReleaseFetchLimit = $RestFallbackUnauthenticatedReleaseFetchLimit
    )

    $message = $null
    if ($RepoCount -gt $MaxReleaseFetches) {
        $message = "REST repo metadata fallback would fetch latest-release metadata for $RepoCount repos, exceeding the configured cap of $MaxReleaseFetches requests."
    } elseif (-not $Authenticated -and $RepoCount -gt $UnauthenticatedReleaseFetchLimit) {
        $message = "REST repo metadata fallback requires authenticated gh access for $RepoCount release requests; unauthenticated runs are capped at $UnauthenticatedReleaseFetchLimit to avoid rate-limit partial data."
    }

    return [ordered]@{
        allowed = [string]::IsNullOrWhiteSpace($message)
        message = $message
        repoCount = $RepoCount
        authenticated = [bool]$Authenticated
        maxReleaseFetches = $MaxReleaseFetches
        unauthenticatedReleaseFetchLimit = $UnauthenticatedReleaseFetchLimit
    }
}

function New-RestFallbackReleaseFetchState {
    param(
        [switch]$Used,
        [ValidateSet("not-used", "preflight-passed", "preflight-blocked", "completed", "aborted")]
        [string]$Status = "not-used",
        [int]$RepoCount = 0,
        [bool]$Authenticated = $false,
        [int]$MaxReleaseFetches = $RestFallbackMaxReleaseFetches,
        [int]$UnauthenticatedReleaseFetchLimit = $RestFallbackUnauthenticatedReleaseFetchLimit,
        [int]$AttemptedReleaseFetches = 0,
        [int]$SuccessfulReleaseFetches = 0,
        [int]$NoRelease404Count = 0,
        [bool]$Fatal = $false,
        [string]$AbortRepo = $null,
        [Nullable[int]]$AbortHttpStatus = $null,
        [string]$AbortMessage = $null
    )

    return [ordered]@{
        used = [bool]$Used
        status = $Status
        repoCount = [int]$RepoCount
        authenticated = [bool]$Authenticated
        maxReleaseFetches = [int]$MaxReleaseFetches
        unauthenticatedReleaseFetchLimit = [int]$UnauthenticatedReleaseFetchLimit
        attemptedReleaseFetches = [int]$AttemptedReleaseFetches
        successfulReleaseFetches = [int]$SuccessfulReleaseFetches
        noRelease404Count = [int]$NoRelease404Count
        fatal = [bool]$Fatal
        abortRepo = if ([string]::IsNullOrWhiteSpace($AbortRepo)) { $null } else { $AbortRepo }
        abortHttpStatus = $AbortHttpStatus
        abortMessage = if ([string]::IsNullOrWhiteSpace($AbortMessage)) { $null } else { $AbortMessage }
    }
}

function Reset-RestFallbackReleaseFetchState {
    $script:RestFallbackReleaseFetchState = New-RestFallbackReleaseFetchState
}

function Get-RestFallbackReleaseFetchState {
    if ($null -eq $script:RestFallbackReleaseFetchState) {
        Reset-RestFallbackReleaseFetchState
    }

    return $script:RestFallbackReleaseFetchState
}

function Get-GitHubRepos {
    <#
    .SYNOPSIS
    Fetches the owner's active public repository metadata.
    .DESCRIPTION
    Uses GitHub CLI GraphQL metadata first, retries transient failures, and
    falls back to REST pagination when GraphQL returns an unsafe partial page.
    Release metadata is intentionally excluded from the bulk GraphQL request
    and fetched by Add-ReleaseAssetMetadata to avoid high-complexity 502s.
    #>
    [CmdletBinding()]
    param()

    if ($Offline) {
        Reset-RestFallbackReleaseFetchState
        return @()
    }

    $repoLimit = 500
    $ghArgs = @(
        "repo", "list", $Owner,
        "--visibility", "public",
        "--no-archived",
        "--limit", [string]$repoLimit,
        "--json", "name,description,stargazerCount,defaultBranchRef,licenseInfo,isFork,parent,isPrivate,visibility,isArchived,repositoryTopics,pushedAt,url,primaryLanguage"
    )
    $lastOutput = $null

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $script:MetadataFetchAttemptCount = $attempt
        $gh = Invoke-GhCli -Arguments $ghArgs
        $lastOutput = $gh.text

        if ($gh.exitCode -eq 0) {
            try {
                $repos = @($lastOutput | ConvertFrom-Json)
                if ($repos.Count -eq 0) {
                    throw "GitHub returned an empty repository list."
                }
                if ($repos.Count -eq 100 -and $repoLimit -gt 100) {
                    throw "gh repo list returned exactly 100 repos despite requested limit $repoLimit; falling back to REST pagination to avoid a partial default-page result."
                }
                if ($repos.Count -ge $repoLimit) {
                    Write-Warning "gh repo list returned $($repos.Count) repos (limit $repoLimit); some public repos may be truncated."
                }
                $script:RepositoryMetadataProvider = "graphql"
                $script:RepositoryEnumerationRequestedLimit = $repoLimit
                $script:RepositoryEnumerationTruncated = [bool]($repos.Count -ge $repoLimit)
                Reset-RestFallbackReleaseFetchState
                return $repos
            } catch {
                $lastOutput = $_.Exception.Message
            }
        }

        if ($attempt -lt 3) {
            Start-Sleep -Seconds (2 * $attempt)
        }
    }

    $script:MetadataFetchFallbackReason = $lastOutput
    Write-Warning "GraphQL repo metadata failed after 3 attempts; using REST fallback. Last gh output: $lastOutput"
    return Get-GitHubReposFromRest
}

function ConvertFrom-RestReleaseMetadata {
    param([object]$Release)

    $assetNames = @(Get-ReleaseAssetNamesFromApiRelease -Release $Release)
    $assetDigests = Get-ReleaseAssetDigestsFromApiRelease -Release $Release

    return [pscustomobject]@{
        tagName = Get-MemberValue -Object $Release -Name "tag_name"
        url = Get-MemberValue -Object $Release -Name "html_url"
        name = Get-MemberValue -Object $Release -Name "name"
        publishedAt = Get-MemberValue -Object $Release -Name "published_at"
        releaseAssetNames = $assetNames
        releaseAssetKinds = @(Get-ReleaseAssetKinds -AssetNames $assetNames)
        releaseAssetDigests = $assetDigests
        assetApiInspected = $true
        immutable = Get-MemberValue -Object $Release -Name "immutable"
    }
}

function Add-ReleaseAssetMetadata {
    <#
    .SYNOPSIS
    Enriches repository metadata with latest-release and asset evidence.
    .PARAMETER Repos
    Repository metadata rows returned by GitHub GraphQL or REST enumeration.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    if ($Offline) {
        return @($Repos)
    }

    $repoRows = @($Repos | Sort-Object name | Where-Object {
        $repoName = Get-MemberValue -Object $_ -Name "name"
        -not [string]::IsNullOrWhiteSpace([string]$repoName)
    })

    $authenticated = Test-GitHubCliAuthenticated
    $releaseBudget = Test-RestFallbackReleaseFetchBudget -RepoCount $repoRows.Count -Authenticated $authenticated
    $script:RestFallbackReleaseFetchState = New-RestFallbackReleaseFetchState `
        -Used `
        -Status "preflight-passed" `
        -RepoCount $repoRows.Count `
        -Authenticated:$authenticated `
        -MaxReleaseFetches $releaseBudget.maxReleaseFetches `
        -UnauthenticatedReleaseFetchLimit $releaseBudget.unauthenticatedReleaseFetchLimit
    if (-not $releaseBudget.allowed) {
        $script:RestFallbackReleaseFetchState["status"] = "preflight-blocked"
        $script:RestFallbackReleaseFetchState["fatal"] = $true
        $script:RestFallbackReleaseFetchState["abortMessage"] = $releaseBudget.message
        throw $releaseBudget.message
    }

    foreach ($repo in $repoRows) {
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        $release = Get-MemberValue -Object $repo -Name "latestRelease"
        if ($null -eq $release) {
            Set-MemberValue -Object $repo -Name "latestRelease" -Value $null
        }
        if ($release -and (Test-ReleaseAssetMetadataInspected -Meta $repo)) {
            continue
        }

        $script:RestFallbackReleaseFetchState["attemptedReleaseFetches"] = [int]$script:RestFallbackReleaseFetchState["attemptedReleaseFetches"] + 1
        $gh = Invoke-GhCli -Arguments @("api", "repos/$Owner/$repoName/releases/latest")
        $releaseOutput = $gh.text
        if ($gh.exitCode -ne 0) {
            if (Test-GhApiNotFound -Output $releaseOutput) {
                $script:RestFallbackReleaseFetchState["noRelease404Count"] = [int]$script:RestFallbackReleaseFetchState["noRelease404Count"] + 1
                continue
            }

            if ($release) {
                Set-MemberValue -Object $release -Name "releaseAssetFetchError" -Value $releaseOutput
                Set-MemberValue -Object $release -Name "assetApiInspected" -Value $false
            }
            $script:RestFallbackReleaseFetchState["status"] = "aborted"
            $script:RestFallbackReleaseFetchState["fatal"] = $true
            $script:RestFallbackReleaseFetchState["abortRepo"] = $repoName
            $script:RestFallbackReleaseFetchState["abortHttpStatus"] = Get-GhApiHttpStatus -Output $releaseOutput
            $script:RestFallbackReleaseFetchState["abortMessage"] = "Latest-release fetch failed after $($script:RestFallbackReleaseFetchState["attemptedReleaseFetches"]) attempted request(s)."
            Write-Warning "REST latest-release metadata failed for $repoName; aborting to avoid partial release metadata. Last gh output: $releaseOutput"
            throw "REST latest-release metadata failed while fetching $repoName. Refusing to emit partial release metadata."
        }

        if ([string]::IsNullOrWhiteSpace($releaseOutput)) {
            continue
        }

        $releaseData = $releaseOutput | ConvertFrom-Json
        $script:RestFallbackReleaseFetchState["successfulReleaseFetches"] = [int]$script:RestFallbackReleaseFetchState["successfulReleaseFetches"] + 1
        Set-MemberValue -Object $repo -Name "latestRelease" -Value (ConvertFrom-RestReleaseMetadata -Release $releaseData)
    }

    $script:RestFallbackReleaseFetchState["status"] = "completed"
    return @($Repos)
}

function ConvertTo-BooleanValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [bool]) {
        return [bool]$Value
    }
    return ([string]$Value).ToLowerInvariant() -eq "true"
}

function Get-ContributionCalendar {
    <#
    .SYNOPSIS
    Fetches the owner's GitHub contribution calendar for committed SVG assets.
    .DESCRIPTION
    Returns null in offline mode or when GitHub GraphQL contribution evidence is
    unavailable so generation can preserve the previously committed graph.
    #>
    [CmdletBinding()]
    param()

    if ($Offline) {
        return $null
    }

    $query = 'query($login: String!) { user(login: $login) { contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { contributionCount date weekday } } } } } }'
    try {
        $gh = Invoke-GhCli -Arguments @("api", "graphql", "-f", "query=$query", "-f", "login=$Owner")
        $raw = $gh.text
        if ($gh.exitCode -ne 0) {
            Write-Warning "Contribution calendar fetch failed: $raw"
            return $null
        }
        $parsed = $raw | ConvertFrom-Json
        return $parsed.data.user.contributionsCollection.contributionCalendar
    } catch {
        Write-Warning "Contribution calendar error: $($_.Exception.Message)"
        return $null
    }
}

function Get-RepoNameWithOwner {
    param([object]$Repo)

    foreach ($field in @("nameWithOwner", "full_name", "fullName")) {
        $value = Get-MemberValue -Object $Repo -Name $field
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }

    $owner = Get-MemberValue -Object $Repo -Name "owner"
    $ownerLogin = Get-MemberValue -Object $owner -Name "login"
    $name = Get-MemberValue -Object $Repo -Name "name"
    if (-not [string]::IsNullOrWhiteSpace([string]$ownerLogin) -and -not [string]::IsNullOrWhiteSpace([string]$name)) {
        return "$ownerLogin/$name"
    }

    return $null
}

function Get-ForkParentNameWithOwner {
    param([object]$Meta)

    return Get-RepoNameWithOwner -Repo (Get-MemberValue -Object $Meta -Name "parent")
}

function Add-ForkParentMetadata {
    <#
    .SYNOPSIS
    Completes missing fork-parent metadata for forked repositories.
    .PARAMETER Repos
    Repository metadata rows to enrich with parent repository details.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    if ($Offline) {
        return @($Repos)
    }

    foreach ($repo in @($Repos | Sort-Object name)) {
        if (-not (ConvertTo-BooleanValue (Get-MemberValue -Object $repo -Name "isFork"))) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-ForkParentNameWithOwner -Meta $repo))) {
            continue
        }

        $repoName = Get-MemberValue -Object $repo -Name "name"
        if ([string]::IsNullOrWhiteSpace([string]$repoName)) {
            continue
        }

        $gh = Invoke-GhCli -Arguments @("api", "repos/$Owner/$repoName")
        $repoOutput = $gh.text
        if ($gh.exitCode -ne 0) {
            Set-MemberValue -Object $repo -Name "forkParentFetchError" -Value $repoOutput
            continue
        }

        $repoData = $repoOutput | ConvertFrom-Json
        $parent = Get-MemberValue -Object $repoData -Name "parent"
        $parentName = Get-RepoNameWithOwner -Repo $parent
        if (-not [string]::IsNullOrWhiteSpace([string]$parentName)) {
            Set-MemberValue -Object $repo -Name "parent" -Value ([pscustomobject]@{
                nameWithOwner = [string]$parentName
                url = Get-MemberValue -Object $parent -Name "html_url"
            })
        } else {
            Set-MemberValue -Object $repo -Name "forkParentFetchError" -Value "GitHub reported this repository as a fork, but REST repository metadata did not include a parent."
        }
    }

    return @($Repos)
}

function Set-ForkParentMetadataEnrichmentFailure {
    param(
        [object[]]$Repos,
        [string]$Message
    )

    $reason = if ([string]::IsNullOrWhiteSpace($Message)) {
        "Fork-parent metadata enrichment failed before completing."
    } else {
        "Fork-parent metadata enrichment failed before completing: $Message"
    }

    foreach ($repo in @($Repos | Sort-Object name)) {
        if (-not (ConvertTo-BooleanValue (Get-MemberValue -Object $repo -Name "isFork"))) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-ForkParentNameWithOwner -Meta $repo))) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $repo -Name "forkParentFetchError"))) {
            continue
        }

        Set-MemberValue -Object $repo -Name "forkParentFetchError" -Value $reason
    }

    return @($Repos)
}

function Add-LiveRepositoryMetadata {
    <#
    .SYNOPSIS
    Applies live metadata enrichments needed by generated profile reports.
    .PARAMETER Repos
    Base repository metadata rows from GitHub enumeration.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    if ($Offline) {
        return @($Repos)
    }

    $enrichedRepos = @($Repos)
    try {
        $enrichedRepos = @(Add-ForkParentMetadata -Repos $enrichedRepos)
    } catch {
        $message = $_.Exception.Message
        Write-Warning "Fork-parent metadata enrichment failed; continuing with base repository metadata. $message"
        $enrichedRepos = @(Set-ForkParentMetadataEnrichmentFailure -Repos $enrichedRepos -Message $message)
    }

    return @(Add-ReleaseAssetMetadata -Repos $enrichedRepos)
}

function ConvertTo-Lookup {
    <#
    .SYNOPSIS
    Builds a case-insensitive repository lookup table by repository name.
    .PARAMETER Repos
    Repository metadata rows that may contain a name property.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    $lookup = @{}
    foreach ($repo in $Repos) {
        $repoName = Get-MemberValue -Object $repo -Name "name"
        if ([string]::IsNullOrWhiteSpace([string]$repoName)) {
            continue
        }
        $lookup[([string]$repoName).ToLowerInvariant()] = $repo
    }
    return $lookup
}

function New-CatalogEntry {
    param(
        [string]$Repo,
        [string]$Category,
        [string]$Description,
        [int]$Order
    )

    return [ordered]@{
        repo = $Repo
        title = $Repo
        category = $Category
        includeInReadme = $true
        includeInPortfolio = $true
        order = $Order
        branch = $null
        entrypoint = $null
        installKind = $null
        downloadKind = $null
        userscriptUrl = $null
        liveUrl = $null
        language = $null
        descriptionOverride = $Description
        featured = $false
        featuredRank = $null
        currentlyBuilding = $false
        currentlyBuildingText = $null
        allowPublicMedical = $false
        forkOf = $null
        upstreamLicense = $null
        aliasOf = $null
        suppressionReason = $null
        readmeReviewNote = $null
        notes = $null
    }
}

function Set-IfMissing {
    param(
        [hashtable]$Entry,
        [string]$Name,
        [object]$Value
    )

    if (-not $Entry.Contains($Name)) {
        $Entry[$Name] = $Value
    }
}

function ConvertTo-EntryHashtable {
    param([object]$Entry)

    $json = $Entry | ConvertTo-Json -Depth 20
    $hash = $json | ConvertFrom-Json -AsHashtable

    Set-IfMissing $hash "title" $hash.repo
    Set-IfMissing $hash "includeInReadme" $true
    Set-IfMissing $hash "includeInPortfolio" $true
    Set-IfMissing $hash "order" 9999
    Set-IfMissing $hash "branch" $null
    Set-IfMissing $hash "entrypoint" $null
    Set-IfMissing $hash "installKind" $null
    Set-IfMissing $hash "downloadKind" $null
    Set-IfMissing $hash "userscriptUrl" $null
    Set-IfMissing $hash "liveUrl" $null
    Set-IfMissing $hash "language" $null
    Set-IfMissing $hash "descriptionOverride" $null
    Set-IfMissing $hash "featured" $false
    Set-IfMissing $hash "featuredRank" $null
    Set-IfMissing $hash "currentlyBuilding" $false
    Set-IfMissing $hash "currentlyBuildingText" $null
    Set-IfMissing $hash "allowPublicMedical" $false
    Set-IfMissing $hash "forkOf" $null
    Set-IfMissing $hash "upstreamLicense" $null
    Set-IfMissing $hash "aliasOf" $null
    Set-IfMissing $hash "suppressionReason" $null
    Set-IfMissing $hash "readmeReviewNote" $null
    Set-IfMissing $hash "notes" $null

    return $hash
}

function Get-Catalog {
    <#
    .SYNOPSIS
    Loads and normalizes the profile catalog.
    .PARAMETER Path
    Path to the JSON catalog file to read.
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Catalog not found: $Path. Create data/profile-catalog.json directly, or run scripts/sync-profile.ps1 -SeedCatalog -ForceSeedCatalog only for a lossy one-shot bootstrap."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $catalog = $raw | ConvertFrom-Json
    $entries = foreach ($entry in $catalog.entries) {
        ConvertTo-EntryHashtable $entry
    }

    return [ordered]@{
        schema = $catalog.schema
        generatedAt = $catalog.generatedAt
        entries = @($entries)
    }
}

function Get-RepoMeta {
    param(
        [hashtable]$Entry,
        [hashtable]$RepoLookup
    )

    $key = ([string]$Entry.repo).ToLowerInvariant()
    if ($RepoLookup.ContainsKey($key)) {
        return $RepoLookup[$key]
    }

    if ($Entry.aliasOf) {
        $aliasKey = ([string]$Entry.aliasOf).ToLowerInvariant()
        if ($RepoLookup.ContainsKey($aliasKey)) {
            return $RepoLookup[$aliasKey]
        }
    }

    return $null
}

function Get-Description {
    param(
        [hashtable]$Entry,
        [object]$Meta
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.descriptionOverride)) {
        return [string]$Entry.descriptionOverride
    }
    if ($Meta -and -not [string]::IsNullOrWhiteSpace([string]$Meta.description)) {
        return [string]$Meta.description
    }
    return [string]$Entry.repo
}

function Get-UpstreamUrl {
    param([string]$ForkOf)

    if ([string]::IsNullOrWhiteSpace($ForkOf)) {
        return $null
    }

    if ($ForkOf -match '^[^/\s]+/[^/\s]+$') {
        return "https://github.com/$ForkOf"
    }

    return $null
}

function Get-UpstreamAttribution {
    param([hashtable]$Entry)

    $parts = New-Object System.Collections.Generic.List[string]
    $forkOf = [string]$Entry.forkOf
    if (-not [string]::IsNullOrWhiteSpace($forkOf)) {
        $url = Get-UpstreamUrl -ForkOf $forkOf
        if ($url) {
            $parts.Add("Upstream: [$forkOf]($url)")
        } else {
            $parts.Add("Upstream: $forkOf")
        }
    }

    $upstreamLicense = [string]$Entry.upstreamLicense
    if (-not [string]::IsNullOrWhiteSpace($upstreamLicense)) {
        $parts.Add("License: $upstreamLicense")
    }

    if ($parts.Count -eq 0) {
        return ""
    }

    return "<br/><sub>$($parts -join '; ')</sub>"
}

function Get-DisplayDescription {
    param(
        [hashtable]$Entry,
        [object]$Meta
    )

    return "$(Get-Description $Entry $Meta)$(Get-UpstreamAttribution $Entry)"
}

function Get-Branch {
    param(
        [hashtable]$Entry,
        [object]$Meta
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.branch)) {
        return [string]$Entry.branch
    }
    if ($Meta -and $Meta.defaultBranchRef -and $Meta.defaultBranchRef.name) {
        return [string]$Meta.defaultBranchRef.name
    }
    return "main"
}

function Get-StarText {
    param([object]$Meta)

    if ($Meta -and $Meta.stargazerCount -gt 0) {
        return " &#11088;$($Meta.stargazerCount)"
    }
    return ""
}

function Test-SafeGitHubName {
    <#
    .SYNOPSIS
    Returns true when a repository or owner name is safe to interpolate into a URL or gh api path.
    .DESCRIPTION
    GitHub repository names allow only ASCII letters, digits, period, underscore, and hyphen.
    This guard rejects path-traversal (../), query/fragment injection, whitespace, and slashes so
    catalog-sourced names cannot be tampered into unexpected gh api paths or generated install snippets.
    .PARAMETER Name
    The candidate repository or owner name.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return $Name -match '^[A-Za-z0-9._-]+$'
}

function Get-RepoUrl {
    param([hashtable]$Entry)

    $repo = if ($Entry.aliasOf) { [string]$Entry.aliasOf } else { [string]$Entry.repo }
    return "https://github.com/$Owner/$repo"
}

function Get-ProjectLink {
    param(
        [hashtable]$Entry,
        [object]$Meta
    )

    return "[**$($Entry.title)**]($(Get-RepoUrl $Entry))$(Get-StarText $Meta)"
}

function Get-ReleaseUrl {
    param([hashtable]$Entry)

    $repo = if ($Entry.aliasOf) { [string]$Entry.aliasOf } else { [string]$Entry.repo }
    return "https://github.com/$Owner/$repo/releases/latest"
}

function ConvertTo-ReleaseAssetKind {
    param([string]$Name)

    $lower = ([string]$Name).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($lower)) { return $null }
    if ($lower.EndsWith(".apk")) { return "apk" }
    if ($lower -match '\.(exe|msi|msix|appx|appxbundle)$') { return "exe" }
    if ($lower -match '\.(zip|7z|rar|tgz)$' -or $lower.EndsWith(".tar.gz")) { return "zip" }
    if ($lower.EndsWith(".crx")) { return "crx" }
    if ($lower.EndsWith(".xpi")) { return "xpi" }
    if ($lower.EndsWith(".user.js") -or $lower.EndsWith(".userscript.js")) { return "userscript" }
    if ($lower.EndsWith(".jar")) { return "jar" }
    if ($lower.EndsWith(".deb")) { return "deb" }
    if ($lower.EndsWith(".rpm")) { return "rpm" }
    if ($lower.EndsWith(".dmg")) { return "dmg" }
    if ($lower -match '\.(ps1|bat|cmd|sh)$') { return "script" }
    return "other"
}

function Get-ReleaseAssetKinds {
    param([string[]]$AssetNames)

    $names = @($AssetNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($names.Count -eq 0) {
        return @("source-archive")
    }

    $kinds = foreach ($name in $names) {
        ConvertTo-ReleaseAssetKind -Name $name
    }
    return @($kinds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
}

function Get-ReleaseAssetNamesFromApiRelease {
    param([object]$Release)

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($asset in @((Get-MemberValue -Object $Release -Name "assets"))) {
        $name = Get-MemberValue -Object $asset -Name "name"
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
            $names.Add([string]$name)
        }
    }
    return $names.ToArray()
}

function Get-ReleaseAssetDigestsFromApiRelease {
    param([object]$Release)

    $digests = @{}
    foreach ($asset in @((Get-MemberValue -Object $Release -Name "assets"))) {
        $name = Get-MemberValue -Object $asset -Name "name"
        $digest = Get-MemberValue -Object $asset -Name "digest"
        if (-not [string]::IsNullOrWhiteSpace([string]$name) -and -not [string]::IsNullOrWhiteSpace([string]$digest)) {
            $digests[[string]$name] = [string]$digest
        }
    }
    return $digests
}

function Test-ReleaseAssetMetadataInspected {
    param([object]$Meta)

    $release = Get-MemberValue -Object $Meta -Name "latestRelease"
    if (-not $release) { return $false }
    return [bool](Get-MemberValue -Object $release -Name "assetApiInspected")
}

function Get-ReleaseAssetKindsFromMeta {
    param([object]$Meta)

    $release = Get-MemberValue -Object $Meta -Name "latestRelease"
    if (-not $release) { return @() }
    $kinds = @(Get-MemberValue -Object $release -Name "releaseAssetKinds")
    return @($kinds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-ReleaseAssetNamesFromMeta {
    param([object]$Meta)

    $release = Get-MemberValue -Object $Meta -Name "latestRelease"
    if (-not $release) { return @() }
    $names = @(Get-MemberValue -Object $release -Name "releaseAssetNames")
    return @($names | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Test-HasDownloadableReleaseAsset {
    param([string[]]$AssetKinds)

    return @($AssetKinds | Where-Object { $_ -ne "source-archive" }).Count -gt 0
}

function Get-ExecutableReleaseAssetKinds {
    param([string[]]$AssetKinds)

    $executableKinds = @("apk", "crx", "deb", "dmg", "exe", "jar", "rpm", "script", "userscript", "xpi", "zip")
    return @($AssetKinds | Where-Object { $_ -in $executableKinds } | Sort-Object -Unique)
}

function Test-ChecksumCoverageForExecutableAssets {
    param(
        [string[]]$ExecutableAssetNames,
        [string[]]$ChecksumAssets
    )

    $executables = @($ExecutableAssetNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($executables.Count -eq 0 -or $ChecksumAssets.Count -eq 0) {
        return $false
    }

    $checksums = @($ChecksumAssets | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if (@($checksums | Where-Object { $_ -match '(^|[-_.])(checksums?|sums)([-_.]|$)' }).Count -gt 0) {
        return $true
    }

    foreach ($asset in $executables) {
        $assetLower = ([string]$asset).ToLowerInvariant()
        $stemLower = [System.IO.Path]::GetFileNameWithoutExtension($assetLower)
        $matched = @($checksums | Where-Object { $_.Contains($assetLower) -or (-not [string]::IsNullOrWhiteSpace($stemLower) -and $_.Contains($stemLower)) }).Count -gt 0
        if (-not $matched) {
            return $false
        }
    }

    return $true
}

function New-ReleaseTrust {
    param(
        [string[]]$AssetKinds,
        [string[]]$AssetNames,
        [bool]$HasRelease,
        [bool]$AssetInspected,
        [object]$Immutable = $null,
        [hashtable]$AssetDigests = @{}
    )

    $names = @($AssetNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $checksumAssets = @($names | Where-Object { $_ -match '(?i)(sha256|sha512|checksum|checksums|sums|\.sha256|\.sha512)' } | Sort-Object)
    $signatureAssets = @($names | Where-Object { $_ -match '(?i)(\.sig$|\.asc$|signature|signatures)' } | Sort-Object)
    $sbomAssets = @($names | Where-Object { $_ -match '(?i)(sbom|spdx|cyclonedx)' } | Sort-Object)
    $attestationAssets = @($names | Where-Object { $_ -match '(?i)(attestation|intoto|in-toto|\.att$)' } | Sort-Object)
    $debugArtifactPresent = [bool](@($names | Where-Object { $_ -match '(?i)(^|[-_.])debug([-_.]|$)' }).Count)
    $executableAssetKinds = @(Get-ExecutableReleaseAssetKinds -AssetKinds $AssetKinds)
    $executableAssetNames = @(
        $names |
            Where-Object {
                $assetKind = @(Get-ReleaseAssetKinds -AssetNames @([string]$_))
                @(Get-ExecutableReleaseAssetKinds -AssetKinds $assetKind).Count -gt 0
            }
    )
    $hasChecksumForEveryExecutable = Test-ChecksumCoverageForExecutableAssets -ExecutableAssetNames $executableAssetNames -ChecksumAssets $checksumAssets
    $sourceOnlyRelease = [bool]($HasRelease -and $AssetInspected -and @($AssetKinds).Count -eq 1 -and $AssetKinds[0] -eq "source-archive")

    $trustLevel = "unknown"
    if ($HasRelease -and $AssetInspected) {
        $trustLevel = "metadata-only"
        if ($checksumAssets.Count -gt 0) {
            $trustLevel = "checksum-metadata"
        }
        if ($signatureAssets.Count -gt 0) {
            $trustLevel = "signature-metadata"
        }
        if ($attestationAssets.Count -gt 0) {
            $trustLevel = "attestation-metadata"
        }
        if ($signatureAssets.Count -gt 0 -and $attestationAssets.Count -gt 0) {
            $trustLevel = "signature-and-attestation-metadata"
        }
    }

    $checksumCoverage = "none"
    if ($checksumAssets.Count -gt 0) {
        $checksumCoverage = if ($hasChecksumForEveryExecutable -and $executableAssetNames.Count -gt 0) { "full" } else { "partial" }
    }

    return [ordered]@{
        checksumAssets = @($checksumAssets)
        checksumCoverage = $checksumCoverage
        hasChecksumForEveryExecutable = $hasChecksumForEveryExecutable
        signatureAssets = @($signatureAssets)
        hasAuthenticodeSignature = $null
        apkSignatureVerified = $null
        sbomAssets = @($sbomAssets)
        attestationAvailable = [bool]($attestationAssets.Count -gt 0)
        debugArtifactPresent = $debugArtifactPresent
        sourceOnlyRelease = $sourceOnlyRelease
        executableAssetKinds = @($executableAssetKinds)
        trustLevel = $trustLevel
        platformDigestCount = if ($HasRelease) { [int]$AssetDigests.Count } else { 0 }
        releaseImmutable = if ($HasRelease -and $null -ne $Immutable) { [bool]$Immutable } else { $null }
        notesPublic = if ($HasRelease -and $AssetInspected) { "Metadata evidence only: derived from release asset filenames and GitHub release API asset digests; binaries were not downloaded or locally verified." } else { $null }
    }
}

function ConvertTo-IsoText {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [datetime]) {
        return $Value.ToString("o")
    }
    return [string]$Value
}

function ConvertTo-DateTimeOffsetOrNull {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [datetimeoffset]) {
        return $Value
    }
    if ($Value -is [datetime]) {
        return [datetimeoffset]$Value
    }

    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Get-AgeDays {
    param(
        [object]$Value,
        [datetimeoffset]$Now
    )

    $parsed = ConvertTo-DateTimeOffsetOrNull -Value $Value
    if ($null -eq $parsed) {
        return $null
    }
    return [math]::Round(($Now.ToUniversalTime() - $parsed.ToUniversalTime()).TotalDays, 2)
}

function ConvertTo-RawGitHubUrl {
    param(
        [string]$Repo,
        [string]$Branch,
        [string]$Path
    )

    $segments = $Path -split '[\\/]'
    $encodedPath = ($segments | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    return "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/$encodedPath"
}

function Test-HttpUrl {
    param([string]$Url, [int]$TimeoutSec = 12, [int]$Retries = 2)

    # Returns ok/status/error plus a `fatal` flag. Only a definitive dead-link
    # response (404/410) is fatal; transient blocks (403/429/5xx/timeout) are
    # reported as non-fatal warnings so a flaky host does not fail the whole gate.
    $status = $null
    $err = $null
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        foreach ($method in @('Head', 'Get')) {
            try {
                $response = Invoke-WebRequest -Uri $Url -Method $method -MaximumRedirection 5 -TimeoutSec $TimeoutSec
                $code = [int]$response.StatusCode
                return [ordered]@{ ok = ($code -ge 200 -and $code -lt 400); status = $code; error = $null; fatal = $false }
            } catch {
                $err = $_.Exception.Message
                $status = $null
                # StrictMode-safe: not every exception type (e.g. DNS failures) exposes
                # a Response property, so probe for it before dereferencing.
                $exception = $_.Exception
                if ($exception.PSObject.Properties.Name -contains 'Response' -and $exception.Response) {
                    $response = $exception.Response
                    if ($response.PSObject.Properties.Name -contains 'StatusCode' -and $response.StatusCode) {
                        $status = [int]$response.StatusCode
                    }
                }
                if ($status -eq 404 -or $status -eq 410) {
                    return [ordered]@{ ok = $false; status = $status; error = $err; fatal = $true }
                }
            }
        }
        if ($attempt -lt $Retries) { Start-Sleep -Seconds $attempt }
    }
    return [ordered]@{ ok = $false; status = $status; error = $err; fatal = $false }
}

function Get-LinkHost {
    param([string]$Url)

    try {
        return ([Uri]$Url).Host.ToLowerInvariant()
    } catch {
        return $null
    }
}

function New-LinkValidationTarget {
    param(
        [hashtable]$Entry,
        [string]$Type,
        [string]$Url,
        [string]$Repo = $null,
        [bool]$FatalOnFailure = $true,
        [string]$Group = "catalog"
    )

    $targetRepo = if (-not [string]::IsNullOrWhiteSpace($Repo)) {
        $Repo
    } elseif ($Entry -and -not [string]::IsNullOrWhiteSpace([string]$Entry.repo)) {
        [string]$Entry.repo
    } else {
        $Owner
    }

    return [ordered]@{
        repo = $targetRepo
        type = $Type
        url = $Url
        host = Get-LinkHost $Url
        fatalOnFailure = [bool]$FatalOnFailure
        group = $Group
    }
}

function Get-LinkValidationTargets {
    param(
        [hashtable[]]$Included,
        [hashtable]$RepoLookup
    )

    $targets = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $Included) {
        $meta = Get-RepoMeta $entry $RepoLookup
        $repoForUrl = if ($entry.aliasOf) { [string]$entry.aliasOf } else { [string]$entry.repo }
        $branch = Get-Branch $entry $meta

        if (-not [string]::IsNullOrWhiteSpace([string]$entry.entrypoint)) {
            $url = ConvertTo-RawGitHubUrl -Repo $repoForUrl -Branch $branch -Path ([string]$entry.entrypoint)
            $targets.Add((New-LinkValidationTarget -Entry $entry -Type "entrypoint" -Url $url))
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$entry.userscriptUrl)) {
            $url = [string]$entry.userscriptUrl
            $targets.Add((New-LinkValidationTarget -Entry $entry -Type "userscript" -Url $url))
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$entry.liveUrl)) {
            $url = [string]$entry.liveUrl
            $targets.Add((New-LinkValidationTarget -Entry $entry -Type "launch" -Url $url))
        }

        $action = Get-PrimaryAction $entry $meta $entry.category
        if ($action["kind"] -eq "release") {
            $targets.Add((New-LinkValidationTarget -Entry $entry -Type "release" -Url ([string]$action["url"])))
        }
    }

    return $targets.ToArray()
}

function Add-LinkValidationTarget {
    param(
        [System.Collections.Generic.List[object]]$Targets,
        [System.Collections.Generic.HashSet[string]]$SeenUrls,
        [string]$Type,
        [string]$Url,
        [bool]$FatalOnFailure,
        [string]$Group = "readme-header"
    )

    if ([string]::IsNullOrWhiteSpace($Url) -or -not $Url.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    if ($SeenUrls.Add($Url)) {
        $Targets.Add((New-LinkValidationTarget -Repo $Owner -Type $Type -Url $Url -FatalOnFailure $FatalOnFailure -Group $Group))
    }
}

function Get-ReadmeHeaderLinkValidationTargets {
    param([string]$ExpectedReadme)

    $targets = New-Object System.Collections.Generic.List[object]
    $seenUrls = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $criticalLinks = @(
        [ordered]@{ type = "profile-portfolio"; url = "https://sysadmindoc.github.io/" },
        [ordered]@{ type = "setup-raw"; url = "https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1" },
        [ordered]@{ type = "setup-source"; url = "https://github.com/SysAdminDoc/SysAdminDoc/blob/main/setup.ps1" }
    )
    foreach ($link in $criticalLinks) {
        if ($ExpectedReadme.Contains([string]$link.url)) {
            Add-LinkValidationTarget -Targets $targets -SeenUrls $seenUrls -Type ([string]$link.type) -Url ([string]$link.url) -FatalOnFailure $true
        }
    }

    foreach ($match in [regex]::Matches($ExpectedReadme, '(?i)\b(?:src|srcset)="(?<url>https://[^"]+)"')) {
        Add-LinkValidationTarget -Targets $targets -SeenUrls $seenUrls -Type "header-image" -Url $match.Groups['url'].Value -FatalOnFailure $false
    }

    foreach ($match in [regex]::Matches($ExpectedReadme, '(?i)!\[[^\]]*\]\((?<url>https://[^\s)]+)[^)]*\)')) {
        Add-LinkValidationTarget -Targets $targets -SeenUrls $seenUrls -Type "header-image" -Url $match.Groups['url'].Value -FatalOnFailure $false
    }

    return $targets.ToArray()
}

function Invoke-LinkProbeBatch {
    param(
        [object[]]$Targets,
        [int]$ThrottleLimit = $LinkValidationThrottle,
        [scriptblock]$ProbeScript = $null
    )

    $targetList = @($Targets)
    $throttle = [Math]::Max(1, $ThrottleLimit)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if ($targetList.Count -eq 0) {
        $stopwatch.Stop()
        return [ordered]@{
            results = @()
            targetCount = 0
            throttleLimit = $throttle
            elapsedMs = $stopwatch.ElapsedMilliseconds
        }
    }

    if ($ProbeScript) {
        $probeRows = foreach ($target in $targetList) {
            $result = & $ProbeScript $target
            $targetFatalOnFailure = if ($target -is [System.Collections.IDictionary] -and $target.Contains('fatalOnFailure')) {
                [bool]$target['fatalOnFailure']
            } elseif ($target.PSObject.Properties.Name -contains 'fatalOnFailure') {
                [bool]$target.fatalOnFailure
            } else {
                $true
            }
            [ordered]@{
                repo = $target.repo
                type = $target.type
                url = $target.url
                host = $target.host
                ok = [bool]$result.ok
                status = $result.status
                error = $result.error
                fatal = [bool]($targetFatalOnFailure -and [bool]$result.fatal)
            }
        }
    } else {
        $testHttpUrlDefinition = ${function:Test-HttpUrl}.ToString()
        $probeRows = $targetList | ForEach-Object -Parallel {
            ${function:Test-HttpUrl} = $using:testHttpUrlDefinition
            $target = $_
            $result = Test-HttpUrl -Url $target.url
            $targetFatalOnFailure = if ($target -is [System.Collections.IDictionary] -and $target.Contains('fatalOnFailure')) {
                [bool]$target['fatalOnFailure']
            } elseif ($target.PSObject.Properties.Name -contains 'fatalOnFailure') {
                [bool]$target.fatalOnFailure
            } else {
                $true
            }
            [ordered]@{
                repo = $target.repo
                type = $target.type
                url = $target.url
                host = $target.host
                ok = [bool]$result.ok
                status = $result.status
                error = $result.error
                fatal = [bool]($targetFatalOnFailure -and [bool]$result.fatal)
            }
        } -ThrottleLimit $throttle
    }

    $stopwatch.Stop()
    return [ordered]@{
        results = @($probeRows)
        targetCount = $targetList.Count
        throttleLimit = $throttle
        elapsedMs = $stopwatch.ElapsedMilliseconds
    }
}

function Test-LinkTargets {
    param(
        [hashtable[]]$Included,
        [hashtable]$RepoLookup,
        [object[]]$ExtraTargets = @(),
        [int]$ThrottleLimit = $LinkValidationThrottle,
        [scriptblock]$ProbeScript = $null
    )

    $targets = @((Get-LinkValidationTargets -Included $Included -RepoLookup $RepoLookup) + @($ExtraTargets))
    $probeBatch = Invoke-LinkProbeBatch -Targets $targets -ThrottleLimit $ThrottleLimit -ProbeScript $ProbeScript
    $failures = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[object]

    foreach ($result in @($probeBatch.results | Where-Object { -not $_.ok } | Sort-Object repo, type, url)) {
        $row = [ordered]@{
            repo = $result.repo
            type = $result.type
            url = $result.url
            host = $result.host
            status = $result.status
            error = $result.error
        }
        if ($result.fatal) { $failures.Add($row) } else { $warnings.Add($row) }
    }

    $warningCountByHost = @(
        $warnings |
            Group-Object { $_.host } |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    host = if ([string]::IsNullOrWhiteSpace([string]$_.Name)) { $null } else { [string]$_.Name }
                    count = $_.Count
                }
            }
    )
    $headerHostWarnings = @(
        $warnings |
            Where-Object { $_.type -eq "header-image" } |
            Group-Object { $_.host } |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    host = if ([string]::IsNullOrWhiteSpace([string]$_.Name)) { $null } else { [string]$_.Name }
                    count = $_.Count
                }
            }
    )

    return [ordered]@{
        failures = $failures.ToArray()
        warnings = $warnings.ToArray()
        warningCountByHost = $warningCountByHost
        headerHostWarnings = $headerHostWarnings
        targetCount = $probeBatch.targetCount
        throttleLimit = $probeBatch.throttleLimit
        elapsedMs = $probeBatch.elapsedMs
    }
}

function Get-DownloadLabel {
    param(
        [hashtable]$Entry,
        [string]$Category
    )

    $kind = Get-EffectiveDownloadKind -Entry $Entry -Category $Category
    switch ($kind) {
        "apk" { return "APK" }
        "exe" { return "EXE" }
        "zip" { return "ZIP" }
        "zip-xpi" { return "ZIP/XPI" }
        "crx" { return "CRX" }
        "xpi" { return "XPI" }
        "crx-xpi" { return "CRX/XPI" }
        "userscript" { return "Install" }
        default { return "Download" }
    }
}

function Get-EffectiveDownloadKind {
    param(
        [hashtable]$Entry,
        [string]$Category
    )

    $kind = ([string]$Entry.downloadKind).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($kind)) {
        switch ($Category) {
            "android" { $kind = "apk" }
            "extensions" { $kind = "download" }
            "desktop" { $kind = "zip" }
            default { $kind = "download" }
        }
    }
    return $kind
}

function Get-ExpectedReleaseAssetKinds {
    param(
        [hashtable]$Entry,
        [string]$Category
    )

    $kind = Get-EffectiveDownloadKind -Entry $Entry -Category $Category
    switch ($kind) {
        "apk" { return @("apk") }
        "exe" { return @("exe") }
        "zip" { return @("zip") }
        "zip-xpi" { return @("zip", "xpi") }
        "crx" { return @("crx") }
        "xpi" { return @("xpi") }
        "crx-xpi" { return @("crx", "xpi") }
        "download" { return @("downloadable") }
        default { return @($kind) }
    }
}

function Test-ReleaseAssetKindMatch {
    param(
        [string[]]$ExpectedKinds,
        [string[]]$ActualKinds
    )

    if (@($ExpectedKinds).Count -eq 0) {
        return $true
    }
    if (@($ExpectedKinds | Where-Object { $_ -eq "downloadable" }).Count -gt 0) {
        return Test-HasDownloadableReleaseAsset -AssetKinds $ActualKinds
    }
    foreach ($kind in @($ExpectedKinds)) {
        if (@($ActualKinds | Where-Object { $_ -eq $kind }).Count -eq 0) {
            return $false
        }
    }
    return $true
}

function Get-CategoryDisplayName {
    param([string]$Slug)

    $def = $CategoryDefinitions | Where-Object { $_.Slug -eq $Slug } | Select-Object -First 1
    if ($def -and -not [string]::IsNullOrWhiteSpace([string]$def.DisplayName)) {
        return [string]$def.DisplayName
    }
    return $Slug
}

function ConvertTo-SearchSlug {
    param([string]$Value)

    $normalized = ([string]$Value).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    $normalized = $normalized -replace '#', ' sharp '
    $normalized = $normalized -replace '\+', ' plus '
    $slug = ($normalized -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return $null
    }

    return $slug
}

function Add-SearchMetadataValue {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    $clean = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return
    }
    if (-not $List.Contains($clean)) {
        $List.Add($clean)
    }
}

function Get-ProjectSearchType {
    param(
        [hashtable]$Entry,
        [string]$PrimaryActionKind
    )

    $category = ([string]$Entry.category).ToLowerInvariant()
    $downloadKind = ([string]$Entry.downloadKind).ToLowerInvariant()

    if ($PrimaryActionKind -eq "install" -or $downloadKind -eq "userscript") {
        return "userscript"
    }

    switch ($category) {
        "android" { return "android-app" }
        "desktop" { return "desktop-app" }
        "extensions" { return "browser-extension" }
        "guides" { return "guide" }
        "media" { return "media-tool" }
        "powershell" { return "powershell-tool" }
        "python" { return "python-tool" }
        "security" { return "security-tool" }
        "web" { return "web-app" }
        default {
            if ($PrimaryActionKind -eq "release") { return "downloadable-project" }
            return "repository"
        }
    }
}

function Get-ProjectSearchTypeLabel {
    param([string]$Type)

    switch ($Type) {
        "android-app" { return "Android app" }
        "browser-extension" { return "Browser extension" }
        "desktop-app" { return "Desktop app" }
        "downloadable-project" { return "Downloadable project" }
        "guide" { return "Guide" }
        "media-tool" { return "Media tool" }
        "powershell-tool" { return "PowerShell tool" }
        "python-tool" { return "Python tool" }
        "repository" { return "Repository" }
        "security-tool" { return "Security tool" }
        "userscript" { return "Userscript" }
        "web-app" { return "Web app" }
        default { return "Project" }
    }
}

function New-ProjectSearchMetadata {
    param(
        [hashtable]$Entry,
        [object]$PrimaryAction,
        [string]$Language
    )

    $category = ([string]$Entry.category).ToLowerInvariant()
    $categoryLabel = Get-CategoryDisplayName -Slug $category
    $actionKind = [string]$PrimaryAction["kind"]
    $type = Get-ProjectSearchType -Entry $Entry -PrimaryActionKind $actionKind
    $typeLabel = Get-ProjectSearchTypeLabel -Type $type
    $languageSlug = ConvertTo-SearchSlug -Value $Language

    $labels = New-Object System.Collections.Generic.List[string]
    Add-SearchMetadataValue -List $labels -Value $categoryLabel
    Add-SearchMetadataValue -List $labels -Value $typeLabel

    $filters = New-Object System.Collections.Generic.List[string]
    Add-SearchMetadataValue -List $filters -Value "category:$category"
    Add-SearchMetadataValue -List $filters -Value "type:$type"
    if (-not [string]::IsNullOrWhiteSpace($languageSlug)) {
        Add-SearchMetadataValue -List $filters -Value "language:$languageSlug"
    }

    return [ordered]@{
        type = $type
        labels = @($labels.ToArray())
        filters = @($filters.ToArray())
    }
}

function Get-CategoryAnchor {
    param([string]$Slug)

    switch ($Slug) {
        "powershell" { return "powershell-system-utilities" }
        "python" { return "python-desktop-applications" }
        "web" { return "web-applications" }
        "extensions" { return "browser-extensions--userscripts" }
        "android" { return "android-applications" }
        "security" { return "security--networking" }
        "media" { return "media--conversion-tools" }
        "desktop" { return "native-desktop-applications" }
        "guides" { return "guides--resources" }
        "misc" { return "misc--forks" }
        default { return $Slug }
    }
}

function Get-PrimaryAction {
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [string]$Category
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.liveUrl)) {
        return [ordered]@{
            kind = "live"
            label = "Launch"
            url = [string]$Entry.liveUrl
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.userscriptUrl)) {
        return [ordered]@{
            kind = "install"
            label = "Install"
            url = [string]$Entry.userscriptUrl
        }
    }

    if (([string]$Entry.downloadKind).ToLowerInvariant() -eq "repo") {
        return [ordered]@{
            kind = "repo"
            label = "Repo"
            url = Get-RepoUrl $Entry
        }
    }

    if ($Meta -and $Meta.latestRelease) {
        if ((Test-ReleaseAssetMetadataInspected -Meta $Meta) -and -not (Test-HasDownloadableReleaseAsset -AssetKinds (Get-ReleaseAssetKindsFromMeta -Meta $Meta))) {
            return [ordered]@{
                kind = "repo"
                label = "Repo"
                url = Get-RepoUrl $Entry
            }
        }
        $label = Get-DownloadLabel $Entry $Category
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = "Download"
        }
        return [ordered]@{
            kind = "release"
            label = $label
            url = Get-ReleaseUrl $Entry
        }
    }

    return [ordered]@{
        kind = "repo"
        label = "Repo"
        url = Get-RepoUrl $Entry
    }
}

function Get-ActionLink {
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [string]$Category
    )

    $action = Get-PrimaryAction $Entry $Meta $Category
    $label = [string]$action["label"]
    $url = [string]$action["url"]
    if ($action["kind"] -eq "release") {
        return "[<kbd>&#11015;&nbsp;$label</kbd>]($url)"
    }

    return "[$label]($url)"
}

function Get-InstallSnippet {
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [string]$Category
    )

    $branch = Get-Branch $Entry $Meta
    $installKind = if (-not [string]::IsNullOrWhiteSpace([string]$Entry.installKind)) {
        [string]$Entry.installKind
    } else {
        ($CategoryDefinitions | Where-Object { $_.Slug -eq $Category }).DefaultInstallKind
    }

    $entrypoint = [string]$Entry.entrypoint
    if ([string]::IsNullOrWhiteSpace($entrypoint)) {
        return $null
    }

    $runner = if ($installKind -eq "powershell") {
        '& "$d\{0}"' -f $entrypoint
    } else {
        'python "$d\{0}"' -f $entrypoint
    }

    return '$d="$env:TEMP\{0}"; if(Test-Path $d){{git -C $d pull -q}}else{{git clone -q --depth 1 -b {1} https://github.com/{2}/{0} $d}}; if(Test-Path "$d\requirements.txt"){{pip install -q -r "$d\requirements.txt"}}; {3}' -f $Entry.repo, $branch, $Owner, $runner
}

function New-CategoryLink {
    param([string]$Slug)

    return "[{0}](#{1})" -f (Get-CategoryDisplayName $Slug), (Get-CategoryAnchor $Slug)
}

function New-CategoryPreviewLine {
    param(
        [hashtable[]]$Items
    )

    $picks = @($Items |
        Sort-Object @{ Expression = { if ($_.featured -eq $true) { 0 } else { 1 } } },
                    @{ Expression = { if ($_.featuredRank) { [int]$_.featuredRank } else { [int]$_.order } } },
                    repo |
        Select-Object -First 3)

    if ($picks.Count -eq 0) {
        return $null
    }

    $links = foreach ($entry in $picks) {
        "[**$($entry.title)**]($(Get-RepoUrl $entry))"
    }

    return "Suggested starting points: $($links -join ', ')."
}

function New-DiscoverySection {
    $powershellLink = New-CategoryLink "powershell"
    $desktopLink = New-CategoryLink "desktop"
    $extensionsLink = New-CategoryLink "extensions"
    $androidLink = New-CategoryLink "android"
    $webLink = New-CategoryLink "web"
    $setupLink = "[First-time setup](#first-time-setup)"
    $validationLink = "[Local validation](#local-validation)"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("### Start Here")
    $lines.Add("")
    $lines.Add("This profile organizes public projects by platform. Use the portfolio for search and filters, or jump to the section that matches your machine, browser, or device.")
    $lines.Add("")
    $lines.Add("| Goal | Best path | What to expect |")
    $lines.Add("|:-----|:----------|:---------------|")
    $lines.Add("| Run a Windows utility | $powershellLink or $desktopLink | One-liner install commands and release downloads. |")
    $lines.Add("| Install a browser or Android tool | $extensionsLink or $androidLink | CRX, XPI, userscript, and APK installs labeled per project. |")
    $lines.Add("| Launch a web tool | $webLink | Browser-based tools that work without local setup. |")
    $lines.Add("| Set up a fresh Windows machine | $setupLink | Guided Python and Git setup with an inspect-before-install path. |")
    $lines.Add("| Validate this repo | $validationLink | Runs markdownlint, PSScriptAnalyzer, and Pester with pinned tool versions. |")
    $lines.Add("| Search the full catalog | [Full portfolio](https://sysadmindoc.github.io/) | Filterable catalog generated from this repo's project feed. |")

    return ($lines -join [Environment]::NewLine)
}

function New-FirstTimeSetupSection {
    return @'
<a id="first-time-setup"></a>

<details>
<summary><b>&#128190; First-time setup</b> -- <i>Install Python 3 + Git only if your machine needs them.</i></summary>
<br/>

The command below checks for Python and Git before installing anything, then refreshes the current shell so the project snippets work immediately. On a fresh Windows machine, open **PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1 | iex
```

Inspect before installing:

```powershell
$u='https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1'; $p="$env:TEMP\SysAdminDoc-setup.ps1"; irm $u -OutFile $p; notepad $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -CheckOnly
```

| Step | Behavior |
|:-----|:---------|
| Checks first | Skips Python or Git when already installed. |
| Inspect before installing | Save the script, review it, then run `-CheckOnly` to report Python, Git, pip, and winget state without installing. |
| Installs with Windows tooling | Uses `winget` for [Python 3.12](https://www.python.org/) and [Git for Windows](https://git-scm.com/). |
| Refreshes the shell | Updates the current `PATH` so the commands below work without reopening PowerShell. |
| Records diagnostics | Writes a best-effort transcript to `%TEMP%\SysAdminDoc-setup-*.log`. |
| Shows its source | [`setup.ps1`](https://github.com/SysAdminDoc/SysAdminDoc/blob/main/setup.ps1) is the exact script being run. |

Already have Python and Git? Skip this section and open the category you need.

</details>
'@
}

function New-LocalValidationSection {
    return @'
<a id="local-validation"></a>

<details>
<summary><b>&#9989; Local validation</b> -- <i>Install pinned validation tools and run every local check.</i></summary>
<br/>

Use this from the repo root before pushing profile, catalog, or validation changes:

```powershell
pwsh -NoProfile -File .\scripts\validate-local.ps1
```

Run the manual dependency and advisory review:

```powershell
npm run review:dependencies
```

| Check | Behavior |
|:------|:---------|
| Node tools | Runs `npm ci` before markdownlint so the pinned local package is present. |
| Dependency review | Runs `npm audit --json`, checks package override drift, verifies npm lock pins, and reports PowerShell plus Python audit-tool pins. |
| PowerShell tools | Installs and imports Pester 5.8.0 plus PSScriptAnalyzer 1.25.0 for the current user when needed. |
| Markdown | Runs `npm run lint:markdown` against the tracked public Markdown set. |
| Static analysis | Runs PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`. |
| Tests | Runs `Invoke-Pester -Path tests -Output Detailed`. |

Already bootstrapped? Add `-SkipBootstrap` to reuse installed modules and `node_modules`.

</details>
'@
}

function New-CategorySection {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup,
        [hashtable]$Definition
    )

    $items = @($Entries | Where-Object { $_.category -eq $Definition.Slug } | Sort-Object @{ Expression = {
        $key = ([string]$_.repo).ToLowerInvariant()
        $m = if ($RepoLookup -and $RepoLookup.ContainsKey($key)) { $RepoLookup[$key] } else { $null }
        if ($m -and $null -ne $m.stargazerCount) { [int]$m.stargazerCount } else { 0 }
    }; Descending = $true }, repo)
    # Skip categories with no visible entries so an empty <details> shell is never rendered.
    if ($items.Count -eq 0) {
        return ""
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<a id=`"$(Get-CategoryAnchor $Definition.Slug)`"></a>")
    $lines.Add("<details>")
    $lines.Add(($Definition.Summary -f $items.Count))
    $lines.Add("<br/>")
    $lines.Add("")
    $preview = New-CategoryPreviewLine -Items $items
    if ($preview) {
        $lines.Add($preview)
        $lines.Add("")
    }

    switch ($Definition.Render) {
        "code" {
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $line = "$(Get-ProjectLink $entry $meta) -- $(Get-DisplayDescription $entry $meta)"
                $action = Get-ActionLink $entry $meta $Definition.Slug
                if ($action -match 'releases/latest') {
                    $line += " &nbsp;$action"
                }
                $lines.Add($line)
                $snippet = Get-InstallSnippet $entry $meta $Definition.Slug
                if ($snippet) {
                    $lines.Add('```powershell')
                    $lines.Add($snippet)
                    $lines.Add('```')
                    $lines.Add("")
                } else {
                    $lines.Add("")
                }
            }
        }
        "web-table" {
            $lines.Add("| Project | Description | Live |")
            $lines.Add("|:--------|:------------|:----:|")
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-DisplayDescription $entry $meta) | $(Get-ActionLink $entry $meta $Definition.Slug) |")
            }
            $lines.Add("")
        }
        "install-table" {
            $lines.Add("| Project | Description | Install |")
            $lines.Add("|:--------|:------------|:-------:|")
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-DisplayDescription $entry $meta) | $(Get-ActionLink $entry $meta $Definition.Slug) |")
            }
            $lines.Add("")
        }
        "download-table" {
            $lines.Add("| Project | Description | Download |")
            $lines.Add("|:--------|:------------|:--------:|")
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-DisplayDescription $entry $meta) | $(Get-ActionLink $entry $meta $Definition.Slug) |")
            }
            $lines.Add("")
        }
        "desktop-table" {
            $lines.Add("| Project | Description | Language | Download |")
            $lines.Add("|:--------|:------------|:--------:|:--------:|")
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $language = if (-not [string]::IsNullOrWhiteSpace([string]$entry.language)) {
                    [string]$entry.language
                } elseif ($meta -and $meta.primaryLanguage -and $meta.primaryLanguage.name) {
                    [string]$meta.primaryLanguage.name
                } else {
                    ""
                }
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-DisplayDescription $entry $meta) | $language | $(Get-ActionLink $entry $meta $Definition.Slug) |")
            }
            $lines.Add("")
        }
        "simple-table" {
            $lines.Add("| Project | Description |")
            $lines.Add("|:--------|:------------|")
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-DisplayDescription $entry $meta) |")
            }
            $lines.Add("")
        }
    }

    $lines.Add("</details>")
    return ($lines -join [Environment]::NewLine)
}

function New-FeaturedSection {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $featured = @($Entries | Where-Object { $_.featured -eq $true } | Sort-Object @{ Expression = { if ($_.featuredRank) { [int]$_.featuredRank } else { 9999 } } }, repo)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("### Featured Projects")
    $lines.Add("")
    $lines.Add("Representative ready-to-run projects. Each item keeps one direct action line so visitors can download, launch, install, or open the repo without scanning the full catalog.")
    $lines.Add("")
    foreach ($entry in $featured) {
        $meta = Get-RepoMeta $entry $RepoLookup
        $stars = if ($meta) { [int]$meta.stargazerCount } else { 0 }
        $category = Get-CategoryDisplayName $entry.category
        $action = Get-ActionLink $entry $meta $entry.category
        $lines.Add("- [**$($entry.title)**]($(Get-RepoUrl $entry)) -- $category, &#11088;$stars<br/>$(Get-DisplayDescription $entry $meta)<br/>Action: $action")
    }
    return ($lines -join [Environment]::NewLine)
}

function New-ThemeAwareImage {
    param(
        [string]$DarkUrl,
        [string]$LightUrl,
        [string]$Alt,
        [string]$Attributes = ""
    )

    $suffix = if ([string]::IsNullOrWhiteSpace($Attributes)) { "" } else { " $Attributes" }
    return "<picture><source media=`"(prefers-color-scheme: dark)`" srcset=`"$DarkUrl`"><source media=`"(prefers-color-scheme: light)`" srcset=`"$LightUrl`"><img src=`"$DarkUrl`" alt=`"$Alt`"$suffix /></picture>"
}

function ConvertTo-SvgText {
    param([object]$Value)

    if ($null -eq $Value) { return "" }
    return [System.Security.SecurityElement]::Escape([string]$Value)
}

function ConvertTo-SvgId {
    param([string]$Value)

    $slug = ([string]$Value).ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "profile-svg"
    }
    return "profile-$slug"
}

function New-ProfilePanelDescription {
    param(
        [string]$Subtitle,
        [object[]]$Rows
    )

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        $parts.Add($Subtitle.Trim())
    }

    $rowSummaries = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($Rows)) {
        $value = [string](Get-MemberValue -Object $row -Name "value")
        $label = [string](Get-MemberValue -Object $row -Name "label")
        $detail = [string](Get-MemberValue -Object $row -Name "detail")

        if ([string]::IsNullOrWhiteSpace($value) -and [string]::IsNullOrWhiteSpace($label)) {
            continue
        }

        $summary = @($value.Trim(), $label.Trim()) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $summaryText = ($summary -join " ")
        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            $summaryText = "$summaryText ($($detail.Trim()))"
        }
        $rowSummaries.Add($summaryText)
    }

    if ($rowSummaries.Count -gt 0) {
        $parts.Add("Rows: $($rowSummaries -join '; ').")
    }

    return ($parts -join " ")
}

function New-ProfilePanelSvg {
    param(
        [string]$Title,
        [string]$Subtitle,
        [object[]]$Rows,
        [ValidateSet("dark", "light")]
        [string]$Theme,
        [int]$Width = 820,
        [int]$Height = 250
    )

    if ($Theme -eq "dark") {
        $bg = "#0d1117"; $panel = "#161b22"; $border = "#30363d"; $titleColor = "#f0f6fc"; $text = "#c9d1d9"; $muted = "#8b949e"; $accent = "#58a6ff"; $rule = "#1f6feb"
    } else {
        $bg = "#ffffff"; $panel = "#f6f8fa"; $border = "#d0d7de"; $titleColor = "#24292f"; $text = "#24292f"; $muted = "#57606a"; $accent = "#0969da"; $rule = "#0969da"
    }

    $baseId = ConvertTo-SvgId "$Title $Theme"
    $titleId = "$baseId-title"
    $descId = "$baseId-desc"
    $description = New-ProfilePanelDescription -Subtitle $Subtitle -Rows $Rows

    $rowY = 112
    $columns = 2
    $physicalRows = [math]::Ceiling(@($Rows).Count / $columns)
    $lastContentY = $rowY + (($physicalRows - 1) * 54) + 36
    $minHeight = $lastContentY + 30
    $Height = [math]::Max($Height, $minHeight)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-labelledby=`"$titleId`" aria-describedby=`"$descId`">")
    $lines.Add("  <title id=`"$titleId`">$(ConvertTo-SvgText $Title)</title>")
    $lines.Add("  <desc id=`"$descId`">$(ConvertTo-SvgText $description)</desc>")
    $lines.Add("  <rect width=`"100%`" height=`"100%`" rx=`"0`" fill=`"$bg`"/>")
    $lines.Add("  <rect x=`"12`" y=`"12`" width=`"$($Width - 24)`" height=`"$($Height - 24)`" rx=`"12`" fill=`"$panel`" stroke=`"$border`"/>")
    $lines.Add("  <line x1=`"28`" y1=`"28`" x2=`"$($Width - 28)`" y2=`"28`" stroke=`"$rule`" stroke-width=`"1`" opacity=`"0.45`"/>")
    $lines.Add("  <text x=`"32`" y=`"45`" fill=`"$titleColor`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"20`" font-weight=`"700`">$(ConvertTo-SvgText $Title)</text>")
    $lines.Add("  <text x=`"32`" y=`"70`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"13`">$(ConvertTo-SvgText $Subtitle)</text>")
    $lines.Add("  <line x1=`"32`" y1=`"84`" x2=`"$($Width - 32)`" y2=`"84`" stroke=`"$border`" stroke-width=`"0.5`" opacity=`"0.6`"/>")

    $colWidth = [math]::Floor(($Width - 64) / $columns)
    for ($i = 0; $i -lt @($Rows).Count; $i++) {
        $row = $Rows[$i]
        $col = $i % $columns
        $line = [math]::Floor($i / $columns)
        $x = 32 + ($col * $colWidth)
        $y = $rowY + ($line * 54)
        $value = Get-MemberValue -Object $row -Name "value"
        $label = Get-MemberValue -Object $row -Name "label"
        $detail = Get-MemberValue -Object $row -Name "detail"
        $lines.Add("  <rect x=`"$x`" y=`"$($y - 14)`" width=`"3`" height=`"20`" rx=`"1.5`" fill=`"$accent`"/>")
        $lines.Add("  <text x=`"$($x + 14)`" y=`"$y`" fill=`"$text`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"20`" font-weight=`"700`">$(ConvertTo-SvgText $value)</text>")
        $lines.Add("  <text x=`"$($x + 14)`" y=`"$($y + 20)`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"12`">$(ConvertTo-SvgText $label)</text>")
        if (-not [string]::IsNullOrWhiteSpace([string]$detail)) {
            $lines.Add("  <text x=`"$($x + 14)`" y=`"$($y + 36)`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"11`">$(ConvertTo-SvgText $detail)</text>")
        }
    }

    $lines.Add("</svg>")
    return ($lines -join [Environment]::NewLine)
}

function New-ProfileHeroSvg {
    param(
        [ValidateSet("dark", "light")]
        [string]$Theme,
        [int]$Width = 820,
        [int]$Height = 240
    )

    if ($Theme -eq "dark") {
        $bg = "#0d1117"; $panel = "#161b22"; $border = "#30363d"; $titleColor = "#f0f6fc"; $text = "#c9d1d9"; $muted = "#8b949e"; $accent = "#58a6ff"; $accentStrong = "#1f6feb"
    } else {
        $bg = "#ffffff"; $panel = "#f6f8fa"; $border = "#d0d7de"; $titleColor = "#24292f"; $text = "#57606a"; $muted = "#57606a"; $accent = "#0969da"; $accentStrong = "#0969da"
    }

    $title = "SysAdminDoc profile header"
    $description = "Static profile header for a healthcare IT engineer, DICOM/PACS specialist, product builder, and public open-source catalog maintainer."
    $baseId = ConvertTo-SvgId "$title $Theme"
    $titleId = "$baseId-title"
    $descId = "$baseId-desc"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-labelledby=`"$titleId`" aria-describedby=`"$descId`">")
    $lines.Add("  <title id=`"$titleId`">$(ConvertTo-SvgText $title)</title>")
    $lines.Add("  <desc id=`"$descId`">$(ConvertTo-SvgText $description)</desc>")
    $lines.Add("  <rect width=`"100%`" height=`"100%`" fill=`"$bg`"/>")
    $lines.Add("  <rect x=`"16`" y=`"16`" width=`"$($Width - 32)`" height=`"$($Height - 32)`" rx=`"12`" fill=`"$panel`" stroke=`"$border`"/>")
    $lines.Add("  <rect x=`"16`" y=`"16`" width=`"4`" height=`"$($Height - 32)`" rx=`"2`" fill=`"$accentStrong`"/>")
    $center = [math]::Floor($Width / 2)
    $lines.Add("  <line x1=`"$($center - 92)`" y1=`"52`" x2=`"$($center + 92)`" y2=`"52`" stroke=`"$accent`" stroke-width=`"2`" opacity=`"0.9`"/>")
    $lines.Add("  <text x=`"$center`" y=`"82`" text-anchor=`"middle`" fill=`"$accent`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"14`" font-weight=`"700`">PUBLIC OPEN-SOURCE CATALOG</text>")
    $lines.Add("  <text x=`"$center`" y=`"130`" text-anchor=`"middle`" fill=`"$titleColor`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"48`" font-weight=`"700`">SysAdminDoc</text>")
    $lines.Add("  <text x=`"$center`" y=`"164`" text-anchor=`"middle`" fill=`"$text`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"17`" font-weight=`"600`">Healthcare IT Engineer | DICOM/PACS Specialist | Product Builder</text>")
    $lines.Add("  <text x=`"$center`" y=`"192`" text-anchor=`"middle`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"14`">16+ years in IT operations | Windows, Android, web, automation, and imaging workflows</text>")
    $lines.Add("  <text x=`"$center`" y=`"216`" text-anchor=`"middle`" fill=`"$accent`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"13`" font-weight=`"600`">PowerShell / Python / Kotlin / C# / Rust</text>")
    $lines.Add("</svg>")
    return ($lines -join [Environment]::NewLine)
}

function New-ProfileFooterSvg {
    param(
        [ValidateSet("dark", "light")]
        [string]$Theme,
        [int]$Width = 820,
        [int]$Height = 120
    )

    if ($Theme -eq "dark") {
        $bg = "#0d1117"; $waveOne = "#161b22"; $waveTwo = "#1f6feb"; $line = "#30363d"
    } else {
        $bg = "#ffffff"; $waveOne = "#f6f8fa"; $waveTwo = "#dbeafe"; $line = "#d0d7de"
    }

    $title = "Decorative footer wave for the SysAdminDoc profile"
    $description = "Static footer divider used by the generated profile README."
    $baseId = ConvertTo-SvgId "$title $Theme"
    $titleId = "$baseId-title"
    $descId = "$baseId-desc"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-labelledby=`"$titleId`" aria-describedby=`"$descId`">")
    $lines.Add("  <title id=`"$titleId`">$(ConvertTo-SvgText $title)</title>")
    $lines.Add("  <desc id=`"$descId`">$(ConvertTo-SvgText $description)</desc>")
    $lines.Add("  <rect width=`"100%`" height=`"100%`" fill=`"$bg`"/>")
    $lines.Add("  <path d=`"M0 70 C140 38 280 34 410 64 C540 94 670 88 820 50 L820 120 L0 120 Z`" fill=`"$waveOne`" stroke=`"$line`" stroke-width=`"0.5`"/>")
    $lines.Add("  <path d=`"M0 88 C160 52 300 56 440 82 C570 108 690 100 820 66 L820 120 L0 120 Z`" fill=`"$waveTwo`" opacity=`"0.25`"/>")
    $lines.Add("  <path d=`"M0 100 C180 74 340 78 480 96 C600 112 720 106 820 82 L820 120 L0 120 Z`" fill=`"$waveTwo`" opacity=`"0.12`"/>")
    $lines.Add("</svg>")
    return ($lines -join [Environment]::NewLine)
}

function Get-TopLanguageRows {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $counts = @{}
    foreach ($entry in $Entries) {
        $meta = Get-RepoMeta $entry $RepoLookup
        $language = if (-not [string]::IsNullOrWhiteSpace([string]$entry.language)) {
            [string]$entry.language
        } elseif ($meta -and $meta.primaryLanguage -and $meta.primaryLanguage.name) {
            [string]$meta.primaryLanguage.name
        } else {
            "Other"
        }
        if (-not $counts.ContainsKey($language)) { $counts[$language] = 0 }
        $counts[$language]++
    }

    return @(
        $counts.GetEnumerator() |
            Sort-Object @{ Expression = { [int]$_.Value }; Descending = $true }, Name |
            Select-Object -First 6 |
            ForEach-Object {
                [ordered]@{
                    label = [string]$_.Key
                    value = [string]$_.Value
                    detail = "visitor-facing projects"
                }
            }
    )
}

function New-ContributionGraphSvg {
    <#
    .SYNOPSIS
    Renders a theme-aware GitHub contribution heatmap SVG.
    .PARAMETER Calendar
    GitHub contribution calendar object returned by Get-ContributionCalendar.
    .PARAMETER Theme
    Visual theme variant to render.
    .PARAMETER Width
    Minimum SVG width; the function expands it when more week columns are present.
    #>
    [CmdletBinding()]
    param(
        [object]$Calendar,
        [ValidateSet("dark", "light")]
        [string]$Theme,
        [int]$Width = 820
    )

    if ($Theme -eq "dark") {
        $bg = "#0d1117"; $panel = "#161b22"; $border = "#30363d"; $titleColor = "#f0f6fc"
        $muted = "#8b949e"; $rule = "#1f6feb"
        $cellEmpty = "#161b22"
        $cellLevels = @("#0e4429", "#006d32", "#26a641", "#39d353")
    } else {
        $bg = "#ffffff"; $panel = "#f6f8fa"; $border = "#d0d7de"; $titleColor = "#24292f"
        $muted = "#57606a"; $rule = "#0969da"
        $cellEmpty = "#ebedf0"
        $cellLevels = @("#9be9a8", "#40c463", "#30a14e", "#216e39")
    }

    $weeks = @()
    $totalContributions = 0
    if ($null -ne $Calendar) {
        $weeks = @($Calendar.weeks)
        $total = Get-MemberValue -Object $Calendar -Name "totalContributions"
        if ($null -ne $total) { $totalContributions = [int]$total }
    }

    $cellSize = 12
    $cellGap = 2
    $cellStep = $cellSize + $cellGap
    $gridLeft = 60
    $gridTop = 100
    $monthLabelY = $gridTop - 8
    $minimumWidth = $gridLeft + ([Math]::Max(53, $weeks.Count) * $cellStep) + 32
    $Width = [Math]::Max($Width, $minimumWidth)
    $gridHeight = 7 * $cellStep - $cellGap
    $Height = $gridTop + $gridHeight + 40

    $title = "Contribution activity for $Owner"
    $description = "GitHub contribution heatmap showing $totalContributions contributions in the last year."
    $baseId = ConvertTo-SvgId "$title $Theme"
    $titleId = "$baseId-title"
    $descId = "$baseId-desc"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-labelledby=`"$titleId`" aria-describedby=`"$descId`">")
    $lines.Add("  <title id=`"$titleId`">$(ConvertTo-SvgText $title)</title>")
    $lines.Add("  <desc id=`"$descId`">$(ConvertTo-SvgText $description)</desc>")
    $lines.Add("  <rect width=`"100%`" height=`"100%`" rx=`"0`" fill=`"$bg`"/>")
    $lines.Add("  <rect x=`"12`" y=`"12`" width=`"$($Width - 24)`" height=`"$($Height - 24)`" rx=`"12`" fill=`"$panel`" stroke=`"$border`"/>")
    $lines.Add("  <line x1=`"28`" y1=`"28`" x2=`"$($Width - 28)`" y2=`"28`" stroke=`"$rule`" stroke-width=`"1`" opacity=`"0.45`"/>")
    $lines.Add("  <text x=`"32`" y=`"45`" fill=`"$titleColor`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"20`" font-weight=`"700`">Contribution Activity</text>")
    $lines.Add("  <text x=`"32`" y=`"70`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"13`">$totalContributions contributions in the last year</text>")
    $lines.Add("  <line x1=`"32`" y1=`"84`" x2=`"$($Width - 32)`" y2=`"84`" stroke=`"$border`" stroke-width=`"0.5`" opacity=`"0.6`"/>")

    $dayLabels = @("", "Mon", "", "Wed", "", "Fri", "")
    for ($d = 0; $d -lt 7; $d++) {
        if (-not [string]::IsNullOrWhiteSpace($dayLabels[$d])) {
            $labelY = $gridTop + ($d * $cellStep) + $cellSize - 2
            $lines.Add("  <text x=`"32`" y=`"$labelY`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"10`">$($dayLabels[$d])</text>")
        }
    }

    $monthNames = @("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")
    $lastMonth = -1
    for ($w = 0; $w -lt $weeks.Count; $w++) {
        $weekDays = @($weeks[$w].contributionDays)
        if ($weekDays.Count -eq 0) { continue }

        $firstDate = [string]$weekDays[0].date
        if ($firstDate -match '^\d{4}-(\d{2})-') {
            $month = [int]$Matches[1] - 1
            if ($month -ne $lastMonth) {
                $labelX = $gridLeft + ($w * $cellStep)
                $lines.Add("  <text x=`"$labelX`" y=`"$monthLabelY`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"10`">$($monthNames[$month])</text>")
                $lastMonth = $month
            }
        }

        foreach ($day in $weekDays) {
            $count = 0
            $countVal = Get-MemberValue -Object $day -Name "contributionCount"
            if ($null -ne $countVal) { $count = [int]$countVal }
            $weekday = 0
            $wdVal = Get-MemberValue -Object $day -Name "weekday"
            if ($null -ne $wdVal) { $weekday = [int]$wdVal }

            if ($count -eq 0) {
                $fill = $cellEmpty
            } elseif ($count -le 2) {
                $fill = $cellLevels[0]
            } elseif ($count -le 5) {
                $fill = $cellLevels[1]
            } elseif ($count -le 9) {
                $fill = $cellLevels[2]
            } else {
                $fill = $cellLevels[3]
            }

            $cx = $gridLeft + ($w * $cellStep)
            $cy = $gridTop + ($weekday * $cellStep)
            $lines.Add("  <rect x=`"$cx`" y=`"$cy`" width=`"$cellSize`" height=`"$cellSize`" rx=`"2`" fill=`"$fill`"/>")
        }
    }

    $legendY = $gridTop + $gridHeight + 16
    $legendX = $Width - 200
    $lines.Add("  <text x=`"$legendX`" y=`"$($legendY + 10)`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"10`">Less</text>")
    $legendBoxX = $legendX + 28
    $lines.Add("  <rect x=`"$legendBoxX`" y=`"$legendY`" width=`"$cellSize`" height=`"$cellSize`" rx=`"2`" fill=`"$cellEmpty`"/>")
    foreach ($lvl in 0..3) {
        $lx = $legendBoxX + (($lvl + 1) * $cellStep)
        $lines.Add("  <rect x=`"$lx`" y=`"$legendY`" width=`"$cellSize`" height=`"$cellSize`" rx=`"2`" fill=`"$($cellLevels[$lvl])`"/>")
    }
    $moreX = $legendBoxX + (5 * $cellStep) + 4
    $lines.Add("  <text x=`"$moreX`" y=`"$($legendY + 10)`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"10`">More</text>")

    $lines.Add("</svg>")
    return ($lines -join [Environment]::NewLine)
}

function Get-ExistingProfileAssetText {
    <#
    .SYNOPSIS
    Reads an existing generated profile asset for fallback preservation.
    .PARAMETER AssetPath
    Repository-relative or absolute asset path to read.
    #>
    [CmdletBinding()]
    param([string]$AssetPath)

    $normalizedPath = $AssetPath -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $fullPath = if ([System.IO.Path]::IsPathRooted($normalizedPath)) {
        $normalizedPath
    } else {
        Join-Path $RepoRoot $normalizedPath
    }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $null
    }
    return (Get-Content -LiteralPath $fullPath -Raw).TrimEnd()
}

function New-ContributionAssetSvg {
    <#
    .SYNOPSIS
    Builds or preserves a contribution graph SVG asset.
    .PARAMETER AssetPath
    Target contribution SVG asset path.
    .PARAMETER Calendar
    Contribution calendar object; null preserves an existing committed asset.
    .PARAMETER Theme
    Visual theme variant to render when a calendar is available.
    #>
    [CmdletBinding()]
    param(
        [string]$AssetPath,
        [object]$Calendar,
        [ValidateSet("dark", "light")]
        [string]$Theme
    )

    if ($null -eq $Calendar) {
        $existing = Get-ExistingProfileAssetText -AssetPath $AssetPath
        if (-not [string]::IsNullOrWhiteSpace($existing)) {
            return $existing
        }
    }
    return New-ContributionGraphSvg -Calendar $Calendar -Theme $Theme
}

function New-ProfileAssetSvgs {
    <#
    .SYNOPSIS
    Generates the committed theme-aware SVG profile assets.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER Repos
    Live or offline repository metadata used for counts and release summaries.
    .PARAMETER ContributionCalendar
    Contribution calendar object from Get-ContributionCalendar, or $null for offline/empty.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [object]$ContributionCalendar
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries | Where-Object {
        $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
    })
    $releaseDrift = Test-ReleaseAssetDrift -Entries $entries -RepoLookup $repoLookup
    $currentBuilds = @($entries | Where-Object { $_.currentlyBuilding -eq $true }).Count
    $totalStars = 0
    foreach ($repo in @($Repos)) {
        $stars = Get-MemberValue -Object $repo -Name "stargazerCount"
        if ($null -ne $stars -and [string]$stars -match '^\d+$') {
            $totalStars += [int]$stars
        }
    }
    $languageRows = @(Get-TopLanguageRows -Entries $entries -RepoLookup $repoLookup)
    $assetPathPrefix = ($AssetsPath -replace '\\', '/').TrimEnd('/')

    $statsRows = @(
        [ordered]@{ label = "active public repositories"; value = [string]@($Repos | Where-Object { $null -ne $_ }).Count; detail = "live GitHub metadata" },
        [ordered]@{ label = "visitor-facing projects"; value = [string]@($entries).Count; detail = "generated profile catalog" },
        [ordered]@{ label = "total public stars"; value = [string]$totalStars; detail = "live GitHub metadata" },
        [ordered]@{ label = "currently building"; value = [string]$currentBuilds; detail = "first-viewport queue" }
    )
    $activityRows = @(
        [ordered]@{ label = "latest releases inspected"; value = [string]$releaseDrift.inspectedReleaseRows; detail = "asset names normalized" },
        [ordered]@{ label = "release kind mismatches"; value = [string]@($releaseDrift.releaseAssetKindMismatches).Count; detail = "catalog vs assets" },
        [ordered]@{ label = "source-only release rows"; value = [string]@($releaseDrift.sourceOnlyWithRelease).Count; detail = "kept as Repo actions" },
        [ordered]@{ label = "asset fetch failures"; value = [string]@($releaseDrift.releaseAssetFetchFailures).Count; detail = "latest report" }
    )

    $assets = [ordered]@{}
    $assets["$assetPathPrefix/header-dark.svg"] = New-ProfileHeroSvg -Theme dark
    $assets["$assetPathPrefix/header-light.svg"] = New-ProfileHeroSvg -Theme light
    $assets["$assetPathPrefix/stats-dark.svg"] = New-ProfilePanelSvg -Title "SysAdminDoc Catalog Stats" -Subtitle "Generated from public GitHub metadata and data/profile-catalog.json" -Rows $statsRows -Theme dark
    $assets["$assetPathPrefix/stats-light.svg"] = New-ProfilePanelSvg -Title "SysAdminDoc Catalog Stats" -Subtitle "Generated from public GitHub metadata and data/profile-catalog.json" -Rows $statsRows -Theme light
    $assets["$assetPathPrefix/languages-dark.svg"] = New-ProfilePanelSvg -Title "Language Mix" -Subtitle "Top visitor-facing project languages from the catalog" -Rows $languageRows -Theme dark
    $assets["$assetPathPrefix/languages-light.svg"] = New-ProfilePanelSvg -Title "Language Mix" -Subtitle "Top visitor-facing project languages from the catalog" -Rows $languageRows -Theme light
    $assets["$assetPathPrefix/activity-dark.svg"] = New-ProfilePanelSvg -Title "Release Asset Health" -Subtitle "Generated release taxonomy and validation summary" -Rows $activityRows -Theme dark
    $assets["$assetPathPrefix/activity-light.svg"] = New-ProfilePanelSvg -Title "Release Asset Health" -Subtitle "Generated release taxonomy and validation summary" -Rows $activityRows -Theme light
    $contributionsDarkPath = "$assetPathPrefix/contributions-dark.svg"
    $contributionsLightPath = "$assetPathPrefix/contributions-light.svg"
    $assets[$contributionsDarkPath] = New-ContributionAssetSvg -AssetPath $contributionsDarkPath -Calendar $ContributionCalendar -Theme dark
    $assets[$contributionsLightPath] = New-ContributionAssetSvg -AssetPath $contributionsLightPath -Calendar $ContributionCalendar -Theme light
    $assets["$assetPathPrefix/footer-dark.svg"] = New-ProfileFooterSvg -Theme dark
    $assets["$assetPathPrefix/footer-light.svg"] = New-ProfileFooterSvg -Theme light
    return $assets
}

function New-ProfileChrome {
    $assetPathPrefix = ($AssetsPath -replace '\\', '/').TrimEnd('/')
    $headerImage = New-ThemeAwareImage -DarkUrl "$assetPathPrefix/header-dark.svg" -LightUrl "$assetPathPrefix/header-light.svg" -Alt 'SysAdminDoc - Healthcare IT Engineer, DICOM/PACS Specialist, Product Builder' -Attributes 'width="100%"'

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('<p align="center">')
    $lines.Add("  $headerImage")
    $lines.Add('</p>')
    $lines.Add('')
    $lines.Add('<p align="center">')
    $lines.Add('  <strong>Healthcare IT engineer and DICOM/PACS specialist</strong><br/>')
    $lines.Add('  16+ years in IT operations, 10+ production platforms, and public tools across Python, React, C++, C#, Go, Rust, Kotlin, and PowerShell.')
    $lines.Add('</p>')
    $lines.Add('')
    return ($lines -join [Environment]::NewLine)
}

function New-ProfileStatsChrome {
    $assetPathPrefix = ($AssetsPath -replace '\\', '/').TrimEnd('/')
    $skillsDark = "https://skillicons.dev/icons?i=powershell,python,js,kotlin,cs,cpp,html,css,dotnet,qt,androidstudio,git,github&theme=dark&perline=13"
    $skillsLight = "https://skillicons.dev/icons?i=powershell,python,js,kotlin,cs,cpp,html,css,dotnet,qt,androidstudio,git,github&theme=light&perline=13"
    $statsImage = New-ThemeAwareImage -DarkUrl "$assetPathPrefix/stats-dark.svg" -LightUrl "$assetPathPrefix/stats-light.svg" -Alt 'Generated SysAdminDoc public catalog statistics' -Attributes 'width="48%"'
    $languagesImage = New-ThemeAwareImage -DarkUrl "$assetPathPrefix/languages-dark.svg" -LightUrl "$assetPathPrefix/languages-light.svg" -Alt 'Generated SysAdminDoc public project language mix' -Attributes 'width="48%"'
    $activityImage = New-ThemeAwareImage -DarkUrl "$assetPathPrefix/activity-dark.svg" -LightUrl "$assetPathPrefix/activity-light.svg" -Alt 'Generated SysAdminDoc release asset validation summary' -Attributes 'width="98%"'
    $contributionsImage = New-ThemeAwareImage -DarkUrl "$assetPathPrefix/contributions-dark.svg" -LightUrl "$assetPathPrefix/contributions-light.svg" -Alt 'GitHub contribution activity heatmap for SysAdminDoc' -Attributes 'width="98%"'

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('---')
    $lines.Add('')
    $lines.Add('<p align="center">')
    $lines.Add('  <a href="https://skillicons.dev">')
    $lines.Add("    $(New-ThemeAwareImage -DarkUrl $skillsDark -LightUrl $skillsLight -Alt 'PowerShell, Python, JavaScript, Kotlin, C#, C++, HTML, CSS, .NET, Qt, Android Studio, Git, and GitHub')")
    $lines.Add('  </a>')
    $lines.Add('</p>')
    $lines.Add('')
    $lines.Add('---')
    $lines.Add('')
    $lines.Add('<p align="center">')
    $lines.Add("  $statsImage")
    $lines.Add("  $languagesImage")
    $lines.Add('</p>')
    $lines.Add('')
    $lines.Add('<p align="center">')
    $lines.Add("  $activityImage")
    $lines.Add('</p>')
    $lines.Add('')
    $lines.Add('<p align="center">')
    $lines.Add("  $contributionsImage")
    $lines.Add('</p>')
    $lines.Add('')
    $lines.Add('---')

    return ($lines -join [Environment]::NewLine)
}

function New-ProfileFooter {
    $assetPathPrefix = ($AssetsPath -replace '\\', '/').TrimEnd('/')
    return New-ThemeAwareImage -DarkUrl "$assetPathPrefix/footer-dark.svg" -LightUrl "$assetPathPrefix/footer-light.svg" -Alt "Decorative footer wave for the SysAdminDoc profile" -Attributes 'width="100%"'
}

function Update-Header {
    param(
        [string]$Header,
        [int]$PublicRepoCount,
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $chromePatterns = @(
        '(?s)\r?\n(?:---\r?\n\r?\n)?<p align="center">\s*<a href="https://skillicons\.dev">.*?github-readme-activity-graph\.vercel\.app.*?</p>\r?\n\r?\n---',
        '(?s)\r?\n(?:---\r?\n\r?\n)?<p align="center">\s*<a href="https://skillicons\.dev">.*?assets/profile/activity-(?:dark|light)\.svg.*?</p>\r?\n\r?\n---'
    )
    $updated = $Header
    foreach ($chromePattern in $chromePatterns) {
        do {
            $previous = $updated
            $updated = [regex]::Replace($updated, $chromePattern, [Environment]::NewLine)
        } while ($updated -ne $previous)
    }
    $focusMarker = "### Professional Focus"
    $hasRichProfileHeader = $updated.Contains($focusMarker) -or
        $updated.Contains("Healthcare IT engineer and DICOM/PACS specialist") -or
        $updated.Contains("https://skillicons.dev") -or
        $updated.Contains("assets/profile/stats-")
    $focusIndex = $updated.IndexOf($focusMarker, [StringComparison]::Ordinal)
    if ($focusIndex -ge 0) {
        $updated = $updated.Substring($focusIndex)
    }

    $updated = $updated -replace '\d+%2B\+open\+source\+tools', "$PublicRepoCount%2B+open+source+tools"
    $updated = $updated -replace '- \d+\+ open source projects across', "- $PublicRepoCount+ open source projects across"
    $updated = $updated -replace 'Public portfolio: \d+ active repos, \d+ visitor-facing projects,', "Public portfolio: $PublicRepoCount active repos, $($Entries.Count) visitor-facing projects,"
    $updated = $updated -replace '\| Public catalog \| \d+ active repos,', "| Public catalog | $PublicRepoCount active repos,"

    if ($hasRichProfileHeader) {
        $updated = (New-ProfileChrome) + [Environment]::NewLine + [Environment]::NewLine + $updated
    }

    $building = @($Entries | Where-Object { $_.currentlyBuilding -eq $true } | Sort-Object @{ Expression = { [int]$_.order } }, repo)
    if ($hasRichProfileHeader -and $building.Count -gt 0) {
        $tableLines = New-Object System.Collections.Generic.List[string]
        $tableLines.Add("**Currently Building**")
        $tableLines.Add("")
        $tableLines.Add("| Project | Focus | Action |")
        $tableLines.Add("|:--------|:------|:------:|")
        foreach ($entry in $building) {
            $meta = Get-RepoMeta $entry $RepoLookup
            $text = if (-not [string]::IsNullOrWhiteSpace([string]$entry.currentlyBuildingText)) {
                "$([string]$entry.currentlyBuildingText)$(Get-UpstreamAttribution $entry)"
            } else {
                Get-DisplayDescription $entry $meta
            }
            $project = "[**$($entry.title)**]($(Get-RepoUrl $entry))"
            $action = Get-ActionLink $entry $meta $entry.category
            $tableLines.Add("| $project | $text | $action |")
        }
        $table = $tableLines -join [Environment]::NewLine
        $pattern = '(?s)\*\*Currently Building\*\*\r?\n\r?\n\|[^\r\n]+\|\r?\n\|[:\-\| ]+\|\r?\n(?:\|.*?\|\r?\n)+'
        $updated = [regex]::Replace($updated, $pattern, $table + [Environment]::NewLine)
    }

    $updated = [regex]::Replace($updated.TrimEnd(), '(\r?\n\s*---\s*)+$', '')
    if ($hasRichProfileHeader) {
        return $updated.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + (New-ProfileStatsChrome)
    }
    return $updated.TrimEnd()
}

function New-Readme {
    <#
    .SYNOPSIS
    Renders the generated GitHub profile README from catalog and repo metadata.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER Repos
    Repository metadata used for stars, release actions, topics, and counts.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries | Where-Object {
        $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
    })
    $readmeReadPath = if ([System.IO.Path]::IsPathRooted($ReadmePath)) { $ReadmePath } else { Join-Path $RepoRoot $ReadmePath }
    $readme = Get-Content -LiteralPath $readmeReadPath -Raw
    $sectionMarkers = @($GeneratedCatalogNotice, "### Start Here", "### Featured Projects")
    $includeGeneratedNotice = $readme.Contains($GeneratedCatalogNotice)
    $includeDiscoverySection = $readme.Contains("### Start Here") -or $readme.Contains("### Catalog Snapshot")
    $start = -1
    foreach ($marker in $sectionMarkers) {
        $markerIndex = $readme.IndexOf($marker, [StringComparison]::Ordinal)
        if ($markerIndex -ge 0 -and ($start -lt 0 -or $markerIndex -lt $start)) {
            $start = $markerIndex
        }
    }
    if ($start -lt 0) {
        throw "README marker not found: generated catalog notice, ### Start Here, or ### Featured Projects"
    }
    $footer = New-ProfileFooter
    $repoCount = @($Repos | Where-Object { $null -ne $_ }).Count
    $publicCount = if ($repoCount -gt 0) { $repoCount } else { @($entries | Select-Object -ExpandProperty repo -Unique).Count }
    $header = Update-Header -Header $readme.Substring(0, $start) -PublicRepoCount $publicCount -Entries $entries -RepoLookup $repoLookup
    $header = [regex]::Replace($header, '(\r?\n\s*---\s*)+$', [Environment]::NewLine + [Environment]::NewLine + '---')

    $blocks = New-Object System.Collections.Generic.List[string]
    $blocks.Add($header)
    $blocks.Add("")
    if ($includeGeneratedNotice) {
        $blocks.Add($GeneratedCatalogNotice)
        $blocks.Add("")
    }
    if ($includeDiscoverySection) {
        $blocks.Add((New-DiscoverySection))
        $blocks.Add("")
        $blocks.Add("---")
        $blocks.Add("")
    }
    $blocks.Add((New-FirstTimeSetupSection))
    $blocks.Add("")
    $blocks.Add((New-LocalValidationSection))
    $blocks.Add("")

    foreach ($definition in $CategoryDefinitions) {
        $section = New-CategorySection -Entries $entries -RepoLookup $repoLookup -Definition $definition
        if ([string]::IsNullOrEmpty($section)) {
            continue
        }
        $blocks.Add($section)
        $blocks.Add("")
    }

    $blocks.Add($footer)
    $blocks.Add("")
    return ($blocks -join [Environment]::NewLine)
}

function Get-SuppressionReasonCode {
    param([string]$Reason)

    if ([string]::IsNullOrWhiteSpace($Reason)) {
        return "other"
    }

    $normalized = $Reason.ToLowerInvariant()
    if ($normalized -match '\b(private|medical|x-ray|xray|dicom|pacs|radiology)\b') {
        return "private-or-sensitive"
    }
    if ($normalized -match '\b(duplicate|renamed|superseded|fork)\b') {
        return "duplicate-or-superseded"
    }
    if ($normalized -match '\bplaceholder\b') {
        return "placeholder"
    }
    if ($normalized -match '\b(not visitor-facing|not ready|omitted|keep out|not included)\b') {
        return "not-visitor-facing"
    }

    return "other"
}

function Get-PublicSuppressionReason {
    param([string]$ReasonCode)

    switch ($ReasonCode) {
        "private-or-sensitive" { return "Private or sensitive project omitted from the public feed." }
        "duplicate-or-superseded" { return "Duplicate or superseded project omitted from the public feed." }
        "placeholder" { return "Placeholder project omitted from the public feed." }
        "not-visitor-facing" { return "Project omitted because it is not visitor-facing." }
        default { return "Project omitted from the public feed." }
    }
}

function New-SuppressedProjectExportRow {
    param(
        [object]$Entry,
        [int]$SuppressedIndex
    )

    $reasonCode = Get-SuppressionReasonCode -Reason ([string]$Entry.suppressionReason)
    $visibilityClass = if ($reasonCode -eq "private-or-sensitive") {
        "private-or-sensitive"
    } else {
        "suppressed"
    }

    return [ordered]@{
        suppressedId = "suppressed-{0:D3}" -f $SuppressedIndex
        suppressed = $true
        category = [string]$Entry.category
        reasonCode = $reasonCode
        publicReason = Get-PublicSuppressionReason -ReasonCode $reasonCode
        visibilityClass = $visibilityClass
    }
}

function Get-RepoFileSha256 {
    param([string]$RelativePath)

    $fullPath = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $null
    }

    $content = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
    $normalizedContent = $content -replace "`r`n", "`n" -replace "`r", "`n"
    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedContent)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($contentBytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha256.Dispose()
    }
}

function Get-GitHeadCommit {
    $head = & git -C $RepoRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $commit = (($head | Out-String).Trim()).ToLowerInvariant()
    if ($commit -notmatch '^[a-f0-9]{40}$') {
        return $null
    }

    return $commit
}

function New-ProjectsProvenance {
    param([object[]]$Repos)

    return [ordered]@{
        version = 1
        feedSchemaVersion = $ProjectsFeedSchemaVersion
        sourceRepository = "$Owner/$Owner"
        sourceCommit = Get-GitHeadCommit
        catalogSha256 = Get-RepoFileSha256 -RelativePath "data/profile-catalog.json"
        generatorSha256 = Get-RepoFileSha256 -RelativePath "scripts/sync-profile.ps1"
        projectSchemaSha256 = Get-RepoFileSha256 -RelativePath "schemas/profile-projects.v1.json"
        metadataSnapshotAt = $script:MetadataSnapshotAt
        metadataProvider = [string]$script:RepositoryMetadataProvider
        repoEnumeration = [ordered]@{
            requestedLimit = [int]$script:RepositoryEnumerationRequestedLimit
            returnedCount = [int]@($Repos | Where-Object { $null -ne $_ }).Count
            truncated = [bool]$script:RepositoryEnumerationTruncated
        }
    }
}

function New-ProjectsExportJson {
    <#
    .SYNOPSIS
    Builds the public projects.json feed for downstream portfolio consumers.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER Repos
    Repository metadata used to populate public-safe project feed fields.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries | Sort-Object category, @{ Expression = { [int]$_.order } }, repo)
    $projects = New-Object System.Collections.Generic.List[object]
    $suppressed = New-Object System.Collections.Generic.List[object]
    $suppressedIndex = 0

    foreach ($entry in $entries) {
        $meta = Get-RepoMeta $entry $repoLookup
        $repoUrl = Get-RepoUrl $entry
        $downloadUrl = $null
        if ($meta -and $meta.latestRelease -and (([string]$entry.downloadKind).ToLowerInvariant() -ne "repo")) {
            $downloadUrl = Get-ReleaseUrl $entry
        }
        $primaryAction = Get-PrimaryAction $entry $meta $entry.category
        $topics = @()
        if ($meta -and $meta.repositoryTopics) {
            $topics = @($meta.repositoryTopics | ForEach-Object { $_.name } | Sort-Object)
        }
        $isSuppressed = -not [string]::IsNullOrWhiteSpace([string]$entry.suppressionReason)
        $releaseAssetKinds = @()
        if ($meta -and $meta.latestRelease) {
            $releaseAssetKinds = @(Get-ReleaseAssetKindsFromMeta -Meta $meta)
        }
        $releaseAssetNames = @()
        if (-not $isSuppressed -and $meta -and $meta.latestRelease) {
            $releaseAssetNames = @(Get-ReleaseAssetNamesFromMeta -Meta $meta)
        }
        $licenseMetadata = Get-LicenseMetadata -Meta $meta
        $releaseAssetInspected = [bool](Test-ReleaseAssetMetadataInspected -Meta $meta)
        $releaseDigests = if ($meta -and $meta.latestRelease) { $d = Get-MemberValue -Object $meta.latestRelease -Name "releaseAssetDigests"; if ($d -is [hashtable]) { $d } else { @{} } } else { @{} }
        $releaseTrust = New-ReleaseTrust `
            -AssetKinds $releaseAssetKinds `
            -AssetNames $releaseAssetNames `
            -HasRelease ([bool]($meta -and $meta.latestRelease)) `
            -AssetInspected $releaseAssetInspected `
            -Immutable $(if ($meta -and $meta.latestRelease) { Get-MemberValue -Object $meta.latestRelease -Name "immutable" } else { $null }) `
            -AssetDigests $releaseDigests
        $language = if (-not [string]::IsNullOrWhiteSpace([string]$entry.language)) {
            [string]$entry.language
        } elseif ($meta -and $meta.primaryLanguage -and $meta.primaryLanguage.name) {
            [string]$meta.primaryLanguage.name
        } else {
            $null
        }

        $row = [ordered]@{
            repo = [string]$entry.repo
            title = [string]$entry.title
            category = [string]$entry.category
            includeInReadme = [bool]$entry.includeInReadme
            includeInPortfolio = [bool]$entry.includeInPortfolio
            suppressed = $isSuppressed
            suppressionReason = if ([string]::IsNullOrWhiteSpace([string]$entry.suppressionReason)) { $null } else { [string]$entry.suppressionReason }
            description = Get-Description $entry $meta
            forkOf = if ([string]::IsNullOrWhiteSpace([string]$entry.forkOf)) { $null } else { [string]$entry.forkOf }
            forkOfUrl = Get-UpstreamUrl -ForkOf ([string]$entry.forkOf)
            upstreamLicense = if ([string]::IsNullOrWhiteSpace([string]$entry.upstreamLicense)) { $null } else { [string]$entry.upstreamLicense }
            licenseKey = $licenseMetadata["licenseKey"]
            licenseName = $licenseMetadata["licenseName"]
            licenseSpdxId = $licenseMetadata["licenseSpdxId"]
            repoUrl = $repoUrl
            liveUrl = if ([string]::IsNullOrWhiteSpace([string]$entry.liveUrl)) { $null } else { [string]$entry.liveUrl }
            installUrl = if ([string]::IsNullOrWhiteSpace([string]$entry.userscriptUrl)) { $null } else { [string]$entry.userscriptUrl }
            downloadUrl = $downloadUrl
            downloadKind = if ([string]::IsNullOrWhiteSpace([string]$entry.downloadKind)) { $null } else { [string]$entry.downloadKind }
            primaryAction = [ordered]@{
                kind = [string]$primaryAction["kind"]
                label = [string]$primaryAction["label"]
                url = [string]$primaryAction["url"]
            }
            searchMetadata = New-ProjectSearchMetadata -Entry $entry -PrimaryAction $primaryAction -Language $language
            hasDownload = [bool]($primaryAction["kind"] -eq "release")
            hasLiveDemo = [bool]($primaryAction["kind"] -eq "live")
            hasDirectInstall = [bool]($primaryAction["kind"] -eq "install")
            branch = Get-Branch $entry $meta
            entrypoint = if ([string]::IsNullOrWhiteSpace([string]$entry.entrypoint)) { $null } else { [string]$entry.entrypoint }
            installKind = if ([string]::IsNullOrWhiteSpace([string]$entry.installKind)) { $null } else { [string]$entry.installKind }
            language = $language
            stars = if ($meta) { [int]$meta.stargazerCount } else { $null }
            latestReleaseTag = if ($meta -and $meta.latestRelease) { [string]$meta.latestRelease.tagName } else { $null }
            latestReleaseUrl = if ($meta -and $meta.latestRelease) { [string]$meta.latestRelease.url } else { $null }
            releaseAssetKinds = @($releaseAssetKinds)
            releaseAssetNames = @($releaseAssetNames)
            releaseAssetInspected = $releaseAssetInspected
            releaseTrust = $releaseTrust
            pushedAt = if ($meta -and $meta.pushedAt) { ConvertTo-IsoText $meta.pushedAt } else { $null }
            topics = @($topics)
            featured = [bool]$entry.featured
            featuredRank = if ($entry.featuredRank) { [int]$entry.featuredRank } else { $null }
            currentlyBuilding = [bool]$entry.currentlyBuilding
            notes = if ([string]::IsNullOrWhiteSpace([string]$entry.notes)) { $null } else { [string]$entry.notes }
        }

        if ($row.suppressed) {
            $suppressedIndex++
            $suppressed.Add((New-SuppressedProjectExportRow -Entry $entry -SuppressedIndex $suppressedIndex))
        } elseif ($row.includeInPortfolio) {
            $projects.Add($row)
        }
    }

    $payload = [ordered]@{
        schema = $ProjectsSchemaUrl
        generatedAt = ConvertTo-IsoText $Catalog.generatedAt
        source = "SysAdminDoc/SysAdminDoc data/profile-catalog.json"
        provenance = New-ProjectsProvenance -Repos $Repos
        publicRepoCount = @($Repos | Where-Object { $null -ne $_ }).Count
        projectCount = $projects.Count
        suppressedCount = $suppressed.Count
        projects = $projects.ToArray()
        suppressed = $suppressed.ToArray()
    }

    return ($payload | ConvertTo-Json -Depth 20)
}

function New-CatalogFeedAccountingRow {
    param(
        [object]$Entry,
        [int]$CatalogIndex,
        [string]$ExportStatus,
        [string]$ReasonCode,
        [string]$PublicReason
    )

    return [ordered]@{
        catalogId = "catalog-{0:D3}" -f $CatalogIndex
        category = [string]$Entry.category
        includeInReadme = [bool]$Entry.includeInReadme
        includeInPortfolio = [bool]$Entry.includeInPortfolio
        exportStatus = $ExportStatus
        reasonCode = if ([string]::IsNullOrWhiteSpace($ReasonCode)) { $null } else { $ReasonCode }
        publicReason = if ([string]::IsNullOrWhiteSpace($PublicReason)) { $null } else { $PublicReason }
    }
}

function New-CatalogFeedAccountingMismatch {
    param(
        [string]$Field,
        [int]$Expected,
        [int]$Actual,
        [string]$Message
    )

    return [ordered]@{
        field = $Field
        expected = $Expected
        actual = $Actual
        message = $Message
    }
}

function Test-CatalogFeedAccounting {
    param(
        [hashtable]$Catalog,
        [string]$ProjectsJson
    )

    $entries = @($Catalog.entries)
    $payload = $null
    try {
        $payload = $ProjectsJson | ConvertFrom-Json
    } catch {
        $payload = $null
    }

    $feedProjectCount = if ($payload) { @((Get-MemberValue -Object $payload -Name "projects")).Count } else { 0 }
    $feedSuppressedCount = if ($payload) { @((Get-MemberValue -Object $payload -Name "suppressed")).Count } else { 0 }
    $visitorFacingEntries = @($entries | Where-Object {
            $_.includeInPortfolio -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
        })
    $suppressedEntries = @($entries | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
        })
    $unaccountedRows = New-Object System.Collections.Generic.List[object]
    $catalogIndex = 0
    foreach ($entry in $entries) {
        $catalogIndex++
        $suppressionReason = [string]$entry.suppressionReason
        if ($entry.includeInPortfolio -eq $false -and [string]::IsNullOrWhiteSpace($suppressionReason)) {
            $unaccountedRows.Add((New-CatalogFeedAccountingRow `
                        -Entry $entry `
                        -CatalogIndex $catalogIndex `
                        -ExportStatus "unaccounted" `
                        -ReasonCode "missing-accounting-reason" `
                        -PublicReason "Catalog row is excluded from the public feed without a public-safe suppression reason."))
        }
    }

    $mismatches = New-Object System.Collections.Generic.List[object]
    if ($feedProjectCount -ne $visitorFacingEntries.Count) {
        $mismatches.Add((New-CatalogFeedAccountingMismatch `
                    -Field "projectCount" `
                    -Expected $visitorFacingEntries.Count `
                    -Actual $feedProjectCount `
                    -Message "Generated feed project count does not match visitor-facing catalog rows."))
    }
    if ($feedSuppressedCount -ne $suppressedEntries.Count) {
        $mismatches.Add((New-CatalogFeedAccountingMismatch `
                    -Field "suppressedCount" `
                    -Expected $suppressedEntries.Count `
                    -Actual $feedSuppressedCount `
                    -Message "Generated feed suppressed count does not match catalog rows with suppression reasons."))
    }

    $unaccountedArray = @($unaccountedRows.ToArray())
    $mismatchArray = @($mismatches.ToArray())
    $fatalCount = $unaccountedArray.Count + $mismatchArray.Count

    return [ordered]@{
        passed = [bool]($fatalCount -eq 0)
        catalogEntryCount = $entries.Count
        visitorFacingCatalogCount = $visitorFacingEntries.Count
        suppressedCatalogCount = $suppressedEntries.Count
        exportedProjectCount = $feedProjectCount
        exportedSuppressedCount = $feedSuppressedCount
        projectCountMatches = [bool]($feedProjectCount -eq $visitorFacingEntries.Count)
        suppressedCountMatches = [bool]($feedSuppressedCount -eq $suppressedEntries.Count)
        unaccountedRowCount = $unaccountedArray.Count
        mismatchCount = $mismatchArray.Count
        fatalCount = $fatalCount
        unaccountedRows = $unaccountedArray
        mismatches = $mismatchArray
        note = "Public-safe accounting confirms each catalog row is exported as a project, exported as a redacted suppression, or flagged without exposing omitted repo names."
    }
}

function Test-PortfolioFeedCompatibility {
    param([string]$ProjectsJson)

    $payload = $null
    try {
        $payload = $ProjectsJson | ConvertFrom-Json
    } catch {
        $payload = $null
    }

    $requiredProjectFields = @(
        "repo",
        "title",
        "category",
        "description",
        "repoUrl",
        "primaryAction.kind",
        "primaryAction.label",
        "primaryAction.url",
        "searchMetadata.type",
        "searchMetadata.labels",
        "searchMetadata.filters",
        "hasDownload",
        "hasLiveDemo",
        "hasDirectInstall",
        "releaseTrust.trustLevel",
        "topics",
        "featured",
        "currentlyBuilding"
    )
    $requiredPrimaryActionKinds = @("install", "live", "release", "repo")
    $suppressedDisallowedFields = @(
        "repo",
        "title",
        "description",
        "repoUrl",
        "liveUrl",
        "installUrl",
        "downloadUrl",
        "primaryAction",
        "searchMetadata",
        "releaseAssetKinds",
        "releaseAssetNames",
        "releaseTrust"
    )
    $missingProjectFields = New-Object System.Collections.Generic.List[object]
    $suppressedIdentifierLeaks = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]
    $primaryActionKindCounts = New-Object System.Collections.Generic.List[object]

    if ($null -eq $payload) {
        $errors.Add("projects.json could not be parsed for portfolio compatibility.")
        return [ordered]@{
            status = "unavailable"
            consumerContract = "sysadmindoc.github.io profile-feed importer"
            feedSourceUrl = "https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/projects.json"
            projectCount = 0
            suppressedCount = 0
            topLevelProjectCount = $null
            topLevelSuppressedCount = $null
            projectCountMatchesTopLevel = $false
            suppressedCountMatchesTopLevel = $false
            projectRequiredFields = $requiredProjectFields
            missingProjectFieldCount = 0
            missingProjectFields = @()
            suppressedDisallowedFields = $suppressedDisallowedFields
            suppressedIdentifierLeakCount = 0
            suppressedIdentifierLeaks = @()
            duplicateVisibleRepoCount = 0
            duplicateVisibleRepos = @()
            redactedSuppressedRowsCompatible = $false
            provenanceAvailable = $false
            releaseTrustAvailable = $false
            searchMetadataAvailable = $false
            searchFiltersAvailable = $false
            primaryActionKindCounts = @()
            warningCount = $warnings.Count
            warnings = @($warnings.ToArray())
            fatalCount = $errors.Count
            errors = @($errors.ToArray())
            note = "Compatibility snapshot for the downstream portfolio feed importer; normal consumers should use payload.projects and ignore unknown additive fields."
        }
    }

    $projects = @((Get-MemberValue -Object $payload -Name "projects"))
    $suppressed = @((Get-MemberValue -Object $payload -Name "suppressed"))
    $topLevelProjectCount = [int](Get-MemberValue -Object $payload -Name "projectCount")
    $topLevelSuppressedCount = [int](Get-MemberValue -Object $payload -Name "suppressedCount")
    $projectCountMatchesTopLevel = [bool]($projects.Count -eq $topLevelProjectCount)
    $suppressedCountMatchesTopLevel = [bool]($suppressed.Count -eq $topLevelSuppressedCount)
    if (-not $projectCountMatchesTopLevel) {
        $errors.Add("Feed projectCount does not match projects array length.")
    }
    if (-not $suppressedCountMatchesTopLevel) {
        $errors.Add("Feed suppressedCount does not match suppressed array length.")
    }
    if ($projects.Count -eq 0) {
        $errors.Add("Portfolio feed has no visible projects.")
    }

    $duplicateVisibleRepos = New-Object System.Collections.Generic.List[string]
    $seenRepos = @{}
    $projectIndex = 0
    foreach ($project in $projects) {
        $projectIndex++
        $repo = [string](Get-MemberValue -Object $project -Name "repo")
        $repoLabel = if ([string]::IsNullOrWhiteSpace($repo)) { "project-$projectIndex" } else { $repo }
        if (-not [string]::IsNullOrWhiteSpace($repo)) {
            $repoKey = $repo.ToLowerInvariant()
            if ($seenRepos.ContainsKey($repoKey)) {
                $duplicateVisibleRepos.Add($repo)
            } else {
                $seenRepos[$repoKey] = $true
            }
        }
        foreach ($field in $requiredProjectFields) {
            if ($field -eq "topics") {
                $missing = -not (Test-MemberExists -Object $project -Name $field)
            } elseif ($field -in @("searchMetadata.labels", "searchMetadata.filters")) {
                $value = Get-NestedMemberValue -Object $project -Path $field
                $missing = ($null -eq $value -or @($value).Count -eq 0)
            } else {
                $value = if ($field.Contains(".")) {
                    Get-NestedMemberValue -Object $project -Path $field
                } else {
                    Get-MemberValue -Object $project -Name $field
                }
                $missing = $null -eq $value
                if (-not $missing -and $value -is [string]) {
                    $missing = [string]::IsNullOrWhiteSpace($value)
                }
            }
            if ($missing) {
                $missingProjectFields.Add([ordered]@{
                    repo = $repoLabel
                    field = $field
                })
            }
        }
    }

    $suppressedIndex = 0
    foreach ($row in $suppressed) {
        $suppressedIndex++
        $suppressedId = [string](Get-MemberValue -Object $row -Name "suppressedId")
        if ([string]::IsNullOrWhiteSpace($suppressedId)) {
            $suppressedId = "suppressed-$suppressedIndex"
        }
        foreach ($field in $suppressedDisallowedFields) {
            if ($null -ne (Get-MemberValue -Object $row -Name $field)) {
                $suppressedIdentifierLeaks.Add([ordered]@{
                    suppressedId = $suppressedId
                    field = $field
                })
            }
        }
    }

    $actionKinds = @($projects | ForEach-Object {
            $primaryAction = Get-MemberValue -Object $_ -Name "primaryAction"
            [string](Get-MemberValue -Object $primaryAction -Name "kind")
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    foreach ($kind in $actionKinds) {
        $primaryActionKindCounts.Add([ordered]@{
            kind = $kind
            count = [int]@($projects | Where-Object {
                    $primaryAction = Get-MemberValue -Object $_ -Name "primaryAction"
                    [string](Get-MemberValue -Object $primaryAction -Name "kind") -eq $kind
                }).Count
        })
    }
    $missingPrimaryActionKinds = @($requiredPrimaryActionKinds | Where-Object { $actionKinds -notcontains $_ })
    if ($missingPrimaryActionKinds.Count -gt 0) {
        $errors.Add("Portfolio feed lacks consumer-required primary action kind(s): $($missingPrimaryActionKinds -join ', ').")
    }

    $missingFieldsArray = @($missingProjectFields.ToArray())
    $suppressedLeaksArray = @($suppressedIdentifierLeaks.ToArray())
    if ($missingFieldsArray.Count -gt 0) {
        $errors.Add("Portfolio project rows are missing downstream-required fields.")
    }
    if ($suppressedLeaksArray.Count -gt 0) {
        $errors.Add("Redacted suppressed feed rows expose project-identifying fields.")
    }
    $duplicateVisibleRepoArray = @($duplicateVisibleRepos.ToArray())
    if ($duplicateVisibleRepoArray.Count -gt 0) {
        $errors.Add("Duplicate visible repo names in the portfolio feed: $($duplicateVisibleRepoArray -join ', ').")
    }

    $provenance = Get-MemberValue -Object $payload -Name "provenance"
    if ($null -eq $provenance) {
        $warnings.Add("Feed provenance is not available to downstream consumers.")
    }
    $releaseTrustAvailable = @($projects | Where-Object { $null -ne (Get-MemberValue -Object $_ -Name "releaseTrust") }).Count -eq $projects.Count
    if (-not $releaseTrustAvailable) {
        $warnings.Add("Not every visible project row exposes releaseTrust metadata.")
    }
    $searchMetadataAvailable = @($projects | Where-Object { $null -ne (Get-MemberValue -Object $_ -Name "searchMetadata") }).Count -eq $projects.Count
    if (-not $searchMetadataAvailable) {
        $warnings.Add("Not every visible project row exposes searchMetadata.")
    }
    $searchFiltersAvailable = @($projects | Where-Object {
            $metadata = Get-MemberValue -Object $_ -Name "searchMetadata"
            $null -ne $metadata -and @((Get-MemberValue -Object $metadata -Name "filters")).Count -gt 0
        }).Count -eq $projects.Count
    if (-not $searchFiltersAvailable) {
        $warnings.Add("Not every visible project row exposes search filters.")
    }

    $fatalCount = $errors.Count
    return [ordered]@{
        status = if ($fatalCount -eq 0) { "compatible" } else { "incompatible" }
        consumerContract = "sysadmindoc.github.io profile-feed importer"
        feedSourceUrl = "https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/projects.json"
        projectCount = [int]$projects.Count
        suppressedCount = [int]$suppressed.Count
        topLevelProjectCount = $topLevelProjectCount
        topLevelSuppressedCount = $topLevelSuppressedCount
        projectCountMatchesTopLevel = $projectCountMatchesTopLevel
        suppressedCountMatchesTopLevel = $suppressedCountMatchesTopLevel
        projectRequiredFields = $requiredProjectFields
        missingProjectFieldCount = $missingFieldsArray.Count
        missingProjectFields = $missingFieldsArray
        suppressedDisallowedFields = $suppressedDisallowedFields
        suppressedIdentifierLeakCount = $suppressedLeaksArray.Count
        suppressedIdentifierLeaks = $suppressedLeaksArray
        duplicateVisibleRepoCount = [int]$duplicateVisibleRepoArray.Count
        duplicateVisibleRepos = @($duplicateVisibleRepoArray)
        redactedSuppressedRowsCompatible = [bool]($suppressedLeaksArray.Count -eq 0)
        provenanceAvailable = [bool]($null -ne $provenance)
        releaseTrustAvailable = $releaseTrustAvailable
        searchMetadataAvailable = $searchMetadataAvailable
        searchFiltersAvailable = $searchFiltersAvailable
        primaryActionKindCounts = @($primaryActionKindCounts.ToArray())
        warningCount = $warnings.Count
        warnings = @($warnings.ToArray())
        fatalCount = $fatalCount
        errors = @($errors.ToArray())
        note = "Compatibility snapshot for the downstream portfolio feed importer; normal consumers should use payload.projects and ignore unknown additive fields."
    }
}

function New-CatalogFromReadme {
    param([object[]]$Repos)

    $repoLookup = ConvertTo-Lookup $Repos
    $readmeReadPath = if ([System.IO.Path]::IsPathRooted($ReadmePath)) { $ReadmePath } else { Join-Path $RepoRoot $ReadmePath }
    $readme = Get-Content -LiteralPath $readmeReadPath -Raw
    $lines = $readme -split "\r?\n"
    $entries = [ordered]@{}
    $category = $null
    $order = @{}
    $lastRepo = $null
    $inCode = $false
    $codeLines = New-Object System.Collections.Generic.List[string]

    $featuredRank = 1
    foreach ($line in $lines) {
        if ($line -match '^\| \[\*\*(?<title>.+?)\*\*\]\(https://github\.com/SysAdminDoc/(?<repo>[^)/]+)\) \| &#11088;(?<stars>\d+) \| (?<description>.*?) \|$') {
            $repo = $Matches.repo
            if (-not $entries.Contains($repo)) {
                $entries[$repo] = New-CatalogEntry -Repo $repo -Category "misc" -Description $Matches.description -Order 9999
            }
            $entries[$repo].featured = $true
            $entries[$repo].featuredRank = $featuredRank
            $featuredRank++
        } elseif ($line -match '^\| \[\*\*(?<title>.+?)\*\*\]\(https://github\.com/SysAdminDoc/(?<repo>[^)/]+)\) \| (?<category>.*?) \| &#11088;(?<stars>\d+) \| (?<description>.*?) \| (?<action>.*?) \|$') {
            $repo = $Matches.repo
            if (-not $entries.Contains($repo)) {
                $entries[$repo] = New-CatalogEntry -Repo $repo -Category "misc" -Description $Matches.description -Order 9999
            }
            $entries[$repo].featured = $true
            $entries[$repo].featuredRank = $featuredRank
            $featuredRank++
        }
    }

    foreach ($line in $lines) {
        $slug = ConvertTo-CategorySlug $line
        if ($slug) {
            $category = $slug
            if (-not $order.Contains($category)) {
                $order[$category] = 0
            }
            continue
        }

        if (-not $category) {
            continue
        }

        if ($inCode) {
            if ($line -eq '```') {
                $inCode = $false
                if ($lastRepo -and $entries.Contains($lastRepo)) {
                    $code = ($codeLines -join " ")
                    if ($code -match 'git clone -q --depth 1 -b (?<branch>\S+)') {
                        $entries[$lastRepo].branch = $Matches.branch
                    }
                    if ($code -match '(?<runner>python|&)\s+"\$d\\(?<entry>[^"]+)"') {
                        $entries[$lastRepo].entrypoint = $Matches.entry
                        $entries[$lastRepo].installKind = if ($Matches.runner -eq "&") { "powershell" } else { "python" }
                    }
                }
                $codeLines.Clear()
                continue
            }
            $codeLines.Add($line)
            continue
        }

        if ($line -eq '```powershell') {
            $inCode = $true
            continue
        }

        if ($line -match '^\[\*\*(?<title>.+?)\*\*\]\(https://github\.com/SysAdminDoc/(?<repo>[^)/]+)\)(?: &#11088;(?<stars>\d+))? (?:--|—) (?<rest>.+)$') {
            $repo = $Matches.repo
            $rest = $Matches.rest
            $description = $rest -replace '\s*&nbsp;\[.*$', ''
            $order[$category]++
            if (-not $entries.Contains($repo)) {
                $entries[$repo] = New-CatalogEntry -Repo $repo -Category $category -Description $description -Order $order[$category]
            }
            $entries[$repo].title = $Matches.title
            $entries[$repo].category = $category
            $entries[$repo].order = $order[$category]
            $entries[$repo].descriptionOverride = $description
            if ($rest -match 'releases/latest') {
                $entries[$repo].downloadKind = "download"
            }
            $lastRepo = $repo
            continue
        }

        if ($line -match '^\| \[\*\*(?<title>.+?)\*\*\]\(https://github\.com/SysAdminDoc/(?<repo>[^)/]+)\)(?: &#11088;(?<stars>\d+))? \| (?<description>.*?) \| (?<tail>.*) \|$') {
            $repo = $Matches.repo
            $tail = $Matches.tail
            $order[$category]++
            if (-not $entries.Contains($repo)) {
                $entries[$repo] = New-CatalogEntry -Repo $repo -Category $category -Description $Matches.description -Order $order[$category]
            }
            $entries[$repo].title = $Matches.title
            $entries[$repo].category = $category
            $entries[$repo].order = $order[$category]
            $entries[$repo].descriptionOverride = $Matches.description

            if ($category -eq "web" -and $tail -match '\[Launch\]\((?<url>[^)]+)\)') {
                $entries[$repo].liveUrl = $Matches.url
            } elseif ($tail -match '\[Install\]\((?<url>[^)]+)\)') {
                $entries[$repo].userscriptUrl = $Matches.url
                $entries[$repo].downloadKind = "userscript"
            } elseif ($tail -match 'releases/latest') {
                if ($tail -match 'CRX/XPI') { $entries[$repo].downloadKind = "crx-xpi" }
                elseif ($tail -match 'CRX') { $entries[$repo].downloadKind = "crx" }
                elseif ($tail -match 'XPI') { $entries[$repo].downloadKind = "xpi" }
                elseif ($tail -match 'APK') { $entries[$repo].downloadKind = "apk" }
                elseif ($tail -match 'EXE') { $entries[$repo].downloadKind = "exe" }
                elseif ($tail -match 'ZIP') { $entries[$repo].downloadKind = "zip" }
                else { $entries[$repo].downloadKind = "download" }
            } elseif ($tail -match '\[Repo\]') {
                $entries[$repo].downloadKind = "repo"
            }

            if ($category -eq "desktop") {
                $cells = $tail -split '\s\|\s'
                if ($cells.Count -ge 2) {
                    $entries[$repo].language = $cells[0]
                }
            }
            continue
        }

        if ($line -match '^\| \[\*\*(?<title>.+?)\*\*\]\(https://github\.com/SysAdminDoc/(?<repo>[^)/]+)\)(?: &#11088;(?<stars>\d+))? \| (?<description>.*?) \|$') {
            $repo = $Matches.repo
            $order[$category]++
            if (-not $entries.Contains($repo)) {
                $entries[$repo] = New-CatalogEntry -Repo $repo -Category $category -Description $Matches.description -Order $order[$category]
            }
            $entries[$repo].title = $Matches.title
            $entries[$repo].category = $category
            $entries[$repo].order = $order[$category]
            $entries[$repo].descriptionOverride = $Matches.description
            continue
        }
    }

    $buildingMatches = [regex]::Matches($readme, '\| \*\*(?<repo>[^*]+)\*\* \| (?<text>.*?) \|')
    foreach ($match in $buildingMatches) {
        $repo = $match.Groups["repo"].Value
        if ($entries.Contains($repo)) {
            $entries[$repo].currentlyBuilding = $true
            $entries[$repo].currentlyBuildingText = $match.Groups["text"].Value
        }
    }

    foreach ($entry in $entries.Values) {
        $meta = Get-RepoMeta $entry $repoLookup
        if ($meta -and $meta.defaultBranchRef -and $meta.defaultBranchRef.name -and -not $entry.branch) {
            $entry.branch = [string]$meta.defaultBranchRef.name
        }
        if ($meta -and $meta.primaryLanguage -and $meta.primaryLanguage.name -and -not $entry.language) {
            $entry.language = [string]$meta.primaryLanguage.name
        }
    }

    return [ordered]@{
        schema = $CatalogSchemaUrl
        generatedAt = (Get-Date).ToString("o")
        entries = @($entries.Values)
    }
}

function Test-SeedCatalogGuard {
    param(
        [bool]$SeedRequested,
        [bool]$ForceRequested
    )

    return [ordered]@{
        allowed = [bool](-not $SeedRequested -or $ForceRequested)
        message = if ($SeedRequested) { $SeedCatalogGuardMessage } else { $null }
    }
}

function Test-ReadmeExperience {
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [string]$ExpectedReadme
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries | Where-Object {
        $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
    })
    $featured = @($entries | Where-Object { $_.featured -eq $true })
    $building = @($entries | Where-Object { $_.currentlyBuilding -eq $true })
    $missingPrimaryAction = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $entries) {
        $action = Get-PrimaryAction $entry (Get-RepoMeta $entry $repoLookup) $entry.category
        if ([string]::IsNullOrWhiteSpace([string]$action["label"]) -or [string]::IsNullOrWhiteSpace([string]$action["url"])) {
            $missingPrimaryAction.Add([string]$entry.repo)
        }
    }

    $missingAnchors = New-Object System.Collections.Generic.List[string]
    foreach ($definition in $CategoryDefinitions) {
        # Categories with no visible entries render no section, so only require an anchor
        # for categories that actually have at least one entry.
        $categoryEntryCount = @($entries | Where-Object { $_.category -eq $definition.Slug }).Count
        if ($categoryEntryCount -eq 0) {
            continue
        }
        $anchor = '<a id="{0}"></a>' -f (Get-CategoryAnchor $definition.Slug)
        if (-not $ExpectedReadme.Contains($anchor)) {
            $missingAnchors.Add($definition.Slug)
        }
    }

    $unlabeledDownloads = [regex]::Matches($ExpectedReadme, '<kbd>&#11015;\s*</kbd>').Count
    $hasStartHere = $ExpectedReadme.Contains("### Start Here")
    $hasSnapshot = $ExpectedReadme.Contains("### Catalog Snapshot")
    $hasGeneratedNotice = $ExpectedReadme.Contains($GeneratedCatalogNotice)
    $hasSetupInspectPath = $ExpectedReadme.Contains("Inspect before installing") -and
        $ExpectedReadme.Contains("-CheckOnly") -and
        $ExpectedReadme.Contains("SysAdminDoc-setup.ps1") -and
        $ExpectedReadme.Contains("SysAdminDoc-setup-*.log")
    $hasThemeAwareChrome = $ExpectedReadme.Contains("<picture>") -and
        $ExpectedReadme.Contains('(prefers-color-scheme: dark)') -and
        $ExpectedReadme.Contains('(prefers-color-scheme: light)') -and
        $ExpectedReadme.Contains("theme=light") -and
        $ExpectedReadme.Contains("assets/profile/stats-light.svg") -and
        $ExpectedReadme.Contains("assets/profile/languages-light.svg") -and
        $ExpectedReadme.Contains("assets/profile/activity-light.svg") -and
        $ExpectedReadme.Contains("assets/profile/contributions-light.svg")
    $thirdPartyMetricHostPattern = 'komarev\.com|github-readme-stats|streak-stats|github-readme-activity-graph'
    $thirdPartyMetricHostCount = [regex]::Matches($ExpectedReadme, $thirdPartyMetricHostPattern).Count
    $thirdPartyBadgeHostPattern = 'img\.shields\.io/github/(?:followers|stars)'
    $thirdPartyBadgeHostCount = [regex]::Matches($ExpectedReadme, $thirdPartyBadgeHostPattern).Count
    $thirdPartyRenderHostPattern = 'https://(?<host>(?:capsule-render\.vercel\.app|readme-typing-svg\.demolab\.com|skillicons\.dev))'
    $thirdPartyRenderHosts = @(
        [regex]::Matches($ExpectedReadme, $thirdPartyRenderHostPattern) |
            ForEach-Object { $_.Groups['host'].Value } |
            Sort-Object -Unique
    )
    $motionPattern = '(?i)(?:[?&]animation=|[?&]repeat=true|readme-typing-svg(?:\.demolab\.com)?)'
    $motionPatternCount = [regex]::Matches($ExpectedReadme, $motionPattern).Count
    $motionSafeChrome = $motionPatternCount -eq 0
    $profileStatsChromeCount = [regex]::Matches($ExpectedReadme, '<a href="https://skillicons\.dev">').Count
    $hasPlainTextTagline = $ExpectedReadme.Contains("Healthcare IT engineer and DICOM/PACS specialist") -and
        $ExpectedReadme.Contains("16+ years in IT operations")
    $genericAltPattern = 'alt="(Header|Typing SVG|Profile Views|Followers|Stars|Tech Stack|GitHub Stats|Top Languages|GitHub Streak|Activity Graph|Footer)"'
    $genericAltCount = [regex]::Matches($ExpectedReadme, $genericAltPattern).Count
    $hasMeaningfulAltText = $genericAltCount -eq 0 -and
        $ExpectedReadme.Contains('alt="SysAdminDoc - Healthcare IT Engineer, DICOM/PACS Specialist, Product Builder"') -and
        $ExpectedReadme.Contains('alt="PowerShell, Python, JavaScript, Kotlin, C#, C++, HTML, CSS, .NET, Qt, Android Studio, Git, and GitHub"')
    # Per GitHub accessibility guidance, every <img> needs descriptive alt text.
    # Warning-only completeness check across all rendered <img> tags.
    $genericAltValuePattern = '(?i)^(header|typing svg|profile views|followers|stars|tech stack|github stats|top languages|github streak|activity graph|footer|image|img|logo|icon|screenshot|banner)$'
    $imageTags = [regex]::Matches($ExpectedReadme, '(?is)<img\b[^>]*>')
    $imageTagCount = $imageTags.Count
    $imageAltTextIssueCount = 0
    foreach ($imageTag in $imageTags) {
        $altMatch = [regex]::Match($imageTag.Value, '(?is)\balt\s*=\s*(?:"(?<alt>[^"]*)"|''(?<alt>[^'']*)'')')
        if (-not $altMatch.Success) {
            $imageAltTextIssueCount++
            continue
        }
        $altText = $altMatch.Groups['alt'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($altText) -or $altText -match $genericAltValuePattern) {
            $imageAltTextIssueCount++
        }
    }
    $imageAltTextComplete = $imageAltTextIssueCount -eq 0
    $hasFeaturedActionColumn = $ExpectedReadme.Contains("| Project | Category | Stars | Description | Action |")
    $hasFeaturedActionList = [regex]::IsMatch($ExpectedReadme, '(?m)^- \[\*\*.+?\*\*\]\(https://github\.com/SysAdminDoc/.+?\) -- .+?<br/>.+?<br/>(?:Action: )?\[')
    $hasFeaturedPrimaryActions = $hasFeaturedActionColumn -or $hasFeaturedActionList
    $hasMinimalProfileHeader = $ExpectedReadme.TrimStart().StartsWith('<p align="center"><b>Broadcast IT, Healthcare IT, and practical public tools.</b>', [StringComparison]::Ordinal) -and
        $ExpectedReadme.Contains('<a href="https://sysadmindoc.github.io/"><b>View my full portfolio') -and
        $ExpectedReadme.Contains('<a href="#powershell-system-utilities">PowerShell</a>') -and
        -not $ExpectedReadme.Contains('assets/profile/header-dark.svg') -and
        -not $ExpectedReadme.Contains('assets/profile/header-light.svg')
    $hasRichProfileHeader = $ExpectedReadme.Contains("### Professional Focus") -or
        $ExpectedReadme.Contains("Healthcare IT engineer and DICOM/PACS specialist") -or
        $ExpectedReadme.Contains("https://skillicons.dev") -or
        $profileStatsChromeCount -gt 0
    $hasCurrentlyBuildingActionColumn = ($building.Count -eq 0) -or
        (-not $ExpectedReadme.Contains("**Currently Building**")) -or
        $ExpectedReadme.Contains("| Project | Focus | Action |")
    $hasDiscoveryContract = ($hasStartHere -and -not $hasSnapshot -and $hasGeneratedNotice) -or
        ($hasMinimalProfileHeader -and -not $hasStartHere -and -not $hasSnapshot -and -not $hasGeneratedNotice)
    $hasProfileHeaderContract = ($hasRichProfileHeader -and $hasThemeAwareChrome -and $hasPlainTextTagline -and $hasMeaningfulAltText -and $profileStatsChromeCount -eq 1) -or
        ($hasMinimalProfileHeader -and -not $hasRichProfileHeader -and -not $hasPlainTextTagline -and $profileStatsChromeCount -eq 0)
    $passed = $hasDiscoveryContract -and $hasSetupInspectPath -and $hasCurrentlyBuildingActionColumn -and
        $hasProfileHeaderContract -and
        $motionSafeChrome -and
        $thirdPartyMetricHostCount -eq 0 -and $thirdPartyBadgeHostCount -eq 0 -and
        $missingAnchors.Count -eq 0 -and $missingPrimaryAction.Count -eq 0 -and $unlabeledDownloads -eq 0

    return [ordered]@{
        passed = [bool]$passed
        startHereSection = [bool]$hasStartHere
        catalogSnapshotSection = [bool]$hasSnapshot
        generatedCatalogNotice = [bool]$hasGeneratedNotice
        setupInspectPath = [bool]$hasSetupInspectPath
        themeAwareImageChrome = [bool]$hasThemeAwareChrome
        plainTextTagline = [bool]$hasPlainTextTagline
        meaningfulImageAltText = [bool]$hasMeaningfulAltText
        minimalProfileHeader = [bool]$hasMinimalProfileHeader
        richProfileHeader = [bool]$hasRichProfileHeader
        genericImageAltTextCount = $genericAltCount
        imageTagCount = [int]$imageTagCount
        imageAltTextIssueCount = [int]$imageAltTextIssueCount
        imageAltTextComplete = [bool]$imageAltTextComplete
        thirdPartyMetricHostCount = $thirdPartyMetricHostCount
        thirdPartyBadgeHostCount = $thirdPartyBadgeHostCount
        thirdPartyRenderHostCount = $thirdPartyRenderHosts.Count
        thirdPartyRenderHosts = $thirdPartyRenderHosts
        motionSafeChrome = [bool]$motionSafeChrome
        motionPatternCount = $motionPatternCount
        profileStatsChromeCount = $profileStatsChromeCount
        featuredRows = $featured.Count
        featuredActionColumn = [bool]$hasFeaturedActionColumn
        featuredActionList = [bool]$hasFeaturedActionList
        featuredPrimaryActions = [bool]$hasFeaturedPrimaryActions
        currentlyBuildingRows = $building.Count
        currentlyBuildingActionColumn = [bool]$hasCurrentlyBuildingActionColumn
        categoryAnchorCount = $CategoryDefinitions.Count - $missingAnchors.Count
        missingCategoryAnchors = $missingAnchors.ToArray()
        primaryActionCoverage = $entries.Count - $missingPrimaryAction.Count
        missingPrimaryActions = $missingPrimaryAction.ToArray()
        unlabeledDownloadButtons = $unlabeledDownloads
    }
}

function Test-ReadmeSizeBudget {
    param(
        [string]$ExpectedReadme,
        [int]$SoftLimitBytes = $ReadmeSoftLimitBytes
    )

    $byteCount = [System.Text.Encoding]::UTF8.GetByteCount($ExpectedReadme)
    $overSoftLimit = $byteCount -gt $SoftLimitBytes

    return [ordered]@{
        byteCount = $byteCount
        softLimitBytes = $SoftLimitBytes
        overSoftLimit = [bool]$overSoftLimit
        warning = if ($overSoftLimit) {
            "Generated README is $byteCount bytes, above the $SoftLimitBytes byte soft limit; consider collapsing low-traffic categories."
        } else {
            $null
        }
    }
}

function Test-ReadmeHeadingHierarchy {
    param(
        [string]$ExpectedReadme,
        # Profile READMEs render under the GitHub profile name (an implicit H1),
        # so opening at H2/H3 is allowed without being treated as a skipped level.
        [int]$ProfileContextMaxFirstLevel = 3
    )

    $sequence = New-Object System.Collections.Generic.List[int]
    $inFence = $false
    foreach ($line in ($ExpectedReadme -split "\r?\n")) {
        if ($line -match '^\s*(```|~~~)') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }
        $headingMatch = [regex]::Match($line, '^(?<hashes>#{1,6})\s+\S')
        if ($headingMatch.Success) {
            $sequence.Add($headingMatch.Groups['hashes'].Value.Length)
        }
    }

    $levels = @($sequence.ToArray())
    $firstLevel = if ($levels.Count -gt 0) { [int]$levels[0] } else { 0 }
    $profileContextAllowlistApplied = ($levels.Count -gt 0 -and $firstLevel -le $ProfileContextMaxFirstLevel)

    $skips = New-Object System.Collections.Generic.List[object]
    # Initial jump from the implied H1 to the first heading, only flagged when it
    # exceeds the profile-context allowance.
    if ($levels.Count -gt 0 -and -not $profileContextAllowlistApplied) {
        $skips.Add([ordered]@{ from = 1; to = $firstLevel; afterHeadingIndex = 0; context = "document-start" })
    }
    for ($i = 1; $i -lt $levels.Count; $i++) {
        if ($levels[$i] -gt ($levels[$i - 1] + 1)) {
            $skips.Add([ordered]@{ from = [int]$levels[$i - 1]; to = [int]$levels[$i]; afterHeadingIndex = $i; context = "descent" })
        }
    }

    $skipArray = @($skips.ToArray())
    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($skip in $skipArray) {
        $warnings.Add("Generated README heading level jumps from H$($skip.from) to H$($skip.to) ($($skip.context)); add the intermediate level or document the exception.")
    }

    return [ordered]@{
        status = if ($warnings.Count -eq 0) { "ok" } else { "warning" }
        headingCount = [int]$levels.Count
        firstLevel = [int]$firstLevel
        headingSequence = $levels
        profileContextMaxFirstLevel = [int]$ProfileContextMaxFirstLevel
        profileContextAllowlistApplied = [bool]$profileContextAllowlistApplied
        skippedLevelTransitions = $skipArray
        skippedLevelCount = [int]$skipArray.Count
        warnings = @($warnings.ToArray())
        warningCount = [int]$warnings.Count
    }
}

function New-ReadmePortfolioOnlyPreview {
    param(
        [object[]]$Entries,
        [object[]]$Candidates,
        [int]$CategorySoftLimit = $ReadmeCategorySoftLimit
    )

    $safeEntries = @($Entries)
    $safeCandidates = @($Candidates | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $_ -Name "repo"))
        } | Sort-Object @{ Expression = { [int](Get-MemberValue -Object $_ -Name "reviewRank") }; Ascending = $true })
    $candidateRepos = @($safeCandidates | ForEach-Object { [string](Get-MemberValue -Object $_ -Name "repo") })
    $candidateSet = @{}
    foreach ($repo in $candidateRepos) {
        $candidateSet[$repo.ToLowerInvariant()] = $true
    }

    $previewEntries = @($safeEntries | Where-Object {
            $repo = [string](Get-MemberValue -Object $_ -Name "repo")
            [string]::IsNullOrWhiteSpace($repo) -or -not $candidateSet.ContainsKey($repo.ToLowerInvariant())
        })
    $categoryRows = New-Object System.Collections.Generic.List[object]

    foreach ($definition in $CategoryDefinitions) {
        $slug = [string]$definition.Slug
        $currentCount = @($safeEntries | Where-Object { [string](Get-MemberValue -Object $_ -Name "category") -eq $slug }).Count
        $previewCount = @($previewEntries | Where-Object { [string](Get-MemberValue -Object $_ -Name "category") -eq $slug }).Count
        $categoryRows.Add([ordered]@{
                category = $slug
                displayName = Get-CategoryDisplayName -Slug $slug
                currentProjectCount = [int]$currentCount
                previewProjectCount = [int]$previewCount
                projectRowDelta = [int]($previewCount - $currentCount)
                currentOverSoftLimitBy = [int][Math]::Max(0, ($currentCount - $CategorySoftLimit))
                previewOverSoftLimitBy = [int][Math]::Max(0, ($previewCount - $CategorySoftLimit))
            })
    }

    $categoryRowsArray = @($categoryRows.ToArray())
    $largestPreviewCategory = @($categoryRowsArray |
        Sort-Object @{ Expression = { [int]$_.previewProjectCount }; Descending = $true }, category |
        Select-Object -First 1)
    $previewLargestCategory = $null
    $previewLargestCategoryCount = 0
    if ($largestPreviewCategory.Count -gt 0) {
        $previewLargestCategory = [string]$largestPreviewCategory[0].category
        $previewLargestCategoryCount = [int]$largestPreviewCategory[0].previewProjectCount
    }
    $largestCurrentCategory = @($categoryRowsArray |
        Sort-Object @{ Expression = { [int]$_.currentProjectCount }; Descending = $true }, category |
        Select-Object -First 1)
    $currentLargestCategory = $null
    if ($largestCurrentCategory.Count -gt 0) {
        $currentLargestCategory = [string]$largestCurrentCategory[0].category
    }

    $remainingOverSoftLimitCategoryCount = @($categoryRowsArray | Where-Object { [int]$_.previewOverSoftLimitBy -gt 0 }).Count
    $resolvedOverSoftLimitCategoryCount = @($categoryRowsArray | Where-Object {
            [int]$_.currentOverSoftLimitBy -gt 0 -and [int]$_.previewOverSoftLimitBy -eq 0
        }).Count
    $preservesPortfolioRoutes = @($safeCandidates | Where-Object {
            (Get-MemberValue -Object $_ -Name "includeInPortfolio") -ne $true
        }).Count -eq 0
    $candidateCount = [int]$candidateRepos.Count
    $status = if ($candidateCount -eq 0) {
        "no-candidates"
    } elseif ($remainingOverSoftLimitCategoryCount -gt 0) {
        "warning"
    } else {
        "ready"
    }
    $recommendation = if ($candidateCount -eq 0) {
        "keep-readme-routing-surface"
    } elseif ($remainingOverSoftLimitCategoryCount -gt 0) {
        "review-next-candidate-batch"
    } else {
        "review-catalog-demotion"
    }

    return [ordered]@{
        enabled = $true
        mode = "report-only"
        candidateSource = "readmeDensity.portfolioOnlyCandidates"
        candidateCount = $candidateCount
        candidateRepos = @($candidateRepos)
        currentProjectRowCount = [int]$safeEntries.Count
        previewProjectRowCount = [int]$previewEntries.Count
        projectRowDelta = [int]($previewEntries.Count - $safeEntries.Count)
        currentLargestCategory = $currentLargestCategory
        previewLargestCategory = $previewLargestCategory
        previewLargestCategoryCount = [int]$previewLargestCategoryCount
        remainingOverSoftLimitCategoryCount = [int]$remainingOverSoftLimitCategoryCount
        resolvedOverSoftLimitCategoryCount = [int]$resolvedOverSoftLimitCategoryCount
        preservesPortfolioRoutes = [bool]$preservesPortfolioRoutes
        catalogMutated = $false
        readmeMutated = $false
        projectsFeedMutated = $false
        status = $status
        recommendation = $recommendation
        note = "Report-only preview; catalog, README, and projects feed output are not mutated by this section."
        categoryRows = $categoryRowsArray
    }
}

function Test-ReadmeDensity {
    param(
        [string]$ExpectedReadme,
        [object[]]$Entries,
        [hashtable]$RepoLookup,
        [int]$CategorySoftLimit = $ReadmeCategorySoftLimit,
        [int]$LowSignalSoftLimit = $ReadmeLowSignalSoftLimit
    )

    $safeReadme = if ($null -eq $ExpectedReadme) { "" } else { $ExpectedReadme }
    $lineCount = if ([string]::IsNullOrEmpty($safeReadme)) {
        0
    } else {
        [regex]::Split($safeReadme.TrimEnd(), '\r?\n').Count
    }
    $detailsSectionCount = [regex]::Matches($safeReadme, '(?m)^<details>\s*$').Count
    $tableRowCount = [regex]::Matches($safeReadme, '(?m)^\| \[\*\*.+?\*\*\]\(https://github\.com/SysAdminDoc/').Count
    $categoryRows = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $repoOnlyProjectCount = 0
    $lowSignalProjectCount = 0
    $portfolioOnlyCandidateCount = 0
    $portfolioOnlyCandidateCategories = New-Object System.Collections.Generic.List[string]
    $portfolioOnlyCandidates = New-Object System.Collections.Generic.List[object]

    foreach ($definition in $CategoryDefinitions) {
        $slug = [string]$definition.Slug
        $categoryEntries = @($Entries | Where-Object { [string]$_.category -eq $slug })
        $categoryEntryRows = New-Object System.Collections.Generic.List[object]
        $repoOnlyCount = 0
        $actionableCount = 0
        $lowSignalCount = 0
        $overCategorySoftLimitBy = [Math]::Max(0, ($categoryEntries.Count - $CategorySoftLimit))
        $categoryWarnings = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $categoryEntries) {
            $meta = Get-RepoMeta $entry $RepoLookup
            $action = Get-PrimaryAction $entry $meta $entry.category
            $actionKind = [string]$action["kind"]
            $stars = if ($meta -and $null -ne (Get-MemberValue -Object $meta -Name "stargazerCount")) {
                [int](Get-MemberValue -Object $meta -Name "stargazerCount")
            } else {
                0
            }
            $release = if ($meta) { Get-MemberValue -Object $meta -Name "latestRelease" } else { $null }
            $pushedAt = if ($meta) { ConvertTo-IsoText (Get-MemberValue -Object $meta -Name "pushedAt") } else { $null }
            $categoryEntryRows.Add([ordered]@{
                    repo = [string]$entry.repo
                    title = [string]$entry.title
                    category = $slug
                    order = [int]$entry.order
                    primaryAction = $actionKind
                    stars = [int]$stars
                    includeInPortfolio = [bool]$entry.includeInPortfolio
                    featured = [bool]$entry.featured
                    currentlyBuilding = [bool]$entry.currentlyBuilding
                    hasLatestRelease = [bool]($null -ne $release)
                    pushedAt = if ([string]::IsNullOrWhiteSpace($pushedAt)) { $null } else { $pushedAt }
                    latestReleaseTag = if ($release) { [string](Get-MemberValue -Object $release -Name "tagName") } else { $null }
                    catalogReviewNote = if ([string]::IsNullOrWhiteSpace([string]$entry.readmeReviewNote)) { $null } else { [string]$entry.readmeReviewNote }
                })

            if ($actionKind -eq "repo") {
                $repoOnlyCount++
                if ($stars -eq 0) {
                    $lowSignalCount++
                }
            } else {
                $actionableCount++
            }
        }

        if ($categoryEntries.Count -gt $CategorySoftLimit) {
            $categoryWarnings.Add(("{0} has {1} README rows, above the {2} row category soft limit." -f $slug, $categoryEntries.Count, $CategorySoftLimit))
        }
        if ($lowSignalCount -ge $LowSignalSoftLimit -and $lowSignalCount -gt 0) {
            $categoryWarnings.Add(("{0} has {1} repo-only zero-star row(s); consider portfolio-only review for low-signal entries." -f $slug, $lowSignalCount))
        }

        $lowSignalCandidateCount = if ($lowSignalCount -ge $LowSignalSoftLimit) { $lowSignalCount } else { 0 }
        $categoryPortfolioOnlyCandidateCount = [Math]::Max($overCategorySoftLimitBy, $lowSignalCandidateCount)
        $categoryRoutingRecommendation = if ($categoryPortfolioOnlyCandidateCount -gt 0) {
            "review-portfolio-only-candidates"
        } else {
            "keep-in-readme"
        }
        $categoryCandidateRows = if ($categoryPortfolioOnlyCandidateCount -gt 0) {
            @($categoryEntryRows.ToArray() | Where-Object {
                    (Get-MemberValue -Object $_ -Name "primaryAction") -eq "repo" -and
                    (Get-MemberValue -Object $_ -Name "includeInPortfolio") -eq $true -and
                    (Get-MemberValue -Object $_ -Name "featured") -ne $true -and
                    (Get-MemberValue -Object $_ -Name "currentlyBuilding") -ne $true
                } | Sort-Object `
                @{ Expression = { [int](Get-MemberValue -Object $_ -Name "stars") }; Ascending = $true },
                @{ Expression = { [bool](Get-MemberValue -Object $_ -Name "hasLatestRelease") }; Ascending = $true },
                @{ Expression = {
                        $candidatePushedAt = Get-MemberValue -Object $_ -Name "pushedAt"
                        if ([string]::IsNullOrWhiteSpace([string]$candidatePushedAt)) {
                            [datetime]::MinValue
                        } else {
                            [datetime]::Parse([string]$candidatePushedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
                        }
                    }; Ascending = $true },
                @{ Expression = { [int](Get-MemberValue -Object $_ -Name "order") }; Descending = $true },
                @{ Expression = { [string](Get-MemberValue -Object $_ -Name "repo") }; Ascending = $true } |
                Select-Object -First $categoryPortfolioOnlyCandidateCount)
        } else {
            @()
        }
        foreach ($candidate in $categoryCandidateRows) {
            $candidateStars = [int](Get-MemberValue -Object $candidate -Name "stars")
            $reasonCodes = New-Object System.Collections.Generic.List[string]
            if ($overCategorySoftLimitBy -gt 0) { $reasonCodes.Add("category-over-soft-limit") }
            if ($lowSignalCandidateCount -gt 0 -and $candidateStars -eq 0) { $reasonCodes.Add("low-signal-zero-star") }
            $reasonCodes.Add("repo-only-action")
            if ((Get-MemberValue -Object $candidate -Name "hasLatestRelease") -ne $true) { $reasonCodes.Add("no-latest-release") }
            if ((Get-MemberValue -Object $candidate -Name "includeInPortfolio") -eq $true) { $reasonCodes.Add("portfolio-route-available") }

            $portfolioOnlyCandidates.Add([ordered]@{
                    reviewRank = [int]($portfolioOnlyCandidates.Count + 1)
                    category = $slug
                    displayName = Get-CategoryDisplayName -Slug $slug
                    repo = [string](Get-MemberValue -Object $candidate -Name "repo")
                    title = [string](Get-MemberValue -Object $candidate -Name "title")
                    stars = $candidateStars
                    primaryAction = [string](Get-MemberValue -Object $candidate -Name "primaryAction")
                    includeInPortfolio = [bool](Get-MemberValue -Object $candidate -Name "includeInPortfolio")
                    pushedAt = Get-MemberValue -Object $candidate -Name "pushedAt"
                    latestReleaseTag = Get-MemberValue -Object $candidate -Name "latestReleaseTag"
                    catalogReviewNote = Get-MemberValue -Object $candidate -Name "catalogReviewNote"
                    reasonCodes = @($reasonCodes.ToArray())
                    recommendation = "review-for-portfolio-only"
                })
        }

        foreach ($warning in $categoryWarnings) {
            $warnings.Add($warning)
        }

        $repoOnlyProjectCount += $repoOnlyCount
        $lowSignalProjectCount += $lowSignalCount
        $portfolioOnlyCandidateCount += $categoryPortfolioOnlyCandidateCount
        if ($categoryPortfolioOnlyCandidateCount -gt 0) {
            $portfolioOnlyCandidateCategories.Add($slug)
        }
        $categoryRows.Add([ordered]@{
            category = $slug
            displayName = Get-CategoryDisplayName -Slug $slug
            projectCount = [int]$categoryEntries.Count
            actionableCount = [int]$actionableCount
            repoOnlyCount = [int]$repoOnlyCount
            lowSignalCount = [int]$lowSignalCount
            overCategorySoftLimitBy = [int]$overCategorySoftLimitBy
            portfolioOnlyCandidateCount = [int]$categoryPortfolioOnlyCandidateCount
            routingRecommendation = $categoryRoutingRecommendation
            warningCount = [int]$categoryWarnings.Count
            warnings = @($categoryWarnings)
        })
    }

    $largestCategory = @($categoryRows | Sort-Object @{ Expression = { [int]$_.projectCount }; Descending = $true }, category | Select-Object -First 1)
    $largestCategoryName = $null
    $largestCategoryCount = 0
    if ($largestCategory.Count -gt 0) {
        $largestCategoryName = [string]$largestCategory[0].category
        $largestCategoryCount = [int]$largestCategory[0].projectCount
    }
    $warningsArray = @($warnings.ToArray())
    $categoryRowsArray = @($categoryRows.ToArray())
    $routingRecommendation = if ($portfolioOnlyCandidateCount -gt 0) {
        "review-portfolio-only-candidates"
    } else {
        "keep-readme-routing-surface"
    }
    $portfolioOnlyPreview = New-ReadmePortfolioOnlyPreview `
        -Entries $Entries `
        -Candidates $portfolioOnlyCandidates.ToArray() `
        -CategorySoftLimit $CategorySoftLimit

    return [ordered]@{
        lineCount = [int]$lineCount
        detailsSectionCount = [int]$detailsSectionCount
        tableRowCount = [int]$tableRowCount
        projectRowCount = [int](@($Entries).Count)
        categoryCount = [int]($CategoryDefinitions.Count)
        categorySoftLimit = [int]$CategorySoftLimit
        lowSignalSoftLimit = [int]$LowSignalSoftLimit
        largestCategory = $largestCategoryName
        largestCategoryCount = $largestCategoryCount
        repoOnlyProjectCount = [int]$repoOnlyProjectCount
        lowSignalProjectCount = [int]$lowSignalProjectCount
        portfolioOnlyCandidateCount = [int]$portfolioOnlyCandidateCount
        portfolioOnlyCandidateCategoryCount = [int]$portfolioOnlyCandidateCategories.Count
        portfolioOnlyCandidateCategories = @($portfolioOnlyCandidateCategories.ToArray())
        portfolioOnlyCandidateSelectionPolicy = "Review non-featured, non-currently-building repo-only rows that still have portfolio routes; sort by stars, release availability, age, category order, and repo name."
        portfolioOnlyCandidates = @($portfolioOnlyCandidates.ToArray())
        portfolioOnlyPreview = $portfolioOnlyPreview
        routingRecommendation = $routingRecommendation
        warningCount = [int]($warningsArray.Count)
        warnings = $warningsArray
        categoryRows = $categoryRowsArray
    }
}

function New-ArtifactBudgetRow {
    param(
        [string]$Artifact,
        [string]$Metric,
        [int]$Value,
        [int]$SoftLimit,
        [string]$Note
    )

    $overSoftLimit = $Value -gt $SoftLimit
    return [ordered]@{
        artifact = $Artifact
        metric = $Metric
        value = [int]$Value
        softLimit = [int]$SoftLimit
        overSoftLimit = [bool]$overSoftLimit
        warning = if ($overSoftLimit) {
            "{0} {1} is {2}, above the {3} soft limit." -f $Artifact, $Metric, $Value, $SoftLimit
        } else {
            $null
        }
        note = $Note
    }
}

function Test-GeneratedArtifactBudgets {
    param(
        [string]$ExpectedReadme,
        [string]$ExpectedProjectsJson,
        [hashtable]$ExpectedAssets,
        [AllowNull()][string]$ReportJson
    )

    $safeReadme = if ($null -eq $ExpectedReadme) { "" } else { $ExpectedReadme }
    $safeProjects = if ($null -eq $ExpectedProjectsJson) { "" } else { $ExpectedProjectsJson }
    $safeReport = if ($null -eq $ReportJson) { "" } else { $ReportJson }
    $lineCount = if ([string]::IsNullOrEmpty($safeReadme)) {
        0
    } else {
        [regex]::Split($safeReadme.TrimEnd(), '\r?\n').Count
    }
    $tableRowCount = [regex]::Matches($safeReadme, '(?m)^\| \[\*\*.+?\*\*\]\(https://github\.com/SysAdminDoc/').Count
    $detailsSectionCount = [regex]::Matches($safeReadme, '(?m)^<details>\s*$').Count
    $imageTagCount = [regex]::Matches($safeReadme, '<img\b|!\[').Count
    $codeFenceCount = [regex]::Matches($safeReadme, '(?m)^```').Count
    $codeBlockCount = [int][Math]::Floor($codeFenceCount / 2)
    $assetTotalBytes = 0
    $assetCount = 0
    $assetKeys = if ($null -eq $ExpectedAssets) {
        @()
    } elseif ($ExpectedAssets -is [System.Collections.IDictionary]) {
        @($ExpectedAssets.Keys)
    } elseif ($ExpectedAssets.PSObject.Properties.Name -contains "Keys") {
        @($ExpectedAssets.Keys)
    } else {
        @()
    }
    foreach ($assetPath in $assetKeys) {
        $assetCount++
        $assetTotalBytes += [System.Text.Encoding]::UTF8.GetByteCount(([string]$ExpectedAssets[$assetPath]) + [Environment]::NewLine)
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "bytes" -Value ([System.Text.Encoding]::UTF8.GetByteCount($safeReadme)) -SoftLimit $ReadmeSoftLimitBytes -Note "Generated profile README byte budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "lines" -Value $lineCount -SoftLimit $ReadmeLineSoftLimit -Note "Rendered profile scan budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "tableRows" -Value $tableRowCount -SoftLimit $ReadmeTableRowSoftLimit -Note "Generated project table-row budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "detailsSections" -Value $detailsSectionCount -SoftLimit $ReadmeDetailsSectionSoftLimit -Note "Collapsible section budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "imageTags" -Value $imageTagCount -SoftLimit $ReadmeImageTagSoftLimit -Note "Rendered image budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "README.md" -Metric "codeBlocks" -Value $codeBlockCount -SoftLimit $ReadmeCodeBlockSoftLimit -Note "Install-snippet block budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "projects.json" -Metric "bytes" -Value ([System.Text.Encoding]::UTF8.GetByteCount($safeProjects)) -SoftLimit $ProjectsJsonSoftLimitBytes -Note "Public portfolio feed size budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "reports/profile-sync-report.json" -Metric "bytes" -Value ([System.Text.Encoding]::UTF8.GetByteCount($safeReport)) -SoftLimit $ReportJsonSoftLimitBytes -Note "Serialized sync-report size budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "assets/profile" -Metric "bytes" -Value $assetTotalBytes -SoftLimit $ProfileAssetsSoftLimitBytes -Note "Generated profile SVG asset total budget."))
    $rows.Add((New-ArtifactBudgetRow -Artifact "assets/profile" -Metric "files" -Value $assetCount -SoftLimit $ProfileAssetsCountSoftLimit -Note "Generated profile SVG asset count budget."))

    $warnings = @($rows.ToArray() | Where-Object { $_.overSoftLimit -eq $true } | ForEach-Object { $_.warning })
    return [ordered]@{
        status = if ($warnings.Count -gt 0) { "warning" } else { "within-budget" }
        warningCount = [int]$warnings.Count
        warnings = @($warnings)
        rows = @($rows.ToArray())
    }
}

function New-RenderedProfileSmokeSummary {
    <#
    .SYNOPSIS
    Normalizes rendered profile smoke-test evidence for the sync report.
    .PARAMETER SmokeReport
    Parsed smoke-test report object, or null when no smoke artifact is available.
    .PARAMETER SourcePath
    Local rendered-profile smoke artifact path used as report provenance.
    .PARAMETER MinimumRootClientWidth
    Minimum acceptable root client width for mobile rendered-profile checks.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$SmokeReport,
        [AllowNull()][string]$SourcePath,
        [int]$MinimumRootClientWidth = $RenderedSmokeMinimumRootClientWidth
    )

    $sourcePathForReport = if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $null
    } else {
        ConvertTo-RepoRelativeReportPath -Path $SourcePath
    }

    if ($null -eq $SmokeReport) {
        $reason = "Local rendered smoke artifact was not found; run scripts/render-profile-smoke.ps1 locally to collect it."
        return [ordered]@{
            status = "not-run"
            source = "missing-local-artifact"
            sourcePath = $sourcePathForReport
            generatedAt = $null
            url = $null
            viewportCount = 0
            passedViewportCount = 0
            failedViewportCount = 0
            failedImageCount = 0
            missingSectionCount = 0
            overflowCount = 0
            minimumRootClientWidth = $null
            mobileRootClientWidth = $null
            skipReason = $reason
            warningCount = 1
            warnings = @($reason)
        }
    }

    $skipped = [bool](Get-MemberValue -Object $SmokeReport -Name "skipped")
    $skipReason = [string](Get-MemberValue -Object $SmokeReport -Name "skipReason")
    $viewports = @(Get-MemberValue -Object $SmokeReport -Name "viewports")
    $passedViewportCount = @($viewports | Where-Object { [bool](Get-MemberValue -Object $_ -Name "passed") }).Count
    $failedViewportCount = @($viewports | Where-Object { -not [bool](Get-MemberValue -Object $_ -Name "passed") }).Count
    $failedImageCount = 0
    $missingSectionCount = 0
    $overflowCount = 0
    $rootWidths = New-Object System.Collections.Generic.List[int]
    $mobileRootClientWidth = $null
    foreach ($viewport in $viewports) {
        $failedImageCount += @(Get-MemberValue -Object $viewport -Name "failedImages").Count
        $missingSectionCount += @(Get-MemberValue -Object $viewport -Name "missingSections").Count
        if ([bool](Get-MemberValue -Object $viewport -Name "rootOverflow") -or [bool](Get-MemberValue -Object $viewport -Name "documentOverflow")) {
            $overflowCount++
        }
        $rootClientWidth = Get-MemberValue -Object $viewport -Name "rootClientWidth"
        if ($null -ne $rootClientWidth) {
            $widthValue = [int]$rootClientWidth
            $rootWidths.Add($widthValue)
            if ([string](Get-MemberValue -Object $viewport -Name "name") -eq "mobile") {
                $mobileRootClientWidth = $widthValue
            }
        }
    }

    $minimumRootClientWidthValue = if ($rootWidths.Count -gt 0) {
        [int](@($rootWidths.ToArray()) | Measure-Object -Minimum).Minimum
    } else {
        $null
    }
    $warnings = New-Object System.Collections.Generic.List[string]
    if ($failedViewportCount -gt 0) {
        $warnings.Add("Rendered profile smoke has $failedViewportCount failed viewport(s).")
    }
    if ($failedImageCount -gt 0) {
        $warnings.Add("Rendered profile smoke has $failedImageCount failed image(s).")
    }
    if ($missingSectionCount -gt 0) {
        $warnings.Add("Rendered profile smoke has $missingSectionCount missing section assertion(s).")
    }
    if ($overflowCount -gt 0) {
        $warnings.Add("Rendered profile smoke has $overflowCount viewport overflow warning(s).")
    }
    if ($null -ne $mobileRootClientWidth -and $mobileRootClientWidth -lt $MinimumRootClientWidth) {
        $warnings.Add("Rendered profile mobile root width is $mobileRootClientWidth px, below the $MinimumRootClientWidth px budget.")
    }
    if ($skipped) {
        $reason = if ([string]::IsNullOrWhiteSpace($skipReason)) { "reason unavailable" } else { $skipReason }
        $warnings.Add("Rendered profile smoke did not run locally: $reason")
    }

    return [ordered]@{
        status = if ($skipped) { "not-run" } elseif ([bool](Get-MemberValue -Object $SmokeReport -Name "passed") -and $warnings.Count -eq 0) { "passed" } else { "warning" }
        source = "local-artifact"
        sourcePath = $sourcePathForReport
        generatedAt = Get-MemberValue -Object $SmokeReport -Name "generatedAt"
        url = Get-MemberValue -Object $SmokeReport -Name "url"
        viewportCount = [int]$viewports.Count
        passedViewportCount = [int]$passedViewportCount
        failedViewportCount = [int]$failedViewportCount
        failedImageCount = [int]$failedImageCount
        missingSectionCount = [int]$missingSectionCount
        overflowCount = [int]$overflowCount
        minimumRootClientWidth = $minimumRootClientWidthValue
        mobileRootClientWidth = $mobileRootClientWidth
        skipReason = if ([string]::IsNullOrWhiteSpace($skipReason)) { $null } else { $skipReason }
        warningCount = [int]$warnings.Count
        warnings = @($warnings.ToArray())
    }
}

function Read-RenderedProfileSmokeReport {
    param([string]$Path)

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return [ordered]@{
            path = $fullPath
            report = $null
        }
    }

    try {
        return [ordered]@{
            path = $fullPath
            report = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
        }
    } catch {
        return [ordered]@{
            path = $fullPath
            report = [ordered]@{
                generatedAt = (Get-Date).ToString("o")
                url = $null
                passed = $false
                skipped = $true
                skipReason = "Local rendered smoke artifact could not be read: $($_.Exception.Message)"
                viewports = @()
            }
        }
    }
}

function Get-LatestReportAffectingCommit {
    param([string[]]$Paths = $ReportAffectingPaths)

    $gitArgs = @('-C', $RepoRoot, 'log', '-1', '--format=%H%n%cI', '--') + @($Paths)
    $output = & git @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
        return [ordered]@{ sha = $null; date = $null }
    }

    $lines = @($output)
    $sha = if ($lines.Count -ge 1) { [string]$lines[0] } else { $null }
    $dateText = if ($lines.Count -ge 2) { [string]$lines[1] } else { $null }
    $date = ConvertTo-DateTimeOffsetOrNull $dateText
    return [ordered]@{ sha = $sha; date = $date }
}

function Test-ReportEvidenceFreshness {
    param(
        [AllowNull()][object]$CommittedReport,
        [AllowNull()][object]$LatestCommitDate,
        [AllowNull()][string]$LatestCommitSha,
        [string[]]$ReportAffectingPathList = $ReportAffectingPaths
    )

    $warnings = New-Object System.Collections.Generic.List[string]

    $committedPresent = $null -ne $CommittedReport
    $committedGeneratedAtText = if ($committedPresent) { ConvertTo-IsoText (Get-MemberValue -Object $CommittedReport -Name "generatedAt") } else { $null }
    $committedGeneratedAt = ConvertTo-DateTimeOffsetOrNull $committedGeneratedAtText
    $latestCommitDateOffset = ConvertTo-DateTimeOffsetOrNull $LatestCommitDate

    $smokeStatus = "unavailable"
    $smokeSource = $null
    if ($committedPresent) {
        $smoke = Get-MemberValue -Object $CommittedReport -Name "renderedProfileSmoke"
        if ($null -ne $smoke) {
            $statusValue = Get-MemberValue -Object $smoke -Name "status"
            if (-not [string]::IsNullOrWhiteSpace([string]$statusValue)) {
                $smokeStatus = [string]$statusValue
            }
            $sourceValue = Get-MemberValue -Object $smoke -Name "source"
            if (-not [string]::IsNullOrWhiteSpace([string]$sourceValue)) {
                $smokeSource = [string]$sourceValue
            }
        }
    }

    $reportBehindCommit = $false
    $reportAgeBehindHours = $null
    $generatedWithCommit = $false
    $sameCommitThresholdMinutes = 10
    if (-not $committedPresent) {
        $warnings.Add("Committed sync report was not found; report-freshness evidence is unavailable.")
    } elseif ($null -eq $committedGeneratedAt) {
        $warnings.Add("Committed sync report generatedAt is missing or unparseable.")
    } elseif ($null -ne $latestCommitDateOffset -and $committedGeneratedAt -lt $latestCommitDateOffset) {
        $reportBehindCommit = $true
        $reportAgeBehindHours = [math]::Round(($latestCommitDateOffset - $committedGeneratedAt).TotalHours, 2)
        $deltaMinutes = ($latestCommitDateOffset - $committedGeneratedAt).TotalMinutes
        if ($deltaMinutes -le $sameCommitThresholdMinutes) {
            $generatedWithCommit = $true
        } else {
            $shaLabel = if ([string]::IsNullOrWhiteSpace($LatestCommitSha)) { "the latest report-affecting commit" } else { $LatestCommitSha.Substring(0, [Math]::Min(7, $LatestCommitSha.Length)) }
            $warnings.Add("Committed sync report ($committedGeneratedAtText) is older than the latest report-affecting commit $shaLabel ($($latestCommitDateOffset.ToString('o'))); regenerate and recommit reports/profile-sync-report.json.")
        }
    }

    $smokeEvidenceStale = $false
    if ($committedPresent -and $smokeStatus -eq "not-run" -and [string]::IsNullOrWhiteSpace($smokeSource)) {
        $smokeEvidenceStale = $true
        $warnings.Add("Committed rendered-smoke status is not-run without local source metadata; run scripts/render-profile-smoke.ps1 locally and regenerate reports/profile-sync-report.json.")
    }

    $status = if ($warnings.Count -eq 0) {
        if ($generatedWithCommit) { "generated-with-commit" } else { "fresh" }
    } else { "stale" }

    return [ordered]@{
        status = $status
        committedReportPresent = [bool]$committedPresent
        committedReportGeneratedAt = $committedGeneratedAtText
        latestReportAffectingCommitSha = if ([string]::IsNullOrWhiteSpace($LatestCommitSha)) { $null } else { [string]$LatestCommitSha }
        latestReportAffectingCommitDate = if ($null -ne $latestCommitDateOffset) { $latestCommitDateOffset.ToString("o") } else { $null }
        reportAgeBehindCommit = [bool]$reportBehindCommit
        reportAgeBehindHours = $reportAgeBehindHours
        generatedWithCommit = [bool]$generatedWithCommit
        sameCommitThresholdMinutes = [int]$sameCommitThresholdMinutes
        smokeStatus = $smokeStatus
        smokeEvidenceStale = [bool]$smokeEvidenceStale
        reportAffectingPaths = @($ReportAffectingPathList)
        warnings = @($warnings.ToArray())
        warningCount = [int]$warnings.Count
    }
}

function Get-CronNumericSet {
    param(
        [string]$Field,
        [int]$Min,
        [int]$Max
    )

    if ([string]::IsNullOrWhiteSpace($Field)) { return $null }
    if ($Field -notmatch '^[0-9]+(,[0-9]+)*$') { return $null }
    $values = @($Field -split ',' | ForEach-Object { [int]$_ })
    foreach ($value in $values) {
        if ($value -lt $Min -or $value -gt $Max) { return $null }
    }
    return @($values | Sort-Object -Unique)
}

function Get-CronWeekMinuteOffsets {
    param([string]$Cron)

    if ([string]::IsNullOrWhiteSpace($Cron)) { return $null }
    $parts = @($Cron.Trim() -split '\s+')
    if ($parts.Count -ne 5) { return $null }

    $minuteField, $hourField, $domField, $monthField, $dowField = $parts
    # Only day-of-week weekly schedules are supported precisely; anything that
    # constrains day-of-month or month is treated as complex (cadence unknown).
    if ($domField -ne '*' -or $monthField -ne '*') { return $null }

    $minutes = Get-CronNumericSet -Field $minuteField -Min 0 -Max 59
    $hours = Get-CronNumericSet -Field $hourField -Min 0 -Max 23
    if ($null -eq $minutes -or $null -eq $hours) { return $null }

    if ($dowField -eq '*') {
        $days = @(0..6)
    } else {
        $days = Get-CronNumericSet -Field $dowField -Min 0 -Max 7
        if ($null -eq $days) { return $null }
        # cron treats both 0 and 7 as Sunday.
        $days = @($days | ForEach-Object { if ($_ -eq 7) { 0 } else { $_ } } | Sort-Object -Unique)
    }

    $offsets = New-Object System.Collections.Generic.List[int]
    foreach ($day in $days) {
        foreach ($hour in $hours) {
            foreach ($minute in $minutes) {
                $offsets.Add(($day * 1440) + ($hour * 60) + $minute)
            }
        }
    }
    return @($offsets.ToArray() | Sort-Object -Unique)
}

function Get-CronMaxGapMinutes {
    param([string[]]$Crons)

    $all = New-Object System.Collections.Generic.List[int]
    foreach ($cron in @($Crons)) {
        $offsets = Get-CronWeekMinuteOffsets -Cron $cron
        if ($null -eq $offsets) { return $null }
        foreach ($offset in $offsets) { $all.Add([int]$offset) }
    }

    $sorted = @($all.ToArray() | Sort-Object -Unique)
    if ($sorted.Count -eq 0) { return $null }
    if ($sorted.Count -eq 1) { return 10080 }

    $maxGap = 0
    for ($i = 1; $i -lt $sorted.Count; $i++) {
        $gap = $sorted[$i] - $sorted[$i - 1]
        if ($gap -gt $maxGap) { $maxGap = $gap }
    }
    $wrapGap = ($sorted[0] + 10080) - $sorted[$sorted.Count - 1]
    if ($wrapGap -gt $maxGap) { $maxGap = $wrapGap }
    return [int]$maxGap
}

function Get-ScheduledWorkflowDefinitions {
    param([string]$WorkflowDirectory = (Join-Path $RepoRoot ".github/workflows"))

    $definitions = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $WorkflowDirectory)) { return @() }

    foreach ($file in @(Get-ChildItem -LiteralPath $WorkflowDirectory -Filter '*.yml' -File | Sort-Object Name)) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        $crons = @([regex]::Matches($content, '(?m)^\s*-\s*cron:\s*["'']?(?<cron>[^"''\r\n]+?)["'']?\s*$') | ForEach-Object { $_.Groups['cron'].Value.Trim() })
        if ($crons.Count -eq 0) { continue }

        $nameMatch = [regex]::Match($content, '(?m)^name:\s*(?<name>.+?)\s*$')
        $name = if ($nameMatch.Success) { $nameMatch.Groups['name'].Value.Trim() } else { $file.BaseName }
        $hasDispatch = [bool][regex]::IsMatch($content, '(?m)^\s*workflow_dispatch:')

        $definitions.Add([ordered]@{
                workflowFile = ".github/workflows/$($file.Name)"
                name = $name
                crons = @($crons)
                hasWorkflowDispatch = $hasDispatch
            })
    }
    return @($definitions.ToArray())
}

function Get-ScheduledWorkflowRunLookup {
    param([object[]]$Definitions)

    $lookup = @{}
    foreach ($definition in @($Definitions)) {
        $key = [string](Get-MemberValue -Object $definition -Name "workflowFile")
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        if ($Offline) {
            $lookup[$key] = [ordered]@{
                available = $false
                state = "unknown"
                latestScheduledConclusion = $null
                latestScheduledRunAt = $null
                latestSuccessfulScheduledAt = $null
                error = "offline mode"
            }
            continue
        }

        $fileName = Split-Path -Leaf $key
        $stateResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/actions/workflows/$fileName"
        $state = if ($stateResult.ok -and $null -ne $stateResult.value) { [string]$stateResult.value.state } else { "unknown" }
        $runsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/actions/workflows/$fileName/runs?event=schedule&per_page=20"
        if (-not $runsResult.ok) {
            $lookup[$key] = [ordered]@{
                available = $false
                state = $state
                latestScheduledConclusion = $null
                latestScheduledRunAt = $null
                latestSuccessfulScheduledAt = $null
                error = $runsResult.error
            }
            continue
        }

        $runs = @($runsResult.value.workflow_runs)
        $latest = if ($runs.Count -gt 0) { $runs[0] } else { $null }
        $success = @($runs | Where-Object { [string]$_.conclusion -eq "success" } | Select-Object -First 1)
        $latestRunAt = if ($latest) { $value = Get-MemberValue -Object $latest -Name "run_started_at"; if ([string]::IsNullOrWhiteSpace([string]$value)) { Get-MemberValue -Object $latest -Name "created_at" } else { $value } } else { $null }
        $successRunAt = if ($success.Count -gt 0) { $value = Get-MemberValue -Object $success[0] -Name "run_started_at"; if ([string]::IsNullOrWhiteSpace([string]$value)) { Get-MemberValue -Object $success[0] -Name "created_at" } else { $value } } else { $null }

        $lookup[$key] = [ordered]@{
            available = $true
            state = $state
            latestScheduledConclusion = if ($latest) { [string](Get-MemberValue -Object $latest -Name "conclusion") } else { $null }
            latestScheduledRunAt = if ([string]::IsNullOrWhiteSpace([string]$latestRunAt)) { $null } else { [string]$latestRunAt }
            latestSuccessfulScheduledAt = if ([string]::IsNullOrWhiteSpace([string]$successRunAt)) { $null } else { [string]$successRunAt }
            error = $null
        }
    }
    return $lookup
}

function Test-ScheduledWorkflowFreshness {
    param(
        [object[]]$Definitions,
        [AllowNull()][hashtable]$RunLookup,
        [AllowNull()][object]$Now,
        [int]$GraceMinutes = $ScheduledWorkflowGraceMinutes
    )

    if ($null -eq $RunLookup) { $RunLookup = @{} }
    $nowOffset = ConvertTo-DateTimeOffsetOrNull $Now
    if ($null -eq $nowOffset) { $nowOffset = [datetimeoffset]::Now }

    $failingConclusions = @("failure", "cancelled", "timed_out", "startup_failure", "action_required", "stale")
    $disabledStates = @("disabled_manually", "disabled_inactivity")

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($definition in @($Definitions)) {
        $key = [string](Get-MemberValue -Object $definition -Name "workflowFile")
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        $definitionName = [string](Get-MemberValue -Object $definition -Name "name")
        $definitionCrons = @(Get-MemberValue -Object $definition -Name "crons")
        $definitionHasWorkflowDispatch = [bool](Get-MemberValue -Object $definition -Name "hasWorkflowDispatch")
        $cadence = Get-CronMaxGapMinutes -Crons $definitionCrons

        $lookup = if ($RunLookup.ContainsKey($key)) { $RunLookup[$key] } else { $null }
        $available = if ($lookup) { [bool](Get-MemberValue -Object $lookup -Name "available") } else { $false }
        $state = if ($lookup -and -not [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $lookup -Name "state"))) { [string](Get-MemberValue -Object $lookup -Name "state") } else { "unknown" }
        $latestConclusion = if ($lookup) { [string](Get-MemberValue -Object $lookup -Name "latestScheduledConclusion") } else { $null }
        $latestRunAt = if ($lookup) { Get-MemberValue -Object $lookup -Name "latestScheduledRunAt" } else { $null }
        $latestSuccessAt = if ($lookup) { Get-MemberValue -Object $lookup -Name "latestSuccessfulScheduledAt" } else { $null }
        $lookupError = if ($lookup) { [string](Get-MemberValue -Object $lookup -Name "error") } else { "no scheduled run evidence supplied" }

        $warning = $null
        $ageMinutes = $null
        $stale = $false
        $failing = $false
        if (-not $available) {
            $status = "unavailable"
            $reason = if ([string]::IsNullOrWhiteSpace($lookupError)) { "scheduled run evidence unavailable" } else { $lookupError }
            $warning = "Scheduled workflow '$definitionName' run evidence is unavailable: $reason."
        } elseif ($disabledStates -contains $state) {
            $status = "disabled"
            $warning = "Scheduled workflow '$definitionName' is $state and is not running on its cron."
        } else {
            if (-not [string]::IsNullOrWhiteSpace($latestConclusion) -and $failingConclusions -contains $latestConclusion) {
                $failing = $true
            }
            $successOffset = ConvertTo-DateTimeOffsetOrNull $latestSuccessAt
            if ($null -ne $successOffset) {
                $ageMinutes = [int][math]::Round(($nowOffset - $successOffset).TotalMinutes, 0)
                if ($null -ne $cadence -and $ageMinutes -gt ($cadence + $GraceMinutes)) {
                    $stale = $true
                }
            } else {
                $stale = $true
            }

            if ($failing) {
                $status = "failing"
                $warning = "Scheduled workflow '$definitionName' latest scheduled run concluded '$latestConclusion'."
            } elseif ($stale) {
                $status = "stale"
                if ($null -eq $successOffset) {
                    $warning = "Scheduled workflow '$definitionName' has no recorded successful scheduled run."
                } else {
                    $warning = "Scheduled workflow '$definitionName' last succeeded $ageMinutes minute(s) ago, beyond its $cadence-minute cadence plus $GraceMinutes-minute grace."
                }
            } else {
                $status = "ok"
            }
        }

        $rows.Add([ordered]@{
                workflowFile = $key
                name = $definitionName
                crons = @($definitionCrons)
                hasWorkflowDispatch = $definitionHasWorkflowDispatch
                cadenceMinutes = $cadence
                graceMinutes = [int]$GraceMinutes
                state = $state
                latestScheduledConclusion = if ([string]::IsNullOrWhiteSpace([string]$latestConclusion)) { $null } else { [string]$latestConclusion }
                latestScheduledRunAt = if ([string]::IsNullOrWhiteSpace([string]$latestRunAt)) { $null } else { [string]$latestRunAt }
                latestSuccessfulScheduledAt = if ([string]::IsNullOrWhiteSpace([string]$latestSuccessAt)) { $null } else { [string]$latestSuccessAt }
                ageMinutes = $ageMinutes
                stale = [bool]$stale
                failing = [bool]$failing
                available = [bool]$available
                status = $status
                warning = $warning
            })
    }

    $rowArray = @($rows.ToArray())
    $rowArray = @($rowArray | Sort-Object -Property @{ Expression = { [string]$_.workflowFile } })
    $staleCount = @($rowArray | Where-Object { $_.status -eq "stale" }).Count
    $failingCount = @($rowArray | Where-Object { $_.status -eq "failing" }).Count
    $unavailableCount = @($rowArray | Where-Object { $_.status -eq "unavailable" }).Count
    $disabledCount = @($rowArray | Where-Object { $_.status -eq "disabled" }).Count
    $warningCount = @($rowArray | Where-Object { $null -ne $_.warning }).Count
    $status = if ($rowArray.Count -eq 0) {
        "not-applicable"
    } elseif ($warningCount -eq 0) {
        "ok"
    } else {
        "warning"
    }

    return [ordered]@{
        status = $status
        scheduledWorkflowCount = [int]$rowArray.Count
        staleCount = [int]$staleCount
        failingCount = [int]$failingCount
        unavailableCount = [int]$unavailableCount
        disabledCount = [int]$disabledCount
        warningCount = [int]$warningCount
        graceMinutes = [int]$GraceMinutes
        rows = $rowArray
    }
}

function Get-RoadmapHygieneRules {
    # Each rule flags an OPEN roadmap entry whose completion is fully verifiable
    # from committed repository files. Items whose acceptance depends on
    # GitHub-side toggles (PVR enablement, branch settings) are intentionally
    # excluded because file state cannot prove them shipped.
    return @(
        [ordered]@{
            id = "dependency-review-action"
            marker = "Add dependency-review-action to PR workflows"
            satisfied = {
                $path = Join-Path $RepoRoot ".github/workflows/tests.yml"
                if (-not (Test-Path -LiteralPath $path)) { return $false }
                return ((Get-Content -LiteralPath $path -Raw) -match 'actions/dependency-review-action@')
            }
        },
        [ordered]@{
            id = "upload-artifact-v7"
            marker = "Upgrade upload-artifact to v7"
            satisfied = {
                $dir = Join-Path $RepoRoot ".github/workflows"
                if (-not (Test-Path -LiteralPath $dir)) { return $false }
                $all = @(Get-ChildItem -LiteralPath $dir -Filter '*.yml' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
                return ($all -match 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a') -and ($all -notmatch 'actions/upload-artifact@b7c566a772e6b6bfb58ed0dc250532a479d7789f')
            }
        },
        [ordered]@{
            id = "fetch-metadata-v3"
            marker = "fetch-metadata"
            satisfied = {
                $path = Join-Path $RepoRoot ".github/workflows/dependabot-auto-merge.yml"
                if (-not (Test-Path -LiteralPath $path)) { return $false }
                return ((Get-Content -LiteralPath $path -Raw) -match 'dependabot/fetch-metadata@25dd0e34f4fe68f24cc83900b1fe3fe149efef98')
            }
        },
        [ordered]@{
            id = "pip-dependabot"
            marker = "Add Dependabot pip updates"
            satisfied = {
                $path = Join-Path $RepoRoot ".github/dependabot.yml"
                if (-not (Test-Path -LiteralPath $path)) { return $false }
                return ((Get-Content -LiteralPath $path -Raw) -match 'package-ecosystem:\s*"pip"')
            }
        }
    )
}

function Test-RoadmapHygiene {
    <#
    .SYNOPSIS
    Reports open roadmap entries that current repository files already satisfy.
    .PARAMETER RoadmapPath
    Path to ROADMAP.md when reading roadmap text from disk.
    .PARAMETER RoadmapText
    Optional roadmap text used by tests instead of reading a file.
    .PARAMETER Rules
    Optional hygiene rule objects that map roadmap markers to satisfaction checks.
    #>
    [CmdletBinding()]
    param(
        [string]$RoadmapPath = (Join-Path $RepoRoot "ROADMAP.md"),
        [AllowNull()][string]$RoadmapText,
        [AllowNull()][object[]]$Rules
    )

    if ($null -eq $Rules) { $Rules = Get-RoadmapHygieneRules }

    $present = $false
    $text = $null
    if ($PSBoundParameters.ContainsKey("RoadmapText") -and $null -ne $RoadmapText) {
        $present = $true
        $text = $RoadmapText
    } elseif (Test-Path -LiteralPath $RoadmapPath) {
        $present = $true
        $text = Get-Content -LiteralPath $RoadmapPath -Raw
    }

    $rows = New-Object System.Collections.Generic.List[object]
    if ($present) {
        $openEntries = @([regex]::Matches($text, '(?m)^\s*-\s*\[ \]\s*(?<title>.+?)\s*$') | ForEach-Object { $_.Groups['title'].Value })
        foreach ($rule in @($Rules)) {
            $marker = [string]$rule.marker
            if ([string]::IsNullOrWhiteSpace($marker)) { continue }
            $matchingEntries = @($openEntries | Where-Object { $_ -match [regex]::Escape($marker) })
            if ($matchingEntries.Count -eq 0) { continue }

            $isSatisfied = $false
            try { $isSatisfied = [bool](& $rule.satisfied) } catch { $isSatisfied = $false }
            if ($isSatisfied) {
                $rows.Add([ordered]@{
                        ruleId = [string]$rule.id
                        marker = $marker
                        entry = [string]$matchingEntries[0]
                        reason = "Open roadmap entry matches '$marker' but current repository files already satisfy it; remove the entry."
                    })
            }
        }
    }

    $rowArray = @($rows.ToArray() | Sort-Object -Property @{ Expression = { [string]$_.ruleId } })
    return [ordered]@{
        status = if (-not $present) { "not-present" } elseif ($rowArray.Count -eq 0) { "clean" } else { "stale-entries" }
        roadmapPresent = [bool]$present
        shippedEntryCount = [int]$rowArray.Count
        warningCount = [int]$rowArray.Count
        rows = $rowArray
        note = "Warning-only roadmap hygiene: lists open ROADMAP.md entries already satisfied by committed repository files. ROADMAP.md is local-only and is typically absent in CI checkouts."
    }
}

function Test-RootMarkdownHygiene {
    <#
    .SYNOPSIS
    Checks root Markdown files against the repository documentation contract.
    .PARAMETER RepoRootPath
    Repository root to scan for root-level Markdown files.
    .PARAMETER AllowedFiles
    Markdown file names allowed at the repository root.
    .PARAMETER Exemptions
    Root Markdown names that should be reported as exempt instead of warnings.
    .PARAMETER RootMarkdownNames
    Optional file-name list used by tests instead of scanning the filesystem.
    #>
    [CmdletBinding()]
    param(
        [string]$RepoRootPath = $RepoRoot,
        [string[]]$AllowedFiles = @("README.md", "CLAUDE.md", "AGENTS.md", "CHANGELOG.md", "ROADMAP.md", "Roadmap_Blocked.md", "RESEARCH.md", "SECURITY.md"),
        [string[]]$Exemptions = @(),
        [AllowNull()][string[]]$RootMarkdownNames
    )

    if ($null -ne $RootMarkdownNames) {
        $names = @($RootMarkdownNames)
    } elseif (Test-Path -LiteralPath $RepoRootPath) {
        $names = @(Get-ChildItem -LiteralPath $RepoRootPath -Filter '*.md' -File | ForEach-Object { $_.Name })
    } else {
        $names = @()
    }

    $allowedSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($allowed in @($AllowedFiles)) { [void]$allowedSet.Add($allowed) }
    $exemptSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($exempt in @($Exemptions)) { [void]$exemptSet.Add($exempt) }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($name in @($names | Sort-Object -Unique)) {
        if ($allowedSet.Contains($name)) { continue }
        $isExempt = $exemptSet.Contains($name)
        $rows.Add([ordered]@{
                file = [string]$name
                status = if ($isExempt) { "exempt" } else { "unexpected" }
            })
    }

    $rowArray = @($rows.ToArray())
    $unexpected = @($rowArray | Where-Object { $_.status -eq "unexpected" })
    $exempt = @($rowArray | Where-Object { $_.status -eq "exempt" })

    return [ordered]@{
        status = if (@($unexpected).Count -eq 0) { "clean" } else { "unexpected-files" }
        rootMarkdownCount = [int]@($names).Count
        allowedFiles = @($AllowedFiles | Sort-Object -Unique)
        unexpectedFiles = @($unexpected | ForEach-Object { [string]$_.file })
        exemptFiles = @($exempt | ForEach-Object { [string]$_.file })
        rows = $rowArray
        warningCount = [int]@($unexpected).Count
        note = "Warning-only root Markdown hygiene against the repo documentation contract. Most non-README root Markdown is gitignored and absent in CI; historical leftovers can be removed or added to the exemption allowlist."
    }
}

function ConvertFrom-HexColor {
    param([string]$Hex)

    if ([string]::IsNullOrWhiteSpace($Hex)) { return $null }
    $value = $Hex.Trim().TrimStart('#')
    if ($value.Length -eq 3) {
        $value = [string]::Concat($value[0], $value[0], $value[1], $value[1], $value[2], $value[2])
    }
    if ($value.Length -ne 6 -or $value -notmatch '^[0-9a-fA-F]{6}$') { return $null }
    return [ordered]@{
        r = [Convert]::ToInt32($value.Substring(0, 2), 16)
        g = [Convert]::ToInt32($value.Substring(2, 2), 16)
        b = [Convert]::ToInt32($value.Substring(4, 2), 16)
    }
}

function Get-ColorRelativeLuminance {
    param([object]$Color)

    $channels = @($Color.r, $Color.g, $Color.b) | ForEach-Object {
        $c = [double]$_ / 255.0
        if ($c -le 0.03928) { $c / 12.92 } else { [Math]::Pow((($c + 0.055) / 1.055), 2.4) }
    }
    return (0.2126 * $channels[0]) + (0.7152 * $channels[1]) + (0.0722 * $channels[2])
}

function Get-ColorContrastRatio {
    param([object]$Foreground, [object]$Background)

    if ($null -eq $Foreground -or $null -eq $Background) { return $null }
    $l1 = Get-ColorRelativeLuminance -Color $Foreground
    $l2 = Get-ColorRelativeLuminance -Color $Background
    $lighter = [Math]::Max($l1, $l2)
    $darker = [Math]::Min($l1, $l2)
    return [Math]::Round((($lighter + 0.05) / ($darker + 0.05)), 2)
}

function Get-SvgContrastAnalysis {
    param(
        [string]$Name,
        [string]$Content,
        [double]$TextMinRatio = 4.5,
        [double]$NonTextMinRatio = 3.0
    )

    # Panel background = the largest numeric-area <rect> fill (the content panel
    # text actually sits on), ignoring full-canvas page backgrounds and thin
    # decorative accent stripes. Falls back to the last rect fill.
    $rectMatches = @([regex]::Matches($Content, '(?is)<rect\b[^>]*>'))
    $backgroundHex = $null
    $bestArea = -1.0
    foreach ($rect in $rectMatches) {
        $tag = $rect.Value
        $fillMatch = [regex]::Match($tag, '(?is)\bfill="(?<fill>#[0-9a-fA-F]{3,6})"')
        if (-not $fillMatch.Success) { continue }
        $widthMatch = [regex]::Match($tag, '(?is)\bwidth="(?<w>[0-9]+(?:\.[0-9]+)?)"')
        $heightMatch = [regex]::Match($tag, '(?is)\bheight="(?<h>[0-9]+(?:\.[0-9]+)?)"')
        if (-not $widthMatch.Success -or -not $heightMatch.Success) { continue }
        $area = [double]$widthMatch.Groups['w'].Value * [double]$heightMatch.Groups['h'].Value
        if ($area -gt $bestArea) {
            $bestArea = $area
            $backgroundHex = $fillMatch.Groups['fill'].Value
        }
    }
    if ([string]::IsNullOrWhiteSpace($backgroundHex)) {
        $rectFills = @($rectMatches | ForEach-Object { ([regex]::Match($_.Value, '(?is)\bfill="(?<fill>#[0-9a-fA-F]{3,6})"')).Groups['fill'].Value } | Where-Object { $_ })
        $backgroundHex = if ($rectFills.Count -gt 0) { $rectFills[$rectFills.Count - 1] } else { $null }
    }
    $background = ConvertFrom-HexColor $backgroundHex

    $textFills = @([regex]::Matches($Content, '(?is)<text\b[^>]*\bfill="(?<fill>#[0-9a-fA-F]{3,6})"') | ForEach-Object { $_.Groups['fill'].Value } | Sort-Object -Unique)

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($hex in $textFills) {
        $foreground = ConvertFrom-HexColor $hex
        $ratio = Get-ColorContrastRatio -Foreground $foreground -Background $background
        $rows.Add([ordered]@{
                foreground = [string]$hex
                ratio = $ratio
                meetsTextMin = [bool]($null -ne $ratio -and $ratio -ge $TextMinRatio)
                meetsNonTextMin = [bool]($null -ne $ratio -and $ratio -ge $NonTextMinRatio)
            })
    }

    $rowArray = @($rows.ToArray())
    $belowTextMin = @($rowArray | Where-Object { -not $_.meetsTextMin })
    $belowNonTextMin = @($rowArray | Where-Object { -not $_.meetsNonTextMin })
    $minRatio = if ($rowArray.Count -gt 0) { (@($rowArray | ForEach-Object { $_.ratio } | Where-Object { $null -ne $_ }) | Measure-Object -Minimum).Minimum } else { $null }

    return [ordered]@{
        asset = [string]$Name
        backgroundColor = if ([string]::IsNullOrWhiteSpace($backgroundHex)) { $null } else { [string]$backgroundHex }
        textColorCount = [int]$rowArray.Count
        minTextContrastRatio = $minRatio
        belowTextMinCount = [int]@($belowTextMin).Count
        belowNonTextMinCount = [int]@($belowNonTextMin).Count
        textColors = $rowArray
        pass = [bool](@($belowTextMin).Count -eq 0)
    }
}

function Test-ProfileAssetsAccessibility {
    <#
    .SYNOPSIS
    Checks generated profile SVG assets for minimum color contrast.
    .PARAMETER AssetDirectory
    Directory containing committed profile SVG assets.
    .PARAMETER AssetContents
    Optional map of asset names to SVG content used by tests.
    .PARAMETER TextMinRatio
    Minimum WCAG contrast ratio for SVG text.
    .PARAMETER NonTextMinRatio
    Minimum WCAG contrast ratio for non-text checks.
    #>
    [CmdletBinding()]
    param(
        [string]$AssetDirectory = (Join-Path $RepoRoot "assets/profile"),
        [AllowNull()][hashtable]$AssetContents,
        [double]$TextMinRatio = 4.5,
        [double]$NonTextMinRatio = 3.0
    )

    $assets = [ordered]@{}
    if ($null -ne $AssetContents) {
        foreach ($key in @($AssetContents.Keys | Sort-Object)) { $assets[$key] = [string]$AssetContents[$key] }
    } elseif (Test-Path -LiteralPath $AssetDirectory) {
        foreach ($file in @(Get-ChildItem -LiteralPath $AssetDirectory -Filter '*.svg' -File | Sort-Object Name)) {
            $assets[$file.Name] = Get-Content -LiteralPath $file.FullName -Raw
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($name in @($assets.Keys)) {
        $rows.Add((Get-SvgContrastAnalysis -Name $name -Content $assets[$name] -TextMinRatio $TextMinRatio -NonTextMinRatio $NonTextMinRatio))
    }

    $rowArray = @($rows.ToArray())
    $failingAssets = @($rowArray | Where-Object { -not $_.pass })
    $belowNonTextMin = @($rowArray | Where-Object { $_.belowNonTextMinCount -gt 0 })

    return [ordered]@{
        status = if (@($failingAssets).Count -eq 0) { "ok" } else { "warning" }
        textMinRatio = $TextMinRatio
        nonTextMinRatio = $NonTextMinRatio
        assetCount = [int]$rowArray.Count
        failingAssetCount = [int]@($failingAssets).Count
        belowNonTextMinAssetCount = [int]@($belowNonTextMin).Count
        warningCount = [int]@($failingAssets).Count
        contrastRatios = $rowArray
        note = "WCAG 2.1 contrast check of generated profile SVG <text> colors against the panel background (text min 4.5:1, non-text min 3:1). Warning-only."
    }
}

function Test-CatalogShape {
    <#
    .SYNOPSIS
    Validates catalog rows before generated profile rendering.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    #>
    [CmdletBinding()]
    param([hashtable]$Catalog)

    $issues = New-Object System.Collections.Generic.List[object]
    $allowedCategories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($definition in $CategoryDefinitions) {
        [void]$allowedCategories.Add([string]$definition.Slug)
    }
    [void]$allowedCategories.Add("suppressed")

    $allowedDownloadKinds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($kind in @("apk", "crx", "crx-xpi", "download", "exe", "repo", "userscript", "zip", "zip-xpi")) {
        [void]$allowedDownloadKinds.Add($kind)
    }

    $seenRepos = @{}
    foreach ($entry in @($Catalog.entries)) {
        $repo = [string]$entry.repo
        if ([string]::IsNullOrWhiteSpace($repo)) {
            $issues.Add([ordered]@{ repo = $null; field = "repo"; value = $repo; reason = "repo is required" })
        } else {
            $key = $repo.ToLowerInvariant()
            if ($seenRepos.ContainsKey($key)) {
                $issues.Add([ordered]@{ repo = $repo; field = "repo"; value = $repo; reason = "duplicate repo also appears as $($seenRepos[$key])" })
            } else {
                $seenRepos[$key] = $repo
            }

            if (-not (Test-SafeGitHubName -Name $repo)) {
                $issues.Add([ordered]@{ repo = $repo; field = "repo"; value = $repo; reason = "repo name must match ^[A-Za-z0-9._-]+$" })
            }
        }

        $aliasOf = [string]$entry.aliasOf
        if (-not [string]::IsNullOrWhiteSpace($aliasOf) -and -not (Test-SafeGitHubName -Name $aliasOf)) {
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "aliasOf"; value = $aliasOf; reason = "aliasOf name must match ^[A-Za-z0-9._-]+$" })
        }

        $category = [string]$entry.category
        if ([string]::IsNullOrWhiteSpace($category) -or -not $allowedCategories.Contains($category)) {
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "category"; value = $category; reason = "unknown category" })
        }

        $downloadKind = [string]$entry.downloadKind
        if (-not [string]::IsNullOrWhiteSpace($downloadKind) -and -not $allowedDownloadKinds.Contains($downloadKind)) {
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "downloadKind"; value = $downloadKind; reason = "unknown downloadKind" })
        }
    }

    return [ordered]@{
        passed = ($issues.Count -eq 0)
        issueCount = $issues.Count
        issues = $issues.ToArray()
    }
}

function Get-MemberValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}

function Test-MemberExists {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }

    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-SortedReportRows {
    param(
        [object[]]$Rows,
        [string[]]$Keys
    )

    $sortProperties = @(
        foreach ($key in $Keys) {
            $sortKey = $key
            @{
                Expression = {
                    $value = $null
                    if ($_ -is [System.Collections.IDictionary]) {
                        if ($_.Contains($sortKey)) {
                            $value = $_[$sortKey]
                        }
                    } else {
                        $property = $_.PSObject.Properties[$sortKey]
                        if ($property) {
                            $value = $property.Value
                        }
                    }
                    if ($null -eq $value) { "" } else { [string]$value }
                }.GetNewClosure()
            }
        }
    )

    return @($Rows | Sort-Object -Property $sortProperties)
}

function Set-MemberValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($null -eq $Object) {
        return
    }
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    } else {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Get-NestedMemberValue {
    param(
        [object]$Object,
        [string]$Path
    )

    $value = $Object
    foreach ($segment in ($Path -split '\.')) {
        $value = Get-MemberValue -Object $value -Name $segment
        if ($null -eq $value) {
            return $null
        }
    }
    return $value
}

function Get-NullableBool {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    return [bool]$Value
}

function Get-PublicSafeGhError {
    param([string]$Output)

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return "gh api failed without output"
    }
    if (Test-GhApiNotFound -Output $Output) {
        return "not found"
    }
    if ($Output -match '(?i)(needs|requires).*(scope|permission)') {
        return "required GitHub API scope is unavailable"
    }

    $firstLine = @($Output -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($firstLine.Count -eq 0) {
        return "gh api failed"
    }
    return (($firstLine[0] -replace '^gh:\s*', '').Trim())
}

function Convert-LicenseKeyToSpdxId {
    param([string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key)) {
        return $null
    }

    $map = @{
        "agpl-3.0" = "AGPL-3.0"
        "apache-2.0" = "Apache-2.0"
        "bsd-2-clause" = "BSD-2-Clause"
        "bsd-3-clause" = "BSD-3-Clause"
        "cc0-1.0" = "CC0-1.0"
        "gpl-2.0" = "GPL-2.0"
        "gpl-3.0" = "GPL-3.0"
        "isc" = "ISC"
        "lgpl-2.1" = "LGPL-2.1"
        "lgpl-3.0" = "LGPL-3.0"
        "mit" = "MIT"
        "mpl-2.0" = "MPL-2.0"
        "unlicense" = "Unlicense"
    }
    $normalized = $Key.ToLowerInvariant()
    if ($map.ContainsKey($normalized)) {
        return $map[$normalized]
    }
    if ($normalized -eq "other") {
        return "NOASSERTION"
    }
    return $Key
}

function Get-LicenseMetadata {
    param([object]$Meta)

    $license = Get-MemberValue -Object $Meta -Name "licenseInfo"
    if ($null -eq $license) {
        $license = Get-MemberValue -Object $Meta -Name "license"
    }

    $key = [string](Get-MemberValue -Object $license -Name "key")
    $name = [string](Get-MemberValue -Object $license -Name "name")
    $spdxId = [string](Get-MemberValue -Object $license -Name "spdxId")
    if ([string]::IsNullOrWhiteSpace($spdxId)) {
        $spdxId = [string](Get-MemberValue -Object $license -Name "spdx_id")
    }
    if ([string]::IsNullOrWhiteSpace($spdxId)) {
        $spdxId = Convert-LicenseKeyToSpdxId -Key $key
    }

    return [ordered]@{
        licenseKey = if ([string]::IsNullOrWhiteSpace($key)) { $null } else { $key }
        licenseName = if ([string]::IsNullOrWhiteSpace($name)) { $null } else { $name }
        licenseSpdxId = if ([string]::IsNullOrWhiteSpace($spdxId)) { $null } else { $spdxId }
    }
}

function Invoke-GhApiJsonSafe {
    param([string]$Path)

    $gh = Invoke-GhCli -Arguments @("api", $Path)
    $text = $gh.text
    if ($gh.exitCode -ne 0) {
        return [ordered]@{
            ok = $false
            value = $null
            error = Get-PublicSafeGhError -Output $text
        }
    }

    try {
        return [ordered]@{
            ok = $true
            value = ($text | ConvertFrom-Json)
            error = $null
        }
    } catch {
        return [ordered]@{
            ok = $false
            value = $null
            error = "gh api returned malformed JSON"
        }
    }
}

function Get-PublicSafeRestError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $statusCode = $null
    if ($ErrorRecord.Exception -and $ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.StatusCode) {
        $statusCode = [int]$ErrorRecord.Exception.Response.StatusCode
    }
    if ($null -ne $statusCode) {
        return "HTTP $statusCode"
    }

    $message = if ($ErrorRecord.Exception) { [string]$ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    if ([string]::IsNullOrWhiteSpace($message)) {
        return "request failed"
    }
    return ($message -replace '[\r\n]+', ' ').Trim()
}

function Invoke-RestJsonSafe {
    param([string]$Uri)

    try {
        $value = Invoke-RestMethod `
            -Uri $Uri `
            -Method Get `
            -Headers @{ Accept = "application/json"; "User-Agent" = "SysAdminDoc-profile-sync" } `
            -TimeoutSec 20 `
            -MaximumRedirection 5

        return [ordered]@{
            ok = $true
            value = $value
            error = $null
        }
    } catch {
        return [ordered]@{
            ok = $false
            value = $null
            error = Get-PublicSafeRestError -ErrorRecord $_
        }
    }
}

function Get-CommunityLocalFileStatus {
    $checks = @(
        [ordered]@{ path = "README.md"; required = $true },
        [ordered]@{ path = "LICENSE"; required = $true },
        [ordered]@{ path = "SECURITY.md"; required = $true },
        [ordered]@{ path = ".github/CODEOWNERS"; required = $true },
        [ordered]@{ path = ".github/pull_request_template.md"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/broken-link.yml"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/profile-correction.yml"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/local-validation.yml"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/config.yml"; required = $true },
        [ordered]@{ path = "CONTRIBUTING.md"; required = $false },
        [ordered]@{ path = "CODE_OF_CONDUCT.md"; required = $false }
    )

    return @($checks | ForEach-Object {
        $path = [string]$_["path"]
        [ordered]@{
            path = $path
            required = [bool]$_["required"]
            exists = [bool](Test-Path -LiteralPath (Join-Path $RepoRoot $path))
        }
    })
}

function Get-CodeScanningLocalEvidence {
    param([string]$WorkflowDirectory = (Join-Path $RepoRoot ".github/workflows"))

    $workflowFiles = @()
    $workflowText = ""
    if (Test-Path -LiteralPath $WorkflowDirectory) {
        $workflowFiles = @(Get-ChildItem -LiteralPath $WorkflowDirectory -Filter "*.yml" -File -ErrorAction SilentlyContinue | Sort-Object Name)
        $workflowText = (($workflowFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")
    }

    $validateLocalPath = Join-Path $RepoRoot "scripts/validate-local.ps1"
    $validateLocalText = if (Test-Path -LiteralPath $validateLocalPath) { Get-Content -LiteralPath $validateLocalPath -Raw } else { "" }
    $packageJsonPath = Join-Path $RepoRoot "package.json"
    $packageJsonText = if (Test-Path -LiteralPath $packageJsonPath) { Get-Content -LiteralPath $packageJsonPath -Raw } else { "" }
    $psScriptAnalyzerSettingsPresent = Test-Path -LiteralPath (Join-Path $RepoRoot "PSScriptAnalyzerSettings.psd1")
    $testsPresent = Test-Path -LiteralPath (Join-Path $RepoRoot "tests")
    $zizmorConfigPresent = Test-Path -LiteralPath (Join-Path $RepoRoot ".github/zizmor.yml")

    $hasCodeQlWorkflow = [regex]::IsMatch($workflowText, '(?i)github/codeql-action/(init|analyze)@|codeql\s+(database|analyze)')
    $hasSarifUpload = [regex]::IsMatch($workflowText, '(?i)github/codeql-action/upload-sarif@')
    $hasScorecardSarif = (
        [regex]::IsMatch($workflowText, '(?i)ossf/scorecard-action@') -and
        [regex]::IsMatch($workflowText, '(?m)^\s*results_format:\s*sarif\s*$') -and
        $hasSarifUpload
    )

    return [ordered]@{
        workflowFilesInspected = @($workflowFiles | ForEach-Object { $_.Name })
        codeqlWorkflowPresent = [bool]$hasCodeQlWorkflow
        sarifUploadWorkflowPresent = [bool]$hasSarifUpload
        scorecardSarifUploadPresent = [bool]$hasScorecardSarif
        psScriptAnalyzerWorkflowPresent = [bool][regex]::IsMatch($workflowText, '(?i)Invoke-ScriptAnalyzer|PSScriptAnalyzer')
        actionlintWorkflowPresent = [bool][regex]::IsMatch($workflowText, '(?i)\bactionlint\b')
        zizmorWorkflowPresent = [bool][regex]::IsMatch($workflowText, '(?i)\bzizmor\b')
        localValidationScriptPresent = [bool](Test-Path -LiteralPath $validateLocalPath)
        psScriptAnalyzerLocalPresent = [bool]($psScriptAnalyzerSettingsPresent -and [regex]::IsMatch($validateLocalText, '(?i)\bInvoke-ScriptAnalyzer\b'))
        pesterLocalPresent = [bool]($testsPresent -and [regex]::IsMatch($validateLocalText, '(?i)\bInvoke-Pester\b'))
        markdownlintLocalPresent = [bool]([regex]::IsMatch($packageJsonText, '(?i)markdownlint-cli2') -and [regex]::IsMatch($validateLocalText, '(?i)lint:markdown'))
        zizmorLocalConfigPresent = [bool]$zizmorConfigPresent
    }
}

function Get-DependabotSecurityPosture {
    param(
        [object]$DependabotSecurityUpdates,
        [string]$UnavailableReason
    )

    $configPath = ".github/dependabot.yml"
    $fullConfigPath = Join-Path $RepoRoot $configPath
    $configPresent = Test-Path -LiteralPath $fullConfigPath
    $ecosystems = @()
    if ($configPresent) {
        $configText = Get-Content -LiteralPath $fullConfigPath -Raw
        $ecosystems = @([regex]::Matches($configText, 'package-ecosystem:\s*"?([^"\r\n]+)"?') | ForEach-Object {
                $_.Groups[1].Value.Trim()
            } | Sort-Object -Unique)
    }

    $statusText = if ($null -eq $DependabotSecurityUpdates) { "" } else { [string]$DependabotSecurityUpdates }
    $available = -not [string]::IsNullOrWhiteSpace($statusText)
    $securityUpdatesEnabled = [bool]($statusText -eq "enabled")
    $status = if (-not $available) {
        "unavailable"
    } elseif ($securityUpdatesEnabled) {
        "enabled"
    } else {
        "disabled"
    }

    $recommendation = if ($status -eq "enabled") {
        "monitor-dependabot-security-updates"
    } elseif ($status -eq "disabled") {
        "enable-dependabot-security-updates-or-document-manual-triage"
    } else {
        "verify-dependabot-security-update-setting"
    }

    $evidence = if ($status -eq "disabled") {
        "Local Dependabot version-update config is present for $($ecosystems.Count) ecosystem(s), but repository security_and_analysis.dependabot_security_updates.status is disabled."
    } elseif ($status -eq "enabled") {
        "Dependabot security updates are enabled, and local version-update config is present for $($ecosystems.Count) ecosystem(s)."
    } elseif (-not [string]::IsNullOrWhiteSpace($UnavailableReason)) {
        "Dependabot security update setting was unavailable from repository metadata and automated-security-fixes endpoint: $UnavailableReason."
    } else {
        "Dependabot security update setting was unavailable from repository metadata and automated-security-fixes endpoint."
    }

    $nextAction = if ($status -eq "disabled") {
        "Enable Dependabot security updates in repository settings, or record why manual security triage is sufficient for this profile repository."
    } elseif ($status -eq "enabled") {
        "Keep monitoring Dependabot alert volume and grouped version-update PRs."
    } else {
        "Re-query repository security_and_analysis metadata or the automated-security-fixes endpoint before changing Dependabot policy."
    }

    return [ordered]@{
        available = $available
        status = $status
        recommendation = $recommendation
        dependabotSecurityUpdatesStatus = if ($available) { $statusText } else { $null }
        securityUpdatesEnabled = if ($available) { $securityUpdatesEnabled } else { $null }
        localConfigPresent = [bool]$configPresent
        localConfigPath = $configPath
        localConfigEcosystems = @($ecosystems)
        warningDisposition = if ($status -eq "disabled") { "repository-setting-warning" } else { "none" }
        documentationPath = "decision:dependabot-security-posture"
        evidence = $evidence
        nextAction = $nextAction
    }
}

function Test-SecurityPolicyLinkedReportingTarget {
    $path = Join-Path $RepoRoot "SECURITY.md"
    if (-not (Test-Path -LiteralPath $path)) {
        return $false
    }

    $text = Get-Content -LiteralPath $path -Raw
    return [bool][regex]::IsMatch($text, '(?i)\bhttps?://|mailto:')
}

function Get-ScorecardScoreApiUrl {
    return "https://api.securityscorecards.dev/projects/github.com/$Owner/$Owner"
}

function ConvertTo-NullableDouble {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal] -or $Value -is [int] -or $Value -is [long]) {
        return [double]$Value
    }

    $parsed = [double]0
    if ([double]::TryParse(
            [string]$Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed
        )) {
        return $parsed
    }
    return $null
}

function Get-ScorecardScoreSnapshot {
    param(
        [object]$ScorecardScoreResult,
        [string]$UnavailableReason
    )

    $sourceUrl = Get-ScorecardScoreApiUrl
    $score = ConvertTo-NullableDouble (Get-MemberValue -Object $ScorecardScoreResult -Name "score")
    $resultRepo = Get-MemberValue -Object $ScorecardScoreResult -Name "repo"
    $missingReason = if ([string]::IsNullOrWhiteSpace($UnavailableReason)) { "scorecard score evidence was not supplied" } else { $UnavailableReason }
    if ($null -eq $ScorecardScoreResult -or $null -eq $score -or -not [string]::IsNullOrWhiteSpace($UnavailableReason)) {
        return [ordered]@{
            available = $false
            score = $null
            maxScore = 10
            provider = "securityscorecards-api"
            sourceUrl = $sourceUrl
            date = $null
            analyzedRepo = $null
            analyzedCommit = $null
            unavailableReason = if ($null -eq $ScorecardScoreResult -or -not [string]::IsNullOrWhiteSpace($UnavailableReason)) { $missingReason } else { "scorecard API result omitted a numeric score" }
        }
    }

    return [ordered]@{
        available = $true
        score = $score
        maxScore = 10
        provider = "securityscorecards-api"
        sourceUrl = $sourceUrl
        date = ConvertTo-IsoText (Get-MemberValue -Object $ScorecardScoreResult -Name "date")
        analyzedRepo = [string](Get-MemberValue -Object $resultRepo -Name "name")
        analyzedCommit = [string](Get-MemberValue -Object $resultRepo -Name "commit")
        unavailableReason = $null
    }
}

function New-ScorecardAlertPostureRow {
    param(
        [object]$Alert,
        [bool]$SecurityPolicyHasLinkedReportingTarget
    )

    $rule = Get-MemberValue -Object $Alert -Name "rule"
    $ruleId = [string](Get-MemberValue -Object $rule -Name "id")
    $description = [string](Get-MemberValue -Object $rule -Name "description")
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = [string](Get-MemberValue -Object $rule -Name "name")
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = $ruleId
    }

    $classification = "needs-review"
    $localDisposition = "review-alert"
    $localEvidence = "Scorecard alert needs local review before classification."
    $nextAction = "Review the Scorecard check details and update this posture row."
    switch ($ruleId) {
        "CodeReviewID" {
            $classification = "external-gated-reviewer-model"
            $localDisposition = "not-fixed-by-local-report"
            $localEvidence = "PR delivery and required checks are proven; pull request review enforcement remains warning-only until an independent reviewer or team model exists."
            $nextAction = "Define an independent reviewer or team model before requiring pull request reviews; keep required-check PR delivery in the meantime."
        }
        "BranchProtectionID" {
            $classification = "external-gated-branch-protection-policy"
            $localDisposition = "policy-gated-scorecard-control"
            $localEvidence = "Required-check readiness and direct-main maintenance policy are tracked separately; enabling branch-protection enforcement is a repository policy decision, not an unclassified local code gap."
            $nextAction = "Keep required-check readiness evidence current and enable enforcement only after the direct-main maintenance policy changes."
        }
        "SecurityPolicyID" {
            if ($SecurityPolicyHasLinkedReportingTarget) {
                $classification = "local-fix-pending-scorecard-refresh"
                $localDisposition = "fixed-locally"
                $localEvidence = "SECURITY.md includes a direct private vulnerability reporting URL."
                $nextAction = "Rerun the local security posture summary and verify the Security-Policy alert closes or score improves."
            } else {
                $classification = "actionable-local-gap"
                $localDisposition = "needs-local-fix"
                $localEvidence = "SECURITY.md is present but lacks a URL or mailto reporting target."
                $nextAction = "Add a public-safe private vulnerability reporting URL or security contact."
            }
        }
        "SASTID" {
            $classification = "covered-by-local-static-analysis"
            $localDisposition = "accepted-scorecard-limitation"
            $localEvidence = "The live language mix is PowerShell-only; CodeQL is not applicable, while local validation covers PSScriptAnalyzer, markdownlint, Pester, and local zizmor configuration review."
            $nextAction = "Reopen the CodeQL posture decision when a CodeQL-supported language appears."
        }
        "CIIBestPracticesID" {
            $classification = "external-program-optional"
            $localDisposition = "manual-governance-choice"
            $localEvidence = "OpenSSF Best Practices badge enrollment is an external manual governance program, not a local repository defect."
            $nextAction = "Enroll in the OpenSSF Best Practices program only if the maintainer wants the external badge workflow."
        }
        "FuzzingID" {
            $classification = "not-applicable-profile-generator"
            $localDisposition = "accepted-scorecard-limitation"
            $localEvidence = "This repository is a deterministic profile README/catalog generator with Pester fixtures rather than a binary parser or network service."
            $nextAction = "Consider property-based generator tests if catalog input handling becomes broader or riskier."
        }
    }

    $tool = Get-MemberValue -Object $Alert -Name "tool"
    return [ordered]@{
        alertNumber = Get-MemberValue -Object $Alert -Name "number"
        ruleId = $ruleId
        checkName = $description
        state = [string](Get-MemberValue -Object $Alert -Name "state")
        severity = [string](Get-MemberValue -Object $rule -Name "severity")
        securitySeverity = [string](Get-MemberValue -Object $rule -Name "security_severity_level")
        classification = $classification
        localDisposition = $localDisposition
        localEvidence = $localEvidence
        nextAction = $nextAction
        htmlUrl = Get-MemberValue -Object $Alert -Name "html_url"
        helpUrl = Get-MemberValue -Object $rule -Name "help_uri"
        toolName = [string](Get-MemberValue -Object $tool -Name "name")
        toolVersion = [string](Get-MemberValue -Object $tool -Name "version")
        createdAt = Get-MemberValue -Object $Alert -Name "created_at"
        updatedAt = Get-MemberValue -Object $Alert -Name "updated_at"
    }
}

function Get-ScorecardAlertPosture {
    param(
        [object[]]$Alerts,
        [string]$UnavailableReason
    )

    $available = ($null -ne $Alerts -and [string]::IsNullOrWhiteSpace($UnavailableReason))
    if (-not $available) {
        return [ordered]@{
            available = $false
            unavailableReason = if ([string]::IsNullOrWhiteSpace($UnavailableReason)) { "scorecard alert evidence was not supplied" } else { $UnavailableReason }
            provider = "github-code-scanning-alerts"
            tool = "Scorecard"
            queriedAt = $script:MetadataSnapshotAt
            openAlertCount = 0
            localActionableCount = 0
            needsHostedRefreshCount = 0
            externalGatedCount = 0
            notApplicableCount = 0
            recommendation = "verify-scorecard-alerts-with-security-api"
            rows = @()
            note = "Scorecard alert posture is informational and does not fail profile sync when the code-scanning alerts API is unavailable."
        }
    }

    $securityPolicyHasLink = Test-SecurityPolicyLinkedReportingTarget
    $rows = @(Get-SortedReportRows -Rows @($Alerts | ForEach-Object {
            New-ScorecardAlertPostureRow -Alert $_ -SecurityPolicyHasLinkedReportingTarget $securityPolicyHasLink
        }) -Keys @("ruleId"))
    $localActionableCount = @($rows | Where-Object { $_.classification -eq "actionable-local-gap" }).Count
    $needsHostedRefreshCount = @($rows | Where-Object { $_.classification -eq "local-fix-pending-scorecard-refresh" }).Count
    $externalGatedCount = @($rows | Where-Object { $_.classification -in @("external-gated-pr-delivery", "external-gated-reviewer-model", "external-gated-branch-protection-policy", "external-program-optional") }).Count
    $notApplicableCount = @($rows | Where-Object { $_.classification -in @("covered-by-local-static-analysis", "not-applicable-profile-generator") }).Count
    $recommendation = if ($localActionableCount -gt 0) {
        "fix-local-scorecard-alerts"
    } elseif ($needsHostedRefreshCount -gt 0) {
        "rerun-scorecard-to-refresh-alerts"
    } elseif ($externalGatedCount -gt 0) {
        "track-external-scorecard-governance-items"
    } else {
        "keep-current-scorecard-controls"
    }

    return [ordered]@{
        available = $true
        unavailableReason = $null
        provider = "github-code-scanning-alerts"
        tool = "Scorecard"
        queriedAt = $script:MetadataSnapshotAt
        openAlertCount = $rows.Count
        localActionableCount = $localActionableCount
        needsHostedRefreshCount = $needsHostedRefreshCount
        externalGatedCount = $externalGatedCount
        notApplicableCount = $notApplicableCount
        recommendation = $recommendation
        rows = @($rows)
        note = "Rows classify open Scorecard SARIF alerts as local fixes, hosted-refresh waits, accepted tool limitations, or external governance items; the posture remains warning-only."
    }
}

function Get-RequiredCheckReadiness {
    param(
        [bool]$BranchProtectionAvailable,
        [bool]$RulesetsAvailable,
        [Nullable[bool]]$RequiredStatusChecks,
        [Nullable[bool]]$EnforceAdmins,
        [Nullable[bool]]$ActionsPullRequestCreationAllowed,
        [int]$RulesetCount,
        [string]$BranchProtectionUnavailableReason,
        [string]$RulesetsUnavailableReason
    )

    $workflowCoverage = Test-RequiredCheckWorkflowCoverage
    if ((Get-MemberValue -Object $workflowCoverage -Name "status") -eq "not-applicable") {
        $prDeliveryTransition = Get-PrDeliveryTransitionChecklist `
            -WorkflowCoverage $workflowCoverage `
            -RequiredChecksEnabled $false `
            -EnforceAdmins $EnforceAdmins `
            -ActionsPullRequestCreationAllowed $ActionsPullRequestCreationAllowed `
            -BranchProtectionAvailable $BranchProtectionAvailable `
            -RulesetsAvailable $RulesetsAvailable

        return [ordered]@{
            status = "not-applicable"
            recommendation = "local-validation-only"
            readyForEnforcement = $false
            branchProtectionRequiredStatusChecks = Get-NullableBool $RequiredStatusChecks
            rulesetCount = [int]$RulesetCount
            enforceAdmins = Get-NullableBool $EnforceAdmins
            candidateCheckCount = 0
            candidateChecks = @()
            workflowCoverage = $workflowCoverage
            prDeliveryTransition = $prDeliveryTransition
            blockerCount = 0
            blockers = @()
        }
    }

    $routinePrDrillEvidence = Get-RoutineMaintenancePrDrillEvidence
    $routinePrDeliveryProven = ((Get-MemberValue -Object $routinePrDrillEvidence -Name "status") -eq "passed")
    $requiredChecksEnabled = ($RequiredStatusChecks -eq $true -or $RulesetCount -gt 0)
    $blockers = New-Object System.Collections.Generic.List[string]
    if (-not $BranchProtectionAvailable -and -not [string]::IsNullOrWhiteSpace($BranchProtectionUnavailableReason)) {
        $blockers.Add("Branch protection evidence unavailable: $BranchProtectionUnavailableReason.")
    } elseif ($RequiredStatusChecks -ne $true) {
        $blockers.Add("Branch protection does not require status checks.")
    }

    if (-not $RulesetsAvailable -and -not [string]::IsNullOrWhiteSpace($RulesetsUnavailableReason)) {
        $blockers.Add("Repository ruleset evidence unavailable: $RulesetsUnavailableReason.")
    } elseif ($RulesetCount -eq 0 -and $RequiredStatusChecks -ne $true) {
        $blockers.Add("No repository rulesets are configured.")
    }

    if ($EnforceAdmins -eq $true -and -not $routinePrDeliveryProven) {
        $blockers.Add("Protected main enforces admins; routine PR delivery is selected but still needs a live merge drill before enabling required checks.")
    }

    $prDeliveryTransition = Get-PrDeliveryTransitionChecklist `
        -WorkflowCoverage $workflowCoverage `
        -RequiredChecksEnabled $requiredChecksEnabled `
        -EnforceAdmins $EnforceAdmins `
        -ActionsPullRequestCreationAllowed $ActionsPullRequestCreationAllowed `
        -BranchProtectionAvailable $BranchProtectionAvailable `
        -RulesetsAvailable $RulesetsAvailable `
        -RoutineMaintenancePrDrillEvidence $routinePrDrillEvidence

    $status = if (-not $BranchProtectionAvailable -and -not $RulesetsAvailable) {
        "needs-live-validation"
    } elseif ($requiredChecksEnabled) {
        "enforcement-present"
    } else {
        "not-enabled"
    }

    $recommendation = if ($requiredChecksEnabled -and $blockers.Count -eq 0) {
        "monitor-required-check-enforcement"
    } else {
        "defer-until-pr-delivery-or-bypass"
    }

    return [ordered]@{
        status = $status
        recommendation = $recommendation
        readyForEnforcement = [bool]($blockers.Count -eq 0)
        branchProtectionRequiredStatusChecks = Get-NullableBool $RequiredStatusChecks
        rulesetCount = [int]$RulesetCount
        enforceAdmins = Get-NullableBool $EnforceAdmins
        candidateCheckCount = @($RequiredStatusCheckCandidates).Count
        candidateChecks = @($RequiredStatusCheckCandidates)
        workflowCoverage = $workflowCoverage
        prDeliveryTransition = $prDeliveryTransition
        blockerCount = $blockers.Count
        blockers = $blockers.ToArray()
    }
}

function New-PrDeliveryChecklistItem {
    param(
        [string]$Id,
        [ValidateSet("ready", "blocked", "needs-live-validation")]
        [string]$Status,
        [string]$Summary,
        [string]$Evidence,
        [string]$NextAction
    )

    return [ordered]@{
        id = $Id
        status = $Status
        summary = $Summary
        evidence = $Evidence
        nextAction = $NextAction
    }
}

function Get-GeneratedPrDryRunEvidence {
    return $null
}

function Get-GeneratedPrWriteEvidence {
    return $null
}

function Get-GeneratedPrCredentialDecision {
    param(
        [Nullable[bool]]$ActionsPullRequestCreationAllowed
    )

    $settingAllowsGeneratedPr = Get-NullableBool $ActionsPullRequestCreationAllowed
    return [ordered]@{
        status = "not-applicable"
        selectedPath = "manual-local-validation"
        rejectedPath = "hosted-generated-pr-delivery"
        rationale = "Hosted workflows are absent by policy; generated PR helpers are retained only as offline/manual previews and do not need repository Actions PR creation settings."
        requiresRepositorySetting = $false
        requiresNewSecret = $false
        currentSettingAllowsGeneratedPr = $settingAllowsGeneratedPr
        decisionDocumentPath = "decision:local-validation-only"
        activationCommand = ""
        nextAction = "Use scripts/validate-local.ps1 and scripts/render-profile-smoke.ps1 before committing generated artifacts locally."
    }
}

function Test-RequiredCheckWorkflowCoverage {
    param(
        [object[]]$Candidates = $RequiredStatusCheckCandidates
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $workflowRows = New-Object System.Collections.Generic.List[object]
    $workflowPaths = @($Candidates | ForEach-Object { [string](Get-MemberValue -Object $_ -Name "workflow") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

    if (@($Candidates).Count -eq 0 -or $workflowPaths.Count -eq 0) {
        return [ordered]@{
            status = "not-applicable"
            workflowCount = 0
            candidateCheckCount = 0
            warningCount = 0
            warnings = @()
            workflows = @()
        }
    }

    foreach ($workflowPath in $workflowPaths) {
        $candidateNames = @($Candidates | Where-Object {
                [string](Get-MemberValue -Object $_ -Name "workflow") -eq $workflowPath
            } | ForEach-Object {
                [string](Get-MemberValue -Object $_ -Name "name")
            })
        $literalPath = Join-Path $RepoRoot $workflowPath
        $exists = Test-Path -LiteralPath $literalPath
        $text = if ($exists) { Get-Content -LiteralPath $literalPath -Raw } else { "" }
        $hasPullRequest = [bool][regex]::IsMatch($text, '(?m)^  pull_request:\s*$')
        $hasMergeGroup = [bool][regex]::IsMatch($text, '(?m)^  merge_group:\s*$')
        $pullRequestPathFiltered = [bool][regex]::IsMatch($text, '(?ms)^  pull_request:\s*\r?\n\s+paths:')
        $missingCandidateNames = @($candidateNames | Where-Object {
                -not [regex]::IsMatch($text, "(?m)^\s+name:\s*$([regex]::Escape($_))\s*$")
            })

        if (-not $exists) {
            $warnings.Add("Candidate required-check workflow is missing: $workflowPath.")
        }
        if ($exists -and -not $hasPullRequest) {
            $warnings.Add("Candidate required-check workflow lacks pull_request trigger: $workflowPath.")
        }
        if ($exists -and -not $hasMergeGroup) {
            $warnings.Add("Candidate required-check workflow lacks merge_group trigger: $workflowPath.")
        }
        if ($exists -and $pullRequestPathFiltered) {
            $warnings.Add("Candidate required-check workflow path-filters pull_request runs: $workflowPath.")
        }
        foreach ($candidateName in $missingCandidateNames) {
            $warnings.Add("Candidate required-check job name '$candidateName' was not found in $workflowPath.")
        }

        $workflowRows.Add([ordered]@{
                workflow = $workflowPath
                candidateChecks = @($candidateNames)
                exists = [bool]$exists
                pullRequestTrigger = $hasPullRequest
                mergeGroupTrigger = $hasMergeGroup
                pullRequestPathFiltered = $pullRequestPathFiltered
                missingCandidateCheckNames = @($missingCandidateNames)
            })
    }

    return [ordered]@{
        status = if ($warnings.Count -eq 0) { "ready" } else { "blocked" }
        workflowCount = $workflowRows.Count
        candidateCheckCount = @($Candidates).Count
        warningCount = $warnings.Count
        warnings = $warnings.ToArray()
        workflows = @($workflowRows.ToArray())
    }
}

function Get-DirectMainMaintenancePolicy {
    return [ordered]@{
        status = "pr-delivery-proven"
        allowed = $false
        requiredBeforeEnforcement = $true
        selectedPath = "pull-request-delivery"
        recommendation = "keep-pr-delivery"
        documentationPath = "decision:routine-maintenance-pr-delivery"
        evidence = "No direct-main bypass actor is approved. Routine maintenance uses pull-request delivery; PR #14 proved routine PR delivery before enforcement, and PR #16 proved it under active required checks."
        nextAction = "Keep routine maintenance on pull-request delivery unless a separate approved bypass is documented."
    }
}

function Get-CandidateCheckExercisePlan {
    return $null
}

function Get-CandidateCheckExerciseEvidence {
    return $null
}

function Get-RoutineMaintenancePrDrillEvidence {
    return [ordered]@{
        available = $true
        status = "passed"
        evidenceStatus = "successful"
        requiredBeforeEnforcement = $true
        selectedPath = "pull-request-delivery"
        pullRequestNumber = 14
        pullRequestUrl = "https://github.com/SysAdminDoc/SysAdminDoc/pull/14"
        pullRequestState = "merged"
        branch = "routine-pr-drill-evidence"
        headSha = "65475b7b47fc1e33a96843a131108b2660b18d19"
        mergeSha = "64e02f3b4b9737f77b4629052dabc9f449e261bb"
        workflowRunIds = @(
            27090770215,
            27090770193,
            27090770203
        )
        profileSyncRunId = 27090770215
        testsRunId = 27090770193
        workflowSecurityRunId = 27090770203
        expectedCandidateCheckCount = @($RequiredStatusCheckCandidates).Count
        observedCandidateCheckCount = 6
        successfulCandidateCheckCount = 6
        failedCandidateCheckCount = 0
        successfulCandidateChecks = @(
            "Check generated README",
            "PSScriptAnalyzer",
            "Pester (offline)",
            "Markdownlint",
            "Windows setup smoke",
            "zizmor"
        )
        failedCandidateChecks = @()
        mergeMethod = "rebase"
        cleanupState = "merged-pr-and-deleted-branch"
        evidenceSummary = "Routine maintenance PR #14 merged by rebase after all six candidate checks passed. GitHub deleted the routine-pr-drill-evidence branch after merge. Squash and merge-commit methods are disabled for this repository."
        documentationPath = "decision:routine-maintenance-pr-delivery"
        nextAction = "Required-check enforcement proof is now recorded by PR #16; keep future maintenance on PR delivery."
    }
}

function Get-RequiredCheckEnforcementEvidence {
    return [ordered]@{
        available = $true
        status = "passed"
        evidenceStatus = "successful"
        enforcementMechanism = "branch-protection"
        strictRequiredStatusChecks = $true
        pullRequestNumber = 16
        pullRequestUrl = "https://github.com/SysAdminDoc/SysAdminDoc/pull/16"
        pullRequestState = "merged"
        branch = "record-required-check-enforcement"
        headSha = "8575e324182b96527bb9b58420d5ff44e3c05c06"
        mergeSha = "dc05296386af847d4e89803f1ed3ac966df49fb7"
        mergedAt = "2026-06-07T11:58:25Z"
        workflowRunIds = @(
            27091837034,
            27091837025,
            27091837036
        )
        profileSyncRunId = 27091837034
        testsRunId = 27091837025
        workflowSecurityRunId = 27091837036
        profileSyncArtifactId = 7463884699
        renderedSmokeArtifactId = 7463884770
        expectedCandidateCheckCount = @($RequiredStatusCheckCandidates).Count
        observedCandidateCheckCount = 6
        successfulCandidateCheckCount = 6
        failedCandidateCheckCount = 0
        skippedNonCandidateCheckCount = 3
        successfulCandidateChecks = @(
            "Check generated README",
            "PSScriptAnalyzer",
            "Pester (offline)",
            "Markdownlint",
            "Windows setup smoke",
            "zizmor"
        )
        failedCandidateChecks = @()
        skippedNonCandidateChecks = @(
            "Open generated README PR",
            "Preview generated README PR",
            "Generated profile validation status"
        )
        mergeMethod = "rebase"
        cleanupState = "merged-pr-and-deleted-branch"
        evidenceSummary = "PR #16 was the first normal maintenance pull request after branch-protection required checks were enabled. GitHub required all six candidate checks, every candidate check passed on head SHA 8575e324182b96527bb9b58420d5ff44e3c05c06, and the pull request merged by rebase."
        documentationPath = "decision:pr-delivery-transition-checklist"
        nextAction = "Keep monitoring required checks on routine pull requests and re-query branch protection after check-name changes."
    }
}

function Get-PrDeliveryTransitionChecklist {
    param(
        [object]$WorkflowCoverage,
        [bool]$RequiredChecksEnabled,
        [Nullable[bool]]$EnforceAdmins,
        [Nullable[bool]]$ActionsPullRequestCreationAllowed,
        [bool]$BranchProtectionAvailable,
        [bool]$RulesetsAvailable,
        [object]$RoutineMaintenancePrDrillEvidence,
        [object]$RequiredCheckEnforcementEvidence
    )

    if ($null -eq $RoutineMaintenancePrDrillEvidence) {
        $RoutineMaintenancePrDrillEvidence = Get-RoutineMaintenancePrDrillEvidence
    }
    if ($null -eq $RequiredCheckEnforcementEvidence) {
        $RequiredCheckEnforcementEvidence = Get-RequiredCheckEnforcementEvidence
    }
    if ((Get-MemberValue -Object $WorkflowCoverage -Name "status") -eq "not-applicable") {
        return [ordered]@{
            status = "not-applicable"
            readyForRequiredCheckEnforcement = $false
            checklistCount = 0
            readyCount = 0
            blockedCount = 0
            needsLiveValidationCount = 0
            generatedPrDryRunEvidence = $null
            generatedPrWriteEvidence = $null
            directMainMaintenancePolicy = $null
            candidateCheckExercisePlan = $null
            candidateCheckExerciseEvidence = $null
            routineMaintenancePrDrillEvidence = $null
            requiredCheckEnforcementEvidence = $null
            items = @()
        }
    }

    $routinePrDrillPassed = ((Get-MemberValue -Object $RoutineMaintenancePrDrillEvidence -Name "status") -eq "passed")
    $requiredCheckEnforcementPassed = ((Get-MemberValue -Object $RequiredCheckEnforcementEvidence -Name "status") -eq "passed")

    $items = New-Object System.Collections.Generic.List[object]
    $candidateCount = @($RequiredStatusCheckCandidates).Count
    $candidateStatus = if ($candidateCount -gt 0) { "ready" } else { "blocked" }
    $items.Add((New-PrDeliveryChecklistItem `
                -Id "candidate-checks-defined" `
                -Status $candidateStatus `
                -Summary "Candidate required-check names are defined and must stay stable." `
                -Evidence "$candidateCount candidate check(s) are configured." `
                -NextAction "Keep required-check job names unique and unchanged before enabling enforcement."))

    $workflowStatus = if ((Get-MemberValue -Object $WorkflowCoverage -Name "status") -eq "ready") { "ready" } else { "blocked" }
    $items.Add((New-PrDeliveryChecklistItem `
                -Id "candidate-workflow-coverage" `
                -Status $workflowStatus `
                -Summary "Candidate workflows must create checks for pull requests and merge queue runs." `
                -Evidence "$((Get-MemberValue -Object $WorkflowCoverage -Name "workflowCount")) workflow file(s), $((Get-MemberValue -Object $WorkflowCoverage -Name "warningCount")) warning(s)." `
                -NextAction "Fix missing pull_request or merge_group triggers before making any check required."))

    $items.Add((New-PrDeliveryChecklistItem `
                -Id "recent-check-run-proof" `
                -Status "needs-live-validation" `
                -Summary "Each required check must have a current proof path before enforcement." `
                -Evidence "No hosted candidate-check proof is tracked while the repository is local-validation-only." `
                -NextAction "Define a new local or hosted proof path before making any check required."))

    $deliveryStatus = if ($ActionsPullRequestCreationAllowed -eq $false) {
        "blocked"
    } elseif ($routinePrDrillPassed) {
        "ready"
    } elseif ($EnforceAdmins -eq $true) {
        "needs-live-validation"
    } else {
        "needs-live-validation"
    }
    $deliveryEvidence = if ($ActionsPullRequestCreationAllowed -eq $false) {
        "Generated PR delivery is retired while hosted workflows are absent; repository Actions PR creation is not a local-validation requirement."
    } elseif ($null -eq $ActionsPullRequestCreationAllowed) {
        "Generated PR delivery is retired while hosted workflows are absent; Actions PR creation permission evidence is not required."
    } elseif ($routinePrDrillPassed) {
        "Routine maintenance PR #14 merged by rebase after Check generated README, PSScriptAnalyzer, Pester (offline), Markdownlint, Windows setup smoke, and zizmor all passed. The proof branch was deleted after merge."
    } elseif ($EnforceAdmins -eq $true) {
        "Generated PR delivery is retired while hosted workflows are absent; routine maintenance must use local validation or a newly defined PR delivery path."
    } else {
        "Admin enforcement is not confirmed as blocking, but the delivery path still needs a live PR or documented bypass drill."
    }
    $deliveryNextAction = if ($ActionsPullRequestCreationAllowed -eq $false) {
        "Keep generated helpers offline-only and validate generated artifacts locally."
    } elseif ($null -eq $ActionsPullRequestCreationAllowed) {
        "Keep generated helpers offline-only and validate generated artifacts locally."
    } elseif ($routinePrDrillPassed) {
        "Select and enable one required-check enforcement mechanism, then re-query branch protection or rulesets."
    } else {
        "Run a routine maintenance PR merge drill before enabling admin-enforced required-check protection."
    }
    $items.Add((New-PrDeliveryChecklistItem `
                -Id "pr-delivery-or-bypass" `
                -Status $deliveryStatus `
                -Summary "Direct-main delivery must be replaced by PR delivery or a documented bypass before enforcement." `
                -Evidence $deliveryEvidence `
                -NextAction $deliveryNextAction))

    $enforcementStatus = if ($RequiredChecksEnabled) { "ready" } elseif ($BranchProtectionAvailable -or $RulesetsAvailable) { "blocked" } else { "needs-live-validation" }
    $enforcementEvidence = if ($RequiredChecksEnabled -and $requiredCheckEnforcementPassed) {
        "Branch protection requires all six candidate checks, and PR #16 passed every required check before rebase merge."
    } elseif ($RequiredChecksEnabled) {
        "Required-check enforcement is already present."
    } elseif ($BranchProtectionAvailable -or $RulesetsAvailable) {
        "Live settings are readable and currently show no required-check enforcement."
    } else {
        "Live branch-protection and ruleset state must be validated before selecting an enforcement mechanism."
    }
    $enforcementNextAction = if ($RequiredChecksEnabled -and $requiredCheckEnforcementPassed) {
        "Keep monitoring required checks on routine pull requests and re-query branch protection after check-name changes."
    } elseif ($RequiredChecksEnabled) {
        "Keep monitoring required checks on routine pull requests and re-query branch protection after any check-name changes."
    } else {
        "After PR delivery is proven, enable one enforcement mechanism and re-query branch protection/rulesets."
    }
    $items.Add((New-PrDeliveryChecklistItem `
                -Id "enforcement-mechanism" `
                -Status $enforcementStatus `
                -Summary "Choose branch protection or a repository ruleset only after PR delivery is ready." `
                -Evidence $enforcementEvidence `
                -NextAction $enforcementNextAction))

    $blockedCount = @($items | Where-Object { (Get-MemberValue -Object $_ -Name "status") -eq "blocked" }).Count
    $needsLiveValidationCount = @($items | Where-Object { (Get-MemberValue -Object $_ -Name "status") -eq "needs-live-validation" }).Count
    $readyCount = @($items | Where-Object { (Get-MemberValue -Object $_ -Name "status") -eq "ready" }).Count
    $status = if ($blockedCount -gt 0) {
        "blocked"
    } elseif ($needsLiveValidationCount -gt 0) {
        "needs-live-validation"
    } else {
        "ready"
    }

    return [ordered]@{
        status = $status
        readyForRequiredCheckEnforcement = [bool]($status -eq "ready")
        checklistCount = $items.Count
        readyCount = $readyCount
        blockedCount = $blockedCount
        needsLiveValidationCount = $needsLiveValidationCount
        generatedPrDryRunEvidence = Get-GeneratedPrDryRunEvidence
        generatedPrWriteEvidence = Get-GeneratedPrWriteEvidence
        directMainMaintenancePolicy = Get-DirectMainMaintenancePolicy
        candidateCheckExercisePlan = Get-CandidateCheckExercisePlan
        candidateCheckExerciseEvidence = Get-CandidateCheckExerciseEvidence
        routineMaintenancePrDrillEvidence = $RoutineMaintenancePrDrillEvidence
        requiredCheckEnforcementEvidence = $RequiredCheckEnforcementEvidence
        items = @($items.ToArray())
    }
}

function Get-ReviewPolicyPosture {
    param(
        [bool]$BranchProtectionAvailable,
        [object]$RequiredPullRequestReviews,
        [object]$RequiredCodeOwnerReviews,
        [object]$RequiredStatusChecks,
        [object]$RequiredCheckReadiness,
        [object[]]$LocalFiles = @(),
        [string]$BranchProtectionUnavailableReason
    )

    if (-not $BranchProtectionAvailable) {
        return [ordered]@{
            available = $false
            status = "unavailable"
            recommendation = "verify-branch-protection-review-policy"
            branchProtectionUnavailableReason = if ([string]::IsNullOrWhiteSpace($BranchProtectionUnavailableReason)) { "branch protection evidence was not supplied" } else { $BranchProtectionUnavailableReason }
            pullRequestReviewsRequired = $null
            codeOwnerReviewsRequired = $null
            requiredStatusChecksEnabled = $null
            codeownersFilePresent = [bool](@($LocalFiles | Where-Object { [string](Get-MemberValue -Object $_ -Name "path") -eq ".github/CODEOWNERS" -and (Get-MemberValue -Object $_ -Name "exists") -eq $true }).Count -gt 0)
            routinePrDeliveryProven = $false
            requiredCheckEnforcementProven = $false
            directMainBypassApproved = $false
            reviewerModel = "unverified"
            scorecardCodeReviewClassification = "needs-review"
            documentationPath = "decision:review-policy-posture"
            evidence = "Branch-protection review settings were unavailable."
            nextAction = "Re-query branch protection before changing pull request review or code-owner review requirements."
        }
    }

    $pullRequestReviewsRequired = [bool]($RequiredPullRequestReviews -eq $true)
    $codeOwnerReviewsRequired = [bool]($RequiredCodeOwnerReviews -eq $true)
    $requiredStatusChecksEnabled = [bool]($RequiredStatusChecks -eq $true)
    $transition = Get-MemberValue -Object $RequiredCheckReadiness -Name "prDeliveryTransition"
    $routinePrDeliveryProven = [string](Get-NestedMemberValue -Object $transition -Path "routineMaintenancePrDrillEvidence.status") -eq "passed"
    $requiredCheckEnforcementProven = [string](Get-NestedMemberValue -Object $transition -Path "requiredCheckEnforcementEvidence.status") -eq "passed"
    $directMainBypassApproved = [bool](Get-NestedMemberValue -Object $transition -Path "directMainMaintenancePolicy.allowed")
    $codeownersFilePresent = [bool](@($LocalFiles | Where-Object { [string](Get-MemberValue -Object $_ -Name "path") -eq ".github/CODEOWNERS" -and (Get-MemberValue -Object $_ -Name "exists") -eq $true }).Count -gt 0)

    $status = if ($pullRequestReviewsRequired -and $codeOwnerReviewsRequired) {
        "enforced-pr-and-code-owner-review"
    } elseif ($pullRequestReviewsRequired) {
        "enforced-pr-review"
    } else {
        "warning-only-single-maintainer"
    }

    $recommendation = if ($status -eq "enforced-pr-and-code-owner-review") {
        "monitor-review-enforcement"
    } elseif ($status -eq "enforced-pr-review") {
        "decide-code-owner-review-requirement"
    } else {
        "keep-warning-only-until-reviewer-model"
    }

    $evidence = if ($status -eq "warning-only-single-maintainer") {
        "Branch protection requires status checks and PR #16 proved required-check PR delivery, but branch protection does not require pull request or code-owner reviews. CODEOWNERS is present for routing; review enforcement should wait for an independent reviewer or team model."
    } elseif ($status -eq "enforced-pr-review") {
        "Branch protection requires pull request reviews but does not require code-owner reviews."
    } else {
        "Branch protection requires pull request reviews and code-owner reviews."
    }

    $nextAction = if ($status -eq "warning-only-single-maintainer") {
        "Define an independent reviewer or team model before requiring pull request reviews or code-owner reviews."
    } elseif ($status -eq "enforced-pr-review") {
        "Decide whether CODEOWNERS review should also be required after validating reviewer availability."
    } else {
        "Monitor review enforcement and update CODEOWNERS before adding new public-contract paths."
    }

    return [ordered]@{
        available = $true
        status = $status
        recommendation = $recommendation
        branchProtectionUnavailableReason = $null
        pullRequestReviewsRequired = $pullRequestReviewsRequired
        codeOwnerReviewsRequired = $codeOwnerReviewsRequired
        requiredStatusChecksEnabled = $requiredStatusChecksEnabled
        codeownersFilePresent = $codeownersFilePresent
        routinePrDeliveryProven = $routinePrDeliveryProven
        requiredCheckEnforcementProven = $requiredCheckEnforcementProven
        directMainBypassApproved = $directMainBypassApproved
        reviewerModel = "single-maintainer-profile-repo"
        scorecardCodeReviewClassification = "external-gated-reviewer-model"
        documentationPath = "decision:review-policy-posture"
        evidence = $evidence
        nextAction = $nextAction
    }
}

function Test-RepositoryCommunityBaseline {
    param(
        [object]$Repository,
        [object]$CommunityProfile,
        [object]$BranchProtection,
        [object[]]$Rulesets = @(),
        [object]$ActionsWorkflowPermissions,
        [object]$Languages,
        [object[]]$LocalFiles = @(),
        [object]$CodeScanningLocalEvidence,
        [object[]]$ScorecardAlerts,
        [object]$ScorecardScoreResult,
        [string]$DependabotSecurityUpdatesStatus,
        [string]$DependabotSecurityUpdatesUnavailableReason,
        [string]$RepositoryUnavailableReason,
        [string]$CommunityUnavailableReason,
        [string]$BranchProtectionUnavailableReason,
        [string]$RulesetsUnavailableReason,
        [string]$ActionsWorkflowPermissionsUnavailableReason,
        [string]$LanguagesUnavailableReason,
        [string]$ScorecardAlertsUnavailableReason,
        [string]$ScorecardScoreUnavailableReason
    )

    $repoWarnings = New-Object System.Collections.Generic.List[string]
    $communityWarnings = New-Object System.Collections.Generic.List[string]
    $communityErrors = New-Object System.Collections.Generic.List[string]
    $communityInfo = New-Object System.Collections.Generic.List[string]

    $repoAvailable = ($null -ne $Repository -and [string]::IsNullOrWhiteSpace($RepositoryUnavailableReason))
    $communityAvailable = ($null -ne $CommunityProfile -and [string]::IsNullOrWhiteSpace($CommunityUnavailableReason))
    $branchProtectionAvailable = ($null -ne $BranchProtection -and [string]::IsNullOrWhiteSpace($BranchProtectionUnavailableReason))
    $rulesetsAvailable = ($null -ne $Rulesets -and [string]::IsNullOrWhiteSpace($RulesetsUnavailableReason))
    $actionsWorkflowPermissionsAvailable = ($null -ne $ActionsWorkflowPermissions -and [string]::IsNullOrWhiteSpace($ActionsWorkflowPermissionsUnavailableReason))
    $languagesAvailable = ($null -ne $Languages -and [string]::IsNullOrWhiteSpace($LanguagesUnavailableReason))
    if ($null -eq $CodeScanningLocalEvidence) {
        $CodeScanningLocalEvidence = Get-CodeScanningLocalEvidence
    }
    $scorecardAlertPosture = Get-ScorecardAlertPosture -Alerts $ScorecardAlerts -UnavailableReason $ScorecardAlertsUnavailableReason
    $scorecardScore = Get-ScorecardScoreSnapshot -ScorecardScoreResult $ScorecardScoreResult -UnavailableReason $ScorecardScoreUnavailableReason

    if (-not $repoAvailable -and -not [string]::IsNullOrWhiteSpace($RepositoryUnavailableReason)) {
        $repoWarnings.Add("Repository settings unavailable: $RepositoryUnavailableReason.")
    }
    if (-not $communityAvailable -and -not [string]::IsNullOrWhiteSpace($CommunityUnavailableReason)) {
        $communityWarnings.Add("GitHub community profile unavailable: $CommunityUnavailableReason.")
    }
    if (-not $actionsWorkflowPermissionsAvailable -and -not [string]::IsNullOrWhiteSpace($ActionsWorkflowPermissionsUnavailableReason)) {
        $repoWarnings.Add("GitHub Actions workflow permissions unavailable: $ActionsWorkflowPermissionsUnavailableReason.")
    }
    if (-not [bool](Get-MemberValue -Object $scorecardAlertPosture -Name "available")) {
        $repoWarnings.Add("Scorecard code-scanning alerts unavailable: $((Get-MemberValue -Object $scorecardAlertPosture -Name "unavailableReason")).")
    }

    $secretScanning = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.secret_scanning.status"
    $secretScanningPushProtection = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.secret_scanning_push_protection.status"
    $secretScanningNonProviderPatterns = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.secret_scanning_non_provider_patterns.status"
    $secretScanningValidityChecks = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.secret_scanning_validity_checks.status"
    $repositoryDependabotSecurityUpdates = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.dependabot_security_updates.status"
    $dependabotSecurityUpdates = if (-not [string]::IsNullOrWhiteSpace([string]$repositoryDependabotSecurityUpdates)) {
        $repositoryDependabotSecurityUpdates
    } else {
        $DependabotSecurityUpdatesStatus
    }
    $dependabotSecurityPosture = Get-DependabotSecurityPosture `
        -DependabotSecurityUpdates $dependabotSecurityUpdates `
        -UnavailableReason $DependabotSecurityUpdatesUnavailableReason

    if ($repoAvailable) {
        if ([string]::IsNullOrWhiteSpace([string]$secretScanning)) {
            $repoWarnings.Add("Secret scanning status is unavailable.")
        } elseif ($secretScanning -ne "enabled") {
            $repoWarnings.Add("Secret scanning is not enabled.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$secretScanningPushProtection)) {
            $repoWarnings.Add("Secret scanning push protection status is unavailable.")
        } elseif ($secretScanningPushProtection -ne "enabled") {
            $repoWarnings.Add("Secret scanning push protection is not enabled.")
        }
        if ((Get-MemberValue -Object $dependabotSecurityPosture -Name "status") -eq "disabled") {
            $repoWarnings.Add("Dependabot security updates are not enabled.")
        } elseif ((Get-MemberValue -Object $dependabotSecurityPosture -Name "status") -eq "unavailable") {
            $repoWarnings.Add("Dependabot security update status is unavailable.")
        }
    }

    $requiredStatusChecks = $null
    $requiredPullRequestReviews = $null
    $requiredCodeOwnerReviews = $null
    $requiredConversationResolution = $null
    $enforceAdmins = $null
    $allowForcePushes = $null
    $allowDeletions = $null
    if ($branchProtectionAvailable) {
        $requiredStatusChecks = $null -ne (Get-MemberValue -Object $BranchProtection -Name "required_status_checks")
        $pullRequestReviewObject = Get-MemberValue -Object $BranchProtection -Name "required_pull_request_reviews"
        $requiredPullRequestReviews = $null -ne $pullRequestReviewObject
        $requiredCodeOwnerReviews = if ($pullRequestReviewObject) { [bool](Get-MemberValue -Object $pullRequestReviewObject -Name "require_code_owner_reviews") } else { $false }
        $requiredConversationResolution = [bool](Get-NestedMemberValue -Object $BranchProtection -Path "required_conversation_resolution.enabled")
        $enforceAdmins = [bool](Get-NestedMemberValue -Object $BranchProtection -Path "enforce_admins.enabled")
        $allowForcePushes = [bool](Get-NestedMemberValue -Object $BranchProtection -Path "allow_force_pushes.enabled")
        $allowDeletions = [bool](Get-NestedMemberValue -Object $BranchProtection -Path "allow_deletions.enabled")

        if (-not $requiredStatusChecks) {
            $repoWarnings.Add("Branch protection does not require status checks.")
        }
        if (-not $requiredPullRequestReviews) {
            $repoWarnings.Add("Branch protection does not require pull request reviews.")
        }
        if (-not $requiredCodeOwnerReviews) {
            $repoWarnings.Add("Branch protection does not require code owner reviews.")
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($BranchProtectionUnavailableReason)) {
        $repoWarnings.Add("Branch protection unavailable: $BranchProtectionUnavailableReason.")
    }

    $rulesetCount = if ($rulesetsAvailable) { @($Rulesets).Count } else { 0 }
    if ($rulesetsAvailable -and $rulesetCount -eq 0) {
        $repoWarnings.Add("No repository rulesets are configured.")
    } elseif (-not [string]::IsNullOrWhiteSpace($RulesetsUnavailableReason)) {
        $repoWarnings.Add("Repository rulesets unavailable: $RulesetsUnavailableReason.")
    }

    $defaultWorkflowPermissions = $null
    $canApprovePullRequestReviews = $null
    $generatedPrCreationAllowed = $null
    if ($actionsWorkflowPermissionsAvailable) {
        $defaultWorkflowPermissions = [string](Get-MemberValue -Object $ActionsWorkflowPermissions -Name "default_workflow_permissions")
        $canApprovePullRequestReviews = Get-NullableBool (Get-MemberValue -Object $ActionsWorkflowPermissions -Name "can_approve_pull_request_reviews")
        $generatedPrCreationAllowed = [bool]($canApprovePullRequestReviews -eq $true)
        if (-not $generatedPrCreationAllowed -and @($RequiredStatusCheckCandidates).Count -gt 0) {
            $repoWarnings.Add("GitHub Actions workflow permissions do not allow GITHUB_TOKEN to create pull requests.")
        }
    }
    $generatedPrCredentialDecision = Get-GeneratedPrCredentialDecision -ActionsPullRequestCreationAllowed $generatedPrCreationAllowed

    $requiredCheckReadiness = Get-RequiredCheckReadiness `
        -BranchProtectionAvailable $branchProtectionAvailable `
        -RulesetsAvailable $rulesetsAvailable `
        -RequiredStatusChecks $requiredStatusChecks `
        -EnforceAdmins $enforceAdmins `
        -ActionsPullRequestCreationAllowed $generatedPrCreationAllowed `
        -RulesetCount $rulesetCount `
        -BranchProtectionUnavailableReason $BranchProtectionUnavailableReason `
        -RulesetsUnavailableReason $RulesetsUnavailableReason

    $reviewPolicyPosture = Get-ReviewPolicyPosture `
        -BranchProtectionAvailable $branchProtectionAvailable `
        -RequiredPullRequestReviews $requiredPullRequestReviews `
        -RequiredCodeOwnerReviews $requiredCodeOwnerReviews `
        -RequiredStatusChecks $requiredStatusChecks `
        -RequiredCheckReadiness $requiredCheckReadiness `
        -LocalFiles $LocalFiles `
        -BranchProtectionUnavailableReason $BranchProtectionUnavailableReason

    $languageNames = @()
    if ($languagesAvailable) {
        $languageNames = @($Languages.PSObject.Properties.Name | Sort-Object)
    }
    $detectedCodeQlSupportedLanguages = @($languageNames | Where-Object { $CodeQlSupportedLanguages -contains $_ } | Sort-Object)
    $hasCodeqlSupportedLanguage = $detectedCodeQlSupportedLanguages.Count -gt 0
    $powerShellOnly = ($languageNames.Count -eq 1 -and $languageNames[0] -eq "PowerShell")
    $codeQlWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "codeqlWorkflowPresent")
    $sarifUploadWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "sarifUploadWorkflowPresent")
    $scorecardSarifUploadPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "scorecardSarifUploadPresent")
    $psScriptAnalyzerWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "psScriptAnalyzerWorkflowPresent")
    $actionlintWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "actionlintWorkflowPresent")
    $zizmorWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "zizmorWorkflowPresent")
    $localValidationScriptPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "localValidationScriptPresent")
    $psScriptAnalyzerLocalPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "psScriptAnalyzerLocalPresent")
    $pesterLocalPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "pesterLocalPresent")
    $markdownlintLocalPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "markdownlintLocalPresent")
    $zizmorLocalConfigPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "zizmorLocalConfigPresent")
    $codeScanningStatus = if ($languagesAvailable -and -not $hasCodeqlSupportedLanguage) {
        "not-applicable"
    } elseif ($languagesAvailable) {
        "needs-live-validation"
    } else {
        "unavailable"
    }
    $codeScanningRecommendation = if ($codeScanningStatus -eq "not-applicable") {
        if ($powerShellOnly) {
            "not-applicable-powershell-only"
        } else {
            "no-codeql-supported-languages-detected"
        }
    } elseif ($codeScanningStatus -eq "needs-live-validation") {
        "verify-code-scanning-for-supported-languages"
    } else {
        $LanguagesUnavailableReason
    }
    $codeScanningReason = if ($codeScanningStatus -eq "not-applicable") {
        "Detected repository languages do not include a current CodeQL-supported source language."
    } elseif ($codeScanningStatus -eq "needs-live-validation") {
        "Detected repository languages include CodeQL-supported source language(s)."
    } else {
        $LanguagesUnavailableReason
    }
    $localCodeScanningControls = New-Object System.Collections.Generic.List[string]
    if ($localValidationScriptPresent) { $localCodeScanningControls.Add("local-validation-bootstrap") }
    if ($psScriptAnalyzerLocalPresent) { $localCodeScanningControls.Add("psscriptanalyzer") }
    if ($pesterLocalPresent) { $localCodeScanningControls.Add("pester") }
    if ($markdownlintLocalPresent) { $localCodeScanningControls.Add("markdownlint") }
    if ($zizmorLocalConfigPresent) { $localCodeScanningControls.Add("zizmor-config") }

    $hostedCodeScanningControls = New-Object System.Collections.Generic.List[string]
    if ($secretScanning -eq "enabled") { $hostedCodeScanningControls.Add("secret-scanning") }
    if ($secretScanningPushProtection -eq "enabled") { $hostedCodeScanningControls.Add("secret-scanning-push-protection") }
    if ($dependabotSecurityUpdates -eq "enabled") { $hostedCodeScanningControls.Add("dependabot-security-updates") }
    if ($psScriptAnalyzerWorkflowPresent) { $hostedCodeScanningControls.Add("psscriptanalyzer-workflow") }
    if ($actionlintWorkflowPresent) { $hostedCodeScanningControls.Add("actionlint-workflow") }
    if ($zizmorWorkflowPresent) { $hostedCodeScanningControls.Add("zizmor-workflow") }
    if ($scorecardSarifUploadPresent) { $hostedCodeScanningControls.Add("openssf-scorecard-sarif") }
    if ($sarifUploadWorkflowPresent) { $hostedCodeScanningControls.Add("sarif-upload-workflow") }
    if ($codeQlWorkflowPresent) { $hostedCodeScanningControls.Add("codeql-workflow") }

    $activeCodeScanningControls = @(@(
        @($localCodeScanningControls.ToArray())
        @($hostedCodeScanningControls.ToArray())
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    if ($languagesAvailable -and $hasCodeqlSupportedLanguage -and -not $codeQlWorkflowPresent) {
        $repoWarnings.Add("CodeQL-supported languages detected; verify code scanning default setup, add an intentional CodeQL workflow, or document another SARIF-producing analyzer.")
    }

    foreach ($file in @($LocalFiles)) {
        if ((Get-MemberValue -Object $file -Name "required") -eq $true -and (Get-MemberValue -Object $file -Name "exists") -ne $true) {
            $communityErrors.Add("Required community file is missing: $((Get-MemberValue -Object $file -Name "path")).")
        }
    }

    $communityFiles = Get-MemberValue -Object $CommunityProfile -Name "files"
    $communityReadme = $null -ne (Get-MemberValue -Object $communityFiles -Name "readme")
    $communityLicense = $null -ne (Get-MemberValue -Object $communityFiles -Name "license")
    $communityIssueTemplate = $null -ne (Get-MemberValue -Object $communityFiles -Name "issue_template")
    $communityPullRequestTemplate = $null -ne (Get-MemberValue -Object $communityFiles -Name "pull_request_template")
    $communityContributing = $null -ne (Get-MemberValue -Object $communityFiles -Name "contributing")
    $communityCodeOfConduct = $null -ne (Get-MemberValue -Object $communityFiles -Name "code_of_conduct")

    $localIssueForms = @($LocalFiles | Where-Object {
        ([string](Get-MemberValue -Object $_ -Name "path")).StartsWith(".github/ISSUE_TEMPLATE/", [StringComparison]::OrdinalIgnoreCase) -and
            (Get-MemberValue -Object $_ -Name "exists") -eq $true
    }).Count
    # The community-profile API only detects legacy issue *templates*, not issue
    # *forms* (.github/ISSUE_TEMPLATE/*.yml). When the provider reports no issue
    # template but local issue forms exist, treat it as a provider gap (info), not
    # a warning; genuinely missing local intake stays a warning/fatal elsewhere.
    $issueTemplateProviderState = if (-not $communityAvailable) {
        "unavailable"
    } elseif ($communityIssueTemplate) {
        "detected"
    } elseif ($localIssueForms -gt 0) {
        "provider-gap-local-forms-present"
    } else {
        "missing"
    }
    if ($communityAvailable) {
        if ($issueTemplateProviderState -eq "provider-gap-local-forms-present") {
            $communityInfo.Add("GitHub community profile does not detect issue-template metadata, but $localIssueForms local issue form(s) are present; the provider does not surface issue forms (.github/ISSUE_TEMPLATE/*.yml).")
        } elseif ($issueTemplateProviderState -eq "missing") {
            $communityWarnings.Add("No issue templates or local issue forms detected; public reporters have no structured intake.")
        }
        if (-not $communityContributing) {
            $communityWarnings.Add("GitHub community profile does not report contributing guidelines.")
        }
        if (-not $communityCodeOfConduct) {
            $communityWarnings.Add("GitHub community profile does not report a code of conduct.")
        }
    }

    $repositorySettings = [ordered]@{
        available = [bool]$repoAvailable
        unavailableReason = if ($repoAvailable) { $null } else { $RepositoryUnavailableReason }
        repository = "$Owner/$Owner"
        visibility = if ($repoAvailable) { [string](Get-MemberValue -Object $Repository -Name "visibility") } else { $null }
        features = [ordered]@{
            hasIssues = Get-NullableBool (Get-MemberValue -Object $Repository -Name "has_issues")
            hasDiscussions = Get-NullableBool (Get-MemberValue -Object $Repository -Name "has_discussions")
            hasProjects = Get-NullableBool (Get-MemberValue -Object $Repository -Name "has_projects")
            hasWiki = Get-NullableBool (Get-MemberValue -Object $Repository -Name "has_wiki")
            allowForking = Get-NullableBool (Get-MemberValue -Object $Repository -Name "allow_forking")
            deleteBranchOnMerge = Get-NullableBool (Get-MemberValue -Object $Repository -Name "delete_branch_on_merge")
            webCommitSignoffRequired = Get-NullableBool (Get-MemberValue -Object $Repository -Name "web_commit_signoff_required")
        }
        security = [ordered]@{
            secretScanning = $secretScanning
            secretScanningPushProtection = $secretScanningPushProtection
            secretScanningNonProviderPatterns = $secretScanningNonProviderPatterns
            secretScanningValidityChecks = $secretScanningValidityChecks
            dependabotSecurityUpdates = $dependabotSecurityUpdates
            dependabotSecurityPosture = $dependabotSecurityPosture
            scorecardScore = $scorecardScore
            codeScanning = [ordered]@{
                status = $codeScanningStatus
                recommendation = $codeScanningRecommendation
                reason = $codeScanningReason
                languagesInspected = @($languageNames)
                codeqlSupportedLanguages = @($detectedCodeQlSupportedLanguages)
                codeqlSupportedLanguageDetected = [bool]$hasCodeqlSupportedLanguage
                codeqlWorkflowPresent = $codeQlWorkflowPresent
                sarifUploadWorkflowPresent = $sarifUploadWorkflowPresent
                scorecardSarifUploadPresent = $scorecardSarifUploadPresent
                localControls = @($localCodeScanningControls.ToArray())
                hostedControls = @($hostedCodeScanningControls.ToArray())
                activeControls = @($activeCodeScanningControls)
                scorecardAlertPosture = $scorecardAlertPosture
            }
        }
        branchProtection = [ordered]@{
            available = [bool]$branchProtectionAvailable
            unavailableReason = if ($branchProtectionAvailable) { $null } else { $BranchProtectionUnavailableReason }
            requiredStatusChecks = Get-NullableBool $requiredStatusChecks
            requiredPullRequestReviews = Get-NullableBool $requiredPullRequestReviews
            requiredCodeOwnerReviews = Get-NullableBool $requiredCodeOwnerReviews
            requiredConversationResolution = Get-NullableBool $requiredConversationResolution
            enforceAdmins = Get-NullableBool $enforceAdmins
            allowForcePushes = Get-NullableBool $allowForcePushes
            allowDeletions = Get-NullableBool $allowDeletions
        }
        rulesets = [ordered]@{
            available = [bool]$rulesetsAvailable
            unavailableReason = if ($rulesetsAvailable) { $null } else { $RulesetsUnavailableReason }
            count = [int]$rulesetCount
        }
        actionsWorkflowPermissions = [ordered]@{
            available = [bool]$actionsWorkflowPermissionsAvailable
            unavailableReason = if ($actionsWorkflowPermissionsAvailable) { $null } else { $ActionsWorkflowPermissionsUnavailableReason }
            defaultWorkflowPermissions = if ($actionsWorkflowPermissionsAvailable) { $defaultWorkflowPermissions } else { $null }
            canApprovePullRequestReviews = $canApprovePullRequestReviews
            generatedPrCreationAllowed = if ($actionsWorkflowPermissionsAvailable) { $generatedPrCreationAllowed } else { $null }
            recommendation = "local-validation-only"
            generatedPrCredentialDecision = $generatedPrCredentialDecision
        }
        requiredCheckReadiness = $requiredCheckReadiness
        reviewPolicyPosture = $reviewPolicyPosture
        warningCount = $repoWarnings.Count
        warnings = $repoWarnings.ToArray()
    }

    $communityHealth = [ordered]@{
        available = [bool]$communityAvailable
        unavailableReason = if ($communityAvailable) { $null } else { $CommunityUnavailableReason }
        healthPercentage = if ($communityAvailable) { [int](Get-MemberValue -Object $CommunityProfile -Name "health_percentage") } else { $null }
        providerFiles = [ordered]@{
            readme = Get-NullableBool $communityReadme
            license = Get-NullableBool $communityLicense
            issueTemplate = Get-NullableBool $communityIssueTemplate
            pullRequestTemplate = Get-NullableBool $communityPullRequestTemplate
            contributing = Get-NullableBool $communityContributing
            codeOfConduct = Get-NullableBool $communityCodeOfConduct
        }
        localFiles = @($LocalFiles)
        localIssueFormCount = [int]$localIssueForms
        issueTemplateProviderState = $issueTemplateProviderState
        localRequiredMissingCount = $communityErrors.Count
        warningCount = $communityWarnings.Count
        warnings = $communityWarnings.ToArray()
        infoCount = $communityInfo.Count
        info = $communityInfo.ToArray()
        fatalCount = $communityErrors.Count
        errors = $communityErrors.ToArray()
    }

    return [ordered]@{
        repositorySettings = $repositorySettings
        communityHealth = $communityHealth
    }
}

function Get-RepositoryCommunityBaseline {
    $localFiles = @(Get-CommunityLocalFileStatus)
    if ($Offline) {
        return Test-RepositoryCommunityBaseline `
            -LocalFiles $localFiles `
            -RepositoryUnavailableReason "offline" `
            -CommunityUnavailableReason "offline" `
            -BranchProtectionUnavailableReason "offline" `
            -RulesetsUnavailableReason "offline" `
            -ActionsWorkflowPermissionsUnavailableReason "offline" `
            -LanguagesUnavailableReason "offline" `
            -ScorecardAlertsUnavailableReason "offline" `
            -ScorecardScoreUnavailableReason "offline"
    }
    if (-not (Test-GitHubCliAuthenticated)) {
        return Test-RepositoryCommunityBaseline `
            -LocalFiles $localFiles `
            -RepositoryUnavailableReason "gh authentication unavailable" `
            -CommunityUnavailableReason "gh authentication unavailable" `
            -BranchProtectionUnavailableReason "gh authentication unavailable" `
            -RulesetsUnavailableReason "gh authentication unavailable" `
            -ActionsWorkflowPermissionsUnavailableReason "gh authentication unavailable" `
            -LanguagesUnavailableReason "gh authentication unavailable" `
            -ScorecardAlertsUnavailableReason "gh authentication unavailable" `
            -ScorecardScoreUnavailableReason "gh authentication unavailable"
    }

    $repositoryResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner"
    $communityResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/community/profile"
    $branchProtectionResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/branches/main/protection"
    $rulesetsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/rulesets"
    $actionsWorkflowPermissionsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/actions/permissions/workflow"
    $languagesResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/languages"
    $scorecardAlertsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/code-scanning/alerts?tool_name=Scorecard&state=open&per_page=100"
    $scorecardScoreResult = Invoke-RestJsonSafe -Uri (Get-ScorecardScoreApiUrl)
    $dependabotSecurityUpdatesResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/automated-security-fixes"

    $repositoryValue = if ($repositoryResult["ok"]) { $repositoryResult["value"] } else { $null }
    $communityValue = if ($communityResult["ok"]) { $communityResult["value"] } else { $null }
    $branchProtectionValue = if ($branchProtectionResult["ok"]) { $branchProtectionResult["value"] } else { $null }
    $rulesetsValue = if ($rulesetsResult["ok"]) { @($rulesetsResult["value"]) } else { @() }
    $actionsWorkflowPermissionsValue = if ($actionsWorkflowPermissionsResult["ok"]) { $actionsWorkflowPermissionsResult["value"] } else { $null }
    $languagesValue = if ($languagesResult["ok"]) { $languagesResult["value"] } else { $null }
    $scorecardAlertsValue = if ($scorecardAlertsResult["ok"]) { @($scorecardAlertsResult["value"]) } else { $null }
    $scorecardScoreValue = if ($scorecardScoreResult["ok"]) { $scorecardScoreResult["value"] } else { $null }
    $dependabotSecurityUpdatesValue = if ($dependabotSecurityUpdatesResult["ok"]) {
        $automatedFixesEnabled = Get-MemberValue -Object $dependabotSecurityUpdatesResult["value"] -Name "enabled"
        if ($null -eq $automatedFixesEnabled) {
            $null
        } elseif ([bool]$automatedFixesEnabled) {
            "enabled"
        } else {
            "disabled"
        }
    } else {
        $null
    }

    return Test-RepositoryCommunityBaseline `
        -Repository $repositoryValue `
        -CommunityProfile $communityValue `
        -BranchProtection $branchProtectionValue `
        -Rulesets $rulesetsValue `
        -ActionsWorkflowPermissions $actionsWorkflowPermissionsValue `
        -Languages $languagesValue `
        -LocalFiles $localFiles `
        -ScorecardAlerts $scorecardAlertsValue `
        -ScorecardScoreResult $scorecardScoreValue `
        -DependabotSecurityUpdatesStatus $dependabotSecurityUpdatesValue `
        -DependabotSecurityUpdatesUnavailableReason $(if ($dependabotSecurityUpdatesResult["ok"]) { $null } else { $dependabotSecurityUpdatesResult["error"] }) `
        -RepositoryUnavailableReason $(if ($repositoryResult["ok"]) { $null } else { $repositoryResult["error"] }) `
        -CommunityUnavailableReason $(if ($communityResult["ok"]) { $null } else { $communityResult["error"] }) `
        -BranchProtectionUnavailableReason $(if ($branchProtectionResult["ok"]) { $null } else { $branchProtectionResult["error"] }) `
        -RulesetsUnavailableReason $(if ($rulesetsResult["ok"]) { $null } else { $rulesetsResult["error"] }) `
        -ActionsWorkflowPermissionsUnavailableReason $(if ($actionsWorkflowPermissionsResult["ok"]) { $null } else { $actionsWorkflowPermissionsResult["error"] }) `
        -LanguagesUnavailableReason $(if ($languagesResult["ok"]) { $null } else { $languagesResult["error"] }) `
        -ScorecardAlertsUnavailableReason $(if ($scorecardAlertsResult["ok"]) { $null } else { $scorecardAlertsResult["error"] }) `
        -ScorecardScoreUnavailableReason $(if ($scorecardScoreResult["ok"]) { $null } else { $scorecardScoreResult["error"] })
}

function ConvertTo-ComparableJson {
    param([object]$Value)

    if ($null -eq $Value) {
        return "null"
    }
    return ConvertTo-Json -InputObject $Value -Depth 20 -Compress
}

function ConvertFrom-JsonElementValue {
    param([System.Text.Json.JsonElement]$Element)

    switch ($Element.ValueKind) {
        ([System.Text.Json.JsonValueKind]::Object) {
            $hash = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) {
                $hash[$property.Name] = (ConvertFrom-JsonElementValue -Element $property.Value)
            }
            return $hash
        }
        ([System.Text.Json.JsonValueKind]::Array) {
            $items = New-Object System.Collections.Generic.List[object]
            foreach ($item in $Element.EnumerateArray()) {
                $items.Add((ConvertFrom-JsonElementValue -Element $item))
            }
            $wrapper = [pscustomobject]@{
                __JsonArray = $true
                Items = $null
            }
            $wrapper.Items = $items
            return $wrapper
        }
        ([System.Text.Json.JsonValueKind]::String) {
            return $Element.GetString()
        }
        ([System.Text.Json.JsonValueKind]::Number) {
            $integerValue = [int64]0
            if ($Element.TryGetInt64([ref]$integerValue)) {
                return $integerValue
            }
            return $Element.GetDouble()
        }
        ([System.Text.Json.JsonValueKind]::True) {
            return $true
        }
        ([System.Text.Json.JsonValueKind]::False) {
            return $false
        }
        default {
            return $null
        }
    }
}

function ConvertFrom-JsonPreservingArrays {
    param([string]$Json)

    $document = [System.Text.Json.JsonDocument]::Parse($Json)
    try {
        return ConvertFrom-JsonElementValue -Element $document.RootElement
    } finally {
        $document.Dispose()
    }
}

function ConvertTo-ProjectsSyncComparableJson {
    param([string]$Json)

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return ""
    }

    try {
        $payload = ConvertFrom-JsonPreservingArrays -Json $Json
        $generatedAt = Get-MemberValue -Object $payload -Name "generatedAt"
        if (-not [string]::IsNullOrWhiteSpace([string]$generatedAt)) {
            $parsedGeneratedAt = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse([string]$generatedAt, [ref]$parsedGeneratedAt)) {
                Set-MemberValue -Object $payload -Name "generatedAt" -Value ($parsedGeneratedAt.ToString("o"))
            }
        }
        $provenance = Get-MemberValue -Object $payload -Name "provenance"
        if ($provenance) {
            Set-MemberValue -Object $provenance -Name "metadataSnapshotAt" -Value $null
            Set-MemberValue -Object $provenance -Name "sourceCommit" -Value $null
        }
        $projects = @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name "projects"))
        foreach ($project in $projects) {
            Set-MemberValue -Object $project -Name "pushedAt" -Value $null
        }
        return ConvertTo-ComparableJson $payload
    } catch {
        return (($Json -replace "`r`n", "`n").TrimEnd())
    }
}

function Get-ObjectPropertyNames {
    param([object]$Object)

    if ($null -eq $Object) {
        return @()
    }
    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys | ForEach-Object { [string]$_ })
    }
    return @($Object.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty', 'Property') } | ForEach-Object { $_.Name })
}

function Test-JsonArrayWrapper {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    $marker = $Value.PSObject.Properties['__JsonArray']
    return [bool]($marker -and $marker.Value -eq $true -and $Value.PSObject.Properties['Items'])
}

function Get-JsonArrayItems {
    param([object]$Value)

    if ($null -eq $Value) {
        return
    }
    if (Test-JsonArrayWrapper $Value) {
        foreach ($item in $Value.Items) {
            $item
        }
        return
    }
    foreach ($item in @($Value)) {
        $item
    }
}

function ConvertTo-JsonSchemaValidationValue {
    param(
        [object]$Value,
        [ref]$Result
    )

    if ($null -eq $Value) {
        $Result.Value = $null
        return
    }

    if (Test-JsonArrayWrapper $Value) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value.Items) {
            $convertedItem = $null
            ConvertTo-JsonSchemaValidationValue -Value $item -Result ([ref]$convertedItem)
            $items.Add($convertedItem)
        }
        $Result.Value = [object[]]$items.ToArray()
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $hash = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $convertedValue = $null
            ConvertTo-JsonSchemaValidationValue -Value $Value[$key] -Result ([ref]$convertedValue)
            $hash[[string]$key] = $convertedValue
        }
        $Result.Value = $hash
        return
    }

    if ($Value -is [string] -or $Value -is [datetime] -or $Value -is [datetimeoffset] -or
        $Value -is [bool] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or
        $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        $Result.Value = $Value
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $convertedItem = $null
            ConvertTo-JsonSchemaValidationValue -Value $item -Result ([ref]$convertedItem)
            $items.Add($convertedItem)
        }
        $Result.Value = [object[]]$items.ToArray()
        return
    }

    $propertyNames = @(Get-ObjectPropertyNames $Value)
    if ($propertyNames.Count -gt 0) {
        $hash = [ordered]@{}
        foreach ($propertyName in $propertyNames) {
            $convertedValue = $null
            ConvertTo-JsonSchemaValidationValue -Value (Get-MemberValue -Object $Value -Name $propertyName) -Result ([ref]$convertedValue)
            $hash[$propertyName] = $convertedValue
        }
        $Result.Value = $hash
        return
    }

    $Result.Value = $Value
}

$script:SupportedSchemaKeywords = @(
    '$schema', '$id', '$ref', '$defs', 'definitions',
    'title', 'description',
    'type', 'const', 'enum', 'format', 'pattern',
    'minimum', 'minLength', 'minItems', 'items',
    'required', 'properties', 'additionalProperties'
)

function Test-SchemaKeywordCoverage {
    param(
        [object]$Schema,
        [string]$Path = '$',
        [object]$RootSchema = $null
    )

    if ($null -eq $RootSchema) { $RootSchema = $Schema }
    $warnings = New-Object System.Collections.Generic.List[string]

    foreach ($name in @(Get-ObjectPropertyNames $Schema)) {
        if ($name -notin $script:SupportedSchemaKeywords) {
            $warnings.Add("$Path uses schema keyword '$name' outside the project compatibility allowlist")
        }
    }

    $properties = Get-MemberValue -Object $Schema -Name "properties"
    if ($properties) {
        foreach ($propName in @(Get-ObjectPropertyNames $properties)) {
            $propSchema = Get-MemberValue -Object $properties -Name $propName
            if ($propSchema) {
                foreach ($w in @(Test-SchemaKeywordCoverage -Schema $propSchema -Path "$Path.properties.$propName" -RootSchema $RootSchema)) {
                    $warnings.Add($w)
                }
            }
        }
    }

    $items = Get-MemberValue -Object $Schema -Name "items"
    if ($items) {
        foreach ($w in @(Test-SchemaKeywordCoverage -Schema $items -Path "$Path.items" -RootSchema $RootSchema)) {
            $warnings.Add($w)
        }
    }

    $defs = Get-MemberValue -Object $Schema -Name '$defs'
    if (-not $defs) { $defs = Get-MemberValue -Object $Schema -Name 'definitions' }
    if ($defs -and $Path -eq '$') {
        foreach ($defName in @(Get-ObjectPropertyNames $defs)) {
            $defSchema = Get-MemberValue -Object $defs -Name $defName
            if ($defSchema) {
                foreach ($w in @(Test-SchemaKeywordCoverage -Schema $defSchema -Path "`$defs.$defName" -RootSchema $RootSchema)) {
                    $warnings.Add($w)
                }
            }
        }
    }

    return $warnings.ToArray()
}

function Test-JsonSchemaContract {
    <#
    .SYNOPSIS
    Validates a JSON-shaped value against a repository JSON Schema file.
    .PARAMETER Value
    Object graph to validate after converting preserved JSON arrays back to arrays.
    .PARAMETER SchemaPath
    Absolute or repository-relative schema file path.
    #>
    [CmdletBinding()]
    param(
        [object]$Value,
        [string]$SchemaPath
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($SchemaPath)) { $SchemaPath } else { Join-Path $RepoRoot $SchemaPath }
    $errors = New-Object System.Collections.Generic.List[string]
    $schema = $null
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $errors.Add("schema file not found: $SchemaPath")
    } else {
        try {
            $schema = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath $fullPath -Raw)
        } catch {
            $errors.Add("schema file is unreadable: $($_.Exception.Message)")
        }
    }

    $keywordWarnings = @()
    if ($schema) {
        $keywordWarnings = @(Test-SchemaKeywordCoverage -Schema $schema)

        $testJsonCommand = Get-Command Test-Json -ErrorAction SilentlyContinue
        if (-not $testJsonCommand -or -not $testJsonCommand.Parameters.ContainsKey("SchemaFile")) {
            $errors.Add("Test-Json -SchemaFile is unavailable; PowerShell 7.4+ is required.")
        } else {
            try {
                $validationValue = $null
                ConvertTo-JsonSchemaValidationValue -Value $Value -Result ([ref]$validationValue)
                $json = ConvertTo-Json -InputObject $validationValue -Depth 100
                $null = Test-Json -Json $json -SchemaFile $fullPath -ErrorAction Stop
            } catch {
                $errors.Add($_.Exception.Message)
            }
        }
    }

    $resolvedSchemaPath = Resolve-Path -LiteralPath $fullPath -ErrorAction SilentlyContinue
    $schemaPathForReport = if ($resolvedSchemaPath) {
        ([System.IO.Path]::GetRelativePath($RepoRoot, $resolvedSchemaPath.Path) -replace '\\', '/')
    } else {
        $SchemaPath
    }

    return [ordered]@{
        schemaPath = [string]$schemaPathForReport
        schemaId = if ($schema) { Get-MemberValue -Object $schema -Name '$id' } else { $null }
        valid = [bool]($errors.Count -eq 0)
        errors = $errors.ToArray()
        unsupportedKeywords = $keywordWarnings
    }
}

function Test-FeedSchemaContracts {
    <#
    .SYNOPSIS
    Validates catalog and projects feed schema contracts together.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER ProjectsJson
    Generated projects.json text to parse and validate.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [string]$ProjectsJson
    )

    $projectsPayload = $null
    $projectsParseErrors = New-Object System.Collections.Generic.List[string]
    try {
        if ([string]::IsNullOrWhiteSpace($ProjectsJson)) {
            throw "generated projects feed is empty"
        }
        $projectsPayload = ConvertFrom-JsonPreservingArrays -Json $ProjectsJson
    } catch {
        $projectsParseErrors.Add("generated projects feed is unreadable: $($_.Exception.Message)")
    }

    $catalogResult = Test-JsonSchemaContract -Value $Catalog -SchemaPath $CatalogSchemaPath
    $projectsResult = if ($projectsPayload) {
        Test-JsonSchemaContract -Value $projectsPayload -SchemaPath $ProjectsSchemaPath
    } else {
        [ordered]@{
            schemaPath = "schemas/profile-projects.v1.json"
            schemaId = $ProjectsSchemaUrl
            valid = $false
            errors = $projectsParseErrors.ToArray()
            unsupportedKeywords = @()
        }
    }

    return [ordered]@{
        passed = [bool]($catalogResult.valid -and $projectsResult.valid)
        catalog = $catalogResult
        projects = $projectsResult
    }
}

function ConvertTo-RepoRelativeReportPath {
    param([string]$Path)

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }
    $resolvedPath = Resolve-Path -LiteralPath $fullPath -ErrorAction SilentlyContinue
    if ($resolvedPath) {
        return ([System.IO.Path]::GetRelativePath($RepoRoot, $resolvedPath.Path) -replace '\\', '/')
    }

    return ($Path -replace '\\', '/')
}

function Read-DocConsistencyFile {
    param(
        [string]$Path,
        [System.Collections.Generic.List[string]]$Errors
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }
    $reportPath = ConvertTo-RepoRelativeReportPath -Path $fullPath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $Errors.Add("$reportPath is missing")
        return [ordered]@{
            path = $reportPath
            text = $null
        }
    }

    try {
        return [ordered]@{
            path = $reportPath
            text = Get-Content -LiteralPath $fullPath -Raw
        }
    } catch {
        $Errors.Add("$reportPath is unreadable: $($_.Exception.Message)")
        return [ordered]@{
            path = $reportPath
            text = $null
        }
    }
}

function Add-DocConsistencyRecord {
    param(
        [System.Collections.Generic.List[object]]$Records,
        [System.Collections.Generic.List[string]]$Errors,
        [hashtable]$Document,
        [string]$Field,
        [string]$Pattern,
        [string]$MissingMessage
    )

    $value = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$Document.text)) {
        $match = [regex]::Match([string]$Document.text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($match.Success) {
            $value = $match.Groups[1].Value
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        $Errors.Add("$($Document.path) missing $MissingMessage")
    }

    $Records.Add([ordered]@{
            path = $Document.path
            field = $Field
            value = if ([string]::IsNullOrWhiteSpace([string]$value)) { $null } else { [string]$value }
        })

    return $value
}

function Test-IsoDateText {
    param([string]$Value)

    $parsedDate = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $Value,
        "yyyy-MM-dd",
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedDate
    )
}

function Test-ChangelogReleaseHeadings {
    param([object]$Document)

    $malformedHeadings = New-Object System.Collections.Generic.List[object]
    $headingCount = 0
    $headingPattern = '^## \[v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\] - (\d{4}-\d{2}-\d{2})\s*$'

    if (-not [string]::IsNullOrWhiteSpace([string]$Document.text)) {
        $lines = ([string]$Document.text) -split "\r?\n"
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = [string]$lines[$index]
            if ($line -notmatch '^## \[') {
                continue
            }

            $headingCount++
            $reason = $null
            $match = [regex]::Match($line, $headingPattern)
            if (-not $match.Success) {
                $reason = "heading must match '## [vMAJOR.MINOR.PATCH] - YYYY-MM-DD'"
            } elseif (-not (Test-IsoDateText -Value $match.Groups[4].Value)) {
                $reason = "release date is not a valid yyyy-MM-dd date"
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$reason)) {
                $malformedHeadings.Add([ordered]@{
                        path = $Document.path
                        lineNumber = [int]($index + 1)
                        text = $line
                        reason = $reason
                    })
            }
        }
    }

    return [ordered]@{
        passed = [bool]($malformedHeadings.Count -eq 0)
        headingCount = [int]$headingCount
        malformedCount = [int]$malformedHeadings.Count
        malformedHeadings = $malformedHeadings.ToArray()
    }
}

function Test-DocVersionConsistency {
    param(
        [string]$ProfileVersionPath = $script:ProfileVersionPath
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $versions = New-Object System.Collections.Generic.List[object]
    $dates = New-Object System.Collections.Generic.List[object]

    $profileVersionDoc = Read-DocConsistencyFile -Path $ProfileVersionPath -Errors $errors
    $profileVersion = $null
    $profileDate = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$profileVersionDoc.text)) {
        try {
            $profileVersionJson = [string]$profileVersionDoc.text | ConvertFrom-Json
            $profileVersion = [string](Get-MemberValue -Object $profileVersionJson -Name "version")
            $profileDate = [string](Get-MemberValue -Object $profileVersionJson -Name "date")
        } catch {
            $errors.Add("$($profileVersionDoc.path) is unreadable JSON: $($_.Exception.Message)")
        }
    }

    if ([string]::IsNullOrWhiteSpace($profileVersion)) {
        $errors.Add("$($profileVersionDoc.path) missing version")
    } elseif ($profileVersion -notmatch '^v\d+\.\d+\.\d+$') {
        $errors.Add("$($profileVersionDoc.path) version '$profileVersion' must match vMAJOR.MINOR.PATCH")
    }
    if ([string]::IsNullOrWhiteSpace($profileDate)) {
        $errors.Add("$($profileVersionDoc.path) missing date")
    } elseif (-not (Test-IsoDateText -Value $profileDate)) {
        $errors.Add("$($profileVersionDoc.path) date '$profileDate' is not a valid yyyy-MM-dd date")
    }

    $versions.Add([ordered]@{
            path = $profileVersionDoc.path
            field = "version"
            value = if ([string]::IsNullOrWhiteSpace($profileVersion)) { $null } else { $profileVersion }
        })
    $dates.Add([ordered]@{
            path = $profileVersionDoc.path
            field = "date"
            value = if ([string]::IsNullOrWhiteSpace($profileDate)) { $null } else { $profileDate }
        })

    $changelogHeadingValidation = [ordered]@{
        passed = $true
        headingCount = 0
        malformedCount = 0
        malformedHeadings = @()
    }

    return [ordered]@{
        passed = [bool]($errors.Count -eq 0)
        expectedVersion = if ([string]::IsNullOrWhiteSpace([string]$profileVersion)) { $null } else { [string]$profileVersion }
        expectedDate = if ([string]::IsNullOrWhiteSpace([string]$profileDate)) { $null } else { [string]$profileDate }
        versions = $versions.ToArray()
        dates = $dates.ToArray()
        changelogHeadingValidation = $changelogHeadingValidation
        errors = $errors.ToArray()
        warnings = $warnings.ToArray()
    }
}

function ConvertTo-ProfileVersion {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match($Value.Trim(), '^v?(\d+)\.(\d+)\.(\d+)$')
    if (-not $match.Success) {
        return $null
    }

    return [version]::new(
        [int]$match.Groups[1].Value,
        [int]$match.Groups[2].Value,
        [int]$match.Groups[3].Value
    )
}

function Get-ProfileRepositoryTagRef {
    param(
        [string]$TagName,
        [string]$Repository = "$Owner/$Owner"
    )

    $result = [ordered]@{
        checked = $false
        exists = $null
        tagName = if ([string]::IsNullOrWhiteSpace($TagName)) { $null } else { [string]$TagName }
        url = $null
        sha = $null
        unavailableReason = $null
    }

    if ([string]::IsNullOrWhiteSpace($TagName)) {
        $result.unavailableReason = "expected version is missing"
        return $result
    }

    if ($Offline) {
        $result.unavailableReason = "offline mode"
        return $result
    }

    $gh = Invoke-GhCli -Arguments @("api", "repos/$Repository/git/ref/tags/$TagName")
    $tagOutput = $gh.text
    if ($gh.exitCode -eq 0) {
        $tag = $tagOutput | ConvertFrom-Json
        $result.checked = $true
        $result.exists = $true
        $result.url = "https://github.com/$Repository/releases/tag/$TagName"
        $result.sha = [string](Get-NestedMemberValue -Object $tag -Path "object.sha")
        return $result
    }

    if (Test-GhApiNotFound -Output $tagOutput) {
        $result.checked = $true
        $result.exists = $false
        return $result
    }

    $result.unavailableReason = $tagOutput
    return $result
}

function Test-ProfileReleaseConsistency {
    <#
    .SYNOPSIS
    Compares the profile repo release/tag state with the tracked profile version.
    .PARAMETER Repos
    Repository metadata rows that include the profile repository.
    .PARAMETER DocVersionConsistency
    Version consistency result containing the expected profile version.
    .PARAMETER TagRef
    Optional pre-fetched expected tag reference result used by tests.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Repos,
        [object]$DocVersionConsistency,
        [object]$TagRef = $null
    )

    $repository = "$Owner/$Owner"
    $expectedVersion = [string](Get-MemberValue -Object $DocVersionConsistency -Name "expectedVersion")
    if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
        $expectedVersion = $null
    }

    $warnings = New-Object System.Collections.Generic.List[object]
    $profileRepo = $Repos | Where-Object { [string](Get-MemberValue -Object $_ -Name "name") -eq $Owner } | Select-Object -First 1
    $latestRelease = if ($profileRepo) { Get-MemberValue -Object $profileRepo -Name "latestRelease" } else { $null }
    $latestReleaseTag = if ($latestRelease) { [string](Get-MemberValue -Object $latestRelease -Name "tagName") } else { $null }
    $latestReleaseUrl = if ($latestRelease) { [string](Get-MemberValue -Object $latestRelease -Name "url") } else { $null }
    $latestReleasePublishedAt = if ($latestRelease) { ConvertTo-IsoText (Get-MemberValue -Object $latestRelease -Name "publishedAt") } else { $null }
    $versionRelation = "unavailable"
    $latestMatchesExpected = $false
    $latestAtLeastExpected = $false

    if (-not $profileRepo) {
        $warnings.Add([ordered]@{
            kind = "profile-repo-metadata-unavailable"
            expectedVersion = $expectedVersion
            actualVersion = $null
            message = "Profile repository metadata was not available in the public repo list."
        })
    } elseif ([string]::IsNullOrWhiteSpace($expectedVersion)) {
        $warnings.Add([ordered]@{
            kind = "expected-version-missing"
            expectedVersion = $null
            actualVersion = $latestReleaseTag
            message = "Planning docs did not expose a current version for release/tag comparison."
        })
    } elseif ([string]::IsNullOrWhiteSpace($latestReleaseTag)) {
        $versionRelation = "missing-release"
        $warnings.Add([ordered]@{
            kind = "latest-release-missing"
            expectedVersion = $expectedVersion
            actualVersion = $null
            message = "Profile repository has no latest release to compare with the planning version."
        })
    } else {
        $latestMatchesExpected = ([string]$latestReleaseTag -eq [string]$expectedVersion)
        $expectedParsed = ConvertTo-ProfileVersion -Value $expectedVersion
        $latestParsed = ConvertTo-ProfileVersion -Value $latestReleaseTag

        if ($latestMatchesExpected) {
            $versionRelation = "matching"
            $latestAtLeastExpected = $true
        } elseif ($expectedParsed -and $latestParsed) {
            $comparison = $latestParsed.CompareTo($expectedParsed)
            if ($comparison -lt 0) {
                $versionRelation = "behind"
                $warnings.Add([ordered]@{
                    kind = "latest-release-behind"
                    expectedVersion = $expectedVersion
                    actualVersion = $latestReleaseTag
                    message = "Latest profile release is older than the planning-doc version."
                })
            } elseif ($comparison -gt 0) {
                $versionRelation = "ahead"
                $latestAtLeastExpected = $true
                $warnings.Add([ordered]@{
                    kind = "latest-release-ahead"
                    expectedVersion = $expectedVersion
                    actualVersion = $latestReleaseTag
                    message = "Latest profile release is newer than the planning-doc version."
                })
            }
        } else {
            $versionRelation = "unparseable"
            $warnings.Add([ordered]@{
                kind = "release-version-unparseable"
                expectedVersion = $expectedVersion
                actualVersion = $latestReleaseTag
                message = "Release tag or planning version did not match vMAJOR.MINOR.PATCH."
            })
        }
    }

    if ($null -eq $TagRef) {
        $TagRef = [ordered]@{
            checked = $false
            exists = $null
            tagName = $expectedVersion
            url = $null
            sha = $null
            unavailableReason = "tag ref not checked"
        }
    }

    $tagRefChecked = [bool](Get-MemberValue -Object $TagRef -Name "checked")
    $tagRefExistsValue = Get-MemberValue -Object $TagRef -Name "exists"
    $tagRefExists = if ($null -eq $tagRefExistsValue) { $null } else { [bool]$tagRefExistsValue }
    $tagRefUnavailableReason = [string](Get-MemberValue -Object $TagRef -Name "unavailableReason")
    if ([string]::IsNullOrWhiteSpace($tagRefUnavailableReason)) {
        $tagRefUnavailableReason = $null
    }

    if ($expectedVersion) {
        if (-not $tagRefChecked) {
            $warnings.Add([ordered]@{
                kind = "expected-version-tag-unavailable"
                expectedVersion = $expectedVersion
                actualVersion = $null
                message = "Expected profile tag could not be checked: $tagRefUnavailableReason"
            })
        } elseif ($tagRefExists -ne $true) {
            $warnings.Add([ordered]@{
                kind = "expected-version-tag-missing"
                expectedVersion = $expectedVersion
                actualVersion = $null
                message = "Expected profile tag is not published on GitHub."
            })
        }
    }

    $releasePolicy = [ordered]@{
        status = "documented-internal-version-gap"
        decisionDocumentPath = "decision:profile-release-tag-policy"
        planningVersionKind = "profile-sync-internal-evidence-version"
        publicReleaseCadence = "manual-public-milestone-only"
        warningDisposition = "informational"
        releaseCreationRecommended = $false
        tagCreationRecommended = $false
        releaseCreationGate = "Create a GitHub release/tag only for user-visible public profile milestones or explicit operator request."
        nextAction = "Keep reporting the release/tag gap as warning-only evidence until a public milestone is intentionally cut or the repo switches to per-version releases."
    }

    return [ordered]@{
        passed = [bool]($warnings.Count -eq 0)
        repository = $repository
        expectedVersion = $expectedVersion
        latestReleaseTag = if ([string]::IsNullOrWhiteSpace($latestReleaseTag)) { $null } else { $latestReleaseTag }
        latestReleaseUrl = if ([string]::IsNullOrWhiteSpace($latestReleaseUrl)) { $null } else { $latestReleaseUrl }
        latestReleasePublishedAt = if ([string]::IsNullOrWhiteSpace($latestReleasePublishedAt)) { $null } else { $latestReleasePublishedAt }
        versionRelation = $versionRelation
        latestReleaseMatchesExpected = [bool]$latestMatchesExpected
        latestReleaseAtLeastExpected = [bool]$latestAtLeastExpected
        expectedTag = $expectedVersion
        expectedTagRefChecked = [bool]$tagRefChecked
        expectedTagExists = $tagRefExists
        expectedTagUrl = if ([string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $TagRef -Name "url"))) { $null } else { [string](Get-MemberValue -Object $TagRef -Name "url") }
        expectedTagSha = if ([string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $TagRef -Name "sha"))) { $null } else { [string](Get-MemberValue -Object $TagRef -Name "sha") }
        expectedTagUnavailableReason = $tagRefUnavailableReason
        warningCount = $warnings.Count
        warnings = $warnings.ToArray()
        releasePolicy = $releasePolicy
        note = "Warning-only comparison of the planning-doc version against the profile repository's latest GitHub release and matching tag ref."
    }
}

function New-MetadataRowIndex {
    param([object]$ProjectsPayload)

    $index = @{}
    $projects = Get-MemberValue -Object $ProjectsPayload -Name "projects"
    foreach ($row in @($projects)) {
        $repo = Get-MemberValue -Object $row -Name "repo"
        if (-not [string]::IsNullOrWhiteSpace([string]$repo)) {
            $index["project:$(([string]$repo).ToLowerInvariant())"] = $row
        }
    }

    $suppressed = Get-MemberValue -Object $ProjectsPayload -Name "suppressed"
    foreach ($row in @($suppressed)) {
        $suppressedId = Get-MemberValue -Object $row -Name "suppressedId"
        if (-not [string]::IsNullOrWhiteSpace([string]$suppressedId)) {
            $index["suppressed:$(([string]$suppressedId).ToLowerInvariant())"] = $row
            continue
        }

        $repo = Get-MemberValue -Object $row -Name "repo"
        if (-not [string]::IsNullOrWhiteSpace([string]$repo)) {
            $index["suppressed-repo:$(([string]$repo).ToLowerInvariant())"] = $row
        }
    }
    return $index
}

function New-MetadataDriftRecord {
    param(
        [string]$Repo,
        [string]$Category,
        [string]$Field,
        [object]$OldValue,
        [object]$NewValue,
        [string]$Severity
    )

    return [ordered]@{
        repo = if ([string]::IsNullOrWhiteSpace($Repo)) { $null } else { $Repo }
        category = if ([string]::IsNullOrWhiteSpace($Category)) { $null } else { $Category }
        field = $Field
        oldValue = $OldValue
        newValue = $NewValue
        severity = $Severity
        failing = [bool]($Severity -eq "fatal")
    }
}

function Test-TransientReleaseAssetInspectionDrift {
    param(
        [object]$CurrentRow,
        [object]$ExpectedRow,
        [string]$Field
    )

    $assetDependentFields = @(
        "primaryAction.kind",
        "primaryAction.label",
        "primaryAction.url",
        "searchMetadata",
        "hasDownload",
        "releaseAssetKinds",
        "releaseAssetNames",
        "releaseAssetInspected",
        "releaseTrust"
    )
    if ($assetDependentFields -notcontains $Field) {
        return $false
    }

    $currentInspected = ConvertTo-BooleanValue (Get-NestedMemberValue -Object $CurrentRow -Path "releaseAssetInspected")
    $expectedInspected = ConvertTo-BooleanValue (Get-NestedMemberValue -Object $ExpectedRow -Path "releaseAssetInspected")
    if (-not $currentInspected -or $expectedInspected) {
        return $false
    }

    $currentReleaseTag = Get-NestedMemberValue -Object $CurrentRow -Path "latestReleaseTag"
    $expectedReleaseTag = Get-NestedMemberValue -Object $ExpectedRow -Path "latestReleaseTag"
    if ((ConvertTo-ComparableJson $currentReleaseTag) -ne (ConvertTo-ComparableJson $expectedReleaseTag)) {
        return $false
    }

    $currentReleaseUrl = Get-NestedMemberValue -Object $CurrentRow -Path "latestReleaseUrl"
    $expectedReleaseUrl = Get-NestedMemberValue -Object $ExpectedRow -Path "latestReleaseUrl"
    if ((ConvertTo-ComparableJson $currentReleaseUrl) -ne (ConvertTo-ComparableJson $expectedReleaseUrl)) {
        return $false
    }

    return $true
}

function Test-MetadataDrift {
    param(
        [string]$CurrentProjectsJson,
        [string]$ExpectedProjectsJson,
        [int]$StaleGeneratedAtDays = $MetadataGeneratedAtStaleDays,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )

    $drift = New-Object System.Collections.Generic.List[object]
    $current = $null
    $expected = $null

    try {
        if ([string]::IsNullOrWhiteSpace($CurrentProjectsJson)) {
            throw "projects.json is missing or empty"
        }
        $current = $CurrentProjectsJson | ConvertFrom-Json
    } catch {
        $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field "projects.json" -OldValue "unreadable" -NewValue "valid generated feed" -Severity "fatal"))
    }

    try {
        $expected = $ExpectedProjectsJson | ConvertFrom-Json
    } catch {
        $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field "expectedProjects" -OldValue "generated feed" -NewValue "unreadable" -Severity "fatal"))
    }

    $generatedAtText = if ($current) { ConvertTo-IsoText (Get-MemberValue -Object $current -Name "generatedAt") } else { $null }
    $generatedAtInfo = [ordered]@{
        value = if ([string]::IsNullOrWhiteSpace($generatedAtText)) { $null } else { $generatedAtText }
        ageDays = $null
        staleAfterDays = $StaleGeneratedAtDays
        stale = $false
        warning = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($generatedAtText)) {
        $parsedGeneratedAt = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse($generatedAtText, [ref]$parsedGeneratedAt)) {
            $ageDays = [math]::Round(($Now.ToUniversalTime() - $parsedGeneratedAt.ToUniversalTime()).TotalDays, 2)
            $generatedAtInfo.ageDays = $ageDays
            if ($ageDays -gt $StaleGeneratedAtDays) {
                $generatedAtInfo.stale = $true
                $generatedAtInfo.warning = "projects.json generatedAt is older than $StaleGeneratedAtDays days"
            }
        } else {
            $generatedAtInfo.warning = "projects.json generatedAt could not be parsed"
        }
    } else {
        $generatedAtInfo.warning = "projects.json generatedAt is missing"
    }

    if ($current -and $expected) {
        $topLevelFatalFields = @("schema", "source", "publicRepoCount", "projectCount", "suppressedCount")
        foreach ($field in $topLevelFatalFields) {
            $oldValue = Get-MemberValue -Object $current -Name $field
            $newValue = Get-MemberValue -Object $expected -Name $field
            if ((ConvertTo-ComparableJson $oldValue) -ne (ConvertTo-ComparableJson $newValue)) {
                $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "fatal"))
            }
        }

        $provenanceFatalFields = @(
            "provenance.version",
            "provenance.feedSchemaVersion",
            "provenance.sourceRepository",
            "provenance.catalogSha256",
            "provenance.generatorSha256",
            "provenance.projectSchemaSha256",
            "provenance.metadataProvider",
            "provenance.repoEnumeration.requestedLimit",
            "provenance.repoEnumeration.returnedCount",
            "provenance.repoEnumeration.truncated"
        )
        foreach ($field in $provenanceFatalFields) {
            $oldValue = Get-NestedMemberValue -Object $current -Path $field
            $newValue = Get-NestedMemberValue -Object $expected -Path $field
            if ((ConvertTo-ComparableJson $oldValue) -ne (ConvertTo-ComparableJson $newValue)) {
                $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "fatal"))
            }
        }

        foreach ($field in @("provenance.sourceCommit", "provenance.metadataSnapshotAt")) {
            $oldValue = Get-NestedMemberValue -Object $current -Path $field
            $newValue = Get-NestedMemberValue -Object $expected -Path $field
            if ((ConvertTo-ComparableJson $oldValue) -ne (ConvertTo-ComparableJson $newValue)) {
                $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "info"))
            }
        }

        $currentRows = New-MetadataRowIndex -ProjectsPayload $current
        $expectedRows = New-MetadataRowIndex -ProjectsPayload $expected
        $rowKeys = @(@($currentRows.Keys) + @($expectedRows.Keys) | Sort-Object -Unique)
        $infoFields = @(
            "stars",
            "latestReleaseTag",
            "latestReleaseUrl",
            "releaseAssetKinds",
            "releaseAssetNames",
            "releaseAssetInspected",
            "releaseTrust",
            "pushedAt",
            "topics"
        )
        $rowFields = @(
            "suppressedId",
            "title",
            "category",
            "includeInReadme",
            "includeInPortfolio",
            "suppressed",
            "suppressionReason",
            "reasonCode",
            "publicReason",
            "description",
            "repoUrl",
            "liveUrl",
            "installUrl",
            "downloadUrl",
            "downloadKind",
            "primaryAction.kind",
            "primaryAction.label",
            "primaryAction.url",
            "searchMetadata",
            "hasDownload",
            "hasLiveDemo",
            "hasDirectInstall",
            "branch",
            "entrypoint",
            "installKind",
            "language",
            "stars",
            "latestReleaseTag",
            "latestReleaseUrl",
            "releaseAssetKinds",
            "releaseAssetNames",
            "releaseAssetInspected",
            "releaseTrust",
            "pushedAt",
            "topics",
            "visibility",
            "visibilityClass",
            "featured",
            "featuredRank",
            "currentlyBuilding",
            "notes"
        )

        foreach ($key in $rowKeys) {
            $hasCurrent = $currentRows.ContainsKey($key)
            $hasExpected = $expectedRows.ContainsKey($key)
            $repo = if ($hasExpected) {
                [string](Get-MemberValue -Object $expectedRows[$key] -Name "repo")
            } else {
                [string](Get-MemberValue -Object $currentRows[$key] -Name "repo")
            }
            $category = if ($hasExpected) {
                [string](Get-MemberValue -Object $expectedRows[$key] -Name "category")
            } else {
                [string](Get-MemberValue -Object $currentRows[$key] -Name "category")
            }

            if (-not $hasCurrent) {
                $drift.Add((New-MetadataDriftRecord -Repo $repo -Category $category -Field "row" -OldValue $null -NewValue "present" -Severity "fatal"))
                continue
            }
            if (-not $hasExpected) {
                $drift.Add((New-MetadataDriftRecord -Repo $repo -Category $category -Field "row" -OldValue "present" -NewValue $null -Severity "fatal"))
                continue
            }

            foreach ($field in $rowFields) {
                $oldValue = Get-NestedMemberValue -Object $currentRows[$key] -Path $field
                $newValue = Get-NestedMemberValue -Object $expectedRows[$key] -Path $field
                if ((ConvertTo-ComparableJson $oldValue) -ne (ConvertTo-ComparableJson $newValue)) {
                    $releaseAssetInspectionDrift = Test-TransientReleaseAssetInspectionDrift `
                        -CurrentRow $currentRows[$key] `
                        -ExpectedRow $expectedRows[$key] `
                        -Field $field
                    $severity = if ($infoFields -contains $field -or $releaseAssetInspectionDrift) { "info" } else { "fatal" }
                    $drift.Add((New-MetadataDriftRecord -Repo $repo -Category $category -Field $field -OldValue $oldValue -NewValue $newValue -Severity $severity))
                }
            }
        }
    }

    $fatalCount = @($drift | Where-Object { $_.severity -eq "fatal" }).Count
    $infoCount = @($drift | Where-Object { $_.severity -eq "info" }).Count

    return [ordered]@{
        metadataDrift = $drift.ToArray()
        fatalCount = $fatalCount
        informationalCount = $infoCount
        generatedAt = $generatedAtInfo
    }
}

function ConvertTo-TopicToken {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $token = $Value.ToLowerInvariant()
    $token = $token -replace '\+', 'plus'
    $token = $token -replace '#', 'sharp'
    $token = $token -replace '[^a-z0-9]+', '-'
    $token = $token.Trim('-')
    if ([string]::IsNullOrWhiteSpace($token)) {
        return $null
    }
    return $token
}

function Add-TopicHint {
    param(
        [System.Collections.Generic.List[string]]$Hints,
        [string]$Value
    )

    $token = ConvertTo-TopicToken $Value
    if (-not [string]::IsNullOrWhiteSpace($token) -and -not $Hints.Contains($token)) {
        $Hints.Add($token)
    }
}

function New-CatalogEntryLookup {
    param([hashtable[]]$Entries)

    $lookup = @{}
    foreach ($entry in @($Entries)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.repo)) {
            $lookup[([string]$entry.repo).ToLowerInvariant()] = $entry
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.aliasOf)) {
            $lookup[([string]$entry.aliasOf).ToLowerInvariant()] = $entry
        }
    }
    return $lookup
}

function Get-TopicHints {
    param(
        [string]$Repo,
        [string]$Language,
        [hashtable]$Entry,
        [string]$Description
    )

    $hints = New-Object System.Collections.Generic.List[string]
    if ($Entry) {
        switch ([string]$Entry.category) {
            "powershell" { foreach ($hint in @("powershell", "windows", "sysadmin")) { Add-TopicHint $hints $hint } }
            "python" { foreach ($hint in @("python", "desktop-app", "windows")) { Add-TopicHint $hints $hint } }
            "web" { foreach ($hint in @("web-app", "javascript", "github-pages")) { Add-TopicHint $hints $hint } }
            "extensions" { foreach ($hint in @("browser-extension", "userscript")) { Add-TopicHint $hints $hint } }
            "android" { foreach ($hint in @("android", "kotlin")) { Add-TopicHint $hints $hint } }
            "security" { foreach ($hint in @("security", "networking")) { Add-TopicHint $hints $hint } }
            "media" { foreach ($hint in @("media", "conversion")) { Add-TopicHint $hints $hint } }
            "desktop" { foreach ($hint in @("desktop-app", "windows")) { Add-TopicHint $hints $hint } }
            "guides" { foreach ($hint in @("documentation", "guide")) { Add-TopicHint $hints $hint } }
            "misc" { Add-TopicHint $hints "utility" }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$Entry.userscriptUrl) -or ([string]$Entry.downloadKind).ToLowerInvariant() -eq "userscript") {
            Add-TopicHint $hints "userscript"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Entry.liveUrl)) {
            Add-TopicHint $hints "web-app"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Entry.entrypoint)) {
            Add-TopicHint $hints "script"
        }
        if ($Entry.currentlyBuilding -eq $true) {
            Add-TopicHint $hints "active-development"
        }
    }

    switch ((ConvertTo-TopicToken $Language)) {
        "c-sharp" { Add-TopicHint $hints "csharp" }
        "csharp" { Add-TopicHint $hints "csharp" }
        "cplusplus" { Add-TopicHint $hints "cpp" }
        "c" { Add-TopicHint $hints "cpp" }
        default { Add-TopicHint $hints $Language }
    }

    $text = "$Repo $Description"
    if ($text -match '(?i)\bad[- ]?block|hosts') { Add-TopicHint $hints "ad-blocking" }
    if ($text -match '(?i)\bweather|hurricane|storm') { Add-TopicHint $hints "weather" }
    if ($text -match '(?i)\bvideo|subtitle') { Add-TopicHint $hints "video" }
    if ($text -match '(?i)\bimage|photo|icon|wallpaper') { Add-TopicHint $hints "image-tools" }
    if ($text -match '(?i)\bpdf') { Add-TopicHint $hints "pdf" }
    if ($text -match '(?i)\bfirewall|network|dns|vpn') { Add-TopicHint $hints "networking" }
    if ($text -match '(?i)\bprivacy|portable') { Add-TopicHint $hints "privacy" }
    if ($text -match '(?i)\bconvert|converter|conversion') { Add-TopicHint $hints "conversion" }
    if ($hints.Count -eq 0) { Add-TopicHint $hints "utility" }

    return @($hints | Select-Object -First 8)
}

function Test-MetadataHygiene {
    param(
        [object[]]$Repos,
        [hashtable[]]$CatalogEntries = @()
    )

    $missingTopics = New-Object System.Collections.Generic.List[object]
    $missingDescriptions = New-Object System.Collections.Generic.List[object]
    $catalogLookup = New-CatalogEntryLookup -Entries $CatalogEntries

    foreach ($repo in @($Repos | Sort-Object name)) {
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        if ([string]::IsNullOrWhiteSpace($repoName)) {
            continue
        }
        $catalogEntry = $null
        $repoKey = $repoName.ToLowerInvariant()
        if ($catalogLookup.ContainsKey($repoKey)) {
            $catalogEntry = $catalogLookup[$repoKey]
        }

        $language = $null
        $primaryLanguage = Get-MemberValue -Object $repo -Name "primaryLanguage"
        if ($primaryLanguage) {
            $language = Get-MemberValue -Object $primaryLanguage -Name "name"
        }

        $topicNames = @()
        $topics = Get-MemberValue -Object $repo -Name "repositoryTopics"
        foreach ($topic in @($topics)) {
            $topicName = Get-MemberValue -Object $topic -Name "name"
            if (-not [string]::IsNullOrWhiteSpace([string]$topicName)) {
                $topicNames += [string]$topicName
            }
        }

        if ($topicNames.Count -eq 0) {
            $missingTopics.Add([ordered]@{
                repo = $repoName
                language = if ([string]::IsNullOrWhiteSpace([string]$language)) { $null } else { [string]$language }
                pushedAt = ConvertTo-IsoText (Get-MemberValue -Object $repo -Name "pushedAt")
                category = if ($catalogEntry) { [string]$catalogEntry.category } else { $null }
                topicHints = @(Get-TopicHints -Repo $repoName -Language $language -Entry $catalogEntry -Description ([string](Get-MemberValue -Object $repo -Name "description")))
            })
        }

        $description = Get-MemberValue -Object $repo -Name "description"
        if ([string]::IsNullOrWhiteSpace([string]$description)) {
            $missingDescriptions.Add([ordered]@{
                repo = $repoName
                language = if ([string]::IsNullOrWhiteSpace([string]$language)) { $null } else { [string]$language }
                category = if ($catalogEntry) { [string]$catalogEntry.category } else { $null }
                catalogDescription = if ($catalogEntry -and -not [string]::IsNullOrWhiteSpace([string]$catalogEntry.descriptionOverride)) { [string]$catalogEntry.descriptionOverride } else { $null }
            })
        }
    }

    return [ordered]@{
        missingTopicCount = $missingTopics.Count
        missingDescriptionCount = $missingDescriptions.Count
        topicHintPolicy = [ordered]@{
            mutatesRepositories = $false
            applyModeAvailable = $false
            requiresExplicitAllowlist = $true
        }
        missingTopics = $missingTopics.ToArray()
        missingDescriptions = $missingDescriptions.ToArray()
    }
}

function Test-ProjectLicenseMetadata {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $missingLicenses = New-Object System.Collections.Generic.List[object]
    $unknownLicenses = New-Object System.Collections.Generic.List[object]
    $licenseCounts = @{}
    $checkedCount = 0
    $detectedCount = 0
    $intentionalExceptionCount = 0
    $unresolvedUnknownCount = 0

    foreach ($entry in @($Entries | Sort-Object repo)) {
        $checkedCount++
        $meta = Get-RepoMeta $entry $RepoLookup
        $license = Get-LicenseMetadata -Meta $meta
        $licenseKey = [string]$license["licenseKey"]
        $licenseName = [string]$license["licenseName"]
        $licenseSpdxId = [string]$license["licenseSpdxId"]

        if ([string]::IsNullOrWhiteSpace($licenseKey) -and [string]::IsNullOrWhiteSpace($licenseName) -and [string]::IsNullOrWhiteSpace($licenseSpdxId)) {
            $missingLicenses.Add([ordered]@{
                repo = [string]$entry.repo
                reason = "GitHub did not report a detected repository license"
            })
            continue
        }

        $detectedCount++
        if ($licenseKey -eq "other" -or $licenseSpdxId -eq "NOASSERTION") {
            $entryNotes = [string]$entry.notes
            $upstreamLicense = [string]$entry.upstreamLicense
            $exceptionReason = $null
            if (-not [string]::IsNullOrWhiteSpace($upstreamLicense) -and $upstreamLicense -match '^(Other|Custom|NOASSERTION)$') {
                $exceptionReason = "Catalog preserves upstream license attribution: $upstreamLicense"
            } elseif (-not [string]::IsNullOrWhiteSpace($entryNotes) -and $entryNotes -match '(?i)(business source|BSL|custom license|NOASSERTION|source license)') {
                $exceptionReason = $entryNotes
            }
            $intentionalException = -not [string]::IsNullOrWhiteSpace($exceptionReason)
            if ($intentionalException) {
                $intentionalExceptionCount++
            } else {
                $unresolvedUnknownCount++
            }
            $unknownLicenses.Add([ordered]@{
                repo = [string]$entry.repo
                licenseKey = if ([string]::IsNullOrWhiteSpace($licenseKey)) { $null } else { $licenseKey }
                licenseName = if ([string]::IsNullOrWhiteSpace($licenseName)) { $null } else { $licenseName }
                licenseSpdxId = if ([string]::IsNullOrWhiteSpace($licenseSpdxId)) { $null } else { $licenseSpdxId }
                reason = "GitHub reported an unrecognized or non-standard license"
                intentionalException = [bool]$intentionalException
                exceptionReason = if ([string]::IsNullOrWhiteSpace($exceptionReason)) { $null } else { $exceptionReason }
            })
        }

        $countKey = if (-not [string]::IsNullOrWhiteSpace($licenseSpdxId)) {
            $licenseSpdxId
        } elseif (-not [string]::IsNullOrWhiteSpace($licenseKey)) {
            $licenseKey
        } else {
            "unknown"
        }
        if (-not $licenseCounts.ContainsKey($countKey)) {
            $licenseCounts[$countKey] = [ordered]@{
                licenseSpdxId = if ([string]::IsNullOrWhiteSpace($licenseSpdxId)) { $null } else { $licenseSpdxId }
                licenseKey = if ([string]::IsNullOrWhiteSpace($licenseKey)) { $null } else { $licenseKey }
                licenseName = if ([string]::IsNullOrWhiteSpace($licenseName)) { $null } else { $licenseName }
                count = 0
            }
        }
        $licenseCounts[$countKey]["count"] = [int]$licenseCounts[$countKey]["count"] + 1
    }

    return [ordered]@{
        checkedCount = $checkedCount
        detectedCount = $detectedCount
        missingCount = $missingLicenses.Count
        unknownCount = $unknownLicenses.Count
        intentionalExceptionCount = [int]$intentionalExceptionCount
        unresolvedUnknownCount = [int]$unresolvedUnknownCount
        warningCount = $missingLicenses.Count + $unresolvedUnknownCount
        licenseCounts = Get-SortedReportRows -Rows @($licenseCounts.Values) -Keys @("licenseSpdxId", "licenseKey", "licenseName")
        missingLicenses = $missingLicenses.ToArray()
        unknownLicenses = $unknownLicenses.ToArray()
    }
}

function Test-ForkParentDrift {
    param(
        [object[]]$Repos,
        [hashtable[]]$CatalogEntries = @()
    )

    $catalogLookup = New-CatalogEntryLookup -Entries $CatalogEntries
    $matchingGitHubForks = New-Object System.Collections.Generic.List[object]
    $catalogContinuations = New-Object System.Collections.Generic.List[object]
    $missingCatalogAttribution = New-Object System.Collections.Generic.List[object]
    $parentMismatches = New-Object System.Collections.Generic.List[object]
    $parentUnavailable = New-Object System.Collections.Generic.List[object]
    $checkedCount = 0
    $githubForkCount = 0
    $catalogForkOfCount = 0

    foreach ($repo in @($Repos | Sort-Object name)) {
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        if ([string]::IsNullOrWhiteSpace($repoName) -or $repoName -eq $Owner) {
            continue
        }

        $entry = $null
        $repoKey = $repoName.ToLowerInvariant()
        if ($catalogLookup.ContainsKey($repoKey)) {
            $entry = $catalogLookup[$repoKey]
        }
        $catalogForkOf = if ($entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.forkOf)) { [string]$entry.forkOf } else { $null }
        $isFork = ConvertTo-BooleanValue (Get-MemberValue -Object $repo -Name "isFork")
        $githubParent = Get-ForkParentNameWithOwner -Meta $repo
        $fetchError = Get-MemberValue -Object $repo -Name "forkParentFetchError"

        if (-not [string]::IsNullOrWhiteSpace($catalogForkOf)) {
            $catalogForkOfCount++
        }
        if (-not $isFork -and [string]::IsNullOrWhiteSpace($catalogForkOf)) {
            continue
        }

        $checkedCount++
        if ($isFork) {
            $githubForkCount++
            if ([string]::IsNullOrWhiteSpace([string]$githubParent)) {
                $parentUnavailable.Add([ordered]@{
                    repo = $repoName
                    reason = "GitHub marks this repository as a fork, but parent metadata was unavailable"
                    error = if ([string]::IsNullOrWhiteSpace([string]$fetchError)) { $null } else { [string]$fetchError }
                })
            }
            if ([string]::IsNullOrWhiteSpace($catalogForkOf)) {
                $missingCatalogAttribution.Add([ordered]@{
                    repo = $repoName
                    githubParent = if ([string]::IsNullOrWhiteSpace([string]$githubParent)) { $null } else { [string]$githubParent }
                    reason = "GitHub marks this repository as a fork, but the catalog has no forkOf attribution"
                })
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$githubParent) -and $catalogForkOf.ToLowerInvariant() -ne ([string]$githubParent).ToLowerInvariant()) {
                $parentMismatches.Add([ordered]@{
                    repo = $repoName
                    catalogForkOf = $catalogForkOf
                    githubParent = [string]$githubParent
                    reason = "catalog forkOf does not match GitHub fork parent"
                })
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$githubParent)) {
                $matchingGitHubForks.Add([ordered]@{
                    repo = $repoName
                    catalogForkOf = $catalogForkOf
                    githubParent = [string]$githubParent
                })
            }
            continue
        }

        $catalogContinuations.Add([ordered]@{
            repo = $repoName
            catalogForkOf = $catalogForkOf
            reason = "catalog declares an upstream continuation/import, but GitHub does not mark this repository as a fork"
        })
    }

    return [ordered]@{
        checkedCount = $checkedCount
        githubForkCount = $githubForkCount
        catalogForkOfCount = $catalogForkOfCount
        matchingGitHubForkCount = $matchingGitHubForks.Count
        catalogContinuationCount = $catalogContinuations.Count
        missingCatalogAttributionCount = $missingCatalogAttribution.Count
        parentMismatchCount = $parentMismatches.Count
        parentUnavailableCount = $parentUnavailable.Count
        warningCount = $missingCatalogAttribution.Count + $parentMismatches.Count + $parentUnavailable.Count
        matchingGitHubForks = $matchingGitHubForks.ToArray()
        catalogContinuations = $catalogContinuations.ToArray()
        missingCatalogAttribution = $missingCatalogAttribution.ToArray()
        parentMismatches = $parentMismatches.ToArray()
        parentUnavailable = $parentUnavailable.ToArray()
        note = "GitHub fork-parent drift is warning-only: catalog continuations are allowed, while missing or mismatched GitHub fork attribution should be reviewed."
    }
}

function Test-StaleProjectReview {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup,
        [datetimeoffset]$Now = [datetimeoffset]::Now,
        [int]$StaleAfterDays = $StaleProjectPushedAtReviewDays,
        [int]$ReleaseStaleAfterDays = $StaleProjectReleaseReviewDays,
        [int]$ArchiveAfterDays = $ArchiveProjectPushedAtReviewDays
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $suppressionCounts = @{}
    $statusCounts = @{
        current = 0
        "stale-review" = 0
        "archive-review" = 0
    }
    $checkedProjectCount = 0
    $suppressedCount = 0
    $noReleaseCount = 0
    $archiveReviewCount = 0

    foreach ($entry in @($Entries | Sort-Object category, repo)) {
        $isSuppressed = -not [string]::IsNullOrWhiteSpace([string]$entry.suppressionReason)
        if ($isSuppressed) {
            $suppressedCount++
            $reasonCode = Get-SuppressionReasonCode -Reason ([string]$entry.suppressionReason)
            $visibilityClass = if ($reasonCode -eq "private-or-sensitive") { "private-or-sensitive" } else { "suppressed" }
            $key = "$reasonCode|$visibilityClass"
            if (-not $suppressionCounts.ContainsKey($key)) {
                $suppressionCounts[$key] = [ordered]@{
                    reasonCode = $reasonCode
                    publicReason = Get-PublicSuppressionReason -ReasonCode $reasonCode
                    visibilityClass = $visibilityClass
                    count = 0
                }
            }
            $suppressionCounts[$key]["count"] = [int]$suppressionCounts[$key]["count"] + 1
            continue
        }

        if ($entry.includeInPortfolio -eq $false -and $entry.includeInReadme -eq $false) {
            continue
        }

        $checkedProjectCount++
        $meta = Get-RepoMeta $entry $RepoLookup
        $signals = New-Object System.Collections.Generic.List[string]
        $pushedAt = if ($meta) { ConvertTo-IsoText (Get-MemberValue -Object $meta -Name "pushedAt") } else { $null }
        $pushedAtAgeDays = Get-AgeDays -Value $pushedAt -Now $Now
        $release = if ($meta) { Get-MemberValue -Object $meta -Name "latestRelease" } else { $null }
        $latestReleaseTag = if ($release) { [string](Get-MemberValue -Object $release -Name "tagName") } else { $null }
        $latestReleasePublishedAt = if ($release) { ConvertTo-IsoText (Get-MemberValue -Object $release -Name "publishedAt") } else { $null }
        $latestReleaseAgeDays = Get-AgeDays -Value $latestReleasePublishedAt -Now $Now

        if (-not $meta) {
            $signals.Add("metadata-unavailable")
        }
        if ($null -eq $pushedAtAgeDays) {
            $signals.Add("pushedAt-missing")
        } elseif ($pushedAtAgeDays -gt $StaleAfterDays) {
            $signals.Add("pushedAt-stale")
        }
        if ($release) {
            if ($null -eq $latestReleaseAgeDays) {
                $signals.Add("release-date-missing")
            } elseif ($latestReleaseAgeDays -gt $ReleaseStaleAfterDays) {
                $signals.Add("release-stale")
            }
        } else {
            $noReleaseCount++
            if ($null -ne $pushedAtAgeDays -and $pushedAtAgeDays -gt $StaleAfterDays) {
                $signals.Add("no-latest-release")
            }
        }

        $isPinned = ($entry.featured -eq $true -or $entry.currentlyBuilding -eq $true)
        if (-not $isPinned -and $null -ne $pushedAtAgeDays -and $pushedAtAgeDays -gt $ArchiveAfterDays) {
            $signals.Add("archive-review")
        }

        $status = "current"
        if ($signals.Contains("archive-review")) {
            $status = "archive-review"
            $archiveReviewCount++
        } elseif ($signals.Count -gt 0) {
            $status = "stale-review"
        }
        $statusCounts[$status] = [int]$statusCounts[$status] + 1

        if ($status -ne "current") {
            $primaryAction = Get-PrimaryAction $entry $meta $entry.category
            $rows.Add([ordered]@{
                repo = [string]$entry.repo
                category = [string]$entry.category
                status = $status
                signals = @($signals)
                pushedAt = if ([string]::IsNullOrWhiteSpace($pushedAt)) { $null } else { $pushedAt }
                pushedAtAgeDays = $pushedAtAgeDays
                latestReleaseTag = if ([string]::IsNullOrWhiteSpace($latestReleaseTag)) { $null } else { $latestReleaseTag }
                latestReleasePublishedAt = if ([string]::IsNullOrWhiteSpace($latestReleasePublishedAt)) { $null } else { $latestReleasePublishedAt }
                latestReleaseAgeDays = $latestReleaseAgeDays
                primaryAction = [string]$primaryAction["kind"]
                featured = [bool]$entry.featured
                currentlyBuilding = [bool]$entry.currentlyBuilding
            })
        }
    }

    $staleProjectCount = @($rows | Where-Object { $_.status -in @("stale-review", "archive-review") }).Count
    return [ordered]@{
        checkedProjectCount = [int]$checkedProjectCount
        staleAfterDays = [int]$StaleAfterDays
        releaseStaleAfterDays = [int]$ReleaseStaleAfterDays
        archiveAfterDays = [int]$ArchiveAfterDays
        staleProjectCount = [int]$staleProjectCount
        archiveReviewCount = [int]$archiveReviewCount
        noReleaseCount = [int]$noReleaseCount
        suppressedCount = [int]$suppressedCount
        warningCount = [int]$staleProjectCount
        statusCounts = @($statusCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { [ordered]@{ kind = [string]$_.Name; count = [int]$_.Value } })
        suppressionReasonCounts = Get-SortedReportRows -Rows @($suppressionCounts.Values) -Keys @("reasonCode", "visibilityClass", "publicReason")
        rows = $rows.ToArray()
        note = "Warning-only stale/archive review: visitor-facing rows are listed by repo; suppressed catalog rows are summarized by public reason code without exposing suppressed identifiers."
    }
}

function Test-ReleaseAssetDrift {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $missingReleaseForDownloadKind = New-Object System.Collections.Generic.List[object]
    $sourceOnlyWithRelease = New-Object System.Collections.Generic.List[object]
    $releaseActionLabelMismatches = New-Object System.Collections.Generic.List[object]
    $releaseAssetKindMismatches = New-Object System.Collections.Generic.List[object]
    $releaseAssetFetchFailures = New-Object System.Collections.Generic.List[object]
    $userscriptKindWithoutInstallUrl = New-Object System.Collections.Generic.List[object]
    $executableDownloadsMissingChecksums = New-Object System.Collections.Generic.List[object]
    $executableDownloadCandidates = New-Object System.Collections.Generic.List[object]
    $debugArtifactRows = New-Object System.Collections.Generic.List[object]
    $releaseAssetKindCounts = @{}
    $trustLevelCounts = @{}
    $immutableReleaseCount = 0
    $mutableReleaseCount = 0
    $digestCoverageCount = 0
    $releaseBearingRows = 0
    $releaseActionRows = 0
    $inspectedReleaseRows = 0

    foreach ($entry in @($Entries | Sort-Object repo)) {
        $meta = Get-RepoMeta $entry $RepoLookup
        $hasRelease = [bool]($meta -and $meta.latestRelease)
        $downloadKind = Get-EffectiveDownloadKind -Entry $entry -Category $entry.category
        $explicitDownloadKind = ([string]$entry.downloadKind).ToLowerInvariant()
        $action = Get-PrimaryAction $entry $meta $entry.category
        $assetKinds = if ($hasRelease) { @(Get-ReleaseAssetKindsFromMeta -Meta $meta) } else { @() }
        $assetNames = if ($hasRelease) { @(Get-ReleaseAssetNamesFromMeta -Meta $meta) } else { @() }
        $assetInspected = (Test-ReleaseAssetMetadataInspected -Meta $meta)
        $releaseImmutable = if ($hasRelease) { Get-MemberValue -Object $meta.latestRelease -Name "immutable" } else { $null }
        $releaseDigestsForDrift = if ($hasRelease) { $d = Get-MemberValue -Object $meta.latestRelease -Name "releaseAssetDigests"; if ($d -is [hashtable]) { $d } else { @{} } } else { @{} }
        $releaseTrust = New-ReleaseTrust -AssetKinds $assetKinds -AssetNames $assetNames -HasRelease $hasRelease -AssetInspected $assetInspected -Immutable $releaseImmutable -AssetDigests $releaseDigestsForDrift
        $trustLevel = [string]$releaseTrust.trustLevel
        if (-not $trustLevelCounts.ContainsKey($trustLevel)) {
            $trustLevelCounts[$trustLevel] = 0
        }
        $trustLevelCounts[$trustLevel]++

        if ($hasRelease) {
            $releaseBearingRows++
            if ($releaseTrust.releaseImmutable -eq $true) { $immutableReleaseCount++ }
            elseif ($releaseTrust.releaseImmutable -eq $false) { $mutableReleaseCount++ }
            if ([int]$releaseTrust.platformDigestCount -gt 0) { $digestCoverageCount++ }
            if ($assetInspected) {
                $inspectedReleaseRows++
                foreach ($kind in @($assetKinds)) {
                    if (-not $releaseAssetKindCounts.ContainsKey($kind)) {
                        $releaseAssetKindCounts[$kind] = 0
                    }
                    $releaseAssetKindCounts[$kind]++
                }
            } else {
                $release = Get-MemberValue -Object $meta -Name "latestRelease"
                $fetchError = Get-MemberValue -Object $release -Name "releaseAssetFetchError"
                if (-not [string]::IsNullOrWhiteSpace([string]$fetchError)) {
                    $releaseAssetFetchFailures.Add([ordered]@{
                        repo = [string]$entry.repo
                        latestReleaseTag = [string]$meta.latestRelease.tagName
                        error = [string]$fetchError
                    })
                }
            }
        }
        if ($action["kind"] -eq "release") {
            $releaseActionRows++
            $expectedLabel = Get-DownloadLabel $entry $entry.category
            if ([string]$action["label"] -ne [string]$expectedLabel) {
                $releaseActionLabelMismatches.Add([ordered]@{
                    repo = [string]$entry.repo
                    downloadKind = if ([string]::IsNullOrWhiteSpace($downloadKind)) { $null } else { $downloadKind }
                    expectedLabel = [string]$expectedLabel
                    actualLabel = [string]$action["label"]
                })
            }
            if (@($releaseTrust.executableAssetKinds).Count -gt 0 -and $releaseTrust.hasChecksumForEveryExecutable -ne $true) {
                $executableDownloadsMissingChecksums.Add([ordered]@{
                    repo = [string]$entry.repo
                    latestReleaseTag = if ($meta -and $meta.latestRelease) { [string]$meta.latestRelease.tagName } else { $null }
                    executableAssetKinds = @($releaseTrust.executableAssetKinds)
                    trustLevel = [string]$releaseTrust.trustLevel
                })
            }
            if ($releaseTrust.debugArtifactPresent) {
                $debugArtifactRows.Add([ordered]@{
                    repo = [string]$entry.repo
                    latestReleaseTag = if ($meta -and $meta.latestRelease) { [string]$meta.latestRelease.tagName } else { $null }
                    trustLevel = [string]$releaseTrust.trustLevel
                })
            }
            if (@($releaseTrust.executableAssetKinds).Count -gt 0) {
                $hasChecksum = [bool]$releaseTrust.hasChecksumForEveryExecutable -and @($releaseTrust.checksumAssets).Count -gt 0
                $checksumCoverage = [string]$releaseTrust.checksumCoverage
                $hasPlatformDigest = [bool]([int]$releaseTrust.platformDigestCount -gt 0)
                $hasSbom = @($releaseTrust.sbomAssets).Count -gt 0
                $hasAttestation = [bool]$releaseTrust.attestationAvailable
                $hasMetadataEvidence = $hasChecksum -or $hasPlatformDigest
                $gapScore = 0
                if (-not $hasMetadataEvidence) { $gapScore++ }
                if (-not $hasSbom) { $gapScore++ }
                if (-not $hasAttestation) { $gapScore++ }
                $nextAction = if (-not $hasMetadataEvidence -and $checksumCoverage -eq "partial") {
                    "complete-missing-sha256sums"
                } elseif (-not $hasMetadataEvidence) {
                    "publish-sha256sums"
                } elseif (-not $hasAttestation) {
                    "publish-build-provenance-attestation"
                } elseif (-not $hasSbom) {
                    "publish-sbom"
                } else {
                    "metadata-complete"
                }
                $isImmutable = [bool]($releaseTrust.releaseImmutable -eq $true)
                $readinessLevel = if ($hasMetadataEvidence -and $hasAttestation -and $hasSbom -and $isImmutable) {
                    "metadata-complete"
                } elseif ($hasAttestation) {
                    "attestation-metadata"
                } elseif ($hasSbom) {
                    "sbom-metadata"
                } elseif ($isImmutable) {
                    "immutable-metadata"
                } elseif ($hasMetadataEvidence) {
                    "digest-metadata"
                } else {
                    "no-metadata-evidence"
                }
                $executableDownloadCandidates.Add([ordered]@{
                        repo = [string]$entry.repo
                        stars = if ($meta) { [int]$meta.stargazerCount } else { 0 }
                        latestReleaseTag = if ($meta -and $meta.latestRelease) { [string]$meta.latestRelease.tagName } else { $null }
                        executableAssetKinds = @($releaseTrust.executableAssetKinds)
                        trustLevel = [string]$releaseTrust.trustLevel
                        evidenceSource = "release-metadata-only"
                        hasChecksum = [bool]$hasChecksum
                        checksumCoverage = [string]$checksumCoverage
                        hasPlatformDigest = [bool]$hasPlatformDigest
                        hasMetadataEvidence = [bool]$hasMetadataEvidence
                        hasSbom = [bool]$hasSbom
                        hasAttestation = [bool]$hasAttestation
                        isImmutable = [bool]$isImmutable
                        readinessLevel = $readinessLevel
                        gapScore = [int]$gapScore
                        nextAction = $nextAction
                    })
            }
        }

        if ($hasRelease -and $downloadKind -eq "repo") {
            $sourceOnlyWithRelease.Add([ordered]@{
                repo = [string]$entry.repo
                latestReleaseTag = [string]$meta.latestRelease.tagName
                releaseAssetKinds = @($assetKinds)
            })
        }

        if (-not $hasRelease -and -not [string]::IsNullOrWhiteSpace($explicitDownloadKind) -and $explicitDownloadKind -notin @("repo", "userscript")) {
            $missingReleaseForDownloadKind.Add([ordered]@{
                repo = [string]$entry.repo
                downloadKind = $explicitDownloadKind
            })
        }

        if ($hasRelease -and $assetInspected -and -not [string]::IsNullOrWhiteSpace($explicitDownloadKind) -and $explicitDownloadKind -notin @("repo", "userscript")) {
            $expectedKinds = @(Get-ExpectedReleaseAssetKinds -Entry $entry -Category $entry.category)
            if (-not (Test-ReleaseAssetKindMatch -ExpectedKinds $expectedKinds -ActualKinds $assetKinds)) {
                $releaseAssetKindMismatches.Add([ordered]@{
                    repo = [string]$entry.repo
                    downloadKind = $explicitDownloadKind
                    expectedAssetKinds = @($expectedKinds)
                    releaseAssetKinds = @($assetKinds)
                    releaseAssetNames = @($assetNames)
                    primaryAction = [string]$action["kind"]
                })
            }
        }

        if ($downloadKind -eq "userscript" -and [string]::IsNullOrWhiteSpace([string]$entry.userscriptUrl)) {
            $userscriptKindWithoutInstallUrl.Add([ordered]@{
                repo = [string]$entry.repo
                downloadKind = $downloadKind
            })
        }
    }

    $kindCounts = @(
        $releaseAssetKindCounts.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    kind = [string]$_.Key
                    count = [int]$_.Value
                }
            }
    )
    $trustCounts = @(
        $trustLevelCounts.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    trustLevel = [string]$_.Key
                    count = [int]$_.Value
                }
            }
    )

    # Prioritized executable-download trust starter lane: rank executable-bearing
    # download repos by how much verifiable supply-chain evidence they are missing
    # (checksums, then attestation, then SBOM), then by reach (stars). This keeps
    # filename-derived heuristics distinct from a "checksum/SBOM/attestation present"
    # signal so adoption work can start with the highest-impact rows first.
    $shortlistSoftCap = 10
    $rankedCandidates = @(
        $executableDownloadCandidates.ToArray() |
            Sort-Object -Property `
                @{ Expression = { [int]$_.gapScore }; Descending = $true }, `
                @{ Expression = { [int]$_.stars }; Descending = $true }, `
                @{ Expression = { [string]$_.repo }; Descending = $false }
    )
    $shortlistRows = New-Object System.Collections.Generic.List[object]
    $rank = 0
    foreach ($candidate in $rankedCandidates) {
        if ($shortlistRows.Count -ge $shortlistSoftCap) { break }
        $rank++
        $row = [ordered]@{ priorityRank = $rank }
        foreach ($property in $candidate.GetEnumerator()) {
            $row[$property.Key] = $property.Value
        }
        $shortlistRows.Add($row)
    }
    # Use Measure-Object for counts: arrays of OrderedDictionary rows otherwise
    # trigger PowerShell member-enumeration on .Count and return per-row counts.
    $executableDownloadCount = ($rankedCandidates | Measure-Object).Count
    $metadataCompleteCount = ($rankedCandidates | Where-Object { [int]$_.gapScore -eq 0 } | Measure-Object).Count
    $checksumGapCount = ($rankedCandidates | Where-Object { -not $_.hasChecksum } | Measure-Object).Count
    $metadataEvidenceGapCount = ($rankedCandidates | Where-Object { -not $_.hasMetadataEvidence } | Measure-Object).Count
    $platformDigestCount = ($rankedCandidates | Where-Object { $_.hasPlatformDigest } | Measure-Object).Count
    $attestationGapCount = ($rankedCandidates | Where-Object { -not $_.hasAttestation } | Measure-Object).Count
    $sbomGapCount = ($rankedCandidates | Where-Object { -not $_.hasSbom } | Measure-Object).Count
    $immutableCount = ($rankedCandidates | Where-Object { $_.isImmutable } | Measure-Object).Count
    $readinessBuckets = @{}
    foreach ($candidate in @($rankedCandidates)) {
        $level = [string]$candidate.readinessLevel
        if (-not $readinessBuckets.ContainsKey($level)) { $readinessBuckets[$level] = 0 }
        $readinessBuckets[$level]++
    }
    $readinessCounts = @(foreach ($level in @("metadata-complete", "attestation-metadata", "sbom-metadata", "immutable-metadata", "digest-metadata", "no-metadata-evidence")) {
        if ($readinessBuckets.ContainsKey($level)) {
            [ordered]@{ readinessLevel = $level; count = [int]$readinessBuckets[$level] }
        }
    })
    $shortlistTruncatedCount = [int]$executableDownloadCount - [int]$shortlistRows.Count
    if ($shortlistTruncatedCount -lt 0) { $shortlistTruncatedCount = 0 }
    $executableDownloadTrustShortlist = [ordered]@{
        evidenceSource = "release-metadata-only"
        executableDownloadCount = [int]$executableDownloadCount
        metadataCompleteCount = [int]$metadataCompleteCount
        checksumGapCount = [int]$checksumGapCount
        metadataEvidenceGapCount = [int]$metadataEvidenceGapCount
        platformDigestCount = [int]$platformDigestCount
        attestationGapCount = [int]$attestationGapCount
        sbomGapCount = [int]$sbomGapCount
        immutableCount = [int]$immutableCount
        readinessCounts = @($readinessCounts)
        shortlistSoftCap = [int]$shortlistSoftCap
        truncatedCount = [int]$shortlistTruncatedCount
        rows = @($shortlistRows.ToArray())
        note = "Metadata evidence records filename-derived sidecar checksums, SBOM or attestation filenames, and GitHub platform asset digests; no binaries were downloaded or locally verified."
    }

    return [ordered]@{
        checkedCatalogRows = @($Entries).Count
        releaseBearingRows = $releaseBearingRows
        releaseActionRows = $releaseActionRows
        assetApiInspected = ($inspectedReleaseRows -gt 0)
        inspectedReleaseRows = $inspectedReleaseRows
        releaseAssetKindCounts = $kindCounts
        releaseTrustLevelCounts = $trustCounts
        releaseImmutability = [ordered]@{
            immutableCount = [int]$immutableReleaseCount
            mutableCount = [int]$mutableReleaseCount
            unknownCount = [int]($releaseBearingRows - $immutableReleaseCount - $mutableReleaseCount)
        }
        platformDigestCoverage = [ordered]@{
            withDigestCount = [int]$digestCoverageCount
            withoutDigestCount = [int]($releaseBearingRows - $digestCoverageCount)
        }
        executableDownloadTrustShortlist = $executableDownloadTrustShortlist
        executableDownloadsMissingChecksums = $executableDownloadsMissingChecksums.ToArray()
        debugArtifactRows = $debugArtifactRows.ToArray()
        sourceOnlyWithRelease = $sourceOnlyWithRelease.ToArray()
        missingReleaseForDownloadKind = $missingReleaseForDownloadKind.ToArray()
        releaseActionLabelMismatches = $releaseActionLabelMismatches.ToArray()
        releaseAssetKindMismatches = $releaseAssetKindMismatches.ToArray()
        releaseAssetFetchFailures = $releaseAssetFetchFailures.ToArray()
        userscriptKindWithoutInstallUrl = $userscriptKindWithoutInstallUrl.ToArray()
        note = "Release asset filename inspection compares catalog downloadKind labels against uploaded latest-release asset names; source-only releases remain repo actions."
    }
}

function Get-RawGitHubSourceInfo {
    param([string]$Url)

    $info = [ordered]@{
        sourceHost = $null
        sourceRepository = $null
        sourceRef = $null
        sourceRefType = "unknown"
        sourcePath = $null
        rawGitHub = $false
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $info
    }

    try {
        $uri = [Uri]$Url
        $info.sourceHost = $uri.Host
        if ($uri.Host -ne "raw.githubusercontent.com") {
            return $info
        }

        $match = [regex]::Match($uri.AbsolutePath, '^/(?<owner>[^/]+)/(?<repo>[^/]+)/(?<ref>[^/]+)/(?<path>.+)$')
        if (-not $match.Success) {
            return $info
        }

        $ref = [Uri]::UnescapeDataString($match.Groups["ref"].Value)
        $info.rawGitHub = $true
        $info.sourceRepository = "$([Uri]::UnescapeDataString($match.Groups["owner"].Value))/$([Uri]::UnescapeDataString($match.Groups["repo"].Value))"
        $info.sourceRef = $ref
        $info.sourcePath = [Uri]::UnescapeDataString($match.Groups["path"].Value)
        $info.sourceRefType = if ($ref -match '^[a-f0-9]{40}$') {
            "commit"
        } elseif ($ref -match '^v?\d+(\.\d+){1,3}([.-].*)?$') {
            "tag"
        } else {
            "branch"
        }
    } catch {
        $info.sourceHost = $null
    }

    return $info
}

function Get-UserscriptMetadata {
    param([string]$Content)

    $metadata = @{}
    $inBlock = $false
    $closed = $false

    foreach ($line in @(([string]$Content) -split "`r?`n")) {
        if (-not $inBlock) {
            if ($line -match '^\s*//\s*==UserScript==\s*$') {
                $inBlock = $true
            }
            continue
        }

        if ($line -match '^\s*//\s*==/UserScript==\s*$') {
            $closed = $true
            break
        }

        $match = [regex]::Match($line, '^\s*//\s*@(?<key>[A-Za-z][\w:-]*)\s*(?<value>.*)$')
        if (-not $match.Success) {
            continue
        }

        $key = $match.Groups["key"].Value
        $value = $match.Groups["value"].Value.Trim()
        if (-not $metadata.ContainsKey($key)) {
            $metadata[$key] = New-Object System.Collections.Generic.List[string]
        }
        $metadata[$key].Add($value)
    }

    return [ordered]@{
        metadataBlockPresent = $inBlock
        metadataBlockClosed = [bool]($inBlock -and $closed)
        metadata = $metadata
    }
}

function Get-UserscriptMetadataValues {
    param(
        [hashtable]$Metadata,
        [string]$Key
    )

    if ($null -eq $Metadata -or -not $Metadata.ContainsKey($Key)) {
        return @()
    }
    return @($Metadata[$Key] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-FirstUserscriptMetadataValue {
    param(
        [hashtable]$Metadata,
        [string]$Key
    )

    $values = @(Get-UserscriptMetadataValues -Metadata $Metadata -Key $Key)
    if ($values.Count -eq 0) {
        return $null
    }
    return [string]$values[0]
}

function Test-UserscriptBroadScope {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $normalized = (([string]$Value).Trim() -replace '\s+', '')
    return $normalized -in @(
        "*",
        "*://*",
        "*://*/*",
        "http://*/*",
        "https://*/*",
        "http*://*/*"
    )
}

function Test-AllowedUserscriptUrl {
    <#
    .SYNOPSIS
    Returns true when a userscript fetch URL is HTTPS on a trusted GitHub raw-content host.
    .DESCRIPTION
    Userscript install URLs are canonically raw.githubusercontent.com (Tampermonkey/Violentmonkey install links).
    Restricting fetches to HTTPS on GitHub-owned hosts prevents a tampered catalog userscriptUrl from turning
    the sync run into an SSRF probe against internal or arbitrary hosts.
    .PARAMETER Url
    The candidate userscript URL.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }

    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.Scheme -ne 'https') { return $false }

    $allowedHosts = @(
        'raw.githubusercontent.com',
        'gist.githubusercontent.com',
        'objects.githubusercontent.com',
        'github.com'
    )
    return $uri.Host -in $allowedHosts
}

function Get-UserscriptContent {
    param([string]$Url)

    if (-not (Test-AllowedUserscriptUrl -Url $Url)) {
        return [ordered]@{
            succeeded = $false
            content = $null
            statusCode = $null
            error = "Blocked userscript fetch: URL is not HTTPS on an allowed GitHub raw-content host."
        }
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 20 -MaximumRedirection 5 -UseBasicParsing
        return [ordered]@{
            succeeded = $true
            content = [string]$response.Content
            statusCode = if ($response.BaseResponse) { [int]$response.BaseResponse.StatusCode } else { $null }
            error = $null
        }
    } catch {
        $statusCode = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        return [ordered]@{
            succeeded = $false
            content = $null
            statusCode = $statusCode
            error = $_.Exception.Message
        }
    }
}

function New-UserscriptTrustWarning {
    param(
        [string]$Kind,
        [string]$Message,
        [bool]$Fatal = $false
    )

    return [ordered]@{
        kind = $Kind
        message = $Message
        fatal = [bool]$Fatal
    }
}

function Get-UserscriptUrlProbe {
    param(
        [string]$Url,
        [hashtable]$ProbeByUrl = @{}
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return [ordered]@{
            checked = $false
            ok = $null
            statusCode = $null
            error = $null
            fatal = $false
        }
    }

    if ($ProbeByUrl.ContainsKey($Url)) {
        $probe = $ProbeByUrl[$Url]
        return [ordered]@{
            checked = $true
            ok = [bool](Get-MemberValue -Object $probe -Name "ok")
            statusCode = Get-MemberValue -Object $probe -Name "status"
            error = Get-MemberValue -Object $probe -Name "error"
            fatal = [bool](Get-MemberValue -Object $probe -Name "fatal")
        }
    }

    $result = Test-HttpUrl -Url $Url -TimeoutSec 12 -Retries 1
    return [ordered]@{
        checked = $true
        ok = [bool]$result.ok
        statusCode = $result.status
        error = $result.error
        fatal = [bool]$result.fatal
    }
}

function Get-UserscriptMetadataUrlTrust {
    param(
        [string]$Url,
        [object]$InstallSource,
        [hashtable]$ProbeByUrl = @{}
    )

    $source = Get-RawGitHubSourceInfo -Url $Url
    $refMatches = $null
    if ([bool](Get-MemberValue -Object $InstallSource -Name "rawGitHub") -and [bool]$source.rawGitHub) {
        $installRepository = [string](Get-MemberValue -Object $InstallSource -Name "sourceRepository")
        $installRef = [string](Get-MemberValue -Object $InstallSource -Name "sourceRef")
        if (-not [string]::IsNullOrWhiteSpace($installRepository) -and -not [string]::IsNullOrWhiteSpace($installRef)) {
            $refMatches = [bool](
                $source.sourceRepository -eq $installRepository -and
                $source.sourceRef -eq $installRef
            )
        }
    }

    $probe = Get-UserscriptUrlProbe -Url $Url -ProbeByUrl $ProbeByUrl
    return [ordered]@{
        sourceRef = $source.sourceRef
        refMatchesSource = $refMatches
        probeSucceeded = if ([bool]$probe.checked) { $probe.ok } else { $null }
        probeStatusCode = $probe.statusCode
        probeError = $probe.error
        probeFatal = [bool]$probe.fatal
    }
}

function Test-UserscriptInstallTrust {
    param(
        [hashtable[]]$Entries,
        [hashtable]$ContentByUrl = @{},
        [hashtable]$ProbeByUrl = @{},
        [switch]$Skip
    )

    $userscriptEntries = @($Entries | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.userscriptUrl) -or
            ([string]$_.downloadKind).ToLowerInvariant() -eq "userscript"
        } | Sort-Object repo)

    if ($Skip) {
        return [ordered]@{
            skipped = $true
            skipReason = if ($Offline) { "offline mode" } else { "link validation skipped" }
            checkedCount = 0
            installActionCount = $userscriptEntries.Count
            rawGitHubCount = 0
            branchSourceCount = 0
            tagOrCommitSourceCount = 0
            metadataBlockCount = 0
            missingMetadataBlockCount = 0
            missingVersionCount = 0
            missingUpdateUrlCount = 0
            missingDownloadUrlCount = 0
            updateUrlProbeFailureCount = 0
            downloadUrlProbeFailureCount = 0
            updateUrlRefMismatchCount = 0
            downloadUrlRefMismatchCount = 0
            broadScopeCount = 0
            releaseChannelReadyCount = 0
            releaseChannelKeepBranchCount = 0
            releaseChannelBlockedCount = 0
            warningCount = 0
            fatalCount = 0
            rows = @()
            note = "Userscript metadata inspection parses raw .user.js headers only; script bodies are not executed."
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $userscriptEntries) {
        $url = if ([string]::IsNullOrWhiteSpace([string]$entry.userscriptUrl)) { $null } else { [string]$entry.userscriptUrl }
        $source = Get-RawGitHubSourceInfo -Url $url
        $warnings = New-Object System.Collections.Generic.List[object]
        $fetchStatus = [ordered]@{ succeeded = $false; content = $null; statusCode = $null; error = $null }

        if ([string]::IsNullOrWhiteSpace($url)) {
            $warnings.Add((New-UserscriptTrustWarning -Kind "userscript-url-missing" -Message "Catalog marks this row as a userscript but has no userscriptUrl."))
        } elseif ($ContentByUrl.ContainsKey($url)) {
            $fetchStatus.succeeded = $true
            $fetchStatus.content = [string]$ContentByUrl[$url]
        } else {
            $fetchStatus = Get-UserscriptContent -Url $url
        }

        $metadataResult = Get-UserscriptMetadata -Content ([string]$fetchStatus.content)
        $metadata = [hashtable]$metadataResult.metadata
        $name = Get-FirstUserscriptMetadataValue -Metadata $metadata -Key "name"
        $version = Get-FirstUserscriptMetadataValue -Metadata $metadata -Key "version"
        $updateUrl = Get-FirstUserscriptMetadataValue -Metadata $metadata -Key "updateURL"
        $downloadUrl = Get-FirstUserscriptMetadataValue -Metadata $metadata -Key "downloadURL"
        $matchValues = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "match")
        $includes = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "include")
        $grants = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "grant")
        $connects = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "connect")
        $requires = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "require")
        $scopeValues = @($matchValues + $includes)
        $broadScopes = @($scopeValues | Where-Object { Test-UserscriptBroadScope -Value ([string]$_) })
        $updateUrlTrust = Get-UserscriptMetadataUrlTrust -Url $updateUrl -InstallSource $source -ProbeByUrl $ProbeByUrl
        $downloadUrlTrust = Get-UserscriptMetadataUrlTrust -Url $downloadUrl -InstallSource $source -ProbeByUrl $ProbeByUrl

        if (-not $fetchStatus.succeeded) {
            $warnings.Add((New-UserscriptTrustWarning -Kind "userscript-fetch-failed" -Message "Could not fetch the raw userscript for metadata inspection."))
        } elseif (-not [bool]$metadataResult.metadataBlockPresent) {
            $warnings.Add((New-UserscriptTrustWarning -Kind "metadata-block-missing" -Message "Userscript metadata block is missing."))
        } else {
            if (-not [bool]$metadataResult.metadataBlockClosed) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "metadata-block-unclosed" -Message "Userscript metadata block is not closed."))
            }
            if ([string]::IsNullOrWhiteSpace($name)) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "name-missing" -Message "Userscript metadata is missing @name."))
            }
            if ([string]::IsNullOrWhiteSpace($version)) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "version-missing" -Message "Userscript metadata is missing @version, which userscript managers use for update checks."))
            }
            if ($scopeValues.Count -eq 0) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "scope-missing" -Message "Userscript metadata is missing @match or @include scope."))
            }
            if ($broadScopes.Count -gt 0) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "scope-broad" -Message "Userscript metadata includes an all-sites @match or @include scope."))
            }
            if ([string]::IsNullOrWhiteSpace($updateUrl)) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "update-url-missing" -Message "Userscript metadata is missing an explicit @updateURL."))
            } else {
                if ($null -ne $updateUrlTrust.refMatchesSource -and -not [bool]$updateUrlTrust.refMatchesSource) {
                    $warnings.Add((New-UserscriptTrustWarning -Kind "update-url-ref-mismatch" -Message "Userscript @updateURL does not use the same repository/ref as the catalog install URL."))
                }
                if ($null -ne $updateUrlTrust.probeSucceeded -and -not [bool]$updateUrlTrust.probeSucceeded) {
                    $warnings.Add((New-UserscriptTrustWarning -Kind "update-url-unreachable" -Message "Userscript @updateURL could not be reached." -Fatal:([bool]$updateUrlTrust.probeFatal)))
                }
            }
            if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "download-url-missing" -Message "Userscript metadata is missing an explicit @downloadURL."))
            } else {
                if ($null -ne $downloadUrlTrust.refMatchesSource -and -not [bool]$downloadUrlTrust.refMatchesSource) {
                    $warnings.Add((New-UserscriptTrustWarning -Kind "download-url-ref-mismatch" -Message "Userscript @downloadURL does not use the same repository/ref as the catalog install URL."))
                }
                if ($null -ne $downloadUrlTrust.probeSucceeded -and -not [bool]$downloadUrlTrust.probeSucceeded) {
                    $warnings.Add((New-UserscriptTrustWarning -Kind "download-url-unreachable" -Message "Userscript @downloadURL could not be reached." -Fatal:([bool]$downloadUrlTrust.probeFatal)))
                }
            }
        }

        $rowFatalCount = @($warnings | Where-Object { $_.fatal }).Count

        # Release-channel readiness classifier (does not change install URLs):
        #   blocked     - metadata too incomplete to support an update channel
        #   ready       - metadata complete and already pinned to a tag/commit ref
        #   keep-branch - metadata complete branch install (canonical per the
        #                 userscript install-posture decision)
        $metadataComplete = [bool]$metadataResult.metadataBlockPresent -and
            -not [string]::IsNullOrWhiteSpace($version) -and
            -not [string]::IsNullOrWhiteSpace($updateUrl) -and
            -not [string]::IsNullOrWhiteSpace($downloadUrl)
        $sourceRefType = [string]$source.sourceRefType
        $updateUrlAligned = [bool]($null -ne $updateUrlTrust.refMatchesSource -and $updateUrlTrust.refMatchesSource)
        $releaseChannelReadiness = if (-not $metadataComplete) {
            "blocked"
        } elseif ($sourceRefType -in @("tag", "commit")) {
            "ready"
        } else {
            "keep-branch"
        }
        $releaseChannelNextAction = switch ($releaseChannelReadiness) {
            "blocked" { "Add @version, @updateURL, and @downloadURL metadata before evaluating a tag/release install channel." }
            "ready" { "Eligible to evaluate a tag or release install channel; metadata already pins a ref. No install-URL change required yet." }
            default { "Keep the branch-hosted raw install per the userscript install-posture decision; metadata is complete." }
        }

        $rows.Add([ordered]@{
            repo = [string]$entry.repo
            url = $url
            sourceHost = $source.sourceHost
            sourceRepository = $source.sourceRepository
            sourceRef = $source.sourceRef
            sourceRefType = $source.sourceRefType
            sourcePath = $source.sourcePath
            rawGitHub = [bool]$source.rawGitHub
            fetchSucceeded = [bool]$fetchStatus.succeeded
            fetchStatusCode = $fetchStatus.statusCode
            metadataBlockPresent = [bool]$metadataResult.metadataBlockPresent
            metadataBlockClosed = [bool]$metadataResult.metadataBlockClosed
            name = if ([string]::IsNullOrWhiteSpace($name)) { $null } else { $name }
            version = if ([string]::IsNullOrWhiteSpace($version)) { $null } else { $version }
            updateUrl = if ([string]::IsNullOrWhiteSpace($updateUrl)) { $null } else { $updateUrl }
            downloadUrl = if ([string]::IsNullOrWhiteSpace($downloadUrl)) { $null } else { $downloadUrl }
            updateUrlSourceRef = if ([string]::IsNullOrWhiteSpace([string]$updateUrlTrust.sourceRef)) { $null } else { [string]$updateUrlTrust.sourceRef }
            updateUrlRefMatchesSource = $updateUrlTrust.refMatchesSource
            updateUrlProbeSucceeded = $updateUrlTrust.probeSucceeded
            updateUrlProbeStatusCode = $updateUrlTrust.probeStatusCode
            downloadUrlSourceRef = if ([string]::IsNullOrWhiteSpace([string]$downloadUrlTrust.sourceRef)) { $null } else { [string]$downloadUrlTrust.sourceRef }
            downloadUrlRefMatchesSource = $downloadUrlTrust.refMatchesSource
            downloadUrlProbeSucceeded = $downloadUrlTrust.probeSucceeded
            downloadUrlProbeStatusCode = $downloadUrlTrust.probeStatusCode
            matchCount = $matchValues.Count
            includeCount = $includes.Count
            grantCount = $grants.Count
            connectCount = $connects.Count
            requireCount = $requires.Count
            broadScope = [bool]($broadScopes.Count -gt 0)
            releaseChannelReadiness = $releaseChannelReadiness
            releaseChannelNextAction = $releaseChannelNextAction
            releaseChannelEvidence = [ordered]@{
                metadataComplete = [bool]$metadataComplete
                sourceRefType = if ([string]::IsNullOrWhiteSpace($sourceRefType)) { $null } else { $sourceRefType }
                hasVersion = [bool](-not [string]::IsNullOrWhiteSpace($version))
                updateUrlAligned = [bool]$updateUrlAligned
            }
            warningCount = $warnings.Count
            fatalCount = $rowFatalCount
            warnings = $warnings.ToArray()
        })
    }

    $rowArray = @($rows.ToArray())
    $warningTotal = 0
    $fatalTotal = 0
    foreach ($row in $rowArray) {
        $warningTotal += [int]$row.warningCount
        $fatalTotal += [int]$row.fatalCount
    }

    return [ordered]@{
        skipped = $false
        skipReason = $null
        checkedCount = $rowArray.Count
        installActionCount = $userscriptEntries.Count
        rawGitHubCount = @($rowArray | Where-Object { $_.rawGitHub }).Count
        branchSourceCount = @($rowArray | Where-Object { $_.sourceRefType -eq "branch" }).Count
        tagOrCommitSourceCount = @($rowArray | Where-Object { $_.sourceRefType -in @("tag", "commit") }).Count
        metadataBlockCount = @($rowArray | Where-Object { $_.metadataBlockPresent }).Count
        missingMetadataBlockCount = @($rowArray | Where-Object { -not $_.metadataBlockPresent }).Count
        missingVersionCount = @($rowArray | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.version) }).Count
        missingUpdateUrlCount = @($rowArray | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.updateUrl) }).Count
        missingDownloadUrlCount = @($rowArray | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.downloadUrl) }).Count
        updateUrlProbeFailureCount = @($rowArray | Where-Object { $null -ne $_.updateUrlProbeSucceeded -and -not $_.updateUrlProbeSucceeded }).Count
        downloadUrlProbeFailureCount = @($rowArray | Where-Object { $null -ne $_.downloadUrlProbeSucceeded -and -not $_.downloadUrlProbeSucceeded }).Count
        updateUrlRefMismatchCount = @($rowArray | Where-Object { $null -ne $_.updateUrlRefMatchesSource -and -not $_.updateUrlRefMatchesSource }).Count
        downloadUrlRefMismatchCount = @($rowArray | Where-Object { $null -ne $_.downloadUrlRefMatchesSource -and -not $_.downloadUrlRefMatchesSource }).Count
        broadScopeCount = @($rowArray | Where-Object { $_.broadScope }).Count
        releaseChannelReadyCount = @($rowArray | Where-Object { $_.releaseChannelReadiness -eq "ready" }).Count
        releaseChannelKeepBranchCount = @($rowArray | Where-Object { $_.releaseChannelReadiness -eq "keep-branch" }).Count
        releaseChannelBlockedCount = @($rowArray | Where-Object { $_.releaseChannelReadiness -eq "blocked" }).Count
        warningCount = [int]$warningTotal
        fatalCount = [int]$fatalTotal
        rows = $rowArray
        note = "Userscript metadata inspection parses raw .user.js headers only; script bodies are not executed."
    }
}

function Test-UrlScheme {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $true }
    try {
        $uri = [System.Uri]::new($Url)
        return $uri.Scheme -eq 'https'
    } catch {
        return $false
    }
}

function Test-CatalogUrlSchemes {
    param([hashtable[]]$Entries)

    $violations = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Entries) {
        foreach ($field in @('liveUrl', 'userscriptUrl')) {
            $url = [string]$entry[$field]
            if (-not [string]::IsNullOrWhiteSpace($url) -and -not (Test-UrlScheme $url)) {
                $violations.Add([ordered]@{
                    repo = [string]$entry.repo
                    field = $field
                    url = $url
                    reason = "only https: URLs are allowed in visitor-facing catalog fields"
                })
            }
        }
    }
    return $violations.ToArray()
}

function Test-ProfileState {
    <#
    .SYNOPSIS
    Runs the complete profile sync validation and builds the sync report.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER Repos
    Live or offline repository metadata used for generated output and reports.
    .PARAMETER ExpectedReadme
    README content expected from the current catalog and metadata.
    .PARAMETER ExpectedProjects
    projects.json content expected from the current catalog and metadata.
    .PARAMETER CurrentReadme
    Optional current README content; defaults to reading README.md.
    .PARAMETER CurrentProjects
    Optional current projects.json content; defaults to reading projects.json.
    .PARAMETER ExpectedAssets
    Expected generated profile SVG content keyed by relative path.
    .PARAMETER SkipLinkValidation
    Skips outbound link probing while keeping the rest of the sync checks active.
    .PARAMETER SmokeReportPath
    Local rendered-profile smoke artifact to fold into reports/profile-sync-report.json.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [string]$ExpectedReadme,
        [string]$ExpectedProjects,
        [string]$CurrentReadme,
        [string]$CurrentProjects,
        [hashtable]$ExpectedAssets = @{},
        [switch]$SkipLinkValidation,
        [string]$SmokeReportPath = $script:SmokeReportPath
    )

    # Normalize to a null-filtered array so .Count and enumeration stay safe under StrictMode
    # when the repo set is empty (e.g. offline runs bind $Repos to $null).
    $Repos = @($Repos | Where-Object { $null -ne $_ })
    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries)
    $catalogShape = Test-CatalogShape -Catalog $Catalog
    $included = @($entries | Where-Object { $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })
    $orphanedSuppressed = @($entries | Where-Object {
        $_.category -eq 'suppressed' -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
    } | ForEach-Object { [ordered]@{ repo = [string]$_.repo; reason = "category is 'suppressed' but suppressionReason is missing" } })
    $handledNames = @{}
    foreach ($entry in $entries) {
        $handledNames[$entry.repo.ToLowerInvariant()] = $true
        if ($entry.aliasOf) {
            $handledNames[([string]$entry.aliasOf).ToLowerInvariant()] = $true
        }
    }

    $missingPublic = @()
    foreach ($repo in $Repos) {
        if ($repo.name -eq $Owner) {
            continue
        }
        if (-not $handledNames.ContainsKey($repo.name.ToLowerInvariant())) {
            $missingPublic += [ordered]@{
                repo = $repo.name
                description = $repo.description
                language = if ($repo.primaryLanguage) { $repo.primaryLanguage.name } else { $null }
            }
        }
    }

    $privateViolations = @()
    $medicalViolations = @()
    $redirects = @()
    foreach ($entry in $included) {
        $meta = Get-RepoMeta $entry $repoLookup
        if (-not $meta) {
            if (-not $Offline) {
                $view = $null
                try {
                    $view = gh repo view "$Owner/$($entry.repo)" --json name,url,visibility 2>$null | ConvertFrom-Json
                } catch {
                    $view = $null
                }
                if ($view -and $view.name -ne $entry.repo) {
                    $redirects += [ordered]@{
                        repo = $entry.repo
                        canonical = $view.name
                        url = $view.url
                    }
                } else {
                    $privateViolations += [ordered]@{
                        repo = $entry.repo
                        reason = "not returned by public active repo list"
                    }
                }
            }
            continue
        }

        if ($meta.visibility -ne "PUBLIC" -or $meta.isPrivate) {
            $privateViolations += [ordered]@{
                repo = $entry.repo
                visibility = $meta.visibility
            }
        }

        $topicText = if ($meta.repositoryTopics) { ($meta.repositoryTopics.name -join " ") } else { "" }
        $medicalText = "$($entry.repo) $($meta.description) $topicText"
        if ($medicalText -match $MedicalPattern -and $entry.allowPublicMedical -ne $true) {
            $medicalViolations += [ordered]@{
                repo = $entry.repo
                reason = "medical-imaging keyword requires explicit allowPublicMedical"
            }
        }
    }

    $readmeReadPath = if ([System.IO.Path]::IsPathRooted($ReadmePath)) { $ReadmePath } else { Join-Path $RepoRoot $ReadmePath }
    $projectsReadPath = if ([System.IO.Path]::IsPathRooted($ProjectsPath)) { $ProjectsPath } else { Join-Path $RepoRoot $ProjectsPath }
    $currentReadme = if ($PSBoundParameters.ContainsKey("CurrentReadme")) {
        $CurrentReadme
    } else {
        Get-Content -LiteralPath $readmeReadPath -Raw
    }
    $currentProjects = if ($PSBoundParameters.ContainsKey("CurrentProjects")) {
        $CurrentProjects
    } elseif (Test-Path -LiteralPath $projectsReadPath) {
        Get-Content -LiteralPath $projectsReadPath -Raw
    } else {
        ""
    }
    $normalize = {
        param([string]$Text)
        return (($Text -replace "`r`n", "`n").TrimEnd())
    }
    $readmeInSync = (& $normalize $currentReadme) -eq (& $normalize $ExpectedReadme)
    $projectsComparableInSync = (ConvertTo-ProjectsSyncComparableJson -Json $currentProjects) -eq (ConvertTo-ProjectsSyncComparableJson -Json $ExpectedProjects)
    $metadataDriftResult = Test-MetadataDrift -CurrentProjectsJson $currentProjects -ExpectedProjectsJson $ExpectedProjects
    $projectsInSync = $projectsComparableInSync -or ([int](Get-MemberValue -Object $metadataDriftResult -Name "fatalCount") -eq 0)
    $assetChecks = New-Object System.Collections.Generic.List[object]
    foreach ($assetPath in @($ExpectedAssets.Keys | Sort-Object)) {
        $fullPath = Join-Path $RepoRoot $assetPath
        $exists = Test-Path -LiteralPath $fullPath
        $assetInSync = $false
        if ($exists) {
            $currentAsset = Get-Content -LiteralPath $fullPath -Raw
            $assetInSync = ((& $normalize $currentAsset) -eq (& $normalize ([string]$ExpectedAssets[$assetPath])))
        }
        $assetChecks.Add([ordered]@{
            path = [string]$assetPath
            exists = [bool]$exists
            inSync = [bool]$assetInSync
        })
    }
    # Contribution heatmaps are regenerated from the live GitHub contribution calendar, which
    # changes continuously for an active account, so committed-vs-fresh drift is expected between
    # a -Write and a later -Check. Keep their per-asset drift visible in the rows but exclude them
    # from the fatal sync gate; the deterministic catalog-driven assets remain fatal. Missing
    # (non-existent) contribution files still fail the gate.
    $assetsInSync = @($assetChecks | Where-Object {
        $_.inSync -ne $true -and ($_.exists -ne $true -or [string]$_.path -notmatch 'contributions-(dark|light)\.svg$')
    }).Count -eq 0

    $linkFailures = @()
    $linkWarnings = @()
    $linkValidationSummary = [ordered]@{
        targetCount = 0
        throttleLimit = $LinkValidationThrottle
        elapsedMs = 0
        warningCountByHost = @()
        headerHostWarnings = @()
    }
    if (-not $Offline -and -not $SkipLinkValidation) {
        $readmeHeaderTargets = @(Get-ReadmeHeaderLinkValidationTargets -ExpectedReadme $ExpectedReadme)
        $linkResult = Test-LinkTargets -Included $included -RepoLookup $repoLookup -ExtraTargets $readmeHeaderTargets
        $linkFailures = @($linkResult.failures)
        $linkWarnings = @($linkResult.warnings)
        $linkValidationSummary = [ordered]@{
            targetCount = $linkResult.targetCount
            throttleLimit = $linkResult.throttleLimit
            elapsedMs = $linkResult.elapsedMs
            warningCountByHost = @($linkResult.warningCountByHost)
            headerHostWarnings = @($linkResult.headerHostWarnings)
        }
    }

    $urlSchemeViolations = @(Test-CatalogUrlSchemes -Entries $included)
    $experienceChecks = Test-ReadmeExperience -Catalog $Catalog -Repos $Repos -ExpectedReadme $ExpectedReadme
    $readmeSizeBudget = Test-ReadmeSizeBudget -ExpectedReadme $ExpectedReadme
    $readmeHeadingHierarchy = Test-ReadmeHeadingHierarchy -ExpectedReadme $ExpectedReadme
    $readmeDensity = Test-ReadmeDensity -ExpectedReadme $ExpectedReadme -Entries $included -RepoLookup $repoLookup
    $artifactBudgets = Test-GeneratedArtifactBudgets -ExpectedReadme $ExpectedReadme -ExpectedProjectsJson $ExpectedProjects -ExpectedAssets $ExpectedAssets -ReportJson $null
    $smokeArtifact = Read-RenderedProfileSmokeReport -Path $SmokeReportPath
    $renderedProfileSmoke = New-RenderedProfileSmokeSummary -SmokeReport $smokeArtifact.report -SourcePath $smokeArtifact.path
    $committedReportForFreshness = $null
    $committedReportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $RepoRoot $ReportPath }
    if (Test-Path -LiteralPath $committedReportFullPath) {
        try {
            $committedReportForFreshness = Get-Content -LiteralPath $committedReportFullPath -Raw | ConvertFrom-Json
        } catch {
            $committedReportForFreshness = $null
        }
    }
    $latestReportCommit = Get-LatestReportAffectingCommit
    $evidenceFreshness = Test-ReportEvidenceFreshness -CommittedReport $committedReportForFreshness -LatestCommitDate $latestReportCommit.date -LatestCommitSha $latestReportCommit.sha
    $scheduledWorkflowDefinitions = Get-ScheduledWorkflowDefinitions
    $scheduledWorkflowRunLookup = Get-ScheduledWorkflowRunLookup -Definitions $scheduledWorkflowDefinitions
    $scheduledWorkflowFreshness = Test-ScheduledWorkflowFreshness -Definitions $scheduledWorkflowDefinitions -RunLookup $scheduledWorkflowRunLookup -Now (Get-Date)
    $roadmapHygiene = Test-RoadmapHygiene
    $rootMarkdownHygiene = Test-RootMarkdownHygiene
    $profileAssetsAccessibility = Test-ProfileAssetsAccessibility
    $metadataHygiene = Test-MetadataHygiene -Repos $Repos -CatalogEntries $entries
    $projectLicenseMetadata = Test-ProjectLicenseMetadata -Entries $included -RepoLookup $repoLookup
    $forkParentDrift = Test-ForkParentDrift -Repos $Repos -CatalogEntries $entries
    $staleProjectReview = Test-StaleProjectReview -Entries $entries -RepoLookup $repoLookup
    $releaseAssetDrift = Test-ReleaseAssetDrift -Entries $included -RepoLookup $repoLookup
    $userscriptInstallTrust = Test-UserscriptInstallTrust -Entries $included -Skip:($Offline -or $SkipLinkValidation)
    $catalogFeedAccounting = Test-CatalogFeedAccounting -Catalog $Catalog -ProjectsJson $ExpectedProjects
    $portfolioCompatibility = Test-PortfolioFeedCompatibility -ProjectsJson $ExpectedProjects
    $feedSchemaValidation = Test-FeedSchemaContracts -Catalog $Catalog -ProjectsJson $ExpectedProjects
    $repositoryCommunityBaseline = Get-RepositoryCommunityBaseline
    $schemaValidation = [ordered]@{
        passed = [bool]$feedSchemaValidation.passed
        catalog = $feedSchemaValidation.catalog
        projects = $feedSchemaValidation.projects
        report = [ordered]@{
            schemaPath = "schemas/profile-sync-report.v1.json"
            schemaId = $ReportSchemaUrl
            valid = $true
            errors = @()
            unsupportedKeywords = @()
        }
    }
    $docVersionConsistency = Test-DocVersionConsistency
    $profileReleaseConsistency = Test-ProfileReleaseConsistency `
        -Repos $Repos `
        -DocVersionConsistency $docVersionConsistency `
        -TagRef (Get-ProfileRepositoryTagRef -TagName ([string]$docVersionConsistency.expectedVersion))
    $reportGeneratedAt = (Get-Date).ToString("o")
    $feedProvenance = $null
    try {
        $expectedProjectsPayload = ConvertFrom-JsonPreservingArrays -Json $ExpectedProjects
        $feedProvenance = Get-MemberValue -Object $expectedProjectsPayload -Name "provenance"
    } catch {
        $feedProvenance = $null
    }
    $validationPerformance = [ordered]@{
        metadataFetch = [ordered]@{
            provider = [string]$script:RepositoryMetadataProvider
            attemptCount = [int]$script:MetadataFetchAttemptCount
            fallbackUsed = [bool]($script:RepositoryMetadataProvider -eq "rest-fallback")
            fallbackReason = if ([string]::IsNullOrWhiteSpace($script:MetadataFetchFallbackReason)) { $null } else { [string]$script:MetadataFetchFallbackReason }
            repoCount = [int]$Repos.Count
            fidelityDegraded = [bool]($script:RepositoryEnumerationTruncated -or $script:RepositoryMetadataProvider -eq "rest-fallback")
        }
        linkValidation = [ordered]@{
            skipped = [bool]($Offline -or $SkipLinkValidation)
            targetCount = $linkValidationSummary.targetCount
            throttleLimit = $linkValidationSummary.throttleLimit
            elapsedMs = $linkValidationSummary.elapsedMs
            failureCount = @($linkFailures).Count
            warningCount = @($linkWarnings).Count
            warningHostCount = @($linkValidationSummary.warningCountByHost).Count
            headerWarningHostCount = @($linkValidationSummary.headerHostWarnings).Count
        }
        restFallbackReleaseFetch = Get-RestFallbackReleaseFetchState
    }
    $report = [ordered]@{
        schema = $ReportSchemaUrl
        generatedAt = $reportGeneratedAt
        readmeInSync = $readmeInSync
        projectsExportInSync = $projectsInSync
        profileAssetsInSync = $assetsInSync
        profileAssetChecks = $assetChecks.ToArray()
        publicRepoCount = $Repos.Count
        catalogEntryCount = $entries.Count
        includedReadmeCount = $included.Count
        provenance = $feedProvenance
        catalogShape = $catalogShape
        metadataHygiene = $metadataHygiene
        projectLicenseMetadata = $projectLicenseMetadata
        forkParentDrift = $forkParentDrift
        staleProjectReview = $staleProjectReview
        releaseAssetDrift = $releaseAssetDrift
        userscriptInstallTrust = $userscriptInstallTrust
        catalogFeedAccounting = $catalogFeedAccounting
        portfolioCompatibility = $portfolioCompatibility
        repositorySettings = $repositoryCommunityBaseline["repositorySettings"]
        communityHealth = $repositoryCommunityBaseline["communityHealth"]
        schemaValidation = $schemaValidation
        docVersionConsistency = $docVersionConsistency
        profileReleaseConsistency = $profileReleaseConsistency
        validationPerformance = $validationPerformance
        missingPublicRepos = $missingPublic
        privateVisibilityViolations = $privateViolations
        medicalPrivacyViolations = $medicalViolations
        urlSchemeViolations = $urlSchemeViolations
        orphanedSuppressedEntries = $orphanedSuppressed
        renamedRepoRedirects = $redirects
        metadataDrift = @($metadataDriftResult.metadataDrift)
        metadataDriftSummary = [ordered]@{
            fatalCount = $metadataDriftResult.fatalCount
            informationalCount = $metadataDriftResult.informationalCount
            generatedAt = $metadataDriftResult.generatedAt
        }
        linkValidationSkipped = [bool]($Offline -or $SkipLinkValidation)
        linkValidationSummary = $linkValidationSummary
        linkValidationFailures = @($linkFailures)
        linkValidationWarnings = @($linkWarnings)
        readmeSizeBudget = $readmeSizeBudget
        readmeHeadingHierarchy = $readmeHeadingHierarchy
        readmeDensity = $readmeDensity
        artifactBudgets = $artifactBudgets
        renderedProfileSmoke = $renderedProfileSmoke
        evidenceFreshness = $evidenceFreshness
        scheduledWorkflowFreshness = $scheduledWorkflowFreshness
        roadmapHygiene = $roadmapHygiene
        rootMarkdownHygiene = $rootMarkdownHygiene
        profileAssetsAccessibility = $profileAssetsAccessibility
        readmeExperienceChecks = $experienceChecks
    }
    # Compact report sections to keep the committed JSON below the 70 % soft-limit.
    # The live PS objects are still fully populated for downstream use within this
    # function; only the serialised report copy is stripped here.

    # 1. prDeliveryTransition: replace per-evidence detail objects and the items
    #    checklist array with compact status strings / counts.
    $prTransitionRef = $null
    try {
        $prTransitionRef = $report["repositorySettings"]["requiredCheckReadiness"]["prDeliveryTransition"]
    } catch {
        $prTransitionRef = $null
    }
    if ($prTransitionRef -is [System.Collections.IDictionary]) {
        $detailKeys = @(
            'generatedPrDryRunEvidence', 'generatedPrWriteEvidence', 'directMainMaintenancePolicy',
            'candidateCheckExercisePlan', 'candidateCheckExerciseEvidence',
            'routineMaintenancePrDrillEvidence', 'requiredCheckEnforcementEvidence', 'items'
        )
        foreach ($dk in $detailKeys) {
            if ($prTransitionRef.Contains($dk)) {
                $detail = $prTransitionRef[$dk]
                # Replace detail objects and arrays with compact summaries.
                # The items count is preserved as a nonNegativeInteger.
                # generatedPrWriteEvidence is kept as a minimal stub so that
                # write-profile-sync-summary.ps1 can still read statusHandoffContext
                # for the CI step summary (tested by the summary test suite).
                $prTransitionRef[$dk] = if ($dk -eq 'items' -and $null -ne $detail -and $detail.GetType().IsArray) {
                    [int]($detail | Measure-Object).Count
                } elseif ($dk -eq 'generatedPrWriteEvidence' -and $detail -is [System.Collections.IDictionary]) {
                    # Keep a stub with all fields that write-profile-sync-summary.ps1 reads under
                    # Set-StrictMode -Version Latest (missing props throw); only statusHandoffContext
                    # needs its real value — the rest default to null so guards short-circuit.
                    [ordered]@{
                        available                           = $null
                        conclusion                          = $null
                        failedStep                          = $null
                        generatedBranchCleanup              = $null
                        runUrl                              = $null
                        pullRequestNumber                   = $null
                        pullRequestState                    = $null
                        validationDispatched                = $null
                        validationConclusion                = $null
                        validationFailedStep                = $null
                        validationRunUrl                    = $null
                        generatedBranchCheckRunCount        = $null
                        generatedBranchSuccessfulCheckRunCount = $null
                        pullRequestCheckRollupCount         = $null
                        pullRequestChecksAttached           = $null
                        statusHandoffImplemented            = $null
                        statusHandoffContext                 = [string](Get-MemberValue -Object $detail -Name 'statusHandoffContext')
                        statusHandoffProof                  = $null
                        statusHandoffState                  = $null
                        statusHandoffPermission             = $null
                    }
                } else {
                    $null
                }
            }
        }
    }

    # 2. executableDownloadsMissingChecksums: replace the per-repo row array with
    #    just the count.
    $releaseAssetDriftRef = $report["releaseAssetDrift"]
    if ($releaseAssetDriftRef -is [System.Collections.IDictionary] -and
        $releaseAssetDriftRef.Contains('executableDownloadsMissingChecksums')) {
        $checksumArray = $releaseAssetDriftRef['executableDownloadsMissingChecksums']
        $releaseAssetDriftRef['executableDownloadsMissingChecksums'] = if ($null -ne $checksumArray -and $checksumArray.GetType().IsArray) {
            [int]($checksumArray | Measure-Object).Count
        } else {
            [int]0
        }
    }
    for ($artifactBudgetPass = 0; $artifactBudgetPass -lt 2; $artifactBudgetPass++) {
        $draftReportJson = $report | ConvertTo-Json -Depth 30
        $report.artifactBudgets = Test-GeneratedArtifactBudgets -ExpectedReadme $ExpectedReadme -ExpectedProjectsJson $ExpectedProjects -ExpectedAssets $ExpectedAssets -ReportJson $draftReportJson
    }
    $reportSchemaValidation = Test-JsonSchemaContract -Value $report -SchemaPath $ReportSchemaPath
    $schemaValidation = [ordered]@{
        passed = [bool]($feedSchemaValidation.passed -and $reportSchemaValidation.valid)
        catalog = $feedSchemaValidation.catalog
        projects = $feedSchemaValidation.projects
        report = $reportSchemaValidation
    }
    $report.schemaValidation = $schemaValidation

    $failureConditions = [ordered]@{
        readmeInSync = [bool](-not $readmeInSync)
        projectsExportInSync = [bool](-not $projectsInSync)
        profileAssetsInSync = [bool](-not $assetsInSync)
        catalogShape = [bool]($catalogShape.passed -ne $true)
        metadataDrift = [bool]($metadataDriftResult.fatalCount -gt 0)
        missingPublic = [bool](@($missingPublic | Where-Object { $null -ne $_ }).Count -gt 0)
        privateViolations = [bool](@($privateViolations | Where-Object { $null -ne $_ }).Count -gt 0)
        medicalViolations = [bool](@($medicalViolations | Where-Object { $null -ne $_ }).Count -gt 0)
        urlSchemeViolations = [bool](@($urlSchemeViolations | Where-Object { $null -ne $_ }).Count -gt 0)
        orphanedSuppressed = [bool](@($orphanedSuppressed | Where-Object { $null -ne $_ }).Count -gt 0)
        redirects = [bool](@($redirects | Where-Object { $null -ne $_ }).Count -gt 0)
        linkFailures = [bool](@($linkFailures | Where-Object { $null -ne $_ }).Count -gt 0)
        readmeExperience = [bool]($experienceChecks["passed"] -ne $true)
        communityHealth = [bool]($repositoryCommunityBaseline["communityHealth"]["fatalCount"] -gt 0)
        catalogFeedAccounting = [bool]($catalogFeedAccounting.fatalCount -gt 0)
        portfolioCompatibility = [bool]($portfolioCompatibility.fatalCount -gt 0)
        schemaValidation = [bool]($schemaValidation.passed -ne $true)
        docVersionConsistency = [bool]($docVersionConsistency.passed -ne $true)
    }
    $failed = $failureConditions.Values -contains $true
    return [ordered]@{
        Failed = $failed
        FailureConditions = $failureConditions
        Report = $report
    }
}

# Test seam: when dot-sourced (e.g. by Pester), load the functions above and stop
# before running the live-metadata fetch / generation below.
if ($MyInvocation.InvocationName -eq '.') { return }

Set-Location $RepoRoot

if ($SeedCatalog) {
    $seedGuard = Test-SeedCatalogGuard -SeedRequested ([bool]$SeedCatalog) -ForceRequested ([bool]$ForceSeedCatalog)
    if (-not $seedGuard.allowed) {
        Write-Error $seedGuard.message
        exit 1
    }
    Write-Warning "LOSSY LEGACY SEED MODE: $($seedGuard.message -replace '^-SeedCatalog is a ', '')"
}

$repos = if ($Offline) { @() } else { Add-LiveRepositoryMetadata -Repos (Get-GitHubRepos) }

if ($SeedCatalog) {
    $catalog = New-CatalogFromReadme -Repos $repos
    $catalogDir = Split-Path -Parent $CatalogPath
    if ($catalogDir -and -not (Test-Path -LiteralPath $catalogDir)) {
        New-Item -ItemType Directory -Path $catalogDir | Out-Null
    }
    $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $CatalogPath -Encoding utf8
    Write-Host "Seeded $CatalogPath with $($catalog.entries.Count) entries."
    if (-not $Write -and -not $Check) {
        exit 0
    }
}

$contributionCalendar = Get-ContributionCalendar

$catalogForRun = if (Test-Path -LiteralPath $CatalogPath) {
    Get-Catalog -Path $CatalogPath
} elseif ($SeedCatalog) {
    Get-Catalog -Path $CatalogPath
} else {
    $null
}

if ($catalogForRun -and ($Write -or $Check)) {
    $expected = New-Readme -Catalog $catalogForRun -Repos $repos
    $expectedProjects = New-ProjectsExportJson -Catalog $catalogForRun -Repos $repos
    $expectedAssets = New-ProfileAssetSvgs -Catalog $catalogForRun -Repos $repos -ContributionCalendar $contributionCalendar

    if ($Write) {
        $readmeFullPath = if ([System.IO.Path]::IsPathRooted($ReadmePath)) { $ReadmePath } else { Join-Path $RepoRoot $ReadmePath }
        $projectsFullPath = if ([System.IO.Path]::IsPathRooted($ProjectsPath)) { $ProjectsPath } else { Join-Path $RepoRoot $ProjectsPath }
        [System.IO.File]::WriteAllText($readmeFullPath, $expected, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($projectsFullPath, $expectedProjects + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        foreach ($assetPath in @($expectedAssets.Keys)) {
            $fullPath = if ([System.IO.Path]::IsPathRooted($assetPath)) { $assetPath } else { Join-Path $RepoRoot $assetPath }
            $assetDir = Split-Path -Parent $fullPath
            if ($assetDir -and -not (Test-Path -LiteralPath $assetDir)) {
                New-Item -ItemType Directory -Path $assetDir | Out-Null
            }
            [System.IO.File]::WriteAllText($fullPath, [string]$expectedAssets[$assetPath] + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        }
        Write-Host "Wrote $ReadmePath from $CatalogPath."
        Write-Host "Wrote $ProjectsPath from $CatalogPath."
        Write-Host "Wrote profile assets to $AssetsPath."
    }

    if ($Check) {
        $result = Test-ProfileState -Catalog $catalogForRun -Repos $repos -ExpectedReadme $expected -ExpectedProjects $expectedProjects -ExpectedAssets $expectedAssets -SkipLinkValidation:$SkipLinkValidation
        $reportDir = Split-Path -Parent $ReportPath
        if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir | Out-Null
        }
        $result.Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReportPath -Encoding utf8

        if ($result["Failed"] -eq $true) {
            Write-Error "Profile sync check failed. See $ReportPath."
            exit 1
        }

        Write-Host "Profile sync check passed. Report: $ReportPath"
        # Keep hosted shells from surfacing handled native-command failures.
        exit 0
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
        $topicOutput = $topicPayload | gh api "repos/$Owner/$repoName/topics" -X PUT --input - 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to apply topics to $repoName (exit code $LASTEXITCODE): $topicOutput"
        } else {
            $applied++
        }
    }
    Write-Host "Topic apply complete: $applied applied, $skipped skipped."
}
