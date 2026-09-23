# Shared helpers for the profile generator: member access on JSON and hashtable
# values, JSON round-tripping, hashing, date and version parsing. Dot-sourced by
# scripts/sync-profile.ps1, whose parameters and constants these functions read.

function ConvertTo-BooleanValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [bool]) {
        return [bool]$Value
    }
    return ([string]$Value).ToLowerInvariant() -eq "true"
}

function Test-SafeGitHubName {
    <#
    .SYNOPSIS
    Returns true when a repository or owner name is safe to interpolate into a URL or gh api path.
    .DESCRIPTION
    GitHub repository names allow only ASCII letters, digits, period, underscore, and hyphen.
    This guard rejects path-traversal (../), query/fragment injection, whitespace, and slashes so
    catalog-sourced names cannot be tampered into unexpected gh api paths or generated install snippets.
    .PARAMETER Name
    The candidate repository or owner name.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    # \z, not $: in .NET $ also matches before a final newline, so "WinTool`n" would pass.
    return $Name -cmatch '^[A-Za-z0-9._-]+\z'
}

function Test-VisibleText {
    <#
    .SYNOPSIS
    Returns true when text has at least one character a reader would see.
    .DESCRIPTION
    Judged by code point, so a character outside the Basic Multilingual Plane is seen whole
    rather than as its surrogates. Invisible: controls; format characters (zero-width space,
    bidi marks and controls, word joiner, byte order mark, tag characters) except the
    prepended concatenation marks, which draw a glyph; whitespace and other separators
    except U+1680, which draws a line; the other default-ignorable code points (variation
    selectors, Hangul fillers, the grapheme joiner, Khmer inherent vowels, Mongolian
    variation selectors, and U+2065, the one unassigned code point among the invisible
    operators); and the braille blank. IsNullOrWhiteSpace counts most of these as
    text, so a label made only of them would draw an empty link or heading.
    .PARAMETER Text
    The candidate text; $null and empty are not visible.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $false }
    # A lone surrogate comes back as U+FFFD, which the encoders write too: visible.
    foreach ($rune in $Text.EnumerateRunes()) {
        $code = $rune.Value
        $invisible = switch ([System.Text.Rune]::GetUnicodeCategory($rune)) {
            'Control' { $true }
            'Format' { -not (($code -ge 0x0600 -and $code -le 0x0605) -or $code -in @(0x06DD, 0x070F, 0x0890, 0x0891, 0x08E2, 0x110BD, 0x110CD)) }
            'SpaceSeparator' { $code -ne 0x1680 }
            'LineSeparator' { $true }
            'ParagraphSeparator' { $true }
            default {
                $code -eq 0x034F -or ($code -ge 0x115F -and $code -le 0x1160) -or ($code -ge 0x17B4 -and $code -le 0x17B5) -or
                ($code -ge 0x180B -and $code -le 0x180F) -or $code -eq 0x2065 -or $code -eq 0x2800 -or $code -eq 0x3164 -or ($code -ge 0xFE00 -and $code -le 0xFE0F) -or
                $code -eq 0xFFA0 -or ($code -ge 0xFFF0 -and $code -le 0xFFF8) -or ($code -ge 0xE0000 -and $code -le 0xE0FFF)
            }
        }
        if (-not $invisible) { return $true }
    }
    return $false
}

function ConvertTo-IsoText {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [datetime]) {
        # ConvertFrom-Json turns an offset like +02:00 into local time, so a local value is
        # written as UTC; otherwise the feed would change with the machine's time zone.
        # SpecifyKind because ToUniversalTime keeps Kind Local when the local zone is UTC,
        # and "o" then writes +00:00 where every other machine writes Z.
        $normalized = if ($Value.Kind -eq [System.DateTimeKind]::Local) { [datetime]::SpecifyKind($Value.ToUniversalTime(), [System.DateTimeKind]::Utc) } else { $Value }
        return $normalized.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function ConvertTo-OrdinalSortKey {
    <#
    .SYNOPSIS
    Returns a Sort-Object key that orders strings case-insensitively by code unit under any culture.
    .DESCRIPTION
    Sort-Object compares strings with the current culture, so generated order moved with the
    machine locale: under tr-TR a dotless capital I sorts before a dotted small i, and
    IRL_Streamer jumped ahead of iOSIconPack. Each UTF-16 code unit of the invariant
    upper-cased value becomes five decimal digits. Digits collate the same way in every
    culture, so sorting the keys gives the OrdinalIgnoreCase order of the values.
    .PARAMETER Value
    Identifier to order: a repository name, category slug, topic, tag or action kind.
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }
    $upper = $Value.ToUpperInvariant()
    $builder = [System.Text.StringBuilder]::new($upper.Length * 5)
    foreach ($codeUnit in $upper.ToCharArray()) {
        [void]$builder.Append(([int]$codeUnit).ToString('D5', [System.Globalization.CultureInfo]::InvariantCulture))
    }
    return $builder.ToString()
}

