#Requires -Version 7.4
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$NpmAuditJsonPath,
    [switch]$SkipNpmAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
    $hashCount = [regex]::Matches($requirementsText, '--hash=sha256:[a-fA-F0-9]{64}').Count
    return @(
        foreach ($match in [regex]::Matches($requirementsText, '(?m)^(?<name>[A-Za-z0-9_.-]+)==(?<version>[^\s\\]+)')) {
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
$missingPins = @(
    @($npmToolPins | Where-Object { $_.status -ne "aligned" })
    @($powerShellPins | Where-Object { $_.status -ne "pinned" })
    @($pythonToolPins | Where-Object { $_.status -ne "hash-pinned" })
).Count
$status = if ($npmAudit.status -eq "clean" -and $overrideReview.driftCount -eq 0 -and $missingPins -eq 0) {
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
    npm = [ordered]@{
        audit = $npmAudit
        overrides = $overrideReview
        devDependencyPins = $npmToolPins
    }
    powershell = [ordered]@{
        requiredModules = $powerShellPins
    }
    python = [ordered]@{
        requirementsFile = "requirements-local-audit.txt"
        auditTools = $pythonToolPins
    }
}

Write-Output ($review | ConvertTo-Json -Depth 8)
