#!/bin/bash
# Seed workspace-level CLAUDE.md from the in-image template.
# Idempotent — leaves an existing CLAUDE.md alone.
set -euo pipefail

WORKSPACE_DIR="${AICODEBOX_WORKSPACE:-${AICODE_WORKSPACE:-/workspace}}"
VARIANT="${CLAUDEBOX_IMAGE_VARIANT:-minimal}"
TEMPLATE="/opt/claudebox/templates/CLAUDE.md.${VARIANT}"

if [ ! -f "$TEMPLATE" ]; then
    TEMPLATE="/opt/claudebox/templates/CLAUDE.md.minimal"
fi

if [ ! -f "$TEMPLATE" ]; then
    echo "[20-workspace-claude-md] no template at $TEMPLATE; skipping" >&2
    exit 0
fi

mkdir -p "$WORKSPACE_DIR"
if [ ! -f "${WORKSPACE_DIR}/CLAUDE.md" ]; then
    cp "$TEMPLATE" "${WORKSPACE_DIR}/CLAUDE.md"
fi
