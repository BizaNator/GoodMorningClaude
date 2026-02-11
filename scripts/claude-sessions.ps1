<#
.SYNOPSIS
    Manage Claude session registry.

.EXAMPLE
    claude-sessions              # List active sessions
    claude-sessions -All         # Include completed/removed
    claude-sessions -Remove 2    # Remove entry #2 from registry
    claude-sessions -Clean       # Remove entries with missing files
    claude-sessions -Done "proj" # Mark a project as done (removes from registry)
#>

[CmdletBinding()]
param(
    [switch]$All,
    [int]$Remove = 0,
    [switch]$Clean,
    [string]$Done = "",
    [Alias("h")]
    [switch]$Help,
    [switch]$Open,

    # New commands
    [switch]$SyncWave,
    [string]$SetTerminal = "",
    [switch]$RefreshTmux
)

$SessionDir   = Join-Path $env:USERPROFILE ".claude-sessions"
$RegistryFile = Join-Path $SessionDir "session-registry.json"

# Load terminal providers for Wave sync and tmux commands
$providerDir = Join-Path $PSScriptRoot "terminal-providers"
if (Test-Path $providerDir) {
    . (Join-Path $providerDir "TerminalProvider.ps1")
    . (Join-Path $providerDir "WaveTerminalProvider.ps1")
}

function Get-Registry {
    if (-not (Test-Path $RegistryFile)) { return @() }
    $raw = Get-Content $RegistryFile -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    try { return @($raw | ConvertFrom-Json) }
    catch { return @() }
}

function Save-Registry {
    param([array]$Entries)
    $json = $Entries | ConvertTo-Json -Depth 5
    if ($Entries.Count -eq 0) { $json = "[]" }
    if ($Entries.Count -eq 1) { $json = "[$json]" }
    [System.IO.File]::WriteAllText($RegistryFile, $json, [System.Text.Encoding]::UTF8)
}

$registry = Get-Registry

