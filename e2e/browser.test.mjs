// End-to-end checks of the built dist/ in headless Chrome: it loads without
// console errors at desktop and phone widths, in both themes; the keyboard,
// a real pointer drag, undo/redo, Run (with and without reduced motion),
// share links and bad links all behave.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { serve } from '../scripts/serve.mjs';
import { browserPlan, findChrome, launchChrome } from './cdp.mjs';
import { dist, knownSolutionFragments } from './helpers.mjs';

const chromePath = findChrome();
const plan = browserPlan(chromePath);
let server;
let chrome;
let base;

before(async () => {
  if (!plan.run) return;
  server = await serve(dist, 0);
  base = `http://127.0.0.1:${server.address().port}/`;
  chrome = await launchChrome(chromePath);
});

after(async () => {
  await chrome?.close();
  await new Promise((r) => (server ? server.close(r) : r()));
});

const ready = 'document.querySelector("svg.marey .thread") !== null';

async function open(opts, hash = '') {
  const page = await chrome.openPage(opts);
  await page.navigate(base + hash);
  await page.waitFor(ready, 20000);
  return page;
}

function noProblems(page, label) {
  assert.deepEqual(page.problems, [], `${label}: ${JSON.stringify(page.problems)}`);
}

const text = (sel) => `(document.querySelector(${JSON.stringify(sel)})?.textContent ?? '').trim()`;
const count = (sel) => `document.querySelectorAll(${JSON.stringify(sel)}).length`;
const noHorizontalScroll = 'document.documentElement.scrollWidth <= document.documentElement.clientWidth';

async function key(page, keyName, modifiers = 0) {
  const codes = { ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40, Enter: 13 };
  const vk = codes[keyName] ?? keyName.toUpperCase().charCodeAt(0);
  const params = { key: keyName, code: keyName.length === 1 ? `Key${keyName.toUpperCase()}` : keyName, windowsVirtualKeyCode: vk, modifiers };
  await page.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', ...params });
  await page.send('Input.dispatchKeyEvent', { type: 'keyUp', ...params });
}

// Elm redraws on the next animation frame, so wait for the control to appear.
async function clickText(page, label) {
  const find = `[...document.querySelectorAll('button, a')].find((b) => b.textContent.trim() === ${JSON.stringify(label)})`;
  await page.waitFor(`${find} !== undefined`, 5000);
  await page.evaluate(`${find}.click()`);
}

// Locally a missing Chrome skips these; with REQUIRE_BROWSER=1 it fails them.
const run = (name, fn) =>
  test(name, { skip: plan.skip ?? false }, async () => {
    if (plan.fail) assert.fail(plan.fail);
    await fn();
  });

const onPlate = (n) => `${text('.plate-no')}.startsWith(${JSON.stringify(`Plate ${romanOf(n)} of`)})`;

run('desktop: plate I loads with its conflict and no errors', async () => {
  const page = await open({ width: 1280, height: 800, scheme: 'light' }, '#p1');
  try {
    assert.match(await page.evaluate('document.title'), /First Meeting/);
    assert.equal(await page.evaluate(count('svg.marey .thread')), 2);
    assert.equal(await page.evaluate(count('svg.marey .conflict')), 1);
    assert.equal(await page.evaluate(text('.headline')), '1 conflict');
    assert.match(await page.evaluate(text('.log li')), /^Head-on: Down local and Up local meet between Brill and Colley/);
    assert.equal(await page.evaluate(count('.plates a')), 13);
    assert.ok(await page.evaluate(noHorizontalScroll));
    noProblems(page, 'desktop');
  } finally {
    await page.close();
  }
});

run('keyboard: pick a knob, shift it, undo and redo', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    await page.evaluate('document.querySelector(".chart-surface").focus()');
    await key(page, '1');
    await key(page, 'ArrowDown'); // from the departure at Ashby to the wait at Brill
    for (let i = 0; i < 3; i++) await key(page, 'ArrowRight');
    await page.waitFor(`${text('.headline')}.startsWith('Line clear')`);
    assert.equal(await page.evaluate(text('.tally-item:nth-child(1) dd')), '1', 'three nudges of one knob are one move');
    assert.equal(await page.evaluate(text('.tally-item:nth-child(2) dd')), '3 min');
    assert.equal(await page.evaluate(count('svg.marey .conflict')), 0);

    await key(page, 'z', 2); // Ctrl+Z
    await page.waitFor(`${text('.headline')} === '1 conflict'`);
    await key(page, 'z', 2 | 8); // Ctrl+Shift+Z
    await page.waitFor(`${text('.headline')}.startsWith('Line clear')`);

    // Shift + arrow moves five minutes, and the bounds hold.
    await key(page, 'ArrowUp');
    await key(page, 'ArrowLeft', 8);
    assert.match(await page.evaluate(text('.knob-row.active output')), /06:00/, 'cannot leave before ready');
    noProblems(page, 'keyboard');
  } finally {
    await page.close();
  }
});

