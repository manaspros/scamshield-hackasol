import {
  validateRecords, countByDistrict, countByScamType, countByWeek, countByTypePerWeek,
} from './agg.mjs';

const SAMPLE_URL = '../data/trends/sample.json';
const DISTRICTS_URL = '../data/districts.json';
const M1_URL = './m1.json';
const COLORS = ['var(--s1)', 'var(--s2)', 'var(--s3)', 'var(--s4)'];
const OTHER = 'Other types';

const label = (t) => t.replace(/_/g, ' ').toLowerCase().replace(/^./, (c) => c.toUpperCase());
const ranked = (counts) => Object.entries(counts).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));

// Accepts a bare array or {rows: [...]}; throws TypeError with a readable message.
export function parseExport(text, districts) {
  let parsed;
  try { parsed = JSON.parse(text); } catch { throw new TypeError('File is not valid JSON.'); }
  const rows = Array.isArray(parsed) ? parsed : parsed && Array.isArray(parsed.rows) ? parsed.rows : null;
  if (!rows) throw new TypeError('Expected a JSON array of reports, or an object with a "rows" array.');
  if (rows.length === 0) throw new TypeError('The file has no reports.');
  validateRecords(rows, districts);
  return { rows, synthetic: !Array.isArray(parsed) && parsed._synthetic === true };
}

export function summarize(rows) {
  const districts = ranked(countByDistrict(rows));
  const types = ranked(countByScamType(rows));
  const weekly = countByWeek(rows);
  const perWeek = countByTypePerWeek(rows);
  const weeks = Object.keys(weekly).sort();
  const top = types.slice(0, 4).map(([t]) => t);
  const series = [...top, OTHER].map((t, i) => ({
    key: t, name: t === OTHER ? OTHER : label(t), color: i < 4 ? COLORS[i] : 'var(--s5)',
    values: weeks.map((w) => t === OTHER
      ? Object.entries(perWeek[w]).filter(([k]) => !top.includes(k)).reduce((s, [, n]) => s + n, 0)
      : perWeek[w][t] ?? 0),
  })).filter((s) => s.key !== OTHER || s.values.some((v) => v > 0));
  return { total: rows.length, districts, types, weeks, series };
}

// Pure: text for the accuracy panel when there is no usable report.
export function accuracyText(m1) {
  return accuracyRows(m1).length ? '' : 'not measured';
}

// Shape-agnostic: collect any nested object carrying precision/recall/fpr/f1 numbers.
export function accuracyRows(m1, path = []) {
  if (!m1 || typeof m1 !== 'object') return [];
  const keys = ['precision', 'recall', 'fpr', 'macro_f1', 'f1'];
  if (keys.some((k) => typeof m1[k] === 'number')) return [{ name: path.join(' / ') || 'overall', ...m1 }];
  return Object.entries(m1).flatMap(([k, v]) => accuracyRows(v, [...path, k]));
}

const pct = (v) => (typeof v === 'number' ? `${(v * 100).toFixed(1)}%` : '-');

