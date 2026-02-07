<#
.SYNOPSIS
    Claude Launch -- Spin up fresh Claude Code sessions (or plain terminals).

.DESCRIPTION
    Launches multiple Windows Terminal tabs/panes with Claude Code pre-loaded,
    targeting local or remote (SSH) project paths. Unlike claude-goodmorning
    (which resumes saved sessions with context), claude-launch spawns fresh
    instances for quick parallel work across multiple paths.

    Supports three methods for specifying targets:
    1. Target strings: "user@host:/path xN" (SSH) or "C:\path xN" (local)
    2. Single-target shorthand: -Host/-Path/-Count parameters
    3. Saved profiles: ~/.claude-sessions/launch-profiles.json

    Each spawned session gets:
    - Correct working directory (local) or SSH connection (remote)
    - Claude Code with --dangerously-skip-permissions (disable with -NoSkipPermissions)
    - OR plain terminal/shell with -NoClaude
    - Unique color scheme per pane for visual identification
    - Custom pane title with -Label or auto-generated from path

.EXAMPLE
    # Single-target shorthand (local)
    claude-launch -Path "C:\tools\myproject" -Count 2 -Panes "1x2"

.EXAMPLE
    # Single-target shorthand (remote SSH)
    claude-launch -Host "home@brainz" -Path "/opt/config" -Count 4 -Panes "2x2"

.EXAMPLE
    # Target strings (multiple targets, mixed local/remote)
    claude-launch "home@brainz:/opt/ai-server-config x2" "home@brainz:/opt/game-server-config x2" -Panes "2x2"
    claude-launch "C:\tools\project-a" "home@brainz:/opt/project-b x3" -Windows

.EXAMPLE
    # Terminal-only mode (no Claude)
    claude-launch -Path "C:\tools" -NoClaude

.EXAMPLE
    # Save and use profiles
    claude-launch -SaveProfile "brainz-servers" "home@brainz:/opt/ai-server x2" "home@brainz:/opt/game-server x2" -Panes "2x2"
    claude-launch -Profile "brainz-servers"
    claude-launch -ListProfiles
    claude-launch -DeleteProfile -Profile "brainz-servers"

.EXAMPLE
    # Dry run preview
    claude-launch -DryRun -Path "C:\tools" -Count 2 -Panes "1x2"
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Targets = @(),

    [string]$Host2 = "",
    [string]$Path = "",
    [int]$Count = 1,
    [string]$Label = "",

    [string]$Profile = "",
    [string]$SaveProfile = "",
    [switch]$ListProfiles,
    [switch]$DeleteProfile,

    [switch]$NoClaude,
    [switch]$NoSkipPermissions,

    [string]$Panes = "",
    [Alias("w")]
    [switch]$Windows,
    [int]$Delay = 3,
    [switch]$DryRun,
    [Alias("h")]
    [switch]$Help
)

# ── Remap -Host to avoid collision with automatic $Host variable ─────────
# PowerShell reserves $Host, so we use $Host2 as the param name and accept
# -Host from the command line via manual parsing.
$SshHost = $Host2
if (-not $SshHost) {
    for ($i = 0; $i -lt $Targets.Count; $i++) {
        if ($Targets[$i] -eq "-Host" -and ($i + 1) -lt $Targets.Count) {
            $SshHost = $Targets[$i + 1]
            $newTargets = @()
            for ($j = 0; $j -lt $Targets.Count; $j++) {
                if ($j -eq $i -or $j -eq ($i + 1)) { continue }
                $newTargets += $Targets[$j]
            }
            $Targets = $newTargets
            break
        }
    }
}

# ── Config ──────────────────────────────────────────────────────────────────
$SessionDir    = Join-Path $env:USERPROFILE ".claude-sessions"
$ProfilesFile  = Join-Path $SessionDir "launch-profiles.json"

