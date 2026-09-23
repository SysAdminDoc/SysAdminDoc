# GitHub access for the profile generator: the gh CLI adapter, repository enumeration
# (GraphQL with paginated REST fallback), and release, fork-parent and branch-tip
# enrichment of live repository metadata. Dot-sourced by scripts/sync-profile.ps1.

function Add-GitHubApiVersionArgument {
    <#
    .SYNOPSIS
    Pins REST calls to a known GitHub API calendar version.
    .DESCRIPTION
    GitHub shipped its first breaking REST calendar version (2026-03-10), which drops
    `rate` from /rate_limit plus `has_downloads`, `assignee`, and attestation `bundle`
    fields. Unversioned requests keep the older behavior today, but that default is not
    guaranteed, so `gh api` calls send an explicit version instead of inheriting it.
    Only REST (`gh api`) calls are pinned; GraphQL ignores the header. A caller that
    already supplies the header wins, so a future migration can override per call.
    .PARAMETER Arguments
    The gh argument list to inspect.
    #>
    [CmdletBinding()]
    param([string[]]$Arguments)

    $argumentList = @($Arguments)
    if ($argumentList.Count -eq 0 -or $argumentList[0] -ne "api") {
        return $argumentList
    }
    if ($argumentList -contains "graphql") {
        return $argumentList
    }
    foreach ($argument in $argumentList) {
        if ([string]$argument -match '^X-GitHub-Api-Version:') {
            return $argumentList
        }
    }

    return @($argumentList + @("-H", "X-GitHub-Api-Version: $GitHubRestApiVersion"))
}

function Invoke-GhCli {
    <#
    .SYNOPSIS
    Runs the GitHub CLI and returns its merged output, exit code, and trimmed text.
    .DESCRIPTION
    Single adapter seam for every read-path `gh` invocation so error handling, output
    normalization, and test mocking live in one place instead of being duplicated at each
    call site. Merges stderr into stdout (2>&1) and captures $LASTEXITCODE immediately so
    callers can inspect gh's real exit code regardless of later pipeline commands. Pester
    tests mock this function instead of replacing the raw `gh` command.
    .PARAMETER Arguments
    The argument list passed to gh (e.g. @("api", "repos/OWNER/REPO")).
    .PARAMETER TimeoutSeconds
    Wall-clock timeout for real gh.exe invocations. Function/alias mocks use the direct
    PowerShell invocation path so Pester can replace gh without starting a child process.
    .PARAMETER StandardInput
    Optional text to send to gh stdin for commands such as `gh api --input -`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [string]$StandardInput,

        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 45
    )

    $Arguments = @(Add-GitHubApiVersionArgument -Arguments $Arguments)
    $command = Get-Command gh -ErrorAction Stop
    $hasStandardInput = $PSBoundParameters.ContainsKey("StandardInput")
    if ($command.CommandType -ne [System.Management.Automation.CommandTypes]::Application) {
        $output = if ($hasStandardInput) {
            $StandardInput | gh @Arguments 2>&1
        } else {
            & gh @Arguments 2>&1
        }
        $exitCode = $LASTEXITCODE
        return [ordered]@{
            output = $output
            exitCode = $exitCode
            text = (($output | Out-String).Trim())
        }
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $command.Source
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $hasStandardInput
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stdoutTask = $null
    $stderrTask = $null
    $stdoutText = ""
    $stderrText = ""
    try {
        [void]$process.Start()
        if ($hasStandardInput) {
            $process.StandardInput.Write($StandardInput)
            $process.StandardInput.Close()
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try {
                $process.Kill($true)
            } catch {
                try {
                    $process.Kill()
                } catch {
                    Write-Warning "Could not terminate timed-out gh process: $($_.Exception.Message)"
                }
            }
            try {
                [void]$process.WaitForExit(5000)
            } catch {
                Write-Warning "Could not observe timed-out gh process exit: $($_.Exception.Message)"
            }
            $text = "gh timed out after $TimeoutSeconds second(s): gh $($Arguments -join ' ')"
            return [ordered]@{
                output = @($text)
                exitCode = 124
                text = $text
            }
        }

        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $stdoutText = if ($stdoutTask) { $stdoutTask.GetAwaiter().GetResult() } else { "" }
        $stderrText = if ($stderrTask) { $stderrTask.GetAwaiter().GetResult() } else { "" }
    } finally {
        $process.Dispose()
    }

    $text = (($stdoutText, $stderrText) -join "`n").Trim()
    $output = if ([string]::IsNullOrWhiteSpace($text)) { @() } else { @($text -split "\r?\n") }
    return [ordered]@{
        output = $output
        exitCode = $exitCode
        text = $text
    }
}

