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
                $release = [pscustomobject]@{
                    tagName = $releaseData.tag_name
                    url = $releaseData.html_url
                    name = $releaseData.name
                    publishedAt = $releaseData.published_at
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

    return $mapped.ToArray()
}

function Get-GitHubRepos {
    if ($Offline) {
        return @()
    }

    $ghArgs = @(
        "repo", "list", $Owner,
        "--visibility", "public",
        "--no-archived",
        "--limit", "300",
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
        [string]$Url
    )

    return [ordered]@{
        repo = [string]$Entry.repo
        type = $Type
        url = $Url
        host = Get-LinkHost $Url
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

        if ($meta -and $meta.latestRelease -and (([string]$entry.downloadKind).ToLowerInvariant() -ne "repo")) {
            $releaseUrl = Get-ReleaseUrl $entry
            $targets.Add((New-LinkValidationTarget -Entry $entry -Type "release" -Url $releaseUrl))
        }
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
            [ordered]@{
                repo = $target.repo
                type = $target.type
                url = $target.url
                host = $target.host
                ok = [bool]$result.ok
                status = $result.status
                error = $result.error
                fatal = [bool]$result.fatal
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
            [ordered]@{
                repo = $target.repo
                type = $target.type
                url = $target.url
                host = $target.host
                ok = [bool]$result.ok
                status = $result.status
                error = $result.error
                fatal = [bool]$result.fatal
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
        [int]$ThrottleLimit = $LinkValidationThrottle,
        [scriptblock]$ProbeScript = $null
    )

    $targets = @(Get-LinkValidationTargets -Included $Included -RepoLookup $RepoLookup)
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

    return [ordered]@{
        failures = $failures.ToArray()
        warnings = $warnings.ToArray()
        warningCountByHost = $warningCountByHost
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

    $kind = ([string]$Entry.downloadKind).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($kind)) {
        switch ($Category) {
            "android" { $kind = "apk" }
            "extensions" { $kind = "download" }
            "desktop" { $kind = "zip" }
            default { $kind = "download" }
        }
    }

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

function Get-CategoryDefinition {
    param([string]$Slug)

    return ($CategoryDefinitions | Where-Object { $_.Slug -eq $Slug } | Select-Object -First 1)
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
        [hashtable[]]$Items,
        [hashtable]$RepoLookup
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

| Step | Behavior |
|:-----|:---------|
| Checks first | Skips Python or Git when already installed. |
| Installs with Windows tooling | Uses `winget` for [Python 3.12](https://www.python.org/) and [Git for Windows](https://git-scm.com/). |
| Refreshes the shell | Updates the current `PATH` so the commands below work without reopening PowerShell. |
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
    $preview = New-CategoryPreviewLine -Items $items -RepoLookup $RepoLookup
    if ($preview) {
        $lines.Add($preview)
        $lines.Add("")
    }

    switch ($Definition.Render) {
        "code" {
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $line = "$(Get-ProjectLink $entry $meta) -- $(Get-Description $entry $meta)"
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
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-Description $entry $meta) | $(Get-ActionLink $entry $meta $Definition.Slug) |")
            }
            $lines.Add("")
        }
        "install-table" {
            $lines.Add("| Project | Description | Install |")
            $lines.Add("|:--------|:------------|:-------:|")
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-Description $entry $meta) | $(Get-ActionLink $entry $meta $Definition.Slug) |")
            }
            $lines.Add("")
        }
        "download-table" {
            $lines.Add("| Project | Description | Download |")
            $lines.Add("|:--------|:------------|:--------:|")
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-Description $entry $meta) | $(Get-ActionLink $entry $meta $Definition.Slug) |")
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
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-Description $entry $meta) | $language | $(Get-ActionLink $entry $meta $Definition.Slug) |")
            }
            $lines.Add("")
        }
        "simple-table" {
            $lines.Add("| Project | Description |")
            $lines.Add("|:--------|:------------|")
            foreach ($entry in $items) {
                $meta = Get-RepoMeta $entry $RepoLookup
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-Description $entry $meta) |")
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
        $lines.Add("| [**$($entry.title)**]($(Get-RepoUrl $entry)) | $category | &#11088;$stars | $(Get-Description $entry $meta) | $action |")
    }
    return ($lines -join [Environment]::NewLine)
}

