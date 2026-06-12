#Requires -Version 7.0
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
    [string]$AssetsPath = "assets/profile",
    [switch]$SkipLinkValidation,
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
Set-Location $RepoRoot

if (-not $SeedCatalog -and -not $Write -and -not $Check) {
    $Check = $true
}

$Owner = "SysAdminDoc"
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
$ReportJsonSoftLimitBytes = 112KB
$ProfileAssetsSoftLimitBytes = 128KB
$ProfileAssetsCountSoftLimit = 16
$RenderedSmokeMinimumRootClientWidth = 300
$StaleProjectPushedAtReviewDays = 365
$StaleProjectReleaseReviewDays = 540
$ArchiveProjectPushedAtReviewDays = 730
$RequiredStatusCheckCandidates = @(
    [ordered]@{ name = "Pester (offline)"; workflow = ".github/workflows/tests.yml" },
    [ordered]@{ name = "PSScriptAnalyzer"; workflow = ".github/workflows/tests.yml" },
    [ordered]@{ name = "Markdownlint"; workflow = ".github/workflows/tests.yml" },
    [ordered]@{ name = "Windows setup smoke"; workflow = ".github/workflows/tests.yml" },
    [ordered]@{ name = "Check generated README"; workflow = ".github/workflows/profile-sync.yml" },
    [ordered]@{ name = "zizmor"; workflow = ".github/workflows/workflow-security.yml" }
)
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

$CategoryDefinitions = @(
    [ordered]@{
        Slug = "powershell"
        Title = "&#9889; PowerShell System Utilities"
        Summary = '<summary><b>&#9889; PowerShell System Utilities</b> -- {0} repos -- <i>Requires Git (see <b>First-time setup</b> above).</i></summary>'
        Render = "code"
        DefaultInstallKind = "powershell"
    },
    [ordered]@{
        Slug = "python"
        Title = "&#128013; Python Desktop Applications"
        Summary = '<summary><b>&#128013; Python Desktop Applications</b> -- {0} repos -- <i>Requires Python 3.8+ and Git (see <b>First-time setup</b> above). Each one-liner shallow-clones the repo to <code>$env:TEMP</code>, installs <code>requirements.txt</code> if present, then runs the entry script.</i></summary>'
        Render = "code"
        DefaultInstallKind = "python"
    },
    [ordered]@{
        Slug = "web"
        Title = "&#127760; Web Applications"
        Summary = '<summary><b>&#127760; Web Applications</b> -- {0} repos -- <i>Click to open in browser, no install needed.</i></summary>'
        Render = "web-table"
    },
    [ordered]@{
        Slug = "extensions"
        Title = "&#129513; Browser Extensions & Userscripts"
        Summary = '<summary><b>&#129513; Browser Extensions & Userscripts</b> -- {0} repos -- <i>Requires <a href="https://www.tampermonkey.net/">Tampermonkey</a> or <a href="https://violentmonkey.github.io/">Violentmonkey</a>.</i></summary>'
        Render = "install-table"
    },
    [ordered]@{
        Slug = "android"
        Title = "&#128241; Android Applications"
        Summary = '<summary><b>&#128241; Android Applications</b> -- {0} repos -- <i>Kotlin / Material You</i></summary>'
        Render = "download-table"
        DefaultDownloadKind = "apk"
    },
    [ordered]@{
        Slug = "security"
        Title = "&#128274; Security & Networking"
        Summary = '<summary><b>&#128274; Security & Networking</b> -- {0} repos</summary>'
        Render = "download-table"
    },
    [ordered]@{
        Slug = "media"
        Title = "&#127916; Media & Conversion Tools"
        Summary = '<summary><b>&#127916; Media & Conversion Tools</b> -- {0} repos</summary>'
        Render = "code"
        DefaultInstallKind = "python"
    },
    [ordered]@{
        Slug = "desktop"
        Title = "&#128421;&#65039; Native Desktop Applications"
        Summary = '<summary><b>&#128421;&#65039; Native Desktop Applications</b> -- {0} repos</summary>'
        Render = "desktop-table"
    },
    [ordered]@{
        Slug = "guides"
        Title = "&#128218; Guides & Resources"
        Summary = '<summary><b>&#128218; Guides & Resources</b> -- {0} repos</summary>'
        Render = "simple-table"
    },
    [ordered]@{
        Slug = "misc"
        Title = "&#128256; Misc & Forks"
        Summary = '<summary><b>&#128256; Misc & Forks</b> -- {0} repos</summary>'
        Render = "simple-table"
    }
)

function ConvertTo-CategorySlug {
    param([string]$SummaryLine)

    if ($SummaryLine -match 'PowerShell System Utilities') { return "powershell" }
    if ($SummaryLine -match 'Python Desktop Applications') { return "python" }
    if ($SummaryLine -match 'Web Applications') { return "web" }
    if ($SummaryLine -match 'Browser Extensions') { return "extensions" }
    if ($SummaryLine -match 'Android Applications') { return "android" }
    if ($SummaryLine -match 'Security & Networking') { return "security" }
    if ($SummaryLine -match 'Media & Conversion Tools') { return "media" }
    if ($SummaryLine -match 'Native Desktop Applications') { return "desktop" }
    if ($SummaryLine -match 'Guides & Resources') { return "guides" }
    if ($SummaryLine -match 'Misc & Forks') { return "misc" }
    return $null
}

function Get-GitHubReposFromRest {
    if ($Offline) {
        return @()
    }

    $repoJson = & gh api --paginate --slurp "users/$Owner/repos?per_page=100" 2>&1
    $repoOutput = (($repoJson | Out-String).Trim())
    if ($LASTEXITCODE -ne 0) {
        throw "REST repo metadata fallback failed while enumerating repos. Last gh output: $repoOutput"
    }

    $allRepos = New-Object System.Collections.Generic.List[object]
    foreach ($repo in @(ConvertFrom-RestRepoPageJson -Json $repoOutput)) {
        if (-not [bool](Get-MemberValue -Object $repo -Name "archived") -and -not [bool](Get-MemberValue -Object $repo -Name "private")) {
            $allRepos.Add($repo)
        }
    }

    $authenticated = Test-GitHubCliAuthenticated
    $releaseBudget = Test-RestFallbackReleaseFetchBudget -RepoCount $allRepos.Count -Authenticated $authenticated
    $script:RestFallbackReleaseFetchState = New-RestFallbackReleaseFetchState `
        -Used `
        -Status "preflight-passed" `
        -RepoCount $allRepos.Count `
        -Authenticated:$authenticated `
        -MaxReleaseFetches $releaseBudget.maxReleaseFetches `
        -UnauthenticatedReleaseFetchLimit $releaseBudget.unauthenticatedReleaseFetchLimit
    if (-not $releaseBudget.allowed) {
        $script:RestFallbackReleaseFetchState["status"] = "preflight-blocked"
        $script:RestFallbackReleaseFetchState["fatal"] = $true
        $script:RestFallbackReleaseFetchState["abortMessage"] = $releaseBudget.message
        throw $releaseBudget.message
    }

    $mapped = New-Object System.Collections.Generic.List[object]
    foreach ($repo in $allRepos) {
        $release = $null
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        if ([string]::IsNullOrWhiteSpace($repoName)) {
            continue
        }
        $script:RestFallbackReleaseFetchState["attemptedReleaseFetches"] = [int]$script:RestFallbackReleaseFetchState["attemptedReleaseFetches"] + 1
        $releaseJson = & gh api "repos/$Owner/$repoName/releases/latest" 2>&1
        $releaseOutput = (($releaseJson | Out-String).Trim())
        if ($LASTEXITCODE -eq 0) {
            $script:RestFallbackReleaseFetchState["successfulReleaseFetches"] = [int]$script:RestFallbackReleaseFetchState["successfulReleaseFetches"] + 1
            if (-not [string]::IsNullOrWhiteSpace($releaseOutput)) {
                $releaseData = $releaseOutput | ConvertFrom-Json
                $assetNames = @(Get-ReleaseAssetNamesFromApiRelease -Release $releaseData)
                $release = [pscustomobject]@{
                    tagName = Get-MemberValue -Object $releaseData -Name "tag_name"
                    url = Get-MemberValue -Object $releaseData -Name "html_url"
                    name = Get-MemberValue -Object $releaseData -Name "name"
                    publishedAt = Get-MemberValue -Object $releaseData -Name "published_at"
                    releaseAssetNames = $assetNames
                    releaseAssetKinds = @(Get-ReleaseAssetKinds -AssetNames $assetNames)
                    assetApiInspected = $true
                }
            }
        } elseif (-not (Test-GhApiNotFound -Output $releaseOutput)) {
            $script:RestFallbackReleaseFetchState["status"] = "aborted"
            $script:RestFallbackReleaseFetchState["fatal"] = $true
            $script:RestFallbackReleaseFetchState["abortRepo"] = $repoName
            $script:RestFallbackReleaseFetchState["abortHttpStatus"] = Get-GhApiHttpStatus -Output $releaseOutput
            $script:RestFallbackReleaseFetchState["abortMessage"] = "Latest-release fetch failed after $($script:RestFallbackReleaseFetchState["attemptedReleaseFetches"]) attempted request(s)."
            Write-Warning "REST release fallback failed for $repoName; aborting to avoid partial release metadata. Last gh output: $releaseOutput"
            throw "REST repo metadata fallback failed while fetching latest release for $repoName. Refusing to emit partial release metadata."
        } else {
            $script:RestFallbackReleaseFetchState["noRelease404Count"] = [int]$script:RestFallbackReleaseFetchState["noRelease404Count"] + 1
        }

        $mapped.Add((ConvertFrom-RestRepoMetadata -Repo $repo -Release $release))
    }

    $script:RepositoryMetadataProvider = "rest-fallback"
    $script:RepositoryEnumerationRequestedLimit = 0
    $script:RepositoryEnumerationTruncated = $false
    $script:RestFallbackReleaseFetchState["status"] = "completed"
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
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN) -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        return $true
    }

    $null = & gh auth status -h github.com 2>&1
    return ($LASTEXITCODE -eq 0)
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
        "--json", "name,description,stargazerCount,defaultBranchRef,latestRelease,licenseInfo,isFork,parent,isPrivate,visibility,isArchived,repositoryTopics,pushedAt,url,primaryLanguage"
    )
    $lastOutput = $null

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $output = & gh @ghArgs 2>&1
        $lastOutput = (($output | Out-String).Trim())

        if ($LASTEXITCODE -eq 0) {
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

    Write-Warning "GraphQL repo metadata failed after 3 attempts; using REST fallback. Last gh output: $lastOutput"
    return Get-GitHubReposFromRest
}

