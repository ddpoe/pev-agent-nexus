# hook-spike

Minimal Claude Code plugin-hook test harness. Install this when plugin hooks aren't firing and you need to isolate which variable is broken.

## What it provides

**Driver skills:**

| Skill | Purpose |
|---|---|
| `/hs-heartbeat` | Single-agent smoke test — one Bash call, canary files + stderr messages. Does plugin `hooks.json` fire at all? |
| `/hook-spike` | Four-agent matrix across agent-frontmatter hooks (plugin-root vs project-dir), `hooks.json` control, and SubagentStop. Returns pass/fail table with env-var values. |

**Bonus:** the plugin's `hooks.json` dumps every hook's stdin JSON to `/tmp/hook-spike/input-<event>-<tool>.json`. Reuse these captures as realistic test inputs for debugging other plugins' hooks.

## When to reach for this

- A plugin hook seems silent — canary file missing, tool wasn't blocked
- You're about to add a new hook and want to confirm the pattern works in your env
- You need to see the raw hook-input JSON Claude Code passes (fields, shapes, encoding)

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) — symptom-first guide covering the full failure catalog (Windows cwd, jq path issues, grep locale, matcher gotchas, etc.) and architecture invariants for adding hooks.
