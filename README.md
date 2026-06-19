# OpenClaw Hyperlift Template

A ready-to-deploy [OpenClaw](https://docs.openclaw.ai/) agent gateway for [Spaceship Hyperlift](https://hyperlift.spaceship.com). Deploy to run a hosted AI agent with a web control UI. The agent's workspace — its memory, personality, and configuration — persists on the deployment's volume, and can optionally sync to a branch of your own GitHub repository so you can edit it from your machine and keep your own backup.

## What's included

On boot, the container starts an OpenClaw **gateway** — a web control UI and chat interface for your agent — with a standard [OpenClaw agent workspace](https://docs.openclaw.ai/concepts/agent-workspace) (the agent's memory, identity, rules, and config). On its first run the agent introduces itself and sets up its identity with you, guided by a `BOOTSTRAP.md` ritual it then deletes.

On top of that, this template adds a `git-sync` skill and a sync-status hook, used only when git sync is enabled.

> **Note:** The `seed/` directory bootstraps the workspace only on first boot — editing it has no effect on an already-running deployment. To change a running deployment, see [Editing the configuration](#editing-the-configuration).

## Deploy to Hyperlift

Create a Hyperlift app from this template; Hyperlift builds the container from the `Dockerfile`. On first install it asks you to pick a model provider and enter its API key, and to set a **gateway password**; both are stored as the app's environment variables. The optional variables you add to the app's environment yourself.

| Variable | Set | Purpose |
|---|---|---|
| `<provider>_API_KEY` | Prompted on install | API key for the model provider you pick during install — e.g. `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`. See [Configure your model provider](#configure-your-model-provider). |
| `OPENCLAW_GATEWAY_PASSWORD` | Prompted on install | Password for the gateway and its control UI. |
| `WORKSPACE_GIT_URL` | Optional | Enables git sync — the HTTPS URL of the repository to sync the agent's workspace to. See [Git sync](#git-sync-optional). |
| `WORKSPACE_GIT_TOKEN` | Optional | GitHub token for git sync, paired with `WORKSPACE_GIT_URL`. |

See the [configuration reference](https://docs.openclaw.ai/gateway/configuration) for `openclaw.json` options.

> **Note:** The agent's data lives at `/home/node/.openclaw` on the app's persistent volume. Leave `OPENCLAW_STATE_DIR` at its default — pointing it outside `/home/node` means the data won't survive a restart.

Once deployed, open the gateway's URL, sign in with your gateway password, and start chatting with your agent.

## Configure your model provider

The template ships with six providers enabled and tested — **Anthropic, Google, Mistral, OpenAI, OpenRouter, and xAI**. Using one of these is the easy path; any other provider takes a few extra steps on the running deployment.

### A preconfigured provider (recommended)

Pick your provider when you create the app and enter its API key. Its plugin is already on, so its models show up in the control UI — open the model picker and choose the one the agent should use. That's all.

To switch to a different one of the six later, add that provider's key (e.g. `ANTHROPIC_API_KEY`) in the [Hyperlift manager](https://www.spaceship.com/application/hyperlift-manager/) and select its model in the UI.

### Another provider

OpenClaw supports many more providers; you just enable and configure them yourself. The full list and per-provider settings are in the [OpenClaw provider docs](https://docs.openclaw.ai/providers).

**Recommended — run onboarding from the chat.** This template enables the `/bash` command in the web chat, which runs commands inside the container (Hyperlift gives no SSH access, so this is how you run commands in the deployment). Add your provider's API key in the Hyperlift manager, then enable the plugin and run `onboard` — it configures the plugin, populates the model catalog, and sets the agent's default model in one step. For Cerebras:

```text
/plugins enable cerebras
/bash openclaw onboard --auth-choice cerebras-api-key --cerebras-api-key "$CEREBRAS_API_KEY" --gateway-auth=password --gateway-password="\${OPENCLAW_GATEWAY_PASSWORD}" --gateway-bind=lan --skip-skills --skip-ui --accept-risk --non-interactive
```

- Swap `--auth-choice` and `--<provider>-api-key` for your provider — the [provider docs](https://docs.openclaw.ai/providers) list the exact names.
- The `--gateway-*` flags are required even though Hyperlift already sets these; `onboard` refuses to run without them. The escaped `\$` is intentional — it stores `${OPENCLAW_GATEWAY_PASSWORD}` in `openclaw.json` as a reference that OpenClaw resolves from the environment at runtime, so the real password never lands in the file.
- `--accept-risk` and `--non-interactive` let it run unattended from the chat.

**Alternative — configure it by hand.** [Edit the live `openclaw.json`](#editing-the-configuration) and:

1. Enable the plugin — set `plugins.entries.<provider>.enabled` to `true`.
2. Add the provider's API key as an environment variable in the Hyperlift manager.
3. If its models don't appear, add them by hand under `models.providers` and set `agents.defaults.model` — the [provider docs](https://docs.openclaw.ai/providers) include a sample config for each.
4. Still not working? Restart the app from the Hyperlift manager; if it persists, see [Troubleshooting](#troubleshooting).

For most providers, steps 1–2 are enough.

## Editing the configuration

Almost everything about the deployment lives in `openclaw.json` — the model, enabled plugins and skills, agent behavior, and gateway settings — so you'll change it regularly as you customize. The easiest way is to just **ask the agent**; there are five methods in all, and every one changes the **live** instance:

| Method | Where | Good for |
|---|---|---|
| **Ask the agent** | Plain language in the web chat | The simplest and most common approach — say what you want ("enable the Cerebras plugin", "switch to model X", "add a skill for Y") and the agent edits `openclaw.json` and applies it for you. It runs inside the container, so it can't set Hyperlift env vars — add API keys there yourself. |
| **Control UI — Raw Mode** | **Settings → Advanced → Raw Mode → Raw config** in the gateway | Editing `openclaw.json` by hand from the browser; nothing to install. |
| **`/bash` in the web chat** | Type `/bash openclaw …` in the chat | Running OpenClaw commands inside the container yourself — `onboard`, `plugins enable`, `config set`. They take effect on the deployment. |
| **Git-sync branch** | The `workspace-sync` branch, edited from your machine | Versioned, off-cluster edits to `openclaw.json` and workspace files. Requires [git sync](#git-sync-optional). |
| **Remote CLI** | The `openclaw` CLI on your machine | *Operating* the gateway (health, logs, messaging) — **not** config: `config`/`plugins`/`onboard` run locally, not on the deployment. See [Remote CLI limitations](#remote-cli-limitations). |

Pick whichever suits the change — the [model-provider steps](#configure-your-model-provider) above, for example, use `/bash` (onboarding) or Raw Mode (manual edits). Whichever you use, keep secrets out of `openclaw.json` — see [Security](#security).

## Persistent storage

Hyperlift mounts a persistent volume at `/home/node`. The deployment uses OpenClaw's defaults — `OPENCLAW_STATE_DIR=/home/node/.openclaw` and `OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json` — so the agent's state lives on that volume, and anything written under `/home/node` at runtime persists across restarts and redeploys.

The same mount has a build-time implication for customizing this template: at runtime the volume mounts over whatever the image has at `/home/node`, so anything a `Dockerfile` `RUN` step writes there — directly or as a side effect — is hidden by the mount at runtime. For example:

- `RUN openclaw plugins install clawhub:@openclaw/diagnostics-otel` — writes plugins, extensions, and config under `/home/node/.openclaw`
- `RUN openclaw skills install calendar` — writes skills to `/home/node/.openclaw/workspace/skills`

Installing ordinary system packages (`jq`, `wget`, `tree`, …) in the `Dockerfile` works as expected — they land outside `/home/node`.

To install anything that lives under `/home/node`, do it after the volume is mounted instead:

- **Ask the agent** — it can run the command inside its container with the exec tool.
- **Extend `init.sh`** — it's the entrypoint and runs on every boot after the volume is mounted, so its changes to `/home/node` stick and re-apply even to a fresh volume.

## Connect the OpenClaw CLI

You can operate your deployed gateway from your own machine with the OpenClaw CLI; a local gateway is not required.

**1. Install the matching version.** The CLI and gateway must run the same OpenClaw version, otherwise the connection fails with a protocol error. See the `Dockerfile`, or the version shown in the control UI. Install that version with npm — Node 24 is recommended and Node 22+ is supported, per the [installation guide](https://docs.openclaw.ai/install):

```bash
npm install -g openclaw@2026.6.8
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

### Remote CLI limitations

The CLI talks to the gateway over its WebSocket API; it is not a shell inside the container. Use it to operate the running gateway: check `health`, tail `logs`, message the agent (`agent --message …`), manage `cron` jobs, approve `devices`.

Installation and setup commands — `config`, `plugins`, `skills`, `models`, `onboard`, and similar — act on the machine the CLI runs on, not the remote gateway. They complete without error even with remote mode configured.

To change the deployment itself, use one of the methods in [Editing the configuration](#editing-the-configuration) — ask the agent, the control UI, `/bash`, or the git-sync branch. For low-level access, [`openclaw gateway call`](https://docs.openclaw.ai/cli/gateway) invokes gateway RPC methods directly.

**Reference:** [Installation](https://docs.openclaw.ai/install) · [Remote gateway](https://docs.openclaw.ai/gateway/remote) · [Devices & pairing](https://docs.openclaw.ai/cli/devices)

## Git sync (optional)

The agent's workspace already persists on the deployment's volume across restarts and redeploys. Git sync is optional: it mirrors the workspace to a dedicated `workspace-sync` branch of your GitHub repository.

**Set up:**

1. Create a fine-grained GitHub PAT (Settings → Developer settings → Personal access tokens → Fine-grained), scoped to the single repository this app deploys from, with **Contents: read and write**.
2. Set `WORKSPACE_GIT_URL` (your template repository's HTTPS URL, e.g. `https://github.com/you/repo.git`) and `WORKSPACE_GIT_TOKEN` (the PAT) in your Hyperlift environment — saving them restarts the app automatically, and sync is set up on the way back up.

On first sync, the agent's current workspace becomes the first commit on a new `workspace-sync` branch — a standalone branch that holds only the workspace files, kept separate from your app's code.

**What syncs:** the agent's `workspace/` directory, its `openclaw.json` configuration, and `skills/`. Runtime state — credentials, sessions, and scheduled jobs — stays local to the container and is never committed.

> **Never put secrets in `openclaw.json`.** With sync on, anything in that file is pushed to your repository in plaintext — keep API keys and tokens in your Hyperlift environment variables instead. See [Security](#security).

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

## Security

The gateway and its web chat are served on a public URL, so treat the deployment as internet-facing:

- **Set a strong, unique gateway password and rotate it regularly.** It's the only thing between the public internet and your agent.
- **Keep secrets in environment variables, not in `openclaw.json`.** OpenClaw reads keys such as `OPENAI_API_KEY` straight from the environment, and can substitute env values into the config where you do need to reference one — so a secret rarely has to live in the file at all, which also keeps it out of [git sync](#git-sync-optional).
- **Disable what you don't use.** This template turns on the unrestricted `/bash` command in the web chat so you can run provider onboarding (see [Configure your model provider](#configure-your-model-provider)). Once that's done, switch it off — set `commands.bash` to `false` in the live config — so a compromised UI can't run arbitrary commands in the container. You can still repair and reconfigure the deployment with [`/crestodian`](https://docs.openclaw.ai/cli/crestodian), OpenClaw's restricted setup-and-repair command surface, which works regardless.

## Troubleshooting

- **A provider or its models don't appear after you set them up.** Confirm the plugin is enabled and the key is set (see [Configure your model provider](#configure-your-model-provider)), then restart the app from the Hyperlift manager. If it still misbehaves, run `/bash openclaw doctor --fix` from the web chat — or `/crestodian doctor fix` (then `/crestodian yes`) if you've turned `/bash` off — to repair common configuration problems.
- **Git sync is not working.** Check the container logs. The most common causes are an expired PAT, an SSH-form URL instead of HTTPS, or a PAT missing **Contents: read and write**. If the remote cannot be reached, the container falls back to local-only mode and keeps running.
- **The CLI reports `protocol error`.** The CLI and gateway versions differ — install the version this template pins (see [Connect the OpenClaw CLI](#connect-the-openclaw-cli)).
- **The CLI reports `pairing required` or `scope upgrade pending`.** Approve the device in the control UI under **Nodes → Devices**.
- **A plugin/skill/config change made via the CLI doesn't show up in the deployment.** Install- and config-type commands act on the machine running the CLI, not the remote gateway. See [Remote CLI limitations](#remote-cli-limitations).
- **`openclaw dashboard` or `openclaw gateway status` reports the gateway is not running.** Both check for a gateway on the local machine. Use `openclaw health` to check the deployment.
- **Something installed in the `Dockerfile` is missing at runtime.** If the build wrote it under `/home/node` (plugins, skills, caches), the persistent volume mounts over it — install it after boot instead. See [Persistent storage](#persistent-storage).
- **The app restarts or runs out of memory (`OOMKilled`).** This template disables the Codex plugin (`plugins.entries.codex.enabled: false` in `seed/openclaw.default.json`). OpenAI models on the official API otherwise route to OpenAI's *Codex* runtime, which runs the agent in a separate app-server and spawns a full helper process per tool call — enough to exhaust a medium instance. Disabling it makes OpenAI models fall back to OpenClaw's lighter built-in runtime; non-OpenAI models are unaffected. Re-enable codex only if you want its agentic/code-execution features and have given the app more memory.

## License

This template is released under the [MIT License](LICENSE).
