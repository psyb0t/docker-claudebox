#!/bin/bash
# claudebox agent launcher — restores the interactive/one-shot defaults that the
# agent-agnostic aicodebox base dropped when it replaced the pre-v2 entrypoint's
# `exec claude --dangerously-skip-permissions --continue --append-system-prompt …`
# with a bare `exec claude "$@"`.
#
# aicodebox's passthrough runs `exec $AICODEBOX_AGENT_BINARY "$@"` for BOTH
# interactive (`claudebox`) and one-shot (`claudebox -p …`) sessions. Pointing
# AICODEBOX_AGENT_BINARY at this script lets claudebox re-add the Claude-specific
# defaults. Server modes (API/telegram/cron) build argv via the adapter and spawn
# `claude` directly (the adapter binary is the hardcoded "claude"), so they never
# reach this script and are unaffected.
#
# Restores, matching pre-v2 (v1.14.1 entrypoint.sh):
#   - --continue (resume the workspace's last session) with a graceful fallback
#     to a fresh session when there's nothing to resume; honors the
#     .<container>-no-continue marker and --no-continue / --resume in args.
#   - --permission-mode bypassPermissions (no per-tool prompts in the sandbox;
#     the adapter's modern equivalent of pre-v2's --dangerously-skip-permissions).
#   - --append-system-prompt = system-hint + always-skills (same sources/order
#     as the adapter's _compose_append_system_prompt).
#   - `claude update` when the wrapper's --update wrote the .<container>-update marker.
set -euo pipefail

readonly CLAUDE_BIN="claude"
readonly CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
readonly CONTAINER="${CLAUDEBOX_CONTAINER_NAME:-}"

dbg() {
    [ "${DEBUG:-}" = "true" ] && printf '[claudebox-agent] %s\n' "$*" >&2
    return 0
}

# Subcommands that must run verbatim — no session/permission/append injection.
case "${1:-}" in
    setup-token | -v | --version | doctor | auth | mcp)
        dbg "passthrough subcommand: ${1}"
        exec "$CLAUDE_BIN" "$@"
        ;;
esac

# --append-system-prompt payload: system-hint first, then always-skills,
# matching the adapter's composition order.
hint_file="${CLAUDEBOX_SYSTEM_HINT_FILE:-$CFG/system-hint.txt}"
skills_dir="${CLAUDEBOX_ALWAYS_SKILLS_DIR:-$CFG/.always-skills}"
append=""
[ -f "$hint_file" ] && append="$(cat "$hint_file")"
if [ -d "$skills_dir" ]; then
    while IFS= read -r -d '' skill_file; do
        skill_content="$(cat "$skill_file")"
        [ -n "$skill_content" ] || continue
        skill_block="[Skill file: ${skill_file}]

${skill_content}"
        if [ -n "$append" ]; then
            append="${append}

${skill_block}"
        else
            append="$skill_block"
        fi
    done < <(find "$skills_dir" -name SKILL.md -print0 2>/dev/null | sort -z)
fi

flags=(--permission-mode bypassPermissions)
[ -n "$append" ] && flags+=(--append-system-prompt "$append")

# Update marker: the wrapper's --update touched .<container>-update. Update first,
# then fall through to the normal launch.
#
# `claude update` rewrites the npm global install under /usr/lib/node_modules,
# which is root-owned (the image installs claude-code via `npm install -g` as
# root), but the runtime user is aicode (uid 1000). A bare `claude update` dies
# with "Insufficient permissions to install update". aicode has passwordless
# sudo, so run the update through sudo to write the root-owned global dir.
if [ -n "$CONTAINER" ] && [ -f "$CFG/.${CONTAINER}-update" ]; then
    dbg "update marker present — running claude update via sudo"
    rm -f "$CFG/.${CONTAINER}-update"
    sudo "$CLAUDE_BIN" update || true
fi

# Auto-continue unless the caller opted out via --resume / --no-continue, or the
# wrapper wrote the one-shot .<container>-no-continue marker.
want_continue=1
for arg in "$@"; do
    case "$arg" in
        --resume | --resume=* | --no-continue) want_continue=0 ;;
    esac
done
if [ -n "$CONTAINER" ] && [ -f "$CFG/.${CONTAINER}-no-continue" ]; then
    dbg "no-continue marker present — skipping --continue"
    rm -f "$CFG/.${CONTAINER}-no-continue"
    want_continue=0
fi

# Drop --no-continue — it's a claudebox flag, not a claude flag.
args=()
for arg in "$@"; do
    [ "$arg" = "--no-continue" ] && continue
    args+=("$arg")
done

if [ "$want_continue" -eq 1 ]; then
    dbg "launching with --continue (fallback to fresh if nothing to resume)"
    # claude --continue exits non-zero before starting when there's nothing to
    # resume, so fall back to a fresh session in that case.
    "$CLAUDE_BIN" "${flags[@]}" --continue ${args[@]+"${args[@]}"} \
        || exec "$CLAUDE_BIN" "${flags[@]}" ${args[@]+"${args[@]}"}
else
    dbg "launching without --continue"
    exec "$CLAUDE_BIN" "${flags[@]}" ${args[@]+"${args[@]}"}
fi
