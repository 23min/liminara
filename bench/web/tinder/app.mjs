// app.mjs — Tinder UI client for dag-map bench.
// No build step. Loaded as an ES module from index.html.

const $ = (sel) => document.querySelector(sel);

let state = null;
let selectedSide = null; // 'left' or 'right' for protect/kill targeting

async function fetchJSON(url, opts = {}) {
  const res = await fetch(url, {
    headers: { 'content-type': 'application/json', ...opts.headers },
    ...opts,
  });
  return res.json();
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

  // Status
  $('#status').textContent = state.paused ? 'PAUSED' : `Gen ${state.generation}`;

  // Footer
  $('#run-info').textContent = `Run: ${state.runId} | Gen: ${state.generation}`;
  $('#vote-info').textContent = `Votes: ${state.voteCount} (${state.votesSinceLastRefit} since refit)`;
  if (state.currentWeights) {
    const w = Object.entries(state.currentWeights)
      .map(([k, v]) => `${k}:${typeof v === 'number' ? v.toFixed(2) : v}`)
      .join(' ');
    $('#weights-info').textContent = `W: ${w}`;
  }

  // Pause button
  const pauseBtn = $('#btn-pause');
  pauseBtn.textContent = state.paused ? 'Resume' : 'Pause';
  pauseBtn.classList.toggle('paused', state.paused);

  // Pair display
  if (!state.pair) {
    $('#pair').classList.add('hidden');
    $('#no-pair').classList.remove('hidden');
    return;
  }

  $('#no-pair').classList.add('hidden');
  $('#pair').classList.remove('hidden');

  const { left, right } = state.pair;
  $('#left-label').textContent = `${left.id} (fitness: ${left.fitness?.toFixed(2) ?? '?'})`;
  $('#right-label').textContent = `${right.id} (fitness: ${right.fitness?.toFixed(2) ?? '?'})`;

  // Load SVGs for the first fixture (synth or first available).
  loadSvg('left-svg', left.id);
  loadSvg('right-svg', right.id);
}

async function loadSvg(containerId, individualId) {
  const container = $(`#${containerId}`);
  try {
    // Try to load the first fixture's SVG. If gallery isn't available,
    // show the individual ID as placeholder text.
    const res = await fetch(`/svg/${individualId}/stub`);
    if (res.ok) {
      container.innerHTML = await res.text();
    } else {
      container.innerHTML = `<div style="padding:2rem;color:#666;text-align:center">${individualId}</div>`;
    }
  } catch {
    container.innerHTML = `<div style="padding:2rem;color:#666;text-align:center">${individualId}</div>`;
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
    // Update state with the returned next pair.
    if (res.pair !== undefined) {
      state.pair = res.pair;
    } else {
      state.pair = null;
    }
    // Increment local vote count for immediate feedback.
    state.voteCount = (state.voteCount ?? 0) + 1;
    state.votesSinceLastRefit = (state.votesSinceLastRefit ?? 0) + 1;
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
    if (res.paused !== undefined) {
      state.paused = res.paused;
    }
    render();
  } catch (err) {
    $('#status').textContent = `Control error: ${err.message}`;
  }
}

function getSelectedId(side) {
  if (!state?.pair) return null;
  return side === 'left' ? state.pair.left.id : state.pair.right.id;
}

// ── Event listeners ─────────────────────────────────────────────────────

function setupListeners() {
  // Vote buttons
  $('#btn-left').addEventListener('click', () => vote('left'));
  $('#btn-right').addEventListener('click', () => vote('right'));
  $('#btn-tie').addEventListener('click', () => vote('tie'));
  $('#btn-skip').addEventListener('click', () => vote('skip'));

  // Control buttons
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

  // Keyboard shortcuts
  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    switch (e.key) {
      case 'ArrowLeft':  e.preventDefault(); vote('left'); break;
      case 'ArrowRight': e.preventDefault(); vote('right'); break;
      case 'ArrowDown':  e.preventDefault(); vote('tie'); break;
      case ' ':          e.preventDefault(); vote('skip'); break;
    }
  });
}

// ── Init ────────────────────────────────────────────────────────────────

setupListeners();
loadState();

// Poll for state updates every 3 seconds (catches generation changes).
setInterval(loadState, 3000);
