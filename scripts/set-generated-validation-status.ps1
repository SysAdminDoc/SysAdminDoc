#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('pending', 'success', 'failure', 'error')]
    [string]$State,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Description,

    [ValidateNotNullOrEmpty()]
    [string]$Context = 'generated-profile/validation',

    [string]$Repository = $env:GITHUB_REPOSITORY,

    [string]$Sha = $env:GITHUB_SHA,

    [string]$RunId = $env:GITHUB_RUN_ID,

    [string]$ServerUrl = $env:GITHUB_SERVER_URL,

    [string]$TargetUrl,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Repository)) {
    throw 'Repository is required.'
}
if ([string]::IsNullOrWhiteSpace($Sha)) {
    throw 'Commit SHA is required.'
}
if (-not [regex]::IsMatch($Sha, '^[a-f0-9]{40}$')) {
    throw "Commit SHA '$Sha' must be a 40-character lowercase hexadecimal value."
}
if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
    $ServerUrl = 'https://github.com'
}
if ([string]::IsNullOrWhiteSpace($TargetUrl)) {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw 'RunId or TargetUrl is required.'
    }
    $TargetUrl = "$ServerUrl/$Repository/actions/runs/$RunId"
}
if ($Description.Length -gt 140) {
    throw 'Description must be 140 characters or fewer for the commit status API.'
}

$payload = [ordered]@{
    state = $State
    target_url = $TargetUrl
    description = $Description
    context = $Context
}

if ($DryRun) {
    $payload | ConvertTo-Json -Depth 4
    exit 0
}

if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    throw 'GH_TOKEN is required.'
}

gh api -X POST "repos/$Repository/statuses/$Sha" `
    -f "state=$State" `
    -f "target_url=$TargetUrl" `
    -f "description=$Description" `
    -f "context=$Context" > $null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set commit status '$Context' to '$State' for $Sha."
}

Write-Host "Set commit status '$Context' to '$State' for $Sha."
