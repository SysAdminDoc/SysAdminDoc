# Report sections about catalog and repository metadata: feed metadata drift, topic
# and description hygiene with apply guidance, license metadata, fork-parent drift
# and stale-project review. Dot-sourced by scripts/sync-profile.ps1.

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
        [string]$Category,
        [string]$Field,
        [object]$OldValue,
        [object]$NewValue,
        [string]$Severity
    )

    return [ordered]@{
        repo = if ([string]::IsNullOrWhiteSpace($Repo)) { $null } else { $Repo }
        category = if ([string]::IsNullOrWhiteSpace($Category)) { $null } else { $Category }
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
        "searchMetadata",
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
        $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field "projects.json" -OldValue "unreadable" -NewValue "valid generated feed" -Severity "fatal"))
    }

    try {
        $expected = $ExpectedProjectsJson | ConvertFrom-Json
    } catch {
        $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field "expectedProjects" -OldValue "generated feed" -NewValue "unreadable" -Severity "fatal"))
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
                $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "fatal"))
            }
        }

        $provenanceFatalFields = @(
            "provenance.version",
            "provenance.feedSchemaVersion",
            "provenance.sourceRepository",
            "provenance.catalogSha256",
            "provenance.generatorSha256",
            "provenance.projectSchemaSha256",
            "provenance.repoEnumeration.returnedCount",
            "provenance.repoEnumeration.truncated"
        )
        foreach ($field in $provenanceFatalFields) {
            $oldValue = Get-NestedMemberValue -Object $current -Path $field
            $newValue = Get-NestedMemberValue -Object $expected -Path $field
            if ((ConvertTo-ComparableJson $oldValue) -ne (ConvertTo-ComparableJson $newValue)) {
                $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "fatal"))
            }
        }

        # Which transport enumerated the repos is a fetch-path detail, not catalog
        # content. This script drops from GraphQL to REST on its own whenever
        # GitHub throttles the query, so a run that wrote "graphql" and a later
        # check that fell back to "rest-fallback" describe the same inventory.
        # Treating that as fatal failed the nightly freshness check on GitHub's
        # mood rather than on any real drift. Same test the requestedLimit
        # comparison below already uses: identical inventory, neither truncated.
        $currentProvider = Get-NestedMemberValue -Object $current -Path "provenance.metadataProvider"
        $expectedProvider = Get-NestedMemberValue -Object $expected -Path "provenance.metadataProvider"
        if ((ConvertTo-ComparableJson $currentProvider) -ne (ConvertTo-ComparableJson $expectedProvider)) {
            $providerCurrentCount = Get-NestedMemberValue -Object $current -Path "provenance.repoEnumeration.returnedCount"
            $providerExpectedCount = Get-NestedMemberValue -Object $expected -Path "provenance.repoEnumeration.returnedCount"
            $providerCurrentTruncated = ConvertTo-BooleanValue (Get-NestedMemberValue -Object $current -Path "provenance.repoEnumeration.truncated")
            $providerExpectedTruncated = ConvertTo-BooleanValue (Get-NestedMemberValue -Object $expected -Path "provenance.repoEnumeration.truncated")
            $providerInventorySame = (ConvertTo-ComparableJson $providerCurrentCount) -eq (ConvertTo-ComparableJson $providerExpectedCount)
            $providerNotTruncated = ($providerCurrentTruncated -eq $false -and $providerExpectedTruncated -eq $false)
            $providerSeverity = if ($providerInventorySame -and $providerNotTruncated) { "info" } else { "fatal" }
            $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field "provenance.metadataProvider" -OldValue $currentProvider -NewValue $expectedProvider -Severity $providerSeverity))
        }

        $currentRequestedLimit = Get-NestedMemberValue -Object $current -Path "provenance.repoEnumeration.requestedLimit"
        $expectedRequestedLimit = Get-NestedMemberValue -Object $expected -Path "provenance.repoEnumeration.requestedLimit"
        if ((ConvertTo-ComparableJson $currentRequestedLimit) -ne (ConvertTo-ComparableJson $expectedRequestedLimit)) {
            $currentReturnedCount = Get-NestedMemberValue -Object $current -Path "provenance.repoEnumeration.returnedCount"
            $expectedReturnedCount = Get-NestedMemberValue -Object $expected -Path "provenance.repoEnumeration.returnedCount"
            $currentTruncated = ConvertTo-BooleanValue (Get-NestedMemberValue -Object $current -Path "provenance.repoEnumeration.truncated")
            $expectedTruncated = ConvertTo-BooleanValue (Get-NestedMemberValue -Object $expected -Path "provenance.repoEnumeration.truncated")
            $inventorySame = (ConvertTo-ComparableJson $currentReturnedCount) -eq (ConvertTo-ComparableJson $expectedReturnedCount)
            $notTruncated = ($currentTruncated -eq $false -and $expectedTruncated -eq $false)
            $severity = if ($inventorySame -and $notTruncated) { "info" } else { "fatal" }
            $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field "provenance.repoEnumeration.requestedLimit" -OldValue $currentRequestedLimit -NewValue $expectedRequestedLimit -Severity $severity))
        }

        foreach ($field in @("provenance.sourceCommit", "provenance.metadataSnapshotAt")) {
            $oldValue = Get-NestedMemberValue -Object $current -Path $field
            $newValue = Get-NestedMemberValue -Object $expected -Path $field
            if ((ConvertTo-ComparableJson $oldValue) -ne (ConvertTo-ComparableJson $newValue)) {
                $drift.Add((New-MetadataDriftRecord -Repo $null -Category $null -Field $field -OldValue $oldValue -NewValue $newValue -Severity "info"))
            }
        }

        $currentRows = New-MetadataRowIndex -ProjectsPayload $current
        $expectedRows = New-MetadataRowIndex -ProjectsPayload $expected
        $rowKeys = @(@($currentRows.Keys) + @($expectedRows.Keys) | Sort-Object -Unique)
        # Same list the sync-equality mask uses, so a field cannot be tolerated by one
        # and treated as a real difference by the other.
        $infoFields = @($script:ProjectsFeedVolatileProjectFields)
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
            "searchMetadata",
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
            $category = if ($hasExpected) {
                [string](Get-MemberValue -Object $expectedRows[$key] -Name "category")
            } else {
                [string](Get-MemberValue -Object $currentRows[$key] -Name "category")
            }

            if (-not $hasCurrent) {
                $drift.Add((New-MetadataDriftRecord -Repo $repo -Category $category -Field "row" -OldValue $null -NewValue "present" -Severity "fatal"))
                continue
            }
            if (-not $hasExpected) {
                $drift.Add((New-MetadataDriftRecord -Repo $repo -Category $category -Field "row" -OldValue "present" -NewValue $null -Severity "fatal"))
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
                    $drift.Add((New-MetadataDriftRecord -Repo $repo -Category $category -Field $field -OldValue $oldValue -NewValue $newValue -Severity $severity))
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

function Test-PublicMetadataHygieneRow {
    param(
        [object]$Repo,
        [string]$RepoName,
        [string]$Category
    )

    if (-not (Test-SafeGitHubName -Name $RepoName)) {
        return $false
    }
    if ([string]$Category -eq "suppressed") {
        return $false
    }
    if (ConvertTo-BooleanValue (Get-MemberValue -Object $Repo -Name "isPrivate")) {
        return $false
    }

    $visibility = [string](Get-MemberValue -Object $Repo -Name "visibility")
    if (-not [string]::IsNullOrWhiteSpace($visibility) -and -not 'PUBLIC'.Equals($visibility.ToUpperInvariant())) {
        return $false
    }

    return $true
}

function Test-SafeTopicToken {
    param([string]$Value)

    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^[a-z0-9][a-z0-9-]{0,49}$')
}

function New-MetadataTopicCommand {
    param(
        [string]$OwnerName,
        [string]$RepoName,
        [string[]]$TopicHints
    )

    if (-not (Test-SafeGitHubName -Name $OwnerName) -or -not (Test-SafeGitHubName -Name $RepoName)) {
        return $null
    }

    $safeTopics = New-Object System.Collections.Generic.List[string]
    foreach ($hint in @($TopicHints)) {
        $token = ConvertTo-TopicToken $hint
        if ((Test-SafeTopicToken -Value $token) -and -not $safeTopics.Contains($token)) {
            $safeTopics.Add($token)
        }
    }
    if ($safeTopics.Count -eq 0) {
        return $null
    }

    $topicArguments = @($safeTopics | ForEach-Object { "--add-topic $_" })
    return "gh repo edit $OwnerName/$RepoName $($topicArguments -join ' ')"
}

function New-MetadataDescriptionCommand {
    param(
        [string]$OwnerName,
        [string]$RepoName,
        [string]$Description
    )

    if (-not (Test-SafeGitHubName -Name $OwnerName) -or -not (Test-SafeGitHubName -Name $RepoName)) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($Description)) {
        return $null
    }

    return "gh repo edit $OwnerName/$RepoName --description $(ConvertTo-PowerShellSingleQuotedArgument -Value $Description)"
}

