# README rendering: the generated header (hero, proof line, pitch, shelf nav), the
# flagship cards, the problem index, the trust notes, the latest releases, the shelves,
# the footer, and the button each project links from. Dot-sourced by
# scripts/sync-profile.ps1.

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

function Get-ProfileAssetUrl {
    # Images are written as absolute raw URLs on the profile repository's main branch.
    # GitHub rewrites a relative img src, but not a relative srcset in <picture>, and a
    # README read anywhere else (the portfolio, a feed reader) has no base to resolve
    # one against.
    param([string]$Path)

    if ($Path -cmatch '^https://') { return $Path }
    return "https://raw.githubusercontent.com/$Owner/$Owner/main/$($Path.TrimStart('/'))"
}

function Get-ActionButton {
    <#
    .SYNOPSIS
    Picks the button a project's primary action shows and the name a screen reader hears.
    .DESCRIPTION
    Returns the button file under assets/buttons and alt text naming the project. A
    release is sorted by what its latest assets are: an APK, a browser extension, a
    Windows build, or a plain download. Without inspected assets the catalog's download
    kind decides.
    #>
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [string]$Category,
        # The name the alt text uses; the catalog title when omitted.
        [string]$DisplayName
    )

    $action = Get-PrimaryAction $Entry $Meta $Category
    $title = if (Test-VisibleText $DisplayName) { $DisplayName } else { [string]$Entry.title }
    if (-not (Test-VisibleText $title)) { $title = [string]$Entry.repo }
    $button = switch ([string]$action["kind"]) {
        "live" { @{ file = "web"; alt = "Open $title in your browser" } }
        "install" { @{ file = "userscript"; alt = "Install the $title userscript" } }
        "repo" {
            if ($Category -eq "guides") { @{ file = "guide"; alt = "Read the $title guide" } }
            else { @{ file = "source"; alt = "View the $title source on GitHub" } }
        }
        default {
            $kind = Get-EffectiveDownloadKind -Entry $Entry -Category $Category
            $names = @(Get-ReleaseAssetNamesFromMeta -Meta $Meta) -join "`n"
            # A Morphe patch bundle is installed by adding its repository as a source in
            # Morphe Manager, so that link leads and the file download follows it
            # (Get-MorpheDownloadLink). A Windows build outranks a browser build outside the
            # extensions category: a desktop app can ship a companion extension (a web
            # clipper) beside its installer.
            if ($kind -eq "morphe" -or (Test-MorpheBundleRelease -Meta $Meta)) {
                @{ file = "morphe"; alt = "Add $title to Morphe"; url = Get-MorpheSourceUrl $Entry }
            } elseif ($kind -eq "apk") {
                @{ file = "apk"; alt = "Get the $title APK" }
            } elseif ($Category -eq "extensions" -or $kind -in @("crx", "xpi", "crx-xpi", "zip-xpi")) {
                @{ file = "extension"; alt = "Get the $title browser extension" }
            } elseif ($kind -eq "exe" -or $Category -eq "powershell" -or $names -match '(?im)\.(exe|msi|msix)$|win(?:dows)?[-_.]?(?:x64|x86|arm64)') {
                @{ file = "windows"; alt = "Download $title for Windows" }
            } elseif ($names -match '(?im)\.(crx|xpi)$|[-_.](chrome|chromium|firefox|edge)[-_.]') {
                @{ file = "extension"; alt = "Get the $title browser extension" }
            } else {
                @{ file = "download"; alt = "Download $title" }
            }
        }
    }
    return [ordered]@{
        kind = [string]$action["kind"]
        url = if ($button.ContainsKey("url")) { [string]$button.url } else { [string]$action["url"] }
        file = [string]$button.file
        alt = [string]$button.alt
    }
}

