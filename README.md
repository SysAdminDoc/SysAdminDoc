<p align="center"><b>Broadcast IT, Healthcare IT, and practical public tools.</b><br/><sub>PowerShell &middot; Python &middot; C# &middot; Kotlin &middot; JavaScript &middot; Rust &middot; C++</sub></p>

## AI Implementation Services

I help small and midsize businesses put AI to work through tool rollout, workflow automation, team training, and ongoing support. I bring 15 years of enterprise IT and healthcare systems experience.

<p align="center"><a href="https://getparkerai.com/"><b>Explore Parker AI services</b></a> &middot; <a href="https://portfolio.getparkerai.com/ai/"><b>AI service overview</b></a></p>

<p align="center"><a href="#start-here">Start Here</a> &middot; <a href="#first-time-setup">First-time setup</a> &middot; <a href="#local-validation">Local validation</a></p>

<p align="center"><a href="#powershell-system-utilities">PowerShell</a> &middot; <a href="#python-desktop-applications">Python</a> &middot; <a href="#web-applications">Web Apps</a> &middot; <a href="#browser-extensions--userscripts">Extensions</a> &middot; <a href="#android-applications">Android</a> &middot; <a href="#security--networking">Security</a> &middot; <a href="#native-desktop-applications">Desktop</a> &middot; <a href="#media--conversion-tools">Media</a> &middot; <a href="#guides--resources">Guides</a> &middot; <a href="#misc--forks">Forks</a></p>

<!-- GENERATED PROFILE CATALOG: edit data/profile-catalog.json, then run scripts/sync-profile.ps1 -Write. Do not hand-edit the sections below. -->

### Start Here

Use this table to route quickly by task, platform, install path, and confidence signal. The full portfolio is better for search and filters; this README is optimized for fast routing and install confidence.

