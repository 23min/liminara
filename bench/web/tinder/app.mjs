// app.mjs — Tinder UI client for dag-map bench.

const $ = (sel) => document.querySelector(sel);

let state = null;
let fixtureList = [];
let currentFixture = null;
let autoShuffle = true; // rotate fixture on each vote

async function fetchJSON(url, opts = {}) {
  const res = await fetch(url, {
    headers: { 'content-type': 'application/json', ...opts.headers },
    ...opts,
  });
  return res.json();
}

async function loadFixtures() {
  try {
    const data = await fetchJSON('/fixtures');
    fixtureList = data.fixtures || [];
    if (fixtureList.length > 0 && !currentFixture) {
      currentFixture = fixtureList[Math.floor(Math.random() * fixtureList.length)];
    }
    renderFixtureSelector();
  } catch (err) {
    console.error('Failed to load fixtures:', err);
  }
}

function nextFixture() {
  if (fixtureList.length === 0) return;
  if (autoShuffle) {
    currentFixture = fixtureList[Math.floor(Math.random() * fixtureList.length)];
    const sel = $('#fixture-select');
    if (sel) sel.value = currentFixture;
  }
}

function renderFixtureSelector() {
  const sel = $('#fixture-select');
  if (!sel) return;
  sel.innerHTML = '';
  for (const f of fixtureList) {
    const opt = document.createElement('option');
    opt.value = f;
    opt.textContent = f;
    if (f === currentFixture) opt.selected = true;
    sel.appendChild(opt);
  }
}

async function loadState() {
  try {
    state = await fetchJSON('/state');
    render();
  } catch (err) {
    $('#status').textContent = `Error: ${err.message}`;
  }
}

function render() {
  if (!state) return;
  try { _render(); } catch (e) { console.error('render error:', e); }
}

function _render() {

  // Status — show running/paused/done clearly
  const statusEl = $('#status');
  if (state.done) {
    statusEl.textContent = `DONE (gen ${state.generation})`;
    statusEl.style.color = '#6c6';
  } else if (state.paused) {
    statusEl.textContent = `PAUSED at gen ${state.generation}`;
    statusEl.style.color = '#e94560';
  } else {
    statusEl.textContent = `RUNNING — gen ${state.generation}`;
    statusEl.style.color = '#6c9';
  }

  // Fixture name
  const fixLabel = $('#current-fixture');
  if (fixLabel) fixLabel.textContent = currentFixture || '?';

  // Convergence chart
  renderConvergenceChart(state.convergence);

  // Stats panel (with null checks)
  const setTextSafe = (sel, val) => { const el = $(sel); if (el) el.textContent = val; };
  setTextSafe('#stat-gen', state.generation);
  setTextSafe('#stat-votes', state.voteCount);
  setTextSafe('#stat-refit', state.votesSinceLastRefit);

  if (state.convergence) {
    let best = Infinity;
    for (const pts of Object.values(state.convergence)) {
      if (pts.length > 0) {
        const last = pts[pts.length - 1].fitness;
        if (last < best) best = last;
      }
    }
    setTextSafe('#stat-best', best < Infinity ? best.toFixed(0) : '—');
  }

  // Footer
  setTextSafe('#run-info', `Run: ${state.runId} | Gen: ${state.generation}`);
  if (state.currentWeights) {
    const top3 = Object.entries(state.currentWeights)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 4)
      .map(([k, v]) => `${k}:${typeof v === 'number' ? v.toFixed(1) : v}`)
      .join('  ');
    setTextSafe('#weights-info', `Top weights: ${top3}`);
  }

  // Pause button
  const pauseBtn = $('#btn-pause');
  pauseBtn.textContent = state.paused ? '▶ Resume' : '⏸ Pause';
  pauseBtn.classList.toggle('paused', state.paused);

  // Shuffle toggle
  const shuffleBtn = $('#btn-shuffle');
  if (shuffleBtn) {
    shuffleBtn.textContent = autoShuffle ? '🔀 ON' : '🔀 OFF';
    shuffleBtn.classList.toggle('active', autoShuffle);
  }

  // Pair display
  if (!state.pair) {
    $('#pair').classList.add('hidden');
    $('#no-pair').classList.remove('hidden');
    return;
  }

  $('#no-pair').classList.add('hidden');
  $('#pair').classList.remove('hidden');

  const { left, right } = state.pair;
  const islandLabel = (ind) => {
    const island = ind.island || '';
    return island.replace('island-', '').toUpperCase() || ind.id;
  };
  $('#left-label').textContent = `${islandLabel(left)} (${left.fitness?.toFixed(1) ?? '?'})`;
  $('#right-label').textContent = `${islandLabel(right)} (${right.fitness?.toFixed(1) ?? '?'})`;

  // Strategy info
  const stratStr = (s) => {
    if (!s) return 'defaults';
    return [
      s['strategy.orderNodes'] !== 'none' ? `order:${s['strategy.orderNodes']}` : '',
      s['strategy.reduceCrossings'] !== 'none' ? `cross:${s['strategy.reduceCrossings']}` : '',
      s['strategy.assignLanes'] !== 'default' ? `lanes:${s['strategy.assignLanes']}` : '',
      s['strategy.positionX'] !== 'fixed' ? `xPos:${s['strategy.positionX']}` : '',
      s['strategy.refineCoordinates'] !== 'none' ? `refine:${s['strategy.refineCoordinates']}` : '',
    ].filter(Boolean).join(' ') || 'defaults';
  };
  const leftInfo = $('#left-strategy');
  const rightInfo = $('#right-strategy');
  if (leftInfo) leftInfo.textContent = stratStr(left.genome?.strategy);
  if (rightInfo) rightInfo.textContent = stratStr(right.genome?.strategy);

  // Load SVGs
  if (currentFixture) {
    loadSvg('left-svg', left.id, currentFixture);
    loadSvg('right-svg', right.id, currentFixture);
  }
}

