<#
.SYNOPSIS
    Install Claude Session Manager for Windows.

.DESCRIPTION
    Copies slash commands to ~/.claude/commands/ and PowerShell scripts
    to a location on your PATH. Creates the session storage directory.
    Ensures all scripts have UTF-8 BOM encoding for PowerShell 5.1 compatibility.
#>

[CmdletBinding()]
param(
    [string]$ScriptDir = (Join-Path $env:USERPROFILE ".local\bin")
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

Write-Host ""
Write-Host "  Claude Session Manager -- Installer" -ForegroundColor Cyan
Write-Host "  ====================================" -ForegroundColor Cyan
Write-Host ""

# ── Helper: Copy with UTF-8 BOM ─────────────────────────────────────────────
# Windows PowerShell 5.1 reads scripts as Windows-1252 unless a BOM is present.
# This silently corrupts non-ASCII characters (em dashes, box drawing, etc.)
# and can cause parse errors far from the actual problem. Always add a BOM.
function Copy-WithBom {
    param([string]$Source, [string]$Dest)
    $bytes = [System.IO.File]::ReadAllBytes($Source)
    $bom = [byte[]]@(0xEF, 0xBB, 0xBF)

    # Strip existing BOM if present
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $content = New-Object byte[] ($bytes.Length - 3)
        [Array]::Copy($bytes, 3, $content, 0, $content.Length)
        $bytes = $content
    }

    # Write with BOM
    $stream = [System.IO.File]::Create($Dest)
    $stream.Write($bom, 0, 3)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
}

# ── 1. Slash commands -> ~/.claude/commands/ ─────────────────────────────────
$cmdDest = Join-Path $env:USERPROFILE ".claude\commands"
New-Item -ItemType Directory -Force -Path $cmdDest | Out-Null

Copy-Item (Join-Path $root "claude-commands\goodnight.md")  (Join-Path $cmdDest "goodnight.md")  -Force
Copy-Item (Join-Path $root "claude-commands\goodmorning.md") (Join-Path $cmdDest "goodmorning.md") -Force

Write-Host "  [OK] Slash commands -> $cmdDest" -ForegroundColor Green

# ── 2. PowerShell scripts (with UTF-8 BOM) ──────────────────────────────────
New-Item -ItemType Directory -Force -Path $ScriptDir | Out-Null

Copy-WithBom (Join-Path $root "scripts\claude-goodmorning.ps1") (Join-Path $ScriptDir "claude-goodmorning.ps1")
Copy-WithBom (Join-Path $root "scripts\claude-sessions.ps1")    (Join-Path $ScriptDir "claude-sessions.ps1")
Copy-WithBom (Join-Path $root "scripts\claude-launch.ps1")      (Join-Path $ScriptDir "claude-launch.ps1")
Copy-WithBom (Join-Path $root "scripts\claude-menu.ps1")        (Join-Path $ScriptDir "claude-menu.ps1")

Write-Host "  [OK] Scripts -> $ScriptDir (UTF-8 with BOM)" -ForegroundColor Green

# ── 2.5. Terminal providers (with UTF-8 BOM) ────────────────────────────────
$providerDest = Join-Path $ScriptDir "terminal-providers"
New-Item -ItemType Directory -Force -Path $providerDest | Out-Null

Copy-WithBom (Join-Path $root "scripts\terminal-providers\TerminalProvider.ps1")          (Join-Path $providerDest "TerminalProvider.ps1")
Copy-WithBom (Join-Path $root "scripts\terminal-providers\WindowsTerminalProvider.ps1")  (Join-Path $providerDest "WindowsTerminalProvider.ps1")
Copy-WithBom (Join-Path $root "scripts\terminal-providers\WaveTerminalProvider.ps1")     (Join-Path $providerDest "WaveTerminalProvider.ps1")
Copy-WithBom (Join-Path $root "scripts\terminal-providers\CmdFallbackProvider.ps1")      (Join-Path $providerDest "CmdFallbackProvider.ps1")

Write-Host "  [OK] Terminal providers -> $providerDest" -ForegroundColor Green

