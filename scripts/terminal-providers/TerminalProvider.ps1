# TerminalProvider.ps1
# Base interface and common functions for terminal providers

function Get-TerminalCapabilities {
    <#
    .SYNOPSIS
    Detect available terminals and return capabilities hash
    #>

    $caps = @{
        WindowsTerminal = $false
        Wave = $false
        Cmd = $true  # Always available on Windows
        TmuxAvailable = $false  # Will be checked per remote host
    }

    # Check for Windows Terminal
    $wtPath = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wtPath) {
        $caps.WindowsTerminal = $true
    }

    # Check for Wave Terminal
    $wavePaths = @(
        "$env:LOCALAPPDATA\Programs\Wave\Wave.exe",
        "$env:ProgramFiles\Wave\Wave.exe",
        (Get-Command wave -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    )

    foreach ($path in $wavePaths) {
        if ($path -and (Test-Path $path)) {
            $caps.Wave = $true
            break
        }
    }

    return $caps
}

function Get-PreferredTerminal {
    <#
    .SYNOPSIS
    Determine which terminal to use based on config and availability

    .PARAMETER Requested
    Explicitly requested terminal (auto|wave|wt|windowsterminal|cmd)
    #>
    param(
        [string]$Requested = "auto"
    )

    $caps = Get-TerminalCapabilities

    # Load terminal config
    $termConfigPath = Join-Path $env:USERPROFILE ".claude-sessions\terminal-config.json"
    $config = @{
        preferredTerminal = "auto"
        fallbackChain = @("wave", "windowsterminal", "cmd")
    }

    if (Test-Path $termConfigPath) {
        try {
            $loadedConfig = Get-Content $termConfigPath -Raw | ConvertFrom-Json
            if ($loadedConfig.preferredTerminal) { $config.preferredTerminal = $loadedConfig.preferredTerminal }
            if ($loadedConfig.fallbackChain) { $config.fallbackChain = $loadedConfig.fallbackChain }
        } catch {
            # Use defaults if config is malformed
        }
    }

    # If explicitly requested, try that first
    if ($Requested -ne "auto") {
        $normalized = $Requested.ToLower()
        if ($normalized -eq "wt") { $normalized = "windowsterminal" }

        switch ($normalized) {
            "wave" {
                if ($caps.Wave) { return "wave" }
                Write-Host "Wave Terminal requested but not found, falling back..." -ForegroundColor Yellow
            }
            "windowsterminal" {
                if ($caps.WindowsTerminal) { return "windowsterminal" }
                Write-Host "Windows Terminal requested but not found, falling back..." -ForegroundColor Yellow
            }
            "cmd" {
                return "cmd"
            }
        }
    }

    # Use config preference if set
    if ($config.preferredTerminal -ne "auto") {
        $preferred = $config.preferredTerminal.ToLower()
        if ($preferred -eq "wt") { $preferred = "windowsterminal" }

        if ($preferred -eq "wave" -and $caps.Wave) { return "wave" }
        if ($preferred -eq "windowsterminal" -and $caps.WindowsTerminal) { return "windowsterminal" }
        if ($preferred -eq "cmd") { return "cmd" }
    }

    # Auto-detect using fallback chain
    foreach ($terminal in $config.fallbackChain) {
        $normalized = $terminal.ToLower()
        if ($normalized -eq "wt") { $normalized = "windowsterminal" }

        if ($normalized -eq "wave" -and $caps.Wave) { return "wave" }
        if ($normalized -eq "windowsterminal" -and $caps.WindowsTerminal) { return "windowsterminal" }
        if ($normalized -eq "cmd") { return "cmd" }
    }

    # Final fallback
    return "cmd"
}

function Test-TmuxSession {
    <#
    .SYNOPSIS
    Check if a tmux session exists on remote host

    .PARAMETER SshHost
    SSH host in user@hostname format

    .PARAMETER TmuxName
    Tmux session name to check
    #>
    param(
        [string]$SshHost,
        [string]$TmuxName
    )

    if ([string]::IsNullOrWhiteSpace($SshHost) -or [string]::IsNullOrWhiteSpace($TmuxName)) {
        return $false
    }

    try {
        # Check if tmux is available and session exists
        $checkCmd = "command -v tmux &>/dev/null && tmux has-session -t '$TmuxName' 2>/dev/null && echo 'EXISTS' || echo 'NONE'"
        $result = ssh $SshHost $checkCmd 2>$null

        return ($result -eq "EXISTS")
    } catch {
        return $false
    }
}

