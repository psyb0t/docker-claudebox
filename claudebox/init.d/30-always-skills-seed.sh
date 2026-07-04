#!/bin/bash
# Ensure ~/.claude/.always-skills exists so the adapter's per-call scan has a
# stable target dir. Users drop SKILL.md files under this path (typically via a
# bind mount from the host's dotfiles). Missing dir is non-fatal — the adapter
# gracefully returns empty when the scan finds nothing.
set -euo pipefail

SKILLS_DIR="${HOME}/.claude/.always-skills"
HINT_FILE="${HOME}/.claude/system-hint.txt"

mkdir -p "$SKILLS_DIR"
chmod 755 "$SKILLS_DIR"

if [ ! -f "$HINT_FILE" ]; then
    cat > "$HINT_FILE" <<'HINT'
You are running in a Docker container with passwordless sudo access. ~/.claude/bin is in PATH — custom user scripts may be available there. Docker socket may be mounted for docker-in-docker. The workspace path inside the container matches the host path so docker volume mounts from within this container resolve correctly on the host.
HINT
fi
