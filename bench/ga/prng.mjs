// prng.mjs — deterministic, splittable PRNG used by every GA operator.
//
// Core: mulberry32 over a single uint32 state. Fast, reproducible, and
// trivial to clone. Every stochastic GA operator takes an explicit PRNG
// instance so seeding is a first-class concern, not an accident of
// import order.
//
// API:
//   const r = createPrng(seed)
//   r.next()           -> uint32
//   r.nextFloat()      -> [0, 1)
//   r.nextInt(lo, hi)  -> integer in [lo, hi] (both inclusive)
//   r.nextGaussian(mu, sigma)
//   r.pick(array)      -> uniformly chosen element
//   r.clone()          -> independent PRNG at the same state
//   r.fork(label)      -> independent PRNG derived from (seed, label)
//   r.getState()       -> snapshot (plain object)
//   r.setState(s)      -> restore snapshot
//
// No Math.random. No Date.now. Fork() uses a simple FNV-like mix of the
// current state and the label bytes, so the same (parent-state, label)
// pair always yields the same child seed.

const UINT32 = 0x1_0000_0000;

function mulberry32(state) {
  let s = state >>> 0;
  function next() {
    s = (s + 0x6D2B79F5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0);
  }
  return {
    next,
    get state() {
      return s;
    },
    set state(v) {
      s = v >>> 0;
    },
  };
}

function hashLabel(state, label) {
  // FNV-1a-flavored mix of the current state and the label string.
  let h = (state ^ 0x811c9dc5) >>> 0;
  for (let i = 0; i < label.length; i++) {
    h ^= label.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  // Final avalanche so single-character labels still scramble well.
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b) >>> 0;
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35) >>> 0;
  h ^= h >>> 16;
  return h >>> 0;
}

export function createPrng(seed) {
  const core = mulberry32(seed >>> 0);

  function next() {
    return core.next();
  }

  function nextFloat() {
    return core.next() / UINT32;
  }

  function nextInt(lo, hi) {
    if (hi < lo) throw new Error(`nextInt: hi (${hi}) < lo (${lo})`);
    const range = hi - lo + 1;
    return lo + Math.floor(nextFloat() * range);
  }

  function nextGaussian(mu = 0, sigma = 1) {
    // Box-Muller. Each call consumes two uniforms and discards the second
    // sample so state stays trivially snapshotable.
    let u1 = nextFloat();
    if (u1 < 1e-12) u1 = 1e-12;
    const u2 = nextFloat();
    const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
    return mu + sigma * z;
  }

  function pick(array) {
    if (!Array.isArray(array) || array.length === 0) {
      throw new Error('pick: array is empty');
    }
    return array[nextInt(0, array.length - 1)];
  }

  function clone() {
    return createPrngFromState(core.state);
  }

  function fork(label) {
    if (typeof label !== 'string' || label.length === 0) {
      throw new Error('fork: label must be a non-empty string');
    }
    const childSeed = hashLabel(core.state, label);
    return createPrng(childSeed);
  }

  function getState() {
    return { state: core.state };
  }

  function setState(snapshot) {
    if (!snapshot || typeof snapshot.state !== 'number') {
      throw new Error('setState: expected { state: uint32 }');
    }
    core.state = snapshot.state;
  }

  return { next, nextFloat, nextInt, nextGaussian, pick, clone, fork, getState, setState };
}

function createPrngFromState(state) {
  const r = createPrng(0);
  r.setState({ state });
  return r;
}
