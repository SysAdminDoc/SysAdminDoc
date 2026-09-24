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
        reviewBy = $null
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
    Set-IfMissing $hash "reviewBy" $null
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

    $normalized = [ordered]@{
        schema = $catalog.schema
        generatedAt = $catalog.generatedAt
    }
    # Optional: the README header's personal text and links. Absent, the header is neutral,
    # and the key stays absent so the normalized catalog still matches the schema. Present,
    # it is copied as written, null or array included, so the schema gate sees what the
    # file says; a function return would unroll a one-item array into its item.
    $profileHeaderProperty = $catalog.PSObject.Properties['profileHeader']
    if ($null -ne $profileHeaderProperty) {
        $normalized['profileHeader'] = $profileHeaderProperty.Value
    }
    # Optional too: the portfolio behind "See everything", used unless -PortfolioUrl is given.
    $portfolioUrlProperty = $catalog.PSObject.Properties['portfolioUrl']
    if ($null -ne $portfolioUrlProperty) {
        $normalized['portfolioUrl'] = $portfolioUrlProperty.Value
    }
    $normalized['entries'] = @($entries)
    return $normalized
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

    # Text a reader can't see falls through, like a missing value: an override of only
    # zero-width characters would leave the description cell empty.
    if (Test-VisibleText ([string]$Entry.descriptionOverride)) {
        return [string]$Entry.descriptionOverride
    }
    if ($Meta -and (Test-VisibleText ([string]$Meta.description))) {
        return [string]$Meta.description
    }
    return [string]$Entry.repo
}

