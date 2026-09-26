// Design-time search for each plate's par: the least total waiting found by a
// branch-and-bound over meeting and overtaking orders (see rules.mjs). Writes
// results.json; run emit.mjs afterwards to regenerate the Elm files.
//   node tools/par-search/search.mjs
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { levels } from './levels.mjs';
import { solve, solved, initialPlan, waiting, conflicts, late } from './rules.mjs';
const out = {};
for (const l of levels) {
  const t0 = Date.now();
  const s = solve(l);
  if (!s.bestPlan || !solved(l, s.bestPlan)) throw new Error('unsolvable ' + l.id);
  const init = initialPlan(l);
  out[l.id] = { par: s.best, plan: s.bestPlan, initConflicts: conflicts(l, init).length, initLate: late(l, init).length, optimal: s.optimalCount, truncated: s.truncated };
  console.log(l.id, l.title, 'par', s.best, 'w', waiting(l, s.bestPlan), 'init', out[l.id].initConflicts, out[l.id].initLate, Date.now() - t0, 'ms');
}
writeFileSync(join(dirname(fileURLToPath(import.meta.url)), 'results.json'), JSON.stringify(out, null, 1) + '\n');
