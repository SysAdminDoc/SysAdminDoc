#Requires -Version 7.4
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$NpmAuditJsonPath,
    [ValidateRange(1, 365)]
    [int]$PinFreshnessStaleAfterDays = 30,
    [string]$RegistryCachePath,
    [switch]$OfflineRegistry,
    [switch]$SkipNpmAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
# Registry endpoints. Fixed hosts, never built from untrusted input; package names are
# validated against $SafePackageNamePattern before interpolation.
$NpmRegistryBase = "https://registry.npmjs.org"
$PyPiRegistryBase = "https://pypi.org/pypi"
$SafePackageNamePattern = '^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$'
$Pester6CompatibilityVersion = "6.1.0"

function Get-JsonHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required JSON file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Get-MapValue {
    [CmdletBinding()]
    param(
        [object]$Map,
        [Parameter(Mandatory)]
        [string]$Key,
        [object]$Default = $null
    )

    if ($Map -is [System.Collections.IDictionary] -and $Map.Contains($Key)) {
        return $Map[$Key]
    }

    return $Default
}

function ConvertTo-Count {
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return 0
    }

    return [int]$Value
}

function ConvertTo-NpmAuditReview {
    [CmdletBinding()]
    param(
        [string]$RawJson,
        [object]$ExitCode,
        [Parameter(Mandatory)]
        [string]$Source
    )

    $command = "npm audit --json"
    if ([string]::IsNullOrWhiteSpace($RawJson)) {
        return [ordered]@{
            status = "unavailable"
            source = $Source
            command = $command
            exitCode = $ExitCode
            severityCounts = [ordered]@{ info = 0; low = 0; moderate = 0; high = 0; critical = 0; total = 0 }
            dependencyCounts = [ordered]@{ prod = 0; dev = 0; optional = 0; peer = 0; peerOptional = 0; total = 0 }
            note = "npm audit did not return JSON."
        }
    }

    try {
        $audit = $RawJson | ConvertFrom-Json -AsHashtable
    } catch {
        return [ordered]@{
            status = "invalid-json"
            source = $Source
            command = $command
            exitCode = $ExitCode
            severityCounts = [ordered]@{ info = 0; low = 0; moderate = 0; high = 0; critical = 0; total = 0 }
            dependencyCounts = [ordered]@{ prod = 0; dev = 0; optional = 0; peer = 0; peerOptional = 0; total = 0 }
            note = $_.Exception.Message
        }
    }

    $metadata = Get-MapValue -Map $audit -Key "metadata" -Default @{}
    $vulnerabilities = Get-MapValue -Map $metadata -Key "vulnerabilities" -Default @{}
    $dependencies = Get-MapValue -Map $metadata -Key "dependencies" -Default @{}
    $severityCounts = [ordered]@{
        info = ConvertTo-Count (Get-MapValue -Map $vulnerabilities -Key "info" -Default 0)
        low = ConvertTo-Count (Get-MapValue -Map $vulnerabilities -Key "low" -Default 0)
        moderate = ConvertTo-Count (Get-MapValue -Map $vulnerabilities -Key "moderate" -Default 0)
        high = ConvertTo-Count (Get-MapValue -Map $vulnerabilities -Key "high" -Default 0)
        critical = ConvertTo-Count (Get-MapValue -Map $vulnerabilities -Key "critical" -Default 0)
        total = ConvertTo-Count (Get-MapValue -Map $vulnerabilities -Key "total" -Default 0)
    }
    $dependencyCounts = [ordered]@{
        prod = ConvertTo-Count (Get-MapValue -Map $dependencies -Key "prod" -Default 0)
        dev = ConvertTo-Count (Get-MapValue -Map $dependencies -Key "dev" -Default 0)
        optional = ConvertTo-Count (Get-MapValue -Map $dependencies -Key "optional" -Default 0)
        peer = ConvertTo-Count (Get-MapValue -Map $dependencies -Key "peer" -Default 0)
        peerOptional = ConvertTo-Count (Get-MapValue -Map $dependencies -Key "peerOptional" -Default 0)
        total = ConvertTo-Count (Get-MapValue -Map $dependencies -Key "total" -Default 0)
    }
    $status = if ($severityCounts.total -eq 0) { "clean" } else { "vulnerabilities-found" }

    return [ordered]@{
        status = $status
        source = $Source
        command = $command
        exitCode = $ExitCode
        severityCounts = $severityCounts
        dependencyCounts = $dependencyCounts
        note = if ($status -eq "clean") { "npm audit reported no vulnerabilities." } else { "Review npm advisory details before updating pins." }
    }
}

