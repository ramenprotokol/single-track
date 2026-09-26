// The built dist/ is complete, self-consistent and served with the headers
// Cloudflare Pages will send.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { serve } from '../scripts/serve.mjs';
import { dist, knownSolutionFragments, root } from './helpers.mjs';

const html = () => readFileSync(join(dist, 'index.html'), 'utf8');

test('dist/index.html references hashed assets that exist', () => {
  assert.ok(existsSync(join(dist, 'index.html')), 'run `npm run build` first');
  const refs = [...html().matchAll(/(?:src|href)="(assets\/[^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(refs.map((r) => r.replace(/\.[0-9a-f]{10}\./, '.HASH.')).sort(), [
    'assets/app.HASH.js',
    'assets/boot.HASH.js',
    'assets/style.HASH.css',
  ]);
  for (const r of refs) assert.ok(statSync(join(dist, r)).size > 0, r);
  assert.doesNotMatch(html(), /\{\{\w+\}\}/);
});

test('the app bundle is the optimised Elm program with its glue', () => {
  const app = readdirSync(join(dist, 'assets')).find((f) => f.startsWith('app.'));
  const js = readFileSync(join(dist, 'assets', app), 'utf8');
  assert.match(js, /Elm/);
  assert.match(js, /single-track\/v1/);
  assert.doesNotMatch(js, /Debug\.|elm\/core\/latest\/Debug/, 'debug code in the build');
  assert.ok(js.length < 200 * 1024, `bundle is ${js.length} bytes`);
});

test('headers: a strict CSP everywhere, long caching only for hashed assets', () => {
  const headers = readFileSync(join(dist, '_headers'), 'utf8');
  assert.match(headers, /^\/\*\n\s+Content-Security-Policy: default-src 'self'; script-src 'self';/m);
  const blocks = headers.split(/\n(?=\S)/);
  const cached = blocks.filter((b) => /max-age=31536000/.test(b));
  assert.equal(cached.length, 1);
  assert.match(cached[0], /^\/assets\/\*/);
});

test('no local paths or placeholders leak into dist/', () => {
  for (const f of ['index.html', ...readdirSync(join(dist, 'assets')).map((a) => `assets/${a}`)]) {
    const text = readFileSync(join(dist, f), 'utf8');
    assert.doesNotMatch(text, /\/Users\/|\/home\/[a-z]/, f);
  }
});

test('third-party notices ship with the licence of every bundled Elm package', () => {
  const file = join(dist, 'THIRD-PARTY-NOTICES.txt');
  assert.ok(existsSync(file), 'dist/THIRD-PARTY-NOTICES.txt is missing');
  const notices = readFileSync(file, 'utf8');
  const elmJson = JSON.parse(readFileSync(join(dist, '..', 'elm.json'), 'utf8'));
  const packages = { ...elmJson.dependencies.direct, ...elmJson.dependencies.indirect };
  assert.ok(Object.keys(packages).length >= 5);
  for (const [name, version] of Object.entries(packages)) {
    const at = notices.indexOf(`${name} ${version}\n`);
    assert.ok(at >= 0, `${name} ${version} not listed`);
    const section = notices.slice(at, notices.indexOf('-----', at + 1) >>> 0);
    assert.match(section, /Copyright/, `${name}: no copyright line`);
    assert.match(section, /Redistribution and use in source and binary forms/, `${name}: no licence text`);
  }
  assert.match(notices, /SIL Open Font License/);
  assert.match(html(), /Single Track/); // the page itself links it; see the browser test
});

test('the plates in Elm match the design data the par search used', () => {
  // Throws (non-zero exit) if src/Levels.elm or tests/KnownSolutions.elm drifted.
  execFileSync(process.execPath, [join(root, 'tools', 'par-search', 'emit.mjs'), '--check'], { stdio: 'pipe' });
});

test('the JavaScript mirror of the rules still gives the verdicts the Elm tests check', () => {
  // Throws if tests/MirrorCases.elm no longer matches tools/par-search/rules.mjs.
  execFileSync(process.execPath, [join(root, 'tools', 'par-search', 'mirror.mjs'), '--check'], { stdio: 'pipe' });
});

test('the par proof runs: no timetable beats par on plates I to IV', () => {
  // The full proof (plates I to VIII, about 20 s) is `npm run prove`.
  const out = execFileSync(process.execPath, [join(root, 'tools', 'par-search', 'prove.mjs'), '4'], { encoding: 'utf8' });
  const lines = out.trim().split('\n');
  assert.equal(lines.length, 4);
  for (const line of lines) assert.match(line, /none solves: par is optimal/);
});

test('known solutions exist for every plate', () => {
  const sols = knownSolutionFragments();
  assert.ok(sols.length >= 12, `${sols.length} solutions`);
  assert.deepEqual(sols.map((s) => s.plate), sols.map((_, i) => i + 1));
});

test('the local server serves dist/ with the production headers', async () => {
  const server = await serve(dist, 0);
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const index = await fetch(base + '/');
    assert.equal(index.status, 200);
    assert.match(index.headers.get('content-security-policy'), /script-src 'self'/);
    assert.match(await index.text(), /Single Track/);
    const asset = html().match(/src="(assets\/app[^"]+)"/)[1];
    const js = await fetch(`${base}/${asset}`);
    assert.equal(js.status, 200);
    assert.match(js.headers.get('content-type'), /javascript/);
    assert.equal((await fetch(base + '/nope.js')).status, 404);
    assert.notEqual((await fetch(base + '/%2e%2e/package.json')).status, 200);
  } finally {
    await new Promise((r) => server.close(r));
  }
});
