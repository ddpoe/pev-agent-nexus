# Plugin-Hook Troubleshooting Guide

Reference for debugging Claude Code plugin hooks in the `pev-agent-nexus` marketplace. Covers the two test plugins, their layering, Windows-specific pitfalls, and a catalog of failure modes we've hit and fixed.

Symptom-first where possible — scan the section headings, find what matches, read the fix.

---

## 1. Overview — two plugins, two test layers

```
pev-agent-nexus (marketplace)
├── plugins/pev/         Real PEV workflow + /pev-spike (11-test integration)
└── plugins/hook-spike/  Low-level plugin-hook infra test harness
```

Layer cake:

- **Layer 1 — hook infrastructure**: can a plugin's `hooks.json` fire at all? Does `${CLAUDE_PLUGIN_ROOT}` expand? Does `agent_type` reach the hook? → `hook-spike`.
- **Layer 2 — PEV-specific behavior**: do the worktree/bash/doc/cortex scope hooks enforce correctly? Does the tool-budget counter + allowlist gate work per-agent? → `pev-spike`.

**Always debug bottom-up.** If `/hs-heartbeat` fails, `/pev-spike` cannot meaningfully pass. Don't chase PEV hook bugs until Layer 1 is green.

---

## 2. `hook-spike` plugin

Minimal harness that isolates **one variable at a time**. Each spike agent uses a unique tool (Read / Glob / Grep / none) to avoid hooks from different tests cross-firing. Hooks use **inline commands** in `hooks.json` (no separate `.sh` files) so the thing under test is variable expansion, not file-path resolution.

### Agents

| Agent | Trigger | Hook placement | What it tests |
|---|---|---|---|
| `hs-heartbeat` | `Bash` | plugin `hooks.json` (PreToolUse + PostToolUse) | **Start here**. Does plugin hooks.json fire at all? |
| `hs-hooksjson-control` | `Read` | plugin `hooks.json` PreToolUse(Read) | Baseline: `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PROJECT_DIR}` expansion in hooks.json |
| `hs-frontmatter-plugin-root` | `Glob` | agent frontmatter | Does agent-frontmatter hook fire with `${CLAUDE_PLUGIN_ROOT}`? (Answer: no — see §7) |
| `hs-frontmatter-project-dir` | `Grep` | agent frontmatter | Does agent-frontmatter hook fire with `${CLAUDE_PROJECT_DIR}`? |
| `hs-subagent-stop` | (none) | agent frontmatter `SubagentStop` | Does frontmatter SubagentStop fire on subagent return? |

### Driver skills

| Skill | Purpose |
|---|---|
| `/hs-heartbeat` | Single-agent smoke test. Run this FIRST whenever you suspect hook infra is broken. |
| `/hook-spike` | Dispatches all four matrix agents in parallel. Reads canary files. Returns pass/fail table + what each env var expanded to. |

### Diagnostic side-effects

`hook-spike`'s `hooks.json` also dumps every hook's stdin JSON to `/tmp/hook-spike/input-<event>-<tool>.json`. You can **reuse these captures** to construct realistic hook-input JSON for testing other hooks standalone. Overwrites on each fire, so pay attention to which event you want.

Canary contents include: `fired=true`, `pwd=...`, `CLAUDE_PLUGIN_ROOT=...`, `CLAUDE_PROJECT_DIR=...`. If the var is absent, you see `<UNSET>`.

---

## 3. `pev-spike` agent (inside `pev` plugin)

Integration test for the real PEV hook behavior. Exercises the scope hooks, budget counter, gate, and allowlists end-to-end in a disposable worktree.

### 11-test protocol

| # | Test | What it exercises |
|---|---|---|
| 1 | worktree-scope: Write outside worktree blocked | `pev-worktree-scope.sh` + cwd resolution |
| 2 | bash-scope: `cd /tmp` blocked | `pev-bash-scope.sh` + `cd`-target extraction |
| 3 | cortex-scope: wrong `project_root` blocked | `pev-cortex-scope.sh` + path comparison |
| 4 | doc-scope: write to wrong doc blocked | `pev-doc-scope.sh` + `.pev-state.json` `cycle_doc_id` |
| 5 | doc-scope: write to cycle manifest allowed | hook allow path (cortex layer may still 404 if manifest unindexed — not a hook failure) |
| 6a | budget warning advisory (3/7) | `pev-tool-counter.sh` warn threshold |
| 6b | budget urgent advisory (5/7) | `pev-tool-counter.sh` urgent threshold |
| 6c | budget gate advisory (7/7) | `pev-tool-counter.sh` + `pev-tool-gate.sh` at threshold |
| 7 | gate blocks non-allowlisted tool | `pev-tool-gate.sh` block path |
| 8 | allowlist: Write works after gate | gate allowlist pass-through |
| 9 | allowlist: `cortex_update_section` works after gate | gate + doc-scope stacking |

### Driver skill

`/pev-spike` — orchestrates worktree creation, state file setup, subagent dispatch, result collection, cleanup. See `plugins/pev/skills/pev-spike/SKILL.md` for the exact protocol.

### Why keep pev-spike detailed

Its tests are deliberately specific. When a hook regresses, the matrix tells you *which* hook broke. This saved hours in the v1.8.x fix arc — each failure pointed at a single script. Do not collapse it into a smaller test.

---

## 4. How the two layers interface

**Shared infrastructure:**

