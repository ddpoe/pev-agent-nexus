# Review Criteria

This file describes project-specific emphasis areas for the code Reviewer's Pass 4 (PEV-specific checks). Copy to `.pev/review-criteria.md` and customize. Optional — if absent, the Reviewer falls back to generic quality checks.

**What reads this file:**

- **Reviewer** — during Pass 4, applies these project-specific checks on top of the generic ones (spec compliance, functionality preservation, code quality)

This file is the right place to encode project conventions that a generic code review would miss — logging styles, error handling patterns, feature-flag usage, performance-sensitive paths, anti-patterns specific to this codebase.

---

## Generic checks (always applied)

The Reviewer always runs these regardless of this file:

- **Spec compliance** — every change authorized by the pitch? Every user story implemented?
- **Functionality preservation** — callers of modified functions still work? Behavioral changes documented?
- **Code quality** — issues ranked critical / important / minor
- **Source-doc cross-check** — pitch consistent with referenced ADRs / PRDs?

---

## Project-specific checks

Add a section per emphasis area. Each section has: **what to check**, **how severe a violation is**, and optionally **example of right vs wrong**.

### Logging

- **What to check**: every `log.error()` call has a correlation ID (either `request_id` or `trace_id`) in its structured fields
- **Severity**: important (merge should be gated on fix)
- **Rationale**: production debugging relies on threading IDs through logs; an error without one is ~useless

```python
# ✅ right
log.error("failed to persist record", request_id=req.id, exc_info=True)

# ❌ wrong — no correlation
log.error("failed to persist record", exc_info=True)
```

### Error handling

- **What to check**: new code that raises typed exceptions (e.g., `ValidationError`, `NotFoundError`) instead of bare `ValueError` / `Exception`
- **Severity**: minor unless at a public API boundary (then important)
- **Rationale**: typed exceptions enable downstream handlers to react correctly; bare exceptions force callers to parse error messages

### Test annotation tiers

- **What to check**: tests Builder added correctly annotated per `.pev/test-policy.md` — tier matches what the Architect proposed in `architect.test-plan`
- **Severity**: important (tier drift breaks cortex indexing downstream)
- **Cross-reference**: `.pev/test-policy.md`

### Workflow markers (dFlow / cortex)

- **What to check**: new workflow functions have `@workflow` decorators with `purpose` strings; multi-step workflows have numbered `Step()` markers
- **Severity**: important if the workflow is user-facing, minor if internal
- **Cross-reference**: `.pev/test-policy.md` (annotation contract) if your project uses workflow markers in test code too

---

## Anti-patterns specific to this codebase

List things that are easy to do but systematically wrong in this project. These are patterns an agent might introduce without realizing they're problematic.

- **Don't**: import from `internal/` modules outside the owning package
- **Don't**: use `datetime.now()` without a timezone argument
- **Don't**: rely on dict ordering for anything user-visible
- **Don't**: catch `Exception` broadly — catch specific types

---

## Severity guide

The Reviewer's Pass 4 findings use these levels:

| Severity | Meaning | Effect on merge |
|---|---|---|
| `critical` | Breaks the feature, violates security/correctness, will cause production failures | Blocks merge |
| `important` | Degrades quality meaningfully; should be fixed before merge | Gates merge (Builder loopback) |
| `minor` | Style, naming, small improvements | Noted; does not block merge |

---

## Project-specific additions

Free-form below. The Reviewer reads this for context but doesn't enforce structure.
