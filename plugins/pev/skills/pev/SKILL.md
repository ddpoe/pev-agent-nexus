---
name: pev
description: PEV orchestrator — Plan-Execute-Validate workflow. Dispatches Architect, Builder, Reviewer, and Auditor subagents to implement changes through a structured cycle.
user-invocable: true
---

# PEV Orchestrator

You coordinate a Plan-Execute-Validate cycle by dispatching subagents and managing phase transitions through a cycle manifest document.

**Reference:** For shell commands, templates, format specs, and dispatch prompts, consult `cortex::docs.templates.pev-orchestrator-reference` (use `cortex_read_doc` with `section=` to read individual sections on demand).

## Phases

### 1. Intake

**Pre-flight: clean working tree.** Run `git status` before anything else. If there are uncommitted changes (staged or unstaged, excluding untracked files), ask the user to commit or stash them first. A dirty working tree causes merge conflicts when the worktree branch is merged back. Do NOT proceed with uncommitted changes.

Parse the user's `/pev` request. If empty or unclear, ask what they want to build or fix.

Generate the cycle ID (see ref: `naming-conventions`). Present to user for confirmation:
```
PEV Cycle: {cycle_id}
Request: "{user request}"
Proceed? (or suggest a different name)
```
**HUMAN GATE** — wait for confirmation.

Capture baseline SHA (`git rev-parse HEAD`).

**Create worktree and set up environment** (see ref: `worktree-commands`): `git worktree add`, `poetry install --no-root` (install deps without the project itself), `cortex_checkout` to copy cortex DB into worktree.

**Write pev-state.json** (see ref: `state-file`) — include `worktree_path`, `cycle_doc_id`, and `counter_file` for the Architect. All subagent hooks read this file.

Create the cycle manifest inside the worktree (see ref: `manifest-creation`).

### 2. Plan (Architect)

Update pev-state.json counter_file for Architect. Dispatch `pev-architect` subagent pointing at the worktree (see ref: `dispatch-prompts`).

Handle returns:
- **NEEDS_INPUT**: If the payload includes a `preamble` field, print it as a text message to the user first. Then relay the Architect's `questions` to the user via AskUserQuestion. Resume with SendMessage containing the answers and the Architect's `context` field.
- **CONTINUING**: Write checkpoint to manifest, increment incarnation, redispatch.
- **Complete**: Proceed to Phase 3.

### 3. Approve Plan

Read the cycle manifest. Present the Architect's pitch — scope, user stories, solution sketch, constraints.

**HUMAN GATE** — "Approve this pitch to proceed to Builder phase, or provide feedback to revise?"

- **Approved**: Update status to `builder` (see ref: `status-updates`). Proceed to Phase 4.
- **Rejected**: Redispatch Architect with feedback appended (see ref: `dispatch-prompts`). Loop back to Phase 3.

### 4. Build

**Before dispatching**, read the Architect's pitch from the cycle manifest and inline it into the Builder dispatch prompt (see ref: `builder-context-handoff`). The Builder uses cortex tools to read source on demand from the worktree's cortex DB snapshot.

Update pev-state.json counter_file for Builder. Dispatch `pev-builder` subagent pointing at the worktree (see ref: `dispatch-prompts`). Do NOT use `isolation: "worktree"`.

Parse return — extract manifest from `---MANIFEST---` separator (see ref: `manifest-parsing`).

Handle status codes:
- **DONE**: Write manifest to `builder.manifest` section of cycle doc. Proceed to Phase 5.
- **DONE_WITH_CONCERNS**: Present concerns to user with options: (1) proceed to review, (2) redispatch Builder to address concerns (treat as CONTINUING — same worktree), (3) abort.
- **BLOCKED / NEEDS_CONTEXT**: Present to user. Options: provide guidance and redispatch, or abort (set status to `incomplete`).
- **CONTINUING** (or no separator — maxTurns cutoff): The Builder's plan and progress are already in the manifest (it writes them as it works). Write checkpoint to manifest. Re-index the worktree (`cortex_build(project_root=worktree_path)`) so the next Builder incarnation can use cortex tools on modified files. Increment incarnation, redispatch to same worktree.

### 5. Review

**Re-index the worktree** before dispatching the Reviewer: run `cortex_build(project_root=worktree_path)` so cortex tools reflect the Builder's changes. Without this, `cortex_check`, `cortex_diff`, and `cortex_source` would return pre-Builder data.

