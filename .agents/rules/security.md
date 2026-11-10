# Security

Prefix: SEC. The image runs an agent with shell access, so these hold for every change.

- **SEC1:** Do not claim isolation the code does not give. The standard wrapper uses host networking, mounts the Docker socket, runs with passwordless sudo and bypasses permission prompts. Docs and the skill say so, and no text calls the container a sandbox.
- **SEC3:** The API token and the MCP token are separate (`CLAUDEBOX_API_MODE_TOKEN`, `CLAUDEBOX_MCP_MODE_TOKEN`) and an unset token means no authentication. Every page that starts a server says this.
- **SEC4:** The wrapper writes credentials to disk only in the `0600` per-container auth files in the state directory, and trims whitespace first.
- **SEC5:** Examples use the placeholder shapes in `.gitleaks.toml` (`your-mcp-token`, `$TOKEN`, ...). Do not widen that allowlist by path or rule.
- **SEC6:** The GitHub Action keeps its trust-boundary comment in `action.yml` true: read-only context, one writable output directory, empty job-local state and SSH directories, `SSH_AUTH_SOCK` unset, credentials masked.
