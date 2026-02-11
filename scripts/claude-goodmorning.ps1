<#
.SYNOPSIS
    Claude Good Morning -- Spawn Claude Code sessions for all active projects.

.DESCRIPTION
    Reads the session registry (~\.claude-sessions\session-registry.json),
    filters for active sessions (in-progress, blocked, planning), and spawns
    a new Windows Terminal tab for each one with Claude Code pre-loaded
    with the saved session context.

.EXAMPLE
    claude-goodmorning                    # Spawn all active sessions
    claude-goodmorning -List              # Just show what's registered
    claude-goodmorning -Pick              # Interactive picker
    claude-goodmorning -DryRun            # Preview without spawning
    claude-goodmorning -Session "path.md" # Spawn one specific session
#>

[CmdletBinding()]
param(
    [Alias("s")]
    [string]$Session = "",

    [switch]$List,
    [switch]$Pick,
    [switch]$DryRun,
    [switch]$NoSkipPermissions,
    [Alias("h")]
    [switch]$Help,
    [switch]$Open,
    [Alias("w")]
    [switch]$Windows,
    [string]$Panes = "",
    [string]$Terminal = "auto",

    [int]$Delay = 3
)

# ── Config ──────────────────────────────────────────────────────────────────
$SessionDir   = Join-Path $env:USERPROFILE ".claude-sessions"
$RegistryFile = Join-Path $SessionDir "session-registry.json"

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
    Write-Host "  ==============================" -ForegroundColor Yellow
    Write-Host "    Claude Good Morning" -ForegroundColor Yellow
    Write-Host "  ==============================" -ForegroundColor Yellow
    Write-Host ""
}

function Get-ActiveSessions {
    if (-not (Test-Path $RegistryFile)) {
        return @()
    }

    $raw = Get-Content $RegistryFile -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    try {
        $all = $raw | ConvertFrom-Json
        $active = @($all | Where-Object {
            $_.status -in @("in-progress", "blocked", "planning")
        })
        return $active
    }
    catch {
        Write-Warning "Failed to parse registry: $_"
        return @()
    }
}

function Show-Sessions {
    param([array]$Sessions)

    if ($Sessions.Count -eq 0) {
        Write-Host "  No active sessions in registry." -ForegroundColor Gray
        Write-Host "  Use /goodnight inside Claude Code to save a session." -ForegroundColor DarkGray
        return
    }

    $i = 0
    foreach ($s in $Sessions) {
        $tabClr = $TabColors[$i % $TabColors.Count]
        $i++
        $color = switch ($s.status) {
            "in-progress" { "Green" }
            "blocked"     { "Red" }
            "planning"    { "Yellow" }
            default       { "Gray" }
        }

        # Extract created date from filename
        $createdDate = "Unknown"
        if ($s.resumePath -and $s.resumePath -match '(\d{4}-\d{2}-\d{2})_') {
            $createdDate = $Matches[1]
        }

        # Calculate days since last update
        $daysAgo = ""
        if ($s.lastUpdated) {
            try {
                $lastUpdate = [DateTime]::Parse($s.lastUpdated)
                $daysSince = ([DateTime]::Now - $lastUpdate).Days
                if ($daysSince -eq 0) { $daysAgo = " (today)" }
                elseif ($daysSince -eq 1) { $daysAgo = " (yesterday)" }
                else { $daysAgo = " ($daysSince days ago)" }
            } catch { }
        }

        Write-Host "  [$i]" -NoNewline -ForegroundColor White
        Write-Host " $tabClr " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($s.sessionName)" -NoNewline -ForegroundColor Cyan
        Write-Host "  $($s.status)" -ForegroundColor $color
        if ($s.host) {
            Write-Host "      Host: $($s.host)" -ForegroundColor DarkYellow
        }
        Write-Host "      Dir:  $($s.projectPath)" -ForegroundColor DarkGray
        Write-Host "      Created: $createdDate" -NoNewline -ForegroundColor DarkGray
        Write-Host " | Last used: $($s.lastUpdated)$daysAgo" -ForegroundColor DarkGray
        Write-Host "      File: $($s.resumePath)" -ForegroundColor DarkGray

        # Show first next-step from session file
        if (Test-Path $s.resumePath) {
            $content = Get-Content $s.resumePath -Raw
            $m = [regex]::Match($content, '## Plan / Next Steps\r?\n1\.\s*(.+)')
            if ($m.Success) {
                Write-Host "      Next: $($m.Groups[1].Value)" -ForegroundColor DarkYellow
            }
        }
        Write-Host ""
    }
}

