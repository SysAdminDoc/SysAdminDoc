#Requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$SkipBootstrap,

    [switch]$Pester6Compatibility,

    [switch]$SkipProfileCheck,

    [switch]$SkipLinkValidation,

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

function Invoke-ProfileCheck {
    <#
    .SYNOPSIS
    Runs the generator's own state check against the working tree.
    .DESCRIPTION
    The Pester suite validates the generator against fixtures; it never reads the
    committed README.md or projects.json. Without this lane the documented pre-push
    command could pass while the published profile was out of sync, leaked a
    suppressed repository, or carried a dead link. Runs in a child process because
    the generator and Pester can collide on already-loaded assemblies.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [switch]$SkipLinkValidation
    )

    $scriptPath = Join-Path $RepoRoot "scripts/sync-profile.ps1"
    $arguments = @("-NoProfile", "-File", $scriptPath, "-Check")
    if ($SkipLinkValidation) {
        $arguments += "-SkipLinkValidation"
    }

    Write-Host "Profile check: pwsh $($arguments -join ' ')"
    try {
        Invoke-NativeCommand -FilePath (Get-Command pwsh -ErrorAction Stop).Source -ArgumentList $arguments
    } catch {
        $reportPath = Join-Path $RepoRoot "reports/profile-sync-report.json"
        foreach ($name in @(Get-FailedProfileConditionName -ReportPath $reportPath)) {
            Write-Warning "Profile check failing condition: $name"
        }
        throw
    }
}

function Get-FailedProfileConditionName {
    <#
    .SYNOPSIS
    Names the report sections that failed, so the lane says what broke rather than
    only that something did.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReportPath
    )

    if (-not (Test-Path -LiteralPath $ReportPath)) {
        return @()
    }

    try {
        $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    } catch {
        return @()
    }

    $failed = New-Object System.Collections.Generic.List[string]
    # Mirrors the fatal signals the generator itself exits on. Kept to the small,
    # stable set so a schema addition cannot make this reporting path throw.
    foreach ($name in @("readmeInSync", "projectsExportInSync", "profileAssetsInSync")) {
        $property = $report.PSObject.Properties[$name]
        if ($property -and $property.Value -ne $true) {
            $failed.Add($name)
        }
    }
    foreach ($name in @(
            "missingPublicRepos",
            "privateVisibilityViolations",
            "medicalPrivacyViolations",
            "urlSchemeViolations",
            "orphanedSuppressedEntries",
            "linkValidationFailures")) {
        $property = $report.PSObject.Properties[$name]
        if ($property -and @($property.Value | Where-Object { $null -ne $_ }).Count -gt 0) {
            $failed.Add($name)
        }
    }

    return $failed.ToArray()
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

function Get-ModuleLockEntry {
    <#
    .SYNOPSIS
    Returns the reviewed lock record for one module version.
    .DESCRIPTION
    An exact version pin does not detect a changed same-version Gallery package, so the
    lock carries the reviewed nupkg SHA-256 and the expected Authenticode signer. A
    module with no lock record is refused rather than installed unverified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Version,

        [string]$LockPath = "data/powershell-module-lock.json"
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($LockPath)) { $LockPath } else { Join-Path $RepoRoot $LockPath }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "PowerShell module lock not found at $LockPath; cannot verify $Name $Version before import."
    }

    $lock = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    $entry = @($lock.modules | Where-Object { $_.name -ceq $Name -and $_.version -ceq $Version }) | Select-Object -First 1
    if (-not $entry) {
        throw "No reviewed lock record for $Name $Version in $LockPath; add one with its nupkg SHA-256 and expected signer before importing it."
    }
    foreach ($field in @("packageUrl", "nupkgSha256")) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.$field)) {
            throw "Lock record for $Name $Version is missing $field."
        }
    }
    if ($entry.signed -eq $true -and @($entry.expectedSigners | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
        throw "Lock record for $Name $Version claims the package is signed but names no expected signer."
    }

    return $entry
}

