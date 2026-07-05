#!/bin/bash
# Regression test — claudebox-agent.sh (the interactive/one-shot launcher).
#
# Guards the pre-v2 defaults the agent-agnostic aicodebox base dropped: the
# launcher must add --permission-mode bypassPermissions + --continue (resume) for
# interactive and `-p` sessions, honor the no-continue marker and
# --no-continue/--resume opt-outs, pass version/doctor/mcp through verbatim, and
# fall back to a fresh session when --continue has nothing to resume.
#
# Hermetic: a fake `claude` on PATH records argv; no docker, no real claude.
set -euo pipefail

LAUNCHER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claudebox-agent.sh"
readonly LAUNCHER
readonly CONTAINER="testctr"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"test_agent_launcher.sh","msg":"%s"}\n' \
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
readonly CFG="$TMPROOT/cfg"
readonly LOG="$TMPROOT/claude-argv.log"
mkdir -p "$FAKEBIN" "$CFG"

# Fake claude: record argv; optionally fail when --continue is present so the
# launcher's resume->fresh fallback can be exercised.
cat > "$FAKEBIN/claude" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$LOG"
if [ "\${FAKE_FAIL_ON_CONTINUE:-}" = "1" ]; then
    for a in "\$@"; do [ "\$a" = "--continue" ] && exit 1; done
fi
exit 0
EOF
chmod +x "$FAKEBIN/claude"

# Run the launcher with a given extra-env string; capture argv into $LOG.
run_launcher() {
    local env_assigns="$1"
    shift
    : > "$LOG"
    # shellcheck disable=SC2086 # deliberate VAR=val word-split
    PATH="$FAKEBIN:$PATH" CLAUDE_CONFIG_DIR="$CFG" CLAUDEBOX_CONTAINER_NAME="$CONTAINER" \
        env $env_assigns bash "$LAUNCHER" "$@" >/dev/null 2>&1 || true
}

log_has() { grep -qF -- "$1" "$LOG"; }
log_line_count() { grep -c '' "$LOG" 2>/dev/null || echo 0; }

# ── 1. interactive (no args) → skip-permissions + continue ───────────────────
log INFO "1: interactive adds --permission-mode bypassPermissions --continue"
run_launcher ""
log_has "--permission-mode bypassPermissions" || fail "1: missing --permission-mode bypassPermissions ($(cat "$LOG"))"
log_has "--continue" || fail "1: missing --continue ($(cat "$LOG"))"
log INFO "  PASS ($(cat "$LOG"))"

# ── 2. --version passes through verbatim (no injected flags) ──────────────────
log INFO "2: --version verbatim, no injected flags"
run_launcher "" --version
[ "$(cat "$LOG")" = "--version" ] || fail "2: expected exactly '--version', got '$(cat "$LOG")'"
log INFO "  PASS"

# ── 3. one-shot -p → skip-permissions + continue + the args ──────────────────
log INFO "3: -p adds skip-permissions + continue and keeps args"
run_launcher "" -p "hi"
log_has "--permission-mode bypassPermissions" || fail "3: missing skip-permissions"
log_has "--continue" || fail "3: missing --continue"
log_has "-p hi" || fail "3: prompt args dropped ($(cat "$LOG"))"
log INFO "  PASS"

# ── 4. no-continue marker → no --continue, marker consumed ───────────────────
log INFO "4: no-continue marker suppresses --continue and is removed"
: > "$CFG/.${CONTAINER}-no-continue"
run_launcher ""
log_has "--continue" && fail "4: --continue present despite no-continue marker ($(cat "$LOG"))"
[ -f "$CFG/.${CONTAINER}-no-continue" ] && fail "4: no-continue marker not consumed"
log INFO "  PASS"

# ── 5. --no-continue arg → no --continue, flag stripped ──────────────────────
log INFO "5: --no-continue suppresses + is stripped (not passed to claude)"
run_launcher "" --no-continue
log_has "--continue" && fail "5: --continue present despite --no-continue"
log_has "--no-continue" && fail "5: --no-continue leaked to claude ($(cat "$LOG"))"
log INFO "  PASS"

# ── 6. --resume → no auto --continue, resume passes through ──────────────────
log INFO "6: --resume opts out of auto --continue"
run_launcher "" --resume "sess-123"
log_has "--continue" && fail "6: auto --continue present alongside --resume"
log_has "--resume sess-123" || fail "6: --resume args dropped ($(cat "$LOG"))"
log INFO "  PASS"

# ── 7. fallback: --continue fails → retry fresh (no --continue) ──────────────
log INFO "7: resume failure falls back to a fresh session"
run_launcher "FAKE_FAIL_ON_CONTINUE=1"
[ "$(log_line_count)" -ge 2 ] || fail "7: expected 2 claude invocations (resume + fallback), got: $(cat "$LOG")"
tail -1 "$LOG" | grep -qF -- "--continue" && fail "7: fallback invocation still had --continue ($(cat "$LOG"))"
tail -1 "$LOG" | grep -qF -- "--permission-mode bypassPermissions" || fail "7: fallback lost --permission-mode bypassPermissions"
log INFO "  PASS (resume then fresh)"

log INFO "ALL AGENT-LAUNCHER TESTS PASSED"
