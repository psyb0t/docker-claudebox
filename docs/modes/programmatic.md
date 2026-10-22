# Programmatic mode

Pass `-p` and a prompt to get a response. No TTY required. It works from scripts, cron jobs, CI pipelines, and anywhere else you need non-interactive output.

Successful first-start CLI installation is silent. Stdout contains only native CLI output; installation failures remain visible on stderr.

```bash
claudebox -p "explain this codebase"                                       # plain text output (default)
claudebox -p "explain this codebase" --output-format json                  # structured JSON response
claudebox -p "list all TODOs" --output-format stream-json | jq .           # streaming NDJSON
claudebox -p "explain this codebase" --model opus                          # choose a specific model
claudebox -p "review this" --system-prompt "You are a security auditor"    # override the system prompt
claudebox -p "review this" --append-system-prompt "Focus on SQL injection" # append to the default system prompt
claudebox -p "debug this" --effort max                                     # maximum reasoning effort
claudebox -p "quick question" --effort low                                 # fast, lightweight response
claudebox -p "start over" --no-continue                                    # fresh session, no history
claudebox -p "keep going" --resume abc123-def456                           # resume a specific session by ID

# structured output with a JSON schema
claudebox -p "extract the author and title" --output-format json \
  --json-schema '{"type":"object","properties":{"author":{"type":"string"},"title":{"type":"string"}},"required":["author","title"]}'
```

`--continue` is applied automatically so successive programmatic runs in the same workspace share conversation context. Use `--no-continue` to start fresh or `--resume <session_id>` to continue a specific conversation.

## Model selection

The wrapper passes `--model` to Claude Code. Use an alias such as `opus`, `sonnet`, `haiku`, or `opusplan`, or a full model ID supported by your account and the installed CLI. Claudebox does not pin aliases to a particular model generation. Available models and context sizes depend on Claude Code, your provider, and your account. Without this flag, Claude Code selects its default.

## Output formats

**`text`** (default): plain text response, suitable for reading or piping.

**`json`**: one JSON result object from the installed Claude Code CLI. Claudebox passes it through unchanged, so field names and optional fields follow that CLI version.

**`stream-json`**: native NDJSON, one Claude Code record per line. Claudebox passes it through unchanged and automatically requests partial messages, hook events, and subagent text. Use the HTTP API's `POST /run` with `"eventMode": "full"` when you need a stable `{sequence, attempt, backend, eventType, event}` envelope around every native record.

**`json-verbose`**: rejected by the v2 wrapper. It was a v1 assembled format. Use `stream-json` for direct native events or API mode for the stable full-event response.
