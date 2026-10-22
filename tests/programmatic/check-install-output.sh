#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO
# shellcheck source=tests/test-common.sh
source "$REPO/tests/test-common.sh"
trap 'log ERROR "installation output check failed at line $LINENO"' ERR
readonly LOG_FILE="${LOG_FILE:-/tmp/claudebox-install-output.log}"
exec > >(tee -a "$LOG_FILE") 2>&1
readonly BASE_IMAGE="${BASE_IMAGE:-psyb0t/aicodebox:latest}"
readonly PREFIX="claudebox-install-output-$$"
OUTPUT_DIR="$(mktemp -d)"
readonly OUTPUT_DIR
trap 'rm -rf -- "$OUTPUT_DIR"' EXIT

run_case() {
    local name="$1" output="$2" npm_status="$3" warm="$4"
    local format=text
    case "$name" in
    json) format=json ;;
    stream) format=stream-json ;;
    esac
    docker run --rm --name "$PREFIX-$name" --network none \
        --mount "type=bind,src=$REPO/claudebox-entrypoint.sh,dst=/entrypoint.sh,readonly" \
        -e "TEST_AGENT_OUTPUT=$output" -e "TEST_NPM_STATUS=$npm_status" \
        -e "TEST_WARM=$warm" -e "TEST_OUTPUT_FORMAT=$format" --entrypoint bash "$BASE_IMAGE" -c '
            set -euo pipefail
            npm() {
                touch /tmp/npm-called
                printf "installer stdout\n"
                printf "installer stderr\n" >&2
                return "$TEST_NPM_STATUS"
            }
            export -f npm
            printf "#!/bin/bash\n[[ \"\$TEST_WARM\" != 1 || ! -e /tmp/npm-called ]] || exit 1\nprintf '\''%%s'\'' \"\$TEST_AGENT_OUTPUT\"\n" > /usr/local/bin/aicodebox-entrypoint
            if [[ "$TEST_WARM" == 1 ]]; then
                printf "#!/bin/sh\nexit 0\n" > /usr/local/bin/claude
                chmod +x /usr/local/bin/claude
            fi
            exec bash /entrypoint.sh -p unused --output-format "$TEST_OUTPUT_FORMAT"
        ' >"$OUTPUT_DIR/$name.stdout" 2>"$OUTPUT_DIR/$name.stderr"
    printf '%s' "$output" | cmp - "$OUTPUT_DIR/$name.stdout" || fail "$name: stdout changed"
    if [[ "$npm_status" == 0 ]]; then
        [[ ! -s "$OUTPUT_DIR/$name.stderr" ]] || fail "$name: successful installation was noisy"
        return
    fi
    grep -Fq 'installer stdout' "$OUTPUT_DIR/$name.stderr" || fail "missing installer stdout diagnostic"
    grep -Fq 'installer stderr' "$OUTPUT_DIR/$name.stderr" || fail "missing installer stderr diagnostic"
    grep -Fq 'could not install Claude Code' "$OUTPUT_DIR/$name.stderr" || fail "missing installation warning"
}

run_case text $'response λ\n' 0 0
run_case json $'{"result":"ok","is_error":false}\n' 0 0
run_case stream $'{"type":"system"}\n{"type":"result"}\n' 0 0
run_case empty '' 0 0
run_case warm $'already installed\n' 0 1
run_case failure '' 1 0
log INFO "installation output checks passed"
