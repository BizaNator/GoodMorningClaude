# claude-menu.ps1
# Interactive menu system for Good Morning, Claude

<#
.SYNOPSIS
    Interactive menu for managing Claude Code sessions

.DESCRIPTION
    User-friendly interface for common workflows:
    - Resume saved sessions
    - Launch new sessions
    - Manage existing sessions
    - Configure defaults

.EXAMPLE
    claude-menu
#>

[CmdletBinding()]
param()

# ── Config ──────────────────────────────────────────────────────────────────
$SessionDir   = Join-Path $env:USERPROFILE ".claude-sessions"
$MenuConfigFile = Join-Path $SessionDir "menu-config.json"
$TermConfigFile = Join-Path $SessionDir "terminal-config.json"

# Ensure session directory exists
if (-not (Test-Path $SessionDir)) {
    New-Item -Path $SessionDir -ItemType Directory -Force | Out-Null
}

# ── Configuration ───────────────────────────────────────────────────────────
function Load-MenuConfig {
    $defaults = @{
        panes = ""
        windows = $false
        noSkipPermissions = $false
        delay = 3
        terminal = "auto"
        tmuxMode = "prefer-attach"
    }

    if (Test-Path $MenuConfigFile) {
        try {
            $loaded = Get-Content $MenuConfigFile -Raw | ConvertFrom-Json
            if ($loaded.defaults) {
                if ($loaded.defaults.panes) { $defaults.panes = $loaded.defaults.panes }
                if ($loaded.defaults.PSObject.Properties.Name -contains "windows") { $defaults.windows = $loaded.defaults.windows }
                if ($loaded.defaults.PSObject.Properties.Name -contains "noSkipPermissions") { $defaults.noSkipPermissions = $loaded.defaults.noSkipPermissions }
                if ($loaded.defaults.delay) { $defaults.delay = $loaded.defaults.delay }
                if ($loaded.defaults.terminal) { $defaults.terminal = $loaded.defaults.terminal }
                if ($loaded.defaults.tmuxMode) { $defaults.tmuxMode = $loaded.defaults.tmuxMode }
            }
        } catch {
            # Use defaults if config is malformed
        }
    }

    return $defaults
}

function Save-MenuConfig {
    param([hashtable]$Config)

    $obj = @{
        defaults = @{
            panes = $Config.panes
            windows = $Config.windows
            noSkipPermissions = $Config.noSkipPermissions
            delay = $Config.delay
            terminal = $Config.terminal
            tmuxMode = $Config.tmuxMode
        }
    }

    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($MenuConfigFile, $json, [System.Text.Encoding]::UTF8)
}

# ── UI Helpers ──────────────────────────────────────────────────────────────
function Write-MenuBanner {
    param([string]$Title = "Claude Menu")
    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "    $Title" -ForegroundColor Yellow
    Write-Host "  ═══════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
}

function Get-MenuChoice {
    param(
        [int]$Max,
        [string]$Prompt = "Enter choice"
    )

    Write-Host ""
    Write-Host "  $Prompt (1-$Max): " -NoNewline -ForegroundColor White
    $input = Read-Host

    $choice = 0
    if ([int]::TryParse($input, [ref]$choice)) {
        if ($choice -ge 1 -and $choice -le $Max) {
            return $choice
        }
    }

    return 0
}

function Show-PressKey {
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ── Main Menu ───────────────────────────────────────────────────────────────
function Show-MainMenu {
    Write-MenuBanner -Title "Claude Menu"

    Write-Host "  [1] Resume saved sessions" -ForegroundColor Cyan
    Write-Host "      Load and restore your active Claude sessions" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] Launch new session(s)" -ForegroundColor Cyan
    Write-Host "      Start fresh Claude instances for parallel work" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3] Manage sessions" -ForegroundColor Cyan
    Write-Host "      View, clean, sync, or remove sessions" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [4] Configure defaults" -ForegroundColor Cyan
    Write-Host "      Set preferences for terminal, panes, and behavior" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [5] Exit" -ForegroundColor Cyan
    Write-Host ""
}

