# PEV Reviewer Hardening + Architect Source Doc Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the PEV Reviewer to catch two failure modes: (1) Builder deviating from the Architect's pitch without detection, and (2) the pitch itself contradicting its source documents (ADRs, PRDs). Additionally, formalize the Architect's relationship with source documents — the Architect reads DocJSON source docs via cortex tools and proposes edits through the orchestrator for user approval before writing the pitch.

**Architecture:** Add a `source-documents` section to the Architect's pitch so the Reviewer can cross-check upstream constraints. Add a `doc_edits` field to the Architect's NEEDS_INPUT protocol so it can propose source doc revisions during brainstorming. The orchestrator presents proposed edits to the user, applies approved ones, and resumes the Architect. Restructure the Reviewer's passes: run tests first (Pass 0), cross-check source docs (Pass 1), reverse-map every code change to a user story (Pass 2), then existing functionality/quality/PEV passes (3-5). Add adversarial framing throughout and a structured deviation tribunal replacing the current soft "do deviations make sense?" check.

**Tech Stack:** Markdown skill files, JSON manifest template, shell dispatch prompts. No code changes.

---

## File Map

- Modify: `.claude/templates/cycle-manifest-template.json` — add `source-documents` sub-section under `architect`
- Modify: `.claude/skills/pev-architect/SKILL.md` — add source-documents writing step, source doc edit engagement pattern, doc_edits in NEEDS_INPUT protocol
- Modify: `.claude/agents/pev-reviewer.md` — adversarial framing in preamble
- Modify: `.claude/skills/pev-reviewer/SKILL.md` — main skill rewrite (context gathering, 6 passes, return format)
- Modify: `.claude/templates/pev-orchestrator-reference.md` — update Reviewer dispatch prompt, add doc_edits handling to Architect NEEDS_INPUT
- Modify: `.claude/skills/pev-cycle/SKILL.md` — update Phase 2 (Plan) to handle doc_edits, update Phase 5 (Review) for six-pass structure

---

### Task 1: Add source-documents section to cycle manifest template

**Files:**
- Modify: `.claude/templates/cycle-manifest-template.json` — add sub-section inside `architect.sections` array

The Architect needs a structured place to list which ADRs, PRDs, and design docs informed its pitch. Currently these are scattered across the narrative. The Reviewer needs a reliable list to cross-check.

- [ ] **Step 1: Read the current manifest template**

Read `.claude/templates/cycle-manifest-template.json` to understand the existing `architect.sections` array structure.

- [ ] **Step 2: Add source-documents sub-section**

In the `architect.sections` array, add a new entry **after `changelog-draft`** (last position, before the closing `]`):

```json
{
  "id": "source-documents",
  "heading": "Source Documents",
  "content": "(Architect replaces this with referenced ADRs, PRDs, design specs, and prior cycle docs that informed this pitch)"
}
```

- [ ] **Step 3: Update the architect parent section instructions**

In the `architect` section's `content` field, add `Source Documents` to the list of sub-sections. After the `### Changelog Draft` paragraph, add:

```
### Source Documents
List every ADR, PRD, design spec, prior cycle doc, or issue that informed this pitch. For each, include: (1) the cortex doc ID or file path, (2) a one-line summary of what constraint or requirement it contributes. The Reviewer uses this list to cross-check the pitch against upstream intent. If no source documents exist (greenfield work), state "None — greenfield."
```

- [ ] **Step 4: Verify the JSON is valid**

Run:
```bash
python -c "import json; json.load(open('.claude/templates/cycle-manifest-template.json'))"
```
Expected: No output (valid JSON).

- [ ] **Step 5: Commit**

```bash
git add .claude/templates/cycle-manifest-template.json
git commit -m "feat(pev): add source-documents section to cycle manifest template"
```

---

### Task 2: Update Architect skill to write source documents

**Files:**
- Modify: `.claude/skills/pev-architect/SKILL.md:~175-220` — Step 5 section table

The Architect needs instructions to identify and record source documents during exploration, and write them as a structured section.

- [ ] **Step 1: Read the Architect skill Step 2 and Step 5**

Read `.claude/skills/pev-architect/SKILL.md` to locate the exact text of Step 2 (Explore the codebase) and Step 5 (Write remaining architect sub-sections).

- [ ] **Step 2: Add source document discovery to Step 2**

In Step 2 (Explore the codebase), after the existing bullet list of cortex tools (`cortex_search`, `cortex_source`, etc.), add a new paragraph:

```markdown
**Identify source documents.** As you explore, note every ADR, PRD, design spec, or prior cycle doc that contains constraints or requirements relevant to this pitch. You will record these in `architect.source-documents` — the Reviewer uses this list to verify the pitch doesn't contradict upstream intent. Pay special attention to ADRs that specify HOW something should be implemented (e.g., "use Python API, not CLI wrappers") — these are the constraints most likely to be misinterpreted.
```

- [ ] **Step 3: Add source-documents to the Step 5 section table**

In the Step 5 table, add a new row after `architect.changelog-draft`:

| Section ID | What to write |
|---|---|
| `architect.source-documents` | Every ADR, PRD, design spec, prior cycle doc, or issue that informed this pitch. For each document, include: (1) the cortex doc ID or file path, (2) a one-line summary of the constraint or requirement it contributes to this pitch. Format as a numbered list. If greenfield (no source documents), write "None — greenfield." Example: `1. **cortex::docs.adrs.adr-007** — DVC integration must use Python API, no CLI wrappers or .dvc pointer files. 2. **cortex::docs.features.cache.prd** — Cache layer PRD defining storage requirements.` |

- [ ] **Step 4: Add the cortex_update_section call example**