- Both plugins register hooks in `plugins/<name>/hooks/hooks.json` at plugin root, using `${CLAUDE_PLUGIN_ROOT}/hooks/...` paths.
- Both rely on the **hook input JSON** delivered on stdin, which carries `agent_type`, `agent_id`, `cwd`, `tool_name`, `tool_input`, `hook_event_name`.
- Both write evidence under `/tmp/` — `hook-spike` uses `/tmp/hook-spike/`, `pev` uses `/tmp/pev-counter-<agent_id>.txt` and (when diagnostic logging is on) `/tmp/pev-hook-debug.log`.

**Test targeting:**

- `hook-spike` asks: *is the platform giving me what I expect?* Its hooks are inline, stateless, and as minimal as possible. If these don't work, nothing else will.
- `pev-spike` asks: *does the PEV plugin's logic correctly enforce its intended policies?* It depends on Layer 1 already being green.

**When something breaks, always** — run `/hs-heartbeat`. If the plugin hooks.json isn't firing at all for the simplest case, no amount of PEV debugging will help.

---

## 5. Architecture invariants

Future hooks in this marketplace must respect these patterns, or they won't work on the plugin path.

### 5.1 Registration

- **Hooks live in `plugins/<name>/hooks/hooks.json`.** Agent-frontmatter hooks do not fire in marketplace-installed plugins (see §7.1).
- **Paths use `${CLAUDE_PLUGIN_ROOT}/hooks/...`.** Confirmed by hook-spike to expand correctly.
- **Matchers are full-string regex.** See §7.2.

### 5.2 Dispatch

- PEV hook scripts gate on the `agent_type` field from stdin JSON. If it doesn't start with `pev:`, the script exits 0 (pass-through). This keeps hooks silent for the orchestrator session and for unrelated subagents.
- Per-agent config (budgets, allowlists) lives inside the hook script, dispatched via a `case "$AGENT_TYPE"` block. Do NOT put per-agent config in `.pev-state.json`.

### 5.3 State

- `.pev-state.json` at the worktree root carries cycle-scoped data (`cycle_id`, `cycle_doc_id`, `worktree_path`). Written once per cycle.
- Counter files are keyed on `agent_id` (unique per subagent invocation): `/tmp/pev-counter-<agent_id>.txt`. Auto-cleaned by `pev-subagent-stop.sh`.
- Do NOT put counter paths in the state file. Do NOT try to use the state file to identify the current agent — it races with orchestrator tool calls.

### 5.4 Block signaling

- Reliable pattern: `echo "BLOCKED: reason" >&2; exit 2`
- Unreliable: `echo "{...hookSpecificOutput...}"` on stdout with no `exit 2` (see §7.4)

---

## 5.5 How Claude Code handles hook I/O

Get this model right and 80% of hook debugging clicks into place.

### The model: pipes, not files

A hook is NOT a long-running process that Claude writes state into. It's a **new bash process spawned per tool call**, wired up with pipes:

```
Claude Code process
  │
  │ (tool call triggers a matching hook)
  │
  ├─ spawns: bash ${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh
  │             ↑
  │             │ stdin pipe (ephemeral — closes when hook exits)
  │             │
  │             └─ Claude writes JSON payload:
  │                {"session_id":"...", "agent_type":"pev:pev-spike",
  │                 "agent_id":"xyz", "cwd":"C:\\...",
  │                 "tool_name":"Bash", "tool_input":{...}, ...}
  │
  │ (hook reads stdin, runs, exits)
  │
  └─ reads: exit code + stdout + stderr
```

The stdin JSON is **constructed in memory per hook invocation and streamed to the child's stdin pipe**. Claude Code never writes it to a file from its side. When the hook exits, the pipe closes and that payload is gone. The next hook invocation gets a brand-new process with a brand-new payload.

**Fields like `agent_type` and `agent_id` are not files you look up — they're keys in the JSON payload that Claude re-sends on every invocation.**

### Lifetime of identity fields

Claude Code tracks subagent context in its own memory for the lifetime of the subagent session, and stamps that identity into each hook invocation's stdin JSON:

```
orchestrator calls Agent(subagent_type="pev-spike")
  │
  ├─ Claude spawns subagent session internally
  │   (Claude remembers: "active subagent = pev:pev-spike, agent_id = xyz")
  │
  ├─ subagent calls Bash
  │   ├─ PreToolUse hook → stdin JSON has agent_type="pev:pev-spike"
  │   └─ PostToolUse hook → stdin JSON has agent_type="pev:pev-spike"
  │
  ├─ subagent calls Read
  │   └─ PreToolUse hook → stdin JSON has agent_type="pev:pev-spike"
  │
  ├─ subagent returns
  │   └─ SubagentStop hook → stdin JSON has agent_type="pev:pev-spike"
  │       (plus last_assistant_message, agent_transcript_path)
  │
  └─ (subagent session ends; Claude discards the context)
      orchestrator's next tool call → stdin JSON has NO agent_type
```

### Three identity fields in the stdin payload

Different scopes, useful to combine:

| Field | Scope | Uniqueness |
|---|---|---|
| `session_id` | Claude Code session (shared across orchestrator + its subagents) | One per `claude` process |
| `agent_id` | Subagent invocation | One per Agent-tool call — if you dispatch `pev-spike` twice, you get two `agent_id`s |
| `agent_type` | Agent definition used | Same value for every invocation of the same agent (e.g. `pev:pev-spike`) |

This is why `pev-tool-counter.sh` uses `agent_id` for counter files: it guarantees no collision when the orchestrator happens to dispatch two instances of the same agent in one session.

