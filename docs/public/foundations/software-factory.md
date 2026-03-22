# Software Factory — Agentic Coding with Provenance

**When an LLM writes code, who wrote the code? Can you trace every decision in a 47-call coding session back to its reasoning?**

Research | discovery mode, LLM decision chains, security gates, replay with model substitution

---

## The scenario

Klara Nilsson is a developer at Proliminal. She asks an LLM to add XBRL export to Liminara's VSME sustainability reporting pack. The task sounds simple — "read the VSME spec, add XBRL output alongside the existing PDF renderer" — but the LLM session that follows involves 47 LLM calls over 25 minutes, branching through analysis, design, code generation, test writing, test execution, failure diagnosis, and iteration.

This is **discovery mode**: the plan isn't known upfront. The LLM decides what to do next based on what it just learned. Each decision expands the DAG.

---

## The session, step by step

```
  DISCOVERY MODE — DAG grows as the LLM works
  ═══════════════════════════════════════════════

  Call 1    ┌─── read VSME spec ──────────┐
  (plan)    │ "I need to understand the    │
            │  VSME disclosure structure"  │──→ vsme-spec-summary (artifact)
            └─────────────────────────────┘
                        │
  Calls 2-4  ┌─── analyze existing code ──┐
  (read)     │  report renderer module     │
             │  PDF template structure     │──→ code-analysis (artifact)
             │  artifact schema            │
             └─────────────────────────────┘
                        │
  Call 5     ┌─── design decision ────────┐
  (plan)     │ "Use ex_xbrl or hand-      │
             │  build XBRL XML?"          │
             │                            │
             │  Decision: use ex_xbrl     │──→ decision record:
             │  Reason: "maintained,       │    library_choice = "ex_xbrl"
             │  covers ESRS taxonomy,      │    rationale = "maintained, ESRS
             │  1,200 GitHub stars"         │    taxonomy, type-safe"
             └─────────────────────────────┘
                        │
  Calls 6-12 ┌─── design XBRL mapping ───┐
  (plan)     │  B1-B11 → XBRL concepts   │
             │  data types, units,        │──→ xbrl-schema-mapping (artifact)
             │  period references          │    sha256:c4a1...
             └─────────────────────────────┘
                        │
  Calls 13-28 ┌── generate code ──────────┐
  (write)     │  xbrl_renderer.ex         │
              │  xbrl_template.ex         │──→ patchset (artifact)
              │  mix.exs dep addition     │    sha256:8f72...
              └───────────────────────────┘
                        │
              ┌── SECURITY GATE ──────────┐
              │  Human approves file       │──→ decision record:
              │  writes before they        │    gate = "file_write"
              │  touch disk                │    approved_by = "klara.nilsson"
              └───────────────────────────┘
                        │
  Calls 29-34 ┌── write tests ───────────┐
  (write)     │  xbrl_renderer_test.exs  │──→ test-patchset (artifact)
              │  12 test cases            │    sha256:a903...
              └───────────────────────────┘
                        │
  Calls 35-38 ┌── run tests ─────────────┐
  (exec)      │  mix test                │──→ test-result (artifact)
              │  9 pass, 3 fail          │    sha256:d2e1...
              └───────────────────────────┘
                        │
  Calls 39-43 ┌── diagnose + fix ────────┐
  (iterate)   │  "period ref format      │
              │   wrong for B3 energy    │──→ fix-patchset (artifact)
              │   disclosure — XBRL       │    sha256:1b44...
              │   expects duration not   │
              │   instant"                │
              └───────────────────────────┘
                        │
  Calls 44-46 ┌── re-run tests ──────────┐
  (exec)      │  mix test                │──→ test-result-v2 (artifact)
              │  12 pass, 0 fail         │    sha256:7f93...
              └───────────────────────────┘
                        │
              ┌── SECURITY GATE ──────────┐
              │  Human approves PR        │──→ decision record:
              │  creation                 │    gate = "pr_create"
              └───────────────────────────┘
                        │
  Call 47     ┌── open PR ────────────────┐
  (side-fx)   │  PR #142: "Add XBRL      │──→ delivery-receipt (artifact)
              │  export to VSME pack"     │    sha256:e4b8...
              └───────────────────────────┘
```