After the table, where the existing `cortex_update_section` call example is shown, the pattern is already clear. No additional example needed — the existing pattern (`cortex_update_section(section_id="{cycle_doc_id}::architect.source-documents", content="...")`) follows naturally.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/pev-architect/SKILL.md
git commit -m "feat(pev): add source-documents discovery and writing to Architect skill"
```

---

### Task 3: Rewrite Reviewer agent definition with adversarial framing

**Files:**
- Modify: `.claude/agents/pev-reviewer.md:70-81` — the prose section after the YAML frontmatter

The current preamble is neutral: "Your job is to review the Builder's code changes." This lets the Reviewer approach the review as a confirmation exercise. Replace it with adversarial framing.

- [ ] **Step 1: Read the current agent definition**

Read `.claude/agents/pev-reviewer.md`.

- [ ] **Step 2: Replace the preamble prose**

Replace the entire prose section (lines 70-81, everything after the `---` closing the frontmatter) with:

```markdown
You are the PEV Reviewer agent. Your job is to find problems — not to confirm the Builder's work is correct.

**Default stance: skeptical.** Assume the Builder cut corners, drifted from the pitch, or missed edge cases until the evidence proves otherwise. A clean review is earned by evidence, not assumed by default. The Builder's self-reported progress and decisions are claims to verify, not facts to accept.

**Two failure modes you prevent:**
1. **Builder drift** — the Builder deviated from the Architect's pitch (approach, scope, constraints) without justification. Check every change against the pitch.
2. **Pitch contradiction** — the Architect's pitch contradicts its own source documents (ADRs, PRDs, design specs). Cross-check the pitch against referenced source docs before evaluating the Builder's work.

You have NO access to code-write tools (Edit, Write). A PreToolUse hook will block any attempt. You cannot modify source code.

You CAN use `cortex_update_section` to write review progress to the cycle manifest (scoped by the doc-scope hook). Use this to persist pass results after each completed pass — this survives across incarnations.

You CAN use Bash for read-only commands: `git diff`, `git log`, `poetry run pytest`, etc. Do NOT use Bash to modify files.

**Git commands:** Your cwd is already the worktree — run `git` commands directly. If you ever need to target a different directory, use `git -C /path/to/dir <command>` instead of `cd /path && git <command>`. The `-C` flag avoids compound shell commands that require extra permission.

Follow the pev-reviewer skill instructions for your workflow. Return your review verdict when done.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/pev-reviewer.md
git commit -m "feat(pev): add adversarial framing to Reviewer agent definition"
```

---

### Task 4: Rewrite Reviewer skill — Context Gathering (pitch-first ordering)

**Files:**
- Modify: `.claude/skills/pev-reviewer/SKILL.md:32-48` — the "Gathering Context" section

The current ordering reads the Builder's plan/progress/decisions before the Architect's pitch, which anchors the Reviewer in the Builder's framing. Reverse this: read the pitch first, form expectations, THEN read the Builder's narrative.

- [ ] **Step 1: Read the current Gathering Context section**

Read `.claude/skills/pev-reviewer/SKILL.md` lines 32-48.

- [ ] **Step 2: Replace the Gathering Context section**

Replace the entire "## Gathering Context" section with:

```markdown
## Gathering Context

Before starting the review passes, orient yourself. **Read the Architect's pitch before the Builder's notes.** This prevents the Builder's framing from anchoring your expectations.

### Phase A: Form expectations from the pitch (read FIRST)

1. **Read the Architect's pitch** — problem, user stories, solution sketch, constraints:
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="architect.problem")`
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="architect.user-stories")`
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="architect.solution-sketch")`
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="architect.constraints")`
2. **Read required artifacts** — what the Architect declared as concrete deliverables:
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="architect.required-artifacts")`
3. **Read source documents** — which ADRs, PRDs, and design specs informed the pitch:
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="architect.source-documents")`
4. **Form expectations** — before reading anything from the Builder, note:
   - What user stories must be satisfied
   - What approach the solution sketch describes
   - What constraints must not be violated
   - What source document requirements the pitch claims to implement

### Phase B: Read the Builder's claims (read SECOND)

5. **Read the Builder's plan and progress** — what the Builder intended and claims is done:
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="builder.build-plan")`
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="builder.progress")`
   - `cortex_read_doc(doc_id="{cycle_doc_id}", section="decisions")`
6. **Note any tensions** — where the Builder's plan/decisions diverge from your expectations formed in Phase A. These become investigation targets.

### Phase C: Map the impact area

7. **`cortex_check`** on the worktree — get the stale-node overview. This tells you which nodes changed and why.
8. **Plan your passes** — use the check output to identify:
   - Nodes the pitch says should change -> verify against user stories
   - Stale nodes NOT mentioned in the pitch -> potential scope creep or drift
   - Callers/dependents to verify -> candidates for `cortex_diff`
```

- [ ] **Step 3: Update the intro text**

Also update the intro paragraph at the top of the skill (line 7-8) from:

```
You review the Builder's code changes against the Architect's pitch.
```

to:

```
You review the Builder's code changes against the Architect's pitch AND the pitch's source documents. Your default stance is skeptical — assume problems exist until evidence proves otherwise.
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/pev-reviewer/SKILL.md
git commit -m "feat(pev): reorder Reviewer context gathering to pitch-first"
```

---

### Task 5: Add Pass 0 — Run Tests

**Files:**
- Modify: `.claude/skills/pev-reviewer/SKILL.md:49-67` — insert before current "### Pass 1: Spec Compliance"

Tests should run before any review passes. A failing test suite is an immediate FAIL — there's no point reviewing code that doesn't pass its own tests.

- [ ] **Step 1: Read the current pass structure**

Read `.claude/skills/pev-reviewer/SKILL.md` lines 49-67 (the "## Four-Pass Review" heading and start of Pass 1).

- [ ] **Step 2: Replace the section heading and insert Pass 0**

Replace `## Four-Pass Review` with:

```markdown
## Six-Pass Review

### Pass 0: Run Tests

**Run the full test suite before any code review.** A failing test suite is an immediate finding — no point reviewing code that doesn't pass its own tests.

```bash
poetry run pytest tests/ -x -q
```

- **All pass**: Record the test count and proceed to Pass 1. Note: "all pass" means the Builder's tests pass, not that they're sufficient — test quality is evaluated in Pass 3.
- **Failures**: Record the failing tests and tracebacks. This is a **critical** finding — include it in `quality_issues` with severity `critical`. Continue with the remaining passes (the failures inform your review), but the overall verdict cannot be `PASS`.
- **Import errors / collection failures**: The code has structural problems. Record and continue.

Write results to progress:
```
cortex_update_section(
  section_id="{cycle_doc_id}::reviewer.progress",
  content="Pass 0 (Run Tests): COMPLETE — {N} tests passed / {M} failed\n{failure details if any}\n\nPass 1 (Source Doc Cross-Check): NOT STARTED\n..."
)
```
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/pev-reviewer/SKILL.md
git commit -m "feat(pev): add Pass 0 (Run Tests) to Reviewer skill"
```

---

### Task 6: Add Pass 1 — Source Document Cross-Check

**Files:**
- Modify: `.claude/skills/pev-reviewer/SKILL.md` — insert after Pass 0, before current spec compliance pass

This is the new pass that catches the "Architect misread the ADR" failure mode. The Reviewer reads the source documents referenced in the pitch and checks for contradictions.

- [ ] **Step 1: Insert Pass 1 after Pass 0**

Add the following section after Pass 0:

```markdown
### Pass 1: Source Document Cross-Check

**Purpose:** Verify the Architect's pitch is consistent with its own source documents. This catches the failure mode where the Architect misinterprets an ADR/PRD, creating a pitch that contradicts upstream intent — and the Builder + Reviewer faithfully validate the wrong thing.

**If `architect.source-documents` says "None — greenfield":** Skip this pass. Record as "SKIPPED — greenfield, no source docs" in progress.

**For each referenced source document:**

1. **Read the source document** — use `cortex_read_doc` with the doc ID from the source-documents list.
2. **Extract explicit constraints** — look for:
   - "MUST" / "MUST NOT" / "SHALL" / "SHALL NOT" requirements
   - Explicit prohibitions ("do not use X", "no Y")
   - Required approaches ("use X API", "implement via Y")
   - Scope boundaries ("only covers X", "excludes Y")
3. **Cross-check against the pitch** — for each constraint found:
   - Does the pitch's solution sketch align with or contradict this constraint?
   - Does the pitch's constraints section acknowledge this requirement?
   - Could the Builder implement the pitch as written and violate the source doc?
4. **Verdict per source doc**: **CONSISTENT** (no contradictions found), **CONTRADICTION** (pitch contradicts a specific constraint — quote both), or **INCOMPLETE** (pitch doesn't address a relevant constraint from the source doc).

**A CONTRADICTION is a critical finding.** If the pitch says "wrap DVC CLI" but the referenced ADR says "use DVC Python API, not CLI wrappers," that's a CONTRADICTION — the entire downstream implementation is building the wrong thing. This is the highest-severity issue the Reviewer can find because it means the human gate after the Architect phase missed something.

**What this pass is NOT:** A full re-evaluation of the Architect's design. You're not re-doing the Architect's job. You're looking for explicit, quotable contradictions between the pitch and its declared source documents. If the pitch says "approach X" and the source doc doesn't mention approach X at all, that's not a contradiction — the Architect has latitude to choose approaches. But if the source doc says "NOT approach X" and the pitch says "approach X," that's a clear CONTRADICTION.

Write results to progress after completing:
```
cortex_update_section(
  section_id="{cycle_doc_id}::reviewer.progress",
  content="Pass 0 (Run Tests): COMPLETE — 23 tests passed\n\nPass 1 (Source Doc Cross-Check): COMPLETE\n- ADR-007 (cortex::docs.adrs.adr-007): CONSISTENT — pitch uses Python API per ADR\n- Cache PRD (cortex::docs.features.cache.prd): INCOMPLETE — PRD mentions TTL policy, pitch doesn't address it\n\nPass 2 (Spec Compliance): NOT STARTED\n..."
)
```
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/pev-reviewer/SKILL.md
git commit -m "feat(pev): add Pass 1 (Source Document Cross-Check) to Reviewer skill"
```

---

### Task 7: Rewrite Pass 2 — Reverse Mapping + Spec Compliance with Deviation Tribunal

**Files:**
- Modify: `.claude/skills/pev-reviewer/SKILL.md` — replace current "### Pass 1: Spec Compliance" section

This combines the current forward spec compliance check with a new reverse mapping pass and a structured deviation tribunal, replacing the soft "do deviations make sense?" bullet.

- [ ] **Step 1: Read the current Pass 1 (Spec Compliance)**

Read `.claude/skills/pev-reviewer/SKILL.md` to locate the current "### Pass 1: Spec Compliance" section.

- [ ] **Step 2: Replace with new Pass 2**

Replace the entire current "### Pass 1: Spec Compliance" section (from the heading through to just before "### Pass 2: Functionality Preservation") with:

