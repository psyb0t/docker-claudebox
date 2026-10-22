# claudebox

[![CI](https://github.com/psyb0t/docker-claudebox/actions/workflows/pipeline.yml/badge.svg?branch=master)](https://github.com/psyb0t/docker-claudebox/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-claudebox/badges/version.svg)](https://github.com/psyb0t/docker-claudebox/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-claudebox/badges/license.svg)](https://github.com/psyb0t/docker-claudebox/blob/master/LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/claudebox?style=flat-square)](https://hub.docker.com/r/psyb0t/claudebox)

Run [Claude Code](https://claude.com/product/claude-code) in Docker, from an interactive terminal, a script, an HTTP client, MCP, Telegram, or a cron schedule. Claudebox adds Claude-specific setup to the shared [aicodebox](https://github.com/psyb0t/docker-aicodebox) runtime.

The wrapper mounts your current directory, persists Claude state and SSH keys, and resumes the workspace's last session by default.

**Not a security sandbox:** the standard wrapper uses host networking, mounts the host Docker socket, gives Claude passwordless sudo, and bypasses Claude's permission prompts. Use it only with trusted workloads. Separate workspace directories do not isolate untrusted tenants. Server examples omit the Docker socket.

## Install

You need Bash, Docker running and accessible to your user, curl, SSH key-generation tools, and sudo permission to install the wrapper. The installer pulls the image, creates Claude state and an SSH key, and installs the `claudebox` command.

Minimal image, the default:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash
```

Full development image:

```bash
export CLAUDEBOX_FULL=1 && curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash
```

The full-image choice stays in the installed wrapper. Both variants install the pinned Claude Code CLI from npm when a fresh container first starts, so that start needs network access.

For a reviewed local install, a custom command name, image overrides, or wrapper updates, see [Installation and wrapper](https://github.com/psyb0t/docker-claudebox/blob/master/docs/wrapper.md). The remote installer currently fetches the wrapper from its embedded release ref, not necessarily `master`.

## First run

Run from the directory Claude should work in:

```bash
cd /path/to/project
claudebox
```

Authenticate in Claude Code, or supply `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` through your environment. `claudebox setup-token` runs Claude Code's OAuth token flow; keep the resulting token in a secret store and export it when needed.

```bash
claudebox --no-continue
claudebox -p "explain this codebase"
claudebox -p "review this codebase" --output-format json
claudebox -p "inspect the workspace" --output-format stream-json
claudebox stop
```

The wrapper supports a defined set of flags, not every native Claude Code argument. See [Programmatic mode](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/programmatic.md) for output formats, model selection, and session control.

## Image variants

| Image | Contents |
| --- | --- |
| `psyb0t/claudebox:latest` | Minimal aicodebox runtime, Claude adapter, and first-start setup. |
| `psyb0t/claudebox:latest-full` | The same Claude interfaces plus aicodebox's shared development toolchain. |

The full variant adds Go and its tools, Python and Node development tools, C/C++ tools, infrastructure tools, database clients, and shell utilities. The shared [Dockerfile.full](https://github.com/psyb0t/docker-aicodebox/blob/main/Dockerfile.full) and lockfiles own the package inventory. Neither Claudebox variant bundles the Claude Code CLI in the published image.

Set `CLAUDEBOX_IMAGE` to use an explicit image tag or digest. An existing container keeps its original image and launch configuration until recreated. See [Wrapper lifecycle](https://github.com/psyb0t/docker-claudebox/blob/master/docs/wrapper.md#container-lifecycle).

## Modes

| Interface | Guide |
| --- | --- |
| Interactive terminal with persistent sessions | [Interactive mode](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/interactive.md) |
| One prompt with text, JSON, or native NDJSON output | [Programmatic mode](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/programmatic.md) |
| HTTP `/run`, files, async polling, and OpenAI-compatible chat | [API mode](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/api.md) |
| Streamable HTTP tools for other agents | [MCP mode](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/mcp.md) |
| Chat workspaces, attachments, and access lists | [Telegram mode](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/telegram.md) |
| Scheduled jobs and durable run artifacts | [Cron mode](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/cron.md) |

For all native events from HTTP `POST /run`, request `"eventMode": "full"`. This works with or without `jsonSchema`. Events include the records Claude Code emits, such as tool calls, tool results, and available thinking content. It does not expose private reasoning that the CLI does not emit. `/run` returns a completed JSON response; use native `stream-json` for direct CLI streaming or the OpenAI endpoint's opt-in native SSE events.

API and MCP authentication are independent. An unset token leaves its endpoint open. Configure explicit Telegram chat access too. Use the loopback-bound deployment examples in each mode guide before exposing a server.

## Configuration and extensions

- [Environment variables](https://github.com/psyb0t/docker-claudebox/blob/master/docs/environment-variables.md): wrapper settings, forwarded variables, extra mounts, and sibling boxes.
- [Customization](https://github.com/psyb0t/docker-claudebox/blob/master/docs/customization.md): user scripts, first-container init hooks, always-active skills, and external MCP servers.
- [GitHub Action](https://github.com/psyb0t/docker-claudebox/blob/master/docs/github-action.md): one-shot jobs with a read-only context and a writable output directory.
- [Agent integrations](https://github.com/psyb0t/docker-claudebox/blob/master/docs/agent-integrations.md): local wrapper skills and remote MCP connections for Claude Code, Codex, and OpenClaw.

Install sibling `claudebox`, `codexbox`, and `pibox` wrappers in the same command directory for nested launches. Each sibling mounts its own host state. Do not manually set `AICODEBOX_HOST_*`.

## Development

```bash
make help
make test-unit
make test-image-select
make test-programmatic-contract
make test-agent-launcher
make build
make build-full
```

Builds use the minimal or full aicodebox parent respectively. See [Makefile](https://github.com/psyb0t/docker-claudebox/blob/master/Makefile) for base-image overrides and the remaining checks. The adapter lives in [claudebox/claudebox/adapter.py](https://github.com/psyb0t/docker-claudebox/blob/master/claudebox/claudebox/adapter.py); the shared server modes live in aicodebox.

## Migration and license

Previously named `docker-claude-code` with image `psyb0t/claude-code`. Current names are `docker-claudebox`, `psyb0t/claudebox`, and `claudebox`. In v2, `latest` became minimal and `latest-full` became the full variant. See [CHANGELOG.md](https://github.com/psyb0t/docker-claudebox/blob/master/CHANGELOG.md) for migration history.

[WTFPL](https://github.com/psyb0t/docker-claudebox/blob/master/LICENSE).
