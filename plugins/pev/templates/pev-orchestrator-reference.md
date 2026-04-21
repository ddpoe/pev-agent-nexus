# PEV Orchestrator Reference

## Naming Conventions

Cycle ID format: `pev-YYYY-MM-DD-{slug}`

- Date: today's date
- Slug: derived from user request — lowercase, hyphens only, truncated to 40 chars
- Example: `pev-2026-03-21-add-history-filtering`

Collision check:
```bash
ls docs/pev/cycles/ 2>/dev/null | grep "^{slug-prefix}"
```
If collision exists, append `-2`, `-3`, etc.

Worktree path: `.claude/worktrees/{cycle-id}`

Branch name: `worktree-{cycle-id}`

Cortex doc ID: `{project_id}::docs.pev.cycles.{cycle-id}` — the `{project_id}` prefix MUST be read from `cortex.toml` (`project_id` field) at runtime. Do NOT hardcode it. Read `cortex.toml` in the project root and extract the `project_id` value. Example: if `project_id = "pm_mvp"`, the doc ID is `pm_mvp::docs.pev.cycles.{cycle-id}`.

## Manifest Creation

Use `cortex_write_doc` to create the cycle manifest. Read the cycle manifest template from `${CLAUDE_PLUGIN_ROOT}/templates/cycle-manifest-template.json` for the full section layout and instructions.

Call pattern:
```
cortex_write_doc(
  project_root="{worktree_path}",
  doc_json='{JSON with title, id, tags, sections}'
)
```

Required values to fill:
- `title`: `"PEV Cycle: {cycle-id}"`
- `id`: `"pev/cycles/{cycle-id}"` (filename hint)
- `tags`: `["pev-cycle", "pev-active"]`
- `status.content`: Phase, baseline SHA, timestamp, cycle ID
- `request.content`: User's request verbatim
- `architect.required-artifacts`: Filled by Architect
- `decisions`: Accumulated by all agents
- `builder.build-plan`: Filled by Builder
- `builder.progress`: Updated by Builder as it works
- `builder.manifest`: Filled by Orchestrator from Builder return
- `review`: Filled by Orchestrator from Reviewer return
- `auditor.change-ledger`: Filled by Auditor as it works
- `auditor.impact-report`: Filled by Orchestrator from Auditor return

After writing, the doc is indexed as `{project_id}::docs.pev.cycles.{cycle-id}`. Store this as `cycle_doc_id` in `.pev-state.json`.

All other sections start with placeholder content — Architect, Builder, and Auditor fill them.

## State File

Write `.pev-state.json` to the **worktree root** (the cwd after `EnterWorktree`) once per cycle, before the first subagent dispatch. The doc-scope, cortex-scope, and worktree-scope hooks all find this file by reading the `cwd` field from their input and locating `.pev-state.json` at that root. The file does NOT need to be rewritten between phases — hooks dispatch per-agent behavior on the `agent_type` field in hook input, not on state.

For the **Auditor phase only** (runs on main after worktree is removed), write `.pev-state.json` to the **main repo root**. This is a serial mutex — check for an existing `.pev-state.json` on main before writing (see Auditor Mutex section).

Format:
```json
{
  "cycle_id": "{cycle-id}",
  "cycle_doc_id": "{cycle_doc_id}",
  "worktree_path": "{absolute-path-to-worktree}"
}
```

- `cycle_doc_id`: the full cortex doc ID for the cycle manifest: `{project_id}::docs.pev.cycles.{cycle-id}`. The `{project_id}` MUST be read from `cortex.toml` at runtime — it varies per project. All dispatch prompts and hooks use this value.
- `worktree_path`: absolute path to the worktree created in Phase 1. Builder and Reviewer receive this — hooks use it to scope Write/Edit, Bash, and cortex `project_root` calls. Not used for Auditor (runs on main).
- Tool-budget counters are keyed on the subagent's `agent_id` (read by hooks from stdin JSON) at `/tmp/pev-counter-<agent_id>.txt`. Files are auto-created on first increment and auto-deleted by the `SubagentStop` hook. No counter_file field needed in state.
- Use the Write tool to create this file.

## Auditor Mutex

Before dispatching the Auditor, check if `.pev-state.json` exists in the main repo root:

```bash
[ -f .pev-state.json ] && cat .pev-state.json
```

If it exists, another cycle's Auditor is running. Present to user:
```
Another PEV cycle's Auditor is active: {cycle_id from existing state file}
Options:
1. Wait for it to finish (check again later)
2. End the other Auditor and proceed (deletes the state file)
3. Skip Auditor phase for this cycle
```

