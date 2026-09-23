# Catalog loading and per-entry accessors: reading data/profile-catalog.json, entry
# normalisation, repository URLs, descriptions, stable project identity, shape
# validation, missing-repo drafts and the guarded legacy seed parser. Dot-sourced by
# scripts/sync-profile.ps1.

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

function New-CatalogEntry {
    param(
        [string]$Repo,
        [string]$Category,
        [string]$Description,
        [int]$Order
    )

    return [ordered]@{
        repo = $Repo
        id = $null
        aliases = @()
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
        localeHints = @()
        scriptHints = @()
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
    Set-IfMissing $hash "id" $null
    Set-IfMissing $hash "aliases" @()
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
    Set-IfMissing $hash "localeHints" @()
    Set-IfMissing $hash "scriptHints" @()
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

    if ($null -eq $hash.aliases) { $hash.aliases = @() }
    if ($null -eq $hash.localeHints) { $hash.localeHints = @() }
    if ($null -eq $hash.scriptHints) { $hash.scriptHints = @() }

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
            $parts.Add("Upstream: [$(ConvertTo-MarkdownText $forkOf)]($url)")
        } else {
            $parts.Add("Upstream: $(ConvertTo-MarkdownText $forkOf)")
        }
    }

    $upstreamLicense = [string]$Entry.upstreamLicense
    if (-not [string]::IsNullOrWhiteSpace($upstreamLicense)) {
        $parts.Add("License: $(ConvertTo-MarkdownText $upstreamLicense)")
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

    # README only: projects.json carries the raw Get-Description text.
    return "$(ConvertTo-MarkdownText (Get-Description $Entry $Meta))$(Get-UpstreamAttribution $Entry)"
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

function Get-RepoUrl {
    param([hashtable]$Entry)

    $repo = if ($Entry.aliasOf) { [string]$Entry.aliasOf } else { [string]$Entry.repo }
    return "https://github.com/$Owner/$repo"
}

function Get-OwnerRepoUrlPattern {
    # Regex for the start of a repository link as Get-RepoUrl writes it. The README parsers
    # and row counters match rendered links with it, so they follow -Owner.
    return 'https://github\.com/' + [regex]::Escape([string]$Owner) + '/'
}

function Get-ProjectCanonicalRepo {
    <#
    .SYNOPSIS
    Returns the owner-qualified repository identity used by public feed rows.
    .PARAMETER Entry
    Normalized profile catalog entry.
    #>
    [CmdletBinding()]
    param([hashtable]$Entry)

    $repo = if ($Entry.aliasOf) { [string]$Entry.aliasOf } else { [string]$Entry.repo }
    return "$Owner/$repo"
}

function Get-ProjectAliases {
    <#
    .SYNOPSIS
    Normalizes legacy repository aliases without exposing suppressed rows.
    .PARAMETER Entry
    Normalized profile catalog entry.
    #>
    [CmdletBinding()]
    param([hashtable]$Entry)

    $canonicalName = if ($Entry.aliasOf) { [string]$Entry.aliasOf } else { [string]$Entry.repo }
    $aliases = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($Entry.aliases)) {
        $alias = [string]$candidate
        if ([string]::IsNullOrWhiteSpace($alias) -or $alias -ieq $canonicalName -or $alias -ieq [string]$Entry.repo) {
            continue
        }
        if (-not @($aliases | Where-Object { $_ -ieq $alias })) {
            $aliases.Add($alias)
        }
    }
    if ($Entry.aliasOf -and [string]$Entry.repo -ine $canonicalName -and -not @($aliases | Where-Object { $_ -ieq [string]$Entry.repo })) {
        $aliases.Add([string]$Entry.repo)
    }

    return @($aliases.ToArray() | Sort-Object { ConvertTo-OrdinalSortKey $_ })
}

function Get-StableProjectEntityId {
    <#
    .SYNOPSIS
    Returns an explicit catalog ID or a deterministic opaque ID for a project.
    .PARAMETER Entry
    Normalized profile catalog entry.
    #>
    [CmdletBinding()]
    param([hashtable]$Entry)

    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.id)) {
        return [string]$Entry.id
    }

    $identity = (Get-ProjectCanonicalRepo -Entry $Entry).ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($identity)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = (($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha256.Dispose()
    }
    return "project-$($hash.Substring(0, 24))"
}

