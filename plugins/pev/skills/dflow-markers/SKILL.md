---
name: dflow-markers
description: Reference for dFlow decorator and step marker syntax. Use when adding or modifying @workflow, @task, Step, or AutoStep markers in Python code.
disable-model-invocation: false
---

# dFlow Marker Syntax Reference

The canonical reference for dFlow decorator and step marker syntax lives in axiom-graph docs:

```
axiom_graph_render("axiom_graph::docs.references.dflow-markers", level=2)
```

Use `axiom_graph_search("dflow step marker")` to find it, or render individual sections:

- `axiom_graph::docs.references.dflow-markers::core-rule` — the one rule that governs everything
- `axiom_graph::docs.references.dflow-markers::decorators` — `@workflow` and `@task` usage
- `axiom_graph::docs.references.dflow-markers::step-markers` — `Step` and `AutoStep` fields and numbering
- `axiom_graph::docs.references.dflow-markers::common-mistakes` — error table
- `axiom_graph::docs.references.dflow-markers::pattern-summary` — quick copy-paste template

**Quick reminder:** Minor step numbers (N.M) can ONLY appear inside loops. Major step numbers (integers) can appear anywhere.
