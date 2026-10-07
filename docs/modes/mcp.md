# MCP Mode

Expose Claude Code as a [Model Context Protocol](https://modelcontextprotocol.io/) server over streamable HTTP so other agents, IDEs, and MCP clients can drive it as a tool.

MCP is the one mode that is not a foreground mode. It coexists with whatever else the container is doing, which is the point: a box that runs cron jobs all day can also answer MCP calls the whole time.

## Two ways to get it

| | How it runs | Port |
| --- | --- | --- |
| **Inside API mode** | Mounted at `/mcp/` on the API server | The API port (`8080` by default) |
| **Standalone** | Its own uvicorn process, spawned as a sidecar at `/` | `CLAUDEBOX_MCP_MODE_PORT` (`8081` by default) |

Set `CLAUDEBOX_MCP_MODE=1` in every placement. With API mode it mounts at `/mcp/` instead of starting a second server. The slashless `/mcp` spelling also reaches the same handler without a redirect. In every other mode it starts a background process, and the container still exits when the foreground mode exits.

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
  - CLAUDEBOX_MCP_MODE_TOKEN=your-mcp-token
```

Two things here that will bite you if you assume otherwise:

- **An empty token means no auth at all.** Not "no access" — open. Anyone who can reach the port gets `run_prompt`, and `run_prompt` runs code. Leave it unset only when the port is bound to loopback or an internal network.
- **There is no fallback to the API token.** Setting `CLAUDEBOX_API_MODE_TOKEN` does nothing for MCP. To authenticate both surfaces, set both variables.

The token is accepted as either a header or a query parameter, since not every MCP client can set headers:

```
Authorization: Bearer your-mcp-token
```
```
http://host:8081/?apiToken=your-mcp-token
```

## Standalone alongside cron

Run scheduled jobs and expose the same box as a tool:

```yaml
# docker-compose.yml
services:
  claudebox:
    image: psyb0t/claudebox:latest
    init: true
    restart: unless-stopped
    ports:
      - "127.0.0.1:8081:8081"
    environment:
      - CLAUDEBOX_CRON_MODE=1
      - CLAUDEBOX_CRON_MODE_FILE=/home/aicode/.aicodebox/cron.yaml
      - CLAUDEBOX_MCP_MODE=1
      - CLAUDEBOX_MCP_MODE_TOKEN=${CLAUDEBOX_MCP_MODE_TOKEN:?set this in .env}
      - CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:?set this in .env}
    volumes:
      - ./claude-state:/home/aicode/.aicodebox
      - ./workspaces:/workspace
      - ./cron.yaml:/home/aicode/.aicodebox/cron.yaml:ro
    mem_limit: 2g
    cpus: 2
    pids_limit: 512
    logging:
      driver: local
      options:
        max-size: 10m
        max-file: "3"
```

Cron is the foreground process, so `docker logs` shows every tick and the container's lifetime follows the scheduler. MCP rides along in the background.

Swap `CLAUDEBOX_CRON_MODE` for `CLAUDEBOX_TELEGRAM_MODE` and the same thing holds for the bot. See [cron.md](cron.md) and [telegram.md](telegram.md) for those modes.

## Inside API mode

When API mode is already running, set `CLAUDEBOX_MCP_MODE=1` to mount MCP at `/mcp/` on the same port. No second port is needed:

```yaml
services:
  claudebox-api:
    image: psyb0t/claudebox:latest
    init: true
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      - CLAUDEBOX_API_MODE=1
      - CLAUDEBOX_API_MODE_TOKEN=${CLAUDEBOX_API_MODE_TOKEN:?set this in .env}
      - CLAUDEBOX_MCP_MODE=1
      - CLAUDEBOX_MCP_MODE_TOKEN=${CLAUDEBOX_MCP_MODE_TOKEN:?set this in .env}
      - CLAUDEBOX_AVAILABLE_MODELS=haiku,sonnet,opus,opusplan
      - CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:?set this in .env}
    volumes:
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

Reachable at `http://host:8080/mcp/`. The auth split above still applies: the mounted MCP surface reads `CLAUDEBOX_MCP_MODE_TOKEN`, so set it if you want `/mcp/` protected. See [api.md](api.md) for the rest of the API surface.

## Reverse proxies and public hosts

MCP keeps DNS rebinding protection enabled. Loopback hosts and origins work by default. If a reverse proxy, tunnel, or public DNS name forwards MCP, allow the exact values it sends. A browser MCP client also needs its exact Origin, including the scheme.

```dotenv
CLAUDEBOX_MCP_MODE_ALLOWED_HOSTS=localhost,localhost:*,127.0.0.1,127.0.0.1:*,[::1],[::1]:*,mcp.example.net
CLAUDEBOX_MCP_MODE_ALLOWED_ORIGINS=http://localhost:*,http://127.0.0.1:*,http://[::1]:*,https://mcp.example.net
```

An unexpected Host returns `421`, and an unexpected browser Origin returns `403`. Keep the port bound to loopback when a local proxy terminates TLS. Do not disable the protection or allow broad wildcards for an internet-facing endpoint.

## MCP mode environment variables

| Variable | Description | Default |
| --- | --- | --- |
| `CLAUDEBOX_MCP_MODE` | Set to `1` to expose the MCP server. Coexists with any foreground mode. | _(unset)_ |
| `CLAUDEBOX_MCP_MODE_PORT` | Port for the standalone server. Ignored when the foreground is API mode. | `8081` |
| `CLAUDEBOX_MCP_MODE_TOKEN` | Bearer token. Empty means no auth. No fallback to the API token. | _(unset)_ |
| `CLAUDEBOX_MCP_MODE_ALLOWED_HOSTS` | Comma-separated MCP `Host` allowlist. Add each proxy host name. | loopback hosts |
| `CLAUDEBOX_MCP_MODE_ALLOWED_ORIGINS` | Comma-separated MCP browser Origin allowlist. Add each proxy origin. | loopback HTTP origins |

> Every `CLAUDEBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Connecting a client

Point any MCP client at the streamable-HTTP endpoint:

```bash
claude mcp add --transport http claudebox http://host:8081/ \
  --header "Authorization: Bearer your-mcp-token"
```
