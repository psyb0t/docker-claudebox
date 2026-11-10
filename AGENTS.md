# docker-claudebox

Instructions for AI agents and people who change this repository. Users of the image start at the [README](README.md) and the [documentation site](https://psyb0t.github.io/docker-claudebox/).

## Agent setup

`CLAUDE.md` is a committed symlink to `AGENTS.md`, and `.claude` is a committed symlink to `.agents`, so Claude Code reads the same instructions, rules and skills as Codex. Claude's Edit and Write tools refuse to write through a symlink, so edit `AGENTS.md` and `.agents/rules/*.md` directly.

## What it is

The Docker image `psyb0t/claudebox` runs Claude Code from an interactive terminal, a one-shot `-p` call, an HTTP API with an OpenAI-compatible endpoint, an MCP server, a Telegram bot, or a cron scheduler. It is a thin child of [`psyb0t/aicodebox`](https://github.com/psyb0t/docker-aicodebox), which owns the runtime user, the four servers, init hooks and mode selection. This repository adds only what is specific to Claude Code, plus `wrapper.sh`, the host command installed as `claudebox`.

The published image does not contain the Claude Code CLI. It is proprietary with no redistribution grant, so the image pins a version and the entrypoint installs it from npm on a container's first start.

## Architecture

- `Dockerfile` (`:latest`, on `psyb0t/aicodebox:latest`) and `Dockerfile.full` (`:latest-full`, on `psyb0t/aicodebox:latest-full`) add the same layer: the `claudebox` Python package, `claudebox/init.d/` copied to `/aicodebox-init.d/`, the launcher, the entrypoint, and the environment (`AICODEBOX_ADAPTER`, `AICODEBOX_AGENT_BINARY`, `CLAUDE_CONFIG_DIR`, `DISABLE_AUTOUPDATER`, `CLAUDEBOX_IMAGE_VARIANT`, `CLAUDEBOX_CLAUDE_VERSION`).
- `claudebox-entrypoint.sh` (installed as `/usr/local/bin/claudebox-entrypoint`, the image `ENTRYPOINT`): copies `CLAUDEBOX_<name>` to `AICODEBOX_<name>` for the names in `_CLAUDEBOX_ALIASES` and the legacy names in `_LEGACY_MODE_MAP`, links `/workspaces` and `~/.claude` to `~/.aicodebox`, runs `npm install -g @anthropic-ai/claude-code@$CLAUDEBOX_CLAUDE_VERSION` when `claude` is missing, then `exec`s the base `aicodebox-entrypoint`.
- `claudebox-agent.sh` (installed as `claudebox-agent`, named by `AICODEBOX_AGENT_BINARY`): the CLI path for interactive and `-p` sessions. Adds `--permission-mode bypassPermissions`, the system hint and always-skills as `--append-system-prompt`, `--continue` with a fresh-session fallback, and handles the wrapper's update and no-continue marker files.
- `claudebox/claudebox/adapter.py`: `ClaudecodeAdapter`, the aicodebox `AgentAdapter` for the server modes. `build_argv` turns a `RunRequest` into a `claude -p --output-format stream-json` command line, `parse_output`, `parse_events` and `parse_stream_event` read Claude's native stream. Server modes never go through the launcher.
- `claudebox/init.d/`: first-start scripts the base runs once per container: `.claude.json` patch, workspace `CLAUDE.md` seed from `claudebox/templates/`, always-skills directory and default system hint.
- `wrapper.sh`: the host command. Resolves the image, names containers after `$PWD`, mounts the workspace, `~/.claude`, `~/.ssh/claudebox` and the Docker socket, forwards `CLAUDEBOX_ENV_*` and `AICODEBOX_ENV_*`, validates `-p` flags, and creates or restarts the interactive, `_prog` and `_cron` containers.
- `install.sh`: pulls the image, creates `~/.claude` and the SSH key, downloads or copies `wrapper.sh`, writes the chosen variant into it, and installs it with sudo.
- `action.yml`: a composite GitHub Action that runs `wrapper.sh` one-shot on a read-only context directory.

Data flow, CLI: `claudebox` (wrapper) -> `docker run` or `docker start` -> `claudebox-entrypoint` -> `aicodebox-entrypoint` -> `claudebox-agent` -> `claude`.
Data flow, servers: client -> aicodebox API, MCP, Telegram or cron server -> `ClaudecodeAdapter.build_argv` -> `claude -p` -> adapter parsers -> response.

## Stack

- Bash for the wrapper, installer, entrypoint, launcher, init scripts and tests.
- Python 3.12 or newer for the adapter (`requires-python` in `claudebox/pyproject.toml`), with no runtime dependencies beyond the base's `aicodebox` package. Dev tools pinned in the `dev` dependency group: pytest, ruff, pyright. `uv` manages the lockfile.
- Runtime: the aicodebox base (Ubuntu 24.04, Python, Node, Docker CLI, `jq`). Claude Code comes from npm at first start.
- Images: `linux/amd64` and `linux/arm64`, built and published by `.github/workflows/pipeline.yml` through `psyb0t/reusable-github-workflows`.
- Docs: Jekyll on GitHub Pages with the just-the-docs theme, from `docs/`.

## Layout

| Path | What it holds |
| --- | --- |
| `Dockerfile`, `Dockerfile.full` | The minimal and full images |
| `Dockerfile.dev` | Development image for `make lint` and `make test-ci`, never published |
| `claudebox-entrypoint.sh`, `claudebox-agent.sh` | Image entrypoint and CLI launcher |
| `claudebox/claudebox/` | The adapter package |
| `claudebox/tests/` | Adapter unit tests (pytest) |
| `claudebox/init.d/`, `claudebox/templates/` | First-start scripts and workspace `CLAUDE.md` templates |
| `claudebox/pyproject.toml`, `claudebox/uv.lock` | Package metadata, the version, dev tools, ruff and pyright settings |
| `wrapper.sh`, `install.sh` | Host command and installer |
| `action.yml`, `stream-log.jq` | GitHub Action and its log formatter |
| `cron.yml.example`, `telegram.yml.example`, `.env.example` | Annotated configuration examples |
| `tests/` | Shell test suites. `test.sh` at the root runs the credentialed ones. |
| `tests/programmatic/` | Native output contract and first-start install output checks |
| `docs/` | Documentation site source (`_config.yml`, `_sass/`, pages, `llms.txt`, `404.md`) |
| `.agents/skills/claudebox/` | The agent skill, published to ClawHub |
| `.agents/plugins/claudebox/` | The OpenClaw stdio-to-HTTP MCP bridge, published to ClawHub |
| `.agents/.claude-plugin/`, `.agents/.codex-plugin/` | Claude Code and Codex plugin manifests |
| `.agents/rules/` | Rules for changes to this repository |
| `server.json`, `glama.json` | MCP registry and Glama listings |
| `.github/workflows/` | CI pipeline, mirroring, issue sync, PR policy |
| `THIRD_PARTY.md`, `LICENSES/` | Third-party notices |

## Commands

Docker, Make and Git on the host are enough for everything except `make test-unit`.

```bash
make help                # every target
make build               # psyb0t/claudebox:latest and :v<version>
make build-full          # psyb0t/claudebox:latest-full and :v<version>-full
make lint                # shellcheck, shfmt, ruff, pyright (containers)
make format              # shfmt -w and ruff format
make test-ci             # credential-free tests, what CI runs (containers)
make test-unit           # adapter tests with uv and a sibling docker-aicodebox checkout
make docs                # build the docs site into .testing/docs-site
make version V=X.Y.Z     # set the version in pyproject, the Codex manifest and install.sh
```

`./test.sh` runs the end-to-end suites against real Claude Code and needs `tests/.env` with a `CLAUDE_CODE_OAUTH_TOKEN`. It is never part of CI.

## Rules

Rules for every change are in `.agents/rules/`, one file per topic. Read the ones that match what you are about to touch before editing.