run('pointer: dragging the knob at Brill lengthens the wait', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    const box = JSON.parse(await page.evaluate(`JSON.stringify(document.querySelector('[data-grab="w0.0"]').getBoundingClientRect())`));
    const x = box.x + box.width / 2;
    const y = box.y + box.height / 2;
    const mouse = (type, px, extra = {}) => page.send('Input.dispatchMouseEvent', { type, x: px, y, button: 'left', clickCount: 1, ...extra });
    await mouse('mousePressed', x, { buttons: 1 });
    for (let dx = 10; dx <= 60; dx += 10) await mouse('mouseMoved', x + dx, { buttons: 1 });
    await mouse('mouseReleased', x + 60, { buttons: 0 });
    await page.waitFor(`${text('.tally-item:nth-child(1) dd')} === '1'`);
    const wait = await page.evaluate(`[...document.querySelectorAll('.knob-row')].find((r) => r.textContent.includes('Waits at Brill')).querySelector('output').textContent`);
    assert.match(wait, /^\d+ min$/);
    assert.ok(parseInt(wait, 10) > 0, `wait is ${wait}`);
    noProblems(page, 'pointer');
  } finally {
    await page.close();
  }
});

run('run with reduced motion: the cursor steps, the plate is passed and remembered', async () => {
  const page = await open({ width: 1280, height: 800, reducedMotion: true }, '#p1/0.3-3.0');
  try {
    assert.match(await page.evaluate(text('.notice')), /Opened a shared timetable for plate I/);
    await clickText(page, 'Run');
    await page.waitFor(`${text('.stamp-head')} === 'Passed'`, 10000);
    assert.match(await page.evaluate(text('.stamp-body')), /3 min waiting · par 3 min · shared timetable/);
    assert.match(await page.evaluate(text('.scrub-label')), /Chart time 06:22/);
    const stored = JSON.parse(await page.evaluate('localStorage.getItem("single-track/v1")'));
    assert.deepEqual(stored.records['1'], { waiting: 3, moves: 0 });
    assert.ok(await page.evaluate('document.querySelector(".plates a[href=\\"#p1\\"]").classList.contains("solved")'));
    noProblems(page, 'reduced run');
  } finally {
    await page.evaluate('localStorage.clear()');
    await page.close();
  }
});

run('run with full motion: the cursor glides and the survey trains move', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p2');
  try {
    await clickText(page, 'Run');
    await page.waitFor(`document.querySelector('svg.marey .cursor') !== null`);
    await new Promise((r) => setTimeout(r, 400));
    const x1 = Number(await page.evaluate(`document.querySelector('svg.marey .cursor').getAttribute('x1')`));
    const trains1 = await page.evaluate(`[...document.querySelectorAll('.survey-train rect')].map((r) => r.getAttribute('x')).join()`);
    await new Promise((r) => setTimeout(r, 500));
    const x2 = Number(await page.evaluate(`document.querySelector('svg.marey .cursor').getAttribute('x1')`));
    const trains2 = await page.evaluate(`[...document.querySelectorAll('.survey-train rect')].map((r) => r.getAttribute('x')).join()`);
    assert.ok(x2 > x1, `cursor ${x1} -> ${x2}`);
    assert.notEqual(trains1, trains2);
    await clickText(page, 'Pause');
    noProblems(page, 'full-motion run');
  } finally {
    await page.close();
  }
});

run('every plate: its known solution loads from a link and clears the line', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    for (const { plate, fragment } of knownSolutionFragments()) {
      await page.evaluate(`location.hash = ${JSON.stringify(fragment)}`);
      await page.waitFor(onPlate(plate));
      await page.waitFor(`${text('.headline')}.startsWith('Line clear')`, 5000);
      assert.equal(await page.evaluate(count('svg.marey .conflict')), 0, `plate ${plate}`);
      assert.ok(await page.evaluate(noHorizontalScroll), `plate ${plate} scrolls sideways`);
    }
    noProblems(page, 'all plates');
  } finally {
    await page.close();
  }
});

