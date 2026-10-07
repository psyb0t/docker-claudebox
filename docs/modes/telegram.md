# Telegram Mode

Talk to Claude Code from Telegram. Each configured chat gets its own workspace and can select its own model, effort, session behavior, and system prompt. The bot accepts text, documents, photos, videos, voice messages, and captions.

## Setup

1. Create a bot with [@BotFather](https://t.me/BotFather), run `/newbot`, and keep its token in an ignored `.env` file.
2. Find your Telegram user ID with [@userinfobot](https://t.me/userinfobot). A direct message chat ID is that user ID. Group chat IDs are negative numbers.
3. Create `telegram.yml` in the persistent Aicodebox state directory. Claudebox accepts `~/.claude/telegram.yml` through its compatibility alias, but new container configuration should use `$HOME/.aicodebox/telegram.yml`.

```yaml
allowed_chats:
  - 123456789
  - -987654321

default:
  model: sonnet
  effort: high
  continue: true

chats:
  123456789:
    workspace: personal-project
    model: opus
    effort: max
    system_prompt: "You are a senior engineer."

  -987654321:
    workspace: team-project
    model: sonnet
    effort: medium
    continue: false
    append_system_prompt: "Keep responses short."
    allowed_users:
      - 123456789
      - 111222333
```

`allowed_chats` is the access boundary. An empty list means no chat restriction, which allows anyone who can reach the bot to start work. Set explicit direct message and group IDs before exposing the token. Use `allowed_users` to limit members inside a group.

Chat configuration supports `workspace`, `model`, `effort`, `continue`, `system_prompt`, `append_system_prompt`, and `allowed_users`. Workspace values must be safe relative paths below `/workspace`.

## Compose example

```yaml
services:
  claudebox-telegram:
    image: psyb0t/claudebox:latest
    init: true
    restart: unless-stopped
    environment:
      CLAUDEBOX_TELEGRAM_MODE: "1"
      CLAUDEBOX_TELEGRAM_MODE_CONFIG: /home/aicode/.aicodebox/telegram.yml
      CLAUDEBOX_TELEGRAM_MODE_TOKEN: ${CLAUDEBOX_TELEGRAM_MODE_TOKEN:?set this in .env}
      CLAUDE_CODE_OAUTH_TOKEN: ${CLAUDE_CODE_OAUTH_TOKEN:?set this in .env}
    volumes:
      - ./telegram.yml:/home/aicode/.aicodebox/telegram.yml:ro
      - ./claude-state:/home/aicode/.aicodebox
      - ./workspaces:/workspace
    mem_limit: 2g
    cpus: 2
    pids_limit: 512
    logging:
      driver: local
      options:
        max-size: 10m
        max-file: "3"
```

The example intentionally does not mount `/var/run/docker.sock`. Adding that socket lets the bot control the host Docker daemon. Add it only for a specific trusted workflow that requires it. A fresh image installs Claude Code during first start, so verify startup before adding `read_only: true` or dropping all capabilities.

## Environment variables

| Variable | Description | Default |
| --- | --- | --- |
| `CLAUDEBOX_TELEGRAM_MODE` | Set to `1` to start Telegram mode. | None |
| `CLAUDEBOX_TELEGRAM_MODE_TOKEN` | Bot token from [@BotFather](https://t.me/BotFather). | None |
| `CLAUDEBOX_TELEGRAM_MODE_CONFIG` | Path inside the container to `telegram.yml`. | `$HOME/.aicodebox/telegram.yml` |
| `CLAUDEBOX_TELEGRAM_MODE_OVERRIDES` | Persistent JSON file for per chat command overrides. | `$HOME/.aicodebox/telegram_overrides.json` |
| `CLAUDEBOX_AVAILABLE_MODELS` | Comma separated models shown by `/model`. | Adapter model list |
| `CLAUDEBOX_AVAILABLE_EFFORTS` | Comma separated effort levels shown by `/effort`. | Adapter thinking levels |

Legacy `CLAUDE_MODE_TELEGRAM`, `CLAUDE_TELEGRAM_BOT_TOKEN`, and `CLAUDE_TELEGRAM_CONFIG` remain accepted as fallbacks.

## Bot commands

| Command | Description |
| --- | --- |
| Any text message | Sends the text to Claude in the chat workspace. |
| File, photo, video, or voice message | Saves it in the workspace. Its caption becomes the prompt when present. |
| `/model [name]` | Shows the selected model or sets it directly. Use `reset` to clear a command override. |
| `/effort [level]` | Shows or sets the selected effort level. Use `reset` to clear a command override. |
| `/system_prompt [text]` | Shows, sets, or clears this chat's system prompt override. |
| `/append_system_prompt [text]` | Shows, sets, or clears this chat's appended system prompt override. |
| `/fetch <path>` | Sends a relative file from the chat workspace as a Telegram attachment. |
| `/cancel` | Cancels the active Claude process for this chat. |
| `/status` | Shows chats that currently have active processes. |
| `/config` | Shows the chat's effective configuration. |
| `/reload` | Reloads `telegram.yml` without restarting the container. |

Claude can return files by writing `[SEND_FILE: relative/path]` in its response. The bot sends images as photos, videos as video messages, and other files as document attachments. Long responses are split to fit Telegram's message limit.

## Combined with cron mode

When `CLAUDEBOX_CRON_MODE=1` is also set, a cron job with `telegram_chat_id` posts its result to that Telegram chat. Reply directly to that notification to ask about its recorded run. The bot supplies the selected notification's job context to a fresh Claude session. It does not add cron history to unrelated messages. See [Cron mode](cron.md#combined-cron--telegram-mode).
