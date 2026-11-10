---
title: "Home"
description: "claudebox runs Claude Code in Docker from a terminal, a script, an HTTP API, an MCP server, a Telegram bot or a cron schedule, in minimal or full images."
nav_order: 1
permalink: /
seo:
  type: WebSite
---

# claudebox

Run [Claude Code](https://claude.com/product/claude-code) in Docker, from an interactive terminal, a script, an HTTP client, MCP, Telegram, or a cron schedule. The image `psyb0t/claudebox` adds the Claude-specific parts to the shared [aicodebox](https://psyb0t.github.io/docker-aicodebox/) runtime: an adapter that turns requests into `claude` command lines, a launcher that restores session resumption and the permission bypass, first-start setup, and `CLAUDEBOX_*` names for the shared settings.

The `claudebox` wrapper on the host mounts your current directory, keeps Claude state and SSH keys between runs, and resumes the workspace's last session by default.

**Not a security sandbox.** The standard wrapper uses host networking, mounts the host Docker socket, gives Claude passwordless sudo, and bypasses Claude's permission prompts. Use it only with trusted workloads. Separate workspace directories do not isolate untrusted tenants. The server examples on this site leave the Docker socket out. See [Host access and server deployment](wrapper.md#host-access-and-server-deployment).

## Quick start

You need Bash, a running Docker daemon your user can reach, curl, `ssh-keygen`, and sudo to install the wrapper.

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash
```

Then run it from the directory Claude should work in:

```bash
cd /path/to/project
claudebox
```

Log in inside Claude Code, or export `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` first. One prompt, no TTY:

```bash
claudebox -p "explain this codebase"
claudebox -p "review this codebase" --output-format json
```

[Installation and wrapper](wrapper.md) covers the full image, a reviewed install, image selection and the container lifecycle.

## Image variants

| Image | Contents |
| --- | --- |
| `psyb0t/claudebox:latest` | The minimal aicodebox runtime, the Claude adapter and the first-start setup. |
| `psyb0t/claudebox:latest-full` | The same, on the aicodebox full base with Go, Python, Node, C/C++, infrastructure and database tools. |

Neither image contains the Claude Code CLI. Claude Code is proprietary, so each container installs the pinned version from npm the first time it starts, and that first start needs network access. Releases also publish `:vX.Y.Z` and `:vX.Y.Z-full`.

## Ways to run it

| Interface | Page |
| --- | --- |
| Interactive terminal with persistent sessions | [Interactive mode](modes/interactive.md) |
| One prompt with text, JSON, or native NDJSON output | [Programmatic mode](modes/programmatic.md) |
| HTTP `/run`, files, async polling, and OpenAI-compatible chat | [API mode](modes/api.md) |
| Streamable HTTP tools for other agents | [MCP mode](modes/mcp.md) |
| Chat workspaces, attachments, and access lists | [Telegram mode](modes/telegram.md) |
| Scheduled jobs and durable run artifacts | [Cron mode](modes/cron.md) |

[Modes](modes.md) explains how the container picks one and which ones combine.

## Reference

- [Environment variables](environment-variables.md): wrapper settings, forwarded variables, extra mounts and sibling boxes.
- [Customization](customization.md): your own scripts, first-start init hooks, always-active skills and external MCP servers.
- [GitHub Action](github-action.md): one-shot jobs with a read-only context and a writable output directory.
- [Agent integrations](agent-integrations.md): the skill and plugins for Claude Code, Codex and OpenClaw.
- [Architecture](architecture.md): what claudebox adds to the aicodebox base, and what happens when a container starts.
- [Troubleshooting](troubleshooting.md): error messages from the wrapper, the entrypoint and the servers, with their fixes.
- [Upgrading](upgrading.md): the old `docker-claude-code` names, the v2 image swap, and the legacy variables that still work.
- [Development](development.md): build, lint and test from source, and what CI runs.