# ── Help ────────────────────────────────────────────────────────────────────
if ($Help) {
    Write-Host ""
    Write-Host "  Claude Sessions -- Manage session registry" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Basic Commands:" -ForegroundColor White
    Write-Host "    claude-sessions" -NoNewline -ForegroundColor Cyan
    Write-Host "                    List active sessions" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -All" -NoNewline -ForegroundColor Cyan
    Write-Host "                Show all including done" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -Done " -NoNewline -ForegroundColor Cyan
    Write-Host "<name>" -NoNewline -ForegroundColor White
    Write-Host "         Mark a project as done (remove from registry)" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -Remove " -NoNewline -ForegroundColor Cyan
    Write-Host "<#>" -NoNewline -ForegroundColor White
    Write-Host "           Remove entry by number" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -Clean" -NoNewline -ForegroundColor Cyan
    Write-Host "              Remove entries with missing files" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -Open" -NoNewline -ForegroundColor Cyan
    Write-Host "               Open sessions folder in Explorer" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Terminal & Tmux Commands:" -ForegroundColor White
    Write-Host "    claude-sessions -SyncWave" -NoNewline -ForegroundColor Cyan
    Write-Host "           Sync remote sessions to Wave Terminal connections.json" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -SetTerminal " -NoNewline -ForegroundColor Cyan
    Write-Host "'slug terminal'" -NoNewline -ForegroundColor White
    Write-Host "  Set per-session terminal preference" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -RefreshTmux" -NoNewline -ForegroundColor Cyan
    Write-Host "       Check tmux session status for all remote sessions" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Storage: $SessionDir" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── Open sessions folder ───────────────────────────────────────────────────
if ($Open) {
    if (Test-Path $SessionDir) {
        Start-Process explorer.exe -ArgumentList $SessionDir
        Write-Host "Opened: $SessionDir" -ForegroundColor Green
    }
    else {
        Write-Host "Sessions folder not found: $SessionDir" -ForegroundColor Yellow
    }
    exit 0
}

# ── Mark done ───────────────────────────────────────────────────────────────
if ($Done -ne "") {
    $match = $registry | Where-Object { $_.projectName -like "*$Done*" }
    if ($match) {
        $registry = @($registry | Where-Object { $_.projectName -notlike "*$Done*" })
        Save-Registry -Entries $registry
        Write-Host "Removed '$($match.sessionName)' from registry." -ForegroundColor Green
    }
    else {
        Write-Host "No matching project found for '$Done'." -ForegroundColor Yellow
    }
    exit 0
}

# ── Clean ───────────────────────────────────────────────────────────────────
if ($Clean) {
    $before = $registry.Count
    $registry = @($registry | Where-Object { Test-Path $_.resumePath })
    $removed = $before - $registry.Count
    Save-Registry -Entries $registry
    Write-Host "Cleaned $removed orphaned entries. $($registry.Count) remaining." -ForegroundColor Green
    exit 0
}

# ── Remove by index ─────────────────────────────────────────────────────────
if ($Remove -gt 0) {
    $idx = $Remove - 1
    if ($idx -ge 0 -and $idx -lt $registry.Count) {
        $name = $registry[$idx].sessionName
        $registry = @($registry | Where-Object { $_ -ne $registry[$idx] })
        Save-Registry -Entries $registry
        Write-Host "Removed '$name' from registry." -ForegroundColor Green
    }
    else {
        Write-Host "Invalid index: $Remove" -ForegroundColor Red
    }
    exit 0
}

# ── Sync Wave Connections ───────────────────────────────────────────────────
if ($SyncWave) {
    Write-Host ""
    Write-Host "  Syncing Wave Terminal Connections..." -ForegroundColor Cyan
    Write-Host ""

    # Get all registry entries with remote hosts
    $remoteEntries = @($registry | Where-Object { $_.host -and $_.host -ne "" })

    if ($remoteEntries.Count -eq 0) {
        Write-Host "  No remote sessions found in registry." -ForegroundColor Yellow
        exit 0
    }

    # Generate connections.json
    try {
        $connections = Export-WaveConnections -RegistryEntries $remoteEntries
        Write-WaveConnections -Connections $connections

        Write-Host ""
        Write-Host "  Synced $($remoteEntries.Count) remote session(s) to Wave Terminal." -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "  Error syncing Wave connections: $_" -ForegroundColor Red
        exit 1
    }

    exit 0
}

# ── Set Terminal Preference ─────────────────────────────────────────────────
if ($SetTerminal -ne "") {
    # Parse: sessionSlug terminal
    $parts = $SetTerminal -split '\s+', 2
    if ($parts.Count -ne 2) {
        Write-Host "Usage: claude-sessions -SetTerminal 'sessionSlug terminal'" -ForegroundColor Yellow
        Write-Host "Example: claude-sessions -SetTerminal 'my-project wave'" -ForegroundColor DarkGray
        exit 1
    }

    $slug = $parts[0]
    $terminal = $parts[1]

    # Validate terminal
    if ($terminal -notin @("wave", "wt", "windowsterminal", "cmd", "auto")) {
        Write-Host "Invalid terminal: $terminal" -ForegroundColor Red
        Write-Host "Valid options: wave, wt, windowsterminal, cmd, auto" -ForegroundColor Yellow
        exit 1
    }

    # Find session by slug
    $match = $registry | Where-Object { $_.sessionSlug -eq $slug }
    if (-not $match) {
        Write-Host "Session not found: $slug" -ForegroundColor Red
        exit 1
    }

    # Update terminal preference
    foreach ($s in $registry) {
        if ($s.sessionSlug -eq $slug) {
            # Add preferredTerminal field if it doesn't exist
            if ($s.PSObject.Properties.Name -notcontains "preferredTerminal") {
                $s | Add-Member -MemberType NoteProperty -Name "preferredTerminal" -Value $terminal
            }
            else {
                $s.preferredTerminal = $terminal
            }
        }
    }

    Save-Registry -Entries $registry
    Write-Host "Set terminal preference for '$slug' to '$terminal'." -ForegroundColor Green
    exit 0
}

# ── Refresh Tmux Status ─────────────────────────────────────────────────────
if ($RefreshTmux) {
    Write-Host ""
    Write-Host "  Refreshing Tmux Session Status..." -ForegroundColor Cyan
    Write-Host ""

    $remoteEntries = @($registry | Where-Object { $_.host -and $_.host -ne "" })

    if ($remoteEntries.Count -eq 0) {
        Write-Host "  No remote sessions found in registry." -ForegroundColor Yellow
        exit 0
    }

    $updated = 0
    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"

    foreach ($s in $registry) {
        if (-not $s.host -or $s.host -eq "") { continue }
        if (-not $s.tmuxSessionName) { continue }

        Write-Host "  Checking $($s.sessionSlug)..." -NoNewline

        $info = Get-TmuxSessionInfo -SshHost $s.host -TmuxName $s.tmuxSessionName

        if ($info) {
            # Update fields
            if ($s.PSObject.Properties.Name -notcontains "tmuxAttached") {
                $s | Add-Member -MemberType NoteProperty -Name "tmuxAttached" -Value $info.Attached
            }
            else {
                $s.tmuxAttached = $info.Attached
            }

            if ($s.PSObject.Properties.Name -notcontains "tmuxLastSeen") {
                $s | Add-Member -MemberType NoteProperty -Name "tmuxLastSeen" -Value $now
            }
            else {
                $s.tmuxLastSeen = $now
            }

            $statusLabel = if ($info.Exists) {
                if ($info.Attached) { "attached" } else { "detached" }
            }
            elseif (-not $info.TmuxAvailable) {
                "tmux not installed"
            }
            else {
                "not found"
            }

            Write-Host " $statusLabel" -ForegroundColor $(if ($info.Exists) { "Green" } else { "Yellow" })
            $updated++
        }
        else {
            Write-Host " error" -ForegroundColor Red
        }
    }

    Save-Registry -Entries $registry

    Write-Host ""
    Write-Host "  Refreshed $updated remote session(s)." -ForegroundColor Green
    Write-Host ""
    exit 0
}

# ── List ────────────────────────────────────────────────────────────────────
$show = if ($All) { $registry } else {
    @($registry | Where-Object { $_.status -in @("in-progress", "blocked", "planning") })
}

if ($show.Count -eq 0) {
    Write-Host "No sessions registered." -ForegroundColor Gray
    Write-Host "Use /goodnight inside Claude Code to save a session. Run claude-sessions -Help for more." -ForegroundColor DarkGray
    exit 0
}

Write-Host ""
Write-Host "  Claude Sessions" -ForegroundColor Cyan
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor DarkGray

$i = 0
foreach ($s in $show) {
    $i++
    $color = switch ($s.status) {
        "in-progress" { "Green" }
        "blocked"     { "Red" }
        "planning"    { "Yellow" }
        "done"        { "DarkGray" }
        default       { "Gray" }
    }
    $exists = if ($s.resumePath -and (Test-Path $s.resumePath)) { "" } elseif (-not $s.resumePath) { " [NO FILE]" } else { " [FILE MISSING]" }

    # Extract created date from filename (e.g., 2026-02-09_session.md → 2026-02-09)
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
        } catch {
            $daysAgo = ""
        }
    }

    Write-Host "  [$i] " -NoNewline -ForegroundColor White
    Write-Host "$($s.sessionName)" -NoNewline -ForegroundColor Cyan
    Write-Host "  $($s.status)$exists" -ForegroundColor $color
    Write-Host "      $($s.projectPath)" -ForegroundColor DarkGray
    Write-Host "      Created: $createdDate" -NoNewline -ForegroundColor DarkGray
    Write-Host " | " -NoNewline -ForegroundColor DarkGray
    Write-Host "Last used: $($s.lastUpdated)$daysAgo" -ForegroundColor DarkGray

    # Show tmux status for remote sessions
    if ($s.host -and $s.tmuxSessionName) {
        $tmuxStatus = if ($s.tmuxAttached) { "attached" } else { "detached" }
        $tmuxColor = if ($s.tmuxAttached) { "Green" } else { "Yellow" }
        Write-Host "      Tmux: $($s.tmuxSessionName) " -NoNewline -ForegroundColor DarkGray
        Write-Host "($tmuxStatus)" -ForegroundColor $tmuxColor
    }
}

Write-Host ""
