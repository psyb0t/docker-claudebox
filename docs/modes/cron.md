# Cron Mode

Run scheduled Claude jobs from a YAML file. The scheduler expands template values when a job fires, runs Claude in the selected workspace, and keeps durable artifacts for every run.

## Cron YAML

Create a YAML file and mount it into the container. `cron.yml.example` contains the complete annotated reference.

```yaml
model: haiku
effort: medium
append_system_prompt: |
  The current UTC time is {system_datetime}.
telegram_chat_id: -1001234567890

jobs:
  - name: every_thirty_seconds
    schedule: "*/30 * * * * *"
    instruction: |
      Write the current UTC timestamp to ./status.txt.

  - name: hourly_repo_check
    schedule: "0 * * * *"
    workspace: repository
    model: sonnet
    effort: high
    instruction: |
      Summarize commits from the last hour. Job name: {job_name}.

  - name: silent_job
    schedule: "*/5 * * * *"
    telegram_chat_id: 0
    instruction: |
      Write the current UTC timestamp to ./status.txt without sending Telegram notifications.
```

Root fields set defaults. A job may override `model`, `effort`, `thinking`, `system_prompt`, `append_system_prompt`, and `telegram_chat_id`. Setting a job's `telegram_chat_id` to `0` disables an inherited notification target. `no_continue: true` starts that job without continuing its prior Claude session.

Each job needs a unique `name`, a `schedule`, and an `instruction`. `workspace` is optional. Without it, jobs run in `CLAUDEBOX_WORKSPACE`. A job can select a safe relative directory below that root, such as `repository` or `reports`. Absolute paths and paths that escape the workspace are rejected.

Use standard five field cron for minute resolution, `min hr dom mon dow`, or six field cron for second resolution, `sec min hr dom mon dow`. For example, `*/30 * * * * *` fires every thirty seconds.

`{system_datetime}` and `{job_name}` work in `instruction`, `system_prompt`, and `append_system_prompt`. They are expanded when the job fires.

## Run history and notifications

The scheduler stores each run under `$HOME/.aicodebox/cron/history/<workspace-slug>/<YYYYMMDD-HHMMSS>-<job-name>/`. A run directory contains `meta.json`, `stdout.log`, `stderr.log`, and `result.txt`. It also appends a summary record to `$HOME/.aicodebox/cron/<job-name>.jsonl`.

Set `CLAUDEBOX_CRON_MODE_HISTORY_DIR` to move the whole cron state root. The scheduler and Telegram reply bridge use that same directory. Do not point it at the `history` child directory.

Set `telegram_chat_id` and `CLAUDEBOX_TELEGRAM_MODE_TOKEN` to post a completed result to Telegram. Successful jobs send their parsed result text, empty successful jobs send a completion notice, and failed jobs send a failure notice. See [Telegram mode](telegram.md).

The scheduler runs one process per job name. If a job is still running at its next tick, that tick is skipped and logged. Jobs may run at the same time when their names differ.

## Compose example

This example keeps credentials and cron state on the host, mounts one workspace, and deliberately does not give Claude Docker socket access.

```yaml
services:
  claudebox-cron:
    image: psyb0t/claudebox:latest
    init: true
    restart: unless-stopped
    environment:
      CLAUDEBOX_CRON_MODE: "1"
      CLAUDEBOX_CRON_MODE_FILE: /home/aicode/.aicodebox/cron.yaml
      CLAUDEBOX_WORKSPACE: /workspace
      CLAUDE_CODE_OAUTH_TOKEN: ${CLAUDE_CODE_OAUTH_TOKEN:?set this in .env}
    volumes:
      - ./cron.yaml:/home/aicode/.aicodebox/cron.yaml:ro
      - ./claude-state:/home/aicode/.aicodebox
      - ./workspace:/workspace
    mem_limit: 2g
    cpus: 2
    pids_limit: 512
    logging:
      driver: local
      options:
        max-size: 10m
        max-file: "3"
```

Claudebox creates `~/.claude` as a compatibility alias for its canonical `$HOME/.aicodebox` state directory. Use the canonical path in new container configuration. A Docker socket is a host control boundary. Add it only when a job genuinely needs Docker control and you accept that authority.

The current image installs Claude Code during first start, so a fresh long running container needs a writable root filesystem. Do not add `read_only: true` or `cap_drop: [ALL]` to this image without first verifying its startup path for the image version you run.

## Combined cron + Telegram mode

Set both `CLAUDEBOX_CRON_MODE=1` and `CLAUDEBOX_TELEGRAM_MODE=1` to run the scheduler in the background while the Telegram bot owns the foreground process. When the bot stops, the scheduler stops too.

Cron jobs post results only when their root or per job `telegram_chat_id` is set. Reply to a cron notification in Telegram to start a fresh Claude session with that notification's job name, fire time, instruction, result, and history directory added to the prompt. Ordinary Telegram messages retain their own chat session behavior. The bot does not inject a rolling cron summary into unrelated chat messages.

Use one host workspace mount at `/workspace`. Give cron jobs and Telegram chats different relative `workspace` values if they must not share files. Do not mount two host directories at the same container path.

## Environment variables

| Variable | Description | Default |
| --- | --- | --- |
| `CLAUDEBOX_CRON_MODE` | Set to `1` to start cron mode. | None |
| `CLAUDEBOX_CRON_MODE_FILE` | Path inside the container to the cron YAML file. | None |
| `CLAUDEBOX_CRON_MODE_HISTORY_DIR` | Cron state root for run artifacts, job summaries, and Telegram reply metadata. | `$HOME/.aicodebox/cron` |
| `CLAUDEBOX_WORKSPACE` | Absolute workspace root. Jobs may select safe relative subdirectories below it. | `/workspace` |
| `DEBUG` | Set to `true` for per tick and per line debug logs. | None |

Legacy `CLAUDEBOX_MODE_CRON`, `CLAUDEBOX_MODE_CRON_FILE`, `CLAUDE_MODE_CRON`, `CLAUDE_MODE_CRON_FILE`, and `CLAUDE_WORKSPACE` remain accepted as fallbacks.
