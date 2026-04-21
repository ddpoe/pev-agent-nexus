# PEV Design

Architecture reference for the `pev` plugin. For end-user workflow documentation, see [USER_GUIDE.md](./USER_GUIDE.md). For debugging plugin hooks, see [../hook-spike/TROUBLESHOOTING.md](../hook-spike/TROUBLESHOOTING.md).

## Architecture overview

PEV is a multi-agent orchestration for structured code changes. Five agent definitions plus two orchestrator skills (`/pev-cycle`, `/pev-instance`), each with structurally enforced tool permissions. Claude owns reasoning within each phase. Cortex MCP tools own the knowledge layer (code index, doc graph). The orchestrator owns phase transitions, human gates, and the cycle manifest lifecycle.

```
User request
  → Orchestrator: worktree + cortex checkout + cycle manifest doc (pev-active)
  → Architect     [doc-write: cycle manifest only]
    → explore codebase → NEEDS_INPUT questions (proxy-relay) → pitch
    → Human gate
  → Builder       [code-write; doc-write scoped to cycle manifest]
    → read pitch → decompose → TDD → build plan + progress on manifest
    → commit in worktree branch
  → Reviewer      [read-only code; doc-write scoped to cycle manifest]
    → 6-pass review (test, source-doc, spec, functionality, quality, PEV-checks)
    → PASS → Human gate
    → FAIL → Builder loopback (max 2x)
  → Merge gate (human approval) → orchestrator merges worktree → main
  → Auditor       [no code-write; unrestricted doc-write on main]
    → cortex_build + cortex_check → review stale nodes
    → read .pev/doc-topology.json → per-category auditor-action
    → update graph-linked + topology-listed docs
    → Impact Report
  → Doc Reviewer  [read-only; cycle manifest write-back only]
    → verify Auditor's doc updates → scan for missed drift
    → PASS → Human gate
    → FAIL → Auditor loopback (max 2x)
  → Complete: single commit, cycle manifest → completed, worktree removed
```

**Planning model: Shape Up over waterfall.** The Architect writes a pitch — problem, user stories (3–5 coarse outcomes), solution sketch (fat-marker approach at module level), constraints (rabbit holes and no-gos). The Builder receives orientation and boundaries, not a prescriptive implementation spec. The Builder reads source code and makes implementation decisions.

**Cycle manifest as central artifact.** A DocJSON at `docs/pev/cycles/<cycle-id>.json` carrying the pitch, build plan, review findings, change ledger, and impact report. Agents write their phase's outputs to the manifest as they work, so partial progress survives incarnation cutoffs. The orchestrator reads manifest status sections to determine phase transitions.

**`/pev-instance` shares the spine, not the machinery.** Same user-story framing, same human gate, same self-review against `.pev/` SOPs. But single agent, no worktree, no separate Reviewer — the trade for small tasks. Writes to `docs/pev/instances/<id>.json` under the same namespace so `cortex_search` finds both cycle and instance history.

## Tool permissions matrix

Each agent's `tools:` frontmatter is a runtime-enforced allowlist. Agents cannot see or call tools outside their list. The invariant:

> **No single agent can both write code AND update live feature docs.**

