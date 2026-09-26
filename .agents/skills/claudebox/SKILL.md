---
name: claudebox
description: "Install, configure, or run Claude Code through the claudebox wrapper, or connect to its HTTP, MCP, Telegram, or cron surfaces."
homepage: https://github.com/psyb0t/docker-claudebox
user-invocable: true
metadata:
  { "openclaw": { "emoji": "📦", "primaryEnv": "CLAUDEBOX_URL", "requires": { "bins": ["docker", "curl"] } } }
---

# claudebox

Claude Code — the agentic coding CLI from Anthropic — running in an isolated Docker container with dev tools, passwordless sudo, docker-in-docker, and `--permission-mode bypassPermissions` on by default. Built as a thin child image of `psyb0t/aicodebox`; every server-mode surface (API / OpenAI adapter / MCP / Telegram / Cron) is inherited from that base.

## Agent execution

Use `claudebox` when it is on `PATH`. Run it from the workspace the user
named. Do not assemble a new `docker run` command for routine interactive or
one-shot work. The wrapper owns the workspace mount, `~/.claude`, SSH state,
image selection, and session lifecycle.

```bash
claudebox                                      # interactive Claude Code
claudebox -p "inspect this workspace"          # one-shot work
claudebox -p "emit events" --output-format stream-json
CLAUDEBOX_FULL=1 claudebox -p "run the full suite"
```

For a wrapper-started server, prefix container variables with
`CLAUDEBOX_ENV_`. For example,
`CLAUDEBOX_ENV_CLAUDEBOX_API_MODE=1 claudebox` passes
`CLAUDEBOX_API_MODE=1` into the container. Bare `CLAUDEBOX_API_MODE` is not
forwarded and does not start the server.

Start a local API and MCP server only when the user asks for one. Authenticate
Claude first, then use distinct bearer tokens for the two surfaces:

```bash
CLAUDEBOX_ENV_CLAUDEBOX_API_MODE=1 \
CLAUDEBOX_ENV_CLAUDEBOX_MCP_MODE=1 \
CLAUDEBOX_ENV_CLAUDEBOX_API_MODE_TOKEN=your-api-token \
CLAUDEBOX_ENV_CLAUDEBOX_MCP_MODE_TOKEN=your-mcp-token \
claudebox
```

Use an HTTP or MCP endpoint only when the user asks for a service or provides
an already-running remote URL. MCP plugins connect to a server. They do not
replace the local wrapper.

If `claudebox`, `codexbox`, and `pibox` were installed in the same command
directory, a box can invoke a sibling command directly. The parent wrapper
passes the real host paths and the sibling wrapper file. Do not set
`AICODEBOX_HOST_*`, copy wrapper files, or manually mount another box's state
directory. If the sibling command is absent, ask the user to install it or to
choose another approach.

## Security & safety

