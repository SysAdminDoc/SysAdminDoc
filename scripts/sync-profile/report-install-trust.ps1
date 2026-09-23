# Report sections about install paths: userscript metadata and install URL trust,
# and branch-tip provenance for clone-and-run snippets. Dot-sourced by
# scripts/sync-profile.ps1.

function Get-RawGitHubSourceInfo {
    param([string]$Url)

    $info = [ordered]@{
        sourceHost = $null
        sourceRepository = $null
        sourceRef = $null
        sourceRefType = "unknown"
        sourcePath = $null
        rawGitHub = $false
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $info
    }

    try {
        $uri = [Uri]$Url
        $info.sourceHost = $uri.Host
        if ($uri.Host -ne "raw.githubusercontent.com") {
            return $info
        }

        $match = [regex]::Match($uri.AbsolutePath, '^/(?<owner>[^/]+)/(?<repo>[^/]+)/(?<ref>[^/]+)/(?<path>.+)$')
        if (-not $match.Success) {
            return $info
        }

        $ref = [Uri]::UnescapeDataString($match.Groups["ref"].Value)
        $info.rawGitHub = $true
        $info.sourceRepository = "$([Uri]::UnescapeDataString($match.Groups["owner"].Value))/$([Uri]::UnescapeDataString($match.Groups["repo"].Value))"
        $info.sourceRef = $ref
        $info.sourcePath = [Uri]::UnescapeDataString($match.Groups["path"].Value)
        $info.sourceRefType = if ($ref -match '^[a-f0-9]{40}$') {
            "commit"
        } elseif ($ref -match '^v?\d+(\.\d+){1,3}([.-].*)?$') {
            "tag"
        } else {
            "branch"
        }
    } catch {
        $info.sourceHost = $null
    }

    return $info
}

function Get-UserscriptMetadata {
    param([string]$Content)

    $metadata = @{}
    $inBlock = $false
    $closed = $false

    foreach ($line in @(([string]$Content) -split "`r?`n")) {
        if (-not $inBlock) {
            if ($line -match '^\s*//\s*==UserScript==\s*$') {
                $inBlock = $true
            }
            continue
        }

        if ($line -match '^\s*//\s*==/UserScript==\s*$') {
            $closed = $true
            break
        }

        $match = [regex]::Match($line, '^\s*//\s*@(?<key>[A-Za-z][\w:-]*)\s*(?<value>.*)$')
        if (-not $match.Success) {
            continue
        }

        $key = $match.Groups["key"].Value
        $value = $match.Groups["value"].Value.Trim()
        if (-not $metadata.ContainsKey($key)) {
            $metadata[$key] = New-Object System.Collections.Generic.List[string]
        }
        $metadata[$key].Add($value)
    }

    return [ordered]@{
        metadataBlockPresent = $inBlock
        metadataBlockClosed = [bool]($inBlock -and $closed)
        metadata = $metadata
    }
}

function Get-UserscriptMetadataValues {
    param(
        [hashtable]$Metadata,
        [string]$Key
    )

    if ($null -eq $Metadata -or -not $Metadata.ContainsKey($Key)) {
        return @()
    }
    return @($Metadata[$Key] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-FirstUserscriptMetadataValue {
    param(
        [hashtable]$Metadata,
        [string]$Key
    )

    $values = @(Get-UserscriptMetadataValues -Metadata $Metadata -Key $Key)
    if ($values.Count -eq 0) {
        return $null
    }
    return [string]$values[0]
}

function Test-UserscriptBroadScope {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $normalized = (([string]$Value).Trim() -replace '\s+', '')
    return $normalized -in @(
        "*",
        "*://*",
        "*://*/*",
        "http://*/*",
        "https://*/*",
        "http*://*/*"
    )
}

function Test-AllowedUserscriptUrl {
    <#
    .SYNOPSIS
    Returns true when a userscript fetch URL is HTTPS on a trusted GitHub raw-content host.
    .DESCRIPTION
    Userscript install URLs are canonically raw.githubusercontent.com (Tampermonkey/Violentmonkey install links).
    Restricting fetches to HTTPS on GitHub-owned hosts prevents a tampered catalog userscriptUrl from turning
    the sync run into an SSRF probe against internal or arbitrary hosts.
    .PARAMETER Url
    The candidate userscript URL.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }

    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.Scheme -ne 'https') { return $false }

    $hostName = $uri.Host.ToLowerInvariant()
    if ($hostName -eq 'github.com') {
        return ($uri.AbsolutePath -match '(?i)(^|/)raw(/|$)')
    }

    $allowedHosts = @(
        'raw.githubusercontent.com',
        'gist.githubusercontent.com',
        'objects.githubusercontent.com'
    )
    return $hostName -in $allowedHosts
}

