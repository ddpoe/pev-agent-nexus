# EnterWorktree + Hook Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual `git worktree add` with Claude Code's `EnterWorktree` tool so subagents inherit the worktree cwd and hooks find `.pev-state.json` at cwd root — no walk-up needed.

**Architecture:** `EnterWorktree(name="{cycle-id}")` creates `.claude/worktrees/{cycle-id}/` and moves session cwd there. `.pev-state.json` is written at cwd. Subagents inherit cwd, so hooks just read `$cwd/.pev-state.json`. For Auditor, orchestrator `ExitWorktree`s back to main and writes a fresh `.pev-state.json` at main root. Since cwd IS the worktree, agents don't need `git -C` or `cd {worktree_path}` — they just run `git`, `poetry run pytest`, etc. directly.

**Tech Stack:** Bash hooks, Markdown skill/reference docs

---

## File Structure

| File | Action | Change |
|------|--------|--------|
| `plugins/pev/hooks/pev-tool-counter.sh` | Modify | Use `.cwd` from hook input instead of `CLAUDE_PROJECT_DIR`, delete walk-up loop |
| `plugins/pev/hooks/pev-tool-gate.sh` | Modify | Same |
| `plugins/pev/hooks/pev-doc-scope.sh` | Modify | Same |
| `plugins/pev/hooks/pev-bash-scope.sh` | Modify | Same |
| `plugins/pev/hooks/pev-worktree-scope.sh` | Modify | Same |
| `plugins/pev/hooks/pev-cortex-scope.sh` | Modify | Same |
| `plugins/pev/templates/pev-orchestrator-reference.md` | Modify | `EnterWorktree`/`ExitWorktree`, update paths/branch names, simplify dispatch prompts (no `-C`, no `cd`) |
| `plugins/pev/skills/pev-cycle/SKILL.md` | Modify | Phase 1: `EnterWorktree`. Phase 6: `ExitWorktree` before merge. Path updates. |
| `plugins/pev/skills/pev-builder/SKILL.md` | Modify | Remove `git -C {worktree_path}` → `git`. Remove `cd {worktree_path} &&` → run directly. Update anti-pattern path. |
| `plugins/pev/skills/pev-reviewer/SKILL.md` | Modify | Same simplifications as Builder. |
| `plugins/pev/agents/pev-builder.md` | Modify | Remove `-C {worktree}` from agent description. |

---

### Task 1: Fix all 6 hooks — use cwd instead of CLAUDE_PROJECT_DIR

**Files:**
- Modify: `plugins/pev/hooks/pev-tool-counter.sh:18-29`
- Modify: `plugins/pev/hooks/pev-tool-gate.sh:22-33`
- Modify: `plugins/pev/hooks/pev-doc-scope.sh:9-18`
- Modify: `plugins/pev/hooks/pev-bash-scope.sh:12-21`
- Modify: `plugins/pev/hooks/pev-worktree-scope.sh:10-19`
- Modify: `plugins/pev/hooks/pev-cortex-scope.sh:9-18`

In each hook, replace the `CLAUDE_PROJECT_DIR` + walk-up block:

```bash
# OLD (broken — CLAUDE_PROJECT_DIR always set, walk-up never runs)
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  while [ -n "$PROJECT_ROOT" ] && [ "$PROJECT_ROOT" != "/" ]; do
    [ -f "$PROJECT_ROOT/.pev-state.json" ] && break
    PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
  done
fi
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

With:

```bash
# NEW — cwd IS the worktree root (set by EnterWorktree), state file is right there
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

- [ ] **Step 1: Update `pev-tool-counter.sh`**

Replace lines 18-29 (the comment `# Counter file from .pev-state.json` through `STATE_FILE=...` line). The replacement block is:

```bash
# Counter file from .pev-state.json (lives at cwd root — set by EnterWorktree)
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

Everything after (`if [ -f "$STATE_FILE" ]`, counter logic, warnings) stays unchanged.

- [ ] **Step 2: Update `pev-tool-gate.sh`**

Replace lines 22-33 (same pattern). The replacement block is:

```bash
# Counter file from .pev-state.json (lives at cwd root — set by EnterWorktree)
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

