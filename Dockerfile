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
ARG BASE_IMAGE=psyb0t/aicodebox:latest
FROM ${BASE_IMAGE}

USER root

# claude-code CLI — pinned npm global install. Runs as npm root so it lands on
# a shared PATH for both root (init.d) and the aicode user (mode dispatchers).
ARG CLAUDE_VERSION=2.1.197
RUN npm install -g --no-audit --no-fund @anthropic-ai/claude-code@${CLAUDE_VERSION}

# claudebox python package (ClaudecodeAdapter). aicodebox already exists in the
# base's system Python, so --no-deps skips redundant resolution.
COPY claudebox /opt/claudebox
RUN uv pip install --system --break-system-packages --no-deps /opt/claudebox

# First-run init scripts — base runs each once, marks completion at
# ~/.aicodebox/.init-done, then skips on subsequent boots.
COPY claudebox/init.d/ /aicodebox-init.d/
RUN chmod +x /aicodebox-init.d/*.sh

# Adapter selection — the modes resolve this at runtime.
ENV AICODEBOX_ADAPTER=claudebox.adapter:ClaudecodeAdapter \
    AICODEBOX_AGENT_BINARY=claude \
    DISABLE_AUTOUPDATER=1 \
    CLAUDEBOX_IMAGE_VARIANT=minimal

# claudebox-branded entrypoint: aliases CLAUDEBOX_* / legacy CLAUDE_MODE_* env
# vars to their AICODEBOX_* equivalents, sets up compat symlinks, then exec's
# the base entrypoint.
COPY claudebox-entrypoint.sh /usr/local/bin/claudebox-entrypoint
RUN chmod +x /usr/local/bin/claudebox-entrypoint

ENTRYPOINT ["/usr/local/bin/claudebox-entrypoint"]
