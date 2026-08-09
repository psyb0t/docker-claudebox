# MCP Mode

Expose Claude Code as a [Model Context Protocol](https://modelcontextprotocol.io/) server over streamable HTTP, so other agents — Claude Desktop, another Claude Code, an IDE, anything that speaks MCP — can drive it as a tool.

MCP is the one mode that is not a foreground mode. It coexists with whatever else the container is doing, which is the point: a box that runs cron jobs all day can also answer MCP calls the whole time.

## Two ways to get it

| | How it runs | Port |
| --- | --- | --- |
| **Inside API mode** | Mounted at `/mcp` on the API server — no extra process | The API port (`8080` by default) |
| **Standalone** | Its own uvicorn process, spawned as a sidecar | `CLAUDEBOX_MCP_MODE_PORT` (`8081` by default) |

Setting `CLAUDEBOX_MCP_MODE=1` while the foreground **is** API mode does not start a second server — the MCP surface is already mounted at `/mcp`. In every other mode (telegram, cron, interactive) it starts as a background process, and the container still exits when the foreground mode exits.

## Tools

| Tool | Arguments | What it does |
| --- | --- | --- |
| `run_prompt` | `prompt`, `workspace`, `model`, `system_prompt`, `append_system_prompt`, `no_continue`, `resume`, `thinking`, `json_schema` | Runs a prompt through Claude Code and returns the response |
| `list_files` | `path` | Lists a directory under the workspace root |
| `read_file` | `path` | Reads a file |
| `write_file` | `path`, `content` | Writes a file |
| `delete_file` | `path` | Removes a file |

Only `prompt` is required on `run_prompt`; everything else has a default. It defaults to `no_continue=True`, so each call is a fresh session unless you pass `resume` with a session id. `workspace` is a subpath under the workspace root, so several callers can share one container without sharing a directory.

Prefer the file tools over stuffing large payloads into `prompt`. The agent can read and write the workspace itself, so "write the input to a file, then tell it which file" beats a 50 KB prompt.

## Paths are confined to the workspace

The four file tools resolve their `path` under the workspace root and reject anything that climbs out of it:

```
path escapes workspace root
```

The check happens after resolution, so `..` segments and symlinks are both caught.

What this does **not** sandbox is `run_prompt` — Claude Code runs with the container's own permissions and reaches whatever the container reaches. The confinement applies to the file tools, not to the agent.

## Auth

```yaml
environment:
  - CLAUDEBOX_MCP_MODE=1
  - CLAUDEBOX_MCP_MODE_TOKEN=some-long-random-string
```

Two things here that will bite you if you assume otherwise:

- **An empty token means no auth at all.** Not "no access" — open. Anyone who can reach the port gets `run_prompt`, and `run_prompt` runs code. Leave it unset only when the port is bound to loopback or an internal network.
- **There is no fallback to the API token.** Setting `CLAUDEBOX_API_MODE_TOKEN` does nothing for MCP. To authenticate both surfaces, set both variables.

The token is accepted as either a header or a query parameter, since not every MCP client can set headers:

```
Authorization: Bearer some-long-random-string
```
```
http://host:8081/mcp?apiToken=some-long-random-string
```

## Standalone alongside cron

The combination worth having — scheduled jobs running on their own, and the same box reachable as a tool while they run:

```yaml
# docker-compose.yml
services:
  claudebox:
    image: psyb0t/claudebox:latest
    ports:
      - "8081:8081"
    environment:
      - CLAUDEBOX_CRON_MODE=1
      - CLAUDEBOX_CRON_MODE_FILE=/home/aicode/.claude/cron.yaml
      - CLAUDEBOX_MCP_MODE=1
      - CLAUDEBOX_MCP_MODE_TOKEN=some-long-random-string
      - CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-xxx
    volumes:
      - ~/.claude:/home/aicode/.claude
      - ~/workspaces:/workspace
```

Cron is the foreground process, so `docker logs` shows every tick and the container's lifetime follows the scheduler. MCP rides along in the background.

Swap `CLAUDEBOX_CRON_MODE` for `CLAUDEBOX_TELEGRAM_MODE` and the same thing holds for the bot. See [cron.md](cron.md) and [telegram.md](telegram.md) for those modes.

## Inside API mode

If the API is already running, MCP comes with it at `/mcp` on the same port — no second port to publish, no `CLAUDEBOX_MCP_MODE` needed:

```yaml
services:
  claudebox-api:
    image: psyb0t/claudebox:latest
    ports:
      - "8080:8080"
    environment:
      - CLAUDEBOX_API_MODE=1
      - CLAUDEBOX_API_MODE_TOKEN=some-long-random-string
      - CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-xxx
```

Reachable at `http://host:8080/mcp`. The auth split above still applies: the mounted MCP surface reads `CLAUDEBOX_MCP_MODE_TOKEN`, so set it if you want `/mcp` protected. See [api.md](api.md) for the rest of the API surface.

## MCP mode environment variables

| Variable | Description | Default |
| --- | --- | --- |
| `CLAUDEBOX_MCP_MODE` | Set to `1` to expose the MCP server. Coexists with any foreground mode. | _(unset)_ |
| `CLAUDEBOX_MCP_MODE_PORT` | Port for the standalone server. Ignored when the foreground is API mode. | `8081` |
| `CLAUDEBOX_MCP_MODE_TOKEN` | Bearer token. Empty means no auth. No fallback to the API token. | _(unset)_ |

> Every `CLAUDEBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Connecting a client

Point any MCP client at the streamable-HTTP endpoint:

```bash
claude mcp add --transport http claudebox http://host:8081/mcp \
  --header "Authorization: Bearer some-long-random-string"
```
