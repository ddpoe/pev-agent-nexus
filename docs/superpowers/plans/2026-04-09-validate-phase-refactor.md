# Validate Phase Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the PEV Validate phase to separate doc writing from doc reviewing, move code quality checks to the code Reviewer, and establish a write-then-review cycle consistent with the Builder/Reviewer pattern.

**Architecture:** The Auditor becomes a focused "doc writer + staleness manager" (post-implementation updates, staleness review, automated doc checks). A new Doc Reviewer agent verifies the Auditor's doc changes against templates and implementation. PEV-specific code quality checks (logging, test annotations, workflow markers) move to the existing code Reviewer as Pass 4, where the Builder can fix them pre-merge. The orchestrator gains a Doc Review sub-phase after Audit with loopback support.

**Tech Stack:** Claude Code agent definitions (YAML frontmatter + markdown), skill files (markdown), orchestrator reference templates, cycle manifest (DocJSON)

---

## File Map

### Modified files

| File | Responsibility change |
|------|----------------------|
| `.claude/skills/pev-auditor/SKILL.md` | Remove Step 4d (PEV-specific checks), update Impact Report format, update status code table |
| `.claude/templates/auditor-reference-protocol.md` | Remove PEV-Specific Checks section (6-8), update Quick Reference Checklist |
| `.claude/agents/pev-auditor.md` | Remove `cortex_workflow_list`, `cortex_workflow_detail` tools; adjust tool budget |
| `.claude/skills/pev-reviewer/SKILL.md` | Add Pass 4 (PEV-specific checks), update return format, update progress section |
| `.claude/agents/pev-reviewer.md` | Add `cortex_workflow_list`, `cortex_workflow_detail` tools; adjust tool budget |
| `.claude/skills/pev-cycle/SKILL.md` | Add Phase 7.5 (Doc Review) between Audit and Complete, add loopback handling |
| `.claude/templates/pev-orchestrator-reference.md` | Add Doc Reviewer dispatch prompt, update status transitions |
| `.claude/templates/cycle-manifest-template.json` | Add `doc-review` section |

### New files

| File | Purpose |
|------|---------|
| `.claude/agents/pev-doc-reviewer.md` | Agent definition — read-only tools + cycle manifest write access |
| `.claude/skills/pev-doc-reviewer/SKILL.md` | Behavioral instructions — reviews Auditor's doc changes |

### Plugin mirrors

Every `.claude/` change is mirrored to `plugins/pev/` at the same relative path:
- `.claude/agents/pev-*.md` → `plugins/pev/agents/pev-*.md`
- `.claude/skills/pev-*/SKILL.md` → `plugins/pev/skills/pev-*/SKILL.md`
- `.claude/templates/*` → `plugins/pev/templates/*`

Plugin mirrors are identical copies. Each task below specifies both paths.

---

### Task 1: Remove PEV-specific checks from Auditor skill

**Files:**
- Modify: `.claude/skills/pev-auditor/SKILL.md`
- Modify: `plugins/pev/skills/pev-auditor/SKILL.md`

This task removes Step 4d (PEV-Specific Checks) from the Auditor skill, updates the Impact Report format, and adjusts the status code table and budget management section.

- [ ] **Step 1: Remove Step 4d from the Auditor skill**

In `.claude/skills/pev-auditor/SKILL.md`, delete the entire `#### 4d. PEV-Specific Checks` block (lines 173-178) which contains checks 6 (logging audit), 7 (test annotation audit), and 8 (workflow step markers).

- [ ] **Step 2: Update the Impact Report `checks_completed` field**

In the Impact Report JSON template (inside Step 6), change:
```json
"checks_completed": {
    "staleness_review": true,
    "automated_checks": true,
    "pev_specific_checks": true,
    "final_verification": true
}
```
to:
```json
"checks_completed": {
    "staleness_review": true,
    "automated_checks": true,
    "final_verification": true
}
```

- [ ] **Step 3: Remove PEV-specific categories from `needs_fix`**

In the Impact Report JSON template, remove the `logging`, `test_budget`, and `workflow_markers` categories from the `needs_fix[].category` enum. The remaining categories are: `code_bug`, `needs_new_tests`.

Update the example `needs_fix` entry if it uses one of the removed categories.

- [ ] **Step 4: Update the status code table**

In the Status Codes section, update the `DONE` description. Change:
> `DONE` — **All steps completed** — staleness review (4b), automated checks (4c), PEV-specific checks (4d), and final verification (Step 5)

to:
> `DONE` — **All steps completed** — post-implementation updates (4a), staleness review (4b), automated checks (4c), and final verification (Step 5)

Update the critical distinction note similarly. Change:
> **Critical distinction:** `DONE` means all 4 sub-steps of Step 4 (4a, 4b, 4c, 4d) AND Step 5 are finished. If you completed the staleness review (4b) but haven't run the automated checks (4c) or PEV-specific checks (4d), you are NOT done

to:
> **Critical distinction:** `DONE` means all 3 sub-steps of Step 4 (4a, 4b, 4c) AND Step 5 are finished. If you completed the staleness review (4b) but haven't run the automated checks (4c), you are NOT done

- [ ] **Step 5: Update budget management references**

In the Budget Management section, the warning level text says "are you through the post-implementation updates (4a) and into the staleness review (4b)?" — this is still correct. No change needed.

