#!/bin/bash
# Regression test — onboarding/login/theme MUST persist across container
# recreates via the bind-mounted ~/.claude.
#
# The bug this guards (regression from the v2.0.0 aicodebox rebase): the
# entrypoint stopped setting CLAUDE_CONFIG_DIR to the bind-mounted config dir,
# so Claude Code read/wrote its config (.claude.json — theme, the
# onboarding-complete flag, oauthAccount) at the ephemeral $HOME/.claude.json
# instead of the mounted /home/aicode/.claude/.claude.json. Every fresh
# container then re-prompted for theme + login. Empirically, with
# CLAUDE_CONFIG_DIR unset the mounted .claude.json is never written; with it
# set, Claude Code persists there (firstStartTime/userID land on the mount).
#
# Boots the REAL image through the REAL entrypoint (mirroring wrapper.sh, which
# bind-mounts a host dir at /home/aicode/.claude) and asserts:
#   1. the agent process actually sees CLAUDE_CONFIG_DIR = the mounted dir;
#   2. Claude Code persists its own config ON THE MOUNT (a claude-written key
#      lands there, not just the init.d seed);
#   3. a pre-seeded onboarding config (theme + onboarding + account) survives a
#      run — i.e. the next container opens configured, not re-onboarding.
#
# Requires: docker, python3. Image psyb0t/claudebox:latest must exist (make build).
set -euo pipefail

readonly IMAGE="${IMAGE:-psyb0t/claudebox:latest}"
readonly MOUNT="/home/aicode/.claude"      # where wrapper.sh bind-mounts ~/.claude
readonly AICODE_UID=1000                    # the in-image agent user
# A NON-default theme: Claude Code omits the default ("dark") from .claude.json,
# so seeding "dark" would legitimately vanish. A non-default value is what a real
# "I picked a theme" choice looks like and must survive.
readonly SEED_THEME="dark-daltonized"
readonly SEED_ACCOUNT="persist-test-sentinel-1234"
# A key Claude Code itself writes (never the init.d seed) — its presence on the
# mount proves claude persisted there rather than to the ephemeral $HOME.
readonly CLAUDE_WRITTEN_KEY="userID"
readonly VOL="claudebox-persist-$$"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"test_persist.sh","msg":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$level" "$*" >&2
}

cleanup() {
    # best-effort teardown; the volume may already be gone on the happy path
    docker volume rm "$VOL" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

fail() {
    log ERROR "$*"
    exit 1
}

# Run a shell snippet against the volume via a throwaway alpine, so the test
# host needs no special perms to read the (root/1000-owned) volume files.
vol_sh() {
    docker run --rm -v "$VOL":/m alpine sh -c "$1"
}

# Fresh, aicode-owned mount standing in for the host ~/.claude the wrapper
# bind-mounts. The chown mirrors what the entrypoint does to a real mount.
docker volume create "$VOL" >/dev/null
vol_sh "chown ${AICODE_UID}:${AICODE_UID} /m && chmod 700 /m"

# ── Test 1 — the agent process sees CLAUDE_CONFIG_DIR = the mounted dir ───────
# Swap the agent binary for `printenv` so we observe EXACTLY the environment
# Claude Code runs with, after the full entrypoint + setpriv drop.
log INFO "Test 1: agent process sees CLAUDE_CONFIG_DIR pointing at the mount"
ccd="$(docker run --rm -v "$VOL":"$MOUNT" -e AICODEBOX_AGENT_BINARY=printenv \
    "$IMAGE" CLAUDE_CONFIG_DIR 2>/dev/null | tr -d '\r' | tail -1)"
[ "$ccd" = "$MOUNT" ] \
    || fail "agent CLAUDE_CONFIG_DIR='$ccd', expected '$MOUNT' — config would go to ephemeral \$HOME/.claude.json and re-onboard"
log INFO "  PASS (CLAUDE_CONFIG_DIR=$ccd)"

# ── Test 2 — Claude Code persists its own config ON THE MOUNT ─────────────────
# A real `claude -p` run writes .claude.json before it needs auth. It exits
# non-zero here (no valid credentials) — expected; we only assert on what it
# persisted first. The mounted file must carry a claude-written key, proving
# Claude Code wrote to the mount and not to the ephemeral $HOME.
log INFO "Test 2: claude persists its config (with $CLAUDE_WRITTEN_KEY) to the mount"
docker run --rm -v "$VOL":"$MOUNT" "$IMAGE" -p "hi" >/dev/null 2>&1 \
    || true   # non-zero exit expected without auth; the config write happens first
vol_sh 'test -f /m/.claude.json' \
    || fail "no .claude.json on the mount after a run — config went to ephemeral \$HOME"
has_key="$(
    vol_sh 'cat /m/.claude.json' \
        | python3 -c "import json,sys; print('${CLAUDE_WRITTEN_KEY}' in json.load(sys.stdin))"
)"
[ "$has_key" = "True" ] \
    || fail "mounted .claude.json lacks '$CLAUDE_WRITTEN_KEY' — Claude Code wrote its config to ephemeral \$HOME; only the init.d seed persisted"
log INFO "  PASS ($CLAUDE_WRITTEN_KEY present on the mounted config)"

# ── Test 3 — a pre-seeded onboarding config survives a run ────────────────────
# Seed theme + onboarding + a sentinel account, run, and assert they survive.
# This is the end-to-end "won't re-onboard next time" proof.
log INFO "Test 3: seeded theme + onboarding + account survive a run"
vol_sh "cat > /m/.claude.json <<'JSON'
{\"theme\":\"${SEED_THEME}\",\"hasCompletedOnboarding\":true,\"oauthAccount\":{\"accountUuid\":\"${SEED_ACCOUNT}\"}}
JSON
chown ${AICODE_UID}:${AICODE_UID} /m/.claude.json"
docker run --rm -v "$VOL":"$MOUNT" "$IMAGE" -p "hi" >/dev/null 2>&1 \
    || true   # non-zero exit expected without auth; config merge happens first
survived="$(
    vol_sh 'cat /m/.claude.json' \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print('|'.join([str(d.get('theme')), str(d.get('hasCompletedOnboarding')), str((d.get('oauthAccount') or {}).get('accountUuid'))]))"
)"
readonly EXPECTED_SURVIVED="${SEED_THEME}|True|${SEED_ACCOUNT}"
[ "$survived" = "$EXPECTED_SURVIVED" ] \
    || fail "seeded onboarding state did not survive (got '$survived', want '$EXPECTED_SURVIVED') — theme/login would re-prompt"
log INFO "  PASS (theme+onboarding+account persisted)"

log INFO "ALL PERSISTENCE TESTS PASSED"
