# The public projects.json feed and its consumers: project rows, search metadata,
# provenance, license metadata, the optional Backstage export, catalog/feed accounting,
# portfolio compatibility and cross-surface probes, and feed identity checks.
# Dot-sourced by scripts/sync-profile.ps1.

function New-ProjectsFeedSchemaPolicy {
    <#
    .SYNOPSIS
    Describes the public feed compatibility and migration contract.
    #>
    [CmdletBinding()]
    param()

    $previousVersion = [Math]::Max(1, [int]$ProjectsFeedSchemaVersion - 1)
    return [ordered]@{
        currentVersion = [int]$ProjectsFeedSchemaVersion
        supportedVersions = @($previousVersion, [int]$ProjectsFeedSchemaVersion)
        compatibility = "backward-compatible-for-field-selecting-consumers"
        changeKind = "required-field-addition"
        migrationRequired = $true
        migrationNotes = @(
            "Feed version 3 adds project identity, canonical repository, alias, locale, and script metadata fields.",
            "Consumers that select known fields can continue reading the feed without changing their rendering path.",
            "Strict schema validators must accept feed version 3 before requiring the new project fields."
        )
        deprecatedVersions = @()
        deprecationNotes = @("No supported feed version is currently deprecated.")
    }
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

function Get-BranchTipActionEvidence {
    [CmdletBinding()]
    param(
        [hashtable]$Entry,
        [object]$Meta
    )

    $hasBranchBackedAction = -not [string]::IsNullOrWhiteSpace([string]$Entry.entrypoint)
    if (-not $hasBranchBackedAction) {
        return [ordered]@{
            sha = $null
            fetchedAt = $null
            status = "not-applicable"
            warning = $null
        }
    }

    $branchTipSha = if ($Meta) { [string](Get-MemberValue -Object $Meta -Name "branchTipSha") } else { $null }
    $branchTipFetchedAt = if ($Meta) { [string](Get-MemberValue -Object $Meta -Name "branchTipFetchedAt") } else { $null }
    $branchTipStatus = if ($Meta) { [string](Get-MemberValue -Object $Meta -Name "branchTipStatus") } else { "unreachable" }
    $branchTipWarning = if ($Meta) { [string](Get-MemberValue -Object $Meta -Name "branchTipWarning") } else { "Repository metadata did not include branch-tip evidence." }

    return [ordered]@{
        sha = if ($branchTipSha -match '^[a-f0-9]{40}$') { $branchTipSha.ToLowerInvariant() } else { $null }
        fetchedAt = if ([string]::IsNullOrWhiteSpace($branchTipFetchedAt)) { $null } else { $branchTipFetchedAt }
        status = if ($branchTipStatus -in @("fresh", "stale", "unreachable", "missing")) { $branchTipStatus } else { "unreachable" }
        warning = if ([string]::IsNullOrWhiteSpace($branchTipWarning)) { $null } else { $branchTipWarning }
    }
}

function Get-BackstageEntityName {
    param([hashtable]$Entry)

    $entityName = [string](Get-StableProjectEntityId -Entry $Entry)
    $entityName = ([regex]::Replace($entityName.ToLowerInvariant(), '[^a-z0-9-]', '-')).Trim('-')
    if ($entityName.Length -gt 63) {
        $entityName = $entityName.Substring(0, 63).TrimEnd('-')
    }
    return $entityName
}

function Get-BackstageComponentType {
    param([string]$Category)

    switch ($Category) {
        'web' { return 'website' }
        'guides' { return 'documentation' }
        'python' { return 'library' }
        default { return 'service' }
    }
}

function ConvertTo-BackstageTag {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $tag = [regex]::Replace($Value.ToLowerInvariant(), '[^a-z0-9:+#-]', '-')
    $tag = [regex]::Replace($tag, '-{2,}', '-').Trim('-')
    if ($tag.Length -gt 63) {
        $tag = $tag.Substring(0, 63).TrimEnd('-')
    }
    return $tag
}

function New-BackstageCatalogExport {
    <#
    .SYNOPSIS
    Builds redaction-safe Backstage Component descriptors from public catalog rows.
    .DESCRIPTION
    The export uses Backstage's v1alpha1 Component envelope. Suppressed rows, rows
    excluded from the public portfolio, private metadata, and metadata-unavailable
    rows are counted but never emitted or named in the export.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER Repos
    Public repository metadata used to confirm export eligibility and enrich links.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $components = New-Object System.Collections.Generic.List[object]
    $suppressedCount = 0
    $privateSkippedCount = 0
    $missingMetadataCount = 0

    foreach ($entry in @($Catalog.entries | Sort-Object category, @{ Expression = { [int]$_.order } }, repo)) {
        $isSuppressed = -not [string]::IsNullOrWhiteSpace([string]$entry.suppressionReason)
        if ($isSuppressed -or $entry.includeInPortfolio -eq $false) {
            $suppressedCount++
            continue
        }

        $meta = Get-RepoMeta $entry $repoLookup
        if (-not $meta) {
            $missingMetadataCount++
            continue
        }
        if ((Get-MemberValue -Object $meta -Name 'isPrivate') -eq $true -or [string](Get-MemberValue -Object $meta -Name 'visibility') -ne 'PUBLIC') {
            $privateSkippedCount++
            continue
        }

        $repoUrl = Get-RepoUrl -Entry $entry
        $links = New-Object System.Collections.Generic.List[object]
        $links.Add([ordered]@{ title = 'Repository'; url = $repoUrl })
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.liveUrl) -and (Test-UrlScheme -Url ([string]$entry.liveUrl))) {
            $links.Add([ordered]@{ title = 'Live site'; url = [string]$entry.liveUrl })
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.userscriptUrl) -and (Test-UrlScheme -Url ([string]$entry.userscriptUrl))) {
            $links.Add([ordered]@{ title = 'Install'; url = [string]$entry.userscriptUrl })
        }
        if ($meta.latestRelease -and [string]$entry.downloadKind -ne 'repo') {
            $links.Add([ordered]@{ title = 'Release'; url = Get-ReleaseUrl -Entry $entry })
        }

        $language = if (-not [string]::IsNullOrWhiteSpace([string]$entry.language)) { [string]$entry.language } elseif ($meta.primaryLanguage) { [string]$meta.primaryLanguage.name } else { $null }
        $tags = New-Object System.Collections.Generic.List[string]
        foreach ($tagValue in @(
                (ConvertTo-BackstageTag -Value ('category-' + [string]$entry.category)),
                (ConvertTo-BackstageTag -Value $language),
                (ConvertTo-BackstageTag -Value ([string]$entry.downloadKind)))) {
            if (-not [string]::IsNullOrWhiteSpace($tagValue) -and -not $tags.Contains($tagValue)) {
                $tags.Add($tagValue)
            }
        }

        $components.Add([ordered]@{
            apiVersion = 'backstage.io/v1alpha1'
            kind = 'Component'
            metadata = [ordered]@{
                name = Get-BackstageEntityName -Entry $entry
                title = [string]$entry.title
                description = Get-Description -Entry $entry -Meta $meta
                tags = @($tags | Sort-Object)
                links = $links.ToArray()
            }
            spec = [ordered]@{
                type = Get-BackstageComponentType -Category ([string]$entry.category)
                lifecycle = if ($entry.currentlyBuilding -eq $true) { 'experimental' } else { 'production' }
                owner = "user:default/$($Owner.ToLowerInvariant())"
            }
        })
    }

    $componentJson = if ($components.Count -eq 0) { '[]' } else { $components.ToArray() | ConvertTo-Json -Depth 15 }

    [ordered]@{
        json = $componentJson
        summary = [ordered]@{
            schemaVersion = 'sysadmindoc-backstage-catalog.v1'
            componentCount = [int]$components.Count
            suppressedCount = [int]$suppressedCount
            privateSkippedCount = [int]$privateSkippedCount
            missingMetadataCount = [int]$missingMetadataCount
            redactionSafe = $true
            note = 'Only public, visitor-facing catalog rows with public repository metadata are emitted as Backstage Component descriptors.'
        }
    }
}