In the CONTINUING handling section, update `checks_completed` references to remove `pev_specific_checks`. Change the "Steps remaining" bullet:
> Steps remaining — staleness review done but automated checks (4c) or PEV-specific checks (4d) not started yet

to:
> Steps remaining — staleness review done but automated checks (4c) not started yet

Also update the paragraph:
> Do NOT return `DONE` just because you finished the staleness review. That's only Step 4b — there are still automated checks (4c), PEV-specific checks (4d), and final verification (Step 5) to complete.

to:
> Do NOT return `DONE` just because you finished the staleness review. That's only Step 4b — there are still automated checks (4c) and final verification (Step 5) to complete.

- [ ] **Step 6: Mirror to plugins/pev/**

Copy the modified `.claude/skills/pev-auditor/SKILL.md` to `plugins/pev/skills/pev-auditor/SKILL.md`.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/pev-auditor/SKILL.md plugins/pev/skills/pev-auditor/SKILL.md
git commit -m "refactor(auditor): remove PEV-specific checks from Auditor skill

Logging audit, test annotation audit, and workflow step markers are code
quality concerns that belong in the code Reviewer (pre-merge), not the
Auditor (post-merge). This slims the Auditor to doc writing + staleness
management."
```

---

### Task 2: Remove PEV-specific checks from Auditor reference protocol

**Files:**
- Modify: `.claude/templates/auditor-reference-protocol.md`
- Modify: `plugins/pev/templates/auditor-reference-protocol.md`

- [ ] **Step 1: Remove the PEV-Specific Checks section**

Delete the entire `## PEV-Specific Checks` section (lines 206-235) containing checks 6 (logging audit), 7 (test annotation audit), and 8 (workflow step markers).

- [ ] **Step 2: Update the Quick Reference Checklist**

Remove the `### PEV-Specific Checks` block from the checklist (lines 283-286):
```
### PEV-Specific Checks
- [ ] Logging audit (ADR-014) — modified code has appropriate logging
- [ ] Test annotation audit — correct tiers, within budget
- [ ] Workflow step markers — accurate on changed multi-step functions
```

- [ ] **Step 3: Update the Resolution & Checkpoint triage order**

Remove item 6 from the triage order list:
```
6. **Logging / test / workflow gaps** → add to `needs_fix` for user review
```

Renumber the remaining items (section length / fan-out becomes item 6).

- [ ] **Step 4: Update the Purpose section**

Change:
> Combines post-implementation documentation updates with audit checks and PEV-specific checks (logging, test annotation, workflow markers).

to:
> Combines post-implementation documentation updates with automated audit checks.

- [ ] **Step 5: Mirror to plugins/pev/**

Copy the modified `.claude/templates/auditor-reference-protocol.md` to `plugins/pev/templates/auditor-reference-protocol.md`.

- [ ] **Step 6: Commit**

```bash
git add .claude/templates/auditor-reference-protocol.md plugins/pev/templates/auditor-reference-protocol.md
git commit -m "refactor(auditor): remove PEV-specific checks from reference protocol

Mirrors the Auditor skill change — PEV-specific checks (logging, test
annotations, workflow markers) move to the code Reviewer."
```

---

### Task 3: Slim Auditor agent definition

**Files:**
- Modify: `.claude/agents/pev-auditor.md`
- Modify: `plugins/pev/agents/pev-auditor.md`

- [ ] **Step 1: Remove workflow and report tools**

In `.claude/agents/pev-auditor.md`, remove these tools from the `tools:` list (they were only used by PEV-specific checks):

```yaml
  - mcp__cortex__cortex_workflow_list
  - mcp__cortex__cortex_workflow_detail
```

Keep all other tools — the Auditor still needs `cortex_report` (for re-checking AGENT_VERIFIED events in staleness review), read-only cortex tools for doc review, doc-write tools for updates, and `cortex_mark_clean` for marking nodes.

- [ ] **Step 2: Adjust tool budget thresholds**

The Auditor now does fewer checks (no PEV-specific passes). Reduce the tool budget to reflect this:

Change the tool gate line:
```yaml
command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-gate.sh 65 cortex_update_section,cortex_write_doc,cortex_add_section,cortex_delete_link,cortex_update_doc_meta,cortex_mark_clean,cortex_purge_node,cortex_build,cortex_check"
```
to:
```yaml
command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-gate.sh 55 cortex_update_section,cortex_write_doc,cortex_add_section,cortex_delete_link,cortex_update_doc_meta,cortex_mark_clean,cortex_purge_node,cortex_build,cortex_check"
```

Change the counter thresholds:
```yaml
command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-counter.sh 40 55 65"
```
to:
```yaml
command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-counter.sh 30 45 55"
```

Also reduce `maxTurns` from 100 to 80 — the slimmed scope needs less runway.

- [ ] **Step 3: Mirror to plugins/pev/**

Copy the modified `.claude/agents/pev-auditor.md` to `plugins/pev/agents/pev-auditor.md`.

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/pev-auditor.md plugins/pev/agents/pev-auditor.md
git commit -m "refactor(auditor): remove workflow/report tools, reduce budget

Auditor no longer runs PEV-specific checks (logging, test annotations,
workflow markers), so it doesn't need workflow_list, workflow_detail, or
report tools. Budget reduced to match slimmer scope."
```

---

### Task 4: Add PEV-specific checks to Reviewer skill (Pass 4)

**Files:**
- Modify: `.claude/skills/pev-reviewer/SKILL.md`
- Modify: `plugins/pev/skills/pev-reviewer/SKILL.md`

- [ ] **Step 1: Add Pass 4 section to the Three-Pass Review**

After the existing `### Pass 3: Code Quality` section, add a new pass. Insert before the `## Persisting Progress` section:

```markdown
### Pass 4: PEV-Specific Checks

These are judgment calls, not mechanical greps. Review the Builder's code for adherence to project standards.

#### 4a. Logging audit (ADR-014)

For each modified code node, read the source and judge whether it needs logging per ADR-014 patterns:
- **Tool entry/exit timing** — MCP tool functions should log start/end with elapsed time
- **Phase milestones** — Multi-step operations should emit progress at phase boundaries
- **Exception handler visibility** — No bare `except: pass`; handlers should `logger.warning`
- **Subprocess timeouts** — New subprocess calls should have timeout parameters

For code that already had logging, check if the logging was updated to reflect the changes.

#### 4b. Test annotation audit

**Tier verification:** Is each test at the right tier?
- Tier 1 (plain pytest) — internal logic, edge cases, helpers
- Tier 2 (`@workflow(purpose=...)`) — meaningful subsystem tests
- Tier 3 (`@workflow` + `Step()`) — E2E user-story-level scenarios

**Budget check:** 5-10 focused tests per subsystem change. Past 15, likely testing implementation details. Flag excessive counts and recommend consolidation.

**Gap detection:** For each changed code node, check `cortex_graph(direction="in")` for `validates` edges. Missing coverage goes in `quality_issues` with severity `important`.

#### 4c. Workflow step markers

Run `cortex_workflow_list` to find all `@workflow` and `@task` functions. For key multi-step functions (CLI commands, MCP tools, API endpoints with >3 logical steps):
- Render at level 3: `cortex_render(node_id, level=3)` to see existing markers
- Compare step sequence against current code via `cortex_source`
- Flag: missing steps, out-of-order steps, ghost steps (describe removed behavior), wrong marker types, minor steps outside loops
```

- [ ] **Step 2: Update the Three-Pass Review header**

The section is called "Three-Pass Review" — rename it to:

```markdown
## Four-Pass Review
```

- [ ] **Step 3: Update the Persisting Progress section**

Update the example progress text to include Pass 4:

```
cortex_update_section(
  section_id="{cycle_doc_id}::reviewer.progress",
  content="Pass 1 (Spec Compliance): COMPLETE\n- US-1: PASS — ...\n\nPass 2 (Functionality): COMPLETE\n- ...\n\nPass 3 (Code Quality): COMPLETE\n- ...\n\nPass 4 (PEV Checks): NOT STARTED"
)
```

- [ ] **Step 4: Update the return format — complete verdict**

Add a `pev_checks` field to the JSON verdict structure. Insert after `quality_issues`:

```json
"pev_checks": [
    {
      "check": "logging|test_annotations|workflow_markers",
      "node_id": "cortex::module.function",
      "severity": "critical|important|minor",
      "description": "What needs attention"
    }
]
```

- [ ] **Step 5: Update the return format — partial verdict**

Add `"pev_checks"` to `passes_completed` / `passes_remaining` arrays in the CONTINUING example. Add a `pev_checks` field to the partial verdict JSON.

- [ ] **Step 6: Update budget management**

The Reviewer now does 4 passes instead of 3. Update the warning level text:
> Check your progress — are you on track to finish all four passes? If still in Pass 1, tighten scope rather than exploring every node.

Update the urgent level text:
> Finish your current pass if close. If not, write your progress to `reviewer.progress` via `cortex_update_section` so the next incarnation can skip completed passes. Do not start a new pass.

- [ ] **Step 7: Mirror to plugins/pev/**

Copy the modified `.claude/skills/pev-reviewer/SKILL.md` to `plugins/pev/skills/pev-reviewer/SKILL.md`.

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/pev-reviewer/SKILL.md plugins/pev/skills/pev-reviewer/SKILL.md
git commit -m "feat(reviewer): add Pass 4 — PEV-specific checks (logging, tests, markers)

Moves logging audit (ADR-014), test annotation audit, and workflow step
marker checks from the Auditor to the code Reviewer. These are code
quality concerns best caught pre-merge so the Builder can fix them in
the same cycle."
```

---

### Task 5: Expand Reviewer agent definition

**Files:**
- Modify: `.claude/agents/pev-reviewer.md`
- Modify: `plugins/pev/agents/pev-reviewer.md`

- [ ] **Step 1: Add tools for PEV-specific checks**

In `.claude/agents/pev-reviewer.md`, add these to the `# Read-only cortex tools` section:

```yaml
  - mcp__cortex__cortex_workflow_list
  - mcp__cortex__cortex_workflow_detail
```

These are needed for Pass 4:
- `cortex_workflow_list` — find `@workflow` and `@task` functions for workflow marker checks
- `cortex_workflow_detail` — inspect workflow step details

The Reviewer already has `cortex_render` (needed for workflow marker checks).

- [ ] **Step 2: Adjust tool budget thresholds**

The Reviewer now runs 4 passes. Increase the budget slightly:

Change the tool gate line:
```yaml
command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-gate.sh 55 cortex_update_section"
```
to:
```yaml
command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-gate.sh 65 cortex_update_section"
```

Change the counter thresholds:
```yaml
command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-counter.sh 30 45 55"
```
to:
```yaml
command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-counter.sh 35 55 65"
```

- [ ] **Step 3: Mirror to plugins/pev/**

Copy the modified `.claude/agents/pev-reviewer.md` to `plugins/pev/agents/pev-reviewer.md`.

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/pev-reviewer.md plugins/pev/agents/pev-reviewer.md
git commit -m "feat(reviewer): add workflow/report tools, increase budget for Pass 4

Reviewer needs cortex_workflow_list, cortex_workflow_detail, and
cortex_report to run PEV-specific checks. Budget increased to
accommodate the additional pass."
```

---

### Task 6: Create Doc Reviewer agent definition

**Files:**
- Create: `.claude/agents/pev-doc-reviewer.md`
- Create: `plugins/pev/agents/pev-doc-reviewer.md`

- [ ] **Step 1: Create the agent definition**

Create `.claude/agents/pev-doc-reviewer.md`:

```yaml
---
name: pev-doc-reviewer
description: PEV Doc Reviewer — reviews Auditor's doc changes against templates and implementation
model: inherit
maxTurns: 60
tools:
  # Read-only file tools
  - Read
  - Grep
  - Glob
  # Read-only cortex tools
  - mcp__cortex__cortex_search
  - mcp__cortex__cortex_source
  - mcp__cortex__cortex_read_doc
  - mcp__cortex__cortex_render
  - mcp__cortex__cortex_graph
  - mcp__cortex__cortex_list
  - mcp__cortex__cortex_diff
  - mcp__cortex__cortex_history
  - mcp__cortex__cortex_check
  - mcp__cortex__cortex_report
  # Doc-write cortex tools (scoped to cycle manifest by hook)
  - mcp__cortex__cortex_update_section
skills:
  - pev-doc-reviewer
hooks:
  PreToolUse:
    # Block all code-write and doc-write tools
    - matcher: "Edit|Write|Bash|NotebookEdit|mcp__cortex__cortex_write_doc|mcp__cortex__cortex_add_section|mcp__cortex__cortex_add_link|mcp__cortex__cortex_delete_link|mcp__cortex__cortex_mark_clean|mcp__cortex__cortex_build|mcp__cortex__cortex_delete_doc|mcp__cortex__cortex_delete_section|mcp__cortex__cortex_update_doc_meta|mcp__cortex__cortex_purge_node"
      hooks:
        - type: command
          command: "echo 'BLOCKED: Doc Reviewer cannot modify code or docs — review only' >&2; exit 2"
          timeout: 5
    # Doc-write: allow cortex_update_section but scope to cycle manifest only
    - matcher: "mcp__cortex__cortex_update_section"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-doc-scope.sh"
          timeout: 5
          statusMessage: "Checking doc scope..."
    # Tool budget gate
    - matcher: ""
      hooks:
        - type: command
          command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-gate.sh 45 cortex_update_section"
          timeout: 5
  PostToolUse:
    - matcher: ""
      hooks:
        - type: command
          command: "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/pev-tool-counter.sh 25 35 45"
          timeout: 5
---

You are the PEV Doc Reviewer agent. Your job is to review the Auditor's documentation changes against templates, the actual implementation, and the Architect's pitch.

You have NO access to code-write or doc-write tools (Edit, Write, Bash, cortex_write_doc, cortex_add_section, cortex_add_link, cortex_mark_clean). A PreToolUse hook will block any attempt. You cannot modify source code or documentation.

You CAN write review findings to the cycle manifest via `cortex_update_section` (scoped to the cycle manifest by the doc-scope hook).

Follow the pev-doc-reviewer skill instructions for your workflow. Return your review verdict when done.
```

- [ ] **Step 2: Copy to plugins/pev/**

Copy `.claude/agents/pev-doc-reviewer.md` to `plugins/pev/agents/pev-doc-reviewer.md`.

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/pev-doc-reviewer.md plugins/pev/agents/pev-doc-reviewer.md
git commit -m "feat(doc-reviewer): create Doc Reviewer agent definition

Read-only agent that reviews Auditor doc changes against templates and
implementation. Can only write review findings to the cycle manifest.
Mirrors the code Reviewer pattern — no agent judges its own work."
```

---

### Task 7: Create Doc Reviewer skill

**Files:**
- Create: `.claude/skills/pev-doc-reviewer/SKILL.md`
- Create: `plugins/pev/skills/pev-doc-reviewer/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `.claude/skills/pev-doc-reviewer/SKILL.md`:

```markdown
---
name: pev-doc-reviewer
description: Behavioral instructions for the PEV Doc Reviewer phase — reviews Auditor's doc changes against templates and implementation
---

# PEV Doc Reviewer

You review the Auditor's documentation changes against templates, the actual implementation, and the Architect's pitch. You cannot modify docs or code — you verify and report.

**You do NOT modify docs.** Your doc-write tools are structurally blocked except for `cortex_update_section` scoped to the cycle manifest. The Auditor writes docs; you verify them.
**You do NOT modify code.** Your code-write tools are structurally blocked.
**You do NOT commit.** The orchestrator handles all git operations.

## Input

The orchestrator passes:

1. **Cycle manifest doc ID** — contains the Architect's pitch, Builder's manifest, Auditor's change ledger and impact report
2. **Project root** — the main repo path (post-merge, same as the Auditor ran on)

## Workflow

### Step 1: Read the cycle manifest

```
cortex_read_doc(doc_id="{cycle_doc_id}")
```

Read the full manifest to understand:
- **Architect pitch** — user stories, solution sketch, constraints (the "what was requested")
- **Builder manifest** — what was implemented, files changed, tests added (the "what was built")
- **Auditor change ledger** — what docs were changed and why (the "what was documented")
- **Auditor impact report** — summary of audit findings

### Step 2: Review the Auditor's changes

For each entry in the Auditor's change ledger, run the appropriate check:

#### 2a. PRD Capabilities Table Accuracy

For each `prd_capability` entry in the change ledger:
1. Read the updated capabilities table: `cortex_read_doc(doc_id=..., section="current-capabilities")`
2. Cross-reference against the Builder's manifest — does each "Done" capability match something the Builder actually built?
3. Cross-reference against the Architect's user stories — are all user stories represented?
4. Check for missing capabilities — did the Builder build something not reflected in the table?
5. Check for premature "Done" — is there a capability marked Done that the Builder only partially implemented?

#### 2b. Interface Spec Completeness

For each `interface_spec` entry in the change ledger:
1. Read the updated interface spec: `cortex_read_doc(doc_id=...)`
2. Read the actual code via `cortex_source` for the functions/tables referenced
3. Verify completeness:
   - **data-model.json**: Every table and column the Builder added/modified is documented. Types are correct. No stale columns from removed code.
   - **cli.json**: Every command, flag, and option the Builder added/modified is documented. Help text matches.
   - **Other interface specs**: Parameters, return types, and examples match the implementation.
4. Check for omissions — did the Builder change an interface that the Auditor missed?

#### 2c. New Doc Template Compliance

For each `new_doc` entry in the change ledger:
1. Read the new doc: `cortex_read_doc(doc_id=...)`
2. Read the template it was based on (path is in `docs/templates/`)
3. Verify structure — does the new doc have all required sections from the template?
4. Verify content — are sections populated (not placeholder text)?
5. Verify placement — is the doc at the correct path in the feature hierarchy?

#### 2d. Design Spec Accuracy

For each `design_decision` entry in the change ledger:
1. Read the updated design spec section
2. Verify the decision matches the Builder's actual implementation (check via `cortex_source`)
3. Verify the decision aligns with the Architect's constraints

#### 2e. Link Quality

For each `link_maintenance` or `new_coverage` entry in the change ledger:
1. Use `cortex_graph(section_id=..., direction="out")` to see the links
2. Verify each link follows the linking policy:
   - Behavior docs → linked to public entry point (not private helpers)
   - Mechanism docs → linked to the specific function described
   - No test functions, fixtures, or external packages linked
   - No module-level composite nodes linked (should link children)
3. Check link targets still exist: `cortex_source(node_id=...)` — if the source call fails, the link is broken

#### 2f. Change Ledger Completeness

Cross-check the change ledger against what actually changed:
1. Run `cortex_diff(project_root=..., summary_only=True)` to see all doc node changes
2. Compare against the change ledger — every doc change should have a ledger entry
3. Flag undocumented changes (doc nodes that changed but have no ledger entry)

### Step 3: Persisting Progress

After completing each check category, write progress to the cycle manifest:

```
cortex_update_section(
  section_id="{cycle_doc_id}::doc-review.progress",
  content="PRD Accuracy: COMPLETE — 3 capabilities verified\nInterface Completeness: COMPLETE — data-model.json verified\nTemplate Compliance: NOT STARTED\nDesign Spec: NOT STARTED\nLink Quality: NOT STARTED\nLedger Completeness: NOT STARTED"
)
```

If this is a continuation, read existing progress first and skip completed checks.

### Step 4: Return the review verdict

**Return EXACTLY this format:**

```
DOC-REVIEWER {status}

{If issues found, explain here}

---DOC-REVIEW---
{
  "status": "PASS|FAIL|PASS_WITH_CONCERNS|CONTINUING",
  "prd_accuracy": [
    {
      "doc_id": "cortex::docs.features.{feature}.sub_features.{sub}.prd",
      "verdict": "PASS|FAIL",
      "note": "All 3 capabilities correctly marked Done"
    }
  ],
  "interface_completeness": [
    {
      "doc_id": "cortex::docs.features.{feature}.interfaces.data-model",
      "verdict": "PASS|FAIL",
      "note": null,
      "missing": ["new_column not documented"]
    }
  ],
  "template_compliance": [
    {
      "doc_id": "cortex::docs.features.{feature}.sub_features.{new-sub}.prd",
      "verdict": "PASS|FAIL",
      "note": "Missing user-stories section"
    }
  ],
  "design_accuracy": [
    {
      "doc_id": "cortex::docs.features.{feature}.design",
      "verdict": "PASS|FAIL",
      "note": null
    }
  ],
  "link_quality": {
    "links_checked": 5,
    "issues": []
  },
  "ledger_completeness": {
    "ledger_entries": 4,
    "undocumented_changes": 0,
    "issues": []
  },
  "summary": "All doc changes verified against implementation and templates."
}
```

### Status Codes

| Status | Meaning | When to use |
|---|---|---|
| `PASS` | All checks pass, Auditor's doc work is correct | Happy path |
| `FAIL` | Issues found that need Auditor correction | Missing capabilities, incorrect interface specs, broken template compliance |
| `PASS_WITH_CONCERNS` | Minor issues that don't block completion | Style issues, optional sections empty, non-critical link quality |
| `CONTINUING` | Review incomplete, need another incarnation | Tool budget running low or large review scope |

## Asking the User

If you encounter ambiguity that blocks your review, use the proxy-question protocol (same as other PEV agents):

```json
{"status": "NEEDS_INPUT", "preamble": "...", "questions": [...], "context": "..."}
```

## Constraints

- **Do NOT modify docs.** Only `cortex_update_section` to the cycle manifest is allowed.
- **Do NOT modify code.** No `Edit`, `Write`, or `Bash`.
- **Verify against implementation, not just the pitch.** The Auditor may have correctly documented something the Architect didn't anticipate. Check the code.
- **Missing is worse than imperfect.** A capabilities table that's 90% right is better than missing entirely. Reserve FAIL for substantive gaps (missing capabilities, wrong interface specs), not style issues.
- **Use `verified_by="agent:pev-doc-reviewer"` context** when writing progress to the manifest.

## Budget Management

Same two-mechanism budget as other PEV agents:

- **maxTurns** — hard cutoff, treated as CONTINUING automatically.
- **Tool budget hook** — warns as you approach the limit. At gate, only `cortex_update_section` works.

Returning `CONTINUING` is normal. Write your progress and return — the next incarnation skips completed checks.
```

- [ ] **Step 2: Copy to plugins/pev/**

Copy `.claude/skills/pev-doc-reviewer/SKILL.md` to `plugins/pev/skills/pev-doc-reviewer/SKILL.md`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/pev-doc-reviewer/SKILL.md plugins/pev/skills/pev-doc-reviewer/SKILL.md
git commit -m "feat(doc-reviewer): create Doc Reviewer skill with review workflow

Defines the Doc Reviewer's six-check review: PRD accuracy, interface
completeness, template compliance, design accuracy, link quality, and
change ledger completeness. Returns structured verdict for orchestrator."
```

---

### Task 8: Update orchestrator — add Doc Review phase

**Files:**
- Modify: `.claude/skills/pev-cycle/SKILL.md`
- Modify: `plugins/pev/skills/pev-cycle/SKILL.md`

- [ ] **Step 1: Add Phase 7.5 (Doc Review) to the orchestrator skill**

In `.claude/skills/pev-cycle/SKILL.md`, after the existing `### 7. Audit` section and before `### 8. Complete`, insert a new phase:

```markdown
### 7.5. Doc Review

After the Auditor completes (DONE or DONE_WITH_CONCERNS), review its documentation changes.

Update `.pev-state.json` counter_file for Doc Reviewer. Dispatch `pev-doc-reviewer` subagent pointing at the **main repo** (see ref: `dispatch-prompts`).

Parse return — extract review from `---DOC-REVIEW---` separator.

Handle status codes:
- **PASS**: Write review to `doc-review` section. Proceed to Phase 8.
- **PASS_WITH_CONCERNS**: Write review to `doc-review` section. Present concerns to user. Options: (1) proceed to complete, (2) redispatch Auditor to fix doc issues, then re-review.
- **FAIL**: Write review to `doc-review` section. Present failures to user. Redispatch Auditor with specific doc issues to fix (same main repo). After fix, re-dispatch Doc Reviewer. Max 2 review-fix loops before escalating to user.
- **CONTINUING** (or no separator): Write checkpoint. Increment incarnation, redispatch.
- **NEEDS_INPUT**: Relay questions to user via AskUserQuestion. Resume with SendMessage.

**Auditor fix dispatch (doc loopback):** When the Doc Reviewer returns FAIL, redispatch the Auditor with targeted fix instructions. The Auditor's CONTINUING mechanism handles partial work — already-marked-clean nodes are preserved, and the fresh Auditor reads the change ledger to know what's already done.
```

- [ ] **Step 2: Renumber Phase 8**

The existing Phase 8 (Complete) references remain the same. No renumbering needed — "Phase 7.5" sits between 7 and 8.

- [ ] **Step 3: Update Phase 7 (Audit) to reference Doc Review**

In the Phase 7 section, update the DONE handling to transition to Doc Review instead of directly to Complete:

Change:
> - **DONE**: Write Impact Report to `auditor.impact-report` section. The change ledger is already in `auditor.change-ledger` (written by Auditor as it works). Proceed to Phase 8.

to:
> - **DONE**: Write Impact Report to `auditor.impact-report` section. The change ledger is already in `auditor.change-ledger` (written by Auditor as it works). Proceed to Phase 7.5 (Doc Review).

Change:
> - **DONE_WITH_CONCERNS** (has `needs_fix`): Present the `needs_fix` items to the user as "these need attention." Options: (1) address them in a follow-up PEV cycle, (2) fix manually, (3) accept and proceed. Then proceed to Phase 8.

to:
> - **DONE_WITH_CONCERNS** (has `needs_fix`): Present the `needs_fix` items to the user as "these need attention." Options: (1) address them in a follow-up PEV cycle, (2) fix manually, (3) accept and proceed. Then proceed to Phase 7.5 (Doc Review).

- [ ] **Step 4: Update Phase 8 references**

In Phase 8, the Auditor state file cleanup still applies. Add a note that the Doc Reviewer's state is also cleaned up here (same `.pev-state.json` on main, last written for the Doc Reviewer).

- [ ] **Step 5: Mirror to plugins/pev/**

Copy `.claude/skills/pev-cycle/SKILL.md` to `plugins/pev/skills/pev-cycle/SKILL.md`.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/pev-cycle/SKILL.md plugins/pev/skills/pev-cycle/SKILL.md
git commit -m "feat(orchestrator): add Doc Review phase (7.5) between Audit and Complete

Establishes Auditor → Doc Reviewer → Complete flow with loopback
support. Doc Reviewer verifies Auditor's doc changes; failures
redispatch the Auditor for targeted fixes (max 2 loops)."
```

---

### Task 9: Update orchestrator reference — dispatch prompt and status

**Files:**
- Modify: `.claude/templates/pev-orchestrator-reference.md`
- Modify: `plugins/pev/templates/pev-orchestrator-reference.md`

- [ ] **Step 1: Add Doc Reviewer dispatch prompt**

In the `## Dispatch Prompts` section, after the Auditor (continuation) prompt, add:

```markdown
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
```

- [ ] **Step 2: Add Doc Reviewer to the dispatch note**

Update the "All dispatches use" note:

Change:
> **All dispatches use:** `subagent_type="pev-{agent}"`. Do NOT use `isolation: "worktree"` — the orchestrator owns the worktree lifecycle.

to:
> **All dispatches use:** `subagent_type="pev-{agent}"` (agents: `architect`, `builder`, `reviewer`, `auditor`, `doc-reviewer`). Do NOT use `isolation: "worktree"` — the orchestrator owns the worktree lifecycle.

- [ ] **Step 3: Add Auditor fix dispatch prompt (doc loopback)**

After the Doc Reviewer prompts, add:

```markdown
**Auditor (doc fix — doc review loopback):**
```
You are the PEV Auditor for cycle {cycle_id} (targeted doc fix — doc review iteration {N}).

Cycle manifest doc ID: {cycle_doc_id}
Project root: {main_repo_path}

This is a TARGETED DOC FIX dispatch from the Doc Reviewer. Fix ONLY the following documentation issues:
{doc review failures}

Your previous change ledger and marked-clean nodes are preserved. Focus on the specific doc issues identified.
```
```

- [ ] **Step 4: Update status transitions**

In the `## Status Updates` section, add the doc-review transition. After `Merge → Auditor`:

```markdown
**Auditor → Doc Review:**
Add: `- doc-review: {now-timestamp} — audit complete, reviewing docs`

**Doc Review → Completed:**
Add: `- completed: {now-timestamp} — doc review passed`
```

Update the existing `Auditor → Completed` transition to become `Doc Review → Completed`.

- [ ] **Step 5: Update manifest parsing section**

Add after the Auditor parsing:

```markdown
**Doc Reviewer returns:** Look for `---DOC-REVIEW---` separator. Everything after it is JSON review findings. Write to the `doc-review` section:
```
cortex_update_section(
  section_id="{cycle_doc_id}::doc-review",
  content="{formatted doc review findings}"
)
```
```

- [ ] **Step 6: Update state file section**

In the State File section, add `doc-reviewer` to the `{agent}` list:

Change:
> - `{agent}`: `architect`, `builder`, `reviewer`, or `auditor`

to:
> - `{agent}`: `architect`, `builder`, `reviewer`, `auditor`, or `doc-reviewer`

- [ ] **Step 7: Mirror to plugins/pev/**

Copy `.claude/templates/pev-orchestrator-reference.md` to `plugins/pev/templates/pev-orchestrator-reference.md`.

- [ ] **Step 8: Commit**

```bash
git add .claude/templates/pev-orchestrator-reference.md plugins/pev/templates/pev-orchestrator-reference.md
git commit -m "feat(orchestrator): add Doc Reviewer dispatch prompt and status transitions

Adds dispatch templates for Doc Reviewer (initial + re-review), Auditor
doc-fix loopback, and status transition entries for the new phase."
```

---

### Task 10: Update cycle manifest template

**Files:**
- Modify: `.claude/templates/cycle-manifest-template.json`
- Modify: `plugins/pev/templates/cycle-manifest-template.json`

- [ ] **Step 1: Add doc-review section to the manifest template**

In `.claude/templates/cycle-manifest-template.json`, add a new section after the `auditor` section (before the closing `]` of the `sections` array):

```json
,
{
  "id": "doc-review",
  "heading": "Doc Review",
  "content": "**Filled by:** Orchestrator — writes the Doc Reviewer's verdict after doc review.\n\nThe Doc Reviewer returns this as structured data in its subagent completion message. The orchestrator writes it here.\n\n**Example:**\n```json\n{\n  \"status\": \"PASS\",\n  \"prd_accuracy\": [{\"doc_id\": \"cortex::docs.features.history.sub_features.filtering.prd\", \"verdict\": \"PASS\", \"note\": \"All capabilities correctly marked Done\"}],\n  \"interface_completeness\": [{\"doc_id\": \"cortex::docs.features.history.interfaces.data-model\", \"verdict\": \"PASS\", \"note\": null, \"missing\": []}],\n  \"summary\": \"All doc changes verified against implementation and templates.\"\n}\n```\n\n**Instructions:** If the Doc Reviewer returns FAIL, the orchestrator redispatches the Auditor with targeted fix instructions. After the Auditor fixes, the Doc Reviewer is re-dispatched. Max 2 loops before escalating to user.\n\n### Continuation Checkpoint\n**Only present if the Doc Reviewer hit the context leash.** Written by the orchestrator from the Doc Reviewer's return."
}
```

- [ ] **Step 2: Add reviewer.progress sub-section to the review section if missing**

The existing `review` section doesn't have explicit sub-sections in the template — the Reviewer writes progress dynamically. Verify this is still fine (it is — `cortex_update_section` creates sub-sections on demand).

No change needed.

- [ ] **Step 3: Update Auditor section `needs_fix` categories**

The Auditor section's Instructions text lists `needs_fix` categories that include PEV-specific ones that now belong to the Reviewer. In the `auditor` section's `content`, change:

```
`needs_fix` categories: `code_bug`, `needs_new_tests`, `test_budget`, `logging`, `workflow_markers`.
```

to:

```
`needs_fix` categories: `code_bug`, `needs_new_tests`.
```

The `test_budget`, `logging`, and `workflow_markers` categories are now handled by the code Reviewer's Pass 4, not the Auditor.

- [ ] **Step 4: Mirror to plugins/pev/**

Copy `.claude/templates/cycle-manifest-template.json` to `plugins/pev/templates/cycle-manifest-template.json`.

- [ ] **Step 5: Commit**

```bash
git add .claude/templates/cycle-manifest-template.json plugins/pev/templates/cycle-manifest-template.json
git commit -m "feat(manifest): add doc-review section, update needs_fix categories

New section stores the Doc Reviewer's structured verdict, enabling
the orchestrator to track doc review status and support loopback."
```

---

### Task 11: Cross-check consistency

**Files:** All files modified in Tasks 1-10 (read-only verification)

This task verifies that all changes are internally consistent across files.

- [ ] **Step 1: Verify tool lists are consistent**

Check that:
- Tools removed from Auditor (`cortex_workflow_list`, `cortex_workflow_detail`) are added to Reviewer. Note: `cortex_report` stays on the Auditor (used in staleness review for AGENT_VERIFIED events) and is NOT added to the Reviewer.
- Doc Reviewer tools are a subset of read-only cortex tools + `cortex_update_section`
- No agent has both code-write tools (Edit, Write, Bash) and doc-write tools (cortex_write_doc, cortex_add_section, etc.) — the invariant

- [ ] **Step 2: Verify dispatch prompts reference correct agent types**

Check that:
- Doc Reviewer dispatch uses `subagent_type="pev-doc-reviewer"`
- Auditor doc-fix dispatch uses `subagent_type="pev-auditor"`
- All dispatch prompts reference `{main_repo_path}` (not worktree — both run on main)

- [ ] **Step 3: Verify manifest sections match what agents write**

Check that:
- Doc Reviewer writes to `doc-review` section (matches template)
- Doc Reviewer progress writes to `doc-review.progress` (consistent with `reviewer.progress` pattern)
- Auditor's change ledger format is unchanged (Doc Reviewer reads it)

- [ ] **Step 4: Verify status codes are handled**

Check that the orchestrator handles all status codes from:
- Auditor: DONE, DONE_WITH_CONCERNS, CONTINUING, NEEDS_INPUT (unchanged)
- Doc Reviewer: PASS, FAIL, PASS_WITH_CONCERNS, CONTINUING, NEEDS_INPUT (new)

- [ ] **Step 5: Verify plugin mirrors are identical**

For each modified/created file in `.claude/`, verify the `plugins/pev/` copy is byte-identical:
```bash
diff .claude/agents/pev-auditor.md plugins/pev/agents/pev-auditor.md
diff .claude/agents/pev-reviewer.md plugins/pev/agents/pev-reviewer.md
diff .claude/agents/pev-doc-reviewer.md plugins/pev/agents/pev-doc-reviewer.md
diff .claude/skills/pev-auditor/SKILL.md plugins/pev/skills/pev-auditor/SKILL.md
diff .claude/skills/pev-reviewer/SKILL.md plugins/pev/skills/pev-reviewer/SKILL.md
diff .claude/skills/pev-doc-reviewer/SKILL.md plugins/pev/skills/pev-doc-reviewer/SKILL.md
diff .claude/skills/pev-cycle/SKILL.md plugins/pev/skills/pev-cycle/SKILL.md
diff .claude/templates/auditor-reference-protocol.md plugins/pev/templates/auditor-reference-protocol.md
diff .claude/templates/pev-orchestrator-reference.md plugins/pev/templates/pev-orchestrator-reference.md
diff .claude/templates/cycle-manifest-template.json plugins/pev/templates/cycle-manifest-template.json
```

- [ ] **Step 6: Commit (if any fixes needed)**

If cross-checking reveals inconsistencies, fix them and commit:
```bash
git add -A
git commit -m "fix: resolve cross-file consistency issues from validate phase refactor"
```
