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
