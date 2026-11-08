# syntax=docker/dockerfile:1
#
# claude-box: Claude Code CLI in a container that only sees the folders you mount.
#
# Build (from an otherwise empty directory, so the build context stays tiny):
#   docker build -t claude-box .
#
#   UID/GID default to 1000:1000. On a machine where `id -u`/`id -g` differ, add:
#     --build-arg UID="$(id -u)" --build-arg GID="$(id -g)"
#
# Optional build args:
#   CLAUDE_VERSION=stable|latest|<x.y.z>   release channel or exact version (default: stable)
#   WITH_JAVA=1                            add a headless JDK + Maven (Spring Boot projects)
#   WITH_NODE=1                            add Node.js + npm
#
# Run (one project, read-write, mounted at the same path as on the host):
#   docker run --rm -it --init \
#     --cap-drop ALL --security-opt no-new-privileges \
#     --read-only --tmpfs /tmp --tmpfs /home/claude/.cache \
#     -e CLAUDE_CODE_OAUTH_TOKEN \
#     -v claude-config:/home/claude/.claude \
#     --mount type=bind,src="$PWD",dst="$PWD" -w "$PWD" \
#     claude-box
#
#   Extra folders: one --mount per folder; add ",readonly" for read-only access.
#   Anything after the image name is passed to claude (e.g. --dangerously-skip-permissions).
#   Shell instead of claude: add --entrypoint bash before the image name.

FROM debian:trixie-slim

ARG UID=1000
ARG GID=1000
ARG CLAUDE_VERSION=stable
ARG WITH_JAVA=0
ARG WITH_NODE=0

# Fail a RUN step if any command in a pipe fails (matters for curl | bash).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base tools Claude uses to inspect and change code. No sudo on purpose.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      less \
      procps \
      ripgrep \
 && if [ "${WITH_JAVA}" = "1" ]; then \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        default-jdk-headless maven; \
    fi \
 && if [ "${WITH_NODE}" = "1" ]; then \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs npm; \
    fi \
 && rm -rf /var/lib/apt/lists/*

# Non-root user with the same UID/GID as your host user, so files Claude
# creates in bind mounts are owned by you (and git doesn't flag "dubious ownership").
RUN getent group "${GID}" >/dev/null || groupadd --gid "${GID}" claude \
 && useradd --uid "${UID}" --gid "${GID}" --create-home --shell /bin/bash claude \
 && mkdir -p /workspace \
 && chown "${UID}:${GID}" /workspace

USER claude
WORKDIR /home/claude

# CLAUDE_CONFIG_DIR keeps both ~/.claude and .claude.json (OAuth account,
# per-project trust) in one directory, so a single volume persists all state.
# Updates come from rebuilding the image, not from self-updating at runtime.
ENV PATH="/home/claude/.local/bin:${PATH}" \
    CLAUDE_CONFIG_DIR="/home/claude/.claude" \
    DISABLE_AUTOUPDATER=1 \
    LANG=C.UTF-8
# Optional: also turn off telemetry/error reporting (disables a few features).
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Native installer (npm install is deprecated). Binary: ~/.local/bin/claude.
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_VERSION}" \
 && claude --version

# Pre-create the config dir owned by the user, and skip the first-run onboarding
# wizard (it otherwise shows in containers even with a valid token).
# A new named volume mounted here starts as a copy of this directory.
RUN mkdir -p "${CLAUDE_CONFIG_DIR}" \
 && cfg="${CLAUDE_CONFIG_DIR}/.claude.json" \
 && if [ -f "${cfg}" ]; then \
      jq '. + {hasCompletedOnboarding: true}' "${cfg}" > "${cfg}.tmp" && mv "${cfg}.tmp" "${cfg}"; \
    else \
      echo '{"hasCompletedOnboarding": true}' > "${cfg}"; \
    fi

WORKDIR /workspace

ENTRYPOINT ["claude"]
