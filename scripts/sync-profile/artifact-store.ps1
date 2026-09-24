# Durable local state: atomic writes, the journaled artifact publication transaction,
# the repository run lock, the validation cache and the complete generation snapshot
# that offline writes replay. Dot-sourced by scripts/sync-profile.ps1.

function Write-AtomicUtf8TextFile {
    <#
    .SYNOPSIS
    Publishes one UTF-8 text file with a same-directory atomic replacement.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "Cannot determine the parent directory for atomic publication: $Path"
    }
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null

    $transactionId = [guid]::NewGuid().ToString('N')
    $fileName = [System.IO.Path]::GetFileName($fullPath)
    $stagedPath = Join-Path $directory ".$fileName.$transactionId.stage"
    $backupPath = Join-Path $directory ".$fileName.$transactionId.backup"
    $targetExisted = [System.IO.File]::Exists($fullPath)
    $published = $false
    try {
        [System.IO.File]::WriteAllText($stagedPath, $Content, [System.Text.UTF8Encoding]::new($false))
        $expectedHash = Get-Utf8TextSha256Hex -Text $Content
        $stagedHash = Get-FileSha256Hex -Path $stagedPath
        if ($stagedHash -ne $expectedHash) {
            throw "Staged content hash mismatch for $fullPath."
        }

        if ([System.IO.File]::Exists($fullPath)) {
            [System.IO.File]::Replace($stagedPath, $fullPath, $backupPath, $true)
        } else {
            [System.IO.File]::Move($stagedPath, $fullPath)
        }

        if ((Get-FileSha256Hex -Path $fullPath) -ne $expectedHash) {
            throw "Published content hash mismatch for $fullPath."
        }
        $published = $true
    } catch {
        if ([System.IO.File]::Exists($backupPath)) {
            if ([System.IO.File]::Exists($fullPath)) {
                $discardPath = "$backupPath.discard"
                [System.IO.File]::Delete($discardPath)
                [System.IO.File]::Replace($backupPath, $fullPath, $discardPath, $true)
                [System.IO.File]::Delete($discardPath)
            } else {
                [System.IO.File]::Move($backupPath, $fullPath)
            }
        } elseif (-not $targetExisted -and -not $published -and [System.IO.File]::Exists($fullPath)) {
            [System.IO.File]::Delete($fullPath)
        }
        throw
    } finally {
        [System.IO.File]::Delete($stagedPath)
        [System.IO.File]::Delete($backupPath)
    }
}

function Get-ProfileAssetFileContents {
    <#
    .SYNOPSIS
    Reads every file under -AssetsPath, keyed by the relative path generated assets use.
    .DESCRIPTION
    -Force includes hidden files and dotfiles: git commits them like any other file, so
    the stray-asset gate has to see them too.
    .PARAMETER Path
    Asset directory, repository-relative or absolute; defaults to the -AssetsPath parameter.
    #>
    [CmdletBinding()]
    param([string]$Path = $script:AssetsPath)

    $contents = @{}
    $assetRoot = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }
    if (-not (Test-Path -LiteralPath $assetRoot -PathType Container)) {
        return $contents
    }
    $assetPathPrefix = ($Path -replace '\\', '/').TrimEnd('/')
    foreach ($file in @(Get-ChildItem -LiteralPath $assetRoot -File -Recurse -Force | Sort-Object FullName)) {
        $relativePath = [System.IO.Path]::GetRelativePath($assetRoot, $file.FullName) -replace '\\', '/'
        $contents["$assetPathPrefix/$relativePath"] = [string](Get-Content -LiteralPath $file.FullName -Raw)
    }
    return $contents
}

function Get-ArtifactPublicationTransactionRoot {
    $cacheRoot = Get-ValidationCacheRoot
    if ([string]::IsNullOrWhiteSpace($cacheRoot)) {
        $cacheRoot = Join-Path $RepoRoot '.cache/profile-sync'
    }

    return (Join-Path $cacheRoot 'transactions')
}

