# GA Validation Results — CP-4

## Run Parameters
- Seed: 10000, Generations: 100, Population: 12, Elite: 3
- Genome: 2 continuous (mainSpacing, subSpacing) + 4 categorical strategies
- Fitness: energy functional with overlap + direction_changes terms
- Training fixtures: 34 Tier A+B fixtures

## What the GA Found

### Unanimous convergence on:
- **Lane assignment: `ordered`** — all top-5 elites use it. Validates our design.

### Surprising findings:

| Parameter | GA chose | Our default | Interpretation |
|-----------|----------|-------------|----------------|
| orderNodes | `hybrid` | `barycenter` | Spectral+barycenter blend beats pure barycenter |
| reduceCrossings | `none` | `barycenter` | Hybrid ordering makes crossing reduction redundant |
| mainSpacing | ~26px | 40px | Trunk lanes should be tight |
| subSpacing | ~40px | 25px | Branches should be spread |

### Key insight: spacing inverted
Our defaults had mainSpacing=40 (wide trunk lanes) and subSpacing=25 (tight branches).
The GA flipped this: tight trunk lanes (~26px) with wide branch spacing (~40px).
This makes sense: the trunk is the visual anchor, it should be compact. Branches
need room to spread without overlapping.

## The Evolved Algorithm (explainable)

```
1. Topological sort + layer assignment
2. Hybrid ordering (spectral + barycenter blend)
3. NO crossing reduction (hybrid handles it)
4. Ordered lane assignment (ordering → Y positions)
5. MLCM track assignment at interchange stations (R1-R10)
6. mainSpacing: 26px, subSpacing: 40px
7. Route extraction + rendering (parallel tracks, pills)
```

In words: *"Use hybrid spectral+barycenter ordering with ordered lane assignment.
Skip crossing reduction — the hybrid ordering handles it. Keep trunk lanes tight
(26px) and spread branches wide (40px)."*

## Benchmark
- vs dagre: 32W / 1L (Tier A+B)
- vs ELK: 32W / 1L (Tier A+B)

## Ablation validation
- Removing ordered lanes → fitness degrades significantly
- Removing hybrid → fitness degrades (pure barycenter is worse)
- Adding crossing reduction back → no improvement (confirmed redundant)
