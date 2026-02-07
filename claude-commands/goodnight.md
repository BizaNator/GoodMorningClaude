Save the current work session and register it for tomorrow's resume routine.

## Steps

1. **Identify project info**:
   - Project name: basename of current working directory
   - Project path: full path of current working directory
   - Host: if connected via SSH (not localhost), record the SSH host (e.g., `home@brainz`). Detect by checking if `$SSH_CONNECTION` or `$SSH_CLIENT` env vars exist, or if the hostname differs from the Windows machine. If local, omit the host field.
   - Date: today's date YYYY-MM-DD
   - Session name: a short descriptive name for THIS session (e.g., "BDRP -- Props System" or "BrainMon -- Dashboard"). Should be unique across sessions even when multiple sessions share the same project directory.
   - Session slug: a filesystem-safe version of the session name, lowercased, spaces/special chars replaced with dashes, max 40 chars (e.g., `bdrp-props-system`)
   - Session file name: `YYYY-MM-DD_<session-slug>.md`

   **IMPORTANT**: When multiple sessions work in the same project directory (or subfolders of the same project), each session MUST get a unique session name and slug. Use the specific area of work (subfolder name, feature name, component name) to differentiate. Never use just the project root basename as the slug when the work is more specific.

2. **Check for existing registry entry**: Before writing, read the session registry. If this Claude session was previously saved (match by checking if the current working directory and general task area match an existing entry), reuse that entry's session slug to update it rather than creating a duplicate. If no match, create a new unique slug.

3. **Create session directory** if needed:
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude-sessions"
   ```

4. **Write the session file** to `%USERPROFILE%\.claude-sessions\YYYY-MM-DD_<session-slug>.md`:

```markdown
# Session: <SessionName> -- <YYYY-MM-DD>

## Status
<!-- one of: in-progress | blocked | planning | done -->
<status>

## Session Name
<!-- Short human-readable name like: "BDRP -- Props System" -->
<!-- Must be unique across sessions, even if same project directory -->
<name>

## Project Path
<full path to the project directory>

## Host
<!-- Only include if this is a remote/SSH session. Omit section entirely for local sessions. -->
<!-- Format: user@hostname (e.g., home@brainz) -->

## Active Tasks
- <bullet list of what we were actively working on>

## Plan / Next Steps
1. <numbered list of what to do next, in priority order>

## Key Context
- <important decisions, state, gotchas, blockers -- things a fresh Claude instance needs>

## Files & Paths
- <list key files we were editing or referencing, with paths>

## Notes
<any user notes from $ARGUMENTS, or other relevant context>
```

5. **Update the session registry** at `%USERPROFILE%\.claude-sessions\session-registry.json`.

Read the existing JSON file or start with an empty array `[]`. The registry is:

```json
[
  {
    "sessionName": "BDRP -- Props System",
    "sessionSlug": "bdrp-props-system",
    "projectName": "braindeadrp",
    "projectPath": "C:\\P4\\bizanator_Eros_bdrp_main_5588\\BrainDeadRP",
    "host": "",
    "resumePath": "C:\\Users\\BizaNator\\.claude-sessions\\2026-02-05_bdrp-props-system.md",
    "status": "in-progress",
    "lastUpdated": "2026-02-05T18:30:00"
  }
]
```

Registry update rules:
- Match on `sessionSlug` (NOT projectName -- multiple sessions can share a project)
- If entry with same slug exists: **update** its resumePath, status, sessionName, host, and lastUpdated
- If no matching slug: **add** new entry
- Set `host` to the SSH user@hostname if remote, or empty string `""` if local
- If status is `done` -> **remove** the entry from the registry (session file stays on disk as history)
- Only `in-progress`, `blocked`, and `planning` entries remain in the registry

6. **Confirm** by showing:
   - Session file location
   - Session slug used (so user can verify uniqueness)
   - Summary of current registry (name + status for each entry)
   - Reminder: _"Run `claude-goodmorning` in PowerShell tomorrow to reopen all sessions."_

Be thorough but concise. A fresh Claude instance will rely on this file to reconstruct full context.

User notes: $ARGUMENTS