function Get-UserscriptContent {
    param([string]$Url)

    if (-not (Test-AllowedUserscriptUrl -Url $Url)) {
        return [ordered]@{
            succeeded = $false
            content = $null
            statusCode = $null
            error = "Blocked userscript fetch: URL is not HTTPS on an allowed GitHub raw-content host."
        }
    }

    $result = Invoke-SafeOutboundHttpRequest `
        -Url $Url `
        -Method Get `
        -TimeoutSec 20 `
        -MaxRedirects 5 `
        -ReadBody `
        -MaxBytes 2MB `
        -UserAgent 'SysAdminDoc-userscript-inspector' `
        -Accept 'text/plain, */*;q=0.1'
    return [ordered]@{
        succeeded = [bool]$result.ok
        content = $result.text
        statusCode = $result.statusCode
        error = $result.error
    }
}

function New-UserscriptTrustWarning {
    param(
        [string]$Kind,
        [string]$Message,
        [bool]$Fatal = $false
    )

    return [ordered]@{
        kind = $Kind
        message = $Message
        fatal = [bool]$Fatal
    }
}

function Get-UserscriptUrlProbe {
    param(
        [string]$Url,
        [hashtable]$ProbeByUrl = @{}
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return [ordered]@{
            checked = $false
            ok = $null
            statusCode = $null
            error = $null
            fatal = $false
        }
    }

    if ($ProbeByUrl.ContainsKey($Url)) {
        $probe = $ProbeByUrl[$Url]
        return [ordered]@{
            checked = $true
            ok = [bool](Get-MemberValue -Object $probe -Name "ok")
            statusCode = Get-MemberValue -Object $probe -Name "status"
            error = Get-MemberValue -Object $probe -Name "error"
            fatal = [bool](Get-MemberValue -Object $probe -Name "fatal")
        }
    }

    if (-not (Test-AllowedUserscriptUrl -Url $Url)) {
        return [ordered]@{
            checked = $true
            ok = $false
            statusCode = $null
            error = "Blocked userscript metadata URL probe: URL is not HTTPS on an allowed GitHub raw-content host."
            fatal = $false
        }
    }

    $result = Test-HttpUrl -Url $Url -TimeoutSec 12 -Retries 1
    return [ordered]@{
        checked = $true
        ok = [bool]$result.ok
        statusCode = $result.status
        error = $result.error
        fatal = [bool]$result.fatal
    }
}

function Get-UserscriptMetadataUrlTrust {
    param(
        [string]$Url,
        [object]$InstallSource,
        [hashtable]$ProbeByUrl = @{}
    )

    $source = Get-RawGitHubSourceInfo -Url $Url
    $refMatches = $null
    if ([bool](Get-MemberValue -Object $InstallSource -Name "rawGitHub") -and [bool]$source.rawGitHub) {
        $installRepository = [string](Get-MemberValue -Object $InstallSource -Name "sourceRepository")
        $installRef = [string](Get-MemberValue -Object $InstallSource -Name "sourceRef")
        if (-not [string]::IsNullOrWhiteSpace($installRepository) -and -not [string]::IsNullOrWhiteSpace($installRef)) {
            $refMatches = [bool](
                $source.sourceRepository -eq $installRepository -and
                $source.sourceRef -eq $installRef
            )
        }
    }

    $probe = Get-UserscriptUrlProbe -Url $Url -ProbeByUrl $ProbeByUrl
    return [ordered]@{
        sourceRef = $source.sourceRef
        refMatchesSource = $refMatches
        probeSucceeded = if ([bool]$probe.checked) { $probe.ok } else { $null }
        probeStatusCode = $probe.statusCode
        probeError = $probe.error
        probeFatal = [bool]$probe.fatal
    }
}

