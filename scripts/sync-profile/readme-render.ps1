# README rendering: the generated header and footer, the category grid, per-category
# sections, project actions, install snippets and the setup and local-validation
# sections. Dot-sourced by scripts/sync-profile.ps1.

function Get-StarText {
    param([object]$Meta)

    if ($Meta -and $Meta.stargazerCount -gt 0 -and $Meta.stargazerCount -ge $MinStarDisplay) {
        return " &#11088;$($Meta.stargazerCount)"
    }
    return ""
}

function ConvertTo-MarkdownText {
    <#
    .SYNOPSIS
    Encodes catalog or GitHub text for README prose, table cells and link labels.
    .DESCRIPTION
    Line breaks become spaces, control characters and bidi embedding, override and
    isolate characters are dropped, an unpaired surrogate becomes U+FFFD, and backslash,
    pipe and square brackets are escaped, so a value cannot end a table cell, open a row
    or close a link label. & < and > become entities, so it cannot open an HTML element
    or smuggle a control character in as "&#8238;". Backticks are escaped too: a code
    span binds before a link, so a backtick in a title could pair with one in the
    description and swallow the link between them, and the escapes above would show as
    written inside one. A dollar sign goes inside a span: GitHub pairs dollar signs into
    math after rendering, so $x$ or $$x$$ would become a formula, and neither \$ nor &#36;
    stops that, while a span does. Emphasis and ordinary accented or non-Latin text pass
    through unchanged. GitHub still turns a bare URL or address in the text into a link of
    its own; that adds no row, cell or element, and nothing here prevents it.

    That link is the one exception. GitHub keeps everything in an autolinked URL as
    written, escapes and entities included, so an escape or entity there would change the
    address (a=1&b=2 would link to a=1&amp;b=2) and a span would cut it short. Inside the
    exact stretch GitHub links, & and $ stay as they are and the characters an escape
    would break are percent-encoded, which is how GitHub writes the address anyway. The
    tail it trims off stays outside: an entity-like &rlm; there is decoded, so it's encoded
    like any other text. Encoded, though, that tail could carry the link on: GitHub runs a
    link to a space or <, and &amp;, &lt; and the backslash escapes hold neither. So when the
    rest of the word holds a character the encoding rewrites that way, an empty
    <span></span> right after the URL ends the link where the raw text's would end.
    .PARAMETER Text
    The untrusted text; $null renders as an empty string.
    .PARAMETER LinkLabel
    The text is a link label. GitHub never autolinks inside one and decodes entities there,
    so a URL in it is encoded like any other text.
    #>
    param(
        [AllowNull()][string]$Text,
        [switch]$LinkLabel
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }
    $oneLine = [regex]::Replace($Text, '\r\n|[\r\n\u0085\u2028\u2029]', ' ')
    $visible = [regex]::Replace($oneLine, '[\p{Cc}\u202A-\u202E\u2066-\u2069]', '')
    # Where GitHub will autolink a bare URL: http(s) by the rules of the bare-URL pass in
    # Get-ReadmeHeaderLinkReference, which reads the rendered header (keep the two in step),
    # and a www. host after a space, * _ ~ or (, which GitHub links as http and the check
    # never probes. Nothing written inside the stretch is a space or a <, so GitHub can't end
    # the link sooner; the boundary below stops it going further.
    $inUrl = [bool[]]::new($visible.Length)
    $boundary = [bool[]]::new($visible.Length + 1)
    if (-not $LinkLabel) {
        $urlStarts = @(
            foreach ($scheme in [regex]::Matches($visible, '(?<![A-Za-z])[A-Za-z]+://')) {
                if ($scheme.Value -in @('http://', 'https://')) {
                    @{ Start = $scheme.Index; Domain = $scheme.Index + $scheme.Length }
                }
            }
            foreach ($www in [regex]::Matches($visible, '(?<=^|[\s*_~(])www\.')) {
                @{ Start = $www.Index; Domain = $www.Index }
            }
        )
        foreach ($urlStart in $urlStarts) {
            $domainStart = $urlStart.Domain
            $domain = [regex]::Match($visible.Substring($domainStart), '^(?:[^\s!-/:-@\[-`{-~\p{P}]|[-._])+')
            if (-not $domain.Success -or $domain.Value -match '_[^.]*(?:\.[^.]*)?\z') {
                continue
            }
            $end = $domainStart + $domain.Length
            while ($end -lt $visible.Length -and $visible[$end] -ne '<' -and " `t`n`r`f`v".IndexOf($visible[$end]) -lt 0) {
                $end++
            }
            $url = $visible.Substring($urlStart.Start, $end - $urlStart.Start)
            $opened = $url.Split('(').Count - 1
            $closed = $url.Split(')').Count - 1
            while ($url.Length -gt 0) {
                $last = $url[$url.Length - 1]
                if ($last -eq ')' -and $closed -gt $opened) {
                    $closed--
                } elseif ($last -eq ';') {
                    $entity = [regex]::Match($url, '&[A-Za-z]+;\z')
                    if ($entity.Success) {
                        $url = $url.Substring(0, $entity.Index)
                        continue
                    }
                } elseif ('?!.,:*_~''"'.IndexOf($last) -lt 0) {
                    break
                }
                $url = $url.Substring(0, $url.Length - 1)
            }
            for ($position = $urlStart.Start; $position -lt $urlStart.Start + $url.Length; $position++) {
                $inUrl[$position] = $true
            }
            # The rest of the word, which GitHub reads on into once the encoding has turned a
            # & < > | [ ] \ or ` in it into text with no space or < to stop at.
            $after = $urlStart.Start + $url.Length
            $wordEnd = $after
            while ($wordEnd -lt $visible.Length -and " `t`n`r`f`v".IndexOf($visible[$wordEnd]) -lt 0) {
                $wordEnd++
            }
            if ($visible.Substring($after, $wordEnd - $after).IndexOfAny([char[]]'&<>|[]\`') -ge 0) {
                $boundary[$after] = $true
            }
        }
    }

    $builder = [System.Text.StringBuilder]::new($visible.Length + 16)
    for ($index = 0; $index -lt $visible.Length; $index++) {
        $character = $visible[$index]
        if ($boundary[$index]) {
            [void]$builder.Append('<span></span>')
        }
        if ([char]::IsHighSurrogate($character) -and $index + 1 -lt $visible.Length -and [char]::IsLowSurrogate($visible[$index + 1])) {
            [void]$builder.Append($character).Append($visible[$index + 1])
            $index++
            continue
        }
        if ([char]::IsSurrogate($character)) {
            [void]$builder.Append([char]0xFFFD)
            continue
        }
        if ($inUrl[$index]) {
            switch -CaseSensitive ([string]$character) {
                '\' { [void]$builder.Append('%5C') }
                '|' { [void]$builder.Append('%7C') }
                '[' { [void]$builder.Append('%5B') }
                ']' { [void]$builder.Append('%5D') }
                '`' { [void]$builder.Append('%60') }
                '>' { [void]$builder.Append('%3E') }
                default { [void]$builder.Append($character) }
            }
            continue
        }
        switch -CaseSensitive ([string]$character) {
            '\' { [void]$builder.Append('\\') }
            '|' { [void]$builder.Append('\|') }
            '[' { [void]$builder.Append('\[') }
            ']' { [void]$builder.Append('\]') }
            '`' { [void]$builder.Append('\`') }
            '&' { [void]$builder.Append('&amp;') }
            '<' { [void]$builder.Append('&lt;') }
            '>' { [void]$builder.Append('&gt;') }
            '$' { [void]$builder.Append('<span>$</span>') }
            default { [void]$builder.Append($character) }
        }
    }
    return $builder.ToString()
}