function Assert-ModuleAuthenticodeSigner {
    <#
    .SYNOPSIS
    Requires every signed file in an extracted module to carry the expected signer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleRoot,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string[]]$ExpectedSigners
    )

    $signable = @(Get-ChildItem -LiteralPath $ModuleRoot -Recurse -File -Include '*.psd1', '*.psm1', '*.ps1', '*.dll' -ErrorAction SilentlyContinue)
    if ($signable.Count -eq 0) {
        throw "Extracted $Name $Version contains no signable files to verify."
    }

    $allowed = @($ExpectedSigners | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    if ($allowed.Count -eq 0) {
        throw "No expected signer was supplied for $Name $Version; refusing to import."
    }

    $signedCount = 0
    $unsigned = New-Object System.Collections.Generic.List[string]
    foreach ($file in $signable) {
        $signature = Get-AuthenticodeSignature -FilePath $file.FullName
        if ($signature.Status -eq "NotSigned") {
            # A package the lock records as signed should not contain unsigned
            # executable content: stripping a signature block is how a tampered file
            # slips past a check that only looks at files which still carry one.
            $unsigned.Add([string]$file.Name)
            continue
        }
        if ($signature.Status -ne "Valid") {
            throw "$Name $Version file '$($file.Name)' has Authenticode status $($signature.Status); refusing to import."
        }
        $subject = [string]$signature.SignerCertificate.Subject
        # A module may legitimately bundle third-party signed assemblies, so the lock
        # names the full set of signers it is allowed to ship. Comparison is
        # case-sensitive: a transliterated subject is a different signer.
        if (@($allowed | Where-Object { $_ -ceq $subject }).Count -eq 0) {
            throw "$Name $Version file '$($file.Name)' is signed by '$subject', which the lock does not list for this module; refusing to import."
        }
        $signedCount++
    }

    if ($unsigned.Count -gt 0) {
        throw "$Name $Version is recorded as signed but $($unsigned.Count) extracted file(s) carry no signature ($($unsigned -join ', ')); refusing to import."
    }
    if ($signedCount -eq 0) {
        throw "$Name $Version is recorded as signed in the lock but no extracted file carries a signature; refusing to import."
    }

    return $signedCount
}