function Enter-ProfileSyncRunLock {
    <#
    .SYNOPSIS
    Serializes profile sync runs before they can inspect or publish shared artifacts.
    #>
    [CmdletBinding()]
    param(
        [string]$LockPath = (Join-Path (Split-Path -Parent (Get-ArtifactPublicationTransactionRoot)) 'run.lock'),

        [ValidateRange(0, 3600)]
        [int]$TimeoutSeconds = 900
    )

    $fullPath = [System.IO.Path]::GetFullPath($LockPath)
    $directory = Split-Path -Parent $fullPath
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "Cannot determine the parent directory for the profile sync lock: $LockPath"
    }
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $waitWarningWritten = $false
    while ($true) {
        $stream = $null
        try {
            $stream = [System.IO.FileStream]::new(
                $fullPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            $lockMetadata = [ordered]@{
                processId = $PID
                acquiredAt = [DateTime]::UtcNow.ToString('o')
                repoRoot = $RepoRoot
            } | ConvertTo-Json -Compress
            $lockBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($lockMetadata + [Environment]::NewLine)
            $stream.SetLength(0)
            $stream.Position = 0
            $stream.Write($lockBytes, 0, $lockBytes.Length)
            $stream.Flush($true)
            return $stream
        } catch [System.IO.IOException] {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
            if ([DateTime]::UtcNow -ge $deadline) {
                throw "Another profile sync process is already running and still owns the publication lock after $TimeoutSeconds second(s): $fullPath"
            }
            if (-not $waitWarningWritten) {
                Write-Warning "Another profile sync process is already running. Waiting up to $TimeoutSeconds seconds for its publication lock."
                $waitWarningWritten = $true
            }
            Start-Sleep -Milliseconds 250
        } catch {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
            throw
        }
    }
}

function Write-ArtifactPublicationJournal {
    param([object]$Transaction)

    $journalPath = [string](Get-MemberValue -Object $Transaction -Name 'journalPath')
    if ([string]::IsNullOrWhiteSpace($journalPath)) {
        throw 'Artifact publication transaction has no journal path.'
    }

    $journalJson = $Transaction | ConvertTo-Json -Depth 12
    Write-AtomicUtf8TextFile -Path $journalPath -Content ($journalJson + [Environment]::NewLine)
}

function Add-ArtifactPublicationRows {
    param(
        [Parameter(Mandatory)]
        [object]$Transaction,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Artifacts
    )

    $rows = $null
    if ($Transaction -is [System.Collections.IDictionary]) {
        $rows = $Transaction['artifacts']
    } else {
        $rows = $Transaction.PSObject.Properties['artifacts'].Value
    }
    if ($null -eq $rows) {
        throw 'Artifact publication transaction has no artifact collection.'
    }

    foreach ($artifact in @($Artifacts)) {
        $path = [string](Get-MemberValue -Object $artifact -Name 'path')
        $content = [string](Get-MemberValue -Object $artifact -Name 'content')
        $isReport = [bool](Get-MemberValue -Object $artifact -Name 'isReport')
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw 'Artifact publication requires a non-empty target path.'
        }

        $targetPath = [System.IO.Path]::GetFullPath($path)
        foreach ($existingRow in @($rows)) {
            $existingTarget = [string](Get-MemberValue -Object $existingRow -Name 'targetPath')
            if ([string]::Equals($existingTarget, $targetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Artifact publication target is duplicated: $targetPath"
            }
        }

        if ($isReport -and @($rows | Where-Object { [bool](Get-MemberValue -Object $_ -Name 'isReport') }).Count -gt 0) {
            throw 'Artifact publication supports exactly one report target per transaction.'
        }

        $directory = Split-Path -Parent $targetPath
        if ([string]::IsNullOrWhiteSpace($directory)) {
            throw "Cannot determine the parent directory for artifact target: $targetPath"
        }
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null

        $transactionId = [string](Get-MemberValue -Object $Transaction -Name 'transactionId')
        $fileName = [System.IO.Path]::GetFileName($targetPath)
        $stagedPath = Join-Path $directory ".$fileName.$transactionId.stage"
        $backupPath = Join-Path $directory ".$fileName.$transactionId.backup"
        $existed = [System.IO.File]::Exists($targetPath)
        $row = [ordered]@{
            targetPath = $targetPath
            stagedPath = $stagedPath
            backupPath = $backupPath
            existed = $existed
            oldHash = if ($existed) { Get-FileSha256Hex -Path $targetPath } else { $null }
            newHash = $null
            isReport = $isReport
            promoted = $false
        }
        $rows.Add($row) | Out-Null
        Write-ArtifactPublicationJournal -Transaction $Transaction

        [System.IO.File]::WriteAllText($stagedPath, $content, [System.Text.UTF8Encoding]::new($false))
        $row.newHash = Get-Utf8TextSha256Hex -Text $content
        $stagedHash = Get-FileSha256Hex -Path $stagedPath
        if ($stagedHash -ne $row.newHash) {
            throw "Staged artifact hash mismatch for $targetPath."
        }
        Write-ArtifactPublicationJournal -Transaction $Transaction
    }
}

