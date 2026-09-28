#!/usr/bin/env node
// Build dist/ from a clean clone: compile the Elm app with --optimize,
// minify it with terser, content-hash the assets (the self-hosted fonts
// included) and write index.html and the third-party notices.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
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

// Fonts, served from this site so a visit reaches no third party. Each file
// in web/fonts/ must be listed here (for the notices) and used by the
// stylesheet; each lands in assets/ under a content-hashed name.
const FONTS = {
  'eb-garamond-400': { family: 'EB Garamond', style: 'Regular (400)' },
  'eb-garamond-500': { family: 'EB Garamond', style: 'Medium (500)' },
  'eb-garamond-600': { family: 'EB Garamond', style: 'SemiBold (600)' },
  'eb-garamond-italic-400': { family: 'EB Garamond', style: 'Italic (400)' },
  'im-fell-english-sc-400': { family: 'IM FELL English SC', style: 'Regular (400)' },
};
const FAMILIES = {
  'EB Garamond': {
    version: '1.003',
    licence: 'EB-Garamond-OFL.txt',
    what: [
      'The Latin subset as Google Fonts serves it (static instances of the',
      'variable font), shipped as downloaded. The family has no Reserved Font',
      'Name.',
    ],
    source: [
      'https://github.com/octaviopardo/EBGaramond12 (as served by Google',
      'Fonts, https://fonts.google.com/specimen/EB+Garamond)',
    ],
  },
  'IM FELL English SC': {
    version: '3.00',
    licence: 'IM-Fell-English-SC-OFL.txt',
    notice: '© 2007 Igino Marini (www.iginomarini.com) With Reserved Font Name IM FELL English SC',
    what: [
      'The whole font (IMFeENsc28P.ttf), unmodified, compressed to WOFF2: every',
      'glyph and table as published. The second copyright line above is the',
      "font file's own notice; because the name is reserved, the font is not",
      'subset or otherwise changed here.',
    ],
    source: [
      'https://github.com/google/fonts/tree/main/ofl/imfellenglishsc (upstream:',
      'https://github.com/librefonts/imfellenglishsc)',
    ],
  },
};
const fontDir = join(web, 'fonts');
const unlisted = readdirSync(fontDir).filter((f) => !f.startsWith('.') && !FONTS[f.replace(/\.woff2$/, '')]);
if (unlisted.length) throw new Error(`web/fonts/ has files without a notices entry: ${unlisted.join(', ')}`);
let css = readFileSync(join(web, 'style.css'), 'utf8');
const fontFiles = {};
for (const stem of Object.keys(FONTS)) {
  const file = hashed(stem, 'woff2', readFileSync(join(fontDir, `${stem}.woff2`)));
  const ref = `url("fonts/${stem}.woff2")`;
  if (!css.includes(ref)) throw new Error(`style.css does not use fonts/${stem}.woff2`);
  css = css.replaceAll(ref, `url("${file.slice('assets/'.length)}")`);
  fontFiles[stem] = file;
}
if (/url\("?fonts\//.test(css)) throw new Error('style.css names a font file that is not in web/fonts/');

const files = {
  app: hashed('app', 'js', compressed.code),
  boot: hashed('boot', 'js', boot.code),
  style: hashed('style', 'css', css),
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
// Fonts: each file with its family's copyright line(s) from licenses/, and
// the SIL OFL 1.1 text, which is the same in every licence file, once.
const OFL_START = '-----------------------------------------------------------\nSIL OPEN FONT LICENSE Version 1.1';
let ofl = null;
const fontSections = Object.entries(FAMILIES).map(([family, f]) => {
  const text = readFileSync(join(root, 'licenses', f.licence), 'utf8').replace(/\r\n/g, '\n');
  const at = text.indexOf(OFL_START);
  if (at < 0) throw new Error(`licenses/${f.licence} does not contain the SIL OFL 1.1 text`);
  const body = text.slice(at).trimEnd();
  if (ofl !== null && body !== ofl) throw new Error(`licenses/${f.licence}: its OFL text differs from the others`);
  ofl = body;
  const copyright = text.slice(0, at).split('\n').filter((l) => /^(Copyright|©)/.test(l));
  if (!copyright.length) throw new Error(`licenses/${f.licence} has no copyright line`);
  return [
    `${family} ${f.version} (font)`,
    ...Object.entries(FONTS).filter(([, v]) => v.family === family).map(([stem, v]) => `  ${fontFiles[stem]}  ${v.style}`),
    ...copyright,
    ...(f.notice ? [f.notice] : []),
    'Licence: SIL Open Font License 1.1 (OFL-1.1), full text at the end of this file',
    ...f.what,
    `Source: ${f.source[0]}`,
    ...f.source.slice(1).map((l) => `        ${l}`),
  ].join('\n');
});
const rule = '------------------------------------------------------------------------';
const notices = [
  'Third-party notices for Single Track',
  '====================================',
  '',
  'The JavaScript in assets/app.*.js was compiled by the Elm compiler from this',
  "project's own source and the Elm packages listed below, which are bundled",
  'into it. Each is distributed under the licence reproduced here.',
  '',
  'The two typefaces, EB Garamond and IM FELL English SC, are served from this',
  'site (assets/*.woff2), so opening the page sends nothing to a font service.',
  'Both are under the SIL Open Font License 1.1. Each file is listed after the',
  'Elm packages with its copyright line, and the licence text follows them.',
  '',
  ...sections.flatMap((s) => [rule, '', s, '']),
  ...fontSections.flatMap((s) => [rule, '', s, '']),
  rule,
  '',
  `SIL Open Font License 1.1 (for ${Object.keys(FAMILIES).join(' and ')})`,
  '',
  ofl,
  '',
].join('\n');
writeFileSync(join(dist, 'THIRD-PARTY-NOTICES.txt'), notices + '\n');

for (const f of ['index.html', 'THIRD-PARTY-NOTICES.txt', ...Object.values(files), ...Object.values(fontFiles)]) {
  console.log(`${f.padEnd(32)} ${(statSync(join(dist, f)).size / 1024).toFixed(1)} KiB`);
}
