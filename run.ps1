#Requires -Version 5.1
# SysAdminDoc run.ps1 - starts one of the PowerShell or Python tools listed on the
# SysAdminDoc profile. It only defines Start-Tool; nothing runs until you call it.
#
# Usage (paste into PowerShell):
#   irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/run.ps1 | iex; Start-Tool <Name>
#
# Start-Tool <Name> does what the profile's older one-line snippets spelled out in full:
#   $d="$env:TEMP\<Name>"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b <branch> https://github.com/SysAdminDoc/<Name> $d};
#   if(Test-Path "$d\requirements.txt"){python -m pip install -q -r "$d\requirements.txt"}; & "$d\<entry script>"
# The branch and the entry script come from the profile's public projects.json feed. A
# .ps1 entry script runs in this PowerShell; a .py or .pyw one runs with python.
#
# A fork of the profile changes $profileOwner below to its own account; the profile's
# README check fails until it does.

function Start-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    # No function-wide $ErrorActionPreference: the entry script would inherit it, and a tool
    # written for the default would stop at its first non-terminating error. Failures here
    # throw or use -ErrorAction Stop instead.
    $profileOwner = 'SysAdminDoc'
    if ($Name -cnotmatch '^[A-Za-z0-9._-]+\z') {
        throw "Start-Tool: '$Name' is not a repository name."
    }
    # Say a tool is missing before anything is fetched. A missing git would otherwise leave an
    # old exit code behind, and the tool would be started from a folder that was never cloned.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Start-Tool: git isn't installed or isn't on PATH. The profile's first-time setup section installs it."
    }
    # On a machine without Python, the python on PATH can be the Windows Store's stand-in,
    # which prints "Python was not found" and exits 9009; one that can't report its version
    # counts as missing. Checked only when a Python tool or requirements need it.
    $pythonReady = {
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) { return $false }
        # Continue inside this block only: with the session's preference at Stop, Windows
        # PowerShell turns any stderr line into an error, and Python 2 prints its version on
        # stderr. The exit code decides.
        $ErrorActionPreference = 'Continue'
        try {
            $null = & python --version 2>&1
        } catch {
            return $false
        }
        return ($LASTEXITCODE -eq 0)
    }

    $feed = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$profileOwner/$profileOwner/main/projects.json" -ErrorAction Stop
    # Ordinal, ignoring case like GitHub's names: -eq compares by culture, which skips
    # zero-width and other invisible characters, so a feed row with one hidden in its name
    # would match.
    $project = @($feed.projects | Where-Object { [string]::Equals([string]$_.repo, $Name, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$_.entrypoint) }) | Select-Object -First 1
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

    # Before cloning: a Python tool can't start without a working python.
    $usesPython = $entrypoint -notlike '*.ps1'
    if ($usesPython -and -not (& $pythonReady)) {
        throw "Start-Tool: $repo is a Python tool, and python isn't installed. Either none is on PATH or the one there can't report its version, like the Windows Store's stand-in. The profile's first-time setup section installs it."
    }

    $directory = Join-Path $env:TEMP $repo
    if (Test-Path -LiteralPath $directory) {
        git -C $directory pull -q
    } else {
        git clone -q --depth 1 -b $branch "https://github.com/$profileOwner/$repo" $directory
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Start-Tool: git could not fetch $repo (exit $LASTEXITCODE). If $directory holds an old copy, delete it and run Start-Tool again."
    }

    $requirements = Join-Path $directory 'requirements.txt'
    if (Test-Path -LiteralPath $requirements) {
        # python -m pip, so the requirements land in the interpreter that runs the tool.
        if (-not (& $pythonReady)) {
            Write-Warning "Start-Tool: $repo lists Python requirements, but there's no working python to install them with, so it starts without them."
        } else {
            python -m pip install -q -r $requirements
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Start-Tool: installing $repo's requirements failed (exit $LASTEXITCODE); starting it anyway."
            }
        }
    }

    $target = Join-Path $directory $entrypoint
    if ($usesPython) {
        python $target
    } else {
        # From a fresh module scope, whose parent is the session: the tool sees the session's
        # variables, as it did when the old one-liner ran it from the prompt, and none of
        # Start-Tool's ($Name, $feed, $repo, $target and the rest). One difference: a module
        # the tool imports stays with that scope, so it isn't left loaded in the session
        # after the tool exits.
        & (New-Module -ScriptBlock { }) { & $args[0] } $target
    }
}
