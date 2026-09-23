# Link validation: collecting catalog, header and README action targets, resolving
# local anchors, probing targets in parallel through the safe-outbound policy with a
# status-aware cache, and URL scheme checks. Dot-sourced by scripts/sync-profile.ps1.

function Get-LinkCacheTtlHours {
    <#
    .SYNOPSIS
    How long a link result of a given status may be reused.
    .DESCRIPTION
    One flat TTL treated a corrected 404 and a transient 429 exactly like a healthy
    200, so a fixed link stayed broken for a day and a rate-limited host stayed
    "failed" without ever being retried. Successes hold for the configured window,
    definitive dead links for an hour, and transient failures are never reused across
    runs because the next run is exactly when they should be retried.
    #>
    param(
        [AllowNull()][object]$Status,
        [bool]$Ok,
        [int]$SuccessTtlHours = $script:CacheTtlHours,
        [int]$DeadLinkTtlHours = 1
    )

    if ($Ok) { return [int]$SuccessTtlHours }
    $statusCode = 0
    if ($null -ne $Status -and [int]::TryParse([string]$Status, [ref]$statusCode)) {
        if ($statusCode -eq 404 -or $statusCode -eq 410) { return [int]$DeadLinkTtlHours }
    }
    return 0
}

function Get-RetryAfterSeconds {
    <#
    .SYNOPSIS
    Parses a Retry-After header, capping how long this run will defer a target.
    .DESCRIPTION
    RFC 9110 section 10.2.3 allows delta-seconds or an HTTP-date. A server can name
    hours; a local validation run must not sleep that long, so the wait is capped and
    the real retry time is reported instead.
    #>
    param(
        [AllowNull()][object]$RetryAfter,
        [int]$CapSeconds = 60,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )

    if ($null -eq $RetryAfter) { return $null }
    $text = ([string]$RetryAfter).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $seconds = $null
    $delta = 0
    if ([int]::TryParse($text, [ref]$delta)) {
        $seconds = $delta
    } else {
        $when = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$when)) {
            $seconds = [int][math]::Ceiling(($when.ToUniversalTime() - $Now.ToUniversalTime()).TotalSeconds)
        }
    }
    if ($null -eq $seconds) { return $null }
    if ($seconds -lt 0) { $seconds = 0 }

    return [ordered]@{
        requestedSeconds = [int]$seconds
        waitSeconds = [int][math]::Min($seconds, $CapSeconds)
        retryAfterUtc = $Now.ToUniversalTime().AddSeconds($seconds).ToString('o')
        capped = [bool]($seconds -gt $CapSeconds)
    }
}