function Test-UserscriptInstallTrust {
    param(
        [hashtable[]]$Entries,
        [hashtable]$ContentByUrl = @{},
        [hashtable]$ProbeByUrl = @{},
        [switch]$Skip
    )

    $userscriptEntries = @($Entries | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.userscriptUrl) -or
            ([string]$_.downloadKind).ToLowerInvariant() -eq "userscript"
        } | Sort-Object repo)

    if ($Skip) {
        return [ordered]@{
            skipped = $true
            skipReason = if ($script:Offline) { "offline mode" } else { "link validation skipped" }
            checkedCount = 0
            installActionCount = $userscriptEntries.Count
            rawGitHubCount = 0
            branchSourceCount = 0
            tagOrCommitSourceCount = 0
            metadataBlockCount = 0
            missingMetadataBlockCount = 0
            missingVersionCount = 0
            missingUpdateUrlCount = 0
            missingDownloadUrlCount = 0
            updateUrlProbeFailureCount = 0
            downloadUrlProbeFailureCount = 0
            updateUrlRefMismatchCount = 0
            downloadUrlRefMismatchCount = 0
            broadScopeCount = 0
            releaseChannelReadyCount = 0
            releaseChannelKeepBranchCount = 0
            releaseChannelBlockedCount = 0
            warningCount = 0
            fatalCount = 0
            rows = @()
            note = "Userscript metadata inspection parses raw .user.js headers only; script bodies are not executed."
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $userscriptEntries) {
        $url = if ([string]::IsNullOrWhiteSpace([string]$entry.userscriptUrl)) { $null } else { [string]$entry.userscriptUrl }
        $source = Get-RawGitHubSourceInfo -Url $url
        $warnings = New-Object System.Collections.Generic.List[object]
        $fetchStatus = [ordered]@{ succeeded = $false; content = $null; statusCode = $null; error = $null }

        if ([string]::IsNullOrWhiteSpace($url)) {
            $warnings.Add((New-UserscriptTrustWarning -Kind "userscript-url-missing" -Message "Catalog marks this row as a userscript but has no userscriptUrl."))
        } elseif ($ContentByUrl.ContainsKey($url)) {
            $fetchStatus.succeeded = $true
            $fetchStatus.content = [string]$ContentByUrl[$url]
        } else {
            $fetchStatus = Get-UserscriptContent -Url $url
        }

        $metadataResult = Get-UserscriptMetadata -Content ([string]$fetchStatus.content)
        $metadata = [hashtable]$metadataResult.metadata
        $name = Get-FirstUserscriptMetadataValue -Metadata $metadata -Key "name"
        $version = Get-FirstUserscriptMetadataValue -Metadata $metadata -Key "version"
        $updateUrl = Get-FirstUserscriptMetadataValue -Metadata $metadata -Key "updateURL"
        $downloadUrl = Get-FirstUserscriptMetadataValue -Metadata $metadata -Key "downloadURL"
        $matchValues = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "match")
        $includes = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "include")
        $grants = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "grant")
        $connects = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "connect")
        $requires = @(Get-UserscriptMetadataValues -Metadata $metadata -Key "require")
        $scopeValues = @($matchValues + $includes)
        $broadScopes = @($scopeValues | Where-Object { Test-UserscriptBroadScope -Value ([string]$_) })
        $updateUrlTrust = Get-UserscriptMetadataUrlTrust -Url $updateUrl -InstallSource $source -ProbeByUrl $ProbeByUrl
        $downloadUrlTrust = Get-UserscriptMetadataUrlTrust -Url $downloadUrl -InstallSource $source -ProbeByUrl $ProbeByUrl

        if (-not $fetchStatus.succeeded) {
            $warnings.Add((New-UserscriptTrustWarning -Kind "userscript-fetch-failed" -Message "Could not fetch the raw userscript for metadata inspection."))
        } elseif (-not [bool]$metadataResult.metadataBlockPresent) {
            $warnings.Add((New-UserscriptTrustWarning -Kind "metadata-block-missing" -Message "Userscript metadata block is missing."))
        } else {
            if (-not [bool]$metadataResult.metadataBlockClosed) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "metadata-block-unclosed" -Message "Userscript metadata block is not closed."))
            }
            if ([string]::IsNullOrWhiteSpace($name)) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "name-missing" -Message "Userscript metadata is missing @name."))
            }
            if ([string]::IsNullOrWhiteSpace($version)) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "version-missing" -Message "Userscript metadata is missing @version, which userscript managers use for update checks."))
            }
            if ($scopeValues.Count -eq 0) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "scope-missing" -Message "Userscript metadata is missing @match or @include scope."))
            }
            if ($broadScopes.Count -gt 0) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "scope-broad" -Message "Userscript metadata includes an all-sites @match or @include scope."))
            }
            if ([string]::IsNullOrWhiteSpace($updateUrl)) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "update-url-missing" -Message "Userscript metadata is missing an explicit @updateURL."))
            } else {
                if ($null -ne $updateUrlTrust.refMatchesSource -and -not [bool]$updateUrlTrust.refMatchesSource) {
                    $warnings.Add((New-UserscriptTrustWarning -Kind "update-url-ref-mismatch" -Message "Userscript @updateURL does not use the same repository/ref as the catalog install URL."))
                }
                if ($null -ne $updateUrlTrust.probeSucceeded -and -not [bool]$updateUrlTrust.probeSucceeded) {
                    $warnings.Add((New-UserscriptTrustWarning -Kind "update-url-unreachable" -Message "Userscript @updateURL could not be reached." -Fatal:([bool]$updateUrlTrust.probeFatal)))
                }
            }
            if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
                $warnings.Add((New-UserscriptTrustWarning -Kind "download-url-missing" -Message "Userscript metadata is missing an explicit @downloadURL."))
            } else {
                if ($null -ne $downloadUrlTrust.refMatchesSource -and -not [bool]$downloadUrlTrust.refMatchesSource) {
                    $warnings.Add((New-UserscriptTrustWarning -Kind "download-url-ref-mismatch" -Message "Userscript @downloadURL does not use the same repository/ref as the catalog install URL."))
                }
                if ($null -ne $downloadUrlTrust.probeSucceeded -and -not [bool]$downloadUrlTrust.probeSucceeded) {
                    $warnings.Add((New-UserscriptTrustWarning -Kind "download-url-unreachable" -Message "Userscript @downloadURL could not be reached." -Fatal:([bool]$downloadUrlTrust.probeFatal)))
                }
            }
        }

        $rowFatalCount = @($warnings | Where-Object { $_.fatal }).Count

        # Release-channel readiness classifier (does not change install URLs):
        #   blocked     - metadata too incomplete to support an update channel
        #   ready       - metadata complete and already pinned to a tag/commit ref
        #   keep-branch - metadata complete branch install (canonical per the
        #                 userscript install-posture decision)
        $metadataComplete = [bool]$metadataResult.metadataBlockPresent -and
            -not [string]::IsNullOrWhiteSpace($version) -and
            -not [string]::IsNullOrWhiteSpace($updateUrl) -and
            -not [string]::IsNullOrWhiteSpace($downloadUrl)
        $sourceRefType = [string]$source.sourceRefType
        $updateUrlAligned = [bool]($null -ne $updateUrlTrust.refMatchesSource -and $updateUrlTrust.refMatchesSource)
        $releaseChannelReadiness = if (-not $metadataComplete) {
            "blocked"
        } elseif ($sourceRefType -in @("tag", "commit")) {
            "ready"
        } else {
            "keep-branch"
        }
        $releaseChannelNextAction = switch ($releaseChannelReadiness) {
            "blocked" { "Add @version, @updateURL, and @downloadURL metadata before evaluating a tag/release install channel." }
            "ready" { "Eligible to evaluate a tag or release install channel; metadata already pins a ref. No install-URL change required yet." }
            default { "Keep the branch-hosted raw install per the userscript install-posture decision; metadata is complete." }
        }

        $rows.Add([ordered]@{
            repo = [string]$entry.repo
            url = $url
            sourceHost = $source.sourceHost
            sourceRepository = $source.sourceRepository
            sourceRef = $source.sourceRef
            sourceRefType = $source.sourceRefType
            sourcePath = $source.sourcePath
            rawGitHub = [bool]$source.rawGitHub
            fetchSucceeded = [bool]$fetchStatus.succeeded
            fetchStatusCode = $fetchStatus.statusCode
            metadataBlockPresent = [bool]$metadataResult.metadataBlockPresent
            metadataBlockClosed = [bool]$metadataResult.metadataBlockClosed
            name = if ([string]::IsNullOrWhiteSpace($name)) { $null } else { $name }
            version = if ([string]::IsNullOrWhiteSpace($version)) { $null } else { $version }
            updateUrl = if ([string]::IsNullOrWhiteSpace($updateUrl)) { $null } else { $updateUrl }
            downloadUrl = if ([string]::IsNullOrWhiteSpace($downloadUrl)) { $null } else { $downloadUrl }
            updateUrlSourceRef = if ([string]::IsNullOrWhiteSpace([string]$updateUrlTrust.sourceRef)) { $null } else { [string]$updateUrlTrust.sourceRef }
            updateUrlRefMatchesSource = $updateUrlTrust.refMatchesSource
            updateUrlProbeSucceeded = $updateUrlTrust.probeSucceeded
            updateUrlProbeStatusCode = $updateUrlTrust.probeStatusCode
            downloadUrlSourceRef = if ([string]::IsNullOrWhiteSpace([string]$downloadUrlTrust.sourceRef)) { $null } else { [string]$downloadUrlTrust.sourceRef }
            downloadUrlRefMatchesSource = $downloadUrlTrust.refMatchesSource
            downloadUrlProbeSucceeded = $downloadUrlTrust.probeSucceeded
            downloadUrlProbeStatusCode = $downloadUrlTrust.probeStatusCode
            matchCount = $matchValues.Count
            includeCount = $includes.Count
            grantCount = $grants.Count
            connectCount = $connects.Count
            requireCount = $requires.Count
            broadScope = [bool]($broadScopes.Count -gt 0)
            releaseChannelReadiness = $releaseChannelReadiness
            releaseChannelNextAction = $releaseChannelNextAction
            releaseChannelEvidence = [ordered]@{
                metadataComplete = [bool]$metadataComplete
                sourceRefType = if ([string]::IsNullOrWhiteSpace($sourceRefType)) { $null } else { $sourceRefType }
                hasVersion = [bool](-not [string]::IsNullOrWhiteSpace($version))
                updateUrlAligned = [bool]$updateUrlAligned
            }
            warningCount = $warnings.Count
            fatalCount = $rowFatalCount
            warnings = $warnings.ToArray()
        })
    }

    $rowArray = @($rows.ToArray())
    $warningTotal = 0
    $fatalTotal = 0
    foreach ($row in $rowArray) {
        $warningTotal += [int]$row.warningCount
        $fatalTotal += [int]$row.fatalCount
    }

    return [ordered]@{
        skipped = $false
        skipReason = $null
        checkedCount = $rowArray.Count
        installActionCount = $userscriptEntries.Count
        rawGitHubCount = @($rowArray | Where-Object { $_.rawGitHub }).Count
        branchSourceCount = @($rowArray | Where-Object { $_.sourceRefType -eq "branch" }).Count
        tagOrCommitSourceCount = @($rowArray | Where-Object { $_.sourceRefType -in @("tag", "commit") }).Count
        metadataBlockCount = @($rowArray | Where-Object { $_.metadataBlockPresent }).Count
        missingMetadataBlockCount = @($rowArray | Where-Object { -not $_.metadataBlockPresent }).Count
        missingVersionCount = @($rowArray | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.version) }).Count
        missingUpdateUrlCount = @($rowArray | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.updateUrl) }).Count
        missingDownloadUrlCount = @($rowArray | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.downloadUrl) }).Count
        updateUrlProbeFailureCount = @($rowArray | Where-Object { $null -ne $_.updateUrlProbeSucceeded -and -not $_.updateUrlProbeSucceeded }).Count
        downloadUrlProbeFailureCount = @($rowArray | Where-Object { $null -ne $_.downloadUrlProbeSucceeded -and -not $_.downloadUrlProbeSucceeded }).Count
        updateUrlRefMismatchCount = @($rowArray | Where-Object { $null -ne $_.updateUrlRefMatchesSource -and -not $_.updateUrlRefMatchesSource }).Count
        downloadUrlRefMismatchCount = @($rowArray | Where-Object { $null -ne $_.downloadUrlRefMatchesSource -and -not $_.downloadUrlRefMatchesSource }).Count
        broadScopeCount = @($rowArray | Where-Object { $_.broadScope }).Count
        releaseChannelReadyCount = @($rowArray | Where-Object { $_.releaseChannelReadiness -eq "ready" }).Count
        releaseChannelKeepBranchCount = @($rowArray | Where-Object { $_.releaseChannelReadiness -eq "keep-branch" }).Count
        releaseChannelBlockedCount = @($rowArray | Where-Object { $_.releaseChannelReadiness -eq "blocked" }).Count
        warningCount = [int]$warningTotal
        fatalCount = [int]$fatalTotal
        rows = $rowArray
        note = "Userscript metadata inspection parses raw .user.js headers only; script bodies are not executed."
    }
}

