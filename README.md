# Single Track

A timetable puzzle: run trains on one track without a collision.

![Plate XIII, the grand chart, paused mid-run: six ink threads cross a graphic timetable, with the surveyed line and its trains below](docs/screenshot.png)

The line is drawn as a **Marey diagram**, the graphic timetable of the 1880s
(the famous Paris–Lyon chart is one): time runs left to right, the stations
run down the side spaced by their real distance, and every train is an ink
thread. A steep thread is a fast train; a flat stretch is a train waiting at a
station. On a single-track line two trains can only meet or overtake where
there is a passing loop, so the whole puzzle is visible at a glance: wherever
two threads cross between stations, there is a collision.

## The 30-second experience

1. Open a plate. The starting timetable always has at least one conflict,
   marked on the chart with a small red cross-hatch and listed in plain words
   underneath ("Head-on: Down local and Up local meet between Brill and Colley
   at 06:11").
2. Drag a thread sideways to change when that train leaves, or drag one of
   its round knobs to make it wait longer at a station. Conflicts update as
   you drag. Every train card (and the bar under the chart) has − / + steppers
   that do the same thing.
3. When the status line says **Line clear**, press **Run**. A time cursor
   sweeps across the chart while the trains move along a survey drawing of
   the line below it. A clean run earns an inspection stamp with your total
   waiting against the plate's par.
4. **Share timetable** puts your solution in the address (for example
   `#p1/0.3-3.0`) so anyone can open it and press Run.

Thirteen hand-designed plates climb gently: a first meeting at a loop, choosing
between loops, a halt where trains cannot pass, overtaking, three trains, a
loop's two-track limit, trains that must call at every station, short
workings that run only part of the line, and finally six trains on seven
stations.

### Rules the game enforces

- A train occupies a section of single track from the moment it leaves one
  station until it reaches the next. Two trains may never share a section at
  the same time. Opposite directions is a **head-on** conflict; the same
  direction is a **rear-end** conflict (so overtaking is only possible at a
  station).
- A station holds as many trains at once as it has tracks: a **halt** (dashed
  rule) has one, a **loop** (double rule) two, a **yard** three. Too many is a
  **crowded** conflict. Trains start from and finish in sidings, so a train at
  its own origin or destination does not count.
- Every train has a time it is ready to leave, a deadline at its destination,
  a speed (express 60 km/h, stopping 40, goods 30; section times are rounded
  up to whole minutes), and sometimes a minimum call at each station.
- **Waiting** is every minute a train spends beyond its earliest start and
  its required calls. **Par** is the least waiting that the design-time search
  in `tools/par-search/` found for that plate. The search is not exhaustive,
  so par may be beatable; the stamp says so when you do.
- A **move** is one adjustment of one knob. Nudging the same knob again
  straight away continues the same move, so dragging a departure twelve
  minutes, or pressing → twelve times, is one move and one undo step.

### Keys

Focus the chart (Tab), then: `1`–`6` pick a train, `←` `→` adjust the selected
knob by a minute (`Shift` for five), `↑` `↓` move between that train's
stations, `Enter` runs. `Ctrl`/`⌘`+`Z` undoes and `Ctrl`/`⌘`+`Shift`+`Z` (or
`Ctrl`+`Y`) redoes, from anywhere on the page.

With **reduced motion** set, Run does not animate the trains: the cursor steps
ten minutes at a time and the survey drawing redraws at each step.

## Why Elm

The whole game is a pure function of a small immutable value, and Elm is
built for exactly that.

- `src/Rail.elm` is the model and the rules: running times, the schedule a
  timetable implies, conflict detection (with the exact crossing point of two
  threads for the mark), deadlines, waiting and validation. It has no effects
  at all.
- `src/History.elm` is undo and redo in a few dozen lines. Because every game state
  is an immutable value, a history is just two stacks either side of the
  present one; nothing is copied or diffed.
- `src/Game.elm` combines the two: the move counting and the rule that
  repeated nudges of one knob are a single undo step.
- `src/Share.elm` turns timetables into link fragments and back, with every
  number checked against the plate.
- `src/Levels.elm` is the level data, typed Elm records.
- `src/Chart.elm` and `src/Survey.elm` draw the Marey diagram and the survey
  drawing as SVG; `src/Main.elm` wires everything to the browser.

The compiler's exhaustive checking of custom types (`HeadOn | RearEnd |
Crowded`, `Departure | Dwell n`) did real work while the rules changed during
design. The only JavaScript is `web/glue.js` (about seventy lines: flags,
localStorage, the clipboard, pointer capture and the theme attribute) and
`web/boot.js`, which applies a saved theme before first paint.

## Build and test

Requirements: Node 20 or newer. The Elm compiler, elm-test and terser are
pinned dev dependencies (`elm` 0.19.1-6, `elm-test` 0.19.1-revision17,
`terser` 5.44.1). The first build downloads the Elm packages listed in
`elm.json` into the Elm package cache (`~/.elm`, or `$ELM_HOME`).

```sh
npm ci
npm run build      # dist/: index.html, hashed assets, _headers, notices
npm test           # elm-test, then build, then the end-to-end checks
npm run serve      # serve dist/ on a free local port
```

`npm test` runs:

- **elm-test** (151 tests): head-on, rear-end, overtaking and meeting at a
  loop, touching times, halts, loop capacity, origins and destinations,
  arrival times and deadlines, knob bounds, validation, positions; every
  plate's known solution is valid, conflict-free and on time, its waiting
  equals the plate's par, and the starting timetable is not already solved;
  share links round-trip (fuzzed over every plate) and hostile links are
  refused; undo, redo, move counting and reset.
- **Node checks** against the built `dist/`: the page references hashed
  assets that exist, the headers are right, the third-party notices cover
  every bundled package, WCAG contrast of the colour tokens in both themes,
  the level data matches the design data, and the local server behaves.
- **Headless Chrome** (over the DevTools protocol): no console errors; the
  keyboard, a real pointer drag, undo and redo; Run with and without reduced
  motion; every plate's known solution loaded from a link; bad and enormous
  links; the share button; the theme toggle; and every plate at a true
  400 px phone width with no sideways scrolling. If Chrome is not found these
  are skipped locally; set `REQUIRE_BROWSER=1` to make that a failure, or
  `CHROME_PATH` to point at a browser.

To re-run the par search: `node tools/par-search/search.mjs` then
`node tools/par-search/emit.mjs` (the tests check the Elm files match).

## Running on Cloudflare (free)

It is a static site. `npm run build` produces `dist/` (seven files, about
108 KB before compression), deployable to **Cloudflare Pages** with no Worker
and no storage. The Pages free tier serves static assets with unlimited
requests, up to 20,000 files per site and 25 MiB per file, so this fits with
room to spare. Progress and the theme choice live in the visitor's own
browser (localStorage); the game sends nothing anywhere. The only
third-party request is the typefaces, fetched from Google Fonts.

`dist/_headers` sets a strict Content-Security-Policy (scripts only from the
site itself; styles and fonts from Google Fonts) and a one-year immutable
cache only for the content-hashed files under `/assets/`.

To deploy your own copy: `npm run build`, then
`npx wrangler pages deploy dist --project-name single-track`. This repository
deliberately has no deploy script and no `account_id`; the owner deploys
through a separate guarded script so the right account is always used.

## Honest limitations

- **Par is not proven optimal.** It is the least waiting a branch-and-bound
  search found; the search allows at most one overtake per pair of trains and
  handles crowded loops with a bounded number of extra constraints. The tests
  prove each par is achievable, not that it cannot be beaten.
- **The railway is simplified.** Trains are points with constant speed, no
  acceleration or braking, whole minutes, and zero headway: a train may enter a
  section the minute another leaves it. Lines, stations, speeds and times are
  invented.
- **Thirteen plates, one line each.** There is no level editor yet.
- **Dragging on a phone is coarse.** At 400 px a minute is about two pixels;
  the steppers are the precise way to edit there.
- **The chart is visual.** Keyboard users can do everything, and the conflict
  log, train cards and knob bar give the same information in text, but a
  screen reader hears a summary of the graph rather than the graph itself.
- **Fonts come from Google Fonts** at run time; if that is blocked the page
  falls back to local serif faces.
- **Copying the share link** uses the Clipboard API; where that is refused the
  link is shown for copying by hand. The automated tests check the link, not
  the clipboard.
- **Progress is per browser.** There is no account and no server.

## Next

- A leaderboard of least waiting and fewest moves per plate (Cloudflare D1).
- A level editor, and shareable user-made plates.
- More lines: junctions, double-track sections, and trains that reverse.
- A proven par, from an exhaustive search.

## Credits and licence

Built by Ramen Protocol with AI assistance (Claude). MIT licence, see
`LICENSE`. The built site bundles the Elm core packages (BSD-3-Clause); their
notices ship as `dist/THIRD-PARTY-NOTICES.txt` and are linked from the page
footer. The typefaces, EB Garamond and IM FELL English SC, are loaded from
Google Fonts under the SIL Open Font License.
