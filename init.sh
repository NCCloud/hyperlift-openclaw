#!/usr/bin/env bash
#
# Container entrypoint: prepare the OpenClaw state dir — optionally syncing it to a
# `workspace-sync` git branch when WORKSPACE_GIT_TOKEN + WORKSPACE_GIT_URL are set —
# then exec the gateway. Keep OPENCLAW_STATE_DIR under /home/node (the persistent
# volume) so state survives restarts.

set -uo pipefail

STATE_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
SEED_CONFIG="/app/seed/openclaw.default.json"
SEED_WORKSPACE="/app/seed/workspace"
SEED_GITIGNORE="/app/seed/workspace-sync.gitignore"
SEED_SKILLS="/app/seed/skills"

log()  { printf 'init: %s\n'          "$*" >&2; }
warn() { printf 'init: WARNING: %s\n' "$*" >&2; }

have_sync_env() {
  [ -n "${WORKSPACE_GIT_TOKEN:-}" ] && [ -n "${WORKSPACE_GIT_URL:-}" ]
}

# Store the PAT for HTTPS git auth; persists on the volume so git works without the env var.
setup_credentials() {
  git config --global user.name "openclaw-agent" || return 1
  git config --global user.email "agent@openclaw.local" || return 1
  git config --global credential.helper store || return 1
  printf 'https://x-access-token:%s@github.com\n' "$WORKSPACE_GIT_TOKEN" > ~/.git-credentials || return 1
  chmod 600 ~/.git-credentials || return 1
}

clear_credentials() { rm -f ~/.git-credentials; }

# Seed the git-sync skill into $STATE_DIR/skills — beside workspace/, not inside it
# (a skill under workspace/ makes OpenClaw skip the first-run ritual).
seed_managed_skills() {
  [ -d "$SEED_SKILLS" ] || return 0
  [ -d "$STATE_DIR/skills" ] && return 0
  cp -r "$SEED_SKILLS" "$STATE_DIR/skills" || { warn "could not seed the git-sync skill"; return 1; }
}

# Seed workspace/ when empty, not just when absent: the base image ships an empty
# workspace/ that a `[ -d ]` test would mistake for seeded. `/.` copies contents.
seed_workspace_if_empty() {
  [ -n "$(ls -A workspace 2>/dev/null)" ] && return 0
  mkdir -p workspace || return 1
  cp -r "$SEED_WORKSPACE/." workspace/ || return 1
}

# Seed config + workspace (required) and the skill (best-effort). Caller cd's to $STATE_DIR.
seed_state() {
  [ -f openclaw.json ] || cp "$SEED_CONFIG" openclaw.json || return 1
  seed_workspace_if_empty || return 1
  seed_managed_skills || true   # optional — never blocks boot
}

# No git sync: seed the state dir so the gateway can boot standalone.
seed_local_only() {
  mkdir -p "$STATE_DIR" || return 1
  cd "$STATE_DIR" || return 1
  seed_state || return 1
  log "local-only mode — no git sync"
}

# Real local state worth preserving (non-empty workspace or a config file). Gate on
# emptiness so the base image's empty workspace/ doesn't trigger a spurious backup.
has_local_state() { [ -n "$(ls -A workspace 2>/dev/null)" ] || [ -f openclaw.json ]; }

# Remote branch exists: back up local state to a local-backup-<ts> branch before adopting.
preserve_local_to_backup() {
  has_local_state || return 0
  local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)"
  cp "$SEED_GITIGNORE" .gitignore || return 1
  [ -d workspace     ] && { git add workspace     || return 1; }
  [ -f openclaw.json ] && { git add openclaw.json || return 1; }
  git add .gitignore || return 1
  git diff --cached --quiet && return 0
  git commit -q -m "local state before sync ($ts)" || return 1
  git push -q origin "HEAD:refs/heads/local-backup-$ts" || return 1
  log "backed up prior local state to branch local-backup-$ts"
}

# Adopt the remote branch; untracked runtime state is left in place.
adopt_remote_sync() {
  git fetch -q origin workspace-sync:refs/remotes/origin/workspace-sync || return 1
  git checkout -q -B workspace-sync origin/workspace-sync || return 1
}

# Remote branch missing: create it as an orphan from local state (or the seed).
create_orphan_sync() {
  git checkout -q -b workspace-sync || return 1
  cp "$SEED_GITIGNORE" .gitignore || return 1
  seed_state || return 1
  git add .gitignore workspace openclaw.json || return 1
  [ -d skills ] && { git add skills || return 1; }
  git commit -q -m "bootstrap workspace-sync" || return 1
  git push -q -u origin workspace-sync || return 1
}

# Set sync up in place: fast-path a healthy clone, else probe and adopt/create.
setup_sync() {
  mkdir -p "$STATE_DIR" || return 1
  cd "$STATE_DIR" || return 1

  if [ -d .git ]; then
    if git rev-parse --verify -q refs/heads/workspace-sync >/dev/null 2>&1; then
      [ "$(git remote get-url origin 2>/dev/null || true)" = "$WORKSPACE_GIT_URL" ] \
        || { git remote set-url origin "$WORKSPACE_GIT_URL" || return 1; }
      log "sync already configured"
      return 0
    fi
    warn "incomplete .git from an interrupted boot — re-initializing"
    rm -rf .git
  fi

  # rc: 0 = branch exists, 2 = missing, anything else = unreachable.
  local rc=0
  git ls-remote --exit-code --quiet "$WORKSPACE_GIT_URL" workspace-sync >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    warn "cannot reach $WORKSPACE_GIT_URL — check the URL, token, and network"
    return 1
  fi

  git init -q || return 1            # in place — runtime state stays untouched
  git remote add origin "$WORKSPACE_GIT_URL" || return 1

  if [ "$rc" -eq 0 ]; then
    log "remote workspace-sync exists — backing up any local state, then adopting it"
    preserve_local_to_backup || { rm -rf .git; return 1; }
    adopt_remote_sync        || { rm -rf .git; return 1; }
  else
    log "remote workspace-sync missing — creating it from local state (or seed)"
    create_orphan_sync       || { rm -rf .git; return 1; }
  fi

  log "sync ready at $STATE_DIR"
}

main() {
  local sync_ok=0

  if have_sync_env; then
    if setup_credentials && setup_sync; then
      sync_ok=1
    else
      clear_credentials
      warn "git sync setup failed (check WORKSPACE_GIT_URL / WORKSPACE_GIT_TOKEN); continuing in local-only mode"
    fi
    unset WORKSPACE_GIT_TOKEN
  fi

  [ "$sync_ok" -eq 0 ] && { seed_local_only || { warn "could not seed workspace"; exit 1; }; }

  cd "$STATE_DIR" || exit 1
  log "starting gateway: $*"
  exec "$@"
}

main "$@"
