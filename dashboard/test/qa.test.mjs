import test from 'node:test';
import assert from 'node:assert/strict';
import {
  validateRecords, isoWeek, countByDistrict, countByScamType, countByWeek, countByTypePerWeek, SCAM_TYPES,
} from '../agg.mjs';
import { parseExport, summarize, headline, typeName } from '../app.js';

const D = ['Raipur', 'Bilaspur'];
const ok = (o = {}) => ({ district: 'Raipur', scam_type: 'OTP', date: '2026-01-05', ...o });
const rejects = (rows, re) => assert.throws(() => validateRecords(rows, D), re);

test('QA validate privacy: any extra or missing key is rejected', () => {
  for (const extra of ['text', 'message', 'phone', 'raw_text', 'id', '__proto__x']) {
    rejects([ok({ [extra]: 'secret' })], /exactly district, scam_type, date/);
  }
  rejects([{ district: 'Raipur', scam_type: 'OTP' }], /exactly/);
  rejects([{ district: 'Raipur', scam_type: 'OTP', dat: '2026-01-05' }], /exactly/);
  rejects([{}], /exactly/);
});

test('QA validate own __proto__ key from JSON.parse is rejected as an extra key', () => {
  const row = JSON.parse('{"district":"Raipur","scam_type":"OTP","date":"2026-01-05","__proto__":{"text":"x"}}');
  rejects([row], /exactly/);
});

test('QA validate key order does not matter and valid rows pass through unchanged', () => {
  const rows = [{ date: '2026-01-05', scam_type: 'KYC', district: 'Bilaspur' }];
  assert.equal(validateRecords(rows, D), rows);
});

test('QA validate every documented scam type accepted, near-misses rejected', () => {
  assert.equal(SCAM_TYPES.length, 18);
  for (const t of SCAM_TYPES) validateRecords([ok({ scam_type: t })], D);
  for (const t of ['otp', 'OTP ', 'SCAM', '', 'constructor', 'toString']) rejects([ok({ scam_type: t })], /unknown scam_type/);
});

test('QA validate district must be an exact listed string', () => {
  for (const d of ['raipur', 'Raipur ', '', 'constructor', '__proto__']) rejects([ok({ district: d })], /unknown district/);
  for (const d of [null, 5, ['Raipur'], undefined]) rejects([ok({ district: d })], /unknown district/);
});

test('QA validate dates: format, calendar and type', () => {
  validateRecords([ok({ date: '2024-02-29' }), ok({ date: '2026-12-31' })], D);
  for (const date of ['2026-02-29', '2026-02-30', '2026-13-01', '2026-00-10', '2026-04-31', '2026-1-5', '26-01-05',
    '2026-01-05T00:00:00Z', ' 2026-01-05', '2026/01/05', '', '٢٠٢٦-٠١-٠٥']) {
    rejects([ok({ date })], /date must be|invalid calendar date/);
  }
  for (const date of [null, 20260105, {}, ['2026-01-05']]) rejects([ok({ date })], /date must be/);
});

test('QA validate non-object rows and bad containers', () => {
  for (const bad of [null, 5, 'row', [], [ok()]]) rejects([bad], /row 1: must be an object|exactly/);
  assert.throws(() => validateRecords({}, D), /records must be an array/);
  assert.throws(() => validateRecords(null, D), TypeError);
  assert.throws(() => validateRecords([], 'Raipur'), /districts must be an array/);
  assert.throws(() => validateRecords([], [1]), /districts/);
  assert.deepEqual(validateRecords([], D), []);
});

test('QA validate error names the offending row number', () => {
  rejects([ok(), ok(), ok({ scam_type: 'X' })], /row 3:/);
});

test('QA parseExport garbage and empty inputs raise TypeError with a readable message', () => {
  for (const [input, re] of [
    ['', /not valid JSON/], ['   ', /not valid JSON/], ['{nope', /not valid JSON/], ['undefined', /not valid JSON/],
    ['null', /Expected a JSON array/], ['123', /Expected a JSON array/], ['"str"', /Expected a JSON array/],
    ['true', /Expected a JSON array/], ['{}', /Expected a JSON array/], ['{"rows":"x"}', /Expected a JSON array/],
    ['{"rows":null}', /Expected a JSON array/], ['[]', /no reports/], ['{"rows":[]}', /no reports/],
  ]) {
    assert.throws(() => parseExport(input, D), (e) => e instanceof TypeError && re.test(e.message), input);
  }
});

