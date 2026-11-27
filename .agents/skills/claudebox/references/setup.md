# Claudebox setup

Use the installed `claudebox` wrapper from the target workspace for local work. It owns workspace mounts, persistent state, SSH, image selection, and nested-launch context. Use MCP for an already-running remote server, not as a replacement for the local wrapper.

## Quick install (CLI wrapper)

You need Bash, Docker, curl, SSH key-generation tools, and permission to install the wrapper. Authenticate with Claude Code or supply `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`.

Download the installer, read it, then run it:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh -o claudebox-install.sh
less claudebox-install.sh
bash claudebox-install.sh
```

The installer pulls the `psyb0t/claudebox` image, creates `~/.claude` and an SSH key at `~/.ssh/claudebox/id_ed25519`, downloads `wrapper.sh` from the same release ref (`CLAUDEBOX_INSTALL_REF` overrides it), and uses `sudo` to copy the wrapper into `/usr/local/bin` (`CLAUDEBOX_INSTALL_DIR` changes the directory). For the full image, run `CLAUDEBOX_FULL=1 bash claudebox-install.sh`.

To review the wrapper too, use a local checkout and read `install.sh` and the adjacent `wrapper.sh` before running `bash install.sh`. The wrapper and image are updated separately. See [installation and wrapper behavior](https://github.com/psyb0t/docker-claudebox/blob/master/docs/wrapper.md) before changing image selection or reusing a container.

## Local use

```bash
claudebox
claudebox -p "inspect this workspace"
claudebox -p "inspect this workspace" --output-format stream-json
```

Install sibling box wrappers in the same command directory. The parent mounts the sibling wrapper files and passes host-path context; the sibling mounts its own state. Do not set `AICODEBOX_HOST_*` manually.

## Server modes (API / OpenAI / MCP / Telegram / Cron)

- [API](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/api.md): `/run`, native events, async polling, files, and OpenAI-compatible chat.
- [MCP](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/mcp.md): `run_prompt` and file tools, separate authentication, and reverse-proxy allowlists.
- [Telegram](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/telegram.md): chat access lists and configuration.
- [Cron and Telegram combined](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/cron.md#combined-cron--telegram-mode): schedules, history, notifications, and replies.
- [Environment variables](https://github.com/psyb0t/docker-claudebox/blob/master/docs/environment-variables.md): host settings and forwarded container settings.
- [Customization](https://github.com/psyb0t/docker-claudebox/blob/master/docs/customization.md): scripts, init hooks, skills, and external MCP servers.

The standard wrapper mounts the host Docker socket, uses host networking, and bypasses Claude's permission prompts. It is not a security sandbox. Server Compose examples omit that socket. API and MCP tokens are independent; unset tokens leave their endpoint open. Configure a Telegram chat allowlist before exposing the bot.

## Cron + Telegram combined mode

Enable both mode flags to run the scheduler alongside the bot. Set root or per-job `telegram_chat_id` values to post job results. Replies to those notifications receive the recorded job context. See the [combined-mode guide](https://github.com/psyb0t/docker-claudebox/blob/master/docs/modes/cron.md#combined-cron--telegram-mode) for configuration and history paths.

## Lifecycle

`claudebox stop` stops this workspace's interactive container. `claudebox clear-session` deletes its session history, not its credentials. Pulling an image does not replace an existing container. Inspect and recreate only the exact container you intend to update, after backing up files stored outside mounted directories.
