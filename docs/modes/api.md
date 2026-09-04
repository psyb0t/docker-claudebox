# API Mode

Run the container as an HTTP API server with workspace management, file operations, and optional authentication. This is the mode that powers the OpenAI-compatible adapter and MCP server as well.

```yaml
# docker-compose.yml
services:
  claudebox:
    image: psyb0t/claudebox:latest
    ports:
      - "8080:8080"
    environment:
      - CLAUDEBOX_API_MODE=1
      - CLAUDEBOX_API_MODE_TOKEN=your-secret-token
      - CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-xxx
    volumes:
      - ~/.claude:/home/aicode/.claude
      - /your/projects:/workspace
      - /var/run/docker.sock:/var/run/docker.sock
```

| Variable                   | Description                                                         | Default  |
| -------------------------- | ------------------------------------------------------------------- | -------- |
| `CLAUDEBOX_API_MODE`       | Set to `1` to start in API server mode                              | _(none)_ |
| `CLAUDEBOX_API_MODE_PORT`  | Port the API server listens on                                      | `8080`   |
| `CLAUDEBOX_API_MODE_TOKEN` | Bearer token for API authentication (if unset, no auth is required) | _(none)_ |
| `DEBUG`                    | Set to `1` or `true` for structured JSON debug logging              | _(none)_ |

> Legacy `CLAUDE_MODE_API`, `CLAUDE_MODE_API_PORT`, `CLAUDE_MODE_API_TOKEN` are still accepted as fallbacks.

The API server outputs structured JSON logs (timestamp, level, logger, function name, line number, and file) for every request, error, and lifecycle event.

## API Endpoints

**`POST /run`** — send a prompt to Claude Code and get a JSON response:

```bash
curl -X POST http://localhost:8080/run \
  -H "Authorization: Bearer your-secret-token" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "what does this repo do", "workspace": "myproject"}'
```

