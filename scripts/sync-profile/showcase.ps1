# Profile showcase: the marketing layer the README is built around (hero, flagship
# cards, the problem index, the trust notes and the shelves that group categories).
# It lives in data/showcase.json beside the catalog. Rendering is lenient, so a row
# whose repository isn't a README entry is left out; Test-ShowcaseShape is strict and
# -Write and -Check both refuse a showcase that fails it. Dot-sourced by
# scripts/sync-profile.ps1.

function Get-DefaultShowcase {
    <#
    .SYNOPSIS
    The neutral showcase used when the catalog has no showcase file beside it.
    .DESCRIPTION
    A run for another account, or a fixture catalog, gets no hero image, flagship cards,
    problem rows or trust notes, and one shelf per category, so it publishes nothing
    this profile's showcase says.
    #>
    $shelves = foreach ($definition in $CategoryDefinitions) {
        [ordered]@{
            id = Get-CategoryAnchor $definition.Slug
            title = Get-CategoryDisplayName $definition.Slug
            icon = Get-CategoryIcon -Slug $definition.Slug
            blurb = $null
            categories = @([string]$definition.Slug)
        }
    }
    return [ordered]@{
        schema = $ShowcaseSchemaUrl
        flagships = @()
        problems = @()
        trust = @()
        shelves = @($shelves)
        freshReleaseCount = 0
    }
}

function Get-ShowcaseFullPath {
    # scripts/sync-profile.ps1 resolves -ShowcasePath (or the file beside the catalog) to
    # a full path when it starts; anything else is read from the repository root.
    $path = [string]$script:ShowcasePath
    if ([string]::IsNullOrWhiteSpace($path)) { $path = 'data/showcase.json' }
    if ([System.IO.Path]::IsPathRooted($path)) { return $path }
    return Join-Path $RepoRoot $path
}

function Get-Showcase {
    <#
    .SYNOPSIS
    Reads data/showcase.json, or returns the neutral showcase when there is none.
    #>
    $fullPath = Get-ShowcaseFullPath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return Get-DefaultShowcase
    }
    $raw = [System.IO.File]::ReadAllText($fullPath, [System.Text.UTF8Encoding]::new($false, $true))
    return ($raw | ConvertFrom-Json -AsHashtable -Depth 20)
}

function Get-ShowcaseList {
    param([object]$Showcase, [string]$Name)

    return @(Get-JsonArrayItems (Get-MemberValue -Object $Showcase -Name $Name) | Where-Object { $null -ne $_ })
}

function Test-ShowcaseImageSource {
    # An image is a file committed beside the README (relative path, no parent steps) or
    # an https URL on a GitHub content host. Anything else could break out of its
    # attribute or pull from a host the page doesn't otherwise depend on.
    param([string]$Source)

    if ([string]::IsNullOrWhiteSpace($Source)) { return $false }
    if ($Source -cmatch '^https://(?:raw\.githubusercontent\.com|github\.com/user-attachments/assets)/[A-Za-z0-9._~/%-]+\z') {
        return $true
    }
    if ($Source -cmatch '^[A-Za-z0-9_-][A-Za-z0-9._/-]*\.(?:png|jpg|jpeg|webp|gif|svg)\z' -and -not $Source.Contains('..')) {
        return (Test-Path -LiteralPath (Join-Path $RepoRoot $Source) -PathType Leaf)
    }
    return $false
}

