#!/bin/bash
# Regression test: a reused <name>_prog container must run the new prompt.
#
# The bug this guards: when the _prog container already exists, the wrapper
# runs `docker start -a`, which replays the arguments the container was
# created with. The wrapper writes the new arguments to .<name>_prog-args for
# the container to read, but nothing in v2 read that file, so every later
# `claudebox -p` call answered the first prompt again.
#
# Hermetic: a fake `docker` on PATH plays a stopped _prog container. Its
# `start -a` runs claudebox-agent.sh with the container's original arguments,
# as the image would, and a fake `claude` records the arguments it gets.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO
readonly WRAPPER="$REPO/wrapper.sh"
readonly LAUNCHER="$REPO/claudebox-agent.sh"
readonly CONTAINER="claude-test"
readonly PROG="${CONTAINER}_prog"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"check-prog-reuse.sh","msg":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$level" "$*" >&2
}

TMPROOT="$(mktemp -d)"
cleanup() {
    rm -rf "$TMPROOT"
}
trap cleanup EXIT INT TERM

fail() {
    log ERROR "$*"
    exit 1
}

readonly FAKEBIN="$TMPROOT/bin"
readonly DATA="$TMPROOT/claude"
readonly CLAUDE_LOG="$TMPROOT/claude-argv.log"
mkdir -p "$FAKEBIN" "$DATA" "$TMPROOT/ssh" "$TMPROOT/ws"

# Fake claude: one argument per line, then a separator line.
cat >"$FAKEBIN/claude" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >>"$CLAUDE_LOG"
printf '%s\n' "--" >>"$CLAUDE_LOG"
exit 0
EOF

# Fake docker: the _prog container exists and is stopped. `start -a` runs the
# launcher with the arguments the container was created with, the way the
# image entrypoint does, and with the wrapper's data directory as the
# container's CLAUDE_CONFIG_DIR.
cat >"$FAKEBIN/docker" <<EOF
#!/bin/bash
case "\$1" in
    ps)
        for a in "\$@"; do [ "\$a" = "-a" ] && printf '%s\n' "$PROG"; done
        ;;
    start)
        CLAUDE_CONFIG_DIR="$DATA" CLAUDEBOX_CONTAINER_NAME="$PROG" \
            bash "$LAUNCHER" -p "FIRST PROMPT" --output-format text
        ;;
esac
exit 0
EOF
chmod +x "$FAKEBIN/claude" "$FAKEBIN/docker"

(
    cd "$TMPROOT/ws"
    for launch_var in "${!AICODEBOX_HOST_@}"; do
        unset "$launch_var"
    done
    unset AICODEBOX_LAUNCH_CONTEXT_VERSION CLAUDEBOX_CRON_MODE CLAUDEBOX_MODE_CRON CLAUDE_MODE_CRON
    PATH="$FAKEBIN:$PATH" \
        CLAUDEBOX_CONTAINER_NAME="$CONTAINER" \
        CLAUDEBOX_DATA_DIR="$DATA" \
        CLAUDEBOX_SSH_DIR="$TMPROOT/ssh" \
        bash "$WRAPPER" -p "second prompt with  spaces" --model haiku --no-continue
) >/dev/null 2>&1 || fail "wrapper exited non-zero"

[ -s "$CLAUDE_LOG" ] || fail "claude was not run"
log INFO "claude argv: $(tr '\n' ' ' <"$CLAUDE_LOG")"

grep -qxF "FIRST PROMPT" "$CLAUDE_LOG" &&
    fail "reused _prog container replayed its original prompt"
grep -qxF "second prompt with  spaces" "$CLAUDE_LOG" ||
    fail "new prompt did not reach claude as one argument"
grep -qxF "haiku" "$CLAUDE_LOG" || fail "--model value from the new call is missing"
grep -qxF -- "--continue" "$CLAUDE_LOG" && fail "--no-continue from the new call was ignored"
grep -qxF -- "--no-continue" "$CLAUDE_LOG" && fail "--no-continue leaked to claude"
[ -e "$DATA/.${PROG}-args" ] && fail "args file left behind"

log INFO "reused _prog container runs the new arguments"
