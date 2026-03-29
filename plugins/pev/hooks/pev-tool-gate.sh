#!/bin/bash
# pev-tool-gate.sh — PreToolUse hook for PEV subagents
# Reads the tool call counter and BLOCKS non-allowlisted tools
# once the budget limit is reached. Runs BEFORE the tool executes.
#
# Args: <limit> [allowlist]
#   limit     — hard block threshold
#   allowlist — pipe-separated tool names allowed past limit
# Counter file path read from .claude/pev-state.json (field: counter_file)
# Falls back to /tmp/pev-tool-counter-spike if pev-state.json missing.

# Read hook input from stdin to get the tool name
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Threshold and allowlist from positional args
# Allowlist is comma-separated (pipes can't survive shell command strings)
LIMIT=${1:-10}
ALLOWLIST_CSV=${2:-"cortex_update_section,cortex_write_doc,cortex_add_section,cortex_mark_clean,cortex_build,cortex_check"}
ALLOWLIST="${ALLOWLIST_CSV//,/|}"

# Counter file from pev-state.json
# Resolve project root: prefer CLAUDE_PROJECT_DIR, then parse cwd from stdin input
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  # Walk up from cwd to find .claude/pev-state.json (handles worktree cwd)
  while [ -n "$PROJECT_ROOT" ] && [ "$PROJECT_ROOT" != "/" ]; do
    [ -f "$PROJECT_ROOT/.claude/pev-state.json" ] && break
    PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
  done
fi
STATE_FILE="$PROJECT_ROOT/.claude/pev-state.json"
if [ -f "$STATE_FILE" ]; then
  PEV_TOOL_COUNTER=$(jq -r '.counter_file // empty' "$STATE_FILE" 2>/dev/null)
fi
if [ -z "$PEV_TOOL_COUNTER" ]; then
  PEV_TOOL_COUNTER="/tmp/pev-tool-counter-spike"
fi

# Read current count
COUNT=0
if [ -f "$PEV_TOOL_COUNTER" ]; then
  COUNT=$(cat "$PEV_TOOL_COUNTER" 2>/dev/null || echo 0)
fi

# If under the limit, allow everything
if [ "$COUNT" -lt "$LIMIT" ]; then
  exit 0
fi

# Over limit — check allowlist
if echo "$TOOL_NAME" | grep -qE "$ALLOWLIST"; then
  # Allowed tool — let it through
  exit 0
fi

# Blocked — deny with reason
ALLOWED_READABLE="${ALLOWLIST_CSV//,/, }"
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"TOOL BUDGET EXHAUSTED (${COUNT}/${LIMIT}). ${TOOL_NAME} is blocked. Only these tools are allowed: ${ALLOWED_READABLE}. Finish your work and return your structured summary.\"}}"
