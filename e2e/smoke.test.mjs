// The built dist/ is complete, self-consistent and served with the headers
// Cloudflare Pages will send.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
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

// The self-hosted fonts, by source name (web/fonts/<name>.woff2).
const FONTS = ['eb-garamond-400', 'eb-garamond-500', 'eb-garamond-600', 'eb-garamond-italic-400', 'im-fell-english-sc-400'];

test('fonts ship from this site: no Google Fonts in dist/, hashed WOFF2 files the stylesheet uses', () => {
  const assets = readdirSync(join(dist, 'assets'));
  const css = readFileSync(join(dist, 'assets', assets.find((a) => /^style\.[0-9a-f]{10}\.css$/.test(a))), 'utf8');
  const headers = readFileSync(join(dist, '_headers'), 'utf8');
  for (const [name, text] of [['index.html', html()], ['the stylesheet', css], ['_headers', headers]]) {
    assert.doesNotMatch(text, /googleapis|gstatic|fonts\.google/, `${name} must not reach Google`);
  }
  assert.match(headers, /Content-Security-Policy: [^\n]*; style-src 'self'; font-src 'self';/);
  const fonts = assets.filter((a) => a.endsWith('.woff2')).sort();
  assert.deepEqual(fonts.map((f) => f.replace(/\.[0-9a-f]{10}\.woff2$/, '')), FONTS, 'five content-hashed WOFF2 files in dist/assets/');
  for (const f of fonts) {
    const bytes = readFileSync(join(dist, 'assets', f));
    assert.equal(bytes.subarray(0, 4).toString('latin1'), 'wOF2', `${f} is WOFF2`);
    assert.equal(f.split('.')[1], createHash('sha256').update(bytes).digest('hex').slice(0, 10), `${f}: the name carries its content hash`);
    assert.ok(css.includes(`url("${f}")`), `${f} is referenced from the stylesheet`);
  }
  const faces = css.match(/@font-face\s*\{[^}]*\}/g) ?? [];
  assert.equal(faces.length, FONTS.length, 'one @font-face per file');
  for (const face of faces) assert.match(face, /font-display: swap;/);
  for (const [, url] of css.matchAll(/url\("([^"]+)"\)/g)) {
    if (!url.startsWith('data:')) assert.ok(existsSync(join(dist, 'assets', url)), `${url} (from the stylesheet) exists`);
  }
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
  // The self-hosted fonts: every file, its copyright line (and reserved name), and the OFL text once.
  const fonts = readdirSync(join(dist, 'assets')).filter((a) => a.endsWith('.woff2'));
  assert.equal(fonts.length, FONTS.length, 'the font files are in dist/assets/');
  for (const f of fonts) assert.ok(notices.includes(`assets/${f}`), `${f} is not listed`);
  assert.match(notices, /EB Garamond 1\.003/);
  assert.match(notices, /Copyright 2017 The EB Garamond Project Authors \(https:\/\/github\.com\/octaviopardo\/EBGaramond12\)/);
  assert.match(notices, /IM FELL English SC 3\.00/);
  assert.match(notices, /Copyright \(c\) 2010, Igino Marini/);
  assert.match(notices, /With Reserved Font Name IM FELL English SC/);
  assert.match(notices, /SIL OPEN FONT LICENSE Version 1\.1 - 26 February 2007[\s\S]*PERMISSION & CONDITIONS[\s\S]*TERMINATION/);
  assert.equal(notices.match(/PERMISSION & CONDITIONS/g).length, 1, 'the OFL text appears once');
  assert.doesNotMatch(notices, /not bundled or redistributed|asks Google Fonts/);
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
    const font = readdirSync(join(dist, 'assets')).find((a) => a.endsWith('.woff2'));
    const fr = await fetch(`${base}/assets/${font}`);
    assert.equal(fr.status, 200);
    assert.equal(fr.headers.get('content-type'), 'font/woff2');
    assert.equal((await fetch(base + '/nope.js')).status, 404);
    assert.notEqual((await fetch(base + '/%2e%2e/package.json')).status, 200);
  } finally {
    await new Promise((r) => server.close(r));
  }
});
