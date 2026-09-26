// End-to-end checks of the built dist/ in headless Chrome: it loads without
// console errors at desktop and phone widths, in both themes; the keyboard,
// a real pointer drag, undo/redo, Run (with and without reduced motion, with
// the chart and survey in view together), share links, Back, bad links and
// the system theme all behave.
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
  const codes = { Tab: 9, Enter: 13, End: 35, Home: 36, ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40 };
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

run('run with reduced motion: the cursor steps, and a solve by hand is passed and remembered', async () => {
  const page = await open({ width: 1280, height: 800, reducedMotion: true }, '#p1');
  try {
    await page.evaluate('document.querySelector(".chart-surface").focus()');
    await key(page, 'ArrowDown'); // the wait at Brill
    for (let i = 0; i < 3; i++) await key(page, 'ArrowRight');
    await clickText(page, 'Run');
    await page.waitFor(`${text('.stamp-head')} === 'Passed'`, 10000);
    assert.match(await page.evaluate(text('.stamp-body')), /3 min waiting · par 3 min · 1 move$/);
    assert.match(await page.evaluate(text('.scrub-label')), /Chart time 06:22/);
    const stored = JSON.parse(await page.evaluate('localStorage.getItem("single-track/v1")'));
    assert.deepEqual(stored.records['1'], { waiting: 3, moves: 1 });
    assert.ok(await page.evaluate('document.querySelector(".plates a[href=\\"#p1\\"]").classList.contains("solved")'));
    noProblems(page, 'reduced run');
  } finally {
    await page.evaluate('localStorage.clear()');
    await page.close();
  }
});

run('a shared timetable passes but is not recorded until the player changes it', async () => {
  const page = await open({ width: 1280, height: 800, reducedMotion: true }, '#p1/0.3-3.0');
  try {
    assert.match(await page.evaluate(text('.notice')), /Opened a shared timetable for plate I/);
    await page.waitFor(`location.hash === '#p1'`); // used once, then cut back to the plate
    await clickText(page, 'Run');
    await page.waitFor(`${text('.stamp-head')} === 'Passed'`, 10000);
    assert.match(await page.evaluate(text('.stamp-body')), /shared timetable/);
    assert.match(await page.evaluate(text('.stamp')), /Not added to your record until you change it/);
    assert.equal(await page.evaluate('localStorage.getItem("single-track/v1")'), null);

    // One change of the player's own (a minute more at Brill) makes it theirs.
    await page.evaluate('document.querySelector(".chart-surface").focus()');
    await key(page, 'ArrowDown');
    await key(page, 'ArrowRight');
    await page.evaluate('document.querySelector(".run-bar .primary").click()'); // "Run again"
    await page.waitFor(`/^4 min waiting/.test(${text('.stamp-body')})`, 10000);
    assert.match(await page.evaluate(text('.stamp-body')), /4 min waiting · par 3 min · 1 move$/);
    const stored = JSON.parse(await page.evaluate('localStorage.getItem("single-track/v1")'));
    assert.deepEqual(stored.records['1'], { waiting: 4, moves: 1 });
    noProblems(page, 'shared run');
  } finally {
    await page.evaluate('localStorage.clear()');
    await page.close();
  }
});

// Where the chart (svg.marey) and the survey drawing (svg.survey) sit in the window.
const stageInView = `(() => {
  const chart = document.querySelector('svg.marey').getBoundingClientRect();
  const survey = document.querySelector('svg.survey').getBoundingClientRect();
  return chart.top >= 0 && survey.bottom <= innerHeight && chart.bottom < survey.top;
})()`;
const playing = `[...document.querySelectorAll('button')].some((b) => b.textContent.trim() === 'Pause')`;

for (const plate of [1, 9, 13]) {
  run(`run at 1280×800: plate ${romanOf(plate)} scrolls so the chart and the survey are both in view while it runs`, async () => {
    const page = await open({ width: 1280, height: 800 }, `#p${plate}`);
    try {
      assert.equal(await page.evaluate(stageInView), false, 'the survey starts below the fold');
      await clickText(page, 'Run');
      await page.waitFor(`${playing} && ${stageInView}`, 4000);
      await clickText(page, 'Pause');
      noProblems(page, `stage ${plate}`);
    } finally {
      await page.close();
    }
  });
}