function ConvertTo-SafeHref {
    # Live and userscript URLs come from the catalog. Percent-encode what would end or
    # break the attribute or its table cell; a well-formed URL is unchanged. Control
    # characters too, C1 included as their UTF-8 bytes (U+0085 is a line break to some
    # readers). -Write refuses all of these before it renders and -Check fails on them,
    # but the renderer doesn't lean on either.
    param([string]$Url)

    $url = $Url.Replace(' ', '%20').Replace('(', '%28').Replace(')', '%29').Replace('<', '%3C').Replace('>', '%3E').Replace('|', '%7C').Replace('\', '%5C')
    $url = [regex]::Replace($url, '[\x00-\x1F\x7F-\x9F]', { param($match) -join ([System.Text.Encoding]::UTF8.GetBytes($match.Value) | ForEach-Object { '%{0:X2}' -f $_ }) })
    return $url.Replace('&', '&amp;').Replace('"', '%22')
}

function ConvertTo-ButtonAltText {
    # The alt text names whose button it is, so a screen reader listing 190 links doesn't
    # hear the same few words. It comes from catalog text, so the quote and ampersand are
    # encoded, and a pipe too, which would split a table cell; brackets and backticks as
    # well, so the tag read as text couldn't start a link or a code span.
    param([string]$Text)

    return [System.Net.WebUtility]::HtmlEncode($Text).Replace('|', '&#124;').Replace('[', '&#91;').Replace(']', '&#93;').Replace('`', '&#96;')
}

function Get-ActionLink {
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [string]$Category,
        [int]$Height = 24,
        [string]$DisplayName
    )

    $button = Get-ActionButton $Entry $Meta $Category -DisplayName $DisplayName
    $src = Get-ProfileAssetUrl "assets/buttons/$($button.file).svg"
    return "<a href=`"$(ConvertTo-SafeHref $button.url)`"><img src=`"$src`" height=`"$Height`" alt=`"$(ConvertTo-ButtonAltText $button.alt)`"></a>"
}

function Get-ObtainiumLink {
    # A second button for an Android app whose latest release ships an APK: Obtainium adds
    # the repository and installs each new release from GitHub.
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [int]$Height = 24,
        [string]$DisplayName
    )

    if (@(Get-ReleaseAssetKindsFromMeta -Meta $Meta) -notcontains "apk") { return $null }
    $title = if (Test-VisibleText $DisplayName) { $DisplayName } else { [string]$Entry.title }
    if (-not (Test-VisibleText $title)) { $title = [string]$Entry.repo }
    $href = "https://apps.obtainium.imranr.dev/redirect?r=obtainium://add/$(Get-RepoUrl $Entry)"
    $src = Get-ProfileAssetUrl "assets/buttons/obtainium.svg"
    return "<a href=`"$(ConvertTo-SafeHref $href)`"><img src=`"$src`" height=`"$Height`" alt=`"$(ConvertTo-ButtonAltText "Add $title to Obtainium for automatic updates")`"></a>"
}

function Test-MorpheBundleRelease {
    # True when the latest release ships a Morphe patch bundle (.mpp).
    param([object]$Meta)

    return @(Get-ReleaseAssetKindsFromMeta -Meta $Meta) -contains "mpp"
}

function Get-MorpheSourceUrl {
    # The add-source link Morphe Manager documents (docs/patch-sources.md): the app adds
    # the repository as a patch source and installs each new bundle from GitHub. The
    # owner/repo value is one query parameter, so its slash is percent-encoded.
    param([hashtable]$Entry)

    $ownerRepo = (Get-RepoUrl $Entry) -replace '^https://github\.com/', ''
    return "https://morphe.software/add-source?github=$([Uri]::EscapeDataString($ownerRepo))"
}

