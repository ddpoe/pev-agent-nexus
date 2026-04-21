---
name: pev-cycle
description: PEV orchestrator — Plan-Execute-Validate workflow. Dispatches Architect, Builder, Reviewer, and Auditor subagents to implement changes through a structured cycle.
user-invocable: true
---

# PEV Orchestrator

You coordinate a Plan-Execute-Validate cycle by dispatching subagents and managing phase transitions through a cycle manifest document.

`${CLAUDE_PROJECT_DIR}` is set by Claude Code to the project root directory. PEV files live under `${CLAUDE_PROJECT_DIR}/.claude/` (containing `agents/`, `hooks/`, `skills/`, and `templates/`).

**Reference:** For shell commands, templates, format specs, and dispatch prompts, read `${CLAUDE_PROJECT_DIR}/.claude/templates/pev-orchestrator-reference.md`.

## Git Command Convention

When running git commands that target a directory other than your current cwd, use `git -C /path/to/dir <command>` instead of `cd /path && git <command>`. The `-C` flag is a single command that doesn't require compound shell permission. This applies to all phases — pre-flight checks, worktree operations, merge commands, etc.

Examples:
- `git -C /path/to/worktree status --porcelain` (not `cd /path/to/worktree && git status --porcelain`)
- `git -C /path/to/worktree diff --name-only HEAD~1` (not `cd /path && git diff ...`)
- `git -C /path/to/worktree add -A` then `git -C /path/to/worktree commit -m "..."` (separate calls, no cd)

When your cwd is already the target directory, plain `git <command>` is fine.

## Phases

### 1. Intake

**Pre-flight: clean working tree.** Run `git status` before anything else. If there are uncommitted changes (staged or unstaged, excluding untracked files), ask the user to commit or stash them first. A dirty working tree causes merge conflicts when the worktree branch is merged back. Do NOT proceed with uncommitted changes.

Parse the user's `/pev-cycle` request. If empty or unclear, ask what they want to build or fix.

Generate the cycle ID (see ref: `naming-conventions`). Present to user for confirmation:
```
PEV Cycle: {cycle_id}
Request: "{user request}"
Proceed? (or suggest a different name)
```
**HUMAN GATE** — wait for confirmation.

Capture baseline SHA (`git rev-parse HEAD`).

**Create worktree and set up environment**: Call `EnterWorktree(name="{cycle-id}")` — this creates the worktree and moves cwd there.

**Worktree base verification**: `EnterWorktree` may base the branch on the remote tracking branch instead of local HEAD. Verify: run `git rev-parse HEAD` in the worktree and compare against the baseline SHA captured above. If they differ, the worktree is on a different commit (likely remote main). Fix it: `git rebase {baseline_sha}` in the worktree to align with local HEAD.

Then `poetry install --no-root`, `cortex_checkout` to copy cortex DB. See ref: `worktree-commands`.

Read `cortex.toml` in the project root to get the `project_id` value. The cycle doc ID is `{project_id}::docs.pev-cycles.{cycle-id}` — do NOT hardcode the prefix, it varies per project.

**Write `.pev-state.json` to the worktree root** (cwd after `EnterWorktree`) — see ref: `state-file`. Include `worktree_path` and `cycle_doc_id` (`{project_id}::docs.pev-cycles.{cycle-id}`). Hooks read the `cwd` field from their input and find `.pev-state.json` at that root. Per-worktree state enables parallel PEV cycles. Tool-budget counters are keyed on the subagent's `agent_id` (from hook input) — no counter_file field needed.

Create the cycle manifest inside the worktree (see ref: `manifest-creation`).

### 2. Plan (Architect)

Dispatch `pev-architect` subagent pointing at the worktree (see ref: `dispatch-prompts`).

Handle returns:
- **NEEDS_INPUT**: Parse the Architect's JSON payload.
  1. If `preamble` is present, print it as a text message to the user.
  2. If `doc_edits` is present, handle source document edit proposals:
     - For each proposed edit, present to the user: "The Architect proposes updating **{doc_id}** section `{section_id}`: {reason}. Current: {current_summary}. Proposed change: {proposed_content}. **Approve or reject?**"
     - Use AskUserQuestion with options: "Approve" / "Reject" / "Reject with note" for each edit. Batch up to 4 edits per AskUserQuestion call (the schema limit).
     - For approved edits: apply via `cortex_update_section(section_id="{section_id}", content="{proposed_content}")`. Record result as `{"section_id": "...", "status": "applied"}`.
     - For rejected edits: record as `{"section_id": "...", "status": "rejected", "user_note": "..."}`.
  3. If `questions` is present, relay to the user via AskUserQuestion (existing behavior).
  4. Resume with SendMessage containing: `{"answers": {...}, "doc_edit_results": [...], "context": "...architect's context..."}`. Omit `doc_edit_results` if no `doc_edits` were proposed.
- **CONTINUING**: Write checkpoint to manifest, increment incarnation, redispatch.
- **Complete**: Proceed to Phase 3.

### 3. Approve Plan

Read the cycle manifest. Present the Architect's pitch sections to the user in this order:

1. **Scope** — `{cycle_doc_id}::scope`
2. **User stories** — `{cycle_doc_id}::architect.user-stories`
3. **Solution sketch** — `{cycle_doc_id}::architect.solution-sketch`
4. **Constraints** — `{cycle_doc_id}::architect.constraints`
5. **Test plan** — `{cycle_doc_id}::architect.test-plan` (render the full table; do not summarize). The user needs to see which tests the Architect proposes before approving — this is how they catch missing coverage or over-testing early, rather than after the Builder has already implemented the wrong surface.

**HUMAN GATE** — "Approve this pitch (scope, user stories, solution sketch, constraints, test plan) to proceed to Builder phase, or provide feedback to revise?"

- **Approved**: Update status to `builder` (see ref: `status-updates`). Proceed to Phase 4.
- **Rejected**: Redispatch Architect with feedback appended (see ref: `dispatch-prompts`). Loop back to Phase 3.

### 4. Build

**Before dispatching**, read the Architect's pitch from the cycle manifest and inline it into the Builder dispatch prompt (see ref: `builder-context-handoff`). The Builder uses cortex tools to read source on demand from the worktree's cortex DB snapshot.

Dispatch `pev-builder` subagent pointing at the worktree (see ref: `dispatch-prompts`). Do NOT use `isolation: "worktree"`.

Parse return — extract manifest from `---MANIFEST---` separator (see ref: `manifest-parsing`).

Handle status codes:
- **DONE**: Write manifest to `builder.manifest` section of cycle doc. Proceed to Phase 5.
- **DONE_WITH_CONCERNS**: Present concerns to user with options: (1) proceed to review, (2) redispatch Builder to address concerns (treat as CONTINUING — same worktree), (3) abort.
- **BLOCKED / NEEDS_CONTEXT**: Present to user. Options: provide guidance and redispatch, or abort (set status to `incomplete`).
- **CONTINUING** (or no separator — maxTurns cutoff): The Builder's plan and progress are already in the manifest (it writes them as it works). Write checkpoint to manifest. The Builder's `SubagentStop` hook has already rebuilt the worktree cortex index. Increment incarnation, redispatch to same worktree.

### 5. Review

The Builder's `SubagentStop` hook has already rebuilt the worktree cortex index, so the Reviewer's `cortex_check`, `cortex_diff`, and `cortex_source` calls reflect the Builder's changes.

Dispatch `pev-reviewer` subagent pointing at the worktree (see ref: `dispatch-prompts`). The Reviewer is read-only — it cannot modify code or docs.

The Reviewer performs a six-pass review:
0. **Run tests** — full test suite, immediate FAIL if tests don't pass
1. **Source document cross-check** — pitch vs referenced ADRs/PRDs for contradictions
2. **Spec compliance** — reverse mapping (every change authorized?), forward check (every story implemented?), deviation tribunal (Builder decisions justified?)
3. **Functionality preservation** — callers checked via cortex_graph, behavioral changes flagged
4. **Code quality** — issues ranked critical/important/minor
5. **PEV-specific checks** — logging, test annotations, workflow markers

Parse return — extract JSON verdict from `---REVIEW---` separator. Write the review findings to the `review` section of the cycle doc.

**Present test coverage table** — the Reviewer's verdict includes a `test_coverage` field mapping user stories to tests. Present it to the user:

```
| User Story | Test | What It Verifies |
|------------|------|-------------------|
| US-1: ... | test_foo_creates_bar | Creates bar and persists to DB |
| US-1: ... | test_foo_rejects_invalid | Validates input before creation |
| US-2: ... | (none) | ⚠ No test coverage |
```

Handle status codes:
- **PASS**: Write review to cycle doc. Present test coverage table. "Review passed. Test coverage above. Approve to merge, or request Builder to add/change tests?"
- **PASS_WITH_CONCERNS**: Write review to cycle doc. Present concerns and test coverage table to user. Options: (1) proceed to merge, (2) redispatch Builder to fix concerns or improve test coverage, then re-review.
- **FAIL**: Write review to cycle doc. Present failures and test coverage table to user. Redispatch Builder with the specific failures to fix (same worktree). The Builder's `SubagentStop` hook rebuilds the cortex index; then re-dispatch Reviewer. Max 2 review-fix loops before escalating to user.
- **Source doc CONTRADICTION in review**: If the Reviewer finds a CONTRADICTION between the pitch and a source document, this is a special case. The Builder implemented the pitch correctly — the pitch itself is wrong. Present to user: "The Reviewer found that the Architect's pitch contradicts [source doc]. The Builder implemented the pitch as written, but the pitch is inconsistent with upstream requirements. Options: (1) abort and re-plan with a new Architect dispatch, (2) proceed to merge knowing the contradiction exists." **HUMAN GATE**.
- **NEEDS_INPUT**: Relay the Reviewer's questions to the user via AskUserQuestion (same proxy-question protocol as the Architect). Resume with SendMessage containing the answers and the Reviewer's `context` field.

### 6. Merge

The Builder's `SubagentStop` hook has already rebuilt the worktree cortex index. Run `cortex_check(project_root=worktree_path)` to surface staleness info for the merge summary.

