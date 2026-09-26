// Regenerate src/Levels.elm and tests/KnownSolutions.elm from levels.mjs and
// results.json. With --check, compare instead of writing (used by the tests).
//   node tools/par-search/emit.mjs [--check]
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { levels } from './levels.mjs';
const here = dirname(fileURLToPath(import.meta.url));
const res = JSON.parse(readFileSync(join(here, 'results.json'), 'utf8'));
const repo = join(here, '..', '..');
const check = process.argv.includes('--check');
const outputs = [];
const put = (file, text) => outputs.push([file, text]);
const q = (s) => JSON.stringify(s);
const speedName = { 60: 'express', 40: 'local', 30: 'goods' };
const stationFn = (s, i, n) => (i === 0 || i === n - 1 ? 'terminus' : s.tracks === 1 ? 'halt' : s.tracks === 2 ? 'loop' : 'yard');
// Plates whose par prove.mjs has checked exhaustively (see README).
const PROVEN_THROUGH = 8;
let elm = `module Levels exposing (all, count, get, parProven)

{-| The hand-designed plates, from a first meeting to the grand chart.

Every plate has a known solution in tests/LevelTests.elm, and its par is the
least total waiting that the design-time search found for it.

-}

import Array
import Rail exposing (Level, Station)


all : List Level
all =
    [ ${levels.map((l) => 'plate' + l.id).join('\n    , ')}
    ]


count : Int
count =
    List.length all


get : Int -> Maybe Level
get id =
    List.filter (\\l -> l.id == id) all |> List.head


{-| Whether a plate's par is proven to be the least waiting possible:
tools/par-search/prove.mjs tries every timetable with less waiting and none
solves the plate. On the other plates par is the best the search found.
-}
parProven : Int -> Bool
parProven id =
    id <= ${PROVEN_THROUGH}



-- SPEEDS (km/h)


express : Int
express =
    60


local : Int
local =
    40


goods : Int
goods =
    30



-- STATIONS


{-| End of the line. Trains start from and finish in sidings here.
-}
terminus : String -> Int -> Station
terminus name km =
    { name = name, km = km, tracks = 3 }


{-| A passing loop: two tracks, so two trains can meet or overtake.
-}
loop : String -> Int -> Station
loop name km =
    { name = name, km = km, tracks = 2 }


{-| One track: a train may stop, but nothing can pass it here.
-}
halt : String -> Int -> Station
halt name km =
    { name = name, km = km, tracks = 1 }


{-| A station with a yard: three tracks.
-}
yard : String -> Int -> Station
yard name km =
    { name = name, km = km, tracks = 3 }
`;
for (const l of levels) {
  const n = l.stations.length;
  elm += `


plate${l.id} : Level
plate${l.id} =
    { id = ${l.id}
    , title = ${q(l.title)}
    , brief = ${q(l.brief)}
    , clock = ${l.clock}
    , span = ${l.span}
    , stations =
        Array.fromList
            [ ${l.stations.map((s, i) => `${stationFn(s, i, n)} ${q(s.name)} ${s.km}`).join('\n            , ')}
            ]
    , trains =
        [ ${l.trains.map((t) => `{ name = ${q(t.name)}, ink = ${t.ink}, from = ${t.from}, to = ${t.to}, speed = ${speedName[t.speed]}, ready = ${t.ready}, due = ${t.due}, call = ${t.call} }`).join('\n        , ')}
        ]
    , par = ${res[l.id].par}
    }`;
}
put(join(repo, 'src', 'Levels.elm'), elm + '\n');

let sol = `module KnownSolutions exposing (solutions)

{-| One known solution per plate: [ departure, wait, wait, ... ] for each
train, in the plate's train order. Found at design time; the tests check
them against the game's own rules.
-}


solutions : List ( Int, List (List Int) )
solutions =
    [ ${levels.map((l) => `( ${l.id}, [ ${res[l.id].plan.map((p) => `[ ${[p.dep, ...p.dwells].join(', ')} ]`).join(', ')} ] )`).join('\n    , ')}
    ]
`;
put(join(repo, 'tests', 'KnownSolutions.elm'), sol);
let stale = 0;
for (const [file, text] of outputs) {
  if (check) {
    if (readFileSync(file, 'utf8') !== text) {
      console.error(`out of date: ${file}`);
      stale++;
    }
  } else {
    writeFileSync(file, text);
  }
}
process.exitCode = stale ? 1 : 0;