function New-ArtifactPublicationTransaction {
    <#
    .SYNOPSIS
    Stages and journals a set of generated artifacts before any target changes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        [string]$TransactionRoot = (Get-ArtifactPublicationTransactionRoot)
    )

    if (@($Artifacts).Count -eq 0) {
        throw 'Artifact publication requires at least one target.'
    }

    $root = [System.IO.Path]::GetFullPath($TransactionRoot)
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    $transactionId = [guid]::NewGuid().ToString('N')
    $transaction = [ordered]@{
        schemaVersion = 1
        transactionId = $transactionId
        state = 'staging'
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
        journalPath = (Join-Path $root "$transactionId.json")
        artifacts = [System.Collections.Generic.List[object]]::new()
    }

    Write-ArtifactPublicationJournal -Transaction $transaction
    try {
        Add-ArtifactPublicationRows -Transaction $transaction -Artifacts $Artifacts
        $transaction.state = 'ready'
        Write-ArtifactPublicationJournal -Transaction $transaction
        return $transaction
    } catch {
        try {
            Repair-ArtifactPublicationTransactions -TransactionRoot $root | Out-Null
        } catch {
            Write-Warning "Artifact staging cleanup failed: $($_.Exception.Message)"
        }
        throw
    }
}

function Publish-ArtifactPublicationTransaction {
    <#
    .SYNOPSIS
    Promotes staged artifacts, with the report ordered after every other target.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Transaction,

        [ValidateRange(0, 10000)]
        [int]$FaultAfterPromotion = 0
    )

    $state = [string](Get-MemberValue -Object $Transaction -Name 'state')
    if (-not @('ready', 'publishing').Contains($state)) {
        throw "Cannot publish transaction in state '$state'."
    }

    Set-MemberValue -Object $Transaction -Name 'state' -Value 'publishing'
    Write-ArtifactPublicationJournal -Transaction $Transaction
    $rows = @(Get-JsonArrayItems (Get-MemberValue -Object $Transaction -Name 'artifacts'))
    $orderedRows = @($rows | Where-Object { -not [bool](Get-MemberValue -Object $_ -Name 'isReport') }) +
        @($rows | Where-Object { [bool](Get-MemberValue -Object $_ -Name 'isReport') })
    $promotionCount = @($rows | Where-Object { [bool](Get-MemberValue -Object $_ -Name 'promoted') }).Count

    foreach ($row in $orderedRows) {
        if ([bool](Get-MemberValue -Object $row -Name 'promoted')) {
            continue
        }

        $targetPath = [string](Get-MemberValue -Object $row -Name 'targetPath')
        $stagedPath = [string](Get-MemberValue -Object $row -Name 'stagedPath')
        $backupPath = [string](Get-MemberValue -Object $row -Name 'backupPath')
        $oldHash = [string](Get-MemberValue -Object $row -Name 'oldHash')
        $newHash = [string](Get-MemberValue -Object $row -Name 'newHash')
        $existed = [bool](Get-MemberValue -Object $row -Name 'existed')

        if ((Get-FileSha256Hex -Path $stagedPath) -ne $newHash) {
            throw "Staged artifact changed before promotion: $targetPath"
        }
        if ($existed) {
            if ((Get-FileSha256Hex -Path $targetPath) -ne $oldHash) {
                throw "Artifact target changed after staging: $targetPath"
            }
            [System.IO.File]::Replace($stagedPath, $targetPath, $backupPath, $true)
        } else {
            if ([System.IO.File]::Exists($targetPath)) {
                throw "New artifact target appeared after staging: $targetPath"
            }
            [System.IO.File]::Move($stagedPath, $targetPath)
        }

        if ((Get-FileSha256Hex -Path $targetPath) -ne $newHash) {
            throw "Published artifact hash mismatch for $targetPath."
        }
        Set-MemberValue -Object $row -Name 'promoted' -Value $true
        $promotionCount++
        Write-ArtifactPublicationJournal -Transaction $Transaction
        if ($FaultAfterPromotion -gt 0 -and $promotionCount -eq $FaultAfterPromotion) {
            throw "Injected artifact publication failure after promotion $promotionCount."
        }
    }
}

function Remove-ArtifactPublicationResidue {
    param(
        [object]$Transaction,
        [switch]$RemoveJournal
    )

    foreach ($row in @(Get-JsonArrayItems (Get-MemberValue -Object $Transaction -Name 'artifacts'))) {
        $stagedPath = [string](Get-MemberValue -Object $row -Name 'stagedPath')
        $backupPath = [string](Get-MemberValue -Object $row -Name 'backupPath')
        if (-not [string]::IsNullOrWhiteSpace($stagedPath)) {
            [System.IO.File]::Delete($stagedPath)
        }
        if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
            [System.IO.File]::Delete($backupPath)
        }
    }
    if ($RemoveJournal) {
        [System.IO.File]::Delete([string](Get-MemberValue -Object $Transaction -Name 'journalPath'))
    }
}

