---
title: "Git Sync — workspace supplement"
summary: "Behavioral rules for the git-sync workflow. Loaded into context alongside the default AGENTS.md via the bootstrap-extra-files hook."
read_when:
  - Deciding whether or when to sync the workspace
  - The user asks about git sync, backups, or pulling changes
---

# Git Sync

This workspace can sync to the `workspace-sync` branch of the app's GitHub repo via the `git-sync` skill. A runtime-state marker is injected at the top of your `AGENTS.md` context on every turn — the `sync-status-inject` hook runs on each `agent:bootstrap` event — as a line of the form `<!-- Runtime state (auto-injected): git sync is currently ON -->` (or `OFF`). Trust that marker as the live, filesystem-derived truth for whether sync is active.

## Behavior

- **Trust the injected runtime-state marker for sync status.** The `sync-status-inject` hook prepends it on every `agent:bootstrap` event (i.e. every turn). Read it and rely on it instead of stale conclusions from earlier in the conversation — it can be turned ON at any time (e.g. the user added a token and restarted), even if it was OFF earlier in the same conversation.
- **Sync is bidirectional.** `git-sync` commits your local changes, then runs `git pull --rebase` — so running sync also pulls down any commits the user pushed from their machine to `workspace-sync`. Sync = upload AND download in one go.
- **Sync silently.** Use `git-sync` at natural breakpoints — end of a session, after meaningful memory or config writes, when the user has given you something worth preserving. Not too often.
- **Don't announce auto-syncs.** No "I've saved your changes" chatter for syncs you decided on your own.
- **Surface sync activity only when:**
  - The user explicitly asked ("sync now", "save that", etc.) — confirm with the commit subject.
  - Something went wrong (rebase conflict → report the backup branch; auth failure → report the PAT is invalid).

### First-time sync intro (once, ever)

The FIRST time you see the runtime-state marker as `ON` AND neither `MEMORY.md` nor recent `memory/YYYY-MM-DD.md` contains the line `gave sync intro`, weave into your next reply a brief note that 🔄 git sync is active and suggest a couple of follow-up questions the user can ask to learn more about how it works. Keep it short — just an opening; the user will ask what they want to know, and you have the full details below.

After delivering the intro, record a line like `2026-04-24 — gave sync intro` in `MEMORY.md` (or today's `memory/YYYY-MM-DD.md` if MEMORY.md isn't active). On future turns, if that line is present, do not repeat the intro.

(The `OFF`-state nudge for brand-new workspaces lives in `BOOTSTRAP.md` and fires only during first-run setup; this `ON` intro is its steady-state counterpart.)

### Pulling changes the user pushed from their machine

Because sync is bidirectional, if the user edited files in their local clone of `workspace-sync`, committed, and pushed, those changes only land in the running container when a sync happens.

- If the user says *"I edited SOUL.md locally, can you pick it up?"* / *"pull from git"* → invoke `git-sync`. The `git pull --rebase` step brings their changes into the local tree.
- **Startup-context files** (AGENTS.md, SOUL.md, USER.md, TOOLS.md, HEARTBEAT.md) are re-read and re-injected on **every turn**, so a pulled change to one of them is picked up automatically on your **next turn** — no need to wait for a new session.
- Memory files (`memory/YYYY-MM-DD.md`, `MEMORY.md`) you read on demand anyway, so edits to those show up as soon as you read them.

### Recognized user asks

- **"sync to git now"** / **"save that"** → invoke the `git-sync` skill immediately with a semantic commit message. Remember this also pulls any remote changes the user may have pushed.
- **"pull my changes from git"** / **"I pushed something from my machine"** → invoke `git-sync` — the pull-rebase step picks up their commits; any changed startup files (AGENTS.md etc.) re-load on your next turn.
- **"enable periodic git backup"** → offer to add an OpenClaw cron job that runs `git-sync` every 6 hours:
  `openclaw cron add --name "git-sync" --every 6h --session isolated --tools exec --message "run the git-sync skill"`
  Flag the LLM cost; only enable on explicit request. (You sync automatically at natural breakpoints anyway unless the user tells you not to.)
- **"disable git sync"** → removing `WORKSPACE_GIT_TOKEN` alone does **not** stop sync on a running deployment: the git repo and stored credentials persist on the volume, so I'd keep syncing. To actually stop, the user should revoke the PAT on GitHub (my pushes then fail) or wipe the deployment's volume to start fresh.
- **"how do I set up sync" / "how do I create the PAT"** → read `sync/SETUP.md` and walk them through the steps there.

### Backup branches the user might ask about

Two kinds of backup branches may appear on the remote:

- **`backup/<timestamp>`** — created by `git-sync` when a rebase conflicts. Divergent `workspace-sync` state that couldn't merge cleanly.
- **`local-backup-<timestamp>`** — created by init.sh when the container booted in local-only mode (agent wrote local memory), then restarted with sync enabled while the remote `workspace-sync` already had its own history. Preserves the local-only work so nothing is silently lost. Main `workspace-sync` continues with the remote's prior state.

If the user asks about them, explain which kind they are and that they can be inspected, cherry-picked from, or deleted at leisure.

### Conflict handling

If `git-sync` fails, follow the recovery steps in `skills/git-sync/SKILL.md`. Never force-push `workspace-sync`. Always preserve divergent work on a `backup/<timestamp>` branch.

### Security

`openclaw.json` is tracked at the repo root on `workspace-sync`. **Never store API keys, OAuth tokens, or other secrets in openclaw.json via the control UI** — they'll end up in git history. Direct users to Hyperlift env vars (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) instead. Warn them if you see them about to paste a key into the config editor.
