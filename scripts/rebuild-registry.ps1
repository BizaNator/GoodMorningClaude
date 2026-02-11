# Rebuild registry from session files
param(
    [string]$DateFilter = "",  # e.g., "2026-02-08" or "2026-02-(08|09)"
    [int]$DaysBack = 7          # Default: last 7 days
)

$SessionDir = "$env:USERPROFILE\.claude-sessions"
$RegistryFile = Join-Path $SessionDir "session-registry.json"

# Get all .md files
$sessionFiles = Get-ChildItem $SessionDir -Filter "*.md" | Where-Object {
    if ($DateFilter) {
        # Use custom date filter regex
        $_.Name -match "^$DateFilter"
    } else {
        # Default: files from last N days
        $cutoffDate = (Get-Date).AddDays(-$DaysBack)
        $_.LastWriteTime -ge $cutoffDate
    }
} | Sort-Object LastWriteTime -Descending

Write-Host ""
Write-Host "  Scanning $($sessionFiles.Count) session file(s)..." -ForegroundColor Yellow
Write-Host ""

$registry = @()

foreach ($file in $sessionFiles) {
    Write-Host "Processing: $($file.Name)" -ForegroundColor Cyan

    $content = Get-Content $file.FullName -Raw

    # Parse session metadata
    $status = "in-progress"
    $sessionName = ""
    $projectPath = ""
    $sshHost = ""
    $tmuxName = ""

    if ($content -match '(?ms)^## Status\s*$\s*(.+?)(?=\s*^##|\z)') { $status = $Matches[1].Trim() }
    if ($content -match '(?ms)^## Session Name\s*$\s*(.+?)(?=\s*^##|\z)') { $sessionName = $Matches[1].Trim() }
    if ($content -match '(?ms)^## Project Path\s*$\s*(.+?)(?=\s*^##|\z)') { $projectPath = $Matches[1].Trim() }
    if ($content -match '(?ms)^## Host\s*$\s*(.+?)(?=\s*^##|\z)') { $sshHost = $Matches[1].Trim() }
    if ($content -match '(?ms)^## Tmux Session\s*$\s*(.+?)(?=\s*^##|\z)') { $tmuxName = $Matches[1].Trim() }

    Write-Host "  DEBUG: status='$status', name='$sessionName', path='$projectPath'" -ForegroundColor DarkGray

    # Derive slug from filename (remove date prefix and .md)
    $sessionSlug = $file.BaseName -replace '^2026-\d{2}-\d{2}_', ''
    $projectName = if ($projectPath) { Split-Path $projectPath -Leaf } else { "Unknown" }

    # Only add active sessions
    $statusOk = $status -in @('in-progress', 'blocked', 'planning')
    $hasName = -not [string]::IsNullOrWhiteSpace($sessionName)
    $hasPath = -not [string]::IsNullOrWhiteSpace($projectPath)

    Write-Host "  DEBUG: statusOk=$statusOk, hasName=$hasName, hasPath=$hasPath" -ForegroundColor DarkGray

    if ($statusOk -and $hasName -and $hasPath) {
        # Use parsed tmux name, or generate default if not found
        $finalTmuxName = if ($tmuxName) {
            $tmuxName
        } elseif ($sshHost) {
            "claude-$sessionSlug"
        } else {
            ""
        }

        $registry += @{
            sessionName = $sessionName
            sessionSlug = $sessionSlug
            projectName = $projectName
            projectPath = $projectPath
            host = $sshHost
            resumePath = $file.FullName
            status = $status
            lastUpdated = $file.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
            tmuxSessionName = $finalTmuxName
            tmuxAttached = $false
            preferredTerminal = "auto"
        }
        Write-Host "  Added: $sessionName ($status)" -ForegroundColor Green
    } else {
        Write-Host "  Skipped: $($file.Name) - status=$status, hasName=$($null -ne $sessionName), hasPath=$($null -ne $projectPath)" -ForegroundColor DarkGray
    }
}

# Write registry
$json = $registry | ConvertTo-Json -Depth 5
if ($registry.Count -eq 0) { $json = "[]" }
if ($registry.Count -eq 1) { $json = "[$json]" }
[System.IO.File]::WriteAllText($RegistryFile, $json, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "  ════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Registry rebuilt with $($registry.Count) sessions!" -ForegroundColor Green
Write-Host "  ════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Run 'claude-sessions' to view them" -ForegroundColor Yellow
Write-Host "  Run 'claude-goodmorning' to resume all" -ForegroundColor Yellow
Write-Host ""
