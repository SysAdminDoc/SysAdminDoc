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
$SchemaBaseUrl = "https://raw.githubusercontent.com/$Owner/$Owner/main/schemas"
$CatalogSchemaUrl = "$SchemaBaseUrl/profile-catalog.v1.json"
$ProjectsSchemaUrl = "$SchemaBaseUrl/profile-projects.v1.json"
$ReportSchemaUrl = "$SchemaBaseUrl/profile-sync-report.v1.json"
$CatalogSchemaPath = Join-Path $RepoRoot "schemas/profile-catalog.v1.json"
$ProjectsSchemaPath = Join-Path $RepoRoot "schemas/profile-projects.v1.json"
$ReportSchemaPath = Join-Path $RepoRoot "schemas/profile-sync-report.v1.json"
$script:RepositoryMetadataProvider = "graphql"
$script:RepositoryEnumerationRequestedLimit = 500
$script:RepositoryEnumerationTruncated = $false
$script:MetadataSnapshotAt = (Get-Date).ToString("o")

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

    $allRepos = New-Object System.Collections.Generic.List[object]
    $page = 1
    do {
        $repoJson = & gh api "users/$Owner/repos?per_page=100&page=$page" 2>&1
        $repoOutput = (($repoJson | Out-String).Trim())
        if ($LASTEXITCODE -ne 0) {
            throw "REST repo metadata fallback failed on page $page. Last gh output: $repoOutput"
        }

        $pageRepos = @($repoOutput | ConvertFrom-Json)
        foreach ($repo in $pageRepos) {
            if (-not $repo.archived -and -not $repo.private) {
                $allRepos.Add($repo)
            }
        }
        $page++
    } while ($pageRepos.Count -eq 100)

    $mapped = New-Object System.Collections.Generic.List[object]
    foreach ($repo in $allRepos) {
        $release = $null
        $releaseJson = & gh api "repos/$Owner/$($repo.name)/releases/latest" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $releaseOutput = (($releaseJson | Out-String).Trim())
            if (-not [string]::IsNullOrWhiteSpace($releaseOutput)) {
                $releaseData = $releaseOutput | ConvertFrom-Json
                $assetNames = @(Get-ReleaseAssetNamesFromApiRelease -Release $releaseData)
                $release = [pscustomobject]@{
                    tagName = $releaseData.tag_name
                    url = $releaseData.html_url
                    name = $releaseData.name
                    publishedAt = $releaseData.published_at
                    releaseAssetNames = $assetNames
                    releaseAssetKinds = @(Get-ReleaseAssetKinds -AssetNames $assetNames)
                    assetApiInspected = $true
                }
            }
        }

        $topics = @()
        if ($repo.topics) {
            $topics = @($repo.topics | ForEach-Object { [pscustomobject]@{ name = $_ } })
        }

        $mapped.Add([pscustomobject]@{
            name = $repo.name
            description = $repo.description
            stargazerCount = [int]$repo.stargazers_count
            defaultBranchRef = [pscustomobject]@{ name = $repo.default_branch }
            latestRelease = $release
            isPrivate = [bool]$repo.private
            visibility = "PUBLIC"
            isArchived = [bool]$repo.archived
            repositoryTopics = $topics
            pushedAt = $repo.pushed_at
            url = $repo.html_url
            primaryLanguage = if ([string]::IsNullOrWhiteSpace([string]$repo.language)) { $null } else { [pscustomobject]@{ name = $repo.language } }
        })
    }

    $script:RepositoryMetadataProvider = "rest-fallback"
    $script:RepositoryEnumerationRequestedLimit = 0
    $script:RepositoryEnumerationTruncated = $false
    return $mapped.ToArray()
}