function Invoke-NpmAuditReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [string]$AuditJsonPath,
        [switch]$Skip
    )

    if ($AuditJsonPath) {
        $rawJson = Get-Content -LiteralPath $AuditJsonPath -Raw
        return ConvertTo-NpmAuditReview -RawJson $rawJson -ExitCode $null -Source "file"
    }

    if ($Skip) {
        return [ordered]@{
            status = "skipped"
            source = "not-run"
            command = "npm audit --json"
            exitCode = $null
            severityCounts = [ordered]@{ info = 0; low = 0; moderate = 0; high = 0; critical = 0; total = 0 }
            dependencyCounts = [ordered]@{ prod = 0; dev = 0; optional = 0; peer = 0; peerOptional = 0; total = 0 }
            note = "Skipped by caller. Run without -SkipNpmAudit for live npm advisory data."
        }
    }

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        return [ordered]@{
            status = "unavailable"
            source = "local"
            command = "npm audit --json"
            exitCode = $null
            severityCounts = [ordered]@{ info = 0; low = 0; moderate = 0; high = 0; critical = 0; total = 0 }
            dependencyCounts = [ordered]@{ prod = 0; dev = 0; optional = 0; peer = 0; peerOptional = 0; total = 0 }
            note = "npm was not found on PATH."
        }
    }

    Push-Location -LiteralPath $RootPath
    try {
        $auditOutput = & $npm.Source audit --json 2>&1
        $auditExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    return ConvertTo-NpmAuditReview -RawJson ($auditOutput -join "`n") -ExitCode $auditExitCode -Source "local"
}

function Get-PackageOverrideReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$PackageJson,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$PackageLock
    )

    $overrides = Get-MapValue -Map $PackageJson -Key "overrides" -Default @{}
    $packages = Get-MapValue -Map $PackageLock -Key "packages" -Default @{}
    $rows = @(
        foreach ($name in @($overrides.Keys | Sort-Object)) {
            $overrideVersion = [string]$overrides[$name]
            $lockKey = "node_modules/$name"
            $lockEntry = Get-MapValue -Map $packages -Key $lockKey -Default $null
            $lockedVersion = if ($lockEntry) { [string](Get-MapValue -Map $lockEntry -Key "version" -Default "") } else { "" }
            $status = if ([string]::IsNullOrWhiteSpace($lockedVersion)) {
                "missing-lock-entry"
            } elseif ($lockedVersion -eq $overrideVersion) {
                "aligned"
            } else {
                "lock-drift"
            }

            [ordered]@{
                package = [string]$name
                overrideVersion = $overrideVersion
                lockedVersion = $lockedVersion
                status = $status
            }
        }
    )

    return [ordered]@{
        count = [int]$rows.Count
        driftCount = [int](@($rows | Where-Object { $_.status -ne "aligned" }).Count)
        rows = $rows
    }
}

function Get-NpmToolPins {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$PackageJson,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$PackageLock
    )

    $devDependencies = Get-MapValue -Map $PackageJson -Key "devDependencies" -Default @{}
    $packages = Get-MapValue -Map $PackageLock -Key "packages" -Default @{}
    return @(
        foreach ($name in @($devDependencies.Keys | Sort-Object)) {
            $manifestVersion = [string]$devDependencies[$name]
            $lockEntry = Get-MapValue -Map $packages -Key "node_modules/$name" -Default $null
            $lockedVersion = if ($lockEntry) { [string](Get-MapValue -Map $lockEntry -Key "version" -Default "") } else { "" }
            [ordered]@{
                package = [string]$name
                manifestVersion = $manifestVersion
                lockedVersion = $lockedVersion
                status = if ($manifestVersion -eq $lockedVersion) { "aligned" } else { "lock-drift" }
            }
        }
    )
}

function Get-PowerShellModulePins {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ValidationScriptPath
    )

    $validationScript = Get-Content -LiteralPath $ValidationScriptPath -Raw
    return @(
        foreach ($match in [regex]::Matches($validationScript, 'Name\s*=\s*"(?<name>[^"]+)";\s*Version\s*=\s*"(?<version>[^"]+)"')) {
            [ordered]@{
                name = [string]$match.Groups["name"].Value
                requiredVersion = [string]$match.Groups["version"].Value
                source = "scripts/validate-local.ps1"
                status = "pinned"
            }
        }
    )
}

