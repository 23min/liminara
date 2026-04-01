# Dataflow Systems, Procedural Audio, and Liminara

**Date:** 2026-03-31
**Sources:**
- *Designing Sound* by Andy Farnell (MIT Press, 2010), 689 pages
- Miller Puckette's Pure Data architecture and *The Theory and Technique of Electronic Music* (2007)
- Joe Armstrong's Erlang + music experiments (blog posts, OSC integration)
- Sam Aaron / Sonic Pi / Overtone — bridging BEAM and audio communities

**Context:** Positioned against Liminara's DAG execution model, determinism classification, and general-purpose runtime architecture. Procedural audio — synthesizing sound from first principles using dataflow graphs — turns out to share deep structural parallels with Liminara. Both are DAG-of-operations runtimes that compose typed primitives, separate control from computation, and achieve reproducibility by capturing nondeterminism rather than banning it. This document also explores the feasibility of audio DSP from Elixir/OTP and the prior art from Armstrong's Erlang music work.

---

## The Procedural Audio Thesis

Farnell's central argument, stated on page 1 of *Designing Sound*:

> *"It's about sound as a process rather than sound as data, a subject sometimes called 'procedural audio.' The thesis of this book is that any sound can be generated from first principles, guided by analysis and synthesis."*

The book argues that **procedural sound models are superior to recordings** because they capture *behaviour*, not a frozen snapshot. A recording of a car engine is a single instance; a procedural model generates infinite variations that respond to runtime parameters (RPM, load, gear, road surface). Farnell calls this property **"deferred form"** — the computation is specified as a model and deferred to runtime, where it adapts to dynamic conditions.

The book uses **Pure Data (Pd)**, Miller Puckette's visual dataflow language, to build 35 practical sound effects from scratch: bells, fire, rain, thunder, wind, engines, helicopters, footsteps, insects, birds, guns, explosions, and science fiction sounds (Star Trek transporter, R2D2, Red Alert siren). Each follows a rigorous cycle: physical analysis → abstract model → synthesis method → Pd implementation → critique and iteration.

### Miller Puckette and the Lineage

**Miller Smith Puckette** (b. 1959) is the creator of both Max and Pure Data. MIT-trained mathematician, he spent a decade at **IRCAM** (Paris) where he built **Max** (1986–88) — a graphical patching environment for real-time music, named after Max Mathews (Bell Labs, godfather of computer music). Max originally controlled IRCAM's custom 4X DSP processor and later the ISPW (Intel i860-based boards). It was used in landmark pieces like Philippe Manoury's *Jupiter* (1987) — one of the first major concerts with real-time computer processing of a live instrument.

After moving to **UC San Diego** in 1994, Puckette created **Pure Data** (1996) as an open-source, from-scratch reimagining. The key design decision: Pd would run on **commodity desktop hardware** — no expensive DSP boards. This was radical. Before Pd, real-time computer music meant Fairlight, Synclavier, or IRCAM hardware costing tens of thousands.