```markdown
### Pass 2: Spec Compliance (Reverse Map + Forward Check + Deviation Tribunal)

This pass has three sub-phases. The reverse map catches unauthorized changes. The forward check catches missing implementations. The deviation tribunal evaluates Builder decisions with structure, not vibes.

#### 2a. Reverse Mapping — "Is every change authorized?"

Start from the code changes, not the pitch. For every file and function the Builder modified:

1. **Get the full change list** — `git diff --name-only {baseline_sha}..HEAD` for files, `cortex_check` for node-level changes.
2. **For each changed file/node**, answer: **Which user story or declared deviation authorizes this change?**
   - If it maps to a user story: record the mapping.
   - If it maps to a declared deviation in `decisions`: record it (evaluated in 2c).
   - If it maps to neither: **flag as unauthorized change**. This is scope creep at best, or the Builder going off-script at worst. Severity: `important` minimum.
3. **Build the reverse map table:**

| Changed Node | Authorized By | Notes |
|---|---|---|
| `cortex::cortex.cache.store` | US-2 (cache integration) | Expected |
| `cortex::cortex.cli.main` | D-1 (Builder decision) | Evaluate in 2c |
| `cortex::cortex.viz.render` | **UNAUTHORIZED** | Not in pitch or decisions |

#### 2b. Forward Check — "Is every user story implemented?"

For each user story in the Architect's pitch:

1. Read the user story and its acceptance criteria
2. Find the code that implements it (use cortex_search, cortex_source, grep/read as appropriate)
3. Find the test(s) that verify it — record what each test actually exercises (not just the test name)
4. Verdict: **PASS** (code + test cover the acceptance criteria), **PARTIAL** (code exists, test missing or incomplete, or acceptance criteria partially met), or **FAIL** (not implemented)

**Build the test coverage table as you go.** For each user story, record every test that covers it and a one-line description of what that test verifies. If a story has no test coverage, mark it as a gap.

Also check:
- **Required artifacts**: For each artifact declared by the Architect in `required-artifacts`, verify it exists. Migration script? New test file? Updated CLI output? If an artifact is missing, verdict is PARTIAL at best.
- **Solution sketch fidelity**: Compare the Builder's actual approach to the Architect's solution sketch. If the Builder took a fundamentally different approach, flag it — even if user stories technically pass. The Architect may have chosen that approach for reasons (performance, compatibility, future work) that the Builder didn't consider. This gets evaluated in 2c if the Builder declared the deviation, or flagged as unauthorized if not.
- **Constraints violated**: Check the Architect's constraints/rabbit-holes section. Flag any violations as severity `critical`.

#### 2c. Deviation Tribunal — "Are the Builder's deviations justified?"

For each entry in the `decisions` section attributed to the Builder, evaluate with structure:

| Field | What to record |
|---|---|
| **Decision ID** | e.g., D-3 (Builder) |
| **What the pitch specified** | Quote the relevant pitch section (solution sketch, constraints, or task list) |
| **What the Builder did instead** | Quote the Builder's decision entry or describe from code |
| **Does it weaken any user story?** | YES/NO — if YES, which story and how |
| **Does it violate any constraint?** | YES/NO — if YES, which constraint |
| **Does it contradict a source document?** | YES/NO — if YES, which doc and what requirement |
| **Verdict** | **JUSTIFIED** (reasonable trade-off, no stories/constraints weakened), **UNJUSTIFIED** (weakens a story, violates a constraint, or contradicts a source doc), or **NEEDS_INPUT** (ambiguous — ask the user) |

An **UNJUSTIFIED** deviation is severity `critical` if it breaks a user story or constraint, `important` if it's a significant approach change without justification.

**Do not rubber-stamp deviations.** "The Builder had a good reason" is not analysis. Quote what the pitch said. Quote what the Builder did. Show the gap. Then judge.

Write results to progress after completing all three sub-phases.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/pev-reviewer/SKILL.md
git commit -m "feat(pev): rewrite Pass 2 with reverse mapping, forward check, and deviation tribunal"
```

---

### Task 8: Renumber remaining passes and update references

**Files:**
- Modify: `.claude/skills/pev-reviewer/SKILL.md` — renumber Pass 2 -> Pass 3, Pass 3 -> Pass 4, Pass 4 -> Pass 5

The existing passes shift by 2 positions due to the new Pass 0 and Pass 1. All internal references must be updated.

- [ ] **Step 1: Renumber Functionality Preservation**

Change `### Pass 2: Functionality Preservation` to `### Pass 3: Functionality Preservation`. No content changes needed — this pass is unchanged.

- [ ] **Step 2: Renumber Code Quality**

Change `### Pass 3: Code Quality` to `### Pass 4: Code Quality`. No content changes needed.

- [ ] **Step 3: Renumber PEV-Specific Checks**

Change `### Pass 4: PEV-Specific Checks` to `### Pass 5: PEV-Specific Checks`. Update internal sub-section references:
- `#### 4a.` -> `#### 5a.`
- `#### 4b.` -> `#### 5b.`
- `#### 4c.` -> `#### 5c.`

- [ ] **Step 4: Update Persisting Progress section**

In the "## Persisting Progress" section, update the example `cortex_update_section` call to reflect the new 6-pass structure:

```
cortex_update_section(
  section_id="{cycle_doc_id}::reviewer.progress",
  content="Pass 0 (Run Tests): COMPLETE — 23 tests passed\n\nPass 1 (Source Doc Cross-Check): COMPLETE\n- ADR-007: CONSISTENT\n\nPass 2 (Spec Compliance): COMPLETE\n- US-1: PASS — cortex/mcp_server.py:120, tests/test_mcp.py::test_delete\n- US-2: PARTIAL — code exists, no test for error case\n- Reverse map: 12 changes mapped, 0 unauthorized\n- Deviations: D-2 JUSTIFIED, D-3 UNJUSTIFIED (violates constraint C-1)\n\nPass 3 (Functionality): NOT STARTED\nPass 4 (Code Quality): NOT STARTED\nPass 5 (PEV Checks): NOT STARTED"
)
```

- [ ] **Step 5: Update the "three-pass review" reference in Gathering Context**

Search for any remaining references to "three-pass" or "four-pass" in the file and update them to "six-pass". (Note: the Gathering Context section from Task 4 should already say "six-pass" — check for any other stale references.)

- [ ] **Step 6: Update Budget Management section references**

