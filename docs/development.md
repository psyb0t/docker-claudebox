---
title: "Development"
description: "Build claudebox from source, run its lint, credential-free and end-to-end tests with Make and Docker, build these docs, and what the CI pipeline runs."
---

# Development

Docker, Make and Git are enough on the host. Lint, the CI tests and the docs build run in containers.

```bash
git clone https://github.com/psyb0t/docker-claudebox.git
cd docker-claudebox
make help
```

The [`AGENTS.md`](https://github.com/psyb0t/docker-claudebox/blob/master/AGENTS.md) file maps the repository, and the rules in [`.agents/rules/`](https://github.com/psyb0t/docker-claudebox/tree/master/.agents/rules) hold the conventions for each kind of change.

## Building the image

```bash
make build        # psyb0t/claudebox:latest and :v<version>
make build-full   # psyb0t/claudebox:latest-full and :v<version>-full
make build-all    # both
```

Both pull their aicodebox base first. To build on a base you built yourself, name it and skip the pull:

```bash
make build \
  BASE_IMAGE=aicodebox-base:local \
  SKIP_BASE_PULL=1
```

`FULL_BASE_IMAGE` does the same for `build-full`, and `CLAUDE_VERSION` changes the Claude Code version the image pins. The version tag comes from `version` in [`claudebox/pyproject.toml`](https://github.com/psyb0t/docker-claudebox/blob/master/claudebox/pyproject.toml).

## Lint

```bash
make lint     # shellcheck, shfmt, ruff and pyright
make format   # rewrite shell and Python sources in place
```

`make lint` checks every tracked `.sh` file with shellcheck at warning level and with `shfmt -i 4 -ci`, then runs `ruff check`, `ruff format --check` and `pyright` on the `claudebox/` package. The Python tools run in a development image built from [`Dockerfile.dev`](https://github.com/psyb0t/docker-claudebox/blob/master/Dockerfile.dev) on the same aicodebox base the published image uses, so the adapter is checked against the real `aicodebox` package.

## Tests

| Command | Needs | Covers |
| --- | --- | --- |
| `make test-ci` | Docker | Everything CI runs. No credentials, no image build. |
| `make test-unit` | [uv](https://docs.astral.sh/uv/) and a `docker-aicodebox` checkout next to this one | The adapter unit tests, outside a container |
| `make test` | uv, Docker | `test-unit`, the native output contract, and the first-start install output |
| `make test-smoke`, `make test-persist` | Docker | Build the minimal image, then boot it |
| `./test.sh [test_name ...]` | Docker, `tests/.env` | The end-to-end suites against real Claude Code |

`make test-ci` runs, each in the development image:

- the adapter unit tests in [`claudebox/tests/`](https://github.com/psyb0t/docker-claudebox/tree/master/claudebox/tests);
- [`tests/programmatic/check-contract.sh`](https://github.com/psyb0t/docker-claudebox/blob/master/tests/programmatic/check-contract.sh), which feeds recorded native output through the wrapper and checks it comes out byte for byte;
- the wrapper and launcher tests `test_image_select.sh`, `test_agent_launcher.sh`, `test_managed_nested.sh`, `test_cron_shortcut.sh` and `programmatic/check-prog-reuse.sh`, which put a fake `docker` or `claude` on `PATH`;
- with the host Docker socket, `check-install-output.sh`, `test_entrypoint_aliases.sh` and `test_entrypoint_identity.sh`, which run the entrypoint in throwaway containers to check the first-start install, the variable aliases, and the Git identity.

The end-to-end suites spend real Claude usage. Put a token in `tests/.env`, using [`tests/.env.example`](https://github.com/psyb0t/docker-claudebox/blob/master/tests/.env.example) as the template, and run `./test.sh --help` for the list of suites.

## Documentation

This site is built from [`docs/`](https://github.com/psyb0t/docker-claudebox/tree/master/docs) with Docusaurus. The configuration, sidebar order and `llms.txt` live in [`website/`](https://github.com/psyb0t/docker-claudebox/tree/master/website), and [`docs.yml`](https://github.com/psyb0t/docker-claudebox/blob/master/.github/workflows/docs.yml) publishes it to GitHub Pages.

```bash
make docs        # build into website/build in a pinned Node container and check every link
make docs-lock   # refresh website/pnpm-lock.yaml after a dependency change
```

Every page needs front matter with a unique `title` and a `description` of 50 to 170 characters. Add a new page to `website/sidebars.mjs` and to `website/static/llms.txt`. Link between pages with the relative `.md` path. Link a file outside `docs/` with its full GitHub URL, because a relative link to it breaks on the site.

## CI

[`.github/workflows/pipeline.yml`](https://github.com/psyb0t/docker-claudebox/blob/master/.github/workflows/pipeline.yml) runs on every push:

- **Any branch:** the `code` job runs `make lint` and `make test-ci`.
- **`master`:** when `code` passes, both variants are built for `linux/amd64` and `linux/arm64`, scanned, and pushed as `:latest`, `:latest-full` and the `:sha-<commit>` tags, and the badges are refreshed.
- **A `v*` tag:** no rebuild. The pipeline waits for that commit's `master` run to succeed, promotes the same image digests to the release tags, creates the GitHub release, refreshes the badges, publishes the skill and the OpenClaw plugin to ClawHub, and updates the MCP registry entry from [`server.json`](https://github.com/psyb0t/docker-claudebox/blob/master/server.json).

## Versions

```bash
make version            # print the current tag
make version V=X.Y.Z    # set the version everywhere it is stored
```

`make version V=X.Y.Z` updates `claudebox/pyproject.toml`, the Codex plugin manifest, and the release ref `install.sh` downloads the wrapper from. It does not commit or tag.
