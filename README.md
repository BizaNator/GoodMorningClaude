# ☀️ Good Morning, Claude

**One command reopens all of yesterday's work.** Persist and resume Claude Code sessions across restarts -- save all your active sessions at end of day, reopen them all in the morning with full context.

Supports tabs, panes, grid layouts, separate windows, and remote SSH sessions. Tab mode by default lets you drag windows out if you want :)

![image-20260206122939923](README.assets/image-20260206122939923.png)

```
claude-goodmorning
```

![image-20260206123147119](README.assets/image-20260206123147119.png) Window mode shown above - use "claude-goodmorning -w"

**🧠 BrainDeadGuild**

*Don't Be BrAIn Dead Alone*

*🎮 Games | 🤖 AI | 👥 Community*

[![BrainDeadGuild](https://img.shields.io/badge/BrainDeadGuild-Community-purple.svg)](https://braindeadguild.com/discord) [![BrainDead.TV](https://img.shields.io/badge/BrainDead.TV-Lore-red.svg)](https://braindead.tv/)

## 🎯 About BrainDeadGuild

**BrainDeadGuild** started in 2008 as a gaming community and evolved into a collaboration of gamers, streamers, AI creators, and game developers. We're focused on:

- 🎮 **Game Development** -- UEFN / Fortnite projects
- 🧠 **AI-Assisted Creation** -- tools and workflows
- 📺 **BrainDead.TV** -- shared lore, characters, and worlds (including the City of Brains universe)

The tools we release (like this one) are built for our own game and content pipelines, then shared openly when they're useful to others.

## ⚙️ How It Works

```
End of day:                          Next morning:
+-----------------------+            +------------------------+
| Claude Code (Proj A)  |--/goodnight-->|                        |
| Claude Code (Proj B)  |--/goodnight-->|  session-registry.json |
| Claude Code (SSH: C)  |--/goodnight-->|  (central manifest)    |
+-----------------------+            +------------+-----------+
                                                  |
                                       claude-goodmorning
                                                  |
                                     +------------v-----------+
                                     | WT Tab: Proj A + ctx   |
                                     | WT Tab: Proj B + ctx   |
                                     | WT Tab: SSH -> C + ctx |
                                     +------------------------+
```

## 📦 Install

```powershell
git clone https://github.com/BizaNator/GoodMorningClaude.git
cd GoodMorningClaude
.\Install.ps1
```

The installer handles:
- 📝 `/goodnight` and `/goodmorning` slash commands -> `~\.claude\commands\`
- 📜 `claude-goodmorning.ps1` and `claude-sessions.ps1` -> `~\.local\bin\` (or custom path)
- 📁 Creates `~\.claude-sessions\` storage directory
- 🔤 Adds UTF-8 BOM to scripts (required for PowerShell 5.1)
- 🔓 Sets ExecutionPolicy to RemoteSigned if needed
- 🛡️ Removes Zone.Identifier from downloaded files (Unblock-File)
- 📍 Adds script directory to PATH if needed
- 🎨 Optionally installs Windows Terminal color schemes and profile

### 🔧 Troubleshooting

**"File cannot be loaded... not digitally signed"**
Scripts downloaded from the internet get a Zone.Identifier that blocks execution under RemoteSigned policy. The installer runs `Unblock-File` automatically. If you hit this manually:
```powershell
Unblock-File ~\.local\bin\claude-goodmorning.ps1
Unblock-File ~\.local\bin\claude-sessions.ps1
```

**"The string is missing the terminator" or other parse errors**
PowerShell 5.1 reads `.ps1` files as Windows-1252 unless they have a UTF-8 BOM. Non-ASCII characters (em dashes, box drawing) get silently corrupted into smart quotes, breaking the parser. The installer adds a BOM automatically. If you copy scripts manually, ensure they have a UTF-8 BOM.

**"Raw mode is not supported" from Claude Code**
This happens if you pipe content into `claude` (e.g., `$content | claude`). Claude Code needs a real TTY for its interactive UI. The goodmorning script avoids this by using a `.cmd` launcher and passing `/goodmorning <path>` as the initial prompt instead of piping.

## 🚀 Usage

### 📋 Use -help for a list of all commands

![image-20260206122745143](README.assets/image-20260206122745143.png)

### 🌙 End of Day -- Save Sessions

Inside each Claude Code session:

```
/goodnight                        # Save session with auto-detected context
/goodnight focusing on auth bug   # Add a note for tomorrow
```

This creates a structured markdown file in `~\.claude-sessions\` and registers the session in `session-registry.json`. Works for both local and SSH sessions -- the host is recorded automatically.

### ☀️ Next Morning -- Resume Everything

From PowerShell:

```powershell
claude-goodmorning                # Spawn ALL active sessions as WT tabs
claude-goodmorning -List          # See what's registered without spawning
claude-goodmorning -Pick          # Interactive: choose which to spawn
claude-goodmorning -DryRun        # Preview what would happen
claude-goodmorning -Session "C:\...\.claude-sessions\2026-02-05_myproject.md"
claude-goodmorning -Open          # Open sessions folder in Explorer
claude-goodmorning -Help          # Full usage info
```

Options:

```powershell
claude-goodmorning -Panes "2x4"   # 2-row x 4-column grid layout
claude-goodmorning -Panes 4       # 4 side-by-side columns (1 row)
claude-goodmorning -Windows       # Separate windows instead of tabs
claude-goodmorning -Delay 5       # 5 second pause between spawns
claude-goodmorning -NoSkipPermissions  # Don't pass --dangerously-skip-permissions
```

Each session opens in a new Windows Terminal tab/pane with:
- 📂 Correct working directory (local) or SSH connection (remote)
- 💬 `/goodmorning` command auto-sent as first message to load context
- ⚡ `--dangerously-skip-permissions` (disable with `-NoSkipPermissions`)
- 🎨 Unique color scheme per pane for visual identification
- 🏷️ Pane title showing session name (`--suppressApplicationTitle`)

### 📋 Manage Sessions

```powershell
claude-sessions                   # List active sessions
claude-sessions -All              # Show all including done
claude-sessions -Done "myproject" # Remove a project from registry
claude-sessions -Remove 2         # Remove entry #2
claude-sessions -Clean            # Remove entries with missing files
claude-sessions -Open             # Open sessions folder in Explorer
claude-sessions -Help             # Full usage info
```

### 🔄 Inside a Running Session

If you opened Claude Code manually (not via `claude-goodmorning`):

```
/goodmorning                      # Load context for current project
/goodmorning C:\path\to\session.md  # Load a specific session file
```

## 🚀 Launch Fresh Sessions

Need to spin up a batch of fresh Claude Code instances without any saved session context? Use `claude-launch` to open multiple tabs/panes targeting local or remote paths.

### 🎯 Basic Usage

```powershell
# Target strings: "user@host:/path xN"
claude-launch "home@brainz:/opt/ai-server-config x2" "home@brainz:/opt/game-server-config x2" -Panes "2x2"

# Single-target shorthand
claude-launch -Host "home@brainz" -Path "/opt/ai-server-config" -Count 4 -Panes "2x2"

# Local targets
claude-launch -Path "C:\tools\myproject" -Count 2 -Panes "1x2"

# Terminal only (no Claude)
claude-launch -Path "C:\tools" -NoClaude

# Dry run preview
claude-launch -DryRun -Path "C:\tools" -Count 2 -Panes "1x2"
```

### 📝 Target String Format

Three ways to specify targets:

**1. Positional target strings** -- Most flexible:
```
"user@host:/path xN"   # Remote SSH (@ distinguishes from C:\ drive letters)
"C:\local\path xN"      # Local path
```
The `xN` suffix is optional (defaults to `x1`). Examples:
```powershell
claude-launch "home@brainz:/opt/config x2" "C:\tools\myproject"
```

**2. Single-target shorthand** -- Named parameters for one target:
```powershell
claude-launch -Host "home@brainz" -Path "/opt/config" -Count 4 -Label "Config"
claude-launch -Path "C:\tools" -Count 2
```

**3. Profiles** -- Saved configurations (see below).

### 📋 Profiles

Save frequently-used launch configurations to `~\.claude-sessions\launch-profiles.json`:

```powershell
# Save a profile
claude-launch -SaveProfile "brainz-servers" "home@brainz:/opt/ai-server-config x2" "home@brainz:/opt/game-server-config x2" -Panes "2x2"

# Launch from profile
claude-launch -Profile "brainz-servers"

# Manage profiles
claude-launch -ListProfiles
claude-launch -DeleteProfile -Profile "brainz-servers"
```

**Profile JSON format:**
```json
{
  "brainz-servers": {
    "description": "Remote server config sessions",
    "panes": "2x2",
    "targets": [
      { "host": "home@brainz", "path": "/opt/ai-server-config", "count": 2, "label": "AI Server" },
      { "host": "home@brainz", "path": "/opt/game-server-config", "count": 2, "label": "Game Server" }
    ]
  }
}
```

### ⚙️ Options

```powershell
# Mode Options
-NoClaude                   # Open terminal only (no Claude Code)
-NoSkipPermissions          # Don't pass --dangerously-skip-permissions to Claude

# Layout Options
-Panes "2x2"                # Grid layout (rows x columns)
-Panes 4                    # Single row, 4 columns
-Windows                    # Separate windows instead of tabs

# Execution Options
-Delay 5                    # Pause between spawns in seconds (default: 3)
-DryRun                     # Preview what would launch without executing
-Help                       # Show full usage information

# Profile Options
-Profile "name"             # Load saved profile
-SaveProfile "name"         # Save current targets as profile
-ListProfiles               # Show all saved profiles
-DeleteProfile -Profile "name"  # Delete a saved profile

# Target Options (single-target shorthand)
-Host "user@hostname"       # SSH host for single target
-Path "C:\path"             # Local or remote path
-Count 4                    # Number of instances (default: 1)
-Label "Name"               # Custom label for pane titles
```

### 🔄 Claude Mode vs NoClaude Mode

**Claude Mode (default):**
- Launches `claude --dangerously-skip-permissions` in each pane
- Remote sessions: `ssh user@host -t "cd '/path' && claude ..."`
- Local sessions: `cd /d "C:\path" && claude ...`

**NoClaude Mode (`-NoClaude`):**
- Opens plain terminal/shell in each pane
- Remote sessions: `ssh user@host -t "cd '/path' && exec $SHELL -l"`
- Local sessions: `cd /d "C:\path" && cmd /k`
- Useful for quick terminal access or manual workflows

## 🔲 Pane Grid Layout

The `-Panes "RxC"` option arranges sessions in a grid within a single Windows Terminal tab:

![image-20260206122631892](README.assets/image-20260206122631892.png)

```
-Panes "2x4" with 8 sessions:
+--------+--------+--------+--------+
| Sess 1 | Sess 2 | Sess 3 | Sess 4 |    (Claude Teal, Purple, Amber, Emerald)
+--------+--------+--------+--------+
| Sess 5 | Sess 6 | Sess 7 | Sess 8 |    (Claude Red, Violet, Cyan, Gold)
+--------+--------+--------+--------+
```

If you have more sessions than fit in one grid, additional tabs are created automatically. Plain `-Panes 4` creates a single row of 4 columns.

![image-20260206122528499](README.assets/image-20260206122528499.png)

## 🎨 Windows Terminal Setup

The installer can optionally configure Windows Terminal with:

**"Claude Session" profile** -- Hidden profile with `suppressApplicationTitle: true` so pane titles stick.

**8 custom color schemes** -- Subtle tinted dark backgrounds for visual identification:

| Scheme | Background | Accent |
|--------|-----------|--------|
| 🟦 Claude Teal | `#0D2830` | `#2D7D9A` |
| 🟪 Claude Purple | `#1A1028` | `#8B5CF6` |
| 🟧 Claude Amber | `#281E0D` | `#D97706` |
| 🟩 Claude Emerald | `#0D2818` | `#059669` |
| 🟥 Claude Red | `#280D0D` | `#DC2626` |
| 💜 Claude Violet | `#1A0D28` | `#7C3AED` |
| 🩵 Claude Cyan | `#0D2228` | `#0891B2` |
| 💛 Claude Gold | `#28200D` | `#CA8A04` |

Each pane gets a different scheme automatically. All schemes share the same VSCode-like foreground palette so code readability is identical.

If you skip the WT setup during install, the scripts still work -- they just won't apply color schemes or custom titles.

## 📁 File Structure

```
%USERPROFILE%\.claude-sessions\
+-- session-registry.json              # Central manifest of all active sessions
+-- launch-profiles.json               # Saved claude-launch configurations
+-- 2026-02-05_bdrp-props-system.md    # Session snapshots (slug-based filenames)
+-- 2026-02-05_brainmon-dashboard.md
+-- 2026-02-06_bdrp-props-system.md    # New save = new file, old one stays as history
```

### 📄 Registry Format

```json
[
  {
    "sessionName": "BDRP -- Props System",
    "sessionSlug": "bdrp-props-system",
    "projectName": "braindeadrp",
    "projectPath": "C:\\P4\\BrainDeadRP",
    "host": "",
    "resumePath": "C:\\Users\\BizaNator\\.claude-sessions\\2026-02-05_bdrp-props-system.md",
    "status": "in-progress",
    "lastUpdated": "2026-02-05T18:30:00"
  },
  {
    "sessionName": "BrainMon -- Dashboard",
    "sessionSlug": "brainmon-dashboard",
    "projectName": "brainmon",
    "projectPath": "/opt/BrainMon",
    "host": "home@brainz",
    "resumePath": "C:\\Users\\BizaNator\\.claude-sessions\\2026-02-05_brainmon-dashboard.md",
    "status": "in-progress",
    "lastUpdated": "2026-02-05T22:00:00"
  }
]
```

Multiple sessions can share the same `projectPath` -- each gets a unique `sessionSlug`. Registry matches on slug, not project name.

### 📝 Session File Format

```markdown
# Session: ProjectName -- 2026-02-05

## Status
in-progress

## Session Name
BiloxiStudios -- Storage Recovery

## Project Path
D:\Projects\BiloxiStudios

## Host
<!-- Only for remote/SSH sessions. Omit for local. -->
home@brainz

## Active Tasks
- Troubleshooting Storage Spaces pool reassembly

## Plan / Next Steps
1. Run diskpart to check sector sizes on all drives
2. Try Import-StoragePool with specific subsystem

## Key Context
- 6 SAS drives moved from failed LSI controller to Dell PERC H730
- Core issue: 512e vs 4Kn sector size mismatch

## Files & Paths
- D:\Projects\BiloxiStudios\docs\storage-recovery-notes.md

## Notes
User wants to preserve all data -- no destructive operations without confirmation.
```

## ✅ Requirements

- Windows 10/11
- PowerShell 5.1+ (UTF-8 BOM handled by installer)
- Claude Code CLI (`claude` on PATH)
- Windows Terminal recommended (falls back to plain cmd windows)
- SSH client (for remote sessions)

## 📜 License

MIT License. See [LICENSE](LICENSE) for details.

---

## 💬 Community & Support

**🧠 Don't Be BrAIn Dead Alone!**

[![Discord](https://img.shields.io/badge/Discord-Join%20Us-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://BrainDeadGuild.com/discord)
[![Website](https://img.shields.io/badge/Website-BrainDeadGuild.com-FF6B6B?style=for-the-badge)](https://BrainDeadGuild.com)

- 💬 **Discord**: [BrainDeadGuild.com/discord](https://BrainDeadGuild.com/discord) - Get help, share creations, suggest features
- 🌐 **Website**: [BrainDeadGuild.com](https://BrainDeadGuild.com)
- 📺 **Lore & Content**: [BrainDead.TV](https://BrainDead.TV)
- 🐙 **GitHub**: [github.com/BrainDeadGuild](https://github.com/BrainDeadGuild)

### 🛠️ Other BrainDead Tools

Check out our other free tools for creators:

| Tool | Description |
|------|-------------|
| [ComfyUI-BrainDead](https://github.com/BizaNator/ComfyUI-BrainDead) | Custom nodes for ComfyUI - character consistency, prompt tools, and more |
| [BrainDeadBlender](https://github.com/BizaNator/BrainDeadBlender) | Blender add-ons for 3D artists and game developers |
| [BrainDeadBackgroundRemover](https://github.com/BizaNator/BrainDeadBackgroundRemover) | Free AI background removal - drag, drop, done |

---

*A [Biloxi Studios Inc.](https://BrainDeadGuild.com) Production*
