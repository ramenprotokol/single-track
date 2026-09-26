#!/usr/bin/env node
// Build dist/ from a clean clone: compile the Elm app with --optimize,
// minify it with terser, content-hash the assets and write index.html.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { minify } from 'terser';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const web = join(root, 'web');
const dist = join(root, 'dist');
const work = join(root, 'build');

rmSync(dist, { recursive: true, force: true });
mkdirSync(join(dist, 'assets'), { recursive: true });
mkdirSync(work, { recursive: true });

const elmOut = join(work, 'elm.js');
const elm = join(root, 'node_modules', '.bin', 'elm');
execFileSync(elm, ['make', 'src/Main.elm', '--optimize', `--output=${elmOut}`], { cwd: root, stdio: 'inherit' });

const source = readFileSync(elmOut, 'utf8') + '\n' + readFileSync(join(web, 'glue.js'), 'utf8');

// Elm's recommended terser settings: its curried helpers are pure.
const pure = ['F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9'];
const compressed = await minify(source, {
  compress: { pure_funcs: pure, pure_getters: true, keep_fargs: false, unsafe_comps: true, unsafe: true, passes: 2 },
  mangle: true,
  format: { comments: false },
});
const boot = await minify(readFileSync(join(web, 'boot.js'), 'utf8'), { format: { comments: false } });

const hashed = (name, ext, body) => {
  const hash = createHash('sha256').update(body).digest('hex').slice(0, 10);
  const file = `assets/${name}.${hash}.${ext}`;
  writeFileSync(join(dist, file), body);
  return file;
};

const files = {
  app: hashed('app', 'js', compressed.code),
  boot: hashed('boot', 'js', boot.code),
  style: hashed('style', 'css', readFileSync(join(web, 'style.css'), 'utf8')),
};

let html = readFileSync(join(web, 'index.html'), 'utf8');
for (const [key, file] of Object.entries(files)) html = html.replace(`{{${key}}}`, file);
if (/\{\{\w+\}\}/.test(html)) throw new Error('index.html has an unfilled placeholder');
writeFileSync(join(dist, 'index.html'), html);

for (const f of ['_headers', 'favicon.svg']) cpSync(join(web, f), join(dist, f));

// Third-party notices: every Elm package compiled into the bundle, with its
// licence text taken from the package cache that `elm make` just used.
const elmJson = JSON.parse(readFileSync(join(root, 'elm.json'), 'utf8'));
const packages = { ...elmJson.dependencies.direct, ...elmJson.dependencies.indirect };
const elmHome = process.env.ELM_HOME || join(homedir(), '.elm');
const sections = Object.entries(packages)
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([name, version]) => {
    const licence = join(elmHome, elmJson['elm-version'], 'packages', name, version, 'LICENSE');
    if (!existsSync(licence)) throw new Error(`no LICENSE for ${name} ${version} in the Elm package cache`);
    return [
      `${name} ${version}`,
      `Source: https://package.elm-lang.org/packages/${name}/${version}/ (https://github.com/${name})`,
      'Licence: BSD-3-Clause',
      '',
      readFileSync(licence, 'utf8').trim(),
    ].join('\n');
  });
const notices = [
  'Third-party notices for Single Track',
  '====================================',
  '',
  'The JavaScript in assets/app.*.js was compiled by the Elm compiler from this',
  "project's own source and the Elm packages listed below, which are bundled",
  'into it. Each is distributed under the licence reproduced here.',
  '',
  'Fonts are not bundled or redistributed. The page asks Google Fonts for',
  'EB Garamond (https://fonts.google.com/specimen/EB+Garamond) and',
  'IM FELL English SC (https://fonts.google.com/specimen/IM+Fell+English+SC)',
  'at run time. Both are published under the SIL Open Font License 1.1',
  '(https://openfontlicense.org); their copyright notices are in the OFL.txt',
  'that accompanies each family at Google Fonts.',
  '',
  ...sections.flatMap((s) => ['------------------------------------------------------------------------', '', s, '']),
].join('\n');
writeFileSync(join(dist, 'THIRD-PARTY-NOTICES.txt'), notices + '\n');

for (const f of ['index.html', 'THIRD-PARTY-NOTICES.txt', ...Object.values(files)]) {
  console.log(`${f.padEnd(32)} ${(statSync(join(dist, f)).size / 1024).toFixed(1)} KiB`);
}
