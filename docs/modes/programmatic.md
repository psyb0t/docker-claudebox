# Programmatic Mode

Pass a prompt and get a response. The `-p` flag is added automatically. No TTY required — works from scripts, cron jobs, CI pipelines, and anywhere else you need non-interactive output.

```bash
claudebox "explain this codebase"                                       # plain text output (default)
claudebox "explain this codebase" --output-format json                  # structured JSON response
claudebox "list all TODOs" --output-format stream-json | jq .           # streaming NDJSON
claudebox "explain this codebase" --model opus                          # choose a specific model
claudebox "review this" --system-prompt "You are a security auditor"    # override the system prompt
claudebox "review this" --append-system-prompt "Focus on SQL injection" # append to the default system prompt
claudebox "debug this" --effort max                                     # maximum reasoning effort
claudebox "quick question" --effort low                                 # fast, lightweight response
claudebox "start over" --no-continue                                    # fresh session, no history
claudebox "keep going" --resume abc123-def456                           # resume a specific session by ID

# structured output with a JSON schema
claudebox "extract the author and title" --output-format json \
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

**`stream-json`**: native NDJSON, one Claude Code record per line. Claudebox passes the stream through unchanged. It includes initialization, assistant, tool, user, rate-limit, and result records when the installed CLI emits them. Use the HTTP API's `POST /run` with `"eventMode": "full"` when you need a stable `{sequence, attempt, backend, eventType, event}` envelope around every native record.

**`json-verbose`**: rejected by the v2 wrapper. It was a v1 assembled format. Use `stream-json` for direct native events or API mode for the stable full-event response.
