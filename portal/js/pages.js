/* Page renderers. Each returns { html, mount(root) }; mount draws charts. */
const Pages = (() => {
  const A = Analytics;
  let C = { accent: '#ff5a2b', pink: '#ff3e7f', violet: '#7c4dff', green: '#3ecf8e', blue: '#3aa0ff', warn: '#ffb020', bad: '#ff4d5e', dim: '#a7a3ac' };
  Chart.defaults.color = '#a7a3ac';
  Chart.defaults.borderColor = 'rgba(255,255,255,.07)';
  Chart.defaults.font.family = '-apple-system,BlinkMacSystemFont,Inter,"Segoe UI",sans-serif';
  Chart.defaults.maintainAspectRatio = false;
  Chart.defaults.plugins.legend.labels.boxWidth = 10;

  let charts = [];
  const hex = h => { const n = parseInt(h.replace('#', ''), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
  const dist = (a, b) => { const x = hex(a), y = hex(b); return Math.hypot(x[0] - y[0], x[1] - y[1], x[2] - y[2]); };
  /** Recolours charts from the app theme; secondary series avoid colours too close to the accent. */
  function setTheme(t) {
    const base = { pink: '#ff3e7f', violet: '#7c4dff', green: '#3ecf8e', blue: '#3aa0ff', warn: '#ffb020', bad: '#ff4d5e' };
    const spare = ['#ffd166', '#06d6a0', '#c77dff', '#4cc9f0', '#f72585'];
    C = { ...C, ...base, accent: t.accent, dim: t.dim };
    Object.keys(base).forEach(k => { if (dist(C[k], t.accent) < 100) { C[k] = spare.find(c => dist(c, t.accent) > 140 && !Object.values(C).includes(c)) || C[k]; } });
    Chart.defaults.color = t.dim;
    Chart.defaults.borderColor = t.grid;
  }
  const destroyCharts = () => { charts.forEach(c => c.destroy()); charts = []; };
  const chart = (root, id, config) => {
    const el = root.querySelector('#' + id);
    if (el) charts.push(new Chart(el, config));
  };

  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const fmt = (n, d = 0) => n == null || isNaN(n) ? '—' : Number(n).toLocaleString(undefined, { maximumFractionDigits: d, minimumFractionDigits: d });
  const dateStr = d => d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
  const shortDate = d => d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  const duration = s => { const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60); return h ? `${h}h ${m}m` : `${m}m`; };
  const pace = p => p == null ? '—' : `${Math.floor(p)}:${String(Math.round((p % 1) * 60)).padStart(2, '0')}`;

  const W = ctx => ctx.unit === 'lb' ? 2.20462 : 1;
  const wv = (ctx, kg, d = 1) => fmt(kg * W(ctx), d);
  const wu = ctx => ctx.unit;

  const kpi = (label, value, note = '', cls = '') =>
    `<div class="card kpi"><div class="label">${label}</div><div class="value">${value}</div><div class="note ${cls}">${note}</div></div>`;
  const card = (title, body, extra = '') => `<div class="card ${extra}">${title ? `<h2>${title}</h2>` : ''}${body}</div>`;
  const canvas = (id, tall) => `<div class="chart ${tall ? 'tall' : ''}"><canvas id="${id}"></canvas></div>`;
  const header = (t, s) => `<h1>${t}</h1><p class="sub">${s}</p>`;
  const table = (heads, rows, nums = []) =>
    `<div class="tablewrap"><table><thead><tr>${heads.map((h, i) => `<th class="${nums.includes(i) ? 'num' : ''}">${h}</th>`).join('')}</tr></thead><tbody>${
      rows.map(r => `<tr>${r.map((c, i) => `<td class="${nums.includes(i) ? 'num' : ''}">${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
  const empty = msg => `<div class="empty">${msg}</div>`;
  const delta = (v, unit, goodWhenDown = false) => {
    if (v == null) return '';
    const cls = Math.abs(v) < 0.05 ? 'flat' : (v > 0) !== goodWhenDown ? 'up' : 'down';
    return `<span class="${cls}">${v > 0 ? '+' : ''}${fmt(v, 1)} ${unit}</span>`;
  };

  const barOpts = (extra = {}) => ({ responsive: true, plugins: { legend: { display: false } }, scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 12 } }, y: { beginAtZero: true } }, ...extra });
  const lineOpts = (extra = {}) => ({ responsive: true, interaction: { mode: 'index', intersect: false }, plugins: { legend: { display: false } }, scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 12 } } }, ...extra });

  /* ---------------- Overview ---------------- */
  function overview(ctx) {
    const { view: m } = ctx;
    if (!m.sessions.length && !m.cardio.length && !m.weights.length) return { html: header('Overview', ctx.client.name) + empty('No data in this period.') };
    const vol = A.sum(m.sessions.map(s => s.volume));
    const km = A.sum(m.cardio.map(c => c.distanceKm));
    const w = m.weights, wd = w.length > 1 ? w[w.length - 1].kg - w[0].kg : null;
    const st = ctx.stress.length ? ctx.stress[ctx.stress.length - 1] : null;
    const band = st ? A.stressBand(st.total) : null;
    const weeks = Math.max(1, (ctx.to - ctx.from) / (7 * 86400000));
    const recent = [...m.sessions.map(s => ({ d: s.start, t: 'Lift', n: s.name, x: `${fmt(s.volume * W(ctx))} ${wu(ctx)} · ${s.sets.length} sets · ${duration(s.durationSeconds)}` })),
      ...m.cardio.map(c => ({ d: c.start, t: 'Cardio', n: c.sport, x: `${fmt(c.distanceKm, 1)} km · ${duration(c.durationSeconds)}${c.paceMinPerKm ? ' · ' + pace(c.paceMinPerKm) + '/km' : ''}` }))]
      .sort((a, z) => z.d - a.d).slice(0, 10);
    const html = header('Overview', `${esc(ctx.client.name)} · ${dateStr(ctx.from)} – ${dateStr(ctx.to)}`) +
      `<div class="grid g4">
        ${kpi('Lifting sessions', fmt(m.sessions.length), `${fmt(m.sessions.length / weeks, 1)} per week`)}
        ${kpi('Total volume', `${fmt(vol * W(ctx))} <small>${wu(ctx)}</small>`, `${fmt(m.sets.length)} sets · ${fmt(A.sum(m.sets.map(s => s.reps)))} reps`)}
        ${kpi('Cardio distance', `${fmt(km, 1)} <small>km</small>`, `${m.cardio.length} sessions · ${duration(A.sum(m.cardio.map(c => c.durationSeconds)))}`)}
        ${kpi('Bodyweight', w.length ? `${wv(ctx, w[w.length - 1].kg)} <small>${wu(ctx)}</small>` : '—', wd == null ? '' : delta(wd * W(ctx), wu(ctx)) + ' over period')}
        ${kpi('Training stress', st ? fmt(st.total) : '—', band ? `<span class="pill ${band.key}">${band.label}</span> leftover fatigue` : '')}
      </div>
      <div class="grid g2">
        ${card('Weekly volume (' + wu(ctx) + ')', canvas('cVol'))}
        ${card('Weekly cardio distance (km)', canvas('cCardio'))}
        ${card('Bodyweight (' + wu(ctx) + ')', canvas('cWeight'))}
        ${card('Training stress (leftover fatigue)', canvas('cStress'))}
      </div>
      ${card('Recent activity', table(['Date', 'Type', 'Session', 'Detail'], recent.map(r => [dateStr(r.d), r.t, esc(r.n), r.x])))}`;
    return { html, mount(root) {
      const wk = A.weekly(m.sessions, s => s.start);
      chart(root, 'cVol', { type: 'bar', data: { labels: wk.map(x => shortDate(x.date)), datasets: [{ data: wk.map(x => A.sum(x.items.map(s => s.volume)) * W(ctx)), backgroundColor: C.accent, borderRadius: 4 }] }, options: barOpts() });
      const ck = A.weekly(m.cardio, c => c.start);
      chart(root, 'cCardio', { type: 'bar', data: { labels: ck.map(x => shortDate(x.date)), datasets: [{ data: ck.map(x => A.sum(x.items.map(c => c.distanceKm))), backgroundColor: C.blue, borderRadius: 4 }] }, options: barOpts() });
      chart(root, 'cWeight', weightConfig(ctx, w));
      chart(root, 'cStress', stressLine(ctx.stress));
    } };
  }

  function weightConfig(ctx, w) {
    const vals = w.map(x => x.kg * W(ctx));
    return { type: 'line', data: { labels: w.map(x => shortDate(x.date)), datasets: [
      { label: 'Weigh-in', data: vals, borderColor: C.pink, backgroundColor: C.pink, pointRadius: 3, tension: .25 },
      { label: '7-entry average', data: A.movingAverage(vals, 7), borderColor: Chart.defaults.color, borderDash: [5, 4], pointRadius: 0, tension: .35, borderWidth: 1.5 }] },
      options: lineOpts({ plugins: { legend: { display: true } }, scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 12 } }, y: { grace: '5%' } } }) };
  }

  function stressLine(series) {
    const band = (v, c) => ({ data: series.map(() => v), borderColor: c, borderDash: [4, 4], pointRadius: 0, borderWidth: 1 });
    return { type: 'line', data: { labels: series.map(s => shortDate(s.date)), datasets: [
      { data: series.map(s => s.total), borderColor: C.violet, backgroundColor: 'rgba(124,77,255,.15)', fill: true, pointRadius: 0, tension: .3, borderWidth: 2 },
      band(30, C.green), band(55, C.blue), band(75, C.warn)] },
      options: lineOpts({ scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 12 } }, y: { min: 0, max: 100 } } }) };
  }

  /* ---------------- Volume ---------------- */
  function volume(ctx) {
    const { view: m } = ctx;
    if (!m.sets.length) return { html: header('Volume', 'Training volume breakdown') + empty('No lifting data in this period.') };
    const mv = Object.entries(A.muscleVolume(m.sets)).sort((a, z) => z[1] - a[1]);
    const msw = A.muscleSetsByWeek(m.sets);
    const weeks = A.weekly(m.sets, s => s.date).slice(-10);
    const muscles = Object.keys(msw).sort((a, z) => A.sum(Object.values(msw[z])) - A.sum(Object.values(msw[a])));
    const max = Math.max(1, ...muscles.flatMap(mu => weeks.map(w => msw[mu][w.key] || 0)));
    const heat = `<div class="tablewrap"><table class="heat"><thead><tr><th>Muscle</th><th class="num">Avg / wk</th>${weeks.map(w => `<th class="num">${shortDate(w.date)}</th>`).join('')}</tr></thead><tbody>${
      muscles.map(mu => { const vals = weeks.map(w => msw[mu][w.key] || 0);
        return `<tr><td>${esc(mu)}</td><td class="num"><strong>${fmt(A.avg(vals), 1)}</strong></td>${vals.map(v => `<td class="h" style="background:rgba(var(--accent-rgb),${(v / max * .75).toFixed(2)})">${v ? fmt(v, v % 1 ? 1 : 0) : ''}</td>`).join('')}</tr>`; }).join('')}</tbody></table></div>
      <p class="foot">Hard sets per muscle per week, last 10 weeks. Primary muscles count 1 set, secondary 0.5.</p>`;
    const html = header('Volume', `Volume = weight × reps, in ${wu(ctx)}. Secondary muscles count at 50%.`) +
      `<div class="grid g2">${card('Weekly volume', canvas('vWeek'))}${card('Weekly sets & average volume per session', canvas('vSets'))}</div>
       <div class="grid g2">${card('Volume by muscle', canvas('vMuscle', true))}${card('Sets per muscle per week', heat)}</div>`;
    return { html, mount(root) {
      const wk = A.weekly(m.sessions, s => s.start);
      const labels = wk.map(x => shortDate(x.date));
      chart(root, 'vWeek', { type: 'bar', data: { labels, datasets: [{ data: wk.map(x => A.sum(x.items.map(s => s.volume)) * W(ctx)), backgroundColor: C.accent, borderRadius: 4 }] }, options: barOpts() });
      chart(root, 'vSets', { data: { labels, datasets: [
        { type: 'bar', label: 'Sets', data: wk.map(x => A.sum(x.items.map(s => s.sets.length))), backgroundColor: C.violet, borderRadius: 4, yAxisID: 'y' },
        { type: 'line', label: `Avg volume / session (${wu(ctx)})`, data: wk.map(x => x.items.length ? A.avg(x.items.map(s => s.volume)) * W(ctx) : null), borderColor: C.green, spanGaps: true, tension: .3, yAxisID: 'y1' }] },
        options: { responsive: true, plugins: { legend: { display: true } }, scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 12 } }, y: { beginAtZero: true }, y1: { position: 'right', beginAtZero: true, grid: { display: false } } } } });
      const top = mv.slice(0, 16);
      chart(root, 'vMuscle', { type: 'bar', data: { labels: top.map(x => x[0]), datasets: [{ data: top.map(x => x[1] * W(ctx)), backgroundColor: C.pink, borderRadius: 4 }] }, options: { ...barOpts(), indexAxis: 'y', scales: { x: { beginAtZero: true }, y: { grid: { display: false } } } } });
    } };
  }

  /* ---------------- Weightlifting ---------------- */
  let liftExercise = null;
  function lifting(ctx) {
    const { view: m } = ctx;
    if (!m.sets.length) return { html: header('Weightlifting', 'Per-exercise progression') + empty('No lifting data in this period.') };
    const byEx = new Map();
    m.sets.forEach(s => { if (!byEx.has(s.exercise)) byEx.set(s.exercise, []); byEx.get(s.exercise).push(s); });
    const exercises = [...byEx.entries()].sort((a, z) => z[1].length - a[1].length);
    if (!byEx.has(liftExercise)) liftExercise = exercises[0][0];

    const prs = exercises.map(([name, sets]) => {
      const best = sets.reduce((b, s) => s.e1rm > b.e1rm ? s : b, sets[0]);
      const heavy = sets.reduce((b, s) => s.weight > b.weight ? s : b, sets[0]);
      const last = sets.reduce((b, s) => s.date > b.date ? s : b, sets[0]);
      return [`<a href="#/lifting" data-ex="${esc(name)}" class="pick">${esc(name)}</a>`, fmt(sets.length), `${wv(ctx, best.e1rm)} ${wu(ctx)}`, `${wv(ctx, heavy.weight)} × ${heavy.reps}`, dateStr(best.date), dateStr(last.date)];
    });
    const logs = [...m.sessions].reverse().map(s => `<details><summary><span>${dateStr(s.start)}</span><strong>${esc(s.name)}</strong><span>${s.sets.length} sets · ${fmt(s.volume * W(ctx))} ${wu(ctx)} · ${duration(s.durationSeconds)}</span></summary><div class="inner">${
      table(['Exercise', 'Weight', 'Reps', 'RIR', 'Est. 1RM'], s.sets.map(x => [esc(x.exercise), `${wv(ctx, x.weight)} ${wu(ctx)}`, x.reps, x.rir, `${wv(ctx, x.e1rm)} ${wu(ctx)}`]), [1, 2, 3, 4])}</div></details>`).join('');

    const sets = m.sets, rirAvg = A.avg(sets.map(s => s.rir));
    const html = header('Weightlifting', 'Strength progression, personal bests and the full session log.') +
      `<div class="grid g4">${kpi('Sessions', fmt(m.sessions.length))}${kpi('Total sets', fmt(sets.length))}${kpi('Avg reps / set', fmt(A.avg(sets.map(s => s.reps)), 1))}${kpi('Avg RIR', fmt(rirAvg, 1), 'reps in reserve')}${kpi('Avg session', duration(A.avg(m.sessions.map(s => s.durationSeconds)) || 0))}</div>
       <div class="card" style="margin-bottom:16px"><div class="row" style="margin-bottom:12px"><h2 style="margin:0">Exercise progression</h2>
         <select id="exSelect">${exercises.map(([n, s]) => `<option value="${esc(n)}" ${n === liftExercise ? 'selected' : ''}>${esc(n)} (${s.length})</option>`).join('')}</select></div>
         <div class="grid g2" style="margin:0"><div>${canvas('lRM')}</div><div>${canvas('lVol')}</div></div></div>
       <div class="grid g2">${card('Personal bests (click an exercise)', table(['Exercise', 'Sets', 'Best est. 1RM', 'Heaviest set', 'Best on', 'Last done'], prs, [1, 2, 3]))}${card('Session log', `<div class="tablewrap">${logs}</div>`)}</div>`;

    return { html, mount(root) {
      const draw = () => {
        charts.filter(c => ['lRM', 'lVol'].includes(c.canvas.id)).forEach(c => { c.destroy(); charts = charts.filter(x => x !== c); });
        const per = [...new Set(byEx.get(liftExercise).map(s => s.session))].map(id => {
          const ss = byEx.get(liftExercise).filter(s => s.session === id);
          return { date: ss[0].date, e1rm: Math.max(...ss.map(s => s.e1rm)), top: Math.max(...ss.map(s => s.weight)), vol: A.sum(ss.map(s => s.volume)) };
        }).sort((a, z) => a.date - z.date);
        const labels = per.map(p => shortDate(p.date));
        chart(root, 'lRM', { type: 'line', data: { labels, datasets: [
          { label: 'Est. 1RM', data: per.map(p => p.e1rm * W(ctx)), borderColor: C.accent, backgroundColor: C.accent, tension: .25, pointRadius: 3 },
          { label: 'Top set weight', data: per.map(p => p.top * W(ctx)), borderColor: C.blue, backgroundColor: C.blue, tension: .25, pointRadius: 3 }] },
          options: lineOpts({ plugins: { legend: { display: true } }, scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 10 } }, y: { grace: '5%' } } }) });
        chart(root, 'lVol', { type: 'bar', data: { labels, datasets: [{ label: 'Volume', data: per.map(p => p.vol * W(ctx)), backgroundColor: C.violet, borderRadius: 4 }] }, options: barOpts() });
      };
      draw();
      root.querySelector('#exSelect').onchange = e => { liftExercise = e.target.value; draw(); };
      root.querySelectorAll('.pick').forEach(a => a.onclick = e => { e.preventDefault(); liftExercise = a.dataset.ex; root.querySelector('#exSelect').value = liftExercise; draw(); window.scrollTo({ top: 0, behavior: 'smooth' }); });
    } };
  }

  /* ---------------- Cardio ---------------- */
  let defaultMaxHr = 190;
  const setDefaultMaxHr = v => { defaultMaxHr = Math.round(v) || 190; };
  const maxHr = () => { try { return Number(localStorage.getItem('maxHr')) || defaultMaxHr; } catch { return defaultMaxHr; } };
  function zoneSummary(list) {
    const mx = maxHr(), minutes = [0, 0, 0, 0, 0];
    list.filter(c => c.averageHeartRate > 0).forEach(c => {
      const p = c.averageHeartRate / mx;
      minutes[p < .6 ? 0 : p < .7 ? 1 : p < .8 ? 2 : p < .9 ? 3 : 4] += c.durationSeconds / 60;
    });
    const total = A.sum(minutes);
    return { minutes, easy: total ? (minutes[0] + minutes[1]) / total * 100 : null, hard: total ? (minutes[3] + minutes[4]) / total * 100 : null };
  }
  let cardioKind = 'all';
  function cardio(ctx) {
    const all = ctx.view.cardio;
    if (!all.length) return { html: header('Cardio', 'Runs, rides and walks from Apple Health') + empty('No cardio data in this period. Export with “Cardio” ticked and Health access granted.') };
    const kinds = [...new Set(all.map(c => c.kind))];
    if (cardioKind !== 'all' && !kinds.includes(cardioKind)) cardioKind = 'all';
    const list = cardioKind === 'all' ? all : all.filter(c => c.kind === cardioKind);
    const km = A.sum(list.map(c => c.distanceKm)), secs = A.sum(list.map(c => c.durationSeconds));
    const hrs = list.filter(c => c.averageHeartRate > 0).map(c => c.averageHeartRate);
    const zones = zoneSummary(list);
    const html = header('Cardio', 'Distance, pace, heart rate and load for every cardio session.') +
      `<div class="row" style="margin-bottom:16px"><div class="seg" id="kindSeg">${['all', ...kinds].map(k => `<button data-k="${k}" class="${k === cardioKind ? 'on' : ''}">${k === 'all' ? 'All' : k[0].toUpperCase() + k.slice(1)}</button>`).join('')}</div></div>
       <div class="grid g4">${kpi('Sessions', fmt(list.length))}${kpi('Distance', `${fmt(km, 1)} <small>km</small>`)}${kpi('Time', duration(secs))}${kpi('Avg pace', km ? pace(secs / 60 / km) + ' <small>/km</small>' : '—')}${kpi('Avg heart rate', hrs.length ? `${fmt(A.avg(hrs))} <small>bpm</small>` : '—')}${kpi('Elevation', `${fmt(A.sum(list.map(c => c.elevationGainMeters || 0)))} <small>m</small>`)}</div>
       <div class="grid g2">${card('Weekly distance (km)', canvas('kWeek'))}${card('Pace per session (min/km, lower is faster)', canvas('kPace'))}${card('Average heart rate (bpm)', canvas('kHr'))}${card('Session stress', canvas('kStress'))}</div>
       ${card(`<div class="row"><span>Heart-rate zones</span><span class="inline muted">Max HR <input type="number" id="maxHr" min="120" max="230" value="${maxHr()}"></span></div>`, `<div class="grid g4" style="margin:0 0 12px">${kpi('Easy time (Z1–Z2)', zones.easy == null ? '—' : fmt(zones.easy) + '%', zones.easy == null ? 'needs heart-rate data' : zones.easy >= 75 ? 'well polarised' : 'consider more easy volume', zones.easy >= 75 ? 'up' : 'flat')}${kpi('Hard time (Z4–Z5)', zones.hard == null ? '—' : fmt(zones.hard) + '%')}</div><div class="grid g2" style="margin:0">${canvas('kZone')}${canvas('kEasy')}</div><p class="foot">Each session is placed in a zone from its average heart rate (the export has no per-second data), so this is an approximation.</p>`)}
       ${card('Sessions', table(['Date', 'Type', 'Distance', 'Time', 'Pace', 'Avg HR', 'Elev.', 'Stress'], [...list].reverse().map(c => [dateStr(c.start), esc(c.sport), `${fmt(c.distanceKm, 2)} km`, duration(c.durationSeconds), c.paceMinPerKm ? pace(c.paceMinPerKm) + '/km' : '—', c.averageHeartRate ? fmt(c.averageHeartRate) : '—', c.elevationGainMeters ? fmt(c.elevationGainMeters) + ' m' : '—', fmt(c.stress)]), [2, 3, 4, 5, 6, 7]))}`;
    return { html, mount(root) {
      root.querySelectorAll('#kindSeg button').forEach(b => b.onclick = () => { cardioKind = b.dataset.k; ctx.rerender(); });
      const wk = A.weekly(list, c => c.start);
      chart(root, 'kWeek', { type: 'bar', data: { labels: wk.map(x => shortDate(x.date)), datasets: [{ data: wk.map(x => A.sum(x.items.map(c => c.distanceKm))), backgroundColor: C.blue, borderRadius: 4 }] }, options: barOpts() });
      const p = list.filter(c => c.paceMinPerKm && c.paceMinPerKm < 20);
      chart(root, 'kPace', { type: 'line', data: { labels: p.map(c => shortDate(c.start)), datasets: [{ data: p.map(c => c.paceMinPerKm), borderColor: C.green, backgroundColor: C.green, tension: .25, pointRadius: 3 }] }, options: lineOpts({ scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 10 } }, y: { reverse: true, grace: '5%', ticks: { callback: v => pace(v) } } } }) });
      const h = list.filter(c => c.averageHeartRate > 0);
      chart(root, 'kHr', { type: 'line', data: { labels: h.map(c => shortDate(c.start)), datasets: [{ data: h.map(c => c.averageHeartRate), borderColor: C.bad, backgroundColor: C.bad, tension: .25, pointRadius: 3 }] }, options: lineOpts({ scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 10 } }, y: { grace: '5%' } } }) });
      const zw = A.weekly(list, c => c.start);
      const zdata = zw.map(w => zoneSummary(w.items).minutes);
      const ZC = ['#7fd6ff', '#3ecf8e', '#ffd166', '#ff8a3d', '#ff4d5e'];
      chart(root, 'kZone', { type: 'bar', data: { labels: zw.map(x => shortDate(x.date)), datasets: [0, 1, 2, 3, 4].map(i => ({ label: 'Z' + (i + 1), data: zdata.map(z => z[i]), backgroundColor: ZC[i], stack: 'z' })) }, options: { responsive: true, plugins: { legend: { display: true } }, scales: { x: { stacked: true, grid: { display: false }, ticks: { maxTicksLimit: 10 } }, y: { stacked: true, beginAtZero: true, title: { display: true, text: 'minutes' } } } } });
      const ez = zw.map(w => zoneSummary(w.items).easy);
      chart(root, 'kEasy', { type: 'line', data: { labels: zw.map(x => shortDate(x.date)), datasets: [{ label: '% easy', data: ez, borderColor: C.green, spanGaps: true, tension: .3, pointRadius: 3 }] }, options: lineOpts({ scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 10 } }, y: { min: 0, max: 100 } } }) });
      const mh = root.querySelector('#maxHr'); if (mh) mh.onchange = () => { try { localStorage.setItem('maxHr', mh.value); } catch {} ctx.rerender(); };
      chart(root, 'kStress', { type: 'bar', data: { labels: list.map(c => shortDate(c.start)), datasets: [{ data: list.map(c => c.stress), backgroundColor: C.violet, borderRadius: 4 }] }, options: barOpts({ scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 10 } }, y: { min: 0, max: 100 } } }) });
    } };
  }

  /* ---------------- Stress ---------------- */
  function stress(ctx) {
    const s = ctx.stress;
    if (!s.length || !(ctx.view.sets.length || ctx.view.cardio.length)) return { html: header('Stress & recovery', 'Rolling 7-day training load') + empty('No training data in this period.') };
    const now = s[s.length - 1], band = A.stressBand(now.total);
    const weeks = A.weekly(s, x => x.date, false);
    const rows = weeks.map(w => { const t = A.avg(w.items.map(x => x.total)); return [dateStr(w.date), fmt(t), `<span class="pill ${A.stressBand(t).key}">${A.stressBand(t).label}</span>`, fmt(Math.max(...w.items.map(x => x.total)))]; }).reverse();
    const html = header('Stress & recovery', 'Identical to the app: each day adds its lifting and cardio load to 65% of the previous day’s leftover fatigue. The value is today’s leftover fatigue.') +
      `<div class="grid g4">${kpi('Current stress', fmt(now.total), `<span class="pill ${band.key}">${band.label}</span>`)}${kpi('Recovery score', fmt(100 - now.total), '100 − stress')}${kpi('Period average', fmt(A.avg(s.map(x => x.total))))}${kpi('Peak', fmt(Math.max(...s.map(x => x.total))), 'highest leftover fatigue')}</div>
       <div class="grid g2">${card('Daily training stress', canvas('sTotal', true))}${card('Leftover fatigue by source', canvas('sSplit', true))}</div>
       ${card('Weekly summary', table(['Week of', 'Avg stress', 'Band', 'Peak'], rows, [1, 3]))}
       <p class="foot">Bands: 0–30 recovery, 31–55 productive, 56–75 high, 76–100 very high.</p>`;
    return { html, mount(root) {
      chart(root, 'sTotal', stressLine(s));
      chart(root, 'sSplit', { type: 'line', data: { labels: s.map(x => shortDate(x.date)), datasets: [
        { label: 'Lifting', data: s.map(x => x.lift), borderColor: C.accent, pointRadius: 0, tension: .3 },
        { label: 'Cardio', data: s.map(x => x.run), borderColor: C.blue, pointRadius: 0, tension: .3 }] },
        options: lineOpts({ plugins: { legend: { display: true } }, scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 12 } }, y: { min: 0, max: 100 } } }) });
    } };
  }

  /* ---------------- Bodyweight ---------------- */
  let measureKey = 'waistCm';
  const MEASURES = [['chestCm', 'Chest'], ['shouldersCm', 'Shoulders'], ['neckCm', 'Neck'], ['waistCm', 'Waist'], ['hipsCm', 'Hips'], ['leftBicepsCm', 'Left biceps'], ['rightBicepsCm', 'Right biceps'],
    ['leftForearmCm', 'Left forearm'], ['rightForearmCm', 'Right forearm'], ['leftThighCm', 'Left thigh'], ['rightThighCm', 'Right thigh'], ['leftCalfCm', 'Left calf'], ['rightCalfCm', 'Right calf']];
  function bodyweight(ctx) {
    const w = ctx.view.weights, ms = ctx.view.measurements;
    if (!w.length && !ms.length) return { html: header('Bodyweight', 'Weight and measurements') + empty('No bodyweight data in this period.') };
    const vals = w.map(x => x.kg);
    const change = vals.length > 1 ? vals[vals.length - 1] - vals[0] : null;
    const weeksSpan = w.length > 1 ? (w[w.length - 1].date - w[0].date) / (7 * 86400000) : 0;
    const len = ctx.unit === 'lb' ? 0.393701 : 1, lu = ctx.unit === 'lb' ? 'in' : 'cm';
    const haveMeasures = MEASURES.filter(([k]) => ms.some(x => x[k]));
    if (!haveMeasures.some(([k]) => k === measureKey) && haveMeasures.length) measureKey = haveMeasures[0][0];
    const measTable = haveMeasures.length ? table(['Measurement', 'First', 'Latest', 'Change'], haveMeasures.map(([k, label]) => {
      const v = ms.filter(x => x[k]); const f = v[0][k] * len, l = v[v.length - 1][k] * len;
      return [label, `${fmt(f, 1)} ${lu}`, `${fmt(l, 1)} ${lu}`, delta(l - f, lu)];
    }), [1, 2, 3]) : '<p class="muted">No measurements logged.</p>';
    const html = header('Bodyweight', 'Weigh-in trend and body measurements.') +
      `<div class="grid g4">${kpi('Current', w.length ? `${wv(ctx, vals[vals.length - 1])} <small>${wu(ctx)}</small>` : '—', w.length ? dateStr(w[w.length - 1].date) : '')}${kpi('Change', change == null ? '—' : delta(change * W(ctx), wu(ctx)))}${kpi('Rate', weeksSpan >= 1 ? delta(change / weeksSpan * W(ctx), wu(ctx) + '/wk') : '—')}${kpi('Lowest / highest', w.length ? `${wv(ctx, Math.min(...vals))} / ${wv(ctx, Math.max(...vals))}` : '—', wu(ctx))}${kpi('Weigh-ins', fmt(w.length))}</div>
       ${card('Bodyweight trend', canvas('bTrend', true), '')}
       <div class="grid g2" style="margin-top:16px">${card('Measurements', measTable)}
         ${card(`<div class="row"><span>Measurement history</span><select id="mSelect">${haveMeasures.map(([k, l]) => `<option value="${k}" ${k === measureKey ? 'selected' : ''}>${l}</option>`).join('')}</select></div>`, canvas('bMeasure'))}</div>
       ${card('Weigh-in log', table(['Date', `Weight (${wu(ctx)})`], [...w].reverse().map(x => [dateStr(x.date), wv(ctx, x.kg, 1)]), [1]))}`;
    return { html, mount(root) {
      if (w.length) chart(root, 'bTrend', weightConfig(ctx, w));
      const drawM = () => {
        charts.filter(c => c.canvas.id === 'bMeasure').forEach(c => { c.destroy(); charts = charts.filter(x => x !== c); });
        const v = ms.filter(x => x[measureKey]);
        chart(root, 'bMeasure', { type: 'line', data: { labels: v.map(x => shortDate(x.date)), datasets: [{ data: v.map(x => x[measureKey] * len), borderColor: C.green, backgroundColor: C.green, tension: .25, pointRadius: 4 }] }, options: lineOpts({ scales: { x: { grid: { display: false } }, y: { grace: '5%' } } }) });
      };
      if (haveMeasures.length) { drawM(); root.querySelector('#mSelect').onchange = e => { measureKey = e.target.value; drawM(); }; }
    } };
  }

  /* ---------------- Programs ---------------- */
  function programs(ctx) {
    const ps = ctx.model.programs;
    if (!ps.length) return { html: header('Programs', 'Training programs') + empty('No programs in this export.') };
    const html = header('Programs', 'Program structure as set up in the app (not filtered by period).') + ps.map(p =>
      card(`${esc(p.name)} ${p.isActive ? '<span class="pill recovery">Active</span>' : ''}`,
        (p.days || []).sort((a, z) => a.sortIndex - z.sortIndex).map(d => `<div class="prog-day"><strong>${esc(d.name)}</strong>${
          table(['Exercise', 'Sets × reps', 'Rest', 'Muscles'], (d.exercises || []).sort((a, z) => a.sortIndex - z.sortIndex).map(e => [esc(e.name), `${e.targetSets} × ${e.targetReps}`, e.restSeconds ? e.restSeconds + 's' : '—', esc((e.primaryMuscles || []).join(', '))]), [1, 2]).replace('<table>', '<table class="fixed prog" style="table-layout:fixed;width:100%"><colgroup><col style="width:40%"><col style="width:15%"><col style="width:10%"><col style="width:35%"></colgroup>')}</div>`).join(''), '')).join('<div style="height:16px"></div>');
    return { html };
  }

  const registry = { overview, volume, lifting, cardio, stress, bodyweight, programs };
  const u = { chart, charts: () => charts, setCharts: c => { charts = c; }, colors: () => C, esc, fmt, dateStr, shortDate, duration, pace, W, wv, wu, kpi, card, canvas, header, table, empty, delta, barOpts, lineOpts };
  return { registry, u, setTheme, setDefaultMaxHr, destroyCharts, esc, dateStr };
})();
