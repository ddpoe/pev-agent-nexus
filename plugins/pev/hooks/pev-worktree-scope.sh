#!/bin/bash
# pev-worktree-scope.sh — PreToolUse hook for PEV subagents
# Enforces that Write/Edit calls target only files inside the worktree.
# Reads worktree_path from .pev-state.json. If .pev-state.json is
# missing or has no worktree_path, the hook is a no-op (allows
# non-PEV sessions to work without interference).

INPUT=$(cat)

# Resolve project root: prefer CLAUDE_PROJECT_DIR, then parse cwd
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  while [ -n "$PROJECT_ROOT" ] && [ "$PROJECT_ROOT" != "/" ]; do
    [ -f "$PROJECT_ROOT/.pev-state.json" ] && break
    PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
  done
fi
STATE_FILE="$PROJECT_ROOT/.pev-state.json"

# No state file → not in a PEV cycle → allow everything
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Read worktree path from state
WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$STATE_FILE" 2>/dev/null)

# No worktree_path in state → no constraint to enforce → allow
if [ -z "$WORKTREE_PATH" ]; then
  exit 0
fi

# Resolve to absolute path (handles trailing slashes, symlinks)
WORKTREE_PATH=$(cd "$WORKTREE_PATH" 2>/dev/null && pwd -P)
if [ -z "$WORKTREE_PATH" ]; then
  # Worktree path doesn't exist on disk — block to be safe
  echo "BLOCKED: worktree_path in pev-state.json does not exist on disk" >&2
  exit 2
fi

# Extract file_path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  # No file_path in tool input (shouldn't happen for Write/Edit) — allow
  exit 0
fi

# Resolve file_path to absolute (it may already be absolute)
case "$FILE_PATH" in
  /*) ;; # already absolute
  *)  FILE_PATH="$(echo "$INPUT" | jq -r '.cwd // empty')/$FILE_PATH" ;;
esac

# Normalize: resolve .. and symlinks in the directory portion
FILE_DIR=$(dirname "$FILE_PATH")
FILE_BASE=$(basename "$FILE_PATH")
if [ -d "$FILE_DIR" ]; then
  FILE_PATH="$(cd "$FILE_DIR" && pwd -P)/$FILE_BASE"
else
  # Directory doesn't exist yet (Write creating new file) — check parent chain
  CHECK_DIR="$FILE_DIR"
  while [ ! -d "$CHECK_DIR" ] && [ "$CHECK_DIR" != "/" ]; do
    CHECK_DIR=$(dirname "$CHECK_DIR")
  done
  if [ -d "$CHECK_DIR" ]; then
    RESOLVED=$(cd "$CHECK_DIR" && pwd -P)
    REMAINDER="${FILE_DIR#$CHECK_DIR}"
    FILE_PATH="${RESOLVED}${REMAINDER}/$FILE_BASE"
  fi
fi

# Check: file_path must start with worktree_path
case "$FILE_PATH" in
  "$WORKTREE_PATH"/*)
    # Inside worktree — allow
    exit 0
    ;;
  "$WORKTREE_PATH")
    # Exact match (unlikely for a file) — allow
    exit 0
    ;;
  *)
    echo "BLOCKED: Write/Edit target '$FILE_PATH' is outside the worktree '$WORKTREE_PATH'" >&2
    exit 2
    ;;
esac