function Complete-ArtifactPublicationTransaction {
    <#
    .SYNOPSIS
    Commits a fully promoted artifact set and removes transaction residue.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Transaction)

    foreach ($row in @(Get-JsonArrayItems (Get-MemberValue -Object $Transaction -Name 'artifacts'))) {
        $targetPath = [string](Get-MemberValue -Object $row -Name 'targetPath')
        $newHash = [string](Get-MemberValue -Object $row -Name 'newHash')
        if (-not [bool](Get-MemberValue -Object $row -Name 'promoted') -or (Get-FileSha256Hex -Path $targetPath) -ne $newHash) {
            throw "Cannot commit an incomplete artifact publication transaction: $targetPath"
        }
    }

    Set-MemberValue -Object $Transaction -Name 'state' -Value 'committed'
    Write-ArtifactPublicationJournal -Transaction $Transaction
    Remove-ArtifactPublicationResidue -Transaction $Transaction -RemoveJournal
}

function Repair-ArtifactPublicationTransactions {
    <#
    .SYNOPSIS
    Recovers interrupted artifact publications to a complete old or new set.
    #>
    [CmdletBinding()]
    param([string]$TransactionRoot = (Get-ArtifactPublicationTransactionRoot))

    $root = [System.IO.Path]::GetFullPath($TransactionRoot)
    if (-not [System.IO.Directory]::Exists($root)) {
        return 0
    }

    $recovered = 0
    foreach ($journalPath in @([System.IO.Directory]::GetFiles($root, '*.json') | Sort-Object)) {
        $transaction = ConvertFrom-JsonPreservingArrays -Json ([System.IO.File]::ReadAllText($journalPath))
        Set-MemberValue -Object $transaction -Name 'journalPath' -Value $journalPath
        $rows = @(Get-JsonArrayItems (Get-MemberValue -Object $transaction -Name 'artifacts'))
        $state = [string](Get-MemberValue -Object $transaction -Name 'state')
        $keepNew = 'committed'.Equals($state)
        if ($keepNew) {
            foreach ($row in $rows) {
                $targetPath = [string](Get-MemberValue -Object $row -Name 'targetPath')
                $newHash = [string](Get-MemberValue -Object $row -Name 'newHash')
                if ((Get-FileSha256Hex -Path $targetPath) -ne $newHash) {
                    $keepNew = $false
                    break
                }
            }
        }

        if (-not $keepNew) {
            [array]::Reverse($rows)
            foreach ($row in $rows) {
                $targetPath = [string](Get-MemberValue -Object $row -Name 'targetPath')
                $stagedPath = [string](Get-MemberValue -Object $row -Name 'stagedPath')
                $backupPath = [string](Get-MemberValue -Object $row -Name 'backupPath')
                $oldHash = [string](Get-MemberValue -Object $row -Name 'oldHash')
                $newHash = [string](Get-MemberValue -Object $row -Name 'newHash')
                $existed = [bool](Get-MemberValue -Object $row -Name 'existed')
                $promoted = [bool](Get-MemberValue -Object $row -Name 'promoted')
                if ($existed) {
                    $restoredBackup = $false
                    if ([System.IO.File]::Exists($backupPath)) {
                        if ([System.IO.File]::Exists($targetPath)) {
                            $recoveryDiscardPath = "$backupPath.recovery-discard"
                            [System.IO.File]::Delete($recoveryDiscardPath)
                            [System.IO.File]::Replace($backupPath, $targetPath, $recoveryDiscardPath, $true)
                            [System.IO.File]::Delete($recoveryDiscardPath)
                        } else {
                            [System.IO.File]::Move($backupPath, $targetPath)
                        }
                        $restoredBackup = $true
                    } elseif ($promoted -and (Get-FileSha256Hex -Path $targetPath) -ne $oldHash) {
                        throw "Cannot recover artifact because its original backup is unavailable: $targetPath"
                    }
                    # An unpromoted row with no backup never changed its target. Preserve a
                    # newer file written by another process instead of treating it as damage.
                    if (($restoredBackup -or $promoted) -and (Get-FileSha256Hex -Path $targetPath) -ne $oldHash) {
                        throw "Recovered artifact hash mismatch for $targetPath."
                    }
                } elseif ([System.IO.File]::Exists($targetPath)) {
                    $currentHash = Get-FileSha256Hex -Path $targetPath
                    $moveCompletedBeforeJournal = -not [System.IO.File]::Exists($stagedPath) -and $currentHash -eq $newHash
                    if ($promoted -or $moveCompletedBeforeJournal) {
                        if ($currentHash -ne $newHash) {
                            throw "Refusing to remove an unexpected file while recovering: $targetPath"
                        }
                        [System.IO.File]::Delete($targetPath)
                    } elseif (-not [System.IO.File]::Exists($stagedPath)) {
                        throw "Refusing to remove an unexpected file while recovering: $targetPath"
                    }
                }
            }
        }

        Remove-ArtifactPublicationResidue -Transaction $transaction -RemoveJournal
        $recovered++
    }

    foreach ($orphanPath in @([System.IO.Directory]::GetFiles($root))) {
        $orphanName = [System.IO.Path]::GetFileName($orphanPath)
        if ($orphanName -match '^[.].+[.](stage|backup)$') {
            [System.IO.File]::Delete($orphanPath)
        }
    }

    return $recovered
}