- [ ] **Step 3: Update `pev-doc-scope.sh`**

Replace lines 9-18. The replacement block is:

```bash
# Resolve .pev-state.json (lives at cwd root — set by EnterWorktree)
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

- [ ] **Step 4: Update `pev-bash-scope.sh`**

Replace lines 12-21. The replacement block is:

```bash
# Resolve .pev-state.json (lives at cwd root — set by EnterWorktree)
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

- [ ] **Step 5: Update `pev-worktree-scope.sh`**

Replace lines 10-19. The replacement block is:

```bash
# Resolve .pev-state.json (lives at cwd root — set by EnterWorktree)
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

- [ ] **Step 6: Update `pev-cortex-scope.sh`**

Replace lines 9-18. The replacement block is:

```bash
# Resolve .pev-state.json (lives at cwd root — set by EnterWorktree)
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

- [ ] **Step 7: Commit**

```bash
git add plugins/pev/hooks/pev-tool-counter.sh plugins/pev/hooks/pev-tool-gate.sh plugins/pev/hooks/pev-doc-scope.sh plugins/pev/hooks/pev-bash-scope.sh plugins/pev/hooks/pev-worktree-scope.sh plugins/pev/hooks/pev-cortex-scope.sh
git commit -m "fix(hooks): use cwd from hook input instead of CLAUDE_PROJECT_DIR

CLAUDE_PROJECT_DIR always points to the main repo root, so hooks
could never find .pev-state.json in worktree subdirectories. Now
hooks read cwd from the hook input JSON, which reflects the actual
session directory (set to worktree root by EnterWorktree).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Update orchestrator reference for EnterWorktree

**Files:**
- Modify: `plugins/pev/templates/pev-orchestrator-reference.md`

- [ ] **Step 1: Update Naming Conventions section**

Old:
```
Worktree path: pev-worktrees/{cycle-id}
Branch name: pev/{cycle-id}
```

New:
```
Worktree path: .claude/worktrees/{cycle-id}
Branch name: worktree-{cycle-id}
```

- [ ] **Step 2: Update State File section**

Old:
> Write `.pev-state.json` to the **worktree root** (`pev-worktrees/{cycle-id}/.pev-state.json`) before each subagent dispatch. The doc-scope, cortex-scope, worktree-scope, and tool-budget hooks all find this file via walk-up from the agent's cwd.

New:
> Write `.pev-state.json` to the **worktree root** (cwd after `EnterWorktree`) before each subagent dispatch. The hooks read the `cwd` field from their input and find `.pev-state.json` at that root.

Old:
> For the **Auditor phase only** (runs on main after worktree is removed), write `.pev-state.json` to the **main repo root**.

Keep this line — Auditor behavior is unchanged. A fresh `.pev-state.json` is written to the main repo root for the Auditor.

- [ ] **Step 3: Update Worktree Commands section**

Replace manual worktree creation:

Old:
```bash
git worktree add -b pev/{cycle-id} pev-worktrees/{cycle-id} HEAD
```

New:
```
EnterWorktree(name="{cycle-id}")
```
Add note: Creates `.claude/worktrees/{cycle-id}/` with branch `worktree-{cycle-id}` based on HEAD. Moves session cwd to the worktree.

Update setup commands — no `-C` flags needed since cwd is the worktree:

Old:
```bash
poetry install --no-root -C pev-worktrees/{cycle-id}
```

New:
```bash
poetry install --no-root
```

Old:
```bash
if [ -f pev-worktrees/{cycle-id}/cortex/viz/static/ts/package.json ]; then
  cd pev-worktrees/{cycle-id}/cortex/viz/static/ts && npm install
fi
```

New:
```bash
if [ -f cortex/viz/static/ts/package.json ]; then
  cd cortex/viz/static/ts && npm install && cd -
