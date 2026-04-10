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

  // Footer
  $('#run-info').textContent = `Run: ${state.runId} | Gen: ${state.generation}`;
  $('#vote-info').textContent = `Votes: ${state.voteCount} (${state.votesSinceLastRefit} since refit)`;
  if (state.currentWeights) {
    const top3 = Object.entries(state.currentWeights)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 4)
      .map(([k, v]) => `${k}:${typeof v === 'number' ? v.toFixed(1) : v}`)
      .join('  ');
    $('#weights-info').textContent = `Top weights: ${top3}`;
  }

  // Pause button
  const pauseBtn = $('#btn-pause');
  pauseBtn.textContent = state.paused ? '▶ Resume' : '⏸ Pause';
  pauseBtn.classList.toggle('paused', state.paused);

  // Shuffle toggle
  const shuffleBtn = $('#btn-shuffle');
  if (shuffleBtn) {
    shuffleBtn.textContent = autoShuffle ? '🔀 Shuffle ON' : '🔀 Shuffle OFF';
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
  'island-optimized': '#4ea8de',
  'island-shuffle': '#16c79a',
  'island-classic': '#f5a623',
};

function renderConvergenceChart(convergence) {
  const container = $('#convergence-chart');
  if (!container || !convergence) return;

  const islands = Object.keys(convergence);
  if (islands.length === 0) { container.innerHTML = ''; return; }

  let maxGen = 0, minFit = Infinity, maxFit = 0;
  for (const key of islands) {
    for (const pt of convergence[key]) {
      if (pt.gen > maxGen) maxGen = pt.gen;
      if (pt.fitness < minFit) minFit = pt.fitness;
      if (pt.fitness > maxFit) maxFit = pt.fitness;
    }
  }
  if (maxGen === 0 || maxFit === minFit) return;

  const w = 700, h = 200, pad = 45;
  const plotW = w - pad * 2, plotH = h - pad * 1.5;
  const scaleX = (gen) => pad + (gen / maxGen) * plotW;
  const scaleY = (fit) => pad / 2 + plotH - ((fit - minFit) / (maxFit - minFit)) * plotH;

  let svg = '<svg width="' + w + '" height="' + h + '" xmlns="http://www.w3.org/2000/svg">';
  svg += '<rect width="' + w + '" height="' + h + '" fill="#111" rx="4"/>';
  svg += '<line x1="' + pad + '" y1="' + (pad/2) + '" x2="' + pad + '" y2="' + (h-pad) + '" stroke="#444" stroke-width="0.5"/>';
  svg += '<line x1="' + pad + '" y1="' + (h-pad) + '" x2="' + (w-pad) + '" y2="' + (h-pad) + '" stroke="#444" stroke-width="0.5"/>';
  svg += '<text x="' + (w/2) + '" y="' + (h-4) + '" text-anchor="middle" fill="#666" font-size="9" font-family="sans-serif">generation</text>';
  svg += '<text x="' + pad + '" y="14" fill="#888" font-size="11" font-family="sans-serif">energy (lower = better)</text>';

  for (const key of islands) {
    const pts = convergence[key];
    if (pts.length < 2) continue;
    const color = ISLAND_COLORS[key] || '#888';
    const d = pts.map((pt, i) => (i === 0 ? 'M' : 'L') + ' ' + scaleX(pt.gen).toFixed(1) + ' ' + scaleY(pt.fitness).toFixed(1)).join(' ');
    svg += '<path d="' + d + '" fill="none" stroke="' + color + '" stroke-width="1.5" stroke-opacity="0.8"/>';
    // Legend entry on the right
    const legendY = 25 + islands.indexOf(key) * 16;
    svg += '<line x1="' + (w - 110) + '" y1="' + legendY + '" x2="' + (w - 90) + '" y2="' + legendY + '" stroke="' + color + '" stroke-width="2"/>';
    svg += '<text x="' + (w - 86) + '" y="' + (legendY + 4) + '" fill="' + color + '" font-size="11" font-family="sans-serif">' + key.replace('island-', '') + '</text>';
  }

  svg += '</svg>';
  container.innerHTML = svg;
}

setupListeners();
loadFixtures().then(() => loadState());
setInterval(loadState, 5000);