function Get-MorpheDownloadLink {
    # The second button beside "Add to Morphe": the bundle itself, for anyone who adds
    # sources by hand or keeps a copy.
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [int]$Height = 24,
        [string]$DisplayName
    )

    $button = Get-ActionButton $Entry $Meta ([string]$Entry.category) -DisplayName $DisplayName
    if ($button.kind -ne "release" -or $button.file -ne "morphe") { return $null }
    $title = if (Test-VisibleText $DisplayName) { $DisplayName } else { [string]$Entry.title }
    if (-not (Test-VisibleText $title)) { $title = [string]$Entry.repo }
    $src = Get-ProfileAssetUrl "assets/buttons/download.svg"
    return "<a href=`"$(ConvertTo-SafeHref (Get-ReleaseUrl $Entry))`"><img src=`"$src`" height=`"$Height`" alt=`"$(ConvertTo-ButtonAltText "Download $title")`"></a>"
}

function Get-ActionLinkGroup {
    # A row's buttons: the primary action, then the bundle download beside "Add to Morphe".
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [string]$Category,
        [int]$Height = 24,
        [string]$DisplayName
    )

    $links = @((Get-ActionLink $Entry $Meta $Category -Height $Height -DisplayName $DisplayName))
    $download = Get-MorpheDownloadLink -Entry $Entry -Meta $Meta -Height $Height -DisplayName $DisplayName
    if ($download) { $links += $download }
    return ($links -join " ")
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

function Get-ReadmeEntries {
    param([hashtable]$Catalog)

    return @($Catalog.entries | Where-Object {
        $_.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$_.suppressionReason)
    })
}

function Get-ShelfEntries {
    # A shelf's entries, most-starred first, then by name.
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup,
        [string[]]$Categories
    )

    $rows = foreach ($entry in @($Entries | Where-Object { $Categories -ccontains [string]$_.category })) {
        $stars = Get-MemberValue -Object (Get-RepoMeta $entry $RepoLookup) -Name 'stargazerCount'
        [pscustomobject]@{ entry = $entry; stars = $(if ($null -ne $stars) { [int]$stars } else { 0 }) }
    }
    return @($rows | Sort-Object @{ Expression = 'stars'; Descending = $true }, @{ Expression = { ConvertTo-OrdinalSortKey $_.entry.repo } } | ForEach-Object { $_.entry })
}

function Get-RenderedShelves {
    # The showcase's shelves that have at least one README entry, each with its entries.
    param(
        [object]$Showcase,
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $shelves = foreach ($shelf in (Get-ShowcaseList $Showcase 'shelves')) {
        # The id lands raw in an anchor and the nav's href, so one that could leave its
        # attribute drops the shelf. The schema check refuses such a showcase before a write.
        $id = [string](Get-MemberValue -Object $shelf -Name 'id')
        if ($id -cnotmatch '^[a-z0-9]+(?:-+[a-z0-9]+)*\z') { continue }
        $categories = @(Get-JsonArrayItems (Get-MemberValue -Object $shelf -Name 'categories') | ForEach-Object { [string]$_ })
        $items = @(Get-ShelfEntries -Entries $Entries -RepoLookup $RepoLookup -Categories $categories)
        if ($items.Count -eq 0) { continue }
        [ordered]@{
            id = $id
            title =[string](Get-MemberValue -Object $shelf -Name 'title')
            icon = [string](Get-MemberValue -Object $shelf -Name 'icon')
            blurb = [string](Get-MemberValue -Object $shelf -Name 'blurb')
            categories = $categories
            entries = $items
        }
    }
    return @($shelves)
}

function Get-EntryByRepo {
    param([hashtable[]]$Entries, [string]$Repo)

    return @($Entries | Where-Object { [string]::Equals([string]$_.repo, $Repo, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
}

function New-ProfileChrome {
    <#
    .SYNOPSIS
    Renders the README header: the hero, the proof line and the pitch.
    .DESCRIPTION
    With a showcase hero the header opens on its banner (a <picture> with dark and light
    sources). Without one it opens on the catalog's tagline, as a
    plain paragraph. The pitch is the catalog's about text; the proof line comes from
    New-ProofLine. Everything personal comes from the catalog and showcase, so a run for
    another account publishes only its own.
    #>
    param(
        # The catalog's profileHeader block; $null renders the neutral header.
        [object]$Header,
        [object]$Showcase,
        [int]$ProjectCount = 0
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $hero = Get-MemberValue -Object $Showcase -Name 'hero'
    $dark = [string](Get-MemberValue -Object $hero -Name 'darkImage')
    $light = [string](Get-MemberValue -Object $hero -Name 'lightImage')
    $alt = [string](Get-MemberValue -Object $hero -Name 'alt')
    if ($null -ne $hero -and (Test-ShowcaseImageSource $dark) -and (Test-ShowcaseImageSource $light) -and (Test-VisibleText $alt)) {
        # A bare <picture> on its own lines, the one form GitHub keeps whole. Inside a link it
        # wraps the <img> in a second link of its own; the browser can't nest them, so the
        # outer link ends up empty and the light source is lost.
        $lines.Add('<picture>')
        $lines.Add('  <source media="(prefers-color-scheme: dark)" srcset="' + (Get-ProfileAssetUrl $dark) + '">')
        $lines.Add('  <source media="(prefers-color-scheme: light)" srcset="' + (Get-ProfileAssetUrl $light) + '">')
        $lines.Add('  <img src="' + (Get-ProfileAssetUrl $dark) + '" width="100%" alt="' + (ConvertTo-HtmlText $alt -Attribute) + '">')
        $lines.Add('</picture>')
        $lines.Add('')
    } else {
        # Text a reader can't see (NBSP, zero-width or bidi characters alone) counts as missing,
        # so it can't draw an empty heading or an arrow-only link.
        $tagline = [string](Get-MemberValue -Object $Header -Name 'tagline')
        if (-not (Test-VisibleText $tagline)) {
            $tagline = "Public projects by $Owner"
        }
        $lines.Add('<p align="center"><b>' + (ConvertTo-HtmlText $tagline) + '</b></p>')
        $lines.Add('')
    }

    $proofLine = New-ProofLine -Showcase $Showcase -ProjectCount $ProjectCount
    if ($proofLine) {
        $lines.Add($proofLine)
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
            '<a href="' + $url + '">' + (ConvertTo-HtmlText $text) + ' &#8594;</a>'
        }
    })
    $about = [string](Get-MemberValue -Object $Header -Name 'about')
    $pitch = @()
    if (Test-VisibleText $about) { $pitch += (ConvertTo-HtmlText $about) }
    if ($links.Count -gt 0) { $pitch += ($links -join ' &middot; ') }
    if ($pitch.Count -gt 0) {
        $lines.Add('<p align="center">' + ($pitch -join ' ') + '</p>')
        $lines.Add('')
    }
    return ($lines -join [Environment]::NewLine)
}

function New-ProofLine {
    <#
    .SYNOPSIS
    The header's proof line: how many free projects and how many downloads.
    .DESCRIPTION
    Both numbers are hand-kept floors in the showcase's proof block ("200+"). Without a
    projects floor the line counts the README entries; without a downloads floor it leaves
    downloads out. Returns an empty string when there's nothing to say.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [object]$Showcase,
        [int]$ProjectCount = 0
    )

    $proof = Get-MemberValue -Object $Showcase -Name 'proof'
    $parts = New-Object System.Collections.Generic.List[string]
    $projects = [string](Get-MemberValue -Object $proof -Name 'projects')
    if (Test-VisibleText $projects) {
        $parts.Add('<b>' + (ConvertTo-HtmlText $projects) + '</b> free projects')
    } elseif ($ProjectCount -gt 0) {
        $parts.Add("<b>$ProjectCount</b> free projects")
    }
    $downloads = [string](Get-MemberValue -Object $proof -Name 'downloads')
    if (Test-VisibleText $downloads) { $parts.Add('<b>' + (ConvertTo-HtmlText $downloads) + '</b> downloads') }
    if ($parts.Count -eq 0) { return "" }
    return '<p align="center">' + ($parts -join ' &middot; ') + '</p>'
}

function New-FlagshipCard {
    param(
        [hashtable]$Entry,
        [object]$Meta,
        [object]$Card
    )

    $repoUrl = Get-RepoUrl $Entry
    $name = [string](Get-MemberValue -Object $Card -Name 'name')
    if (-not (Test-VisibleText $name)) { $name = [string]$Entry.title }
    $facts = New-Object System.Collections.Generic.List[string]
    $facts.Add('<b><a href="' + $repoUrl + '">' + (ConvertTo-HtmlText $name) + '</a></b>')
    $platform = [string](Get-MemberValue -Object $Card -Name 'platform')
    if (Test-VisibleText $platform) { $facts.Add((ConvertTo-HtmlText $platform)) }
    $stars = (Get-StarText $Meta).Trim()
    if ($stars) { $facts.Add($stars) }
    $downloads = [string](Get-MemberValue -Object $Card -Name 'downloads')
    if (Test-VisibleText $downloads) { $facts.Add((ConvertTo-HtmlText $downloads) + ' downloads') }

    $buttons = @((Get-ActionLink $Entry $Meta ([string]$Entry.category) -Height 28 -DisplayName $name))
    $obtainium = Get-ObtainiumLink -Entry $Entry -Meta $Meta -Height 28 -DisplayName $name
    if ($obtainium) { $buttons += $obtainium }
    $download = Get-MorpheDownloadLink -Entry $Entry -Meta $Meta -Height 28 -DisplayName $name
    if ($download) { $buttons += $download }

    $image = Get-ProfileAssetUrl ([string](Get-MemberValue -Object $Card -Name 'image'))
    $alt = ConvertTo-HtmlText ([string](Get-MemberValue -Object $Card -Name 'imageAlt')) -Attribute
    return @(
        '<td width="50%" valign="top">'
        '<a href="' + $repoUrl + '"><img src="' + $image + '" width="100%" alt="' + $alt + '"></a>'
        '<p>' + ($facts -join ' &middot; ') + '<br>' + (ConvertTo-HtmlText ([string](Get-MemberValue -Object $Card -Name 'pitch'))) + '</p>'
        '<p>' + ($buttons -join ' ') + '</p>'
        '</td>'
    ) -join [Environment]::NewLine
}

function New-FlagshipSection {
    param(
        [object]$Showcase,
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $cells = New-Object System.Collections.Generic.List[string]
    foreach ($card in (Get-ShowcaseList $Showcase 'flagships')) {
        $entry = Get-EntryByRepo -Entries $Entries -Repo ([string](Get-MemberValue -Object $card -Name 'repo'))
        if (-not $entry -or -not (Test-ShowcaseImageSource ([string](Get-MemberValue -Object $card -Name 'image')))) { continue }
        $cells.Add((New-FlagshipCard -Entry $entry -Meta (Get-RepoMeta $entry $RepoLookup) -Card $card))
    }
    if ($cells.Count -eq 0) { return "" }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## $ToolCatalogHeading")
    $lines.Add("")
    $lines.Add("The ones people download most, and a few I'm proudest of.")
    $lines.Add("")
    $lines.Add("<table>")
    for ($i = 0; $i -lt $cells.Count; $i += 2) {
        $lines.Add("<tr>")
        $lines.Add($cells[$i])
        if ($i + 1 -lt $cells.Count) { $lines.Add($cells[$i + 1]) } else { $lines.Add('<td width="50%"></td>') }
        $lines.Add("</tr>")
    }
    $lines.Add("</table>")
    return ($lines -join [Environment]::NewLine)
}

function New-ProblemSection {
    param(
        [object]$Showcase,
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($row in (Get-ShowcaseList $Showcase 'problems')) {
        $want = [string](Get-MemberValue -Object $row -Name 'want')
        $entry = Get-EntryByRepo -Entries $Entries -Repo ([string](Get-MemberValue -Object $row -Name 'repo'))
        if (-not $entry -or -not (Test-VisibleText $want)) { continue }
        $meta = Get-RepoMeta $entry $RepoLookup
        # The button shares the project's cell: in a column of its own, a phone-width table
        # squeezes an image-only column down to nothing.
        $rows.Add("| $(ConvertTo-MarkdownText $want) | $(Get-ProjectLink $entry $meta)<br>$(Get-ActionLinkGroup $entry $meta ([string]$entry.category)) |")
    }
    if ($rows.Count -eq 0) { return "" }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## Pick your problem")
    $lines.Add("")
    $lines.Add("| If you want to... | Try this |")
    $lines.Add("|:------------------|:---------|")
    foreach ($row in $rows) { $lines.Add($row) }
    return ($lines -join [Environment]::NewLine)
}

function Get-ChecksumReleaseCount {
    # README entries whose latest release lists a checksum file beside its assets.
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    return @($Entries | Where-Object {
        $names = @(Get-ReleaseAssetNamesFromMeta -Meta (Get-RepoMeta $_ $RepoLookup))
        @($names | Where-Object { $_ -match '(?i)(sha256|sha512|checksum|sums)' }).Count -gt 0
    }).Count
}

function New-TrustSection {
    param(
        [object]$Showcase,
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $notes = @(Get-ShowcaseList $Showcase 'trust' | Where-Object {
        (Test-VisibleText ([string](Get-MemberValue -Object $_ -Name 'title'))) -and (Test-VisibleText ([string](Get-MemberValue -Object $_ -Name 'text')))
    })
    if ($notes.Count -eq 0) { return "" }
    $checksumCount = [string](Get-ChecksumReleaseCount -Entries $Entries -RepoLookup $RepoLookup)

    $cells = @(foreach ($note in $notes) {
        $icon = [string](Get-MemberValue -Object $note -Name 'icon')
        $prefix = if ($icon -cmatch '^(?:&#[0-9]{2,7};)+\z') { "$icon " } else { "" }
        $text = (ConvertTo-HtmlText ([string](Get-MemberValue -Object $note -Name 'text'))).Replace('{checksumCount}', $checksumCount)
        '<td width="50%" valign="top">' + $prefix + '<b>' + (ConvertTo-HtmlText ([string](Get-MemberValue -Object $note -Name 'title'))) + '</b><br>' + $text + '</td>'
    })
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## How I ship")
    $lines.Add("")
    $lines.Add("<table>")
    for ($i = 0; $i -lt $cells.Count; $i += 2) {
        $lines.Add("<tr>")
        $lines.Add($cells[$i])
        if ($i + 1 -lt $cells.Count) { $lines.Add($cells[$i + 1]) } else { $lines.Add('<td width="50%"></td>') }
        $lines.Add("</tr>")
    }
    $lines.Add("</table>")
    return ($lines -join [Environment]::NewLine)
}

function New-FreshReleaseSection {
    param(
        [object]$Showcase,
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $limit = Get-MemberValue -Object $Showcase -Name 'freshReleaseCount'
    if ($null -eq $limit -or [int]$limit -le 0) { return "" }
    # Newest release first; the timestamp is compared as UTC ticks so the order can't
    # follow the machine's culture or time zone, and ties fall back to the repo name.
    $dated = foreach ($entry in $Entries) {
        $meta = Get-RepoMeta $entry $RepoLookup
        $release = Get-MemberValue -Object $meta -Name 'latestRelease'
        $published = Get-MemberValue -Object $release -Name 'publishedAt'
        $tag = [string](Get-MemberValue -Object $release -Name 'tagName')
        if ($null -eq $published -or -not (Test-VisibleText $tag)) { continue }
        if ((Get-ActionButton $entry $meta ([string]$entry.category)).kind -ne 'release') { continue }
        $ticks = if ($published -is [datetime]) { $published.ToUniversalTime().Ticks } else {
            $parsed = [datetimeoffset]::MinValue
            if (-not [datetimeoffset]::TryParse([string]$published, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { continue }
            $parsed.UtcTicks
        }
        [pscustomobject]@{ entry = $entry; meta = $meta; tag = $tag; ticks = $ticks }
    }
    $recent = @($dated | Sort-Object @{ Expression = 'ticks'; Descending = $true }, @{ Expression = { ConvertTo-OrdinalSortKey $_.entry.repo } } | Select-Object -First ([int]$limit))
    if ($recent.Count -eq 0) { return "" }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## Latest releases")
    $lines.Add("")
    $lines.Add("| Project | Version | Get it |")
    $lines.Add("|:--------|:--------|:-------|")
    foreach ($row in $recent) {
        $lines.Add("| $(Get-ProjectLink $row.entry $row.meta) | [$(ConvertTo-MarkdownText $row.tag -LinkLabel)]($(Get-ReleaseUrl $row.entry)) | $(Get-ActionLinkGroup $row.entry $row.meta ([string]$row.entry.category)) |")
    }
    return ($lines -join [Environment]::NewLine)
}

function New-ShelfSection {
    param(
        [System.Collections.IDictionary]$Shelf,
        [hashtable]$RepoLookup
    )

    $items = @($Shelf.entries)
    if ($items.Count -eq 0) { return "" }
    $icon = if ($Shelf.icon -cmatch '^(?:&#[0-9]{2,7};)+\z') { "$($Shelf.icon) " } else { "" }
    $noun = if ($items.Count -eq 1) { "project" } else { "projects" }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<a id=`"$($Shelf.id)`"></a>")
    $lines.Add("<details>")
    $lines.Add("<summary><b>$icon$(ConvertTo-HtmlText $Shelf.title)</b> &middot; $($items.Count) $noun</summary>")
    $lines.Add("<br/>")
    $lines.Add("")
    if (Test-VisibleText $Shelf.blurb) {
        $lines.Add((ConvertTo-MarkdownText $Shelf.blurb))
        $lines.Add("")
    }
    $lines.Add("| Project | What it does |")
    $lines.Add("|:--------|:-------------|")
    foreach ($entry in $items) {
        $meta = Get-RepoMeta $entry $RepoLookup
        # The button sits under the description, the widest cell, for the reason given in
        # New-ProblemSection.
        $lines.Add("| $(Get-ProjectLink $entry $meta) | $(Get-DisplayDescription $entry $meta)<br>$(Get-ActionLinkGroup $entry $meta ([string]$entry.category)) |")
    }
    $lines.Add("")
    $lines.Add("</details>")
    return ($lines -join [Environment]::NewLine)
}