function ConvertTo-HtmlText {
    <#
    .SYNOPSIS
    Encodes catalog text for an HTML element or attribute in the README header.
    .DESCRIPTION
    GitHub shows the inside of an HTML block as written, so the Markdown escapes from
    ConvertTo-MarkdownText would appear as backslashes there. Line breaks become spaces,
    because a blank line would end the block, control and bidi characters are dropped
    the same way, and WebUtility.HtmlEncode turns & < > " and ' into entities. GitHub
    finds math inside HTML blocks too, so a dollar sign in element text goes inside a
    span, as in ConvertTo-MarkdownText.
    .PARAMETER Text
    The untrusted text; $null renders as an empty string.
    .PARAMETER Attribute
    The text is an attribute value. GitHub doesn't look for math there, and a span would
    show as written, so a dollar sign stays as it is.
    #>
    param(
        [AllowNull()][string]$Text,
        [switch]$Attribute
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }
    $oneLine = [regex]::Replace($Text, '\r\n|[\r\n\u0085\u2028\u2029]', ' ')
    $visible = [regex]::Replace($oneLine, '[\p{Cc}\u202A-\u202E\u2066-\u2069]', '')
    $encoded = [System.Net.WebUtility]::HtmlEncode($visible)
    if ($Attribute) {
        return $encoded
    }
    return $encoded.Replace('$', '<span>$</span>')
}