function Get-TmuxSessionInfo {
    <#
    .SYNOPSIS
    Get tmux session details (attached, created, last activity)

    .PARAMETER SshHost
    SSH host in user@hostname format

    .PARAMETER TmuxName
    Tmux session name
    #>
    param(
        [string]$SshHost,
        [string]$TmuxName
    )

    if ([string]::IsNullOrWhiteSpace($SshHost) -or [string]::IsNullOrWhiteSpace($TmuxName)) {
        return $null
    }

    try {
        # Get session info: attached status, created time, last activity
        $infoCmd = @"
if command -v tmux &>/dev/null; then
    tmux list-sessions -F '#{session_name}|#{session_attached}|#{session_created}|#{session_activity}' 2>/dev/null | grep '^$TmuxName|' || echo 'NOTFOUND'
else
    echo 'NOTMUX'
fi
"@

        $result = ssh $SshHost $infoCmd 2>$null

        if ($result -eq "NOTFOUND") {
            return @{
                Exists = $false
                Attached = $false
                TmuxAvailable = $true
            }
        }

        if ($result -eq "NOTMUX") {
            return @{
                Exists = $false
                Attached = $false
                TmuxAvailable = $false
            }
        }

        # Parse: sessionname|attached|created|activity
        $parts = $result.Split('|')
        if ($parts.Count -ge 4) {
            return @{
                Exists = $true
                Attached = ($parts[1] -ne "0")
                Created = $parts[2]
                LastActivity = $parts[3]
                TmuxAvailable = $true
            }
        }

        return $null
    } catch {
        return $null
    }
}

function Test-RemoteTmuxAvailable {
    <#
    .SYNOPSIS
    Check if tmux is installed on remote host

    .PARAMETER SshHost
    SSH host in user@hostname format
    #>
    param(
        [string]$SshHost
    )

    if ([string]::IsNullOrWhiteSpace($SshHost)) {
        return $false
    }

    try {
        $result = ssh $SshHost "command -v tmux &>/dev/null && echo 'YES' || echo 'NO'" 2>$null
        return ($result -eq "YES")
    } catch {
        return $false
    }
}

function Test-LocalTmuxAvailable {
    <#
    .SYNOPSIS
    Check if tmux (psmux) is installed locally on Windows

    .DESCRIPTION
    Detects psmux or other tmux-compatible implementations on Windows.
    Checks both PATH and common install locations.
    #>

    # Check if tmux is in PATH
    $tmuxCmd = Get-Command tmux -ErrorAction SilentlyContinue
    if ($tmuxCmd) {
        return $true
    }

    # Check common psmux install locations
    $commonPaths = @(
        "$env:LOCALAPPDATA\Programs\psmux\tmux.exe",
        "$env:ProgramFiles\psmux\tmux.exe",
        "$env:ProgramFiles (x86)\psmux\tmux.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $true
        }
    }

    return $false
}

function Test-LocalTmuxSession {
    <#
    .SYNOPSIS
    Check if a tmux session exists locally

    .PARAMETER TmuxName
    Tmux session name to check
    #>
    param(
        [string]$TmuxName
    )

    if ([string]::IsNullOrWhiteSpace($TmuxName)) {
        return $false
    }

    if (-not (Test-LocalTmuxAvailable)) {
        return $false
    }

    try {
        $result = tmux has-session -t $TmuxName 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Get-TeamModeConfig {
    <#
    .SYNOPSIS
    Load Team mode configuration from menu config

    .DESCRIPTION
    Returns the tmuxMode setting (prefer-attach, auto, always-new, disabled)
    #>

    $menuConfigPath = Join-Path $env:USERPROFILE ".claude-sessions\menu-config.json"
    $default = "prefer-attach"

    if (-not (Test-Path $menuConfigPath)) {
        return $default
    }

    try {
        $config = Get-Content $menuConfigPath -Raw | ConvertFrom-Json
        if ($config.defaults.tmuxMode) {
            return $config.defaults.tmuxMode
        }
    } catch {
        # Return default if config is malformed
    }

    return $default
}

# Functions are available when dot-sourced (no Export-ModuleMember needed for scripts)
