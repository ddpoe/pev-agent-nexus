# Migrate PEV Hooks from Agent Frontmatter to hooks.json

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all PEV hook registrations from agent `.md` frontmatter (silently stripped by Claude Code) into `hooks/hooks.json` (global plugin-level hooks that actually fire), using `.pev-state.json` for phase-aware routing.

**Architecture:** Global hooks fire on every tool call. Each script reads `.pev-state.json` — no state file means exit 0 (no-op outside PEV cycles). Phase is extracted from `counter_file` name. A template file centralizes all budget config, copied once at cycle start.

**Tech Stack:** Bash hook scripts, jq for JSON parsing, Claude Code plugin hooks.json format

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `plugins/pev/templates/pev-state.template.json` | CREATE | Budget config for all 5 phases |
| `plugins/pev/hooks/pev-tool-gate.sh` | REWRITE | Read budget/allowlist from state file instead of $1/$2 |
| `plugins/pev/hooks/pev-tool-counter.sh` | REWRITE | Read thresholds from state file instead of $1/$2/$3 |
| `plugins/pev/hooks/pev-write-gate.sh` | CREATE | Phase-aware code-write blocking (reviewer/auditor deny) |
| `plugins/pev/hooks/pev-destructive-cortex-gate.sh` | CREATE | Phase-aware destructive cortex tool blocking |
| `plugins/pev/hooks/hooks.json` | REWRITE | 7 PreToolUse + 1 PostToolUse global entries |
| `plugins/pev/agents/pev-architect.md` | EDIT | Strip `hooks:` frontmatter |
| `plugins/pev/agents/pev-builder.md` | EDIT | Strip `hooks:` frontmatter |
| `plugins/pev/agents/pev-spike.md` | EDIT | Strip `hooks:` frontmatter |
| `plugins/pev/agents/pev-reviewer.md` | EDIT | Strip `hooks:` frontmatter |
| `plugins/pev/agents/pev-auditor.md` | EDIT | Strip `hooks:` frontmatter |
| `plugins/pev/templates/pev-orchestrator-reference.md` | EDIT | Update State File section for new format |
| `plugins/pev/skills/pev-cycle/SKILL.md` | EDIT | Reference template in Phase 1 and Phase 7 |
| `plugins/pev/skills/pev-spike/SKILL.md` | EDIT | Reference template in Step 4, add write-gate/destructive-gate tests |

**Unchanged scripts** (already read from `.pev-state.json`, no-op without it):
- `pev-bash-scope.sh`
- `pev-worktree-scope.sh`
- `pev-cortex-scope.sh`
- `pev-doc-scope.sh`

---

## Cross-cutting: Phase extraction

All phase-aware scripts extract the agent name from `counter_file`. **Must use `grep -oE` + `sed`** (not `grep -P` — fails on Windows/Git Bash):

```bash
PHASE=$(basename "$PEV_TOOL_COUNTER" | grep -oE '(architect|builder|reviewer|auditor|spike)-[0-9]+$' | sed 's/-[0-9]*$//')
```

This is used in: `pev-tool-gate.sh`, `pev-tool-counter.sh`, `pev-write-gate.sh`, `pev-destructive-cortex-gate.sh`.

---

### Important: Plugin cache behavior

**Finding from pre-implementation testing:** Claude Code loads plugin hooks from the **cache** at `~/.claude/plugins/cache/pev-agent-nexus/pev/{version}/`, NOT from the repo's `plugins/pev/` directory. Editing files in the repo has no effect until a new version is cached. The cached PEV v1.6.0 has `{"hooks":{}}`.

**Implication:** All changes in Tasks 1-7 modify repo files. After committing, we must bump the version to 1.6.1 (Task 8) and re-cache the plugin. Hooks won't fire until the new version is installed.

**Version bump locations (3 files):**
- `plugins/pev/.claude-plugin/plugin.json:4`
- `.claude-plugin/marketplace.json:8`
- `.claude-plugin/marketplace.json:15`

**Still unknown:** What `cwd` the hook input contains when firing inside a worktree subagent. The `/pev-spike` smoke test (run after re-cache) will validate this. If `cwd` is wrong, the fallback `${CLAUDE_PROJECT_DIR}` env var may work — all scripts already check it.

---

### Task 1: Create state template

**Files:**
- Create: `plugins/pev/templates/pev-state.template.json`

- [ ] **Step 1: Create the template file**

