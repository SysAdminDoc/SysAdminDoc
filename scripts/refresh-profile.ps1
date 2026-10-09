#Requires -Version 7.4
<#
.SYNOPSIS
Refreshes the profile storefront in one command.
.DESCRIPTION
Runs every step a refresh needs, in order, and stops at the first one that fails with a
non-zero exit that names it.

  identity    (-Commit) git's author and committer must both be SysAdminDoc.
  clean-tree  (-Commit) no tracked file may be modified before the run starts, so the
              refresh commit holds generated files only.
  sync        scripts/sync-profile.ps1 -Write -Check -DraftMissingCatalogEntries at the
              page size that fits the account. A public repository with no catalog row
              fails here, and the run drafts a suppressed row for it in
              data/profile-catalog.json for the owner to finish.
  floors      prints each hand-kept download floor next to the measured release downloads
              (the report's downloadFloors section).
  commit      (-Commit) commits the regenerated files with a generated message.
  push        (-Commit) pushes main.
  smoke       scripts/render-profile-smoke.ps1 against the published profile, when
              CHROME_PATH is set. With -Commit it runs after the push, so it renders the
              page that was just pushed.
  evidence    after a smoke, runs -Check again so the report carries the fresh smoke, and
              with -Commit commits and pushes that report on its own. The report isn't a
              smoke-affecting path, so this commit doesn't make the smoke stale again.
.PARAMETER Commit
Commit and push the refresh. Needs a clean tree and the SysAdminDoc identity.
.PARAMETER GraphQlPageSize
Page size for the repository listing. 150 fits this account; the generator's default
of 500 trips GitHub's GraphQL resource limit.
.EXAMPLE
pwsh -NoProfile -File scripts/refresh-profile.ps1 -Commit
#>
[CmdletBinding()]
param(
    [switch]$Commit,
    [ValidateRange(1, 1000)]
    [int]$GraphQlPageSize = 150
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RefreshRepoRoot = Split-Path -Parent $PSScriptRoot
$RefreshIdentityName = "SysAdminDoc"
$RefreshIdentityEmail = "matt_parker@outlook.com"
$RefreshReportPath = "reports/profile-sync-report.json"
# What -Write regenerates. data/profile-catalog.json only changes when drafts are written,
# and a run that drafts has already failed, so it is never part of a refresh commit.
$RefreshGeneratedPaths = @("README.md", "projects.json", $RefreshReportPath, "assets/profile")

function Invoke-RefreshScript {
    # Runs a repository script in a child pwsh from the repository root, the directory its
    # relative paths are read against, and returns the exit code. Output streams through.
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Arguments = @()
    )

    Push-Location -LiteralPath $RefreshRepoRoot
    try {
        & pwsh -NoProfile -NonInteractive -File (Join-Path $RefreshRepoRoot $Path) @Arguments | Out-Host
        return [int]$LASTEXITCODE
    } finally {
        Pop-Location
    }
}

function Invoke-RefreshGit {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& git -C $RefreshRepoRoot @Arguments 2>&1 | ForEach-Object { [string]$_ })
    return [ordered]@{ exitCode = [int]$LASTEXITCODE; output = $output }
}

function Get-RefreshReport {
    $path = Join-Path $RefreshRepoRoot $RefreshReportPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable)
}

function Test-RefreshIdentity {
    # git var resolves the identity a commit would get, environment overrides included.
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($role in @("AUTHOR", "COMMITTER")) {
        $result = Invoke-RefreshGit -Arguments @("var", "GIT_${role}_IDENT")
        $ident = [string]($result.output -join "`n")
        $match = [regex]::Match($ident, '^(?<name>.+?) <(?<email>[^>]*)>')
        if ($result.exitCode -ne 0 -or -not $match.Success) {
            $problems.Add("git has no $($role.ToLowerInvariant()) identity ($ident)")
        } elseif ($match.Groups['name'].Value -cne $RefreshIdentityName -or $match.Groups['email'].Value -ne $RefreshIdentityEmail) {
            $problems.Add("the $($role.ToLowerInvariant()) is $($match.Groups['name'].Value) <$($match.Groups['email'].Value)>, not $RefreshIdentityName <$RefreshIdentityEmail>")
        }
    }
    return @($problems.ToArray())
}

