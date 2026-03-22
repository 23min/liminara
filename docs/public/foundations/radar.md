# Radar — Research Intelligence

**Can a provenance engine turn information monitoring into structured, explorable knowledge?**

Active development | LLM orchestration, vector search, serendipity detection, caching

---

## The scenario

Katarina runs strategy at a mid-sized Swedish consultancy. She monitors regulatory developments, technology shifts, and adjacent-field research — not just for what's happening, but for connections nobody is looking for. Last month, a paper on immune system cascade failures turned out to be directly relevant to a client's supply chain resilience problem. That connection was serendipitous — she happened to read both papers in the same week.

What if serendipity could be systematic?

---

## Two layers, not one

Radar is not a newsletter generator. It has two fundamentally different layers:

```
COLLECTION LAYER (continuous, growing)
═══════════════════════════════════════════════════════════════

  Sources ──→ fetch ──→ normalize ──→ embed ──→ update index
  (RSS, web,   (amber)    (teal)      (teal)     (amber)
   APIs, HN)
              │                        │
              │  source snapshots      │  vector embeddings
              │  (immutable artifacts) │  (content-addressed)
              │                        │
              ▼                        ▼
         Source Corpus            Vector Index
         (growing over time)     (LanceDB, file-based)
         sha256:... per doc      sha256:... per version


ANALYSIS LAYER (triggered, snapshot-based, replayable)
═══════════════════════════════════════════════════════════════

  Corpus snapshot ──→ classify ──→ cluster ──→ cross-domain ──→ synthesize ──→ briefing
  (immutable)          (coral)      (teal)      search           (coral)
                                                (teal)
                        │                        │                │
                        │ LLM relevance         │ unexpected     │ LLM writes
                        │ scores                │ proximities    │ the briefing
                        │ DECISION RECORDED     │ found          │ DECISION RECORDED
                        │                       │                │
                        ▼                       ▼                ▼
                   "Is this relevant?"    "Why are these     "What does this
                   "What domain is it?"    close together?"    pattern mean?"
```

The **collection layer** runs continuously in discovery mode — new sources are found, fetched, normalized, and embedded into a growing vector index. Each document gets a permanent, content-addressed identity. The index is a versioned artifact: each update produces a new version with a new hash.

The **analysis layer** runs on demand — taking an immutable snapshot of the current corpus and producing a briefing. This layer is fully replayable: same corpus snapshot + same decisions = same briefing.

The separation keeps analysis clean and testable while collection handles the messy reality of the open web.

---

## What makes Radar more than a feed reader

### Cross-domain connection finding

Every document is embedded into a shared semantic space (the vector index). Documents from different domains that are unexpectedly close — high semantic similarity despite different source categories — are flagged as potential connections.

```
  Domain A: EU regulation                Domain B: Systems theory
  ──────────────────────                 ────────────────────────
  "EUDR requires tracing commodities     "Cascade failure propagation
   through every aggregation point        in complex networks follows
   in the supply chain"                   power-law distributions with
                                          critical node identification"
                        │                          │
                        └──── similarity: 0.84 ────┘
                              (unexpectedly high for
                               cross-domain pair)
                                     │
                                     ▼
                        ┌────────────────────────────┐
                        │  Serendipity candidate     │
                        │                            │
                        │  LLM evaluates: "Supply    │  coral (recordable)
                        │  chain traceability under  │  DECISION RECORDED
                        │  EUDR is structurally      │
                        │  similar to critical node  │
                        │  identification in cascade │
                        │  failure analysis. The     │
                        │  methods from network      │
                        │  science could identify    │
                        │  which aggregation points  │
                        │  are highest risk for      │
                        │  traceability loss."       │
                        └────────────────────────────┘
```

The embedding is a `pure` op (same document + same model = same vector, cacheable). The cross-domain search is a `pure` op (deterministic nearest-neighbor query against a pinned index version). The LLM evaluation of whether the connection is substantive is `recordable` — the judgment is captured as a decision.

### Historical search

The corpus accumulates over time. Each document has a permanent identity. A question like "has anyone written about supply chain cascade failures before?" becomes a vector search against the full historical corpus — not just this week's sources, but everything ever collected.

### Serendipity as architecture