# ── Launch Sub-Menu ─────────────────────────────────────────────────────────
function Show-LaunchMenu {
    param([hashtable]$Config)

    while ($true) {
        Write-MenuBanner -Title "Launch New Session(s)"

        Write-Host "  [1] Single local path" -ForegroundColor Cyan
        Write-Host "  [2] Single remote path (SSH)" -ForegroundColor Cyan
        Write-Host "  [3] Multiple targets (advanced)" -ForegroundColor Cyan
        Write-Host "  [4] From saved profile" -ForegroundColor Cyan
        Write-Host "  [5] Back to main menu" -ForegroundColor Cyan

        $choice = Get-MenuChoice -Max 5 -Prompt "Select option"

        switch ($choice) {
            1 {
                # Single local path
                Write-Host ""
                Write-Host "  Enter local path: " -NoNewline -ForegroundColor White
                $path = Read-Host
                Write-Host "  Number of instances (default 1): " -NoNewline -ForegroundColor White
                $countStr = Read-Host
                $count = if ($countStr -eq "") { 1 } else { [int]$countStr }

                $panesArg = if ($Config.panes) { "-Panes '$($Config.panes)'" } else { "" }
                $windowsArg = if ($Config.windows) { "-Windows" } else { "" }
                $terminalArg = if ($Config.terminal -ne "auto") { "-Terminal '$($Config.terminal)'" } else { "" }
                $delayArg = "-Delay $($Config.delay)"

                $cmd = "claude-launch -Path '$path' -Count $count $panesArg $windowsArg $terminalArg $delayArg"
                Write-Host ""
                Write-Host "  Executing: $cmd" -ForegroundColor DarkGray
                Write-Host ""
                Invoke-Expression $cmd
                Show-PressKey
            }
            2 {
                # Single remote path
                Write-Host ""
                Write-Host "  Enter SSH host (user@hostname): " -NoNewline -ForegroundColor White
                $sshHost = Read-Host
                Write-Host "  Enter remote path: " -NoNewline -ForegroundColor White
                $path = Read-Host
                Write-Host "  Number of instances (default 1): " -NoNewline -ForegroundColor White
                $countStr = Read-Host
                $count = if ($countStr -eq "") { 1 } else { [int]$countStr }

                $panesArg = if ($Config.panes) { "-Panes '$($Config.panes)'" } else { "" }
                $windowsArg = if ($Config.windows) { "-Windows" } else { "" }
                $terminalArg = if ($Config.terminal -ne "auto") { "-Terminal '$($Config.terminal)'" } else { "" }
                $delayArg = "-Delay $($Config.delay)"

                $cmd = "claude-launch -Host '$sshHost' -Path '$path' -Count $count $panesArg $windowsArg $terminalArg $delayArg"
                Write-Host ""
                Write-Host "  Executing: $cmd" -ForegroundColor DarkGray
                Write-Host ""
                Invoke-Expression $cmd
                Show-PressKey
            }
            3 {
                # Multiple targets
                Write-Host ""
                Write-Host "  Enter targets (one per line, empty line to finish):" -ForegroundColor White
                Write-Host "  Format: 'user@host:/path xN' or 'C:\path xN'" -ForegroundColor DarkGray
                Write-Host ""

                $targets = @()
                while ($true) {
                    Write-Host "    Target: " -NoNewline -ForegroundColor White
                    $target = Read-Host
                    if ([string]::IsNullOrWhiteSpace($target)) { break }
                    $targets += "'$target'"
                }

                if ($targets.Count -eq 0) {
                    Write-Host ""
                    Write-Host "  No targets provided." -ForegroundColor Yellow
                    Show-PressKey
                    continue
                }

                $panesArg = if ($Config.panes) { "-Panes '$($Config.panes)'" } else { "" }
                $windowsArg = if ($Config.windows) { "-Windows" } else { "" }
                $terminalArg = if ($Config.terminal -ne "auto") { "-Terminal '$($Config.terminal)'" } else { "" }
                $delayArg = "-Delay $($Config.delay)"

                $cmd = "claude-launch $($targets -join ' ') $panesArg $windowsArg $terminalArg $delayArg"
                Write-Host ""
                Write-Host "  Executing: $cmd" -ForegroundColor DarkGray
                Write-Host ""
                Invoke-Expression $cmd
                Show-PressKey
            }
            4 {
                # From profile
                Write-Host ""
                & claude-launch -ListProfiles
                Write-Host ""
                Write-Host "  Enter profile name (or blank to cancel): " -NoNewline -ForegroundColor White
                $profile = Read-Host

                if ([string]::IsNullOrWhiteSpace($profile)) {
                    continue
                }

                $terminalArg = if ($Config.terminal -ne "auto") { "-Terminal '$($Config.terminal)'" } else { "" }
                $cmd = "claude-launch -Profile '$profile' $terminalArg"
                Write-Host ""
                Write-Host "  Executing: $cmd" -ForegroundColor DarkGray
                Write-Host ""
                Invoke-Expression $cmd
                Show-PressKey
            }
            5 {
                return
            }
            default {
                Write-Host "  Invalid choice." -ForegroundColor Red
                Show-PressKey
            }
        }
    }
}