# ── 3. Create session storage ────────────────────────────────────────────────
$sessDir = Join-Path $env:USERPROFILE ".claude-sessions"
New-Item -ItemType Directory -Force -Path $sessDir | Out-Null
Write-Host "  [OK] Session storage -> $sessDir" -ForegroundColor Green

# ── 3.5. Create terminal-config.json (if doesn't exist) ─────────────────────
$termConfigPath = Join-Path $sessDir "terminal-config.json"
if (-not (Test-Path $termConfigPath)) {
    $defaultTermConfig = @{
        preferredTerminal = "auto"
        fallbackChain = @("wave", "windowsterminal", "cmd")
        waveEnabled = $true
        wtEnabled = $true
        tmuxAutomatic = $true
    }
    $termConfigJson = $defaultTermConfig | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($termConfigPath, $termConfigJson, [System.Text.Encoding]::UTF8)
    Write-Host "  [OK] Terminal config created -> $termConfigPath" -ForegroundColor Green
}
else {
    Write-Host "  [OK] Terminal config exists (not overwritten)" -ForegroundColor Green
}

# ── 3.7. psmux (terminal multiplexer) ─────────────────────────────────────────
# psmux enables Team mode: Claude Code agent teams spawn in visible panes,
# sessions persist across disconnects, and mouse scrolling works natively.
$psmuxCmd = Get-Command psmux -ErrorAction SilentlyContinue
if (-not $psmuxCmd) {
    $psmuxCmd = Get-Command tmux -ErrorAction SilentlyContinue
}

$psmuxVersion = $null
if ($psmuxCmd) {
    $versionOutput = & $psmuxCmd.Source --version 2>$null
    if ($versionOutput -match '(\d+\.\d+\.\d+)') {
        $psmuxVersion = [version]$Matches[1]
    }
}

# Check latest available version from GitHub
$latestVersion = $null
try {
    $releaseInfo = Invoke-RestMethod "https://api.github.com/repos/marlocarlo/psmux/releases/latest" -TimeoutSec 10
    if ($releaseInfo.tag_name -match '(\d+\.\d+\.\d+)') {
        $latestVersion = [version]$Matches[1]
    }
}
catch {
    Write-Host "  (Could not check latest psmux version from GitHub)" -ForegroundColor DarkGray
}

