# pev-agent-nexus

Claude Code plugin marketplace with two plugins:

| Plugin | Purpose |
|---|---|
| [`pev`](./plugins/pev/) | Plan-Execute-Validate agent workflow — Architect, Builder, Reviewer, Auditor, and Doc Reviewer subagents for structured code changes, with cortex integration. Includes `/pev-cycle` (real workflow) and `/pev-spike` (11-test integration smoke test). |
| [`hook-spike`](./plugins/hook-spike/) | Minimal plugin-hook test harness. Use when you suspect plugin hooks aren't firing or an env var isn't expanding. Includes `/hs-heartbeat` (smoke) and `/hook-spike` (4-agent matrix). |

## Install

```
/plugin marketplace add ddpoe/pev-agent-nexus
/plugin install pev@pev-agent-nexus
/plugin install hook-spike@pev-agent-nexus
```

## Customizing PEV per project

The `pev` plugin reads three optional project-level SOP files from `<project_root>/.pev/`:

| File | What it configures |
|---|---|
| `doc-review-guide.md` | Doc Reviewer's taxonomy of doc categories + review triggers |
| `test-policy.md` | Test tiers, annotation contract, coverage expectations |
| `review-criteria.md` | Project-specific code-review emphasis (logging, anti-patterns) |

If the files don't exist, the plugin uses its own defaults from `plugins/pev/templates/`. To customize, copy any template into your repo's `.pev/` directory and edit — the SOP files are git-tracked so worktrees pick them up automatically.

See §5.7 of [TROUBLESHOOTING.md](./plugins/hook-spike/TROUBLESHOOTING.md#57-project-sops--the-pev-convention) for the full convention.

## Debugging plugin hooks

When hooks misbehave, start with [`plugins/hook-spike/TROUBLESHOOTING.md`](./plugins/hook-spike/TROUBLESHOOTING.md) — symptom-first reference covering the full failure catalog (Windows cwd handling, jq path issues, grep locale bugs, matcher gotchas, etc.) from the v1.8.x debugging arc.
