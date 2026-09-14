#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
TMP_ROOT="$(mktemp -d)"
readonly TMP_ROOT
trap 'rm -rf "$TMP_ROOT"' EXIT
readonly FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN" "$TMP_ROOT/home/.ssh/claudebox" "$TMP_ROOT/wrappers" "$TMP_ROOT/remote"
: >"$TMP_ROOT/home/.ssh/claudebox/id_ed25519"

cat >"$FAKE_BIN/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMP_ROOT/docker.log"
exit 0
EOF
cat >"$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat >"$FAKE_BIN/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMP_ROOT/curl.log"
while [[ "\$#" -gt 0 ]]; do
    if [[ "\$1" == -o ]]; then
        shift
        cp "$REPO/wrapper.sh" "\$1"
        exit 0
    fi
    shift
done
exit 1
EOF
chmod +x "$FAKE_BIN/docker" "$FAKE_BIN/sudo" "$FAKE_BIN/curl"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

for name in codexbox claudebox pibox; do
    printf '#!/bin/sh\n' >"$TMP_ROOT/wrappers/$name"
done

: >"$TMP_ROOT/docker.log"
(
    cd "$TMP_ROOT"
    HOME=/home/aicode PATH="$FAKE_BIN:$PATH" \
        AICODEBOX_LAUNCH_CONTEXT_VERSION=1 \
        AICODEBOX_HOST_HOME="$TMP_ROOT/home" \
        AICODEBOX_HOST_CODEX_HOME="$TMP_ROOT/home/.codex" \
        AICODEBOX_HOST_CLAUDE_HOME="$TMP_ROOT/home/.claude" \
        AICODEBOX_HOST_PI_HOME="$TMP_ROOT/home/.pi" \
        AICODEBOX_HOST_WRAPPER_DIR="$TMP_ROOT/wrappers" \
        AICODEBOX_ENV_SHARED_VALUE=visible \
        AICODEBOX_MOUNT_SHARED="$TMP_ROOT/shared:/shared" \
        bash "$REPO/wrapper.sh" -p test --no-continue >/dev/null
)
launch="$(cat "$TMP_ROOT/docker.log")"
[[ "$launch" == *"run --rm"* ]] || fail "nested programmatic launch is not disposable"
for name in codexbox claudebox pibox; do
    [[ "$launch" == *"dst=/usr/local/bin/$name,readonly"* ]] || fail "missing $name wrapper mount"
done
[[ "$launch" == *"AICODEBOX_HOST_HOME=$TMP_ROOT/home"* ]] || fail "missing host-home context"
[[ "$launch" == *"SHARED_VALUE=visible"* ]] || fail "missing common environment"
[[ "$launch" == *"$TMP_ROOT/shared:/shared"* ]] || fail "missing common mount"

cp "$REPO/install.sh" "$TMP_ROOT/remote/install.sh"
HOME="$TMP_ROOT/home" PATH="$FAKE_BIN:$PATH" \
    CLAUDEBOX_INSTALL_DIR="$TMP_ROOT/wrappers" \
    CLAUDEBOX_BIN_NAME=claudebox AICODEBOX_MANAGED_INSTALL=1 \
    bash "$TMP_ROOT/remote/install.sh" </dev/null >/dev/null
[[ -x "$TMP_ROOT/wrappers/claudebox" ]] || fail "managed installer target"
curl_call="$(cat "$TMP_ROOT/curl.log")"
[[ "$curl_call" == *"/v2.4.2/wrapper.sh"* ]] || fail "wrapper download is not release-pinned"

if AICODEBOX_LAUNCH_CONTEXT_VERSION=2 bash "$REPO/wrapper.sh" --version >/dev/null 2>&1; then
    fail "unsupported nested-launch context was accepted"
fi

printf 'managed installer and nested launch tests passed\n'
