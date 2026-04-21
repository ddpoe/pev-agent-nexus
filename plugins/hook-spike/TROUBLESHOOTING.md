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

### 6.5 Bash heredocs strip `\\` silently

Constructing test JSON in a `<<'EOF'` heredoc — e.g. trying to write `"cwd":"C:\\Users\\..."` — produces single backslashes in the resulting file (`C:\Users\...`), which is **invalid JSON**. jq rejects it with `Invalid escape at line 1, column N`. This is specific to the git-bash build on this system.

**Fix:** generate test JSON via Python `json.dump` — it escapes correctly:

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

**Fix:** Canary files, not stderr, are the authoritative signal. Write `echo "..." >> /tmp/pev-hook-debug.log` or a canary marker file. The v1.8.2 diagnostic pattern is the standard:

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

### 8.3 Trace a specific PEV hook

Add at the top of the hook script, BEFORE the agent_type gate:

```bash
echo "[$(date -Is)] hook=<name> pid=$$ agent_type=$(echo "$INPUT" | jq -r '.agent_type // \"<empty>\"') tool=$(echo "$INPUT" | jq -r '.tool_name // \"<empty>\"')" >> /tmp/pev-hook-debug.log 2>/dev/null
```

Run the scenario. `cat /tmp/pev-hook-debug.log` — you'll see every invocation, which tools they matched on, and what agent fired them.

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

The diagnostic logging from 1.8.2 is still present in every hook. Safe to strip in a future cleanup, but helpful to leave in place while the system is shaking out.