function New-MetadataDescriptionPatchGuidance {
    param(
        [string]$RepoName,
        [string]$CatalogDescription
    )

    if ([string]::IsNullOrWhiteSpace($CatalogDescription)) {
        return "Add descriptionOverride for $RepoName in data/profile-catalog.json or set a public GitHub description before rerunning sync."
    }

    return "Use the command to set the public GitHub description, or update descriptionOverride for $RepoName in data/profile-catalog.json if the catalog wording should differ."
}

function New-MetadataHygieneHandoff {
    param(
        [object[]]$MissingTopics,
        [object[]]$MissingDescriptions,
        [int]$SuppressedTopicCount,
        [int]$SuppressedDescriptionCount,
        [int]$UnsafeOrPrivateTopicCount,
        [int]$UnsafeOrPrivateDescriptionCount,
        [string]$OwnerName,
        [int]$MaxRows = 10
    )

    $topicRows = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($MissingTopics | Select-Object -First $MaxRows)) {
        $repoName = [string](Get-MemberValue -Object $row -Name "repo")
        $topicHints = @((Get-MemberValue -Object $row -Name "topicHints") | ForEach-Object { [string]$_ })
        $command = New-MetadataTopicCommand -OwnerName $OwnerName -RepoName $repoName -TopicHints $topicHints
        if ([string]::IsNullOrWhiteSpace($command)) {
            continue
        }

        $topicRows.Add([ordered]@{
            repo = $repoName
            language = Get-MemberValue -Object $row -Name "language"
            category = Get-MemberValue -Object $row -Name "category"
            topicHints = @($topicHints)
            command = $command
        })
    }

    $descriptionRows = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($MissingDescriptions | Select-Object -First $MaxRows)) {
        $repoName = [string](Get-MemberValue -Object $row -Name "repo")
        $catalogDescription = Get-MemberValue -Object $row -Name "catalogDescription"
        $command = New-MetadataDescriptionCommand -OwnerName $OwnerName -RepoName $repoName -Description ([string]$catalogDescription)
        $descriptionRows.Add([ordered]@{
            repo = $repoName
            language = Get-MemberValue -Object $row -Name "language"
            category = Get-MemberValue -Object $row -Name "category"
            catalogDescription = if ([string]::IsNullOrWhiteSpace([string]$catalogDescription)) { $null } else { [string]$catalogDescription }
            command = if ([string]::IsNullOrWhiteSpace($command)) { $null } else { $command }
            catalogPatchGuidance = New-MetadataDescriptionPatchGuidance -RepoName $repoName -CatalogDescription ([string]$catalogDescription)
        })
    }

    $actionableCount = $topicRows.Count + $descriptionRows.Count
    $redactedCount = $SuppressedTopicCount + $SuppressedDescriptionCount + $UnsafeOrPrivateTopicCount + $UnsafeOrPrivateDescriptionCount
    $status = if ($actionableCount -gt 0) {
        "actionable"
    } elseif ($redactedCount -gt 0) {
        "redacted-only"
    } else {
        "clean"
    }

    return [ordered]@{
        status = $status
        maxRows = $MaxRows
        topicRowCount = $topicRows.Count
        descriptionRowCount = $descriptionRows.Count
        excludedSuppressedTopicCount = $SuppressedTopicCount
        excludedSuppressedDescriptionCount = $SuppressedDescriptionCount
        excludedUnsafeOrPrivateTopicCount = $UnsafeOrPrivateTopicCount
        excludedUnsafeOrPrivateDescriptionCount = $UnsafeOrPrivateDescriptionCount
        topicRows = $topicRows.ToArray()
        descriptionRows = $descriptionRows.ToArray()
        note = "Handoff rows intentionally exclude suppressed, private, and unsafe repository names; count fields preserve hidden gap totals."
    }
}

