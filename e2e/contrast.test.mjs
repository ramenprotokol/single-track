// Text colours reach WCAG AA (4.5:1) on the paper and on the panels, in both
// the paper and the cyanotype themes; train inks stand out from the paper and
// from each other.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { root } from './helpers.mjs';

const css = readFileSync(join(root, 'web', 'style.css'), 'utf8');

function block(pattern) {
  const m = pattern.exec(css);
  assert.ok(m, `no block for ${pattern}`);
  const start = css.indexOf('{', m.index + m[0].length - 1) + 1;
  let depth = 1;
  let i = start;
  while (depth > 0) {
    if (css[i] === '{') depth++;
    if (css[i] === '}') depth--;
    i++;
  }
  return css.slice(start, i - 1);
}

function tokens(text) {
  const out = {};
  for (const m of text.matchAll(/--([\w-]+):\s*(#[0-9a-fA-F]{6})\s*;/g)) out[m[1]] = m[2].toLowerCase();
  return out;
}

function luminance(hex) {
  const [r, g, b] = [1, 3, 5]
    .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

// CIEDE2000 colour difference, for telling two inks apart.
function lab(hex) {
  const [r, g, b] = [1, 3, 5]
    .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  const f = (t) => (t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116);
  const x = f((r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047);
  const y = f(r * 0.2126 + g * 0.7152 + b * 0.0722);
  const z = f((r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}

function deltaE(p, q) {
  const [L1, a1, b1] = lab(p);
  const [L2, a2, b2] = lab(q);
  const rad = Math.PI / 180;
  const Cbar = (Math.hypot(a1, b1) + Math.hypot(a2, b2)) / 2;
  const G = 0.5 * (1 - Math.sqrt(Cbar ** 7 / (Cbar ** 7 + 25 ** 7)));
  const [A1, A2] = [a1 * (1 + G), a2 * (1 + G)];
  const [C1, C2] = [Math.hypot(A1, b1), Math.hypot(A2, b2)];
  const hue = (a, b) => ((Math.atan2(b, a) / rad) + 360) % 360;
  const [h1, h2] = [hue(A1, b1), hue(A2, b2)];
  let dh = C1 * C2 === 0 ? 0 : h2 - h1;
  if (dh > 180) dh -= 360;
  if (dh < -180) dh += 360;
  const dH = 2 * Math.sqrt(C1 * C2) * Math.sin((dh / 2) * rad);
  const Lb = (L1 + L2) / 2;
  const Cb = (C1 + C2) / 2;
  const hb = C1 * C2 === 0 ? h1 + h2 : Math.abs(h1 - h2) > 180 ? (h1 + h2 + 360) / 2 : (h1 + h2) / 2;
  const T = 1 - 0.17 * Math.cos((hb - 30) * rad) + 0.24 * Math.cos(2 * hb * rad) + 0.32 * Math.cos((3 * hb + 6) * rad) - 0.2 * Math.cos((4 * hb - 63) * rad);
  const SL = 1 + (0.015 * (Lb - 50) ** 2) / Math.sqrt(20 + (Lb - 50) ** 2);
  const SC = 1 + 0.045 * Cb;
  const SH = 1 + 0.015 * Cb * T;
  const RT = -Math.sin(2 * 30 * Math.exp(-(((hb - 275) / 25) ** 2)) * rad) * 2 * Math.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7));
  const [l, c, h] = [(L2 - L1) / SL, (C2 - C1) / SC, dH / SH];
  return Math.sqrt(l * l + c * c + h * h + RT * c * h);
}

test('the colour difference is 100 from white to black and 0 for one colour', () => {
  assert.ok(Math.abs(deltaE('#ffffff', '#000000') - 100) < 0.01);
  assert.equal(deltaE('#146a74', '#146a74'), 0);
  // The two goods inks this palette used to have (ochre and umber) were too
  // close; the check must catch that.
  assert.ok(deltaE('#93630d', '#6b4a2b') < 15);
  assert.ok(deltaE('#f1d07d', '#e0c4a4') < 15);
});

const light = tokens(block(/^:root\s*\{/m));
const dark = tokens(block(/^:root\[data-theme="dark"\]\s*\{/m));
const autoDark = tokens(block(/:root:not\(\[data-theme="light"\]\)\s*\{/));

const TEXT = ['ink', 'ink-soft', 'alarm', 'good', 'stamp'];
const GROUNDS = ['paper', 'paper-deep'];
// Train inks are lines, not body text: WCAG asks 3:1 for graphics.
const INKS = ['ink-0', 'ink-1', 'ink-2', 'ink-3', 'ink-4', 'ink-5', 'cursor'];

for (const [name, theme] of [['paper', light], ['cyanotype', dark]]) {
  test(`${name}: text tokens reach 4.5:1 on paper and panels`, () => {
    for (const t of TEXT) {
      for (const g of GROUNDS) {
        const r = contrast(theme[t], theme[g]);
        assert.ok(r >= 4.5, `${t} on ${g}: ${r.toFixed(2)}`);
      }
    }
  });

  test(`${name}: train inks reach 3:1 against the paper`, () => {
    for (const t of INKS) {
      const r = contrast(theme[t], theme.paper);
      assert.ok(r >= 3, `${t}: ${r.toFixed(2)}`);
    }
  });

  // Up to six trains share a chart, so every pair of inks must be easy to
  // tell apart (CIEDE2000 of 15 or more: clearly different at a glance).
  test(`${name}: every pair of train inks is clearly different`, () => {
    const inks = INKS.filter((t) => t !== 'cursor');
    for (let i = 0; i < inks.length; i++) {
      for (let j = i + 1; j < inks.length; j++) {
        const d = deltaE(theme[inks[i]], theme[inks[j]]);
        assert.ok(d >= 15, `${inks[i]} and ${inks[j]}: ${d.toFixed(1)}`);
      }
    }
  });

  // Train numbers are printed in the paper colour on blocks of ink.
  test(`${name}: train numbers on their ink blocks reach 4.5:1`, () => {
    for (const t of INKS.filter((k) => k !== 'cursor')) {
      const r = contrast(theme.paper, theme[t]);
      assert.ok(r >= 4.5, `${t}: ${r.toFixed(2)}`);
    }
  });
}

test('the automatic dark theme matches the explicit one', () => {
  assert.deepEqual(autoDark, dark);
});