function Get-GitHubReposFromRest {
    if ($script:Offline) {
        return @()
    }

    $script:MetadataFetchRequestCount = [int]$script:MetadataFetchRequestCount + 1
    $gh = Invoke-GhCli -Arguments @("api", "--paginate", "--slurp", "users/$Owner/repos?per_page=100")
    $repoOutput = $gh.text
    if ($gh.exitCode -ne 0) {
        throw "REST repo metadata fallback failed while enumerating repos. Last gh output: $repoOutput"
    }

    $allRepos = New-Object System.Collections.Generic.List[object]
    foreach ($repo in @(ConvertFrom-RestRepoPageJson -Json $repoOutput)) {
        if (-not [bool](Get-MemberValue -Object $repo -Name "archived") -and -not [bool](Get-MemberValue -Object $repo -Name "private")) {
            $allRepos.Add($repo)
        }
    }

    $mapped = New-Object System.Collections.Generic.List[object]
    foreach ($repo in $allRepos) {
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        if ([string]::IsNullOrWhiteSpace($repoName)) {
            continue
        }
        $mapped.Add((ConvertFrom-RestRepoMetadata -Repo $repo -Release $null))
    }

    $script:RepositoryMetadataProvider = "rest-fallback"
    $script:RepositoryEnumerationRequestedLimit = 0
    $script:RepositoryEnumerationTruncated = $false
    return $mapped.ToArray()
}

function ConvertFrom-RestRepoMetadata {
    param(
        [object]$Repo,
        [object]$Release
    )

    $topicsValue = Get-MemberValue -Object $Repo -Name "topics"
    $topics = @()
    if ($topicsValue) {
        $topics = @($topicsValue | ForEach-Object { [pscustomobject]@{ name = [string]$_ } })
    }

    $parentValue = Get-MemberValue -Object $Repo -Name "parent"
    $parent = $null
    if ($parentValue) {
        $parentName = Get-MemberValue -Object $parentValue -Name "full_name"
        $parentUrl = Get-MemberValue -Object $parentValue -Name "html_url"
        if (-not [string]::IsNullOrWhiteSpace([string]$parentName) -or -not [string]::IsNullOrWhiteSpace([string]$parentUrl)) {
            $parent = [pscustomobject]@{
                nameWithOwner = if ([string]::IsNullOrWhiteSpace([string]$parentName)) { $null } else { [string]$parentName }
                url = if ([string]::IsNullOrWhiteSpace([string]$parentUrl)) { $null } else { [string]$parentUrl }
            }
        }
    }

    $language = Get-MemberValue -Object $Repo -Name "language"

    return [pscustomobject]@{
        name = Get-MemberValue -Object $Repo -Name "name"
        description = Get-MemberValue -Object $Repo -Name "description"
        stargazerCount = [int](Get-MemberValue -Object $Repo -Name "stargazers_count")
        defaultBranchRef = [pscustomobject]@{ name = Get-MemberValue -Object $Repo -Name "default_branch" }
        branchTipSha = $null
        branchTipFetchedAt = $null
        branchTipStatus = "unreachable"
        branchTipWarning = "REST repository metadata does not include the default-branch commit tip."
        latestRelease = $Release
        licenseInfo = Get-MemberValue -Object $Repo -Name "license"
        isFork = [bool](Get-MemberValue -Object $Repo -Name "fork")
        parent = $parent
        isPrivate = [bool](Get-MemberValue -Object $Repo -Name "private")
        visibility = "PUBLIC"
        isArchived = [bool](Get-MemberValue -Object $Repo -Name "archived")
        repositoryTopics = $topics
        pushedAt = Get-MemberValue -Object $Repo -Name "pushed_at"
        url = Get-MemberValue -Object $Repo -Name "html_url"
        primaryLanguage = if ([string]::IsNullOrWhiteSpace([string]$language)) { $null } else { [pscustomobject]@{ name = [string]$language } }
    }
}

function ConvertFrom-RestRepoPageJson {
    param([string]$Json)

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return @()
    }

    $repos = New-Object System.Collections.Generic.List[object]
    foreach ($page in @($Json | ConvertFrom-Json)) {
        foreach ($repo in @($page)) {
            $repos.Add($repo)
        }
    }

    return $repos.ToArray()
}

function Test-GitHubCliAuthenticated {
    # Authenticates via GH_TOKEN/GITHUB_TOKEN or the gh CLI keyring. Minimum token scopes:
    #   - Read-only generation (-Write/-Check): public repo read is enough; a fine-grained
    #     token needs read-only "Metadata" + "Contents" on public repos.
    #   - -ApplyTopics (writes repo topics via PUT /repos/.../topics): needs classic "public_repo"
    #     (or fine-grained "Administration: read and write" on the target public repos).
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN) -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        return $true
    }

    $gh = Invoke-GhCli -Arguments @("auth", "status", "-h", "github.com")
    return ($gh.exitCode -eq 0)
}

function Test-GhApiNotFound {
    param([string]$Output)

    return ((Get-GhApiHttpStatus -Output $Output) -eq 404 -or $Output -match '(?i)\bNot Found\b')
}

function Test-GitHubMetadataResourceLimit {
    param([string]$Output)

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return $false
    }

    return ($Output -match '(?i)(graphql resource limit|resource limit|secondary rate limit|api rate limit|rate limit exceeded|abuse detection|HTTP\s+50[234])')
}

function Get-GhApiHttpStatus {
    param([string]$Output)

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return $null
    }

    $match = [regex]::Match($Output, '(?i)\bHTTP\s+(\d{3})\b')
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups[1].Value
}

