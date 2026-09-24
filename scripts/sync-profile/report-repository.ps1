# Report sections about repository settings and supply-chain posture: the PowerShell
# runtime, community health, security features, Dependabot policy, Scorecard, review
# policy and required checks. Dot-sourced by scripts/sync-profile.ps1.

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

function Test-PowerShellRuntimeSecurity {
    param(
        [object]$Version = $PSVersionTable.PSVersion,
        [string]$Edition = [string]$PSVersionTable.PSEdition,
        [object]$NativeJsonSchemaAvailable = $null,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )

    $versionValue = ConvertTo-VersionValue -Version $Version
    $nativeJsonSchema = if ($null -ne $NativeJsonSchemaAvailable) { [bool]$NativeJsonSchemaAvailable } else { Test-NativeJsonSchemaAvailable }
    $channel = Get-PowerShellRuntimeChannel -Version $versionValue -Edition $Edition
    $transitionEnd = [datetimeoffset]::Parse("$PowerShellPreviousLtsAcceptedUntil`T23:59:59Z")
    $warnings = New-Object System.Collections.Generic.List[string]

    $isWindowsPowerShell = ($channel -eq "windows-powershell-bootstrap-only")
    $meetsFloor = (-not $isWindowsPowerShell -and $versionValue -ge $PowerShellMinimumGeneratorVersion)
    $withinTransition = ($Now.ToUniversalTime() -le $transitionEnd)

    if ($isWindowsPowerShell) {
        $warnings.Add("Windows PowerShell $WindowsPowerShellBootstrapVersion is allowed only for setup.ps1 bootstrap because $WindowsPowerShellAdvisoryId affects legacy Windows PowerShell command-injection posture.")
    } elseif (-not $meetsFloor) {
        $warnings.Add("PowerShell $versionValue is below the generator floor $PowerShellMinimumGeneratorVersion; install current LTS $PowerShellPreferredLtsVersion or newer.")
    } elseif ($versionValue -lt $PowerShellPreferredLtsVersion) {
        if ($withinTransition) {
            $warnings.Add("PowerShell $versionValue is accepted during the 7.4 transition window through $PowerShellPreviousLtsAcceptedUntil, but local generation should move to current LTS $PowerShellPreferredLtsVersion.")
        } else {
            $warnings.Add("PowerShell $versionValue is below current LTS $PowerShellPreferredLtsVersion and the 7.4 transition window ended on $PowerShellPreviousLtsAcceptedUntil.")
        }
    }

    $securePatch = $null
    if (-not $isWindowsPowerShell) {
        $securePatch = $PowerShellMinimumSecurePatchVersions |
            Where-Object { $_.Major -eq $versionValue.Major -and $_.Minor -eq $versionValue.Minor } |
            Select-Object -First 1
    }
    $meetsSecurePatch = ($null -eq $securePatch) -or ($versionValue -ge $securePatch)
    if (-not $meetsSecurePatch) {
        $warnings.Add("PowerShell $versionValue is affected by $PowerShellSecurityAdvisoryId; update to $securePatch or newer on the $($versionValue.Major).$($versionValue.Minor) line.")
    }

    if ($meetsFloor -and -not $nativeJsonSchema) {
        $warnings.Add("PowerShell $versionValue does not expose Test-Json -SchemaFile; native JSON Schema validation requires PowerShell 7.4 or newer.")
    }

    $supported = [bool]($meetsFloor -and $nativeJsonSchema -and ($versionValue -ge $PowerShellPreferredLtsVersion -or $withinTransition))
    $preferred = [bool]($supported -and $versionValue -ge $PowerShellPreferredLtsVersion)
    $status = if (-not $supported) { "fail" } elseif ($warnings.Count -gt 0) { "warning" } else { "ok" }

    return [ordered]@{
        status = $status
        current = [ordered]@{
            edition = if ([string]::IsNullOrWhiteSpace($Edition)) { "unknown" } else { $Edition }
            version = $versionValue.ToString()
            major = [int]$versionValue.Major
            minor = [int]$versionValue.Minor
            patch = [int]$versionValue.Build
            channel = $channel
            executable = if ($isWindowsPowerShell) { "powershell" } else { "pwsh" }
        }
        policy = [ordered]@{
            generatorMinimumVersion = $PowerShellMinimumGeneratorVersion.ToString()
            preferredLtsVersion = $PowerShellPreferredLtsVersion.ToString()
            previousLtsAcceptedUntil = $PowerShellPreviousLtsAcceptedUntil
            windowsPowerShellBootstrapVersion = $WindowsPowerShellBootstrapVersion
            windowsPowerShellBootstrapOnly = $true
            windowsPowerShellAdvisory = $WindowsPowerShellAdvisoryId
            runtimeSecurityAdvisory = $PowerShellSecurityAdvisoryId
            minimumSecurePatchVersions = @($PowerShellMinimumSecurePatchVersions | ForEach-Object { $_.ToString() })
            meetsMinimumSecurePatch = [bool]$meetsSecurePatch
            sources = @($PowerShellLifecycleUrl, $WindowsPowerShellAdvisoryUrl, $PowerShellSecurityAdvisoryUrl)
        }
        capabilities = [ordered]@{
            nativeJsonSchema = [bool]$nativeJsonSchema
            setupBootstrapOnly = [bool]$isWindowsPowerShell
        }
        supported = $supported
        preferred = $preferred
        warningCount = [int]$warnings.Count
        warnings = @($warnings.ToArray())
    }
}