fi
```

`cortex_checkout` call stays the same — it needs both `main_repo_path` and `worktree_path` as absolute paths.

- [ ] **Step 4: Update Merge Commands section**

Add `ExitWorktree` before merge. Update safety-net commit paths and branch name:

Old:
```bash
git -C pev-worktrees/{cycle-id} status --porcelain
```

New:
```bash
git status --porcelain
```
(Still in worktree at this point — ExitWorktree comes after safety-net commit.)

Old:
```bash
git merge --no-commit --no-ff pev/{cycle-id}
```

New (after ExitWorktree, back on main):
```bash
git merge --no-commit --no-ff worktree-{cycle-id}
```

- [ ] **Step 5: Update Merge Cleanup section**

New Phase 6 flow:

1. Safety-net commit (cwd is still the worktree):
```bash
git status --porcelain
# If non-empty:
git add -A
git commit -m "PEV: commit uncommitted changes before merge ({cycle-id})"
```
2. `ExitWorktree(action="keep")` — returns to main repo root
3. `git merge --no-commit --no-ff worktree-{cycle-id}`
4. `cortex_build` + `cortex_check` on main
5. Commit with structured message
6. Cleanup:
```bash
git worktree remove .claude/worktrees/{cycle-id}
git branch -d worktree-{cycle-id}
```

- [ ] **Step 6: Update Dispatch Prompts — Builder**

Old:
```
Your working directory is: {worktree_path}
Use absolute paths rooted there. Use git -C {worktree_path} for git commands.
For pytest: cd {worktree_path} && poetry run pytest (cd is required so Python imports worktree code).
```

New:
```
Your working directory is: {worktree_path}
Your cwd is already set to this directory. Use git commands directly (no -C flag needed).
For pytest: poetry run pytest (cwd is already the worktree, so imports are correct).
```

- [ ] **Step 7: Update Dispatch Prompts — Reviewer**

Same pattern — remove `cd {worktree_path} &&` from pytest instructions, remove `-C {worktree_path}` from git instructions.

- [ ] **Step 8: Replace all remaining `pev-worktrees/` and `pev/{cycle-id}` branch references**

Search and replace throughout the file:
- `pev-worktrees/{cycle-id}` → `.claude/worktrees/{cycle-id}`
- `pev-worktrees/` → `.claude/worktrees/` (in general references)
- `pev/{cycle-id}` (as branch name) → `worktree-{cycle-id}`

Be careful to distinguish `pev/{cycle-id}` as a branch name vs `pev-cycles/{cycle-id}` as a docs path — only branch names change.

- [ ] **Step 9: Commit**

```bash
git add plugins/pev/templates/pev-orchestrator-reference.md
git commit -m "feat(orchestrator-ref): switch to EnterWorktree, simplify dispatch prompts

Replace git worktree add with EnterWorktree tool. Worktrees now at
.claude/worktrees/{cycle-id} with branch worktree-{cycle-id}. Since
cwd IS the worktree, dispatch prompts drop -C flags and cd prefixes.
Add ExitWorktree before merge in Phase 6.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Update pev-cycle SKILL.md

**Files:**
- Modify: `plugins/pev/skills/pev-cycle/SKILL.md`

- [ ] **Step 1: Update Phase 1 (Intake)**

Replace worktree creation:

Old:
> **Create worktree and set up environment** (see ref: `worktree-commands`): `git worktree add`, `poetry install --no-root` (install deps without the project itself), `cortex_checkout` to copy cortex DB into worktree.

New:
> **Create worktree and set up environment**: Call `EnterWorktree(name="{cycle-id}")` — this creates the worktree and moves cwd there. Then `poetry install --no-root`, `cortex_checkout` to copy cortex DB. See ref: `worktree-commands`.

Replace state file location:

Old:
> **Write `.pev-state.json` to the worktree root** (`pev-worktrees/{cycle-id}/.pev-state.json`)

New:
> **Write `.pev-state.json` to the worktree root** (cwd after `EnterWorktree`)

- [ ] **Step 2: Update Phase 6 (Merge)**

Old:
> Safety-net commit: check worktree for uncommitted changes and commit them before merging (see ref: `merge-commands`). **Call `ExitWorktree(action="keep")`** to return to main repo root. Merge worktree branch into main, remove worktree/branch.

(The safety-net part was already added earlier in this branch. Now add the ExitWorktree instruction.)