function Test-RestFallbackReleaseFetchBudget {
    param(
        [int]$RepoCount,
        [bool]$Authenticated,
        [int]$MaxReleaseFetches = $RestFallbackMaxReleaseFetches,
        [int]$UnauthenticatedReleaseFetchLimit = $RestFallbackUnauthenticatedReleaseFetchLimit
    )

    $message = $null
    if ($RepoCount -gt $MaxReleaseFetches) {
        $message = "REST repo metadata fallback would fetch latest-release metadata for $RepoCount repos, exceeding the configured cap of $MaxReleaseFetches requests."
    } elseif (-not $Authenticated -and $RepoCount -gt $UnauthenticatedReleaseFetchLimit) {
        $message = "REST repo metadata fallback requires authenticated gh access for $RepoCount release requests; unauthenticated runs are capped at $UnauthenticatedReleaseFetchLimit to avoid rate-limit partial data."
    }

    return [ordered]@{
        allowed = [string]::IsNullOrWhiteSpace($message)
        message = $message
        repoCount = $RepoCount
        authenticated = [bool]$Authenticated
        maxReleaseFetches = $MaxReleaseFetches
        unauthenticatedReleaseFetchLimit = $UnauthenticatedReleaseFetchLimit
    }
}

function New-RestFallbackReleaseFetchState {
    param(
        [switch]$Used,
        [ValidateSet("not-used", "preflight-passed", "preflight-blocked", "completed", "aborted")]
        [string]$Status = "not-used",
        [int]$RepoCount = 0,
        [bool]$Authenticated = $false,
        [int]$MaxReleaseFetches = $RestFallbackMaxReleaseFetches,
        [int]$UnauthenticatedReleaseFetchLimit = $RestFallbackUnauthenticatedReleaseFetchLimit,
        [int]$AttemptedReleaseFetches = 0,
        [int]$SuccessfulReleaseFetches = 0,
        [int]$NoRelease404Count = 0,
        [bool]$Fatal = $false,
        [string]$AbortRepo = $null,
        [Nullable[int]]$AbortHttpStatus = $null,
        [string]$AbortMessage = $null
    )

    return [ordered]@{
        used = [bool]$Used
        status = $Status
        repoCount = [int]$RepoCount
        authenticated = [bool]$Authenticated
        maxReleaseFetches = [int]$MaxReleaseFetches
        unauthenticatedReleaseFetchLimit = [int]$UnauthenticatedReleaseFetchLimit
        attemptedReleaseFetches = [int]$AttemptedReleaseFetches
        successfulReleaseFetches = [int]$SuccessfulReleaseFetches
        noRelease404Count = [int]$NoRelease404Count
        fatal = [bool]$Fatal
        abortRepo = if ([string]::IsNullOrWhiteSpace($AbortRepo)) { $null } else { $AbortRepo }
        abortHttpStatus = $AbortHttpStatus
        abortMessage = if ([string]::IsNullOrWhiteSpace($AbortMessage)) { $null } else { $AbortMessage }
    }
}

function Reset-RestFallbackReleaseFetchState {
    $script:RestFallbackReleaseFetchState = New-RestFallbackReleaseFetchState
}

function Get-RestFallbackReleaseFetchState {
    if ($null -eq $script:RestFallbackReleaseFetchState) {
        Reset-RestFallbackReleaseFetchState
    }

    return $script:RestFallbackReleaseFetchState
}

function Reset-MetadataFetchTelemetry {
    $script:RepositoryMetadataProvider = "graphql"
    $script:RepositoryEnumerationRequestedLimit = [int]$script:GraphQlPageSize
    $script:RepositoryEnumerationTruncated = $false
    $script:MetadataFetchAttemptCount = 0
    $script:MetadataFetchRequestCount = 0
    $script:MetadataFetchPageSizeReduced = $false
    $script:MetadataFetchFallbackReason = $null
    $script:MetadataFetchResourceLimitFallback = $false
    $script:MetadataFetchResourceLimitReason = $null
    Reset-ValidationCacheState
}