| Signal | I want to... | Best category | What you'll find | Action |
|:------:|:-------------|:--------------|:-----------------|:-------|
| <kbd>PS</kbd> | Automate Windows administration | [PowerShell](#powershell-system-utilities) or [Desktop](#native-desktop-applications) | Branch-pinned commands, release downloads, and focused desktop utilities. | [<kbd>Browse &#8594;</kbd>](#powershell-system-utilities) |
| <kbd>PY</kbd> | Build or run Python utilities | [Python](#python-desktop-applications) | Local-first tools, media workflows, automation, and integration helpers. | [<kbd>Browse &#8594;</kbd>](#python-desktop-applications) |
| <kbd>WEB</kbd> | Use a browser tool | [Web Apps](#web-applications) | No-install dashboards and self-hosted or live project surfaces. | [<kbd>Open &#8594;</kbd>](#web-applications) |
| <kbd>EXT</kbd> | Add browser functionality | [Extensions](#browser-extensions--userscripts) | CRX, XPI, userscript, source, and release-backed install paths. | [<kbd>Install &#8594;</kbd>](#browser-extensions--userscripts) |
| <kbd>APK</kbd> | Use tools on Android devices | [Android](#android-applications) | APK releases, Android source projects, and mobile utility workflows. | [<kbd>Download &#8594;</kbd>](#android-applications) |
| <kbd>SEC</kbd> | Audit, validate, or secure systems | [Security](#security--networking) | Network checks, DNS control, defensive tooling, and operator notes. | [<kbd>Browse &#8594;</kbd>](#security--networking) |
| <kbd>MED</kbd> | Capture, convert, or repair media | [Media](#media--conversion-tools) | Stream capture, video repair, compression, conversion, and cleanup tools. | [<kbd>Download &#8594;</kbd>](#media--conversion-tools) |
| <kbd>DOC</kbd> | Learn a repeatable workflow | [Guides](#guides--resources) | Public references, checklists, companion guides, and setup material. | [<kbd>Read &#8594;</kbd>](#guides--resources) |
| <kbd>OPS</kbd> | Set up or verify this profile repo | [First-time setup](#first-time-setup) or [Local validation](#local-validation) | Install checks, local linting, Pester, schema validation, and smoke evidence. | [<kbd>Verify &#8594;</kbd>](#local-validation) |
| <kbd>ALL</kbd> | Search across everything | [Full portfolio](https://portfolio.getparkerai.com/) or [Misc](#misc--forks) | Filterable portfolio data from the generated projects.json feed. | [<kbd>Search &#8594;</kbd>](https://portfolio.getparkerai.com/) |

Quick platform map: [PowerShell](#powershell-system-utilities) &middot; [Python](#python-desktop-applications) &middot; [Web Apps](#web-applications) &middot; [Extensions](#browser-extensions--userscripts) &middot; [Android](#android-applications) &middot; [Desktop](#native-desktop-applications)

Feed consumers: `projects.json` includes stable project IDs, canonical repository aliases, locale/script hints, and a `schemaPolicy` migration signal. Field-selecting consumers can keep their existing rendering path; strict validators should follow the declared supported version window.

---

<a id="first-time-setup"></a>

<details>
<summary><b>&#128190; First-time setup</b> -- <i>Inspect first, then install only the tooling your machine is missing.</i></summary>
<br/>

The setup path checks for PowerShell 7, Python, pip, and Git before changing anything, then refreshes the current shell so the project snippets and validation tools work immediately. On a fresh Windows machine, open **PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1 | iex
```

Inspect before installing:

```powershell
$u='https://raw.githubusercontent.com/SysAdminDoc/SysAdminDoc/main/setup.ps1'; $p="$env:TEMP\SysAdminDoc-setup.ps1"; irm $u -OutFile $p; notepad $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -CheckOnly
```

| Step | Behavior |
|:-----|:---------|
| Checks first | Reports PowerShell 7, Python, pip, and Git state before installing missing tools. |
| Inspect before installing | Save the script, review it, then run `-CheckOnly` to report PowerShell 7, Python, Git, pip, and winget state without installing. |
| Installs with Windows tooling | Uses `winget` for [PowerShell 7](https://learn.microsoft.com/powershell/), [Python 3.12](https://www.python.org/), and [Git for Windows](https://git-scm.com/). |
| Refreshes the shell | Updates the current `PATH` so install snippets and validation commands work without reopening PowerShell. |
| Records diagnostics | Writes a best-effort transcript to `%TEMP%\SysAdminDoc-setup-*.log`. |
| Shows its source | [`setup.ps1`](https://github.com/SysAdminDoc/SysAdminDoc/blob/main/setup.ps1) is the exact script being run. |

Already have PowerShell 7, Python, pip, and Git? Skip this section and open the category you need.

</details>

<a id="local-validation"></a>

<details>
<summary><b>&#9989; Local validation</b> -- <i>Regenerate, lint, analyze, test, and smoke-check the profile feed locally.</i></summary>
<br/>

Use this from the repo root before pushing profile, catalog, asset, or validation changes:

```powershell
pwsh -NoProfile -File .\scripts\validate-local.ps1
```

Create a redacted support bundle when local validation or setup needs troubleshooting:

```powershell
pwsh -NoProfile -File .\scripts\validate-local.ps1 -SupportBundlePath .\SysAdminDoc-support.zip -SupportBundleRedactValue 'PrivateRepoName'
```

The bundle contains tool versions, validation output, the profile sync report, and dependency-review evidence. User paths, common tokens/secrets, query credentials, and values supplied through `-SupportBundleRedactValue` are redacted. A setup transcript can be added directly when needed:

```powershell
pwsh -NoProfile -File .\scripts\new-support-bundle.ps1 -OutputPath .\SysAdminDoc-setup-support.zip -ProfileReportPath .\reports\profile-sync-report.json -SetupTranscriptPath (Get-ChildItem "$env:TEMP\SysAdminDoc-setup-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
```

Run the manual dependency and advisory review:

```powershell
npm run review:dependencies
```

Run the opt-in Pester 6 compatibility lane in an isolated module path:

```powershell
pwsh -NoProfile -File .\scripts\validate-local.ps1 -Pester6Compatibility
```

Optionally probe the deployed portfolio feed and key routes (warning-only):

```powershell
pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check -ProbePortfolio
```

Emit an optional redaction-safe Backstage catalog export:

```powershell
pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check -BackstageExportPath .\reports\backstage-catalog.json
```

| Check | Behavior |
|:------|:---------|
| Node tools | Runs `npm ci` before markdownlint so the pinned local package is present. |
| Dependency review | Runs `npm audit --json`, checks package override drift, verifies npm lock/hash pins, and reports latest-known npm/Python audit-tool freshness without failing solely on stale evidence. |
| PowerShell runtime | Reports the current `pwsh` version/channel, warns below PowerShell 7.6 LTS during the 7.4 transition window, and keeps Windows PowerShell 5.1 limited to `setup.ps1` bootstrap. |
| PowerShell tools | Installs and imports Pester 5.9.1 plus PSScriptAnalyzer 1.25.0 for the current user when needed. |
| Pester 6 compatibility | Add `-Pester6Compatibility` to save Pester 6.1.0 into an isolated temporary module path and run the non-integration suite; the default Pester 5.9.1 lane is unchanged. |
| Portfolio cross-surface probe | Add `-ProbePortfolio` to compare the deployed portfolio feed timestamp/schema/counts and key routes; external drift or outage is warning-only. |
| Markdown | Runs `npm run lint:markdown` against the tracked public Markdown surfaces. |
| Static analysis | Runs PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`. |
| Tests | Runs `Invoke-Pester -Path tests -Output Detailed`. |
| Support bundle | Add `-SupportBundlePath .\SysAdminDoc-support.zip` to capture a redacted JSON/ZIP diagnostic bundle; pass known private values with `-SupportBundleRedactValue`. |
| Backstage export | Add `-BackstageExportPath .\reports\backstage-catalog.json` to emit opt-in public-safe `backstage.io/v1alpha1` Component descriptors; suppressed, private, and metadata-unavailable rows are omitted. |
| Metadata budget drill | Runs `pwsh -NoProfile -File .\scripts\sync-profile.ps1 -Check -GraphQlPageSize 300` to exercise a smaller GitHub metadata page size and record request/retry telemetry. |
| Release verification pilot | Add `-VerifyReleaseArtifacts` to `-Check` to opt into capped GitHub release downloads with matching SHA-256 sidecars; the default remains metadata-only. |

Already bootstrapped? Add `-SkipBootstrap` to reuse installed modules and `node_modules`.

</details>

### Tool Catalog

Categories with suggested starting points and quick actions before the full generated catalog below.

| PowerShell | Python | Web Apps | Extensions | Android |
|:---|:---|:---|:---|:---|
| &#9889; **PowerShell**<br/>Windows automation and administration.<br/><sub>[**win11-nvme-driver-patcher**](https://github.com/SysAdminDoc/win11-nvme-driver-patcher)<br/>[**LibreSpot**](https://github.com/SysAdminDoc/LibreSpot)<br/>[**Network_Security_Auditor**](https://github.com/SysAdminDoc/Network_Security_Auditor)</sub><br/>[<kbd>Browse &#8594;</kbd>](#powershell-system-utilities) | &#128013; **Python**<br/>Utilities, libraries, and integration tools.<br/><sub>[**OpenCut**](https://github.com/SysAdminDoc/OpenCut)<br/>[**project-nomad-desktop**](https://github.com/SysAdminDoc/project-nomad-desktop)<br/>[**Vertigo**](https://github.com/SysAdminDoc/Vertigo)</sub><br/>[<kbd>Browse &#8594;</kbd>](#python-desktop-applications) | &#127760; **Web Apps**<br/>Self-hosted and online tools for IT.<br/><sub>[**Openshop**](https://github.com/SysAdminDoc/Openshop)<br/>[**StormviewRadar**](https://github.com/SysAdminDoc/StormviewRadar)<br/>[**SkyTrack**](https://github.com/SysAdminDoc/SkyTrack)</sub><br/>[<kbd>Open &#8594;</kbd>](#web-applications) | &#129513; **Extensions**<br/>Browser installs for productivity and security.<br/><sub>[**Astra-Deck**](https://github.com/SysAdminDoc/Astra-Deck)<br/>[**ScriptVault**](https://github.com/SysAdminDoc/ScriptVault)<br/>[**AmazonEnhanced**](https://github.com/SysAdminDoc/AmazonEnhanced)</sub><br/>[<kbd>Install &#8594;</kbd>](#browser-extensions--userscripts) | &#128241; **Android**<br/>Utilities and assistants for mobile workflows.<br/><sub>[**ZeusWatch**](https://github.com/SysAdminDoc/ZeusWatch)<br/>[**ClearCut**](https://github.com/SysAdminDoc/ClearCut)<br/>[**HostShield**](https://github.com/SysAdminDoc/HostShield)</sub><br/>[<kbd>Download &#8594;</kbd>](#android-applications) |

| Security | Desktop | Media | Guides | Misc |
|:---|:---|:---|:---|:---|
| &#128274; **Security**<br/>Audit, validate, and secure systems.<br/><sub>[**BetterNext**](https://github.com/SysAdminDoc/BetterNext)<br/>[**ESET**](https://github.com/SysAdminDoc/ESET)</sub><br/>[<kbd>Browse &#8594;</kbd>](#security--networking) | &#128421;&#65039; **Desktop**<br/>Focused Windows and cross-platform apps.<br/><sub>[**MyPortfolio**](https://github.com/SysAdminDoc/MyPortfolio)<br/>[**LocalChromeStore**](https://github.com/SysAdminDoc/LocalChromeStore)<br/>[**LocalDesktopStore**](https://github.com/SysAdminDoc/LocalDesktopStore)</sub><br/>[<kbd>Download &#8594;</kbd>](#native-desktop-applications) | &#127916; **Media**<br/>Capture, conversion, and media repair tools.<br/><sub>[**VideoSubtitleRemover**](https://github.com/SysAdminDoc/VideoSubtitleRemover)<br/>[**VideoCrush**](https://github.com/SysAdminDoc/VideoCrush)<br/>[**AlphaCut**](https://github.com/SysAdminDoc/AlphaCut)</sub><br/>[<kbd>Download &#8594;</kbd>](#media--conversion-tools) | &#128218; **Guides**<br/>Step-by-step guides and reference material.<br/><sub>[**AI_Realism**](https://github.com/SysAdminDoc/AI_Realism)<br/>[**facebook-exit-guide**](https://github.com/SysAdminDoc/facebook-exit-guide)<br/>[**android-debloat-list**](https://github.com/SysAdminDoc/android-debloat-list)</sub><br/>[<kbd>Read &#8594;</kbd>](#guides--resources) | &#128256; **Misc**<br/>Forks, continuations, and supporting utilities.<br/><sub>[**octopus-factory**](https://github.com/SysAdminDoc/octopus-factory)<br/>[**LTSC-MicrosoftStore**](https://github.com/SysAdminDoc/LTSC-MicrosoftStore)<br/>[**RcloneBrowser**](https://github.com/SysAdminDoc/RcloneBrowser)</sub><br/>[<kbd>Explore &#8594;</kbd>](#misc--forks) |

<a id="powershell-system-utilities"></a>
<details>
<summary><b>&#9889; PowerShell System Utilities</b> -- 30 repos -- <i>Clipboard-ready Windows administration tools with branch-pinned run commands.</i></summary>
<br/>

Suggested starting points: [**win11-nvme-driver-patcher**](https://github.com/SysAdminDoc/win11-nvme-driver-patcher), [**LibreSpot**](https://github.com/SysAdminDoc/LibreSpot), [**Network_Security_Auditor**](https://github.com/SysAdminDoc/Network_Security_Auditor).

[**win11-nvme-driver-patcher**](https://github.com/SysAdminDoc/win11-nvme-driver-patcher) &#11088;56 -- GUI to enable Windows Server 2025 NVMe driver on Win11 &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/win11-nvme-driver-patcher/releases/latest)
```powershell
$d="$env:TEMP\win11-nvme-driver-patcher"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/win11-nvme-driver-patcher $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\NVMe_Driver_Patcher.ps1"
```

[**LibreSpot**](https://github.com/SysAdminDoc/LibreSpot) &#11088;11 -- Spotify customization — automates Spicetify, themes, extensions &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/LibreSpot/releases/latest)
```powershell
$d="$env:TEMP\LibreSpot"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/LibreSpot $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\LibreSpot.ps1"
```

[**DisableDefender**](https://github.com/SysAdminDoc/DisableDefender) &#11088;10 -- Defender disabler/remover with CLI + premium WPF GUI; firewall preserved &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/DisableDefender/releases/latest)
```powershell
$d="$env:TEMP\DisableDefender"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/DisableDefender $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\DisableDefender.ps1"
```

[**DefenderControl**](https://github.com/SysAdminDoc/DefenderControl) &#11088;9 -- WPF GUI to fully disable or re-enable Microsoft Defender &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/DefenderControl/releases/latest)
```powershell
$d="$env:TEMP\DefenderControl"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/DefenderControl $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\DefenderControl.ps1"
```

[**Network_Security_Auditor**](https://github.com/SysAdminDoc/Network_Security_Auditor) &#11088;6 -- 67 automated checks across 8 security domains, MITRE ATT&CK mapping &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Network_Security_Auditor/releases/latest)
```powershell
$d="$env:TEMP\Network_Security_Auditor"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Network_Security_Auditor $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\NetworkSecurityAudit.ps1"
```

[**SystemUpdatePro**](https://github.com/SysAdminDoc/SystemUpdatePro) &#11088;5 -- Enterprise Windows update automation — OEM drivers, Windows Update, winget
```powershell
$d="$env:TEMP\SystemUpdatePro"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/SystemUpdatePro $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\SystemUpdatePro.ps1"
```

[**Debloat-Win11**](https://github.com/SysAdminDoc/Debloat-Win11) &#11088;4 -- Enterprise Windows 11 debloating with AppX removal, Office cleanup, telemetry blocking &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Debloat-Win11/releases/latest)
```powershell
$d="$env:TEMP\Debloat-Win11"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Debloat-Win11 $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\Debloat-Win11.ps1"
```

[**Start-Menu-Organizer**](https://github.com/SysAdminDoc/Start-Menu-Organizer) &#11088;4 -- Clean junk, detect broken shortcuts, reorganize Start Menu &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Start-Menu-Organizer/releases/latest)
```powershell
$d="$env:TEMP\Start-Menu-Organizer"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Start-Menu-Organizer $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\StartMenuOrganizerPro.ps1"
```

[**WURepair**](https://github.com/SysAdminDoc/WURepair) &#11088;4 -- Comprehensive Windows Update component repair — DLL re-registration, DISM, SFC, network reset &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/WURepair/releases/latest)
```powershell
$d="$env:TEMP\WURepair"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/WURepair $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\WURepair.ps1"
```

[**MonitorControl**](https://github.com/SysAdminDoc/MonitorControl) &#11088;3 -- Control monitor settings via DDC/CI &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/MonitorControl/releases/latest)
```powershell
$d="$env:TEMP\MonitorControl"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/MonitorControl $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\MonitorControlPro.ps1"
```

[**NetForge**](https://github.com/SysAdminDoc/NetForge) &#11088;3 -- WPF network adapter manager — static/DHCP, DNS presets, profile management &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/NetForge/releases/latest)
```powershell
$d="$env:TEMP\NetForge"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/NetForge $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\NetForge.ps1"
```

[**Disable-AdobeTelemetry**](https://github.com/SysAdminDoc/Disable-AdobeTelemetry) &#11088;2 -- Comprehensive Adobe telemetry and GrowthSDK suppression for Windows &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Disable-AdobeTelemetry/releases/latest)
```powershell
$d="$env:TEMP\Disable-AdobeTelemetry"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Disable-AdobeTelemetry $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\Disable-AdobeTelemetry.ps1"
```

[**Wingetter**](https://github.com/SysAdminDoc/Wingetter) &#11088;2 -- Discover, select, and bulk install software via Winget &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Wingetter/releases/latest)
```powershell
$d="$env:TEMP\Wingetter"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Wingetter $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\Wingetter.ps1"
```

[**Brave-Portable-Updater**](https://github.com/SysAdminDoc/Brave-Portable-Updater) &#11088;1 -- Update Brave inside a Portapps portable install without touching system install
```powershell
$d="$env:TEMP\Brave-Portable-Updater"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Brave-Portable-Updater $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\Update-BravePortable.ps1"
```

[**DefenderShield**](https://github.com/SysAdminDoc/DefenderShield) &#11088;1 -- Repair and restore Windows Defender and Firewall after debloaters
```powershell
$d="$env:TEMP\DefenderShield"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/DefenderShield $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\DefenderShield.ps1"
```

[**EXTRACTORX**](https://github.com/SysAdminDoc/EXTRACTORX) &#11088;1 -- Open-source bulk archive extraction tool for Windows &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/EXTRACTORX/releases/latest)
```powershell
$d="$env:TEMP\EXTRACTORX"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/EXTRACTORX $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\ExtractorX.ps1"
```

[**FirewallForge**](https://github.com/SysAdminDoc/FirewallForge) &#11088;1 -- WPF Windows Firewall manager with live rule editing and offline backup editor
```powershell
$d="$env:TEMP\FirewallForge"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/FirewallForge $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\FirewallManager.ps1"
```

[**TelemetrySlayer**](https://github.com/SysAdminDoc/TelemetrySlayer) &#11088;1 -- WPF GUI to disable Windows telemetry, data collection, and compatibility bloat &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/TelemetrySlayer/releases/latest)
```powershell
$d="$env:TEMP\TelemetrySlayer"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/TelemetrySlayer $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\TelemetrySlayer.ps1"
```

[**VoidTools-Everything-Settings-Manager**](https://github.com/SysAdminDoc/VoidTools-Everything-Settings-Manager) &#11088;1 -- GUI for managing VoidTools Everything settings, INI editing, CSV filter/bookmark management
```powershell
$d="$env:TEMP\VoidTools-Everything-Settings-Manager"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/VoidTools-Everything-Settings-Manager $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\EverythingSettingsManager.ps1"
```

[**WinForge**](https://github.com/SysAdminDoc/WinForge) &#11088;1 -- All-in-one Windows provisioning suite — app installer, tweaks, features, updates
```powershell
$d="$env:TEMP\WinForge"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/WinForge $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\WinForge.ps1"
```

[**AdapterLock**](https://github.com/SysAdminDoc/AdapterLock) -- Per-adapter IP lockdown for Windows -- WPF GUI, CLI mode, policy export, and event-log auditing
```powershell
$d="$env:TEMP\AdapterLock"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b master https://github.com/SysAdminDoc/AdapterLock $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\AdapterLock.ps1"
```

[**HostnameForensics**](https://github.com/SysAdminDoc/HostnameForensics) -- Traces how, when, and by whom a Windows hostname changed, with zipped raw evidence
```powershell
$d="$env:TEMP\HostnameForensics"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/HostnameForensics $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\Invoke-HostnameForensics.ps1"
```

[**JDownloader-2-Ultimate-Manager**](https://github.com/SysAdminDoc/JDownloader-2-Ultimate-Manager) -- Comprehensive automation for JDownloader 2 &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/releases/latest)
```powershell
$d="$env:TEMP\JDownloader-2-Ultimate-Manager"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/JDownloader-2-Ultimate-Manager $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\JDownloader 2 Ultimate Manager.ps1"
```

[**LogVerdict**](https://github.com/SysAdminDoc/LogVerdict) -- Scans Windows logs, deduplicates them into signatures, and rules on each one in plain English &nbsp;[<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/LogVerdict/releases/latest)

[**npp-sc-scanner**](https://github.com/SysAdminDoc/npp-sc-scanner) -- Detect and remediate Notepad++ supply chain attack IOCs
```powershell
$d="$env:TEMP\npp-sc-scanner"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/npp-sc-scanner $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\NppScanner-GUI.ps1"
```

[**NuclearDellRemover**](https://github.com/SysAdminDoc/NuclearDellRemover) -- Scorched-earth Dell bloatware removal — 8-phase complete cleanup &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/NuclearDellRemover/releases/latest)
```powershell
$d="$env:TEMP\NuclearDellRemover"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/NuclearDellRemover $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\NuclearDellRemover.ps1"
```

[**PathForge**](https://github.com/SysAdminDoc/PathForge) -- Filesystem repair, stubborn file deletion, path management &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/PathForge/releases/latest)
```powershell
$d="$env:TEMP\PathForge"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/PathForge $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\PathForge.ps1"
```

[**Restore-WindowsDefaults**](https://github.com/SysAdminDoc/Restore-WindowsDefaults) -- Reverse debloat changes and restore Windows to factory defaults
```powershell
$d="$env:TEMP\Restore-WindowsDefaults"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Restore-WindowsDefaults $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\Restore-WindowsDefaults.ps1"
```

[**ThankYouJeffrey**](https://github.com/SysAdminDoc/ThankYouJeffrey) -- A tribute to the creator of PowerShell, Jeffrey Snover
```powershell
$d="$env:TEMP\ThankYouJeffrey"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/ThankYouJeffrey $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\ThankYouJeffrey.ps1"
```

[**WallBrand**](https://github.com/SysAdminDoc/WallBrand) -- Wallpaper branding tool with GUI and CLI modes
```powershell
$d="$env:TEMP\WallBrand"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/WallBrand $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\WallBrandPro.ps1"
```

</details>

<a id="python-desktop-applications"></a>
<details>
<summary><b>&#128013; Python Desktop Applications</b> -- 30 repos -- <i>Local-first desktop utilities, media workflows, and automation built on Python 3.</i></summary>
<br/>

Suggested starting points: [**OpenCut**](https://github.com/SysAdminDoc/OpenCut), [**project-nomad-desktop**](https://github.com/SysAdminDoc/project-nomad-desktop), [**Vertigo**](https://github.com/SysAdminDoc/Vertigo).

[**OpenCut**](https://github.com/SysAdminDoc/OpenCut) &#11088;39 -- AI-powered video editing automation for Premiere Pro — caption generation, audio processing, VFX &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/OpenCut/releases/latest)
```powershell
$d="$env:TEMP\OpenCut"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/OpenCut $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\Install.ps1"
```

[**project-nomad-desktop**](https://github.com/SysAdminDoc/project-nomad-desktop) &#11088;12 -- Offline survival command center — maps, AI chat, situation room, NukeMap, supply tracking &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/project-nomad-desktop/releases/latest)
```powershell
$d="$env:TEMP\project-nomad-desktop"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b master https://github.com/SysAdminDoc/project-nomad-desktop $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\nomad.py"
```

[**SlunderStudio**](https://github.com/SysAdminDoc/SlunderStudio) &#11088;12 -- Offline AI music generation suite — song creation, lyrics, MIDI, vocals, stem separation, mastering &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/SlunderStudio/releases/latest)
```powershell
$d="$env:TEMP\SlunderStudio"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/SlunderStudio $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\main.py"
```

[**SunoJump**](https://github.com/SysAdminDoc/SunoJump) &#11088;10 -- Audio fingerprint masking for Suno AI — 10-pass pipeline, PyQt6 GUI, batch processing &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/SunoJump/releases/latest)
```powershell
$d="$env:TEMP\SunoJump"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/SunoJump $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\sunojump.py"
```

[**Bookmark-Organizer-Pro**](https://github.com/SysAdminDoc/Bookmark-Organizer-Pro) &#11088;7 -- AI-powered bookmark manager and categorizer &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Bookmark-Organizer-Pro/releases/latest)
```powershell
$d="$env:TEMP\Bookmark-Organizer-Pro"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Bookmark-Organizer-Pro $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\main.py"
```

[**MSStoreHelper**](https://github.com/SysAdminDoc/MSStoreHelper) &#11088;7 -- Install Microsoft Store apps without the Store &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/MSStoreHelper/releases/latest)
```powershell
$d="$env:TEMP\MSStoreHelper"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/MSStoreHelper $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\MSStoreHelper.py"
```

[**FaceSlim**](https://github.com/SysAdminDoc/FaceSlim) &#11088;3 -- AI face slimming, reshaping, and beautification with real-time preview and GPU acceleration &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/FaceSlim/releases/latest)
```powershell
$d="$env:TEMP\FaceSlim"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/FaceSlim $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\FaceSlim.py"
```

[**FileOrganizer**](https://github.com/SysAdminDoc/FileOrganizer) &#11088;3 -- AI-powered desktop tool for classifying and organizing design asset folders &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/FileOrganizer/releases/latest)
```powershell
$d="$env:TEMP\FileOrganizer"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/FileOrganizer $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\run.py"
```

[**ImgConverter**](https://github.com/SysAdminDoc/ImgConverter) &#11088;3 -- Universal image batch converter (PyQt6 GUI + CLI) with metadata, ICC, and HDR fidelity &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/ImgConverter/releases/latest)
```powershell
$d="$env:TEMP\ImgConverter"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b master https://github.com/SysAdminDoc/ImgConverter $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\imgconverter.py"
```

[**PyShop**](https://github.com/SysAdminDoc/PyShop) &#11088;3 -- Open source Photoshop alternative
```powershell
$d="$env:TEMP\PyShop"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/PyShop $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\pyshop_image_editor.py"
```

[**ExplorerTweaks**](https://github.com/SysAdminDoc/ExplorerTweaks) &#11088;2 -- GUI for toggling 50+ Windows File Explorer registry settings with live preview &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/ExplorerTweaks/releases/latest)
```powershell
$d="$env:TEMP\ExplorerTweaks"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/ExplorerTweaks $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\explorer_tweaks.py"
```

[**QuickFind**](https://github.com/SysAdminDoc/QuickFind) &#11088;2 -- Lightning-fast file search for Windows — reads NTFS MFT directly &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/QuickFind/releases/latest)
```powershell
$d="$env:TEMP\QuickFind"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/QuickFind $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\quickfind.py"
```

[**UniFile**](https://github.com/SysAdminDoc/UniFile) &#11088;2 -- AI-powered unified file organization — 5 engines, tag-based library, LLM integration &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/UniFile/releases/latest)
```powershell
$d="$env:TEMP\UniFile"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b master https://github.com/SysAdminDoc/UniFile $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\run.py"
```

[**AI-Model-Compass**](https://github.com/SysAdminDoc/AI-Model-Compass) &#11088;1 -- Discover, download, and run local AI models tailored to your hardware &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/AI-Model-Compass/releases/latest)
```powershell
$d="$env:TEMP\AI-Model-Compass"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/AI-Model-Compass $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\ai_model_compass.py"
```

[**AppList**](https://github.com/SysAdminDoc/AppList) &#11088;1 -- Scan, catalog, and export all installed applications &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/AppList/releases/latest)
```powershell
$d="$env:TEMP\AppList"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/AppList $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\AppList.py"
```

[**FoxPort**](https://github.com/SysAdminDoc/FoxPort) &#11088;1 -- Migrate passwords, bookmarks, and extensions from Chromium browsers to Firefox &nbsp;[<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/FoxPort/releases/latest)

[**GitForge**](https://github.com/SysAdminDoc/GitForge) &#11088;1 -- Full GitHub repo manager — clone, sync, diff, manage &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/GitForge/releases/latest)
```powershell
$d="$env:TEMP\GitForge"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/GitForge $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\gitforge.py"
```

[**HostsFileGet**](https://github.com/SysAdminDoc/HostsFileGet) &#11088;1 -- GUI for managing the Windows hosts file &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/HostsFileGet/releases/latest)
```powershell
$d="$env:TEMP\HostsFileGet"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/HostsFileGet $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\PythonLauncher.ps1"
```

[**LlamaLink**](https://github.com/SysAdminDoc/LlamaLink) &#11088;1 -- Sleek GUI frontend for llama.cpp — search, download, and chat with local LLMs &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/LlamaLink/releases/latest)
```powershell
$d="$env:TEMP\LlamaLink"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b master https://github.com/SysAdminDoc/LlamaLink $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\llamalink.py"
```

[**PromptCompanion**](https://github.com/SysAdminDoc/PromptCompanion) &#11088;1 -- A curated, searchable, offline library of the best AI prompts &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/PromptCompanion/releases/latest)
```powershell
$d="$env:TEMP\PromptCompanion"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/PromptCompanion $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\promptcompanion.py"
```

[**PyWall**](https://github.com/SysAdminDoc/PyWall) &#11088;1 -- Real-time Windows Firewall manager and network monitor &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/PyWall/releases/latest)
```powershell
$d="$env:TEMP\PyWall"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/PyWall $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\PyWall.py"
```

[**Qwen3-TTS-Studio**](https://github.com/SysAdminDoc/Qwen3-TTS-Studio) &#11088;1 -- AI voice generator powered by Qwen3-TTS &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Qwen3-TTS-Studio/releases/latest)
```powershell
$d="$env:TEMP\Qwen3-TTS-Studio"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Qwen3-TTS-Studio $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\qwen3_tts_studio.py"
```

[**Vertigo**](https://github.com/SysAdminDoc/Vertigo) &#11088;1 -- Vertical video studio for short-form creators — turns raw footage into polished 9:16 for Shorts/TikTok/Reels &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Vertigo/releases/latest)
```powershell
$d="$env:TEMP\Vertigo"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Vertigo $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\vertigo.py"
```

[**AIUsageTracker**](https://github.com/SysAdminDoc/AIUsageTracker) -- Windows dashboard that tracks AI assistant usage windows and alarms when they reset &nbsp;[<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/AIUsageTracker/releases/latest)

[**AstraDownloader**](https://github.com/SysAdminDoc/AstraDownloader) -- Desktop video downloader for Windows that also serves the Astra Deck extension locally &nbsp;[<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/AstraDownloader/releases/latest)

[**FantasyLeagueFootball**](https://github.com/SysAdminDoc/FantasyLeagueFootball) -- Draft-day board for half-PPR fantasy football, one offline HTML second screen plus a CLI &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/FantasyLeagueFootball/releases/latest)

[**FrameSnap**](https://github.com/SysAdminDoc/FrameSnap) -- Browse MP4 videos, mark frames visually, and export precise screenshots &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/FrameSnap/releases/latest)
```powershell
$d="$env:TEMP\FrameSnap"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/FrameSnap $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\framesnap.py"
```

[**Mattpad**](https://github.com/SysAdminDoc/Mattpad) -- Minimal notepad built for personal workflow &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/Mattpad/releases/latest)
```powershell
$d="$env:TEMP\Mattpad"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/Mattpad $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\mattpad.py"
```

[**SwiftShot**](https://github.com/SysAdminDoc/SwiftShot) -- Debloated, Greenshot-inspired screenshot tool &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/SwiftShot/releases/latest)
```powershell
$d="$env:TEMP\SwiftShot"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/SwiftShot $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; & "$d\App\Install-SwiftShot.ps1"
```

[**uBlock-Stylus-Converter**](https://github.com/SysAdminDoc/uBlock-Stylus-Converter) -- Convert uBlock cosmetic filters to Stylus CSS &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/uBlock-Stylus-Converter/releases/latest)
```powershell
$d="$env:TEMP\uBlock-Stylus-Converter"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/uBlock-Stylus-Converter $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\ublocktoCSS.py"
```

</details>

<a id="web-applications"></a>
<details>
<summary><b>&#127760; Web Applications</b> -- 28 repos -- <i>Launchable browser tools, dashboards, and project surfaces with no local install.</i></summary>
<br/>

Suggested starting points: [**Openshop**](https://github.com/SysAdminDoc/Openshop), [**StormviewRadar**](https://github.com/SysAdminDoc/StormviewRadar), [**SkyTrack**](https://github.com/SysAdminDoc/SkyTrack).

| Project | Description | Live |
|:--------|:------------|:----:|
| [**Openshop**](https://github.com/SysAdminDoc/Openshop) &#11088;11 | Free browser-based image editor - layers, smart effects, PSD import | [Launch](https://sysadmindoc.github.io/Openshop/) |
| [**CoolSites**](https://github.com/SysAdminDoc/CoolSites) &#11088;4 | Curated directory of 470+ free tools and open source projects | [Launch](https://sysadmindoc.github.io/CoolSites/) |
| [**UserScriptHunt**](https://github.com/SysAdminDoc/UserScriptHunt) &#11088;4 | Unified search engine for userscripts | [Launch](https://sysadmindoc.github.io/UserScriptHunt/) |
| [**BetterTTS**](https://github.com/SysAdminDoc/BetterTTS) &#11088;3 | Client-side text-to-speech studio running entirely in the browser, with WAV and MP3 export | [Launch](https://sysadmindoc.github.io/BetterTTS/) |
| [**ClipForge**](https://github.com/SysAdminDoc/ClipForge) &#11088;3 | Browser-based video editor powered by FFmpeg.wasm | [Launch](https://sysadmindoc.github.io/ClipForge/) |
| [**ImageXpert**](https://github.com/SysAdminDoc/ImageXpert) &#11088;2 | Multi-engine reverse image search — Google Lens, Yandex, Bing, TinEye | [Launch](https://sysadmindoc.github.io/ImageXpert/) |
| [**Multistreamer**](https://github.com/SysAdminDoc/Multistreamer) &#11088;2 | Multi-video streaming viewer with chat | [Launch](https://sysadmindoc.github.io/Multistreamer/) |
| [**SearchHub**](https://github.com/SysAdminDoc/SearchHub) &#11088;2 | Search 538 engines across 29 categories | [Launch](https://sysadmindoc.github.io/SearchHub/) |
| [**ConvertFlow**](https://github.com/SysAdminDoc/ConvertFlow) &#11088;1 | Browser-based media converter — audio, video, image — no uploads | [Launch](https://sysadmindoc.github.io/ConvertFlow/) |
| [**GifStudio**](https://github.com/SysAdminDoc/GifStudio) &#11088;1 | Browser-based GIF creation and editing studio — 100% client-side | [Launch](https://sysadmindoc.github.io/GifStudio/) |
| [**IconForge**](https://github.com/SysAdminDoc/IconForge) &#11088;1 | Browser-based image resizer and converter | [Launch](https://sysadmindoc.github.io/IconForge/) |
| [**LogLens**](https://github.com/SysAdminDoc/LogLens) &#11088;1 | Log file viewer and analyzer | [Launch](https://sysadmindoc.github.io/LogLens/) |
| [**MHTMLens**](https://github.com/SysAdminDoc/MHTMLens) &#11088;1 | MHTML file viewer and inspector | [Launch](https://sysadmindoc.github.io/MHTMLens/) |
| [**SkyTrack**](https://github.com/SysAdminDoc/SkyTrack) &#11088;1 | Real-time aircraft tracker — commercial, military, helicopters | [Launch](https://sysadmindoc.github.io/SkyTrack/) |
| [**SPECTRE**](https://github.com/SysAdminDoc/SPECTRE) &#11088;1 | Intelligence aggregator platform | [Launch](https://sysadmindoc.github.io/SPECTRE/) |
| [**StormviewRadar**](https://github.com/SysAdminDoc/StormviewRadar) &#11088;1 | Open source weather radar viewer | [Launch](https://sysadmindoc.github.io/StormviewRadar/) |
| [**ApocalypseWatch**](https://github.com/SysAdminDoc/ApocalypseWatch) | Realtime business-jet tracker dashboard vs. 24h baseline | [Launch](https://sysadmindoc.github.io/ApocalypseWatch/) |
| [**Base64Converter**](https://github.com/SysAdminDoc/Base64Converter) | Base64 encoding/decoding with file, text, QR code, and image support | [Launch](https://sysadmindoc.github.io/Base64Converter/) |
| [**BookmarkVault**](https://github.com/SysAdminDoc/BookmarkVault) | Bookmark management web app | [Launch](https://sysadmindoc.github.io/BookmarkVault/) |
| [**CronScope**](https://github.com/SysAdminDoc/CronScope) | Cron expression builder and visualizer | [Launch](https://sysadmindoc.github.io/CronScope/) |
| [**DeGoogler**](https://github.com/SysAdminDoc/DeGoogler) | Turnkey migration toolkit for leaving Google services | [Launch](https://sysadmindoc.github.io/DeGoogler/) |
| [**HurricaneMap**](https://github.com/SysAdminDoc/HurricaneMap) | Interactive map of every U.S. hurricane landfall (1851–present) — NOAA HURDAT2 | [Launch](https://sysadmindoc.github.io/HurricaneMap/) |
| [**kindred**](https://github.com/SysAdminDoc/kindred) | Compatibility-first dating and social platform | [Repo](https://github.com/SysAdminDoc/kindred) |
| [**NATO_PHONETIC_TRAINING**](https://github.com/SysAdminDoc/NATO_PHONETIC_TRAINING) | NATO phonetic alphabet training app | [Launch](https://sysadmindoc.github.io/NATO_PHONETIC_TRAINING/) |
| [**Segue**](https://github.com/SysAdminDoc/Segue) | Migrates Spotify playlists and liked songs to YouTube Music with a match-review step | [Launch](https://segue.getparkerai.com) |
| [**StormScope**](https://github.com/SysAdminDoc/StormScope) | Live US weather radar with webcam overlays -- NEXRAD radar plus 7,000+ traffic cameras | [Repo](https://github.com/SysAdminDoc/StormScope) |
| [**Text-Filter-Editor**](https://github.com/SysAdminDoc/Text-Filter-Editor) | Text filtering and processing tool | [Launch](https://sysadmindoc.github.io/Text-Filter-Editor/) |
| [**VIPTrack**](https://github.com/SysAdminDoc/VIPTrack) | Military and VIP aircraft tracker | [Launch](https://sysadmindoc.github.io/VIPTrack/) |

</details>

<a id="browser-extensions--userscripts"></a>
<details>
<summary><b>&#129513; Browser Extensions & Userscripts</b> -- 26 repos -- <i>Chrome, Firefox, and userscript installs with explicit release or raw-source paths.</i></summary>
<br/>

Suggested starting points: [**Astra-Deck**](https://github.com/SysAdminDoc/Astra-Deck), [**ScriptVault**](https://github.com/SysAdminDoc/ScriptVault), [**AmazonEnhanced**](https://github.com/SysAdminDoc/AmazonEnhanced).

| Project | Description | Install |
|:--------|:------------|:-------:|
| [**Astra-Deck**](https://github.com/SysAdminDoc/Astra-Deck) &#11088;12 | Premium YouTube enhancement extension — 150+ features for Chrome & Firefox | [<kbd>&#11015;&nbsp;ZIP/XPI</kbd>](https://github.com/SysAdminDoc/Astra-Deck/releases/latest) |
| [**YoutubeAdblock**](https://github.com/SysAdminDoc/YoutubeAdblock) &#11088;10 | Undetectable YouTube ad blocker with proxy engine | [Install](https://raw.githubusercontent.com/SysAdminDoc/YoutubeAdblock/main/YoutubeAdblock.user.js) |
| [**ScriptVault**](https://github.com/SysAdminDoc/ScriptVault) &#11088;6 | Open-source Chrome MV3 userscript manager — Monaco editor, 35+ GM APIs | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/ScriptVault/releases/latest) |
| [**UserScript-Finder**](https://github.com/SysAdminDoc/UserScript-Finder) &#11088;5 | Discover userscripts for any website | [Install](https://raw.githubusercontent.com/SysAdminDoc/UserScript-Finder/main/UserScript-Finder.user.js) |
| [**StyleKit**](https://github.com/SysAdminDoc/StyleKit) &#11088;3 | CSS customization extension — visual editor for any website | [<kbd>&#11015;&nbsp;CRX</kbd>](https://github.com/SysAdminDoc/StyleKit/releases/latest) |
| [**GeminiBuddy**](https://github.com/SysAdminDoc/GeminiBuddy) &#11088;2 | Productivity features for Gemini | [Install](https://raw.githubusercontent.com/SysAdminDoc/GeminiBuddy/main/GeminiBuddy.user.js) |
| [**MediaDL**](https://github.com/SysAdminDoc/MediaDL) &#11088;2 | Media downloader userscript | [Install](https://raw.githubusercontent.com/SysAdminDoc/MediaDL/main/MediaDL.user.js) |
| [**NDNS**](https://github.com/SysAdminDoc/NDNS) &#11088;2 | NextDNS control panel userscript | [Repo](https://github.com/SysAdminDoc/NDNS) |
| [**StyleCraft**](https://github.com/SysAdminDoc/StyleCraft) &#11088;2 | Full-featured CSS style editor and manager — Chrome extension | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/StyleCraft/releases/latest) |
| [**Claude-Ultimate-Enhancer**](https://github.com/SysAdminDoc/Claude-Ultimate-Enhancer) &#11088;1 | All-in-one Claude.ai enhancement suite — themes, usage monitor, prompt library | [Install](https://raw.githubusercontent.com/SysAdminDoc/Claude-Ultimate-Enhancer/main/Claude%20Ultimate%20Enhancer.user.js) |
| [**ClearGem**](https://github.com/SysAdminDoc/ClearGem) &#11088;1 | Removes visible watermarks from Google Gemini AI-generated images | [Install](https://raw.githubusercontent.com/SysAdminDoc/ClearGem/master/cleargem.user.js) |
| [**IMDb_Enhanced**](https://github.com/SysAdminDoc/IMDb_Enhanced) &#11088;1 | IMDb enhancement userscript | [Install](https://raw.githubusercontent.com/SysAdminDoc/IMDb_Enhanced/main/IMDb_Enhanced.user.js) |
| [**RumbleX**](https://github.com/SysAdminDoc/RumbleX) &#11088;1 | Comprehensive Rumble.com enhancement | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/RumbleX/releases/latest) |
| [**uBlockVanced**](https://github.com/SysAdminDoc/uBlockVanced) &#11088;1 | uBlock Origin with Catppuccin Mocha and Element Forge panel<br/><sub>Upstream: [gorhill/uBlock](https://github.com/gorhill/uBlock); License: GPL-3.0</sub> | [<kbd>&#11015;&nbsp;CRX</kbd>](https://github.com/SysAdminDoc/uBlockVanced/releases/latest) |
| [**Vantage**](https://github.com/SysAdminDoc/Vantage) &#11088;1 | New tab dashboard for Chromium — customizable search, RSS, news, weather, quick links | [Repo](https://github.com/SysAdminDoc/Vantage) |
| [**AI-Usage_Tracker**](https://github.com/SysAdminDoc/AI-Usage_Tracker) | Usage-limit countdowns and notifications for AI chat tools -- Chrome, Firefox, and userscript builds | [<kbd>&#11015;&nbsp;ZIP/XPI</kbd>](https://github.com/SysAdminDoc/AI-Usage_Tracker/releases/latest) |
| [**AmazonEnhanced**](https://github.com/SysAdminDoc/AmazonEnhanced) | Chrome MV3 Amazon UX cleanup — dark theme, sponsored-result removal, review-quality scoring, 20 locales | [<kbd>&#11015;&nbsp;CRX</kbd>](https://github.com/SysAdminDoc/AmazonEnhanced/releases/latest) |
| [**BackgroundSearch**](https://github.com/SysAdminDoc/BackgroundSearch) | Chrome extension — force background tabs + context menu search | [Repo](https://github.com/SysAdminDoc/BackgroundSearch) |
| [**Chapterizer**](https://github.com/SysAdminDoc/Chapterizer) | Auto-generate YouTube chapters, detect filler words, skip pauses | [Install](https://raw.githubusercontent.com/SysAdminDoc/Chapterizer/main/Chapterizer.user.js) |
| [**DarkModer**](https://github.com/SysAdminDoc/DarkModer) | Dark Reader as a userscript | [Install](https://raw.githubusercontent.com/SysAdminDoc/DarkModer/main/DarkModer.user.js) |
| [**Doordash-Enhanced**](https://github.com/SysAdminDoc/Doordash-Enhanced) | DoorDash dark mode and feature enhancements | [Install](https://raw.githubusercontent.com/SysAdminDoc/Doordash-Enhanced/main/DoorDashEnhanced.user.js) |
| [**ForceBGTab**](https://github.com/SysAdminDoc/ForceBGTab) | Forces link-opened tabs into the background so they never steal focus | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/ForceBGTab/releases/latest) |
| [**Kick Focus**](https://github.com/SysAdminDoc/kick-focus) | Desktop-first layout, accessibility, content filters, and ad defense for Kick.com | [Install](https://raw.githubusercontent.com/SysAdminDoc/kick-focus/main/kick-focus.user.js) |
| [**Reddit-Enhancement-Continued**](https://github.com/SysAdminDoc/Reddit-Enhancement-Continued) | Enhancement suite for old.reddit.com | [Install](https://raw.githubusercontent.com/SysAdminDoc/Reddit-Enhancement-Continued/main/RedditEnhancementContinued.user.js) |
| [**RES-Slim**](https://github.com/SysAdminDoc/RES-Slim) | Stripped-down Reddit Enhancement Suite fork for old.reddit.com comment tweaks and media expandos<br/><sub>Upstream: [honestbleeps/Reddit-Enhancement-Suite](https://github.com/honestbleeps/Reddit-Enhancement-Suite); License: GPL-3.0</sub> | [Repo](https://github.com/SysAdminDoc/RES-Slim) |
| [**StarBoard**](https://github.com/SysAdminDoc/StarBoard) | Ranks your GitHub repos by stars and shows star and fork gains since your last check | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/StarBoard/releases/latest) |

</details>

<a id="android-applications"></a>
<details>
<summary><b>&#128241; Android Applications</b> -- 21 repos -- <i>AMOLED-friendly APKs, Android source projects, and device-focused utilities.</i></summary>
<br/>

Suggested starting points: [**ZeusWatch**](https://github.com/SysAdminDoc/ZeusWatch), [**ClearCut**](https://github.com/SysAdminDoc/ClearCut), [**HostShield**](https://github.com/SysAdminDoc/HostShield).

| Project | Description | Download |
|:--------|:------------|:--------:|
| [**AppManagerNG**](https://github.com/SysAdminDoc/AppManagerNG) &#11088;52 | Power-user package manager — continuation of MuntashirAkon/AppManager<br/><sub>Upstream: [MuntashirAkon/AppManager](https://github.com/MuntashirAkon/AppManager); License: GPL-3.0-or-later</sub> | [Repo](https://github.com/SysAdminDoc/AppManagerNG) |
| [**OpenTasker**](https://github.com/SysAdminDoc/OpenTasker) &#11088;36 | FOSS Tasker alternative for Android | [Repo](https://github.com/SysAdminDoc/OpenTasker) |
| [**ClearCut**](https://github.com/SysAdminDoc/ClearCut) &#11088;34 | Full-featured Android video editor -- Kotlin, Jetpack Compose, and Media3 | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/ClearCut/releases/latest) |
| [**Aura**](https://github.com/SysAdminDoc/Aura) &#11088;21 | Open-source Zedge alternative — wallpapers, video wallpapers, ringtones, YouTube integration | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/Aura/releases/latest) |
| [**SwiftFloris**](https://github.com/SysAdminDoc/SwiftFloris) &#11088;21 | SwiftKey-inspired keyboard built on FlorisBoard's foundation | [Repo](https://github.com/SysAdminDoc/SwiftFloris) |
| [**HostShield**](https://github.com/SysAdminDoc/HostShield) &#11088;15 | AMOLED-dark hosts-based ad blocker — inspired by AdAway | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/HostShield/releases/latest) |
| [**FileExplorer**](https://github.com/SysAdminDoc/FileExplorer) &#11088;13 | Full-featured file manager with root access, archive support, cloud storage | [Repo](https://github.com/SysAdminDoc/FileExplorer) |
| [**AlarmClockXtreme**](https://github.com/SysAdminDoc/AlarmClockXtreme) &#11088;12 | Feature-rich alarm clock with dismiss challenges | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/AlarmClockXtreme/releases/latest) |
| [**Droidsmith**](https://github.com/SysAdminDoc/Droidsmith) &#11088;12 | Cross-platform ADB GUI for managing Android devices over USB/WiFi *(Rust)* | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/Droidsmith/releases/latest) |
| [**CallShield**](https://github.com/SysAdminDoc/CallShield) &#11088;11 | Spam call and text blocker — GitHub-hosted spam database, no API keys, no subscriptions | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/CallShield/releases/latest) |
| [**OpenLumen**](https://github.com/SysAdminDoc/OpenLumen) &#11088;9 | Open-source CF.Lumen successor -- root-grade display color filter for Android with rootless fallback | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/OpenLumen/releases/latest) |
| [**ZeusWatch**](https://github.com/SysAdminDoc/ZeusWatch) &#11088;7 | Premium dark weather app — no API keys required | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/ZeusWatch/releases/latest) |
| [**Lawnchair-Lite**](https://github.com/SysAdminDoc/Lawnchair-Lite) &#11088;5 | Lightweight launcher with 5 built-in dark themes | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/Lawnchair-Lite/releases/latest) |
| [**LocalAndroidStore**](https://github.com/SysAdminDoc/LocalAndroidStore) &#11088;4 | Personal Android-app catalog sourced from GitHub Releases — Android sibling of LocalChromeStore | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/LocalAndroidStore/releases/latest) |
| [**OpenSwift**](https://github.com/SysAdminDoc/OpenSwift) &#11088;4 | SwiftKey-inspired Android keyboard — glide typing, prediction, themes, clipboard | [Repo](https://github.com/SysAdminDoc/OpenSwift) |
| [**iOSIconPack**](https://github.com/SysAdminDoc/iOSIconPack) &#11088;3 | iOS-style icon pack for Android — 6 iOS eras | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/iOSIconPack/releases/latest) |
| [**one-ui-home-clone**](https://github.com/SysAdminDoc/one-ui-home-clone) &#11088;2 | Samsung One UI 7 parity launcher — Compose, clone not a port | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/one-ui-home-clone/releases/latest) |
| [**SnapCrop**](https://github.com/SysAdminDoc/SnapCrop) &#11088;1 | Screenshot editor — ML Kit autocrop, 14 draw tools, collage, device mockup | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/SnapCrop/releases/latest) |
| [**BillMinder**](https://github.com/SysAdminDoc/BillMinder) | Bill tracker with alarm-style reminders | [<kbd>&#11015;&nbsp;APK</kbd>](https://github.com/SysAdminDoc/BillMinder/releases/latest) |
| [**GuitarTuner**](https://github.com/SysAdminDoc/GuitarTuner) | Offline Android acoustic guitar tuner with automatic string detection and local-only microphone processing | [Repo](https://github.com/SysAdminDoc/GuitarTuner) |
| [**PatchDock**](https://github.com/SysAdminDoc/PatchDock) | Android patch manager | [Repo](https://github.com/SysAdminDoc/PatchDock) |

</details>

<a id="security--networking"></a>
<details>
<summary><b>&#128274; Security & Networking</b> -- 2 repos -- <i>Network auditing, DNS control, and defensive tooling with practical operator notes.</i></summary>
<br/>

Suggested starting points: [**BetterNext**](https://github.com/SysAdminDoc/BetterNext), [**ESET**](https://github.com/SysAdminDoc/ESET).

| Project | Description | Download |
|:--------|:------------|:--------:|
| [**BetterNext**](https://github.com/SysAdminDoc/BetterNext) &#11088;1 | Enhanced NextDNS Control Panel | [Repo](https://github.com/SysAdminDoc/BetterNext) |
| [**ESET**](https://github.com/SysAdminDoc/ESET) | Complete ESET port and address reference lists | [Repo](https://github.com/SysAdminDoc/ESET) |

</details>

<a id="media--conversion-tools"></a>
<details>
<summary><b>&#127916; Media & Conversion Tools</b> -- 7 repos -- <i>Video repair, compression, conversion, subtitle removal, and stream-capture workflows.</i></summary>
<br/>

Suggested starting points: [**VideoSubtitleRemover**](https://github.com/SysAdminDoc/VideoSubtitleRemover), [**VideoCrush**](https://github.com/SysAdminDoc/VideoCrush), [**AlphaCut**](https://github.com/SysAdminDoc/AlphaCut).

[**VideoSubtitleRemover**](https://github.com/SysAdminDoc/VideoSubtitleRemover) &#11088;63 -- Remove hardcoded subtitles from video &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/VideoSubtitleRemover/releases/latest)
```powershell
$d="$env:TEMP\VideoSubtitleRemover"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/VideoSubtitleRemover $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\VideoSubtitleRemover.py"
```

[**StreamKeep**](https://github.com/SysAdminDoc/StreamKeep) &#11088;11 -- Multi-platform stream/VOD downloader with built-in media converter &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/StreamKeep/releases/latest)
```powershell
$d="$env:TEMP\StreamKeep"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/StreamKeep $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\StreamKeep.py"
```

[**AlphaCut**](https://github.com/SysAdminDoc/AlphaCut) &#11088;1 -- Video background removal and compositing &nbsp;[<kbd>&#11015;&nbsp;Download</kbd>](https://github.com/SysAdminDoc/AlphaCut/releases/latest)
```powershell
$d="$env:TEMP\AlphaCut"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/AlphaCut $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\AlphaCut.py"
```

[**MediaForge**](https://github.com/SysAdminDoc/MediaForge) &#11088;1 -- Multi-format media converter
```powershell
$d="$env:TEMP\MediaForge"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/MediaForge $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\MediaForge.py"
```

[**GIFM**](https://github.com/SysAdminDoc/GIFM) -- Local GIF maker and compressor with Discord-ready target fitting &nbsp;[<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/GIFM/releases/latest)

[**VideoCrush**](https://github.com/SysAdminDoc/VideoCrush) -- Video compression and processing
```powershell
$d="$env:TEMP\VideoCrush"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/VideoCrush $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\video_compressor.py"
```

[**yt_livestream_downloader**](https://github.com/SysAdminDoc/yt_livestream_downloader) -- Download livestreams while they're still live
```powershell
$d="$env:TEMP\yt_livestream_downloader"; if(Test-Path $d){git -C $d pull -q}else{git clone -q --depth 1 -b main https://github.com/SysAdminDoc/yt_livestream_downloader $d}; if(Test-Path "$d\requirements.txt"){pip install -q -r "$d\requirements.txt"}; python "$d\yt_livestream_downloader.py"
```

</details>

<a id="native-desktop-applications"></a>
<details>
<summary><b>&#128421;&#65039; Native Desktop Applications</b> -- 26 repos -- <i>Installable Windows and cross-platform apps across C#, C++, Rust, and TypeScript.</i></summary>
<br/>

Suggested starting points: [**MyPortfolio**](https://github.com/SysAdminDoc/MyPortfolio), [**LocalChromeStore**](https://github.com/SysAdminDoc/LocalChromeStore), [**LocalDesktopStore**](https://github.com/SysAdminDoc/LocalDesktopStore).

| Project | Description | Language | Download |
|:--------|:------------|:--------:|:--------:|
| [**DeepPurge**](https://github.com/SysAdminDoc/DeepPurge) &#11088;6 | Thorough Windows uninstaller — removes programs completely, hunts down every leftover | C# | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/DeepPurge/releases/latest) |
| [**UniversalConverterX**](https://github.com/SysAdminDoc/UniversalConverterX) &#11088;6 | Native Windows file converter with context menu integration — 1000+ formats | C# | [Repo](https://github.com/SysAdminDoc/UniversalConverterX) |
| [**OpenNetLimit**](https://github.com/SysAdminDoc/OpenNetLimit) &#11088;3 | Per-application bandwidth limiter and network monitor for Windows | C# | [Repo](https://github.com/SysAdminDoc/OpenNetLimit) |
| [**PartitionPilot**](https://github.com/SysAdminDoc/PartitionPilot) &#11088;3 | Windows disk partition manager -- WPF disk map, SMART health, maintenance, and image workflows | C# | [Repo](https://github.com/SysAdminDoc/PartitionPilot) |
| [**RcloneBrowserNG**](https://github.com/SysAdminDoc/RcloneBrowserNG) &#11088;3 | Modern rclone GUI -- file browser, transfer manager, mount handler. Qt/C++ cross-platform desktop app. Community continuation of RcloneBrowser. | C++ | [Repo](https://github.com/SysAdminDoc/RcloneBrowserNG) |
| [**Images**](https://github.com/SysAdminDoc/Images) &#11088;2 | Dark-mode Windows 7 Classic Photo Viewer with live inline rename-while-viewing | C# | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/Images/releases/latest) |
| [**qBittorrent-Vanced**](https://github.com/SysAdminDoc/qBittorrent-Vanced) &#11088;2 | Customized BitTorrent client with dark theme<br/><sub>Upstream: [c0re100/qBittorrent-Enhanced-Edition](https://github.com/c0re100/qBittorrent-Enhanced-Edition); License: GPL-2.0-or-later / GPL-3.0-or-later assets</sub> | C++ | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/qBittorrent-Vanced/releases/latest) |
| [**AndroidEmulatorPlus**](https://github.com/SysAdminDoc/AndroidEmulatorPlus) &#11088;1 | Install Android SDK, manage AVDs, root with Magisk, migrate apps | C# | [Repo](https://github.com/SysAdminDoc/AndroidEmulatorPlus) |
| [**Cataclysm**](https://github.com/SysAdminDoc/Cataclysm) &#11088;1 | 3D-globe desktop simulator for tsunamis from asteroid impacts, nuclear bursts, earthquakes, and landslides | TypeScript | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/Cataclysm/releases/latest) |
| [**Devicer**](https://github.com/SysAdminDoc/Devicer) &#11088;1 | Unified Windows toolkit for rooted Android — identify, ROM search, partition backup, boot.img patch, flashing | C# | [Repo](https://github.com/SysAdminDoc/Devicer) |
| [**HostsGuard**](https://github.com/SysAdminDoc/HostsGuard) &#11088;1 | Real-time network privacy manager — DNS monitoring, hosts file management, firewall rules | C# | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/HostsGuard/releases/latest) |
| [**Keepr**](https://github.com/SysAdminDoc/Keepr) &#11088;1 | Pixel-close offline-first Google Keep clone -- Tauri 2 + React + Rust + SQLite | TypeScript | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/Keepr/releases/latest) |
| [**LocalChromeStore**](https://github.com/SysAdminDoc/LocalChromeStore) &#11088;1 | Personal Chromium extension store sourced from GitHub releases — one-click install/uninstall | C# | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/LocalChromeStore/releases/latest) |
| [**LocalDesktopStore**](https://github.com/SysAdminDoc/LocalDesktopStore) &#11088;1 | Private catalog for Windows desktop apps — MSI/Inno/NSIS/ZIP from GitHub releases | C# | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/LocalDesktopStore/releases/latest) |
| [**PhoneFork**](https://github.com/SysAdminDoc/PhoneFork) &#11088;1 | Dual-Samsung Android migration tool for Windows -- apps, media, settings, Wi-Fi, roles, and debloat profiles | C# | [Repo](https://github.com/SysAdminDoc/PhoneFork) |
| [**TaskCopy**](https://github.com/SysAdminDoc/TaskCopy) &#11088;1 | Single-click clipboard snippet menu -- tray icon, global hotkey, search | C# | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/TaskCopy/releases/latest) |
| [**Vigil**](https://github.com/SysAdminDoc/Vigil) &#11088;1 | Windows packaging for ungoogled-chromium<br/><sub>Upstream: [ungoogled-software/ungoogled-chromium-windows](https://github.com/ungoogled-software/ungoogled-chromium-windows); License: BSD-3-Clause</sub> | HTML | [Repo](https://github.com/SysAdminDoc/Vigil) |
| [**WolfPack**](https://github.com/SysAdminDoc/WolfPack) &#11088;1 | Custom LibreWolf portable distribution | Fluent | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/WolfPack/releases/latest) |
| [**MyPortfolio**](https://github.com/SysAdminDoc/MyPortfolio) | One Windows desktop catalog for every app I ship — binaries, extensions, APKs from GitHub releases | C# | [<kbd>&#11015;&nbsp;ZIP</kbd>](https://github.com/SysAdminDoc/MyPortfolio/releases/latest) |
| [**OrganizeContacts**](https://github.com/SysAdminDoc/OrganizeContacts) | Local-first contact organizer and deduper — native Windows, no cloud upload | C# | [Repo](https://github.com/SysAdminDoc/OrganizeContacts) |
| [**QuotaGlass**](https://github.com/SysAdminDoc/QuotaGlass) | Always-visible AI usage quota widget for Windows | C# | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/QuotaGlass/releases/latest) |
| [**REDplusplus**](https://github.com/SysAdminDoc/REDplusplus) | RED++ -- Remove Empty Directories. Find, display, and delete empty directories recursively with custom filter rules. | C# | [Repo](https://github.com/SysAdminDoc/REDplusplus) |
| [**Scour**](https://github.com/SysAdminDoc/Scour) | High-performance disk cleanup — 12 scanner types, NTFS MFT reading | C# | [Repo](https://github.com/SysAdminDoc/Scour) |
| [**Snapture**](https://github.com/SysAdminDoc/Snapture) | All-in-one screenshot utility — region/window/fullscreen, pinned overlays, no telemetry | C# | [Repo](https://github.com/SysAdminDoc/Snapture) |
| [**SurfaceMedic**](https://github.com/SysAdminDoc/SurfaceMedic) | Tune-up and thermal toolkit for heavily used Surface devices, with a dark WPF interface | C# | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/SurfaceMedic/releases/latest) |
| [**TerminalAI**](https://github.com/SysAdminDoc/TerminalAI) | Control surface for running many AI coding sessions at once, with native ConPTY terminals | Rust | [<kbd>&#11015;&nbsp;EXE</kbd>](https://github.com/SysAdminDoc/TerminalAI/releases/latest) |

</details>

<a id="guides--resources"></a>
<details>
<summary><b>&#128218; Guides & Resources</b> -- 4 repos -- <i>Public references, checklists, and companion guides for repeatable workflows.</i></summary>
<br/>

Suggested starting points: [**AI_Realism**](https://github.com/SysAdminDoc/AI_Realism), [**facebook-exit-guide**](https://github.com/SysAdminDoc/facebook-exit-guide), [**android-debloat-list**](https://github.com/SysAdminDoc/android-debloat-list).

| Project | Description |
|:--------|:------------|
| [**AI_Realism**](https://github.com/SysAdminDoc/AI_Realism) &#11088;1 | Field guide for ultra-realistic AI video generation |
| [**facebook-exit-guide**](https://github.com/SysAdminDoc/facebook-exit-guide) &#11088;1 | Guide for leaving Facebook |
| [**sysadmindoc.github.io**](https://github.com/SysAdminDoc/sysadmindoc.github.io) &#11088;1 | Personal portfolio and project showcase site hosted on GitHub Pages |
| [**android-debloat-list**](https://github.com/SysAdminDoc/android-debloat-list) | Curated Android debloat list with vulnerability notes — companion to AppManagerNG<br/><sub>Upstream: [MuntashirAkon/android-debloat-list](https://github.com/MuntashirAkon/android-debloat-list); License: AGPL-3.0</sub> |

</details>

<a id="misc--forks"></a>
<details>
<summary><b>&#128256; Misc & Forks</b> -- 6 repos -- <i>Forks, continuations, and supporting utilities with upstream context preserved.</i></summary>
<br/>

Suggested starting points: [**octopus-factory**](https://github.com/SysAdminDoc/octopus-factory), [**LTSC-MicrosoftStore**](https://github.com/SysAdminDoc/LTSC-MicrosoftStore), [**RcloneBrowser**](https://github.com/SysAdminDoc/RcloneBrowser).

| Project | Description |
|:--------|:------------|
| [**LTSC-MicrosoftStore**](https://github.com/SysAdminDoc/LTSC-MicrosoftStore) &#11088;1 | Add Windows Store to Win11 24H2 LTSC<br/><sub>Upstream: [minihub/LTSC-Add-MicrosoftStore](https://github.com/minihub/LTSC-Add-MicrosoftStore); License: Other</sub> |
| [**codex-terminal**](https://github.com/SysAdminDoc/codex-terminal) | Opens an AI CLI in a real PowerShell tab from VS Code, with a native terminal profile |
| [**octopus-factory**](https://github.com/SysAdminDoc/octopus-factory) | Recipe-driven autonomous coding pipeline - multi-agent build/audit/release |
| [**RcloneBrowser**](https://github.com/SysAdminDoc/RcloneBrowser) | Cross-platform GUI for rclone<br/><sub>Upstream: [kapitainsky/RcloneBrowser](https://github.com/kapitainsky/RcloneBrowser); License: MIT</sub> |
| [**TabExplorer**](https://github.com/SysAdminDoc/TabExplorer) | Tabbed file manager for Windows<br/><sub>Upstream: [derceg/explorerplusplus](https://github.com/derceg/explorerplusplus); License: GPL-3.0</sub> |
| [**TagStudio**](https://github.com/SysAdminDoc/TagStudio) | User-focused photo & file management system<br/><sub>Upstream: [TagStudioDev/TagStudio](https://github.com/TagStudioDev/TagStudio); License: GPL-3.0</sub> |

</details>

---

<p align="center"><a href="https://portfolio.getparkerai.com/"><b>View my full portfolio</b></a> &middot; <a href="https://github.com/SysAdminDoc?tab=repositories">Browse repositories</a></p>