function Test-HttpUrl {
    param(
        [string]$Url,
        [int]$TimeoutSec = 12,
        [int]$Retries = 2,
        [AllowNull()][string]$IfNoneMatch,
        [AllowNull()][string]$IfModifiedSince
    )

    # Returns ok/status/error plus a `fatal` flag. Only a definitive dead-link
    # response (404/410) is fatal; transient blocks (403/429/5xx/timeout) are
    # reported as non-fatal warnings so a flaky host does not fail the whole gate.
    # The shared safe-outbound request path reads headers only, so GET fallback
    # proves reachability without downloading release assets or raw file bodies.
    $status = $null
    $err = $null
    $etag = $null
    $lastModified = $null
    $retry = $null

    # Stored validators turn a stale entry into a cheap revalidation instead of a
    # full re-probe: a 304 means the previous answer still stands.
    $conditionalHeaders = @{}
    if (-not [string]::IsNullOrWhiteSpace($IfNoneMatch)) { $conditionalHeaders['If-None-Match'] = $IfNoneMatch }
    if (-not [string]::IsNullOrWhiteSpace($IfModifiedSince)) { $conditionalHeaders['If-Modified-Since'] = $IfModifiedSince }

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        foreach ($methodName in @('Head', 'Get')) {
            $result = Invoke-SafeOutboundHttpRequest `
                -Url $Url `
                -Method $methodName `
                -TimeoutSec $TimeoutSec `
                -MaxRedirects 5 `
                -UserAgent 'SysAdminDoc-profile-link-validator' `
                -Accept '*/*' `
                -Headers $conditionalHeaders
            $status = $result.statusCode
            $err = $result.error
            $etag = Get-MemberValue -Object $result -Name 'etag'
            $lastModified = Get-MemberValue -Object $result -Name 'lastModified'
            $retry = Get-RetryAfterSeconds -RetryAfter (Get-MemberValue -Object $result -Name 'retryAfter')
            if ($status -eq 304) {
                # Not modified: the cached answer is still current.
                return [ordered]@{ ok = $true; status = 304; error = $null; fatal = $false; notModified = $true; etag = $etag; lastModified = $lastModified; retryAfter = $null }
            }
            if ($result.ok) {
                return [ordered]@{ ok = $true; status = $status; error = $null; fatal = $false; notModified = $false; etag = $etag; lastModified = $lastModified; retryAfter = $null }
            }
            if ($result.policyBlocked -or $status -eq 404 -or $status -eq 410) {
                return [ordered]@{ ok = $false; status = $status; error = $err; fatal = $true; notModified = $false; etag = $etag; lastModified = $lastModified; retryAfter = $null }
            }
        }
        if ($attempt -lt $Retries) {
            # Honour a server-directed wait, but never sleep longer than the local cap;
            # the real retry time is reported instead.
            $waitSeconds = $attempt
            if ($null -ne $retry) { $waitSeconds = [int]$retry.waitSeconds }
            if ($waitSeconds -gt 0) { Start-Sleep -Seconds $waitSeconds }
        }
    }

    return [ordered]@{ ok = $false; status = $status; error = $err; fatal = $false; notModified = $false; etag = $etag; lastModified = $lastModified; retryAfter = $retry }
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
        [string]$Url,
        [string]$Repo = $null,
        [bool]$FatalOnFailure = $true,
        [string]$Group = "catalog"
    )

    $targetRepo = if (-not [string]::IsNullOrWhiteSpace($Repo)) {
        $Repo
    } elseif ($Entry -and -not [string]::IsNullOrWhiteSpace([string]$Entry.repo)) {
        [string]$Entry.repo
    } else {
        $Owner
    }

    return [ordered]@{
        repo = $targetRepo
        type = $Type
        url = $Url
        host = Get-LinkHost $Url
        fatalOnFailure = [bool]$FatalOnFailure
        group = $Group
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

        $action = Get-PrimaryAction $entry $meta $entry.category
        if ($action["kind"] -eq "release") {
            $targets.Add((New-LinkValidationTarget -Entry $entry -Type "release" -Url ([string]$action["url"])))
        }
    }

    return $targets.ToArray()
}

function Add-LinkValidationTarget {
    param(
        [System.Collections.Generic.List[object]]$Targets,
        [System.Collections.Generic.HashSet[string]]$SeenUrls,
        [string]$Type,
        [string]$Url,
        [bool]$FatalOnFailure,
        [string]$Group = "readme-header"
    )

    if ([string]::IsNullOrWhiteSpace($Url) -or -not $Url.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    if ($SeenUrls.Add($Url)) {
        $Targets.Add((New-LinkValidationTarget -Repo $Owner -Type $Type -Url $Url -FatalOnFailure $FatalOnFailure -Group $Group))
    }
}

function Get-ReadmeHeaderRegion {
    <#
    .SYNOPSIS
    Returns the hand-authored part of the README, above the generated-catalog notice.
    #>
    param([string]$ExpectedReadme)

    if ([string]::IsNullOrEmpty($ExpectedReadme)) {
        return ""
    }
    $boundary = $ExpectedReadme.IndexOf($GeneratedCatalogNotice, [StringComparison]::Ordinal)
    if ($boundary -lt 0) {
        return $ExpectedReadme
    }
    return $ExpectedReadme.Substring(0, $boundary)
}

function Get-ReadmeHeaderLinkReference {
    <#
    .SYNOPSIS
    Enumerates every hand-authored link reference above the generated-catalog notice.
    .DESCRIPTION
    Recognizing three known URLs meant an arbitrary hand-written call to action could
    die without failing the link check, which is how a dead services link shipped.
    Collects Markdown links and images, HTML href/src/srcset, and local fragments.
    #>
    param([string]$ExpectedReadme)

    $header = Get-ReadmeHeaderRegion -ExpectedReadme $ExpectedReadme
    $references = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($header)) {
        return $references.ToArray()
    }

    $add = {
        param([string]$Kind, [string]$Value)
        $trimmed = ([string]$Value).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { return }
        $references.Add([ordered]@{ kind = $Kind; value = $trimmed })
    }

    # Markdown images first so the link pattern does not claim them.
    foreach ($match in [regex]::Matches($header, '!\[[^\]]*\]\(\s*(?<url>[^\s)]+)')) {
        & $add "image" $match.Groups['url'].Value
    }
    foreach ($match in [regex]::Matches($header, '(?<![!])\[[^\]]*\]\(\s*(?<url>[^\s)]+)')) {
        & $add "link" $match.Groups['url'].Value
    }
    foreach ($match in [regex]::Matches($header, '(?i)\bhref\s*=\s*"(?<url>[^"]*)"')) {
        & $add "link" $match.Groups['url'].Value
    }
    foreach ($match in [regex]::Matches($header, '(?i)\bsrc\s*=\s*"(?<url>[^"]*)"')) {
        & $add "image" $match.Groups['url'].Value
    }
    # srcset is a comma-separated candidate list, each optionally followed by a descriptor.
    foreach ($match in [regex]::Matches($header, '(?i)\bsrcset\s*=\s*"(?<set>[^"]*)"')) {
        foreach ($candidate in @($match.Groups['set'].Value -split ',')) {
            & $add "image" (@($candidate.Trim() -split '\s+')[0])
        }
    }

    return $references.ToArray()
}

function Get-ReadmeHeaderLinkValidationTargets {
    param([string]$ExpectedReadme)

    $targets = New-Object System.Collections.Generic.List[object]
    $seenUrls = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # These three carry the profile's call to action and install path, so a failure is
    # fatal rather than a warning even though every header link is now probed.
    $criticalUrls = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $criticalLinks = @(
        [ordered]@{ type = "profile-portfolio"; url = Get-ProfilePortfolioUrl },
        [ordered]@{ type = "setup-raw"; url = Get-ProfileSetupRawUrl },
        [ordered]@{ type = "setup-source"; url = Get-ProfileSetupSourceUrl }
    )
    foreach ($link in $criticalLinks) {
        $null = $criticalUrls.Add([string]$link.url)
        if ($ExpectedReadme.Contains([string]$link.url)) {
            Add-LinkValidationTarget -Targets $targets -SeenUrls $seenUrls -Type ([string]$link.type) -Url ([string]$link.url) -FatalOnFailure $true
        }
    }

    foreach ($reference in @(Get-ReadmeHeaderLinkReference -ExpectedReadme $ExpectedReadme)) {
        $url = [string]$reference.value
        if (-not $url.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($criticalUrls.Contains($url)) {
            continue
        }
        # A hand-authored destination that no longer resolves is a broken promise to a
        # visitor, so it fails the run. Images stay warning-only: a slow badge host is
        # not a broken profile.
        $type = if ($reference.kind -eq "image") { "header-image" } else { "header-link" }
        Add-LinkValidationTarget -Targets $targets -SeenUrls $seenUrls -Type $type -Url $url -FatalOnFailure ($reference.kind -ne "image")
    }

    return $targets.ToArray()
}

function Test-ReadmeHeaderAnchor {
    <#
    .SYNOPSIS
    Verifies every hand-authored local fragment resolves inside the generated README.
    .DESCRIPTION
    Runs without network access. GitHub derives heading anchors by lowercasing, dropping
    punctuation and joining words with hyphens; the generator also emits explicit
    <a id="..."> anchors, which are matched directly.
    #>
    param([string]$ExpectedReadme)

    $missing = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($ExpectedReadme)) {
        return $missing.ToArray()
    }

    $anchors = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches($ExpectedReadme, '(?i)<a\s+id="(?<id>[^"]+)"')) {
        $null = $anchors.Add($match.Groups['id'].Value)
    }
    foreach ($match in [regex]::Matches($ExpectedReadme, '(?i)\bname\s*=\s*"(?<id>[^"]+)"')) {
        $null = $anchors.Add($match.Groups['id'].Value)
    }
    foreach ($match in [regex]::Matches($ExpectedReadme, '(?m)^\s{0,3}#{1,6}\s+(?<text>.+?)\s*$')) {
        $slug = ConvertTo-GitHubHeadingAnchor -Text $match.Groups['text'].Value
        if (-not [string]::IsNullOrWhiteSpace($slug)) {
            $null = $anchors.Add($slug)
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($reference in @(Get-ReadmeHeaderLinkReference -ExpectedReadme $ExpectedReadme)) {
        $value = [string]$reference.value
        if (-not $value.StartsWith("#", [StringComparison]::Ordinal)) {
            continue
        }
        $fragment = $value.Substring(1)
        if ([string]::IsNullOrWhiteSpace($fragment) -or -not $seen.Add($fragment)) {
            continue
        }
        if (-not $anchors.Contains($fragment)) {
            $missing.Add([ordered]@{
                fragment = $fragment
                kind = [string]$reference.kind
                reason = "No heading or explicit anchor in the generated README matches #$fragment."
            })
        }
    }

    return $missing.ToArray()
}

function ConvertTo-GitHubHeadingAnchor {
    <#
    .SYNOPSIS
    Reproduces GitHub's heading-to-anchor slug rules for local fragment checks.
    #>
    param([string]$Text)

    $value = [string]$Text
    # Strip inline HTML and Markdown emphasis/link syntax before slugging, matching how
    # GitHub slugs the rendered heading text rather than the raw source.
    $value = [regex]::Replace($value, '<[^>]+>', '')
    $value = [regex]::Replace($value, '!?\[(?<text>[^\]]*)\]\([^)]*\)', '${text}')
    $value = [regex]::Replace($value, '[`*_~]', '')
    $value = $value.Trim().ToLowerInvariant()
    $value = [regex]::Replace($value, '[^\p{L}\p{Nd}\s-]', '')
    # Each whitespace character becomes its own hyphen. GitHub does not collapse runs,
    # which is why a heading containing "&" yields a double hyphen once the "&" is
    # dropped and both surrounding spaces survive.
    $value = [regex]::Replace($value, '\s', '-')
    return $value
}

