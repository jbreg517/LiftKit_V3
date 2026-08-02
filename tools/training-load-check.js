#!/usr/bin/env node
'use strict';
//
// Verification port of LiftKit/Services/TrainingLoad.swift.
//
// There is no Swift toolchain on the dev machine, so the arithmetic is mirrored here
// and asserted against hand-computed expectations. This does NOT prove the Swift
// compiles — Codemagic does that — it proves the maths is what we think it is.
//
// Keep in step with TrainingLoad.swift. Anything changed there and not here is a
// silent divergence, which is the whole failure mode this file exists to catch.
//
//   node tools/training-load-check.js
//
// Week boundaries use Sunday, matching Calendar.current in a US locale (the Swift side
// uses the device calendar, so a user whose week starts Monday gets Monday buckets —
// that only shifts which sessions land in which bucket, not any of the arithmetic).

const EASY_SET_THRESHOLD = 5;

// ---------------------------------------------------------------- model helpers

const day = (iso) => new Date(`${iso}T09:00:00`);
const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const startOfWeek = (d) => addDays(startOfDay(d), -startOfDay(d).getDay());
const addWeeks = (d, n) => addDays(d, n * 7);
const key = (d) => startOfDay(d).toISOString().slice(0, 10);

/** A session: { startedAt, minutes, sessionRPE, entries: [{ rpe, sets: [...], muscles }] } */
function session({ startedAt, minutes, sessionRPE = null, entries = [], active = false }) {
  return { startedAt, minutes, sessionRPE, entries, active };
}
function set({ rpe = null, warmup = false } = {}) {
  return { rpe, warmup };
}

// ---------------------------------------------------------------- TrainingLoad

function ratedEfforts(s) {
  const values = [];
  for (const entry of s.entries) {
    const setRPEs = (entry.sets || [])
      .filter((x) => !x.warmup)
      .map((x) => x.rpe)
      .filter((r) => r !== null && r > 0);
    if (setRPEs.length) values.push(...setRPEs);
    else if (entry.rpe && entry.rpe > 0) values.push(entry.rpe);
  }
  return values;
}

function rpeFor(s) {
  if (s.sessionRPE && s.sessionRPE > 0) return { value: s.sessionRPE, source: 'entered' };
  const rated = ratedEfforts(s);
  if (!rated.length) return { value: 0, source: 'none' };
  return { value: rated.reduce((a, b) => a + b, 0) / rated.length, source: 'derived' };
}

function srpe(s) {
  const r = rpeFor(s);
  if (r.source === 'none') return null;
  if (!(s.minutes > 0)) return null;
  return r.value * s.minutes;
}

const isWorkingSet = (x) => !x.warmup;
function isHardSet(x) {
  if (!isWorkingSet(x)) return false;
  if (x.rpe !== null && x.rpe > 0 && x.rpe < EASY_SET_THRESHOLD) return false;
  return true;
}

function hardSetCount(s) {
  return s.entries.reduce((n, e) => n + (e.sets || []).filter(isHardSet).length, 0);
}

/** muscles: [{ muscle, weight }] mirroring Exercise.muscleContributions */
function hardSetsByMuscle(sessions, cutoff) {
  const counts = new Map();
  for (const s of sessions) {
    if (s.active || s.startedAt < cutoff) continue;
    for (const entry of s.entries) {
      if (!entry.muscles) continue;
      const sets = (entry.sets || []).filter(isHardSet).length;
      if (!sets) continue;
      for (const c of entry.muscles) {
        counts.set(c.muscle, (counts.get(c.muscle) || 0) + sets * c.weight);
      }
    }
  }
  return [...counts.entries()]
    .map(([muscle, sets]) => ({ muscle, sets }))
    .sort((a, b) => b.sets - a.sets);
}

function dailyLoads(sessions) {
  const byDay = new Map();
  for (const s of sessions) {
    if (s.active) continue;
    const d = startOfDay(s.startedAt);
    const k = key(d);
    const load = byDay.get(k) || { date: d, srpe: 0, minutes: 0, sessions: 0, ratedSessions: 0, hardSets: 0 };
    load.sessions += 1;
    load.minutes += s.minutes;
    load.hardSets += hardSetCount(s);
    const au = srpe(s);
    if (au !== null) {
      load.srpe += au;
      load.ratedSessions += 1;
    }
    byDay.set(k, load);
  }
  return [...byDay.values()].sort((a, b) => a.date - b.date);
}