function Format-RefreshDownloadFloors {
    param([AllowNull()][object]$Report)

    $section = if ($null -ne $Report -and $Report.Contains('downloadFloors')) { $Report['downloadFloors'] } else { $null }
    if ($null -eq $section) { return @("Download floors: the report has no downloadFloors section.") }
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $lines = New-Object System.Collections.Generic.List[string]
    $total = $section['totalReleaseDownloads']
    $totalText = if ($null -eq $total) { "not measured" } else { ([long]$total).ToString("N0", $invariant) }
    $lines.Add("Download floors ($($section['status'])): $totalText release downloads across $($section['measuredRepoCount']) of $($section['repoCount']) repos.")
    foreach ($row in @($section['rows'])) {
        $name = if ($row['subject'] -eq 'proof') { 'header' } else { [string]$row['repo'] }
        $measured = if ($null -eq $row['measured']) { 'not measured' } else { ([long]$row['measured']).ToString("N0", $invariant) }
        $suggestion = if ([string]::IsNullOrWhiteSpace([string]$row['suggestedFloor'])) { '' } else { " (suggest $($row['suggestedFloor']))" }
        $lines.Add("  ${name}: $($row['floorText']) against $measured, $($row['status'])$suggestion")
    }
    return @($lines.ToArray())
}

function New-RefreshCommitMessage {
    param(
        [AllowNull()][object]$Report,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )

    $facts = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Report) {
        if ($Report.Contains('publicRepoCount')) { $facts.Add("$($Report['publicRepoCount']) public repos") }
        if ($Report.Contains('missingPublicRepos')) { $facts.Add("$(@($Report['missingPublicRepos']).Count) uncataloged") }
        $floors = if ($Report.Contains('downloadFloors')) { $Report['downloadFloors'] } else { $null }
        if ($null -ne $floors -and $null -ne $floors['totalReleaseDownloads']) {
            $facts.Add("$(([long]$floors['totalReleaseDownloads']).ToString('N0', [Globalization.CultureInfo]::InvariantCulture)) release downloads measured")
        }
    }
    $body = "Regenerated from live metadata on $($Now.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture))"
    if ($facts.Count -gt 0) { $body += ": " + ($facts -join ", ") }
    return "chore: refresh the profile storefront`n`n$body."
}

