# Auditor Reference Protocol

## Purpose

Single reference for the PEV Auditor agent. Combines post-implementation documentation updates with audit checks and PEV-specific checks (logging, test annotation, workflow markers). The Auditor skill points at this doc.

The Auditor IS the post-implementation protocol — there is no separate step. Follow sections in order: post-implementation updates first (fast, targeted), then audit checks (systematic), then PEV-specific checks (judgment calls), then checkpoint.

Two modes:
- **PEV cycle** — the Auditor reads the `change-set` section from the cycle manifest to categorize findings as `expected` (in the change-set) or `collateral` (from external merges or indirect effects).
- **Manual audit** — run independently via `cortex check`. No cycle manifest; all findings are treated equally.

## Post-Implementation Updates

After `cortex_build` on merged main, perform these updates before the audit checks. Use `cortex_update_section` to patch sections directly.

### 1. Sub-feature PRD capabilities table
**Section:** `current-capabilities` in the relevant sub-feature PRD.
**Action:** Update status based on the Builder's `change-set` section in the cycle manifest and the Architect's user stories (the outcomes that define "done"). Match completed outcomes to PRD capabilities.
**Tool:** `cortex_update_section(section_id=..., content=<updated table>)`

### 2. Interface specs (if applicable)
**Action:** Add new commands, flags, or API endpoints. Remove deprecated ones. This is the canonical reference for CLI/API shapes.

### 3. Design spec (if architecture changed)
**Action:** Update architecture, sequence diagrams, or decision log if the implementation changed the system structure.

### 4. Doc-to-code links
**Tool:** `cortex_add_link(section_id=..., node_id=...)`
**Decision test:** If a developer rewrites the linked function, would this section need review? If yes, link it.
**What to link:** Public entry points named in the prose, functions whose contract is explicitly documented.
**What NOT to link:** Private helpers (unless the section documents their internals), modules mentioned for orientation, test functions.

See the Linking Policy section below for detailed rules.

## Staleness & Clean Review

**Only the Auditor marks nodes clean.** `cortex_mark_clean` is exclusively an Auditor tool. Every `mark_clean` call is a deliberate judgment — the Auditor read the diff, checked the code, and decided the change is correct.

**Scope determination:** The Auditor determines review scope empirically:

1. **`cortex_check`** — the primary signal. Every stale node after `cortex_build` is in scope for review.
2. **Builder's `change-set`** — what the Builder actually changed. Used to categorize findings as `expected` (in change-set) or `collateral` (not in change-set, from external merges or indirect effects).
3. **Architect's coarse scope boundary** — which modules/subsystems were in scope. Sanity check only — flag if the Builder touched something wildly outside scope.

The Auditor does NOT use the Architect's pitch to enumerate individual nodes for review. The staleness engine answers "what changed and needs review" mechanically.

After `cortex_build` + `cortex_check`, review every stale node:

- **AGREE** (node is fine) → `mark_clean` with reason → remove tag. Scope: `expected` if in change-set, `collateral` if not.
- **DOC NEEDS UPDATE** → `cortex_update_section` → `mark_clean` → remove tag
- **CODE NEEDS FIX** → add to `needs_fix` in Impact Report, do NOT mark clean

Also re-check any `AGENT_VERIFIED` events via `cortex_report` — verify the agent's judgment was correct.

**Key principle:** Stale ≠ broken. Most stale nodes after a Builder run are fine — changed intentionally. Read the diff, make a judgment, mark clean. Only flag things that are actually wrong.

## Automated Audit Checks

Run these in order after the staleness review. Each check produces findings to triage.

### 1. Unlinked public nodes
**Tool:** `cortex_list_undocumented`
**Filter out:** `_`-prefixed (unless core internal with own doc section), `test_`-prefixed, fixtures/helpers in test files, external package nodes, entity nodes.
**Resolution:** For each unlinked public node, find or create the doc section that describes its contract, then `cortex_add_link`.

### 2. Section length
**Threshold:** Flag sections over ~1500 characters.
**Why:** Long sections cover multiple concerns, harder to keep accurate and harder to update surgically.
**Resolution:** Split into focused subsections, each covering one concept or one function's contract.

### 3. Orphan links
**Tool:** `cortex_graph(section_id, direction="out")` for each doc section with links.
**Flags:** Links pointing to node IDs that no longer exist (graph rot from renames/deletions).
**Resolution:** Remove dead link. If function renamed, relink to new ID. If deleted, remove link and update prose.

### 4. Composite coverage
**Tool:** `cortex_list(parent_id=module_id)` to get children, check which have `documents` edges.
**Threshold:** Flag modules where <50% of public children have `documents` edges.
**Resolution:** Prioritize linking the most important public functions.

### 5. Link fan-out
**Threshold:** Flag doc sections with >8 outbound `documents` edges.
**Resolution:** Split the section, or remove links to functions mentioned only for orientation.

## Linking Policy

### Link the contract boundary, not the implementation

The key question: **is the doc section describing what the system does, or how a specific function works?**

