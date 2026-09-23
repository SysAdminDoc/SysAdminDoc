# Release assets and download trust: asset kind taxonomy, checksum and digest coverage,
# the opt-in artifact verification pilot, and the release asset drift report section.
# Dot-sourced by scripts/sync-profile.ps1.

function Get-ReleaseUrl {
    param([hashtable]$Entry)

    $repo = if ($Entry.aliasOf) { [string]$Entry.aliasOf } else { [string]$Entry.repo }
    return "https://github.com/$Owner/$repo/releases/latest"
}

function ConvertTo-ReleaseAssetKind {
    param([string]$Name)

    $lower = ([string]$Name).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($lower)) { return $null }
    if ($lower.EndsWith(".apk")) { return "apk" }
    if ($lower -match '\.(exe|msi|msix|appx|appxbundle)$') { return "exe" }
    if ($lower -match '\.(zip|7z|rar|tgz)$' -or $lower.EndsWith(".tar.gz")) { return "zip" }
    if ($lower.EndsWith(".crx")) { return "crx" }
    if ($lower.EndsWith(".xpi")) { return "xpi" }
    if ($lower.EndsWith(".user.js") -or $lower.EndsWith(".userscript.js")) { return "userscript" }
    if ($lower.EndsWith(".jar")) { return "jar" }
    if ($lower.EndsWith(".deb")) { return "deb" }
    if ($lower.EndsWith(".rpm")) { return "rpm" }
    if ($lower.EndsWith(".dmg")) { return "dmg" }
    if ($lower -match '\.(ps1|bat|cmd|sh)$') { return "script" }
    return "other"
}

function Get-ReleaseAssetKinds {
    param([string[]]$AssetNames)

    $names = @($AssetNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($names.Count -eq 0) {
        return @("source-archive")
    }

    $kinds = foreach ($name in $names) {
        ConvertTo-ReleaseAssetKind -Name $name
    }
    return @($kinds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object { ConvertTo-OrdinalSortKey $_ } -Unique)
}

function Get-ReleaseAssetNamesFromApiRelease {
    param([object]$Release)

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($asset in @((Get-MemberValue -Object $Release -Name "assets"))) {
        $name = Get-MemberValue -Object $asset -Name "name"
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
            $names.Add([string]$name)
        }
    }
    return $names.ToArray()
}

function Get-ReleaseAssetDigestsFromApiRelease {
    param([object]$Release)

    $digests = @{}
    foreach ($asset in @((Get-MemberValue -Object $Release -Name "assets"))) {
        $name = Get-MemberValue -Object $asset -Name "name"
        $digest = Get-MemberValue -Object $asset -Name "digest"
        if (-not [string]::IsNullOrWhiteSpace([string]$name) -and -not [string]::IsNullOrWhiteSpace([string]$digest)) {
            $digests[[string]$name] = [string]$digest
        }
    }
    return $digests
}

function Test-ReleaseAssetMetadataInspected {
    param([object]$Meta)

    $release = Get-MemberValue -Object $Meta -Name "latestRelease"
    if (-not $release) { return $false }
    return [bool](Get-MemberValue -Object $release -Name "assetApiInspected")
}

