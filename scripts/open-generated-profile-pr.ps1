#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('automation/profile-sync-', 'automation/profile-assets-')]
    [string]$BranchPrefix,

    [Parameter(Mandatory)]
    [string]$CommitMessage,

    [Parameter(Mandatory)]
    [string]$PullRequestTitle,

    [Parameter(Mandatory)]
    [string]$PullRequestBodyIntro,

    [Parameter(Mandatory)]
    [string]$NoChangesMessage,

    [Parameter(Mandatory)]
    [string]$NoStagedChangesMessage,

    [string]$BaseBranch = 'main',

    [string]$ValidationWorkflow = 'profile-sync.yml',

    [string]$ValidationMode = 'check',

    [string[]]$Paths = @(
        'README.md',
        'projects.json',
        'reports/profile-sync-report.json',
        'assets/profile/*.svg'
    ),

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$missingEnvironment = @()
foreach ($name in @('GH_TOKEN', 'GITHUB_REPOSITORY', 'GITHUB_RUN_ID')) {
    if ([string]::IsNullOrWhiteSpace([string][Environment]::GetEnvironmentVariable($name))) {
        $missingEnvironment += $name
    }
}
if ($missingEnvironment.Count -gt 0 -and -not $DryRun) {
    throw "$($missingEnvironment -join ', ') required."
}

$repository = if ([string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
    'SysAdminDoc/SysAdminDoc'
} else {
    $env:GITHUB_REPOSITORY
}
$runId = if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) {
    'dry-run'
} else {
    $env:GITHUB_RUN_ID
}
$branch = "$BranchPrefix$runId"

$changedGeneratedPaths = @(git diff --name-only -- @Paths)
if ($LASTEXITCODE -ne 0) {
    throw "git diff --name-only failed (exit code $LASTEXITCODE)."
}
$validationQuery = [uri]::EscapeDataString("branch:$branch")
$validationRunsUrl = "https://github.com/$repository/actions/workflows/$ValidationWorkflow" +
    "?query=$validationQuery"

if ($DryRun) {
    $dryRunLines = @(
        '### Generated profile PR dry run'
        ''
        "- Repository: $repository"
        "- Planned branch: $branch"
        "- Base branch: $BaseBranch"
        "- Commit message: $CommitMessage"
        "- Pull request title: $PullRequestTitle"
        "- Validation workflow: $ValidationWorkflow"
        "- Validation mode: $ValidationMode"
        "- Validation runs URL: $validationRunsUrl"
        "- Missing CI environment: $(if ($missingEnvironment.Count -gt 0) { $missingEnvironment -join ', ' } else { 'none' })"
        "- Changed generated paths: $(if ($changedGeneratedPaths.Count -gt 0) { $changedGeneratedPaths -join ', ' } else { 'none' })"
        ''
        'Dry run: no branch, commit, push, pull request, or validation dispatch will be created.'
    )
    foreach ($line in $dryRunLines) {
        Write-Host $line
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        $dryRunLines | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
    }
    exit 0
}

function Assert-GitHubActionsCanCreatePullRequests {
    if ($env:GITHUB_ACTIONS -ne 'true') {
        return
    }

    $permissions = $null
    $output = gh api "repos/$repository/actions/permissions/workflow" 2>&1
    $text = (($output | Out-String).Trim())
    if ($LASTEXITCODE -ne 0) {
        if ($text -match 'Resource not accessible by integration') {
            Write-Warning "Unable to verify GitHub Actions workflow permissions before creating $branch because GITHUB_TOKEN cannot read the repository workflow-permissions endpoint; continuing to gh pr create."
            return
        }
        throw "Unable to verify GitHub Actions workflow permissions before creating $branch. $text"
    }

    try {
        $permissions = $text | ConvertFrom-Json
    } catch {
        throw "Unable to parse GitHub Actions workflow permissions before creating $branch."
    }

    if ($permissions.can_approve_pull_request_reviews -ne $true) {
        throw "GitHub Actions workflow permissions do not allow GITHUB_TOKEN to create pull requests. Enable 'Allow GitHub Actions to create and approve pull requests' or provide an approved non-GITHUB_TOKEN credential before running generated PR delivery."
    }
}