function New-ValidationCacheBucket {
    return [ordered]@{
        hitCount = 0
        missCount = 0
        staleCount = 0
        writeCount = 0
        fallbackHitCount = 0
        usedForFallback = $false
        lastFallbackReason = $null
    }
}

function Reset-ValidationCacheState {
    $script:ValidationCacheState = [ordered]@{
        enabled = [bool]$script:CacheEnabled
        path = [string]$script:CachePath
        ttlHours = [int]$script:CacheTtlHours
        metadata = New-ValidationCacheBucket
        releases = New-ValidationCacheBucket
        links = New-ValidationCacheBucket
    }
}

function Get-ValidationCacheState {
    if ($null -eq $script:ValidationCacheState) {
        Reset-ValidationCacheState
    }

    return $script:ValidationCacheState
}

function Add-ValidationCacheCounter {
    param(
        [ValidateSet('metadata', 'releases', 'links')]
        [string]$Bucket,
        [ValidateSet('hitCount', 'missCount', 'staleCount', 'writeCount', 'fallbackHitCount')]
        [string]$Counter,
        [string]$FallbackReason = $null
    )

    $state = Get-ValidationCacheState
    $bucketState = $state[$Bucket]
    $bucketState[$Counter] = [int]$bucketState[$Counter] + 1
    if ('fallbackHitCount'.Equals($Counter)) {
        $bucketState['usedForFallback'] = $true
        if (-not [string]::IsNullOrWhiteSpace($FallbackReason)) {
            $bucketState['lastFallbackReason'] = $FallbackReason
        }
    }
}

function Get-ValidationCacheRoot {
    if ([string]::IsNullOrWhiteSpace([string]$script:CachePath)) {
        return $null
    }
    if ([System.IO.Path]::IsPathRooted([string]$script:CachePath)) {
        return [string]$script:CachePath
    }

    return (Join-Path $RepoRoot ([string]$script:CachePath))
}

function Get-ValidationCacheFilePath {
    param(
        [ValidateSet('metadata', 'releases', 'links')]
        [string]$Bucket,
        [string]$Key
    )

    $root = Get-ValidationCacheRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        return $null
    }

    $hash = Get-StringSha256 -Text $Key
    return (Join-Path (Join-Path $root $Bucket) "$hash.json")
}

