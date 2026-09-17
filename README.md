# OpenClaw Hyperlift Template

A ready-to-deploy [OpenClaw](https://docs.openclaw.ai/) agent gateway for [Spaceship Hyperlift](https://www.spaceship.com/starlight-cloud/hyperlift/). Deploy to run a hosted AI agent with a web control UI. The agent's workspace — its memory, personality, and configuration — persists on the deployment's volume, and can optionally sync to a branch of your own GitHub repository so you can edit it from your machine and keep your own backup.

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

## Log in

1. Open the app URL, enter your gateway password in the **Password** field and click **Connect**.
2. The first time from a new browser you get a red **Device pairing required** box with CLI instructions. Ignore the instructions: the template's `device-autopair` plugin approves the browser within a few seconds. Click **Connect** once more and you are in.
3. The browser does not store the password, so a new session asks for it again. The pairing is remembered per browser.

On the first visit the control UI may open **Model Setup** instead of the chat, or the model picker may say **No models available**. Your provider's key is already there: click **Test & use** (or **Check model** when a model is already selected), and once it verifies the model you can start chatting.

### Run commands in your deployment

Open **Terminal** from the chat side panel in the Control UI, or add `/focus/terminal` to your gateway URL for a full-screen terminal. Commands entered here run directly inside your deployment; no local CLI installation is needed. Use this terminal for the provider installation and configuration commands below. The [remote CLI](#connect-the-openclaw-cli) runs on your own computer instead.

## Configure your model provider

The template ships with six providers enabled and tested — **Anthropic, Google, Mistral, OpenAI, OpenRouter, and xAI**. Using one of these is the easy path; any other provider takes a few extra steps on the running deployment. (Mistral is not part of the OpenClaw image, so this template's `Dockerfile` adds the official `@openclaw/mistral-provider` package to it.)

### A preconfigured provider (recommended)

Pick your provider when you create the app and enter its API key. Its plugin is already on, so its models show up in the control UI — set the agent's default under **Settings → Agents & Tools → Models → Default model** and **Save** (or let the first-run **Model Setup** page do it). That's all. The **Chat model** control next to the message box only overrides the model for the current chat.

To switch to a different one of the six later, add that provider's key (e.g. `ANTHROPIC_API_KEY`) in the [Hyperlift manager](https://www.spaceship.com/application/hyperlift-manager/), or enter it in the control UI under **Settings → Agents & Tools → Models → Model Setup**. Select its model under **Settings → Agents & Tools → Models** and save the default.

### Another provider

OpenClaw supports many more providers; you just enable and configure them yourself. The full list and per-provider settings are in the [OpenClaw provider docs](https://docs.openclaw.ai/providers).

**Example — add Cerebras using the [built-in terminal](#run-commands-in-your-deployment):**

1. Run the following command in the [built-in terminal](#run-commands-in-your-deployment):
   ```bash
   openclaw plugins install @openclaw/cerebras-provider
   ```
2. Add `CEREBRAS_API_KEY` as an environment variable in the Hyperlift manager. Saving it automatically restarts the app, loading the plugin and API key; no separate restart is needed.
3. In the control UI, select a Cerebras model under **Settings → Agents & Tools → Models → Default model** and **Save**.

For other providers, follow their [provider-specific instructions](https://docs.openclaw.ai/providers) for the plugin package, credentials, and any additional configuration. Run deployment commands in the [built-in terminal](#run-commands-in-your-deployment). If setup still fails, see [Troubleshooting](#troubleshooting).

## Editing the configuration

Most deployment settings live in `openclaw.json` — the model, enabled plugins and skills, agent behavior, and gateway settings — so you'll change it regularly as you customize. Workspace files such as `AGENTS.md`, `SOUL.md`, and `IDENTITY.md` hold the agent's instructions and personality. The easiest way is to just **ask the agent**; the five methods below let you change the deployment::

| Method | Where | Good for |
|---|---|---|
| **Ask the agent** | Plain language in the web chat | The simplest and most common approach — say what you want ("switch to model X", "add a skill for Y") and the agent edits `openclaw.json` and applies it for you. It runs inside the container, so it can't set Hyperlift env vars — add API keys there yourself. |
| **Control UI — raw config editor** | **Settings → System → Advanced** in the gateway, then switch the editor to **Raw** | Editing `openclaw.json` by hand from the browser; nothing to install. Reveal the redacted values with the eye button before editing, then **Save**. |
| **Built-in terminal** | The [Control UI terminal](#run-commands-in-your-deployment) | Running commands such as `openclaw config set ...` directly inside the deployment. |
| **`/bash` in the web chat** | Type `/bash openclaw …` in the chat | An alternative for running deployment commands from chat; enabled by this template. |
| **Git-sync branch** | The `workspace-sync` branch, edited from your machine | Versioned, off-cluster edits to `openclaw.json` and workspace files. Requires [git sync](#git-sync-optional). |

Most valid configuration changes apply automatically; some require a gateway restart. With the default reload mode, OpenClaw restarts when required. The CLI on your own computer has [remote limitations](#remote-cli-limitations). Whichever method you use, keep secrets out of `openclaw.json` — see [Security](#security).

## Persistent storage

Hyperlift mounts a persistent volume at `/home/node`. The deployment uses OpenClaw's defaults — `OPENCLAW_STATE_DIR=/home/node/.openclaw` and `OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json` — so the agent's state lives on that volume, and anything written under `/home/node` at runtime persists across restarts and redeploys.

The same mount has a build-time implication for customizing this template: at runtime the volume mounts over whatever the image has at `/home/node`, so anything a `Dockerfile` `RUN` step writes there — directly or as a side effect — is hidden by the mount at runtime. Examples of Dockerfile steps affected by this problem:

- `RUN openclaw plugins install clawhub:@openclaw/diagnostics-otel` — writes plugins, extensions, and config under `/home/node/.openclaw`
- `RUN openclaw skills install calendar` — writes skills to `/home/node/.openclaw/workspace/skills`

Installing ordinary system packages (`jq`, `wget`, `tree`, …) in the `Dockerfile` works as expected — they land outside `/home/node`.

To install anything that lives under `/home/node`, do it after the volume is mounted instead:

- **Use the [built-in terminal](#run-commands-in-your-deployment)** — run the command directly in the deployment.
- **Ask the agent** — it can run the command inside its container with the exec tool.
- **Extend `init.sh`** — it's the entrypoint and runs on every boot after the volume is mounted, so its changes to `/home/node` stick and re-apply even to a fresh volume.

## Connect the OpenClaw CLI

You can operate your deployed gateway from your own machine with the OpenClaw CLI; a local gateway is not required.

**1. Install the matching version.** Install the version the image pins (see the `Dockerfile`, or the version shown in the control UI) — a CLI that speaks a different gateway wire protocol is rejected at connect with `protocol mismatch`, and matching the pinned version is the reliable way to avoid that. Node 26 is recommended; Node 22.22.3+, 24.15+, or 25.9+ are supported, per the [installation guide](https://docs.openclaw.ai/install):

```bash
npm install -g openclaw@2026.8.2
```

**2. Point the CLI at your gateway.** Configure [remote gateway mode](https://docs.openclaw.ai/gateway/remote) on your own computer:

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
openclaw agent --agent main --message "Say hi"
```

`health` works right away. The first command that talks to the agent reports `pairing required: device is not approved yet`. The template's `device-autopair` plugin approves it within about five seconds — wait a moment and run it again. If it stays pending, approve it manually under **Settings → Connections → Devices** → **Paired devices**.

**4. Approve scope upgrades when prompted.** OpenClaw grants access per action, by [least-privilege design](https://docs.openclaw.ai/gateway/operator-scopes) — there is no way to pre-approve everything from the CLI. The first time you run a command that needs broader access — for example, messaging the agent:

```bash
openclaw agent --agent main --message "hello from the cli"
```

you will see `scope upgrade pending approval`. Approve it under **Settings → Connections → Devices** — the `device-autopair` plugin deliberately never auto-approves upgrades for an already-paired device, so this one is always a manual click. Routine use afterward does not prompt again unless an action requires a new scope.

### Remote CLI limitations

The CLI talks to the gateway over its WebSocket API; it is not a shell inside the container. Use it to operate the running gateway: check `health`, tail `logs`, message the agent (`agent --message …`), manage `cron` jobs, approve `devices`.

Commands such as `openclaw config set`, `openclaw plugins install`, and `openclaw onboard` modify state on the machine running the CLI. Remote mode does not redirect those writes to the deployment; behavior depends on the subcommand, so do not assume every CLI command targets the remote gateway.

To change the deployment itself, use one of the methods in [Editing the configuration](#editing-the-configuration) — ask the agent, the control UI, `/bash`, or the git-sync branch. For low-level access, [`openclaw gateway call`](https://docs.openclaw.ai/cli/gateway) invokes gateway RPC methods directly.

**Reference:** [Installation](https://docs.openclaw.ai/install) · [Remote gateway](https://docs.openclaw.ai/gateway/remote) · [Devices & pairing](https://docs.openclaw.ai/cli/devices)

## Git sync (optional)

The agent's workspace already persists on the deployment's volume across restarts and redeploys. Git sync is optional: it mirrors the workspace to a dedicated `workspace-sync` branch of your GitHub repository.

**Set up:**

1. Create a fine-grained GitHub PAT (Settings → Developer settings → Personal access tokens → Fine-grained), scoped to the single repository this app deploys from, with **Contents: read and write**.
2. Set `WORKSPACE_GIT_URL` (your template repository's HTTPS URL, e.g. `https://github.com/you/repo.git`) and `WORKSPACE_GIT_TOKEN` (the PAT) in your Hyperlift environment — saving them restarts the app automatically, and sync is set up on the way back up.

On first sync, the agent's current workspace becomes the first commit on a new `workspace-sync` branch — a standalone branch kept separate from your app's code.

**What syncs:** the agent's `workspace/` directory, its `openclaw.json` configuration, and `skills/`. Runtime state — credentials, sessions, and scheduled jobs — stays on the deployment's persistent volume and is never committed. Git sync is a backup of these selected files, not a full deployment backup.

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

- **Set a strong, unique gateway password and rotate it regularly.** OpenClaw also asks for a one-time approval of every new browser. Approving normally takes a shell on the gateway or an already approved browser, which a fresh Hyperlift deployment does not have, so the template's `device-autopair` plugin approves those requests for you. Node enrollments stay manual under **Settings → Connections → Devices**. You can turn the plugin off by setting `plugins.entries.device-autopair.enabled` to `false`; new browsers then need approval from a browser that is already paired.
- **Keep secrets in environment variables, not in `openclaw.json`.** OpenClaw reads keys such as `OPENAI_API_KEY` straight from the environment, and can substitute env values into the config where you do need to reference one — so a secret rarely has to live in the file at all, which also keeps it out of [git sync](#git-sync-optional).
- **Disable what you don't use.** Set `commands.bash` to `false` to disable `/bash` commands in chat. To disable the built-in terminal, set `gateway.terminal.enabled` to `false`. Agent tools are controlled separately through `tools.allow` and `tools.deny`; see the [tool policy documentation](https://docs.openclaw.ai/gateway/config-tools#toolsallow-toolsdeny).

## Troubleshooting

- **A provider or its models don't appear after you set them up.** Confirm the plugin is installed and enabled and the key is set (see [Configure your model provider](#configure-your-model-provider)). Saving environment variables restarts the app; if you changed plugin files afterward, restart it from the Hyperlift manager. If it still misbehaves, run `openclaw doctor` in the [built-in terminal](#run-commands-in-your-deployment) to diagnose the issue; `openclaw doctor --fix` applies repairs.
- **Git sync is not working.** Check the container logs. The most common causes are an expired PAT, an SSH-form URL instead of HTTPS, or a PAT missing **Contents: read and write**. If the remote cannot be reached, the container falls back to local-only mode and keeps running.
- **The CLI reports `protocol mismatch`.** The CLI and gateway use incompatible protocol versions — install the version this template pins (see [Connect the OpenClaw CLI](#connect-the-openclaw-cli)).
- **The CLI reports `scope upgrade pending`.** Approve the device in the control UI under **Settings → Connections → Devices**. (A plain `pairing required` clears itself within a few seconds via `device-autopair` — just retry.)
- **A plugin/skill/config change made via the CLI doesn't show up in the deployment.** Install- and config-type commands act on the machine running the CLI, not the remote gateway. See [Remote CLI limitations](#remote-cli-limitations).
- **`openclaw dashboard` or `openclaw gateway status` reports the gateway is not running when using the CLI on your own computer.** The message may refer to your computer’s local gateway or service, even with remote mode configured. Use openclaw health to check the deployment through your configured remote connection.
- **Something installed in the `Dockerfile` is missing at runtime.** If the build wrote it under `/home/node` (plugins, skills, caches), the persistent volume mounts over it — install it after boot instead. See [Persistent storage](#persistent-storage).
- **The app restarts or runs out of memory (`OOMKilled`).** This template disables the Codex plugin (`plugins.entries.codex.enabled: false`) and pins OpenAI models to OpenClaw's lighter built-in runtime (`models.providers.openai.agentRuntime.id: "openclaw"` in `seed/openclaw.default.json`). Without the pin, OpenAI models on the official API route to OpenAI's *Codex* runtime, which runs the agent in a separate app-server and spawns a full helper process per tool call — enough to exhaust a medium instance. And with the plugin disabled but the pin missing, OpenAI models fail outright with `runtime "codex" is unavailable`, so keep the two settings together. Non-OpenAI models are unaffected. Re-enable codex (and remove the pin) only if you want its agentic/code-execution features and have given the app more memory.

## License

This template is released under the [MIT License](LICENSE).