function Get-ProjectLink {
    param(
        [hashtable]$Entry,
        [object]$Meta
    )

    return "[**$(ConvertTo-MarkdownText $Entry.title -LinkLabel)**]($(Get-RepoUrl $Entry))$(Get-StarText $Meta)"
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

function Get-ProfileNavLabel {
    param([string]$Slug)

    if ($Slug -eq "misc") {
        return "Forks"
    }

    return Get-CategoryDisplayName -Slug $Slug
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
    # Live and userscript URLs come from the catalog. Percent-encode what would end or
    # break a Markdown link destination or its table cell; a well-formed URL is unchanged.
    # Control characters too, since a line break here would end the row. -Write refuses all
    # of these before it renders and -Check fails on them, but the renderer doesn't lean on either.
    $url = ([string]$action["url"]).Replace(' ', '%20').Replace('(', '%28').Replace(')', '%29').Replace('<', '%3C').Replace('>', '%3E').Replace('|', '%7C').Replace('\', '%5C')
    # C1 controls (0x80-0x9F) too, as their UTF-8 bytes: U+0085 is a line break to some readers.
    $url = [regex]::Replace($url, '[\x00-\x1F\x7F-\x9F]', { param($match) -join ([System.Text.Encoding]::UTF8.GetBytes($match.Value) | ForEach-Object { '%{0:X2}' -f $_ }) })
    # Every row's action says Download, Launch, Install or Repo, so a screen reader listing the
    # links heard the same few names for 190 different places. The link is written as HTML so
    # it can carry a name that says whose it is (GitHub keeps aria-label), while it still
    # shows the short word. Both values are attributes now: the quote and ampersand are
    # encoded, and a pipe too, which would split the table cell. The name comes from catalog
    # text, so brackets and backticks are encoded as well: in the attribute they read the
    # same, and if the tag were ever taken for text they couldn't start a link or a code span.
    $title = [string]$Entry.title
    if ([string]::IsNullOrWhiteSpace($title)) { $title = [string]$Entry.repo }
    $name = switch ([string]$action["kind"]) {
        "release" { if ([string]::Equals($label, 'Download', [StringComparison]::Ordinal)) { "Download $title" } else { "Download $title ($label)" } }
        "repo" { "$title repository" }
        default { "$label $title" }
    }
    $href = $url.Replace('&', '&amp;').Replace('"', '%22')
    $ariaLabel = [System.Net.WebUtility]::HtmlEncode($name).Replace('|', '&#124;').Replace('[', '&#91;').Replace(']', '&#93;').Replace('`', '&#96;')
    $text = if ($action["kind"] -eq "release") { "<kbd>&#11015;&nbsp;$([System.Net.WebUtility]::HtmlEncode($label))</kbd>" } else { [System.Net.WebUtility]::HtmlEncode($label) }
    return "<a href=`"$href`" aria-label=`"$ariaLabel`">$text</a>"
}

function Get-InstallSnippet {
    # One short line per project. The clone, requirements and run steps live in run.ps1,
    # which looks the branch and entry script up in projects.json; the first-time setup
    # section shows the steps written out in full.
    param([hashtable]$Entry)

    if ([string]::IsNullOrWhiteSpace([string]$Entry.entrypoint)) {
        return $null
    }
    return "irm https://raw.githubusercontent.com/$Owner/$Owner/main/run.ps1 | iex; Start-Tool $($Entry.repo)"
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
                    @{ Expression = { ConvertTo-OrdinalSortKey $_.repo } } |
        Select-Object -First 3)

    if ($picks.Count -eq 0) {
        return $null
    }

    $links = foreach ($entry in $picks) {
        "[**$(ConvertTo-MarkdownText $entry.title -LinkLabel)**]($(Get-RepoUrl $entry))"
    }

    return "Suggested starting points: $($links -join ', ')."
}

function Get-ProfilePortfolioUrl {
    <#
    .SYNOPSIS
    Returns the canonical public portfolio origin used by generated profile links.
    .DESCRIPTION
    Defaults to the -PortfolioUrl parameter or the catalog's portfolioUrl, whichever the
    run resolved; the cross-surface probe is handed the same value, so published links
    and drift probes can never disagree. Falls back to the owner's GitHub Pages origin
    when neither is set, when -PortfolioUrl '' asks for it, and when the configured value
    isn't a plain https URL that can sit in an href as written.
    #>
    # Script scope only: Test-ProfileState and Test-PortfolioCrossSurfaceDrift both
    # declare a local $PortfolioUrl parameter, and an unqualified lookup would bind
    # to the caller's local instead of the configured origin. Get-Variable keeps this
    # StrictMode-safe when the script is dot-sourced without its param block running.
    $configured = $null
    $portfolioVariable = Get-Variable -Name "PortfolioUrl" -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $portfolioVariable) { $configured = [string]$portfolioVariable.Value }
    if (-not [string]::IsNullOrWhiteSpace($configured)) {
        $url = $configured.Trim()
        # The same shape Test-CatalogShape holds the catalog value to; -PortfolioUrl skips
        # that check, so a value that could leave its attribute isn't used.
        if ($url -cmatch '^(?i:https)://[!#-&(-;=?-\[\]-{}~]+\z') {
            if (-not $url.EndsWith("/")) { $url += "/" }
            return $url
        }
    }
    return "https://$($Owner.ToLowerInvariant()).github.io/"
}

