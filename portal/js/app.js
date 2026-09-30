/* Router, global state (client / period / unit) and import flow. */
(() => {
  const A = Analytics, P = Pages;
  const $ = s => document.querySelector(s);
  const view = $('#view'), top = $('#top');
  const ls = {
    get: (k, d) => { try { return localStorage.getItem(k) ?? d; } catch { return d; } },
    set: (k, v) => { try { localStorage.setItem(k, v); } catch {} },
  };
  const state = { clients: [], clientId: ls.get('clientId', null), range: ls.get('range', 'all'), from: '', to: '', unit: ls.get('unit', 'kg'), model: null };

  const routes = P.registry;

  function currentClient() { return state.clients.find(c => c.id === state.clientId) || null; }

  function buildModel() {
    const c = currentClient();
    state.model = c ? A.parse(c.backup) : null;
    applyTheme(c && c.backup.theme);
  }

  /* Match the colours the client uses in the app (accent, background, card, light/dark). */
  const DEFAULT_THEME = { accentHex: 'FF5A2B', backgroundHex: '0A0A0B', cardHex: '141317', isDark: true };
  const rgb = h => { const n = parseInt(h, 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
  const toHex = c => '#' + c.map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
  const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
  const lum = c => (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255;
  function applyTheme(t) {
    const th = { ...DEFAULT_THEME, ...(t || {}) };
    const valid = h => /^[0-9a-fA-F]{6}$/.test(h);
    if (!valid(th.accentHex)) th.accentHex = DEFAULT_THEME.accentHex;
    if (!valid(th.backgroundHex)) th.backgroundHex = DEFAULT_THEME.backgroundHex;
    if (!valid(th.cardHex)) th.cardHex = DEFAULT_THEME.cardHex;
    const bg = rgb(th.backgroundHex), card = rgb(th.cardHex), accent = rgb(th.accentHex);
    const dark = lum(bg) < 0.5;
    const ink = dark ? [243, 241, 236] : [28, 28, 30];
    const r = document.documentElement.style;
    r.setProperty('--void', toHex(bg));
    r.setProperty('--panel', toHex(card));
    r.setProperty('--panel-2', toHex(mix(card, dark ? [255, 255, 255] : [0, 0, 0], 0.07)));
    r.setProperty('--ink', toHex(ink));
    r.setProperty('--ink-dim', toHex(mix(ink, bg, 0.36)));
    r.setProperty('--ink-faint', toHex(mix(ink, bg, 0.58)));
    r.setProperty('--line', dark ? 'rgba(255,255,255,.12)' : 'rgba(0,0,0,.10)');
    r.setProperty('--hover', dark ? 'rgba(255,255,255,.03)' : 'rgba(0,0,0,.03)');
    r.setProperty('--accent', toHex(accent));
    r.setProperty('--accent-2', toHex(mix(accent, [255, 62, 127], 0.35)));
    r.setProperty('--accent-rgb', accent.map(Math.round).join(','));
    r.setProperty('--on-accent', lum(accent) > 0.55 ? '#111' : '#fff');
    r.setProperty('color-scheme', dark ? 'dark' : 'light');
    P.setTheme({ accent: toHex(accent), dim: toHex(mix(ink, bg, 0.36)), grid: dark ? 'rgba(255,255,255,.08)' : 'rgba(0,0,0,.08)' });
  }

  function context() {
    const model = state.model, b = A.bounds(model);
    const end = A.startOfDay(b ? b.last : new Date());
    let from = b ? b.first : end, to = new Date(end.getTime() + 86399999);
    if (state.range === 'custom') {
      if (state.from) from = new Date(state.from + 'T00:00:00');
      if (state.to) to = new Date(state.to + 'T23:59:59');
    } else if (state.range !== 'all') {
      from = A.addDays(end, -Number(state.range) + 1);
    }
    from = A.startOfDay(from);
    const sliced = A.slice(model, from, to);
    // Stress needs the previous 7 days of context, so compute it on the full model.
    const stress = A.stressSeries(model, from, to <= new Date() ? to : new Date());
    return { client: currentClient(), model, view: sliced, from, to, stress, unit: state.unit, rangeKey: state.range, rerender: render };
  }

  function renderTop() {
    const c = currentClient();
    const ranges = [['30', '30d'], ['90', '90d'], ['180', '6m'], ['365', '1y'], ['all', 'All'], ['custom', 'Custom']];
    top.innerHTML = state.clients.length ? `
      <select id="clientSel">${state.clients.map(x => `<option value="${x.id}" ${x.id === state.clientId ? 'selected' : ''}>${P.esc(x.name)}</option>`).join('')}</select>
      <div class="seg" id="rangeSeg">${ranges.map(([k, l]) => `<button data-r="${k}" class="${state.range === k ? 'on' : ''}">${l}</button>`).join('')}</div>
      ${state.range === 'custom' ? `<input type="date" id="fromD" value="${state.from}"><span class="muted">to</span><input type="date" id="toD" value="${state.to}">` : ''}
      <span class="grow"></span>
      <div class="seg" id="unitSeg"><button data-u="kg" class="${state.unit === 'kg' ? 'on' : ''}">kg</button><button data-u="lb" class="${state.unit === 'lb' ? 'on' : ''}">lb</button></div>
      <button id="printBtn">Print</button>` : '<span class="muted">No clients yet — import a VIGOR export to begin.</span>';
    if (!state.clients.length) return;
    $('#clientSel').onchange = e => { state.clientId = e.target.value; ls.set('clientId', state.clientId); buildModel(); render(); };
    top.querySelectorAll('#rangeSeg button').forEach(b => b.onclick = () => { state.range = b.dataset.r; ls.set('range', state.range); render(); });
    top.querySelectorAll('#unitSeg button').forEach(b => b.onclick = () => { state.unit = b.dataset.u; ls.set('unit', state.unit); render(); });
    $('#printBtn').onclick = () => window.print();
    const f = $('#fromD'), t = $('#toD');
    if (f) { f.onchange = () => { state.from = f.value; render(); }; t.onchange = () => { state.to = t.value; render(); }; }
  }

  function routeName() {
    const r = (location.hash.replace(/^#\//, '') || 'overview');
    return r in routes || r === 'clients' ? r : 'overview';
  }

  function render() {
    P.destroyCharts();
    renderTop();
    const name = routeName();
    document.querySelectorAll('#nav a').forEach(a => a.classList.toggle('active', a.dataset.route === name));
    if (name === 'clients' || !state.model) return renderClients();
    const page = routes[name](context());
    view.innerHTML = page.html;
    view.querySelectorAll('.g4').forEach(g => { g.style.setProperty('--n', g.children.length); g.dataset.n = g.children.length; });
    if (page.mount) page.mount(view);
  }

  /* ---------------- Clients & import ---------------- */
  function renderClients() {
    view.innerHTML = `<h1>Clients &amp; import</h1><p class="sub">Import the .json file exported from the VIGOR app. Each import is stored as a client in this browser only.</p>
      <div class="card" style="margin-bottom:16px">
        <div class="drop" id="drop"><p><strong>Drop a VIGOR export here</strong></p><p>or</p><p style="margin-top:10px"><button class="primary" id="pick">Choose file…</button></p><input type="file" id="file" accept=".json,application/json" multiple hidden></div>
        <p class="foot" id="msg"></p>
      </div>
      <div class="card"><h2>Stored clients</h2>${state.clients.length ? state.clients.map(c => `
        <div class="client-row"><div class="grow"><strong>${P.esc(c.name)}</strong><div class="muted">${c.summary}</div></div>
        <button data-open="${c.id}">Open</button><button data-re="${c.id}">Rename</button><button class="danger" data-del="${c.id}">Delete</button></div>`).join('') : '<p class="muted">No clients yet.</p>'}
        <p class="foot">Importing the same client again? Give it the same name to replace their previous data.</p></div>`;
    const drop = $('#drop'), file = $('#file'), msg = $('#msg');
    $('#pick').onclick = () => file.click();
    file.onchange = () => importFiles([...file.files], msg);
    ['dragenter', 'dragover'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add('over'); }));
    ['dragleave', 'drop'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove('over'); }));
    drop.addEventListener('drop', e => importFiles([...e.dataTransfer.files], msg));
    view.querySelectorAll('[data-open]').forEach(b => b.onclick = () => { state.clientId = b.dataset.open; ls.set('clientId', state.clientId); buildModel(); location.hash = '#/overview'; render(); });
    view.querySelectorAll('[data-del]').forEach(b => b.onclick = async () => {
      const c = state.clients.find(x => x.id === b.dataset.del);
      if (!confirm(`Delete ${c.name} and all their data from this browser?`)) return;
      await Store.remove(c.id); await reload(); render();
    });
    view.querySelectorAll('[data-re]').forEach(b => b.onclick = async () => {
      const c = state.clients.find(x => x.id === b.dataset.re);
      const n = prompt('Client name', c.name); if (!n || !n.trim()) return;
      c.name = n.trim(); await Store.save(c); await reload(); render();
    });
  }

  async function importFiles(files, msg) {
    const out = [];
    for (const f of files) {
      try {
        const backup = JSON.parse(await f.text());
        if (!backup || !Array.isArray(backup.sessions) || !Array.isArray(backup.bodyWeights)) throw new Error('not a VIGOR export');
        const def = f.name.replace(/\.json$/i, '').replace(/^workout-data-?/, '').replace(/[-_]?\d{4}-\d{2}-\d{2}.*/, '').replace(/-/g, ' ').trim();
        const name = (prompt(`Client name for “${f.name}”`, def && def !== 'all time' ? def : '') || '').trim();
        if (!name) { out.push(`Skipped ${f.name}`); continue; }
        const existing = state.clients.find(c => c.name.toLowerCase() === name.toLowerCase());
        const client = existing || { id: crypto.randomUUID ? crypto.randomUUID() : String(Date.now() + Math.random()), name };
        client.importedAt = Date.now();
        client.backup = mergeBackups(existing && existing.backup, backup);
        const m = A.parse(client.backup);
        client.summary = `${m.sessions.length} sessions · ${m.cardio.length} cardio · ${m.weights.length} weigh-ins · exported ${P.dateStr(m.exportedAt)}`;
        await Store.save(client);
        state.clientId = client.id; ls.set('clientId', client.id);
        out.push(`${existing ? 'Updated' : 'Imported'} ${name}`);
      } catch (e) { out.push(`${f.name}: ${e.message}`); }
    }
    await reload();
    if (out.some(x => /^(Imported|Updated)/.test(x))) { location.hash = '#/overview'; }
    render();
    const m = $('#msg'); if (m) m.textContent = out.join(' · ');
  }

  /** Re-importing a client merges by id/date so earlier history is never lost. */
  function mergeBackups(old, nw) {
    if (!old) return nw;
    const uniq = (a, b, key) => { const m = new Map(); [...(a || []), ...(b || [])].forEach(x => m.set(key(x), x)); return [...m.values()]; };
    return {
      ...nw,
      programs: uniq(old.programs, nw.programs, x => x.uuid),
      sessions: uniq(old.sessions, nw.sessions, x => x.uuid),
      bodyWeights: uniq(old.bodyWeights, nw.bodyWeights, x => x.date),
      measurements: uniq(old.measurements, nw.measurements, x => x.date),
      cardio: uniq(old.cardio, nw.cardio, x => x.start),
      theme: nw.theme || old.theme,
    };
  }

  async function reload() {
    state.clients = (await Store.list()).sort((a, z) => a.name.localeCompare(z.name));
    if (!currentClient()) state.clientId = state.clients[0] ? state.clients[0].id : null;
    buildModel();
  }

  window.addEventListener('hashchange', render);
  reload().then(() => { if (!state.model && !location.hash) location.hash = '#/clients'; render(); });
})();