Update pev-state.json counter_file for Reviewer. Dispatch `pev-reviewer` subagent pointing at the worktree (see ref: `dispatch-prompts`). The Reviewer is read-only — it cannot modify code or docs.

The Reviewer performs a three-pass review against the Architect's pitch:
1. **Spec compliance** — per-user-story pass/fail with evidence
2. **Functionality preservation** — callers checked via cortex_graph, behavioral changes flagged
3. **Code quality** — issues ranked critical/important/minor

Parse return — extract JSON verdict from `---REVIEW---` separator. Write the review findings to the `review` section of the cycle doc.

Handle status codes:
- **PASS**: Write review to cycle doc. Proceed to Phase 6.
- **PASS_WITH_CONCERNS**: Write review to cycle doc. Present concerns to user. Options: (1) proceed to audit, (2) redispatch Builder to fix concerns, then re-review.
- **FAIL**: Write review to cycle doc. Present failures to user. Redispatch Builder with the specific failures to fix (same worktree). After fix, re-index the worktree (`cortex_build`), then re-dispatch Reviewer. Max 2 review-fix loops before escalating to user.
- **NEEDS_INPUT**: Relay the Reviewer's questions to the user via AskUserQuestion (same proxy-question protocol as the Architect). Resume with SendMessage containing the answers and the Reviewer's `context` field.

### 6. Audit

**Re-index the worktree**: run `cortex_build(project_root=worktree_path)` then `cortex_check(project_root=worktree_path)`.

Construct change-set from `git diff {baseline_sha}..HEAD` + Builder manifest. Write Builder manifest and change-set to cycle doc. Update status to `auditor` (see ref: `status-updates`).

**HUMAN GATE** — Present implementation summary (files changed, tests, review verdict, deviations, cortex check results). "Approve to proceed to Auditor phase, or provide feedback?"

- **Rejected**: Discuss options — redispatch Builder with feedback.

Check for concurrent `pev-active` cycles in auditor phase (`cortex_list` with tag `pev-active`). Warn if found — only one Auditor should run at a time.

Update pev-state.json counter_file for Auditor. Dispatch `pev-auditor` subagent pointing at the worktree (see ref: `dispatch-prompts`).

Parse return — extract report from `---IMPACT-REPORT---` separator (see ref: `manifest-parsing`).

Handle status codes:
- **DONE**: Write Impact Report to `auditor.impact-report` section. The change ledger is already in `auditor.change-ledger` (written by Auditor as it works). Proceed to Phase 7.
- **DONE_WITH_CONCERNS** (has `needs_fix`): Builder loopback — max 2 iterations (see ref: `loopback-mechanics`). After fix, re-dispatch Auditor.
- **CONTINUING** (or no separator): The Auditor writes partial progress and change ledger entries to the manifest as it works. Increment incarnation, redispatch. Already-marked-clean nodes are skipped automatically.
- **NEEDS_INPUT**: Relay the Auditor's questions to the user via AskUserQuestion (same proxy-question protocol as the Architect). Resume with SendMessage containing the answers and the Auditor's `context` field.

### 7. Complete

**HUMAN GATE** — Present final audit results (nodes reviewed, change ledger entries, links, decisions, concerns). "Approve to merge and complete this PEV cycle?"

Merge worktree branch into main, remove worktree/branch, rebuild cortex on main, run cortex_check (see ref: `merge-commands`).

Create audit checkpoint. Single commit with structured message (see ref: `commit-format`). Update cycle manifest status to `completed`, remove `pev-active` tag.

Run efficiency analysis and present the compact summary (see ref: `completion-cleanup`):
```bash
python scripts/analyze_pev_session.py --find-cycle {cycle-id} --docjson --summary
```
This writes `docs/pev-cycles/{cycle-id}-efficiency.json` and prints a verdict. Present the summary to the user.

Clean up state file. Invoke `superpowers:finishing-a-development-branch`. Do NOT invoke `superpowers:requesting-code-review` — the PEV Reviewer (Phase 5) already covered spec compliance, functionality preservation, and code quality.

## Error Handling

- **Agent dispatch failure**: Check `.claude/agents/pev-{agent}.md` exists; suggest `/agents` to reload.
- **Worktree failure**: Check `git worktree list` for stale entries.
- **Merge conflicts**: Present to user and resolve before proceeding.
- **cortex_check hangs**: Timeout and retry; if persistent, proceed with manual review scope from Builder's change-set.
- **Failure at any point**: Update status to `incomplete`. Keep `pev-active` tag so the cycle can be resumed.