function New-BackstageCatalogExportJson {
    <#
    .SYNOPSIS
    Returns the optional redaction-safe Backstage Component export as JSON.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER Repos
    Public repository metadata used to confirm export eligibility.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos
    )

    return (New-BackstageCatalogExport -Catalog $Catalog -Repos $Repos).json
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

function New-ProjectsProvenance {
    param([object[]]$Repos)

    # The generator is the entry script plus every library file it dot-sources, so its
    # identity covers all of them: an edit to any one must change generatorSha256.
    $generatorFileHashes = foreach ($relativePath in @("scripts/sync-profile.ps1") + @($GeneratorLibraryFiles)) {
        "$relativePath $(Get-RepoFileSha256 -RelativePath $relativePath)"
    }

    return [ordered]@{
        version = 1
        feedSchemaVersion = $ProjectsFeedSchemaVersion
        sourceRepository = "$Owner/$Owner"
        sourceCommit = Get-GitHeadCommit
        catalogSha256 = Get-RepoFileSha256 -RelativePath "data/profile-catalog.json"
        generatorSha256 = Get-StringSha256 -Text ($generatorFileHashes -join "`n")
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
    .PARAMETER GeneratedAt
    Optional stable generation timestamp used when replaying a complete snapshot.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [object[]]$Repos,
        [string]$GeneratedAt
    )

    $repoLookup = ConvertTo-Lookup $Repos
    $entries = @($Catalog.entries | Sort-Object category, @{ Expression = { [int]$_.order } }, repo)
    $projects = New-Object System.Collections.Generic.List[object]
    $suppressed = New-Object System.Collections.Generic.List[object]
    $suppressedIndex = 0

    foreach ($entry in $entries) {
        $meta = Get-RepoMeta $entry $repoLookup
        $repoUrl = Get-RepoUrl $entry
        $entityId = Get-StableProjectEntityId -Entry $entry
        $canonicalRepo = Get-ProjectCanonicalRepo -Entry $entry
        $aliases = Get-ProjectAliases -Entry $entry
        $localeHints = Get-ProjectLocaleHints -Entry $entry
        $scriptHints = Get-ProjectScriptHints -Entry $entry
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

        $branch = Get-Branch $entry $meta
        $branchTipEvidence = Get-BranchTipActionEvidence -Entry $entry -Meta $meta

        $row = [ordered]@{
            id = $entityId
            repo = [string]$entry.repo
            canonicalRepo = $canonicalRepo
            aliases = @($aliases)
            title = [string]$entry.title
            category = [string]$entry.category
            includeInReadme = [bool]$entry.includeInReadme
            includeInPortfolio = [bool]$entry.includeInPortfolio
            suppressed = $isSuppressed
            suppressionReason = Get-NullableString $entry.suppressionReason
            description = Get-Description $entry $meta
            forkOf = Get-NullableString $entry.forkOf
            forkOfUrl = Get-UpstreamUrl -ForkOf ([string]$entry.forkOf)
            upstreamLicense = Get-NullableString $entry.upstreamLicense
            licenseKey = $licenseMetadata["licenseKey"]
            licenseName = $licenseMetadata["licenseName"]
            licenseSpdxId = $licenseMetadata["licenseSpdxId"]
            repoUrl = $repoUrl
            liveUrl = Get-NullableString $entry.liveUrl
            installUrl = Get-NullableString $entry.userscriptUrl
            downloadUrl = $downloadUrl
            downloadKind = Get-NullableString $entry.downloadKind
            primaryAction = [ordered]@{
                kind = [string]$primaryAction["kind"]
                label = [string]$primaryAction["label"]
                url = [string]$primaryAction["url"]
            }
            searchMetadata = New-ProjectSearchMetadata -Entry $entry -PrimaryAction $primaryAction -Language $language
            hasDownload = [bool]($primaryAction["kind"] -eq "release")
            hasLiveDemo = [bool]($primaryAction["kind"] -eq "live")
            hasDirectInstall = [bool]($primaryAction["kind"] -eq "install")
            branch = $branch
            branchTipSha = $branchTipEvidence.sha
            branchTipFetchedAt = $branchTipEvidence.fetchedAt
            branchTipStatus = $branchTipEvidence.status
            branchTipWarning = $branchTipEvidence.warning
            entrypoint = Get-NullableString $entry.entrypoint
            installKind = Get-NullableString $entry.installKind
            language = $language
            localeHints = @($localeHints)
            scriptHints = @($scriptHints)
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
            notes = Get-NullableString $entry.notes
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
        # Stamped when the feed is generated, not copied from the catalog. The catalog
        # stamp is only refreshed by the lossy seed path, so copying it froze the
        # published feed's generatedAt and made the staleness warning permanent.
        # ConvertTo-ProjectsSyncComparableJson treats this as a volatile field so
        # check-only runs still compare equal.
        generatedAt = if ([string]::IsNullOrWhiteSpace($GeneratedAt)) { (Get-Date).ToString("o") } else { $GeneratedAt }
        source = "$Owner/$Owner data/profile-catalog.json"
        provenance = New-ProjectsProvenance -Repos $Repos
        schemaPolicy = New-ProjectsFeedSchemaPolicy
        publicRepoCount = @($Repos | Where-Object { $null -ne $_ }).Count
        projectCount = $projects.Count
        suppressedCount = $suppressed.Count
        projects = $projects.ToArray()
        suppressed = $suppressed.ToArray()
    }

    return ($payload | ConvertTo-Json -Depth 20 -Compress)
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
            consumerContract = "portfolio.getparkerai.com profile-feed importer"
            feedSourceUrl = "https://raw.githubusercontent.com/$Owner/$Owner/main/projects.json"
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
        consumerContract = "portfolio.getparkerai.com profile-feed importer"
        feedSourceUrl = "https://raw.githubusercontent.com/$Owner/$Owner/main/projects.json"
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

function Get-PortfolioProbeUrl {
    param(
        [string]$BaseUrl,
        [string]$Path
    )

    try {
        $baseUri = [Uri]$BaseUrl
        $relativeUri = [Uri]::new($Path, [UriKind]::RelativeOrAbsolute)
        return [Uri]::new($baseUri, $relativeUri).AbsoluteUri
    } catch {
        return $null
    }
}

function Get-PortfolioHttpDocument {
    param(
        [string]$Url,
        [int]$TimeoutSec = 15
    )

    $result = Invoke-SafeOutboundHttpRequest `
        -Url $Url `
        -Method Get `
        -TimeoutSec $TimeoutSec `
        -MaxRedirects 5 `
        -ReadBody `
        -MaxBytes 5MB `
        -UserAgent 'SysAdminDoc-portfolio-probe' `
        -Accept 'application/json, text/html;q=0.9, */*;q=0.1'
    return [ordered]@{
        succeeded = [bool]$result.ok
        statusCode = $result.statusCode
        content = $result.text
        error = $result.error
        finalUrl = $result.finalUrl
    }
}

function Get-PortfolioProbeDocument {
    param(
        [string]$Kind,
        [string]$Url,
        [object]$Snapshot
    )

    if ($null -ne $Snapshot) {
        $snapshotDocument = Get-MemberValue -Object $Snapshot -Name $Kind
        if ($null -ne $snapshotDocument) {
            return $snapshotDocument
        }
    }

    return Get-PortfolioHttpDocument -Url $Url
}

function Get-PortfolioRouteProbe {
    param(
        [string]$Path,
        [string]$Url,
        [object]$Snapshot
    )

    $snapshotRoutes = if ($null -ne $Snapshot) { Get-MemberValue -Object $Snapshot -Name "routes" } else { $null }
    $snapshotRoute = $null
    if ($snapshotRoutes -is [System.Collections.IDictionary] -and $snapshotRoutes.Contains($Path)) {
        $snapshotRoute = $snapshotRoutes[$Path]
    }

    $probe = if ($null -ne $snapshotRoute) {
        $snapshotRoute
    } else {
        Test-HttpUrl -Url $Url -TimeoutSec 15 -Retries 1
    }
    $statusCode = Get-MemberValue -Object $probe -Name "statusCode"
    if ($null -eq $statusCode) {
        $statusCode = Get-MemberValue -Object $probe -Name "status"
    }
    $okValue = Get-MemberValue -Object $probe -Name "ok"
    if ($null -eq $okValue) {
        $okValue = $null -ne $statusCode -and [int]$statusCode -ge 200 -and [int]$statusCode -lt 400
    }
    $probeError = Get-MemberValue -Object $probe -Name "error"
    return [ordered]@{
        path = $Path
        url = $Url
        ok = [bool]$okValue
        statusCode = if ($null -eq $statusCode) { $null } else { [int]$statusCode }
        error = if ([string]::IsNullOrWhiteSpace([string]$probeError)) { $null } else { [string]$probeError }
    }
}

function Test-PortfolioCrossSurfaceDrift {
    <#
    .SYNOPSIS
    Optionally compares the deployed portfolio feed and route surface with local feed evidence.
    .DESCRIPTION
    The probe is opt-in and warning-only. It records deployed portfolio schema/timestamps,
    feed-derived catalog counts, and a small set of key route probes. External outages and
    drift never enter the local profile-sync failure conditions.
    .PARAMETER ProjectsJson
    Locally generated projects.json content used as the expected feed snapshot.
    .PARAMETER Enabled
    Enables outbound requests to the configured portfolio URL.
    .PARAMETER PortfolioUrl
    HTTPS origin of the deployed portfolio.
    .PARAMETER Snapshot
    Optional deterministic root/feed/route evidence used by tests instead of network calls.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectsJson,

        [switch]$Enabled,

        [string]$PortfolioUrl = "https://portfolio.getparkerai.com/",

        [object]$Snapshot
    )

    $localPayload = $null
    try {
        $localPayload = ConvertFrom-JsonPreservingArrays -Json $ProjectsJson
    } catch {
        $localPayload = $null
    }
    $localProjects = if ($localPayload) {
        @(Get-JsonArrayItems (Get-MemberValue -Object $localPayload -Name "projects"))
    } else {
        @()
    }
    $localFeedGeneratedAt = if ($localPayload) { [string](Get-MemberValue -Object $localPayload -Name "generatedAt") } else { $null }
    $localProvenance = if ($localPayload) { Get-MemberValue -Object $localPayload -Name "provenance" } else { $null }
    $localFeedSchemaVersion = if ($null -ne $localProvenance -and $null -ne (Get-MemberValue -Object $localProvenance -Name "feedSchemaVersion")) {
        [int](Get-MemberValue -Object $localProvenance -Name "feedSchemaVersion")
    } else {
        $null
    }
    $localRouteCounts = [ordered]@{
        catalog = [int]$localProjects.Count
        featured = [int]@($localProjects | Where-Object { [bool](Get-MemberValue -Object $_ -Name "featured") }).Count
        liveApps = [int]@($localProjects | Where-Object {
                [bool](Get-MemberValue -Object $_ -Name "hasLiveDemo") -or
                -not [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $_ -Name "liveUrl"))
            }).Count
    }

    $baseUri = $null
    try {
        $baseUri = [Uri]$PortfolioUrl
    } catch {
        $baseUri = $null
    }
    $validBaseUri = $null -ne $baseUri -and $baseUri.IsAbsoluteUri -and $baseUri.Scheme -eq "https"
    $normalizedPortfolioUrl = if ($validBaseUri) { $baseUri.AbsoluteUri.TrimEnd('/') + '/' } else { [string]$PortfolioUrl }
    $feedUrl = if ($validBaseUri) { Get-PortfolioProbeUrl -BaseUrl $normalizedPortfolioUrl -Path "projects.json" } else { $null }
    $routeCountsEmpty = [ordered]@{
        catalog = $null
        featured = $null
        liveApps = $null
    }
    $baseResult = [ordered]@{
        enabled = [bool]$Enabled
        status = if ($Enabled) { "unavailable" } else { "disabled" }
        portfolioUrl = if ($validBaseUri) { $normalizedPortfolioUrl } else { [string]$PortfolioUrl }
        feedUrl = $feedUrl
        localFeedGeneratedAt = if ([string]::IsNullOrWhiteSpace($localFeedGeneratedAt)) { $null } else { $localFeedGeneratedAt }
        deployedPortfolioGeneratedAt = $null
        deployedProfileFeedGeneratedAt = $null
        localFeedSchemaVersion = $localFeedSchemaVersion
        expectedPortfolioSchemaVersion = [int]$PortfolioFeedSchemaVersion
        deployedPortfolioSchemaVersion = $null
        localRouteCounts = $localRouteCounts
        deployedRouteCounts = $routeCountsEmpty
        rootStatusCode = $null
        feedStatusCode = $null
        feedFetchSucceeded = $false
        routeProbeCount = 0
        routeProbePassedCount = 0
        routeProbeFailedCount = 0
        routeProbes = @()
        warningCount = 0
        warnings = @()
        note = if ($Enabled) { "Opt-in warning-only probe; external portfolio availability or drift never fails local profile validation." } else { "Disabled by default; pass -ProbePortfolio to compare the deployed portfolio feed and key routes." }
    }

    if (-not $Enabled) {
        return $baseResult
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    if (-not $validBaseUri) {
        $warnings.Add("Portfolio probe requires an absolute HTTPS URL.")
        $baseResult.status = "unavailable"
        $baseResult.warningCount = $warnings.Count
        $baseResult.warnings = @($warnings.ToArray())
        return $baseResult
    }

    $rootUrl = Get-PortfolioProbeUrl -BaseUrl $normalizedPortfolioUrl -Path "/"
    $rootDocument = Get-PortfolioProbeDocument -Kind "root" -Url $rootUrl -Snapshot $Snapshot
    $feedDocument = Get-PortfolioProbeDocument -Kind "feed" -Url $feedUrl -Snapshot $Snapshot
    $rootStatusCode = Get-MemberValue -Object $rootDocument -Name "statusCode"
    $feedStatusCode = Get-MemberValue -Object $feedDocument -Name "statusCode"
    $baseResult.rootStatusCode = if ($null -eq $rootStatusCode) { $null } else { [int]$rootStatusCode }
    $baseResult.feedStatusCode = if ($null -eq $feedStatusCode) { $null } else { [int]$feedStatusCode }

    $rootSucceeded = [bool](Get-MemberValue -Object $rootDocument -Name "succeeded")
    if (-not $rootSucceeded -and $null -ne $rootStatusCode) {
        $rootSucceeded = [int]$rootStatusCode -ge 200 -and [int]$rootStatusCode -lt 400
    }
    if (-not $rootSucceeded) {
        $rootError = [string](Get-MemberValue -Object $rootDocument -Name "error")
        $warnings.Add("Portfolio root route is unavailable: $(if ([string]::IsNullOrWhiteSpace($rootError)) { 'no response' } else { $rootError }).")
    }

    $feedSucceeded = [bool](Get-MemberValue -Object $feedDocument -Name "succeeded")
    if (-not $feedSucceeded -and $null -ne $feedStatusCode) {
        $feedSucceeded = [int]$feedStatusCode -ge 200 -and [int]$feedStatusCode -lt 400
    }
    $baseResult.feedFetchSucceeded = [bool]$feedSucceeded
    if (-not $feedSucceeded) {
        $feedError = [string](Get-MemberValue -Object $feedDocument -Name "error")
        $warnings.Add("Portfolio projects.json feed is unavailable: $(if ([string]::IsNullOrWhiteSpace($feedError)) { 'no response' } else { $feedError }).")
    }

    $routePaths = @("/", "projects.json", "catalog/", "feed.json", "releases/", "resume/", "search/")
    $routeRows = New-Object System.Collections.Generic.List[object]
    foreach ($path in $routePaths) {
        $routeUrl = Get-PortfolioProbeUrl -BaseUrl $normalizedPortfolioUrl -Path $path
        $route = if ($path -eq "/") {
            [ordered]@{
                path = $path
                url = $routeUrl
                ok = [bool]$rootSucceeded
                statusCode = if ($null -eq $rootStatusCode) { $null } else { [int]$rootStatusCode }
                error = if ($rootSucceeded) { $null } else { [string](Get-MemberValue -Object $rootDocument -Name "error") }
            }
        } elseif ($path -eq "projects.json") {
            [ordered]@{
                path = $path
                url = $routeUrl
                ok = [bool]$feedSucceeded
                statusCode = if ($null -eq $feedStatusCode) { $null } else { [int]$feedStatusCode }
                error = if ($feedSucceeded) { $null } else { [string](Get-MemberValue -Object $feedDocument -Name "error") }
            }
        } else {
            Get-PortfolioRouteProbe -Path $path -Url $routeUrl -Snapshot $Snapshot
        }
        $routeRows.Add($route)
        if (-not $route.ok) {
            $routeError = if ([string]::IsNullOrWhiteSpace([string]$route.error)) { "no response" } else { [string]$route.error }
            $warnings.Add("Portfolio route '$path' is unavailable: $routeError.")
        }
    }
    $routeArray = @($routeRows.ToArray())
    $baseResult.routeProbeCount = [int]$routeArray.Count
    $baseResult.routeProbePassedCount = [int]@($routeArray | Where-Object { $_.ok }).Count
    $baseResult.routeProbeFailedCount = [int]@($routeArray | Where-Object { -not $_.ok }).Count
    $baseResult.routeProbes = $routeArray

    $deployedPayload = $null
    if ($feedSucceeded) {
        try {
            $deployedPayload = ConvertFrom-JsonPreservingArrays -Json ([string](Get-MemberValue -Object $feedDocument -Name "content"))
        } catch {
            $warnings.Add("Portfolio projects.json feed could not be parsed: $($_.Exception.Message).")
        }
    }

    if ($deployedPayload) {
        $deployedSource = Get-MemberValue -Object $deployedPayload -Name "source"
        $deployedCounts = Get-MemberValue -Object $deployedPayload -Name "counts"
        $deployedPortfolioGeneratedAt = [string](Get-MemberValue -Object $deployedPayload -Name "generatedAt")
        $deployedProfileFeedGeneratedAt = [string](Get-MemberValue -Object $deployedSource -Name "profileFeedGeneratedAt")
        $deployedSchemaVersion = Get-MemberValue -Object $deployedPayload -Name "schemaVersion"
        $deployedRouteCounts = [ordered]@{
            catalog = if ($null -eq (Get-MemberValue -Object $deployedCounts -Name "catalog")) { $null } else { [int](Get-MemberValue -Object $deployedCounts -Name "catalog") }
            featured = if ($null -eq (Get-MemberValue -Object $deployedCounts -Name "featured")) { $null } else { [int](Get-MemberValue -Object $deployedCounts -Name "featured") }
            liveApps = if ($null -eq (Get-MemberValue -Object $deployedCounts -Name "liveApps")) { $null } else { [int](Get-MemberValue -Object $deployedCounts -Name "liveApps") }
        }
        $baseResult.deployedPortfolioGeneratedAt = if ([string]::IsNullOrWhiteSpace($deployedPortfolioGeneratedAt)) { $null } else { $deployedPortfolioGeneratedAt }
        $baseResult.deployedProfileFeedGeneratedAt = if ([string]::IsNullOrWhiteSpace($deployedProfileFeedGeneratedAt)) { $null } else { $deployedProfileFeedGeneratedAt }
        $baseResult.deployedPortfolioSchemaVersion = if ($null -eq $deployedSchemaVersion) { $null } else { [int]$deployedSchemaVersion }
        $baseResult.deployedRouteCounts = $deployedRouteCounts

        if ($null -eq $deployedSchemaVersion) {
            $warnings.Add("Portfolio feed schemaVersion is missing.")
        } elseif ([int]$deployedSchemaVersion -ne [int]$PortfolioFeedSchemaVersion) {
            $warnings.Add("Portfolio feed schemaVersion $deployedSchemaVersion differs from expected version $PortfolioFeedSchemaVersion.")
        }

        if ([string]::IsNullOrWhiteSpace($deployedProfileFeedGeneratedAt)) {
            $warnings.Add("Portfolio feed source.profileFeedGeneratedAt is missing.")
        } else {
            $localTimestamp = ConvertTo-DateTimeOffsetOrNull -Value $localFeedGeneratedAt
            $deployedTimestamp = ConvertTo-DateTimeOffsetOrNull -Value $deployedProfileFeedGeneratedAt
            if ($null -eq $localTimestamp -or $null -eq $deployedTimestamp) {
                $warnings.Add("Portfolio feed timestamp comparison was unavailable because one timestamp is invalid.")
            } elseif ($localTimestamp.ToUniversalTime().Ticks -ne $deployedTimestamp.ToUniversalTime().Ticks) {
                $warnings.Add("Portfolio feed source timestamp differs from local projects.json generatedAt.")
            }
        }

        foreach ($routeCountName in @("catalog", "featured", "liveApps")) {
            $actualCount = $deployedRouteCounts[$routeCountName]
            $expectedCount = $localRouteCounts[$routeCountName]
            if ($null -eq $actualCount) {
                $warnings.Add("Portfolio feed counts.$routeCountName is missing.")
            } elseif ([int]$actualCount -ne [int]$expectedCount) {
                $warnings.Add("Portfolio feed counts.$routeCountName $actualCount differs from local expected count $expectedCount.")
            }
        }
    }

    $baseResult.warningCount = [int]$warnings.Count
    $baseResult.warnings = @($warnings.ToArray())
    $baseResult.status = if ($null -eq $deployedPayload) { "unavailable" } elseif ($warnings.Count -gt 0) { "warning" } else { "compatible" }
    return $baseResult
}

function Test-StableProjectEntityIds {
    <#
    .SYNOPSIS
    Verifies that every visible feed row has a unique stable identity and alias metadata.
    .PARAMETER ProjectsJson
    Generated projects.json text to inspect.
    #>
    [CmdletBinding()]
    param([string]$ProjectsJson)

    $payload = $null
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $payload = ConvertFrom-JsonPreservingArrays -Json $ProjectsJson
    } catch {
        $errors.Add("projects.json could not be parsed for stable entity identity validation.")
    }

    $missingIds = New-Object System.Collections.Generic.List[object]
    $invalidIds = New-Object System.Collections.Generic.List[object]
    $duplicateIds = New-Object System.Collections.Generic.List[string]
    $seenIds = @{}
    $missingCanonicalRepoCount = 0
    $missingAliasMetadataCount = 0
    $aliasRowCount = 0
    $aliasCount = 0
    $projects = if ($payload) { @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name "projects")) } else { @() }

    $projectIndex = 0
    foreach ($project in $projects) {
        $projectIndex++
        $repo = [string](Get-MemberValue -Object $project -Name "repo")
        $label = if ([string]::IsNullOrWhiteSpace($repo)) { "project-$projectIndex" } else { $repo }
        $id = [string](Get-MemberValue -Object $project -Name "id")
        if ([string]::IsNullOrWhiteSpace($id)) {
            $missingIds.Add([ordered]@{ repo = $label; index = $projectIndex })
        } elseif ($id -notmatch '^[a-z0-9][a-z0-9-]{2,63}$') {
            $invalidIds.Add([ordered]@{ repo = $label; id = $id })
        } else {
            $idKey = $id.ToLowerInvariant()
            if ($seenIds.ContainsKey($idKey)) {
                $duplicateIds.Add($id)
            } else {
                $seenIds[$idKey] = $label
            }
        }

        $canonicalRepo = [string](Get-MemberValue -Object $project -Name "canonicalRepo")
        if ([string]::IsNullOrWhiteSpace($canonicalRepo)) {
            $missingCanonicalRepoCount++
        }
        if (-not (Test-MemberExists -Object $project -Name "aliases")) {
            $missingAliasMetadataCount++
        } else {
            $rowAliases = @(Get-JsonArrayItems (Get-MemberValue -Object $project -Name "aliases"))
            if ($rowAliases.Count -gt 0) { $aliasRowCount++ }
            $aliasCount += $rowAliases.Count
        }
    }

    if ($null -eq $payload) {
        $errors.Add("projects.json is unavailable to stable entity identity validation.")
    }
    $duplicateIdArray = @($duplicateIds.ToArray() | Sort-Object -Unique)
    $missingIdArray = @($missingIds.ToArray())
    $invalidIdArray = @($invalidIds.ToArray())
    $fatalCount = $errors.Count + $missingIdArray.Count + $invalidIdArray.Count + $duplicateIdArray.Count + $missingCanonicalRepoCount + $missingAliasMetadataCount

    return [ordered]@{
        passed = [bool]($fatalCount -eq 0)
        status = if ($fatalCount -eq 0) { "verified" } elseif ($null -eq $payload) { "unavailable" } else { "failed" }
        projectCount = $projects.Count
        missingIdCount = $missingIdArray.Count
        missingIds = $missingIdArray
        invalidIdCount = $invalidIdArray.Count
        invalidIds = $invalidIdArray
        duplicateIdCount = $duplicateIdArray.Count
        duplicateIds = $duplicateIdArray
        missingCanonicalRepoCount = $missingCanonicalRepoCount
        missingAliasMetadataCount = $missingAliasMetadataCount
        aliasRowCount = $aliasRowCount
        aliasCount = $aliasCount
        fatalCount = $fatalCount
        errors = @($errors.ToArray())
        note = "Every visible project row carries an explicit or deterministic ID, an owner-qualified canonical repository, and an aliases array."
    }
}