New:
> Safety-net commit: check worktree for uncommitted changes and commit them before merging (see ref: `merge-commands`). Call `ExitWorktree(action="keep")` to return to main repo root. Merge worktree branch into main, remove worktree/branch. Rebuild cortex on main. Single commit with structured message (see ref: `commit-format`). Capture commit SHA.

- [ ] **Step 3: Replace remaining path/branch references**

Replace `pev-worktrees/` with `.claude/worktrees/` and `pev/{cycle-id}` (as branch) with `worktree-{cycle-id}` throughout the file.

- [ ] **Step 4: Commit**

```bash
git add plugins/pev/skills/pev-cycle/SKILL.md
git commit -m "feat(pev-cycle): use EnterWorktree in Phase 1, ExitWorktree in Phase 6

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Simplify Builder and Reviewer skills — remove -C and cd worktree

**Files:**
- Modify: `plugins/pev/skills/pev-builder/SKILL.md`
- Modify: `plugins/pev/skills/pev-reviewer/SKILL.md`
- Modify: `plugins/pev/agents/pev-builder.md`

- [ ] **Step 1: Update Builder SKILL.md — commit instructions (Step 4)**

Old (lines 154-156):
```bash
# These are SEPARATE Bash tool calls — do NOT chain with &&
git -C {worktree_path} add -A
git -C {worktree_path} commit -m "PEV Builder: {brief summary of changes}"
```

New:
```bash
# These are SEPARATE Bash tool calls — do NOT chain with &&
git add -A
git commit -m "PEV Builder: {brief summary of changes}"
```

- [ ] **Step 2: Update Builder SKILL.md — CONTINUING section (line 220)**

Old:
```
git -C {worktree_path} add -A
git -C {worktree_path} commit
```

New:
```
git add -A
git commit
```

- [ ] **Step 3: Update Builder SKILL.md — Constraints section (line 249)**

Old:
> **Commit before returning.** Stage and commit all changes (separate Bash calls: `git -C {worktree_path} add -A` then `git -C {worktree_path} commit -m "..."`) so the orchestrator can merge via `git merge`.

New:
> **Commit before returning.** Stage and commit all changes (separate Bash calls: `git add -A` then `git commit -m "..."`) so the orchestrator can merge via `git merge`.

- [ ] **Step 4: Update Builder SKILL.md — Bash conventions (lines 258-263)**

Old:
```
- **git:** Use `git -C {worktree_path}` for all git commands (e.g., `git -C /path/to/worktree diff`). Issue each git command as a **separate Bash tool call** — never chain with `&&` or `;`.
- **pytest:** Always run from the worktree directory: `cd {worktree_path} && poetry run pytest tests/ -x -q`. The `cd` is **required** so that Python imports the worktree's code, not the main repo's.
  - **NEVER run pytest from the main repo with worktree test paths** (e.g., `cd /main/repo && poetry run pytest pev-worktrees/.../tests/...`). This imports the main repo's code, not your worktree changes, producing false passes or phantom failures.
  - **When tests fail, debug in the worktree.** Test failures mean your code is wrong — read the traceback, check your imports, fix the code. Do not switch to running from the main repo as a workaround. Do not try `poetry env info`, `sys.path` checks, or `python -m pytest` as alternatives — these are distractions. The worktree setup is correct; your code has a bug.
- **Other commands:** Pass absolute worktree paths as arguments where possible (e.g., `poetry run python {worktree_path}/scripts/foo.py`).
```

New:
```
- **git:** Issue each git command as a **separate Bash tool call** — never chain with `&&` or `;`. No `-C` flag needed — your cwd is already the worktree.
- **pytest:** Run directly: `poetry run pytest tests/ -x -q`. Your cwd is the worktree, so Python imports the correct code.
  - **When tests fail, debug in the worktree.** Test failures mean your code is wrong — read the traceback, check your imports, fix the code. Do not try `poetry env info`, `sys.path` checks, or `python -m pytest` as alternatives — these are distractions. The worktree setup is correct; your code has a bug.
