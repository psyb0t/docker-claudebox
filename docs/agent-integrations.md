# Agent integrations

[Back to README](../README.md)

The [skill](../.agents/skills/claudebox) works in any agent that reads `.agents/skills/` (such as [peen](https://github.com/psyb0t/peen)). It tells agents to use the installed wrapper for local work and to use MCP only for an already-running remote server. It installs natively in the clients below.

### Claude Code

```bash
claude plugin marketplace add psyb0t/agents
claude plugin install claudebox@psyb0t
```

The Claude plugin declares configuration for the running server URL and its optional MCP bearer token. Configure the client to store that secret securely. The plugin does not start a server for you.

### Codex

```bash
codex plugin marketplace add psyb0t/agents
codex plugin add claudebox@psyb0t
```

Installed via the marketplace, the skill invokes as `$claudebox:claudebox`. Codex also picks the skill up automatically, with no install, in any repo containing `.agents/skills/`, where it invokes as plain `$claudebox`.

### OpenClaw

The release workflow publishes the skill to ClawHub when its publishing job succeeds:

```bash
openclaw skills install @psyb0t/claudebox
```

For MCP clients that speak local stdio, the [`@psyb0t/claudebox`](../.agents/plugins/claudebox) plugin bridges to the service's `/mcp/` endpoint:

```bash
openclaw plugins install clawhub:@psyb0t/claudebox
```

Then set `CLAUDEBOX_URL` (and `CLAUDEBOX_MCP_MODE_TOKEN` if the server requires auth).
