# WindowsTerminalProvider.ps1
# Windows Terminal spawning logic extracted from claude-goodmorning and claude-launch

# Tab colors -- distinct hues for easy visual identification
$script:TabColors = @("#2D7D9A", "#8B5CF6", "#D97706", "#059669", "#DC2626", "#7C3AED", "#0891B2", "#CA8A04", "#4F46E5", "#BE185D")

# WT color schemes -- match the custom schemes in Windows Terminal settings
$script:ColorSchemes = @("Claude Teal", "Claude Purple", "Claude Amber", "Claude Emerald", "Claude Red", "Claude Violet", "Claude Cyan", "Claude Gold")

function Spawn-WindowsTerminalSessions {
    <#
    .SYNOPSIS
    Spawn sessions using Windows Terminal (wt.exe)

    .PARAMETER Items
    Array of session items with Title, Launcher, ProjectPath, SshHost properties

    .PARAMETER LayoutMode
    Layout configuration: @{ PaneRows, PaneCols, PanesPerTab, Windows }

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
    $paneRows = if ($LayoutMode.PaneRows) { $LayoutMode.PaneRows } else { 0 }
    $paneCols = if ($LayoutMode.PaneCols) { $LayoutMode.PaneCols } else { 0 }
    $panesPerTab = if ($LayoutMode.PanesPerTab) { $LayoutMode.PanesPerTab } else { 0 }

    if ($Items.Count -eq 0) { return 0 }

    # Check if Windows Terminal is available
    $hasWt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $hasWt) {
        Write-Warning "Windows Terminal (wt.exe) not found - cannot spawn sessions with WT provider"
        return 0
    }

    # Dry run mode
    if ($dryRun) {
        foreach ($item in $Items) {
            Write-Host "  [DRY RUN] " -NoNewline -ForegroundColor Magenta
            Write-Host "$($item.Title)" -NoNewline -ForegroundColor Cyan
            $color = $script:TabColors[$launched % $script:TabColors.Count]
            Write-Host " $color" -ForegroundColor DarkGray
            Remove-Item $item.Launcher -ErrorAction SilentlyContinue
            $launched++
        }
        return $launched
    }

    # ── Grid pane mode: RxC layout per tab ─────────────────────────────
    if ($paneCols -gt 0) {
        $groups = @()
        for ($i = 0; $i -lt $Items.Count; $i += $panesPerTab) {
            $end = [Math]::Min($i + $panesPerTab, $Items.Count)
            $groups += ,@($Items[$i..($end - 1)])
        }

        foreach ($group in $groups) {
            $windowArg = if ($windows) { "-w new" } else { "-w 0" }
            $actualCols = [Math]::Min($paneCols, $group.Count)

            # Helper to build pane args
            function Get-PaneArgs($item, $idx) {
                $scheme = $script:ColorSchemes[$idx % $script:ColorSchemes.Count]
                $dir = if ($item.SshHost -eq "") { "-d `"$($item.ProjectPath)`"" } else { "" }
                return "--title `"$($item.Title)`" --suppressApplicationTitle --colorScheme `"$scheme`" $dir cmd /k `"$($item.Launcher)`""
            }

            # Row 0, Column 0: new-tab
            $first = $group[0]
            $firstColor = $script:TabColors[$launched % $script:TabColors.Count]
            $wtCmd = "$windowArg new-tab --tabColor `"$firstColor`" $(Get-PaneArgs $first 0)"

            # Row 0, Columns 1..cols-1: split-pane -V (vertical columns)
            for ($c = 1; $c -lt $actualCols -and $c -lt $group.Count; $c++) {
                $wtCmd += " ; split-pane -V $(Get-PaneArgs $group[$c] $c)"
            }

            # Additional rows: alternate right-to-left / left-to-right
            for ($r = 1; $r -lt $paneRows; $r++) {
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
            Start-Sleep -Seconds $delay
        }
    }
    # ── Tab mode: one tab per session ────────────────────────────────────
    else {
        $tabIdx = 0
        foreach ($item in $Items) {
            $windowArg = if ($windows) { "-w new" } else { "-w 0" }
            $color = $script:TabColors[$tabIdx % $script:TabColors.Count]
            $colorArg  = "--tabColor `"$color`""
            $scheme    = $script:ColorSchemes[$tabIdx % $script:ColorSchemes.Count]
            $startDir  = if ($item.SshHost -eq "") { "-d `"$($item.ProjectPath)`"" } else { "" }

            $wtArgs = "$windowArg new-tab --title `"$($item.Title)`" --suppressApplicationTitle $colorArg --colorScheme `"$scheme`" $startDir cmd /k `"$($item.Launcher)`""
            Start-Process wt.exe -ArgumentList $wtArgs

            Write-Host "  Spawned: " -NoNewline -ForegroundColor Green
            Write-Host "$($item.Title)" -ForegroundColor Cyan
            $launched++
            $tabIdx++
            Start-Sleep -Seconds $delay
        }
    }

    return $launched
}

# Function is available when dot-sourced