run('run at 1440×900 with reduced motion: the scroll is instant, and the stamp and next link are in view at the end', async () => {
  const page = await open({ width: 1440, height: 900, reducedMotion: true }, '#p1');
  try {
    const frames = 'new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => r(true)))))';
    for (const { plate, fragment } of knownSolutionFragments().filter((s) => [1, 9, 13].includes(s.plate))) {
      await page.evaluate('scrollTo(0, 0)');
      await page.evaluate(`location.hash = ${JSON.stringify(fragment)}`);
      await page.waitFor(`${onPlate(plate)} && ${text('.headline')}.startsWith('Line clear')`);
      await clickText(page, 'Run');
      await page.evaluate(frames);
      assert.ok(await page.evaluate(stageInView), `plate ${plate}: stage not in view straight away`);
      await page.waitFor(`${text('.stamp-head')} === 'Passed'`, 15000);
      const box = JSON.parse(await page.evaluate(`JSON.stringify(document.querySelector('.stamp').getBoundingClientRect())`));
      assert.ok(box.top >= 0 && box.bottom <= 900, `plate ${plate}: stamp at ${box.top}..${box.bottom}`);
      if (plate < 13) {
        const next = JSON.parse(await page.evaluate(`JSON.stringify(document.querySelector('.stamp .next-plate').getBoundingClientRect())`));
        assert.ok(next.top >= 0 && next.bottom <= 900, `plate ${plate}: next link at ${next.top}..${next.bottom}`);
      }
      assert.ok(await page.evaluate(stageInView), `plate ${plate}: stage left the view`);
    }
    noProblems(page, 'reduced stage');
  } finally {
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

run('share: the button shows the full link and leaves the address alone', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    await page.evaluate('document.querySelector(".chart-surface").focus()');
    await key(page, 'ArrowDown');
    await key(page, 'ArrowRight');
    await clickText(page, 'Share timetable');
    await page.waitFor(`document.querySelector('.share-link') !== null`);
    assert.equal(await page.evaluate('document.querySelector(".share-link").value'), `${base}#p1/0.1-3.0`);
    assert.equal(await page.evaluate('location.hash'), '#p1');
    noProblems(page, 'share');
  } finally {
    await page.close();
  }
});

run('a shared link opened over work in progress is one undo step away from it', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    const waiting = text('.tally-item:nth-child(2) dd');
    await page.evaluate('document.querySelector(".chart-surface").focus()');
    await key(page, 'ArrowDown');
    await key(page, 'ArrowRight');
    await page.waitFor(`${waiting} === '1 min'`);
    await page.evaluate(`location.hash = 'p1/0.3-3.0'`);
    await page.waitFor(`${waiting} === '3 min'`);
    assert.match(await page.evaluate(text('.notice')), /Undo brings back the timetable you had/);
    await key(page, 'z', 2); // Ctrl+Z
    await page.waitFor(`${waiting} === '1 min'`);
    noProblems(page, 'link over work');
  } finally {
    await page.close();
  }
});

run('after a link loads, Back only switches plates and never replaces later work', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1/0.3-3.0');
  try {
    const waiting = text('.tally-item:nth-child(2) dd');
    await page.waitFor(`location.hash === '#p1'`);
    await page.evaluate('document.querySelector(".chart-surface").focus()');
    await key(page, 'ArrowDown');
    await key(page, 'ArrowRight');
    await page.waitFor(`${waiting} === '4 min'`);
    await page.evaluate(`document.querySelector('.plates a[href="#p2"]').click()`);
    await page.waitFor(onPlate(2));
    await page.evaluate('history.back()');
    await page.waitFor(onPlate(1));
    await new Promise((r) => setTimeout(r, 300));
    assert.equal(await page.evaluate(waiting), '4 min', 'Back brought the shared timetable back over the work');
    noProblems(page, 'back');
  } finally {
    await page.close();
  }
});

run('keyboard reach: a skip link goes straight to the chart, and the plates are one tab stop', async () => {
  const page = await open({ width: 1280, height: 800 }, '#p1');
  try {
    const active = 'document.activeElement?.className + "#" + document.activeElement?.id';
    await key(page, 'Tab');
    assert.match(await page.evaluate(active), /^skip-link#/);
    await key(page, 'Enter');
    await page.waitFor(`document.activeElement?.id === 'chart'`);

    await page.evaluate('document.activeElement.blur(); document.querySelector(".skip-link").focus()');
    await key(page, 'Tab'); // the theme switch
    await key(page, 'Tab'); // the current plate
    assert.equal(await page.evaluate('document.activeElement.id'), 'plate-1');
    assert.equal(await page.evaluate(`document.querySelectorAll('.plate-link[tabindex="0"]').length`), 1);
    const focused = (id) => page.waitFor(`document.activeElement?.id === ${JSON.stringify(id)}`, 3000);
    await key(page, 'ArrowRight');
    await key(page, 'ArrowRight');
    await focused('plate-3');
    await key(page, 'End');
    await focused('plate-13');
    await key(page, 'Home');
    await key(page, 'ArrowRight');
    await focused('plate-2');
    await key(page, 'Enter');
    await page.waitFor(onPlate(2));
    await key(page, 'Tab'); // out of the plates in one step, to Run
    assert.equal(await page.evaluate('document.activeElement.textContent.trim()'), 'Run');
    noProblems(page, 'keyboard reach');
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

run('theme: left on automatic, the switch follows the system when it changes', async () => {
  const page = await open({ width: 1280, height: 800, scheme: 'light' }, '#p1');
  const toggle = text('.theme-toggle');
  const scheme = (value) => page.send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value }] });
  try {
    assert.equal(await page.evaluate(toggle), 'Cyanotype');
    await scheme('dark');
    await page.waitFor(`${toggle} === 'Paper'`, 5000);
    assert.equal(await page.evaluate('getComputedStyle(document.body).backgroundColor'), 'rgb(15, 51, 85)');
    await scheme('light');
    await page.waitFor(`${toggle} === 'Cyanotype'`, 5000);
    noProblems(page, 'system theme');
  } finally {
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
