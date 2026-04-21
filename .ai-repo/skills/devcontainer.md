# Long-form devcontainer reference (archived)

> **This is archived content, not an active framework skill.** The active skill at `.ai/skills/devcontainer.md` is a 40-line generic core. If your repo relies on the detail below (Dockerfile templates, stack-specific blocks, worktree topology), copy the relevant sections into your own `.ai-repo/skills/devcontainer.md` — that file overrides the framework skill for this repo.

---

---
description: Create, maintain, and operate VS Code devcontainers with correct mount topology, worktree support, and persistence guarantees.
name: devcontainer
when_to_use: |
  - When creating a new devcontainer for a project
  - When modifying devcontainer configuration (Dockerfile, mounts, post-create)
  - When setting up or recovering git worktrees inside a devcontainer
  - When diagnosing lost data or mount issues after a container rebuild
  - When a user asks "set up a devcontainer" or "fix the container"
responsibilities:
  - Configure devcontainer.json with correct mount topology
  - Write Dockerfiles with the project's required toolchain
  - Write post-create scripts for dependency setup
  - Set up git worktrees at mount-safe locations
  - Maintain .dockerignore for build context hygiene
  - Diagnose and fix persistence issues across container rebuilds
output:
  - .devcontainer/devcontainer.json
  - .devcontainer/Dockerfile
  - .devcontainer/post-create.sh
  - .dockerignore
  - Working worktree at a rebuild-safe location
