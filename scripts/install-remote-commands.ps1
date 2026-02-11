#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Install Claude slash commands on remote SSH hosts

.DESCRIPTION
    Copies /goodnight and /goodmorning slash commands to a remote host via SSH.
    Run this once per remote host to enable session persistence.

.EXAMPLE
    install-remote-commands home@brainz
    install-remote-commands user@example.com

.PARAMETER SshHost
    SSH host in user@hostname format
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$SshHost
)

$goodnightFile = "$env:USERPROFILE\.claude\commands\goodnight.md"
$goodmorningFile = "$env:USERPROFILE\.claude\commands\goodmorning.md"

if (-not (Test-Path $goodnightFile)) {
    Write-Host "ERROR: Slash commands not found locally. Install Good Morning Claude first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Installing Claude slash commands on $SshHost..." -ForegroundColor Cyan
Write-Host ""

# Create directory on remote
Write-Host "  Creating ~/.claude/commands directory..." -ForegroundColor DarkGray
ssh $SshHost "mkdir -p ~/.claude/commands"

# Copy files
Write-Host "  Copying goodnight.md..." -ForegroundColor DarkGray
Get-Content $goodnightFile -Raw | ssh $SshHost "cat > ~/.claude/commands/goodnight.md"

Write-Host "  Copying goodmorning.md..." -ForegroundColor DarkGray
Get-Content $goodmorningFile -Raw | ssh $SshHost "cat > ~/.claude/commands/goodmorning.md"

Write-Host ""
Write-Host "  ✓ Slash commands installed on $SshHost" -ForegroundColor Green
Write-Host ""
Write-Host "  You can now use /goodnight and /goodmorning on remote sessions!" -ForegroundColor DarkGray
Write-Host ""
