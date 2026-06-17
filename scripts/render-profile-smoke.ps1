#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Url = "https://github.com/SysAdminDoc",
    [string]$OutputDir = "reports",
    [int]$Port = 9224,
    [int]$TimeoutSec = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "sync-profile.ps1")

function Find-ChromeExecutable {
    $commands = @("google-chrome", "google-chrome-stable", "chromium", "chromium-browser")
    foreach ($command in $commands) {
        $found = Get-Command $command -ErrorAction SilentlyContinue
        if ($found) {
            return $found.Source
        }
    }

    $paths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )

    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    throw "Chrome, Edge, or Chromium was not found."
}

function Wait-ForDevTools {
    param(
        [int]$Port,
        [int]$TimeoutSec,
        [System.Diagnostics.Process]$Process
    )

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
    $lastError = $null
    do {
        if ($Process -and $Process.HasExited) {
            throw "Chrome exited before DevTools became ready on port $Port. Exit code: $($Process.ExitCode)."
        }
        try {
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2
        } catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Milliseconds 250
        }
    } while ([datetime]::UtcNow -lt $deadline)

    throw "Chrome DevTools endpoint did not become ready on port $Port within $TimeoutSec seconds. Last error: $lastError"
}

function Send-CdpCommand {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [int]$Id,
        [string]$Method,
        [hashtable]$Params = @{}
    )

    $payload = [ordered]@{
        id = $Id
        method = $Method
        params = $Params
    } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $Socket.SendAsync(
        [ArraySegment[byte]]::new($bytes),
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None
    ).GetAwaiter().GetResult() | Out-Null

    $buffer = New-Object byte[] 1048576
    $cdpDeadline = [datetime]::UtcNow.AddSeconds(60)
    while ([datetime]::UtcNow -lt $cdpDeadline) {
        $stream = [System.IO.MemoryStream]::new()
        try {
            do {
                $cts = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(30))
                try {
                    $segment = [ArraySegment[byte]]::new($buffer)
                    $result = $Socket.ReceiveAsync($segment, $cts.Token).GetAwaiter().GetResult()
                } finally {
                    $cts.Dispose()
                }
                if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    throw "Chrome DevTools socket closed while waiting for $Method."
                }
                $stream.Write($buffer, 0, $result.Count)
            } while (-not $result.EndOfMessage)

            $message = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
        } finally {
            $stream.Dispose()
        }
        $response = $message | ConvertFrom-Json
        if (($response.PSObject.Properties.Name -contains "id") -and $response.id -eq $Id) {
            if ($response.PSObject.Properties.Name -contains "error") {
                throw "CDP $Method failed: $($response.error | ConvertTo-Json -Compress)"
            }
            return $response.result
        }
    }
    throw "CDP $Method timed out waiting for response id $Id."
}

function Invoke-RenderedSmoke {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [ref]$CommandId,
        [string]$Url,
        [string]$Name,
        [int]$Width,
        [int]$Height,
        [string]$ScreenshotPath
    )

    $CommandId.Value++
    Send-CdpCommand -Socket $Socket -Id $CommandId.Value -Method "Page.enable" | Out-Null
    $CommandId.Value++
    Send-CdpCommand -Socket $Socket -Id $CommandId.Value -Method "Runtime.enable" | Out-Null
    $CommandId.Value++
    Send-CdpCommand -Socket $Socket -Id $CommandId.Value -Method "Emulation.setDeviceMetricsOverride" -Params @{
        width = $Width
        height = $Height
        deviceScaleFactor = 1
        mobile = ($Width -lt 600)
    } | Out-Null
    $CommandId.Value++
    Send-CdpCommand -Socket $Socket -Id $CommandId.Value -Method "Page.navigate" -Params @{ url = $Url } | Out-Null
    $loadDeadline = [datetime]::UtcNow.AddSeconds(30)
    while ([datetime]::UtcNow -lt $loadDeadline) {
        Start-Sleep -Milliseconds 500
        $CommandId.Value++
        $readyState = Send-CdpCommand -Socket $Socket -Id $CommandId.Value -Method "Runtime.evaluate" -Params @{
            expression = 'document.readyState'
            returnByValue = $true
        }
        if ($readyState.result.value -eq 'complete') { break }
    }
    if ([datetime]::UtcNow -ge $loadDeadline) {
        Write-Warning "Page load did not reach readyState 'complete' within 30 seconds at ${Width}x${Height}; proceeding on a partially loaded page."
    }
    Start-Sleep -Seconds 2

    $expression = @'
