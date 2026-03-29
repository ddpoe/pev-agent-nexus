#!/bin/bash
# pev-tool-counter.sh — PostToolUse hook for PEV subagents
# Increments the tool call counter and pushes advisory warnings.
# Actual blocking is done by pev-tool-gate.sh (PreToolUse).
#
# Args: <warn> <urgent> <limit>
# Counter file path read from .claude/pev-state.json (field: counter_file)
# Falls back to /tmp/pev-tool-counter-spike if pev-state.json missing.

# Read hook input from stdin
INPUT=$(cat)

# Thresholds from positional args (defaults for spike testing)
WARN=${1:-3}
URGENT=${2:-6}
LIMIT=${3:-10}

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

# Read current count (default 0 if file doesn't exist)
COUNT=0
if [ -f "$PEV_TOOL_COUNTER" ]; then
  COUNT=$(cat "$PEV_TOOL_COUNTER" 2>/dev/null || echo 0)
fi

# Increment
COUNT=$((COUNT + 1))

# Write back
echo "$COUNT" > "$PEV_TOOL_COUNTER"

# Push advisory warnings (blocking is handled by PreToolUse gate)
if [ "$COUNT" -ge "$LIMIT" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT} used. Budget exhausted. Only allowlisted tools will work. Return your summary.\"}}"
elif [ "$COUNT" -ge "$URGENT" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT} used. URGENT — finish current task and produce your summary on the NEXT turn.\"}}"
elif [ "$COUNT" -ge "$WARN" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT} used. Start wrapping up soon.\"}}"
fi
