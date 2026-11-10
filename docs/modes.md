---
title: "Modes"
description: "How a claudebox container picks its mode: interactive or one-shot CLI, API server, Telegram bot, cron scheduler, and the MCP server that runs next to any of them."
nav_order: 3
has_children: true
---

# Modes

One image serves every interface. Environment variables decide what a container runs when it starts.

| Mode | Turned on by | What runs in the foreground |
| --- | --- | --- |
| [Interactive](modes/interactive.md) | No mode variable, no arguments | The Claude Code CLI with a TTY |
| [Programmatic](modes/programmatic.md) | No mode variable, `claudebox -p "..."` | One Claude Code run, then the container exits |
| [API](modes/api.md) | `CLAUDEBOX_API_MODE=1` | The HTTP server, with the OpenAI-compatible endpoint |
| [Telegram](modes/telegram.md) | `CLAUDEBOX_TELEGRAM_MODE=1` | The Telegram bot |
| [Cron](modes/cron.md) | `CLAUDEBOX_CRON_MODE=1` | The scheduler |
| [MCP](modes/mcp.md) | `CLAUDEBOX_MCP_MODE=1` | Nothing of its own; it runs next to the foreground mode |

## How the mode is chosen

The shared aicodebox entrypoint checks the mode variables in this order and runs the first match:

1. API mode, when `CLAUDEBOX_API_MODE=1`. Any other foreground mode variable is ignored.
2. Telegram and cron together, when both are `1`. The scheduler runs in the background and the bot owns the foreground.
3. Telegram alone.
4. Cron alone.
5. Otherwise the Claude Code CLI, through the claudebox launcher. Arguments go to `claude`, so the same image serves the interactive terminal and `-p` runs.

MCP is separate. With API mode it is mounted at `/mcp/` on the API port. With any other mode it starts as a background process on its own port, and it stops when the foreground mode exits.

## Setting a mode

In a Compose file or a plain `docker run`, set the variables directly:

```yaml
environment:
  - CLAUDEBOX_API_MODE=1
  - CLAUDEBOX_API_MODE_TOKEN=${CLAUDEBOX_API_MODE_TOKEN:?set this in .env}
```

Through the wrapper, a variable reaches the container only with the `CLAUDEBOX_ENV_` prefix. `CLAUDEBOX_API_MODE=1 claudebox` starts an ordinary interactive session. Use this instead:

```bash
CLAUDEBOX_ENV_CLAUDEBOX_API_MODE=1 claudebox
```

The wrapper's cron shortcut is the one exception, see [Cron mode](modes/cron.md#cron-through-the-wrapper).

Every `CLAUDEBOX_*` mode variable is an alias for the `AICODEBOX_*` name the base reads. When both are set, the `AICODEBOX_*` value wins. The full list is in [Environment variables](environment-variables.md#settings-inside-the-container).

## Authentication by mode

Every mode needs an Anthropic credential in the container, `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`, or a login stored in the state directory. Each server also has its own access control:

| Server | Variable | When unset |
| --- | --- | --- |
| API and OpenAI endpoint | `CLAUDEBOX_API_MODE_TOKEN` | No authentication |
| MCP | `CLAUDEBOX_MCP_MODE_TOKEN` | No authentication. The API token never applies to MCP. |
| Telegram | `allowed_chats` in `telegram.yml` | Every chat that finds the bot can use it |

`CLAUDEBOX_TELEGRAM_MODE_TOKEN` is the bot's token from BotFather, not an access control.
