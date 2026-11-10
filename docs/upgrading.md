---
title: "Upgrading"
description: "Update the claudebox image and wrapper, move from docker-claude-code and v1, and the legacy variable names, paths and endpoints that still work."
nav_order: 10
---

# Upgrading

## Updating the image and the wrapper

The image and the wrapper update separately.

- **Image.** `docker pull psyb0t/claudebox:latest`, or `:latest-full`. An existing container keeps the image it was created from, so replace that container afterwards, as [Container lifecycle](wrapper.md#container-lifecycle) describes. A new container installs the Claude Code version pinned by the new image.
- **Wrapper.** Run the installer again. It replaces the installed `claudebox` command, keeps your state directory, and asks before replacing your SSH key.
- **Claude Code alone.** `claudebox --update` updates the CLI inside the interactive container for this workspace, without a new image.

The [CHANGELOG](https://github.com/psyb0t/docker-claudebox/blob/master/CHANGELOG.md) lists every release with its changes.

## From docker-claude-code

The project used to be `docker-claude-code`, with the image `psyb0t/claude-code`. The names now are:

| Before | Now |
| --- | --- |
| Repository `psyb0t/docker-claude-code` | `psyb0t/docker-claudebox` |
| Image `psyb0t/claude-code` | `psyb0t/claudebox` |
| Command | `claudebox`. The installer takes another name as its first argument, see [Installation](wrapper.md#install). |

## Changes in v2

Version 2 rebuilt the image on aicodebox. What changes for an existing setup:

- **Image variants swapped.** `latest` is now the minimal image and `latest-full` the one with the development toolchain. `CLAUDEBOX_MINIMAL=1` does nothing any more; use `CLAUDEBOX_FULL=1` for the full image.
- **Endpoints.** `POST /run/cancel?runId=...` became `DELETE /run/{runId}`, and `GET /health` became `GET /healthz`.
- **MCP tool.** `claude_run` became `run_prompt`.
- **Output format.** `--output-format json-verbose` is rejected. Use `stream-json`, or API mode with `"eventMode": "full"`.
- **Paths.** The workspace root is `/workspace` and the state directory `/home/aicode/.aicodebox`. The entrypoint links `/workspaces` and `/home/aicode/.claude` to them, so old mounts still resolve.
- **Init scripts.** Your scripts go in the state directory's `init.d/`, which is `~/.claude/init.d/` with the wrapper. See [Customization](customization.md#init-hooks-claudeinitd).
- **Telegram.** The `/bash` command is gone.

## Legacy variable names

These older names still work. Prefer the current names in new configuration.

Inside the container, the entrypoint maps them to the current setting when that setting is not already set:

| Legacy name | Current name |
| --- | --- |
| `CLAUDEBOX_MODE_API`, `CLAUDE_MODE_API` | `CLAUDEBOX_API_MODE` |
| `CLAUDEBOX_MODE_API_PORT`, `CLAUDE_MODE_API_PORT` | `CLAUDEBOX_API_MODE_PORT` |
| `CLAUDEBOX_MODE_API_TOKEN`, `CLAUDE_MODE_API_TOKEN` | `CLAUDEBOX_API_MODE_TOKEN` |
| `CLAUDEBOX_MODE_TELEGRAM`, `CLAUDE_MODE_TELEGRAM` | `CLAUDEBOX_TELEGRAM_MODE` |
| `CLAUDE_TELEGRAM_BOT_TOKEN` | `CLAUDEBOX_TELEGRAM_MODE_TOKEN` |
| `CLAUDE_TELEGRAM_CONFIG` | `CLAUDEBOX_TELEGRAM_MODE_CONFIG` |
| `CLAUDEBOX_MODE_CRON`, `CLAUDE_MODE_CRON` | `CLAUDEBOX_CRON_MODE` |
| `CLAUDEBOX_MODE_CRON_FILE`, `CLAUDE_MODE_CRON_FILE` | `CLAUDEBOX_CRON_MODE_FILE` |
| `CLAUDE_WORKSPACE` | `CLAUDEBOX_WORKSPACE` |

On the host, the wrapper and the installer read the `CLAUDE_` form of their settings when the `CLAUDEBOX_` form is unset:

| Legacy name | Current name |
| --- | --- |
| `CLAUDE_IMAGE`, `CLAUDE_FULL` | `CLAUDEBOX_IMAGE`, `CLAUDEBOX_FULL` |
| `CLAUDE_DATA_DIR`, `CLAUDE_SSH_DIR` | `CLAUDEBOX_DATA_DIR`, `CLAUDEBOX_SSH_DIR` |
| `CLAUDE_GIT_NAME`, `CLAUDE_GIT_EMAIL` | `CLAUDEBOX_GIT_NAME`, `CLAUDEBOX_GIT_EMAIL` |
| `CLAUDE_CONTAINER_NAME`, `CLAUDE_MAX_MEM` | `CLAUDEBOX_CONTAINER_NAME`, `CLAUDEBOX_MAX_MEM` |
| `CLAUDE_BIN_NAME`, `CLAUDE_INSTALL_DIR` | `CLAUDEBOX_BIN_NAME`, `CLAUDEBOX_INSTALL_DIR` |
| `CLAUDE_ENV_*`, `CLAUDE_MOUNT_*` | `CLAUDEBOX_ENV_*`, `CLAUDEBOX_MOUNT_*` |
| `CLAUDEBOX_MANAGED_INSTALL` | `AICODEBOX_MANAGED_INSTALL` |
| `CLAUDEBOX_MODE_CRON`, `CLAUDE_MODE_CRON` for the cron shortcut | `CLAUDEBOX_CRON_MODE` |
| `CLAUDEBOX_MODE_CRON_FILE`, `CLAUDE_MODE_CRON_FILE` for the cron shortcut | `CLAUDEBOX_CRON_MODE_FILE` |

The wrapper also forwards a bare `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` from the host without the `CLAUDEBOX_ENV_` prefix, and `DEBUG=true` turns on debug output on both sides.
