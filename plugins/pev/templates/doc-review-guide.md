# Doc Review Guide

This file describes the documentation surface the Doc Reviewer should scan for drift after each PEV cycle. Copy to `.pev/doc-review-guide.md` in your repo and customize.

**What reads this file:**

- **Doc Reviewer** — iterates over each doc category, applies review passes against the change-set

The Auditor operates on documentation that's linked in the cortex graph (design docs referenced by code nodes, feature docs tied to modules). Many projects also have **freeform, unlinked documentation** — PRDs, interface specs, user-facing requirement docs, ADRs — that the Auditor can't see. The Doc Reviewer scans those.

If `.pev/doc-review-guide.md` is not present, the Doc Reviewer falls back to a generic scan: it walks `docs/` and flags any file modified within the cycle's change window as a candidate for stale-ness review. That fallback is noisy; a project-specific guide is much better.

---

## Categories

Each category describes a class of documentation with its own path, update triggers, and review checks. Add, remove, or rename categories to match your project.

### PRD

- **Path**: `docs/prd/**/*.md`
- **Reviewed when**: cycle touched user-facing behavior, added features, or changed acceptance criteria
- **Check for**:
  - Feature list still accurate — new features added, removed features noted
  - Acceptance criteria still match implemented behavior
  - Out-of-scope items haven't silently crept in
  - User stories haven't drifted from the pitch's user stories
- **Template**: `docs/templates/prd-template.md` (if you have one — Doc Reviewer compares structure)

### Interface spec

- **Path**: `docs/interfaces/**/*.md`
- **Reviewed when**: cycle touched public API surface, function signatures, or contract boundaries
- **Check for**:
  - Signatures in the doc match the actual code (use `cortex_source` to verify)
  - Example snippets in the doc would still run against the new code
  - Deprecations recorded (what was removed, what replaced it, migration path)
  - Error conditions documented for new failure modes

### ADR

- **Path**: `docs/adr/*.md`
- **Reviewed when**: cycle touched architectural decisions, or a prior ADR was invalidated by the change
- **Check for**:
  - Status field accurate (`proposed` / `accepted` / `superseded`)
  - If a new architectural decision was made during the cycle, a new ADR exists for it
  - Superseded ADRs link forward to the new one that replaces them
  - Consequences section still accurate given implementation experience

### Design spec

- **Path**: `docs/design/**/*.md`
- **Reviewed when**: cycle touched internal architecture, module boundaries, or data flow
- **Check for**:
  - Module descriptions match actual module responsibilities in code
  - Data-flow diagrams accurate (file paths, function names referenced still exist)
  - Cross-module contracts (who calls whom) still valid

### README / top-level docs

- **Path**: `README.md`, `CONTRIBUTING.md`, `docs/getting-started.md`
- **Reviewed when**: cycle changed install/setup, common workflows, or project structure
- **Check for**:
  - Install/setup commands still correct
  - Example code still runs
  - Links to moved files still resolve
  - Feature list in README matches current capabilities

---

## Conventions

Use this section for project-wide documentation style rules the Doc Reviewer should respect.

- Cross-references use `[link text](relative/path.md)`, not cortex node IDs
- Code snippets in docs are Python 3.12+ and pandoc-flavored Markdown fences
- Section headings use Title Case, not Sentence case
- Every doc has an H1 (`# Title`) and the first paragraph is a one-sentence summary
- Dates use ISO format (`YYYY-MM-DD`) not `M/D/YY`

The Doc Reviewer flags violations of these as part of its scan.

---

## Review passes

When applied to each category, the Doc Reviewer runs these passes:

1. **Path exists** — files matching the category's path glob actually exist
2. **Change-relevance** — using the cycle's change-set, identify which docs in the category *should* be affected
3. **Drift check** — for each affected doc, compare against the code it describes. Flag inaccuracies.
4. **Template compliance** — if a template is listed, compare structure (required sections present, ordered correctly)
5. **Convention compliance** — check the whole-category conventions above
6. **Cross-ref validation** — verify any links in the doc still resolve

Findings are reported to the `doc-review` section of the cycle manifest with a severity ranking.

---

## Project-specific additions

Anything below this heading is free-form for your project. The Doc Reviewer reads it for context but doesn't enforce structure.
