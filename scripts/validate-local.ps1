#Requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$SkipBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredModules = @(
    [pscustomobject]@{ Name = "Pester"; Version = "5.8.0" },
    [pscustomobject]@{ Name = "PSScriptAnalyzer"; Version = "1.25.0" }
)
$minimumPowerShellVersion = [version]"7.4.0"
$preferredPowerShellVersion = [version]"7.6.0"
$previousLtsAcceptedUntil = [datetimeoffset]::Parse("2026-11-10T23:59:59Z")

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

function Get-PowerShellRuntimeChannel {
    param(
        [Parameter(Mandatory)]
        [version]$Version,

        [string]$Edition = "Core"
    )

    if ($Edition -eq "Desktop" -or $Version.Major -lt 6) {
        return "windows-powershell-bootstrap-only"
    }
    if ($Version.Major -lt 7 -or ($Version.Major -eq 7 -and $Version.Minor -lt 4)) {
        return "unsupported"
    }
    if ($Version.Major -eq 7 -and $Version.Minor -eq 4) {
        return "previous-lts"
    }
    if ($Version.Major -eq 7 -and $Version.Minor -eq 5) {
        return "stable-non-lts"
    }
    if ($Version.Major -eq 7 -and $Version.Minor -eq 6) {
        return "current-lts"
    }
    return "newer-than-current-lts"
}

function Get-ValidationPowerShellRuntimePosture {
    $version = [version]::new([int]$PSVersionTable.PSVersion.Major, [int]$PSVersionTable.PSVersion.Minor, [int]$PSVersionTable.PSVersion.Patch)
    $edition = [string]$PSVersionTable.PSEdition
    $channel = Get-PowerShellRuntimeChannel -Version $version -Edition $edition
    $warnings = New-Object System.Collections.Generic.List[string]
    $schemaFileAvailable = [bool]((Get-Command Test-Json -ErrorAction Stop).Parameters.ContainsKey("SchemaFile"))
    $meetsFloor = ($edition -ne "Desktop" -and $version -ge $minimumPowerShellVersion)
    $withinTransition = ([datetimeoffset]::Now.ToUniversalTime() -le $previousLtsAcceptedUntil)

    if (-not $meetsFloor) {
        $warnings.Add("PowerShell $version is below the generator floor $minimumPowerShellVersion.")
    } elseif ($version -lt $preferredPowerShellVersion) {
        $warnings.Add("PowerShell $version is accepted until 2026-11-10 but current LTS $preferredPowerShellVersion is preferred for local validation.")
    }
    if (-not $schemaFileAvailable) {
        $warnings.Add("Test-Json -SchemaFile is unavailable; native JSON Schema validation requires PowerShell 7.4 or newer.")
    }

    [pscustomobject]@{
        Version = $version.ToString()
        Edition = $edition
        Channel = $channel
        Supported = [bool]($meetsFloor -and $schemaFileAvailable -and ($version -ge $preferredPowerShellVersion -or $withinTransition))
        Preferred = [bool]($version -ge $preferredPowerShellVersion)
        WarningCount = [int]$warnings.Count
        Warnings = @($warnings.ToArray())
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
        "scripts/review-local-dependencies.ps1",
        "scripts/validate-local.ps1",
        "scripts/render-profile-smoke.ps1",
        "scripts/open-generated-profile-pr.ps1",
        "scripts/write-profile-sync-summary.ps1",
        "scripts/set-generated-validation-status.ps1",
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

function Invoke-DependencyReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $pwsh = Get-Command pwsh -ErrorAction Stop
    $reviewScript = Join-Path $RepoRoot "scripts/review-local-dependencies.ps1"
    $output = & $pwsh.Source -NoProfile -File $reviewScript 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if ($exitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-Warning $text
        }
        throw "Dependency review failed with exit code $exitCode."
    }

    try {
        $review = $text | ConvertFrom-Json
        Write-Host ("Dependency review: {0}; npm audit: {1}; pin freshness: {2}" -f $review.status, $review.npm.audit.status, $review.pinFreshness.status)
    } catch {
        Write-Host "Dependency review passed, but the JSON summary could not be parsed: $($_.Exception.Message)"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repoRoot
try {
    $runtimePosture = Get-ValidationPowerShellRuntimePosture
    Write-Host ("PowerShell runtime: {0} ({1}, {2}); preferred LTS: {3}" -f $runtimePosture.Version, $runtimePosture.Edition, $runtimePosture.Channel, $preferredPowerShellVersion)
    foreach ($warning in @($runtimePosture.Warnings)) {
        Write-Warning $warning
    }
    if (-not $runtimePosture.Supported) {
        throw "Unsupported PowerShell runtime for local validation."
    }

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
    Invoke-DependencyReview -RepoRoot $repoRoot

    # Invoke-Pester -Path tests with a configuration object so JaCoCo code coverage
    # (coverage.xml, gitignored) is produced for the generation engine. Profiler-based
    # coverage (UseBreakpoints = $false) keeps the large sync-profile.ps1 scan fast.
    $coveragePath = Join-Path $repoRoot "coverage.xml"
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = (Join-Path $repoRoot "tests")
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = "Detailed"
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.UseBreakpoints = $false
    $pesterConfig.CodeCoverage.Path = @(Join-Path $repoRoot "scripts/sync-profile.ps1")
    $pesterConfig.CodeCoverage.OutputFormat = "JaCoCo"
    $pesterConfig.CodeCoverage.OutputPath = $coveragePath

    $pesterResult = Invoke-Pester -Configuration $pesterConfig
    if ($pesterResult.FailedCount -gt 0) {
        throw "Pester reported $($pesterResult.FailedCount) failed test(s)."
    }

    $coverage = $pesterResult.CodeCoverage
    if ($coverage) {
        $percent = [math]::Round([double]$coverage.CoveragePercent, 2)
        $covered = [int]$coverage.CommandsExecutedCount
        $total = [int]$coverage.CommandsAnalyzedCount
        Write-Host "Code coverage: $percent% ($covered/$total commands) -> $coveragePath (JaCoCo)"
    }
} finally {
    Pop-Location
}