function Read-ValidationCacheEntry {
    param(
        [ValidateSet('metadata', 'releases', 'links')]
        [string]$Bucket,
        [string]$Key,
        # Returns the entry even when past its TTL so the caller can reuse stored
        # ETag / Last-Modified validators for a conditional revalidation.
        [switch]$IncludeStale,
        # The link bucket decides reuse per status, not on the flat TTL, so it counts
        # its own hits and misses. Counting here too reported a re-probed 404 or 429 as
        # a cache hit.
        [switch]$NoCounters
    )

    if (-not [bool]$script:CacheEnabled) {
        if (-not $NoCounters) { Add-ValidationCacheCounter -Bucket $Bucket -Counter missCount }
        return $null
    }

    $path = Get-ValidationCacheFilePath -Bucket $Bucket -Key $Key
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        if (-not $NoCounters) { Add-ValidationCacheCounter -Bucket $Bucket -Counter missCount }
        return $null
    }

    try {
        $cacheJson = Get-Content -LiteralPath $path -Raw
        $preservedJson = ConvertFrom-JsonPreservingArrays -Json $cacheJson
        $entry = $null
        ConvertTo-JsonSchemaValidationValue -Value $preservedJson -Result ([ref]$entry)
        $fetchedAtText = [string](Get-MemberValue -Object $entry -Name 'fetchedAt')
        $fetchedAt = if ([string]::IsNullOrWhiteSpace($fetchedAtText)) { [datetime]::MinValue } else { [datetime]::Parse($fetchedAtText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
        $ageHours = ((Get-Date).ToUniversalTime() - $fetchedAt.ToUniversalTime()).TotalHours
        Set-MemberValue -Object $entry -Name 'ageHours' -Value ([math]::Round($ageHours, 4))
        if ($ageHours -gt [int]$script:CacheTtlHours) {
            if (-not $NoCounters) { Add-ValidationCacheCounter -Bucket $Bucket -Counter staleCount }
            if (-not $IncludeStale) {
                return $null
            }
            Set-MemberValue -Object $entry -Name 'stale' -Value $true
            return $entry
        }

        Set-MemberValue -Object $entry -Name 'stale' -Value $false
        if (-not $NoCounters) { Add-ValidationCacheCounter -Bucket $Bucket -Counter hitCount }
        return $entry
    } catch {
        if (-not $NoCounters) { Add-ValidationCacheCounter -Bucket $Bucket -Counter missCount }
        return $null
    }
}

function Write-ValidationCacheEntry {
    param(
        [ValidateSet('metadata', 'releases', 'links')]
        [string]$Bucket,
        [string]$Key,
        [AllowNull()]
        [object]$Value,
        [hashtable]$Headers = @{}
    )

    if (-not [bool]$script:CacheEnabled) {
        return
    }

    $path = Get-ValidationCacheFilePath -Bucket $Bucket -Key $Key
    if ([string]::IsNullOrWhiteSpace($path)) {
        return
    }

    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $entry = [ordered]@{
        key = $Key
        fetchedAt = (Get-Date).ToUniversalTime().ToString("o")
        etag = if ($Headers.ContainsKey('ETag')) { [string]$Headers['ETag'] } else { $null }
        lastModified = if ($Headers.ContainsKey('Last-Modified')) { [string]$Headers['Last-Modified'] } else { $null }
        value = $Value
    }

    $entryJson = $entry | ConvertTo-Json -Depth 50
    $cacheTransactionRoot = Get-ArtifactPublicationTransactionRoot
    $cacheTransaction = New-ArtifactPublicationTransaction -TransactionRoot $cacheTransactionRoot -Artifacts @(
        [ordered]@{ path = $path; content = ($entryJson + [Environment]::NewLine); isReport = $false }
    )
    try {
        Publish-ArtifactPublicationTransaction -Transaction $cacheTransaction
        Complete-ArtifactPublicationTransaction -Transaction $cacheTransaction
    } catch {
        try {
            Repair-ArtifactPublicationTransactions -TransactionRoot $cacheTransactionRoot | Out-Null
        } catch {
            Write-Warning "Validation cache rollback failed: $($_.Exception.Message)"
        }
        throw
    }
    Add-ValidationCacheCounter -Bucket $Bucket -Counter writeCount
}

function Get-ValidationCacheValue {
    param(
        [ValidateSet('metadata', 'releases', 'links')]
        [string]$Bucket,
        [string]$Key,
        [string]$FallbackReason = $null
    )

    $entry = Read-ValidationCacheEntry -Bucket $Bucket -Key $Key
    if ($null -eq $entry) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($FallbackReason)) {
        Add-ValidationCacheCounter -Bucket $Bucket -Counter fallbackHitCount -FallbackReason $FallbackReason
    }

    return (Get-MemberValue -Object $entry -Name 'value')
}

function Get-LiveRepositoryMetadataCacheKey {
    return "github-repos-live:${Owner}:$([int]$script:GraphQlPageSize)"
}

function Get-ReleaseMetadataCacheKey {
    param([string]$Repo)

    return "github-release:${Owner}:${Repo}"
}

function Get-LinkProbeCacheKey {
    param([string]$Url)

    return "link-probe:$Url"
}

function Get-CompleteGenerationSnapshotCacheKey {
    <#
    .SYNOPSIS
    Returns the owner-bound cache key for a complete generation snapshot.
    #>
    [CmdletBinding()]
    param()

    return "generation-snapshot:v3:$Owner"
}

function New-CompleteGenerationSnapshot {
    <#
    .SYNOPSIS
    Packages complete, replayable generation inputs for safe offline writes.
    .PARAMETER Repos
    Fully enriched repository metadata from the current online run.
    .PARAMETER ReleaseMetadataComplete
    Confirms that release enrichment completed without a partial-result failure.
    .PARAMETER GenerationTimestamp
    Stable timestamp shared by the snapshot and generated feed during online or offline replay.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Repos,
        [bool]$ReleaseMetadataComplete,
        [string]$GenerationTimestamp = (Get-Date).ToString('o')
    )

    $repoRows = @($Repos | Where-Object { $null -ne $_ })
    $provider = [string]$script:RepositoryMetadataProvider
    $repositoryEnumerationComplete = [bool](
        $repoRows.Count -gt 0 -and
        -not [bool]$script:RepositoryEnumerationTruncated -and
        @('graphql', 'rest-fallback').Contains($provider)
    )
    $releaseRows = @(
        foreach ($repo in $repoRows) {
            [ordered]@{
                repo = [string](Get-MemberValue -Object $repo -Name 'name')
                latestRelease = Get-MemberValue -Object $repo -Name 'latestRelease'
            }
        }
    )
    $releaseDataComplete = [bool]($ReleaseMetadataComplete -and $releaseRows.Count -eq $repoRows.Count)
    $sourceComplete = [bool]($repositoryEnumerationComplete -and $releaseDataComplete)

    return [ordered]@{
        schemaVersion = 3
        owner = [string]$Owner
        fetchedAt = [string]$script:MetadataSnapshotAt
        generationTimestamp = $GenerationTimestamp
        sourceComplete = $sourceComplete
        sourceCompleteness = [ordered]@{
            repositoryEnumeration = $repositoryEnumerationComplete
            releases = $releaseDataComplete
        }
        repositoryEnumeration = [ordered]@{
            provider = $provider
            requestedLimit = [int]$script:RepositoryEnumerationRequestedLimit
            returnedCount = [int]$repoRows.Count
            truncated = [bool]$script:RepositoryEnumerationTruncated
        }
        repositories = $repoRows
        releases = $releaseRows
        restFallbackReleaseFetch = Get-RestFallbackReleaseFetchState
    }
}

