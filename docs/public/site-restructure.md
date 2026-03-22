# Proliminal.net — Site Restructure Prompt

> Use this document as a prompt when restructuring the Astro site.
> It describes the new navigation, page structure, content placement, and rationale.

---

## New navigation

```
Services | Lab | Work | About | Contact
```

Five items. Consulting first, research second, credibility third, person fourth.

### What changed from the current structure

| Current | New | What happened |
|---------|-----|---------------|
| Services | **Services** | Stays. Absorbs Approach (methodology becomes part of how you describe services, not a standalone page). |
| Work | **Work** | Stays, but now strictly past/current client projects and engagements (track record, credibility). |
| About | **About** | Stays. Absorbs VOODOO as discoverable content within the page (see below). |
| Approach | *(folded into Services)* | The Understand → Transform → Emerge methodology becomes a section within Services. It describes *how* you work, which is part of the service offering. |
| VOODOO | *(folded into About)* | Becomes a section or linked sub-page within About. Still prominent for curious visitors, but not competing for top-nav space with the business. The liminality concept connects naturally to the About narrative. |
| Contact | **Contact** | Stays as-is. |
| *(new)* | **Lab** | New top-level section. Applied research, prototypes, explorations. The Liminara ecosystem. |

---

## Lab — the new section

### What it is

Applied research and prototypes. Tools and ideas being forged in active use — not academic research, not finished products. Things being built that inform consulting work and may become products.

The tagline for Lab could be something like:

> "Applied research at the boundary between consulting insight and working software."

or simply:

> "Prototypes, explorations, and tools in active development."

### URL structure

```
/lab                          ← Lab landing page (overview of all explorations)
/lab/liminara                 ← Liminara overview (the runtime)
/lab/provenance               ← Position paper: "Provenance for the Prove It Era"
/lab/foundations/              ← Packs that prove the architecture
/lab/foundations/radar
/lab/foundations/house-compiler
/lab/foundations/flowtime
/lab/foundations/process-mining
/lab/foundations/software-factory
/lab/foundations/lodetime
/lab/compliance/              ← EU regulatory compliance packs
/lab/compliance/vsme
/lab/compliance/dpp
/lab/compliance/eudr
/lab/compliance/battery-passport
/lab/compliance/cbam
/lab/horizons/                ← Future research directions
/lab/horizons/agent-fleets
/lab/horizons/population-sim
/lab/horizons/behavior-dsl
/lab/horizons/evolutionary-factory
```

### Lab landing page (/lab)

The landing page should show all explorations organized by category, with a brief introduction explaining what the Lab is. Each exploration gets a card with:

- Title
- The research question (the bold line from each pack entry)
- Status tag (Active development / Research / Far horizon)
- Category tag (Foundations / Compliance / Horizons)

The Liminara card should be visually distinguished (larger, or pinned at top) since it's the runtime that all packs build on.

### Content source files

All content for Lab pages lives in `/docs/public/` in the Liminara repo:

```
docs/public/
├── proliminal-liminara-work-entry.md    → /lab/liminara
├── proliminal-provenance-page.md        → /lab/provenance
├── vsme-pipeline.svg                    → used by /lab/compliance/vsme
├── foundations/
│   ├── radar.md                         → /lab/foundations/radar
│   ├── house-compiler.md                → /lab/foundations/house-compiler
│   ├── flowtime.md                      → /lab/foundations/flowtime
│   ├── process-mining.md                → /lab/foundations/process-mining
│   ├── software-factory.md              → /lab/foundations/software-factory
│   └── lodetime.md                      → /lab/foundations/lodetime
├── compliance/
│   ├── vsme.md                          → /lab/compliance/vsme
│   ├── dpp.md                           → /lab/compliance/dpp
│   ├── eudr.md                          → /lab/compliance/eudr
│   ├── battery-passport.md              → /lab/compliance/battery-passport
│   └── cbam.md                          → /lab/compliance/cbam
└── horizons/
    ├── agent-fleets.md                  → /lab/horizons/agent-fleets
    ├── population-sim.md                → /lab/horizons/population-sim
    ├── behavior-dsl.md                  → /lab/horizons/behavior-dsl
    └── evolutionary-factory.md          → /lab/horizons/evolutionary-factory
```

