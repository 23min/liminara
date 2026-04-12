// versions.mjs — named layout configurations for systematic comparison.
//
// Simplified: removed spectral (identical to barycenter) and refined
// (no visible difference). Added GA-validated configuration.

export const VERSIONS = {
  // Baseline: original dag-map (BFS lanes, no ordering)
  'v0-original': {
    label: 'Original',
    opts: {},
  },

  // Compact X + BFS lanes (compact X only, no ordering)
  'v1-compact-classic': {
    label: 'Compact+Classic',
    opts: {
      strategies: { positionX: 'compact' },
    },
  },

  // Compact X + barycenter ordering + crossing reduction
  'v2-compact-ordered': {
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

  // GA-validated: hybrid ordering, no crossing reduction, ordered lanes
  'v3-ga-evolved': {
    label: 'GA Evolved',
    opts: {
      strategies: {
        orderNodes: 'hybrid',
        reduceCrossings: 'none',
        assignLanes: 'ordered',
        positionX: 'compact',
      },
      mainSpacing: 26,
      subSpacing: 40,
    },
  },

  // Compact X + route-aware crossing reduction
  'v3b-route-aware': {
    label: 'Route-Aware',
    opts: {
      strategies: {
        orderNodes: 'barycenter',
        reduceCrossings: 'route-aware',
        assignLanes: 'direct',
        positionX: 'compact',
      },
      strategyConfig: { crossingPasses: 12 },
    },
  },

  // Grid X + ordered (for comparison — shows compact X benefit)
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
};
