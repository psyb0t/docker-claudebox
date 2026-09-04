# claudebox

[![CI](https://github.com/psyb0t/docker-claudebox/actions/workflows/pipeline.yml/badge.svg?branch=master)](https://github.com/psyb0t/docker-claudebox/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-claudebox/badges/version.svg)](https://github.com/psyb0t/docker-claudebox/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-claudebox/badges/license.svg)](LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/claudebox?style=flat-square)](https://hub.docker.com/r/psyb0t/claudebox)

A runtime harness for [Claude Code](https://claude.com/product/claude-code) — the agentic coding CLI from Anthropic — running in a fully isolated Docker container with every dev tool pre-installed, passwordless sudo, docker-in-docker support, and `--permission-mode bypassPermissions` enabled by default.

> **v2.0.0 — rebased on `psyb0t/aicodebox`.** claudebox is now a thin child image of the shared aicodebox base (same pattern as `psyb0t/pibox`). Every mode surface (API / Telegram / Cron / MCP) is inherited from the base and stays in lockstep with future base fixes. See [`CHANGELOG.md`](CHANGELOG.md) for the full migration guide (endpoint shape changes, env-var namespace, path renames — all mitigated by aliases + symlinks so existing configs keep working).

**Runtime hardening (recommended `docker run` flags):**
- `--cap-drop=ALL --cap-add=NET_BIND_SERVICE` — drop every Linux capability, add back only bind-below-1024 if you actually need it.
- `--security-opt no-new-privileges:true` — block setuid privilege escalation inside the container.
- `--memory=2g --cpus=2 --pids-limit=512` — cap runtime resource use so a runaway process can't starve the host.
- `--read-only --tmpfs /tmp:rw,noexec,nosuid` (only if you don't use `/workspace` for writes — otherwise skip).
The container drops from root to `aicode` (UID 1000) at boot via `setpriv` in the base entrypoint, so the process running your code is never root even without `--user`.

claudebox wraps Claude Code with several distinct interfaces:

- **Interactive CLI** — a drop-in replacement for the native `claude` command, with persistent containers and automatic session resumption across runs
- **Programmatic CLI** — non-interactive mode for scripts, CI/CD pipelines, and automation; pass a prompt, get structured output, pipe it wherever you need
- **HTTP API server** — a full REST API with workspace management, file operations, structured output formats, and workspace isolation for multi-tenant deployments
- **OpenAI-compatible endpoint** — a `chat/completions` adapter that lets LiteLLM, OpenAI SDKs, and any OpenAI-compatible client talk to Claude Code, complete with streaming SSE, multi-turn conversations, and multimodal image handling
- **MCP server** — a [Model Context Protocol](https://modelcontextprotocol.io/) endpoint over streamable HTTP so other AI agents and tools (Claude Desktop, other Claude Code instances, etc.) can use Claude Code as a tool
- **Telegram bot** — a conversational interface with per-chat workspaces, configurable models and effort levels, file sharing, shell access, and group chat support
- **Cron scheduler** — yaml-defined Claude jobs running on cron schedules with per-job activity history, sub-minute resolution, and overlap protection

Beyond just running Claude Code in Docker, claudebox adds skill injection (auto-load `SKILL.md` files into every session), init hooks, custom script directories, structured JSON logging, and a workspace management layer that handles multi-tenant isolation with automatic busy/idle tracking.

> **Renamed from `docker-claude-code`:** This project was previously called `docker-claude-code` with the Docker image at `psyb0t/claude-code`. Starting with v1.0.0, it is `claudebox` — the Docker image is now `psyb0t/claudebox`, the default binary name is `claudebox`, the GitHub repository is `psyb0t/docker-claudebox`, and the SSH key directory defaults to `~/.ssh/claudebox`. If you were using the old names, update your image references, wrapper scripts, and SSH paths accordingly.

## Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Image Variants](#image-variants)
- [What's Inside (Full Image)](#whats-inside-full-image)
- [Authentication](#authentication)
- [Modes](#modes)
  - [Interactive mode](docs/modes/interactive.md)
  - [Programmatic mode](docs/modes/programmatic.md)
  - [API mode](docs/modes/api.md)
  - [Telegram mode](docs/modes/telegram.md)
  - [Cron mode](docs/modes/cron.md)
  - [MCP mode](docs/modes/mcp.md)
- [Configuration](#configuration)
- [Agent integrations](#agent-integrations)
- [Gotchas](#gotchas)
- [License](#license)

## Requirements

Docker installed and running. That's it.

## Quick Start

### One-liner install

The install script pulls the Docker image, generates SSH keys for git operations inside the container, downloads the wrapper script, and installs it as a command on your system.

```bash
# minimal image — default; Claude installs what it needs on the fly
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash

# full image — every dev tool pre-installed (Go, Python, kubectl, terraform, ...)
export CLAUDEBOX_FULL=1 && curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash

# custom binary name (e.g. if you want to call it 'claude' instead of 'claudebox')
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash -s -- claude
# or: export CLAUDEBOX_BIN_NAME=claude && curl -fsSL .../install.sh | bash
```

> **v2 note:** the variant naming flipped in v2. `latest` is now the minimal image (was the full image pre-v2); `latest-full` is the toolchain-loaded variant (was `latest` pre-v2). The `CLAUDEBOX_MINIMAL=1` opt-in from v1 is now a no-op — you already get minimal by default. Set `CLAUDEBOX_FULL=1` to opt into the toolchain image. Installing with `CLAUDEBOX_FULL=1` (as above) bakes the choice into the installed wrapper, so the full variant sticks for every run — you don't need to keep the env var set afterward.

> **Heads up on env vars:** `VAR=x curl … | bash` does **not** set `VAR` for the install script — bash semantics attach the var to `curl` only. Always `export` the var first (or put it on the `bash` side of the pipe).

### Manual setup

If you prefer not to pipe scripts to bash:

```bash
# 1. create the data directory
mkdir -p ~/.claude

# 2. create SSH keys for git operations inside the container
mkdir -p "$HOME/.ssh/claudebox"
ssh-keygen -t ed25519 -C "claude@claude.ai" -f "$HOME/.ssh/claudebox/id_ed25519" -N ""
# then add the public key to GitHub/GitLab/wherever you push code

# 3. pull the image
docker pull psyb0t/claudebox:latest        # minimal (default)
# or: docker pull psyb0t/claudebox:latest-full   # toolchain-loaded variant

# 4. grab the wrapper script and install it
# see install.sh for exactly how the wrapper is set up
```

## Image Variants

### `psyb0t/claudebox:latest` (minimal, default)

The default v2 image. Just enough to run Claude Code on top of the aicodebox base: Ubuntu 24.04, git/curl/wget/jq, Node.js 22 LTS + npm, Python 3.12 + uv, Docker CE. Claude has passwordless sudo, so it will install whatever else it needs on the fly via `apt-get`, `pip`, `npm`, etc. Smaller image, faster pull, first run may take longer while Claude sorts out its own tooling.

> **Claude Code is installed on first run, not baked into the image.** Anthropic's Claude Code CLI is proprietary and can't be redistributed, so the image ships only the pinned version (`CLAUDEBOX_CLAUDE_VERSION`, default set at build) and the entrypoint runs `npm install -g @anthropic-ai/claude-code@<version>` from npm the first time a fresh container starts. This means the published image redistributes none of Anthropic's software, and each container pulls Claude Code straight from npm. First container start needs network and takes a few extra seconds; warm restarts skip it. To pin a different version, set `CLAUDEBOX_CLAUDE_VERSION` at `docker run`.

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash
```

Use `/aicodebox-init.d/*.sh` hooks (see [Init Hooks](docs/customization.md#init-hooks-claudeinitd)) to pre-install your tools on first container create so Claude doesn't burn tokens figuring out package management.

### `psyb0t/claudebox:latest-full` (toolchain-loaded)

Everything pre-installed. Layered on top of the minimal image: Go 1.26.5, Python 3.12.13 via pyenv, Node.js dev tools, C/C++ toolchain, terraform, kubectl, helm, gh, database clients (sqlite/postgres/mysql/redis), editors (vim/nano/htop/tmux), linters + formatters (flake8/black/isort/pyright/mypy/ruff/eslint/prettier/gofumpt/…). Larger image but Claude wakes up ready.

```bash
export CLAUDEBOX_FULL=1 && curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash
```

### Comparison

|                                       | `latest` (minimal) | `latest-full` |
| ------------------------------------- | :----------------: | :-----------: |
| Ubuntu 24.04                          |       yes       |       yes        |
| git, curl, wget, jq                   |       yes       |       yes        |
| Node.js LTS + npm                     |       yes       |       yes        |
| Docker CE + Compose                   |       yes       |       yes        |
| Claude Code CLI                       |       yes       |       yes        |
| Go 1.26.5 + tools                     |       yes       |        -         |
| Python 3.12.13 + tools                |       yes       |        -         |
| Node.js dev tools                     |       yes       |        -         |
| C/C++ tools                           |       yes       |        -         |
| DevOps (terraform, kubectl, helm, gh) |       yes       |        -         |
| Database clients                      |       yes       |        -         |
| Shell utilities (ripgrep, bat, etc.)  |       yes       |        -         |

## What's Inside (Full Image)

**Languages and runtimes:**

- **Go 1.26.5** with the full toolchain — golangci-lint, gopls, delve, staticcheck, gofumpt, gotests, impl, gomodifytags
- **Python 3.12.13** via pyenv — flake8, black, isort, autoflake, pyright, mypy, vulture, pytest, poetry, pipenv, plus common libraries (requests, beautifulsoup4, lxml, pyyaml, toml)
- **Node.js LTS** — eslint, prettier, typescript, ts-node, yarn, pnpm, nodemon, pm2, framework CLIs (React, Vue, Angular), newman, http-server, serve, lighthouse, storybook
- **C/C++** — gcc, g++, make, cmake, clang-format, valgrind, gdb, strace, ltrace

**DevOps and infrastructure:**

- Docker CE with Docker Compose (docker-in-docker support)
- Terraform, kubectl, helm, GitHub CLI (`gh`)

**Database clients:**

- sqlite3, postgresql-client (`psql`), mysql-client, redis-tools (`redis-cli`)

**Shell and system utilities:**

- jq, tree, ripgrep, bat, exa, fd-find, ag (silversearcher), htop, tmux, shellcheck, shfmt, httpie, vim, nano
- Archive tools (zip, unzip, tar), networking (net-tools, iputils-ping, dnsutils)

**Container automation:**

- Auto-generated `CLAUDE.md` in each workspace listing all available tools, so Claude knows what it has access to
- Git identity auto-configured from environment variables
- Claude Code CLI with auto-updates disabled by default (opt in with `--update`)
- Workspace trust dialog pre-accepted — no interactive prompts
- Custom scripts via `~/.claude/bin` (added to PATH automatically)
- Init hooks via `~/.claude/init.d/*.sh` (run once on first container create)
- Always-active skills via `~/.claude/.always-skills/` (injected into every invocation)
- Session continuity via `--continue` / `--no-continue` / `--resume <session_id>`
- Structured JSON debug logging with `DEBUG=true`

## Authentication

You need either an Anthropic API key or an OAuth token. Set up once, use everywhere:

```bash
# interactive OAuth token setup (one-time)
claudebox setup-token

# then use the token for programmatic and headless runs
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-xxx claudebox "do stuff"

# or use an API key directly
ANTHROPIC_API_KEY=sk-ant-api03-xxx claudebox "do stuff"
```

## Modes

claudebox can run in several modes — pick the one that matches how you want to use Claude Code. Each has its own page with full setup, env vars, and examples.

### [Interactive Mode →](docs/modes/interactive.md)

Drop-in replacement for `claude`. Persistent per-workspace container, automatic session resumption, plus utility commands like `claudebox doctor`, `claudebox mcp list`, `claudebox stop`, and `claudebox clear-session`.

```bash
claudebox
```

### [Programmatic Mode →](docs/modes/programmatic.md)

Non-interactive prompt → response for scripts, pipelines, and automation. Plain text, JSON, and native stream-json output formats. Model selection, system prompt overrides, JSON-schema-constrained output, and session continuation. For a stable full-event response, use API mode with `eventMode: "full"`.

```bash
claudebox "explain this codebase" --output-format json --model haiku
```

### [API Mode →](docs/modes/api.md)

Run as a long-lived HTTP server. Full REST API for prompts and file ops with workspace isolation, async runs with run-id polling, OpenAI-compatible `chat/completions` endpoint (streaming + multimodal + LiteLLM compatible), and an [MCP](https://modelcontextprotocol.io/) endpoint over streamable HTTP so other agents can use Claude Code as a tool.

```yaml
environment:
  - CLAUDEBOX_API_MODE=1
  - CLAUDEBOX_API_MODE_TOKEN=your-secret-token
```

### [Telegram Mode →](docs/modes/telegram.md)

Talk to Claude from Telegram. Per-chat isolated workspaces, configurable models/effort/system-prompts per chat, allowed-chats and per-chat allowed-users gating, file/photo/video/voice ingestion, `/fetch`, `/cancel`, `/status`, `/config`, `/reload` commands, and `[SEND_FILE: path]` for Claude to send files back.

```yaml
environment:
  - CLAUDEBOX_TELEGRAM_MODE=1
  - CLAUDEBOX_TELEGRAM_MODE_TOKEN=...
```

### [Cron Mode →](docs/modes/cron.md)

YAML-defined scheduled jobs. Standard 5-field cron or 6-field for sub-minute resolution. Per-job stream-json history under `~/.claude/cron/history/<workspace-slug>/<ts>-<job>/`, foreground process so `docker logs` shows every tick, overlap protection. Set `model` at the root of the YAML as a default for all jobs; override per-job as needed.

```yaml
environment:
  - CLAUDEBOX_CRON_MODE=1
  - CLAUDEBOX_CRON_MODE_FILE=/home/aicode/.claude/cron.yaml
```

### [MCP Mode →](docs/modes/mcp.md)

Expose Claude Code as an [MCP](https://modelcontextprotocol.io/) server over streamable HTTP, so other agents can drive it as a tool — `run_prompt` plus workspace-confined file tools. Not a foreground mode: it runs as a sidecar alongside telegram, cron or interactive on its own port, and is already mounted at `/mcp` on the API port when the foreground is API mode.

```yaml
environment:
  - CLAUDEBOX_MCP_MODE=1
  - CLAUDEBOX_MCP_MODE_TOKEN=your-secret-token
```

## Configuration

- **[Environment variables →](docs/environment-variables.md)** — full table of `CLAUDEBOX_*` settings the wrapper and entrypoint understand, plus `CLAUDEBOX_ENV_*` (forward arbitrary vars into the container) and `CLAUDEBOX_MOUNT_*` (extra volume mounts).
- **[Customization →](docs/customization.md)** — extend Claude's container with custom scripts (`~/.claude/bin`), one-time init hooks (`~/.claude/init.d`), always-active skills auto-injected into every session (`~/.claude/.always-skills`), and MCP server definitions (project `.mcp.json` or global `~/.claude.json`).

## Agent integrations

The [skill](.agents/skills/claudebox) works in any agent that reads `.agents/skills/`, and installs natively in the clients below.

### Claude Code

```bash
claude plugin marketplace add psyb0t/agents
claude plugin install claudebox@psyb0t
```

Claude Code prompts for the claudebox server URL and, if the MCP surface has auth enabled, the bearer token — the token is stored in your OS keychain.

### Codex

```bash
codex plugin marketplace add psyb0t/agents
codex plugin add claudebox@psyb0t
```

Installed via the marketplace, the skill invokes as `$claudebox:claudebox`. Codex also picks the skill up automatically, with no install, in any repo containing `.agents/skills/` — there it invokes as plain `$claudebox`.

### OpenClaw

The skill is published to ClawHub on every release:

```bash
openclaw skills install @psyb0t/claudebox
```

For MCP clients that speak local stdio, the [`@psyb0t/claudebox`](.agents/plugins/claudebox) plugin bridges to the service's `/mcp` endpoint:

```bash
openclaw plugins install clawhub:@psyb0t/claudebox
```

Then set `CLAUDEBOX_URL` (and `CLAUDEBOX_MCP_MODE_TOKEN` if the server requires auth).

## Gotchas

- **`--permission-mode bypassPermissions`** is the adapter's default (modern equivalent of the pre-v2 `--dangerously-skip-permissions`). Claude has full, unrestricted access to the container. That's the entire point. Override per-request via `RunRequest.extra_args`.
- **SSH keys** are mounted from the host for git push/pull inside the container. Do not share your container or image with untrusted parties.
- **Host paths are preserved** — your project at `/home/you/project` is mounted at the same path inside the container. This means Docker volume mounts that Claude creates from within the container resolve correctly against host paths.
- **UID/GID matching** — the container's `claude` user UID/GID is automatically adjusted to match the host directory owner on startup. File permissions should just work without manual `chown`.
- **Docker-in-Docker** — the Docker socket is mounted into the container. Claude can build images and run containers from within its container. This is by design.
- **Two containers per workspace** — the wrapper creates `claude-<path>` for interactive (TTY) sessions and `claude-<path>_prog` for programmatic (no TTY) sessions. Both share the same mounted volumes and data.
- **Workspace busy tracking** — in API mode, each workspace can only have one active Claude process at a time. Concurrent requests to the same workspace return a 409 Conflict response. Use different workspace subpaths for parallel work.
- **Telegram config is required** — the Telegram bot will not start without a `telegram.yml` config file. This is intentional to prevent accidentally exposing Claude to the public.
- **Auto-updates disabled** — Claude Code CLI auto-updates are disabled by default inside the container to ensure reproducible behavior. Opt in with `claudebox --update` when you want to update.

## License

[WTFPL](http://www.wtfpl.net/) — do what the fuck you want to.
