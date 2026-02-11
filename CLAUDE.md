# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Good Morning, Claude** is a Windows-based session persistence system for Claude Code CLI. It allows users to save their active Claude Code sessions at end-of-day and restore all of them in the morning with full context using Windows Terminal tabs/panes or separate windows.

The system consists of:
- Two slash commands (`/goodnight`, `/goodmorning`) that Claude Code executes
- Three PowerShell CLI tools (`claude-goodmorning`, `claude-sessions`, `claude-launch`) that users run
- A central registry (`~\.claude-sessions\session-registry.json`) tracking active sessions
- Session markdown files (`~\.claude-sessions\YYYY-MM-DD_slug.md`) containing context snapshots

## Key Architecture Concepts

### Session Identity: sessionSlug vs projectName

**Critical distinction**: Multiple Claude Code sessions can work in the same `projectPath` simultaneously. Each needs a unique identity.

- **sessionSlug**: Primary identifier for a session. Derived from the session name (e.g., "BDRP -- Props System" → "bdrp-props-system"). Must be unique across all active sessions.
- **projectName**: The basename of `projectPath`. Multiple sessions can share the same projectName if working on different aspects of the project.
- **Registry matching**: Always match by `sessionSlug`, NEVER by `projectName`.

When creating or updating sessions, check the registry for existing entries by `sessionSlug` to avoid duplicates. If the slug exists, update it; if not, create new.

### Session File Format

Session files (`.md`) are structured markdown with specific sections that future Claude instances parse:

```markdown
# Session: <SessionName> -- <YYYY-MM-DD>

## Status
<!-- in-progress | blocked | planning | done -->

## Session Name
<!-- Must be unique across all sessions -->

## Project Path
<!-- Full absolute path -->

## Host
<!-- user@hostname for SSH sessions; omit entirely for local -->

## Active Tasks
<!-- Bullet list of current work -->

## Plan / Next Steps
<!-- Numbered priority list -- first item is what to do next -->

## Key Context
<!-- Critical decisions, gotchas, state that fresh Claude needs -->

## Files & Paths
<!-- Key files we were editing/referencing -->

## Notes
<!-- User-provided notes from /goodnight arguments -->
```

The `## Plan / Next Steps` section is critical -- item #1 is what the session resumes with.

### Registry Status Management

The registry (`session-registry.json`) only contains sessions with status `in-progress`, `blocked`, or `planning`. When status is set to `done`, the entry is removed from the registry (the session file remains on disk as history). This keeps `claude-goodmorning` focused on active work.

### Windows Terminal Integration

The system spawns sessions via `wt.exe` with specific features:
- **Pane grid layout**: `-Panes "RxC"` arranges sessions in rows×columns within one tab
- **Tab mode**: Default behavior spawns one tab per session
- **Color schemes**: 8 custom "Claude *" color schemes rotate across panes for visual identification
- **suppressApplicationTitle**: Uses WT profile "Claude Session" to make custom `--title` stick
- **Launchers**: Temporary `.cmd` files in `%TEMP%` wrap the actual command execution

The grid layout uses a specific focus-movement pattern (right-to-left on odd rows, left-to-right on even rows) to build the panes correctly.

### Remote SSH vs Local Sessions

Detection of SSH sessions:
1. Check environment variables `$SSH_CONNECTION` or `$SSH_CLIENT`
2. Record `host` as `user@hostname` format in both session file and registry
3. Launcher commands differ:
   - **SSH**: `ssh user@host -t "cd '/path' && claude ..."`
   - **Local**: `cd /d "C:\path" && claude ..."`

If `host` field exists in registry, spawn uses SSH. If empty string or absent, spawn uses local path.

### Three Launching Modes

1. **claude-goodmorning**: Resumes saved sessions from registry with `/goodmorning <path>` to load context
2. **claude-launch**: Spawns fresh instances (no session context) for quick parallel work. Supports:
   - Target strings: `"user@host:/path xN"`
   - Single-target shorthand: `-Host -Path -Count`
   - Profiles: Saved configurations in `launch-profiles.json`
3. **NoClaude mode**: Opens plain terminals instead of Claude (useful for manual work)

### UTF-8 BOM Requirement

PowerShell 5.1 on Windows reads `.ps1` files as Windows-1252 by default, causing silent corruption of non-ASCII characters (em dashes, box drawing, smart quotes). This breaks the parser.

