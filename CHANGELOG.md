# Changelog

All notable changes to the `pev-agent-nexus` marketplace. Entries are per-version of the `pev` plugin; marketplace-only releases (no plugin change) are rare.

Versions loosely follow [Semantic Versioning](https://semver.org/) — major bumps mark breaking changes in doc layout or required consumer migration; minor bumps add features; patch bumps are fixes or docs.

## [Unreleased]

Nothing pending.

## [2.1.3] — 2026-04-21

### Fixed
- `pev-doc-reviewer.md` was not registered in `plugins/pev/.claude-plugin/plugin.json`'s `agents` array, so Claude Code never loaded it. Any `/pev-cycle` that reached Phase 7.5 (Doc Review) failed with `Agent type 'pev:pev-doc-reviewer' not found`. Added to the manifest.
- `pev-doc-scope.sh` blocked the Auditor from writing to live feature docs during Phase 7 (Audit), contradicting the Auditor's documented role in `DESIGN.md` ("Doc-write on live feature docs but no code-write"). The hook now exempts `pev:pev-auditor` from the cycle-manifest-only scope; Architect, Builder, Reviewer, and Doc Reviewer remain scoped.

## [2.1.0] — 2026-04-21

### Added
- Project SOPs are now DocJSON (`.json` instead of `.md`) so cortex can index them when a project adds `.pev` to `doc_dirs` under `[cortex.scan]` in `cortex.toml`. LLM agents parse JSON fine; content fields remain markdown (#15).
- `doc-topology.json` schema gains `Auditor action` field — the Auditor now reads the topology and proactively updates guide-listed doc categories during post-implementation. Boundary shifts from "Auditor = graph-only" to "Auditor = graph + guide-listed." Doc Reviewer stays as verifier + gap catcher (#15).

### Changed
- `.pev/doc-review-guide.md` → `.pev/doc-topology.json` (rename reflects cross-agent usage).
- `.pev/test-policy.md` → `.pev/test-policy.json`.
- `.pev/review-criteria.md` → `.pev/review-criteria.json`.
- Stale `${CLAUDE_PROJECT_DIR}/.claude/templates/` path in Auditor skill corrected to `${CLAUDE_PLUGIN_ROOT}/templates/`.

### Migration
Consumers with existing `.pev/` files port content by copying the structure from `${CLAUDE_PLUGIN_ROOT}/templates/<name>.json` and pasting customizations into the matching sections.

Step-by-step commands in [`plugins/pev/SETUP.md`](./plugins/pev/SETUP.md#20x--210) §Migration (2.0.x → 2.1.0+).

## [2.0.0] — 2026-04-21

### Added
- New `/pev-instance` skill — slim single-agent cycle for small tasks. Mini-pitch → human gate → implement → structured self-review → checkin doc at `docs/pev/instances/<id>.json`. Escalates proactively to `/pev-cycle` when scope outgrows (#14).
- Reviewer Pass 5d — forward-looking workflow taxonomy hygiene. Flags new core-mechanism candidates, marker extensions, and split candidates. Severity always `minor`/`suggestion`, never blocks merge (#14).
- `cortex_workflow_list(steps=true)` framed as authoritative "developer-declared core mechanisms" signal, used consistently across Reviewer Pass 3/4/5c and `/pev-instance` escalation (#14).

### Changed — BREAKING
- Cycle docs relocated from `docs/pev-cycles/` → `docs/pev/cycles/`. Cortex doc IDs: `docs.pev-cycles.*` → `docs.pev.cycles.*`.

### Migration
```bash
mv docs/pev-cycles docs/pev/cycles
cortex build   # re-index at new paths
```

Full migration in [`plugins/pev/SETUP.md`](./plugins/pev/SETUP.md#pre-200--any-2x) §Migration (Pre-2.0.0 → any 2.x).

## [1.9.1] — 2026-04-21

### Removed
- Per-invocation diagnostic `echo >> /tmp/pev-hook-debug.log` lines from all 7 PEV hooks (added in v1.8.2 as temporary instrumentation during shakedown). Hooks are stable; the log was steady-state noise (#13).

### Changed
- Debug-tracing recipe moved to `plugins/hook-spike/TROUBLESHOOTING.md` §8.3 with per-hook-type insertion instructions. Use it when a hook seems silent; remove before committing.

## [1.9.0] — 2026-04-21

### Added
- `.pev/` project SOP convention — three DocJSON (originally markdown, converted in 2.1.0) files consumers create to customize PEV per project: `doc-topology.json` (Doc Reviewer taxonomy), `test-policy.json` (test tiers and annotation contract), `review-criteria.json` (Reviewer emphasis). Skills read project SOP first, fall back to plugin-shipped templates (#12).
- Doc Reviewer mandate rewritten as "drift scanner for non-graph docs," scoped to scan + verify using the project's topology.

## [1.8.6] — 2026-04-21

### Fixed
- Stale `${CLAUDE_PROJECT_DIR}/.claude/templates/` reference in Architect skill corrected to `${CLAUDE_PLUGIN_ROOT}/templates/` (#11).
- "As a developer" hardcoded in Architect user-stories loosened to "As a [user type]" with guidance to pick the persona who benefits most directly.
- Orchestrator pitch display (Phase 3 "Approve Plan") now always shows the test plan table alongside scope/user-stories/solution-sketch/constraints.

## [1.8.5] — 2026-04-21

### Fixed
- `grep -oP` in `pev-bash-scope.sh` fails silently on systems without UTF-8 locale (the hook execution environment on Windows git-bash hits this). Replaced with POSIX `sed` (#8).
- `pev-cortex-scope.sh` matcher `"mcp__cortex__"` never fired — Claude Code matchers require full-string regex match. Changed to `"mcp__cortex__.*"` (#8).

## [1.8.4] — 2026-04-21

### Fixed
- `pev-bash-scope.sh` block path now uses `echo "reason" >&2; exit 2` instead of emitting `hookSpecificOutput` JSON on stdout — the JSON-only approach did not reliably trigger a block (#7).
- Added diagnostic logging to `pev-cortex-scope.sh` around its comparison to enable tracing (later removed in 1.9.1).

## [1.8.3] — 2026-04-21

### Fixed
- Native Windows jq cannot open POSIX paths (`/c/Users/...`). Scope hooks silently returned empty from `jq -r '...' "$STATE_FILE"`, causing all gates to fall through. Changed to `cat "$STATE_FILE" | jq -r '...'` so jq reads stdin and doesn't care about path format (#6).

## [1.8.2] — 2026-04-21

### Added
- Temporary diagnostic `echo >> /tmp/pev-hook-debug.log` line at the top of every PEV hook (before the `agent_type` gate) to observe invocations during the shakedown (#5). Later removed in 1.9.1.

## [1.8.1] — 2026-04-21

### Fixed
- Hook scripts silently fell open on Windows because `cwd` in stdin JSON is a Windows path (`C:\...\worktree`) and `[ -f "$cwd/.pev-state.json" ]` with mixed slashes returned false. Added `cygpath -u` normalization on `PROJECT_ROOT` in every scope hook (#4).

## [1.8.0] — 2026-04-21

### Changed — BREAKING (within PEV, consumer config preserved)
- All PEV hooks migrated from agent-frontmatter `hooks:` blocks into the plugin's `hooks.json`. Per-agent behavior (budgets, allowlists) now dispatched inside hook scripts on `agent_type` from stdin JSON. Agent-frontmatter hooks silently no-op in marketplace installs (proved in the hook-spike matrix); this PR made PEV actually work in plugin installs (#3).
- `.pev-state.json` schema simplified: `counter_file` field removed (counter now keyed on `agent_id` from hook input). Per-phase state updates by the orchestrator eliminated.

### Added
- `pev-subagent-stop.sh` — unified SubagentStop hook, replaces per-agent stop hooks. Cleans up counter files universally, runs `cortex build` on worktree when the Builder returns.

### Removed
- All 6 agent frontmatter `hooks:` blocks (architect, auditor, builder, doc-reviewer, reviewer, spike). The blocks don't fire in plugin installs — their behavior is now in shared scripts dispatched on `agent_type`.

## Earlier (pre-v1.8.0)

Historical versions predate the hook-shakedown arc. Pre-v1.8.0 plugin installs did not run hooks at all (discovered empirically in v1.8.x). Retained in the installed_plugins cache as orphans pending cleanup; not documented here because their hook behavior was effectively no-op.