# Tab colors -- distinct hues for easy visual identification
$TabColors = @("#2D7D9A", "#8B5CF6", "#D97706", "#059669", "#DC2626", "#7C3AED", "#0891B2", "#CA8A04", "#4F46E5", "#BE185D")

# WT color schemes -- match the custom schemes in Windows Terminal settings
$ColorSchemes = @("Claude Teal", "Claude Purple", "Claude Amber", "Claude Emerald", "Claude Red", "Claude Violet", "Claude Cyan", "Claude Gold")

# WT profile with suppressApplicationTitle so our --title sticks
$WtProfile = "Claude Session"

# Parse -Panes format: "RxC" (e.g. "2x4") or plain number (e.g. "4" = 1xN)
$PaneRows = 0
$PaneCols = 0
if ($Panes -match '^(\d+)x(\d+)$') {
    $PaneRows = [int]$Matches[1]
    $PaneCols = [int]$Matches[2]
}
elseif ($Panes -match '^\d+$' -and $Panes -ne "" -and [int]$Panes -gt 0) {
    $PaneRows = 1
    $PaneCols = [int]$Panes
}
$PanesPerTab = $PaneRows * $PaneCols

# ── Helpers ─────────────────────────────────────────────────────────────────

function Write-Banner {
    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor Cyan
    Write-Host "    Claude Launch" -ForegroundColor Cyan
    Write-Host "  ==============================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Usage {
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Target strings:" -ForegroundColor Yellow
    Write-Host "    claude-launch ""home@brainz:/opt/config x2""" -NoNewline -ForegroundColor Cyan
    Write-Host "           Remote SSH, 2 instances" -ForegroundColor DarkGray
    Write-Host "    claude-launch ""C:\tools\myproject""" -NoNewline -ForegroundColor Cyan
    Write-Host "                    Local path" -ForegroundColor DarkGray
    Write-Host "    claude-launch ""home@brainz:/opt/a x2"" ""home@brainz:/opt/b x2"" -Panes ""2x2""" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Single-target shorthand:" -ForegroundColor Yellow
    Write-Host "    claude-launch -Host ""home@brainz"" -Path ""/opt/config"" -Count 4 -Panes ""2x2""" -ForegroundColor Cyan
    Write-Host "    claude-launch -Path ""C:\tools"" -Count 2 -Panes ""1x2""" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Profiles:" -ForegroundColor Yellow
    Write-Host "    claude-launch -Profile ""brainz-servers""" -NoNewline -ForegroundColor Cyan
    Write-Host "                         Load saved profile" -ForegroundColor DarkGray
    Write-Host "    claude-launch -SaveProfile ""name"" <targets...>" -NoNewline -ForegroundColor Cyan
    Write-Host "          Save as profile" -ForegroundColor DarkGray
    Write-Host "    claude-launch -ListProfiles" -NoNewline -ForegroundColor Cyan
    Write-Host "                                  List all profiles" -ForegroundColor DarkGray
    Write-Host "    claude-launch -DeleteProfile -Profile ""name""" -NoNewline -ForegroundColor Cyan
    Write-Host "           Delete a profile" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor White
    Write-Host "    -NoClaude" -NoNewline -ForegroundColor Cyan
    Write-Host "             Open terminal only, no Claude" -ForegroundColor DarkGray
    Write-Host "    -NoSkipPermissions" -NoNewline -ForegroundColor Cyan
    Write-Host "    Don't use --dangerously-skip-permissions" -ForegroundColor DarkGray
    Write-Host "    -Panes <RxC>" -NoNewline -ForegroundColor Cyan
    Write-Host "         Grid layout per tab (e.g. -Panes 2x2, -Panes 4)" -ForegroundColor DarkGray
    Write-Host "    -Windows (-w)" -NoNewline -ForegroundColor Cyan
    Write-Host "        Separate windows instead of tabs" -ForegroundColor DarkGray
    Write-Host "    -Delay <seconds>" -NoNewline -ForegroundColor Cyan
    Write-Host "    Pause between spawns (default: 3)" -ForegroundColor DarkGray
    Write-Host "    -DryRun" -NoNewline -ForegroundColor Cyan
    Write-Host "              Preview without launching" -ForegroundColor DarkGray
    Write-Host "    -Help (-h)" -NoNewline -ForegroundColor Cyan
    Write-Host "           Show this help" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Target string format:" -ForegroundColor White
    Write-Host "    ""user@host:/remote/path xN""   Remote SSH (@ distinguishes from drive letters)" -ForegroundColor DarkGray
    Write-Host "    ""C:\local\path xN""             Local path" -ForegroundColor DarkGray
    Write-Host "    xN suffix is optional (defaults to 1)" -ForegroundColor DarkGray
    Write-Host ""
}