function Get-GitHubRepos {
    <#
    .SYNOPSIS
    Fetches the owner's active public repository metadata.
    .DESCRIPTION
    Uses GitHub CLI GraphQL metadata first, retries transient failures, and
    falls back to REST pagination when GraphQL returns an unsafe partial page.
    Release metadata is intentionally excluded from the bulk GraphQL request
    and fetched by Add-ReleaseAssetMetadata to avoid high-complexity 502s.
    #>
    [CmdletBinding()]
    param()

    Reset-MetadataFetchTelemetry

    if ($script:Offline) {
        $cachedRepos = Get-ValidationCacheValue -Bucket metadata -Key (Get-LiveRepositoryMetadataCacheKey) -FallbackReason 'offline'
        if ($null -ne $cachedRepos) {
            $script:RepositoryMetadataProvider = "cache-offline"
            $script:RepositoryEnumerationRequestedLimit = [int]$script:GraphQlPageSize
            $script:RepositoryEnumerationTruncated = $false
            $script:MetadataFetchFallbackReason = "offline cache hit"
            Reset-RestFallbackReleaseFetchState
            return @($cachedRepos)
        }
        Reset-RestFallbackReleaseFetchState
        return @()
    }

    $repoLimit = [int]$script:GraphQlPageSize
    $lastOutput = $null
    $completeRestFallbackRequired = $false

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        # GitHub's per-query GraphQL resource limit (announced 2025-09-01) is a function of
        # how much the query asks for, so re-sending the same oversized page is futile.
        # Halve the page instead, which turns a REST fallback into a smaller live query.
        $ghArgs = @(
            "repo", "list", $Owner,
            "--visibility", "public",
            "--no-archived",
            "--limit", [string]$repoLimit,
            "--json", "name,description,stargazerCount,defaultBranchRef,licenseInfo,isFork,parent,isPrivate,visibility,isArchived,repositoryTopics,pushedAt,url,primaryLanguage"
        )
        $script:MetadataFetchAttemptCount = $attempt
        $script:MetadataFetchRequestCount = [int]$script:MetadataFetchRequestCount + 1
        $gh = Invoke-GhCli -Arguments $ghArgs
        $lastOutput = $gh.text

        if ($gh.exitCode -eq 0) {
            try {
                $repos = @($lastOutput | ConvertFrom-Json)
                if ($repos.Count -eq 0) {
                    throw "GitHub returned an empty repository list."
                }
                if ($repos.Count -eq 100 -and $repoLimit -gt 100) {
                    $lastOutput = "gh repo list returned exactly 100 repos despite requested limit $repoLimit; falling back to REST pagination to avoid a partial default-page result."
                    $completeRestFallbackRequired = $true
                    break
                }
                if ($repos.Count -ge $repoLimit) {
                    # A list that fills its own page is indistinguishable from a truncated
                    # one, and a truncated enumeration makes every missing repo look like it
                    # went private. REST pagination is complete, so fall back instead of
                    # drawing visibility conclusions from a partial list.
                    $lastOutput = "gh repo list returned $($repos.Count) repos at limit $repoLimit; falling back to REST pagination to avoid a truncated enumeration."
                    $completeRestFallbackRequired = $true
                    break
                }
                $script:RepositoryMetadataProvider = "graphql"
                $script:RepositoryEnumerationRequestedLimit = $repoLimit
                $script:RepositoryEnumerationTruncated = [bool]($repos.Count -ge $repoLimit)
                $script:MetadataFetchFallbackReason = $null
                $script:MetadataFetchResourceLimitFallback = $false
                $script:MetadataFetchResourceLimitReason = $null
                Reset-RestFallbackReleaseFetchState
                return $repos
            } catch {
                $lastOutput = $_.Exception.Message
            }
        }

        if ($attempt -lt 3) {
            if ((Test-GitHubMetadataResourceLimit -Output $lastOutput) -and $repoLimit -gt 100) {
                $reducedLimit = [Math]::Max(100, [int][Math]::Floor($repoLimit / 2))
                if ($reducedLimit -lt $repoLimit) {
                    Write-Warning "GraphQL resource limit hit at page size $repoLimit; retrying with $reducedLimit."
                    $repoLimit = $reducedLimit
                    $script:RepositoryEnumerationRequestedLimit = $repoLimit
                    $script:MetadataFetchPageSizeReduced = $true
                }
            }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }

    $script:MetadataFetchFallbackReason = $lastOutput
    $script:MetadataFetchResourceLimitFallback = Test-GitHubMetadataResourceLimit -Output $lastOutput
    $script:MetadataFetchResourceLimitReason = if ($script:MetadataFetchResourceLimitFallback) { $lastOutput } else { $null }
    if (-not $completeRestFallbackRequired) {
        $cachedFallbackRepos = Get-ValidationCacheValue -Bucket metadata -Key (Get-LiveRepositoryMetadataCacheKey) -FallbackReason $lastOutput
        if ($null -ne $cachedFallbackRepos) {
            Write-Warning "GraphQL repo metadata failed after 3 attempts; using cached metadata. Last gh output: $lastOutput"
            $script:RepositoryMetadataProvider = "cache-fallback"
            $script:RepositoryEnumerationRequestedLimit = [int]$script:GraphQlPageSize
            $script:RepositoryEnumerationTruncated = $false
            Reset-RestFallbackReleaseFetchState
            return @($cachedFallbackRepos)
        }
    }
    $attemptDescription = if ($completeRestFallbackRequired) { 'returned a full page' } else { 'failed after 3 attempts' }
    Write-Warning "GraphQL repo metadata $attemptDescription; using REST fallback. Last gh output: $lastOutput"
    return Get-GitHubReposFromRest
}

