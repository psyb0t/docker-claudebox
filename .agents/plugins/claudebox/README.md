# @psyb0t/claudebox

An OpenClaw/MCP plugin that connects your agent to a self-hosted
[claudebox](https://github.com/psyb0t/docker-claudebox) instance — Claude Code
running in a Docker container — over the
[Model Context Protocol](https://modelcontextprotocol.io).

claudebox serves a Streamable-HTTP MCP endpoint at `/mcp` when the container
is started with `CLAUDEBOX_API_MODE=1` and `CLAUDEBOX_MCP_MODE=1`. This
package is a thin stdio↔HTTP bridge (via
[`mcp-remote`](https://www.npmjs.com/package/mcp-remote)) for MCP clients that
speak local stdio servers — it forwards everything to your running claudebox
instance and authenticates with your bearer token when the server requires one.

> claudebox is **self-hosted**. This plugin does not ship the container — it
> connects to a claudebox instance that **you** run. See the
> [claudebox repo](https://github.com/psyb0t/docker-claudebox) to stand one up.

## Tools

The 5 claudebox MCP tools become available to your agent: `run_prompt` (run a
prompt through the containerized Claude Code CLI — full file, shell, and tool
access to the workspace, not just text generation), plus `list_files`,
`read_file`, `write_file`, and `delete_file` for workspace file operations.

## Configuration

| Env var | Required | Description |
|---|---|---|
| `CLAUDEBOX_URL` | yes | Base URL of your running claudebox server, e.g. `http://localhost:8080`. The bridge appends `/mcp`. |
| `CLAUDEBOX_MCP_MODE_TOKEN` | no | Bearer token — only if the claudebox server was started with `CLAUDEBOX_MCP_MODE_TOKEN` set. |

The server needs `CLAUDEBOX_API_MODE=1` and `CLAUDEBOX_MCP_MODE=1` set for
`/mcp` to be mounted — see the
[claudebox MCP mode docs](https://github.com/psyb0t/docker-claudebox/blob/master/.agents/skills/claudebox/SKILL.md).

## Install

Install it into your OpenClaw agent from ClawHub:

```bash
openclaw plugins install clawhub:@psyb0t/claudebox
```

Then set `CLAUDEBOX_URL` (and `CLAUDEBOX_MCP_MODE_TOKEN` if your server uses
auth) in the plugin's environment.

## Native remote MCP (no install)

If your MCP client already supports **remote** Streamable-HTTP servers, you
don't need this bridge — point the client straight at
`$CLAUDEBOX_URL/mcp` with an `Authorization: Bearer <token>` header.

## License

MIT. See [LICENSE](LICENSE).