function Get-CommunityLocalFileStatus {
    $checks = @(
        [ordered]@{ path = "README.md"; required = $true },
        [ordered]@{ path = "LICENSE"; required = $true },
        [ordered]@{ path = "SECURITY.md"; required = $true },
        [ordered]@{ path = ".github/CODEOWNERS"; required = $true },
        [ordered]@{ path = ".github/pull_request_template.md"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/broken-link.yml"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/profile-correction.yml"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/local-validation.yml"; required = $true },
        [ordered]@{ path = ".github/ISSUE_TEMPLATE/config.yml"; required = $true },
        [ordered]@{ path = "CONTRIBUTING.md"; required = $false },
        [ordered]@{ path = "CODE_OF_CONDUCT.md"; required = $false }
    )

    return @($checks | ForEach-Object {
        $path = [string]$_["path"]
        [ordered]@{
            path = $path
            required = [bool]$_["required"]
            exists = [bool](Test-Path -LiteralPath (Join-Path $RepoRoot $path))
        }
    })
}

function Get-CodeScanningLocalEvidence {
    param([string]$WorkflowDirectory = (Join-Path $RepoRoot ".github/workflows"))

    $workflowFiles = @()
    $workflowText = ""
    if (Test-Path -LiteralPath $WorkflowDirectory) {
        $workflowFiles = @(Get-ChildItem -LiteralPath $WorkflowDirectory -Filter "*.yml" -File -ErrorAction SilentlyContinue | Sort-Object Name)
        $workflowText = (($workflowFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")
    }

    $validateLocalPath = Join-Path $RepoRoot "scripts/validate-local.ps1"
    $validateLocalText = if (Test-Path -LiteralPath $validateLocalPath) { Get-Content -LiteralPath $validateLocalPath -Raw } else { "" }
    $packageJsonPath = Join-Path $RepoRoot "package.json"
    $packageJsonText = if (Test-Path -LiteralPath $packageJsonPath) { Get-Content -LiteralPath $packageJsonPath -Raw } else { "" }
    $psScriptAnalyzerSettingsPresent = Test-Path -LiteralPath (Join-Path $RepoRoot "PSScriptAnalyzerSettings.psd1")
    $testsPresent = Test-Path -LiteralPath (Join-Path $RepoRoot "tests")
    $zizmorConfigPresent = Test-Path -LiteralPath (Join-Path $RepoRoot ".github/zizmor.yml")

    $hasCodeQlWorkflow = [regex]::IsMatch($workflowText, '(?i)github/codeql-action/(init|analyze)@|codeql\s+(database|analyze)')
    $hasSarifUpload = [regex]::IsMatch($workflowText, '(?i)github/codeql-action/upload-sarif@')

    return [ordered]@{
        workflowFilesInspected = @($workflowFiles | ForEach-Object { $_.Name })
        codeqlWorkflowPresent = [bool]$hasCodeQlWorkflow
        sarifUploadWorkflowPresent = [bool]$hasSarifUpload
        psScriptAnalyzerWorkflowPresent = [bool][regex]::IsMatch($workflowText, '(?i)Invoke-ScriptAnalyzer|PSScriptAnalyzer')
        actionlintWorkflowPresent = [bool][regex]::IsMatch($workflowText, '(?i)\bactionlint\b')
        zizmorWorkflowPresent = [bool][regex]::IsMatch($workflowText, '(?i)\bzizmor\b')
        localValidationScriptPresent = [bool](Test-Path -LiteralPath $validateLocalPath)
        psScriptAnalyzerLocalPresent = [bool]($psScriptAnalyzerSettingsPresent -and [regex]::IsMatch($validateLocalText, '(?i)\bInvoke-ScriptAnalyzer\b'))
        pesterLocalPresent = [bool]($testsPresent -and [regex]::IsMatch($validateLocalText, '(?i)\bInvoke-Pester\b'))
        markdownlintLocalPresent = [bool]([regex]::IsMatch($packageJsonText, '(?i)markdownlint-cli2') -and [regex]::IsMatch($validateLocalText, '(?i)lint:markdown'))
        zizmorLocalConfigPresent = [bool]$zizmorConfigPresent
    }
}

function Get-LocalAdvisoryReviewPosture {
    <#
    .SYNOPSIS
    Reports the state of the local dependency-advisory lane that stands in for Dependabot.
    .DESCRIPTION
    Repository policy bans Dependabot, so "disabled" is intended rather than a gap, but
    only if the compensating control actually ran. validate-local.ps1 writes this
    artifact on every run; a missing, stale or failing one means there is no advisory
    coverage right now, which is the thing worth warning about.
    #>
    param([string]$ReviewPath = "reports/dependency-review.json")

    $fullPath = if ([System.IO.Path]::IsPathRooted($ReviewPath)) { $ReviewPath } else { Join-Path $RepoRoot $ReviewPath }
    $present = Test-Path -LiteralPath $fullPath
    $status = $null
    $generatedAtText = $null
    $ageDays = $null
    $stale = $false
    $reason = $null
    $signatureStatus = $null
    $signatureSummary = $null

    if (-not $present) {
        $reason = "No local dependency review artifact at $ReviewPath; run npm run review:dependencies (validate-local.ps1 writes it)."
    } else {
        try {
            $review = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
            $status = [string](Get-MemberValue -Object $review -Name "status")
            $generatedAtText = ConvertTo-IsoText (Get-MemberValue -Object $review -Name "generatedAt")
            $signatures = Get-MemberValue -Object (Get-MemberValue -Object $review -Name "npm") -Name "signatures"
            $signatureStatus = [string](Get-MemberValue -Object $signatures -Name "status")
            if (-not [string]::IsNullOrWhiteSpace($signatureStatus)) {
                $signatureSummary = "npm audit signatures: $signatureStatus ($([int](Get-MemberValue -Object $signatures -Name 'verifiedCount')) verified, $([int](Get-MemberValue -Object $signatures -Name 'invalidCount')) invalid, $([int](Get-MemberValue -Object $signatures -Name 'missingCount')) missing)."
            }
        } catch {
            $reason = "Local dependency review artifact at $ReviewPath could not be parsed."
        }
        if ($null -eq $reason) {
            $generatedAt = ConvertTo-DateTimeOffsetOrNull $generatedAtText
            if ($null -eq $generatedAt) {
                $reason = "Local dependency review artifact at $ReviewPath has no usable generatedAt."
            } else {
                $ageDays = [math]::Round(([datetimeoffset]::Now.ToUniversalTime() - $generatedAt.ToUniversalTime()).TotalDays, 2)
                if ($ageDays -gt $LocalAdvisoryReviewStaleDays) {
                    $stale = $true
                    $reason = "Local dependency review is $ageDays days old, past the $LocalAdvisoryReviewStaleDays day window; run npm run review:dependencies."
                } elseif ($status -ne "ok") {
                    # review-local-dependencies.ps1 emits ok / review-needed / not-run.
                    $reason = "Local dependency review reports status '$status'; resolve it before treating advisory coverage as current."
                }
            }
        }
    }

    return [ordered]@{
        present = [bool]$present
        status = if ([string]::IsNullOrWhiteSpace($status)) { $null } else { $status }
        generatedAt = if ([string]::IsNullOrWhiteSpace($generatedAtText)) { $null } else { $generatedAtText }
        ageDays = $ageDays
        stale = [bool]$stale
        staleAfterDays = [int]$LocalAdvisoryReviewStaleDays
        covering = [bool]($null -eq $reason)
        gapReason = $reason
        registrySignatureStatus = if ([string]::IsNullOrWhiteSpace($signatureStatus)) { $null } else { $signatureStatus }
        registrySignatureSummary = if ([string]::IsNullOrWhiteSpace($signatureSummary)) { $null } else { $signatureSummary }
    }
}

function Get-DependabotSecurityPosture {
    param(
        [object]$DependabotSecurityUpdates,
        [string]$UnavailableReason,
        [object]$LocalAdvisoryReview
    )

    $configPath = ".github/dependabot.yml"
    $fullConfigPath = Join-Path $RepoRoot $configPath
    $configPresent = Test-Path -LiteralPath $fullConfigPath
    $ecosystems = @()
    if ($configPresent) {
        $configText = Get-Content -LiteralPath $fullConfigPath -Raw
        $ecosystems = @([regex]::Matches($configText, 'package-ecosystem:\s*"?([^"\r\n]+)"?') | ForEach-Object {
                $_.Groups[1].Value.Trim()
            } | Sort-Object -Unique)
    }

    $statusText = if ($null -eq $DependabotSecurityUpdates) { "" } else { [string]$DependabotSecurityUpdates }
    $available = -not [string]::IsNullOrWhiteSpace($statusText)
    $securityUpdatesEnabled = [bool]($statusText -eq "enabled")
    $status = if (-not $available) {
        "unavailable"
    } elseif ($securityUpdatesEnabled) {
        "enabled"
    } else {
        "disabled"
    }

    # Repository policy bans Dependabot in every form, so "disabled" is the intended state
    # rather than a gap. Advisory coverage comes from the local dependency review lane
    # (npm run review:dependencies), which runs npm audit inside validate-local.ps1 and
    # exits nonzero on advisories, so a disabled setting is not an untriaged risk.
    $recommendation = if ($status -eq "enabled") {
        "disable-dependabot-per-repository-policy"
    } elseif ($status -eq "disabled") {
        "keep-dependabot-disabled-with-local-advisory-review"
    } else {
        "verify-dependabot-security-update-setting"
    }

    $advisoryCovering = [bool](Get-MemberValue -Object $LocalAdvisoryReview -Name "covering")
    $advisoryGapReason = [string](Get-MemberValue -Object $LocalAdvisoryReview -Name "gapReason")
    $advisorySignatureStatus = [string](Get-MemberValue -Object $LocalAdvisoryReview -Name "registrySignatureStatus")
    $advisorySignatureSummary = [string](Get-MemberValue -Object $LocalAdvisoryReview -Name "registrySignatureSummary")

    $evidence = if ($status -eq "disabled" -and $advisoryCovering) {
        "Dependabot security updates are disabled by repository policy; advisory triage runs locally through npm run review:dependencies, which fails validation on open advisories. The local review is current. Local Dependabot version-update config is present for $($ecosystems.Count) ecosystem(s)."
    } elseif ($status -eq "disabled") {
        "Dependabot security updates are disabled by repository policy, but the compensating local advisory review is not currently covering: $advisoryGapReason"
    } elseif ($status -eq "enabled") {
        "Dependabot security updates are enabled, and local version-update config is present for $($ecosystems.Count) ecosystem(s)."
    } elseif (-not [string]::IsNullOrWhiteSpace($UnavailableReason)) {
        "Dependabot security update setting was unavailable from repository metadata and automated-security-fixes endpoint: $UnavailableReason."
    } else {
        "Dependabot security update setting was unavailable from repository metadata and automated-security-fixes endpoint."
    }

    # Never recommend enabling Dependabot or adding its config: AGENTS.md bans both. The
    # only actionable gap is the compensating local lane not being current.
    $nextAction = if ($status -eq "disabled" -and $advisoryCovering) {
        "Keep Dependabot disabled and the local advisory review current."
    } elseif ($status -eq "disabled") {
        "Run npm run review:dependencies so the local advisory lane covers the disabled Dependabot setting."
    } elseif ($status -eq "enabled") {
        "Disable Dependabot security updates to match repository policy; advisory triage belongs to the local review lane."
    } else {
        "Re-query repository security_and_analysis metadata or the automated-security-fixes endpoint before changing Dependabot policy."
    }

    return [ordered]@{
        available = $available
        status = $status
        recommendation = $recommendation
        dependabotSecurityUpdatesStatus = if ($available) { $statusText } else { $null }
        securityUpdatesEnabled = if ($available) { $securityUpdatesEnabled } else { $null }
        localConfigPresent = [bool]$configPresent
        localConfigPath = $configPath
        localConfigEcosystems = @($ecosystems)
        warningDisposition = if ($status -eq "disabled" -and -not $advisoryCovering) { "compensating-control-warning" } elseif ($status -eq "disabled") { "none" } else { "none" }
        localAdvisoryReviewCovering = [bool]$advisoryCovering
        localAdvisoryReviewGapReason = if ([string]::IsNullOrWhiteSpace($advisoryGapReason)) { $null } else { $advisoryGapReason }
        registrySignatureStatus = if ([string]::IsNullOrWhiteSpace($advisorySignatureStatus)) { $null } else { $advisorySignatureStatus }
        registrySignatureSummary = if ([string]::IsNullOrWhiteSpace($advisorySignatureSummary)) { $null } else { $advisorySignatureSummary }
        documentationPath = "decision:dependabot-security-posture"
        evidence = $evidence
        nextAction = $nextAction
    }
}

function Test-SecurityPolicyLinkedReportingTarget {
    $path = Join-Path $RepoRoot "SECURITY.md"
    if (-not (Test-Path -LiteralPath $path)) {
        return $false
    }

    $text = Get-Content -LiteralPath $path -Raw
    return [bool][regex]::IsMatch($text, '(?i)\bhttps?://|mailto:')
}

function Invoke-ScorecardCli {
    <#
    .SYNOPSIS
    Runs the OpenSSF Scorecard CLI against the profile repository and returns its JSON.
    .DESCRIPTION
    Returns ok/value/error. Scorecard reads GitHub's API, so the token comes from gh and is
    passed only in the child's environment; the process starts with no window. A missing
    binary is an error result, not a failure, and the report then says why the score is
    unavailable.
    .PARAMETER TimeoutSeconds
    Wall-clock limit for one Scorecard run.
    #>
    param([ValidateRange(10, 1800)][int]$TimeoutSeconds = 300)

    $scorecard = Get-Command -Name scorecard -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $scorecard) {
        return [ordered]@{ ok = $false; value = $null; error = "scorecard binary not found on PATH; install OpenSSF Scorecard v5 to use -RunScorecard" }
    }
    # Invoke-GhCli merges stderr into its text, so a warning gh prints would ride along
    # with the token; use only a line shaped like a GitHub token.
    $tokenResult = Invoke-GhCli -Arguments @("auth", "token")
    $token = @(([string]$tokenResult.text) -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object {
            # gh's own prefixes, fine-grained tokens, and the 40-hex tokens issued before 2021.
            $_ -cmatch '^(?:gh[oprsu]_[A-Za-z0-9]{20,255}|github_pat_[A-Za-z0-9_]{20,255}|[0-9a-f]{40})\z'
        }) | Select-Object -First 1
    if ($tokenResult.exitCode -ne 0 -or [string]::IsNullOrWhiteSpace([string]$token)) {
        return [ordered]@{ ok = $false; value = $null; error = "gh auth token returned no GitHub token; Scorecard needs one" }
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $scorecard.Source
    [void]$startInfo.ArgumentList.Add("--repo=github.com/$Owner/$Owner")
    [void]$startInfo.ArgumentList.Add("--format=json")
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.Environment["GITHUB_AUTH_TOKEN"] = $token
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $failure = $null
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $process.Kill($true)
            } catch {
                Write-Verbose "Could not stop the timed-out scorecard process: $($_.Exception.Message)"
            }
            return [ordered]@{ ok = $false; value = $null; error = "scorecard timed out after $TimeoutSeconds seconds" }
        }
        $process.WaitForExit()
        if ($process.ExitCode -eq 0) {
            return [ordered]@{ ok = $true; value = ($stdoutTask.Result | ConvertFrom-Json); error = $null }
        }
        # One line: only the reason matters.
        $firstLine = @(([string]$stderrTask.Result) -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        $detail = if ($firstLine.Count -gt 0) { ([string]$firstLine[0]).Trim() } else { "no error output" }
        $failure = "scorecard exited $($process.ExitCode): $detail"
    } catch {
        $failure = "scorecard could not run: $($_.Exception.Message)"
    } finally {
        $process.Dispose()
    }
    # The report is public: take tokens and account names out of whatever the tool said, and
    # only then cap it, so the cut can't leave part of a token behind.
    # Tokens: gh's prefixes wherever they start (after %20 too), and runs of 40 or more hex
    # digits, the shape of the tokens issued before 2021. Only lowercase hex bounds the run:
    # percent-encoding writes uppercase, so %3D or a word like Expired can sit right against one.
    $failure = [regex]::Replace($failure, '(?:gh[oprsu]_|github_pat_)[A-Za-z0-9_]+|(?<![0-9a-f])[0-9a-f]{40,}(?![0-9a-f])', '<token>')
    # Account names, in one pass so a URL is recognised first and comes back whole: any scheme
    # case, with plain, JSON-escaped (\/) or percent-encoded (%2F) slashes and a plain or
    # percent-encoded (%3A) colon.
    # - Windows, after \Users\ with any run of backslashes (Go and JSON double them) or %5C, or
    #   after C:/Users/. The name runs to a character Windows doesn't allow in one, so spaces
    #   and apostrophes stay inside it ("John Smith", "O'Brien") and ": Access is denied."
    #   survives.
    # - macOS and Linux, after /Users/ or /home/ in any case (macOS paths ignore it), wherever
    #   the path sits (/mnt/c/Users, /var/home, //server/Users), and with a slash written as
    #   \/, \\/ or %2F. These names hold no space.
    # Either name keeps its percent-encoded bytes (john%20smith, j%C3%B6rg); an encoded slash,
    # backslash, colon, quote or angle bracket ends it, as the plain one would, so the reason
    # after it survives. After C:%5CUsers the separator may be %2F too. A run of separators is
    # tried only from its first character: from every one of 50 KB of backslashes the match
    # would scan the rest and fail, which took 44 seconds.
    $failure = [regex]::Replace($failure, '(?<url>(?i:https?)(?::|%3[Aa])(?:\\*/|%2[Ff]){2}[^\s"''<>]*)|(?<windows>(?i)(?<!\\|%5C)(?:(?:\\|%5C)+|(?<=\b[A-Za-z]:)/+)(?:Users|home)(?:(?:\\|%5C|%2F)+|/+))(?:[^\\/"<>:|?*\[\];=,+\r\n%]|%(?!5[Cc]|2[Ff]|3[AaCcEeFf]|22|7[Cc]|2[Aa]))+|(?<posix>(?<!\\)(?:\\*/|%2[Ff])(?i:Users|home)(?:\\*/|%2[Ff]))(?:[^\\/\s"''<>:%]|%(?!2[Ff]|5[Cc]|3[AaCcEe]|22))+', {
            param($match)
            if ($match.Groups['url'].Success) {
                $match.Value
            } elseif ($match.Groups['windows'].Success) {
                $match.Groups['windows'].Value + '<user>'
            } else {
                $match.Groups['posix'].Value + '<user>'
            }
        })
    if ($failure.Length -gt 240) { $failure = $failure.Substring(0, 240) }
    return [ordered]@{ ok = $false; value = $null; error = $failure }
}

function Get-ScorecardScoreSnapshot {
    param(
        [object]$ScorecardScoreResult,
        [string]$UnavailableReason
    )

    $command = "scorecard --repo=github.com/$Owner/$Owner --format=json"
    $score = ConvertTo-NullableDouble (Get-MemberValue -Object $ScorecardScoreResult -Name "score")
    $resultRepo = Get-MemberValue -Object $ScorecardScoreResult -Name "repo"
    $missingReason = if ([string]::IsNullOrWhiteSpace($UnavailableReason)) { "scorecard score evidence was not supplied" } else { $UnavailableReason }
    if ($null -eq $ScorecardScoreResult -or $null -eq $score -or -not [string]::IsNullOrWhiteSpace($UnavailableReason)) {
        return [ordered]@{
            available = $false
            score = $null
            maxScore = 10
            provider = "scorecard-cli"
            command = $command
            scorecardVersion = $null
            date = $null
            analyzedRepo = $null
            analyzedCommit = $null
            checks = @()
            unavailableReason = if ($null -eq $ScorecardScoreResult -or -not [string]::IsNullOrWhiteSpace($UnavailableReason)) { $missingReason } else { "scorecard result omitted a numeric score" }
        }
    }

    # Per-check scores, in a stable order. Scorecard scores a check -1 when it cannot decide.
    $checks = @(@(Get-JsonArrayItems (Get-MemberValue -Object $ScorecardScoreResult -Name "checks")) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-MemberValue -Object $_ -Name "name")) } |
        ForEach-Object {
            $reason = [string](Get-MemberValue -Object $_ -Name "reason")
            [ordered]@{
                name = [string](Get-MemberValue -Object $_ -Name "name")
                score = ConvertTo-NullableDouble (Get-MemberValue -Object $_ -Name "score")
                reason = if ([string]::IsNullOrWhiteSpace($reason)) { $null } else { $reason }
            }
        } |
        Sort-Object { ConvertTo-OrdinalSortKey $_.name })
    $version = [string](Get-MemberValue -Object (Get-MemberValue -Object $ScorecardScoreResult -Name "scorecard") -Name "version")

    return [ordered]@{
        available = $true
        score = $score
        maxScore = 10
        provider = "scorecard-cli"
        command = $command
        scorecardVersion = if ([string]::IsNullOrWhiteSpace($version)) { $null } else { $version }
        date = ConvertTo-IsoText (Get-MemberValue -Object $ScorecardScoreResult -Name "date")
        analyzedRepo = [string](Get-MemberValue -Object $resultRepo -Name "name")
        analyzedCommit = [string](Get-MemberValue -Object $resultRepo -Name "commit")
        checks = @($checks)
        unavailableReason = $null
    }
}

