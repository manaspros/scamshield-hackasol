import {
  validateRecords, countByDistrict, countByScamType, countByWeek, countByTypePerWeek,
} from './agg.mjs';

const SAMPLE_URL = '../data/trends/sample.json';
const DISTRICTS_URL = '../data/districts.json';
const M1_URL = './m1.json';
const COLORS = ['var(--s1)', 'var(--s2)', 'var(--s3)', 'var(--s4)'];
const OTHER = 'Other types';
const UNCLASSIFIED = 'OTHER';

const label = (t) => String(t).replace(/_/g, ' ').toLowerCase().replace(/^./, (c) => c.toUpperCase());
const TYPE_NAMES = {
  OTP: 'OTP', KYC: 'KYC', DIGITAL_ARREST: 'Digital arrest', COURIER_CUSTOMS: 'Courier or customs', FAKE_QR: 'Fake QR',
  LOAN_APP: 'Loan app', INVESTMENT: 'Investment', JOB: 'Job offer', MISTAKEN_TRANSFER: 'Mistaken transfer', OTHER: 'Other',
};
const named = (map, k) => (Object.hasOwn(map, k) ? map[k] : label(k));
export const typeName = (t) => named(TYPE_NAMES, t);
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
    key: t, name: t === OTHER ? OTHER : typeName(t), color: i < 4 ? COLORS[i] : 'var(--s5)',
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

const SYSTEM_NAMES = { rules: 'Rules only', base_gemma: 'Base Gemma 3 1B', finetuned_gemma: 'Fine-tuned Gemma' };
const LANG_NAMES = { en: 'English', hi: 'Hindi', hinglish: 'Hinglish' };
const METRICS = ['precision', 'recall', 'fpr', 'macro_f1'];
const hasMetrics = (o) => !!o && METRICS.some((k) => typeof o[k] === 'number');

// Rows follow the data: {name, overall, langs:[{name, m}]} per system in m1.systems, or {name, notRun:true}
// when a system has no usable metrics. The three known systems always appear so a missing
// fine-tuned run reads "Not run yet". Falls back to a flat scan for reports without `systems`.
export function accuracyRows(m1) {
  const sys = m1 && m1.systems;
  if (sys && typeof sys === 'object') {
    const keys = [...new Set([...Object.keys(SYSTEM_NAMES), ...Object.keys(sys)])];
    const rows = keys.map((k) => {
      const name = named(SYSTEM_NAMES, k);
      const o = sys[k] && sys[k].overall;
      if (!hasMetrics(o)) {
        const st = sys[k] && typeof sys[k].status === 'string' ? sys[k].status.trim() : '';
        return { name, notRun: true, status: !st || st.toLowerCase() === 'not run' ? 'Not run yet' : st.replace(/^./, (c) => c.toUpperCase()) };
      }
      const per = sys[k].per_language || {};
      return { name, overall: o, langs: Object.keys(per).filter((l) => hasMetrics(per[l]))
        .map((l) => ({ name: named(LANG_NAMES, l), m: per[l] })) };
    });
    return rows.some((r) => !r.notRun) ? rows : [];
  }
  const flat = (o, path = []) => {
    if (!o || typeof o !== 'object') return [];
    if (hasMetrics(o)) return [{ name: path.join(' / ') || 'overall', overall: o, langs: [] }];
    return Object.entries(o).flatMap(([k, v]) => flat(v, [...path, k]));
  };
  return flat(m1);
}

const pct = (v) => (typeof v === 'number' ? `${(v * 100).toFixed(1)}%` : '-');