function weeklyLoads(sessions, weeks, now) {
  if (weeks <= 0) return [];
  const thisWeek = startOfWeek(now);
  const starts = [];
  const buckets = new Map();
  for (let offset = weeks - 1; offset >= 0; offset--) {
    const start = addWeeks(thisWeek, -offset);
    buckets.set(key(start), { weekStart: start, srpe: 0, minutes: 0, sessions: 0, ratedSessions: 0, hardSets: 0 });
    starts.push(start);
  }
  const earliest = starts[0];
  for (const s of sessions) {
    if (s.active || s.startedAt < earliest) continue;
    const week = buckets.get(key(startOfWeek(s.startedAt)));
    if (!week) continue;
    week.sessions += 1;
    week.minutes += s.minutes;
    week.hardSets += hardSetCount(s);
    const au = srpe(s);
    if (au !== null) {
      week.srpe += au;
      week.ratedSessions += 1;
    }
  }
  return starts.map((d) => buckets.get(key(d)));
}

function rollingLoad(days, end, window) {
  const last = startOfDay(end);
  const first = addDays(last, -(window - 1));
  return days
    .filter((d) => d.date >= first && d.date <= last)
    .reduce((a, d) => a + d.srpe, 0);
}

function acuteChronicRatio(days, now) {
  if (!days.length) return null;
  const earliest = days[0].date;
  const cutoff = addDays(startOfDay(now), -27);
  if (earliest > cutoff) return null;
  const chronic = rollingLoad(days, now, 28) / 4;
  if (!(chronic > 0)) return null;
  return rollingLoad(days, now, 7) / chronic;
}

function monotony(days, end) {
  const last = startOfDay(end);
  const first = addDays(last, -6);
  const byDay = new Map(days.map((d) => [key(d.date), d.srpe]));
  const values = [];
  for (let i = 0; i < 7; i++) values.push(byDay.get(key(addDays(first, i))) || 0);
  const mean = values.reduce((a, b) => a + b, 0) / 7;
  if (!(mean > 0)) return null;
  const variance = values.reduce((a, v) => a + (v - mean) ** 2, 0) / 7;
  const sd = Math.sqrt(variance);
  if (!(sd > 0)) return null;
  return mean / sd;
}

function strain(days, end) {
  const m = monotony(days, end);
  if (m === null) return null;
  return rollingLoad(days, end, 7) * m;
}

// ---------------------------------------------------------------- assertions

let checks = 0;
let failures = 0;
function check(label, actual, expected, tolerance = 1e-9) {
  checks++;
  const ok =
    expected === null || actual === null
      ? actual === expected
      : typeof expected === 'number'
        ? Math.abs(actual - expected) <= tolerance
        : JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) {
    failures++;
    console.log(`  FAIL  ${label}\n          expected ${JSON.stringify(expected)}\n          actual   ${JSON.stringify(actual)}`);
  }
}
function group(name, fn) {
  console.log(`\n${name}`);
  fn();
}

// ---- session RPE resolution

group('Session RPE', () => {
  const entered = session({ startedAt: day('2026-07-01'), minutes: 45, sessionRPE: 7 });
  check('entered rating wins', rpeFor(entered).value, 7);
  check('entered source', rpeFor(entered).source, 'entered');
  check('sRPE = RPE x minutes', srpe(entered), 315);

  // Derived: warm-ups excluded, so the mean is over 8 and 8, not 3, 8, 8.
  const derived = session({
    startedAt: day('2026-07-01'),
    minutes: 30,
    entries: [{ sets: [set({ rpe: 3, warmup: true }), set({ rpe: 8 }), set({ rpe: 8 })] }],
  });
  check('derived skips warm-up ratings', rpeFor(derived).value, 8);
  check('derived source', rpeFor(derived).source, 'derived');
  check('derived sRPE', srpe(derived), 240);

  // Exercise-level RPE is the fallback only when no set carries one (AMRAP etc.).
  const entryLevel = session({
    startedAt: day('2026-07-01'),
    minutes: 20,
    entries: [{ rpe: 9, sets: [] }],
  });
  check('exercise-level RPE used when no sets rated', rpeFor(entryLevel).value, 9);

  const bothLevels = session({
    startedAt: day('2026-07-01'),
    minutes: 20,
    entries: [{ rpe: 9, sets: [set({ rpe: 6 })] }],
  });
  check('set ratings beat the exercise rating', rpeFor(bothLevels).value, 6);

  const unrated = session({ startedAt: day('2026-07-01'), minutes: 60 });
  check('unrated source', rpeFor(unrated).source, 'none');
  check('unrated sRPE is null, not zero', srpe(unrated), null);

  const zeroMinutes = session({ startedAt: day('2026-07-01'), minutes: 0, sessionRPE: 8 });
  check('no measured time means no load', srpe(zeroMinutes), null);
});