function Get-ProfileSetupRawUrl {
    return "https://raw.githubusercontent.com/$Owner/$Owner/main/setup.ps1"
}

function Get-ProfileSetupSourceUrl {
    return "https://github.com/$Owner/$Owner/blob/main/setup.ps1"
}

function Get-ProfileRouteDefinitions {
    $powershellLink = New-CategoryLink "powershell"
    $pythonLink = New-CategoryLink "python"
    $desktopLink = New-CategoryLink "desktop"
    $extensionsLink = New-CategoryLink "extensions"
    $androidLink = New-CategoryLink "android"
    $webLink = New-CategoryLink "web"
    $securityLink = New-CategoryLink "security"
    $mediaLink = New-CategoryLink "media"
    $guidesLink = New-CategoryLink "guides"
    $miscLink = New-CategoryLink "misc"
    $setupLink = "[First-time setup](#first-time-setup)"
    $validationLink = "[Local validation](#local-validation)"

    return @(
        [ordered]@{
            Signal = "<kbd>PS</kbd>"
            Want = "Automate something on Windows"
            Best = "$powershellLink or $desktopLink"
            Find = "PowerShell scripts you can paste and run, plus downloadable desktop tools."
            Action = "[<kbd>Browse &#8594;</kbd>](#powershell-system-utilities)"
        },
        [ordered]@{
            Signal = "<kbd>PY</kbd>"
            Want = "Run a Python tool"
            Best = $pythonLink
            Find = "Desktop apps, media tools, automation scripts, and utilities."
            Action = "[<kbd>Browse &#8594;</kbd>](#python-desktop-applications)"
        },
        [ordered]@{
            Signal = "<kbd>WEB</kbd>"
            Want = "Open something in a browser"
            Best = $webLink
            Find = "Live web apps and self-hosted dashboards. No install needed."
            Action = "[<kbd>Open &#8594;</kbd>](#web-applications)"
        },
        [ordered]@{
            Signal = "<kbd>EXT</kbd>"
            Want = "Add something to Chrome or Firefox"
            Best = $extensionsLink
            Find = "Browser extensions and userscripts you can install in one click."
            Action = "[<kbd>Install &#8594;</kbd>](#browser-extensions--userscripts)"
        },
        [ordered]@{
            Signal = "<kbd>APK</kbd>"
            Want = "Get an Android app"
            Best = $androidLink
            Find = "APKs you can sideload, plus Android source projects."
            Action = "[<kbd>Download &#8594;</kbd>](#android-applications)"
        },
        [ordered]@{
            Signal = "<kbd>SEC</kbd>"
            Want = "Check or lock down a network"
            Best = $securityLink
            Find = "Security auditing, DNS tools, and hardening scripts."
            Action = "[<kbd>Browse &#8594;</kbd>](#security--networking)"
        },
        [ordered]@{
            Signal = "<kbd>MED</kbd>"
            Want = "Fix, convert, or capture media"
            Best = $mediaLink
            Find = "Video repair, stream capture, compression, and format conversion."
            Action = "[<kbd>Download &#8594;</kbd>](#media--conversion-tools)"
        },
        [ordered]@{
            Signal = "<kbd>DOC</kbd>"
            Want = "Read a how-to guide"
            Best = $guidesLink
            Find = "Step-by-step guides, checklists, and reference material."
            Action = "[<kbd>Read &#8594;</kbd>](#guides--resources)"
        },
        [ordered]@{
            Signal = "<kbd>OPS</kbd>"
            Want = "Contribute to this repo"
            Best = "$setupLink or $validationLink"
            Find = "Dev setup, linting, testing, and validation for contributors."
            Action = "[<kbd>Verify &#8594;</kbd>](#local-validation)"
        },
        [ordered]@{
            Signal = "<kbd>ALL</kbd>"
            Want = "Search everything"
            Best = "[Full portfolio]($(Get-ProfilePortfolioUrl)) or $miscLink"
            Find = "The full catalog with filters, search, and download links."
            Action = "[<kbd>Search &#8594;</kbd>]($(Get-ProfilePortfolioUrl))"
        }
    )
}

function Get-ToolCatalogDescription {
    param([string]$Slug)

    switch ($Slug) {
        "powershell" { return "Scripts and tools for Windows." }
        "python" { return "Desktop apps, utilities, and creative tools." }
        "web" { return "Browser-based tools and dashboards." }
        "extensions" { return "Chrome/Firefox add-ons and userscripts." }
        "android" { return "Apps for your phone." }
        "security" { return "Network auditing and hardening." }
        "desktop" { return "Windows and cross-platform apps." }
        "media" { return "Video, audio, and stream tools." }
        "guides" { return "How-to guides and reference docs." }
        "misc" { return "Forks and side projects." }
        default { return "Public projects." }
    }
}

