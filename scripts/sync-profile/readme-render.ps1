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

function Get-ProjectLink {
    param(
        [hashtable]$Entry,
        [object]$Meta
    )

    return "[**$($Entry.title)**]($(Get-RepoUrl $Entry))$(Get-StarText $Meta)"
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
                    @{ Expression = { ConvertTo-OrdinalSortKey $_.repo } } |
        Select-Object -First 3)

    if ($picks.Count -eq 0) {
        return $null
    }

    $links = foreach ($entry in $picks) {
        "[**$($entry.title)**]($(Get-RepoUrl $entry))"
    }

    return "Suggested starting points: $($links -join ', ')."
}

function Get-ProfilePortfolioUrl {
    <#
    .SYNOPSIS
    Returns the canonical public portfolio origin used by generated profile links.
    .DESCRIPTION
    Defaults to the -PortfolioUrl parameter, which is also the cross-surface probe
    target, so published links and drift probes can never disagree. Falls back to
    the owner's GitHub Pages origin when no portfolio URL is configured; pass
    -PortfolioUrl '' to force the owner-derived fallback for another account.
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
        if (-not $url.EndsWith("/")) { $url += "/" }
        return $url
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

    $pickLinks = @($picks | ForEach-Object { "[**$($_.title)**]($(Get-RepoUrl $_))" })
    if ($pickLinks.Count -eq 0) {
        $pickLinks = @("No public rows")
    }

    $actionLabel = Get-ToolCatalogActionLabel -Slug $Slug
    $anchor = Get-CategoryAnchor $Slug
    $description = Get-ToolCatalogDescription -Slug $Slug
    $icon = Get-CategoryIcon -Slug $Slug
    $heading = if ([string]::IsNullOrWhiteSpace($icon)) {
        "**$($definition.DisplayName)**"
    } else {
        "$icon **$($definition.DisplayName)**"
    }

    return "$heading<br/>$description<br/><sub>$($pickLinks -join '<br/>')</sub><br/>[<kbd>$actionLabel &#8594;</kbd>](#$anchor)"
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
    $lines.Add("### What's here")
    $lines.Add("")
    # One sentence for a visitor who arrives from a search result and has no idea what this
    # page is. The count comes from the catalog so it cannot go stale.
    $lines.Add("This is the index of the $(@($Entries).Count) free, open-source tools and apps I've published, sorted by where they run, for anyone who wants something that works on the setup they already have.")
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
<summary><b>&#128190; First-time setup</b> -- <i>Inspect first, then install only the tooling your machine is missing.</i></summary>
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
<summary><b>&#9989; Local validation</b> -- <i>For contributors: check the profile before you push.</i></summary>
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
    # Minimal header with a Ko-fi support image at the bottom. Satisfies the minimal
    # profile-header contract in Test-ReadmeExperience (README must start with the tagline
    # paragraph, carry the support-lead intro and portfolio links, and expose plain
    # category nav anchors with no profile-asset header image).
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($ProfileTaglineHtml)
    $lines.Add('')
    $lines.Add('## Hey, I''m Matt')
    $lines.Add('')
    $lines.Add('I do technical support for a medical imaging company during the day, and I build things at night. Some of these are tools I wrote to fix problems at work. Others are side projects, personal apps, or just things I wanted to exist. All of it is stuff I actually use or actively maintain.')
    $lines.Add('')
    $lines.Add('<p align="center"><a href="https://portfolio.getparkerai.com/healthcare-it/"><b>More about what I do &#8594;</b></a></p>')
    $lines.Add('')
    $navSlugs = @("powershell", "python", "web", "extensions", "android", "security", "desktop", "media", "guides", "misc")
    $categoryLinks = @($navSlugs | ForEach-Object {
        $slug = [string]$_
        $displayName = Get-ProfileNavLabel -Slug $slug
        "<a href=`"#$((Get-CategoryAnchor $slug))`">$displayName</a>"
    })
    $lines.Add('<p align="center">' + ($categoryLinks -join ' &middot; ') + '</p>')
    $lines.Add('')
    $lines.Add('<p align="center">')
    $lines.Add('  <a href="https://ko-fi.com/X8K126YVER">')
    $lines.Add('    <img height="36" src="https://storage.ko-fi.com/cdn/kofi2.png?v=3" alt="Buy me a coffee on Ko-fi" />')
    $lines.Add('  </a>')
    $lines.Add('</p>')
    $lines.Add('')
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
    return (New-ProfileChrome).TrimEnd()
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
    $footer = New-ProfileFooter
    $header = Update-Header
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

    foreach ($definition in $CategoryDefinitions) {
        $section = New-CategorySection -Entries $entries -RepoLookup $repoLookup -Definition $definition
        if ([string]::IsNullOrEmpty($section)) {
            continue
        }
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