### What CAN'T be passed through the stdin channel

- You can't mutate the next hook's stdin from inside this hook. Claude constructs each payload fresh.
- You can't read another hook's stdin. The pipe closes with the process.
- You can't get state that persists across invocations via env vars — every hook process starts with a fresh environment inherited from Claude Code (which inherited from your shell). `export FOO=bar` inside a hook dies with that process.

For cross-invocation state, use the filesystem (see below).

### The three output channels

| Channel | How you write to it | Who reads it |
|---|---|---|
| **stdout** (fd 1, unredirected) | `echo "x"` with no redirect | Claude Code — parses for `{"hookSpecificOutput": {...}}` |
| **stderr** (fd 2) | `echo "x" >&2` | Claude Code — surfaces as denial reason iff `exit 2` |
| **filesystem** (file redirect) | `echo "x" >> /tmp/log` or `> /tmp/log` | Only whoever inspects the file later (you) |

Shell redirects (`>>`, `>`, `2>`) reassign the underlying file descriptor *before* any bytes leave the process. So `echo "x" >> /tmp/foo` writes nothing to stdout — the bytes are routed to the file instead. Claude Code sees an empty stdout pipe.

### How Claude Code treats stderr + exit code

Claude Code uses stderr as a **reason channel**, not a log channel — it's attached to the tool-call outcome:

| Exit code | Tool outcome | What happens to stderr |
|---|---|---|
| `0` | Tool runs normally | Discarded from the agent's view |
| `2` | Tool BLOCKED | Stderr becomes the `permissionDecisionReason` shown to the agent |
| Other non-zero | Error (tool still runs, fail-open) | Logged internally, not surfaced to the agent |

Two concrete observations from this session:

- `hs-heartbeat`'s hook does `echo '*** HOOK-SPIKE: PreToolUse(Bash) fired ***' >&2` then `exit 0`. The subagent explicitly reported *"No hook messages seen"* — stderr on exit 0 is invisible.
- `pev-worktree-scope.sh` does `echo "BLOCKED: Write/Edit target '...'" >&2 ; exit 2`. The spike recorded exactly that string as the hook_message in its results — stderr on exit 2 is surfaced as the block reason.

Same mechanism. Visibility depends entirely on exit code.

### How Claude Code treats stdout

stdout is a **structured injection channel**. Claude Code parses it as the hook-output schema.

- **Valid JSON with `additionalContext`** → injected into the agent's next turn as a system reminder. `pev-tool-counter.sh` uses this for budget advisories ("TOOL BUDGET: 3/7...") — the agent sees them.
- **Valid JSON with `permissionDecision: deny`** → signals a block, but in practice only reliably triggers one when combined with `exit 2`. Use stderr + exit 2 for blocks instead.
- **Non-JSON plaintext** → reaches Claude Code but fails to parse. Silently discarded.

### Why canary files are authoritative for debugging

Because the filesystem channel is **decoupled from Claude Code's surfacing logic entirely**:

- stderr on exit 0 is invisible to the agent
- stderr on other non-zero is invisible to the agent
- stdout without valid JSON is dropped
- A file on disk is always there — you can inspect it from any process, at any time

So when you add `echo "[trace]" >> /tmp/pev-hook-debug.log 2>/dev/null` to a hook, you get tracing that is **visible to you, invisible to the agent** — no influence on agent behavior, no noise in the transcript, always retrievable. This is why canary files and debug logs are the first tool to reach for when a hook seems to "not fire."

### Output cheat sheet

Pick by intent:

| Intent | Mechanism |
|---|---|
| Block a tool call | `echo "reason" >&2; exit 2` |
| Inject a non-blocking message to the agent | `echo '{"hookSpecificOutput":{"additionalContext":"..."}}'` on stdout, exit 0 |
| Debug trace for yourself | Redirect to file: `echo "..." >> /tmp/some-log 2>/dev/null` |
| Structured artifact for other tools to read | Write a file with a known format (canary) |

### One edge case worth knowing

If a hook process crashes with "command not found" or similar (exit 127 etc.), Claude Code typically surfaces a terse transcript notice like *"Hook PreToolUse completed with non-zero exit code: 127"*. Three distinct observables to keep straight:

- **Silent absence** → hook didn't fire at all (matcher miss, plugin not loaded, or hook gate exited 0 early)
- **Crash notice in transcript** → hook fired but blew up before doing useful work
- **Denial reason in transcript** → hook fired, decided to block, used `exit 2` correctly

---

## 5.6 Environment variables and state persistence

Env vars reach your hook in two ways, and neither is magic. State that survives across invocations is a separate concern — the filesystem — because the env channel is one-way.

### The inheritance chain

```
your shell env
      │
      │ (you run `claude`)
      ▼
Claude Code process env
      │
      │ (Claude spawns a hook)
      ▼
hook process env   ← sees everything above, plus CLAUDE_* vars
                     Claude injects for this hook
```

Hooks inherit whatever your shell had when you launched Claude. So if you `export PATH=/custom:$PATH` before `claude`, hooks see that custom PATH. If you start `claude` from an Anaconda-activated shell, hooks see Anaconda env vars.

### What Claude Code sets for you

Captured by `hook-spike`'s `hooksjson-control.env` canary, here's what Claude injects (values from this session):