**HUMAN GATE** — wait for user decision. If user chooses option 2, `rm -f .pev-state.json` and proceed.

When clear, write `.pev-state.json` to main repo root with `cycle_id`, `cycle_doc_id`, and `counter_file` for the Auditor (no `worktree_path` — Auditor runs on main). Delete it in Phase 8 cleanup.

## Worktree Commands

The orchestrator creates the worktree in Phase 1 (Intake), before any subagent is dispatched. Builder and Reviewer run inside this worktree. Merge happens in Phase 6 (Merge), and the Auditor runs on main in Phase 7.

**Create worktree (Phase 1 — Intake):**
```
EnterWorktree(name="{cycle-id}")
```
Creates `.claude/worktrees/{cycle-id}/` with branch `worktree-{cycle-id}` based on HEAD. Moves session cwd to the worktree.

**Verify worktree base (immediately after EnterWorktree):**
`EnterWorktree` may base the new branch on the remote tracking branch (e.g., `origin/main`) instead of local HEAD. This means the worktree starts from the remote state, missing any local commits not yet pushed.

```bash
git rev-parse HEAD
```

Compare the output against the baseline SHA captured before `EnterWorktree`. If they differ:
```bash
git rebase {baseline_sha}
```

This rebases the worktree branch onto the local HEAD. Unlike `reset --hard`, rebase preserves any commits already on the branch — safer if the worktree somehow has work on it.

**Install dependencies (reuse cached packages):**
```bash
poetry install --no-root
```
This creates a new venv for the worktree and installs all deps from the lock file. With a warm pip cache this is fast. The `--no-root` flag skips installing the project package itself (not needed — agents import from local source).

**Note:** Each worktree creates a venv in `{cache-dir}/virtualenvs/`. These are not auto-cleaned when the worktree is removed. Periodically clean up stale venvs with `poetry env list` and `poetry env remove {name}` from the main repo.

**Install frontend deps (if package.json exists):**
```bash
if [ -f cortex/viz/static/ts/package.json ]; then
  cd cortex/viz/static/ts && npm install
fi
```

**Copy cortex DB into worktree:**
```
cortex_checkout(
  project_root="{main_repo_path}",
  worktree_path="{worktree_path}"
)
```

`{main_repo_path}` = the main working tree path from `git worktree list`.
`{worktree_path}` = absolute path to `.claude/worktrees/{cycle-id}`.

**Check for stale worktrees:**
```bash
git worktree list
```

## Git Command Convention

**Always use `git -C <path>` instead of `cd <path> && git ...`** when targeting a directory other than cwd. The `-C` flag is a single command that doesn't require compound shell permission. When cwd is already the target, plain `git` is fine.

## Merge Commands

Phase 6 (Merge) — after Review passes. Merge happens before the Auditor runs. See the **Merge Cleanup** section for the full numbered procedure.

**Get changed files for change-set:**
```bash
git diff --name-only {baseline_sha}..HEAD
```

## Dispatch Prompts

**Architect (initial):**
```
You are the PEV Architect for cycle {cycle_id}.

Cycle manifest doc ID: {cycle_doc_id}
Project root: {worktree_path}

User request:
{user request verbatim}

Read the cycle manifest, explore the codebase, engage with the user (brainstorm if appropriate), and write your plan to the cycle manifest. Follow your skill instructions.
```

**Architect (revision):**
Append: `REVISION REQUESTED. Read your previous plan from the cycle manifest and revise based on this feedback: {user feedback}`

**Builder (initial):**

Before dispatching, the Orchestrator reads the Architect's pitch from the cycle manifest and inlines the text (see Builder Context Handoff section).

```
You are the PEV Builder for cycle {cycle_id}.

Cycle manifest doc ID: {cycle_doc_id}
Project root: {worktree_path}

Your working directory is: {worktree_path}
Your cwd is already set to this directory. Use git commands directly (no -C flag needed).
For pytest: poetry run pytest (cwd is already the worktree, so imports are correct).
The worktree has a cortex DB snapshot — use {worktree_path} as project_root for all cortex tool calls.

== ARCHITECT PITCH ==

{full pitch text: problem, user-stories, solution-sketch, constraints, affected-nodes, tasks, required-artifacts, changelog-draft}

== INSTRUCTIONS ==

- Follow the task list in the pitch. Work one task at a time.
- Use cortex_source/cortex_graph/cortex_search(scope="code") to read code.
- cortex_source output includes file path and line range — use those for Edit calls.
- All code changes go in the worktree at the project root above.
- You have doc-write access to the cycle manifest (scoped by doc-scope hook). Write your build plan to builder.build-plan, update progress in builder.progress, and record decisions in the decisions section.
- Follow your skill instructions. Return your implementation manifest when done.
```

