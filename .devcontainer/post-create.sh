#!/usr/bin/env bash
# Runs after the devcontainer is created.
# Installs project dependencies for both Elixir and Python.
set -e

echo "==> Setting up Liminara development environment"

# Correct the gh credential helper path. The devcontainers github-cli
# feature hardcodes /usr/local/bin/gh, but gh may live elsewhere
# (/usr/bin/gh on this image). Rewrite to bare `gh` so PATH resolves it.
# ~/.gitconfig isn't host-mounted, so this must re-run on every rebuild.
echo "==> Fixing gh credential helper path..."
for host in https://github.com https://gist.github.com; do
  git config --global --unset-all "credential.${host}.helper" 2>/dev/null || true
  git config --global --add "credential.${host}.helper" ""
  git config --global --add "credential.${host}.helper" "!gh auth git-credential"
done

# Elixir dependencies (runtime/ is the umbrella project)
if [ -d runtime ]; then
  echo "==> Installing Elixir dependencies..."
  cd runtime
  mix deps.get
  cd ..
fi

# Runtime Python ops environment (runtime/python/ uses uv)
if [ -d runtime/python ]; then
  echo "==> Installing runtime Python op environment..."
  cd runtime/python
  uv sync --extra test
  cd ../..
fi

# Python SDK/integration environment (integrations/python/ uses uv)
if [ -d integrations/python ]; then
  echo "==> Installing Python SDK/integration environment..."
  cd integrations/python
  uv sync --extra dev
  cd ../..
fi

echo "==> Done. Happy hacking!"