function Get-TopicApplyCapability {
    <#
    .SYNOPSIS
    Reports whether -ApplyTopics could actually run, rather than asserting it cannot.
    .DESCRIPTION
    -ApplyTopics is implemented and gated on data/topic-allowlist.json. Hard-coding
    applyModeAvailable to false made the report describe a capability the tree does
    not have. Reads the same allowlist the apply path reads so the two agree.
    #>
    param([string]$AllowlistPath = $TopicAllowlistPath)

    $available = $false
    $count = 0
    $reason = $null
    $fullPath = if ([string]::IsNullOrWhiteSpace($AllowlistPath)) {
        $null
    } elseif ([System.IO.Path]::IsPathRooted($AllowlistPath)) {
        $AllowlistPath
    } else {
        Join-Path $RepoRoot $AllowlistPath
    }

    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        $reason = "No topic allowlist path is configured."
    } elseif (-not (Test-Path -LiteralPath $fullPath)) {
        $reason = "Topic allowlist not found at $AllowlistPath; create a JSON array of repository names."
    } else {
        try {
            # ConvertFrom-Json unwraps a single-element array to a bare value, which would
            # misreport a one-repository allowlist as malformed. The token-preserving
            # reader keeps the array wrapper.
            $parsed = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath $fullPath -Raw)
        } catch {
            $parsed = $null
            $reason = "Topic allowlist at $AllowlistPath is not valid JSON."
        }
        if ($null -eq $reason) {
            if (-not (Test-JsonArrayWrapper -Value $parsed)) {
                $reason = "Topic allowlist at $AllowlistPath must be a JSON array of repository names."
            } else {
                # Every element must be a string. A nested object stringifies to
                # "System.Collections.Specialized.OrderedDictionary", a bool to "True"
                # and a number to "1", all of which satisfy the safe-name pattern and
                # would be counted as repositories.
                $items = @(Get-JsonArrayItems $parsed)
                $nonString = @($items | Where-Object { $_ -isnot [string] })
                $names = @($items | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })
                if ($nonString.Count -gt 0) {
                    $reason = "Topic allowlist at $AllowlistPath must contain only repository name strings."
                } elseif ($names.Count -ne $items.Count) {
                    $reason = "Topic allowlist at $AllowlistPath contains a blank repository name."
                } elseif (@($names | Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 }).Count -gt 0) {
                    # The apply path matches with -notin, so a duplicate inflates the
                    # reported count without adding a repository it would touch.
                    $reason = "Topic allowlist at $AllowlistPath contains duplicate repository names."
                } elseif ($names.Count -eq 0) {
                    $reason = "Topic allowlist at $AllowlistPath is empty; no repository is eligible for topic apply."
                } elseif (@($names | Where-Object { -not (Test-SafeGitHubName -Name ([string]$_)) }).Count -gt 0) {
                    $reason = "Topic allowlist at $AllowlistPath contains an unsafe repository name."
                } else {
                    $available = $true
                    $count = $names.Count
                }
            }
        }
    }

    return [ordered]@{
        available = [bool]$available
        allowlistedRepositoryCount = [int]$count
        unavailableReason = $reason
    }
}