**Builder (continuation):**
Add: `CONTINUATION: A previous Builder incarnation was dispatched and returned CONTINUING. Your code changes from the previous incarnation are already on disk in the worktree. Previous Builder checkpoint: {checkpoint}`

Note: continuations do NOT need the full pitch re-inlined — the Builder already has it from the initial dispatch context.

**Builder (fix — review loopback):**
```
You are the PEV Builder for cycle {cycle_id} (targeted fix — review iteration {N}).

Cycle manifest doc ID: {cycle_doc_id}
Project root: {worktree_path}

Your cwd is already set to this directory. Use git commands directly (no -C flag needed).
For pytest: poetry run pytest (cwd is already the worktree, so imports are correct).

This is a TARGETED FIX dispatch from the Reviewer. Fix ONLY the following issues identified by the Reviewer:
{review failures/concerns}
```

**Reviewer:**
```
You are the PEV Reviewer for cycle {cycle_id}.

Cycle manifest doc ID: {cycle_doc_id}
Project root: {worktree_path}

Your cwd is already set to this directory. Use git commands directly (no -C flag needed).
For pytest: poetry run pytest (cwd is already the worktree, so imports are correct).

Review the Builder's code changes against the Architect's pitch AND the pitch's source documents. You are read-only. Your default stance is skeptical.

**Read the pitch FIRST** (sections: problem, user-stories, solution-sketch, constraints, source-documents, required-artifacts). Form expectations before reading the Builder's notes.

Then read the Builder's context: builder.build-plan, builder.progress, and the decisions section. Note tensions between Builder claims and Architect expectations.

Files changed by the Builder:
{git diff --stat output from worktree branch vs baseline}

Use cortex tools (cortex_diff, cortex_source, cortex_graph) to review the actual code changes on demand.

Run the test suite first (Pass 0). Cross-check source documents (Pass 1). Then reverse-map every code change to a user story or deviation (Pass 2). Include test_coverage, reverse_mapping, and deviation_tribunal in your verdict.

Follow your skill instructions. Return your review verdict when done.
```

**Reviewer (re-review after fix):**
Add: `RE-REVIEW: The Builder has addressed the following issues from your previous review. Verify the fixes and re-evaluate: {previous failures}`

**Auditor (initial):**
```
You are the PEV Auditor for cycle {cycle_id}.

Cycle manifest doc ID: {cycle_doc_id}
Project root: {main_repo_path}

The merge has already happened — you are running on the live codebase (main), not a worktree. Use {main_repo_path} as project_root for all cortex tool calls.

Read the cycle manifest, then run cortex_build + cortex_check to determine the review scope. Follow the Auditor Reference Protocol for the full checklist.

Write your doc change ledger to auditor.change-ledger as you work — each entry should include reason, trigger_node, category, and diff_command so changes are traceable in cortex viz.

Return your Impact Report when done.
```

**Auditor (continuation):**
Add: `CONTINUATION: A previous Auditor incarnation was dispatched and returned CONTINUING. Already-marked-clean nodes will not appear stale on cortex_check. Previous Auditor checkpoint: {checkpoint}`

**Doc Reviewer (initial):**
```
You are the PEV Doc Reviewer for cycle {cycle_id}.

Cycle manifest doc ID: {cycle_doc_id}
Project root: {main_repo_path}

The Auditor has completed its documentation updates on the live codebase (main). Review the Auditor's doc changes against templates and the actual implementation.

Read the cycle manifest for context: Architect pitch (what was requested), Builder manifest (what was built), Auditor change ledger (what docs were changed), and Auditor impact report (audit summary).

Use cortex tools to verify doc content matches the code. Follow your skill instructions. Return your review verdict when done.
```

**Doc Reviewer (re-review after Auditor fix):**
Add: `RE-REVIEW: The Auditor has addressed the following doc issues from your previous review. Verify the fixes and re-evaluate: {previous failures}`

**Auditor (doc fix — doc review loopback):**
```
You are the PEV Auditor for cycle {cycle_id} (targeted doc fix — doc review iteration {N}).

Cycle manifest doc ID: {cycle_doc_id}
Project root: {main_repo_path}

This is a TARGETED DOC FIX dispatch from the Doc Reviewer. Fix ONLY the following documentation issues:
{doc review failures}

Your previous change ledger and marked-clean nodes are preserved. Focus on the specific doc issues identified.
```

