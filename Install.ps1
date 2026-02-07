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

Write-Host "  [OK] Scripts -> $ScriptDir (UTF-8 with BOM)" -ForegroundColor Green

# ── 3. Create session storage ────────────────────────────────────────────────
$sessDir = Join-Path $env:USERPROFILE ".claude-sessions"
New-Item -ItemType Directory -Force -Path $sessDir | Out-Null
Write-Host "  [OK] Session storage -> $sessDir" -ForegroundColor Green

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
Write-Host "  Usage:" -ForegroundColor White
Write-Host "    Inside Claude Code:  /goodnight           Save session + register it" -ForegroundColor DarkGray
Write-Host "    Inside Claude Code:  /goodmorning         Load session in current window" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-goodmorning   Spawn ALL active sessions" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-goodmorning -Panes `"2x4`"  Grid layout" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-sessions      List registered sessions" -ForegroundColor DarkGray
Write-Host "    In PowerShell:       claude-launch        Launch fresh sessions" -ForegroundColor DarkGray
Write-Host "    Either script:       -Help                Show all options" -ForegroundColor DarkGray
Write-Host ""
