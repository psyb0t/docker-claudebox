# Third-Party Software

claudebox's own code (this repo, minus the exceptions below) is
[WTFPL](LICENSE)-licensed. The **published Docker images**
(`psyb0t/claudebox:latest`, `psyb0t/claudebox:latest-full`), however, install
third-party tools at build time that ship under their own licenses. This file
lists everything the published images redistribute — not dev-only
dependencies, not things the end user downloads themselves after the box is
running.

| Component | Kind | License (SPDX) | Source | Where it lives | Note |
|---|---|---|---|---|---|
| [`@anthropic-ai/claude-code`](https://www.npmjs.com/package/@anthropic-ai/claude-code) | first-run install (NOT in the image) | **Proprietary** — Anthropic Commercial Terms | https://www.anthropic.com/legal | installed at container startup by `claudebox-entrypoint.sh` | **Not baked into or redistributed by the published image.** Anthropic's CLI is proprietary ("all rights reserved") with no redistribution grant, so the image ships only the pinned version number (`CLAUDEBOX_CLAUDE_VERSION`) and the entrypoint runs `npm install -g @anthropic-ai/claude-code@<version>` from npm on first run — i.e. each user's own container fetches it directly from Anthropic/npm. The image itself carries none of Anthropic's software. |
| [HashiCorp Terraform](https://www.terraform.io/) | apt package | `BUSL-1.1` (source-available, non-compete) | https://github.com/hashicorp/terraform | `Dockerfile.full` only | `latest-full` image only; not in `latest`. |
| [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) | npm dependency of the bundled plugin | `MIT` | https://www.npmjs.com/package/mcp-remote | `.agents/plugins/claudebox/package.json` | Dependency of the `@psyb0t/claudebox` MIT plugin, not baked into the Docker image. |
| [GitHub CLI (`gh`)](https://cli.github.com/) | apt package | `MIT` | https://github.com/cli/cli | `Dockerfile.full` only | `latest-full` image only; not in `latest`. |
| [`kubectl`](https://kubernetes.io/docs/reference/kubectl/) | apt package | `Apache-2.0` | https://github.com/kubernetes/kubectl | `Dockerfile.full` only | `latest-full` image only; not in `latest`. License text: [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt). |
| [Helm](https://helm.sh/) | install script | `Apache-2.0` | https://github.com/helm/helm | `Dockerfile.full` only | `latest-full` image only; not in `latest`. License text: [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt). |

No license text is bundled for the proprietary Claude Code CLI — see
Anthropic's own terms at the link above.

See also: [`.agents/plugins/claudebox/LICENSE`](.agents/plugins/claudebox/LICENSE)
for the full MIT text covering the `@psyb0t/claudebox` plugin itself (which
stays MIT, as-is).
