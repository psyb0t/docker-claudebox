#!/bin/bash
# Patch ~/.claude.json so claude-code runs headless in the container:
#   installMethod=native  → skip the auto-update chatter
#   autoUpdates=false     → don't try to self-update (image ships pinned version)
#   autoUpdatesProtectedForNative=true → belt-and-braces guard
#   projects.<ws>.hasTrustDialogAccepted=true → don't prompt for trust on -p
# Idempotent — safe to re-run.
set -euo pipefail

# Patch the .claude.json that Claude Code actually reads. With
# CLAUDE_CONFIG_DIR set (to the bind-mounted ~/.claude), Claude Code keeps
# .claude.json there so it PERSISTS across container recreates — theme,
# onboarding + oauthAccount survive, so a fresh container opens logged-in.
# Fall back to $HOME when the var is unset (agent-agnostic / older setups).
CLAUDE_JSON="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
SEED_JSON="/claude/.claude.json"
WORKSPACE_DIR="${AICODEBOX_WORKSPACE:-${AICODE_WORKSPACE:-/workspace}}"

mkdir -p "$(dirname "$CLAUDE_JSON")"

if [ ! -f "$CLAUDE_JSON" ]; then
    if [ -f "$SEED_JSON" ]; then
        cp "$SEED_JSON" "$CLAUDE_JSON"
    else
        echo "{}" > "$CLAUDE_JSON"
    fi
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "[10-claude-json-patch] jq missing; skipping" >&2
    exit 0
fi

tmp="$(mktemp)"
jq \
    --arg dir "$WORKSPACE_DIR" \
    '.installMethod = "native"
     | .autoUpdates = false
     | .autoUpdatesProtectedForNative = true
     | .projects[$dir].hasTrustDialogAccepted = true' \
    "$CLAUDE_JSON" > "$tmp" && mv "$tmp" "$CLAUDE_JSON"