function Get-PythonAuditToolPins {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RequirementsPath
    )

    $requirementsText = Get-Content -LiteralPath $RequirementsPath -Raw
    $hashPattern = '--hash=sha256:[a-fA-F0-9]{64}'
    # Count --hash= directives per package by slicing the text between consecutive
    # package declarations, so a multi-package requirements file reports each package's
    # own hash count instead of the file-global total.
    $packageMatches = @([regex]::Matches($requirementsText, '(?m)^(?<name>[A-Za-z0-9_.-]+)==(?<version>[^\s\\]+)'))
    return @(
        for ($i = 0; $i -lt $packageMatches.Count; $i++) {
            $match = $packageMatches[$i]
            $spanStart = $match.Index
            $spanEnd = if ($i + 1 -lt $packageMatches.Count) { $packageMatches[$i + 1].Index } else { $requirementsText.Length }
            $block = $requirementsText.Substring($spanStart, $spanEnd - $spanStart)
            $hashCount = [regex]::Matches($block, $hashPattern).Count
            [ordered]@{
                name = [string]$match.Groups["name"].Value
                requiredVersion = [string]$match.Groups["version"].Value
                source = "requirements-local-audit.txt"
                hashCount = [int]$hashCount
                hashPinned = [bool]($hashCount -gt 0)
                status = if ($hashCount -gt 0) { "hash-pinned" } else { "missing-hashes" }
            }
        }
    )
}

function Get-RegistryVersionCache {
    <#
    .SYNOPSIS
    Loads the cached registry answers and their fetch date.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ fetchedAt = $null; packages = @{} }
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        return [ordered]@{ fetchedAt = $null; packages = @{} }
    }
    $packages = @{}
    if ($raw.PSObject.Properties.Name -contains 'packages' -and $null -ne $raw.packages) {
        foreach ($property in $raw.packages.PSObject.Properties) {
            $packages[$property.Name] = [string]$property.Value
        }
    }
    # ConvertFrom-Json turns an ISO timestamp into a DateTime, and casting that back to
    # string uses the current culture, which turns a round-trippable value into
    # "09/05/2026 07:29:42" and breaks the next parse. Re-emit round-trip format.
    $fetchedAt = $null
    if ($raw.PSObject.Properties.Name -contains 'fetchedAt' -and $null -ne $raw.fetchedAt) {
        $fetchedAt = if ($raw.fetchedAt -is [datetime]) {
            ([datetimeoffset]$raw.fetchedAt).ToUniversalTime().ToString('o')
        } elseif ($raw.fetchedAt -is [datetimeoffset]) {
            $raw.fetchedAt.ToUniversalTime().ToString('o')
        } else {
            [string]$raw.fetchedAt
        }
    }
    return [ordered]@{ fetchedAt = $fetchedAt; packages = $packages }
}

function Get-RegistryLatestVersion {
    <#
    .SYNOPSIS
    Returns the registry's current latest version for one package, or $null offline.
    .DESCRIPTION
    Replaces a hand-edited "latest known" map, which reported a pin as current long
    after the registry had moved. npm answers from dist-tags.latest, PyPI from
    info.version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('npm', 'python')][string]$Kind,
        [int]$TimeoutSec = 15
    )

    if ($Name -notmatch $SafePackageNamePattern) {
        return $null
    }

    $uri = if ($Kind -eq 'npm') {
        "$NpmRegistryBase/$([uri]::EscapeDataString($Name))"
    } else {
        "$PyPiRegistryBase/$([uri]::EscapeDataString($Name))/json"
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -TimeoutSec $TimeoutSec -MaximumRedirection 3 -ErrorAction Stop
    } catch {
        return $null
    }

    if ($Kind -eq 'npm') {
        if ($response.PSObject.Properties.Name -notcontains 'dist-tags') { return $null }
        $tags = $response.'dist-tags'
        if ($null -eq $tags -or $tags.PSObject.Properties.Name -notcontains 'latest') { return $null }
        return [string]$tags.latest
    }

    if ($response.PSObject.Properties.Name -notcontains 'info' -or $null -eq $response.info) { return $null }
    if ($response.info.PSObject.Properties.Name -notcontains 'version') { return $null }
    return [string]$response.info.version
}