```json
{
  "cycle_id": "",
  "cycle_doc_id": "",
  "worktree_path": "",
  "counter_file": "",
  "budgets": {
    "architect": {
      "limit": 40,
      "thresholds": [25, 35, 40],
      "allowlist": ["cortex_update_section", "cortex_write_doc", "cortex_add_section", "cortex_build"]
    },
    "builder": {
      "limit": 80,
      "thresholds": [50, 70, 80],
      "allowlist": ["^Bash$", "^Edit$", "^Write$", "cortex_update_section", "cortex_add_section"]
    },
    "spike": {
      "limit": 7,
      "thresholds": [3, 5, 7],
      "allowlist": ["^Write$", "cortex_update_section"]
    },
    "reviewer": {
      "limit": 55,
      "thresholds": [30, 45, 55],
      "allowlist": ["cortex_update_section"]
    },
    "auditor": {
      "limit": 65,
      "thresholds": [40, 55, 65],
      "allowlist": ["cortex_update_section", "cortex_write_doc", "cortex_add_section", "cortex_delete_link", "cortex_update_doc_meta", "cortex_mark_clean", "cortex_purge_node", "cortex_build", "cortex_check"]
    }
  }
}
```

Built-in tools use `^anchored$` regex to prevent substring false positives (e.g., `Write` matching `cortex_write_doc`). Cortex tools use substrings to match through the `mcp__cortex__` prefix.

- [ ] **Step 2: Validate**

Run: `cat plugins/pev/templates/pev-state.template.json | jq '.budgets | keys[]' | wc -l`
Expected: 5

- [ ] **Step 3: Commit**

```bash
git add plugins/pev/templates/pev-state.template.json
git commit -m "feat(pev): add pev-state template with centralized budget config"
```

---

### Task 2: Rewrite `pev-tool-gate.sh`

**Files:**
- Modify: `plugins/pev/hooks/pev-tool-gate.sh`

- [ ] **Step 1: Rewrite the script**

Replace entire file. Key changes vs current:
- Remove positional args `$1` (limit), `$2` (allowlist CSV)
- Add early exit when no `.pev-state.json` (critical — without this, hook is a no-op breaker in non-PEV sessions)
- Extract phase from counter_file name
- Read `limit` from `.budgets[PHASE].limit`
- Read `allowlist` from `.budgets[PHASE].allowlist` as JSON array, join with `|` for grep regex

```bash
#!/bin/bash
# pev-tool-gate.sh — PreToolUse hook for PEV subagents
# Reads the tool call counter and BLOCKS non-allowlisted tools
# once the budget limit is reached. Runs BEFORE the tool executes.
#
# Config read from .pev-state.json: counter_file, budgets[PHASE].limit, budgets[PHASE].allowlist
# Phase extracted from counter_file name.
# No-op when .pev-state.json is missing (non-PEV session).

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve .pev-state.json
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"

# No state file → not in a PEV cycle → allow
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

PEV_TOOL_COUNTER=$(jq -r '.counter_file // empty' "$STATE_FILE" 2>/dev/null)
if [ -z "$PEV_TOOL_COUNTER" ]; then
  exit 0
fi

# Extract phase from counter_file name
PHASE=$(basename "$PEV_TOOL_COUNTER" | grep -oE '(architect|builder|reviewer|auditor|spike)-[0-9]+$' | sed 's/-[0-9]*$//')
if [ -z "$PHASE" ]; then
  exit 0
fi

# Read budget config for this phase
LIMIT=$(jq -r ".budgets.${PHASE}.limit // empty" "$STATE_FILE" 2>/dev/null)
if [ -z "$LIMIT" ]; then
  exit 0
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

# Over limit — check allowlist from .pev-state.json (JSON array of patterns)
ALLOWLIST_JSON=$(jq -c ".budgets.${PHASE}.allowlist // []" "$STATE_FILE" 2>/dev/null)
ALLOWLIST_COUNT=$(echo "$ALLOWLIST_JSON" | jq 'length')

if [ "$ALLOWLIST_COUNT" -gt 0 ]; then
  ALLOWLIST_REGEX=$(echo "$ALLOWLIST_JSON" | jq -r 'join("|")')
  if echo "$TOOL_NAME" | grep -qE "$ALLOWLIST_REGEX"; then
    exit 0
  fi
fi

# Blocked
ALLOWED_READABLE=$(echo "$ALLOWLIST_JSON" | jq -r 'join(", ")')
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${TOOL_NAME} is blocked (budget ${COUNT}/${LIMIT}). Tools still available: ${ALLOWED_READABLE}. Use cortex_update_section to save your state to the cycle manifest, then return with CONTINUING status. The next incarnation continues from your progress.\"}}"
```

- [ ] **Step 2: Test no-op (no state file)**