function Parse-TargetString {
    param([string]$Target)

    $count = 1
    $host_ = ""
    $path_ = ""
    $label_ = ""

    # Strip trailing " xN" count suffix
    if ($Target -match '^(.+?)\s+x(\d+)$') {
        $Target = $Matches[1].Trim()
        $count = [int]$Matches[2]
    }

    # Detect SSH vs local: presence of @ before any : means SSH
    # (C:\path has : but no @ before it)
    if ($Target -match '^([^:]+@[^:]+):(.+)$') {
        $host_ = $Matches[1]
        $path_ = $Matches[2]
    }
    elseif ($Target -match '@') {
        # host only, no path (e.g. "user@host")
        $host_ = $Target
        $path_ = "~"
    }
    else {
        $path_ = $Target
    }

    return @{
        Host  = $host_
        Path  = $path_.Trim()
        Count = $count
        Label = $label_
    }
}

function Load-Profiles {
    if (-not (Test-Path $ProfilesFile)) { return @{} }
    $raw = Get-Content $ProfilesFile -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    try {
        $obj = $raw | ConvertFrom-Json
        # Convert to hashtable
        $ht = @{}
        $obj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
        return $ht
    }
    catch {
        Write-Warning "Failed to parse profiles: $_"
        return @{}
    }
}

function Save-Profiles {
    param([hashtable]$Profiles)
    New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
    $Profiles | ConvertTo-Json -Depth 10 | Set-Content $ProfilesFile -Encoding UTF8
}

function Build-LaunchCmd {
    param(
        [string]$Title,
        [string]$ProjectPath,
        [string]$RemoteHost = "",
        [bool]$NoClaude = $false,
        [bool]$NoSkipPermissions = $false
    )

    $skipFlag = if ($NoSkipPermissions) { "" } else { "--dangerously-skip-permissions" }
    $launcherFile = Join-Path $env:TEMP "claude-launch-$(New-Guid).cmd"

    if ($RemoteHost -ne "") {
        if ($NoClaude) {
            $launcherContent = @"
@echo off
title $Title
echo.
echo   Claude Launch -- $Title [remote: $RemoteHost]
echo   Connecting to $RemoteHost...
echo.
ssh $RemoteHost -t "cd '$ProjectPath' && exec `$SHELL -l"
"@
        }
        else {
            $launcherContent = @"
@echo off
title $Title
echo.
echo   Claude Launch -- $Title [remote: $RemoteHost]
echo   Connecting to $RemoteHost...
echo.
ssh $RemoteHost -t "cd '$ProjectPath' && claude $skipFlag"
"@
        }
    }
    else {
        if ($NoClaude) {
            $launcherContent = @"
@echo off
title $Title
cd /d "$ProjectPath"
echo.
echo   Claude Launch -- $Title
echo.
cmd /k
"@
        }
        else {
            $launcherContent = @"
@echo off
title $Title
cd /d "$ProjectPath"
echo.
echo   Claude Launch -- $Title
echo.
claude $skipFlag
"@
        }
    }
    [System.IO.File]::WriteAllText($launcherFile, $launcherContent, [System.Text.Encoding]::ASCII)
    return $launcherFile
}

