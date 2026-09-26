// Exhaustive proof that par is optimal for the smaller plates.
//
// A timetable's waiting is the sum of its "extras": minutes each train leaves
// after it is ready, plus minutes it waits beyond its minimum call at each
// stop. Every extra is a whole number of at least zero. So every timetable
// with less waiting than par is one way of sharing out fewer than `par`
// minutes among the extras, and there are finitely many. This script tries
// every one of them against the rules; if none solves the plate, nothing
// beats par. It also checks the known solution at par still solves.
//
// It runs on rules.mjs, the JavaScript mirror of src/Rail.elm; the Elm test
// MirrorTests checks the two agree (regenerate it with mirror.mjs).
//
//   node tools/par-search/prove.mjs [lastPlate]     (default 8, about 20 s)
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { levels } from './levels.mjs';
import { solved, waiting } from './rules.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const results = JSON.parse(readFileSync(join(here, 'results.json'), 'utf8'));

/** Try every timetable with less waiting than par. Returns the first that solves, if any. */
export function beatPar(level, par) {
  const stops = level.trains.map((t) => Math.abs(t.to - t.from) - 1);
  const slots = stops.reduce((n, s) => n + 1 + s, 0);
  const extra = new Array(slots).fill(0);
  let tried = 0;
  const plan = () => {
    let k = 0;
    return level.trains.map((t, i) => {
      const dep = t.ready + extra[k++];
      const dwells = [];
      for (let j = 0; j < stops[i]; j++) dwells.push(t.call + extra[k++]);
      return { dep, dwells };
    });
  };
  // Share out at most `left` minutes among slots idx..end.
  const share = (idx, left) => {
    if (idx === slots) {
      tried++;
      const p = plan();
      if (p.some((tp) => tp.dep > level.span)) return null;
      return solved(level, p) ? p : null;
    }
    for (let v = 0; v <= left; v++) {
      extra[idx] = v;
      const found = share(idx + 1, left - v);
      if (found) return found;
    }
    extra[idx] = 0;
    return null;
  };
  const found = par > 0 ? share(0, par - 1) : null;
  return { found, tried };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const last = Number(process.argv[2] ?? 8);
  let failed = false;
  for (const level of levels.filter((l) => l.id <= last)) {
    const { par, plan } = results[level.id];
    const t0 = Date.now();
    const atPar = solved(level, plan) && waiting(level, plan) === par;
    const { found, tried } = beatPar(level, par);
    const ms = Date.now() - t0;
    if (!atPar || found) failed = true;
    console.log(
      `plate ${String(level.id).padStart(2)}  par ${String(par).padStart(3)} min  ` +
        `${String(tried).padStart(9)} timetables under par tried  ` +
        (found ? `BEATEN by ${JSON.stringify(found)}` : atPar ? 'none solves: par is optimal' : 'known solution no longer solves') +
        `  (${ms} ms)`,
    );
  }
  if (failed) process.exit(1);
}
