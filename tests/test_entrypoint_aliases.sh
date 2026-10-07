#!/bin/bash
# Regression test: claudebox-entrypoint.sh maps every claudebox mode env name
# onto the AICODEBOX_* name the base entrypoint reads.
#
# The bug this guards: v2.0.0 renamed CLAUDEBOX_MODE_* to CLAUDEBOX_*_MODE and
# the CHANGELOG promised the old names still worked, but the entrypoint only
# aliased CLAUDE_MODE_*, so CLAUDEBOX_MODE_CRON=1 started a container that
# never entered cron mode.
#
# Runs the repo's entrypoint in a plain ubuntu container with a stub base
# entrypoint that prints the AICODEBOX_* env it receives, and a stub `claude`
# so the first-run npm install is skipped. No image build needed.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
readonly RUNNER_IMAGE="${RUNNER_IMAGE:-ubuntu:24.04}"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"test_entrypoint_aliases.sh","msg":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$level" "$*" >&2
}

failures=0

# Runs the entrypoint under the given VAR=value assignments and prints the
# AICODEBOX_* variables it handed to the base entrypoint, sorted.
aliased_env() {
    local env_args=()
    local assignment
    for assignment in "$@"; do
        env_args+=(-e "$assignment")
    done
    docker run --rm \
        -v "$REPO/claudebox-entrypoint.sh:/claudebox-entrypoint.sh:ro" \
        "${env_args[@]}" \
        --entrypoint bash "$RUNNER_IMAGE" -c '
            set -euo pipefail
            printf "#!/bin/sh\nprintenv | grep ^AICODEBOX_ | sort\n" > /usr/local/bin/aicodebox-entrypoint
            printf "#!/bin/sh\nexit 0\n" > /usr/local/bin/claude
            chmod +x /usr/local/bin/aicodebox-entrypoint /usr/local/bin/claude
            bash /claudebox-entrypoint.sh
        '
}

expect_env() {
    local description="$1"
    local expected="$2"
    shift 2
    local actual
    actual="$(aliased_env "$@")"
    if [[ "$actual" == *"$expected"* ]]; then
        log INFO "pass: $description"
        return 0
    fi
    log ERROR "fail: $description expected=[$expected] actual=[$actual]"
    failures=$((failures + 1))
}

# description|expected AICODEBOX_ line|assignments (space separated)
readonly CASES=(
    "v1 cron flag|AICODEBOX_CRON_MODE=1|CLAUDEBOX_MODE_CRON=1"
    "v1 cron file|AICODEBOX_CRON_MODE_FILE=/c.yaml|CLAUDEBOX_MODE_CRON_FILE=/c.yaml"
    "v1 api flag|AICODEBOX_API_MODE=1|CLAUDEBOX_MODE_API=1"
    "v1 api port|AICODEBOX_API_MODE_PORT=9090|CLAUDEBOX_MODE_API_PORT=9090"
    "v1 api token|AICODEBOX_API_MODE_TOKEN=fake-token|CLAUDEBOX_MODE_API_TOKEN=fake-token"
    "v1 telegram flag|AICODEBOX_TELEGRAM_MODE=1|CLAUDEBOX_MODE_TELEGRAM=1"
    "early v1 cron flag|AICODEBOX_CRON_MODE=1|CLAUDE_MODE_CRON=1"
    "canonical cron flag|AICODEBOX_CRON_MODE=1|CLAUDEBOX_CRON_MODE=1"
    "canonical name wins over v1|AICODEBOX_CRON_MODE_FILE=/canonical.yaml|CLAUDEBOX_CRON_MODE_FILE=/canonical.yaml CLAUDEBOX_MODE_CRON_FILE=/legacy.yaml"
    "AICODEBOX name wins over every alias|AICODEBOX_CRON_MODE_FILE=/direct.yaml|AICODEBOX_CRON_MODE_FILE=/direct.yaml CLAUDEBOX_MODE_CRON_FILE=/legacy.yaml"
)

for entry in "${CASES[@]}"; do
    IFS='|' read -r description expected assignments <<<"$entry"
    read -r -a assignment_list <<<"$assignments"
    expect_env "$description" "$expected" "${assignment_list[@]}"
done

if ((failures > 0)); then
    log ERROR "entrypoint alias contract failed failures=$failures"
    exit 1
fi
log INFO "entrypoint alias contract passed"
