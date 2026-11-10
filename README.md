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

For a reviewed local install, a custom command name, image overrides, or wrapper updates, see [Installation and wrapper](https://psyb0t.github.io/docker-claudebox/wrapper/). The remote installer currently fetches the wrapper from its embedded release ref, not necessarily `master`.

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

The wrapper supports a defined set of flags, not every native Claude Code argument. See [Programmatic mode](https://psyb0t.github.io/docker-claudebox/modes/programmatic/) for output formats, model selection, and session control.

## Image variants

| Image | Contents |
| --- | --- |
| `psyb0t/claudebox:latest` | Minimal aicodebox runtime, Claude adapter, and first-start setup. |
| `psyb0t/claudebox:latest-full` | The same Claude interfaces plus aicodebox's shared development toolchain. |

The full variant adds Go and its tools, Python and Node development tools, C/C++ tools, infrastructure tools, database clients, and shell utilities. The shared [Dockerfile.full](https://github.com/psyb0t/docker-aicodebox/blob/main/Dockerfile.full) and lockfiles own the package inventory. Neither Claudebox variant bundles the Claude Code CLI in the published image.

Set `CLAUDEBOX_IMAGE` to use an explicit image tag or digest. An existing container keeps its original image and launch configuration until recreated. See [Wrapper lifecycle](https://psyb0t.github.io/docker-claudebox/wrapper/#container-lifecycle).

## Modes

| Interface | Guide |
| --- | --- |
| Interactive terminal with persistent sessions | [Interactive mode](https://psyb0t.github.io/docker-claudebox/modes/interactive/) |
| One prompt with text, JSON, or native NDJSON output | [Programmatic mode](https://psyb0t.github.io/docker-claudebox/modes/programmatic/) |
| HTTP `/run`, files, async polling, and OpenAI-compatible chat | [API mode](https://psyb0t.github.io/docker-claudebox/modes/api/) |
| Streamable HTTP tools for other agents | [MCP mode](https://psyb0t.github.io/docker-claudebox/modes/mcp/) |
| Chat workspaces, attachments, and access lists | [Telegram mode](https://psyb0t.github.io/docker-claudebox/modes/telegram/) |
| Scheduled jobs and durable run artifacts | [Cron mode](https://psyb0t.github.io/docker-claudebox/modes/cron/) |

API and MCP authentication are independent. An unset token leaves its endpoint open. Configure explicit Telegram chat access too. Use the loopback-bound deployment examples in each mode guide before exposing a server.

## Documentation

The full documentation lives at **[psyb0t.github.io/docker-claudebox](https://psyb0t.github.io/docker-claudebox/)**.

| Section | Covers |
| --- | --- |
| [Installation and wrapper](https://psyb0t.github.io/docker-claudebox/wrapper/) | Install routes, image selection, authentication, Git identity, container lifecycle, host access |
| [Modes](https://psyb0t.github.io/docker-claudebox/modes/) | How the container picks a mode, and one page per mode |
| [Environment variables](https://psyb0t.github.io/docker-claudebox/environment-variables/) | Wrapper settings, forwarded variables, extra mounts, sibling boxes |
| [Customization](https://psyb0t.github.io/docker-claudebox/customization/) | Your own scripts, init hooks, always-active skills, external MCP servers |
| [GitHub Action](https://psyb0t.github.io/docker-claudebox/github-action/) | One-shot jobs with a read-only context and a writable output directory |
| [Agent integrations](https://psyb0t.github.io/docker-claudebox/agent-integrations/) | The skill and plugins for Claude Code, Codex and OpenClaw |
| [Architecture](https://psyb0t.github.io/docker-claudebox/architecture/) | What claudebox adds to aicodebox, and the startup order |
| [Troubleshooting](https://psyb0t.github.io/docker-claudebox/troubleshooting/) | Error messages and their fixes |
| [Upgrading](https://psyb0t.github.io/docker-claudebox/upgrading/) | The old `docker-claude-code` names, v2 changes, legacy variables |
| [Development](https://psyb0t.github.io/docker-claudebox/development/) | Building, lint, tests and CI |

## Development

```bash
make help
make build
make lint
make test-ci
```

`make lint` and `make test-ci` run in containers and need only Docker. See [Development](https://psyb0t.github.io/docker-claudebox/development/) for the other test suites and base-image overrides.

## Sponsor

<a href="https://www.buymeacoffee.com/psyb0t"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-blue.png" alt="Buy Me a Coffee" height="60" width="217"></a>

## License

[WTFPL](https://github.com/psyb0t/docker-claudebox/blob/master/LICENSE). Previously named `docker-claude-code` with the image `psyb0t/claude-code`; see [Upgrading](https://psyb0t.github.io/docker-claudebox/upgrading/) and the [CHANGELOG](https://github.com/psyb0t/docker-claudebox/blob/master/CHANGELOG.md).