async function loadSvg(containerId, individualId, fixtureId) {
  const container = $(`#${containerId}`);
  const url = `/svg/${individualId}/${fixtureId}`;
  try {
    const res = await fetch(url);
    if (res.ok) {
      container.innerHTML = await res.text();
    } else {
      const err = await res.text();
      container.innerHTML = `<div style="padding:2rem;color:#f66;text-align:center;font-size:0.9rem">${err}</div>`;
    }
  } catch (e) {
    container.innerHTML = `<div style="padding:2rem;color:#f66;text-align:center">${e.message}</div>`;
  }
}

async function vote(winner) {
  if (!state?.pair) return;
  try {
    const res = await fetchJSON('/vote', {
      method: 'POST',
      body: JSON.stringify({
        left_id: state.pair.left.id,
        right_id: state.pair.right.id,
        winner,
      }),
    });
    if (res.pair !== undefined) {
      state.pair = res.pair;
    } else {
      state.pair = null;
    }
    state.voteCount = (state.voteCount ?? 0) + 1;
    state.votesSinceLastRefit = (state.votesSinceLastRefit ?? 0) + 1;
    // Rotate fixture for next comparison
    nextFixture();
    render();
  } catch (err) {
    $('#status').textContent = `Vote error: ${err.message}`;
  }
}

async function control(action, extraFields = {}) {
  try {
    const res = await fetchJSON('/control', {
      method: 'POST',
      body: JSON.stringify({ action, ...extraFields }),
    });
    if (res.paused !== undefined) state.paused = res.paused;
    render();
  } catch (err) {
    $('#status').textContent = `Control error: ${err.message}`;
  }
}

function getSelectedId(side) {
  if (!state?.pair) return null;
  return side === 'left' ? state.pair.left.id : state.pair.right.id;
}

function setupListeners() {
  $('#btn-left').addEventListener('click', () => vote('left'));
  $('#btn-right').addEventListener('click', () => vote('right'));
  $('#btn-tie').addEventListener('click', () => vote('tie'));
  $('#btn-skip').addEventListener('click', () => { nextFixture(); loadState(); });

  $('#fixture-select')?.addEventListener('change', (e) => {
    currentFixture = e.target.value;
    autoShuffle = false;
    const shuffleBtn = $('#btn-shuffle');
    if (shuffleBtn) shuffleBtn.textContent = '🔀 Shuffle OFF';
    render();
  });

  $('#btn-shuffle')?.addEventListener('click', () => {
    autoShuffle = !autoShuffle;
    render();
  });

  $('#btn-pause').addEventListener('click', () => {
    control(state?.paused ? 'resume' : 'pause');
  });
  $('#btn-protect-left').addEventListener('click', () => {
    const id = getSelectedId('left');
    if (id) control('protect', { id });
  });
  $('#btn-protect-right').addEventListener('click', () => {
    const id = getSelectedId('right');
    if (id) control('protect', { id });
  });
  $('#btn-kill-left').addEventListener('click', () => {
    const id = getSelectedId('left');
    if (id) control('kill', { id });
  });
  $('#btn-kill-right').addEventListener('click', () => {
    const id = getSelectedId('right');
    if (id) control('kill', { id });
  });

  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
    switch (e.key) {
      case 'ArrowLeft':  e.preventDefault(); vote('left'); break;
      case 'ArrowRight': e.preventDefault(); vote('right'); break;
      case 'ArrowDown':  e.preventDefault(); vote('tie'); break;
      case ' ':          e.preventDefault(); vote('skip'); break;
    }
  });
}

// Convergence chart

const ISLAND_COLORS = {
  'island-raw': '#f85149',
  'island-refined': '#3fb950',
  'island-spectral': '#58a6ff',
};

function downsample(pts, maxPoints) {
  if (pts.length <= maxPoints) return pts;
  const step = Math.ceil(pts.length / maxPoints);
  const result = [];
  for (let i = 0; i < pts.length; i += step) {
    result.push(pts[i]);
  }
  if (result[result.length - 1] !== pts[pts.length - 1]) {
    result.push(pts[pts.length - 1]);
  }
  return result;
}