function Test-MetadataHygiene {
    param(
        [object[]]$Repos,
        [hashtable[]]$CatalogEntries = @(),
        [string]$OwnerName = $Owner,
        [string]$TopicAllowlist = $TopicAllowlistPath
    )

    $missingTopics = New-Object System.Collections.Generic.List[object]
    $missingDescriptions = New-Object System.Collections.Generic.List[object]
    $catalogLookup = New-CatalogEntryLookup -Entries $CatalogEntries
    $totalMissingTopicCount = 0
    $totalMissingDescriptionCount = 0
    $suppressedTopicCount = 0
    $suppressedDescriptionCount = 0
    $unsafeOrPrivateTopicCount = 0
    $unsafeOrPrivateDescriptionCount = 0

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
        $category = if ($catalogEntry) { [string]$catalogEntry.category } else { $null }
        $publicHygieneRow = Test-PublicMetadataHygieneRow -Repo $repo -RepoName $repoName -Category $category

        $topicNames = @()
        $topics = Get-MemberValue -Object $repo -Name "repositoryTopics"
        foreach ($topic in @($topics)) {
            $topicName = Get-MemberValue -Object $topic -Name "name"
            if (-not [string]::IsNullOrWhiteSpace([string]$topicName)) {
                $topicNames += [string]$topicName
            }
        }

        if ($topicNames.Count -eq 0) {
            $totalMissingTopicCount++
            if ($publicHygieneRow) {
                $missingTopics.Add([ordered]@{
                    repo = $repoName
                    language = if ([string]::IsNullOrWhiteSpace([string]$language)) { $null } else { [string]$language }
                    pushedAt = ConvertTo-IsoText (Get-MemberValue -Object $repo -Name "pushedAt")
                    category = if ([string]::IsNullOrWhiteSpace([string]$category)) { $null } else { $category }
                    topicHints = @(Get-TopicHints -Repo $repoName -Language $language -Entry $catalogEntry -Description ([string](Get-MemberValue -Object $repo -Name "description")))
                })
            } elseif ($category -eq "suppressed") {
                $suppressedTopicCount++
            } else {
                $unsafeOrPrivateTopicCount++
            }
        }

        $description = Get-MemberValue -Object $repo -Name "description"
        if ([string]::IsNullOrWhiteSpace([string]$description)) {
            $totalMissingDescriptionCount++
            if ($publicHygieneRow) {
                $missingDescriptions.Add([ordered]@{
                    repo = $repoName
                    language = if ([string]::IsNullOrWhiteSpace([string]$language)) { $null } else { [string]$language }
                    category = if ([string]::IsNullOrWhiteSpace([string]$category)) { $null } else { $category }
                    catalogDescription = if ($catalogEntry -and -not [string]::IsNullOrWhiteSpace([string]$catalogEntry.descriptionOverride)) { [string]$catalogEntry.descriptionOverride } else { $null }
                })
            } elseif ($category -eq "suppressed") {
                $suppressedDescriptionCount++
            } else {
                $unsafeOrPrivateDescriptionCount++
            }
        }
    }
    $topicApplyCapability = Get-TopicApplyCapability -AllowlistPath $TopicAllowlist
    $handoff = New-MetadataHygieneHandoff `
        -MissingTopics $missingTopics.ToArray() `
        -MissingDescriptions $missingDescriptions.ToArray() `
        -SuppressedTopicCount $suppressedTopicCount `
        -SuppressedDescriptionCount $suppressedDescriptionCount `
        -UnsafeOrPrivateTopicCount $unsafeOrPrivateTopicCount `
        -UnsafeOrPrivateDescriptionCount $unsafeOrPrivateDescriptionCount `
        -OwnerName $OwnerName

    return [ordered]@{
        missingTopicCount = $totalMissingTopicCount
        missingDescriptionCount = $totalMissingDescriptionCount
        publicMissingTopicCount = $missingTopics.Count
        publicMissingDescriptionCount = $missingDescriptions.Count
        redactedTopicCount = $suppressedTopicCount + $unsafeOrPrivateTopicCount
        redactedDescriptionCount = $suppressedDescriptionCount + $unsafeOrPrivateDescriptionCount
        suppressedTopicCount = $suppressedTopicCount
        suppressedDescriptionCount = $suppressedDescriptionCount
        unsafeOrPrivateTopicCount = $unsafeOrPrivateTopicCount
        unsafeOrPrivateDescriptionCount = $unsafeOrPrivateDescriptionCount
        topicHintPolicy = [ordered]@{
            # -Check only reports hints; only the separate -ApplyTopics mode writes.
            mutatesRepositories = $false
            applyModeAvailable = $topicApplyCapability.available
            requiresExplicitAllowlist = $true
            allowlistedRepositoryCount = $topicApplyCapability.allowlistedRepositoryCount
            applyModeUnavailableReason = $topicApplyCapability.unavailableReason
        }
        handoff = $handoff
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
        # @(): the function's return unrolls a zero- or one-row result to $null or a bare row.
        licenseCounts = @(Get-SortedReportRows -Rows @($licenseCounts.Values) -Keys @("licenseSpdxId", "licenseKey", "licenseName"))
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
    $matchingGitHubForkCount = 0
    $catalogContinuationCount = 0
    $missingCatalogAttributionCount = 0
    $parentMismatchCount = 0
    $parentUnavailableCount = 0
    $publicDetailRowCount = 0
    $redactedDetailRowCount = 0

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
        $category = if ($entry) { [string]$entry.category } else { $null }
        $publicForkRow = Test-PublicMetadataHygieneRow -Repo $repo -RepoName $repoName -Category $category
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
                $parentUnavailableCount++
                $row = [ordered]@{
                    repo = $repoName
                    reason = "GitHub marks this repository as a fork, but parent metadata was unavailable"
                    error = if ([string]::IsNullOrWhiteSpace([string]$fetchError)) { $null } else { [string]$fetchError }
                }
                if ($publicForkRow) {
                    $parentUnavailable.Add($row)
                    $publicDetailRowCount++
                } else {
                    $redactedDetailRowCount++
                }
            }
            if ([string]::IsNullOrWhiteSpace($catalogForkOf)) {
                $missingCatalogAttributionCount++
                $row = [ordered]@{
                    repo = $repoName
                    githubParent = if ([string]::IsNullOrWhiteSpace([string]$githubParent)) { $null } else { [string]$githubParent }
                    reason = "GitHub marks this repository as a fork, but the catalog has no forkOf attribution"
                }
                if ($publicForkRow) {
                    $missingCatalogAttribution.Add($row)
                    $publicDetailRowCount++
                } else {
                    $redactedDetailRowCount++
                }
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$githubParent) -and $catalogForkOf.ToLowerInvariant() -ne ([string]$githubParent).ToLowerInvariant()) {
                $parentMismatchCount++
                $row = [ordered]@{
                    repo = $repoName
                    catalogForkOf = $catalogForkOf
                    githubParent = [string]$githubParent
                    reason = "catalog forkOf does not match GitHub fork parent"
                }
                if ($publicForkRow) {
                    $parentMismatches.Add($row)
                    $publicDetailRowCount++
                } else {
                    $redactedDetailRowCount++
                }
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$githubParent)) {
                $matchingGitHubForkCount++
                $row = [ordered]@{
                    repo = $repoName
                    catalogForkOf = $catalogForkOf
                    githubParent = [string]$githubParent
                }
                if ($publicForkRow) {
                    $matchingGitHubForks.Add($row)
                    $publicDetailRowCount++
                } else {
                    $redactedDetailRowCount++
                }
            }
            continue
        }

        $catalogContinuationCount++
        $row = [ordered]@{
            repo = $repoName
            catalogForkOf = $catalogForkOf
            reason = "catalog declares an upstream continuation/import, but GitHub does not mark this repository as a fork"
        }
        if ($publicForkRow) {
            $catalogContinuations.Add($row)
            $publicDetailRowCount++
        } else {
            $redactedDetailRowCount++
        }
    }

    return [ordered]@{
        checkedCount = $checkedCount
        githubForkCount = $githubForkCount
        catalogForkOfCount = $catalogForkOfCount
        matchingGitHubForkCount = $matchingGitHubForkCount
        catalogContinuationCount = $catalogContinuationCount
        missingCatalogAttributionCount = $missingCatalogAttributionCount
        parentMismatchCount = $parentMismatchCount
        parentUnavailableCount = $parentUnavailableCount
        warningCount = $missingCatalogAttributionCount + $parentMismatchCount + $parentUnavailableCount
        publicDetailRowCount = $publicDetailRowCount
        redactedDetailRowCount = $redactedDetailRowCount
        matchingGitHubForks = $matchingGitHubForks.ToArray()
        catalogContinuations = $catalogContinuations.ToArray()
        missingCatalogAttribution = $missingCatalogAttribution.ToArray()
        parentMismatches = $parentMismatches.ToArray()
        parentUnavailable = $parentUnavailable.ToArray()
        note = "GitHub fork-parent drift is warning-only: catalog continuations are allowed, while missing or mismatched GitHub fork attribution should be reviewed. Detail rows intentionally exclude suppressed, private, and unsafe repository names."
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
    $reviewByCount = 0
    $reviewOverdueCount = 0
    $reviewScheduledCount = 0

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

        # A review-by date takes over from the age thresholds: until that day the entry is left
        # alone (a finished tool can be quiet on purpose), and after it the entry is overdue
        # however recently it was pushed.
        $reviewBy = $null
        $reviewByDate = [datetime]::MinValue
        if ($entry.reviewBy -is [string] -and [datetime]::TryParseExact($entry.reviewBy, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$reviewByDate)) {
            $reviewBy = [string]$entry.reviewBy
            $reviewByCount++
        }
        if ($null -ne $reviewBy -and $Now.Date -gt $reviewByDate.Date) {
            $signals.Add("review-overdue")
            $reviewOverdueCount++
        } elseif ($null -ne $reviewBy) {
            $reviewScheduledCount++
        } elseif (-not $meta) {
            $signals.Add("metadata-unavailable")
        }
        # With a review-by date the date decides, and none of the age signals apply.
        $byAge = $null -eq $reviewBy
        if ($byAge -and $null -eq $pushedAtAgeDays) {
            $signals.Add("pushedAt-missing")
        } elseif ($byAge -and $pushedAtAgeDays -gt $StaleAfterDays) {
            $signals.Add("pushedAt-stale")
        }
        if ($release) {
            if ($byAge -and $null -eq $latestReleaseAgeDays) {
                $signals.Add("release-date-missing")
            } elseif ($byAge -and $latestReleaseAgeDays -gt $ReleaseStaleAfterDays) {
                $signals.Add("release-stale")
            }
        } else {
            $noReleaseCount++
            if ($byAge -and $null -ne $pushedAtAgeDays -and $pushedAtAgeDays -gt $StaleAfterDays) {
                $signals.Add("no-latest-release")
            }
        }

        $isPinned = ($entry.featured -eq $true -or $entry.currentlyBuilding -eq $true)
        if ($byAge -and -not $isPinned -and $null -ne $pushedAtAgeDays -and $pushedAtAgeDays -gt $ArchiveAfterDays) {
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
                reviewBy = $reviewBy
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
        reviewByCount = [int]$reviewByCount
        reviewOverdueCount = [int]$reviewOverdueCount
        reviewScheduledCount = [int]$reviewScheduledCount
        warningCount = [int]$staleProjectCount
        statusCounts = @($statusCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { [ordered]@{ kind = [string]$_.Name; count = [int]$_.Value } })
        # @(): the function's return unrolls a zero- or one-row result to $null or a bare row.
        suppressionReasonCounts = @(Get-SortedReportRows -Rows @($suppressionCounts.Values) -Keys @("reasonCode", "visibilityClass", "publicReason"))
        rows = $rows.ToArray()
        note = "Warning-only stale/archive review: visitor-facing rows are listed by repo; suppressed catalog rows are summarized by public reason code without exposing suppressed identifiers. An entry with a reviewBy date is judged by that date alone."
    }
}
