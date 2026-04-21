# pev-agent-nexus

Claude Code plugin marketplace. Two plugins:

| Plugin | Purpose |
|---|---|
| [`pev`](./plugins/pev/) | Plan-Execute-Validate agent workflow for structured code changes — Architect, Builder, Reviewer, Auditor, and Doc Reviewer subagents with cortex integration. Includes `/pev-cycle` (full multi-agent workflow), `/pev-instance` (slim single-agent mode), and `/pev-spike` (infrastructure smoke test). |
| [`hook-spike`](./plugins/hook-spike/) | Minimal plugin-hook test harness. Install when debugging plugin hooks that silently fail. |

## Install

```
/plugin marketplace add ddpoe/pev-agent-nexus
/plugin install pev@pev-agent-nexus
/plugin install hook-spike@pev-agent-nexus
```

For the full setup including directory creation, SOP templates, and per-version migration steps, see [`plugins/pev/SETUP.md`](./plugins/pev/SETUP.md).

## Where to go next

- **Setting up PEV in a consumer project** → [`plugins/pev/SETUP.md`](./plugins/pev/SETUP.md)
- **Using PEV in your project** → [`plugins/pev/USER_GUIDE.md`](./plugins/pev/USER_GUIDE.md)
- **Modifying PEV** → [`plugins/pev/DESIGN.md`](./plugins/pev/DESIGN.md)
- **Debugging plugin hooks** → [`plugins/hook-spike/TROUBLESHOOTING.md`](./plugins/hook-spike/TROUBLESHOOTING.md)
- **Release history** → [`CHANGELOG.md`](./CHANGELOG.md)
- **Working ON this marketplace** (extending the plugins, authoring PRs) → [`AGENTS.md`](./AGENTS.md)