function Test-FeedSchemaMigrationPolicy {
    <#
    .SYNOPSIS
    Verifies that the generated feed records its compatibility and migration policy.
    .PARAMETER ProjectsJson
    Generated projects.json text to inspect.
    #>
    [CmdletBinding()]
    param([string]$ProjectsJson)

    $payload = $null
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $payload = ConvertFrom-JsonPreservingArrays -Json $ProjectsJson
    } catch {
        $errors.Add("projects.json could not be parsed for schema migration policy validation.")
    }

    $policy = if ($payload) { Get-MemberValue -Object $payload -Name "schemaPolicy" } else { $null }
    $currentVersion = if ($policy) { [int](Get-MemberValue -Object $policy -Name "currentVersion") } else { 0 }
    $supportedVersions = if ($policy) { @(Get-JsonArrayItems (Get-MemberValue -Object $policy -Name "supportedVersions")) | ForEach-Object { [int]$_ } } else { @() }
    $compatibility = if ($policy) { [string](Get-MemberValue -Object $policy -Name "compatibility") } else { "" }
    $changeKind = if ($policy) { [string](Get-MemberValue -Object $policy -Name "changeKind") } else { "" }
    $migrationRequiredValue = if ($policy) { Get-MemberValue -Object $policy -Name "migrationRequired" } else { $false }
    $migrationRequired = [bool]$migrationRequiredValue
    $migrationNotes = if ($policy) { @(Get-JsonArrayItems (Get-MemberValue -Object $policy -Name "migrationNotes")) | ForEach-Object { [string]$_ } } else { @() }
    $deprecatedVersions = if ($policy) { @(Get-JsonArrayItems (Get-MemberValue -Object $policy -Name "deprecatedVersions")) | ForEach-Object { [int]$_ } } else { @() }
    $deprecationNotes = if ($policy) { @(Get-JsonArrayItems (Get-MemberValue -Object $policy -Name "deprecationNotes")) | ForEach-Object { [string]$_ } } else { @() }

    if ($null -eq $policy) { $errors.Add("Generated feed does not expose schemaPolicy.") }
    if ($currentVersion -ne [int]$ProjectsFeedSchemaVersion) {
        $errors.Add("Feed schema policy currentVersion does not match the generator version.")
    }
    if ($supportedVersions -notcontains $currentVersion) {
        $errors.Add("Feed schema policy supportedVersions does not include currentVersion.")
    }
    if ($migrationRequired -and @($migrationNotes).Count -eq 0) {
        $errors.Add("Required feed schema changes must include a migration note.")
    }
    if ($changeKind -eq "breaking" -and @($migrationNotes).Count -eq 0) {
        $errors.Add("Breaking feed schema changes must include a migration note.")
    }

    return [ordered]@{
        passed = [bool]($errors.Count -eq 0)
        status = if ($errors.Count -eq 0) { "documented" } else { "invalid" }
        currentVersion = $currentVersion
        supportedVersions = @($supportedVersions)
        compatibility = $compatibility
        changeKind = $changeKind
        migrationRequired = $migrationRequired
        migrationNotes = @($migrationNotes)
        deprecatedVersions = @($deprecatedVersions)
        deprecationNotes = @($deprecationNotes)
        fatalCount = $errors.Count
        errors = @($errors.ToArray())
        note = "The feed declares its supported version window and requires written migration notes for required or breaking contract changes."
    }
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

