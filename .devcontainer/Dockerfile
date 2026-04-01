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
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Node.js LTS (22.x)
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# uv — Astral package manager for Python
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Hex + Rebar for root (used during image build)
RUN mix local.hex --force && mix local.rebar --force

# Non-root user for VS Code
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && chsh -s /bin/zsh ${USERNAME}

# Hex + Rebar for vscode user
USER ${USERNAME}
RUN mix local.hex --force && mix local.rebar --force

# Claude Code CLI (native installer, runs as vscode user)
ENV PATH="/home/vscode/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash
