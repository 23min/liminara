import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { existsSync } from 'node:fs';

import { generateReport } from '../report.mjs';
import { loadEliteFromRun } from '../report-cli.mjs';

// Minimal fixtures for testing
const FIXTURES = [
  {
    id: 'tri',
    dag: {
      nodes: [
        { id: 'a', label: 'a' },
        { id: 'b', label: 'b' },
        { id: 'c', label: 'c' },
      ],
      edges: [['a', 'b'], ['b', 'c']],
    },
    theme: 'cream',
    opts: {},
  },
  {
    id: 'pair',
    dag: {
      nodes: [
        { id: 'x', label: 'x' },
        { id: 'y', label: 'y' },
      ],
      edges: [['x', 'y']],
    },
    theme: 'cream',
    opts: {},
  },
];

const WEIGHTS = {
  stretch: 1,
  bend: 1,
  crossings: 1,
  monotone: 1,
  envelope: 1,
  channel: 1,
  repel_nn: 1,
  repel_ne: 1,
};

test('generateReport produces report.md and report.json', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'report-'));
  await generateReport({
    fixtures: FIXTURES,
    weights: WEIGHTS,
    outDir,
    runId: 'test-run-001',
    skipGallery: true,
  });

  assert.ok(existsSync(join(outDir, 'report.md')));
  assert.ok(existsSync(join(outDir, 'report.json')));
});

test('report.json contains per-fixture per-engine scores', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'report-'));
  await generateReport({
    fixtures: FIXTURES,
    weights: WEIGHTS,
    outDir,
    runId: 'test-run-002',
    skipGallery: true,
  });

  const raw = await readFile(join(outDir, 'report.json'), 'utf8');
  const data = JSON.parse(raw);

  assert.ok(data.fixtures);
  assert.equal(data.fixtures.length, FIXTURES.length);
  assert.ok(data.summary);
  assert.ok(data.meta);

  for (const entry of data.fixtures) {
    assert.ok(entry.id);
    assert.ok(entry.engines);
    assert.ok('dag-map' in entry.engines);
    assert.ok('dagre' in entry.engines);
    assert.ok('elk' in entry.engines);
  }
});

test('report.json includes weight vector and run id (honesty)', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'report-'));
  await generateReport({
    fixtures: FIXTURES,
    weights: WEIGHTS,
    outDir,
    runId: 'honesty-test',
    skipGallery: true,
  });

  const data = JSON.parse(await readFile(join(outDir, 'report.json'), 'utf8'));

  assert.deepStrictEqual(data.meta.weights, WEIGHTS);
  assert.equal(data.meta.runId, 'honesty-test');
});

test('report.md lists loss fixtures explicitly (honesty)', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'report-'));
  await generateReport({
    fixtures: FIXTURES,
    weights: WEIGHTS,
    outDir,
    runId: 'honesty-md',
    skipGallery: true,
  });

  const md = await readFile(join(outDir, 'report.md'), 'utf8');

  // Report must include the weight vector
  assert.ok(md.includes('Weight Vector'), 'report.md should show weight vector');
  // Report must include the run id
  assert.ok(md.includes('honesty-md'), 'report.md should include run id');
  // Report must have a section about losses
  assert.ok(
    md.includes('dag-map loses') || md.includes('Losses') || md.includes('Loss'),
    'report.md should explicitly list fixtures where dag-map loses',
  );
});

test('report.json summary has win/loss/tie counts', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'report-'));
  await generateReport({
    fixtures: FIXTURES,
    weights: WEIGHTS,
    outDir,
    runId: 'wlt-test',
    skipGallery: true,
  });

  const data = JSON.parse(await readFile(join(outDir, 'report.json'), 'utf8'));

  for (const engine of ['dagre', 'elk']) {
    const vs = data.summary[`dag-map_vs_${engine}`];
    assert.ok(vs, `summary should have dag-map vs ${engine}`);
    assert.equal(typeof vs.wins, 'number');
    assert.equal(typeof vs.losses, 'number');
    assert.equal(typeof vs.ties, 'number');
    assert.equal(vs.wins + vs.losses + vs.ties, FIXTURES.length);
  }
});

test('report is reproducible — same inputs produce identical numbers', async () => {
  const dir1 = await mkdtemp(join(tmpdir(), 'report-'));
  const dir2 = await mkdtemp(join(tmpdir(), 'report-'));

  await generateReport({ fixtures: FIXTURES, weights: WEIGHTS, outDir: dir1, runId: 'r1', skipGallery: true });
  await generateReport({ fixtures: FIXTURES, weights: WEIGHTS, outDir: dir2, runId: 'r1', skipGallery: true });

  const j1 = JSON.parse(await readFile(join(dir1, 'report.json'), 'utf8'));
  const j2 = JSON.parse(await readFile(join(dir2, 'report.json'), 'utf8'));

  assert.deepStrictEqual(j1, j2);
});