function Build-Launcher {
    param(
        [string]$Title,
        [string]$ProjectPath,
        [string]$ResumePath,
        [string]$SshHost = "",
        [string]$TmuxSessionName = ""
    )

    $skipFlag = if ($NoSkipPermissions) { "" } else { "--dangerously-skip-permissions" }
    $initialPrompt = "/goodmorning $ResumePath"
    $launcherFile = Join-Path $env:TEMP "claude-gm-$(New-Guid).cmd"

    if ($SshHost -ne "") {
        # Check if we should use tmux
        if ($TmuxSessionName -ne "") {
            # Check if tmux session exists
            $tmuxExists = Test-TmuxSession -SshHost $SshHost -TmuxName $TmuxSessionName

            if ($tmuxExists) {
                # Attach to existing session
                $launcherContent = @"
@echo off
title $Title
echo.
echo   Good Morning -- $Title [remote: $SshHost]
echo   Attaching to tmux session: $TmuxSessionName...
echo.
ssh $SshHost -t "tmux attach-session -t '$TmuxSessionName'"
"@
            }
            else {
                # Create new tmux session with Claude
                $launcherContent = @"
@echo off
title $Title
echo.
echo   Good Morning -- $Title [remote: $SshHost]
echo   Creating tmux session: $TmuxSessionName...
echo.
ssh $SshHost -t "tmux new-session -s '$TmuxSessionName' -c '$ProjectPath' 'claude $skipFlag \"$initialPrompt\"'"
"@
            }
        }
        else {
            # No tmux - direct SSH
            $launcherContent = @"
@echo off
title $Title
echo.
echo   Good Morning -- $Title [remote: $SshHost]
echo   Connecting to $SshHost...
echo.
ssh $SshHost -t "cd '$ProjectPath' && claude $skipFlag '$initialPrompt'"
"@
        }
    }
    else {
        # Local session - check if Team mode enabled and tmux available
        $teamMode = Get-TeamModeConfig
        $useTmux = ($teamMode -in @("prefer-attach", "auto")) -and (Test-LocalTmuxAvailable)

        if ($useTmux -and $TmuxSessionName -ne "") {
            # Local Team mode with tmux
            $tmuxExists = Test-LocalTmuxSession -TmuxName $TmuxSessionName

            if ($tmuxExists) {
                # Attach to existing local tmux session
                $launcherContent = @"
@echo off
title $Title
echo.
echo   Good Morning -- $Title [Team mode]
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
echo   Good Morning -- $Title [Team mode]
echo   Creating tmux session: $TmuxSessionName...
echo.
tmux new-session -d -s "$TmuxSessionName"
tmux send-keys -t "$TmuxSessionName" "cd /d `"$ProjectPath`"" Enter
tmux send-keys -t "$TmuxSessionName" "claude $skipFlag `"$initialPrompt`"" Enter
tmux attach-session -t "$TmuxSessionName"
"@
            }
        }
        else {
            # Regular local session (no tmux)
            $launcherContent = @"
@echo off
title $Title
cd /d "$ProjectPath"
echo.
echo   Good Morning -- $Title
echo   Loading session context...
echo.
claude $skipFlag "$initialPrompt"
"@
        }
    }
    [System.IO.File]::WriteAllText($launcherFile, $launcherContent, [System.Text.Encoding]::ASCII)
    return $launcherFile
}

