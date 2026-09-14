# Programmatic Mode

Pass `-p` and a prompt to get a response. No TTY required. It works from
scripts, cron jobs, CI pipelines, and anywhere else you need non-interactive
output.

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

## Model Selection

| Alias        | Model                                | Best for                                               |
| ------------ | ------------------------------------ | ------------------------------------------------------ |
| `opus`       | Claude Opus 4.6                      | Complex reasoning, architecture design, hard debugging |
| `sonnet`     | Claude Sonnet 4.6                    | Daily coding tasks, balanced speed and intelligence    |
| `haiku`      | Claude Haiku 4.5                     | Quick lookups, simple tasks, high-volume operations    |
| `opusplan`   | Opus (planning) + Sonnet (execution) | Best of both worlds for large tasks                    |
| `sonnet[1m]` | Sonnet with 1M context               | Long sessions, huge codebases                          |

You can also pin specific model versions using full model names like `claude-opus-4-6`, `claude-sonnet-4-6`, or `claude-haiku-4-5-20251001`. If no model is specified, the default depends on your account type.

## Output Formats

**`text`** (default) — plain text response, suitable for reading or piping.

**`json`**: one JSON result object from the installed Claude Code CLI. Claudebox passes it through unchanged, so field names and optional fields follow that CLI version.

**`stream-json`**: native NDJSON, one Claude Code record per line. Claudebox
passes it through unchanged and automatically requests partial messages, hook
events, and subagent text. Use the HTTP API's `POST /run` with
`"eventMode": "full"` when you need a stable
`{sequence, attempt, backend, eventType, event}` envelope around every native
record.

**`json-verbose`**: rejected by the v2 wrapper. It was a v1 assembled format. Use `stream-json` for direct native events or API mode for the stable full-event response.
