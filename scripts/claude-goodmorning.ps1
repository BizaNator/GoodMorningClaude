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

    [int]$Delay = 3
)

# ── Config ──────────────────────────────────────────────────────────────────
$SessionDir   = Join-Path $env:USERPROFILE ".claude-sessions"
$RegistryFile = Join-Path $SessionDir "session-registry.json"

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

        Write-Host "  [$i]" -NoNewline -ForegroundColor White
        Write-Host " $tabClr " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($s.sessionName)" -NoNewline -ForegroundColor Cyan
        Write-Host "  $($s.status)" -ForegroundColor $color
        if ($s.host) {
            Write-Host "      Host: $($s.host)" -ForegroundColor DarkYellow
        }
        Write-Host "      Dir:  $($s.projectPath)" -ForegroundColor DarkGray
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
        [string]$SshHost = ""
    )

    $skipFlag = if ($NoSkipPermissions) { "" } else { "--dangerously-skip-permissions" }
    $initialPrompt = "/goodmorning $ResumePath"
    $launcherFile = Join-Path $env:TEMP "claude-gm-$(New-Guid).cmd"

    if ($SshHost -ne "") {
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
    else {
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
    [System.IO.File]::WriteAllText($launcherFile, $launcherContent, [System.Text.Encoding]::ASCII)
    return $launcherFile
}

function Spawn-Sessions {
    param([array]$Sessions)

    $hasWt = Get-Command wt.exe -ErrorAction SilentlyContinue
    $launched = 0

    # Build launcher files for all sessions
    $items = @()
    foreach ($s in $Sessions) {
        $title = $s.sessionName -replace '[^\w\s\-\.\:]', '' | ForEach-Object { $_.Trim() }
        if ([string]::IsNullOrWhiteSpace($title)) { $title = Split-Path $s.projectPath -Leaf }
        $remoteHost = if ($s.host) { $s.host } else { "" }
        $color = $TabColors[$items.Count % $TabColors.Count]

        if (-not $s.host -and -not (Test-Path $s.projectPath)) {
            Write-Warning "  Skipping '$title' -- path not found: $($s.projectPath)"
            continue
        }

        $launcher = Build-Launcher -Title $title -ProjectPath $s.projectPath -ResumePath $s.resumePath -SshHost $remoteHost

        if ($DryRun) {
            Write-Host "  [DRY RUN] " -NoNewline -ForegroundColor Magenta
            Write-Host "$title" -NoNewline -ForegroundColor Cyan
            Write-Host " $color" -ForegroundColor DarkGray
            Remove-Item $launcher -ErrorAction SilentlyContinue
            $launched++
            continue
        }

        $items += @{
            Title       = $title
            Launcher    = $launcher
            Color       = $color
            ProjectPath = $s.projectPath
            SshHost     = $remoteHost
        }
    }

    if ($DryRun) { return $launched }
    if ($items.Count -eq 0) { return 0 }

    if (-not $hasWt) {
        # Fallback: plain cmd windows
        foreach ($item in $items) {
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
        for ($i = 0; $i -lt $items.Count; $i += $PanesPerTab) {
            $end = [Math]::Min($i + $PanesPerTab, $items.Count)
            $groups += ,@($items[$i..($end - 1)])
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
        foreach ($item in $items) {
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
$sessions = Get-ActiveSessions

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
    Write-Host "  Enter numbers to spawn (comma-separated, or 'all'): " -NoNewline -ForegroundColor White
    $input = Read-Host

    if ($input -eq 'all') {
        $selected = $sessions
    }
    else {
        $indices = $input -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
        $selected = @($indices | Where-Object { $_ -ge 0 -and $_ -lt $sessions.Count } | ForEach-Object { $sessions[$_] })
    }

    if ($selected.Count -eq 0) {
        Write-Host "  No valid selections." -ForegroundColor Yellow
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
