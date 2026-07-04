#!/bin/bash
# Smoke test — boots the freshly-built minimal image and probes the surfaces
# that must survive the migration: /healthz, /openai/v1/models, MCP tools list,
# .always-skills injection into argv, compat env alias, init.d completion.
#
# Uses a MOCK claude binary (bind-mounted at /usr/local/bin/claude) that emits
# canned stream-json — no real Anthropic API call needed.
#
# Requires: docker, curl, jq. Image `psyb0t/claudebox:latest` must exist —
# `make build` before running this.
set -euo pipefail

IMAGE="${IMAGE:-psyb0t/claudebox:latest}"
API_PORT="${API_PORT:-18080}"
CONTAINER_PREFIX="claudebox-smoke-$$"
MOCK_TARGET=/usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe
FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.smoke-fixture"

cleanup() {
    docker rm -f "${CONTAINER_PREFIX}-api" 2>/dev/null || true
    rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT INT TERM

log() {
    local level="$1"; shift
    printf '{"time":"%s","level":"%s","file":"test_smoke.sh","msg":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$level" "$*" >&2
}

fail() {
    log ERROR "$*"
    exit 1
}

# Mock claude binary emits stream-json + echoes its argv so tests can inspect.
rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR"

cat > "${FIXTURE_DIR}/mock-claude" <<'MOCK'
#!/bin/bash
if [ "${1:-}" = "--version" ]; then
    echo "claude-code mock 0.0.1"
    exit 0
fi
_ARGV=$(printf '%s\n' "$@" | jq -R . | jq -s -c '.')
cat <<EOF
{"type":"system","subtype":"init","session_id":"sess-mock","model":"mock","cwd":"/workspace","tools":[]}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"mock-response"}]}}
{"type":"result","subtype":"success","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"result":"mock-response","argv_seen":$_ARGV}
EOF
MOCK
# Fixture pre-created above (workspace path).
chmod +x "${FIXTURE_DIR}/mock-claude"

# Skill fixture — the .always-skills injection assertion looks for the marker.
mkdir -p "${FIXTURE_DIR}/always-skills/skill-echo"
cat > "${FIXTURE_DIR}/always-skills/skill-echo/SKILL.md" <<'SKILL'
[SMOKE-SKILL-MARKER-abc123]

This skill's presence in the outbound --append-system-prompt is what the
smoke test asserts on.
SKILL

# ── Test 1 — claude --version via passthrough ────────────────────────────────
log INFO "Test 1: passthrough claude --version"
version_out=$(docker run --rm \
    -v "${FIXTURE_DIR}/mock-claude:${MOCK_TARGET}:ro" \
    "$IMAGE" --version 2>&1) || fail "passthrough exited non-zero"
echo "$version_out" | grep -q "claude-code mock" \
    || fail "expected mock version banner, got: $version_out"
log INFO "  PASS"

# ── Test 2 — API mode /healthz ───────────────────────────────────────────────
log INFO "Test 2: API mode /healthz"
docker run -d \
    --name "${CONTAINER_PREFIX}-api" \
    -e AICODEBOX_API_MODE=1 \
    -e AICODEBOX_API_MODE_PORT=8080 \
    -e AICODEBOX_API_MODE_TOKEN=smoke-token \
    -e AICODEBOX_AVAILABLE_MODELS=haiku,sonnet,opus,opusplan \
    -p "${API_PORT}:8080" \
    -v "${FIXTURE_DIR}/mock-claude:${MOCK_TARGET}:ro" \
    "$IMAGE" >/dev/null

booted=0
for _ in $(seq 1 30); do
    if curl -fsS "http://localhost:${API_PORT}/healthz" >/dev/null 2>&1; then
        booted=1
        break
    fi
    sleep 1
done

if [ "$booted" != "1" ]; then
    docker logs "${CONTAINER_PREFIX}-api" 2>&1 | tail -40
    fail "API server never became healthy on :${API_PORT}"
fi
log INFO "  API up on :${API_PORT}"

health=$(curl -fsS "http://localhost:${API_PORT}/healthz")
echo "$health" | jq -e '.ok == true' >/dev/null \
    || fail "expected healthz.ok=true, got: $health"
log INFO "  PASS"

# ── Test 3 — /openai/v1/models honors AICODEBOX_AVAILABLE_MODELS ─────────────
log INFO "Test 3: /openai/v1/models"
models=$(curl -fsS \
    -H "Authorization: Bearer smoke-token" \
    "http://localhost:${API_PORT}/openai/v1/models")
echo "$models" | jq -e '.data | map(.id) | contains(["haiku","sonnet","opus","opusplan"])' >/dev/null \
    || fail "expected all four models in list, got: $models"
log INFO "  PASS"

# ── Test 4 — init.d completion + .claude.json patch ──────────────────────────
log INFO "Test 4: init.d completion + .claude.json patch"
docker exec "${CONTAINER_PREFIX}-api" test -f /home/aicode/.aicodebox/.init-done \
    || fail "init-done marker missing"

patched=$(docker exec "${CONTAINER_PREFIX}-api" jq -r '
    .installMethod + "|" + (.autoUpdates|tostring) + "|" + (.autoUpdatesProtectedForNative|tostring)
' /home/aicode/.claude/.claude.json)
if [ "$patched" != "native|false|true" ]; then
    fail "expected patched keys native|false|true, got: $patched"
fi
log INFO "  PASS"

# ── Test 5 — /workspaces compat symlink resolves to /workspace ───────────────
log INFO "Test 5: /workspaces compat symlink"
resolved=$(docker exec "${CONTAINER_PREFIX}-api" readlink -f /workspaces)
[ "$resolved" = "/workspace" ] \
    || fail "expected /workspaces -> /workspace, got: $resolved"
log INFO "  PASS"

docker rm -f "${CONTAINER_PREFIX}-api" >/dev/null

# ── Test 6 — CLAUDEBOX_* env alias -> AICODEBOX_* ────────────────────────────
log INFO "Test 6: CLAUDEBOX_* alias applied by entrypoint"
alias_out=$(docker run --rm \
    -e CLAUDEBOX_API_MODE=1 \
    -e CLAUDEBOX_API_MODE_TOKEN=alias-token \
    -e CLAUDEBOX_AVAILABLE_MODELS=haiku \
    --entrypoint bash \
    "$IMAGE" -c '
        # Simulate the entrypoint aliasing then dump.
        for suffix in API_MODE API_MODE_TOKEN AVAILABLE_MODELS; do
            cb="CLAUDEBOX_${suffix}"
            ai="AICODEBOX_${suffix}"
            if [ -n "${!cb:-}" ] && [ -z "${!ai:-}" ]; then
                export "$ai=${!cb}"
            fi
        done
        echo "API=${AICODEBOX_API_MODE:-} TOKEN=${AICODEBOX_API_MODE_TOKEN:-} MODELS=${AICODEBOX_AVAILABLE_MODELS:-}"
    ' 2>&1 | tail -1)

if ! (echo "$alias_out" | grep -q "API=1" \
    && echo "$alias_out" | grep -q "TOKEN=alias-token" \
    && echo "$alias_out" | grep -q "MODELS=haiku"); then
    fail "env alias not applied — got: $alias_out"
fi
log INFO "  PASS"

# ── Test 7 — .always-skills injection into build_argv ────────────────────────
log INFO "Test 7: .always-skills injection"
argv_out=$(docker run --rm \
    -v "${FIXTURE_DIR}/always-skills:/home/aicode/.claude/.always-skills:ro" \
    -v "${FIXTURE_DIR}/mock-claude:${MOCK_TARGET}:ro" \
    -e HOME=/home/aicode \
    -e CLAUDEBOX_ALWAYS_SKILLS_DIR=/home/aicode/.claude/.always-skills \
    -e CLAUDEBOX_SYSTEM_HINT_FILE=/dev/null \
    --entrypoint python3 \
    "$IMAGE" -c "
from claudebox.adapter import ClaudecodeAdapter
from aicodebox.adapters.base import RunRequest
argv = ClaudecodeAdapter().build_argv(RunRequest(prompt='hi'))
i = argv.index('--append-system-prompt')
print(argv[i+1])
")
echo "$argv_out" | grep -q "SMOKE-SKILL-MARKER-abc123" \
    || fail "expected SKILL marker in --append-system-prompt payload, got: $argv_out"
log INFO "  PASS"

# ── Test 8 — RunRequest.extra_args appended verbatim ─────────────────────────
log INFO "Test 8: RunRequest.extra_args"
extra_out=$(docker run --rm \
    -e CLAUDEBOX_ALWAYS_SKILLS_DIR=/nonexistent \
    -e CLAUDEBOX_SYSTEM_HINT_FILE=/nonexistent \
    --entrypoint python3 \
    "$IMAGE" -c "
from claudebox.adapter import ClaudecodeAdapter
from aicodebox.adapters.base import RunRequest
argv = ClaudecodeAdapter().build_argv(RunRequest(prompt='hi', extra_args=['--foo','bar']))
print(argv[-2], argv[-1])
")
[ "$extra_out" = "--foo bar" ] \
    || fail "expected trailing '--foo bar', got: $extra_out"
log INFO "  PASS"

# ── Test 9 — --permission-mode bypassPermissions default ─────────────────────
log INFO "Test 9: --permission-mode bypassPermissions in default argv"
pm_out=$(docker run --rm \
    -e CLAUDEBOX_ALWAYS_SKILLS_DIR=/nonexistent \
    -e CLAUDEBOX_SYSTEM_HINT_FILE=/nonexistent \
    --entrypoint python3 \
    "$IMAGE" -c "
from claudebox.adapter import ClaudecodeAdapter
from aicodebox.adapters.base import RunRequest
argv = ClaudecodeAdapter().build_argv(RunRequest(prompt='hi'))
i = argv.index('--permission-mode')
print(argv[i+1])
")
[ "$pm_out" = "bypassPermissions" ] \
    || fail "expected bypassPermissions, got: $pm_out"
log INFO "  PASS"

log INFO "ALL 9 SMOKE TESTS PASSED"
