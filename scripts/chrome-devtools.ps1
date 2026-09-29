#Requires -Version 7.4
# Headless Chromium over the DevTools protocol, shared by render-profile-smoke.ps1 and
# render-showcase-assets.ps1. Functions only: dot-source it, nothing runs on load.

function Find-ChromeExecutable {
    # CHROME_PATH names the browser outright (a Playwright Chromium, say). One that points
    # nowhere is an error, not a reason to start whatever browser the search below finds.
    # Set at all, it's used: one of only spaces is an error too.
    if (-not [string]::IsNullOrEmpty($env:CHROME_PATH)) {
        if (-not (Test-Path -LiteralPath $env:CHROME_PATH -PathType Leaf)) {
            throw "CHROME_PATH is set to '$env:CHROME_PATH', which isn't a file."
        }
        return $env:CHROME_PATH
    }

    $commands = @("google-chrome", "google-chrome-stable", "chromium", "chromium-browser")
    foreach ($command in $commands) {
        # Restrict to Application so a same-named alias/function/script shim cannot resolve to
        # an empty or non-browser Source that later breaks Start-Process.
        $found = Get-Command $command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found -and -not [string]::IsNullOrWhiteSpace($found.Source)) {
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

function Connect-CdpWebSocket {
    param(
        [string]$WebSocketUrl,
        [int]$TimeoutSec = 10
    )

    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    $cts = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSec))
    try {
        $socket.ConnectAsync([uri]$WebSocketUrl, $cts.Token).GetAwaiter().GetResult() | Out-Null
        return $socket
    } catch {
        $socket.Dispose()
        throw
    } finally {
        $cts.Dispose()
    }
}