function Clean-OldLaunchers {
    $cutoff = (Get-Date).AddDays(-1)
    Get-ChildItem $env:TEMP -Filter "claude-launch-*.cmd" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Spawn-LaunchSessions {
    param([array]$Items)

    $hasWt = Get-Command wt.exe -ErrorAction SilentlyContinue
    $launched = 0

    # Build launcher files for all items
    $launchItems = @()
    foreach ($item in $Items) {
        $title = $item.Label
        if ([string]::IsNullOrWhiteSpace($title)) {
            $pathLeaf = Split-Path $item.Path -Leaf
            if ($item.Host) { $title = "$($item.Host):$pathLeaf" } else { $title = $pathLeaf }
        }
        $title = $title -replace '[^\w\s\-\.\:\@\/\\]', '' | ForEach-Object { $_.Trim() }
        if ([string]::IsNullOrWhiteSpace($title)) { $title = "Claude Launch" }

        # Add instance number if there are multiple with same base title
        if ($item.InstanceNum -gt 1 -or ($Items | Where-Object { $_.Label -eq $item.Label -and $_.Path -eq $item.Path -and $_.Host -eq $item.Host }).Count -gt 1) {
            $title = "$title #$($item.InstanceNum)"
        }

        $color = $TabColors[$launchItems.Count % $TabColors.Count]

        # Validate local paths
        if (-not $item.Host -and -not (Test-Path $item.Path)) {
            Write-Warning "  Skipping '$title' -- path not found: $($item.Path)"
            continue
        }

        $launcher = Build-LaunchCmd -Title $title -ProjectPath $item.Path -RemoteHost $item.Host -NoClaude $NoClaude -NoSkipPermissions $NoSkipPermissions

        if ($DryRun) {
            $modeTag = if ($NoClaude) { "[terminal]" } else { "[claude]" }
            $hostTag = if ($item.Host) { " @ $($item.Host)" } else { "" }
            Write-Host "  [DRY RUN] " -NoNewline -ForegroundColor Magenta
            Write-Host "$title" -NoNewline -ForegroundColor Cyan
            Write-Host " $modeTag" -NoNewline -ForegroundColor DarkYellow
            Write-Host "$hostTag" -NoNewline -ForegroundColor DarkGray
            Write-Host " -> $($item.Path)" -ForegroundColor DarkGray
            Remove-Item $launcher -ErrorAction SilentlyContinue
            $launched++
            continue
        }

        $launchItems += @{
            Title       = $title
            Launcher    = $launcher
            Color       = $color
            ProjectPath = $item.Path
            SshHost     = $item.Host
        }
    }

    if ($DryRun) { return $launched }
    if ($launchItems.Count -eq 0) { return 0 }

    if (-not $hasWt) {
        # Fallback: plain cmd windows
        foreach ($item in $launchItems) {
            $wd = if ($item.SshHost -eq "") { $item.ProjectPath } else { $env:USERPROFILE }
            Start-Process cmd.exe -ArgumentList "/k `"$($item.Launcher)`"" -WorkingDirectory $wd
            Write-Host "  Spawned: " -NoNewline -ForegroundColor Green
            Write-Host "$($item.Title)" -ForegroundColor Cyan
            $launched++
            Start-Sleep -Seconds $Delay
        }
        return $launched
    }

    # ── Grid pane mode: RxC layout per tab ─────────────────────────────
    if ($PaneCols -gt 0) {
        $groups = @()
        for ($i = 0; $i -lt $launchItems.Count; $i += $PanesPerTab) {
            $end = [Math]::Min($i + $PanesPerTab, $launchItems.Count)
            $groups += ,@($launchItems[$i..($end - 1)])
        }

        foreach ($group in $groups) {
            $windowArg = if ($Windows) { "-w new" } else { "-w 0" }
            $actualCols = [Math]::Min($PaneCols, $group.Count)

            # Helper to build pane args
            function Get-PaneArgs($item, $idx) {
                $scheme = $ColorSchemes[$idx % $ColorSchemes.Count]
                $dir = if ($item.SshHost -eq "") { "-d `"$($item.ProjectPath)`"" } else { "" }
                return "--title `"$($item.Title)`" --suppressApplicationTitle --colorScheme `"$scheme`" $dir cmd /k `"$($item.Launcher)`""
            }

            # Row 0, Column 0: new-tab
            $first = $group[0]
            $wtCmd = "$windowArg new-tab --tabColor `"$($first.Color)`" $(Get-PaneArgs $first 0)"

            # Row 0, Columns 1..cols-1: split-pane -V (vertical columns)
            for ($c = 1; $c -lt $actualCols -and $c -lt $group.Count; $c++) {
                $wtCmd += " ; split-pane -V $(Get-PaneArgs $group[$c] $c)"
            }

            # Additional rows: alternate right-to-left / left-to-right
            for ($r = 1; $r -lt $PaneRows; $r++) {
                $rightToLeft = ($r % 2 -eq 1)

                if ($rightToLeft) {
                    # Start from rightmost column (focus is already there after row 0 / previous even row)
                    $idx = $r * $actualCols + ($actualCols - 1)
                    if ($idx -lt $group.Count) {
                        $wtCmd += " ; split-pane -H $(Get-PaneArgs $group[$idx] $idx)"
                    }
                    # Move left through remaining columns
                    for ($c = $actualCols - 2; $c -ge 0; $c--) {
                        $idx = $r * $actualCols + $c
                        if ($idx -lt $group.Count) {
                            $wtCmd += " ; move-focus left ; split-pane -H $(Get-PaneArgs $group[$idx] $idx)"
                        }
                    }
                }
                else {
                    # Start from leftmost column (focus is there after previous odd row)
                    $idx = $r * $actualCols
                    if ($idx -lt $group.Count) {
                        $wtCmd += " ; split-pane -H $(Get-PaneArgs $group[$idx] $idx)"
                    }
                    # Move right through remaining columns
                    for ($c = 1; $c -lt $actualCols; $c++) {
                        $idx = $r * $actualCols + $c
                        if ($idx -lt $group.Count) {
                            $wtCmd += " ; move-focus right ; split-pane -H $(Get-PaneArgs $group[$idx] $idx)"
                        }
                    }
                }
            }

            Start-Process wt.exe -ArgumentList $wtCmd
            foreach ($item in $group) {
                Write-Host "  Spawned: " -NoNewline -ForegroundColor Green
                Write-Host "$($item.Title)" -ForegroundColor Cyan
                $launched++
            }
            Start-Sleep -Seconds $Delay
        }
    }
    # ── Tab mode: one tab per session ────────────────────────────────────
    else {
        $tabIdx = 0
        foreach ($item in $launchItems) {
            $windowArg = if ($Windows) { "-w new" } else { "-w 0" }
            $colorArg  = "--tabColor `"$($item.Color)`""
            $scheme    = $ColorSchemes[$tabIdx % $ColorSchemes.Count]
            $startDir  = if ($item.SshHost -eq "") { "-d `"$($item.ProjectPath)`"" } else { "" }

            $wtArgs = "$windowArg new-tab --title `"$($item.Title)`" --suppressApplicationTitle $colorArg --colorScheme `"$scheme`" $startDir cmd /k `"$($item.Launcher)`""
            Start-Process wt.exe -ArgumentList $wtArgs

            Write-Host "  Spawned: " -NoNewline -ForegroundColor Green
            Write-Host "$($item.Title)" -ForegroundColor Cyan
            $launched++
            $tabIdx++
            Start-Sleep -Seconds $Delay
        }
    }

    return $launched
}

# ── Main ────────────────────────────────────────────────────────────────────

Write-Banner

# ── Temp file cleanup ──────────────────────────────────────────────────────
Clean-OldLaunchers

# ── Help ────────────────────────────────────────────────────────────────────
if ($Help) {
    Write-Usage
    exit 0
}

# ── List profiles ──────────────────────────────────────────────────────────
if ($ListProfiles) {
    $profiles = Load-Profiles
    if ($profiles.Count -eq 0) {
        Write-Host "  No saved profiles." -ForegroundColor Gray
        Write-Host "  Use -SaveProfile ""name"" <targets...> to create one." -ForegroundColor DarkGray
    }
    else {
        Write-Host "  Saved profiles:" -ForegroundColor White
        Write-Host ""
        foreach ($name in ($profiles.Keys | Sort-Object)) {
            $p = $profiles[$name]
            $desc = if ($p.description) { " -- $($p.description)" } else { "" }
            $panes = if ($p.panes) { " [panes: $($p.panes)]" } else { "" }
            Write-Host "    $name" -NoNewline -ForegroundColor Cyan
            Write-Host "$desc" -NoNewline -ForegroundColor DarkGray
            Write-Host "$panes" -ForegroundColor DarkYellow

            if ($p.targets) {
                foreach ($t in $p.targets) {
                    $hostStr = if ($t.host) { "$($t.host):" } else { "" }
                    $countStr = if ($t.count -gt 1) { " x$($t.count)" } else { "" }
                    $labelStr = if ($t.label) { " ($($t.label))" } else { "" }
                    Write-Host "      $hostStr$($t.path)$countStr$labelStr" -ForegroundColor DarkGray
                }
            }
            Write-Host ""
        }
    }
    Write-Host ""
    exit 0
}

# ── Delete profile ─────────────────────────────────────────────────────────
if ($DeleteProfile) {
    if ([string]::IsNullOrWhiteSpace($Profile)) {
        Write-Host "  ERROR: -DeleteProfile requires -Profile ""name""" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    $profiles = Load-Profiles
    if ($profiles.ContainsKey($Profile)) {
        $profiles.Remove($Profile)
        Save-Profiles -Profiles $profiles
        Write-Host "  Deleted profile: $Profile" -ForegroundColor Green
    }
    else {
        Write-Host "  Profile not found: $Profile" -ForegroundColor Yellow
    }
    Write-Host ""
    exit 0
}

# ── Load profile if specified ──────────────────────────────────────────────
$profileTargets = @()
if ($Profile -ne "" -and $SaveProfile -eq "") {
    $profiles = Load-Profiles
    if (-not $profiles.ContainsKey($Profile)) {
        Write-Host "  ERROR: Profile not found: $Profile" -ForegroundColor Red
        Write-Host "  Use -ListProfiles to see available profiles." -ForegroundColor DarkGray
        Write-Host ""
        exit 1
    }

    $p = $profiles[$Profile]
    Write-Host "  Loading profile: $Profile" -ForegroundColor Yellow
    if ($p.description) {
        Write-Host "  $($p.description)" -ForegroundColor DarkGray
    }
    Write-Host ""

    # Apply profile defaults (command-line overrides take precedence)
    if ($Panes -eq "" -and $p.panes) {
        $Panes = $p.panes
        if ($Panes -match '^(\d+)x(\d+)$') {
            $PaneRows = [int]$Matches[1]
            $PaneCols = [int]$Matches[2]
        }
        elseif ($Panes -match '^\d+$' -and [int]$Panes -gt 0) {
            $PaneRows = 1
            $PaneCols = [int]$Panes
        }
        $PanesPerTab = $PaneRows * $PaneCols
    }

    if ($p.targets) {
        foreach ($t in $p.targets) {
            $profileTargets += @{
                Host  = if ($t.host) { $t.host } else { "" }
                Path  = $t.path
                Count = if ($t.count) { [int]$t.count } else { 1 }
                Label = if ($t.label) { $t.label } else { "" }
            }
        }
    }
}

# ── Resolve targets ────────────────────────────────────────────────────────
$resolvedTargets = @()

# Add targets from positional strings
foreach ($t in $Targets) {
    # Skip things that look like parameter names (already consumed)
    if ($t -match '^-') { continue }
    $resolvedTargets += Parse-TargetString $t
}

# Add single-target shorthand (-Host/-Path/-Count)
if ($Path -ne "") {
    $resolvedTargets += @{
        Host  = $SshHost
        Path  = $Path
        Count = $Count
        Label = $Label
    }
}

# Add profile targets
$resolvedTargets += $profileTargets

# ── Save profile ───────────────────────────────────────────────────────────
if ($SaveProfile -ne "") {
    if ($resolvedTargets.Count -eq 0) {
        Write-Host "  ERROR: No targets to save. Specify targets or -Path." -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    $profiles = Load-Profiles
    $profileData = @{
        description = ""
        panes = $Panes
        targets = @()
    }
    foreach ($t in $resolvedTargets) {
        $profileData.targets += @{
            host  = $t.Host
            path  = $t.Path
            count = $t.Count
            label = $t.Label
        }
    }
    $profiles[$SaveProfile] = $profileData
    Save-Profiles -Profiles $profiles

    Write-Host "  Saved profile: $SaveProfile" -ForegroundColor Green
    Write-Host "  Targets:" -ForegroundColor DarkGray
    foreach ($t in $resolvedTargets) {
        $hostStr = if ($t.Host) { "$($t.Host):" } else { "" }
        $countStr = if ($t.Count -gt 1) { " x$($t.Count)" } else { "" }
        Write-Host "    $hostStr$($t.Path)$countStr" -ForegroundColor DarkGray
    }
    if ($Panes) { Write-Host "  Panes: $Panes" -ForegroundColor DarkGray }
    Write-Host ""
    exit 0
}

# ── Validate ───────────────────────────────────────────────────────────────
if ($resolvedTargets.Count -eq 0) {
    Write-Host "  No targets specified." -ForegroundColor Yellow
    Write-Host "  Use -Help for usage, or specify targets / -Profile." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── Expand targets (count -> individual items) ─────────────────────────────
$expandedItems = @()
foreach ($t in $resolvedTargets) {
    $c = if ($t.Count -gt 0) { $t.Count } else { 1 }
    for ($i = 1; $i -le $c; $i++) {
        $expandedItems += @{
            Host        = $t.Host
            Path        = $t.Path
            Label       = $t.Label
            InstanceNum = $i
            TotalCount  = $c
        }
    }
}

# ── Display summary ────────────────────────────────────────────────────────
$modeLabel = if ($NoClaude) { "terminal" } else { "claude" }
$layoutLabel = if ($PaneCols -gt 0) { "${PaneRows}x${PaneCols} grid" } else { "tab" }

Write-Host "  Targets:" -ForegroundColor White
foreach ($t in $resolvedTargets) {
    $hostStr = if ($t.Host) { "$($t.Host):" } else { "" }
    $countStr = if ($t.Count -gt 1) { " x$($t.Count)" } else { "" }
    $labelStr = if ($t.Label) { " ($($t.Label))" } else { "" }
    $color = $TabColors[$resolvedTargets.IndexOf($t) % $TabColors.Count]
    Write-Host "    $color " -NoNewline -ForegroundColor DarkGray
    Write-Host "$hostStr$($t.Path)$countStr$labelStr" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Launching $($expandedItems.Count) $modeLabel session(s) in $layoutLabel mode..." -ForegroundColor Yellow
Write-Host ""

# ── Spawn ──────────────────────────────────────────────────────────────────
$spawned = Spawn-LaunchSessions -Items $expandedItems

Write-Host ""
if ($spawned -gt 0) {
    if ($DryRun) {
        Write-Host "  $spawned session(s) previewed. Remove -DryRun to launch." -ForegroundColor Magenta
    }
    else {
        Write-Host "  $spawned session(s) launched. Let's get to work." -ForegroundColor Green
    }
}
else {
    Write-Host "  No sessions could be launched. Check paths and targets." -ForegroundColor Yellow
}
Write-Host ""