function New-ScorecardAlertPostureRow {
    param(
        [object]$Alert,
        [bool]$SecurityPolicyHasLinkedReportingTarget
    )

    $rule = Get-MemberValue -Object $Alert -Name "rule"
    $ruleId = [string](Get-MemberValue -Object $rule -Name "id")
    $description = [string](Get-MemberValue -Object $rule -Name "description")
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = [string](Get-MemberValue -Object $rule -Name "name")
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = $ruleId
    }

    $classification = "needs-review"
    $localDisposition = "review-alert"
    $localEvidence = "Scorecard alert needs local review before classification."
    $nextAction = "Review the Scorecard check details and update this posture row."
    switch ($ruleId) {
        "CodeReviewID" {
            $classification = "external-gated-reviewer-model"
            $localDisposition = "not-fixed-by-local-report"
            $localEvidence = "PR delivery and required checks are proven; pull request review enforcement remains warning-only until an independent reviewer or team model exists."
            $nextAction = "Define an independent reviewer or team model before requiring pull request reviews; keep required-check PR delivery in the meantime."
        }
        "BranchProtectionID" {
            $classification = "external-gated-branch-protection-policy"
            $localDisposition = "policy-gated-scorecard-control"
            $localEvidence = "Required-check readiness and direct-main maintenance policy are tracked separately; enabling branch-protection enforcement is a repository policy decision, not an unclassified local code gap."
            $nextAction = "Keep required-check readiness evidence current and enable enforcement only after the direct-main maintenance policy changes."
        }
        "SecurityPolicyID" {
            if ($SecurityPolicyHasLinkedReportingTarget) {
                $classification = "local-fix-pending-scorecard-refresh"
                $localDisposition = "fixed-locally"
                $localEvidence = "SECURITY.md includes a direct private vulnerability reporting URL."
                $nextAction = "Rerun the local security posture summary and verify the Security-Policy alert closes or score improves."
            } else {
                $classification = "actionable-local-gap"
                $localDisposition = "needs-local-fix"
                $localEvidence = "SECURITY.md is present but lacks a URL or mailto reporting target."
                $nextAction = "Add a public-safe private vulnerability reporting URL or security contact."
            }
        }
        "SASTID" {
            $classification = "covered-by-local-static-analysis"
            $localDisposition = "accepted-scorecard-limitation"
            $localEvidence = "The live language mix is PowerShell-only; CodeQL is not applicable, while local validation covers PSScriptAnalyzer, markdownlint, Pester, and local zizmor configuration review."
            $nextAction = "Reopen the CodeQL posture decision when a CodeQL-supported language appears."
        }
        "CIIBestPracticesID" {
            $classification = "external-program-optional"
            $localDisposition = "manual-governance-choice"
            $localEvidence = "OpenSSF Best Practices badge enrollment is an external manual governance program, not a local repository defect."
            $nextAction = "Enroll in the OpenSSF Best Practices program only if the maintainer wants the external badge workflow."
        }
        "FuzzingID" {
            $classification = "not-applicable-profile-generator"
            $localDisposition = "accepted-scorecard-limitation"
            $localEvidence = "This repository is a deterministic profile README/catalog generator with Pester fixtures rather than a binary parser or network service."
            $nextAction = "Consider property-based generator tests if catalog input handling becomes broader or riskier."
        }
    }

    $tool = Get-MemberValue -Object $Alert -Name "tool"
    return [ordered]@{
        alertNumber = Get-MemberValue -Object $Alert -Name "number"
        ruleId = $ruleId
        checkName = $description
        state = [string](Get-MemberValue -Object $Alert -Name "state")
        severity = [string](Get-MemberValue -Object $rule -Name "severity")
        securitySeverity = [string](Get-MemberValue -Object $rule -Name "security_severity_level")
        classification = $classification
        localDisposition = $localDisposition
        localEvidence = $localEvidence
        nextAction = $nextAction
        htmlUrl = Get-MemberValue -Object $Alert -Name "html_url"
        helpUrl = Get-MemberValue -Object $rule -Name "help_uri"
        toolName = [string](Get-MemberValue -Object $tool -Name "name")
        toolVersion = [string](Get-MemberValue -Object $tool -Name "version")
        createdAt = Get-MemberValue -Object $Alert -Name "created_at"
        updatedAt = Get-MemberValue -Object $Alert -Name "updated_at"
    }
}

function Get-ScorecardAlertPosture {
    param(
        [object[]]$Alerts,
        [string]$UnavailableReason
    )

    $available = ($null -ne $Alerts -and [string]::IsNullOrWhiteSpace($UnavailableReason))
    if (-not $available) {
        return [ordered]@{
            available = $false
            unavailableReason = if ([string]::IsNullOrWhiteSpace($UnavailableReason)) { "scorecard alert evidence was not supplied" } else { $UnavailableReason }
            provider = "github-code-scanning-alerts"
            tool = "Scorecard"
            queriedAt = $script:MetadataSnapshotAt
            openAlertCount = 0
            localActionableCount = 0
            needsHostedRefreshCount = 0
            externalGatedCount = 0
            notApplicableCount = 0
            recommendation = "verify-scorecard-alerts-with-security-api"
            rows = @()
            note = "Scorecard alert posture is informational and does not fail profile sync when the code-scanning alerts API is unavailable."
        }
    }

    $securityPolicyHasLink = Test-SecurityPolicyLinkedReportingTarget
    $rows = @(Get-SortedReportRows -Rows @($Alerts | ForEach-Object {
            New-ScorecardAlertPostureRow -Alert $_ -SecurityPolicyHasLinkedReportingTarget $securityPolicyHasLink
        }) -Keys @("ruleId"))
    $localActionableCount = @($rows | Where-Object { $_.classification -eq "actionable-local-gap" }).Count
    $needsHostedRefreshCount = @($rows | Where-Object { $_.classification -eq "local-fix-pending-scorecard-refresh" }).Count
    $externalGatedCount = @($rows | Where-Object { $_.classification -in @("external-gated-pr-delivery", "external-gated-reviewer-model", "external-gated-branch-protection-policy", "external-program-optional") }).Count
    $notApplicableCount = @($rows | Where-Object { $_.classification -in @("covered-by-local-static-analysis", "not-applicable-profile-generator") }).Count
    $recommendation = if ($localActionableCount -gt 0) {
        "fix-local-scorecard-alerts"
    } elseif ($needsHostedRefreshCount -gt 0) {
        "rerun-scorecard-to-refresh-alerts"
    } elseif ($externalGatedCount -gt 0) {
        "track-external-scorecard-governance-items"
    } else {
        "keep-current-scorecard-controls"
    }

    return [ordered]@{
        available = $true
        unavailableReason = $null
        provider = "github-code-scanning-alerts"
        tool = "Scorecard"
        queriedAt = $script:MetadataSnapshotAt
        openAlertCount = $rows.Count
        localActionableCount = $localActionableCount
        needsHostedRefreshCount = $needsHostedRefreshCount
        externalGatedCount = $externalGatedCount
        notApplicableCount = $notApplicableCount
        recommendation = $recommendation
        rows = @($rows)
        note = "Rows classify open Scorecard SARIF alerts as local fixes, hosted-refresh waits, accepted tool limitations, or external governance items; the posture remains warning-only."
    }
}