function Get-BranchTipRows {
    <#
    .SYNOPSIS
    Fetches public owner repository default-branch names and tip OIDs in one paginated GraphQL query.
    .DESCRIPTION
    Branch-tip evidence is warning-only. A failed query never blocks generation; callers mark affected
    branch-backed install actions as unreachable or stale instead of inventing a commit SHA.
    .PARAMETER Repos
    Repository metadata rows used to limit the returned rows to repositories in this run.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    if ($script:Offline) {
        return [ordered]@{
            succeeded = $false
            fetchedAt = $null
            error = "Branch-tip lookup skipped in offline mode."
            rows = @()
        }
    }

    $requestedNames = @{}
    foreach ($repo in @($Repos | Where-Object { $null -ne $_ })) {
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        if (-not [string]::IsNullOrWhiteSpace($repoName)) {
            $requestedNames[$repoName.ToLowerInvariant()] = $true
        }
    }

    $query = 'query($login: String!, $cursor: String) { user(login: $login) { repositories(first: 100, after: $cursor, ownerAffiliations: OWNER, privacy: PUBLIC) { nodes { name defaultBranchRef { name target { oid } } } pageInfo { hasNextPage endCursor } } } }'
    $rows = New-Object System.Collections.Generic.List[object]
    $cursor = $null
    $lastError = $null

    try {
        for ($page = 0; $page -lt 10; $page++) {
            $arguments = @(
                "api",
                "graphql",
                "-f",
                "query=$query",
                "-f",
                "login=$Owner"
            )
            if ($null -eq $cursor) {
                $arguments += @("-F", "cursor=null")
            } else {
                $arguments += @("-f", "cursor=$cursor")
            }

            $gh = Invoke-GhCli -Arguments $arguments
            if ($gh.exitCode -ne 0) {
                $lastError = $gh.text
                break
            }

            $payload = $gh.text | ConvertFrom-Json
            $connection = Get-MemberValue -Object (Get-MemberValue -Object (Get-MemberValue -Object $payload -Name "data") -Name "user") -Name "repositories"
            if ($null -eq $connection) {
                $lastError = "GitHub branch-tip query returned no repository connection."
                break
            }

            foreach ($node in @($connection.nodes)) {
                $nodeName = [string](Get-MemberValue -Object $node -Name "name")
                if ($requestedNames.Count -gt 0 -and -not $requestedNames.ContainsKey($nodeName.ToLowerInvariant())) {
                    continue
                }
                $ref = Get-MemberValue -Object $node -Name "defaultBranchRef"
                $target = Get-MemberValue -Object $ref -Name "target"
                $rows.Add([ordered]@{
                    name = $nodeName
                    branch = [string](Get-MemberValue -Object $ref -Name "name")
                    sha = [string](Get-MemberValue -Object $target -Name "oid")
                })
            }

            $pageInfo = Get-MemberValue -Object $connection -Name "pageInfo"
            if (-not [bool](Get-MemberValue -Object $pageInfo -Name "hasNextPage")) {
                break
            }

            $cursor = [string](Get-MemberValue -Object $pageInfo -Name "endCursor")
            if ([string]::IsNullOrWhiteSpace($cursor)) {
                $lastError = "GitHub branch-tip query reported another page without an end cursor."
                break
            }
        }
    } catch {
        $lastError = $_.Exception.Message
    }

    if (-not [string]::IsNullOrWhiteSpace($lastError)) {
        return [ordered]@{
            succeeded = $false
            fetchedAt = $null
            error = $lastError
            rows = @()
        }
    }

    return [ordered]@{
        succeeded = $true
        fetchedAt = (Get-Date).ToUniversalTime().ToString("o")
        error = $null
        rows = $rows.ToArray()
    }
}

function Set-BranchTipMetadata {
    <#
    .SYNOPSIS
    Applies branch-tip provenance and warning state to repository metadata rows.
    .PARAMETER Repos
    Repository metadata rows to annotate.
    .PARAMETER FetchResult
    Result from Get-BranchTipRows or an equivalent hermetic fixture.
    .PARAMETER StaleAfterHours
    Age after which previously fetched branch-tip evidence becomes stale.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Repos,
        [object]$FetchResult,
        [ValidateRange(1, 720)]
        [int]$StaleAfterHours = $BranchTipStaleAfterHours
    )

    $rowsByName = @{}
    foreach ($row in @($FetchResult.rows)) {
        $name = [string](Get-MemberValue -Object $row -Name "name")
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $rowsByName[$name.ToLowerInvariant()] = $row
        }
    }

    $fetchSucceeded = [bool](Get-MemberValue -Object $FetchResult -Name "succeeded")
    $fetchAt = [string](Get-MemberValue -Object $FetchResult -Name "fetchedAt")
    $fetchError = [string](Get-MemberValue -Object $FetchResult -Name "error")

    foreach ($repo in @($Repos | Where-Object { $null -ne $_ })) {
        $branchRef = Get-MemberValue -Object $repo -Name "defaultBranchRef"
        $branch = [string](Get-MemberValue -Object $branchRef -Name "name")
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        $tipSha = $null
        $tipFetchedAt = $null
        $status = "missing"
        $warning = $null
        $row = if ($rowsByName.ContainsKey($repoName.ToLowerInvariant())) { $rowsByName[$repoName.ToLowerInvariant()] } else { $null }

        if ([string]::IsNullOrWhiteSpace($branch)) {
            $status = "missing"
            $warning = "GitHub did not advertise a default branch for this repository."
        } elseif ($fetchSucceeded -and $null -ne $row) {
            $rowBranch = [string](Get-MemberValue -Object $row -Name "branch")
            $candidateSha = [string](Get-MemberValue -Object $row -Name "sha")
            if ($rowBranch -ne $branch) {
                $status = "unreachable"
                $warning = "Branch-tip response disagreed with the advertised default branch."
            } elseif ($candidateSha -match '^[a-f0-9]{40}$') {
                $tipSha = $candidateSha.ToLowerInvariant()
                $tipFetchedAt = $fetchAt
                $status = "fresh"
            } else {
                $status = "missing"
                $warning = "GitHub returned the default branch without a commit OID."
            }
        } elseif (-not $fetchSucceeded) {
            $existingSha = [string](Get-MemberValue -Object $repo -Name "branchTipSha")
            $existingFetchedAt = [string](Get-MemberValue -Object $repo -Name "branchTipFetchedAt")
            if ($existingSha -match '^[a-f0-9]{40}$' -and $existingFetchedAt -match '^\d{4}-\d{2}-\d{2}T') {
                try {
                    $ageHours = ([datetimeoffset]::Now.ToUniversalTime() - [datetimeoffset]::Parse($existingFetchedAt).ToUniversalTime()).TotalHours
                    if ($ageHours -le $StaleAfterHours) {
                        $tipSha = $existingSha.ToLowerInvariant()
                        $tipFetchedAt = $existingFetchedAt
                        $status = "stale"
                        $warning = "Branch-tip refresh was unreachable; retaining evidence fetched $([math]::Round($ageHours, 1)) hour(s) ago."
                    } else {
                        $tipSha = $existingSha.ToLowerInvariant()
                        $tipFetchedAt = $existingFetchedAt
                        $status = "stale"
                        $warning = "Branch-tip evidence is $([math]::Round($ageHours, 1)) hour(s) old and the refresh was unreachable."
                    }
                } catch {
                    $status = "stale"
                    $warning = "Branch-tip evidence has an invalid fetched-at timestamp and the refresh was unreachable."
                }
            } else {
                $status = "unreachable"
                $warning = if ([string]::IsNullOrWhiteSpace($fetchError)) { "Branch-tip lookup was unreachable." } else { "Branch-tip lookup was unreachable: $fetchError" }
            }
        } else {
            $status = "unreachable"
            $warning = "Branch-tip response did not include this public repository."
        }

        Set-MemberValue -Object $repo -Name "branchTipSha" -Value $tipSha
        Set-MemberValue -Object $repo -Name "branchTipFetchedAt" -Value $tipFetchedAt
        Set-MemberValue -Object $repo -Name "branchTipStatus" -Value $status
        Set-MemberValue -Object $repo -Name "branchTipWarning" -Value $warning
    }

    return @($Repos)
}

