import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  createIslands,
  placeIndividual,
  islandKeys,
  totalSize,
  allIndividuals,
  DEFAULT_POPULATION_KEYS,
} from '../islands.mjs';
import { defaultGenome } from '../../genome/genome.mjs';

function ind(id, island) {
  return { id, island, genome: defaultGenome(), fitness: 0 };
}

test('createIslands with no args uses DEFAULT_POPULATION_KEYS', () => {
  const islands = createIslands();
  assert.deepEqual(islandKeys(islands), DEFAULT_POPULATION_KEYS);
  assert.equal(totalSize(islands), 0);
});

test('createIslands accepts a custom list of population keys', () => {
  const islands = createIslands(['alpha', 'beta']);
  assert.deepEqual(islandKeys(islands).sort(), ['alpha', 'beta']);
  assert.equal(totalSize(islands), 0);
});

test('placeIndividual routes by individual.island', () => {
  const islands = createIslands(['pop-0', 'pop-1', 'pop-2']);
  placeIndividual(islands, ind('a', 'pop-0'));
  placeIndividual(islands, ind('b', 'pop-1'));
  placeIndividual(islands, ind('c', 'pop-1'));
  assert.equal(islands.populations.get('pop-0').length, 1);
  assert.equal(islands.populations.get('pop-1').length, 2);
  assert.equal(islands.populations.get('pop-2').length, 0);
  assert.equal(totalSize(islands), 3);
});

test('placeIndividual throws when the individual has no island field', () => {
  const islands = createIslands();
  const bad = { id: 'x', genome: defaultGenome(), fitness: 0 };
  assert.throws(() => placeIndividual(islands, bad), /no island field/);
});

test('placeIndividual throws when the target island does not exist', () => {
  const islands = createIslands(['pop-0', 'pop-1']);
  assert.throws(
    () => placeIndividual(islands, ind('x', 'pop-2')),
    /no island "pop-2"/,
  );
});

test('allIndividuals returns one flat array across islands', () => {
  const islands = createIslands(['pop-0', 'pop-1', 'pop-2']);
  placeIndividual(islands, ind('a', 'pop-0'));
  placeIndividual(islands, ind('b', 'pop-1'));
  placeIndividual(islands, ind('c', 'pop-2'));
  const all = allIndividuals(islands);
  assert.equal(all.length, 3);
  assert.deepEqual(all.map((i) => i.id).sort(), ['a', 'b', 'c']);
});

test('individual can be moved between islands by rewriting its island field', () => {
  // This is the migration primitive the ring-topology migration (M-02
  // commit B) will exercise: updating an individual's `island` field
  // and placing it in the next-generation container routes it to the
  // new bucket.
  const islands = createIslands(['pop-0', 'pop-1']);
  const original = ind('a', 'pop-0');
  placeIndividual(islands, original);
  assert.equal(islands.populations.get('pop-0').length, 1);

  const migrated = { ...original, island: 'pop-1' };
  const nextIslands = createIslands(['pop-0', 'pop-1']);
  placeIndividual(nextIslands, migrated);
  assert.equal(nextIslands.populations.get('pop-1').length, 1);
  assert.equal(nextIslands.populations.get('pop-1')[0].id, 'a');
});