run('bad links get a clear message instead of a broken page', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    const cases = [
      ['p99', /There is no plate 99/],
      ['p1/zz', /whole minutes/],
      ['p1/0.3', /does not fit this plate: it has the wrong number of trains/],
      ['p1/0.3-1.0', /does not fit this plate: the Up local leaves at a time outside the chart/],
      ['p1/' + '1.'.repeat(300), /too long/],
      ['hello', /not a timetable from this game/],
    ];
    for (const [fragment, message] of cases) {
      await page.evaluate(`location.hash = ${JSON.stringify(fragment)}`);
      await page.waitFor(`${JSON.stringify(message.source)} && new RegExp(${JSON.stringify(message.source)}).test(${text('.notice')})`, 5000);
      assert.ok(await page.evaluate(ready), `chart still drawn after ${fragment}`);
    }
    noProblems(page, 'bad links');
  } finally {
    await page.close();
  }
});

run('a hostile, enormous link is refused quickly without hanging the tab', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    const huge = 'p1/' + '9.'.repeat(100000);
    await page.evaluate(`location.hash = ${JSON.stringify(huge)}`);
    await page.waitFor(`/too long/.test(${text('.notice')})`, 5000);
    await page.evaluate(`location.hash = 'p1/' + Array(50).fill('1.1').join('-')`);
    await page.waitFor(`/more trains than any plate/.test(${text('.notice')})`, 5000);
    assert.equal(await page.evaluate(count('svg.marey .thread')), 2);
    noProblems(page, 'hostile link');
  } finally {
    await page.close();
  }
});

run('the colophon links the third-party notices, which load as a page', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    await clickText(page, 'third-party notices');
    await page.waitFor(`location.pathname.endsWith('/THIRD-PARTY-NOTICES.txt') && document.body.innerText.includes('elm/core')`, 10000);
  } finally {
    await page.close();
  }
});

run('share: the button writes the timetable into the address and shows the link', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    await page.evaluate('document.querySelector(".chart-surface").focus()');
    await key(page, 'ArrowDown');
    await key(page, 'ArrowRight');
    await clickText(page, 'Share timetable');
    await page.waitFor(`location.hash === '#p1/0.1-3.0'`);
    await page.waitFor(`document.querySelector('.share-link') !== null`);
    assert.equal(await page.evaluate('document.querySelector(".share-link").value'), '#p1/0.1-3.0');
    noProblems(page, 'share');
  } finally {
    await page.close();
  }
});

run('theme: the cyanotype toggle applies and persists', async () => {
  const page = await open({ width: 1280, height: 800, scheme: 'light' }, '#p3');
  try {
    await clickText(page, 'Cyanotype');
    await page.waitFor(`document.documentElement.dataset.theme === 'dark'`);
    const bg = await page.evaluate('getComputedStyle(document.body).backgroundColor');
    assert.equal(bg, 'rgb(15, 51, 85)');
    assert.equal(JSON.parse(await page.evaluate('localStorage.getItem("single-track/v1")')).theme, 'dark');
    await clickText(page, 'Paper');
    await page.waitFor(`document.documentElement.dataset.theme === 'light'`);
    noProblems(page, 'theme');
  } finally {
    await page.evaluate('localStorage.clear()');
    await page.close();
  }
});

run('phone width (400 px, emulated): every plate fits without sideways scrolling', async () => {
  const page = await open({ width: 400, height: 860, mobile: true, scale: 2, scheme: 'dark' }, '#p1');
  try {
    for (let plate = 1; plate <= 13; plate++) {
      await page.evaluate(`location.hash = 'p${plate}'`);
      await page.waitFor(onPlate(plate));
      assert.ok(await page.evaluate(noHorizontalScroll), `plate ${plate} scrolls sideways at 400 px`);
      const svgWidth = await page.evaluate(`document.querySelector('svg.marey').getBoundingClientRect().width`);
      assert.ok(svgWidth <= 400 && svgWidth > 300, `chart is ${svgWidth} px wide`);
    }
    noProblems(page, 'phone');
  } finally {
    await page.close();
  }
});

function romanOf(n) {
  const table = [[10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']];
  let out = '';
  for (const [v, s] of table) while (n >= v) { out += s; n -= v; }
  return out;
}
