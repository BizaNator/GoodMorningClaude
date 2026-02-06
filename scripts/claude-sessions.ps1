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
    [switch]$Open
)

$SessionDir   = Join-Path $env:USERPROFILE ".claude-sessions"
$RegistryFile = Join-Path $SessionDir "session-registry.json"

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
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host "    claude-sessions" -NoNewline -ForegroundColor Cyan
    Write-Host "              List active sessions" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -All" -NoNewline -ForegroundColor Cyan
    Write-Host "          Show all including done" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -Done " -NoNewline -ForegroundColor Cyan
    Write-Host "<name>" -NoNewline -ForegroundColor White
    Write-Host "   Mark a project as done (remove from registry)" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -Remove " -NoNewline -ForegroundColor Cyan
    Write-Host "<#>" -NoNewline -ForegroundColor White
    Write-Host "     Remove entry by number" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -Clean" -NoNewline -ForegroundColor Cyan
    Write-Host "        Remove entries with missing files" -ForegroundColor DarkGray
    Write-Host "    claude-sessions -Open" -NoNewline -ForegroundColor Cyan
    Write-Host "         Open sessions folder in Explorer" -ForegroundColor DarkGray
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
    $exists = if (Test-Path $s.resumePath) { "" } else { " [FILE MISSING]" }

    Write-Host "  [$i] " -NoNewline -ForegroundColor White
    Write-Host "$($s.sessionName)" -NoNewline -ForegroundColor Cyan
    Write-Host "  $($s.status)$exists" -ForegroundColor $color
    Write-Host "      $($s.projectPath)" -ForegroundColor DarkGray
    Write-Host "      Updated: $($s.lastUpdated)" -ForegroundColor DarkGray
}

Write-Host ""