- **No auth when the per-mode token is unset.** `CLAUDEBOX_API_MODE_TOKEN` and `CLAUDEBOX_MCP_MODE_TOKEN` each default to no auth if unset — see [HTTP REST API mode](#http-rest-api-mode) and [MCP server mode](#mcp-server-mode) for details and the exact capability exposed unauthenticated in each case.
- **File operations include removal.** Deleting a workspace file has no undo — only remove files the current task created, and only when the user asked.
- **Mounting `/var/run/docker.sock` grants host-level container control** — see [Server modes (API / OpenAI / MCP / Telegram / Cron)](references/setup.md#server-modes-api--openai--mcp--telegram--cron) in `references/setup.md`, only do this on a host you trust.
- **`--permission-mode bypassPermissions` is on by default** — Claude has full, unrestricted shell/file/docker access inside the container by design (see [When NOT To Use](#when-not-to-use)). Don't treat the container boundary as a sandbox for untrusted input unless you've isolated the container itself.
- **Install script is piped from curl into bash by default** — a safer download-inspect-run alternative is documented alongside it; see [references/setup.md](references/setup.md#quick-install-cli-wrapper).

Seven programmatic surfaces, all reachable from the same container image, selected by which `CLAUDEBOX_*_MODE` env flags are set at boot:

- **Interactive shell** — `claudebox` drops you into the native `claude` CLI, container-backed, with automatic session resumption.
- **One-shot exec**: `claudebox -p "prompt" [flags]`, non-interactive, prompt in / structured output out, for scripts and CI.
- **HTTP REST API** — `CLAUDEBOX_API_MODE=1`. `POST /run`, async runs polled via `GET /run/result?runId=`, `GET/PUT/DELETE /files/{path}`, workspace isolation.
- **OpenAI-compatible endpoint** — same API-mode server, `/openai/v1/chat/completions` + `/openai/v1/models`. Streaming SSE, multi-turn, multimodal image input.
- **MCP server** — `CLAUDEBOX_MCP_MODE=1`, 5 tools over streamable HTTP. Mounts at `/mcp` on the API port when `CLAUDEBOX_API_MODE=1` is also set; otherwise runs standalone as a sidecar process on its own port (`CLAUDEBOX_MCP_MODE_PORT`, default `8081`), coexisting with Telegram/Cron/interactive mode.
- **Telegram bot** — `CLAUDEBOX_TELEGRAM_MODE=1`, per-chat isolated workspaces, file/photo/video/voice ingestion, slash commands.
- **Cron scheduler** — `CLAUDEBOX_CRON_MODE=1`, YAML-defined jobs on 5- or 6-field cron schedules, per-job activity history.

For installation and configuration, see [references/setup.md](references/setup.md).

## When To Use

- Run Claude Code from a script, Makefile target, or CI pipeline without a TTY (`claudebox -p "explain this diff" --output-format json`).
- Expose Claude Code as an HTTP backend other services can `POST /run` against, with workspace isolation for multi-tenant use.
- Point an OpenAI SDK / LiteLLM at a self-hosted agentic backend instead of a plain model API — every completion runs the full Claude Code CLI (file I/O, shell, tools), not just text generation.
- Let another MCP-aware agent (Claude Desktop, another Claude Code instance, an agent framework) use this Claude Code instance as a tool over `/mcp`.
- Run Claude from Telegram — ask questions, share files, get shell access, from your phone.
- Schedule recurring Claude jobs (nightly cleanup, hourly repo checks) with per-run history and optional Telegram result delivery.

## When NOT To Use

- Real-time token-by-token streaming for tool-calling or JSON-schema-constrained runs — the OpenAI adapter buffers those (computes the full answer, replays as one SSE burst). Only plain chat (no `tools`, no `response_format` schema) streams incrementally.
- Multiple concurrent requests against the *same* workspace — API mode enforces one active Claude process per workspace and returns `409` on conflict. Use distinct `workspace` subpaths for parallel work.
- Treating `--permission-mode bypassPermissions` as sandboxed-safe for untrusted input — Claude has full container access by design (shell, docker-in-docker, mounted SSH keys). Isolate the container itself if the input is untrusted.
- Expecting one fixed MCP path — it's `/mcp` (mounted, requires `CLAUDEBOX_API_MODE=1` too) in the documented API-mode setup, but a different, unmounted standalone port (`CLAUDEBOX_MCP_MODE_PORT`) when MCP mode runs without API mode. Match your client config to which one you actually launched.

## Interactive shell mode

Drop-in replacement for the native `claude` command, container-backed:

```bash
claudebox                  # interactive session, --continue applied automatically
claudebox --no-continue    # start a fresh session instead of resuming
claudebox --update         # opt in to a Claude Code CLI update this run
```

Utility commands pass through without entering interactive mode:

```bash
claudebox --version         # claude CLI version
claudebox doctor            # health checks
claudebox auth              # manage authentication
claudebox mcp <args...>     # manage MCP servers, e.g. `claudebox mcp list`
claudebox setup-token       # interactive OAuth token setup
claudebox stop              # stop the running interactive container for this workspace
claudebox clear-session     # delete session history for this workspace
```

No mode flag needed — this is the default when you run `claudebox` with no `CLAUDEBOX_*_MODE` env vars set. Auth: `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` (see [Auth](#auth)).

## One-shot exec mode

Non-interactive prompt-in/response-out. Pass `-p` for scripts, CI, cron, or
anywhere without a TTY:

```bash
claudebox -p "explain this codebase"                                       # plain text (default)
claudebox -p "explain this codebase" --output-format json                  # structured JSON
claudebox -p "list all TODOs" --output-format stream-json | jq .           # complete native NDJSON
claudebox -p "explain this codebase" --model opus                          # pick a model
claudebox -p "review this" --system-prompt "You are a security auditor"    # replace system prompt
claudebox -p "review this" --append-system-prompt "Focus on SQL injection" # append to system prompt
claudebox -p "debug this" --effort max                                     # max reasoning effort
claudebox -p "start over" --no-continue                                    # fresh session
claudebox -p "keep going" --resume abc123-def456                           # resume a specific session

# JSON-schema-constrained output
claudebox -p "extract the author and title" --output-format json \
  --json-schema '{"type":"object","properties":{"author":{"type":"string"},"title":{"type":"string"}},"required":["author","title"]}'
```

`--continue` is applied automatically so successive runs in the same workspace
share context. Use `--no-continue` for a clean slate or `--resume <session_id>`
for a specific one. Model aliases: `haiku`, `sonnet`, `opus`, `opusplan`,
`sonnet[1m]`. The wrapper requires `-p` to select this mode.

## HTTP REST API mode

`CLAUDEBOX_API_MODE=1` starts a long-lived FastAPI server (default port `8080`, `CLAUDEBOX_API_MODE_PORT` to override). Bearer auth via `CLAUDEBOX_API_MODE_TOKEN` (unset = no auth).

With `CLAUDEBOX_API_MODE_TOKEN` unset the API surface is unauthenticated — anyone who can reach it gets full `/run` (arbitrary-prompt agentic execution) and `/files` (read/write anywhere under `/workspace`) access. Set the token and bind to loopback / behind an authenticating proxy before exposing it beyond localhost.

```yaml
environment:
  - CLAUDEBOX_API_MODE=1
  - CLAUDEBOX_API_MODE_TOKEN=your-secret-token
  - CLAUDEBOX_AVAILABLE_MODELS=haiku,sonnet,opus,opusplan  # optional — overrides the adapter's built-in default list
```

```bash
curl -X POST http://localhost:8080/run \
  -H "Authorization: Bearer your-secret-token" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "what does this repo do", "workspace": "myproject"}'
```

Key `/run` body fields: `prompt` (required), `workspace` (subpath under
`/workspace`), `model`, `systemPrompt`, `appendSystemPrompt`, `jsonSchema`,
`eventMode`, `outputFormat` (legacy), `noContinue`, `resume`,
`fireAndForget`, `async`, `includeRaw` (raw stdout/stderr), `extraArgs`,
`toolsAllowlist`, `noTools`, and `timeoutSeconds`. The Claude adapter always
requests complete native records. Use `"eventMode": "full"` to return them in
the stable `{sequence, attempt, backend, eventType, event}` envelope.
`thinking` is accepted but has no effect on claudebox (see
[OpenAI-compatible endpoint mode](#openai-compatible-endpoint-mode)). Every
response carries a `runId`. Returns `409` if the target workspace is already
busy.

**Async runs** — `"async": true` returns immediately with a `runId`; poll it:

```bash
curl -X POST http://localhost:8080/run -H "Authorization: Bearer token" -H "Content-Type: application/json" \
  -d '{"prompt": "refactor this codebase", "workspace": "myproject", "async": true}'
# → {"runId": "abc123", "workspace": "/workspace/myproject", "status": "running"}

curl "http://localhost:8080/run/result?runId=abc123" -H "Authorization: Bearer token"
# running → {"runId":..., "status": "running"}; completed → full result JSON (then purged from cache)
```

Completed/failed/cancelled results are returned once then purged; unread results expire after 6 hours. `GET /run/result?runId=X` 404s on unknown/already-read/expired IDs.

**File operations** — all paths relative to `/workspace`, path traversal blocked with `400`:

```bash
curl "http://localhost:8080/files" -H "Authorization: Bearer token"                          # list root
curl "http://localhost:8080/files/myproject/src" -H "Authorization: Bearer token"            # list dir
curl "http://localhost:8080/files/myproject/src/main.py" -H "Authorization: Bearer token"    # download
curl -X PUT "http://localhost:8080/files/myproject/src/main.py" -H "Authorization: Bearer token" --data-binary @main.py
curl -X DELETE "http://localhost:8080/files/myproject/src/old.py" -H "Authorization: Bearer token"
```

`DELETE /files/{path}` removes a file under `/workspace` (no undo). Confirm the target path first, only remove files the current task created, and on a shared instance don't touch another caller's workspace — see [Security & safety](#security--safety).

**Introspection and lifecycle:**

```bash
curl http://localhost:8080/healthz                                                          # {"ok": true, "adapter": "claude"} — no auth
curl http://localhost:8080/status -H "Authorization: Bearer token"                           # {busyWorkspaces, runs}
curl -X DELETE "http://localhost:8080/run/abc123" -H "Authorization: Bearer token"            # cancel a run by id
```

## OpenAI-compatible endpoint mode

Same API-mode server (`CLAUDEBOX_API_MODE=1`); no separate flag. `chat/completions`-shaped adapter for LiteLLM, OpenAI SDKs, or any client speaking that wire format. Every request runs the full agentic CLI, not just text generation — Claude can read/write files and run shell commands as part of answering.

```bash
curl http://localhost:8080/openai/v1/models
# {"object":"list","data":[{"id":"haiku",...},{"id":"sonnet",...},{"id":"opus",...},{"id":"opusplan",...}]}

curl -X POST http://localhost:8080/openai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"haiku","messages":[{"role":"user","content":"hello"}]}'

# streaming
curl -X POST http://localhost:8080/openai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"haiku","messages":[{"role":"user","content":"hello"}],"stream":true}'
```

Model aliases match the CLI (`haiku`/`sonnet`/`opus`/`opusplan`); provider prefixes are stripped (`claudebox/haiku` → `haiku`). `role: "system"` messages become `--system-prompt`. Single-user-message requests are the fast path (sent directly as the prompt); multi-turn conversations are serialized to a JSON file under `_oai_uploads/` in the workspace so Claude Code can read the full history. Multimodal `image_url` content (data URLs or `http(s)://`) is downloaded/decoded to the workspace and referenced by path.

For every native Claude record in an OpenAI stream, send
`"stream_options": {"include_aicodebox_events": true}`. Claudebox emits a
named `aicodebox.native` SSE event before normal OpenAI chunks. Its payload is
`{sequence, attempt, backend, eventType, event}`. Standard chunks remain
unchanged, so the extension stays opt-in for strict OpenAI SSE clients.

`temperature` and `max_tokens` are accepted for OpenAI-client compatibility but have no effect on this adapter. `reasoning_effort` maps to the `claude --effort` flag: `low`, `medium`, `high`, `xhigh`, and `max` pass through, `minimal` maps to `low`, `none` or `off` keeps the default, and any other value is rejected. The `thinking` field on `/run` and MCP `run_prompt` works the same way.

**Tool calling and structured output are supported, not ignored** — `tools`/`tool_choice` engage a client-executed function-calling bridge (Claude Code acts as a pure function-calling model, emits `tool_calls` for the *client* to run), and `response_format` (`json_object` or `json_schema`) constrains the final answer turn. Both can combine in one request. Because a tool call or schema-checked answer only exists once the full response is computed, `stream:true` combined with `tools` or a schema `response_format` returns a **buffered** single-shot SSE stream instead of token-incremental deltas — only plain chat (no tools, no schema) streams token-by-token.

Custom headers for claudebox-specific behavior (canonical `x-aicodebox-*`, with legacy `X-Claude-*` aliases still accepted):

| Header | Description |
| --- | --- |
| `x-aicodebox-workspace` (`X-Claude-Workspace`) | Workspace subpath under `/workspace` |
| `x-aicodebox-continue` (`X-Claude-Continue`) | `1`/`true`/`yes` to continue the previous session |
| `x-aicodebox-append-system-prompt` (`X-Claude-Append-System-Prompt`) | Text appended to the system prompt |
| `x-aicodebox-json-schema` | JSON-schema string — fallback for clients that can't set `response_format` in the body (body field wins if both are set) |
| `x-aicodebox-resume` | Resume a specific session id |
| `x-aicodebox-tools-allowlist` | CSV or JSON array restricting Claude Code's own internal tools |
| `x-aicodebox-no-tools` | Disable Claude Code's own internal tools (auto-defaulted on when in client tool-calling mode) |

LiteLLM example:

```python
import litellm

response = litellm.completion(
    model="claudebox/haiku",
    messages=[{"role": "user", "content": "hello"}],
    api_base="http://localhost:8080/openai/v1",
    api_key="your-secret-token",  # any string if no API token is configured
)
print(response.choices[0].message.content)
```

## MCP server mode

`CLAUDEBOX_MCP_MODE=1` exposes a [Model Context Protocol](https://modelcontextprotocol.io/) server over streamable HTTP, using `CLAUDEBOX_MCP_MODE_TOKEN` as its bearer token (independent of the API token, no fallback; empty/unset = no auth). Where it listens depends on whether API mode is also on:

With `CLAUDEBOX_MCP_MODE_TOKEN` unset the MCP surface is unauthenticated — anyone who can reach it gets full tool access (run prompts, read/write/remove files under `/workspace`). Set the token and bind to loopback / behind an authenticating proxy before exposing it beyond localhost.

- **`CLAUDEBOX_API_MODE=1` + `CLAUDEBOX_MCP_MODE=1`** (the setup the rest of the README documents) — MCP mounts at `/mcp` on the API port, no extra process.
- **`CLAUDEBOX_MCP_MODE=1` alone** (or combined with Telegram/Cron/interactive mode) — MCP runs as an independent background process on its own port (`CLAUDEBOX_MCP_MODE_PORT`, default `8081`), serving at the port root, not under `/mcp`.

```yaml
environment:
  - CLAUDEBOX_API_MODE=1
  - CLAUDEBOX_MCP_MODE=1
  - CLAUDEBOX_MCP_MODE_TOKEN=your-mcp-token
```

```json
{
  "mcpServers": {
    "claudebox": {
      "url": "http://localhost:8080/mcp/",
      "headers": { "Authorization": "Bearer your-mcp-token" }
    }
  }
}
```

Clients that can't set headers can pass the token as a query param instead: `http://localhost:8080/mcp/?apiToken=your-mcp-token`. Wire it into Claude Code directly:

```bash
claude mcp add --transport http claudebox http://localhost:8080/mcp/ \
  --header "Authorization: Bearer your-mcp-token"
```

**Available tools:**

| Tool | Description |
| --- | --- |
| `run_prompt` | Run a prompt through Claude Code. Args: `prompt`, `workspace`, `model`, `system_prompt`, `append_system_prompt`, `no_continue` (default `true`), `resume`, `thinking` (accepted, no effect on claudebox — see [OpenAI-compatible endpoint mode](#openai-compatible-endpoint-mode)), `json_schema`. Returns the assistant's text. |
| `list_files` | List files/dirs under a workspace path. |
| `read_file` | Read a file's text content. |
| `write_file` | Write content to a file (creates parent dirs). |
| `delete_file` | Delete a file (refuses directories). |

`delete_file` removes a file under `/workspace` (no undo). Confirm the target path first and only remove files the current task created — see [Security & safety](#security--safety).

Raw JSON-RPC for debugging (streamable-HTTP handshake — `initialize` then reuse the returned `mcp-session-id`):

```bash
curl -s -D - -X POST "http://localhost:8080/mcp/" \
  -H "Authorization: Bearer your-mcp-token" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"debug","version":"1"}}}'
# capture the mcp-session-id response header, then:
curl -s -X POST "http://localhost:8080/mcp/" \
  -H "Authorization: Bearer your-mcp-token" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: <session-id-from-above>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

## Telegram bot mode

`CLAUDEBOX_TELEGRAM_MODE=1` runs a conversational bot with per-chat isolated workspaces. Requires a config file — the bot refuses to start without one, to prevent accidentally exposing Claude to the public.

```yaml
environment:
  - CLAUDEBOX_TELEGRAM_MODE=1
  - CLAUDEBOX_TELEGRAM_MODE_TOKEN=123456:ABC-DEF   # from @BotFather
```

`~/.claude/telegram.yml` (mounted into the container):

```yaml
allowed_chats:
  - 123456789    # your DM (positive = user id)
  - -987654321   # a group chat (negative)

default:
  model: sonnet
  effort: high
  continue: true

chats:
  123456789:
    workspace: my-project
    model: opus
    system_prompt: "You are a senior engineer"
```

Per-chat overrides: `workspace`, `model`, `effort`, `continue`, `system_prompt`, `append_system_prompt`, `max_budget_usd`, `allowed_users` (group-chat allowlist).

Bot commands: any text message is a prompt; sending a file/photo/video/voice saves it to the workspace (caption becomes the prompt); `/model [name]`, `/effort [level]`, `/system_prompt [text]`, `/append_system_prompt [text]`, `/fetch <path>`, `/cancel`, `/status`, `/config`, `/reload`. Claude sends files back with `[SEND_FILE: relative/path]` in its response text.

`effort` (config field and `/effort` command) is passed to the `claude` CLI as `--effort`. `off` keeps Claude Code's default effort.

## Cron scheduler mode

`CLAUDEBOX_CRON_MODE=1` runs YAML-defined Claude jobs on cron schedules (5-field standard, 6-field for sub-minute resolution). Foreground process — `docker logs` shows every tick.

```yaml
environment:
  - CLAUDEBOX_CRON_MODE=1
  - CLAUDEBOX_CRON_MODE_FILE=/home/aicode/.claude/cron.yaml
  - CLAUDEBOX_WORKSPACE=/workspace
```

`cron.yaml`:

```yaml
model: haiku                       # default for all jobs; per-job "model" overrides
jobs:
  - name: hourly_repo_check
    schedule: "0 * * * *"          # 5-field standard cron
    instruction: |
      Look at the git log for the last hour. Summarize commits.
  - name: every_30_seconds
    schedule: "*/30 * * * * *"     # 6-field sub-minute
    instruction: Write the current UTC timestamp to ./status.txt.
```

Per-job/root fields: `model`, `effort`, `system_prompt`, `append_system_prompt`, `telegram_chat_id` (requires `CLAUDEBOX_TELEGRAM_MODE_TOKEN`). Template vars usable in `instruction`/`system_prompt`/`append_system_prompt`: `{system_datetime}`, `{job_name}`. `effort` has the same no-effect caveat as [Telegram bot mode](#telegram-bot-mode) — accepted, not currently wired into the CLI invocation.

Output streams to `~/.claude/cron/history/<workspace-slug>/<YYYYMMDD-HHMMSS>-<job-name>/` (`activity.jsonl` stream-json, `stderr.log`, `meta.json`). Overlapping ticks are skipped, not queued. Combine with `CLAUDEBOX_TELEGRAM_MODE=1` to get results posted to Telegram and reply-to-interrogate on finished runs — see [references/setup.md](references/setup.md#cron--telegram-combined-mode).

## Auth

Interactive/exec/cron/CLI-driven modes need an Anthropic credential:

```bash
claudebox setup-token                                        # interactive OAuth setup, one-time
CLAUDE_CODE_OAUTH_TOKEN=<YOUR_OAUTH_TOKEN> claudebox -p "do stuff" # then reuse the token
# or
ANTHROPIC_API_KEY=<YOUR_API_KEY> claudebox -p "do stuff"
```

Server modes gate their own HTTP surface independently, each with its own bearer token (unset = open):

| Mode | Token var |
| --- | --- |
| API / OpenAI adapter | `CLAUDEBOX_API_MODE_TOKEN` |
| MCP | `CLAUDEBOX_MCP_MODE_TOKEN` (separate from the API token, no fallback) |
| Telegram | `CLAUDEBOX_TELEGRAM_MODE_TOKEN` (the bot token itself, not a bearer secret) |

All of these still need the underlying Anthropic credential (`CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY`) set in the container env to actually talk to the model.

## Typical Workflows

### Pipe a code review through CI

```bash
claudebox -p "review this diff for security issues" --output-format json --model sonnet | jq -r .result
```

### Drive claudebox from another agent over MCP

```bash
claude mcp add --transport http claudebox http://localhost:8080/mcp/ \
  --header "Authorization: Bearer $CLAUDEBOX_MCP_MODE_TOKEN"
```

### Fire-and-poll a long refactor over HTTP

```bash
RUN_ID=$(curl -s -X POST http://localhost:8080/run -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"prompt": "refactor the auth module", "workspace": "myproject", "async": true}' | jq -r .runId)

until curl -s "http://localhost:8080/run/result?runId=$RUN_ID" -H "Authorization: Bearer $TOKEN" | jq -e '.status != "running"' >/dev/null; do
  sleep 5
done
curl -s "http://localhost:8080/run/result?runId=$RUN_ID" -H "Authorization: Bearer $TOKEN" | jq
```

### Point LiteLLM at claudebox as an OpenAI-compatible backend

```python
import litellm
litellm.completion(model="claudebox/sonnet", messages=[{"role": "user", "content": "hello"}],
                    api_base="http://localhost:8080/openai/v1", api_key=API_TOKEN)
```

### Nightly cleanup job with Telegram notification

```yaml
telegram_chat_id: -1001234567890
jobs:
  - name: nightly_cleanup
    schedule: "0 3 * * *"
    instruction: Find files older than 7 days under ./tmp and delete them. Report what you removed.
```

For install steps, docker run/compose invocations, the full env-var reference, port list, and container management commands, see [references/setup.md](references/setup.md).