function Update-Header {
    param(
        [string]$Header,
        [int]$PublicRepoCount,
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $updated = $Header -replace '\d+%2B\+open\+source\+tools', "$PublicRepoCount%2B+open+source+tools"
    $updated = $updated -replace '- \d+\+ open source projects across', "- $PublicRepoCount+ open source projects across"
    $updated = $updated -replace 'Public portfolio: \d+ active repos, \d+ visitor-facing projects,', "Public portfolio: $PublicRepoCount active repos, $($Entries.Count) visitor-facing projects,"
    $updated = $updated -replace '\| Public catalog \| \d+ active repos,', "| Public catalog | $PublicRepoCount active repos,"

    $building = @($Entries | Where-Object { $_.currentlyBuilding -eq $true } | Sort-Object @{ Expression = { [int]$_.order } }, repo)
    if ($building.Count -gt 0) {
        $tableLines = New-Object System.Collections.Generic.List[string]
        $tableLines.Add("**Currently Building**")
        $tableLines.Add("")
        $tableLines.Add("| Project | Focus | Action |")
        $tableLines.Add("|:--------|:------|:------:|")
        foreach ($entry in $building) {
            $meta = Get-RepoMeta $entry $RepoLookup
            $text = if (-not [string]::IsNullOrWhiteSpace([string]$entry.currentlyBuildingText)) {
                [string]$entry.currentlyBuildingText
            } else {
                Get-Description $entry $meta
            }
            $project = "[**$($entry.title)**]($(Get-RepoUrl $entry))"
            $action = Get-ActionLink $entry $meta $entry.category
            $tableLines.Add("| $project | $text | $action |")
        }
        $table = $tableLines -join [Environment]::NewLine
        $pattern = '(?s)\*\*Currently Building\*\*\r?\n\r?\n\|[^\r\n]+\|\r?\n\|[:\-\| ]+\|\r?\n(?:\|.*?\|\r?\n)+'
        $updated = [regex]::Replace($updated, $pattern, $table + [Environment]::NewLine)
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
    $footer = '![Footer](https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,50:161b22,100:1f6feb&height=120&section=footer)'
    $publicCount = if ($Repos.Count -gt 0) { $Repos.Count } else { ($entries | Select-Object -ExpandProperty repo -Unique).Count }
    $header = Update-Header -Header $readme.Substring(0, $start) -PublicRepoCount $publicCount -Entries $entries -RepoLookup $repoLookup
    $header = [regex]::Replace($header, '(\r?\n\s*---\s*)+$', [Environment]::NewLine + [Environment]::NewLine + '---')

    $blocks = New-Object System.Collections.Generic.List[string]
    $blocks.Add($header)
    $blocks.Add("")
    $blocks.Add($GeneratedCatalogNotice)
    $blocks.Add("")
    $blocks.Add((New-DiscoverySection -Entries $entries -Repos $Repos))
    $blocks.Add("")
    $blocks.Add("---")
    $blocks.Add("")
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

function New-ProjectsExportJson {
    param(
        [hashtable]$Catalog,
        [object[]]$Repos
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries | Sort-Object category, @{ Expression = { [int]$_.order } }, repo)
    $projects = New-Object System.Collections.Generic.List[object]
    $suppressed = New-Object System.Collections.Generic.List[object]

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

        $row = [ordered]@{
            repo = [string]$entry.repo
            title = [string]$entry.title
            category = [string]$entry.category
            includeInReadme = [bool]$entry.includeInReadme
            includeInPortfolio = [bool]$entry.includeInPortfolio
            suppressed = -not [string]::IsNullOrWhiteSpace([string]$entry.suppressionReason)
            suppressionReason = if ([string]::IsNullOrWhiteSpace([string]$entry.suppressionReason)) { $null } else { [string]$entry.suppressionReason }
            description = Get-Description $entry $meta
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
            pushedAt = if ($meta -and $meta.pushedAt) { ConvertTo-IsoText $meta.pushedAt } else { $null }
            topics = $topics
            featured = [bool]$entry.featured
            featuredRank = if ($entry.featuredRank) { [int]$entry.featuredRank } else { $null }
            currentlyBuilding = [bool]$entry.currentlyBuilding
            notes = if ([string]::IsNullOrWhiteSpace([string]$entry.notes)) { $null } else { [string]$entry.notes }
        }

        if ($row.suppressed) {
            $suppressed.Add($row)
        } elseif ($row.includeInPortfolio) {
            $projects.Add($row)
        }
    }

    $payload = [ordered]@{
        schema = "https://sysadmindoc.github.io/schemas/profile-projects.v1.json"
        generatedAt = ConvertTo-IsoText $Catalog.generatedAt
        source = "SysAdminDoc/SysAdminDoc data/profile-catalog.json"
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
        schema = "https://sysadmindoc.github.io/schemas/profile-catalog.v1.json"
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
    $hasFeaturedActionColumn = $ExpectedReadme.Contains("| Project | Category | Stars | Description | Action |")
    $hasCurrentlyBuildingActionColumn = ($building.Count -eq 0) -or $ExpectedReadme.Contains("| Project | Focus | Action |")
    $passed = $hasStartHere -and $hasSnapshot -and $hasGeneratedNotice -and $hasFeaturedActionColumn -and $hasCurrentlyBuildingActionColumn -and
        $missingAnchors.Count -eq 0 -and $missingPrimaryAction.Count -eq 0 -and $unlabeledDownloads -eq 0

    return [ordered]@{
        passed = [bool]$passed
        startHereSection = [bool]$hasStartHere
        catalogSnapshotSection = [bool]$hasSnapshot
        generatedCatalogNotice = [bool]$hasGeneratedNotice
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
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Name)) {
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

function New-MetadataRowIndex {
    param([object]$ProjectsPayload)

    $index = @{}
    foreach ($collectionName in @("projects", "suppressed")) {
        $collection = Get-MemberValue -Object $ProjectsPayload -Name $collectionName
        foreach ($row in @($collection)) {
            $repo = Get-MemberValue -Object $row -Name "repo"
            if (-not [string]::IsNullOrWhiteSpace([string]$repo)) {
                $index[([string]$repo).ToLowerInvariant()] = $row
            }
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

        $currentRows = New-MetadataRowIndex -ProjectsPayload $current
        $expectedRows = New-MetadataRowIndex -ProjectsPayload $expected
        $rowKeys = @(@($currentRows.Keys) + @($expectedRows.Keys) | Sort-Object -Unique)
        $infoFields = @("stars", "pushedAt", "topics")
        $rowFields = @(
            "title",
            "category",
            "includeInReadme",
            "includeInPortfolio",
            "suppressed",
            "suppressionReason",
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
            "pushedAt",
            "topics",
            "visibility",
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
    $userscriptKindWithoutInstallUrl = New-Object System.Collections.Generic.List[object]
    $releaseBearingRows = 0
    $releaseActionRows = 0

    foreach ($entry in @($Entries | Sort-Object repo)) {
        $meta = Get-RepoMeta $entry $RepoLookup
        $hasRelease = [bool]($meta -and $meta.latestRelease)
        $downloadKind = ([string]$entry.downloadKind).ToLowerInvariant()
        $action = Get-PrimaryAction $entry $meta $entry.category

        if ($hasRelease) {
            $releaseBearingRows++
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
        }

        if ($hasRelease -and $downloadKind -eq "repo") {
            $sourceOnlyWithRelease.Add([ordered]@{
                repo = [string]$entry.repo
                latestReleaseTag = [string]$meta.latestRelease.tagName
            })
        }

        if (-not $hasRelease -and -not [string]::IsNullOrWhiteSpace($downloadKind) -and $downloadKind -notin @("repo", "userscript")) {
            $missingReleaseForDownloadKind.Add([ordered]@{
                repo = [string]$entry.repo
                downloadKind = $downloadKind
            })
        }

        if ($downloadKind -eq "userscript" -and [string]::IsNullOrWhiteSpace([string]$entry.userscriptUrl)) {
            $userscriptKindWithoutInstallUrl.Add([ordered]@{
                repo = [string]$entry.repo
                downloadKind = $downloadKind
            })
        }
    }

    return [ordered]@{
        checkedCatalogRows = @($Entries).Count
        releaseBearingRows = $releaseBearingRows
        releaseActionRows = $releaseActionRows
        sourceOnlyWithRelease = $sourceOnlyWithRelease.ToArray()
        missingReleaseForDownloadKind = $missingReleaseForDownloadKind.ToArray()
        releaseActionLabelMismatches = $releaseActionLabelMismatches.ToArray()
        userscriptKindWithoutInstallUrl = $userscriptKindWithoutInstallUrl.ToArray()
        assetApiInspected = $false
        note = "Release asset filename inspection is tracked by the release asset taxonomy roadmap item."
    }
}

function Test-ProfileState {
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [string]$ExpectedReadme,
        [string]$ExpectedProjects
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries)
    $included = @($entries | Where-Object { $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason) })
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
    $projectsInSync = (& $normalize $currentProjects) -eq (& $normalize $ExpectedProjects)
    $metadataDriftResult = Test-MetadataDrift -CurrentProjectsJson $currentProjects -ExpectedProjectsJson $ExpectedProjects

    $linkFailures = @()
    $linkWarnings = @()
    $linkValidationSummary = [ordered]@{
        targetCount = 0
        throttleLimit = $LinkValidationThrottle
        elapsedMs = 0
        warningCountByHost = @()
    }
    if (-not $Offline -and -not $SkipLinkValidation) {
        $linkResult = Test-LinkTargets -Included $included -RepoLookup $repoLookup
        $linkFailures = @($linkResult.failures)
        $linkWarnings = @($linkResult.warnings)
        $linkValidationSummary = [ordered]@{
            targetCount = $linkResult.targetCount
            throttleLimit = $linkResult.throttleLimit
            elapsedMs = $linkResult.elapsedMs
            warningCountByHost = @($linkResult.warningCountByHost)
        }
    }

    $experienceChecks = Test-ReadmeExperience -Catalog $Catalog -Repos $Repos -ExpectedReadme $ExpectedReadme
    $metadataHygiene = Test-MetadataHygiene -Repos $Repos -CatalogEntries $entries
    $releaseAssetDrift = Test-ReleaseAssetDrift -Entries $included -RepoLookup $repoLookup
    $reportGeneratedAt = (Get-Date).ToString("o")
    $validationPerformance = [ordered]@{
        linkValidation = [ordered]@{
            skipped = [bool]($Offline -or $SkipLinkValidation)
            targetCount = $linkValidationSummary.targetCount
            throttleLimit = $linkValidationSummary.throttleLimit
            elapsedMs = $linkValidationSummary.elapsedMs
            failureCount = @($linkFailures).Count
            warningCount = @($linkWarnings).Count
            warningHostCount = @($linkValidationSummary.warningCountByHost).Count
        }
    }
    $report = [ordered]@{
        generatedAt = $reportGeneratedAt
        readmeInSync = $readmeInSync
        projectsExportInSync = $projectsInSync
        publicRepoCount = $Repos.Count
        catalogEntryCount = $entries.Count
        includedReadmeCount = $included.Count
        metadataHygiene = $metadataHygiene
        releaseAssetDrift = $releaseAssetDrift
        validationPerformance = $validationPerformance
        missingPublicRepos = $missingPublic
        privateVisibilityViolations = $privateViolations
        medicalPrivacyViolations = $medicalViolations
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

    $failed = -not $readmeInSync -or $metadataDriftResult.fatalCount -gt 0 -or $missingPublic.Count -gt 0 -or $privateViolations.Count -gt 0 -or $medicalViolations.Count -gt 0 -or $redirects.Count -gt 0 -or $linkFailures.Count -gt 0 -or $experienceChecks["passed"] -ne $true
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

$repos = if ($Offline) { @() } else { Get-GitHubRepos }

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

    if ($Write) {
        [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $ReadmePath).Path, $expected, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $RepoRoot $ProjectsPath), $expectedProjects + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Wrote $ReadmePath from $CatalogPath."
        Write-Host "Wrote $ProjectsPath from $CatalogPath."
    }

    if ($Check) {
        $result = Test-ProfileState -Catalog $catalogForRun -Repos $repos -ExpectedReadme $expected -ExpectedProjects $expectedProjects
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
