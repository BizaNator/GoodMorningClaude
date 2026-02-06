Load saved session context and resume work.

1. **Find the session file**:
   - If `$ARGUMENTS` contains a file path, use that
   - Otherwise check `%USERPROFILE%\.claude-sessions\session-registry.json` for an entry matching the current directory's project name
   - Otherwise find the most recent `.md` in `%USERPROFILE%\.claude-sessions\` matching the project name

2. **Read the session file** and internalize the context.

3. **Verify workspace**: Confirm we're in the correct project directory.

4. **Resume**: Summarize where we left off, then start executing from "Plan / Next Steps" item 1. Ask if the user wants to continue the plan or pivot.

Get back to work fast — minimize preamble.

Session file or notes: $ARGUMENTS
