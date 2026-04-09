import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { writeGallery } from '../gallery.mjs';
import { defaultGenome } from '../../genome/genome.mjs';
import { loadTierA } from '../../corpus/tier-a.mjs';

async function withTmp(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-gallery-'));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function mkElite(id) {
  return { id, genome: defaultGenome(), fitness: 1 };
}

test('writeGallery renders one SVG per (elite, fixture) under galleryDir', async () => {
  await withTmp(async (root) => {
    const fixtures = (await loadTierA()).slice(0, 2);
    const elite = [mkElite('champ-a'), mkElite('champ-b')];
    await writeGallery({
      galleryDir: root,
      elite,
      fixtures,
    });
    // Expect root/champ-a/<fixtureId>.svg and root/champ-b/<fixtureId>.svg
    for (const e of elite) {
      for (const f of fixtures) {
        const path = join(root, e.id, `${f.id}.svg`);
        const st = await stat(path);
        assert.ok(st.isFile(), `expected ${path} to exist`);
        const content = await readFile(path, 'utf8');
        assert.ok(content.includes('<svg'), `file ${path} is not an SVG`);
      }
    }
  });
});

test('writeGallery accepts an injected render function (lets tests avoid dag-map)', async () => {
  await withTmp(async (root) => {
    let calls = 0;
    async function stubRender(_fixture, _genome) {
      calls++;
      return '<svg>stub</svg>';
    }
    const fixtures = [
      { id: 'fixA', dag: { nodes: [], edges: [] }, theme: 'cream', opts: {} },
      { id: 'fixB', dag: { nodes: [], edges: [] }, theme: 'cream', opts: {} },
    ];
    const elite = [mkElite('e1')];
    await writeGallery({
      galleryDir: root,
      elite,
      fixtures,
      render: stubRender,
    });
    assert.equal(calls, 2);
    const content = await readFile(join(root, 'e1', 'fixA.svg'), 'utf8');
    assert.equal(content, '<svg>stub</svg>');
  });
});

test('writeGallery skips rejected individuals', async () => {
  await withTmp(async (root) => {
    const fixtures = [
      { id: 'fixA', dag: { nodes: [], edges: [] }, theme: 'cream', opts: {} },
    ];
    const elite = [
      { id: 'good', genome: defaultGenome(), fitness: 1 },
      { id: 'bad', genome: defaultGenome(), fitness: Infinity, rejected: true },
    ];
    async function stubRender() {
      return '<svg/>';
    }
    await writeGallery({
      galleryDir: root,
      elite,
      fixtures,
      render: stubRender,
    });
    const entries = await readdir(root);
    assert.deepEqual(entries.sort(), ['good']);
  });
});

test('writeGallery produces deterministic output: two calls with same inputs yield identical files', async () => {
  await withTmp(async (root) => {
    const fixtures = (await loadTierA()).slice(0, 1);
    const elite = [mkElite('deterministic')];
    const dirA = join(root, 'a');
    const dirB = join(root, 'b');
    await writeGallery({ galleryDir: dirA, elite, fixtures });
    await writeGallery({ galleryDir: dirB, elite, fixtures });
    for (const f of fixtures) {
      const a = await readFile(join(dirA, 'deterministic', `${f.id}.svg`), 'utf8');
      const b = await readFile(join(dirB, 'deterministic', `${f.id}.svg`), 'utf8');
      assert.equal(a, b, `fixture ${f.id} produced nondeterministic SVG`);
    }
  });
});
