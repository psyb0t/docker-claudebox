IMAGE_NAME := psyb0t/claudebox
PKG        := claudebox
# Single-source version derivation — claudebox/pyproject.toml [project] version
# is THE truth. Override at build time: `VERSION=2.0.0-rc1 make build`.
VERSION    ?= $(shell awk -F\" '/^version *= *"/ {print $$2; exit}' claudebox/pyproject.toml)
TAG        := v$(VERSION)
# Default to the published aicodebox base, digest-pinned (keep in sync with the
# ARG default in Dockerfile) — override with `make build BASE_IMAGE=...` to point
# at a locally-built base image.
BASE_IMAGE ?= psyb0t/aicodebox:v0.14.8@sha256:3f28a053b88d9989698444c0f3d372b5ec6865df1eacb3ae11333245876a0b51
CLAUDE_VERSION ?= 2.1.251

.PHONY: all build build-full build-all pull-base test test-unit test-smoke test-persist test-image-select test-agent-launcher clean help version pkg-lock

all: build ## Build the minimal claudebox image on top of the published base

version: ## Print version, or set-everywhere+commit+tag: make version V=X.Y.Z
ifeq ($(strip $(V)),)
	@echo $(TAG)
else
	@echo "$(V)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$$' || { echo "V must be semver (X.Y.Z), got '$(V)'" >&2; exit 1; }
	@set -e; old="$(VERSION)"; \
	( cd $(PKG) && uv version "$(V)" >/dev/null ); \
	tmp=$$(mktemp); jq --arg v "$(V)" '.version=$$v' .agents/.codex-plugin/plugin.json >"$$tmp" && mv "$$tmp" .agents/.codex-plugin/plugin.json; \
	git add $(PKG)/pyproject.toml $(PKG)/uv.lock .agents/.codex-plugin/plugin.json; \
	git commit -q -m "v$(V)"; \
	git tag -a "v$(V)" -m "$(PKG) v$(V)"; \
	echo "[make version] v$$old -> v$(V): bumped pyproject+uv.lock+codex-manifest, committed, tagged"; \
	if git --no-pager grep -In -e "$$old" -- ':!CHANGELOG.md' ':!uv.lock' ':!*server.json' ':!*package.json' >/dev/null 2>&1; then \
		echo "⚠ v$$old still appears in tracked files make version does not manage — check for a missed version location:" >&2; \
		git --no-pager grep -In -e "$$old" -- ':!CHANGELOG.md' ':!uv.lock' ':!*server.json' ':!*package.json' >&2; \
	fi
endif

pkg-lock: ## Refresh the Python lockfile under the current dependency pins
	cd claudebox && uv lock

pull-base: ## Pull the aicodebox base image (SKIP_BASE_PULL=1 to use a locally-built base)
	@if [ "$${SKIP_BASE_PULL:-0}" = "1" ]; then \
		echo "[make] SKIP_BASE_PULL=1 — using local $(BASE_IMAGE)"; \
		docker image inspect $(BASE_IMAGE) >/dev/null 2>&1 \
			|| { echo "❌ SKIP_BASE_PULL=1 but $(BASE_IMAGE) not found locally" >&2; exit 1; }; \
	else \
		docker pull $(BASE_IMAGE); \
	fi

build: pull-base ## Build + tag the minimal image (both :v<VERSION> and :latest)
	docker build \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg CLAUDE_VERSION=$(CLAUDE_VERSION) \
		-t $(IMAGE_NAME):$(TAG) \
		-t $(IMAGE_NAME):latest \
		.

build-full: build ## Build the toolchain-loaded variant on top of the minimal
	docker build \
		-f Dockerfile.full \
		--build-arg BASE_IMAGE=$(IMAGE_NAME):latest \
		-t $(IMAGE_NAME):$(TAG)-full \
		-t $(IMAGE_NAME):latest-full \
		.

build-all: build build-full ## Build both minimal and full variants

test-unit: ## Run in-process adapter unit tests (no docker required)
	cd claudebox && uv run --frozen python -m pytest tests/ -v

test-smoke: build ## Boot the minimal image + probe endpoints
	bash tests/test_smoke.sh

test-persist: build ## Assert .claude.json (theme/login/onboarding) persists on the bind-mounted ~/.claude
	IMAGE=$(IMAGE_NAME):latest bash tests/test_persist.sh

test-image-select: ## Assert wrapper.sh resolves the right image (CLAUDEBOX_FULL/MINIMAL/override); no build needed
	bash tests/test_image_select.sh

test-agent-launcher: ## Assert claudebox-agent.sh restores interactive defaults (--continue/skip-permissions/markers); no build needed
	bash tests/test_agent_launcher.sh

test: test-unit ## Alias for test-unit

clean: ## Remove built images (keeps the aicodebox base)
	docker rmi $(IMAGE_NAME):$(TAG) 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	docker rmi $(IMAGE_NAME):$(TAG)-full 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest-full 2>/dev/null || true

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
