# Artifact Store Design: Lessons from Existing Systems

**Date:** 2026-03-02
**Context:** Supporting research for Liminara core runtime analysis

---

## Existing Systems with Content-Addressed Artifacts

### AiiDA (closest to Liminara's model)

- Full DAG provenance graph: every calculation and its inputs/outputs are nodes
- Content-addressable data nodes (immutable)
- Cache key: `hash(code_version + input_hashes)` -> reuse stored outputs
- Storage: Postgres + file repository
- Scale: millions of calculation nodes in production materials science labs
- **Key lesson:** Provenance graph queries get expensive at scale. AiiDA built a custom query builder. Plan for this.

### Bazel (cleanest architecture)

- **CAS (Content-Addressable Storage):** blob store addressed by SHA-256 hash
- **Action cache:** maps `hash(command + input_hashes + env)` to output hashes
- Clean separation: the action cache enables cache hits, the CAS is just blob storage
- Scale: billions of actions at Google
- **Key lesson:** Separate "what is stored" (CAS) from "how to find it" (action cache). This maps to Liminara's `artifacts` table (CAS) vs `run_nodes` table (action cache).

### Nix (cautionary tale about content addressing)

- Historically input-addressed (hash the recipe). Migrating to content-addressed (hash the output).
- Content-addressed mode has taken years to stabilize — significant complexity around "realisations", trust models, and self-references.
- GC works via explicit GC roots + reachability traversal.
- **Key lesson:** Start with input-addressed caching (hash the op + inputs). Don't over-invest in content-addressed dedup until you need it.

### Pachyderm (cautionary tale about scope)

- Full data versioning + pipeline provenance tracking
- "Every transformation is versioned" — conceptually identical to Liminara
- Required heavy infrastructure (etcd + Kubernetes + object storage)
- Company pivoted and was acquired. The "track everything" approach had market/operational challenges.
- **Key lesson:** The system that tracks everything must also have a good story for *not* tracking everything when the overhead exceeds the value.

---

## Engineering Decisions

### What to hash

**Recommended:** `SHA-256(type_discriminator || canonical_bytes)`

- Hash content bytes to get deduplication across runs
- Include a type discriminator to prevent cross-type collisions (a JSON file and a PDF will never actually collide, but the discriminator makes the intent explicit)
- Store provenance as graph edges, not baked into the hash

**Canonicalization matters.** If artifacts are JSON, different key orderings produce different hashes. Use canonical JSON (RFC 8785) or a binary format (CBOR, ETF with sorted keys).

### Garbage collection

**Recommended: hybrid approach**

1. **Time-based retention** (default): keep all artifacts from runs in the last N days
2. **Explicit pinning**: compliance-critical outputs are pinned and exempt from GC
3. **Periodic tracing GC**: walk the reference graph from GC roots (active runs, pinned artifacts), delete unreachable blobs

Store the reference graph in Postgres (`artifact_edges` table). Use SQL reachability queries rather than in-memory traversal.

### Large binary artifacts

Adopt an OCI-inspired model:
- A "composite artifact" is a small manifest (JSON, content-hashed) pointing to one or more blobs (content-hashed)
- Stream large blobs directly to object storage — never load into BEAM process heaps
- Consider chunked storage for artifacts that change incrementally

### Performance of "everything is an artifact"

Each intermediate requires: serialize -> hash -> store -> register metadata -> create provenance edges.

For small, fast ops (1ms transforms), this overhead dominates.

**Mitigations (in priority order):**
1. **Start with eager persistence** — simpler, correct. Measure before optimizing.
2. **Tiered storage** — inline small artifacts (<64KB) in Postgres. Medium to local disk. Large to object storage.
3. **In-memory passing** — for sequential ops on the same BEAM node, pass artifact refs in memory with async persistence
4. **Async persistence** — return hash immediately, write durably in background. Risk: crash before persistence.
5. **Lazy materialization** — for pure ops, record the "recipe" and only materialize if needed. (Nix's derivation vs realisation concept. Complex to implement.)

---

## Storage Cost Projections

| Scenario | Artifacts/day | Avg size | Daily storage | Annual storage |
|---|---|---|---|---|
| Radar only (4 runs/day) | ~60 | 50KB | 3MB | ~1.1GB |
| 3 toy packs (10 runs/day) | ~150 | 30KB | 4.5MB | ~1.6GB |
| House compiler (10 projects) | ~150 total | 1MB | N/A | ~5-20GB |
| All packs, heavy use | ~2000 | 100KB | 195MB | ~68GB |

At S3 pricing (~$0.023/GB/month), even the heavy-use scenario costs ~$1.50/month. **Storage cost is not the bottleneck.** The bottleneck is Postgres metadata performance as the provenance graph grows to millions of rows.

**Recommendation:** Partition `events` and `artifact_edges` tables by tenant and time range from the start.

---

## Practical Implementation Path

1. Start with local filesystem + SQLite for the walking skeleton
2. Migrate to Postgres + local disk when you need concurrent access
3. Add S3/MinIO when you need multi-node or off-machine storage
4. Each migration should be behind a behaviour/protocol so the artifact store is pluggable

Don't start with S3 + Postgres + Elasticsearch. Premature infrastructure choices are a solo-dev killer.