- **Other commands:** Run directly — cwd is the worktree (e.g., `poetry run python scripts/foo.py`).
```

- [ ] **Step 5: Update Reviewer SKILL.md — Guidelines (lines 244-250)**

Old:
```
- **Run the tests**: Use `cd {worktree_path} && poetry run pytest {test_file}` to verify tests actually pass. The `cd` is **required** so that `poetry run` activates the worktree's venv and Python imports the worktree's code, not the main repo's. A review that says PASS on a failing test is a review failure.
- **Bash conventions for worktree commands:**
  - **git:** Use `git -C {worktree_path}` for all git commands (e.g., `git -C /path/to/worktree diff`). Issue each git command as a **separate Bash tool call** — never chain with `&&` or `;`.
  - **pytest:** Always run from the worktree directory: `cd {worktree_path} && poetry run pytest tests/ -x -q`. The `cd` is **required** so that Python imports the worktree's code, not the main repo's.
    - **NEVER run pytest from the main repo with worktree test paths** (e.g., `cd /main/repo && poetry run pytest pev-worktrees/.../tests/...`). This imports the main repo's code, not the worktree changes, producing false passes or phantom failures.
    - **When tests fail, debug in the worktree.** Read the traceback and fix the code. Do not switch to running from the main repo as a workaround — the worktree setup is correct; the code has a bug.
  - **Other commands:** Pass absolute worktree paths as arguments where possible.
```

New:
```
- **Run the tests**: Use `poetry run pytest {test_file}` to verify tests actually pass. Your cwd is the worktree, so imports are correct. A review that says PASS on a failing test is a review failure.
- **Bash conventions:**
  - **git:** Issue each git command as a **separate Bash tool call** — never chain with `&&` or `;`. No `-C` flag needed — your cwd is the worktree.
  - **pytest:** Run directly: `poetry run pytest tests/ -x -q`.
    - **When tests fail, debug in the worktree.** Read the traceback and fix the code — the worktree setup is correct; the code has a bug.
  - **Other commands:** Run directly — cwd is the worktree.
```

- [ ] **Step 6: Update Builder agent definition (`pev-builder.md`)**

Old (line 82):
> You commit before returning (separate Bash calls: `git -C {worktree} add -A` then `git -C {worktree} commit -m "..."`) so the orchestrator can merge via `git merge`.

New:
> You commit before returning (separate Bash calls: `git add -A` then `git commit -m "..."`) so the orchestrator can merge via `git merge`. Your cwd is already the worktree.

- [ ] **Step 7: Commit**

```bash
git add plugins/pev/skills/pev-builder/SKILL.md plugins/pev/skills/pev-reviewer/SKILL.md plugins/pev/agents/pev-builder.md
git commit -m "refactor(skills): simplify worktree commands — cwd is the worktree

Since EnterWorktree sets cwd to the worktree, agents no longer need
git -C {worktree_path} or cd {worktree_path} prefixes. Commands run
directly from cwd.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Verify — no stale references

- [ ] **Step 1: Search for stale `pev-worktrees` references**

```bash
grep -rn "pev-worktrees" plugins/pev/
```

Expected: zero results. If any found, fix them.

- [ ] **Step 2: Search for stale `CLAUDE_PROJECT_DIR` in hooks**

```bash
grep -n "CLAUDE_PROJECT_DIR" plugins/pev/hooks/*.sh
```

Expected: only appears in fallback lines (`[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"`), NOT as the primary lookup.

- [ ] **Step 3: Search for stale `pev/` branch references**

```bash
grep -rn 'pev/' plugins/pev/ | grep -v 'pev-cycles' | grep -v 'pev-state' | grep -v 'pev-active' | grep -v 'pev-tool' | grep -v 'pev-doc' | grep -v 'pev-bash' | grep -v 'pev-worktree' | grep -v 'pev-cortex' | grep -v 'pev-builder' | grep -v 'pev-reviewer' | grep -v 'pev-architect' | grep -v 'pev-auditor' | grep -v 'pev-cycle' | grep -v 'PLUGIN_ROOT'
```

Look for `pev/{cycle-id}` used as a branch name that should now be `worktree-{cycle-id}`.

- [ ] **Step 4: Fix any remaining issues and commit if needed**