function Get-RequiredCheckReadiness {
    param(
        [bool]$BranchProtectionAvailable,
        # Whether the default branch's active rules could be read. They show what every
        # enabled ruleset enforces there, so the ruleset list itself isn't needed.
        [bool]$RulesetsAvailable,
        [Nullable[bool]]$RequiredStatusChecks,
        [Nullable[bool]]$EnforceAdmins,
        [Nullable[bool]]$ActionsPullRequestCreationAllowed,
        [int]$RulesetCount,
        # Whether an active ruleset puts a required_status_checks rule on the default branch.
        # The ruleset count alone can't say: it includes tag rulesets and disabled ones.
        [Nullable[bool]]$RulesetRequiresStatusChecks,
        [string]$BranchProtectionUnavailableReason,
        [string]$RulesetsUnavailableReason
    )

    $workflowCoverage = Test-RequiredCheckWorkflowCoverage
    if ((Get-MemberValue -Object $workflowCoverage -Name "status") -eq "not-applicable") {
        $prDeliveryTransition = Get-PrDeliveryTransitionChecklist `
            -WorkflowCoverage $workflowCoverage `
            -RequiredChecksEnabled $false `
            -EnforceAdmins $EnforceAdmins `
            -ActionsPullRequestCreationAllowed $ActionsPullRequestCreationAllowed `
            -BranchProtectionAvailable $BranchProtectionAvailable `
            -RulesetsAvailable $RulesetsAvailable

        return [ordered]@{
            status = "not-applicable"
            recommendation = "local-validation-only"
            readyForEnforcement = $false
            branchProtectionRequiredStatusChecks = Get-NullableBool $RequiredStatusChecks
            rulesetCount = [int]$RulesetCount
            enforceAdmins = Get-NullableBool $EnforceAdmins
            candidateCheckCount = 0
            candidateChecks = @()
            workflowCoverage = $workflowCoverage
            prDeliveryTransition = $prDeliveryTransition
            blockerCount = 0
            blockers = @()
        }
    }

    $requiredChecksEnabled = ($RequiredStatusChecks -eq $true -or $RulesetRequiresStatusChecks -eq $true)
    # Either source showing enforcement settles it. "Not enabled" needs both readable and
    # silent; with one unreadable and the other silent the answer is unknown, and says so.
    $enforcementKnown = $requiredChecksEnabled -or ($BranchProtectionAvailable -and $RulesetsAvailable)
    # Blockers stand between the repository and enforcement, so they only apply until one
    # mechanism enforces the checks; after that the checklist's delivery item tracks the drill.
    $blockers = New-Object System.Collections.Generic.List[string]
    if (-not $requiredChecksEnabled) {
        if (-not $BranchProtectionAvailable) {
            $blockers.Add("Branch protection evidence unavailable$(if (-not [string]::IsNullOrWhiteSpace($BranchProtectionUnavailableReason)) { ": $BranchProtectionUnavailableReason" }).")
        } else {
            $blockers.Add("Branch protection does not require status checks.")
        }

        if (-not $RulesetsAvailable) {
            $blockers.Add("Repository ruleset evidence unavailable$(if (-not [string]::IsNullOrWhiteSpace($RulesetsUnavailableReason)) { ": $RulesetsUnavailableReason" }).")
        } else {
            $blockers.Add("No active repository ruleset requires status checks on the default branch.")
        }

        if ($EnforceAdmins -eq $true) {
            $blockers.Add("Protected main enforces admins; a pull-request delivery path needs a live merge drill before required checks are enabled.")
        }
    }

    $prDeliveryTransition = Get-PrDeliveryTransitionChecklist `
        -WorkflowCoverage $workflowCoverage `
        -RequiredChecksEnabled $requiredChecksEnabled `
        -EnforceAdmins $EnforceAdmins `
        -ActionsPullRequestCreationAllowed $ActionsPullRequestCreationAllowed `
        -BranchProtectionAvailable $BranchProtectionAvailable `
        -RulesetsAvailable $RulesetsAvailable

    $status = if ($requiredChecksEnabled) {
        "enforcement-present"
    } elseif ($enforcementKnown) {
        "not-enabled"
    } else {
        "needs-live-validation"
    }

    $recommendation = if ($requiredChecksEnabled -and $blockers.Count -eq 0) {
        "monitor-required-check-enforcement"
    } else {
        "defer-until-pr-delivery-or-bypass"
    }

    return [ordered]@{
        status = $status
        recommendation = $recommendation
        # Ready means nothing blocks enforcement and every delivery item is proven, the same
        # answer prDeliveryTransition.readyForRequiredCheckEnforcement gives. Enforcement
        # already being on doesn't prove the check-run evidence or the merge drill.
        readyForEnforcement = [bool]($blockers.Count -eq 0 -and (Get-MemberValue -Object $prDeliveryTransition -Name 'readyForRequiredCheckEnforcement') -eq $true)
        branchProtectionRequiredStatusChecks = Get-NullableBool $RequiredStatusChecks
        rulesetCount = [int]$RulesetCount
        enforceAdmins = Get-NullableBool $EnforceAdmins
        candidateCheckCount = @($RequiredStatusCheckCandidates).Count
        candidateChecks = @($RequiredStatusCheckCandidates)
        workflowCoverage = $workflowCoverage
        prDeliveryTransition = $prDeliveryTransition
        blockerCount = $blockers.Count
        blockers = $blockers.ToArray()
    }
}

function New-PrDeliveryChecklistItem {
    param(
        [string]$Id,
        [ValidateSet("ready", "blocked", "needs-live-validation")]
        [string]$Status,
        [string]$Summary,
        [string]$Evidence,
        [string]$NextAction
    )

    return [ordered]@{
        id = $Id
        status = $Status
        summary = $Summary
        evidence = $Evidence
        nextAction = $NextAction
    }
}

function Get-GeneratedPrDryRunEvidence {
    return $null
}

function Get-GeneratedPrWriteEvidence {
    return $null
}

function Get-GeneratedPrCredentialDecision {
    param(
        [Nullable[bool]]$ActionsPullRequestCreationAllowed,
        # Candidate required-check workflows exist; without them no generated PR runs.
        [bool]$WorkflowsPresent
    )

    $settingAllowsGeneratedPr = Get-NullableBool $ActionsPullRequestCreationAllowed
    if (-not $WorkflowsPresent) {
        return [ordered]@{
            status = "not-applicable"
            selectedPath = "manual-local-validation"
            rejectedPath = "hosted-generated-pr-delivery"
            rationale = "No candidate workflows exist, so generated PR helpers stay offline previews and need no repository Actions PR creation setting."
            requiresRepositorySetting = $false
            requiresNewSecret = $false
            currentSettingAllowsGeneratedPr = $settingAllowsGeneratedPr
            decisionDocumentPath = "decision:local-validation-only"
            activationCommand = ""
            nextAction = "Use scripts/validate-local.ps1 and scripts/render-profile-smoke.ps1 before committing generated artifacts locally."
        }
    }
    if ($settingAllowsGeneratedPr -eq $true) {
        return [ordered]@{
            status = "setting-enabled"
            selectedPath = "enable-actions-pr-creation"
            rejectedPath = "approved-github-app-or-pat-token"
            rationale = "Candidate workflows exist and the repository lets GitHub Actions create pull requests, so a generated PR can use GITHUB_TOKEN without a new secret."
            requiresRepositorySetting = $true
            requiresNewSecret = $false
            currentSettingAllowsGeneratedPr = $settingAllowsGeneratedPr
            decisionDocumentPath = "setting:actions-can-create-pull-requests"
            activationCommand = ""
            nextAction = "Run a routine maintenance PR merge drill with a generated pull request."
        }
    }
    $settingText = if ($null -eq $settingAllowsGeneratedPr) { "whether GitHub Actions may create pull requests couldn't be read" } else { "GitHub Actions may not create pull requests" }
    # Neither path is chosen yet, so neither is recorded as selected or rejected.
    return [ordered]@{
        status = "needs-decision"
        selectedPath = "undecided"
        rejectedPath = "undecided"
        rationale = "Candidate workflows exist, but $settingText, so generated pull requests need that setting or a dedicated credential; until then maintenance PRs are opened by hand."
        requiresRepositorySetting = $true
        requiresNewSecret = $false
        currentSettingAllowsGeneratedPr = $settingAllowsGeneratedPr
        decisionDocumentPath = "decision:pending"
        activationCommand = ""
        nextAction = "Allow GitHub Actions to create pull requests, or record a decision to use a GitHub App or token."
    }
}