function Add-BranchTipMetadata {
    <#
    .SYNOPSIS
    Enriches live repository metadata with warning-only default-branch tip evidence.
    .PARAMETER Repos
    Repository metadata rows to enrich.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    if ($script:Offline) {
        return @($Repos)
    }

    $fetchResult = if (([string]$script:RepositoryMetadataProvider).StartsWith("cache", [StringComparison]::OrdinalIgnoreCase)) {
        [ordered]@{
            succeeded = $false
            fetchedAt = $null
            error = "Repository metadata came from cache; branch-tip refresh was not attempted."
            rows = @()
        }
    } else {
        Get-BranchTipRows -Repos $Repos
    }

    return @(Set-BranchTipMetadata -Repos $Repos -FetchResult $fetchResult)
}

function ConvertFrom-RestReleaseMetadata {
    param([object]$Release)

    $assetNames = @(Get-ReleaseAssetNamesFromApiRelease -Release $Release)
    $assetDigests = Get-ReleaseAssetDigestsFromApiRelease -Release $Release
    $releaseAssets = foreach ($asset in @((Get-MemberValue -Object $Release -Name "assets"))) {
        $assetName = [string](Get-MemberValue -Object $asset -Name "name")
        if ([string]::IsNullOrWhiteSpace($assetName)) { continue }
        [pscustomobject]@{
            name = $assetName
            browserDownloadUrl = Get-MemberValue -Object $asset -Name "browser_download_url"
            size = if ($null -eq (Get-MemberValue -Object $asset -Name "size")) { $null } else { [int64](Get-MemberValue -Object $asset -Name "size") }
            digest = Get-MemberValue -Object $asset -Name "digest"
        }
    }

    return [pscustomobject]@{
        tagName = Get-MemberValue -Object $Release -Name "tag_name"
        url = Get-MemberValue -Object $Release -Name "html_url"
        name = Get-MemberValue -Object $Release -Name "name"
        publishedAt = Get-MemberValue -Object $Release -Name "published_at"
        releaseAssetNames = $assetNames
        releaseAssetKinds = @(Get-ReleaseAssetKinds -AssetNames $assetNames)
        releaseAssetDigests = $assetDigests
        releaseAssets = @($releaseAssets)
        assetApiInspected = $true
        immutable = Get-MemberValue -Object $Release -Name "immutable"
    }
}

