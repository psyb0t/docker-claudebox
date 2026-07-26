# claudebox — Claude Code on the aicodebox base.
#
# Build (base lives in ../docker-aicodebox):
#   docker build -t aicodebox-base:local ../docker-aicodebox/
#   docker build --build-arg BASE_IMAGE=aicodebox-base:local -t claudebox:local .
#
# Minimal variant. The toolchain-loaded `full` variant lives in Dockerfile.full
# and layers on top of the image this file produces.
#
# NOTE on hardening: the base sets `aicode` (UID 1000) as its runtime user via
# `setpriv` inside `aicodebox-entrypoint`. This Dockerfile switches to root
# only for the install steps below; runtime drops back to aicode automatically.
ARG BASE_IMAGE=psyb0t/aicodebox:v0.14.0@sha256:543aec8bf85ebc8a0689c4746d4c9e2ede65599decb50827593db0b3c65bd2a5
FROM ${BASE_IMAGE}

USER root

# claude-code CLI — NOT baked into this image. Anthropic's Claude Code is
# proprietary ("© Anthropic PBC. All rights reserved", Anthropic Commercial
# Terms) with no redistribution grant, so this published image must not ship
# it. Instead we pin the version here and the entrypoint installs it (npm
# global, on the same shared PATH as before) on first container start if it
# isn't already present — so each user's own container fetches it from npm at
# runtime rather than us redistributing Anthropic's software.
ARG CLAUDE_VERSION=2.1.220
ENV CLAUDEBOX_CLAUDE_VERSION=${CLAUDE_VERSION}

# claudebox python package (ClaudecodeAdapter). aicodebox already exists in the
# base's system Python, so --no-deps skips redundant resolution.
COPY claudebox /opt/claudebox
RUN uv pip install --system --break-system-packages --no-deps /opt/claudebox

# First-run init scripts — base runs each once, marks completion at
# ~/.aicodebox/.init-done, then skips on subsequent boots.
COPY claudebox/init.d/ /aicodebox-init.d/
RUN chmod +x /aicodebox-init.d/*.sh

# Adapter selection — the modes resolve this at runtime.
#
# CLAUDE_CONFIG_DIR points Claude Code at the bind-mounted ~/.claude dir so
# .claude.json (theme, onboarding, oauthAccount) + credentials live ON the
# mount and PERSIST across container recreates — otherwise Claude Code
# writes them to $HOME/.claude.json (unmounted) and re-onboards (theme +
# login) on every run. Only claudebox knows the payload is Claude Code, so
# only claudebox can set this (the aicodebox base is agent-agnostic).
# AICODEBOX_AGENT_BINARY points the base's passthrough (`exec $AGENT_BINARY
# "$@"`) at the claudebox launcher instead of `claude` directly. The launcher
# restores the interactive/one-shot defaults the agent-agnostic base dropped:
# --continue (resume) with fallback, --permission-mode bypassPermissions, and the
# system-hint + always-skills --append-system-prompt. Server modes build argv via
# the adapter (hardcoded "claude") and never go through the launcher.
ENV AICODEBOX_ADAPTER=claudebox.adapter:ClaudecodeAdapter \
    AICODEBOX_AGENT_BINARY=claudebox-agent \
    DISABLE_AUTOUPDATER=1 \
    CLAUDEBOX_IMAGE_VARIANT=minimal \
    CLAUDE_CONFIG_DIR=/home/aicode/.claude

# claudebox agent launcher (see claudebox-agent.sh header for the full rationale).
COPY claudebox-agent.sh /usr/local/bin/claudebox-agent
RUN chmod +x /usr/local/bin/claudebox-agent

# claudebox-branded entrypoint: aliases CLAUDEBOX_* / legacy CLAUDE_MODE_* env
# vars to their AICODEBOX_* equivalents, sets up compat symlinks, then exec's
# the base entrypoint.
COPY claudebox-entrypoint.sh /usr/local/bin/claudebox-entrypoint
RUN chmod +x /usr/local/bin/claudebox-entrypoint

ENTRYPOINT ["/usr/local/bin/claudebox-entrypoint"]
