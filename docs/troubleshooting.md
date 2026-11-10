---
title: "Troubleshooting"
description: "claudebox error messages from the installer, the wrapper, the entrypoint and the servers, what causes each one, and how to fix it."
nav_order: 9
---

# Troubleshooting

Messages are quoted as the scripts print them, minus any leading emoji, so you can search this page for the text you see. Set `DEBUG=true` on the host to make the wrapper print what it resolves and runs, and forward it with `CLAUDEBOX_ENV_DEBUG=true` for the launcher inside the container.

## Installer

### `Docker is not installed. Please install Docker first.`

The installer did not find `docker` on `PATH`. Install Docker and make sure your user can reach the daemon.

### `CLAUDEBOX_FULL must be 0 or 1`

Use `0` for the minimal image or `1` for the full one. The wrapper checks the same variable on every run.

### `AICODEBOX_MANAGED_INSTALL must be 0 or 1`

The managed-install switch only takes `0` or `1`.

### `Failed to download wrapper.sh`

The installer was run without a `wrapper.sh` next to it and could not fetch one. Check the network and `CLAUDEBOX_INSTALL_REF`, which must name an existing tag, branch or commit.

## Wrapper

### `Unknown flag: <flag> (allowed: ...)`

The wrapper accepts its own short list of flags, printed in the message, not every Claude Code flag. See [Programmatic mode](modes/programmatic.md).

### `Unknown command: <word>`

A bare word without `-p` is not a prompt. Use `claudebox -p "your prompt"`.

### `Invalid output format: <format> (allowed: text, json, json-verbose, stream-json)`

Pick one of `text`, `json` or `stream-json`.

### `--output-format json-verbose is v1-only. In v2, use API mode:`

The v1 assembled format is gone, and the wrapper exits with status 2. Use `stream-json` for the native records, or API mode with `"eventMode": "full"` for a stable envelope.

### `Native event flags require --output-format stream-json`

`--include-partial-messages`, `--forward-subagent-text` and `--include-hook-events` only apply to `stream-json`, and the wrapper adds them there by itself.

### `Missing value for <flag>`

The last flag on the line needs a value.

### `Container '<name>' is busy. Waiting for it to finish...`, then `Container is still busy after 3 attempts. Try again later.`

Another interactive session in the same directory is still running. The wrapper waits about 30 seconds in total. Finish the other session, or stop it with `claudebox stop`.

### `unsupported AICODEBOX_LAUNCH_CONTEXT_VERSION`

This variable is set by a parent box for nested launches. Unset it on the host.

## Container start

### `[claudebox] WARNING: could not install Claude Code. Check the network and restart; modes requiring the CLI will fail until installation succeeds.`

A new container installs Claude Code from npm and could not. npm's own output is printed just before this line. Fix the network or the registry access, then restart the container so it tries again.

### `[entrypoint] init script <path> failed`

One of the init scripts exited with an error. The others still ran, and the script will not run again in this container. Fix it, then create a new container. See [Customization](customization.md#init-hooks-claudeinitd).

### Claude asks you to log in or pick a theme on every run

Claude Code is writing its configuration somewhere that is not mounted. This happens with a container created from an image older than the `CLAUDE_CONFIG_DIR` setting, or with a custom image without it. Recreate the container from a current image.

### A setting or a new image has no effect

The wrapper reuses existing containers, and a container keeps the image, mounts and environment it was created with. See [Container lifecycle](wrapper.md#container-lifecycle) for how to replace it.

## API and MCP

### HTTP `409` from `POST /run`

That workspace already has a run in progress. Wait for it, cancel it with `DELETE /run/{runId}`, or use another `workspace`.

### HTTP `400` from a file endpoint, or `path escapes workspace root` from an MCP file tool

The path resolves outside the workspace root, through `..` or a symlink.

### HTTP `404` from `GET /run/result`

The run ID never existed, its result was already read once, or it expired after 6 hours.

### A request fails with `thinking='<value>' invalid; choose one of [...]`

The effort level is not one Claude Code accepts. Use `low`, `medium`, `high`, `xhigh`, `max`, or `off`.

### HTTP `421` or `403` from MCP behind a proxy

The `Host` or browser `Origin` is not in the MCP allowlist. Add the exact values, see [Reverse proxies and public hosts](modes/mcp.md#reverse-proxies-and-public-hosts).

### MCP accepts calls without a token

`CLAUDEBOX_MCP_MODE_TOKEN` is unset. The API token does not protect MCP.
