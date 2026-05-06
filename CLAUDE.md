# CLAUDE.md

OpenClaw gateway template built for dev purposes to be run via docker. When `WORKSPACE_GIT_TOKEN` and `WORKSPACE_GIT_URL` are set, the agent's workspace + `openclaw.json` sync to a `workspace-sync` branch on the same repo. No token = local-only mode, container still boots.
Find openclaw docs at https://docs.openclaw.ai/

Two branches:
- `main` — Dockerfile, init.sh, seed/, docker-compose.yml. What Hyperlift builds from.
- `workspace-sync` — branched from main; carries main's content + `workspace/` + `openclaw.json` + `.gitignore` (allowlist) at root.

## Layout at runtime

`~/.openclaw/` IS the git working tree of `workspace-sync`. No symlinks, no subdirs.

```
~/.openclaw/
├── .git/                                clone of workspace-sync
├── .gitignore                           allowlist (/* + !/.gitignore + !/workspace + !/openclaw.json)
├── workspace/                           tracked, agent writes here
├── openclaw.json                        tracked, control UI writes here
├── Dockerfile, init.sh, seed/, …        tracked, inherited from main, INERT at runtime
├── credentials/, agents/, cron/         untracked, openclaw runtime state
```

The skill stages explicit paths only (`git add workspace/ openclaw.json`), never `-A`. The `.gitignore` is defense-in-depth.

## Key files

| Path | Role |
|---|---|
| `init.sh` | ENTRYPOINT. Single `git ls-remote --exit-code workspace-sync` probe distinguishes branch-exists / branch-missing / unreachable. Stashes pre-existing state into sibling `~/.openclaw-pre-sync/`. **Branch missing**: clones default branch, creates `workspace-sync` from local state (or seed if no local). **Branch exists**: pushes local to `local-backup-<ts>` branch first, then clones canonical `workspace-sync`. Falls back to local-only on any failure. PRE_SYNC must be on the same persistent volume as STATE_DIR — keep `/home/node` mounted whole. |
| `seed/openclaw.default.json` | Gateway config seed |
| `seed/workspace-sync.gitignore` | Allowlist pushed to workspace-sync root |
| `seed/workspace/AGENTS.md` | Agent operating rules + sync-related guidance |
| `seed/workspace/skills/git-sync/SKILL.md` | Order: `add → commit → pull --rebase → push`. On rebase fail: `rebase --abort` first, then `git branch backup/<ts>`, push, hard-reset. |
| `seed/workspace/hooks/sync-status-inject/{HOOK.md, handler.js}` | `agent:bootstrap` hook. Detects `~/.openclaw/.git`, prepends a runtime-state comment to AGENTS.md. ~15 tokens/turn. |
| `BOOT-SCENARIOS.md` | All 9 boot paths init.sh handles + mermaid decision tree. Read this when reasoning about transitions. |
| `/Users/cssimon/.claude/plans/scalable-wishing-sky.md` | Plan file — read this when in doubt. |

## init.sh flow

```
if WORKSPACE_GIT_TOKEN+URL set:
  setup_credentials
  setup_sync:
    .git exists?    → update remote URL if changed; done.
    branch exists?  → stash → push local to local-backup-<ts> → clone workspace-sync → restore runtime.
    branch missing? → stash → clone default branch → seed workspace-sync from local (or seed) → push.
    on failure: restore_full, fall through to local-only.
else / on failure:
  seed_local_only (cp seed/* if missing)
exec gateway
```

Per-resource gates (no `.initialized` marker). Idempotent across reboots.

## What NOT to do

- **No symlinks** at `~/.openclaw/workspace` or `openclaw.json`. Atomic writes (control UI saving config) replace symlinks with regular files, breaking sync.
- **Don't reorder the skill** to `pull → add → commit → push`. Autostash-pop data-loss path. Current order is `add → commit → pull → push`.
- **No `git add -A` / `.`** in init.sh, scripts, or the skill. Always explicit paths.
- **No debug `console.log` or `/tmp/` writes** in shipped code.