function Get-ReadmeActionRepoFromUrl {
    param([string]$Url)

    try {
        $uri = [Uri]$Url
        $segments = @($uri.AbsolutePath.Trim('/') -split '/')
        if ($segments.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($segments[1])) {
            return [Uri]::UnescapeDataString($segments[1])
        }
    } catch {
        return $Owner
    }

    return $Owner
}

function Add-ReadmeActionLinkValidationTarget {
    param(
        [System.Collections.Generic.List[object]]$Targets,
        [System.Collections.Generic.HashSet[string]]$SeenTargets,
        [string]$Type,
        [string]$Url,
        [string]$Repo = $null
    )

    if ([string]::IsNullOrWhiteSpace($Url) -or -not $Url.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $targetKey = "$Type`n$Url"
    if (-not $SeenTargets.Add($targetKey)) {
        return
    }

    $targetRepo = if ([string]::IsNullOrWhiteSpace($Repo)) { Get-ReadmeActionRepoFromUrl -Url $Url } else { $Repo }
    $Targets.Add((New-LinkValidationTarget -Repo $targetRepo -Type $Type -Url $Url -FatalOnFailure $true -Group "readme-actions"))
}

function Get-ReadmeActionLinkValidationTargets {
    param([string]$ExpectedReadme)

    $targets = New-Object System.Collections.Generic.List[object]
    $seenTargets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($block in [regex]::Matches($ExpectedReadme, '(?ms)```(?:powershell|pwsh|ps1)?\s*(?<script>.*?)```')) {
        $scriptText = $block.Groups['script'].Value
        $cloneMatch = [regex]::Match($scriptText, 'git clone -q --depth 1 -b (?<branch>[^\s;]+) https://github\.com/(?<owner>[^/\s;]+)/(?<repo>[^\s;]+) \$d')
        $runnerMatch = [regex]::Match($scriptText, '(?:^|;)\s*(?:&|python)\s+"\$d\\(?<entry>[^"]+)"')
        if (-not $cloneMatch.Success -or -not $runnerMatch.Success) {
            continue
        }

        $cloneOwner = $cloneMatch.Groups['owner'].Value
        $repo = $cloneMatch.Groups['repo'].Value
        $branch = $cloneMatch.Groups['branch'].Value
        $entrypoint = $runnerMatch.Groups['entry'].Value
        $rawUrl = ConvertTo-RawGitHubUrl -RepositoryOwner $cloneOwner -Repo $repo -Branch $branch -Path $entrypoint
        Add-ReadmeActionLinkValidationTarget -Targets $targets -SeenTargets $seenTargets -Type "readme-install-entrypoint" -Url $rawUrl -Repo $repo
    }

    foreach ($match in [regex]::Matches($ExpectedReadme, '(?i)\]\((?<url>https://github\.com/[^)\s]+/releases/latest)\)')) {
        Add-ReadmeActionLinkValidationTarget -Targets $targets -SeenTargets $seenTargets -Type "readme-download" -Url $match.Groups['url'].Value
    }

    foreach ($match in [regex]::Matches($ExpectedReadme, '(?i)\[Install\]\((?<url>https://raw\.githubusercontent\.com/[^)\s]+)\)')) {
        Add-ReadmeActionLinkValidationTarget -Targets $targets -SeenTargets $seenTargets -Type "readme-userscript-install" -Url $match.Groups['url'].Value
    }

    return $targets.ToArray()
}

function Set-LinkProbeCacheContext {
    <#
    .SYNOPSIS
    Attaches any cached probe and its validators to a target, and says whether the
    cached verdict may be reused as-is.
    .DESCRIPTION
    Shared by the live and injected probe paths so both make the same reuse decision
    and both carry stored ETag / Last-Modified values into the request. Returns $true
    when the cached answer is still within the lifetime its own status earns.
    #>
    param([object]$Target)

    $cacheEntry = Read-ValidationCacheEntry -Bucket links -Key (Get-LinkProbeCacheKey -Url ([string](Get-MemberValue -Object $Target -Name 'url'))) -IncludeStale -NoCounters
    $cachedProbe = if ($null -ne $cacheEntry) { Get-MemberValue -Object $cacheEntry -Name 'value' } else { $null }
    $reusable = $false
    if ($null -ne $cachedProbe) {
        $allowedTtl = Get-LinkCacheTtlHours -Status (Get-MemberValue -Object $cachedProbe -Name 'status') -Ok ([bool](Get-MemberValue -Object $cachedProbe -Name 'ok'))
        $entryAge = [double](Get-MemberValue -Object $cacheEntry -Name 'ageHours')
        $reusable = ($allowedTtl -gt 0 -and $entryAge -le $allowedTtl)
    }
    if ($null -ne $cacheEntry) {
        Set-MemberValue -Object $Target -Name 'ifNoneMatch' -Value (Get-MemberValue -Object $cacheEntry -Name 'etag')
        Set-MemberValue -Object $Target -Name 'ifModifiedSince' -Value (Get-MemberValue -Object $cacheEntry -Name 'lastModified')
        Set-MemberValue -Object $Target -Name 'cachedProbe' -Value $cachedProbe
    }
    return [bool]$reusable
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
    $deferred = New-Object System.Collections.Generic.List[object]

    if ($targetList.Count -eq 0) {
        $stopwatch.Stop()
        return [ordered]@{
            results = @()
            deferredRetries = @()
            targetCount = 0
            liveProbedCount = 0
            cacheServedCount = 0
            oldestCacheEntryAgeHours = $null
            allResultsFromCache = $false
            throttleLimit = $throttle
            elapsedMs = $stopwatch.ElapsedMilliseconds
        }
    }

    if ($ProbeScript) {
        # Runs the same cache read and reuse decision as the live path, so an injected
        # probe exercises validator attachment rather than a shortcut around it.
        $probeTargets = New-Object System.Collections.Generic.List[object]
        foreach ($target in $targetList) {
            $null = Set-LinkProbeCacheContext -Target $target
            $probeTargets.Add($target)
        }
        $probeRows = foreach ($target in $probeTargets) {
            $result = & $ProbeScript $target
            $targetFatalOnFailure = if ($target -is [System.Collections.IDictionary] -and $target.Contains('fatalOnFailure')) {
                [bool]$target['fatalOnFailure']
            } elseif ($target.PSObject.Properties.Name -contains 'fatalOnFailure') {
                [bool]$target.fatalOnFailure
            } else {
                $true
            }
            [ordered]@{
                repo = $target.repo
                type = $target.type
                url = $target.url
                host = $target.host
                ok = [bool]$result.ok
                status = $result.status
                error = $result.error
                probeFatal = [bool]$result.fatal
                fatal = [bool]($targetFatalOnFailure -and [bool]$result.fatal)
                # Same row shape as the live branch below. A test lane that produces
                # different fields tests a different code path than production.
                notModified = [bool](Get-MemberValue -Object $result -Name 'notModified')
                etag = Get-MemberValue -Object $result -Name 'etag'
                lastModified = Get-MemberValue -Object $result -Name 'lastModified'
                retryAfterUtc = [string](Get-MemberValue -Object (Get-MemberValue -Object $result -Name 'retryAfter') -Name 'retryAfterUtc')
            }
        }
        $liveProbedCount = @($probeRows).Count
        $cacheServedCount = 0
    } else {
        $cachedRows = New-Object System.Collections.Generic.List[object]
        $uncachedTargets = New-Object System.Collections.Generic.List[object]
        foreach ($target in $targetList) {
            $reusable = Set-LinkProbeCacheContext -Target $target
            $cachedProbe = Get-MemberValue -Object $target -Name 'cachedProbe'
            $cacheEntry = if ($null -ne $cachedProbe) { $cachedProbe } else { $null }
            # Count the decision, not the raw TTL: a 404 or 429 that gets re-probed is
            # not a cache hit, however recently it was written.
            if ($reusable) {
                Add-ValidationCacheCounter -Bucket links -Counter hitCount
            } elseif ($null -ne $cacheEntry) {
                Add-ValidationCacheCounter -Bucket links -Counter staleCount
            } else {
                Add-ValidationCacheCounter -Bucket links -Counter missCount
            }
            if (-not $reusable) {
                # Validators are already attached by Set-LinkProbeCacheContext.
                $uncachedTargets.Add($target)
                continue
            }

            $targetFatalOnFailure = if ($target -is [System.Collections.IDictionary] -and $target.Contains('fatalOnFailure')) {
                [bool]$target['fatalOnFailure']
            } elseif ($target.PSObject.Properties.Name -contains 'fatalOnFailure') {
                [bool]$target.fatalOnFailure
            } else {
                $true
            }
            $cachedRows.Add([ordered]@{
                repo = $target.repo
                type = $target.type
                url = $target.url
                host = $target.host
                ok = [bool](Get-MemberValue -Object $cachedProbe -Name 'ok')
                status = Get-MemberValue -Object $cachedProbe -Name 'status'
                error = Get-MemberValue -Object $cachedProbe -Name 'error'
                probeFatal = [bool](Get-MemberValue -Object $cachedProbe -Name 'fatal')
                fatal = [bool]($targetFatalOnFailure -and [bool](Get-MemberValue -Object $cachedProbe -Name 'fatal'))
            })
        }

        # Compile the pinned transport once in the parent runspace before the
        # parallel workers inherit the function definitions.
        Initialize-SafeOutboundTransport
        $testPublicIpAddressDefinition = ${function:Test-PublicIPAddress}.ToString()
        $resolveSafeOutboundDestinationDefinition = ${function:Resolve-SafeOutboundDestination}.ToString()
        $initializeSafeOutboundTransportDefinition = ${function:Initialize-SafeOutboundTransport}.ToString()
        $invokeSafeOutboundHttpHopDefinition = ${function:Invoke-SafeOutboundHttpHop}.ToString()
        $invokeSafeOutboundHttpRequestDefinition = ${function:Invoke-SafeOutboundHttpRequest}.ToString()
        $getMemberValueDefinition = ${function:Get-MemberValue}.ToString()
        $testHttpUrlDefinition = ${function:Test-HttpUrl}.ToString()
        $getRetryAfterSecondsDefinition = ${function:Get-RetryAfterSeconds}.ToString()
        $freshRows = @($uncachedTargets.ToArray() | ForEach-Object -Parallel {
            ${function:Test-PublicIPAddress} = $using:testPublicIpAddressDefinition
            ${function:Resolve-SafeOutboundDestination} = $using:resolveSafeOutboundDestinationDefinition
            ${function:Initialize-SafeOutboundTransport} = $using:initializeSafeOutboundTransportDefinition
            ${function:Invoke-SafeOutboundHttpHop} = $using:invokeSafeOutboundHttpHopDefinition
            ${function:Invoke-SafeOutboundHttpRequest} = $using:invokeSafeOutboundHttpRequestDefinition
            ${function:Get-MemberValue} = $using:getMemberValueDefinition
            ${function:Test-HttpUrl} = $using:testHttpUrlDefinition
            ${function:Get-RetryAfterSeconds} = $using:getRetryAfterSecondsDefinition
            $target = $_
            # Targets are [ordered] dictionaries, whose PSObject.Properties lists Count,
            # Keys and Values rather than the entries, so a PSObject guard here silently
            # never found the validators and no conditional header was ever sent.
            $ifNoneMatch = [string](Get-MemberValue -Object $target -Name 'ifNoneMatch')
            $ifModifiedSince = [string](Get-MemberValue -Object $target -Name 'ifModifiedSince')
            $result = Test-HttpUrl -Url $target.url -IfNoneMatch $ifNoneMatch -IfModifiedSince $ifModifiedSince
            $cachedProbe = Get-MemberValue -Object $target -Name 'cachedProbe'
            if ($result.status -eq 304 -and $null -ne $cachedProbe) {
                # 304 means the stored answer still holds; keep it and refresh its age.
                $result = [ordered]@{
                    ok = [bool]$cachedProbe.ok
                    status = $cachedProbe.status
                    error = $cachedProbe.error
                    fatal = [bool]$cachedProbe.fatal
                    notModified = $true
                    etag = $result.etag
                    lastModified = $result.lastModified
                    retryAfter = $null
                }
            }
            $targetFatalOnFailure = if ($target -is [System.Collections.IDictionary] -and $target.Contains('fatalOnFailure')) {
                [bool]$target['fatalOnFailure']
            } elseif ($target.PSObject.Properties.Name -contains 'fatalOnFailure') {
                [bool]$target.fatalOnFailure
            } else {
                $true
            }
            [ordered]@{
                repo = $target.repo
                type = $target.type
                url = $target.url
                host = $target.host
                ok = [bool]$result.ok
                status = $result.status
                error = $result.error
                probeFatal = [bool]$result.fatal
                fatal = [bool]($targetFatalOnFailure -and [bool]$result.fatal)
                # Test-HttpUrl also returns an [ordered] dictionary, so the same guard
                # discarded every validator and the cache was written with empty ones.
                notModified = [bool](Get-MemberValue -Object $result -Name 'notModified')
                etag = Get-MemberValue -Object $result -Name 'etag'
                lastModified = Get-MemberValue -Object $result -Name 'lastModified'
                retryAfterUtc = [string](Get-MemberValue -Object (Get-MemberValue -Object $result -Name 'retryAfter') -Name 'retryAfterUtc')
            }
        } -ThrottleLimit $throttle)

        foreach ($row in @($freshRows)) {
            # Transient failures get a zero TTL, so writing them still records the
            # validators without letting the next run reuse the verdict.
            Write-ValidationCacheEntry -Bucket links -Key (Get-LinkProbeCacheKey -Url ([string]$row.url)) -Value ([ordered]@{
                    ok = [bool]$row.ok
                    status = $row.status
                    error = $row.error
                    fatal = [bool]$row.probeFatal
                }) -Headers @{
                    'ETag' = [string]$row.etag
                    'Last-Modified' = [string]$row.lastModified
                }
        }


        $probeRows = @($cachedRows.ToArray() + $freshRows)
        $liveProbedCount = @($freshRows).Count
        $cacheServedCount = $cachedRows.Count
    }

    $oldestCacheAgeHours = $null
    foreach ($target in $targetList) {
        $cachedProbe = Get-MemberValue -Object $target -Name 'cachedProbe'
        if ($null -eq $cachedProbe) { continue }
        $entry = Read-ValidationCacheEntry -Bucket links -Key (Get-LinkProbeCacheKey -Url ([string](Get-MemberValue -Object $target -Name 'url'))) -IncludeStale -NoCounters
        if ($null -ne $entry) {
            $age = [double](Get-MemberValue -Object $entry -Name 'ageHours')
            if ($null -eq $oldestCacheAgeHours -or $age -gt $oldestCacheAgeHours) {
                $oldestCacheAgeHours = $age
            }
        }
    }

    # A server-directed retry longer than the local cap is reported rather than slept
    # through, so the run says when each deferred target may be probed again. Collected
    # from the rows themselves so both the live and the injected probe path report it.
    foreach ($row in @($probeRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $_ -Name 'retryAfterUtc')) })) {
        $deferred.Add([ordered]@{
            url = [string](Get-MemberValue -Object $row -Name 'url')
            host = Get-MemberValue -Object $row -Name 'host'
            status = Get-MemberValue -Object $row -Name 'status'
            retryAfterUtc = [string](Get-MemberValue -Object $row -Name 'retryAfterUtc')
        })
    }

    $stopwatch.Stop()
    return [ordered]@{
        results = @($probeRows)
        deferredRetries = @($deferred.ToArray())
        targetCount = $targetList.Count
        liveProbedCount = [int]$liveProbedCount
        cacheServedCount = [int]$cacheServedCount
        oldestCacheEntryAgeHours = if ($null -ne $oldestCacheAgeHours) { [math]::Round($oldestCacheAgeHours, 2) } else { $null }
        allResultsFromCache = [bool]($targetList.Count -gt 0 -and [int]$liveProbedCount -eq 0)
        throttleLimit = $throttle
        elapsedMs = $stopwatch.ElapsedMilliseconds
    }
}

