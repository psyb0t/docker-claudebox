# Customization

[Back to README](../README.md)

With the standard wrapper, the host's `~/.claude` supplies the persistent state directory. The entrypoint aliases it to `/home/aicode/.aicodebox` inside the container. In server Compose deployments, use the directory mounted at `/home/aicode/.aicodebox` instead.

## Custom scripts (`~/.claude/bin`)

Executables in the state directory's `bin/` are on PATH before the system tools, in interactive and server modes, init scripts, and container shells.

```bash
mkdir -p ~/.claude/bin
printf '#!/bin/sh\nprintf "hello from custom script\\n"\n' > ~/.claude/bin/my-tool
chmod +x ~/.claude/bin/my-tool
```

Only put trusted executables here. They can override system command names.

## Init hooks (`~/.claude/init.d`)

The base runs image scripts from `/aicodebox-init.d/*.sh`, then user scripts from the state directory's `init.d/*.sh`, in filename order. Both run as `aicode` with passwordless sudo, not root. Use sudo for system package installation.

```bash
mkdir -p ~/.claude/init.d
printf '#!/bin/bash\nset -euo pipefail\nsudo apt-get update\nsudo apt-get install -y make\n' > ~/.claude/init.d/setup.sh
```

The entrypoint invokes these files with Bash, so an executable bit is not required. Scripts run once per container. Restarting that container does not rerun them; creating another container does. A failing script is logged, and the entrypoint continues with the remaining scripts. Fix failures before relying on the installed tools.

## Always-active skills (`~/.claude/.always-skills`)

Put a `SKILL.md` in each skill directory. The launcher and adapter scan recursively in sorted path order and append every nonempty skill to the system prompt on Claude prompt invocations across CLI and server modes.

```bash
mkdir -p ~/.claude/.always-skills/my-rules
printf 'Before editing, read the project documentation and applicable rules.\n' > ~/.claude/.always-skills/my-rules/SKILL.md
```

Each block starts with its container path:

```text
[Skill file: /home/aicode/.claude/.always-skills/my-rules/SKILL.md]
```

Keep adjacent resources with the skill when its instructions refer to them. Copying only `SKILL.md` from another plugin may leave those references broken.

The shared system hint comes first, then always-active skills. The server adapter appends the caller's `appendSystemPrompt` afterward. This is prompt composition, not an enforced instruction-priority or security boundary. Utility subcommands such as `auth`, `mcp`, and `--version` bypass prompt injection.

Set `CLAUDEBOX_ALWAYS_SKILLS_DIR` or `CLAUDEBOX_SYSTEM_HINT_FILE` inside the container to change those sources. With the wrapper, use `CLAUDEBOX_ENV_CLAUDEBOX_ALWAYS_SKILLS_DIR` or `CLAUDEBOX_ENV_CLAUDEBOX_SYSTEM_HINT_FILE`.

## External MCP servers

This configures servers Claude Code can call. It is separate from exposing Claudebox itself through [MCP mode](modes/mcp.md).

The image sets `CLAUDE_CONFIG_DIR=/home/aicode/.claude`. The current Claude init script and adapter use `$CLAUDE_CONFIG_DIR/.claude.json` for Claude configuration. With the standard wrapper, that is the host's `~/.claude/.claude.json`, not its separate `~/.claude.json`.

| Scope | Location inside the container |
| --- | --- |
| Project | `<workspace>/.mcp.json` |
| User | `$CLAUDE_CONFIG_DIR/.claude.json`, under `mcpServers` |
| Local | Per-project entries in the same configuration file |

A project example using a remote server:

```json
{
  "mcpServers": {
    "my-server": {
      "type": "http",
      "url": "https://mcp.example.net/mcp/"
    }
  }
}
```

Add it through the installed wrapper:

```bash
claudebox mcp add --transport http --scope project my-server https://mcp.example.net/mcp/
claudebox mcp list
```

Use `--scope user` for configuration shared across projects, or omit the scope for a local project entry. Run `/mcp` in an interactive Claude session to inspect the loaded servers. Keep credentials out of tracked MCP configuration.