# ── Manage Sub-Menu ─────────────────────────────────────────────────────────
function Show-ManageMenu {
    while ($true) {
        Write-MenuBanner -Title "Manage Sessions"

        Write-Host "  [1] List all sessions" -ForegroundColor Cyan
        Write-Host "  [2] List active only" -ForegroundColor Cyan
        Write-Host "  [3] Mark session done" -ForegroundColor Cyan
        Write-Host "  [4] Remove session" -ForegroundColor Cyan
        Write-Host "  [5] Clean orphaned entries" -ForegroundColor Cyan
        Write-Host "  [6] Sync Wave Terminal connections" -ForegroundColor Cyan
        Write-Host "  [7] Refresh tmux status" -ForegroundColor Cyan
        Write-Host "  [8] Open sessions folder" -ForegroundColor Cyan
        Write-Host "  [9] Install slash commands on remote host" -ForegroundColor Yellow
        Write-Host "  [10] Rebuild registry from session files" -ForegroundColor Yellow
        Write-Host "  [11] Back to main menu" -ForegroundColor Cyan

        $choice = Get-MenuChoice -Max 11 -Prompt "Select option"

        switch ($choice) {
            1 {
                Write-Host ""
                & claude-sessions -All
                Show-PressKey
            }
            2 {
                Write-Host ""
                & claude-sessions
                Show-PressKey
            }
            3 {
                Write-Host ""
                & claude-sessions
                Write-Host ""
                Write-Host "  Enter session name (partial match): " -NoNewline -ForegroundColor White
                $name = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    Write-Host ""
                    & claude-sessions -Done $name
                }
                Show-PressKey
            }
            4 {
                Write-Host ""
                & claude-sessions
                Write-Host ""
                Write-Host "  Enter session number to remove: " -NoNewline -ForegroundColor White
                $numStr = Read-Host
                if ($numStr -match '^\d+$') {
                    Write-Host ""
                    & claude-sessions -Remove ([int]$numStr)
                }
                Show-PressKey
            }
            5 {
                Write-Host ""
                & claude-sessions -Clean
                Show-PressKey
            }
            6 {
                Write-Host ""
                & claude-sessions -SyncWave
                Show-PressKey
            }
            7 {
                Write-Host ""
                & claude-sessions -RefreshTmux
                Show-PressKey
            }
            8 {
                & claude-sessions -Open
                Show-PressKey
            }
            9 {
                # Install slash commands on remote host
                Write-Host ""
                Write-Host "  Enter SSH host (user@hostname): " -NoNewline -ForegroundColor White
                $sshHost = Read-Host

                if (-not [string]::IsNullOrWhiteSpace($sshHost)) {
                    Write-Host ""
                    Write-Host "  Installing slash commands on $sshHost..." -ForegroundColor Cyan
                    Write-Host ""

                    $goodnightFile = "$env:USERPROFILE\.claude\commands\goodnight.md"
                    $goodmorningFile = "$env:USERPROFILE\.claude\commands\goodmorning.md"

                    if (-not (Test-Path $goodnightFile)) {
                        Write-Host "  ERROR: Slash commands not found locally." -ForegroundColor Red
                        Write-Host "  Install Good Morning Claude first." -ForegroundColor Red
                    } else {
                        # Create directory on remote
                        Write-Host "  Creating ~/.claude/commands directory..." -ForegroundColor DarkGray
                        ssh $sshHost "mkdir -p ~/.claude/commands"

                        # Copy files using scp
                        Write-Host "  Copying goodnight.md..." -ForegroundColor DarkGray
                        scp $goodnightFile "${sshHost}:~/.claude/commands/"

                        Write-Host "  Copying goodmorning.md..." -ForegroundColor DarkGray
                        scp $goodmorningFile "${sshHost}:~/.claude/commands/"

                        Write-Host ""
                        Write-Host "  ✓ Slash commands installed on $sshHost" -ForegroundColor Green
                        Write-Host ""
                    }
                }
                Show-PressKey
            }
            10 {
                # Rebuild registry from session files
                Write-Host ""
                Write-Host "  This will scan session .md files and rebuild the registry." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Scan how many days back? (default 7): " -NoNewline -ForegroundColor White
                $daysStr = Read-Host
                $days = if ($daysStr -match '^\d+$') { [int]$daysStr } else { 7 }

                Write-Host ""
                & "$PSScriptRoot\rebuild-registry.ps1" -DaysBack $days
                Show-PressKey
            }
            11 {
                return
            }
            default {
                Write-Host "  Invalid choice." -ForegroundColor Red
                Show-PressKey
            }
        }
    }
}

