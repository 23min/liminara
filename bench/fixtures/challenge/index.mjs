// Challenge benchmark suite — synthetic graphs designed to stress
// specific layout criteria. Each graph targets a known hard problem.

export const challengeGraphs = [

  // --- Crossing challenges ---
  {
    id: 'cross-forced',
    challenge: 'crossings',
    description: 'Two groups of edges that must cross in any layered layout',
    dag: {
      nodes: [
        { id: 'a1', label: 'a1' }, { id: 'a2', label: 'a2' },
        { id: 'b1', label: 'b1' }, { id: 'b2', label: 'b2' },
        { id: 'c1', label: 'c1' }, { id: 'c2', label: 'c2' },
      ],
      edges: [
        ['a1', 'b1'], ['a1', 'b2'],
        ['a2', 'b1'], ['a2', 'b2'],
        ['b1', 'c1'], ['b1', 'c2'],
        ['b2', 'c1'], ['b2', 'c2'],
      ],
    },
    theme: 'cream', opts: {},
  },

  {
    id: 'cross-bipartite',
    challenge: 'crossings',
    description: 'Complete bipartite K4,4 — maximum crossing density',
    dag: {
      nodes: [
        { id: 's1', label: 's1' }, { id: 's2', label: 's2' },
        { id: 's3', label: 's3' }, { id: 's4', label: 's4' },
        { id: 't1', label: 't1' }, { id: 't2', label: 't2' },
        { id: 't3', label: 't3' }, { id: 't4', label: 't4' },
      ],
      edges: [
        ['s1', 't1'], ['s1', 't2'], ['s1', 't3'], ['s1', 't4'],
        ['s2', 't1'], ['s2', 't2'], ['s2', 't3'], ['s2', 't4'],
        ['s3', 't1'], ['s3', 't2'], ['s3', 't3'], ['s3', 't4'],
        ['s4', 't1'], ['s4', 't2'], ['s4', 't3'], ['s4', 't4'],
      ],
    },
    theme: 'cream', opts: {},
  },

  // --- Fan-in / fan-out ---
  {
    id: 'fan-out-8',
    challenge: 'fan-out',
    description: '1 source diverging to 8 sinks — tests edge separation',
    dag: {
      nodes: [
        { id: 'src', label: 'src' },
        ...Array.from({ length: 8 }, (_, i) => ({ id: `t${i}`, label: `t${i}` })),
      ],
      edges: Array.from({ length: 8 }, (_, i) => ['src', `t${i}`]),
    },
    theme: 'cream', opts: {},
  },

  {
    id: 'fan-in-8',
    challenge: 'fan-in',
    description: '8 sources converging to 1 sink — tests edge overlap',
    dag: {
      nodes: [
        ...Array.from({ length: 8 }, (_, i) => ({ id: `s${i}`, label: `s${i}` })),
        { id: 'sink', label: 'sink' },
      ],
      edges: Array.from({ length: 8 }, (_, i) => [`s${i}`, 'sink']),
    },
    theme: 'cream', opts: {},
  },

  {
    id: 'fan-both',
    challenge: 'fan-in-out',
    description: 'Fan-out then fan-in through a bottleneck',
    dag: {
      nodes: [
        { id: 'src', label: 'src' },
        ...Array.from({ length: 6 }, (_, i) => ({ id: `m${i}`, label: `m${i}` })),
        { id: 'sink', label: 'sink' },
      ],
      edges: [
        ...Array.from({ length: 6 }, (_, i) => ['src', `m${i}`]),
        ...Array.from({ length: 6 }, (_, i) => [`m${i}`, 'sink']),
      ],
    },
    theme: 'cream', opts: {},
  },

  // --- Wide layers ---
  {
    id: 'wide-15',
    challenge: 'wide-layer',
    description: '1 → 15 → 1 — extremely wide middle layer',
    dag: {
      nodes: [
        { id: 'in', label: 'in' },
        ...Array.from({ length: 15 }, (_, i) => ({ id: `w${i}`, label: `w${i}` })),
        { id: 'out', label: 'out' },
      ],
      edges: [
        ...Array.from({ length: 15 }, (_, i) => ['in', `w${i}`]),
        ...Array.from({ length: 15 }, (_, i) => [`w${i}`, 'out']),
      ],
    },
    theme: 'cream', opts: {},
  },

  // --- Parallel paths ---
  {
    id: 'parallel-4',
    challenge: 'parallel-paths',
    description: '4 independent parallel paths of length 5 — tests edge coincidence',
    dag: {
      nodes: [
        { id: 'start', label: 'start' },
        ...Array.from({ length: 4 }, (_, p) =>
          Array.from({ length: 4 }, (_, s) => ({ id: `p${p}s${s}`, label: `p${p}s${s}` }))
        ).flat(),
        { id: 'end', label: 'end' },
      ],
      edges: [
        ...Array.from({ length: 4 }, (_, p) => ['start', `p${p}s0`]),
        ...Array.from({ length: 4 }, (_, p) =>
          Array.from({ length: 3 }, (_, s) => [`p${p}s${s}`, `p${p}s${s + 1}`])
        ).flat(),
        ...Array.from({ length: 4 }, (_, p) => [`p${p}s3`, 'end']),
      ],
    },
    theme: 'cream', opts: {},
  },

  // --- Diamond chain (symmetry) ---
  {
    id: 'diamond-chain-3',
    challenge: 'symmetry',
    description: '3 chained diamonds — tests symmetry preservation',
    dag: {
      nodes: [
        { id: 'd0', label: 'd0' },
        { id: 'd1a', label: 'd1a' }, { id: 'd1b', label: 'd1b' },
        { id: 'd2', label: 'd2' },
        { id: 'd3a', label: 'd3a' }, { id: 'd3b', label: 'd3b' },
        { id: 'd4', label: 'd4' },
        { id: 'd5a', label: 'd5a' }, { id: 'd5b', label: 'd5b' },
        { id: 'd6', label: 'd6' },
      ],
      edges: [
        ['d0', 'd1a'], ['d0', 'd1b'],
        ['d1a', 'd2'], ['d1b', 'd2'],
        ['d2', 'd3a'], ['d2', 'd3b'],
        ['d3a', 'd4'], ['d3b', 'd4'],
        ['d4', 'd5a'], ['d4', 'd5b'],
        ['d5a', 'd6'], ['d5b', 'd6'],
      ],
    },
    theme: 'cream', opts: {},
  },

  // --- Deep narrow ---
  {
    id: 'deep-20',
    challenge: 'deep',
    description: '20-node chain — tests horizontal stretch',
    dag: {
      nodes: Array.from({ length: 20 }, (_, i) => ({ id: `n${i}`, label: `n${i}` })),
      edges: Array.from({ length: 19 }, (_, i) => [`n${i}`, `n${i + 1}`]),
    },
    theme: 'cream', opts: {},
  },

  // --- Dense ---
  {
    id: 'dense-20',
    challenge: 'dense',
    description: '20 nodes with ~50 edges — everything at once',
    dag: (() => {
      const nodes = Array.from({ length: 20 }, (_, i) => ({ id: `n${i}`, label: `n${i}` }));
      const edges = [];
      // Every node connects to the next 2-3 nodes (ensuring DAG via i < j)
      for (let i = 0; i < 20; i++) {
        for (let j = i + 1; j < Math.min(i + 4, 20); j++) {
          if (edges.length < 55) edges.push([`n${i}`, `n${j}`]);
        }
      }
      return { nodes, edges };
    })(),
    theme: 'cream', opts: {},
  },
];
