IMAGE_NAME := psyb0t/claudebox
PKG        := claudebox
# Single-source version derivation: claudebox/pyproject.toml [project] version
# is THE truth. Override at build time: `VERSION=2.0.0-rc1 make build`.
VERSION    ?= $(shell awk -F\" '/^version *= *"/ {print $$2; exit}' claudebox/pyproject.toml)
TAG        := v$(VERSION)
# Default to the published aicodebox base (keep in sync with the
# ARG default in Dockerfile). Override with `make build BASE_IMAGE=...` to point
# at a locally-built base image.
BASE_IMAGE ?= psyb0t/aicodebox:latest
FULL_BASE_IMAGE ?= psyb0t/aicodebox:latest-full
CLAUDE_VERSION ?= 2.1.296

# Lint, CI tests and the docs build run in containers, so the host needs only
# Docker, Make and Git. DEV_IMAGE is built from Dockerfile.dev on BASE_IMAGE.
DEV_IMAGE        ?= claudebox-dev:local
SHELLCHECK_IMAGE ?= koalaman/shellcheck:v0.11.0
SHFMT_IMAGE      ?= mvdan/shfmt:v3.14.1
JEKYLL_IMAGE     ?= ghcr.io/actions/jekyll-build-pages:v1.0.13@sha256:6791ebfd912185ed59bfb5fb102664fa872496b79f87ff8b9cfba292a7345041
DOCS_SITE        ?= .testing/docs-site
SHFMT_FLAGS      := -i 4 -ci
SHELL_FILES      := $(shell git ls-files '*.sh' 2>/dev/null)

# The repository is mounted read-only at its own path. The Docker variant also
# gets the host Docker socket, and the same path keeps the bind mounts those
# tests create valid on the host.
DEV_RUN        := docker run --rm --network none -v "$(CURDIR):$(CURDIR):ro" -w "$(CURDIR)" $(DEV_IMAGE)
DEV_RUN_DOCKER := docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$(CURDIR):$(CURDIR):ro" -w "$(CURDIR)" -e BASE_IMAGE=$(BASE_IMAGE) $(DEV_IMAGE)

.PHONY: all build build-full build-all pull-base pull-full-base test test-unit test-smoke test-persist test-image-select test-agent-launcher test-managed-nested test-cron-shortcut test-entrypoint-aliases clean help version pkg-lock dev-image lint format test-ci docs

all: build ## Build the minimal claudebox image on top of the published base

V ?=
export V
version: ## Print or synchronize version metadata without committing: make version V=X.Y.Z
	@set -eu; \
	if [ -z "$$V" ]; then printf '%s\n' "$(TAG)"; exit 0; fi; \
	printf '%s\n' "$$V" | LC_ALL=C grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$$' || { echo "V must be semver X.Y.Z" >&2; exit 1; }; \
	(cd $(PKG) && uv version --no-sync "$$V"); \
	tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT; \
	jq --arg v "$$V" '.version=$$v' .agents/.codex-plugin/plugin.json >"$$tmp"; \
	mv "$$tmp" .agents/.codex-plugin/plugin.json; \
	tmp=$$(mktemp); \
	sed -E "s|^readonly CLAUDEBOX_RELEASE_REF=.*|readonly CLAUDEBOX_RELEASE_REF=\"v$$V\"|" install.sh >"$$tmp"; \
	chmod 755 "$$tmp"; \
	mv "$$tmp" install.sh

.PHONY: test-entrypoint-identity
test-entrypoint-identity: ## Verify Git identity aliases against the shared container entrypoint
	bash tests/test_entrypoint_identity.sh

pkg-lock: ## Refresh the Python lockfile under the current dependency pins
	cd claudebox && uv lock

pull-base: ## Pull the aicodebox base image (SKIP_BASE_PULL=1 to use a locally-built base)
	@if [ "$${SKIP_BASE_PULL:-0}" = "1" ]; then \
		echo "[make] SKIP_BASE_PULL=1, using local $(BASE_IMAGE)"; \
		docker image inspect $(BASE_IMAGE) >/dev/null 2>&1 \
			|| { echo "❌ SKIP_BASE_PULL=1 but $(BASE_IMAGE) not found locally" >&2; exit 1; }; \
	else \
		docker pull $(BASE_IMAGE); \
	fi

pull-full-base: ## Pull the full aicodebox base image (SKIP_BASE_PULL=1 for a local image)
	@if [ "$${SKIP_BASE_PULL:-0}" = "1" ]; then \
		echo "[make] SKIP_BASE_PULL=1, using local $(FULL_BASE_IMAGE)"; \
		docker image inspect $(FULL_BASE_IMAGE) >/dev/null 2>&1 \
			|| { echo "full base image not found: $(FULL_BASE_IMAGE)" >&2; exit 1; }; \
	else \
		docker pull $(FULL_BASE_IMAGE); \
	fi

build: pull-base ## Build + tag the minimal image (both :v<VERSION> and :latest)
	docker build \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg CLAUDE_VERSION=$(CLAUDE_VERSION) \
		-t $(IMAGE_NAME):$(TAG) \
		-t $(IMAGE_NAME):latest \
		.

build-full: pull-full-base ## Build the full variant on top of aicodebox full
	docker build \
		-f Dockerfile.full \
		--build-arg BASE_IMAGE=$(FULL_BASE_IMAGE) \
		--build-arg CLAUDE_VERSION=$(CLAUDE_VERSION) \
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

.PHONY: test-programmatic-contract
test-programmatic-contract: ## Check native CLI output assertions without provider credentials
	bash tests/programmatic/check-contract.sh

.PHONY: test-install-output
test-install-output: ## Check first-start installation output in disposable containers
	bash tests/programmatic/check-install-output.sh

test-agent-launcher: ## Assert claudebox-agent.sh restores interactive defaults (--continue/skip-permissions/markers); no build needed
	bash tests/test_agent_launcher.sh

test-managed-nested: ## Verify managed install and nested wrapper propagation without Docker
	bash tests/test_managed_nested.sh

test-cron-shortcut: ## Assert the wrapper's cron shortcut passes the canonical cron env names; no build needed
	bash tests/test_cron_shortcut.sh

test-entrypoint-aliases: ## Assert the entrypoint maps every claudebox mode env name to AICODEBOX_*; needs docker, no build
	bash tests/test_entrypoint_aliases.sh

test: test-unit test-programmatic-contract test-install-output ## Run adapter, programmatic, and first-start output tests

dev-image: ## Build the lint and CI test image from Dockerfile.dev
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(DEV_IMAGE) - <Dockerfile.dev

lint: dev-image ## Lint shell (shellcheck, shfmt) and Python (ruff, pyright) in containers
	docker run --rm -v "$(CURDIR):/src:ro" -w /src $(SHELLCHECK_IMAGE) --severity=warning $(SHELL_FILES)
	docker run --rm -v "$(CURDIR):/src:ro" -w /src $(SHFMT_IMAGE) $(SHFMT_FLAGS) -d $(SHELL_FILES)
	$(DEV_RUN) bash -c 'cd claudebox && ruff check --no-cache . && ruff format --no-cache --check . && pyright'

format: dev-image ## Rewrite shell and Python sources with shfmt and ruff format
	docker run --rm --user "$$(id -u):$$(id -g)" -v "$(CURDIR):/src" -w /src $(SHFMT_IMAGE) $(SHFMT_FLAGS) -w $(SHELL_FILES)
	docker run --rm --network none --user "$$(id -u):$$(id -g)" -e HOME=/tmp -v "$(CURDIR):/src" -w /src/claudebox $(DEV_IMAGE) ruff format --no-cache .

test-ci: dev-image ## Run the credential-free tests CI runs: adapter, wrapper, launcher, entrypoint
	$(DEV_RUN) bash -c 'cd claudebox && python3 -m pytest -p no:cacheprovider tests'
	$(DEV_RUN) bash tests/programmatic/check-contract.sh
	$(DEV_RUN) bash tests/test_image_select.sh
	$(DEV_RUN) bash tests/test_agent_launcher.sh
	$(DEV_RUN) bash tests/test_managed_nested.sh
	$(DEV_RUN) bash tests/test_cron_shortcut.sh
	$(DEV_RUN_DOCKER) bash tests/programmatic/check-install-output.sh
	$(DEV_RUN_DOCKER) bash tests/test_entrypoint_aliases.sh
	$(DEV_RUN_DOCKER) bash tests/test_entrypoint_identity.sh

# Builds with the image GitHub Pages uses, so the output matches the published
# site. The output directory is gitignored.
docs: ## Build the documentation site into .testing/docs-site
	@mkdir -p "$(DOCS_SITE)"
	docker run --rm \
		--user "$$(id -u):$$(id -g)" \
		-e HOME=/tmp \
		-e GITHUB_WORKSPACE=/work \
		-e GITHUB_REPOSITORY=psyb0t/docker-claudebox \
		-e INPUT_SOURCE=docs \
		-e INPUT_DESTINATION="$(DOCS_SITE)" \
		-e INPUT_VERBOSE=false \
		-v "$(CURDIR):/work" \
		$(JEKYLL_IMAGE)

clean: ## Remove built images (keeps the aicodebox base)
	docker rmi $(IMAGE_NAME):$(TAG) 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	docker rmi $(IMAGE_NAME):$(TAG)-full 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest-full 2>/dev/null || true

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