function ConvertTo-DateTimeOffsetOrNull {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [datetimeoffset]) {
        return $Value
    }
    if ($Value -is [datetime]) {
        return [datetimeoffset]$Value
    }

    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Get-AgeDays {
    param(
        [object]$Value,
        [datetimeoffset]$Now
    )

    $parsed = ConvertTo-DateTimeOffsetOrNull -Value $Value
    if ($null -eq $parsed) {
        return $null
    }
    return [math]::Round(($Now.ToUniversalTime() - $parsed.ToUniversalTime()).TotalDays, 2)
}

function ConvertTo-RawGitHubUrl {
    param(
        [string]$RepositoryOwner = $Owner,
        [string]$Repo,
        [string]$Branch,
        [string]$Path
    )

    $segments = $Path -split '[\\/]'
    $encodedPath = ($segments | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    return "https://raw.githubusercontent.com/$RepositoryOwner/$Repo/$Branch/$encodedPath"
}

function Get-RepoFileSha256 {
    param([string]$RelativePath)

    $fullPath = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $null
    }

    $content = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
    $normalizedContent = $content -replace "`r`n", "`n" -replace "`r", "`n"
    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedContent)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($contentBytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha256.Dispose()
    }
}

function ConvertTo-NormalizedGeneratedText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return (($Text -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd())
}

function Get-StringSha256 {
    param([AllowNull()][string]$Text)

    $normalizedText = ConvertTo-NormalizedGeneratedText -Text $Text
    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedText)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($contentBytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha256.Dispose()
    }
}

