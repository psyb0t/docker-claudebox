# Installation and wrapper

[Back to README](../README.md)

## Install

The installer needs Bash, a running Docker daemon, curl, `ssh-keygen`, and sudo access to the installation directory. It creates `~/.claude`, creates or reuses `~/.ssh/claudebox/id_ed25519`, pulls an image, and installs a wrapper in `/usr/local/bin`.

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash
```

Select the full variant before running the installer:

```bash
export CLAUDEBOX_FULL=1
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash
```

Export variables before the pipeline. `VAR=value curl ... | bash` sets the variable for curl, not Bash.

To use a different command name:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash -s -- claude
```

`CLAUDEBOX_BIN_NAME` and `CLAUDEBOX_INSTALL_DIR` are the equivalent installer settings. `AICODEBOX_MANAGED_INSTALL=1` keeps an existing SSH key without asking whether to replace it.

### Review before running

Download the repository archive or use a local checkout, inspect `install.sh` and `wrapper.sh`, then run `bash install.sh` from that checkout. The installer uses its adjacent wrapper when present.

When downloaded through the one-line pipeline, the installer instead downloads the wrapper from `CLAUDEBOX_INSTALL_REF`, falling back to the embedded `CLAUDEBOX_RELEASE_REF`. `make version V=X.Y.Z` keeps that ref aligned with the package and plugin metadata; it does not commit or tag. Updating the image does not update an installed wrapper. To explicitly request the current default-branch wrapper:

```bash
export CLAUDEBOX_INSTALL_REF=master
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-claudebox/master/install.sh | bash
```

Use a reviewed tag or commit ref instead of `master` when you need a fixed wrapper version. This selects the wrapper source, not the image version.

## Image selection

The default is `psyb0t/claudebox:latest`, the minimal image. Installing with `CLAUDEBOX_FULL=1` stores the full choice in the wrapper. `CLAUDEBOX_IMAGE` overrides the image at launch:

```bash
CLAUDEBOX_IMAGE=psyb0t/claudebox:latest-full claudebox
```

`CLAUDEBOX_FULL=0` selects minimal and `CLAUDEBOX_FULL=1` selects full. Other nonempty values fail. With no runtime override, the wrapper keeps its installed variant. `CLAUDEBOX_IMAGE` overrides the selected variant. The legacy `CLAUDEBOX_MINIMAL` setting does not select another image.

Both variants install the pinned Claude Code version from npm on first container start. Warm starts reuse that installation. `CLAUDEBOX_CLAUDE_VERSION` selects the version installed when the CLI is absent; it does not replace an existing installation. Through the wrapper, forward it as `CLAUDEBOX_ENV_CLAUDEBOX_CLAUDE_VERSION`.

Minimal and full inherit their runtime from aicodebox. Full adds the shared development tools. Check the base's [full-image definition](https://github.com/psyb0t/docker-aicodebox/blob/main/Dockerfile.full), [Node packages](https://github.com/psyb0t/docker-aicodebox/blob/main/full-node/package.json), [Python requirements](https://github.com/psyb0t/docker-aicodebox/blob/main/full-python/requirements.txt), and [dependency audit](https://github.com/psyb0t/docker-aicodebox/blob/main/docs/dependency-audit.md) rather than assuming every tool is installed or advisory-free.

## Authentication and state

The standard wrapper mounts:

| Host path | Container path | Purpose |
| --- | --- | --- |
| Current directory | Same absolute path | Workspace |
| `~/.claude` | `/home/aicode/.claude` | Claude config, credentials, sessions, and shared mode state |
| `~/.ssh/claudebox` | `/home/aicode/.ssh` | SSH keys and config |

The entrypoint links Claude state with `/home/aicode/.aicodebox` for the shared modes. `CLAUDE_CONFIG_DIR` points to `/home/aicode/.claude`, so Claude's configuration file is `~/.claude/.claude.json` on the host under the default mount, not the host's separate `~/.claude.json`.