// Pure: headline figures for the four summary tiles.
export function headline(rows) {
  const total = rows.length;
  const detected = rows.filter((r) => r.scam_type !== UNCLASSIFIED).length;
  const weekly = countByWeek(rows);
  const weeks = Object.keys(weekly).sort();
  const last = weeks[weeks.length - 1];
  const prev = weeks[weeks.length - 2];
  const topType = ranked(countByScamType(rows.filter((r) => r.scam_type !== UNCLASSIFIED)))[0];
  const dates = rows.map((r) => r.date).sort();
  return {
    total, detected, share: total ? detected / total : 0, unclassified: total - detected,
    lastWeek: last, lastCount: weekly[last], delta: prev ? weekly[last] - weekly[prev] : null,
    topType: topType ? { name: typeName(topType[0]), n: topType[1] } : null,
    from: dates[0], to: dates[dates.length - 1],
  };
}

// Pure: best overall accuracy, (tp + tn) / n, among systems that report counts; null when none.
export function modelAccuracy(m1) {
  const found = accuracyRows(m1)
    .filter((r) => !r.notRun && r.overall.counts && r.overall.counts.n > 0)
    .map((r) => ({ system: r.name, value: (r.overall.counts.tp + r.overall.counts.tn) / r.overall.counts.n,
      recall: r.overall.recall, fp: r.overall.counts.fp, n: r.overall.counts.n }));
  if (!found.length) return null;
  const best = found.reduce((a, b) => (b.value > a.value ? b : a));
  return { ...best, synthetic: m1.data?.headline === 'synthetic' };
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const fmtDate = (iso) => `${Number(iso.slice(8))} ${MONTHS[Number(iso.slice(5, 7)) - 1]} ${iso.slice(0, 4)}`;

// Pure: the toggle names the theme it switches to.
export const themeLabel = (dark) => (dark ? 'Light theme' : 'Dark theme');

// Pure: round the axis top up to a 1/2/5 step so ticks are whole numbers.
export function niceScale(max) {
  const raw = Math.max(1, max) / 4;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw);
  const n = Math.ceil(max / step);
  return { step, top: step * Math.max(n, 1) };
}

// Pure: push label y positions apart by at least gap, keeping order, within [lo, hi].
export function spreadLabels(ys, gap, lo, hi) {
  const order = ys.map((y, i) => [y, i]).sort((a, b) => a[0] - b[0]);
  const out = [...ys];
  let prev = lo - gap;
  for (const [y, i] of order) { prev = Math.max(y, prev + gap); out[i] = prev; }
  const over = out.reduce((m, y) => Math.max(m, y - hi), 0);
  return out.map((y) => y - over);
}