function Install-RequiredModule {
    <#
    .SYNOPSIS
    Installs a pinned module only after its package bytes and signer match the lock.
    .DESCRIPTION
    Downloads the Gallery nupkg, verifies its SHA-256 against the reviewed lock BEFORE
    extracting anything, expands it into the user module path, then requires the
    expected Authenticode signer on every signed file. A verified nupkg cached under
    the repo supports an offline lane.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$CacheRoot,

        [string]$DestinationRoot
    )

    $entry = Get-ModuleLockEntry -RepoRoot $RepoRoot -Name $Name -Version $Version

    $available = Get-Module -ListAvailable -Name $Name |
        Where-Object { $_.Version -eq [version]$Version } |
        Select-Object -First 1
    if ($available -and [string]::IsNullOrWhiteSpace($DestinationRoot)) {
        # Already present from a previous verified install. Re-check the signer, which is
        # cheap, rather than trusting that whatever is on disk arrived through this path.
        if ($entry.signed -eq $true) {
            $null = Assert-ModuleAuthenticodeSigner -ModuleRoot (Split-Path -Parent $available.Path) `
                -Name $Name -Version $Version -ExpectedSigners (@($entry.expectedSigners))
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
        $CacheRoot = Join-Path $RepoRoot ".cache/powershell-modules"
    }
    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
    $nupkgPath = Join-Path $CacheRoot "$Name.$Version.nupkg"

    if (-not (Test-Path -LiteralPath $nupkgPath)) {
        Write-Host "Downloading $Name $Version from $($entry.packageUrl)"
        Invoke-WebRequest -Uri ([string]$entry.packageUrl) -OutFile $nupkgPath -MaximumRedirection 5 -UseBasicParsing -ErrorAction Stop
    } else {
        Write-Host "Using cached package $nupkgPath"
    }

    $actualHash = (Get-FileHash -LiteralPath $nupkgPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = ([string]$entry.nupkgSha256).ToLowerInvariant()
    if ($actualHash -cne $expectedHash) {
        # Remove the bad bytes so a retry cannot pick them back up from the cache.
        Remove-Item -LiteralPath $nupkgPath -Force -ErrorAction SilentlyContinue
        throw "$Name $Version package hash $actualHash does not match the reviewed $expectedHash; refusing to extract."
    }

    # Explicit destination so a caller (and a test) can install somewhere other than the
    # real CurrentUser tree. Defaults to the CurrentUser scope Install-Module would use.
    $userModuleRoot = $DestinationRoot
    if ([string]::IsNullOrWhiteSpace($userModuleRoot)) {
        $userModuleRoot = ($env:PSModulePath -split [System.IO.Path]::PathSeparator |
            Where-Object { $_ -like "$([Environment]::GetFolderPath('MyDocuments'))*" } |
            Select-Object -First 1)
    }
    if ([string]::IsNullOrWhiteSpace($userModuleRoot)) {
        $userModuleRoot = ($env:PSModulePath -split [System.IO.Path]::PathSeparator | Select-Object -First 1)
    }
    $destination = Join-Path (Join-Path $userModuleRoot $Name) $Version
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Expand-Archive -LiteralPath $nupkgPath -DestinationPath $destination -Force

    # Package plumbing, not module content; leaving it behind confuses module discovery.
    foreach ($residue in @('_rels', 'package', '[Content_Types].xml', "$Name.nuspec")) {
        $residuePath = Join-Path $destination $residue
        if (Test-Path -LiteralPath $residuePath) {
            Remove-Item -LiteralPath $residuePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($entry.signed -eq $true) {
        $verified = Assert-ModuleAuthenticodeSigner -ModuleRoot $destination -Name $Name -Version $Version -ExpectedSigners (@($entry.expectedSigners))
        Write-Host "Verified ${Name} ${Version}: package hash matches the lock and $verified signed file(s) carry the expected signer."
    } else {
        Write-Host "Verified $Name $Version by reviewed package hash; the lock records this package as unsigned."
    }
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
        # Same verification as the default lane: reviewed package bytes before extraction,
        # expected signer before import. Save-Module would take whatever the Gallery
        # served for that version.
        $entry = Get-ModuleLockEntry -RepoRoot $RepoRoot -Name 'Pester' -Version $Version.ToString()
        $nupkgPath = Join-Path $moduleRoot "Pester.$($Version).nupkg"
        Invoke-WebRequest -Uri ([string]$entry.packageUrl) -OutFile $nupkgPath -MaximumRedirection 5 -UseBasicParsing -ErrorAction Stop
        $actualHash = (Get-FileHash -LiteralPath $nupkgPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -cne ([string]$entry.nupkgSha256).ToLowerInvariant()) {
            throw "Pester $Version package hash $actualHash does not match the reviewed $($entry.nupkgSha256); refusing to extract."
        }
        $destination = Join-Path (Join-Path $moduleRoot 'Pester') $Version.ToString()
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Expand-Archive -LiteralPath $nupkgPath -DestinationPath $destination -Force
        Remove-Item -LiteralPath $nupkgPath -Force -ErrorAction SilentlyContinue
        foreach ($residue in @('_rels', 'package', '[Content_Types].xml', 'Pester.nuspec')) {
            $residuePath = Join-Path $destination $residue
            if (Test-Path -LiteralPath $residuePath) {
                Remove-Item -LiteralPath $residuePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if ($entry.signed -eq $true) {
            $null = Assert-ModuleAuthenticodeSigner -ModuleRoot $destination -Name 'Pester' -Version $Version.ToString() -ExpectedSigners (@($entry.expectedSigners))
        }

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
        "scripts/write-profile-sync-summary.ps1",
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

function Get-NpmSupplyChainPosture {
    <#
    .SYNOPSIS
    Reports whether npm is actually running with the committed supply-chain settings.
    .DESCRIPTION
    A committed .npmrc is a claim, not a control. npm resolves config from four files
    plus the environment, so a user-level or environment override can quietly turn
    ignore-scripts back on for the very install this lane is meant to protect. This asks
    npm what it resolved rather than trusting the file. min-release-age only exists from
    npm 11.5.0, so on older npm it is reported as unsupported instead of failing a clone
    that cannot honour it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NpmPath,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $expected = [ordered]@{
        "ignore-scripts" = "true"
        "audit-level" = "high"
        "min-release-age" = "1"
    }
    $minReleaseAgeFloor = [version]"11.5.0"

    Push-Location -LiteralPath $RepoRoot
    try {
        $resolvedVersion = (& $NpmPath --version 2>&1 | Out-String).Trim()
        $resolved = [ordered]@{}
        foreach ($key in $expected.Keys) {
            $resolved[$key] = (& $NpmPath config get $key 2>&1 | Out-String).Trim()
        }
    } finally {
        Pop-Location
    }

    $parsedVersion = $null
    $supportsMinReleaseAge = $true
    if ([version]::TryParse((($resolvedVersion -split '-')[0]), [ref]$parsedVersion)) {
        $supportsMinReleaseAge = $parsedVersion -ge $minReleaseAgeFloor
    }

    $settings = @()
    $violations = @()
    $warnings = @()
    foreach ($key in $expected.Keys) {
        $actual = [string]$resolved[$key]
        $required = -not ($key -eq "min-release-age" -and -not $supportsMinReleaseAge)
        $status = if ($actual -ceq $expected[$key]) {
            "enforced"
        } elseif (-not $required) {
            "unsupported"
        } else {
            "overridden"
        }

        $settings += [ordered]@{
            key = $key
            expected = $expected[$key]
            actual = $actual
            status = $status
        }

        if ($status -eq "overridden") {
            $violations += "npm resolved $key to '$actual'; the committed .npmrc requires '$($expected[$key])'."
        } elseif ($status -eq "unsupported") {
            $warnings += "npm $resolvedVersion predates min-release-age support (npm $minReleaseAgeFloor); the setting is committed but not enforced here."
        }
    }

    return [ordered]@{
        npmVersion = $resolvedVersion
        supportsMinReleaseAge = [bool]$supportsMinReleaseAge
        settings = $settings
        violations = @($violations)
        warnings = @($warnings)
        status = if (@($violations).Count -gt 0) { "overridden" } else { "enforced" }
    }
}

function Assert-NpmSupplyChainDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NpmPath,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $posture = Get-NpmSupplyChainPosture -NpmPath $NpmPath -RepoRoot $RepoRoot
    foreach ($warning in @($posture.warnings)) {
        Write-Warning $warning
    }
    if ($posture.status -ne "enforced") {
        foreach ($violation in @($posture.violations)) {
            Write-Warning $violation
        }
        throw "npm is not running with the committed supply-chain settings. Remove the overriding config before installing dependencies."
    }

    Write-Host ("npm supply chain: {0} (npm {1}); {2}" -f $posture.status, $posture.npmVersion, (@($posture.settings | ForEach-Object { "$($_.key)=$($_.actual)" }) -join ", "))
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

    # Persist the result where the generator can read it. The Dependabot posture treats
    # this lane as the compensating control for the banned Dependabot setting, and a
    # control nobody can see the result of is not evidence. Gitignored, local-only.
    $reviewArtifactPath = Join-Path $RepoRoot "reports/dependency-review.json"
    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $reviewArtifactPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($reviewArtifactPath, $text, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-Warning "Could not record the dependency review artifact: $($_.Exception.Message)"
    }

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
        Write-Host ("Dependency review: {0}; npm audit: {1}; signatures: {2}; pin freshness: {3}" -f $review.status, $review.npm.audit.status, $review.npm.signatures.status, $review.pinFreshness.status)
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
    Assert-NpmSupplyChainDefaults -NpmPath $npm.Source -RepoRoot $repoRoot

    if (-not $SkipBootstrap) {
        Invoke-NativeCommand -FilePath $npm.Source -ArgumentList @("ci")
        foreach ($module in $requiredModules) {
            Install-RequiredModule -Name $module.Name -Version $module.Version -RepoRoot $repoRoot
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

    if ($SkipProfileCheck) {
        Write-Warning "Skipped lane: profile check (-SkipProfileCheck). Catalog, privacy, link, and artifact-sync evidence was not validated."
    } else {
        if ($SkipLinkValidation) {
            Write-Warning "Reduced lane: profile check running with -SkipLinkValidation; outbound link targets were not probed."
        }
        Invoke-ProfileCheck -RepoRoot $repoRoot -SkipLinkValidation:$SkipLinkValidation
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
