# Changelog

All notable changes to **claudebox** (formerly `docker-claude-code`).

Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [v2.0.5] — 2026-07-05 — Wrapper honors CLAUDEBOX_FULL so the pulled image is the one that runs

`CLAUDEBOX_FULL=1` was honored by `install.sh` (which pulls `psyb0t/claudebox:latest-full`) but IGNORED by the wrapper, which always launched `psyb0t/claudebox:latest` (the minimal image). So `CLAUDEBOX_FULL=1 claudebox` ran a different image than was pulled — commonly a stale, pre-`CLAUDE_CONFIG_DIR` `latest` — which wrote Claude Code's config to an ephemeral path in the container and re-prompted for theme + login on every run. The full image you pulled was never actually used.

### Fixed

- **`wrapper.sh`**: honors `CLAUDEBOX_FULL` (and the `CLAUDE_FULL` alias) → launches `latest-full`, mirroring `install.sh`'s tag resolution so the wrapper runs the image that was pulled. `CLAUDEBOX_MINIMAL` is now a no-op (resolves to `latest`), matching `install.sh` and the README (in v2, `latest` IS the minimal image); the old `latest-minimal` branch resolved a tag that isn't published. `CLAUDEBOX_IMAGE` still overrides everything.
- **`wrapper.sh`**: quoted `$CLAUDE_IMAGE` at every `docker run` site and replaced a `sed` pipeline with parameter expansion (shellcheck clean).

### Tests

- **`tests/test_image_select.sh`**: hermetic (fake `docker`, no image build) — asserts the wrapper resolves the correct tag for each flag AND that `install.sh`'s pulled tag equals the wrapper's launched tag (the pull/run consistency the bug violated).
- **`tests/test_persist.sh`**: boots the image through the real entrypoint and asserts Claude Code reads/writes `.claude.json` on the bind-mounted `~/.claude` (so theme/login/onboarding persist) instead of the ephemeral `$HOME/.claude.json`.
- **`Makefile`**: `make test-persist` and `make test-image-select` targets.

## [v2.0.4] — 2026-07-04 — Build latest-full after the base so it inherits base env

The v2.0.3 `CLAUDE_CONFIG_DIR` fix landed only in `Dockerfile` (the `:latest` base). `Dockerfile.full` does `FROM psyb0t/claudebox:latest` and inherits that env — but CI built both images in parallel from the same commit, so `latest-full` layered on the *previously published* base (v2.0.0) and never picked up the fix. Running `claudebox` with `CLAUDEBOX_FULL=1` therefore still re-prompted for theme + login even after v2.0.3 shipped.

### Fixed

- **`.github/workflows/pipeline.yml`**: marked the `Dockerfile.full` build target `"stage": 1` so it builds only after the stage-0 base (`Dockerfile` → `:latest`) has built **and pushed**. `latest-full` now inherits the current base — including `CLAUDE_CONFIG_DIR` and any future base env/config changes — instead of the last published one. Relies on the ordered-build (`stage`) support in the reusable docker-image workflow.

## [v2.0.3] — 2026-07-04 — Restore CLAUDE_CONFIG_DIR so login + theme persist

Regression from v2.0.0. Running `claudebox` in a fresh directory prompted for theme selection and login every time, instead of opening already logged-in. Claude Code keeps its onboarding state — the selected theme, the onboarding-complete flag, and the `oauthAccount` — in `.claude.json`. Pre-v2 the entrypoint set `CLAUDE_CONFIG_DIR=/home/claude/.claude` (the bind-mounted config dir) so `.claude.json` lived on the mount and persisted across container recreates. The v2.0.0 aicodebox rebase moved the interactive init into `claudebox/init.d/10-claude-json-patch.sh`, which hardcoded `${HOME}/.claude.json` (an unmounted path), and nothing re-set `CLAUDE_CONFIG_DIR`. So every run wrote config to a throwaway path and re-onboarded. `CLAUDE_CONFIG_DIR` is Claude-Code-specific, so only claudebox can set it — the aicodebox base is agent-agnostic.