The DAG contains 47 LLM decision records, 2 human gate approvals, 11 intermediate artifacts, and 1 side-effecting delivery. Every node is content-addressed. The entire session — including the dead end where the period reference format was wrong — is preserved.

---

## Tracing a decision

Two weeks later, a reviewer asks: **"Why did the model choose ex_xbrl over hand-building XBRL XML?"**

The answer is not "because the LLM said so." The answer is a trace:

1. Navigate to run `sf-run-2026-03-14-xbrl` in the observation UI
2. Find decision record at call 5: `decision.llm_output.v1`
3. Read the recorded rationale: *"ex_xbrl — maintained library with 1,200 GitHub stars, covers ESRS taxonomy, provides type-safe concept builders. Hand-building XML risks namespace errors and lacks validation. Build-vs-buy favors the library for a v1."*
4. See the input artifacts that informed this decision: the VSME spec summary, the code analysis of the existing renderer
5. See what happened downstream: the schema mapping (calls 6-12) depended on this choice

The decision is not just recorded — it is positioned in its causal context. The reviewer can see what information was available when the decision was made and what consequences followed.

---

## Replay with a different model

Klara wants to compare: what if she had used claude-sonnet-4 instead of claude-haiku-4 for this session?

```
replay sf-run-2026-03-14-xbrl
  --override model=claude-sonnet-4
```

The replay re-executes every LLM call with the new model. The DAG structure evolves in the same discovery pattern — the plan isn't fixed — but the inputs to each decision point are the same. Sonnet might choose a different library at call 5. If it does, the downstream DAG diverges from that point: different schema mapping, different generated code, different test results.

The result: two complete run traces, comparable side by side. Same task, same starting context, different model. Every divergence point is visible. The cost difference is visible. The quality difference (did the tests pass on the first try?) is visible.

Pure ops (applying patches, running tests) cache-hit when the inputs are identical. Only the LLM calls and their downstream dependencies re-execute.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Why did the model choose ex_xbrl?" | Decision record at call 5: rationale, input artifacts, downstream consequences. Full causal context. |
| "What information did the model have when it designed the schema mapping?" | Trace inputs to calls 6-12: the VSME spec summary (artifact), the code analysis (artifact), and the library choice decision (call 5). |
| "Why did three tests fail on the first run?" | Test result artifact (sha256:d2e1...) shows failures. Diagnosis at calls 39-43 explains: XBRL period reference format mismatch. The fix is a separate artifact (sha256:1b44...). |
| "What would this session cost with a different model?" | Replay with `--override model=claude-sonnet-4`. Compare: total tokens, wall time, test-pass rate, number of iteration cycles. |
| "Did the model access any files outside the VSME pack?" | Audit the tool call records in all 47 decisions. Every file read, every directory listing is recorded. Scope violations are detectable after the fact. |
| "Can we reproduce the exact PR that was created?" | Replay the original run (no overrides). Every decision replays from stored records. The patchset artifact is identical (same hash). The PR body is identical. |

---

## Before and after

**Today:** Klara uses an LLM coding tool. It produces a PR. The PR looks reasonable. She merges it. Three months later, someone asks why ex_xbrl was chosen instead of the ESRS-specific library that the Finnish team uses. Nobody knows. The reasoning happened in a chat window that no longer exists. The decision was made by a model that has since been deprecated.

**With provenance:** The entire coding session is a run. Every LLM call is a decision record. The library choice traces to specific reasoning informed by specific context. The dead end (wrong period format) is preserved — it documents what didn't work and why. When someone asks "why?", the answer exists, is findable, and is verifiable. When a better model becomes available, the session can be replayed to compare outcomes without re-doing the human parts (the task description, the gate approvals reuse stored decisions unless explicitly re-gated).

---

*Looking for development teams exploring provenance for AI-assisted coding — especially those subject to audit requirements for AI-generated code. [Contact ->]*