git diff --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host $NoChangesMessage
    exit 0
}
if ($LASTEXITCODE -ne 1) {
    throw "git diff --quiet failed (exit code $LASTEXITCODE)."
}

Assert-GitHubActionsCanCreatePullRequests

git switch -c $branch
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create branch $branch (exit code $LASTEXITCODE)."
}
git config user.name 'github-actions[bot]'
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure commit user name (exit code $LASTEXITCODE)."
}
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure commit user email (exit code $LASTEXITCODE)."
}
git add -- @Paths
if ($LASTEXITCODE -ne 0) {
    throw "Failed to stage generated profile artifacts (exit code $LASTEXITCODE)."
}

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host $NoStagedChangesMessage
    exit 0
}
if ($LASTEXITCODE -ne 1) {
    throw "git diff --cached --quiet failed (exit code $LASTEXITCODE)."
}

git commit -m $CommitMessage
if ($LASTEXITCODE -ne 0) {
    throw "Failed to commit generated profile artifacts (exit code $LASTEXITCODE)."
}
$generatedHeadSha = (git rev-parse HEAD)
if ($LASTEXITCODE -ne 0) {
    throw "Failed to read generated profile commit SHA (exit code $LASTEXITCODE)."
}
$generatedHeadSha = $generatedHeadSha.Trim()

$branchPushed = $false
$basicToken = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes("x-access-token:$env:GH_TOKEN")
)
git config --local http.https://github.com/.extraheader "Authorization: basic $basicToken"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure push credentials (exit code $LASTEXITCODE)."
}
try {
    git push origin $branch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push $branch (exit code $LASTEXITCODE)."
    }
    $branchPushed = $true
} finally {
    git config --local --unset http.https://github.com/.extraheader 2>$null
}

try {
    & (Join-Path $PSScriptRoot 'set-generated-validation-status.ps1') `
        -State pending `
        -Repository $repository `
        -Sha $generatedHeadSha `
        -TargetUrl $validationRunsUrl `
        -Description 'Generated profile validation pending.'
} catch {
    git push origin --delete $branch
    if ($LASTEXITCODE -eq 0) {
        Write-Warning "Deleted generated branch $branch after generated validation status publishing failed."
    } else {
        Write-Warning "Failed to delete generated branch $branch after generated validation status publishing failed (exit code $LASTEXITCODE)."
    }
    throw
}

$prBody = @"
$PullRequestBodyIntro

Validation handoff: this workflow dispatches Profile sync in check mode on the generated branch after opening the pull request.
Status context: generated-profile/validation
Validation runs: $validationRunsUrl
"@

$prUrl = gh pr create `
    --base $BaseBranch `
    --head $branch `
    --title $PullRequestTitle `
    --body $prBody
if ($LASTEXITCODE -ne 0) {
    $prCreateExitCode = $LASTEXITCODE
    if ($branchPushed) {
        git push origin --delete $branch
        if ($LASTEXITCODE -eq 0) {
            Write-Warning "Deleted generated branch $branch after pull-request creation failed."
        } else {
            Write-Warning "Failed to delete generated branch $branch after pull-request creation failed (exit code $LASTEXITCODE)."
        }
    }
    throw "Failed to create generated profile pull request (exit code $prCreateExitCode)."
}

gh workflow run $ValidationWorkflow --ref $branch -f "mode=$ValidationMode"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to dispatch generated profile validation (exit code $LASTEXITCODE)."
}

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    @(
        '### Generated profile PR validation handoff'
        ''
        "- Pull request: $prUrl"
        ("- Dispatched: Profile sync check on ``{0}``" -f $branch)
        "- Status context: generated-profile/validation"
        "- Validation runs: $validationRunsUrl"
    ) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
}
