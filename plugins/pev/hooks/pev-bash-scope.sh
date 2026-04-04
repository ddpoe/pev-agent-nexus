#!/bin/bash
# pev-bash-scope.sh — PreToolUse hook for Bash calls in PEV subagents
# Blocks Bash commands that `cd` into a directory outside the worktree.
# This prevents the anti-pattern of running pytest from the main repo
# with worktree test paths (which imports the wrong code).
#
# Reads worktree_path from .claude/pev-state.json. If pev-state.json
# is missing or has no worktree_path, the hook is a no-op.

INPUT=$(cat)

# Resolve project root
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  while [ -n "$PROJECT_ROOT" ] && [ "$PROJECT_ROOT" != "/" ]; do
    [ -f "$PROJECT_ROOT/.claude/pev-state.json" ] && break
    PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
  done
fi
STATE_FILE="$PROJECT_ROOT/.claude/pev-state.json"

# No state file → not in a PEV cycle → allow
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Read worktree path from state
WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$STATE_FILE" 2>/dev/null)

# No worktree_path → no constraint → allow
if [ -z "$WORKTREE_PATH" ]; then
  exit 0
fi

# Resolve worktree to absolute path
WORKTREE_PATH=$(cd "$WORKTREE_PATH" 2>/dev/null && pwd -P)
if [ -z "$WORKTREE_PATH" ]; then
  exit 0
fi

# Extract the Bash command
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Extract the cd target from the command.
# Matches: "cd /some/path && ...", "cd /some/path;", "cd /some/path"
# Does NOT match: "git -C /path" (which is correct usage)
CD_TARGET=$(echo "$COMMAND" | grep -oP '^\s*cd\s+\K[^\s;&]+' 2>/dev/null)

if [ -z "$CD_TARGET" ]; then
  # No cd at the start of the command → allow
  exit 0
fi

# Resolve cd target to absolute path
case "$CD_TARGET" in
  /*) ;; # already absolute
  *)  CD_TARGET="$(echo "$INPUT" | jq -r '.cwd // empty')/$CD_TARGET" ;;
esac

# Normalize the cd target
if [ -d "$CD_TARGET" ]; then
  CD_TARGET=$(cd "$CD_TARGET" && pwd -P)
else
  # Directory doesn't exist — allow (will fail naturally)
  exit 0
fi

# Allow: cd into worktree or any subdirectory of worktree
case "$CD_TARGET" in
  "$WORKTREE_PATH"|"$WORKTREE_PATH"/*)
    exit 0
    ;;
  *)
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BLOCKED: 'cd ${CD_TARGET}' is outside the worktree '${WORKTREE_PATH}'. You must run all commands from the worktree directory. Use: cd ${WORKTREE_PATH} && ... For git commands, use: git -C ${WORKTREE_PATH} ...\"}}"
    ;;
esac
