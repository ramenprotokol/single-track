// Text colours reach WCAG AA (4.5:1) on the paper and on the panels, in both
// the paper and the cyanotype themes.
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
}

test('the automatic dark theme matches the explicit one', () => {
  assert.deepEqual(autoDark, dark);
});