function Get-RegistryLatestVersionMap {
    <#
    .SYNOPSIS
    Resolves latest versions for a set of packages, falling back to the cache offline.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Packages = @(),
        [Parameter(Mandatory)][string]$CachePath,
        [switch]$Offline
    )

    $cache = Get-RegistryVersionCache -Path $CachePath
    $resolved = @{}
    $source = 'registry'
    $queried = 0
    $failed = 0

    foreach ($package in @($Packages | Where-Object { $null -ne $_ })) {
        $name = [string]$package.name
        $kind = [string]$package.kind
        $key = "$kind/$name"
        if ($Offline) {
            if ($cache.packages.ContainsKey($key)) { $resolved[$key] = $cache.packages[$key] }
            continue
        }
        $queried++
        $latest = Get-RegistryLatestVersion -Name $name -Kind $kind
        if ([string]::IsNullOrWhiteSpace($latest)) {
            $failed++
            # Fall back to the cached answer rather than claiming the version is unknown.
            if ($cache.packages.ContainsKey($key)) { $resolved[$key] = $cache.packages[$key] }
        } else {
            $resolved[$key] = $latest
        }
    }

    $fetchedAt = $cache.fetchedAt
    if (-not $Offline -and $queried -gt 0 -and $failed -lt $queried) {
        $fetchedAt = ([datetimeoffset]::Now).ToUniversalTime().ToString('o')
        try {
            $parent = Split-Path -Parent $CachePath
            if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $payload = [ordered]@{ fetchedAt = $fetchedAt; packages = [ordered]@{} }
            foreach ($key in @($resolved.Keys | Sort-Object)) { $payload.packages[$key] = $resolved[$key] }
            ($payload | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $CachePath -Encoding utf8
        } catch {
            Write-Warning "Could not write the registry version cache: $($_.Exception.Message)"
        }
    } elseif ($Offline -or $failed -eq $queried) {
        $source = if ($null -eq $cache.fetchedAt) { 'unavailable' } else { 'cache' }
    }

    return [ordered]@{
        source = $source
        fetchedAt = $fetchedAt
        queriedCount = [int]$queried
        failedCount = [int]$failed
        versions = $resolved
    }
}

function Test-CompatibleWithLatest {
    <#
    .SYNOPSIS
    Classifies a pin against the registry latest without forcing an upgrade.
    .DESCRIPTION
    A new major is review-needed, not a failure: the repo deliberately holds
    markdown-it at 14.x while 15.x exists, because the major is breaking and the
    markdownlint regression suite has not approved it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$CurrentVersion,
        [AllowNull()][AllowEmptyString()][string]$RegistryLatest
    )

    if ([string]::IsNullOrWhiteSpace($RegistryLatest)) { return 'unknown' }
    if ([string]::IsNullOrWhiteSpace($CurrentVersion)) { return 'unknown' }
    if ($CurrentVersion -ceq $RegistryLatest) { return 'current' }

    $currentParsed = $null
    $latestParsed = $null
    if (-not [version]::TryParse((($CurrentVersion -split '-')[0]), [ref]$currentParsed) -or
        -not [version]::TryParse((($RegistryLatest -split '-')[0]), [ref]$latestParsed)) {
        return 'behind-registry-latest'
    }
    if ($currentParsed -gt $latestParsed) { return 'ahead-of-registry-latest' }
    if ($currentParsed.Major -lt $latestParsed.Major) { return 'major-upgrade-available' }
    return 'behind-registry-latest'
}

