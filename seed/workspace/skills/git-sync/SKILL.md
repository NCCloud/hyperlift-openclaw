---
name: git-sync
description: "Commit and push workspace changes to the `workspace-sync` branch of the app repo with a semantic message. Use when: (1) user asks 'sync to git' or similar, (2) at the end of a meaningful sequence of memory writes, (3) at natural end-of-session moments. Requires WORKSPACE_GIT_TOKEN to have been configured at container boot."
metadata:
  { "openclaw": { "emoji": "🔄", "requires": { "bins": ["git"] } } }
---

# git-sync

Push workspace changes to the `workspace-sync` branch of the app's git repo. If `~/.openclaw/.git` does not exist, report "git sync not configured" to the user and stop — the container was started without `WORKSPACE_GIT_TOKEN`.

Git operations run at `~/.openclaw/`, which is the working tree of `workspace-sync`.

## Normal flow

1. `cd ~/.openclaw`
2. `git add workspace/ openclaw.json` — scope commits to agent state (`workspace/`) and container config (`openclaw.json`). Never stage other root-level files.
3. If `git diff --cached --quiet` exits 0 (no staged changes): report "nothing to sync" and stop.
4. `git commit -m "<semantic message describing what changed>"` — e.g. `"save notes on user's Python project"`, `"update SOUL.md per user feedback"`, `"end-of-session memory flush"`.
5. `git pull --rebase origin workspace-sync` — pull any remote changes (the user may have pushed from their machine).
6. `git push origin workspace-sync`
7. Report success to the user with the commit subject. Only report that you synced if the user asked for it. When syncing automatically, don't report anything.

## If `pull --rebase` fails (rebase conflict)

Preserve the divergent work on a backup branch, then reset `workspace-sync` to upstream. **Order matters**: abort the rebase first so `workspace-sync` is restored to your commit, then back it up, then reset.

```sh
ts=$(date -u +%Y%m%dT%H%M%SZ)
git rebase --abort 2>/dev/null || true       # restore workspace-sync to our local commit
git branch "backup/$ts"                       # backup at workspace-sync's tip (our commit)
git push origin "backup/$ts"                  # publish the backup branch
git reset --hard origin/workspace-sync        # adopt the remote tip
```

Why this order: during a conflicted rebase, `HEAD` is detached at the partial-rebase state and the `workspace-sync` branch ref still points at our commit. `git branch backup/$ts` creates the branch at `HEAD`, so without aborting first you'd back up the partial-rebase mess instead of our actual commit.

After this block, the working tree matches the remote and there's nothing left to commit. Don't retry the steps above — your work is already preserved on the backup branch. Tell the user:

> *"I couldn't merge cleanly, so your local changes are preserved on branch `backup/<ts>` on the remote. `workspace-sync` is now in sync with upstream."*

## If `push` fails (non-fast-forward)

Upstream moved while we were working. Run `git pull --rebase origin workspace-sync` and retry `git push origin workspace-sync`. If it fails again, apply the conflict-recovery block above.

## If git commands fail for auth reasons

Report *"git auth failure — the PAT may have expired or been revoked"* and stop. Do not retry.