In the Budget Management section, update the example from "If still in Pass 1" to "If still in Pass 2" (since Passes 0-1 should be quick).

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/pev-reviewer/SKILL.md
git commit -m "refactor(pev): renumber Reviewer passes to accommodate new Pass 0 and Pass 1"
```

---

### Task 9: Update return format with new fields

**Files:**
- Modify: `.claude/skills/pev-reviewer/SKILL.md:~165-235` — the "## Return Format" section

Add new JSON fields for source doc cross-check, reverse mapping, and deviation tribunal results.

- [ ] **Step 1: Read the current return format**

Read `.claude/skills/pev-reviewer/SKILL.md` to locate the complete verdict JSON example.

- [ ] **Step 2: Update the complete verdict JSON**

Replace the existing `---REVIEW---` JSON example with:

```json
{
  "status": "PASS|FAIL|PASS_WITH_CONCERNS",
  "test_run": {
    "total": 23,
    "passed": 23,
    "failed": 0,
    "errors": []
  },
  "source_doc_check": [
    {
      "doc_id": "cortex::docs.adrs.adr-007",
      "summary": "DVC integration must use Python API, no CLI wrappers",
      "verdict": "CONSISTENT|CONTRADICTION|INCOMPLETE",
      "detail": null
    }
  ],
  "reverse_mapping": {
    "total_changes": 15,
    "mapped_to_story": 12,
    "mapped_to_deviation": 2,
    "unauthorized": 1,
    "unauthorized_details": [
      {
        "node": "cortex::cortex.viz.render",
        "description": "Added tooltip rendering — not in pitch or decisions"
      }
    ]
  },
  "spec_compliance": [
    {
      "story": "As a user, I want per-dimension staleness so I can see what kind of drift occurred",
      "verdict": "PASS|PARTIAL|FAIL",
      "evidence": "cortex/index/staleness.py:45, tests/test_staleness.py::test_two_column",
      "note": null
    }
  ],
  "deviation_tribunal": [
    {
      "decision_id": "D-3 (Builder)",
      "pitch_specified": "Use FTS5 triggers for real-time index updates",
      "builder_did": "Batch rebuild via cron — FTS5 triggers caused write contention",
      "weakens_story": false,
      "violates_constraint": false,
      "contradicts_source_doc": false,
      "verdict": "JUSTIFIED|UNJUSTIFIED|NEEDS_INPUT",
      "reasoning": "Write contention is a valid concern; batch approach still meets US-3 acceptance criteria"
    }
  ],
  "required_artifacts": [
    {
      "artifact": "Migration script for new DB columns",
      "present": true,
      "location": "cortex/index/db.py::init_db"
    }
  ],
  "functionality": [
    {
      "file": "cortex/index/db.py",
      "callers_checked": 8,
      "concerns": null
    }
  ],
  "quality_issues": [
    {
      "severity": "critical|important|minor",
      "file": "cortex/index/staleness.py",
      "description": "Magic number 0.8 threshold — consider named constant"
    }
  ],
  "pev_checks": [
    {
      "check": "logging|test_annotations|workflow_markers",
      "node_id": "cortex::module.function",
      "severity": "critical|important|minor",
      "description": "What needs attention"
    }
  ],
  "test_coverage": [
    {
      "story": "As a user, I want per-dimension staleness so I can see what kind of drift occurred",
      "tests": [
        {"test": "tests/test_staleness.py::test_two_column", "verifies": "Staleness splits into own_status and link_status columns"},
        {"test": "tests/test_staleness.py::test_dimension_display", "verifies": "CLI output shows both dimensions separately"}
      ]
    }
  ],
  "scope_creep": [],
  "decisions_review": "D-2 JUSTIFIED (write contention), D-3 UNJUSTIFIED (violates constraint C-1: no external dependencies)",
  "summary": "All user stories pass. Source docs consistent. 1 unauthorized change flagged. 1 unjustified deviation."
}
```

- [ ] **Step 3: Update the CONTINUING verdict format**

Update the `passes_completed` and `passes_remaining` arrays in the CONTINUING example to use the new pass names:

```json
{
  "status": "CONTINUING",
  "passes_completed": ["test_run", "source_doc_check", "spec_compliance"],
  "passes_remaining": ["functionality", "quality", "pev_checks"],
  "test_run": { "total": 23, "passed": 23, "failed": 0, "errors": [] },
  "source_doc_check": [ ... ],
  "reverse_mapping": { ... },
  "spec_compliance": [ ... ],
  "deviation_tribunal": [ ... ],
  "required_artifacts": [ ... ],
  "test_coverage": [ ... ],
  "pev_checks": [],
  "summary": "Passes 0-2 complete. 5/5 stories PASS. No source doc contradictions. Passes 3-5 not started."
}
```

- [ ] **Step 4: Update the Status Codes table**

Add a note to the FAIL row: "Missing user stories, broken callers, constraint violations, **source document contradictions**, or **unjustified deviations**".

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/pev-reviewer/SKILL.md
git commit -m "feat(pev): update Reviewer return format with source doc, reverse mapping, and tribunal fields"
```

---

### Task 10: Update orchestrator Reviewer dispatch prompt

**Files:**
- Modify: `.claude/templates/pev-orchestrator-reference.md:232-255` — Reviewer dispatch prompt

The dispatch prompt needs to mention source documents so the Reviewer knows to look for them.

- [ ] **Step 1: Read the current Reviewer dispatch prompt**

Read `.claude/templates/pev-orchestrator-reference.md` lines 232-255.

- [ ] **Step 2: Update the dispatch prompt**

