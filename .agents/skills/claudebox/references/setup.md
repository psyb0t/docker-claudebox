# claudebox setup

## Requirements

- Docker installed and running. That's it — the wrapper handles the rest.
- An Anthropic credential: `CLAUDE_CODE_OAUTH_TOKEN` (via `claudebox setup-token`) or `ANTHROPIC_API_KEY`.

## Quick Install (CLI wrapper)

Safer path — download, inspect, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh -o install.sh
less install.sh   # read it before running anything you downloaded
bash install.sh

# full image variant
export CLAUDEBOX_FULL=1 && bash install.sh

# custom binary name
bash install.sh claude
```

Piping straight into bash (still works, same script, just skips the inspection step):

```bash
# minimal image — default; Claude installs what it needs on the fly
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash

# full image — every dev tool pre-installed (Go, Python, kubectl, terraform, ...)
export CLAUDEBOX_FULL=1 && curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash

# custom binary name
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash -s -- claude
```

Piping a remote script straight into bash executes unreviewed remote code as you. Download it, read it, then run it — prefer the download-inspect-run form above, especially in an agent-driven or CI context.

The installer pulls the image, generates an ed25519 SSH key at `~/.ssh/claudebox/id_ed25519` for git operations inside the container, creates `~/.claude`, and installs the wrapper to `/usr/local/bin/claudebox` (override with `CLAUDEBOX_INSTALL_DIR` / `CLAUDEBOX_BIN_NAME`). Add the generated public key to GitHub/GitLab for git push/pull to work from inside the container.

`VAR=x curl ... | bash` does **not** set `VAR` for the install script — bash attaches env assignments before a pipeline to the first command only (`curl`). Always `export` the var first.

Manual setup without piping to bash: `mkdir -p ~/.claude`, generate the SSH key yourself, `docker pull psyb0t/claudebox:latest` (or `:latest-full`), then fetch `wrapper.sh` and install it as your `claudebox` binary.

## Image Variants

| | `psyb0t/claudebox:latest` (minimal, default) | `psyb0t/claudebox:latest-full` |
| --- | --- | --- |
| Base | Ubuntu 24.04, git/curl/wget/jq, Node.js 22 LTS, Python 3.12 + uv, Docker CE | same, plus everything below |
| Go | — | 1.26 toolchain (golangci-lint, gopls, delve, staticcheck, gofumpt, gotests, impl, gomodifytags) |
| Python | — | 3.12 via pyenv (flake8, black, isort, pyright, mypy, vulture, pytest, poetry, pipenv) |
| Node dev tools | — | eslint, prettier, typescript, yarn, pnpm, framework CLIs |
| C/C++ | — | gcc, g++, make, cmake, clang-format, valgrind, gdb |
| DevOps | — | terraform, kubectl, helm, gh |
| DB clients | — | sqlite3, psql, mysql, redis-cli |
| Shell utils | — | ripgrep, bat, exa, fd-find, ag, htop, tmux, shellcheck, shfmt |

Minimal has passwordless sudo, so Claude installs whatever else it needs via `apt-get`/`pip`/`npm` on the fly — smaller pull, slower first task. Use `/aicodebox-init.d/*.sh` hooks to pre-install tooling on first container create instead of burning tokens on package management.

`CLAUDEBOX_FULL=1` at install time bakes the full-variant choice into the wrapper permanently; at runtime it overrides per-invocation. Pre-v2 `CLAUDEBOX_MINIMAL=1` is a no-op (minimal is already the default).

## docker run / docker-compose

### Interactive / exec (via the wrapper — recommended)

The installed `claudebox` wrapper handles container naming, volume mounts, SSH key mounting, and auth forwarding automatically. Don't hand-roll `docker run` for interactive/exec use — install the wrapper instead (see Quick Install above).

### Server modes (API / OpenAI / MCP / Telegram / Cron)

```yaml
# docker-compose.yml
services:
  claudebox:
    image: psyb0t/claudebox:latest
    ports:
      - "8080:8080"
    environment:
      - CLAUDEBOX_API_MODE=1
      - CLAUDEBOX_API_MODE_TOKEN=your-secret-token
      - CLAUDEBOX_AVAILABLE_MODELS=haiku,sonnet,opus,opusplan
      - CLAUDE_CODE_OAUTH_TOKEN=<YOUR_OAUTH_TOKEN>
    volumes:
      - ~/.claude:/home/aicode/.claude
      - /your/projects:/workspace
      - /var/run/docker.sock:/var/run/docker.sock
```

Mounting `/var/run/docker.sock` grants host-level container control — anything that can reach the socket (including Claude itself, by design, or an attacker who compromises the API/MCP surface above) can create, inspect, or destroy any container on the host, not just this one. Only mount it on a host you trust, and only if you need docker-in-docker for this workload.

Add `CLAUDEBOX_MCP_MODE=1` + `CLAUDEBOX_MCP_MODE_TOKEN` alongside `CLAUDEBOX_API_MODE=1` to mount MCP on the same port. Set `CLAUDEBOX_TELEGRAM_MODE=1` + `CLAUDEBOX_TELEGRAM_MODE_TOKEN` for the bot, or `CLAUDEBOX_CRON_MODE=1` + `CLAUDEBOX_CRON_MODE_FILE` for the scheduler — any combination can run in the same container (e.g. cron + Telegram share one workspace).

## Runtime Hardening (recommended `docker run` flags)

- `--cap-drop=ALL --cap-add=NET_BIND_SERVICE` — drop every Linux capability, add back only bind-below-1024 if needed.
- `--security-opt no-new-privileges:true` — block setuid privilege escalation inside the container.
- `--memory=2g --cpus=2 --pids-limit=512` — cap resource use so a runaway process can't starve the host.
- `--read-only --tmpfs /tmp:rw,noexec,nosuid` — only if you don't need `/workspace` writes, otherwise skip.

The container drops from root to `aicode` (UID 1000) at boot via `setpriv`, so the process running your code is never root even without `--user`.

## Environment Variable Reference

All wrapper/installer config uses the `CLAUDEBOX_*` prefix; the entrypoint aliases each to `AICODEBOX_*` (the base image's canonical names) when the target is unset — `AICODEBOX_*` wins if both are set. Legacy pre-v2 `CLAUDE_*` / `CLAUDE_MODE_*` names still work as fallbacks.

### Wrapper / installer

| Variable | Description | Default |
| --- | --- | --- |
| `CLAUDEBOX_GIT_NAME` / `CLAUDEBOX_GIT_EMAIL` | Git identity inside the container | _(none)_ |
| `CLAUDEBOX_DATA_DIR` | Host path for the `.claude` data dir | `~/.claude` |
| `CLAUDEBOX_SSH_DIR` | Host path for the SSH key directory | `~/.ssh/claudebox` |
| `CLAUDEBOX_INSTALL_DIR` | Wrapper binary install location (install-time) | `/usr/local/bin` |
| `CLAUDEBOX_BIN_NAME` | Wrapper binary name (install-time) | `claudebox` |
| `CLAUDEBOX_IMAGE` | Override the Docker image | `psyb0t/claudebox:latest` |
| `CLAUDEBOX_FULL` | Use the `latest-full` toolchain image instead of minimal | _(none)_ |
| `CLAUDEBOX_CONTAINER_NAME` | Override the per-workspace container name | derived from `$PWD` |
| `CLAUDEBOX_MAX_MEM` | Per-container memory limit | `10g` |
| `CLAUDEBOX_ENV_*` | Forward arbitrary vars into the container (prefix stripped) | _(none)_ |
| `CLAUDEBOX_MOUNT_*` | Mount extra host directories | _(none)_ |

Auth/in-container settings route through `CLAUDEBOX_ENV_*`:

```bash
CLAUDEBOX_ENV_ANTHROPIC_API_KEY=sk-... claudebox "do stuff"
CLAUDEBOX_ENV_CLAUDE_CODE_OAUTH_TOKEN=<YOUR_OAUTH_TOKEN> claudebox "do stuff"
CLAUDEBOX_ENV_DEBUG=true claudebox "do stuff"          # structured JSON debug logging
```

Extra mounts:

```bash
CLAUDEBOX_MOUNT_DATA=/data claudebox "process the data"                   # same path both sides
CLAUDEBOX_MOUNT_1=/opt/configs CLAUDEBOX_MOUNT_2=/var/logs claudebox "go" # multiple mounts
CLAUDEBOX_MOUNT_STUFF=/host/path:/container/path claudebox "do stuff"     # explicit src:dst
CLAUDEBOX_MOUNT_RO=/data:/data:ro claudebox "read the data"               # read-only
```

### Server modes

| Variable | Description | Default |
| --- | --- | --- |
| `CLAUDEBOX_API_MODE` | `1` to start the HTTP API server | _(none)_ |
| `CLAUDEBOX_API_MODE_PORT` | API server port | `8080` |
| `CLAUDEBOX_API_MODE_TOKEN` | Bearer token for `/run`, `/files`, `/status`, `/openai/*` | _(none — no auth)_ |
| `CLAUDEBOX_AVAILABLE_MODELS` | CSV of model aliases surfaced at `/openai/v1/models`. Optional — claudebox's adapter has a built-in default (`haiku,sonnet,opus,opusplan`); set this to override it. The API server only refuses to boot if the resolved list ends up empty. | _(none — adapter default applies)_ |
| `CLAUDEBOX_AVAILABLE_EFFORTS` | CSV of effort levels surfaced to Telegram `/effort` picker | adapter default |
| `CLAUDEBOX_MCP_MODE` | `1` to expose MCP. Mounts at `/mcp` on the API port if `CLAUDEBOX_API_MODE=1` is also set; otherwise runs standalone on its own port | _(none)_ |
| `CLAUDEBOX_MCP_MODE_PORT` | Port for the standalone MCP process (only used when API mode is off) | `8081` |
| `CLAUDEBOX_MCP_MODE_TOKEN` | Bearer token for MCP (independent of the API token, no fallback) | _(none — no auth)_ |
| `CLAUDEBOX_TELEGRAM_MODE` | `1` to start the Telegram bot | _(none)_ |
| `CLAUDEBOX_TELEGRAM_MODE_TOKEN` | Bot token from [@BotFather](https://t.me/BotFather) | _(none)_ |
| `CLAUDEBOX_TELEGRAM_MODE_CONFIG` | Path to `telegram.yml` inside the container | `/home/aicode/.claude/telegram.yml` |
| `CLAUDEBOX_CRON_MODE` | `1` to start the cron scheduler | _(none)_ |
| `CLAUDEBOX_CRON_MODE_FILE` | Path to the cron YAML inside the container | _(none)_ |
| `CLAUDEBOX_WORKSPACE` | Absolute workspace path (cwd for every mode) | `/workspace` |
| `CLAUDEBOX_ALWAYS_SKILLS_DIR` | Where `SKILL.md` files are scanned for always-active injection | `/home/aicode/.claude/.always-skills` |
| `CLAUDEBOX_SYSTEM_HINT_FILE` | Text prepended to `--append-system-prompt` on every call | `/home/aicode/.claude/system-hint.txt` |
| `DEBUG` | `1`/`true` for structured JSON debug logging | _(none)_ |

Legacy fallbacks still accepted: `CLAUDE_MODE_API`/`CLAUDE_MODE_API_PORT`/`CLAUDE_MODE_API_TOKEN`, `CLAUDE_MODE_TELEGRAM`, `CLAUDE_MODE_CRON`/`CLAUDE_MODE_CRON_FILE`, `CLAUDE_WORKSPACE`, `CLAUDE_TELEGRAM_BOT_TOKEN`, `CLAUDE_TELEGRAM_CONFIG`.

## Ports

| Port | Service |
| --- | --- |
| 8080 (default, `CLAUDEBOX_API_MODE_PORT`) | HTTP API + OpenAI adapter, and MCP (`/mcp`) if `CLAUDEBOX_MCP_MODE=1` is also set |
| 8081 (default, `CLAUDEBOX_MCP_MODE_PORT`) | Standalone MCP, only when `CLAUDEBOX_MCP_MODE=1` is set without `CLAUDEBOX_API_MODE=1` |

MCP either mounts onto the API port or runs on its own port — never both at once, depending on whether API mode is also enabled.

## Cron + Telegram Combined Mode

Set both `CLAUDEBOX_CRON_MODE=1` and `CLAUDEBOX_TELEGRAM_MODE=1` in the same container: a single workspace shared between the cron scheduler (background) and the bot (foreground); when the bot exits, the scheduler is killed too.

- Cron jobs post results to Telegram automatically when `telegram_chat_id` is set (root default and/or per-job override) in `cron.yaml`.
- Reply to a cron notification message to interrogate that run — the bot detects the reply, looks up the original job (name, timestamp, instruction, result), and prepends that context to a fresh session.
- The whole chat gets the last ~10 cron runs injected via `--append-system-prompt`, so Claude can answer cron questions anywhere in the conversation.

Sent message IDs and job context are stored in `~/.claude/cron/telegram_messages.json` (auto-pruned to the last 200 entries).

## MCP Servers claudebox Itself Can Use

Independent of exposing claudebox *as* an MCP server (MCP mode above), Claude Code running inside claudebox can also *consume* MCP servers you configure — same mechanism as any Claude Code install:

| Scope | Path | Notes |
| --- | --- | --- |
| Project | `<workspace>/.mcp.json` | Checked into git, shared by the team |
| User | `~/.claude.json` under `mcpServers` | Global, every project on the host |
| Local | `~/.claude.json` per-project section | Default scope of `claude mcp add` |

```bash
claudebox mcp add --scope project my-server -- npx -y @some/mcp-server
claudebox mcp add --scope user my-server -- npx -y @some/mcp-server
```

Run `/mcp` inside an interactive session to inspect what's loaded. This is how cron and Telegram modes reach external systems (post to Discord/Slack/email/webhooks) — configure the server, reference it from the job instruction or chat.

## Customization

- **Custom scripts (`~/.claude/bin`)** — any executable placed here is on PATH in every mode.
- **Init hooks (`~/.claude/init.d/*.sh`)** — run once as root on first container create, before the entrypoint drops to `aicode`. Good for pre-installing tools on the minimal image.
- **Always-active skills (`~/.claude/.always-skills/`)** — every `SKILL.md` found (recursive, alphabetical) is appended to `--append-system-prompt` on every invocation, across all modes, prefixed with `[Skill file: <path>]`.

## Gotchas

- `--permission-mode bypassPermissions` is the default — Claude has full, unrestricted access to the container. Override per-request via `RunRequest.extra_args` at the API layer.
- SSH keys are mounted from the host for git push/pull. Don't share your container or image with untrusted parties.
- Host paths are preserved — a project at `/home/you/project` mounts at the same path inside the container, so Docker volume mounts Claude creates from within it resolve correctly against the host.
- UID/GID of the `aicode` user auto-adjusts to match the host directory owner at startup.
- The Docker socket is mounted in — Claude can build images and run containers from within its own container, by design.
- Two containers per workspace: `claude-<path>` for interactive (TTY), `claude-<path>_prog` for one-shot exec (no TTY). Both share mounted volumes and data.
- API-mode workspace busy tracking: one active Claude process per workspace; concurrent requests to the same workspace get `409`.
- Telegram mode requires `telegram.yml` to exist — refuses to boot silently exposed.
- Claude Code CLI auto-updates are disabled inside the container by default; opt in with `claudebox --update`.

## Management

```bash
docker logs -f <container>       # tail logs (structured JSON in server modes)
claudebox stop                   # stop the interactive container for this workspace
claudebox clear-session          # delete session history for this workspace
docker pull psyb0t/claudebox:latest       # update (minimal)
docker pull psyb0t/claudebox:latest-full  # update (full)
```
