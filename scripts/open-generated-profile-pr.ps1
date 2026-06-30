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

$repository = if ([string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
    'SysAdminDoc/SysAdminDoc'
} else {
    $env:GITHUB_REPOSITORY
}
$runId = if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) {
    'manual'
} else {
    $env:GITHUB_RUN_ID
}
$branch = "$BranchPrefix$runId"

$changedGeneratedPaths = @(git diff --name-only -- @Paths)
if ($LASTEXITCODE -ne 0) {
    throw "git diff --name-only failed (exit code $LASTEXITCODE)."
}

$modeLabel = if ($DryRun) { 'Dry run' } else { 'Manual preview' }
$previewLines = @(
    '### Generated artifact manual preview',
    '',
    "- Repository: $repository",
    "- Planned branch name: $branch",
    "- Base branch: $BaseBranch",
    "- Commit message: $CommitMessage",
    "- Pull request title: $PullRequestTitle",
    "- Pull request body intro: $PullRequestBodyIntro",
    "- Retired hosted workflow name (ignored): $ValidationWorkflow",
    "- Requested validation mode (ignored): $ValidationMode",
    "- Local validation command: pwsh -NoProfile -File scripts/validate-local.ps1",
    "- No-change message: $NoChangesMessage",
    "- No-staged-change message: $NoStagedChangesMessage",
    "- Changed generated paths: $(if ($changedGeneratedPaths.Count -gt 0) { $changedGeneratedPaths -join ', ' } else { 'none' })",
    '',
    "$modeLabel`: no branch, commit, push, pull request, commit status, or hosted validation dispatch will be created."
)

foreach ($line in $previewLines) {
    Write-Host $line
}

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    $previewLines | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
}

if (-not $DryRun) {
    throw 'Hosted generated pull-request creation is retired while this repository has no GitHub Actions workflows. Rerun with -DryRun to inspect generated-artifact changes, then run scripts/validate-local.ps1 before committing locally.'
}