function Get-FileSha256Hex {
    param([string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        return $null
    }

    $stream = [System.IO.File]::OpenRead($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Get-Utf8TextSha256Hex {
    param([AllowNull()][string]$Text)

    $textValue = if ($null -eq $Text) { '' } else { $Text }
    $contentBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($textValue)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($contentBytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha256.Dispose()
    }
}

function Get-GitHeadCommit {
    $head = & git -C $RepoRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $commit = (($head | Out-String).Trim()).ToLowerInvariant()
    if ($commit -notmatch '^[a-f0-9]{40}$') {
        return $null
    }

    return $commit
}

function Get-NullableString {
    param([AllowNull()][object]$Value)
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

function Get-MemberValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}

function Test-MemberExists {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }

    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-SortedReportRows {
    # Returns the rows through the pipeline, so a caller that needs a list, such as a report
    # field typed as an array, wraps the call in @(); otherwise no rows become $null and one
    # row becomes a bare object.
    param(
        [object[]]$Rows,
        [string[]]$Keys
    )

    $sortProperties = @(
        foreach ($key in $Keys) {
            $sortKey = $key
            @{
                Expression = {
                    $value = $null
                    if ($_ -is [System.Collections.IDictionary]) {
                        if ($_.Contains($sortKey)) {
                            $value = $_[$sortKey]
                        }
                    } else {
                        $property = $_.PSObject.Properties[$sortKey]
                        if ($property) {
                            $value = $property.Value
                        }
                    }
                    if ($null -eq $value) { "" } else { [string]$value }
                }.GetNewClosure()
            }
        }
    )

    return @($Rows | Sort-Object -Property $sortProperties)
}

function Set-MemberValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($null -eq $Object) {
        return
    }
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    } else {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function ConvertTo-VersionValue {
    param([object]$Version)

    if ($null -eq $Version) {
        return [version]"0.0.0"
    }
    if ($Version -is [version]) {
        $patch = if ($Version.Build -lt 0) { 0 } else { [int]$Version.Build }
        return [version]::new([int]$Version.Major, [int]$Version.Minor, $patch)
    }
    if ($Version -is [string]) {
        return ConvertTo-VersionValue -Version ([version]$Version)
    }

    $major = Get-MemberValue -Object $Version -Name "Major"
    $minor = Get-MemberValue -Object $Version -Name "Minor"
    $patch = Get-MemberValue -Object $Version -Name "Patch"
    if ($null -eq $patch) {
        $patch = Get-MemberValue -Object $Version -Name "Build"
    }
    $patchValue = if ($null -eq $patch) { 0 } else { [int]$patch }

    return [version]::new([int]$major, [int]$minor, $patchValue)
}

function Get-NestedMemberValue {
    param(
        [object]$Object,
        [string]$Path
    )

    $value = $Object
    foreach ($segment in ($Path -split '\.')) {
        $value = Get-MemberValue -Object $value -Name $segment
        if ($null -eq $value) {
            return $null
        }
    }
    return $value
}

function Get-NullableBool {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    return [bool]$Value
}

function ConvertTo-NullableDouble {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal] -or $Value -is [int] -or $Value -is [long]) {
        return [double]$Value
    }

    $parsed = [double]0
    if ([double]::TryParse(
            [string]$Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed
        )) {
        return $parsed
    }
    return $null
}

function ConvertTo-ComparableJson {
    param([object]$Value)

    if ($null -eq $Value) {
        return "null"
    }
    return ConvertTo-Json -InputObject $Value -Depth 20 -Compress
}

function ConvertFrom-JsonElementValue {
    param([System.Text.Json.JsonElement]$Element)

    switch ($Element.ValueKind) {
        ([System.Text.Json.JsonValueKind]::Object) {
            $hash = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) {
                $hash[$property.Name] = (ConvertFrom-JsonElementValue -Element $property.Value)
            }
            return $hash
        }
        ([System.Text.Json.JsonValueKind]::Array) {
            $items = New-Object System.Collections.Generic.List[object]
            foreach ($item in $Element.EnumerateArray()) {
                $items.Add((ConvertFrom-JsonElementValue -Element $item))
            }
            $wrapper = [pscustomobject]@{
                __JsonArray = $true
                Items = $null
            }
            $wrapper.Items = $items
            return $wrapper
        }
        ([System.Text.Json.JsonValueKind]::String) {
            return $Element.GetString()
        }
        ([System.Text.Json.JsonValueKind]::Number) {
            $integerValue = [int64]0
            if ($Element.TryGetInt64([ref]$integerValue)) {
                return $integerValue
            }
            return $Element.GetDouble()
        }
        ([System.Text.Json.JsonValueKind]::True) {
            return $true
        }
        ([System.Text.Json.JsonValueKind]::False) {
            return $false
        }
        default {
            return $null
        }
    }
}

function ConvertFrom-JsonPreservingArrays {
    param([string]$Json)

    $document = [System.Text.Json.JsonDocument]::Parse($Json)
    try {
        return ConvertFrom-JsonElementValue -Element $document.RootElement
    } finally {
        $document.Dispose()
    }
}

function Get-ObjectPropertyNames {
    param([object]$Object)

    if ($null -eq $Object) {
        return @()
    }
    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys | ForEach-Object { [string]$_ })
    }
    return @($Object.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty', 'Property') } | ForEach-Object { $_.Name })
}

function Test-JsonArrayWrapper {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    $marker = $Value.PSObject.Properties['__JsonArray']
    return [bool]($marker -and $marker.Value -eq $true -and $Value.PSObject.Properties['Items'])
}

function Get-JsonArrayItems {
    param([object]$Value)

    if ($null -eq $Value) {
        return
    }
    if (Test-JsonArrayWrapper $Value) {
        foreach ($item in $Value.Items) {
            $item
        }
        return
    }
    foreach ($item in @($Value)) {
        $item
    }
}

function ConvertTo-RepoRelativeReportPath {
    param([string]$Path)

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }
    $resolvedPath = Resolve-Path -LiteralPath $fullPath -ErrorAction SilentlyContinue
    if ($resolvedPath) {
        return ([System.IO.Path]::GetRelativePath($RepoRoot, $resolvedPath.Path) -replace '\\', '/')
    }

    return ($Path -replace '\\', '/')
}

function Test-IsoDateText {
    param([string]$Value)

    $parsedDate = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $Value,
        "yyyy-MM-dd",
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedDate
    )
}

function ConvertTo-PowerShellSingleQuotedArgument {
    param([AllowNull()][string]$Value)

    $normalized = if ($null -eq $Value) { "" } else { (([string]$Value -replace "\r?\n", " ") -replace "\s+", " ").Trim() }
    return "'$($normalized.Replace("'", "''"))'"
}
