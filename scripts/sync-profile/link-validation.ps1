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
    The header is read the way GitHub renders it (checked with the /markdown API). In
    Markdown text: links and images, their destinations unescaped (#sec\_tion links
    #sec_tion), and every bare http(s) URL GitHub autolinks, escaped link text such as
    \[docs\](https://x) included. In HTML: href, src and srcset, but only inside a real
    <a>, <img> or <source> tag, so the words href="#x" in a paragraph aren't a link. An
    HTML block is raw: nothing in it is autolinked, and a backslash there is plain text.
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

    # Split HTML blocks from Markdown text where CommonMark does. A line opening with a
    # raw-text tag, a comment, <? or <! starts a block that runs to its closing marker; one
    # opening with a block-level tag starts a block that runs to a blank line; so does a
    # line holding nothing but one complete tag, unless it would interrupt a paragraph.
    $blockTags = 'address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul'
    $attribute = '\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:[^\s"''=<>`]+|''[^'']*''|"[^"]*"))?'
    $htmlBlockStarts = @(
        @{ Start = '(?i)^ {0,3}<(?:pre|script|style|textarea)(?:[\s>]|\z)'; End = '(?i)</(?:pre|script|style|textarea)>' }
        @{ Start = '^ {0,3}<!--'; End = '-->' }
        @{ Start = '^ {0,3}<\?'; End = '\?>' }
        @{ Start = '^ {0,3}<!\[CDATA\['; End = '\]\]>' }
        @{ Start = '^ {0,3}<![A-Za-z]'; End = '>' }
        @{ Start = "(?i)^ {0,3}</?(?:$blockTags)(?:[\s>]|/>|\z)"; End = $null }
    )
    $completeTagLine = "^ {0,3}(?:<[A-Za-z][A-Za-z0-9-]*(?:$attribute)*\s*/?>|</[A-Za-z][A-Za-z0-9-]*\s*>)\s*\z"
    $htmlLines = [System.Collections.Generic.List[string]]::new()
    $markdownLines = [System.Collections.Generic.List[string]]::new()
    $inHtml = $false
    $htmlEnd = $null
    $inParagraph = $false
    # The column an open paragraph's container starts at: 0 at the top, a list item's content
    # column inside one. A line indented less isn't inside that container.
    $paragraphIndent = 0
    $inList = $false
    $listContentIndent = 0
    $fence = $null
    foreach ($line in ($header -split '\r?\n')) {
        $blank = [string]::IsNullOrWhiteSpace($line)
        $lineIndent = 0
        foreach ($character in [regex]::Match($line, '^[ \t]*').Value.ToCharArray()) {
            $lineIndent = if ([int]$character -eq 9) { $lineIndent + 4 - ($lineIndent % 4) } else { $lineIndent + 1 }
        }
        # A fenced code block shows its lines as written, to the closing fence or the end, so
        # nothing in it is a tag, a link or a URL; they're left out of both texts. So is an
        # indented code block, which can't interrupt a paragraph; inside a list item it's
        # indented four past the item's content ("- item" then six spaces).
        if ($null -ne $fence) {
            $close = [regex]::Match($line, '^ {0,3}(?<run>`{3,}|~{3,})[ \t]*\z')
            if ($close.Success -and $close.Groups['run'].Value[0] -eq $fence[0] -and $close.Groups['run'].Value.Length -ge $fence.Length) {
                $fence = $null
            }
            $htmlLines.Add('')
            $markdownLines.Add('')
            continue
        }
        if (-not $inHtml) {
            $open = [regex]::Match($line, '^ {0,3}(?<run>`{3,}|~{3,})(?<info>.*)\z')
            if ($open.Success -and -not ($open.Groups['run'].Value[0] -eq '`' -and $open.Groups['info'].Value.Contains('`'))) {
                $fence = $open.Groups['run'].Value
                $inParagraph = $false
                $htmlLines.Add('')
                $markdownLines.Add('')
                continue
            }
            if (-not $blank -and -not $inParagraph -and $lineIndent -ge (4 + $(if ($inList) { $listContentIndent } else { 0 }))) {
                $htmlLines.Add('')
                $markdownLines.Add('')
                continue
            }
        }
        if (-not $inHtml -and -not $blank) {
            foreach ($start in $htmlBlockStarts) {
                if ($line -match $start.Start) {
                    $inHtml = $true
                    $htmlEnd = $start.End
                    break
                }
            }
            # A lone tag can't interrupt a paragraph from inside the paragraph's container, but
            # it can from outside one: after "- item", "  <a ...>" continues the item's
            # paragraph while an unindented "<a ...>" starts an HTML block, as on GitHub.
            if (-not $inHtml -and -not ($inParagraph -and $lineIndent -ge $paragraphIndent) -and $line -match $completeTagLine) {
                $inHtml = $true
                $htmlEnd = $null
            }
        }
        if ($inHtml -and -not ($blank -and $null -eq $htmlEnd)) {
            $htmlLines.Add($line)
            $markdownLines.Add('')
            if ($null -ne $htmlEnd -and $line -match $htmlEnd) {
                $inHtml = $false
            }
            $inParagraph = $false
            continue
        }
        $inHtml = $false
        # A heading, a rule, a setext underline or a quote line leaves no open paragraph for
        # the next line to join (GitHub starts an HTML block after each); other text opens or
        # continues one. A list item with text opens a paragraph in the item, at the item's
        # content column (after the marker and up to four spaces, or one when more follow).
        # Indented lines after a list item stay in it.
        $listItem = [regex]::Match($line, '^(?<lead> {0,3})(?<marker>[-+*]|[0-9]{1,9}[.)])(?<gap>[ \t]*)(?<rest>.*)\z')
        $isListItem = $listItem.Success -and ($listItem.Groups['gap'].Length -gt 0 -or $listItem.Groups['rest'].Length -eq 0)
        $closesParagraph = $line -match '^ {0,3}(?:#{1,6}(?:[ \t]|\z)|>|(?:\*[ \t]*){3,}\z|(?:-[ \t]*){3,}\z|(?:_[ \t]*){3,}\z)' -or
            ($inParagraph -and $line -match '^ {0,3}(?:=+|-+)[ \t]*\z')
        if (-not $blank) {
            $inList = $isListItem -or ($inList -and $line -match '^(?: {2,}|\t)')
        }
        if ($isListItem -and -not $closesParagraph) {
            $rest = $listItem.Groups['rest'].Value
            $gap = $listItem.Groups['gap'].Length
            $listContentIndent = $listItem.Groups['lead'].Length + $listItem.Groups['marker'].Length + $(if ($rest.Length -eq 0 -or $gap -gt 4) { 1 } else { $gap })
            $paragraphIndent = $listContentIndent
            # Text five or more spaces after the marker is indented code in the item, shown as written.
            $itemCode = $rest.Length -gt 0 -and $gap -gt 4
            $inParagraph = $rest.Length -gt 0 -and -not $itemCode -and $rest -notmatch '^(?:#{1,6}(?:[ \t]|\z)|>|<)'
        } else {
            $itemCode = $false
            $opensParagraph = -not $blank -and -not $closesParagraph -and -not $isListItem
            if ($opensParagraph -and -not $inParagraph) {
                $paragraphIndent = if ($inList -and $lineIndent -ge $listContentIndent) { $listContentIndent } else { 0 }
            }
            $inParagraph = $opensParagraph
        }
        $htmlLines.Add('')
        $markdownLines.Add($(if ($itemCode) { '' } else { $line }))
    }
    $htmlText = $htmlLines -join "`n"
    $markdownText = $markdownLines -join "`n"

    # Markdown text is read one construct at a time, and each one read is blanked so a later
    # pass can't look inside it: code spans, then inline tags, images, links and last the
    # bare URLs. $plain keeps the text as written, $markup has each backslash escape blanked
    # too (a backslash before ASCII punctuation makes it plain text, so "\[x\](y)", which is
    # how ConvertTo-MarkdownText writes brackets from catalog text, is not a link). Blanking
    # writes spaces over the same characters, so offsets line up across the two.
    $plain = $markdownText.ToCharArray()
    $markup = ([regex]::Replace($markdownText, '\\[!-/:-@\[-`{-~]', '  ')).ToCharArray()
    $blankOut = {
        param([int]$Start, [int]$Length)
        for ($index = $Start; $index -lt $Start + $Length; $index++) {
            $plain[$index] = ' '
            $markup[$index] = ' '
        }
    }

    # A code span shows its text as written: nothing inside it is a tag, a link or a URL.
    foreach ($span in [regex]::Matches([string]::new($markup), '(?<!`)(?<ticks>`+)(?!`)(?:(?!\n[ \t]*\n)[\s\S])+?(?<!`)\k<ticks>(?!`)')) {
        & $blankOut $span.Index $span.Length
    }

    # An autolink in angle brackets links what's inside it, where escapes don't apply but
    # entities are decoded (&amp; is &).
    $unescaped = '(?<=(?:^|[^\\])(?:\\\\)*)'
    foreach ($autolink in [regex]::Matches([string]::new($plain), $unescaped + '<(?<url>[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\s<>]*)>')) {
        & $add "link" ([System.Net.WebUtility]::HtmlDecode($autolink.Groups['url'].Value)).Replace('\', '%5C')
        & $blankOut $autolink.Index $autolink.Length
    }

    # Raw HTML: everything in an HTML block, and in Markdown text any complete tag, comment,
    # <?...?>, <!...> or CDATA whose < isn't escaped. It shows no Markdown and no autolink,
    # and a tag inside a comment is no tag. Of the tags, GitHub keeps href on <a>, src on
    # <img> and srcset on a <picture>'s <source> (a theme image), stripping srcset from
    # <img>. Attribute values are HTML, so entities are decoded.
    $rawHtml = "(?i)<(?:[A-Za-z][A-Za-z0-9-]*(?:$attribute)*\s*/?>|/[A-Za-z][A-Za-z0-9-]*\s*>|!--[\s\S]*?-->|\?[\s\S]*?\?>|!\[CDATA\[[\s\S]*?\]\]>|![A-Za-z][^>]*>)"
    $tagPattern = "(?i)^<(?<name>a|img|source)(?<attributes>(?:$attribute)*)\s*/?>\z"
    $attributeCapture = '\s+(?<name>[A-Za-z_:][A-Za-z0-9_.:-]*)(?:\s*=\s*(?:(?<value>[^\s"''=<>`]+)|''(?<value>[^'']*)''|"(?<value>[^"]*)"))?'
    $inlineTags = [regex]::Matches([string]::new($plain), $unescaped + $rawHtml)
    $readableTags = foreach ($token in @([regex]::Matches($htmlText, $rawHtml)) + @($inlineTags)) {
        $tag = [regex]::Match($token.Value, $tagPattern)
        if ($tag.Success) { $tag }
    }
    foreach ($tag in @($readableTags)) {
        $tagName = $tag.Groups['name'].Value.ToLowerInvariant()
        foreach ($pair in [regex]::Matches($tag.Groups['attributes'].Value, $attributeCapture)) {
            $name = $pair.Groups['name'].Value.ToLowerInvariant()
            $value = [System.Net.WebUtility]::HtmlDecode($pair.Groups['value'].Value)
            if ($tagName -eq 'a' -and $name -eq 'href') {
                & $add "link" $value
            } elseif ($tagName -eq 'img' -and $name -eq 'src') {
                & $add "image" $value
            } elseif ($tagName -eq 'source' -and $name -eq 'srcset') {
                # A comma-separated candidate list, each optionally followed by a descriptor.
                foreach ($candidate in @($value -split ',')) {
                    & $add "image" (@($candidate.Trim() -split '\s+')[0])
                }
            }
        }
    }
    foreach ($tag in $inlineTags) {
        & $blankOut $tag.Index $tag.Length
    }

    # Images, then links, so a badge image inside a link's text is read as an image and
    # the link around it still has a bracket-free label. The destination is read as
    # written, then its escapes and entities are decoded the way CommonMark does, and a
    # literal backslash becomes %5C as GitHub writes it. Without the closing parenthesis
    # it isn't a link, and the bare-URL pass sees the text instead.
    $destinationPattern = [regex]::new('\G[ \t]*\n?[ \t]*(?:<(?<url>(?:\\.|[^<>\n\\])*)>|(?<url>(?:\\\S|\((?:\\\S|[^\s()\\])*\)|[^\s()<\\])(?:\\\S|\((?:\\\S|[^\s()\\])*\)|[^\s()\\])*))(?:[ \t]*\n?[ \t]*(?:"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|\((?:\\.|[^()\\])*\)))?[ \t]*\n?[ \t]*\)')
    foreach ($pass in @(@{ Kind = 'image'; Pattern = '!\[[^\]]*\]\(' }, @{ Kind = 'link'; Pattern = '\[[^\]]*\]\(' })) {
        foreach ($match in [regex]::Matches([string]::new($markup), $pass.Pattern)) {
            $destination = $destinationPattern.Match($markdownText, $match.Index + $match.Length)
            if (-not $destination.Success) {
                continue
            }
            $url = [regex]::Replace($destination.Groups['url'].Value, '\\([!-/:-@\[-`{-~])|&(?:#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});', {
                    param($token)
                    if ($token.Groups[1].Success) { $token.Groups[1].Value } else { [System.Net.WebUtility]::HtmlDecode($token.Value) }
                })
            & $add $pass.Kind $url.Replace('\', '%5C')
            & $blankOut $match.Index ($destination.Index + $destination.Length - $match.Index)
        }
    }

    # Bare URLs, found the way GitHub's autolink extension finds them: the letters before
    # :// must be exactly http or https, the domain is host characters, hyphens, dots and
    # underscores (none in its last two labels), and the link runs to ASCII whitespace or
    # <, then drops trailing ? ! . , : * _ ~ ' ", an entity-like &name;, and each ) beyond
    # the ones it opened. Backslashes and entities stay as written, as GitHub keeps them.
    $scan = [string]::new($plain)
    foreach ($scheme in [regex]::Matches($scan, '(?<![A-Za-z])[A-Za-z]+(?=://)')) {
        if ($scheme.Value -notin @('http', 'https')) {
            continue
        }
        $domainStart = $scheme.Index + $scheme.Length + 3
        $domain = [regex]::Match($scan.Substring($domainStart), '^(?:[^\s!-/:-@\[-`{-~\p{P}]|[-._])+')
        if (-not $domain.Success -or $domain.Value -match '_[^.]*(?:\.[^.]*)?\z') {
            continue
        }
        $end = $domainStart + $domain.Length
        while ($end -lt $scan.Length -and $scan[$end] -ne '<' -and " `t`n`r`f`v".IndexOf($scan[$end]) -lt 0) {
            $end++
        }
        $url = $scan.Substring($scheme.Index, $end - $scheme.Index)
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
        & $add "link" $url.Replace('\', '%5C')
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
    # Only a real tag names an anchor, by its id or its name (GitHub keeps both, as
    # user-content-<value>, on any element), so the words name="x" in a paragraph can't make
    # a missing anchor look present. Neither can a tag GitHub shows as text or drops: one in
    # a fenced code block, a code span or an HTML comment, or one whose < is escaped.
    $attribute = '\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:[^\s"''=<>`]+|''[^'']*''|"[^"]*"))?'
    $attributeCapture = '\s+(?<name>[A-Za-z_:][A-Za-z0-9_.:-]*)(?:\s*=\s*(?:(?<value>[^\s"''=<>`]+)|''(?<value>[^'']*)''|"(?<value>[^"]*)"))?'
    # The README is written with CRLF on Windows; GitHub ends a line at CR, LF or CRLF, and
    # the fence and heading patterns below end theirs at LF.
    $text = [regex]::Replace($ExpectedReadme, '\r\n?', "`n")
    # A fence runs to a closing run of its own character at least as long, or to the end. A
    # backtick fence's info string can't hold a backtick (then the line isn't a fence), and
    # ```~ doesn't close one.
    $fencePattern = '(?ms)^ {0,3}(?<fence>(?<char>`)`{2,}(?=[^`\n]*$)|(?<char>~)~{2,})(?:.*?^ {0,3}\k<fence>\k<char>*[ \t]*$|.*\z)'
    $withoutFences = [regex]::Replace($text, $fencePattern, '')
    # Escapes, code spans and comments are read in one pass from the left, so whichever
    # starts first wins: a comment inside a code span is code, a backtick inside a comment
    # opens nothing, and an escaped backtick doesn't open a span. An escaped character keeps
    # its backslash but not itself, so an escaped < starts no tag.
    $inlineScan = '(?<escape>\\[!-/:-@\[-`{-~])|(?<code>(?<!`)(?<ticks>`+)(?!`)(?:(?!\n[ \t]*\n)[\s\S])+?(?<!`)\k<ticks>(?!`))|(?<comment><!--[\s\S]*?-->)'
    $tagText = [regex]::Replace($withoutFences, $inlineScan, { param($match) if ($match.Groups['escape'].Success) { '\' + [char]0xE000 } else { '' } })
    foreach ($tag in [regex]::Matches($tagText, "(?<=(?:^|[^\\])(?:\\\\)*)<(?<name>[A-Za-z][A-Za-z0-9-]*)(?<attributes>(?:$attribute)*)\s*/?>")) {
        foreach ($pair in [regex]::Matches($tag.Groups['attributes'].Value, $attributeCapture)) {
            $name = $pair.Groups['name'].Value
            if ($name -eq 'name' -or $name -eq 'id') {
                $id = [System.Net.WebUtility]::HtmlDecode($pair.Groups['value'].Value)
                if (-not [string]::IsNullOrWhiteSpace($id)) {
                    $null = $anchors.Add($id)
                }
            }
        }
    }
    # GitHub gives every heading it renders an id, in three forms, and numbers them in
    # document order, so they're gathered with their offsets first. What it doesn't render as
    # Markdown (fenced blocks, HTML comments) is blanked to spaces rather than cut, so the
    # offsets of the three forms line up.
    $blankOut = { param($match) [regex]::Replace($match.Value, '[^\n]', ' ') }
    $headingText = [regex]::Replace($text, $fencePattern, $blankOut)
    $headingText = [regex]::Replace($headingText, $inlineScan, { param($match) if ($match.Groups['comment'].Success) { & $blankOut $match } else { $match.Value } })
    $headings = [System.Collections.Generic.List[object]]::new()
    # Line by line, as CommonMark reads blocks. An HTML block starts at a line opening with a
    # form that starts one: <pre>, <script>, <style> or <textarea> (it ends at the closing
    # tag), a comment, <?, a declaration or CDATA (each ends at its closing marker), a
    # block-level tag (it ends at a blank line), or a lone complete tag that doesn't continue a
    # paragraph (it ends at a blank line). Nothing in one is a heading. Any other line opening
    # with < (an inline tag, an autolink, "< 5") is paragraph text. ATX: its text is on its
    # own line (a bare # is an empty heading, and the line after it a paragraph), a closing
    # run of # isn't part of it, and it can sit behind quote and list markers in any order, up
    # to three spaces in; a list marker followed by five spaces opens indented code instead.
    # Setext: the paragraph above a line of = or -, its lines joined without a space ("Two
    # line" over "setext heading" gives two-linesetext-heading); a line of - after a blank
    # line, a list item or a quote is a rule instead. A raw <h1> to <h6> in a heading's text
    # closes it, as the HTML parser does, so "## Outer <h3>Inner</h3>" gives outer- and inner.
    # Not read: a heading in a list item's indented continuation lines, and a fence inside a
    # list item or quote, which need a real Markdown parser.
    $blockTags = 'address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul'
    $htmlBlockStarts = @(
        @{ Start = '(?i)^ {0,3}<(?:pre|script|style|textarea)(?:[\s>]|$)'; End = '(?i)</(?:pre|script|style|textarea)>' }
        @{ Start = '^ {0,3}<!--'; End = '-->' }
        @{ Start = '^ {0,3}<\?'; End = '\?>' }
        @{ Start = '^ {0,3}<!\[CDATA\['; End = '\]\]>' }
        @{ Start = '^ {0,3}<![A-Za-z]'; End = '>' }
        @{ Start = "(?i)^ {0,3}</?(?:$blockTags)(?:[\s>]|/>|$)"; End = $null }
    )
    $completeTagLine = "^ {0,3}(?:<[A-Za-z][A-Za-z0-9-]*(?:$attribute)*\s*/?>|</[A-Za-z][A-Za-z0-9-]*\s*>)\s*$"
    $container = '(?: {0,3}(?:>[ ]?|(?:[-+*]|\d{1,9}[.)])(?: {1,4}(?! )|\t)))*'
    $atxPattern = '^' + $container + ' {0,3}#{1,6}[ \t]+(?<text>.+?)(?:[ \t]+#+)?[ \t]*$'
    $rawHeadingOpen = "(?i)<h[1-6](?:$attribute)*\s*/?>"
    $paragraph = [System.Collections.Generic.List[string]]::new()
    $paragraphStart = 0
    $inHtml = $false
    $htmlEnd = $null
    $codeLines = [System.Collections.Generic.List[object]]::new()
    $offset = 0
    foreach ($line in ($headingText -split "`n")) {
        $isBlank = [string]::IsNullOrWhiteSpace($line)
        $blockStart = $null
        if (-not $inHtml -and -not $isBlank) {
            foreach ($start in $htmlBlockStarts) {
                if ($line -match $start.Start) { $blockStart = $start; break }
            }
        }
        if ($inHtml) {
            $inHtml = if ($null -ne $htmlEnd) { $line -notmatch $htmlEnd } else { -not $isBlank }
        } elseif ($isBlank) {
            $paragraph.Clear()
        } elseif ($paragraph.Count -gt 0 -and $line -match '^ {0,3}(?:=+|-+)[ \t]*$') {
            $setext = @($paragraph | ForEach-Object { $_.Trim() }) -join "`n"
            $headings.Add([pscustomobject]@{ Offset = $paragraphStart; Text = [regex]::Split($setext, $rawHeadingOpen)[0] })
            $paragraph.Clear()
        } elseif ($null -ne $blockStart -or ($paragraph.Count -eq 0 -and $line -match $completeTagLine)) {
            $paragraph.Clear()
            $htmlEnd = if ($null -ne $blockStart) { $blockStart.End } else { $null }
            # A block that ends at a marker can end on the line it starts.
            $inHtml = -not ($null -ne $htmlEnd -and $line -match $htmlEnd)
        } elseif (($atx = [regex]::Match($line, $atxPattern)).Success) {
            $headings.Add([pscustomobject]@{ Offset = $offset + $atx.Index; Text = [regex]::Split($atx.Groups['text'].Value, $rawHeadingOpen)[0] })
            $paragraph.Clear()
        } elseif ($line -match '^ {0,3}(?:#{1,6}(?:[ \t]|$)|>|(?:[-+*]|\d{1,9}[.)])(?:[ \t]|$)|(?:\*[ \t]*){3,}$|(?:_[ \t]*){3,}$|(?:-[ \t]*){3,}$)') {
            $paragraph.Clear()
        } elseif ($paragraph.Count -gt 0 -or $line -notmatch '^(?: {4}|\t)') {
            if ($paragraph.Count -eq 0) { $paragraphStart = $offset }
            $paragraph.Add($line)
        } else {
            # Indented code: shown as written, so a raw heading tag in it is text.
            $codeLines.Add(@($offset, $line.Length))
        }
        $offset += $line.Length + 1
    }
    # Raw <h1> to <h6>, in an HTML block or inline in a paragraph, but not in a code span,
    # indented code or behind an escaped <. One with its own id keeps that as well (read with
    # the tags above). Attribute values are quoted, so a > inside one doesn't end the tag.
    $htmlHeadingText = [regex]::Replace($headingText, $inlineScan, { param($match) if ($match.Groups['escape'].Success) { '\' + [char]0xE000 } else { & $blankOut $match } })
    foreach ($codeLine in $codeLines) {
        $htmlHeadingText = $htmlHeadingText.Remove($codeLine[0], $codeLine[1]).Insert($codeLine[0], ' ' * $codeLine[1])
    }
    foreach ($match in [regex]::Matches($htmlHeadingText, "(?i)(?<=(?:^|[^\\])(?:\\\\)*)<(?<level>h[1-6])(?:$attribute)*\s*>(?<inner>[\s\S]*?)</\k<level>\s*>")) {
        $headings.Add([pscustomobject]@{ Offset = $match.Index; Text = $match.Groups['inner'].Value })
    }
    # A repeated slug gets -1, -2 and so on, skipping any id an earlier heading already took
    # (Same, Same, Same-1 give same, same-1, same-1-1).
    $headingIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($heading in @($headings | Sort-Object Offset)) {
        $slug = ConvertTo-GitHubHeadingAnchor -Text $heading.Text
        if (-not [string]::IsNullOrWhiteSpace($slug)) {
            $id = $slug
            for ($suffix = 1; $headingIds.Contains($id); $suffix++) { $id = "$slug-$suffix" }
            $null = $headingIds.Add($id)
            $null = $anchors.Add($id)
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

    # GitHub slugs the rendered heading text, so the Markdown goes first. Every rule here was
    # read off the ids of headings rendered on github.com, or off GitHub's rendering of the
    # heading's text (2026-09-24). Escapes, code spans, autolinks and raw HTML are read in one
    # pass from the left, so whichever starts first wins: an escaped backtick opens no span,
    # and a backslash in a span or an underscore in an autolink stays as written. Each escape,
    # span and autolink waits behind a placeholder (a noncharacter, its index in digits and
    # another noncharacter) until the markup around it is gone, so emphasis can wrap it, and
    # a tag or comment leaves a mark that counts as punctuation until then, so <b>a</b>_b_
    # still pairs its underscores. A code span keeps its text, losing one space at each end
    # unless it's only spaces. Then an image drops out, a link (brackets nested two deep)
    # leaves its text, an underscore that opens or closes emphasis goes while one inside a
    # word stays (a_b_c), and entities are decoded. A noncharacter in the heading itself
    # would pass for a placeholder, and GitHub drops it from the slug anyway, so it goes first.
    $mark = [string][char]0xFDD0
    $markEnd = [string][char]0xFDD1
    $gone = [string][char]0xFDD2
    $held = [System.Collections.Generic.List[string]]::new()
    $hold = { param([string]$Item) $held.Add($Item); $mark + [string]($held.Count - 1) + $markEnd }
    $value = [regex]::Replace([string]$Text, '[' + [char]0xFDD0 + '-' + [char]0xFDEF + ']', '')
    $attribute = '\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:[^\s"''=<>`]+|''[^'']*''|"[^"]*"))?'
    $inline = '(?<escape>\\[!-/:-@\[-`{-~])|(?<!`)(?<ticks>`+)(?!`)(?<code>.+?)(?<!`)\k<ticks>(?!`)' +
        '|<(?<url>[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\s<>]*)>' +
        '|<(?<url>[A-Za-z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*)>' +
        '|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[[\s\S]*?\]\]>|<![A-Za-z][^>]*>|</?[A-Za-z][A-Za-z0-9-]*(?:' + $attribute + ')*\s*/?>'
    $value = [regex]::Replace($value, $inline, {
            param($match)
            if ($match.Groups['escape'].Success) { return (& $hold $match.Value.Substring(1)) }
            if ($match.Groups['code'].Success) {
                $code = $match.Groups['code'].Value
                if ($code.Length -ge 2 -and $code.StartsWith(' ') -and $code.EndsWith(' ') -and $code.Trim(' ').Length -gt 0) { $code = $code.Substring(1, $code.Length - 2) }
                return (& $hold $code)
            }
            if ($match.Groups['url'].Success) { return (& $hold $match.Groups['url'].Value) }
            return $gone
        })
    $bracketed = '(?:[^\[\]]|\[(?:[^\[\]]|\[[^\[\]]*\])*\])*'
    $value = [regex]::Replace($value, '!\[' + $bracketed + '\]\([^)]*\)', '')
    $value = [regex]::Replace($value, '\[(?<text>' + $bracketed + ')\]\([^)]*\)', '${text}')
    # An underscore run opens emphasis when what's before it is the start, a space or
    # punctuation and what follows isn't a space, and closes it the other way round: the
    # rule GitHub follows, where a symbol such as the euro sign or an emoji is no punctuation,
    # so a_b_c and euro_a_ keep their underscores. Whole runs only, the span holds no other
    # opener (so _a_b _c_ keeps its first underscore and ____ stays as it is), and runs of
    # different lengths use the shorter one: __a_ is _a and _a__ is a_. Each pass takes the
    # innermost pairs, so nesting deeper than 64 (no real heading) keeps its underscores rather
    # than taking a pass per level of a long crafted line.
    $punctuation = '\p{P}!-/:-@\[-`{-~' + $mark + $markEnd + $gone
    $opener = '(?<=^|[\s' + $punctuation + '])(?<!_)_+(?=[^\s_])'
    $passes = 0
    do {
        $passes++
        $before = $value
        $value = [regex]::Replace($value, '(?<=^|[\s' + $punctuation + '])(?<!_)(?<open>_+)(?=[^\s_])(?<text>(?:(?!' + $opener + ')[\s\S])+?)(?<=[^\s_])(?<close>_+)(?!_)(?=$|[\s' + $punctuation + '])', {
                param($match)
                $used = [Math]::Min($match.Groups['open'].Length, $match.Groups['close'].Length)
                ('_' * ($match.Groups['open'].Length - $used)) + $match.Groups['text'].Value + ('_' * ($match.Groups['close'].Length - $used))
            })
    } while ($passes -lt 64 -and -not [string]::Equals($value, $before, [StringComparison]::Ordinal))
    $value = [System.Net.WebUtility]::HtmlDecode($value.Replace($gone, ''))
    $rendered = [regex]::Replace($value, $mark + '(?<index>[0-9]+)' + $markEnd, { param($match) $held[[int]$match.Groups['index'].Value] })

    # Lower case, with U+0130 (dotted capital I) in full, i and a combining dot as GitHub has
    # it, where .NET gives a bare i. Then keep what GitHub's word class keeps: letters, marks,
    # decimal digits, letter numbers (U+216B, roman twelve), connector punctuation (_, U+203F,
    # U+FF3F), the joiners ZWJ and ZWNJ, the alphabetic symbols (circled U+24B6 on, and the
    # squared and negative letters), hyphens and spaces. Other numbers (U+00BD one half,
    # U+00B2, U+2081), emoji, tabs, NBSP and other spaces all go. Each space becomes its own
    # hyphen, so "A & B" gives a-b with two hyphens.
    $keptCategories = @(
        [System.Globalization.UnicodeCategory]::UppercaseLetter, [System.Globalization.UnicodeCategory]::LowercaseLetter,
        [System.Globalization.UnicodeCategory]::TitlecaseLetter, [System.Globalization.UnicodeCategory]::ModifierLetter,
        [System.Globalization.UnicodeCategory]::OtherLetter, [System.Globalization.UnicodeCategory]::NonSpacingMark,
        [System.Globalization.UnicodeCategory]::SpacingCombiningMark, [System.Globalization.UnicodeCategory]::EnclosingMark,
        [System.Globalization.UnicodeCategory]::DecimalDigitNumber, [System.Globalization.UnicodeCategory]::LetterNumber,
        [System.Globalization.UnicodeCategory]::ConnectorPunctuation
    )
    $slug = [System.Text.StringBuilder]::new()
    foreach ($rune in $rendered.ToString().Replace([string][char]0x0130, "i$([char]0x0307)").ToLowerInvariant().EnumerateRunes()) {
        $value = $rune.Value
        if ($value -eq 0x20) {
            [void]$slug.Append('-')
        } elseif ($value -eq 0x2D -or $value -eq 0x200C -or $value -eq 0x200D -or
            ($value -ge 0x24B6 -and $value -le 0x24E9) -or ($value -ge 0x1F130 -and $value -le 0x1F149) -or
            ($value -ge 0x1F150 -and $value -le 0x1F169) -or ($value -ge 0x1F170 -and $value -le 0x1F189) -or
            $keptCategories.Contains([System.Text.Rune]::GetUnicodeCategory($rune))) {
            [void]$slug.Append($rune.ToString())
        }
    }
    return $slug.ToString()
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
    param(
        [string]$ExpectedReadme,
        # Catalog rows and live metadata, to resolve each "Start-Tool <Name>" line to the
        # entry script run.ps1 will start.
        [hashtable[]]$Entries = @(),
        [hashtable]$RepoLookup = @{}
    )

    $targets = New-Object System.Collections.Generic.List[object]
    $seenTargets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entryByRepo = @{}
    foreach ($entry in @($Entries)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.repo)) {
            $entryByRepo[([string]$entry.repo).ToLowerInvariant()] = $entry
        }
    }

    foreach ($block in [regex]::Matches($ExpectedReadme, '(?ms)```(?:powershell|pwsh|ps1)?\s*(?<script>.*?)```')) {
        $scriptText = $block.Groups['script'].Value
        $startMatch = [regex]::Match($scriptText, '(?m)^\s*irm (?<dispatcher>https://raw\.githubusercontent\.com/\S+/run\.ps1) \| iex; Start-Tool (?<repo>[A-Za-z0-9._-]+)\s*$')
        if (-not $startMatch.Success) {
            continue
        }

        # The dispatcher itself: every one-liner breaks if it is missing.
        Add-ReadmeActionLinkValidationTarget -Targets $targets -SeenTargets $seenTargets -Type "readme-install-dispatcher" -Url $startMatch.Groups['dispatcher'].Value
        $repo = $startMatch.Groups['repo'].Value
        $entry = $entryByRepo[$repo.ToLowerInvariant()]
        if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.entrypoint)) {
            continue
        }
        $branch = Get-Branch $entry (Get-RepoMeta $entry $RepoLookup)
        $rawUrl = ConvertTo-RawGitHubUrl -RepositoryOwner $Owner -Repo ([string]$entry.repo) -Branch $branch -Path ([string]$entry.entrypoint)
        Add-ReadmeActionLinkValidationTarget -Targets $targets -SeenTargets $seenTargets -Type "readme-install-entrypoint" -Url $rawUrl -Repo ([string]$entry.repo)
    }

    # Row actions are <a href="..." aria-label="..."> tags now (the href's & written &amp;);
    # an older README's Markdown links are still read.
    foreach ($match in [regex]::Matches($ExpectedReadme, '(?i)\]\((?<url>https://github\.com/[^)\s]+/releases/latest)\)|<a href="(?<url>https://github\.com/[^"\s]+/releases/latest)"')) {
        Add-ReadmeActionLinkValidationTarget -Targets $targets -SeenTargets $seenTargets -Type "readme-download" -Url ([System.Net.WebUtility]::HtmlDecode($match.Groups['url'].Value))
    }

    foreach ($match in [regex]::Matches($ExpectedReadme, '(?i)\[Install\]\((?<url>https://raw\.githubusercontent\.com/[^)\s]+)\)|<a href="(?<url>https://raw\.githubusercontent\.com/[^"\s]+)" aria-label="Install ')) {
        Add-ReadmeActionLinkValidationTarget -Targets $targets -SeenTargets $seenTargets -Type "readme-userscript-install" -Url ([System.Net.WebUtility]::HtmlDecode($match.Groups['url'].Value))
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
