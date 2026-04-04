# PEV Orchestrator Reference

## Naming Conventions

Cycle ID format: `pev-YYYY-MM-DD-{slug}`

- Date: today's date
- Slug: derived from user request — lowercase, hyphens only, truncated to 40 chars
- Example: `pev-2026-03-21-add-history-filtering`

Collision check:
```bash
ls docs/pev-cycles/ 2>/dev/null | grep "^{slug-prefix}"
```
If collision exists, append `-2`, `-3`, etc.

Worktree path: `pev-worktrees/{cycle-id}`

Branch name: `pev/{cycle-id}`

Cortex doc ID: `cortex::docs.pev-cycles.{cycle-id}` — the project prefix comes from `cortex.toml` (`project_id = "cortex"`), which is a tracked file present in both the main repo and worktrees. All cortex tools use this consistent prefix.

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
- `id`: `"pev-cycles/{cycle-id}"` (filename hint)
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

After writing, the doc is indexed as `cortex::docs.pev-cycles.{cycle-id}`. Store this as `cycle_doc_id` in pev-state.json.

All other sections start with placeholder content — Architect, Builder, and Auditor fill them.

## State File

Write `.claude/pev-state.json` before each subagent dispatch. The doc-scope, cortex-scope, worktree-scope, and tool-budget hooks all read this file.

Format:
```json
{
  "cycle_id": "{cycle-id}",
  "cycle_doc_id": "{cycle_doc_id}",
  "worktree_path": "{absolute-path-to-worktree}",
  "counter_file": "/tmp/pev-{cycle-id}-{agent}-{incarnation}"
}
```

