# Liminara: Phase 0 Data Model Specification

**Date:** 2026-03-14
**Status:** Canonical. Both the Python SDK (Phase 1) and Elixir runtime (Phase 2) implement this spec. Do not change without updating both.

---

## Purpose

This is the one-page specification that makes the Python compliance demo tool and the Elixir runtime interoperable. It defines the on-disk format for artifacts, events, and decisions — the three persistent outputs of any Liminara run.

Defining this before writing code prevents the most common cause of cross-language incompatibility: each implementation making slightly different serialization choices.

---

## Hash Algorithm

```
SHA-256, encoded as "sha256:{64 lowercase hex chars}"
```

Examples:
```
sha256:2c624232cdd221771294dfbb310acbc
sha256:e3b0c44298fc1c149afbf4c8996fb924...
```

Every reference to a stored object — artifact, event, decision — is a SHA-256 hash in this encoding. There are no other identifiers in the storage layer.

---

## Canonical Serialization

All structured data (event records, decision records, artifact metadata) is serialized using **RFC 8785 JSON Canonicalization Scheme (JCS)**:

- Keys sorted lexicographically (Unicode code point order)
- No whitespace between tokens
- UTF-8 encoding
- Numbers: no trailing zeros, no scientific notation for integers
- Strings: no unnecessary escaping

This produces a unique, deterministic byte representation for any given JSON value. The SHA-256 of this representation is stable across languages and platforms.

**References:**
- RFC 8785: https://www.rfc-editor.org/rfc/rfc8785
- Python: `canonicaljson` package (Matrix.org implementation)
- Elixir: implement as `Jason.encode!(value, pretty: false)` after key-sorting (or use a JCS library)

---

## Artifact Storage

```
{store_root}/
  {hash[7:9]}/
    {hash[9:11]}/
      {hash}          ← raw bytes, no extension
```

Where `hash` is the full `sha256:{64 hex}` string stripped of the `sha256:` prefix for path construction (i.e., the 64 hex chars only).

**Example:** artifact with hash `sha256:2c624232cdd221771294dfbb310acbc8f347f4a1c695fc8e2d0a48967caa8b97`

```
{store_root}/32/cd/2c624232cdd221771294dfbb310acbc8f347f4a1c695fc8e2d0a48967caa8b97
```

**Content:** raw bytes. No serialization. No envelope. The artifact IS the bytes.

**Identity:** `artifact_hash = sha256(raw_bytes)`

**Write behavior:** write-once. If the file exists, it is identical by definition (same hash = same content). Skip write, return hash.

**Metadata:** stored separately in the event log (op, run, node, produced_at). The artifact blob has no metadata embedded.

---

## Event Log

```
{runs_root}/{run_id}/events.jsonl
```

**Format:** JSONL — one canonical JSON object per line, `\n`-terminated. Append-only. Each line is independently parseable.

**Event schema:**

```json
{
  "event_hash": "sha256:...",
  "event_type": "op_started",
  "payload": { ... },
  "prev_hash": "sha256:..." ,
  "timestamp": "2026-03-14T12:00:00.000Z"
}
```

Fields:

| Field | Type | Description |
|-------|------|-------------|
| `event_hash` | string | SHA-256 of canonical JSON of `{event_type, payload, prev_hash, timestamp}` |
| `event_type` | string | One of the event types listed below |
| `payload` | object | Event-specific data (see below) |
| `prev_hash` | string \| null | `event_hash` of the previous event. `null` for the first event in the run |
| `timestamp` | string | ISO 8601, UTC, millisecond precision |

**Hash computation:**

```
event_hash = sha256(utf8(canonical_json({
  "event_type": event_type,
  "payload":    payload,
  "prev_hash":  prev_hash,
  "timestamp":  timestamp
})))
```