Run: `echo '{"tool_name":"Read","cwd":"/tmp/nonexistent"}' | bash plugins/pev/hooks/pev-tool-gate.sh; echo "exit:$?"`
Expected: `exit:0` with no output

- [ ] **Step 3: Test blocking and allowlist**

```bash
mkdir -p /tmp/pev-gate-test
cat plugins/pev/templates/pev-state.template.json | jq '.counter_file="/tmp/pev-gate-test-builder-1"' > /tmp/pev-gate-test/.pev-state.json
echo '85' > /tmp/pev-gate-test-builder-1
# Blocked (Read not on builder allowlist)
echo '{"tool_name":"Read","cwd":"/tmp/pev-gate-test"}' | bash plugins/pev/hooks/pev-tool-gate.sh | jq -r '.hookSpecificOutput.permissionDecision'
# Expected: deny
# Allowed (^Bash$ anchored match)
echo '{"tool_name":"Bash","cwd":"/tmp/pev-gate-test"}' | bash plugins/pev/hooks/pev-tool-gate.sh; echo "exit:$?"
# Expected: exit:0, no output
# Allowed (cortex substring match)
echo '{"tool_name":"mcp__cortex__cortex_update_section","cwd":"/tmp/pev-gate-test"}' | bash plugins/pev/hooks/pev-tool-gate.sh; echo "exit:$?"
# Expected: exit:0
# Verify Write does NOT match cortex_write_doc (anchored)
echo '{"tool_name":"mcp__cortex__cortex_write_doc","cwd":"/tmp/pev-gate-test"}' | bash plugins/pev/hooks/pev-tool-gate.sh | jq -r '.hookSpecificOutput.permissionDecision'
# Expected: deny (cortex_write_doc is not on builder's allowlist)
rm -rf /tmp/pev-gate-test /tmp/pev-gate-test-builder-1
```

- [ ] **Step 4: Commit**

```bash
git add plugins/pev/hooks/pev-tool-gate.sh
git commit -m "feat(pev): rewrite tool-gate to read budget config from .pev-state.json"
```

---

### Task 3: Rewrite `pev-tool-counter.sh`

**Files:**
- Modify: `plugins/pev/hooks/pev-tool-counter.sh`

- [ ] **Step 1: Rewrite the script**

Same pattern as gate. Key changes:
- Remove positional args `$1` (warn), `$2` (urgent), `$3` (limit)
- Add early exit when no `.pev-state.json`
- Extract phase from counter_file name
- Read thresholds from `.budgets[PHASE].thresholds` array

```bash
#!/bin/bash
# pev-tool-counter.sh — PostToolUse hook for PEV subagents
# Increments the tool call counter and pushes advisory warnings.
# Actual blocking is done by pev-tool-gate.sh (PreToolUse).
#
# Config read from .pev-state.json: counter_file, budgets[PHASE].thresholds
# Phase extracted from counter_file name.
# No-op when .pev-state.json is missing (non-PEV session).

INPUT=$(cat)

# Resolve .pev-state.json
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"

# No state file → not in a PEV cycle → no-op
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

PEV_TOOL_COUNTER=$(jq -r '.counter_file // empty' "$STATE_FILE" 2>/dev/null)
if [ -z "$PEV_TOOL_COUNTER" ]; then
  exit 0
fi

# Extract phase from counter_file name
PHASE=$(basename "$PEV_TOOL_COUNTER" | grep -oE '(architect|builder|reviewer|auditor|spike)-[0-9]+$' | sed 's/-[0-9]*$//')
if [ -z "$PHASE" ]; then
  exit 0
fi

# Read thresholds for this phase: [warn, urgent, limit]
WARN=$(jq -r ".budgets.${PHASE}.thresholds[0] // empty" "$STATE_FILE" 2>/dev/null)
URGENT=$(jq -r ".budgets.${PHASE}.thresholds[1] // empty" "$STATE_FILE" 2>/dev/null)
LIMIT=$(jq -r ".budgets.${PHASE}.thresholds[2] // empty" "$STATE_FILE" 2>/dev/null)

if [ -z "$WARN" ] || [ -z "$URGENT" ] || [ -z "$LIMIT" ]; then
  exit 0
fi

# Read current count
COUNT=0
if [ -f "$PEV_TOOL_COUNTER" ]; then
  COUNT=$(cat "$PEV_TOOL_COUNTER" 2>/dev/null || echo 0)
fi

# Increment
COUNT=$((COUNT + 1))

# Write back
echo "$COUNT" > "$PEV_TOOL_COUNTER"

# Push advisory warnings
if [ "$COUNT" -ge "$LIMIT" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT}. Some tools are now blocked — you still have your allowlisted tools. If you are mid-task, use cortex_update_section to document your current state in the cycle manifest: what is done, what is in progress, what remains, and context the next incarnation needs. Then produce your structured return with CONTINUING status. The next incarnation picks up where you left off with a fresh budget. Do not rush or cut corners.\"}}"
elif [ "$COUNT" -ge "$URGENT" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT}. Approaching the tool limit — after ${LIMIT}, some tools will be blocked. Finish your current task if close. If not, that is OK — document your progress in the cycle manifest via cortex_update_section so the next incarnation can continue seamlessly. Do not start a new task.\"}}"
elif [ "$COUNT" -ge "$WARN" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"TOOL BUDGET: ${COUNT}/${LIMIT}. You have used more than half your budget. Check your progress against your plan — if many tasks remain, focus on completing one at a time rather than exploring broadly.\"}}"
fi
```