- `cycle_doc_id`: the full cortex doc ID for the cycle manifest: `cortex::docs.pev-cycles.{cycle-id}`. The `cortex` prefix comes from `cortex.toml` (`project_id`). All dispatch prompts and hooks use this value.
- `worktree_path`: absolute path to the worktree created in Phase 1. All agents receive this — hooks use it to scope Write/Edit and cortex `project_root` calls.
- `{agent}`: `architect`, `builder`, `reviewer`, or `auditor`
- `{incarnation}`: starts at 1, increments per re-dispatch
- A fresh counter_file path (file doesn't exist yet) starts at 0 automatically — no explicit reset needed
- Use the Write tool to create this file

## Worktree Commands

The orchestrator creates the worktree in Phase 1 (Intake), before any subagent is dispatched. All agents run inside this worktree. Merge happens in Phase 7 (Complete).

**Create worktree (Phase 1 — Intake):**
```bash
git worktree add -b pev/{cycle-id} pev-worktrees/{cycle-id} HEAD
```

**Install dependencies (reuse cached packages):**
```bash
poetry install --no-root -C pev-worktrees/{cycle-id}
```
This creates a new venv for the worktree and installs all deps from the lock file. With a warm pip cache this is fast. The `--no-root` flag skips installing the project package itself (not needed — agents import from local source).

**Note:** Each worktree creates a venv in `{cache-dir}/virtualenvs/`. These are not auto-cleaned when the worktree is removed. Periodically clean up stale venvs with `poetry env list` and `poetry env remove {name}` from the main repo.

**Install frontend deps (if package.json exists):**
```bash
if [ -f pev-worktrees/{cycle-id}/cortex/viz/static/ts/package.json ]; then
  cd pev-worktrees/{cycle-id}/cortex/viz/static/ts && npm install
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
`{worktree_path}` = absolute path to `pev-worktrees/{cycle-id}`.

**Check for stale worktrees:**
```bash
git worktree list
```

## Merge Commands

Phase 7 (Complete) — after all agents finish in the worktree. See Completion Cleanup for the full step-by-step sequence.

**Merge worktree branch into main:**
```bash
git merge --no-commit --no-ff pev/{cycle-id}
```
Run from the main repo directory. If conflicts exist, present them to the user and resolve before proceeding.

**Post-merge rebuild:**
```
cortex_build(project_root="{main_repo_path}")
cortex_check(project_root="{main_repo_path}")
```

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
Use absolute paths rooted there. Use git -C {worktree_path} for git commands.
For pytest: cd {worktree_path} && poetry run pytest (cd is required so Python imports worktree code).
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

This is a TARGETED FIX dispatch from the Reviewer. Fix ONLY the following issues identified by the Reviewer:
{review failures/concerns}
```

**Builder (fix — auditor loopback):**
```
You are the PEV Builder for cycle {cycle_id} (targeted fix — auditor loopback iteration {N}).

Cycle manifest doc ID: {cycle_doc_id}
Project root: {worktree_path}

This is a TARGETED FIX dispatch. The Auditor found issues that need code changes. Fix ONLY the following items:
{needs_fix items}

You are working in the same worktree as the original build. Commit your fixes so the orchestrator can re-dispatch the Auditor.
```

**Reviewer:**
```
You are the PEV Reviewer for cycle {cycle_id}.

Cycle manifest doc ID: {cycle_doc_id}
Project root: {worktree_path}

Review the Builder's code changes against the Architect's pitch. You are read-only.

The Architect's pitch is in the cycle manifest (sections: user-stories, solution-sketch, constraints, affected-nodes).
The Builder's build plan and progress are in the cycle manifest. Read builder.build-plan, builder.progress, and the decisions section for context. Also check architect.required-artifacts against the Builder's output.

Git diff of the Builder's changes:
{git diff output from worktree branch vs baseline}

Follow your skill instructions. Return your review verdict when done.
```

**Reviewer (re-review after fix):**
Add: `RE-REVIEW: The Builder has addressed the following issues from your previous review. Verify the fixes and re-evaluate: {previous failures}`

**Auditor (initial):**
```
You are the PEV Auditor for cycle {cycle_id}.

Cycle manifest doc ID: {cycle_doc_id}
Project root: {worktree_path}

Read the cycle manifest, then run cortex_build + cortex_check to determine the review scope. Follow the Auditor Reference Protocol for the full checklist.

Write your doc change ledger to auditor.change-ledger as you work — each entry should include reason, trigger_node, category, and diff_command so changes are traceable in cortex viz.

Return your Impact Report when done.
```

**Auditor (continuation):**
Add: `CONTINUATION: A previous Auditor incarnation was dispatched and returned CONTINUING. Already-marked-clean nodes will not appear stale on cortex_check. Previous Auditor checkpoint: {checkpoint}`

**All dispatches use:** `subagent_type="pev-{agent}"`. Do NOT use `isolation: "worktree"` — the orchestrator owns the worktree lifecycle.

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
- `architect.changelog-draft`

Use `cortex_read_doc` with `section=` for each.

**Step 2: Assemble the prompt.**

Use the Builder (initial) dispatch template from the Dispatch Prompts section, substituting the pitch text into the `ARCHITECT PITCH` placeholder.

Source code is not inlined. The Builder reads source on demand using cortex tools (`cortex_source`, `cortex_graph`, `cortex_search`) against the cortex DB snapshot (copied via `cortex_checkout` during worktree setup). The Architect's task list gives the Builder specific node IDs to look up per task, so it can start implementing immediately with targeted reads.

**When NOT to inline the pitch:**

- Builder continuations (CONTINUING status): the Builder already has context from its previous incarnation
- Builder fix dispatches (review/auditor loopback): these are targeted fixes with their own context

## Status Updates

Use `cortex_update_section` to update the status section at each phase transition.

**Planning → Builder:**
```
cortex_update_section(
  section_id="{cycle_doc_id}::status",
  content="Phase: builder\nBaseline SHA: {baseline_sha}\nStarted: {original-timestamp}\nCycle ID: {cycle-id}\n\nPhase transitions:\n- planning: {original-timestamp} — cycle created\n- builder: {now-timestamp} — plan approved"
)
```

**Builder → Auditor:**
Add: `- auditor: {now-timestamp} — builder complete, reviewed`

**Auditor → Completed:**
Add: `- completed: {now-timestamp} — merged, committed as {commit_sha}`
Also add: `Commit SHA: {commit_sha}` and `Completed: {now-timestamp}`

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

## Loopback Mechanics

When the Auditor returns `DONE_WITH_CONCERNS` with `needs_fix` items, dispatch a targeted Builder to fix them in the same worktree.

**Rules:**
- Maximum 2 loopback iterations
- Builder fix happens in the **same worktree** — no separate fix worktree or branch (merge hasn't happened yet)
- Use the Builder fix (auditor loopback) dispatch prompt (see Dispatch Prompts section)
- After Builder commits the fix, re-index the worktree: `cortex_build(project_root="{worktree_path}")`
- Re-dispatch the Auditor pointing at the same worktree

**After max iterations:**
If the Auditor still returns `needs_fix` after iteration 2, surface remaining items to the user:
```
Auditor found remaining issues after 2 Builder loopback iterations:
{remaining needs_fix items}

Options:
1. Fix these manually and re-run the Auditor
2. Accept the current state and proceed to merge
3. Abort the cycle
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

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

Capture the commit SHA: `git rev-parse HEAD`

## Completion Cleanup

Phase 7 (Complete) — after human approves final audit results.

1. **Merge worktree into main** (see Merge Commands section):
```bash
git merge --no-commit --no-ff pev/{cycle-id}
```

2. **Rebuild cortex on main:**
```
cortex_build(project_root="{main_repo_path}")
cortex_check(project_root="{main_repo_path}")
```

3. **Create audit checkpoint:**
```bash
poetry run cortex history checkpoint . --message "pev-cycle-{cycle-id}-audit-complete"
```

4. **Commit** with structured message (see Commit Format section). This finalizes the merge.

5. **Remove worktree and branch** (must be after commit — `git branch -d` requires the branch to be merged into HEAD):
```bash
git worktree remove pev-worktrees/{cycle-id}
git branch -d pev/{cycle-id}
```

6. **Update status to completed** (see Status Updates section).

7. **Remove pev-active tag:** Read the full doc with `cortex_read_doc`, then `cortex_write_doc` to rewrite with `pev-active` removed from the tags list. Keep `pev-cycle` tag.

8. **Run efficiency analysis:** Find the current session's JSONL file and generate the efficiency report.
```bash
python scripts/analyze_pev_session.py --find-cycle {cycle-id} --docjson --summary
```
This writes a DocJSON report to `docs/pev-cycles/{cycle-id}-efficiency.json` and prints a compact summary. Present the summary to the user.

9. **Delete state file:**
```bash
rm -f .claude/pev-state.json
```

10. **Invoke** `superpowers:finishing-a-development-branch` to present merge/PR options.

## Error Handling

**Agent dispatch fails:** Check that `.claude/agents/pev-{agent}.md` exists. Suggest user run `/agents` to reload definitions.

**cortex_write_doc fails:** Check that `docs/pev-cycles/` directory exists.

**Worktree creation fails:** Check for stale worktrees with `git worktree list` and remove them.

**Merge conflicts:** Present conflicts to the user and resolve before proceeding.

**cortex_check hangs:** Known issue — set a timeout and retry. If it hangs again, proceed with manual review scope based on the Builder's change-set.

**Failure at any point:** Update the cycle manifest status to `incomplete`. The `pev-active` tag stays — the cycle can be resumed on the next `/pev-cycle` invocation.

**Subagent returns CONTINUING:** Write checkpoint to cycle manifest and redispatch (see Manifest Parsing section).
