# Interactive Mode

```bash
claudebox
```

Runs an interactive Claude Code session inside a persistent container. The launcher applies `--continue` by default, with a fresh-session fallback when resuming fails. The wrapper supports its own flag set, not every native CLI argument. See [Programmatic mode](programmatic.md) and [wrapper lifecycle](../wrapper.md#container-lifecycle).

```bash
claudebox --update        # opt in to a Claude Code CLI update on this run
claudebox --no-continue   # start a fresh session instead of resuming the last one
```

## Utility commands

Some commands are passed through directly without entering interactive mode:

```bash
claudebox --version      # show the Claude Code CLI version
claudebox -v             # same thing
claudebox doctor         # run health checks
claudebox auth           # manage authentication
claudebox mcp <args...>  # manage MCP servers (e.g. `claudebox mcp list`, `claudebox mcp add ...`)
claudebox setup-token    # interactive OAuth token setup
claudebox stop           # stop the running interactive container for this workspace
claudebox clear-session  # delete session history for this workspace
```