### Fixed

- **`Dockerfile`**: added `CLAUDE_CONFIG_DIR=/home/aicode/.claude` to the `ENV` block. Claude Code now reads/writes `.claude.json` + credentials inside the bind-mounted `~/.claude` (the wrapper's `-v "$CLAUDE_DIR:/home/aicode/.claude"`), so theme, onboarding, and account persist and a fresh container opens logged-in.
- **`claudebox/init.d/10-claude-json-patch.sh`**: patch target is now `"${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"` (falls back to `$HOME` when the var is unset), matching where Claude Code actually reads config.
- **`claudebox/claudebox/adapter.py`**: `ClaudecodeAdapter.auth_paths()` now resolves `.claude.json` under `CLAUDE_CONFIG_DIR` when set (falling back to `$HOME/.claude.json`), so the headless modes' auth-readiness check points at the file Claude Code actually uses.

### Tests

- `claudebox/tests/test_adapter.py`: added `test_auth_paths_honors_config_dir` covering the `CLAUDE_CONFIG_DIR`-set case; the existing `test_auth_paths_uses_home` now clears `CLAUDE_CONFIG_DIR` to assert the fallback.
- `tests/test_smoke.sh`: Test 4 now reads the patched config from `/home/aicode/.claude/.claude.json` (its new persisted location).

## [v2.0.2] — 2026-07-04 — Fix Dockerfile.full BuildKit gpg failure

The v2.0.1 CI push exposed a BuildKit-only failure: `gpg --dearmor` in the terraform + kubectl keyring steps of `Dockerfile.full` failed with `cannot open '/dev/tty': No such device or address`. gpg tries to open the (non-existent) tty for its unused pinentry prompt when running under BuildKit. Local `docker build` didn't hit this because it was falling back to the classic builder.

### Fixed

- **Dockerfile.full**: added `--batch --no-tty --yes` to both `gpg --dearmor` invocations (terraform + kubectl apt keyrings) so gpg doesn't try to open the tty. Verified with a local `docker build -f Dockerfile.full` — both keyring steps complete cleanly.

## [v2.0.1] — 2026-07-04 — CI fix + doc sync + uv/lint hardening

Follow-up to v2.0.0. Fixes the CI pipeline broken by the two-Dockerfile split, brings every user-facing doc in sync with the v2 env-var / path / variant naming, and formalizes the Python dev toolchain around `uv` + `ruff` + `pyright` with a committed lockfile. Runtime behavior is identical to v2.0.0 — no adapter code change.

### Fixed

- **CI**: `.github/workflows/pipeline.yml` was invoking the reusable docker-image-workflow in `target: full/minimal` mode, expecting the pre-v2 multi-stage single Dockerfile. v2.0.0 split the image into `Dockerfile` (minimal) + `Dockerfile.full` (toolchain). Switched the matrix to `file:` mode — `Dockerfile` → `:latest`, `Dockerfile.full` → `:latest-full`.

### Changed — docs

- Env-var renames throughout the docs: `CLAUDEBOX_MODE_API` → `CLAUDEBOX_API_MODE`, `CLAUDEBOX_MODE_TELEGRAM` → `CLAUDEBOX_TELEGRAM_MODE`, `CLAUDEBOX_MODE_CRON` → `CLAUDEBOX_CRON_MODE`, plus the matching `_TOKEN` / `_PORT` / `_FILE` / `_CONFIG` suffixes. Legacy `CLAUDE_MODE_*` names still work — the entrypoint aliases them forward — but the canonical names in the docs are now the v2 shape.
- Path renames throughout the docs and example YAML comments: `/home/claude/.claude/...` → `/home/aicode/.claude/...` (the entrypoint's compat symlink keeps pre-v2 bind mounts working), `/workspaces` (plural) → `/workspace` (singular).
- Image variant naming section rewritten. `latest` is now the minimal image (was the full image pre-v2); `latest-full` is the toolchain-loaded variant (was `latest` pre-v2). The `CLAUDEBOX_MINIMAL=1` opt-in is now a no-op; opt into the toolchain with `CLAUDEBOX_FULL=1`.
- Permission flag reference updated: `--dangerously-skip-permissions` (v1) → `--permission-mode bypassPermissions` (v2, same effect) in the Gotchas section.
- `CLAUDEBOX_MINIMAL` → `CLAUDEBOX_FULL` in the environment variables table (`docs/environment-variables.md`).

### Changed — Python dev toolchain (uv + ruff + pyright)

- `claudebox/pyproject.toml` — added `[dependency-groups] dev` (PEP 735) declaring `pytest` / `ruff` / `pyright` / `aicodebox` for local dev. `[tool.uv.sources]` points `aicodebox` at the sibling `docker-aicodebox` repo in editable mode so `uv sync --group dev` works without a registry. Docker builds don't touch this group — the image installs the adapter with `--no-deps` against the base's already-present aicodebox.
- Expanded ruff lint rules from the default set to `E / F / W / I / B / UP / SIM / C4 / ARG` (basics + import sort + bugbear + pyupgrade + simplify + comprehension idioms + unused args). All checks pass.
- Added `[tool.pytest.ini_options]` for consistent test discovery + output formatting.
- New `claudebox/uv.lock` committed — every runtime + dev dep pinned by version + hash for reproducibility.

### Changed — shell

- `claudebox-entrypoint.sh` upgraded from `set -e` to `set -euo pipefail` (strict-mode discipline). Every v2-authored shell script (entrypoint + 3 init.d + 2 smoke tests) now passes `shellcheck` clean.

## [v2.0.0] — 2026-07-04 — REBASED ON `psyb0t/aicodebox`

**Full architectural rebase.** The image is now a thin child of `psyb0t/aicodebox` (same pattern as `psyb0t/pibox`). Every mode (API, Telegram, Cron, MCP) is inherited from the base — future base fixes reach claudebox for free.

### Migration for existing users

- **Endpoint shape**: `POST /run/cancel?runId=…` → `DELETE /run/{run_id}`. `GET /health` → `GET /healthz`. Update client scripts.
- **MCP tool rename**: `claude_run` → `run_prompt`. Update MCP client configs.
- **Env vars**: `CLAUDEBOX_MODE_API` → `CLAUDEBOX_API_MODE`, `CLAUDEBOX_MODE_API_TOKEN` → `CLAUDEBOX_API_MODE_TOKEN`, `CLAUDEBOX_MODE_CRON_FILE` → `CLAUDEBOX_CRON_MODE_FILE`, etc. Entrypoint aliases the legacy names forward, so existing configs keep working; the canonical names going forward are the new ones. See `.env.example` for the full list.
- **Paths**: workspace root `/workspaces` (plural) → `/workspace` (singular). Home dir `/home/claude/.claude` → `/home/aicode/.aicodebox`. The entrypoint installs compat symlinks so existing bind mounts still resolve.
- **Init.d dir**: `~/.claude/init.d/*.sh` → `/aicodebox-init.d/*.sh`. Move custom scripts.
- **Cron schedules**: 6-field croniter only. Pre-v2 configs using 5-field entries need `0 ` prepended.
- **Removed**: Telegram `/bash <cmd>` command (reimplement client-side if needed); `--max-budget-usd` support pending an adapter-level knob.
- **Full variant**: `make build-full` now layers on top of the minimal image (was a multi-stage build target).

### Added

- `claudebox/adapter.py` — `ClaudecodeAdapter` implementing the aicodebox `AgentAdapter` contract. Ports the pre-v2 `jsonpipe.py` stream-json reassembly (turns + tool_result truncation @ 2000 chars + sha256) into `parse_output` / `parse_events` / `parse_stream_event`.
- `.always-skills` `SKILL.md` injection every call — the adapter scans `~/.claude/.always-skills` on every invocation and appends every file's contents (with `[Skill file: <path>]` headers) to `--append-system-prompt`. Matches the pre-v2 `entrypoint.sh` behavior.
- `--permission-mode bypassPermissions` in every default argv (modern equivalent of `--dangerously-skip-permissions`). Callers override via `RunRequest.extra_args`.
- Init.d scripts: `10-claude-json-patch.sh` (trust dialog + autoUpdater off), `20-workspace-claude-md.sh` (seed workspace CLAUDE.md from image template), `30-always-skills-seed.sh` (ensure the skills dir + system-hint file exist).
- `claudebox-entrypoint.sh` — aliases `CLAUDEBOX_*` and legacy `CLAUDE_MODE_*` env vars to their `AICODEBOX_*` equivalents, installs compat symlinks, then execs the base entrypoint.
- 29 pytest unit tests for the adapter (`claudebox/tests/test_adapter.py`).
- `tests/test_smoke.sh` — 9 containerized smoke tests using a mock claude binary: /healthz, /openai/v1/models, init.d markers, compat symlinks, env aliasing, `.always-skills` injection, `extra_args`, `--permission-mode` default.
- `.env.example` — canonical `CLAUDEBOX_*` env template.
- `Dockerfile.full` — toolchain layer (Go, kubectl, terraform, helm, pyenv, Node globals, DB clients, editors) FROM the minimal claudebox image.

### Removed

- `api_server.py`, `telegram_bot.py`, `telegram_utils.py`, `cron.py`, `jsonpipe.py`, `entrypoint.sh` — all replaced by aicodebox's mode dispatchers + the adapter.
- Pre-v2 monolithic `Dockerfile` with `AS base` / `AS minimal` / `AS full` stages — split into `Dockerfile` (child of aicodebox) + `Dockerfile.full` (layered variant).

### Retained

- `wrapper.sh` + `install.sh` (host-side CLI + installer) — updated for the new env-var namespace and `/workspace` path. Every wrapper subcommand (`setup-token`, `stop`, `clear-session`, `--update`, `--no-continue`, arg whitelist) still works.

## [v1.14.1] — 2026-07-01

### Changed
- Bump the pinned Claude CLI to `2.1.197` (was `2.1.123`) via the Dockerfile `CLAUDE_VERSION` build arg.
- `.gitignore`: ignore `.telemetry/`.

## [v1.14.0] — 2026-05-08

### Added
- 24 unit tests + 3 integration tests for the OpenAI-compat wrapper.

### Security
- SSRF guard on the OpenAI-compat wrapper.

### Fixed
- `finish_reason` mapping, multi-turn workspace handling, and a `400` response on unsupported request fields in the OpenAI-compat wrapper.

## [v1.13.1] — 2026-05-07

### Fixed
- Installer always pulls, removing the `SKIP_PULL`/`FORCE_PULL` pipeline-scoping footgun.

### Changed
- README/docs use the export-before-pipe pattern so env-var examples actually work.

## [v1.13.0] — 2026-05-02

### Added
- Cron jobs automatically see paths to prior runs (`history_dir` + glob pattern), enabling trend/regression jobs without per-job wiring.

### Changed
- pyright clean over the Python entrypoints.

## [v1.12.7] — 2026-05-01

### Added
- Full end-to-end Telegram test suite via telethon-plus.

### Fixed
- cron+telegram `HOME` propagation (the bot read `/root/.claude/` and missed every cron-reply context).
- Iterative placeholder restore for nested stashes.

## [v1.12.6] — 2026-05-01

### Fixed
- Telegram placeholder leak: NUL-byte delimiters were stripped in transport, leaking `CB0`, `CB1`, … as visible text. Switched to Unicode PUA delimiters.

## [v1.12.5] — 2026-04-30

### Changed
- markdown → Telegram-HTML converter; formatting hint flipped to markdown. (Re-tag of v1.12.4 — the v1.12.4 Docker tag was poisoned by an earlier incomplete commit.)

## [v1.12.4] — 2026-04-30

### Added
- markdown → Telegram-HTML converter + canonical formatting hint.

## [v1.12.3] — 2026-04-30

### Added
- Telegram-aware cron output.

### Fixed
- Raw HTML fallback.

## [v1.12.1] — 2026-04-30

### Fixed
- Permission-error reply in cron+telegram mode (path resolution + `Path.exists()` wrapped in try/except).

## [v1.12.0] — 2026-04-30

### Added
- Cron `effort` field (root-level default + per-job override).

## [v1.11.0] — 2026-04-30

### Added
- **Telegram per-chat overrides** stored in `~/.claude/telegram_overrides.json`, persisting across bot restarts and trumping the YAML config:
  - `/model` — inline keyboard or `/model <name>`; choices: `haiku`, `sonnet`, `opus`, `opusplan`, `reset`.
  - `/effort` — same UX; choices: `low`, `medium`, `high`, `xhigh`, `max`, `reset` (verified against the official Claude CLI docs).
  - `/system_prompt [text|reset]` — show/set/clear system-prompt override per chat.
  - `/append_system_prompt [text|reset]` — same for the appended system prompt.
- `opusplan` model alias surfaced everywhere: telegram bot, OpenAI `/openai/v1/models`, MCP tool docstring, docs.
- `tests/test_cron_telegram.sh` — unit + integration tests for the cron/telegram bridge: round-trip message tracking, prune to 200 entries, no-`--continue` on cron replies, `CRON_SYSTEM_HINT` content, combined-entrypoint smoke test.
- `run-e2e-cron-telegram.sh` — end-to-end script (sources `tests/.env` for credentials) for the cron+telegram reply-context flow.

### Changed
- `get_chat_config()` merges in-memory + on-disk overrides on top of YAML defaults.
- `_apply_choice` / `_send_choice_keyboard` / `_BUTTON_HANDLERS` shared plumbing for keyboard-driven overrides.

### Security
- `run-e2e-cron-telegram.sh` now sources `tests/.env` instead of carrying hardcoded OAuth/bot tokens. (A previously-committed token in `v1.10.0`'s `run-test.sh` was auto-revoked by Anthropic's secret scanning; new token issued and stored only in gitignored `tests/.env`.)

## [v1.10.0] — 2026-04-29

### Added
- **Combined cron + telegram mode**: when both `CLAUDEBOX_MODE_CRON=1` and `CLAUDEBOX_MODE_TELEGRAM=1` are set, the entrypoint runs the cron scheduler in the background and the telegram bot in the foreground (trap kills cron when the bot exits).
- Cron yaml supports `telegram_chat_id` (root-level default + per-job override) — finished jobs post their result to Telegram.
- **Cron-reply context injection**: when a user replies to a cron notification in Telegram, the bot looks up the original job (name, fired_at, instruction, result) in `~/.claude/cron/telegram_messages.json` and prepends it to the prompt. Cron replies always run in a fresh session (no `--continue`); regular messages keep `--continue`.
- Chat-wide cron awareness: the most recent 10 cron runs are injected into every prompt's `--append-system-prompt` so Claude can answer questions about them without an explicit reply.
- `telegram_utils.py` shared module (`BOT_TOKEN`, `make_bot()`, `send_long()`); `send_long()` now returns the list of sent `Message` objects so the caller can capture `message_id`.
- `wrapper.sh` gained a named `_cron` container with start/stop/restart parity to `_prog`, plus an auth file.

## [v1.9.0] — 2026-04-29

### Added
- Cron jobs support `system_prompt` / `append_system_prompt` (root-level + per-job override).
- Template variables expanded at fire time: `{system_datetime}`, `{job_name}`.

## [v1.8.0] — 2026-04-29

### Added
- `claudebox mcp ...` wrapper passthrough (`list`, `add`, `remove`, …) so MCP server management works the same as bare `claude mcp`.
- Documentation covering MCP server scopes (project `.mcp.json`, user, local) with CLI examples.

## [v1.7.0] — 2026-04-29

### Added
- **Cron mode** (`CLAUDEBOX_MODE_CRON=1`): yaml-scheduled Claude jobs with sub-minute resolution, per-job history under `~/.claude/cron/history/<workspace-slug>/<ts>-<job>/`, overlap protection, and foreground logging.

### Changed
- Environment variable namespace renamed `CLAUDE_*` → `CLAUDEBOX_*`. Legacy `CLAUDE_*` names are still accepted as fallbacks for backwards compatibility.

## [v1.6.0] — 2026-04-29

### Added
- Proper standalone installer (`install.sh`) that drops in a working setup with one command.

## [v1.5.0] — 2026-04-29

### Fixed
- Misc release-blocking bugs.

## [v1.4.1] — 2026-04-29

### Fixed
- Installer script regressions; bumped pinned Claude CLI version.

## [v1.4.0] — 2026-04-16

### Changed
- Base image upgraded to **Ubuntu 24.04** (CVE reduction).
- Adopted DEB822 apt sources; dropped `apt-transport-https` (no longer needed).
- `pip3 --break-system-packages --ignore-installed` to work around PEP 668 + PyJWT conflict.
- `userdel ubuntu` before `useradd claude` to free UID 1000.
- `exa` → `eza` (exa is unmaintained); `mysql-client` → `default-mysql-client`.
- Dropped `python3-venv`.

## [v1.3.0] — 2026-04-16

### Added
- **Async run mode** in API: `POST /run` with `async: true`, `GET /run/result` for polling. Run IDs included on every response. Read-once result cache with 6-hour TTL. Cancel by `runId`. `/status` now lists active runs.

### Changed
- All API responses include `workspace`.
- Switched build apt mirror to Cloudflare for faster Docker builds.
- README updated with full response schemas.

### Fixed
- `asyncio.Lock` around run state to eliminate races.

## [v1.2.0] — 2026-04-11

### Security
- Telegram **path traversal** fix on file operations.
- Auth file mode hardened to `chmod 600`.
- Entrypoint **command-injection** fix via `printf %q` quoting.
- `jq` failure protection.
- Port number validation.
- Install script fail-safe.

### Changed
- `/status` response normalized to camelCase.
- Test isolation via `mktemp`.

## [v1.1.0] — 2026-04-11

### Added
- `make test` target.
- `.dockerignore` (faster, smaller build context).
- Test for entrypoint always-skills wiring.

### Changed
- Tests refactored to a table-driven layout with workspace-relative test dirs.
- README revamp.

## [v1.0.0] — 2026-04-11

### BREAKING
Project renamed from `docker-claude-code` → **`claudebox`**:
- Docker image: `psyb0t/docker-claude-code` → `psyb0t/claudebox`.
- Binary: `claude-code` → `claudebox`.
- SSH dir: `~/.ssh/claude-code` → `~/.ssh/claudebox`.
- GitHub repo: `psyb0t/docker-claudebox`.

## [v0.39.0] — 2026-04-11

### Added
- **Always-skills**: scan `~/.claude/.always-skills` for `SKILL.md` files and inject them (with file-path prefix) into every Claude invocation across interactive, programmatic, API, and OpenAI modes.

## [v0.38.0] — 2026-04-10

### Added
- Structured JSON logging (`ts`, `level`, `logger`, `func`, `line`, `file`, `msg`) across auth, `/run`, OpenAI, MCP, and image handling. `DEBUG=1` enables debug level.

## [v0.37.0] — 2026-04-10

### Added
- **OpenAI multimodal**: base64 + URL images saved to the workspace and forwarded to Claude.
- Real usage-token reporting on OpenAI responses.
- Multi-turn via conversation JSON file.
- `X-Claude-Append-System-Prompt` request header.

### Changed
- Extra/unknown OpenAI fields silently ignored.

## [v0.36.0] — 2026-04-10

### Changed
- All 24 tests in `ALL_TESTS`; every assertion now checks the response body, not just status codes.

## [v0.35.0] — 2026-04-10

### Fixed
- `streamable_http_app` for MCP.
- MCP lifespan registered via FastAPI.
- `stream-json` assistant-event parsing.
- `--continue` flag logic.
- MCP tests with proper session init.

## [v0.34.0] — 2026-04-10

### Changed
- OpenAI `/v1/models` returns bare aliases (`haiku`, `sonnet`, `opus`).
- Provider prefix (`openai/`, `claudebox/`) stripped from inbound model names.
- Tests use `$TEST_MODEL` instead of hardcoded values.

## [v0.33.0] — 2026-04-10

### Added
- **OpenAI-compatible adapter** at `/openai/v1` (streaming, custom headers, `reasoning_effort`).
- **MCP server** at `/mcp` exposing `claude_run`, file operations, and auth tools.
- Shared `_run_claude_text` helper.

## [v0.32.0] — 2026-04-07

### Changed
- camelCase response normalization across the board: `jsonpipe.py` normalizes `json` / `stream-json` / `json-verbose`, wrapper pipes all formats. Tests assert recursively against snake_case.

## [v0.31.0] — 2026-04-07

### Fixed
- `asyncio.StreamReader` 64KB-line crash in API.
- Truncate `json-verbose` tool results > 2K with sha256 hash.

## [v0.30.0 – v0.29.0] — 2026-04-07

### Added
- `outputFormat: json-verbose` — assembles `stream-json` into a single JSON document with a `turns` array showing all tool calls.

## [v0.28.0] — 2026-04-03

### Added
- `clear-session` wrapper command.

### Fixed
- `--no-continue` without prompt.

### Changed
- README env-var section restructured.

## [v0.27.0] — 2026-04-03

### Changed
- camelCase normalization rolled out further.

## [v0.26.0] — 2026-04-03

### Removed
- Claude Code Router (CCR) integration.

### Changed
- Bumped Claude CLI to 2.1.90.

## [v0.25.0] — 2026-04-03

### Changed
- API moved to camelCase.
- Auto-updates now opt-in.
- Bumped CLI to 2.1.89.

## [v0.24.0] — 2026-04-01

### Added
- `claudebox stop` wrapper command.

## [v0.23.1 – v0.23.0] — 2026-03-31

### Added
- Wrapper passthrough for utility commands: `--version`, `doctor`, `auth`.

### Changed
- Go bumped 1.25.5 → 1.26.1.

## [v0.22.0] — 2026-03-31

### Added
- System hint appended to all modes — informs Claude about container info, image variant, sudo access, bin path, and host-path mapping.

## [v0.21.x] — 2026-03-30/31

### Added
- `CLAUDE.md` template seeded into all workspaces (telegram, API, interactive).
- Makefile build targets.

### Fixed
- Telegram cancel-retry bug; better logging.
- API kills the Claude process on client disconnect (opt out via `fire_and_forget`).

## [v0.20.x] — 2026-03-30

### Added
- **Telegram bot mode** (`CLAUDE_MODE_TELEGRAM=1`): per-chat workspaces, file/photo/video/voice handling, command menu, HTML formatting with plain-text fallback.

### Fixed
- Empty-file crash; httpx polling-spam silenced; proper logging.
- Filters, media handlers, command menu wiring.

## [v0.19.0] — 2026-03-30

### Added
- `--no-continue` and `--resume` wrapper flags.

### Changed
- Bumped Claude CLI to 2.1.87.

## [v0.18.x] — 2026-03-28

### Changed
- Hardcoded `/workspaces` as the API root; removed `CLAUDE_MODE_API_ROOT_WORKSPACE` env var.

### Fixed
- Workspace permissions.

## [v0.17.0] — 2026-03-28

### Added
- `--effort` (reasoning effort) flag in wrapper and API.

### Removed
- `claude-code-router` support.

## [v0.16.x] — 2026-03-28

### Added
- API expansion: `/files` with path params (`GET`/`PUT`/`DELETE`), `/health`, `/status`, `/run/cancel`.
- `--system-prompt`, `--append-system-prompt`, `--json-schema` flags in wrapper + API.
- Graceful API shutdown.
- `--continue` automatic fallback when no prior session.

### Changed
- API output is now JSON-only.

## [v0.15.0] — 2026-03-28

### Added
- **API mode** (`CLAUDE_MODE_API=1`) — FastAPI server.
- Multi-stage Dockerfile: `minimal` and `full` variants; `CLAUDE_MINIMAL` runtime flag.
- `CLAUDE_MOUNT_*` extra volume mounts.
- Per-workspace `409` locking.

### Changed
- `wrapper.sh` extracted from `install.sh` for clarity.

## [v0.14.x] — 2026-03-09/19

### Added
- `CLAUDE_MOUNT_*` extra volume mounts (same-path default, or explicit `src:dest`).
- Container env notes + overwrite warning baked into `CLAUDE.md`.

### Fixed
- Permissions / `chown` cleanup.

## [v0.13.x] — 2026-03-01/03

### Added
- `~/.claude/bin` in `PATH` for custom user scripts.
- `~/.claude/init.d/` hooks fired on first container creation.
- `CLAUDE_ENV_*` passthrough.
- `CLAUDE_INSTALL_DIR`, `CLAUDE_SSH_DIR`, `DEBUG` env-var docs.

### Removed
- Ephemeral mode (programmatic uses its own container — ephemeral was redundant).

## [v0.12.0] — 2026-02-27

### Added
- `--model` flag for programmatic / ephemeral runs.
- All available models documented.

## [v0.11.x – v0.10.x] — 2026-02-27

### Added
- **Programmatic** and **ephemeral** modes.
- `--no-update` flag (file-signal based).
- Argument whitelist + container lock.
- `--continue` automatic fallback.

### Changed
- Background auto-updates disabled by default.
- Restart instead of attach to existing containers.
- Trust pre-accept on first run.
- Bumped Claude CLI to 2.1.62.

### Fixed
- Silenced output for programmatic / ephemeral runs.

## [v0.9.x] — 2026-01-08 → 2026-02-03

### Added
- Native Claude installer (no more npm).

### Fixed
- Runtime permission fixes.
- Misc bug fixes; README updates.

## [v0.8.0] — 2025-12-10

### Added
- pyenv with Python 3.12.
- Auto-generated `CLAUDE.md` so Claude knows what tools are available in the container.

## [v0.7.x – v0.6.0] — 2025-11-23 → 2025-12-08

### Added
- Pinned Claude CLI version for reproducible builds.

## [v0.5.x] — 2025-10-10/13

### Fixed
- DNS resolution issue.

### Changed
- Image rebuild.

## [v0.4.0 – v0.1.0] — 2025-06-14 → 2025-08-25

Initial development: base image, more bundled tooling, project bootstrap.

[v1.11.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.11.0
[v1.10.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.10.0
[v1.9.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.9.0
[v1.8.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.8.0
[v1.7.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.7.0
[v1.6.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.6.0
[v1.5.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.5.0
[v1.4.1]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.4.1
[v1.4.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.4.0
[v1.3.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.3.0
[v1.2.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.2.0
[v1.1.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.1.0
[v1.0.0]: https://github.com/psyb0t/docker-claudebox/releases/tag/v1.0.0
