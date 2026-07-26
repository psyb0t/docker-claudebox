#!/bin/bash
# claudebox entrypoint — thin wrapper around the aicodebox base entrypoint.
#
# Translates CLAUDEBOX_* env vars to their AICODEBOX_* equivalents so the
# image presents a claudebox-branded surface to users. AICODEBOX_* still works
# (and wins if both are set) for power users and forward compatibility.
#
# Also creates compat symlinks so:
#  - /workspaces → /workspace (pre-v2 codebase used the plural)
#  - /home/aicode/.claude → /home/aicode/.aicodebox (bind mounts of ~/.claude
#    from pre-v2 users still resolve to the state dir)
set -euo pipefail

# CLAUDEBOX_<suffix> → AICODEBOX_<suffix>. If both are set, AICODEBOX_ wins.
# Also alias legacy CLAUDE_MODE_* (pre-CLAUDEBOX_ era) forward.
_CLAUDEBOX_ALIASES=(
    API_MODE
    API_MODE_PORT
    API_MODE_TOKEN
    TELEGRAM_MODE
    TELEGRAM_MODE_TOKEN
    TELEGRAM_MODE_CONFIG
    TELEGRAM_MODE_OVERRIDES
    CRON_MODE
    CRON_MODE_FILE
    CRON_MODE_HISTORY_DIR
    MCP_MODE
    MCP_MODE_PORT
    MCP_MODE_TOKEN
    WORKSPACE
    AVAILABLE_MODELS
    AVAILABLE_EFFORTS
    CONTAINER_NAME
)

for _suffix in "${_CLAUDEBOX_ALIASES[@]}"; do
    _cb_var="CLAUDEBOX_${_suffix}"
    _ai_var="AICODEBOX_${_suffix}"
    _cb_val="$(printenv "$_cb_var" 2>/dev/null || true)"
    _ai_val="$(printenv "$_ai_var" 2>/dev/null || true)"
    if [ -n "$_cb_val" ] && [ -z "$_ai_val" ]; then
        export "$_ai_var=$_cb_val"
    fi
done

# Legacy CLAUDE_MODE_* → AICODEBOX_*_MODE (pre-CLAUDEBOX_ naming from v1.x).
_LEGACY_MODE_MAP=(
    "CLAUDE_MODE_API:AICODEBOX_API_MODE"
    "CLAUDE_MODE_API_PORT:AICODEBOX_API_MODE_PORT"
    "CLAUDE_MODE_API_TOKEN:AICODEBOX_API_MODE_TOKEN"
    "CLAUDE_MODE_TELEGRAM:AICODEBOX_TELEGRAM_MODE"
    "CLAUDE_MODE_CRON:AICODEBOX_CRON_MODE"
    "CLAUDE_MODE_CRON_FILE:AICODEBOX_CRON_MODE_FILE"
    "CLAUDE_WORKSPACE:AICODEBOX_WORKSPACE"
    "CLAUDE_TELEGRAM_BOT_TOKEN:AICODEBOX_TELEGRAM_MODE_TOKEN"
    "CLAUDE_TELEGRAM_CONFIG:AICODEBOX_TELEGRAM_MODE_CONFIG"
)

for _pair in "${_LEGACY_MODE_MAP[@]}"; do
    _legacy="${_pair%%:*}"
    _target="${_pair##*:}"
    _legacy_val="$(printenv "$_legacy" 2>/dev/null || true)"
    _target_val="$(printenv "$_target" 2>/dev/null || true)"
    if [ -n "$_legacy_val" ] && [ -z "$_target_val" ]; then
        export "$_target=$_legacy_val"
    fi
done

unset _CLAUDEBOX_ALIASES _LEGACY_MODE_MAP _suffix _cb_var _ai_var _cb_val _ai_val _pair _legacy _target _legacy_val _target_val

# Compat symlinks — resolve pre-v2 paths (plural /workspaces + ~/.claude bind
# mount) to the aicodebox singular /workspace + ~/.aicodebox state dir.
WORKSPACE_DIR="${AICODEBOX_WORKSPACE:-${AICODE_WORKSPACE:-/workspace}}"
if [ ! -e /workspaces ] && [ "$WORKSPACE_DIR" != "/workspaces" ]; then
    ln -sfn "$WORKSPACE_DIR" /workspaces 2>/dev/null || true
fi

AICODE_HOME="/home/aicode"
if [ ! -e "${AICODE_HOME}/.aicodebox" ] && [ -d "${AICODE_HOME}/.claude" ]; then
    # First boot on an existing ~/.claude bind mount — direct base state at it.
    ln -sfn "${AICODE_HOME}/.claude" "${AICODE_HOME}/.aicodebox" 2>/dev/null || true
elif [ ! -e "${AICODE_HOME}/.claude" ]; then
    mkdir -p "${AICODE_HOME}/.aicodebox"
    ln -sfn "${AICODE_HOME}/.aicodebox" "${AICODE_HOME}/.claude" 2>/dev/null || true
fi

# Claude Code — install on first run if absent. It is deliberately NOT baked
# into the image (Anthropic's CLI is proprietary and cannot be redistributed),
# so each container fetches the pinned version from npm at startup. Runs while
# still root here, so it lands on the shared npm global PATH exactly as the
# old build-time `RUN npm install -g` did, before the base entrypoint drops
# privileges. Fresh container installs once; a warm restart finds it and skips.
# Same install command + flags as the previous Dockerfile step.
if ! command -v claude >/dev/null 2>&1; then
    echo "[claudebox] Claude Code not present — installing @anthropic-ai/claude-code@${CLAUDEBOX_CLAUDE_VERSION:-latest} from npm (first run)..." >&2
    if npm install -g --no-audit --no-fund "@anthropic-ai/claude-code@${CLAUDEBOX_CLAUDE_VERSION:-latest}"; then
        echo "[claudebox] Claude Code installed." >&2
    else
        echo "[claudebox] WARNING: could not install Claude Code (offline or npm error) — modes that need it will fail until it installs; check network and restart." >&2
    fi
fi

# Hand off to the base — it owns UID/GID rematch, init.d dispatch, mode
# selection, MCP sidecar, and the setpriv drop.
exec /usr/local/bin/aicodebox-entrypoint "$@"
