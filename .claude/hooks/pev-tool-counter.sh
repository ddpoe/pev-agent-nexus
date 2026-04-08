#!/bin/bash
# pev-tool-counter.sh — PostToolUse hook for PEV subagents
# Increments the tool call counter and pushes advisory warnings.
# Actual blocking is done by pev-tool-gate.sh (PreToolUse).
#
# Args: <warn> <urgent> <limit>
# Counter file path read from .pev-state.json (field: counter_file)
# Falls back to /tmp/pev-tool-counter-spike if .pev-state.json missing.

# Read hook input from stdin
INPUT=$(cat)

# Thresholds from positional args (defaults for spike testing)
WARN=${1:-3}
URGENT=${2:-6}
LIMIT=${3:-10}

# Counter file from .pev-state.json (lives at cwd root — set by EnterWorktree)
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
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
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT}. Some tools are now blocked — you still have your allowlisted tools. If you are mid-task, use cortex_update_section to document your current state in the cycle manifest: what is done, what is in progress, what remains, and context the next incarnation needs. Then produce your structured return with CONTINUING status. The next incarnation picks up where you left off with a fresh budget. Do not rush or cut corners.\"}}"
elif [ "$COUNT" -ge "$URGENT" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT}. Approaching the tool limit — after ${LIMIT}, some tools will be blocked. Finish your current task if close. If not, that is OK — document your progress in the cycle manifest via cortex_update_section so the next incarnation can continue seamlessly. Do not start a new task.\"}}"
elif [ "$COUNT" -ge "$WARN" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT}. You have used more than half your budget. Check your progress against your plan — if many tasks remain, focus on completing one at a time rather than exploring broadly.\"}}"
fi
