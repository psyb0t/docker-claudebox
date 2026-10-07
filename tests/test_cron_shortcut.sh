#!/bin/bash
# Regression test: `<cron var>=1 claudebox` must start a <name>_cron container
# that the image actually runs in cron mode.
#
# The bug this guards: the wrapper passed CLAUDEBOX_MODE_CRON=1 into the
# container, a v1 name the v2 entrypoint never aliased, so the container
# started and cron mode never turned on. The wrapper now accepts the canonical
# name and both v1 spellings and always passes the canonical names inward.
#
# Hermetic: a fake `docker` on PATH logs its argv. No build, no containers.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
readonly WRAPPER="$REPO/wrapper.sh"
readonly CRON_FILE="/home/aicode/.aicodebox/cron.yaml"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"test_cron_shortcut.sh","msg":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$level" "$*" >&2
}

TMPROOT="$(mktemp -d)"
cleanup() {
    rm -rf "$TMPROOT"
}
trap cleanup EXIT INT TERM

failures=0
fail_case() {
    log ERROR "$*"
    failures=$((failures + 1))
}

# Fake docker: logs argv and prints nothing, so the wrapper's `docker ps`
# checks find no running or stopped cron container and it goes to `docker run`.
readonly FAKEBIN="$TMPROOT/bin"
mkdir -p "$FAKEBIN" "$TMPROOT/claude" "$TMPROOT/ssh"
cat >"$FAKEBIN/docker" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$TMPROOT/docker.log"
exit 0
EOF
chmod +x "$FAKEBIN/docker"

clear_inherited_env() {
    unset AICODEBOX_LAUNCH_CONTEXT_VERSION AICODEBOX_HOST_HOME AICODEBOX_HOST_WORKSPACE
    unset AICODEBOX_HOST_CODEX_HOME AICODEBOX_HOST_CLAUDE_HOME AICODEBOX_HOST_PI_HOME
    unset AICODEBOX_HOST_WRAPPER_DIR AICODEBOX_HOST_CODEX_WRAPPER
    unset AICODEBOX_HOST_CLAUDE_WRAPPER AICODEBOX_HOST_PI_WRAPPER
    unset CLAUDEBOX_CRON_MODE CLAUDEBOX_CRON_MODE_FILE
    unset CLAUDEBOX_MODE_CRON CLAUDEBOX_MODE_CRON_FILE
    unset CLAUDE_MODE_CRON CLAUDE_MODE_CRON_FILE
}

# Runs the wrapper under the given VAR=value assignments and prints the
# `docker run` line it produced.
cron_run_line() {
    : >"$TMPROOT/docker.log"
    (
        cd "$TMPROOT"
        clear_inherited_env
        PATH="$FAKEBIN:$PATH" \
            CLAUDEBOX_DATA_DIR="$TMPROOT/claude" \
            CLAUDEBOX_SSH_DIR="$TMPROOT/ssh" \
            env "$@" bash "$WRAPPER" >/dev/null 2>&1
    ) || true
    grep -m1 '^run -d --name ' "$TMPROOT/docker.log" || true
}

# mode var|file var, for each spelling the wrapper accepts.
readonly CASES=(
    "CLAUDEBOX_CRON_MODE|CLAUDEBOX_CRON_MODE_FILE"
    "CLAUDEBOX_MODE_CRON|CLAUDEBOX_MODE_CRON_FILE"
    "CLAUDE_MODE_CRON|CLAUDE_MODE_CRON_FILE"
)

for entry in "${CASES[@]}"; do
    IFS='|' read -r mode_var file_var <<<"$entry"
    failures_before=$failures
    line="$(cron_run_line "${mode_var}=1" "${file_var}=${CRON_FILE}")"

    if [[ -z "$line" ]]; then
        fail_case "$mode_var: wrapper did not start a cron container"
        continue
    fi
    [[ "$line" == *"_cron "* ]] ||
        fail_case "$mode_var: container is not named <name>_cron: $line"
    [[ "$line" == *"-e CLAUDEBOX_CRON_MODE=1 "* ]] ||
        fail_case "$mode_var: CLAUDEBOX_CRON_MODE=1 not passed: $line"
    [[ "$line" == *"-e CLAUDEBOX_CRON_MODE_FILE=${CRON_FILE} "* ]] ||
        fail_case "$mode_var: CLAUDEBOX_CRON_MODE_FILE not passed: $line"
    [[ "$line" != *"CLAUDEBOX_MODE_CRON"* ]] ||
        fail_case "$mode_var: the v1 CLAUDEBOX_MODE_CRON name reached the container: $line"
    ((failures == failures_before)) &&
        log INFO "pass: $mode_var starts a cron container with the canonical names"
done

line="$(cron_run_line "CLAUDEBOX_CRON_MODE=1")"
[[ "$line" != *"CRON_MODE_FILE"* ]] ||
    fail_case "no file var set, but a cron file was passed: $line"

if ((failures > 0)); then
    log ERROR "cron shortcut contract failed failures=$failures"
    exit 1
fi
log INFO "cron shortcut contract passed"
