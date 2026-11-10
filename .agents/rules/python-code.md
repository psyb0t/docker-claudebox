# Python code

Prefix: PY. Applies to `claudebox/claudebox/` and `claudebox/tests/`.

- **PY1:** `make lint` must pass: `ruff check`, `ruff format --check` and `pyright`, with the settings in `claudebox/pyproject.toml` (line length 100, rule sets `E F W I B UP SIM C4 ARG`, target Python 3.12). `make format` applies `ruff format`.
- **PY2:** The package has no runtime dependencies (`dependencies = []`). The Dockerfiles install it with `uv pip install --no-deps` on top of the base's system Python, so anything it imports must already be in the aicodebox base. Import from `aicodebox` only, never from a new third-party package.
- **PY3:** Dev tools are pinned exactly in `[dependency-groups] dev` and again in `Dockerfile.dev`. Change both together, then `make pkg-lock`.
- **PY4:** Log through the module `logger` with a fixed message and the variable parts in `extra={...}`, as `adapter.py` does. Never log a prompt, a system prompt or a credential in full; use `_truncate` for samples of untrusted output.
- **PY5:** Validate caller input before it reaches the `claude` command line. `_effort_flag_value` raises `ValueError` for an unknown level, and `validate` calls it, so a bad value fails the request instead of reaching the CLI.
