// Design-time mirror of the game's rules (src/Rail.elm is the source of truth;
// the Elm tests check every known solution against it, and MirrorTests checks
// the two agree on many more timetables) plus the par search.
//
// The search fixes, for every pair of trains that share track, the order in
// which they use it: where two opposing trains meet, or where one overtakes
// another (at most once). For each choice it computes the earliest schedule
// that respects those orders, prunes on deadlines and on the best waiting found
// so far, and handles a crowded loop by making one train leave before another
// arrives (a bounded number of times). It is not exhaustive, so a par it finds
// may be beatable; prove.mjs checks par exhaustively for plates I to VIII.
export const run = (level, train, g) => {
  const len = Math.abs(level.stations[g + 1].km - level.stations[g].km);
  return Math.ceil((len * 60) / train.speed);
};

export const route = (t) => {
  const s = [];
  const step = t.to > t.from ? 1 : -1;
  for (let i = t.from; i !== t.to + step; i += step) s.push(i);
  return s;
};

export function schedule(level, plan) {
  return level.trains.map((t, ti) => {
    const st = route(t);
    const n = st.length - 1;
    const arr = [null];
    const dep = [plan[ti].dep];
    for (let k = 0; k < n; k++) {
      const g = Math.min(st[k], st[k + 1]);
      arr[k + 1] = dep[k] + run(level, t, g);
      if (k + 1 < n) dep[k + 1] = arr[k + 1] + plan[ti].dwells[k];
    }
    const legs = [];
    for (let k = 0; k < n; k++) legs.push({ g: Math.min(st[k], st[k + 1]), enter: dep[k], exit: arr[k + 1] });
    const calls = [];
    for (let k = 1; k < n; k++) calls.push({ s: st[k], a: arr[k], d: dep[k] });
    return { ti, st, arr, dep, legs, calls, down: t.to > t.from, arrival: arr[n] };
  });
}

export function conflicts(level, plan) {
  const sch = schedule(level, plan);
  const out = [];
  for (let i = 0; i < sch.length; i++)
    for (let j = i + 1; j < sch.length; j++)
      for (const a of sch[i].legs)
        for (const b of sch[j].legs)
          if (a.g === b.g && a.enter < b.exit && b.enter < a.exit)
            out.push({ kind: sch[i].down === sch[j].down ? 'rear' : 'head', trains: [i, j], g: a.g });
  level.stations.forEach((s, si) => {
    const iv = [];
    sch.forEach((r) => r.calls.forEach((c) => c.s === si && iv.push({ ti: r.ti, a: c.a, d: c.d })));
    const seen = new Set();
    for (const p of iv) {
      const here = iv.filter((q) => q.a <= p.a && p.a <= q.d);
      if (here.length > s.tracks) {
        const key = here.map((q) => q.ti).sort().join(',');
        if (!seen.has(key)) { seen.add(key); out.push({ kind: 'crowd', trains: here.map((q) => q.ti), s: si }); }
      }
    }
  });
  return out;
}

export function waiting(level, plan) {
  return level.trains.reduce((acc, t, i) => acc + (plan[i].dep - t.ready) + plan[i].dwells.reduce((x, d) => x + d - t.call, 0), 0);
}

export function late(level, plan) {
  const sch = schedule(level, plan);
  return sch.filter((r) => r.arrival > level.trains[r.ti].due).map((r) => r.ti);
}

export function initialPlan(level) {
  return level.trains.map((t) => ({ dep: t.ready, dwells: Array(Math.abs(t.to - t.from) - 1).fill(t.call) }));
}

export function solved(level, plan) {
  return conflicts(level, plan).length === 0 && late(level, plan).length === 0;
}