function Test-LinkTargets {
    param(
        [hashtable[]]$Included,
        [hashtable]$RepoLookup,
        [object[]]$ExtraTargets = @(),
        [int]$ThrottleLimit = $LinkValidationThrottle,
        [scriptblock]$ProbeScript = $null
    )

    $targets = @((Get-LinkValidationTargets -Included $Included -RepoLookup $RepoLookup) + @($ExtraTargets))
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
    $headerHostWarnings = @(
        $warnings |
            Where-Object { $_.type -eq "header-image" } |
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
        headerHostWarnings = $headerHostWarnings
        targetCount = $probeBatch.targetCount
        liveProbedCount = [int]$probeBatch.liveProbedCount
        cacheServedCount = [int]$probeBatch.cacheServedCount
        oldestCacheEntryAgeHours = $probeBatch.oldestCacheEntryAgeHours
        allResultsFromCache = [bool]$probeBatch.allResultsFromCache
        throttleLimit = $probeBatch.throttleLimit
        elapsedMs = $probeBatch.elapsedMs
        deferredRetries = @(Get-MemberValue -Object $probeBatch -Name 'deferredRetries')
    }
}

function Test-UrlScheme {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $true }
    try {
        $uri = [System.Uri]::new($Url)
        return $uri.Scheme -eq 'https'
    } catch {
        return $false
    }
}

function Test-CatalogUrlSchemes {
    param([hashtable[]]$Entries)

    $violations = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Entries) {
        foreach ($field in @('liveUrl', 'userscriptUrl')) {
            $url = [string]$entry[$field]
            if (-not [string]::IsNullOrWhiteSpace($url) -and -not (Test-UrlScheme $url)) {
                $violations.Add([ordered]@{
                    repo = [string]$entry.repo
                    field = $field
                    url = $url
                    reason = "only https: URLs are allowed in visitor-facing catalog fields"
                })
            }
        }
    }
    return $violations.ToArray()
}
