# Auditor Reference Protocol

## Purpose

Single reference for the PEV Auditor agent. Combines post-implementation documentation updates with automated audit checks. The Auditor skill points at this doc.

The Auditor IS the post-implementation protocol — there is no separate step. Follow sections in order: post-implementation updates first (fast, targeted), then audit checks (systematic), then checkpoint.

Two modes:
- **PEV cycle** — the Auditor reads the `change-set` section from the cycle manifest to categorize findings as `expected` (in the change-set) or `collateral` (from external merges or indirect effects).
- **Manual audit** — run independently via `cortex check`. No cycle manifest; all findings are treated equally.

## Feature Doc Hierarchy

The project uses a structured doc hierarchy under `docs/features/`. The Auditor must understand this structure to find and update the right docs.

### Directory structure

```
docs/features/{feature}/
    prd.json                    ← Feature PRD
    design.json                 ← Design spec
    user-guide.json             ← User guide (if applicable)
    interfaces/
        cli.json                ← CLI interface spec
        data-model.json         ← DB schema, tables, columns
        {other}.json            ← Other interface specs as needed
    sub_features/{sub-feature}/
        prd.json                ← Sub-feature PRD (lighter than feature PRD)
        design.json             ← Sub-feature design spec
        workflows/              ← Workflow diagrams (if applicable)
```

### Doc types and their key sections

**Feature PRD** (`prd.json`):
- `problem` — Problem statement
- `user-stories` — User stories (may have sub-sections per phase)
- `requirements` — V1 requirements
- `non-goals` — Scope shield
- `icebox` — Future ideas

