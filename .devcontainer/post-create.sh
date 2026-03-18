#!/usr/bin/env bash
# Runs after the devcontainer is created.
# Installs project dependencies for both Elixir and Python.
set -e

echo "==> Setting up Liminara development environment"

# Elixir dependencies (runtime/ is the umbrella project)
if [ -d runtime ]; then
  echo "==> Installing Elixir dependencies..."
  cd runtime
  mix deps.get
  cd ..
fi

# Python dependencies (integrations/python/ uses uv)
if [ -d integrations/python ]; then
  echo "==> Installing Python dependencies..."
  cd integrations/python
  uv sync
  cd ../..
fi

echo "==> Done. Happy hacking!"
