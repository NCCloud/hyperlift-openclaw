# OpenClaw Hyperlift Template

A ready-to-deploy [OpenClaw](https://docs.openclaw.ai/) agent gateway for [Spaceship Hyperlift](https://hyperlift.spaceship.com). Deploy to run a hosted AI agent with a web control UI. The agent's workspace — its memory, personality, and configuration — persists on the deployment's volume, and can optionally sync to a branch of your own GitHub repository so you can edit it from your machine and keep your own backup.

## What's included

On boot, the container starts an OpenClaw **gateway** — a web control UI and chat interface for your agent — with a standard [OpenClaw agent workspace](https://docs.openclaw.ai/concepts/agent-workspace) (the agent's memory, identity, rules, and config). On its first run the agent introduces itself and sets up its identity with you, guided by a `BOOTSTRAP.md` ritual it then deletes.

On top of that, this template adds a `git-sync` skill and a sync-status hook, used only when git sync is enabled.

You shape the agent by talking to it and by editing its live workspace — see the note below.

> **Note:** `seed/` only seeds a fresh workspace on first boot — editing it has no effect on an already-running deployment. Interact with the live agent through the control UI, or (with git sync enabled) edit its `workspace-sync` branch from your machine.

## Deploy to Hyperlift

Create a Hyperlift app from this template; Hyperlift builds the container from the `Dockerfile`. On first install it prompts you for the two required values — a **provider API key** and the **gateway password** — and stores them as the app's environment variables. The optional variables you add to the app's environment yourself.

| Variable | Set | Purpose |
|---|---|---|
| `OPENAI_API_KEY` | Prompted on install | Provider key for the agent's model. The template defaults to the `openai/gpt-5.4` model; to use another provider, change the model in `openclaw.json` and supply the matching key (e.g. `ANTHROPIC_API_KEY`). |
| `OPENCLAW_GATEWAY_PASSWORD` | Prompted on install | Password for the gateway and its control UI. |
| `WORKSPACE_GIT_URL` | Optional | Enables git sync — the HTTPS URL of the repository to sync the agent's workspace to. See [Git sync](#git-sync-optional). |
| `WORKSPACE_GIT_TOKEN` | Optional | GitHub token for git sync, paired with `WORKSPACE_GIT_URL`. |

See the [configuration reference](https://docs.openclaw.ai/gateway/configuration) for `openclaw.json` options.

> **Note:** The agent's data lives at `/home/node/.openclaw` on the app's persistent volume. Leave `OPENCLAW_STATE_DIR` at its default — pointing it outside `/home/node` means the data won't survive a restart.

Once deployed, open the gateway's URL, sign in with your gateway password, and start chatting with your agent.

## Persistent storage

Hyperlift mounts a persistent volume at `/home/node`. The deployment uses OpenClaw's defaults — `OPENCLAW_STATE_DIR=/home/node/.openclaw` and `OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json` — so the agent's state lives on that volume, and anything written under `/home/node` at runtime persists across restarts and redeploys.

The same mount has a build-time implication for customizing this template: at runtime the volume mounts over whatever the image has at `/home/node`, so anything a `Dockerfile` `RUN` step writes there — directly or as a side effect — is hidden by the mount at runtime. For example:

- `RUN openclaw plugins install clawhub:@openclaw/diagnostics-otel` — writes plugins, extensions, and config under `/home/node/.openclaw`
- `RUN openclaw skills install calendar` — writes skills to `/home/node/.openclaw/workspace/skills`

Installing ordinary system packages (`jq`, `wget`, `tree`, …) in the `Dockerfile` works as expected — they land outside `/home/node`.

To install anything that lives under `/home/node`, do it after the volume is mounted instead:

- **Ask the agent** — it can run the command inside its container with the exec tool.
- **Use the OpenClaw CLI** against your gateway (see [Connect the OpenClaw CLI](#connect-the-openclaw-cli)) — e.g. `openclaw plugins install …`.
- **Extend `init.sh`** — it's the entrypoint and runs on every boot after the volume is mounted, so its changes to `/home/node` stick and re-apply even to a fresh volume.

## Connect the OpenClaw CLI

You can operate your deployed gateway from your own machine with the OpenClaw CLI; a local gateway is not required.

**1. Install the matching version.** The CLI and gateway must run the same OpenClaw version, otherwise the connection fails with a protocol error. See the `Dockerfile`, or the version shown in the control UI. Install that version with npm — Node 24 is recommended and Node 22+ is supported, per the [installation guide](https://docs.openclaw.ai/install):

```bash
npm install -g openclaw@2026.6.1
```

**2. Point the CLI at your gateway.** Configure [remote gateway mode](https://docs.openclaw.ai/gateway/remote):

```bash
openclaw config set gateway.mode remote
openclaw config set gateway.remote.url wss://your-gateway.example.com
openclaw config set gateway.remote.password '<gateway-password>'
```

Use your gateway's public `wss://` URL and the credential it is configured with — for this template, the value you set in `OPENCLAW_GATEWAY_PASSWORD`.

> **Note:** These examples use `wss://` (TLS). If your gateway is reachable only over plaintext `ws://`, use a `ws://` URL instead — and, since the gateway host is public, set the break-glass variable in the shell running the CLI before connecting:
>
> ```bash
> export OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
> ```
>
> Plaintext `ws://` exposes your token and chat traffic to network interception. To use `wss://` instead, enable SSL for your app in the [Hyperlift manager](https://www.spaceship.com/application/hyperlift-manager/).

**3.** Test the connection:

```bash
openclaw health
```

On first use this reports `pairing required: device is not approved yet`. In the control UI, open **Nodes → Devices**, locate the pending request, and click **Approve**. Run `openclaw health` again and it connects.

**4. Approve scope upgrades when prompted.** OpenClaw grants access per action, by [least-privilege design](https://docs.openclaw.ai/gateway/operator-scopes) — there is no way to pre-approve everything from the CLI. The first time you run a command that needs broader access — for example, messaging the agent:

```bash
openclaw agent --agent main --message "hello from the cli"
```

you may see `scope upgrade pending approval`. Approve it the same way, under **Nodes → Devices**. Routine use afterward does not prompt again unless an action requires a new scope.

**Reference:** [Installation](https://docs.openclaw.ai/install) · [Remote gateway](https://docs.openclaw.ai/gateway/remote) · [Devices & pairing](https://docs.openclaw.ai/cli/devices)

## Git sync (optional)

The agent's workspace already persists on the deployment's volume across restarts and redeploys. Git sync is optional: it mirrors the workspace to a dedicated `workspace-sync` branch of your GitHub repository.

**Set up:**

1. Create a fine-grained GitHub PAT (Settings → Developer settings → Personal access tokens → Fine-grained), scoped to the single repository this app deploys from, with **Contents: read and write**.
2. Set `WORKSPACE_GIT_URL` (your template repository's HTTPS URL, e.g. `https://github.com/you/repo.git`) and `WORKSPACE_GIT_TOKEN` (the PAT) in your Hyperlift environment, then restart.

On first sync, the agent's current workspace becomes the first commit on a new `workspace-sync` branch — a standalone branch that holds only the workspace files, kept separate from your app's code.

**What syncs:** the agent's `workspace/` directory, its `openclaw.json` configuration, and `skills/`. Runtime state — credentials, sessions, and scheduled jobs — stays local to the container and is never committed.

> **Do not put secrets in `openclaw.json`.** Because that file is synced to your repository, any API key or token entered into the control UI's configuration or skill fields would be pushed to the branch in plaintext. Keep secrets in your Hyperlift environment variables instead.

**Edit the workspace from your machine:**

```bash
git clone <your-repo-url>
cd <repo>
git checkout workspace-sync
# edit files under workspace/ (e.g. workspace/IDENTITY.md)
git add workspace/ && git commit -m "tweak agent" && git push
```

Then tell the agent `"pull from git"` and it picks up your changes. Ask it to `"sync to git"` to push its own changes on demand.

**Good to know:**

- **Two-way and mostly automatic.** The agent syncs at natural points and on request (`"sync to git"`, `"pull from git"`) — each sync pulls your edits and pushes the agent's.
- **Portable.** The branch is the workspace's durable, off-cluster copy: point a new app at the same repo and it comes up with the agent's memory, personality, and config intact.
- **Conflict-safe.** If changes can't merge cleanly, the agent keeps the remote and saves its divergent work on a `backup/<timestamp>` branch — nothing is overwritten.

## Troubleshooting

- **Git sync is not working.** Check the container logs. The most common causes are an expired PAT, an SSH-form URL instead of HTTPS, or a PAT missing **Contents: read and write**. If the remote cannot be reached, the container falls back to local-only mode and keeps running.
- **The CLI reports `protocol error`.** The CLI and gateway versions differ — install the version this template pins (see [Connect the OpenClaw CLI](#connect-the-openclaw-cli)).
- **The CLI reports `pairing required` or `scope upgrade pending`.** Approve the device in the control UI under **Nodes → Devices**.
- **Something installed in the `Dockerfile` is missing at runtime.** If the build wrote it under `/home/node` (plugins, skills, caches), the persistent volume mounts over it — install it after boot instead. See [Persistent storage](#persistent-storage).