function Get-UpstreamUrl {
    param([string]$ForkOf)

    if ([string]::IsNullOrWhiteSpace($ForkOf)) {
        return $null
    }

    # The schema's owner/repo shape, anchored at the true end. The link lands in a README
    # table cell as written, so anything looser (a | splits the row) stays encoded text.
    if ($ForkOf -cmatch '^[A-Za-z0-9-]+/(?!\.\.?\z)[A-Za-z0-9._-]+\z') {
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
            $parts.Add("Upstream: [$(ConvertTo-MarkdownText $forkOf -LinkLabel)]($url)")
        } else {
            $parts.Add("Upstream: $(ConvertTo-MarkdownText $forkOf)")
        }
    }

    $upstreamLicense = [string]$Entry.upstreamLicense
    if (Test-VisibleText $upstreamLicense) {
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

    # Ordinal, like every comparison in this file: a switch compares by culture, which skips
    # zero-width and other ignorable characters.
    if ('private-or-sensitive'.Equals($ReasonCode)) { return "Private or sensitive project omitted from the public feed." }
    if ('duplicate-or-superseded'.Equals($ReasonCode)) { return "Duplicate or superseded project omitted from the public feed." }
    if ('placeholder'.Equals($ReasonCode)) { return "Placeholder project omitted from the public feed." }
    if ('not-visitor-facing'.Equals($ReasonCode)) { return "Project omitted because it is not visitor-facing." }
    return "Project omitted from the public feed."
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
    # Install blocks written as Start-Tool <Name>: they name the tool and nothing else, so
    # the entry's branch and entry script can't be read back from them.
    $startToolRepos = New-Object System.Collections.Generic.List[string]

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
            if ('```'.Equals($line)) {
                $inCode = $false
                if ($lastRepo -and $entries.Contains($lastRepo)) {
                    $code = ($codeLines -join " ")
                    if ($code -match 'git clone -q --depth 1 -b (?<branch>\S+)') {
                        $entries[$lastRepo].branch = $Matches.branch
                    }
                    if ($code -match '(?<runner>python|&)\s+"\$d\\(?<entry>[^"]+)"') {
                        $entries[$lastRepo].entrypoint = $Matches.entry
                        $entries[$lastRepo].installKind = if ('&'.Equals($Matches.runner)) { "powershell" } else { "python" }
                    } elseif ($code -match '\bStart-Tool\s+\S') {
                        $startToolRepos.Add($lastRepo)
                    }
                }
                $codeLines.Clear()
                continue
            }
            $codeLines.Add($line)
            continue
        }

        if ([string]::Equals($line, '```powershell', [StringComparison]::OrdinalIgnoreCase)) {
            $inCode = $true
            continue
        }

        # Rows join the name and the description with &middot; now; older READMEs used a
        # double hyphen or an em dash.
        if ($line -match ('^\[\*\*(?<title>.+?)\*\*\]\(' + $ownerRepoUrl + '(?<repo>[^)/]+)\)(?: &#11088;(?<stars>\d+))? (?:--|—|&middot;) (?<rest>.+)$')) {
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

            # The action is an <a href="..." aria-label="..."> tag with the short word as its
            # text (its href's & written &amp;); an older README wrote a Markdown link.
            if ('web'.Equals($category) -and $tail -match '\[Launch\]\((?<url>[^)]+)\)|<a href="(?<url>[^"]+)"[^>]*>Launch</a>') {
                $entries[$repo].liveUrl = [System.Net.WebUtility]::HtmlDecode($Matches.url)
            } elseif ($tail -match '\[Install\]\((?<url>[^)]+)\)|<a href="(?<url>[^"]+)"[^>]*>Install</a>') {
                $entries[$repo].userscriptUrl = [System.Net.WebUtility]::HtmlDecode($Matches.url)
                $entries[$repo].downloadKind = "userscript"
            } elseif ($tail -match 'releases/latest') {
                # The labels New-Readme writes for each kind, read off the button so a name in
                # the link's aria-label can't be taken for one. XPI alone isn't a catalog kind,
                # so it seeds as a plain download.
                $kindLabel = if ($tail -match '<kbd>&#11015;&nbsp;(?<kind>[^<]+)</kbd>') { $Matches.kind } else { $tail }
                if ($kindLabel -match 'CRX/XPI') { $entries[$repo].downloadKind = "crx-xpi" }
                elseif ($kindLabel -match 'ZIP/XPI') { $entries[$repo].downloadKind = "zip-xpi" }
                elseif ($kindLabel -match 'CRX') { $entries[$repo].downloadKind = "crx" }
                elseif ($kindLabel -match 'APK') { $entries[$repo].downloadKind = "apk" }
                elseif ($kindLabel -match 'EXE') { $entries[$repo].downloadKind = "exe" }
                elseif ($kindLabel -match 'ZIP') { $entries[$repo].downloadKind = "zip" }
                else { $entries[$repo].downloadKind = "download" }
            } elseif ($tail -match '\[Repo\]|>Repo</a>') {
                $entries[$repo].downloadKind = "repo"
            }

            if ('desktop'.Equals($category)) {
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

    if ($startToolRepos.Count -gt 0) {
        $noBranch = @($startToolRepos | Where-Object { -not $entries[$_].branch }).Count
        Write-Warning ("$($startToolRepos.Count) install lines are Start-Tool <Name>, which carries no entry script and no branch, so those entries were seeded without an entrypoint" +
            $(if ($noBranch -gt 0) { " and $noBranch without a branch (no repository metadata gave a default one)" } else { " and with each repository's default branch" }) +
            ". Copy entrypoint, installKind and branch for them from projects.json before relying on this catalog: $(@($startToolRepos | Select-Object -First 5) -join ', ')$(if ($startToolRepos.Count -gt 5) { ', ...' })")
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

function ConvertTo-VisibleIssueText {
    <#
    .SYNOPSIS
    Writes each character a reader couldn't see, or that would break or reorder the line, as its code point.
    .DESCRIPTION
    Catalog check issues reach the committed report and the console as written, so a
    control, format or other invisible character in one would hide, reorder or split what
    it says. Each such character, and each half of a broken surrogate pair, is written as
    {U+XXXX}: Win{U+200B}Tool. Plain spaces and everything visible stay as they are.
    Invisible means what Test-VisibleText says, so the two can't disagree.
    .PARAMETER Text
    The issue text; $null and empty come back as they are.
    #>
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }
    $builder = [System.Text.StringBuilder]::new($Text.Length + 8)
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ([char]::IsHighSurrogate($character) -and $index + 1 -lt $Text.Length -and [char]::IsLowSurrogate($Text[$index + 1])) {
            $pair = $Text.Substring($index, 2)
            $index++
            if (Test-VisibleText $pair) {
                [void]$builder.Append($pair)
            } else {
                [void]$builder.AppendFormat('{{U+{0:X}}}', [char]::ConvertToUtf32($pair, 0))
            }
        } elseif ([char]::IsSurrogate($character) -or ([int]$character -ne 0x20 -and -not (Test-VisibleText ([string]$character)))) {
            [void]$builder.AppendFormat('{{U+{0:X4}}}', [int]$character)
        } else {
            [void]$builder.Append($character)
        }
    }
    return $builder.ToString()
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
    # Case-sensitive like the schema's enums: -Write copies the value into projects.json as
    # written, so "PowerShell" or "APK" would publish a feed the schema refuses.
    $allowedCategories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($definition in $CategoryDefinitions) {
        [void]$allowedCategories.Add([string]$definition.Slug)
    }
    [void]$allowedCategories.Add("suppressed")

    $allowedDownloadKinds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($kind in @("apk", "crx", "crx-xpi", "download", "exe", "repo", "userscript", "zip", "zip-xpi")) {
        [void]$allowedDownloadKinds.Add($kind)
    }

    $seenRepos = @{}
    $seenIds = @{}
    # Public one-line text and URLs from the rows and the header, checked together below.
    $publicTexts = New-Object System.Collections.Generic.List[object]
    $publicUrls = New-Object System.Collections.Generic.List[object]
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
            # Case-sensitive and anchored at the true end, like the schema's pattern.
            if ($entryId -cnotmatch '^[a-z0-9][a-z0-9-]{2,63}\z') {
                $issues.Add([ordered]@{ repo = $repo; field = "id"; value = $entryId; reason = "id must be 3 to 64 lowercase letters, digits or hyphens, starting with a letter or digit" })
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

        # The title is every row's link text, so it can't be blank. The row's other text may be
        # left out (null), but when it's given it has to say something a reader can see.
        foreach ($field in @('title', 'descriptionOverride', 'currentlyBuildingText', 'language', 'forkOf', 'upstreamLicense', 'readmeReviewNote', 'suppressionReason')) {
            $nonBlank = 'title'.Equals($field) -or (@('descriptionOverride', 'currentlyBuildingText', 'language', 'upstreamLicense', 'forkOf').Contains($field) -and $null -ne $entry[$field])
            $publicTexts.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = $field; text = [string]$entry[$field]; nonBlank = $nonBlank })
        }
        # The action link's destination in the README table row. Plain http passes here
        # because Test-CatalogUrlSchemes already fails it under its own condition.
        foreach ($field in @('liveUrl', 'userscriptUrl')) {
            if (-not [string]::IsNullOrEmpty([string]$entry[$field])) {
                $publicUrls.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = $field; url = [string]$entry[$field]; scheme = 'https?' })
            }
        }

        # \z, not $: in .NET $ also matches before a final newline, which would pass
        # "tool.ps1`n" and break the pasted command.
        # entrypoint and branch reach git and the shell through run.ps1 (git clone -b <branch>,
        # then the entry script), and the expanded command in the README's setup section
        # quotes them the same way. A $ or backtick would expand inside double quotes and a
        # quote, semicolon or space would end the argument, so both take a strict shape.
        $entrypoint = [string]$entry.entrypoint
        if (-not [string]::IsNullOrWhiteSpace($entrypoint) -and $entrypoint -cnotmatch '^(?:[A-Za-z0-9][A-Za-z0-9 ._()+-]*[\\/])*[A-Za-z0-9][A-Za-z0-9 ._()+-]*\.(?:ps1|py|pyw)\z') {
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "entrypoint"; value = $entrypoint; reason = "entrypoint must be a relative .ps1, .py or .pyw path of letters, digits, spaces and ._()+- only" })
        }
        # Ordinal, like the sets above: PowerShell's -ceq and -cnotin compare by culture, which
        # skips zero-width and other ignorable characters, so "py<ZWSP>thon" equals "python"
        # there and would be published as written.
        if (-not [string]::IsNullOrWhiteSpace($entrypoint)) {
            # run.ps1 starts a .ps1 in PowerShell and a .py or .pyw with python, and
            # projects.json carries installKind for anyone else reading the feed; both must agree.
            $expectedKind = if ($entrypoint -like '*.ps1') { 'powershell' } else { 'python' }
            if (-not [string]::Equals([string]$entry.installKind, $expectedKind, [StringComparison]::Ordinal)) {
                $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "installKind"; value = [string]$entry.installKind; reason = "installKind must be $expectedKind for the entrypoint $entrypoint" })
            }
        } elseif (-not [string]::IsNullOrEmpty([string]$entry.installKind) -and -not ([string]::Equals([string]$entry.installKind, 'powershell', [StringComparison]::Ordinal) -or [string]::Equals([string]$entry.installKind, 'python', [StringComparison]::Ordinal))) {
            # Without an entry script nothing else checks it, and the feed carries it as written.
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "installKind"; value = [string]$entry.installKind; reason = "installKind must be powershell, python or left out" })
        }
        # A date the entry is next due for review, so the stale-project check can hold a quiet
        # but finished project to a promise instead of to how long ago it was pushed.
        $reviewBy = $entry.reviewBy
        $reviewByDate = [datetime]::MinValue
        if ($null -ne $reviewBy -and -not ($reviewBy -is [string] -and [datetime]::TryParseExact($reviewBy, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$reviewByDate))) {
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "reviewBy"; value = [string]$reviewBy; reason = "reviewBy must be a date written as YYYY-MM-DD, or left out" })
        }
        $branch = [string]$entry.branch
        if (-not [string]::IsNullOrWhiteSpace($branch) -and $branch -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*\z') {
            $issues.Add([ordered]@{ repo = if ([string]::IsNullOrWhiteSpace($repo)) { $null } else { $repo }; field = "branch"; value = $branch; reason = "branch must start with a letter or digit and use only letters, digits and ._/-" })
        }
    }

    # The README header's text and links, when the catalog has a profileHeader block.
    if (Test-MemberExists -Object $Catalog -Name 'portfolioUrl') {
        $publicUrls.Add([ordered]@{ repo = $null; field = 'portfolioUrl'; url = [string](Get-MemberValue -Object $Catalog -Name 'portfolioUrl'); scheme = 'https' })
    }

    # nonBlank marks text that must say something when present: a blank tagline would fall
    # back to the neutral one unnoticed, and a blank link text or alt renders an empty label.
    # Blank means nothing a reader can see (Test-VisibleText), so NBSP or zero-width text too.
    $header = Get-MemberValue -Object $Catalog -Name 'profileHeader'
    if ($null -ne $header) {
        foreach ($field in @('tagline', 'heading', 'about')) {
            $publicTexts.Add([ordered]@{ repo = $null; field = "profileHeader.$field"; text = [string](Get-MemberValue -Object $header -Name $field); nonBlank = (Test-MemberExists -Object $header -Name $field) })
        }
        $index = 0
        foreach ($language in @(Get-JsonArrayItems (Get-MemberValue -Object $header -Name 'languages'))) {
            $publicTexts.Add([ordered]@{ repo = $null; field = "profileHeader.languages[$index]"; text = [string]$language; nonBlank = $true })
            $index++
        }
        $index = 0
        foreach ($link in @(Get-JsonArrayItems (Get-MemberValue -Object $header -Name 'links'))) {
            $publicTexts.Add([ordered]@{ repo = $null; field = "profileHeader.links[$index].text"; text = [string](Get-MemberValue -Object $link -Name 'text'); nonBlank = $true })
            $publicUrls.Add([ordered]@{ repo = $null; field = "profileHeader.links[$index].url"; url = [string](Get-MemberValue -Object $link -Name 'url'); scheme = 'https' })
            $index++
        }
        $support = Get-MemberValue -Object $header -Name 'support'
        if ($null -ne $support) {
            $publicTexts.Add([ordered]@{ repo = $null; field = "profileHeader.support.imageAlt"; text = [string](Get-MemberValue -Object $support -Name 'imageAlt'); nonBlank = $true })
            foreach ($field in @('url', 'imageUrl')) {
                $publicUrls.Add([ordered]@{ repo = $null; field = "profileHeader.support.$field"; url = [string](Get-MemberValue -Object $support -Name $field); scheme = 'https' })
            }
        }
    }

    # Public one-line text: nothing that breaks a line, hides as a control character,
    # reorders what a reader sees (bidi embedding, override or isolate), or is half of a
    # surrogate pair. The README encoders would drop these, so the catalog refuses them
    # rather than publishing text that differs from what was written. The value in the
    # issue is the offending code point.
    $dashCharacters = -join @(0x2012, 0x2013, 0x2014, 0x2015, 0x2E3A, 0x2E3B, 0xFE31, 0xFE32, 0xFE58 | ForEach-Object { [char]$_ })
    $dashPattern = '[' + $dashCharacters + ']|\s--?\s|(?<=\w)--(?=\w)|-{3,}'
    foreach ($publicText in $publicTexts) {
        $text = [string]$publicText.text
        if ($publicText['nonBlank'] -and -not (Test-VisibleText $text)) {
            $issues.Add([ordered]@{ repo = $publicText.repo; field = $publicText.field; value = $null; reason = "$($publicText.field) must not be blank or only invisible characters" })
            continue
        }
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
            $issues.Add([ordered]@{ repo = $publicText.repo; field = $publicText.field; value = $problem.codePoint; reason = "$($publicText.field) $($problem.reason)" })
        } elseif ('forkOf'.Equals($publicText.field) -and ($text.Length -gt 140 -or $text -cnotmatch '^[A-Za-z0-9-]+/(?!\.\.?\z)[A-Za-z0-9._-]+\z')) {
            # The fork attribution links https://github.com/<forkOf> from the README row, so it
            # takes the schema's owner/repo shape and length too; -Write alone never runs the
            # schema. The issue shows the text with any invisible character as its code point.
            $issues.Add([ordered]@{ repo = $publicText.repo; field = 'forkOf'; value = $text; reason = "forkOf must be owner/repo, at most 140 characters: an account name of letters, digits and hyphens, a slash, then a repository name" })
        } elseif (($dash = [regex]::Match($text, $dashPattern)).Success) {
            # The README is public writing, and its style joins clauses with commas, periods or
            # parentheses, never a dash: no dash character (figure, en, em, horizontal bar, the
            # two- and three-em dashes and their small and vertical forms), and no hyphen used
            # as one, which is one or two hyphens with space (NBSP too) on both sides, two
            # hyphens between words or three in a row. A hyphen in a word, --help, a range
            # (1-5, or 1 to 5) and the minus sign U+2212 are fine.
            $value = if ($dash.Length -eq 1) { 'U+{0:X4}' -f [int]$dash.Value[0] } else { $dash.Value }
            $issues.Add([ordered]@{ repo = $publicText.repo; field = $publicText.field; value = $value; reason = "$($publicText.field) joins clauses with a dash; use a comma, a period or parentheses" })
        }
    }

    # Catalog URLs land in README link destinations, table cells and HTML attributes as
    # written, so a line break, space, quote, angle bracket, backslash or pipe could end
    # the attribute or tag, or split the table row. The issue shows the URL with any line
    # break or other invisible character as its code point, so it stays one line. Header
    # URLs have no scheme check of their own, so they must be https here.
    foreach ($publicUrl in $publicUrls) {
        if ([string]$publicUrl.url -cnotmatch ('^(?i:' + $publicUrl.scheme + ')://[!#-&(-;=?-\[\]-{}~]+\z')) {
            $schemeText = if ('https'.Equals($publicUrl.scheme)) { 'an https' } else { 'an http or https' }
            $issues.Add([ordered]@{ repo = $publicUrl.repo; field = $publicUrl.field; value = [string]$publicUrl.url; reason = "$($publicUrl.field) must be $schemeText URL of printable ASCII with no space, quote, angle bracket, backslash or pipe" })
        }
    }

    # Issue text reaches the report and the console as written, so every character in it a
    # reader couldn't see, or that would break or reorder the line, is shown by its code
    # point: the repo, the value and a reason that quotes one. Done here, once, so no issue
    # added above can skip it.
    foreach ($issue in $issues) {
        foreach ($key in @('repo', 'value', 'reason')) {
            if ($null -ne $issue[$key]) {
                $issue[$key] = ConvertTo-VisibleIssueText ([string]$issue[$key])
            }
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

    if ('powershell'.Equals($language)) { return "powershell" }
    if ('python'.Equals($language)) { return "python" }
    if ('kotlin'.Equals($language)) { return "android" }
    return $null
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
    # The array-preserving parser wraps every array as { __JsonArray, Items }, which
    # ConvertTo-Json would write out as an object; unwrap back to plain arrays first.
    $plainCatalog = $null
    ConvertTo-JsonSchemaValidationValue -Value $catalog -Result ([ref]$plainCatalog)
    $json = ($plainCatalog | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
    Write-AtomicUtf8TextFile -Path $fullPath -Content ($json.TrimEnd() + "`n")
    Write-Host "Drafted $($drafted.Count) suppressed catalog row(s) in $($CatalogPath): $($drafted -join ', '). Review and complete them before publishing."
}
