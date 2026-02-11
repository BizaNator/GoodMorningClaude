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
    [string]$Terminal = "auto",
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

# Load terminal providers
$providerDir = Join-Path $PSScriptRoot "terminal-providers"
. (Join-Path $providerDir "TerminalProvider.ps1")
. (Join-Path $providerDir "WindowsTerminalProvider.ps1")
. (Join-Path $providerDir "WaveTerminalProvider.ps1")
. (Join-Path $providerDir "CmdFallbackProvider.ps1")

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

function Get-SlashCommandInstallScript {
    <#
    .SYNOPSIS
        Returns a bash script that auto-installs /goodnight and /goodmorning slash commands on remote hosts
    #>

    # Embed the slash command content (escaped for heredoc)
    $goodnightContent = Get-Content "$PSScriptRoot\..\claude-commands\goodnight.md" -Raw
    $goodmorningContent = Get-Content "$PSScriptRoot\..\claude-commands\goodmorning.md" -Raw

    # Create bash script with heredocs (single quotes prevent expansion)
    # NOTE: Use -f (file exists) check instead of ! -f to avoid cmd.exe ! escaping issues
    return @"
# Auto-install Claude slash commands if not present
if [ -f ~/.claude/commands/goodnight.md ]; then
    true
else
    echo "  Installing Claude slash commands..."
    mkdir -p ~/.claude/commands

    cat > ~/.claude/commands/goodnight.md << 'EOFGOODNIGHT'
$goodnightContent
EOFGOODNIGHT

    cat > ~/.claude/commands/goodmorning.md << 'EOFGOODMORNING'
$goodmorningContent
EOFGOODMORNING

    echo "  Slash commands installed^!"
fi
"@
}

function New-AutoSavedSession {
    param(
        [string]$SessionSlug,
        [string]$SessionName,
        [string]$ProjectPath,
        [string]$SshHost = "",
        [string]$TmuxSessionName = ""
    )

    <#
    .SYNOPSIS
        Auto-saves a newly launched session to the registry and creates a session file
    .DESCRIPTION
        This allows sessions launched via claude-launch to be tracked immediately,
        even if the user forgets to run /goodnight. They can still reconnect via tmux.
    #>

    $timestamp = Get-Date -Format "yyyy-MM-dd"
    $sessionFile = Join-Path $SessionDir "${timestamp}_${SessionSlug}.md"
    $projectName = if ($ProjectPath) { Split-Path $ProjectPath -Leaf } else { "Unknown" }

    # Create session file with placeholder content
    $sessionContent = @"
# Session: $SessionName -- $timestamp

## Status
in-progress

## Session Name
$SessionName

## Project Path
$ProjectPath
"@

    if ($SshHost) {
        $sessionContent += @"


## Host
$SshHost
"@
    }

    if ($TmuxSessionName) {
        $sessionContent += @"


## Tmux Session
$TmuxSessionName
"@
    }

    $sessionContent += @"


## Active Tasks
- Freshly launched session - no saved context yet

## Plan / Next Steps
1. Run ``/goodnight`` to save your work context before closing

## Key Context
- Session was auto-created by claude-launch
- No context saved yet - this is a fresh start

## Files & Paths
- (None recorded yet)

## Notes
Auto-saved session created at launch time. Run ``/goodnight`` to update with actual work context.
"@

    # Write session file
    New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
    [System.IO.File]::WriteAllText($sessionFile, $sessionContent, [System.Text.Encoding]::UTF8)

    # Update registry
    $RegistryFile = Join-Path $SessionDir "session-registry.json"
    $registry = @()
    if (Test-Path $RegistryFile) {
        $raw = Get-Content $RegistryFile -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try {
                $parsed = ConvertFrom-Json $raw
                # Ensure we have a flat array of valid entries
                if ($parsed -is [Array]) {
                    $registry = @($parsed | Where-Object { $_ -and $_.sessionSlug })
                } elseif ($parsed.sessionSlug) {
                    $registry = @($parsed)
                }
            } catch {
                Write-Warning "Registry file corrupted, starting fresh"
                $registry = @()
            }
        }
    }

    # Create new entry
    $newEntry = @{
        sessionName      = $SessionName
        sessionSlug      = $SessionSlug
        projectName      = $projectName
        projectPath      = $ProjectPath
        host             = $SshHost
        resumePath       = $sessionFile
        status           = "in-progress"
        lastUpdated      = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        tmuxSessionName  = $TmuxSessionName
        tmuxAttached     = $false
        preferredTerminal = "auto"
    }

    # Check if entry already exists (by sessionSlug)
    $existingIndex = -1
    for ($i = 0; $i -lt $registry.Count; $i++) {
        if ($registry[$i].sessionSlug -eq $SessionSlug) {
            $existingIndex = $i
            break
        }
    }

    if ($existingIndex -ge 0) {
        # Update existing entry
        $registry[$existingIndex] = $newEntry
    } else {
        # Add new entry
        $registry += $newEntry
    }

    # Write registry
    $json = $registry | ConvertTo-Json -Depth 5
    if ($registry.Count -eq 0) { $json = "[]" }
    if ($registry.Count -eq 1) { $json = "[$json]" }
    [System.IO.File]::WriteAllText($RegistryFile, $json, [System.Text.Encoding]::UTF8)

    Write-Host "  Auto-saved: $SessionName" -ForegroundColor DarkGray
}

