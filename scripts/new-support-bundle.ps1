#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputPath,

    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$ValidationOutputPath,

    [string]$ProfileReportPath,

    [string]$DependencyReviewPath,

    [string]$SetupTranscriptPath,

    [ValidateSet('Auto', 'Zip', 'Json')]
    [string]$Format = 'Auto',

    [ValidateSet('not-provided', 'passed', 'failed')]
    [string]$ValidationStatus = 'not-provided',

    [ValidateRange(1024, 52428800)]
    [int]$MaxInputBytes = 5MB,

    [string[]]$RedactValue = @(),

    [string[]]$RedactPattern = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SupportToolVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string[]]$Arguments = @('--version')
    )

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return 'not-installed'
    }

    try {
        $output = & $command.Source @Arguments 2>&1 | Select-Object -First 1
        if ($output) {
            return ([string]$output).Trim()
        }
    } catch {
        return 'unavailable'
    }

    return 'unknown'
}

function Get-SupportToolVersions {
    [CmdletBinding()]
    param()

    $pester = Get-Module -ListAvailable -Name Pester -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    $scriptAnalyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    [ordered]@{
        powershell = [string]$PSVersionTable.PSVersion
        pester = if ($pester) { [string]$pester.Version } else { 'not-installed' }
        psscriptanalyzer = if ($scriptAnalyzer) { [string]$scriptAnalyzer.Version } else { 'not-installed' }
        node = Get-SupportToolVersion -Name 'node'
        npm = Get-SupportToolVersion -Name 'npm'
        git = Get-SupportToolVersion -Name 'git'
        python = Get-SupportToolVersion -Name 'python' -Arguments @('--version')
        gh = Get-SupportToolVersion -Name 'gh'
    }
}

function ConvertTo-RedactedSupportText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text,

        [AllowEmptyCollection()]
        [string[]]$AdditionalValues = @(),

        [AllowEmptyCollection()]
        [string[]]$AdditionalPatterns = @()
    )

    $result = if ($null -eq $Text) { '' } else { $Text }

    foreach ($value in @($AdditionalValues)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $result = [regex]::Replace($result, [regex]::Escape($value), '<REDACTED_VALUE>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }

    foreach ($pattern in @($AdditionalPatterns)) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        try {
            $result = [regex]::Replace($result, $pattern, '<REDACTED_VALUE>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        } catch {
            throw "Invalid support-bundle redaction pattern: $pattern"
        }
    }

    $userPathPattern = '(?i)(?:[A-Z]:\\Users\\|/Users/|/home/)[^ \t\r\n"''<>]+'
    $result = [regex]::Replace($result, $userPathPattern, '<REDACTED_USER_PATH>')

    $tokenPattern = '(?i)\b(?:ghp_|github_pat_|glpat-|xox[baprs]-|sk-)[A-Za-z0-9_-]+'
    $result = [regex]::Replace($result, $tokenPattern, '<REDACTED_TOKEN>')

    $bearerPattern = '(?i)(\bBearer\s+)[A-Za-z0-9._~+/=-]+'
    $result = [regex]::Replace($result, $bearerPattern, '$1<REDACTED_TOKEN>')

    $secretPattern = '(?i)(["'']?\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|passwd|secret|client[_-]?secret)\b["'']?\s*[:=]\s*)["'']?[^\s,"'';}]+'
    $result = [regex]::Replace($result, $secretPattern, '$1<REDACTED_SECRET>')

    $querySecretPattern = '(?i)([?&](?:token|access_token|api_key|signature|sig|key)=)[^&#\s"''<>]+'
    $result = [regex]::Replace($result, $querySecretPattern, '$1<REDACTED_QUERY_VALUE>')

    return $result
}

function Limit-SupportText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [ValidateRange(1024, 52428800)]
        [int]$MaxBytes
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $bytes = $encoding.GetBytes($Text)
    if ($bytes.Length -le $MaxBytes) {
        return $Text
    }

    $prefix = $encoding.GetString($bytes, 0, $MaxBytes)
    return $prefix + "`n[Support bundle input truncated at $MaxBytes bytes.]"
}

function Get-SupportEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogicalName,

        [string]$SourcePath,

        [Parameter(Mandatory)]
        [int]$MaxBytes,

        [string[]]$AdditionalValues = @(),

        [string[]]$AdditionalPatterns = @()
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return [pscustomobject]@{
            name = $LogicalName
            status = 'not-provided'
            bytes = 0
            content = "No $LogicalName was supplied."
            redacted = $true
        }
    }

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return [pscustomobject]@{
            name = $LogicalName
            status = 'missing'
            bytes = 0
            content = "The supplied $LogicalName file was not available."
            redacted = $true
        }
    }

    try {
        $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath).Path)
        $redacted = ConvertTo-RedactedSupportText -Text $raw -AdditionalValues $AdditionalValues -AdditionalPatterns $AdditionalPatterns
        $limited = Limit-SupportText -Text $redacted -MaxBytes $MaxBytes
        $encoding = [System.Text.UTF8Encoding]::new($false)

        return [pscustomobject]@{
            name = $LogicalName
            status = 'included'
            bytes = $encoding.GetByteCount($limited)
            content = $limited
            redacted = $true
        }
    } catch {
        $message = ConvertTo-RedactedSupportText -Text $_.Exception.Message -AdditionalValues $AdditionalValues -AdditionalPatterns $AdditionalPatterns
        return [pscustomobject]@{
            name = $LogicalName
            status = 'unreadable'
            bytes = 0
            content = "Unable to include ${LogicalName}: $message"
            redacted = $true
        }
    }
}