**Solution**: All `.ps1` scripts MUST have a UTF-8 BOM (bytes `0xEF 0xBB 0xBF`). The installer automatically adds BOMs via `Copy-WithBom()` helper. When editing scripts, preserve the BOM.

### Terminal Provider Architecture

The system uses a pluggable provider pattern to support multiple terminal applications:

#### Provider Structure
```
scripts/terminal-providers/
  ├── TerminalProvider.ps1          # Base interface, terminal detection, tmux helpers
  ├── WindowsTerminalProvider.ps1   # Windows Terminal (wt.exe) spawning
  ├── WaveTerminalProvider.ps1      # Wave Terminal + connections.json generation
  └── CmdFallbackProvider.ps1       # Plain cmd.exe fallback
```

#### Provider Interface
Each provider implements `Spawn-*Sessions()` function:
- **Input**: Items array (Title, Launcher, ProjectPath, SshHost), LayoutMode config, Options hash
- **Output**: Number of sessions spawned
- **Responsibilities**: Terminal detection, launcher execution, window/tab/pane creation

#### Terminal Detection & Selection
1. `Get-TerminalCapabilities()` - Detects available terminals (WT, Wave, cmd)
2. `Get-PreferredTerminal($Requested)` - Determines which to use:
   - Explicit `-Terminal` parameter (highest priority)
   - Per-session preference from registry
   - Global config from `terminal-config.json`
   - Auto-detect fallback chain

#### Dispatch Logic
Both `claude-goodmorning.ps1` and `claude-launch.ps1` use identical provider dispatch:
```powershell
$preferredTerminal = Get-PreferredTerminal -Requested $Terminal
$spawned = switch ($preferredTerminal) {
    "wave" { Spawn-WaveTerminalSessions -Items $items -LayoutMode $layoutMode -Options $options }
    "windowsterminal" { Spawn-WindowsTerminalSessions -Items $items -LayoutMode $layoutMode -Options $options }
    "cmd" { Spawn-CmdSessions -Items $items -Options $options }
}
```

#### Why This Architecture?
- **Extensibility**: Add new terminals by creating a provider (e.g., Alacritty, Kitty)
- **Backward compatibility**: Existing WT workflows unchanged
- **Testing**: Providers can be tested independently
- **Clean separation**: Terminal-specific logic isolated from session management

### Tmux Integration Architecture

Tmux support is **automatic for all remote SSH sessions** with smart detection and graceful fallback.

#### Tmux Session Lifecycle

**1. Detection (during `/goodnight`)**:
```bash
# Check if running in tmux
if [ -n "$TMUX" ]; then
    # Get current session name
    tmux display-message -p '#S'
else
    # Suggest name based on session slug
    echo "claude-$sessionSlug"
fi
```

**2. Storage (session registry)**:
```json
{
  "sessionSlug": "brainmon-dashboard",
  "tmuxSessionName": "claude-brainmon-dashboard",
  "tmuxAttached": false,
  "tmuxLastSeen": "2026-02-08T10:30:00"
}
```

**3. Launcher Generation** (`Build-Launcher` / `Build-LaunchCmd`):
```powershell
if ($TmuxSessionName -ne "") {
    $tmuxExists = Test-TmuxSession -SshHost $SshHost -TmuxName $TmuxSessionName
    if ($tmuxExists) {
        # Attach to existing
        ssh $host -t "tmux attach-session -t '$TmuxName'"
    } else {
        # Create new with Claude
        ssh $host -t "tmux new-session -s '$TmuxName' -c '$Path' 'claude $flags \"$prompt\"'"
    }
}
```

**4. Status Tracking**:
```powershell
claude-sessions -RefreshTmux  # Queries each remote host
# Updates tmuxAttached (true/false) and tmuxLastSeen timestamp
```

#### Tmux Helper Functions (TerminalProvider.ps1)

- `Test-TmuxSession($SshHost, $TmuxName)` - Check if session exists
- `Get-TmuxSessionInfo($SshHost, $TmuxName)` - Get detailed status (attached, created time)
- `Test-RemoteTmuxAvailable($SshHost)` - Check if tmux is installed

#### Naming Strategy

- **Saved sessions**: `claude-<sessionSlug>` (e.g., `claude-bdrp-props-system`)
- **Fresh launches**: `claude-launch-<pathslug>-<instanceNum>` (e.g., `claude-launch-opt-brainmon-1`)
- **Manual override**: If already in tmux during `/goodnight`, uses existing session name

