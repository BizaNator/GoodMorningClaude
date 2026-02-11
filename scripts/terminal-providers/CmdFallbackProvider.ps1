# CmdFallbackProvider.ps1
# Plain cmd.exe fallback when no modern terminal is available

function Spawn-CmdSessions {
    <#
    .SYNOPSIS
    Spawn sessions using plain cmd.exe windows

    .PARAMETER Items
    Array of session items with Title, Launcher, ProjectPath, SshHost properties

    .PARAMETER Options
    Additional options: @{ DryRun, Delay }
    #>
    param(
        [array]$Items,
        [hashtable]$Options
    )

    $launched = 0
    $delay = if ($Options.Delay) { $Options.Delay } else { 3 }
    $dryRun = $Options.DryRun -eq $true

    if ($Items.Count -eq 0) { return 0 }

    # Dry run mode
    if ($dryRun) {
        foreach ($item in $Items) {
            Write-Host "  [DRY RUN] " -NoNewline -ForegroundColor Magenta
            Write-Host "$($item.Title)" -NoNewline -ForegroundColor Cyan
            Write-Host " [cmd.exe]" -ForegroundColor DarkGray
            Remove-Item $item.Launcher -ErrorAction SilentlyContinue
            $launched++
        }
        return $launched
    }

    # Spawn plain cmd.exe windows
    foreach ($item in $Items) {
        $wd = if ($item.SshHost -eq "") { $item.ProjectPath } else { $env:USERPROFILE }
        Start-Process cmd.exe -ArgumentList "/k `"$($item.Launcher)`"" -WorkingDirectory $wd
        Write-Host "  Spawned: " -NoNewline -ForegroundColor Green
        Write-Host "$($item.Title)" -ForegroundColor Cyan
        $launched++
        Start-Sleep -Seconds $delay
    }

    return $launched
}

# Function is available when dot-sourced