function Get-ToolCatalogActionLabel {
    param([string]$Slug)

    switch ($Slug) {
        "web" { return "Open" }
        "extensions" { return "Install" }
        "android" { return "Download" }
        "desktop" { return "Download" }
        "media" { return "Download" }
        "guides" { return "Read" }
        "misc" { return "Explore" }
        default { return "Browse" }
    }
}

function New-ToolCatalogCell {
    param(
        [string]$Slug,
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $definition = $CategoryDefinitions | Where-Object { $_.Slug -eq $Slug } | Select-Object -First 1
    if (-not $definition) {
        return ""
    }

    $lookup = $RepoLookup
    $items = @($Entries | Where-Object { $_.category -eq $Slug } | Sort-Object @{ Expression = {
        $key = ([string]$_.repo).ToLowerInvariant()
        $m = if ($lookup -and $lookup.ContainsKey($key)) { $lookup[$key] } else { $null }
        if ($m -and $null -ne $m.stargazerCount) { [int]$m.stargazerCount } else { 0 }
    }; Descending = $true }, @{ Expression = { ConvertTo-OrdinalSortKey $_.repo } })

    $picks = @($items |
        Sort-Object @{ Expression = { if ($_.featured -eq $true) { 0 } else { 1 } } },
                    @{ Expression = { if ($_.featuredRank) { [int]$_.featuredRank } else { [int]$_.order } } },
                    @{ Expression = { ConvertTo-OrdinalSortKey $_.repo } } |
        Select-Object -First 3)

    $description = Get-ToolCatalogDescription -Slug $Slug
    $icon = Get-CategoryIcon -Slug $Slug
    $heading = if ([string]::IsNullOrWhiteSpace($icon)) {
        "**$($definition.DisplayName)**"
    } else {
        "$icon **$($definition.DisplayName)**"
    }
    if ($picks.Count -eq 0) {
        # An empty category renders no section (New-CategorySection), so a Browse button
        # here would point at an anchor that does not exist.
        return "$heading<br/>$description<br/><sub>No public rows</sub>"
    }

    $pickLinks = @($picks | ForEach-Object { "[**$(ConvertTo-MarkdownText $_.title -LinkLabel)**]($(Get-RepoUrl $_))" })
    $actionLabel = Get-ToolCatalogActionLabel -Slug $Slug
    $anchor = Get-CategoryAnchor $Slug
    # Several cards say Browse or Download, so each button is named for its category, as the
    # row actions are for their projects.
    $buttonName = [System.Net.WebUtility]::HtmlEncode("$actionLabel $($definition.DisplayName)").Replace('|', '&#124;').Replace('[', '&#91;').Replace(']', '&#93;')

    return "$heading<br/>$description<br/><sub>$($pickLinks -join '<br/>')</sub><br/><a href=`"#$anchor`" aria-label=`"$buttonName`"><kbd>$actionLabel &#8594;</kbd></a>"
}

function New-ToolCatalogSection {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $rows = @(
        @("powershell", "python", "web", "extensions", "android"),
        @("security", "desktop", "media", "guides", "misc")
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("### $ToolCatalogHeading")
    $lines.Add("")
    # One sentence for a visitor who arrives from a search result and has no idea what this
    # page is. The count comes from the catalog so it cannot go stale.
    # "Public projects", not "open-source tools": the count includes guides, and a few repos
    # carry source-available licenses that GitHub reports as "Other".
    $lines.Add("This is the index of the $(@($Entries).Count) public projects I've published, mostly tools and apps, sorted by where they run, for anyone who wants something that works on the setup they already have.")
    $lines.Add("")
    $lines.Add("Pick a category to jump in. Each one has a few suggestions to start with.")
    $lines.Add("")

    foreach ($row in $rows) {
        $headers = @($row | ForEach-Object { Get-CategoryDisplayName -Slug $_ })
        $cells = @($row | ForEach-Object { New-ToolCatalogCell -Slug $_ -Entries $Entries -RepoLookup $RepoLookup })
        $lines.Add("| $($headers -join ' | ') |")
        $lines.Add("|$((@(':---') * $headers.Count) -join '|')|")
        $lines.Add("| $($cells -join ' | ') |")
        $lines.Add("")
    }

    return ($lines -join [Environment]::NewLine).TrimEnd()
}

function New-DiscoverySection {
    $routes = @(Get-ProfileRouteDefinitions)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("### Start Here")
    $lines.Add("")
    $lines.Add("Pick what you're looking for. Each section has install commands, download links, or a live demo you can try right now.")
    $lines.Add("")
    # Three columns instead of five. The old "Best category" column duplicated the target of
    # the Action link, and five prose columns forced horizontal scrolling on phone widths.
    $lines.Add("| I want to... | What you'll find | Action |")
    $lines.Add("|:-------------|:-----------------|:-------|")
    foreach ($route in $routes) {
        $lines.Add("| $($route.Signal) $($route.Want) | $($route.Find) | $($route.Action) |")
    }

    return ($lines -join [Environment]::NewLine)
}

function New-FirstTimeSetupSection {
    $content = @'
<a id="first-time-setup"></a>

<details>
<summary><b>&#128190; First-time setup</b> &middot; <i>Inspect first, then install only the tooling your machine is missing.</i></summary>
<br/>

The setup path checks for PowerShell 7, Python, pip, and Git before changing anything, then refreshes the current shell so the project snippets and validation tools work immediately. On a fresh Windows machine, open **PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/__PROFILE_OWNER__/__PROFILE_OWNER__/main/setup.ps1 | iex
```

Inspect before installing:

```powershell
$u='https://raw.githubusercontent.com/__PROFILE_OWNER__/__PROFILE_OWNER__/main/setup.ps1'; $p="$env:TEMP\SysAdminDoc-setup.ps1"; irm $u -OutFile $p; notepad $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -CheckOnly
```

| Step | Behavior |
|:-----|:---------|
| Checks first | Reports PowerShell 7, Python, pip, and Git state before installing missing tools. |
| Inspect before installing | Save the script, review it, then run `-CheckOnly` to report PowerShell 7, Python, Git, pip, and winget state without installing. |
| Installs with Windows tooling | Uses `winget` for [PowerShell 7](https://learn.microsoft.com/powershell/), [Python 3.13](https://www.python.org/), and [Git for Windows](https://git-scm.com/). |
| Refreshes the shell | Updates the current `PATH` so install snippets and validation commands work without reopening PowerShell. |
| Records diagnostics | Writes a best-effort transcript to `%TEMP%\SysAdminDoc-setup-*.log`. |
| Shows its source | [`setup.ps1`](https://github.com/__PROFILE_OWNER__/__PROFILE_OWNER__/blob/main/setup.ps1) is the exact script being run. |

Already have PowerShell 7, Python, pip, and Git? Skip this section and open the category you need.

Every PowerShell and Python project on this page starts with one line like this:

```powershell
irm https://raw.githubusercontent.com/__PROFILE_OWNER__/__PROFILE_OWNER__/main/run.ps1 | iex; Start-Tool <Name>
```

[`run.ps1`](https://github.com/__PROFILE_OWNER__/__PROFILE_OWNER__/blob/main/run.ps1) looks the project up in the public `projects.json` feed, clones it into `%TEMP%` (or updates the copy that's already there), installs its `requirements.txt` if it has one, and starts its entry script. Written out in full, `Start-Tool <Name>` runs:

```text
$d="$env:TEMP\<Name>"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b <branch> https://github.com/__PROFILE_OWNER__/<Name> $d}; if(Test-Path "$d\requirements.txt"){python -m pip install -q -r "$d\requirements.txt"}; & "$d\<entry script>"
```

A `.py` entry script runs with `python` instead of `&`. Both one-liners download over TLS 1.2, which Windows PowerShell uses by default on Windows 10 and later. On older Windows, run `[Net.ServicePointManager]::SecurityProtocol = 'Tls12'` first.

</details>
'@
    return $content.Replace('__PROFILE_OWNER__', [string]$Owner)
}

function New-LocalValidationSection {
    # The full lane list lives in .github/CONTRIBUTING.md: it is contributor material, and
    # at 70 lines it dominated the end of a page most visitors open to find a tool.
    $content = @'
<a id="local-validation"></a>

<details>
<summary><b>&#9989; Local validation</b> &middot; <i>For contributors: check the profile before you push.</i></summary>
<br/>

Changing the catalog or the generator? Run this from the repo root first:

```powershell
pwsh -NoProfile -File .\scripts\validate-local.ps1
```

It lints, analyzes, tests and re-checks the generated profile. Every lane, switch and troubleshooting option is in [CONTRIBUTING.md](https://github.com/__PROFILE_OWNER__/__PROFILE_OWNER__/blob/main/.github/CONTRIBUTING.md#local-validation).

</details>
'@
    return $content.Replace('__PROFILE_OWNER__', [string]$Owner)
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
    }; Descending = $true }, @{ Expression = { ConvertTo-OrdinalSortKey $_.repo } })
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
                $line = "$(Get-ProjectLink $entry $meta) &middot; $(Get-DisplayDescription $entry $meta)"
                $action = Get-ActionLink $entry $meta $Definition.Slug
                if ($action -match 'releases/latest') {
                    $line += " &nbsp;$action"
                }
                $lines.Add($line)
                $snippet = Get-InstallSnippet $entry
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
                $language = if (Test-VisibleText ([string]$entry.language)) {
                    [string]$entry.language
                } elseif ($meta -and $meta.primaryLanguage -and $meta.primaryLanguage.name) {
                    [string]$meta.primaryLanguage.name
                } else {
                    ""
                }
                $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-DisplayDescription $entry $meta) | $(ConvertTo-MarkdownText $language) | $(Get-ActionLink $entry $meta $Definition.Slug) |")
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

function New-ProfileAssetSvgs {
    <#
    .SYNOPSIS
    Returns the generated profile SVG assets, which is an empty set for the text-only README.
    .DESCRIPTION
    The README header and footer are plain text and reference no generated image, so
    nothing is rendered, committed, budgeted or drift-checked, and no contribution
    calendar is fetched. Test-ProfileState reports any file under -AssetsPath as out of
    sync. Bringing image chrome back is a code change: add the renderer here together
    with the README markup that references it.
    #>
    [CmdletBinding()]
    param()

    return [ordered]@{}
}

function New-ProfileChrome {
    # Minimal text header. Everything personal in it (tagline, languages, greeting, about
    # text, links and support button) comes from the catalog's profileHeader block, so a
    # run for another account publishes only what its own catalog says. With no block the
    # header is a neutral tagline and the category nav. Satisfies the minimal header
    # contract in Test-ReadmeExperience: the README starts with the tagline paragraph and
    # exposes plain category nav anchors with no profile-asset header image.
    param(
        # Categories that rendered a section. The nav links only to these: an empty category
        # renders no section, so its anchor would be dead. Omitted, every category is linked.
        [string[]]$CategorySlugs,
        # The catalog's profileHeader block; $null renders the neutral header.
        [object]$Header
    )

    # Text a reader can't see (NBSP, zero-width or bidi characters alone) counts as missing
    # throughout, so it can't draw an empty heading, an empty language slot or an arrow-only link.
    $tagline = [string](Get-MemberValue -Object $Header -Name 'tagline')
    if (-not (Test-VisibleText $tagline)) {
        $tagline = "Public projects by $Owner"
    }
    $languages = @(Get-JsonArrayItems (Get-MemberValue -Object $Header -Name 'languages') | Where-Object { Test-VisibleText ([string]$_) } | ForEach-Object { ConvertTo-HtmlText ([string]$_) })
    $taglineLine = '<p align="center"><b>' + (ConvertTo-HtmlText $tagline) + '</b>'
    if ($languages.Count -gt 0) {
        $taglineLine += '<br/><sub>' + ($languages -join ' &middot; ') + '</sub>'
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($taglineLine + '</p>')
    $lines.Add('')
    $heading = [string](Get-MemberValue -Object $Header -Name 'heading')
    if (Test-VisibleText $heading) {
        # A run of # at the end of an ATX heading, after a space, is read as closing markup and
        # dropped, so its first # is escaped. One right after other text (C#, a URL's #) isn't
        # markup, and an escape there would break an autolinked URL.
        $lines.Add('## ' + ((ConvertTo-MarkdownText $heading).Trim() -replace '(?<=^|[ \t])#+$', '\$0'))
        $lines.Add('')
    }
    $about = [string](Get-MemberValue -Object $Header -Name 'about')
    if (Test-VisibleText $about) {
        # The about text is a paragraph on its own line, so its first characters could open
        # a heading, list, rule or fence, and leading spaces a code block. Backticks, < and
        # > are already escaped or entities by now, and tabs dropped. Only a marker that
        # really opens a block is escaped: a rule line (three or more of one of - * _), a
        # list marker or 1 to 6 #s followed by a space, a tilde fence, an ordered-list number
        # followed by a space. Leading emphasis (*x*, **x**, _x_, ~~x~~) and a #hashtag stay
        # as written. The line after a blank one can't underline a heading, so = is safe.
        $aboutText = (ConvertTo-MarkdownText $about).TrimStart()
        if ($aboutText -match '^([-*_])(?: *\1){2,} *\z' -or $aboutText -match '^(?:[-+*](?: |\z)|#{1,6}(?: |\z)|~~~)') {
            $aboutText = '\' + $aboutText
        } elseif ($aboutText -match '^([0-9]{1,9})([.)])(?= |\z)') {
            $aboutText = $Matches[1] + '\' + $Matches[2] + $aboutText.Substring($Matches[0].Length)
        }
        $lines.Add($aboutText)
        $lines.Add('')
    }
    # Test-CatalogShape refuses any other URL before anything is written, but the renderer
    # doesn't lean on it: a URL that could leave its attribute, or isn't https, isn't rendered.
    $safeUrlPattern = '^(?i:https)://[!#-&(-;=?-\[\]-{}~]+\z'
    $links = @(Get-JsonArrayItems (Get-MemberValue -Object $Header -Name 'links') | ForEach-Object {
        $url = [string](Get-MemberValue -Object $_ -Name 'url')
        # Checked before encoding: a lone NBSP encodes to &#160;, which no longer looks blank.
        $text = [string](Get-MemberValue -Object $_ -Name 'text')
        if ($url -cmatch $safeUrlPattern -and (Test-VisibleText $text)) {
            '<a href="' + $url + '"><b>' + (ConvertTo-HtmlText $text) + ' &#8594;</b></a>'
        }
    })
    if ($links.Count -gt 0) {
        $lines.Add('<p align="center">' + ($links -join ' &middot; ') + '</p>')
        $lines.Add('')
    }
    $navSlugs = @("powershell", "python", "web", "extensions", "android", "security", "desktop", "media", "guides", "misc")
    if ($PSBoundParameters.ContainsKey('CategorySlugs')) {
        $navSlugs = @($navSlugs | Where-Object { $CategorySlugs -ccontains $_ })
    }
    $categoryLinks = @($navSlugs | ForEach-Object {
        $slug = [string]$_
        $displayName = Get-ProfileNavLabel -Slug $slug
        "<a href=`"#$((Get-CategoryAnchor $slug))`">$displayName</a>"
    })
    if ($categoryLinks.Count -gt 0) {
        $lines.Add('<p align="center">' + ($categoryLinks -join ' &middot; ') + '</p>')
        $lines.Add('')
    }
    $support = Get-MemberValue -Object $Header -Name 'support'
    $supportUrl = [string](Get-MemberValue -Object $support -Name 'url')
    $supportImageUrl = [string](Get-MemberValue -Object $support -Name 'imageUrl')
    # The image is the link's only content, so without alt text a reader can see (or hear)
    # the button has no name; like a link with no text, it isn't drawn.
    $supportAlt = [string](Get-MemberValue -Object $support -Name 'imageAlt')
    if ($supportUrl -cmatch $safeUrlPattern -and $supportImageUrl -cmatch $safeUrlPattern -and (Test-VisibleText $supportAlt)) {
        $lines.Add('<p align="center">')
        $lines.Add('  <a href="' + $supportUrl + '">')
        $lines.Add('    <img height="36" src="' + $supportImageUrl + '" alt="' + (ConvertTo-HtmlText $supportAlt -Attribute) + '" />')
        $lines.Add('  </a>')
        $lines.Add('</p>')
        $lines.Add('')
    }
    return ($lines -join [Environment]::NewLine)
}