test('QA parseExport rejects raw-text leakage in rows but ignores wrapper metadata', () => {
  const leaky = JSON.stringify([ok({ text: 'Your OTP is 1234' })]);
  assert.throws(() => parseExport(leaky, D), /exactly district, scam_type, date/);
  const wrapped = JSON.stringify({ rows: [ok()], raw_text: 'private', _synthetic: true });
  const r = parseExport(wrapped, D);
  assert.deepEqual(r.rows, [ok()]);
  assert.equal(r.synthetic, true);
  assert.equal(JSON.stringify(r).includes('private'), false);
});

test('QA parseExport synthetic flag is strictly boolean true and only for wrapper', () => {
  assert.equal(parseExport(JSON.stringify({ rows: [ok()], _synthetic: 'true' }), D).synthetic, false);
  assert.equal(parseExport(JSON.stringify({ rows: [ok()], _synthetic: 1 }), D).synthetic, false);
  assert.equal(parseExport(JSON.stringify([ok()]), D).synthetic, false);
});

test('QA parseExport huge input: 200k valid rows parse fast, huge garbage and deep nesting throw cleanly', () => {
  const rows = Array.from({ length: 200000 }, (_, i) => ok({ date: `2026-01-${String((i % 28) + 1).padStart(2, '0')}` }));
  const t0 = Date.now();
  const r = parseExport(JSON.stringify(rows), D);
  assert.equal(r.rows.length, 200000);
  assert.ok(Date.now() - t0 < 5000, 'took too long');
  assert.throws(() => parseExport('x'.repeat(5_000_000), D), /not valid JSON/);
  assert.throws(() => parseExport('['.repeat(100000), D), TypeError);
  assert.throws(() => parseExport(`[${'['.repeat(50000)}${']'.repeat(50000)}]`, D), TypeError);
});

// Independent ISO-8601 week algorithm (ordinal method) used as an oracle.
function oracle(y, m, d) {
  const utc = Date.UTC(y, m - 1, d);
  const ord = Math.round((utc - Date.UTC(y, 0, 0)) / 86400000);
  const wd = ((new Date(utc).getUTCDay() + 6) % 7) + 1;
  const p = (yy) => (yy + Math.floor(yy / 4) - Math.floor(yy / 100) + Math.floor(yy / 400)) % 7;
  const weeksIn = (yy) => (p(yy) === 4 || p(yy - 1) === 3 ? 53 : 52);
  let w = Math.floor((ord - wd + 10) / 7);
  let wy = y;
  if (w < 1) { wy = y - 1; w = weeksIn(wy); } else if (w > weeksIn(y)) { wy = y + 1; w = 1; }
  return `${wy}-W${String(w).padStart(2, '0')}`;
}

test('QA isoWeek year boundaries, week 53 and 1990-2040 sweep against an independent oracle', () => {
  const cases = {
    '2020-12-31': '2020-W53', '2021-01-01': '2020-W53', '2021-01-03': '2020-W53', '2021-01-04': '2021-W01',
    '2024-12-28': '2024-W52', '2024-12-29': '2024-W52', '2024-12-30': '2025-W01', '2025-01-05': '2025-W01',
    '2025-12-28': '2025-W52', '2025-12-29': '2026-W01', '2026-01-01': '2026-W01', '2026-01-04': '2026-W01',
    '2026-01-05': '2026-W02', '2026-12-31': '2026-W53', '2027-01-03': '2026-W53', '2027-01-04': '2027-W01',
    '2024-02-29': '2024-W09', '2016-01-03': '2015-W53', '2015-12-31': '2015-W53',
  };
  for (const [date, wk] of Object.entries(cases)) assert.equal(isoWeek(date), wk, date);
  for (let t = Date.UTC(1990, 0, 1); t <= Date.UTC(2040, 11, 31); t += 86400000) {
    const dt = new Date(t);
    const iso = dt.toISOString().slice(0, 10);
    assert.equal(isoWeek(iso), oracle(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate()), iso);
  }
});

test('QA isoWeek rejects invalid dates and the 7 days of one week share a key', () => {
  for (const bad of ['2026-02-30', '2026-1-5', '', 'nope', '2026-01-05T00:00:00Z']) assert.throws(() => isoWeek(bad), TypeError, bad);
  const keys = new Set(['2024-12-30', '2024-12-31', '2025-01-01', '2025-01-02', '2025-01-03', '2025-01-04', '2025-01-05'].map(isoWeek));
  assert.deepEqual([...keys], ['2025-W01']);
});