// ---- hard sets

group('Hard sets', () => {
  check('warm-up is not a working set', isHardSet(set({ warmup: true })), false);
  check('unrated working set counts', isHardSet(set()), true);
  check('rated-easy set does not count', isHardSet(set({ rpe: 3 })), false);
  check('threshold is inclusive at 5', isHardSet(set({ rpe: 5 })), true);
  check('hard set counts', isHardSet(set({ rpe: 9 })), true);

  const s = session({
    startedAt: day('2026-07-01'),
    minutes: 40,
    entries: [
      { sets: [set({ warmup: true }), set({ warmup: true }), set({ rpe: 8 }), set({ rpe: 9 }), set({ rpe: 2 })] },
      { sets: [set(), set()] },
    ],
  });
  check('session hard sets', hardSetCount(s), 4);
});

group('Hard sets by muscle', () => {
  // Bench: chest primary, triceps + shoulders secondary at half credit.
  const bench = {
    sets: [set({ warmup: true }), set(), set(), set()],
    muscles: [
      { muscle: 'chest', weight: 1 },
      { muscle: 'triceps', weight: 0.5 },
      { muscle: 'shoulders', weight: 0.5 },
    ],
  };
  const flyes = { sets: [set(), set()], muscles: [{ muscle: 'chest', weight: 1 }] };
  const s = session({ startedAt: day('2026-07-01'), minutes: 50, entries: [bench, flyes] });
  const result = hardSetsByMuscle([s], day('2026-06-01'));
  check('chest gets full credit from both', result.find((r) => r.muscle === 'chest').sets, 5);
  check('triceps gets half credit, warm-up excluded', result.find((r) => r.muscle === 'triceps').sets, 1.5);
  check('sorted highest first', result[0].muscle, 'chest');
  check('cutoff excludes older sessions', hardSetsByMuscle([s], day('2026-08-01')).length, 0);
});

// ---- daily and weekly aggregation

group('Daily loads', () => {
  const twoSessions = [
    session({ startedAt: day('2026-07-01'), minutes: 30, sessionRPE: 6 }), // 180
    session({ startedAt: day('2026-07-01'), minutes: 20, sessionRPE: 9 }), // 180
    session({ startedAt: day('2026-07-03'), minutes: 40 }),                // unrated
  ];
  const days = dailyLoads(twoSessions);
  check('one row per trained day', days.length, 2);
  check('same-day sessions sum', days[0].srpe, 360);
  check('same-day session count', days[0].sessions, 2);
  check('unrated day still appears', days[1].sessions, 1);
  check('unrated day contributes no AU', days[1].srpe, 0);
  check('rated count exposes the gap', days[1].ratedSessions, 0);
  check('untrained days are omitted, not zero-filled',
        days.some((d) => key(d.date) === '2026-07-02'), false);

  const withActive = dailyLoads([
    session({ startedAt: day('2026-07-05'), minutes: 30, sessionRPE: 7 }),
    session({ startedAt: day('2026-07-05'), minutes: 10, sessionRPE: 7, active: true }),
  ]);
  check('in-progress session excluded', withActive[0].sessions, 1);
});

group('Weekly loads', () => {
  const now = day('2026-07-15'); // a Wednesday
  const sessions = [
    session({ startedAt: day('2026-07-13'), minutes: 60, sessionRPE: 7 }), // this week: 420
    session({ startedAt: day('2026-07-08'), minutes: 45, sessionRPE: 6 }), // last week: 270
    session({ startedAt: day('2026-05-01'), minutes: 60, sessionRPE: 8 }), // outside the window
  ];
  const weeks = weeklyLoads(sessions, 4, now);
  check('window length is exact', weeks.length, 4);
  check('oldest first', weeks[0].weekStart < weeks[3].weekStart, true);
  check('current week last', weeks[3].srpe, 420);
  check('previous week', weeks[2].srpe, 270);
  check('empty weeks inside the window are kept as zero', weeks[0].srpe, 0);
  check('empty weeks report no sessions', weeks[0].sessions, 0);
  check('sessions outside the window are dropped',
        weeks.reduce((a, w) => a + w.sessions, 0), 2);
});

// ---- rolling windows

