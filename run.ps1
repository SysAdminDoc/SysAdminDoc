#Requires -Version 5.1
# SysAdminDoc run.ps1 - starts one of the PowerShell or Python tools listed on the
# SysAdminDoc profile. It only defines Start-Tool; nothing runs until you call it.
#
# Usage (paste into PowerShell):
#   irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/run.ps1 | iex; Start-Tool <Name>
#
# Start-Tool <Name> does what the profile's older one-line snippets spelled out in full:
#   $d="$env:TEMP\<Name>"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b <branch> https://github.com/SysAdminDoc/<Name> $d};
#   if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\<entry script>"
# The branch and the entry script come from the profile's public projects.json feed. A
# .ps1 entry script runs in this PowerShell; a .py or .pyw one runs with python.

function Start-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    $ErrorActionPreference = 'Stop'
    $profileOwner = 'SysAdminDoc'
    if ($Name -cnotmatch '^[A-Za-z0-9._-]+\z') {
        throw "Start-Tool: '$Name' is not a repository name."
    }

    # Windows PowerShell 5.1 on an older .NET default can refuse GitHub's TLS 1.2 endpoints.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $feed = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$profileOwner/$profileOwner/main/projects.json"
    $project = @($feed.projects | Where-Object { [string]$_.repo -eq $Name -and -not [string]::IsNullOrWhiteSpace([string]$_.entrypoint) }) | Select-Object -First 1
    if (-not $project) {
        throw "Start-Tool: $Name is not a project you can run from the $profileOwner profile. Check the name on https://github.com/$profileOwner."
    }

    # The feed is checked when it is generated. Check again here, because this runs on your
    # machine: nothing below may reach git, pip or the shell unless it has the expected shape.
    $repo = [string]$project.repo
    $branch = [string]$project.branch
    $entrypoint = [string]$project.entrypoint
    if ($repo -cnotmatch '^[A-Za-z0-9._-]+\z') {
        throw "Start-Tool: the feed names an unexpected repository '$repo'."
    }
    if ($branch -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*\z') {
        throw "Start-Tool: the feed names an unexpected branch '$branch' for $repo."
    }
    if ($entrypoint -cnotmatch '^(?:[A-Za-z0-9][A-Za-z0-9 ._()+-]*[\\/])*[A-Za-z0-9][A-Za-z0-9 ._()+-]*\.(?:ps1|py|pyw)\z') {
        throw "Start-Tool: the feed names an unexpected entry script '$entrypoint' for $repo."
    }

    $directory = Join-Path $env:TEMP $repo
    if (Test-Path -LiteralPath $directory) {
        git -C $directory pull -q
    } else {
        git clone -q --depth 1 -b $branch "https://github.com/$profileOwner/$repo" $directory
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Start-Tool: git could not fetch $repo (exit $LASTEXITCODE)."
    }

    $requirements = Join-Path $directory 'requirements.txt'
    if (Test-Path -LiteralPath $requirements) {
        pip install -q -r $requirements
    }

    $target = Join-Path $directory $entrypoint
    if ($entrypoint -like '*.ps1') {
        & $target
    } else {
        python $target
    }
}