function Test-RequiredCheckWorkflowCoverage {
    param(
        [object[]]$Candidates = $RequiredStatusCheckCandidates
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $workflowRows = New-Object System.Collections.Generic.List[object]
    $workflowPaths = @($Candidates | ForEach-Object { [string](Get-MemberValue -Object $_ -Name "workflow") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

    if (@($Candidates).Count -eq 0 -or $workflowPaths.Count -eq 0) {
        return [ordered]@{
            status = "not-applicable"
            workflowCount = 0
            candidateCheckCount = 0
            warningCount = 0
            warnings = @()
            workflows = @()
        }
    }

    foreach ($workflowPath in $workflowPaths) {
        $candidateNames = @($Candidates | Where-Object {
                [string](Get-MemberValue -Object $_ -Name "workflow") -eq $workflowPath
            } | ForEach-Object {
                [string](Get-MemberValue -Object $_ -Name "name")
            })
        $literalPath = Join-Path $RepoRoot $workflowPath
        $exists = Test-Path -LiteralPath $literalPath
        $text = if ($exists) { Get-Content -LiteralPath $literalPath -Raw } else { "" }
        $hasPullRequest = [bool][regex]::IsMatch($text, '(?m)^  pull_request:\s*$')
        $hasMergeGroup = [bool][regex]::IsMatch($text, '(?m)^  merge_group:\s*$')
        $pullRequestPathFiltered = [bool][regex]::IsMatch($text, '(?ms)^  pull_request:\s*\r?\n\s+paths:')
        $missingCandidateNames = @($candidateNames | Where-Object {
                -not [regex]::IsMatch($text, "(?m)^\s+name:\s*$([regex]::Escape($_))\s*$")
            })

        if (-not $exists) {
            $warnings.Add("Candidate required-check workflow is missing: $workflowPath.")
        }
        if ($exists -and -not $hasPullRequest) {
            $warnings.Add("Candidate required-check workflow lacks pull_request trigger: $workflowPath.")
        }
        if ($exists -and -not $hasMergeGroup) {
            $warnings.Add("Candidate required-check workflow lacks merge_group trigger: $workflowPath.")
        }
        if ($exists -and $pullRequestPathFiltered) {
            $warnings.Add("Candidate required-check workflow path-filters pull_request runs: $workflowPath.")
        }
        foreach ($candidateName in $missingCandidateNames) {
            $warnings.Add("Candidate required-check job name '$candidateName' was not found in $workflowPath.")
        }

        $workflowRows.Add([ordered]@{
                workflow = $workflowPath
                candidateChecks = @($candidateNames)
                exists = [bool]$exists
                pullRequestTrigger = $hasPullRequest
                mergeGroupTrigger = $hasMergeGroup
                pullRequestPathFiltered = $pullRequestPathFiltered
                missingCandidateCheckNames = @($missingCandidateNames)
            })
    }

    return [ordered]@{
        status = if ($warnings.Count -eq 0) { "ready" } else { "blocked" }
        workflowCount = $workflowRows.Count
        candidateCheckCount = @($Candidates).Count
        warningCount = $warnings.Count
        warnings = $warnings.ToArray()
        workflows = @($workflowRows.ToArray())
    }
}

function Get-CandidateCheckExercisePlan {
    return $null
}

function Get-CandidateCheckExerciseEvidence {
    return $null
}

function Get-PrDeliveryTransitionChecklist {
    param(
        [object]$WorkflowCoverage,
        [bool]$RequiredChecksEnabled,
        [Nullable[bool]]$EnforceAdmins,
        [Nullable[bool]]$ActionsPullRequestCreationAllowed,
        [bool]$BranchProtectionAvailable,
        [bool]$RulesetsAvailable
    )

    if ((Get-MemberValue -Object $WorkflowCoverage -Name "status") -eq "not-applicable") {
        return [ordered]@{
            status = "not-applicable"
            readyForRequiredCheckEnforcement = $false
            checklistCount = 0
            readyCount = 0
            blockedCount = 0
            needsLiveValidationCount = 0
            generatedPrDryRunEvidence = $null
            generatedPrWriteEvidence = $null
            directMainMaintenancePolicy = $null
            candidateCheckExercisePlan = $null
            candidateCheckExerciseEvidence = $null
            routineMaintenancePrDrillEvidence = $null
            requiredCheckEnforcementEvidence = $null
            items = @()
        }
    }

    $items = New-Object System.Collections.Generic.List[object]
    $candidateCount = @($RequiredStatusCheckCandidates).Count
    $candidateStatus = if ($candidateCount -gt 0) { "ready" } else { "blocked" }
    $items.Add((New-PrDeliveryChecklistItem `
                -Id "candidate-checks-defined" `
                -Status $candidateStatus `
                -Summary "Candidate required-check names are defined and must stay stable." `
                -Evidence "$candidateCount candidate check(s) are configured." `
                -NextAction "Keep required-check job names unique and unchanged before enabling enforcement."))

    $workflowStatus = if ((Get-MemberValue -Object $WorkflowCoverage -Name "status") -eq "ready") { "ready" } else { "blocked" }
    $items.Add((New-PrDeliveryChecklistItem `
                -Id "candidate-workflow-coverage" `
                -Status $workflowStatus `
                -Summary "Candidate workflows must create checks for pull requests and merge queue runs." `
                -Evidence "$((Get-MemberValue -Object $WorkflowCoverage -Name "workflowCount")) workflow file(s), $((Get-MemberValue -Object $WorkflowCoverage -Name "warningCount")) warning(s)." `
                -NextAction "Fix missing pull_request or merge_group triggers before making any check required."))

    $items.Add((New-PrDeliveryChecklistItem `
                -Id "recent-check-run-proof" `
                -Status "needs-live-validation" `
                -Summary "Each required check must have a current proof path before enforcement." `
                -Evidence "No recent check-run proof for the candidate checks is recorded yet." `
                -NextAction "Define a new local or hosted proof path before making any check required."))

    # This checklist only exists when candidate workflows do, so its text describes the
    # settings it was given and never the local-only posture.
    $drillTiming = if ($RequiredChecksEnabled) { "while the checks are required" } else { "before enabling required checks" }
    $deliveryStatus = if ($ActionsPullRequestCreationAllowed -eq $false) {
        "blocked"
    } else {
        "needs-live-validation"
    }
    $deliveryEvidence = if ($ActionsPullRequestCreationAllowed -eq $false) {
        "Repository settings don't let GitHub Actions create pull requests, so no generated PR delivery path exists."
    } elseif ($null -eq $ActionsPullRequestCreationAllowed) {
        "Whether GitHub Actions may create pull requests couldn't be read."
    } elseif ($EnforceAdmins -eq $true) {
        "GitHub Actions may create pull requests and main enforces admins, but no PR has been shown to merge through that path."
    } else {
        "GitHub Actions may create pull requests, but no PR has been shown to merge through that path and no bypass is documented."
    }
    $deliveryNextAction = if ($ActionsPullRequestCreationAllowed -eq $false) {
        "Allow Actions to create pull requests or open maintenance PRs by hand, then run a routine maintenance PR merge drill $drillTiming."
    } elseif ($null -eq $ActionsPullRequestCreationAllowed) {
        "Read the repository's Actions workflow permissions, then run a routine maintenance PR merge drill $drillTiming."
    } elseif ($EnforceAdmins -eq $true) {
        "Run a routine maintenance PR merge drill $drillTiming, since admins can't push past them."
    } else {
        "Run a routine maintenance PR merge drill, or document a bypass, $drillTiming."
    }
    $items.Add((New-PrDeliveryChecklistItem `
                -Id "pr-delivery-or-bypass" `
                -Status $deliveryStatus `
                -Summary "Direct-main delivery must be replaced by PR delivery or a documented bypass before enforcement." `
                -Evidence $deliveryEvidence `
                -NextAction $deliveryNextAction))

    # Absent only when both sources were read; one unreadable source leaves it unknown.
    $enforcementStatus = if ($RequiredChecksEnabled) { "ready" } elseif ($BranchProtectionAvailable -and $RulesetsAvailable) { "blocked" } else { "needs-live-validation" }
    $enforcementEvidence = if ($RequiredChecksEnabled) {
        "Required-check enforcement is already present."
    } elseif ($BranchProtectionAvailable -and $RulesetsAvailable) {
        "Branch protection and the default branch's rules are readable and show no required-check enforcement."
    } elseif ($BranchProtectionAvailable) {
        "Branch protection requires no status checks, but the default branch's rules couldn't be read, so a ruleset may still require them."
    } elseif ($RulesetsAvailable) {
        "No rule on the default branch requires status checks, but branch protection couldn't be read, so it may still require them."
    } else {
        "Live branch-protection and ruleset state must be validated before selecting an enforcement mechanism."
    }
    $enforcementNextAction = if ($RequiredChecksEnabled) {
        "Keep monitoring required checks on routine pull requests and re-query branch protection after any check-name changes."
    } else {
        "After PR delivery is proven, enable one enforcement mechanism and re-query branch protection/rulesets."
    }
    $items.Add((New-PrDeliveryChecklistItem `
                -Id "enforcement-mechanism" `
                -Status $enforcementStatus `
                -Summary "Choose branch protection or a repository ruleset only after PR delivery is ready." `
                -Evidence $enforcementEvidence `
                -NextAction $enforcementNextAction))

    $blockedCount = @($items | Where-Object { (Get-MemberValue -Object $_ -Name "status") -eq "blocked" }).Count
    $needsLiveValidationCount = @($items | Where-Object { (Get-MemberValue -Object $_ -Name "status") -eq "needs-live-validation" }).Count
    $readyCount = @($items | Where-Object { (Get-MemberValue -Object $_ -Name "status") -eq "ready" }).Count
    $status = if ($blockedCount -gt 0) {
        "blocked"
    } elseif ($needsLiveValidationCount -gt 0) {
        "needs-live-validation"
    } else {
        "ready"
    }

    return [ordered]@{
        status = $status
        readyForRequiredCheckEnforcement = [bool]($status -eq "ready")
        checklistCount = $items.Count
        readyCount = $readyCount
        blockedCount = $blockedCount
        needsLiveValidationCount = $needsLiveValidationCount
        generatedPrDryRunEvidence = Get-GeneratedPrDryRunEvidence
        generatedPrWriteEvidence = Get-GeneratedPrWriteEvidence
        # These three were fixed records of this repository's 2026 PR drills (#14, #16) and
        # reported "passed" on every run, for any owner, long after the workflows they
        # describe were deleted. Nothing reads them live, so they stay null.
        directMainMaintenancePolicy = $null
        candidateCheckExercisePlan = Get-CandidateCheckExercisePlan
        candidateCheckExerciseEvidence = Get-CandidateCheckExerciseEvidence
        routineMaintenancePrDrillEvidence = $null
        requiredCheckEnforcementEvidence = $null
        items = @($items.ToArray())
    }
}

function Get-ReviewPolicyPosture {
    param(
        [bool]$BranchProtectionAvailable,
        [object]$RequiredPullRequestReviews,
        [object]$RequiredCodeOwnerReviews,
        [object]$RequiredStatusChecks,
        [object]$RequiredCheckReadiness,
        [object[]]$LocalFiles = @(),
        [string]$BranchProtectionUnavailableReason
    )

    if (-not $BranchProtectionAvailable) {
        return [ordered]@{
            available = $false
            status = "unavailable"
            recommendation = "verify-branch-protection-review-policy"
            branchProtectionUnavailableReason = if ([string]::IsNullOrWhiteSpace($BranchProtectionUnavailableReason)) { "branch protection evidence was not supplied" } else { $BranchProtectionUnavailableReason }
            pullRequestReviewsRequired = $null
            codeOwnerReviewsRequired = $null
            requiredStatusChecksEnabled = $null
            codeownersFilePresent = [bool](@($LocalFiles | Where-Object { [string](Get-MemberValue -Object $_ -Name "path") -eq ".github/CODEOWNERS" -and (Get-MemberValue -Object $_ -Name "exists") -eq $true }).Count -gt 0)
            routinePrDeliveryProven = $false
            requiredCheckEnforcementProven = $false
            directMainBypassApproved = $false
            reviewerModel = "unverified"
            scorecardCodeReviewClassification = "needs-review"
            documentationPath = "decision:review-policy-posture"
            evidence = "Branch-protection review settings were unavailable."
            nextAction = "Re-query branch protection before changing pull request review or code-owner review requirements."
        }
    }

    $pullRequestReviewsRequired = [bool]($RequiredPullRequestReviews -eq $true)
    $codeOwnerReviewsRequired = [bool]($RequiredCodeOwnerReviews -eq $true)
    $requiredStatusChecksEnabled = [bool]($RequiredStatusChecks -eq $true)
    $transition = Get-MemberValue -Object $RequiredCheckReadiness -Name "prDeliveryTransition"
    $routinePrDeliveryProven = [string](Get-NestedMemberValue -Object $transition -Path "routineMaintenancePrDrillEvidence.status") -eq "passed"
    $requiredCheckEnforcementProven = [string](Get-NestedMemberValue -Object $transition -Path "requiredCheckEnforcementEvidence.status") -eq "passed"
    $directMainBypassApproved = [bool](Get-NestedMemberValue -Object $transition -Path "directMainMaintenancePolicy.allowed")
    $codeownersFilePresent = [bool](@($LocalFiles | Where-Object { [string](Get-MemberValue -Object $_ -Name "path") -eq ".github/CODEOWNERS" -and (Get-MemberValue -Object $_ -Name "exists") -eq $true }).Count -gt 0)

    $status = if ($pullRequestReviewsRequired -and $codeOwnerReviewsRequired) {
        "enforced-pr-and-code-owner-review"
    } elseif ($pullRequestReviewsRequired) {
        "enforced-pr-review"
    } else {
        "warning-only-single-maintainer"
    }

    $recommendation = if ($status -eq "enforced-pr-and-code-owner-review") {
        "monitor-review-enforcement"
    } elseif ($status -eq "enforced-pr-review") {
        "decide-code-owner-review-requirement"
    } else {
        "keep-warning-only-until-reviewer-model"
    }

    $evidence = if ($status -eq "warning-only-single-maintainer") {
        # Derived from live branch-protection state. This previously hard-coded a hosted
        # PR-delivery proof, which contradicted the report once the workflows were removed.
        $statusCheckText = if ($requiredStatusChecksEnabled) {
            "Branch protection requires status checks"
        } else {
            "Branch protection does not require status checks"
        }
        "$statusCheckText, and it does not require pull request or code-owner reviews. CODEOWNERS is present for routing; review enforcement should wait for an independent reviewer or team model."
    } elseif ($status -eq "enforced-pr-review") {
        "Branch protection requires pull request reviews but does not require code-owner reviews."
    } else {
        "Branch protection requires pull request reviews and code-owner reviews."
    }

    $nextAction = if ($status -eq "warning-only-single-maintainer") {
        "Define an independent reviewer or team model before requiring pull request reviews or code-owner reviews."
    } elseif ($status -eq "enforced-pr-review") {
        "Decide whether CODEOWNERS review should also be required after validating reviewer availability."
    } else {
        "Monitor review enforcement and update CODEOWNERS before adding new public-contract paths."
    }

    return [ordered]@{
        available = $true
        status = $status
        recommendation = $recommendation
        branchProtectionUnavailableReason = $null
        pullRequestReviewsRequired = $pullRequestReviewsRequired
        codeOwnerReviewsRequired = $codeOwnerReviewsRequired
        requiredStatusChecksEnabled = $requiredStatusChecksEnabled
        codeownersFilePresent = $codeownersFilePresent
        routinePrDeliveryProven = $routinePrDeliveryProven
        requiredCheckEnforcementProven = $requiredCheckEnforcementProven
        directMainBypassApproved = $directMainBypassApproved
        reviewerModel = "single-maintainer-profile-repo"
        scorecardCodeReviewClassification = "external-gated-reviewer-model"
        documentationPath = "decision:review-policy-posture"
        evidence = $evidence
        nextAction = $nextAction
    }
}

function Test-RepositoryCommunityBaseline {
    param(
        [object]$Repository,
        [object]$CommunityProfile,
        [object]$BranchProtection,
        # Left out, a list reads as unread, not as read and empty: an empty list is an answer.
        [object[]]$Rulesets = $null,
        # Active rules on the default branch (GET .../rules/branches/<default branch>), from
        # every enabled ruleset; the ruleset list alone can't say whether any requires checks.
        [object[]]$BranchRules = $null,
        [object]$ActionsWorkflowPermissions,
        [object]$Languages,
        [object[]]$LocalFiles = @(),
        [object]$CodeScanningLocalEvidence,
        [object[]]$ScorecardAlerts,
        [object]$ScorecardScoreResult,
        [string]$DependabotSecurityUpdatesStatus,
        [object]$ImmutableReleases,
        [string]$DependabotSecurityUpdatesUnavailableReason,
        [string]$RepositoryUnavailableReason,
        [string]$CommunityUnavailableReason,
        [string]$BranchProtectionUnavailableReason,
        [string]$RulesetsUnavailableReason,
        [string]$BranchRulesUnavailableReason,
        [string]$ActionsWorkflowPermissionsUnavailableReason,
        [string]$LanguagesUnavailableReason,
        [string]$ScorecardAlertsUnavailableReason,
        [string]$ScorecardScoreUnavailableReason
    )

    # Immutable releases went GA on 2025-10-28 and are available on personal repositories.
    # The setting lives on its own endpoint rather than the repository object, and it only
    # applies to releases published after it is enabled, so existing releases stay mutable.
    $immutableReleasesEnabled = Get-NullableBool (Get-MemberValue -Object $ImmutableReleases -Name "enabled")
    $immutableReleasesPosture = [ordered]@{
        status = if ($null -eq $immutableReleasesEnabled) {
            "unavailable"
        } elseif ($immutableReleasesEnabled) {
            "enabled"
        } else {
            "disabled"
        }
        enabled = $immutableReleasesEnabled
        enforcedByOwner = Get-NullableBool (Get-MemberValue -Object $ImmutableReleases -Name "enforced_by_owner")
        appliesTo = "releases published after the setting was enabled"
        recommendation = if ($immutableReleasesEnabled -eq $true) {
            "keep-immutable-releases-enabled"
        } elseif ($null -eq $immutableReleasesEnabled) {
            "re-query-immutable-release-setting"
        } else {
            "enable-immutable-releases"
        }
    }

    $repoWarnings = New-Object System.Collections.Generic.List[string]
    $communityWarnings = New-Object System.Collections.Generic.List[string]
    $communityErrors = New-Object System.Collections.Generic.List[string]
    $communityInfo = New-Object System.Collections.Generic.List[string]

    $repoAvailable = ($null -ne $Repository -and [string]::IsNullOrWhiteSpace($RepositoryUnavailableReason))
    $communityAvailable = ($null -ne $CommunityProfile -and [string]::IsNullOrWhiteSpace($CommunityUnavailableReason))
    $branchProtectionAvailable = ($null -ne $BranchProtection -and [string]::IsNullOrWhiteSpace($BranchProtectionUnavailableReason))
    $rulesetsAvailable = ($null -ne $Rulesets -and [string]::IsNullOrWhiteSpace($RulesetsUnavailableReason))
    $branchRulesAvailable = ($null -ne $BranchRules -and [string]::IsNullOrWhiteSpace($BranchRulesUnavailableReason))
    $rulesetRequiresStatusChecks = if ($branchRulesAvailable) {
        [bool](@($BranchRules | Where-Object { [string](Get-MemberValue -Object $_ -Name 'type') -eq 'required_status_checks' }).Count -gt 0)
    } else {
        $null
    }
    $actionsWorkflowPermissionsAvailable = ($null -ne $ActionsWorkflowPermissions -and [string]::IsNullOrWhiteSpace($ActionsWorkflowPermissionsUnavailableReason))
    $languagesAvailable = ($null -ne $Languages -and [string]::IsNullOrWhiteSpace($LanguagesUnavailableReason))
    if ($null -eq $CodeScanningLocalEvidence) {
        $CodeScanningLocalEvidence = Get-CodeScanningLocalEvidence
    }
    $scorecardAlertPosture = Get-ScorecardAlertPosture -Alerts $ScorecardAlerts -UnavailableReason $ScorecardAlertsUnavailableReason
    $scorecardScore = Get-ScorecardScoreSnapshot -ScorecardScoreResult $ScorecardScoreResult -UnavailableReason $ScorecardScoreUnavailableReason

    if (-not $repoAvailable -and -not [string]::IsNullOrWhiteSpace($RepositoryUnavailableReason)) {
        $repoWarnings.Add("Repository settings unavailable: $RepositoryUnavailableReason.")
    }
    if (-not $communityAvailable -and -not [string]::IsNullOrWhiteSpace($CommunityUnavailableReason)) {
        $communityWarnings.Add("GitHub community profile unavailable: $CommunityUnavailableReason.")
    }
    if (-not $actionsWorkflowPermissionsAvailable -and -not [string]::IsNullOrWhiteSpace($ActionsWorkflowPermissionsUnavailableReason)) {
        $repoWarnings.Add("GitHub Actions workflow permissions unavailable: $ActionsWorkflowPermissionsUnavailableReason.")
    }
    if (-not [bool](Get-MemberValue -Object $scorecardAlertPosture -Name "available")) {
        $repoWarnings.Add("Scorecard code-scanning alerts unavailable: $((Get-MemberValue -Object $scorecardAlertPosture -Name "unavailableReason")).")
    }

    $secretScanning = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.secret_scanning.status"
    $secretScanningPushProtection = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.secret_scanning_push_protection.status"
    $secretScanningNonProviderPatterns = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.secret_scanning_non_provider_patterns.status"
    $secretScanningValidityChecks = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.secret_scanning_validity_checks.status"
    $repositoryDependabotSecurityUpdates = Get-NestedMemberValue -Object $Repository -Path "security_and_analysis.dependabot_security_updates.status"
    $dependabotSecurityUpdates = if (-not [string]::IsNullOrWhiteSpace([string]$repositoryDependabotSecurityUpdates)) {
        $repositoryDependabotSecurityUpdates
    } else {
        $DependabotSecurityUpdatesStatus
    }
    $localAdvisoryReview = Get-LocalAdvisoryReviewPosture
    $dependabotSecurityPosture = Get-DependabotSecurityPosture `
        -DependabotSecurityUpdates $dependabotSecurityUpdates `
        -UnavailableReason $DependabotSecurityUpdatesUnavailableReason `
        -LocalAdvisoryReview $localAdvisoryReview

    if ($repoAvailable) {
        if ([string]::IsNullOrWhiteSpace([string]$secretScanning)) {
            $repoWarnings.Add("Secret scanning status is unavailable.")
        } elseif ($secretScanning -ne "enabled") {
            $repoWarnings.Add("Secret scanning is not enabled.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$secretScanningPushProtection)) {
            $repoWarnings.Add("Secret scanning push protection status is unavailable.")
        } elseif ($secretScanningPushProtection -ne "enabled") {
            $repoWarnings.Add("Secret scanning push protection is not enabled.")
        }
        # Dependabot disabled is the policy, so the warning is about the compensating
        # local advisory lane, not about the setting.
        if ((Get-MemberValue -Object $dependabotSecurityPosture -Name "status") -eq "disabled") {
            if (-not (Get-MemberValue -Object $dependabotSecurityPosture -Name "localAdvisoryReviewCovering")) {
                $repoWarnings.Add("Dependabot is disabled by policy and the compensating local advisory review is not current: $(Get-MemberValue -Object $dependabotSecurityPosture -Name 'localAdvisoryReviewGapReason')")
            }
        } elseif ((Get-MemberValue -Object $dependabotSecurityPosture -Name "status") -eq "unavailable") {
            $repoWarnings.Add("Dependabot security update status is unavailable.")
        }
    }

    $requiredStatusChecks = $null
    $requiredPullRequestReviews = $null
    $requiredCodeOwnerReviews = $null
    $requiredConversationResolution = $null
    $enforceAdmins = $null
    $allowForcePushes = $null
    $allowDeletions = $null
    if ($branchProtectionAvailable) {
        $requiredStatusChecks = $null -ne (Get-MemberValue -Object $BranchProtection -Name "required_status_checks")
        $pullRequestReviewObject = Get-MemberValue -Object $BranchProtection -Name "required_pull_request_reviews"
        $requiredPullRequestReviews = $null -ne $pullRequestReviewObject
        $requiredCodeOwnerReviews = if ($pullRequestReviewObject) { [bool](Get-MemberValue -Object $pullRequestReviewObject -Name "require_code_owner_reviews") } else { $false }
        $requiredConversationResolution = [bool](Get-NestedMemberValue -Object $BranchProtection -Path "required_conversation_resolution.enabled")
        $enforceAdmins = [bool](Get-NestedMemberValue -Object $BranchProtection -Path "enforce_admins.enabled")
        $allowForcePushes = [bool](Get-NestedMemberValue -Object $BranchProtection -Path "allow_force_pushes.enabled")
        $allowDeletions = [bool](Get-NestedMemberValue -Object $BranchProtection -Path "allow_deletions.enabled")

        if (-not $requiredStatusChecks) {
            $repoWarnings.Add("Branch protection does not require status checks.")
        }
        if (-not $requiredPullRequestReviews) {
            $repoWarnings.Add("Branch protection does not require pull request reviews.")
        }
        if (-not $requiredCodeOwnerReviews) {
            $repoWarnings.Add("Branch protection does not require code owner reviews.")
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($BranchProtectionUnavailableReason)) {
        $repoWarnings.Add("Branch protection unavailable: $BranchProtectionUnavailableReason.")
    }

    $rulesetCount = if ($rulesetsAvailable) { @($Rulesets).Count } else { 0 }
    if ($rulesetsAvailable -and $rulesetCount -eq 0) {
        $repoWarnings.Add("No repository rulesets are configured.")
    } elseif (-not [string]::IsNullOrWhiteSpace($RulesetsUnavailableReason)) {
        $repoWarnings.Add("Repository rulesets unavailable: $RulesetsUnavailableReason.")
    }
    # The default branch's rules decide ruleset enforcement, so not reading them leaves it unknown.
    if (-not $branchRulesAvailable) {
        $repoWarnings.Add("Default branch rules unavailable$(if (-not [string]::IsNullOrWhiteSpace($BranchRulesUnavailableReason)) { ": $BranchRulesUnavailableReason" }), so a ruleset's required checks can't be seen.")
    }

    $defaultWorkflowPermissions = $null
    $canApprovePullRequestReviews = $null
    $generatedPrCreationAllowed = $null
    if ($actionsWorkflowPermissionsAvailable) {
        $defaultWorkflowPermissions = [string](Get-MemberValue -Object $ActionsWorkflowPermissions -Name "default_workflow_permissions")
        $canApprovePullRequestReviews = Get-NullableBool (Get-MemberValue -Object $ActionsWorkflowPermissions -Name "can_approve_pull_request_reviews")
        $generatedPrCreationAllowed = [bool]($canApprovePullRequestReviews -eq $true)
        if (-not $generatedPrCreationAllowed -and @($RequiredStatusCheckCandidates).Count -gt 0) {
            $repoWarnings.Add("GitHub Actions workflow permissions do not allow GITHUB_TOKEN to create pull requests.")
        }
    }
    $generatedPrCredentialDecision = Get-GeneratedPrCredentialDecision -ActionsPullRequestCreationAllowed $generatedPrCreationAllowed -WorkflowsPresent (@($RequiredStatusCheckCandidates).Count -gt 0)

    # Ruleset enforcement comes from the branch's active rules alone; the list only counts.
    $requiredCheckReadiness = Get-RequiredCheckReadiness `
        -BranchProtectionAvailable $branchProtectionAvailable `
        -RulesetsAvailable $branchRulesAvailable `
        -RequiredStatusChecks $requiredStatusChecks `
        -EnforceAdmins $enforceAdmins `
        -ActionsPullRequestCreationAllowed $generatedPrCreationAllowed `
        -RulesetCount $rulesetCount `
        -RulesetRequiresStatusChecks $rulesetRequiresStatusChecks `
        -BranchProtectionUnavailableReason $BranchProtectionUnavailableReason `
        -RulesetsUnavailableReason $BranchRulesUnavailableReason

    $reviewPolicyPosture = Get-ReviewPolicyPosture `
        -BranchProtectionAvailable $branchProtectionAvailable `
        -RequiredPullRequestReviews $requiredPullRequestReviews `
        -RequiredCodeOwnerReviews $requiredCodeOwnerReviews `
        -RequiredStatusChecks $requiredStatusChecks `
        -RequiredCheckReadiness $requiredCheckReadiness `
        -LocalFiles $LocalFiles `
        -BranchProtectionUnavailableReason $BranchProtectionUnavailableReason

    $languageNames = @()
    if ($languagesAvailable) {
        # ForEach-Object, not .Name: a repository with no detected languages answers {}, and
        # under strict mode member access on the empty property list throws.
        $languageNames = @($Languages.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
    }
    $detectedCodeQlSupportedLanguages = @($languageNames | Where-Object { $CodeQlSupportedLanguages -contains $_ } | Sort-Object)
    $hasCodeqlSupportedLanguage = $detectedCodeQlSupportedLanguages.Count -gt 0
    $powerShellOnly = ($languageNames.Count -eq 1 -and $languageNames[0] -eq "PowerShell")
    $codeQlWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "codeqlWorkflowPresent")
    $sarifUploadWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "sarifUploadWorkflowPresent")
    $psScriptAnalyzerWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "psScriptAnalyzerWorkflowPresent")
    $actionlintWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "actionlintWorkflowPresent")
    $zizmorWorkflowPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "zizmorWorkflowPresent")
    $localValidationScriptPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "localValidationScriptPresent")
    $psScriptAnalyzerLocalPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "psScriptAnalyzerLocalPresent")
    $pesterLocalPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "pesterLocalPresent")
    $markdownlintLocalPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "markdownlintLocalPresent")
    $zizmorLocalConfigPresent = [bool](Get-MemberValue -Object $CodeScanningLocalEvidence -Name "zizmorLocalConfigPresent")
    $codeScanningStatus = if ($languagesAvailable -and -not $hasCodeqlSupportedLanguage) {
        "not-applicable"
    } elseif ($languagesAvailable) {
        "needs-live-validation"
    } else {
        "unavailable"
    }
    $codeScanningRecommendation = if ($codeScanningStatus -eq "not-applicable") {
        if ($powerShellOnly) {
            "not-applicable-powershell-only"
        } else {
            "no-codeql-supported-languages-detected"
        }
    } elseif ($codeScanningStatus -eq "needs-live-validation") {
        "verify-code-scanning-for-supported-languages"
    } else {
        $LanguagesUnavailableReason
    }
    $codeScanningReason = if ($codeScanningStatus -eq "not-applicable") {
        "Detected repository languages do not include a current CodeQL-supported source language."
    } elseif ($codeScanningStatus -eq "needs-live-validation") {
        "Detected repository languages include CodeQL-supported source language(s)."
    } else {
        $LanguagesUnavailableReason
    }
    $localCodeScanningControls = New-Object System.Collections.Generic.List[string]
    if ($localValidationScriptPresent) { $localCodeScanningControls.Add("local-validation-bootstrap") }
    if ($psScriptAnalyzerLocalPresent) { $localCodeScanningControls.Add("psscriptanalyzer") }
    if ($pesterLocalPresent) { $localCodeScanningControls.Add("pester") }
    if ($markdownlintLocalPresent) { $localCodeScanningControls.Add("markdownlint") }
    if ($zizmorLocalConfigPresent) { $localCodeScanningControls.Add("zizmor-config") }

    $hostedCodeScanningControls = New-Object System.Collections.Generic.List[string]
    if ($secretScanning -eq "enabled") { $hostedCodeScanningControls.Add("secret-scanning") }
    if ($secretScanningPushProtection -eq "enabled") { $hostedCodeScanningControls.Add("secret-scanning-push-protection") }
    if ($dependabotSecurityUpdates -eq "enabled") { $hostedCodeScanningControls.Add("dependabot-security-updates") }
    if ($psScriptAnalyzerWorkflowPresent) { $hostedCodeScanningControls.Add("psscriptanalyzer-workflow") }
    if ($actionlintWorkflowPresent) { $hostedCodeScanningControls.Add("actionlint-workflow") }
    if ($zizmorWorkflowPresent) { $hostedCodeScanningControls.Add("zizmor-workflow") }
    if ($sarifUploadWorkflowPresent) { $hostedCodeScanningControls.Add("sarif-upload-workflow") }
    if ($codeQlWorkflowPresent) { $hostedCodeScanningControls.Add("codeql-workflow") }

    $activeCodeScanningControls = @(@(
        @($localCodeScanningControls.ToArray())
        @($hostedCodeScanningControls.ToArray())
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    if ($languagesAvailable -and $hasCodeqlSupportedLanguage -and -not $codeQlWorkflowPresent) {
        $repoWarnings.Add("CodeQL-supported languages detected; verify code scanning default setup, add an intentional CodeQL workflow, or document another SARIF-producing analyzer.")
    }

    foreach ($file in @($LocalFiles)) {
        if ((Get-MemberValue -Object $file -Name "required") -eq $true -and (Get-MemberValue -Object $file -Name "exists") -ne $true) {
            $communityErrors.Add("Required community file is missing: $((Get-MemberValue -Object $file -Name "path")).")
        }
    }

    $communityFiles = Get-MemberValue -Object $CommunityProfile -Name "files"
    $communityReadme = $null -ne (Get-MemberValue -Object $communityFiles -Name "readme")
    $communityLicense = $null -ne (Get-MemberValue -Object $communityFiles -Name "license")
    $communityIssueTemplate = $null -ne (Get-MemberValue -Object $communityFiles -Name "issue_template")
    $communityPullRequestTemplate = $null -ne (Get-MemberValue -Object $communityFiles -Name "pull_request_template")
    $communityContributing = $null -ne (Get-MemberValue -Object $communityFiles -Name "contributing")
    $communityCodeOfConduct = $null -ne (Get-MemberValue -Object $communityFiles -Name "code_of_conduct")

    $localIssueForms = @($LocalFiles | Where-Object {
        ([string](Get-MemberValue -Object $_ -Name "path")).StartsWith(".github/ISSUE_TEMPLATE/", [StringComparison]::OrdinalIgnoreCase) -and
            (Get-MemberValue -Object $_ -Name "exists") -eq $true
    }).Count
    # The community-profile API only detects legacy issue *templates*, not issue
    # *forms* (.github/ISSUE_TEMPLATE/*.yml). When the provider reports no issue
    # template but local issue forms exist, treat it as a provider gap (info), not
    # a warning; genuinely missing local intake stays a warning/fatal elsewhere.
    $issueTemplateProviderState = if (-not $communityAvailable) {
        "unavailable"
    } elseif ($communityIssueTemplate) {
        "detected"
    } elseif ($localIssueForms -gt 0) {
        "provider-gap-local-forms-present"
    } else {
        "missing"
    }
    if ($communityAvailable) {
        if ($issueTemplateProviderState -eq "provider-gap-local-forms-present") {
            $communityInfo.Add("GitHub community profile does not detect issue-template metadata, but $localIssueForms local issue form(s) are present; the provider does not surface issue forms (.github/ISSUE_TEMPLATE/*.yml).")
        } elseif ($issueTemplateProviderState -eq "missing") {
            $communityWarnings.Add("No issue templates or local issue forms detected; public reporters have no structured intake.")
        }
        if (-not $communityContributing) {
            $communityWarnings.Add("GitHub community profile does not report contributing guidelines.")
        }
        if (-not $communityCodeOfConduct) {
            $communityWarnings.Add("GitHub community profile does not report a code of conduct.")
        }
    }

    $repositorySettings = [ordered]@{
        available = [bool]$repoAvailable
        unavailableReason = if ($repoAvailable) { $null } else { $RepositoryUnavailableReason }
        repository = "$Owner/$Owner"
        visibility = if ($repoAvailable) { [string](Get-MemberValue -Object $Repository -Name "visibility") } else { $null }
        features = [ordered]@{
            hasIssues = Get-NullableBool (Get-MemberValue -Object $Repository -Name "has_issues")
            hasDiscussions = Get-NullableBool (Get-MemberValue -Object $Repository -Name "has_discussions")
            hasProjects = Get-NullableBool (Get-MemberValue -Object $Repository -Name "has_projects")
            hasWiki = Get-NullableBool (Get-MemberValue -Object $Repository -Name "has_wiki")
            allowForking = Get-NullableBool (Get-MemberValue -Object $Repository -Name "allow_forking")
            deleteBranchOnMerge = Get-NullableBool (Get-MemberValue -Object $Repository -Name "delete_branch_on_merge")
            webCommitSignoffRequired = Get-NullableBool (Get-MemberValue -Object $Repository -Name "web_commit_signoff_required")
        }
        security = [ordered]@{
            secretScanning = $secretScanning
            secretScanningPushProtection = $secretScanningPushProtection
            secretScanningNonProviderPatterns = $secretScanningNonProviderPatterns
            secretScanningValidityChecks = $secretScanningValidityChecks
            dependabotSecurityUpdates = $dependabotSecurityUpdates
            dependabotSecurityPosture = $dependabotSecurityPosture
            immutableReleases = $immutableReleasesPosture
            scorecardScore = $scorecardScore
            codeScanning = [ordered]@{
                status = $codeScanningStatus
                recommendation = $codeScanningRecommendation
                reason = $codeScanningReason
                languagesInspected = @($languageNames)
                codeqlSupportedLanguages = @($detectedCodeQlSupportedLanguages)
                codeqlSupportedLanguageDetected = [bool]$hasCodeqlSupportedLanguage
                codeqlWorkflowPresent = $codeQlWorkflowPresent
                sarifUploadWorkflowPresent = $sarifUploadWorkflowPresent
                localControls = @($localCodeScanningControls.ToArray())
                hostedControls = @($hostedCodeScanningControls.ToArray())
                activeControls = @($activeCodeScanningControls)
                scorecardAlertPosture = $scorecardAlertPosture
            }
        }
        branchProtection = [ordered]@{
            available = [bool]$branchProtectionAvailable
            unavailableReason = if ($branchProtectionAvailable) { $null } else { $BranchProtectionUnavailableReason }
            requiredStatusChecks = Get-NullableBool $requiredStatusChecks
            requiredPullRequestReviews = Get-NullableBool $requiredPullRequestReviews
            requiredCodeOwnerReviews = Get-NullableBool $requiredCodeOwnerReviews
            requiredConversationResolution = Get-NullableBool $requiredConversationResolution
            enforceAdmins = Get-NullableBool $enforceAdmins
            allowForcePushes = Get-NullableBool $allowForcePushes
            allowDeletions = Get-NullableBool $allowDeletions
        }
        rulesets = [ordered]@{
            available = [bool]$rulesetsAvailable
            unavailableReason = if ($rulesetsAvailable) { $null } else { $RulesetsUnavailableReason }
            count = [int]$rulesetCount
            # True only when an active ruleset puts required status checks on the default branch.
            requiresStatusChecks = $rulesetRequiresStatusChecks
            branchRulesUnavailableReason = if ($branchRulesAvailable) { $null } else { $BranchRulesUnavailableReason }
        }
        actionsWorkflowPermissions = [ordered]@{
            available = [bool]$actionsWorkflowPermissionsAvailable
            unavailableReason = if ($actionsWorkflowPermissionsAvailable) { $null } else { $ActionsWorkflowPermissionsUnavailableReason }
            defaultWorkflowPermissions = if ($actionsWorkflowPermissionsAvailable) { $defaultWorkflowPermissions } else { $null }
            canApprovePullRequestReviews = $canApprovePullRequestReviews
            generatedPrCreationAllowed = if ($actionsWorkflowPermissionsAvailable) { $generatedPrCreationAllowed } else { $null }
            recommendation = if (@($RequiredStatusCheckCandidates).Count -eq 0) {
                "local-validation-only"
            } elseif (-not $actionsWorkflowPermissionsAvailable) {
                "verify-actions-workflow-permissions"
            } elseif ($generatedPrCreationAllowed) {
                "ready-for-generated-pr-delivery"
            } else {
                "enable-actions-pr-creation-or-use-approved-automation-token"
            }
            generatedPrCredentialDecision = $generatedPrCredentialDecision
        }
        requiredCheckReadiness = $requiredCheckReadiness
        reviewPolicyPosture = $reviewPolicyPosture
        warningCount = $repoWarnings.Count
        warnings = $repoWarnings.ToArray()
    }

    $communityHealth = [ordered]@{
        available = [bool]$communityAvailable
        unavailableReason = if ($communityAvailable) { $null } else { $CommunityUnavailableReason }
        healthPercentage = if ($communityAvailable) { [int](Get-MemberValue -Object $CommunityProfile -Name "health_percentage") } else { $null }
        providerFiles = [ordered]@{
            readme = Get-NullableBool $communityReadme
            license = Get-NullableBool $communityLicense
            issueTemplate = Get-NullableBool $communityIssueTemplate
            pullRequestTemplate = Get-NullableBool $communityPullRequestTemplate
            contributing = Get-NullableBool $communityContributing
            codeOfConduct = Get-NullableBool $communityCodeOfConduct
        }
        localFiles = @($LocalFiles)
        localIssueFormCount = [int]$localIssueForms
        issueTemplateProviderState = $issueTemplateProviderState
        localRequiredMissingCount = $communityErrors.Count
        warningCount = $communityWarnings.Count
        warnings = $communityWarnings.ToArray()
        infoCount = $communityInfo.Count
        info = $communityInfo.ToArray()
        fatalCount = $communityErrors.Count
        errors = $communityErrors.ToArray()
    }

    return [ordered]@{
        repositorySettings = $repositorySettings
        communityHealth = $communityHealth
    }
}

function Get-RepositoryCommunityBaseline {
    $localFiles = @(Get-CommunityLocalFileStatus)
    if ($script:Offline) {
        return Test-RepositoryCommunityBaseline `
            -LocalFiles $localFiles `
            -RepositoryUnavailableReason "offline" `
            -CommunityUnavailableReason "offline" `
            -BranchProtectionUnavailableReason "offline" `
            -RulesetsUnavailableReason "offline" `
            -BranchRulesUnavailableReason "offline" `
            -ActionsWorkflowPermissionsUnavailableReason "offline" `
            -LanguagesUnavailableReason "offline" `
            -ScorecardAlertsUnavailableReason "offline" `
            -ScorecardScoreUnavailableReason "offline"
    }
    if (-not (Test-GitHubCliAuthenticated)) {
        return Test-RepositoryCommunityBaseline `
            -LocalFiles $localFiles `
            -RepositoryUnavailableReason "gh authentication unavailable" `
            -CommunityUnavailableReason "gh authentication unavailable" `
            -BranchProtectionUnavailableReason "gh authentication unavailable" `
            -RulesetsUnavailableReason "gh authentication unavailable" `
            -BranchRulesUnavailableReason "gh authentication unavailable" `
            -ActionsWorkflowPermissionsUnavailableReason "gh authentication unavailable" `
            -LanguagesUnavailableReason "gh authentication unavailable" `
            -ScorecardAlertsUnavailableReason "gh authentication unavailable" `
            -ScorecardScoreUnavailableReason "gh authentication unavailable"
    }

    $repositoryResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner"
    # Protection and rules belong to the default branch, which isn't always main. Any name git
    # allows goes into the path escaped, main+dev and dev@2 included. An unreadable repository
    # answer, or a name no branch can have (blank, holding a space or control character, or
    # a bare . or .. that would be a path step even escaped), falls back to main.
    $defaultBranch = if ($repositoryResult["ok"]) { [string](Get-MemberValue -Object $repositoryResult["value"] -Name "default_branch") } else { "" }
    if ([string]::IsNullOrEmpty($defaultBranch) -or $defaultBranch -match '[\s\p{Cc}]' -or @('.', '..').Contains($defaultBranch)) { $defaultBranch = "main" }
    $branchSegment = [uri]::EscapeDataString($defaultBranch)
    $communityResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/community/profile"
    $branchProtectionResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/branches/$branchSegment/protection"
    $rulesetsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/rulesets" -Paginate
    $branchRulesResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/rules/branches/$branchSegment" -Paginate
    $actionsWorkflowPermissionsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/actions/permissions/workflow"
    $languagesResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/languages"
    $scorecardAlertsResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/code-scanning/alerts?tool_name=Scorecard&state=open&per_page=100" -Paginate
    # Scorecard runs locally when asked. The hosted API only held scans from a workflow this
    # repository no longer has, so the score it returned was months out of date.
    $scorecardScoreResult = if ($script:RunScorecard) {
        Invoke-ScorecardCli
    } else {
        [ordered]@{ ok = $false; value = $null; error = "Scorecard was not run; pass -RunScorecard with the OpenSSF Scorecard v5 binary on PATH" }
    }
    $dependabotSecurityUpdatesResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/automated-security-fixes"
    $immutableReleasesResult = Invoke-GhApiJsonSafe -Path "repos/$Owner/$Owner/immutable-releases"

    $repositoryValue = if ($repositoryResult["ok"]) { $repositoryResult["value"] } else { $null }
    $communityValue = if ($communityResult["ok"]) { $communityResult["value"] } else { $null }
    # "Branch not protected" is GitHub saying there's no classic protection: read, and
    # requiring nothing. Any other failure leaves protection unread.
    # Ordinal: that lower-case text is only ever Get-PublicSafeGhError's reading of a 404,
    # while gh's own first line, which it passes on otherwise, is capitalized, and -ceq would
    # still match one with an invisible character in it.
    $branchNotProtected = (-not $branchProtectionResult["ok"]) -and 'branch not protected'.Equals($branchProtectionResult["error"])
    $branchProtectionValue = if ($branchProtectionResult["ok"]) { $branchProtectionResult["value"] } elseif ($branchNotProtected) { [pscustomobject]@{} } else { $null }
    # Assigned inside the branch: an if statement sends an array's items down the pipeline,
    # so "if (...) { @() }" hands $null to the assignment and an empty list read as missing.
    $rulesetsValue = @()
    if ($rulesetsResult["ok"]) { $rulesetsValue = @(Get-JsonArrayItems $rulesetsResult["value"]) }
    $branchRulesValue = @()
    if ($branchRulesResult["ok"]) { $branchRulesValue = @(Get-JsonArrayItems $branchRulesResult["value"]) }
    $actionsWorkflowPermissionsValue = if ($actionsWorkflowPermissionsResult["ok"]) { $actionsWorkflowPermissionsResult["value"] } else { $null }
    $languagesValue = if ($languagesResult["ok"]) { $languagesResult["value"] } else { $null }
    $scorecardAlertsValue = $null
    if ($scorecardAlertsResult["ok"]) { $scorecardAlertsValue = @(Get-JsonArrayItems $scorecardAlertsResult["value"]) }
    $scorecardScoreValue = if ($scorecardScoreResult["ok"]) { $scorecardScoreResult["value"] } else { $null }
    $dependabotSecurityUpdatesValue = if ($dependabotSecurityUpdatesResult["ok"]) {
        $automatedFixesEnabled = Get-MemberValue -Object $dependabotSecurityUpdatesResult["value"] -Name "enabled"
        if ($null -eq $automatedFixesEnabled) {
            $null
        } elseif ([bool]$automatedFixesEnabled) {
            "enabled"
        } else {
            "disabled"
        }
    } else {
        $null
    }

    $immutableReleasesValue = if ($immutableReleasesResult["ok"]) { $immutableReleasesResult["value"] } else { $null }

    return Test-RepositoryCommunityBaseline `
        -Repository $repositoryValue `
        -CommunityProfile $communityValue `
        -BranchProtection $branchProtectionValue `
        -Rulesets $rulesetsValue `
        -BranchRules $branchRulesValue `
        -ActionsWorkflowPermissions $actionsWorkflowPermissionsValue `
        -Languages $languagesValue `
        -LocalFiles $localFiles `
        -ScorecardAlerts $scorecardAlertsValue `
        -ScorecardScoreResult $scorecardScoreValue `
        -DependabotSecurityUpdatesStatus $dependabotSecurityUpdatesValue `
        -ImmutableReleases $immutableReleasesValue `
        -DependabotSecurityUpdatesUnavailableReason $(if ($dependabotSecurityUpdatesResult["ok"]) { $null } else { $dependabotSecurityUpdatesResult["error"] }) `
        -RepositoryUnavailableReason $(if ($repositoryResult["ok"]) { $null } else { $repositoryResult["error"] }) `
        -CommunityUnavailableReason $(if ($communityResult["ok"]) { $null } else { $communityResult["error"] }) `
        -BranchProtectionUnavailableReason $(if ($branchProtectionResult["ok"] -or $branchNotProtected) { $null } else { $branchProtectionResult["error"] }) `
        -RulesetsUnavailableReason $(if ($rulesetsResult["ok"]) { $null } else { $rulesetsResult["error"] }) `
        -BranchRulesUnavailableReason $(if ($branchRulesResult["ok"]) { $null } else { $branchRulesResult["error"] }) `
        -ActionsWorkflowPermissionsUnavailableReason $(if ($actionsWorkflowPermissionsResult["ok"]) { $null } else { $actionsWorkflowPermissionsResult["error"] }) `
        -LanguagesUnavailableReason $(if ($languagesResult["ok"]) { $null } else { $languagesResult["error"] }) `
        -ScorecardAlertsUnavailableReason $(if ($scorecardAlertsResult["ok"]) { $null } else { $scorecardAlertsResult["error"] }) `
        -ScorecardScoreUnavailableReason $(if ($scorecardScoreResult["ok"]) { $null } else { $scorecardScoreResult["error"] })
}