group('Rolling load and ACWR', () => {
  const now = day('2026-07-28');
  // 8 weeks of a steady 300 AU on Mondays and Thursdays.
  const sessions = [];
  for (let i = 0; i < 56; i++) {
    const d = addDays(startOfDay(now), -i);
    if (d.getDay() === 1 || d.getDay() === 4) {
      sessions.push(session({ startedAt: new Date(d.getTime() + 9 * 3600e3), minutes: 50, sessionRPE: 6 }));
    }
  }
  const days = dailyLoads(sessions);
  check('7-day window catches two sessions', rollingLoad(days, now, 7), 600);
  check('28-day window catches eight', rollingLoad(days, now, 28), 2400);
  check('steady training gives a ratio of 1', acuteChronicRatio(days, now), 1, 1e-9);

  // A spike week: one extra hard session.
  const spiked = dailyLoads([
    ...sessions,
    session({ startedAt: day('2026-07-25'), minutes: 100, sessionRPE: 9 }), // +900
  ]);
  const ratio = acuteChronicRatio(spiked, now);
  check('a spike pushes the ratio above 1', ratio > 1, true);
  // acute 1500, chronic (2400+900)/4 = 825
  check('spike ratio value', ratio, 1500 / 825, 1e-9);

  const shortHistory = dailyLoads([session({ startedAt: day('2026-07-27'), minutes: 40, sessionRPE: 7 })]);
  check('no ratio without 28 days of history', acuteChronicRatio(shortHistory, now), null);
});

group('Monotony and strain', () => {
  const now = day('2026-07-28'); // Tuesday
  // One 700 AU session in an otherwise empty week: maximally uneven.
  const spike = dailyLoads([session({ startedAt: day('2026-07-27'), minutes: 100, sessionRPE: 7 })]);
  const m1 = monotony(spike, now);
  // mean 100, population SD = sqrt((6*100^2 + 600^2)/7) = sqrt(60000/7*... ) — compute directly
  const values1 = [0, 0, 0, 0, 0, 700, 0];
  const mean1 = 100;
  const sd1 = Math.sqrt(values1.reduce((a, v) => a + (v - mean1) ** 2, 0) / 7);
  check('single-session week monotony', m1, mean1 / sd1, 1e-9);
  check('strain = weekly load x monotony', strain(spike, now), 700 * (mean1 / sd1), 1e-6);

  // Direction check, because the name misleads: monotony measures SAMENESS, so a week
  // spread over three days scores HIGHER than the same idea concentrated in one spike.
  // Getting this backwards in the UI would invert the advice, so it is pinned here.
  const spread = dailyLoads([
    session({ startedAt: day('2026-07-23'), minutes: 40, sessionRPE: 6 }),
    session({ startedAt: day('2026-07-25'), minutes: 40, sessionRPE: 6 }),
    session({ startedAt: day('2026-07-27'), minutes: 40, sessionRPE: 6 }),
  ]);
  check('spread week is MORE monotonous than a single spike', monotony(spread, now) > m1, true);

  check('no load, no monotony', monotony([], now), null);

  // Seven identical days have no spread at all, so the ratio is undefined.
  const flat = dailyLoads(
    [0, 1, 2, 3, 4, 5, 6].map((i) =>
      session({ startedAt: new Date(addDays(startOfDay(now), -6 + i).getTime() + 9 * 3600e3), minutes: 30, sessionRPE: 5 })
    )
  );
  check('identical every day is undefined, not infinite', monotony(flat, now), null);
});

// ---- the suite merge rule

group('Suite merge', () => {
  // Why SuiteDailyLoad carries sessionLoad rather than letting readers recompute it.
  const lift = { perceivedEffort: 8, activeMinutes: 60, sessionLoad: 8 * 60 };   // 480
  const run = { perceivedEffort: 5, activeMinutes: 40, sessionLoad: 5 * 40 };    // 200

  const mergedEffort = Math.max(lift.perceivedEffort, run.perceivedEffort);      // 8
  const mergedMinutes = lift.activeMinutes + run.activeMinutes;                  // 100
  const mergedLoad = lift.sessionLoad + run.sessionLoad;                         // 680

  check('summing the field is correct', mergedLoad, 680);
  check('recomputing from merged fields is not', mergedEffort * mergedMinutes, 800);
  check('and the two genuinely disagree', mergedEffort * mergedMinutes !== mergedLoad, true);
});

console.log(`\n${checks} assertions, ${failures} failing`);
process.exit(failures ? 1 : 0);