function Test-BranchTipProvenance {
    <#
    .SYNOPSIS
    Reports branch-tip freshness for catalog entries with clone/install actions.
    .DESCRIPTION
    The README continues to use the advertised branch so visitors receive the repository's
    current install path. This report adds the observed tip SHA and warning-only freshness /
    reachability evidence for consumers that need to verify what that branch pointed to.
    .PARAMETER Entries
    Normalized catalog entries.
    .PARAMETER RepoLookup
    Repository metadata keyed by repository name.
    .PARAMETER Now
    Clock value used to classify previously fetched evidence as stale.
    .PARAMETER StaleAfterHours
    Maximum age before branch-tip evidence is warning-only stale.
    #>
    [CmdletBinding()]
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup,
        [datetimeoffset]$Now = [datetimeoffset]::Now,
        [ValidateRange(1, 720)]
        [int]$StaleAfterHours = $BranchTipStaleAfterHours
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $statusCounts = @{
        fresh = 0
        stale = 0
        unreachable = 0
        missing = 0
    }

    foreach ($entry in @($Entries | Sort-Object category, repo)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.entrypoint)) {
            continue
        }

        $meta = Get-RepoMeta $entry $RepoLookup
        $branch = Get-Branch $entry $meta
        $evidence = Get-BranchTipActionEvidence -Entry $entry -Meta $meta
        if ($evidence.status -eq "fresh" -and -not [string]::IsNullOrWhiteSpace([string]$evidence.fetchedAt)) {
            try {
                $ageHours = ($Now - [datetimeoffset]::Parse([string]$evidence.fetchedAt)).TotalHours
                if ($ageHours -gt $StaleAfterHours) {
                    $evidence.status = "stale"
                    $evidence.warning = "Branch-tip evidence is $([math]::Round($ageHours, 1)) hour(s) old."
                }
            } catch {
                $evidence.status = "stale"
                $evidence.warning = "Branch-tip evidence has an invalid fetched-at timestamp."
            }
        }
        $status = [string]$evidence.status
        if ($status -eq "not-applicable") {
            $status = "unreachable"
        }
        if (-not $statusCounts.ContainsKey($status)) {
            $status = "unreachable"
        }
        $statusCounts[$status] = [int]$statusCounts[$status] + 1
        $rows.Add([ordered]@{
            repo = [string]$entry.repo
            branch = $branch
            branchTipSha = $evidence.sha
            branchTipFetchedAt = $evidence.fetchedAt
            status = $status
            warning = $evidence.warning
        })
    }

    $warningCount = @($rows | Where-Object { $_.status -ne "fresh" }).Count
    return [ordered]@{
        status = if ($warningCount -gt 0) { "warning" } else { "ok" }
        checkedInstallActionCount = $rows.Count
        staleAfterHours = [int]$StaleAfterHours
        freshCount = [int]$statusCounts.fresh
        staleCount = [int]$statusCounts.stale
        unreachableCount = [int]$statusCounts.unreachable
        missingCount = [int]$statusCounts.missing
        warningCount = [int]$warningCount
        statusCounts = @($statusCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { [ordered]@{ kind = [string]$_.Name; count = [int]$_.Value } })
        rows = $rows.ToArray()
        note = "Branch-current clone/install snippets remain the README default. Tip SHA and fetched-at fields are warning-only verification evidence; stale or unreachable branch metadata never rewrites a visitor-facing branch or blocks generation."
    }
}
