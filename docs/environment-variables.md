# Environment variables

Wrapper and installer settings belong on the host. Settings intended for the running container must be forwarded with `CLAUDEBOX_ENV_*`, except the documented compatibility variables and the wrapper's cron shortcut. Bare `CLAUDEBOX_API_MODE=1 claudebox` is not forwarded automatically; use `CLAUDEBOX_ENV_CLAUDEBOX_API_MODE=1 claudebox` or set the variable directly in a server Compose configuration.

Claudebox-specific wrapper and installer settings use the `CLAUDEBOX_*` prefix. Anything you want available **inside** the container goes through `CLAUDEBOX_ENV_*` with the prefix stripped. `AICODEBOX_ENV_*` and `AICODEBOX_MOUNT_*` are shared wrapper settings. Legacy `CLAUDE_*` / `CLAUDE_ENV_*` / `CLAUDE_MOUNT_*` and bare `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` / `DEBUG` still work for backwards compatibility.

| Variable                   | Description                                                                                | Default                   |
| -------------------------- | ------------------------------------------------------------------------------------------ | ------------------------- |
| `CLAUDEBOX_GIT_NAME`       | Set the runtime user's global Git name before init hooks and agent startup             | _(none)_                  |
| `CLAUDEBOX_GIT_EMAIL`      | Set the runtime user's global Git email before init hooks and agent startup            | _(none)_                  |
| `CLAUDEBOX_DATA_DIR`       | Override the `.claude` data directory on the host                                          | `~/.claude`               |
| `CLAUDEBOX_SSH_DIR`        | Override the SSH key directory mounted into the container                                  | `~/.ssh/claudebox`        |
| `CLAUDEBOX_INSTALL_DIR`    | Where to install the wrapper binary (install-time only)                                    | `/usr/local/bin`          |
| `CLAUDEBOX_BIN_NAME`       | Name of the wrapper binary (install-time only)                                             | `claudebox`               |
| `CLAUDEBOX_IMAGE`          | Override the Docker image used by the wrapper                                              | `psyb0t/claudebox:latest` |
| `CLAUDEBOX_FULL`           | `0` selects minimal, `1` selects full; other nonempty values fail. Default is `latest` (minimal). Setting it at install time bakes the choice into the installed wrapper, so the full variant sticks for every run without re-exporting the var; runtime `0` or `1` overrides that choice for a newly created container. `CLAUDEBOX_IMAGE` remains the explicit image override. Pre-v2 `CLAUDEBOX_MINIMAL=1` is now a no-op. | _(none)_ |
| `CLAUDEBOX_INSTALL_REF` | Wrapper source tag or commit for remote installation. Defaults to the installer's embedded release ref; see [Installation](wrapper.md#review-before-running). | embedded ref |
| `CLAUDEBOX_CONTAINER_NAME` | Override the per-workspace container name                                                  | derived from `$PWD`       |
| `CLAUDEBOX_MAX_MEM`        | Memory limit for wrapper-created interactive containers (e.g. `16g`, `4g`), not programmatic or cron containers                                  | `10g`                     |
| `CLAUDEBOX_ENV_*`          | Forward env vars into the container (prefix stripped: `CLAUDEBOX_ENV_FOO=bar` → `FOO=bar`) | _(none)_                  |
| `CLAUDEBOX_MOUNT_*`        | Mount extra host directories into the container                                            | _(none)_                  |
| `AICODEBOX_ENV_*`          | Forward a shared environment variable into the launched container, with the prefix stripped | _(none)_                  |
| `AICODEBOX_MOUNT_*`        | Mount a shared host directory into the launched container                                  | _(none)_                  |

Auth and in-container settings go through `CLAUDEBOX_ENV_*`. The entrypoint maps its supported `CLAUDEBOX_*` mode aliases to `AICODEBOX_*`; an already-set `AICODEBOX_*` value wins. Mode-specific settings are documented in [API](modes/api.md), [MCP](modes/mcp.md), [Telegram](modes/telegram.md), and [cron](modes/cron.md).