function Add-ReleaseAssetMetadata {
    <#
    .SYNOPSIS
    Enriches repository metadata with latest-release and asset evidence.
    .PARAMETER Repos
    Repository metadata rows returned by GitHub GraphQL or REST enumeration.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    if ($script:Offline -or ([string]$script:RepositoryMetadataProvider).StartsWith("cache", [StringComparison]::OrdinalIgnoreCase)) {
        return @($Repos)
    }

    $repoRows = @($Repos | Sort-Object name | Where-Object {
        $repoName = Get-MemberValue -Object $_ -Name "name"
        -not [string]::IsNullOrWhiteSpace([string]$repoName)
    })

    $authenticated = Test-GitHubCliAuthenticated
    $releaseBudget = Test-RestFallbackReleaseFetchBudget -RepoCount $repoRows.Count -Authenticated $authenticated
    $script:RestFallbackReleaseFetchState = New-RestFallbackReleaseFetchState `
        -Used `
        -Status "preflight-passed" `
        -RepoCount $repoRows.Count `
        -Authenticated:$authenticated `
        -MaxReleaseFetches $releaseBudget.maxReleaseFetches `
        -UnauthenticatedReleaseFetchLimit $releaseBudget.unauthenticatedReleaseFetchLimit
    if (-not $releaseBudget.allowed) {
        $script:RestFallbackReleaseFetchState["status"] = "preflight-blocked"
        $script:RestFallbackReleaseFetchState["fatal"] = $true
        $script:RestFallbackReleaseFetchState["abortMessage"] = $releaseBudget.message
        throw $releaseBudget.message
    }

    foreach ($repo in $repoRows) {
        $repoName = [string](Get-MemberValue -Object $repo -Name "name")
        $release = Get-MemberValue -Object $repo -Name "latestRelease"
        if ($null -eq $release) {
            Set-MemberValue -Object $repo -Name "latestRelease" -Value $null
        }
        if ($release -and (Test-ReleaseAssetMetadataInspected -Meta $repo)) {
            continue
        }

        $script:RestFallbackReleaseFetchState["attemptedReleaseFetches"] = [int]$script:RestFallbackReleaseFetchState["attemptedReleaseFetches"] + 1
        $releaseCacheKey = Get-ReleaseMetadataCacheKey -Repo $repoName
        $gh = Invoke-GhCli -Arguments @("api", "repos/$Owner/$repoName/releases/latest")
        $releaseOutput = $gh.text
        if ($gh.exitCode -ne 0) {
            if (Test-GhApiNotFound -Output $releaseOutput) {
                $script:RestFallbackReleaseFetchState["noRelease404Count"] = [int]$script:RestFallbackReleaseFetchState["noRelease404Count"] + 1
                continue
            }

            $cachedRelease = Get-ValidationCacheValue -Bucket releases -Key $releaseCacheKey -FallbackReason $releaseOutput
            if ($null -ne $cachedRelease) {
                Set-MemberValue -Object $repo -Name "latestRelease" -Value $cachedRelease
                $script:RestFallbackReleaseFetchState["successfulReleaseFetches"] = [int]$script:RestFallbackReleaseFetchState["successfulReleaseFetches"] + 1
                continue
            }

            if ($release) {
                Set-MemberValue -Object $release -Name "releaseAssetFetchError" -Value $releaseOutput
                Set-MemberValue -Object $release -Name "assetApiInspected" -Value $false
            }
            $script:RestFallbackReleaseFetchState["status"] = "aborted"
            $script:RestFallbackReleaseFetchState["fatal"] = $true
            $script:RestFallbackReleaseFetchState["abortRepo"] = $repoName
            $script:RestFallbackReleaseFetchState["abortHttpStatus"] = Get-GhApiHttpStatus -Output $releaseOutput
            $script:RestFallbackReleaseFetchState["abortMessage"] = "Latest-release fetch failed after $($script:RestFallbackReleaseFetchState["attemptedReleaseFetches"]) attempted request(s)."
            Write-Warning "REST latest-release metadata failed for $repoName; aborting to avoid partial release metadata. Last gh output: $releaseOutput"
            throw "REST latest-release metadata failed while fetching $repoName. Refusing to emit partial release metadata."
        }

        if ([string]::IsNullOrWhiteSpace($releaseOutput)) {
            continue
        }

        $releaseData = $null
        try {
            $releaseData = $releaseOutput | ConvertFrom-Json
        } catch {
            Write-Warning "REST latest-release metadata for $repoName returned unparseable JSON; skipping."
            continue
        }
        $releaseMetadata = ConvertFrom-RestReleaseMetadata -Release $releaseData
        Write-ValidationCacheEntry -Bucket releases -Key $releaseCacheKey -Value $releaseMetadata
        $script:RestFallbackReleaseFetchState["successfulReleaseFetches"] = [int]$script:RestFallbackReleaseFetchState["successfulReleaseFetches"] + 1
        Set-MemberValue -Object $repo -Name "latestRelease" -Value $releaseMetadata
    }

    $script:RestFallbackReleaseFetchState["status"] = "completed"
    return @($Repos)
}

function Get-RepoNameWithOwner {
    param([object]$Repo)

    foreach ($field in @("nameWithOwner", "full_name", "fullName")) {
        $value = Get-MemberValue -Object $Repo -Name $field
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }

    $owner = Get-MemberValue -Object $Repo -Name "owner"
    $ownerLogin = Get-MemberValue -Object $owner -Name "login"
    $name = Get-MemberValue -Object $Repo -Name "name"
    if (-not [string]::IsNullOrWhiteSpace([string]$ownerLogin) -and -not [string]::IsNullOrWhiteSpace([string]$name)) {
        return "$ownerLogin/$name"
    }

    return $null
}

function Get-ForkParentNameWithOwner {
    param([object]$Meta)

    return Get-RepoNameWithOwner -Repo (Get-MemberValue -Object $Meta -Name "parent")
}

