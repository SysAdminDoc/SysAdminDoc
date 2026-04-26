# SysAdminDoc setup.ps1 — installs Python 3 and Git via winget so the
# README install one-liners work on a fresh machine.
#
# Usage (paste into PowerShell):
#   irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1 | iex

$ErrorActionPreference = 'Stop'

function Write-Step  ([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok    ([string]$m) { Write-Host "  + $m" -ForegroundColor Green }
function Write-Skip  ([string]$m) { Write-Host "  = $m" -ForegroundColor DarkGray }
function Write-Warn2 ([string]$m) { Write-Host "  ! $m" -ForegroundColor Yellow }

function Test-Cmd([string]$name) {
    [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Update-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Install-Pkg([string]$id, [string]$display, [string]$probe) {
    if (Test-Cmd $probe) {
        $ver = (& $probe --version 2>&1 | Select-Object -First 1)
        Write-Skip "$display already installed ($ver)"
        return
    }
    Write-Step "Installing $display ($id)"
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements --scope machine 2>&1 |
        Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "machine-scope install failed, retrying user-scope"
        winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements --scope user 2>&1 |
            Out-String | Write-Host
    }
    Update-PathFromRegistry
    if (Test-Cmd $probe) { Write-Ok "$display installed" }
    else { Write-Warn2 "$display not on PATH yet — close and reopen PowerShell, then re-run." }
}

Write-Host ""
Write-Host "SysAdminDoc setup — Python 3 + Git" -ForegroundColor White
Write-Host "------------------------------------" -ForegroundColor White

if (-not (Test-Cmd 'winget')) {
    Write-Warn2 "winget not found. Install 'App Installer' from the Microsoft Store, then re-run:"
    Write-Host  "    https://apps.microsoft.com/detail/9NBLGGH4NNS1" -ForegroundColor Yellow
    return
}

Install-Pkg 'Python.Python.3.12' 'Python 3.12' 'python'
Install-Pkg 'Git.Git'            'Git'         'git'

Update-PathFromRegistry

Write-Host ""
Write-Step "Verifying"
$pyOk  = Test-Cmd 'python'
$gitOk = Test-Cmd 'git'
$pipOk = Test-Cmd 'pip'

if ($pyOk)  { Write-Ok  "python : $(python --version 2>&1)" } else { Write-Warn2 "python missing from PATH" }
if ($pipOk) { Write-Ok  "pip    : $(pip --version 2>&1)"    } else { Write-Warn2 "pip missing from PATH" }
if ($gitOk) { Write-Ok  "git    : $(git --version 2>&1)"    } else { Write-Warn2 "git missing from PATH" }

Write-Host ""
if ($pyOk -and $gitOk) {
    Write-Host "Done. You can now paste any install one-liner from the README." -ForegroundColor Green
} else {
    Write-Host "Setup incomplete. Close this window, open a NEW PowerShell, and try again." -ForegroundColor Yellow
}