function Test-CompleteGenerationSnapshot {
    <#
    .SYNOPSIS
    Validates that a cached snapshot is complete and belongs to the requested owner.
    .PARAMETER Snapshot
    Snapshot value read from the validation cache.
    #>
    [CmdletBinding()]
    param([AllowNull()][object]$Snapshot)

    if ($null -eq $Snapshot -or [int](Get-MemberValue -Object $Snapshot -Name 'schemaVersion') -ne 3) {
        return $false
    }
    $snapshotOwner = [string](Get-MemberValue -Object $Snapshot -Name 'owner')
    if (-not $snapshotOwner.Equals([string]$Owner, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (-not (ConvertTo-BooleanValue (Get-MemberValue -Object $Snapshot -Name 'sourceComplete'))) {
        return $false
    }

    $fetchedAt = [string](Get-MemberValue -Object $Snapshot -Name 'fetchedAt')
    if ([string]::IsNullOrWhiteSpace($fetchedAt)) {
        return $false
    }
    try {
        [void][DateTimeOffset]::Parse($fetchedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        return $false
    }
    $generationTimestamp = [string](Get-MemberValue -Object $Snapshot -Name 'generationTimestamp')
    try {
        [void][DateTimeOffset]::Parse($generationTimestamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        return $false
    }

    $completeness = Get-MemberValue -Object $Snapshot -Name 'sourceCompleteness'
    foreach ($field in @('repositoryEnumeration', 'releases')) {
        if (-not (ConvertTo-BooleanValue (Get-MemberValue -Object $completeness -Name $field))) {
            return $false
        }
    }

    $enumeration = Get-MemberValue -Object $Snapshot -Name 'repositoryEnumeration'
    $repositories = @(Get-JsonArrayItems -Value (Get-MemberValue -Object $Snapshot -Name 'repositories'))
    $releases = @(Get-JsonArrayItems -Value (Get-MemberValue -Object $Snapshot -Name 'releases'))
    $provider = [string](Get-MemberValue -Object $enumeration -Name 'provider')
    if ($repositories.Count -eq 0 -or
        [int](Get-MemberValue -Object $enumeration -Name 'returnedCount') -ne $repositories.Count -or
        (ConvertTo-BooleanValue (Get-MemberValue -Object $enumeration -Name 'truncated')) -or
        -not @('graphql', 'rest-fallback').Contains($provider) -or
        $releases.Count -ne $repositories.Count) {
        return $false
    }

    $repositoryNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $requiredRepositoryFields = @(
        'name',
        'description',
        'stargazerCount',
        'defaultBranchRef',
        'branchTipSha',
        'branchTipFetchedAt',
        'branchTipStatus',
        'branchTipWarning',
        'latestRelease',
        'licenseInfo',
        'isFork',
        'parent',
        'isPrivate',
        'visibility',
        'isArchived',
        'repositoryTopics',
        'pushedAt',
        'url',
        'primaryLanguage'
    )
    foreach ($repository in $repositories) {
        $repositoryName = [string](Get-MemberValue -Object $repository -Name 'name')
        if (-not (Test-SafeGitHubName -Name $repositoryName) -or -not $repositoryNames.Add($repositoryName)) {
            return $false
        }
        foreach ($field in $requiredRepositoryFields) {
            if (-not (Test-MemberExists -Object $repository -Name $field)) {
                return $false
            }
        }
        $starsText = [string](Get-MemberValue -Object $repository -Name 'stargazerCount')
        $stars = [int64]0
        if ($starsText -notmatch '^\d+$' -or -not [int64]::TryParse($starsText, [ref]$stars) -or
            (Get-MemberValue -Object $repository -Name 'isFork') -isnot [bool] -or
            (Get-MemberValue -Object $repository -Name 'isPrivate') -isnot [bool] -or
            (Get-MemberValue -Object $repository -Name 'isArchived') -isnot [bool] -or
            (ConvertTo-BooleanValue (Get-MemberValue -Object $repository -Name 'isPrivate')) -or
            -not [string]::Equals([string](Get-MemberValue -Object $repository -Name 'visibility'), 'PUBLIC', [StringComparison]::OrdinalIgnoreCase) -or
            [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $repository -Name 'url')) -or
            # Ordinal, like the schemas' enums: a restored value is published as written, and
            # -cnotin compares by culture, which skips zero-width and other ignorable characters.
            -not @('fresh', 'stale', 'missing', 'unreachable').Contains([string](Get-MemberValue -Object $repository -Name 'branchTipStatus'))) {
            return $false
        }
    }
    $releaseNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $releaseLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($release in $releases) {
        $releaseRepo = [string](Get-MemberValue -Object $release -Name 'repo')
        if (-not (Test-SafeGitHubName -Name $releaseRepo) -or -not $releaseNames.Add($releaseRepo)) {
            return $false
        }
        $releaseLookup[$releaseRepo] = $release
    }
    if (-not $repositoryNames.SetEquals($releaseNames)) {
        return $false
    }

    foreach ($repository in $repositories) {
        $repositoryName = [string](Get-MemberValue -Object $repository -Name 'name')
        $release = $releaseLookup[$repositoryName]
        if (-not (Test-MemberExists -Object $repository -Name 'latestRelease') -or
            -not (Test-MemberExists -Object $release -Name 'latestRelease') -or
            (ConvertTo-ComparableJson (Get-MemberValue -Object $repository -Name 'latestRelease')) -cne
                (ConvertTo-ComparableJson (Get-MemberValue -Object $release -Name 'latestRelease'))) {
            return $false
        }
    }

    return $true
}

function Write-CompleteGenerationSnapshot {
    <#
    .SYNOPSIS
    Writes a complete online generation snapshot when every required source is present.
    .PARAMETER Repos
    Fully enriched repository metadata from the current online run.
    .PARAMETER ReleaseMetadataComplete
    Confirms that release enrichment completed without a partial-result failure.
    .PARAMETER GenerationTimestamp
    Stable timestamp shared by the snapshot and generated feed during online or offline replay.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Repos,
        [bool]$ReleaseMetadataComplete,
        [string]$GenerationTimestamp = (Get-Date).ToString('o')
    )

    $snapshot = New-CompleteGenerationSnapshot `
        -Repos $Repos `
        -ReleaseMetadataComplete:$ReleaseMetadataComplete `
        -GenerationTimestamp $GenerationTimestamp
    if (-not (Test-CompleteGenerationSnapshot -Snapshot $snapshot)) {
        return $false
    }

    Write-ValidationCacheEntry -Bucket metadata -Key (Get-CompleteGenerationSnapshotCacheKey) -Value $snapshot
    return $true
}

function Get-CompleteGenerationSnapshot {
    <#
    .SYNOPSIS
    Reads a fresh, owner-bound complete generation snapshot from the cache.
    #>
    [CmdletBinding()]
    param()

    $snapshot = Get-ValidationCacheValue `
        -Bucket metadata `
        -Key (Get-CompleteGenerationSnapshotCacheKey) `
        -FallbackReason 'offline complete generation snapshot'
    if (-not (Test-CompleteGenerationSnapshot -Snapshot $snapshot)) {
        return $null
    }

    return $snapshot
}

function Set-GenerationStateFromSnapshot {
    <#
    .SYNOPSIS
    Restores generation provenance and fetch telemetry from a complete snapshot.
    .PARAMETER Snapshot
    Complete snapshot returned by Get-CompleteGenerationSnapshot.
    #>
    [CmdletBinding()]
    param([object]$Snapshot)

    if (-not (Test-CompleteGenerationSnapshot -Snapshot $Snapshot)) {
        throw 'Cannot restore generation state from an incomplete snapshot.'
    }

    $enumeration = Get-MemberValue -Object $Snapshot -Name 'repositoryEnumeration'
    $script:MetadataSnapshotAt = [string](Get-MemberValue -Object $Snapshot -Name 'fetchedAt')
    $script:GenerationArtifactTimestamp = [string](Get-MemberValue -Object $Snapshot -Name 'generationTimestamp')
    $script:RepositoryMetadataProvider = [string](Get-MemberValue -Object $enumeration -Name 'provider')
    $script:RepositoryEnumerationRequestedLimit = [int](Get-MemberValue -Object $enumeration -Name 'requestedLimit')
    $script:RepositoryEnumerationTruncated = [bool](Get-MemberValue -Object $enumeration -Name 'truncated')
    $script:MetadataFetchAttemptCount = 0
    $script:MetadataFetchRequestCount = 0
    $script:MetadataFetchPageSizeReduced = $false
    $script:MetadataFetchFallbackReason = 'complete offline generation snapshot'
    $script:MetadataFetchResourceLimitFallback = $false
    $script:MetadataFetchResourceLimitReason = $null
    $restFallbackState = Get-MemberValue -Object $Snapshot -Name 'restFallbackReleaseFetch'
    if ($null -eq $restFallbackState) {
        Reset-RestFallbackReleaseFetchState
    } else {
        $script:RestFallbackReleaseFetchState = $restFallbackState
    }
}