| Variable | Scope | Example value | When set |
|---|---|---|---|
| `CLAUDECODE` | Marker that you're inside Claude Code | `1` | Always |
| `CLAUDE_CODE_ENTRYPOINT` | How the process was invoked | `sdk-cli` (from `claude -p`) | Always |
| `CLAUDE_CODE_EXECPATH` | Path to the claude binary | `C:\Users\...\claude.exe` | Always |
| `CLAUDE_PROJECT_DIR` | Consumer project root | `C:\Users\dap182\Documents\git\temp\workflow-canvas` | Always (points at the project claude was launched from) |
| `CLAUDE_PLUGIN_ROOT` | Root of the plugin this hook belongs to | `/c/Users/dap182/.claude/plugins/cache/pev-agent-nexus/hook-spike/0.1.0` | Only for plugin-scoped hooks (those registered via `plugins/<name>/hooks/hooks.json`) |
| `CLAUDE_PLUGIN_DATA` | Persistent per-plugin data dir | `/c/Users/dap182/.claude/plugins/data/hook-spike-pev-agent-nexus` | Plugin-scoped hooks only |

**Important distinction**: `CLAUDE_PLUGIN_ROOT` is *not* available in every hook — only in hooks that the plugin system invoked. If you register a hook in user-level `~/.claude/settings.json`, there's no plugin context, and `CLAUDE_PLUGIN_ROOT` is unset. Don't depend on it outside plugin hooks.

`CLAUDE_PLUGIN_DATA` is the right place for persistent per-plugin state (settings, caches) — survives session restarts, scoped to the plugin. Use `/tmp/` instead for transient per-run state (counters, debug logs) that should *not* survive.

### Adding your own custom env vars

Three mechanisms, increasing scope:

**1. One-shot per run** — prepend when launching claude:
```bash
PEV_SESSION_ID=xyz123 MSYS_NO_PATHCONV=1 claude -p "/pev-spike" ...
```
All hooks fired during that claude process see `PEV_SESSION_ID=xyz123`.

**2. Per-shell** — export first, then run claude:
```bash
export PEV_SESSION_ID=xyz123
claude       # and every subsequent claude invocation in this shell
```

**3. Per-project persistent** — settings.json `env` block:
```json
{
  "env": {
    "PEV_SESSION_ID": "xyz123",
    "PEV_DEBUG": "1"
  }
}
```
Placed in `<project>/.claude/settings.json` or `~/.claude/settings.json`. Claude Code injects these into every session launched from that scope. Good for stable per-project identifiers.

The hook itself can read them like any other env var:

```bash
SESSION_ID=${PEV_SESSION_ID:-unknown}
```

### What env CANNOT do

- **You cannot persist state between hook invocations via env.** Each hook is a fresh bash process; `export FOO=bar` inside the hook dies when the hook exits. The next hook starts with a fresh environment (the same one Claude inherited).
- **You cannot change Claude's env from inside a hook.** Claude Code doesn't re-read env from hook output — only the exit code and stdout/stderr.

For cross-invocation state, use the filesystem (next section).

### Inspecting env from inside a hook

Drop this single line into a hook during debugging to capture the full env at invocation time:

```bash
env | sort > /tmp/hook-env-$(date +%s).txt
```

Or, if you just want to check for a specific set of vars:

```bash
env | grep -E '^(CLAUDE_|PEV_)' > /tmp/hook-env.txt
```

Remember the file-redirect pattern from §5.5 — the `>` redirects fd 1 to a file before anything reaches Claude Code. No transcript noise, you read the file manually afterward.

You don't actually need to add this yourself for the initial check — `hook-spike`'s `pev-worktree-scope`-style hook already dumps env on every Read call to `/tmp/hook-spike/hooksjson-control.env`. Trigger any Read while the plugin is installed, inspect that file.

### State persistence patterns (the filesystem)

If env is one-way, and you want a counter or a "did I already do X" flag that survives across hook invocations in a session, write a file. The conventions we use in this marketplace:

| Purpose | Path pattern | Written by | Cleaned up by |
|---|---|---|---|
| Per-subagent tool counter | `/tmp/pev-counter-<agent_id>.txt` | `pev-tool-counter.sh` (PostToolUse) | `pev-subagent-stop.sh` (SubagentStop) |
| Debug trace across a full session | `/tmp/pev-hook-debug.log` | Any hook with the v1.8.2 diagnostic line | User, manually |
| Hook-input JSON captures (diagnostic) | `/tmp/hook-spike/input-<event>-<tool>.json` | `hook-spike` hooks via `cat > file` | Overwritten per invocation; cleared manually |
| Canary markers | `/tmp/hook-spike/<name>.fired` | `hook-spike` hooks via `printf > file` | User, manually |

The key design choices worth copying:

- **Key on `agent_id`, not `agent_type`**, when state is per-invocation. `agent_type` collides if the orchestrator dispatches the same agent twice in one session; `agent_id` never does.
- **Clean up in SubagentStop.** `pev-subagent-stop.sh` removes the counter file when the subagent returns — keeps `/tmp/` from accumulating stale per-run files across sessions.
- **Use `/tmp/` for transient, `CLAUDE_PLUGIN_DATA` for durable.** `/tmp/` is effectively a scratchpad — OK if it's lost. `CLAUDE_PLUGIN_DATA` persists across claude restarts and is the right place for caches or per-plugin config you genuinely want preserved.
- **Prefix filenames with your plugin name** to avoid collisions between plugins sharing `/tmp/` (`pev-counter-*`, not `counter-*`).

---

## 5.7 Project SOPs — the `.pev/` convention

Some PEV behavior varies per project and shouldn't be hardcoded in the plugin — doc taxonomies differ, test tiers differ, review emphasis differs. Those live in per-project SOP files under `<project_root>/.pev/`:

```
<project_root>/
  .pev/
    doc-review-guide.md    ← Doc Reviewer reads this
    test-policy.md         ← Architect, Builder, Reviewer read this
    review-criteria.md     ← Reviewer reads this (optional)
```

### Design principles

- **Git-tracked, not gitignored.** Worktrees check out the same tree as main — git-tracking means every worktree has the file at `{worktree_path}/.pev/...` automatically, so subagents running in worktrees see it without any copy-on-checkout step.
- **Plugin-shipped fallbacks.** Each SOP has a default at `${CLAUDE_PLUGIN_ROOT}/templates/<name>.md` that the skill reads if the project file doesn't exist. New projects work immediately; customization is opt-in.
- **Read-only for the plugin.** Skills read but never write these files. The user maintains them manually.

### Path resolution in skills

Convention in every PEV skill that reads an SOP:

```
Read {worktree_path}/.pev/<file>.md        — primary
Read ${CLAUDE_PLUGIN_ROOT}/templates/<file>.md  — fallback if primary missing
```

`{worktree_path}` is provided in each subagent's dispatch prompt. For the Auditor and Doc Reviewer (which run on main repo post-merge), substitute `${CLAUDE_PROJECT_DIR}` for `{worktree_path}`.

### What goes in each SOP

| File | Purpose | Used by |
|---|---|---|
| `doc-review-guide.md` | Project's doc taxonomy — categories, paths, review triggers, conventions | Doc Reviewer |
| `test-policy.md` | Test tiers, annotation contract, coverage expectations, budget | Architect, Builder, Reviewer |
| `review-criteria.md` (optional) | Project-specific code-review emphasis (logging conventions, anti-patterns) | Reviewer |

### Adding a new SOP

If a future skill needs project-specific config that doesn't fit the existing files:

1. Create `plugins/pev/templates/<new-sop>.md` as the plugin-shipped default
2. Update the relevant skill to read `{worktree_path}/.pev/<new-sop>.md` with fallback
3. Document it in this section
4. Update the TROUBLESHOOTING categories table above

Don't grow individual SOP files past ~3 concerns — split into separate files when they diverge.

---

## 6. Windows gotchas (explicit)

The Windows + git-bash + native-jq stack has three layers of path handling, each with its own assumptions. Here's the list we hit.

### 6.1 `cwd` in hook JSON is Windows-style

Claude Code passes `cwd` as `C:\Users\dap182\...\worktree`. Concatenating `/.pev-state.json` produces a mixed-slash path that `[ -f ]` can't resolve.

**Fix:**

```bash
PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty')
if command -v cygpath >/dev/null 2>&1; then
  PROJECT_ROOT=$(cygpath -u "$PROJECT_ROOT")
fi
STATE_FILE="$PROJECT_ROOT/.pev-state.json"
```

### 6.2 Native Windows jq cannot open POSIX paths

Once you've cygpath'd to `/c/Users/.../pev-state.json`, `[ -f ]` accepts it, but `jq -r '...' "$STATE_FILE"` silently returns empty because the Windows `jq.exe` binary can't open `/c/...`.

**Fix:** pipe file content via `cat`. jq reads stdin, doesn't care about paths:

```bash
# Wrong
WORKTREE_PATH=$(jq -r '.worktree_path' "$STATE_FILE")

# Right
WORKTREE_PATH=$(cat "$STATE_FILE" | jq -r '.worktree_path // empty')
```

### 6.3 `grep -oP` (PCRE) requires UTF-8 locale

In the hook execution environment, `grep -oP '...'` fails with `grep: -P supports only unibyte and UTF-8 locales` and exits 2. The capture is empty and the hook falls through.

**Fix:** use POSIX `sed` instead. Example — extracting the target of a `cd` command:

```bash
# Wrong (may fail depending on locale)
CD_TARGET=$(echo "$COMMAND" | grep -oP '^\s*cd\s+\K[^\s;&]+')

# Right
CD_TARGET=$(echo "$COMMAND" | sed -n 's/^[[:space:]]*cd[[:space:]]\+\([^[:space:];&]\+\).*/\1/p')
```

### 6.4 MSYS2 path conversion mangles `claude -p "/slash-command"`

In git-bash, `claude -p "/pev-spike"` can get rewritten to `claude -p "C:/Program Files/Git/pev-spike"` before `claude` sees it, and Claude then says "what should I do with this path?" The heuristic is context-sensitive; `/hs-heartbeat` sometimes passed through and `/hook-spike` did not.

**Fix:** always prefix with `MSYS_NO_PATHCONV=1`:

```bash
MSYS_NO_PATHCONV=1 claude -p "/pev-spike" --dangerously-skip-permissions ...
```

### 6.5 Bash heredocs strip `\\` silently (debug-only workaround)

*Only relevant when constructing synthetic hook-input JSON by hand for standalone hook testing. Production hooks never hit this.*

Constructing test JSON in a `<<'EOF'` heredoc — e.g. trying to write `"cwd":"C:\\Users\\..."` — produces single backslashes in the resulting file (`C:\Users\...`), which is **invalid JSON**. jq rejects it with `Invalid escape at line 1, column N`. This appears specific to the git-bash build on this system; a `<<'EOF'` heredoc should preserve `\\` literally, but here it doesn't.

**Fix for test-input construction:** use Python `json.dump` — it escapes correctly without any shell interference:

```python
import json
with open("C:/Users/.../test-input.json", "w") as f:
    json.dump({"cwd": "C:\\Users\\...", "agent_type": "pev:pev-spike"}, f)
```

Also: Python `open("/tmp/x.json")` uses Windows Python's cwd semantics. Pass an absolute Windows path (`C:/Users/dap182/AppData/Local/Temp/x.json`) to avoid surprise.

### 6.6 `/tmp` mapping

In git-bash on Windows, `/tmp` resolves to `C:\Users\<user>\AppData\Local\Temp`. Files written to `/tmp/foo.txt` from bash are readable from the Read tool at `C:\Users\<user>\AppData\Local\Temp\foo.txt`. Use `cygpath -w /tmp/foo.txt` to confirm the Windows equivalent when debugging.

---

## 7. Failure catalog

Things we tried that didn't work, plus the evidence and the fix.

### 7.1 Agent-frontmatter hooks silently no-op in plugin installs

**Symptom:** Every hook in `hooks:` blocks of `plugins/<name>/agents/<agent>.md` appears to do nothing. Budgets don't enforce, scope hooks don't block, SubagentStop doesn't fire.

**Evidence:** The `/hook-spike` matrix (PR #1, #2) confirmed with canary files: `hs-hooksjson-control` (hooks.json) fires; `hs-frontmatter-*` and `hs-subagent-stop` (all in agent frontmatter) do not.

**Fix:** Move every registration to `plugins/<name>/hooks/hooks.json`. Per-agent behavior goes inside the hook script, dispatched on `agent_type` from stdin.

### 7.2 Bare prefix matcher doesn't fire

**Symptom:** A hook registered with `"matcher": "mcp__cortex__"` does not fire for `mcp__cortex__cortex_source`. No error, no log entry.

**Evidence:** Absence of log entries in `/tmp/pev-hook-debug.log` for that matcher, despite the subagent clearly calling the tool.

**Fix:** Claude Code matchers appear to require full-string match. Use `"mcp__cortex__.*"` or an explicit alternation like `"mcp__cortex__cortex_source|mcp__cortex__cortex_graph"`.

### 7.3 `${CLAUDE_PLUGIN_ROOT}` in agent frontmatter is unclear

**Symptom:** Plugin-scoped hooks declared in agent frontmatter with `${CLAUDE_PLUGIN_ROOT}/hooks/...` may not expand. Unclear in docs.

**Fix:** Sidestep the question. Declare plugin hooks in `hooks.json` (where `${CLAUDE_PLUGIN_ROOT}` definitely works). For agent-specific behavior, dispatch inside the script on `agent_type`.

### 7.4 `hookSpecificOutput` on stdout without `exit 2`

**Symptom:** Hook prints `{"hookSpecificOutput":{"permissionDecision":"deny",...}}` to stdout and returns 0. Claude does not block the tool.

**Evidence:** `pev-bash-scope.sh` pre-v1.8.4 used this pattern for its block path; test 2 failed consistently even when the hook was clearly firing with the correct `CD_TARGET`.

**Fix:** Use the simpler pattern that every other working hook uses:

```bash
echo "BLOCKED: reason" >&2
exit 2
```

### 7.5 `.pev-state.json` as dispatch source races with orchestrator

**Symptom:** Every time the orchestrator makes a Bash or cortex call, hooks fire but the state file's "current agent" is stale or ambiguous. Pre-v1.8.0 the orchestrator had to "update counter_file for X phase" before every dispatch, which was fragile and would fail if the orchestrator itself called a tool mid-dispatch.

**Fix:** Use `agent_type` from hook input JSON directly. It's populated only when a subagent is executing the tool call, absent when the orchestrator is. Per-agent config branches inside the hook script. Counter files use `agent_id` (unique per invocation).

### 7.6 Hook stderr doesn't surface in subagent transcript

**Symptom:** You add `echo "debug: ..." >&2` to a hook. The subagent runs. You look at the transcript. The message is nowhere.

**Fix:** Canary files, not stderr, are the authoritative signal. Write `echo "..." >> /tmp/pev-hook-debug.log` or a canary marker file. **See §8.3 for the full re-enable recipe** — it's the most common debugging technique for misbehaving hooks.

```bash
echo "[$(date -Is)] hook=<name> pid=$$ agent_type=$AGENT_TYPE tool=$TOOL_NAME" >> /tmp/pev-hook-debug.log 2>/dev/null
```

### 7.7 Local agent files shadow plugin agents

**Symptom:** You install a plugin that provides agent `foo`, but when you dispatch it, the behavior matches an old version. `agent_type` comes through as bare `foo`, not `plugin:foo`.

**Fix:** Claude Code resolves `.claude/agents/<name>.md` before plugin-provided agents. Delete local copies when you want the plugin version. Verify by checking the `agent_type` field — plugin-loaded is `<plugin>:<agent>`; local-loaded is bare `<agent>`.

### 7.8 Stale plugin installs in other projects still count

**Symptom:** Your new plugin version doesn't take effect. `claude plugin list` shows installs at `local` or `project` scope for totally different projects — their `hooks.json` may still load globally.

**Evidence:** This session's v1.8.2 run showed v1.6.6's `SessionStart` echo firing despite v1.8.1 being the user-scope install.

**Fix:** `cd` into the owning project and `claude plugin uninstall <name> --scope=<scope>`. You can find the owning project by reading `~/.claude/plugins/installed_plugins.json` — each install has a `projectPath`. Do not edit that file by hand; the harness flags it as self-modification.

### 7.9 `enabledPlugins` in a project's `settings.local.json` overrides user scope

**Symptom:** You enable a plugin at user scope. Plugin list says "disabled" in a specific project.

**Fix:** Check `<project>/.claude/settings.local.json` for `"enabledPlugins": { "<name>": false }`. Flip to `true` or remove the entry. The setting is project-local and overrides the user-scope enabled flag for that project.

### 7.10 Plugin squash-merge can sweep in unrelated local commits

**Symptom:** You open a PR with one small change. The squash-merge commit message shows it brought 10 unrelated commits along.

**Cause:** Branching `feat/...` from local `main` that's ahead of `origin/main`. The PR diff includes everything between `origin/main` and your branch tip.

**Fix:** Before branching, either push `main` first, or branch from `origin/main` explicitly: `git checkout -b my-branch origin/main`. If it already happened, the squash commit content is still correct — just messier than intended.

---

## 8. Debug recipes

Concrete commands to diagnose a failing hook.

> **If you're debugging a silent/misbehaving hook, jump straight to §8.3** — the invocation-trace recipe is the fastest way to see whether a hook is firing, what `agent_type` it received, and where in the script it exited.

### 8.1 Is the plugin hook firing at all?

```bash
# In consumer project
rm -f /tmp/pev-hook-debug.log
MSYS_NO_PATHCONV=1 claude -p "/hs-heartbeat" --dangerously-skip-permissions --no-session-persistence
cat /tmp/hook-spike/heartbeat-*.fired  # look for "fired=true"
```

If the canary exists, plugin hooks.json is active. If not, the plugin isn't loaded — check `claude plugin list`, `enabledPlugins`, `installed_plugins.json`.

### 8.2 What does the hook actually receive?

Run a session that exercises the tool:

```bash
MSYS_NO_PATHCONV=1 claude -p "<whatever triggers the hook>" --dangerously-skip-permissions --no-session-persistence
cat /tmp/hook-spike/input-PreToolUse-<ToolName>.json | jq
```

`hook-spike`'s hooks.json captures every PreToolUse(Bash), PreToolUse(Read), PostToolUse(Bash), SubagentStop, Stop stdin JSON to disk. Look for `agent_type`, `agent_id`, `tool_input`.

### 8.3 Trace a specific PEV hook — re-enabling invocation logging

> **Important:** PEV hooks used to emit invocation traces to `/tmp/pev-hook-debug.log` during every run (added in v1.8.2 while the hook infrastructure was being shaken out). That instrumentation was **removed in v1.9.1** now that hooks are stable — the log was noise in steady-state use. This recipe restores it temporarily when you need to debug a misbehaving hook. **Reach for it whenever a hook seems silent** — if the log shows no entries for the expected hook, it never fired at all; if it shows entries but the hook still passed through, the bug is in the post-gate logic.

**Setup (two minutes):**

1. Pick the hook script you want to trace. Location: `~/.claude/plugins/cache/pev-agent-nexus/pev/<version>/hooks/<name>.sh`. On Windows git-bash: `/c/Users/<you>/.claude/plugins/cache/pev-agent-nexus/pev/<version>/hooks/<name>.sh`.

2. Decide where to insert the echo line:

| Hook script | Insert location |
|---|---|
| `pev-worktree-scope.sh`, `pev-bash-scope.sh`, `pev-doc-scope.sh`, `pev-cortex-scope.sh` | Right after `INPUT=$(cat)` and before the `# Gate: PEV subagents only` comment |
| `pev-tool-counter.sh`, `pev-tool-gate.sh` | Right after the `AGENT_TYPE=...`, `AGENT_ID=...` (and `TOOL_NAME=...` for gate) extraction block |
| `pev-subagent-stop.sh` | Right after `AGENT_TYPE=...`, `AGENT_ID=...` extraction |

3. Insert the appropriate line — place it **before** the `case "$AGENT_TYPE" in pev:*) ;;` gate so you see invocations from non-PEV agents and the orchestrator too. Otherwise the hook exits 0 before logging and you won't see why.

**Scope hooks** (before the agent_type gate reads `$INPUT`):

```bash
echo "[$(date -Is 2>/dev/null || echo now)] hook=<name> pid=$$ agent_type=$(echo "$INPUT" | jq -r '.agent_type // "<empty>"' 2>/dev/null) tool=$(echo "$INPUT" | jq -r '.tool_name // "<empty>"' 2>/dev/null) event=$(echo "$INPUT" | jq -r '.hook_event_name // "<empty>"' 2>/dev/null)" >> /tmp/pev-hook-debug.log 2>/dev/null
```

Replace `<name>` with the script's short name (e.g., `worktree-scope`).

**tool-counter / tool-gate / subagent-stop** (AGENT_TYPE and AGENT_ID already extracted into variables — use them):

```bash
echo "[$(date -Is 2>/dev/null || echo now)] hook=<name> pid=$$ agent_type=${AGENT_TYPE:-<empty>} agent_id=${AGENT_ID:-<empty>} tool=${TOOL_NAME:-$(echo "$INPUT" | jq -r '.tool_name // "<empty>"' 2>/dev/null)} event=$(echo "$INPUT" | jq -r '.hook_event_name // "<empty>"' 2>/dev/null)" >> /tmp/pev-hook-debug.log 2>/dev/null
```

(For `subagent-stop`, drop the `tool=...` segment — there's no tool name for a SubagentStop event.)

**Using the log:**

```bash
# Clear it before the run
rm -f /tmp/pev-hook-debug.log

# Run whatever scenario reproduces the problem
MSYS_NO_PATHCONV=1 claude -p "/pev-spike" --dangerously-skip-permissions --no-session-persistence

# Inspect
cat /tmp/pev-hook-debug.log
grep 'hook=bash-scope' /tmp/pev-hook-debug.log
grep 'agent_type=pev:pev-builder' /tmp/pev-hook-debug.log
```

You'll see every hook invocation with its agent context, tool name, and event. A missing hook entry means the hook didn't fire at all (matcher miss, plugin not loaded, or gate exited 0 too early). An entry present but followed by no block means the post-gate logic has a bug.

**Cleanup after debugging:**

Remove the lines you added. Either manually, or since you're editing an installed plugin copy, you can force-reinstall:

```bash
claude plugin uninstall pev --scope=user
claude plugin install pev@pev-agent-nexus
```

That resets the installed copy to the marketplace version (no debug lines). A future version of this plugin may ship a `PEV_DEBUG=1` env-var gate so this is a one-line flip — for now it's a manual edit.

### 8.4 Test a hook standalone with real input

```bash
# 1. Capture real hook input by running any scenario with hook-spike active
cp /tmp/hook-spike/input-PreToolUse-Bash.json /tmp/real-input.json

# 2. Edit with jq if you want to change the scenario
jq '.tool_input.command = "cd /tmp && echo escaped" | .agent_type = "pev:pev-spike"' \
  /tmp/real-input.json > /tmp/test-input.json

# 3. Pipe into the hook script under test
cat /tmp/test-input.json | bash plugins/pev/hooks/pev-bash-scope.sh
echo "EXIT=$?"
```

### 8.5 Construct synthetic input (when you don't have a real capture)

Use Python, not bash heredocs:

```python
import json
payload = {
    "session_id": "test",
    "cwd": "C:\\Users\\dap182\\...\\worktree",
    "agent_type": "pev:pev-spike",
    "agent_id": "test-id",
    "tool_name": "Write",
    "tool_input": {"file_path": "C:/...", "content": "x"},
    "hook_event_name": "PreToolUse",
}
with open("C:/Users/dap182/AppData/Local/Temp/test-input.json", "w") as f:
    json.dump(payload, f)
```

Then `cat /tmp/test-input.json | bash <hook>`.

---

## 9. Extending — adding a new hook

Five-step checklist:

1. **Pick the event and matcher.** `PreToolUse`, `PostToolUse`, `SubagentStop`, `Stop`. Matcher is a regex on tool name; use full-string patterns (`.*` at the end if you want a prefix).
2. **Create the script at `plugins/<name>/hooks/<script>.sh`.** Make it executable.
3. **First four lines of the script:**
   ```bash
   #!/bin/bash
   INPUT=$(cat)
   AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
   case "$AGENT_TYPE" in pev:*) ;; *) exit 0 ;; esac
   ```
   (Gate on your plugin's agent prefix; pass-through for anything else.)
4. **Read state via stdin, not by path.** When you need to read a file whose path came from hook input, `cygpath -u` the path for bash, then `cat file | jq` for jq.
5. **Block with `echo "msg" >&2; exit 2`.** Don't rely on stdout JSON alone.
6. **Register in `hooks.json`:**
   ```json
   {
     "matcher": "YourMatcher.*",
     "hooks": [
       {
         "type": "command",
         "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh\"",
         "timeout": 5
       }
     ]
   }
   ```
7. **Smoke-test via `/hs-heartbeat`.** If the infra breaks, you'll know immediately.

---

## 10. Version history — key fixes in the v1.8.x arc

Useful for reasoning about regressions. If a symptom matches an earlier bug, check whether the fix was reverted.

| Version | PR | Change |
|---|---|---|
| 1.8.0 | #3 | Migrate to `hooks.json`-only registration with `agent_type` dispatch. Agent-frontmatter hooks no longer used. |
| 1.8.1 | #4 | Normalize Windows `cwd` with `cygpath -u` before building state-file path. |
| 1.8.2 | #5 | Add diagnostic `echo >> /tmp/pev-hook-debug.log` to every hook (before the agent_type gate) so hook invocations are observable. |
| 1.8.3 | #6 | Pipe state file via `cat "$STATE_FILE" | jq …` — native Windows jq can't open `/c/` paths. |
| 1.8.4 | #7 | `pev-bash-scope.sh` block path switched from stdout `hookSpecificOutput` JSON to stderr + `exit 2`. |
| 1.8.5 | #8 | Replace `grep -oP` with POSIX `sed` (PCRE locale bug). Fix `cortex-scope` matcher `mcp__cortex__` → `mcp__cortex__.*` (full-string match). |
| 1.8.6 | #11 | Architect skill: fix stale `${CLAUDE_PROJECT_DIR}/.claude/templates/` path to plugin-scoped; loosen "As a developer" → "As a [user type]"; orchestrator pitch display now always includes the test plan. |
| 1.9.0 | #12 | `.pev/` project SOP convention — per-project config for Doc Reviewer (taxonomy), Architect/Builder/Reviewer (test policy), Reviewer (criteria). Skills read project SOPs first, fall back to plugin templates. Doc Reviewer mandate rewritten as drift scanner for non-graph docs. |
| 1.9.1 | this PR | Strip diagnostic `echo >> /tmp/pev-hook-debug.log` lines from every PEV hook. Hooks are stable; the per-invocation log was steady-state noise. See §8.3 for the recipe to re-enable when troubleshooting. |