function Get-GitHubRepos {
    if ($Offline) {
        return @()
    }

    $repoLimit = 500
    $ghArgs = @(
        "repo", "list", $Owner,
        "--visibility", "public",
        "--no-archived",
        "--limit", [string]$repoLimit,
        "--json", "name,description,stargazerCount,defaultBranchRef,latestRelease,isPrivate,visibility,isArchived,repositoryTopics,pushedAt,url,primaryLanguage"
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
                if ($repos.Count -ge $repoLimit) {
                    Write-Warning "gh repo list returned $($repos.Count) repos (limit $repoLimit); some public repos may be truncated."
                }
                $script:RepositoryMetadataProvider = "graphql"
                $script:RepositoryEnumerationRequestedLimit = $repoLimit
                $script:RepositoryEnumerationTruncated = [bool]($repos.Count -ge $repoLimit)
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

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-label=`"$(ConvertTo-SvgText $Title)`">")
    $lines.Add("  <title>$(ConvertTo-SvgText $Title)</title>")
    $lines.Add("  <desc>$(ConvertTo-SvgText $Subtitle)</desc>")
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

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-label=`"SysAdminDoc profile header`">")
    $lines.Add("  <title>SysAdminDoc profile header</title>")
    $lines.Add("  <desc>Static profile header for a healthcare IT engineer, DICOM/PACS specialist, and product builder.</desc>")
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

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$Width`" height=`"$Height`" viewBox=`"0 0 $Width $Height`" role=`"img`" aria-label=`"Decorative footer wave for the SysAdminDoc profile`">")
    $lines.Add("  <title>Decorative footer wave for the SysAdminDoc profile</title>")
    $lines.Add("  <desc>Static footer divider used by the generated profile README.</desc>")
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

    $blocks.Add("")
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

    return (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
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

function Test-DocVersionConsistency {
    param(
        [string]$RoadmapPath = (Join-Path $RepoRoot "ROADMAP.md"),
        [string]$ChangelogPath = (Join-Path $RepoRoot "CHANGELOG.md"),
        [string]$ProjectContextPath = (Join-Path $RepoRoot "PROJECT_CONTEXT.md"),
        [string]$ResearchReportPath = (Join-Path $RepoRoot "RESEARCH_REPORT.md")
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $versions = New-Object System.Collections.Generic.List[object]
    $dates = New-Object System.Collections.Generic.List[object]

    $roadmap = Read-DocConsistencyFile -Path $RoadmapPath -Errors $errors
    $changelog = Read-DocConsistencyFile -Path $ChangelogPath -Errors $errors
    $projectContext = Read-DocConsistencyFile -Path $ProjectContextPath -Errors $errors
    $researchReport = Read-DocConsistencyFile -Path $ResearchReportPath -Errors $errors

    $changelogVersion = Add-DocConsistencyRecord -Records $versions -Errors $errors -Document $changelog -Field "latestChangelogVersion" -Pattern '^## \[(v\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}\s*$' -MissingMessage "latest changelog version heading"
    $null = Add-DocConsistencyRecord -Records $versions -Errors $errors -Document $roadmap -Field "currentRepoVersion" -Pattern '^Current repo version:\s*(v\d+\.\d+\.\d+)\s*$' -MissingMessage "Current repo version"
    $null = Add-DocConsistencyRecord -Records $versions -Errors $errors -Document $projectContext -Field "version" -Pattern '^Version:\s*(v\d+\.\d+\.\d+)\s*$' -MissingMessage "Version"
    $null = Add-DocConsistencyRecord -Records $versions -Errors $errors -Document $researchReport -Field "currentVersionAfterRefresh" -Pattern '^Current version after this refresh:\s*(v\d+\.\d+\.\d+)\s*$' -MissingMessage "Current version after this refresh"

    $changelogDate = Add-DocConsistencyRecord -Records $dates -Errors $errors -Document $changelog -Field "latestChangelogDate" -Pattern '^## \[v\d+\.\d+\.\d+\] - (\d{4}-\d{2}-\d{2})\s*$' -MissingMessage "latest changelog date"
    $roadmapSyncDate = Add-DocConsistencyRecord -Records $dates -Errors $errors -Document $roadmap -Field "latestProfileSync" -Pattern '^Latest profile sync:\s*(\d{4}-\d{2}-\d{2})\s*$' -MissingMessage "Latest profile sync"
    $projectContextSyncDate = Add-DocConsistencyRecord -Records $dates -Errors $errors -Document $projectContext -Field "latestSyncDate" -Pattern '^Latest sync date:\s*(\d{4}-\d{2}-\d{2})\s*$' -MissingMessage "Latest sync date"
    $researchRefreshDate = Add-DocConsistencyRecord -Records $dates -Errors $errors -Document $researchReport -Field "researchRefresh" -Pattern '^Research refresh:\s*(\d{4}-\d{2}-\d{2})\s*$' -MissingMessage "Research refresh"

    if (-not [string]::IsNullOrWhiteSpace([string]$changelogVersion)) {
        foreach ($record in @($versions.ToArray())) {
            if (-not [string]::IsNullOrWhiteSpace([string]$record.value) -and [string]$record.value -ne [string]$changelogVersion) {
                $errors.Add("$($record.path) $($record.field) value '$($record.value)' does not match CHANGELOG latest version '$changelogVersion'")
            }
        }
    }

    $dateValues = @($changelogDate, $roadmapSyncDate, $projectContextSyncDate, $researchRefreshDate)
    foreach ($dateValue in $dateValues) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dateValue) -and -not (Test-IsoDateText -Value ([string]$dateValue))) {
            $errors.Add("planning doc date '$dateValue' is not a valid yyyy-MM-dd date")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$changelogDate) -and (Test-IsoDateText -Value ([string]$changelogDate))) {
        $latestChangelogDate = [datetime]::ParseExact([string]$changelogDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
        foreach ($record in @($dates.ToArray() | Where-Object { $_.field -ne "latestChangelogDate" -and -not [string]::IsNullOrWhiteSpace([string]$_.value) })) {
            if (-not (Test-IsoDateText -Value ([string]$record.value))) {
                continue
            }

            $recordedDate = [datetime]::ParseExact([string]$record.value, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
            if ($recordedDate -lt $latestChangelogDate) {
                $errors.Add("$($record.path) $($record.field) date '$($record.value)' is older than CHANGELOG latest date '$changelogDate'")
            } elseif ($recordedDate -gt $latestChangelogDate) {
                $warnings.Add("$($record.path) $($record.field) date '$($record.value)' is newer than CHANGELOG latest date '$changelogDate'")
            }
        }
    }

    return [ordered]@{
        passed = [bool]($errors.Count -eq 0)
        expectedVersion = if ([string]::IsNullOrWhiteSpace([string]$changelogVersion)) { $null } else { [string]$changelogVersion }
        expectedDate = if ([string]::IsNullOrWhiteSpace([string]$changelogDate)) { $null } else { [string]$changelogDate }
        versions = $versions.ToArray()
        dates = $dates.ToArray()
        errors = $errors.ToArray()
        warnings = $warnings.ToArray()
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
                    $severity = if ($infoFields -contains $field) { "info" } else { "fatal" }
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
        [hashtable]$ExpectedAssets = @{},
        [switch]$SkipLinkValidation
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries)
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

    $currentReadme = Get-Content -LiteralPath $ReadmePath -Raw
    $currentProjects = if (Test-Path -LiteralPath $ProjectsPath) { Get-Content -LiteralPath $ProjectsPath -Raw } else { "" }
    $normalize = {
        param([string]$Text)
        return (($Text -replace "`r`n", "`n").TrimEnd())
    }
    $readmeInSync = (& $normalize $currentReadme) -eq (& $normalize $ExpectedReadme)
    $projectsInSync = (ConvertTo-ProjectsSyncComparableJson -Json $currentProjects) -eq (ConvertTo-ProjectsSyncComparableJson -Json $ExpectedProjects)
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
    $metadataDriftResult = Test-MetadataDrift -CurrentProjectsJson $currentProjects -ExpectedProjectsJson $ExpectedProjects

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
    $metadataHygiene = Test-MetadataHygiene -Repos $Repos -CatalogEntries $entries
    $releaseAssetDrift = Test-ReleaseAssetDrift -Entries $included -RepoLookup $repoLookup
    $feedSchemaValidation = Test-FeedSchemaContracts -Catalog $Catalog -ProjectsJson $ExpectedProjects
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
        metadataHygiene = $metadataHygiene
        releaseAssetDrift = $releaseAssetDrift
        schemaValidation = $schemaValidation
        docVersionConsistency = $docVersionConsistency
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
        readmeExperienceChecks = $experienceChecks
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
        $metadataDriftResult.fatalCount -gt 0 -or
        $missingPublic.Count -gt 0 -or
        $privateViolations.Count -gt 0 -or
        $medicalViolations.Count -gt 0 -or
        $urlSchemeViolations.Count -gt 0 -or
        $orphanedSuppressed.Count -gt 0 -or
        $redirects.Count -gt 0 -or
        $linkFailures.Count -gt 0 -or
        $experienceChecks["passed"] -ne $true -or
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

$repos = if ($Offline) { @() } else { Add-ReleaseAssetMetadata -Repos (Get-GitHubRepos) }

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
    }
}
