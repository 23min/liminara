# Liminara development container
# Provides Elixir + OTP, Python + uv, Node.js for the full project.
#
# Pinned versions — update when Elixir 1.20 stable ships with OTP 27.
# See: https://hub.docker.com/r/hexpm/elixir/tags
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.2.4
ARG DEBIAN_VERSION=bookworm-20250610-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    inotify-tools \
    python3 \
    python3-venv \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Node.js LTS (22.x)
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# uv — Astral package manager for Python
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Hex + Rebar for root (used during image build)
RUN mix local.hex --force && mix local.rebar --force

# Non-root user for VS Code
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Hex + Rebar for vscode user
USER ${USERNAME}
RUN mix local.hex --force && mix local.rebar --force
