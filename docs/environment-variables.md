# Environment Variables

Set these on your host (e.g., in `~/.bashrc` or `~/.zshrc`). The wrapper script forwards them into the container automatically. These apply across all modes.

Claudebox-specific wrapper and installer settings use the `CLAUDEBOX_*` prefix.
Anything you want available **inside** the container goes through
`CLAUDEBOX_ENV_*` with the prefix stripped. `AICODEBOX_ENV_*` and
`AICODEBOX_MOUNT_*` are shared wrapper settings. Legacy `CLAUDE_*` /
`CLAUDE_ENV_*` / `CLAUDE_MOUNT_*` and bare `ANTHROPIC_API_KEY` /
`CLAUDE_CODE_OAUTH_TOKEN` / `DEBUG` still work for backwards compatibility.

| Variable                   | Description                                                                                | Default                   |
| -------------------------- | ------------------------------------------------------------------------------------------ | ------------------------- |
| `CLAUDEBOX_GIT_NAME`       | Git `user.name` inside the container                                                       | _(none)_                  |
| `CLAUDEBOX_GIT_EMAIL`      | Git `user.email` inside the container                                                      | _(none)_                  |
| `CLAUDEBOX_DATA_DIR`       | Override the `.claude` data directory on the host                                          | `~/.claude`               |
| `CLAUDEBOX_SSH_DIR`        | Override the SSH key directory mounted into the container                                  | `~/.ssh/claudebox`        |
| `CLAUDEBOX_INSTALL_DIR`    | Where to install the wrapper binary (install-time only)                                    | `/usr/local/bin`          |
| `CLAUDEBOX_BIN_NAME`       | Name of the wrapper binary (install-time only)                                             | `claudebox`               |
| `CLAUDEBOX_IMAGE`          | Override the Docker image used by the wrapper                                              | `psyb0t/claudebox:latest` |
| `CLAUDEBOX_FULL`           | When set, use the toolchain-loaded (`latest-full`) image variant. Default is `latest` (minimal). Setting it at install time bakes the choice into the installed wrapper, so the full variant sticks for every run without re-exporting the var; setting it at runtime overrides the baked default per-run. Pre-v2 `CLAUDEBOX_MINIMAL=1` is now a no-op. | _(none)_ |
| `CLAUDEBOX_CONTAINER_NAME` | Override the per-workspace container name                                                  | derived from `$PWD`       |
| `CLAUDEBOX_MAX_MEM`        | Override the per-container memory limit (e.g. `16g`, `4g`)                                  | `10g`                     |
| `CLAUDEBOX_ENV_*`          | Forward env vars into the container (prefix stripped: `CLAUDEBOX_ENV_FOO=bar` → `FOO=bar`) | _(none)_                  |
| `CLAUDEBOX_MOUNT_*`        | Mount extra host directories into the container                                            | _(none)_                  |
| `AICODEBOX_ENV_*`          | Forward a shared environment variable into the launched container, with the prefix stripped | _(none)_                  |
| `AICODEBOX_MOUNT_*`        | Mount a shared host directory into the launched container                                  | _(none)_                  |

Auth and in-container settings go through `CLAUDEBOX_ENV_*`:

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
CLAUDEBOX_ENV_GITHUB_TOKEN=xxx CLAUDEBOX_ENV_MY_VAR=hello claudebox "do stuff"
```

## Extra volume mounts

The `CLAUDEBOX_MOUNT_` prefix mounts additional host directories into the container:

```bash
CLAUDEBOX_MOUNT_DATA=/data claudebox "process the data"                    # same path inside container
CLAUDEBOX_MOUNT_1=/opt/configs CLAUDEBOX_MOUNT_2=/var/logs claudebox "go"  # mount multiple directories
CLAUDEBOX_MOUNT_STUFF=/host/path:/container/path claudebox "do stuff"      # explicit source:dest mapping
CLAUDEBOX_MOUNT_RO=/data:/data:ro claudebox "read the data"                # read-only mount
```

If the value contains `:`, it is passed directly as Docker `-v` syntax. Otherwise, the same path is used on both host and container sides.

## Sibling boxes

Install `claudebox`, `codexbox`, and `pibox` in the same command directory,
normally `/usr/local/bin`, to make the sibling commands available inside a
box. The parent wrapper mounts only those wrapper files read-only. A sibling
wrapper then uses the host Docker daemon and its recorded host paths to mount
its own data directory. `AICODEBOX_HOST_*` is this internal, versioned launch
context. Leave it unset for an ordinary host launch.
