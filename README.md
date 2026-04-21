# pev-agent-nexus

Claude Code plugin marketplace with two plugins:

| Plugin | Purpose |
|---|---|
| [`pev`](./plugins/pev/) | Plan-Execute-Validate agent workflow — Architect, Builder, Reviewer, Auditor, and Doc Reviewer subagents for structured code changes, with cortex integration. Includes `/pev-cycle` (full multi-agent workflow), `/pev-instance` (slim single-agent mode for small tasks), and `/pev-spike` (11-test integration smoke test). |
| [`hook-spike`](./plugins/hook-spike/) | Minimal plugin-hook test harness. Use when you suspect plugin hooks aren't firing or an env var isn't expanding. Includes `/hs-heartbeat` (smoke) and `/hook-spike` (4-agent matrix). |

## Install

```
/plugin marketplace add ddpoe/pev-agent-nexus
/plugin install pev@pev-agent-nexus
/plugin install hook-spike@pev-agent-nexus
```

## Customizing PEV per project

The `pev` plugin reads three optional project-level SOP files from `<project_root>/.pev/`:

| File | What it configures | Used by |
|---|---|---|
| `doc-topology.json` | Project doc taxonomy — categories, triggers, auditor-action per category, doc-reviewer-check | Auditor (proactive updates), Doc Reviewer (verification) |
| `test-policy.json` | Test tiers, annotation contract, coverage expectations | Architect, Builder, Reviewer |
| `review-criteria.json` | Project-specific code-review emphasis (logging, anti-patterns) | Reviewer |

All three are **DocJSON** so cortex can index them — add `.pev/` to your `cortex.toml` index paths if you want `cortex_search` / `cortex_history` over your SOPs.

If the files don't exist, the plugin uses its own defaults from `plugins/pev/templates/`. To customize, copy any template into your repo's `.pev/` directory and edit — the SOP files are git-tracked so worktrees pick them up automatically.

See §5.7 of [TROUBLESHOOTING.md](./plugins/hook-spike/TROUBLESHOOTING.md#57-project-sops--the-pev-convention) for the full convention.

## Two cycle shapes

| Command | When to use | Writes to |
|---|---|---|
| `/pev-cycle` | Full multi-agent workflow for non-trivial changes (new features, cross-cutting refactors, anything touching core mechanisms) — Architect + Builder + Reviewer + Auditor + Doc Reviewer, in an isolated worktree, with explicit human gates per phase. | `docs/pev/cycles/<id>.json` |
| `/pev-instance` | Slim single-agent mode for small, well-scoped tasks (docstring fixes, single-file bug fixes, small refactors). Mini-pitch → human gate → implement → self-review → checkin doc. Runs in the working tree, no worktree isolation. | `docs/pev/instances/<id>.json` |

Both cycle shapes share the same `.pev/` SOPs (test-policy, review-criteria, doc-review-guide) and the same search surface (`cortex_search` over `docs.pev.*`). `/pev-instance` escalates to `/pev-cycle` proactively if a task turns out to be bigger than scoped (touches core mechanisms per `cortex_workflow_list`, 4+ files, public API changes, etc.).

**Note on doc layout (v2.0.0):** Cycle manifests moved from `docs/pev-cycles/` to `docs/pev/cycles/` so full cycles and slim instances share a consistent tree. If you have pre-v2.0 cycle history, move `docs/pev-cycles/` → `docs/pev/cycles/` in each consumer repo.

## Debugging plugin hooks

When hooks misbehave, start with [`plugins/hook-spike/TROUBLESHOOTING.md`](./plugins/hook-spike/TROUBLESHOOTING.md) — symptom-first reference covering the full failure catalog (Windows cwd handling, jq path issues, grep locale bugs, matcher gotchas, etc.) from the v1.8.x debugging arc.
