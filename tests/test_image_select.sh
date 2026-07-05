#!/bin/bash
# Regression test — install.sh and wrapper.sh MUST resolve the same image tag.
#
# The bug this guards: install.sh (with CLAUDEBOX_FULL=1) pulls
# psyb0t/claudebox:latest-full, but the wrapper ignored the flag and launched
# psyb0t/claudebox:latest (minimal). So `CLAUDEBOX_FULL=1 claudebox` ran a
# DIFFERENT (often stale, pre-CLAUDE_CONFIG_DIR) image than the one pulled —
# config landed in an ephemeral path and every run re-onboarded (theme + login).
#
# Two phases, both hermetic (fake `docker` on PATH — no build, no containers):
#   A. wrapper.sh resolves the expected tag for each flag combo.
#   B. install.sh's PULLED tag == wrapper.sh's RUN tag for the same env — the
#      actual root cause was these two disagreeing.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
readonly WRAPPER="$REPO/wrapper.sh"
readonly INSTALLER="$REPO/install.sh"
readonly OVERRIDE_IMAGE="my-registry/claudebox:custom"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"test_image_select.sh","msg":"%s"}\n' \
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

# Fake bin: `docker` logs its argv (and prints nothing, so the wrapper's `ps`
# check finds no container and proceeds to `docker run`); `sudo` runs its args
# without privilege so install.sh's `sudo install` writes into the sandbox.
readonly FAKEBIN="$TMPROOT/bin"
mkdir -p "$FAKEBIN" "$TMPROOT/claude" "$TMPROOT/ssh"
cat > "$FAKEBIN/docker" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$TMPROOT/docker.log"
exit 0
EOF
cat > "$FAKEBIN/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
chmod +x "$FAKEBIN/docker" "$FAKEBIN/sudo"

# Pull the psyb0t/claudebox:<tag> (or override) image token out of a log line.
image_token() {
    grep -oE '[[:graph:]]*claudebox:[[:graph:]]+' <<< "$1" | head -1
}

# Run the wrapper (programmatic mode, no TTY) under an env-assignment string;
# echo the resolved image from its `docker run` line.
wrapper_image() {
    local env_assigns="$1"
    : > "$TMPROOT/docker.log"
    (
        cd "$TMPROOT"
        # shellcheck disable=SC2086 # deliberate VAR=val word-split
        PATH="$FAKEBIN:$PATH" \
            CLAUDEBOX_DATA_DIR="$TMPROOT/claude" \
            CLAUDEBOX_SSH_DIR="$TMPROOT/ssh" \
            env $env_assigns bash "$WRAPPER" -p "hi" >/dev/null 2>&1
    ) || true
    image_token "$(grep -m1 'run --name' "$TMPROOT/docker.log" || true)"
}

# Run install.sh under an env-assignment string in a throwaway HOME (no existing
# ssh key -> no interactive prompt); echo the image it PULLED.
install_image() {
    local env_assigns="$1"
    local ihome
    ihome="$(mktemp -d)"
    : > "$TMPROOT/docker.log"
    (
        # shellcheck disable=SC2086 # deliberate VAR=val word-split
        HOME="$ihome" \
            PATH="$FAKEBIN:$PATH" \
            CLAUDEBOX_INSTALL_DIR="$TMPROOT/bin-installed" \
            env $env_assigns bash "$INSTALLER" >/dev/null 2>&1
    ) || true
    mkdir -p "$TMPROOT/bin-installed"
    image_token "$(grep -m1 '^pull ' "$TMPROOT/docker.log" || true)"
}

# ── Phase A — wrapper resolves the expected tag ──────────────────────────────
# name | env assignments | expected image
readonly WRAPPER_CASES=(
    "default||psyb0t/claudebox:latest"
    "full|CLAUDEBOX_FULL=1|psyb0t/claudebox:latest-full"
    "full-legacy-alias|CLAUDE_FULL=1|psyb0t/claudebox:latest-full"
    "minimal-is-noop|CLAUDEBOX_MINIMAL=1|psyb0t/claudebox:latest"
    "explicit-image-wins|CLAUDEBOX_IMAGE=${OVERRIDE_IMAGE}|${OVERRIDE_IMAGE}"
    "explicit-beats-full|CLAUDEBOX_FULL=1 CLAUDEBOX_IMAGE=${OVERRIDE_IMAGE}|${OVERRIDE_IMAGE}"
)

for tc in "${WRAPPER_CASES[@]}"; do
    IFS='|' read -r name env_assigns want <<< "$tc"
    log INFO "A/$name (env: ${env_assigns:-none})"
    got="$(wrapper_image "$env_assigns")"
    [ "$got" = "$want" ] \
        || fail "A/$name: wrapper resolved '$got', expected '$want'"
    log INFO "  PASS ($got)"
done

# ── Phase B — install.sh PULL tag == wrapper.sh RUN tag ──────────────────────
# Only the flags install.sh actually honors; CLAUDEBOX_IMAGE is a wrapper-only
# override (install always pulls a published tag), so it's excluded here.
readonly CONSISTENCY_CASES=(
    "default|"
    "full|CLAUDEBOX_FULL=1"
    "minimal|CLAUDEBOX_MINIMAL=1"
)

for tc in "${CONSISTENCY_CASES[@]}"; do
    IFS='|' read -r name env_assigns <<< "$tc"
    log INFO "B/$name (env: ${env_assigns:-none})"
    pulled="$(install_image "$env_assigns")"
    launched="$(wrapper_image "$env_assigns")"
    [ -n "$pulled" ] || fail "B/$name: install.sh pulled no image"
    [ -n "$launched" ] || fail "B/$name: wrapper launched no image"
    [ "$pulled" = "$launched" ] \
        || fail "B/$name: install pulls '$pulled' but wrapper runs '$launched' — pull/run mismatch (the original bug)"
    log INFO "  PASS (both use $pulled)"
done

log INFO "ALL IMAGE-SELECTION TESTS PASSED"