(() => {
  const text = document.body.innerText || "";
  const article = document.querySelector("article.markdown-body") || document.querySelector(".markdown-body");
  const root = article || document.body;
  const sections = ["Featured Projects", "First-time setup", "PowerShell System Utilities", "Python Desktop Applications", "Browser Extensions & Userscripts"];
  const sectionResults = Object.fromEntries(sections.map((name) => [name, text.includes(name)]));
  const rootOverflow = root.scrollWidth > root.clientWidth + 2;
  const documentOverflow = document.documentElement.scrollWidth > window.innerWidth + 2;
  const images = Array.from(root.querySelectorAll("img")).map((img) => ({
    src: img.currentSrc || img.src,
    alt: img.alt || "",
    complete: img.complete,
    naturalWidth: img.naturalWidth || 0
  }));
  return {
    title: document.title,
    url: location.href,
    viewportWidth: window.innerWidth,
    documentScrollWidth: document.documentElement.scrollWidth,
    rootClientWidth: root.clientWidth,
    rootScrollWidth: root.scrollWidth,
    rootOverflow,
    documentOverflow,
    portfolioLinkText: text.includes("View my full portfolio"),
    sections: sectionResults,
    failedImages: images.filter((img) => !img.complete || img.naturalWidth === 0).slice(0, 10)
  };
})()
'@

    $CommandId.Value++
    $evaluation = Send-CdpCommand -Socket $Socket -Id $CommandId.Value -Method "Runtime.evaluate" -Params @{
        expression = $expression
        returnByValue = $true
    }
    $result = $evaluation.result.value

    $CommandId.Value++
    $screenshot = Send-CdpCommand -Socket $Socket -Id $CommandId.Value -Method "Page.captureScreenshot" -Params @{
        format = "png"
        captureBeyondViewport = $false
    }
    [System.IO.File]::WriteAllBytes($ScreenshotPath, [Convert]::FromBase64String($screenshot.data))

    $missingSections = @($result.sections.PSObject.Properties | Where-Object { -not [bool]$_.Value } | ForEach-Object { $_.Name })
    $failedImages = @($result.failedImages)
    $passed = ($missingSections.Count -eq 0) -and
        [bool]$result.portfolioLinkText -and
        (-not [bool]$result.rootOverflow) -and
        (-not [bool]$result.documentOverflow) -and
        ($failedImages.Count -eq 0)

    return [ordered]@{
        name = $Name
        width = $Width
        height = $Height
        passed = $passed
        screenshot = $ScreenshotPath
        title = $result.title
        finalUrl = $result.url
        portfolioLinkText = [bool]$result.portfolioLinkText
        missingSections = $missingSections
        rootOverflow = [bool]$result.rootOverflow
        documentOverflow = [bool]$result.documentOverflow
        rootClientWidth = [int]$result.rootClientWidth
        rootScrollWidth = [int]$result.rootScrollWidth
        documentScrollWidth = [int]$result.documentScrollWidth
        failedImages = $failedImages
    }
}

$currentDirectory = (Get-Location).ProviderPath
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $currentDirectory $OutputDir }
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

function Write-RenderedSmokeArtifact {
    param([object]$Report)

    $reportPath = Join-Path $resolvedOutputDir "rendered-profile-smoke.json"
    $Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding utf8
    $syncReportPath = Join-Path $currentDirectory "reports/profile-sync-report.json"
    if (Test-Path -LiteralPath $syncReportPath) {
        try {
            $syncReport = Get-Content -LiteralPath $syncReportPath -Raw | ConvertFrom-Json -AsHashtable
            $syncReport["renderedProfileSmoke"] = New-RenderedProfileSmokeSummary -SmokeReport $Report
            for ($budgetPass = 0; $budgetPass -lt 2; $budgetPass++) {
                $draftSyncReportJson = $syncReport | ConvertTo-Json -Depth 30
                foreach ($row in @($syncReport["artifactBudgets"]["rows"])) {
                    if ($row["artifact"] -eq "reports/profile-sync-report.json" -and $row["metric"] -eq "bytes") {
                        $value = [System.Text.Encoding]::UTF8.GetByteCount($draftSyncReportJson + [Environment]::NewLine)
                        $row["value"] = [int]$value
                        $row["overSoftLimit"] = [bool]($value -gt [int]$row["softLimit"])
                        $row["warning"] = if ($row["overSoftLimit"]) {
                            "reports/profile-sync-report.json bytes is $value, above the $($row["softLimit"]) soft limit."
                        } else {
                            $null
                        }
                    }
                }
            }
            $syncReport | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $syncReportPath -Encoding utf8
            Write-Host "Updated profile sync report renderedProfileSmoke summary: $syncReportPath"
        } catch {
            Write-Warning "Could not update profile sync report renderedProfileSmoke summary: $($_.Exception.Message)"
        }
    }

    return $reportPath
}