Construct change-set from `git diff {baseline_sha}..HEAD` + Builder manifest. Write Builder manifest and change-set to cycle doc.

**HUMAN GATE** — Present implementation summary (files changed, tests, review verdict, deviations, cortex check results). "Approve to merge into main and proceed to Auditor phase, or provide feedback?"

- **Rejected**: Discuss options — redispatch Builder with feedback.

Safety-net commit: check worktree for uncommitted changes and commit them before merging (see ref: `merge-commands`). Call `ExitWorktree(action="keep")` to return to main repo root. Merge worktree branch into main, remove worktree/branch. Rebuild cortex on main. Single commit with structured message (see ref: `commit-format`). Capture commit SHA.

The worktree's `.pev-state.json` was removed with the worktree. The Auditor's state file is handled separately in Phase 7.

### 7. Audit

The Auditor runs on **main** (not a worktree). The merge has already happened — the Auditor reviews the merged code, updates docs, and marks stale nodes clean on the live codebase.

**Auditor mutex check** (see ref: `auditor-mutex`). Check if `.pev-state.json` exists in the main repo root. If it does, another cycle's Auditor is running — present options to the user (wait, end the other, or skip). **HUMAN GATE** if conflict detected.

When clear, write `.pev-state.json` to the main repo root with `cycle_id` and `cycle_doc_id` (no `worktree_path`).

Update status to `auditor` (see ref: `status-updates`). Dispatch `pev-auditor` subagent pointing at the **main repo** (see ref: `dispatch-prompts`).

Parse return — extract report from `---IMPACT-REPORT---` separator (see ref: `manifest-parsing`).

Handle status codes:
- **DONE**: Write Impact Report to `auditor.impact-report` section. The change ledger is already in `auditor.change-ledger` (written by Auditor as it works). Proceed to Phase 7.5 (Doc Review).
- **DONE_WITH_CONCERNS** (has `needs_fix`): Present the `needs_fix` items to the user as "these need attention." Options: (1) address them in a follow-up PEV cycle, (2) fix manually, (3) accept and proceed. Then proceed to Phase 7.5 (Doc Review).
- **CONTINUING** (or no separator): The Auditor writes partial progress and change ledger entries to the manifest as it works. Increment incarnation, redispatch. Already-marked-clean nodes are skipped automatically.
- **NEEDS_INPUT**: Relay the Auditor's questions to the user via AskUserQuestion (same proxy-question protocol as the Architect). Resume with SendMessage containing the answers and the Auditor's `context` field.

### 7.5. Doc Review

After the Auditor completes (DONE or DONE_WITH_CONCERNS), review its documentation changes.

Dispatch `pev-doc-reviewer` subagent pointing at the **main repo** (see ref: `dispatch-prompts`).

Parse return — extract review from `---DOC-REVIEW---` separator.

Handle status codes:
- **PASS**: Write review to `doc-review` section. Proceed to Phase 8.
- **PASS_WITH_CONCERNS**: Write review to `doc-review` section. Present concerns to user. Options: (1) proceed to complete, (2) redispatch Auditor to fix doc issues, then re-review.
- **FAIL**: Write review to `doc-review` section. Present failures to user. Redispatch Auditor with specific doc issues to fix (same main repo). After fix, re-dispatch Doc Reviewer. Max 2 review-fix loops before escalating to user.
- **CONTINUING** (or no separator): Write checkpoint. Increment incarnation, redispatch.
- **NEEDS_INPUT**: Relay questions to user via AskUserQuestion. Resume with SendMessage.

**Auditor fix dispatch (doc loopback):** When the Doc Reviewer returns FAIL, redispatch the Auditor with targeted fix instructions. The Auditor's CONTINUING mechanism handles partial work — already-marked-clean nodes are preserved, and the fresh Auditor reads the change ledger to know what's already done.

### 8. Complete

Create audit checkpoint (see ref: `completion-cleanup`). Update cycle manifest status to `completed`, remove `pev-active` tag.

Run efficiency analysis and present the compact summary (see ref: `completion-cleanup`):
```bash
python scripts/analyze_pev_session.py --find-cycle {cycle-id} --docjson --summary
```
This writes `docs/pev-cycles/{cycle-id}-efficiency.json` and prints a verdict. Present the summary to the user.

Clean up state file (`rm -f .pev-state.json` from main repo root — last written for the Doc Reviewer). Invoke `superpowers:finishing-a-development-branch`. Do NOT invoke `superpowers:requesting-code-review` — the PEV Reviewer (Phase 5) already covered spec compliance, functionality preservation, and code quality.

## Error Handling

- **Agent dispatch failure**: Check `.claude/agents/pev-{agent}.md` exists; suggest `/agents` to reload.
- **Worktree failure**: Check `git worktree list` for stale entries.
- **Merge conflicts**: Present to user and resolve before proceeding.
- **cortex_check hangs**: Timeout and retry; if persistent, proceed with manual review scope from Builder's change-set.
- **Failure at any point**: Update status to `incomplete`. Keep `pev-active` tag so the cycle can be resumed.
