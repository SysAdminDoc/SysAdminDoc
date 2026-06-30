#Requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$SkipBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredModules = @(
    [pscustomobject]@{ Name = "Pester"; Version = "5.7.1" },
    [pscustomobject]@{ Name = "PSScriptAnalyzer"; Version = "1.25.0" }
)

function Invoke-NativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @()
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Install-RequiredModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $available = Get-Module -ListAvailable -Name $Name |
        Where-Object { $_.Version -eq [version]$Version } |
        Select-Object -First 1

    if ($available) {
        return
    }

    $installModule = Get-Command Install-Module -ErrorAction Stop
    $parameters = @{
        Name = $Name
        RequiredVersion = $Version
        Scope = "CurrentUser"
        Repository = "PSGallery"
        Force = $true
        AllowClobber = $true
        ErrorAction = "Stop"
    }
    if ($installModule.Parameters.ContainsKey("AcceptLicense")) {
        $parameters["AcceptLicense"] = $true
    }

    Install-Module @parameters
}

function Import-RequiredModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Version
    )

    Import-Module -Name $Name -RequiredVersion $Version -Force -ErrorAction Stop
}

function Assert-ScriptAnalyzerClean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $settingsPath = Join-Path $RepoRoot "PSScriptAnalyzerSettings.psd1"
    $targets = @(
        "scripts/sync-profile.ps1",
        "scripts/validate-local.ps1",
        "setup.ps1"
    )

    $findings = foreach ($target in $targets) {
        Invoke-ScriptAnalyzer -Path (Join-Path $RepoRoot $target) -Settings $settingsPath
    }

    if (@($findings).Count -gt 0) {
        $findings | Format-Table -AutoSize | Out-String | Write-Warning
        throw "PSScriptAnalyzer reported $(@($findings).Count) finding(s)."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repoRoot
try {
    $npm = Get-Command npm -ErrorAction Stop

    if (-not $SkipBootstrap) {
        Invoke-NativeCommand -FilePath $npm.Source -ArgumentList @("ci")
        foreach ($module in $requiredModules) {
            Install-RequiredModule -Name $module.Name -Version $module.Version
        }
    }

    foreach ($module in $requiredModules) {
        Import-RequiredModule -Name $module.Name -Version $module.Version
    }

    Invoke-NativeCommand -FilePath $npm.Source -ArgumentList @("run", "lint:markdown")
    Assert-ScriptAnalyzerClean -RepoRoot $repoRoot

    $pesterResult = Invoke-Pester -Path (Join-Path $repoRoot "tests") -Output Detailed -PassThru
    if ($pesterResult.FailedCount -gt 0) {
        throw "Pester reported $($pesterResult.FailedCount) failed test(s)."
    }
} finally {
    Pop-Location
}
