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

git diff --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host $NoChangesMessage
    exit 0
}
if ($LASTEXITCODE -ne 1) {
    throw "git diff --quiet failed (exit code $LASTEXITCODE)."
}

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

$basicToken = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes("x-access-token:$env:GH_TOKEN")
)
git config --local http.https://github.com/.extraheader "Authorization: basic $basicToken"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure push credentials (exit code $LASTEXITCODE)."
}
git push origin $branch
if ($LASTEXITCODE -ne 0) {
    throw "Failed to push $branch (exit code $LASTEXITCODE)."
}

$prBody = @"
$PullRequestBodyIntro

Validation handoff: this workflow dispatches Profile sync in check mode on the generated branch after opening the pull request.
Validation runs: $validationRunsUrl
"@

$prUrl = gh pr create `
    --base $BaseBranch `
    --head $branch `
    --title $PullRequestTitle `
    --body $prBody
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create generated profile pull request (exit code $LASTEXITCODE)."
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
        "- Validation runs: $validationRunsUrl"
    ) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
}
