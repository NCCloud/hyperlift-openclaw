---
name: sync-status-inject
description: "Inject current git-sync status into AGENTS.md at bootstrap, so the agent always has fresh state in its system prompt without chat pollution or agent turns."
metadata:
  { "openclaw": { "emoji": "🔁", "events": ["agent:bootstrap"] } }
---

# sync-status-inject

Prepends a short `<!-- Runtime state (auto-injected): ... -->` marker to the
AGENTS.md entry in the bootstrap file set on every `agent:bootstrap` event.

## What it checks

Sync is on iff `~/.openclaw/.git` exists. `init.sh` creates that directory only
after a successful clone, so its presence is a reliable indicator that sync
is fully set up.

## Why this exists

When the user adds `WORKSPACE_GIT_TOKEN`/`WORKSPACE_GIT_URL` and restarts the
gateway mid-session, the agent otherwise holds stale "sync is off" conclusions
from prior turns. This hook puts the live state into every fresh system prompt
load — no agent turn cost (no LLM round-trip), no chat pollution.