- [ ] **Step 2: Test no-op**

Run: `echo '{"tool_name":"Read","cwd":"/tmp/nonexistent"}' | bash plugins/pev/hooks/pev-tool-counter.sh; echo "exit:$?"`
Expected: `exit:0`, no output, no `/tmp/pev-tool-counter-spike` created

- [ ] **Step 3: Test increment and warning thresholds**

```bash
mkdir -p /tmp/pev-ctr-test
cat plugins/pev/templates/pev-state.template.json | jq '.counter_file="/tmp/pev-ctr-test-spike-1"' > /tmp/pev-ctr-test/.pev-state.json
# Start at 2, increment to 3 → should hit warn threshold (spike warn=3)
echo '2' > /tmp/pev-ctr-test-spike-1
echo '{"tool_name":"Read","cwd":"/tmp/pev-ctr-test"}' | bash plugins/pev/hooks/pev-tool-counter.sh
# Expected: output contains "TOOL BUDGET: 3/7"
cat /tmp/pev-ctr-test-spike-1
# Expected: 3
rm -rf /tmp/pev-ctr-test /tmp/pev-ctr-test-spike-1
```

- [ ] **Step 4: Commit**

```bash
git add plugins/pev/hooks/pev-tool-counter.sh
git commit -m "feat(pev): rewrite tool-counter to read thresholds from .pev-state.json"
```

---

### Task 4: Create `pev-write-gate.sh`

**Files:**
- Create: `plugins/pev/hooks/pev-write-gate.sh`

- [ ] **Step 1: Create the script**

Replaces the inline `echo 'BLOCKED...' >&2; exit 2` from reviewer and auditor frontmatter. Matcher in hooks.json: `Edit|Write|NotebookEdit` (NOT Bash — reviewer needs Bash for pytest/git, and auditor/architect don't have Bash in their tool list so Claude Code won't call it).

```bash
#!/bin/bash
# pev-write-gate.sh — PreToolUse hook for PEV subagents
# Phase-aware blocking of code-modification tools (Edit, Write, NotebookEdit).
# Bash is NOT matched — reviewer needs it for pytest/git, and auditor/architect
# don't have it in their tool list so Claude Code won't call it.
#   - reviewer: blocks Edit/Write/NotebookEdit (read-only agent)
#   - auditor: blocks Edit/Write/NotebookEdit (doc-only agent)
#   - architect: blocks Edit/Write/NotebookEdit (defense-in-depth)
#   - builder/spike: allows (code-write agents)
#
# No-op when .pev-state.json is missing (non-PEV session).

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve .pev-state.json
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

PEV_TOOL_COUNTER=$(jq -r '.counter_file // empty' "$STATE_FILE" 2>/dev/null)
if [ -z "$PEV_TOOL_COUNTER" ]; then
  exit 0
fi

PHASE=$(basename "$PEV_TOOL_COUNTER" | grep -oE '(architect|builder|reviewer|auditor|spike)-[0-9]+$' | sed 's/-[0-9]*$//')
if [ -z "$PHASE" ]; then
  exit 0
fi

case "$PHASE" in
  reviewer)
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BLOCKED: Reviewer cannot modify code — ${TOOL_NAME} is not allowed. Use cortex_update_section to write review findings to the cycle manifest.\"}}"
    ;;
  auditor)
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BLOCKED: Auditor cannot modify code — use cortex doc tools only. ${TOOL_NAME} is not allowed.\"}}"
    ;;
  architect)
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BLOCKED: Architect cannot modify code — ${TOOL_NAME} is not allowed.\"}}"
    ;;
  builder|spike)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
```

- [ ] **Step 2: Make executable**