function Get-ProjectHintArray {
    param(
        [hashtable]$Entry,
        [string]$Field,
        [string[]]$Default
    )

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($Entry[$Field])) {
        $value = [string]$candidate
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if (-not @($values | Where-Object { $_ -ieq $value })) {
            $values.Add($value)
        }
    }
    if ($values.Count -eq 0) {
        foreach ($value in @($Default)) { $values.Add($value) }
    }
    return @($values.ToArray())
}

function Get-ProjectLocaleHints {
    param([hashtable]$Entry)

    return Get-ProjectHintArray -Entry $Entry -Field "localeHints" -Default @("en-US", "en")
}

function Get-ProjectScriptHints {
    param([hashtable]$Entry)

    return Get-ProjectHintArray -Entry $Entry -Field "scriptHints" -Default @("Latn")
}

function Get-CategoryDisplayName {
    param([string]$Slug)

    $def = $CategoryDefinitions | Where-Object { $_.Slug -eq $Slug } | Select-Object -First 1
    if ($def -and -not [string]::IsNullOrWhiteSpace([string]$def.DisplayName)) {
        return [string]$def.DisplayName
    }
    return $Slug
}

function Get-CategoryIcon {
    param([string]$Slug)

    $def = $CategoryDefinitions | Where-Object { $_.Slug -eq $Slug } | Select-Object -First 1
    if (-not $def) {
        return ""
    }

    $title = [string]$def.Title
    if ($title -match '^((?:&#\d+;|&#x[0-9a-fA-F]+;)+)') {
        return $Matches[1]
    }

    return ""
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

    $ownerRepoUrl = Get-OwnerRepoUrlPattern
    $featuredRank = 1
    foreach ($line in $lines) {
        if ($line -match ('^\| \[\*\*(?<title>.+?)\*\*\]\(' + $ownerRepoUrl + '(?<repo>[^)/]+)\) \| &#11088;(?<stars>\d+) \| (?<description>.*?) \|$')) {
            $repo = $Matches.repo
            if (-not $entries.Contains($repo)) {
                $entries[$repo] = New-CatalogEntry -Repo $repo -Category "misc" -Description $Matches.description -Order 9999
            }
            $entries[$repo].featured = $true
            $entries[$repo].featuredRank = $featuredRank
            $featuredRank++
        } elseif ($line -match ('^\| \[\*\*(?<title>.+?)\*\*\]\(' + $ownerRepoUrl + '(?<repo>[^)/]+)\) \| (?<category>.*?) \| &#11088;(?<stars>\d+) \| (?<description>.*?) \| (?<action>.*?) \|$')) {
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

        if ($line -match ('^\[\*\*(?<title>.+?)\*\*\]\(' + $ownerRepoUrl + '(?<repo>[^)/]+)\)(?: &#11088;(?<stars>\d+))? (?:--|—) (?<rest>.+)$')) {
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

        if ($line -match ('^\| \[\*\*(?<title>.+?)\*\*\]\(' + $ownerRepoUrl + '(?<repo>[^)/]+)\)(?: &#11088;(?<stars>\d+))? \| (?<description>.*?) \| (?<tail>.*) \|$')) {
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

        if ($line -match ('^\| \[\*\*(?<title>.+?)\*\*\]\(' + $ownerRepoUrl + '(?<repo>[^)/]+)\)(?: &#11088;(?<stars>\d+))? \| (?<description>.*?) \|$')) {
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
    $seenIds = @{}
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

        $entryId = [string]$entry.id
        if (-not [string]::IsNullOrWhiteSpace($entryId)) {
            if ($entryId -notmatch '^[a-z0-9][a-z0-9-]{2,63}$') {
                $issues.Add([ordered]@{ repo = $repo; field = "id"; value = $entryId; reason = "id must match ^[a-z0-9][a-z0-9-]{2,63}$" })
            } else {
                $idKey = $entryId.ToLowerInvariant()
                if ($seenIds.ContainsKey($idKey)) {
                    $issues.Add([ordered]@{ repo = $repo; field = "id"; value = $entryId; reason = "duplicate id also appears on $($seenIds[$idKey])" })
                } else {
                    $seenIds[$idKey] = $repo
                }
            }
        }

        $seenAliases = @{}
        foreach ($aliasCandidate in @($entry.aliases)) {
            $alias = [string]$aliasCandidate
            if ([string]::IsNullOrWhiteSpace($alias)) {
                $issues.Add([ordered]@{ repo = $repo; field = "aliases"; value = $alias; reason = "aliases entries must be non-empty" })
                continue
            }
            if (-not (Test-SafeGitHubName -Name $alias)) {
                $issues.Add([ordered]@{ repo = $repo; field = "aliases"; value = $alias; reason = "aliases entries must be safe GitHub repository names" })
            }
            $aliasKey = $alias.ToLowerInvariant()
            if ($seenAliases.ContainsKey($aliasKey)) {
                $issues.Add([ordered]@{ repo = $repo; field = "aliases"; value = $alias; reason = "duplicate alias" })
            } else {
                $seenAliases[$aliasKey] = $true
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

        # Public one-line text: nothing that breaks a line, hides as a control character,
        # reorders what a reader sees (bidi embedding, override or isolate), or is half of a
        # surrogate pair. The README encoder would drop these, so the catalog refuses them
        # rather than publishing text that differs from what was written. The value in the
        # issue is the offending code point, never the text itself.
        foreach ($field in @('title', 'descriptionOverride', 'currentlyBuildingText', 'forkOf', 'upstreamLicense', 'readmeReviewNote', 'suppressionReason')) {
            $text = [string]$entry[$field]
            if ([string]::IsNullOrEmpty($text)) {
                continue
            }
            $problem = $null
            for ($index = 0; $index -lt $text.Length -and $null -eq $problem; $index++) {
                $character = $text[$index]
                $code = [int]$character
                if ([char]::IsHighSurrogate($character) -and $index + 1 -lt $text.Length -and [char]::IsLowSurrogate($text[$index + 1])) {
                    $index++
                } elseif ([char]::IsSurrogate($character)) {
                    $problem = [ordered]@{ codePoint = ('U+{0:X4}' -f $code); reason = "contains an unpaired surrogate" }
                } elseif ($code -eq 0x0A -or $code -eq 0x0D -or $code -eq 0x85 -or $code -eq 0x2028 -or $code -eq 0x2029) {
                    $problem = [ordered]@{ codePoint = ('U+{0:X4}' -f $code); reason = "must be one line" }
                } elseif ([char]::IsControl($character)) {
                    $problem = [ordered]@{ codePoint = ('U+{0:X4}' -f $code); reason = "contains a control character" }
                } elseif (($code -ge 0x202A -and $code -le 0x202E) -or ($code -ge 0x2066 -and $code -le 0x2069)) {
                    $problem = [ordered]@{ codePoint = ('U+{0:X4}' -f $code); reason = "contains a bidi embedding, override or isolate character" }
                }
            }
            if ($null -ne $problem) {
                $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = $field; value = $problem.codePoint; reason = "$field $($problem.reason)" })
            }
        }

        # \z, not $: in .NET $ also matches before a final newline, which would pass
        # "tool.ps1`n" and break the pasted command.
        # entrypoint and branch are pasted into the install one-liners: & "$d\<entrypoint>" and
        # git clone -b <branch>. A $ or backtick would expand inside the double quotes and a
        # quote, semicolon or space would end the argument, so both take a strict shape.
        $entrypoint = [string]$entry.entrypoint
        if (-not [string]::IsNullOrWhiteSpace($entrypoint) -and $entrypoint -cnotmatch '^(?:[A-Za-z0-9][A-Za-z0-9 ._()+-]*[\\/])*[A-Za-z0-9][A-Za-z0-9 ._()+-]*\.(?:ps1|py|pyw)\z') {
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "entrypoint"; value = $entrypoint; reason = "entrypoint must be a relative .ps1, .py or .pyw path of letters, digits, spaces and ._()+- only" })
        }
        if (-not [string]::IsNullOrWhiteSpace($entrypoint)) {
            # run.ps1 starts a .ps1 in PowerShell and a .py or .pyw with python, and
            # projects.json carries installKind for anyone else reading the feed; both must agree.
            $expectedKind = if ($entrypoint -like '*.ps1') { 'powershell' } else { 'python' }
            if ([string]$entry.installKind -cne $expectedKind) {
                $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "installKind"; value = [string]$entry.installKind; reason = "installKind must be $expectedKind for the entrypoint $entrypoint" })
            }
        }
        $branch = [string]$entry.branch
        if (-not [string]::IsNullOrWhiteSpace($branch) -and $branch -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*\z') {
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "branch"; value = $branch; reason = "branch must start with a letter or digit and use only letters, digits and ._/-" })
        }
    }

    return [ordered]@{
        passed = ($issues.Count -eq 0)
        issueCount = $issues.Count
        issues = $issues.ToArray()
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

function Get-InferredCatalogCategory {
    <#
    .SYNOPSIS
    Guesses a catalog category from live repository metadata, or returns $null.
    .DESCRIPTION
    Only returns a category when the signal is unambiguous. A wrong guess that looks
    confident is worse than a null the reviewer has to fill in, so anything uncertain
    is left for the owner and reported in unresolvedFields.
    #>
    param([object]$Repo)

    $language = ([string](Get-MemberValue -Object (Get-MemberValue -Object $Repo -Name "primaryLanguage") -Name "name")).ToLowerInvariant()
    $topics = @(Get-MemberValue -Object $Repo -Name "repositoryTopics" | ForEach-Object {
            $name = Get-MemberValue -Object $_ -Name "name"
            if ($null -eq $name) { $name = Get-MemberValue -Object (Get-MemberValue -Object $_ -Name "topic") -Name "name" }
            ([string]$name).ToLowerInvariant()
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    foreach ($topic in $topics) {
        switch -Regex ($topic) {
            '^(userscript|browser-extension|chrome-extension|firefox-addon)$' { return "extensions" }
            '^(android|android-app)$' { return "android" }
            '^(security|networking|dns)$' { return "security" }
            '^(ffmpeg|video|media)$' { return "media" }
        }
    }

    switch ($language) {
        "powershell" { return "powershell" }
        "python" { return "python" }
        "kotlin" { return "android" }
        default { return $null }
    }
}

function New-CatalogEntryStub {
    <#
    .SYNOPSIS
    Builds a paste-ready catalog fragment for an uncataloged public repository.
    .DESCRIPTION
    missingPublicRepos is a fail-closed gate whose only remediation was hand-authoring
    a 22-field row, which turned every new public repository into a multi-day check
    outage. Fields that cannot be observed from metadata are emitted as null and named
    in unresolvedFields rather than guessed.
    #>
    param([object]$Repo)

    $name = [string](Get-MemberValue -Object $Repo -Name "name")
    $language = Get-MemberValue -Object (Get-MemberValue -Object $Repo -Name "primaryLanguage") -Name "name"
    $branch = Get-MemberValue -Object (Get-MemberValue -Object $Repo -Name "defaultBranchRef") -Name "name"
    if ([string]::IsNullOrWhiteSpace([string]$branch)) { $branch = "main" }
    $category = Get-InferredCatalogCategory -Repo $Repo
    $description = Get-MemberValue -Object $Repo -Name "description"

    $entry = [ordered]@{
        repo = $name
        title = $name
        category = $category
        includeInReadme = $true
        includeInPortfolio = $true
        order = $null
        branch = [string]$branch
        entrypoint = $null
        installKind = $null
        downloadKind = $null
        userscriptUrl = $null
        liveUrl = $null
        language = if ([string]::IsNullOrWhiteSpace([string]$language)) { $null } else { [string]$language }
        descriptionOverride = if ([string]::IsNullOrWhiteSpace([string]$description)) { $null } else { [string]$description }
        featured = $false
        featuredRank = $null
        currentlyBuilding = $false
        currentlyBuildingText = $null
        allowPublicMedical = $false
        aliasOf = $null
        suppressionReason = $null
        notes = $null
    }

    $unresolved = New-Object System.Collections.Generic.List[string]
    foreach ($field in @("category", "order", "downloadKind")) {
        if ($null -eq $entry[$field]) { $unresolved.Add($field) }
    }
    if ($null -eq $entry.language) { $unresolved.Add("language") }
    if ($null -eq $entry.descriptionOverride) { $unresolved.Add("descriptionOverride") }

    return [ordered]@{
        entry = $entry
        unresolvedFields = $unresolved.ToArray()
    }
}

function Write-CatalogEntryDraft {
    <#
    .SYNOPSIS
    Appends suppressed draft rows for uncataloged public repositories.
    .DESCRIPTION
    Opt-in behind -DraftMissingCatalogEntries plus -Write. Every drafted row is created
    suppressed so nothing reaches the public README or feed before the owner has
    reviewed and completed it; the run still fails, because a draft is not a catalog
    decision.
    #>
    param(
        [object[]]$MissingPublicRepos,
        [string]$CatalogPath
    )

    $rows = @($MissingPublicRepos | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        return
    }

    $fullPath = if ([System.IO.Path]::IsPathRooted($CatalogPath)) { $CatalogPath } else { Join-Path $RepoRoot $CatalogPath }
    $catalog = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath $fullPath -Raw)
    $existing = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @(Get-JsonArrayItems (Get-MemberValue -Object $catalog -Name "entries"))) {
        $null = $existing.Add([string](Get-MemberValue -Object $entry -Name "repo"))
    }

    $drafted = New-Object System.Collections.Generic.List[string]
    $additions = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        $stub = Get-MemberValue -Object $row -Name "catalogEntryStub"
        if ($null -eq $stub) { continue }
        $repoName = [string](Get-MemberValue -Object $stub -Name "repo")
        if ([string]::IsNullOrWhiteSpace($repoName) -or $existing.Contains($repoName)) { continue }
        $draft = [ordered]@{}
        foreach ($property in $stub.PSObject.Properties) {
            $draft[$property.Name] = $property.Value
        }
        # The stub reports nulls so a reader can see what could not be observed, but the
        # catalog schema requires a category from its enum and a non-negative order.
        # Fill only those two, name them in the reason, and leave everything else null.
        $unresolved = @(Get-MemberValue -Object $row -Name "unresolvedFields")
        if ([string]::IsNullOrWhiteSpace([string]$draft["category"])) {
            $draft["category"] = "misc"
        }
        if ($null -eq $draft["order"]) {
            $category = [string]$draft["category"]
            $maxOrder = 0
            foreach ($entry in @(Get-JsonArrayItems (Get-MemberValue -Object $catalog -Name "entries"))) {
                if ([string](Get-MemberValue -Object $entry -Name "category") -eq $category) {
                    $candidate = [int](Get-MemberValue -Object $entry -Name "order")
                    if ($candidate -gt $maxOrder) { $maxOrder = $candidate }
                }
            }
            $draft["order"] = $maxOrder + 1
        }
        # Suppressed by default: a draft must not publish itself.
        $draft["includeInReadme"] = $false
        $draft["includeInPortfolio"] = $false
        $reason = "Draft catalog row awaiting owner review; complete it and clear this reason before publishing."
        if (@($unresolved).Count -gt 0) {
            $reason += " Unresolved: $(@($unresolved) -join ', ')."
        }
        $draft["suppressionReason"] = $reason
        $additions.Add([pscustomobject]$draft)
        $drafted.Add($repoName)
        $null = $existing.Add($repoName)
    }

    if ($additions.Count -eq 0) {
        return
    }

    $entries = @(Get-JsonArrayItems (Get-MemberValue -Object $catalog -Name "entries")) + $additions.ToArray()
    Set-MemberValue -Object $catalog -Name "entries" -Value $entries
    $json = ($catalog | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
    Write-AtomicUtf8TextFile -Path $fullPath -Content ($json.TrimEnd() + "`n")
    Write-Host "Drafted $($drafted.Count) suppressed catalog row(s) in $($CatalogPath): $($drafted -join ', '). Review and complete them before publishing."
}