function ConvertTo-ProjectsSyncComparableJson {
    param([string]$Json)

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return ""
    }

    try {
        $payload = ConvertFrom-JsonPreservingArrays -Json $Json
        # Mask every volatile field so equality answers "is this the feed the catalog
        # produces", not "did anything upstream move since the last write". Feed freshness
        # and per-field drift are reported separately by Test-MetadataDrift. The masked set
        # is deliberately closed: a field that is not listed here is a real difference.
        foreach ($field in $script:ProjectsFeedVolatileTopLevelFields) {
            Set-MemberValue -Object $payload -Name $field -Value $null
        }
        $provenance = Get-MemberValue -Object $payload -Name "provenance"
        if ($provenance) {
            foreach ($field in $script:ProjectsFeedVolatileProvenanceFields) {
                Set-MemberValue -Object $provenance -Name $field -Value $null
            }
            # returnedCount and truncated stay compared: a genuine inventory change must
            # fail the gate even though the transport that produced it may vary.
            $enumeration = Get-MemberValue -Object $provenance -Name "repoEnumeration"
            if ($enumeration) {
                foreach ($field in $script:ProjectsFeedVolatileEnumerationFields) {
                    Set-MemberValue -Object $enumeration -Name $field -Value $null
                }
            }
        }
        foreach ($collection in @("projects", "suppressed")) {
            foreach ($row in @(Get-JsonArrayItems (Get-MemberValue -Object $payload -Name $collection))) {
                foreach ($field in $script:ProjectsFeedVolatileProjectFields) {
                    if (Test-MemberExists -Object $row -Name $field) {
                        Set-MemberValue -Object $row -Name $field -Value $null
                    }
                }
            }
        }
        return ConvertTo-ComparableJson $payload
    } catch {
        return (($Json -replace "`r`n", "`n").TrimEnd())
    }
}
