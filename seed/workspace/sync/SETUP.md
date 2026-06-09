---
title: "Git Sync — setup walkthrough"
summary: "Step-by-step PAT creation and env-var setup for enabling git sync. Read on demand when the user asks how to turn sync on."
read_when:
  - The user asks how to enable git sync or how to create the PAT
---

# Setting up git sync

Read this when the user wants to enable sync (or asks how to create the PAT). Walk them through these steps:

1. **Create a fine-grained PAT on GitHub:**
   - Go to https://github.com/settings/tokens?type=beta (Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token).
   - **Token name**: anything memorable (e.g. `openclaw-workspace-sync`).
   - **Expiration**: 90 days or 1 year — PATs can't be "never expire" in fine-grained form. The user will need to rotate when it expires.
   - **Repository access**: "Only select repositories" → pick the single repo this app deploys from (the repo Hyperlift is linked to). Do **not** grant access to all repos.
   - **Permissions → Repository permissions**:
     - `Contents`: **Read and write** ← required
     - `Metadata`: Read-only (auto-selected)
     - Leave everything else at "No access".
   - Click Generate. Copy the token — GitHub only shows it once.

2. **Get the repo's HTTPS clone URL:**
   - On the repo's GitHub page, click Code → HTTPS.
   - Copy the URL. It should look like `https://github.com/<owner>/<repo>.git`. **Not** the SSH form (`git@github.com:...`) — the credential helper I use only authenticates HTTPS.

3. **Add both to the Hyperlift env vars:**
   - In the Hyperlift dashboard for this app, set:
     - `WORKSPACE_GIT_TOKEN` = the PAT from step 1 (mark as sensitive).
     - `WORKSPACE_GIT_URL` = the HTTPS URL from step 2.

4. **Restart the container** from the Hyperlift dashboard. When I come back up, I'll clone the repo, create a `workspace-sync` branch if it doesn't exist, and push my current workspace state to it. My next sessions will sync transparently.

## Rotation reminder

When the PAT is close to expiring, GitHub emails the user. They regenerate it, update `WORKSPACE_GIT_TOKEN` in Hyperlift.
