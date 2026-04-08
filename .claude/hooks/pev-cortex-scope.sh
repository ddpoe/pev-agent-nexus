#!/bin/bash
# pev-cortex-scope.sh — PreToolUse hook for PEV subagents
# Enforces that cortex MCP tool calls use the worktree's project_root,
# not the main repo. Reads worktree_path from .pev-state.json.
# No-op when .pev-state.json is missing or has no worktree_path.

INPUT=$(cat)

# Resolve .pev-state.json (lives at cwd root — set by EnterWorktree)
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"

# No state file → not in a PEV cycle → allow
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$STATE_FILE" 2>/dev/null)

# No worktree_path → no constraint → allow
if [ -z "$WORKTREE_PATH" ]; then
  exit 0
fi

# Resolve worktree to absolute canonical path
WORKTREE_PATH=$(cd "$WORKTREE_PATH" 2>/dev/null && pwd -P)
if [ -z "$WORKTREE_PATH" ]; then
  echo "BLOCKED: worktree_path in pev-state.json does not exist on disk" >&2
  exit 2
fi

# Extract project_root from the cortex tool input
TOOL_PROJECT_ROOT=$(echo "$INPUT" | jq -r '.tool_input.project_root // empty' 2>/dev/null)

if [ -z "$TOOL_PROJECT_ROOT" ]; then
  # No project_root in tool input — block (cortex tools require it)
  echo "BLOCKED: cortex tool call missing project_root parameter" >&2
  exit 2
fi

# Resolve to absolute canonical path
if [ -d "$TOOL_PROJECT_ROOT" ]; then
  TOOL_PROJECT_ROOT=$(cd "$TOOL_PROJECT_ROOT" && pwd -P)
else
  echo "BLOCKED: project_root '$TOOL_PROJECT_ROOT' does not exist on disk" >&2
  exit 2
fi

# Check: must match worktree path exactly
if [ "$TOOL_PROJECT_ROOT" = "$WORKTREE_PATH" ]; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
echo "BLOCKED: cortex project_root '$TOOL_PROJECT_ROOT' does not match worktree '$WORKTREE_PATH' (tool: $TOOL_NAME)" >&2
exit 2