invoked_by:
  - builder agent (when devcontainer setup or modification is needed)
  - planner agent (when scoping a new project's infrastructure)
---

# Skill: Devcontainer

Create and maintain VS Code devcontainers that are safe across rebuilds, support git worktrees, and work identically whether accessed locally or via SSH.

## Core Concepts

### Host vs Container

```
Host machine (macOS / Linux)
├── ~/Projects/<repo>/              ← git repo on host disk
├── ~/Projects/worktrees/           ← sibling dir for worktrees (host disk)
├── ~/.claude/                      ← Claude Code config (host disk)
│
└── Docker container
    ├── /workspaces/<repo>/         ← bind-mount of repo
    ├── /workspaces/worktrees/      ← bind-mount of sibling worktrees dir
    ├── /home/vscode/.claude/       ← bind-mount of ~/.claude
    └── everything else             ← EPHEMERAL, lost on rebuild
```

**Rule: anything that must survive a container rebuild must be on a bind mount — either the workspace mount or an explicit additional mount.**

### Persistence classification

| Location | Survives rebuild | Why |
|---|---|---|
| `/workspaces/<repo>/` | yes | workspace bind mount |
| `/workspaces/worktrees/` | yes | explicit bind mount (sibling of repo on host) |
| `/home/vscode/.claude/` | yes | explicit bind mount |
| gitignored files under the workspace | yes | they're on the workspace mount |
| `/home/vscode/.cache/`, `/tmp/`, `_build/` | **no** | container-local filesystem |

## devcontainer.json Template

```jsonc
{
  "name": "<Project Name>",
  "build": {
    "dockerfile": "Dockerfile"
  },
  // Mount the PARENT directory so sibling dirs (worktrees, other repos)
  // are automatically visible inside the container.
  "workspaceFolder": "/workspaces/<repo>",
  "workspaceMount": "source=${localWorkspaceFolder}/..,target=/workspaces,type=bind,consistency=cached",
  // Symlink trick: initializeCommand runs on the HOST where $HOME is
  // always correct. Avoids ${localEnv:HOME} which is unreliable across
  // local vs SSH vs reopened sessions.
  "initializeCommand": "ln -sfn \"$HOME/.claude\" /tmp/.claude-mount",
  "postCreateCommand": "bash .devcontainer/post-create.sh",
  "remoteUser": "vscode",
  "mounts": [
    "source=/tmp/.claude-mount,target=/home/vscode/.claude,type=bind,consistency=cached"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        // Add project-relevant extensions here
        "anthropics.claude-code"
      ]
    }
  }
}
```

### Why this topology

- **`workspaceMount` mounts the parent**: one mount gives access to the repo, worktrees, and any sibling dirs. No need to add explicit mounts for each new worktree or sibling repo.
- **`initializeCommand` symlink for `.claude`**: runs on the host before container creation; `$HOME` is always the host user's home regardless of how VS Code was launched (local, Remote SSH, reopen after restart).
- **No `${localEnv:HOME}`**: this variable is set from VS Code's process environment, which can differ between local, SSH, and background sessions.

## Dockerfile Strategy

### Choosing a base image

Pick the base image based on the project's primary runtime:

| Primary runtime | Base image | Notes |
|---|---|---|
| Python + Node (most projects) | `debian:bookworm-slim` | Install Python, uv, Node yourself — full control |
| Elixir/OTP | `hexpm/elixir:<ver>-erlang-<ver>-debian-bookworm-slim` | Add Python/Node on top |
| .NET | `mcr.microsoft.com/devcontainers/dotnet:<ver>` | Microsoft prebuilt; includes git, sudo, non-root user. Add Python/Node on top |
| Rust | `rust:<ver>-slim-bookworm` | Add Python/Node on top |
| Go | `golang:<ver>-bookworm` | Add Python/Node on top |

When using Microsoft prebuilt images (`mcr.microsoft.com/devcontainers/*`), skip the non-root user setup and Claude Code CLI sections below — those images already provide a `vscode` user and can install tools via features. The common system packages, Python/uv, and Node sections still apply if not already included.

### Dockerfile template (Debian-based)

For non-prebuilt base images, always include:

```dockerfile
# Common system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    sudo \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Node.js LTS (required by most projects for tooling)
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Python via Astral uv (preferred over pip/venv for reproducibility)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# GitHub CLI (for PR workflows)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Non-root user for VS Code
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && chsh -s /bin/zsh ${USERNAME}

USER ${USERNAME}

# Claude Code CLI
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash
```

### Language-specific additions

Add before the non-root user block as needed:

- **Elixir/OTP**: use `hexpm/elixir` as base image, add `mix local.hex --force && mix local.rebar --force` for both root and vscode users
- **.NET**: prefer `mcr.microsoft.com/devcontainers/dotnet` as base image — it includes the SDK, non-root user, and common devcontainer features out of the box. Only add the Python/uv and Node blocks if not already present.
- **Rust**: add `rustup` installation
- **Go**: install from official tarball

## post-create.sh Template

```bash
#!/usr/bin/env bash
set -e
echo "==> Setting up development environment"

# Install language-specific dependencies.
# Use conditional blocks so the script works even if a language dir
# is absent (e.g., in a fresh repo or a trimmed clone).

# Python environments (uv-managed)
for dir in runtime/python integrations/python; do
  if [ -f "$dir/pyproject.toml" ]; then
    echo "==> Installing Python deps in $dir..."
    (cd "$dir" && uv sync)
  fi
done

# Node.js
if [ -f "package.json" ]; then
  echo "==> Installing Node deps..."
  npm install
fi

# Elixir (if present)
if [ -f "mix.exs" ] || [ -d "runtime" ] && [ -f "runtime/mix.exs" ]; then
  echo "==> Installing Elixir deps..."
  (cd runtime 2>/dev/null || true; mix deps.get 2>/dev/null || true)
fi

echo "==> Done."
```

## .dockerignore Template

```
.git
_build/
deps/
node_modules/
__pycache__/
*.pyc
.venv/
.env
.env.*
*.secret
runtime/data/
.claude/worktrees/
```

## Git Worktree Operations

### Creating a worktree

Always create worktrees under the mounted sibling path, never in container-local storage:

```bash
# Good — survives container rebuild
git worktree add /workspaces/worktrees/<name> <branch>

# Bad — lost on rebuild
git worktree add /home/vscode/worktrees/<name> <branch>
git worktree add /tmp/worktrees/<name> <branch>
```

After creating, always init submodules:

```bash
cd /workspaces/worktrees/<name>
git submodule update --init --recursive
```

### Recovering after container rebuild

If the container was rebuilt but the worktree mount survived, git may not know about the worktree (its registration was in `.git/worktrees/` which was re-cloned):

```bash
# Check: does git know about the worktree?
git worktree list

# If the worktree dir exists on disk but git doesn't list it,
# re-add it (git detects existing checkout):
git worktree add /workspaces/worktrees/<name> <branch>
# Then re-init submodules
cd /workspaces/worktrees/<name>
git submodule update --init --recursive
```

### Reviewing worktree code in VS Code

The worktree is at `/workspaces/worktrees/<name>` — outside the VS Code workspace root. Options for reviewing:

1. **Second VS Code window** (recommended): Attach to the running container, open `/workspaces/worktrees/<name>` as workspace. Full explorer, search, git — no search pollution in the main workspace.
2. **Open individual files**: from the integrated terminal, `code /workspaces/worktrees/<name>/path/to/file` opens it in the current editor.
3. **Terminal review**: use `git diff`, `less`, `bat` in the integrated terminal.

Do NOT put the worktree inside the main workspace — it duplicates the entire repo tree and pollutes search.

## Operational Rules

1. **Durable data must be on a bind mount.** If losing a directory on rebuild is a problem, it must live under the workspace mount or an explicit additional mount.
2. **`_build`, `/tmp`, caches are always disposable.** They may survive some rebuilds by accident (they're under the workspace mount if inside the repo tree), but they are not canonical data homes.
3. **Caches are performance aids, not truth.** `/home/vscode/.cache/` (uv, pip, huggingface, mix) is rebuildable. Expensive to re-download, but not project state.
4. **One container per project.** If you see multiple containers for the same project, the older one is stale. Stop and remove it.
5. **Worktrees go in `/workspaces/worktrees/`.** The parent-dir mount makes this path automatically available. Submodules must be re-initialized after worktree creation.

## Safe To Clean

| What | Where | Safe? |
|---|---|---|
| Container-local temp files | `/tmp/*` | always safe |
| Tool caches | `/home/vscode/.cache/` | safe (costs re-download time) |
| Build artifacts | `_build/`, `node_modules/`, `.venv/` | safe (costs rebuild time) |
| Runtime data | `runtime/data/` (or project equivalent) | **not safe** — this is durable local state |
| Git worktrees | `/workspaces/worktrees/` | **not safe** — contains work in progress |