function Spawn-Sessions {
    param([array]$Sessions)

    # Build launcher files and session items
    $items = @()
    foreach ($s in $Sessions) {
        $title = $s.sessionName -replace '[^\w\s\-\.\:]', '' | ForEach-Object { $_.Trim() }
        if ([string]::IsNullOrWhiteSpace($title)) { $title = Split-Path $s.projectPath -Leaf }
        $remoteHost = if ($s.host) { $s.host } else { "" }

        if (-not $s.host -and -not (Test-Path $s.projectPath)) {
            Write-Warning "  Skipping '$title' -- path not found: $($s.projectPath)"
            continue
        }

        # Generate tmux session name (for both remote and local Team mode)
        $tmuxName = ""
        $teamMode = Get-TeamModeConfig
        $needsTmux = ($remoteHost -ne "") -or (($teamMode -in @("prefer-attach", "auto")) -and (Test-LocalTmuxAvailable))

        if ($needsTmux) {
            $tmuxName = if ($s.tmuxSessionName) { $s.tmuxSessionName } else { "claude-$($s.sessionSlug)" }
        }

        $launcher = Build-Launcher -Title $title -ProjectPath $s.projectPath -ResumePath $s.resumePath -SshHost $remoteHost -TmuxSessionName $tmuxName

        $items += @{
            Title       = $title
            Launcher    = $launcher
            ProjectPath = $s.projectPath
            SshHost     = $remoteHost
        }
    }

    if ($items.Count -eq 0) { return 0 }

    # Prepare layout mode configuration
    $layoutMode = @{
        PaneRows = $PaneRows
        PaneCols = $PaneCols
        PanesPerTab = $PanesPerTab
        Windows = $Windows.IsPresent
    }

    # Prepare options
    $options = @{
        DryRun = $DryRun.IsPresent
        Delay = $Delay
    }

    # Determine which terminal provider to use
    $preferredTerminal = Get-PreferredTerminal -Requested $Terminal

    # Dispatch to appropriate provider
    $spawned = switch ($preferredTerminal) {
        "wave" {
            Spawn-WaveTerminalSessions -Items $items -LayoutMode $layoutMode -Options $options
        }
        "windowsterminal" {
            Spawn-WindowsTerminalSessions -Items $items -LayoutMode $layoutMode -Options $options
        }
        "cmd" {
            Spawn-CmdSessions -Items $items -Options $options
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

# ── Help ────────────────────────────────────────────────────────────────────
if ($Help) {
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host "    claude-goodmorning" -NoNewline -ForegroundColor Cyan
    Write-Host "                Spawn all active sessions as WT tabs" -ForegroundColor DarkGray
    Write-Host "    claude-goodmorning -List" -NoNewline -ForegroundColor Cyan
    Write-Host "          List registered sessions without spawning" -ForegroundColor DarkGray
    Write-Host "    claude-goodmorning -Pick" -NoNewline -ForegroundColor Cyan
    Write-Host "          Interactive picker -- choose which to spawn" -ForegroundColor DarkGray
    Write-Host "    claude-goodmorning -DryRun" -NoNewline -ForegroundColor Cyan
    Write-Host "        Preview what would happen" -ForegroundColor DarkGray
    Write-Host "    claude-goodmorning -Session" -NoNewline -ForegroundColor Cyan
    Write-Host " <path>  Spawn one specific session file" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor White
    Write-Host "    -NoSkipPermissions" -NoNewline -ForegroundColor Cyan
    Write-Host "      Disable --dangerously-skip-permissions" -ForegroundColor DarkGray
    Write-Host "    -Delay <seconds>" -NoNewline -ForegroundColor Cyan
    Write-Host "        Pause between spawns (default: 3)" -ForegroundColor DarkGray
    Write-Host "    -Panes <RxC>" -NoNewline -ForegroundColor Cyan
    Write-Host "           Grid layout per tab (e.g. -Panes 2x4, -Panes 4)" -ForegroundColor DarkGray
    Write-Host "    -Windows (-w)" -NoNewline -ForegroundColor Cyan
    Write-Host "          Separate windows instead of tabs" -ForegroundColor DarkGray
    Write-Host "    -Open" -NoNewline -ForegroundColor Cyan
    Write-Host "                    Open the sessions folder in Explorer" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Workflow:" -ForegroundColor White
    Write-Host "    1. Inside Claude Code, run /goodnight to save your session" -ForegroundColor DarkGray
    Write-Host "    2. Next day, run claude-goodmorning to resume everything" -ForegroundColor DarkGray
    Write-Host "    3. Use claude-sessions to list/manage registered sessions" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── Open sessions folder ────────────────────────────────────────────────────
if ($Open) {
    if (Test-Path $SessionDir) {
        Start-Process explorer.exe -ArgumentList $SessionDir
        Write-Host "  Opened: $SessionDir" -ForegroundColor Green
    }
    else {
        Write-Host "  Sessions folder not found: $SessionDir" -ForegroundColor Yellow
    }
    Write-Host ""
    exit 0
}

# ── Single session mode ─────────────────────────────────────────────────────
if ($Session -ne "") {
    if (-not (Test-Path $Session)) {
        Write-Host "  ERROR: File not found: $Session" -ForegroundColor Red
        exit 1
    }

    $content = Get-Content $Session -Raw
    $pathMatch = [regex]::Match($content, '## Project Path\r?\n(.+)')
    $nameMatch = [regex]::Match($content, '## Session Name\r?\n(.+)')

    $projPath = if ($pathMatch.Success) { $pathMatch.Groups[1].Value.Trim() } else { (Get-Location).Path }
    $sessName = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { [System.IO.Path]::GetFileNameWithoutExtension($Session) }

    # Wrap as a fake registry entry for Spawn-Sessions
    $singleSession = @([PSCustomObject]@{
        sessionName = $sessName
        projectPath = $projPath
        resumePath  = $Session
        host        = ""
    })
    Spawn-Sessions -Sessions $singleSession | Out-Null
    exit 0
}

# ── Load registry ───────────────────────────────────────────────────────────
$sessions = @(Get-ActiveSessions)

if ($sessions.Count -eq 0) {
    Write-Host "  No active sessions found." -ForegroundColor Gray
    Write-Host "  Use /goodnight inside Claude Code to register sessions." -ForegroundColor DarkGray
    Write-Host "  Run claude-goodmorning -Help for usage info." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── List mode ───────────────────────────────────────────────────────────────
if ($List) {
    Show-Sessions -Sessions $sessions
    exit 0
}

# ── Pick mode (interactive) ─────────────────────────────────────────────────
if ($Pick) {
    Show-Sessions -Sessions $sessions
    Write-Host ""
    Write-Host "  Enter numbers to spawn (e.g., '1', '1,2,3', or 'all'): " -NoNewline -ForegroundColor White
    $input = Read-Host

    if ([string]::IsNullOrWhiteSpace($input)) {
        Write-Host "  No selection made. Exiting." -ForegroundColor Yellow
        exit 0
    }

    if ($input.Trim() -eq 'all') {
        $selected = $sessions
        Write-Host "  Selected: All sessions ($($sessions.Count))" -ForegroundColor Green
    }
    else {
        try {
            $sessionCount = @($sessions).Count
            $indices = $input -split ',' | ForEach-Object {
                $num = $_.Trim()
                if ($num -match '^\d+$') {
                    [int]$num - 1
                }
            } | Where-Object { $_ -is [int] }

            $selected = @($indices | Where-Object { $_ -ge 0 -and $_ -lt $sessionCount } | ForEach-Object { $sessions[$_] })

            if ($selected.Count -gt 0) {
                Write-Host "  Selected: " -NoNewline -ForegroundColor Green
                Write-Host ($selected | ForEach-Object { $_.sessionName }) -join ", " -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "  Invalid input: $_" -ForegroundColor Red
            exit 1
        }
    }

    if ($selected.Count -eq 0) {
        $sessionCount = @($sessions).Count
        Write-Host "  No valid selections. Check your numbers (1-$sessionCount)." -ForegroundColor Yellow
        exit 0
    }

    $sessions = $selected
}

# ── Spawn all ───────────────────────────────────────────────────────────────
Show-Sessions -Sessions $sessions
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor DarkGray
$modeLabel = if ($PaneCols -gt 0) { "${PaneRows}x${PaneCols} grid" } else { "tab" }
Write-Host "  Spawning $($sessions.Count) session(s) in $modeLabel mode..." -ForegroundColor Yellow
Write-Host ""

$spawned = Spawn-Sessions -Sessions $sessions

Write-Host ""
if ($spawned -gt 0) {
    Write-Host "  $spawned session(s) launched. Let's get to work." -ForegroundColor Green
}
else {
    Write-Host "  No sessions could be spawned. Check project paths." -ForegroundColor Yellow
}
Write-Host ""
