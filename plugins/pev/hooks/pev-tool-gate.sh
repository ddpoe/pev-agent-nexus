#!/bin/bash
# pev-tool-gate.sh — PreToolUse hook for PEV subagents.
# BLOCKS non-allowlisted tools once the budget limit is reached.
#
# Active ONLY when agent_type starts with "pev:". Budget threshold and
# allowlist are dispatched on agent_type. Counter file is keyed on
# agent_id (matched to pev-tool-counter.sh).

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Dispatch limit + allowlist on agent_type. Allowlist is a regex-ready
# pipe-separated string; tool names are matched by substring against it.
case "$AGENT_TYPE" in
  pev:pev-architect)
    LIMIT=80
    ALLOWLIST="cortex_update_section|cortex_write_doc|cortex_add_section|cortex_build"
    ALLOWLIST_HUMAN="cortex_update_section, cortex_write_doc, cortex_add_section, cortex_build"
    ;;
  pev:pev-builder)
    LIMIT=100
    ALLOWLIST="Bash|Edit|Write|cortex_update_section|cortex_add_section"
    ALLOWLIST_HUMAN="Bash, Edit, Write, cortex_update_section, cortex_add_section"
    ;;
  pev:pev-reviewer)
    LIMIT=85
    ALLOWLIST="cortex_update_section"
    ALLOWLIST_HUMAN="cortex_update_section"
    ;;
  pev:pev-auditor)
    LIMIT=75
    ALLOWLIST="cortex_update_section|cortex_write_doc|cortex_add_section|cortex_delete_link|cortex_update_doc_meta|cortex_mark_clean|cortex_purge_node|cortex_build|cortex_check"
    ALLOWLIST_HUMAN="cortex_update_section, cortex_write_doc, cortex_add_section, cortex_delete_link, cortex_update_doc_meta, cortex_mark_clean, cortex_purge_node, cortex_build, cortex_check"
    ;;
  pev:pev-doc-reviewer)
    LIMIT=60
    ALLOWLIST="cortex_update_section"
    ALLOWLIST_HUMAN="cortex_update_section"
    ;;
  pev:pev-spike)
    LIMIT=7
    ALLOWLIST="Write|cortex_update_section"
    ALLOWLIST_HUMAN="Write, cortex_update_section"
    ;;
  *) exit 0 ;;
esac

# Counter file (matches pev-tool-counter.sh keying)
if [ -n "$AGENT_ID" ]; then
  PEV_TOOL_COUNTER="/tmp/pev-counter-${AGENT_ID}.txt"
else
  PEV_TOOL_COUNTER="/tmp/pev-counter-${AGENT_TYPE//:/-}.txt"
fi

COUNT=0
if [ -f "$PEV_TOOL_COUNTER" ]; then
  COUNT=$(cat "$PEV_TOOL_COUNTER" 2>/dev/null || echo 0)
fi

# Under the limit — allow everything
if [ "$COUNT" -lt "$LIMIT" ]; then
  exit 0
fi

# Over limit — check allowlist
if echo "$TOOL_NAME" | grep -qE "$ALLOWLIST"; then
  exit 0
fi

# Blocked
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${TOOL_NAME} is blocked (budget ${COUNT}/${LIMIT}). Tools still available: ${ALLOWLIST_HUMAN}. Use cortex_update_section to save your state to the cycle manifest, then return with CONTINUING status. The next incarnation continues from your progress.\"}}"