function Get-ReleaseAssetKindsFromMeta {
    param([object]$Meta)

    $release = Get-MemberValue -Object $Meta -Name "latestRelease"
    if (-not $release) { return @() }
    $kinds = @(Get-MemberValue -Object $release -Name "releaseAssetKinds")
    return @($kinds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-ReleaseAssetNamesFromMeta {
    param([object]$Meta)

    $release = Get-MemberValue -Object $Meta -Name "latestRelease"
    if (-not $release) { return @() }
    $names = @(Get-MemberValue -Object $release -Name "releaseAssetNames")
    return @($names | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Test-AllowedReleaseArtifactUrl {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try {
        $uri = [Uri]$Url
        if ($uri.Scheme -ne "https") { return $false }
        return $uri.Host.ToLowerInvariant() -in @(
            "github.com",
            "objects.githubusercontent.com",
            "release-assets.githubusercontent.com"
        )
    } catch {
        return $false
    }
}

function Get-ReleaseArtifactVerificationTargets {
    <#
    .SYNOPSIS
    Builds bounded, public-safe release artifact candidates from REST asset metadata.
    .PARAMETER Entries
    Visible catalog entries to inspect.
    .PARAMETER RepoLookup
    Repository metadata keyed by repository name.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Entries,
        [hashtable]$RepoLookup
    )

    $allowedKinds = @("apk", "crx", "deb", "dmg", "exe", "jar", "rpm", "xpi", "zip")
    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($Entries)) {
        $meta = Get-RepoMeta -Entry $entry -RepoLookup $RepoLookup
        $release = if ($meta) { Get-MemberValue -Object $meta -Name "latestRelease" } else { $null }
        if ($null -eq $release) { continue }
        $assets = @(Get-JsonArrayItems (Get-MemberValue -Object $release -Name "releaseAssets"))
        if ($assets.Count -eq 0) { continue }

        $checksumAssets = @($assets | Where-Object {
                $name = [string](Get-MemberValue -Object $_ -Name "name")
                $name -match '(?i)(sha256|sha512|checksum|checksums|sums)'
            })
        foreach ($asset in $assets) {
            $assetName = [string](Get-MemberValue -Object $asset -Name "name")
            $assetKind = ConvertTo-ReleaseAssetKind -Name $assetName
            if ([string]::IsNullOrWhiteSpace($assetName) -or $assetKind -notin $allowedKinds) { continue }

            $checksum = $null
            foreach ($candidate in $checksumAssets) {
                $candidateName = [string](Get-MemberValue -Object $candidate -Name "name")
                if ($candidateName -match [regex]::Escape($assetName)) {
                    $checksum = $candidate
                    break
                }
            }
            if ($null -eq $checksum -and $checksumAssets.Count -eq 1) {
                $checksum = $checksumAssets[0]
            }

            $targets.Add([ordered]@{
                repo = [string]$entry.repo
                assetName = $assetName
                assetKind = $assetKind
                assetUrl = Get-MemberValue -Object $asset -Name "browserDownloadUrl"
                assetSize = Get-MemberValue -Object $asset -Name "size"
                checksumAssetName = if ($checksum) { [string](Get-MemberValue -Object $checksum -Name "name") } else { $null }
                checksumUrl = if ($checksum) { Get-MemberValue -Object $checksum -Name "browserDownloadUrl" } else { $null }
                checksumSize = if ($checksum) { Get-MemberValue -Object $checksum -Name "size" } else { $null }
            })
        }
    }

    return @($targets.ToArray())
}

function Get-ReleaseArtifactDownload {
    param(
        [string]$Url,
        [int]$MaxBytes
    )

    # refused marks what the network can't explain: a host outside GitHub's release hosts,
    # at the start or at the end of the redirects, a redirect the safety checks turn down
    # (to http, a loop, a bad Location, a literal private address), or a successful body
    # bigger than its cap, which for an asset is its
    # published size. A name that DNS answers with a non-public address is what a DNS
    # filter's sinkhole looks like, and an error page over the cap says nothing about the
    # artifact, so both stay unreachable.
    if (-not (Test-AllowedReleaseArtifactUrl -Url $Url)) {
        return [ordered]@{ ok = $false; refused = $true; bytes = @(); text = $null; error = "download URL is not an allowed HTTPS GitHub release host"; bytesRead = 0 }
    }

    $download = Invoke-SafeOutboundHttpRequest `
        -Url $Url `
        -Method Get `
        -TimeoutSec 30 `
        -MaxRedirects 5 `
        -ReadBody `
        -MaxBytes $MaxBytes `
        -UserAgent 'SysAdminDoc-release-verifier' `
        -Accept '*/*'

    # Only the first URL's host was checked, so a redirect could hand over a body from any
    # public host. A chain that ended off GitHub's release hosts is refused, not hashed,
    # whatever came back; a safety-check refusal keeps its own reason.
    $finalUrl = [string](Get-MemberValue -Object $download -Name 'finalUrl')
    $policyBlocked = ConvertTo-BooleanValue (Get-MemberValue -Object $download -Name 'policyBlocked')
    if (-not $policyBlocked -and -not [string]::IsNullOrWhiteSpace($finalUrl) -and -not (Test-AllowedReleaseArtifactUrl -Url $finalUrl)) {
        $finalUri = $null
        $finalHost = if ([System.Uri]::TryCreate($finalUrl, [System.UriKind]::Absolute, [ref]$finalUri)) { $finalUri.Host } else { $finalUrl }
        return [ordered]@{ ok = $false; refused = $true; byteCapExceeded = $false; bytes = @(); text = $null; error = "redirected to $finalHost, outside GitHub's release hosts"; bytesRead = [int64]$download.bytesRead }
    }

    return [ordered]@{
        ok = [bool]($download.ok -and $download.statusCode -ge 200 -and $download.statusCode -lt 300)
        refused = [bool](
            ((ConvertTo-BooleanValue (Get-MemberValue -Object $download -Name 'policyBlocked')) -and -not (ConvertTo-BooleanValue (Get-MemberValue -Object $download -Name 'dnsAnswerBlocked'))) -or
            ((ConvertTo-BooleanValue (Get-MemberValue -Object $download -Name 'byteCapExceeded')) -and [int](Get-MemberValue -Object $download -Name 'statusCode') -ge 200 -and [int](Get-MemberValue -Object $download -Name 'statusCode') -lt 300)
        )
        byteCapExceeded = [bool](ConvertTo-BooleanValue (Get-MemberValue -Object $download -Name 'byteCapExceeded'))
        bytes = @($download.bytes)
        text = $download.text
        error = if ($download.ok -and $download.statusCode -ge 200 -and $download.statusCode -lt 300) { $null } else { $download.error }
        bytesRead = [int64]$download.bytesRead
    }
}

function Get-ReleaseArtifactSha256 {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha256.Dispose()
    }
}

function Get-ReleaseArtifactChecksumFromText {
    param(
        [string]$Text,
        [string]$AssetName
    )

    $hashPattern = '(?i)\b[a-f0-9]{64}\b'
    foreach ($line in @(([string]$Text) -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not [string]::IsNullOrWhiteSpace($AssetName) -and $line -notmatch [regex]::Escape($AssetName)) { continue }
        $match = [regex]::Match($line, $hashPattern)
        if ($match.Success) { return $match.Value.ToLowerInvariant() }
    }
    $fallback = [regex]::Match([string]$Text, $hashPattern)
    if ($fallback.Success) { return $fallback.Value.ToLowerInvariant() }
    return $null
}

function Test-ReleaseArtifactVerification {
    <#
    .SYNOPSIS
    Optionally verifies capped release assets against matching checksum sidecars.
    .DESCRIPTION
    Verification is disabled by default. The default releaseTrust wording remains
    metadata-only; this pilot only runs when explicitly enabled by the caller.
    .PARAMETER Entries
    Visible catalog entries to inspect.
    .PARAMETER RepoLookup
    Repository metadata keyed by repository name.
    .PARAMETER Targets
    Optional test or caller-supplied target rows; when omitted, targets are derived from Entries.
    .PARAMETER Enabled
    Enables bounded downloads and checksum comparison.
    .PARAMETER MaxAssets
    Maximum number of eligible assets considered in one run.
    .PARAMETER MaxBytes
    Maximum byte size for each downloaded asset.
    .PARAMETER DownloadScript
    Optional injectable downloader used by hermetic tests.
    .PARAMETER Now
    Picks the week whose slice of eligible assets is verified; injectable for tests.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Entries,
        [hashtable]$RepoLookup,
        [object[]]$Targets,
        [switch]$Enabled,
        [ValidateRange(1, 32)]
        [int]$MaxAssets = $script:ReleaseVerificationMaxAssets,
        [ValidateRange(1024, 52428800)]
        [int]$MaxBytes = $script:ReleaseVerificationMaxBytes,
        [scriptblock]$DownloadScript,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )

    $targetRows = @(
        if ($PSBoundParameters.ContainsKey("Targets")) {
            @($Targets)
        } else {
            @(Get-ReleaseArtifactVerificationTargets -Entries $Entries -RepoLookup $RepoLookup)
        }
    )
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not $Enabled) {
        return [ordered]@{
            enabled = $false
            status = "disabled"
            verificationMode = "opt-in"
            maxAssets = [int]$MaxAssets
            maxBytes = [int]$MaxBytes
            targetCount = [int]$targetRows.Count
            checkedAssetCount = 0
            verifiedCount = 0
            skippedCount = 0
            failureCount = 0
            unreachableCount = 0
            downloadedBytes = 0
            rotation = $null
            rows = @()
            errors = @()
            note = "Metadata evidence only: release artifacts were not downloaded or locally verified. Use -VerifyReleaseArtifacts for the capped pilot."
        }
    }

    # Which targets can be verified at all, first, so the per-run cap applies to those only.
    $allowedKinds = @("apk", "crx", "deb", "dmg", "exe", "jar", "rpm", "xpi", "zip")
    # object[], not string[]: a string array element turns $null into "".
    $ineligibleReasons = New-Object 'object[]' $targetRows.Count
    $eligibleIndexes = New-Object System.Collections.Generic.List[int]
    for ($index = 0; $index -lt $targetRows.Count; $index++) {
        $target = $targetRows[$index]
        $checksumName = Get-MemberValue -Object $target -Name "checksumAssetName"
        $ineligibleReasons[$index] = if ([string](Get-MemberValue -Object $target -Name "assetKind") -notin $allowedKinds) {
            "asset kind is outside the verification allowlist"
        } elseif ([string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $target -Name "assetUrl"))) {
            "asset download URL is missing"
        } elseif ($null -eq (Get-MemberValue -Object $target -Name "assetSize")) {
            "asset size is unknown; refusing an uncapped download"
        } elseif ([int64](Get-MemberValue -Object $target -Name "assetSize") -gt $MaxBytes) {
            "asset exceeds the configured byte cap"
        } elseif ([string]::IsNullOrWhiteSpace([string]$checksumName) -or [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $target -Name "checksumUrl"))) {
            "matching checksum sidecar is missing"
        } elseif ($null -ne (Get-MemberValue -Object $target -Name "checksumSize") -and [int64](Get-MemberValue -Object $target -Name "checksumSize") -gt [Math]::Min($MaxBytes, 256KB)) {
            # Its download would be refused at the sidecar cap; that's not a sign of tampering.
            "checksum sidecar exceeds the sidecar cap"
        } else {
            $null
        }
        if ([string]::IsNullOrEmpty($ineligibleReasons[$index])) {
            $eligibleIndexes.Add($index)
        }
    }

    # Then one MaxAssets-wide slice of them, in a stable order, picked by the UTC week
    # (weeks counted from Monday 2026-01-05). A weekly run walks through every eligible
    # asset in turn instead of checking the same first few in catalog order forever.
    $orderedEligible = @($eligibleIndexes | Sort-Object {
            ConvertTo-OrdinalSortKey ("{0}/{1}" -f [string](Get-MemberValue -Object $targetRows[$_] -Name "repo"), [string](Get-MemberValue -Object $targetRows[$_] -Name "assetName"))
        })
    $weekIndex = [int][Math]::Floor(($Now.UtcDateTime.Date - [datetime]::new(2026, 1, 5)).TotalDays / 7)
    $sliceCount = [int][Math]::Ceiling($orderedEligible.Count / [double]$MaxAssets)
    $sliceIndex = if ($sliceCount -gt 0) { (($weekIndex % $sliceCount) + $sliceCount) % $sliceCount } else { 0 }
    $selectedIndexes = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($selected in @($orderedEligible | Select-Object -Skip ($sliceIndex * $MaxAssets) -First $MaxAssets)) {
        [void]$selectedIndexes.Add([int]$selected)
    }

    $checkedCount = 0
    $verifiedCount = 0
    $skippedCount = 0
    $failureCount = 0
    $unreachableCount = 0
    $downloadedBytes = [int64]0
    for ($index = 0; $index -lt $targetRows.Count; $index++) {
        $target = $targetRows[$index]
        $repo = [string](Get-MemberValue -Object $target -Name "repo")
        $assetName = [string](Get-MemberValue -Object $target -Name "assetName")
        $assetKind = [string](Get-MemberValue -Object $target -Name "assetKind")
        $checksumName = Get-MemberValue -Object $target -Name "checksumAssetName"
        $status = "skipped"
        $reason = $ineligibleReasons[$index]
        $expected = $null
        $actual = $null
        $assetBytes = [int64]0

        if (-not [string]::IsNullOrEmpty($reason)) {
            # Not verifiable; the reason says why.
        } elseif (-not $selectedIndexes.Contains($index)) {
            $reason = "outside this week's rotation slice"
        } else {
            $checkedCount++
            # Capped at the size the release lists (never 0, which the reader refuses): a
            # longer body can't be the asset, so it's refused, not hashed.
            $publishedSize = [int64](Get-MemberValue -Object $target -Name "assetSize")
            $assetCap = [int][Math]::Max(1, [Math]::Min([int64]$MaxBytes, $publishedSize))
            $assetDownload = if ($DownloadScript) { & $DownloadScript $target "asset" } else { Get-ReleaseArtifactDownload -Url ([string](Get-MemberValue -Object $target -Name "assetUrl")) -MaxBytes $assetCap }
            # A download that fails says nothing about the artifact, and in an unattended run
            # it is usually the network; it warns. A refused one does say something: the
            # safety check turned the host or a redirect down, or the body was bigger than
            # the published size. Those fail the run, like bytes that disagree with their
            # published checksum.
            if (ConvertTo-BooleanValue (Get-MemberValue -Object $assetDownload -Name "refused")) {
                $status = "failed"
                $reason = if (ConvertTo-BooleanValue (Get-MemberValue -Object $assetDownload -Name "byteCapExceeded")) {
                    "asset download refused: the body is bigger than the $publishedSize bytes the release lists"
                } else {
                    "asset download refused: $([string](Get-MemberValue -Object $assetDownload -Name "error"))"
                }
            } elseif (-not (ConvertTo-BooleanValue (Get-MemberValue -Object $assetDownload -Name "ok"))) {
                $status = "unreachable"
                $reason = "asset download failed: $([string](Get-MemberValue -Object $assetDownload -Name "error"))"
            } else {
                $assetByteValue = Get-MemberValue -Object $assetDownload -Name "bytes"
                $assetBytesValue = if ($assetByteValue -is [byte[]]) { $assetByteValue } else { [byte[]]@($assetByteValue) }
                $assetBytes = [int64]$assetBytesValue.Length
                $downloadedBytes += $assetBytes
                $checksumDownload = if ($DownloadScript) { & $DownloadScript $target "checksum" } else { Get-ReleaseArtifactDownload -Url ([string](Get-MemberValue -Object $target -Name "checksumUrl")) -MaxBytes ([Math]::Min($MaxBytes, 256KB)) }
                if (ConvertTo-BooleanValue (Get-MemberValue -Object $checksumDownload -Name "refused")) {
                    $status = "failed"
                    $reason = "checksum sidecar download refused: $([string](Get-MemberValue -Object $checksumDownload -Name "error"))"
                } elseif (-not (ConvertTo-BooleanValue (Get-MemberValue -Object $checksumDownload -Name "ok"))) {
                    $status = "unreachable"
                    $reason = "checksum sidecar download failed: $([string](Get-MemberValue -Object $checksumDownload -Name "error"))"
                } else {
                    $checksumText = [string](Get-MemberValue -Object $checksumDownload -Name "text")
                    $expected = Get-ReleaseArtifactChecksumFromText -Text $checksumText -AssetName $assetName
                    if ([string]::IsNullOrWhiteSpace($expected)) {
                        $status = "failed"
                        $reason = "checksum sidecar did not contain a SHA-256 value"
                    } else {
                        $actual = Get-ReleaseArtifactSha256 -Bytes $assetBytesValue
                        if ($actual -eq $expected) {
                            $status = "verified"
                        } else {
                            $status = "failed"
                            $reason = "SHA-256 mismatch"
                        }
                    }
                }
            }
        }

        if ($status -eq "verified") { $verifiedCount++ }
        elseif ($status -eq "failed") { $failureCount++ }
        elseif ($status -eq "unreachable") { $unreachableCount++ }
        else { $skippedCount++ }
        $rows.Add([ordered]@{
            repo = $repo
            asset = $assetName
            assetKind = $assetKind
            checksumAsset = if ([string]::IsNullOrWhiteSpace([string]$checksumName)) { $null } else { [string]$checksumName }
            status = $status
            reason = if ([string]::IsNullOrWhiteSpace([string]$reason)) { $null } else { [string]$reason }
            expectedSha256 = $expected
            actualSha256 = $actual
            assetBytes = $assetBytes
        })
    }

    return [ordered]@{
        enabled = $true
        status = if ($failureCount -gt 0) { "failed" } elseif ($unreachableCount -gt 0) { "warning" } elseif ($verifiedCount -gt 0) { "verified" } elseif ($skippedCount -gt 0) { "skipped" } else { "no-candidates" }
        verificationMode = "opt-in"
        maxAssets = [int]$MaxAssets
        maxBytes = [int]$MaxBytes
        targetCount = [int]$targetRows.Count
        checkedAssetCount = [int]$checkedCount
        verifiedCount = [int]$verifiedCount
        skippedCount = [int]$skippedCount
        failureCount = [int]$failureCount
        unreachableCount = [int]$unreachableCount
        downloadedBytes = $downloadedBytes
        rotation = [ordered]@{
            weekIndex = $weekIndex
            sliceIndex = $sliceIndex
            sliceCount = $sliceCount
            eligibleCount = $orderedEligible.Count
        }
        rows = @($rows.ToArray())
        errors = @()
        note = "Opt-in: one slice of the eligible GitHub release assets per UTC week, capped by count and bytes, compared with matching SHA-256 sidecars. A checksum mismatch, a body bigger than its published size, or a host or redirect the outbound safety check refused fails the run; an asset that can't be reached is a warning. Default releaseTrust remains metadata-only."
    }
}