function New-PinFreshnessRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [AllowNull()][AllowEmptyString()]
        [string]$RegistryLatest,

        [AllowNull()][AllowEmptyString()]
        [string]$LatestCheckedAt,

        [Parameter(Mandatory)]
        [datetimeoffset]$Now,

        [Parameter(Mandatory)]
        [int]$StaleAfterDays,

        [AllowNull()][AllowEmptyString()]
        [string]$DeclaredByParent
    )

    # Takes the resolved version directly. An earlier version rebuilt the lookup key from
    # $Kind, which is the display kind (npm-override, python-audit-tool) and never matched
    # the registry kind (npm, python), so every row silently reported "unknown".
    # Named distinctly from the $RegistryLatest parameter: PowerShell resolves variable
    # names case-insensitively, so assigning $null to $registryLatest wrote through the
    # [string]-typed parameter and came back as "" instead of null.
    $resolvedLatest = if ([string]::IsNullOrWhiteSpace($RegistryLatest)) { $null } else { [string]$RegistryLatest }
    $compatibility = Test-CompatibleWithLatest -CurrentVersion $CurrentVersion -RegistryLatest $resolvedLatest

    # Freshness is now a property of the registry evidence, not of a hand-edited date.
    $ageDays = $null
    $freshnessStatus = "unavailable"
    if (-not [string]::IsNullOrWhiteSpace($LatestCheckedAt)) {
        $checkedAt = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse($LatestCheckedAt, [ref]$checkedAt)) {
            $ageDays = [math]::Max(0, [math]::Round(($Now.ToUniversalTime() - $checkedAt.ToUniversalTime()).TotalDays, 2))
            $freshnessStatus = if ($ageDays -gt $StaleAfterDays) { "stale" } else { "fresh" }
        }
    }

    $warning = if ($freshnessStatus -eq "stale") {
        "Registry version evidence for $Kind '$Name' is $ageDays day(s) old, past the $StaleAfterDays day window; run the review online to refresh it."
    } elseif ($freshnessStatus -eq "unavailable") {
        "No registry version evidence for $Kind '$Name'; run the review online at least once."
    } else {
        $null
    }

    [ordered]@{
        name = $Name
        kind = $Kind
        declaredByParent = if ([string]::IsNullOrWhiteSpace($DeclaredByParent)) { $null } else { $DeclaredByParent }
        currentCompatible = $CurrentVersion
        registryLatest = $resolvedLatest
        compatibilityStatus = $compatibility
        latestCheckedAt = if ([string]::IsNullOrWhiteSpace($LatestCheckedAt)) { $null } else { $LatestCheckedAt }
        checkAgeDays = $ageDays
        staleAfterDays = [int]$StaleAfterDays
        freshnessStatus = $freshnessStatus
        warning = $warning
    }
}

function Get-DependencyPinFreshness {
    [CmdletBinding()]
    param(
        [object[]]$NpmOverrideRows = @(),
        [object[]]$NpmDevDependencyRows = @(),
        [object[]]$PythonAuditRows = @(),
        [Parameter(Mandatory)]
        [string]$CachePath,
        [int]$StaleAfterDays = 30,
        [datetimeoffset]$Now = [datetimeoffset]::Now,
        [switch]$Offline
    )

    # Resolve every pin against its registry in one pass, then build rows from the answer.
    $packages = @(
        foreach ($row in @($NpmOverrideRows)) { [ordered]@{ name = [string]$row.package; kind = 'npm' } }
        foreach ($row in @($NpmDevDependencyRows)) { [ordered]@{ name = [string]$row.package; kind = 'npm' } }
        foreach ($row in @($PythonAuditRows)) { [ordered]@{ name = [string]$row.name; kind = 'python' } }
    )
    $registry = Get-RegistryLatestVersionMap -Packages $packages -CachePath $CachePath -Offline:$Offline
    $latestCheckedAt = [string]$registry.fetchedAt

    $npmRows = @(
        foreach ($row in @($NpmOverrideRows)) {
            New-PinFreshnessRow `
                -Name ([string]$row.package) `
                -Kind "npm-override" `
                -CurrentVersion ([string]$row.lockedVersion) `
                -RegistryLatest ([string]$registry.versions["npm/$([string]$row.package)"]) `
                -LatestCheckedAt $latestCheckedAt `
                -Now $Now `
                -StaleAfterDays $StaleAfterDays `
                -DeclaredByParent ([string]$row.overrideVersion)
        }
        foreach ($row in @($NpmDevDependencyRows)) {
            New-PinFreshnessRow `
                -Name ([string]$row.package) `
                -Kind "npm-devDependency" `
                -CurrentVersion ([string]$row.lockedVersion) `
                -RegistryLatest ([string]$registry.versions["npm/$([string]$row.package)"]) `
                -LatestCheckedAt $latestCheckedAt `
                -Now $Now `
                -StaleAfterDays $StaleAfterDays `
                -DeclaredByParent ([string]$row.manifestVersion)
        }
    )
    $pythonRows = @(
        foreach ($row in @($PythonAuditRows)) {
            New-PinFreshnessRow `
                -Name ([string]$row.name) `
                -Kind "python-audit-tool" `
                -CurrentVersion ([string]$row.requiredVersion) `
                -RegistryLatest ([string]$registry.versions["python/$([string]$row.name)"]) `
                -LatestCheckedAt $latestCheckedAt `
                -Now $Now `
                -StaleAfterDays $StaleAfterDays `
                -DeclaredByParent $null
        }
    )
    $rows = @($npmRows + $pythonRows)
    # A new major is review-needed evidence, not a failure: the repo holds markdown-it
    # at 14.x on purpose. Only missing or stale evidence warns.
    $warnings = @($rows | Where-Object { $_.freshnessStatus -in @("stale", "unavailable") } | ForEach-Object { [string]$_.warning })
    $reviewNeeded = @($rows | Where-Object { $_.compatibilityStatus -eq "major-upgrade-available" })

    [ordered]@{
        status = if ($warnings.Count -gt 0) { "stale" } else { "fresh" }
        evidenceSource = [string]$registry.source
        latestCheckedAt = if ([string]::IsNullOrWhiteSpace($latestCheckedAt)) { $null } else { $latestCheckedAt }
        registryQueryCount = [int]$registry.queriedCount
        registryFailureCount = [int]$registry.failedCount
        reviewNeededCount = [int]$reviewNeeded.Count
        reviewNeeded = @($reviewNeeded | ForEach-Object { "$($_.kind) '$($_.name)' is at $($_.currentCompatible); registry latest is $($_.registryLatest)" })
        staleAfterDays = [int]$StaleAfterDays
        warningCount = [int]$warnings.Count
        warnings = @($warnings)
        npm = [ordered]@{
            count = [int]$npmRows.Count
            rows = $npmRows
        }
        python = [ordered]@{
            count = [int]$pythonRows.Count
            rows = $pythonRows
        }
    }
}

