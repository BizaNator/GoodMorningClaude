Load saved session context and resume work.

1. **Find the session file**:
   - If `$ARGUMENTS` contains a file path, use that
   - Otherwise check `%USERPROFILE%\.claude-sessions\session-registry.json` for entries matching the current working directory (compare `projectPath`)
     - If exactly one match: use that entry's `resumePath`
     - If multiple matches: list them and ask which session to resume (show sessionName for each)
   - Otherwise find the most recent `.md` in `%USERPROFILE%\.claude-sessions\` that references this project path

2. **Read the session file** and internalize the context.

3. **Verify workspace**: Confirm we're in the correct project directory.

4. **Resume**: Summarize where we left off, then start executing from "Plan / Next Steps" item 1. Ask if the user wants to continue the plan or pivot.

Get back to work fast -- minimize preamble.

Session file or notes: $ARGUMENTS
