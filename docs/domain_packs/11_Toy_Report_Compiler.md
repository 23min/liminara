# Domain Pack: Report & Diagram Compiler (Toy Pack / Substrate Validation)

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `toy.report_compiler`

---

## 1. Purpose and value

Compile structured content (Markdown + diagrams + data tables) into publishable artifacts (PDF/HTML) with strong provenance.

This pack exists primarily to validate: **artifact handling**, **external tool execution**, **environment pinning**, **caching**, and **publish gates**—without domain complexity.

### Fit with the core runtime

A minimal 'compiler pack' that exercises IR passes and binary artifacts end-to-end.

### Non-goals

- Be a full CMS.
- Be a general website generator with themes/plugins as a product.

---

## 2. Pack interfaces

This pack integrates with the core via:

- **Schemas / IR artifacts** (versioned).
- **Op catalog** (determinism class + side-effect policy).
- **Graph builder** (plan DAG → execution DAG expansion).
- **A2UI views** (optional, but recommended for debugging).

---

## 3. IR pipeline

The pack is expressed as *compiler-like passes* (even if the workload is “agentic”). Each pass produces an artifact IR that is inspectable, cacheable, and replayable.

### Document Bundle (`IR0`)

Input bundle: markdown files, assets, diagram sources, and build config.

**Artifact(s):**
- `doc.bundle.v1`

### Parsed AST (`IR1`)

Markdown parsed into an AST/semantic tree; references resolved.

**Artifact(s):**
- `doc.ast.v1`

### Render Plan (`IR2`)

Resolved toolchain plan: which renderer, which diagram engine(s), output formats.

**Artifact(s):**
- `doc.render_plan.v1`

### Rendered Assets (`IR3`)

Rendered diagrams/images and intermediate files.

**Artifact(s):**
- `doc.render_assets.v1`

### Final Artifacts (`IR4`)

PDF/HTML outputs plus a manifest for publishing.

**Artifact(s):**
- `doc.pdf.v1`
- `doc.html.v1`
- `doc.publish_manifest.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`doc.parse`** — *Pure deterministic*, *no side-effects*
  - Parse markdown to AST.
  - Inputs: `doc.bundle.v1`
  - Outputs: `doc.ast.v1`
- **`doc.plan_render`** — *Pure deterministic*, *no side-effects*
  - Select render pipeline and tool versions from config.
  - Inputs: `doc.ast.v1`
  - Outputs: `doc.render_plan.v1`
- **`doc.render`** — *Deterministic w/ pinned env*, *no side-effects*
  - Invoke external renderers (pandoc/typst/mermaid/graphviz).
  - Inputs: `doc.render_plan.v1`
  - Outputs: `doc.render_assets.v1`, `doc.pdf.v1`, `doc.html.v1`
- **`doc.publish`** — *Side-effecting*, *side-effect*
  - Publish to destination (S3/filesystem/wiki). Always gated.
  - Inputs: `doc.publish_manifest.v1`
  - Outputs: `doc.delivery_receipt.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Human approval gate**: Approve publishing of generated artifacts.
  - Stored as: `decision.gate_approval.v1`
  - Used for: Ensures side-effect correctness.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- AST viewer (small).
- Artifact preview (PDF/HTML).
- Diff viewer between two render runs (binary diff via hash + optional visual compare).
- Publish gate form.

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Local containerized renderer (recommended) to pin toolchain versions.
- Optional remote renderer for heavy docs.

---

## 8. MVP plan (incremental, testable)

- Markdown → PDF via one renderer (pandoc or typst).
- Mermaid/Graphviz diagrams as external tool.
- Artifact preview in A2UI.
- Publish gate to write to a configured directory.

---

## 9. Should / shouldn’t

### Should

- Treat toolchain version as part of op implementation identity.
- Store intermediate outputs to enable inspection and faster iteration.

### Shouldn’t

- Don’t embed large binary blobs directly into decision records; store as artifacts and reference by hash.

---

## 10. Risks and mitigations

- **Risk:** Non-hermetic rendering
  - **Why it matters:** Fonts, locale, and OS differences can change PDF bytes.
  - **Mitigation:** Pin container images; record environment fingerprints; allow verify-replay.
- **Risk:** Complexity creep
  - **Why it matters:** Docs can expand into a whole publishing system.
  - **Mitigation:** Keep pack narrow; focus on validating core primitives.

---

## Appendix: Related work and competitive tech

- [Pandoc](https://pandoc.org/) — Document converter.
- [Typst](https://typst.app/) — Modern typesetting.
- [Graphviz](https://graphviz.org/) — Graph visualization tooling.
- [Mermaid](https://mermaid.js.org/) — Text-to-diagram.