$chrome = $null
try {
    $chrome = Find-ChromeExecutable
} catch {
    $skipReason = $_.Exception.Message
    $skipReport = [ordered]@{
        generatedAt = [datetimeoffset]::Now.ToString("o")
        url = $Url
        chrome = $null
        passed = $false
        skipped = $true
        skipReason = $skipReason
        viewports = @()
    }
    $reportPath = Write-RenderedSmokeArtifact -Report $skipReport
    Write-Error "Rendered profile smoke could not run. See $reportPath. Reason: $skipReason"
}

$results = $null
$lastLaunchError = $null
for ($attempt = 1; $attempt -le 2 -and $null -eq $results; $attempt++) {
    $attemptPort = $Port + $attempt - 1
    $profileDir = Join-Path ([System.IO.Path]::GetTempPath()) ("SysAdminDoc-render-smoke-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    $stdoutPath = Join-Path $resolvedOutputDir "rendered-profile-smoke-chrome-$attempt.out.log"
    $stderrPath = Join-Path $resolvedOutputDir "rendered-profile-smoke-chrome-$attempt.err.log"

    $chromeArgs = @(
        "--headless=new",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--disable-background-networking",
        "--disable-extensions",
        "--hide-scrollbars",
        "--no-default-browser-check",
        "--no-first-run",
        "--no-sandbox",
        "--remote-debugging-address=127.0.0.1",
        "--remote-debugging-port=$attemptPort",
        "--user-data-dir=$profileDir",
        "about:blank"
    )

    $startProcessParams = @{
        FilePath = $chrome
        ArgumentList = $chromeArgs
        RedirectStandardOutput = $stdoutPath
        RedirectStandardError = $stderrPath
        PassThru = $true
    }
    if ($IsWindows) {
        $startProcessParams.WindowStyle = "Hidden"
    }
    $process = Start-Process @startProcessParams
    try {
        Wait-ForDevTools -Port $attemptPort -TimeoutSec $TimeoutSec -Process $process | Out-Null
        $target = Invoke-RestMethod -Uri "http://127.0.0.1:$attemptPort/json/new?$([uri]::EscapeDataString($Url))" -Method Put -TimeoutSec 10
        $socket = [System.Net.WebSockets.ClientWebSocket]::new()
        $socket.ConnectAsync([uri]$target.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
        try {
            $commandId = 0
            $viewports = @(
                [ordered]@{ Name = "desktop"; Width = 1280; Height = 900 },
                [ordered]@{ Name = "mobile"; Width = 390; Height = 900 }
            )
            $results = foreach ($viewport in $viewports) {
                Invoke-RenderedSmoke `
                    -Socket $socket `
                    -CommandId ([ref]$commandId) `
                    -Url $Url `
                    -Name $viewport.Name `
                    -Width $viewport.Width `
                    -Height $viewport.Height `
                    -ScreenshotPath (Join-Path $resolvedOutputDir "rendered-profile-smoke-$($viewport.Name).png")
            }
        } finally {
            $socket.Dispose()
        }
    } catch {
        $lastLaunchError = $_.Exception.Message
        if ($attempt -lt 2) {
            Write-Warning "Rendered profile smoke launch attempt $attempt failed: $lastLaunchError"
        }
    } finally {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $profileDir) {
            Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($null -eq $results) {
    $skipReason = "Chrome DevTools could not start after retry. Last error: $lastLaunchError"
    $skipReport = [ordered]@{
        generatedAt = [datetimeoffset]::Now.ToString("o")
        url = $Url
        chrome = $chrome
        passed = $false
        skipped = $true
        skipReason = $skipReason
        viewports = @()
    }
    $reportPath = Write-RenderedSmokeArtifact -Report $skipReport
    throw "Rendered profile smoke could not start Chrome DevTools after retry. See $reportPath. Last error: $lastLaunchError"
}

$report = [ordered]@{
    generatedAt = [datetimeoffset]::Now.ToString("o")
    url = $Url
    chrome = $chrome
    passed = (@($results | Where-Object { -not $_.passed }).Count -eq 0)
    skipped = $false
    skipReason = $null
    viewports = @($results)
}
$reportPath = Write-RenderedSmokeArtifact -Report $report

if (-not $report.passed) {
    Write-Error "Rendered profile smoke failed. See $reportPath."
}

Write-Host "Rendered profile smoke passed. Report: $reportPath"
