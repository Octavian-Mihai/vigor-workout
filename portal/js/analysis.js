/* Deeper analysis pages: Progress & PRs, Balance & intensity, Calendar. */
(() => {
  const A = Analytics, P = Pages, U = P.u;
  const { chart, esc, fmt, dateStr, shortDate, duration, pace, W, wv, wu, kpi, card, canvas, header, table, empty, delta, barOpts, lineOpts } = U;
  const C = () => U.colors();
  const DAY = 86400000;
  const lsGet = (k, d) => { try { return localStorage.getItem(k) ?? d; } catch { return d; } };

  /* ---------- helpers ---------- */
  function exerciseSessions(sets) {
    const byEx = new Map();
    sets.forEach(s => {
      if (!byEx.has(s.exercise)) byEx.set(s.exercise, new Map());
      const m = byEx.get(s.exercise);
      if (!m.has(s.session)) m.set(s.session, []);
      m.get(s.session).push(s);
    });
    const out = new Map();
    byEx.forEach((sessions, name) => {
      out.set(name, [...sessions.values()].map(ss => ({
        date: ss[0].date, e1rm: Math.max(...ss.map(s => s.e1rm)), top: Math.max(...ss.map(s => s.weight)),
        reps: A.avg(ss.map(s => s.reps)), rir: A.avg(ss.map(s => s.rir)), vol: A.sum(ss.map(s => s.volume)),
      })).sort((a, z) => a.date - z.date));
    });
    return out;
  }

  /** PR events over the full history: a session whose best est. 1RM beats every earlier session. */
  function prEvents(model) {
    const events = [];
    exerciseSessions(model.sets).forEach((list, name) => {
      let best = 0;
      list.forEach((x, i) => {
        if (i > 0 && x.e1rm > best * 1.001) events.push({ name, date: x.date, e1rm: x.e1rm, prev: best, top: x.top });
        best = Math.max(best, x.e1rm);
      });
    });
    return events.sort((a, z) => z.date - a.date);
  }

  function stalls(model, now) {
    const res = [];
    exerciseSessions(model.sets).forEach((list, name) => {
      const recent = list.filter(x => now - x.date <= 42 * DAY);
      if (list.length < 4 || recent.length < 3) return;
      let best = 0, bestDate = null;
      list.forEach(x => { if (x.e1rm > best * 1.001) { best = x.e1rm; bestDate = x.date; } });
      const weeks = (now - bestDate) / (7 * DAY);
      if (weeks >= 4) res.push({ name, weeks, best, last: list[list.length - 1].e1rm, since: list.filter(x => x.date > bestDate).length, bestDate });
    });
    return res.sort((a, z) => z.weeks - a.weeks);
  }

  function summarise(model, from, to) {
    const v = A.slice(model, from, to);
    const vol = A.sum(v.sessions.map(s => s.volume));
    const km = A.sum(v.cardio.map(c => c.distanceKm)), secs = A.sum(v.cardio.map(c => c.durationSeconds));
    const st = A.stressSeries(model, from, to < new Date() ? to : new Date());
    return { v, sessions: v.sessions.length, volume: vol, sets: v.sets.length, rir: A.avg(v.sets.map(s => s.rir)),
      cardioKm: km, cardioN: v.cardio.length, pace: km ? secs / 60 / km : null, weight: A.avg(v.weights.map(w => w.kg)),
      stress: A.avg(st.map(s => s.total)), weeks: Math.max(1, (to - from) / (7 * DAY)) };
  }

  /* ---------- Progress & PRs ---------- */
  function progress(ctx) {
    const { model, view: m, from, to } = ctx;
    if (!model.sets.length) return { html: header('Progress & PRs', 'PRs, stalls and overload') + empty('No lifting data yet.') };
    const now = to < new Date() ? to : new Date();
    const prs = prEvents(model).filter(e => e.date >= from && e.date <= to);
    const stall = stalls(model, now);

    // Progressive overload over the selected period
    const over = [];
    exerciseSessions(m.sets).forEach((list, name) => {
      if (list.length < 3) return;
      const k = Math.min(2, Math.floor(list.length / 2));
      const head = list.slice(0, k), tail = list.slice(-k), a = arr => f => A.avg(arr.map(f));
      const e0 = a(head)(x => x.e1rm), e1 = a(tail)(x => x.e1rm);
      const pct = (e1 - e0) / e0 * 100;
      over.push({ name, n: list.length, pct, top: a(tail)(x => x.top) - a(head)(x => x.top), reps: a(tail)(x => x.reps) - a(head)(x => x.reps), rir: a(tail)(x => x.rir) - a(head)(x => x.rir) });
    });
    over.sort((a, z) => z.pct - a.pct);
    const verdict = p => p > 2 ? '<span class="verdict good">Progressing</span>' : p < -2 ? '<span class="verdict bad">Regressing</span>' : '<span class="verdict flat">Flat</span>';

    // Period comparison: selected period vs the previous period of equal length
    const len = to - from, pFrom = new Date(from - len - 1), pTo = new Date(from - 1);
    const canCompare = ctx.rangeKey !== 'all' && pFrom >= A.addDays(A.bounds(model).first, -7);
    const cur = summarise(model, from, to), prev = canCompare ? summarise(model, pFrom, pTo) : null;
    const row = (label, get, f, goodUp = true) => {
      const c = get(cur), p = prev ? get(prev) : null;
      const d = c != null && p ? (c - p) / p * 100 : null;
      const cls = d == null || Math.abs(d) < 0.5 ? 'flat' : (d > 0) === goodUp ? 'up' : 'down';
      return [label, f(c), prev ? f(p) : '—', d == null ? '—' : `<span class="${cls}">${d > 0 ? '+' : ''}${fmt(d, 1)}%</span>`];
    };
    const cmp = canCompare ? table(['Metric', `This period (${shortDate(from)}–${shortDate(to)})`, `Previous (${shortDate(pFrom)}–${shortDate(pTo)})`, 'Change'], [
      row('Lifting sessions', s => s.sessions, fmt), row(`Total volume (${wu(ctx)})`, s => s.volume * W(ctx), v => fmt(v)),
      row('Total sets', s => s.sets, fmt), row('Avg RIR', s => s.rir, v => fmt(v, 1), false),
      row('Cardio distance (km)', s => s.cardioKm, v => fmt(v, 1)), row('Cardio sessions', s => s.cardioN, fmt),
      row('Avg pace (min/km)', s => s.pace, v => v ? pace(v) : '—', false),
      row(`Avg bodyweight (${wu(ctx)})`, s => s.weight && s.weight * W(ctx), v => v ? fmt(v, 1) : '—', false),
      row('Avg training stress', s => s.stress, v => fmt(v), false)], [1, 2, 3])
      : '<p class="muted">Choose a period other than “All time” to compare it with the period just before it.</p>';

    const html = header('Progress & PRs', 'Personal records, stalled lifts, progressive overload and period comparison.') +
      `<div class="grid g4">${kpi('PRs in period', fmt(prs.length), 'new est. 1RM bests')}${kpi('Stalled lifts', fmt(stall.length), 'no PR for 4+ weeks', stall.length ? 'down' : 'up')}${kpi('Progressing', fmt(over.filter(o => o.pct > 2).length), `of ${over.length} lifts tracked`, 'up')}${kpi('Regressing', fmt(over.filter(o => o.pct < -2).length), '', over.some(o => o.pct < -2) ? 'down' : 'flat')}</div>
       <div class="grid g2">${card('PR timeline', prs.length ? table(['Date', 'Exercise', 'Est. 1RM', 'Previous best', 'Gain'], prs.map(e => [dateStr(e.date), esc(e.name), `${wv(ctx, e.e1rm)} ${wu(ctx)}`, `${wv(ctx, e.prev)} ${wu(ctx)}`, `<span class="up">+${fmt((e.e1rm - e.prev) / e.prev * 100, 1)}%</span>`]), [2, 3, 4]) : '<p class="muted">No PRs in this period.</p>')}
         ${card('Stalled lifts', stall.length ? table(['Exercise', 'Weeks since PR', 'Sessions since', 'Best 1RM', 'Latest 1RM'], stall.map(s => [esc(s.name), fmt(s.weeks, 1), s.since, `${wv(ctx, s.best)} ${wu(ctx)}`, `${wv(ctx, s.last)} ${wu(ctx)}`]), [1, 2, 3, 4]) + '<p class="foot">Trained 3+ times in the last 6 weeks without beating the previous best. Consider a deload, rep-range change or variation.</p>' : '<p class="muted">No stalled lifts. Every regularly trained lift set a PR within the last 4 weeks.</p>')}</div>
       ${card('Progressive overload check', over.length ? table(['Exercise', 'Sessions', 'Est. 1RM', 'Top set load', 'Avg reps', 'Avg RIR', 'Verdict'], over.map(o => [esc(o.name), o.n, `${o.pct > 0 ? '+' : ''}${fmt(o.pct, 1)}%`, `${o.top > 0 ? '+' : ''}${wv(ctx, o.top)} ${wu(ctx)}`, `${o.reps > 0 ? '+' : ''}${fmt(o.reps, 1)}`, `${o.rir > 0 ? '+' : ''}${fmt(o.rir, 1)}`, verdict(o.pct)]), [1, 2, 3, 4, 5]) + '<p class="foot">Compares the first and last two sessions of each exercise in the period. Rising load or reps at steady RIR means overload; falling RIR at the same load means effort is increasing instead.</p>' : '<p class="muted">Needs an exercise trained at least 3 times in the period.</p>')}
       <div style="height:16px"></div>
       <div class="grid g2">${card('Period comparison', cmp)}${card('Weekly volume: this period vs previous', canvas('pcCmp'))}</div>`;
    return { html, mount(root) {
      if (!prev) return;
      const a = A.weekly(cur.v.sessions, s => s.start), b = A.weekly(prev.v.sessions, s => s.start);
      const n = Math.max(a.length, b.length), vol = w => A.sum(w.items.map(s => s.volume)) * W(ctx);
      chart(root, 'pcCmp', { type: 'bar', data: { labels: Array.from({ length: n }, (_, i) => 'Week ' + (i + 1)), datasets: [
        { label: 'This period', data: Array.from({ length: n }, (_, i) => a[i] ? vol(a[i]) : null), backgroundColor: C().accent, borderRadius: 4 },
        { label: 'Previous', data: Array.from({ length: n }, (_, i) => b[i] ? vol(b[i]) : null), backgroundColor: C().dim, borderRadius: 4 }] },
        options: { responsive: true, plugins: { legend: { display: true } }, scales: { x: { grid: { display: false } }, y: { beginAtZero: true } } } });
    } };
  }

  /* ---------- Balance & intensity ---------- */
  const PUSH = ['Chest', 'Anterior Delts', 'Lateral Delts', 'Triceps'];
  const PULL = ['Lats', 'Rhomboids', 'Traps', 'Posterior Delts', 'Biceps'];
  const LEGS = ['Quadriceps', 'Hamstrings', 'Glutes', 'Calves', 'Adductors', 'Tibialis', 'Hip Flexors'];
  const CORE = ['Core & Abs', 'Erectors'];

  function balance(ctx) {
    const { view: m, to } = ctx;
    if (!m.sets.length) return { html: header('Balance & intensity', 'Muscle balance and effort') + empty('No lifting data in this period.') };
    const weeks = Math.max(1, (ctx.to - ctx.from) / (7 * DAY));
    const tot = {};
    m.sets.forEach(s => { s.primary.forEach(x => tot[x] = (tot[x] || 0) + 1); s.secondary.forEach(x => tot[x] = (tot[x] || 0) + .5); });
    const wk = n => (tot[n] || 0) / weeks;
    const grp = names => A.sum(names.map(wk));
    const push = grp(PUSH), pull = grp(PULL), legs = grp(LEGS), core = grp(CORE);
    const upper = push + pull;
    const ratio = (a, b) => b ? a / b : null;
    const status = (r, lo, hi) => r == null ? '<span class="muted">—</span>' : r < lo ? '<span class="verdict bad">Low</span>' : r > hi ? '<span class="verdict flat">High</span>' : '<span class="verdict good">Balanced</span>';
    const rows = [
      ['Push : Pull (sets/wk)', `${fmt(push, 1)} : ${fmt(pull, 1)}`, ratio(push, pull), 'Pull ≥ push protects shoulders', 0.6, 1.0],
      ['Quads : Hamstrings', `${fmt(wk('Quadriceps'), 1)} : ${fmt(wk('Hamstrings'), 1)}`, ratio(wk('Quadriceps'), wk('Hamstrings')), 'about 1–1.5 : 1', 0.8, 1.6],
      ['Upper : Lower', `${fmt(upper, 1)} : ${fmt(legs, 1)}`, ratio(upper, legs), 'about 1–1.5 : 1 for a general client', 0.8, 1.8],
      ['Anterior : Posterior delts', `${fmt(wk('Anterior Delts'), 1)} : ${fmt(wk('Posterior Delts'), 1)}`, ratio(wk('Anterior Delts'), wk('Posterior Delts')), 'posterior delts are often undertrained', 0.5, 1.5],
      ['Biceps : Triceps', `${fmt(wk('Biceps'), 1)} : ${fmt(wk('Triceps'), 1)}`, ratio(wk('Biceps'), wk('Triceps')), 'about 1 : 1', 0.6, 1.6],
    ].map(r => [`${r[0]}<div class="note sm">${r[3]}</div>`, r[1], r[2] == null ? '—' : fmt(r[2], 2), status(r[2], r[4], r[5])]);

    // Recency
    const last = {}, recent7 = {};
    const ref = to < new Date() ? to : new Date();
    ctx.model.sets.filter(s => s.date <= ref).forEach(s => s.primary.forEach(n => {
      if (!last[n] || s.date > last[n]) last[n] = s.date;
      if (ref - s.date <= 7 * DAY) recent7[n] = (recent7[n] || 0) + 1;
    }));
    const tiles = Object.entries(last).map(([n, d]) => ({ n, d, days: Math.floor((ref - d) / DAY) })).sort((a, z) => z.days - a.days)
      .map(t => { const c = t.days <= 2 ? 'fresh' : t.days <= 7 ? 'ready' : t.days <= 14 ? 'due' : 'neglected';
        return `<div class="tile ${c}"><b>${esc(t.n)}</b><span>${t.days === 0 ? 'today' : t.days + ' d ago'} · ${recent7[t.n] || 0} sets this week</span></div>`; }).join('');

    // Intensity distribution
    const sets = m.sets, N = sets.length;
    const reps = [0, 0, 0]; sets.forEach(s => reps[s.reps <= 5 ? 0 : s.reps <= 12 ? 1 : 2]++);
    const rirB = [0, 0, 0, 0, 0, 0]; sets.forEach(s => rirB[Math.min(Math.max(s.rir, 0), 5)]++);
    const best = {}; sets.forEach(s => { best[s.exercise] = Math.max(best[s.exercise] || 0, s.e1rm); });
    const zb = [0, 0, 0, 0, 0]; sets.forEach(s => { const p = s.weight / best[s.exercise]; zb[p < .6 ? 0 : p < .7 ? 1 : p < .8 ? 2 : p < .9 ? 3 : 4]++; });
    const fail = rirB[0] / N * 100;

    const html = header('Balance & intensity', 'Where the work goes, what is neglected, and how hard it is. Values are weekly hard sets averaged over the selected period.') +
      `<div class="grid g4">${kpi('Push : Pull', ratio(push, pull) ? fmt(ratio(push, pull), 2) : '—', `${fmt(push, 1)} vs ${fmt(pull, 1)} sets/wk`)}${kpi('Upper : Lower', ratio(upper, legs) ? fmt(ratio(upper, legs), 2) : '—')}${kpi('Sets to failure', fmt(fail) + '%', 'RIR 0', fail > 25 ? 'down' : 'flat')}${kpi('Avg RIR', fmt(A.avg(sets.map(s => s.rir)), 1))}</div>
       <div class="grid g2">${card('Muscle balance ratios', table(['Ratio', 'Sets / week', 'Value', 'Reading'], rows))}${card('Training split (share of weekly sets)', canvas('bSplit'))}</div>
       <div style="height:16px"></div>
       ${card('Body-part recency (time since last direct training)', `<div class="tiles">${tiles}</div><div class="legend"><span><i style="background:var(--bad)"></i>0–2 days (recovering)</span><span><i style="background:var(--good)"></i>3–7 days</span><span><i style="background:var(--warn)"></i>8–14 days</span><span><i style="background:var(--ink-faint)"></i>15+ days</span></div>`)}
       <div style="height:16px"></div>
       <div class="grid g2">${card('Rep ranges', canvas('iReps'))}${card('Reps in reserve (RIR)', canvas('iRir'))}${card('Load as % of best est. 1RM per exercise', canvas('iPct'))}</div>`;
    return { html, mount(root) {
      const pal = [C().accent, C().blue, C().green, C().violet];
      chart(root, 'bSplit', { type: 'doughnut', data: { labels: ['Push', 'Pull', 'Legs', 'Core & back'], datasets: [{ data: [push, pull, legs, core], backgroundColor: pal, borderWidth: 0 }] }, options: { responsive: true, plugins: { legend: { position: 'right' } } } });
      chart(root, 'iReps', { type: 'doughnut', data: { labels: ['1–5 strength', '6–12 hypertrophy', '13+ endurance'], datasets: [{ data: reps, backgroundColor: [C().accent, C().green, C().blue], borderWidth: 0 }] }, options: { responsive: true, plugins: { legend: { position: 'right' } } } });
      chart(root, 'iRir', { type: 'bar', data: { labels: ['0 (failure)', '1', '2', '3', '4', '5+'], datasets: [{ data: rirB.map(x => x / N * 100), backgroundColor: C().violet, borderRadius: 4 }] }, options: barOpts({ scales: { x: { grid: { display: false } }, y: { beginAtZero: true, title: { display: true, text: '% of sets' } } } }) });
      chart(root, 'iPct', { type: 'bar', data: { labels: ['<60%', '60–70%', '70–80%', '80–90%', '90%+'], datasets: [{ data: zb.map(x => x / N * 100), backgroundColor: C().pink, borderRadius: 4 }] }, options: barOpts({ scales: { x: { grid: { display: false } }, y: { beginAtZero: true, title: { display: true, text: '% of sets' } } } }) });
    } };
  }

  /* ---------- Calendar ---------- */
  function calendar(ctx) {
    const { model } = ctx, m = ctx.view;
    if (!m.sessions.length && !m.cardio.length) return { html: header('Calendar', 'Training consistency') + empty('No training in this period.') };
    const end = A.startOfDay(ctx.to < new Date() ? ctx.to : new Date());
    const firstAct = A.startOfDay(new Date(Math.min(...model.sessions.map(x => x.start), ...model.cardio.map(x => x.start), end)));
    const start = A.weekStart(new Date(Math.max(A.addDays(end, -7 * 52), firstAct)));
    const days = new Map();
    const d = x => { const k = A.dayKey(x, model.tz); if (!days.has(k)) days.set(k, { lift: 0, sets: 0, cardio: 0, mins: 0 }); return days.get(k); };
    model.sessions.forEach(s => { const x = d(s.start); x.lift++; x.sets += s.sets.length; });
    model.cardio.forEach(c => { const x = d(c.start); x.cardio++; x.mins += c.durationSeconds / 60; });
    const cells = [], monthLabels = [];
    const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    let idx = 0, lastMonth = -1, lastLabelWeek = -10;
    for (let day = start; day <= end; day = A.addDays(day, 1), idx++) {
      const w = Math.floor(idx / 7), dow = idx % 7;
      if (dow === 0) {
        // Label a column when the month changes (keep labels at least 3 columns apart).
        const mth = day.getMonth();
        if (mth !== lastMonth) { if (w - lastLabelWeek >= 3 || lastLabelWeek < 0) { monthLabels.push(`<span class="cal-m" style="grid-column:${w + 2} / span 3;grid-row:1">${MONTHS[mth]}</span>`); lastLabelWeek = w; } lastMonth = mth; }
      }
      const x = days.get(A.iso(day));
      let bg = '', tip = dateStr(day);
      if (x) {
        const strength = Math.min(1, x.sets / 25), cardio = Math.min(1, x.mins / 60);
        const a = (.3 + .7 * Math.max(strength, cardio)).toFixed(2);
        const col = x.lift && x.cardio ? 'var(--good)' : x.lift ? 'var(--accent)' : 'var(--blue)';
        bg = `background:color-mix(in srgb,${col} ${Math.round(a * 100)}%,transparent);`;
        tip += `: ${x.lift ? x.sets + ' sets' : ''}${x.lift && x.cardio ? ' + ' : ''}${x.cardio ? Math.round(x.mins) + ' min cardio' : ''}`;
      }
      cells.push(`<i style="${bg}grid-column:${w + 2};grid-row:${dow + 2}" title="${tip}"></i>`);
    }
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((n, i) => `<span class="cal-d" style="grid-column:1;grid-row:${i + 2}">${n}</span>`).join('');
    const calHtml = `<div class="calscroll"><div class="cal">${monthLabels.join('')}${dayLabels}${cells.join('')}</div></div>`;
    // Consistency stats within the selected period
    const active = [...new Set([...m.sessions.map(s => A.dayKey(s.start, model.tz)), ...m.cardio.map(c => A.dayKey(c.start, model.tz))])].sort();
    let longest = 0, streak = 0, gap = 0, prevD = null;
    active.forEach(k => { const t = new Date(k + 'T00:00:00'); if (prevD) { const g = Math.round((t - prevD) / DAY) - 1; gap = Math.max(gap, g); } prevD = t; });
    const wk = A.weekly([...m.sessions.map(s => s.start), ...m.cardio.map(c => c.start)], x => x);
    wk.forEach(w => { if (w.items.length) { streak++; longest = Math.max(longest, streak); } else streak = 0; });
    const dow = [0, 0, 0, 0, 0, 0, 0], hours = Array(24).fill(0);
    m.sessions.forEach(s => { dow[A.dowIn(s.start, model.tz)]++; hours[A.hourIn(s.start, model.tz)]++; });
    const months = new Map();
    [...m.sessions.map(s => ({ t: 'l', d: s.start, v: s.volume })), ...m.cardio.map(c => ({ t: 'c', d: c.start, v: c.distanceKm }))].forEach(x => {
      const k = A.dayKey(x.d, model.tz).slice(0, 7);
      const r = months.get(k) || { l: 0, vol: 0, c: 0, km: 0 }; if (x.t === 'l') { r.l++; r.vol += x.v; } else { r.c++; r.km += x.v; } months.set(k, r);
    });
    const mrows = [...months.entries()].sort().reverse().map(([k, r]) => [k, r.l, `${fmt(r.vol * W(ctx))} ${wu(ctx)}`, r.c, `${fmt(r.km, 1)} km`]);
    const html = header('Calendar', 'Every training day over the last year, plus consistency patterns.') +
      `<div class="grid g4">${kpi('Training days', fmt(active.length), 'in selected period')}${kpi('Weeks with activity', `${wk.filter(w => w.items.length).length} / ${wk.length}`)}${kpi('Longest weekly streak', fmt(longest) + ' wk')}${kpi('Longest gap', fmt(gap) + ' d', 'between sessions', gap > 10 ? 'down' : 'flat')}</div>
       ${card('Training calendar (up to 52 weeks)', calHtml + `<div class="legend"><span><i style="background:var(--accent)"></i>Lifting</span><span><i style="background:var(--blue)"></i>Cardio</span><span><i style="background:var(--good)"></i>Both</span><span>Darker = bigger session</span></div>`)}
       <div style="height:16px"></div>
       <div class="grid g2">${card('Sessions by weekday', canvas('cDow'))}${card('Sessions by start time', canvas('cHour'))}</div>
       ${card('Monthly summary', table(['Month', 'Lifting sessions', 'Volume', 'Cardio sessions', 'Distance'], mrows, [1, 2, 3, 4]))}`;
    return { html, mount(root) {
      chart(root, 'cDow', { type: 'bar', data: { labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], datasets: [{ data: dow, backgroundColor: C().accent, borderRadius: 4 }] }, options: barOpts() });
      chart(root, 'cHour', { type: 'bar', data: { labels: hours.map((_, i) => i + ':00'), datasets: [{ data: hours, backgroundColor: C().violet, borderRadius: 4 }] }, options: barOpts() });
    } };
  }

  Object.assign(P.registry, { progress, balance, calendar });
})();