**All dispatches use:** `subagent_type="pev-{agent}"` (agents: `architect`, `builder`, `reviewer`, `auditor`, `doc-reviewer`). Do NOT use `isolation: "worktree"` — the orchestrator owns the worktree lifecycle.

## Handling Architect doc_edits

When the Architect's NEEDS_INPUT payload includes `doc_edits`, process them before (or alongside) questions:

1. Print the Architect's preamble (if any)
2. For each doc_edit entry:
   ```
   The Architect proposes updating {doc_id}:
   Section: {section_id}
   Reason: {reason}
   Currently: {current_summary}
   Proposed: {proposed_content}
   ```
   Present via AskUserQuestion: "Approve this source doc edit?" with options: Approve / Reject / Reject with note.
3. Apply approved edits:
   ```
   cortex_update_section(
     section_id="{section_id}",
     content="{proposed_content}"
   )
   ```
4. Collect results into `doc_edit_results` array
5. Process questions (if any) via AskUserQuestion
6. Resume Architect with SendMessage:
   ```json
   {"answers": {"question text": "selected label"}, "doc_edit_results": [{"section_id": "...", "status": "applied|rejected", "user_note": "..."}], "context": "...architect's context field verbatim..."}
   ```

## Builder Context Handoff

Before dispatching the Builder, the Orchestrator reads the Architect's pitch from the cycle manifest and inlines the text into the dispatch prompt. This gives the Builder the problem, user stories, solution sketch, constraints, and — critically — the **task list** with specific cortex node IDs per task.

**Step 1: Read the pitch sections from the cycle manifest.**

Read these sections and concatenate them into a single text block:
- `architect.problem`
- `architect.user-stories`
- `architect.solution-sketch`
- `architect.constraints`
- `architect.affected-nodes`
- `architect.required-artifacts`
- `architect.tasks`
- `architect.test-plan`
- `architect.changelog-draft`

Use `cortex_read_doc` with `section=` for each.

**Step 2: Assemble the prompt.**

Use the Builder (initial) dispatch template from the Dispatch Prompts section, substituting the pitch text into the `ARCHITECT PITCH` placeholder.

Source code is not inlined. The Builder reads source on demand using cortex tools (`cortex_source`, `cortex_graph`, `cortex_search`) against the cortex DB snapshot (copied via `cortex_checkout` during worktree setup). The Architect's task list gives the Builder specific node IDs to look up per task, so it can start implementing immediately with targeted reads.

**When NOT to inline the pitch:**

- Builder continuations (CONTINUING status): the Builder already has context from its previous incarnation
- Builder fix dispatches (review loopback): these are targeted fixes with their own context

## Status Updates

Use `cortex_update_section` to update the status section at each phase transition.

**Planning → Builder:**
```
cortex_update_section(
  section_id="{cycle_doc_id}::status",
  content="Phase: builder\nBaseline SHA: {baseline_sha}\nStarted: {original-timestamp}\nCycle ID: {cycle-id}\n\nPhase transitions:\n- planning: {original-timestamp} — cycle created\n- builder: {now-timestamp} — plan approved"
)
```

**Builder → Merge:**
Add: `- merge: {now-timestamp} — builder complete, reviewed, merging`
Also add: `Commit SHA: {commit_sha}`

**Merge → Auditor:**
Add: `- auditor: {now-timestamp} — merged as {commit_sha}, auditing on main`

**Auditor → Doc Review:**
Add: `- doc-review: {now-timestamp} — audit complete, reviewing docs`

**Doc Review → Completed:**
Add: `- completed: {now-timestamp} — doc review passed`
Also add: `Completed: {now-timestamp}`

**Failure at any point:**
Set `Phase: incomplete` with reason. Keep the `pev-active` tag so the cycle can be resumed.

## Manifest Parsing

**Builder returns:** Look for `---MANIFEST---` separator in the completion message. Everything after it is the JSON manifest.

**Reviewer returns:** Look for `---REVIEW---` separator. Everything after it is JSON review findings. Write to the `review` section:
```
cortex_update_section(
  section_id="{cycle_doc_id}::review",
  content="{formatted review findings}"
)
```

**Auditor returns:** Look for `---IMPACT-REPORT---` separator. Everything after it is the JSON impact report.

**Doc Reviewer returns:** Look for `---DOC-REVIEW---` separator. Everything after it is JSON review findings. Write to the `doc-review` section:
```
cortex_update_section(
  section_id="{cycle_doc_id}::doc-review",
  content="{formatted doc review findings}"
)
```

