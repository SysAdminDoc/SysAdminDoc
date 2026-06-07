#Requires -Version 5.1
# Required-check proof touch: disposable PR only.
# SysAdminDoc setup.ps1 - installs Python 3 and Git via winget so the
# README install one-liners work on a fresh machine.
#
# Usage (paste into PowerShell):
#   irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1 | iex

[CmdletBinding()]
param(
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

function Write-Step  ([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok    ([string]$m) { Write-Host "  + $m" -ForegroundColor Green }
function Write-Skip  ([string]$m) { Write-Host "  = $m" -ForegroundColor DarkGray }
function Write-Warn2 ([string]$m) { Write-Host "  ! $m" -ForegroundColor Yellow }

$script:TranscriptStarted = $false
$script:TranscriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("SysAdminDoc-setup-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)

function Test-Cmd([string]$name) {
    [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-VersionLine([string]$name) {
    if (-not (Test-Cmd $name)) {
        return $null
    }

    return (& $name --version 2>&1 | Select-Object -First 1)
}

function Start-SetupTranscript {
    try {
        Start-Transcript -Path $script:TranscriptPath -Force | Out-Null
        $script:TranscriptStarted = $true
        Write-Skip "Transcript: $script:TranscriptPath"
    } catch {
        Write-Warn2 "transcript logging unavailable: $($_.Exception.Message)"
    }
}

function Stop-SetupTranscript {
    if (-not $script:TranscriptStarted) {
        return
    }

    try {
        Stop-Transcript | Out-Null
        Write-Skip "Transcript saved: $script:TranscriptPath"
    } catch {
        Write-Warn2 "could not stop transcript cleanly: $($_.Exception.Message)"
    }
}

function Update-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Write-ToolStatus([string]$display, [string]$probe) {
    $version = Get-VersionLine $probe
    if ($version) {
        Write-Ok ("{0,-7}: {1}" -f $display, $version)
        return $true
    }

    Write-Warn2 ("{0,-7}: not found on PATH" -f $display)
    return $false
}

function Test-SetupState {
    Write-Step "Checking prerequisites"
    [ordered]@{
        Winget = Write-ToolStatus 'winget' 'winget'
        Python = Write-ToolStatus 'python' 'python'
        Pip = Write-ToolStatus 'pip' 'pip'
        Git = Write-ToolStatus 'git' 'git'
    }
}

function Install-Pkg([string]$id, [string]$display, [string]$probe) {
    if (Test-Cmd $probe) {
        $ver = Get-VersionLine $probe
        Write-Skip "$display already installed ($ver)"
        return
    }
    Write-Step "Installing $display ($id)"
    $output = winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements --scope machine 2>&1
    $exitCode = $LASTEXITCODE
    ($output | Out-String).Trim() | Write-Host
    if ($exitCode -ne 0) {
        Update-PathFromRegistry
        if (Test-Cmd $probe) {
            Write-Ok "$display installed (winget reported non-zero exit but binary is present)"
            return
        }
        Write-Warn2 "machine-scope install failed (exit $exitCode), retrying user-scope"
        $output = winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements --scope user 2>&1
        ($output | Out-String).Trim() | Write-Host
    }
    Update-PathFromRegistry
    if (Test-Cmd $probe) { Write-Ok "$display installed" }
    else { Write-Warn2 "$display not on PATH yet - close and reopen PowerShell, then re-run." }
}

try {
    Write-Host ""
    Write-Host "SysAdminDoc setup - Python 3 + Git" -ForegroundColor White
    Write-Host "------------------------------------" -ForegroundColor White
    Start-SetupTranscript

    if ($CheckOnly) {
        Write-Skip "Check-only mode: no packages will be installed."
        Update-PathFromRegistry
        $state = Test-SetupState
        if (-not $state.Winget) {
            Write-Warn2 "winget missing; install 'App Installer' from the Microsoft Store if Python or Git must be installed."
            Write-Host  "    https://apps.microsoft.com/detail/9NBLGGH4NNS1" -ForegroundColor Yellow
        }
        if ($state.Python -and $state.Git) {
            Write-Host "Python and Git are ready for the README install one-liners." -ForegroundColor Green
        } else {
            Write-Host "One or more prerequisites are missing. Run without -CheckOnly to install with winget." -ForegroundColor Yellow
        }
        return
    }

    if (-not (Test-Cmd 'winget')) {
        Write-Warn2 "winget not found. Install 'App Installer' from the Microsoft Store, then re-run:"
        Write-Host  "    https://apps.microsoft.com/detail/9NBLGGH4NNS1" -ForegroundColor Yellow
        return
    }

    Install-Pkg 'Python.Python.3.12' 'Python 3.12' 'python'
    Install-Pkg 'Git.Git'            'Git'         'git'

    Update-PathFromRegistry

    Write-Host ""
    $state = Test-SetupState

    Write-Host ""
    if ($state.Python -and $state.Git) {
        Write-Host "Done. You can now paste any install one-liner from the README." -ForegroundColor Green
    } else {
        Write-Host "Setup incomplete. Close this window, open a NEW PowerShell, and try again." -ForegroundColor Yellow
    }
} finally {
    Stop-SetupTranscript
}
