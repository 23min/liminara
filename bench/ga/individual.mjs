// individual.mjs — wraps the evaluator into a GA-friendly Individual record.
//
// An Individual is:
//   {
//     id,                 // string, unique within a run
//     island,             // string, name of the subpopulation this individual
//                         //   belongs to (set by initializePopulation or by
//                         //   advanceGeneration when a child is bred)
//     genome,             // { tier1 }
//     fitness,            // sum of per-fixture scores (lower = better)
//     perFixture,         // { [fixtureId]: score } — weighted scalar per fixture
//     termTotals,         // { stretch, bend, crossings, monotone, envelope,
//                         //   channel, repel_nn, repel_ne } — per-term RAW values
//                         //   summed across every fixture, BEFORE weighting.
//                         //   Needed by the M-03 BT weight refit so it can
//                         //   compute term differences between paired
//                         //   individuals without re-scoring.
//     rejected?,          // true if any fixture's evaluator rejected
//     rejectionRule?,     // rule from the rejection
//     rejectionDetail?,   // detail from the rejection
//   }

import { evaluate, TERM_NAMES } from '../evaluator/evaluator.mjs';
import { toEvaluatorGenome } from '../genome/genome.mjs';

export async function scoreIndividual({ id, genome, fixtures, weights, island }) {
  const ev = toEvaluatorGenome(genome);
  const perFixture = {};
  const termTotals = Object.fromEntries(TERM_NAMES.map((n) => [n, 0]));
  let fitness = 0;
  for (const f of fixtures) {
    const result = await evaluate(ev, f, { weights });
    if (result.rejected) {
      return {
        id,
        island,
        genome,
        fitness: Number.POSITIVE_INFINITY,
        perFixture,
        termTotals,
        rejected: true,
        rejectionRule: result.rule,
        rejectionDetail: result.detail,
      };
    }
    perFixture[f.id] = result.score;
    fitness += result.score;
    for (const n of TERM_NAMES) {
      termTotals[n] += result.terms[n];
    }
  }
  return { id, island, genome, fitness, perFixture, termTotals };
}