The Memex connection: Vannevar Bush described a device that stored a researcher's library and let them create associative trails through it. Radar is this, made buildable. The corpus is content-addressed (permanent document identities). The trail through the corpus is a Liminara run (the DAG of ops). The decisions along the trail are recorded — why did the system find *this* connection interesting? That judgment is preserved. The trail is replayable and forkable.

---

## A concrete week

**Monday — collection runs overnight:**

45 sources monitored. 12 have new content. 33 unchanged → normalization cached. The 12 new documents are embedded and added to the vector index (index version v47 → v48).

**Tuesday — analysis triggered:**

Katarina triggers an analysis run against corpus snapshot v48.

```
Run #23 — Tuesday analysis
──────────────────────────

  classify:  38 documents scored for relevance (12 new + 26 from last week still in window)
             LLM decisions recorded for each

  cluster:   4 clusters formed
             A: EU regulatory simplification (5 docs, avg relevance 0.91)
             B: Battery supply chain developments (3 docs, avg 0.87)
             C: Swedish innovation funding (2 docs, avg 0.82)
             D: Process optimization methods (3 docs, avg 0.76)

  cross-domain search:
             2 serendipity candidates found
             ✓ "Network cascade analysis" × "EUDR aggregation traceability" (0.84)
               → LLM: substantive connection (decision recorded)
             ✗ "Enzyme kinetics paper" × "Queue theory in logistics" (0.79)
               → LLM: superficial similarity, different mechanisms (decision recorded)

  synthesize: briefing generated with 4 cluster summaries + 1 serendipity finding
              LLM decision recorded (model, prompt hash, full response)

  Cost: $0.18 (classification: $0.08, serendipity eval: $0.04, synthesis: $0.06)
  Cached ops: 33 normalizations, 26 classifications from previous run
```

**Thursday — Katarina wants to explore:**

"What if we looked for connections specifically between sustainability regulations and operations research?"

She forks run #23 at the cross-domain search step, changing the search parameters to focus on these two domains. Everything upstream (collection, classification, clustering) is cached. Only the cross-domain search and synthesis re-execute.

Cost: $0.07. Time: 12 seconds.

The fork finds three additional connections that the broad search missed — narrower but more relevant to a specific client project.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Why did the briefing highlight the cascade failure connection?" | Trace: briefing (sha256:9f8e) ← synthesis op ← serendipity candidate ← cross-domain search found similarity 0.84 between doc sha256:a1b2 (EUDR paper) and doc sha256:c3d4 (network science paper) ← LLM evaluated as substantive (decision sha256:7d2f, full reasoning preserved) |
| "What did the model actually say about the enzyme kinetics connection?" | Decision record `decisions/serendipity_eval_2.json`: prompt included both abstracts, model responded "superficial similarity — both describe rate-dependent processes but the mechanisms are fundamentally different", scored 0.31 for substantiveness |
| "Has anything about supply chain cascade failures appeared before?" | Historical search against full corpus (all versions): returns 3 previous documents from months ago that were below the relevance threshold at the time but are now contextually relevant given the new EUDR connection |
| "What if we'd used a broader similarity threshold for serendipity?" | Fork at cross-domain search, lower threshold from 0.75 to 0.60. More candidates surface. LLM evaluates each (new decisions recorded). Compare: which additional connections are substantive? |
| "How has our coverage of battery regulation evolved over the last 6 months?" | Query the corpus: all documents tagged "battery regulation" across all collection runs, ordered by time. The vector index versions are all content-addressed artifacts — the evolution of the knowledge base is itself an artifact trail. |

---

## Before and after

**Today:** Katarina reads sources manually. Connections are accidental — she notices them when she happens to read two related things close together. Briefings are written from memory. Next week: start from scratch. The institutional knowledge is in Katarina's head.

**With Radar:** The collection layer builds a growing, searchable corpus with permanent document identities. The analysis layer finds connections systematically — including cross-domain ones nobody asked for. Every connection traces to specific sources through specific model judgments. Briefings are replayable and forkable. When Katarina leaves for vacation, the system's knowledge doesn't leave with her — it's in the corpus, the decision records, and the event logs.

The serendipitous connection between immune system cascades and supply chain resilience? It would have been found automatically — because "unexpectedly close in semantic space, from different domains" is exactly what the cross-domain search computes.

---

*Radar is Liminara's first real-world pack and primary validation of the runtime against real data, real LLM costs, and real research workflows.*