# ── Config Sub-Menu ─────────────────────────────────────────────────────────
function Show-ConfigMenu {
    param([hashtable]$Config)

    while ($true) {
        Write-MenuBanner -Title "Configure Defaults"

        Write-Host "  Current Settings:" -ForegroundColor White
        Write-Host "    Pane layout: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$(if ($Config.panes) { $Config.panes } else { 'tab mode' })" -ForegroundColor Cyan
        Write-Host "    Terminal: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($Config.terminal)" -ForegroundColor Cyan
        Write-Host "    Team mode (tmux): " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($Config.tmuxMode)" -ForegroundColor Cyan
        Write-Host "    Windows mode: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($Config.windows)" -ForegroundColor Cyan
        Write-Host "    Skip permissions: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$(if ($Config.noSkipPermissions) { 'disabled' } else { 'enabled' })" -ForegroundColor Cyan
        Write-Host "    Launch delay: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($Config.delay)s" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "  [1] Set default pane layout" -ForegroundColor Cyan
        Write-Host "  [2] Set default terminal" -ForegroundColor Cyan
        Write-Host "  [3] Set Claude Team mode (requires tmux)" -ForegroundColor Cyan
        Write-Host "  [4] Toggle windows mode" -ForegroundColor Cyan
        Write-Host "  [5] Toggle skip permissions" -ForegroundColor Cyan
        Write-Host "  [6] Set launch delay" -ForegroundColor Cyan
        Write-Host "  [7] Reset to defaults" -ForegroundColor Cyan
        Write-Host "  [8] Back to main menu" -ForegroundColor Cyan

        $choice = Get-MenuChoice -Max 8 -Prompt "Select option"

        switch ($choice) {
            1 {
                Write-Host ""
                Write-Host "  Enter pane layout (e.g., '2x2', '3x4', or blank for tab mode): " -NoNewline -ForegroundColor White
                $panes = Read-Host
                $Config.panes = $panes
                Save-MenuConfig -Config $Config
                Write-Host "  Pane layout set to: $(if ($panes) { $panes } else { 'tab mode' })" -ForegroundColor Green
                Show-PressKey
            }
            2 {
                Write-Host ""
                Write-Host "  Terminal options: auto, wave, wt (Windows Terminal), cmd" -ForegroundColor DarkGray
                Write-Host "  Enter terminal: " -NoNewline -ForegroundColor White
                $terminal = Read-Host
                if ($terminal -in @("auto", "wave", "wt", "windowsterminal", "cmd")) {
                    $Config.terminal = $terminal
                    Save-MenuConfig -Config $Config
                    Write-Host "  Terminal set to: $terminal" -ForegroundColor Green
                }
                else {
                    Write-Host "  Invalid terminal option." -ForegroundColor Red
                }
                Show-PressKey
            }
            3 {
                Write-Host ""
                Write-Host "  Claude Team Mode options:" -ForegroundColor DarkGray
                Write-Host "    prefer-attach - Enable Team mode (attach to shared sessions) [DEFAULT]" -ForegroundColor Green
                Write-Host "    auto          - Attach if exists, create if not" -ForegroundColor DarkGray
                Write-Host "    always-new    - Always create new sessions (solo mode)" -ForegroundColor DarkGray
                Write-Host "    disabled      - Don't use tmux/Team mode" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  Team mode requires tmux on remote SSH hosts." -ForegroundColor Yellow
                Write-Host "  Enter mode: " -NoNewline -ForegroundColor White
                $tmuxMode = Read-Host
                if ($tmuxMode -in @("auto", "always-new", "prefer-attach", "disabled")) {
                    $Config.tmuxMode = $tmuxMode
                    Save-MenuConfig -Config $Config
                    Write-Host "  Team mode set to: $tmuxMode" -ForegroundColor Green
                }
                else {
                    Write-Host "  Invalid mode option." -ForegroundColor Red
                }
                Show-PressKey
            }
            4 {
                $Config.windows = -not $Config.windows
                Save-MenuConfig -Config $Config
                Write-Host ""
                Write-Host "  Windows mode: $($Config.windows)" -ForegroundColor Green
                Show-PressKey
            }
            5 {
                $Config.noSkipPermissions = -not $Config.noSkipPermissions
                Save-MenuConfig -Config $Config
                Write-Host ""
                Write-Host "  Skip permissions: $(if ($Config.noSkipPermissions) { 'disabled' } else { 'enabled' })" -ForegroundColor Green
                Show-PressKey
            }
            6 {
                Write-Host ""
                Write-Host "  Enter launch delay in seconds (default 3): " -NoNewline -ForegroundColor White
                $delayStr = Read-Host
                if ($delayStr -match '^\d+$') {
                    $Config.delay = [int]$delayStr
                    Save-MenuConfig -Config $Config
                    Write-Host "  Launch delay set to: $($Config.delay)s" -ForegroundColor Green
                }
                else {
                    Write-Host "  Invalid delay value." -ForegroundColor Red
                }
                Show-PressKey
            }
            7 {
                Write-Host ""
                Write-Host "  Reset all settings to defaults? (y/n): " -NoNewline -ForegroundColor Yellow
                $confirm = Read-Host
                if ($confirm -eq "y") {
                    if (Test-Path $MenuConfigFile) {
                        Remove-Item $MenuConfigFile -Force
                    }
                    $Config.panes = ""
                    $Config.windows = $false
                    $Config.noSkipPermissions = $false
                    $Config.delay = 3
                    $Config.terminal = "auto"
                    $Config.tmuxMode = "prefer-attach"
                    Write-Host "  Settings reset to defaults." -ForegroundColor Green
                }
                Show-PressKey
            }
            8 {
                return
            }
            default {
                Write-Host "  Invalid choice." -ForegroundColor Red
                Show-PressKey
            }
        }
    }
}

# ── Main Loop ───────────────────────────────────────────────────────────────
$config = Load-MenuConfig

while ($true) {
    Show-MainMenu
    $choice = Get-MenuChoice -Max 5 -Prompt "Select option"

    switch ($choice) {
        1 {
            # Resume saved sessions
            Write-Host ""
            & claude-goodmorning -Pick
            Show-PressKey
        }
        2 {
            # Launch new sessions
            Show-LaunchMenu -Config $config
            $config = Load-MenuConfig  # Reload in case it was changed
        }
        3 {
            # Manage sessions
            Show-ManageMenu
        }
        4 {
            # Configure defaults
            Show-ConfigMenu -Config $config
            $config = Load-MenuConfig  # Reload config
        }
        5 {
            # Exit
            Write-Host ""
            Write-Host "  Goodbye!" -ForegroundColor Cyan
            Write-Host ""
            exit 0
        }
        default {
            Write-Host "  Invalid choice." -ForegroundColor Red
            Show-PressKey
        }
    }
}