function Get-SupportBundleJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ValidationStatus,

        [Parameter(Mandatory)]
        [hashtable]$ToolVersions,

        [Parameter(Mandatory)]
        [object[]]$Evidence,

        [Parameter(Mandatory)]
        [bool]$IncludeContent
    )

    $evidencePayload = foreach ($item in @($Evidence)) {
        $payload = [ordered]@{
            name = $item.name
            status = $item.status
            bytes = [int]$item.bytes
            redacted = [bool]$item.redacted
        }
        if ($IncludeContent) {
            $payload.content = [string]$item.content
        }
        [pscustomobject]$payload
    }

    $bundle = [ordered]@{
        schemaVersion = 'sysadmindoc-support-bundle.v1'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        validationStatus = $ValidationStatus
        redaction = [ordered]@{
            applied = $true
            userPaths = '<REDACTED_USER_PATH>'
            tokens = '<REDACTED_TOKEN>'
            secrets = '<REDACTED_SECRET>'
            callerValues = '<REDACTED_VALUE>'
            queryValues = '<REDACTED_QUERY_VALUE>'
        }
        toolVersions = $ToolVersions
        evidence = @($evidencePayload)
    }

    return ($bundle | ConvertTo-Json -Depth 12)
}

function New-SupportBundle {
    <#
    .SYNOPSIS
        Creates a redacted JSON or ZIP support bundle from local validation evidence.

    .DESCRIPTION
        Only logical evidence names are written to the manifest. Source paths are
        never stored, and evidence text is redacted for user paths, common tokens,
        secret assignments, query credentials, and caller-supplied private values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$ValidationOutputPath,

        [string]$ProfileReportPath,

        [string]$DependencyReviewPath,

        [string]$SetupTranscriptPath,

        [ValidateSet('Auto', 'Zip', 'Json')]
        [string]$Format = 'Auto',

        [ValidateSet('not-provided', 'passed', 'failed')]
        [string]$ValidationStatus = 'not-provided',

        [ValidateRange(1024, 52428800)]
        [int]$MaxInputBytes = 5MB,

        [string[]]$RedactValue = @(),

        [string[]]$RedactPattern = @()
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    $outputParent = Split-Path -Parent $resolvedOutput
    if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }

    $normalizedRedactValues = @(
        foreach ($value in @($RedactValue)) {
            foreach ($part in ([string]$value -split ',')) {
                if (-not [string]::IsNullOrWhiteSpace($part)) {
                    $part.Trim()
                }
            }
        }
    )
    $evidence = @(
        Get-SupportEvidence -LogicalName 'validation-output.txt' -SourcePath $ValidationOutputPath -MaxBytes $MaxInputBytes -AdditionalValues $normalizedRedactValues -AdditionalPatterns $RedactPattern
        Get-SupportEvidence -LogicalName 'profile-sync-report.json' -SourcePath $ProfileReportPath -MaxBytes $MaxInputBytes -AdditionalValues $normalizedRedactValues -AdditionalPatterns $RedactPattern
        Get-SupportEvidence -LogicalName 'dependency-review.json' -SourcePath $DependencyReviewPath -MaxBytes $MaxInputBytes -AdditionalValues $normalizedRedactValues -AdditionalPatterns $RedactPattern
        Get-SupportEvidence -LogicalName 'setup-transcript.log' -SourcePath $SetupTranscriptPath -MaxBytes $MaxInputBytes -AdditionalValues $normalizedRedactValues -AdditionalPatterns $RedactPattern
    )

    $effectiveFormat = $Format
    if ($effectiveFormat -eq 'Auto') {
        $effectiveFormat = if ([System.IO.Path]::GetExtension($resolvedOutput) -ieq '.json') { 'Json' } else { 'Zip' }
    }

    $toolVersions = Get-SupportToolVersions
    if ($effectiveFormat -eq 'Json') {
        $json = Get-SupportBundleJson -ValidationStatus $ValidationStatus -ToolVersions $toolVersions -Evidence $evidence -IncludeContent $true
        [System.IO.File]::WriteAllText($resolvedOutput, $json, [System.Text.UTF8Encoding]::new($false))
    } else {
        Add-Type -AssemblyName System.IO.Compression
        $manifestJson = Get-SupportBundleJson -ValidationStatus $ValidationStatus -ToolVersions $toolVersions -Evidence $evidence -IncludeContent $false
        $stream = [System.IO.File]::Open($resolvedOutput, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $manifestEntry = $archive.CreateEntry('manifest.json')
            $manifestWriter = [System.IO.StreamWriter]::new($manifestEntry.Open(), [System.Text.UTF8Encoding]::new($false))
            try {
                $manifestWriter.Write($manifestJson)
            } finally {
                $manifestWriter.Dispose()
            }

            foreach ($item in @($evidence)) {
                $entry = $archive.CreateEntry(('evidence/{0}' -f $item.name))
                $writer = [System.IO.StreamWriter]::new($entry.Open(), [System.Text.UTF8Encoding]::new($false))
                try {
                    $writer.Write([string]$item.content)
                } finally {
                    $writer.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
            $stream.Dispose()
        }
    }

    [pscustomobject]@{
        outputPath = $resolvedOutput
        format = $effectiveFormat.ToLowerInvariant()
        evidenceCount = @($evidence).Count
        redactionApplied = $true
        repoRootUsed = $resolvedRoot
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    New-SupportBundle @PSBoundParameters | ConvertTo-Json -Depth 5 -Compress
}
