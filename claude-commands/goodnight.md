Save the current work session and register it for tomorrow's resume routine.

## Steps

1. **Identify project info**:
   - Project name: basename of current working directory
   - Project path: full path of current working directory
   - Host: if connected via SSH (not localhost), record the SSH host (e.g., `home@brainz`). Detect by checking if `$SSH_CONNECTION` or `$SSH_CLIENT` env vars exist, or if the hostname differs from the Windows machine. If local, omit the host field.
   - Date: today's date YYYY-MM-DD
   - Session file name: `YYYY-MM-DD_projectname.md`

2. **Create session directory** if needed:
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude-sessions"
   ```

3. **Write the session file** to `%USERPROFILE%\.claude-sessions\YYYY-MM-DD_projectname.md`:

```markdown
# Session: <ProjectName> — <YYYY-MM-DD>

## Status
<!-- one of: in-progress | blocked | planning | done -->
<status>

## Session Name
<!-- Short human-readable name like: "BiloxiStudios — Storage Recovery" -->
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
- <important decisions, state, gotchas, blockers — things a fresh Claude instance needs>

## Files & Paths
- <list key files we were editing or referencing, with paths>

## Notes
<any user notes from $ARGUMENTS, or other relevant context>
```

4. **Update the session registry** at `%USERPROFILE%\.claude-sessions\session-registry.json`.

Read the existing JSON file or start with an empty array `[]`. The registry is:

```json
[
  {
    "sessionName": "BiloxiStudios -- Storage Recovery",
    "projectName": "biloxistudios",
    "projectPath": "D:\\Projects\\BiloxiStudios",
    "host": "",
    "resumePath": "C:\\Users\\BizaNator\\.claude-sessions\\2026-02-05_biloxistudios.md",
    "status": "in-progress",
    "lastUpdated": "2026-02-05T18:30:00"
  }
]
```

Registry update rules:
- Match on `projectName` (lowercased basename of project directory)
- If entry exists: **update** its resumePath, status, sessionName, host, and lastUpdated
- If entry does not exist: **add** new entry
- Set `host` to the SSH user@hostname if remote, or empty string `""` if local
- If status is `done` → **remove** the entry from the registry (session file stays on disk as history)
- Only `in-progress`, `blocked`, and `planning` entries remain in the registry

5. **Confirm** by showing:
   - Session file location
   - Summary of current registry (name + status for each entry)
   - Reminder: _"Run `claude-goodmorning` in PowerShell tomorrow to reopen all sessions."_

Be thorough but concise. A fresh Claude instance will rely on this file to reconstruct full context.

User notes: $ARGUMENTS