#### Graceful Fallback

1. Check if `tmux` exists on remote: `command -v tmux &>/dev/null`
2. If not found: Fall back to direct SSH (no persistence)
3. User is informed but workflow continues normally

### Wave Terminal Integration

Wave Terminal support adds connection management and tmux initscripts.

#### Connections.json Generation

**Source**: `WaveTerminalProvider.ps1 :: Export-WaveConnections()`

**Process**:
1. Read session registry for entries with `host` field
2. Parse `user@hostname` format
3. Generate connection profile:
```json
{
  "home@brainz": {
    "ssh:hostname": "brainz",
    "ssh:user": "home",
    "cmd:initscript.bash": "if command -v tmux &>/dev/null; then [[ -z \"$TMUX\" ]] && (tmux attach -t claude-brainmon-dashboard || tmux new -s claude-brainmon-dashboard); fi",
    "cmd:initscript.zsh": "[same as bash]",
    "conn:wshenabled": true
  }
}
```

**Merge Strategy**:
- Read existing `connections.json` if present
- Preserve non-Claude connections (other hosts, manual entries)
- Add/update entries from registry
- Write merged result

#### Initscript Template

```bash
if command -v tmux &>/dev/null; then
  [[ -z "$TMUX" ]] && (tmux attach -t SESSIONNAME || tmux new -s SESSIONNAME)
fi
```

**How it works**:
1. Check if tmux is installed
2. Check if not already in tmux (`$TMUX` is unset)
3. Try to attach to named session, or create if doesn't exist

**Result**: When you open a Wave connection, it auto-attaches to your Claude tmux session!

#### Wave Spawning Logic

**Limitation**: Wave CLI doesn't support command execution on launch (yet).

**Workaround**:
- Local sessions: Display launcher command for manual execution
- Remote sessions: Rely on tmux initscript (automatic!)

```powershell
# For remote session
Start-Process $wavePath -ArgumentList "-c `"$($item.SshHost)`""
# Wave connects, initscript runs, tmux attaches, Claude session restored!
```

#### Config Path Detection

Cross-platform:
```powershell
function Get-WaveConfigPath {
    if (Windows) { "$env:APPDATA\waveterm\config" }
    elseif (macOS) { "$HOME/Library/Application Support/waveterm/config" }
    else { "$XDG_CONFIG_HOME/waveterm/config" or "$HOME/.config/waveterm/config" }
}
```

### Interactive Menu System

The `claude-menu.ps1` script provides a TUI for users who prefer menus over CLI flags.

#### Design Philosophy
- **Delegation, not reimplementation** - Menu calls existing scripts, doesn't duplicate logic
- **Configuration persistence** - Saves defaults to `menu-config.json`
- **Discoverability** - Users can explore features without knowing CLI syntax

#### Menu Structure
```
Main Menu
├── [1] Resume saved sessions      → claude-goodmorning -Pick
├── [2] Launch new session(s)      → Launch Sub-Menu
├── [3] Manage sessions            → Manage Sub-Menu
├── [4] Configure defaults         → Config Sub-Menu
└── [5] Exit

Launch Sub-Menu
├── [1] Single local path
├── [2] Single remote path
├── [3] Multiple targets
├── [4] From saved profile
└── [5] Back

Manage Sub-Menu
├── [1] List all sessions          → claude-sessions -All
├── [2] List active only           → claude-sessions
├── [3] Mark session done          → claude-sessions -Done
├── [4] Remove session             → claude-sessions -Remove
├── [5] Clean orphaned             → claude-sessions -Clean
├── [6] Sync Wave connections      → claude-sessions -SyncWave
├── [7] Refresh tmux status        → claude-sessions -RefreshTmux
├── [8] Open sessions folder       → claude-sessions -Open
└── [9] Back