function Invoke-ProfileRefresh {
    <#
    .SYNOPSIS
    Runs the refresh steps and returns what happened; never exits the process.
    #>
    param(
        [switch]$Commit,
        [int]$GraphQlPageSize = 150,
        [AllowNull()][string]$ChromePath = $env:CHROME_PATH
    )

    $steps = New-Object System.Collections.Generic.List[object]
    $commits = New-Object System.Collections.Generic.List[string]
    $finish = {
        param([string]$FailedStep, [string]$Message)
        [ordered]@{
            status = if ($FailedStep) { 'failed' } else { 'ok' }
            failedStep = if ($FailedStep) { $FailedStep } else { $null }
            message = $Message
            steps = @($steps.ToArray())
            commits = @($commits.ToArray())
        }
    }
    $record = { param([string]$Name, [string]$Status, [string]$Detail) $steps.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail }) }
    $commitAndPush = {
        param([string]$Message, [string]$StepPrefix)
        $add = Invoke-RefreshGit -Arguments (@("add", "--") + $RefreshGeneratedPaths)
        if ($add.exitCode -ne 0) { return "${StepPrefix}commit|git add failed: $($add.output -join ' ')" }
        $staged = Invoke-RefreshGit -Arguments @("diff", "--cached", "--quiet")
        if ($staged.exitCode -eq 0) {
            & $record "${StepPrefix}commit" 'skipped' 'nothing changed'
            return $null
        }
        $commitResult = Invoke-RefreshGit -Arguments @("-c", "user.name=$RefreshIdentityName", "-c", "user.email=$RefreshIdentityEmail", "commit", "-q", "-m", $Message)
        if ($commitResult.exitCode -ne 0) { return "${StepPrefix}commit|git commit failed: $($commitResult.output -join ' ')" }
        $sha = Invoke-RefreshGit -Arguments @("rev-parse", "--short", "HEAD")
        $commits.Add([string]($sha.output -join ''))
        & $record "${StepPrefix}commit" 'passed' ([string]($sha.output -join ''))
        $push = Invoke-RefreshGit -Arguments @("push", "origin", "HEAD:main")
        if ($push.exitCode -ne 0) { return "${StepPrefix}push|git push failed: $($push.output -join ' ')" }
        & $record "${StepPrefix}push" 'passed' 'main'
        return $null
    }

    if ($Commit) {
        $identityProblems = @(Test-RefreshIdentity)
        if ($identityProblems.Count -gt 0) { return (& $finish 'identity' ($identityProblems -join '; ')) }
        & $record 'identity' 'passed' "$RefreshIdentityName <$RefreshIdentityEmail>"

        $status = Invoke-RefreshGit -Arguments @("status", "--porcelain", "--untracked-files=no")
        if ($status.exitCode -ne 0) { return (& $finish 'clean-tree' "git status failed: $($status.output -join ' ')") }
        $dirty = @($status.output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($dirty.Count -gt 0) { return (& $finish 'clean-tree' "commit or stash these first: $(($dirty | ForEach-Object { $_.Trim() }) -join ', ')") }
        & $record 'clean-tree' 'passed' $null
    }

    $syncArguments = @("-Write", "-Check", "-DraftMissingCatalogEntries", "-GraphQlPageSize", [string]$GraphQlPageSize)
    if ((Invoke-RefreshScript -Path "scripts/sync-profile.ps1" -Arguments $syncArguments) -ne 0) {
        $report = Get-RefreshReport
        $missing = if ($null -ne $report -and $report.Contains('missingPublicRepos')) { @($report['missingPublicRepos']).Count } else { 0 }
        $hint = if ($missing -gt 0) { "$missing public repo(s) have no catalog row; suppressed drafts were added to data/profile-catalog.json to finish by hand" } else { "see $RefreshReportPath" }
        return (& $finish 'sync' "sync-profile.ps1 -Check failed: $hint")
    }
    & $record 'sync' 'passed' $null

    $report = Get-RefreshReport
    foreach ($line in (Format-RefreshDownloadFloors -Report $report)) { Write-Host $line }
    & $record 'floors' 'passed' $null

    $smokeWillRun = -not [string]::IsNullOrWhiteSpace($ChromePath)
    $pageCommitted = $false
    if ($Commit) {
        # The report restamps itself every run. When the page didn't change and a smoke
        # follows, one commit after the smoke carries the report, instead of two.
        $page = Invoke-RefreshGit -Arguments @("status", "--porcelain", "--", "README.md", "projects.json", "assets/profile")
        $pageChanged = $page.exitCode -ne 0 -or @($page.output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
        if ($pageChanged -or -not $smokeWillRun) {
            $failure = & $commitAndPush (New-RefreshCommitMessage -Report $report) ''
            if ($failure) { $parts = $failure.Split('|', 2); return (& $finish $parts[0] $parts[1]) }
            $pageCommitted = $true
        } else {
            & $record 'commit' 'skipped' 'the published page already matches; the evidence commit carries the report'
        }
    }

    if (-not $smokeWillRun) {
        & $record 'smoke' 'skipped' 'CHROME_PATH is not set'
        Write-Host "Rendered smoke skipped: set CHROME_PATH to a Chromium build to run it."
        return (& $finish $null 'Refreshed without a rendered smoke.')
    }
    if ((Invoke-RefreshScript -Path "scripts/render-profile-smoke.ps1") -ne 0) {
        return (& $finish 'smoke' 'render-profile-smoke.ps1 failed; see reports/rendered-profile-smoke.json')
    }
    & $record 'smoke' 'passed' $null

    # The metadata cache is warm by now, so this second check is the quick one.
    if ((Invoke-RefreshScript -Path "scripts/sync-profile.ps1" -Arguments @("-Check", "-GraphQlPageSize", [string]$GraphQlPageSize)) -ne 0) {
        return (& $finish 'evidence' "sync-profile.ps1 -Check failed after the smoke; see $RefreshReportPath")
    }
    & $record 'evidence' 'passed' $null
    if ($Commit) {
        $evidenceMessage = if ($pageCommitted) { "chore: record the rendered smoke of the refreshed profile" } else { New-RefreshCommitMessage -Report (Get-RefreshReport) }
        $failure = & $commitAndPush $evidenceMessage 'evidence-'
        if ($failure) { $parts = $failure.Split('|', 2); return (& $finish $parts[0] $parts[1]) }
    }
    return (& $finish $null 'Refreshed with a fresh rendered smoke.')
}

if ($MyInvocation.InvocationName -eq '.' -and $env:SYSADMINDOC_TEST_SEAM -eq '1') { return }

$refresh = Invoke-ProfileRefresh -Commit:$Commit -GraphQlPageSize $GraphQlPageSize
foreach ($step in $refresh.steps) {
    $detail = if ([string]::IsNullOrWhiteSpace([string]$step.detail)) { '' } else { " ($($step.detail))" }
    Write-Host "  $($step.name): $($step.status)$detail"
}
if ($refresh.status -ne 'ok') {
    Write-Error "Refresh stopped at step '$($refresh.failedStep)': $($refresh.message)" -ErrorAction Continue
    exit 1
}
Write-Host $refresh.message
exit 0