function Test-ShowcaseShape {
    <#
    .SYNOPSIS
    Checks data/showcase.json against the catalog it decorates.
    .DESCRIPTION
    The showcase meets schemas/profile-showcase.v1.json, every flagship and problem row
    names a README entry, every image is a committed file or a GitHub-hosted URL with real
    alt text, the shelves cover each README category exactly once, and no text a visitor
    reads is blank or carries a shell command.
    #>
    param(
        [hashtable]$Catalog,
        [object]$Showcase
    )

    $issues = New-Object System.Collections.Generic.List[object]
    $add = { param([string]$Field, [string]$Reason) $issues.Add([ordered]@{ field = $Field; reason = $Reason }) | Out-Null }
    # The schema holds each value to its type and length (a misspelled key, a 300-character
    # pitch); the checks after it hold the showcase to the catalog and the files it names.
    foreach ($schemaError in @((Test-JsonSchemaContract -Value $Showcase -SchemaPath $ShowcaseSchemaPath).errors)) {
        $location = [string]$schemaError.instanceLocation
        $reason = if ([string]$schemaError.keywordLocation -like '*/additionalProperties*') { 'is not a showcase field' } else { 'does not match the showcase schema: ' + [string]$schemaError.message }
        & $add $(if ($location) { $location } else { '/' }) $reason
    }
    $readmeRepos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $readmeCategories = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($entry in @($Catalog.entries)) {
        if ($entry.includeInReadme -ne $false -and [string]::IsNullOrWhiteSpace([string]$entry.suppressionReason)) {
            $readmeRepos.Add([string]$entry.repo) | Out-Null
            $readmeCategories.Add([string]$entry.category) | Out-Null
        }
    }
    # A pasted command is what this page exists to avoid; catch one in the copy too.
    $commandPattern = '(?i)(\birm\b|\biwr\b|invoke-(?:restmethod|webrequest|expression)|\|\s*iex\b|\bcurl\b[^|]*\|\s*(?:ba|z)?sh\b|\bwget\b[^|]*\|\s*(?:ba|z)?sh\b)'
    $checkText = {
        param([string]$Field, [object]$Value, [switch]$Optional)
        $text = [string]$Value
        if (-not (Test-VisibleText $text)) {
            if (-not $Optional) { & $add $Field 'is empty' }
            return
        }
        if ($text -match $commandPattern) { & $add $Field 'contains a shell command; the profile never asks a visitor to paste one' }
    }

    $hero = Get-MemberValue -Object $Showcase -Name 'hero'
    if ($null -ne $hero) {
        foreach ($name in @('darkImage', 'lightImage')) {
            if (-not (Test-ShowcaseImageSource ([string](Get-MemberValue -Object $hero -Name $name)))) {
                & $add "hero.$name" 'is not a committed image or a GitHub-hosted https URL'
            }
        }
        & $checkText 'hero.alt' (Get-MemberValue -Object $hero -Name 'alt')
    }

    $index = 0
    foreach ($card in (Get-ShowcaseList $Showcase 'flagships')) {
        $field = "flagships[$index]"
        $repo = [string](Get-MemberValue -Object $card -Name 'repo')
        if (-not $readmeRepos.Contains($repo)) { & $add "$field.repo" "'$repo' is not a README entry in the catalog" }
        if (-not (Test-ShowcaseImageSource ([string](Get-MemberValue -Object $card -Name 'image')))) {
            & $add "$field.image" 'is not a committed image or a GitHub-hosted https URL'
        }
        & $checkText "$field.name" (Get-MemberValue -Object $card -Name 'name')
        & $checkText "$field.imageAlt" (Get-MemberValue -Object $card -Name 'imageAlt')
        & $checkText "$field.pitch" (Get-MemberValue -Object $card -Name 'pitch')
        & $checkText "$field.platform" (Get-MemberValue -Object $card -Name 'platform')
        & $checkText "$field.downloads" (Get-MemberValue -Object $card -Name 'downloads') -Optional
        $index++
    }

    $index = 0
    foreach ($row in (Get-ShowcaseList $Showcase 'problems')) {
        $repo = [string](Get-MemberValue -Object $row -Name 'repo')
        if (-not $readmeRepos.Contains($repo)) { & $add "problems[$index].repo" "'$repo' is not a README entry in the catalog" }
        & $checkText "problems[$index].want" (Get-MemberValue -Object $row -Name 'want')
        $index++
    }

    $index = 0
    foreach ($note in (Get-ShowcaseList $Showcase 'trust')) {
        & $checkText "trust[$index].title" (Get-MemberValue -Object $note -Name 'title')
        & $checkText "trust[$index].text" (Get-MemberValue -Object $note -Name 'text')
        $index++
    }

    $shelfIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $covered = @{}
    $knownSlugs = @($CategoryDefinitions | ForEach-Object { [string]$_.Slug })
    $index = 0
    foreach ($shelf in (Get-ShowcaseList $Showcase 'shelves')) {
        $field = "shelves[$index]"
        # The schema holds the id to lower-case words and hyphens, so it's safe in an anchor.
        $id = [string](Get-MemberValue -Object $shelf -Name 'id')
        if (-not $shelfIds.Add($id)) { & $add "$field.id" "'$id' is used by another shelf" }
        & $checkText "$field.title" (Get-MemberValue -Object $shelf -Name 'title')
        & $checkText "$field.blurb" (Get-MemberValue -Object $shelf -Name 'blurb') -Optional
        foreach ($slug in @(Get-JsonArrayItems (Get-MemberValue -Object $shelf -Name 'categories'))) {
            $slug = [string]$slug
            if ($knownSlugs -cnotcontains $slug) { & $add "$field.categories" "'$slug' is not a catalog category"; continue }
            if ($covered.ContainsKey($slug)) { & $add "$field.categories" "'$slug' is already on shelf '$($covered[$slug])'"; continue }
            $covered[$slug] = $id
        }
        $index++
    }
    # Only categories the README renders need a shelf. A row filed under 'suppressed' without
    # a reason is orphanedSuppressed's to report, and an unknown category the catalog check's.
    foreach ($slug in $readmeCategories) {
        if ($knownSlugs -ccontains $slug -and -not $covered.ContainsKey($slug)) { & $add 'shelves' "category '$slug' has README entries but no shelf" }
    }

    return [ordered]@{
        passed = $issues.Count -eq 0
        issueCount = $issues.Count
        issues = $issues.ToArray()
    }
}