- **Behavior docs** (what happens during a build, how purging works) → link the **public entry point** that triggers the behavior. If the private helper gets renamed, the link survives.
- **Mechanism docs** (how `_derive_change_type` decides, how `_extract_sections` parses) → link the **private function directly**. The doc IS about that function's internals.

### What to link
- Public entry points named in the prose (CLI commands, MCP tools, API endpoints)
- Functions whose contract (inputs, outputs, behavior) is explicitly documented
- Private functions when the section describes their internal logic specifically

### What NOT to link
- Functions mentioned only for orientation ("this lives in db.py")
- Test functions, fixtures, and test helpers
- External package nodes
- Entity nodes
- Module-level composite nodes — link the children, not the container

### Audit check for existing links
- For each link to a `_`-prefixed function: verify the doc section is about that function's internals. If it describes broader behavior, relink to the public caller.
- For each link to a composite (module) node: verify the section is about the module's structure. If about a child, relink to the child.

## PEV-Specific Checks

These checks are judgment calls, not mechanical greps. The Auditor reviews code and flags gaps.

### 6. Logging audit (ADR-014)
For each modified code node, read the source and judge whether it needs logging per ADR-014 patterns:
- **Tool entry/exit timing** — MCP tool functions should log start/end with elapsed time
- **Phase milestones** — Multi-step operations should emit progress at phase boundaries
- **Exception handler visibility** — No bare `except: pass`; handlers should `logger.warning`
- **Subprocess timeouts** — New subprocess calls should have timeout parameters

For code that already had logging, check if the logging was updated to reflect the changes. Findings use Impact Report category `logging`.

### 7. Test annotation audit
**Tier verification:** Is each test at the right tier?
- Tier 1 (plain pytest) — internal logic, edge cases, helpers
- Tier 2 (`@workflow(purpose=...)`) — meaningful subsystem tests
- Tier 3 (`@workflow` + `Step()`) — E2E user-story-level scenarios

**Budget check:** 5-10 focused tests per subsystem change. Past 15, likely testing implementation details. Flag excessive counts and recommend consolidation.

**Gap detection:** For each changed code node, check `cortex_graph(direction="in")` for `validates` edges. Missing coverage goes in `needs_fix` with category `needs_new_tests`.

Findings use category `test_budget`.

### 8. Workflow step markers
Run `cortex_workflow_list` to find all `@workflow` and `@task` functions. For key multi-step functions (CLI commands, MCP tools, API endpoints with >3 logical steps):
- Render at level 3: `cortex_render(node_id, level=3)` to see existing markers
- Compare step sequence against current code via `cortex_source`
- Flag: missing steps, out-of-order steps, ghost steps (describe removed behavior), wrong marker types, minor steps outside loops

Findings use category `workflow_markers`.

## Resolution & Checkpoint

### Triage order
Process findings in this order (highest impact first):

1. **CODE NEEDS FIX** items → add to `needs_fix` in Impact Report for Builder loopback
2. **DOC NEEDS UPDATE** → fix via `cortex_update_section` + `mark_clean`
3. **Unlinked public nodes** → `cortex_add_link` to existing doc sections
4. **Orphan links** → remove dead links
5. **Logging / test / workflow gaps** → add to `needs_fix` for Builder loopback
6. **Section length / fan-out** → refactor docs for maintainability

### After all findings resolved
1. `cortex_build` — re-index
2. `cortex_check` — verify clean state on resolved nodes
3. `cortex history checkpoint --message "pev-cycle-{cycle-id}-audit-complete"` — mark the audit as a reference point

### Builder loopback
If `needs_fix` has actionable items, the orchestrator dispatches a targeted Builder (in the same worktree, max 2 iterations). After the Builder returns, the Auditor re-runs from the staleness review step. After 2 loopback iterations, remaining issues are surfaced to the user.

## Quick Reference Checklist

```
## PEV Audit: {cycle-id}

### Post-Implementation
- [ ] Sub-feature PRD: capabilities table updated to Done
- [ ] Interface spec: added/removed commands, flags, options (if applicable)
- [ ] Design spec: updated architecture/decisions (if changed)
- [ ] Doc-to-code links added (per linking policy)

### Staleness Review
- [ ] cortex_build + cortex_check — all stale nodes identified
- [ ] Each stale node: reviewed, marked clean or flagged
- [ ] AGENT_VERIFIED events re-checked
- [ ] Scope categorization: expected vs collateral for each finding

### Automated Checks
- [ ] cortex_list_undocumented — no unlinked public nodes
- [ ] Section length — no sections >1500 chars
- [ ] Orphan links — no links to nonexistent nodes
- [ ] Composite coverage — >50% public children linked
- [ ] Link fan-out — no sections with >8 outbound links

### PEV-Specific Checks
- [ ] Logging audit (ADR-014) — modified code has appropriate logging
- [ ] Test annotation audit — correct tiers, within budget
- [ ] Workflow step markers — accurate on changed multi-step functions

### Completion
- [ ] cortex_build + cortex_check — clean after fixes
- [ ] cortex history checkpoint — audit reference point recorded
- [ ] Impact Report written to cycle manifest auditor section
```