Config Sub-Menu
├── [1] Set default pane layout
├── [2] Set default terminal
├── [3] Toggle windows mode
├── [4] Toggle skip permissions
├── [5] Set launch delay
├── [6] Reset to defaults
└── [7] Back
```

#### Configuration Format
```json
{
  "defaults": {
    "panes": "2x2",
    "windows": false,
    "noSkipPermissions": false,
    "delay": 3,
    "terminal": "auto"
  }
}
```

#### Key Functions
- `Show-MainMenu()` / `Show-LaunchMenu()` / etc. - Display menus
- `Get-MenuChoice($Max)` - Read and validate user input
- `Load-MenuConfig()` / `Save-MenuConfig()` - Persist preferences
- `Write-MenuBanner($Title)` - Consistent UI styling

## Common Development Commands

### Testing the Installation Flow
```powershell
.\Install.ps1                                # Standard install to ~/.local/bin
.\Install.ps1 -ScriptDir "C:\custom\path"   # Custom script location
```

### Testing Session Management
```powershell
# From inside Claude Code:
/goodnight
/goodnight working on auth bug
/goodmorning
/goodmorning C:\path\to\session.md

# From PowerShell:
claude-goodmorning                  # Spawn all active sessions
claude-goodmorning -List            # View registered sessions
claude-goodmorning -Pick            # Interactive picker
claude-goodmorning -DryRun          # Preview without spawning
claude-goodmorning -Panes "2x4"     # Grid layout
claude-goodmorning -Windows         # Separate windows
claude-goodmorning -Terminal wave   # Force Wave Terminal

claude-sessions                     # List active sessions
claude-sessions -All                # Include done sessions
claude-sessions -Clean              # Remove orphaned entries
claude-sessions -Done "project"     # Mark as done (removes from registry)
claude-sessions -Remove 2           # Remove entry #2
claude-sessions -SyncWave           # Generate Wave connections.json
claude-sessions -RefreshTmux        # Check tmux status for remote sessions
claude-sessions -SetTerminal 'slug wave'  # Set per-session terminal

claude-launch -Path "C:\tools" -Count 2 -Panes "1x2"
claude-launch "user@host:/path x4" -Panes "2x2"
claude-launch -SaveProfile "name" <targets...>
claude-launch -Profile "name"
claude-launch -Terminal cmd         # Force cmd.exe

claude-menu                         # Interactive menu system
```

### Manual Testing of Launcher Generation

The launcher `.cmd` files are created in `%TEMP%` and auto-cleaned after 24 hours. To inspect:
```powershell
Get-ChildItem $env:TEMP -Filter "claude-*.cmd" | Sort-Object LastWriteTime
Get-Content "$env:TEMP\claude-gm-<guid>.cmd"
```

## Important Implementation Details

### Handling sessionSlug Collisions
When `/goodnight` runs, first check the registry for existing entries that match the current session. Match by:
1. Same `projectPath` AND working on similar area (check session name similarity)
2. If uncertain, create a NEW unique slug to avoid overwriting unrelated sessions

The goal: Multiple people/sessions can work in same project without colliding.

### Building Pane Grids
The pane layout algorithm in both scripts:
1. First pane: `new-tab` with first item
2. Remaining columns in row 0: `split-pane -V` (vertical split = columns)
3. Additional rows: Alternate direction to maintain focus correctly
   - Odd rows (r=1,3,...): Right-to-left, starting with `split-pane -H` then `move-focus left` repeatedly
   - Even rows (r=2,4,...): Left-to-right, starting with `split-pane -H` then `move-focus right` repeatedly

This ensures focus is in the correct position for each split without manual focus jumps.

### Windows Terminal Color Scheme Names
The scripts reference these exact scheme names (must match WT settings.json):
- "Claude Teal", "Claude Purple", "Claude Amber", "Claude Emerald"
- "Claude Red", "Claude Violet", "Claude Cyan", "Claude Gold"

If WT setup is skipped during install, scripts still work but won't apply color schemes.

### Execution Policy and Zone.Identifier
Scripts downloaded from GitHub get a `Zone.Identifier` alternate data stream that blocks execution under `RemoteSigned` policy. The installer:
1. Checks if ExecutionPolicy is restrictive and offers to set RemoteSigned
2. Runs `Unblock-File` on all scripts to remove Zone.Identifier

Users who manually copy scripts need to unblock them:
```powershell
Unblock-File ~\.local\bin\claude-*.ps1
```

## File Locations

- **Slash commands**: `~\.claude\commands\goodnight.md`, `goodmorning.md`
- **Main scripts**: `~\.local\bin\` (or custom path)
  - `claude-goodmorning.ps1` - Resume saved sessions
  - `claude-sessions.ps1` - Manage session registry
  - `claude-launch.ps1` - Launch fresh sessions
  - `claude-menu.ps1` - Interactive menu system
- **Terminal providers**: `~\.local\bin\terminal-providers\`
  - `TerminalProvider.ps1` - Base interface and tmux helpers
  - `WindowsTerminalProvider.ps1` - Windows Terminal spawning
  - `WaveTerminalProvider.ps1` - Wave Terminal + connections.json
  - `CmdFallbackProvider.ps1` - cmd.exe fallback
- **Session storage**: `~\.claude-sessions\`
  - `session-registry.json` - Central manifest with session metadata
  - `launch-profiles.json` - Saved launch configurations
  - `terminal-config.json` - Global terminal preferences
  - `menu-config.json` - Interactive menu defaults
  - `YYYY-MM-DD_sessionslug.md` - Session snapshots
- **Temp launchers**: `%TEMP%\claude-gm-<guid>.cmd`, `claude-launch-<guid>.cmd`
- **Wave Terminal config**: Platform-dependent
  - Windows: `$env:APPDATA\waveterm\config\connections.json`
  - macOS: `~/Library/Application Support/waveterm/config/connections.json`
  - Linux: `~/.config/waveterm/config/connections.json`

## Key PowerShell Patterns

### Reading/Writing JSON Registry
```powershell
# Read with empty array fallback
$raw = Get-Content $RegistryFile -Raw -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
$registry = @($raw | ConvertFrom-Json)

