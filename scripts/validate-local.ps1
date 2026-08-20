#Requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$SkipBootstrap,

    [switch]$Pester6Compatibility,

    [string]$SupportBundlePath,

    [string[]]$SupportBundleRedactValue = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredModules = @(
    [pscustomobject]@{ Name = "Pester"; Version = "5.9.1" },
    [pscustomobject]@{ Name = "PSScriptAnalyzer"; Version = "1.25.0" }
)
$pester6CompatibilityVersion = [version]"6.1.0"
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

function Remove-IsolatedPester6ModulePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd($trimChars)
        $parent = [System.IO.Path]::GetFullPath((Split-Path -Parent $resolvedPath)).TrimEnd($trimChars)
        $leaf = Split-Path -Leaf $resolvedPath

        if (-not [string]::Equals($parent, $tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $leaf -notmatch '^SysAdminDoc-Pester6-[0-9a-f]{32}$') {
            throw "Refusing to remove unexpected Pester 6 module path: $resolvedPath"
        }

        Remove-Item -LiteralPath $resolvedPath -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warning "Could not remove isolated Pester 6 module path '$Path': $($_.Exception.Message)"
    }
}

function Invoke-Pester6Compatibility {
    <#
    .SYNOPSIS
    Installs Pester 6 into an isolated temporary module path and runs non-integration tests.
    .DESCRIPTION
    The compatibility lane runs in a child PowerShell with PSModulePath restricted to the
    temporary Save-Module destination. It never changes the default Pester 5.9.1 module pin.
    .PARAMETER RepoRoot
    Repository root containing the tests directory.
    .PARAMETER Version
    Pester 6 version to save and import for this lane.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [version]$Version
    )

    $moduleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("SysAdminDoc-Pester6-{0}" -f [guid]::NewGuid().ToString('N'))
    $result = $null
    try {
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        $saveModule = Get-Command Save-Module -ErrorAction Stop
        & $saveModule.Name -Name Pester -RequiredVersion $Version.ToString() -Path $moduleRoot -Repository PSGallery -Force -ErrorAction Stop

        $pwsh = Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $repoTests = Join-Path $RepoRoot "tests"
        $moduleRootJson = $moduleRoot | ConvertTo-Json -Compress
        $repoTestsJson = $repoTests | ConvertTo-Json -Compress
        $versionJson = $Version.ToString() | ConvertTo-Json -Compress
        $childScript = @"
`$ErrorActionPreference = 'Stop'
`$env:PSModulePath = $moduleRootJson + [System.IO.Path]::PathSeparator + `$env:PSModulePath
Import-Module Pester -RequiredVersion $versionJson -Force -ErrorAction Stop
`$pesterModule = Get-Module Pester
`$pesterResult = Invoke-Pester -Path $repoTestsJson -ExcludeTag Integration -PassThru -Output None
[ordered]@{
    pesterVersion = [string]`$pesterModule.Version
    total = [int]`$pesterResult.TotalCount
    passed = [int]`$pesterResult.PassedCount
    failed = [int]`$pesterResult.FailedCount
    skipped = [int]`$pesterResult.SkippedCount
    notRun = [int]`$pesterResult.NotRunCount
} | ConvertTo-Json -Compress
if ([int]`$pesterResult.FailedCount -gt 0) { exit 1 }
"@
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($childScript))
        $output = @(& $pwsh.Source -NoProfile -EncodedCommand $encodedCommand 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
        $jsonLine = @($output | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
        if ($jsonLine.Count -eq 0) {
            throw "Pester 6 child process returned no result JSON. Output: $($output -join ' ')"
        }

        $childResult = $jsonLine[0] | ConvertFrom-Json
        $result = [ordered]@{
            status = if ($exitCode -eq 0) { "passed" } else { "failed" }
            targetVersion = $Version.ToString()
            loadedVersion = [string]$childResult.pesterVersion
            total = [int]$childResult.total
            passed = [int]$childResult.passed
            failed = [int]$childResult.failed
            skipped = [int]$childResult.skipped
            notRun = [int]$childResult.notRun
            isolation = "temporary PSModulePath"
            note = if ($exitCode -eq 0) { "Pester 6 compatibility suite passed without changing the default Pester 5.9.1 validation lane." } else { "Pester 6 compatibility suite reported one or more failures." }
        }
    } catch {
        $result = [ordered]@{
            status = "unavailable"
            targetVersion = $Version.ToString()
            loadedVersion = $null
            total = 0
            passed = 0
            failed = 0
            skipped = 0
            notRun = 0
            isolation = "temporary PSModulePath"
            note = $_.Exception.Message
        }
    } finally {
        Remove-IsolatedPester6ModulePath -Path $moduleRoot
    }

    Write-Host ("Pester 6 compatibility: {0}; target {1}; loaded {2}; tests {3}; passed {4}; failed {5}; skipped {6}; not run {7}." -f $result.status, $result.targetVersion, $result.loadedVersion, $result.total, $result.passed, $result.failed, $result.skipped, $result.notRun)
    return $result
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
        "scripts/new-support-bundle.ps1",
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
        [string]$RepoRoot,

        [string]$OutputPath
    )

    $pwsh = Get-Command pwsh -ErrorAction Stop
    $reviewScript = Join-Path $RepoRoot "scripts/review-local-dependencies.ps1"
    $output = & $pwsh.Source -NoProfile -File $reviewScript 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $outputParent = Split-Path -Parent $OutputPath
        if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
            New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($OutputPath, $text, [System.Text.UTF8Encoding]::new($false))
    }

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