Run: `chmod +x plugins/pev/hooks/pev-write-gate.sh`

- [ ] **Step 3: Test reviewer blocks, builder allows**

```bash
mkdir -p /tmp/pev-wg-test
cat plugins/pev/templates/pev-state.template.json | jq '.counter_file="/tmp/pev-wg-reviewer-1"' > /tmp/pev-wg-test/.pev-state.json
echo '{"tool_name":"Edit","cwd":"/tmp/pev-wg-test"}' | bash plugins/pev/hooks/pev-write-gate.sh | jq -r '.hookSpecificOutput.permissionDecision'
# Expected: deny

cat plugins/pev/templates/pev-state.template.json | jq '.counter_file="/tmp/pev-wg-builder-1"' > /tmp/pev-wg-test/.pev-state.json
echo '{"tool_name":"Edit","cwd":"/tmp/pev-wg-test"}' | bash plugins/pev/hooks/pev-write-gate.sh; echo "exit:$?"
# Expected: exit:0, no output

rm -rf /tmp/pev-wg-test
```

- [ ] **Step 4: Commit**

```bash
git add plugins/pev/hooks/pev-write-gate.sh
git commit -m "feat(pev): add phase-aware write-gate hook"
```

---

### Task 5: Create `pev-destructive-cortex-gate.sh`

**Files:**
- Create: `plugins/pev/hooks/pev-destructive-cortex-gate.sh`

- [ ] **Step 1: Create the script**

Replaces inline `echo 'BLOCKED...' >&2; exit 2` from builder, reviewer, and auditor frontmatter for destructive cortex tools.

```bash
#!/bin/bash
# pev-destructive-cortex-gate.sh — PreToolUse hook for PEV subagents
# Phase-aware blocking of destructive cortex operations.
#   - builder: blocks write_doc, add_link, mark_clean, build, check,
#              delete_doc, delete_section, delete_link, update_doc_meta, purge_node
#   - reviewer: blocks write_doc, add_section, add_link, mark_clean, build,
#               delete_doc, delete_section, delete_link, update_doc_meta, purge_node
#   - auditor: blocks delete_doc, delete_section
#   - architect/spike: allows (tool lists already restrict)
#
# No-op when .pev-state.json is missing (non-PEV session).

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve .pev-state.json
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

PEV_TOOL_COUNTER=$(jq -r '.counter_file // empty' "$STATE_FILE" 2>/dev/null)
if [ -z "$PEV_TOOL_COUNTER" ]; then
  exit 0
fi

PHASE=$(basename "$PEV_TOOL_COUNTER" | grep -oE '(architect|builder|reviewer|auditor|spike)-[0-9]+$' | sed 's/-[0-9]*$//')
if [ -z "$PHASE" ]; then
  exit 0
fi

# Extract cortex operation: mcp__cortex__cortex_write_doc → cortex_write_doc
CORTEX_OP=$(echo "$TOOL_NAME" | sed 's/^mcp__cortex__//')

case "$PHASE" in
  builder)
    case "$CORTEX_OP" in
      cortex_write_doc|cortex_add_link|cortex_mark_clean|cortex_build|cortex_check|cortex_delete_doc|cortex_delete_section|cortex_delete_link|cortex_update_doc_meta|cortex_purge_node)
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BLOCKED: Builder cannot ${CORTEX_OP} — use cortex_update_section and cortex_add_section for the cycle manifest only.\"}}"
        ;;
      *) exit 0 ;;
    esac
    ;;
  reviewer)
    case "$CORTEX_OP" in
      cortex_write_doc|cortex_add_section|cortex_add_link|cortex_mark_clean|cortex_build|cortex_delete_doc|cortex_delete_section|cortex_delete_link|cortex_update_doc_meta|cortex_purge_node)
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BLOCKED: Reviewer cannot ${CORTEX_OP} — Reviewer can only use cortex_update_section for the cycle manifest.\"}}"
        ;;
      *) exit 0 ;;
    esac
    ;;
  auditor)
    case "$CORTEX_OP" in
      cortex_delete_doc|cortex_delete_section)
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BLOCKED: Auditor cannot ${CORTEX_OP} — too destructive for automated use.\"}}"
        ;;
      *) exit 0 ;;
    esac
    ;;
  architect|spike)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
```

- [ ] **Step 2: Make executable**

Run: `chmod +x plugins/pev/hooks/pev-destructive-cortex-gate.sh`

- [ ] **Step 3: Test per-phase blocking**