Authenticate interactively, or export `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`. The `CLAUDEBOX_ENV_ANTHROPIC_API_KEY` and `CLAUDEBOX_ENV_CLAUDE_CODE_OAUTH_TOKEN` forms work too. `claudebox setup-token` runs the native OAuth token flow. Do not assume generating a token exports it for later shell commands; store and supply the resulting token securely.

Add the SSH public key to your Git host only if Claude needs access there. The wrapper does not forward an SSH agent automatically. To opt in:

```bash
CLAUDEBOX_MOUNT_SSH="$SSH_AUTH_SOCK:/ssh-agent:ro" CLAUDEBOX_ENV_SSH_AUTH_SOCK=/ssh-agent claudebox
```

Every key available through that agent becomes usable inside the container.

## Git identity

Set `CLAUDEBOX_GIT_NAME` and `CLAUDEBOX_GIT_EMAIL` on the host to configure Git for the runtime user before init hooks run. In direct container deployments, use the same names or `AICODEBOX_GIT_NAME` and `AICODEBOX_GIT_EMAIL`. A nonempty shared value wins over the Claude-specific alias. Empty values preserve existing Git configuration. Multiline values stop startup.

## Container lifecycle

For a normal host launch, the wrapper keeps an interactive `claude-<path>` container and a separate `claude-<path>_prog` programmatic container. They share mounted files and Claude state. The cron shortcut creates `claude-<path>_cron`. Nested one-shot launches use temporary containers instead.

`claudebox stop` stops the interactive container for the current workspace. It does not delete containers or pull a new image. `claudebox clear-session` deletes that workspace's saved session directory but keeps authentication and other configuration.

Image tags, mounts, and environment settings are set when the container is created. Pulling a newer image or changing those settings does not update a reused container. Stop the exact affected container, inspect it, and remove only that container if you want the wrapper to create its replacement. Back up any files stored only in its writable container layer first. Mounted files remain on the host.

Interactive launches resume by default. `--no-continue` starts fresh. Programmatic mode also supports `--resume <session_id>`. `--update` is an opt-in CLI update path for the interactive launch; it is not a wrapper or Docker image update.

The base remaps the `aicode` user's UID/GID to the workspace owner at startup. Image init scripts seed `CLAUDE.md` only if the workspace does not already contain one. The file is a template, not a live inventory of every installed package.

## Host access and server deployment

The standard wrapper uses host networking and mounts `/var/run/docker.sock`. Claude runs with passwordless sudo and bypassed permission prompts. This is access to the host daemon, not a separate Docker-in-Docker daemon. Mounting a directory read-only does not prevent an agent with Docker access from reaching the host through another container.

Use the [API](modes/api.md), [MCP](modes/mcp.md), [Telegram](modes/telegram.md), and [cron](modes/cron.md) Compose examples for servers that do not need host Docker access. Bind ports to loopback, configure authentication, and set resource limits. An API bearer token protects the API, not MCP. Give Telegram an explicit chat allowlist.

The API confines file-tool paths and prevents simultaneous runs in the same workspace. The Claude subprocess still has the container's filesystem and process permissions. Do not use workspace subpaths as a security boundary between untrusted tenants.

First-start CLI installation and UID/GID setup need a writable root filesystem and startup privileges. Do not add `read_only: true` or drop all capabilities without testing that exact launch path.

## Sibling boxes

Install `claudebox`, `codexbox`, and `pibox` in the same command directory. The parent mounts sibling wrapper files read-only and records the host paths needed to launch them. Each sibling mounts its own host state directory.

Run the installed sibling command from the requested workspace. Do not copy wrappers into the workspace, manually mount another agent's home, or set `AICODEBOX_HOST_*` yourself. Those variables are the wrapper's internal nested-launch context.

See [Environment variables](environment-variables.md) for extra mounts, arbitrary forwarded variables, and overrides.