if (typeof document !== 'undefined') {
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, text) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  };
  const NS = 'http://www.w3.org/2000/svg';
  const mk = (tag, attrs, text) => {
    const e = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
    if (text !== undefined) e.textContent = text;
    return e;
  };
  let districtNames = [];
  let showAll = false;
  let current = null;
  let summary = null;
  let acc = null;
  let drawnWidth = 0;

  const showError = (msg) => { $('error').textContent = msg; $('error').hidden = !msg; };

  function renderTiles() {
    if (!current) return;
    const h = headline(current.rows);
    const sign = h.delta > 0 ? '+' : h.delta < 0 ? '-' : '';
    const accTile = acc
      ? [`Detector accuracy`, `${(acc.value * 100).toFixed(1)}`, '%',
        `${acc.system}, ${acc.n} ${acc.synthetic ? 'synthetic ' : ''}held-out messages`,
        `Recall ${pct(acc.recall)}, ${acc.fp} false alarms`]
      : ['Detector accuracy', 'Not measured', '', 'No held-out result available yet', ''];
    const items = [
      ['Total reports', String(h.total), '', 'Anonymised reports received', h.delta === null ? '' : `${h.lastWeek}: ${h.lastCount} reports, ${h.delta === 0 ? 'same as the week before' : `${sign}${Math.abs(h.delta)} on the week before`}`],
      ['Scams detected', String(h.detected), '', 'Reports matching a named scam type', h.topType ? `Most common: ${h.topType.name} (${h.topType.n})` : ''],
      ['Share flagged', String(Math.round(h.share * 100)), '%', `${h.detected} of ${h.total} reports`, `${h.unclassified} not yet classified`],
      accTile,
    ];
    $('tiles').replaceChildren(...items.map(([l, v, unit, cap, ctx]) => {
      const t = el('div', 'tile');
      const num = el('div', 'num', v);
      if (unit) num.append(el('small', '', unit));
      if (v === 'Not measured') num.classList.add('na-num');
      t.append(el('div', 'lbl', l), num, el('div', 'cap', cap));
      if (ctx) t.append(el('div', 'ctx', ctx));
      return t;
    }));
    $('period').textContent = `Data ${fmtDate(h.from)} to ${fmtDate(h.to)}`;
  }

  function renderRanking(s) {
    const max = s.districts[0][1];
    const list = showAll ? s.districts : s.districts.slice(0, 10);
    $('ranking').replaceChildren(...list.map(([name, n]) => {
      const row = el('div', 'rank');
      const fill = el('div', 'bar-fill');
      fill.style.setProperty('--r', n / max);
      const track = el('div', 'track');
      track.append(fill, el('span', 'v', String(n)));
      row.append(el('span', 'name', name), track);
      return row;
    }));
    const more = $('more');
    more.hidden = s.districts.length <= 10;
    more.textContent = showAll ? 'Show top 10 only' : `Show all ${s.districts.length} districts`;
  }

  function renderTrend(full) {
    const series = full.series.filter((x) => x.key !== OTHER);
    const W = Math.max(280, Math.floor($('trend').clientWidth));
    drawnWidth = W;
    const PW = W > 640 ? Math.floor((W - 24) / 2) : W;
    const H = 170, L = 28, R = 12, T = 12, B = 28;
    const weeks = full.weeks;
    const n = weeks.length;
    const { step, top } = niceScale(Math.max(1, ...series.flatMap((x) => x.values)));
    const x = (i) => L + (n === 1 ? (PW - L - R) / 2 : (i / (n - 1)) * (PW - L - R));
    const y = (v) => T + (1 - v / top) * (H - T - B);
    const tip = $('tip');
    const every = Math.max(1, Math.ceil(n / Math.max(1, Math.floor((PW - L - R) / 44))));
    const panels = series.map((ser) => {
      const last = ser.values[n - 1];
      const panel = el('div', 'panel');
      const title = el('h3', '', `${ser.name} \u00b7 ${last} this week`);
      title.style.setProperty('--c', ser.color);
      const svg = mk('svg', { viewBox: `0 0 ${PW} ${H}`, role: 'img',
        'aria-label': `${ser.name}: weekly reports from ${weeks[0]} to ${weeks[n - 1]}, latest week ${last}, peak ${Math.max(...ser.values)}. Same scale as the other panels. A data table follows the charts.` });
      svg.append(mk('title', {}, `${ser.name}, weekly reports`));
      for (let v = 0; v <= top; v += step) {
        svg.append(mk('line', { class: 'grid', x1: L, x2: PW - R, y1: y(v), y2: y(v) }),
          mk('text', { x: L - 6, y: y(v) + 4, 'text-anchor': 'end' }, v));
      }
      weeks.forEach((w, i) => { if (i % every === 0) svg.append(mk('text', { x: x(i), y: H - 8, 'text-anchor': 'middle' }, w.slice(5))); });
      const pts = ser.values.map((v, i) => `${x(i)},${y(v)}`);
      svg.append(mk('polygon', { points: `${x(0)},${y(0)} ${pts.join(' ')} ${x(n - 1)},${y(0)}`, fill: ser.color, 'fill-opacity': 0.12 }),
        mk('polyline', { class: 'line', stroke: ser.color, points: pts.join(' ') }),
        mk('circle', { cx: x(n - 1), cy: y(last), r: 4, fill: ser.color, stroke: 'var(--card)', 'stroke-width': 2 }));
      const cross = mk('line', { class: 'cross', y1: T, y2: H - B, visibility: 'hidden' });
      svg.append(cross);
      svg.addEventListener('pointermove', (e) => {
        const r = svg.getBoundingClientRect();
        const px = ((e.clientX - r.left) / r.width) * PW;
        const i = Math.min(n - 1, Math.max(0, Math.round(((px - L) / (PW - L - R)) * (n - 1))));
        cross.setAttribute('x1', x(i)); cross.setAttribute('x2', x(i)); cross.setAttribute('visibility', 'visible');
        tip.replaceChildren(el('strong', '', weeks[i]), el('div', '', `${ser.name}: ${ser.values[i]}`));
        tip.hidden = false;
        tip.style.left = `${Math.min(e.clientX + 14, window.innerWidth - 256)}px`;
        tip.style.top = `${e.clientY + 14}px`;
      });
      svg.addEventListener('pointerleave', () => { tip.hidden = true; cross.setAttribute('visibility', 'hidden'); });
      panel.append(title, svg);
      return panel;
    });
    $('trend').replaceChildren(...panels);
  }

  function renderTrendMeta(s) {
    const other = s.series.find((x) => x.key === OTHER);
    $('other-note').textContent = other ? `Other types (not shown): ${other.values.reduce((a, b) => a + b, 0)} reports over the period` : '';
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
    const cols = [['precision', 'Precision'], ['recall', 'Recall'], ['fpr', 'False alarms']];
    const table = el('table');
    const head = el('tr');
    head.append(el('th', '', 'System and language'), ...cols.map(([c, t]) => { const th = el('th', '', t); if (c === 'fpr') th.title = 'False positive rate: share of genuine messages wrongly flagged as scams'; return th; }));
    table.append(head);
    const line = (name, m, cls) => {
      const first = el('td', '', name);
      const tr = el('tr', cls);
      tr.append(first, ...cols.map(([c]) => el('td', '', pct(m[c]))));
      table.append(tr);
    };
    for (const r of rows) {
      if (r.notRun) {
        const none = el('td', 'notrun', r.status);
        none.colSpan = cols.length;
        const tr = el('tr', 'group');
        tr.append(el('td', 'sysname', r.name), none);
        table.append(tr);
        continue;
      }
      line(r.name, r.overall, 'group head');
      for (const l of r.langs) line(l.name, l.m, 'sub');
    }
    const wrap = el('div', 'scroll');
    wrap.append(table);
    box.replaceChildren(wrap);
    const d = m1.data;
    if (d && typeof d.synthetic_rows === 'number' && typeof d.real_rows === 'number') {
      box.append(el('p', 'note-line', `False alarms are the false positive rate: genuine messages wrongly flagged as scams. ${d.headline === 'synthetic' ? 'Synthetic held-out set' : 'Held-out set'}: ${d.synthetic_rows + d.real_rows} rows, ${d.real_rows} real`));
    }
  }

  function render(data) {
    current = data;
    $('banner').hidden = !data.synthetic;
    if (data.synthetic) $('banner').textContent = 'Synthetic sample data. These numbers are not real reports.';
    summary = summarize(data.rows);
    renderTiles(); renderRanking(summary); renderTrendMeta(summary); renderTrend(summary);
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
  $('more').addEventListener('click', () => { showAll = !showAll; if (summary) renderRanking(summary); });
  const isDark = () => (document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')) === 'dark';
  const syncTheme = () => {
    const dark = isDark();
    $('theme').setAttribute('aria-pressed', String(dark));
    $('theme').textContent = themeLabel(dark);
  };
  $('theme').addEventListener('click', () => {
    document.documentElement.dataset.theme = isDark() ? 'light' : 'dark';
    syncTheme();
  });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', syncTheme);
  syncTheme();
  // Charts are drawn in real pixels, so redraw when the container width changes.
  new ResizeObserver(() => { if (summary && Math.floor($('trend').clientWidth) !== drawnWidth) renderTrend(summary); }).observe($('trend'));

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
    acc = modelAccuracy(m1);
    renderAccuracy(m1);
    renderTiles();
  })();
}