# Write with proper array handling
$json = $registry | ConvertTo-Json -Depth 5
if ($registry.Count -eq 0) { $json = "[]" }
if ($registry.Count -eq 1) { $json = "[$json]" }  # ConvertTo-Json omits brackets for single item
[System.IO.File]::WriteAllText($file, $json, [System.Text.Encoding]::UTF8)
```

### Detecting SSH Sessions
```powershell
# Inside Claude Code (Bash environment):
if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ]; then
    host="$USER@$(hostname)"
else
    host=""
fi
```

### Windows Terminal Arguments
```powershell
# Proper escaping for wt.exe
$wtArgs = "new-tab --title `"My Title`" --suppressApplicationTitle --tabColor `"#2D7D9A`" --colorScheme `"Claude Teal`" -d `"C:\path`" cmd /k `"launcher.cmd`""
Start-Process wt.exe -ArgumentList $wtArgs
```

## Testing and Debugging

### Verifying Session Registry
```powershell
Get-Content "$env:USERPROFILE\.claude-sessions\session-registry.json" | ConvertFrom-Json | Format-Table sessionSlug,status,projectPath
```

### Testing /goodnight Without Running
Instead of running `/goodnight` in Claude Code, directly invoke the goodnight.md logic by reading it and manually testing the PowerShell operations it would perform.

### Dry Run Testing
Both spawning scripts support `-DryRun` to preview what would happen:
```powershell
claude-goodmorning -DryRun
claude-launch -DryRun -Path "C:\tools" -Count 2
```

## Common Pitfalls

1. **Don't match registry by projectName** - Multiple sessions can share the same project. Always match by `sessionSlug`.

2. **Don't forget UTF-8 BOM** - Editing scripts directly without BOM breaks PowerShell 5.1. Use `Copy-WithBom` pattern or ensure editor adds BOM.

3. **Don't assume single session per project** - Users often work on multiple features/areas in the same codebase simultaneously.

4. **Don't pipe to `claude`** - The "Raw mode is not supported" error happens when content is piped in. Claude Code needs a real TTY. Use launcher `.cmd` files with initial prompt instead.

5. **Don't use -Host parameter name in PowerShell** - It collides with built-in `$Host` variable. Scripts use `$Host2` internally and manually parse `-Host` from arguments.

6. **Session file format must be exact** - `/goodmorning` parses via regex. Missing sections or wrong headers break the resume flow.

## When Modifying Scripts

- Preserve UTF-8 BOM when editing `.ps1` files
- Update both `claude-goodmorning.ps1` and `claude-launch.ps1` if changing launcher generation or pane layout logic (they share similar code)
- Keep `goodnight.md` and `goodmorning.md` slash commands in sync with PowerShell script expectations
- When changing session file format, update both the writer (`goodnight.md`) and reader (`goodmorning.md`, `claude-goodmorning.ps1`)
- Test with both local and SSH sessions (behavior differs significantly)
- Verify `-DryRun` output matches actual spawning behavior