| Capability | Architect | Builder | Reviewer | Auditor | Doc Reviewer | pev-instance¹ |
|---|---|---|---|---|---|---|
| Read code (`cortex_source`, `Read`, `Grep`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Search/graph (`cortex_search`, `cortex_graph`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Write code (`Edit`, `Write`, `Bash`) | ✗ | ✓ | ✗² | ✗ | ✗ | ✓ |
| Write cycle manifest (`cortex_update_section`) | ✓ | ✓ | ✓ | (not used) | ✓ | ✓ |
| Write live feature docs | ✗ | ✗ | ✗ | **✓** | ✗ | ✗ |
| `cortex_build` / `cortex_check` | ✓ | ✓ | ✓ (check only) | ✓ | ✗ | ✓ |
| `cortex_mark_clean`, `cortex_purge_node` | ✗ | ✗ | ✗ | **✓** | ✗ | ✗ |
| Commit in git | ✗ | ✓³ | ✗ | ✗ | ✗ | ✓ |
| User interaction | Proxy⁴ | ✗ | Proxy⁴ | Proxy⁴ | Proxy⁴ | Direct |
| Dispatch subagents | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

**¹ `/pev-instance`** runs in the user's main session — no subagent dispatch. Full tool access by design; the discipline comes from the skill's prompt, not tool restriction.

**² Reviewer has `Bash`** for read-only use (`git diff`, `pytest`, `git log`). `Edit` and `Write` are absent from its allowlist. It's expected to use Bash only for inspection.

**³ Builder commits** on the worktree branch (`git add -A` + `git commit -m`) as a transport mechanism. The orchestrator merges the worktree branch into main afterward. Builder does not push.

**⁴ Proxy-question protocol:** `AskUserQuestion` is not available in subagents (Claude Code platform limitation). Subagents return a `NEEDS_INPUT` JSON payload; the orchestrator relays questions to the user via `AskUserQuestion` and resumes the agent with answers via `SendMessage`.

## Hook architecture — the load-bearing invariants

PEV's runtime enforcement lives in plugin hooks. Three invariants that any contributor extending the plugin must respect.

### 1. All hooks live in `plugins/pev/hooks/hooks.json`

Agent-frontmatter `hooks:` blocks silently no-op in marketplace installs — discovered empirically in v1.8.0 (see `CHANGELOG.md` and the `hook-spike` matrix). Register every hook at plugin level using `${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh` paths.

### 2. Per-agent behavior dispatches inside scripts on `agent_type`

Each hook's stdin JSON carries `agent_type` (e.g. `pev:pev-builder`) when a PEV subagent is the caller; absent when the orchestrator is. Every hook script:

```bash
INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
case "$AGENT_TYPE" in pev:*) ;; *) exit 0 ;; esac
# ...agent-specific logic dispatched by full agent_type value
```

Per-agent config (budgets, allowlists, scope rules) lives in the hook script, dispatched via `case "$AGENT_TYPE" in pev:pev-<role>) ... ;; esac`. Do **not** maintain per-agent config in `.pev-state.json` — state-file dispatch races with orchestrator tool calls (the state file says "builder phase" while the orchestrator is doing intermediate work between phases).

### 3. Counter files keyed on `agent_id`

Tool-budget counters are per-subagent-invocation. The `agent_id` field in stdin JSON is unique per dispatch, so `/tmp/pev-counter-<agent_id>.txt` never collides even when the orchestrator dispatches the same agent type twice in one cycle. Cleaned up by `pev-subagent-stop.sh` when the subagent returns.

### Hook roster

| Hook | Event | Purpose |
|---|---|---|
| `pev-worktree-scope.sh` | PreToolUse (Write/Edit) | Blocks writes outside the worktree |
| `pev-bash-scope.sh` | PreToolUse (Bash) | Blocks `cd` out of the worktree |
| `pev-doc-scope.sh` | PreToolUse (cortex doc-write tools) | Restricts doc writes to the cycle manifest |
| `pev-cortex-scope.sh` | PreToolUse (mcp__cortex__.*) | Enforces cortex `project_root` matches worktree |
| `pev-tool-gate.sh` | PreToolUse (.*) | Post-budget allowlist gate |
| `pev-tool-counter.sh` | PostToolUse (.*) | Increments counter; emits budget advisories |
| `pev-subagent-stop.sh` | SubagentStop | Counter cleanup + Builder cortex rebuild |

## Cycle manifest structure

Written to `docs/pev/cycles/<cycle-id>.json`. Sections:

| Section | Written by | When |
|---|---|---|
| `status` | Orchestrator | Creation + every phase transition |
| `request` | Orchestrator | Creation (user's original prompt, verbatim) |
| `scope` | Architect | Planning phase |
| `architect.*` | Architect | Planning (problem, user-stories, solution-sketch, constraints, tasks, test-plan, etc.) |
| `decisions` | All agents | Accumulated — key decisions with rationale |
| `builder.build-plan` | Builder | Before implementation starts |
| `builder.progress` | Builder | Updated per task during implementation |
| `builder.manifest` | Orchestrator (from Builder return) | Implementation complete |
| `change-set` | Orchestrator | After Builder (git diff + manifest) |
| `review` | Orchestrator (from Reviewer return) | Review complete |
| `auditor.change-ledger` | Auditor | Updated as Auditor works |
| `auditor.impact-report` | Orchestrator (from Auditor return) | Validation complete |
| `doc-review` | Orchestrator (from Doc Reviewer return) | Doc review complete |
| `{agent}.friction` | Each agent + orchestrator | Append-as-you-go during each phase |

`/pev-instance` writes a smaller analogous structure to `docs/pev/instances/<id>.json` (meta, problem, user-story, acceptance, changes, self-review, optional escalation, friction).

### Friction logs

Each phase-agent (Architect, Builder, Reviewer, Auditor, Doc Reviewer) and the orchestrator owns a `{agent}.friction` section in the cycle manifest. Agents append observations when something pinches during work — instructions that didn't fit the situation, tool output that was awkward, role constraints that forced workarounds, upstream inputs that required guessing, effort disproportionate to value.

This is distinct from the `decisions` log (cycle-wide record of what was chosen and why) and from `builder.deviations` (structured Builder-vs-plan delta). Friction is phenomenological: what was hard or felt off, regardless of whether the agent deviated.

Entries follow a short-tag + raw-context-paste format documented in each skill and in the cycle-manifest template's `friction-logs` section. Initiative-based, not gated — agents capture in-the-moment or not at all. Empty sections are expected and acceptable; the value compounds across cycles as `cortex_search` surfaces recurring tags (e.g., `cortex-staleness`, `instruction-ambiguity`, `role-pinch`) that drive skill and tool evolution.

Sections are created lazily on first write via `cortex_update_section` — same pattern as `reviewer.progress`, `builder.build-plan`, and `auditor.change-ledger`.

## Agent responsibilities (one-line each)

- **Architect** — read codebase, interact with user via proxy-questions, write Shape Up pitch + test plan to cycle manifest. Owns `architect.*` sections. No code writes. Works in worktree.
- **Builder** — read Architect pitch, implement with TDD in worktree, commit on worktree branch, return structured manifest. Writes build plan and progress to cycle manifest. Has worktree-scoped code-write tools.
- **Reviewer** — six-pass review of Builder's code against Architect pitch (tests, source docs, spec compliance, functionality preservation, code quality, PEV-specific). Read-only code access. Writes review results to cycle manifest.
- **Auditor** — runs on main post-merge. Reviews every stale node; updates graph-linked docs; reads `.pev/doc-topology.json` and performs `auditor-action` per triggered category. Writes Impact Report. Doc-write on live feature docs but no code-write.
- **Doc Reviewer** — verifies Auditor's doc updates against Builder's work; scans for drift in doc categories the Auditor may have missed. Read-only except cycle manifest write-back.
- **pev-spike** — special test agent. 11-test integration smoke test of PEV hook infrastructure (worktree scope, bash scope, doc scope, cortex scope, budget warnings, gate, allowlist). Used only for validating PEV itself.

## `.pev/` SOPs — extension points

Three project-customizable DocJSON files consumers may create in their repo:

| File | Consumed by | Purpose |
|---|---|---|
| `.pev/doc-topology.json` | Auditor (proactive) + Doc Reviewer (verify) | Project doc taxonomy with per-category `auditor-action` and `doc-reviewer-check` |
| `.pev/test-policy.json` | Architect + Builder + Reviewer | Test tier system, annotation contract, coverage, budget |
| `.pev/review-criteria.json` | Reviewer | Project-specific code-review emphasis |

Each has a plugin-shipped fallback at `${CLAUDE_PLUGIN_ROOT}/templates/<name>.json`. Skills read the project file first, fall back to the template if absent.

### Adding a new SOP

If you extend PEV with a new concern that varies per project:

1. Create `plugins/pev/templates/<new-sop>.json` as the plugin's default. DocJSON format with clearly-named sections. Include an `overview` section documenting which skills read this file and what fields matter.
2. Update the relevant skill to read `{worktree_path}/.pev/<new-sop>.json` first, fall back to `${CLAUDE_PLUGIN_ROOT}/templates/<new-sop>.json`. Use `Read` tool + JSON parse; don't require cortex indexing.
3. Document the new SOP in this file's table above and in [USER_GUIDE.md](./USER_GUIDE.md#customizing-via-pev-sops).

### Adding a category to `doc-topology.json`

Add a section with ID `category.<name>` containing four fields in markdown content: Path, Triggered by, Auditor action, Doc Reviewer check. The Auditor reads all `category.*` sections and iterates; no skill change needed for a new category in a consumer's topology.

## Cross-agent signals

Signals that several agents consult to stay consistent:

- **`cortex_workflow_list(steps=true)`** — returns functions with `@workflow` + `Step()` markers. Framed as **developer-declared core mechanisms**. Used by:
  - Reviewer Pass 3 (functionality preservation — scrutinize callers harder for workflow-marked functions)
  - Reviewer Pass 4 (code quality — findings in workflow-marked code rank `important`/`critical`, not `minor`)
  - Reviewer Pass 5c (workflow markers match code behavior)
  - Reviewer Pass 5d (taxonomy hygiene — suggest new markers for Builder-added functions that cross core-mechanism thresholds)
  - `/pev-instance` scope check (escalates to `/pev-cycle` if the task touches any workflow-marked function)

- **`.pev/test-policy.json` tier table** — canonical tier-to-annotation mapping. Architect uses it for `architect.test-plan`, Builder for actual test annotation, Reviewer for Pass 5b cross-check.

- **Cycle manifest `architect.test-plan`** — the source of truth for what tests the Builder owes. Reviewer checks Builder's tests against this row by row.

## Why cortex-integrated

PEV depends on cortex for:
- Code reads during planning and review (`cortex_source`, `cortex_graph`, `cortex_search`)
- Doc graph for the Auditor's graph-linked doc updates
- Cycle manifest persistence + searchability via DocJSON
- Workflow marker introspection via `cortex_workflow_list`

PEV could, in principle, be cortex-independent (`.pev/` SOPs as an abstraction layer + `Read`/`Grep` fallbacks for code reads). This is deliberately out of scope — the value of the integration in practice outweighs the portability.

## Platform observations worth preserving

These are cross-platform and cross-Claude-Code-version issues that shaped the plugin:

- **Windows `cwd` in hook JSON uses backslashes** — hooks must `cygpath -u` before building state-file paths. Without this, `[ -f ]` tests fall open.
- **Native Windows jq cannot open POSIX paths** — `jq -r '...' "$STATE_FILE"` returns empty when `$STATE_FILE` starts with `/c/`. Hook scripts use `cat "$STATE_FILE" | jq -r '...'` to work around.
- **`grep -oP` requires a UTF-8 locale** which the hook execution env doesn't reliably set. All PCRE uses replaced with POSIX `sed`.
- **Hook matchers are full-string regex.** `"mcp__cortex__"` does not match `mcp__cortex__cortex_source`; use `"mcp__cortex__.*"`.
- **Agent-frontmatter hooks silently no-op** in marketplace plugin installs. All PEV hooks live in `plugins/pev/hooks/hooks.json`, none in agent frontmatter.
- **Slash commands through `claude -p` on git-bash need `MSYS_NO_PATHCONV=1`** or the slash becomes a mangled filesystem path.

All of these are documented with symptoms + fixes in [../hook-spike/TROUBLESHOOTING.md](../hook-spike/TROUBLESHOOTING.md) §6 and §7.
