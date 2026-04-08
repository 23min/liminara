# Devcontainer Operations Guide

How to work safely with the Liminara development container without losing intended local state or accumulating avoidable disk bloat.
Last updated: 2026-04-08.

---

## Purpose

This guide is about the development container used for local work on this repo.

It answers four practical questions:
- what the devcontainer currently does
- what data is intended to survive rebuilds in development
- what data is disposable and safe to clean
- how to rebuild or recover the environment without confusing temporary state for durable state

This is an operations note for local development, not a deployment document.

---

## Current Setup

The devcontainer is defined by:
- `.devcontainer/devcontainer.json`
- `.devcontainer/Dockerfile`
- `.devcontainer/post-create.sh`

### What the container provides

The current image installs:
- Elixir and OTP
- Python 3 and `python3-venv`
- Node.js
- `uv`
- GitHub CLI
- zsh

### What happens after create

The current `postCreateCommand` runs:
- `mix deps.get` in `runtime/`
- `uv sync --extra test` in `runtime/python/`
- `uv sync --extra dev` in `integrations/python/`

That means the container bootstrap currently prepares:
- Elixir umbrella dependencies in `runtime/`
- the standard runtime-managed Python op environment in `runtime/python/`
- the SDK/integration Python environment in `integrations/python/`

It does **not** define every possible Python environment in the repo. Additional Python environments must have explicit ownership and documentation instead of becoming ambient shared repo state.

### Current mounts

The current devcontainer config explicitly mounts only:
- the host Claude config directory into `/home/vscode/.claude`

The workspace itself is provided by the normal VS Code devcontainer workspace mount.

### Python environment ownership in the devcontainer

Python is available in the container as a platform capability, but the repo does not rely on one ambient shared Python environment.

Today:
- `runtime/python/` is the standard runtime-managed Python environment for Python ops
- `integrations/python/` is a separate SDK/integration environment
- additional Python environments must be explicit and documented

---

## Development Persistence Model

### Durable in local development

The intended durable local development data lives inside the workspace, primarily under:

```text
runtime/data/
```

This directory is gitignored and intended for persistent local runtime state.

Today that includes, or should include:
- `runtime/data/store` for artifacts
- `runtime/data/runs` for events, decisions, plans, and run outputs
- `runtime/data/<pack>/...` for pack-owned durable local state

Example:
- Radar semantic history should live under `runtime/data/radar/...`, not in temporary directories or build output.

### Durable because it is in the repo working tree

These also survive container rebuilds because they are in the workspace mount:
- source code
- docs
- configuration files
- git history
- repo-local virtualenvs or generated files that live under the repository

Whether those files are *good design* is separate from whether they survive rebuilds. For example, `_build` survives because it is in the repo tree, but it should not be treated as the canonical home for durable pack state.

### Not currently intended as durable app state

The current container should not rely on durable Liminara state under:
- `/tmp`
- `/var/tmp`
- `/var/lib/liminara`
- `/home/vscode/.cache`
- `runtime/_build/...`

If runtime or pack state lands there, that is drift, not policy.

---

## What We Found In This Container

As of 2026-04-08, the container inspection showed:

### Intended local durable state

- `runtime/data/` exists and is the intended home for local persistent runtime data

### Drift or leftovers

- stale `/tmp/liminara_runs`
- stale `/tmp/liminara_store`
- temporary test or log files in `/tmp`
- historical Radar semantic history found under `runtime/_build/dev/lib/data/radar/lancedb` from the pre-fix path drift

### Rebuildable caches

- `/home/vscode/.cache/huggingface`
- `/home/vscode/.cache/uv`
- `/home/vscode/.cache/pip`
- `/home/vscode/.cache/mix`

These caches may be large, but they are rebuildable. They should not be treated as required durable project state.

---

## Safe Mental Model

Use this rule:

If losing a directory would be a real project problem, it should live in the workspace under an explicitly documented persistent path.

That means:
- keep durable runtime state in `runtime/data/`
- keep durable pack state in `runtime/data/<pack>/...`
- keep source-controlled assets in the repo
- treat caches, tmp files, and build outputs as disposable unless explicitly documented otherwise

---

## Safe To Clean

These are generally safe to delete when reclaiming space or resetting local state:

### Container-local temporary files

- `/tmp/liminara_*`
- `/tmp/radar_*`
- other obvious scratch or test logs in `/tmp`

### User caches

- `/home/vscode/.cache/huggingface`
- `/home/vscode/.cache/uv`
- `/home/vscode/.cache/pip`
- `/home/vscode/.cache/mix`

Deleting them costs time and bandwidth, not correctness. They will be rebuilt or re-downloaded.

### Build artifacts

- `runtime/_build/`
- other language-specific build outputs when you want a clean rebuild

But note the current Radar LanceDB drift: deleting `_build` may also delete semantic history that was written to the wrong place. That is exactly why durable pack paths must be explicit.

---

## Not Safe To Treat As Disposable

Do not casually remove these if you want to preserve local runtime history:

- `runtime/data/store`
- `runtime/data/runs`
- any deliberate pack-owned state under `runtime/data/<pack>/...`

These are local durable development data directories even though they are gitignored.

---

## Rebuild Workflow

### When to rebuild the container

Rebuild when:
- `.devcontainer/Dockerfile` changes
- `.devcontainer/devcontainer.json` changes
- system-level dependencies need to be refreshed cleanly
- the container image becomes inconsistent or bloated

### What a rebuild should not destroy

Because the repo is mounted from the host workspace, a rebuild should not destroy:
- repo files
- git history
- `runtime/data/`
- other repo-local generated state

### What a rebuild will typically reset

- container filesystem state outside the workspace mount
- `/tmp`
- user cache directories if the container is recreated from scratch
- OS-level packages or tools that were installed manually after container creation

### Good rebuild discipline

Before rebuilding:
- confirm any state you care about is inside the repo working tree or another explicit persistent mount
- do not assume `/tmp` or user cache directories matter
- if a pack is currently writing to `_build` or tmp, fix the path rather than treating the accidental location as canonical

---

## Disk Management

### First things to check

If the container feels heavy, check:
- `runtime/data/` for intentional project state
- `runtime/_build/` for build outputs
- `/home/vscode/.cache/` for package and model caches
- `/tmp/` for stale scratch state

### Practical rule

Clean in this order:
1. temporary files in `/tmp`
2. rebuildable caches in `/home/vscode/.cache`
3. build outputs such as `_build`

Only clean `runtime/data/` if you explicitly want to discard local runtime history or pack-owned local data.

---

## .dockerignore

The repo now has a `.dockerignore` file at the workspace root.

That means Docker build context filtering is now explicitly documented and enforced for the repo build context.

The current `.dockerignore` excludes at least these kinds of paths from build context:
- `.git`
- build outputs such as `_build/`, `deps/`, and `node_modules/`
- Python caches and local virtualenvs
- local runtime data under `runtime/data/`
- crash dumps and obvious scratch output

Be careful with `runtime/data/`:
- for local development policy, it is durable state
- for Docker build context, it is not something the image should need

So excluding `runtime/data/` from build context is correct for the current devcontainer image because local durable development data should not be sent into the image build.

---

## Operational Rules

### Rule 1: Durable data must be explicit

If a runtime or pack directory matters, it must live in a declared persistent path in the workspace during development.

### Rule 2: `_build` is not a data home

Compiled output may survive rebuilds because it is in the repo tree, but it is still build output. Do not use it as the canonical location for durable pack data.

### Rule 3: tmp is always disposable

`/tmp` may be useful for tests and scratch work, never as the intended home of durable runtime or pack state.

### Rule 4: caches are performance aids, not truth

Tool caches and model caches can be expensive to recreate, but they are not canonical project data.

### Rule 5: if operators need to keep it, document it

Any directory that matters across rebuilds should be named in repo docs, not discovered by accident.

---

## Current Gaps

This guide reflects current practice, but a few things are still not fully standardized:
- existing local `_build` drift data may still need manual migration or deletion
- not all pack-owned durable paths are standardized under one runtime contract yet

---

## Related Sources

- `.devcontainer/devcontainer.json`
- `.devcontainer/Dockerfile`
- `.devcontainer/post-create.sh`
- `.gitignore`
- `docs/guides/pack_design_and_development.md`
- `work/decisions.md`
- `work/gaps.md`