// Branch and bound over pairwise orderings on shared segments.
export function solve(level, { limitLeaves = 5e6, prune = true, limitNodes = Infinity } = {}) {
  let nodes = 0, truncated = false;
  const T = level.trains;
  const info = T.map((t) => {
    const st = route(t);
    const segs = [];
    for (let k = 0; k < st.length - 1; k++) segs.push(Math.min(st[k], st[k + 1]));
    return { st, segs, down: t.to > t.from, lo: Math.min(t.from, t.to), hi: Math.max(t.from, t.to), runs: segs.map((g) => run(level, t, g)) };
  });
  const pairs = [];
  for (let a = 0; a < T.length; a++)
    for (let b = a + 1; b < T.length; b++) {
      const lo = Math.max(info[a].lo, info[b].lo);
      const hi = Math.min(info[a].hi, info[b].hi);
      if (hi <= lo) continue;
      const opts = [];
      const shared = [];
      for (let g = lo; g < hi; g++) shared.push(g);
      if (info[a].down !== info[b].down) {
        const D = info[a].down ? a : b;
        const U = D === a ? b : a;
        for (let m = lo; m <= hi; m++) opts.push(shared.map((g) => (g < m ? [D, U] : [U, D])));
      } else {
        const down = info[a].down;
        opts.push(shared.map(() => [a, b]));
        opts.push(shared.map(() => [b, a]));
        for (let m = lo + 1; m < hi; m++) {
          const before = (g) => (down ? g < m : g >= m);
          opts.push(shared.map((g) => (before(g) ? [a, b] : [b, a])));
          opts.push(shared.map((g) => (before(g) ? [b, a] : [a, b])));
        }
      }
      pairs.push({ a, b, shared, opts });
    }
  pairs.sort((p, q) => q.shared.length - p.shared.length);

  const pos = (ti, station) => info[ti].st.indexOf(station);
  // Earliest times given constraints [{first, second, g}]
  function earliest(cons) {
    const lb = info.map((x) => new Array(x.st.length).fill(-Infinity));
    let dep, arr;
    for (let iter = 0; iter < 200; iter++) {
      dep = []; arr = [];
      T.forEach((t, ti) => {
        const n = info[ti].st.length - 1;
        const d = [Math.max(t.ready, lb[ti][0])];
        const r = [null];
        for (let k = 0; k < n; k++) {
          r[k + 1] = d[k] + info[ti].runs[k];
          if (k + 1 < n) d[k + 1] = Math.max(r[k + 1] + t.call, lb[ti][k + 1]);
        }
        dep.push(d); arr.push(r);
      });
      let changed = false;
      for (const c of cons) {
        if (c.kind === 'after') {
          const kx = pos(c.x, c.s), ky = pos(c.y, c.s);
          const need = dep[c.x][kx] + 1 - info[c.y].runs[ky - 1];
          if (lb[c.y][ky - 1] < need && dep[c.y][ky - 1] < need) { lb[c.y][ky - 1] = need; changed = true; }
          continue;
        }
        const f = c.first, s = c.second, g = c.g;
        const fExit = info[f].down ? g + 1 : g;
        const sEnter = info[s].down ? g : g + 1;
        const need = arr[f][pos(f, fExit)];
        const k = pos(s, sEnter);
        if (lb[s][k] < need && dep[s][k] < need) { lb[s][k] = need; changed = true; }
      }
      if (!changed) return { dep, arr };
      if (dep.some((d) => d.some((x) => x > level.span * 4))) return null;
    }
    return null;
  }
  const pure = T.map((t, ti) => info[ti].runs.reduce((x, y) => x + y, 0) + t.call * (info[ti].st.length - 2));
  function bound(e) {
    let w = 0;
    for (let ti = 0; ti < T.length; ti++) {
      const n = info[ti].st.length - 1;
      const a = e.arr[ti][n];
      if (a > T[ti].due) return Infinity;
      w += a - T[ti].ready - pure[ti];
    }
    return w;
  }
  let best = Infinity, bestPlan = null, leaves = 0, feasibleLeaves = 0, optimalCount = 0;
  const cons = [];
  function dfs(d) {
    if (++nodes > limitNodes) { truncated = true; return; }
    const e = earliest(cons);
    if (!e) return;
    const b = bound(e);
    if (b === Infinity || (prune && b > best)) return;
    if (d === pairs.length) {
      leaves++;
      const plan = T.map((t, ti) => ({ dep: e.dep[ti][0], dwells: e.dep[ti].slice(1).map((x, k) => x - e.arr[ti][k + 1]) }));
      if (!solved(level, plan)) {
        const crowd = conflicts(level, plan).find((c) => c.kind === 'crowd');
        if (!crowd || late(level, plan).length || conflicts(level, plan).some((c) => c.kind !== 'crowd')) return;
        if (cons.filter((c) => c.kind === 'after').length > 6) return;
        for (const x of crowd.trains) for (const y of crowd.trains) {
          if (x === y) continue;
          cons.push({ kind: 'after', x, y, s: crowd.s });
          dfs(d);
          cons.pop();
        }
        return;
      }
      feasibleLeaves++;
      const w = waiting(level, plan);
      if (w < best) { best = w; bestPlan = plan; optimalCount = 1; }
      else if (w === best) optimalCount++;
      return;
    }
    if (leaves > limitLeaves) return;
    const p = pairs[d];
    const scored = p.opts.map((o) => {
      const added = p.shared.map((g, i) => ({ first: o[i][0], second: o[i][1], g }));
      cons.push(...added);
      const e2 = earliest(cons);
      cons.length -= added.length;
      return { added, b: e2 ? bound(e2) : Infinity };
    }).filter((x) => x.b !== Infinity).sort((x, y) => x.b - y.b);
    for (const { added, b: ob } of scored) {
      if (prune && ob > best) break;
      cons.push(...added);
      dfs(d + 1);
      cons.length -= added.length;
    }
  }
  dfs(0);
  return { truncated, best, bestPlan, leaves, feasibleLeaves, optimalCount, pairs: pairs.length, options: pairs.reduce((x, p) => x * p.opts.length, 1) };
}

// Count feasible orderings ignoring optimality (difficulty signal): fraction of leaves meeting deadlines.
export function describe(level) {
  const init = initialPlan(level);
  const c = conflicts(level, init);
  const l = late(level, init);
  const s = solve(level);
  const all = solve(level, { prune: false, limitNodes: 300000 });
  return { feasibleOrderings: (all.truncated ? '>=' : '') + all.feasibleLeaves, id: level.id, title: level.title, trains: level.trains.length, stations: level.stations.length, initialConflicts: c.length, initialLate: l.length, par: s.best, optimalCount: s.optimalCount, feasibleLeaves: s.feasibleLeaves, space: s.options, plan: s.bestPlan };
}