```bash
mkdir -p /tmp/pev-dcg-test

# Builder blocks cortex_write_doc
cat plugins/pev/templates/pev-state.template.json | jq '.counter_file="/tmp/pev-dcg-builder-1"' > /tmp/pev-dcg-test/.pev-state.json
echo '{"tool_name":"mcp__cortex__cortex_write_doc","cwd":"/tmp/pev-dcg-test"}' | bash plugins/pev/hooks/pev-destructive-cortex-gate.sh | jq -r '.hookSpecificOutput.permissionDecision'
# Expected: deny

# Builder allows cortex_update_section
echo '{"tool_name":"mcp__cortex__cortex_update_section","cwd":"/tmp/pev-dcg-test"}' | bash plugins/pev/hooks/pev-destructive-cortex-gate.sh; echo "exit:$?"
# Expected: exit:0

# Auditor blocks cortex_delete_doc
cat plugins/pev/templates/pev-state.template.json | jq '.counter_file="/tmp/pev-dcg-auditor-1"' > /tmp/pev-dcg-test/.pev-state.json
echo '{"tool_name":"mcp__cortex__cortex_delete_doc","cwd":"/tmp/pev-dcg-test"}' | bash plugins/pev/hooks/pev-destructive-cortex-gate.sh | jq -r '.hookSpecificOutput.permissionDecision'
# Expected: deny

# Auditor allows cortex_mark_clean
echo '{"tool_name":"mcp__cortex__cortex_mark_clean","cwd":"/tmp/pev-dcg-test"}' | bash plugins/pev/hooks/pev-destructive-cortex-gate.sh; echo "exit:$?"
# Expected: exit:0

rm -rf /tmp/pev-dcg-test
```

- [ ] **Step 4: Commit**

```bash
git add plugins/pev/hooks/pev-destructive-cortex-gate.sh
git commit -m "feat(pev): add phase-aware destructive cortex gate hook"
```

---

### Task 6: Populate `hooks.json`

**Files:**
- Modify: `plugins/pev/hooks/hooks.json`

- [ ] **Step 1: Rewrite hooks.json**

Hook execution order matters — scope checks first, phase gates next, budget gate last:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__cortex__cortex_update_section|mcp__cortex__cortex_write_doc|mcp__cortex__cortex_add_section",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pev-doc-scope.sh\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pev-bash-scope.sh\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pev-worktree-scope.sh\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "mcp__cortex__",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pev-cortex-scope.sh\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pev-write-gate.sh\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "mcp__cortex__cortex_write_doc|mcp__cortex__cortex_add_section|mcp__cortex__cortex_add_link|mcp__cortex__cortex_mark_clean|mcp__cortex__cortex_build|mcp__cortex__cortex_check|mcp__cortex__cortex_delete_doc|mcp__cortex__cortex_delete_section|mcp__cortex__cortex_delete_link|mcp__cortex__cortex_update_doc_meta|mcp__cortex__cortex_purge_node",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pev-destructive-cortex-gate.sh\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pev-tool-gate.sh\"",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pev-tool-counter.sh\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

No positional args on gate or counter — they read from `.pev-state.json` now.

- [ ] **Step 2: Validate**

Run: `cat plugins/pev/hooks/hooks.json | jq '.hooks.PreToolUse | length'`
Expected: 7

Run: `cat plugins/pev/hooks/hooks.json | jq '.hooks.PostToolUse | length'`
Expected: 1

- [ ] **Step 3: Commit**

```bash
git add plugins/pev/hooks/hooks.json
git commit -m "feat(pev): populate hooks.json with global hook registrations"
```

---

### Task 7: Strip hooks from agent frontmatter

**Files:**
- Modify: `plugins/pev/agents/pev-architect.md` — remove `hooks:` block (lines 30-48)
- Modify: `plugins/pev/agents/pev-builder.md` — remove `hooks:` block (lines 25-73)
- Modify: `plugins/pev/agents/pev-spike.md` — remove `hooks:` block (lines 25-67)
- Modify: `plugins/pev/agents/pev-reviewer.md` — remove `hooks:` block (lines 26-66)
- Modify: `plugins/pev/agents/pev-auditor.md` — remove `hooks:` block (lines 41-65)

- [ ] **Step 1: Strip pev-architect.md**

Remove from `hooks:` through the end of its YAML content (before `---`). Keep `name`, `description`, `model`, `maxTurns`, `tools`, `skills`.

- [ ] **Step 2: Strip pev-builder.md**

Same — remove `hooks:` block. The `skills:` key at line 24 stays.

- [ ] **Step 3: Strip pev-spike.md**

Same — remove `hooks:` block.

- [ ] **Step 4: Strip pev-reviewer.md**

