---
id: M-EE-04-cache
epic: E-06-execution-engine
status: complete
---

# M-EE-04: Cache

## Goal

Implement `Liminara.Cache` — an ETS-based memoization layer that caches op outputs by a deterministic cache key. The cache integrates with `Run.Server` so that pure ops with identical inputs skip re-execution.

## Acceptance criteria

### Module: `Liminara.Cache`

- [x] `Cache.start_link(opts)` — starts the cache (owns an ETS table)
- [x] `Cache.lookup(cache, op_module, input_hashes)` → `{:hit, output_hashes}` or `:miss`
- [x] `Cache.store(cache, op_module, input_hashes, output_hashes)` → `:ok`
- [x] `Cache.clear(cache)` → `:ok` — clears all entries (for testing)

### Cache key computation

- [x] `cache_key = sha256(canonical_json({op_name, op_version, sorted_input_hashes}))`
- [x] Input hashes are sorted lexicographically by input name for determinism
- [x] Same op + same inputs → same cache key, always

### Determinism-based caching

- [x] `:pure` ops — always check cache before dispatch, store on miss
- [x] `:pinned_env` ops — check cache (env hash included in key, deferred — treat as pure for now)
- [x] `:recordable` ops — never cached, always execute
- [x] `:side_effecting` ops — never cached, always execute

### Integration with Run.Server

- [x] Run.Server checks cache before dispatching a `:pure` op
- [x] On cache hit: emits `op_completed` with `cache_hit: true`, does not call executor
- [x] On cache miss: executes normally, stores result in cache
- [x] Second run of same plan with same inputs: pure ops hit cache
- [x] Recordable ops execute every time regardless of cache

### Cache properties

- [x] ETS-based (in-memory, fast)
- [x] Lost on restart (by design — rebuilt as runs re-execute)
- [x] Concurrent-safe (ETS with `:public` or `:protected` access)

## Tests

### `test/liminara/cache_test.exs`

**Lookup and store:**
- Miss on empty cache
- Store then lookup → hit with correct output_hashes
- Different op/inputs → miss
- Same op, different inputs → miss

**Cache key:**
- Same op + inputs produces same key
- Different inputs produce different keys
- Input hash order doesn't matter (sorted internally)

### `test/liminara/run/cached_run_test.exs`

**Cache integration:**
- Run a plan with pure ops → all cache misses
- Run the same plan again → pure ops are cache hits
- `op_completed` events show `cache_hit: true` on second run
- Recordable op in the plan → never cached, executes both times
- Artifacts from cache hit are still valid (retrievable from artifact store)

## TDD sequence

1. **Test agent** reads this spec, writes `cache_test.exs` and `run/cached_run_test.exs`. All tests fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, implements `Liminara.Cache` and integrates with Run.Server until all tests pass (green).
4. Human reviews implementation.
5. Validation pipeline.

## Out of scope

- Cache eviction / TTL
- Persistent cache (survives restart)
- `pinned_env` environment hashing (treat as pure for walking skeleton)
- Cache size limits
- Cache warming / preloading

## Spec reference

- `docs/architecture/01_CORE.md` § Caching = memoization