Note: `event_hash` itself is NOT included in the hash input (it's the output).

**The chain:** `prev_hash` links each event to the previous event's hash. Any modification to any event in the log invalidates all subsequent hashes. This is tamper-evidence without a blockchain.

---

## Run Seal

The `event_hash` of the `run_completed` event is the **run seal**. It cryptographically commits to the entire run history: changing any event, inserting an event, or appending unauthorized events breaks the seal.

Store the run seal separately for fast lookup:

```
{runs_root}/{run_id}/seal.json
```

```json
{
  "run_id": "...",
  "run_seal": "sha256:...",
  "completed_at": "2026-03-14T12:00:00.000Z",
  "event_count": 42
}
```

---

## Decision Records

```
{runs_root}/{run_id}/decisions/{node_id}.json
```

**Format:** canonical JSON (RFC 8785). One file per nondeterministic op execution.

**Schema:**

```json
{
  "node_id": "...",
  "op_id": "...",
  "op_version": "...",
  "decision_type": "llm_response",
  "inputs": {
    "prompt_hash": "sha256:...",
    "model_id": "claude-sonnet-4-6",
    "model_version": "20251001",
    "temperature": 0.7
  },
  "output": {
    "response_hash": "sha256:...",
    "token_usage": { "input": 1024, "output": 512 }
  },
  "recorded_at": "2026-03-14T12:00:00.000Z",
  "decision_hash": "sha256:..."
}
```

`decision_hash = sha256(canonical_json(all fields except decision_hash))`

Decision records are referenced by hash in the event log (`decision_recorded` event payload includes `decision_hash`). The file is the source of truth; the event is the index entry.

---

## Event Types

Minimum set for v1:

| Event type | Payload keys |
|------------|-------------|
| `run_started` | `run_id`, `pack_id`, `pack_version`, `plan_hash` |
| `op_started` | `node_id`, `op_id`, `op_version`, `input_hashes` |
| `op_completed` | `node_id`, `output_hashes`, `cache_hit`, `duration_ms` |
| `op_failed` | `node_id`, `error_type`, `error_message` |
| `decision_recorded` | `node_id`, `decision_hash`, `decision_type` |
| `artifact_produced` | `artifact_hash`, `node_id`, `content_type`, `size_bytes` |
| `run_completed` | `run_id`, `outcome`, `artifact_hashes` |
| `run_failed` | `run_id`, `error_type`, `error_message` |

---

## Directory Layout

```
{liminara_root}/
  store/
    artifacts/
      {aa}/{bb}/{sha256_hex}      ← artifact blobs (raw bytes)
  runs/
    {run_id}/
      events.jsonl                ← append-only event log
      seal.json                   ← run seal (written on run_completed)
      decisions/
        {node_id}.json            ← one decision record per recordable op
```

`run_id` format: `{pack_id}-{timestamp_iso8601}-{8 hex chars random}` — human-readable, sortable, collision-resistant.

---

## What Is NOT Defined Here

- **Artifact content schemas** (IRs) — these are Pack contracts, not runtime contracts. The runtime sees only `sha256:{hash}` and raw bytes.
- **Plan format** — the DAG of op-nodes. Defined by the Elixir runtime; the Python SDK does not need to produce a plan.
- **Op determinism classes** — a runtime concern. The Python SDK records decisions for any decorated function; the Elixir runtime enforces class constraints.
- **Retention policy** — configurable. Default: retain all. Pin specific runs for permanent retention.

---

## Implementation Checklist

For any implementation to be spec-compliant:

- [ ] SHA-256 encoded as `sha256:{64 lowercase hex chars}`
- [ ] Canonical JSON per RFC 8785 (sorted keys, no whitespace, UTF-8)
- [ ] Artifact identity = `sha256(raw_bytes)` — no other hash input
- [ ] Event `event_hash` computed over `{event_type, payload, prev_hash, timestamp}` only
- [ ] First event in run has `prev_hash: null`
- [ ] Each event's `prev_hash` equals previous event's `event_hash`
- [ ] `events.jsonl` is append-only; lines never modified or deleted
- [ ] Run seal = `event_hash` of `run_completed` event
- [ ] Decision `decision_hash` computed over all fields except itself
- [ ] Directory layout matches spec above

---

*See also:*
- *[09_Compliance_Demo_Tool.md](09_Compliance_Demo_Tool.md) — Python SDK implementation of this spec*
- *[07_Compliance_Layer.md](07_Compliance_Layer.md) — integration architecture for existing systems*
- *[10_Synthesis.md](10_Synthesis.md) § 9 — development sequence (Phase 0 = this document)*