Same — remove `hooks:` block.

- [ ] **Step 5: Strip pev-auditor.md**

Same — remove `hooks:` block.

- [ ] **Step 6: Validate no hooks remain**

```bash
for f in plugins/pev/agents/pev-{architect,builder,spike,reviewer,auditor}.md; do
  if grep -q '^hooks:' "$f"; then echo "FAIL: $f"; else echo "PASS: $f"; fi
done
```

- [ ] **Step 7: Validate frontmatter integrity**

```bash
for f in plugins/pev/agents/pev-{architect,builder,spike,reviewer,auditor}.md; do
  COUNT=$(grep -c '^---$' "$f")
  HAS_TOOLS=$(grep -c '^tools:' "$f")
  HAS_SKILLS=$(grep -c '^skills:' "$f")
  if [ "$COUNT" -ge 2 ] && [ "$HAS_TOOLS" -ge 1 ] && [ "$HAS_SKILLS" -ge 1 ]; then
    echo "PASS: $f"
  else
    echo "FAIL: $f (delimiters=$COUNT tools=$HAS_TOOLS skills=$HAS_SKILLS)"
  fi
done
```

- [ ] **Step 8: Commit**

```bash
git add plugins/pev/agents/pev-{architect,builder,spike,reviewer,auditor}.md
git commit -m "feat(pev): strip hooks from agent frontmatter (now in hooks.json)"
```

---

### Task 8: Update orchestrator reference

**Files:**
- Modify: `plugins/pev/templates/pev-orchestrator-reference.md:54-76` (State File section)

- [ ] **Step 1: Replace State File section**

Replace lines 54-76 with updated documentation that:
- References the template file `${CLAUDE_PLUGIN_ROOT}/templates/pev-state.template.json`
- Shows the new format with `budgets` block
- Explains the template-copy workflow (copy once, update counter_file per dispatch)
- Documents phase extraction from counter_file
- Documents `^anchored$` regex for built-in tools in allowlists
- Mentions the new hooks: `write-gate` and `destructive-cortex-gate`

- [ ] **Step 2: Validate**

Run: `grep -c 'pev-state.template.json' plugins/pev/templates/pev-orchestrator-reference.md`
Expected: at least 1

- [ ] **Step 3: Commit**

```bash
git add plugins/pev/templates/pev-orchestrator-reference.md
git commit -m "docs(pev): update orchestrator reference for new state file format"
```

---

### Task 9: Update orchestrator skill

**Files:**
- Modify: `plugins/pev/skills/pev-cycle/SKILL.md:37` (Phase 1 state file creation)
- Modify: `plugins/pev/skills/pev-cycle/SKILL.md:122` (Phase 7 auditor state file)

- [ ] **Step 1: Update Phase 1 instruction**

Replace line 37:
```
**Write `.pev-state.json` to the worktree root** (cwd after `EnterWorktree`) — see ref: `state-file`. Include `worktree_path`, `cycle_doc_id` (`cortex::docs.pev-cycles.{cycle-id}`), and `counter_file` for the Architect. Hooks read the `cwd` field from their input and find `.pev-state.json` at that root. Per-worktree state enables parallel PEV cycles.
```

With:
```
**Write `.pev-state.json` to the worktree root** (cwd after `EnterWorktree`) — see ref: `state-file`. Read the template from `${CLAUDE_PLUGIN_ROOT}/templates/pev-state.template.json`, fill `cycle_id`, `cycle_doc_id` (`cortex::docs.pev-cycles.{cycle-id}`), `worktree_path`, and set `counter_file` for the Architect. The `budgets` block from the template stays unchanged. Hooks read the `cwd` field from their input and find `.pev-state.json` at that root. Per-worktree state enables parallel PEV cycles.
```

- [ ] **Step 2: Update Phase 7 instruction**

Replace line 122:
```
When clear, write `.pev-state.json` to the main repo root with `cycle_id`, `cycle_doc_id`, and `counter_file` for the Auditor (no `worktree_path`).
```

With:
```
When clear, write `.pev-state.json` to the main repo root. Read the template from `${CLAUDE_PLUGIN_ROOT}/templates/pev-state.template.json`, fill `cycle_id`, `cycle_doc_id`, set `counter_file` for the Auditor, and leave `worktree_path` empty (Auditor runs on main).
```

- [ ] **Step 3: Commit**

```bash
git add plugins/pev/skills/pev-cycle/SKILL.md
git commit -m "docs(pev): update orchestrator skill to reference state template"
```

---

### Task 10: Update spike skill