function New-ProfileAssetSvgs {
    <#
    .SYNOPSIS
    Returns the generated profile SVG assets, which is an empty set.
    .DESCRIPTION
    The README's images are static files committed under assets/showcase and
    assets/buttons (see scripts/render-showcase-assets.ps1), not generator output, so
    nothing is rendered, budgeted or drift-checked here. Test-ProfileState reports any
    file under -AssetsPath as out of sync.
    #>
    [CmdletBinding()]
    param()

    return [ordered]@{}
}

function New-ProfileFooter {
    # The contact link opens the portfolio's contact section, which carries email and
    # LinkedIn, so the README publishes no address. The support button comes from the
    # catalog's profileHeader block.
    param([object]$Header)

    $portfolioUrl = Get-ProfilePortfolioUrl
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('---')
    $lines.Add('')
    $lines.Add('<p align="center"><a href="' + $portfolioUrl + '"><img src="' + (Get-ProfileAssetUrl 'assets/buttons/search.svg') + '" height="32" alt="Search every project on the portfolio site"></a></p>')
    $lines.Add('')
    # Test-CatalogShape refuses any other URL before anything is written, but the renderer
    # doesn't lean on it: a URL that could leave its attribute, or isn't https, isn't rendered.
    $safeUrlPattern = '^(?i:https)://[!#-&(-;=?-\[\]-{}~]+\z'
    $support = Get-MemberValue -Object $Header -Name 'support'
    $supportUrl = [string](Get-MemberValue -Object $support -Name 'url')
    $supportImageUrl = [string](Get-MemberValue -Object $support -Name 'imageUrl')
    # The image is the link's only content, so without alt text a reader can see (or hear)
    # the button has no name; like a link with no text, it isn't drawn.
    $supportAlt = [string](Get-MemberValue -Object $support -Name 'imageAlt')
    if ($supportUrl -cmatch $safeUrlPattern -and $supportImageUrl -cmatch $safeUrlPattern -and (Test-VisibleText $supportAlt)) {
        $lines.Add('<p align="center"><sub>Everything here is free. If one of these saved you an afternoon, a coffee keeps the next one coming.</sub></p>')
        $lines.Add('')
        $lines.Add('<p align="center"><a href="' + $supportUrl + '"><img height="36" src="' + $supportImageUrl + '" alt="' + (ConvertTo-HtmlText $supportAlt -Attribute) + '"></a></p>')
        $lines.Add('')
    }
    $lines.Add('<p align="center"><a href="' + $portfolioUrl + '"><b>See everything</b></a> &middot; <a href="https://github.com/' + $Owner + '?tab=repositories">All repos</a> &middot; <a href="' + $portfolioUrl + '#connect">Get in touch</a></p>')
    return ($lines -join [Environment]::NewLine)
}