**Auditor change ledger:** The Auditor writes change_ledger entries to `auditor.change-ledger` as it works (not just at return). Write the final impact-report to `auditor.impact-report`.

**No separator found:** The agent was cut off by the `maxTurns` limit before writing a structured return. Treat this as `CONTINUING` — the work on disk (code for Builder, marked-clean nodes for Auditor) is the real state. Use the agent's last message as the checkpoint summary.

**Writing to manifest:**
```
cortex_update_section(
  section_id="{cycle_doc_id}::builder.manifest",
  content="{formatted manifest}"
)
```

**Checkpoint sub-sections (for CONTINUING):**
```
cortex_add_section(
  doc_id="{cycle_doc_id}",
  parent_section_id="builder",
  section_id="checkpoint-{incarnation}",
  heading="Builder Checkpoint (Incarnation {N})",
  content="{progress summary}"
)
```

## Commit Format

Single commit containing all changes (code + docs).

```bash
git add -A
git commit -m "$(cat <<'EOF'
{commit message summarizing the PEV cycle}

PEV Cycle: {cycle-id}
Architect: {scope summary}
Builder: {implementation summary}
Auditor: {audit summary — nodes reviewed, docs updated}

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Capture the commit SHA: `git rev-parse HEAD`

## Merge Cleanup

Phase 6 (Merge) — after Review passes and human approves.

1. **Safety-net commit** — ensure the worktree branch has no uncommitted changes before merging. If cwd is the worktree, use plain `git`. If cwd is elsewhere, use `git -C {worktree_path}`:
```bash
git status --porcelain
```
If output is non-empty, commit the stragglers:
```bash
git add -A
git commit -m "PEV: commit uncommitted changes before merge ({cycle-id})"
```

2. **Exit worktree** (return to main repo root):
```
ExitWorktree(action="keep")
```

3. **Merge worktree into main** (see Merge Commands section):
```bash
git merge --no-commit --no-ff worktree-{cycle-id}
```

4. **Rebuild cortex on main:**
```
cortex_build(project_root="{main_repo_path}")
cortex_check(project_root="{main_repo_path}")
```

5. **Commit** with structured message (see Commit Format section). This finalizes the merge. Capture commit SHA.

6. **Remove worktree and branch** (must be after commit — `git branch -d` requires the branch to be merged into HEAD):
```bash
git worktree remove .claude/worktrees/{cycle-id}
git branch -d worktree-{cycle-id}
```

7. **State file cleanup** — the worktree's `.pev-state.json` was removed with the worktree. No action needed here. The Auditor's state file is written separately (see Auditor Mutex section).

## Completion Cleanup

Phase 8 (Complete) — after Auditor finishes.

1. **Create audit checkpoint:**
```bash
poetry run cortex history checkpoint . --message "pev-cycle-{cycle-id}-audit-complete"
```

2. **Update status to completed** (see Status Updates section).

3. **Remove pev-active tag:** Read the full doc with `cortex_read_doc`, then `cortex_write_doc` to rewrite with `pev-active` removed from the tags list. Keep `pev-cycle` tag.

4. **Run efficiency analysis:** Find the current session's JSONL file and generate the efficiency report.
```bash
python scripts/analyze_pev_session.py --find-cycle {cycle-id} --docjson --summary
```
This writes a DocJSON report to `docs/pev/cycles/{cycle-id}-efficiency.json` and prints a compact summary. Present the summary to the user.

5. **Delete Auditor state file:**
```bash
rm -f .pev-state.json
```

6. **Invoke** `superpowers:finishing-a-development-branch` to present merge/PR options.

## Error Handling

**Agent dispatch fails:** Check that the pev plugin is installed and enabled (`claude plugin list`). Agent definitions ship in the plugin at `${CLAUDE_PLUGIN_ROOT}/agents/pev-{agent}.md`. If the plugin looks fine but dispatch still fails, see `plugins/hook-spike/TROUBLESHOOTING.md` §7 for known failure modes.

**cortex_write_doc fails:** Check that `docs/pev/cycles/` directory exists.

**Worktree creation fails:** Check for stale worktrees with `git worktree list` and remove them.

**Merge conflicts:** Present conflicts to the user and resolve before proceeding.

**cortex_check hangs:** Known issue — set a timeout and retry. If it hangs again, proceed with manual review scope based on the Builder's change-set.

**Failure at any point:** Update the cycle manifest status to `incomplete`. The `pev-active` tag stays — the cycle can be resumed on the next `/pev-cycle` invocation.

**Subagent returns CONTINUING:** Write checkpoint to cycle manifest and redispatch (see Manifest Parsing section).
