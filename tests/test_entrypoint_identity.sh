#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
# shellcheck source=test-common.sh
source "$REPO/tests/test-common.sh"
trap 'log ERROR "Git identity contract failed at line $LINENO"' ERR
readonly LOG_FILE="${TEST_LOG_FILE:-/tmp/claudebox-git-identity.log}"
exec > >(tee -a "$LOG_FILE") 2>&1
readonly BASE_IMAGE="${BASE_IMAGE:-psyb0t/aicodebox:latest}"
readonly PREFIX="claudebox-identity-$$"

run_identity() {
    local case_id="$1" field="$2"
    shift 2
    docker run --rm --name "$PREFIX-$case_id" \
        --mount "type=bind,src=$REPO/claudebox-entrypoint.sh,dst=/entrypoint.sh,readonly" \
        -e AICODEBOX_AGENT_BINARY=/usr/bin/git -e "IDENTITY_FIELD=$field" \
        "$@" --entrypoint bash "$BASE_IMAGE" -c '
            set -euo pipefail
            printf "#!/bin/sh\\nexit 0\\n" > /usr/local/bin/claude
            chmod +x /usr/local/bin/claude
            exec bash /entrypoint.sh config --global --get "$IDENTITY_FIELD"
        '
}

actual="$(run_identity child user.name -e "CLAUDEBOX_GIT_NAME=Example User Ω")"
[[ "$actual" == "Example User Ω" ]] || fail "child Git name was not applied"
actual="$(run_identity shared user.name -e "CLAUDEBOX_GIT_NAME=child" -e AICODEBOX_GIT_NAME=shared)"
[[ "$actual" == shared ]] || fail "shared identity must win"
actual="$(run_identity email user.email -e "CLAUDEBOX_GIT_EMAIL=example@example.invalid")"
[[ "$actual" == example@example.invalid ]] || fail "child Git email was not applied"
if run_identity invalid user.name -e CLAUDEBOX_GIT_NAME=$'invalid\nname' >/dev/null 2>&1; then
    fail "multiline child identity was accepted"
fi
log INFO "claudebox Git identity contract passed"