function Update-Header {
    param(
        [object]$Header,
        [object]$Showcase,
        [int]$ProjectCount = 0
    )

    return (New-ProfileChrome @PSBoundParameters).TrimEnd()
}

function New-Readme {
    <#
    .SYNOPSIS
    Renders the generated GitHub profile README from catalog, showcase and repo metadata.
    .DESCRIPTION
    The whole file is generated: header, flagship cards, the problem index, the trust
    notes, the latest releases, one collapsed shelf per group of categories, and the
    footer. No section offers a command to paste; every project gets a button that opens
    its release, its live app, its userscript or its source.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER Repos
    Repository metadata used for stars, release actions, topics, and counts.
    .PARAMETER Showcase
    The showcase from Get-Showcase; read from data/showcase.json when omitted.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [object]$Showcase
    )

    if (-not $PSBoundParameters.ContainsKey('Showcase')) { $Showcase = Get-Showcase }
    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @(Get-ReadmeEntries -Catalog $Catalog)
    $shelves = @(Get-RenderedShelves -Showcase $Showcase -Entries $entries -RepoLookup $repoLookup)
    $header = Update-Header -Header (Get-MemberValue -Object $Catalog -Name 'profileHeader') -Showcase $Showcase -ProjectCount $entries.Count

    $blocks = New-Object System.Collections.Generic.List[string]
    $blocks.Add($header)
    $blocks.Add("")
    $blocks.Add($GeneratedCatalogNotice)
    $blocks.Add("")
    foreach ($section in @(
            (New-FlagshipSection -Showcase $Showcase -Entries $entries -RepoLookup $repoLookup),
            (New-ProblemSection -Showcase $Showcase -Entries $entries -RepoLookup $repoLookup),
            (New-TrustSection -Showcase $Showcase -Entries $entries -RepoLookup $repoLookup),
            (New-FreshReleaseSection -Showcase $Showcase -Entries $entries -RepoLookup $repoLookup))) {
        if ([string]::IsNullOrEmpty($section)) { continue }
        $blocks.Add($section)
        $blocks.Add("")
    }
    if ($shelves.Count -gt 0) {
        $blocks.Add("## Browse everything")
        $blocks.Add("")
        $blocks.Add("Every public project, grouped by where it runs. Tap a shelf to open it, or [search them all]($(Get-ProfilePortfolioUrl)) with filters.")
        $blocks.Add("")
        foreach ($shelf in $shelves) {
            $blocks.Add((New-ShelfSection -Shelf $shelf -RepoLookup $repoLookup))
            $blocks.Add("")
        }
    }
    $blocks.Add((New-ProfileFooter -Header (Get-MemberValue -Object $Catalog -Name 'profileHeader')))
    $blocks.Add("")
    return ($blocks -join [Environment]::NewLine)
}