**Files:**
- Modify: `plugins/pev/skills/pev-spike/SKILL.md:48-59` (Step 4: Write .pev-state.json)
- Modify: `plugins/pev/skills/pev-spike/SKILL.md` (add write-gate and destructive-cortex-gate tests)

- [ ] **Step 1: Update Step 4 to use template**

Replace lines 48-59 with instructions to read the template and fill cycle-specific fields:
```markdown
### 4. Write `.pev-state.json`

Read the template from `${CLAUDE_PLUGIN_ROOT}/templates/pev-state.template.json`. Fill the cycle-specific fields and write to cwd (worktree root):

- `cycle_id`: `"pev-spike"`
- `cycle_doc_id`: `"cortex::docs.pev-cycles.pev-spike"`
- `worktree_path`: `"{worktree_path}"`
- `counter_file`: `"/tmp/pev-spike-test-1"`

The `budgets` block stays unchanged from the template.
```

- [ ] **Step 2: Add write-gate and destructive-cortex-gate tests**

Add new tests to the spike agent dispatch prompt between the existing scope tests and budget tests:

```
Test 5b — write-gate (spike allows): Write is allowed in spike phase.
  Call: Write(file_path="{worktree_path}/write-gate-test.txt", content="write gate test")
  Expected: ALLOWED (spike is a code-write agent)
  Record: allowed=true/false

Test 5c — destructive-cortex-gate: Builder-blocked cortex tools are allowed in spike.
  Call: cortex_search(project_root="{worktree_path}", query="test")
  Expected: ALLOWED (spike allows all cortex read tools)
  Record: allowed=true/false
```

Update the results format total count and results table template accordingly.

- [ ] **Step 3: Commit**

```bash
git add plugins/pev/skills/pev-spike/SKILL.md
git commit -m "docs(pev): update spike skill for template workflow and new hook tests"
```

---

### Task 11: Version bump and re-cache

**Files:**
- Modify: `plugins/pev/.claude-plugin/plugin.json` (line 4)
- Modify: `.claude-plugin/marketplace.json` (lines 8 and 15)

- [ ] **Step 1: Bump version in plugin.json**

Change `"version": "1.6.0"` to `"version": "1.6.1"` in `plugins/pev/.claude-plugin/plugin.json`.

- [ ] **Step 2: Bump version in marketplace.json**

Change both `"version": "1.6.0"` occurrences to `"version": "1.6.1"` in `.claude-plugin/marketplace.json` (metadata.version on line 8 and plugins[0].version on line 15).

- [ ] **Step 3: Commit**

```bash
git add plugins/pev/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "v1.6.1: migrate hooks from agent frontmatter to hooks.json"
```

- [ ] **Step 4: Re-cache the plugin**

The user will need to reinstall/update the plugin so Claude Code picks up the new version in `~/.claude/plugins/cache/pev-agent-nexus/pev/1.6.1/`.

- [ ] **Step 5: Start a fresh session and run `/pev-spike`**

This is the end-to-end test. It validates:
- Empty matcher `""` fires on all tools
- `cwd` in hook input resolves correctly inside worktree subagents
- Budget counter increments
- Gate blocks after budget exceeded
- Scope hooks enforce worktree/doc/cortex boundaries
- Write-gate blocks reviewer/auditor writes
- Destructive-cortex-gate blocks per-phase

If the spike passes, the migration is complete.

---

## Verification

After all tasks (1-10), before version bump:

```bash
# Structural checks
cat plugins/pev/hooks/hooks.json | jq . > /dev/null && echo "hooks.json: valid"
cat plugins/pev/templates/pev-state.template.json | jq . > /dev/null && echo "template: valid"
for f in plugins/pev/agents/pev-{architect,builder,spike,reviewer,auditor}.md; do
  ! grep -q '^hooks:' "$f" && echo "$f: hooks stripped" || echo "FAIL: $f"
done

# No-op tests (every script must exit 0 with no output when no state file)
for s in pev-tool-gate pev-tool-counter pev-write-gate pev-destructive-cortex-gate pev-bash-scope pev-worktree-scope pev-cortex-scope pev-doc-scope; do
  OUTPUT=$(echo '{"tool_name":"Read","cwd":"/tmp/nonexistent"}' | bash plugins/pev/hooks/$s.sh 2>&1)
  [ $? -eq 0 ] && [ -z "$OUTPUT" ] && echo "$s: no-op OK" || echo "FAIL: $s"
done
```

After version bump + re-cache (Task 11):

```
# Start a fresh Claude Code session, then:
/pev-spike
```

The spike exercises all hooks end-to-end. If it passes, the migration is complete.
