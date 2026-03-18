---
id: M-SL-01-artifact-store
epic: E-05-storage-layer
status: done
---

# M-SL-01: Artifact Store

## Goal

Implement `Liminara.Artifact.Store` — a pure functional module for content-addressed blob storage on the filesystem. Artifacts are stored in Git-style sharded directories and identified by their SHA-256 hash. The module must produce files byte-identical to the Python SDK's `ArtifactStore`.

## Acceptance criteria

### Module: `Liminara.Artifact.Store`

- [x] `put(store_root, content)` → `{:ok, hash}` where hash is `"sha256:{64 hex}"` and content is written to disk
- [x] `get(store_root, hash)` → `{:ok, binary}` or `{:error, :not_found}`
- [x] `exists?(store_root, hash)` → boolean
- [x] Content hash is `sha256(raw_bytes)` using `Liminara.Hash.hash_bytes/1`

### Directory sharding

- [x] Blobs stored at `{store_root}/{hex[0:2]}/{hex[2:4]}/{hex}` (Git-style)
- [x] Parent directories created automatically on write
- [x] Hash prefix stripped: path uses the 64-char hex portion, not the `sha256:` prefix

### Write-once semantics

- [x] Writing the same content twice is idempotent (no error, one file on disk)
- [x] Writing different content that happens to produce the same hash (impossible in practice) would not overwrite
- [x] Existing file check before write (don't re-write if blob exists)

### Golden fixture validation

- [x] Can read both golden fixture artifacts from `test_fixtures/golden_run/artifacts/`
- [x] Content hash of each artifact matches its path
- [x] Round-trip: write content, read it back, bytes are identical

### Error handling

- [x] `get/2` with non-existent hash returns `{:error, :not_found}`
- [x] `put/2` with empty binary succeeds (empty artifacts are valid)

## Tests

### `test/liminara/artifact/store_test.exs`

**Round-trip:**
- `put` returns a `sha256:{hex}` hash
- `get` with that hash returns the original bytes
- Multiple different artifacts each stored correctly

**Idempotency:**
- `put` same content twice → same hash, single file on disk
- File count in store_root doesn't increase on duplicate write

**Sharding:**
- File path matches `{store_root}/{hex[0:2]}/{hex[2:4]}/{hex}` pattern
- Known content produces known path (use golden fixture hashes)

**Golden fixtures:**
- Read artifact 1 (JSON documents blob) from `test_fixtures/golden_run/artifacts/`
- Read artifact 2 (text summary blob) from `test_fixtures/golden_run/artifacts/`
- Content hash matches expected hash for each

**Edge cases:**
- Empty content: put succeeds, get returns empty binary
- Non-existent hash: `get` returns `{:error, :not_found}`
- `exists?` returns true after put, false for unknown hash

## TDD sequence

1. **Test agent** reads this spec, writes `artifact/store_test.exs`. All tests fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, implements `Liminara.Artifact.Store` until all tests pass (green).
4. Human reviews implementation.
5. Validation pipeline: `mix format --check-formatted && mix credo && mix dialyzer && mix test`

## Out of scope

- GenServer wrapping (stores are plain modules — process management is E-06)
- ETS metadata table (defer to E-06)
- Streaming reads for large files
- Garbage collection / deletion
- Store-root configuration (callers pass `store_root` explicitly)

## Spec reference

- `docs/analysis/11_Data_Model_Spec.md` § Artifact Storage
- `integrations/python/liminara/artifact_store.py` — reference implementation
- `runtime/apps/liminara_core/lib/liminara/hash.ex` — `hash_bytes/1`
