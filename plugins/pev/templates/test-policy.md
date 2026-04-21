# Test Policy

This file describes how tests are organized, classified, annotated, and budgeted in a project using PEV. The Architect, Builder, and Reviewer all read it — copy it to `.pev/test-policy.md` in your repo and customize.

**What reads this file:**

- **Architect** — uses the tier/decision rule to produce `architect.test-plan` in the pitch
- **Builder** — uses the annotation conventions to mark tests correctly as it implements
- **Reviewer** — cross-checks Builder's tests against the policy during Pass 4 (PEV-specific checks)

If `.pev/test-policy.md` is not present in the project, the agents fall back to the plugin-shipped default at `${CLAUDE_PLUGIN_ROOT}/templates/test-policy.md` (this file). The default reflects the cortex project's conventions — **edit or replace freely for your project.**

---

## Tier Decision Rule

**"Would a non-developer stakeholder recognize this test as a product story?"**

- **Yes** → Tier 3 (full annotation — narrative preserved)
- **No, but it exercises a meaningful subsystem boundary** → Tier 2 (purpose annotation)
- **No, it's exercising internal logic, a helper, or a specific edge case** → Tier 1 (plain pytest)

Projects with distinct test surfaces (e.g. backend + GUI, or data pipelines + provenance capture) may want to add more tiers or refactor these. The contract with the Architect is only that **every proposed test must map to a tier**, and the Builder and Reviewer must agree on what each tier means.

---

## Tier 1 — Plain pytest

No decorator, no narrative markers. Good docstrings are sufficient.

Internal helpers, edge cases, parameterized variants of a behavior that's already stakeholder-readable at a higher tier. Tier 1 tests change frequently as internals evolve — they should be easy to rewrite without annotation overhead.

```python
def test_validate_edge_empty_source():
    assert validate_edge(src="", dst="x") is False
```

## Tier 2 — `@workflow(purpose=...)`

Purpose string only — no `Step()` markers. Signals intent at a subsystem level without requiring a full narrative.

Integration tests, tests that exercise a full pipeline inside one module, subsystem contract tests.

```python
@workflow(purpose="Verify that scan_module emits validates edges for all direct calls in a test function")
def test_validates_edges_from_direct_calls(tmp_path):
    ...
```

## Tier 3 — `@workflow(purpose=...)` + `Step()`/`AutoStep()`

Full narrative markers. A reader should be able to understand the test from the annotations alone, without opening the source.

End-to-end flows, user-story-level scenarios, anything that proves an acceptance criterion from the Architect's pitch. `Step(critical="NOT IMPLEMENTED")` is the right marker for skeleton steps — documents the roadmap without faking a green test.

```python
@workflow(
    purpose="Verify that cortex build auto-generates validates edges from test call graph with no manual annotation",
)
def test_ast_validates_edges_end_to_end(tmp_path):
    口 = Step(step_num=1, name="Write production module",
              purpose="Create a .py file with an indexed function")
    ...
    口 = Step(step_num=2, name="Write test file",
              purpose="Create a test_*.py that imports and calls the production function")
    ...
    口 = Step(step_num=3, name="Run cortex build",
              purpose="Scan both files and upsert nodes and edges")
    ...
    口 = Step(step_num=4, name="Assert validates edge exists",
              purpose="Confirm the test function has a validates edge to the production function")
    ...
```

---

## Coverage

Projects differ on how coverage is tracked. The cortex project uses the AST call graph: `validates` edges are auto-generated at build time from test function calls to indexed production functions. No manual `covers=[]` annotation.

If your project tracks coverage differently (e.g., pytest-cov thresholds, explicit test-to-story mapping, end-to-end smoke suites), document it here. The Reviewer reads this section when verifying the Builder's test coverage matches what the Architect's pitch claimed.

---

## Annotation Contract

For the default cortex-style tiers above:

| Tier | Decorator | Markers | Typical length |
|---|---|---|---|
| 1 | none | none | short (<30 lines) |
| 2 | `@workflow(purpose=...)` | none | medium |
| 3 | `@workflow(purpose=...)` | `Step()` / `AutoStep()` | longer (narrative-driven) |

If you replace the tier system, replace this table with the equivalent for your project. The Builder reads it verbatim.

---

## Test Budget

**Guideline: 5-10 focused tests per subsystem change.** Past 15, you are likely testing implementation details rather than behavior — consolidate.

The goal is tests that each cover a meaningful scenario. Three similar assertions about the same behavior belong in one test, not three. A test that exercises a complete flow (write data → read data → verify) is worth more than five tests that each check one field.

**Signs of over-testing:**
- Multiple tests that differ only in the input value (parameterize instead)
- Separate tests for setup, action, and assertion that could be one test
- Tests that duplicate assertions already covered by another test at a higher level
- Tests for internal helpers that are already exercised through a public API test

**Signs of under-testing:**
- Changed code nodes with no coverage signal (no test exercises them)
- Edge cases mentioned in the pitch or design spec but not exercised
- Error paths with no negative test

---

## Project-specific sections

Use this area for project-specific testing rules — tooling, GUI conventions, provenance-tracking requirements, whatever. Each project can shape this freely. The three skills that read this file expect the sections *above* (tiers, coverage, annotation contract, budget) to exist; additions here are for humans and project-specific agent reasoning.

---

## Auditor enforcement note

The Auditor references the budget section during its post-merge test audit. Excessive test counts go in the Impact Report under `needs_fix` with category `test_budget`, along with specific consolidation recommendations. The Builder is expected to generate tests within budget; the Auditor catches overruns.
