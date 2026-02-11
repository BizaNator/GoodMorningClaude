# WaveTerminalProvider.ps1
# Wave Terminal integration with connections.json generation and tmux support

function Get-WaveConfigPath {
    <#
    .SYNOPSIS
    Locate Wave Terminal's config directory based on platform
    #>

    if ($IsWindows -or $env:OS -match "Windows") {
        $configDir = Join-Path $env:APPDATA "waveterm\config"
    }
    elseif ($IsMacOS) {
        $configDir = "$env:HOME/Library/Application Support/waveterm/config"
    }
    else {
        # Linux
        $xdgConfig = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { "$env:HOME/.config" }
        $configDir = Join-Path $xdgConfig "waveterm/config"
    }

    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    return $configDir
}

function Generate-TmuxInitScript {
    <#
    .SYNOPSIS
    Create shell-specific tmux auto-attach initscript

    .PARAMETER SessionSlug
    Tmux session name (e.g., "claude-brainmon-dashboard")

    .PARAMETER ShellType
    Shell type: bash, zsh, fish
    #>
    param(
        [string]$SessionSlug,
        [string]$ShellType = "bash"
    )

    if ([string]::IsNullOrWhiteSpace($SessionSlug)) {
        return ""
    }

    # Template that checks for tmux, and if available + not already in tmux, attach or create
    $template = @"
if command -v tmux &>/dev/null; then
  [[ -z "`$TMUX" ]] && (tmux attach -t $SessionSlug || tmux new -s $SessionSlug)
fi
"@

    return $template
}

function Export-WaveConnections {
    <#
    .SYNOPSIS
    Generate Wave Terminal connections.json from registry entries

    .PARAMETER RegistryEntries
    Array of session registry entries with host, sessionSlug, tmuxSessionName

    .RETURNS
    Hashtable representing the connections.json structure
    #>
    param(
        [array]$RegistryEntries
    )

    $connections = @{}

    # Load existing connections.json if it exists
    $waveConfigDir = Get-WaveConfigPath
    $connectionsPath = Join-Path $waveConfigDir "connections.json"

    if (Test-Path $connectionsPath) {
        try {
            $existing = Get-Content $connectionsPath -Raw | ConvertFrom-Json
            # Convert to hashtable
            $existing.PSObject.Properties | ForEach-Object {
                $connections[$_.Name] = @{}
                $_.Value.PSObject.Properties | ForEach-Object {
                    $connections[$($_.Name)][$($_.Name)] = $_.Value
                }
            }
        } catch {
            # If malformed, start fresh (but warn)
            Write-Warning "Existing connections.json is malformed, recreating..."
        }
    }

    # Add/update entries from registry
    foreach ($entry in $RegistryEntries) {
        if ([string]::IsNullOrWhiteSpace($entry.host)) {
            continue  # Skip local sessions
        }

        $hostParts = $entry.host.Split('@')
        if ($hostParts.Count -ne 2) {
            Write-Warning "Invalid host format: $($entry.host) (expected user@hostname)"
            continue
        }

        $user = $hostParts[0]
        $hostname = $hostParts[1]
        $connKey = $entry.host

        # Create connection entry
        $conn = @{
            "ssh:hostname" = $hostname
            "ssh:user" = $user
            "conn:wshenabled" = $true
        }

        # Add tmux initscript if tmux session name is defined
        if ($entry.tmuxSessionName) {
            $bashScript = Generate-TmuxInitScript -SessionSlug $entry.tmuxSessionName -ShellType "bash"
            $conn["cmd:initscript.bash"] = $bashScript
            $conn["cmd:initscript.zsh"] = $bashScript  # Same for zsh
        }

        $connections[$connKey] = $conn
    }

    return $connections
}

function Write-WaveConnections {
    <#
    .SYNOPSIS
    Write connections hashtable to Wave's connections.json

    .PARAMETER Connections
    Hashtable of connections
    #>
    param(
        [hashtable]$Connections
    )

    $waveConfigDir = Get-WaveConfigPath
    $connectionsPath = Join-Path $waveConfigDir "connections.json"

    # Convert to JSON
    $json = $Connections | ConvertTo-Json -Depth 5

    # Write to file
    [System.IO.File]::WriteAllText($connectionsPath, $json, [System.Text.Encoding]::UTF8)

    Write-Host "  Wave connections synced: " -NoNewline -ForegroundColor Green
    Write-Host "$connectionsPath" -ForegroundColor Cyan
}