Replace the current Reviewer dispatch prompt with:

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
```

- [ ] **Step 3: Update the re-review prompt**

The existing re-review append (`RE-REVIEW: The Builder has addressed...`) is fine as-is — it applies to fix iterations, not the initial dispatch.

- [ ] **Step 4: Commit**

```bash
git add .claude/templates/pev-orchestrator-reference.md
git commit -m "feat(pev): update Reviewer dispatch prompt with source docs and adversarial stance"
```

---

### Task 11: Update orchestrator Phase 5 (Review) handling

**Files:**
- Modify: `.claude/skills/pev-cycle/SKILL.md` — Phase 5 section

The orchestrator's Phase 5 description needs to mention the new pass structure and how to handle source doc contradictions.

- [ ] **Step 1: Read the current Phase 5**

Read `.claude/skills/pev-cycle/SKILL.md` to locate Phase 5 (Review).

- [ ] **Step 2: Update Phase 5 description**

In Phase 5, update the Reviewer description from "three-pass review" to "six-pass review":

Replace:
```
The Reviewer performs a three-pass review against the Architect's pitch:
1. **Spec compliance** — per-user-story pass/fail with evidence
2. **Functionality preservation** — callers checked via cortex_graph, behavioral changes flagged
3. **Code quality** — issues ranked critical/important/minor
```

With:
```
The Reviewer performs a six-pass review:
0. **Run tests** — full test suite, immediate FAIL if tests don't pass
1. **Source document cross-check** — pitch vs referenced ADRs/PRDs for contradictions
2. **Spec compliance** — reverse mapping (every change authorized?), forward check (every story implemented?), deviation tribunal (Builder decisions justified?)
3. **Functionality preservation** — callers checked via cortex_graph, behavioral changes flagged
4. **Code quality** — issues ranked critical/important/minor
5. **PEV-specific checks** — logging, test annotations, workflow markers
```

- [ ] **Step 3: Add source doc contradiction handling**

After the FAIL handling bullet, add guidance for source doc contradictions:

```markdown
- **Source doc CONTRADICTION in review**: If the Reviewer finds a CONTRADICTION between the pitch and a source document, this is a special case. The Builder implemented the pitch correctly — the pitch itself is wrong. Present to user: "The Reviewer found that the Architect's pitch contradicts [source doc]. The Builder implemented the pitch as written, but the pitch is inconsistent with upstream requirements. Options: (1) abort and re-plan with a new Architect dispatch, (2) proceed to merge knowing the contradiction exists." **HUMAN GATE**.
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/pev-cycle/SKILL.md
git commit -m "feat(pev): update orchestrator Phase 5 for six-pass review and source doc contradictions"
```

---

### Task 12: Cross-file consistency verification

**Files:**
- Read: All 5 modified files end-to-end

No edits expected — this is a verification pass to catch inconsistencies.

- [ ] **Step 1: Verify manifest template JSON**

Run:
```bash
python -c "import json; json.load(open('.claude/templates/cycle-manifest-template.json'))"
```
Expected: No output (valid JSON).

- [ ] **Step 2: Verify section IDs match**

Check that:
- `architect.source-documents` appears in: manifest template, Architect skill Step 5 table, Reviewer skill Pass 1, Reviewer dispatch prompt
- Pass names in Reviewer skill match: progress examples, return format JSON, CONTINUING format, Budget Management section

Run:
```bash
grep -c "source-documents" .claude/templates/cycle-manifest-template.json .claude/skills/pev-architect/SKILL.md .claude/skills/pev-reviewer/SKILL.md .claude/templates/pev-orchestrator-reference.md
```
Expected: At least 1 match in each file.

- [ ] **Step 3: Verify no stale "three-pass" or "four-pass" references**

Run:
```bash
grep -rn "three-pass\|four-pass\|Four-Pass" .claude/skills/pev-reviewer/ .claude/skills/pev-cycle/ .claude/templates/pev-orchestrator-reference.md
```
Expected: No matches.

- [ ] **Step 4: Verify no stale "Pass 1:" or "Pass 2:" with old content**

Read through `.claude/skills/pev-reviewer/SKILL.md` end-to-end and verify:
- Pass 0 = Run Tests
- Pass 1 = Source Document Cross-Check
- Pass 2 = Spec Compliance (Reverse Map + Forward Check + Deviation Tribunal)
- Pass 3 = Functionality Preservation
- Pass 4 = Code Quality
- Pass 5 = PEV-Specific Checks

- [ ] **Step 5: Verify Reviewer agent definition mentions both failure modes**

Read `.claude/agents/pev-reviewer.md` and confirm it mentions:
1. Builder drift (deviation from pitch)
2. Pitch contradiction (pitch vs source docs)

- [ ] **Step 6: Final commit (if any fixes needed)**

If any inconsistencies were found and fixed:
```bash
git add -A
git commit -m "fix(pev): resolve cross-file inconsistencies in Reviewer hardening"
```

---

## Part 2: Architect Source Document Workflow

Tasks 13-16 formalize how the Architect interacts with source documents. The Architect reads DocJSON source docs via cortex tools and proposes edits through the orchestrator. The orchestrator presents proposed edits to the user, applies approved ones via `cortex_update_section`, and resumes the Architect. The Architect stays read-only on source docs — it never writes to them directly.

---

### Task 13: Extend NEEDS_INPUT protocol with doc_edits field

**Files:**
- Modify: `.claude/skills/pev-architect/SKILL.md:~68-110` — the NEEDS_INPUT protocol section in Step 4

The Architect's NEEDS_INPUT JSON currently supports `preamble`, `questions`, and `context`. Add a `doc_edits` field so the Architect can propose source document revisions alongside (or instead of) questions.

- [ ] **Step 1: Read the current NEEDS_INPUT protocol**

Read `.claude/skills/pev-architect/SKILL.md` and locate the NEEDS_INPUT protocol section (inside Step 4: Engage with the user).

- [ ] **Step 2: Add doc_edits to the NEEDS_INPUT format**

After the existing `context` field description in the NEEDS_INPUT format documentation, add documentation for the new `doc_edits` field. Update the JSON format block to:

```json
{"status": "NEEDS_INPUT", "preamble": "...markdown context shown to the user before the questions...", "questions": [...], "doc_edits": [{"doc_id": "cortex::docs.adrs.adr-007", "section_id": "cortex::docs.adrs.adr-007::requirements", "reason": "ADR says 'CLI wrappers acceptable' but this contradicts the intent — should say 'Python API only, no CLI wrappers'", "current_summary": "Current text allows CLI wrappers as an implementation option", "proposed_content": "The DVC integration MUST use the DVC Python API directly. CLI wrappers (`dvc add`, `dvc push`, etc.) are NOT permitted — they create .dvc pointer files and require DVC to be installed as a system dependency."}], "context": "...state to preserve across the round-trip..."}
```

Add this field documentation after the existing fields:

```markdown
- `doc_edits` (optional) — proposed changes to source documents (ADRs, PRDs, design specs). Each entry contains:
  - `doc_id`: the cortex doc ID of the source document to edit
  - `section_id`: the full section ID to update (doc_id::section)
  - `reason`: why this edit is needed — what's wrong or missing in the current text
  - `current_summary`: one-line summary of what the section currently says (so the user can evaluate without reading the full doc)
  - `proposed_content`: the complete replacement content for the section
  The orchestrator presents each proposed edit to the user for approval. Approved edits are applied via `cortex_update_section` before resuming you. Rejected edits are reported back so you can adjust your pitch accordingly.
  **When to use:** When the source document has gaps, ambiguities, or contradictions that would make the pitch unreliable. Fix the source of truth first, then derive the pitch from it.
  **When NOT to use:** Don't propose edits for stylistic preferences or minor wording. Only propose edits that affect the correctness or completeness of the pitch.