if (-not $psmuxCmd) {
    Write-Host ""
    Write-Host "  psmux not found. psmux is a Windows terminal multiplexer (tmux for Windows)" -ForegroundColor Yellow
    Write-Host "  that enables Team mode, session persistence, and mouse scrolling." -ForegroundColor Yellow
    if ($latestVersion) {
        Write-Host "  Latest version: $latestVersion" -ForegroundColor Yellow
    }
    Write-Host "  Install psmux? (y/n): " -NoNewline
    $ans = Read-Host
    if ($ans -eq 'y') {
        Write-Host "  Installing psmux from GitHub..." -ForegroundColor Cyan
        try {
            Invoke-Expression (Invoke-RestMethod "https://raw.githubusercontent.com/marlocarlo/psmux/master/scripts/install.ps1")
            Write-Host "  [OK] psmux installed" -ForegroundColor Green
        }
        catch {
            Write-Warning "  Failed to install psmux: $_"
            Write-Host "  You can install manually: irm https://raw.githubusercontent.com/marlocarlo/psmux/master/scripts/install.ps1 | iex" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  Skipped. Team mode and session persistence will not be available." -ForegroundColor DarkGray
    }
}
elseif ($psmuxVersion -and $latestVersion -and $psmuxVersion -lt $latestVersion) {
    Write-Host ""
    Write-Host "  psmux $psmuxVersion installed, but $latestVersion is available." -ForegroundColor Yellow
    Write-Host "  Update psmux? (y/n): " -NoNewline
    $ans = Read-Host
    if ($ans -eq 'y') {
        Write-Host "  Stopping existing psmux processes..." -ForegroundColor Cyan
        Get-Process psmux, pmux, tmux -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        Write-Host "  Updating psmux to $latestVersion..." -ForegroundColor Cyan
        try {
            Invoke-Expression (Invoke-RestMethod "https://raw.githubusercontent.com/marlocarlo/psmux/master/scripts/install.ps1")
            Write-Host "  [OK] psmux updated to $latestVersion" -ForegroundColor Green
        }
        catch {
            Write-Warning "  Failed to update psmux: $_"
        }
    }
    else {
        Write-Host "  Skipped. Current version: $psmuxVersion" -ForegroundColor DarkGray
    }
}
else {
    $upToDate = if ($latestVersion) { "(latest)" } else { "" }
    Write-Host "  [OK] psmux $psmuxVersion $upToDate" -ForegroundColor Green
}

# Deploy psmux config if psmux is installed
$psmuxConfSource = Join-Path $root "scripts\psmux.conf"
if ((Get-Command psmux -ErrorAction SilentlyContinue) -or (Get-Command tmux -ErrorAction SilentlyContinue)) {
    $psmuxConfDest = Join-Path $env:USERPROFILE ".psmux.conf"
    if (Test-Path $psmuxConfSource) {
        Copy-Item $psmuxConfSource $psmuxConfDest -Force
        Write-Host "  [OK] psmux config -> $psmuxConfDest" -ForegroundColor Green
    }

    # Set PSMUX_DIM_PREDICTIONS=0 if not already set
    $currentVal = [Environment]::GetEnvironmentVariable("PSMUX_DIM_PREDICTIONS", "User")
    if ($currentVal -ne "0") {
        [Environment]::SetEnvironmentVariable("PSMUX_DIM_PREDICTIONS", "0", "User")
        $env:PSMUX_DIM_PREDICTIONS = "0"
        Write-Host "  [OK] PSMUX_DIM_PREDICTIONS=0 (env var set)" -ForegroundColor Green
    }
}

# ── 4. Execution policy check ────────────────────────────────────────────────
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -eq "Restricted" -or $policy -eq "AllSigned") {
    Write-Host ""
    Write-Host "  NOTE: ExecutionPolicy is '$policy' -- scripts may be blocked." -ForegroundColor Yellow
    Write-Host "  Set to RemoteSigned? (y/n): " -NoNewline
    $ans = Read-Host
    if ($ans -eq 'y') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host "  [OK] ExecutionPolicy set to RemoteSigned" -ForegroundColor Green
    }
}

# ── 5. Unblock files (in case downloaded from internet) ──────────────────────
Get-ChildItem $ScriptDir -Filter "claude-*.ps1" | Unblock-File -ErrorAction SilentlyContinue
Write-Host "  [OK] Scripts unblocked (Zone.Identifier removed)" -ForegroundColor Green

# ── 6. Check PATH ────────────────────────────────────────────────────────────
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$ScriptDir*") {
    Write-Host ""
    Write-Host "  NOTE: $ScriptDir is not in your PATH." -ForegroundColor Yellow
    Write-Host "  Add it? (y/n): " -NoNewline
    $ans = Read-Host
    if ($ans -eq 'y') {
        [Environment]::SetEnvironmentVariable("PATH", "$userPath;$ScriptDir", "User")
        $env:PATH = "$env:PATH;$ScriptDir"
        Write-Host "  [OK] Added to user PATH" -ForegroundColor Green
    }
    else {
        Write-Host "  Skipped. You can run scripts with full path:" -ForegroundColor DarkGray
        Write-Host "    $ScriptDir\claude-goodmorning.ps1" -ForegroundColor DarkGray
    }
}

