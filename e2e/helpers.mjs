// Shared paths and data for the end-to-end checks.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = join(dirname(fileURLToPath(import.meta.url)), '..');
export const dist = join(root, 'dist');

/** The known solutions from the Elm tests, as share-link fragments. */
export function knownSolutionFragments() {
  const source = readFileSync(join(root, 'tests', 'KnownSolutions.elm'), 'utf8');
  const out = [];
  for (const m of source.matchAll(/\(\s*(\d+),\s*\[\s*(\[.*\])\s*\]\s*\)/g)) {
    const trains = [...m[2].matchAll(/\[([^\]]*)\]/g)].map((t) => t[1].split(',').map((n) => n.trim()).join('.'));
    out.push({ plate: Number(m[1]), fragment: `p${m[1]}/${trains.join('-')}` });
  }
  return out;
}