David Zicarelli licensed Max and commercialized it as **Max/MSP** (Cycling '74, now Ableton). Max became the commercial standard; Pd became the open-source one. Both descend from the same mind and the same dataflow paradigm.

Puckette also wrote *The Theory and Technique of Electronic Music* (2007, freely available at msp.ucsd.edu/techniques.htm) and created influential pitch-tracking algorithms (`fiddle~`, `sigmund~`). **libpd** — Pd's engine as an embeddable C library — later enabled Pd patches to run inside mobile apps, games, and DAW plugins without the GUI.

### Key findings from the textbook

Puckette's textbook provides the *formal mathematical foundations* for the dataflow execution model. Several sections are directly relevant to Liminara's architecture:

**Determinism via logical time** (Ch. 3, p. 62): *"Electronic music computations, if done correctly, are deterministic: two runs of the same real-time or non-real-time audio computation, each having the same inputs, should have identical results."* This is achieved by referencing all computation to a logical clock rather than wall-clock time — the same insight behind Liminara's event-sourced runs.

**Block-scheduled DAG execution** (Ch. 7, pp. 211–214): Puckette describes exactly the scheduling algorithm: *"Although the tilde objects in a patch may have a complicated topology of audio connections, in reality Pd executes them all in a sequential order... This linear order is guaranteed to be compatible with the audio interconnections, in the sense that no tilde object's computation is done until all its inputs, for that same block, have been computed."* The graph must be a DAG — Pd reports an error on cycles. This is topological sort, the same algorithm Liminara's scheduler uses.

**Dual-domain computation** (Ch. 3): Audio signals are regular sequences computed in blocks of B samples. Control streams are irregular (time, value) pairs — events. Four fundamental operations on event streams: delay, merge, prune, resynchronize. Conversion between domains is explicit (snapshot, interpolation). This dual-domain model maps to Liminara's distinction between continuous pipeline computation and discrete event-driven scheduling.

**State via feedback with delay** (Ch. 7–8): Cycles in the dataflow graph are broken by delay elements (delwrite~/delread~) that introduce a minimum delay of B samples. Filters are formally stateful operations with recurrence relations y[n] = f(x[n], x[n-1], ..., y[n-1], ...). The z-transform provides an algebra for composing stateful operations. In Liminara's model, stateful operations correspond to ops that depend on previous run state — the delay element is analogous to reading a cached artifact from a prior run.

**Hierarchical encapsulation** (Ch. 4, p. 102): Subpatches execute atomically — *"Audio computation in subpatches is done atomically, in the sense that the entire subpatch contents are considered as the audio computation for the subpatch as a whole."* Multiple instances of the same abstraction have independent state. This parallels Pack instantiation in Liminara.

### Pure Data's Architecture

Pure Data is a dataflow programming environment where **the diagram is the program**. A Pd "patch" is a directed graph of objects connected by wires. The runtime traverses this graph depth-first, right-to-left — a topological sort that resolves dependencies before computing anything:

> *"A patch, or dataflow graph, is navigated by the interpreter to decide when to compute certain operations. This traversal is right to left and depth first... it wants to know what depends on what before deciding to calculate anything."*

Pd has two execution domains:

- **Message domain** (control rate): Event-driven, asynchronous. Objects sit idle until triggered. Handles sequencing, routing, logic, parameter control.
- **Signal domain** (audio rate): Synchronous, block-based (64-sample blocks). Processes continuous audio streams. Always running when enabled.

Messages are scheduled at the start of each audio block — a two-phase scheduler that processes control events first, then computes signal blocks. The message domain uses a "hot/cold inlet" convention: cold inlets accumulate data silently; hot inlets trigger computation. The `trigger` object forces explicit left-to-right evaluation order, making execution deterministic when multiple inputs arrive at a node.

The runtime is supervised by three processes: **pd** (engine), **pd-gui** (interface), and **pd-watchdog** (monitors execution, halts runaway programs) — a supervision pattern analogous to OTP.

### The Methodology

Every practical follows the same pipeline:

1. **Analysis** — Study the physics of the phenomenon (mechanics, materials, energy flow)
2. **Model** — Decompose into functional subsystems: excitors, resonators, couplings, radiation
3. **Method** — Choose synthesis technique: additive, subtractive, FM, granular, waveshaping, physical modeling
4. **Implementation** — Build the Pd patch from composable abstractions
5. **Test/Iterate** — Evaluate against reference recordings; refine parameters

Farnell maps this explicitly to software engineering: requirements analysis → research → model building → method selection → implementation → integration → test/iteration → maintenance. He invokes agile methodology: *"fail early, fail often."*

### Entity-Action Decomposition

Complex sound-producing objects are decomposed into networks of subsystems connected by typed couplings that represent energy transfers:

> *"Any sound-producing object, no matter how complex, can be reduced to a network system."*

A church bell becomes: striker (excitor) → friction coupling → bell body (resonator) → radiation → air (medium) → environment. A violin: bow (excitor) → friction → string (resonator) → bridge coupling → body (resonator) → radiation. The couplings have types: friction, impact, pressure, radiation. This is graph construction — nodes are physical subsystems, edges are energy transfers.

---

## Seven Structural Parallels to Liminara

### 1. The DAG Is the Program

Both systems are dataflow computation engines where a directed acyclic graph of operations *is* the program.

| Pure Data | Liminara |
|-----------|----------|
| Objects (nodes) | Ops (typed functions) |
| Connections (wires) | Artifacts (content-addressed edges) |
| Patches (graphs) | Plans (DAGs) |
| Subpatches / abstractions | Packs (reusable op definitions) |
| Depth-first traversal | Topological scheduler |

Both resolve dependencies before computing. Both compose complex behavior from simple primitives connected in graphs.

### 2. Determinism Classification

Farnell's sounds span a spectrum from fully deterministic to fully stochastic:

- **Deterministic**: FM synthesis with fixed parameters, polynomial waveshaping, clock mechanisms — *"A clock is a deterministic chain of events, each one causing another."*
- **Controlled stochastic**: Poisson-distributed rain timing, Gaussian raindrop intensity, noise-seeded fire crackling, stick-slip friction randomness. Carefully shaped distributions produce realism.
- **Fully random**: R2D2 — *"completely randomize the parameter space of a simple synthesizer."*

This maps to Liminara's four Op determinism classes:

| Pd pattern | Liminara class | Example |
|---|---|---|
| Fixed-parameter FM, polynomial waveshaping | `pure` | Same inputs → same output, always |
| DSP using platform-specific float behavior | `pinned_env` | Reproducible given same environment |
| Noise with capturable seed, random grain timing | `recordable` | Nondeterministic but the choice can be captured |
| Audio output, file I/O, network | `side_effecting` | Changes the external world |

Farnell describes how `srand()` seeds make pseudo-random noise reproducible — which is precisely the concept of a Decision record capturing a stochastic choice for replay.

### 3. Composition from Typed Primitives

Every sound is built by composing small, reusable, parameterized units:

- **Bell** = 15 oscillators × 5 envelope generators × 5 modal groups × 1 striker × 1 casing resonator
- **Helicopter** = engine + main rotor + tail rotor + gearbox + distance filter
- **Fire** = hiss + crackle + lapping flame components
- **Thunder** = 5 independent layers: strike pattern, N-wave rumble, afterimage, deep noise, environmental echoes

Pd's abstraction system provides per-instance isolation (`$0`-scoped namespaces), creation arguments (`$1, $2...`) for parameterization, and "Graph-on-Parent" for interface exposure. This parallels Liminara's Pack callbacks (`id`, `version`, `ops`, `plan`, `init`).

### 4. Separation of Control Plane and Compute Plane

A consistent design principle throughout the book:

> *"We further illustrate the decoupling of control and synthesis parts. The walking mechanism is particular to the animal, while the sound is governed by the surface on which it moves."*

Pd's message domain (event-driven control logic) is cleanly separated from its signal domain (heavy DSP computation). This mirrors Liminara's Elixir/OTP control plane (scheduling, events, supervision) separated from its compute plane (ports, containers, NIFs for heavy ops).

Both architectures recognize that orchestration and computation are fundamentally different concerns with different performance characteristics and scheduling needs.

### 5. Event Sourcing

The rocket launcher chapter introduces explicit state management: an action-state diagram maps events (fire, reload, drop) to state transitions (loaded ↔ empty), which determine acoustic behavior. Farnell notes:

> *"Strictly, for game objects, state should rarely be built into sounds themselves. The main object code should maintain an authoritative version of all states."*

State lives outside the object; behavior is derived from events received. This is event sourcing. Liminara's Run is *"an append-only event log — events are the source of truth."*

The pouring chapter demonstrates a related pattern: a single time parameter (glass fullness) drives all other state — bubble size, flow rate, liquid depth, cavity resonance. All state derived from a single source of truth.

### 6. The Supervision Pattern

Pd's three-process architecture (pd, pd-gui, pd-watchdog) is a supervision tree. Farnell discusses long-running reliability:

> *"VR software installations for world simulators must be expected to run with up-times of months or optimistically years."*

His solutions — periodic object reset/reinstantiation, finite lifetimes, graceful degradation — map to OTP supervision strategies: let it crash, restart cleanly, isolate failures.

### 7. Caching and Memoization

Farnell discusses "hybrid architectures" for game audio:

> *"A compromise is to restructure programs to include a precomputation stage for intermediate forms that will remain fixed throughout the lifetime of object instances."*

> *"During low load periods, offline processing occurs to fill data tables with anticipated media."*

This is speculative precomputation and memoization. Liminara formalizes this as `cache_key = hash(op, version, input_hashes)` — if inputs haven't changed, reuse the cached result.

Farnell adds a crucial nuance: *"DSP optimisation by reuse depends on causal correlation. Some sounds are features of the same underlying process and signals can be combined, while others are independent and must be kept separate."* Shared computation is valid only when outputs are causally linked. This maps to Liminara's rule that only `pure` ops with identical inputs can share cached results.

---

## Three Borrowable Concepts

### A. "Deferred Form" as a Framing Device

Farnell's term for procedural audio's core property:

> *"Procedural sound is a living sound effect that can run as computer code and be changed in real time according to unpredictable events."*

A Liminara run *is* deferred form — it specifies what to compute and defers execution to runtime, where it responds to dynamic inputs (LLM responses, human approvals, fresh data). The output isn't pre-baked; it emerges from the process. "Deferred form" could be a useful framing when explaining Liminara to people who think in terms of workflows and pipelines.

### B. Dynamic Level of Detail (LOAD)

Farnell proposes **Level of Audio Detail** — simplifying synthesis models based on relevance rather than just attenuating output. A distant helicopter only needs rotor chop; up close it needs engine + rotors + gearbox. The graph itself changes based on context.

Liminara could apply this to DAG execution: for preview/draft runs, execute a simplified plan (skip expensive ops, use cheaper LLM models, reduce fan-out). For final runs, execute the full graph. This is more nuanced than caching — it's **adaptive graph resolution**. Related to the planned "discovery mode" but at a different level of abstraction.

### C. The Analysis → Model → Method → Implementation Cycle

Farnell's 35 practicals each follow the same rigorous cycle. A Pack author developing a Liminara domain pack should follow the same discipline: analyze the domain physics, decompose into functional subsystems, choose appropriate op types and determinism classes, implement, test against reference outputs, iterate. The methodology transfers directly.

---

## The Deeper Connection: Process vs. Data

The most profound link isn't technical — it's philosophical.

Farnell spends 689 pages arguing that **capturing the process that produces a sound is more valuable than capturing the sound itself**. A recording is a frozen snapshot; a procedural model captures the *behaviour* that generates infinite variations, responds to parameters, and can be reasoned about.

Liminara makes the same argument about computation: **capturing the process that produces a result — the DAG, the decisions, the event log — is more valuable than the result alone**. A stored output is a frozen snapshot; a recorded run captures the generative process and can be replayed, audited, varied, and cached.

Both systems reject "store the data" in favor of "store the process." Both achieve reproducibility not by eliminating nondeterminism but by **recording it**. Both build complex results by composing simple, typed operations in directed acyclic graphs.

| Recording (data) | Procedural model (process) |
|---|---|
| One frozen instance | Infinite variations |
| Fixed at capture time | Adapts to runtime conditions |
| Opaque — why this output? | Transparent — trace any output to its causes |
| Large storage, zero compute | Small storage, compute on demand |
| Cannot be audited | Every decision traceable |

---

## Could Procedural Audio Be a Liminara Domain Pack?

Yes — and it would be a powerful validation of architectural generality.

A **Procedural Audio Pack** would:

- Define Ops for oscillators, filters, envelopes, noise generators, waveshapers, delay lines
- Use `pure` determinism for all DSP ops (same inputs → same output)
- Use `recordable` for stochastic elements (noise seeds, random grain timing, Poisson intervals)
- Produce audio Artifacts (WAV blobs, content-addressed)
- Build Plans that are literal signal processing graphs
- Enable exact replay by injecting stored random seeds as Decision records
- Enable variation by changing one parameter and re-executing only downstream ops

This would validate that Liminara's five concepts handle a domain maximally distant from "LLM text pipelines." If the same DAG scheduler that runs a Radar intelligence pipeline can also synthesize a thunderstorm, the architecture is genuinely domain-agnostic.

The practical value is modest (Pd and SuperCollider already exist for this domain), but the architectural validation is significant. It's the same argument made by the house compiler pack — that Liminara's generality is real, not accidental.

---

## Statistical Distributions Farnell Uses (Reference)

The book is precise about which probability distributions produce realistic sounds. Useful reference for any pack involving stochastic processes:

| Distribution | Application | Why |
|---|---|---|
| Gaussian (normal) | Raindrop intensity | Central limit theorem — many independent factors |
| Poisson (via exponential intervals) | Rainfall timing | Memoryless arrival process |
| Bilinear exponential | Water frequency variation | Nearby values most probable, distant values exponentially unlikely |
| 1/f (pink) | General rain ambiance, "comfort noise" | Natural spectra follow 1/f power law |
| Prime-spaced sequences | Bubble timing illusion | No common factors → appears aperiodic |
| Uniform | Explicitly called out as *wrong* for most natural phenomena | Nature is rarely uniform |

---

## Key Quotes

> *"Sounds so constructed are more realistic and useful than recordings because they capture behaviour."* — p. 1

> *"The diagram is the program."* — Pd motto, p. 5

> *"Any sound-producing object, no matter how complex, can be reduced to a network system."* — p. 48

> *"A clock is a deterministic chain of events, each one causing another. That is where the expression 'working like clockwork' comes from."* — p. 387

> *"DSP optimisation by reuse depends on causal correlation."* — p. 409

> *"Critical aesthetic choices can be made later in the process."* — on deferred decisions, p. 319

> *"Procedural audio, on the other hand, is highly dynamic and flexible; it defers many decisions until run time."* — p. 319

> *"In a way it is why we worked so hard, to learn so many rules, only to let go of them. A pianist practices scales, but for entertainment plays music."* — p. 615

---

## How DSP Actually Works (and Why It's Not Choppy)

A natural question: how can combining simple waveforms produce realistic, smooth sound on commodity hardware? The answer is architecture plus mathematics.

### Block-based callback model

Pd's engine is written in **C**. Audio is computed in **blocks of 64 samples**. The OS audio driver calls back into Pd ~689 times per second (44100 / 64), and each callback must complete in under **~1.45 milliseconds**:

1. On startup, Pd performs a **topological sort** of the signal graph (one-time cost)
2. This produces a flat list of C function pointers — the **DSP chain**
3. Each callback: iterate through the chain, calling each `perform` function on pre-allocated 64-sample float buffers
4. No memory allocation, no GC, no interpretation in the audio path — just a tight loop of indirect function calls on float arrays

This is why it ran on 1996 hardware. A Pentium could do millions of float ops per second. A single synth voice needs ~5 million FLOPS. Even a 200 MHz Pentium Pro had the arithmetic headroom. The innovation was the **architecture** (pre-sorted graph, zero-allocation callbacks, separate GUI process) that made the *timing* deterministic.

### Computational requirements

For CD-quality audio (44,100 Hz, 16-bit stereo):

- One sine oscillator: ~10 float ops per sample → ~440K FLOPS
- Realistic synth voice (8 oscillators + filter + envelope + mixer): ~105 ops per sample → ~4.6M FLOPS
- 16 polyphonic voices: ~74M FLOPS
- Complex DAW mix (64 tracks × 5 plugins each): low billions of FLOPS

A modern CPU does tens of billions of FLOPS. **Computation is not the bottleneck — deterministic timing is.** The callback must complete before the current buffer drains. Miss the deadline and you hear a pop, click, or dropout.

### Why combining waveforms sounds smooth

It's the Fourier theorem. Any periodic sound is literally a sum of sine waves:

```
square(t) = sin(t) + sin(3t)/3 + sin(5t)/5 + sin(7t)/7 + ...
```

This isn't an approximation — it's mathematical fact. Combining primitive waveforms produces smooth, rich sound **if the digital representation is handled correctly**.

What causes choppiness is **aliasing**: if a waveform contains frequencies above the Nyquist limit (sample_rate / 2 = 22,050 Hz at CD quality), those frequencies fold back into the audible range as inharmonic, metallic garbage. The solution is **band-limited waveform generation** — techniques like PolyBLEP that correct discontinuities with ~4 extra operations per sample. This has been a solved problem since the late 1990s. Every software synthesizer (Serum, Vital, Massive, SuperCollider, every DAW plugin) works this way.

### Live vs. offline

- **Live/real-time**: Must fill the audio buffer before the deadline (~1.5–12 ms depending on buffer size). Parameters change and sound changes instantly. This is what Pd was built for.
- **Offline rendering**: Compute samples at leisure, write to WAV/FLAC. No deadline. Can use more expensive algorithms. Output sounds identical to live synthesis with the same parameters.

For a Liminara pack, **offline rendering is the natural fit** — the DAG scheduler produces a WAV artifact, no real-time constraint. But live preview via a NIF-based audio engine is architecturally feasible too.

---

## Can the BEAM Do Audio DSP?

**Short answer: Elixir cannot do the sample-rate DSP itself, but it's ideal for everything else.**

### Why the BEAM can't do DSP

- **GC pauses**: The BEAM's per-process garbage collector introduces non-deterministic pauses. At a 128-sample buffer (2.9 ms deadline), even a 1 ms GC pause is catastrophic.
- **Boxed floats**: The BEAM heap-allocates 64-bit floats. Every float operation involves heap allocation. This is ~100–1000x slower than C for tight numerical loops.
- **No SIMD**: No access to SSE/AVX/NEON intrinsics that can process 4–8 samples per clock cycle.
- **Soft real-time scheduler**: Designed for fairness across thousands of processes (millisecond-scale preemption), not for microsecond-scale audio deadlines.

### What the BEAM excels at

- Orchestration, routing, topology management
- Concurrent voice management (each voice = a process, natural fit for polyphony)
- Fault tolerance (crashed voice doesn't take down the ensemble)
- State management, configuration, parameter control
- UI communication (WebSocket-based interfaces, LiveView)
- Event sourcing, scheduling, supervision

### The proven architecture: split-plane design

```
┌─────────────────────────────────────────────┐
│              Elixir / OTP                    │
│  Scheduling, supervision, state management,  │
│  topology, UI, event sourcing                │
│              (control plane)                 │
├─────────────────────────────────────────────┤
│         Rust NIF via Rustler / Port          │
│  Oscillators, filters, envelopes, mixing —   │
│  pre-allocated buffers, dedicated audio       │
│  thread, SIMD vectorization                  │
│              (compute plane)                 │
└─────────────────────────────────────────────┘
```

Elixir sends control messages (note on, set frequency, change filter cutoff) to the Rust engine via a **lock-free ring buffer**. The Rust audio thread reads parameters at the start of each callback. OTP supervises the native engine — if it crashes, restart it.

This is **exactly Liminara's existing architecture**: Elixir/OTP control plane, Ports/containers/NIFs for compute plane. The audio domain is just the most extreme validation of this split.

**Rustler** (Rust NIFs for Erlang/Elixir) is the natural integration tool — well-proven in the Elixir ecosystem (Explorer/Polars, Nx/EXLA) with Rust's solid audio ecosystem (`cpal` for cross-platform audio I/O, `dasp` for DSP primitives, `fundsp` for audio graphs).

---

## Joe Armstrong, Erlang, and Music

Joe Armstrong (1950–2019), co-creator of Erlang, explored exactly this split-plane pattern for music.

### What he did

Armstrong used Erlang as an **orchestration and control layer** communicating with external audio engines via **OSC (Open Sound Control)** — a UDP-based protocol widely used in music software. The architecture:

```
Erlang (sequencing, pattern generation, concurrency)
    → OSC messages over UDP
        → SuperCollider (actual DSP and sound output)
```

He wrote about it on his blog (joearms.github.io, now archived) in posts like "Controlling Sound with Erlang" and "Fun with Erlang and Music." His pragmatic insight: the BEAM is not suitable for sample-rate computation, but Erlang's process model maps **naturally to polyphonic music** — each voice/instrument/track as an independent process, communicating via message passing, supervised for fault tolerance.

### The Sam Aaron bridge

**Sam Aaron**, creator of **Sonic Pi** (the live-coding music tool used in education worldwide), bridges the BEAM and audio communities directly. Sonic Pi uses SuperCollider for DSP and OSC for communication. Aaron created `erlang-osc`, was active in the Erlang community, and he and Armstrong had mutual respect and overlapping interests. Aaron's earlier project **Overtone** (Clojure + SuperCollider) explored similar territory.

### Existing Elixir/Erlang audio ecosystem

| Project | Description |
|---|---|
| **Sonic Pi** | Live-coding music. Erlang internally for OSC networking + SuperCollider for audio |
| **Overtone** | Sam Aaron's Clojure + SuperCollider live-coding environment |
| **`sc_ex_scsyth`** | Elixir bindings for SuperCollider's synthesis server |
| **`ex_osc`** | OSC protocol implementation for Elixir |
| **`midi`** | MIDI message parsing/encoding in Elixir |
| **Phoenix LiveView + Web Audio** | Elixir state management → browser-side DSP via Web Audio API |
| **Nerves + audio** | Embedded Elixir controlling synth hardware via GPIO/MIDI/OSC |

### Relevance to Liminara

Armstrong's architecture (BEAM for orchestration, external engines for heavy computation, messages as the interface) **is** Liminara's architecture. The audio domain confirms that this split-plane pattern is not just viable but arguably ideal for any system where orchestration complexity and computational intensity live in different layers.

OSC is also a potential integration protocol for a Liminara audio pack — speaking OSC to SuperCollider, Pd, or hardware synths would make Liminara an orchestration layer for existing audio tools, not a replacement.

---

## Convergence: Three Independent Paths to the Same Architecture

Armstrong, Puckette, and Farnell reached the same conclusion from different starting points:

| Person | Starting point | Conclusion |
|---|---|---|
| **Puckette** | Real-time computer music at IRCAM | Dataflow graph of typed objects, topologically sorted, with separated control/signal domains and a process supervisor |
| **Farnell** | Procedural audio for games | Composable primitive operations, deterministic + stochastic elements, entity-action decomposition into DAGs, deferred form |
| **Armstrong** | Fault-tolerant telecom systems | Supervised concurrent processes, message passing, control plane separated from compute plane, let-it-crash reliability |

Liminara synthesizes all three: Puckette's dataflow graph model, Farnell's determinism classification and deferred computation, Armstrong's OTP supervision and split-plane architecture. The procedural audio domain is where all three lineages visibly converge.

---

## The Broader Landscape: Visual Dataflow Systems

The DAG-of-operations pattern recurs across many systems beyond audio. Understanding the landscape reveals where Liminara sits and what design choices others have made.

### FAUST — The Most Liminara-Compatible Audio Technology

**FAUST (Functional Audio Stream)** was started in 2002 at GRAME-CNCM (Lyon, France) by Yann Orlarey, Dominique Fober, and Stephane Letz. It is a **purely functional, domain-specific language** for DSP with a mathematically rigorous semantic model:

- **Signals** are discrete functions of time: S: Z → R
- **Signal processors** are second-order functions: functions that map input signals to output signals
- **Composition operators** are third-order functions: functions that combine signal processors

Five composition operators build DSP graphs:

| Operator | Name | What it does |
|---|---|---|
| `:` | Sequential | Output of f feeds input of g |
| `,` | Parallel | f and g process independent signals |
| `<:` | Split | Duplicates f's outputs to g's inputs |
| `:>` | Merge | Sums multiple signals into fewer |
| `~` | Recursive | Creates feedback with implicit one-sample delay |

FAUST compiles to C, C++, **Rust**, LLVM IR, WebAssembly, Java, C#, Julia, and more. The compiler optimizes at the mathematical level — it compiles the *function described*, not the syntax.

**Why FAUST matters most for Liminara:**

1. **Pure functional semantics** → maps to Liminara's `pure` determinism class. Same inputs, same outputs, always.
2. **Compiles to Rust** → FAUST source → Rust code → Rustler NIF → Elixir Op. High-performance DSP without leaving the BEAM ecosystem.
3. **The block diagram algebra IS a DAG** (the `~` operator adds controlled cycles via one-sample delays). FAUST's five operators directly correspond to DAG construction operations.
4. **Content-addressable** → `hash(faust_source + compiler_version + target)` = deterministic output. Perfect for Liminara's caching model.
5. **Embeddable via libfaust** → JIT compilation from within an application. An Op could accept FAUST source as input and produce compiled DSP as output.

No existing project combines FAUST + Rustler + Elixir, but each piece exists independently and the integration path is clear.

### vvvv — Frame-Based Dataflow for Visuals

Created 1998 at MESO (Frankfurt) by Sebastian Oschatz, Max Wolf, and Sebastian Gregor. First public release 2002. A visual dataflow environment originally for large-scale media installations.

Key differences from Pd/Liminara:

- **Frame-based evaluation**: evaluates the *entire* graph every frame (~60 FPS), not demand-driven. Like a game engine main loop.
- **Spreads**: vvvv's signature data type — dynamically-sized arrays that auto-iterate through nodes (implicit parallelism, like NumPy broadcasting at the graph level).
- **Feedback via FrameDelay**: cycles broken by explicit one-frame delay nodes — same pattern as Pd's delwrite~/delread~ and FAUST's `~`.

**vvvv gamma** (2020) is a complete .NET rewrite with static typing, generics, state hot-reload, and multi-threaded async regions. Compiles VL (Visual Language) to C# via Roslyn. Can consume any .NET NuGet package.

Audio is not vvvv's strength — it uses VL.Audio (NAudio-based) and VST3 hosting, but serious audio users integrate Pd or SuperCollider.

### TouchDesigner — Real-Time Installation Art

Created by Greg Hermanovic (Derivative, Toronto, 2000), forked from the Houdini 4.1 codebase. Uses typed operator families (TOP for images, CHOP for audio/control, SOP for geometry, DAT for data, MAT for materials). Frame-based evaluation like vvvv. Commercially dominant for interactive installations and immersive experiences.

### Max/MSP — Gen~ and RNBO

Puckette's original Max, now owned by Ableton. Current version: Max 9. Key recent developments:

- **Gen~**: Sample-level DSP environment compiled to native code at edit time. Single-sample processing (no block-size latency).
- **RNBO** (2022): Export technology — compiles Max/Gen~ patches to VST/AU/AAX plugins, Raspberry Pi, WebAssembly, or C++ source. What you hear while patching is generated from the same compiled code as the export. This represents Max becoming a *compiler*, not just an interpreter.

### SuperCollider — Client/Server via OSC

Created by James McCartney (1996), open-sourced 2002. Three components: **scsynth** (C++ audio server), **sclang** (interpreted language), **scide** (IDE). The key architectural insight: the synthesis server is a standalone process that speaks **OSC**, so it can be controlled from any language — Python, Haskell, Clojure (Overtone), or Elixir (`sc_ex_scsyth`). SynthDefs are unit generator graphs compiled to bytecode.

### Tidal Cycles — Patterns as Temporal Functions

Created by Alex McLean (University of Leeds). A Haskell DSL for algorithmic pattern generation. Patterns are **functions from time spans to event lists** — not sequences but temporal functions that compose via Haskell's type system. Uses SuperCollider (via SuperDirt) for audio. **Strudel** is a JavaScript port running entirely in the browser.

The insight: treating patterns as first-class temporal functions enables transformation (reversal, rotation, symmetry) at the mathematical level.

### ChucK — Strongly-Timed Programming

Created by Ge Wang and Perry Cook (Princeton, ~2003). Makes time a first-class construct — the programmer explicitly advances time with `=>`. Notable for **FaucK** — FAUST integrated into ChucK, bridging functional DSP blocks with temporal orchestration.

### Csound — The Oldest Lineage

Written by Barry Vercoe (MIT, 1985), descended from Max Mathews' MUSIC series (Bell Labs, 1957). Separates **orchestra** (what to compute) from **score** (when to compute it). Csound 7 (2025) adds WebAssembly and bare-metal hardware support.

### Erlang-Red — BEAM Dataflow

An experimental Erlang backend for Node-RED. The author's insight: *"Flow-based programming is done better on the BEAM because FBP is all about message passing of immutable data between concurrent processes."* Has initial Elixir support. Not production-ready but validates the thesis that BEAM's concurrency model is naturally suited to flow-based programming.

### Agent Orchestration Frameworks — How They Handle Loops

Agent frameworks face the iteration problem acutely — an agent's core loop is "think → act → observe → think again."

**LangGraph** (LangChain): Cyclic state graph based on Pregel (Bulk Synchronous Parallel). Conditional edges create explicit cycles between agent and tool nodes. Transactional super-steps. Terminates via conditional edge to END. Each super-step visible in LangSmith. Cost: termination not guaranteed without explicit guards.

**Temporal.io**: Imperative code with durable execution. Workflows contain ordinary `while` loops. Activities (LLM calls, tool use) are non-deterministic but recorded in an Event History. Full deterministic replay by substituting recorded results. Architecturally closest to Liminara's decision-recording philosophy. Constraint: Workflow code must be deterministic.

**Burr** (DAGWorks): Explicit state machine with immutable state. Conditional transitions create cycles naturally. Time-travel debugging via immutable state snapshots. Built-in tracker UI. Philosophically aligned with Liminara's immutable artifacts and event sourcing.

**RuFlo** (ruvnet/ruflo): Swarm coordination for multi-agent software engineering (primarily Claude Code). Queen agent decomposes tasks, delegates via configurable topologies (mesh, hierarchical, ring, star). Q-Learning + Mixture-of-Experts routing. Not graph-based — sophistication is in routing and learning, not formal execution semantics. No replay, no event sourcing.

**AutoGen** (Microsoft): Conversation loop — agents take turns in group chat until termination condition. v0.4 adopted an event-driven actor model internally. Natural for LLM-to-LLM but weak on non-conversational patterns.

**Prefect/Dagster**: Strict DAGs. Iteration via Python loops in flow functions (Prefect) or partition-based re-materialization (Dagster). Guaranteed termination but no native agent loops.

Key insight: the strict DAG camp (Prefect, Dagster) can't express agent loops natively, while the cyclic graph camp (LangGraph, Burr) trades termination guarantees for expressiveness. Temporal sidesteps the debate with imperative code + recorded nondeterminism. Liminara's proposed unrolling model (see Gap 6 below) takes a middle path: strict DAG per-tick, controlled iteration via graph expansion, with full observability.

### Recurring patterns across all these systems

1. **Control/compute split**: Nearly every system separates orchestration from heavy computation. SuperCollider (sclang/scsynth), Tidal (Haskell/SuperDirt), Reaktor (Primary/Core), BEAM + audio engine.
2. **Graph-as-program**: Pd, Max, vvvv, TouchDesigner, FAUST — all represent programs as graphs of operations. The topology IS the program.
3. **Feedback via delay**: Every system handles cycles the same way — an implicit or explicit one-sample (or one-frame) delay. No true algebraic loops allowed.
4. **Two evaluation strategies**: Frame-based (vvvv, TouchDesigner — evaluate everything every tick) vs. demand-driven/event-driven (Pd messages, Tidal, Liminara's topological scheduler).
5. **Strict DAG vs. cyclic graphs**: Data pipeline tools (Prefect, Dagster, Airflow) enforce DAGs. Agent frameworks (LangGraph, Burr) allow cycles. Audio systems allow cycles broken by delay. Temporal avoids the question entirely with imperative code.
6. **FAUST as the natural bridge to Liminara**: Pure functional semantics, Rust compilation, embeddable compiler, block diagram algebra that maps to DAG operations.

---

## Seven Gaps: Where These Systems Expose Liminara's Limitations

The structural parallels between Liminara and audio dataflow systems are real but also easy to overstate — every dataflow system has DAGs, topological scheduling, and composition from primitives. The more valuable question is: **what do these systems do that Liminara doesn't, and should it?**

### Gap 1: No concept of time

Every audio dataflow system treats time as a first-class construct:

- **Pd** has a logical clock advancing in block-sized steps. Control events are timestamped relative to this clock. The two-domain model (message/signal) exists specifically because time behaves differently at different scales.
- **ChucK** makes time the central primitive — `1::second => now` explicitly advances the clock.
- **Tidal** defines patterns as *functions from time spans to event lists* — the most elegant model.
- **FAUST** defines signals as functions from integer time to real values: `S: Z → R`.
- **Csound** separates *orchestra* (what to compute) from *score* (when to compute it) — the earliest explicit temporal decomposition (1985, descended from Mathews 1957).

Liminara has events with timestamps. But there's no concept of temporal relationships *between* ops. No "execute 500ms after parent completes." No time-based scheduling. No temporal patterns. The scheduler is purely dependency-driven.

**Why this matters beyond audio:** Radar needs "run every 6 hours" (Oban covers this). Supply chains need "wait 48 hours for shipping confirmation, then auto-escalate." Consulting workflows need "if no client response within 5 business days, send reminder." These are temporal patterns within a DAG — Oban is a cron scheduler that doesn't understand intra-DAG temporal relationships, and gates require external resolution.

**How other systems do it:** Pd's logical clock decouples computation from wall-clock time — all time references are relative to a block counter, not the system clock. Puckette's textbook states: *"Electronic music computations, if done correctly, are deterministic: two runs of the same computation, each having the same inputs, should have identical results."* This is achieved by keeping all computation referenced to logical time. Tidal goes further — temporal patterns compose algebraically (reversal, rotation, scaling) because they're functions, not schedules.

**What Liminara could borrow:** Not ChucK's strongly-timed model (too specialized). Tidal's insight that temporal patterns are functions is powerful but may be over-engineering. The practical minimum: nodes could declare temporal policies (`after: {:relative, :parent, "48h"}`, `timeout: "5d"`) with auto-resolution strategies. The scheduler would need a time dimension alongside its dependency dimension.

**Pack relevance:** Low for Radar (Oban suffices). Medium for House Compiler. High for future packs with real-world waiting patterns (consulting, supply chain).

### Gap 2: No streaming / continuous data model

Pd's dual-domain model exists because some data is discrete (events/messages) and some is continuous (audio signals). Liminara only has discrete artifacts — an op executes, produces an artifact, done.

**Why this matters:** An LLM generating tokens (you want to show progress), a sensor feed producing data points, a long-running computation with intermediate results — all require some form of continuous data flow. The current architecture forces everything into "execute op → produce artifact." There's no way to observe an op *during* execution except through state-transition events.

**How other systems do it:** Pd has explicit conversion operators between domains: `snapshot~` samples a signal into a message, `sig~` converts a message into a signal. The two domains coexist with well-defined boundaries. vvvv's frame-based evaluation avoids the problem entirely — everything is re-evaluated every frame, so "streaming" is just "the value changes every tick." TouchDesigner's CHOPs (Channel Operators) process continuous data alongside discrete DATs.

**What Liminara could borrow:** The pragmatic solution isn't a streaming artifact type — it's an `emit_progress` callback in the op execution context. Ops can emit progress events via `:pg` during execution. The observation layer picks them up. This solves 90% of the UX problem without architecture changes. A full streaming model (ops producing continuous artifact streams that downstream ops subscribe to) would only be needed for truly continuous inter-op data flow — which none of the current packs require.

**Pack relevance:** Medium for Radar (LLM progress UX). Low for House Compiler. High for Software Factory (agent producing code token-by-token).

### Gap 3: The scheduler has no resource awareness

All ready nodes are dispatched equally. There's no priority, no backpressure, no concurrency limits.

**Why this matters:** Radar fetches 20+ URLs and calls LLMs. Without concurrency limits, you'll hit API rate limits on day one. 200 concurrent HTTP fetches will get you IP-banned. 200 concurrent LLM calls will exhaust your token budget in seconds. This is the only gap that will **block** the first real pack.

**How other systems do it:** Pd's hot/cold inlet system is a priority mechanism — hot inlets trigger computation immediately, cold inlets buffer. Airflow has executor pools with configurable parallelism. Dagster has concurrency limits per op type. Game audio engines use voice pools with priority-based stealing (Farnell describes round-robin allocation for polyphonic bubble synthesis). FAUST's compiler performs automatic parallelization but respects CPU core counts.

**What Liminara could borrow:** Resource pools on the scheduler: `max_concurrent: 5` per op type or per resource tag. Priority levels on nodes (`:high`, `:normal`, `:low`). Rate limiting per external service. The implementation is straightforward — the `find_ready_nodes` function already filters; adding pool-awareness is a predicate check, not an architecture change.

**Pack relevance:** **Blocking for Radar.** Important for House Compiler (memory-intensive NIF ops). Important for Software Factory (LLM rate limits).

### Gap 4: No approximate / draft execution

Liminara's cache is exact-match: `hash(op, version, inputs)` either hits or misses. There's no concept of computing a cheaper version of the same result.

**Why this matters:** Farnell proposes **Level of Audio Detail (LOAD)** — a distant helicopter only needs rotor chop, not the full engine model. The graph itself changes based on relevance. For Liminara: you can't do "quick preview with cheap LLM, full run with expensive LLM" without defining entirely separate ops. You can't do "fast structural estimate for visualization, full Eurocode check for documentation."

**How other systems do it:** Game audio engines have explicit LOD systems — the synthesis model simplifies based on distance/relevance. Pd patches use `switch~` to dynamically enable/disable DSP subgraphs. RNBO compiles the same patch at different quality levels. vvvv gamma has resolution-dependent rendering.

**What Liminara could borrow:** A `fidelity` parameter on ops or runs. An op at `fidelity: :draft` might use a cheaper LLM model, skip validation steps, or use approximation algorithms. Same op name, same interface, different quality/cost tradeoff. The cache key would include the fidelity level: `hash(op, version, inputs, fidelity)`. This enables "preview run in 5 seconds, full run in 5 minutes" without separate op definitions.

**Pack relevance:** Low for Radar (pipeline is short). Medium for House Compiler (structural preview vs. full check). Nice to have, not blocking.

### Gap 5: Pack abstraction is too coarse

Pd's abstraction system has fine-grained composition: subpatches nest arbitrarily deep, $0-scoping provides local namespaces, creation arguments allow parameterization. FAUST has five algebraic composition operators. Reaktor has a two-tier architecture (Primary for routing, Core for compiled DSP). All of these provide composition at multiple scales.

Liminara has Packs. A Pack provides ops and a plan function. That's the coarsest possible abstraction boundary. There's no mechanism for one pack to use another pack's ops, no sub-plans, no shared op libraries.

**Why this matters:** Radar and Software Factory both need "call an LLM and record the decision." Each pack would define its own `llm_summarize` op. There's no shared "LLM op library." As packs multiply, duplicated op definitions accumulate.

**How other systems do it:** Pd has abstraction libraries (`cyclone`, `zexy`, `list-abs`) — collections of reusable patches without a "main program." FAUST has its standard library (`stdfaust.lib`) providing filters, oscillators, effects as composable functions. Max has packages. SuperCollider has Quarks. All provide composition at an intermediate level — more than a single function, less than a complete program.

**What Liminara could borrow:** A "module" level between op and pack — a reusable collection of ops without a plan function. Packs import modules. In practice, this is just a convention: put shared ops in `Liminara.Ops.LLM`, `Liminara.Ops.HTTP`, etc. The runtime doesn't need to change — Elixir's module system already provides this. The gap is conceptual/conventional, not architectural.

**Pack relevance:** Low for one pack. Becomes important with two or more packs sharing op patterns. A workaround (shared Elixir modules) exists today.

### Gap 6: No feedback / iteration primitive

This is the gap where audio systems, agent orchestration frameworks, and FlowTime all converge on the same lesson: **real-world computation is often iterative, and hiding iterations inside opaque nodes sacrifices observability**.

Liminara is a strict DAG — no cycles. The 01_CORE.md proposes a `fixed_point` wrapper for the house compiler's structural/thermal convergence loop. But this hides iterations inside one node — the event log can't see individual iterations, the observation layer can't show convergence progress. This sacrifices Liminara's core value proposition ("the Excel quality — everything visible").

#### Three models for handling cycles

**1. Audio systems: delay-based feedback (DAG per tick, cyclic across ticks)**

FAUST's `~` operator creates feedback with an implicit one-sample delay. Pd's delay lines carry state from block N to block N+1. vvvv's FrameDelay does the same per-frame. The graph is a DAG at any single moment; it's iterative across time steps. Each tick is fully observable.

**2. FlowTime: bin-by-bin ticked evaluation**

FlowTime evaluates the whole graph at tick 0, then tick 1, then tick 2. Within a single tick, evaluation is topological (DAG). Between ticks, outputs from tick N become inputs at tick N+1. The graph itself can be cyclic — Service A feeds Service B feeds Service A — because the time axis breaks the cycle. The same topology evaluates repeatedly; what changes is the state flowing through it. This models steady-state systems over thousands of ticks.

**3. Agent orchestration frameworks: diverse approaches**

| Framework | Execution model | How it handles loops |
|---|---|---|
| **LangGraph** | Cyclic state graph (Pregel/BSP) | First-class cycles via conditional edges. Execution proceeds in transactional super-steps. Agent node → tool node → back to agent. Terminates via conditional edge to END. |
| **Temporal** | Imperative code with durable execution | Native `while` loops in deterministic Workflow code. Activities (LLM calls, tool use) are non-deterministic but recorded in Event History. **Full deterministic replay** — closest to Liminara's philosophy. |
| **Burr** | Explicit state machine, immutable state | Cycles are natural in the state machine. Conditional transitions create loops. Immutable state enables time-travel debugging. |
| **AutoGen** | Conversation loop (actor model) | Group chat IS a loop — agents take turns until termination condition met. |
| **CrewAI** | Role-based task list | No explicit loops. Manager agent can re-delegate failed tasks. |
| **Prefect/Dagster** | Strict DAG | No cycles. Iteration via Python loops submitting new tasks, or via partition-based re-materialization. |
| **RuFlo** | Swarm coordination | Queen agent decomposes tasks with dependency graph. Re-delegation is implicit iteration, not formal cycles. |

The agent frameworks split into two camps:

- **Embrace cycles** (LangGraph, Burr, AutoGen): The graph can loop. Trade deterministic termination for expressiveness. LangGraph's Pregel model provides transactional guarantees per super-step.
- **Imperative with recorded nondeterminism** (Temporal): The orchestration code loops freely; every non-deterministic result is recorded in an Event History for exact replay. This is architecturally closest to Liminara.

#### Why `fixed_point` is insufficient

The `fixed_point` wrapper proposed in 01_CORE.md:

```elixir
Plan.node(:converge, :fixed_point,
  subgraph: [:semantic, :structural, :thermal],
  max_iterations: 3,
  convergence_check: &artifacts_unchanged?/2
)
```

Problems:
- The event log sees one `node_started` and one `node_completed`. Individual iterations are invisible.
- The observation layer can't show "iteration 2 structural check failed, iteration 3 passed."
- You can't replay individual iterations or inspect intermediate artifacts.
- Agent reflection loops (write → test → revise) may run 10+ iterations — hiding all of them in one node is untenable.

#### The preferred model: FAUST-style unrolling

The cleanest model for Liminara is FAUST's `~` operator translated to DAG semantics: **unroll iterations as explicit nodes with full observability**.

When a subgraph is marked as iterative, the scheduler instantiates each iteration as real nodes in the DAG with real events:

```
Iteration 0:                    Iteration 1:                    Iteration 2:
semantic_0 → structural_0       semantic_1 → structural_1       semantic_2 → structural_2
              ↓                               ↓                               ↓
           thermal_0 ──────────→           thermal_1 ──────────→           thermal_2
              ↓                               ↓                               ↓
           converged? NO ────→           converged? NO ────→           converged? YES → done
```

Each iteration is a set of real nodes with real event log entries. The observation layer shows all three iterations. You can inspect `structural_0` vs `structural_1` vs `structural_2`. The convergence check is an explicit node, not hidden logic.

**This preserves:**
- The DAG invariant (no actual cycles — iterations are unrolled)
- Full observability (every iteration is logged and inspectable)
- Replay semantics (decision records from each iteration are available)
- The "Excel quality" — you can see the convergence happening

**Implementation sketch:**
1. A subgraph can be declared `iterative` with a convergence condition and max iterations
2. On first execution, the scheduler instantiates iteration 0's nodes (suffixed `_0`)
3. When iteration 0 completes, the convergence check node evaluates
4. If not converged: the scheduler creates iteration 1's nodes (`_1`) with edges from iteration 0's outputs — this is the "delay" that breaks the cycle, like FAUST's `~`
5. Repeat until converged or max_iterations hit
6. This uses the existing `expand: true` / discovery mode machinery — the scheduler already knows how to add nodes to a running DAG

**Comparison to Temporal:** Temporal records Activity results and replays them. Liminara would record each iteration's artifacts and decisions. Both achieve deterministic replay of iterative processes. But Liminara's approach is declarative (graph topology) while Temporal's is imperative (code flow).

**Comparison to LangGraph:** LangGraph allows cycles natively with Pregel's transactional super-steps. Liminara's unrolling is more conservative — strict DAG per-tick, iteration as controlled graph growth. The tradeoff: LangGraph is more flexible for deeply dynamic agent loops; Liminara's approach is more inspectable and replay-friendly.

**Comparison to FlowTime:** FlowTime evaluates the same graph topology repeatedly over thousands of ticks (simulating a system over time). Liminara's unrolling creates new nodes per iteration (converging in 2-5 ticks). Different use cases: FlowTime models steady-state dynamics; Liminara models convergence of a computation. If you need 10,000 ticks of a cyclic graph, call FlowTime as an op.

**Pack relevance:** Medium for House Compiler (structural/thermal convergence, 2-5 iterations). High for Software Factory (agent loops, 5-50 iterations). Not needed for Radar (linear pipeline).

### Gap 7: "Process maximalism" blind spot

Farnell's procedural models sometimes sound *worse* than recordings. His fire and wind are impressive; his birds and mammals are recognizably synthetic. The book acknowledges this. Real-world game audio uses **hybrid architectures** — procedural for variation, samples for fidelity.

Liminara risks the same trap: making everything an artifact with provenance tracking, determinism classification, and event sourcing when sometimes you just have a file. Not every piece of data benefits from being content-addressed and hash-chained. Reference data, configuration files, intermediate scratch data — wrapping these in the full Liminara machinery adds overhead without adding value.

**How other systems handle it:** Pd has both "cold" data (files loaded once at startup) and "hot" data (signals flowing through the graph). FAUST distinguishes compile-time constants from runtime signals. TouchDesigner has DATs (data tables) that are essentially untracked scratchpads alongside the tracked operator graph. Even Bazel has `genrule` as an escape hatch for things that don't fit the build model.

**What Liminara could borrow:** Make it easy to have plain data alongside tracked artifacts. The Pack `init/0` callback already registers reference data — this is the right pattern. The gap is more philosophical than architectural: resist the temptation to make every op a tracked node in the DAG. Sometimes a helper function that's called inside an op is just a helper function, not a separate op that needs its own event trail.

**Pack relevance:** Low risk for Radar (simple pipeline). Medium risk for House Compiler (reference data, intermediate geometry). The risk grows with pack complexity — over-tracking creates noise that obscures signal in the event log.

### Priority matrix

| Gap | Radar (Phase 5) | House Compiler (Phase 7) | Software Factory | Action |
|---|---|---|---|---|
| #3 Resource pools | Not blocking (linear pipeline) | Important (heavy NIFs) | Important (LLM rate limits) | Defer — add when fan-out creates real concurrency pressure |
| #2 Streaming/progress | UX improvement | Low | High | Add `emit_progress` to op context |
| #1 Time | Covered by Oban | Medium | Medium | Defer until a pack needs intra-DAG time |
| #5 Composition | Workaround exists | Valuable | Valuable | Convention (shared modules), not architecture |
| #4 Approximate execution | Low | Medium | Low | Defer |
| #6 Iteration | Not needed | **Needed** | **Core need** | Design before House Compiler |
| #7 Process maximalism | Low risk | Medium risk | Low risk | Awareness, not a feature |

**Note on resource pools:** Initially assessed as "blocking for Radar," but Radar v1 is a linear pipeline — each node runs after the previous one completes. No fan-out means no concurrent API pressure. If `fetch` needs to rate-limit its internal HTTP calls, that's the op's concern (a `Process.sleep` or internal semaphore), not the scheduler's. Resource pools become important when a pack has massive fan-out (200 parallel nodes hitting the same service), which is not Radar v1. None of the seven gaps block Radar.

---

## Reference: Agentic Algorithm Engineering (AAE)

**Source:** [CHSZLab/AgenticAlgorithmEngineering](https://github.com/CHSZLab/AgenticAlgorithmEngineering), Christian Schulz, Heidelberg University. Based on Sanders (2009) Algorithm Engineering methodology.

AAE deploys Claude Code as an autonomous performance engineer in an indefinite optimization loop: hypothesize → implement → benchmark → evaluate (keep/discard) → repeat. The agent formulates falsifiable hypotheses, implements minimal diffs, runs benchmarks, and keeps improvements. Git commits provide artifact snapshots; a results.tsv provides a primitive decision log.

### Why it matters for Liminara

AAE is a **concrete, working instance of the iteration pattern** (Gap 6). Each cycle is: `recordable` LLM decision (hypothesis + implementation) → `pure` correctness check → `side_effecting` benchmark → `pure` evaluation. On replay with stored decisions, you get the exact optimization trajectory without re-running the LLM or benchmarks.

Three design insights worth capturing:

1. **Hypothesis as structured decision metadata.** AAE requires every experiment to have a falsifiable hypothesis with predicted direction and magnitude ("doubling LR reduces val_bpb; current LR undershoots loss basin"). Liminara's decision records should capture *why*, not just *what* — the hypothesis and prediction alongside the LLM response.

2. **Correctness assertions as gate ops.** Invariant checks before expensive benchmarks. In Liminara: a `pure` validation op gates the `side_effecting` benchmark, saving compute on invalid mutations.

3. **results.tsv validates the event log pattern.** Commit hash, metric, status, hypothesis per experiment — a hand-rolled, fragile version of Liminara's hash-chained event log. Shows the pattern works; shows what formalization gains (integrity, replay, caching, observation).

AAE is not a separate domain pack — it's a use case for the Software Factory pack specialized for algorithm optimization, adjacent to the Evolutionary Factory (`docs/domain_packs/09_Evolutionary_Factory.md`). See that file's appendix for a detailed comparison and potential hybrid design (GA population diversity + LLM-guided mutation).

**See also:** `docs/research/alternative_computation_models.md` for non-DAG models relevant to discovery mode.