function Add-ForkParentMetadata {
    <#
    .SYNOPSIS
    Completes missing fork-parent metadata for forked repositories.
    .PARAMETER Repos
    Repository metadata rows to enrich with parent repository details.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    if ($script:Offline) {
        return @($Repos)
    }

    foreach ($repo in @($Repos | Sort-Object name)) {
        if (-not (ConvertTo-BooleanValue (Get-MemberValue -Object $repo -Name "isFork"))) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-ForkParentNameWithOwner -Meta $repo))) {
            continue
        }

        $repoName = Get-MemberValue -Object $repo -Name "name"
        if ([string]::IsNullOrWhiteSpace([string]$repoName)) {
            continue
        }

        $gh = Invoke-GhCli -Arguments @("api", "repos/$Owner/$repoName")
        $repoOutput = $gh.text
        if ($gh.exitCode -ne 0) {
            Set-MemberValue -Object $repo -Name "forkParentFetchError" -Value $repoOutput
            continue
        }

        $repoData = $repoOutput | ConvertFrom-Json
        $parent = Get-MemberValue -Object $repoData -Name "parent"
        $parentName = Get-RepoNameWithOwner -Repo $parent
        if (-not [string]::IsNullOrWhiteSpace([string]$parentName)) {
            Set-MemberValue -Object $repo -Name "parent" -Value ([pscustomobject]@{
                nameWithOwner = [string]$parentName
                url = Get-MemberValue -Object $parent -Name "html_url"
            })
        } else {
            Set-MemberValue -Object $repo -Name "forkParentFetchError" -Value "GitHub reported this repository as a fork, but REST repository metadata did not include a parent."
        }
    }

    return @($Repos)
}

function Set-ForkParentMetadataEnrichmentFailure {
    param(
        [object[]]$Repos,
        [string]$Message
    )

    $reason = if ([string]::IsNullOrWhiteSpace($Message)) {
        "Fork-parent metadata enrichment failed before completing."
    } else {
        "Fork-parent metadata enrichment failed before completing: $Message"
    }

    foreach ($repo in @($Repos | Sort-Object name)) {
        if (-not (ConvertTo-BooleanValue (Get-MemberValue -Object $repo -Name "isFork"))) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-ForkParentNameWithOwner -Meta $repo))) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $repo -Name "forkParentFetchError"))) {
            continue
        }

        Set-MemberValue -Object $repo -Name "forkParentFetchError" -Value $reason
    }

    return @($Repos)
}

function Add-LiveRepositoryMetadata {
    <#
    .SYNOPSIS
    Applies live metadata enrichments needed by generated profile reports.
    .PARAMETER Repos
    Base repository metadata rows from GitHub enumeration.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    if ($script:Offline) {
        return @($Repos)
    }

    $enrichedRepos = @($Repos)
    try {
        $enrichedRepos = @(Add-ForkParentMetadata -Repos $enrichedRepos)
    } catch {
        $message = $_.Exception.Message
        Write-Warning "Fork-parent metadata enrichment failed; continuing with base repository metadata. $message"
        $enrichedRepos = @(Set-ForkParentMetadataEnrichmentFailure -Repos $enrichedRepos -Message $message)
    }

    $enrichedRepos = @(Add-ReleaseAssetMetadata -Repos $enrichedRepos)
    $enrichedRepos = @(Add-BranchTipMetadata -Repos $enrichedRepos)
    Write-ValidationCacheEntry -Bucket metadata -Key (Get-LiveRepositoryMetadataCacheKey) -Value $enrichedRepos
    return @($enrichedRepos)
}

function ConvertTo-Lookup {
    <#
    .SYNOPSIS
    Builds a case-insensitive repository lookup table by repository name.
    .PARAMETER Repos
    Repository metadata rows that may contain a name property.
    #>
    [CmdletBinding()]
    param([object[]]$Repos)

    $lookup = @{}
    foreach ($repo in $Repos) {
        $repoName = Get-MemberValue -Object $repo -Name "name"
        if ([string]::IsNullOrWhiteSpace([string]$repoName)) {
            continue
        }
        $lookup[([string]$repoName).ToLowerInvariant()] = $repo
    }
    return $lookup
}

function Get-PublicSafeGhError {
    param([string]$Output)

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return "gh api failed without output"
    }
    if (Test-GhApiNotFound -Output $Output) {
        return "not found"
    }
    if ($Output -match '(?i)(needs|requires).*(scope|permission)') {
        return "required GitHub API scope is unavailable"
    }

    $firstLine = @($Output -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($firstLine.Count -eq 0) {
        return "gh api failed"
    }
    return (($firstLine[0] -replace '^gh:\s*', '').Trim())
}

function Invoke-GhApiJsonSafe {
    param(
        [string]$Path,
        # List endpoints: every page, flattened into one array. GitHub pages them at 30
        # items by default, so the first page alone can miss a ruleset, rule or alert.
        [switch]$Paginate
    )

    # The path stays right after "api"; gh reads its flags from anywhere on the line.
    $gh = Invoke-GhCli -Arguments $(if ($Paginate) { @("api", $Path, "--paginate", "--slurp") } else { @("api", $Path) })
    $text = $gh.text
    if ($gh.exitCode -ne 0) {
        return [ordered]@{
            ok = $false
            value = $null
            error = Get-PublicSafeGhError -Output $text
        }
    }

    try {
        $value = if ($Paginate) {
            # --slurp wraps the pages in one outer array; the items of every page, in order.
            , @(foreach ($page in (ConvertFrom-Json -InputObject $text -NoEnumerate)) { foreach ($item in $page) { $item } })
        } else {
            $text | ConvertFrom-Json
        }
        return [ordered]@{
            ok = $true
            value = $value
            error = $null
        }
    } catch {
        return [ordered]@{
            ok = $false
            value = $null
            error = "gh api returned malformed JSON"
        }
    }
}