| Setting inside the container | Purpose |
| --- | --- |
| `CLAUDEBOX_CLAUDE_VERSION` | CLI version installed if Claude Code is absent. Does not replace an installed CLI. |
| `CLAUDEBOX_ALWAYS_SKILLS_DIR` | Always-active skills directory, default `/home/aicode/.claude/.always-skills`. |
| `CLAUDEBOX_SYSTEM_HINT_FILE` | System hint file, default `/home/aicode/.claude/system-hint.txt`. |

Forwarded authentication and debug examples:

| Forwarded as                     | Set on host as                                 |
| -------------------------------- | ---------------------------------------------- |
| `ANTHROPIC_API_KEY`              | `CLAUDEBOX_ENV_ANTHROPIC_API_KEY`              |
| `CLAUDE_CODE_OAUTH_TOKEN`        | `CLAUDEBOX_ENV_CLAUDE_CODE_OAUTH_TOKEN`        |
| `DEBUG`                          | `CLAUDEBOX_ENV_DEBUG`                          |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | `CLAUDEBOX_ENV_CLAUDE_CODE_DISABLE_1M_CONTEXT` |

## Forwarding environment variables

The `CLAUDEBOX_ENV_` prefix injects arbitrary env vars into the container. The prefix is stripped before forwarding:

```bash
# inside the container these become: GITHUB_TOKEN=xxx, MY_VAR=hello
CLAUDEBOX_ENV_GITHUB_TOKEN=xxx CLAUDEBOX_ENV_MY_VAR=hello claudebox -p "do stuff"
```

## Extra volume mounts

The `CLAUDEBOX_MOUNT_` prefix mounts additional host directories into the container:

```bash
CLAUDEBOX_MOUNT_DATA=/data claudebox -p "process the data"                    # same path inside container
CLAUDEBOX_MOUNT_1=/opt/configs CLAUDEBOX_MOUNT_2=/var/logs claudebox -p "go"  # mount multiple directories
CLAUDEBOX_MOUNT_STUFF=/host/path:/container/path claudebox -p "do stuff"      # explicit source:dest mapping
CLAUDEBOX_MOUNT_RO=/data:/data:ro claudebox -p "read the data"                # read-only mount
```

If the value contains `:`, it is passed directly as Docker `-v` syntax. Otherwise, the same path is used on both host and container sides.

The wrapper does not forward an SSH agent automatically. To give the box one, mount the agent socket and forward `SSH_AUTH_SOCK` with the prefix stripped:

```bash
CLAUDEBOX_MOUNT_SSH="$SSH_AUTH_SOCK:/ssh-agent:ro" CLAUDEBOX_ENV_SSH_AUTH_SOCK=/ssh-agent claudebox
```

Every key loaded in that agent becomes usable inside the box.

The standard wrapper also mounts `/var/run/docker.sock` so Claude can manage host containers. Server deployments should use the Compose examples instead when they do not need that authority.

For server-mode MCP settings, use `CLAUDEBOX_MCP_MODE_ALLOWED_HOSTS` and `CLAUDEBOX_MCP_MODE_ALLOWED_ORIGINS` inside the container. With the wrapper, forward them as `CLAUDEBOX_ENV_CLAUDEBOX_MCP_MODE_ALLOWED_HOSTS` and `CLAUDEBOX_ENV_CLAUDEBOX_MCP_MODE_ALLOWED_ORIGINS`.

## Sibling boxes

Install `claudebox`, `codexbox`, and `pibox` in the same command directory, normally `/usr/local/bin`, to make the sibling commands available inside a box. The parent wrapper mounts only those wrapper files read-only. A sibling wrapper then uses the host Docker daemon and its recorded host paths to mount its own data directory. `AICODEBOX_HOST_*` is this internal, versioned launch context. Leave it unset for an ordinary host launch.

Reused containers keep their original mounts, environment, and image. Changing host settings does not reconfigure an existing container. See [Container lifecycle](wrapper.md#container-lifecycle).
