---
name: git-sync
description: "Sync the workspace to the `workspace-sync` branch of the app repo: commit local changes, pull remote changes (rebase), and push. Use when: (1) the user asks to 'sync to git', 'pull from git', or 'save that'; (2) after a meaningful sequence of memory writes; (3) at natural end-of-session moments. Requires git sync to have been enabled at boot (i.e. `~/.openclaw/.git` exists)."
metadata:
  { "openclaw": { "emoji": "🔄", "requires": { "bins": ["git"] } } }
---

# git-sync

Push workspace changes to the `workspace-sync` branch of the app's git repo. If `~/.openclaw/.git` does not exist, report "git sync not configured" to the user and stop — the container was started without `WORKSPACE_GIT_TOKEN`.

Git operations run at `~/.openclaw/`, which is the working tree of `workspace-sync`.

Sync is bidirectional — it always pulls remote changes, and commits + pushes local ones when there are any. So this same flow handles both "save my work" and "pull what I pushed from my machine".

1. `cd ~/.openclaw`
2. `git add workspace/ openclaw.json skills/` — scope commits to agent state (`workspace/`), container config (`openclaw.json`), and the managed skills (`skills/`). Never stage other root-level files.
3. If there ARE staged changes (`git diff --cached --quiet` exits non-zero): `git commit -m "<semantic message describing what changed>"` — e.g. `"save notes on user's Python project"`, `"update SOUL.md per user feedback"`. If nothing is staged, skip the commit but **keep going** (a pure pull still needs the next step).
4. `git pull --rebase origin workspace-sync` — always; this brings down anything pushed from the user's machine.
5. `git push origin workspace-sync` — pushes your commit if you made one (a no-op if there's nothing new).
6. Report only if the user asked — give the commit subject, or say "already up to date" if nothing changed either way. When syncing automatically, stay silent.

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