function New-LocalSupportBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$ValidationOutputPath,

        [Parameter(Mandatory)]
        [string]$DependencyReviewPath,

        [Parameter(Mandatory)]
        [ValidateSet('passed', 'failed')]
        [string]$ValidationStatus,

        [string[]]$RedactValue = @()
    )

    $pwsh = Get-Command pwsh -ErrorAction Stop
    $bundleScript = Join-Path $RepoRoot 'scripts/new-support-bundle.ps1'
    $arguments = @(
        '-NoProfile'
        '-File'
        $bundleScript
        '-OutputPath'
        $OutputPath
        '-RepoRoot'
        $RepoRoot
        '-ValidationOutputPath'
        $ValidationOutputPath
        '-ProfileReportPath'
        (Join-Path $RepoRoot 'reports/profile-sync-report.json')
        '-DependencyReviewPath'
        $DependencyReviewPath
        '-ValidationStatus'
        $ValidationStatus
    )
    if (@($RedactValue).Count -gt 0) {
        $arguments += @('-RedactValue', ($RedactValue -join ','))
    }

    $bundleOutput = & $pwsh.Source @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Support bundle generation failed with exit code $LASTEXITCODE. $($bundleOutput | Out-String)"
    }

    Write-Host "Support bundle written to $OutputPath"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$supportBundlePathResolved = $null
$validationOutputPath = $null
$dependencyReviewPath = $null
$validationTranscriptStarted = $false
$validationStatus = 'passed'
$supportBundleError = $null

if (-not [string]::IsNullOrWhiteSpace($SupportBundlePath)) {
    $supportBundlePathResolved = if ([System.IO.Path]::IsPathRooted($SupportBundlePath)) {
        [System.IO.Path]::GetFullPath($SupportBundlePath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $SupportBundlePath))
    }
    $validationOutputPath = Join-Path ([System.IO.Path]::GetTempPath()) ("SysAdminDoc-validation-{0}.log" -f [guid]::NewGuid().ToString('N'))
    $dependencyReviewPath = Join-Path ([System.IO.Path]::GetTempPath()) ("SysAdminDoc-dependency-review-{0}.json" -f [guid]::NewGuid().ToString('N'))
    try {
        Start-Transcript -Path $validationOutputPath -Force | Out-Null
        $validationTranscriptStarted = $true
    } catch {
        Write-Warning "Validation transcript unavailable: $($_.Exception.Message)"
    }
}

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

    if ($Pester6Compatibility) {
        $pester6Result = Invoke-Pester6Compatibility -RepoRoot $repoRoot -Version $pester6CompatibilityVersion
        if ($pester6Result.status -ne "passed") {
            throw "Pester 6 compatibility status: $($pester6Result.status). $($pester6Result.note)"
        }
        return
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
    Invoke-DependencyReview -RepoRoot $repoRoot -OutputPath $dependencyReviewPath

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
} catch {
    $validationStatus = 'failed'
    throw
} finally {
    Pop-Location

    if ($validationTranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
            Write-Warning "Validation transcript could not be closed cleanly: $($_.Exception.Message)"
        }
    }

    if ($supportBundlePathResolved) {
        try {
            New-LocalSupportBundle -RepoRoot $repoRoot -OutputPath $supportBundlePathResolved -ValidationOutputPath $validationOutputPath -DependencyReviewPath $dependencyReviewPath -ValidationStatus $validationStatus -RedactValue $SupportBundleRedactValue
        } catch {
            $supportBundleError = $_
            Write-Warning "Support bundle generation failed: $($_.Exception.Message)"
        }
    }
}

if ($supportBundleError) {
    throw $supportBundleError
}