---

## Services — absorbing Approach

The current Approach page describes a three-phase methodology: Understand → Transform → Emerge. This should become a section within the Services page (or a clearly linked sub-section), not a standalone nav item.

Suggested structure for the Services page:

1. **Brief intro** — what you do (the current hero text)
2. **Service areas** — the six current offerings (AI Integration, Performance Engineering, Systems & Observability, UX & Usability, Distributed Systems, Transformation Guidance)
3. **How I work** — the Understand → Transform → Emerge methodology (currently the Approach page content). This is the "why hire me" section — it shows a thoughtful, structured approach.
4. **From Lab to practice** — a brief note connecting the Lab explorations to consulting value. Something like: "The tools and methods in the Lab aren't theoretical — they inform how I approach client work. Provenance thinking shapes how I design audit trails. Flow modeling informs performance analysis. The same architectural rigor applies to consulting engagements."

---

## About — absorbing VOODOO

The About page currently covers background, experience, and philosophy. VOODOO (the liminality concept and the origin of the Proliminal name) should become part of this page rather than a standalone nav item.

Suggested structure:

1. **Who I am** — the current About content (30+ years, ex-Microsoft, USA/Netherlands/Sweden, etc.)
2. **The name** — VOODOO content. Why "Proliminal." The liminality concept. This is the philosophical foundation. It should feel like a reward for reading further, not the first thing a new visitor sees. A section heading like "About the name" or "Why Proliminal" works.
3. Optionally, a subtle visual or interactive element that makes the VOODOO section feel special — it's the personality of the brand.

The current standalone URL (`/about-the-name/`) can redirect to the About page with an anchor (`/about#the-name`) so existing links don't break.

---

## Work — past projects and track record

The Work section becomes strictly about delivered work and client engagements. This is the credibility page — proof that you ship.

Current Work entries (Biometria, etc.) stay here. Liminara moves to Lab. LodeTime moves to Lab (as a pack). FlowTime appears in both:
- **Work**: the FlowTime project itself (what it is, what was built, the history)
- **Lab**: the FlowTime Integration pack (how FlowTime connects to Liminara as an exploration)

---

## Visual/UX notes

- **Lab cards should show status clearly.** Use subtle tags or color coding:
  - Active development (Radar, House Compiler, Observation layer)
  - Research (VSME, DPP, EUDR, Software Factory, etc.)
  - Far horizon (Agent Fleets, Population Sim, etc.)

- **The three Lab categories** (Foundations, Compliance, Horizons) could be visually grouped on the landing page — three rows or three columns with distinct headers.

- **Each pack page** follows a consistent layout:
  - Title + research question
  - Status/tags bar
  - The scenario (fictional Swedish company)
  - The pipeline (ASCII art or SVG diagram)
  - "What you can ask afterward" table
  - Before/after comparison
  - Contact CTA

- **The provenance position paper** (`/lab/provenance`) is the anchor piece — it should be linkable from LinkedIn and work as a standalone read. Good Open Graph meta tags (title, description, image) for social sharing.

- **Swedish translation** is a future step. The regulatory terminology needs careful human translation (hållbarhetsrapportering, värdekedjan, spårbarhet, beviskedja), not machine translation.

---

## Summary of navigation flow

```
A visitor arrives at proliminal.net

→ Services: "Here's what I do for clients"
   └── includes methodology (Understand → Transform → Emerge)
   └── connects to Lab ("these explorations inform my consulting")

→ Lab: "Here's what I'm building and researching"
   └── Liminara (the runtime)
   └── Provenance thesis (the position paper)
   └── 15 domain explorations in 3 categories
   └── each with concrete scenarios and "what you can ask"

→ Work: "Here's what I've delivered"
   └── Biometria, past engagements, track record

→ About: "Here's who I am"
   └── background, experience, philosophy
   └── VOODOO / the name (discoverable, delightful)

→ Contact: "Let's talk"
```

A consulting prospect follows: Services → Work → Contact.
A potential collaborator follows: Lab → Provenance → specific pack → Contact.
A curious technologist follows: Lab → About → VOODOO.

All paths lead to Contact.
