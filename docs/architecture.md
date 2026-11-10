---
title: "Architecture"
description: "What claudebox adds to the aicodebox base image: the Claude adapter, the entrypoint, the launcher, first-start scripts, and the container startup order."
nav_order: 8
---

# Architecture

Claudebox is a thin child of [aicodebox](https://psyb0t.github.io/docker-aicodebox/). The base owns everything agent-agnostic: the runtime user, the API, MCP, Telegram and cron servers, init hooks, and mode selection. Claudebox adds the parts that only make sense for Claude Code. When a feature behaves the same in every box, the aicodebox documentation is its reference, and this site documents the claudebox names and differences.

## What the image adds

The two Dockerfiles, [`Dockerfile`](https://github.com/psyb0t/docker-claudebox/blob/master/Dockerfile) for `:latest` and [`Dockerfile.full`](https://github.com/psyb0t/docker-claudebox/blob/master/Dockerfile.full) for `:latest-full`, add the same layer to different bases:

| Piece | Source | Job |
| --- | --- | --- |
| Adapter | [`claudebox/claudebox/adapter.py`](https://github.com/psyb0t/docker-claudebox/blob/master/claudebox/claudebox/adapter.py) | Turns a server-mode request into a `claude` command line and parses its output. Selected with `AICODEBOX_ADAPTER=claudebox.adapter:ClaudecodeAdapter`. |
| Entrypoint | [`claudebox-entrypoint.sh`](https://github.com/psyb0t/docker-claudebox/blob/master/claudebox-entrypoint.sh) | Maps `CLAUDEBOX_*` names to `AICODEBOX_*`, creates compatibility links, installs Claude Code on first start, then runs the base entrypoint. |
| Launcher | [`claudebox-agent.sh`](https://github.com/psyb0t/docker-claudebox/blob/master/claudebox-agent.sh) | Runs `claude` for interactive and `-p` sessions with the claudebox defaults. Selected with `AICODEBOX_AGENT_BINARY=claudebox-agent`. |
| First-start scripts | [`claudebox/init.d/`](https://github.com/psyb0t/docker-claudebox/tree/master/claudebox/init.d) | Prepare Claude's configuration, the workspace `CLAUDE.md`, and the skills directory. |
| Workspace templates | [`claudebox/templates/`](https://github.com/psyb0t/docker-claudebox/tree/master/claudebox/templates) | The `CLAUDE.md` seeded into a workspace that has none, one per image variant. |

The image also sets `CLAUDE_CONFIG_DIR=/home/aicode/.claude`, so Claude Code keeps `.claude.json` on the mounted state directory and a new container starts logged in. `DISABLE_AUTOUPDATER=1` stops Claude Code from updating itself, and `CLAUDEBOX_IMAGE_VARIANT` is `minimal` or `full`.

Neither image contains Claude Code. It is proprietary, with no redistribution grant, so the Dockerfiles only pin a version in `CLAUDEBOX_CLAUDE_VERSION` and the entrypoint installs it.

## Container startup

1. The claudebox entrypoint copies each set `CLAUDEBOX_*` mode variable to its `AICODEBOX_*` name, unless that name is already set, and does the same for the [legacy names](upgrading.md#legacy-variable-names).
2. It links `/workspaces` to the workspace root, and links `/home/aicode/.claude` and `/home/aicode/.aicodebox` so both paths reach the same state directory, whichever one was mounted.
3. If `claude` is not on `PATH`, it runs `npm install -g @anthropic-ai/claude-code@$CLAUDEBOX_CLAUDE_VERSION`. A successful install prints nothing. A failed one prints npm's output and a warning to stderr, and startup continues.
4. The aicodebox entrypoint takes over. It remaps the `aicode` user to the owner of the workspace, matches the Docker socket group, and sets the Git identity.
5. On the first start of a container only, it runs the image scripts in `/aicodebox-init.d/`, then yours in the state directory's `init.d/`. See [Customization](customization.md#init-hooks-claudeinitd).
6. It loads the credentials the wrapper saved for this container, picks the [mode](modes.md), and drops to the `aicode` user.

The three image scripts:

| Script | Does |
| --- | --- |
| `10-claude-json-patch.sh` | Sets `installMethod` to `global`, turns off auto-updates, and accepts the trust dialog for the workspace in `$CLAUDE_CONFIG_DIR/.claude.json`. |
| `20-workspace-claude-md.sh` | Copies the variant's template to the workspace's `CLAUDE.md` if the workspace has none. |
| `30-always-skills-seed.sh` | Creates `~/.claude/.always-skills` and writes a default `~/.claude/system-hint.txt` if there is none. |

## The CLI path

With no server mode set, the base runs `claudebox-agent` with the container's arguments. The launcher:

- passes `setup-token`, `-v`, `--version`, `doctor`, `auth` and `mcp` straight to `claude`;
- adds `--permission-mode bypassPermissions`;
- adds `--append-system-prompt` with the system hint, then every nonempty `SKILL.md` under the always-skills directory in sorted path order;
- runs `sudo claude update` first when the wrapper's `--update` left a marker for this container;
- adds `--continue`, and starts a fresh session if there is nothing to resume, unless the call has `--resume` or `--no-continue`, or the wrapper left a no-continue marker.

## The server path

The API, MCP, Telegram and cron servers come from aicodebox and never go through the launcher. For each run they ask the adapter for a command line:

```text
claude -p --output-format stream-json --verbose
  --permission-mode bypassPermissions
  [--model <model>] [--effort <level>]
  --include-partial-messages --forward-subagent-text --include-hook-events
  [--append-system-prompt <hint, skills, caller text>] [--system-prompt <text>]
  [--json-schema <schema>]
  [--resume <id> | --continue]
  [--disallowedTools '*' | --allowedTools <names>]
  [extra arguments]
```

`--continue` is left out when the request sets `noContinue`. The adapter accepts `low`, `medium`, `high`, `xhigh` and `max` as effort, maps `minimal` to `low`, and treats `off` and `none` as Claude Code's default. Anything else is rejected before Claude starts.

From Claude's native stream it takes the session ID from the `system` init record, the text from `assistant` records, and the usage and stop reason from the final `result` record. With `eventMode: full` the API also returns every native record unchanged.

## The host side

[`wrapper.sh`](https://github.com/psyb0t/docker-claudebox/blob/master/wrapper.sh), installed as `claudebox`, is plain Bash. It names containers after the current directory, mounts the workspace at its own path, `~/.claude`, `~/.ssh/claudebox` and the Docker socket, saves the credentials it was given to a per-container file in `~/.claude`, and then creates or restarts the container. [Installation and wrapper](wrapper.md) covers the lifecycle.