$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$packageJsonPath = Join-Path $resolvedRoot "package.json"
$packageLockPath = Join-Path $resolvedRoot "package-lock.json"
$requirementsPath = Join-Path $resolvedRoot "requirements-local-audit.txt"
$validationScriptPath = Join-Path $resolvedRoot "scripts/validate-local.ps1"

$packageJson = Get-JsonHashtable -Path $packageJsonPath
$packageLock = Get-JsonHashtable -Path $packageLockPath
$npmAudit = Invoke-NpmAuditReview -RootPath $resolvedRoot -AuditJsonPath $NpmAuditJsonPath -Skip:$SkipNpmAudit
$overrideReview = Get-PackageOverrideReview -PackageJson $packageJson -PackageLock $packageLock
$npmToolPins = @(Get-NpmToolPins -PackageJson $packageJson -PackageLock $packageLock)
$powerShellPins = @(Get-PowerShellModulePins -ValidationScriptPath $validationScriptPath)
$pythonToolPins = @(Get-PythonAuditToolPins -RequirementsPath $requirementsPath)
$pinFreshness = Get-DependencyPinFreshness `
    -NpmOverrideRows @($overrideReview.rows) `
    -NpmDevDependencyRows $npmToolPins `
    -PythonAuditRows $pythonToolPins `
    -CachePath $(if ([string]::IsNullOrWhiteSpace($RegistryCachePath)) { Join-Path $RepoRoot ".cache/registry-versions.json" } else { $RegistryCachePath }) `
    -StaleAfterDays $PinFreshnessStaleAfterDays `
    -Offline:$OfflineRegistry
$missingPins = (
    @($npmToolPins | Where-Object { $_.status -ne "aligned" }) +
    @($powerShellPins | Where-Object { $_.status -ne "pinned" }) +
    @($pythonToolPins | Where-Object { $_.status -ne "hash-pinned" })
).Count
$localPinReviewNeeded = [bool]($overrideReview.driftCount -ne 0 -or $missingPins -ne 0)
$status = if ($localPinReviewNeeded) {
    "review-needed"
} elseif ($npmAudit.status -eq "clean") {
    "ok"
} elseif ($npmAudit.status -eq "skipped") {
    "not-run"
} else {
    "review-needed"
}

$review = [ordered]@{
    status = $status
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    policy = "manual-local-only"
    commands = [ordered]@{
        full = "pwsh -NoProfile -File .\scripts\review-local-dependencies.ps1"
        npmAudit = "npm audit --json"
    }
    pinFreshness = $pinFreshness
    npm = [ordered]@{
        audit = $npmAudit
        overrides = $overrideReview
        devDependencyPins = $npmToolPins
    }
    powershell = [ordered]@{
        requiredModules = $powerShellPins
        compatibilityLanes = [ordered]@{
            pester6 = [ordered]@{
                status = "opt-in"
                targetVersion = $Pester6CompatibilityVersion
                command = "pwsh -NoProfile -File .\scripts\validate-local.ps1 -Pester6Compatibility"
                isolation = "temporary PSModulePath"
                note = "The default validation lane remains pinned to Pester 5.9.1."
            }
        }
    }
    python = [ordered]@{
        requirementsFile = "requirements-local-audit.txt"
        auditTools = $pythonToolPins
    }
}

Write-Output ($review | ConvertTo-Json -Depth 8)
if ($status -eq "review-needed") {
    exit 1
}
