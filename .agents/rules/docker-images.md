# Docker images

Prefix: IMG. Applies to `Dockerfile`, `Dockerfile.full`, `Dockerfile.dev`, `claudebox-entrypoint.sh` and `claudebox/init.d/`.

- **IMG1:** `Dockerfile` and `Dockerfile.full` add the same Claude layer to different aicodebox bases. A change to one is made to the other in the same change, except the base image and `CLAUDEBOX_IMAGE_VARIANT`.
- **IMG2:** Generic tooling belongs in aicodebox, not here. These images add only the adapter, the init scripts, the launcher, the entrypoint and the Claude-specific environment.
- **IMG3:** Never bake the Claude Code CLI into an image. It is proprietary with no redistribution grant. Pin the version in `ARG CLAUDE_VERSION` in both Dockerfiles and `CLAUDE_VERSION` in the `Makefile`, all three equal; the entrypoint installs it on first start.
- **IMG4:** The base image defaults pin an aicodebox release by tag and digest (`psyb0t/aicodebox:vX.Y.Z@sha256:...`, `-full` for the full image). `ARG BASE_IMAGE` in both Dockerfiles and `Dockerfile.dev`, `BASE_IMAGE` and `FULL_BASE_IMAGE` in the `Makefile`, and the test fallbacks move together.
- **IMG5:** A new `AICODEBOX_*` setting that users should reach as `CLAUDEBOX_*` is added to `_CLAUDEBOX_ALIASES` in `claudebox-entrypoint.sh`, to the expected list in `tests/test_entrypoint_aliases.sh`, and to `docs/environment-variables.md`. An existing `AICODEBOX_*` value must keep winning.
- **IMG6:** Legacy names in `_LEGACY_MODE_MAP` are never removed in a minor release. `docs/upgrading.md` lists them.
- **IMG7:** Init scripts run once per container as `aicode`, in filename order, and a failure does not stop startup. Keep them idempotent and keep their two-digit prefix order.
- **IMG8:** `Dockerfile.dev` is only for lint and tests. It is never added to the pipeline's `build_targets`.
- **IMG9:** `.dockerignore` keeps documentation, agent and release scratch files, and secrets out of the build context. A new top-level file the image does not copy goes there.