function renderConvergenceChart(convergence) {
  const container = $('#convergence-chart');
  if (!container || !convergence) return;

  const islands = Object.keys(convergence);
  if (islands.length === 0) { container.innerHTML = ''; return; }

  // Find data bounds (use actual min/max, not starting at 0)
  let maxGen = 0, minFit = Infinity, maxFit = -Infinity;
  for (const key of islands) {
    for (const pt of convergence[key]) {
      if (pt.gen > maxGen) maxGen = pt.gen;
      if (pt.fitness < minFit) minFit = pt.fitness;
      if (pt.fitness > maxFit) maxFit = pt.fitness;
    }
  }
  if (maxGen === 0) return;

  // Add 5% padding to Y range
  const fitRange = maxFit - minFit || 1;
  minFit -= fitRange * 0.05;
  maxFit += fitRange * 0.05;

  const w = 520, h = 150, pad = 45, padRight = 130;
  const plotW = w - pad - padRight, plotH = h - 50;
  const plotTop = 25;

  const scaleX = (gen) => pad + (gen / Math.max(maxGen, 1)) * plotW;
  const scaleY = (fit) => plotTop + plotH - ((fit - minFit) / (maxFit - minFit)) * plotH;

  let svg = '<svg width="' + w + '" height="' + h + '" xmlns="http://www.w3.org/2000/svg">';
  svg += '<rect width="' + w + '" height="' + h + '" fill="#0d1117" rx="6"/>';

  // Grid lines
  for (let i = 0; i <= 4; i++) {
    const gy = plotTop + (i / 4) * plotH;
    svg += '<line x1="' + pad + '" y1="' + gy + '" x2="' + (pad + plotW) + '" y2="' + gy + '" stroke="#21262d" stroke-width="0.5"/>';
    const val = maxFit - (i / 4) * (maxFit - minFit);
    svg += '<text x="' + (pad - 4) + '" y="' + (gy + 3) + '" text-anchor="end" fill="#484f58" font-size="8" font-family="sans-serif">' + (val >= 1000 ? (val/1000).toFixed(0) + 'k' : val.toFixed(0)) + '</text>';
  }

  // Axes
  svg += '<line x1="' + pad + '" y1="' + plotTop + '" x2="' + pad + '" y2="' + (plotTop + plotH) + '" stroke="#30363d" stroke-width="1"/>';
  svg += '<line x1="' + pad + '" y1="' + (plotTop + plotH) + '" x2="' + (pad + plotW) + '" y2="' + (plotTop + plotH) + '" stroke="#30363d" stroke-width="1"/>';

  // Labels
  svg += '<text x="' + (pad + plotW/2) + '" y="' + (h - 4) + '" text-anchor="middle" fill="#484f58" font-size="9" font-family="sans-serif">generation</text>';
  svg += '<text x="' + pad + '" y="14" fill="#8b949e" font-size="10" font-family="sans-serif">Energy (lower = better)</text>';
  svg += '<text x="' + (pad + plotW) + '" y="14" text-anchor="end" fill="#484f58" font-size="9" font-family="sans-serif">gen ' + maxGen + '</text>';

  // Lines — downsample to 120 points max for smooth rendering
  for (const key of islands) {
    const raw = convergence[key];
    if (raw.length < 2) continue;
    const pts = downsample(raw, 120);
    const color = ISLAND_COLORS[key] || '#8b949e';
    const d = pts.map((pt, i) => (i === 0 ? 'M' : 'L') + ' ' + scaleX(pt.gen).toFixed(1) + ' ' + scaleY(pt.fitness).toFixed(1)).join(' ');
    svg += '<path d="' + d + '" fill="none" stroke="' + color + '" stroke-width="2" stroke-opacity="0.9" stroke-linejoin="round"/>';

    // Current value dot at end
    const last = pts[pts.length - 1];
    svg += '<circle cx="' + scaleX(last.gen).toFixed(1) + '" cy="' + scaleY(last.fitness).toFixed(1) + '" r="3" fill="' + color + '"/>';

    // Legend on the right
    const legendY = plotTop + 8 + islands.indexOf(key) * 20;
    svg += '<line x1="' + (w - padRight + 8) + '" y1="' + legendY + '" x2="' + (w - padRight + 28) + '" y2="' + legendY + '" stroke="' + color + '" stroke-width="2.5" stroke-linecap="round"/>';
    svg += '<circle cx="' + (w - padRight + 18) + '" cy="' + legendY + '" r="3" fill="' + color + '"/>';
    svg += '<text x="' + (w - padRight + 34) + '" y="' + (legendY + 4) + '" fill="' + color + '" font-size="11" font-weight="500" font-family="sans-serif">' + key.replace('island-', '') + '</text>';
    svg += '<text x="' + (w - padRight + 34) + '" y="' + (legendY + 15) + '" fill="#484f58" font-size="9" font-family="sans-serif">' + last.fitness.toFixed(0) + '</text>';
  }

  svg += '</svg>';
  container.innerHTML = svg;
}

setupListeners();
loadFixtures().then(() => loadState());
setInterval(loadState, 1500);
