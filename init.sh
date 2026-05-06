#!/usr/bin/env sh
set -eu

STATE_DIR="/home/node/.openclaw"
PRE_SYNC="/home/node/.openclaw-pre-sync"
SEED_CONFIG="/app/seed/openclaw.default.json"
SEED_WORKSPACE="/app/seed/workspace"
SEED_GITIGNORE="/app/seed/workspace-sync.gitignore"

# ───── helpers ─────────────────────────────────────────────────────────

# Configure git to authenticate over HTTPS with the user's PAT.
setup_credentials() {
  git config --global user.name "openclaw-agent"
  git config --global user.email "agent@openclaw.local"
  git config --global credential.helper store
  printf 'https://x-access-token:%s@github.com\n' "$WORKSPACE_GIT_TOKEN" > ~/.git-credentials
  chmod 600 ~/.git-credentials
}

# First-sync transition: move pre-existing local-only state aside so STATE_DIR
# is empty for git clone. PRE_SYNC must live on the same persistent volume.
stash_existing_state() {
  if [ -n "$(ls -A . 2>/dev/null)" ]; then
    mkdir -p "$PRE_SYNC"
    find . -mindepth 1 -maxdepth 1 -exec mv {} "$PRE_SYNC/" \;
  fi
}

# After successful clone: restore runtime state (credentials/, agents/, cron/)
# to STATE_DIR. Skip workspace + openclaw.json — clone is canonical for those,
# and any local workspace state is preserved on a remote backup branch already.
restore_stashed_runtime_state() {
  [ -d "$PRE_SYNC" ] || return 0
  for item in "$PRE_SYNC"/*; do
    [ -e "$item" ] || continue
    name=$(basename "$item")
    case "$name" in
      workspace|openclaw.json) ;;
      *) mv "$item" "./$name" ;;
    esac
  done
  rm -rf "$PRE_SYNC"
}

# Failure path: clone didn't succeed. Put everything back verbatim and nuke
# any partial .git so the next boot can retry from a clean slate.
restore_stashed_state_full() {
  rm -rf .git
  [ -d "$PRE_SYNC" ] || return 0
  find "$PRE_SYNC" -mindepth 1 -maxdepth 1 -exec mv {} ./ \;
  rm -rf "$PRE_SYNC"
}

# Branch-exists path: snapshot stashed local workspace + openclaw.json to a
# timestamped local-backup-<ts> branch on the remote so the user can recover
# via the GitHub UI without exec access. Excludes runtime state by selecting
# only those two paths. No-op if there's nothing local to back up.
push_local_to_backup_branch() {
  if [ ! -d "$PRE_SYNC/workspace" ] && [ ! -f "$PRE_SYNC/openclaw.json" ]; then
    return 0
  fi
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  tmp="/tmp/openclaw-backup-$$"
  mkdir -p "$tmp"
  [ -d "$PRE_SYNC/workspace"     ] && cp -r "$PRE_SYNC/workspace"     "$tmp/workspace"
  [ -f "$PRE_SYNC/openclaw.json" ] && cp    "$PRE_SYNC/openclaw.json" "$tmp/openclaw.json"
  rc=0
  (
    cd "$tmp"
    git init -q -b "local-backup-$ts"
    git remote add origin "$WORKSPACE_GIT_URL"
    [ -d workspace     ] && git add workspace
    [ -f openclaw.json ] && git add openclaw.json
    git diff --cached --quiet && exit 0
    git commit -q -m "local state before sync ($ts)"
    git push -q -u origin "local-backup-$ts"
  ) || rc=$?
  rm -rf "$tmp"
  return $rc
}

# Branch-exists path: clone the canonical workspace-sync from the remote.
clone_workspace_sync() {
  git clone -b workspace-sync --single-branch "$WORKSPACE_GIT_URL" . 2>/dev/null
}

# Branch-missing path: clone the default branch, then create workspace-sync
# from stashed local state (or seed if no local state). Local IS canonical
# here since there's no remote workspace-sync to preserve.
create_workspace_sync() {
  git clone "$WORKSPACE_GIT_URL" . 2>/dev/null || return 1
  git checkout -q -b workspace-sync
  cp "$SEED_GITIGNORE" .gitignore
  if [ -f "$PRE_SYNC/openclaw.json" ]; then
    mv "$PRE_SYNC/openclaw.json" openclaw.json
  else
    cp "$SEED_CONFIG" openclaw.json
  fi
  if [ -d "$PRE_SYNC/workspace" ]; then
    mv "$PRE_SYNC/workspace" workspace
  else
    cp -r "$SEED_WORKSPACE" workspace
  fi
  git add .gitignore workspace openclaw.json
  git commit -q -m "bootstrap workspace-sync"
  git push   -q -u origin workspace-sync
}

# Top-level sync orchestrator: short-circuits if .git already exists, probes
# the remote with a single ls-remote call to distinguish branch-exists vs
# branch-missing vs unreachable, and unwinds on any failure.
setup_sync() {
  cd "$STATE_DIR"
  if [ -d .git ]; then
    [ "$(git remote get-url origin 2>/dev/null)" = "$WORKSPACE_GIT_URL" ] \
      || git remote set-url origin "$WORKSPACE_GIT_URL"
    return 0
  fi
  # 0 = workspace-sync exists, 2 = doesn't exist, other = unreachable.
  git ls-remote --exit-code --quiet "$WORKSPACE_GIT_URL" workspace-sync >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    return 1
  fi
  stash_existing_state
  if [ "$rc" -eq 0 ]; then
    if ! push_local_to_backup_branch; then
      restore_stashed_state_full
      return 1
    fi
    if ! clone_workspace_sync; then
      restore_stashed_state_full
      return 1
    fi
  else
    if ! create_workspace_sync; then
      restore_stashed_state_full
      return 1
    fi
  fi
  restore_stashed_runtime_state
}

# Sync-disabled fallback: gateway still needs workspace/ and openclaw.json
# to boot, so seed them from /app/seed/ if they're missing.
seed_local_only() {
  cd "$STATE_DIR"
  [ -f openclaw.json ] || cp    "$SEED_CONFIG"    openclaw.json
  [ -d workspace    ] || cp -r "$SEED_WORKSPACE" workspace
}

# ───── main ────────────────────────────────────────────────────────────

sync_ok=0

if [ -n "${WORKSPACE_GIT_TOKEN:-}" ] && [ -n "${WORKSPACE_GIT_URL:-}" ]; then
  setup_credentials
  if setup_sync; then
    sync_ok=1
  else
    rm -f ~/.git-credentials
    echo "init.sh: sync setup failed (check WORKSPACE_GIT_URL and WORKSPACE_GIT_TOKEN); falling back to local-only" >&2
  fi
  unset WORKSPACE_GIT_TOKEN
fi

[ "$sync_ok" -eq 0 ] && seed_local_only

exec "$@"
