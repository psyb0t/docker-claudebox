#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO
# shellcheck source=tests/test-common.sh
source "$REPO/tests/test-common.sh"
trap 'log ERROR "contract check failed at line $LINENO"' ERR
readonly LOG_FILE="${LOG_FILE:-/tmp/claudebox-programmatic-contract.log}"
exec > >(tee -a "$LOG_FILE") 2>&1

ALL_TESTS=()
TEST_MODEL=haiku
# shellcheck source=tests/test_programmatic.sh
source "$REPO/tests/test_programmatic.sh"

_prog_setup() { :; }
_prog_cleanup() { :; }
_prog_run() {
    printf '%s\n' "$fixture"
    return "$fixture_status"
}

assert_contains() {
    [[ "$1" == *"$2"* ]]
}

readonly NATIVE_JSON='{"type":"result","result":"CAMELTEST","session_id":"session-test","is_error":false,"native_extra":{"tool_input":"unicode λ"}}'
readonly NATIVE_STREAM='{"type":"system","subtype":"init","session_id":"session-test"}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"STREAMTEST"}}}
{"type":"assistant","message":{"content":[{"type":"text","text":"STREAMTEST"}]}}
{"type":"result","result":"STREAMTEST","session_id":"session-test","is_error":false}'
fixture_status=0
fixture="$NATIVE_JSON"
test_programmatic_json_native || fail "native final JSON was rejected"
fixture="$NATIVE_STREAM"
test_programmatic_stream_json_native || fail "native NDJSON was rejected"

for fixture in '' 'null' '{' '{"type":"result","result":"CAMELTEST","is_error":false}' \
    "$NATIVE_JSON"$'\n'"$NATIVE_JSON" \
    "$(jq '.is_error = true' <<<"$NATIVE_JSON")"; do
    if test_programmatic_json_native; then
        fail "invalid native JSON passed"
    fi
done

for fixture in '' "$NATIVE_JSON" "${NATIVE_STREAM}"$'\nnot json' \
    "$NATIVE_STREAM"$'\n\n'"$NATIVE_JSON" \
    "$(tr '\n' ' ' <<<"$NATIVE_STREAM")" \
    "$(sed '$d' <<<"$NATIVE_STREAM")" \
    "$(jq -c 'if .type == "result" then .is_error = true else . end' <<<"$NATIVE_STREAM")"; do
    if test_programmatic_stream_json_native; then
        fail "invalid native stream passed"
    fi
done

fixture_status=1
fixture="$NATIVE_JSON"
if test_programmatic_json_native; then
    fail "failed JSON command passed"
fi
fixture="$NATIVE_STREAM"
if test_programmatic_stream_json_native; then
    fail "failed stream command passed"
fi

fixture_status=2
fixture='json-verbose is v1-only. In v2, use API mode:'
test_programmatic_json_verbose_rejected || fail "removed format rejection was rejected"
fixture_status=0
if test_programmatic_json_verbose_rejected; then
    fail "successful removed-format command passed"
fi

TEMP_DIR="$(mktemp -d)"
readonly TEMP_DIR
trap 'rm -rf -- "$TEMP_DIR"' EXIT
export DOCKER_CALLS="$TEMP_DIR/docker-calls"
export WRAPPER_STDOUT="$NATIVE_STREAM"
docker() {
    printf '%s\n' "$1" >>"$DOCKER_CALLS"
    if [[ "$1" == run ]]; then
        printf '%s\n' "$WRAPPER_STDOUT"
    fi
    return 0
}
export -f docker

run_wrapper() {
    AICODEBOX_LAUNCH_CONTEXT_VERSION=1 \
        CLAUDEBOX_DATA_DIR="$TEMP_DIR/data" \
        CLAUDEBOX_SSH_DIR="$TEMP_DIR/ssh" \
        CLAUDEBOX_CONTAINER_NAME=claudebox-contract \
        DEBUG=false CLAUDEBOX_FULL=0 CLAUDEBOX_IMAGE=example.invalid/claudebox:test \
        bash "$REPO/wrapper.sh" -p 'unused prompt' --no-continue "$@"
}

actual="$(run_wrapper --output-format stream-json)"
[[ "$actual" == "$NATIVE_STREAM" ]] || fail "wrapper changed native stream bytes"
export WRAPPER_STDOUT="$NATIVE_JSON"
actual="$(run_wrapper --output-format json)"
[[ "$actual" == "$NATIVE_JSON" ]] || fail "wrapper changed native JSON bytes"

for spelling in separate equals; do
    format_args=(--output-format json-verbose)
    [[ "$spelling" != equals ]] || format_args=(--output-format=json-verbose)
    : >"$DOCKER_CALLS"
    status=0
    output="$(run_wrapper "${format_args[@]}" 2>&1)" || status=$?
    [[ "$status" == 2 ]] || fail "wrapper accepted removed format"
    [[ "$output" == *'json-verbose is v1-only'* ]] || fail "missing migration error"
    [[ ! -s "$DOCKER_CALLS" ]] || fail "removed format reached Docker"
done
log INFO "native programmatic assertions passed"