test('QA countByWeek merges Dec/Jan boundary rows into one week and splits at Monday', () => {
  const rows = [ok({ date: '2025-12-29' }), ok({ date: '2026-01-04' }), ok({ date: '2026-01-05' })];
  assert.deepEqual({ ...countByWeek(rows) }, { '2026-W01': 2, '2026-W02': 1 });
  assert.throws(() => countByWeek([ok({ date: 'bogus' })]), TypeError);
  assert.deepEqual({ ...countByWeek([]) }, {});
  assert.deepEqual({ ...countByTypePerWeek([]) }, {});
});

test('QA countByDistrict handles unknown, missing and prototype-named districts without losing rows', () => {
  const rows = [ok(), ok({ district: 'Atlantis' }), { scam_type: 'OTP', date: '2026-01-05' },
    ok({ district: '__proto__' }), ok({ district: 'constructor' }), ok({ district: 'toString' }), ok({ district: 'toString' })];
  const c = countByDistrict(rows);
  assert.equal(Object.values(c).reduce((a, b) => a + b, 0), rows.length);
  assert.equal(c.Raipur, 1);
  assert.equal(c.Atlantis, 1);
  assert.equal(c.toString, 2);
  assert.equal(c.constructor, 1);
  assert.equal(Object.getPrototypeOf(c), null);
  assert.equal(({}).polluted, undefined);
  assert.deepEqual({ ...countByDistrict([]) }, {});
  assert.deepEqual({ ...countByScamType([ok(), ok({ scam_type: 'KYC' }), ok()]) }, { OTP: 2, KYC: 1 });
});

test('QA typeName known, unknown and underscore types', () => {
  assert.equal(typeName('OTP'), 'OTP');
  assert.equal(typeName('JOB'), 'Job offer');
  assert.equal(typeName('NEW_SCAM_TYPE'), 'New scam type');
  assert.equal(typeName('X'), 'X');
  assert.equal(typeName(''), '');
  for (const t of SCAM_TYPES) assert.equal(typeof typeName(t), 'string');
});

test('QA summarize empty input does not throw and reports zeros', () => {
  const s = summarize([]);
  assert.deepEqual([s.total, s.districts, s.types, s.weeks, s.series], [0, [], [], [], []]);
  const h = headline([]);
  assert.deepEqual([h.total, h.detected, h.share, h.unclassified, h.topType, h.delta], [0, 0, 0, 0, null, null]);
});

test('QA summarize folds types beyond the top 4 into Other types and conserves every row', () => {
  const types = ['OTP', 'OTP', 'OTP', 'KYC', 'KYC', 'JOB', 'LOAN_APP', 'FAKE_QR', 'INVESTMENT', 'OTHER'];
  const rows = types.map((scam_type, i) => ok({ scam_type, date: i < 5 ? '2026-01-05' : '2026-01-13' }));
  const s = summarize(rows);
  assert.equal(s.total, 10);
  assert.deepEqual(s.weeks, ['2026-W02', '2026-W03']);
  assert.equal(s.series.length, 5);
  assert.equal(s.series.at(-1).name, 'Other types');
  assert.equal(s.series.flatMap((x) => x.values).reduce((a, b) => a + b, 0), 10);
  assert.equal(s.series[0].key, 'OTP');
  assert.deepEqual(s.series[0].values, [3, 0]);
});

test('QA summarize with 4 or fewer types has no Other series; ranking ties break alphabetically', () => {
  const s = summarize([ok({ scam_type: 'KYC' }), ok({ scam_type: 'JOB' })]);
  assert.deepEqual(s.series.map((x) => x.key), ['JOB', 'KYC']);
  assert.deepEqual(s.types, [['JOB', 1], ['KYC', 1]]);
});

test('QA headline week-over-week delta, unclassified share and date range', () => {
  const rows = [ok({ date: '2026-01-05' }), ok({ date: '2026-01-13', scam_type: 'OTHER' }), ok({ date: '2026-01-14' }), ok({ date: '2026-01-15' })];
  const h = headline(rows);
  assert.deepEqual([h.total, h.detected, h.unclassified, h.delta], [4, 3, 1, 2]);
  assert.equal(h.share, 0.75);
  assert.deepEqual([h.from, h.to, h.lastWeek, h.lastCount], ['2026-01-05', '2026-01-15', '2026-W03', 3]);
  assert.equal(headline([ok()]).delta, null);
});
