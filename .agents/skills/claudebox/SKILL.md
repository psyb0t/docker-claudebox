---
name: claudebox
description: "Run Claude Code through an already-installed claudebox: interactive and one-shot `claudebox -p` calls, plus its HTTP /run API, OpenAI-compatible endpoint, MCP tools, Telegram bot and cron results. Use when the user asks to run Claude Code in the claudebox container or to call a claudebox server."
homepage: https://github.com/psyb0t/docker-claudebox
user-invocable: true
metadata:
  { "openclaw": { "emoji": "📦", "primaryEnv": "CLAUDEBOX_URL", "requires": { "bins": ["claudebox", "curl"] } } }
permissions:
  network: "Calls to the user's claudebox server at CLAUDEBOX_URL (http://localhost:8080 by default). Claude Code sends prompts to Anthropic for model requests, and in Telegram mode the bot talks to api.telegram.org."
  shell: "Run the claudebox command and curl."
  filesystem: "Read and write files in the workspace directory the user names for claudebox."
---

# claudebox

Claude Code, the agentic coding CLI from Anthropic, running in a Docker container with `--permission-mode bypassPermissions` on by default. It offers interactive, one-shot, HTTP, OpenAI-compatible, MCP, Telegram and cron surfaces.

## Setup

claudebox must already be installed and running; this skill only covers using it. Installation and server configuration are in the docs at https://psyb0t.github.io/docker-claudebox/ and the README at https://github.com/psyb0t/docker-claudebox. For the HTTP, OpenAI and MCP surfaces, read `CLAUDEBOX_URL` (default `http://localhost:8080`), `CLAUDEBOX_API_MODE_TOKEN` and `CLAUDEBOX_MCP_MODE_TOKEN` from the environment the user set. For the local `claudebox` command, run it from the workspace the user named.

## Agent execution

Use `claudebox` when it is on `PATH`, from the workspace the user named.

```bash
claudebox                                      # interactive Claude Code
claudebox -p "inspect this workspace"          # one-shot work
claudebox -p "emit events" --output-format stream-json
```

Use an HTTP or MCP endpoint only when the user asks for a service or provides an already-running remote URL.

## Security & safety

- **Deletion has no undo.** The file delete endpoint, the MCP `delete_file` tool and `claudebox clear-session` remove data. Use them only on files or sessions the current task created, only when the user asked for that removal, and never in another caller's workspace.
- **Data leaves the machine only to these hosts.** Claude Code sends prompts and the files it reads to Anthropic. Telegram mode sends bot messages and files to the Telegram Bot API. The server fetches `http(s)` image URLs in OpenAI-style requests. The `curl` examples below call the claudebox server the user runs, over plain HTTP on `localhost` by default. Send the user's tokens only to the user's own server.
- **`--permission-mode bypassPermissions` is on by default.** Claude has full, unrestricted shell and file access inside the container, and the container is not a sandbox. Do not send untrusted prompts or input to it.
- **An unset API or MCP token means no authentication** on that surface. If the user's server is open, tell them rather than relying on it.

## Surfaces

- **Interactive shell**: `claudebox` drops you into the native `claude` CLI, container-backed, with automatic session resumption.
- **One-shot exec**: `claudebox -p "prompt" [flags]`, non-interactive, prompt in / structured output out, for scripts and CI.
- **HTTP REST API**: `POST /run`, async runs polled via `GET /run/result?runId=`, file list, download, upload and delete under `/files`, per-request workspace subpaths.
- **OpenAI-compatible endpoint**: `/openai/v1/chat/completions` + `/openai/v1/models`. Streaming SSE, multi-turn, multimodal image input.
- **MCP server**: 5 tools over streamable HTTP, at `/mcp/` on the API port when API mode is also on, otherwise on its own port (default `8081`) at the port root.
- **Telegram bot**: per-chat workspaces, file/photo/video/voice ingestion, slash commands.
- **Cron scheduler**: YAML-defined jobs with durable per-job artifacts.