function Spawn-WaveTerminalSessions {
    <#
    .SYNOPSIS
    Spawn sessions using Wave Terminal

    .DESCRIPTION
    Wave Terminal doesn't support grid panes like Windows Terminal.
    Falls back to tab mode and warns if panes were requested.

    .PARAMETER Items
    Array of session items with Title, Launcher, ProjectPath, SshHost properties

    .PARAMETER LayoutMode
    Layout configuration: @{ PaneRows, PaneCols, Windows }
    Note: Panes are not supported, will fall back to tabs with warning

    .PARAMETER Options
    Additional options: @{ DryRun, Delay }
    #>
    param(
        [array]$Items,
        [hashtable]$LayoutMode,
        [hashtable]$Options
    )

    $launched = 0
    $delay = if ($Options.Delay) { $Options.Delay } else { 3 }
    $dryRun = $Options.DryRun -eq $true
    $windows = $LayoutMode.Windows -eq $true
    $paneCols = if ($LayoutMode.PaneCols) { $LayoutMode.PaneCols } else { 0 }

    if ($Items.Count -eq 0) { return 0 }

    # Check if Wave Terminal is available
    $wavePaths = @(
        "$env:LOCALAPPDATA\Programs\Wave\Wave.exe",
        "$env:ProgramFiles\Wave\Wave.exe",
        (Get-Command wave -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    )

    $wavePath = $null
    foreach ($path in $wavePaths) {
        if ($path -and (Test-Path $path)) {
            $wavePath = $path
            break
        }
    }

    if (-not $wavePath) {
        Write-Warning "Wave Terminal not found - cannot spawn sessions with Wave provider"
        return 0
    }

    # Warn if panes mode was requested (not supported)
    if ($paneCols -gt 0) {
        Write-Host "  Note: Wave Terminal doesn't support grid panes, using tab mode instead" -ForegroundColor Yellow
    }

    # Dry run mode
    if ($dryRun) {
        foreach ($item in $Items) {
            Write-Host "  [DRY RUN] " -NoNewline -ForegroundColor Magenta
            Write-Host "$($item.Title)" -NoNewline -ForegroundColor Cyan
            Write-Host " [wave]" -ForegroundColor DarkGray
            Remove-Item $item.Launcher -ErrorAction SilentlyContinue
            $launched++
        }
        return $launched
    }

    # Wave Terminal spawning - tab mode only
    # For remote sessions, Wave uses the connections.json we generated
    # For local sessions, we need to launch with working directory

    foreach ($item in $Items) {
        if ($item.SshHost -ne "") {
            # Remote session - use Wave's SSH connection
            # Wave will auto-connect using connections.json entry
            # The launcher will SSH in and execute Claude with tmux
            Start-Process $wavePath -ArgumentList "-c `"$($item.SshHost)`""
            Write-Host "  Spawned (Wave SSH): " -NoNewline -ForegroundColor Green
            Write-Host "$($item.Title)" -ForegroundColor Cyan

            # Small delay then execute the launcher via SSH in the Wave terminal
            # (This is a limitation - Wave doesn't have CLI args for executing commands on connect)
            # User will need to manually run the launcher or we rely on tmux initscript
            Write-Host "    (Use tmux initscript or run launcher manually)" -ForegroundColor DarkGray
        }
        else {
            # Local session - spawn Wave with launcher
            $wd = $item.ProjectPath
            Start-Process $wavePath -ArgumentList "-d `"$wd`"" -WorkingDirectory $wd
            Write-Host "  Spawned (Wave local): " -NoNewline -ForegroundColor Green
            Write-Host "$($item.Title)" -ForegroundColor Cyan

            # Note: Wave doesn't support command execution on launch like WT does
            Write-Host "    (Run launcher manually: $($item.Launcher))" -ForegroundColor DarkGray
        }

        $launched++
        Start-Sleep -Seconds $delay
    }

    Write-Host ""
    Write-Host "  Note: Wave Terminal requires manual command execution." -ForegroundColor Yellow
    Write-Host "  For remote sessions with tmux, the initscript will auto-attach." -ForegroundColor Yellow
    Write-Host "  For local sessions, run the launcher commands shown above." -ForegroundColor Yellow

    return $launched
}

# Functions are available when dot-sourced
