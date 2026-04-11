// versions.mjs — named layout configurations for systematic comparison.
//
// Compact X is the focus — it varies X coordinates (breaks the grid)
// and is the foundation for time-proportional layouts.

export const VERSIONS = {
  // Baseline: original dag-map
  'v0-original': {
    label: 'Original',
    opts: {},
  },

  // Compact X + ordered Y (barycenter crossing reduction)
  'v1-compact-ordered': {
    label: 'Compact+Ordered',
    opts: {
      strategies: {
        orderNodes: 'barycenter',
        reduceCrossings: 'barycenter',
        assignLanes: 'direct',
        positionX: 'compact',
      },
      strategyConfig: { crossingPasses: 24 },
    },
  },

  // Compact X + spectral ordering
  'v2-compact-spectral': {
    label: 'Compact+Spectral',
    opts: {
      strategies: {
        orderNodes: 'spectral',
        reduceCrossings: 'barycenter',
        assignLanes: 'direct',
        positionX: 'compact',
      },
      strategyConfig: { crossingPasses: 24 },
    },
  },

  // Compact X + original BFS lanes (metro aesthetic preserved)
  'v3-compact-classic': {
    label: 'Compact+Classic',
    opts: {
      strategies: {
        positionX: 'compact',
      },
    },
  },

  // Fixed X + ordered Y (grid + crossing reduction)
  'v4-grid-ordered': {
    label: 'Grid+Ordered',
    opts: {
      strategies: {
        orderNodes: 'barycenter',
        reduceCrossings: 'barycenter',
        assignLanes: 'direct',
      },
      strategyConfig: { crossingPasses: 24 },
    },
  },

  // Compact X + ordered Y + coordinate refinement
  'v5-compact-refined': {
    label: 'Compact+Refined',
    opts: {
      strategies: {
        orderNodes: 'barycenter',
        reduceCrossings: 'barycenter',
        assignLanes: 'direct',
        positionX: 'compact',
        refineCoordinates: 'barycenter',
      },
      strategyConfig: { crossingPasses: 24 },
    },
  },
};