# ── 7. Windows Terminal profile + color schemes (optional) ────────────────────
$wtSettingsPaths = @(
    (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
    (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
    (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe\LocalState\settings.json")
)
$wtFound = @($wtSettingsPaths | Where-Object { Test-Path $_ })

if ($wtFound.Count -gt 0) {
    Write-Host ""
    Write-Host "  Windows Terminal detected ($($wtFound.Count) installation(s))." -ForegroundColor White
    Write-Host "  Install 'Claude Session' profile and color schemes? (y/n): " -NoNewline
    $ans = Read-Host
    if ($ans -eq 'y') {
        $claudeProfile = @{
            guid = "{c1a2b3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d}"
            commandline = "cmd.exe"
            name = "Claude Session"
            hidden = $true
            suppressApplicationTitle = $true
            font = @{ face = "Cascadia Mono" }
        }

        $claudeSchemes = @(
            @{ name="Claude Teal"; background="#0D2830"; foreground="#D4D4D4"; cursorColor="#2D7D9A"; selectionBackground="#2D7D9A"; black="#1E1E1E"; red="#F44747"; green="#6A9955"; yellow="#D7BA7D"; blue="#569CD6"; purple="#C586C0"; cyan="#4EC9B0"; white="#D4D4D4"; brightBlack="#808080"; brightRed="#F44747"; brightGreen="#6A9955"; brightYellow="#D7BA7D"; brightBlue="#9CDCFE"; brightPurple="#C586C0"; brightCyan="#4EC9B0"; brightWhite="#FFFFFF" },
            @{ name="Claude Purple"; background="#1A1028"; foreground="#D4D4D4"; cursorColor="#8B5CF6"; selectionBackground="#8B5CF6"; black="#1E1E1E"; red="#F44747"; green="#6A9955"; yellow="#D7BA7D"; blue="#569CD6"; purple="#C586C0"; cyan="#4EC9B0"; white="#D4D4D4"; brightBlack="#808080"; brightRed="#F44747"; brightGreen="#6A9955"; brightYellow="#D7BA7D"; brightBlue="#9CDCFE"; brightPurple="#C586C0"; brightCyan="#4EC9B0"; brightWhite="#FFFFFF" },
            @{ name="Claude Amber"; background="#281E0D"; foreground="#D4D4D4"; cursorColor="#D97706"; selectionBackground="#D97706"; black="#1E1E1E"; red="#F44747"; green="#6A9955"; yellow="#D7BA7D"; blue="#569CD6"; purple="#C586C0"; cyan="#4EC9B0"; white="#D4D4D4"; brightBlack="#808080"; brightRed="#F44747"; brightGreen="#6A9955"; brightYellow="#D7BA7D"; brightBlue="#9CDCFE"; brightPurple="#C586C0"; brightCyan="#4EC9B0"; brightWhite="#FFFFFF" },
            @{ name="Claude Emerald"; background="#0D2818"; foreground="#D4D4D4"; cursorColor="#059669"; selectionBackground="#059669"; black="#1E1E1E"; red="#F44747"; green="#6A9955"; yellow="#D7BA7D"; blue="#569CD6"; purple="#C586C0"; cyan="#4EC9B0"; white="#D4D4D4"; brightBlack="#808080"; brightRed="#F44747"; brightGreen="#6A9955"; brightYellow="#D7BA7D"; brightBlue="#9CDCFE"; brightPurple="#C586C0"; brightCyan="#4EC9B0"; brightWhite="#FFFFFF" },
            @{ name="Claude Red"; background="#280D0D"; foreground="#D4D4D4"; cursorColor="#DC2626"; selectionBackground="#DC2626"; black="#1E1E1E"; red="#F44747"; green="#6A9955"; yellow="#D7BA7D"; blue="#569CD6"; purple="#C586C0"; cyan="#4EC9B0"; white="#D4D4D4"; brightBlack="#808080"; brightRed="#F44747"; brightGreen="#6A9955"; brightYellow="#D7BA7D"; brightBlue="#9CDCFE"; brightPurple="#C586C0"; brightCyan="#4EC9B0"; brightWhite="#FFFFFF" },
            @{ name="Claude Violet"; background="#1A0D28"; foreground="#D4D4D4"; cursorColor="#7C3AED"; selectionBackground="#7C3AED"; black="#1E1E1E"; red="#F44747"; green="#6A9955"; yellow="#D7BA7D"; blue="#569CD6"; purple="#C586C0"; cyan="#4EC9B0"; white="#D4D4D4"; brightBlack="#808080"; brightRed="#F44747"; brightGreen="#6A9955"; brightYellow="#D7BA7D"; brightBlue="#9CDCFE"; brightPurple="#C586C0"; brightCyan="#4EC9B0"; brightWhite="#FFFFFF" },
            @{ name="Claude Cyan"; background="#0D2228"; foreground="#D4D4D4"; cursorColor="#0891B2"; selectionBackground="#0891B2"; black="#1E1E1E"; red="#F44747"; green="#6A9955"; yellow="#D7BA7D"; blue="#569CD6"; purple="#C586C0"; cyan="#4EC9B0"; white="#D4D4D4"; brightBlack="#808080"; brightRed="#F44747"; brightGreen="#6A9955"; brightYellow="#D7BA7D"; brightBlue="#9CDCFE"; brightPurple="#C586C0"; brightCyan="#4EC9B0"; brightWhite="#FFFFFF" },
            @{ name="Claude Gold"; background="#28200D"; foreground="#D4D4D4"; cursorColor="#CA8A04"; selectionBackground="#CA8A04"; black="#1E1E1E"; red="#F44747"; green="#6A9955"; yellow="#D7BA7D"; blue="#569CD6"; purple="#C586C0"; cyan="#4EC9B0"; white="#D4D4D4"; brightBlack="#808080"; brightRed="#F44747"; brightGreen="#6A9955"; brightYellow="#D7BA7D"; brightBlue="#9CDCFE"; brightPurple="#C586C0"; brightCyan="#4EC9B0"; brightWhite="#FFFFFF" }
        )

        foreach ($wtPath in $wtFound) {
            try {
                $wtJson = Get-Content $wtPath -Raw | ConvertFrom-Json

                # Add profile if not already present
                $existing = $wtJson.profiles.list | Where-Object { $_.guid -eq $claudeProfile.guid }
                if (-not $existing) {
                    $profileObj = [PSCustomObject]$claudeProfile
                    $wtJson.profiles.list += $profileObj
                }

                # Add/replace color schemes
                $schemeList = @($wtJson.schemes | Where-Object { $_.name -notlike "Claude *" })
                foreach ($s in $claudeSchemes) { $schemeList += [PSCustomObject]$s }
                $wtJson.schemes = $schemeList

                $wtJson | ConvertTo-Json -Depth 10 | Set-Content $wtPath -Encoding UTF8
                Write-Host "  [OK] WT settings updated: $(Split-Path $wtPath -Parent | Split-Path -Leaf)" -ForegroundColor Green
            }
            catch {
                Write-Warning "  Failed to update $wtPath -- $_"
            }
        }
    }
    else {
        Write-Host "  Skipped. You can add the profile/schemes manually (see README)." -ForegroundColor DarkGray
    }
}

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Quick Start:" -ForegroundColor White
Write-Host "    Inside Claude Code:  /goodnight              Save session + register it" -ForegroundColor DarkGray
Write-Host "    Inside Claude Code:  /goodmorning            Load session in current window" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-menu             Interactive menu (recommended!)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Advanced Commands:" -ForegroundColor White
Write-Host "    In PowerShell:       claude-goodmorning      Spawn ALL active sessions" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-goodmorning -Panes `"2x4`"  Grid layout" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-sessions         List registered sessions" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-sessions -SyncWave  Sync to Wave Terminal" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-launch           Launch fresh sessions" -ForegroundColor DarkGray
Write-Host "    Any script:          -Help                   Show all options" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  New Features:" -ForegroundColor White
Write-Host "    - psmux v3.x: Claude Code agent teams in visible panes" -ForegroundColor DarkGray
Write-Host "    - psmux v3.x: Full mouse support with scrolling" -ForegroundColor DarkGray
Write-Host "    - Wave Terminal support with automatic SSH connections" -ForegroundColor DarkGray
Write-Host "    - Session persistence across disconnects (psmux/tmux)" -ForegroundColor DarkGray
Write-Host "    - Interactive menu system for easy session management" -ForegroundColor DarkGray
Write-Host ""