test('gallery SVGs are written when skipGallery is false', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'report-'));
  await generateReport({
    fixtures: FIXTURES,
    weights: WEIGHTS,
    outDir,
    runId: 'gallery-test',
    skipGallery: false,
  });

  assert.ok(existsSync(join(outDir, 'gallery')));
  const files = await readdir(join(outDir, 'gallery'));
  const svgs = files.filter((f) => f.endsWith('.svg'));
  assert.ok(svgs.length > 0, 'gallery should contain at least one SVG');
});

test('no per-engine special-casing — all scored with same weights and terms', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'report-'));
  await generateReport({
    fixtures: FIXTURES,
    weights: WEIGHTS,
    outDir,
    runId: 'fair-test',
    skipGallery: true,
  });

  const data = JSON.parse(await readFile(join(outDir, 'report.json'), 'utf8'));

  // All engines should have the same set of term names
  for (const entry of data.fixtures) {
    const termSets = Object.values(entry.engines).map((e) =>
      e.terms ? Object.keys(e.terms).sort().join(',') : 'error'
    );
    const validSets = termSets.filter((s) => s !== 'error');
    if (validSets.length >= 2) {
      // All valid engines have same terms
      assert.ok(new Set(validSets).size === 1, 'all engines scored with same terms');
    }
  }
});

// --- loadEliteFromRun tests ---

test('loadEliteFromRun reads best genome from latest generation', async () => {
  const runDir = await mkdtemp(join(tmpdir(), 'elite-'));
  const genDir = join(runDir, 'gen-0005');
  await mkdir(genDir, { recursive: true });

  const genomes = [
    { id: 'ind-a', island: 'pop-0', genome: { tier1: { 'render.layerSpacing': 60, 'render.scale': 1.2 } } },
    { id: 'ind-b', island: 'pop-0', genome: { tier1: { 'render.layerSpacing': 80, 'render.scale': 1.8 } } },
  ];
  const scores = {
    individuals: [
      { id: 'ind-a', fitness: 42.5, perFixture: {} },
      { id: 'ind-b', fitness: 10.2, perFixture: {} },
    ],
  };

  await writeFile(join(genDir, 'genomes.json'), JSON.stringify(genomes));
  await writeFile(join(genDir, 'scores.json'), JSON.stringify(scores));

  const result = await loadEliteFromRun(runDir);

  assert.equal(result.individualId, 'ind-b');
  assert.equal(result.fitness, 10.2);
  assert.equal(result.genIndex, 5);
  assert.equal(result.genome.tier1['render.layerSpacing'], 80);
});

test('loadEliteFromRun picks latest generation when multiple exist', async () => {
  const runDir = await mkdtemp(join(tmpdir(), 'elite-'));

  for (const gen of ['gen-0001', 'gen-0010']) {
    const genDir = join(runDir, gen);
    await mkdir(genDir, { recursive: true });
    await writeFile(join(genDir, 'genomes.json'), JSON.stringify([
      { id: `best-${gen}`, island: 'pop-0', genome: { tier1: { x: 1 } } },
    ]));
    await writeFile(join(genDir, 'scores.json'), JSON.stringify({
      individuals: [{ id: `best-${gen}`, fitness: 5.0 }],
    }));
  }

  const result = await loadEliteFromRun(runDir);
  assert.equal(result.genIndex, 10);
  assert.equal(result.individualId, 'best-gen-0010');
});

test('loadEliteFromRun returns null when no generations exist', async () => {
  const runDir = await mkdtemp(join(tmpdir(), 'elite-'));
  const result = await loadEliteFromRun(runDir);
  assert.equal(result, null);
});

test('report.json includes elite metadata when eliteInfo is provided', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'report-'));
  const eliteInfo = {
    individualId: 'test-elite',
    genIndex: 42,
    fitness: 7.5,
    genome: { tier1: { 'render.layerSpacing': 75 } },
  };

  await generateReport({
    fixtures: FIXTURES,
    weights: WEIGHTS,
    outDir,
    runId: 'elite-report',
    eliteInfo,
    skipGallery: true,
  });

  const data = JSON.parse(await readFile(join(outDir, 'report.json'), 'utf8'));

  assert.ok(data.meta.elite);
  assert.equal(data.meta.elite.individualId, 'test-elite');
  assert.equal(data.meta.elite.generation, 42);
  assert.equal(data.meta.elite.fitness, 7.5);
  assert.deepStrictEqual(data.meta.elite.genome, eliteInfo.genome);

  const md = await readFile(join(outDir, 'report.md'), 'utf8');
  assert.ok(md.includes('Evolved Elite'));
  assert.ok(md.includes('test-elite'));
});