## When To Use

- Run Claude Code from a script, Makefile target, or CI pipeline without a TTY (`claudebox -p "explain this diff" --output-format json`).
- Call a claudebox HTTP backend with `POST /run`, using a separate workspace subpath per caller. Subpaths are not a security boundary between untrusted tenants.
- Point an OpenAI SDK / LiteLLM at a claudebox as an agentic backend instead of a plain model API. Every completion runs the full Claude Code CLI (file I/O, shell, tools), not just text generation.
- Let another MCP-aware agent use this Claude Code instance as a tool over `/mcp/`.
- Talk to Claude from Telegram to ask questions and share files.

## When NOT To Use

- Real-time token-by-token streaming for tool-calling or JSON-schema-constrained runs. The OpenAI adapter buffers those (computes the full answer, replays as one SSE burst). Only plain chat (no `tools`, no `response_format` schema) streams incrementally.
- Multiple concurrent requests against the *same* workspace. API mode allows one active Claude process per workspace and returns `409` on conflict. Use distinct `workspace` subpaths for parallel work.
- Treating `--permission-mode bypassPermissions` as safe for untrusted input. Claude has full container access by design.
- Treating the MCP server as a sandbox. `run_prompt` has the same container authority as Claude, including mounted files.

## Interactive shell mode

Drop-in replacement for the native `claude` command, container-backed:

```bash
claudebox                  # interactive session, --continue applied automatically
claudebox --no-continue    # start a fresh session instead of resuming
```

Utility commands pass through without entering interactive mode:

```bash
claudebox --version         # claude CLI version
claudebox doctor            # health checks
claudebox mcp <args...>     # manage MCP servers, e.g. `claudebox mcp list`
claudebox stop              # stop the running interactive container for this workspace
claudebox clear-session     # delete session history for this workspace
```

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

## HTTP REST API

The API listens at `CLAUDEBOX_URL`. If the server has `CLAUDEBOX_API_MODE_TOKEN` set, send it as a bearer token.

```bash
curl -X POST "$CLAUDEBOX_URL/run" \
  -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "what does this repo do", "workspace": "myproject"}'
```

Key `/run` body fields: `prompt` (required), `workspace` (subpath under `/workspace`), `model`, `systemPrompt`, `appendSystemPrompt`, `jsonSchema`, `eventMode`, `outputFormat` (legacy), `noContinue`, `resume`, `fireAndForget`, `async`, `includeRaw` (raw stdout/stderr), `extraArgs`, `toolsAllowlist`, `noTools`, and `timeoutSeconds`. The Claude adapter always requests complete native records. Use `"eventMode": "full"` to return them in the stable `{sequence, attempt, backend, eventType, event}` envelope. `thinking` maps `low`, `medium`, `high`, `xhigh`, and `max` to Claude Code's `--effort` flag. `off` and `none` keep Claude Code's default. Every response carries a `runId`. Returns `409` if the target workspace is already busy.

**Async runs**: `"async": true` returns immediately with a `runId`; poll it:

```bash
curl -X POST "$CLAUDEBOX_URL/run" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN" -H "Content-Type: application/json" \
  -d '{"prompt": "refactor this codebase", "workspace": "myproject", "async": true}'
# → {"runId": "abc123", "workspace": "/workspace/myproject", "status": "running"}

curl "$CLAUDEBOX_URL/run/result?runId=abc123" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN"
# running → {"runId":..., "status": "running"}; completed → full result JSON (then purged from cache)
```

Completed/failed/cancelled results are returned once then purged; unread results expire after 6 hours. `GET /run/result?runId=X` 404s on unknown/already-read/expired IDs.

**File operations**: all paths relative to `/workspace`, path traversal blocked with `400`:

```bash
curl "$CLAUDEBOX_URL/files" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN"                          # list root
curl "$CLAUDEBOX_URL/files/myproject/src" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN"            # list dir
curl "$CLAUDEBOX_URL/files/myproject/src/main.py" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN"    # download
curl -X PUT "$CLAUDEBOX_URL/files/myproject/src/main.py" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN" --data-binary @main.py
curl -X DELETE "$CLAUDEBOX_URL/files/myproject/src/old.py" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN"
```

The delete call removes one file under `/workspace`. See [Security & safety](#security--safety) before using it.

**Introspection and lifecycle:**

```bash
curl "$CLAUDEBOX_URL/healthz"                                                                     # {"ok": true, "adapter": "claude"}, no auth
curl "$CLAUDEBOX_URL/status" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN"                 # {busyWorkspaces, runs}
curl -X DELETE "$CLAUDEBOX_URL/run/abc123" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN"   # cancel a run by id
```

## OpenAI-compatible endpoint

Served by the same API server; no separate URL. `chat/completions`-shaped adapter for LiteLLM, OpenAI SDKs, or any client speaking that wire format. Every request runs the full agentic CLI, not just text generation: Claude can read/write files and run shell commands as part of answering.

```bash
curl "$CLAUDEBOX_URL/openai/v1/models"
# {"object":"list","data":[{"id":"haiku",...},{"id":"sonnet",...},{"id":"opus",...},{"id":"opusplan",...}]}

curl -X POST "$CLAUDEBOX_URL/openai/v1/chat/completions" \
  -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"haiku","messages":[{"role":"user","content":"hello"}]}'

# streaming
curl -X POST "$CLAUDEBOX_URL/openai/v1/chat/completions" \
  -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN" \
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

**Tool calling and structured output are supported, not ignored.** `tools`/`tool_choice` engage a client-executed function-calling bridge (Claude Code acts as a pure function-calling model, emits `tool_calls` for the *client* to run), and `response_format` (`json_object` or `json_schema`) constrains the final answer turn. Both can combine in one request. Because a tool call or schema-checked answer only exists once the full response is computed, `stream:true` combined with `tools` or a schema `response_format` returns a **buffered** single-shot SSE stream instead of token-incremental deltas. Only plain chat (no tools, no schema) streams token-by-token.

Custom headers for claudebox-specific behavior (canonical `x-aicodebox-*`, with legacy `X-Claude-*` aliases still accepted):

| Header | Description |
| --- | --- |
| `x-aicodebox-workspace` (`X-Claude-Workspace`) | Workspace subpath under `/workspace` |
| `x-aicodebox-continue` (`X-Claude-Continue`) | `1`/`true`/`yes` to continue the previous session |
| `x-aicodebox-append-system-prompt` (`X-Claude-Append-System-Prompt`) | Text appended to the system prompt |
| `x-aicodebox-json-schema` | JSON-schema string, a fallback for clients that can't set `response_format` in the body (body field wins if both are set) |
| `x-aicodebox-resume` | Resume a specific session id |
| `x-aicodebox-tools-allowlist` | CSV or JSON array restricting Claude Code's own internal tools |
| `x-aicodebox-no-tools` | Disable Claude Code's own internal tools (auto-defaulted on when in client tool-calling mode) |

LiteLLM example:

```python
import litellm

response = litellm.completion(
    model="claudebox/haiku",
    messages=[{"role": "user", "content": "hello"}],
    api_base="http://localhost:8080/openai/v1",  # CLAUDEBOX_URL + /openai/v1
    api_key="your-api-token",  # the user's CLAUDEBOX_API_MODE_TOKEN, any string if none is configured
)
print(response.choices[0].message.content)
```

## MCP server

The MCP server speaks [Model Context Protocol](https://modelcontextprotocol.io/) over streamable HTTP, with `CLAUDEBOX_MCP_MODE_TOKEN` as its bearer token (independent of the API token, no fallback). When the API server also has MCP on, it is at `$CLAUDEBOX_URL/mcp/`. A standalone MCP server serves at the root of its own port (default `8081`), not under `/mcp`. Use the URL the user gives you.

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
claude mcp add --transport http claudebox "$CLAUDEBOX_URL/mcp/" \
  --header "Authorization: Bearer $CLAUDEBOX_MCP_MODE_TOKEN"
```

**Available tools:**

| Tool | Description |
| --- | --- |
| `run_prompt` | Run a prompt through Claude Code. Args: `prompt`, `workspace`, `model`, `system_prompt`, `append_system_prompt`, `no_continue` (default `true`), `resume`, `thinking` (`low`, `medium`, `high`, `xhigh`, and `max` map to Claude Code effort), `json_schema`. Returns the assistant's text. |
| `list_files` | List files/dirs under a workspace path. |
| `read_file` | Read a file's text content. |
| `write_file` | Write content to a file (creates parent dirs). |
| `delete_file` | Delete a file (refuses directories). |

`delete_file` follows the same guardrail as the file delete call, see [Security & safety](#security--safety).

Raw JSON-RPC for debugging (streamable-HTTP handshake: `initialize`, then reuse the returned `mcp-session-id`):

```bash
curl -s -D - -X POST "$CLAUDEBOX_URL/mcp/" \
  -H "Authorization: Bearer $CLAUDEBOX_MCP_MODE_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"debug","version":"1"}}}'
# capture the mcp-session-id response header, then:
curl -s -X POST "$CLAUDEBOX_URL/mcp/" \
  -H "Authorization: Bearer $CLAUDEBOX_MCP_MODE_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: <session-id-from-above>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

## Telegram bot

When the user's instance runs the Telegram bot, each chat has its own workspace and settings.

Bot commands: any text message is a prompt; sending a file/photo/video/voice saves it to the workspace (caption becomes the prompt); `/model [name]`, `/effort [level]`, `/system_prompt [text]`, `/append_system_prompt [text]`, `/fetch <path>`, `/cancel`, `/status`, `/config`, `/reload`. Claude sends files back with `[SEND_FILE: relative/path]` in its response text. `effort` (config field and `/effort` command) is passed to the `claude` CLI as `--effort`; `off` keeps Claude Code's default effort.

## Cron scheduler

When the user's instance runs the cron scheduler, YAML-defined Claude jobs run on five-field (minute) or six-field (second) cron schedules and can post results to Telegram. Each run records `meta.json`, `stdout.log`, `stderr.log` and `result.txt` under the instance's cron history. Job definitions are the operator's to manage; see the docs at https://psyb0t.github.io/docker-claudebox/.

## Typical Workflows

### Pipe a code review through CI

```bash
claudebox -p "review this diff for security issues" --output-format json --model sonnet | jq -r .result
```

### Drive claudebox from another agent over MCP

```bash
claude mcp add --transport http claudebox "$CLAUDEBOX_URL/mcp/" \
  --header "Authorization: Bearer $CLAUDEBOX_MCP_MODE_TOKEN"
```

### Fire-and-poll a long refactor over HTTP

```bash
RUN_ID=$(curl -s -X POST "$CLAUDEBOX_URL/run" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN" -H "Content-Type: application/json" \
  -d '{"prompt": "refactor the auth module", "workspace": "myproject", "async": true}' | jq -r .runId)

until curl -s "$CLAUDEBOX_URL/run/result?runId=$RUN_ID" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN" | jq -e '.status != "running"' >/dev/null; do
  sleep 5
done
curl -s "$CLAUDEBOX_URL/run/result?runId=$RUN_ID" -H "Authorization: Bearer $CLAUDEBOX_API_MODE_TOKEN" | jq
```

### Point LiteLLM at claudebox as an OpenAI-compatible backend

```python
import litellm
litellm.completion(model="claudebox/sonnet", messages=[{"role": "user", "content": "hello"}],
                    api_base="http://localhost:8080/openai/v1", api_key=API_TOKEN)
```