function Build-LaunchCmd {
    param(
        [string]$Title,
        [string]$ProjectPath,
        [string]$RemoteHost = "",
        [bool]$NoClaude = $false,
        [bool]$NoSkipPermissions = $false,
        [string]$TmuxSessionName = ""
    )

    $skipFlag = if ($NoSkipPermissions) { "" } else { "--dangerously-skip-permissions" }
    $launcherFile = Join-Path $env:TEMP "claude-launch-$(New-Guid).cmd"

    if ($RemoteHost -ne "") {
        # Check if we should use tmux for remote sessions
        if ($TmuxSessionName -ne "" -and -not $NoClaude) {
            # Check if tmux session exists
            $tmuxExists = Test-TmuxSession -SshHost $RemoteHost -TmuxName $TmuxSessionName

            if ($tmuxExists) {
                # Attach to existing session
                $launcherContent = @"
@echo off
title $Title
echo.
echo   Claude Launch -- $Title [remote: $RemoteHost]
echo   Attaching to tmux session: $TmuxSessionName...
echo.
ssh $RemoteHost -t "tmux attach-session -t '$TmuxSessionName'"
"@
            }
            else {
                # Create new tmux session with Claude
                $launcherContent = @"
@echo off
title $Title
echo.
echo   Claude Launch -- $Title [remote: $RemoteHost]
echo   Creating tmux session: $TmuxSessionName...
echo.
ssh $RemoteHost -t "tmux new-session -d -s '$TmuxSessionName' && tmux send-keys -t '$TmuxSessionName' 'cd \"$ProjectPath\"' Enter && tmux send-keys -t '$TmuxSessionName' 'claude $skipFlag' Enter && tmux attach-session -t '$TmuxSessionName'"
"@
            }
        }
        elseif ($NoClaude) {
            # NoClaude mode - plain terminal
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
            # Direct SSH without tmux
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
        # Local session - check if Team mode enabled and tmux available
        $teamMode = Get-TeamModeConfig
        $useTmux = ($teamMode -in @("prefer-attach", "auto")) -and (Test-LocalTmuxAvailable) -and -not $NoClaude

        if ($useTmux -and $TmuxSessionName -ne "") {
            # Local Team mode with tmux
            $tmuxExists = Test-LocalTmuxSession -TmuxName $TmuxSessionName

            if ($tmuxExists) {
                # Attach to existing local tmux session
                $launcherContent = @"
@echo off
title $Title
echo.
echo   Claude Launch -- $Title [Team mode]
echo   Attaching to tmux session: $TmuxSessionName...
echo.
tmux attach-session -t "$TmuxSessionName"
"@
            }
            else {
                # Create new local tmux session with Claude
                # Use send-keys approach for better compatibility with psmux
                $launcherContent = @"
@echo off
title $Title
echo.
echo   Claude Launch -- $Title [Team mode]
echo   Creating tmux session: $TmuxSessionName...
echo.
tmux new-session -d -s "$TmuxSessionName"
tmux send-keys -t "$TmuxSessionName" "cd /d `"$ProjectPath`"" Enter
tmux send-keys -t "$TmuxSessionName" "claude $skipFlag" Enter
tmux attach-session -t "$TmuxSessionName"
"@
            }
        }
        elseif ($NoClaude) {
            # NoClaude mode
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
            # Regular local session (no tmux)
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

    # Build launcher files and session items
    $launchItems = @()
    $launched = 0

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

        # Validate local paths
        if (-not $item.Host -and -not (Test-Path $item.Path)) {
            Write-Warning "  Skipping '$title' -- path not found: $($item.Path)"
            continue
        }

        # Generate tmux session name (for both remote and local Team mode)
        $tmuxName = ""
        $teamMode = Get-TeamModeConfig
        $needsTmux = ($item.Host -ne "") -or (($teamMode -in @("prefer-attach", "auto")) -and (Test-LocalTmuxAvailable))

        if ($needsTmux -and -not $NoClaude) {
            # Use a counter-based naming for launch (since these are fresh sessions)
            $pathSlug = ($item.Path -replace '[^a-zA-Z0-9\-]', '-').Trim('-').ToLower()
            $tmuxName = "claude-launch-$pathSlug-$($item.InstanceNum)"
        }

        # Auto-save session to registry (unless in NoClaude mode)
        if (-not $NoClaude) {
            $sessionSlug = if ($tmuxName) { $tmuxName } else {
                $pathSlug = ($item.Path -replace '[^a-zA-Z0-9\-]', '-').Trim('-').ToLower()
                "launch-$pathSlug-$($item.InstanceNum)"
            }
            $sessionName = "$title (launched)"

            New-AutoSavedSession -SessionSlug $sessionSlug `
                                  -SessionName $sessionName `
                                  -ProjectPath $item.Path `
                                  -SshHost $item.Host `
                                  -TmuxSessionName $tmuxName
        }

        $launcher = Build-LaunchCmd -Title $title -ProjectPath $item.Path -RemoteHost $item.Host -NoClaude $NoClaude -NoSkipPermissions $NoSkipPermissions -TmuxSessionName $tmuxName

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
            ProjectPath = $item.Path
            SshHost     = $item.Host
        }
    }

    if ($DryRun) { return $launched }
    if ($launchItems.Count -eq 0) { return 0 }

    # Prepare layout mode configuration
    $layoutMode = @{
        PaneRows = $PaneRows
        PaneCols = $PaneCols
        PanesPerTab = $PanesPerTab
        Windows = $Windows.IsPresent
    }

    # Prepare options
    $options = @{
        DryRun = $false
        Delay = $Delay
    }

    # Determine which terminal provider to use
    $preferredTerminal = Get-PreferredTerminal -Requested $Terminal

    # Dispatch to appropriate provider
    $spawned = switch ($preferredTerminal) {
        "wave" {
            Spawn-WaveTerminalSessions -Items $launchItems -LayoutMode $layoutMode -Options $options
        }
        "windowsterminal" {
            Spawn-WindowsTerminalSessions -Items $launchItems -LayoutMode $layoutMode -Options $options
        }
        "cmd" {
            Spawn-CmdSessions -Items $launchItems -Options $options
        }
        default {
            Write-Warning "Unknown terminal: $preferredTerminal"
            0
        }
    }

    return $spawned
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
