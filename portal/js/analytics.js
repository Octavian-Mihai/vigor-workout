/* Turns a VIGOR backup (.json) into analysis-ready data. Mirrors the app's formulas where possible. */
const Analytics = (() => {
  const DAY = 86400000;
  const pad = n => String(n).padStart(2, '0');
  const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const startOfDay = d => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const weekStart = d => { const s = startOfDay(d); s.setDate(s.getDate() - ((s.getDay() + 6) % 7)); return s; };
  const addDays = (d, n) => { const r = new Date(d); r.setDate(r.getDate() + n); return r; };
  const sum = a => a.reduce((x, y) => x + y, 0);
  const avg = a => a.length ? sum(a) / a.length : null;

  const e1rm = (w, reps, rir) => w * (1 + (Math.max(reps, 0) + Math.max(rir, 0)) / 30);
  const setVolume = s => s.weight * s.reps;

  function cardioKind(sport) {
    const s = (sport || '').toLowerCase();
    if (s.includes('run')) return 'run';
    if (s.includes('cycl')) return 'cycle';
    if (s.includes('hike')) return 'hike';
    if (s.includes('walk')) return 'walk';
    return 'other';
  }
  const ACTIVITY_WEIGHT = { run: 1, hike: 0.85, cycle: 0.75, walk: 0.5, other: 1 };

  function runStress(c, resting = 60, maxHR = 190) {
    const minutes = Math.max(c.durationSeconds / 60, 0);
    let score;
    if (c.averageHeartRate > 0 && maxHR > resting) {
      const hrr = Math.min(Math.max((c.averageHeartRate - resting) / (maxHR - resting), 0), 1.05);
      score = Math.min(100, (minutes * hrr * 0.64 * Math.exp(1.92 * hrr)) / 1.5);
    } else if (c.distanceKm > 0 && minutes > 0) {
      const rel = Math.min(8 / Math.max(minutes / c.distanceKm, 3), 2);
      score = Math.min(100, (minutes / 60) * rel * 70);
    } else {
      score = Math.min(100, (minutes / 60) * 40);
    }
    if (c.elevationGainMeters > 0) score *= 1 + Math.min(c.elevationGainMeters / 300, 0.35);
    return Math.min(100, score * ACTIVITY_WEIGHT[c.kind]);
  }

  function stressBand(score) {
    if (score < 30.5) return { key: 'recovery', label: 'Recovery / easy', range: '0–30' };
    if (score < 55.5) return { key: 'productive', label: 'Productive', range: '31–55' };
    if (score < 75.5) return { key: 'high', label: 'High', range: '56–75' };
    return { key: 'veryHigh', label: 'Very high', range: '76–100' };
  }

  function parse(b) {
    const sessions = (b.sessions || []).map(s => {
      const start = new Date(s.startDate);
      const sets = (s.sets || []).map(x => ({
        session: s.uuid, exercise: x.exerciseName, primary: x.primaryMuscles || [], secondary: x.secondaryMuscles || [],
        weight: x.weight, reps: x.reps, rir: x.rir, targetReps: x.targetReps, date: new Date(x.timestamp),
        volume: x.weight * x.reps, e1rm: e1rm(x.weight, x.reps, x.rir),
      }));
      return {
        id: s.uuid, start, end: s.endDate ? new Date(s.endDate) : null, name: s.programDayName || 'Workout',
        durationSeconds: s.durationSeconds || 0, sets, volume: sum(sets.map(x => x.volume)),
      };
    }).sort((a, z) => a.start - z.start);

    const cardio = (b.cardio || []).map(c => {
      const o = { ...c, start: new Date(c.start), end: new Date(c.end), kind: cardioKind(c.sport) };
      o.paceMinPerKm = c.distanceKm > 0 && c.durationSeconds > 0 ? c.durationSeconds / 60 / c.distanceKm : null;
      o.stress = runStress(o);
      return o;
    }).sort((a, z) => a.start - z.start);

    // Body weight: explicit weigh-ins, plus weights recorded inside measurement entries (one per day).
    const byDay = new Map();
    (b.measurements || []).forEach(m => { if (m.kilograms) byDay.set(iso(new Date(m.date)), { date: new Date(m.date), kg: m.kilograms }); });
    (b.bodyWeights || []).forEach(w => byDay.set(iso(new Date(w.date)), { date: new Date(w.date), kg: w.kilograms }));
    const weights = [...byDay.values()].sort((a, z) => a.date - z.date);

    const measurements = (b.measurements || []).map(m => ({ ...m, date: new Date(m.date) })).sort((a, z) => a.date - z.date);

    return {
      exportedAt: new Date(b.exportedAt || Date.now()),
      programs: b.programs || [], sessions, sets: sessions.flatMap(s => s.sets), cardio, weights, measurements,
    };
  }

  function slice(m, from, to) {
    const inR = d => (!from || d >= from) && (!to || d <= to);
    const sessions = m.sessions.filter(s => inR(s.start));
    return {
      ...m, sessions, sets: sessions.flatMap(s => s.sets), cardio: m.cardio.filter(c => inR(c.start)),
      weights: m.weights.filter(w => inR(w.date)), measurements: m.measurements.filter(x => inR(x.date)),
    };
  }

  function bounds(m) {
    const dates = [...m.sessions.map(s => s.start), ...m.cardio.map(c => c.start), ...m.weights.map(w => w.date)];
    if (!dates.length) return null;
    return { first: new Date(Math.min(...dates)), last: new Date(Math.max(...dates)) };
  }

  /** Buckets items into Monday-start weeks; returns sorted [{key, date, items}] with empty weeks filled. */
  function weekly(items, dateOf, fill = true) {
    const map = new Map();
    items.forEach(it => {
      const w = weekStart(dateOf(it)); const k = iso(w);
      if (!map.has(k)) map.set(k, { key: k, date: w, items: [] });
      map.get(k).items.push(it);
    });
    const out = [...map.values()].sort((a, z) => a.date - z.date);
    if (!fill || out.length < 2) return out;
    const filled = []; const byKey = new Map(out.map(x => [x.key, x]));
    for (let d = out[0].date; d <= out[out.length - 1].date; d = addDays(d, 7)) {
      const k = iso(d); filled.push(byKey.get(k) || { key: k, date: d, items: [] });
    }
    return filled;
  }

  function muscleVolume(sets) {
    const r = {};
    sets.forEach(s => {
      s.primary.forEach(x => r[x] = (r[x] || 0) + s.volume);
      s.secondary.forEach(x => r[x] = (r[x] || 0) + s.volume * 0.5);
    });
    return r;
  }

  /** Hard sets per muscle per week (primary = 1, secondary = 0.5). */
  function muscleSetsByWeek(sets) {
    const res = {};
    weekly(sets, s => s.date).forEach(w => w.items.forEach(s => {
      s.primary.forEach(x => { (res[x] ||= {})[w.key] = (res[x][w.key] || 0) + 1; });
      s.secondary.forEach(x => { (res[x] ||= {})[w.key] = (res[x][w.key] || 0) + 0.5; });
    }));
    return res;
  }

  /** Rolling 7-day training stress per day (same formula as the app's total stress). */
  function stressSeries(m, from, to) {
    const days = new Map();
    const day = d => { const k = iso(d); if (!days.has(k)) days.set(k, { vol: 0, intSum: 0, n: 0, runs: [] }); return days.get(k); };
    m.sets.forEach(s => { const x = day(s.date); x.vol += s.volume; x.intSum += Math.max(0, 5 - Math.min(s.rir, 5)) / 5; x.n++; });
    m.cardio.forEach(c => day(c.start).runs.push(c.stress));
    const out = [];
    for (let d = startOfDay(from); d <= to; d = addDays(d, 1)) {
      let vol = 0, intSum = 0, n = 0, runs = [];
      for (let i = 0; i < 7; i++) {
        const x = days.get(iso(addDays(d, -i)));
        if (x) { vol += x.vol; intSum += x.intSum; n += x.n; runs = runs.concat(x.runs); }
      }
      const volumeScore = Math.min(50, vol / 500);
      const intensityScore = n ? (intSum / n) * 30 : 0;
      const runScore = runs.length ? Math.min(20, Math.max(0, avg(runs)) * 0.2) : 0;
      const lift = volumeScore + intensityScore;
      out.push({ date: new Date(d), key: iso(d), lift, run: runScore, total: Math.min(100, lift + runScore) });
    }
    return out;
  }

  function movingAverage(values, window) {
    return values.map((_, i) => avg(values.slice(Math.max(0, i - window + 1), i + 1)));
  }

  return { iso, startOfDay, weekStart, addDays, sum, avg, e1rm, parse, slice, bounds, weekly, muscleVolume, muscleSetsByWeek, stressSeries, stressBand, movingAverage };
})();