function Test-HasDownloadableReleaseAsset {
    param([string[]]$AssetKinds)

    return @($AssetKinds | Where-Object { $_ -ne "source-archive" }).Count -gt 0
}

function Get-ExecutableReleaseAssetKinds {
    param([string[]]$AssetKinds)

    $executableKinds = @("apk", "crx", "deb", "dmg", "exe", "jar", "rpm", "script", "userscript", "xpi", "zip")
    return @($AssetKinds | Where-Object { $_ -in $executableKinds } | Sort-Object { ConvertTo-OrdinalSortKey $_ } -Unique)
}

function Test-ChecksumCoverageForExecutableAssets {
    param(
        [string[]]$ExecutableAssetNames,
        [string[]]$ChecksumAssets
    )

    $executables = @($ExecutableAssetNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($executables.Count -eq 0 -or $ChecksumAssets.Count -eq 0) {
        return $false
    }

    $checksums = @($ChecksumAssets | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if (@($checksums | Where-Object { $_ -match '(^|[-_.])(checksums?|sums)([-_.]|$)' }).Count -gt 0) {
        return $true
    }

    foreach ($asset in $executables) {
        $assetLower = ([string]$asset).ToLowerInvariant()
        $stemLower = [System.IO.Path]::GetFileNameWithoutExtension($assetLower)
        $matched = @($checksums | Where-Object { $_.Contains($assetLower) -or (-not [string]::IsNullOrWhiteSpace($stemLower) -and $_.Contains($stemLower)) }).Count -gt 0
        if (-not $matched) {
            return $false
        }
    }

    return $true
}

function New-ReleaseTrust {
    param(
        [string[]]$AssetKinds,
        [string[]]$AssetNames,
        [bool]$HasRelease,
        [bool]$AssetInspected,
        [object]$Immutable = $null,
        [hashtable]$AssetDigests = @{}
    )

    $names = @($AssetNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $checksumAssets = @($names | Where-Object { $_ -match '(?i)(sha256|sha512|checksum|checksums|sums|\.sha256|\.sha512)' } | Sort-Object { ConvertTo-OrdinalSortKey $_ })
    $signatureAssets = @($names | Where-Object { $_ -match '(?i)(\.sig$|\.asc$|signature|signatures)' } | Sort-Object { ConvertTo-OrdinalSortKey $_ })
    $sbomAssets = @($names | Where-Object { $_ -match '(?i)(sbom|spdx|cyclonedx)' } | Sort-Object { ConvertTo-OrdinalSortKey $_ })
    $attestationAssets = @($names | Where-Object { $_ -match '(?i)(attestation|intoto|in-toto|\.att$)' } | Sort-Object { ConvertTo-OrdinalSortKey $_ })
    $debugArtifactPresent = [bool](@($names | Where-Object { $_ -match '(?i)(^|[-_.])debug([-_.]|$)' }).Count)
    $executableAssetKinds = @(Get-ExecutableReleaseAssetKinds -AssetKinds $AssetKinds)
    $executableAssetNames = @(
        $names |
            Where-Object {
                $assetKind = @(Get-ReleaseAssetKinds -AssetNames @([string]$_))
                @(Get-ExecutableReleaseAssetKinds -AssetKinds $assetKind).Count -gt 0
            }
    )
    $hasChecksumForEveryExecutable = Test-ChecksumCoverageForExecutableAssets -ExecutableAssetNames $executableAssetNames -ChecksumAssets $checksumAssets
    $sourceOnlyRelease = [bool]($HasRelease -and $AssetInspected -and @($AssetKinds).Count -eq 1 -and $AssetKinds[0] -eq "source-archive")

    $trustLevel = "unknown"
    if ($HasRelease -and $AssetInspected) {
        $trustLevel = "metadata-only"
        if ($checksumAssets.Count -gt 0) {
            $trustLevel = "checksum-metadata"
        }
        if ($signatureAssets.Count -gt 0) {
            $trustLevel = "signature-metadata"
        }
        if ($attestationAssets.Count -gt 0) {
            $trustLevel = "attestation-metadata"
        }
        if ($signatureAssets.Count -gt 0 -and $attestationAssets.Count -gt 0) {
            $trustLevel = "signature-and-attestation-metadata"
        }
    }

    $checksumCoverage = "none"
    if ($checksumAssets.Count -gt 0) {
        $checksumCoverage = if ($hasChecksumForEveryExecutable -and $executableAssetNames.Count -gt 0) { "full" } else { "partial" }
    }

    return [ordered]@{
        checksumAssets = @($checksumAssets)
        checksumCoverage = $checksumCoverage
        hasChecksumForEveryExecutable = $hasChecksumForEveryExecutable
        signatureAssets = @($signatureAssets)
        hasAuthenticodeSignature = $null
        apkSignatureVerified = $null
        sbomAssets = @($sbomAssets)
        attestationAvailable = [bool]($attestationAssets.Count -gt 0)
        debugArtifactPresent = $debugArtifactPresent
        sourceOnlyRelease = $sourceOnlyRelease
        executableAssetKinds = @($executableAssetKinds)
        trustLevel = $trustLevel
        platformDigestCount = if ($HasRelease) { [int]$AssetDigests.Count } else { 0 }
        releaseImmutable = if ($HasRelease -and $null -ne $Immutable) { [bool]$Immutable } else { $null }
        notesPublic = if ($HasRelease -and $AssetInspected) { "Metadata evidence only: derived from release asset filenames and GitHub release API asset digests; binaries were not downloaded or locally verified." } else { $null }
    }
}

function Get-EffectiveDownloadKind {
    param(
        [hashtable]$Entry,
        [string]$Category
    )

    $kind = ([string]$Entry.downloadKind).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($kind)) {
        switch ($Category) {
            "android" { $kind = "apk" }
            "extensions" { $kind = "download" }
            "desktop" { $kind = "zip" }
            default { $kind = "download" }
        }
    }
    return $kind
}

function Get-ExpectedReleaseAssetKinds {
    param(
        [hashtable]$Entry,
        [string]$Category
    )

    $kind = Get-EffectiveDownloadKind -Entry $Entry -Category $Category
    switch ($kind) {
        "apk" { return @("apk") }
        "exe" { return @("exe") }
        "zip" { return @("zip") }
        "zip-xpi" { return @("zip", "xpi") }
        "crx" { return @("crx") }
        "xpi" { return @("xpi") }
        "crx-xpi" { return @("crx", "xpi") }
        "download" { return @("downloadable") }
        default { return @($kind) }
    }
}

function Test-ReleaseAssetKindMatch {
    param(
        [string[]]$ExpectedKinds,
        [string[]]$ActualKinds
    )

    if (@($ExpectedKinds).Count -eq 0) {
        return $true
    }
    if (@($ExpectedKinds | Where-Object { $_ -eq "downloadable" }).Count -gt 0) {
        return Test-HasDownloadableReleaseAsset -AssetKinds $ActualKinds
    }
    foreach ($kind in @($ExpectedKinds)) {
        if (@($ActualKinds | Where-Object { $_ -eq $kind }).Count -eq 0) {
            return $false
        }
    }
    return $true
}

function Test-ReleaseAssetDrift {
    param(
        [hashtable[]]$Entries,
        [hashtable]$RepoLookup
    )

    $missingReleaseForDownloadKind = New-Object System.Collections.Generic.List[object]
    $sourceOnlyWithRelease = New-Object System.Collections.Generic.List[object]
    $releaseActionLabelMismatches = New-Object System.Collections.Generic.List[object]
    $releaseAssetKindMismatches = New-Object System.Collections.Generic.List[object]
    $releaseAssetFetchFailures = New-Object System.Collections.Generic.List[object]
    $userscriptKindWithoutInstallUrl = New-Object System.Collections.Generic.List[object]
    $executableDownloadsMissingChecksums = New-Object System.Collections.Generic.List[object]
    $executableDownloadCandidates = New-Object System.Collections.Generic.List[object]
    $debugArtifactRows = New-Object System.Collections.Generic.List[object]
    $releaseAssetKindCounts = @{}
    $trustLevelCounts = @{}
    $immutableReleaseCount = 0
    $mutableReleaseCount = 0
    $digestCoverageCount = 0
    $releaseBearingRows = 0
    $releaseActionRows = 0
    $inspectedReleaseRows = 0

    foreach ($entry in @($Entries | Sort-Object repo)) {
        $meta = Get-RepoMeta $entry $RepoLookup
        $hasRelease = [bool]($meta -and $meta.latestRelease)
        $downloadKind = Get-EffectiveDownloadKind -Entry $entry -Category $entry.category
        $explicitDownloadKind = ([string]$entry.downloadKind).ToLowerInvariant()
        $action = Get-PrimaryAction $entry $meta $entry.category
        $assetKinds = if ($hasRelease) { @(Get-ReleaseAssetKindsFromMeta -Meta $meta) } else { @() }
        $assetNames = if ($hasRelease) { @(Get-ReleaseAssetNamesFromMeta -Meta $meta) } else { @() }
        $assetInspected = (Test-ReleaseAssetMetadataInspected -Meta $meta)
        $releaseImmutable = if ($hasRelease) { Get-MemberValue -Object $meta.latestRelease -Name "immutable" } else { $null }
        $releaseDigestsForDrift = if ($hasRelease) { $d = Get-MemberValue -Object $meta.latestRelease -Name "releaseAssetDigests"; if ($d -is [hashtable]) { $d } else { @{} } } else { @{} }
        $releaseTrust = New-ReleaseTrust -AssetKinds $assetKinds -AssetNames $assetNames -HasRelease $hasRelease -AssetInspected $assetInspected -Immutable $releaseImmutable -AssetDigests $releaseDigestsForDrift
        $trustLevel = [string]$releaseTrust.trustLevel
        if (-not $trustLevelCounts.ContainsKey($trustLevel)) {
            $trustLevelCounts[$trustLevel] = 0
        }
        $trustLevelCounts[$trustLevel]++

        if ($hasRelease) {
            $releaseBearingRows++
            if ($releaseTrust.releaseImmutable -eq $true) { $immutableReleaseCount++ }
            elseif ($releaseTrust.releaseImmutable -eq $false) { $mutableReleaseCount++ }
            if ([int]$releaseTrust.platformDigestCount -gt 0) { $digestCoverageCount++ }
            if ($assetInspected) {
                $inspectedReleaseRows++
                foreach ($kind in @($assetKinds)) {
                    if (-not $releaseAssetKindCounts.ContainsKey($kind)) {
                        $releaseAssetKindCounts[$kind] = 0
                    }
                    $releaseAssetKindCounts[$kind]++
                }
            } else {
                $release = Get-MemberValue -Object $meta -Name "latestRelease"
                $fetchError = Get-MemberValue -Object $release -Name "releaseAssetFetchError"
                if (-not [string]::IsNullOrWhiteSpace([string]$fetchError)) {
                    $releaseAssetFetchFailures.Add([ordered]@{
                        repo = [string]$entry.repo
                        latestReleaseTag = [string]$meta.latestRelease.tagName
                        error = [string]$fetchError
                    })
                }
            }
        }
        if ($action["kind"] -eq "release") {
            $releaseActionRows++
            $expectedLabel = Get-DownloadLabel $entry $entry.category
            if ([string]$action["label"] -ne [string]$expectedLabel) {
                $releaseActionLabelMismatches.Add([ordered]@{
                    repo = [string]$entry.repo
                    downloadKind = if ([string]::IsNullOrWhiteSpace($downloadKind)) { $null } else { $downloadKind }
                    expectedLabel = [string]$expectedLabel
                    actualLabel = [string]$action["label"]
                })
            }
            if (@($releaseTrust.executableAssetKinds).Count -gt 0 -and $releaseTrust.hasChecksumForEveryExecutable -ne $true) {
                $executableDownloadsMissingChecksums.Add([ordered]@{
                    repo = [string]$entry.repo
                    latestReleaseTag = if ($meta -and $meta.latestRelease) { [string]$meta.latestRelease.tagName } else { $null }
                    executableAssetKinds = @($releaseTrust.executableAssetKinds)
                    trustLevel = [string]$releaseTrust.trustLevel
                })
            }
            if ($releaseTrust.debugArtifactPresent) {
                $debugArtifactRows.Add([ordered]@{
                    repo = [string]$entry.repo
                    latestReleaseTag = if ($meta -and $meta.latestRelease) { [string]$meta.latestRelease.tagName } else { $null }
                    trustLevel = [string]$releaseTrust.trustLevel
                })
            }
            if (@($releaseTrust.executableAssetKinds).Count -gt 0) {
                $hasChecksum = [bool]$releaseTrust.hasChecksumForEveryExecutable -and @($releaseTrust.checksumAssets).Count -gt 0
                $checksumCoverage = [string]$releaseTrust.checksumCoverage
                $hasPlatformDigest = [bool]([int]$releaseTrust.platformDigestCount -gt 0)
                $hasSbom = @($releaseTrust.sbomAssets).Count -gt 0
                $hasAttestation = [bool]$releaseTrust.attestationAvailable
                $hasMetadataEvidence = $hasChecksum -or $hasPlatformDigest
                $isImmutable = [bool]($releaseTrust.releaseImmutable -eq $true)
                # Build-provenance attestation needs a GitHub Actions OIDC token and this
                # repository bans Actions, so it can never be earned here. Scoring and
                # ranking on it made every row permanently incomplete and put an
                # impossible instruction at the top of the list. Rank on what the
                # maintainer can actually do: checksums first, then immutability, then SBOM.
                $gapScore = 0
                if (-not $hasChecksum) { $gapScore += 2 }
                if (-not $isImmutable) { $gapScore++ }
                if (-not $hasSbom) { $gapScore++ }
                $nextAction = if (-not $hasChecksum) {
                    "publish-sha256-checksums"
                } elseif (-not $isImmutable) {
                    "enable-immutable-releases"
                } elseif (-not $hasSbom) {
                    "publish-sbom"
                } else {
                    "no-action-needed"
                }
                $readinessLevel = if ($hasChecksum -and $isImmutable -and $hasSbom) {
                    "metadata-complete"
                } elseif ($hasSbom) {
                    "sbom-metadata"
                } elseif ($isImmutable) {
                    "immutable-metadata"
                } elseif ($hasMetadataEvidence) {
                    "digest-metadata"
                } else {
                    "no-metadata-evidence"
                }
                $executableDownloadCandidates.Add([ordered]@{
                        repo = [string]$entry.repo
                        stars = if ($meta) { [int]$meta.stargazerCount } else { 0 }
                        latestReleaseTag = if ($meta -and $meta.latestRelease) { [string]$meta.latestRelease.tagName } else { $null }
                        executableAssetKinds = @($releaseTrust.executableAssetKinds)
                        trustLevel = [string]$releaseTrust.trustLevel
                        evidenceSource = "release-metadata-only"
                        hasChecksum = [bool]$hasChecksum
                        checksumCoverage = [string]$checksumCoverage
                        hasPlatformDigest = [bool]$hasPlatformDigest
                        hasMetadataEvidence = [bool]$hasMetadataEvidence
                        hasSbom = [bool]$hasSbom
                        hasAttestation = [bool]$hasAttestation
                        isImmutable = [bool]$isImmutable
                        readinessLevel = $readinessLevel
                        gapScore = [int]$gapScore
                        nextAction = $nextAction
                    })
            }
        }

        if ($hasRelease -and $downloadKind -eq "repo") {
            $sourceOnlyWithRelease.Add([ordered]@{
                repo = [string]$entry.repo
                latestReleaseTag = [string]$meta.latestRelease.tagName
                releaseAssetKinds = @($assetKinds)
            })
        }

        if (-not $hasRelease -and -not [string]::IsNullOrWhiteSpace($explicitDownloadKind) -and $explicitDownloadKind -notin @("repo", "userscript")) {
            $missingReleaseForDownloadKind.Add([ordered]@{
                repo = [string]$entry.repo
                downloadKind = $explicitDownloadKind
            })
        }

        if ($hasRelease -and $assetInspected -and -not [string]::IsNullOrWhiteSpace($explicitDownloadKind) -and $explicitDownloadKind -notin @("repo", "userscript")) {
            $expectedKinds = @(Get-ExpectedReleaseAssetKinds -Entry $entry -Category $entry.category)
            if (-not (Test-ReleaseAssetKindMatch -ExpectedKinds $expectedKinds -ActualKinds $assetKinds)) {
                $releaseAssetKindMismatches.Add([ordered]@{
                    repo = [string]$entry.repo
                    downloadKind = $explicitDownloadKind
                    expectedAssetKinds = @($expectedKinds)
                    releaseAssetKinds = @($assetKinds)
                    releaseAssetNames = @($assetNames)
                    primaryAction = [string]$action["kind"]
                })
            }
        }

        if ($downloadKind -eq "userscript" -and [string]::IsNullOrWhiteSpace([string]$entry.userscriptUrl)) {
            $userscriptKindWithoutInstallUrl.Add([ordered]@{
                repo = [string]$entry.repo
                downloadKind = $downloadKind
            })
        }
    }

    $kindCounts = @(
        $releaseAssetKindCounts.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    kind = [string]$_.Key
                    count = [int]$_.Value
                }
            }
    )
    $trustCounts = @(
        $trustLevelCounts.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    trustLevel = [string]$_.Key
                    count = [int]$_.Value
                }
            }
    )

    # Prioritized executable-download trust starter lane: rank executable-bearing
    # download repos by how much verifiable supply-chain evidence they are missing
    # (checksums, then attestation, then SBOM), then by reach (stars). This keeps
    # filename-derived heuristics distinct from a "checksum/SBOM/attestation present"
    # signal so adoption work can start with the highest-impact rows first.
    $shortlistSoftCap = 10
    $rankedCandidates = @(
        $executableDownloadCandidates.ToArray() |
            Sort-Object -Property `
                @{ Expression = { [int]$_.gapScore }; Descending = $true }, `
                @{ Expression = { [int]$_.stars }; Descending = $true }, `
                @{ Expression = { [string]$_.repo }; Descending = $false }
    )
    $shortlistRows = New-Object System.Collections.Generic.List[object]
    $rank = 0
    foreach ($candidate in $rankedCandidates) {
        if ($shortlistRows.Count -ge $shortlistSoftCap) { break }
        $rank++
        $row = [ordered]@{ priorityRank = $rank }
        foreach ($property in $candidate.GetEnumerator()) {
            $row[$property.Key] = $property.Value
        }
        $shortlistRows.Add($row)
    }
    # Use Measure-Object for counts: arrays of OrderedDictionary rows otherwise
    # trigger PowerShell member-enumeration on .Count and return per-row counts.
    $executableDownloadCount = ($rankedCandidates | Measure-Object).Count
    $metadataCompleteCount = ($rankedCandidates | Where-Object { [int]$_.gapScore -eq 0 } | Measure-Object).Count
    $checksumGapCount = ($rankedCandidates | Where-Object { -not $_.hasChecksum } | Measure-Object).Count
    $metadataEvidenceGapCount = ($rankedCandidates | Where-Object { -not $_.hasMetadataEvidence } | Measure-Object).Count
    $platformDigestCount = ($rankedCandidates | Where-Object { $_.hasPlatformDigest } | Measure-Object).Count
    $attestationGapCount = ($rankedCandidates | Where-Object { -not $_.hasAttestation } | Measure-Object).Count
    $sbomGapCount = ($rankedCandidates | Where-Object { -not $_.hasSbom } | Measure-Object).Count
    $immutableCount = ($rankedCandidates | Where-Object { $_.isImmutable } | Measure-Object).Count
    $readinessBuckets = @{}
    foreach ($candidate in @($rankedCandidates)) {
        $level = [string]$candidate.readinessLevel
        if (-not $readinessBuckets.ContainsKey($level)) { $readinessBuckets[$level] = 0 }
        $readinessBuckets[$level]++
    }
    $readinessCounts = @(foreach ($level in @("metadata-complete", "attestation-metadata", "sbom-metadata", "immutable-metadata", "digest-metadata", "no-metadata-evidence")) {
        if ($readinessBuckets.ContainsKey($level)) {
            [ordered]@{ readinessLevel = $level; count = [int]$readinessBuckets[$level] }
        }
    })
    $shortlistTruncatedCount = [int]$executableDownloadCount - [int]$shortlistRows.Count
    if ($shortlistTruncatedCount -lt 0) { $shortlistTruncatedCount = 0 }
    $executableDownloadTrustShortlist = [ordered]@{
        evidenceSource = "release-metadata-only"
        executableDownloadCount = [int]$executableDownloadCount
        metadataCompleteCount = [int]$metadataCompleteCount
        checksumGapCount = [int]$checksumGapCount
        metadataEvidenceGapCount = [int]$metadataEvidenceGapCount
        platformDigestCount = [int]$platformDigestCount
        attestationGapCount = [int]$attestationGapCount
        attestationAchievable = $false
        attestationUnachievableReason = "Build-provenance attestation requires a GitHub Actions OIDC token to mint the signing certificate, and this repository ships no workflows by policy. SHA-256 sidecars and immutable releases are the achievable ceiling."
        sbomGapCount = [int]$sbomGapCount
        immutableCount = [int]$immutableCount
        readinessCounts = @($readinessCounts)
        shortlistSoftCap = [int]$shortlistSoftCap
        truncatedCount = [int]$shortlistTruncatedCount
        rows = @($shortlistRows.ToArray())
        note = "Metadata evidence records filename-derived sidecar checksums, SBOM filenames, and GitHub platform asset digests; no binaries were downloaded or locally verified. attestationGapCount is reported for completeness only; see attestationUnachievableReason."
    }

    return [ordered]@{
        checkedCatalogRows = @($Entries).Count
        releaseBearingRows = $releaseBearingRows
        releaseActionRows = $releaseActionRows
        assetApiInspected = ($inspectedReleaseRows -gt 0)
        inspectedReleaseRows = $inspectedReleaseRows
        releaseAssetKindCounts = $kindCounts
        releaseTrustLevelCounts = $trustCounts
        releaseImmutability = [ordered]@{
            immutableCount = [int]$immutableReleaseCount
            mutableCount = [int]$mutableReleaseCount
            unknownCount = [int]($releaseBearingRows - $immutableReleaseCount - $mutableReleaseCount)
        }
        platformDigestCoverage = [ordered]@{
            withDigestCount = [int]$digestCoverageCount
            withoutDigestCount = [int]($releaseBearingRows - $digestCoverageCount)
        }
        executableDownloadTrustShortlist = $executableDownloadTrustShortlist
        executableDownloadsMissingChecksums = $executableDownloadsMissingChecksums.ToArray()
        debugArtifactRows = $debugArtifactRows.ToArray()
        sourceOnlyWithRelease = $sourceOnlyWithRelease.ToArray()
        missingReleaseForDownloadKind = $missingReleaseForDownloadKind.ToArray()
        releaseActionLabelMismatches = $releaseActionLabelMismatches.ToArray()
        releaseAssetKindMismatches = $releaseAssetKindMismatches.ToArray()
        releaseAssetFetchFailures = $releaseAssetFetchFailures.ToArray()
        userscriptKindWithoutInstallUrl = $userscriptKindWithoutInstallUrl.ToArray()
        note = "Release asset filename inspection compares catalog downloadKind labels against uploaded latest-release asset names; source-only releases remain repo actions."
    }
}
