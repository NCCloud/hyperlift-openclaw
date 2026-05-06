# OpenClaw Hyperlift Template

A ready-to-deploy OpenClaw gateway template for [Spaceship Hyperlift](https://hyperlift.spaceship.com), with optional git-synced agent workspace so your agent's memory and personality survive across deploys and are editable from your own machine.

---

## What this is

A container you deploy to Hyperlift (or run locally via Docker Compose). On boot:

- **Agent gateway** — chat with the agent at port 3001.
- **Agent workspace** — standard OpenClaw workspace files (`AGENTS.md`, `SOUL.md`, `USER.md`, `TOOLS.md`, memory, skills) pre-seeded.
- **Optional git sync** — if you supply `WORKSPACE_GIT_URL` + `WORKSPACE_GIT_TOKEN`, the agent's workspace + config sync to a dedicated `workspace-sync` branch of your app's GitHub repo. Without these, the container runs in local-only mode.
- **`git-sync` skill** — the agent commits and pushes workspace changes on demand (`"sync to git"`) or at natural breakpoints.

---

## Quick start (local)

```bash
cp .env.example .env
# Edit .env — set OPENCLAW_GATEWAY_PASSWORD and at least one provider key
docker compose up -d --build
# Chat UI: http://localhost:$OPENCLAW_PORT
```

Common operations:

```bash
docker compose up -d --force-recreate   # pick up .env changes
docker compose down -v                   # wipe state and start over
docker compose logs -f openclaw          # tail gateway logs
```

---

## Enable git sync (optional)

1. **Create a fine-grained PAT** at <https://github.com/settings/tokens?type=beta>: scope to a single repo (the one this app deploys from), Contents: read+write, ~90 day expiry.
2. **Set env vars** in `.env`:
   ```
   WORKSPACE_GIT_URL=https://github.com/<you>/<repo>.git   # HTTPS form
   WORKSPACE_GIT_TOKEN=<the PAT>
   ```
3. **Restart**: `docker compose up -d --force-recreate`. On first boot in sync mode, init.sh clones `workspace-sync` from your repo (creates the branch from `main` + initial seed if it doesn't exist yet).

The agent's recognized commands once sync is on: `"sync to git now"`, `"pull from git"`, `"enable periodic git backup"`, `"disable git sync"`.

---

## What's tracked vs untracked

After sync setup, `~/.openclaw/` inside the container is the working tree of the `workspace-sync` branch:

```
~/.openclaw/
├── .git/                ← clone of workspace-sync
├── .gitignore           ← allowlist (see below)
├── workspace/           ← TRACKED, agent writes here
├── openclaw.json        ← TRACKED, control UI writes here
├── Dockerfile, init.sh, seed/, …  ← TRACKED, inherited from main, INERT at runtime
├── credentials/         ← UNTRACKED, runtime state, gitignored
├── agents/              ← UNTRACKED, sessions, gitignored
└── cron/                ← UNTRACKED, scheduled jobs, gitignored
```

**The `.gitignore` is an allowlist:**

```gitignore
/*
!/.gitignore
!/workspace
!/openclaw.json
```

It ignores everything at the root by default and explicitly un-ignores the three paths we want tracked. Two important nuances:

- **Gitignore only affects untracked files.** Inherited main files (Dockerfile, init.sh, etc.) were tracked when the branch was created; they stay tracked. They never change at runtime, so they don't appear in `git status` — they just sit there inert.
- **The agent's `git-sync` skill stages explicit paths** (`git add workspace/ openclaw.json`), never `-A` or `.`. The gitignore is defense-in-depth against accidental adds.

So in practice: the agent only ever commits changes to `workspace/` and `openclaw.json`. Runtime state (channel OAuth tokens, sessions, cron) stays local-only, gitignored, never committed.

---

## Editing the workspace from your machine

```bash
git clone <your-repo-url> my-app
cd my-app
git checkout workspace-sync     # or: git worktree add ../ws workspace-sync
# edit workspace/SOUL.md or wherever
git add workspace/ && git commit -m "tweak personality"
git push
```

Tell the agent `"pull from git"` (or just `"sync"`) and it'll pick up your changes.
If there was a conflict, agent's local changes will be backed up in a separate branch for inspection/manual recovery.

---

## Troubleshooting

**Sync setup fails / "missing config" / agent can't sync.** Check container logs (`docker compose logs openclaw | head -30`). Most common: PAT expired, wrong URL form (must be HTTPS not SSH), or the PAT doesn't have Contents: read+write. Init.sh probes the remote with `git ls-remote` before touching state, so on failure it falls back to local-only mode without disrupting anything.

**Restart didn't pick up `.env` changes.** `docker compose restart` doesn't reload env. Use `docker compose up -d --force-recreate` instead.

**Agent thinks sync is off after I added the token.** The `sync-status-inject` workspace hook injects the live state into AGENTS.md on every agent turn. After your next message the agent should see `<!-- ... ON -->` in its system prompt. If it doesn't, verify `~/.openclaw/.git` exists in the container: `docker compose exec openclaw ls -la /home/node/.openclaw/`.

**What happens to my local-only state when I enable sync?** Init.sh handles it automatically based on whether the `workspace-sync` branch exists yet on the remote:
- **Branch missing** (first-ever sync): your local `workspace/` and `openclaw.json` become the initial commit of the new `workspace-sync` branch.
- **Branch exists** (re-sync, or branch was created elsewhere): your local state is pushed to a timestamped `local-backup-<ts>` branch on the remote, then the canonical `workspace-sync` is cloned. Inspect/merge from `local-backup-<ts>` via the GitHub UI.

In both cases, runtime state (channel OAuth tokens, sessions, cron) is restored automatically. No exec access required.

**Backup branches piling up.** Two kinds:
- `local-backup-<ts>` — created once when you transition from local-only to sync (described above).
- `backup/<ts>` — created by the `git-sync` skill on rebase conflicts during normal sync.

Inspect on GitHub, cherry-pick what you want, delete the branches when done.

---

## Architecture overview

```
Hyperlift / docker compose builds image FROM main branch
  │
  ▼
Container starts
  │
  ▼
init.sh (ENTRYPOINT)
  ├─ if WORKSPACE_GIT_TOKEN+URL set:
  │    setup_credentials → setup_sync → sync_ok=1
  │    branch exists on remote? → push local to local-backup-<ts>, then clone workspace-sync
  │    branch missing?           → clone default branch, create workspace-sync from local (or seed)
  └─ else: seed_local_only (cp /app/seed/* into ~/.openclaw/)
  │
  ▼
exec openclaw gateway run    ← gateway becomes PID 1
  │
  ▼
On every agent turn: sync-status-inject hook injects current sync state into AGENTS.md
  │
  ▼
Agent runs git-sync skill at natural breakpoints or on user request
   → cd ~/.openclaw && git add workspace/ openclaw.json && commit && pull --rebase && push
```

Two branches live in your repo:

- **`main`** — Dockerfile, init.sh, seed/, docker-compose.yml. What Hyperlift builds from. Stays clean.
- **`workspace-sync`** — branched from main; the agent's writable home. Carries `workspace/` (memory, AGENTS.md edits, skills) and `openclaw.json` (gateway config) on top of main's content.