```

- [ ] **Step 3: Add the orchestrator response format for doc_edits**

After the existing response format documentation (`When the orchestrator resumes you, you receive: {"answers": ...}`), add:

```markdown
- If you included `doc_edits`, the response also contains: `{"doc_edit_results": [{"section_id": "...", "status": "applied|rejected", "user_note": "...optional user comment..."}]}`. Check these results — if a critical edit was rejected, you may need to adjust your pitch to work within the existing source doc constraints, or ask the user why.
```

- [ ] **Step 4: Update the "questions" field to be optional**

Currently the format implies `questions` is required. Update the field documentation to note that `questions` and `doc_edits` are both optional, but at least one must be present:

```markdown
- `questions` (optional if `doc_edits` present) — follows the `AskUserQuestion` schema: 1-4 questions...
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/pev-architect/SKILL.md
git commit -m "feat(pev): add doc_edits field to Architect NEEDS_INPUT protocol"
```

---

### Task 14: Add source doc edit engagement pattern to Architect skill

**Files:**
- Modify: `.claude/skills/pev-architect/SKILL.md:~130-155` — the interaction patterns table in Step 4

Add a new engagement pattern for proposing source document revisions during brainstorming.

- [ ] **Step 1: Read the current interaction patterns table**

Read `.claude/skills/pev-architect/SKILL.md` and locate the interaction patterns table in Step 4.

- [ ] **Step 2: Add source doc revision pattern to the table**

Add a new row to the interaction patterns table:

| Pattern | When to use | Example |
|---|---|---|
| **Source doc revision** | Source document has gaps, ambiguities, or contradictions that would make the pitch unreliable. Fix the source of truth before deriving the pitch. | Preamble explains what's wrong in the ADR. `doc_edits` proposes specific section changes. Questions (if any) ask about scope or intent. |

- [ ] **Step 3: Add guidance on when to propose source doc edits**

After the interaction patterns table, add a new sub-section:

```markdown
#### Source document edits

When you read a source document (ADR, PRD, design spec) and find it has issues that would affect your pitch, propose edits rather than working around the problem. Common triggers:

- **Ambiguous requirements** — the ADR says "may use X" when it should say "must use X" or "must not use X". Ambiguity lets the Builder choose the wrong interpretation.
- **Missing constraints** — the PRD defines what to build but not how to avoid known pitfalls. Add the constraint.
- **Contradictory sections** — one section says approach A, another implies approach B. Resolve the contradiction.
- **Stale content** — the doc references an old API or pattern that's been replaced. Update it.

**Flow:**
1. Read the source doc during Step 2 (Explore)
2. Note issues that affect your pitch
3. In your first NEEDS_INPUT round, include `doc_edits` alongside your brainstorm offer
4. The orchestrator applies approved edits before resuming you
5. Re-read the updated sections if needed, then write your pitch from the corrected source

**Do NOT propose edits that:**
- Change the fundamental intent of the document (that's the user's decision, not yours)
- Are purely stylistic or organizational
- Add implementation details to a requirements doc (keep the abstraction level appropriate)

If you're unsure whether an edit is appropriate, include it in your `preamble` as a question rather than a `doc_edit`.
```

- [ ] **Step 4: Update convergence guidance**

In the convergence guidance section, add a note:

```markdown
If source doc edits are needed, propose them in round 1 alongside the brainstorm offer. Getting the source docs right early means the rest of the engagement builds on a solid foundation.
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/pev-architect/SKILL.md
git commit -m "feat(pev): add source doc revision engagement pattern to Architect skill"
```

---

### Task 15: Update orchestrator to handle doc_edits in NEEDS_INPUT

**Files:**
- Modify: `.claude/skills/pev-cycle/SKILL.md` — Phase 2 (Plan) NEEDS_INPUT handling
- Modify: `.claude/templates/pev-orchestrator-reference.md` — Architect dispatch response handling

The orchestrator needs to detect `doc_edits` in the Architect's NEEDS_INPUT response, present them to the user, apply approved ones, and include the results when resuming the Architect.

- [ ] **Step 1: Read the current Phase 2 NEEDS_INPUT handling**

Read `.claude/skills/pev-cycle/SKILL.md` and locate the Phase 2 (Plan) section, specifically the NEEDS_INPUT handling.

- [ ] **Step 2: Update Phase 2 NEEDS_INPUT handling**

In Phase 2, expand the NEEDS_INPUT handling from:

```markdown
- **NEEDS_INPUT**: If the payload includes a `preamble` field, print it as a text message to the user first. Then relay the Architect's `questions` to the user via AskUserQuestion. Resume with SendMessage containing the answers and the Architect's `context` field.
```

To:

```markdown
- **NEEDS_INPUT**: Parse the Architect's JSON payload.
  1. If `preamble` is present, print it as a text message to the user.
  2. If `doc_edits` is present, handle source document edit proposals:
     - For each proposed edit, present to the user: "The Architect proposes updating **{doc_id}** section `{section_id}`: {reason}. Current: {current_summary}. Proposed change: {proposed_content}. **Approve or reject?**"
     - Use AskUserQuestion with options: "Approve" / "Reject" / "Reject with note" for each edit. Batch up to 4 edits per AskUserQuestion call (the schema limit).
     - For approved edits: apply via `cortex_update_section(section_id="{section_id}", content="{proposed_content}")`. Record result as `{"section_id": "...", "status": "applied"}`.
     - For rejected edits: record as `{"section_id": "...", "status": "rejected", "user_note": "..."}`.
  3. If `questions` is present, relay to the user via AskUserQuestion (existing behavior).
  4. Resume with SendMessage containing: `{"answers": {...}, "doc_edit_results": [...], "context": "...architect's context..."}`. Omit `doc_edit_results` if no `doc_edits` were proposed.