function Add-ReleaseAssetMetadata {
    param([object[]]$Repos)

    if ($Offline) {
        return @($Repos)
    }

    foreach ($repo in @($Repos | Sort-Object name)) {
        $release = Get-MemberValue -Object $repo -Name "latestRelease"
        if (-not $release) {
            continue
        }
        if (Test-ReleaseAssetMetadataInspected -Meta $repo) {
            continue
        }

        $repoName = Get-MemberValue -Object $repo -Name "name"
        if ([string]::IsNullOrWhiteSpace([string]$repoName)) {
            continue
        }

        $releaseJson = & gh api "repos/$Owner/$repoName/releases/latest" 2>&1
        $releaseOutput = (($releaseJson | Out-String).Trim())
        if ($LASTEXITCODE -ne 0) {
            Set-MemberValue -Object $release -Name "releaseAssetFetchError" -Value $releaseOutput
            Set-MemberValue -Object $release -Name "assetApiInspected" -Value $false
            continue
        }

        $releaseData = $releaseOutput | ConvertFrom-Json
        $assetNames = @(Get-ReleaseAssetNamesFromApiRelease -Release $releaseData)
        Set-MemberValue -Object $release -Name "releaseAssetNames" -Value $assetNames
        Set-MemberValue -Object $release -Name "releaseAssetKinds" -Value @(Get-ReleaseAssetKinds -AssetNames $assetNames)
        Set-MemberValue -Object $release -Name "assetApiInspected" -Value $true
    }

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

        $repoJson = & gh api "repos/$Owner/$repoName" 2>&1
        $repoOutput = (($repoJson | Out-String).Trim())
        if ($LASTEXITCODE -ne 0) {
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

function ConvertTo-Lookup {
    param([object[]]$Repos)

    $lookup = @{}
    foreach ($repo in $Repos) {
        $lookup[$repo.name.ToLowerInvariant()] = $repo
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

    $key = $Entry.repo.ToLowerInvariant()
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
        [bool]$AssetInspected
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
            $trustLevel = "checksum"
        }
        if ($signatureAssets.Count -gt 0) {
            $trustLevel = "signed"
        }
        if ($attestationAssets.Count -gt 0) {
            $trustLevel = "attested"
        }
        if ($signatureAssets.Count -gt 0 -and $attestationAssets.Count -gt 0) {
            $trustLevel = "signed-and-attested"
        }
    }

    return [ordered]@{
        checksumAssets = @($checksumAssets)
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
        notesPublic = if ($HasRelease -and $AssetInspected) { "Derived from release asset filenames; binaries were not downloaded or verified." } else { $null }
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
        $probeRows = $targetList | ForEach-Object -Parallel {
            function Test-ParallelHttpUrl {
                param([string]$Url, [int]$TimeoutSec = 12, [int]$Retries = 2)

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

            $target = $_
            $result = Test-ParallelHttpUrl -Url $target.url
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

    switch ($Slug) {
        "powershell" { return "PowerShell" }
        "python" { return "Python" }
        "web" { return "Web" }
        "extensions" { return "Extensions" }
        "android" { return "Android" }
        "security" { return "Security" }
        "media" { return "Media" }
        "desktop" { return "Desktop" }
        "guides" { return "Guides" }
        "misc" { return "Misc" }
        default { return $Slug }
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
        return "[<kbd>&#11015; $label</kbd>]($url)"
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

    return "Start with: $($links -join ', ')."
}

function New-DiscoverySection {
    param(
        [hashtable[]]$Entries,
        [object[]]$Repos
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $publicCount = if ($Repos.Count -gt 0) { $Repos.Count } else { ($Entries | Select-Object -ExpandProperty repo -Unique).Count }
    $releaseCount = @($Entries | Where-Object {
        $action = Get-PrimaryAction $_ (Get-RepoMeta $_ $repoLookup) $_.category
        $action["kind"] -eq "release"
    }).Count
    $liveCount = @($Entries | Where-Object {
        $action = Get-PrimaryAction $_ (Get-RepoMeta $_ $repoLookup) $_.category
        $action["kind"] -eq "live"
    }).Count
    $installCount = @($Entries | Where-Object {
        $action = Get-PrimaryAction $_ (Get-RepoMeta $_ $repoLookup) $_.category
        $action["kind"] -eq "install"
    }).Count
    $buildingCount = @($Entries | Where-Object { $_.currentlyBuilding -eq $true }).Count
    $powershellLink = New-CategoryLink "powershell"
    $desktopLink = New-CategoryLink "desktop"
    $extensionsLink = New-CategoryLink "extensions"
    $androidLink = New-CategoryLink "android"
    $webLink = New-CategoryLink "web"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("### Start Here")
    $lines.Add("")
    $lines.Add("| Need | Best path | Why |")
    $lines.Add("|:-----|:----------|:----|")
    $lines.Add("| A Windows utility you can run now | $powershellLink or $desktopLink | Copy a branch-pinned command or use a release download when one exists. |")
    $lines.Add("| Browser tools and userscripts | $extensionsLink | Install links stay pointed at releases or raw userscript URLs. |")
    $lines.Add("| Android apps | $androidLink | APK-ready projects show direct release actions; work-in-progress apps stay marked as repos. |")
    $lines.Add("| Live web tools | $webLink | Launch in-browser tools without local setup. |")
    $lines.Add("| The complete searchable catalog | [Full portfolio](https://sysadmindoc.github.io/) | Uses the generated project feed from this repo. |")
    $lines.Add("")
    $lines.Add("### Catalog Snapshot")
    $lines.Add("")
    $lines.Add("| Signal | Current state |")
    $lines.Add("|:-------|:--------------|")
    $lines.Add("| Public repos tracked | $publicCount |")
    $lines.Add("| README entries | $($Entries.Count) visitor-facing projects |")
    $lines.Add("| Primary actions | $releaseCount downloads, $liveCount launch links, $installCount userscript installs |")
    $lines.Add("| Active build queue | $buildingCount projects linked from the first screen |")
    $lines.Add("| Trust gates | Public-only links, medical/X-ray privacy guard, branch-pinned install snippets |")

    return ($lines -join [Environment]::NewLine)
}

function New-FirstTimeSetupSection {
    return @'
<details>
<summary><b>&#128190; First-time setup</b> -- <i>New to this? Install Python 3 + Git in one paste.</i></summary>
<br/>

The PowerShell and Python sections clone repos with **Git** and run scripts with **Python 3** when needed. On a fresh Windows machine, open **PowerShell** and paste:

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

Already have Python and Git? Skip this and open the category you need.

</details>
'@
}

function New-CategorySection {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup,
        [hashtable]$Definition
    )

    $items = @($Entries | Where-Object { $_.category -eq $Definition.Slug } | Sort-Object @{ Expression = { [int]$_.order } }, repo)
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
    $lines.Add("| Project | Category | Stars | Description | Action |")
    $lines.Add("|:--------|:---------|:-----:|:------------|:------:|")
    foreach ($entry in $featured) {
        $meta = Get-RepoMeta $entry $RepoLookup
        $stars = if ($meta) { [int]$meta.stargazerCount } else { 0 }
        $category = Get-CategoryDisplayName $entry.category
        $action = Get-ActionLink $entry $meta $entry.category
        $lines.Add("| [**$($entry.title)**]($(Get-RepoUrl $entry)) | $category | &#11088;$stars | $(Get-DisplayDescription $entry $meta) | $action |")
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
        $bg = "#0d1117"; $panel = "#161b22"; $border = "#30363d"; $titleColor = "#58a6ff"; $text = "#c9d1d9"; $muted = "#8b949e"; $accent = "#1f6feb"
    } else {
        $bg = "#ffffff"; $panel = "#f6f8fa"; $border = "#d0d7de"; $titleColor = "#0969da"; $text = "#24292f"; $muted = "#57606a"; $accent = "#0969da"
    }

    $baseId = ConvertTo-SvgId "$Title $Theme"
    $titleId = "$baseId-title"
    $descId = "$baseId-desc"
    $description = New-ProfilePanelDescription -Subtitle $Subtitle -Rows $Rows

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-labelledby=`"$titleId`" aria-describedby=`"$descId`">")
    $lines.Add("  <title id=`"$titleId`">$(ConvertTo-SvgText $Title)</title>")
    $lines.Add("  <desc id=`"$descId`">$(ConvertTo-SvgText $description)</desc>")
    $lines.Add("  <rect width=`"100%`" height=`"100%`" rx=`"0`" fill=`"$bg`"/>")
    $lines.Add("  <rect x=`"12`" y=`"12`" width=`"$($Width - 24)`" height=`"$($Height - 24)`" rx=`"8`" fill=`"$panel`" stroke=`"$border`"/>")
    $lines.Add("  <text x=`"32`" y=`"45`" fill=`"$titleColor`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"20`" font-weight=`"700`">$(ConvertTo-SvgText $Title)</text>")
    $lines.Add("  <text x=`"32`" y=`"70`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"13`">$(ConvertTo-SvgText $Subtitle)</text>")

    $rowY = 112
    $columns = 2
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
        $lines.Add("  <circle cx=`"$x`" cy=`"$($y - 6)`" r=`"4`" fill=`"$accent`"/>")
        $lines.Add("  <text x=`"$($x + 14)`" y=`"$y`" fill=`"$text`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"18`" font-weight=`"700`">$(ConvertTo-SvgText $value)</text>")
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
        [int]$Height = 220
    )

    if ($Theme -eq "dark") {
        $bg = "#0d1117"; $panel = "#161b22"; $border = "#30363d"; $titleColor = "#58a6ff"; $text = "#c9d1d9"; $muted = "#8b949e"; $accent = "#1f6feb"
    } else {
        $bg = "#ffffff"; $panel = "#f6f8fa"; $border = "#d0d7de"; $titleColor = "#0969da"; $text = "#24292f"; $muted = "#57606a"; $accent = "#0969da"
    }

    $title = "SysAdminDoc profile header"
    $description = "Static profile header for a healthcare IT engineer, DICOM/PACS specialist, and product builder."
    $baseId = ConvertTo-SvgId "$title $Theme"
    $titleId = "$baseId-title"
    $descId = "$baseId-desc"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-labelledby=`"$titleId`" aria-describedby=`"$descId`">")
    $lines.Add("  <title id=`"$titleId`">$(ConvertTo-SvgText $title)</title>")
    $lines.Add("  <desc id=`"$descId`">$(ConvertTo-SvgText $description)</desc>")
    $lines.Add("  <rect width=`"100%`" height=`"100%`" fill=`"$bg`"/>")
    $lines.Add("  <rect x=`"16`" y=`"16`" width=`"$($Width - 32)`" height=`"$($Height - 32)`" rx=`"8`" fill=`"$panel`" stroke=`"$border`"/>")
    $lines.Add("  <rect x=`"16`" y=`"16`" width=`"8`" height=`"$($Height - 32)`" fill=`"$accent`"/>")
    $lines.Add("  <text x=`"$([math]::Floor($Width / 2))`" y=`"78`" text-anchor=`"middle`" fill=`"$titleColor`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"42`" font-weight=`"700`">SysAdminDoc</text>")
    $lines.Add("  <text x=`"$([math]::Floor($Width / 2))`" y=`"116`" text-anchor=`"middle`" fill=`"$text`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"17`" font-weight=`"600`">Healthcare IT Engineer | DICOM/PACS Specialist | Product Builder</text>")
    $lines.Add("  <text x=`"$([math]::Floor($Width / 2))`" y=`"148`" text-anchor=`"middle`" fill=`"$muted`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"14`">16+ years in IT operations | public tools across PowerShell, Python, JavaScript, Kotlin, C#, C++, and Rust</text>")
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
    $lines.Add("  <path d=`"M0 74 C120 42 226 38 350 68 C482 100 610 94 820 48 L820 120 L0 120 Z`" fill=`"$waveOne`" stroke=`"$line`" stroke-width=`"1`"/>")
    $lines.Add("  <path d=`"M0 92 C156 56 282 58 420 84 C548 108 674 96 820 64 L820 120 L0 120 Z`" fill=`"$waveTwo`" opacity=`"0.35`"/>")
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

function New-ProfileAssetSvgs {
    param(
        [hashtable]$Catalog,
        [object[]]$Repos
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
        [ordered]@{ label = "active public repositories"; value = [string]$Repos.Count; detail = "live GitHub metadata" },
        [ordered]@{ label = "visitor-facing projects"; value = [string]$entries.Count; detail = "generated profile catalog" },
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
    $assets["$assetPathPrefix/footer-dark.svg"] = New-ProfileFooterSvg -Theme dark
    $assets["$assetPathPrefix/footer-light.svg"] = New-ProfileFooterSvg -Theme light
    return $assets
}

function New-ProfileChrome {
    $assetPathPrefix = ($AssetsPath -replace '\\', '/').TrimEnd('/')
    $headerImage = New-ThemeAwareImage -DarkUrl "$assetPathPrefix/header-dark.svg" -LightUrl "$assetPathPrefix/header-light.svg" -Alt 'SysAdminDoc - Healthcare IT Engineer, DICOM/PACS Specialist, Product Builder'

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
    $lines.Add('---')

    return ($lines -join [Environment]::NewLine)
}

function New-ProfileFooter {
    $assetPathPrefix = ($AssetsPath -replace '\\', '/').TrimEnd('/')
    return New-ThemeAwareImage -DarkUrl "$assetPathPrefix/footer-dark.svg" -LightUrl "$assetPathPrefix/footer-light.svg" -Alt "Decorative footer wave for the SysAdminDoc profile"
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
    param(
        [hashtable]$Catalog,
        [object[]]$Repos
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries | Where-Object {
        $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
    })
    $readme = Get-Content -LiteralPath $ReadmePath -Raw
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
    $publicCount = if ($Repos.Count -gt 0) { $Repos.Count } else { ($entries | Select-Object -ExpandProperty repo -Unique).Count }
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
        $blocks.Add((New-DiscoverySection -Entries $entries -Repos $Repos))
        $blocks.Add("")
        $blocks.Add("---")
        $blocks.Add("")
    }
    $blocks.Add((New-FeaturedSection -Entries $entries -RepoLookup $repoLookup))
    $blocks.Add("")
    $blocks.Add("---")
    $blocks.Add("")
    $blocks.Add((New-FirstTimeSetupSection))
    $blocks.Add("")

    foreach ($definition in $CategoryDefinitions) {
        $blocks.Add((New-CategorySection -Entries $entries -RepoLookup $repoLookup -Definition $definition))
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
        sourceRepository = "$Owner/$Owner"
        sourceCommit = Get-GitHeadCommit
        catalogSha256 = Get-RepoFileSha256 -RelativePath "data/profile-catalog.json"
        generatorSha256 = Get-RepoFileSha256 -RelativePath "scripts/sync-profile.ps1"
        projectSchemaSha256 = Get-RepoFileSha256 -RelativePath "schemas/profile-projects.v1.json"
        metadataSnapshotAt = $script:MetadataSnapshotAt
        metadataProvider = [string]$script:RepositoryMetadataProvider
        repoEnumeration = [ordered]@{
            requestedLimit = [int]$script:RepositoryEnumerationRequestedLimit
            returnedCount = [int]@($Repos).Count
            truncated = [bool]$script:RepositoryEnumerationTruncated
        }
    }
}

function New-ProjectsExportJson {
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
        $releaseTrust = New-ReleaseTrust `
            -AssetKinds $releaseAssetKinds `
            -AssetNames $releaseAssetNames `
            -HasRelease ([bool]($meta -and $meta.latestRelease)) `
            -AssetInspected $releaseAssetInspected

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
            hasDownload = [bool]($primaryAction["kind"] -eq "release")
            hasLiveDemo = [bool]($primaryAction["kind"] -eq "live")
            hasDirectInstall = [bool]($primaryAction["kind"] -eq "install")
            branch = Get-Branch $entry $meta
            entrypoint = if ([string]::IsNullOrWhiteSpace([string]$entry.entrypoint)) { $null } else { [string]$entry.entrypoint }
            installKind = if ([string]::IsNullOrWhiteSpace([string]$entry.installKind)) { $null } else { [string]$entry.installKind }
            language = if (-not [string]::IsNullOrWhiteSpace([string]$entry.language)) {
                [string]$entry.language
            } elseif ($meta -and $meta.primaryLanguage -and $meta.primaryLanguage.name) {
                [string]$meta.primaryLanguage.name
            } else {
                $null
            }
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
        publicRepoCount = $Repos.Count
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

    $requiredProjectFields = @("repo", "title", "category", "description", "repoUrl")
    $suppressedDisallowedFields = @(
        "repo",
        "title",
        "description",
        "repoUrl",
        "liveUrl",
        "installUrl",
        "downloadUrl",
        "primaryAction",
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
            redactedSuppressedRowsCompatible = $false
            provenanceAvailable = $false
            releaseTrustAvailable = $false
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

    $projectIndex = 0
    foreach ($project in $projects) {
        $projectIndex++
        $repo = [string](Get-MemberValue -Object $project -Name "repo")
        $repoLabel = if ([string]::IsNullOrWhiteSpace($repo)) { "project-$projectIndex" } else { $repo }
        foreach ($field in $requiredProjectFields) {
            $value = Get-MemberValue -Object $project -Name $field
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
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

    $missingFieldsArray = @($missingProjectFields.ToArray())
    $suppressedLeaksArray = @($suppressedIdentifierLeaks.ToArray())
    if ($missingFieldsArray.Count -gt 0) {
        $errors.Add("Portfolio project rows are missing downstream-required fields.")
    }
    if ($suppressedLeaksArray.Count -gt 0) {
        $errors.Add("Redacted suppressed feed rows expose project-identifying fields.")
    }

    $provenance = Get-MemberValue -Object $payload -Name "provenance"
    if ($null -eq $provenance) {
        $warnings.Add("Feed provenance is not available to downstream consumers.")
    }
    $releaseTrustAvailable = @($projects | Where-Object { $null -ne (Get-MemberValue -Object $_ -Name "releaseTrust") }).Count -eq $projects.Count
    if (-not $releaseTrustAvailable) {
        $warnings.Add("Not every visible project row exposes releaseTrust metadata.")
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
        redactedSuppressedRowsCompatible = [bool]($suppressedLeaksArray.Count -eq 0)
        provenanceAvailable = [bool]($null -ne $provenance)
        releaseTrustAvailable = $releaseTrustAvailable
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
    $readme = Get-Content -LiteralPath $ReadmePath -Raw
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
        }
        if ($line -match '^\| \[\*\*(?<title>.+?)\*\*\]\(https://github\.com/SysAdminDoc/(?<repo>[^)/]+)\) \| (?<category>.*?) \| &#11088;(?<stars>\d+) \| (?<description>.*?) \| (?<action>.*?) \|$') {
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
        $ExpectedReadme.Contains("assets/profile/activity-light.svg")
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
    $hasFeaturedActionColumn = $ExpectedReadme.Contains("| Project | Category | Stars | Description | Action |")
    $hasMinimalProfileHeader = $ExpectedReadme.TrimStart().StartsWith("**[View my full portfolio", [StringComparison]::Ordinal)
    $hasRichProfileHeader = $ExpectedReadme.Contains("### Professional Focus") -or
        $ExpectedReadme.Contains("Healthcare IT engineer and DICOM/PACS specialist") -or
        $ExpectedReadme.Contains("https://skillicons.dev") -or
        $profileStatsChromeCount -gt 0
    $hasCurrentlyBuildingActionColumn = ($building.Count -eq 0) -or
        (-not $ExpectedReadme.Contains("**Currently Building**")) -or
        $ExpectedReadme.Contains("| Project | Focus | Action |")
    $hasDiscoveryContract = ($hasStartHere -and $hasSnapshot -and $hasGeneratedNotice) -or
        ($hasMinimalProfileHeader -and -not $hasStartHere -and -not $hasSnapshot -and -not $hasGeneratedNotice)
    $hasProfileHeaderContract = ($hasRichProfileHeader -and $hasThemeAwareChrome -and $hasPlainTextTagline -and $hasMeaningfulAltText -and $profileStatsChromeCount -eq 1) -or
        ($hasMinimalProfileHeader -and -not $hasRichProfileHeader -and -not $hasPlainTextTagline -and $profileStatsChromeCount -eq 0)
    $passed = $hasDiscoveryContract -and $hasSetupInspectPath -and $hasFeaturedActionColumn -and $hasCurrentlyBuildingActionColumn -and
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
        thirdPartyMetricHostCount = $thirdPartyMetricHostCount
        thirdPartyBadgeHostCount = $thirdPartyBadgeHostCount
        thirdPartyRenderHostCount = $thirdPartyRenderHosts.Count
        thirdPartyRenderHosts = $thirdPartyRenderHosts
        motionSafeChrome = [bool]$motionSafeChrome
        motionPatternCount = $motionPatternCount
        profileStatsChromeCount = $profileStatsChromeCount
        featuredRows = $featured.Count
        featuredActionColumn = [bool]$hasFeaturedActionColumn
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
    param(
        [AllowNull()][object]$SmokeReport,
        [int]$MinimumRootClientWidth = $RenderedSmokeMinimumRootClientWidth
    )

    if ($null -eq $SmokeReport) {
        return [ordered]@{
            status = "not-run"
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
            warningCount = 0
            warnings = @()
        }
    }

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

    return [ordered]@{
        status = if ([bool](Get-MemberValue -Object $SmokeReport -Name "passed") -and $warnings.Count -eq 0) { "passed" } else { "warning" }
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
        warningCount = [int]$warnings.Count
        warnings = @($warnings.ToArray())
    }
}

function Test-CatalogShape {
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

    $output = & gh api $Path 2>&1
    $text = (($output | Out-String).Trim())
    if ($LASTEXITCODE -ne 0) {
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

function Get-CommunityLocalFileStatus {
    $checks = @(
        [ordered]@{ path = "README.md"; required = $true },
        [ordered]@{ path = "LICENSE"; required = $true },
        [ordered]@{ path = "SECURITY.md"; required = $true },
        [ordered]@{ path = ".github/CODEOWNERS"; required = $true },
        [ordered]@{ path = ".github/pull_request_template.md"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/broken-link.yml"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/profile-correction.yml"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/workflow-ci.yml"; required = $true },
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
        "SecurityPolicyID" {
            if ($SecurityPolicyHasLinkedReportingTarget) {
                $classification = "local-fix-pending-scorecard-refresh"
                $localDisposition = "fixed-locally"
                $localEvidence = "SECURITY.md includes a direct private vulnerability reporting URL."
                $nextAction = "Rerun the Scorecard workflow and verify the Security-Policy alert closes or score improves."
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
            $localEvidence = "The live language mix is PowerShell-only; CodeQL is not applicable, while PSScriptAnalyzer, actionlint, zizmor, and Scorecard SARIF run locally or in CI."
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
    $externalGatedCount = @($rows | Where-Object { $_.classification -in @("external-gated-pr-delivery", "external-gated-reviewer-model", "external-program-optional") }).Count
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
    return [ordered]@{
        available = $true
        workflow = ".github/workflows/profile-sync.yml"
        workflowName = "Profile sync"
        mode = "dry-run-pr"
        event = "workflow_dispatch"
        branch = "main"
        headSha = "f6cd6b970a1d92c5a13cac2b1c9abac031fab257"
        runId = [long]27084524165
        runUrl = "https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27084524165"
        createdAt = "2026-06-07T06:06:38Z"
        conclusion = "success"
        jobName = "Preview generated README PR"
        jobId = [long]79936227891
        failedStep = $null
        previewStepReached = $true
        reportArtifactUploaded = $true
        artifactReadinessStatus = "needs-live-validation"
        artifactReadinessBlockedCount = 0
        artifactReadinessNeedsLiveValidationCount = 3
        evidenceSummary = "Manual hosted dry-run completed Regenerate profile, summary, artifact upload, and Preview pull request after workflow artifact-runtime and summary-size guard updates. The helper planned automation/profile-sync-27084524165 without creating a branch, commit, push, pull request, or validation dispatch."
        nextAction = "Keep refreshing this evidence after dry-run workflow changes; continue resolving live PR delivery and required-check preconditions before enforcement."
    }
}

function Get-GeneratedPrWriteEvidence {
    return [ordered]@{
        available = $true
        workflow = ".github/workflows/profile-sync.yml"
        workflowName = "Profile sync"
        mode = "write-pr"
        event = "workflow_dispatch"
        branch = "main"
        headSha = "c3aeeb237b4e82bee169591a0f6a20d499719a73"
        runId = [long]27087776182
        runUrl = "https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27087776182"
        createdAt = "2026-06-07T08:47:24Z"
        conclusion = "success"
        jobName = "Open generated README PR"
        jobId = [long]79945465863
        failedStep = $null
        regenerateStepPassed = $true
        reportArtifactUploaded = $true
        artifactId = [long]7462507030
        generatedBranch = "automation/profile-sync-27087776182"
        generatedBranchPushed = $true
        generatedBranchCleanup = "deleted-after-validation-success"
        pullRequestCreated = $true
        pullRequestUrl = "https://github.com/SysAdminDoc/SysAdminDoc/pull/10"
        pullRequestNumber = [int]10
        pullRequestState = "closed"
        validationDispatched = $true
        validationRunId = [long]27087806797
        validationRunUrl = "https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27087806797"
        validationConclusion = "success"
        validationFailedStep = $null
        validationArtifactId = [long]7462523830
        validationSmokeArtifactId = [long]7462524019
        generatedBranchCheckRunCount = [int]4
        generatedBranchSuccessfulCheckRunCount = [int]2
        pullRequestCheckRollupCount = [int]1
        pullRequestChecksAttached = $true
        pullRequestCheckRollupNote = "PR #10 statusCheckRollup contained StatusContext generated-profile/validation with state SUCCESS and target https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27087806797."
        statusHandoffImplemented = $true
        statusHandoffContext = "generated-profile/validation"
        statusHandoffApi = "commit-statuses"
        statusHandoffPermission = "statuses: write"
        statusHandoffPendingPublisher = "scripts/open-generated-profile-pr.ps1"
        statusHandoffFinalPublisher = ".github/workflows/profile-sync.yml generated-validation-status job"
        statusHandoffProof = "pr-status-rollup-success"
        statusHandoffState = "success"
        statusHandoffTargetUrl = "https://github.com/SysAdminDoc/SysAdminDoc/actions/runs/27087806797"
        statusHandoffDescription = "Generated profile validation success."
        blocker = "Required-check enforcement still needs a documented direct-main maintenance bypass or a broader PR-delivery switch before admin-enforced required checks can be enabled."
        evidenceSummary = "Hosted write-pr drill 27087776182 ran on c3aeeb2, continued past the workflow-permissions endpoint 403, committed 7e1ea63 to automation/profile-sync-27087776182, pushed the branch, published generated-profile/validation as pending, created PR #10, and dispatched Profile sync validation run 27087806797. Validation used sync-profile.ps1 -Write -Check, passed, uploaded profile-sync-report artifact 7462523830 and rendered-profile-smoke artifact 7462524019, then the generated-validation-status job updated generated-profile/validation to success. PR #10 statusCheckRollup and gh pr checks both reported generated-profile/validation as passing, then PR #10 was closed and the generated branch was deleted after evidence collection."
        nextAction = "Document or implement the direct-main maintenance bypass/PR-delivery policy needed before enabling admin-enforced required-check protection."
    }
}

function Get-GeneratedPrCredentialDecision {
    param(
        [Nullable[bool]]$ActionsPullRequestCreationAllowed
    )

    $settingAllowsGeneratedPr = Get-NullableBool $ActionsPullRequestCreationAllowed
    $status = if ($settingAllowsGeneratedPr -eq $true) {
        "setting-enabled"
    } else {
        "decision-recorded"
    }
    $nextAction = if ($settingAllowsGeneratedPr -eq $true) {
        "Use the proven generated-profile/validation PR status handoff as the generated-maintenance path, then document the direct-main maintenance bypass or PR-delivery policy before required-check enforcement."
    } else {
        "Enable the repository Actions pull-request creation setting, rerun hosted write-pr, and verify generated pull-request creation plus branch-scoped validation before required-check enforcement."
    }

    return [ordered]@{
        status = $status
        selectedPath = "enable-actions-pr-creation"
        rejectedPath = "approved-github-app-or-pat-token"
        rationale = "The manual generated-PR job already scopes write privileges to actions:write, contents:write, and pull-requests:write; enabling the repository setting avoids adding a long-lived automation secret."
        requiresRepositorySetting = $true
        requiresNewSecret = $false
        currentSettingAllowsGeneratedPr = $settingAllowsGeneratedPr
        decisionDocumentPath = "decision:generated-pr-credential"
        activationCommand = "gh api -X PUT repos/SysAdminDoc/SysAdminDoc/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true"
        nextAction = $nextAction
    }
}

function Test-RequiredCheckWorkflowCoverage {
    param(
        [object[]]$Candidates = $RequiredStatusCheckCandidates
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $workflowRows = New-Object System.Collections.Generic.List[object]
    $workflowPaths = @($Candidates | ForEach-Object { [string](Get-MemberValue -Object $_ -Name "workflow") } | Sort-Object -Unique)

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
    param(
        [object[]]$Candidates = $RequiredStatusCheckCandidates
    )

    $candidateNames = @($Candidates | ForEach-Object { [string](Get-MemberValue -Object $_ -Name "name") })
    $workflowNames = @($Candidates | ForEach-Object { [string](Get-MemberValue -Object $_ -Name "workflow") } | Sort-Object -Unique)

    return [ordered]@{
        status = "completed"
        readinessStatus = "ready"
        requiredBeforeEnforcement = $true
        purpose = "refresh-recent-check-run-proof"
        disposableBranchPrefix = "automation/required-check-proof-"
        pullRequestTitle = "chore: exercise required-check candidates"
        candidateCheckCount = $candidateNames.Count
        candidateChecks = @($candidateNames)
        workflowCount = $workflowNames.Count
        workflows = @($workflowNames)
        touchPaths = @(
            "README.md",
            ".github/workflows/tests.yml",
            "setup.ps1"
        )
        nonMutationPolicy = "Open a disposable PR only for check creation proof, do not merge it, do not enable branch protection or rulesets, then close the PR and delete the proof branch after evidence collection."
        expectedPrChecks = @(
            "Pester (offline)",
            "PSScriptAnalyzer",
            "Markdownlint",
            "Windows setup smoke",
            "Check generated README",
            "zizmor"
        )
        verificationSteps = @(
            "Create a temporary branch from current main with prefix automation/required-check-proof-.",
            "Make a no-risk proof commit that touches README.md, .github/workflows/tests.yml, and setup.ps1 while preserving generated profile output.",
            "Open a disposable pull request and wait for all candidate checks to appear in the PR check rollup.",
            "Verify pull_request and merge_group-capable workflow check names match the candidate list.",
            "Close the disposable pull request and delete the proof branch after recording run IDs and check conclusions."
        )
        cleanupRequired = $true
        evidenceStatus = "passed"
        documentationPath = "decision:pr-delivery-transition-checklist"
        nextAction = "Keep this proof fresh before enforcement; routine PR delivery is now proven by PR #14."
    }
}

function Get-CandidateCheckExerciseEvidence {
    return [ordered]@{
        available = $true
        status = "passed"
        evidenceStatus = "successful"
        pullRequestNumber = 13
        pullRequestUrl = "https://github.com/SysAdminDoc/SysAdminDoc/pull/13"
        pullRequestState = "closed"
        branch = "automation/required-check-proof-20260607-125"
        headSha = "b67e1f1fc3ec70cf6a91b4d1a0c5f71d52d1fb79"
        mergeSha = "24b6a49dbe03f82f6c794b79f953fdf04190febe"
        workflowRunIds = @(
            27090100279,
            27090100281,
            27090100282
        )
        profileSyncRunId = 27090100279
        testsRunId = 27090100282
        workflowSecurityRunId = 27090100281
        profileSyncArtifactId = 7463321333
        expectedCandidateCheckCount = 6
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
        failureReason = ""
        cleanupState = "closed-pr-and-deleted-branch"
        evidenceSummary = "Disposable PR #13 created all six candidate required-check names. Check generated README, PSScriptAnalyzer, Pester (offline), Markdownlint, Windows setup smoke, and zizmor passed. The PR was closed and automation/required-check-proof-20260607-125 was deleted after evidence collection."
        nextAction = "Keep this proof fresh before enabling required-check enforcement; refresh it if GitHub's recent-check selection window expires."
    }
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
                -Status "ready" `
                -Summary "Each required check must have a recent successful run in this repository before it can be selected." `
                -Evidence "Disposable PR #13 created all six candidate checks and every candidate check completed successfully." `
                -NextAction "Refresh this disposable PR proof if GitHub's recent-check selection window expires before enforcement."))

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
        "Repository workflow permissions currently block GITHUB_TOKEN pull-request creation; hosted write-pr drill 27085061539 failed at createPullRequest after pushing a disposable generated branch that was later deleted."
    } elseif ($null -eq $ActionsPullRequestCreationAllowed) {
        "Hosted write-pr drill 27086351848 showed GITHUB_TOKEN cannot read the repository workflow-permissions endpoint, so the helper must continue to gh pr create when that specific preflight read is unavailable."
    } elseif ($routinePrDrillPassed) {
        "Routine maintenance PR #14 merged by rebase after Check generated README, PSScriptAnalyzer, Pester (offline), Markdownlint, Windows setup smoke, and zizmor all passed. The proof branch was deleted after merge."
    } elseif ($EnforceAdmins -eq $true) {
        "Hosted write-pr run 27087776182 opened PR #10, dispatched validation run 27087806797, and proved generated-profile/validation appears in PR statusCheckRollup as success. Protected main still enforces admins, so routine maintenance is selected for PR delivery and needs a live merge drill before enforcement."
    } else {
        "Admin enforcement is not confirmed as blocking, but the delivery path still needs a live PR or documented bypass drill."
    }
    $deliveryNextAction = if ($ActionsPullRequestCreationAllowed -eq $false) {
        "Enable GitHub Actions pull-request creation for GITHUB_TOKEN or switch the helper to an approved GitHub App/PAT credential before rerunning generated PR delivery."
    } elseif ($null -eq $ActionsPullRequestCreationAllowed) {
        "Rerun generated PR delivery with the preflight-unavailable fallback and verify gh pr create plus validation dispatch."
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
        [string]$DependabotSecurityUpdatesStatus,
        [string]$DependabotSecurityUpdatesUnavailableReason,
        [string]$RepositoryUnavailableReason,
        [string]$CommunityUnavailableReason,
        [string]$BranchProtectionUnavailableReason,
        [string]$RulesetsUnavailableReason,
        [string]$ActionsWorkflowPermissionsUnavailableReason,
        [string]$LanguagesUnavailableReason,
        [string]$ScorecardAlertsUnavailableReason
    )

    $repoWarnings = New-Object System.Collections.Generic.List[string]
    $communityWarnings = New-Object System.Collections.Generic.List[string]
    $communityErrors = New-Object System.Collections.Generic.List[string]

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
        if (-not $generatedPrCreationAllowed) {
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
    $activeCodeScanningControls = New-Object System.Collections.Generic.List[string]
    if ($secretScanning -eq "enabled") { $activeCodeScanningControls.Add("secret-scanning") }
    if ($secretScanningPushProtection -eq "enabled") { $activeCodeScanningControls.Add("secret-scanning-push-protection") }
    if ($dependabotSecurityUpdates -eq "enabled") { $activeCodeScanningControls.Add("dependabot-security-updates") }
    if ($psScriptAnalyzerWorkflowPresent) { $activeCodeScanningControls.Add("psscriptanalyzer") }
    if ($actionlintWorkflowPresent) { $activeCodeScanningControls.Add("actionlint") }
    if ($zizmorWorkflowPresent) { $activeCodeScanningControls.Add("zizmor") }
    if ($scorecardSarifUploadPresent) { $activeCodeScanningControls.Add("openssf-scorecard-sarif") }
    if ($codeQlWorkflowPresent) { $activeCodeScanningControls.Add("codeql-workflow") }
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
    if ($communityAvailable) {
        if (-not $communityIssueTemplate -and $localIssueForms -gt 0) {
            $communityWarnings.Add("GitHub community profile does not report issue-template detection even though local issue forms are present.")
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
                activeControls = @($activeCodeScanningControls.ToArray())
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
            recommendation = if ($actionsWorkflowPermissionsAvailable -and -not $generatedPrCreationAllowed) { "enable-actions-pr-creation-or-use-approved-automation-token" } elseif ($actionsWorkflowPermissionsAvailable) { "ready-for-generated-pr-delivery" } else { "verify-actions-workflow-permissions" }
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
        localRequiredMissingCount = $communityErrors.Count
        warningCount = $communityWarnings.Count
        warnings = $communityWarnings.ToArray()
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
            -ScorecardAlertsUnavailableReason "offline"
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
            -ScorecardAlertsUnavailableReason "gh authentication unavailable"
    }

    $repositoryResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner"
    $communityResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/community/profile"
    $branchProtectionResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/branches/main/protection"
    $rulesetsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/rulesets"
    $actionsWorkflowPermissionsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/actions/permissions/workflow"
    $languagesResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/languages"
    $scorecardAlertsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/code-scanning/alerts?tool_name=Scorecard&state=open&per_page=100"
    $dependabotSecurityUpdatesResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/automated-security-fixes"

    $repositoryValue = if ($repositoryResult["ok"]) { $repositoryResult["value"] } else { $null }
    $communityValue = if ($communityResult["ok"]) { $communityResult["value"] } else { $null }
    $branchProtectionValue = if ($branchProtectionResult["ok"]) { $branchProtectionResult["value"] } else { $null }
    $rulesetsValue = if ($rulesetsResult["ok"]) { @($rulesetsResult["value"]) } else { @() }
    $actionsWorkflowPermissionsValue = if ($actionsWorkflowPermissionsResult["ok"]) { $actionsWorkflowPermissionsResult["value"] } else { $null }
    $languagesValue = if ($languagesResult["ok"]) { $languagesResult["value"] } else { $null }
    $scorecardAlertsValue = if ($scorecardAlertsResult["ok"]) { @($scorecardAlertsResult["value"]) } else { $null }
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
        -DependabotSecurityUpdatesStatus $dependabotSecurityUpdatesValue `
        -DependabotSecurityUpdatesUnavailableReason $(if ($dependabotSecurityUpdatesResult["ok"]) { $null } else { $dependabotSecurityUpdatesResult["error"] }) `
        -RepositoryUnavailableReason $(if ($repositoryResult["ok"]) { $null } else { $repositoryResult["error"] }) `
        -CommunityUnavailableReason $(if ($communityResult["ok"]) { $null } else { $communityResult["error"] }) `
        -BranchProtectionUnavailableReason $(if ($branchProtectionResult["ok"]) { $null } else { $branchProtectionResult["error"] }) `
        -RulesetsUnavailableReason $(if ($rulesetsResult["ok"]) { $null } else { $rulesetsResult["error"] }) `
        -ActionsWorkflowPermissionsUnavailableReason $(if ($actionsWorkflowPermissionsResult["ok"]) { $null } else { $actionsWorkflowPermissionsResult["error"] }) `
        -LanguagesUnavailableReason $(if ($languagesResult["ok"]) { $null } else { $languagesResult["error"] }) `
        -ScorecardAlertsUnavailableReason $(if ($scorecardAlertsResult["ok"]) { $null } else { $scorecardAlertsResult["error"] })
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

function Test-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return [pscustomobject]@{ Exists = $false; Value = $null }
    }
    if ($Object -is [System.Collections.IDictionary]) {
        $exists = [bool]$Object.Contains($Name)
        $value = $null
        if ($exists) {
            $value = $Object[$Name]
        }
        $result = [pscustomobject]@{ Exists = $exists; Value = $null }
        $result.Value = $value
        return $result
    }

    $property = $Object.PSObject.Properties[$Name]
    $exists = [bool]($null -ne $property)
    $value = $null
    if ($property) {
        $value = $property.Value
    }
    $result = [pscustomobject]@{ Exists = $exists; Value = $null }
    $result.Value = $value
    return $result
}

function Get-JsonSchemaValueType {
    param([object]$Value)

    if ($null -eq $Value) { return "null" }
    if (Test-JsonArrayWrapper $Value) { return "array" }
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) { return "string" }
    if ($Value -is [bool]) { return "boolean" }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or $Value -is [int64]) { return "integer" }
    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        if ([double]$Value % 1 -eq 0) { return "integer" }
        return "number"
    }
    if ($Value -is [string]) { return "string" }
    if ($Value -is [array] -or $Value -is [System.Collections.IList]) { return "array" }
    return "object"
}

function Get-SchemaTypeList {
    param([object]$Schema)

    $typeInfo = Test-ObjectProperty -Object $Schema -Name "type"
    if (-not $typeInfo.Exists) {
        return @()
    }
    if ((Get-JsonSchemaValueType $typeInfo.Value) -eq "array") {
        return @(Get-JsonArrayItems $typeInfo.Value | ForEach-Object { [string]$_ })
    }
    return @([string]$typeInfo.Value)
}

function Resolve-JsonSchemaRef {
    param(
        [object]$RootSchema,
        [string]$Ref
    )

    if (-not $Ref.StartsWith("#/")) {
        throw "Only local JSON Schema refs are supported: $Ref"
    }
    $value = $RootSchema
    foreach ($segment in $Ref.Substring(2).Split('/')) {
        $name = ($segment -replace '~1', '/') -replace '~0', '~'
        $value = Get-MemberValue -Object $value -Name $name
        if ($null -eq $value) {
            throw "JSON Schema ref could not be resolved: $Ref"
        }
    }
    return $value
}

function Test-JsonSchemaNode {
    param(
        [object]$Value,
        [object]$Schema,
        [string]$Path = '$',
        [object]$RootSchema = $null
    )

    if ($null -eq $RootSchema) {
        $RootSchema = $Schema
    }
    $errors = New-Object System.Collections.Generic.List[string]

    if (@(Get-ObjectPropertyNames $Schema).Count -eq 0) {
        return $errors.ToArray()
    }

    $refInfo = Test-ObjectProperty -Object $Schema -Name '$ref'
    if ($refInfo.Exists) {
        try {
            $resolved = Resolve-JsonSchemaRef -RootSchema $RootSchema -Ref ([string]$refInfo.Value)
            foreach ($schemaError in @(Test-JsonSchemaNode -Value $Value -Schema $resolved -Path $Path -RootSchema $RootSchema)) {
                $errors.Add($schemaError)
            }
        } catch {
            $errors.Add("$Path schema ref error: $($_.Exception.Message)")
        }
        return $errors.ToArray()
    }

    $actualType = Get-JsonSchemaValueType $Value
    $allowedTypes = @(Get-SchemaTypeList $Schema)
    if ($allowedTypes.Count -gt 0) {
        $typeOk = $false
        foreach ($allowedType in $allowedTypes) {
            if ($allowedType -eq $actualType -or ($allowedType -eq "number" -and $actualType -eq "integer")) {
                $typeOk = $true
                break
            }
        }
        if (-not $typeOk) {
            $errors.Add("$Path expected type $($allowedTypes -join '/') but found $actualType")
            return $errors.ToArray()
        }
    }

    $constInfo = Test-ObjectProperty -Object $Schema -Name "const"
    if ($constInfo.Exists -and (ConvertTo-ComparableJson $Value) -ne (ConvertTo-ComparableJson $constInfo.Value)) {
        $errors.Add("$Path must equal $($constInfo.Value)")
    }

    $enumInfo = Test-ObjectProperty -Object $Schema -Name "enum"
    if ($enumInfo.Exists) {
        $matchesEnum = $false
        foreach ($allowed in @(Get-JsonArrayItems $enumInfo.Value)) {
            if ((ConvertTo-ComparableJson $Value) -eq (ConvertTo-ComparableJson $allowed)) {
                $matchesEnum = $true
                break
            }
        }
        if (-not $matchesEnum) {
            $errors.Add("$Path value is not in the allowed enum")
        }
    }

    if ($actualType -eq "string") {
        $format = Get-MemberValue -Object $Schema -Name "format"
        if ($format -eq "uri") {
            $uri = $null
            if (-not [System.Uri]::TryCreate([string]$Value, [System.UriKind]::Absolute, [ref]$uri)) {
                $errors.Add("$Path must be an absolute URI")
            }
        } elseif ($format -eq "date-time") {
            $parsedDate = [datetimeoffset]::MinValue
            if (-not [datetimeoffset]::TryParse([string]$Value, [ref]$parsedDate)) {
                $errors.Add("$Path must be an ISO date-time")
            }
        }

        $pattern = Get-MemberValue -Object $Schema -Name "pattern"
        if (-not [string]::IsNullOrWhiteSpace([string]$pattern) -and ([string]$Value) -notmatch ([string]$pattern)) {
            $errors.Add("$Path does not match pattern $pattern")
        }
    }

    if ($actualType -eq "integer" -or $actualType -eq "number") {
        $minimumInfo = Test-ObjectProperty -Object $Schema -Name "minimum"
        if ($minimumInfo.Exists -and [double]$Value -lt [double]$minimumInfo.Value) {
            $errors.Add("$Path must be >= $($minimumInfo.Value)")
        }
    }

    if ($actualType -eq "array") {
        $items = @(Get-JsonArrayItems $Value)
        $minItemsInfo = Test-ObjectProperty -Object $Schema -Name "minItems"
        if ($minItemsInfo.Exists -and $items.Count -lt [int]$minItemsInfo.Value) {
            $errors.Add("$Path must contain at least $($minItemsInfo.Value) item(s)")
        }
        $itemsSchema = Get-MemberValue -Object $Schema -Name "items"
        if ($itemsSchema) {
            for ($i = 0; $i -lt $items.Count; $i++) {
                foreach ($schemaError in @(Test-JsonSchemaNode -Value $items[$i] -Schema $itemsSchema -Path "$Path[$i]" -RootSchema $RootSchema)) {
                    $errors.Add($schemaError)
                }
            }
        }
    }

    if ($actualType -eq "object") {
        $required = @(Get-JsonArrayItems (Get-MemberValue -Object $Schema -Name "required"))
        foreach ($requiredName in $required) {
            $property = Test-ObjectProperty -Object $Value -Name ([string]$requiredName)
            if (-not $property.Exists) {
                $errors.Add("$Path.$requiredName is required")
            }
        }

        $properties = Get-MemberValue -Object $Schema -Name "properties"
        $allowedPropertyNames = @{}
        foreach ($propertyName in @(Get-ObjectPropertyNames $properties)) {
            $allowedPropertyNames[$propertyName] = $true
            $valueProperty = Test-ObjectProperty -Object $Value -Name $propertyName
            if ($valueProperty.Exists) {
                $propertySchema = Get-MemberValue -Object $properties -Name $propertyName
                foreach ($schemaError in @(Test-JsonSchemaNode -Value $valueProperty.Value -Schema $propertySchema -Path "$Path.$propertyName" -RootSchema $RootSchema)) {
                    $errors.Add($schemaError)
                }
            }
        }

        $additionalProperties = Get-MemberValue -Object $Schema -Name "additionalProperties"
        if ($additionalProperties -eq $false) {
            foreach ($propertyName in @(Get-ObjectPropertyNames $Value)) {
                if (-not $allowedPropertyNames.ContainsKey($propertyName)) {
                    $errors.Add("$Path.$propertyName is not allowed by the schema")
                }
            }
        }
    }

    return $errors.ToArray()
}

$script:SupportedSchemaKeywords = @(
    '$schema', '$id', '$ref', '$defs', 'definitions',
    'title', 'description',
    'type', 'const', 'enum', 'format', 'pattern',
    'minimum', 'minItems', 'items',
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
            $warnings.Add("$Path uses unsupported schema keyword '$name' — validation may be incomplete")
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
        foreach ($schemaError in @(Test-JsonSchemaNode -Value $Value -Schema $schema -Path '$' -RootSchema $schema)) {
            $errors.Add($schemaError)
        }
        $keywordWarnings = @(Test-SchemaKeywordCoverage -Schema $schema)
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

    $tagJson = & gh api "repos/$Repository/git/ref/tags/$TagName" 2>&1
    $tagOutput = (($tagJson | Out-String).Trim())
    if ($LASTEXITCODE -eq 0) {
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
        [string]$Field,
        [object]$OldValue,
        [object]$NewValue,
        [string]$Severity
    )

    return [ordered]@{
        repo = if ([string]::IsNullOrWhiteSpace($Repo)) { $null } else { $Repo }
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
        $drift.Add((New-MetadataDriftRecord -Repo $null -Field "projects.json" -OldValue "unreadable" -NewValue "valid generated feed" -Severity "fatal"))
    }

    try {
        $expected = $ExpectedProjectsJson | ConvertFrom-Json
    } catch {
        $drift.Add((New-MetadataDriftRecord -Repo $null -Field "expectedProjects" -OldValue "generated feed" -NewValue "unreadable" -Severity "fatal"))
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
                $drift.Add((New-MetadataDriftRecord -Repo $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "fatal"))
            }
        }

        $provenanceFatalFields = @(
            "provenance.version",
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
                $drift.Add((New-MetadataDriftRecord -Repo $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "fatal"))
            }
        }

        foreach ($field in @("provenance.sourceCommit", "provenance.metadataSnapshotAt")) {
            $oldValue = Get-NestedMemberValue -Object $current -Path $field
            $newValue = Get-NestedMemberValue -Object $expected -Path $field
            if ((ConvertTo-ComparableJson $oldValue) -ne (ConvertTo-ComparableJson $newValue)) {
                $drift.Add((New-MetadataDriftRecord -Repo $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "info"))
            }
        }

        $currentRows = New-MetadataRowIndex -ProjectsPayload $current
        $expectedRows = New-MetadataRowIndex -ProjectsPayload $expected
        $rowKeys = @(@($currentRows.Keys) + @($expectedRows.Keys) | Sort-Object -Unique)
        $infoFields = @("stars", "pushedAt", "topics")
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

            if (-not $hasCurrent) {
                $drift.Add((New-MetadataDriftRecord -Repo $repo -Field "row" -OldValue $null -NewValue "present" -Severity "fatal"))
                continue
            }
            if (-not $hasExpected) {
                $drift.Add((New-MetadataDriftRecord -Repo $repo -Field "row" -OldValue "present" -NewValue $null -Severity "fatal"))
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
                    $drift.Add((New-MetadataDriftRecord -Repo $repo -Field $field -OldValue $oldValue -NewValue $newValue -Severity $severity))
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
    $debugArtifactRows = New-Object System.Collections.Generic.List[object]
    $releaseAssetKindCounts = @{}
    $trustLevelCounts = @{}
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
        $releaseTrust = New-ReleaseTrust -AssetKinds $assetKinds -AssetNames $assetNames -HasRelease $hasRelease -AssetInspected $assetInspected
        $trustLevel = [string]$releaseTrust.trustLevel
        if (-not $trustLevelCounts.ContainsKey($trustLevel)) {
            $trustLevelCounts[$trustLevel] = 0
        }
        $trustLevelCounts[$trustLevel]++

        if ($hasRelease) {
            $releaseBearingRows++
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

    return [ordered]@{
        checkedCatalogRows = @($Entries).Count
        releaseBearingRows = $releaseBearingRows
        releaseActionRows = $releaseActionRows
        assetApiInspected = ($inspectedReleaseRows -gt 0)
        inspectedReleaseRows = $inspectedReleaseRows
        releaseAssetKindCounts = $kindCounts
        releaseTrustLevelCounts = $trustCounts
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

function Get-UserscriptContent {
    param([string]$Url)

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
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [string]$ExpectedReadme,
        [string]$ExpectedProjects,
        [string]$CurrentReadme,
        [string]$CurrentProjects,
        [hashtable]$ExpectedAssets = @{},
        [switch]$SkipLinkValidation
    )

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

    $currentReadme = if ($PSBoundParameters.ContainsKey("CurrentReadme")) {
        $CurrentReadme
    } else {
        Get-Content -LiteralPath $ReadmePath -Raw
    }
    $currentProjects = if ($PSBoundParameters.ContainsKey("CurrentProjects")) {
        $CurrentProjects
    } elseif (Test-Path -LiteralPath $ProjectsPath) {
        Get-Content -LiteralPath $ProjectsPath -Raw
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
    $assetsInSync = @($assetChecks | Where-Object { $_.inSync -ne $true }).Count -eq 0

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
    $readmeDensity = Test-ReadmeDensity -ExpectedReadme $ExpectedReadme -Entries $included -RepoLookup $repoLookup
    $artifactBudgets = Test-GeneratedArtifactBudgets -ExpectedReadme $ExpectedReadme -ExpectedProjectsJson $ExpectedProjects -ExpectedAssets $ExpectedAssets -ReportJson $null
    $renderedProfileSmoke = New-RenderedProfileSmokeSummary -SmokeReport $null
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
        readmeDensity = $readmeDensity
        artifactBudgets = $artifactBudgets
        renderedProfileSmoke = $renderedProfileSmoke
        readmeExperienceChecks = $experienceChecks
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

    $failed = (
        -not $readmeInSync -or
        -not $projectsInSync -or
        -not $assetsInSync -or
        $catalogShape.passed -ne $true -or
        $metadataDriftResult.fatalCount -gt 0 -or
        $missingPublic.Count -gt 0 -or
        $privateViolations.Count -gt 0 -or
        $medicalViolations.Count -gt 0 -or
        $urlSchemeViolations.Count -gt 0 -or
        $orphanedSuppressed.Count -gt 0 -or
        $redirects.Count -gt 0 -or
        $linkFailures.Count -gt 0 -or
        $experienceChecks["passed"] -ne $true -or
        $repositoryCommunityBaseline["communityHealth"]["fatalCount"] -gt 0 -or
        $catalogFeedAccounting.fatalCount -gt 0 -or
        $portfolioCompatibility.fatalCount -gt 0 -or
        $schemaValidation.passed -ne $true -or
        $docVersionConsistency.passed -ne $true
    )
    return [ordered]@{
        Failed = $failed
        Report = $report
    }
}

# Test seam: when dot-sourced (e.g. by Pester), load the functions above and stop
# before running the live-metadata fetch / generation below.
if ($MyInvocation.InvocationName -eq '.') { return }

if ($SeedCatalog) {
    $seedGuard = Test-SeedCatalogGuard -SeedRequested ([bool]$SeedCatalog) -ForceRequested ([bool]$ForceSeedCatalog)
    if (-not $seedGuard.allowed) {
        Write-Error $seedGuard.message
        exit 1
    }
    Write-Warning "LOSSY LEGACY SEED MODE: $($seedGuard.message -replace '^-SeedCatalog is a ', '')"
}

$repos = if ($Offline) { @() } else { Add-ReleaseAssetMetadata -Repos (Add-ForkParentMetadata -Repos (Get-GitHubRepos)) }

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

$catalogForRun = if (Test-Path -LiteralPath $CatalogPath) {
    Get-Catalog -Path $CatalogPath
} elseif ($SeedCatalog) {
    Get-Catalog -Path $CatalogPath
} else {
    $null
}

if ($catalogForRun) {
    $expected = New-Readme -Catalog $catalogForRun -Repos $repos
    $expectedProjects = New-ProjectsExportJson -Catalog $catalogForRun -Repos $repos
    $expectedAssets = New-ProfileAssetSvgs -Catalog $catalogForRun -Repos $repos

    if ($Write) {
        [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $ReadmePath).Path, $expected, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $RepoRoot $ProjectsPath), $expectedProjects + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        foreach ($assetPath in @($expectedAssets.Keys)) {
            $fullPath = Join-Path $RepoRoot $assetPath
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

        if ($result.Failed) {
            Write-Error "Profile sync check failed. See $ReportPath."
            exit 1
        }

        Write-Host "Profile sync check passed. Report: $ReportPath"
        # Keep hosted shells from surfacing handled native-command failures.
        exit 0
    }
}
