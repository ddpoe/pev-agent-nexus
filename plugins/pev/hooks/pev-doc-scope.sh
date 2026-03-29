#!/bin/bash
# pev-doc-scope.sh — PreToolUse hook for PEV Architect doc-write tools
# Enforces that doc-write calls target only the current cycle manifest.
# Reads cycle_doc_id from .claude/pev-state.json, compares against
# the doc_id (or doc_json.id) in the tool_input. Exit 2 to block.

INPUT=$(cat)

# Read allowed cycle doc ID from orchestrator state file
CYCLE_DOC_ID=$(jq -r '.cycle_doc_id // ""' .claude/pev-state.json 2>/dev/null)

if [ -z "$CYCLE_DOC_ID" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"No cycle_doc_id in .claude/pev-state.json — cannot verify doc scope"}}' >&2
  exit 2
fi

TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Extract the target doc_id based on which tool is being called
case "$TOOL" in
  mcp__cortex__cortex_update_section)
    # update_section has section_id (fully qualified), not doc_id
    # e.g. "cortex::docs.pev-cycles.pev-2026-03-21-foo::scope"
    # Extract doc_id by removing the last ::segment
    SECTION_ID=$(echo "$INPUT" | jq -r '.tool_input.section_id // ""')
    TARGET=$(echo "$SECTION_ID" | sed 's/::[^:]*$//')
    ;;
  mcp__cortex__cortex_add_section)
    TARGET=$(echo "$INPUT" | jq -r '.tool_input.doc_id // ""')
    ;;
  mcp__cortex__cortex_write_doc)
    # write_doc may receive doc_json as a string or object
    DOC_JSON=$(echo "$INPUT" | jq -r '.tool_input.doc_json // ""')
    if echo "$DOC_JSON" | jq -e . >/dev/null 2>&1; then
      TARGET=$(echo "$DOC_JSON" | jq -r '.id // ""')
    else
      TARGET=""
    fi
    ;;
  *)
    # Not a doc-write tool we care about — allow
    exit 0
    ;;
esac

if [ -z "$TARGET" ]; then
  echo "BLOCKED: Could not extract doc_id from tool call" >&2
  exit 2
fi

if [ "$TARGET" != "$CYCLE_DOC_ID" ]; then
  echo "BLOCKED: Doc-scope violation — target '$TARGET' is not the current cycle manifest '$CYCLE_DOC_ID'" >&2
  exit 2
fi