if (typeof document !== 'undefined') {
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, text) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  };
  let districtNames = [];
  let showAll = false;
  let current = null;

  const showError = (msg) => { $('error').textContent = msg; $('error').hidden = !msg; };

  function renderTiles(s) {
    const items = [
      ['Total reports', String(s.total), ''],
      ['Top district', s.districts[0][0], `${s.districts[0][1]} reports`],
      ['Top scam type', label(s.types[0][0]), `${s.types[0][1]} reports`],
      ['Weeks covered', String(s.weeks.length), `${s.weeks[0]} to ${s.weeks[s.weeks.length - 1]}`],
    ];
    $('tiles').replaceChildren(...items.map(([l, v, n]) => {
      const t = el('div', 'tile');
      t.append(el('div', 'lbl', l), el('div', 'num', v), el('div', 'note', n));
      return t;
    }));
  }

  function renderRanking(s) {
    const max = s.districts[0][1];
    const list = showAll ? s.districts : s.districts.slice(0, 10);
    $('ranking').replaceChildren(...list.map(([name, n]) => {
      const row = el('div', 'rank');
      const bar = el('div', 'bar');
      bar.style.width = `${(n / max) * 100}%`;
      const track = el('div', 'track');
      track.append(bar);
      row.append(el('span', 'name', name), track, el('span', 'v', String(n)));
      return row;
    }));
    const more = $('more');
    more.hidden = s.districts.length <= 10;
    more.textContent = showAll ? 'Show top 10 only' : `Show all ${s.districts.length} districts`;
  }

  function renderTrend(s) {
    const W = 640, H = 260, L = 34, R = 12, T = 10, B = 28;
    const n = s.weeks.length;
    const ymax = Math.max(1, ...s.series.flatMap((x) => x.values));
    const x = (i) => L + (n === 1 ? (W - L - R) / 2 : (i / (n - 1)) * (W - L - R));
    const y = (v) => T + (1 - v / ymax) * (H - T - B);
    const NS = 'http://www.w3.org/2000/svg';
    const mk = (tag, attrs, text) => {
      const e = document.createElementNS(NS, tag);
      for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
      if (text !== undefined) e.textContent = text;
      return e;
    };
    const svg = mk('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img',
      'aria-label': 'Weekly report counts by scam type. A table view follows.' });
    for (let g = 0; g <= 4; g++) {
      const v = Math.round((ymax * g) / 4);
      svg.append(mk('line', { class: 'grid', x1: L, x2: W - R, y1: y(v), y2: y(v) }),
        mk('text', { x: L - 6, y: y(v) + 4, 'text-anchor': 'end' }, v));
    }
    const step = Math.max(1, Math.ceil(n / 8));
    s.weeks.forEach((w, i) => { if (i % step === 0) svg.append(mk('text', { x: x(i), y: H - 8, 'text-anchor': 'middle' }, w.slice(5))); });
    for (const ser of s.series) {
      svg.append(mk('polyline', { class: 'line', stroke: ser.color,
        points: ser.values.map((v, i) => `${x(i)},${y(v)}`).join(' ') }));
      const end = ser.values.length - 1;
      svg.append(mk('circle', { cx: x(end), cy: y(ser.values[end]), r: 4, fill: ser.color, stroke: 'var(--surface)', 'stroke-width': 2 }));
    }
    const cross = mk('line', { class: 'cross', y1: T, y2: H - B, visibility: 'hidden' });
    svg.append(cross);
    const tip = $('tip');
    const move = (e) => {
      const r = svg.getBoundingClientRect();
      const px = ((e.clientX - r.left) / r.width) * W;
      const i = Math.min(n - 1, Math.max(0, Math.round(((px - L) / (W - L - R)) * (n - 1))));
      cross.setAttribute('x1', x(i)); cross.setAttribute('x2', x(i)); cross.setAttribute('visibility', 'visible');
      tip.replaceChildren(el('strong', '', s.weeks[i]), ...s.series.map((ser) => el('div', '', `${ser.name}: ${ser.values[i]}`)));
      tip.hidden = false;
      tip.style.left = `${Math.min(e.clientX + 14, window.innerWidth - 240)}px`;
      tip.style.top = `${e.clientY + 14}px`;
    };
    svg.addEventListener('pointermove', move);
    svg.addEventListener('pointerleave', () => { tip.hidden = true; cross.setAttribute('visibility', 'hidden'); });
    $('trend').replaceChildren(svg);

    $('legend').replaceChildren(...s.series.map((ser) => {
      const sp = el('span', '', ser.name);
      sp.style.setProperty('--c', ser.color);
      return sp;
    }));

    const table = el('table');
    const head = el('tr');
    head.append(el('th', '', 'Week'), ...s.series.map((x2) => el('th', '', x2.name)));
    table.append(head);
    s.weeks.forEach((w, i) => {
      const r = el('tr');
      r.append(el('td', '', w), ...s.series.map((x2) => el('td', '', String(x2.values[i]))));
      table.append(r);
    });
    $('trend-table').replaceChildren(table);
  }

  function renderAccuracy(m1) {
    const box = $('accuracy');
    const rows = accuracyRows(m1);
    if (!rows.length) { box.replaceChildren(el('p', 'na', accuracyText(m1))); return; }
    const cols = ['precision', 'recall', 'fpr', 'macro_f1'].filter((k) => rows.some((r) => typeof r[k] === 'number'));
    const table = el('table');
    const head = el('tr');
    head.append(el('th', '', 'System / language'), ...cols.map((c) => el('th', '', c === 'fpr' ? 'False positive rate' : label(c))));
    table.append(head);
    for (const r of rows) {
      const tr = el('tr');
      tr.append(el('td', '', r.name), ...cols.map((c) => el('td', '', pct(r[c]))));
      table.append(tr);
    }
    const wrap = el('div', 'scroll');
    wrap.append(table);
    box.replaceChildren(wrap);
  }

  function render(data) {
    current = data;
    $('banner').hidden = !data.synthetic;
    if (data.synthetic) $('banner').textContent = 'Synthetic sample data. These numbers are not real reports.';
    const s = summarize(data.rows);
    renderTiles(s); renderRanking(s); renderTrend(s);
  }

  function load(text) {
    try {
      render(parseExport(text, districtNames));
      showError('');
    } catch (e) {
      showError(`Could not load that file: ${e.message}`);
    }
  }

  const readFile = (f) => f && f.text().then(load, () => showError('Could not read that file.'));
  $('file').addEventListener('change', (e) => readFile(e.target.files[0]));
  const drop = $('drop');
  drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.classList.add('over'); });
  drop.addEventListener('dragleave', () => drop.classList.remove('over'));
  drop.addEventListener('drop', (e) => { e.preventDefault(); drop.classList.remove('over'); readFile(e.dataTransfer.files[0]); });
  $('more').addEventListener('click', () => { showAll = !showAll; if (current) renderRanking(summarize(current.rows)); });
  $('theme').addEventListener('click', (e) => {
    const root = document.documentElement;
    const dark = (root.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')) !== 'dark';
    root.dataset.theme = dark ? 'dark' : 'light';
    e.target.setAttribute('aria-pressed', String(dark));
    e.target.textContent = dark ? 'Light theme' : 'Dark theme';
  });

  (async () => {
    try {
      const [d, s] = await Promise.all([fetch(DISTRICTS_URL), fetch(SAMPLE_URL)]);
      if (!d.ok || !s.ok) throw new Error('sample files not found');
      districtNames = (await d.json()).districts;
      load(await s.text());
    } catch (e) {
      showError(`Could not load the sample data (${e.message}). Open a file instead. Opening this page from file:// blocks loading; serve the repo folder over http.`);
    }
    let m1 = null;
    try { const r = await fetch(M1_URL); if (r.ok) m1 = await r.json(); } catch { /* not measured */ }
    renderAccuracy(m1);
  })();
}