function New-ProfileFooter {
    # Minimal, text-only footer: no SVG/image chrome. The contact link opens the portfolio's
    # contact section, which carries email and LinkedIn, so the README publishes no address.
    $portfolioUrl = Get-ProfilePortfolioUrl
    return @(
        '---'
        ''
        ('<p align="center"><a href="' + $portfolioUrl + '"><b>See everything</b></a> &middot; <a href="https://github.com/' + $Owner + '?tab=repositories">All repos</a> &middot; <a href="' + $portfolioUrl + '#connect">Get in touch</a></p>')
    ) -join [Environment]::NewLine
}

function Update-Header {
    param(
        [string[]]$CategorySlugs,
        [object]$Header
    )

    return (New-ProfileChrome @PSBoundParameters).TrimEnd()
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
    $categorySections = New-Object System.Collections.Generic.List[string]
    $renderedSlugs = New-Object System.Collections.Generic.List[string]
    foreach ($definition in $CategoryDefinitions) {
        $section = New-CategorySection -Entries $entries -RepoLookup $repoLookup -Definition $definition
        if ([string]::IsNullOrEmpty($section)) {
            continue
        }
        $categorySections.Add($section)
        $renderedSlugs.Add([string]$definition.Slug)
    }
    $footer = New-ProfileFooter
    $header = Update-Header -CategorySlugs $renderedSlugs.ToArray() -Header (Get-MemberValue -Object $Catalog -Name 'profileHeader')
    $header = [regex]::Replace($header, '(\r?\n\s*---\s*)+$', [Environment]::NewLine + [Environment]::NewLine + '---')

    $blocks = New-Object System.Collections.Generic.List[string]
    $blocks.Add($header)
    $blocks.Add("")
    if ($includeGeneratedNotice) {
        $blocks.Add($GeneratedCatalogNotice)
        $blocks.Add("")
    }
    $blocks.Add((New-ToolCatalogSection -Entries $entries -RepoLookup $repoLookup))
    $blocks.Add("")

    foreach ($section in $categorySections) {
        $blocks.Add($section)
        $blocks.Add("")
    }

    $blocks.Add((New-FirstTimeSetupSection))
    $blocks.Add("")
    $blocks.Add((New-LocalValidationSection))
    $blocks.Add("")
    $blocks.Add($footer)
    $blocks.Add("")
    return ($blocks -join [Environment]::NewLine)
}