```

- [ ] **Step 3: Update the orchestrator reference — Architect response handling**

Read `.claude/templates/pev-orchestrator-reference.md` and locate the Architect dispatch section. After the existing Architect dispatch prompts, add a new sub-section:

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/pev-cycle/SKILL.md .claude/templates/pev-orchestrator-reference.md
git commit -m "feat(pev): add doc_edits handling to orchestrator Phase 2 and reference"
```

---

### Task 16: Update Architect skill — pitch derivation from source docs

**Files:**
- Modify: `.claude/skills/pev-architect/SKILL.md:~175-220` — Step 5 (Write remaining sections) and Step 6 (Self-review)

After source doc edits are applied, the Architect should explicitly derive the pitch from the updated source docs and verify alignment during self-review.

- [ ] **Step 1: Read Step 5 and Step 6**

Read `.claude/skills/pev-architect/SKILL.md` and locate Step 5 (Write remaining architect sub-sections) and Step 6 (Self-review the pitch).

- [ ] **Step 2: Add source doc derivation note to Step 5**

At the beginning of Step 5, before the section table, add:

```markdown
**If source doc edits were applied:** Re-read the updated sections of the source documents before writing the remaining pitch sections. Your pitch must be derived from the current state of the source docs, not your memory of what they said before edits. Use `cortex_read_doc` to re-read any section that was updated.
```

- [ ] **Step 3: Update the source-documents section description**

In the Step 5 table row for `architect.source-documents` (added in Task 2), update the description to note edit history:

| Section ID | What to write |
|---|---|
| `architect.source-documents` | Every ADR, PRD, design spec, prior cycle doc, or issue that informed this pitch. For each document, include: (1) the cortex doc ID or file path, (2) a one-line summary of the constraint or requirement it contributes to this pitch, (3) whether it was edited during this cycle's planning phase (mark as "edited in this cycle" if doc_edits were applied). Example: `1. **cortex::docs.adrs.adr-007** — DVC integration must use Python API, no CLI wrappers or .dvc pointer files. (Edited in this cycle: clarified "may use" → "must use" for Python API requirement.) 2. **cortex::docs.features.cache.prd** — Cache layer PRD defining storage requirements.` |

- [ ] **Step 4: Add source doc alignment check to Step 6 (Self-review)**

In Step 6, add a new check to the self-review checklist (after the existing checks):

```markdown
5. **Source doc alignment** — if source doc edits were applied, verify your pitch is consistent with the updated (not original) text. Re-read any edited sections and compare against your pitch sections. A pitch that was correct before the edits may now be inconsistent.
6. **Source documents section completeness** — verify `architect.source-documents` lists every doc you read during exploration, not just the ones you edited. The Reviewer uses this list to cross-check — a missing entry means the Reviewer won't check that doc.
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/pev-architect/SKILL.md
git commit -m "feat(pev): add source doc derivation and alignment checks to Architect skill"
```

---

### Task 17: Final cross-file consistency verification (expanded)

**Files:**
- Read: All modified files end-to-end

This expands Task 12 to also verify the Architect source doc workflow changes are consistent.

- [ ] **Step 1: Verify doc_edits field consistency**

Check that:
- `doc_edits` field format is described identically in: Architect skill NEEDS_INPUT section, orchestrator Phase 2, orchestrator reference
- `doc_edit_results` response format matches between: Architect skill response docs, orchestrator reference
- The field names (`doc_id`, `section_id`, `reason`, `current_summary`, `proposed_content`) are used consistently

Run:
```bash
grep -c "doc_edits" .claude/skills/pev-architect/SKILL.md .claude/skills/pev-cycle/SKILL.md .claude/templates/pev-orchestrator-reference.md
```
Expected: At least 1 match in each file.

- [ ] **Step 2: Verify source-documents section is referenced everywhere needed**

Run:
```bash
grep -c "source-documents" .claude/templates/cycle-manifest-template.json .claude/skills/pev-architect/SKILL.md .claude/skills/pev-reviewer/SKILL.md .claude/templates/pev-orchestrator-reference.md
```
Expected: At least 1 match in each file.

- [ ] **Step 3: Verify Architect skill flow coherence**

Read `.claude/skills/pev-architect/SKILL.md` end-to-end and verify the flow makes sense:
1. Step 2: Explore + identify source docs
2. Step 3: Write early sections (scope + problem)
3. Step 4: Engage — brainstorm offer + source doc edits (if needed) + design questions
4. Step 5: Re-read updated source docs (if edited) + write remaining sections including source-documents
5. Step 6: Self-review including source doc alignment check
6. Step 7: Return

- [ ] **Step 4: Verify no stale references**

Run:
```bash
grep -rn "three-pass\|four-pass\|Four-Pass" .claude/skills/pev-reviewer/ .claude/skills/pev-cycle/ .claude/templates/pev-orchestrator-reference.md
```
Expected: No matches.

Also check that the Reviewer Guidelines section references Pass 0 for test running (not a standalone bullet).

- [ ] **Step 5: Final commit (if any fixes needed)**

If any inconsistencies were found and fixed:
```bash
git add -A
git commit -m "fix(pev): resolve cross-file inconsistencies in Reviewer + Architect workflow changes"
```