**Sub-feature PRD** (`sub_features/{name}/prd.json`):
- `problem` — Problem statement
- `user-stories` — User stories (prefixed US-XX-##)
- `current-capabilities` — **Status table** of what's built (Done / In progress / Not started). This is the primary section the Auditor updates after a Builder implements new capabilities.
- `backlog` — Planned enhancements

**Design spec** (`design.json`):
- `architecture` — High-level system flow
- `sequence-diagram` — Mermaid diagrams
- `data-modeling` — Data model and schema
- `decision-log` — Implementation trade-offs
- `verification-plan` — Test strategy

**Interface specs** (`interfaces/*.json`):
- `data-model.json` — DB tables, columns, schemas. **Critical to update when the Builder adds/modifies schema.**
- `cli.json` — CLI commands, subcommands, flags, options
- Other interface specs — tool parameters, return types, examples

### Discovering feature docs

To find which feature docs to update, map the Builder's changed files to feature areas. Use the directory structure under `docs/features/` — each top-level directory corresponds to a feature area. Then search for existing docs:

```
cortex_list(location="docs/features/")
cortex_search(query="features {feature-area}", node_type="doc")
```

Walk the feature directory to find PRDs, design specs, and interface specs for the affected area. If a sub-feature directory exists under the feature, check its PRD's capabilities table.

## Post-Implementation Updates

After `cortex_build` on merged main, perform these updates before the audit checks. Use `cortex_update_section` to patch sections directly.

### 1. Sub-feature PRD capabilities table
**Section:** `current-capabilities` in the relevant sub-feature PRD.
**Action:** Read the current capabilities table. Cross-reference against the Builder's `change-set` and the Architect's user stories (the outcomes that define "done"). For each capability that the Builder implemented:
- If the capability row exists with status "Not started" or "In progress", update to "Done"
- If the capability is new (not in the table), add a new row
- If the capability was partially implemented, update to "In progress" with a note

**Tool:** `cortex_update_section(section_id=..., content=<updated table>)`

**Also check the backlog section** — if a backlog item was implemented by the Builder, remove it from the backlog and ensure it appears in `current-capabilities` as Done.

### 2. Interface specs (if applicable)
**Action:** Read the relevant interface spec. Add new commands, flags, parameters, DB tables/columns, or API endpoints that the Builder added. Remove deprecated ones. Update examples if behavior changed.

**Critical triggers:**
- Builder added/modified DB tables or columns → update `data-model.json`
- Builder added/modified CLI commands or flags → update `cli.json`
- Builder added/modified MCP tool parameters → update the tool's interface spec
- Builder added/modified graph node or edge types → update `ontology.json`

### 3. Design spec (if architecture changed)
**Action:** Update architecture, sequence diagrams, data model, or decision log if the implementation changed the system structure. Add a decision log entry if the Builder made a significant trade-off.

### 4. Doc-to-code links
**Tool:** `cortex_add_link(section_id=..., node_id=...)`
**Decision test:** If a developer rewrites the linked function, would this section need review? If yes, link it.
**What to link:** Public entry points named in the prose, functions whose contract is explicitly documented.
**What NOT to link:** Private helpers (unless the section documents their internals), modules mentioned for orientation, test functions.

See the Linking Policy section below for detailed rules.

### 5. Create missing docs

If the Builder's work created a new subsystem, feature area, or significant capability that has no corresponding documentation, create docs from templates rather than leaving gaps.

**Templates** are at `docs/templates/`:

| Gap | Template path |
|---|---|
| Sub-feature needs PRD | `docs/templates/sub_feature_template/sub_feature_prd_template.json` |
| Sub-feature needs design spec | `docs/templates/feature_template/design_spec_template.json` |
| New feature needs PRD | `docs/templates/feature_template/product_review_document_template.json` |
| New feature needs design spec | `docs/templates/feature_template/design_spec_template.json` |

**How to create:** Read the template, populate sections from the Architect's pitch (problem statement, user stories) and the Builder's manifest (what was built → capabilities table). Write with `cortex_write_doc` to the appropriate path in the feature hierarchy. Record in the change ledger with category `new_doc`.

**Placement:** If the changed code lives under a module that already has a feature doc, the new doc is a sub-feature under that feature. If the code is an entirely new top-level module, create a new feature directory. Use NEEDS_INPUT only for genuine ambiguity.

**When to create:**
- Builder implemented a new subsystem with 3+ public functions and no existing sub-feature PRD → create one
- Builder added a new interface type (new CLI subcommand group, new MCP tool category) with no interface spec → create one
- Builder's work is substantial enough to warrant its own design spec (new architecture, new data model) and none exists → create one

**When NOT to create:** Small additions to existing subsystems that are already documented. A single new helper function doesn't need its own sub-feature PRD.

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
- **CODE NEEDS FIX** → add to `needs_fix` in Impact Report for user review, do NOT mark clean

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

## Resolution & Checkpoint

### Triage order
Process findings in this order (highest impact first):

1. **CODE NEEDS FIX** items → add to `needs_fix` in Impact Report for user review
2. **MISSING DOCS** → create from templates via `cortex_write_doc` + record in change ledger with category `new_doc`
3. **DOC NEEDS UPDATE** → fix via `cortex_update_section` + `mark_clean`
4. **Unlinked public nodes** → `cortex_add_link` to existing doc sections
5. **Orphan links** → remove dead links
6. **Section length / fan-out** → refactor docs for maintainability

### After all findings resolved
1. `cortex_build` — re-index
2. `cortex_check` — verify clean state on resolved nodes
3. `cortex history checkpoint --message "pev-cycle-{cycle-id}-audit-complete"` — mark the audit as a reference point

## Quick Reference Checklist

```
## PEV Audit: {cycle-id}

### Post-Implementation
- [ ] Sub-feature PRD: capabilities table updated to Done
- [ ] Interface spec: added/removed commands, flags, options (if applicable)
- [ ] Design spec: updated architecture/decisions (if changed)
- [ ] Missing docs: created from templates for new subsystems/features
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

### Completion
- [ ] cortex_build + cortex_check — clean after fixes
- [ ] cortex history checkpoint — audit reference point recorded
- [ ] Impact Report written to cycle manifest auditor section
```