| Field                | Type   | Description                                                                               | Default         |
| -------------------- | ------ | ----------------------------------------------------------------------------------------- | --------------- |
| `prompt`             | string | The prompt to send to Claude Code                                                         | _(required)_    |
| `workspace`          | string | Subpath under `/workspace` (e.g., `myproject` resolves to `/workspace/myproject`)       | `/workspace`   |
| `model`              | string | Model alias or full model name (see [Model Selection](programmatic.md#model-selection))                  | account default |
| `systemPrompt`       | string | Replace the default system prompt entirely                                                | _(none)_        |
| `appendSystemPrompt` | string | Append text to the default system prompt without replacing it                             | _(none)_        |
| `jsonSchema`         | object | A JSON Schema object for structured output. Claude will return JSON matching this schema | _(none)_        |
| `thinking`           | string | Accepted by the shared request model. The current Claude adapter does not map it to a CLI flag. | _(none)_        |
| `eventMode`          | string | `auto`, `none`, or `full`. `full` returns complete native Claude stream records           | `auto`          |
| `outputFormat`       | string | Legacy compatibility: `json-verbose` selects full events while `eventMode` is `auto`; `text` and `json` do not change the response shape | _(none)_        |
| `noContinue`         | bool   | If true, start a fresh session instead of continuing the previous one                     | `false`         |
| `resume`             | string | Resume a specific session by its session ID                                               | _(none)_        |
| `fireAndForget`      | bool   | Submit in the background and mark the immediate acknowledgement with `fireAndForget: true` | `false`         |
| `async`              | bool   | If true, return immediately with a `runId` and run in the background                      | `false`         |

Every response includes a `runId` field that uniquely identifies the run.

Set `"eventMode": "full"` to return the complete Claude `stream-json` output, including partial assistant messages, tool use, tool results, hook events, subagent text, and final usage. Each response record has the stable envelope `{sequence, attempt, backend, eventType, event}`. The nested `event` is the original Claude record with no field removal or tool-result truncation. `"eventMode": "none"` returns only the final result. The default `"auto"` keeps the historical behavior of including events for a `jsonSchema` request or `"outputFormat": "json-verbose"`. `"outputFormat": "text"` and `"outputFormat": "json"` remain accepted legacy inputs but do not change the response serialization.

`jsonSchema` validates only the final JSON output and can be combined with either event mode.

Returns `application/json`. Returns **409** if the workspace is already busy with another request.

**Async runs** — when `"async": true` is set, the request returns immediately with a run ID:

```bash
# fire off an async run
curl -X POST http://localhost:8080/run \
  -H "Authorization: Bearer token" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "refactor this entire codebase", "workspace": "myproject", "async": true}'
# → {"runId": "abc123", "workspace": "/workspace/myproject", "status": "running", "fireAndForget": false}

# poll for the result
curl "http://localhost:8080/run/result?runId=abc123" -H "Authorization: Bearer token"
# while running → {"runId": "abc123", "workspace": "/workspace/myproject", "status": "running"}
# when done    → full result JSON with runId + workspace injected (see below)
```

Completed results are cached until first read — once you fetch a completed result, it is purged from the cache. Results that are never read are automatically purged after 6 hours. Failed and cancelled results are also returned once and purged.

**`GET /run/result?runId=X`** — poll for the result of an async (or any) run:

| Status      | Response                                                                                 |
| ----------- | ---------------------------------------------------------------------------------------- |
| `running`   | `{"runId": "...", "workspace": "...", "status": "running"}`                              |
| `completed` | Full result JSON with `runId` and `workspace` injected (then purged from cache)          |
| `failed`    | `{"runId": "...", "workspace": "...", "status": "failed", "error": "..."}` (then purged) |
| `cancelled` | `{"runId": "...", "workspace": "...", "status": "cancelled"}` (then purged)              |

Returns **404** if the run ID is not found (never existed, already read, or expired).

Completed result example:

```json
{
  "runId": "abc123",
  "workspace": "/workspace/myproject",
  "status": "completed",
  "exitCode": 0,
  "text": "the response text",
  "usage": { "input_tokens": 100, "output_tokens": 50 },
  "sessionId": "..."
}
```

**`GET /files/{path}`** — list a directory or download a file:

```bash
curl "http://localhost:8080/files" -H "Authorization: Bearer token"                         # list workspace root
curl "http://localhost:8080/files/myproject/src" -H "Authorization: Bearer token"           # list a subdirectory
curl "http://localhost:8080/files/myproject/src/main.py" -H "Authorization: Bearer token"   # download a file
```

Directory listing response:

```json
{
  "path": "myproject/src",
  "entries": [
    { "name": "main.py", "type": "file", "size": 1234 },
    { "name": "utils", "type": "dir" }
  ]
}
```

File download returns raw file content with appropriate content type.

**`PUT /files/{path}`** — upload a file (parent directories are created automatically):

```bash
curl -X PUT "http://localhost:8080/files/myproject/src/main.py" \
  -H "Authorization: Bearer token" --data-binary @main.py
# → {"status": "ok", "path": "/workspace/myproject/src/main.py", "size": 1234}
```

**`DELETE /files/{path}`** — delete a file:

```bash
curl -X DELETE "http://localhost:8080/files/myproject/src/old.py" -H "Authorization: Bearer token"
# → {"status": "ok", "path": "/workspace/myproject/src/old.py"}
```

**`GET /healthz`**: health check endpoint (no authentication required):

```json
{ "ok": true, "adapter": "claude" }
```

**`GET /status`** — returns busy workspaces and all tracked runs (running, completed, failed, cancelled):

```json
{
  "busyWorkspaces": ["/workspace/myproject"],
  "runs": [
    {
      "runId": "abc123",
      "workspace": "/workspace/myproject",
      "status": "running"
    }
  ]
}
```

**`DELETE /run/{runId}`**: cancel a running Claude process by run ID:

```bash
curl -X DELETE "http://localhost:8080/run/abc123" -H "Authorization: Bearer token"
# → {"runId": "abc123", "status": "cancelled"}
```

All file paths are relative to `/workspace`. Path traversal attempts outside the workspace root are blocked and return a 400 error.

## OpenAI-Compatible Endpoints

claudebox exposes an OpenAI-compatible adapter so tools like [LiteLLM](https://github.com/BerriAI/litellm), OpenAI SDKs, and anything that speaks the `chat/completions` protocol can connect directly. This is not a simple model proxy — every request runs the full Claude Code agentic CLI behind the scenes, meaning Claude can read and write files, run shell commands, and use all of its tools.

**`GET /openai/v1/models`** — list available models:

```bash
curl http://localhost:8080/openai/v1/models
# {"object":"list","data":[{"id":"haiku",...},{"id":"sonnet",...},{"id":"opus",...},{"id":"opusplan",...}]}
```

**`POST /openai/v1/chat/completions`** — chat completions (streaming and non-streaming):

```bash
# non-streaming
curl -X POST http://localhost:8080/openai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"haiku","messages":[{"role":"user","content":"hello"}]}'

# streaming (SSE)
curl -X POST http://localhost:8080/openai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"haiku","messages":[{"role":"user","content":"hello"}],"stream":true}'
```

**Model names:** use the same aliases as the CLI (`haiku`, `sonnet`, `opus`, `opusplan`). Provider prefixes are stripped automatically — `claudebox/haiku` becomes `haiku`, `openai/sonnet` becomes `sonnet`.

**System messages:** messages with `role: "system"` are extracted and passed to Claude Code as `--system-prompt`.

**Reasoning effort:** `reasoning_effort` is accepted by the shared OpenAI request model, but the current Claude adapter does not map it to a Claude Code flag.

**Client-executed tools:** standard `tools` and `tool_choice` are supported. A tool-call turn returns OpenAI `tool_calls`; the client runs the selected function and sends the `role: "tool"` result in the next request. Internal agent tools default off for that turn. Send `x-aicodebox-no-tools: 0` to keep them enabled.

**Structured output:** standard `response_format` supports `json_object` and `json_schema`. It composes with client-executed tools: tool-call turns are not schema-checked, and the final answer is validated against the requested schema.

**Ignored fields:** `temperature`, `max_tokens`, and unsupported OpenAI fields are accepted without effect.

**Message handling:**

- **Single user message** — sent directly as the prompt to Claude Code. This is the fast path with no overhead.
- **Multi-turn conversations** — the full messages array is serialized to a JSON file in the workspace (`_oai_uploads/conv_<id>.json`). Claude Code reads the file and responds to the last user message, preserving the full conversation context.
- **Multimodal content** — base64-encoded images and image URLs in message content are automatically downloaded or decoded and saved to the workspace. The content blocks are replaced with local file paths so Claude Code can access the images directly.

**Streaming:** when `"stream": true` is set, the response is returned as standard SSE (Server-Sent Events). Content arrives in message-level chunks rather than character-by-character deltas, since Claude Code assembles complete messages internally.

**File workflow tip:** for best performance with large inputs or outputs, upload files via `PUT /files/...`, reference them by path in your prompt, and then download output files via `GET /files/...`. This is significantly faster than embedding large content directly in message bodies.

**Custom headers** for claudebox-specific behavior:

| Header | Description |
| --- | --- |
| `X-Aicodebox-Workspace` | Workspace subpath under `/workspace`. `X-Claude-Workspace` remains an alias. |
| `X-Aicodebox-Continue` | Set to `1`, `true`, or `yes` to continue the previous session. `X-Claude-Continue` remains an alias. |
| `X-Aicodebox-Append-System-Prompt` | Text to append to the system prompt. `X-Claude-Append-System-Prompt` remains an alias. |
| `X-Aicodebox-Json-Schema` | JSON Schema fallback when the request has no `response_format`. |
| `X-Aicodebox-Resume` | Specific session ID to resume. |
| `X-Aicodebox-Extra-Args` | JSON array or comma-separated CLI arguments. |
| `X-Aicodebox-Timeout-Seconds` | Positive timeout in seconds. |
| `X-Aicodebox-Tools-Allowlist` | JSON array or comma-separated internal tool allowlist. |
| `X-Aicodebox-No-Tools` | Boolean that disables internal agent tools. |

**LiteLLM integration example:**

```python
import litellm

response = litellm.completion(
    model="claudebox/haiku",
    messages=[{"role": "user", "content": "hello"}],
    api_base="http://localhost:8080/openai/v1",
    api_key="your-secret-token",  # or any string if no API token is configured
)
print(response.choices[0].message.content)
```

## MCP Server

claudebox exposes an [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) server at `/mcp/` using streamable HTTP transport. Any MCP-compatible client — Claude Desktop, other Claude Code instances, AI agent frameworks — can connect to it and use Claude Code as a tool. The `claude_run` tool executes the full agentic CLI, meaning it can read/write files, run commands, and use tools in the workspace, not just generate text.

**Configuration for MCP clients:**

```json
{
  "mcpServers": {
    "claudebox": {
      "url": "http://localhost:8080/mcp/",
      "headers": { "Authorization": "Bearer your-secret-token" }
    }
  }
}
```

If your MCP client does not support custom headers, you can pass the API token as a query parameter instead: `http://localhost:8080/mcp/?apiToken=your-secret-token`

**Available tools:**

| Tool          | Description                                                                                                                                                             |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude_run`  | Run a prompt through Claude Code. Parameters: `prompt`, `model`, `system_prompt`, `append_system_prompt`, `json_schema`, `workspace`, `no_continue`, `resume`, `thinking` |
| `list_files`  | List files and directories in the workspace                                                                                                                             |
| `read_file`   | Read the contents of a file from the workspace                                                                                                                          |
| `write_file`  | Write content to a file in the workspace (creates parent directories automatically)                                                                                     |
| `delete_file` | Delete a file from the workspace                                                                                                                                        |
