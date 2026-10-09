#Requires -Version 7.4
<#
.SYNOPSIS
Renders the profile's showcase images.
.DESCRIPTION
Buttons are SVGs built here (assets/buttons/*.svg). Banners are HTML templates in
design/showcase/ rendered to PNG (assets/showcase/*.png). Both go through headless Chromium
over DevTools: it measures the button labels and screenshots the banners. The README links
these files, so run this and commit the output whenever a template or a button changes.

The browser is CHROME_PATH when that's set, otherwise the first Chrome, Chromium or Edge
found. The banners load Inter from Google Fonts and screenshots from GitHub.
.EXAMPLE
pwsh -NoProfile -File scripts/render-showcase-assets.ps1
.EXAMPLE
pwsh -NoProfile -File scripts/render-showcase-assets.ps1 -Target buttons
#>
[CmdletBinding()]
param(
    [ValidateSet("buttons", "banners")]
    [string[]]$Target = @("buttons", "banners"),
    [int]$Port = 9234,
    [int]$TimeoutSec = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "chrome-devtools.ps1")

$RepoRoot = Split-Path -Parent $PSScriptRoot

# 24x24 stroke icons, drawn for these buttons. No third-party marks.
$ButtonIcons = @{
    download = "M12 4v11M7 10.5l5 5 5-5M5 20h14"
    phone = "M8 3h8a1.5 1.5 0 0 1 1.5 1.5v15A1.5 1.5 0 0 1 16 21H8a1.5 1.5 0 0 1-1.5-1.5v-15A1.5 1.5 0 0 1 8 3zM11 18h2"
    refresh = "M19.5 12a7.5 7.5 0 0 1-13 5.1M4.5 12a7.5 7.5 0 0 1 13-5.1M17.5 3.5v3.6h-3.6M6.5 20.5v-3.6h3.6"
    puzzle = "M9 4.5a2 2 0 0 1 4 0V6h4v4h1.5a2 2 0 0 1 0 4H17v5H5v-5h1.5a2 2 0 0 0 0-4H5V6h4z"
    bolt = "M13 3L5.5 13.5H12L11 21l7.5-10.5H12z"
    globe = "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9S14.5 18.4 12 21M12 3C9.5 5.6 8.3 8.6 8.3 12s1.2 6.4 3.7 9"
    code = "M8.5 7L3.5 12l5 5M15.5 7l5 5-5 5M13.5 4.5l-3 15"
    book = "M12 6.5C10.3 5 7.8 4.5 4 4.5v14c3.8 0 6.3.5 8 2 1.7-1.5 4.2-2 8-2v-14c-3.8 0-6.3.5-8 2zM12 6.5v14"
    search = "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13zM15.5 15.5L20 20"
    layers = "M12 3.5l8.5 4.5L12 12.5 3.5 8zM3.5 12.5l8.5 4.5 8.5-4.5M3.5 16.5L12 21l8.5-4.5"
}

# One file per button. Every fill holds at least 4.5:1 against white text and reads on both
# GitHub themes.
$ButtonSpecs = @(
    [pscustomobject]@{ Name = "windows"; Label = "Download for Windows"; Icon = "download"; Fill = "#1F6FEB" }
    [pscustomobject]@{ Name = "download"; Label = "Download"; Icon = "download"; Fill = "#1F6FEB" }
    [pscustomobject]@{ Name = "apk"; Label = "Get the APK"; Icon = "phone"; Fill = "#1A7F37" }
    [pscustomobject]@{ Name = "obtainium"; Label = "Obtainium"; Icon = "refresh"; Fill = "#57606A" }
    [pscustomobject]@{ Name = "morphe"; Label = "Add to Morphe"; Icon = "layers"; Fill = "#BF3989" }
    [pscustomobject]@{ Name = "extension"; Label = "Get the extension"; Icon = "puzzle"; Fill = "#6639BA" }
    [pscustomobject]@{ Name = "userscript"; Label = "Install userscript"; Icon = "bolt"; Fill = "#0E7C86" }
    [pscustomobject]@{ Name = "web"; Label = "Open the app"; Icon = "globe"; Fill = "#8250DF" }
    [pscustomobject]@{ Name = "source"; Label = "View source"; Icon = "code"; Fill = "#32383F" }
    [pscustomobject]@{ Name = "guide"; Label = "Read the guide"; Icon = "book"; Fill = "#32383F" }
    [pscustomobject]@{ Name = "search"; Label = "Search every tool"; Icon = "search"; Fill = "#8250DF" }
)

# The hero comes in both color schemes because the README swaps it with the reader's theme.
$BannerSpecs = @(
    [pscustomobject]@{ Template = "profile-hero.html"; Output = "profile-hero-dark.png"; Width = 1600; Height = 560; Scheme = "dark" }
    [pscustomobject]@{ Template = "profile-hero.html"; Output = "profile-hero-light.png"; Width = 1600; Height = 560; Scheme = "light" }
    [pscustomobject]@{ Template = "opentasker.html"; Output = "opentasker.png"; Width = 1280; Height = 640; Scheme = "dark" }
    [pscustomobject]@{ Template = "nvme-patcher.html"; Output = "nvme-patcher.png"; Width = 1280; Height = 640; Scheme = "dark" }
)

$ButtonFont = [pscustomobject]@{ Family = "'Segoe UI',Inter,'Helvetica Neue',Arial,sans-serif"; Size = 13; Weight = 700 }

function New-ShowcaseButtonSvg {
    <#
    .SYNOPSIS
    One button: an icon and a label in white on a rounded fill, 32 pixels tall.
    .DESCRIPTION
    TextWidth is the label's measured width in pixels. The text is stretched to exactly that
    width (textLength), so a viewer without the first font still gets a button that fits.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$IconPath,
        [Parameter(Mandatory)][string]$Fill,
        [Parameter(Mandatory)][ValidateRange(1, 1000)][int]$TextWidth,
        [Parameter(Mandatory)][object]$Font
    )

    $height = 32
    $padX = 12
    $icon = 16
    $gap = 7
    $width = $padX + $icon + $gap + $TextWidth + $padX
    $invariant = [cultureinfo]::InvariantCulture
    $iconY = ([double]($height - $icon) / 2).ToString($invariant)
    $scale = ([double]$icon / 24).ToString($invariant)
    $textX = $padX + $icon + $gap
    $textY = [math]::Round($height / 2 + 4.6, 1).ToString($invariant)
    $text = [System.Security.SecurityElement]::Escape($Label)

    return ('<svg xmlns="http://www.w3.org/2000/svg" width="{0}" height="{1}" viewBox="0 0 {0} {1}" role="img" aria-label="{2}">' -f $width, $height, $text) +
        "<title>$text</title>" +
        ('<rect width="{0}" height="{1}" rx="7" fill="{2}"/>' -f $width, $height, $Fill) +
        ('<rect x="0.5" y="0.5" width="{0}" height="{1}" rx="6.5" fill="none" stroke="#ffffff" stroke-opacity=".14"/>' -f ($width - 1), ($height - 1)) +
        ('<g transform="translate({0} {1}) scale({2})" fill="none" stroke="#ffffff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="{3}"/></g>' -f $padX, $iconY, $scale, $IconPath) +
        ('<text x="{0}" y="{1}" fill="#ffffff" font-family="{2}" font-size="{3}" font-weight="{4}" textLength="{5}" lengthAdjust="spacingAndGlyphs">{6}</text>' -f $textX, $textY, $Font.Family, $Font.Size, $Font.Weight, $TextWidth, $text) +
        "</svg>`n"
}

function Get-ShowcaseTextWidthExpression {
    <#
    .SYNOPSIS
    The page script that measures each label in the button font, rounded to whole pixels.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string[]]$Label,
        [Parameter(Mandatory)][object]$Font
    )

    $fontValue = "$($Font.Weight) $($Font.Size)px $($Font.Family)"
    $labels = ConvertTo-Json -InputObject @($Label) -Compress
    return "(() => { const c = document.createElement('canvas').getContext('2d'); c.font = $(ConvertTo-Json -InputObject $fontValue -Compress); return $labels.map((l) => Math.round(c.measureText(l).width)); })()"
}

function Invoke-CdpStep {
    # One DevTools command on the shared socket, numbered in order.
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [ref]$CommandId,
        [string]$Method,
        [hashtable]$Params = @{}
    )

    $CommandId.Value++
    return Send-CdpCommand -Socket $Socket -Id $CommandId.Value -Method $Method -Params $Params
}

function Save-ShowcaseBanner {
    <#
    .SYNOPSIS
    Loads one template at the banner's size and color scheme and writes a PNG of it.
    .DESCRIPTION
    Waits for the page, its web fonts and every image before the screenshot, so a slow font
    or screenshot download can't leave a fallback font or an empty frame in the banner.
    #>
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [ref]$CommandId,
        [object]$Spec,
        [string]$TemplatePath,
        [string]$OutputPath,
        [int]$TimeoutSec
    )

    Invoke-CdpStep -Socket $Socket -CommandId $CommandId -Method "Emulation.setDeviceMetricsOverride" -Params @{
        width = $Spec.Width
        height = $Spec.Height
        deviceScaleFactor = 1
        mobile = $false
    } | Out-Null
    Invoke-CdpStep -Socket $Socket -CommandId $CommandId -Method "Emulation.setEmulatedMedia" -Params @{
        features = @(@{ name = "prefers-color-scheme"; value = $Spec.Scheme })
    } | Out-Null
    Invoke-CdpStep -Socket $Socket -CommandId $CommandId -Method "Page.navigate" -Params @{ url = ([uri]$TemplatePath).AbsoluteUri } | Out-Null

    $ready = $null
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
    while ([datetime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $ready = Invoke-CdpStep -Socket $Socket -CommandId $CommandId -Method "Runtime.evaluate" -Params @{
            expression = "document.readyState === 'complete' ? document.fonts.ready.then(() => Promise.all([...document.images].map((i) => i.decode().catch(() => i.src)))).then((failed) => ({ fonts: document.fonts.status, failed: failed.filter(Boolean) })) : null"
            awaitPromise = $true
            returnByValue = $true
        }
        if ($null -ne $ready.result.value) { break }
    }
    if ($null -eq $ready -or $null -eq $ready.result.value) {
        throw "$($Spec.Template) did not finish loading within $TimeoutSec seconds."
    }
    $failed = @($ready.result.value.failed)
    if ($failed.Count -gt 0) {
        throw "$($Spec.Template) could not load: $($failed -join ', ')"
    }

    $shot = Invoke-CdpStep -Socket $Socket -CommandId $CommandId -Method "Page.captureScreenshot" -Params @{
        format = "png"
        clip = @{ x = 0; y = 0; width = $Spec.Width; height = $Spec.Height; scale = 1 }
    }
    [System.IO.File]::WriteAllBytes($OutputPath, [Convert]::FromBase64String($shot.data))
}

# Test seam: the Pester suite sets SYSADMINDOC_TEST_SEAM=1 and dot-sources this file to load
# the functions above, stopping before a browser starts or a file is written.
if ($MyInvocation.InvocationName -eq '.' -and $env:SYSADMINDOC_TEST_SEAM -eq '1') { return }

$chrome = Find-ChromeExecutable
$profileDir = Join-Path ([System.IO.Path]::GetTempPath()) ("SysAdminDoc-showcase-render-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $profileDir | Out-Null
$startProcessParams = @{
    FilePath = $chrome
    ArgumentList = @(
        "--headless=new",
        "--disable-gpu",
        "--disable-extensions",
        "--hide-scrollbars",
        "--no-default-browser-check",
        "--no-first-run",
        "--remote-debugging-address=127.0.0.1",
        "--remote-debugging-port=$Port",
        "--user-data-dir=$profileDir",
        "about:blank"
    )
    RedirectStandardOutput = (Join-Path $profileDir "chrome.out.log")
    RedirectStandardError = (Join-Path $profileDir "chrome.err.log")
    PassThru = $true
}
if ($IsWindows) {
    $startProcessParams.WindowStyle = "Hidden"
}
$process = Start-Process @startProcessParams
try {
    Wait-ForDevTools -Port $Port -TimeoutSec $TimeoutSec -Process $process | Out-Null
    $page = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/new?about:blank" -Method Put -TimeoutSec 10
    $socket = Connect-CdpWebSocket -WebSocketUrl $page.webSocketDebuggerUrl -TimeoutSec 10
    try {
        $commandId = 0
        Invoke-CdpStep -Socket $socket -CommandId ([ref]$commandId) -Method "Page.enable" | Out-Null

        if ($Target -contains "buttons") {
            $buttonDir = Join-Path $RepoRoot "assets/buttons"
            New-Item -ItemType Directory -Force -Path $buttonDir | Out-Null
            $measured = Invoke-CdpStep -Socket $socket -CommandId ([ref]$commandId) -Method "Runtime.evaluate" -Params @{
                expression = Get-ShowcaseTextWidthExpression -Label @($ButtonSpecs.Label) -Font $ButtonFont
                returnByValue = $true
            }
            $widths = @($measured.result.value)
            for ($i = 0; $i -lt $ButtonSpecs.Count; $i++) {
                $spec = $ButtonSpecs[$i]
                $svg = New-ShowcaseButtonSvg -Label $spec.Label -IconPath $ButtonIcons[$spec.Icon] -Fill $spec.Fill -TextWidth ([int]$widths[$i]) -Font $ButtonFont
                [System.IO.File]::WriteAllText((Join-Path $buttonDir "$($spec.Name).svg"), $svg, [System.Text.UTF8Encoding]::new($false))
                Write-Output "assets/buttons/$($spec.Name).svg"
            }
        }

        if ($Target -contains "banners") {
            $bannerDir = Join-Path $RepoRoot "assets/showcase"
            New-Item -ItemType Directory -Force -Path $bannerDir | Out-Null
            foreach ($spec in $BannerSpecs) {
                Save-ShowcaseBanner -Socket $socket -CommandId ([ref]$commandId) -Spec $spec -TemplatePath (Join-Path $RepoRoot "design/showcase/$($spec.Template)") -OutputPath (Join-Path $bannerDir $spec.Output) -TimeoutSec $TimeoutSec
                Write-Output "assets/showcase/$($spec.Output)"
            }
        }
    } finally {
        $socket.Dispose()
    }
} finally {
    if (-not $process.HasExited) {
        # Headless Chrome keeps a child process tree holding the profile directory; stop all of it.
        if ($IsWindows) {
            & taskkill.exe /PID $process.Id /T /F *> $null
        } else {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue
}
